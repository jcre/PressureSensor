import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/units.dart';
import '../services/alert_service.dart';
import '../services/ble_scanner.dart';
import '../services/demo.dart';
import '../services/live_monitor.dart';
import '../services/settings_store.dart';
import '../services/trip_recorder.dart';
import 'alerts_screen.dart';
import 'inspector_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'trip_detail_screen.dart';
import 'trips_screen.dart';
import 'widgets/pressure_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _wakelock;

  void _syncWakelock(bool want) {
    if (_wakelock == want) return;
    _wakelock = want;
    want ? WakelockPlus.enable() : WakelockPlus.disable();
  }

  @override
  void dispose() {
    if (_wakelock == true) WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final monitor = context.watch<LiveMonitor>();
    final recorder = context.watch<TripRecorder>();
    _syncWakelock(settings.keepScreenOn && monitor.sensor != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raft Pressure'),
        actions: [
          IconButton(
            tooltip: 'Trips',
            icon: const Icon(Icons.route),
            onPressed: () => _push(context, const TripsScreen()),
          ),
          IconButton(
            tooltip: 'Alerts',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () => _push(context, const AlertsScreen()),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _push(context, const SettingsScreen()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          const _AlarmBanner(),
          if (settings.demoMode) const _DemoBanner() else const _BluetoothBanner(),
          if (monitor.sensor == null)
            const _NoSensorCard()
          else ...[
            const _ReadoutCard(),
            const SizedBox(height: 8),
            const _ChartCard(),
            const SizedBox(height: 8),
            _TripCard(recorder: recorder),
          ],
        ],
      ),
    );
  }
}

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

class _AlarmBanner extends StatelessWidget {
  const _AlarmBanner();

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AlertService>();
    final alarm = alerts.activeAlarm;
    if (alarm == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.alarm, color: scheme.onErrorContainer, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(AlertService.title(alarm.kind),
                  style: TextStyle(color: scheme.onErrorContainer, fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: scheme.error, minimumSize: const Size(110, 52)),
              onPressed: alerts.stop,
              icon: const Icon(Icons.alarm_off),
              label: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BluetoothBanner extends StatelessWidget {
  const _BluetoothBanner();

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<BleScanner>();
    String? msg;
    if (scanner.adapterState == BluetoothAdapterState.off) {
      msg = 'Bluetooth is off';
    } else if (scanner.adapterState == BluetoothAdapterState.unauthorized) {
      msg = 'Bluetooth permission not granted';
    } else if (scanner.error != null) {
      msg = scanner.error;
    }
    if (msg == null) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.bluetooth_disabled),
        title: Text(msg),
        trailing: scanner.adapterState == BluetoothAdapterState.off
            ? TextButton(onPressed: scanner.turnOnBluetooth, child: const Text('Turn on'))
            : TextButton(onPressed: scanner.ensurePermissions, child: const Text('Grant')),
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<DemoController>();
    final e = demo.elapsed;
    final phase = e.inSeconds < 10
        ? 'flat – try Zero'
        : e.inSeconds < 70
            ? 'inflating'
            : e.inSeconds < 190
                ? 'paddling'
                : 'paddling, slow leak';
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.science_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text('Demo mode · simulated sensor & GPS\n$phase')),
            TextButton(
              onPressed: () {
                demo.restart();
                context.read<LiveMonitor>().clearHistory();
              },
              child: const Text('Restart'),
            ),
            TextButton(onPressed: () => demo.setEnabled(false), child: const Text('Exit')),
          ],
        ),
      ),
    );
  }
}

class _NoSensorCard extends StatelessWidget {
  const _NoSensorCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No sensor yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Switch your beacon on, keep it next to the phone and tap "Find sensor". '
              'If the app doesn\'t recognise its data format you can find the pressure bytes '
              'from the inspector, using your phone\'s barometer as the reference.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _push(context, const ScanScreen()),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Find sensor'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.read<DemoController>().setEnabled(true),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Try demo mode'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadoutCard extends StatelessWidget {
  const _ReadoutCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final monitor = context.watch<LiveMonitor>();
    final scheme = Theme.of(context).colorScheme;
    final sensor = monitor.sensor!;
    final r = monitor.latest;
    final state = monitor.state;
    final unit = settings.unit;
    final gaugeMode = settings.display == PressureDisplay.gauge;
    final alerts = settings.alerts;

    Color valueColor = scheme.onSurface;
    if (r != null && gaugeMode && !monitor.needsZero) {
      if (alerts.high.enabled && r.gaugeHpa >= alerts.high.thresholdHpa) {
        valueColor = Colors.green.shade600;
      } else if (alerts.low.enabled && r.gaugeHpa <= alerts.low.thresholdHpa) {
        valueColor = scheme.error;
      }
    }
    final stale = state != LinkState.live;
    final mainText = r == null
        ? '—'
        : unit.format(gaugeMode ? r.gaugeHpa : r.absHpa, decimals: gaugeMode ? unit.decimals : unit.decimals + 1, withUnit: false);

