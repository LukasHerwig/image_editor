import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:z_image_editor/src/models/image_editor_state.dart';

class ImageProcessing {
  /// Apply all edits to the image and return the processed image.
  ///
  /// Uses a WYSIWYG PictureRecorder approach when display size information is
  /// available, guaranteeing pixel-perfect accuracy between preview and output.
  /// Falls back to pixel-based processing otherwise.
  static Future<File> processImage({
    required File originalFile,
    required ImageEditorState state,
  }) async {
    if (state.displaySize != null) {
      return _processImageWysiwyg(
        bytes: await originalFile.readAsBytes(),
        state: state,
      );
    }
    return _processImageFallback(originalFile: originalFile, state: state);
  }

  /// Process from raw bytes (for imageBytes: path).
  static Future<File> processImageFromBytes({
    required Uint8List bytes,
    required ImageEditorState state,
  }) async {
    if (state.displaySize != null) {
      return _processImageWysiwyg(bytes: bytes, state: state);
    }
    return _processImageFallbackFromBytes(bytes: bytes, state: state);
  }

  // ---------------------------------------------------------------------------
  // WYSIWYG renderer — reproduces the exact pixel content visible in the crop
  // window by replaying the same transform chain used by the display layer.
  //
  // Transform chain (image widget coords → viewport screen coords):
  //   1. Image drawn at BoxFit.contain rect  (fitOffX, fitOffY, fitW, fitH)
  //   2. Transform widget:  T(vpCenter) × S(minScale) × R(angle) × flip × T(-vpCenter)
  //   3. InteractiveViewer: T(pan) × S(userScale)
  //
  // To capture the crop window [cropL,cropT,cropW,cropH] at native resolution,
  // the canvas accumulates:
  //   S(s) × T(-cropL,-cropT) × T_iv × T_widget
  // where s = outputW / cropW  (output pixels per viewport pixel)
  // ---------------------------------------------------------------------------
  static Future<File> _processImageWysiwyg({
    required Uint8List bytes,
    required ImageEditorState state,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final uiImage = frame.image;

    final imgW = uiImage.width.toDouble();
    final imgH = uiImage.height.toDouble();
    final vpW = state.displaySize!.width;
    final vpH = state.displaySize!.height;

    // ── BoxFit.contain metrics ──────────────────────────────────────────────
    final fitScale = math.min(vpW / imgW, vpH / imgH);
    final fitW = imgW * fitScale;
    final fitH = imgH * fitScale;
    final fitOffX = (vpW - fitW) / 2;
    final fitOffY = (vpH - fitH) / 2;

    // ── Crop window in viewport pixels ──────────────────────────────────────
    // Default to the fitted image rect if no crop is set.
    final cropL = (state.cropRect?.left ?? fitOffX / vpW) * vpW;
    final cropT = (state.cropRect?.top ?? fitOffY / vpH) * vpH;
    final cropW = (state.cropRect?.width ?? fitW / vpW) * vpW;
    final cropH = (state.cropRect?.height ?? fitH / vpH) * vpH;

    // ── Output size at native image resolution ──────────────────────────────
    // totalMag: how many viewport pixels one image pixel covers at this zoom.
    final minScaleForRot = state.minScaleForRotation;
    final userScale = state.scale;
    final totalMag = fitScale * minScaleForRot * userScale;
    final outputW = math.max(1, (cropW / totalMag).round());
    final outputH = math.max(1, (cropH / totalMag).round());

    // Render scale: output pixels per viewport pixel.
    final s = outputW / cropW;

    // ── Rebuild the single unified Transform matrix ──────────────────────────
    // Matches Transform(alignment: Alignment.center,
    //   transform: T(pan) * S(totalScale) * R(angle) * S(flip))
    // which expands with the alignment pivot as:
    //   T(vpCenter + pan) * S(totalScale) * R(angle) * S(flip) * T(-vpCenter)
    //
    // This form correctly reconstructs what the user sees for ALL combinations
    // of rotation, userScale and panOffset (the old two-matrix approach was
    // incorrect when userScale ≠ 1.0).
    final totalRotation = state.totalRotation;
    final flipH = state.flipHorizontal;
    final flipV = state.flipVertical;
    final totalDisplayScale = minScaleForRot * userScale;
    final fullMatrix = Matrix4.identity()
      ..translateByDouble(
        vpW / 2 + state.panOffset.dx,
        vpH / 2 + state.panOffset.dy,
        0.0,
        1.0,
      )
      ..scaleByDouble(totalDisplayScale, totalDisplayScale, 1.0, 1.0)
      ..rotateZ(totalRotation * math.pi / 180)
      ..scaleByDouble(flipH ? -1.0 : 1.0, flipV ? -1.0 : 1.0, 1.0, 1.0)
      ..translateByDouble(-vpW / 2, -vpH / 2, 0.0, 1.0);

    // ── Render ───────────────────────────────────────────────────────────────
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, outputW.toDouble(), outputH.toDouble()),
    );

