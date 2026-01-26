import 'dart:io';
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
  final TransformationController _transformationController =
      TransformationController();
  late AnimationController _animationController;

  /// Track the actual image dimensions
  Size? _imageSize;

  /// Flag to prevent recursive updates
  bool _isUpdatingTransform = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Connect animation controller to the editor controller
    widget.controller.setAnimationController(_animationController);
    widget.controller.onTransformationUpdate = _onControllerTransformUpdate;

    // Listen for external transformation changes
    _transformationController.addListener(_onTransformationChanged);
  }

  void _onControllerTransformUpdate(Matrix4 matrix) {
    if (!_isUpdatingTransform) {
      _isUpdatingTransform = true;
      _transformationController.value = matrix;
      _isUpdatingTransform = false;
    }
  }

  void _onTransformationChanged() {
    if (_isUpdatingTransform) return;

    _isUpdatingTransform = true;
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();

    // Clamp scale between 1.0 and 4.0 (Transform handles rotation compensation)
    final clampedScale = scale.clamp(1.0, 4.0);

    // Clamp pan to valid bounds
    final clampedPan = transformationService.clampPanOffset(
      currentOffset: Offset(translation.x, translation.y),
      imageSize: _imageSize ?? const Size(100, 100),
      viewportSize: widget.controller.state.displaySize ?? const Size(100, 100),
      rotationDegrees: widget.controller.state.totalRotation,
      currentScale: clampedScale,
    );

    // If we needed to clamp, update the transformation controller
    if (clampedScale != scale ||
        clampedPan.dx != translation.x ||
        clampedPan.dy != translation.y) {
      final correctedMatrix = Matrix4.identity()
        ..translate(clampedPan.dx, clampedPan.dy)
        ..scale(clampedScale);
      _transformationController.value = correctedMatrix;
    }

    widget.controller.setScale(clampedScale);
    widget.controller.setPanOffset(clampedPan);

    _isUpdatingTransform = false;
  }

  @override
  void dispose() {
    widget.controller.disposeAnimationController();
    widget.controller.onTransformationUpdate = null;
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final state = widget.controller.state;

        // Calculate dynamic minScale based on current rotation
        final minScale = state.minScaleForRotation;

        Widget imageWidget;

        if (widget.imageFile != null) {
          imageWidget = Image.file(
            widget.imageFile!,
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              // Get image dimensions when loaded
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

        // Apply transformations
        Widget transformedImage = imageWidget;

        // Apply color filters for real-time preview
        if (state.brightness != 0 ||
            state.contrast != 1.0 ||
            state.saturation != 1.0) {
          transformedImage = ColorFiltered(
            colorFilter: ColorFilterMatrix.combined(
              brightness: state.brightness,
              contrast: state.contrast,
              saturation: state.saturation,
            ),
            child: transformedImage,
          );
        }

        // Calculate the scale compensation needed for the current rotation
        // This ensures the rotated image always fills the crop area (no black corners)
        final rotationCompensationScale = minScale;

        // Apply rotation, flip, AND scale compensation together
        // The scale compensation zooms the image so black corners are never visible
        transformedImage = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..scale(
                rotationCompensationScale) // Zoom to compensate for rotation
            ..rotateZ(state.totalRotation * 3.14159 / 180)
            ..scale(
              state.flipHorizontal ? -1.0 : 1.0,
              state.flipVertical ? -1.0 : 1.0,
            ),
          child: transformedImage,
        );

        return Container(
          color: Colors.black,
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate the actual displayed image size accounting for BoxFit.contain
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    widget.controller.setDisplaySize(
                      Size(constraints.maxWidth, constraints.maxHeight),
                    );
                  }
                });

                return Stack(
                  children: [
                    // Image with InteractiveViewer for zoom/pan
                    InteractiveViewer(
                      transformationController: _transformationController,
                      minScale:
                          1.0, // Allow zooming out to 1.0 since Transform handles rotation compensation
                      maxScale: 4.0,
                      constrained: true, // Keep image fitted to viewport
                      clipBehavior: Clip.hardEdge,
                      panEnabled: true,
                      scaleEnabled: true,
                      boundaryMargin:
                          EdgeInsets.zero, // No panning outside image bounds
                      onInteractionEnd: (details) {
                        // On interaction end, ensure we're within bounds
                        _ensureWithinBounds();
                      },
                      child: ClipRect(
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Show full image in crop mode, cropped version in other modes
                            if (state.currentTab == EditorTab.crop)
                              transformedImage
                            else if (state.cropRect != null)
                              _buildCroppedImage(
                                  transformedImage, state.cropRect!)
                            else
                              transformedImage,
                          ],
                        ),
                      ),
                    ),

                    // Crop overlay (if in crop mode) - positioned above InteractiveViewer
                    if (state.currentTab == EditorTab.crop)
                      Positioned.fill(
                        child: CropOverlay(
                          cropRect: state.cropRect,
                          aspectRatioPreset: state.aspectRatioPreset,
                          onCropChanged: (rect) {
                            widget.controller.setCropRect(rect);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
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

  /// Ensure the current pan is within valid bounds (animate back if needed)
  void _ensureWithinBounds() {
    final state = widget.controller.state;
    final currentScale = state.scale;

    // Check if scale needs adjustment (minimum is 1.0 since Transform handles rotation)
    if (currentScale < 1.0) {
      _animateToPosition(1.0, Offset.zero);
      return;
    }

    // Check if pan needs adjustment
    final maxPan = state.maxPanOffset;
    final currentPan = state.panOffset;

    final clampedPan = Offset(
      currentPan.dx.clamp(-maxPan.dx, maxPan.dx),
      currentPan.dy.clamp(-maxPan.dy, maxPan.dy),
    );

    if (clampedPan != currentPan) {
      // Animate back to valid bounds
      _animateToPosition(currentScale, clampedPan);
    }
  }

  /// Animate to a specific scale and pan position
  void _animateToPosition(double scale, Offset pan) {
    final startMatrix = _transformationController.value.clone();

    _animationController.reset();

    final animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    animation.addListener(() {
      final t = animation.value;
      final currentMatrix = Matrix4.identity();

      // Interpolate between start and end matrices
      final startScale = startMatrix.getMaxScaleOnAxis();
      final endScale = scale;
      final currentScale = startScale + (endScale - startScale) * t;

      final startTranslation = startMatrix.getTranslation();
      final currentPan = Offset(
        startTranslation.x + (pan.dx - startTranslation.x) * t,
        startTranslation.y + (pan.dy - startTranslation.y) * t,
      );

      currentMatrix
        ..translate(currentPan.dx, currentPan.dy)
        ..scale(currentScale);

      _transformationController.value = currentMatrix;
    });

    _animationController.forward();
  }

  Widget _buildCroppedImage(Widget image, CropRect cropRect) {
    return FittedBox(
      fit: BoxFit.contain,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          widthFactor: cropRect.width,
          heightFactor: cropRect.height,
          child: FractionalTranslation(
            translation: Offset(-cropRect.left, -cropRect.top),
            child: image,
          ),
        ),
      ),
    );
  }
}

