# Story-Aware Generation Contract

`GenerationProvider` accepts `ImageGenerationRequest`: the captured photo,
structured scene understanding, approved temporal story, continuous target time,
model route, and session UUID. It emits progress and a `GeneratedFrame` through an
async throwing stream.

Implementations:

- `MockGenerationProvider` — local deterministic progress (default)
- `RemoteGenerationProvider` — FUMIRA backend upload + poll when
  `FUMIRA_API_BASE_URL` is configured

The UI never knows MiniMax endpoints or vendor credentials. Cancellation and
session identity are mandatory so stale scrubs cannot overwrite the current result.

`GenerationError` distinguishes network, upload, invalid parameters, rate limit,
timeout, server unavailable, and generic generation failures for
`GenerationFailureView`.

The frame records the story beat ID, generation prompt, route ID, and optional
rendered image bytes. When `imageData` is present, `ResultView` displays it.
See `AI_PIPELINE_API.md` for the hosted transport.
