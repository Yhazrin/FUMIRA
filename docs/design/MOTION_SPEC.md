# Motion Specification

## Tokens from Figma

| Token | Duration | Intent |
|---|---:|---|
| Micro | 100–220ms | press, snap-like feedback, micro response |
| Entrance | 450–650ms | decelerating segment entrances (no bounce) |
| Exit | ~75% of entrance | leaving decorative segments |
| Time Flow | 340ms | soft rail morph while scrubbing |
| Time-wheel lock | 70ms + 200ms | directional impulse then firm return to snapped date |
| Page | 520ms | lens/photo continuous transformation |
| Reduced | 150ms | opacity crossfade only |

## Rules

- Press and interaction feedback stay within 100–220ms; entrances use a
  decelerating curve with **no bounce or elastic overshoot**.
- Exit duration is approximately 75% of the matching entrance.
- The lens, scene, and time seed persist across major phase transitions.
- When the shutter moves, poster text stays stable.
- While time changes, animate only scene treatment, active rail, and numeric label.
- Scrubbing is interruptible. Never queue animations for prior time values.
- In Reduce Motion, disable parallax, rotation, scale, orbit, and geometry travel.
- Haptic feedback is sparse: first drag sample establishes a baseline; crossing
  NOW or a signed decade emits one tick — not every drag step.
- No continuous animation when the view is idle.
- Avoid animating layout size, alignment, or padding.

## Continuous rail (WaveTimeRail)

The thumb/cursor directly follows touch. A separate presentation value may spring
toward the domain value after release, but it may not snap to landmarks.
Sparse labels at -100, NOW, +100 are labels only.

Geometry is deterministic: for each normalized value `s`, ordinary bars use
`G*exp(-0.5*(d/3.6)^2)` and `R=0.84+0.16*cos(1.15*d)` capped below 78% of peak;
the active capsule at continuous thumb X is the unique tallest bar, centered on
the rail midline with symmetric ±Y extent.

On finger-up, snap only to browse date granularity (day / week / month / year by
distance from NOW). When motion is enabled, the presentation rail makes one
bounded 70ms directional impulse (at most 1.8% of the rail range), gives the
selected peak a deterministic local resonance, then returns to the snapped date
in 200ms. The date model itself snaps immediately; this never changes date
semantics or crosses ±100 years. Selected wave morph and year label use this
firm settle; while dragging, follow the finger with no lag animation.

VoiceOver adjustable actions step in offset-day space: at NOW, increment/decrement
moves ±1 day instead of snapping back to zero.

Selected bar / cursor / year emphasis uses `PosterPalette.leafGreen` (≤5% 点睛).

## Device tilt (2.5D)

- CoreMotion-backed service publishes clamped normalized attitude on the main actor
  at ~20–30 Hz while connection / result / share are visible.
- Inactive for Reduce Motion, Low Power Mode, and background/disappear.
- Only decorative flat planes offset (~1.5 / 3 / 5 pt in opposing directions).
  Camera preview, grid, waveform, shutter, headlines, body copy, CTAs, and export
  output never move.
- Share poster may rotate one rigid decoration by ≤0.75°.

## 首屏 / 相机动效

### PosterKeywordHero

- Connection uses a one-shot, cancel-safe entrance (opacity + small transform) on
  stable layout segments. No timed invite ↔ connecting layout swap.
- Reduce Motion: static invite composition; phase change uses the 150ms opacity
  crossfade from `PhaseTransition`.

### Viewfinder shutter

- Capture keeps `matchedGeometryEffect("camera-photo")` into shutter feedback
  unless Reduce Motion is on.
- Add a restrained paper-white flash wash (`PosterEffects.cameraFlashWash`) on
  shutter press (Micro duration); AppModel plays `.shutter` before camera capture
  starts so the physical response is immediate.
- Camera chrome uses `PosterPressStyle` press scale only — no looping motion.

## Camera transitions and haptics

- Pow 1.0.6 is limited to three semantic transitions: Iris when entering the
  camera, Snapshot / Film Exposure across capture, and a leaf-green Glare pass
  when the generated result develops. Reduce Motion replaces all three with
  opacity.
- `LiveHapticsClient` owns one reusable Core Haptics engine. It restarts after
  engine reset/stoppage and falls back to UIKit feedback when custom haptics are
  unavailable.
- Shutter: crisp blade release + quieter return + 65ms body resonance.
- Timeline decade and release lock: one crisp leading tooth plus a quiet body
  return. Crossing NOW: stronger soft-leading / crisp-trailing double detent to
  suggest a lateral notch.
- Generated reveal: 220ms low swell resolving into one crisp lock.
- Save/share: three restrained rising film-advance teeth.
- Core Haptics controls intensity, sharpness, and timing; it cannot direct the
  Taptic Engine along a literal physical X axis.
