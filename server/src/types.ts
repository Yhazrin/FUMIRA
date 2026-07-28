export type GenerationStatus =
  | "queued"
  | "processing"
  | "succeeded"
  | "failed";

export type AspectRatio =
  | "1:1"
  | "16:9"
  | "4:3"
  | "3:2"
  | "2:3"
  | "3:4"
  | "9:16"
  | "21:9";

export interface UploadedAsset {
  assetId: string;
  contentType: string;
  byteLength: number;
  absolutePath: string;
  createdAt: string;
}

export interface TimePositionPayload {
  normalized: number;
  offsetDays: number;
  offsetYears: number;
  compactLabel: string;
  /** Optional capture/source date. When absent, offsetDays remains authoritative. */
  sourceDateISO?: string;
}

/** Program-authoritative target time. */
export interface ExactTarget {
  offsetDays: number;
  targetDateISO: string;
  compactLabel: string;
}

export type GenerationMode =
  | "captured_target"
  | "story_preview_target"
  | "regenerate_same_target";

// ---------------------------------------------------------------------------
// V3 machine-facing world representation
// ---------------------------------------------------------------------------

export type ScreenZone =
  | "top_left"
  | "top_center"
  | "top_right"
  | "middle_left"
  | "center"
  | "middle_right"
  | "bottom_left"
  | "bottom_center"
  | "bottom_right";

export type SceneDepth = "foreground" | "midground" | "background" | "sky";

export type SceneCategory =
  | "person"
  | "animal"
  | "vehicle"
  | "vegetation"
  | "architecture"
  | "infrastructure"
  | "surface"
  | "signage"
  | "furniture"
  | "landscape"
  | "atmosphere"
  | "other";

export type RegionPersistence =
  | "persistent_identity"
  | "persistent_geometry"
  | "replaceable"
  | "transient"
  | "unknown";

export type TemporalPolicy =
  | "lock"
  | "age_in_place"
  | "grow"
  | "renovate"
  | "replace_by_era"
  | "may_disappear"
  | "free_evolution";

export interface NormalizedBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface SceneRegion {
  id: string;
  screenZone: ScreenZone;
  boundingBox?: NormalizedBox;
  depth: SceneDepth;
  category: SceneCategory;
  sourceState: {
    description: string;
    materials: string[];
    condition: string;
    identityFeatures: string[];
  };
  persistence: RegionPersistence;
  temporalPolicy: TemporalPolicy;
  confidence: number;
  salience: number;
}

export interface TemporalDriver {
  id: string;
  process: string;
  affectedRegionIds: string[];
  confidence: number;
}

export interface SceneGraph {
  schemaVersion: "scene-graph.v1";
  baseline: {
    locationType: string;
    probableEra?: string;
    season?: string;
    timeOfDay?: string;
    weather?: string;
    culturalContext?: string;
  };
  camera: {
    viewpoint: string;
    framing: string;
    horizon: string;
    perspective: string;
    vanishingPoints: string[];
    depthLayout: string;
  };
  regions: SceneRegion[];
  globalDrivers: TemporalDriver[];
  uncertainties: string[];
}

export type TimeHorizonBand =
  | "hours_days"
  | "months"
  | "years"
  | "decades"
  | "centuries"
  | "millennia"
  | "deep_time";

export type SubjectContinuityMode =
  | "identity_persists"
  | "age_progression"
  | "lineage_or_successor"
  | "object_remains"
  | "site_only"
  | "time_traveler";

export type RegionTemporalAction =
  | "preserve"
  | "age"
  | "grow"
  | "renovate"
  | "replace"
  | "remove"
  | "add_related";

export type ChangeMagnitude =
  | "subtle"
  | "moderate"
  | "major"
  | "transformative";

export interface RegionTemporalChange {
  regionId: string;
  action: RegionTemporalAction;
  magnitude: ChangeMagnitude;
  targetState: string;
  causalReason: string;
  visibleEvidence: string[];
}

export interface EraAddition {
  id: string;
  screenZone: ScreenZone;
  depth: SceneDepth;
  category: SceneCategory;
  description: string;
  causalReason: string;
}

export interface RegionRemoval {
  regionId: string;
  causalReason: string;
  replacementState?: string;
}

export interface CrossRegionCoupling {
  regionIds: string[];
  rule: string;
}

