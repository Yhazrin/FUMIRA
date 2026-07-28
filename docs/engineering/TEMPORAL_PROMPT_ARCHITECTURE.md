# Temporal Prompt Architecture

## Product objective

FUMIRA must generate the **same camera view at another time**, not a loosely
related image and not a local edit applied only to the most salient person or
object.

A successful generation satisfies four contracts simultaneously:

1. **View continuity** — camera position, framing, horizon, perspective and
   major spatial topology remain recognizable.
2. **Identity continuity** — persistent principal subjects retain identity when
   persistence is physically and narratively plausible.
3. **World evolution** — time propagates through the entire visible scene,
   including environmental systems rather than only one subject.
4. **Causal realism** — every addition, removal, replacement or material change
   is justified by the target time, location and story history.

## Current V2.1 behavior

The shipped V2 payload remains unchanged for iOS compatibility, but the backend
now treats its fields differently:

- VLM `subjects` entries act as a compact map of principal subjects and
  environmental anchors across visible depth layers.
- `targetBeat` is mandatory and exact. Canonical beats are browsing nodes only.
- The compiler reserves compact forms of temporal change, scene coverage and
  temporal realism before optional prose receives prompt budget.
- Composition preservation no longer means freezing subject count or forbidding
  all new buildings, vehicles or vegetation.
- Exact browse-year generation receives the existing story context.

This is a compatibility hardening step, not the final representation.

## Why a SceneGraph V3 is needed

The current payload combines three incompatible concerns:

- concise text displayed in the UI;
- a partial scene description;
- machine-facing image-generation instructions.

Character limits appropriate for UI copy remove details required for reliable
rendering. A single `visualPrompt` cannot explicitly describe foreground,
midground, background, temporal permissions and cross-region consistency.

V3 separates human-readable narrative from machine-readable world state.

## Proposed schemas

### Generation context

```ts
interface GenerationContextV3 {
  schemaVersion: "generation-context.v3";
  sceneGraph: SceneGraph;
  temporalStory: TemporalStoryV3;
  targetPlan: TemporalRenderPlan;
  generationMode:
    | "captured_target"
    | "story_preview_target"
    | "regenerate_same_target";
}
```

### Scene graph

```ts
interface SceneGraph {
  baseline: {
    locationType: string;
    probableCaptureEra?: string;
    season?: string;
    timeOfDay?: string;
    weather?: string;
    culturalContext?: string;
  };

  cameraLock: {
    viewpoint: string;
    framing: string;
    horizon: string;
    perspective: string;
    vanishingPoints: string[];
    depthLayout: string;
  };

  regions: SceneRegion[];
  globalDrivers: TemporalDriver[];
  uncertainties: string[];
}
```

### Scene region

```ts
interface SceneRegion {
  id: string;
  depth: "foreground" | "midground" | "background" | "sky";
  category:
    | "person"
    | "animal"
    | "vehicle"
    | "vegetation"
    | "architecture"
    | "infrastructure"
    | "surface"
    | "signage"
    | "furniture"
    | "landscape"
    | "atmosphere"
    | "other";

  description: string;
  spatialAnchor: string;
  materials: string[];
  currentCondition: string;
  confidence: number;
  salience: number;

  temporalPolicy:
    | "lock_geometry"
    | "age_in_place"
    | "evolve"
    | "replace_by_era"
    | "may_disappear"
    | "transient";
}
```

The `temporalPolicy` is the key distinction missing from V2. It prevents one
blanket instruction such as “preserve all subjects” from being applied to
landmarks, people, vehicles, trees and passersby alike.

### Temporal render plan

```ts
interface TemporalRenderPlan {
  schemaVersion: "temporal-render-plan.v1";
  exactTarget: ExactTarget;

  horizonBand:
    | "hours_days"
    | "months"
    | "years"
    | "decades"
    | "centuries"
    | "millennia"
    | "deep_time";

  globalEraState: string;
  regionChanges: RegionTemporalChange[];
  crossRegionCouplings: string[];
  mustPreserve: string[];
  allowedEraAdditions: string[];
  prohibitedDrift: string[];

  coverage: {
    foreground: boolean;
    midground: boolean;
    background: boolean;
    principalSubject: boolean;
    builtEnvironment: boolean;
    naturalEnvironment: boolean;
    technologyInfrastructure: boolean;
  };
}
```

