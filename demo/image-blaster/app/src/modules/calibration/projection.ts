import * as THREE from 'three'
import type { FumiraTemporalScene, TemporalSceneNode, Vec3Tuple } from '../../types/world'
import { interpolateTemporalNode, type InterpolatedTemporalNode } from '../temporal/interpolate'

/**
 * Fixed-photo-camera calibration engine.
 *
 * Everything here is pure math over the scene JSON: project every canonical
 * node back into the source image plane, compare it against the declared
 * imageBox / relations, and emit an executable SceneLayoutPatch. This is the
 * "camera-match" loop that turns text-guessed blockouts into image-verified
 * layouts.
 */

export interface ImageRect {
  x: number
  y: number
  width: number
  height: number
}

/** Normalized [x, y, width, height], top-left origin, image space. */
export type NormalizedBox = [number, number, number, number]

export interface ProjectedNode {
  node: InterpolatedTemporalNode
  box: NormalizedBox
  /** Camera distance to the node's mid-height center. */
  distance: number
  visible: boolean
}

export type CalibrationStage = 0 | 1 | 2 | 3

export const CALIBRATION_STAGES: { stage: CalibrationStage; label: string }[] = [
  { stage: 0, label: '道路 / 人行道' },
  { stage: 1, label: '树 · 配电箱 · 建筑' },
  { stage: 2, label: '人物' },
  { stage: 3, label: '电动车组' },
]

export function stageOfNode(node: TemporalSceneNode): CalibrationStage {
  if (node.kind === 'road' || (node.kind === 'prop' && node.role === 'support')) return 0
  if (node.kind === 'person') return 2
  if (node.kind === 'moped') return 3
  return 1
}

export type CalibrationIssueKind = 'layout' | 'scale' | 'occlusion' | 'depth-order' | 'support' | 'anchor'

export interface CalibrationIssue {
  kind: CalibrationIssueKind
  stage: CalibrationStage
  nodeIds: string[]
  severity: number
  message: string
}

export interface SceneEvaluation {
  projections: ProjectedNode[]
  issues: CalibrationIssue[]
}

export interface LayoutPatchChange {
  id: string
  position?: Vec3Tuple
  scale?: Vec3Tuple
}

export interface SceneLayoutPatch {
  type: 'layout-patch'
  year: number
  stage: CalibrationStage
  reason: string
  changes: LayoutPatchChange[]
}

/** Contain-fit the photo rect inside the viewport (letterboxed). */
export function computeImageRect(viewportWidth: number, viewportHeight: number, imageAspect: number): ImageRect {
  const viewportAspect = viewportWidth / viewportHeight
  if (viewportAspect >= imageAspect) {
    const height = viewportHeight
    const width = height * imageAspect
    return { x: (viewportWidth - width) / 2, y: 0, width, height }
  }
  const width = viewportWidth
  const height = width / imageAspect
  return { x: 0, y: (viewportHeight - height) / 2, width, height }
}

export function photoCamera(scene: FumiraTemporalScene, imageAspect: number): THREE.PerspectiveCamera {
  const camera = new THREE.PerspectiveCamera(scene.camera.fov, imageAspect, 0.1, 200)
  camera.position.set(...scene.camera.position)
  camera.lookAt(...scene.camera.target)
  camera.updateMatrixWorld(true)
  camera.updateProjectionMatrix()
  return camera
}

const CORNER_SIGNS: [number, number, number][] = [
  [-1, 0, -1], [1, 0, -1], [-1, 0, 1], [1, 0, 1],
  [-1, 1, -1], [1, 1, -1], [-1, 1, 1], [1, 1, 1],
]

