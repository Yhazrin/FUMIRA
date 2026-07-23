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

export interface CreateGenerationBody {
  sourceAssetId: string;
  timePosition: TimePositionPayload;
  story: string;
  aspectRatio?: AspectRatio;
  requestId: string;
  /** Explicit opt-in for single-person portrait subject_reference. Default false. */
  useSubjectReference?: boolean;
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
