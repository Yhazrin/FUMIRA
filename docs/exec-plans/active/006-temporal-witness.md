# Temporal Witness — Hackathon Innovation Pass

Status: active.

## Goal

Make FUMIRA memorable for more than changing the apparent age of a photograph.
The product should preserve one camera viewpoint, expose the interpretation that
connects NOW to another time, and compress that explanation into a poster that
can be carried away:

`one scene → one continuous time vector → visible change logic → one time artifact`

This pass stays inside the MVP. It does not add accounts, history, video, AR,
social features, or editing tools.

## Product differentiation

FUMIRA is not an era filter and does not present generated output as a factual
prediction or historical reconstruction. It is a **time witness**: a structured,
explicitly hypothetical interpretation of how the same framed reality could
change while recognizable subjects, composition, and spatial relationships stay
continuous.

The distinction is visible in three layers:

1. **Observed** — source-photo scene, optical context, salient subject, and other
   evidence actually captured or derived locally.
2. **Interpreted** — story change drivers, turning points, and identity rules.
3. **Imagined** — the generated target frame, labeled as one possible reading of
   the selected time.

The UI must not invent confidence percentages, scientific certainty, or proof
that cannot be supported by those existing structures.

## P0 generation contract

The existing ability to generate the image for the user's exact selected time is
more important than every feature in this plan.

- Capture freezes `selectedTime` into `capturedTargetTime`.
- Story writing must produce an exact target beat for that same offset.
- `ImageGenerationRequest.time`, the remote `timePosition.offsetDays`, the
  server-authoritative `exactTarget`, and the completed `GeneratedFrame.time`
  must remain the same value.
- Exact identity uses `TimePosition.hasSameExactTimeIdentity`: only a one-second
  floating-point / serialization tolerance is allowed. UI labels, NOW bands,
  and detent thresholds must never substitute for generation identity.
- Browsing after a result may change narrative context, but cannot silently
  relabel the existing generated image.
- Explicit “生成这一帧” first obtains a fresh exact target beat, then sends a new
  generation request and returns a new valid image for the browsed time.
- Temporal witness and fingerprint code is read-only. It may never mutate time,
  trigger generation, or participate in request construction.

Any failure in this contract blocks innovation integration.

## Experience contract

### 1. Temporal interpretation trace

- Derive a deterministic trace from `TemporalStory`, `StoryBeat`,
  `SceneUnderstanding`, and the current `TimePosition`.
- A matching exact-target beat explains an already generated frame; otherwise
  the nearest canonical beat explains the current browse position without
  snapping or mutating the continuous rail.
- Prefer a beat's explicit transition cause and unchanged anchors. Fall back to
  scene change drivers and story identity rules only when those fields are absent.
- Canonical beats and an optional distinct exact-target beat become bounded,
  monotonically ordered markers in the same nonlinear normalized time space as
  `WaveTimeRail`.
- User-facing language says “一种可能的…” and “解释线索”; it never says prediction,
  restoration, verification, or certainty.

### 2. Time-witness ribbon

- A non-interactive ribbon visualizes story turning points and the live selected
  time without becoming a second time control.
- Markers are orientation and explanation aids only. They are never snap targets.
- The active interpretation shows at most one concise change trace and up to
  three continuity anchors.
- Flat ink, line, and action-blue tokens only. No glass, glow, gradient, particle,
  random animation, or idle motion.
- Reduce Motion uses a 150 ms opacity-only content change.

### 3. Deterministic time fingerprint

- Each result can carry a 21-stroke vector fingerprint derived only from story
  marker positions and the selected time.
- The mark is reproducible for the same trace and contains a compact legend. It
  is not a score or decorative random waveform.
- The fingerprint is reused on the result interpretation layer and the exported
  poster so the on-screen encounter and the saved artifact share one identity.

### 4. Reality comparison remains the primary proof moment

- Preserve the existing source/generated draggable comparison in one common
  crop and viewpoint.
