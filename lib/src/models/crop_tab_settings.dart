/// Controls which ruler badges are visible inside the Crop tab.
///
/// Pass an instance to [ZImageEditor.cropTabSettings] to customise which
/// angle-adjustment controls the user can access. All options default to
/// `true` (shown).
///
/// Example — show only the tilt controls, hide straighten:
/// ```dart
/// ZImageEditor(
///   imageFile: file,
///   onSave: (f) { ... },
///   onCancel: () { ... },
///   cropTabSettings: CropTabSettings(showStraighten: false),
/// )
/// ```
class CropTabSettings {
  /// Whether the straighten (fine-rotation) badge is shown. Defaults to `true`.
  final bool showStraighten;

  /// Whether the vertical-tilt badge is shown. Defaults to `true`.
  final bool showTiltVertical;

  /// Whether the horizontal-tilt badge is shown. Defaults to `true`.
  final bool showTiltHorizontal;

  const CropTabSettings({
    this.showStraighten = true,
    this.showTiltVertical = true,
    this.showTiltHorizontal = true,
  });
}
