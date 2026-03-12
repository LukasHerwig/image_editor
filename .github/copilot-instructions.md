# Project Guidelines

## Code Style

- Follow the Flutter lint baseline in `analysis_options.yaml` and preserve the existing style in `lib/` and `test/`.
- Keep `ImageEditorState` immutable and value-based. State changes should flow through `copyWith()` in the controller rather than mutating fields in widgets.
- Prefer the existing `ChangeNotifier` + `ListenableBuilder` pattern over adding a new state-management layer for package work.
- Keep the public API deliberate. Only update exports in `lib/image_editor.dart` and `lib/z_image_editor.dart` when the task intentionally changes package surface area.

## Architecture

- Read `ARCHITECTURE.md` before changing crop, pan/zoom, rotation, or export behavior. The transform pipeline and invariants are documented there and are part of the implementation contract.
- Keep responsibilities split by layer:
  - `lib/src/controller/image_editor_controller.dart` owns mutations, animation coordination, and editor invariants.
  - `lib/src/utils/transformation_service.dart` owns coordinate conversion, clamping, and rotation-aware scale math.
  - `lib/src/utils/image_processing.dart` owns export rendering.
  - `lib/src/widgets/` owns UI composition and gesture handling.
- Do not duplicate transform or coordinate-space math in widgets when it belongs in `TransformationService`.
- Preserve WYSIWYG export behavior: on-screen transforms and exported output must stay aligned.

## Build and Test

- Run these repo-level checks for package changes:
  - `flutter pub get`
  - `dart format --output=none --set-exit-if-changed .`
  - `flutter analyze`
  - `flutter test`
- When changing the example app, also run in `example/`:
  - `flutter pub get`
  - `flutter analyze`
- Run `flutter pub publish --dry-run` when changing package metadata, assets, or public API.

## Conventions

- This package currently targets non-web Flutter platforms and depends on `dart:io`. Do not introduce web assumptions unless the task explicitly adds web support.
- Crop behavior is constraint-driven: clamp image movement and transforms to keep the crop window covered instead of silently changing the user’s crop selection.
- Treat `build/`, `example/build/`, `example/ios/Pods/`, and Flutter-generated platform artifacts as generated output. Do not edit them unless the task is explicitly about native/project generation.
- The example app demonstrates integration, but package implementation changes belong under `lib/`.
- Use Conventional Commits in commit or PR titles when asked to prepare releaseable changes: `fix:` for patch, `feat:` for minor pre-1.0, and `BREAKING CHANGE:` for breaking releases.
