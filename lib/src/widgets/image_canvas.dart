import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:monogram_image_editor/image_editor.dart';
import 'package:monogram_image_editor/src/utils/image_processing.dart';

/// Interactive image canvas that displays the image with all transformations
class ImageCanvas extends StatefulWidget {
  final File? imageFile;
  final Uint8List? imageBytes;
  final ImageEditorController controller;

  const ImageCanvas({
    Key? key,
    this.imageFile,
    this.imageBytes,
    required this.controller,
  }) : super(key: key);

  @override
  State<ImageCanvas> createState() => _ImageCanvasState();
}

class _ImageCanvasState extends State<ImageCanvas>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  /// Actual pixel dimensions of the source image.
  Size? _imageSize;

  /// Last known viewport size (updated on every LayoutBuilder rebuild).
  Size _viewportSize = const Size(100, 100);

  /// Drives the canvas background fade when the user drags a crop handle.
  bool _isDraggingCropHandle = false;

  // ── Snap-to-viewport timer ────────────────────────────────────────────────
  Timer? _snapTimer;

  /// Cancel any pending snap and start a fresh 2-second countdown.
  void _scheduleSnap() {
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(seconds: 1), _onSnapTimer);
  }

  /// After 2 s of idle the crop box animates to fill the viewport so the user
  /// can see the selected region at full size.
  void _onSnapTimer() {
    if (!mounted) return;
    final state = widget.controller.state;
    if (state.currentTab != EditorTab.crop) return;
    final cropRect = state.cropRect;
    if (cropRect == null || _imageSize == null) return;

    final vpW = _viewportSize.width;
    final vpH = _viewportSize.height;
    final cw = cropRect.width * vpW;
    final ch = cropRect.height * vpH;

    // Scale factor to make the crop box exactly fill the viewport
    // (fit within viewport, preserving aspect ratio).
    final s = math.min(vpW / cw, vpH / ch);
    if (s <= 1.01) return; // already fills the viewport — nothing to do

    final minScaleForRotation = state.minScaleForRotation;
    final currentTotalScale = minScaleForRotation * state.scale;

    // Find the image pixel at the center of the current crop box.
    final cropCenterVp = Offset(
      (cropRect.left + cropRect.width / 2) * vpW,
      (cropRect.top + cropRect.height / 2) * vpH,
    );
    final imagePoint = transformationService.viewportToImageCoordinates(
      viewportPoint: cropCenterVp,
      viewportSize: _viewportSize,
      imageSize: _imageSize!,
      rotationDegrees: state.totalRotation,
      scale: currentTotalScale,
      panOffset: state.panOffset,
      flipHorizontal: state.flipHorizontal,
      flipVertical: state.flipVertical,
    );

    // New user scale (capped at 4×).
    final newUserScale = (state.scale * s).clamp(1.0, 4.0);
    final effectiveS =
        newUserScale / state.scale; // may differ from s if capped
    final newTotalScale = minScaleForRotation * newUserScale;

    // Compute the pan that puts the crop-center image pixel at the viewport center.
    // imageToViewportCoordinates with pan=0 gives: steps1to5 + vpCenter
    // We want: steps1to5 + newPan + vpCenter = vpCenter  →  newPan = -steps1to5
    //                                                        = vpCenter - vpPointZeroPan
    final vpCenter = Offset(vpW / 2, vpH / 2);
    final vpPointZeroPan = transformationService.imageToViewportCoordinates(
      imagePoint: imagePoint,
      viewportSize: _viewportSize,
      imageSize: _imageSize!,
      rotationDegrees: state.totalRotation,
      scale: newTotalScale,
      panOffset: Offset.zero,
      flipHorizontal: state.flipHorizontal,
      flipVertical: state.flipVertical,
    );
    final newPan = vpCenter - vpPointZeroPan;

    // New crop rect: same center, scaled by effectiveS, centered in viewport.
    final newCwPx = cw * effectiveS;
    final newChPx = ch * effectiveS;
    final newCropRect = CropRect(
      left: (vpW - newCwPx) / 2 / vpW,
      top: (vpH - newChPx) / 2 / vpH,
      width: newCwPx / vpW,
      height: newChPx / vpH,
    );

    widget.controller.animateSnapCrop(
      userScale: newUserScale,
      pan: newPan,
      cropRect: newCropRect,
    );
  }

  // ── Gesture state ──────────────────────────────────────────────────────────
  Offset _gestureStartPan = Offset.zero;
  double _gestureStartUserScale = 1.0;
  Offset _gestureStartFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    widget.controller.setAnimationController(_animationController);
  }

  @override
  void dispose() {
    _snapTimer?.cancel();
    widget.controller.disposeAnimationController();
    _animationController.dispose();
    super.dispose();
  }

  // ── Gesture handlers ───────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    _snapTimer?.cancel(); // don't snap while user is actively interacting
    _gestureStartPan = widget.controller.state.panOffset;
    _gestureStartUserScale = widget.controller.state.scale;
    _gestureStartFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final state = widget.controller.state;
    final vpSize = _viewportSize;
    final vpCenter = Offset(vpSize.width / 2, vpSize.height / 2);

    // ── User scale ──────────────────────────────────────────────────────────
    // Minimum scale is dynamic: the user cannot zoom out past the point where
    // the image stops covering the current crop box.  This is the foundational
    // invariant — the crop box is NEVER auto-modified; IMAGE movement is
    // constrained instead.
    final minUserScale = state.cropRect != null && _imageSize != null
        ? transformationService.calculateMinUserScaleForCrop(
            cropRect: state.cropRect!,
            imageSize: _imageSize!,
            viewportSize: vpSize,
            rotationDegrees: state.totalRotation,
          )
        : 1.0;
    final newUserScale =
        (_gestureStartUserScale * details.scale).clamp(minUserScale, 4.0);

    // ── Pan: zoom around focal point + translate with finger movement ───────
    // For any scale ratio r = totalScaleNew / totalScaleStart, keeping the
    // focal-start point visually fixed requires:
    //   pan_new = (1−r)·(focalStart − vpCenter) + r·panStart
    // Then we add the focal-point translation component separately:
    //   pan_new += (focalCurrent − focalStart)
    final minScale = state.minScaleForRotation;
    final totalScaleStart = minScale * _gestureStartUserScale;
    final totalScaleNew = minScale * newUserScale;
    final r = totalScaleStart > 0 ? totalScaleNew / totalScaleStart : 1.0;

    final rawPan = (_gestureStartFocalPoint - vpCenter) * (1 - r) +
        _gestureStartPan * r +
        (details.localFocalPoint - _gestureStartFocalPoint);

    // ── Clamp pan to keep image covering the crop window ───────────────────
    // In crop mode: use exact raycasting (projects all 4 crop corners into
    // image space and pushes the pan just enough to cover them all).
    // Outside crop mode: use the faster AABB approximation.
    final Offset clampedPan;
    if (state.currentTab == EditorTab.crop &&
        state.cropRect != null &&
        _imageSize != null) {
      final totalScale = state.minScaleForRotation * newUserScale;
      clampedPan = transformationService.clampPanToCoverCrop(
        pan: rawPan,
        cropRect: state.cropRect!,
        imageSize: _imageSize!,
        viewportSize: vpSize,
        rotationDegrees: state.totalRotation,
        totalScale: totalScale,
        flipHorizontal: state.flipHorizontal,
        flipVertical: state.flipVertical,
      );
    } else {
      clampedPan = transformationService.clampPanOffset(
        currentOffset: rawPan,
        imageSize: _imageSize ?? const Size(100, 100),
        viewportSize: vpSize,
        rotationDegrees: state.totalRotation,
        userScale: newUserScale,
        cropViewport: _cropViewport(state, vpSize),
      );
    }

    widget.controller.setScale(newUserScale);
    widget.controller.setPanOffsetDirect(clampedPan);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // Final clamp to correct any floating-point drift accumulated during gesture.
    final state = widget.controller.state;
    final Offset clamped;
    if (state.currentTab == EditorTab.crop &&
        state.cropRect != null &&
        _imageSize != null) {
      final totalScale = state.minScaleForRotation * state.scale;
      clamped = transformationService.clampPanToCoverCrop(
        pan: state.panOffset,
        cropRect: state.cropRect!,
        imageSize: _imageSize!,
        viewportSize: _viewportSize,
        rotationDegrees: state.totalRotation,
        totalScale: totalScale,
        flipHorizontal: state.flipHorizontal,
        flipVertical: state.flipVertical,
      );
    } else {
      clamped = transformationService.clampPanOffset(
        currentOffset: state.panOffset,
        imageSize: _imageSize ?? const Size(100, 100),
        viewportSize: _viewportSize,
        rotationDegrees: state.totalRotation,
        userScale: state.scale,
        cropViewport: _cropViewport(state, _viewportSize),
      );
    }
    if (clamped != state.panOffset) {
      widget.controller.setPanOffsetDirect(clamped);
    }
    // Note: the crop rect is NOT re-constrained here.  clampPanOffset already
    // ensures the image always covers the crop box, so auto-reconstraining
    // would only shrink what the user deliberately set.
    if (state.currentTab == EditorTab.crop) _scheduleSnap();
  }

  /// Convert the state's cropRect (viewport fractions) to viewport-pixel Rect.
  Rect? _cropViewport(ImageEditorState state, Size vpSize) {
    final cr = state.cropRect;
    if (cr == null) return null;
    return Rect.fromLTWH(
      cr.left * vpSize.width,
      cr.top * vpSize.height,
      cr.width * vpSize.width,
      cr.height * vpSize.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final state = widget.controller.state;

        // ── Build image widget ──────────────────────────────────────────────
        Widget imageWidget;
        if (widget.imageFile != null) {
          imageWidget = Image.file(
            widget.imageFile!,
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _resolveImageSize();
                });
              }
              return child;
            },
          );
        } else if (widget.imageBytes != null) {
          imageWidget = Image.memory(
            widget.imageBytes!,
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _resolveImageSize();
                });
              }
              return child;
            },
          );
        } else {
          return const Center(
            child: Text(
              'No image loaded',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: 1.0,
            end: _isDraggingCropHandle ? 0.0 : 1.0,
          ),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          builder: (context, bgOpacity, child) => Container(
            color: const Color(0xFF1C1C1E).withOpacity(bgOpacity),
            child: child,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final vpSize = Size(constraints.maxWidth, constraints.maxHeight);

              // Keep controller's displaySize / viewportSize in sync.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _viewportSize = vpSize;
                  widget.controller.setDisplaySize(vpSize);
                }
              });

              // ── Color filter (real-time preview) ─────────────────────────
              Widget content = imageWidget;
              if (state.brightness != 0 ||
                  state.contrast != 1.0 ||
                  state.saturation != 1.0) {
                content = ColorFiltered(
                  colorFilter: ColorFilterMatrix.combined(
                    brightness: state.brightness,
                    contrast: state.contrast,
                    saturation: state.saturation,
                  ),
                  child: content,
                );
              }

              // ── Single unified Transform ──────────────────────────────────
              // Matrix: T(pan) * S(minScale·userScale) * R(angle) * S(flip)
              // with pivot at Alignment.center (= viewport centre = image centre
              // for BoxFit.contain).
              //
              // All components live in the SAME widget tree, so rotation,
              // scale-compensation, user-zoom and pan are always in sync with
              // no one-frame lag or double-application.
              final totalScale = state.minScaleForRotation * state.scale;
              final transformedImage = Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translate(state.panOffset.dx, state.panOffset.dy, 0.0)
                  ..scale(totalScale)
                  ..rotateZ(state.totalRotation * math.pi / 180)
                  ..scale(
                    state.flipHorizontal ? -1.0 : 1.0,
                    state.flipVertical ? -1.0 : 1.0,
                    1.0,
                  ),
                // SizedBox ensures the Image widget receives tight constraints
                // equal to the viewport so BoxFit.contain letterboxes correctly
                // and the transform pivots at the image centre.
                child: SizedBox(
                  width: vpSize.width,
                  height: vpSize.height,
                  child: content,
                ),
              );

              // ── Crop rect in viewport pixels ──────────────────────────────
              final cropVpRect = state.cropRect != null
                  ? Rect.fromLTWH(
                      state.cropRect!.left * vpSize.width,
                      state.cropRect!.top * vpSize.height,
                      state.cropRect!.width * vpSize.width,
                      state.cropRect!.height * vpSize.height,
                    )
                  : null;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Pan/zoom is always active — in crop mode the crop overlay
                // handles consume touches on the handles/interior first.
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Image clipped to viewport bounds.
                    ClipRect(child: transformedImage),

                    // CropOverlay lives OUTSIDE ClipRect so corner/edge handles
                    // are never clipped at the screen edges.
                    if (state.currentTab == EditorTab.crop)
                      Positioned.fill(
                        child: CropOverlay(
                          cropRect: state.cropRect,
                          imageSize: _imageSize,
                          viewportSize: vpSize,
                          totalRotation: state.totalRotation,
                          totalScale: state.minScaleForRotation * state.scale,
                          panOffset: state.panOffset,
                          flipHorizontal: state.flipHorizontal,
                          flipVertical: state.flipVertical,
                          aspectRatioPreset: state.aspectRatioPreset,
                          onCropChanged: widget.controller.setCropRect,
                          onCropDragEnd: _scheduleSnap,
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                          onHandleDragChanged: (dragging) {
                            setState(() {
                              _isDraggingCropHandle = dragging;
                            });
                          },
                        ),
                      ),

                    // Static crop indicator on other tabs (no handles).
                    if (state.currentTab != EditorTab.crop &&
                        cropVpRect != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: CropOverlayPainter(cropRect: cropVpRect),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Resolve the actual image dimensions
  Future<void> _resolveImageSize() async {
    if (_imageSize != null) return;

    ImageProvider imageProvider;
    if (widget.imageFile != null) {
      imageProvider = FileImage(widget.imageFile!);
    } else if (widget.imageBytes != null) {
      imageProvider = MemoryImage(widget.imageBytes!);
    } else {
      return;
    }

    final stream = imageProvider.resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      if (mounted && _imageSize != size) {
        setState(() {
          _imageSize = size;
        });
        widget.controller.setImageSize(size);
      }
    }));
  }
}

