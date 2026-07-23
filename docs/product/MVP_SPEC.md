# MVP Specification

## Outcome

The user can capture a scene, see what AI understood, review a story spanning the
same place from 100 years in the past to 100 years in the future, choose a target
time, generate a story-aware transformation, and open a poster-ready share screen.

## In scope

- Figma-derived connection, viewfinder, understanding, story, generation, result,
  failure, model settings, and share states
- Fully interactive mock flow
- Valid JPEG capture data visible throughout the pipeline
- Real rear-camera permission, live full-screen preview and photo capture on iPhone
- Automatic interactive scene fallback when running in Simulator
- Structured scene subjects, identity rules, clues, and change drivers
- Seven narrative beats with a user-visible story review gate
- Story-aware image prompt preserving original composition and subject identity
- Model route catalog with runnable and backend-required availability states
- Continuous nonlinear time adjustment, not five fixed anchors
- Interruptible SwiftUI motion and haptics
- Accessibility labels, Dynamic Type, and Reduce Motion behavior
- Unit tests for time mapping, pipeline ordering, story variation, route validity,
  identity-aware prompts, state transitions, and failure preservation

## Not in scope

- Production BLE, hosted AI backend, PhotoKit write, accounts,
  history, video, AR, social graph, or editing tools. Those production integrations
  have executable protocol/API contracts but no credentials or server deployment
  are bundled in the app.

## Product rule for time

The range is exactly ±100 years. Control is continuous. Fine movements near NOW
must produce much smaller time changes than the same movement near an endpoint.
Landmark ticks are orientation aids only and never snapping targets.
