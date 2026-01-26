import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Centralized service for all transformation math.
/// Handles rotation-aware bounding box calculations, pan limits,
/// and coordinate space conversions.
class TransformationService {
  /// Cache for memoization
  double? _cachedRotation;
  double? _cachedImageAspectRatio;
  double? _cachedCropAspectRatio;
  double? _cachedMinScale;

  /// Calculate the minimum scale factor required to ensure a rotated image
  /// completely covers the crop area with no empty space.
  ///
  /// This is the correct formula that accounts for both image and crop aspect ratios.
  ///
  /// [rotationDegrees] - Total rotation in degrees
  /// [imageAspectRatio] - Width/Height of the original image
  /// [cropAspectRatio] - Width/Height of the crop area (null = same as image)
  double calculateMinScaleForRotation({
    required double rotationDegrees,
    required double imageAspectRatio,
    double? cropAspectRatio,
  }) {
    // Normalize rotation to 0-90 degrees (symmetrical behavior)
    final normalizedAngle = rotationDegrees.abs() % 180;
    final effectiveAngle =
        normalizedAngle > 90 ? 180 - normalizedAngle : normalizedAngle;

    // At 0 degrees (or very close to it), no extra scale needed - return 1.0
    // This is the key fix: when there's no rotation, always return 1.0
    if (effectiveAngle < 0.5) return 1.0;

    // Use memoization - return cached value if inputs haven't changed
    final cropRatio = cropAspectRatio ?? imageAspectRatio;
    if (_cachedRotation == effectiveAngle &&
        _cachedImageAspectRatio == imageAspectRatio &&
        _cachedCropAspectRatio == cropRatio) {
      return _cachedMinScale!;
    }

    final angleRad = effectiveAngle * math.pi / 180;

    // For an image of dimensions (W, H) rotated by angle θ,
    // the bounding box of the rotated image is:
    //   newWidth = W * cos(θ) + H * sin(θ)
    //   newHeight = W * sin(θ) + H * cos(θ)
    //
    // To fit a crop rectangle of aspect ratio r_crop inside a rotated image
    // of aspect ratio r_image, we need to find the largest rectangle
    // with aspect ratio r_crop that fits inside the rotated bounds.
    //
    // The minimum scale to ensure coverage is:
    //   scale = max(cropW / inscribedW, cropH / inscribedH)

    // Calculate the inscribed rectangle dimensions for a unit-sized image
    // rotated by the given angle
    final inscribedSize = _calculateInscribedRectangle(
      imageAspectRatio: imageAspectRatio,
      cropAspectRatio: cropRatio,
      angleRadians: angleRad,
    );

    // The scale needed is how much we need to enlarge the image so that
    // the inscribed rectangle matches the crop area
    final minScale = 1.0 / inscribedSize;

    // Cache the result
    _cachedRotation = effectiveAngle;
    _cachedImageAspectRatio = imageAspectRatio;
    _cachedCropAspectRatio = cropRatio;
    _cachedMinScale = minScale;

    return minScale;
  }

  /// Calculate the size of the largest rectangle with [cropAspectRatio]
  /// that fits inside a rotated rectangle with [imageAspectRatio].
  /// Returns the scale factor (0-1) relative to the original image.
  double _calculateInscribedRectangle({
    required double imageAspectRatio,
    required double cropAspectRatio,
    required double angleRadians,
  }) {
    final cosA = math.cos(angleRadians).abs();
    final sinA = math.sin(angleRadians).abs();

    // For a rectangle of size (W, H) rotated by angle θ, to find the scale
    // needed so that a centered crop area is fully covered:
    //
    // The rotated image creates a bounding box larger than the original.
    // We need to scale up so no black corners appear in the crop area.
    //
    // Normalize: assume image height = 1, width = imageAspectRatio
    // For the crop area, we consider the cropAspectRatio

    // The key formula: for a rotated rectangle, the scale factor needed is:
    // scale = max(
    //   (crop_w * cos + crop_h * sin) / image_w,
    //   (crop_w * sin + crop_h * cos) / image_h
    // )
    //
    // Normalizing with image_h = 1, image_w = imageAspectRatio,
    // crop_h = 1, crop_w = cropAspectRatio:

    final scaleForWidth = (cropAspectRatio * cosA + sinA) / imageAspectRatio;
    final scaleForHeight = (cropAspectRatio * sinA + cosA);

    // The minimum scale needed is the maximum of both constraints
    final minScaleNeeded = math.max(scaleForWidth, scaleForHeight);

    // Return the inscribed size (inverse of required scale)
    return 1.0 / math.max(1.0, minScaleNeeded);
  }

