# MVP Specification

## Outcome

The user chooses a target time while framing, captures a scene, and immediately
sends the source photo to generate that exact past/future view. FUMIRA keeps the
result sealed while it understands the generated target frame and writes a story
spanning the same place from 100 years in the past to 100 years in the future,
then reveals the image and story together.

## In scope

- Figma-derived connection, viewfinder, understanding, story, generation, result,
  failure, model settings, and share states
- Fully interactive mock flow
- Valid JPEG capture data visible throughout the pipeline
- Real rear-camera permission, live full-screen preview and photo capture on iPhone
- Automatic interactive scene fallback when running in Simulator
- Structured scene subjects, identity rules, clues, and change drivers
- Target-photo-first pipeline with no pre-generation understanding/story gate
- Source-photo prompt preserving composition and subject identity at the exact time
- Generated-target image understanding followed by seven narrative beats
- Model route catalog with runnable and backend-required availability states
- Continuous nonlinear time adjustment, not five fixed anchors
- Interruptible SwiftUI motion and haptics
- Accessibility labels, Dynamic Type, and Reduce Motion behavior
- Unit tests for time mapping, generation-first ordering, generated-image analysis,
  story variation, route validity, exact-time prompts, state transitions, and
  failure preservation

## Not in scope

- Production BLE, hosted AI backend, accounts,
  history, video, AR, social graph, or editing tools. Those production integrations
  have executable protocol/API contracts but no credentials or server deployment
  are bundled in the app. Poster save/share is in-scope as pure software
  (PhotoKit add-only + system share sheet).

## Product rule for time

The range is exactly ±100 years. Control is continuous. Fine movements near NOW
must produce much smaller time changes than the same movement near an endpoint.
Landmark ticks are orientation aids only and never snapping targets.
