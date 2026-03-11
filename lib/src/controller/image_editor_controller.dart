import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:z_image_editor/image_editor.dart';

class ImageEditorController extends ChangeNotifier {
  ImageEditorState _state = const ImageEditorState();

  /// Animation controller for smooth transitions (set by the widget)
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<Offset>? _panAnimation;

  // Snap-to-viewport animation: interpolates the crop rect simultaneously
  // with scale and pan so the crop box smoothly zooms to fill the viewport.
  Animation<double>? _snapTAnimation;
  CropRect? _snapCropStart;
  CropRect? _snapCropEnd;

  ImageEditorState get state => _state;

  void _updateState(ImageEditorState newState) {
    _state = newState;
    notifyListeners();
  }

  /// Set the animation controller (called from widget's initState)
  void setAnimationController(AnimationController controller) {
    _animationController = controller;
    _animationController?.addListener(_onAnimationTick);
  }

  /// Clean up animation controller (called from widget's dispose)
  void disposeAnimationController() {
    _animationController?.removeListener(_onAnimationTick);
    _animationController = null;
  }

  void _onAnimationTick() {
    if (_scaleAnimation != null || _panAnimation != null) {
      final newScale = _scaleAnimation?.value ?? _state.scale;
      final newPan = _panAnimation?.value ?? _state.panOffset;

      if (_snapTAnimation != null &&
          _snapCropStart != null &&
          _snapCropEnd != null) {
        final newCrop = CropRect.lerp(
            _snapCropStart!, _snapCropEnd!, _snapTAnimation!.value);
        _updateState(
          _state.copyWith(
              scale: newScale, panOffset: newPan, cropRect: newCrop),
        );
      } else {
        _updateState(_state.copyWith(scale: newScale, panOffset: newPan));
      }

      // Clean up once the animation controller has finished.
      if (_animationController?.status == AnimationStatus.completed) {
        _snapTAnimation = null;
        _snapCropStart = null;
        _snapCropEnd = null;
        _scaleAnimation = null;
        _panAnimation = null;
      }
    }
  }

  void initialize({File? imageFile, Uint8List? imageBytes}) {
    _updateState(ImageEditorState(
      imageFile: imageFile,
      imageBytes: imageBytes,
    ));
  }

  void setTab(EditorTab tab) {
    if (tab == EditorTab.crop) {
      // Reset pan and zoom so the image is at its BoxFit.contain resting
      // position when crop mode is entered.  This ensures _fittedImageBounds()
      // (which uses pan=0, scale=1 assumptions) stays accurate.
      _updateState(_state.copyWith(
        currentTab: tab,
        scale: 1.0,
        panOffset: Offset.zero,
      ));
    } else {
      _updateState(_state.copyWith(currentTab: tab));
    }
  }

  // Adjustment controls
  void setBrightness(double value) {
    _updateState(_state.copyWith(brightness: value));
  }

  void setContrast(double value) {
    _updateState(_state.copyWith(contrast: value));
  }

  void setSaturation(double value) {
    _updateState(_state.copyWith(saturation: value));
  }

  // Rotation controls
  void rotate90() {
    final newRotation = (_state.rotation + 90) % 360;
    _updateState(_state.copyWith(rotation: newRotation, fineRotation: 0.0));
    _adjustScaleAndPanForRotation(animate: true);
  }

  void setFineRotation(double degrees) {
    _updateState(_state.copyWith(fineRotation: degrees));
    _adjustScaleAndPanForRotation(animate: false);
  }

  /// Clamp pan (and optionally animate) so the image always covers the crop
  /// window after a rotation change.  state.scale is the USER zoom (≥ 1.0);
  /// the Transform widget automatically applies minScaleForRotation on top.
  void _adjustScaleAndPanForRotation({bool animate = true}) {
    // Compute the minimum userScale required to keep the image covering the
    // current crop box (scales up if the crop box is large relative to the
    // rotated image footprint).
    final imgSize = _state.imageSize;
    final vpSize = _state.displaySize;
    double minUserScale = 1.0;
    if (imgSize != null && vpSize != null && _state.cropRect != null) {
      minUserScale = transformationService.calculateMinUserScaleForCrop(
        cropRect: _state.cropRect!,
        imageSize: imgSize,
        viewportSize: vpSize,
        rotationDegrees: _state.totalRotation,
      );
    }
    final targetScale = _state.scale.clamp(minUserScale, 4.0);
    // Start with the AABB clamp (fast, gives a valid starting point).
    var targetPan = transformationService.clampPanOffset(
      currentOffset: _state.panOffset,
      imageSize: _state.imageSize ?? const Size(100, 100),
      viewportSize: _state.displaySize ?? const Size(100, 100),
      rotationDegrees: _state.totalRotation,
      userScale: targetScale,
      cropViewport: _cropViewport(),
    );
    // Then apply exact raycasting correction so no crop corner escapes the image.
    if (imgSize != null && vpSize != null && _state.cropRect != null) {
      targetPan = transformationService.clampPanToCoverCrop(
        pan: targetPan,
        cropRect: _state.cropRect!,
        imageSize: imgSize,
        viewportSize: vpSize,
        rotationDegrees: _state.totalRotation,
        totalScale: _state.minScaleForRotation * targetScale,
        flipHorizontal: _state.flipHorizontal,
        flipVertical: _state.flipVertical,
      );
    }
    if (animate && _animationController != null) {
      _animateToScaleAndPan(targetScale, targetPan);
    } else {
      _updateState(_state.copyWith(
        scale: targetScale,
        panOffset: targetPan,
      ));
    }
  }

