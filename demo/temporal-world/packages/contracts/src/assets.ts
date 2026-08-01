/**
 * FUMIRA Temporal World - Asset Schema
 *
 * Defines the data model for 3D assets produced by the Claude Reconstruction
 * Worker from K230 camera frames. Assets flow through:
 *
 *   K230 Camera --> Reconstruction Worker --> Asset Store --> Scene Compiler --> Three.js Runtime
 *
 * The temporal world uses a normalized time axis [-100..+100] where:
 *   -100 = deep past, 0 = present capture moment, +100 = far future
 */

import type { EntitySpec, TemporalEntityState } from './index';

// ─── Enums & Literals ────────────────────────────────────────────

/** Quality tier assigned by the reconstruction worker after mesh processing. */
export type QualityGrade = 'draft' | 'standard' | 'high' | 'production';

/** Current lifecycle stage of an asset in the store. */
export type AssetStatus = 'pending' | 'processing' | 'ready' | 'failed' | 'archived';

/** Supported mesh container formats. */
export type MeshFormat = 'glb' | 'gltf';

/** Supported texture image formats. */
export type TextureFormat = 'png' | 'jpg' | 'webp' | 'ktx2' | 'basis';

/** Semantic role of a texture within a material. */
export type TextureUsage = 'albedo' | 'normal' | 'roughness' | 'metalness' | 'ao' | 'emissive' | 'height';

/** Axis-aligned bounding box defined by min/max corners in world space. */
export interface BoundingBox {
  min: [number, number, number];
  max: [number, number, number];
}

/** 3D transform: translation, Euler rotation (radians), uniform or per-axis scale. */
export interface Transform {
  position: [number, number, number];
  rotation: [number, number, number];
  scale: [number, number, number];
}

/**
 * Normalized temporal validity range on the [-100..+100] axis.
 *
 * An asset is "alive" for `t` values where `timeRange.start <= t <= timeRange.end`.
 * Use start=0, end=0 for assets that exist only at the present moment.
 * Use start=-100, end=100 for assets that span the entire timeline.
 */
export interface TemporalRange {
  /** Inclusive start on the normalized axis. -100 = deep past. */
  start: number;
  /** Inclusive end on the normalized axis. +100 = far future. */
  end: number;
}

// ─── Base Asset ──────────────────────────────────────────────────

/** Fields shared by every asset type in the store. */
export interface BaseAsset {
  /** Globally unique asset ID (UUIDv4). */
  id: string;

  /** ID of the reconstruction job that produced this asset. */
  sourceJobId: string;

  /** IDs of K230 camera frames consumed during reconstruction. */
  sourceFrameIds: string[];

  /** ISO-8601 creation timestamp. */
  createdAt: string;

  /** ISO-8601 last modification timestamp. */
  updatedAt: string;

  /** Absolute path to the primary asset file on the local filesystem. */
  filePath: string;

  /** Absolute path to a thumbnail image for UI preview (PNG or JPEG). */
  thumbnailPath: string;

  /** Lifecycle status. */
  status: AssetStatus;

  /** Quality grade assigned by the reconstruction worker. */
  quality: QualityGrade;

  /** Numerical quality score from the reconstruction pipeline [0..1]. */
  qualityScore: number;

  /** File size in bytes. */
  fileSizeBytes: number;

  /** User-defined tags for filtering and search. */
  tags: string[];

  /** Free-form key-value metadata from the reconstruction pipeline. */
  metadata: Record<string, unknown>;
}

// ─── MeshAsset ───────────────────────────────────────────────────

/**
 * A reconstructed 3D mesh stored as GLB/GLTF.
 *
 * Produced by the Claude Reconstruction Worker from one or more K230 frames.
 * The mesh is the geometric backbone of a SceneEntity.
 */
export interface MeshAsset extends BaseAsset {
  kind: 'mesh';

  /** Container format. */
  format: MeshFormat;

  /** Axis-aligned bounding box in the mesh's local coordinate space. */
  boundingBox: BoundingBox;

