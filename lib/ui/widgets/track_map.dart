import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trip.dart';
import '../../models/units.dart';

const _ramp = [
  Color(0xFF30123B), // dark blue  – lowest
  Color(0xFF2D9FE6),
  Color(0xFF3BE07A),
  Color(0xFFF2C12E),
  Color(0xFFD9381E), // red        – highest
];

Color rampColor(double t) {
  t = t.clamp(0.0, 1.0);
  final pos = t * (_ramp.length - 1);
  final i = pos.floor().clamp(0, _ramp.length - 2);
  return Color.lerp(_ramp[i], _ramp[i + 1], pos - i)!;
}

/// GPS track coloured by the raft's gauge pressure at each point.
class TrackMap extends StatelessWidget {
  const TrackMap({
    super.key,
    required this.track,
    required this.readings,
    required this.unit,
    this.selected,
    this.mapController,
  });

  final List<TrackPoint> track;
  final List<Reading> readings;
  final PressureUnit unit;
  final DateTime? selected;
  final MapController? mapController;

  static const _buckets = 24;

  @override
  Widget build(BuildContext context) {
    if (track.isEmpty) {
      return const Center(child: Text('No GPS track for this trip'));
    }
    final pts = [for (final p in track) LatLng(p.lat, p.lon)];
    final gauges = [for (final p in track) gaugeAt(readings, p.time)];
    final known = gauges.whereType<double>();
    final minG = known.isEmpty ? 0.0 : known.reduce(math.min);
    final maxG = known.isEmpty ? 1.0 : known.reduce(math.max);
    final span = math.max(maxG - minG, 0.5);

    int bucket(double? g) => g == null ? -1 : (((g - minG) / span) * (_buckets - 1)).round();

    // Merge consecutive segments of the same colour into one polyline.
    final polylines = <Polyline>[];
    var start = 0;
    for (var i = 1; i <= pts.length; i++) {
      final b = bucket(gauges[start]);
      if (i == pts.length || bucket(gauges[i]) != b) {
        final seg = pts.sublist(start, math.min(i + 1, pts.length));
        if (seg.length >= 2) {
          polylines.add(Polyline(
            points: seg,
            strokeWidth: 5,
            color: b < 0 ? Colors.grey : rampColor(b / (_buckets - 1)),
            borderStrokeWidth: 1,
            borderColor: Colors.black26,
          ));
        }
        start = i;
      }
    }

    TrackPoint? sel;
    if (selected != null) {
      sel = track.reduce((a, b) =>
          (a.time.difference(selected!).abs() <= b.time.difference(selected!).abs()) ? a : b);
    }

    final bounds = LatLngBounds.fromPoints(pts);
    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCameraFit: pts.length > 1
                ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(36), maxZoom: 17)
                : null,
            initialCenter: pts.first,
            initialZoom: 15,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.jcre.raft_pressure',
            ),
            PolylineLayer(polylines: polylines),
            MarkerLayer(markers: [
              _dot(pts.first, Colors.green, Icons.play_arrow),
              if (pts.length > 1) _dot(pts.last, Colors.black87, Icons.stop),
              if (sel != null) _dot(LatLng(sel.lat, sel.lon), Theme.of(context).colorScheme.tertiary, Icons.circle),
            ]),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomRight,
              attributions: [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        ),
        if (known.isNotEmpty)
          Positioned(
            left: 8,
            top: 8,
            child: _Legend(min: minG, max: minG + span, unit: unit),
          ),
      ],
    );
  }

  Marker _dot(LatLng p, Color c, IconData icon) => Marker(
        point: p,
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: Icon(icon, size: 12, color: Colors.white),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.min, required this.max, required this.unit});

  final double min;
  final double max;
  final PressureUnit unit;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(unit.format(min, decimals: unit.decimals + 1), style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Container(
              width: 80,
              height: 10,
              decoration: const BoxDecoration(gradient: LinearGradient(colors: _ramp)),
            ),
            const SizedBox(width: 4),
            Text(unit.format(max, decimals: unit.decimals + 1), style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
