import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:monogram_image_editor/image_editor.dart';

/// Crop controls — angle slider only (aspect ratio preset chips live in the
/// context tools row above, rendered by MonogramImageEditor).
class CropControls extends StatelessWidget {
  final ImageEditorController controller;

  const CropControls({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final state = controller.state;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
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
                          '${state.fineRotation.toStringAsFixed(1)}°',
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
        );
      },
    );
  }
}
