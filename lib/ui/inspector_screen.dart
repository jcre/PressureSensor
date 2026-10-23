import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ble/adv_packet.dart';
import '../ble/decoder.dart';
import '../ble/field_finder.dart';
import '../ble/field_spec.dart';
import '../models/sensor_config.dart';
import '../services/barometer_service.dart';
import '../services/ble_scanner.dart';
import '../services/settings_store.dart';

/// Shows a device's raw advertisement bytes live, and lets the user work out
/// (or type in) where the pressure lives in them.
class InspectorScreen extends StatefulWidget {
  const InspectorScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<InspectorScreen> createState() => _InspectorScreenState();
}

class _InspectorScreenState extends State<InspectorScreen> {
  late final BleScanner _scanner;
  StreamSubscription<AdvPacket>? _sub;
  final List<AdvPacket> _packets = [];
  late DecoderProfile _profile;
  late TextEditingController _name;
  DateTime _lastRedraw = DateTime.fromMillisecondsSinceEpoch(0);

  static const _keep = 40;

  @override
  void initState() {
    super.initState();
    _scanner = context.read<BleScanner>();
    final settings = context.read<SettingsStore>();
    final existing = settings.sensors.where((s) => s.id == widget.deviceId).firstOrNull;
    final seen = _scanner.seen[widget.deviceId];
    _profile = existing?.profile ?? const DecoderProfile();
    _name = TextEditingController(
        text: existing?.name ?? (seen == null || seen.name.isEmpty ? 'Raft sensor' : seen.name));
    if (seen != null) _packets.add(seen);
    _sub = _scanner.packets.where((p) => p.deviceId == widget.deviceId).listen((p) {
      _packets.add(p);
      if (_packets.length > _keep) _packets.removeAt(0);
      final now = DateTime.now();
      if (now.difference(_lastRedraw) > const Duration(milliseconds: 400) && mounted) {
        _lastRedraw = now;
        setState(() {});
      }
    });
    _scanner.beginDiscovery();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scanner.endDiscovery();
    _name.dispose();
    super.dispose();
  }

  AdvPacket? get _latest => _packets.lastOrNull;

