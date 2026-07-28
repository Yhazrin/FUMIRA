# Remote Image Understanding — Implemented

Status: **live** via MiniMax VLM (`/v1/coding_plan/vlm` endpoint).

## Current implementation

- `RemoteUnderstandingProvider` (iOS) → `POST /v1/understand` (server)
- Server delegates to `LiveMiniMaxIntelligenceAdapter.analyzeImage()` using the
  MiniMax VLM endpoint with `MINIMAX_VLM_API_KEY` (or falls back to `MINIMAX_API_KEY`)
- Includes prompt injection defense: text visible inside the image is flagged as
  untrusted scene content
- Copy constraints enforced server-side and on-device

## What changed from the original TODO

The original TODO said understanding was not implemented for production. Since then:

1. `POST /v1/understand` route is live and tested
2. `POST /v1/stories` route is live with `targetBeat` support
3. iOS `RemoteUnderstandingProvider` and `RemoteStoryProvider` are wired in `AppDependencies.runtime`
4. The intelligence adapter uses the MiniMax VLM endpoint for image analysis
5. PromptCompiler V3 generates the final prompt from SceneGraph + TemporalRenderPlan

## Architecture

```
iOS photo → upload → /v1/understand → /v1/stories → exact target plan → /v1/generations
                ↑           ↑              ↑               ↑                 ↑
           JPEG only    SceneGraph     M3 narrative   TemporalRenderPlan   PromptCompiler V3
```

No vendor credentials ever reach the iOS client.
