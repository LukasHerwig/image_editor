import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:z_image_editor/src/models/image_editor_state.dart'
    show CropRect;

/// Centralized service for all transformation math.
/// Handles rotation-aware bounding box calculations, pan limits,
/// and coordinate space conversions.
class TransformationService {
  // ── Perspective tilt ───────────────────────────────────────────────────────

  /// Converts the -30…+30 tilt UI value to a Matrix4 perspective entry.
  /// Tune this constant to adjust the visual strength of the tilt effect.
  static const double kTiltFactor = 0.000025;

  /// Builds a perspective tilt matrix pivoted at [vpCenter].
  ///
  /// Uses homogeneous perspective entries M[3,0]=pH and M[3,1]=pV so that
  /// a 2D point (x,y) maps to (x,y) / (1 + pH*(x-cx) + pV*(y-cy)) after
  /// perspective division — creating a keystone/trapezoid distortion.
  ///
  /// Positive [tiltHorizontal]: right side recedes (gets smaller).
  /// Positive [tiltVertical]:   bottom recedes (gets smaller).
  static Matrix4 buildPerspectiveMatrix(
    double tiltHorizontal,
    double tiltVertical,
    Offset vpCenter,
  ) {
    if (tiltHorizontal == 0 && tiltVertical == 0) return Matrix4.identity();
    final pH = tiltHorizontal * kTiltFactor;
    final pV = tiltVertical * kTiltFactor;
    // Perspective at origin: w' = 1 + pH*x + pV*y
    final persp = Matrix4.identity()
      ..setEntry(3, 0, pH)
      ..setEntry(3, 1, pV);
    // Wrap with pivot at viewport centre:
    //   result = T(cx,cy) × persp × T(-cx,-cy)
    return Matrix4.identity()
      ..translateByDouble(vpCenter.dx, vpCenter.dy, 0.0, 1.0)
      ..multiply(persp)
      ..translateByDouble(-vpCenter.dx, -vpCenter.dy, 0.0, 1.0);
  }

  /// Apply a 4×4 homogeneous matrix to a 2D offset with perspective division.
  /// Treats the input point as [x, y, 0, 1] in homogeneous coordinates.
  static Offset _applyPerspMatrix(Matrix4 m, Offset p) {
    final s = m.storage; // column-major: s[col*4+row]
    final x = p.dx;
    final y = p.dy;
    // Result of M * [x, y, 0, 1]:
    final rx = s[0] * x + s[4] * y + s[12]; // s[8]*0 omitted
    final ry = s[1] * x + s[5] * y + s[13];
    final rw = s[3] * x + s[7] * y + s[15];
    if (rw == 0) return p;
    return Offset(rx / rw, ry / rw);
  }

  // ── Cache for memoization ──────────────────────────────────────────────────

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

  /// Returns the valid pan range `(minPan, maxPan)` for the given transform.
  ///
  /// Uses the axis-aligned bounding box of the rotated image to determine how
  /// far the image centre can move while still covering every corner of the
  /// crop window.  Unlike a symmetric ±maxPan, this correctly handles crop
  /// windows that are NOT centred inside the viewport (asymmetric bounds).
  ///
  /// [userScale]    – user-controlled zoom (1.0 = just rotation compensation).
  /// [cropViewport] – crop window in **viewport pixels**; null = full fitted
  ///                  image rect (i.e. the default uncropped state).
  /// [cropAspectRatioOverride] – supply when the crop AR differs from what can
  ///                  be derived from [cropViewport] (rarely needed).
  ({Offset minPan, Offset maxPan}) calculatePanRange({
    required Size imageSize,
    required Size viewportSize,
    required double rotationDegrees,
    required double userScale,
    Rect? cropViewport,
    double? cropAspectRatioOverride,
  }) {
    // BoxFit.contain metrics.
    final fitScale = math.min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );
    final fitW = imageSize.width * fitScale;
    final fitH = imageSize.height * fitScale;

    // Crop window in viewport pixels (default = full fitted image).
    final cl = cropViewport?.left ?? (viewportSize.width - fitW) / 2;
    final ct = cropViewport?.top ?? (viewportSize.height - fitH) / 2;
    final cw = cropViewport?.width ?? fitW;
    final ch = cropViewport?.height ?? fitH;

