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
  story: string;
  structuredContext?: never;
  aspectRatio?: AspectRatio;
  requestId: string;
  useSubjectReference?: boolean;
}

export interface StructuredGenerationBody {
  contextVersion: "generation.v2";
  sourceAssetId: string;
  timePosition: TimePositionPayload;
  story?: never;
  structuredContext: GenerationContext;
  aspectRatio?: AspectRatio;
  requestId: string;
  useSubjectReference?: boolean;
}

/**
 * Structured pipeline data the iOS client sends instead of a pre-built prompt.
 * The server's PromptCompiler owns the final provider prompt.
 */
export interface GenerationContext {
  schemaVersion: "generation-context.v2";
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
  /** Prompt compiler version (e.g. "v2"). Absent for legacy flat prompts. */
  promptVersion?: string;
  /** SHA-256 hex of the compiled prompt for dedup / debugging. */
  promptHash?: string;
  /** Per-section character counts from the compiler. */
  sectionCharCounts?: Record<string, number>;
  /** Which sections were compressed or deleted. */
  truncatedSections?: string[];
  resultRelativeUrl?: string;
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
  /** Program-generated exact target identity — present only on precise target beats. */
  exactTarget?: ExactTarget;
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
    copyConstraints: UnderstandingCopyConstraints;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<SceneUnderstandingPayload>>;
  writeStory(input: {
    understanding: SceneUnderstandingPayload;
    targetTime: ExactTarget;
    copyConstraints: StoryCopyConstraints;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<TemporalStoryPayload>>;
}
