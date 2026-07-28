# FUMIRA Backend

TypeScript + Fastify backend for scene understanding, temporal world planning,
MiniMax `image-01` generation and post-generation visual quality control.

## Structured generation pipeline

```text
source image
  -> SceneGraph v1
  -> exact TemporalRenderPlan v1
  -> PromptCompiler V3
  -> image-01 generation
  -> VisualCritic v1
  -> optional single correction generation
```

Current iOS clients may continue sending `generation.v2`. The server analyzes
the source image into a real SceneGraph, creates or reuses an immutable exact
render plan, and internally upgrades the request to `generation.v3` before
compilation. A provider failure falls back to deterministic region planning;
it never restores the old single-string `visualPrompt` behavior.

## Security

- `MINIMAX_API_KEY` and `MINIMAX_VLM_API_KEY` live only in the server process.
- Scene text and model JSON are treated as untrusted before prompt compilation.
- Logs record request IDs, generation IDs, hashes, quality scores and section
  metadata; raw prompts and image bytes are not logged.
- Admin routes require `Authorization: Bearer $ADMIN_TOKEN`.

## Quick start

```sh
cd server
cp .env.example .env
# Local image-generation flow without a real key:
#   MINIMAX_MOCK=true
# Live V3 intelligence and generation:
#   MINIMAX_API_KEY=...
#   MINIMAX_VLM_API_KEY=...
#   MINIMAX_MOCK=false
npm install
npm test
npm run dev
```

## Proxy configuration

MiniMax outbound HTTPS may use an optional local proxy:

```dotenv
MINIMAX_HTTPS_PROXY=http://127.0.0.1:7990
# or HTTPS_PROXY / HTTP_PROXY
```

The tracked `server/.npmrc` contains only the public npm registry. Do not commit
a localhost proxy because GitHub Actions and other machines cannot reach it.
Mock mode does not call MiniMax and needs no proxy.

## V3 quality controls

```dotenv
VISUAL_CRITIC_ENABLED=true
VISUAL_CRITIC_MAX_REGENERATIONS=1
VISUAL_CRITIC_CAMERA_THRESHOLD=0.78
VISUAL_CRITIC_CHANGE_THRESHOLD=0.72
VISUAL_CRITIC_ENVIRONMENT_THRESHOLD=0.62
VISUAL_CRITIC_ERA_THRESHOLD=0.72
```

The repair pass keeps the original source image as reference, preserves
successful regions, and targets only missed region IDs or detected camera drift.
The better-scoring candidate is retained.

## Time baseline

`timePosition.offsetDays` is authoritative. Clients may additionally send:

```json
{
  "sourceDateISO": "2010-07-28"
}
```

When present, `targetDateISO` is calculated from the photo's source date. When
absent, the image prompt describes a relative offset and does not present the
server's current date as evidence about the photograph's capture era.

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| POST/GET | `/health` | V3 capabilities, thresholds and readiness |
| POST | `/v1/uploads` | Multipart JPEG/HEIC ≤ 10MB |
| POST | `/v1/understand` | Concise V2-compatible understanding |
| POST | `/v1/scene-graphs` | Full spatial SceneGraph analysis |
| POST | `/v1/stories` | User-facing story + exact target beat |
| POST | `/v1/target-beats` | Continue a story at one exact browse time |
| POST | `/v1/render-plans` | Exact region-addressable world plan |
| POST | `/v1/generations` | Accept V2 or native V3 structured generation |
| GET | `/v1/generations/:id` | Poll result and quality status |
| GET | `/v1/results/:filename` | Download generated JPEG |
| GET | `/v1/admin/generations` | Prompt/plan/critic diagnostics |
| PATCH | `/v1/admin/settings` | Generation switch + legacy template |

See:

- `docs/engineering/AI_PIPELINE_API.md`
- `docs/engineering/TEMPORAL_PROMPT_ARCHITECTURE.md`
- `docs/engineering/TEMPORAL_V3_IMPLEMENTATION.md`
