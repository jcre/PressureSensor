import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/trip.dart';
import 'database.dart';
import 'demo.dart';
import 'live_monitor.dart';
import 'settings_store.dart';

/// Records a trip: sensor readings (at the configured interval) plus the GPS
/// track. On Android the GPS stream runs as a foreground service, which also
/// keeps the app (and its BLE scan) alive with the screen off.
class TripRecorder extends ChangeNotifier {
  TripRecorder({required this.db, required this.monitor, required this.settings});

  final TripDatabase db;
  final LiveMonitor monitor;
  final SettingsStore settings;

  Trip? trip;
  bool get recording => trip != null;

  /// Points recorded so far this trip, for the live distance readout.
  final List<TrackPoint> track = [];
  int readingCount = 0;
  double distanceMetres = 0;
  String? gpsError;

  StreamSubscription<Reading>? _readingSub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _demoGps;
  Timer? _flushTimer;
  final List<Reading> _pendingReadings = [];
  final List<TrackPoint> _pendingPoints = [];
  DateTime? _lastRecorded;

  Future<void> start(String name) async {
    if (recording) return;
    final s = monitor.sensor;
    trip = await db.insertTrip(Trip(
      name: name,
      startedAt: DateTime.now(),
      sensorId: s?.id,
      sensorName: s?.name,
    ));
    track.clear();
    readingCount = 0;
    distanceMetres = 0;
    gpsError = null;
    _lastRecorded = null;

    _readingSub = monitor.readings.listen(_onReading);
    _flushTimer = Timer.periodic(const Duration(seconds: 10), (_) => _flush());
    if (settings.gpsEnabled) {
      if (settings.demoMode) {
        final t0 = DateTime.now();
        _demoGps = Timer.periodic(const Duration(seconds: 2), (_) {
          final now = DateTime.now();
          _addPoint(DemoSimulation.position(now.difference(t0), now));
        });
      } else {
        await _startGps();
      }
    }
    notifyListeners();
  }

  void _onReading(Reading r) {
    final last = _lastRecorded;
    if (last != null && r.time.difference(last).inMilliseconds < settings.recordIntervalSec * 1000 - 100) return;
    _lastRecorded = r.time;
    _pendingReadings.add(r);
    readingCount++;
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        gpsError = 'Location services are off – recording pressure only';
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        gpsError = 'Location permission denied – recording pressure only';
        return;
      }
      final LocationSettings locSettings;
      if (Platform.isAndroid) {
        locSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 2),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Recording trip',
            notificationText: 'Logging raft pressure and GPS track',
            notificationChannelName: 'Trip recording',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      } else if (Platform.isIOS) {
        locSettings = AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locSettings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
      }
      _gpsSub = Geolocator.getPositionStream(locationSettings: locSettings).listen(
        _onPosition,
        onError: (Object e) {
          gpsError = 'GPS error: $e';
          notifyListeners();
        },
      );
    } catch (e) {
      gpsError = 'GPS unavailable: $e';
    }
  }

  void _onPosition(Position p) {
    // Skip wildly inaccurate fixes (e.g. first fix indoors).
    if (p.accuracy > 50) return;
    _addPoint(TrackPoint(
      time: p.timestamp,
      lat: p.latitude,
      lon: p.longitude,
      elevation: p.altitude,
      speed: p.speed,
      accuracy: p.accuracy,
    ));
  }

  void _addPoint(TrackPoint pt) {
    if (track.isNotEmpty) {
      distanceMetres += haversineMetres(track.last.lat, track.last.lon, pt.lat, pt.lon);
    }
    track.add(pt);
    _pendingPoints.add(pt);
    notifyListeners();
  }

  Future<void> _flush() async {
    final id = trip?.id;
    if (id == null) return;
    final readings = List.of(_pendingReadings);
    final points = List.of(_pendingPoints);
    _pendingReadings.clear();
    _pendingPoints.clear();
    try {
      await db.insertReadings(id, readings);
      await db.insertTrackPoints(id, points);
    } catch (e) {
      debugPrint('Flush failed: $e');
    }
    notifyListeners();
  }

  Future<Trip?> stop() async {
    final t = trip;
    if (t == null) return null;
    await _readingSub?.cancel();
    await _gpsSub?.cancel();
    _readingSub = null;
    _gpsSub = null;
    _demoGps?.cancel();
    _demoGps = null;
    _flushTimer?.cancel();
    await _flush();
    final done = t.copyWith(endedAt: DateTime.now());
    await db.updateTrip(done);
    trip = null;
    notifyListeners();
    return done;
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    _gpsSub?.cancel();
    _demoGps?.cancel();
    _flushTimer?.cancel();
    super.dispose();
  }
}
