import 'package:flutter_test/flutter_test.dart';
import 'package:z_image_editor/src/models/image_editor_state.dart';

void main() {
  test('ImageEditorState initial values', () {
    const state = ImageEditorState();

    expect(state.brightness, 0.0);
    expect(state.contrast, 1.0);
    expect(state.saturation, 1.0);
    expect(state.rotation, 0.0);
    expect(state.flipHorizontal, false);
    expect(state.flipVertical, false);
    expect(state.hasChanges, false);
  });

  test('ImageEditorState hasChanges detection', () {
    const stateWithBrightness = ImageEditorState(brightness: 50);
    expect(stateWithBrightness.hasChanges, true);

    const stateWithContrast = ImageEditorState(contrast: 1.5);
    expect(stateWithContrast.hasChanges, true);

    const stateWithFlip = ImageEditorState(flipHorizontal: true);
    expect(stateWithFlip.hasChanges, true);
  });

  test('ImageEditorState copyWith', () {
    const state = ImageEditorState();
    final updated = state.copyWith(brightness: 25, saturation: 1.5);

    expect(updated.brightness, 25);
    expect(updated.saturation, 1.5);
    expect(updated.contrast, 1.0); // unchanged
  });
}
