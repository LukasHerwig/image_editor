import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:monogram_image_editor/src/controller/image_editor_controller.dart';
import 'package:monogram_image_editor/src/models/image_editor_state.dart';
import 'package:monogram_image_editor/src/widgets/adjustment_controls.dart';
import 'package:monogram_image_editor/src/widgets/crop_controls.dart';
import 'package:monogram_image_editor/src/widgets/image_canvas.dart';
import 'package:monogram_image_editor/src/utils/image_processing.dart';
import 'package:flutter/material.dart';
import 'package:monogram_image_editor/src/widgets/liquid_glass.dart';
import 'package:monogram_image_editor/src/widgets/rotate_tools_top.dart';

/// iOS-style image editor widget
class MonogramImageEditor extends StatefulWidget {
  final File? imageFile;
  final Uint8List? imageBytes;
  final Function(File editedImage) onSave;
  final VoidCallback onCancel;

  const MonogramImageEditor({
    Key? key,
    this.imageFile,
    this.imageBytes,
    required this.onSave,
    required this.onCancel,
  })  : assert(imageFile != null || imageBytes != null,
            'Either imageFile or imageBytes must be provided'),
        super(key: key);

  @override
  State<MonogramImageEditor> createState() => _MonogramImageEditorState();
}

class _MonogramImageEditorState extends State<MonogramImageEditor> {
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

      // Process the image with all edits
      final File? originalFile = widget.imageFile;

      if (originalFile != null) {
        final processedFile = await ImageProcessing.processImage(
          originalFile: originalFile,
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
            // crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(context),

              if (state.currentTab == EditorTab.crop) ...[
                RotateTools(controller: _controller, state: state),
              ] else if (state.currentTab == EditorTab.adjust) ...[
                // Placeholder for potential adjustment tools header
              ],

              // Image canvas - takes most of the screen
              Expanded(
                flex: 3,
                child: ImageCanvas(
                  imageFile: widget.imageFile,
                  imageBytes: widget.imageBytes,
                  controller: _controller,
                ),
              ),

              // Bottom controls - compact
              Container(
                color: const Color(0xFF1C1C1E),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tool-specific controls - limited height
                    _buildToolControls(state),

                    // Tab selector at bottom
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

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: const Color(0xFF1C1C1E),
      child: SafeArea(
        bottom: false,
        child: Container(
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
              const Text(
                'Edit',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _buildTabSelector(ImageEditorState state) {
    return GlassContainer(
      blur: 0,
      margin: const EdgeInsets.only(left: 62, right: 62, bottom: 26),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      height: 70,
      width: 300,
      borderRadius: 42,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const SizedBox(width: 8),
          _buildTab(
            icon: CupertinoIcons.crop_rotate,
            label: 'Crop',
            isSelected: state.currentTab == EditorTab.crop,
            onTap: () => _controller.setTab(EditorTab.crop),
          ),
          const SizedBox(width: 60),
          _buildTab(
            icon: CupertinoIcons.slider_horizontal_3,
            label: 'Adjust',
            isSelected: state.currentTab == EditorTab.adjust,
            onTap: () => _controller.setTab(EditorTab.adjust),
          ),
          const SizedBox(width: 8),
        ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isSelected ? CupertinoColors.systemBlue : Colors.white70,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? CupertinoColors.systemBlue : Colors.white70,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolControls(ImageEditorState state) {
    switch (state.currentTab) {
      case EditorTab.crop:
        return CropControls(controller: _controller);
      case EditorTab.adjust:
        return AdjustmentControls(controller: _controller);
    }
  }
}
