import 'adv_packet.dart';
import 'field_spec.dart';

enum Quantity { pressure, temperature }

class Encoding {
  const Encoding(this.length, this.type, this.scale, this.label, [this.prior = 0]);

  final int length;
  final FieldType type;
  final double scale;
  final String label;

  /// Ranking penalty: how unusual this encoding is. Exotic encodings can match
  /// by accident, e.g. "Pa × 256" read one byte early is just a Pa field.
  final double prior;
}

/// Common ways cheap sensor beacons pack values. Pressure results are hPa.
const pressureEncodings = <Encoding>[
  Encoding(3, FieldType.uint, 0.01, 'Pa (or 0.01 hPa)'),
  Encoding(4, FieldType.uint, 0.01, 'Pa (or 0.01 hPa)', 0.05),
  Encoding(2, FieldType.uint, 0.1, '0.1 hPa', 0.05),
  Encoding(3, FieldType.uint, 0.001, '0.1 Pa', 0.1),
  Encoding(4, FieldType.uint, 0.001, '0.1 Pa', 0.1),
  Encoding(4, FieldType.float32, 1, 'float hPa', 0.2),
  Encoding(4, FieldType.float32, 0.01, 'float Pa', 0.2),
  Encoding(2, FieldType.uint, 1, 'hPa', 0.3),
  Encoding(3, FieldType.uint, 1 / 4096, 'hPa × 4096 (LPS22 raw)', 0.4),
  Encoding(4, FieldType.uint, 0.01 / 256, 'Pa × 256 (BMP280 Q24.8)', 0.5),
];

/// Temperature results are °C.
const temperatureEncodings = <Encoding>[
  Encoding(2, FieldType.sint, 0.01, '0.01 °C'),
  Encoding(2, FieldType.sint, 0.1, '0.1 °C', 0.05),
  Encoding(4, FieldType.float32, 1, 'float °C', 0.2),
  Encoding(2, FieldType.sint, 1 / 256, '°C × 256 (8.8 fixed point)', 0.3),
  Encoding(1, FieldType.sint, 1, '°C', 0.4),
];

class FieldCandidate {
  const FieldCandidate({required this.spec, required this.encoding, required this.value, required this.error});

  final FieldSpec spec;
  final Encoding encoding;

  /// Decoded value from the most recent packet.
  final double value;

  /// Mean absolute difference from the target across all packets.
  final double error;
}

/// Searches advertisement payloads for byte ranges that decode to a known
/// value, e.g. the phone's barometer reading while the tag sits in open air,
/// or the number the vendor's app shows.
class FieldFinder {
  static List<FieldCandidate> find({
    required List<AdvPacket> packets,
    required Quantity quantity,
    required double target,
    required double tolerance,
    int maxResults = 25,
  }) {
    if (packets.isEmpty) return const [];
    final encodings = quantity == Quantity.pressure ? pressureEncodings : temperatureEncodings;
    final latest = packets.last;
    final results = <FieldCandidate>[];

    for (final block in latest.blocks) {
      final samples = [for (final p in packets) ?p.bytesFor(block.source, block.key)];
      for (final enc in encodings) {
        final endians = enc.length == 1 ? const [true] : const [true, false];
        for (final le in endians) {
          for (var offset = 0; offset + enc.length <= block.bytes.length; offset++) {
            final spec = FieldSpec(
              source: block.source,
              key: block.key,
              offset: offset,
              length: enc.length,
              type: enc.type,
              littleEndian: le,
              scale: enc.scale,
            );
            var sumErr = 0.0;
            var ok = true;
            for (final s in samples) {
              final v = spec.readBytes(s);
              if (v == null || (v - target).abs() > tolerance) {
                ok = false;
                break;
              }
              sumErr += (v - target).abs();
            }
            if (!ok || samples.isEmpty) continue;
            results.add(FieldCandidate(
              spec: spec,
              encoding: enc,
              value: spec.readBytes(block.bytes)!,
              error: sumErr / samples.length,
            ));
          }
        }
      }
    }

    // Closest match first, nudged towards common encodings.
    double score(FieldCandidate c) => c.error / tolerance + c.encoding.prior;
    results.sort((a, b) => score(a).compareTo(score(b)));
    return results.take(maxResults).toList();
  }
}