- The comparison remains a still-image interaction. Do not expand it into video.
- Temporal interpretation context should clarify what the user is seeing without
  covering the image or adding another full-screen destination.

### 5. Time darkroom turns waiting into a physical ritual

- During the existing understanding → story → generation stage, covering the
  iPhone's top proximity sensor accumulates one bounded darkroom exposure. The
  app never starts a second camera session or claims that this exposure is model
  progress.
- Exposure is optional ceremony, never a generation gate. The network/mock
  pipeline continues while the sensor is far, unavailable, cancelled, or the app
  is backgrounded; a completed result always remains reachable.
- The live implementation uses only the public `UIDevice` proximity contract and
  enables monitoring only while a developing phase is foregrounded. Simulator,
  unsupported hardware, VoiceOver, and Reduce Motion receive an explicit 44 pt
  press-and-hold exposure path with the same copy and completion meaning.
- Near/far samples feed a deterministic pure state reducer. Continuous progress
  derives from elapsed monotonic time, clamps to `0...1`, ignores duplicate and
  non-finite timestamps, and never launches work from a SwiftUI `body` pass.
- While fallback press is held, one flat Ink shutter may cover the existing
  persistent print. Releasing it reveals the same captured object; no duplicate
  image card, gradient, idle animation, looping ornament, fake percentage, or
  separate darkroom destination is introduced.
- Completion may emit one native haptic and the quiet instruction “移开手掌，等
  时间回来”. It must not emit haptics on every sensor sample.

### 6. Future forks make possibility physically legible

- Resolve two or three deterministic future interpretations only from existing
  Scene Bible evidence. Every branch carries stable identity, observed evidence,
  a hypothetical rationale, and an explicit non-prediction contract.
- Shaking the iPhone or using its 44pt fallback changes only the highlighted
  branch. It cannot mutate the selected/captured target or automatically start
  generation.
- Explicit “显影这一可能” regenerates from the original capture at the completed
  frame's exact target. The fork may append a bounded narrative and visual
  directive, but must preserve the Beat ID, `exactTarget`, complete render plan,
  camera locks, identity constraints, and prohibited drift.
- No future fork is shown for past/NOW, mismatched browsing, fewer than two
  grounded branches, or invalid target data. Sparse evidence degrades quietly
  instead of inventing alternatives.

## Visual repair contract

Innovation does not excuse inconsistency. In parallel with the witness work:

- Keep the persistent `HeroPhotoSurface`, spatial print, shutter-wave morph,
  reflection back, temporal slit, time door, and comparison interaction.
- Remove decorative glass from ordinary camera and reading chrome where the
  Design System requires opaque semantic surfaces.
- Restore every reflection option and save action to at least a 44 pt target.
- Ensure VoiceOver can change WaveTimeRail granularity through named actions,
  because vertical drag is not available to an adjustable control user.
- Do not hide interactive reflection content by applying
  `accessibilityHidden(true)` to an ancestor hero card.

## Parallel implementation batches

### Batch A — domain trace

Owned files:

- `FUMIRA/Domain/TemporalInterpretationTrace.swift`
- `FUMIRATests/TemporalInterpretationTraceTests.swift`

### Batch B — reusable visual language

Owned files:

- `FUMIRA/DesignSystem/Components/TemporalWitnessRibbon.swift`
- `FUMIRA/DesignSystem/Components/TemporalFingerprintMark.swift`

### Batch C — result and poster integration

Expected files:

- `FUMIRA/Features/Result/ResultView.swift`
- `FUMIRA/Features/Share/SharePosterView.swift`
- `FUMIRA/DesignSystem/Components/PosterExportCard.swift`
- `FUMIRA/Services/Storage/PosterComposer.swift`
- `FUMIRA/App/AppModel.swift`
- focused poster/result tests

### Batch D — contract and accessibility repair

Expected files are limited to the affected components and focused tests. Avoid
public service, dependency-wiring, or state-machine changes.

