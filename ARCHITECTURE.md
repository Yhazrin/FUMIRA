# Architecture

## Decision

FUMIRA is a modular monolith: one Xcode project, one app target, and folders that
enforce boundaries without introducing package overhead. Minimum deployment is
iOS 17 so Observation and modern Swift concurrency are available.

A sibling **demo backend** lives under `server/` (TypeScript + Fastify). It is
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
  → understanding
  → storyWriting
  → storyReady
  → generating
  → result
  → share
```

Phone-only mode enters camera permission directly. Failure, cancellation, retry,
disconnect, retake, and returning from share are explicit transitions rather than
parallel Boolean flags. The story is a review gate: image generation cannot start
until understanding and story writing have both produced domain results.

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
- `HardwareController`: optional physical shutter/rotary controller boundary.
- `ImageUnderstandingProvider`: subjects, composition, clues and change drivers.
- `StoryProvider`: past/present/future beats plus visual continuity rules.
- `GenerationProvider`: story-aware image generation request and progress events.
  - `MockGenerationProvider` (default)
  - `RemoteGenerationProvider` when `FUMIRA_API_BASE_URL` is set
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
Mock understand + story
                               POST /v1/uploads  ──────────────► (store file)
                               POST /v1/generations (202)
                                     │
                                     ▼
                               image-01 I2I  ──────────────────► /v1/image_generation
                                     │                           (API key server-side)
                               save JPEG + resultUrl
GET /v1/generations/:id  ◄──── poll status
download resultUrl       ◄──── GET /v1/results/:id.jpg
show GeneratedFrame.imageData
```

Understanding remains on `MockImageUnderstandingProvider`. A replaceable
`RemoteUnderstandingProvider` protocol exists with an explicit TODO — do not
invent MiniMax HTTP understanding endpoints; MCP is development-only.

## Model routing and trust boundary

The iOS client knows stable route IDs such as `openai.story.server`, not vendor
keys or hard-coded vendor model versions. A future FUMIRA backend returns the
catalog and maps each enabled route to an audited provider/model. Options marked
`requiresBackend` remain visible but disabled. A stored option that is no longer
ready is sanitized back to the runnable demo route.

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
