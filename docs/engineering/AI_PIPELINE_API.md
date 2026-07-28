# AI Pipeline Backend Contract

FUMIRA keeps vendor credentials, model routing, world planning, prompt
compilation, quality thresholds and fallbacks on the server. The app sends
stable structured contracts and never sends a final provider prompt.

## Pipeline

```text
upload
  -> concise understanding / user story
  -> SceneGraph v1
  -> exact TemporalRenderPlan v1
  -> PromptCompiler V3
  -> image-01
  -> generated-image SceneGraph
  -> VisualCritic v1
  -> at most one controlled repair generation
```

The user-facing story and machine-facing render plan are separate. Narrative
copy may provide continuity facts, but it does not directly control the final
image by itself.

## Routes

| Method | Path | Purpose |
|---|---|---|
| POST/GET | `/health` | Generation, V3 capability and critic readiness |
| POST | `/v1/uploads` | Multipart JPEG/HEIC ≤ 10 MB → `assetId` |
| POST | `/v1/understand` | Concise V2-compatible understanding |
| POST | `/v1/scene-graphs` | Full spatial SceneGraph analysis |
| POST | `/v1/stories` | User-facing story + exact target beat |
| POST | `/v1/target-beats` | Continue one exact browse time |
| POST | `/v1/render-plans` | Exact region-addressable target world |
| POST | `/v1/generations` | Prepare and queue V2 or V3 generation |
| GET | `/v1/generations/:id` | Poll status, result and quality status |
| GET | `/v1/results/:filename` | Download generated JPEG |
| GET | `/v1/admin/generations` | Redacted prompt/plan/critic diagnostics |
| PATCH | `/v1/admin/settings` | Kill switch + legacy template |

## Time contract

`timePosition.offsetDays` is authoritative. `offsetYears` and `compactLabel` are
presentation values.

```json
{
  "normalized": 0.5,
  "offsetDays": 9131.25,
  "offsetYears": 25,
  "compactLabel": "25 年后",
  "sourceDateISO": "2010-07-28"
}
```

`sourceDateISO` is optional. When provided, the backend calculates the target
calendar date from the photograph's source moment. When absent, prompt
compilation emphasizes the relative offset and does not present the server's
current calendar date as visual evidence about an old photograph.

## Existing V2 client path

Current iOS clients may continue sending `generation.v2`:

```json
{
  "contextVersion": "generation.v2",
  "sourceAssetId": "UUID",
  "requestId": "UUID",
  "aspectRatio": "3:4",
  "timePosition": {
    "normalized": 0.5,
    "offsetDays": 9131.25,
    "offsetYears": 25,
    "compactLabel": "25 年后",
    "sourceDateISO": "2026-07-28"
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
        "anchorYears": 25,
        "title": "...",
        "narrative": "...",
        "visualPrompt": "..."
      }
    },
    "generationMode": "captured_target"
  }
}
```

Before queueing, the server:

1. analyzes the source image into a full SceneGraph;
2. reuses a cached graph when the same asset is regenerated;
3. creates or reuses an immutable exact render plan keyed by source, target,
   graph and story continuity;
4. internally upgrades to `generation.v3`;
5. compiles the provider prompt with `PromptCompilerV3`.

If live SceneGraph or planning services fail, deterministic V2-to-V3 conversion
still produces a typed region plan. It never falls back to a single flat
`visualPrompt`.

Supported `generationMode` values:

- `captured_target`
- `story_preview_target`
- `regenerate_same_target`

`regenerate_same_target` reuses the same cached RenderPlan whenever immutable
inputs match, preventing a second click from inventing a different world.

## Native V3 generation

```json
{
  "contextVersion": "generation.v3",
  "sourceAssetId": "UUID",
  "requestId": "UUID",
  "aspectRatio": "3:4",
  "timePosition": {
    "normalized": 0.5,
    "offsetDays": 9131.25,
    "offsetYears": 25,
    "compactLabel": "25 年后",
    "sourceDateISO": "2026-07-28"
  },
  "structuredContext": {
    "schemaVersion": "generation-context.v3",
    "sceneGraph": {
      "schemaVersion": "scene-graph.v1",
      "baseline": {},
      "camera": {},
      "regions": [],
      "globalDrivers": [],
      "uncertainties": []
    },
    "targetPlan": {
      "schemaVersion": "temporal-render-plan.v1",
      "planId": "sha256-prefix",
      "exactTarget": {},
      "horizonBand": "decades",
      "globalWorldState": {},
      "regionChanges": [],
      "additions": [],
      "removals": [],
      "crossRegionCouplings": [],
      "unchangedRegionIds": [],
      "subjectContinuityMode": "age_progression",
      "prohibitedDrift": [],
      "coverage": {}
    },
    "temporalStory": {
      "schemaVersion": "temporal-story.v2"
    },
    "generationMode": "captured_target",
    "qualityPolicy": {
      "visualCriticEnabled": true,
      "maxRegenerations": 1,
      "thresholds": {
        "cameraConsistency": 0.78,
        "requiredChangeCompletion": 0.72,
        "environmentEvolution": 0.62,
        "eraCoherence": 0.72
      }
    }
  }
}
```

The backend overwrites the plan's exact offset and date from the authoritative
`timePosition` before validation. A client cannot alter the requested target by
changing model-authored `anchorYears`.

## SceneGraph

