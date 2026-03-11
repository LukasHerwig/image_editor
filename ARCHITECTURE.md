# Z Image Editor — Architecture & Technical Reference

## Table of Contents

1. [What the Editor Does](#1-what-the-editor-does)
2. [File Map](#2-file-map)
3. [State Model](#3-state-model)
4. [Coordinate System](#4-coordinate-system)
5. [Transform Pipeline](#5-transform-pipeline)
6. [Crop Constraint — Raycasting](#6-crop-constraint--raycasting)
7. [Pan Clamping](#7-pan-clamping)
8. [Minimum Zoom Calculation](#8-minimum-zoom-calculation)
9. [Snap-to-Viewport Animation](#9-snap-to-viewport-animation)
10. [Export / Image Processing](#10-export--image-processing)
11. [Gesture System](#11-gesture-system)
12. [Visual Overlay Behaviour](#12-visual-overlay-behaviour)
13. [Data Flow Diagram](#13-data-flow-diagram)

---

## 1. What the Editor Does

`ZImageEditor` is a Flutter widget package that gives the host app a full-screen, iOS Photos-style image editor. It accepts either a `File` or raw `Uint8List` and returns a processed `File` via `onSave`.

**Crop tab**

- Free-form or aspect-ratio-locked crop box.
- Corner and edge handles resize the crop box. Dragging inside the crop area pans the image (not the box).
- Pinch-to-zoom works anywhere on screen, including inside the crop area.
- After 1 second of idle the crop box animates to fill the full viewport (snap animation).
- The image can never be panned or zoomed so that any part of the crop box would fall outside the image.
- The crop box can never escape the image bounds (enforced by raycasting on every drag event).
- A 16 px horizontal inset on each side keeps corner handles fully visible.

**Adjust tab**

- Real-time brightness (−100 … +100), contrast (0.5 × … 2.0 ×), saturation (0.0 × … 2.0 ×) previewed live with a `ColorFilter`.

**Rotate tab**

- 90° discrete rotation, horizontal flip, vertical flip.
- Fine rotation slider (±45°).
- `minScaleForRotation` is recomputed after every rotation change so the rotated image always covers the viewport.

**Export**

- WYSIWYG: the exact same `Matrix4` used by the canvas widget is reconstructed and applied to the native-resolution image via a `ui.Canvas` recorder → PNG.
- Fallback: the `image` package handles pixel manipulation when no layout data is available.

---

## 2. File Map

```
lib/
├── image_editor.dart                    — public barrel (re-exports ZImageEditor)
├── z_image_editor.dart                  — package entry point
└── src/
    ├── models/
    │   └── image_editor_state.dart      — immutable state: all fields + enums + CropRect
    ├── controller/
    │   └── image_editor_controller.dart — ChangeNotifier; owns & mutates state, animations
    ├── utils/
    │   ├── transformation_service.dart  — all coordinate math (raycasting, clamp, coord conversion)
    │   └── image_processing.dart       — WYSIWYG export renderer + color matrix builder
    └── widgets/
        ├── z_image_editor_widget.dart   — root widget (scaffold, header, tab bar)
        ├── image_canvas.dart           — interactive canvas + CropOverlay + gesture handling
        ├── crop_controls.dart          — crop tab bottom panel (fine rotation, aspect ratios)
        ├── adjustment_controls.dart    — adjust tab bottom panel (brightness/contrast/saturation)
        └── rotation_controls.dart      — rotate tab bottom panel (flip, 90°, fine rotation)
```

### File responsibilities in detail

| File                                | Responsible for                                                     | NOT responsible for                 |
| ----------------------------------- | ------------------------------------------------------------------- | ----------------------------------- |
| `image_editor_state.dart`           | Defining the shape of all editor state as an immutable value object | Mutating state; any UI              |
| `image_editor_controller.dart`      | All state mutations, animation coordination, geometric invariants   | Rendering; coordinate math details  |
| `transformation_service.dart`       | Every coordinate-space conversion and geometric clamp               | State, UI, animation                |
| `image_processing.dart`             | Computing the final exported pixel image                            | Live preview, gestures              |
| `z_image_editor_widget.dart` | Scaffold layout, header, tab bar, save flow                         | Canvas rendering, gesture handling  |
| `image_canvas.dart`                 | Rendering the transformed image, crop overlay, all gesture handlers | Bottom controls, export             |
| `crop_controls.dart`                | Crop tab UI (slider, aspect chip row)                               | Actually constraining the crop rect |
| `adjustment_controls.dart`          | Brightness/contrast/saturation sliders                              | Color math                          |
| `rotation_controls.dart`            | Rotation/flip buttons + fine slider                                 | Transform math                      |

---

## 3. State Model

`ImageEditorState` is an immutable `const` struct (value object). Every field change produces a new copy via `copyWith()`. The controller (`ChangeNotifier`) holds the single current instance and calls `notifyListeners()` after every mutation.

```
ImageEditorState
├── brightness        double   −100 … +100 (0 = neutral)
├── contrast          double   0.5 … 2.0   (1.0 = neutral)
├── saturation        double   0.0 … 2.0   (1.0 = neutral)
├── rotation          double   0, 90, 180, 270  (discrete 90° steps)
├── fineRotation      double   −45.0 … +45.0
├── totalRotation     double   rotation + fineRotation  (computed)
├── flipHorizontal    bool
├── flipVertical      bool
├── cropRect          CropRect?  (viewport-fraction coordinates)
├── scale             double   userScale; 0.05 … 4.0 (1.0 = fit)
├── panOffset         Offset   screen-space pixels
├── currentTab        EditorTab (crop | adjust | rotate)
├── aspectRatioPreset AspectRatioPreset
├── displaySize       Size?    (viewport px; set by LayoutBuilder)
└── imageSize         Size?    (source image px; set once decoded)
```

`CropRect` stores `{left, top, width, height}` as fractions of the viewport (0.0–1.0 each). It has a static `lerp(a, b, t)` method for the snap animation.

---

## 4. Coordinate System

There are three distinct spaces that all math operates across:

| Space               | Units                    | Origin                               |
| ------------------- | ------------------------ | ------------------------------------ |
| **Viewport space**  | Screen pixels            | Top-left of the `ImageCanvas` widget |
| **Image space**     | Source image pixels      | Top-left of the source image         |
| **Crop-rect space** | Viewport fractions (0–1) | Top-left of the viewport             |

`CropRect` lives in **crop-rect space**.  
`panOffset` and focal points live in **viewport space**.  
Raycasting operations convert between viewport and image space.

---

## 5. Transform Pipeline

The canvas renders using a **single `Transform` widget** with a `Matrix4`. The concatenated matrix is:

```
M = T(pan) × S(minScaleForRotation × userScale) × R(totalRotation) × S(flip)
```

All transforms pivot at `Alignment.center` (= viewport centre for a `BoxFit.contain` image).

**Why `minScaleForRotation`?**  
When an image is rotated by angle θ, it can no longer fill the same rectangular viewport at scale 1.0 — the corners stick out. `minScaleForRotation` is the smallest scale that guarantees the image always covers the full viewport regardless of rotation. `userScale` is the additional zoom applied on top of this floor.

**`fitScale`** is handled separately by `BoxFit.contain` on the `Image` widget, but must be factored into every coordinate conversion (see §6).

---

## 6. Crop Constraint — Raycasting

**Problem:** After any crop handle drag, the proposed new `CropRect` may have corners that fall outside the visible (rotated, scaled, panned) image area. We must reject / clamp those corners.

**Algorithm (`constrainCropRectToImage` in `transformation_service.dart`):**

For each of the four crop corners:

1. Convert the corner from **viewport space → image space** using `viewportToImageCoordinates()`.
2. Clamp the image-space point to `[0, imageWidth] × [0, imageHeight]`.
3. Convert back from **image space → viewport space** using `imageToViewportCoordinates()`.

The round-trip through image space is the "raycast" — we trace each corner through the full inverse transform to find where it actually lands on the image, clamp it there, and project back.

**`viewportToImageCoordinates()` — 7-step pipeline:**

```
1.  vpPoint  − vpCentre                 (shift origin to viewport centre)
2.  result   − panOffset                (remove user pan)
3.  result   / totalScale               (undo user zoom + minScaleForRotation)
4.  result   rotated by −totalRotation  (undo rotation)
5.  result.x / flipX, result.y / flipY  (undo flip: ×1 or ×−1)
6.  result   / fitScale                 (undo BoxFit.contain scaling)
7.  result   + imageSize / 2            (shift origin from image centre to image top-left)
```

**`imageToViewportCoordinates()`** is the exact inverse of the above (steps reversed, signs flipped).

**Important:** `fitScale = min(vpW / imgW, vpH / imgH)`. This was a critical fix — early versions omitted the fitScale step and produced small but consistent errors when the image aspect ratio differed from the viewport.

**`constrainCropRectToImage()`** runs this round-trip on all four corners and computes the tightest enclosing crop rect that fits entirely within the image. Each corner is clamped independently, allowing asymmetric crops near any rotated edge.

---

## 7. Pan Clamping

**Requirement:** The user must never be able to pan the image so that any part of the crop box lies outside the image.

Two implementations with different speed/accuracy tradeoffs:

### Fast AABB clamp — `clampPanOffset()`

Uses the axis-aligned bounding box (AABB) of the rotated image to compute allowed pan ranges. O(1), used outside crop mode.

```
bbW = fitW · totalScale · cos(θ) + fitH · totalScale · sin(θ)
bbH = fitW · totalScale · sin(θ) + fitH · totalScale · cos(θ)
maxPanX = cropLeft − vpCentreX + bbW/2
minPanX = (cropLeft + cropW) − vpCentreX − bbW/2
```

Over-constrains (allows less pan than strictly necessary), which is safer but slightly restrictive on rotated images.

### Exact raycasting clamp — `clampPanToCoverCrop()`

Projects all four crop corners into image space, finds the minimum pan shift required to bring every corner inside `[0, imgW] × [0, imgH]`, then converts that shift back to a viewport pan delta. Used **in crop mode** for all pan and zoom gestures.

```
// For each crop corner c, compute image-space position:
imgPoint = viewportToImageCoordinates(c, pan: currentPan)

// Find how far out of bounds it is:
ΔimgX = clamp(imgPoint.x, 0, imgW) − imgPoint.x
ΔimgY = clamp(imgPoint.y, 0, imgH) − imgPoint.y

// Convert image-space delta back to pan delta via the inverse rotation+scale matrix:
ΔpanX = −totalScale·fitScale · (cosθ·fx·ΔimgX − sinθ·fy·ΔimgY)
ΔpanY = −totalScale·fitScale · (sinθ·fx·ΔimgX + cosθ·fy·ΔimgY)
// (fx, fy = flip factors: +1 or −1)

// Take the minimum required correction across all four corners
pan_clamped = pan + min_required_delta
```

O(1) — no iteration. Guarantees the **tightest possible** constraint with no over-restriction.

---

## 8. Minimum Zoom Calculation

**Requirement:** The user cannot zoom out past the point where the image stops covering the crop box. The minimum allowed `userScale` is dynamic and depends on the crop box size, rotation and flip state.

**`calculateMinUserScaleForCrop()`**

Treats the crop box as a rectangle and computes how large the image must be (in viewport space) to fully contain the crop box's rotated footprint:

```
cropW = cropRect.width  × vpW
cropH = cropRect.height × vpH
θ     = totalRotation

// Rotated crop box footprint (AABB of the rotated crop box in image space):
cropExtentX = cropW · |cosθ| + cropH · |sinθ|
cropExtentY = cropW · |sinθ| + cropH · |cosθ|

// The image (at fitScale) must be at least this large in viewport space:
minTotalScale = max(cropExtentX / fitW, cropExtentY / fitH)
minUserScale  = max(0.01, minTotalScale / minScaleForRotation)
```

This formula has no floor at `1.0`, so the user can zoom out below the "fit" scale as long as the crop box is small enough — matching iOS Photos behaviour.

**`calculateMinScaleForRotation()`**

Completely separate from the above. Answers the question: _what scale makes the rotated image fill the full viewport?_ Solved using the inscribed-rectangle formula and memoised against `(rotation, imageAR, cropAR)`.

---

## 9. Snap-to-Viewport Animation

After **1 second of idle** (no gesture, no crop handle drag), the crop box and image animate so the crop box exactly fills the viewport. This matches the iOS Photos behaviour.

**Trigger:** `_scheduleSnap()` starts a `Timer(1s, _onSnapTimer)`. It is cancelled on `_onScaleStart` and rescheduled on `_onScaleEnd` and after every crop-handle drag.

**`_onSnapTimer()` math:**

```
s = min(vpW / cropW_px, vpH / cropH_px)   // scale to fill viewport
if s ≤ 1.01: return                        // already full — nothing to do

newUserScale = min(state.scale × s, 4.0)
effectiveS   = newUserScale / state.scale  // may differ if capped at 4×

// Find the image pixel at the current crop-box center:
cropCenterVp = (cropRect.center) × vpSize
imagePoint   = viewportToImageCoordinates(cropCenterVp, ...)

// Find the pan that puts that image pixel at the viewport center:
vpPointZeroPan = imageToViewportCoordinates(imagePoint, pan: Offset.zero, scale: newTotalScale)
newPan         = vpCenter − vpPointZeroPan

// Build new crop rect — same physical size, centered in viewport:
newCropRect = CropRect centered at viewport center, size = cropSize × effectiveS
```

**`animateSnapCrop()`** in the controller drives three simultaneous animations:

- `_scaleAnimation` — `userScale` current → target
- `_panAnimation` — `panOffset` current → target
- `_snapTAnimation` — `0.0 → 1.0`, used to interpolate `_snapCropStart → _snapCropEnd` via `CropRect.lerp()`

All three are driven by the single shared `AnimationController` (350 ms, `easeInOut`).

---

## 10. Export / Image Processing

**Primary path — WYSIWYG (`_processImageWysiwyg`):**

Exact pixel-perfect reproduction of what the canvas shows, at native resolution:

1. Compute `fitScale`, `fitW/H`, `fitOffX/Y` — identical to `BoxFit.contain` math.
2. Determine the crop window in viewport px (falls back to fitted image rect if `cropRect == null`).
3. Output resolution: `outputW = cropW_px / totalMag`, `outputH = cropH_px / totalMag`.
4. Reconstruct the same `Matrix4` as the canvas widget:
   ```
   T(vpCenter + pan) × S(totalDisplayScale) × R(θ) × S(flip) × T(−vpCenter)
   ```
5. Record onto a `ui.Canvas`:
   - `canvas.scale(nativeToDisplayRatio)`
   - `canvas.translate(−cropOrigin)`
   - `canvas.transform(fullMatrix)`
   - `canvas.drawImageRect()` with a `ColorFilter` combining brightness + contrast + saturation in one matrix multiply.
6. Encode as PNG → temp file.

**Fallback path (`_processImageFallbackFromBytes`):**  
Uses the `image` Dart package for pixel manipulation. Order: `rotate → crop → flip → color adjustments`. Used when `displaySize` is not yet known.

**`ColorFilterMatrix.combined()`:**  
Builds a single 5×4 RGBA matrix that folds brightness, contrast, and saturation into one pass (one GPU call). This avoids compounding errors from chaining three separate `ColorFilter` layers.

---

## 11. Gesture System

The canvas has two gesture layers, both ultimately feeding the same `_onScaleStart/Update/End` handlers on `_ImageCanvasState`:

```
Outer GestureDetector (whole canvas)
  onScaleStart/Update/End → _onScaleStart/Update/End

CropOverlay (children in a Stack above ClipRect)
  ├── Corner handles (×4)           — onPanStart/Update/End → resize crop box
  ├── Edge handles (×4)             — onPanStart/Update/End → resize crop box
  └── Interior GestureDetector      — onScaleStart/Update/End → forwarded to canvas handlers
```

**Why the interior forwards to the canvas:** `HitTestBehavior.opaque` on the interior widget would otherwise consume all touches without the outer `GestureDetector` seeing them. By forwarding `onScaleStart/Update/End` back to the canvas handlers, both pan (1-finger) and pinch-zoom (2-finger) work anywhere on screen.

**`_onScaleUpdate` steps:**

1. Compute `minUserScale` via `calculateMinUserScaleForCrop()`.
2. Clamp `newUserScale = (_gestureStartUserScale × details.scale).clamp(min, 4.0)`.
3. Compute raw pan from zoom-around-focal-point formula:
   ```
   r      = totalScaleNew / totalScaleStart
   rawPan = (focalStart − vpCenter) × (1−r) + panStart × r + (focalCurrent − focalStart)
   ```
4. Clamp pan via `clampPanToCoverCrop()` (crop mode) or `clampPanOffset()` (other modes).
5. Write `setScale()` + `setPanOffsetDirect()` to controller.

---

## 12. Visual Overlay Behaviour

### Overlay opacity states

| State                | `overlayOpacity` | Container BG opacity | Effect                                                               |
| -------------------- | ---------------- | -------------------- | -------------------------------------------------------------------- |
| Idle (snap complete) | `1.0`            | `1.0`                | Solid dark outside crop box; matches top/bottom bars (`#1C1C1E`)     |
| Dragging a handle    | `0.5`            | `0.0`                | Semi-transparent overlay + transparent BG → full image shows through |
| Transition           | animating        | animating            | 200 ms `easeInOut` `TweenAnimationBuilder`                           |

**Why two separate opacity levers:** The `CropOverlayPainter` only covers the area inside the `CropOverlay`'s `Positioned.fill` (which matches the canvas). The canvas container background covers the letterbox areas _outside_ the image. Both must fade together to give a seamless effect.

### Crop-box edge guard

`_clampToViewport()` enforces a **16 px horizontal inset** (converted to viewport fractions) so the crop box — and its corner handle circles — can never touch the left or right screen edge.

### `ClipRect` placement

The `ClipRect` wraps only the `transformedImage` (prevents the transformed image from painting into the bar areas during extreme pan). The `CropOverlay` sits **outside** the `ClipRect` in a sibling `Stack` layer, so the 30 px corner circles can safely overflow the strict viewport boundary without being cut off.

---

## 13. Data Flow Diagram

```
User gesture
    │
    ▼
_ImageCanvasState._onScaleUpdate / CropOverlay handle pan
    │                │
    │                ▼ (crop handle drag)
    │           TransformationService.constrainCropRectToImage()
    │           + _clampToViewport(16px inset)
    │                │
    │           controller.setCropRect()
    │
    ▼ (pan/zoom)
TransformationService.clampPanToCoverCrop()   ← exact raycasting
TransformationService.calculateMinUserScaleForCrop()
    │
    ▼
controller.setScale() + setPanOffsetDirect()
    │
    ▼ (notifyListeners)
ImageCanvas.build() → Transform(Matrix4) → renders image
CropOverlay.build() → CropOverlayPainter → draws dark overlay + white border

    ── idle 1 s ──▶  _onSnapTimer()
                         │
                         ▼
                   controller.animateSnapCrop()
                     ├── _scaleAnimation
                     ├── _panAnimation
                     └── _snapTAnimation → CropRect.lerp()
                         │
                         ▼ (each frame)
                   _onAnimationTick → state.copyWith(...) → notifyListeners

    ── "Done" ──▶  ImageProcessing.processImage()
                     │
                     ▼
                   Reconstruct Matrix4 → ui.Canvas → PNG → File → onSave()
```
