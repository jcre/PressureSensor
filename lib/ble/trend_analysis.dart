import 'dart:math' as math;
import 'dart:typed_data';

import 'adv_packet.dart';
import 'field_spec.dart';
import 'known_layouts.dart';

enum TrendSort {
  /// Change over the window relative to the field's packet-to-packet jitter,
  /// so a slow real drift (temperature, pressure) beats a noisy low byte.
  smooth('Smooth change'),

  /// Plain max − min as a percentage of the field's typical value.
  range('Biggest range');

  const TrendSort(this.label);

  final String label;
}

class TrendSample {
  const TrendSample(this.time, this.value);

  final DateTime time;
  final double value;
}

/// One way of reading some bytes as a number, with its history.
class TrendField {
  TrendField(this.spec, this.series)
      : first = series.first.value,
        last = series.last.value,
        min = series.map((s) => s.value).reduce(math.min),
        max = series.map((s) => s.value).reduce(math.max),
        jitter = _meanAbsStep(series);

  final FieldSpec spec;
  final List<TrendSample> series;
  final double first;
  final double last;
  final double min;
  final double max;

  /// Mean absolute change between consecutive packets.
  final double jitter;

  double get range => max - min;

  /// Range in units of jitter: how cleanly it moved, independent of the
  /// field's scale. Tiny moves (a byte flipping by 1) are discounted.
  double get smoothScore {
    if (jitter == 0) return 0;
    final steps = range / jitter;
    return steps * (1 - math.exp(-range / 5));
  }

  /// Range as a % of the field's typical magnitude.
  double get rangePercent {
    final mag = math.max(max.abs(), min.abs());
    return mag == 0 ? 0 : 100 * range / mag;
  }

  static double _meanAbsStep(List<TrendSample> s) {
    if (s.length < 2) return 0;
    var sum = 0.0;
    for (var i = 1; i < s.length; i++) {
      sum += (s[i].value - s[i - 1].value).abs();
    }
    return sum / (s.length - 1);
  }
}

/// Reads every plausible field out of a device's recent packets and ranks
/// them by how much they changed, to spot pressure/temperature bytes by
/// watching them move (squeeze the sensor, warm it in your hand…).
class TrendAnalysis {
  static const _shapes = <(int, bool)>[
    (1, true),
    (2, true),
    (2, false),
    (3, true),
    (3, false),
    (4, true),
    (4, false),
  ];

