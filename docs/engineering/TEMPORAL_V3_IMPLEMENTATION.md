# Temporal Generation V3 — Implemented Pipeline

## Status

This document describes executable server behavior in the
`prompt-v3-scene-evolution` branch. It is not a future proposal.

The structured generation path is now:

```text
V2 understanding or V3 source image
        ↓
SceneGraph v1
        ↓
TemporalRenderPlan v1
        ↓
PromptCompiler V3
        ↓
MiniMax image generation
        ↓
Generated-image SceneGraph
        ↓
VisualCritic v1
        ↓ fail threshold
One controlled correction generation
```

The user-facing story remains separate from the machine-facing render plan.
Story text can provide continuity, but it no longer serves as the sole rendering
instruction.

## Existing iOS clients

The iOS client may continue sending `contextVersion: generation.v2`.

`POST /v1/generations` now performs an asynchronous preparation step:

1. convert V2 `SceneUnderstanding` into a typed provisional `SceneGraph`;
2. submit the graph, exact target and existing story continuity to the V3
   temporal planner;
3. receive a region-addressable `TemporalRenderPlan`;
4. queue an internal `generation.v3` request;
5. compile the final provider prompt with `PromptCompilerV3`.

If the remote temporal planner is unavailable or returns an invalid plan, the
server uses a deterministic region-by-region plan rather than falling back to a
single flat `visualPrompt`.

Direct queue callers also receive the deterministic V2-to-V3 fallback.

## New intelligence endpoints

### Analyze a SceneGraph

`POST /v1/scene-graphs`

```json
{
  "sourceAssetId": "UUID",
  "requestId": "UUID"
}
```

Response:

```json
{
  "schemaVersion": "scene-graph-response.v1",
  "requestId": "UUID",
  "derivedFromV2": false,
  "sceneGraph": {
    "schemaVersion": "scene-graph.v1",
    "baseline": {},
    "camera": {},
    "regions": [],
    "globalDrivers": [],
    "uncertainties": []
  }
}
```

The live VLM analyzes 4–16 regions across foreground, midground, background and
sky. Every region receives:

- stable ID;
- coarse screen zone and optional normalized bounding box;
- depth and semantic category;
- source appearance, material and identity evidence;
- persistence class;
- temporal policy;
- confidence and salience.

### Plan one exact target world

`POST /v1/render-plans`

```json
{
  "sceneGraph": { "schemaVersion": "scene-graph.v1" },
  "target": {
    "offsetDays": 9131.25,
    "targetDateISO": "2051-07-28",
    "compactLabel": "25 年后"
  },
  "storyContext": {
    "title": "站前的时间回声",
    "presentTruth": "当前场景事实",
    "identityRules": ["保持人物身份"],
    "canonicalBeats": []
  },
  "continuityMode": "age_progression",
  "requestId": "UUID"
}
```

Response:

```json
{
  "schemaVersion": "render-plan-response.v1",
  "requestId": "UUID",
  "deterministicFallback": false,
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
  }
}
```

Every source region must be evaluated exactly once. It must either receive a
region change or appear in `unchangedRegionIds`. A region cannot appear in both.

## Native V3 generation request

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
    "compactLabel": "25 年后"
  },
  "structuredContext": {
    "schemaVersion": "generation-context.v3",
    "sceneGraph": { "schemaVersion": "scene-graph.v1" },
    "targetPlan": { "schemaVersion": "temporal-render-plan.v1" },
    "temporalStory": { "schemaVersion": "temporal-story.v2" },
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

The server overwrites `targetPlan.exactTarget` from the program-authoritative
`timePosition.offsetDays` before validation and compilation.

## PromptCompiler V3

The compiler emits an operational edit contract rather than narrative prose.
The required order is:

1. `TARGET`
2. `CAMERA LOCK`
3. `CONTINUITY`
4. `REGION EDITS`
5. `WORLD COHERENCE`
6. `PROHIBITED`

Optional sections are admitted only when the 1,500-character provider budget
allows them:

- cross-region rules;
- justified additions and removals;
- coverage check;
- uncertainty handling.

A region instruction resembles:

```text
R4 middle_right/background/architecture -> RENOVATE major:
retain position and recognizable volume; update facade and access
infrastructure for the target era; cause: one maintenance and renewal cycle
```

The compiler keeps region IDs, spatial locators and actions even when target
state prose must be compressed.

## Continuity modes

- `identity_persists`
- `age_progression`
- `lineage_or_successor`
- `object_remains`
- `site_only`
- `time_traveler`

Deep-time ordinary scenes default to `site_only`. A modern object that remains
across geological time must be explicitly represented as `time_traveler` or an
intentional anomalous object anchor.

## Visual critic and controlled repair

After the first successful image generation, the live adapter:

1. analyzes the generated image into a second SceneGraph;
2. compares source graph, generated graph and target plan;
3. produces `visual-critic.v1` scores and exact missed region IDs.

The critic measures:

- camera consistency;
- spatial topology consistency;
- principal identity consistency;
- required region-change completion;
- environmental evolution;
- era coherence;
- unexplained changes;
- camera drift.

If configured thresholds fail, the server creates one correction prompt. It
preserves already successful regions and explicitly addresses only missed region
IDs and detected camera drift. The original source image remains the generation
reference, preventing recursive degradation.

The repaired output is analyzed again. The server keeps the candidate with the
higher weighted critic score.

Generation records store:

- `renderPlanId`;
- final `visualCritic` result;
- `regenerationCount`;
- V3 prompt hash and section diagnostics.

The normal polling response exposes only:

- `qualityStatus`: `passed`, `best_effort`, `not_scored`, or omitted for legacy;
- `regenerationCount`.

Raw prompts, image bytes and private scene graphs are not exposed to the client.

## Operational controls

```dotenv
VISUAL_CRITIC_ENABLED=true
VISUAL_CRITIC_MAX_REGENERATIONS=1
VISUAL_CRITIC_CAMERA_THRESHOLD=0.78
VISUAL_CRITIC_CHANGE_THRESHOLD=0.72
VISUAL_CRITIC_ENVIRONMENT_THRESHOLD=0.62
VISUAL_CRITIC_ERA_THRESHOLD=0.72
```

Threshold overrides in a V3 request are clamped. The server-level maximum
regeneration count remains the operator authority.

## Validation rules

A SceneGraph is rejected when it has:

- no regions;
- more than 16 regions;
- duplicate or missing IDs;
- invalid normalized boxes;
- missing descriptions or scores.

A TemporalRenderPlan is rejected when it has:

- unknown or duplicate changed region IDs;
- a region in both changed and unchanged lists;
- an unevaluated source region;
- missing target state or causal reason;
- no environmental change for a multi-month or longer scene with environment;
- insufficient changed domains for the time horizon;
- coverage metadata that contradicts actual region changes.

## Remaining client migration

The server implementation is additive. A later iOS migration may display
SceneGraph or RenderPlan diagnostics, but no client change is required for V2
requests to receive V3 planning and compilation today.
