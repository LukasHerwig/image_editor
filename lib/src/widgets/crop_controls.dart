import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:z_image_editor/image_editor.dart';
import 'editor_badge.dart';
import 'editor_ruler_painter.dart';

/// Which ruler axis is currently active.
enum _TiltMode { straighten, vertical, horizontal }

/// Crop controls — iOS-style mode badges + ruler slider.
class CropControls extends StatefulWidget {
  final ImageEditorController controller;
  final CropTabSettings settings;

  const CropControls({
    super.key,
    required this.controller,
    this.settings = const CropTabSettings(),
  });

  @override
  State<CropControls> createState() => _CropControlsState();
}

class _CropControlsState extends State<CropControls> {
  static const double _pxPerDeg = EditorRulerPainter.pxPerDeg;

  _TiltMode _activeMode = _TiltMode.straighten;
  int? _lastHapticTick;

  @override
  void initState() {
    super.initState();
    // Ensure the initial active mode is one that is visible.
    final s = widget.settings;
    final visible = [
      if (s.showStraighten) _TiltMode.straighten,
      if (s.showTiltVertical) _TiltMode.vertical,
      if (s.showTiltHorizontal) _TiltMode.horizontal,
    ];
    if (visible.isNotEmpty && !visible.contains(_activeMode)) {
      _activeMode = visible.first;
    }
  }

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

                  final badges = [
                    if (widget.settings.showStraighten)
                      (
                        mode: _TiltMode.straighten,
                        icon: CupertinoIcons.arrow_clockwise,
                        value: angle,
                        maxRange: 45.0,
                      ),
                    if (widget.settings.showTiltVertical)
                      (
                        mode: _TiltMode.vertical,
                        icon: CupertinoIcons.arrow_up_down,
                        value: tiltV,
                        maxRange: 30.0,
                      ),
                    if (widget.settings.showTiltHorizontal)
                      (
                        mode: _TiltMode.horizontal,
                        icon: CupertinoIcons.arrow_left_right,
                        value: tiltH,
                        maxRange: 30.0,
                      ),
                  ];

                  // Position of the active badge in the filtered list.
                  final selectedIdx = math.max(
                    0,
                    badges.indexWhere((b) => b.mode == _activeMode),
                  );

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
                            child: EditorBadge(
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
                    painter: EditorRulerPainter(
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