export function projectNode(camera: THREE.PerspectiveCamera, node: InterpolatedTemporalNode): ProjectedNode {
  const width = node.footprint[0] * node.scale[0]
  const depth = node.footprint[1] * node.scale[2]
  const height = node.height * node.scale[1]
  const rotation = new THREE.Euler(...node.rotation)
  const position = new THREE.Vector3(...node.position)

  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  let behindCamera = false
  const corner = new THREE.Vector3()
  const viewSpace = new THREE.Vector3()
  for (const [sx, sy, sz] of CORNER_SIGNS) {
    corner.set((sx * width) / 2, sy * height, (sz * depth) / 2)
    corner.applyEuler(rotation).add(position)
    viewSpace.copy(corner).applyMatrix4(camera.matrixWorldInverse)
    if (viewSpace.z > -0.1) behindCamera = true
    corner.project(camera)
    const ix = (corner.x + 1) / 2
    const iy = (1 - corner.y) / 2
    minX = Math.min(minX, ix)
    minY = Math.min(minY, iy)
    maxX = Math.max(maxX, ix)
    maxY = Math.max(maxY, iy)
  }

  const center = new THREE.Vector3(0, height / 2, 0).applyEuler(rotation).add(position)
  const box: NormalizedBox = [minX, minY, maxX - minX, maxY - minY]
  const onScreen = maxX > 0 && minX < 1 && maxY > 0 && minY < 1
  return {
    node,
    box,
    distance: camera.position.distanceTo(center),
    visible: node.opacity > 0.01 && onScreen && !behindCamera,
  }
}

function boxOverlapArea(a: NormalizedBox, b: NormalizedBox): number {
  const x = Math.max(0, Math.min(a[0] + a[2], b[0] + b[2]) - Math.max(a[0], b[0]))
  const y = Math.max(0, Math.min(a[1] + a[3], b[1] + b[3]) - Math.max(a[1], b[1]))
  return x * y
}

function boxCenter(box: NormalizedBox): [number, number] {
  return [box[0] + box[2] / 2, box[1] + box[3] / 2]
}

function footprintContains(support: InterpolatedTemporalNode, supported: InterpolatedTemporalNode): boolean {
  const halfW = (support.footprint[0] * support.scale[0]) / 2 + 0.15
  const halfD = (support.footprint[1] * support.scale[2]) / 2 + 0.15
  const dx = supported.position[0] - support.position[0]
  const dz = supported.position[2] - support.position[2]
  return Math.abs(dx) <= halfW && Math.abs(dz) <= halfD
}

const LAYER_RANK = { foreground: 0, midground: 1, background: 2 } as const

