import { getAsset, readAssetBytes } from "./storage.js";
import { toJpegDataUrl } from "./prompt.js";
import type {
  ExactTarget,
  MiniMaxIntelligenceAdapter,
  SceneUnderstandingPayload,
  StoryBeatPayload,
  StoryCopyConstraints,
  TemporalStoryPayloadV2,
  UnderstandingCopyConstraints,
} from "./types.js";
import { normalizeTemporalStoryCopy, promoteToV3 } from "./storyCopy.js";
import { normalizeSceneUnderstandingCopy } from "./understandingCopy.js";

let adapter: MiniMaxIntelligenceAdapter | null = null;

export function setMiniMaxIntelligenceAdapter(next: MiniMaxIntelligenceAdapter | null): void {
  adapter = next;
}

export function getMiniMaxIntelligenceAdapter(): MiniMaxIntelligenceAdapter | null {
  return adapter;
}

export async function analyzeUploadedAsset(input: {
  sourceAssetId: string;
  targetTime: { offsetYears: number; compactLabel: string };
  copyConstraints: UnderstandingCopyConstraints;
  requestId: string;
}) {
  if (!adapter) return unavailable("understanding_unavailable", "图片理解暂未就绪。");
  if (!input.sourceAssetId || !getAsset(input.sourceAssetId)) {
    return unavailable("invalid_source_asset", "源图片不存在或已过期。", false);
  }
  const asset = await readAssetBytes(input.sourceAssetId);
  if (!asset) return unavailable("invalid_image", "源图片无法读取。", false);
  const result = await adapter.analyzeImage({
    imageDataUrl: toJpegDataUrl(asset.bytes, asset.contentType),
    targetTime: input.targetTime,
    copyConstraints: input.copyConstraints,
    requestId: input.requestId,
  });
  if (!result.ok) return result;
  return {
    ok: true as const,
    value: normalizeSceneUnderstandingCopy(result.value, input.copyConstraints),
  };
}

export async function writeTemporalStory(input: {
  understanding: SceneUnderstandingPayload;
  targetTime: ExactTarget;
  copyConstraints: StoryCopyConstraints;
  requestId: string;
}): Promise<
  | { ok: true; value: TemporalStoryPayloadV2 }
  | { ok: false; errorCode: string; userMessage: string; retryable: boolean; statusMsg?: string }
> {
  if (!adapter) return unavailable("story_unavailable", "时间故事暂未就绪。");
  const storyResult = await adapter.writeStory(input);
  if (!storyResult.ok) return storyResult;
  const normalizedStory = normalizeTemporalStoryCopy(
    storyResult.value,
    input.copyConstraints
  );
  const targetResult = await adapter.writeExactTargetPlan({
    understanding: input.understanding,
    storyContext: {
      title: normalizedStory.title,
      presentTruth: normalizedStory.presentTruth,
      identityRules: normalizedStory.identityRules,
      canonicalBeats: normalizedStory.beats,
    },
    target: input.targetTime,
    requestId: input.requestId,
  });
  if (!targetResult.ok) return targetResult;
  if (!targetResult.value.renderPlan) {
    return unavailable(
      "missing_exact_target_plan",
      "精确目标时间缺少场景渲染计划，请重试。"
    );
  }
  return {
    ok: true,
    value: promoteToV3(
      normalizedStory,
      targetResult.value,
      input.copyConstraints
    ),
  };
}

/**
 * Generate a single exact target beat for a browse-year generation.
 * The model produces narrative + visual changes for the exact requested year;
 * the server overwrites anchorYears and attaches the program-authoritative
 * ExactTarget identity so the client can verify match.
 */
export async function writeTargetBeat(input: {
  understanding: SceneUnderstandingPayload;
  storyContext: {
    title: string;
    presentTruth: string;
    identityRules: string[];
    canonicalBeats: Array<{ anchorYears: number; title: string; narrative: string; visualPrompt: string }>;
  };
  target: ExactTarget;
  requestId: string;
}): Promise<
  | { ok: true; targetBeat: StoryBeatPayload }
  | { ok: false; errorCode: string; userMessage: string; retryable: boolean; statusMsg?: string }
> {
  if (!adapter) return unavailable("story_unavailable", "时间故事暂未就绪。");

  const result = await adapter.writeExactTargetPlan({
    understanding: input.understanding,
    storyContext: {
      title: input.storyContext.title,
      presentTruth: input.storyContext.presentTruth,
      identityRules: input.storyContext.identityRules,
      canonicalBeats: input.storyContext.canonicalBeats,
    },
    target: input.target,
    requestId: input.requestId,
  });
  if (!result.ok) return result;
  if (!result.value.renderPlan) {
    return unavailable(
      "missing_exact_target_plan",
      "精确目标时间缺少场景渲染计划，请重试。"
    );
  }
  return { ok: true, targetBeat: result.value };
}

function unavailable(errorCode: string, userMessage: string, retryable = true) {
  return { ok: false as const, errorCode, userMessage, retryable };
}
