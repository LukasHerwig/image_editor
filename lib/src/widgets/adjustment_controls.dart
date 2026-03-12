import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:z_image_editor/image_editor.dart';

enum _AdjParam { brightness, contrast, saturation }

/// Adjustment controls — three parameter badges + iOS-style ruler slider.
class AdjustmentControls extends StatefulWidget {
  final ImageEditorController controller;

  const AdjustmentControls({super.key, required this.controller});

  @override
  State<AdjustmentControls> createState() => _AdjustmentControlsState();
}

class _AdjustmentControlsState extends State<AdjustmentControls> {
  _AdjParam _active = _AdjParam.brightness;
  int? _lastHapticTick;

  static const double _pxPerDeg = _AdjRulerPainter._pxPerDeg;

  /// Maps the active parameter's current value to a display angle in −45…+45
  /// so the ruler can be reused unchanged.
  double _toDisplayAngle(ImageEditorState state) {
    switch (_active) {
      case _AdjParam.brightness:
        // brightness −100…+100 → −45…+45
        return state.brightness * 45.0 / 100.0;
      case _AdjParam.contrast:
        // contrast 0.0…2.0, neutral 1.0; display −100…+100 → −45…+45
        return (state.contrast - 1.0) * 45.0;
      case _AdjParam.saturation:
        // saturation 0.0…2.0, neutral 1.0; display −100…+100 → −45…+45
        return (state.saturation - 1.0) * 45.0;
    }
  }

  void _onDrag(double deltaPx, ImageEditorState state) {
    final double deltaAngle = deltaPx / _pxPerDeg;
    final int tick = (_toDisplayAngle(state) - deltaAngle).round();
    if (tick != _lastHapticTick) {
      _lastHapticTick = tick;
      HapticFeedback.selectionClick();
    }
    switch (_active) {
      case _AdjParam.brightness:
        widget.controller.setBrightness(
            (state.brightness - deltaAngle * 100.0 / 45.0)
                .clamp(-100.0, 100.0));
      case _AdjParam.contrast:
        widget.controller
            .setContrast((state.contrast - deltaAngle / 45.0).clamp(0.0, 2.0));
      case _AdjParam.saturation:
        widget.controller.setSaturation(
            (state.saturation - deltaAngle / 45.0).clamp(0.0, 2.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final displayAngle = _toDisplayAngle(state);

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // — badges row: selected badge always centred; others slide.
              LayoutBuilder(
                builder: (context, constraints) {
                  final cx = constraints.maxWidth / 2;
                  const step = 68.0;
                  const half = 26.0;
                  final selectedIdx = _active.index; // 0, 1, 2

                  return SizedBox(
                    height: 70,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          left: cx + (0 - selectedIdx) * step - half,
                          top: 0,
                          child: _AdjBadge(
                            label: 'Brightness',
                            icon: CupertinoIcons.sun_max,
                            value: state.brightness,
                            maxRange: 100.0,
                            isZero: state.brightness.abs() < 0.5,
                            formatFn: (v) => '${v > 0 ? '+' : ''}${v.round()}',
                            isSelected: _active == _AdjParam.brightness,
                            onTap: () => setState(() {
                              _active = _AdjParam.brightness;
                              _lastHapticTick = null;
                            }),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          left: cx + (1 - selectedIdx) * step - half,
                          top: 0,
                          child: _AdjBadge(
                            label: 'Contrast',
                            icon: CupertinoIcons.circle_lefthalf_fill,
                            value: (state.contrast - 1.0) * 100.0,
                            maxRange: 100.0,
                            isZero: (state.contrast - 1.0).abs() < 0.005,
                            formatFn: (v) => '${v > 0 ? '+' : ''}${v.round()}',
                            isSelected: _active == _AdjParam.contrast,
                            onTap: () => setState(() {
                              _active = _AdjParam.contrast;
                              _lastHapticTick = null;
                            }),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          left: cx + (2 - selectedIdx) * step - half,
                          top: 0,
                          child: _AdjBadge(
                            label: 'Saturation',
                            icon: CupertinoIcons.drop,
                            value: (state.saturation - 1.0) * 100.0,
                            maxRange: 100.0,
                            isZero: (state.saturation - 1.0).abs() < 0.005,
                            formatFn: (v) => '${v > 0 ? '+' : ''}${v.round()}',
                            isSelected: _active == _AdjParam.saturation,
                            onTap: () => setState(() {
                              _active = _AdjParam.saturation;
                              _lastHapticTick = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              // — ruler
              SizedBox(
                height: 40,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) =>
                      _onDrag(d.delta.dx, widget.controller.state),
                  child: CustomPaint(
                    painter: _AdjRulerPainter(angle: displayAngle),
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

// ── Parameter badge ───────────────────────────────────────────────────────────

class _AdjBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value; // deviation from neutral (or raw for brightness)
  final double maxRange;
  final bool isZero;
  final String Function(double) formatFn;
  final bool isSelected;
  final VoidCallback onTap;

  const _AdjBadge({
    required this.label,
    required this.icon,
    required this.value,
    required this.maxRange,
    required this.isZero,
    required this.formatFn,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPositive = !isZero && value > 0;
    final bool isNegative = !isZero && value < 0;

    final Color valueColor;
    if (isPositive) {
      valueColor = const Color(0xFFFFCC00);
    } else if (isNegative) {
      valueColor = Colors.white;
    } else {
      valueColor = isSelected ? Colors.white70 : Colors.white38;
    }

    final Widget centre;
    if (isSelected && !isZero) {
      centre = Text(
        formatFn(value),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            painter: _AdjArcPainter(
              value: isZero ? 0.0 : value,
              maxRange: maxRange,
              color: valueColor,
            ),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Center(child: centre),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFFFFCC00) : Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Arc painter for adjustment badge border ───────────────────────────────────

class _AdjArcPainter extends CustomPainter {
  final double value;
  final double maxRange;
  final Color color;

  const _AdjArcPainter({
    required this.value,
    required this.maxRange,
    required this.color,
  });

  static const double _strokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - _strokeWidth / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );

    if (value.abs() < 0.001) return;

    final double fraction = (value.abs() / maxRange).clamp(0.0, 1.0);
    final double sweep = (value > 0 ? 1.0 : -1.0) * fraction * 2 * math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
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
  bool shouldRepaint(_AdjArcPainter old) =>
      old.value != value || old.maxRange != maxRange || old.color != color;
}

// ── Ruler painter (same visual as crop angle ruler) ───────────────────────────

class _AdjRulerPainter extends CustomPainter {
  final double angle; // −45…+45 (normalised display value)
  const _AdjRulerPainter({required this.angle});

  static const double _pxPerDeg = 5.0;
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

    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height * 0.72),
      centrePaint,
    );
  }

  @override
  bool shouldRepaint(_AdjRulerPainter old) => old.angle != angle;
}
