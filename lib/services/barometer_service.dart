import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// The phone's own barometer, if it has one. Used as the ambient reference for
/// gauge pressure and as the target when hunting for the pressure bytes.
class BarometerService extends ChangeNotifier {
  StreamSubscription<BarometerEvent>? _sub;

  double? hpa;
  bool available = true;
  DateTime? _lastNotify;

  void start() {
    if (_sub != null) return;
    _sub = barometerEventStream(samplingPeriod: SensorInterval.normalInterval).listen(
      (e) {
        // Light smoothing; phone barometers are noisy at the 0.1 hPa level.
        hpa = hpa == null ? e.pressure : hpa! * 0.8 + e.pressure * 0.2;
        final now = DateTime.now();
        if (_lastNotify == null || now.difference(_lastNotify!) > const Duration(seconds: 1)) {
          _lastNotify = now;
          notifyListeners();
        }
      },
      onError: (Object _) {
        available = false;
        hpa = null;
        notifyListeners();
      },
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
