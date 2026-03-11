import 'package:z_image_editor/src/controller/image_editor_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Adjustment controls for brightness, contrast, and saturation
class AdjustmentControls extends StatelessWidget {
  final ImageEditorController controller;

  const AdjustmentControls({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final state = controller.state;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSlider(
                icon: CupertinoIcons.sun_max,
                label: 'Brightness',
                value: state.brightness,
                min: -100,
                max: 100,
                onChanged: controller.setBrightness,
              ),
              const SizedBox(height: 16),
              _buildSlider(
                icon: CupertinoIcons.circle_lefthalf_fill,
                label: 'Contrast',
                value: state.contrast,
                min: 0.5,
                max: 2.0,
                defaultValue: 1.0,
                onChanged: controller.setContrast,
              ),
              const SizedBox(height: 16),
              _buildSlider(
                icon: CupertinoIcons.drop,
                label: 'Saturation',
                value: state.saturation,
                min: 0.0,
                max: 2.0,
                defaultValue: 1.0,
                onChanged: controller.setSaturation,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlider({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    double? defaultValue,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: CupertinoColors.systemBlue,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor:
                      CupertinoColors.systemBlue.withValues(alpha: 0.2),
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