export interface TemporalRenderPlan {
  schemaVersion: "temporal-render-plan.v1";
  planId: string;
  exactTarget: ExactTarget;
  horizonBand: TimeHorizonBand;
  globalWorldState: {
    eraSummary: string;
    environmentalState: string;
    technologyState: string;
    humanActivityState: string;
  };
  regionChanges: RegionTemporalChange[];
  additions: EraAddition[];
  removals: RegionRemoval[];
  crossRegionCouplings: CrossRegionCoupling[];
  unchangedRegionIds: string[];
  subjectContinuityMode: SubjectContinuityMode;
  prohibitedDrift: string[];
  coverage: {
    evaluatedRegionIds: string[];
    changedRegionIds: string[];
    unchangedRegionIds: string[];
    changedDomains: SceneCategory[];
    foreground: boolean;
    midground: boolean;
    background: boolean;
    principalSubject: boolean;
    builtEnvironment: boolean;
    naturalEnvironment: boolean;
    technologyInfrastructure: boolean;
  };
}

export interface VisualCriticResult {
  schemaVersion: "visual-critic.v1";
  passed: boolean;
  cameraConsistency: number;
  spatialTopologyConsistency: number;
  principalIdentityConsistency: number;
  requiredChangeCompletion: number;
  environmentEvolution: number;
  eraCoherence: number;
  missedRegionChanges: string[];
  unexplainedChanges: string[];
  cameraDrift: string[];
  correctionInstruction: string;
}

export interface QualityPolicy {
  visualCriticEnabled: boolean;
  maxRegenerations: 0 | 1;
  thresholds: {
    cameraConsistency: number;
    requiredChangeCompletion: number;
    environmentEvolution: number;
    eraCoherence: number;
  };
}

export interface QualityPolicyOverride {
  visualCriticEnabled?: boolean;
  maxRegenerations?: 0 | 1;
  thresholds?: Partial<QualityPolicy["thresholds"]>;
}

// ---------------------------------------------------------------------------
// Request contracts
// ---------------------------------------------------------------------------

export type CreateGenerationBody =
  | LegacyGenerationBody
  | StructuredGenerationBodyV2
  | StructuredGenerationBodyV3;

export interface LegacyGenerationBody {
  contextVersion: "legacy.v1";
  sourceAssetId: string;
  timePosition: TimePositionPayload;
  story: string;
  structuredContext?: never;
  aspectRatio?: AspectRatio;
  requestId: string;
  useSubjectReference?: boolean;
}

export interface StructuredGenerationBodyV2 {
  contextVersion: "generation.v2";
  sourceAssetId: string;
  timePosition: TimePositionPayload;
  story?: never;
  structuredContext: GenerationContext;
  aspectRatio?: AspectRatio;
  requestId: string;
  useSubjectReference?: boolean;
}

/** Backward-compatible alias used by older server modules. */
export type StructuredGenerationBody = StructuredGenerationBodyV2;

export interface StructuredGenerationBodyV3 {
  contextVersion: "generation.v3";
  sourceAssetId: string;
  timePosition: TimePositionPayload;
  story?: never;
  structuredContext: GenerationContextV3;
  aspectRatio?: AspectRatio;
  requestId: string;
  useSubjectReference?: boolean;
}

export interface GenerationContext {
  schemaVersion: "generation-context.v2";
  understanding: SceneUnderstandingPayload;
  story: TemporalStoryPayloadV2;
  generationMode: GenerationMode;
}

export interface GenerationContextV3 {
  schemaVersion: "generation-context.v3";
  sceneGraph: SceneGraph;
  targetPlan: TemporalRenderPlan;
  temporalStory?: TemporalStoryPayloadV2;
  generationMode: GenerationMode;
  qualityPolicy?: QualityPolicyOverride;
}

export interface TemporalStoryPayloadV2 {
  schemaVersion: "temporal-story.v2";
  title: string;
  logline: string;
  presentTruth: string;
  identityRules: string[];
  beats: StoryBeatPayload[];
  targetBeat: StoryBeatPayload;
}

