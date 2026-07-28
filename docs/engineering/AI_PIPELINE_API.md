# AI Pipeline Backend Contract

This contract lets operations change concrete models without shipping a new iOS
binary. The app sends stable route IDs; the backend owns vendor credentials,
model-version mapping, safety rules, observability, cost controls, and fallbacks.

## FUMIRA backend (shipped under `server/`)

The Fastify service implements the full AI pipeline: **image understanding**,
**temporal story writing**, and **image generation** against MiniMax.
All three stages are remote when `MINIMAX_API_KEY` is set; mock adapters
are used when `MINIMAX_MOCK=true` or the key is absent.

| Method | Path | Purpose |
|--------|------|---------|
| POST/GET | `/health` | Coarse readiness (`generation.ready`, `generation.mode`) |
| POST | `/v1/uploads` | Multipart JPEG/HEIC ≤ 10MB → `assetId` |
| POST | `/v1/understand` | Analyze uploaded asset → `SceneUnderstanding` |
| POST | `/v1/stories` | Write temporal story → `TemporalStory` (with `targetBeat`) |
| POST | `/v1/target-beats` | Plan one exact browse target → detailed `TemporalRenderPlan` |
| POST | `/v1/generations` | Queue job → `202` + `generationId` |
| GET | `/v1/generations/:id` | `queued` \| `processing` \| `succeeded` \| `failed` |
| GET | `/v1/results/:filename` | Download generated JPEG |
| GET | `/v1/admin/generations` | Bearer admin: redacted job list + prompt metadata |
| PATCH | `/v1/admin/settings` | Enable/disable remote gen + prompt template |

### Create generation body (V3 — scene graph + render plan)

The iOS client sends structured pipeline data. The server's **PromptCompiler**
owns the final provider prompt with section-based budgets.

```json
{
  "contextVersion": "generation.v3",
  "sourceAssetId": "UUID",
  "requestId": "UUID",
  "aspectRatio": "3:4",
  "timePosition": {
    "normalized": 0.5,
    "offsetDays": 9000,
    "offsetYears": 24.6,
    "compactLabel": "25 年后"
  },
  "structuredContext": {
    "schemaVersion": "generation-context.v3",
    "understanding": {
      "summary": "...",
      "locationType": "...",
      "visualMood": "...",
      "timeClues": ["..."],
      "changeDrivers": ["..."],
      "subjects": [{ "name": "...", "confidence": 0.95, "identityRule": "..." }],
      "sceneGraph": {
        "baseline": { "locationType": "..." },
        "cameraLock": { "viewpoint": "...", "horizon": "..." },
        "regions": [{
          "id": "foreground-path",
          "depth": "foreground",
          "category": "surface",
          "description": "...",
          "spatialAnchor": "...",
          "materials": ["..."],
          "currentCondition": "...",
          "confidence": 0.95,
          "salience": 0.8,
          "temporalPolicy": "age_in_place"
        }],
        "globalDrivers": ["..."],
        "uncertainties": ["..."]
      }
    },
    "story": {
      "schemaVersion": "temporal-story.v3",
      "title": "...",
      "logline": "...",
      "presentTruth": "...",
      "identityRules": ["..."],
      "beats": [
        { "anchorYears": -100, "title": "...", "narrative": "...", "visualPrompt": "..." },
        "...seven canonical beats at -100,-30,-10,0,10,30,100..."
      ],
      "targetBeat": {
        "anchorYears": 24.6,
        "title": "...",
        "narrative": "...",
        "visualPrompt": "...",
        "renderPlan": {
          "exactTarget": { "offsetDays": 9000, "targetDateISO": "...", "compactLabel": "25 年后" },
          "horizonBand": "decades",
          "subjectContinuityMode": "identity_persists",
          "globalEraState": "...",
          "regionChanges": [{
            "regionId": "foreground-path",
            "action": "renovate",
            "magnitude": "moderate",
            "targetAppearance": "...",
            "causalReason": "..."
          }],
          "crossRegionCouplings": ["..."],
          "mustPreserve": ["..."],
          "allowedEraAdditions": ["..."],
          "prohibitedDrift": ["..."],
          "coverage": {
            "foreground": true,
            "midground": true,
            "background": true,
            "builtEnvironment": true,
            "naturalEnvironment": true,
            "principalSubject": true
          }
        }
      }
    },
    "generationMode": "captured_target"
  }
}
```

**Legacy path** (backward compatible): the client may still send `"story": "flat string"`
without `structuredContext`. The server wraps it in the admin-configured template
using the legacy truncation strategy.

The generation record now includes prompt metadata:
- `promptVersion`: `"v3"` for compiled prompts, absent for legacy
- `promptHash`: SHA-256 prefix of the compiled prompt
- `sectionCharCounts`: per-section character counts
- `truncatedSections`: which sections were compressed or dropped

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

Local proxy port is **7990**. Live MiniMax HTTPS goes through undici
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
to the corresponding standard route. **Not yet implemented** by the current server; the
app still uses the bundled catalog.

## Understand

`POST /v1/understand`

```json
{
  "sourceAssetId": "UUID",
  "requestId": "UUID",
  "copyConstraints": { "summary": 80, "locationType": 14, "visualMood": 40, "timeClue": 24, "changeDriver": 24, "subjectName": 18, "identityRule": 48 }
}
```

The response separates concise UI copy from a machine-facing `sceneGraph`.
The graph covers visible depth regions, materials, current condition, camera
locks, and each region's temporal policy. UI copy constraints do not truncate
the detailed graph into caption-sized strings.

**Status:** live via MiniMax VLM (`MINIMAX_VLM_API_KEY` or `MINIMAX_API_KEY`).
Includes injection defense for text visible inside the image.

## Write story

`POST /v1/stories`

```json
{
  "understanding": { "...SceneUnderstanding..." },
  "targetTime": { "offsetYears": 24.6, "compactLabel": "25 年后" },
  "copyConstraints": { "title": 16, "logline": 56, "presentTruth": 72, "identityRule": 48, "beatTitle": 14, "beatNarrative": 72, "visualPrompt": 110 },
  "requestId": "UUID"
}
```

The server first writes the seven canonical browsing beats, then makes a
separate exact-target planning call using the story context. The response is
`TemporalStory` V3: concise narrative beats plus a **`targetBeat`** carrying a
detailed `TemporalRenderPlan`. Missing exact planning is rejected; it never
falls back to the nearest canonical beat.

**Status:** live via MiniMax M3 (`MINIMAX_STORY_MODEL`).
Includes injection defense for untrusted scene analysis data.

## Render (legacy sketch)

Earlier drafts described `POST /v1/render` with SSE. The FUMIRA backend supersedes
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
- Generated images can be compared against source + render plan by the optional
  visual critic; at most one repair pass keeps the original prompt and appends
  actionable missing-region instructions.
