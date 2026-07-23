# AI Pipeline Backend Contract

This contract lets operations change concrete models without shipping a new iOS
binary. The app sends stable route IDs; the backend owns vendor credentials,
model-version mapping, safety rules, observability, cost controls, and fallbacks.

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
to the corresponding demo route.

## Understand

`POST /v1/understand` as multipart form data:

- `photo`: JPEG/HEIC bytes
- `session_id`: UUID
- `route_id`: catalog option ID

The response is `SceneUnderstanding`: summary, location type, visual mood, time
clues, change drivers, and subjects with confidence plus identity rules.

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

## Render

`POST /v1/render` as multipart form data:

- `photo`: original image bytes
- `request`: JSON containing session ID, route ID, continuous target years,
  structured understanding, approved story, and continuity constraints

Return a job ID, then stream progress over Server-Sent Events or return the final
image directly. The final result includes the story beat ID and route ID used.

## Reliability and privacy

- Require an app/user authorization token; never ship vendor API keys to iOS.
- Treat `session_id` plus stage as an idempotency key.
- Strip EXIF GPS unless the user explicitly opts into location-aware stories.
- Set upload, inference, and total timeouts separately.
- Reject unknown/not-ready route IDs.
- Log route ID and latency, not raw photo bytes or full prompts.
- Any response from an inactive session must be discarded by the client.
