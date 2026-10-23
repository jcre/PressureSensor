import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/adv_packet.dart';
import '../ble/decoder.dart';
import '../services/ble_scanner.dart';
import '../services/settings_store.dart';
import 'inspector_screen.dart';

/// Lists nearby BLE devices so the user can pick their tag.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final BleScanner _scanner;
  bool _onlyWithData = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _scanner = context.read<BleScanner>();
    _scanner.beginDiscovery();
  }

  @override
  void dispose() {
    _scanner.endDiscovery();
    super.dispose();
  }

  static bool _looksLikeTag(AdvPacket p) {
    final n = p.name.toLowerCase();
    return n.contains('holy') || n.contains('nexbeacon') || n.contains('beacon');
  }

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<BleScanner>();
    final settings = context.watch<SettingsStore>();
    final known = {for (final s in settings.sensors) s.id: s};
    final now = DateTime.now();
    final devices = scanner.seen.values.where((p) {
      if (now.difference(p.time) > const Duration(seconds: 30)) return false;
      if (_onlyWithData && !p.hasPayload) return false;
      if (_filter.isNotEmpty &&
          !p.name.toLowerCase().contains(_filter) &&
          !p.deviceId.toLowerCase().contains(_filter)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final ta = _looksLikeTag(a) || known.containsKey(a.deviceId);
        final tb = _looksLikeTag(b) || known.containsKey(b.deviceId);
        if (ta != tb) return ta ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find sensor'),
        bottom: scanner.scanning
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter by name or address',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.toLowerCase().trim()),
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Only devices broadcasting data'),
            value: _onlyWithData,
            onChanged: (v) => setState(() => _onlyWithData = v),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Tip: hold the tag right next to the phone. The strongest signal (closest to 0 dBm) is usually yours.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (scanner.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(scanner.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: devices.isEmpty
                ? const Center(child: Text('Searching…'))
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = devices[i];
                      final cfg = known[p.deviceId];
                      final v = AdvDecoder.decode(p, cfg?.profile ?? const DecoderProfile());
                      final blocks = p.blocks.map((b) => b.title).join(', ');
                      return ListTile(
                        leading: Icon(
                          cfg != null ? Icons.star : (_looksLikeTag(p) ? Icons.sensors : Icons.bluetooth),
                          color: cfg != null || _looksLikeTag(p) ? Theme.of(context).colorScheme.primary : null,
                        ),
                        title: Text(cfg?.name ?? (p.name.isEmpty ? '(no name)' : p.name)),
                        subtitle: Text(
                          '${p.deviceId}\n${blocks.isEmpty ? 'no payload' : blocks}'
                          '${v.pressureHpa != null ? '\nPressure ${v.pressureHpa!.toStringAsFixed(2)} hPa' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: Text('${p.rssi} dBm'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => InspectorScreen(deviceId: p.deviceId)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
