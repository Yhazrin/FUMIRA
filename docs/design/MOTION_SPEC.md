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

Vertical movement changes the active rail precision in 28pt detents:
year → month → day → hour when pulling up, and the reverse when pulling down.
Horizontal movement follows the finger at that precision. On finger-up, snap
only to the active precision. When motion is enabled, the presentation rail
makes one bounded 70ms directional impulse (at most 1.8% of the rail range),
gives the selected peak a deterministic local resonance, then returns to the
snapped date in 200ms. The date model itself snaps immediately; this never
changes date semantics or crosses ±100 years. Selected wave morph and date
label use this firm settle; while dragging, follow the finger with no lag
animation.

VoiceOver adjustable actions step in offset-day space using the active precision:
±1 year, ±1 month, ±1 day, or ±1 hour.

Selected bar / cursor / year emphasis uses `PosterPalette.actionBlue`.

## Spatial print perspective

FUMIRA remains a flat poster product. “Spatial print” is a transient narrative
cue, not a device-tilt effect or a general 3D language. It may affect only the
narrative lens and the temporal photo during camera entry, capture, and generated
result reveal. Each affected element returns to its flat, untransformed resting
state when the transition completes.

- Decorative CoreMotion remains limited to the existing 2.5D print planes.
  A separate, functional capture-motion stream may drive the time-anchor
  reticle and freeze a bounded shutter context. Result reveal uses short-lived
  microphone level input instead of device rotation.
  Functional motion always has a visible button/touch fallback and never blocks
  capture, generation, or result access. Do not add idle floating, glass,
  realistic lighting, photorealistic 3D, neon gradients, or simulated depth of
  field. The result reveal may emit a bounded paper-fleck field only while the
  user is actively blowing; it disappears at completion.
- Controls, camera grid/chrome, shutter, headlines, body copy, CTA, numeric date,
  waveform/time rail, and export layout stay flat. The only viewfinder exception
  is the user-driven aspect morph: the full-width card changes height and the
  wave-shutter follows the optical center of the newly exposed blue control deck.
  Neither element gains perspective, free rotation, or an idle pose.
- A perspective transform is brief, transition-bound, and reversible: it begins
  and ends at a flat pose, has no bounce or overshoot, and never leaves a
  persistent rotated/scaled card on screen.
- Reduce Motion disables perspective, rotation, scale, and geometry travel. Each
  track below becomes an opacity-only crossfade using the `Reduced` token.

### Three continuous narrative tracks

1. **Lens aperture track — camera entry.** The narrative lens closes to seal the
   connection scene, then opens from the aperture button center into the camera.
   Its printed aperture plane may use one restrained perspective turn while the
   blades travel; the camera surface is flat as soon as it is visible.
2. **Temporal exposure track — capture.** The captured temporal photo remains the
   same matched element through flash/exposure and into interpretation. It may
   make one shallow perspective pass to imply a print passing through the lens,
   then settles flat before controls become interactive again.
3. **Interpretation reveal track — generated result.** Microphone dB is reduced
   immediately to a normalized gust; no audio is recorded or retained. The
   captured photo lifts and erodes from its lower edge while bounded paper flecks
   travel upward, revealing the already-generated target photo below. Surrounding
   copy and controls do not move, and the final composition is flat.

Tracks are interruptible and never queue stale values. They are not active while
the corresponding screen is idle, while the app is backgrounded, or after the
transition has settled. The temporal exposure is triggered only by
`shuttered → understanding`; interpretation reveal only by `generating → result`.
Returning from share, retry navigation, and ordinary phase changes remain flat.

### Implementation contract: FUMIRASpatialMotion

`FUMIRASpatialMotion` is the only mapping authority for narrative spatial
motion. It clamps every input to `0...1`, remaps named subranges, and derives a
brief flat-to-depth-to-flat pulse. `MotionTimeline` permits only these semantic
tracks; it rejects ordinary navigation so spatial motion cannot become a page
transition template.

- `cameraEntryProgress` drives the 88pt connection aperture into
  `CameraEntryPortal`. The portal holds a composited preview while permission is
  being resolved, then releases to the real viewfinder. It mounts at the exact
  88pt source geometry for one frame before progress begins, so the first
  visible frame cannot pop in as a large disc. Its early scale is deliberately
  slow while the first 18% retains the button's press acknowledgement, then
  accelerates to coverage with a non-bouncy ease-in-out curve rather than
  stacking two ease-out curves; there is no closing-iris sleep chain.
- While an already-authorized permission check resolves, CameraPermissionView
  holds the destination's blue body and full-width sky card silhouette. It never
  inserts a white frame between the connection lens and live preview. A real
  consent or recovery prompt remains an ordinary white system-readable page.
- `captureProgress` spans shuttered through understanding. Its hero/chrome/text
  subranges are mapped from one value: camera chrome leaves first, the frozen
  photo lifts and gains paper depth, then it settles into the understanding
  destination. The single capture hold in `AppModel` is semantic still time,
  not a visual timing script.
