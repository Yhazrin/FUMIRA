/**
 * @module @fumira/scene-compiler
 *
 * Scene Compiler API for FUMIRA's temporal world.
 *
 * The Scene Compiler sits between the Asset Store (where 3D assets, textures,
 * and temporal metadata live) and the Three.js Runtime (`@fumira/scene-runtime`)
 * which handles real-time rendering, camera, lighting, and the timeline.
 *
 * Pipeline:
 *   Asset Store --> Scene Compiler --> Scene Manifest --> Three.js Runtime
 *
 * The compiler watches for new/updated assets, validates them, generates
 * Three.js-compatible scene graph entries, manages LOD and temporal
 * transitions, and caches compiled output for fast loading.
 */

import type {
  EntitySpec,
  Palette,
  StyleSpec,
  TemporalSpec,
  TemporalEntityState,
  InterpolatedEntityState,
} from '@fumira/contracts';

// ─── Asset Store Inputs ──────────────────────────────────────────

/**
 * Supported mesh serialization formats the compiler can consume.
 * - `clay-procedural` : FUMIRA's own parametric shape builder (box, cylinder, sphere composites)
 * - `gltf-binary`     : GLB binary blob
 * - `gltf-json`       : glTF 2.0 JSON + external buffers
 * - `obj`             : Wavefront OBJ (geometry only, material must be separate)
 */
export type MeshFormat = 'clay-procedural' | 'gltf-binary' | 'gltf-json' | 'obj';

/**
 * Supported texture formats.
 */
export type TextureFormat = 'png' | 'jpg' | 'ktx2' | 'basis' | 'webp';

/**
 * A single mesh asset registered in the Asset Store.
 */
export interface MeshAsset {
  /** Unique asset identifier (UUIDv4 recommended). */
  id: string;
  /** Human-readable name for editor display. */
  name: string;
  /** Serialization format of this mesh. */
  format: MeshFormat;
  /**
   * For `clay-procedural`: the entity type key that maps to a builder in
   * `@fumira/clay-builders` (e.g. "building", "tree", "character").
   * For file-based formats: a URL or relative path to the blob.
   */
  source: string;
  /** Semantic version of this asset (semver). */
  version: string;
  /** ISO-8601 timestamp of last modification. */
  updatedAt: string;
  /** Bounding box in local space [minX, minY, minZ, maxX, maxY, maxZ]. */
  boundingBox: [number, number, number, number, number, number];
  /** Vertex count of the highest-detail mesh. */
  vertexCount: number;
  /** Triangle count of the highest-detail mesh. */
  triangleCount: number;
  /**
   * LOD variants keyed by distance tier.
   * Each value is either a URL to the reduced mesh or a reduction ratio (0..1).
   * If absent, the compiler generates LODs automatically via decimation.
   */
  lodVariants?: Partial<Record<LODTier, string | number>>;
  /**
   * Temporal variants: different mesh shapes an entity can take across the
   * timeline. Keyed by a structural variant name (e.g. "original", "renovated").
   * If absent, the same mesh is used for all temporal states.
   */
  temporalVariants?: Record<string, string | TemporalMeshOverride>;
}

/**
 * Overrides applied on top of a base mesh for a specific temporal variant.
 * Enables morphing between states without shipping entirely separate meshes.
 */
export interface TemporalMeshOverride {
  /** URL to a morph-target file (same topology, different positions). */
  morphTarget?: string;
  /** Material overrides for this variant. */
  materialOverrides?: Record<string, Partial<MaterialParams>>;
  /** Visibility of specific sub-meshes by name. */
  submeshVisibility?: Record<string, boolean>;
}

/**
 * A texture asset registered in the Asset Store.
 */
export interface TextureAsset {
  id: string;
  name: string;
  format: TextureFormat;
  /** URL or relative path to the texture blob. */
  source: string;
  version: string;
  updatedAt: string;
  /** Pixel dimensions [width, height]. */
  size: [number, number];
  /** Whether the texture contains an alpha channel. */
  hasAlpha: boolean;
  /** Whether mipmaps have been pre-generated. */
  hasMipmaps: boolean;
  /**
   * KTX2 / Basis compression settings applied.
   * `null` if the source is uncompressed.
   */
  compression?: {
    method: 'etc1s' | 'uastc';
    quality: number;
  };
}

