import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trip.dart';
import '../models/units.dart';
import '../services/database.dart';
import '../services/gpx.dart';
import '../services/settings_store.dart';
import '../services/trip_recorder.dart';
import 'widgets/pressure_chart.dart';
import 'widgets/track_map.dart';

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({super.key, required this.tripId});

  final int tripId;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  Trip? _trip;
  List<Reading> _readings = [];
  List<TrackPoint> _track = [];
  bool _loading = true;
  DateTime? _selected;

  TripDatabase get _db => context.read<TripDatabase>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final trip = await _db.getTrip(widget.tripId);
    final readings = await _db.readings(widget.tripId);
    final track = await _db.track(widget.tripId);
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _readings = readings;
      _track = track;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final unit = settings.unit;
    final trip = _trip;
    final recording = context.watch<TripRecorder>().trip?.id == widget.tripId;

    return Scaffold(
      appBar: AppBar(
        title: Text(trip?.name ?? 'Trip'),
        actions: [
          if (trip != null)
            PopupMenuButton<String>(
              onSelected: (v) => _menu(v, trip, unit),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'gpx', child: ListTile(leading: Icon(Icons.map), title: Text('Export GPX'))),
                const PopupMenuItem(value: 'csv', child: ListTile(leading: Icon(Icons.table_chart), title: Text('Export CSV'))),
                const PopupMenuItem(
                    value: 'import', child: ListTile(leading: Icon(Icons.upload_file), title: Text('Import GPX track'))),
                const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit), title: Text('Rename / notes'))),
                if (!recording)
                  const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Delete'))),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : trip == null
              ? const Center(child: Text('Trip not found'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _Stats(trip: trip, readings: _readings, track: _track, unit: unit),
                    const SizedBox(height: 8),
                    if (_track.isNotEmpty)
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: SizedBox(
                          height: 320,
                          child: TrackMap(track: _track, readings: _readings, unit: unit, selected: _selected),
                        ),
                      )
                    else
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.location_off),
                          title: const Text('No GPS track'),
                          subtitle: const Text('Import a GPX from your watch or phone to overlay pressure on it.'),
                          trailing: TextButton(onPressed: () => _import(trip), child: const Text('Import')),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
                        child: SizedBox(
                          height: 240,
                          child: PressureChart(
                            readings: _readings,
                            unit: unit,
                            display: settings.display,
                            highHpa: settings.alerts.high.enabled ? settings.alerts.high.thresholdHpa : null,
                            lowHpa: settings.alerts.low.enabled ? settings.alerts.low.thresholdHpa : null,
                            selected: _selected,
                            onSelect: (t) => setState(() => _selected = t),
                          ),
                        ),
                      ),
                    ),
                    if (_track.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Touch the chart to see where you were on the map.', style: TextStyle(fontSize: 12)),
                      ),
                    if (trip.notes.isNotEmpty)
                      Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(trip.notes))),
                  ],
                ),
    );
  }

  Future<void> _menu(String action, Trip trip, PressureUnit unit) async {
    switch (action) {
      case 'gpx':
        if (_track.isEmpty) {
          _snack('This trip has no GPS track to export – try CSV.');
          return;
        }
        await _share(trip, 'gpx', Gpx.export(trip, _track, _readings, unit), 'application/gpx+xml');
      case 'csv':
        await _share(trip, 'csv', Gpx.readingsCsv(_readings, unit), 'text/csv');
      case 'import':
        await _import(trip);
      case 'rename':
        await _rename(trip);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete trip?'),
            content: Text('"${trip.name}" and all its readings will be removed.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await _db.deleteTrip(trip.id!);
          if (mounted) Navigator.pop(context);
        }
    }
  }

  Future<void> _share(Trip trip, String ext, String content, String mime) async {
    final dir = await getTemporaryDirectory();
    final safe = trip.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = File(p.join(dir.path, '${safe}_${DateFormat('yyyyMMdd_HHmm').format(trip.startedAt)}.$ext'));
    await file.writeAsString(content);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], subject: trip.name));
  }

  Future<void> _import(Trip trip) async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    try {
      final xml = utf8.decode(await files.first.readAsBytes(), allowMalformed: true);
      final pts = Gpx.parse(xml);
      if (pts.isEmpty) {
        _snack('No timestamped track points found in that file.');
        return;
      }
      final start = trip.startedAt.subtract(const Duration(minutes: 30));
      final end = (trip.endedAt ?? DateTime.now()).add(const Duration(minutes: 30));
      final overlapping = pts.where((x) => x.time.isAfter(start) && x.time.isBefore(end)).toList();
      if (overlapping.isEmpty && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Times don\'t overlap'),
            content: const Text(
              'That track was recorded at a different time from this trip, so pressure can\'t be matched to '
              'positions. Import it anyway?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
            ],
          ),
        );
        if (go != true) return;
      }
      await _db.replaceTrack(trip.id!, overlapping.isEmpty ? pts : overlapping);
      await _load();
      _snack('Imported ${overlapping.isEmpty ? pts.length : overlapping.length} track points');
    } catch (e) {
      _snack('Could not read GPX: $e');
    }
  }

  Future<void> _rename(Trip trip) async {
    final name = TextEditingController(text: trip.name);
    final notes = TextEditingController(text: trip.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit trip'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: notes, maxLines: 4, decoration: const InputDecoration(labelText: 'Notes')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final updated = trip.copyWith(name: name.text.trim().isEmpty ? trip.name : name.text.trim(), notes: notes.text);
    await _db.updateTrip(updated);
    setState(() => _trip = updated);
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.trip, required this.readings, required this.track, required this.unit});

  final Trip trip;
  final List<Reading> readings;
  final List<TrackPoint> track;
  final PressureUnit unit;

  @override
  Widget build(BuildContext context) {
    final d = trip.duration;
    final gauges = readings.map((r) => r.gaugeHpa);
    final temps = readings.map((r) => r.temperatureC).whereType<double>();
    final km = trackLengthMetres(track) / 1000;
    String fmtDur(Duration d) => '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

    final items = <(String, String)>[
      ('Started', DateFormat('d MMM y HH:mm').format(trip.startedAt)),
      ('Duration', fmtDur(d)),
      if (track.isNotEmpty) ('Distance', '${km.toStringAsFixed(2)} km'),
      if (track.isNotEmpty && d.inSeconds > 0) ('Avg speed', '${(km / (d.inSeconds / 3600)).toStringAsFixed(1)} km/h'),
      if (readings.isNotEmpty) ('Max', unit.format(gauges.reduce(math.max))),
      if (readings.isNotEmpty) ('Min', unit.format(gauges.reduce(math.min))),
      if (readings.isNotEmpty) ('End', unit.format(readings.last.gaugeHpa)),
      if (temps.isNotEmpty)
        ('Temp', '${temps.reduce(math.min).toStringAsFixed(0)}–${temps.reduce(math.max).toStringAsFixed(0)} °C'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            for (final (k, v) in items)
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(k, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
          ],
        ),
      ),
    );
  }
}
