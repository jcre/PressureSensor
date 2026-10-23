import 'package:flutter_test/flutter_test.dart';
import 'package:raft_pressure/models/alert_settings.dart';
import 'package:raft_pressure/services/alert_engine.dart';

void main() {
  const settings = AlertSettings(
    high: ThresholdAlert(enabled: true, thresholdHpa: 100, actions: AlertActions()),
    low: ThresholdAlert(enabled: true, thresholdHpa: 70, actions: AlertActions()),
    hysteresisHpa: 5,
    signalLostSeconds: 30,
  );

  List<AlertKind> feed(AlertEngine e, List<double> values) =>
      [for (final v in values) ...e.onGauge(v).map((a) => a.kind)];

  test('inflating from flat fires high once and never low', () {
    final e = AlertEngine(settings);
    final fired = feed(e, [0, 10, 40, 69, 71, 90, 99, 100, 101, 103, 99, 101]);
    expect(fired, [AlertKind.high]);
  });

  test('high re-arms after dropping below threshold - hysteresis', () {
    final e = AlertEngine(settings);
    expect(feed(e, [50, 100, 94, 100]), [AlertKind.high, AlertKind.high]);
  });

  test('slow leak fires low once', () {
    final e = AlertEngine(settings);
    final fired = feed(e, [105, 95, 80, 72, 70, 69, 71, 68, 60]);
    expect(fired, [AlertKind.low]);
  });

  test('low re-arms after re-inflating', () {
    final e = AlertEngine(settings);
    expect(feed(e, [90, 70, 76, 70]), [AlertKind.low, AlertKind.low]);
  });

  test('disabled alerts never fire', () {
    final e = AlertEngine(settings.copyWith(
      high: settings.high.copyWith(enabled: false),
      low: settings.low.copyWith(enabled: false),
    ));
    expect(feed(e, [0, 120, 0, 120]), isEmpty);
  });

  test('signal lost fires once until a reading arrives', () {
    final e = AlertEngine(settings);
    expect(e.onSilence(const Duration(seconds: 10)), isNull);
    expect(e.onSilence(const Duration(seconds: 31))?.kind, AlertKind.signalLost);
    expect(e.onSilence(const Duration(seconds: 60)), isNull);
    e.onGauge(80);
    expect(e.onSilence(const Duration(seconds: 31))?.kind, AlertKind.signalLost);
  });

  test('settings round-trip through json', () {
    final s = AlertSettings.fromJson(settings.toJson());
    expect(s.high.thresholdHpa, 100);
    expect(s.low.thresholdHpa, 70);
    expect(s.signalLostSeconds, 30);
  });
}