/// Crop overlay with draggable corners and edges.
///
/// All handle/interior drags are constrained via raycasting: each proposed
/// corner is inverse-projected into image-local coordinates, clamped to the
/// image rectangle, and projected back. This means the crop box can NEVER
/// extend outside the actual visible image, regardless of rotation or flips.
class CropOverlay extends StatefulWidget {
  final CropRect? cropRect;

  // Transform params forwarded from the controller/canvas — used for the
  // raycasting constraint (replaces the old AABB imageBounds approach).
  final Size? imageSize;
  final Size viewportSize;
  final double totalRotation;
  final double totalScale;
  final Offset panOffset;
  final bool flipHorizontal;
  final bool flipVertical;

  final AspectRatioPreset aspectRatioPreset;
  final Function(CropRect) onCropChanged;

  /// Called when the user lifts their finger after dragging any crop handle
  /// or the crop interior.  The canvas uses this to schedule the
  /// snap-to-viewport animation.
  final VoidCallback? onCropDragEnd;

  /// Forwarded to the canvas's _onScaleStart/Update/End so that pinch-zoom
  /// gestures begun inside the crop interior reach the image transform logic.
  final void Function(ScaleStartDetails)? onScaleStart;
  final void Function(ScaleUpdateDetails)? onScaleUpdate;
  final void Function(ScaleEndDetails)? onScaleEnd;

