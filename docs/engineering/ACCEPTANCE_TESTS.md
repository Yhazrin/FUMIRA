# Acceptance Tests

## Functional

- Launch → phone-only → camera → capture → understanding → story → approval →
  generation → result.
- Physical iPhone requests real camera permission and shows the rear-camera preview.
- Denial returns readable recovery copy instead of opening a blank viewfinder.
- The camera session stops after capture and resumes on retake.
- Simulator explicitly labels and uses the deterministic preview fallback.
- Captured data is a decodable JPEG and remains the visual source through story approval.
- Image understanding produces a summary, subjects, clues, drivers, and identity rules.
- Story changes between past, NOW and future and has anchors at -100 and +100 years.
- Generation cannot begin before the story review gate.
- Generated prompts include story context, subject continuity and original composition.
- The model background persists only runnable route IDs and disables backend-only routes.
- Hardware path shows connection feedback and reaches the same viewfinder.
- Dragging reaches exactly -100 and +100 years with no snapping.
- Equal rail movement changes less time near NOW than near either endpoint.
- Rapid direction changes never show a stale selected date.
- Save opens the poster/share preview; return preserves the selected time.
- Each pipeline failure exposes stage-specific recovery and preserves prior output.

## Visual

- Compare key screens against Figma nodes 116:8, 116:145, 116:237, 116:328, 116:631, 116:669.
- Preserve flat large color blocks, handmade typography, illustrated park, black capsules, and lime energy marks.
- Check compact and large iPhone simulators; no clipped controls or status-bar collisions.

## Accessibility

- Every control has a VoiceOver label/value/hint.
- Time rail supports adjustable actions in addition to drag.
- All targets are at least 44pt.
- Reduce Motion uses a 150ms crossfade and removes geometry travel.
- Large accessibility text retains the core flow.

## Commands

Run:

```sh
xcodegen generate
xcodebuild -project FUMIRA.xcodeproj -scheme FUMIRA \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Also build the physical-device code path without signing:

```sh
xcodebuild -project FUMIRA.xcodeproj -scheme FUMIRA \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```
