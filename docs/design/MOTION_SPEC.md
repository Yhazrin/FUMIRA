# Motion Specification

## Tokens from Figma

| Token | Duration | Intent |
|---|---:|---|
| Micro | 180ms | press, snap-like feedback, micro response |
| Time Flow | 340ms | soft rail/scene reveal |
| Poster | 420ms | segmented display lettering entrance |
| Page | 520ms | lens/photo continuous transformation |
| Reduced | 150ms | opacity crossfade only |

## Rules

- Press compresses first; release overshoots slightly and settles.
- The lens, scene, and time seed persist across major phase transitions.
- When the shutter moves, poster text stays stable.
- While time changes, animate only scene treatment, active rail, and numeric label.
- Scrubbing is interruptible. Never queue animations for prior time values.
- In Reduce Motion, disable parallax, rotation, scale, orbit, and geometry travel.
- Haptic feedback is sparse: NOW crossing and decade crossings, not every drag tick.

## Continuous rail (WaveTimeRail)

The thumb/cursor directly follows touch. A separate presentation value may spring
toward the domain value after release, but it may not snap to landmarks.
Sparse labels at -100, NOW, +100 are labels only.

On finger-up, snap only to browse date granularity (day / week / month / year by
distance from NOW). Selected wave bar and year label use Time Flow when Reduce
Motion is off; while dragging, follow the finger with no lag animation.

Selected bar / cursor / year emphasis uses `PosterPalette.moss`（苔黄 ≤5% 点睛）.
Do not paint the rail track or page with fluorescent Energy Lime.

## 首屏 / 相机动效

### PosterKeywordHero

- On connection appear, title may **briefly recompose** (invite ↔ connecting
  layout) with Poster spring — then settle. Never continuous bobbing/orbit.
- Reduce Motion: keep the invite composition; no rotation offsets; phase change
  uses the 150ms opacity crossfade from `PhaseTransition`.

### Viewfinder shutter

- Capture keeps `matchedGeometryEffect("camera-photo")` into shutter feedback
  unless Reduce Motion is on.
- Add a restrained paper-white flash wash (`PosterEffects.cameraFlashWash`) on
  shutter press (Micro duration); AppModel still plays `.shutter` haptics.
- Camera chrome uses `PosterPressStyle` press scale only — no looping motion.
