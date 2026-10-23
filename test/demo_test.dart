import 'package:flutter_test/flutter_test.dart';
import 'package:raft_pressure/ble/decoder.dart';
import 'package:raft_pressure/ble/field_finder.dart';
import 'package:raft_pressure/models/alert_settings.dart';
import 'package:raft_pressure/models/trip.dart';
import 'package:raft_pressure/services/alert_engine.dart';
import 'package:raft_pressure/services/demo.dart';

void main() {
  Duration s(num secs) => Duration(milliseconds: (secs * 1000).round());

  test('demo packets decode automatically via BTHome', () {
    final p = DemoSimulation.packet(s(5), DateTime(2026));
    final v = AdvDecoder.decode(p, const DecoderProfile());
    expect(v.pressureHpa, closeTo(DemoSimulation.ambientHpa, 0.5));
    expect(v.temperatureC, closeTo(16, 0.01));
    expect(v.batteryPct, 87);
  });

  test('field finder locates pressure in the demo manufacturer block', () {
    final packets = [for (var t = 0; t < 5; t++) DemoSimulation.packet(s(t), DateTime(2026))];
    final found = FieldFinder.find(packets: packets, quantity: Quantity.pressure, target: 1013.0, tolerance: 2);
    final mfr = found.where((c) => c.spec.key == 'ffff').first.spec;
    expect(mfr.offset, 8);
    expect(mfr.length, 3);
  });

  test('demo timeline triggers high while inflating, then low after the leak', () {
    final engine = AlertEngine(const AlertSettings());
    final fired = <(AlertKind, double)>[];
    for (var t = 0.0; t < 1200; t += 0.5) {
      final abs = AdvDecoder.decode(DemoSimulation.packet(s(t), DateTime(2026)), const DecoderProfile()).pressureHpa!;
      for (final e in engine.onGauge(abs - DemoSimulation.ambientHpa)) {
        fired.add((e.kind, t));
      }
    }
    expect(fired.map((f) => f.$1), [AlertKind.high, AlertKind.low]);
    expect(fired.first.$2, inInclusiveRange(40, 70));
    expect(fired.last.$2, lessThan(900));
  });

  test('demo GPS loop moves at paddling speed', () {
    final pts = [for (var t = 0; t <= 600; t += 2) DemoSimulation.position(s(t), DateTime(2026).add(s(t)))];
    final km = trackLengthMetres(pts) / 1000;
    expect(km, closeTo(0.78, 0.1)); // 1.3 m/s for 10 minutes
  });
}
