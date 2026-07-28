import {
  DEFAULT_REPAIR_INSTRUCTION,
  parseValidationResponse,
  shouldAttemptRepair,
} from "./validation.js";
import {
  getAsset,
  readAssetBytes,
} from "./storage.js";
import { toJpegDataUrl } from "./prompt.js";
import type {
  GenerationValidationResult,
  PostGenerationValidationAdapter,
  PostGenerationValidationInput,
  PostGenerationValidationResult,
  RepairPlan,
  SceneUnderstandingPayload,
  StoryBeatPayload,
} from "./types.js";

let adapter: PostGenerationValidationAdapter | null = null;

export function setPostGenerationValidationAdapter(
  next: PostGenerationValidationAdapter | null
): void {
  adapter = next;
}

export function getPostGenerationValidationAdapter(): PostGenerationValidationAdapter | null {
  return adapter;
}

export async function runPostGenerationValidation(input: {
  sourceAssetId: string;
  sourceContentType: string;
  targetBytes: Buffer;
  targetContentType: string;
  targetTime: { offsetYears: number; compactLabel: string };
  understanding: SceneUnderstandingPayload | null;
  storyBeat: StoryBeatPayload | null;
  requestId: string;
}): Promise<PostGenerationValidationResult | null> {
  if (!adapter) return null;
  const sourceBytes = await readAssetBytes(input.sourceAssetId);
  if (!sourceBytes) {
    return {
      ok: false,
      errorCode: "validation_source_missing",
      userMessage: "源图片已失效，无法执行校验。",
      retryable: false,
    };
  }
  return adapter.validate({
    sourceBytes: sourceBytes.bytes,
    sourceContentType: input.sourceContentType,
    targetBytes: input.targetBytes,
    targetContentType: input.targetContentType,
    targetTime: input.targetTime,
    understanding: input.understanding,
    storyBeat: input.storyBeat,
    requestId: input.requestId,
  });
}

/**
 * Wrap raw VLM output through `parseValidationResponse` to a uniform result.
 * Exposed for tests and adapters that prefer to handle HTTP responses directly.
 */
export function decodeValidationPayload(raw: unknown): PostGenerationValidationResult {
  const value = parseValidationResponse(raw);
  if (!value) {
    return {
      ok: false,
      errorCode: "invalid_validation_response",
      userMessage: "校验模型返回的格式无法识别。",
      retryable: true,
    };
  }
  return { ok: true, value };
}

/** Convenience: build a {@link RepairPlan} or null when nothing actionable. */
export function planFromValidation(
  value: GenerationValidationResult
): RepairPlan | null {
  if (!shouldAttemptRepair(value)) return null;
  return {
    shouldRegenerate: true,
    problems: value.problems,
    repairInstructions: value.repairInstructions.length
      ? value.repairInstructions
      : [DEFAULT_REPAIR_INSTRUCTION],
  };
}

/** Source-only validation request, e.g. for batch QA tooling. */
export interface SourceOnlyValidationInput {
  sourceAssetId: string;
  targetBytes: Buffer;
  targetContentType: string;
  targetTime: { offsetYears: number; compactLabel: string };
  understanding: SceneUnderstandingPayload | null;
  storyBeat: StoryBeatPayload | null;
  requestId: string;
}

export type SourceOnlyValidationResult = PostGenerationValidationResult;

export async function runSourceOnlyValidation(
  input: SourceOnlyValidationInput
): Promise<SourceOnlyValidationResult | null> {
  if (!adapter) return null;
  const asset = await readAssetBytes(input.sourceAssetId);
  if (!asset) {
    return {
      ok: false,
      errorCode: "validation_source_missing",
      userMessage: "源图片已失效，无法执行校验。",
      retryable: false,
    };
  }
  return adapter.validate({
    sourceBytes: asset.bytes,
    sourceContentType: asset.contentType,
    targetBytes: input.targetBytes,
    targetContentType: input.targetContentType,
    targetTime: input.targetTime,
    understanding: input.understanding,
    storyBeat: input.storyBeat,
    requestId: input.requestId,
  });
}
