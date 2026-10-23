import 'dart:math' as math;

class Trip {
  const Trip({
    this.id,
    required this.name,
    required this.startedAt,
    this.endedAt,
    this.sensorId,
    this.sensorName,
    this.notes = '',
  });

  final int? id;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? sensorId;
  final String? sensorName;
  final String notes;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  Trip copyWith({int? id, String? name, DateTime? endedAt, String? notes}) => Trip(
        id: id ?? this.id,
        name: name ?? this.name,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        sensorId: sensorId,
        sensorName: sensorName,
        notes: notes ?? this.notes,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'sensor_id': sensorId,
        'sensor_name': sensorName,
        'notes': notes,
      };

  factory Trip.fromRow(Map<String, Object?> r) => Trip(
        id: r['id'] as int?,
        name: r['name'] as String? ?? 'Trip',
        startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
        endedAt: r['ended_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['ended_at'] as int),
        sensorId: r['sensor_id'] as String?,
        sensorName: r['sensor_name'] as String?,
        notes: r['notes'] as String? ?? '',
      );
}

/// One decoded sensor reading.
class Reading {
  const Reading({
    required this.time,
    required this.absHpa,
    required this.gaugeHpa,
    this.temperatureC,
    this.batteryPct,
    this.rssi,
  });

  final DateTime time;
  final double absHpa;
  final double gaugeHpa;
  final double? temperatureC;
  final double? batteryPct;
  final int? rssi;

  Map<String, Object?> toRow(int tripId) => {
        'trip_id': tripId,
        't': time.millisecondsSinceEpoch,
        'abs_hpa': absHpa,
        'gauge_hpa': gaugeHpa,
        'temp_c': temperatureC,
        'battery': batteryPct,
        'rssi': rssi,
      };

  factory Reading.fromRow(Map<String, Object?> r) => Reading(
        time: DateTime.fromMillisecondsSinceEpoch(r['t'] as int),
        absHpa: (r['abs_hpa'] as num).toDouble(),
        gaugeHpa: (r['gauge_hpa'] as num).toDouble(),
        temperatureC: (r['temp_c'] as num?)?.toDouble(),
        batteryPct: (r['battery'] as num?)?.toDouble(),
        rssi: r['rssi'] as int?,
      );
}

class TrackPoint {
  const TrackPoint({
    required this.time,
    required this.lat,
    required this.lon,
    this.elevation,
    this.speed,
    this.accuracy,
  });

  final DateTime time;
  final double lat;
  final double lon;
  final double? elevation;

  /// m/s
  final double? speed;

  /// metres
  final double? accuracy;

  Map<String, Object?> toRow(int tripId) => {
        'trip_id': tripId,
        't': time.millisecondsSinceEpoch,
        'lat': lat,
        'lon': lon,
        'ele': elevation,
        'speed': speed,
        'accuracy': accuracy,
      };

  factory TrackPoint.fromRow(Map<String, Object?> r) => TrackPoint(
        time: DateTime.fromMillisecondsSinceEpoch(r['t'] as int),
        lat: (r['lat'] as num).toDouble(),
        lon: (r['lon'] as num).toDouble(),
        elevation: (r['ele'] as num?)?.toDouble(),
        speed: (r['speed'] as num?)?.toDouble(),
        accuracy: (r['accuracy'] as num?)?.toDouble(),
      );
}

/// Great-circle distance in metres.
double haversineMetres(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

double trackLengthMetres(List<TrackPoint> pts) {
  var d = 0.0;
  for (var i = 1; i < pts.length; i++) {
    d += haversineMetres(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
  }
  return d;
}

/// Linear interpolation of gauge pressure at [t] from time-sorted readings.
/// Returns null if [t] is more than [maxGap] from any reading.
double? gaugeAt(List<Reading> readings, DateTime t, {Duration maxGap = const Duration(minutes: 2)}) {
  if (readings.isEmpty) return null;
  final ms = t.millisecondsSinceEpoch;
  var lo = 0;
  var hi = readings.length - 1;
  if (ms <= readings.first.time.millisecondsSinceEpoch) {
    return readings.first.time.difference(t) <= maxGap ? readings.first.gaugeHpa : null;
  }
  if (ms >= readings.last.time.millisecondsSinceEpoch) {
    return t.difference(readings.last.time) <= maxGap ? readings.last.gaugeHpa : null;
  }
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (readings[mid].time.millisecondsSinceEpoch <= ms) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final a = readings[lo];
  final b = readings[hi];
  final span = b.time.millisecondsSinceEpoch - a.time.millisecondsSinceEpoch;
  if (span > maxGap.inMilliseconds * 2) {
    final nearest = (ms - a.time.millisecondsSinceEpoch) < (b.time.millisecondsSinceEpoch - ms) ? a : b;
    return nearest.time.difference(t).abs() <= maxGap ? nearest.gaugeHpa : null;
  }
  if (span == 0) return a.gaugeHpa;
  final f = (ms - a.time.millisecondsSinceEpoch) / span;
  return a.gaugeHpa + (b.gaugeHpa - a.gaugeHpa) * f;
}
