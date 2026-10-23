import 'package:flutter_test/flutter_test.dart';
import 'package:raft_pressure/models/trip.dart';
import 'package:raft_pressure/services/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('stores trips, readings and track, and summarises them', () async {
    final db = await TripDatabase.open(path: inMemoryDatabasePath);
    final t0 = DateTime(2026, 7, 1, 10);
    final trip = await db.insertTrip(Trip(name: 'Loch Lomond', startedAt: t0, sensorId: 'AA'));
    await db.insertReadings(trip.id!, [
      Reading(time: t0, absHpa: 1100, gaugeHpa: 90, temperatureC: 15),
      Reading(time: t0.add(const Duration(seconds: 2)), absHpa: 1110, gaugeHpa: 100),
    ]);
    await db.insertTrackPoints(trip.id!, [TrackPoint(time: t0, lat: 56.1, lon: -4.6)]);

    final list = await db.listTrips();
    expect(list.single.trip.name, 'Loch Lomond');
    expect(list.single.readingCount, 2);
    expect(list.single.pointCount, 1);
    expect(list.single.minGaugeHpa, 90);
    expect(list.single.maxGaugeHpa, 100);

    // A trip left open by a crash gets closed at its last reading.
    await db.closeDanglingTrips();
    expect((await db.getTrip(trip.id!))!.endedAt, t0.add(const Duration(seconds: 2)));

    await db.replaceTrack(trip.id!, [
      TrackPoint(time: t0, lat: 1, lon: 2),
      TrackPoint(time: t0.add(const Duration(seconds: 1)), lat: 1.1, lon: 2.1),
    ]);
    expect((await db.track(trip.id!)).length, 2);

    await db.deleteTrip(trip.id!);
    expect(await db.listTrips(), isEmpty);
    expect(await db.readings(trip.id!), isEmpty);
  });
}
