import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:monogram_image_editor/image_editor.dart';
import 'package:monogram_image_editor/monogram_image_editor.dart';

class ImageEditorController extends ChangeNotifier {
  ImageEditorState _state = const ImageEditorState();

  /// Animation controller for smooth transitions (set by the widget)
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<Offset>? _panAnimation;

  /// Callback to update the TransformationController externally
  void Function(Matrix4)? onTransformationUpdate;

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

      _updateState(_state.copyWith(
        scale: newScale,
        panOffset: newPan,
      ));

      // Notify the widget to update the transformation matrix
      _updateTransformationMatrix(newScale, newPan);
    }
  }

  void _updateTransformationMatrix(double scale, Offset pan) {
    if (onTransformationUpdate != null) {
      final matrix = Matrix4.identity()
        ..translate(pan.dx, pan.dy)
        ..scale(scale);
      onTransformationUpdate!(matrix);
    }
  }

  void initialize({File? imageFile, Uint8List? imageBytes}) {
    _updateState(ImageEditorState(
      imageFile: imageFile,
      imageBytes: imageBytes,
    ));
  }

  void setTab(EditorTab tab) {
    _updateState(_state.copyWith(currentTab: tab));
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

  /// Adjust scale and pan to ensure the image covers the crop area after rotation
  void _adjustScaleAndPanForRotation({bool animate = true}) {
    final minScale = _state.minScaleForRotation;
    final currentScale = _state.scale;

    // If current scale is below minimum, adjust it
    double targetScale = currentScale;
    if (currentScale < minScale) {
      targetScale = minScale;
    }

    // Clamp pan to valid bounds at the target scale
    final maxPan = transformationService.calculateMaxPanOffset(
      imageSize: _state.imageSize ?? const Size(100, 100),
      viewportSize: _state.displaySize ?? const Size(100, 100),
      rotationDegrees: _state.totalRotation,
      currentScale: targetScale,
    );

    final targetPan = Offset(
      _state.panOffset.dx.clamp(-maxPan.dx, maxPan.dx),
      _state.panOffset.dy.clamp(-maxPan.dy, maxPan.dy),
    );

    if (animate && _animationController != null) {
      _animateToScaleAndPan(targetScale, targetPan);
    } else {
      _updateState(_state.copyWith(
        scale: targetScale,
        panOffset: targetPan,
      ));
      _updateTransformationMatrix(targetScale, targetPan);
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

  /// Animate to minimum scale (for returning to 0° rotation)
  void animateToMinScale() {
    final minScale = _state.minScaleForRotation;
    _animateToScaleAndPan(minScale, _state.clampedPanOffset);
  }

  void flipHorizontal() {
    _updateState(_state.copyWith(flipHorizontal: !_state.flipHorizontal));
  }

  void flipVertical() {
    _updateState(_state.copyWith(flipVertical: !_state.flipVertical));
  }

  // Crop controls
  void setCropRect(CropRect rect) {
    _updateState(_state.copyWith(cropRect: rect));
    // Clear transformation service cache when crop changes
    transformationService.clearCache();
  }

  void resetCrop() {
    _updateState(_state.copyWith(clearCropRect: true));
    transformationService.clearCache();
  }

  // Aspect ratio preset
  void setAspectRatioPreset(AspectRatioPreset preset) {
    _updateState(_state.copyWith(aspectRatioPreset: preset));
    transformationService.clearCache();
  }

  // Zoom and pan controls
  void setScale(double scale) {
    // Ensure scale doesn't go below minimum for current rotation
    final minScale = _state.minScaleForRotation;
    final clampedScale = scale.clamp(minScale, 4.0);
    _updateState(_state.copyWith(scale: clampedScale));
  }

  void setPanOffset(Offset offset) {
    // Clamp pan to valid bounds
    final clamped = transformationService.clampPanOffset(
      currentOffset: offset,
      imageSize: _state.imageSize ?? const Size(100, 100),
      viewportSize: _state.displaySize ?? const Size(100, 100),
      rotationDegrees: _state.totalRotation,
      currentScale: _state.scale,
    );
    _updateState(_state.copyWith(panOffset: clamped));
  }

  void setDisplaySize(Size size) {
    _updateState(_state.copyWith(displaySize: size));
  }

  void setImageSize(Size size) {
    _updateState(_state.copyWith(imageSize: size));
  }

  void resetZoom() {
    final minScale = _state.minScaleForRotation;
    _updateState(_state.copyWith(scale: minScale, panOffset: Offset.zero));
    _updateTransformationMatrix(minScale, Offset.zero);
  }

  // Reset all adjustments
  void reset() {
    // Preserve image source and sizes, reset everything else
    _updateState(ImageEditorState(
      imageFile: _state.imageFile,
      imageBytes: _state.imageBytes,
      imageSize: _state.imageSize,
      displaySize: _state.displaySize,
    ));
    transformationService.clearCache();

    // Reset the transformation controller to identity (scale 1.0, no pan)
    _updateTransformationMatrix(1.0, Offset.zero);
  }

  // Get the current image data
  dynamic get currentImage => _state.imageFile ?? _state.imageBytes;
}
