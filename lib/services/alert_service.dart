import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import '../models/alert_settings.dart';
import '../models/units.dart';
import 'alert_engine.dart';

/// Turns [AlertEvent]s into sound, vibration and notifications, and tracks the
/// alarm currently sounding so the UI can offer a "Stop" button.
class AlertService extends ChangeNotifier {
  final _notifications = FlutterLocalNotificationsPlugin();

  AlertEvent? activeAlarm;
  DateTime? activeSince;
  Timer? _autoStop;
  int? _alarmId;
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

    if (a.vibrate) {
      try {
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(pattern: const [0, 600, 300, 600, 300, 600, 300, 1200]);
        }
      } catch (e) {
        debugPrint('Vibration failed: $e');
      }
    }

    // Sound is played by the notification itself, so it works with the screen
    // off. The alarm channel uses the phone's alarm tone on the alarm volume
    // stream and loops ("insistent") until the notification is cancelled.
    if (a.sound == AlertSound.none && !a.notify) return;
    final id = event.kind.index + 100;
    if (a.sound == AlertSound.alarm) {
      _alarmId = id;
      _autoStop?.cancel();
      _autoStop = Timer(Duration(seconds: alarmMaxSeconds), stop);
    }
    try {
      await _notifications.show(
        id: id,
        title: title(event.kind),
        body: body,
        notificationDetails: NotificationDetails(
          android: _androidDetails(a.sound),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: a.sound != AlertSound.none),
        ),
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }

  /// One channel per sound: Android fixes a channel's sound once created.
  static AndroidNotificationDetails _androidDetails(AlertSound sound) => switch (sound) {
        AlertSound.alarm => AndroidNotificationDetails(
            'alerts_alarm',
            'Pressure alarms',
            channelDescription: 'Looping alarm for high / low raft pressure',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
            audioAttributesUsage: AudioAttributesUsage.alarm,
            enableVibration: false, // vibration is handled separately
            additionalFlags: Int32List.fromList([_flagInsistent]),
          ),
        AlertSound.beep => const AndroidNotificationDetails(
            'alerts_beep',
            'Pressure alerts (beep)',
            channelDescription: 'Single notification sound',
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: false,
          ),
        AlertSound.none => const AndroidNotificationDetails(
            'alerts_silent',
            'Pressure alerts (silent)',
            channelDescription: 'Silent notifications',
            importance: Importance.high,
            priority: Priority.high,
            playSound: false,
            enableVibration: false,
          ),
      };

  /// android.app.Notification.FLAG_INSISTENT: repeat the sound until cancelled.
  static const _flagInsistent = 4;

  Future<void> stop() async {
    _autoStop?.cancel();
    _autoStop = null;
    activeAlarm = null;
    activeSince = null;
    notifyListeners();
    final id = _alarmId;
    _alarmId = null;
    try {
      if (id != null) await _notifications.cancel(id: id);
      await Vibration.cancel();
    } catch (_) {}
  }

  /// Plays an action set so the user can hear what it sounds like.
  Future<void> test(AlertActions actions, {required PressureUnit unit, required int alarmMaxSeconds}) =>
      fire(AlertEvent(AlertKind.high, null, actions),
          unit: unit, alarmMaxSeconds: alarmMaxSeconds.clamp(1, 5));

  @override
  void dispose() {
    _autoStop?.cancel();
    super.dispose();
  }
}