  /// Called with `true` when the user starts dragging a corner/edge handle
  /// and with `false` when the drag ends.  Used by the parent canvas to
  /// fade the background so the image shows through.
  final void Function(bool)? onHandleDragChanged;

  const CropOverlay({
    Key? key,
    this.cropRect,
    required this.imageSize,
    required this.viewportSize,
    required this.totalRotation,
    required this.totalScale,
    required this.panOffset,
    required this.flipHorizontal,
    required this.flipVertical,
    this.aspectRatioPreset = AspectRatioPreset.free,
    required this.onCropChanged,
    this.onCropDragEnd,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.onHandleDragChanged,
  }) : super(key: key);

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  CropRect? _currentRect;
  CropRect? _dragStartRect;

  /// True while the user is dragging a corner or edge handle — drives the
  /// overlay opacity animation (0 → transparent when idle, 0.5 → dim when
  /// resizing so the cropped-out image region is subtly visible).
  bool _isDraggingHandle = false;

  /// Get the target aspect ratio (null = free form)
  double? get _targetAspectRatio => widget.aspectRatioPreset.ratio;

  // ── Raycasting constraint helper ──────────────────────────────────────────

  /// Returns true when all transform info needed for raycasting is available.
  bool get _canConstrain => widget.imageSize != null;