export function evaluateScene(scene: FumiraTemporalScene, year: number, imageAspect: number): SceneEvaluation {
  const camera = photoCamera(scene, imageAspect)
  const projections = scene.nodes.map((node) => projectNode(camera, interpolateTemporalNode(scene, node, year)))
  const byId = new Map(projections.map((projected) => [projected.node.id, projected]))
  const issues: CalibrationIssue[] = []

  // 1. Frame layout + relative scale against the declared imageBox.
  for (const projected of projections) {
    const declared = projected.node.imageBox
    if (!declared || !projected.visible) continue
    const [projectedCx, projectedCy] = boxCenter(projected.box)
    const [declaredCx, declaredCy] = boxCenter(declared)
    const centerOffset = Math.hypot(projectedCx - declaredCx, projectedCy - declaredCy)
    const stage = stageOfNode(projected.node)
    if (centerOffset > 0.05) {
      issues.push({
        kind: 'layout',
        stage,
        nodeIds: [projected.node.id],
        severity: Math.min(1, centerOffset * 3),
        message: `${projected.node.id} 偏离原图位置 ${(centerOffset * 100).toFixed(0)}% 画幅`,
      })
    }
    const sizeRatio = declared[3] > 0 ? projected.box[3] / declared[3] : 1
    if (sizeRatio < 0.72 || sizeRatio > 1.4) {
      issues.push({
        kind: 'scale',
        stage,
        nodeIds: [projected.node.id],
        severity: Math.min(1, Math.abs(Math.log2(sizeRatio))),
        message: `${projected.node.id} 投影高度是原图标注的 ${(sizeRatio * 100).toFixed(0)}%`,
      })
    }
  }

  // 1b. Measured pixel anchors: the projected box must cover the anchor point.
  // An offscreen projection is the worst violation, not an exemption.
  for (const projected of projections) {
    const anchor = projected.node.imageAnchor
    if (!anchor) continue
    const [ax, ay] = anchor.point
    const [px, py, pw, ph] = projected.box
    const inside = projected.visible && ax >= px && ax <= px + pw && ay >= py && ay <= py + ph
    if (!inside) {
      const [centerX, centerY] = boxCenter(projected.box)
      const offset = projected.visible ? Math.hypot(ax - centerX, ay - centerY) : 1
      issues.push({
        kind: 'anchor',
        stage: stageOfNode(projected.node),
        nodeIds: [projected.node.id],
        severity: Math.min(1, offset * 3) * anchor.confidence,
        message: projected.visible
          ? `${projected.node.id} 投影未覆盖实测像素锚点 (${ax.toFixed(2)}, ${ay.toFixed(2)})`
          : `${projected.node.id} 完全在画面外，但有实测像素锚点 (${ax.toFixed(2)}, ${ay.toFixed(2)})`,
      })
    }
  }

  // 2. Declared relations: occlusion, behind, support.
  for (const relation of scene.relations) {
    const from = byId.get(relation.from)
    const to = byId.get(relation.to)
    if (!from || !to || !from.visible || !to.visible) continue
    if (relation.type === 'occludes') {
      if (boxOverlapArea(from.box, to.box) <= 0) {
        issues.push({
          kind: 'occlusion',
          stage: stageOfNode(to.node),
          nodeIds: [relation.from, relation.to],
          severity: relation.strength,
          message: `${relation.from} 未遮挡 ${relation.to}（投影框无重叠）`,
        })
      } else if (from.distance >= to.distance) {
        issues.push({
          kind: 'occlusion',
          stage: stageOfNode(to.node),
          nodeIds: [relation.from, relation.to],
          severity: relation.strength,
          message: `${relation.from} 未遮挡 ${relation.to}（${relation.from} 反而更远）`,
        })
      }
    }
    if (relation.type === 'behind' && from.distance <= to.distance) {
      issues.push({
        kind: 'depth-order',
        stage: stageOfNode(from.node),
        nodeIds: [relation.from, relation.to],
        severity: relation.strength,
        message: `${relation.from} 应位于 ${relation.to} 之后，但当前更近`,
      })
    }
    if (relation.type === 'supports' && !footprintContains(from.node, to.node)) {
      issues.push({
        kind: 'support',
        stage: stageOfNode(to.node),
        nodeIds: [relation.to, relation.from],
        severity: relation.strength,
        message: `${relation.to} 未落在 ${relation.from} 的占地范围内`,
      })
    }
  }

  // 3. Perspective queue inside the moped cluster: nearer must read bigger.
  const mopeds = projections
    .filter((projected) => projected.node.kind === 'moped' && projected.visible)
    .sort((a, b) => a.distance - b.distance)
  for (let index = 0; index < mopeds.length - 1; index += 1) {
    const near = mopeds[index]
    const far = mopeds[index + 1]
    if (far.box[3] > near.box[3] * 1.05) {
      issues.push({
        kind: 'depth-order',
        stage: 3,
        nodeIds: [near.node.id, far.node.id],
        severity: 0.8,
        message: `moped cluster 深度排序错误：${far.node.id} 更远但画面中更大`,
      })
    }
    if (LAYER_RANK[near.node.layer] > LAYER_RANK[far.node.layer]) {
      issues.push({
        kind: 'depth-order',
        stage: 3,
        nodeIds: [near.node.id, far.node.id],
        severity: 0.6,
        message: `${near.node.id} 声明为 ${near.node.layer}，但比 ${far.node.id} 更靠近相机`,
      })
    }
  }

  issues.sort((a, b) => b.severity - a.severity)
  return { projections, issues }
}

function round2(value: number): number {
  return Math.round(value * 100) / 100
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value))
}

/**
 * Emit an executable patch for one calibration stage only. Position
 * suggestions come from intersecting the camera ray through the declared
 * imageBox bottom-center with the node's ground plane; scale suggestions come
 * from the declared vs projected box-height ratio.
 */