export interface GenerationRecord {
  generationId: string;
  requestId: string;
  sourceAssetId: string;
  status: GenerationStatus;
  createdAt: string;
  updatedAt: string;
  startedAt?: string;
  finishedAt?: string;
  durationMs?: number;
  modelName: string;
  aspectRatio: AspectRatio;
  promptTruncated: boolean;
  promptCharCount: number;
  promptVersion?: string;
  promptHash?: string;
  sectionCharCounts?: Record<string, number>;
  truncatedSections?: string[];
  renderPlanId?: string;
  visualCritic?: VisualCriticResult;
  regenerationCount?: number;
  resultRelativeUrl?: string;
  errorCode?: string;
  userMessage?: string;
  retryable?: boolean;
  statusMsg?: string;
}

export interface AdminSettings {
  remoteGenerationEnabled: boolean;
  promptTemplate: string;
  modelName: string;
}

export interface MiniMaxGenerateInput {
  prompt: string;
  imageDataUrl: string;
  aspectRatio: AspectRatio;
  useSubjectReference: boolean;
  requestId: string;
  generationId: string;
}

export interface MiniMaxGenerateSuccess {
  ok: true;
  imageBytes: Buffer;
  contentType: string;
}

export interface MiniMaxGenerateFailure {
  ok: false;
  errorCode: string;
  userMessage: string;
  retryable: boolean;
  statusMsg?: string;
  httpStatus?: number;
}

export type MiniMaxGenerateResult =
  | MiniMaxGenerateSuccess
  | MiniMaxGenerateFailure;

export interface MiniMaxAdapter {
  generate(input: MiniMaxGenerateInput): Promise<MiniMaxGenerateResult>;
}

// ---------------------------------------------------------------------------
// V2 client-facing intelligence payloads
// ---------------------------------------------------------------------------

export interface SceneUnderstandingPayload {
  summary: string;
  locationType: string;
  visualMood: string;
  timeClues: string[];
  changeDrivers: string[];
  subjects: Array<{
    name: string;
    confidence: number;
    identityRule: string;
  }>;
}

export interface UnderstandingCopyConstraints {
  summary: number;
  locationType: number;
  visualMood: number;
  timeClue: number;
  changeDriver: number;
  subjectName: number;
  identityRule: number;
}

export interface StoryBeatPayload {
  anchorYears: number;
  title: string;
  narrative: string;
  visualPrompt: string;
  exactTarget?: ExactTarget;
}

export interface TargetBeatResponse {
  schemaVersion: "target-beat.v1";
  target: ExactTarget;
  targetBeat: StoryBeatPayload;
}

export interface TemporalStoryPayload {
  title: string;
  logline: string;
  presentTruth: string;
  identityRules: string[];
  beats: StoryBeatPayload[];
  targetBeat?: StoryBeatPayload;
}

export interface StoryCopyConstraints {
  title: number;
  logline: number;
  presentTruth: number;
  identityRule: number;
  beatTitle: number;
  beatNarrative: number;
  visualPrompt: number;
}

export interface StoryContinuityContext {
  title: string;
  presentTruth: string;
  identityRules: string[];
  canonicalBeats: Array<{
    anchorYears: number;
    title: string;
    narrative: string;
    visualPrompt: string;
  }>;
}

export interface MiniMaxIntelligenceFailure {
  ok: false;
  errorCode: string;
  userMessage: string;
  retryable: boolean;
  statusMsg?: string;
}

export type MiniMaxIntelligenceResult<T> =
  | { ok: true; value: T }
  | MiniMaxIntelligenceFailure;

export interface MiniMaxIntelligenceAdapter {
  analyzeImage(input: {
    imageDataUrl: string;
    copyConstraints: UnderstandingCopyConstraints;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<SceneUnderstandingPayload>>;

  writeStory(input: {
    understanding: SceneUnderstandingPayload;
    targetTime: ExactTarget;
    copyConstraints: StoryCopyConstraints;
    requestId: string;
    storyContext?: StoryContinuityContext;
    exactTargetOnly?: boolean;
  }): Promise<MiniMaxIntelligenceResult<TemporalStoryPayload>>;

  analyzeSceneGraph?(input: {
    imageDataUrl: string;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<SceneGraph>>;

  planTemporalRender?(input: {
    sceneGraph: SceneGraph;
    exactTarget: ExactTarget;
    storyContext?: StoryContinuityContext;
    continuityMode?: SubjectContinuityMode;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<TemporalRenderPlan>>;

  critiqueGeneration?(input: {
    sourceSceneGraph: SceneGraph;
    generatedSceneGraph: SceneGraph;
    targetPlan: TemporalRenderPlan;
    qualityPolicy: QualityPolicy;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<VisualCriticResult>>;
}
