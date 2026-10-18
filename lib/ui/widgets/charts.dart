import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A "nice" axis step (1, 2, 2.5, 5 × 10^n) giving about [ticks] divisions.
double niceStep(double range, int ticks) {
  if (range <= 0) return 1;
  final raw = range / ticks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (raw <= m * mag) return m * mag;
  }
  return 10 * mag;
}

String _tick(double v, double step) => v.toStringAsFixed(step >= 1 ? 0 : step >= 0.1 ? 1 : 2);

bool _onStep(double v, double step) => ((v / step) - (v / step).round()).abs() < 0.01;

/// Tiny line chart without axes, used in sensor rows.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color, this.height = 36});
  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    final mn = values.reduce(math.min), mx = values.reduce(math.max);
    final pad = (mx - mn).abs() < 1e-6 ? 1.0 : (mx - mn) * 0.15;
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: mn - pad,
          maxY: mx + pad,
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
              isCurved: true,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}

/// Time-series chart with axes for live data, battery test and trends.
class TimeChart extends StatelessWidget {
  const TimeChart({
    super.key,
    required this.points,
    required this.color,
    this.minY,
    this.maxY,
    this.height = 160,
    this.xLabel,
    this.bands = const [],
    this.xFormatter,
  });

  /// (x, y) pairs.
  final List<(double, double)> points;
  final Color color;
  final double? minY, maxY;
  final double height;
  final String? xLabel;

  /// Horizontal reference bands: (from, to, colour), e.g. the normal range.
  final List<(double, double, Color)> bands;
  final String Function(double)? xFormatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.isEmpty) {
      return SizedBox(height: height, child: Center(child: Text('Waiting for data…', style: theme.textTheme.bodySmall)));
    }
    final ys = points.map((p) => p.$2);
    var lo = minY ?? ys.reduce(math.min);
    var hi = maxY ?? ys.reduce(math.max);
    if ((hi - lo).abs() < 1e-6) {
      lo -= 1;
      hi += 1;
    } else if (minY == null || maxY == null) {
      final pad = (hi - lo) * 0.12;
      if (minY == null) lo -= pad;
      if (maxY == null) hi += pad;
    }
    final style = theme.textTheme.labelSmall;
    final x0 = points.first.$1;
    final x1 = math.max(points.last.$1, points.first.$1 + 1);
    final xStep = xFormatter == null ? niceStep(x1 - x0, 6) : math.max(1.0, niceStep(x1 - x0, 6).roundToDouble());
    final yStep = niceStep(hi - lo, 4);
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: lo,
          maxY: hi,
          minX: x0,
          maxX: x1,
          clipData: const FlClipData.all(),
          rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
            for (final b in bands) HorizontalRangeAnnotation(y1: b.$1, y2: b.$2, color: b.$3.withValues(alpha: 0.10)),
          ]),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: yStep,
            getDrawingHorizontalLine: (_) => FlLine(color: theme.dividerColor.withValues(alpha: 0.4), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: yStep,
                getTitlesWidget: (v, meta) => !_onStep(v, yStep)
                    ? const SizedBox.shrink()
                    : SideTitleWidget(meta: meta, child: Text(_tick(v, yStep), style: style)),
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: xLabel == null ? null : Text(xLabel!, style: style),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: xStep,
                getTitlesWidget: (v, meta) => !_onStep(v, xStep)
                    ? const SizedBox.shrink()
                    : SideTitleWidget(meta: meta, child: Text(xFormatter?.call(v) ?? _tick(v, xStep), style: style)),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(s.y.toStringAsFixed(2), TextStyle(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final p in points) FlSpot(p.$1, p.$2)],
              isCurved: points.length > 3,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 2.5,
              dotData: FlDotData(show: points.length < 25),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.10)),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}