    // Minimum scale needed for the image (at userScale=1) to cover the crop.
    final cropAR = cropAspectRatioOverride ?? (ch > 0 ? cw / ch : null);
    final minScale = calculateMinScaleForRotation(
      rotationDegrees: rotationDegrees,
      imageAspectRatio: imageSize.width / imageSize.height,
      cropAspectRatio: cropAR,
    );
    final totalScale = minScale * userScale;

    // Axis-aligned bounding box of the scaled + rotated fitted image.
    final scaledW = fitW * totalScale;
    final scaledH = fitH * totalScale;
    final angleRad = rotationDegrees.abs() * math.pi / 180;
    final cosA = math.cos(angleRad).abs();
    final sinA = math.sin(angleRad).abs();
    final bbW = scaledW * cosA + scaledH * sinA;
    final bbH = scaledW * sinA + scaledH * cosA;

    // Image centre = (vpCx + panX, vpCy + panY).
    // For the image to cover the crop window:
    //   image_left  ≤ crop_left   →  panX ≤  cl       - vpCx + bbW/2  (maxPanX)
    //   image_right ≥ crop_right  →  panX ≥ (cl + cw) - vpCx - bbW/2  (minPanX)
    final vpCx = viewportSize.width / 2;
    final vpCy = viewportSize.height / 2;
    final maxPanX = cl - vpCx + bbW / 2;
    final minPanX = (cl + cw) - vpCx - bbW / 2;
    final maxPanY = ct - vpCy + bbH / 2;
    final minPanY = (ct + ch) - vpCy - bbH / 2;

