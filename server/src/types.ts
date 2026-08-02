export type GenerationStatus =
  | "queued"
  | "processing"
  | "succeeded"
  | "failed";

export type { GenerationTier } from "./tiers.js";

export type ImageGenerationProvider = "minimax" | "apimart";

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
}

/**
 * Precise target time — authoritative values set by the program, not the LLM.
 * `offsetYears` is for narrative/display only; `offsetDays` + `targetDateISO`
 * are the canonical identifiers for equality and dedup.
 */
export interface ExactTarget {
  offsetDays: number;
  targetDateISO: string;
  compactLabel: string;
}

// ---------------------------------------------------------------------------
// CreateGenerationBody — discriminated union (Task 4 & 6)
// ---------------------------------------------------------------------------

export type CreateGenerationBody = LegacyGenerationBody | StructuredGenerationBody;

export interface LegacyGenerationBody {
  contextVersion: "legacy.v1";
  sourceAssetId: string;
  timePosition: TimePositionPayload;
  /**
   * Deprecated client-authored prompt. Ignored when present — the server always
   * builds the authoritative core prompt from timePosition (+ optional bible/beat).
   */
  prompt?: string;
  /** Backward-compatible field for older app builds. Ignored for prompt authorship. */
  story?: string;
  /** Optional Scene Bible from source understanding (story-driven generation). */
  understanding?: SceneUnderstandingPayload;
  /** Optional full story; nearest beat is selected when storyBeat is omitted. */
  temporalStory?: TemporalStoryPayload;
  /** Optional explicit target beat for story-driven compilation. */
  storyBeat?: StoryBeatPayload;
  structuredContext?: never;
  aspectRatio?: AspectRatio;
  imageProvider?: ImageGenerationProvider;
  /** Optional APIMart vendor model id (e.g. gpt-image-2). Ignored for MiniMax. */
  imageModel?: string;
  /** Quality tier; resolves model, validation and repair budget when unset fields remain. */
  tier?: string;
  requestId: string;
  useSubjectReference?: boolean;
}

export interface StructuredGenerationBody {
  contextVersion: "generation.v2" | "generation.v3";
  sourceAssetId: string;
  timePosition: TimePositionPayload;
  story?: never;
  structuredContext: GenerationContext;
  aspectRatio?: AspectRatio;
  imageProvider?: ImageGenerationProvider;
  /** Optional APIMart vendor model id (e.g. gpt-image-2). Ignored for MiniMax. */
  imageModel?: string;
  /** Quality tier; resolves model, validation and repair budget when unset fields remain. */
  tier?: string;
  requestId: string;
  useSubjectReference?: boolean;
}

/**
 * Structured pipeline data the iOS client sends instead of a pre-built prompt.
 * The server's PromptCompiler owns the final provider prompt.
 */
export interface GenerationContext {
  schemaVersion: "generation-context.v2" | "generation-context.v3";
  understanding: SceneUnderstandingPayload;
  story: TemporalStoryPayloadV2;
  generationMode: GenerationMode;
}

export type GenerationMode =
  | "captured_target"
  | "story_preview_target"
  | "regenerate_same_target";

/**
 * V2 story payload — `targetBeat` is REQUIRED.
 * If the model omits it, the server must reject the payload rather than
 * silently falling back to the nearest canonical beat.
 */
