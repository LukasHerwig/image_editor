import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:monogram_image_editor/image_editor.dart';
import 'package:monogram_image_editor/monogram_image_editor.dart';

/// Crop controls with aspect ratio presets
class CropControls extends StatefulWidget {
  final ImageEditorController controller;

  const CropControls({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  State<CropControls> createState() => _CropControlsState();
}

class _CropControlsState extends State<CropControls> {
  AspectRatioPreset _selectedRatio = AspectRatioPreset.free;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final state = widget.controller.state;

        return Container(
          padding: const EdgeInsets.only(
            top: 20,
            bottom: 5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fine rotation slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                  CupertinoColors.systemBlue.withOpacity(0.2),
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                            ),
                            child: Slider(
                              value: state.fineRotation,
                              min: -45,
                              max: 45,
                              onChanged: widget.controller.setFineRotation,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Aspect ratio presets
              const SizedBox(height: 16),
              _buildAspectRatioSelector(state),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAspectRatioSelector(ImageEditorState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: AspectRatioPreset.values.map((preset) {
          final isSelected = state.aspectRatioPreset == preset;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => widget.controller.setAspectRatioPreset(preset),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? CupertinoColors.systemBlue
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? CupertinoColors.systemBlue
                        : Colors.white24,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAspectRatioIcon(preset, isSelected),
                    const SizedBox(width: 6),
                    Text(
                      preset.label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAspectRatioIcon(AspectRatioPreset preset, bool isSelected) {
    final color = isSelected ? Colors.white : Colors.white70;

    switch (preset) {
      case AspectRatioPreset.free:
        return Icon(CupertinoIcons.crop, size: 16, color: color);
      case AspectRatioPreset.square:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case AspectRatioPreset.ratio4x3:
        return Container(
          width: 16,
          height: 12,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case AspectRatioPreset.ratio3x2:
        return Container(
          width: 15,
          height: 10,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case AspectRatioPreset.ratio16x9:
        return Container(
          width: 18,
          height: 10,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case AspectRatioPreset.ratio9x16:
        return Container(
          width: 10,
          height: 18,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
        );
    }
  }
}
