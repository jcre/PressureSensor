import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';

import '../models/alert_settings.dart';
import '../models/units.dart';
import 'alert_engine.dart';

/// Turns [AlertEvent]s into sound, vibration and notifications, and tracks the
/// alarm currently sounding so the UI can offer a "Stop" button.
class AlertService extends ChangeNotifier {
  final _notifications = FlutterLocalNotificationsPlugin();
  final _ringtone = FlutterRingtonePlayer();

  AlertEvent? activeAlarm;
  DateTime? activeSince;
  Timer? _autoStop;
  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  Future<void> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        await _notifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _notifications
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true);
      }
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
  }

  static String title(AlertKind kind) => switch (kind) {
        AlertKind.high => 'Raft pressure reached',
        AlertKind.low => 'Raft pressure low',
        AlertKind.signalLost => 'Sensor signal lost',
      };

  Future<void> fire(AlertEvent event, {required PressureUnit unit, required int alarmMaxSeconds}) async {
    final a = event.actions;
    final body = event.gaugeHpa == null
        ? 'No readings received from the pressure sensor.'
        : 'Gauge pressure ${unit.format(event.gaugeHpa!)}';

    if (a.sound == AlertSound.alarm || a.vibrate) {
      activeAlarm = event;
      activeSince = DateTime.now();
      notifyListeners();
    }

    try {
      switch (a.sound) {
        case AlertSound.none:
          break;
        case AlertSound.beep:
          await _ringtone.playNotification(asAlarm: true);
        case AlertSound.alarm:
          await _ringtone.playAlarm(looping: true, asAlarm: true);
          _autoStop?.cancel();
          _autoStop = Timer(Duration(seconds: alarmMaxSeconds), stop);
      }
    } catch (e) {
      debugPrint('Sound failed: $e');
    }

    if (a.vibrate) {
      try {
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(pattern: const [0, 600, 300, 600, 300, 600, 300, 1200]);
        }
      } catch (e) {
        debugPrint('Vibration failed: $e');
      }
    }

    if (a.notify) {
      try {
        await _notifications.show(
          id: event.kind.index + 100,
          title: title(event.kind),
          body: body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'alerts',
              'Pressure alerts',
              channelDescription: 'High / low raft pressure and lost-sensor alerts',
              importance: Importance.max,
              priority: Priority.high,
              // Our own sound/vibration handles the noise; keep the notification quiet
              // so it doesn't double up.
              playSound: false,
              enableVibration: false,
              category: AndroidNotificationCategory.alarm,
            ),
            iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: false),
          ),
        );
      } catch (e) {
        debugPrint('Notification failed: $e');
      }
    }
  }

  Future<void> stop() async {
    _autoStop?.cancel();
    _autoStop = null;
    activeAlarm = null;
    activeSince = null;
    notifyListeners();
    try {
      await _ringtone.stop();
      await Vibration.cancel();
    } catch (_) {}
  }

  /// Plays an action set so the user can hear what it sounds like.
  Future<void> test(AlertActions actions, {required PressureUnit unit, required int alarmMaxSeconds}) =>
      fire(AlertEvent(AlertKind.high, null, actions.copyWith(notify: false)),
          unit: unit, alarmMaxSeconds: alarmMaxSeconds.clamp(1, 5));

  @override
  void dispose() {
    _autoStop?.cancel();
    super.dispose();
  }
}
