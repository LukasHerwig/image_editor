import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared ruler [CustomPainter] used by both the crop and adjustment control
/// panels.
///
/// Draws an iOS-style tick ruler centred on [angle] (degrees).  Ticks are
/// clamped to ±[maxRange] so the ruler never scrolls past its hard stops.
/// The [pxPerDeg] constant controls how many pixels equal one degree of travel
/// and must match the value used in the owning widget's drag handler.
class EditorRulerPainter extends CustomPainter {
  final double angle;
  final double maxRange;

  const EditorRulerPainter({required this.angle, this.maxRange = 45.0});

  /// How many logical pixels correspond to one degree of ruler travel.
  /// Callers must use this constant in their drag-delta calculations.
  static const double pxPerDeg = 5.0;

  static const double _majorEvery = 5.0;
  static const double _minorEvery = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final double majorH = size.height * 0.55;
    final double minorH = size.height * 0.28;
    final double medH = size.height * 0.40;

    final tickPaint = Paint()
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final centrePaint = Paint()
      ..color = const Color(0xFFFFCC00)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Clamp to hard stops so ticks never extend beyond the allowed range.
    final double visibleDeg = (size.width / 2) / pxPerDeg + 2;
    final double startDeg =
        math.max(-maxRange, (angle - visibleDeg).floorToDouble());
    final double endDeg =
        math.min(maxRange, (angle + visibleDeg).ceilToDouble());

    for (double deg = startDeg; deg <= endDeg; deg += _minorEvery) {
      final double x = cx + (deg - angle) * pxPerDeg;
      if (x < 0 || x > size.width) continue;

      final bool isMajor = (deg % _majorEvery).abs() < 0.01;
      final bool isMed = (deg % 5 != 0) && (deg % 5).abs() < 2.51;
      final double h = isMajor ? majorH : (isMed ? medH : minorH);

      // Fade ticks near the edges.
      final double distFromCentre = (x - cx).abs() / (size.width / 2);
      final double opacity =
          (1.0 - math.pow(distFromCentre, 2)).clamp(0.15, 1.0).toDouble();

      tickPaint.color = isMajor
          ? Colors.white.withValues(alpha: opacity)
          : Colors.white54.withValues(alpha: opacity * 0.7);

      canvas.drawLine(
        Offset(x, cy - h / 2),
        Offset(x, cy + h / 2),
        tickPaint,
      );
    }

    // Fixed centre indicator line.
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height * 0.72),
      centrePaint,
    );
  }

  @override
  bool shouldRepaint(EditorRulerPainter old) =>
      old.angle != angle || old.maxRange != maxRange;
}
