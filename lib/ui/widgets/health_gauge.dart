import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../diagnostics/models.dart';
import '../theme.dart';

/// Large 240° dial showing the 0–100 health score.
class HealthGauge extends StatelessWidget {
  const HealthGauge({super.key, required this.score, required this.status, this.size = 220, this.label = 'Health score'});
  final int score;
  final Status status;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size * 0.86,
        child: CustomPaint(
          painter: _GaugePainter(
            value: v / 100,
            track: Theme.of(context).colorScheme.surfaceContainerHighest,
            colors: [statusColor(Status.fail, b), statusColor(Status.warn, b), statusColor(Status.ok, b)],
          ),
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${v.round()}',
                  style: TextStyle(fontSize: size * 0.26, fontWeight: FontWeight.w800, color: statusColor(status, b), height: 1)),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                switch (status) {
                  Status.ok => 'Good condition',
                  Status.warn => 'Needs attention',
                  Status.fail => 'Problems found',
                  Status.info => '—',
                },
                style: TextStyle(color: statusColor(status, b), fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.track, required this.colors});
  final double value;
  final Color track;
  final List<Color> colors;

  static const _start = math.pi * 5 / 6; // 150°
  static const _sweep = math.pi * 4 / 3; // 240°

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final r = size.width / 2 - stroke / 2;
    final center = Offset(size.width / 2, size.width / 2);
    final rect = Rect.fromCircle(center: center, radius: r);

    canvas.drawArc(
        rect,
        _start,
        _sweep,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round);

    final gradient = SweepGradient(
      // Start slightly before the arc so the round end-cap stays red.
      endAngle: _sweep + 0.4,
      colors: colors,
      stops: const [0.25, 0.6, 0.85],
      transform: const GradientRotation(_start - 0.2),
    );
    if (value > 0) {
      canvas.drawArc(
          rect,
          _start,
          _sweep * value.clamp(0, 1),
          false,
          Paint()
            ..shader = gradient.createShader(rect)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round);
    }

    // Tick marks every 10 points.
    final tick = Paint()
      ..color = track.withValues(alpha: 1)
      ..strokeWidth = 2;
    for (var i = 0; i <= 10; i++) {
      final a = _start + _sweep * i / 10;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * (r - stroke * 0.9);
      final p2 = center + Offset(math.cos(a), math.sin(a)) * (r - stroke * 1.4);
      canvas.drawLine(p1, p2, tick);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.track != track;
}

/// Small semicircle meter for a single live value.
class MiniMeter extends StatelessWidget {
  const MiniMeter({super.key, required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(56, 32),
        painter: _MiniPainter(fraction.clamp(0, 1), color, Theme.of(context).colorScheme.surfaceContainerHighest),
      );
}

class _MiniPainter extends CustomPainter {
  _MiniPainter(this.f, this.c, this.track);
  final double f;
  final Color c, track;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Rect.fromLTWH(4, 4, s.width - 8, (s.height - 4) * 2 - 4);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, p..color = track);
    canvas.drawArc(rect, math.pi, math.pi * f, false, p..color = c);
  }

  @override
  bool shouldRepaint(_MiniPainter o) => o.f != f || o.c != c;
}
