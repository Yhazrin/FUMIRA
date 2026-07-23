# FUMIRA — 时间相机

FUMIRA is a narrative time-camera SwiftUI MVP inspired by the supplied Future
Camera Figma prototype. It captures a valid photo, understands its subjects and
change clues, writes a continuous past/future story, and generates a selected
time-world while preserving the original composition.

## Run (iOS Mock — default)

```sh
xcodegen generate
xcodebuild -project FUMIRA.xcodeproj -scheme FUMIRA -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Without `FUMIRA_API_BASE_URL`, the app stays on local demo AI routes (Mock
understanding / story / generation). Simulator builds use the deterministic
camera fallback; physical devices use the live rear camera.

## Run (remote MiniMax I2I demo)

1. Start the FUMIRA backend (API key never enters the iOS target):

```sh
cd server
cp .env.example .env
# Either:
#   MINIMAX_MOCK=true
# or a real:
#   MINIMAX_API_KEY=...
#   MINIMAX_MOCK=false
# Also set ADMIN_TOKEN=...
# Local outbound proxy for MiniMax (port 7990):
#   HTTPS_PROXY=http://127.0.0.1:7990
#   HTTP_PROXY=http://127.0.0.1:7990
npm install
npm run dev
```

2. Point the app at the backend (scheme env, or Info.plist `FUMIRA_API_BASE_URL`):

```text
FUMIRA_API_BASE_URL=http://127.0.0.1:8787
```

On a physical device use your Mac’s LAN IP instead of `127.0.0.1`. Local HTTP is
allowed via `NSAllowsLocalNetworking`.

Flow: capture → (mock) understand/story → upload JPEG → queue MiniMax
`image-01` I2I → poll → show generated JPEG on the result screen.

Admin (Bearer `ADMIN_TOKEN`):

```sh
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://127.0.0.1:8787/v1/admin/generations
```

## Docs

- `ARCHITECTURE.md` — module boundaries and remote generation trust boundary
- `docs/engineering/AI_PIPELINE_API.md` — hosted transport contract
- `docs/engineering/ACCEPTANCE_TESTS.md` — acceptance checklist
- `docs/engineering/REMOTE_UNDERSTANDING_TODO.md` — understanding stays mock
- `server/README.md` — backend endpoints and env vars

## 首屏 / 相机视觉

- **Connection** is a paper poster: centered `PosterKeywordHero` (ink / pine /
  moss + hand underline), sky–grass layers, park vignette. Invite copy:
  「给时间，一张照片」/「把此刻，留给未来」. No settings gear on first screen.
- **Viewfinder** is immersive: full-bleed preview, top/bottom scrims only (no
  large white control card). Top = flash when supported + `NOW · year` chip;
  bottom = `WaveTimeRail` + centered shutter + flip (when live) + grid. Shutter
  uses paper fill with moss accent ring — never a solid yellow / energyLime button.
- Palette: paper · sky · grassLight · pine · moss · ink (`energyLime` → moss).
- Generation / result lettering:「时间正在生长」/「未来的回信」.

## Settings information architecture

- User-visible chrome is always labeled **设置**, never “模型后台”.
- The connection (first) screen has **no** settings entry.
- Immersive camera / pipeline phases hide the global settings control; a
  low-disruption gear appears only on non-immersive phases (e.g. camera
  permission, story ready, result, failure recovery).
- Viewfinder never hosts Settings. Flip/flash appear only when
  `CameraControlProviding` reports support; grid always works (simulator too).
- Model routing lives under **设置 → 高级 → 模型路由** for development and
  configuration recovery — not as a primary product entry.
