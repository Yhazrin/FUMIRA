# Acceptance Tests

## Functional

- Launch → phone-only → camera → capture → understanding → story → approval →
  generation → result.
- Viewfinder album import (PhotosPicker) enters the same understanding → story →
  generation pipeline as shutter capture; simulator-safe; silent center-crop to 3:4
  JPEG with no crop editor.
- Result「重新生成」re-runs image generation with the same source photo and current
  time position, replacing the current frame; optional one-level in-memory「撤销」
  restores the previous frame (not a history library).
- Physical iPhone requests real camera permission and shows the rear-camera preview.
- Denial returns readable recovery copy instead of opening a blank viewfinder.
- The camera session stops after capture and resumes on retake.
- Simulator explicitly labels and uses the deterministic preview fallback.
- Captured data is a decodable JPEG and remains the visual source through story approval.
- Image understanding produces a summary, subjects, clues, drivers, and identity rules.
- Story changes between past, NOW and future and has anchors at -100 and +100 years.
- Generation cannot begin before the story review gate.
- Generated prompts include story context, subject continuity and original composition.
- The model catalog persists only runnable route IDs and disables backend-only routes.
- Settings chrome is labeled “设置”; no user-visible “模型后台” copy.
- Connection has no settings entry; immersive camera/pipeline phases hide the
  global settings control.
- Settings → 高级 → 模型路由 holds developer/advanced model routing; ordinary
  capture flow does not surface it as a primary entry.
- Viewfinder top-leading controls are limited to live-supported actions: camera
  flip and flash appear only when `LiveCameraService` reports capability, plus a
  working composition grid toggle (simulator included). Unsupported actions are
  omitted — never shown as disabled dead buttons.
- Hardware path shows connection feedback and reaches the same viewfinder.
- Dragging reaches exactly -100 and +100 years; release may snap to date
  granularity (day/week/month/year) but never to landmark anchors.
- Equal rail movement changes less time near NOW than near either endpoint.
- WaveTimeRail shows a leafGreen active capsule/cursor with year above; ordinary
  bars stay low-contrast, symmetric around the midline, and float without a white card.
- Rapid direction changes never show a stale selected date.
- Save opens the poster/share preview; return preserves the selected time.
- Share screen composites a flat poster PNG (result JPEG when present, else park
  scene + story copy) via `PosterComposer` / DesignSystem tokens — no AI gradients.
- **保存到相册** writes through `PosterStorage` (`PhotoLibraryPosterStorage` at
  runtime, `MockPosterStorage` in tests) and shows success / permission failure copy.
- **分享海报** presents the system share sheet (`ShareLink` + PNG `Transferable`).
- Minimal deep link: `fumira://share` / `fumira://result` when story/result exists.
  Richer share URLs remain a product TODO (no invented backend).
- Each pipeline failure exposes stage-specific recovery and preserves prior output.
- Without `FUMIRA_API_BASE_URL` (typical Release / Archive), generation stays on `MockGenerationProvider`.
- Debug builds default to `http://127.0.0.1:8787` → `RemoteGenerationProvider` when the local server is up.
- With `FUMIRA_API_BASE_URL` set (Info.plist / scheme env), generation uploads → polls → shows remote JPEG bytes.
- Remote failures map to distinct copy: network / upload / invalid params / rate limit /
  generation failure / server unavailable.

## Backend demo

- `POST /health` reports `generation.ready=false` and `mode=unavailable` when no
  adapter is attached, without leaking key configuration.
- Uploads reject >10MB and invalid JPEG magic bytes.
- Mock MiniMax adapter completes I2I; `2013` → non-retryable `invalid_params`;
  timeout → retryable.
- Admin list requires `ADMIN_TOKEN` and never returns secrets, base64, or full prompts.

## Visual

- Compare key screens against Figma nodes 116:8, 116:145, 116:237, 116:328, 116:631, 116:669.
- Preserve flat large color blocks, handmade typography, illustrated park, pine
  capsules, and leafGreen accent marks (≤5% — never fluorescent full-bleed fills).
- Check compact and large iPhone simulators; no clipped controls or status-bar collisions.
- When `GeneratedFrame.imageData` is present, the result screen shows that image
  instead of the local park mock.

### 首屏 / 相机视觉

- Connection reads as a full-screen flat poster: centered keyword hero
  (ink/pine/leafGreen + hand underline), `ParkPosterBackdrop`, no settings gear /
  「模型后台」. Supporting copy does not repeat the hero headline.
- Copy invites with「给时间，一张照片」; generation uses
  「时间正在生长」; result uses「未来的回信」.
- Viewfinder has no bottom white control card; preview is full-bleed with
  top/bottom scrims only.
- Viewfinder shows `WaveTimeRail` on the bottom scrim, centered shutter, circular
  album import / grid chrome (flip moves to top with flash when live-capable);
  time chip is minimal (`NOW · year`), not a slogan block.
- Feature code has no raw `Color(red:)` product tokens.

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

Server:

```sh
cd server && npm install && npm test
```

Also build the physical-device code path without signing:

```sh
xcodebuild -project FUMIRA.xcodeproj -scheme FUMIRA \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Real MiniMax key verification

When `MINIMAX_API_KEY` is available:

1. Set `MINIMAX_MOCK=false` in `server/.env`.
2. `npm run dev`, upload a real JPEG via `POST /v1/uploads`, create a generation,
   poll until `succeeded`, open `resultUrl`.
3. Run the iOS app with `FUMIRA_API_BASE_URL` pointing at the server and confirm
   the result screen shows the downloaded image.

Without a key, `MINIMAX_MOCK=true` plus `npm test` covers the same control flow.