/**
 * A material definition that references textures by asset ID.
 */
export interface MaterialAsset {
  id: string;
  name: string;
  version: string;
  updatedAt: string;
  /** Base color as hex string (e.g. "#FF672A") or texture asset ID. */
  color: string | { textureAssetId: string };
  /** Roughness value (0..1). */
  roughness: number;
  /** Metalness value (0..1). */
  metalness: number;
  /** Flat shading toggle (for FUMIRA's clay aesthetic). */
  flatShading: boolean;
  /** Optional normal map asset ID. */
  normalMap?: string;
  /** Optional emissive color. */
  emissive?: string;
  /** Emissive intensity multiplier. */
  emissiveIntensity?: number;
}

/**
 * Union of all asset types the compiler can consume.
 */
export type Asset = MeshAsset | TextureAsset | MaterialAsset;

/**
 * Material parameters accepted by the compiler when generating Three.js materials.
 */
export interface MaterialParams {
  color: string;
  roughness: number;
  metalness: number;
  flatShading: boolean;
  transparent: boolean;
  opacity: number;
  side: 'front' | 'back' | 'double';
}

// ─── LOD ─────────────────────────────────────────────────────────

/**
 * Distance tiers for level-of-detail selection.
 * - `high`   : 0-10 world units (camera close-up)
 * - `medium` : 10-30 world units (mid-range orbit)
 * - `low`    : 30-60 world units (overview / distant)
 * - `billboard` : 60+ world units (impostor sprite)
 */
export type LODTier = 'high' | 'medium' | 'low' | 'billboard';

/**
 * Per-tier LOD configuration.
 */
export interface LODConfig {
  /** Distance thresholds in world units that separate each tier. */
  thresholds: [number, number, number];
  /** Whether to auto-generate LOD meshes via decimation. */
  autoGenerate: boolean;
  /** Decimation ratios for auto-generated LODs (target vertex fraction). */
  decimationRatios: [number, number, number];
  /**
   * Maximum texture resolution per LOD tier.
   * The compiler downscales textures exceeding this limit.
   */
  maxTextureSize: Record<LODTier, number>;
}

/**
 * A resolved LOD entry in the compiled scene graph.
 */
export interface LODEntry {
  tier: LODTier;
  /** Distance at which this LOD activates. */
  distance: number;
  /** Mesh reference for this tier. */
  mesh: SceneMeshDefinition;
  /** Vertex count at this tier. */
  vertexCount: number;
}

// ─── Scene Graph Definitions (Three.js Object3D serializable) ────

/**
 * Serializable representation of a Three.js material.
 * The runtime hydrates this into a live THREE.Material instance.
 */
export interface SceneMaterialDefinition {
  type: 'MeshStandardMaterial' | 'MeshBasicMaterial' | 'MeshPhongMaterial';
  color: string;
  roughness?: number;
  metalness?: number;
  flatShading?: boolean;
  transparent?: boolean;
  opacity?: number;
  wireframe?: boolean;
  side?: 'front' | 'back' | 'double';
  emissive?: string;
  emissiveIntensity?: number;
  /** Reference to a texture asset ID for the diffuse map. */
  map?: string;
  /** Reference to a texture asset ID for the normal map. */
  normalMap?: string;
  /** User data attached to the material (e.g. baseColor for temporal tinting). */
  userData?: Record<string, unknown>;
}

/**
 * Serializable representation of a Three.js geometry.
 * Covers the primitive types used by FUMIRA's clay builders.
 */
export type SceneGeometryDefinition =
  | { type: 'BoxGeometry'; width: number; height: number; depth: number; widthSegments?: number; heightSegments?: number; depthSegments?: number }
  | { type: 'SphereGeometry'; radius: number; widthSegments?: number; heightSegments?: number; phiStart?: number; phiLength?: number; thetaStart?: number; thetaLength?: number }
  | { type: 'CylinderGeometry'; radiusTop: number; radiusBottom: number; height: number; radialSegments?: number; heightSegments?: number; openEnded?: boolean; thetaStart?: number; thetaLength?: number }
  | { type: 'PlaneGeometry'; width: number; height: number; widthSegments?: number; heightSegments?: number }
  | { type: 'CapsuleGeometry'; radius: number; length: number; capSegments?: number; radialSegments?: number }
  | { type: 'TorusGeometry'; radius: number; tube: number; radialSegments?: number; tubularSegments?: number }
  | { type: 'BufferGeometry'; /** Reference to a GLB/GLTF asset ID. */ assetId: string }
  | { type: 'MorphGeometry'; /** Base geometry + morph targets from temporal variants. */ base: SceneGeometryDefinition; morphTargets: Record<string, string> };

