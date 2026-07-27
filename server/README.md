# FUMIRA Backend

TypeScript + Fastify relay for routed MiniMax `image-01` and API Mart
`gpt-image-2` image-to-image generation.

## Security

- `MINIMAX_API_KEY` and `APIMART_API_KEY` live only in server process env.
  Never send either credential to iOS.
- Logs record `requestId`, `generationId`, status, duration, and error codes only.
- Admin routes require `Authorization: Bearer $ADMIN_TOKEN`.

## Quick start

```sh
cd server
cp .env.example .env
# For local flow without a real key:
#   MINIMAX_MOCK=true
# or a real:
#   MINIMAX_API_KEY=...   # never commit
#   APIMART_API_KEY=...   # optional GPT-Image-2 relay route
#   APIMART_RESOLVE_IP=... # optional provider-only DNS override
#   MINIMAX_MOCK=false
# Also set ADMIN_TOKEN=...
#
# Outbound MiniMax calls use the local proxy on port 7990 by default:
#   HTTPS_PROXY=http://127.0.0.1:7990
#   HTTP_PROXY=http://127.0.0.1:7990
npm install
npm test
npm run dev
```

### Proxy (port 7990)

This project’s local HTTP/HTTPS proxy listens on **7990**.

| Use | How |
|-----|-----|
| MiniMax I2I outbound | Set `HTTPS_PROXY` / `HTTP_PROXY` (or `MINIMAX_HTTPS_PROXY`) in `.env` to `http://127.0.0.1:7990`. The live adapter routes vendor HTTPS through undici `ProxyAgent`. |
| npm install | `server/.npmrc` points at `http://127.0.0.1:7990`. Ensure the proxy is running before `npm install`. |

Mock mode (`MINIMAX_MOCK=true`) does not call MiniMax and does not need the proxy.
## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| POST/GET | `/health` | Coarse readiness for both image providers |
| POST | `/v1/uploads` | multipart JPEG/HEIC ≤ 10MB |
| POST | `/v1/generations` | source asset + exact-time `prompt`; returns 202 + `generationId` |
| GET | `/v1/generations/:id` | poll status / resultUrl |
| GET | `/v1/results/:filename` | download generated JPEG/PNG |
| POST | `/v1/understand` | analyzes the generated target image at its exact target time |
| POST | `/v1/stories` | writes a timeline anchored to that generated image |
| GET | `/v1/admin/generations` | Bearer admin list |
| PATCH | `/v1/admin/settings` | enable/disable + prompt template |

`imageProvider` on `/v1/generations` accepts `minimax` or `apimart`; omitted
values default to MiniMax for compatibility with older app builds.

The app pipeline is intentionally ordered as generation → generated-image
understanding → story. The relay still accepts the legacy `story` request field
as a prompt alias for older builds, but current clients send `prompt`.
