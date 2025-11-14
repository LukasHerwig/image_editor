import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:monogram_image_editor/src/models/image_editor_state.dart';

class ImageProcessing {
  /// Apply all edits to the image and return the processed image
  static Future<File> processImage({
    required File originalFile,
    required ImageEditorState state,
  }) async {
    // Read the original image
    final bytes = await originalFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Apply crop if set
    if (state.cropRect != null) {
      image = _applyCrop(image, state.cropRect!);
    }

    // Apply rotation (both 90-degree and fine rotation)
    final totalRotation = state.rotation + state.fineRotation;
    if (totalRotation != 0) {
      image = _applyRotation(image, totalRotation);
    }

    // Apply flips
    if (state.flipHorizontal) {
      image = img.flipHorizontal(image);
    }
    if (state.flipVertical) {
      image = img.flipVertical(image);
    }

    // Apply color adjustments
    image = _applyColorAdjustments(
      image,
      brightness: state.brightness,
      contrast: state.contrast,
      saturation: state.saturation,
    );

    // Save to temporary file
    final tempDir = Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/edited_image_$timestamp.jpg');

    await tempFile.writeAsBytes(img.encodeJpg(image, quality: 95));

    return tempFile;
  }

  static img.Image _applyCrop(img.Image image, CropRect cropRect) {
    final x = (cropRect.left * image.width).toInt();
    final y = (cropRect.top * image.height).toInt();
    final width = (cropRect.width * image.width).toInt();
    final height = (cropRect.height * image.height).toInt();

    return img.copyCrop(
      image,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  static img.Image _applyRotation(img.Image image, double degrees) {
    // For 90-degree increments, use optimized rotation
    if (degrees % 90 == 0) {
      final times = ((degrees / 90) % 4).toInt();
      for (int i = 0; i < times; i++) {
        image = img.copyRotate(image, angle: 90);
      }
      return image;
    }

    // For arbitrary angles (copyRotate expects degrees, not radians)
    return img.copyRotate(image, angle: degrees);
  }

  static img.Image _applyColorAdjustments(
    img.Image image, {
    required double brightness,
    required double contrast,
    required double saturation,
  }) {
    // Apply brightness (-100 to 100 -> -255 to 255)
    if (brightness != 0) {
      final brightnessValue = (brightness * 2.55).toInt();
      image = img.adjustColor(image, brightness: brightnessValue);
    }

    // Apply contrast (0.5 to 2.0)
    if (contrast != 1.0) {
      image = img.adjustColor(image, contrast: contrast);
    }

    // Apply saturation (0.0 to 2.0)
    if (saturation != 1.0) {
      image = img.adjustColor(image, saturation: saturation);
    }

    return image;
  }

  /// Create a preview image for display
  static Future<ui.Image> createPreviewImage({
    required dynamic imageSource,
    required ImageEditorState state,
  }) async {
    Uint8List bytes;

    if (imageSource is File) {
      bytes = await imageSource.readAsBytes();
    } else if (imageSource is Uint8List) {
      bytes = imageSource;
    } else {
      throw Exception('Invalid image source');
    }

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

/// Color filter matrix builder for real-time preview
class ColorFilterMatrix {
  static ColorFilter brightness(double value) {
    // value: -100 to 100
    final v = value / 100;
    return ColorFilter.matrix([
      1,
      0,
      0,
      0,
      v * 255,
      0,
      1,
      0,
      0,
      v * 255,
      0,
      0,
      1,
      0,
      v * 255,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  static ColorFilter contrast(double value) {
    // value: 0.5 to 2.0
    final v = value;
    final t = (1.0 - v) / 2.0 * 255;
    return ColorFilter.matrix([
      v,
      0,
      0,
      0,
      t,
      0,
      v,
      0,
      0,
      t,
      0,
      0,
      v,
      0,
      t,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  static ColorFilter saturation(double value) {
    // value: 0.0 to 2.0
    final v = value;
    final invSat = 1 - v;
    final R = 0.213 * invSat;
    final G = 0.715 * invSat;
    final B = 0.072 * invSat;

    return ColorFilter.matrix([
      R + v,
      G,
      B,
      0,
      0,
      R,
      G + v,
      B,
      0,
      0,
      R,
      G,
      B + v,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  static ColorFilter combined({
    required double brightness,
    required double contrast,
    required double saturation,
  }) {
    // Combine all filters
    final b = brightness / 100;
    final c = contrast;
    final s = saturation;

    final invSat = 1 - s;
    final R = 0.213 * invSat;
    final G = 0.715 * invSat;
    final B = 0.072 * invSat;

    final t = (1.0 - c) / 2.0 * 255 + b * 255;

    return ColorFilter.matrix([
      (R + s) * c,
      G * c,
      B * c,
      0,
      t,
      R * c,
      (G + s) * c,
      B * c,
      0,
      t,
      R * c,
      G * c,
      (B + s) * c,
      0,
      t,
      0,
      0,
      0,
      1,
      0,
    ]);
  }
}
