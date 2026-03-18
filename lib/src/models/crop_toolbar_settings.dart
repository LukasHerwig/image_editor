/// Controls which buttons are visible inside the crop toolbar.
///
/// Pass an instance to [ZImageEditor.cropToolbarSettings] to customise the
/// toolbar. All options default to `true` (shown).
///
/// Example — hide the aspect-ratio picker:
/// ```dart
/// ZImageEditor(
///   imageFile: file,
///   onSave: (f) { ... },
///   onCancel: () { ... },
///   cropToolbarSettings: CropToolbarSettings(showAspectRatio: false),
/// )
/// ```
class CropToolbarSettings {
  /// Whether the rotate-90° button is shown. Defaults to `true`.
  final bool showRotate;

  /// Whether the flip-horizontal button is shown. Defaults to `true`.
  final bool showFlipHorizontal;

  /// Whether the flip-vertical button is shown. Defaults to `true`.
  final bool showFlipVertical;

  /// Whether the aspect-ratio picker is shown. Defaults to `true`.
  final bool showAspectRatio;

  const CropToolbarSettings({
    this.showRotate = true,
    this.showFlipHorizontal = true,
    this.showFlipVertical = true,
    this.showAspectRatio = true,
  });
}
