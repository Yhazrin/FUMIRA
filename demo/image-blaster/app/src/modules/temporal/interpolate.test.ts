import { describe, expect, it } from 'vitest'
import { interpolateTemporalNode } from './interpolate'
import type { FumiraTemporalScene, TemporalSceneNode } from '../../types/world'

const node: TemporalSceneNode = {
  id: 'tree-main', kind: 'tree', role: 'occluder-anchor', layer: 'midground',
  position: [0, 0, 0], footprint: [1, 1], height: 3, importance: 1,
}
const scene: FumiraTemporalScene = {
  version: 1,
  bounds: { width: 8, depth: 8, groundY: 0 },
  camera: { position: [1, 1, 1], target: [0, 0, 0], fov: 35 },
  nodes: [node], relations: [], evaluation: { target: 'overall-recognizability', fixedView: true, checks: [] },
  anchors: [
    { year: 2026, patches: { 'tree-main': { scale: [1, 1, 1] } } },
    { year: 2036, patches: { 'tree-main': { scale: [1.4, 1.5, 1.4] } } },
  ],
}

describe('interpolateTemporalNode', () => {
  it('interpolates a canonical entity patch instead of replacing the entity', () => {
    expect(interpolateTemporalNode(scene, node, 2031).scale).toEqual([1.2, 1.25, 1.2])
  })
})
