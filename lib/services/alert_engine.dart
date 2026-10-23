import '../models/alert_settings.dart';

enum AlertKind { high, low, signalLost }

class AlertEvent {
  const AlertEvent(this.kind, this.gaugeHpa, this.actions);

  final AlertKind kind;
  final double? gaugeHpa;
  final AlertActions actions;
}

/// Pure threshold logic, kept free of Flutter so it can be unit-tested.
///
/// * High fires when pressure rises to the threshold, then re-arms once it
///   drops below threshold − hysteresis.
/// * Low only arms after pressure has been above threshold + hysteresis (so it
///   is quiet while inflating from flat), fires when pressure falls to the
///   threshold, then re-arms once it is back above threshold + hysteresis.
class AlertEngine {
  AlertEngine(this.settings);

  AlertSettings settings;

  bool _highArmed = false;
  bool _lowArmed = false;
  bool _signalLostFired = false;

  bool get highArmed => _highArmed;
  bool get lowArmed => _lowArmed;

  void reset() {
    _highArmed = false;
    _lowArmed = false;
    _signalLostFired = false;
  }

  /// Feed a new gauge reading; returns any alerts that should fire now.
  List<AlertEvent> onGauge(double gaugeHpa) {
    final events = <AlertEvent>[];
    final h = settings.hysteresisHpa;
    _signalLostFired = false;

    final high = settings.high;
    if (high.enabled) {
      if (gaugeHpa < high.thresholdHpa - h) {
        _highArmed = true;
      } else if (_highArmed && gaugeHpa >= high.thresholdHpa) {
        _highArmed = false;
        events.add(AlertEvent(AlertKind.high, gaugeHpa, high.actions));
      }
    }

    final low = settings.low;
    if (low.enabled) {
      if (gaugeHpa > low.thresholdHpa + h) {
        _lowArmed = true;
      } else if (_lowArmed && gaugeHpa <= low.thresholdHpa) {
        _lowArmed = false;
        events.add(AlertEvent(AlertKind.low, gaugeHpa, low.actions));
      }
    }
    return events;
  }

  /// Call periodically with the time since the last packet from the sensor.
  AlertEvent? onSilence(Duration sinceLastPacket) {
    if (!settings.signalLostEnabled || _signalLostFired) return null;
    if (sinceLastPacket.inSeconds >= settings.signalLostSeconds) {
      _signalLostFired = true;
      return AlertEvent(AlertKind.signalLost, null, settings.signalLost);
    }
    return null;
  }
}
