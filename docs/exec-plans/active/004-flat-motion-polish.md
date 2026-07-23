# Flat Motion Polish

## Goal

Refine FUMIRA's latest park-poster UI so motion feels like animated print:
flat color planes, crisp silhouettes, purposeful depth, and restrained device
tilt. Fix the waveform time rail, redraw the connection backdrop, remove the
duplicate/displaced invite title behavior, and eliminate the ochre accent.

## Product direction

- The memorable interaction is the time waveform: the precise selected
  position is always the unique tallest peak.
- 2.5D is allowed only as separated flat planes. Do not introduce glass,
  photorealistic 3D, continuous floating, neon gradients, or particle noise.
- Camera preview, shutter, waveform, title, body copy, and CTA must remain
  stable under device tilt. Only decorative background planes may move.
- Replace the ochre `moss` accent (`#C9B35A`) with a fresh leaf-green accent.
  The new accent must not read as yellow, brown, gold, mustard, or fluorescent.

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

## Device tilt

Add a small CoreMotion-backed service compatible with Swift 6 strict
concurrency. It must:

- publish clamped normalized gravity/attitude values on the main actor;
- update at 20–30 Hz, start only while an eligible screen is visible, and stop
  on disappear/background;
- remain inactive for Reduce Motion and Low Power Mode;
- never move camera preview, camera grid, waveform, shutter, headline, body
  copy, or CTA;
- offset only decorative flat planes by approximately 1.5 / 3 / 5 points in
  opposing directions;
- optionally rotate one rigid result-poster decoration by at most 0.75 degrees.

The effect must read as layered screen printing, not a floating glass card.

## Motion language

- Entrance: 450–650 ms, decelerating, no bounce or elastic overshoot.
- Interaction feedback: 100–220 ms.
- Exit is approximately 75% of entrance duration.
- Every motion has a Reduce Motion fallback.
- No continuous animation when the view is idle.
- Avoid animating layout size, alignment, or padding.

## Required tests and verification

- Pure geometry tests prove the active peak is strictly taller than all
  ordinary bars at NOW, both endpoints, and intermediate values.
- Continuity tests cover nearby selected values.
- VoiceOver tests prove NOW adjusts to +1 day and -1 day and endpoints clamp.
- Existing nonlinear time mapping tests remain unchanged and pass.
- Verify no `#C9B35A`, “苔黄”, or direct `PosterPalette.moss` product use remains.
- Build the simulator target and run the full test suite.
- Inspect Swift 6 concurrency diagnostics.
- Verify Reduce Motion and Low Power behavior in code and previews.