  /** Total vertex count (sum across all primitives in the GLB). */
  vertexCount: number;

  /** Total triangle/face count. */
  faceCount: number;

  /** Number of discrete mesh primitives (sub-meshes) in the GLB. */
  primitiveCount: number;

  /** Number of materials referenced by this mesh. */
  materialCount: number;

  /** IDs of TextureAssets used by materials in this mesh. */
  textureRefs: string[];

  /** LOD level: 0 = highest detail, higher = more simplified. */
  lodLevel: number;

  /** Whether the mesh includes embedded animation data. */
  hasAnimation: boolean;

  /** Whether the mesh includes embedded skeleton/rig data. */
  hasSkeleton: boolean;

  /** Meshoptimizer compression was applied. */
  compressed: boolean;
}

// ─── TextureAsset ────────────────────────────────────────────────

/**
 * An image texture intended for use on a MeshAsset's materials.
 *
 * May be derived from K230 camera frames (projected texture) or synthesized
 * by the reconstruction pipeline (e.g., inpainted normal maps).
 */
export interface TextureAsset extends BaseAsset {
  kind: 'texture';

  /** Image container format. */
  format: TextureFormat;

  /** Semantic role of this texture in a PBR material. */
  usage: TextureUsage;

  /** Image width in pixels. */
  width: number;

  /** Image height in pixels. */
  height: number;

  /** Number of color channels (e.g., 3 for RGB, 4 for RGBA). */
  channels: number;

  /** Bits per channel (e.g., 8, 16, 32). */
  bitsPerChannel: number;

  /** Whether the texture has been UV-unwrapped and atlas-packed. */
  uvMapped: boolean;

  /** UV channel index this texture targets (0 = default UV set). */
  uvChannel: number;

  /** Whether mipmaps have been generated. */
  hasMipmaps: boolean;

  /** Whether the texture uses sRGB color space (false = linear). */
  isSRGB: boolean;

  /** If this is a projected texture, the source frame ID it was derived from. */
  projectedFromFrameId?: string;
}

// ─── SceneEntity ─────────────────────────────────────────────────

/**
 * A temporal world entity that combines mesh geometry, textures, a world
 * transform, and a temporal validity range.
 *
 * SceneEntities are the primary unit consumed by the Scene Compiler.
 * Each entity maps to one or more MeshAssets and TextureAssets, positioned
 * in the world and alive for a defined interval on the temporal axis.
 *
 * The `entitySpec` field links back to the hand-authored or procedurally-
 * generated EntitySpec from the scene fixture, enabling the runtime to
 * apply temporal interpolation via InterpolatedEntityState.
 */
export interface SceneEntity {
  /** Globally unique entity ID (UUIDv4). */
  id: string;

  /** Human-readable name for editor display. */
  name: string;

  /** ID of the reconstruction job that assembled this entity. */
  sourceJobId: string;

  /** ISO-8601 creation timestamp. */
  createdAt: string;

  /** ISO-8601 last modification timestamp. */
  updatedAt: string;

  /** The mesh that provides this entity's geometry. */
  meshAssetId: string;

  /** Texture assets bound to this entity, keyed by material slot name. */
  textureBindings: Record<string, string>;

  /** World-space transform placed by the scene author or auto-fitted. */
  transform: Transform;

  /**
   * Normalized temporal range during which this entity is visible.
   * The Scene Compiler uses this to gate entity presence in the
   * Three.js scene graph as the user scrubs through time.
   */
  temporalRange: TemporalRange;

  /**
   * Optional: fine-grained temporal states for interpolation.
   * Maps a normalized time value to a partial TemporalEntityState.
   * The runtime interpolates between adjacent states.
   */
  temporalKeyframes?: Record<number, Partial<TemporalEntityState>>;

  /**
   * Link to the original or synthesized EntitySpec.
   * Allows the runtime's existing temporal interpolation logic
   * (getInterpolatedState) to drive this entity.
   */
  entitySpec?: Partial<EntitySpec>;

