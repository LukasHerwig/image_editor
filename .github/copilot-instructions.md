# Monogram Image Editor — Copilot Instructions

## What this project is

`monogram_image_editor` is a Flutter widget package that provides an iOS Photos-style image editor. The public API is a single widget, `MonogramImageEditor`, which accepts a `File` or `Uint8List` and calls back with a processed `File` via `onSave`.

The editor has three tabs:

- **Crop** — free-form or aspect-ratio-locked crop box with handle drag, interior pan, and pinch-zoom.
- **Adjust** — brightness, contrast, and saturation sliders with live preview.
- **Rotate** — 90° discrete rotation, horizontal/vertical flip, fine rotation slider (±45°).

Full technical details live in [ARCHITECTURE.md](../ARCHITECTURE.md).

---

## Project structure

```
lib/src/
├── models/image_editor_state.dart          — immutable state value object
├── controller/image_editor_controller.dart — ChangeNotifier; owns all state mutations
├── utils/transformation_service.dart       — all coordinate math (raycasting, clamps)
├── utils/image_processing.dart             — WYSIWYG export renderer
└── widgets/
    ├── monogram_image_editor_widget.dart   — root scaffold + tab bar
    ├── image_canvas.dart                   — interactive canvas + CropOverlay
    ├── crop_controls.dart                  — crop tab bottom panel
    ├── adjustment_controls.dart            — adjust tab bottom panel
    └── rotation_controls.dart              — rotate tab bottom panel
```

---

## Architecture rules

### State management

- `ImageEditorState` is **immutable**. All changes go through `ImageEditorController` (a `ChangeNotifier`) which produces a new state via `copyWith()` and calls `notifyListeners()`.
- Widgets listen with `ListenableBuilder`. Never mutate `ImageEditorState` fields directly.

### Coordinate spaces

There are three distinct spaces. Always be explicit about which one you're in:

| Space               | Units                  | Notes                               |
| ------------------- | ---------------------- | ----------------------------------- |
| **Viewport space**  | Screen pixels          | Origin at top-left of `ImageCanvas` |
| **Image space**     | Source image pixels    | Origin at top-left of source image  |
| **Crop-rect space** | Viewport fractions 0–1 | `CropRect` always lives here        |

Converting between viewport ↔ image space goes through the 7-step pipeline in `TransformationService.viewportToImageCoordinates` / `imageToViewportCoordinates`. Never skip the `fitScale` step.

### Crop invariants — never break these

1. **Crop box must stay inside the image.** Use `TransformationService.constrainCropRectToImage()` after every crop-handle drag. This is the raycasting constraint.
2. **Image must always cover the crop box.** Use `TransformationService.clampPanToCoverCrop()` for all pan/zoom gestures in crop mode.
3. **Zoom floor is dynamic.** Compute `minUserScale` via `TransformationService.calculateMinUserScaleForCrop()` before clamping scale. Do not hard-code a `1.0` floor.
4. **16 px horizontal inset.** `_clampToViewport()` in `_CropOverlayState` applies `hInset = 16.0 / viewportSize.width` so corner handles are never clipped.

### Gesture architecture

- The **outer `GestureDetector`** (wraps the whole canvas) handles pan and pinch-zoom via `onScaleStart/Update/End`.
- **Corner/edge handles** resize the crop box via their own `onPanStart/Update/End`.
- The **crop interior `GestureDetector`** forwards all `onScaleStart/Update/End` events back to the canvas handlers so single-finger pan and pinch-zoom work inside the crop area too.
- Do not add a `onPanStart/Update/End` to the canvas outer `GestureDetector` — it uses `onScale*` exclusively to support simultaneous pan + pinch.

### Transform matrix

The rendered transform is always:

```
M = T(pan) × S(minScaleForRotation × userScale) × R(totalRotation) × S(flip)
```

Pivot is `Alignment.center`. When reconstructing the matrix for export, use the exact same order.

### Visual style

- Background and bar color is always `const Color(0xFF1C1C1E)`. Do not use `Colors.black` for structural backgrounds.
- When a crop handle is being dragged, the overlay fades to `overlayOpacity = 0.5` and the canvas background fades to transparent. Both are driven by `TweenAnimationBuilder` (200 ms, `easeInOut`).
- `ClipRect` wraps **only the transformed image**, not the `CropOverlay`. This allows the 30 px corner-handle circles to extend beyond the strict image bounds without being clipped.

### Snap animation

After 1 second of idle in crop mode, the crop box animates to fill the full viewport (`animateSnapCrop` on the controller). The snap drives three simultaneous tweens: `_scaleAnimation`, `_panAnimation`, and `_snapTAnimation` (which interpolates `CropRect` via `CropRect.lerp`). Cancel/reschedule the snap timer on every gesture start/end.

### Export

Use `ImageProcessing.processImage()` (WYSIWYG) when `state.displaySize` is available. It reconstructs the same `Matrix4` and records onto a `ui.Canvas`. Use `processImageFromBytes()` as a fallback. Always combine brightness + contrast + saturation into a single `ColorFilterMatrix.combined()` matrix — never chain three separate `ColorFilter` layers.

---

## Code style

- Use `const` constructors everywhere possible.
- Prefer `CupertinoIcons` and `CupertinoColors` over Material equivalents for UI chrome.
- All pure math belongs in `TransformationService` (a stateless service class). Do not put coordinate math inside widgets or the controller.
- Keep `image_canvas.dart` focused on rendering and gesture routing. Business logic goes in the controller; math goes in `TransformationService`.