  /// Byte positions whose value changed across the recent packets.
  Set<int> _changing(AdBlock block) {
    final out = <int>{};
    for (final p in _packets) {
      final b = p.bytesFor(block.source, block.key);
      if (b == null) continue;
      for (var i = 0; i < b.length && i < block.bytes.length; i++) {
        if (b[i] != block.bytes[i]) out.add(i);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final latest = _latest;
    final values = latest == null ? const SensorValues() : AdvDecoder.decode(latest, _profile);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor inspector'),
        actions: [
          IconButton(
            tooltip: 'Copy packet log',
            icon: const Icon(Icons.copy_all),
            onPressed: _packets.isEmpty ? null : _copyLog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Sensor name')),
          const SizedBox(height: 8),
          Text(
            '${widget.deviceId}   ·   ${latest == null ? 'waiting for data…' : '${latest.rssi} dBm   ·   ${_packets.length} packets'}',
            style: TextStyle(color: scheme.outline),
          ),
          const SizedBox(height: 12),
          Text('Raw data', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Byte numbers start after the service UUID / company ID. Highlighted bytes are changing – '
            'pressure bytes will change when you squeeze or blow on the sensor.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (latest == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (!latest.hasPayload)
            const Text('This device broadcasts no service or manufacturer data.')
          else
            for (final block in latest.blocks) _BlockView(block: block, changing: _changing(block)),
          if (latest != null && latest.name.isNotEmpty)
            Text('Name: ${latest.name}${latest.serviceUuids.isEmpty ? '' : '   ·   UUIDs: ${latest.serviceUuids.join(', ')}'}',
                style: const TextStyle(fontSize: 12)),
          const Divider(height: 32),
          Text('Decoder', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<DecoderKind>(
            segments: [for (final k in DecoderKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {_profile.kind},
            onSelectionChanged: (s) => setState(() => _profile = _profile.copyWith(kind: s.first)),
          ),
          const SizedBox(height: 8),
          _ValueRow(
            label: 'Pressure',
            value: values.pressureHpa == null ? null : '${values.pressureHpa!.toStringAsFixed(2)} hPa',
            spec: _profile.kind == DecoderKind.custom ? _profile.pressure : null,
            custom: _profile.kind == DecoderKind.custom,
            onFind: () => _find(Quantity.pressure),
            onEdit: () => _edit('Pressure (hPa)', _profile.pressure, (f) => _profile.copyWith(pressure: f)),
            onClear: () => setState(() => _profile = _profile.copyWith(clearPressure: true)),
          ),
          _ValueRow(
            label: 'Temperature',
            value: values.temperatureC == null ? null : '${values.temperatureC!.toStringAsFixed(2)} °C',
            spec: _profile.kind == DecoderKind.custom ? _profile.temperature : null,
            custom: _profile.kind == DecoderKind.custom,
            onFind: () => _find(Quantity.temperature),
            onEdit: () => _edit('Temperature (°C)', _profile.temperature, (f) => _profile.copyWith(temperature: f)),
            onClear: () => setState(() => _profile = _profile.copyWith(clearTemperature: true)),
          ),
          _ValueRow(
            label: 'Battery',
            value: values.batteryPct == null ? null : '${values.batteryPct!.toStringAsFixed(0)} %',
            spec: _profile.kind == DecoderKind.custom ? _profile.battery : null,
            custom: _profile.kind == DecoderKind.custom,
            onEdit: () => _edit('Battery (%)', _profile.battery, (f) => _profile.copyWith(battery: f)),
            onClear: () => setState(() => _profile = _profile.copyWith(clearBattery: true)),
          ),
          if (_profile.kind == DecoderKind.auto && values.pressureHpa == null && latest != null)
            Card(
              color: scheme.tertiaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No known format found. Switch to "Custom byte layout" and tap "Find" next to Pressure '
                  'while the sensor is in open air – the app compares every plausible byte range against '
                  'your phone\'s barometer (or a value you type in from the vendor app).',
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Use this sensor'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final settings = context.read<SettingsStore>();
    final existing = settings.sensors.where((s) => s.id == widget.deviceId).firstOrNull;
    final name = _name.text.trim().isEmpty ? 'Raft sensor' : _name.text.trim();
    final cfg = (existing ?? SensorConfig(id: widget.deviceId, name: name)).copyWith(name: name, profile: _profile);
    await settings.upsertSensor(cfg, makeActive: true);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _copyLog() async {
    final sb = StringBuffer('Device ${widget.deviceId} "${_latest?.name}"\n');
    for (final p in _packets) {
      sb.write('${p.time.toIso8601String()} rssi=${p.rssi}');
      for (final b in p.blocks) {
        sb.write('  ${b.title}: ${toHex(b.bytes, separator: '')}');
      }
      sb.writeln();
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Packet log copied to clipboard')));
    }
  }

  Future<void> _find(Quantity q) async {
    final baro = context.read<BarometerService>().hpa;
    final isPressure = q == Quantity.pressure;
    final target = TextEditingController(
        text: isPressure ? (baro?.toStringAsFixed(1) ?? '') : '');
    final tol = TextEditingController(text: isPressure ? (baro != null ? '6' : '1') : '1');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isPressure ? 'Find pressure field' : 'Find temperature field'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isPressure
                ? (baro != null
                    ? 'Prefilled from your phone\'s barometer. Keep the sensor in open air, next to the phone. '
                        'If the vendor app shows a reading, typing that in is even better (use a smaller tolerance).'
                    : 'Your phone has no barometer. Enter the pressure the vendor app (Holyiot / NexBeacon) '
                        'shows, or a local weather station\'s station pressure.')
                : 'Enter the temperature the vendor app shows.'),
            const SizedBox(height: 12),
            TextField(
              controller: target,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: isPressure ? 'Expected pressure (hPa / mbar)' : 'Expected temperature (°C)'),
            ),
            TextField(
              controller: tol,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: isPressure ? 'Tolerance (hPa)' : 'Tolerance (°C)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Search')),
        ],
      ),
    );
    final t = double.tryParse(target.text.replaceAll(',', '.'));
    final tl = double.tryParse(tol.text.replaceAll(',', '.'));
    if (go != true || t == null || tl == null || !mounted) return;

    final found = FieldFinder.find(packets: _packets, quantity: q, target: t, tolerance: tl);
    final picked = await showModalBottomSheet<FieldCandidate>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => found.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No byte range matched. Try a larger tolerance, check the value you entered, or use '
                '"Copy packet log" and look at the bytes yourself (or share the log for help).',
              ),
            )
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Best matches first. After choosing, squeeze/warm the sensor and check the value moves.'),
                ),
                for (final c in found)
                  ListTile(
                    title: Text(isPressure ? '${c.value.toStringAsFixed(2)} hPa' : '${c.value.toStringAsFixed(2)} °C'),
                    subtitle: Text('${c.spec.describe()}\n${c.encoding.label}'),
                    isThreeLine: true,
                    trailing: Text('±${c.error.toStringAsFixed(2)}'),
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ],
            ),
    );
    if (picked == null) return;
    setState(() {
      _profile = isPressure
          ? _profile.copyWith(kind: DecoderKind.custom, pressure: picked.spec)
          : _profile.copyWith(kind: DecoderKind.custom, temperature: picked.spec);
    });
  }

  Future<void> _edit(String title, FieldSpec? current, DecoderProfile Function(FieldSpec) apply) async {
    final latest = _latest;
    final blocks = latest?.blocks ?? const <AdBlock>[];
    final initial = current ??
        FieldSpec(
          source: blocks.isNotEmpty ? blocks.first.source : AdSource.serviceData,
          key: blocks.isNotEmpty ? blocks.first.key : '',
          offset: 0,
        );
    final result = await showDialog<FieldSpec>(
      context: context,
      builder: (_) => _FieldSpecDialog(title: title, initial: initial, packet: latest),
    );
    if (result != null) setState(() => _profile = apply(result).copyWith(kind: DecoderKind.custom));
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, required this.changing});

  final AdBlock block;
  final Set<int> changing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${block.title}  (${block.bytes.length} bytes)', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 2,
              runSpacing: 4,
              children: [
                for (var i = 0; i < block.bytes.length; i++)
                  Container(
                    width: 30,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: changing.contains(i) ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        Text(toHex([block.bytes[i]]),
                            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                        Text('$i', style: TextStyle(fontSize: 9, color: scheme.outline)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    required this.spec,
    required this.custom,
    this.onFind,
    required this.onEdit,
    required this.onClear,
  });

  final String label;
  final String? value;
  final FieldSpec? spec;
  final bool custom;
  final VoidCallback? onFind;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(value ?? '—', style: const TextStyle(fontSize: 18)),
                  if (custom)
                    Text(spec?.describe() ?? 'not set',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
            if (onFind != null) TextButton(onPressed: onFind, child: const Text('Find')),
            IconButton(tooltip: 'Edit layout', onPressed: onEdit, icon: const Icon(Icons.edit)),
            if (custom && spec != null) IconButton(tooltip: 'Clear', onPressed: onClear, icon: const Icon(Icons.clear)),
          ],
        ),
      ),
    );
  }
}