export interface TemporalStoryPayloadV2 {
  schemaVersion: "temporal-story.v2" | "temporal-story.v3";
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
  imageProvider: ImageGenerationProvider;
  aspectRatio: AspectRatio;
  promptTruncated: boolean;
  promptCharCount: number;
  /** Prompt compiler version (e.g. "v2"). Absent for legacy flat prompts. */
  promptVersion?: string;
  /** SHA-256 hex of the compiled prompt for dedup / debugging. */
  promptHash?: string;
  /** Per-section character counts from the compiler. */
  sectionCharCounts?: Record<string, number>;
  /** Which sections were compressed or deleted. */
  truncatedSections?: string[];
  resultRelativeUrl?: string;
  /** Optional URL of the post-repair image (relative to PUBLIC_BASE_URL). */
  repairedResultRelativeUrl?: string;
  /** Number of repair attempts run so far; capped by the tier's repairRounds. */
  repairAttempts?: number;
  /** Resolved quality tier for this generation. */
  tier?: string;
  /** Last validation summary kept for admin telemetry; never returned to the app client. */
  validationSummary?: GenerationValidationResult;
  /** Mean of the seven validation metrics for the image that was finally served. */
  qualityScore?: number;
  /** Per-round validation means, oldest first, for offline prompt A/B analysis. */
  qualityHistory?: number[];
  errorCode?: string;
  userMessage?: string;
  retryable?: boolean;
  /** Admin-only diagnostic; never returned to the app client. */
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
  /** APIMart vendor model; MiniMax adapters ignore this. */
  modelName?: string;
  /**
   * Rejected image from the previous repair round. Adapters that accept multiple
   * reference images pass it alongside the source so the model can see what to fix.
   */
  priorAttemptDataUrl?: string;
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

export type ImageGenerationAdapter = MiniMaxAdapter;

export interface CameraLockPayload {
  viewpoint?: string;
  lensAndPerspective?: string;
  horizon?: string;
  depthStructure?: string;
}

export interface SpatialAnchorPayload {
  name: string;
  depth?: string;
  position?: string;
  geometry?: string;
  identityLock?: string;
}

export interface TemporalLayerPayload {
  layer: string;
  visibleEvidence?: string;
  pastPotential?: string;
  futurePotential?: string;
  confidence?: number;
}

export type SceneDepth = "foreground" | "midground" | "background" | "sky";

export type SceneRegionCategory =
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
  | "other";

export type TemporalPolicy =
  | "lock_geometry"
  | "age_in_place"
  | "evolve"
  | "replace_by_era"
  | "may_disappear"
  | "transient";

export interface SceneRegionPayload {
  id: string;
  depth: SceneDepth;
  category: SceneRegionCategory;
  description: string;
  spatialAnchor: string;
  materials: string[];
  currentCondition: string;
  confidence: number;
  salience: number;
  temporalPolicy: TemporalPolicy;
}

export interface SceneGraphPayload {
  baseline: {
    locationType: string;
    broadCulturalContext?: string;
    probableCaptureEra?: string;
    season?: string;
    timeOfDay?: string;
    weather?: string;
  };
  cameraLock: CameraLockPayload;
  regions: SceneRegionPayload[];
  globalDrivers: string[];
  uncertainties: string[];
}

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
  /** Optional Scene Bible extensions (backward compatible). */
  cameraLock?: CameraLockPayload;
  spatialAnchors?: SpatialAnchorPayload[];
  temporalLayers?: TemporalLayerPayload[];
  storySeeds?: string[];
  hardConstraints?: string[];
  /** Machine-facing scene decomposition. UI copy fields above stay concise. */
  sceneGraph?: SceneGraphPayload;
}

/** Character budgets for image-analysis copy rendered by the client. */
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
  /** Optional panoramic story fields (backward compatible). */
  transitionCause?: string;
  unchangedAnchors?: string[];
  foregroundDelta?: string;
  midgroundDelta?: string;
  backgroundDelta?: string;
  subjectDelta?: string;
  environmentDelta?: string;
  /** Program-generated exact target identity — present only on precise target beats. */
  exactTarget?: ExactTarget;
  /** Detailed machine-facing plan; never truncated to UI copy budgets. */
  renderPlan?: TemporalRenderPlan;
}

export type HorizonBand =
  | "hours_days"
  | "months"
  | "years"
  | "decades"
  | "centuries"
  | "millennia"
  | "deep_time";

export type SubjectContinuityMode =
  | "identity_persists"
  | "lineage_or_successor"
  | "object_remains"
  | "site_only"
  | "time_traveler";

export type RegionChangeAction =
  | "preserve"
  | "age"
  | "grow"
  | "renovate"
  | "replace"
  | "remove"
  | "add_related";

export type RegionChangeMagnitude =
  | "subtle"
  | "moderate"
  | "major"
  | "transformative";

export interface RegionTemporalChange {
  regionId: string;
  action: RegionChangeAction;
  magnitude: RegionChangeMagnitude;
  targetAppearance: string;
  causalReason: string;
}

