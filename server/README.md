# FUMIRA Backend

TypeScript + Fastify proxy between the iOS app and MiniMax understanding,
story-planning and `image-01` I2I services.

## Security

- `MINIMAX_API_KEY` and `MINIMAX_VLM_API_KEY` live only in the server process.
- Logs record request IDs, generation IDs, status, duration, error codes and
  prompt-section metadata only.
- Admin routes require `Authorization: Bearer $ADMIN_TOKEN`.

## Quick start

```sh
cd server
cp .env.example .env
# For local flow without real keys:
#   MINIMAX_MOCK=true
# Or configure:
#   MINIMAX_API_KEY=...
#   MINIMAX_VLM_API_KEY=...
#   MINIMAX_MOCK=false
# Also set ADMIN_TOKEN=...
npm install
npm test
npm run dev
```

## Proxy configuration

MiniMax outbound HTTPS may use the local proxy on port `7990`:

```dotenv
HTTPS_PROXY=http://127.0.0.1:7990
HTTP_PROXY=http://127.0.0.1:7990
# or:
MINIMAX_HTTPS_PROXY=http://127.0.0.1:7990
```

The tracked `server/.npmrc` contains only the public npm registry so GitHub
Actions and machines without the local proxy can run `npm ci`. Developers who
also need npm itself to use the proxy should export the proxy variables in their
shell or configure an untracked user-level `~/.npmrc`.

Mock mode (`MINIMAX_MOCK=true`) does not call MiniMax and does not need a proxy.

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| POST/GET | `/health` | Coarse generation readiness |
| POST | `/v1/uploads` | Multipart JPEG/HEIC ≤ 10MB |
| POST | `/v1/understand` | Scene-wide image understanding |
| POST | `/v1/stories` | Canonical story + exact target beat |
| POST | `/v1/target-beats` | Continue existing story at an exact browse time |
| POST | `/v1/generations` | Queue generation; structured V2 preferred |
| GET | `/v1/generations/:id` | Poll status / result URL |
| GET | `/v1/results/:filename` | Download generated JPEG |
| GET | `/v1/admin/generations` | Bearer admin list |
| PATCH | `/v1/admin/settings` | Enable/disable + legacy prompt template |

See `docs/engineering/AI_PIPELINE_API.md` and
`docs/engineering/TEMPORAL_PROMPT_ARCHITECTURE.md` for the prompt contract and
SceneGraph V3 migration plan.
