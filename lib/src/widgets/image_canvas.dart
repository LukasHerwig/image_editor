import 'dart:io';
import 'dart:typed_data';
import 'package:monogram_image_editor/src/controller/image_editor_controller.dart';
import 'package:monogram_image_editor/src/models/image_editor_state.dart';
import 'package:monogram_image_editor/src/utils/image_processing.dart';
import 'package:flutter/material.dart';

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

class _ImageCanvasState extends State<ImageCanvas> {
  final TransformationController _transformationController =
      TransformationController();
  double _lastAutoScale = 1.0;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _updateTransformationForRotation(double autoScale) {
    // When rotation changes, we need to adjust the InteractiveViewer's scale
    // to compensate for the auto-scale applied to the image
    if (_lastAutoScale != autoScale) {
      final currentMatrix = _transformationController.value;
      final currentScale = currentMatrix.getMaxScaleOnAxis();

      // Calculate the new scale that maintains the effective zoom level
      // We want to scale up by 1/autoScale to compensate for the image shrinking
      final compensationScale = 1.0 / autoScale;
      final newScale =
          currentScale * (compensationScale / (1.0 / _lastAutoScale));

      // Apply the new transformation
      _transformationController.value = Matrix4.identity()
        ..scale(newScale, newScale);

      _lastAutoScale = autoScale;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final state = widget.controller.state;

        Widget imageWidget;

        if (widget.imageFile != null) {
          imageWidget = Image.file(
            widget.imageFile!,
            fit: BoxFit.contain,
          );
        } else if (widget.imageBytes != null) {
          imageWidget = Image.memory(
            widget.imageBytes!,
            fit: BoxFit.contain,
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

        // Apply rotation and flips
        // Auto-scale is applied to prevent black background from showing during rotation
        final autoScale = state.autoScaleForRotation;

        // Update InteractiveViewer transformation to compensate for rotation scale
        _updateTransformationForRotation(autoScale);

        transformedImage = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ((state.rotation + state.fineRotation) * 3.14159 / 180)
            ..scale(
              state.flipHorizontal ? -autoScale : autoScale,
              autoScale,
            ),
          child: transformedImage,
        );

        return Container(
          color: Colors.black,
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Update the display size based on the available viewport
                // This is called on every build, ensuring we have the current size
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    // The constraints give us the viewport size
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
                      minScale: 1.0 / autoScale,
                      maxScale: 4.0,
                      boundaryMargin: EdgeInsets.zero,
                      clipBehavior: Clip.hardEdge,
                      panEnabled: true,
                      scaleEnabled: true,
                      onInteractionUpdate: (details) {
                        // Extract scale and translation from transformation matrix in real-time
                        final matrix = _transformationController.value;
                        final scale = matrix.getMaxScaleOnAxis();
                        final translation = matrix.getTranslation();

                        widget.controller.setScale(scale);
                        widget.controller
                            .setPanOffset(Offset(translation.x, translation.y));
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
                    // This stays fixed and doesn't zoom/pan with the image
                    if (state.currentTab == EditorTab.crop)
                      Positioned.fill(
                        child: CropOverlay(
                          cropRect: state.cropRect,
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
  final Function(CropRect) onCropChanged;

  const CropOverlay({
    Key? key,
    this.cropRect,
    required this.onCropChanged,
  }) : super(key: key);

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  CropRect? _currentRect;
  CropRect? _dragStartRect;

  @override
  void initState() {
    super.initState();
    _currentRect = widget.cropRect ??
        const CropRect(
          left: 0.0,
          top: 0.0,
          width: 1.0,
          height: 1.0,
        );
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
            // Dark overlay outside crop area - this is visual only, no touch blocking
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CropOverlayPainter(
                    cropRect: Rect.fromLTWH(left, top, width, height),
                  ),
                ),
              ),
            ),

            // Draggable crop area - DISABLED to allow zoom gestures
            // Users can still move crop by dragging the handles
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: IgnorePointer(
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

            if (alignment == Alignment.topLeft) {
              newRect = CropRect(
                left: (newRect.left + dx)
                    .clamp(0.0, newRect.left + newRect.width - 0.1),
                top: (newRect.top + dy)
                    .clamp(0.0, newRect.top + newRect.height - 0.1),
                width: (newRect.width - dx).clamp(0.1, 1.0),
                height: (newRect.height - dy).clamp(0.1, 1.0),
              );
            } else if (alignment == Alignment.topRight) {
              newRect = CropRect(
                left: newRect.left,
                top: (newRect.top + dy)
                    .clamp(0.0, newRect.top + newRect.height - 0.1),
                width: (newRect.width + dx).clamp(0.1, 1.0 - newRect.left),
                height: (newRect.height - dy).clamp(0.1, 1.0),
              );
            } else if (alignment == Alignment.bottomLeft) {
              newRect = CropRect(
                left: (newRect.left + dx)
                    .clamp(0.0, newRect.left + newRect.width - 0.1),
                top: newRect.top,
                width: (newRect.width - dx).clamp(0.1, 1.0),
                height: (newRect.height + dy).clamp(0.1, 1.0 - newRect.top),
              );
            } else if (alignment == Alignment.bottomRight) {
              newRect = CropRect(
                left: newRect.left,
                top: newRect.top,
                width: (newRect.width + dx).clamp(0.1, 1.0 - newRect.left),
                height: (newRect.height + dy).clamp(0.1, 1.0 - newRect.top),
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
