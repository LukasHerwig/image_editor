import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:z_image_editor/image_editor.dart';

/// Crop controls — iOS-style angle badge + ruler slider.
class CropControls extends StatefulWidget {
  final ImageEditorController controller;

  const CropControls({super.key, required this.controller});

  @override
  State<CropControls> createState() => _CropControlsState();
}

class _CropControlsState extends State<CropControls> {
  static const double _pxPerDeg = _RulerPainter._pxPerDeg;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final angle = widget.controller.state.fineRotation;

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // — badges row (angle circle + space for future tilt circles)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AngleBadge(angle: angle),
                ],
              ),
              const SizedBox(height: 10),
              // — ruler
              SizedBox(
                height: 40,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    widget.controller.setFineRotation(
                        (widget.controller.state.fineRotation -
                                d.delta.dx / _pxPerDeg)
                            .clamp(-45.0, 45.0));
                  },
                  child: CustomPaint(
                    painter: _RulerPainter(angle: angle),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Circular angle badge ──────────────────────────────────────────────────────

class _AngleBadge extends StatelessWidget {
  final double angle;
  const _AngleBadge({required this.angle});

  @override
  Widget build(BuildContext context) {
    final bool isNonZero = angle.abs() > 0.05;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isNonZero ? const Color(0xFFFFCC00) : Colors.white24,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          angle.abs() < 0.05
              ? '0'
              : '${angle > 0 ? '+' : ''}${angle.toStringAsFixed(1)}',
          style: TextStyle(
            color: isNonZero ? const Color(0xFFFFCC00) : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Ruler painter ─────────────────────────────────────────────────────────────

class _RulerPainter extends CustomPainter {
  final double angle; // −45 … +45
  const _RulerPainter({required this.angle});

  static const double _pxPerDeg = 5.0;
  static const double _majorEvery = 5.0; // every 5° is tall
  static const double _minorEvery = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Tick extents
    final double majorH = size.height * 0.55;
    final double minorH = size.height * 0.28;
    final double medH = size.height * 0.40;

    final tickPaint = Paint()
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    // Centre yellow line
    final centrePaint = Paint()
      ..color = const Color(0xFFFFCC00)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Range to draw: clamp to the allowed ±45° limits so the ruler
    // never shows ticks beyond the hard stops.
    final double visibleDeg = (size.width / 2) / _pxPerDeg + 2;
    final double startDeg =
        math.max(-45.0, (angle - visibleDeg).floorToDouble());
    final double endDeg = math.min(45.0, (angle + visibleDeg).ceilToDouble());

    for (double deg = startDeg; deg <= endDeg; deg += _minorEvery) {
      final double x = cx + (deg - angle) * _pxPerDeg;
      if (x < 0 || x > size.width) continue;

      final bool isMajor = (deg % _majorEvery).abs() < 0.01;
      final bool isMed = (deg % 5 != 0) && (deg % 5).abs() < 2.51;
      final double h = isMajor ? majorH : (isMed ? medH : minorH);

      // Fade ticks near the edges
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

    // Fixed centre indicator line
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height * 0.72),
      centrePaint,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.angle != angle;
}