  static List<TrendField> analyze(
    List<AdvPacket> packets, {
    TrendSort sort = TrendSort.smooth,
    int maxResults = 30,
  }) {
    if (packets.length < 2) return const [];
    final latest = packets.last;
    final known = KnownLayouts.annotate(latest);
    final out = <TrendField>[];
    final histories = <String, List<List<int>>>{};

    for (final block in latest.blocks) {
      final labels = known[KnownLayouts.blockId(block)] ?? const {};
      final history = [
        for (final p in packets)
          if (p.bytesFor(block.source, block.key) case final b? when b.length == block.bytes.length) (p.time, b),
      ];
      if (history.length < 2) continue;
      final raw = [for (final h in history) h.$2];
      histories[KnownLayouts.blockId(block)] = raw;
      final random = {for (var i = 0; i < block.bytes.length; i++) if (_byteJitter(raw, i) >= 64) i};

      for (final (len, le) in _shapes) {
        for (var off = 0; off + len <= block.bytes.length; off++) {
          // Skip fields that include MAC/battery bytes we already know about.
          final bytes = List.generate(len, (i) => off + i);
          if (bytes.any(labels.containsKey)) continue;
          // Random-looking bytes only make sense on their own.
          if (len > 1 && bytes.any(random.contains)) continue;
          // A changing number whose lowest byte never changes is almost always
          // a real field read with an extra constant byte tacked on.
          final lsb = le ? off : off + len - 1;
          if (len > 1 && history.every((h) => h.$2[lsb] == history.first.$2[lsb])) continue;

          TrendField? best;
          for (final type in len == 1 ? const [FieldType.uint] : const [FieldType.uint, FieldType.sint]) {
            final spec = FieldSpec(
              source: block.source,
              key: block.key,
              offset: off,
              length: len,
              type: type,
              littleEndian: le,
            );
            final series = [
              for (final (t, b) in history) TrendSample(t, spec.readBytes(b)!),
            ];
            final f = TrendField(spec, series);
            if (f.range == 0) break; // constant: same for the signed read
            // Signed vs unsigned: keep whichever reads less jumpily.
            if (best == null || f.jitter < best.jitter) best = f;
          }
          if (best != null) out.add(best);
        }
      }
    }

    double score(TrendField f) => sort == TrendSort.smooth ? f.smoothScore : f.rangePercent;
    out.sort((a, b) {
      final c = score(b).compareTo(score(a));
      return c != 0 ? c : a.spec.length.compareTo(b.spec.length);
    });

    bool overlap(FieldSpec a, FieldSpec b) =>
        a.source == b.source &&
        a.key == b.key &&
        a.offset < b.offset + b.length &&
        b.offset < a.offset + a.length;

    // One reading per group of bytes, grown into the whole number it belongs to.
    final chosen = <TrendField>[];
    for (final f in out) {
      final id = '${f.spec.source.name}:${f.spec.key}';
      final grown = _grow(f, histories[id]!, known[id] ?? const {});
      if (chosen.any((c) => overlap(c.spec, grown.spec) || overlap(c.spec, f.spec))) continue;
      chosen.add(grown);
      if (chosen.length >= maxResults) break;
    }
    return chosen;
  }

  /// Mean absolute step of one byte; a random byte averages ~85.
  static double _byteJitter(List<List<int>> h, int i) {
    var sum = 0;
    for (var k = 1; k < h.length; k++) {
      sum += (h[k][i] - h[k - 1][i]).abs();
    }
    return sum / (h.length - 1);
  }

  /// Widens [f] to the full multi-byte value it is probably part of: a less
  /// significant neighbour is added if it changes but isn't random, a more
  /// significant one if it is steady (the top byte of the same number).
  static TrendField _grow(TrendField f, List<List<int>> h, Map<int, String> labels) {
    final width = h.first.length;
    var lo = f.spec.offset;
    var hi = f.spec.offset + f.spec.length - 1;
    bool usable(int i) => i >= 0 && i < width && !labels.containsKey(i);
    bool lowByteLike(int i) => usable(i) && h.any((b) => b[i] != h.first[i]) && _byteJitter(h, i) < 64;
    // A single byte doesn't tell us the byte order: follow its low-byte-like
    // neighbour (left for little-endian, right for big-endian).
    final le = f.spec.length > 1 ? f.spec.littleEndian : (lowByteLike(lo - 1) || !lowByteLike(hi + 1));

    while (hi - lo + 1 < 4) {
      final lsbSide = le ? lo - 1 : hi + 1;
      final msbSide = le ? hi + 1 : lo - 1;
      if (lowByteLike(lsbSide)) {
        le ? lo-- : hi++;
      } else if (usable(msbSide) && hi - lo + 1 < 3 && _byteJitter(h, msbSide) < 1) {
        le ? hi++ : lo--;
      } else {
        break;
      }
    }
    if (lo == f.spec.offset && hi == f.spec.offset + f.spec.length - 1) return f;

    TrendField? best;
    for (final type in const [FieldType.uint, FieldType.sint]) {
      final spec = f.spec.copyWith(offset: lo, length: hi - lo + 1, type: type, littleEndian: le);
      final series = [
        for (var k = 0; k < h.length; k++) TrendSample(f.series[k].time, spec.readBytes(Uint8List.fromList(h[k]))!),
      ];
      final g = TrendField(spec, series);
      if (best == null || g.jitter < best.jitter) best = g;
    }
    return best!;
  }
}
