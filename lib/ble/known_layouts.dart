import 'dart:typed_data';

import 'adv_packet.dart';
import 'bthome.dart';

/// Byte layouts we know from other projects, used to decode battery
/// automatically and to label bytes in the inspector so the unknown ones
/// (pressure candidates) stand out.
///
/// * Holyiot app firmware: service data 0x5242, battery % at byte 1
///   (ESPHome community configs; xxddff/HolyIot-home-assistant).
/// * NexBeacon Pro firmware: service data 0x180A, battery % in the last byte
///   (xxddff/HolyIot-home-assistant PR #22).
///
/// Both also carry the tag's MAC address, which [annotate] finds by value.
class KnownLayouts {
  static const holyiotUuid = '5242';
  static const nexbeaconUuid = '180a';

  /// 0xFF means "unknown" in both firmwares.
  static const _unknownBattery = 0xff;

  static double? battery(AdvPacket p) {
    final holy = p.serviceData[holyiotUuid];
    if (holy != null && holy.length >= 2 && holy[1] != _unknownBattery && holy[1] <= 100) {
      return holy[1].toDouble();
    }
    final nex = p.serviceData[nexbeaconUuid];
    if (nex != null && nex.isNotEmpty && nex.last != _unknownBattery && nex.last <= 100) {
      return nex.last.toDouble();
    }
    return null;
  }

  /// Labels for known bytes, keyed by [blockId] then byte index.
  static Map<String, Map<int, String>> annotate(AdvPacket p) {
    final out = <String, Map<int, String>>{};
    final mac = _macBytes(p.deviceId);
    for (final block in p.blocks) {
      final labels = <int, String>{};
      if (mac != null) {
        for (final candidate in [mac, mac.reversed.toList()]) {
          final at = _indexOf(block.bytes, candidate);
          if (at >= 0) {
            for (var i = 0; i < 6; i++) {
              labels[at + i] = 'MAC';
            }
            break;
          }
        }
      }
      if (block.source == AdSource.serviceData && block.key == BTHome.serviceUuid) {
        for (final i in BTHome.structureBytes(block.bytes) ?? const <int>{}) {
          labels[i] = i == 0 ? 'hdr' : 'id';
        }
      }
      if (block.source == AdSource.serviceData) {
        if (block.key == holyiotUuid && block.bytes.length >= 2) labels[1] = 'batt';
        if (block.key == nexbeaconUuid && block.bytes.isNotEmpty) labels[block.bytes.length - 1] = 'batt';
      }
      if (labels.isNotEmpty) out[blockId(block)] = labels;
    }
    return out;
  }

  static String blockId(AdBlock b) => '${b.source.name}:${b.key}';

  /// "AA:BB:CC:DD:EE:FF" -> bytes; null for iOS-style UUID ids.
  static List<int>? _macBytes(String id) {
    final parts = id.split(':');
    if (parts.length != 6) return null;
    final bytes = [for (final s in parts) int.tryParse(s, radix: 16)];
    return bytes.contains(null) ? null : bytes.cast<int>();
  }

  static int _indexOf(Uint8List hay, List<int> needle) {
    for (var i = 0; i + needle.length <= hay.length; i++) {
      var ok = true;
      for (var j = 0; j < needle.length && ok; j++) {
        ok = hay[i + j] == needle[j];
      }
      if (ok) return i;
    }
    return -1;
  }
}
