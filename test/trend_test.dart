import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:raft_pressure/ble/adv_packet.dart';
import 'package:raft_pressure/ble/decoder.dart';
import 'package:raft_pressure/ble/field_spec.dart';
import 'package:raft_pressure/ble/known_layouts.dart';
import 'package:raft_pressure/ble/trend_analysis.dart';

const mac = 'BA:17:C2:F5:31:F1';

AdvPacket pkt(DateTime t, List<int> holy, {List<int>? nex}) => AdvPacket(
      deviceId: mac,
      name: 'Holy-IOT',
      rssi: -60,
      time: t,
      serviceData: {'5242': holy, '180a': ?nex},
    );

void main() {
  group('KnownLayouts', () {
    test('Holyiot battery at byte 1 (Tasmota sample)', () {
      final p = pkt(DateTime(2026), [0x41, 0x62, 0xF1, 0x31, 0xF5, 0xC2, 0x17, 0xBA, 0x06, 0x06, 0x02, 0x58, 0xC5]);
      expect(KnownLayouts.battery(p), 98);
      expect(AdvDecoder.decode(p, const DecoderProfile()).batteryPct, 98);
      final labels = KnownLayouts.annotate(p)['serviceData:5242']!;
      expect(labels[1], 'batt');
      expect([for (var i = 2; i <= 7; i++) labels[i]], everyElement('MAC'));
    });

    test('NexBeacon Pro battery in last byte of 0x180A (ble_monitor sample)', () {
      final p = AdvPacket(
        deviceId: 'D8:F8:41:DA:CE:F9',
        name: 'NexBeacon Pro',
        rssi: -60,
        time: DateTime(2026),
        serviceData: {'0000180a-0000-1000-8000-00805f9b34fb': [0x03, 0xf9, 0xce, 0xda, 0x41, 0xf8, 0xd8, 0x04, 0x5a]},
      );
      expect(KnownLayouts.battery(p), 90);
      final labels = KnownLayouts.annotate(p)['serviceData:180a']!;
      expect(labels[8], 'batt');
      expect(labels[1], 'MAC');
    });

    test('0xFF battery means unknown', () {
      expect(KnownLayouts.battery(pkt(DateTime(2026), [0x41, 0xff])), isNull);
    });

    test('custom profile still gets known battery', () {
      final p = pkt(DateTime(2026), [0x41, 0x50, 0x00, 0x10]);
      const profile = DecoderProfile(
        kind: DecoderKind.custom,
        pressure: FieldSpec(source: AdSource.serviceData, key: '5242', offset: 2, length: 2),
      );
      expect(AdvDecoder.decode(p, profile).batteryPct, 80);
    });
  });

  group('TrendAnalysis', () {
    // 5 minutes at 2 Hz: temperature drifts up, pressure gets squeezed,
    // a random byte jitters, a packet counter wraps.
    final rnd = math.Random(1);
    final t0 = DateTime(2026);
    final packets = <AdvPacket>[];
    for (var i = 0; i < 600; i++) {
      final temp = 2100 + (i * 200 / 600).round() + rnd.nextInt(3) - 1; // 21.00 → 23.00 °C
      final squeeze = i > 300 && i < 360 ? 4000 : 0;
      final pa = 101300 + squeeze + rnd.nextInt(5);
      packets.add(pkt(t0.add(Duration(milliseconds: 500 * i)), [
        0x41, 0x62, 0xF1, 0x31, 0xF5, 0xC2, 0x17, 0xBA, // header, batt, MAC
        temp & 0xff, temp >> 8, // s16 LE @8
        pa & 0xff, (pa >> 8) & 0xff, pa >> 16, // u24 LE @10
        rnd.nextInt(256), // noise @13
        i & 0xff, // counter @14
      ]));
    }

    test('smooth sort surfaces temperature and pressure, skips known bytes', () {
      final fields = TrendAnalysis.analyze(packets);
      final top = fields.take(3).map((f) => (f.spec.offset, f.spec.length)).toList();
      expect(top, containsAll([(8, 2), (10, 3)]));
      final temp = fields.firstWhere((f) => f.spec.offset == 8);
      expect(temp.spec.littleEndian, isTrue);
      expect(temp.first, closeTo(2100, 2));
      expect(temp.last, closeTo(2300, 2));
      final pressure = fields.firstWhere((f) => f.spec.offset == 10);
      expect(pressure.max - pressure.min, greaterThan(3990));
      expect(fields.any((f) => f.spec.offset < 8), isFalse, reason: 'battery/MAC bytes are known');
    });

    test('noise ranks below real signals', () {
      final fields = TrendAnalysis.analyze(packets);
      final noise = fields.indexWhere((f) => f.spec.offset == 13 && f.spec.length == 1);
      final temp = fields.indexWhere((f) => f.spec.offset == 8);
      expect(noise, anyOf(-1, greaterThan(temp)));
    });

    test('range sort works and constant data yields nothing', () {
      expect(TrendAnalysis.analyze(packets, sort: TrendSort.range), isNotEmpty);
      final flat = [for (var i = 0; i < 10; i++) pkt(t0.add(Duration(seconds: i)), [1, 2, 3, 4])];
      expect(TrendAnalysis.analyze(flat), isEmpty);
    });
  });
}
