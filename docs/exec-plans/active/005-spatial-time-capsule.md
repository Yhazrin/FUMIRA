# Spatial Time Capsule

## Goal

Turn the MVP capture flow into one continuous encounter with reality:

`live scene → anchored instant → frozen reality → time develops → body opens result`

This plan enriches the existing still-photo pipeline without expanding product
scope. The JPEG remains canonical input; motion and the short time slice are
bounded context. Every enhancement is optional and has a non-motion fallback.

## Experience contract

### 1. Composition remains native and reachable

- The user pinches directly on the top-most viewfinder interaction surface.
- Pinching changes framing ratio, not zoom. The sequence remains continuous and
  bounded across full frame, 16:9, 3:4, and 1:1.
- The live scene is a full-width upper card over a solid blue camera body. Its
  top edge is fixed at the screen edge; only the lower edge moves between
  ratios. Only the lower corners are rounded, with no resting shadow or glass
  surround.
- The wave-shutter follows the optical center of the newly exposed blue body,
  and capture chrome reuses that exact geometry for its departure afterimage.
- Live chrome and capture departure chrome share the active window's safe-area
  insets, so neither top buttons nor the wave jump on shutter.
- Simulator framing crops one stable 3:4 SwiftUI scene master for every ratio.
  Mock capture renders that same logical-point master at 3x pixel density, so
  the flash freezes the scene without trees or roads changing scale.
- VoiceOver adjustable actions expose the same operation.
- Camera chrome, grid, and system-owned Dynamic Island remain separate. The app
  never draws a fake Dynamic Island.

### 2. The instant can be anchored, never gated

- A 12-segment reticle responds to real stability.
- Holding stability briefly tightens the reticle and produces one anchor haptic.
- Capture remains available before anchoring; VoiceOver explains this without
  adding persistent instructional copy over the viewfinder.
- Simulator and tests use a deterministic settling motion provider.

### 3. Capture creates a bounded temporal packet

`TemporalCapturePacket` contains:

- canonical still photo and selected composition;
- shutter date and capture origin;
- at most 1.2 seconds of recent motion context;
- an optional, low-resolution micro time slice around the shutter.
- native camera optical evidence (focus, exposure, ISO, zoom, and light class);
- an optional Vision-derived foreground mask and bounded salient regions.

The live camera samples the slice at approximately 8 fps, keeps at most 12
240px-wide JPEG frames, and chooses a window around the shutter. Failure or
unavailability returns an empty slice and does not fail still capture.

### 4. Waiting becomes reality developing

- Understanding, story writing, and generation share one persistent stage.
- The captured image remains mounted as the same hero object.
- Actual progress separates printed echo contours; device roll or a small drag
  permits bounded inspection.
- Horizontal inspection selects a real captured slice frame and reveals it only
  through a narrow temporal slit; the whole photo never becomes a muddy blend.
- The selected slice remains readable for 2.2 seconds after release, and the
  next drag cancels that dwell immediately.
- Scene clues and evidence chips use fully opaque semantic card colors. Image
  transparency is reserved for the temporal slit and subject-layer effects.
- Scene clues appear only after understanding exists. Before that, copy describes
  process rather than inventing content.
- A single solid status card shows the large percentage and a return-to-camera
  action. Interaction never controls pipeline completion.
- When the user has enabled the system Live Activity, it continues from capture
  through understanding, story, generation, and ready so progress is available
  outside the app without duplicating instructions inside the stage.

### 5. The body opens the result

- Result entry calibrates the current yaw as zero.
- The shortest yaw arc maps continuously to the time-door progress; roughly
  10–15 degrees completes it.
- The same shared progress controls image mask, ripple, shallow photo depth, and
  one completion haptic.
- “直接打开” is a 44pt fallback and the Reduce Motion path.
- After reveal, “对准现实” opens a draggable live/original versus generated
  split. The visible card contains only `拖动，看时间差` and the NOW-to-target
  range; VoiceOver owns the precise boundary instructions.
- “对准现实” is promoted to the result's primary action row after reveal;
  regeneration remains available as a secondary action.

## Service and ownership boundaries

- `AppModel` owns the `TemporalCapturePacket`, result reveal progress, and phase
  semantics.
- `CaptureMotionModel` owns bounded smoothing, anchoring, lifecycle, and context
  freezing.
- `CaptureMotionProviding` has live and mock implementations.
- `TemporalCameraSampling` is an optional camera capability. Photo capture does
  not depend on it.
- `SceneLayerAnalyzing` has live Vision and deterministic mock implementations.
  Foreground segmentation and attention saliency remain optional context.
- Camera optical state is sampled immediately before shutter and propagated as
  evidence rather than being re-inferred by the generation model.
- `RootView` owns persistent hero geometry and the functional motion lifecycle.
- Phase views render the current meaning of the same object; they do not create
  duplicate source/generated hero photos.

## Accessibility and resilience

- Capture is never disabled by instability or missing sensors.
- Reduce Motion removes motion-driven reveal and spatial inspection while
  preserving all information and completion paths.
- Controls remain at least 44pt.
- VoiceOver announces anchor status, aspect ratio, time-door progress, and the
  comparison boundary.
- Motion stops outside eligible foreground phases.

## Acceptance

- Real simulator `XCUIElement.pinch` changes the displayed framing ratio.
- Modern portrait 16:9, 3:4, and 1:1 cards use the exact screen width, share a
  fixed top edge, and expose progressively more blue body without a drop shadow.
- The real UI-test accessibility frame for the card starts at the window's
  leading edge and ends at its trailing edge before and after a pinch.
- Full/native framing remains visibly taller than 16:9 while its wave-shutter
  still clears the home indicator.
- Mock 3:4, 16:9, and 1:1 captures keep the selected ratio and a high-density
  master of at least 1500 pixels on the portrait long edge.
- Capture succeeds with mock motion and produces a packet.
- Camera and photo-library packet origins are correct.
- Result reveal math handles angle wraparound and reaches exactly 1.
- Real UI tap on “直接打开” removes the time door.
- Understanding can be cancelled back to the viewfinder during every developing
  subphase.
- Information cards remain fully opaque over both bright and dark photographs.
- Full build and tests pass under Swift 6.
- No feature file introduces raw product palette/radius/motion values.

## Verification snapshot — 2026-07-29

- iPhone 17 Pro simulator (iOS 26.5): 111 tests passed, 0 failed, 0 skipped.
- The UI suite exercised full-width framing, a real pinch ratio change, subject
  anchoring, top-chrome geometry, Live Activity feedback, reality-slice
  inspection, result reveal, and reality alignment.
- The simulator mock captured 3:4, 9:16, and 1:1 high-density images with the
  requested ratios.
- Generic iOS Simulator build completed with Swift 6 concurrency checking.
- Server relay: 40 tests passed and TypeScript compilation completed.
- The top action chrome is guarded by an automated opacity and contrast test:
  white glyphs on `actionBlue` meet 3:1 non-text contrast, while compact text
  feedback uses `actionBlueDeep` to meet 4.5:1.