/**
 * Serializable representation of a Three.js Mesh.
 */
export interface SceneMeshDefinition {
  geometry: SceneGeometryDefinition;
  material: SceneMaterialDefinition;
  /** Whether this mesh casts shadow. Default: true. */
  castShadow?: boolean;
  /** Whether this mesh receives shadow. Default: true. */
  receiveShadow?: boolean;
  /** Arbitrary user data attached to the mesh (e.g. isGrass, baseColor). */
  userData?: Record<string, unknown>;
}

/**
 * A node in the scene graph. Can contain child nodes, forming a tree.
 * This maps to THREE.Object3D / THREE.Group at runtime.
 */
export interface SceneNodeDefinition {
  /** Unique instance ID for this node (usually matches entity ID). */
  id: string;
  /** Node type determines how the runtime hydrates it. */
  type: 'group' | 'mesh' | 'lod-group' | 'ambient-light' | 'directional-light' | 'point-light';
  /** Local position [x, y, z]. */
  position?: [number, number, number];
  /** Local rotation as Euler angles [x, y, z] in radians. */
  rotation?: [number, number, number];
  /** Local scale [x, y, z] or uniform scalar. */
  scale?: [number, number, number] | number;
  /** Visibility flag. */
  visible?: boolean;
  /** Mesh definition (only for type === 'mesh'). */
  mesh?: SceneMeshDefinition;
  /** LOD entries (only for type === 'lod-group'). */
  lodEntries?: LODEntry[];
  /** Light parameters (only for light types). */
  light?: SceneLightDefinition;
  /** Child nodes. */
  children?: SceneNodeDefinition[];
  /** Arbitrary user data forwarded to THREE.Object3D.userData. */
  userData?: Record<string, unknown>;
}

/**
 * Serializable light definition.
 */
export type SceneLightDefinition =
  | { type: 'AmbientLight'; color: string; intensity: number }
  | { type: 'DirectionalLight'; color: string; intensity: number; position: [number, number, number]; castShadow?: boolean; shadow?: ShadowConfig }
  | { type: 'PointLight'; color: string; intensity: number; distance?: number; decay?: number };

/**
 * Shadow configuration for directional / spot lights.
 */
export interface ShadowConfig {
  mapSize: [number, number];
  camera: {
    near: number;
    far: number;
    left: number;
    right: number;
    top: number;
    bottom: number;
  };
  radius: number;
  bias?: number;
}

// ─── Scene Manifest ──────────────────────────────────────────────

/**
 * The compiled scene graph plus all metadata the Three.js Runtime needs
 * to instantiate and render the scene.
 */
export interface SceneManifest {
  /** Manifest schema version (semver). */
  schemaVersion: string;
  /** Unique compilation run ID. */
  compilationId: string;
  /** ISO-8601 timestamp of compilation. */
  compiledAt: string;
  /** Source scene fixture ID this was compiled from. */
  sourceFixtureId: string;
  /** Source scene fixture version. */
  sourceFixtureVersion: string;

  /** Palette tokens forwarded to the runtime. */
  palette: Palette;
  /** Style / rendering configuration. */
  style: StyleSpec;

  /**
   * Complete scene graph tree. The runtime calls scene.add() on each root node.
   * Nodes are ordered: infrastructure first (ground, road, base), then entities.
   */
  sceneGraph: SceneNodeDefinition[];

  /**
   * Entity-centric lookup table. Keyed by entity ID.
   * Each entry points to a node in the sceneGraph and carries
   * the original EntitySpec plus compiled temporal data.
   */
  entities: Record<string, CompiledEntity>;

