import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/adv_packet.dart';
import '../ble/decoder.dart';
import '../models/sensor_config.dart';
import '../models/trip.dart';
import '../models/units.dart';
import 'alert_engine.dart';
import 'alert_service.dart';
import 'barometer_service.dart';
import 'ble_scanner.dart';
import 'settings_store.dart';

enum LinkState {
  /// No sensor chosen yet.
  noSensor,

  /// Waiting for the first advertisement.
  searching,

  /// Packets arrive but the decoder finds no pressure in them.
  undecoded,

  /// Fresh readings.
  live,

  /// Readings stopped arriving.
  stale,
}

/// Follows the active sensor: decodes its advertisements, converts them to
/// gauge pressure, keeps a rolling history for the live chart and drives the
/// alerts.
class LiveMonitor extends ChangeNotifier {
  LiveMonitor({
    required this.scanner,
    required this.settings,
    required this.barometer,
    required this.alerts,
  }) {
    _engine = AlertEngine(settings.alerts);
    _packetSub = scanner.packets.listen(_onPacket);
    settings.addListener(_onSettings);
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _onTick());
    _onSettings();
  }

  final BleScanner scanner;
  final SettingsStore settings;
  final BarometerService barometer;
  final AlertService alerts;

  late final AlertEngine _engine;
  StreamSubscription<AdvPacket>? _packetSub;
  Timer? _tick;
  String? _sensorId;

  static const historyLimit = Duration(hours: 12);

  /// Downsampled to ≤1 reading per second.
  final List<Reading> history = [];
  Reading? latest;
  AdvPacket? latestPacket;
  DateTime? lastPacketAt;
  final _readings = StreamController<Reading>.broadcast();

  /// Every decoded reading (not downsampled).
  Stream<Reading> get readings => _readings.stream;

  SensorConfig? get sensor => settings.activeSensor;

  LinkState get state {
    if (sensor == null) return LinkState.noSensor;
    if (lastPacketAt == null) return LinkState.searching;
    final age = DateTime.now().difference(lastPacketAt!);
    if (age > const Duration(seconds: 15)) return LinkState.stale;
    if (latest == null || DateTime.now().difference(latest!.time) > const Duration(seconds: 15)) {
      return LinkState.undecoded;
    }
    return LinkState.live;
  }

  /// Ambient pressure used to turn absolute into gauge pressure, or null if it
  /// isn't known yet (e.g. never zeroed).
  double? get referenceHpa {
    final s = sensor;
    switch (settings.referenceMode) {
      case ReferenceMode.capturedZero:
        return s?.zeroHpa;
      case ReferenceMode.phoneBarometer:
        final phone = barometer.hpa;
        if (phone == null) return s?.zeroHpa;
        return phone + (s?.phoneOffsetHpa ?? 0);
      case ReferenceMode.standardAtmosphere:
        return kStandardAtmosphereHpa;
    }
  }

  bool get needsZero => settings.referenceMode != ReferenceMode.standardAtmosphere && sensor?.zeroHpa == null;

  void _onSettings() {
    _engine.settings = settings.alerts;
    final id = settings.activeSensorId;
    if (id != _sensorId) {
      _sensorId = id;
      history.clear();
      latest = null;
      latestPacket = null;
      lastPacketAt = null;
      _engine.reset();
      scanner.monitor(id);
      notifyListeners();
    }
  }

  void _onPacket(AdvPacket p) {
    final s = sensor;
    if (s == null || p.deviceId != s.id) return;
    latestPacket = p;
    lastPacketAt = p.time;

    final values = AdvDecoder.decode(p, s.profile);
    final abs = values.pressureHpa;
    if (abs == null) {
      _throttledNotify();
      return;
    }
    final ref = referenceHpa ?? abs; // un-zeroed: show 0 until the user zeroes
    final reading = Reading(
      time: p.time,
      absHpa: abs,
      gaugeHpa: abs - ref,
      temperatureC: values.temperatureC,
      batteryPct: values.batteryPct,
      rssi: p.rssi,
    );
    latest = reading;
    _readings.add(reading);

    if (history.isEmpty || reading.time.difference(history.last.time) >= const Duration(seconds: 1)) {
      history.add(reading);
      final cutoff = reading.time.subtract(historyLimit);
      while (history.isNotEmpty && history.first.time.isBefore(cutoff)) {
        history.removeAt(0);
      }
    }

    if (referenceHpa != null) {
      for (final e in _engine.onGauge(reading.gaugeHpa)) {
        alerts.fire(e, unit: settings.unit, alarmMaxSeconds: settings.alerts.alarmMaxSeconds);
      }
    }
    _throttledNotify();
  }

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  void _throttledNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) >= const Duration(milliseconds: 250)) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  void _onTick() {
    if (sensor == null) return;
    // Only "lost" once we've actually heard from it.
    final last = lastPacketAt;
    final e = last == null ? null : _engine.onSilence(DateTime.now().difference(last));
    if (e != null) alerts.fire(e, unit: settings.unit, alarmMaxSeconds: settings.alerts.alarmMaxSeconds);
    notifyListeners(); // refresh "x s ago" and link state
  }

  void clearHistory() {
    history.clear();
    _engine.reset();
    notifyListeners();
  }

  /// Captures the current reading as ambient: do this with the valve open /
  /// before sealing the sensor in the raft.
  Future<bool> zero() async {
    final s = sensor;
    final r = latest;
    if (s == null || r == null) return false;
    final phone = barometer.hpa;
    await settings.upsertSensor(s.copyWith(
      zeroHpa: r.absHpa,
      phoneOffsetHpa: phone == null ? s.phoneOffsetHpa : r.absHpa - phone,
    ));
    _engine.reset();
    history.clear();
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    _tick?.cancel();
    settings.removeListener(_onSettings);
    _readings.close();
    super.dispose();
  }
}
