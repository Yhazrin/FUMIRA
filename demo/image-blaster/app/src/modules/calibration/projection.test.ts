import { describe, expect, it } from 'vitest'
import type { FumiraTemporalScene, TemporalSceneNode } from '../../types/world'
import {
  applyLayoutPatch,
  buildLayoutPatch,
  calibrateScene,
  computeImageRect,
  evaluateScene,
  photoCamera,
  projectNode,
  stageOfNode,
} from './projection'
import { interpolateTemporalNode } from '../temporal/interpolate'

function makeScene(nodes: TemporalSceneNode[], relations: FumiraTemporalScene['relations'] = []): FumiraTemporalScene {
  return {
    version: 1,
    bounds: { width: 20, depth: 20, groundY: 0 },
    camera: { position: [0, 2, 8], target: [0, 1, 0], fov: 40 },
    nodes,
    relations,
    anchors: [{ year: 2026, patches: {} }],
    evaluation: { target: 'overall-recognizability', fixedView: true, checks: [] },
  }
}

const centeredBox: TemporalSceneNode = {
  id: 'box',
  kind: 'prop',
  role: 'vertical-landmark',
  layer: 'midground',
  position: [0, 0, 0],
  footprint: [1, 1],
  height: 2,
  importance: 1,
}

describe('computeImageRect', () => {
  it('letterboxes horizontally when the viewport is wider than the photo', () => {
    const rect = computeImageRect(2000, 1000, 4 / 3)
    expect(rect.height).toBe(1000)
    expect(rect.width).toBeCloseTo(1333.33, 1)
    expect(rect.x).toBeGreaterThan(0)
    expect(rect.y).toBe(0)
  })

  it('letterboxes vertically when the viewport is narrower than the photo', () => {
    const rect = computeImageRect(800, 1200, 4 / 3)
    expect(rect.width).toBe(800)
    expect(rect.x).toBe(0)
    expect(rect.y).toBeGreaterThan(0)
  })
})

describe('projectNode', () => {
  it('projects a node at the camera target near the frame center', () => {
    const scene = makeScene([centeredBox])
    const camera = photoCamera(scene, 4 / 3)
    const projected = projectNode(camera, interpolateTemporalNode(scene, centeredBox, 2026))
    const centerX = projected.box[0] + projected.box[2] / 2
    const centerY = projected.box[1] + projected.box[3] / 2
    expect(centerX).toBeGreaterThan(0.35)
    expect(centerX).toBeLessThan(0.65)
    expect(centerY).toBeGreaterThan(0.3)
    expect(centerY).toBeLessThan(0.7)
    expect(projected.visible).toBe(true)
  })

  it('renders nearer nodes larger than farther identical nodes', () => {
    const near: TemporalSceneNode = { ...centeredBox, id: 'near', position: [0, 0, 3] }
    const far: TemporalSceneNode = { ...centeredBox, id: 'far', position: [0, 0, -3] }
    const scene = makeScene([near, far])
    const camera = photoCamera(scene, 4 / 3)
    const nearProjected = projectNode(camera, interpolateTemporalNode(scene, near, 2026))
    const farProjected = projectNode(camera, interpolateTemporalNode(scene, far, 2026))
    expect(nearProjected.box[3]).toBeGreaterThan(farProjected.box[3])
    expect(nearProjected.distance).toBeLessThan(farProjected.distance)
  })
})

describe('evaluateScene', () => {
  it('flags a declared occlusion whose projections do not overlap', () => {
    const occluder: TemporalSceneNode = { ...centeredBox, id: 'tree-main', kind: 'tree', position: [-3, 0, 0] }
    const subject: TemporalSceneNode = { ...centeredBox, id: 'person', kind: 'person', position: [3, 0, 0] }
    const scene = makeScene(
      [occluder, subject],
      [{ type: 'occludes', from: 'tree-main', to: 'person', strength: 0.9 }],
    )
    const { issues } = evaluateScene(scene, 2026, 4 / 3)
    expect(issues.some((issue) => issue.kind === 'occlusion' && issue.message.includes('未遮挡'))).toBe(true)
  })

  it('flags a farther moped that reads larger than a nearer one', () => {
    const nearSmall: TemporalSceneNode = { ...centeredBox, id: 'moped-a', kind: 'moped', layer: 'foreground', position: [0, 0, 3], height: 0.5 }
    const farBig: TemporalSceneNode = { ...centeredBox, id: 'moped-b', kind: 'moped', layer: 'midground', position: [0.5, 0, -3], height: 4 }
    const scene = makeScene([nearSmall, farBig])
    const { issues } = evaluateScene(scene, 2026, 4 / 3)
    expect(issues.some((issue) => issue.kind === 'depth-order' && issue.message.includes('深度排序错误'))).toBe(true)
  })

  it('passes a well-formed layout without issues', () => {
    const scene = makeScene([centeredBox])
    const { issues } = evaluateScene(scene, 2026, 4 / 3)
    expect(issues).toHaveLength(0)
  })
})

