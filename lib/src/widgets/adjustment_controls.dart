import 'dart:math' as math;

import 'package:flutter/material.dart';
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

  static const double _pxPerDeg = _AdjRulerPainter._pxPerDeg;

  /// Maps the active parameter's current value to a display angle in −45…+45
  /// so the ruler can be reused unchanged.
  double _toDisplayAngle(ImageEditorState state) {
    switch (_active) {
      case _AdjParam.brightness:
        // brightness −100…+100 → −45…+45
        return state.brightness * 45.0 / 100.0;
      case _AdjParam.contrast:
        // contrast 0.5…2.0, neutral 1.0 → deviation −0.5…+0.5 → −45…+45
        return (state.contrast - 1.0) * 90.0;
      case _AdjParam.saturation:
        // saturation 0.0…2.0, neutral 1.0 → deviation −1.0…+1.0 → −45…+45
        return (state.saturation - 1.0) * 45.0;
    }
  }

  void _onDrag(double deltaPx, ImageEditorState state) {
    final double deltaAngle = deltaPx / _pxPerDeg;
    switch (_active) {
      case _AdjParam.brightness:
        widget.controller.setBrightness(
            (state.brightness - deltaAngle * 100.0 / 45.0)
                .clamp(-100.0, 100.0));
      case _AdjParam.contrast:
        widget.controller
            .setContrast((state.contrast - deltaAngle / 90.0).clamp(0.5, 2.0));
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
              // — badges row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AdjBadge(
                    label: 'Brightness',
                    value: state.brightness,
                    isZero: state.brightness.abs() < 0.5,
                    formatFn: (v) => '${v > 0 ? '+' : ''}${v.round()}',
                    isSelected: _active == _AdjParam.brightness,
                    onTap: () => setState(() => _active = _AdjParam.brightness),
                  ),
                  const SizedBox(width: 20),
                  _AdjBadge(
                    label: 'Contrast',
                    value: state.contrast - 1.0,
                    isZero: (state.contrast - 1.0).abs() < 0.01,
                    formatFn: (v) =>
                        '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}',
                    isSelected: _active == _AdjParam.contrast,
                    onTap: () => setState(() => _active = _AdjParam.contrast),
                  ),
                  const SizedBox(width: 20),
                  _AdjBadge(
                    label: 'Saturation',
                    value: state.saturation - 1.0,
                    isZero: (state.saturation - 1.0).abs() < 0.01,
                    formatFn: (v) =>
                        '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}',
                    isSelected: _active == _AdjParam.saturation,
                    onTap: () => setState(() => _active = _AdjParam.saturation),
                  ),
                ],
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
  final double value; // deviation from neutral (or raw for brightness)
  final bool isZero;
  final String Function(double) formatFn;
  final bool isSelected;
  final VoidCallback onTap;

  const _AdjBadge({
    required this.label,
    required this.value,
    required this.isZero,
    required this.formatFn,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderColor = isSelected
        ? const Color(0xFFFFCC00)
        : (isZero ? Colors.white24 : Colors.white54);
    final Color textColor = isSelected
        ? const Color(0xFFFFCC00)
        : (isZero ? Colors.white70 : Colors.white);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Center(
              child: Text(
                isZero ? '0' : formatFn(value),
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