  /// Convert the current cropRect (viewport fractions) to a Rect in viewport px.
  Rect? _cropViewport() {
    final crop = _state.cropRect;
    final vp = _state.displaySize;
    if (crop == null || vp == null) return null;
    return Rect.fromLTWH(
      crop.left * vp.width,
      crop.top * vp.height,
      crop.width * vp.width,
      crop.height * vp.height,
    );
  }

  /// Animate scale, pan and crop rect simultaneously so that the current crop
  /// area smoothly expands to fill the viewport (the iOS snap behaviour).
  void animateSnapCrop({
    required double userScale,
    required Offset pan,
    required CropRect cropRect,
  }) {
    if (_animationController == null) return;
    _animationController!.stop();
    _animationController!.duration = const Duration(milliseconds: 350);

    _scaleAnimation = Tween<double>(begin: _state.scale, end: userScale)
        .animate(CurvedAnimation(
            parent: _animationController!, curve: Curves.easeInOut));
    _panAnimation = Tween<Offset>(begin: _state.panOffset, end: pan).animate(
        CurvedAnimation(
            parent: _animationController!, curve: Curves.easeInOut));
    _snapTAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _animationController!, curve: Curves.easeInOut));
    _snapCropStart = _state.cropRect;
    _snapCropEnd = cropRect;

    _animationController!.forward(from: 0.0);

    // Restore default animation duration for other animations.
    _animationController!.addStatusListener(_onSnapComplete);
  }

  void _onSnapComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _animationController?.duration = const Duration(milliseconds: 250);
      _animationController?.removeStatusListener(_onSnapComplete);
    }
  }

  /// Animate to a target scale and pan position
  void _animateToScaleAndPan(double targetScale, Offset targetPan) {
    if (_animationController == null) return;

    _animationController!.stop();

    _scaleAnimation = Tween<double>(
      begin: _state.scale,
      end: targetScale,
    ).animate(CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeOut,
    ));

    _panAnimation = Tween<Offset>(
      begin: _state.panOffset,
      end: targetPan,
    ).animate(CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeOut,
    ));

    _animationController!.forward(from: 0.0);
  }

  /// Return to minimum user zoom (1.0) with pan clamped for current rotation.
  void animateToMinScale() {
    final targetPan = transformationService.clampPanOffset(
      currentOffset: _state.panOffset,
      imageSize: _state.imageSize ?? const Size(100, 100),
      viewportSize: _state.displaySize ?? const Size(100, 100),
      rotationDegrees: _state.totalRotation,
      userScale: 1.0,
      cropViewport: _cropViewport(),
    );
    _animateToScaleAndPan(1.0, targetPan);
  }

  void flipHorizontal() {
    _updateState(_state.copyWith(flipHorizontal: !_state.flipHorizontal));
  }

  void flipVertical() {
    _updateState(_state.copyWith(flipVertical: !_state.flipVertical));
  }

  // ── Crop bounds helpers ────────────────────────────────────────────────────

  /// Returns the safe crop bounds in viewport-fraction units for use as an
  /// initialisation default and for resetCrop().  This AABB approximation is
  /// fine for a starting rect; drag-time constraint now uses raycasting.
  CropRect? _fittedImageBounds() {
    final imgSize = _state.imageSize;
    final vpSize = _state.displaySize;
    if (imgSize == null || vpSize == null) return null;
    final fitScale =
        math.min(vpSize.width / imgSize.width, vpSize.height / imgSize.height);
    final fitW = imgSize.width * fitScale;
    final fitH = imgSize.height * fitScale;

    // Scale up by minScaleForRotation to find the actual image coverage.
    // (In crop mode scale is always 1.0 — reset by setTab.)
    final rot = _state.minScaleForRotation;
    final scaledW = fitW * rot;
    final scaledH = fitH * rot;

    // If the image fills (or overflows) the viewport, the crop can go anywhere.
    if (scaledW >= vpSize.width - 0.5 && scaledH >= vpSize.height - 0.5) {
      return const CropRect(left: 0, top: 0, width: 1, height: 1);
    }

    return CropRect(
      left: (vpSize.width - scaledW) / 2 / vpSize.width,
      top: (vpSize.height - scaledH) / 2 / vpSize.height,
      width: scaledW / vpSize.width,
      height: scaledH / vpSize.height,
    );
  }

  // Crop controls
  void setCropRect(CropRect rect) {
    // Always clamp to the actual visible image — rotation-aware raycasting
    // ensures the crop box can never include black letterbox areas.
    final imgSize = _state.imageSize;
    final vpSize = _state.displaySize;
    final CropRect clamped;
    if (imgSize != null && vpSize != null) {
      clamped = transformationService.constrainCropRectToImage(
        cropRect: rect,
        imageSize: imgSize,
        viewportSize: vpSize,
        rotationDegrees: _state.totalRotation,
        totalScale: _state.minScaleForRotation * _state.scale,
        panOffset: _state.panOffset,
        flipHorizontal: _state.flipHorizontal,
        flipVertical: _state.flipVertical,
      );
    } else {
      // Sizes not yet known — store as-is; will be constrained once known.
      clamped = rect;
    }
    _updateState(_state.copyWith(cropRect: clamped));
    transformationService.clearCache();
    // Re-clamp pan in case the new crop window shrinks the allowed pan range.
    _adjustScaleAndPanForRotation(animate: false);
  }

  void resetCrop() {
    // Reset to the full safe image area (accounts for rotation scaling).
    final bounds = _fittedImageBounds();
    if (bounds != null) {
      _updateState(_state.copyWith(clearCropRect: false, cropRect: bounds));
    } else {
      _updateState(_state.copyWith(clearCropRect: true));
    }
    transformationService.clearCache();
  }

  // Aspect ratio preset
  void setAspectRatioPreset(AspectRatioPreset preset) {
    _updateState(_state.copyWith(aspectRatioPreset: preset));
    transformationService.clearCache();
  }

  // Zoom and pan controls
  /// Set user zoom scale.  In crop mode values below 1.0 are valid — the
  /// effective minimum is enforced by [calculateMinUserScaleForCrop].
  void setScale(double scale) {
    _updateState(_state.copyWith(scale: scale.clamp(0.05, 4.0)));
  }

  /// Set pan with clamping to keep the image covering the crop window.
  void setPanOffset(Offset offset) {
    final clamped = transformationService.clampPanOffset(
      currentOffset: offset,
      imageSize: _state.imageSize ?? const Size(100, 100),
      viewportSize: _state.displaySize ?? const Size(100, 100),
      rotationDegrees: _state.totalRotation,
      userScale: _state.scale,
      cropViewport: _cropViewport(),
    );
    _updateState(_state.copyWith(panOffset: clamped));
  }

  /// Set pan directly, bypassing clamping (caller is responsible for bounds).
  void setPanOffsetDirect(Offset offset) {
    _updateState(_state.copyWith(panOffset: offset));
  }

  void setDisplaySize(Size size) {
    final updated = _state.copyWith(displaySize: size);
    _state = updated;
    _maybeInitCropRect();
    notifyListeners();
  }

  void setImageSize(Size size) {
    final updated = _state.copyWith(imageSize: size);
    _state = updated;
    _maybeInitCropRect();
    notifyListeners();
  }

  /// When both imageSize and displaySize are first known, initialize the crop
  /// rect to the BoxFit.contain fitted image region — never the full viewport.
  /// This prevents black letterbox bars from appearing inside the crop area.
  void _maybeInitCropRect() {
    if (_state.cropRect != null) return; // already set
    final bounds = _fittedImageBounds();
    if (bounds == null) return;
    _state = _state.copyWith(cropRect: bounds);
    transformationService.clearCache();
  }

  /// Returns the currently fitted image rect in viewport space (pixels).
  /// Null until both imageSize and displaySize are known.
  Rect? get fittedImageRect {
    final imgSize = _state.imageSize;
    final vpSize = _state.displaySize;
    if (imgSize == null || vpSize == null) return null;
    final fitScale =
        math.min(vpSize.width / imgSize.width, vpSize.height / imgSize.height);
    final fitW = imgSize.width * fitScale;
    final fitH = imgSize.height * fitScale;
    return Rect.fromLTWH(
      (vpSize.width - fitW) / 2,
      (vpSize.height - fitH) / 2,
      fitW,
      fitH,
    );
  }

  void resetZoom() {
    _updateState(_state.copyWith(scale: 1.0, panOffset: Offset.zero));
  }

  // Reset all adjustments
  void reset() {
    _updateState(ImageEditorState(
      imageFile: _state.imageFile,
      imageBytes: _state.imageBytes,
      imageSize: _state.imageSize,
      displaySize: _state.displaySize,
    ));
    transformationService.clearCache();
    _maybeInitCropRect();
  }

  // Get the current image data
  dynamic get currentImage => _state.imageFile ?? _state.imageBytes;
}
