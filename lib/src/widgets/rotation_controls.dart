import 'package:z_image_editor/src/controller/image_editor_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Rotation and flip controls
class RotationControls extends StatelessWidget {
  final ImageEditorController controller;

  const RotationControls({
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rotation buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildButton(
                    icon: CupertinoIcons.rotate_left,
                    label: 'Rotate',
                    onTap: controller.rotate90,
                  ),
                  _buildButton(
                    icon: CupertinoIcons.arrow_left_right,
                    label: 'Flip H',
                    isActive: state.flipHorizontal,
                    onTap: controller.flipHorizontal,
                  ),
                  _buildButton(
                    icon: CupertinoIcons.arrow_up_down,
                    label: 'Flip V',
                    isActive: state.flipVertical,
                    onTap: controller.flipVertical,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Fine rotation slider
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.rotate_right,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Angle',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${state.fineRotation.toStringAsFixed(0)}°',
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
                            overlayColor: CupertinoColors.systemBlue
                                .withValues(alpha: 0.2),
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: state.fineRotation,
                            min: -45,
                            max: 45,
                            onChanged: controller.setFineRotation,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color:
              isActive ? CupertinoColors.systemBlue : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
