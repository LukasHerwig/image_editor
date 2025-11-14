import 'dart:io';
import 'dart:typed_data';
import 'package:monogram_image_editor/src/controller/image_editor_controller.dart';
import 'package:monogram_image_editor/src/models/image_editor_state.dart';
import 'package:monogram_image_editor/src/utils/image_processing.dart';
import 'package:flutter/material.dart';

/// Interactive image canvas that displays the image with all transformations
class ImageCanvas extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final state = controller.state;

        Widget imageWidget;

        if (imageFile != null) {
          imageWidget = Image.file(
            imageFile!,
            fit: BoxFit.contain,
          );
        } else if (imageBytes != null) {
          imageWidget = Image.memory(
            imageBytes!,
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
        transformedImage = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ((state.rotation + state.fineRotation) * 3.14159 / 180)
            ..scale(
              state.flipHorizontal ? -1.0 : 1.0,
              state.flipVertical ? -1.0 : 1.0,
            ),
          child: transformedImage,
        );

        return Container(
          color: Colors.black,
          child: Center(
            child: ClipRect(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Show full image in crop mode, cropped version in other modes
                  if (state.currentTab == EditorTab.crop)
                    transformedImage
                  else if (state.cropRect != null)
                    _buildCroppedImage(transformedImage, state.cropRect!)
                  else
                    transformedImage,

                  // Crop overlay (if in crop mode)
                  if (state.currentTab == EditorTab.crop)
                    Positioned.fill(
                      child: CropOverlay(
                        cropRect: state.cropRect,
                        onCropChanged: (rect) {
                          controller.setCropRect(rect);
                        },
                      ),
                    ),
                ],
              ),
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
  Offset? _dragStart;
  CropRect? _dragStartRect;

  @override
  void initState() {
    super.initState();
    _currentRect = widget.cropRect ??
        const CropRect(
          left: 0.1,
          top: 0.1,
          width: 0.8,
          height: 0.8,
        );
  }

  @override
  void didUpdateWidget(CropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cropRect != oldWidget.cropRect) {
      _currentRect = widget.cropRect ??
          const CropRect(
            left: 0.1,
            top: 0.1,
            width: 0.8,
            height: 0.8,
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
