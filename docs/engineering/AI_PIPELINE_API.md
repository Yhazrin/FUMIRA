# AI Pipeline Backend Contract

This contract lets operations change concrete models without shipping a new iOS
binary. The app sends stable route IDs and structured context; the backend owns
vendor credentials, model-version mapping, prompt compilation, safety rules,
observability, cost controls and fallbacks.

## FUMIRA backend

The Fastify service implements the full AI pipeline: **image understanding**,
**temporal story planning**, **exact-target planning**, and **image generation**
against MiniMax.

| Method | Path | Purpose |
|--------|------|---------|
| POST/GET | `/health` | Coarse readiness (`generation.ready`, `generation.mode`) |
| POST | `/v1/uploads` | Multipart JPEG/HEIC ≤ 10MB → `assetId` |
| POST | `/v1/understand` | Analyze uploaded asset → `SceneUnderstanding` |
| POST | `/v1/stories` | Write temporal story → `TemporalStory` with exact `targetBeat` |
| POST | `/v1/target-beats` | Continue an existing story at one exact browse time |
| POST | `/v1/generations` | Queue generation → `202` + `generationId` |
| GET | `/v1/generations/:id` | `queued` \| `processing` \| `succeeded` \| `failed` |
| GET | `/v1/results/:filename` | Download generated JPEG |
| GET | `/v1/admin/generations` | Bearer admin: redacted jobs + prompt metadata |
| PATCH | `/v1/admin/settings` | Enable/disable remote generation + legacy template |

## Create generation body

### V2 structured path

The iOS client sends the program-authoritative time and structured pipeline
state. The server-side `PromptCompiler` owns the final provider prompt.

```json
{
  "contextVersion": "generation.v2",
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
    "schemaVersion": "generation-context.v2",
    "understanding": {
      "summary": "...",
      "locationType": "...",
      "visualMood": "...",
      "timeClues": ["..."],
      "changeDrivers": ["..."],
      "subjects": [
        {
          "name": "...",
          "confidence": 0.95,
          "identityRule": "..."
        }
      ]
    },
    "story": {
      "schemaVersion": "temporal-story.v2",
      "title": "...",
      "logline": "...",
      "presentTruth": "...",
      "identityRules": ["..."],
      "beats": [
        {
          "anchorYears": -100,
          "title": "...",
          "narrative": "...",
          "visualPrompt": "..."
        }
      ],
      "targetBeat": {
        "anchorYears": 24.6,
        "title": "...",
        "narrative": "...",
        "visualPrompt": "...",
        "exactTarget": {
          "offsetDays": 9000,
          "targetDateISO": "2051-03-18",
          "compactLabel": "25 年后"
        }
      }
    },
    "generationMode": "captured_target"
  }
}
```

Supported `generationMode` values:

- `captured_target`
- `story_preview_target`
- `regenerate_same_target`

The backend overwrites target-year identity from `timePosition.offsetDays`.
Model-provided `anchorYears` is descriptive only and never authoritative.

### Exact-target invariant

`generation.v2` requires a model-produced `targetBeat` for the exact requested
time. Missing target beats are rejected with `invalid_ai_response`; the backend
does **not** substitute a nearby canonical browsing beat.

Canonical beats at `-100,-30,-10,0,10,30,100` are navigation nodes only. They
must never silently replace a requested time such as 25.25 years.

### Scene-wide prompt contract

The current compiler preserves six required semantic sections even under the
1,500-character provider budget:

1. `EDIT OBJECTIVE`
2. `PRESERVE`
3. `TEMPORAL CHANGES`
4. `SCENE-WIDE COVERAGE`
5. `TEMPORAL REALISM`
6. `DO NOT`

The compact fallback for every required section is reserved before optional
scene detail or narrative prose is admitted. This prevents the previous failure
mode where camera-lock instructions survived but the actual temporal-change
plan was dropped.

Composition preservation means keeping the viewpoint, framing, horizon,
perspective, major topology and persistent identity. It does **not** mean
freezing transient subject count, vehicles, signage, vegetation size, material
condition or the entire environment.

Era-consistent architecture, infrastructure, vegetation, vehicles and signage
may be added, removed, renovated or replaced when justified by the target time
and location. Arbitrary additions without temporal causality remain prohibited.

