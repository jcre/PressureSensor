enum AlertSound {
  none('Silent'),
  beep('Short beep'),
  alarm('Continuous alarm');

  const AlertSound(this.label);

  final String label;

  static AlertSound byName(String? name) =>
      AlertSound.values.firstWhere((s) => s.name == name, orElse: () => AlertSound.alarm);
}

/// What happens when an alert fires.
class AlertActions {
  const AlertActions({this.sound = AlertSound.alarm, this.vibrate = true, this.notify = true});

  final AlertSound sound;
  final bool vibrate;
  final bool notify;

  AlertActions copyWith({AlertSound? sound, bool? vibrate, bool? notify}) => AlertActions(
        sound: sound ?? this.sound,
        vibrate: vibrate ?? this.vibrate,
        notify: notify ?? this.notify,
      );

  Map<String, dynamic> toJson() => {'sound': sound.name, 'vibrate': vibrate, 'notify': notify};

  factory AlertActions.fromJson(Map<String, dynamic>? j) => j == null
      ? const AlertActions()
      : AlertActions(
          sound: AlertSound.byName(j['sound'] as String?),
          vibrate: j['vibrate'] as bool? ?? true,
          notify: j['notify'] as bool? ?? true,
        );
}

/// A gauge-pressure threshold alert.
class ThresholdAlert {
  const ThresholdAlert({required this.enabled, required this.thresholdHpa, required this.actions});

  final bool enabled;

  /// Gauge pressure (above ambient), hPa.
  final double thresholdHpa;
  final AlertActions actions;

  ThresholdAlert copyWith({bool? enabled, double? thresholdHpa, AlertActions? actions}) => ThresholdAlert(
        enabled: enabled ?? this.enabled,
        thresholdHpa: thresholdHpa ?? this.thresholdHpa,
        actions: actions ?? this.actions,
      );

  Map<String, dynamic> toJson() => {'enabled': enabled, 'thresholdHpa': thresholdHpa, 'actions': actions.toJson()};

  factory ThresholdAlert.fromJson(Map<String, dynamic>? j, ThresholdAlert fallback) => j == null
      ? fallback
      : ThresholdAlert(
          enabled: j['enabled'] as bool? ?? fallback.enabled,
          thresholdHpa: (j['thresholdHpa'] as num?)?.toDouble() ?? fallback.thresholdHpa,
          actions: j['actions'] is Map
              ? AlertActions.fromJson(Map<String, dynamic>.from(j['actions'] as Map))
              : fallback.actions,
        );
}

class AlertSettings {
  const AlertSettings({
    this.high = const ThresholdAlert(
      enabled: true,
      thresholdHpa: 103.42, // 1.5 psi
      actions: AlertActions(sound: AlertSound.alarm),
    ),
    this.low = const ThresholdAlert(
      enabled: true,
      thresholdHpa: 68.95, // 1.0 psi
      actions: AlertActions(sound: AlertSound.alarm),
    ),
    this.hysteresisHpa = 6.89, // 0.1 psi
    this.signalLost = const AlertActions(sound: AlertSound.beep),
    this.signalLostEnabled = true,
    this.signalLostSeconds = 60,
    this.alarmMaxSeconds = 30,
  });

  /// "Fully inflated" alert: fires when gauge pressure rises to the threshold.
  final ThresholdAlert high;

  /// "Losing air" alert: fires when gauge pressure falls to the threshold.
  /// Only armed once pressure has been above it, so it stays quiet while
  /// inflating from flat.
  final ThresholdAlert low;

  /// Pressure must move back this far past a threshold before that alert can
  /// fire again. Stops sensor noise from repeatedly triggering.
  final double hysteresisHpa;

  final bool signalLostEnabled;
  final int signalLostSeconds;
  final AlertActions signalLost;

  /// A continuous alarm stops itself after this long.
  final int alarmMaxSeconds;

  AlertSettings copyWith({
    ThresholdAlert? high,
    ThresholdAlert? low,
    double? hysteresisHpa,
    bool? signalLostEnabled,
    int? signalLostSeconds,
    AlertActions? signalLost,
    int? alarmMaxSeconds,
  }) =>
      AlertSettings(
        high: high ?? this.high,
        low: low ?? this.low,
        hysteresisHpa: hysteresisHpa ?? this.hysteresisHpa,
        signalLostEnabled: signalLostEnabled ?? this.signalLostEnabled,
        signalLostSeconds: signalLostSeconds ?? this.signalLostSeconds,
        signalLost: signalLost ?? this.signalLost,
        alarmMaxSeconds: alarmMaxSeconds ?? this.alarmMaxSeconds,
      );

  Map<String, dynamic> toJson() => {
        'high': high.toJson(),
        'low': low.toJson(),
        'hysteresisHpa': hysteresisHpa,
        'signalLostEnabled': signalLostEnabled,
        'signalLostSeconds': signalLostSeconds,
        'signalLost': signalLost.toJson(),
        'alarmMaxSeconds': alarmMaxSeconds,
      };

  factory AlertSettings.fromJson(Map<String, dynamic> j) {
    const d = AlertSettings();
    Map<String, dynamic>? m(String k) => j[k] is Map ? Map<String, dynamic>.from(j[k] as Map) : null;
    return AlertSettings(
      high: ThresholdAlert.fromJson(m('high'), d.high),
      low: ThresholdAlert.fromJson(m('low'), d.low),
      hysteresisHpa: (j['hysteresisHpa'] as num?)?.toDouble() ?? d.hysteresisHpa,
      signalLostEnabled: j['signalLostEnabled'] as bool? ?? d.signalLostEnabled,
      signalLostSeconds: (j['signalLostSeconds'] as num?)?.toInt() ?? d.signalLostSeconds,
      signalLost: m('signalLost') == null ? d.signalLost : AlertActions.fromJson(m('signalLost')),
      alarmMaxSeconds: (j['alarmMaxSeconds'] as num?)?.toInt() ?? d.alarmMaxSeconds,
    );
  }
}
