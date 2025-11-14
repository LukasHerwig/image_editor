import 'dart:io';
import 'dart:typed_data';

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
    this.flipVertical = false,
    this.cropRect,
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
      flipVertical: flipVertical ?? this.flipVertical,
      cropRect: clearCropRect ? null : (cropRect ?? this.cropRect),
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
      flipVertical ||
      cropRect != null;
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
