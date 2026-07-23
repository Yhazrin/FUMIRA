# Remote Image Understanding — TODO

Status: **not implemented for production runtime**.

## Why this exists

FUMIRA’s narrative pipeline still uses `MockImageUnderstandingProvider` on device.
Image generation can already go through the FUMIRA Fastify backend → MiniMax
`image-01` I2I. Image understanding does **not** have a verified public MiniMax
HTTP endpoint in `MINIMAX_API_GUIDE.md`.

Development-only verification may use the MiniMax MCP tool
(`understand_image` / equivalent). That MCP server is **not** a production
dependency and must not be called from the iOS app or the demo backend at
runtime.

## Protocol already in tree

- `ImageUnderstandingProvider` — existing stream contract
- `RemoteUnderstandingProvider` — marker protocol + `UnimplementedRemoteUnderstandingProvider`
  stub that fails closed

## When to implement

Implement only after FUMIRA backend publishes a stable understanding route, for
example the contract already sketched in `AI_PIPELINE_API.md`:

`POST /v1/understand` (multipart photo + session_id + route_id)

Then:

1. Add a real `FUMIRARemoteUnderstandingProvider` that talks to **FUMIRA**, not
   MiniMax directly.
2. Wire it in `AppDependencies` behind the same `FUMIRA_API_BASE_URL` (or a
   dedicated readiness flag from `/health`).
3. Keep the mock provider as the default when the backend route is unavailable.
4. Never ship `MINIMAX_API_KEY` to iOS.

## Explicit non-goals

- Do not invent a MiniMax HTTP understanding URL.
- Do not call MCP tools from the server request path.
- Do not block the MVP demo on understanding parity with generation.
