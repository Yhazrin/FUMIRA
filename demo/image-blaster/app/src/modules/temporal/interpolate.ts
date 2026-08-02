import type { FumiraTemporalScene, TemporalNodePatch, TemporalSceneNode, Vec3Tuple } from '../../types/world'

export interface InterpolatedTemporalNode extends TemporalSceneNode {
  rotation: Vec3Tuple
  scale: Vec3Tuple
  opacity: number
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value))
}

function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t
}

function lerpVec3(a: Vec3Tuple, b: Vec3Tuple, t: number): Vec3Tuple {
  return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)]
}

function patchFor(scene: FumiraTemporalScene, nodeId: string, year: number): TemporalNodePatch {
  const anchors = [...scene.anchors].sort((a, b) => a.year - b.year)
  const first = anchors[0]
  const last = anchors[anchors.length - 1]
  if (!first || !last) return {}
  if (year <= first.year) return first.patches[nodeId] ?? {}
  if (year >= last.year) return last.patches[nodeId] ?? {}

  let before = first
  let after = last
  for (let index = 0; index < anchors.length - 1; index += 1) {
    if (anchors[index].year <= year && year <= anchors[index + 1].year) {
      before = anchors[index]
      after = anchors[index + 1]
      break
    }
  }

  const t = clamp((year - before.year) / (after.year - before.year), 0, 1)
  const a = before.patches[nodeId] ?? {}
  const b = after.patches[nodeId] ?? {}
  const result: TemporalNodePatch = {}
  if (a.position || b.position) result.position = lerpVec3(a.position ?? b.position!, b.position ?? a.position!, t)
  if (a.rotation || b.rotation) result.rotation = lerpVec3(a.rotation ?? b.rotation!, b.rotation ?? a.rotation!, t)
  if (a.scale || b.scale) result.scale = lerpVec3(a.scale ?? b.scale!, b.scale ?? a.scale!, t)
  if (a.opacity !== undefined || b.opacity !== undefined) result.opacity = lerp(a.opacity ?? b.opacity ?? 1, b.opacity ?? a.opacity ?? 1, t)
  return result
}

export function interpolateTemporalNode(
  scene: FumiraTemporalScene,
  node: TemporalSceneNode,
  year: number,
): InterpolatedTemporalNode {
  const patch = patchFor(scene, node.id, year)
  return {
    ...node,
    position: patch.position ?? node.position,
    rotation: patch.rotation ?? node.rotation ?? [0, 0, 0],
    scale: patch.scale ?? node.scale ?? [1, 1, 1],
    opacity: patch.opacity ?? 1,
  }
}

export function timelineRange(scene: FumiraTemporalScene): [number, number] {
  const years = scene.anchors.map((anchor) => anchor.year)
  return [Math.min(...years), Math.max(...years)]
}