    final (chipText, chipColor) = switch (state) {
      LinkState.noSensor => ('No sensor', scheme.outline),
      LinkState.searching => ('Searching…', scheme.outline),
      LinkState.undecoded => ('No pressure in data', scheme.tertiary),
      LinkState.live => ('Live', Colors.green.shade600),
      LinkState.stale => ('Signal lost', scheme.error),
    };
    final age = monitor.lastPacketAt == null ? null : DateTime.now().difference(monitor.lastPacketAt!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(sensor.name, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                ),
                Chip(
                  label: Text(chipText),
                  labelStyle: TextStyle(color: chipColor, fontWeight: FontWeight.w600),
                  side: BorderSide(color: chipColor),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(gaugeMode ? 'Gauge pressure' : 'Absolute pressure', style: TextStyle(color: scheme.outline)),
            FittedBox(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    mainText,
                    style: TextStyle(
                      fontSize: 84,
                      fontWeight: FontWeight.w700,
                      color: stale ? valueColor.withValues(alpha: 0.4) : valueColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(unit.label, style: TextStyle(fontSize: 28, color: scheme.outline)),
                ],
              ),
            ),
            if (monitor.needsZero && gaugeMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Not zeroed yet: with the sensor in open air (raft valve open), tap Zero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.tertiary),
                ),
              ),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                if (r != null)
                  _Stat(Icons.speed, gaugeMode ? 'abs ${r.absHpa.toStringAsFixed(1)} hPa' : 'gauge ${unit.format(r.gaugeHpa)}'),
                if (r?.temperatureC != null) _Stat(Icons.thermostat, '${r!.temperatureC!.toStringAsFixed(1)} °C'),
                if (r?.batteryPct != null) _Stat(Icons.battery_std, '${r!.batteryPct!.toStringAsFixed(0)} %'),
                if (monitor.latestPacket != null) _Stat(Icons.network_cell, '${monitor.latestPacket!.rssi} dBm'),
                if (age != null) _Stat(Icons.schedule, age.inSeconds < 2 ? 'now' : '${age.inSeconds}s ago'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: r == null ? null : () => _confirmZero(context, monitor),
                    icon: const Icon(Icons.exposure_zero),
                    label: const Text('Zero'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _push(context, InspectorScreen(deviceId: sensor.id)),
                    icon: Icon(state == LinkState.undecoded ? Icons.warning_amber : Icons.tune),
                    label: Text(state == LinkState.undecoded ? 'Set up decoder' : 'Inspector'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmZero(BuildContext context, LiveMonitor monitor) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zero the sensor?'),
        content: const Text(
          'Only do this while the sensor is at outside air pressure: before the raft is sealed, '
          'or with the valve open. The current reading becomes 0.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zero')),
        ],
      ),
    );
    if (ok == true) await monitor.zero();
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.outline;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: c),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(color: c)),
    ]);
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard();

  static const windows = [2, 5, 30, 120, 0];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final monitor = context.watch<LiveMonitor>();
    final minutes = settings.liveWindowMinutes;
    final now = DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
        child: Column(
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (final w in windows)
                  ButtonSegment(value: w, label: Text(w == 0 ? 'All' : (w < 60 ? '${w}m' : '${w ~/ 60}h'))),
              ],
              selected: {windows.contains(minutes) ? minutes : 5},
              onSelectionChanged: (s) => settings.update((x) => x.liveWindowMinutes = s.first),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: PressureChart(
                readings: monitor.history,
                unit: settings.unit,
                display: settings.display,
                highHpa: settings.alerts.high.enabled ? settings.alerts.high.thresholdHpa : null,
                lowHpa: settings.alerts.low.enabled ? settings.alerts.low.thresholdHpa : null,
                windowStart: minutes == 0 ? null : now.subtract(Duration(minutes: minutes)),
                windowEnd: minutes == 0 ? null : now,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.recorder});

  final TripRecorder recorder;

  @override
  Widget build(BuildContext context) {
    final trip = recorder.trip;
    if (trip == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.kayaking, size: 32),
          title: const Text('Start a trip'),
          subtitle: const Text('Logs pressure and your GPS track until you stop'),
          trailing: FilledButton(onPressed: () => _start(context), child: const Text('Start')),
        ),
      );
    }
    final d = trip.duration;
    final dur = '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.fiber_manual_record, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(trip.name, style: Theme.of(context).textTheme.titleMedium)),
              FilledButton.tonalIcon(
                onPressed: () => _stop(context),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ]),
            const SizedBox(height: 8),
            Text('$dur  ·  ${(recorder.distanceMetres / 1000).toStringAsFixed(2)} km  ·  '
                '${recorder.readingCount} readings  ·  ${recorder.track.length} GPS points'),
            if (recorder.gpsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(recorder.gpsError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final ctrl = TextEditingController(text: 'Trip ${DateFormat('d MMM HH:mm').format(DateTime.now())}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start trip'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Start')),
        ],
      ),
    );
    if (name == null) return;
    await recorder.start(name.isEmpty ? 'Trip' : name);
  }

  Future<void> _stop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop recording?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop & save')),
        ],
      ),
    );
    if (ok != true) return;
    final trip = await recorder.stop();
    if (trip?.id != null && context.mounted) _push(context, TripDetailScreen(tripId: trip!.id!));
  }
}
