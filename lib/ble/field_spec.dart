import 'dart:typed_data';

import 'adv_packet.dart';

enum FieldType {
  uint('Unsigned int'),
  sint('Signed int'),
  float32('Float32');

  const FieldType(this.label);

  final String label;

  static FieldType byName(String? name) =>
      FieldType.values.firstWhere((t) => t.name == name, orElse: () => FieldType.uint);
}

/// Describes where one value lives inside an advertisement and how to scale it:
///
///   value = raw * scale + add
///
/// Offsets are relative to the start of the service data (after the UUID) or
/// manufacturer data (after the company ID).
class FieldSpec {
  const FieldSpec({
    required this.source,
    required this.key,
    required this.offset,
    this.length = 2,
    this.type = FieldType.uint,
    this.littleEndian = true,
    this.scale = 1,
    this.add = 0,
  });

  final AdSource source;
  final String key;
  final int offset;
  final int length;
  final FieldType type;
  final bool littleEndian;
  final double scale;
  final double add;

  double? read(AdvPacket packet) {
    final bytes = packet.bytesFor(source, key);
    return bytes == null ? null : readBytes(bytes);
  }

  double? readBytes(Uint8List bytes) {
    final raw = readRaw(bytes, offset, length, type, littleEndian);
    if (raw == null || raw.isNaN || raw.isInfinite) return null;
    return raw * scale + add;
  }

  static double? readRaw(Uint8List bytes, int offset, int length, FieldType type, bool littleEndian) {
    if (offset < 0 || length < 1 || length > 4 || offset + length > bytes.length) return null;
    if (type == FieldType.float32) {
      if (length != 4) return null;
      final bd = ByteData.sublistView(bytes, offset, offset + 4);
      return bd.getFloat32(0, littleEndian ? Endian.little : Endian.big);
    }
    var v = 0;
    for (var i = 0; i < length; i++) {
      final b = littleEndian ? bytes[offset + length - 1 - i] : bytes[offset + i];
      v = (v << 8) | b;
    }
    if (type == FieldType.sint) {
      final signBit = 1 << (length * 8 - 1);
      if (v & signBit != 0) v -= 1 << (length * 8);
    }
    return v.toDouble();
  }

  String describe() {
    final where = source == AdSource.serviceData ? 'svc 0x$key' : 'mfr 0x$key';
    final t = type == FieldType.float32 ? 'float32' : '${type == FieldType.sint ? 's' : 'u'}int${length * 8}';
    final end = length > 1 ? (littleEndian ? ' LE' : ' BE') : '';
    final addStr = add == 0 ? '' : ' ${add >= 0 ? '+' : '-'} ${add.abs()}';
    return '$where @$offset $t$end × $scale$addStr';
  }

  FieldSpec copyWith({
    AdSource? source,
    String? key,
    int? offset,
    int? length,
    FieldType? type,
    bool? littleEndian,
    double? scale,
    double? add,
  }) =>
      FieldSpec(
        source: source ?? this.source,
        key: key ?? this.key,
        offset: offset ?? this.offset,
        length: length ?? this.length,
        type: type ?? this.type,
        littleEndian: littleEndian ?? this.littleEndian,
        scale: scale ?? this.scale,
        add: add ?? this.add,
      );

  Map<String, dynamic> toJson() => {
        'source': source.name,
        'key': key,
        'offset': offset,
        'length': length,
        'type': type.name,
        'littleEndian': littleEndian,
        'scale': scale,
        'add': add,
      };

  factory FieldSpec.fromJson(Map<String, dynamic> j) => FieldSpec(
        source: AdSource.byName(j['source'] as String?),
        key: j['key'] as String? ?? '',
        offset: (j['offset'] as num?)?.toInt() ?? 0,
        length: (j['length'] as num?)?.toInt() ?? 2,
        type: FieldType.byName(j['type'] as String?),
        littleEndian: j['littleEndian'] as bool? ?? true,
        scale: (j['scale'] as num?)?.toDouble() ?? 1,
        add: (j['add'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is FieldSpec &&
      other.source == source &&
      other.key == key &&
      other.offset == offset &&
      other.length == length &&
      other.type == type &&
      other.littleEndian == littleEndian &&
      other.scale == scale &&
      other.add == add;

  @override
  int get hashCode => Object.hash(source, key, offset, length, type, littleEndian, scale, add);
}