class _FieldSpecDialog extends StatefulWidget {
  const _FieldSpecDialog({required this.title, required this.initial, required this.packet});

  final String title;
  final FieldSpec initial;
  final AdvPacket? packet;

  @override
  State<_FieldSpecDialog> createState() => _FieldSpecDialogState();
}

class _FieldSpecDialogState extends State<_FieldSpecDialog> {
  late FieldSpec _spec = widget.initial;
  late final _key = TextEditingController(text: widget.initial.key);
  late final _offset = TextEditingController(text: '${widget.initial.offset}');
  late final _scale = TextEditingController(text: '${widget.initial.scale}');
  late final _add = TextEditingController(text: '${widget.initial.add}');

  void _sync() {
    setState(() {
      _spec = _spec.copyWith(
        key: _key.text.trim().toLowerCase(),
        offset: int.tryParse(_offset.text) ?? _spec.offset,
        scale: double.tryParse(_scale.text.replaceAll(',', '.')) ?? _spec.scale,
        add: double.tryParse(_add.text.replaceAll(',', '.')) ?? _spec.add,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.packet == null ? null : _spec.read(widget.packet!);
    final blocks = widget.packet?.blocks ?? const <AdBlock>[];
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<AdSource>(
              initialValue: _spec.source,
              decoration: const InputDecoration(labelText: 'Source'),
              items: [for (final s in AdSource.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (v) => setState(() => _spec = _spec.copyWith(source: v)),
            ),
            TextField(
              controller: _key,
              decoration: InputDecoration(
                labelText: _spec.source == AdSource.serviceData ? 'Service UUID (hex, e.g. 5242)' : 'Company ID (hex, e.g. ffff)',
                helperText: blocks.isEmpty ? null : 'Seen: ${blocks.map((b) => b.key).join(', ')}',
              ),
              onChanged: (_) => _sync(),
            ),
            TextField(
              controller: _offset,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Byte offset'),
              onChanged: (_) => _sync(),
            ),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _spec.length,
                  decoration: const InputDecoration(labelText: 'Bytes'),
                  items: [for (final l in [1, 2, 3, 4]) DropdownMenuItem(value: l, child: Text('$l'))],
                  onChanged: (v) => setState(() => _spec = _spec.copyWith(length: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<FieldType>(
                  initialValue: _spec.type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [for (final t in FieldType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: (v) => setState(() => _spec = _spec.copyWith(type: v)),
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Little-endian'),
              subtitle: const Text('Least significant byte first (most common)'),
              value: _spec.littleEndian,
              onChanged: (v) => setState(() => _spec = _spec.copyWith(littleEndian: v)),
            ),
            TextField(
              controller: _scale,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Scale (value = raw × scale + add)'),
              onChanged: (_) => _sync(),
            ),
            TextField(
              controller: _add,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Add'),
              onChanged: (_) => _sync(),
            ),
            const SizedBox(height: 12),
            Text('Current value: ${preview?.toStringAsFixed(3) ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _spec), child: const Text('Apply')),
      ],
    );
  }
}
