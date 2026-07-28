# PR #1 Temporal V3 Design Reference

> This document is retained as the implementation design carried by PR #1. Its
> standalone `GenerationContextV3` modules use a different wire schema from the
> current iOS-backed V3 contract, so it is not the runtime API reference. See
> `AI_PIPELINE_API.md`, `server/src/types.ts`, and `server/src/promptCompiler.ts`
> for the implementation currently exercised by the application.

## Status

This document records the complete V3 design from the
`prompt-v3-scene-evolution` branch and PR #1. Its scene-wide prompt coverage,
exact-target integrity, time-horizon behavior, and visual-critic goals are
absorbed by the current pipeline; the branch's parallel runtime modules are
kept in Git history rather than run beside the existing schema.

```text
source image
  -> SceneGraph v1
  -> exact TemporalRenderPlan v1
  -> PromptCompiler V3
  -> MiniMax image-01
  -> generated-image SceneGraph
  -> VisualCritic v1
  -> optional single correction generation
```

The core architectural rule is:

> Narrative copy explains the world to the user. A structured render plan tells
> the image model what each visible region must do.

## V2 clients receive V3 behavior

An existing iOS request using `contextVersion: generation.v2` is upgraded before
queueing:

1. The server analyzes the original uploaded image with the V3 SceneGraph VLM.
2. If live graph analysis fails, the V2 understanding payload is expanded into
   a conservative typed graph.
3. The server sends `SceneGraph + ExactTarget + story continuity` to the
   temporal planner.
4. If live planning fails or validation rejects the result, a deterministic
   region-by-region plan is produced.
5. The request is internally converted to `generation.v3`.
6. PromptCompiler V3 compiles region actions for `image-01`.

The old flat story prompt is therefore not used for any structured generation,
even during provider degradation.

## Immutable preparation cache

The process keeps bounded caches for:

- SceneGraph by `sourceAssetId`;
- TemporalRenderPlan by source asset, exact target, graph and story continuity.

A repeated `regenerate_same_target` request with the same immutable inputs reuses
the same plan and `planId`. It does not ask the planner to reinterpret the world.
The cache is bounded to 128 prepared contexts per process.

## Source time baseline

`offsetDays` is the authoritative temporal distance. `sourceDateISO` is optional:

```json
{
  "offsetDays": 9131.25,
  "offsetYears": 25,
  "compactLabel": "25 年后",
  "sourceDateISO": "2010-07-28"
}
```

When the source date is known, the target calendar date is calculated from the
photograph's capture time. When it is unknown, the final image prompt states only
the relative offset. This prevents a scanned 1990 photograph from being treated
as though it was captured on the server's current date.

## SceneGraph v1

The live VLM creates 4–16 regions covering visible foreground, midground,
background and sky.

```ts
interface SceneRegion {
  id: string;
  screenZone: ScreenZone;
  boundingBox?: NormalizedBox;
  depth: SceneDepth;
  category: SceneCategory;
  sourceState: {
    description: string;
    materials: string[];
    condition: string;
    identityFeatures: string[];
  };
  persistence: RegionPersistence;
  temporalPolicy: TemporalPolicy;
  confidence: number;
  salience: number;
}
```

Persistence and temporal policy are separate because the following are not the
same kind of continuity:

- a person's identity;
- a station building's spatial geometry;
- a tree's planting position;
- a passing vehicle;
- replaceable signage;
- a temporary pedestrian.

Temporal policies:

- `lock`
- `age_in_place`
- `grow`
- `renovate`
- `replace_by_era`
- `may_disappear`
- `free_evolution`

The analyzer treats visible image text as untrusted scene content and does not
follow instructions embedded in signs, screens or posters.

## TemporalRenderPlan v1

Every source region must be evaluated exactly once.

```ts
interface RegionTemporalChange {
  regionId: string;
  action:
    | "preserve"
    | "age"
    | "grow"
    | "renovate"
    | "replace"
    | "remove"
    | "add_related";
  magnitude: "subtle" | "moderate" | "major" | "transformative";
  targetState: string;
  causalReason: string;
  visibleEvidence: string[];
}
```

A region appears either in `regionChanges` or `unchangedRegionIds`, never both.
Validation rejects:

- unknown or duplicate region IDs;
- contradictory changed/unchanged policies;
- unevaluated regions;
- missing target state or causal reason;
- no environmental change for a multi-month or longer scene containing an
  environment;
- insufficient changed domains for the horizon;
- coverage metadata that contradicts actual actions.

The plan also contains:

- exact target and time horizon;
- global environmental, technology and activity state;
- justified additions and removals;
- cross-region material and era couplings;
- prohibited drift;
- explicit coverage diagnostics.

