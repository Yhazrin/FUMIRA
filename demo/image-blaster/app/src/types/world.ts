export interface WorldAssets {
  mesh: { collider_mesh_url: string }
  imagery: { pano_url: string }
  splats: {
    spz_urls: {
      '500k'?: string
      '100k'?: string
      '150k'?: string
      full_res?: string
    }
    semantics_metadata: {
      metric_scale_factor: number
      ground_plane_offset: number
      flip_y?: boolean
    }
  }
  thumbnail_url: string
  caption: string
}

export interface World {
  world_id: string
  display_name: string
  assets: WorldAssets
  world_marble_url: string
  tags: string[] | null
  world_prompt: string | null
  created_at: string | null
  updated_at: string | null
}

export interface WorldProject {
  slug: string
  display_name?: string
  created_at?: string
  updated_at?: string
  notes?: string
}

export interface WorldObjectAsset {
  id: string
  assetId: string
  sourceWorldSlug: string
  baseObjectId: string
  index?: number
  variantLabel?: string
  fileName?: string
  name: string
  url: string
  referenceImageUrl?: string
  thumbnailUrl?: string
  sfxUrls: string[]
  complete: boolean
  status?: string
}

export type Vec3Tuple = [number, number, number]
export type WorldObjectPhysics = 'rigidbody' | 'static' | 'ghost'

/**
 * FUMIRA's source of truth is a scene, not a loose collection of generated
 * meshes. Assets can be swapped later, while these IDs and spatial relations
 * remain stable across the temporal timeline.
 */
export type TemporalSceneNodeKind =
  | 'road'
  | 'building'
  | 'tree'
  | 'hedge'
  | 'utility-box'
  | 'moped'
  | 'person'
  | 'signal'
  | 'prop'

export interface TemporalSceneNode {
  id: string
  kind: TemporalSceneNodeKind
  role: 'recognition-anchor' | 'occluder-anchor' | 'vertical-landmark' | 'cluster-member' | 'depth-plane' | 'edge-frame' | 'secondary-subject' | 'support'
  layer: 'foreground' | 'midground' | 'background'
  position: Vec3Tuple
  rotation?: Vec3Tuple
  scale?: Vec3Tuple
  footprint: [number, number]
  height: number
  color?: string
  importance: number
  /** Declared [x, y, width, height] in the source image, normalized 0..1, top-left origin. */
  imageBox?: [number, number, number, number]
  /** Measured pixel-evidence anchor: the projected node must cover this image point. */
  imageAnchor?: {
    point: [number, number]
    /** Where the anchor sits on the node vertically (0 = ground, 1 = top). Default 0.5. */
    heightFactor?: number
    confidence: number
    source?: string
  }
  /** 3 = hero recognition anchor … 0 = background filler. */
  visualPriority?: 0 | 1 | 2 | 3
  /** How trustworthy the declared image-space annotation is (0..1). */
  confidence?: number
}

export interface TemporalSceneRelation {
  type: 'occludes' | 'supports' | 'clustered-with' | 'behind' | 'frames'
  from: string
  to: string
  strength: number
}

export interface TemporalNodePatch {
  position?: Vec3Tuple
  rotation?: Vec3Tuple
  scale?: Vec3Tuple
  opacity?: number
}

export interface TemporalSceneAnchor {
  year: number
  patches: Record<string, TemporalNodePatch>
}

export interface FumiraTemporalScene {
  version: 1
  sourceImage?: string
  bounds: { width: number; depth: number; groundY: number }
  camera: { position: Vec3Tuple; target: Vec3Tuple; fov: number }
  nodes: TemporalSceneNode[]
  relations: TemporalSceneRelation[]
  anchors: TemporalSceneAnchor[]
  evaluation: {
    target: 'overall-recognizability'
    fixedView: boolean
    checks: string[]
  }
}

export interface WorldObjectPlacement {
  instanceId: string
  objectId: string
  assetId?: string
  physics?: WorldObjectPhysics
  position: Vec3Tuple
  rotation: Vec3Tuple
  scale: Vec3Tuple
}

export interface WorldSceneSun {
  intensity: number
  rotation: Vec3Tuple
  environmentIntensity?: number
}

export interface WorldSceneProject {
  version: 1 | 2
  instances: WorldObjectPlacement[]
  sun?: WorldSceneSun
  metricScaleFactor?: number
  groundPlaneOffset?: number
  groundPlaneColliderEnabled?: boolean
  shadowCatcherOpacity?: number
  shadowCatcherColor?: string
  temporalScene?: FumiraTemporalScene
}

export interface WorldVersion {
  index: number
  label: string
  world?: World
  plateImageUrl?: string
  complete: boolean
  status?: string
}

export interface SourceImageVersion {
  url: string
  label: string
  fileName: string
  index?: number
}

export interface WorldHoverPreview {
  slug: string
  imageUrl?: string
  alt: string
}

export interface WorldEntry {
  slug: string
  project: WorldProject
  world?: World
  worldVersions: WorldVersion[]
  objectAssets: WorldObjectAsset[]
  allObjectAssets: WorldObjectAsset[]
  sourceImageUrl?: string
  sourceImageVersions: SourceImageVersion[]
  worldSfxUrls: string[]
  sceneProject?: WorldSceneProject
}

export enum WorldRenderMode {
  SplatOnly = 'splat-only',
  ObjectOnly = 'object-only',
  Combined = 'combined',
}

export enum ObjectRenderMode {
  Lit = 'lit',
  Wireframe = 'wireframe',
  ShadedWireframe = 'shaded-wireframe',
}

export enum ViewerQuality {
  Low = 'low',
  High = 'high',
}
