import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:z_image_editor/image_editor.dart';

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
  final bool flipVertical;
  final CropRect? cropRect;
  final double scale; // zoom scale (1.0 = no zoom)
  final Offset panOffset; // pan offset in screen pixels from InteractiveViewer
  final Size? displaySize; // actual displayed image size on screen
  final Size? imageSize; // original image dimensions
  final EditorTab currentTab;
  final bool isProcessing;
  final AspectRatioPreset aspectRatioPreset; // selected aspect ratio for crop
  final double
      tiltHorizontal; // keystone tilt −30…+30 (positive = right recedes)
  final double
      tiltVertical; // keystone tilt −30…+30 (positive = bottom recedes)

  const ImageEditorState({
    this.imageFile,
    this.imageBytes,
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.rotation = 0.0,
    this.fineRotation = 0.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cropRect,
    this.scale = 1.0,
    this.panOffset = Offset.zero,
    this.displaySize,
    this.imageSize,
    this.currentTab = EditorTab.crop,
    this.isProcessing = false,
    this.aspectRatioPreset = AspectRatioPreset.free,
    this.tiltHorizontal = 0.0,
    this.tiltVertical = 0.0,
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
    Size? imageSize,
    EditorTab? currentTab,
    bool? isProcessing,
    AspectRatioPreset? aspectRatioPreset,
    double? tiltHorizontal,
    double? tiltVertical,
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
      flipVertical: flipVertical ?? this.flipVertical,
      cropRect: clearCropRect ? null : (cropRect ?? this.cropRect),
      scale: scale ?? this.scale,
      panOffset: panOffset ?? this.panOffset,
      displaySize: displaySize ?? this.displaySize,
      imageSize: imageSize ?? this.imageSize,
      currentTab: currentTab ?? this.currentTab,
      isProcessing: isProcessing ?? this.isProcessing,
      aspectRatioPreset: aspectRatioPreset ?? this.aspectRatioPreset,
      tiltHorizontal: tiltHorizontal ?? this.tiltHorizontal,
      tiltVertical: tiltVertical ?? this.tiltVertical,
    );
  }

  bool get hasChanges =>
      brightness != 0.0 ||
      contrast != 1.0 ||
      saturation != 1.0 ||
      rotation != 0.0 ||
      fineRotation != 0.0 ||
      tiltHorizontal != 0.0 ||
      tiltVertical != 0.0 ||
      flipHorizontal ||
      cropRect != null ||
      scale != 1.0 ||
      panOffset != Offset.zero;

  /// Get the total rotation angle in degrees
  double get totalRotation => rotation + fineRotation;

  /// Get the image aspect ratio (width / height)
  double get imageAspectRatio {
    if (imageSize != null) {
      return imageSize!.width / imageSize!.height;
    }
    // Default to 4:3 if image size not known yet
    return 4.0 / 3.0;
  }

  /// Get the crop area aspect ratio
  double get cropAspectRatio {
    if (cropRect != null && displaySize != null) {
      final cropWidth = cropRect!.width * displaySize!.width;
      final cropHeight = cropRect!.height * displaySize!.height;
      return cropWidth / cropHeight;
    }
    return imageAspectRatio;
  }

  /// Calculate the minimum scale factor needed to ensure a rotated image
  /// completely covers the crop area with no empty space.
  /// Uses the TransformationService for correct math.
  double get minScaleForRotation {
    return transformationService.calculateMinScaleForRotation(
      rotationDegrees: totalRotation,
      imageAspectRatio: imageAspectRatio,
      cropAspectRatio: cropAspectRatio,
    );
  }

  /// Calculate the scale factor needed to fit a rotated rectangle within its bounds
  /// This ensures no black background is visible when rotating
  /// DEPRECATED: Use minScaleForRotation instead - kept for backwards compatibility
  double get autoScaleForRotation {
    return 1.0 / minScaleForRotation;
  }

  /// Calculate the maximum allowed pan offset based on current rotation and scale
  Offset get maxPanOffset {
    if (displaySize == null || imageSize == null) {
      return Offset.zero;
    }
    return transformationService.calculateMaxPanOffset(
      imageSize: imageSize!,
      viewportSize: displaySize!,
      rotationDegrees: totalRotation,
      currentScale: scale,
    );
  }

  /// Get a clamped version of the current pan offset
  Offset get clampedPanOffset {
    final max = maxPanOffset;
    return Offset(
      panOffset.dx.clamp(-max.dx, max.dx),
      panOffset.dy.clamp(-max.dy, max.dy),
    );
  }
}

enum EditorTab {
  crop,
  adjust,
  rotate,
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

  /// Linearly interpolate between two crop rects.
  static CropRect lerp(CropRect a, CropRect b, double t) {
    return CropRect(
      left: a.left + (b.left - a.left) * t,
      top: a.top + (b.top - a.top) * t,
      width: a.width + (b.width - a.width) * t,
      height: a.height + (b.height - a.height) * t,
    );
  }
}

enum AspectRatioPreset {
  free,
  square,
  ratio4x3,
  ratio3x2,
  ratio16x9,
  ratio9x16,
}

extension AspectRatioPresetExtension on AspectRatioPreset {
  String get label {
    switch (this) {
      case AspectRatioPreset.free:
        return 'Free';
      case AspectRatioPreset.square:
        return '1:1';
      case AspectRatioPreset.ratio4x3:
        return '4:3';
      case AspectRatioPreset.ratio3x2:
        return '3:2';
      case AspectRatioPreset.ratio16x9:
        return '16:9';
      case AspectRatioPreset.ratio9x16:
        return '9:16';
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
      case AspectRatioPreset.ratio3x2:
        return 3.0 / 2.0;
      case AspectRatioPreset.ratio16x9:
        return 16.0 / 9.0;
      case AspectRatioPreset.ratio9x16:
        return 9.0 / 16.0;
    }
  }
}