    // output_coords = S(s) × T(-cropL, -cropT) × fullMatrix × widget_coords
    canvas.scale(s);
    canvas.translate(-cropL, -cropT);
    canvas.transform(fullMatrix.storage);

    // Color adjustments via paint colorFilter (matches live preview exactly).
    final paint = Paint()..filterQuality = FilterQuality.high;
    if (state.brightness != 0 ||
        state.contrast != 1.0 ||
        state.saturation != 1.0) {
      paint.colorFilter = ColorFilterMatrix.combined(
        brightness: state.brightness,
        contrast: state.contrast,
        saturation: state.saturation,
      );
    }

    // Draw the image at its BoxFit.contain destination rect.
    canvas.drawImageRect(
      uiImage,
      Rect.fromLTWH(0, 0, imgW, imgH),
      Rect.fromLTWH(fitOffX, fitOffY, fitW, fitH),
      paint,
    );

    final picture = recorder.endRecording();
    final outputImage = await picture.toImage(outputW, outputH);
    final pngData =
        await outputImage.toByteData(format: ui.ImageByteFormat.png);
    if (pngData == null) throw Exception('Failed to encode rendered image');

    final tempDir = Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/edited_$timestamp.png');
    await tempFile.writeAsBytes(pngData.buffer.asUint8List());
    return tempFile;
  }

  // ---------------------------------------------------------------------------
  // Fallback: pixel-based processing (used only when displaySize is unavailable)
  // NOTE: This path is intentionally simple and does NOT account for zoom/pan.
  // ---------------------------------------------------------------------------
  static Future<File> _processImageFallback({
    required File originalFile,
    required ImageEditorState state,
  }) async {
    return _processImageFallbackFromBytes(
      bytes: await originalFile.readAsBytes(),
      state: state,
    );
  }

  static Future<File> _processImageFallbackFromBytes({
    required Uint8List bytes,
    required ImageEditorState state,
  }) async {
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    // Rotation first, then crop (correct order).
    final totalRotation = state.totalRotation;
    if (totalRotation != 0) {
      image = _applyRotation(image, totalRotation);
    }

    // Crop using image-space coordinates.
    // NOTE: In the fallback path cropRect fractions are applied to image dims,
    // which is only accurate when the image fills the full viewport.
    if (state.cropRect != null) {
      image = _applyCrop(image, state.cropRect!);
    }

    if (state.flipHorizontal) image = img.flipHorizontal(image);
    if (state.flipVertical) image = img.flipVertical(image);

    image = _applyColorAdjustments(
      image,
      brightness: state.brightness,
      contrast: state.contrast,
      saturation: state.saturation,
    );

    final tempDir = Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/edited_$timestamp.jpg');
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
      width: width.clamp(1, image.width - x),
      height: height.clamp(1, image.height - y),
    );
  }

  static img.Image _applyRotation(img.Image image, double degrees) {
    if (degrees % 90 == 0) {
      final times = ((degrees / 90) % 4).toInt();
      for (int i = 0; i < times; i++) {
        image = img.copyRotate(image, angle: 90);
      }
      return image;
    }
    return img.copyRotate(image, angle: degrees);
  }

  static img.Image _applyColorAdjustments(
    img.Image image, {
    required double brightness,
    required double contrast,
    required double saturation,
  }) {
    if (brightness != 0) {
      final brightnessValue = (brightness * 2.55).toInt();
      image = img.adjustColor(image, brightness: brightnessValue);
    }
    if (contrast != 1.0) {
      image = img.adjustColor(image, contrast: contrast);
    }
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