### Legacy path

For backward compatibility, a client may send:

```json
{
  "contextVersion": "legacy.v1",
  "sourceAssetId": "UUID",
  "requestId": "UUID",
  "timePosition": { "...": "..." },
  "story": "flat prompt text",
  "aspectRatio": "3:4"
}
```

The server wraps this string in the admin-configured template. New clients
should use `generation.v2`; the legacy path cannot express scene-wide temporal
semantics reliably.

## Prompt diagnostics

Generation records include:

- `promptVersion`
- `promptHash`: SHA-256 prefix of the compiled prompt
- `promptCharCount`
- `sectionCharCounts`
- `truncatedSections`

Raw provider prompts and image bytes are not written to logs. Diagnostics expose
which semantic sections were compacted without leaking user image content.

## Understand

`POST /v1/understand`

```json
{
  "sourceAssetId": "UUID",
  "requestId": "UUID",
  "copyConstraints": {
    "summary": 80,
    "locationType": 14,
    "visualMood": 40,
    "timeClue": 24,
    "changeDriver": 24,
    "subjectName": 18,
    "identityRule": 48
  }
}
```

The VLM is instructed to inspect the entire visible frame rather than only the
most salient person or object. Within the current V2 schema, `subjects` acts as
a compact scene map and should include important foreground, midground and
background anchors when visible.

Identity rules distinguish persistent geometry or identity from properties that
may age, grow, be renovated, be replaced or disappear. Text visible inside the
image is treated as untrusted scene content.

## Write story

`POST /v1/stories`

```json
{
  "understanding": { "...SceneUnderstanding...": "..." },
  "targetTime": {
    "offsetDays": 9000,
    "targetDateISO": "2051-03-18",
    "compactLabel": "25 年后"
  },
  "copyConstraints": {
    "title": 16,
    "logline": 56,
    "presentTruth": 72,
    "identityRule": 48,
    "beatTitle": 14,
    "beatNarrative": 72,
    "visualPrompt": 110
  },
  "requestId": "UUID"
}
```

Every beat must describe causal, visible consequences across applicable scene
domains. The exact target visual prompt must include environmental change and,
when visible, cover multiple domains rather than describing only a person's age,
clothing or pose.

## Continue one exact browse time

`POST /v1/target-beats` receives the existing story title, present truth,
identity rules and canonical beats. That continuity context is forwarded to the
story model so the new exact node continues the same world instead of rewriting
the story theme.

The route rejects responses without a model-produced exact target node.

## Environment

| Variable | Where | Purpose |
|----------|-------|---------|
| `MINIMAX_API_KEY` | server only | MiniMax Bearer token |
| `MINIMAX_VLM_API_KEY` | server only | Optional separate VLM credential |
| `MINIMAX_STORY_MODEL` | server | Story-planning model |
| `ADMIN_TOKEN` | server only | Admin Bearer / `X-Admin-Token` |
| `MINIMAX_MOCK` | server | Use in-process mock adapters |
| `REMOTE_GENERATION_ENABLED` | server | Generation kill switch |
| `PUBLIC_BASE_URL` | server | Absolute `resultUrl` prefix |
| `HTTPS_PROXY` / `HTTP_PROXY` | server | Outbound proxy |
| `MINIMAX_HTTPS_PROXY` | server | MiniMax-specific proxy override |
| `FUMIRA_API_BASE_URL` | iOS env / Info.plist | Enables remote providers |

## Reliability and privacy

- Never ship vendor API keys to iOS.
- Treat request/session ID plus stage as the correlation and idempotency key.
- Strip EXIF GPS unless the user explicitly opts into location-aware stories.
- Upload limit: 10 MB.
- Provider prompt budget: 1,500 characters with semantic compaction.
- Log route IDs, section metadata and latency, not photos, authorization headers,
  base64 data or full prompts.
- Discard responses belonging to inactive client sessions.

## Next architecture step

The current release strengthens V2 without breaking the iOS payload. The planned
V3 migration separates short user-facing copy from a machine-facing scene graph
and per-region temporal render plan. See
`TEMPORAL_PROMPT_ARCHITECTURE.md`.