  /// Constrain [rect] so every corner stays inside the visible image AND
  /// inside the viewport bounds [0, 1] × [0, 1].
  /// Falls back to viewport-only clamping when imageSize is not yet known.
  CropRect _constrain(CropRect rect) {
    if (_canConstrain) {
      rect = transformationService.constrainCropRectToImage(
        cropRect: rect,
        imageSize: widget.imageSize!,
        viewportSize: widget.viewportSize,
        rotationDegrees: widget.totalRotation,
        totalScale: widget.totalScale,
        panOffset: widget.panOffset,
        flipHorizontal: widget.flipHorizontal,
        flipVertical: widget.flipVertical,
      );
    }
    return _clampToViewport(rect);
  }

  /// Clamp [rect] so it never extends outside the viewport (fractions in [0,1]).
  /// A 16 px horizontal inset is applied on each side so corner handles are
  /// always fully visible and never clipped at the screen edges.
  CropRect _clampToViewport(CropRect rect) {
    const minSize = 0.05;
    // Convert 16 px inset to viewport fractions.
    final hInset =
        widget.viewportSize.width > 0 ? 16.0 / widget.viewportSize.width : 0.0;
    final left = rect.left.clamp(hInset, 1.0 - hInset - minSize);
    final top = rect.top.clamp(0.0, 1.0 - minSize);
    final right = (left + rect.width).clamp(left + minSize, 1.0 - hInset);
    final bottom = (top + rect.height).clamp(top + minSize, 1.0);
    return CropRect(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }

  /// Variant of [_constrain] used for interior-pan (translate) gestures.
  /// Preserves the user's crop size: instead of shrinking the rect when an
  @override
  void initState() {
    super.initState();
    _initializeRect();
  }

  void _initializeRect() {
    if (widget.cropRect != null) {
      _currentRect = _constrain(widget.cropRect!);
    } else if (_canConstrain) {
      // Default: image-filling rect (will be constrained automatically).
      _currentRect = _constrain(const CropRect(
        left: 0,
        top: 0,
        width: 1,
        height: 1,
      ));
    }
  }

  @override
  void didUpdateWidget(CropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // cropRect pushed from controller (e.g. resetCrop, aspect-ratio change).
    // Note: when the transform changes (pan/zoom/rotation) we do NOT
    // auto-recalculate the crop rect.  clampPanOffset keeps the image
    // covering the crop box, so the crop never escapes the image and
    // shrinking it automatically would override the user's explicit size.
    if (widget.cropRect != oldWidget.cropRect) {
      final incoming = widget.cropRect;
      if (incoming == null) {
        // Re-initialise to image-filling default.
        if (_canConstrain) {
          _currentRect =
              _constrain(const CropRect(left: 0, top: 0, width: 1, height: 1));
        }
      } else {
        _currentRect = _constrain(incoming);
      }
    }

    // Aspect ratio preset changed.
    if (widget.aspectRatioPreset != oldWidget.aspectRatioPreset &&
        widget.aspectRatioPreset != AspectRatioPreset.free) {
      _adjustToAspectRatio();
    }
  }

  /// Adjust the current rect to match the target aspect ratio
  void _adjustToAspectRatio() {
    if (_currentRect == null || _targetAspectRatio == null) return;

    final rect = _currentRect!;
    final currentAspect = rect.width / rect.height;
    final targetAspect = _targetAspectRatio!;

    double newWidth = rect.width;
    double newHeight = rect.height;

    if (currentAspect > targetAspect) {
      newWidth = rect.height * targetAspect;
    } else {
      newHeight = rect.width / targetAspect;
    }

    final left = rect.left + (rect.width - newWidth) / 2;
    final top = rect.top + (rect.height - newHeight) / 2;

    final proposed = CropRect(
      left: left,
      top: top,
      width: newWidth,
      height: newHeight,
    );

    setState(() {
      _currentRect = _constrain(proposed);
    });
    final toNotify = _currentRect!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCropChanged(toNotify);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentRect == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = _currentRect!;
        final left = rect.left * constraints.maxWidth;
        final top = rect.top * constraints.maxHeight;
        final width = rect.width * constraints.maxWidth;
        final height = rect.height * constraints.maxHeight;

        return Stack(
          children: [
            // Dark overlay outside crop area — animated opacity.
            // Idle: fully transparent (background color shows through).
            // Resizing: semi-transparent so the image under the overlay is visible.
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 1.0,
                  end: _isDraggingHandle ? 0.5 : 1.0,
                ),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                builder: (context, opacity, _) => CustomPaint(
                  painter: CropOverlayPainter(
                    cropRect: Rect.fromLTWH(left, top, width, height),
                    overlayOpacity: opacity,
                  ),
                ),
              ),
            ),

            // Crop interior: all gestures (pan + pinch) move/zoom the image
            // behind the crop box — exactly like iOS Photos.
            // Resizing/moving the crop box is done via the edge and corner handles.
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) {
                  widget.onScaleStart?.call(details);
                },
                onScaleUpdate: (details) {
                  widget.onScaleUpdate?.call(details);
                },
                onScaleEnd: (details) {
                  widget.onScaleEnd?.call(details);
                },
                child: CustomPaint(
                  painter: GridPainter(),
                ),
              ),
            ),

            // Corner handles
            _buildHandle(left, top, Alignment.topLeft, constraints),
            _buildHandle(left + width, top, Alignment.topRight, constraints),
            _buildHandle(left, top + height, Alignment.bottomLeft, constraints),
            _buildHandle(
                left + width, top + height, Alignment.bottomRight, constraints),

            // Edge handles
            _buildEdgeHandle(left + width / 2, top, 'top', constraints),
            _buildEdgeHandle(
                left + width / 2, top + height, 'bottom', constraints),
            _buildEdgeHandle(left, top + height / 2, 'left', constraints),
            _buildEdgeHandle(
                left + width, top + height / 2, 'right', constraints),
          ],
        );
      },
    );
  }

  Widget _buildHandle(
      double x, double y, Alignment alignment, BoxConstraints constraints) {
    return Positioned(
      left: x - 15,
      top: y - 15,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          setState(() {
            _dragStartRect = _currentRect;
            _isDraggingHandle = true;
          });
          widget.onHandleDragChanged?.call(true);
        },
        onPanUpdate: (details) {
          if (_dragStartRect == null) return;

          final dx = details.delta.dx / constraints.maxWidth;
          final dy = details.delta.dy / constraints.maxHeight;

          setState(() {
            var newRect = _dragStartRect!;

            if (_targetAspectRatio != null) {
              newRect = _handleAspectRatioConstrainedDrag(
                  newRect, dx, dy, alignment, constraints);
            } else {
              newRect = _handleFreeFormDrag(newRect, dx, dy, alignment);
            }

            _currentRect = _constrain(newRect);
            _dragStartRect = _currentRect;
          });
          widget.onCropChanged(_currentRect!);
        },
        onPanEnd: (_) {
          setState(() {
            _dragStartRect = null;
            _isDraggingHandle = false;
          });
          widget.onHandleDragChanged?.call(false);
          widget.onCropDragEnd?.call();
        },
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle free-form dragging (no aspect ratio constraint).
  /// Returns the raw (unconstrained) proposed rect — constraint is applied
  /// centrally in _constrain() after this returns.
  CropRect _handleFreeFormDrag(
      CropRect rect, double dx, double dy, Alignment alignment) {
    const minSize = 0.05;

    if (alignment == Alignment.topLeft) {
      final newLeft = rect.left + dx;
      final newTop = rect.top + dy;
      final newWidth = (rect.width - dx).clamp(minSize, double.infinity);
      final newHeight = (rect.height - dy).clamp(minSize, double.infinity);
      return CropRect(
          left: newLeft, top: newTop, width: newWidth, height: newHeight);
    } else if (alignment == Alignment.topRight) {
      final newTop = rect.top + dy;
      final newWidth = (rect.width + dx).clamp(minSize, double.infinity);
      final newHeight = (rect.height - dy).clamp(minSize, double.infinity);
      return CropRect(
          left: rect.left, top: newTop, width: newWidth, height: newHeight);
    } else if (alignment == Alignment.bottomLeft) {
      final newLeft = rect.left + dx;
      final newWidth = (rect.width - dx).clamp(minSize, double.infinity);
      final newHeight = (rect.height + dy).clamp(minSize, double.infinity);
      return CropRect(
          left: newLeft, top: rect.top, width: newWidth, height: newHeight);
    } else {
      // bottomRight
      final newWidth = (rect.width + dx).clamp(minSize, double.infinity);
      final newHeight = (rect.height + dy).clamp(minSize, double.infinity);
      return CropRect(
          left: rect.left, top: rect.top, width: newWidth, height: newHeight);
    }
  }

  /// Handle aspect-ratio-constrained dragging.
  CropRect _handleAspectRatioConstrainedDrag(
    CropRect rect,
    double dx,
    double dy,
    Alignment alignment,
    BoxConstraints constraints,
  ) {
    final aspectRatio = _targetAspectRatio!;

    final absDx = dx.abs();
    final absDy = dy.abs();

    double scale;
    if (absDx > absDy) {
      scale = dx *
          (alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
              ? -1
              : 1);
    } else {
      scale = dy *
          aspectRatio *
          (alignment == Alignment.topLeft || alignment == Alignment.topRight
              ? -1
              : 1);
    }

    double newWidth = (rect.width + scale).clamp(0.05, 1.0);
    double newHeight = newWidth / aspectRatio;

    if (newHeight < 0.05) {
      newHeight = 0.05;
      newWidth = newHeight * aspectRatio;
    }

    double newLeft = rect.left;
    double newTop = rect.top;

    if (alignment == Alignment.topLeft) {
      newLeft = rect.left + rect.width - newWidth;
      newTop = rect.top + rect.height - newHeight;
    } else if (alignment == Alignment.topRight) {
      newTop = rect.top + rect.height - newHeight;
    } else if (alignment == Alignment.bottomLeft) {
      newLeft = rect.left + rect.width - newWidth;
    }

    // The raycasting constraint in _constrain() will tighten to the actual
    // image boundary; no AABB pre-clamp needed here.
    return CropRect(
      left: newLeft,
      top: newTop,
      width: newWidth,
      height: newHeight,
    );
  }

  Widget _buildEdgeHandle(
      double x, double y, String edge, BoxConstraints constraints) {
    final isHorizontal = edge == 'top' || edge == 'bottom';

    return Positioned(
      left: x - (isHorizontal ? 15 : 4),
      top: y - (isHorizontal ? 4 : 15),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          setState(() {
            _dragStartRect = _currentRect;
            _isDraggingHandle = true;
          });
          widget.onHandleDragChanged?.call(true);
        },
        onPanUpdate: (details) {
          if (_dragStartRect == null) return;

          final dx = details.delta.dx / constraints.maxWidth;
          final dy = details.delta.dy / constraints.maxHeight;

          setState(() {
            var newRect = _dragStartRect!;
            const minSize = 0.05;

            if (edge == 'top') {
              final newTop = newRect.top + dy;
              final newHeight =
                  (newRect.height - dy).clamp(minSize, double.infinity);
              newRect = CropRect(
                  left: newRect.left,
                  top: newTop,
                  width: newRect.width,
                  height: newHeight);
            } else if (edge == 'bottom') {
              final newHeight =
                  (newRect.height + dy).clamp(minSize, double.infinity);
              newRect = CropRect(
                  left: newRect.left,
                  top: newRect.top,
                  width: newRect.width,
                  height: newHeight);
            } else if (edge == 'left') {
              final newLeft = newRect.left + dx;
              final newWidth =
                  (newRect.width - dx).clamp(minSize, double.infinity);
              newRect = CropRect(
                  left: newLeft,
                  top: newRect.top,
                  width: newWidth,
                  height: newRect.height);
            } else if (edge == 'right') {
              final newWidth =
                  (newRect.width + dx).clamp(minSize, double.infinity);
              newRect = CropRect(
                  left: newRect.left,
                  top: newRect.top,
                  width: newWidth,
                  height: newRect.height);
            }

            _currentRect = _constrain(newRect);
            _dragStartRect = _currentRect;
          });
          widget.onCropChanged(_currentRect!);
        },
        onPanEnd: (_) {
          setState(() {
            _dragStartRect = null;
            _isDraggingHandle = false;
          });
          widget.onHandleDragChanged?.call(false);
          widget.onCropDragEnd?.call();
        },
        child: Container(
          width: isHorizontal ? 30 : 8,
          height: isHorizontal ? 8 : 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CropOverlayPainter extends CustomPainter {
  final Rect cropRect;

  /// 0.0 = fully transparent (shows background), 0.5 = semi-opaque dim.
  final double overlayOpacity;

  CropOverlayPainter({required this.cropRect, this.overlayOpacity = 0.5});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw dark overlay around crop area (only when opacity > 0).
    if (overlayOpacity > 0) {
      final paint = Paint()
        ..color = const Color(0xFF1C1C1E).withOpacity(overlayOpacity)
        ..style = PaintingStyle.fill;

      final path = Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRect(cropRect)
        ..fillType = PathFillType.evenOdd;

      canvas.drawPath(path, paint);
    }

    // Always draw white border so the crop boundary is always visible.
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(cropRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.overlayOpacity != overlayOpacity;
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1;

    // Draw rule of thirds grid
    for (int i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
