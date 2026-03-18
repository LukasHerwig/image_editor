import 'dart:math' as math;
import 'package:flutter/material.dart';

const _kYellow = Color(0xFFFFCC00);

/// Circular badge widget shared by crop and adjustment controls.
///
/// Renders an arc border whose sweep encodes [value]'s magnitude and sign
/// (positive → yellow clockwise, negative → white counter-clockwise), and
/// shows either the [icon] or the formatted numeric value when [selected] and
/// non-zero.
///
/// Pass a [label] to render a small text caption below the circle (used by
/// the adjustment panel). Leave [label] null for badge-only display (used by
/// the crop panel).
///
/// [isZero] defaults to `value.abs() < 0.05`; supply an explicit value when
/// the caller has a domain-specific threshold (e.g. contrast/saturation
/// neutral at 1.0 mapped to 0.0 deviation).
///
/// [formatFn] customises the numeric string shown when selected and non-zero.
/// Defaults to `±X.X` (one decimal place).
class EditorBadge extends StatelessWidget {
  final IconData icon;
  final double value;
  final double maxRange;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  /// Optional label shown below the circle.
  final String? label;

  /// Custom number formatter. Defaults to `±X.X`.
  final String Function(double)? formatFn;

  /// Whether [value] counts as zero. Defaults to `value.abs() < 0.05`.
  final bool? isZero;

  const EditorBadge({
    super.key,
    required this.icon,
    required this.value,
    required this.maxRange,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
    this.label,
    this.formatFn,
    this.isZero,
  });

  @override
  Widget build(BuildContext context) {
    final bool zero = isZero ?? value.abs() < 0.05;
    final bool isPositive = !zero && value > 0;
    final bool isNegative = !zero && value < 0;

    final Color valueColor;
    if (isPositive) {
      valueColor = _kYellow;
    } else if (isNegative) {
      valueColor = Colors.white;
    } else {
      valueColor = selected ? Colors.white70 : Colors.white38;
    }

    final Widget centre;
    if (selected && !zero) {
      final String text = formatFn != null
          ? formatFn!(value)
          : '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}';
      centre = Text(
        text,
        style: TextStyle(
          color: valueColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
    } else {
      centre = Icon(icon, color: valueColor, size: 16);
    }

    final Widget circle = CustomPaint(
      painter: _BadgeArcPainter(
        value: zero ? 0.0 : value,
        maxRange: maxRange,
        color: valueColor,
      ),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Center(child: centre),
      ),
    );

    final Widget content = label == null
        ? circle
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              circle,
              const SizedBox(height: 4),
              Text(
                label!,
                style: TextStyle(
                  color: selected ? _kYellow : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: content,
    );
  }
}

// ── Arc painter ───────────────────────────────────────────────────────────────

/// Paints a dim full-circle track plus a coloured arc whose sweep encodes
/// both the magnitude and sign of [value]:
///
///   positive → clockwise from 12-o'clock
///   negative → counter-clockwise from 12-o'clock
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
  bool shouldRepaint(_BadgeArcPainter old) =>
      old.value != value || old.maxRange != maxRange || old.color != color;
}