    return (
      minPan: Offset(minPanX, minPanY),
      maxPan: Offset(maxPanX, maxPanY),
    );
  }

  /// Convenience wrapper kept for backwards compatibility.
  /// Prefer [calculatePanRange] for asymmetric (off-centre crop) correctness.
  Offset calculateMaxPanOffset({
    required Size imageSize,
    required Size viewportSize,
    required double rotationDegrees,
    required double currentScale,
  }) {
    final range = calculatePanRange(
      imageSize: imageSize,
      viewportSize: viewportSize,
      rotationDegrees: rotationDegrees,
      userScale: currentScale,
    );
    // Return the positive half as a symmetric ±bound (centred crop assumption).
    return Offset(
      math.max(0.0, range.maxPan.dx),
      math.max(0.0, range.maxPan.dy),
    );
  }

  /// Returns the minimum **userScale** such that the crop box can fit inside
  /// the actual image at the given rotation — i.e. there exists a pan position
  /// where every crop corner lands within the image pixel boundary.
  ///
  /// This is the foundational minimum zoom constraint.  Values below 1.0 are
  /// possible and correct: the user can zoom out past the BoxFit.contain size
  /// as long as the current crop box still fits entirely inside the image.
  double calculateMinUserScaleForCrop({
    required CropRect cropRect,
    required Size imageSize,
    required Size viewportSize,
    required double rotationDegrees,
    double tiltHorizontal = 0.0,
    double tiltVertical = 0.0,
  }) {
    final vpW = viewportSize.width;
    final vpH = viewportSize.height;
    final fitScale = math.min(vpW / imageSize.width, vpH / imageSize.height);
    final fitW = imageSize.width * fitScale;
    final fitH = imageSize.height * fitScale;

    final angleRad = rotationDegrees.abs() * math.pi / 180;
    final cosA = math.cos(angleRad).abs();
    final sinA = math.sin(angleRad).abs();

    // The four crop corners in viewport space.
    final corners = [
      Offset(cropRect.left * vpW, cropRect.top * vpH),
      Offset((cropRect.left + cropRect.width) * vpW, cropRect.top * vpH),
      Offset(cropRect.left * vpW, (cropRect.top + cropRect.height) * vpH),
      Offset((cropRect.left + cropRect.width) * vpW,
          (cropRect.top + cropRect.height) * vpH),
    ];

    // When tilt is active the affine pipeline operates on un-tilted viewport
    // coordinates (step 0 of viewportToImageCoordinates).  At the near (magnified)
    // end of the tilt the un-tilted positions are *farther* from the viewport
    // centre than the raw viewport positions — so the formula must use the
    // un-tilted extents, otherwise it underestimates the required minimum scale
    // and allows pinch-zoom below the level where the image still covers the crop.
    final List<Offset> effective;
    if (tiltHorizontal != 0 || tiltVertical != 0) {
      final vpCenter = Offset(vpW / 2, vpH / 2);
      final mTilt =
          buildPerspectiveMatrix(tiltHorizontal, tiltVertical, vpCenter);
      final invTilt = Matrix4.inverted(mTilt);
      effective = corners.map((c) => _applyPerspMatrix(invTilt, c)).toList();
    } else {
      effective = corners;
    }

    // Project each (un-tilted) corner onto the image's rotation axes to find
    // the bounding extent the image must cover.  This is the tilt-aware
    // generalisation of the original cropW*cosA+cropH*sinA formula.
    final vpCx = vpW / 2;
    final vpCy = vpH / 2;
    double minU = double.infinity, maxU = double.negativeInfinity;
    double minV = double.infinity, maxV = double.negativeInfinity;
    for (final c in effective) {
      final dx = c.dx - vpCx;
      final dy = c.dy - vpCy;
      final u = dx * cosA + dy * sinA;
      final v = -dx * sinA + dy * cosA;
      if (u < minU) minU = u;
      if (u > maxU) maxU = u;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final cropExtentX = maxU - minU;
    final cropExtentY = maxV - minV;

    final minTotalScale = math.max(
      fitW > 0 ? cropExtentX / fitW : 1.0,
      fitH > 0 ? cropExtentY / fitH : 1.0,
    );

    // totalScale = minScaleForRotation × userScale  →  userScale = totalScale / minScaleForRotation
    final minForRotation = calculateMinScaleForRotation(
      rotationDegrees: rotationDegrees,
      imageAspectRatio: imageSize.width / imageSize.height,
      cropAspectRatio:
          cropExtentX > 0 && cropExtentY > 0 ? cropExtentX / cropExtentY : null,
    );

    // No floor at 1.0 — in crop mode it is intentional to allow values < 1.0.
    return math.max(0.01, minTotalScale / minForRotation);
  }

  /// Clamp a pan offset to the valid range computed by [calculatePanRange].
  ///
  /// Pass [cropViewport] (crop window in viewport pixels) for exact bounds;
  /// omit it to fall back to the full fitted-image area (symmetric clamp).
  Offset clampPanOffset({
    required Offset currentOffset,
    required Size imageSize,
    required Size viewportSize,
    required double rotationDegrees,
    required double userScale,
    Rect? cropViewport,
  }) {
    final range = calculatePanRange(
      imageSize: imageSize,
      viewportSize: viewportSize,
      rotationDegrees: rotationDegrees,
      userScale: userScale,
      cropViewport: cropViewport,
    );
    return Offset(
      currentOffset.dx.clamp(range.minPan.dx, range.maxPan.dx),
      currentOffset.dy.clamp(range.minPan.dy, range.maxPan.dy),
    );
  }

  /// Exact, raycasting-based pan clamp for crop mode.
  ///
  /// Projects all four corners of [cropRect] into image space using [pan], then
  /// computes the minimum pan correction that brings every corner inside the
  /// image rectangle [0,W]×[0,H].  Unlike [clampPanOffset] (which uses an
  /// AABB approximation) this is exact for any rotation angle.
  ///
  /// Because pan is a global viewport translation, a single Δpan shifts every
  /// image-space coordinate by the same Δimg, so the correction can be solved
  /// analytically in one pass — no iteration required.
  ///
  /// [totalScale] must be `minScaleForRotation * userScale`.
  Offset clampPanToCoverCrop({
    required Offset pan,
    required CropRect cropRect,
    required Size imageSize,
    required Size viewportSize,
    required double rotationDegrees,
    required double totalScale,
    required bool flipHorizontal,
    required bool flipVertical,
    double tiltHorizontal = 0.0,
    double tiltVertical = 0.0,
  }) {
    final vpW = viewportSize.width;
    final vpH = viewportSize.height;
    final fitScale = math.min(vpW / imageSize.width, vpH / imageSize.height);

    // Four corners of the crop box in viewport px.
    final corners = [
      Offset(cropRect.left * vpW, cropRect.top * vpH),
      Offset((cropRect.left + cropRect.width) * vpW, cropRect.top * vpH),
      Offset(cropRect.left * vpW, (cropRect.top + cropRect.height) * vpH),
      Offset((cropRect.left + cropRect.width) * vpW,
          (cropRect.top + cropRect.height) * vpH),
    ];

    // Project all corners into image space with the proposed pan.
    double minIX = double.infinity, maxIX = double.negativeInfinity;
    double minIY = double.infinity, maxIY = double.negativeInfinity;
    for (final c in corners) {
      final ip = viewportToImageCoordinates(
        viewportPoint: c,
        viewportSize: viewportSize,
        imageSize: imageSize,
        rotationDegrees: rotationDegrees,
        scale: totalScale,
        panOffset: pan,
        flipHorizontal: flipHorizontal,
        flipVertical: flipVertical,
        tiltHorizontal: tiltHorizontal,
        tiltVertical: tiltVertical,
      );
      if (ip.dx < minIX) minIX = ip.dx;
      if (ip.dx > maxIX) maxIX = ip.dx;
      if (ip.dy < minIY) minIY = ip.dy;
      if (ip.dy > maxIY) maxIY = ip.dy;
    }

    // Minimum image-space shift (Δimg) to bring all corners inside [0,W]×[0,H].
    // The required range is: Δimg.x ∈ [-minIX, W - maxIX]
    //                        Δimg.y ∈ [-minIY, H - maxIY]
    // Pick the smallest non-zero correction.
    final needRight =
        math.max(0.0, -minIX); // corners left of image → push right
    final needLeft = math.max(0.0, maxIX - imageSize.width); // → push left
    final needDown = math.max(0.0, -minIY);
    final needUp = math.max(0.0, maxIY - imageSize.height);

    // If both sides are violated the crop is larger than the image — leave as-is.
    double dImgX = 0, dImgY = 0;
    if (needRight > 0 && needLeft == 0) {
      dImgX = needRight;
    } else if (needLeft > 0 && needRight == 0) {
      dImgX = -needLeft;
    }
    if (needDown > 0 && needUp == 0) {
      dImgY = needDown;
    } else if (needUp > 0 && needDown == 0) {
      dImgY = -needUp;
    }

    if (dImgX == 0 && dImgY == 0) return pan;

    // Convert image-space correction → pan correction.
    // Derivation: img = F·R(-a)·(P − vpCenter − pan) / (totalScale·fitScale) + imgCenter
    // → Δpan = −(totalScale·fitScale)·R(a)·F·Δimg
    final factor = totalScale * fitScale;
    final angleRad = rotationDegrees * math.pi / 180;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    final fx = flipHorizontal ? -1.0 : 1.0;
    final fy = flipVertical ? -1.0 : 1.0;

    final dPanX = -factor * (cosA * fx * dImgX - sinA * fy * dImgY);
    final dPanY = -factor * (sinA * fx * dImgX + cosA * fy * dImgY);

    return pan + Offset(dPanX, dPanY);
  }

  /// Convert a point from viewport coordinates to original image coordinates,
  /// accounting for all transformations (rotation, scale, pan, flip, tilt).
  ///
  /// The full rendering pipeline applied by the Transform widget + BoxFit.contain is:
  ///   image-px → centre-relative → ×fitScale → flip → rotate → ×totalScale → +pan → tilt → +vpCentre
  ///
  /// This function inverts that pipeline in reverse order.
  /// [scale] must be `minScaleForRotation * userScale` (i.e. `totalScale`),
  /// NOT including fitScale — fitScale is computed internally.
  Offset viewportToImageCoordinates({
    required Offset viewportPoint,
    required Size viewportSize,
    required Size imageSize,
    required double rotationDegrees,
    required double scale,
    required Offset panOffset,
    required bool flipHorizontal,
    bool flipVertical = false,
    double tiltHorizontal = 0.0,
    double tiltVertical = 0.0,
  }) {
    final viewportCenter =
        Offset(viewportSize.width / 2, viewportSize.height / 2);

    // 0. Remove perspective tilt (outermost forward transform).
    Offset p = viewportPoint;
    if (tiltHorizontal != 0 || tiltVertical != 0) {
      final mTilt =
          buildPerspectiveMatrix(tiltHorizontal, tiltVertical, viewportCenter);
      final invTilt = Matrix4.inverted(mTilt);
      p = _applyPerspMatrix(invTilt, p);
    }

    // 1. Remove viewport centre offset.
    var point = p - viewportCenter;

    // 2. Remove pan.
    point = point - panOffset;

    // 3. Remove totalScale (minScaleForRotation * userScale).
    point = point / scale;

    // 4. Remove rotation.
    final angleRad = -rotationDegrees * math.pi / 180;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    point = Offset(
      point.dx * cosA - point.dy * sinA,
      point.dx * sinA + point.dy * cosA,
    );

    // 5. Remove flips.
    if (flipHorizontal) point = Offset(-point.dx, point.dy);
    if (flipVertical) point = Offset(point.dx, -point.dy);

    // 6. Remove BoxFit.contain fitScale.
    //    After steps 1-5 we are in SizedBox-centre-relative units where the
    //    image spans ±fitW/2 × ±fitH/2.  Dividing by fitScale converts to
    //    image-centre-relative pixels.
    final fitScale = math.min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );
    point = point / fitScale;

    // 7. Shift from image-centre-relative to image top-left origin.
    final imageCenter = Offset(imageSize.width / 2, imageSize.height / 2);
    point = point + imageCenter;

    return point;
  }

  /// Convert a point from original image coordinates to viewport coordinates.
  ///
  /// Forward pipeline (inverse of [viewportToImageCoordinates]):
  ///   image-px → centre-relative → ×fitScale → flip → rotate → ×totalScale → +pan → tilt → +vpCentre
  Offset imageToViewportCoordinates({
    required Offset imagePoint,
    required Size viewportSize,
    required Size imageSize,
    required double rotationDegrees,
    required double scale,
    required Offset panOffset,
    required bool flipHorizontal,
    bool flipVertical = false,
    double tiltHorizontal = 0.0,
    double tiltVertical = 0.0,
  }) {
    // 1. Shift from top-left origin to image-centre-relative.
    final imageCenter = Offset(imageSize.width / 2, imageSize.height / 2);
    var point = imagePoint - imageCenter;

    // 2. Apply BoxFit.contain fitScale → SizedBox-centre-relative units.
    final fitScale = math.min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );
    point = point * fitScale;

    // 3. Apply flips.
    if (flipHorizontal) point = Offset(-point.dx, point.dy);
    if (flipVertical) point = Offset(point.dx, -point.dy);

    // 4. Apply rotation.
    final angleRad = rotationDegrees * math.pi / 180;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    point = Offset(
      point.dx * cosA - point.dy * sinA,
      point.dx * sinA + point.dy * cosA,
    );

    // 5. Apply totalScale (minScaleForRotation * userScale).
    point = point * scale;

    // 6. Apply pan.
    point = point + panOffset;

    // 7. Add viewport centre offset.
    final viewportCenter =
        Offset(viewportSize.width / 2, viewportSize.height / 2);
    point = point + viewportCenter;

    // 8. Apply perspective tilt (outermost forward transform).
    if (tiltHorizontal != 0 || tiltVertical != 0) {
      final mTilt =
          buildPerspectiveMatrix(tiltHorizontal, tiltVertical, viewportCenter);
      point = _applyPerspMatrix(mTilt, point);
    }

    return point;
  }

  // ── Raycasting-based crop constraint ──────────────────────────────────────

  /// Clamps a single viewport-pixel point so that it lies within the visible
  /// image rectangle. Works by inverse-projecting the point into image-local
  /// coordinates, clamping to [0,W]×[0,H], then forward-projecting back.
  ///
  /// [totalScale] must be `minScaleForRotation * userScale` — the same scale
  /// factor used in the Transform widget.
  Offset constrainViewportPointToImage({
    required Offset viewportPxPoint,
    required Size imageSize,
    required Size viewportSize,
    required double rotationDegrees,
    required double totalScale,
    required Offset panOffset,
    required bool flipHorizontal,
    required bool flipVertical,
    double tiltHorizontal = 0.0,
    double tiltVertical = 0.0,
  }) {
    // 1. Project viewport → image-local px.
    final imagePoint = viewportToImageCoordinates(
      viewportPoint: viewportPxPoint,
      viewportSize: viewportSize,
      imageSize: imageSize,
      rotationDegrees: rotationDegrees,
      scale: totalScale,
      panOffset: panOffset,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
      tiltHorizontal: tiltHorizontal,
      tiltVertical: tiltVertical,
    );

    // 2. Clamp to image bounds [0, W] × [0, H].
    final clampedImage = Offset(
      imagePoint.dx.clamp(0.0, imageSize.width),
      imagePoint.dy.clamp(0.0, imageSize.height),
    );

    // 3. Project clamped image-local point back → viewport px.
    return imageToViewportCoordinates(
      imagePoint: clampedImage,
      viewportSize: viewportSize,
      imageSize: imageSize,
      rotationDegrees: rotationDegrees,
      scale: totalScale,
      panOffset: panOffset,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
      tiltHorizontal: tiltHorizontal,
      tiltVertical: tiltVertical,
    );
  }

  /// Constrains a [CropRect] (in viewport-fraction coordinates) so that all
  /// four corners lie within the visible image pixel boundary.
  ///
  /// This is the rotation-aware replacement for the old AABB `_clampToBounds`.
  /// Each corner is individually projected into image space, clamped, and
  /// projected back — so any rotation angle is handled correctly.
  ///
  /// [totalScale] must be `minScaleForRotation * userScale`.
  CropRect constrainCropRectToImage({
    required CropRect cropRect,
    required Size imageSize,
    required Size viewportSize,
    required double rotationDegrees,
    required double totalScale,
    required Offset panOffset,
    required bool flipHorizontal,
    required bool flipVertical,
    double tiltHorizontal = 0.0,
    double tiltVertical = 0.0,
  }) {
    const minFrac = 0.05;

    // Convert fraction corners to viewport-pixel corners.
    final vpW = viewportSize.width;
    final vpH = viewportSize.height;

    final tlPx = Offset(cropRect.left * vpW, cropRect.top * vpH);
    final trPx =
        Offset((cropRect.left + cropRect.width) * vpW, cropRect.top * vpH);
    final blPx =
        Offset(cropRect.left * vpW, (cropRect.top + cropRect.height) * vpH);
    final brPx = Offset((cropRect.left + cropRect.width) * vpW,
        (cropRect.top + cropRect.height) * vpH);

    // Constrain each corner to the visible image.
    Offset constrain(Offset p) => constrainViewportPointToImage(
          viewportPxPoint: p,
          imageSize: imageSize,
          viewportSize: viewportSize,
          rotationDegrees: rotationDegrees,
          totalScale: totalScale,
          panOffset: panOffset,
          flipHorizontal: flipHorizontal,
          flipVertical: flipVertical,
          tiltHorizontal: tiltHorizontal,
          tiltVertical: tiltVertical,
        );

    final cTL = constrain(tlPx);
    final cTR = constrain(trPx);
    final cBL = constrain(blPx);
    final cBR = constrain(brPx);

    // Derive bounding box of constrained corners (all in viewport px).
    final left = math.max(cTL.dx, cBL.dx); // inner left edge
    final top = math.max(cTL.dy, cTR.dy); // inner top edge
    final right = math.min(cTR.dx, cBR.dx); // inner right edge
    final bottom = math.min(cBL.dy, cBR.dy); // inner bottom edge

    // Ensure minimum size and convert back to fractions.
    final safeRight = math.max(right, left + minFrac * vpW);
    final safeBottom = math.max(bottom, top + minFrac * vpH);

    return CropRect(
      left: left / vpW,
      top: top / vpH,
      width: (safeRight - left) / vpW,
      height: (safeBottom - top) / vpH,
    );
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
