import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alert_settings.dart';
import '../models/units.dart';
import '../services/alert_service.dart';
import '../services/settings_store.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final a = settings.alerts;
    final unit = settings.unit;

    Future<void> save(AlertSettings next) => settings.update((s) => s.alerts = next);

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _ThresholdCard(
            title: 'Fully inflated (high)',
            subtitle: 'Fires as gauge pressure rises to this level – stop pumping.',
            icon: Icons.arrow_upward,
            alert: a.high,
            unit: unit,
            onChanged: (h) => save(a.copyWith(high: h)),
          ),
          _ThresholdCard(
            title: 'Losing air (low)',
            subtitle: 'Fires if pressure falls to this level after having been above it.',
            icon: Icons.arrow_downward,
            alert: a.low,
            unit: unit,
            onChanged: (l) => save(a.copyWith(low: l)),
          ),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.signal_cellular_connected_no_internet_0_bar),
                  title: const Text('Sensor signal lost'),
                  subtitle: Text('No readings for ${a.signalLostSeconds} s'),
                  value: a.signalLostEnabled,
                  onChanged: (v) => save(a.copyWith(signalLostEnabled: v)),
                ),
                if (a.signalLostEnabled) ...[
                  Slider(
                    min: 15,
                    max: 300,
                    divisions: 19,
                    value: a.signalLostSeconds.toDouble().clamp(15, 300),
                    label: '${a.signalLostSeconds} s',
                    onChanged: (v) => save(a.copyWith(signalLostSeconds: v.round())),
                  ),
                  _ActionsEditor(
                    actions: a.signalLost,
                    onChanged: (x) => save(a.copyWith(signalLost: x)),
                  ),
                ],
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Hysteresis'),
                  subtitle: Text(
                    'Pressure must move ${unit.format(a.hysteresisHpa, decimals: unit.decimals + 1)} back past a '
                    'threshold before that alert can fire again.',
                  ),
                ),
                Slider(
                  min: 1,
                  max: 30,
                  divisions: 29,
                  value: a.hysteresisHpa.clamp(1, 30),
                  label: unit.format(a.hysteresisHpa, decimals: unit.decimals + 1),
                  onChanged: (v) => save(a.copyWith(hysteresisHpa: v)),
                ),
                ListTile(
                  title: const Text('Continuous alarm stops after'),
                  trailing: DropdownButton<int>(
                    value: [10, 30, 60, 120, 300].contains(a.alarmMaxSeconds) ? a.alarmMaxSeconds : 30,
                    items: [
                      for (final s in [10, 30, 60, 120, 300]) DropdownMenuItem(value: s, child: Text('$s s')),
                    ],
                    onChanged: (v) => save(a.copyWith(alarmMaxSeconds: v)),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Alerts need a zeroed sensor (or the standard-atmosphere reference). They also work with the '
              'screen off while a trip is recording.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThresholdCard extends StatelessWidget {
  const _ThresholdCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.alert,
    required this.unit,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final ThresholdAlert alert;
  final PressureUnit unit;
  final ValueChanged<ThresholdAlert> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            value: alert.enabled,
            onChanged: (v) => onChanged(alert.copyWith(enabled: v)),
          ),
          if (alert.enabled) ...[
            ListTile(
              title: const Text('Threshold (gauge)'),
              subtitle: const Text('Tap the value to type it in'),
              trailing: TextButton(
                onPressed: () => _editThreshold(context),
                child: Text(unit.format(alert.thresholdHpa), style: const TextStyle(fontSize: 18)),
              ),
            ),
            Builder(builder: (context) {
              // Slide in tidy steps of the display unit, up to ≈5 psi
              // (packrafts typically run 1–2.5 psi).
              final max = (unit.fromHpa(345) / unit.step).round() * unit.step;
              return Slider(
                min: 0,
                max: max,
                divisions: (max / unit.step).round(),
                value: unit.fromHpa(alert.thresholdHpa).clamp(0, max),
                label: unit.format(alert.thresholdHpa),
                onChanged: (v) => onChanged(alert.copyWith(thresholdHpa: unit.toHpa(v))),
              );
            }),
            _ActionsEditor(actions: alert.actions, onChanged: (x) => onChanged(alert.copyWith(actions: x))),
          ],
        ],
      ),
    );
  }

  Future<void> _editThreshold(BuildContext context) async {
    final ctrl = TextEditingController(text: unit.fromHpa(alert.thresholdHpa).toStringAsFixed(unit.decimals + 1));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: unit.label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (v != null && v >= 0) onChanged(alert.copyWith(thresholdHpa: unit.toHpa(v)));
  }
}

class _ActionsEditor extends StatelessWidget {
  const _ActionsEditor({required this.actions, required this.onChanged});

  final AlertActions actions;
  final ValueChanged<AlertActions> onChanged;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsStore>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<AlertSound>(
            value: actions.sound,
            items: [for (final s in AlertSound.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (v) => onChanged(actions.copyWith(sound: v)),
          ),
          FilterChip(
            label: const Text('Vibrate'),
            selected: actions.vibrate,
            onSelected: (v) => onChanged(actions.copyWith(vibrate: v)),
          ),
          FilterChip(
            label: const Text('Notification'),
            selected: actions.notify,
            onSelected: (v) => onChanged(actions.copyWith(notify: v)),
          ),
          TextButton.icon(
            onPressed: () => context
                .read<AlertService>()
                .test(actions, unit: settings.unit, alarmMaxSeconds: settings.alerts.alarmMaxSeconds),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Test'),
          ),
        ],
      ),
    );
  }
}
