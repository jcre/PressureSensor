import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/trip.dart';
import '../../models/units.dart';

/// Pressure-over-time line chart with optional high/low threshold lines.
class PressureChart extends StatelessWidget {
  const PressureChart({
    super.key,
    required this.readings,
    required this.unit,
    this.display = PressureDisplay.gauge,
    this.highHpa,
    this.lowHpa,
    this.windowStart,
    this.windowEnd,
    this.selected,
    this.onSelect,
    this.maxPoints = 1200,
  });

  final List<Reading> readings;
  final PressureUnit unit;
  final PressureDisplay display;

  /// Gauge thresholds (only drawn in gauge mode).
  final double? highHpa;
  final double? lowHpa;

  final DateTime? windowStart;
  final DateTime? windowEnd;
  final DateTime? selected;
  final ValueChanged<DateTime?>? onSelect;
  final int maxPoints;

  double _value(Reading r) => unit.fromHpa(display == PressureDisplay.gauge ? r.gaugeHpa : r.absHpa);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var data = readings;
    if (windowStart != null) {
      final first = data.indexWhere((r) => !r.time.isBefore(windowStart!));
      data = first < 0 ? const [] : data.sublist(first);
    }
    if (data.isEmpty) {
      return Center(child: Text('No readings yet', style: TextStyle(color: scheme.outline)));
    }

    final origin = windowStart ?? data.first.time;
    final end = windowEnd ?? data.last.time;
    double x(DateTime t) => t.difference(origin).inMilliseconds / 1000.0;

    final step = math.max(1, (data.length / maxPoints).ceil());
    final spots = <FlSpot>[
      for (var i = 0; i < data.length; i += step) FlSpot(x(data[i].time), _value(data[i])),
      if ((data.length - 1) % step != 0) FlSpot(x(data.last.time), _value(data.last)),
    ];

    final gaugeMode = display == PressureDisplay.gauge;
    var minY = spots.map((s) => s.y).reduce(math.min);
    var maxY = spots.map((s) => s.y).reduce(math.max);
    if (gaugeMode) {
      for (final t in [highHpa, lowHpa]) {
        if (t != null) {
          minY = math.min(minY, unit.fromHpa(t));
          maxY = math.max(maxY, unit.fromHpa(t));
        }
      }
      minY = math.min(minY, 0);
    }
    final pad = math.max((maxY - minY) * 0.1, unit.fromHpa(2));
    minY -= pad;
    maxY += pad;

    final spanSec = math.max(x(end), 1.0);
    final xInterval = _niceInterval(spanSec);
    final timeFmt = xInterval >= 60 ? DateFormat.Hm() : DateFormat.Hms();

    HorizontalLine threshold(double hpa, Color c, String label) => HorizontalLine(
          y: unit.fromHpa(hpa),
          color: c,
          strokeWidth: 1.5,
          dashArray: const [6, 4],
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.topRight,
            style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600),
            labelResolver: (_) => '$label ${unit.format(hpa)}',
          ),
        );

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        minX: 0,
        maxX: spanSec,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: true,
          verticalInterval: xInterval,
          getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 0.5),
          getDrawingVerticalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(v.toStringAsFixed(unit.decimals),
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: xInterval,
              getTitlesWidget: (v, meta) {
                // The last label would be clipped at the right edge.
                if (v > meta.max - xInterval * 0.5) return const SizedBox.shrink();
                final t = origin.add(Duration(milliseconds: (v * 1000).round()));
                return SideTitleWidget(meta: meta, child: Text(timeFmt.format(t), style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (gaugeMode && highHpa != null) threshold(highHpa!, Colors.green.shade600, 'High'),
            if (gaugeMode && lowHpa != null) threshold(lowHpa!, Colors.red.shade600, 'Low'),
          ],
          verticalLines: [
            if (selected != null)
              VerticalLine(x: x(selected!), color: scheme.tertiary, strokeWidth: 1.5),
          ],
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchCallback: onSelect == null
              ? null
              : (event, response) {
                  final spot = response?.lineBarSpots?.firstOrNull;
                  if (spot != null) {
                    onSelect!(origin.add(Duration(milliseconds: (spot.x * 1000).round())));
                  }
                },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            fitInsideHorizontally: true,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.y.toStringAsFixed(unit.decimals + 1)} ${unit.label}\n'
                  '${DateFormat.Hms().format(origin.add(Duration(milliseconds: (s.x * 1000).round())))}',
                  TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: scheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: scheme.primary.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }

  static double _niceInterval(double spanSec) {
    const steps = [10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 10800, 21600];
    for (final s in steps) {
      if (spanSec / s <= 5) return s.toDouble();
    }
    return 43200;
  }
}