  /** Semantic category (e.g., 'building', 'vegetation', 'character', 'prop'). */
  category: string;

  /** Entity type within its category (e.g., 'tree', 'bench', 'lampPost'). */
  type: string;

  /** Whether the entity casts shadows in the Three.js scene. */
  castShadow: boolean;

  /** Whether the entity receives shadows. */
  receiveShadow: boolean;

  /** LOD bias: 0 = auto, positive = force lower detail. */
  lodBias: number;

  /** Free-form metadata from the reconstruction or scene-assembly pass. */
  metadata: Record<string, unknown>;
}

// ─── ReconstructionResult ────────────────────────────────────────

/** Status of a reconstruction output in the asset store. */
export type ReconstructionOutputStatus = 'queued' | 'running' | 'completed' | 'failed' | 'cancelled';

/** Camera intrinsics captured from the K230 at reconstruction time. */
export interface CameraIntrinsics {
  /** Focal length in pixels. */
  focalLengthPx: number;
  /** Principal point offset [cx, cy]. */
  principalPoint: [number, number];
  /** Image resolution [width, height] of the source frames. */
  imageResolution: [number, number];
  /** Radial distortion coefficients [k1, k2, k3]. */
  distortionCoefficients: [number, number, number];
}

/** Estimated camera pose for a single input frame. */
export interface FramePose {
  /** The K230 frame ID. */
  frameId: string;
  /** 4x4 column-major world-from-camera transform matrix (16 floats). */
  worldFromCamera: number[];
  /** Reprojection error in pixels (lower = better). */
  reprojectionError: number;
}

/**
 * Full output of a reconstruction job.
 *
 * This is the top-level structure produced by the Claude Reconstruction Worker
 * after processing a set of K230 camera frames. It contains all generated
 * meshes, textures, assembled SceneEntities, and diagnostic metadata.
 *
 * The Scene Compiler consumes a ReconstructionOutput to produce a
 * SceneFixture-compatible scene graph for the Three.js runtime.
 *
 * Note: The simpler `ReconstructionResult` in `reconstruction-job.ts` is the
 * transport object returned via callback. This is the expanded, store-resident
 * version with full asset references.
 */
export interface ReconstructionOutput {
  /** Globally unique job ID (UUIDv4). */
  jobId: string;

  /** ISO-8601 timestamp when the job was created. */
  createdAt: string;

  /** ISO-8601 timestamp when the job finished (null if still running). */
  completedAt: string | null;

  /** Current reconstruction output status. */
  status: ReconstructionOutputStatus;

  /** Normalized time-axis position this reconstruction targets. */
  temporalPosition: number;

  /**
   * Temporal range this reconstruction covers on the [-100..+100] axis.
   * A single-point reconstruction has start === end === temporalPosition.
   * A sweep reconstruction covers a wider interval.
   */
  temporalRange: TemporalRange;

  /** IDs of K230 camera frames fed into this job. */
  inputFrameIds: string[];

  /** Camera intrinsics shared across all input frames. */
  cameraIntrinsics: CameraIntrinsics;

  /** Estimated per-frame camera poses from SfM. */
  framePoses: FramePose[];

  /** All mesh assets produced by this job. */
  meshes: MeshAsset[];

  /** All texture assets produced by this job. */
  textures: TextureAsset[];

  /** Assembled scene entities referencing the meshes and textures above. */
  entities: SceneEntity[];

  /** Total vertex count across all meshes. */
  totalVertexCount: number;

  /** Total triangle count across all meshes. */
  totalFaceCount: number;

  /** Total file size of all assets in bytes. */
  totalFileSizeBytes: number;

  /** Aggregate quality score [0..1]. */
  overallQualityScore: number;

  /** Reconstruction algorithm version string. */
  pipelineVersion: string;

  /** Wall-clock processing duration in milliseconds. */
  processingDurationMs: number;

  /** Peak memory usage during reconstruction in bytes. */
  peakMemoryBytes: number;

