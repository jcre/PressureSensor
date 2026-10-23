import 'dart:typed_data';

/// A platform-neutral snapshot of one BLE advertisement (merged with its scan
/// response, which Android and iOS both do for us).
///
/// Byte arrays follow the same convention as ESPHome / nRF Connect "service
/// data" and "manufacturer data": service data bytes start *after* the UUID,
/// manufacturer data bytes start *after* the 2-byte company ID.
class AdvPacket {
  AdvPacket({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.time,
    Map<String, List<int>> serviceData = const {},
    Map<int, List<int>> manufacturerData = const {},
    this.serviceUuids = const [],
    this.txPower,
    this.connectable = false,
  })  : serviceData = {
          for (final e in serviceData.entries) normalizeUuid(e.key): Uint8List.fromList(e.value),
        },
        manufacturerData = {
          for (final e in manufacturerData.entries) e.key: Uint8List.fromList(e.value),
        };

  final String deviceId;
  final String name;
  final int rssi;
  final DateTime time;

  /// Keyed by normalised UUID: 4 hex chars for 16-bit SIG UUIDs ("fcd2"),
  /// otherwise the full lowercase 128-bit string.
  final Map<String, Uint8List> serviceData;

  /// Keyed by Bluetooth SIG company ID (0xFFFF is the "test/no company" ID
  /// many cheap beacons use).
  final Map<int, Uint8List> manufacturerData;

  final List<String> serviceUuids;
  final int? txPower;
  final bool connectable;

  bool get hasPayload => serviceData.isNotEmpty || manufacturerData.isNotEmpty;

  /// Bytes for a given source/key, or null when not present in this packet.
  Uint8List? bytesFor(AdSource source, String key) {
    switch (source) {
      case AdSource.serviceData:
        return serviceData[normalizeUuid(key)];
      case AdSource.manufacturerData:
        final id = int.tryParse(key, radix: 16);
        return id == null ? null : manufacturerData[id];
    }
  }

  /// Every payload block in this packet, for the inspector and field finder.
  List<AdBlock> get blocks => [
        for (final e in serviceData.entries) AdBlock(AdSource.serviceData, e.key, e.value),
        for (final e in manufacturerData.entries)
          AdBlock(AdSource.manufacturerData, companyKey(e.key), e.value),
      ];

  static String companyKey(int id) => id.toRadixString(16).padLeft(4, '0');

  static const _sigBaseSuffix = '-0000-1000-8000-00805f9b34fb';

  /// "0000FCD2-0000-1000-8000-00805F9B34FB" -> "fcd2", "FCD2" -> "fcd2".
  static String normalizeUuid(String uuid) {
    final u = uuid.toLowerCase().trim();
    if (u.length == 36 && u.startsWith('0000') && u.endsWith(_sigBaseSuffix)) {
      return u.substring(4, 8);
    }
    if (u.length == 36 && u.endsWith(_sigBaseSuffix)) {
      return u.substring(0, 8);
    }
    return u;
  }
}

enum AdSource {
  serviceData('Service data'),
  manufacturerData('Manufacturer data');

  const AdSource(this.label);

  final String label;

  static AdSource byName(String? name) =>
      AdSource.values.firstWhere((s) => s.name == name, orElse: () => AdSource.serviceData);
}

/// One payload block in an advertisement.
class AdBlock {
  const AdBlock(this.source, this.key, this.bytes);

  final AdSource source;

  /// Service UUID (normalised) or company ID as 4 hex chars.
  final String key;
  final Uint8List bytes;

  String get title => source == AdSource.serviceData ? 'Service 0x$key' : 'Manufacturer 0x$key';
}

String toHex(List<int> bytes, {String separator = ' '}) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(separator).toUpperCase();