`POST /v1/scene-graphs`

```json
{
  "sourceAssetId": "UUID",
  "requestId": "UUID"
}
```

The live VLM produces 4–16 semantic regions across foreground, midground,
background and sky. Each region includes:

- stable region ID;
- screen zone and optional normalized bounding box;
- depth and category;
- visible source state, materials and identity features;
- persistence class;
- temporal policy;
- confidence and salience.

The analyzer distinguishes people, vehicles, architecture, infrastructure,
surfaces, signage, vegetation and atmosphere rather than applying one blanket
"preserve subjects" instruction.

## RenderPlan

`POST /v1/render-plans`

```json
{
  "sceneGraph": { "schemaVersion": "scene-graph.v1" },
  "target": {
    "offsetDays": 9131.25,
    "compactLabel": "25 年后",
    "sourceDateISO": "2026-07-28"
  },
  "storyContext": {
    "title": "...",
    "presentTruth": "...",
    "identityRules": ["..."],
    "canonicalBeats": []
  },
  "continuityMode": "age_progression",
  "requestId": "UUID"
}
```

Every source region must appear exactly once: either in `regionChanges` or
`unchangedRegionIds`, never both. Each change requires:

- action and magnitude;
- concrete target state;
- causal reason;
- visible evidence.

For multi-month or longer targets, a scene containing environment must include a
non-person environmental change. Decades and longer horizons require multiple
applicable domains and consistent depth-layer evolution.

## Continuity modes

- `identity_persists`
- `age_progression`
- `lineage_or_successor`
- `object_remains`
- `site_only`
- `time_traveler`

Strong MiniMax `subject_reference` is automatically suppressed for
`site_only` and `lineage_or_successor`, even when an older client requests it.
This prevents long-horizon environment generation from being frozen by a
portrait-style identity constraint.

## PromptCompiler V3

The required provider contract is:

1. `TARGET`
2. `CAMERA LOCK`
3. `CONTINUITY`
4. `REGION EDITS`
5. `WORLD COHERENCE`
6. `PROHIBITED`

The compiler first assigns a compact action to every changed region. Only after
all region IDs survive does it expand high-salience regions with more detail.
For extreme 16-region scenes, an emergency representation retains all region
IDs, actions, camera constraints, coherence and prohibitions under the
1,500-character limit.

Model strings are sanitized before compilation. Raw angle-bracket boundaries,
null bytes and control characters are not passed to the image model.

## Visual critic

After generation, the backend analyzes the result into another SceneGraph and
compares it with the source graph and exact RenderPlan.

Scores:

- camera consistency;
- spatial topology consistency;
- principal identity consistency;
- required change completion;
- environmental evolution;
- era coherence.

The critic also returns exact missed region IDs, unexplained changes and camera
drift. When configured thresholds fail, the backend performs one controlled
repair pass. The correction prompt preserves successful regions and addresses
only missed IDs or drift. The candidate with the better weighted critic score
is retained.

Polling exposes:

```json
{
  "qualityStatus": "passed",
  "regenerationCount": 1
}
```

Admin diagnostics additionally include `renderPlanId`, full critic scores,
prompt hash, section counts and compacted sections.

## Exact target invariants

- `generation.v2` requires an exact `targetBeat`.
- Missing target beats are rejected; no nearest canonical node fallback.
- Canonical `-100,-30,-10,0,10,30,100` beats are browsing nodes only.
- `offsetDays` is authoritative for planning, compilation and deduplication.
- Story-model `anchorYears` never overrides the program target.

## Legacy path

`legacy.v1` remains available for compatibility, but it cannot express
SceneGraph, RenderPlan or visual-critic semantics and should not be used by new
clients.

## Environment

| Variable | Purpose |
|---|---|
| `MINIMAX_API_KEY` | Image generation and temporal planning |
| `MINIMAX_VLM_API_KEY` | Optional separate source/result VLM credential |
| `MINIMAX_STORY_MODEL` | Story and world planning model |
| `MINIMAX_TEXT_MODEL` | Critic comparison model |
| `ADMIN_TOKEN` | Admin authentication |
| `REMOTE_GENERATION_ENABLED` | Generation kill switch |
| `VISUAL_CRITIC_ENABLED` | Enable post-generation quality loop |
| `VISUAL_CRITIC_MAX_REGENERATIONS` | Server maximum, currently 0 or 1 |
| `VISUAL_CRITIC_CAMERA_THRESHOLD` | Camera consistency threshold |
| `VISUAL_CRITIC_CHANGE_THRESHOLD` | Planned-change completion threshold |
| `VISUAL_CRITIC_ENVIRONMENT_THRESHOLD` | Environment evolution threshold |
| `VISUAL_CRITIC_ERA_THRESHOLD` | Era coherence threshold |
| `PUBLIC_BASE_URL` | Absolute result URL prefix |
| `MINIMAX_HTTPS_PROXY` | Optional MiniMax-specific proxy |

## Reliability and privacy

- Vendor keys never ship to iOS.
- Upload limit: 10 MB.
- Prompt budget: 1,500 characters with semantic compaction.
- Raw prompts, photos, base64 and authorization headers are not logged.
- Plan cache is bounded to 128 source/target contexts per process.
- Remote planning failures use deterministic typed plans.
- Visual-critic failure does not discard an otherwise successful image; the
  result is marked `best_effort` when thresholds remain unmet.
