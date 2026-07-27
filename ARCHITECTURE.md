# Architecture

## Decision

FUMIRA is a modular monolith in one Xcode project. The main app remains one
application target, with one narrowly scoped WidgetKit extension for the camera
Live Activity and Dynamic Island presentation. Shared `ActivityAttributes` are
compiled into both targets; camera behavior remains owned by the app and is
reached from the system surface through FUMIRA deep links. Minimum deployment is
iOS 17 so Observation and modern Swift concurrency are available.

A sibling **FUMIRA backend** lives under `server/` (TypeScript + Fastify). It is
the only process allowed to hold `MINIMAX_API_KEY`. The iOS app never talks to
MiniMax directly.

## Dependency direction

```text
SwiftUI View
  → @Observable AppModel / local value state
  → service protocol
  → real or mock service
```

Feature views may know Domain and DesignSystem. They must not import or construct
AVCaptureSession, CBCentralManager, URLSession API clients, or persistence stores.
`RemoteGenerationProvider` is constructed only inside `AppDependencies`.

## State machine

```text
connection
  → bluetoothPermission → connected
  → cameraPermission → viewfinder
  → shuttered
  → generating
  → understanding
  → storyWriting
  → result
  → share
```

Phone-only mode enters camera permission directly. Failure, cancellation, retry,
disconnect, retake, and returning from share are explicit transitions rather than
parallel Boolean flags. The reveal is deliberately suspenseful: the captured
photo and locked target time go to image generation first. The generated target
frame is then analyzed and used to write the story; neither the frame nor its
analysis is shown until both downstream stages finish.

## Continuous time model

The rail stores a normalized position `p ∈ [-1, 1]` and maps it to days:

```text
offsetDays = sign(p) × 36,525 × |p|^2.35
```

This is reversible and monotonic. It yields precise control near NOW while still
reaching exactly ±100 Gregorian years at the rail endpoints. UI formatting may
show days, months, tenths of years, or whole years depending on magnitude, but the
underlying value remains continuous. Generation requests carry the full value and
a session ID so stale results cannot overwrite a newer scrub position.

## Services

- `CameraService`: real authorization, preview lifecycle and captured-photo boundary.
- `CameraPreviewFactory`: an opaque preview view so Features never construct or
  import `AVCaptureSession`.
- `CameraLiveActivityService`: ActivityKit lifecycle for the triggered system
  Dynamic Island camera deck. The WidgetKit extension renders only shared,
  bounded camera state and never owns the capture session.
- `HardwareController`: optional physical shutter/rotary controller boundary.
- `GenerationProvider`: source-photo + exact-target image generation and progress.
  - `MockGenerationProvider` (default)
  - `RemoteGenerationProvider` when `FUMIRA_API_BASE_URL` is set
- `ImageUnderstandingProvider`: analyzes the generated target frame, including
  subjects, composition, visible time clues, and bounded change drivers.
- `StoryProvider`: writes past/present/future beats anchored to the generated
  target frame and its exact selected time.
- `AIModelCatalogProvider`: backend-controlled route catalog.
- `AIModelConfigurationStore`: selected route IDs only; never vendor credentials.
- `PosterStorage`: rendering persistence boundary.
  - `MockPosterStorage` (tests / preview)
  - `PhotoLibraryPosterStorage` (runtime: temp PNG + Photos add-only)
- `HapticsClient`: feedback boundary with accessibility-aware implementation.

Every boundary has a deterministic mock. The camera boundary additionally has a
production `LiveCameraService`: physical-device runtime uses AVFoundation while
the simulator is selected at compile time for the safe scene fallback.

## Remote generation data flow

```text
iOS App                        FUMIRA server                     MiniMax
───────                        ─────────────                     ───────
capture JPEG
                               POST /v1/uploads  ──────────────► (store file)
exact target prompt            POST /v1/generations (202)
                                     │
                                     ▼
                               image-01 I2I  ──────────────────► /v1/image_generation
                                     │                           (API key server-side)
                               save JPEG + resultUrl
GET /v1/generations/:id  ◄──── poll status
download resultUrl       ◄──── GET /v1/results/:id.jpg
keep frame sealed
generated JPEG            POST /v1/uploads
generated asset           POST /v1/understand
target understanding      POST /v1/stories
reveal image + story
```

The relay owns live image generation, generated-image understanding, and story
writing credentials. The iOS app receives only bounded domain results.

## Model routing and trust boundary

The iOS client knows stable route IDs such as `openai.story.server`, not vendor
keys or hard-coded vendor model versions. A future FUMIRA backend returns the
catalog and maps each enabled route to an audited provider/model. Options marked
`requiresBackend` remain visible but disabled. A stored option that is no longer
ready is sanitized back to the runnable standard route.

`MINIMAX_API_KEY` and `ADMIN_TOKEN` exist only in the server environment.
`FUMIRA_API_BASE_URL` is the sole client switch for remote generation.

Live MiniMax HTTPS outbound uses undici `ProxyAgent` when
`HTTPS_PROXY` / `HTTP_PROXY` / `MINIMAX_HTTPS_PROXY` is set. The project local
proxy example is `http://127.0.0.1:7990`. Mock generation does not need a proxy.
## Motion

Shared geometry carries the lens/scene between major states. A single interruptible
timeline value drives the rail, scene palette, year label, and poster treatment.
Reduce Motion replaces spatial transforms with a 150ms opacity crossfade.

## Concurrency

`AppModel` is `@MainActor`. External implementations are `Sendable`; mock services
use actors where they own mutable state. Each capture or retry receives a fresh
UUID. Understanding, story and image events must match the active session before
they can update visible state. Retake, back and failure invalidate that session.
