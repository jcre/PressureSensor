import 'package:flutter_test/flutter_test.dart';
import 'package:raft_pressure/models/trip.dart';
import 'package:raft_pressure/models/units.dart';
import 'package:raft_pressure/services/gpx.dart';

void main() {
  final t0 = DateTime.utc(2026, 7, 1, 10);
  final readings = [
    Reading(time: t0, absHpa: 1100, gaugeHpa: 100),
    Reading(time: t0.add(const Duration(seconds: 60)), absHpa: 1090, gaugeHpa: 90),
  ];

  test('interpolates gauge pressure between readings', () {
    expect(gaugeAt(readings, t0.add(const Duration(seconds: 30))), closeTo(95, 1e-9));
    expect(gaugeAt(readings, t0.subtract(const Duration(seconds: 10))), 100);
    expect(gaugeAt(readings, t0.add(const Duration(hours: 1))), isNull);
  });

  test('exports and re-imports a GPX track with pressure', () {
    final track = [
      TrackPoint(time: t0, lat: 54.5, lon: -3.0, elevation: 100),
      TrackPoint(time: t0.add(const Duration(seconds: 30)), lat: 54.501, lon: -3.001),
    ];
    final trip = Trip(name: 'Ullswater', startedAt: t0);
    final xml = Gpx.export(trip, track, readings, PressureUnit.psi);
    expect(xml, contains('<rp:gauge_hpa>95.00</rp:gauge_hpa>'));
    expect(xml, contains('unit="psi"'));
    final back = Gpx.parse(xml);
    expect(back.length, 2);
    expect(back.first.lat, 54.5);
    expect(back.first.elevation, 100);
    expect(back.last.time.toUtc(), t0.add(const Duration(seconds: 30)));
  });

  test('track length', () {
    final pts = [
      TrackPoint(time: t0, lat: 0, lon: 0),
      TrackPoint(time: t0, lat: 0, lon: 1),
    ];
    expect(trackLengthMetres(pts), closeTo(111195, 10));
  });

  test('unit conversions', () {
    expect(PressureUnit.psi.fromHpa(68.9476), closeTo(1.0, 1e-4));
    expect(PressureUnit.bar.format(150), '0.150 bar');
    expect(PressureUnit.psi.toHpa(1.5), closeTo(103.42, 0.01));
  });
}