export interface TemporalRenderPlan {
  exactTarget: ExactTarget;
  horizonBand: HorizonBand;
  subjectContinuityMode: SubjectContinuityMode;
  globalEraState: string;
  regionChanges: RegionTemporalChange[];
  crossRegionCouplings: string[];
  mustPreserve: string[];
  allowedEraAdditions: string[];
  prohibitedDrift: string[];
  coverage: {
    foreground: boolean;
    midground: boolean;
    background: boolean;
    builtEnvironment: boolean;
    naturalEnvironment: boolean;
    principalSubject: boolean;
  };
}

/** Response from POST /v1/target-beats */
export interface TargetBeatResponse {
  schemaVersion: "target-beat.v1";
  target: ExactTarget;
  targetBeat: StoryBeatPayload;
}

/**
 * V1 story payload — `targetBeat` is optional (for legacy/mock adapters).
 * The intelligence adapter should produce TemporalStoryPayloadV2 when possible.
 */
export interface TemporalStoryPayload {
  title: string;
  logline: string;
  presentTruth: string;
  identityRules: string[];
  beats: StoryBeatPayload[];
  /** Exact beat matching the user's chosen year — never the nearest canonical node. */
  targetBeat?: StoryBeatPayload;
}

/** Character budgets requested by the current client layout. */
export interface StoryCopyConstraints {
  title: number;
  logline: number;
  presentTruth: number;
  identityRule: number;
  beatTitle: number;
  beatNarrative: number;
  visualPrompt: number;
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
    targetTime: { offsetYears: number; compactLabel: string };
    copyConstraints: UnderstandingCopyConstraints;
    requestId: string;
    narrativeAnchor?: {
      normalizedX: number;
      normalizedY: number;
    };
    opticalContext?: CameraObservationPayload;
  }): Promise<MiniMaxIntelligenceResult<SceneUnderstandingPayload>>;
  writeStory(input: {
    understanding: SceneUnderstandingPayload;
    targetTime: ExactTarget;
    copyConstraints: StoryCopyConstraints;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<TemporalStoryPayload>>;
  writeExactTargetPlan(input: {
    understanding: SceneUnderstandingPayload;
    storyContext: {
      title: string;
      presentTruth: string;
      identityRules: string[];
      canonicalBeats: StoryBeatPayload[];
    };
    target: ExactTarget;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<StoryBeatPayload>>;
}

export interface CameraObservationPayload {
  lensPosition?: "front" | "back";
  focusPosition?: number;
  exposureDurationSeconds?: number;
  iso?: number;
  exposureTargetOffset?: number;
  zoomFactor?: number;
  lightCondition: "lowLight" | "balanced" | "bright" | "unknown";
}

/**
 * Dual-image VLM compare of source photo vs generated target photo.
 * Returned only when a generation passes through the optional post validator.
 */
export interface GenerationValidationResult {
  cameraConsistency: number;
  anchorPreservation: number;
  identityConsistency: number;
  temporalCoverage: number;
  environmentEvolution: number;
  eraCoherence: number;
  storyAlignment: number;
  unexplainedAdditions: string[];
  missedRequiredChanges: string[];
  problems: string[];
  repairInstructions: string[];
  shouldRegenerate: boolean;
}

export interface ValidationCopyConstraints {
  problem: 80;
  repairInstruction: 120;
}

export interface PostGenerationValidationInput {
  sourceBytes: Buffer;
  sourceContentType: string;
  targetBytes: Buffer;
  targetContentType: string;
  targetTime: { offsetYears: number; compactLabel: string };
  understanding: SceneUnderstandingPayload | null;
  storyBeat: StoryBeatPayload | null;
  requestId: string;
}

export type PostGenerationValidationResult =
  | { ok: true; value: GenerationValidationResult }
  | MiniMaxIntelligenceFailure;

export interface PostGenerationValidationAdapter {
  validate(
    input: PostGenerationValidationInput
  ): Promise<PostGenerationValidationResult>;
}

/** Same shape returned by the standalone parseValidationResponse helper. */
export interface RepairPlan {
  shouldRegenerate: boolean;
  problems: string[];
  repairInstructions: string[];
}