  /**
   * Temporal specification forwarded from the fixture, augmented with
   * pre-compiled transition descriptors.
   */
  temporalSpec: CompiledTemporalSpec;

  /** Runtime hints derived during compilation. */
  runtimeHints: RuntimeHints;

  /** LOD configuration used for this compilation. */
  lodConfig: LODConfig;

  /** Asset versions consumed during this compilation. */
  assetVersions: Record<string, string>;

  /** Total vertex count across all entities at highest LOD. */
  totalVertexCount: number;

  /** Total triangle count across all entities at highest LOD. */
  totalTriangleCount: number;

  /** Estimated GPU memory usage in bytes. */
  estimatedGpuMemoryBytes: number;
}

/**
 * A compiled entity: the original spec plus its resolved scene node
 * and temporal transition data.
 */
export interface CompiledEntity {
  /** Original entity specification from the fixture. */
  spec: EntitySpec;
  /** ID of the scene graph node that represents this entity. */
  sceneNodeId: string;
  /** LOD entries if this entity has multiple detail levels. */
  lodEntries?: LODEntry[];
  /**
   * Temporal state interpolation tables, pre-baked for the runtime.
   * Keyed by anchor year pairs "startYear-endYear".
   */
  temporalInterpolationTables?: Record<string, InterpolationTable>;
}

/**
 * Pre-computed interpolation table for an entity between two anchor years.
 * Avoids runtime computation of lerp parameters.
 */
export interface InterpolationTable {
  entityId: string;
  startYear: number;
  endYear: number;
  /** The resolved TemporalEntityState at the start anchor. */
  startState: TemporalEntityState;
  /** The resolved TemporalEntityState at the end anchor. */
  endState: TemporalEntityState;
  /**
   * Flags indicating which properties use discrete (step) interpolation
   * vs continuous (lerp) interpolation between these two anchors.
   */
  discreteProperties: (keyof TemporalEntityState)[];
  continuousProperties: (keyof TemporalEntityState)[];
  /**
   * If a structural variant change occurs between anchors,
   * the morph target path and blend parameters.
   */
  morphTransition?: {
    fromVariant: string;
    toVariant: string;
    /** Blend function: 'linear' | 'ease-in' | 'ease-out' | 'ease-in-out'. */
    blendFunction: string;
    /** Threshold t value at which to snap to the new variant (for discrete switches). */
    snapThreshold?: number;
  };
}

/**
 * Compiled temporal specification: the original spec plus pre-compiled
 * transition descriptors for each interval.
 */
export interface CompiledTemporalSpec {
  /** Original temporal spec from the fixture. */
  raw: TemporalSpec;
  /**
   * Per-interval transition descriptors.
   * One entry per TimelineInterval in the original spec.
   */
  intervals: CompiledInterval[];
}

/**
 * A compiled timeline interval with pre-resolved entity states.
 */
export interface CompiledInterval {
  startYear: number;
  endYear: number;
  mode: string;
  narrative: string;
  /** Pre-resolved entity states at the start of this interval. */
  startEntityStates: Record<string, TemporalEntityState>;
  /** Pre-resolved entity states at the end of this interval. */
  endEntityStates: Record<string, TemporalEntityState>;
  /** IDs of entities that change during this interval. */
  changingEntityIds: string[];
}

/**
 * Performance and rendering hints the compiler derives from the scene
 * content and passes to the runtime for optimization.
 */
export interface RuntimeHints {
  /** Recommended initial camera position. */
  cameraPosition: [number, number, number];
  /** Recommended orbit controls target. */
  cameraTarget: [number, number, number];
  /** Recommended camera FOV in degrees. */
  cameraFov: number;
  /** Recommended near/far clip planes. */
  cameraClipping: [number, number];
  /** Recommended min/max orbit distance. */
  orbitDistanceRange: [number, number];
  /** Recommended max polar angle in radians. */
  maxPolarAngle: number;
  /** Whether instanced rendering should be used for repeated meshes. */
  useInstancing: boolean;
  /** Entities eligible for instanced rendering, grouped by mesh signature. */
  instanceGroups: Record<string, string[]>;
  /** Shadow map resolution recommendation based on scene complexity. */
  recommendedShadowMapSize: number;
  /** Whether the scene is complex enough to benefit from frustum culling. */
  enableFrustumCulling: boolean;
}