/// Crop overlay with draggable corners and edges
class CropOverlay extends StatefulWidget {
  final CropRect? cropRect;
  final AspectRatioPreset aspectRatioPreset;
  final Function(CropRect) onCropChanged;

  const CropOverlay({
    Key? key,
    this.cropRect,
    this.aspectRatioPreset = AspectRatioPreset.free,
    required this.onCropChanged,
  }) : super(key: key);

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  CropRect? _currentRect;
  Offset? _dragStart;
  CropRect? _dragStartRect;

  /// Get the target aspect ratio (null = free form)
  double? get _targetAspectRatio => widget.aspectRatioPreset.ratio;

  @override
  void initState() {
    super.initState();
    _initializeRect();
  }

  void _initializeRect() {
    if (widget.cropRect != null) {
      _currentRect = widget.cropRect;
    } else {
      _currentRect = const CropRect(
        left: 0.0,
        top: 0.0,
        width: 1.0,
        height: 1.0,
      );
    }
  }

  @override
  void didUpdateWidget(CropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cropRect != oldWidget.cropRect) {
      _currentRect = widget.cropRect ??
          const CropRect(
            left: 0.0,
            top: 0.0,
            width: 1.0,
            height: 1.0,
          );
    }
    // If aspect ratio changed, adjust the current rect
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
      // Current is too wide, reduce width
      newWidth = rect.height * targetAspect;
    } else {
      // Current is too tall, reduce height
      newHeight = rect.width / targetAspect;
    }

    // Center the adjusted rect within the original
    final left = rect.left + (rect.width - newWidth) / 2;
    final top = rect.top + (rect.height - newHeight) / 2;

    setState(() {
      _currentRect = CropRect(
        left: left.clamp(0.0, 1.0 - newWidth),
        top: top.clamp(0.0, 1.0 - newHeight),
        width: newWidth.clamp(0.1, 1.0),
        height: newHeight.clamp(0.1, 1.0),
      );
    });
    widget.onCropChanged(_currentRect!);
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
            // Dark overlay outside crop area
            Positioned.fill(
              child: CustomPaint(
                painter: CropOverlayPainter(
                  cropRect: Rect.fromLTWH(left, top, width, height),
                ),
              ),
            ),

            // Draggable crop area (to move the entire crop)
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: GestureDetector(
                onPanStart: (details) {
                  _dragStart = details.localPosition;
                  _dragStartRect = _currentRect;
                },
                onPanUpdate: (details) {
                  if (_dragStart == null || _dragStartRect == null) return;

                  final delta = details.localPosition - _dragStart!;
                  final dx = delta.dx / constraints.maxWidth;
                  final dy = delta.dy / constraints.maxHeight;

                  setState(() {
                    var newLeft = (_dragStartRect!.left + dx)
                        .clamp(0.0, 1.0 - _dragStartRect!.width);
                    var newTop = (_dragStartRect!.top + dy)
                        .clamp(0.0, 1.0 - _dragStartRect!.height);

                    _currentRect = CropRect(
                      left: newLeft,
                      top: newTop,
                      width: _dragStartRect!.width,
                      height: _dragStartRect!.height,
                    );
                  });
                  widget.onCropChanged(_currentRect!);
                },
                onPanEnd: (_) {
                  _dragStart = null;
                  _dragStartRect = null;
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
        onPanStart: (details) {
          _dragStartRect = _currentRect;
        },
        onPanUpdate: (details) {
          if (_dragStartRect == null) return;

          final dx = details.delta.dx / constraints.maxWidth;
          final dy = details.delta.dy / constraints.maxHeight;

          setState(() {
            var newRect = _dragStartRect!;

            // If we have a target aspect ratio, constrain the drag
            if (_targetAspectRatio != null) {
              newRect = _handleAspectRatioConstrainedDrag(
                newRect,
                dx,
                dy,
                alignment,
                constraints,
              );
            } else {
              // Free form dragging
              newRect = _handleFreeFormDrag(newRect, dx, dy, alignment);
            }

            _currentRect = newRect;
            _dragStartRect = newRect;
          });
          widget.onCropChanged(_currentRect!);
        },
        onPanEnd: (_) {
          _dragStartRect = null;
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

  /// Handle free-form dragging (no aspect ratio constraint)
  CropRect _handleFreeFormDrag(
      CropRect rect, double dx, double dy, Alignment alignment) {
    if (alignment == Alignment.topLeft) {
      return CropRect(
        left: (rect.left + dx).clamp(0.0, rect.left + rect.width - 0.1),
        top: (rect.top + dy).clamp(0.0, rect.top + rect.height - 0.1),
        width: (rect.width - dx).clamp(0.1, 1.0),
        height: (rect.height - dy).clamp(0.1, 1.0),
      );
    } else if (alignment == Alignment.topRight) {
      return CropRect(
        left: rect.left,
        top: (rect.top + dy).clamp(0.0, rect.top + rect.height - 0.1),
        width: (rect.width + dx).clamp(0.1, 1.0 - rect.left),
        height: (rect.height - dy).clamp(0.1, 1.0),
      );
    } else if (alignment == Alignment.bottomLeft) {
      return CropRect(
        left: (rect.left + dx).clamp(0.0, rect.left + rect.width - 0.1),
        top: rect.top,
        width: (rect.width - dx).clamp(0.1, 1.0),
        height: (rect.height + dy).clamp(0.1, 1.0 - rect.top),
      );
    } else {
      // bottomRight
      return CropRect(
        left: rect.left,
        top: rect.top,
        width: (rect.width + dx).clamp(0.1, 1.0 - rect.left),
        height: (rect.height + dy).clamp(0.1, 1.0 - rect.top),
      );
    }
  }

  /// Handle aspect-ratio-constrained dragging
  CropRect _handleAspectRatioConstrainedDrag(
    CropRect rect,
    double dx,
    double dy,
    Alignment alignment,
    BoxConstraints constraints,
  ) {
    final aspectRatio = _targetAspectRatio!;

    // Use the larger absolute delta to determine scale change
    final absDx = dx.abs();
    final absDy = dy.abs();

    double scale;
    if (absDx > absDy) {
      // Width change drives the resize
      scale = dx *
          (alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
              ? -1
              : 1);
    } else {
      // Height change drives the resize (convert to equivalent width change)
      scale = dy *
          aspectRatio *
          (alignment == Alignment.topLeft || alignment == Alignment.topRight
              ? -1
              : 1);
    }

    // Calculate new dimensions maintaining aspect ratio
    double newWidth = (rect.width + scale).clamp(0.1, 1.0);
    double newHeight = newWidth / aspectRatio;

    // Ensure height is also within bounds
    if (newHeight > 1.0) {
      newHeight = 1.0;
      newWidth = newHeight * aspectRatio;
    }
    if (newHeight < 0.1) {
      newHeight = 0.1;
      newWidth = newHeight * aspectRatio;
    }

    // Calculate new position based on anchor corner
    double newLeft = rect.left;
    double newTop = rect.top;

    if (alignment == Alignment.topLeft) {
      // Anchor is bottom-right
      newLeft = rect.left + rect.width - newWidth;
      newTop = rect.top + rect.height - newHeight;
    } else if (alignment == Alignment.topRight) {
      // Anchor is bottom-left
      newTop = rect.top + rect.height - newHeight;
    } else if (alignment == Alignment.bottomLeft) {
      // Anchor is top-right
      newLeft = rect.left + rect.width - newWidth;
    }
    // bottomRight: anchor is top-left, no position change needed

    // Clamp to bounds
    newLeft = newLeft.clamp(0.0, 1.0 - newWidth);
    newTop = newTop.clamp(0.0, 1.0 - newHeight);

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
        onPanStart: (details) {
          _dragStartRect = _currentRect;
        },
        onPanUpdate: (details) {
          if (_dragStartRect == null) return;

          final dx = details.delta.dx / constraints.maxWidth;
          final dy = details.delta.dy / constraints.maxHeight;

          setState(() {
            var newRect = _dragStartRect!;

            if (edge == 'top') {
              newRect = CropRect(
                left: newRect.left,
                top: (newRect.top + dy)
                    .clamp(0.0, newRect.top + newRect.height - 0.1),
                width: newRect.width,
                height: (newRect.height - dy).clamp(0.1, 1.0),
              );
            } else if (edge == 'bottom') {
              newRect = CropRect(
                left: newRect.left,
                top: newRect.top,
                width: newRect.width,
                height: (newRect.height + dy).clamp(0.1, 1.0 - newRect.top),
              );
            } else if (edge == 'left') {
              newRect = CropRect(
                left: (newRect.left + dx)
                    .clamp(0.0, newRect.left + newRect.width - 0.1),
                top: newRect.top,
                width: (newRect.width - dx).clamp(0.1, 1.0),
                height: newRect.height,
              );
            } else if (edge == 'right') {
              newRect = CropRect(
                left: newRect.left,
                top: newRect.top,
                width: (newRect.width + dx).clamp(0.1, 1.0 - newRect.left),
                height: newRect.height,
              );
            }

            _currentRect = newRect;
            _dragStartRect = newRect;
          });
          widget.onCropChanged(_currentRect!);
        },
        onPanEnd: (_) {
          _dragStartRect = null;
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

  CropOverlayPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Draw dark overlay around crop area
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw white border around crop area
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(cropRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
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
