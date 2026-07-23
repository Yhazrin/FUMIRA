# AI Pipeline Backend Contract

This contract lets operations change concrete models without shipping a new iOS
binary. The app sends stable route IDs; the backend owns vendor credentials,
model-version mapping, safety rules, observability, cost controls, and fallbacks.

## Demo backend (shipped under `server/`)

The Fastify demo implements the **image generation** half of the pipeline against
MiniMax `image-01` I2I. Understanding and story remain on-device mocks until their
hosted routes are ready (see `REMOTE_UNDERSTANDING_TODO.md`).

| Method | Path | Purpose |
|--------|------|---------|
| POST/GET | `/health` | Coarse readiness (`generation.ready`, `generation.mode`) |
| POST | `/v1/uploads` | Multipart JPEG/HEIC ≤ 10MB → `assetId` |
| POST | `/v1/generations` | Queue job → `202` + `generationId` |
| GET | `/v1/generations/:id` | `queued` \| `processing` \| `succeeded` \| `failed` |
| GET | `/v1/results/:filename` | Download generated JPEG |
| GET | `/v1/admin/generations` | Bearer admin: redacted job list |
| PATCH | `/v1/admin/settings` | Enable/disable remote gen + prompt template |

### Create generation body

```json
{
  "sourceAssetId": "UUID",
  "requestId": "UUID",
  "aspectRatio": "3:4",
  "story": "continuity-aware prompt text",
  "timePosition": {
    "normalized": 0.5,
    "offsetDays": 9000,
    "offsetYears": 24.6,
    "compactLabel": "25 年后"
  }
}
```

On success the poll payload includes `resultUrl` pointing at the FUMIRA server,
never a MiniMax CDN URL that would require vendor auth.

### Environment

| Variable | Where | Purpose |
|----------|-------|---------|
| `MINIMAX_API_KEY` | server only | MiniMax Bearer token |
| `ADMIN_TOKEN` | server only | Admin Bearer / `X-Admin-Token` |
| `MINIMAX_MOCK` | server | Use in-process mock adapter |
| `REMOTE_GENERATION_ENABLED` | server | Kill-switch default |
| `PUBLIC_BASE_URL` | server | Absolute `resultUrl` prefix |
| `HTTPS_PROXY` / `HTTP_PROXY` | server | Outbound proxy for MiniMax (local example: `http://127.0.0.1:7990`) |
| `MINIMAX_HTTPS_PROXY` | server | Optional override used only by the MiniMax adapter |
| `FUMIRA_API_BASE_URL` | iOS env / Info.plist | Enables `RemoteGenerationProvider` |

Local demo proxy port is **7990**. Live MiniMax HTTPS goes through undici
`ProxyAgent` when any of the proxy env vars above is set. Mock mode needs no
proxy. Never put `MINIMAX_API_KEY` in iOS, git, or logs.
## Model catalog

`GET /v1/model-catalog`

```json
{
  "version": "2026-07-23",
  "options": [
    {
      "id": "openai.story.server",
      "role": "story",
      "provider": "openAI",
      "displayName": "ChatGPT 编剧路由",
      "detail": "受控的时间叙事模型",
      "availability": "ready"
    }
  ]
}
```

The backend may remap the provider model behind an ID, but must not silently
change its role or response schema. Removing readiness causes the app to fall back
to the corresponding demo route. **Not yet implemented** by the demo server; the
app still uses the bundled catalog.

## Understand

`POST /v1/understand` as multipart form data:

- `photo`: JPEG/HEIC bytes
- `session_id`: UUID
- `route_id`: catalog option ID

The response is `SceneUnderstanding`: summary, location type, visual mood, time
clues, change drivers, and subjects with confidence plus identity rules.

**Status:** contract reserved. Runtime uses `MockImageUnderstandingProvider`.
Do not invent a MiniMax HTTP understanding URL; MCP is development-only.

## Write story

`POST /v1/story`

```json
{
  "session_id": "UUID",
  "route_id": "openai.story.server",
  "range_years": [-100, 100],
  "anchors": [-100, -30, -10, 0, 10, 30, 100],
  "understanding": {}
}
```

The response is `TemporalStory`: title, logline, present truth, identity rules,
and ordered beats. Each beat includes an anchor year, narrative, and visual prompt.

**Status:** contract reserved. Runtime uses `MockStoryProvider`.

## Render (legacy sketch)

Earlier drafts described `POST /v1/render` with SSE. The demo backend supersedes
that with the upload + generations poll flow above, which matches MiniMax’s
synchronous I2I HTTP call wrapped in a server-side job.

## Reliability and privacy

- Never ship vendor API keys to iOS.
- Treat `requestId` / `session_id` plus stage as an idempotency / correlation key.
- Strip EXIF GPS unless the user explicitly opts into location-aware stories.
- Upload limit 10MB; MiniMax HTTP timeout 240s with limited exponential backoff.
- Reject prompts over 1500 characters via explicit truncation + `promptTruncated`.
- Log route/request IDs and latency, not raw photo bytes, Authorization headers,
  or full prompts / base64.
- Any response from an inactive session must be discarded by the client.
