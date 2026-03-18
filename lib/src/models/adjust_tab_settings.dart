/// Controls which ruler badges are visible inside the Adjust tab.
///
/// Pass an instance to [ZImageEditor.adjustTabSettings] to customise which
/// image-adjustment parameters the user can access.  All options default to
/// `true` (shown).
///
/// Example — show only brightness and contrast, hide saturation:
/// ```dart
/// ZImageEditor(
///   imageFile: file,
///   onSave: (f) { ... },
///   onCancel: () { ... },
///   adjustTabSettings: AdjustTabSettings(showSaturation: false),
/// )
/// ```
class AdjustTabSettings {
  /// Whether the brightness badge is shown. Defaults to `true`.
  final bool showBrightness;

  /// Whether the contrast badge is shown. Defaults to `true`.
  final bool showContrast;

  /// Whether the saturation badge is shown. Defaults to `true`.
  final bool showSaturation;

  const AdjustTabSettings({
    this.showBrightness = true,
    this.showContrast = true,
    this.showSaturation = true,
  });
}