// ─── Compiler Configuration ──────────────────────────────────────

/**
 * Configuration for the Scene Compiler.
 */
export interface SceneCompilerConfig {
  /** LOD configuration. */
  lod: LODConfig;
  /** Whether to enable automatic LOD generation via mesh decimation. */
  enableAutoLOD: boolean;
  /** Maximum texture size (pixels) for any LOD tier. */
  maxTextureSize: number;
  /** Whether to validate asset compatibility on ingest. */
  strictValidation: boolean;
  /** Cache directory path for compiled manifests. */
  cacheDirectory: string;
  /** Maximum cache size in bytes before LRU eviction. */
  maxCacheBytes: number;
  /**
   * Temporal interpolation resolution: number of pre-computed samples
   * between anchor years. Higher = smoother but larger manifest.
   * 0 = compute at runtime (smaller manifest, more CPU).
   */
  temporalSampleCount: number;
  /** Whether to emit source maps for debugging. */
  emitSourceMaps: boolean;
}

/**
 * Validation result for a single asset.
 */
export interface AssetValidationResult {
  assetId: string;
  valid: boolean;
  errors: ValidationError[];
  warnings: ValidationWarning[];
}

export interface ValidationError {
  code: string;
  message: string;
  /** Path to the problematic field or file. */
  path?: string;
}

export interface ValidationWarning {
  code: string;
  message: string;
  path?: string;
}

/**
 * Result of a compilation run.
 */
export interface CompilationResult {
  /** Whether the compilation succeeded. */
  success: boolean;
  /** The compiled manifest (only present on success). */
  manifest?: SceneManifest;
  /** Validation results per asset. */
  validationResults: AssetValidationResult[];
  /** Compilation duration in milliseconds. */
  durationMs: number;
  /** Any non-fatal warnings generated during compilation. */
  warnings: ValidationWarning[];
  /** Fatal errors that prevented compilation. */
  errors: ValidationError[];
  /** Cache hit information. */
  cache: {
    hit: boolean;
    /** How many cached assets were reused. */
    reusedAssets: number;
    /** How many assets were recompiled. */
    recompiledAssets: number;
  };
}

// ─── Compiler Public API ─────────────────────────────────────────

/**
 * Asset change event emitted by the Asset Store watcher.
 */
export interface AssetChangeEvent {
  type: 'added' | 'updated' | 'removed';
  asset: Asset;
  previousVersion?: string;
  timestamp: string;
}

/**
 * The Scene Compiler interface.
 *
 * Usage:
 * ```ts
 * const compiler = createSceneCompiler(config);
 * const result = await compiler.compileScene(assets);
 * if (result.success) {
 *   runtime.loadManifest(result.manifest);
 * }
 * ```
 */
export interface SceneCompiler {
  /**
   * Compile a full set of assets into a SceneManifest.
   *
   * This is a full recompilation: all assets are validated, scene graph
   * entries are generated, LODs are computed, and temporal transitions
   * are pre-baked. Use `updateEntity` for incremental updates.
   *
   * @param assets - All assets (mesh, texture, material) to compile.
   * @param fixture - The scene fixture defining entity placement and temporal spec.
   * @param config - Optional config overrides for this compilation run.
   * @returns A CompilationResult containing the manifest or errors.
   */
  compileScene(
    assets: Asset[],
    fixture: import('@fumira/contracts').SceneFixture,
    config?: Partial<SceneCompilerConfig>,
  ): Promise<CompilationResult>;

  /**
   * Incrementally update a single entity in the current manifest.
   *
   * This avoids a full recompilation when only one entity's asset changes.
   * The compiler patches the scene graph, re-computes LODs for that entity,
   * and updates temporal interpolation tables if affected.
   *
   * @param entityId - The ID of the entity to update.
   * @param newAsset - The new or updated asset for this entity.
   * @param newTemporalState - Optional updated temporal states for this entity.
   * @returns The patched manifest, or null if the entity doesn't exist.
   */
  updateEntity(
    entityId: string,
    newAsset: MeshAsset | MaterialAsset,
    newTemporalState?: Record<string, TemporalEntityState>,
  ): Promise<IncrementalUpdateResult>;