  /// Calculate the maximum allowed pan offset for a rotated and scaled image
  /// to ensure the crop area is always fully covered.
  ///
  /// Returns the maximum absolute offset in each direction.
  Offset calculateMaxPanOffset({
    required Size imageSize,
    required Size viewportSize,
    required double rotationDegrees,
    required double currentScale,
  }) {
    final angleRad = rotationDegrees.abs() * math.pi / 180;
    final cosA = math.cos(angleRad).abs();
    final sinA = math.sin(angleRad).abs();

    // Calculate the rotated image dimensions at current scale
    final scaledWidth = imageSize.width * currentScale;
    final scaledHeight = imageSize.height * currentScale;

    // The bounding box of the rotated image
    final rotatedWidth = scaledWidth * cosA + scaledHeight * sinA;
    final rotatedHeight = scaledWidth * sinA + scaledHeight * cosA;

    // Maximum pan is the excess beyond the viewport divided by 2
    // (because we can pan equally in both directions from center)
    final maxPanX = math.max(0.0, (rotatedWidth - viewportSize.width) / 2);
    final maxPanY = math.max(0.0, (rotatedHeight - viewportSize.height) / 2);

    return Offset(maxPanX, maxPanY);
  }

  /// Clamp a pan offset to valid bounds based on rotation and scale.
  Offset clampPanOffset({
    required Offset currentOffset,
    required Size imageSize,
    required Size viewportSize,
    required double rotationDegrees,
    required double currentScale,
  }) {
    final maxOffset = calculateMaxPanOffset(
      imageSize: imageSize,
      viewportSize: viewportSize,
      rotationDegrees: rotationDegrees,
      currentScale: currentScale,
    );

    return Offset(
      currentOffset.dx.clamp(-maxOffset.dx, maxOffset.dx),
      currentOffset.dy.clamp(-maxOffset.dy, maxOffset.dy),
    );
  }

  /// Convert a point from viewport coordinates to original image coordinates,
  /// accounting for all transformations (rotation, scale, pan, flip).
  Offset viewportToImageCoordinates({
    required Offset viewportPoint,
    required Size viewportSize,
    required Size imageSize,
    required double rotationDegrees,
    required double scale,
    required Offset panOffset,
    required bool flipHorizontal,
  }) {
    // Start from viewport center
    final viewportCenter =
        Offset(viewportSize.width / 2, viewportSize.height / 2);

    // Translate point relative to center
    var point = viewportPoint - viewportCenter;

    // Remove pan offset
    point = point - panOffset;

    // Remove scale
    point = point / scale;

    // Remove rotation (rotate in opposite direction)
    final angleRad = -rotationDegrees * math.pi / 180;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    point = Offset(
      point.dx * cosA - point.dy * sinA,
      point.dx * sinA + point.dy * cosA,
    );

    // Handle flip
    if (flipHorizontal) {
      point = Offset(-point.dx, point.dy);
    }

    // Translate back to image coordinates (origin at top-left)
    final imageCenter = Offset(imageSize.width / 2, imageSize.height / 2);
    point = point + imageCenter;

    return point;
  }

  /// Convert a point from original image coordinates to viewport coordinates.
  Offset imageToViewportCoordinates({
    required Offset imagePoint,
    required Size viewportSize,
    required Size imageSize,
    required double rotationDegrees,
    required double scale,
    required Offset panOffset,
    required bool flipHorizontal,
  }) {
    // Translate to center-based coordinates
    final imageCenter = Offset(imageSize.width / 2, imageSize.height / 2);
    var point = imagePoint - imageCenter;

    // Apply flip
    if (flipHorizontal) {
      point = Offset(-point.dx, point.dy);
    }

    // Apply rotation
    final angleRad = rotationDegrees * math.pi / 180;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    point = Offset(
      point.dx * cosA - point.dy * sinA,
      point.dx * sinA + point.dy * cosA,
    );

    // Apply scale
    point = point * scale;

    // Apply pan offset
    point = point + panOffset;

    // Translate to viewport coordinates
    final viewportCenter =
        Offset(viewportSize.width / 2, viewportSize.height / 2);
    point = point + viewportCenter;

    return point;
  }

  /// Check if a crop rectangle is fully covered by the rotated image.
  bool isCropFullyCovered({
    required Rect cropRect,
    required Size imageSize,
    required double rotationDegrees,
    required double scale,
    required Offset panOffset,
  }) {
    // Get the four corners of the crop rectangle
    final corners = [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ];

    // Transform each corner to image coordinates and check if it's within image bounds
    for (final corner in corners) {
      final imagePoint = viewportToImageCoordinates(
        viewportPoint: corner,
        viewportSize:
            cropRect.size, // Using crop rect as viewport for this check
        imageSize: imageSize,
        rotationDegrees: rotationDegrees,
        scale: scale,
        panOffset: panOffset,
        flipHorizontal: false,
      );

      if (imagePoint.dx < 0 ||
          imagePoint.dx > imageSize.width ||
          imagePoint.dy < 0 ||
          imagePoint.dy > imageSize.height) {
        return false;
      }
    }

    return true;
  }

  /// Clear the memoization cache (call when crop aspect ratio changes significantly)
  void clearCache() {
    _cachedRotation = null;
    _cachedImageAspectRatio = null;
    _cachedCropAspectRatio = null;
    _cachedMinScale = null;
  }
}

/// Singleton instance for easy access
final transformationService = TransformationService();
