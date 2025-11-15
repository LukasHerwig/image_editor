import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// State model for the image editor
class ImageEditorState {
  final File? imageFile;
  final Uint8List? imageBytes;
  final double brightness;
  final double contrast;
  final double saturation;
  final double rotation; // in degrees (90-degree increments)
  final double fineRotation; // fine-tune angle (-45 to 45)
  final bool flipHorizontal;
  final CropRect? cropRect;
  final double scale; // zoom scale (1.0 = no zoom)
  final Offset panOffset; // pan offset in screen pixels from InteractiveViewer
  final Size? displaySize; // actual displayed image size on screen
  final EditorTab currentTab;
  final bool isProcessing;

  const ImageEditorState({
    this.imageFile,
    this.imageBytes,
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.rotation = 0.0,
    this.fineRotation = 0.0,
    this.flipHorizontal = false,
    this.cropRect,
    this.scale = 1.0,
    this.panOffset = Offset.zero,
    this.displaySize,
    this.currentTab = EditorTab.crop,
    this.isProcessing = false,
  });

  ImageEditorState copyWith({
    File? imageFile,
    Uint8List? imageBytes,
    double? brightness,
    double? contrast,
    double? saturation,
    double? rotation,
    double? fineRotation,
    bool? flipHorizontal,
    bool? flipVertical,
    CropRect? cropRect,
    bool clearCropRect = false,
    double? scale,
    Offset? panOffset,
    Size? displaySize,
    EditorTab? currentTab,
    bool? isProcessing,
  }) {
    return ImageEditorState(
      imageFile: imageFile ?? this.imageFile,
      imageBytes: imageBytes ?? this.imageBytes,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      rotation: rotation ?? this.rotation,
      fineRotation: fineRotation ?? this.fineRotation,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      cropRect: clearCropRect ? null : (cropRect ?? this.cropRect),
      scale: scale ?? this.scale,
      panOffset: panOffset ?? this.panOffset,
      displaySize: displaySize ?? this.displaySize,
      currentTab: currentTab ?? this.currentTab,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }

  bool get hasChanges =>
      brightness != 0.0 ||
      contrast != 1.0 ||
      saturation != 1.0 ||
      rotation != 0.0 ||
      fineRotation != 0.0 ||
      flipHorizontal ||
      cropRect != null ||
      scale != 1.0 ||
      panOffset != Offset.zero;

  /// Calculate the scale factor needed to fit a rotated rectangle within its bounds
  /// This ensures no black background is visible when rotating
  double get autoScaleForRotation {
    final totalRotation = rotation + fineRotation;
    if (totalRotation == 0.0) return 1.0;

    // Convert to radians and normalize to 0-90 degrees for calculation
    final angleInRadians = (totalRotation.abs() % 90) * (math.pi / 180);

    // For a rectangle rotated by angle θ, the scale factor needed is:
    // 1 / (cos(θ) + sin(θ))
    // We add a safety margin to ensure no background shows at any angle
    final cosAngle = math.cos(angleInRadians);
    final sinAngle = math.sin(angleInRadians);

    // The base scale with a 3% safety margin to prevent any edge cases
    final baseScale = 1.0 / (cosAngle + sinAngle);
    return baseScale *
        0.85; // Scale down more (zoom in more) to eliminate all black edges
  }
}

enum EditorTab {
  crop,
  adjust,
}

/// Represents a crop rectangle
class CropRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  CropRect copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return CropRect(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

enum AspectRatioPreset {
  free,
  square,
  ratio4x3,
  ratio16x9,
}

extension AspectRatioPresetExtension on AspectRatioPreset {
  String get label {
    switch (this) {
      case AspectRatioPreset.free:
        return 'Free';
      case AspectRatioPreset.square:
        return 'Square';
      case AspectRatioPreset.ratio4x3:
        return '4:3';
      case AspectRatioPreset.ratio16x9:
        return '16:9';
    }
  }

  double? get ratio {
    switch (this) {
      case AspectRatioPreset.free:
        return null;
      case AspectRatioPreset.square:
        return 1.0;
      case AspectRatioPreset.ratio4x3:
        return 4.0 / 3.0;
      case AspectRatioPreset.ratio16x9:
        return 16.0 / 9.0;
    }
  }
}
