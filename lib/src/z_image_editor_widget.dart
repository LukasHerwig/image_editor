import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:z_image_editor/src/controller/image_editor_controller.dart';
import 'package:z_image_editor/src/models/image_editor_state.dart';
import 'package:z_image_editor/src/utils/image_processing.dart';
import 'package:z_image_editor/src/widgets/adjustment_controls.dart';
import 'package:z_image_editor/src/widgets/crop_controls.dart';
import 'package:z_image_editor/src/widgets/image_canvas.dart';

/// iOS-style image editor widget
class ZImageEditor extends StatefulWidget {
  final File? imageFile;
  final Uint8List? imageBytes;
  final Function(File editedImage) onSave;
  final VoidCallback onCancel;

  const ZImageEditor({
    super.key,
    this.imageFile,
    this.imageBytes,
    required this.onSave,
    required this.onCancel,
  }) : assert(imageFile != null || imageBytes != null,
            'Either imageFile or imageBytes must be provided');

  @override
  State<ZImageEditor> createState() => _ZImageEditorState();
}

class _ZImageEditorState extends State<ZImageEditor> {
  bool _isSaving = false;
  late ImageEditorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ImageEditorController();
    _controller.initialize(
      imageFile: widget.imageFile,
      imageBytes: widget.imageBytes,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final state = _controller.state;

      // If no changes were made, return original file
      if (!state.hasChanges && widget.imageFile != null) {
        widget.onSave(widget.imageFile!);
        return;
      }

      // Process the image with all edits (WYSIWYG when displaySize is available)
      final File? originalFile = widget.imageFile;
      final imageBytes = widget.imageBytes;

      if (originalFile != null) {
        final processedFile = await ImageProcessing.processImage(
          originalFile: originalFile,
          state: state,
        );
        widget.onSave(processedFile);
      } else if (imageBytes != null) {
        final processedFile = await ImageProcessing.processImageFromBytes(
          bytes: imageBytes,
          state: state,
        );
        widget.onSave(processedFile);
      }
    } catch (e) {
      // Show error dialog
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to process image'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        final state = _controller.state;

        return Material(
          color: Colors.black,
          child: Column(
            children: [
              // Header
              _buildHeader(context, state),

              // Image canvas
              Expanded(
                child: ImageCanvas(
                  imageFile: widget.imageFile,
                  imageBytes: widget.imageBytes,
                  controller: _controller,
                ),
              ),

              // Bottom controls
              Container(
                color: const Color(0xFF1C1C1E),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tool-specific controls
                    Flexible(
                      child: SingleChildScrollView(
                        child: _buildToolControls(state),
                      ),
                    ),
                    _buildTabSelector(state),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ImageEditorState state) {
    return Container(
      color: const Color(0xFF1C1C1E),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: _isSaving ? null : widget.onCancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: CupertinoColors.systemBlue,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: _isSaving ? null : () => _controller.reset(),
                    child: const Text(
                      'Reset',
                      style: TextStyle(
                        color: CupertinoColors.systemBlue,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: _isSaving ? null : _handleSave,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CupertinoActivityIndicator(),
                          )
                        : const Text(
                            'Done',
                            style: TextStyle(
                              color: CupertinoColors.systemBlue,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            if (state.currentTab == EditorTab.crop) _buildCropToolbar(state),
          ],
        ),
      ),
    );
  }

  // Compact single-row crop toolbar: rotate/flip icons on the left,
  // aspect ratio picker icon on the right.
  Widget _buildCropToolbar(ImageEditorState state) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // — rotate 90°
            _buildToolIcon(
              icon: CupertinoIcons.rotate_left,
              onTap: _controller.rotate90,
            ),
            const SizedBox(width: 4),
            // — flip horizontal
            _buildToolIcon(
              icon: CupertinoIcons.arrow_left_right,
              isActive: state.flipHorizontal,
              onTap: _controller.flipHorizontal,
            ),
            const SizedBox(width: 4),
            // — flip vertical
            _buildToolIcon(
              icon: CupertinoIcons.arrow_up_down,
              isActive: state.flipVertical,
              onTap: _controller.flipVertical,
            ),
            const Spacer(),
            // — aspect ratio picker
            GestureDetector(
              onTap: () => _showAspectRatioPicker(state),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: state.aspectRatioPreset != AspectRatioPreset.free
                      ? CupertinoColors.systemBlue.withValues(alpha: 0.2)
                      : const Color(0xFF3A3A3C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: state.aspectRatioPreset != AspectRatioPreset.free
                        ? CupertinoColors.systemBlue
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.crop,
                      size: 16,
                      color: state.aspectRatioPreset != AspectRatioPreset.free
                          ? CupertinoColors.systemBlue
                          : Colors.white70,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      state.aspectRatioPreset.label,
                      style: TextStyle(
                        color: state.aspectRatioPreset != AspectRatioPreset.free
                            ? CupertinoColors.systemBlue
                            : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      CupertinoIcons.chevron_down,
                      size: 11,
                      color: state.aspectRatioPreset != AspectRatioPreset.free
                          ? CupertinoColors.systemBlue
                          : Colors.white38,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolIcon({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color:
              isActive ? CupertinoColors.systemBlue : const Color(0xFF3A3A3C),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  void _showAspectRatioPicker(ImageEditorState state) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: AspectRatioPreset.values.map((preset) {
          final isSelected = state.aspectRatioPreset == preset;
          return CupertinoActionSheetAction(
            onPressed: () {
              _controller.setAspectRatioPreset(preset);
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  preset.label,
                  style: TextStyle(
                    color: isSelected
                        ? CupertinoColors.systemBlue
                        : CupertinoColors.label,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    CupertinoIcons.checkmark,
                    size: 16,
                    color: CupertinoColors.systemBlue,
                  ),
                ],
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _buildTabSelector(ImageEditorState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
      child: Center(
        child: IntrinsicWidth(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 30,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTab(
                    icon: CupertinoIcons.crop,
                    label: 'Crop',
                    isSelected: state.currentTab == EditorTab.crop,
                    onTap: () => _controller.setTab(EditorTab.crop),
                  ),
                  _buildTab(
                    icon: CupertinoIcons.slider_horizontal_3,
                    label: 'Adjust',
                    isSelected: state.currentTab == EditorTab.adjust,
                    onTap: () => _controller.setTab(EditorTab.adjust),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? CupertinoColors.systemBlue : Colors.white70,
              size: 20,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? CupertinoColors.systemBlue : Colors.white70,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolControls(ImageEditorState state) {
    switch (state.currentTab) {
      case EditorTab.crop:
        return CropControls(controller: _controller);
      case EditorTab.adjust:
        return AdjustmentControls(controller: _controller);
      case EditorTab.rotate:
        return const SizedBox.shrink();
    }
  }
}