- `timeRevealProgress` masks the generated photo across its existing crop while
  three thin printed time rings travel across it and the photo makes a short
  depth pulse. It is not an opacity-only replacement of the source image.

`TemporalPhotoCard` has a front surface, an intentionally plain reverse,
paper rim, directional thin edges, motion-aware specular highlight, and a
shadow derived from lift/yaw/pitch. It remains a SwiftUI 2.5D surface; no
SceneKit, RealityKit, or idle 3D treatment is used.

### Silent developing reflection

Understanding, story writing, and image generation share one quiet waiting
stage. There is no visible percentage, progress bar, queue label, or looping
loading ornament. The shared captured print is the only interactive hero:

1. A vertical drag gives the print the existing bounded held pose.
2. A committed horizontal drag turns the same print exactly 180 degrees to its
   paper reverse. The reverse varies its local medium: a future guess, past
   time-imprint stamps, or a NOW written note; it remains available while phases
   advance.
3. A second horizontal turn returns to the photo. The front carries no extra
   flip control, and reduced motion swaps faces without perspective travel.

The turn uses `PosterMotion.photoHandSettle`, has no bounce, and does not block
the pipeline. It is an intentional interaction, not an idle animation. Outside
the print, the existing bounded temporal-slice scrub remains available.

### Shared depth planes

`SpatialDepthLayer` defines four planes: background (2pt), environment (5pt),
hero (8pt and at most 2.8 degrees), and chrome (1pt, no rotation). CoreMotion
only enhances eligible idle poster scenes. Reduce Motion, Low Power Mode,
serious/critical thermal state, and inactive scenes disable the field.

## Functional capture motion

- `CaptureMotionProviding` is separate from decorative `MotionFieldProviding`.
  Live capture samples device attitude, rotation rate, and user acceleration at
  roughly 30 Hz. The app retains only the most recent 1.2 seconds in memory.
- Stability is a progressive signal, not a shutter gate. At 82% smoothed
  stability held for about 420ms, the 12-segment reticle tightens and changes to
  “时间已定锚”. Users can still capture at any stability.
- The shutter freezes a bounded `TemporalMotionContext` into the
  `TemporalCapturePacket`; camera capture also requests an optional micro time
  slice around the shutter. Failure of either enhancement never fails the still.
- A horizontal inspection selects the slice continuously while the finger moves,
  then holds the selected slit for 2.2 seconds after release. The hold is a
  readability window, not a pipeline delay; a new gesture cancels it immediately.

## Result reveal

- On result entry, a short-lived `AVAudioEngine` input tap publishes only RMS/dB
  levels. A noise gate and attack/release smoothing map blow strength to the same
  continuous generated-image reveal progress. Raw buffers are never recorded,
  retained, encoded, or written to storage. A 44pt “直接显影” button is always
  available for denied permission, unavailable input, VoiceOver, and preference.
  Reduce Motion keeps the microphone gesture but replaces paper travel and
  particles with a bottom-up mask and opacity fade.
- During silent development, the persistent print can also turn to a single
  time-specific reflection question. Horizontal drag rotates the same card in
  place; with Reduce Motion the same horizontal gesture swaps faces directly.
- Motion sampling is active only for viewfinder, capture/developing, and result
  phases while the scene is foregrounded. Anchor haptics are enabled only in the
  viewfinder.

## Future-fork shake

- Future results with at least two Scene Bible evidence paths may offer a
  bounded “同一年，另一种可能” selector. Past, NOW, missing evidence, and a
  mismatched browse time expose no branch interaction.
- UIKit's discrete `motionEnded(_:with:)` shake event is bridged through a
  result-only responder controller. It never creates another `CMMotionManager`;
  the bridge resigns first responder on disappearance or backgrounding and the
  default listening window ends after eight seconds.
- A shake advances exactly one deterministic branch and emits one selection
  haptic. It never changes `selectedTime`, writes a prompt, starts network work,
  or automatically spends a generation request. A 44pt “换一种可能” action feeds
  the same reducer for Simulator, Reduce Motion, VoiceOver, expired listening,
  or unavailable responder delivery.
- “显影这一可能” is the only action that starts branch generation. It reuses the
  original captured JPEG, the completed frame's exact target, the same Beat ID,
  `exactTarget`, and complete render plan; only the evidence-backed narrative and
  visual directive vary. One-level undo restores the previous generated frame.
- Branch selection uses stable identifiers and opacity-only reduced motion. No
  looping shake prompt, random seed shuffle, prediction probability, certainty
  score, history library, or editing destination is introduced.

## Device tilt (decorative 2.5D)

- CoreMotion publishes clamped normalized attitude on the main actor at roughly
  20–30 Hz while eligible connection, result, or share screens are visible.
