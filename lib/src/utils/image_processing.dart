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

    // Apply rotation (both 90-degree and fine rotation) FIRST
    // This is important because the rotation affects the coordinate system
    final totalRotation = state.rotation + state.fineRotation;
    if (totalRotation != 0) {
      image = _applyRotation(image, totalRotation);

      // After rotation, apply auto-scale by cropping to the inscribed rectangle
      // This ensures the output matches what the user sees (no black corners)
      if (totalRotation % 90 != 0) {
        final autoScale = state.autoScaleForRotation;
        // Calculate the inscribed rectangle dimensions
        final newWidth = (image.width * autoScale).round();
        final newHeight = (image.height * autoScale).round();
        final offsetX = ((image.width - newWidth) / 2).round();
        final offsetY = ((image.height - newHeight) / 2).round();

        image = img.copyCrop(
          image,
          x: offsetX,
          y: offsetY,
          width: newWidth,
          height: newHeight,
        );
      }
    }

    // Apply flips
    if (state.flipHorizontal) {
      image = img.flipHorizontal(image);
    }

    // Apply crop/zoom if either crop rect is set OR if there's zoom/pan
    // If no explicit crop rect, use full image (0,0,1,1) as the crop area
    if (state.cropRect != null ||
        state.scale != 1.0 ||
        state.panOffset != Offset.zero) {
      final cropRect = state.cropRect ??
          const CropRect(
            left: 0.0,
            top: 0.0,
            width: 1.0,
            height: 1.0,
          );

      image = _applyCrop(
        image,
        cropRect,
        state.scale,
        state.panOffset,
        state.displaySize,
      );
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

  static img.Image _applyCrop(
    img.Image image,
    CropRect cropRect,
    double scale,
    Offset panOffset,
    Size? displaySize,
  ) {
    // The crop overlay is in normalized viewport coordinates (0-1)
    // The image is zoomed by 'scale' and panned by 'panOffset' (in screen pixels)
    // We need to calculate what region of the original image is inside the crop overlay

    if (scale == 1.0 && panOffset == Offset.zero) {
      // No zoom/pan - simple crop using the crop rect directly
      final x = (cropRect.left * image.width).toInt();
      final y = (cropRect.top * image.height).toInt();
      final width = (cropRect.width * image.width).toInt();
      final height = (cropRect.height * image.height).toInt();

      return img.copyCrop(
        image,
        x: x.clamp(0, image.width),
        y: y.clamp(0, image.height),
        width: width.clamp(1, image.width - x.clamp(0, image.width)),
        height: height.clamp(1, image.height - y.clamp(0, image.height)),
      );
    }

    // When zoomed/panned, we need to transform coordinates:
    // 1. Crop rect is in viewport space (0-1 normalized)
    // 2. Convert to display pixel space
    // 3. Account for pan offset (subtract it, since pan moves the image)
    // 4. Divide by scale to get original image space
    // 5. Convert to original image pixel coordinates

    if (displaySize == null) {
      // Fallback if display size not available - use simple crop
      final x = (cropRect.left * image.width).toInt();
      final y = (cropRect.top * image.height).toInt();
      final width = (cropRect.width * image.width).toInt();
      final height = (cropRect.height * image.height).toInt();

      return img.copyCrop(
        image,
        x: x.clamp(0, image.width),
        y: y.clamp(0, image.height),
        width: width.clamp(1, image.width - x.clamp(0, image.width)),
        height: height.clamp(1, image.height - y.clamp(0, image.height)),
      );
    }

    // Convert crop rect from normalized viewport coordinates to display pixels
    final cropLeftPx = cropRect.left * displaySize.width;
    final cropTopPx = cropRect.top * displaySize.height;
    final cropWidthPx = cropRect.width * displaySize.width;
    final cropHeightPx = cropRect.height * displaySize.height;

    // Account for pan and scale to get position in original image space
    // panOffset is how much the image has been moved in screen pixels
    // Subtracting pan offset gives us the position relative to the unmovedimage
    // Then dividing by scale gives us the position in the original image coordinates
    final imageLeftPx = (cropLeftPx - panOffset.dx) / scale;
    final imageTopPx = (cropTopPx - panOffset.dy) / scale;
    final imageWidthPx = cropWidthPx / scale;
    final imageHeightPx = cropHeightPx / scale;

    // The displaySize represents the fitted image size
    // We need to map from display coordinates to original image coordinates
    // Calculate the scale factor between display size and original image size
    final displayAspect = displaySize.width / displaySize.height;
    final imageAspect = image.width / image.height;

    double displayToImageScale;
    double offsetX = 0;
    double offsetY = 0;

    if (displayAspect > imageAspect) {
      // Image is fitted to height, letterboxed on sides
      displayToImageScale = image.height / displaySize.height;
      final displayedWidth = image.width / displayToImageScale;
      offsetX = (displaySize.width - displayedWidth) / 2;
    } else {
      // Image is fitted to width, letterboxed on top/bottom
      displayToImageScale = image.width / displaySize.width;
      final displayedHeight = image.height / displayToImageScale;
      offsetY = (displaySize.height - displayedHeight) / 2;
    }

    // Convert from display coordinates to original image coordinates
    // Account for letterboxing offset
    final x = ((imageLeftPx - offsetX) * displayToImageScale).toInt();
    final y = ((imageTopPx - offsetY) * displayToImageScale).toInt();
    final width = (imageWidthPx * displayToImageScale).toInt();
    final height = (imageHeightPx * displayToImageScale).toInt();

    return img.copyCrop(
      image,
      x: x.clamp(0, image.width),
      y: y.clamp(0, image.height),
      width: width.clamp(1, image.width - x.clamp(0, image.width)),
      height: height.clamp(1, image.height - y.clamp(0, image.height)),
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
