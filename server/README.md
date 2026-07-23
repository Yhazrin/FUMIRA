# FUMIRA Demo Backend

TypeScript + Fastify proxy between the iOS app and MiniMax `image-01` I2I.

## Security

- `MINIMAX_API_KEY` lives only in server process env. Never send it to iOS.
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
| POST/GET | `/health` | Coarse generation readiness |
| POST | `/v1/uploads` | multipart JPEG/HEIC ≤ 10MB |
| POST | `/v1/generations` | 202 + `generationId` |
| GET | `/v1/generations/:id` | poll status / resultUrl |
| GET | `/v1/results/:filename` | download generated JPEG |
| GET | `/v1/admin/generations` | Bearer admin list |
| PATCH | `/v1/admin/settings` | enable/disable + prompt template |

Image understanding stays on the iOS Mock provider for MVP. See
`docs/engineering/REMOTE_UNDERSTANDING_TODO.md` — do not invent MiniMax HTTP
understanding endpoints; MCP is for development verification only.