- It is inactive for Reduce Motion, Low Power Mode, and background/disappear.
- It offsets only decorative flat planes by roughly 1.5 / 3 / 5 points in
  opposing directions. Camera preview, grid, waveform, shutter, headlines,
  body copy, CTAs, export output, narrative lens, and temporal photo never move.
- It may rotate one rigid share-poster decoration by at most 0.75 degrees.

## 首屏 / 相机动效

### Connection aperture

- Wordmark and aperture button are static on first appearance. There is no
  entrance translation, stagger, scale reveal, parallax, or idle breathing.
- RootView owns the camera-entry lens track so it survives the phase swap: eight
  blades begin beyond the screen diagonal, close in 340ms, swap the phase only
  while fully sealed, then reopen from the aperture button's center. Only this
  narrative lens may make the track's brief spatial-print perspective pass.
- Repeated taps are ignored while the iris is active. Cancellation resets the
  overlay. Reduce Motion bypasses blade geometry and uses the phase crossfade.

### Viewfinder shutter

- The live preview and captured still resolve through the same
  `CameraCompositionGeometry` frame. RootView mounts the still at that exact
  full-width, top-anchored slot before it begins the temporal-photo lift.
- Add a restrained paper-white flash wash (`PosterEffects.cameraFlashWash`) on
  shutter press (Micro duration); AppModel plays `.shutter` before camera capture
  starts so the physical response is immediate.
- RootView owns temporal-exposure geometry; `AppModel` owns interpretation-reveal
  progress, while `BlowRevealModel` publishes only normalized gust/progress from
  aggregate microphone levels. The matched temporal photo renders those values.
  The live chrome's capture afterimage uses the
  same two buttons, wave-shutter position, aspect frame, and blue body; it fades
  before the photo settles rather than swapping to unrelated legacy controls.
- Live chrome and its capture afterimage resolve the same active-window safe
  area insets. A full-bleed GeometryReader's zero inset must never drive the
  departure frame, or controls will jump toward the Dynamic Island and home
  indicator on shutter.
- The resting viewfinder card has no shadow. Paper depth and shadow begin at zero
  and grow only after shutter capture turns the flat preview into a lifted photo.
- Simulator preview and mock JPEG capture share one fixed 3:4 SwiftUI scene
  master. Aspect changes crop that master; `ImageRenderer` raises only its pixel
  density, never its logical-point layout, so preview and frozen still align.
- Camera chrome uses `PosterPressStyle` press scale only — no looping motion.
- In the clear composition area, a two-finger pinch changes only the framing
  ratio: closing moves toward 16:9 then full frame; opening moves toward 1:1.
  Each crossed ratio morphs the composition frame immediately and can be
  interrupted by reversing the pinch. The gesture does not scale the preview.
  The ratio capsule appears inside the card during the gesture, remains readable
  for about 0.9s after release, and cancels that dismissal if a new pinch begins.
  The gesture surface must live in the top-most camera chrome layer so real
  touches are not intercepted by that overlay. VoiceOver exposes the same
  control as an adjustable “取景画幅” element.
- The viewfinder does not imitate the Dynamic Island in app chrome. Its two
  44pt camera buttons remain ordinary in-app controls. The right button starts
  the existing ActivityKit Live Activity; the WidgetKit `DynamicIsland`
  configuration owns compact, minimal, and expanded content. iOS owns the
  cutout geometry, placement, interaction, and system animation curve.

## Camera transitions and haptics

- Pow 1.0.6 is limited to the three spatial-print tracks: lens aperture on camera
  entry, temporal exposure across capture, and interpretation reveal as the result
  develops. Only the narrative lens or temporal photo gains transient perspective;
  Reduce Motion replaces all three with opacity.
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

## Motion acceptance checks

- Exercise camera entry, capture, and generated-result reveal. Confirm only the
  narrative lens or temporal photo receives transient perspective, and each ends
  flat with no residual transform, shadow depth, or idle motion.
- Exercise a real two-finger pinch through `XCUIElement.pinch` and confirm the
  aspect label changes without directly mutating app state.
- Confirm time anchoring is advisory, the micro time slice is optional, and the
  pipeline succeeds when functional motion is unavailable.
- On a physical iPhone, confirm sustained blow strength advances one continuous
  reveal and silence releases the gust. Confirm microphone denial and “直接显影”
  complete the same progress without blocking the generated result.
- During all three tracks, confirm controls, text, shutter, camera grid/chrome,
  numeric date, and WaveTimeRail do not translate, rotate, scale, or change
  layout. The rail remains continuous and interruptible while scrubbing.
- Confirm no spatial-print track runs on an idle, backgrounded, or disappeared
  view; existing decorative device-motion behavior remains bounded by its
  Reduce Motion, Low Power Mode, and scene-activity gates.
- With Reduce Motion enabled, confirm each of the three tracks uses only the
  `Reduced` opacity crossfade and does not apply perspective, rotation, scale, or
  geometry travel.