  /**
   * Get the current compiled scene manifest.
   *
   * @returns The current manifest, or null if no compilation has been run.
   */
  getSceneManifest(): SceneManifest | null;

  /**
   * Get the interpolated state of an entity at a specific time value.
   *
   * Time is expressed as a normalized year value. The compiler uses its
   * pre-baked interpolation tables for fast lookup, falling back to
   * runtime interpolation if temporalSampleCount was 0.
   *
   * @param entityId - The entity to query.
   * @param timeValue - A year value (e.g. 2026.5 for mid-2026).
   * @returns The interpolated entity state, or null if the entity has no temporal data.
   */
  getEntityAtTime(
    entityId: string,
    timeValue: number,
  ): InterpolatedEntityState | null;

  /**
   * Start watching the Asset Store for changes.
   * Emits events when assets are added, updated, or removed.
   *
   * @param assetStoreUrl - URL of the Asset Store API.
   * @returns An unsubscribe function.
   */
  watchAssetStore(assetStoreUrl: string): () => void;

  /**
   * Subscribe to compiler events (compilation progress, errors, cache hits).
   */
  on(event: SceneCompilerEvent, handler: (data: unknown) => void): () => void;

  /**
   * Validate a set of assets without compiling.
   * Useful for pre-flight checks in the editor.
   */
  validateAssets(assets: Asset[]): Promise<AssetValidationResult[]>;

  /**
   * Clear the compilation cache.
   */
  clearCache(): Promise<void>;

  /**
   * Dispose of all resources, stop watchers, close connections.
   */
  dispose(): void;
}

/**
 * Events emitted by the Scene Compiler.
 */
export type SceneCompilerEvent =
  | 'compilation:start'
  | 'compilation:progress'
  | 'compilation:complete'
  | 'compilation:error'
  | 'validation:complete'
  | 'cache:hit'
  | 'cache:miss'
  | 'asset:change'
  | 'incremental:update';

/**
 * Progress event payload during compilation.
 */
export interface CompilationProgress {
  phase: 'validation' | 'scene-graph' | 'lod-generation' | 'temporal-bake' | 'caching';
  /** 0..1 progress fraction. */
  progress: number;
  /** Current asset being processed (if applicable). */
  currentAssetId?: string;
  /** Human-readable status message. */
  message: string;
}

/**
 * Result of an incremental entity update.
 */
export interface IncrementalUpdateResult {
  success: boolean;
  /** The updated manifest (same object, mutated in place). */
  manifest: SceneManifest | null;
  /** Which parts of the manifest were affected. */
  affected: {
    sceneGraph: boolean;
    lod: boolean;
    temporal: boolean;
  };
  durationMs: number;
  errors: ValidationError[];
}

// ─── Factory Function ────────────────────────────────────────────

/**
 * Create a new Scene Compiler instance.
 */
export function createSceneCompiler(config?: Partial<SceneCompilerConfig>): SceneCompiler;

// ─── WebSocket Protocol ──────────────────────────────────────────

/**
 * WebSocket message types for real-time communication between the
 * Scene Compiler (server) and the Three.js Runtime (client).
 *
 * The WebSocket server runs alongside the existing Fastify server
 * in `server/index.js`. The Three.js display client connects to it
 * to receive live scene updates without polling.
 */

/**
 * Base structure for all WebSocket messages.
 */
export interface WSMessage {
  /** Message type identifier (dotted namespace). */
  type: string;
  /** ISO-8601 timestamp of when the message was created. */
  timestamp: string;
  /** Optional request ID for request/response correlation. */
  requestId?: string;
}

// ── scene.entity.added ─────────────────────────────────────────

/**
 * Emitted when a new entity is added to the scene after an Asset Store change.
 *
 * Server --> Client
 */
export interface WSEntityAdded extends WSMessage {
  type: 'scene.entity.added';
  payload: {
    /** The compiled entity definition. */
    entity: CompiledEntity;
    /** The scene graph node to insert. */
    node: SceneNodeDefinition;
    /** Parent node ID under which to insert. Null = scene root. */
    parentId: string | null;
    /** Insertion index among siblings. Null = append. */
    index: number | null;
  };
}

