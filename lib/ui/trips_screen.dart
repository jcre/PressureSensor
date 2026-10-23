import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/database.dart';
import '../services/settings_store.dart';
import '../services/trip_recorder.dart';
import 'trip_detail_screen.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  late Future<List<TripSummary>> _trips;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _trips = context.read<TripDatabase>().listTrips();

  @override
  Widget build(BuildContext context) {
    final unit = context.watch<SettingsStore>().unit;
    final recordingId = context.watch<TripRecorder>().trip?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: FutureBuilder<List<TripSummary>>(
        future: _trips,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final trips = snap.data!;
          if (trips.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No trips yet. Start one from the main screen.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            itemCount: trips.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = trips[i];
              final t = s.trip;
              final d = t.duration;
              final range = s.minGaugeHpa == null
                  ? 'no readings'
                  : '${unit.format(s.minGaugeHpa!)} – ${unit.format(s.maxGaugeHpa!)}';
              return ListTile(
                leading: Icon(t.id == recordingId ? Icons.fiber_manual_record : Icons.kayaking,
                    color: t.id == recordingId ? Colors.red : null),
                title: Text(t.name),
                subtitle: Text(
                  '${DateFormat('EEE d MMM y, HH:mm').format(t.startedAt)}  ·  '
                  '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m\n'
                  '$range  ·  ${s.pointCount} GPS points',
                ),
                isThreeLine: true,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => TripDetailScreen(tripId: t.id!)),
                  );
                  if (mounted) setState(_reload);
                },
              );
            },
          );
        },
      ),
    );
  }
}