export function buildLayoutPatch(
  scene: FumiraTemporalScene,
  year: number,
  imageAspect: number,
  stage: CalibrationStage,
  options: { minConfidence?: number } = {},
): SceneLayoutPatch | null {
  const minConfidence = options.minConfidence ?? 0
  const camera = photoCamera(scene, imageAspect)
  const evaluation = evaluateScene(scene, year, imageAspect)
  const stageIssues = evaluation.issues.filter((issue) => issue.stage === stage)
  const flagged = new Set(stageIssues.flatMap((issue) => issue.nodeIds))
  const changes: LayoutPatchChange[] = []

  for (const projected of evaluation.projections) {
    const node = projected.node
    if (stageOfNode(node) !== stage || !flagged.has(node.id)) continue
    const anchor = node.imageAnchor
    const anchorTrusted = Boolean(anchor && anchor.confidence >= minConfidence)
    const boxTrusted = Boolean(node.imageBox && (node.confidence ?? 1) >= minConfidence)
    if (!anchorTrusted && !boxTrusted) continue
    const change: LayoutPatchChange = { id: node.id }

    // Position: prefer the measured anchor ray at the anchor's height plane,
    // otherwise the declared box bottom-center on the ground plane.
    let imagePoint: [number, number] | null = null
    let planeHeight = node.position[1]
    if (anchorTrusted && anchor) {
      imagePoint = anchor.point
      planeHeight = node.position[1] + (anchor.heightFactor ?? 0.5) * node.height * node.scale[1]
    } else if (node.imageBox) {
      const [dx, dy, dw, dh] = node.imageBox
      imagePoint = [dx + dw / 2, dy + dh]
    }
    if (imagePoint) {
      const ndc = new THREE.Vector2(imagePoint[0] * 2 - 1, 1 - imagePoint[1] * 2)
      const raycaster = new THREE.Raycaster()
      raycaster.setFromCamera(ndc, camera)
      const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -planeHeight)
      const hit = new THREE.Vector3()
      if (raycaster.ray.intersectPlane(plane, hit)) {
        const next: Vec3Tuple = [round2(hit.x), node.position[1], round2(hit.z)]
        const moved = Math.hypot(next[0] - node.position[0], next[2] - node.position[2])
        const inBounds = Math.abs(next[0]) <= scene.bounds.width && Math.abs(next[2]) <= scene.bounds.depth
        if (moved > 0.12 && inBounds) change.position = next
      }
    }

    // Scale: only a trusted full imageBox may drive size (mask centroids underestimate extents).
    if (boxTrusted && node.imageBox) {
      const dh = node.imageBox[3]
      const ratio = dh > 0 && projected.box[3] > 0 ? clampNumber(dh / projected.box[3], 0.6, 1.6) : 1
      if (Math.abs(ratio - 1) > 0.08) {
        change.scale = [round2(node.scale[0] * ratio), round2(node.scale[1] * ratio), round2(node.scale[2] * ratio)]
      }
    }

    if (change.position || change.scale) changes.push(change)
  }

  // Relation repair: when a declared occlusion/behind relation is violated and
  // the offending node has no trusted image evidence, push it back along the
  // camera's ground ray until it sits behind its reference. Screen column is
  // roughly preserved; only depth changes. Evidence-driven moves take priority.
  const projectedById = new Map(evaluation.projections.map((entry) => [entry.node.id, entry]))
  const alreadyChanged = new Set(changes.map((change) => change.id))
  const pushBehind = (mover: ProjectedNode, reference: ProjectedNode) => {
    const node = mover.node
    if (alreadyChanged.has(node.id)) return
    const anchorTrusted = Boolean(node.imageAnchor && node.imageAnchor.confidence >= minConfidence)
    const boxTrusted = Boolean(node.imageBox && (node.confidence ?? 1) >= minConfidence)
    if (anchorTrusted || boxTrusted) return
    const camGround = new THREE.Vector3(camera.position.x, 0, camera.position.z)
    const ground = new THREE.Vector3(node.position[0], 0, node.position[2])
    const direction = ground.clone().sub(camGround)
    if (direction.lengthSq() < 1e-6) return
    direction.normalize()
    const midHeight = node.position[1] + (node.height * node.scale[1]) / 2
    const target = reference.distance * 1.04
    const probe = new THREE.Vector3()
    for (let step = 0.25; step <= 6; step += 0.25) {
      probe.copy(ground).addScaledVector(direction, step)
      if (Math.abs(probe.x) > scene.bounds.width || Math.abs(probe.z) > scene.bounds.depth) return
      const distance = camera.position.distanceTo(new THREE.Vector3(probe.x, midHeight, probe.z))
      if (distance > target) {
        changes.push({ id: node.id, position: [round2(probe.x), node.position[1], round2(probe.z)] })
        alreadyChanged.add(node.id)
        return
      }
    }
  }
  for (const relation of scene.relations) {
    const from = projectedById.get(relation.from)
    const to = projectedById.get(relation.to)
    if (!from || !to || !from.visible || !to.visible) continue
    if (relation.type === 'occludes' && stageOfNode(to.node) === stage && from.distance >= to.distance) {
      pushBehind(to, from)
    }
    if (relation.type === 'behind' && stageOfNode(from.node) === stage && from.distance <= to.distance) {
      pushBehind(from, to)
    }
  }

  if (!changes.length) return null
  return {
    type: 'layout-patch',
    year: Math.round(year),
    stage,
    reason: stageIssues.slice(0, 4).map((issue) => issue.message).join('；'),
    changes,
  }
}

