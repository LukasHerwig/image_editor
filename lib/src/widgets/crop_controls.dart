import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:z_image_editor/image_editor.dart';

/// Which ruler axis is currently active.
enum _TiltMode { straighten, vertical, horizontal }

/// Crop controls — iOS-style mode badges + ruler slider.
class CropControls extends StatefulWidget {
  final ImageEditorController controller;

  const CropControls({super.key, required this.controller});

  @override
  State<CropControls> createState() => _CropControlsState();
}

class _CropControlsState extends State<CropControls> {
  static const double _pxPerDeg = _RulerPainter._pxPerDeg;

  _TiltMode _activeMode = _TiltMode.straighten;
  int? _lastHapticTick;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final angle = state.fineRotation;
        final tiltV = state.tiltVertical;
        final tiltH = state.tiltHorizontal;

        // Value and range for the currently active mode.
        final double activeValue;
        final double maxRange;
        switch (_activeMode) {
          case _TiltMode.straighten:
            activeValue = angle;
            maxRange = 45.0;
          case _TiltMode.vertical:
            activeValue = tiltV;
            maxRange = 30.0;
          case _TiltMode.horizontal:
            activeValue = tiltH;
            maxRange = 30.0;
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // — badges row: selected badge is always centred; others slide.
              LayoutBuilder(
                builder: (context, constraints) {
                  // Centre of the available width.
                  final cx = constraints.maxWidth / 2;
                  // Badge width (52) + gap (16) = one step.
                  const step = 68.0;
                  const half = 26.0; // half badge width for centering
                  final selectedIdx = _activeMode.index; // 0, 1, 2

                  final badges = [
                    (
                      mode: _TiltMode.straighten,
                      icon: CupertinoIcons.arrow_clockwise,
                      value: angle,
                      maxRange: 45.0,
                    ),
                    (
                      mode: _TiltMode.vertical,
                      icon: CupertinoIcons.arrow_up_down,
                      value: tiltV,
                      maxRange: 30.0,
                    ),
                    (
                      mode: _TiltMode.horizontal,
                      icon: CupertinoIcons.arrow_left_right,
                      value: tiltH,
                      maxRange: 30.0,
                    ),
                  ];

                  return SizedBox(
                    height: 52,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (int i = 0; i < badges.length; i++)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            // Shift so selected badge sits exactly at cx.
                            left: cx + (i - selectedIdx) * step - half,
                            top: 0,
                            child: _ModeBadge(
                              icon: badges[i].icon,
                              value: badges[i].value,
                              maxRange: badges[i].maxRange,
                              selected: _activeMode == badges[i].mode,
                              onTap: () => setState(() {
                                _activeMode = badges[i].mode;
                                _lastHapticTick = null;
                              }),
                              onDoubleTap: _activeMode == badges[i].mode
                                  ? () {
                                      switch (badges[i].mode) {
                                        case _TiltMode.straighten:
                                          widget.controller.setFineRotation(0);
                                        case _TiltMode.vertical:
                                          widget.controller.setTiltVertical(0);
                                        case _TiltMode.horizontal:
                                          widget.controller
                                              .setTiltHorizontal(0);
                                      }
                                    }
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              // — ruler (controls active mode)
              SizedBox(
                height: 40,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    switch (_activeMode) {
                      case _TiltMode.straighten:
                        final newValue =
                            (angle - d.delta.dx / _pxPerDeg).clamp(-45.0, 45.0);
                        final tick = newValue.round();
                        if (tick != _lastHapticTick) {
                          _lastHapticTick = tick;
                          HapticFeedback.selectionClick();
                        }
                        widget.controller.setFineRotation(newValue);
                      case _TiltMode.vertical:
                        final newValue =
                            (tiltV - d.delta.dx / _pxPerDeg).clamp(-30.0, 30.0);
                        final tick = newValue.round();
                        if (tick != _lastHapticTick) {
                          _lastHapticTick = tick;
                          HapticFeedback.selectionClick();
                        }
                        widget.controller.setTiltVertical(newValue);
                      case _TiltMode.horizontal:
                        final newValue =
                            (tiltH - d.delta.dx / _pxPerDeg).clamp(-30.0, 30.0);
                        final tick = newValue.round();
                        if (tick != _lastHapticTick) {
                          _lastHapticTick = tick;
                          HapticFeedback.selectionClick();
                        }
                        widget.controller.setTiltHorizontal(newValue);
                    }
                  },
                  // After lifting the finger, smoothly animate any remaining
                  // scale/pan correction so the settle feels fluid.
                  onHorizontalDragEnd: (_) =>
                      widget.controller.settleAfterRulerDrag(),
                  child: CustomPaint(
                    painter: _RulerPainter(
                      angle: activeValue,
                      maxRange: maxRange,
                    ),
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

// ── Circular mode badge ───────────────────────────────────────────────────────

const _kYellow = Color(0xFFFFCC00);

/// Circular badge showing mode icon + arc-fill border indicating the value.
///
/// When NOT selected: always shows the [icon]; arc fill in yellow (positive)
/// or white (negative) proportional to |value|/[maxRange].
///
/// When selected and non-zero: shows the numeric value instead of the icon
/// (same colour rule). When selected and zero: shows the icon.
class _ModeBadge extends StatelessWidget {
  final IconData icon;
  final double value;
  final double maxRange;
  final bool selected;
  final VoidCallback onTap;

  final VoidCallback? onDoubleTap;

  const _ModeBadge({
    required this.icon,
    required this.value,
    required this.maxRange,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPositive = value > 0.05;
    final bool isNegative = value < -0.05;
    final bool isNonZero = isPositive || isNegative;

    final Color valueColor;
    if (isPositive) {
      valueColor = _kYellow;
    } else if (isNegative) {
      valueColor = Colors.white;
    } else {
      valueColor = selected ? Colors.white70 : Colors.white38;
    }

    // When selected and non-zero show the numeric value; otherwise show icon.
    final Widget centre;
    if (selected && isNonZero) {
      centre = Text(
        '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}',
        style: TextStyle(
          color: valueColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
    } else {
      centre = Icon(icon, color: valueColor, size: 16);
    }

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: CustomPaint(
        painter: _BadgeArcPainter(
          value: value,
          maxRange: maxRange,
          color: valueColor,
        ),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Center(child: centre),
        ),
      ),
    );
  }
}

// ── Arc painter for badge border ─────────────────────────────────────────────

/// Paints a dim full-circle track plus a coloured arc whose sweep encodes
/// both the magnitude and sign of [value]:
///
///   positive → clockwise from 12-o'clock   (right side fills first)
///   negative → counter-clockwise from 12-o'clock  (left side fills first)
///
/// Sweep angle = (|value| / [maxRange]) × 360°, so the full range = full circle.
class _BadgeArcPainter extends CustomPainter {
  final double value;
  final double maxRange;
  final Color color;

  const _BadgeArcPainter({
    required this.value,
    required this.maxRange,
    required this.color,
  });

  static const double _strokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - _strokeWidth / 2;

    // Dim track — always present so the badge shape is always visible.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );

    if (value.abs() < 0.05) return;

    final double fraction = (value.abs() / maxRange).clamp(0.0, 1.0);
    // Clockwise for positive (fills right side), CCW for negative (fills left).
    final double sweep = (value > 0 ? 1.0 : -1.0) * fraction * 2 * math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // start at 12-o'clock
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BadgeArcPainter old) =>
      old.value != value || old.maxRange != maxRange || old.color != color;
}

// ── Ruler painter ─────────────────────────────────────────────────────────────

class _RulerPainter extends CustomPainter {
  final double angle;
  final double maxRange;
  const _RulerPainter({required this.angle, this.maxRange = 45.0});

  static const double _pxPerDeg = 5.0;
  static const double _majorEvery = 5.0;
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

    // Clamp to hard stops so ticks never extend beyond the allowed range.
    final double visibleDeg = (size.width / 2) / _pxPerDeg + 2;
    final double startDeg =
        math.max(-maxRange, (angle - visibleDeg).floorToDouble());
    final double endDeg =
        math.min(maxRange, (angle + visibleDeg).ceilToDouble());

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
  bool shouldRepaint(_RulerPainter old) =>
      old.angle != angle || old.maxRange != maxRange;
}
