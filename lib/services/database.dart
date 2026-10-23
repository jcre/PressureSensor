import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/trip.dart';

class TripSummary {
  const TripSummary({
    required this.trip,
    required this.readingCount,
    required this.pointCount,
    this.minGaugeHpa,
    this.maxGaugeHpa,
  });

  final Trip trip;
  final int readingCount;
  final int pointCount;
  final double? minGaugeHpa;
  final double? maxGaugeHpa;
}

class TripDatabase {
  TripDatabase._(this._db);

  final Database _db;

  static Future<TripDatabase> open({String? path}) async {
    final db = await openDatabase(
      path ?? p.join(await getDatabasesPath(), 'trips.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE trips(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER,
            sensor_id TEXT,
            sensor_name TEXT,
            notes TEXT NOT NULL DEFAULT ''
          )''');
        await db.execute('''
          CREATE TABLE readings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trip_id INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
            t INTEGER NOT NULL,
            abs_hpa REAL NOT NULL,
            gauge_hpa REAL NOT NULL,
            temp_c REAL,
            battery REAL,
            rssi INTEGER
          )''');
        await db.execute('''
          CREATE TABLE track_points(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trip_id INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
            t INTEGER NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            ele REAL,
            speed REAL,
            accuracy REAL
          )''');
        await db.execute('CREATE INDEX readings_trip ON readings(trip_id, t)');
        await db.execute('CREATE INDEX track_trip ON track_points(trip_id, t)');
      },
    );
    return TripDatabase._(db);
  }

  Future<Trip> insertTrip(Trip trip) async {
    final id = await _db.insert('trips', trip.toRow());
    return trip.copyWith(id: id);
  }

  Future<void> updateTrip(Trip trip) =>
      _db.update('trips', trip.toRow(), where: 'id = ?', whereArgs: [trip.id]);

  Future<void> deleteTrip(int id) => _db.delete('trips', where: 'id = ?', whereArgs: [id]);

  Future<void> insertReadings(int tripId, List<Reading> readings) async {
    if (readings.isEmpty) return;
    final batch = _db.batch();
    for (final r in readings) {
      batch.insert('readings', r.toRow(tripId));
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertTrackPoints(int tripId, List<TrackPoint> points) async {
    if (points.isEmpty) return;
    final batch = _db.batch();
    for (final pt in points) {
      batch.insert('track_points', pt.toRow(tripId));
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceTrack(int tripId, List<TrackPoint> points) async {
    await _db.delete('track_points', where: 'trip_id = ?', whereArgs: [tripId]);
    await insertTrackPoints(tripId, points);
  }

  Future<List<TripSummary>> listTrips() async {
    final rows = await _db.rawQuery('''
      SELECT t.*,
        (SELECT COUNT(*) FROM readings r WHERE r.trip_id = t.id) AS reading_count,
        (SELECT COUNT(*) FROM track_points p WHERE p.trip_id = t.id) AS point_count,
        (SELECT MIN(gauge_hpa) FROM readings r WHERE r.trip_id = t.id) AS min_gauge,
        (SELECT MAX(gauge_hpa) FROM readings r WHERE r.trip_id = t.id) AS max_gauge
      FROM trips t ORDER BY started_at DESC''');
    return [
      for (final r in rows)
        TripSummary(
          trip: Trip.fromRow(r),
          readingCount: r['reading_count'] as int? ?? 0,
          pointCount: r['point_count'] as int? ?? 0,
          minGaugeHpa: (r['min_gauge'] as num?)?.toDouble(),
          maxGaugeHpa: (r['max_gauge'] as num?)?.toDouble(),
        ),
    ];
  }

  Future<Trip?> getTrip(int id) async {
    final rows = await _db.query('trips', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Trip.fromRow(rows.first);
  }

  Future<List<Reading>> readings(int tripId) async {
    final rows = await _db.query('readings', where: 'trip_id = ?', whereArgs: [tripId], orderBy: 't');
    return rows.map(Reading.fromRow).toList();
  }

  Future<List<TrackPoint>> track(int tripId) async {
    final rows = await _db.query('track_points', where: 'trip_id = ?', whereArgs: [tripId], orderBy: 't');
    return rows.map(TrackPoint.fromRow).toList();
  }

  /// Trips left open by a crash or the OS killing the app.
  Future<void> closeDanglingTrips() async {
    await _db.rawUpdate('''
      UPDATE trips SET ended_at = COALESCE(
        (SELECT MAX(t) FROM readings r WHERE r.trip_id = trips.id),
        (SELECT MAX(t) FROM track_points p WHERE p.trip_id = trips.id),
        started_at)
      WHERE ended_at IS NULL''');
  }
}