### Batch E — native time-language interaction

Expected files:

- protocol-backed proximity service with live/mock implementations;
- a main-actor darkroom model and deterministic exposure reducer;
- one reusable flat SwiftUI darkroom control;
- `AppDependencies`, `AppModel`, `RootView`, and `RealityDevelopingView` lifecycle
  integration;
- focused reducer, service/model lifecycle, and developing-stage UI tests.

The existing exact-time generation contract remains P0. Batch E may observe the
pipeline but cannot change request construction, selected/captured time, phase
completion, retry semantics, or generated-frame validation.

### Batch F — structured future forks

Expected files:

- a deterministic Scene Bible → future-fork Domain engine;
- UIKit responder-based shake service, reducer, model, and mock;
- one flat result-page fork selector with explicit generation confirmation;
- exact-target AppModel integration and generated-frame provenance;
- focused engine, service/model, component, AppModel, and result UI tests.

Batch F must reuse generation.v3's existing exact target and render-plan schema.
It may not add a random-seed endpoint, silently generate on shake, use a generated
result as the next source image, or turn branch exploration into a history/editing
feature.

## Evidence and inspiration

The implementation borrows principles rather than appearances:

- [Time-Travel Rephotography](https://time-travel-rephotography.github.io/):
  change time while protecting recognizable identity and pose.
- [DateLens](https://faculty.cc.gatech.edu/~stasko/7450/Papers/bederson-tochi04.pdf):
  keep local temporal detail and global context visible together.
- [Scene Chronology](https://www.cs.cornell.edu/~snavely/publications/matzen_eccv2014.pdf):
  organize time around object changes rather than evenly spaced dates.
- [Time-lapse Mining from Internet Photos](https://grail.cs.washington.edu/projects/timelapse/):
  make change legible by comparing aligned viewpoints.
- [Dear Data](https://www.dear-data.com/theproject): turn structured personal
  observations into a portable visual artifact with a readable legend.

## Verification strategy

Full build/test cycles happen only at integration boundaries.

1. During parallel batches: `git diff --check`, token scans, pure-model focused
   tests, and isolated previews where possible.
2. After Batch C integration: focused domain, poster, time-rail, result reveal,
   and developing tests.
3. Runtime acceptance: simulator screenshots and interaction checks for result,
   comparison, share poster, Reduce Motion, accessibility type, and compact/large
   iPhone geometry.
4. Final gate: one simulator build/test pass, Swift 6 concurrency diagnostics,
   Feature-layer raw-token scan, and one generic `iphoneos` SDK build.

## Acceptance

- The result identifies itself as one possible interpretation, not a prediction.
- A user can see the current change trace and what remains continuous while
  browsing without the rail snapping to story beats.
- Trace markers are deterministic, ordered, and bounded to `-1...1`.
- The same deterministic fingerprint appears in result/share contexts and in the
  rendered PNG.
- Empty or partial story data degrades to a quiet narrative without blank cards,
  fabricated evidence, or crashes.
- Reduce Motion, Dynamic Type, VoiceOver, and 44 pt controls remain usable.
- Existing persistent-photo continuity, spatial-print tracks, and comparison
  interaction remain recognizable.
- Proximity monitoring is active only in foreground developing phases and is
  disabled on result, cancellation, background, retake, and disappearance.
- Covering the real sensor and pressing the fallback both accumulate the same
  deterministic exposure; neither can delay or fail image generation.
- Unsupported hardware and Reduce Motion expose a complete non-sensor path, and
  darkroom controls remain at least 44 pt at accessibility text sizes.
- Rich future evidence produces stable, bounded branches; shake and fallback
  advance the same selection without changing the displayed exact time.
- Confirmed branch generation starts from the original capture and preserves
  Beat identity, exact target, and the full machine render plan. Mismatched
  branch targets submit no generation request.
- Relevant focused tests pass before the final integrated build/test gate.