describe('buildLayoutPatch', () => {
  it('suggests moving a node toward its declared imageBox', () => {
    const misplaced: TemporalSceneNode = {
      ...centeredBox,
      id: 'utility-box',
      kind: 'utility-box',
      position: [4, 0, 0],
      imageBox: [0.45, 0.35, 0.1, 0.3],
    }
    const scene = makeScene([misplaced])
    const patch = buildLayoutPatch(scene, 2026, 4 / 3, stageOfNode(misplaced))
    expect(patch).not.toBeNull()
    expect(patch!.type).toBe('layout-patch')
    const change = patch!.changes.find((entry) => entry.id === 'utility-box')
    expect(change?.position).toBeDefined()
    expect(Math.abs(change!.position![0])).toBeLessThan(4)
  })

  it('returns null when the stage has nothing to fix', () => {
    const scene = makeScene([centeredBox])
    expect(buildLayoutPatch(scene, 2026, 4 / 3, 2)).toBeNull()
  })

  it('moves a node so its projection covers a trusted measured anchor', () => {
    const moped: TemporalSceneNode = {
      ...centeredBox,
      id: 'moped-a',
      kind: 'moped',
      layer: 'foreground',
      position: [5, 0, 2],
      height: 1.2,
      imageAnchor: { point: [0.42, 0.8], heightFactor: 0.45, confidence: 0.85 },
    }
    const scene = makeScene([moped])
    const patch = buildLayoutPatch(scene, 2026, 0.75, 3, { minConfidence: 0.55 })
    expect(patch).not.toBeNull()
    const change = patch!.changes.find((entry) => entry.id === 'moped-a')
    expect(change?.position).toBeDefined()
    const calibrated = applyLayoutPatch(scene, patch!)
    const camera = photoCamera(calibrated, 0.75)
    const projected = projectNode(camera, interpolateTemporalNode(calibrated, calibrated.nodes[0], 2026))
    expect(projected.box[0]).toBeLessThanOrEqual(0.42)
    expect(projected.box[0] + projected.box[2]).toBeGreaterThanOrEqual(0.42)
    expect(projected.box[1]).toBeLessThanOrEqual(0.8)
    expect(projected.box[1] + projected.box[3]).toBeGreaterThanOrEqual(0.8)
  })

  it('pushes an untrusted occluded node behind its occluder to honor the relation', () => {
    const occluder: TemporalSceneNode = { ...centeredBox, id: 'tree-main', kind: 'tree', position: [0, 0, -2], height: 5 }
    const subject: TemporalSceneNode = { ...centeredBox, id: 'person', kind: 'person', position: [0.2, 0, 2], confidence: 0.3 }
    const scene = makeScene(
      [occluder, subject],
      [{ type: 'occludes', from: 'tree-main', to: 'person', strength: 0.9 }],
    )
    const patch = buildLayoutPatch(scene, 2026, 4 / 3, 2, { minConfidence: 0.55 })
    expect(patch).not.toBeNull()
    const calibrated = applyLayoutPatch(scene, patch!)
    const camera = photoCamera(calibrated, 4 / 3)
    const tree = projectNode(camera, interpolateTemporalNode(calibrated, calibrated.nodes[0], 2026))
    const person = projectNode(camera, interpolateTemporalNode(calibrated, calibrated.nodes[1], 2026))
    expect(tree.distance).toBeLessThan(person.distance)
  })
})

describe('applyLayoutPatch', () => {
  it('propagates base position deltas and scale factors into temporal anchors', () => {
    const node: TemporalSceneNode = { ...centeredBox, id: 'tree-main', kind: 'tree', scale: [1, 1, 1] }
    const scene: FumiraTemporalScene = {
      ...makeScene([node]),
      anchors: [
        { year: 2026, patches: { 'tree-main': { position: [0, 0, 0], scale: [1, 1, 1] } } },
        { year: 2080, patches: { 'tree-main': { position: [1, 0, -1], scale: [1.3, 1.5, 1.3] } } },
      ],
    }
    const calibrated = applyLayoutPatch(scene, {
      type: 'layout-patch',
      year: 2026,
      stage: 1,
      reason: 'test',
      changes: [{ id: 'tree-main', position: [2, 0, 3], scale: [2, 2, 2] }],
    })
    expect(calibrated.nodes[0].position).toEqual([2, 0, 3])
    const far = calibrated.anchors.find((anchor) => anchor.year === 2080)!.patches['tree-main']
    expect(far.position).toEqual([3, 0, 2])
    expect(far.scale).toEqual([2.6, 3, 2.6])
  })
})

describe('calibrateScene', () => {
  it('converges to a fixed point: a second run emits no patches', () => {
    const moped: TemporalSceneNode = {
      ...centeredBox,
      id: 'moped-a',
      kind: 'moped',
      layer: 'foreground',
      position: [5, 0, 2],
      height: 1.2,
      imageAnchor: { point: [0.42, 0.8], heightFactor: 0.45, confidence: 0.85 },
    }
    const scene = makeScene([moped])
    const run = calibrateScene(scene, 2026, 0.75, { minConfidence: 0.55 })
    expect(run.converged).toBe(true)
    expect(run.iterations.length).toBeGreaterThan(0)
    const verify = calibrateScene(run.scene, 2026, 0.75, { minConfidence: 0.55 })
    expect(verify.iterations).toHaveLength(0)
    expect(verify.converged).toBe(true)
  })
})
