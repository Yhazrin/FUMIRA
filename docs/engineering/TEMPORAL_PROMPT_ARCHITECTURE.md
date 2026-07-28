# Temporal Prompt Architecture (PR #1 Reference)

> This design reference is preserved from PR #1. The runnable contract is the
> current `server/src/types.ts`, `server/src/promptCompiler.ts`, and the
> intelligence/queue path. Optional ideas here such as normalized boxes and
> source-date planning are not accepted API fields unless they are added to that
> contract first.

## Product objective

FUMIRA generates the same camera view at another time, not a loosely related
image and not a local edit applied only to the most salient subject.

A successful result satisfies four contracts:

1. **View continuity** — camera position, framing, horizon, perspective and
   spatial topology remain recognizable.
2. **Identity continuity** — persistent subjects keep identity only when
   persistence is physically and narratively plausible.
3. **World evolution** — time propagates through the visible environment rather
   than only one person or object.
4. **Causal realism** — additions, removals, replacements and material changes
   are justified by target time, location and story history.

## Implemented architecture

```text
Source Image
  -> SceneGraph v1
  -> TemporalRenderPlan v1
  -> PromptCompiler V3
  -> Generated Image
  -> VisualCritic v1
  -> Optional Controlled Repair
```

Narrative writing is separated from rendering control. The story may supply
continuity, but the final provider prompt is compiled from a region-addressable
world plan.

## SceneGraph

A SceneGraph records baseline context, camera geometry, 4–16 spatial regions,
global temporal drivers and uncertainty. Regions include stable IDs, screen
zones, optional normalized boxes, depth, semantic category, visible source
state, materials, persistence, temporal policy, confidence and salience.

The temporal policy explicitly distinguishes locked geometry, aging, biological
growth, renovation, era replacement, disappearance and free evolution.

## TemporalRenderPlan

The exact target plan contains:

- program-authoritative target and horizon;
- global era, environment, technology and activity state;
- one action or explicit preserve policy for every source region;
- additions, removals and cross-region couplings;
- subject continuity mode;
- prohibited drift and coverage diagnostics.

Every changed region has an action, magnitude, target state, causal reason and
visible evidence. A region cannot be both changed and unchanged.

## Time horizons

| Horizon | Primary visual processes |
|---|---|
| hours–days | light, weather, temporary objects, people and traffic |
| months | season, vegetation state, temporary construction and decoration |
| years | wear, maintenance, vehicles, shops, signage and incremental growth |
| decades | human aging, mature vegetation, renewal and technology turnover |
| centuries | rebuilding, ruins, ecological succession and cultural replacement |
| millennia | climate, geomorphology, archaeology and civilizational discontinuity |
| deep time | geology and ecology; short-lived modern subjects are released |

## Subject continuity

- `identity_persists`
- `age_progression`
- `lineage_or_successor`
- `object_remains`
- `site_only`
- `time_traveler`

Deep-time ordinary scenes default to site continuity. A modern object crossing
geological time must be an explicit anomaly such as `time_traveler`.

## Prompt compilation

PromptCompiler V3 emits:

1. target;
2. camera lock;
3. continuity;
4. region contract;
5. world coherence;
6. prohibited drift.

All changed and unchanged region IDs survive before optional prose receives
budget. Bounding boxes are included when available. Extreme 16-region scenes
use a compact emergency contract under the 1,500-character provider limit.

## Visual critic

The generated image is analyzed into a second SceneGraph and compared with the
source graph and target plan. The critic scores camera, topology, identity,
required changes, environment evolution and era coherence, and identifies exact
missed region IDs, unexplained changes and camera drift.

A failing result may receive one controlled repair. The original source remains
the reference, successful regions are preserved, only failures are corrected,
and the higher-scoring candidate is retained.

## Compatibility

Existing `generation.v2` clients are upgraded before queueing. Source-image
SceneGraphs and exact plans are cached by immutable inputs. Provider degradation
uses a deterministic typed plan and never restores the flat story-only prompt.

`sourceDateISO` is optional; without it, relative time is authoritative and the
server current date is not presented as the photograph's source era.
