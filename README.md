# FUMIRA — 时间相机

FUMIRA is a narrative time-camera SwiftUI MVP inspired by the supplied Future
Camera Figma prototype. It captures a valid photo, understands its subjects and
change clues, writes a continuous past/future story, and generates a selected
time-world while preserving the original composition.

## Run (iOS)

```sh
xcodegen generate
xcodebuild -project FUMIRA.xcodeproj -scheme FUMIRA -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

**Debug** builds bake in `FUMIRA_API_BASE_URL=http://127.0.0.1:8787` so the app
talks to the local FUMIRA backend (`RemoteGenerationProvider`). **Release** /
Archive leave the URL empty → local Mock generation (safe default).

Understanding / story stay on Mock in MVP either way. Simulator uses the
deterministic camera fallback; physical devices use the live rear camera.

MiniMax is **not** packaged into the app. The key lives only in `server/.env`.
Packaging the iOS target never embeds vendor credentials — you run the backend
alongside the Debug app.

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

2. Run a **Debug** app build (simulator default already points at
   `http://127.0.0.1:8787`). Confirm remote mode:

```text
# In LLDB / a Debug breakpoint:
po FUMIRAAPIConfiguration.usesRemoteGeneration  // true
po FUMIRAAPIConfiguration.baseURL               // http://127.0.0.1:8787
```

Or watch the server terminal for `POST /v1/uploads` when generation starts.
If that never appears, the app is still on Mock (Release build, empty URL, or
unreachable host).

3. **Physical device:** `127.0.0.1` is the phone itself, not your Mac. Override
   via Xcode scheme → Run → Arguments → Environment Variables:

```text
FUMIRA_API_BASE_URL=http://<Mac-LAN-IP>:8787
```

Scheme env wins over the Info.plist Debug default. Mac and phone must be on the
same LAN; local HTTP is allowed via `NSAllowsLocalNetworking`.

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

- **Connection** is a full-screen flat poster: centered `PosterKeywordHero`
  (ink / pine / leafGreen + hand underline) over `ParkPosterBackdrop` shapes.
  Supporting copy explains hardware vs phone-only — it does not repeat the hero
  headline. No settings gear on first screen.
- **Viewfinder** is immersive: full-bleed preview, top/bottom scrims only (no
  large white control card). Top = flash when supported + `NOW · year` chip;
  bottom = `WaveTimeRail` + centered shutter + flip (when live) + grid. Shutter
  uses paper fill with leafGreen accent ring.
- Palette: paper · sky · grassLight · pine · leafGreen · ink.
- Generation / result lettering:「时间正在生长」/「未来的回信」.
- Decorative 2.5D parallax (connection / result / share only) moves flat
  background planes at 1.5 / 3 / 5 pt; camera, waveform, text, and CTAs stay fixed.

## 分享与保存

- Result → **保存海报** opens the share preview (`SharePosterView`).
- The app composites a flat poster PNG (`PosterComposer` + `PosterExportCard`):
  generated JPEG when available, otherwise the park scene, plus year / story copy.
- **保存到相册** uses `PhotoLibraryPosterStorage` (Photos add-only permission).
- **分享海报** uses system `ShareLink` with PNG `Transferable`.
- Deep link (minimal): `fumira://share` / `fumira://result` when a story exists.
  No cloud share backend in MVP.
- Tests / Preview keep `MockPosterStorage` for deterministic coverage.

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