/**
 * Apply a SceneLayoutPatch without regenerating entity IDs. Base transform
 * changes are propagated into every temporal anchor (positions by delta,
 * scales by factor) so declared year-over-year motion stays continuous.
 */
export function applyLayoutPatch(scene: FumiraTemporalScene, patch: SceneLayoutPatch): FumiraTemporalScene {
  const changeById = new Map(patch.changes.map((change) => [change.id, change]))
  const baseById = new Map(scene.nodes.map((node) => [node.id, node]))

  const nodes = scene.nodes.map((node) => {
    const change = changeById.get(node.id)
    if (!change) return node
    return {
      ...node,
      position: change.position ?? node.position,
      scale: change.scale ?? node.scale,
    }
  })

  const anchors = scene.anchors.map((anchor) => {
    const patches = { ...anchor.patches }
    for (const change of patch.changes) {
      const entry = patches[change.id]
      const base = baseById.get(change.id)
      if (!entry || !base) continue
      const next = { ...entry }
      if (change.position && entry.position) {
        next.position = [
          round2(entry.position[0] + change.position[0] - base.position[0]),
          round2(entry.position[1] + change.position[1] - base.position[1]),
          round2(entry.position[2] + change.position[2] - base.position[2]),
        ]
      }
      if (change.scale && entry.scale) {
        const baseScale = base.scale ?? [1, 1, 1]
        next.scale = [
          round2(entry.scale[0] * (change.scale[0] / baseScale[0])),
          round2(entry.scale[1] * (change.scale[1] / baseScale[1])),
          round2(entry.scale[2] * (change.scale[2] / baseScale[2])),
        ]
      }
      patches[change.id] = next
    }
    return { ...anchor, patches }
  })

  return { ...scene, nodes, anchors }
}

export interface CalibrationIterationRecord {
  iteration: number
  stage: CalibrationStage
  reason: string
  changes: LayoutPatchChange[]
  issuesAfter: number
}

export interface CalibrationRun {
  scene: FumiraTemporalScene
  iterations: CalibrationIterationRecord[]
  issues: CalibrationIssue[]
  converged: boolean
}

/**
 * Staged fixed-point loop: repeatedly review the fixed-camera render and
 * apply layout patches (ground → landmarks → person → vehicle cluster) until
 * no stage emits changes. Low-confidence annotations are report-only.
 */
export function calibrateScene(
  scene: FumiraTemporalScene,
  year: number,
  imageAspect: number,
  options: { minConfidence?: number; maxIterations?: number } = {},
): CalibrationRun {
  const minConfidence = options.minConfidence ?? 0.55
  const maxIterations = options.maxIterations ?? 12
  let current = scene
  const iterations: CalibrationIterationRecord[] = []
  let converged = false

  for (let iteration = 1; iteration <= maxIterations; iteration += 1) {
    let anyChange = false
    for (const { stage } of CALIBRATION_STAGES) {
      const patch = buildLayoutPatch(current, year, imageAspect, stage, { minConfidence })
      if (!patch) continue
      current = applyLayoutPatch(current, patch)
      anyChange = true
      iterations.push({
        iteration,
        stage,
        reason: patch.reason,
        changes: patch.changes,
        issuesAfter: evaluateScene(current, year, imageAspect).issues.length,
      })
    }
    if (!anyChange) {
      converged = true
      break
    }
  }

  return {
    scene: current,
    iterations,
    issues: evaluateScene(current, year, imageAspect).issues,
    converged,
  }
}
