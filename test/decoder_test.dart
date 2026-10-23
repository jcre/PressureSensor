import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:raft_pressure/ble/adv_packet.dart';
import 'package:raft_pressure/ble/bthome.dart';
import 'package:raft_pressure/ble/decoder.dart';
import 'package:raft_pressure/ble/field_finder.dart';
import 'package:raft_pressure/ble/field_spec.dart';

AdvPacket packet({Map<String, List<int>> svc = const {}, Map<int, List<int>> mfr = const {}}) => AdvPacket(
      deviceId: 'AA:BB:CC:DD:EE:FF',
      name: 'Holy-IOT',
      rssi: -60,
      time: DateTime(2026),
      serviceData: svc,
      manufacturerData: mfr,
    );

/// uint24 little-endian Pa.
List<int> pa24(int pa) => [pa & 0xff, (pa >> 8) & 0xff, (pa >> 16) & 0xff];

void main() {
  group('AdvPacket', () {
    test('normalises 16-bit SIG UUIDs', () {
      expect(AdvPacket.normalizeUuid('0000FCD2-0000-1000-8000-00805F9B34FB'), 'fcd2');
      expect(AdvPacket.normalizeUuid('FCD2'), 'fcd2');
      final p = packet(svc: {'0000180a-0000-1000-8000-00805f9b34fb': [1, 2]});
      expect(p.bytesFor(AdSource.serviceData, '180A'), [1, 2]);
    });

    test('looks up manufacturer data by hex company id', () {
      final p = packet(mfr: {0xffff: [0x0b, 0xff]});
      expect(p.bytesFor(AdSource.manufacturerData, 'ffff'), [0x0b, 0xff]);
      expect(p.blocks.single.title, 'Manufacturer 0xffff');
    });
  });

  group('FieldSpec', () {
    final bytes = Uint8List.fromList([0x0b, 0xff, 0xdb, 0xff, 0xeb, 0x03]);

    test('reads signed little-endian int16 (Holyiot accelerometer sample)', () {
      const spec = FieldSpec(source: AdSource.manufacturerData, key: 'ffff', offset: 0, type: FieldType.sint);
      expect(spec.readBytes(bytes), -245);
      expect(spec.copyWith(offset: 4).readBytes(bytes), 1003);
    });

    test('reads big-endian and applies scale/add', () {
      const spec = FieldSpec(
          source: AdSource.serviceData, key: '5242', offset: 4, littleEndian: false, scale: 0.5, add: 10);
      expect(spec.readBytes(bytes), (0xeb03) * 0.5 + 10);
    });

    test('returns null when out of range', () {
      const spec = FieldSpec(source: AdSource.serviceData, key: 'x', offset: 5, length: 2);
      expect(spec.readBytes(bytes), isNull);
    });

    test('reads float32', () {
      final bd = ByteData(4)..setFloat32(0, 1013.5, Endian.little);
      const spec = FieldSpec(source: AdSource.serviceData, key: 'x', offset: 0, length: 4, type: FieldType.float32);
      expect(spec.readBytes(bd.buffer.asUint8List()), closeTo(1013.5, 1e-3));
    });

    test('round-trips through json', () {
      const spec = FieldSpec(
          source: AdSource.manufacturerData, key: '004c', offset: 3, length: 3, scale: 0.01, littleEndian: false);
      expect(FieldSpec.fromJson(spec.toJson()), spec);
    });
  });

  group('BTHome', () {
    test('decodes pressure, temperature and battery', () {
      final data = Uint8List.fromList([0x40, 0x01, 0x61, 0x02, 0xca, 0x09, 0x04, 0x13, 0x8a, 0x01]);
      final objs = BTHome.decode(data)!;
      expect(objs[0x01]!.first, 97);
      expect(objs[0x02]!.first, closeTo(25.06, 1e-9));
      expect(objs[0x04]!.first, closeTo(1008.83, 1e-9));
    });

    test('rejects encrypted payloads', () {
      expect(BTHome.decode(Uint8List.fromList([0x41, 0x01, 0x61])), isNull);
    });

    test('auto decoder picks up BTHome service data', () {
      final p = packet(svc: {'fcd2': [0x40, 0x04, 0x13, 0x8a, 0x01, 0x02, 0x0c, 0xfe]});
      final v = AdvDecoder.decode(p, const DecoderProfile());
      expect(v.pressureHpa, closeTo(1008.83, 1e-9));
      expect(v.temperatureC, closeTo(-5.0, 1e-9));
    });
  });

  group('custom profile', () {
    test('decodes configured fields', () {
      final p = packet(svc: {'5242': [0x41, 0x62, ...pa24(101325), 0xe8, 0x08]});
      const profile = DecoderProfile(
        kind: DecoderKind.custom,
        pressure: FieldSpec(source: AdSource.serviceData, key: '5242', offset: 2, length: 3, scale: 0.01),
        temperature:
            FieldSpec(source: AdSource.serviceData, key: '5242', offset: 5, type: FieldType.sint, scale: 0.01),
        battery: FieldSpec(source: AdSource.serviceData, key: '5242', offset: 1, length: 1),
      );
      final v = AdvDecoder.decode(p, profile);
      expect(v.pressureHpa, closeTo(1013.25, 1e-9));
      expect(v.temperatureC, closeTo(22.80, 1e-9));
      expect(v.batteryPct, 98);
      expect(DecoderProfile.fromJson(profile.toJson()).pressure, profile.pressure);
    });
  });

  group('FieldFinder', () {
    test('finds a uint24 Pa pressure field among noise', () {
      // MAC-like noise, battery, then pressure at offset 8, temp after.
      List<int> payload(int pa) => [0x41, 0x62, 0xf1, 0x31, 0xf5, 0xc2, 0x17, 0xba, ...pa24(pa), 0x10, 0x09];
      final packets = [
        packet(svc: {'5242': payload(101210)}),
        packet(svc: {'5242': payload(101230)}),
        packet(svc: {'5242': payload(101225)}),
      ];
      final found = FieldFinder.find(
        packets: packets,
        quantity: Quantity.pressure,
        target: 1013.0, // phone barometer reads a bit higher than the tag
        tolerance: 8,
      );
      expect(found, isNotEmpty);
      final best = found.first.spec;
      expect(best.offset, 8);
      expect(best.length, 3);
      expect(best.littleEndian, isTrue);
      expect(best.scale, 0.01);
      expect(found.first.value, closeTo(1012.25, 1e-9));
    });

    test('finds a big-endian 0.1 hPa field in manufacturer data', () {
      final p = packet(mfr: {0xffff: [0x00, 0x27, 0x95, 0x55]}); // 0x2795 = 10133
      final found = FieldFinder.find(packets: [p], quantity: Quantity.pressure, target: 1013.3, tolerance: 1);
      expect(found.first.spec.source, AdSource.manufacturerData);
      expect(found.first.spec.offset, 1);
      expect(found.first.spec.littleEndian, isFalse);
      expect(found.first.spec.scale, 0.1);
    });

    test('rejects fields that drift away from the target', () {
      final packets = [
        packet(svc: {'aaaa': pa24(101300)}),
        packet(svc: {'aaaa': pa24(120000)}),
      ];
      final found = FieldFinder.find(packets: packets, quantity: Quantity.pressure, target: 1013, tolerance: 5);
      expect(found.where((c) => c.spec.offset == 0 && c.spec.length == 3), isEmpty);
    });

    test('finds a temperature field', () {
      final p = packet(svc: {'aaaa': [0x01, 0xe8, 0x08]}); // 2280 → 22.80 °C
      final found = FieldFinder.find(packets: [p], quantity: Quantity.temperature, target: 22.8, tolerance: 0.5);
      expect(found.first.spec.offset, 1);
      expect(found.first.spec.scale, 0.01);
    });
  });
}
