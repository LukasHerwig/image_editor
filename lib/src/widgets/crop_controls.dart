import 'package:monogram_image_editor/src/controller/image_editor_controller.dart';
import 'package:monogram_image_editor/src/models/image_editor_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Aspect Ratio',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: AspectRatioPreset.values.map((preset) {
              return _buildRatioButton(preset);
            }).toList(),
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _selectedRatio = AspectRatioPreset.free;
              });
              widget.controller.resetCrop();
            },
            child: const Text(
              'Reset',
              style: TextStyle(
                color: CupertinoColors.systemBlue,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatioButton(AspectRatioPreset preset) {
    final isSelected = _selectedRatio == preset;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRatio = preset;
        });
        _applyAspectRatio(preset);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? CupertinoColors.systemBlue : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          preset.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _applyAspectRatio(AspectRatioPreset preset) {
    final currentRect = widget.controller.state.cropRect ??
        const CropRect(
          left: 0.1,
          top: 0.1,
          width: 0.8,
          height: 0.8,
        );

    if (preset == AspectRatioPreset.free) {
      // Keep current crop rect for free aspect ratio
      return;
    }

    final targetRatio = preset.ratio!;
    final currentRatio = currentRect.width / currentRect.height;

    CropRect newRect;

    if (currentRatio > targetRatio) {
      // Current is wider, adjust width
      final newWidth = currentRect.height * targetRatio;
      final centerX = currentRect.left + currentRect.width / 2;
      final newLeft = (centerX - newWidth / 2).clamp(0.0, 1.0 - newWidth);

      newRect = CropRect(
        left: newLeft,
        top: currentRect.top,
        width: newWidth.clamp(0.1, 1.0 - newLeft),
        height: currentRect.height,
      );
    } else {
      // Current is taller, adjust height
      final newHeight = currentRect.width / targetRatio;
      final centerY = currentRect.top + currentRect.height / 2;
      final newTop = (centerY - newHeight / 2).clamp(0.0, 1.0 - newHeight);

      newRect = CropRect(
        left: currentRect.left,
        top: newTop,
        width: currentRect.width,
        height: newHeight.clamp(0.1, 1.0 - newTop),
      );
    }

    widget.controller.setCropRect(newRect);
  }
}
