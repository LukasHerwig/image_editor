# Z Image Editor

`z_image_editor` is a Flutter package for in-app image editing with a polished, iOS-inspired editing surface. It provides crop, rotate, flip, brightness, contrast, and saturation controls with real-time preview.

## Features

- Crop with preset aspect ratios and freeform handles
- Rotate in 90-degree steps plus fine rotation control
- Flip horizontally and vertically
- Adjust brightness, contrast, and saturation
- Perspective tilt (vertical and horizontal)
- Optional magnifying glass on crop handle drag
- Save edited output as a file
- Fully configurable UI — hide tabs, toolbar buttons, and ruler badges
- Ship a runnable demo in [`example/`](./example)

## Installation

This repository is not publishing to pub.dev yet. Until that happens, depend on it directly from Git:

```yaml
dependencies:
  z_image_editor:
    git:
      url: https://github.com/Zero8-AB/z_image_editor.git
```

After the package is published, you can switch to:

```bash
flutter pub add z_image_editor
```

## Usage

The package focuses on editing. You bring your own image source, such as `image_picker`, a downloaded file, or raw bytes.

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:z_image_editor/z_image_editor.dart';

class EditImageButton extends StatelessWidget {
  const EditImageButton({
    super.key,
    required this.imageFile,
  });

  final File imageFile;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () async {
        final editedImage = await Navigator.of(context).push<File>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => ZImageEditor(
              imageFile: imageFile,
              onSave: (edited) => Navigator.of(context).pop(edited),
              onCancel: () => Navigator.of(context).pop(),
            ),
          ),
        );

        if (editedImage != null) {
          // Persist or display the edited file.
        }
      },
      child: const Text('Edit image'),
    );
  }
}
```

For a complete integration example, see [`example/lib/main.dart`](./example/lib/main.dart).

## Configuration

All parameters are optional and have sensible defaults, so a minimal integration only requires `imageFile`/`imageBytes`, `onSave`, and `onCancel`.

### Button labels

Localise or customise the three header buttons:

```dart
ZImageEditor(
  imageFile: imageFile,
  onSave: ...,
  onCancel: ...,
  cancelLabel: 'Avbryt',
  resetLabel: 'Återställ',
  doneLabel: 'Klar',
)
```

### Magnifying glass

Show a magnifying glass above the finger while dragging crop handles for precise positioning (off by default):

```dart
ZImageEditor(
  imageFile: imageFile,
  onSave: ...,
  onCancel: ...,
  enableMagnifyingGlass: true,
)
```

### Crop toolbar

The crop toolbar (rotate, flip, aspect ratio) is shown by default. Hide it entirely or disable individual buttons:

```dart
ZImageEditor(
  imageFile: imageFile,
  onSave: ...,
  onCancel: ...,
  // Hide the whole toolbar:
  showCropToolbar: false,

  // — or keep the toolbar but hide specific buttons:
  cropToolbarSettings: CropToolbarSettings(
    showRotate: true,
    showFlipHorizontal: true,
    showFlipVertical: true,
    showAspectRatio: false,
  ),
)
```

### Tabs

Show or hide the Crop and Adjust tabs, and control which ruler badges appear inside each one:

```dart
ZImageEditor(
  imageFile: imageFile,
  onSave: ...,
  onCancel: ...,
  // Hide a tab entirely:
  showAdjustTab: false,

  // Keep the Crop tab but hide the straighten badge:
  cropTabSettings: CropTabSettings(
    showStraighten: true,
    showTiltVertical: true,
    showTiltHorizontal: true,
  ),

  // Keep the Adjust tab but hide saturation:
  adjustTabSettings: AdjustTabSettings(
    showBrightness: true,
    showContrast: true,
    showSaturation: false,
  ),
)
```

When only one tab is enabled the tab bar is hidden automatically.

## Platform Support

The package currently targets non-web Flutter platforms that support `dart:io`. Web is not supported in this release line.

## Local Quality Checks

Run the same checks used in CI before opening a pull request:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter pub publish --dry-run
(cd example && flutter pub get && flutter analyze)
```

## Releases and Versioning

This repository uses `release-please` for changelog and version automation.

- `fix:` creates a patch release
- `feat:` creates a minor release while the package is still in `0.x`
- `BREAKING CHANGE:` marks a breaking release

Use Conventional Commits for merge commits and squash commit messages so release automation can generate accurate release PRs.