  /** Warnings emitted during reconstruction (non-fatal). */
  warnings: string[];

  /** Error message if the job failed. */
  error: string | null;

  /** Free-form diagnostic metadata from the pipeline. */
  diagnostics: Record<string, unknown>;
}

// ─── Asset Store Interface ───────────────────────────────────────

/** Filter predicates for listing assets. */
export interface AssetFilters {
  /** Filter by asset kind. */
  kind?: 'mesh' | 'texture';

  /** Filter by source job ID. */
  sourceJobId?: string;

  /** Filter by status. */
  status?: AssetStatus;

  /** Filter by minimum quality score (inclusive). */
  minQualityScore?: number;

  /** Filter by quality grade. */
  quality?: QualityGrade;

  /** Filter by tags (match any). */
  tags?: string[];

  /** Filter by temporal position overlap: include assets whose temporalRange covers this value. */
  temporalPosition?: number;

  /** Maximum number of results to return. */
  limit?: number;

  /** Offset for pagination. */
  offset?: number;

  /** Sort field. */
  sortBy?: 'createdAt' | 'updatedAt' | 'qualityScore' | 'fileSizeBytes';

  /** Sort direction. */
  sortOrder?: 'asc' | 'desc';
}

/** Paginated list result. */
export interface AssetListResult<T extends BaseAsset = BaseAsset> {
  items: T[];
  total: number;
  limit: number;
  offset: number;
}

/**
 * Asset Store interface.
 *
 * Provides CRUD operations for all asset types produced by the Reconstruction
 * Worker. Implementations may back this with a local filesystem, SQLite, or
 * a remote service.
 */
export interface AssetStore {
  /**
   * Persist an asset to the store.
   * @returns The absolute filesystem path where the asset metadata was stored.
   */
  saveAsset(asset: MeshAsset | TextureAsset): Promise<string>;

  /**
   * Retrieve a single asset by its unique ID.
   * @returns The asset metadata, or null if not found.
   */
  getAsset(id: string): Promise<MeshAsset | TextureAsset | null>;

  /**
   * List assets matching the given filters.
   */
  listAssets(filters?: AssetFilters): Promise<AssetListResult>;

  /**
   * List only mesh assets matching the given filters.
   */
  listMeshAssets(filters?: AssetFilters): Promise<AssetListResult<MeshAsset>>;

  /**
   * List only texture assets matching the given filters.
   */
  listTextureAssets(filters?: AssetFilters): Promise<AssetListResult<TextureAsset>>;

  /**
   * Delete an asset and its associated files from the store.
   * @returns true if the asset existed and was deleted, false if not found.
   */
  deleteAsset(id: string): Promise<boolean>;

  /**
   * Get the most recent ready asset for a given scene entity.
   * Looks up the entity's meshAssetId, then returns the latest MeshAsset
   * (by createdAt) with status 'ready'.
   */
  getLatestForEntity(entityId: string): Promise<MeshAsset | null>;

  /**
   * Save a complete reconstruction output (all meshes, textures, and entities).
   * This is a batch operation that persists every sub-asset atomically.
   */
  saveReconstructionOutput(output: ReconstructionOutput): Promise<void>;

  /**
   * Retrieve a full reconstruction output by job ID.
   */
  getReconstructionOutput(jobId: string): Promise<ReconstructionOutput | null>;

  /**
   * List all reconstruction outputs, most recent first.
   */
  listReconstructionOutputs(limit?: number): Promise<ReconstructionOutput[]>;

  /**
   * Save or update a scene entity definition.
   */
  saveEntity(entity: SceneEntity): Promise<string>;

  /**
   * Retrieve a scene entity by ID.
   */
  getEntity(entityId: string): Promise<SceneEntity | null>;

  /**
   * List all scene entities, optionally filtered by temporal position.
   */
  listEntities(temporalPosition?: number): Promise<SceneEntity[]>;

  /**
   * Delete a scene entity definition.
   */
  deleteEntity(entityId: string): Promise<boolean>;
}
