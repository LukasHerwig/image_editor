# Monogram Image Editor

A beautiful iOS-style image editor for Flutter with crop, rotate, and color adjustment features.

## Features

- 🎨 **iOS-Native Design** - Authentic iOS aesthetics with dark theme
- ✂️ **Crop** - Multiple aspect ratio presets (Free, Square, 4:3, 16:9) with visual grid overlay
- 🔄 **Rotate** - 90° rotation, horizontal/vertical flip, and fine-tune rotation slider
- 🌈 **Color Adjustments** - Brightness, contrast, and saturation controls with real-time preview
- 📱 **Platform Aware** - Optimized for iOS with CupertinoActionSheet integration
- ⚡ **Real-time Preview** - See changes instantly as you adjust

## Screenshots

[Add screenshots here]

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  monogram_image_editor: ^0.1.0
```

Or reference it locally:

```yaml
dependencies:
  monogram_image_editor:
    path: ../monogram_image_editor
```

Then run:

```bash
flutter pub get
```

## Usage

### Basic Usage

```dart
import 'package:monogram_image_editor/monogram_image_editor.dart';
import 'dart:io';

// Show the image editor
final editedImage = await Navigator.of(context).push<File>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (context) => MonogramImageEditor(
      imageFile: File('path/to/image.jpg'),
      onSave: (File editedFile) {
        Navigator.of(context).pop(editedFile);
      },
      onCancel: () {
        Navigator.of(context).pop();
      },
    ),
  ),
);

if (editedImage != null) {
  // Use the edited image
  print('Image edited: ${editedImage.path}');
}
```

### With Image Picker Integration

```dart
import 'package:image_picker/image_picker.dart';
import 'package:monogram_image_editor/monogram_image_editor.dart';

final picker = ImagePicker();

// Take a photo
final photo = await picker.pickImage(source: ImageSource.camera);

if (photo != null) {
  // Show editor
  final editedImage = await Navigator.of(context).push<File>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => MonogramImageEditor(
        imageFile: File(photo.path),
        onSave: (File edited) {
          Navigator.of(context).pop(edited);
        },
        onCancel: () {
          Navigator.of(context).pop();
        },
      ),
    ),
  );

  if (editedImage != null) {
    // Use edited image
  }
}
```

### With iOS Action Sheet

```dart
import 'package:flutter/cupertino.dart';
import 'package:monogram_image_editor/monogram_image_editor.dart';

Future<void> showImageSourcePicker(BuildContext context) async {
  final result = await showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: const Text('Add Image'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext, 'camera'),
          child: const Text('Take Photo'),
        ),
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext, 'gallery'),
          child: const Text('Choose from Gallery'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(sheetContext),
        child: const Text('Cancel'),
      ),
    ),
  );

  if (result == 'camera' && context.mounted) {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo != null && context.mounted) {
      final edited = await Navigator.of(context).push<File>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => MonogramImageEditor(
            imageFile: File(photo.path),
            onSave: (file) => Navigator.pop(context, file),
            onCancel: () => Navigator.pop(context),
          ),
        ),
      );
      // Use edited image
    }
  }
}
```

## API Reference

### MonogramImageEditor

Main widget for the image editor.

#### Properties

- `imageFile` (File?) - The image file to edit
- `imageBytes` (Uint8List?) - Alternative: image as bytes
- `onSave` (Function(File)) - Callback when user saves the edited image
- `onCancel` (VoidCallback) - Callback when user cancels editing

### Editing Features

#### Crop Tab

- **Aspect Ratios**: Free, Square (1:1), 4:3, 16:9
- **Visual Grid**: Rule of thirds overlay
- **Reset**: Quick reset to original crop

#### Adjust Tab

- **Brightness**: -100 to +100
- **Contrast**: 0.5 to 2.0
- **Saturation**: 0.0 to 2.0
- **Real-time Preview**: See changes instantly

#### Rotate Tab

- **90° Rotation**: Quick rotate button
- **Flip Horizontal**: Mirror image horizontally
- **Flip Vertical**: Mirror image vertically
- **Fine Rotation**: -45° to +45° with slider

## Architecture

The package uses Riverpod for state management and follows a clean architecture:

```
lib/
├── monogram_image_editor.dart          # Main widget export
├── src/
│   ├── models/
│   │   └── image_editor_state.dart     # State model
│   ├── controller/
│   │   └── image_editor_controller.dart # Riverpod controller
│   ├── widgets/
│   │   ├── image_canvas.dart           # Image display with transformations
│   │   ├── adjustment_controls.dart    # Color adjustment sliders
│   │   ├── crop_controls.dart          # Crop aspect ratio controls
│   │   └── rotation_controls.dart      # Rotation and flip controls
│   └── utils/
│       └── image_processing.dart       # Image processing utilities
```

## Requirements

- Flutter SDK: >=3.1.3
- Dart SDK: >=3.1.3
- iOS 12.0+ (for iOS platform)
- Android 21+ (for Android platform)

## Dependencies

- `flutter_riverpod` - State management
- `riverpod_annotation` - Code generation for Riverpod
- `image` - Image processing and manipulation

## Development

### Running the example

```bash
cd example
flutter run
```

### Running tests

```bash
flutter test
```

### Code generation

After making changes to Riverpod providers:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Credits

Developed by [Monogram Art](https://github.com/Monogram-Art)

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