### Per-region change

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
  targetAppearance: string;
  causalReason: string;
}
```

## Pipeline separation

### Stage A — scene analysis

The VLM describes visible evidence and spatial structure only. It does not write
story prose or guess a desired emotional ending.

Required behavior:

- inspect foreground, midground, background and sky;
- identify surfaces, architecture, vegetation, infrastructure, vehicles,
  signage and atmosphere when visible;
- distinguish persistent anchors from transient entities;
- assign temporal policies;
- state uncertainty instead of inventing hidden facts.

### Stage B — temporal world planning

A planning model receives `SceneGraph + ExactTarget + story continuity` and
produces `TemporalRenderPlan`.

Required behavior:

- map every temporal driver to concrete regions;
- include an environmental change unless the interval is too short;
- cover all visible depth layers when change is plausible;
- keep changed domains in the same era;
- attach a causal reason to every change;
- explicitly preserve regions that should not change.

### Stage C — narrative copy

A story model turns approved world plans into concise user-facing copy. It does
not decide rendering details.

Suggested beat fields:

```ts
interface StoryBeatV3 {
  anchor: ExactTarget | CanonicalAnchor;
  title: string;
  worldEvent: string;
  visibleEvidence: string[];
  emotionalEcho: string;
  narrativeCopy: string;
  renderPlanId: string;
}
```

### Stage D — prompt compilation

The compiler serializes the target render plan for a specific provider. Provider
adapters may use different wording, ordering and budgets, while consuming the
same semantic plan.

Semantic priority:

1. exact target and edit objective;
2. camera geometry;
3. required region changes;
4. scene-wide coverage;
5. persistent identity;
6. cross-region era coherence;
7. justified additions and removals;
8. negative drift constraints;
9. optional narrative tone.

### Stage E — visual critic

After generation, a VLM compares:

- source image;
- generated image;
- target render plan.

Suggested result:

```ts
interface VisualCriticResult {
  compositionConsistency: number;
  principalIdentityConsistency: number;
  temporalChangeCoverage: number;
  environmentEvolution: number;
  eraCoherence: number;
  unexplainedAdditions: string[];
  missedRequiredChanges: string[];
}
```

A result with high composition consistency but low environment evolution is the
classic failure mode where only the person changed. The missing region changes
can be appended to a controlled regeneration prompt.

## Time-horizon policy

| Horizon | Primary visual processes |
|---|---|
| hours–days | light, weather, temporary objects, people and traffic |
| months | season, vegetation state, temporary construction, decoration |
| 1–5 years | wear, maintenance, vehicles, shops, signage, incremental growth |
| 5–30 years | human aging, mature vegetation, material renewal, technology turnover |
| 30–100 years | rebuilding, infrastructure replacement, urban density, generations |
| 100–1000 years | ruins, reconstruction, ecological succession, cultural replacement |
| millennia | climate, geomorphology, archaeology, civilizational discontinuity |
| deep time | geology and ecology; short-lived subjects persist only as explicit anomalies |

## Special continuity modes

Very long intervals require an explicit subject policy:

```ts
type SubjectContinuityMode =
  | "identity_persists"
  | "lineage_or_successor"
  | "object_remains"
  | "site_only"
  | "time_traveler";
```

For example, a present-day car surviving millions of years is not normal world
evolution. It should be represented as `time_traveler`, allowing the environment
to obey deep-time physics while the car remains an intentional anomaly.

## Evaluation suite

The repository should maintain representative source scenes:

- single portrait in an environment;
- crowded street;
- station or transport hub;
- indoor room;
- natural landscape;
- dominant vehicle;
- landmark architecture;
- sparse scene with little visible context;
- century, millennium and deep-time targets.

Each fixture should assert:

- exact-target identity;
- required depth-layer coverage;
- at least one non-principal environmental change when appropriate;
- absence of contradictory preserve/change rules;
- prompt budget compliance;
- visual critic thresholds after live-model evaluation.

## Migration plan

### Phase 1 — shipped in V2 compatibility layer

- required scene-wide compiler sections;
- strict exact target;
- continuity-aware browse-year planning;
- time-horizon guidance;
- regression tests for subject-only change failures.

### Phase 2 — additive V3 server contract

- add `generation-context.v3` and SceneGraph types;
- keep V2 routes operational;
- let the backend derive a provisional SceneGraph from V2 fields when needed;
- store render-plan diagnostics without exposing raw prompts.

### Phase 3 — client adoption

- iOS consumes separate narrative copy and render-plan metadata;
- target regeneration references immutable `renderPlanId`;
- UI copy limits no longer truncate machine-facing instructions.

### Phase 4 — visual critic loop

- score every generated image;
- retry only when a controlled threshold fails;
- record failure categories for prompt and model A/B evaluation.
