# FUMIRA Agent Guide

## Mission

Build the smallest reliable SwiftUI time-camera MVP that delivers:

capture or import → generate a temporal interpretation → browse continuously from -100 to +100 years → save/share a poster.

Do not add accounts, a history library, video, AR, social features, or editing tools.

## Sources of truth

1. `docs/product/MVP_SPEC.md`
2. `docs/design/FIGMA_HANDOFF.md`
3. `docs/design/DESIGN_SYSTEM.md`
4. `docs/design/MOTION_SPEC.md`
5. `ARCHITECTURE.md`
6. The active plan under `docs/exec-plans/active/`

## Architecture

- Swift 6, SwiftUI, Observation, Swift Concurrency
- iOS 17 minimum; newer APIs need availability fallbacks
- One Xcode project and one app target
- Protocol-backed Camera, Hardware, Generation, Storage, and Haptics services
- Real and mock implementations; the MVP runs entirely with mocks
- No TCA, RxSwift, global singletons, or DI framework

## Ownership

Codex owns architecture, public protocols, dependency wiring, state machine,
project configuration, integration, and acceptance.

Cursor tasks may modify only files explicitly listed in the task contract.
Cursor must stop and report if architecture changes are required.

## Design constraints

- Preserve the Figma flat poster identity; no blue-purple AI gradients.
- Use DesignSystem tokens for product color, spacing, radius, shadows, and motion.
- Paper, Time Blue, Park Green, Energy Lime, and Ink are the core palette.
- Display lettering uses the approved poster fonts when bundled; functional text uses the system font.
- Photo/scene content remains the visual hero.
- Energy Lime is an accent, not a full-screen background.
- The time control is continuous and bounded to ±100 years. It never snaps to five anchors.
- The mapping is nonlinear: finer around NOW and increasingly coarse toward the ends.
- Support Reduce Motion, Dynamic Type, VoiceOver, and 44pt minimum targets.

## Mandatory checks

Before completing any task:

1. Build the app.
2. Run relevant tests.
3. Check Swift concurrency diagnostics.
4. Confirm Feature code did not introduce raw product token values.
5. Report changed files, commands, results, and remaining risk.

## Commands

Generate the project:

`xcodegen generate`

Build:

`xcodebuild -project FUMIRA.xcodeproj -scheme FUMIRA -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Test with an available simulator:

`xcodebuild -project FUMIRA.xcodeproj -scheme FUMIRA -destination 'platform=iOS Simulator,name=<resolved device>' CODE_SIGNING_ALLOWED=NO test`
