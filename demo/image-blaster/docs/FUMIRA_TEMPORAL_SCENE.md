# FUMIRA Temporal Scene

`image-blaster` remains the upstream asset-orchestration layer. FUMIRA adds a
scene compiler between generated assets and the viewer so the world remains
editable and temporally stable.

## Source of truth

`worlds/<slug>/scene.json` is version `2` and contains `temporalScene`.

- `nodes` are stable canonical entities. Their IDs must survive asset upgrades.
- `position`, `rotation`, `footprint`, `height`, `layer`, and `role` describe
  where an entity belongs in the bounded Y-up sandbox.
- `relations` encode composition and spatial meaning (`occludes`, `supports`,
  `clustered-with`, `behind`, `frames`). They are not UI annotations.
- `anchors` contain only per-year patches. An anchor never replaces a node or
  regenerates the whole scene.

The local `TemporalSandbox` draws clay proxy geometry whenever GLB/SPZ assets
are unavailable. It is therefore safe to inspect the SceneGraph before paying
for World Labs or FAL generation.

## Provider split

```text
source photo / short burst
  -> spatial analysis + SceneGraph
  -> static plate / distant environment (World Labs or future 3DGS provider)
  -> dynamic entity meshes (Hunyuan, SAM 3D, or procedural builders)
  -> clay style normalizer
  -> Canonical Scene + Temporal Patch
  -> Three.js continuous interpolation
```

World Labs and FAL credentials are required only when their corresponding
generation scripts are invoked. They are intentionally not required for the
scene editor, sandbox, tests, or the checked-in FUMIRA street demo.

## Demo

```bash
cd app
npm install --workspaces=false
npm run dev
```

Open `/fumira-beijing-street`. The 2026 → 2080 slider interpolates the same
entity IDs: tree mass grows, the occluded person fades, and the foreground red
moped moves/rotates. It does not regenerate the street at each year.

## Calibration loop (camera-match, not text-guessing)

Nodes may declare `imageBox` (`[x, y, w, h]`, normalized, top-left origin in
the source photo), `visualPriority` (3 = hero anchor … 0 = filler), and
`confidence`. These are the image-space constraints the 3D layout must satisfy.

Click **对照校正** on the timeline to enter calibration mode:

- the render camera locks to the photo camera and pixel-aligns with the
  letterboxed source image (`setViewOffset`);
- the original photo overlays the clay render with an opacity slider;
- every node shows its 2D projection box (orange) next to its declared
  `imageBox` (dashed lime);
- declared relations are re-checked in image space: `occludes` needs box
  overlap plus correct depth order, `behind` needs greater camera distance,
  `supports` needs footprint containment, and the moped cluster must read
  strictly smaller with distance;
- corrections are staged one layer at a time: ① 道路/人行道 ② 树/配电箱/建筑
  ③ 人物 ④ 电动车组;
- the reviewer emits an executable `SceneLayoutPatch` (copyable JSON) whose
  position suggestions come from intersecting the camera ray through the
  declared box bottom-center with the node's ground plane, and whose scale
  suggestions come from the declared/projected box-height ratio.

Apply a patch by copying its `changes` back into the node definitions in
`scene.json` — never by regenerating the scene. The math lives in
`app/src/modules/calibration/projection.ts` and is fully unit-tested.

## Scene Reconstructor master prompt

```text
You are FUMIRA Scene Reconstructor.

Do not output a list of objects.
Reconstruct a bounded clay diorama from the reference image as a Canonical SceneGraph.

For every visible semantic entity, infer:
- image-plane bounding box and visual priority;
- ground footprint, height, orientation, and depth layer;
- support, occlusion, clustering, behind, and framing relations;
- confidence and hidden-geometry assumptions.

First solve fixed-camera composition and depth ordering.
Then create procedural or generated assets.
Render the scene from the matched camera and compare it to the reference.

Do not accept a result because all objects exist.
Accept only when the fixed-camera render preserves:
1. composition,
2. depth and occlusion,
3. silhouette recognizability,
4. relative scale,
5. FUMIRA soft-clay style.

After every review, emit an executable SceneLayoutPatch.
Do not regenerate stable Canonical Entity IDs.

For time evolution, create TemporalEvents and TemporalPatches only.
A year may modify transforms, material state, presence, growth, or introduce a new entity,
but it must preserve declared spatial relations unless an explicit event changes them.
All changes must interpolate continuously between anchors.
```
