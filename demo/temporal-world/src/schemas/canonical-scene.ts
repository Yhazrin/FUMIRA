// Canonical Scene Spec — the universal scene description
// Every service reads/writes this format.

export interface CanonicalSceneSpec {
  version: 2;
  sceneId: string;
  createdAt: string;
  source: SceneSource;

  // The scene hierarchy
  entities: CanonicalEntity[];

  // Spatial layout
  ground: GroundSpec;

  // Camera defaults
  camera: CameraSpec;

  // Lighting profile
  lighting: LightingProfile;

  // Temporal anchors (key years with pre-computed states)
  temporalAnchors: TemporalAnchor[];

  // Story narrative across time
  temporalStory?: TemporalStory;

  // Style constraints
  style: StyleProfile;

  // Metadata
  metadata: SceneMetadata;
}

export interface SceneSource {
  type: 'photo' | 'text' | 'sketch';
  inputPath: string;         // original photo/sketch path
  visionAnalysis?: string;   // Xiaomi vision output
  generatedAt: string;
}

export interface CanonicalEntity {
  id: string;
  type: EntityType;
  label: string;
  description?: string;

  // Spatial
  position: [number, number, number];
  rotation: [number, number, number];
  scale: [number, number, number];

  // Geometry spec (what Clay Builder to use)
  geometry: GeometrySpec;

  // Material spec
  material: MaterialSpec;

  // Temporal behavior
  temporalBehavior: TemporalBehavior;

  // Variants (different visual states)
  variants: EntityVariant[];

  // Build status
  buildStatus: 'pending' | 'blockout' | 'refined' | 'failed';
  buildLog?: string;

  // Confidence from vision
  confidence: number;
}

export type EntityType =
  | 'building' | 'tree' | 'vehicle' | 'person'
  | 'road' | 'path' | 'water' | 'prop' | 'terrain'
  | 'furniture' | 'sign' | 'light-pole' | 'bench';

export interface GeometrySpec {
  builder: string;  // which Clay Builder function to use
  parameters: Record<string, number | string | boolean>;
  // Example: { builder: 'stylized-building', parameters: { floors: 4, width: 3.8, cornerRadius: 0.14 } }
}

export interface MaterialSpec {
  color: string;           // hex color
  roughness: number;       // 0-1
  metalness: number;       // 0-1 (usually 0 for clay)
  clearcoat: number;       // 0-1
  opacity: number;         // 0-1
  emissive?: string;
  emissiveIntensity?: number;
  textureRef?: string;     // reference to texture asset
}

export interface TemporalBehavior {
  // How this entity changes over time
  mode: 'static' | 'grow' | 'decay' | 'transform' | 'appear' | 'disappear' | 'custom';

  // For grow/decay: rate per year
  rate?: number;

  // For transform: what it transforms into
  transformTo?: string;  // entity type

  // Custom interpolation tables
  interpolationTables?: Record<string, InterpolationTable>;
}

export interface InterpolationTable {
  keyframes: { time: number; value: number }[];
  easing: 'linear' | 'ease-in' | 'ease-out' | 'ease-in-out';
}

export interface EntityVariant {
  id: string;
  label: string;
  timeRange: [number, number];  // normalized -1 to 1
  geometry?: Partial<GeometrySpec>;
  material?: Partial<MaterialSpec>;
  position?: [number, number, number];
  scale?: [number, number, number];
}

export interface TemporalAnchor {
  normalizedTime: number;  // -1 to 1
  year: number;            // actual year
  label: string;           // e.g., "2016", "2026", "2036"

  // Entity states at this anchor
  entityStates: Record<string, AnchorEntityState>;

  // Scene-level changes
  sceneChanges?: {
    lighting?: Partial<LightingProfile>;
    camera?: Partial<CameraSpec>;
  };
}

export interface AnchorEntityState {
  visible: boolean;
  position?: [number, number, number];
  scale?: [number, number, number];
  material?: Partial<MaterialSpec>;
  variantId?: string;
}

export interface TemporalStory {
  title: string;
  description: string;
  keyEvents: StoryEvent[];
}

export interface StoryEvent {
  time: number;        // normalized
  year: number;
  title: string;
  description: string;
  affectedEntities: string[];
}

export interface StyleProfile {
  name: string;        // e.g., 'soft-clay', 'paper-craft', 'wireframe'
  globalRoughness: [number, number];  // min, max
  globalMetalness: [number, number];
  bevelRadius: [number, number];      // min, max
  colorPalette: string[];             // allowed colors
  lightingMood: 'warm' | 'cool' | 'neutral' | 'dramatic';
}

export interface LightingProfile {
  key: LightSpec;
  fill: LightSpec;
  rim: LightSpec;
  ambient: LightSpec;
  contactShadow: boolean;
  shadowIntensity: number;
}

export interface LightSpec {
  color: string;
  intensity: number;
  position: [number, number, number];
}

export interface CameraSpec {
  position: [number, number, number];
  target: [number, number, number];
  fov: number;
  near: number;
  far: number;
}

export interface GroundSpec {
  size: [number, number];
  color: string;
  roughness: number;
  receiveShadow: boolean;
}

export interface SceneMetadata {
  description: string;
  dominantColors: string[];
  complexity: 'low' | 'medium' | 'high';
  estimatedEntities: number;
  sourcePhotoSize?: [number, number];
  xiaomiAnalysis?: string;
  claudeRefinement?: string;
}