// ── scene.entity.updated ───────────────────────────────────────

/**
 * Emitted when an existing entity is modified (asset swap, material change, etc.).
 *
 * Server --> Client
 */
export interface WSEntityUpdated extends WSMessage {
  type: 'scene.entity.updated';
  payload: {
    entityId: string;
    /** Patch to apply to the scene graph node. Partial update. */
    nodePatch: Partial<SceneNodeDefinition>;
    /** Whether the LOD entries changed. */
    lodChanged: boolean;
    /** Whether temporal data changed. */
    temporalChanged: boolean;
    /** Updated interpolation tables (only if temporalChanged). */
    interpolationTables?: Record<string, InterpolationTable>;
  };
}

// ── scene.entity.removed ───────────────────────────────────────

/**
 * Emitted when an entity is removed from the scene.
 *
 * Server --> Client
 */
export interface WSEntityRemoved extends WSMessage {
  type: 'scene.entity.removed';
  payload: {
    entityId: string;
    /** Scene node ID to remove from the graph. */
    sceneNodeId: string;
    /** If true, the runtime should animate the entity out before removing. */
    animateOut: boolean;
  };
}

// ── scene.reconstruction.progress ──────────────────────────────

/**
 * Emitted periodically during a full scene recompilation to report progress.
 *
 * Server --> Client
 */
export interface WSReconstructionProgress extends WSMessage {
  type: 'scene.reconstruction.progress';
  payload: {
    /** Current compilation phase. */
    phase: CompilationProgress['phase'];
    /** 0..1 overall progress fraction. */
    overallProgress: number;
    /** 0..1 phase-specific progress fraction. */
    phaseProgress: number;
    /** Human-readable status message. */
    message: string;
    /** Number of assets processed so far. */
    assetsProcessed: number;
    /** Total number of assets to process. */
    assetsTotal: number;
  };
}

// ── scene.reconstruction.complete ──────────────────────────────

/**
 * Emitted when a full scene recompilation finishes successfully.
 * The client should swap in the new manifest.
 *
 * Server --> Client
 */
export interface WSReconstructionComplete extends WSMessage {
  type: 'scene.reconstruction.complete';
  payload: {
    /** The new manifest, ready to load. */
    manifest: SceneManifest;
    /** Compilation result metadata. */
    result: Pick<CompilationResult, 'durationMs' | 'cache' | 'warnings'>;
    /**
     * Diff summary: which entities changed vs the previous manifest.
     * The client can use this to selectively update rather than full reload.
     */
    diff: {
      added: string[];
      updated: string[];
      removed: string[];
      unchanged: string[];
    };
  };
}

// ── Client --> Server messages ──────────────────────────────────

/**
 * Client requests a full recompilation.
 */
export interface WSRecompileRequest extends WSMessage {
  type: 'scene.recompile.request';
  payload: {
    /** Optional: recompile only these entity IDs. Omit for full recompile. */
    entityIds?: string[];
    /** Optional: config overrides for this compilation. */
    configOverrides?: Partial<SceneCompilerConfig>;
  };
}

/**
 * Client requests the current manifest.
 */
export interface WSManifestRequest extends WSMessage {
  type: 'scene.manifest.request';
}

/**
 * Client requests interpolated entity state at a given time.
 */
export interface WSEntityQueryRequest extends WSMessage {
  type: 'scene.entity.query';
  payload: {
    entityId: string;
    timeValue: number;
  };
}

/**
 * Server response to a client request.
 */
export interface WSResponse extends WSMessage {
  type: 'scene.response';
  requestId: string;
  payload: {
    success: boolean;
    data?: unknown;
    error?: string;
  };
}

/**
 * Union of all server-to-client WebSocket messages.
 */
export type ServerWSMessage =
  | WSEntityAdded
  | WSEntityUpdated
  | WSEntityRemoved
  | WSReconstructionProgress
  | WSReconstructionComplete
  | WSResponse;

/**
 * Union of all client-to-server WebSocket messages.
 */
export type ClientWSMessage =
  | WSRecompileRequest
  | WSManifestRequest
  | WSEntityQueryRequest;

/**
 * Union of all WebSocket messages.
 */
export type AnyWSMessage = ServerWSMessage | ClientWSMessage;
