import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/units.dart';
import '../services/barometer_service.dart';
import '../services/demo.dart';
import '../services/settings_store.dart';
import 'inspector_screen.dart';
import 'scan_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final baro = context.watch<BarometerService>();
    final demo = context.read<DemoController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Display'),
          ListTile(
            title: const Text('Units'),
            trailing: SegmentedButton<PressureUnit>(
              showSelectedIcon: false,
              segments: [for (final u in PressureUnit.values) ButtonSegment(value: u, label: Text(u.label))],
              selected: {s.unit},
              onSelectionChanged: (v) => s.update((x) => x.unit = v.first),
            ),
          ),
          SwitchListTile(
            title: const Text('Show absolute pressure'),
            subtitle: const Text('Off: pressure above ambient, like a pump gauge'),
            value: s.display == PressureDisplay.absolute,
            onChanged: (v) => s.update((x) => x.display = v ? PressureDisplay.absolute : PressureDisplay.gauge),
          ),
          SwitchListTile(
            title: const Text('Keep screen on'),
            subtitle: const Text('While the live view is open'),
            value: s.keepScreenOn,
            onChanged: (v) => s.update((x) => x.keepScreenOn = v),
          ),
          const _Header('Ambient reference'),
          for (final m in ReferenceMode.values)
            ListTile(
              leading: Icon(s.referenceMode == m ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(m.label),
              subtitle: m == ReferenceMode.phoneBarometer
                  ? Text(baro.hpa == null
                      ? 'No phone barometer detected – falls back to captured zero'
                      : 'Phone reads ${baro.hpa!.toStringAsFixed(1)} hPa. Best for long trips with altitude/weather changes.')
                  : null,
              onTap: () => s.update((x) => x.referenceMode = m),
            ),
          const _Header('Trip recording'),
          SwitchListTile(
            title: const Text('Record GPS track'),
            subtitle: const Text('Also keeps recording running with the screen off (Android)'),
            value: s.gpsEnabled,
            onChanged: (v) => s.update((x) => x.gpsEnabled = v),
          ),
          ListTile(
            title: const Text('Save a reading every'),
            trailing: DropdownButton<int>(
              value: [1, 2, 5, 10, 30].contains(s.recordIntervalSec) ? s.recordIntervalSec : 2,
              items: [for (final v in [1, 2, 5, 10, 30]) DropdownMenuItem(value: v, child: Text('$v s'))],
              onChanged: (v) => s.update((x) => x.recordIntervalSec = v ?? 2),
            ),
          ),
          const _Header('Sensors'),
          for (final sensor in s.sensors)
            ListTile(
              leading: Icon(sensor.id == s.activeSensorId ? Icons.star : Icons.star_border),
              title: Text(sensor.name),
              subtitle: Text('${sensor.id}\n${sensor.profile.kind.label}'
                  '${sensor.zeroHpa == null ? ' · not zeroed' : ' · zero ${sensor.zeroHpa!.toStringAsFixed(1)} hPa'}'),
              isThreeLine: true,
              onTap: () => s.update((x) => x.activeSensorId = sensor.id),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'inspect') {
                    Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => InspectorScreen(deviceId: sensor.id)));
                  } else if (v == 'remove') {
                    if (sensor.id == DemoSimulation.deviceId) {
                      await demo.setEnabled(false);
                    } else {
                      await s.removeSensor(sensor.id);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'inspect', child: Text('Inspector / decoder')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add sensor'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ScanScreen())),
          ),
          const _Header('Demo'),
          SwitchListTile(
            secondary: const Icon(Icons.science_outlined),
            title: const Text('Demo mode'),
            subtitle: const Text('Simulated sensor (inflate → paddle → slow leak) and GPS track. No hardware needed.'),
            value: s.demoMode,
            onChanged: demo.setEnabled,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      );
}
