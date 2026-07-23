# FUMIRA — 时间相机

FUMIRA is a narrative time-camera SwiftUI MVP inspired by the supplied Future
Camera Figma prototype. It captures a valid photo, understands its subjects and
change clues, writes a continuous past/future story, and generates a selected
time-world while preserving the original composition.

## Run

```sh
xcodegen generate
xcodebuild -project FUMIRA.xcodeproj -scheme FUMIRA -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

On a physical iPhone the runtime uses the rear wide camera, a full-screen live
preview, the system permission dialog, and high-quality JPEG capture. Simulator
builds automatically use the deterministic scene fallback. AI remains on the
local demo routes unless a backend catalog enables another provider.

See `ARCHITECTURE.md`, `docs/engineering/AI_PIPELINE_API.md`, and
`docs/engineering/ACCEPTANCE_TESTS.md` for the executable contract.
