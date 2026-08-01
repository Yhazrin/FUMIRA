// diorama/contracts.ts — Shared type definitions for the Diorama Runtime.
// Desktop and iOS consume the EXACT same scene graph structure.
// No platform-specific types leak into these contracts.

// ---------------------------------------------------------------------------
// Time
// ---------------------------------------------------------------------------

/** Normalized time value: -1 = earliest, 1 = latest, 0 = present. */
export interface TimeValue {
  normalized: number; // -1 … 1
  year?: number;      // optional concrete year for display
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

export interface GeometrySpec {
  type: 'box' | 'cylinder' | 'sphere' | 'plane' | 'blob';
  width?: number;
  height?: number;
  depth?: number;
  radius?: number;
  radiusTop?: number;
  radiusBottom?: number;
  segments?: number;
  /** REQUIRED — minimum 0.02. Gives clay-like softness to every edge. */
  bevelRadius: number;
  /** Squash factor for blob type (0–1, default 0 = sphere). */
  squash?: number;
  /** Seed for deterministic blob noise — never use Math.random at runtime. */
  seed?: number;
}

// ---------------------------------------------------------------------------
// Material
// ---------------------------------------------------------------------------

export interface MaterialSpec {
  /** Hex colour string, e.g. "#ff8844". */
  color: string;
  /** 0–1, per-entity, NOT shared across entities. */
  roughness: number;
  /** 0–1, usually 0 for clay look. */
  metalness: number;
  /** 0–1, clearcoat layer. */
  clearcoat: number;
  /** 0–1, opacity. */
  opacity: number;
  /** Optional emissive hex colour. */
  emissive?: string;
  /** Emissive intensity multiplier. */
  emissiveIntensity?: number;
}

// ---------------------------------------------------------------------------
// Transform
// ---------------------------------------------------------------------------

export interface TransformSpec {
  position: [number, number, number];
  rotation: [number, number, number]; // Euler radians
  scale: [number, number, number];
}

// ---------------------------------------------------------------------------
// Entity
// ---------------------------------------------------------------------------

export interface Entity {
  id: string;
  type: 'building' | 'tree' | 'vehicle' | 'terrain' | 'prop' | 'path';
  geometry: GeometrySpec;
  material: MaterialSpec;
  transform: TransformSpec;
  /** Temporal range as normalised pair: [-1, 1] means always visible. */
  temporalRange: [number, number];
  label: string;
  confidence: number;
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

export interface CameraSpec {
  position: [number, number, number];
  target: [number, number, number];
  fov: number;
  near: number;
  far: number;
  /** Optional offset applied in portrait orientation for mobile framing. */
  portraitOffset?: [number, number];
}

// ---------------------------------------------------------------------------
// Lighting
// ---------------------------------------------------------------------------

export interface LightSpec {
  color: string;
  intensity: number;
  position: [number, number, number];
}

export interface LightingSpec {
  key: LightSpec;
  fill: LightSpec;
  rim: LightSpec;
  ambient: LightSpec;
  contactShadow: boolean;
}

// ---------------------------------------------------------------------------
// Scene metadata
// ---------------------------------------------------------------------------

export interface SceneMetadata {
  description: string;
  dominantColors: string[];
  complexity: 'low' | 'medium' | 'high';
  estimatedVertices: number;
  generatedAt: string;
  sourceJobId?: string;
}

// ---------------------------------------------------------------------------
// Scene graph — the single source of truth
// ---------------------------------------------------------------------------

export interface SceneGraph {
  version: number;
  entities: Entity[];
  camera: CameraSpec;
  lighting: LightingSpec;
  metadata: SceneMetadata;
}

// ---------------------------------------------------------------------------
// Runtime state (read-only snapshot)
// ---------------------------------------------------------------------------

export interface SceneState {
  currentTime: number;       // normalised -1…1
  selectedEntityId: string | null;
  entityCount: number;
  isReady: boolean;
}

// ---------------------------------------------------------------------------
// Bridge messages — every message carries version + timestamp
// ---------------------------------------------------------------------------

export interface BridgeMessage {
  version: 1;
  type:
    | 'diorama.ready'
    | 'time.set'
    | 'entity.select'
    | 'entity.clear'
    | 'entity.selected'
    | 'runtime.error';
  payload: any;
  timestamp: number;
}

// Payloads for strongly-typed send/receive helpers ---------------

export interface ReadyPayload {
  sceneState: SceneState;
}

export interface TimeSetPayload {
  normalized: number;
}

export interface EntitySelectPayload {
  entityId: string;
}

export interface EntityClearPayload {}

export interface EntitySelectedPayload {
  entityId: string | null;
  label?: string;
}

export interface RuntimeErrorPayload {
  message: string;
  stack?: string;
}

// ---------------------------------------------------------------------------
// Convenience type guard
// ---------------------------------------------------------------------------

export function isBridgeMessage(value: unknown): value is BridgeMessage {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as BridgeMessage).version === 1 &&
    typeof (value as BridgeMessage).type === 'string'
  );
}