## Time-horizon behavior

| Horizon | Primary processes |
|---|---|
| hours–days | light, weather, temporary activity and traffic |
| months | season, vegetation state, decoration and temporary construction |
| years | wear, maintenance, vehicles, shops and incremental growth |
| decades | human aging, mature vegetation, renovation and technology turnover |
| centuries | rebuilding, ruins, ecological succession and cultural replacement |
| millennia | climate, geomorphology, archaeology and civilizational discontinuity |
| deep time | geology and ecology; modern short-lived subjects are released |

The planner evaluates every region but does not force every region to change.
Stable regions are explicitly preserved.

## Subject continuity

Modes:

- `identity_persists`
- `age_progression`
- `lineage_or_successor`
- `object_remains`
- `site_only`
- `time_traveler`

Examples:

- person, 20 years later → `age_progression`;
- person, 500 years later → `lineage_or_successor` or `site_only`;
- Xiaomi SU7 intentionally crossing geological time → `time_traveler`;
- ordinary street one million years later → `site_only`.

MiniMax `subject_reference` is a strong portrait-style identity constraint. The
server suppresses it for `site_only` and `lineage_or_successor` at both the
preparation layer and provider boundary, even when an older client requests it.

## PromptCompiler V3

Required sections:

1. `TARGET`
2. `CAMERA LOCK`
3. `CONTINUITY`
4. `REGION EDITS`
5. `WORLD COHERENCE`
6. `PROHIBITED`

Example:

```text
R4 middle_right/background/architecture -> RENOVATE major:
retain location and recognizable volume; update facade and accessibility
infrastructure; cause: one long maintenance and renewal cycle
```

Budget behavior:

1. Fixed constraints are deliberately compact.
2. Every changed region first receives a compact action line.
3. Only after all region IDs survive does the compiler expand high-salience
   regions with more target-state detail.
4. Optional couplings, additions, coverage and uncertainty are admitted last.
5. Extreme scenes use an emergency format that retains all 16 region IDs,
   camera lock, coherence and prohibitions under 1,500 characters.

Untrusted model strings are sanitized before compilation. Angle-bracket
boundaries, null bytes and control characters are not passed through unchanged.

## VisualCritic v1

After a successful image generation:

1. the result is analyzed into another SceneGraph;
2. source graph, generated graph and target plan are compared;
3. scores and exact missed target region IDs are returned.

Scores:

- camera consistency;
- spatial topology consistency;
- principal identity consistency;
- required change completion;
- environmental evolution;
- era coherence.

A visually polished output still fails when the person changes but planned
architecture, vegetation, surfaces or background remain frozen.

## Controlled repair

When thresholds fail and one retry is allowed:

- the original source image remains the generation reference;
- successful camera and regions are explicitly preserved;
- only missed region IDs and detected camera drift are appended as corrections;
- the repaired image is analyzed again;
- the higher weighted critic score is retained.

The retry is corrective, not a new random story or a new render plan.

## Operational controls

```dotenv
VISUAL_CRITIC_ENABLED=true
VISUAL_CRITIC_MAX_REGENERATIONS=1
VISUAL_CRITIC_CAMERA_THRESHOLD=0.78
VISUAL_CRITIC_CHANGE_THRESHOLD=0.72
VISUAL_CRITIC_ENVIRONMENT_THRESHOLD=0.62
VISUAL_CRITIC_ERA_THRESHOLD=0.72
```

Request-level threshold overrides are clamped. The server-level maximum retry
count remains authoritative.

## Observability

Generation records store:

- prompt compiler version and hash;
- section character counts and compacted sections;
- immutable `renderPlanId`;
- critic scores and failure lists;
- regeneration count;
- duration and provider error metadata.

Client polling exposes `qualityStatus` and `regenerationCount`. Full plan and
critic diagnostics remain admin-only. Raw prompts and image bytes are not logged.

## Implemented tests

The branch includes regressions for:

- exact target strictness;
- required whole-scene prompt sections;
- typed V2-to-V3 conversion;
- non-person environmental evolution;
- contradictory region policies;
- deep-time continuity;
- all 16 region IDs surviving prompt budgeting;
- prompt-boundary/control-character sanitization;
- controlled critic repair prompts;
- visual critic threshold behavior;
- trusted source-date handling.

## Current external limitation

The repository's GitHub Actions job currently terminates before it exposes any
workflow steps, logs or the configured always-uploaded diagnostics artifact. The
PR remains intentionally unmerged until the repository/runner issue is resolved
or the branch is validated in a working Node 20 environment.
