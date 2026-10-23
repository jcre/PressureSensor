import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_settings.dart';
import '../models/sensor_config.dart';
import '../models/units.dart';

/// All user settings, persisted as JSON in shared preferences.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs);

  static const _key = 'settings_v1';

  final SharedPreferences _prefs;

  PressureUnit unit = PressureUnit.psi;
  PressureDisplay display = PressureDisplay.gauge;
  ReferenceMode referenceMode = ReferenceMode.capturedZero;

  /// How often a reading is written to a trip (the live view shows them all).
  int recordIntervalSec = 2;
  bool gpsEnabled = true;
  bool keepScreenOn = true;

  /// Width of the live chart window.
  int liveWindowMinutes = 5;

  AlertSettings alerts = const AlertSettings();
  List<SensorConfig> sensors = [];
  String? activeSensorId;

  /// Simulated sensor + GPS instead of real hardware.
  bool demoMode = false;

  /// Sensor that was active before demo mode was switched on.
  String? demoPreviousSensorId;

  SensorConfig? get activeSensor {
    for (final s in sensors) {
      if (s.id == activeSensorId) return s;
    }
    return null;
  }

  static Future<SettingsStore> load() async {
    final store = SettingsStore._(await SharedPreferences.getInstance());
    final raw = store._prefs.getString(_key);
    if (raw != null) {
      try {
        store._fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('Ignoring unreadable settings: $e');
      }
    }
    return store;
  }

  void _fromJson(Map<String, dynamic> j) {
    unit = PressureUnit.byName(j['unit'] as String?);
    display = (j['display'] as String?) == 'absolute' ? PressureDisplay.absolute : PressureDisplay.gauge;
    referenceMode = ReferenceMode.byName(j['referenceMode'] as String?);
    recordIntervalSec = (j['recordIntervalSec'] as num?)?.toInt() ?? recordIntervalSec;
    gpsEnabled = j['gpsEnabled'] as bool? ?? gpsEnabled;
    keepScreenOn = j['keepScreenOn'] as bool? ?? keepScreenOn;
    liveWindowMinutes = (j['liveWindowMinutes'] as num?)?.toInt() ?? liveWindowMinutes;
    if (j['alerts'] is Map) alerts = AlertSettings.fromJson(Map<String, dynamic>.from(j['alerts'] as Map));
    sensors = [
      for (final s in (j['sensors'] as List? ?? const []))
        SensorConfig.fromJson(Map<String, dynamic>.from(s as Map)),
    ];
    activeSensorId = j['activeSensorId'] as String?;
    demoMode = j['demoMode'] as bool? ?? false;
    demoPreviousSensorId = j['demoPreviousSensorId'] as String?;
  }

  Map<String, dynamic> _toJson() => {
        'unit': unit.name,
        'display': display.name,
        'referenceMode': referenceMode.name,
        'recordIntervalSec': recordIntervalSec,
        'gpsEnabled': gpsEnabled,
        'keepScreenOn': keepScreenOn,
        'liveWindowMinutes': liveWindowMinutes,
        'alerts': alerts.toJson(),
        'sensors': [for (final s in sensors) s.toJson()],
        'activeSensorId': activeSensorId,
        'demoMode': demoMode,
        'demoPreviousSensorId': demoPreviousSensorId,
      };

  /// Apply a change and persist it.
  Future<void> update(void Function(SettingsStore s) change) async {
    change(this);
    notifyListeners();
    await _prefs.setString(_key, jsonEncode(_toJson()));
  }

  Future<void> upsertSensor(SensorConfig config, {bool makeActive = false}) => update((s) {
        final i = s.sensors.indexWhere((x) => x.id == config.id);
        if (i >= 0) {
          s.sensors[i] = config;
        } else {
          s.sensors.add(config);
        }
        if (makeActive) s.activeSensorId = config.id;
      });

  Future<void> removeSensor(String id) => update((s) {
        s.sensors.removeWhere((x) => x.id == id);
        if (s.activeSensorId == id) s.activeSensorId = s.sensors.isEmpty ? null : s.sensors.first.id;
      });
}
