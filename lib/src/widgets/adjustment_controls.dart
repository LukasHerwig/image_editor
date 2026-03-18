import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:z_image_editor/image_editor.dart';
import 'editor_badge.dart';
import 'editor_ruler_painter.dart';

enum _AdjParam { brightness, contrast, saturation }

/// Adjustment controls — three parameter badges + iOS-style ruler slider.
class AdjustmentControls extends StatefulWidget {
  final ImageEditorController controller;
  final AdjustTabSettings settings;

  const AdjustmentControls({
    super.key,
    required this.controller,
    this.settings = const AdjustTabSettings(),
  });

  @override
  State<AdjustmentControls> createState() => _AdjustmentControlsState();
}

class _AdjustmentControlsState extends State<AdjustmentControls> {
  _AdjParam _active = _AdjParam.brightness;
  int? _lastHapticTick;

  static const double _pxPerDeg = EditorRulerPainter.pxPerDeg;

  @override
  void initState() {
    super.initState();
    // Ensure the initial active param is one that is visible.
    final s = widget.settings;
    final visible = [
      if (s.showBrightness) _AdjParam.brightness,
      if (s.showContrast) _AdjParam.contrast,
      if (s.showSaturation) _AdjParam.saturation,
    ];
    if (visible.isNotEmpty && !visible.contains(_active)) {
      _active = visible.first;
    }
  }

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

                  // Build filtered badge list based on settings.
                  final badges = [
                    if (widget.settings.showBrightness)
                      (
                        param: _AdjParam.brightness,
                        label: 'Brightness',
                        icon: CupertinoIcons.sun_max,
                        value: state.brightness,
                        maxRange: 100.0,
                        isZero: state.brightness.abs() < 0.5,
                      ),
                    if (widget.settings.showContrast)
                      (
                        param: _AdjParam.contrast,
                        label: 'Contrast',
                        icon: CupertinoIcons.circle_lefthalf_fill,
                        value: (state.contrast - 1.0) * 100.0,
                        maxRange: 100.0,
                        isZero: (state.contrast - 1.0).abs() < 0.005,
                      ),
                    if (widget.settings.showSaturation)
                      (
                        param: _AdjParam.saturation,
                        label: 'Saturation',
                        icon: CupertinoIcons.drop,
                        value: (state.saturation - 1.0) * 100.0,
                        maxRange: 100.0,
                        isZero: (state.saturation - 1.0).abs() < 0.005,
                      ),
                  ];

                  // Position of the active badge in the filtered list.
                  final selectedIdx = math.max(
                    0,
                    badges.indexWhere((b) => b.param == _active),
                  );

                  return SizedBox(
                    height: 70,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (int i = 0; i < badges.length; i++)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            left: cx + (i - selectedIdx) * step - half,
                            top: 0,
                            child: EditorBadge(
                              label: badges[i].label,
                              icon: badges[i].icon,
                              value: badges[i].value,
                              maxRange: badges[i].maxRange,
                              isZero: badges[i].isZero,
                              formatFn: (v) =>
                                  '${v > 0 ? '+' : ''}${v.round()}',
                              selected: _active == badges[i].param,
                              onTap: () => setState(() {
                                _active = badges[i].param;
                                _lastHapticTick = null;
                              }),
                              onDoubleTap: _active == badges[i].param
                                  ? switch (badges[i].param) {
                                      _AdjParam.brightness => () =>
                                          widget.controller.setBrightness(0),
                                      _AdjParam.contrast => () =>
                                          widget.controller.setContrast(1.0),
                                      _AdjParam.saturation => () =>
                                          widget.controller.setSaturation(1.0),
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
              // — ruler
              SizedBox(
                height: 40,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) =>
                      _onDrag(d.delta.dx, widget.controller.state),
                  child: CustomPaint(
                    painter: EditorRulerPainter(angle: displayAngle),
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
