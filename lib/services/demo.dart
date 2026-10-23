import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ble/adv_packet.dart';
import '../models/sensor_config.dart';
import '../models/trip.dart';
import 'barometer_service.dart';
import 'ble_scanner.dart';
import 'settings_store.dart';

/// A simulated raft sensor so the app can be tried without hardware.
///
/// Timeline: ~10 s flat, ~60 s of pump strokes up to ≈1.6 psi (the high
/// alert fires on the way), then a paddle where pressure breathes with a
/// warm/cool cycle and, after two minutes, a slow leak sets off the low alert.
class DemoSimulation {
  static const deviceId = 'DE:MO:00:00:00:01';
  static const name = 'Demo raft sensor';
  static const ambientHpa = 1013.25;

  static const _inflateStart = 10.0;
  static const _inflateEnd = 70.0;
  static const _fullHpa = 112.0;
  static const _leakAfter = 120.0;
  static const _leakHpaPerSec = 0.1;

  static double gaugeHpa(Duration elapsed) {
    final t = elapsed.inMilliseconds / 1000.0;
    final noise = 0.15 * math.sin(t * 7.3) + 0.1 * math.sin(t * 13.1);
    double g;
    if (t < _inflateStart) {
      g = 0;
    } else if (t < _inflateEnd) {
      final p = (t - _inflateStart) / (_inflateEnd - _inflateStart);
      final strokes = 3 * math.max(0, math.sin(2 * math.pi * (t - _inflateStart) / 2.5)) * p;
      g = _fullHpa * (1 - math.pow(1 - p, 1.6)) + strokes;
    } else {
      final u = t - _inflateEnd;
      final leak = u > _leakAfter ? (u - _leakAfter) * _leakHpaPerSec : 0.0;
      g = _fullHpa - leak + 5 * math.sin(2 * math.pi * u / 300);
    }
    return math.max(0, g + noise);
  }

  static double temperatureC(Duration elapsed) {
    final t = elapsed.inMilliseconds / 1000.0;
    final u = math.max(0, t - _inflateEnd);
    return 16 + 3 * math.sin(2 * math.pi * u / 300);
  }

  /// BTHome v2 service data (decoded automatically) plus a Holyiot-style
  /// manufacturer block, so the field finder can be tried on it too.
  static AdvPacket packet(Duration elapsed, DateTime now) {
    final pa = ((ambientHpa + gaugeHpa(elapsed)) * 100).round();
    final temp = (temperatureC(elapsed) * 100).round() & 0xffff;
    final pressure24 = [pa & 0xff, (pa >> 8) & 0xff, (pa >> 16) & 0xff];
    final temp16 = [temp & 0xff, (temp >> 8) & 0xff];
    return AdvPacket(
      deviceId: deviceId,
      name: name,
      rssi: -55 + (3 * math.sin(elapsed.inSeconds / 3)).round(),
      time: now,
      serviceData: {
        'fcd2': [0x40, 0x01, 87, 0x02, ...temp16, 0x04, ...pressure24],
      },
      manufacturerData: {
        0xffff: [0x41, 87, 0xd8, 0xf8, 0x41, 0xda, 0xce, 0xf9, ...pressure24, ...temp16],
      },
    );
  }

  /// A paddle round a loop on Ullswater at ~1.3 m/s.
  static TrackPoint position(Duration elapsed, DateTime now) {
    const lat0 = 54.5745;
    const lon0 = -2.8790;
    const radius = 450.0;
    final s = 1.3 * elapsed.inMilliseconds / 1000.0;
    final theta = s / radius;
    final wiggle = 12 * math.sin(s / 37);
    final north = (radius + wiggle) * math.sin(theta);
    final east = (radius + wiggle) * (1 - math.cos(theta));
    return TrackPoint(
      time: now,
      lat: lat0 + north / 111320,
      lon: lon0 + east / (111320 * math.cos(lat0 * math.pi / 180)),
      elevation: 145,
      speed: 1.3,
      accuracy: 5,
    );
  }
}

/// Runs [DemoSimulation] while demo mode is on, feeding packets into the
/// scanner exactly as real advertisements would arrive.
class DemoController extends ChangeNotifier {
  DemoController({required this.settings, required this.scanner, required this.barometer}) {
    settings.addListener(_sync);
    _sync();
  }

  final SettingsStore settings;
  final BleScanner scanner;
  final BarometerService barometer;

  Timer? _timer;
  DateTime _start = DateTime.now();

  bool get running => _timer != null;
  Duration get elapsed => DateTime.now().difference(_start);

  void _sync() {
    if (settings.demoMode && _timer == null) {
      _start = DateTime.now();
      var ticks = 0;
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        scanner.inject(DemoSimulation.packet(elapsed, DateTime.now()));
        if (++ticks % 4 == 0) notifyListeners(); // refresh the phase label
      });
      notifyListeners();
    } else if (!settings.demoMode && _timer != null) {
      _timer?.cancel();
      _timer = null;
      notifyListeners();
    }
  }

  /// Turns demo mode on: adds the simulated sensor (already zeroed) and makes
  /// it active. Turning it off restores the previously active sensor.
  Future<void> setEnabled(bool on) async {
    if (on == settings.demoMode) return;
    if (on) {
      final phone = barometer.hpa;
      await settings.update((s) {
        s.demoPreviousSensorId = s.activeSensorId;
        s.sensors.removeWhere((x) => x.id == DemoSimulation.deviceId);
        s.sensors.add(SensorConfig(
          id: DemoSimulation.deviceId,
          name: DemoSimulation.name,
          zeroHpa: DemoSimulation.ambientHpa,
          phoneOffsetHpa: phone == null ? 0 : DemoSimulation.ambientHpa - phone,
        ));
        s.activeSensorId = DemoSimulation.deviceId;
        s.demoMode = true;
      });
    } else {
      await settings.update((s) {
        s.sensors.removeWhere((x) => x.id == DemoSimulation.deviceId);
        final prev = s.demoPreviousSensorId;
        s.activeSensorId = s.sensors.any((x) => x.id == prev) ? prev : s.sensors.firstOrNull?.id;
        s.demoPreviousSensorId = null;
        s.demoMode = false;
      });
    }
  }

  /// Starts the inflate → paddle → leak story again ([at] skips ahead).
  void restart({Duration at = Duration.zero}) {
    _start = DateTime.now().subtract(at);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    settings.removeListener(_sync);
    super.dispose();
  }
}
