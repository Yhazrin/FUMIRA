# Flat Motion Polish

> Superseded for functional capture/reveal behavior by
> `005-spatial-time-capsule.md`. This plan remains the authority for the flat
> poster palette, time rail, and the three transient spatial-print tracks.

## Goal

Refine FUMIRA's latest park-poster UI so motion feels like spatial print:
flat color planes and crisp silhouettes, with perspective reserved for a brief
narrative camera/photo transition. Fix the waveform time rail, redraw the
connection backdrop, remove the duplicate/displaced invite title behavior, and
eliminate the ochre accent.

## Product direction

- The memorable interaction is the time waveform: the precise selected
  position is always the unique tallest peak.
- Spatial print perspective is allowed only for the narrative lens and temporal
  photo, and only during camera entry, capture, and generated-result reveal.
  It always settles back to a flat pose; it is not an idle or device-driven
  effect. Do not introduce glass, photorealistic 3D, realistic lighting,
  continuous floating, neon gradients, or particle noise.
- Controls, camera preview/chrome, shutter, waveform/time rail, numeric date,
  title, body copy, CTA, and export layout remain flat and spatially stable.
- Replace the ochre `moss` accent (`#C9B35A`) with the Doraemon-like
  `actionBlue` for controls, progress, and time selection. Landscape
  illustration may retain leaf green as a non-interactive natural color.

## Waveform requirements

Use a deterministic, continuous geometry model. For bar count `N`, selected
normalized value `s`, and continuous selected index `u`:

```text
u = ((clamp(s, -1, 1) + 1) / 2) * (N - 1)
d = index - u
G = exp(-0.5 * (d / 3.6)^2)
R = 0.84 + 0.16 * cos(1.15 * d)
```

Ordinary bars use the envelope/rhythm but must stay below 78% of maximum.
Draw an exact active capsule at the continuous thumb X with full maximum
height, making it the unique peak at every value. Draw all bars around one
horizontal center line so each capsule extends equally toward positive and
negative Y. Neighboring bars must morph continuously while dragging; do not
use a static/random height table or rounded selected index as the geometry
driver.

Preserve `TimePosition`'s nonlinear mapping:

```text
offsetDays = sign(s) * 36525 * abs(s)^2.35
```

Fix VoiceOver adjustment in offset-day space so NOW increments to ±1 day
instead of snapping back to zero. Fix haptics so the first touch establishes a
baseline, crossing NOW emits one tick, and signed decade crossings emit one
tick.

## Connection screen requirements

- Replace the gradient plus stacked ellipses and inset park card with one
  deeply drawn full-screen flat poster scene.
- Build the scene from custom SwiftUI `Shape`/`Canvas` layers: clean sky field,
  two or three designed hill silhouettes, an off-white path/river cut, and a
  small number of graphic botanical/time marks.
- Use asymmetry and strong negative space. The hero and CTA remain readable.
- Do not wrap the illustration in a rounded card.
- Render one invite headline only. Do not repeat “给时间，一张照片” as both
  hero and supporting copy.
- Remove the timed invite → connecting → invite layout swap. Do not animate
  whole-view alignment or offset. Use a one-shot, cancel-safe entrance that
  animates opacity and a small transform of stable-layout segments.

## Spatial-print tracks

Implement exactly three continuous, interruptible narrative tracks. Each begins
and ends flat, runs only for its semantic transition, has no bounce/overshoot,
and is inactive while idle, backgrounded, or disappeared.

1. **Lens aperture / camera entry:** the narrative lens seals the connection
   scene and opens into the camera from the aperture button center. The lens
   alone may use a shallow perspective turn while it travels.
2. **Temporal exposure / capture:** the matched captured photo persists through
   flash and exposure, with one shallow perspective pass that settles before
   camera controls are interactive again.
3. **Interpretation reveal / generated result:** that temporal photo develops
   into the generated treatment, may briefly recede/return in perspective, then
   locks into the flat result poster. Copy and controls never join the transform.

Keep the existing `MotionFieldProviding` service decorative-only: it may offset
flat background planes but never drives the narrative lens/photo. Functional
capture motion is owned separately by `CaptureMotionProviding` under plan 005.
Do not add a persistent 3D card. Perspective belongs only to the narrative
lens/photo during those three tracks and must read as printed material moving
through a camera, not as glass.

## Current implementation checkpoint

- `FUMIRASpatialMotion`, `MotionTimeline`, `SpatialDepthLayer`, and
  `SpatialTransformModifier` own the shared mapping, semantic admission, and
  device-motion depth rules.
- `CameraEntryPortal` grows the connection aperture into a preview hold and is
  reused after permission before the viewfinder becomes interactive.
- Root-owned `cameraEntryProgress`, `captureProgress`, and
  `timeRevealProgress` drive the three narrative tracks. The capture business
  task now has one semantic still hold rather than separate crossfade/dwell
  sleeps.
- `TemporalPhotoCard` supplies front/back/rim/edge/highlight/shadow treatment;
  `TimeRevealMask` develops the result inside the established photo crop.

## Motion language

- Entrance: 450–650 ms, decelerating, no bounce or elastic overshoot.
- Interaction feedback: 100–220 ms.
- Exit is approximately 75% of entrance duration.
- Every motion has a Reduce Motion fallback.
- No continuous animation when the view is idle.
- Avoid animating layout size, alignment, or padding.
- Reduce Motion uses the `Reduced` duration opacity crossfade only: no
  perspective, rotation, scale, or geometry travel.

## System camera surface

- The top camera chrome keeps two 48pt circular in-app controls. The trailing
  control starts the official ActivityKit Live Activity rather than imitating
  system hardware in the app view hierarchy.
- `FUMIRALiveActivity` renders compact, minimal, and expanded content with
  WidgetKit's `DynamicIsland`. iOS owns the island's outline, position,
  expansion gesture, and animation.
- The expanded presentation exposes flash, lens, grid, and aspect-ratio deep
  links. Capture and AVCaptureSession ownership remain in the main app.

## Required tests and verification

- Pure geometry tests prove the active peak is strictly taller than all
  ordinary bars at NOW, both endpoints, and intermediate values.
- Continuity tests cover nearby selected values.
- VoiceOver tests prove NOW adjusts to +1 day and -1 day and endpoints clamp.
- Existing nonlinear time mapping tests remain unchanged and pass.
- Verify no `#C9B35A`, “苔黄”, or direct `PosterPalette.moss` product use remains,
  and no interactive control uses green as its active color.
- Build the simulator target and run the full test suite.
- Inspect Swift 6 concurrency diagnostics.
- Verify Reduce Motion and Low Power behavior in code and previews.
- Exercise all three spatial-print tracks and verify perspective is transient,
  begins/ends flat, and is applied only to the narrative lens or temporal photo.
- During those tracks, verify controls, camera grid/chrome, shutter, text,
  numeric date, and WaveTimeRail retain stable position, size, and orientation.
- Verify device tilt remains decorative-only and respects its existing Reduce
  Motion, Low Power Mode, and scene-activity gates; spatial-print tracks add no
  idle motion.
