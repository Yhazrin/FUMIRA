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
import { normalizeTemporalStoryCopy, promoteToV2 } from "./storyCopy.js";
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
  const result = await adapter.writeStory(input);
  if (!result.ok) return result;

  // generation.v2 promises an exact target beat. Silently substituting a
  // nearby canonical beat makes the contract appear valid while rendering the
  // wrong year, so fail visibly and allow a clean retry instead.
  if (!result.value.targetBeat) {
    return invalidAIResponse("时间故事缺少精确目标节点，请重试。");
  }

  const targetOffsetYears = input.targetTime.offsetDays / 365.25;
  const v2 = promoteToV2(result.value, targetOffsetYears, input.copyConstraints);
  return { ok: true, value: v2 };
}

/**
 * Generate one exact target beat for a browse-year generation while retaining
 * the causal and identity contract of the story the user is already browsing.
 */
export async function writeTargetBeat(input: {
  understanding: SceneUnderstandingPayload;
  storyContext: {
    title: string;
    presentTruth: string;
    identityRules: string[];
    canonicalBeats: Array<{
      anchorYears: number;
      title: string;
      narrative: string;
      visualPrompt: string;
    }>;
  };
  target: ExactTarget;
  requestId: string;
}): Promise<
  | { ok: true; targetBeat: StoryBeatPayload }
  | { ok: false; errorCode: string; userMessage: string; retryable: boolean; statusMsg?: string }
> {
  if (!adapter) return unavailable("story_unavailable", "时间故事暂未就绪。");

  const targetOffsetYears = input.target.offsetDays / 365.25;
  const result = await adapter.writeStory({
    understanding: input.understanding,
    targetTime: input.target,
    copyConstraints: {
      title: 16,
      logline: 56,
      presentTruth: 72,
      identityRule: 48,
      beatTitle: 14,
      beatNarrative: 72,
      visualPrompt: 110,
    },
    requestId: input.requestId,
    storyContext: input.storyContext,
    exactTargetOnly: true,
  } as Parameters<MiniMaxIntelligenceAdapter["writeStory"]>[0]);

  if (!result.ok) return result;
  if (!result.value.targetBeat) {
    return invalidAIResponse("精确年份节点生成失败，请重试。");
  }

  const normalized = normalizeTemporalStoryCopy(
    { ...result.value, beats: result.value.beats },
    {
      title: 16,
      logline: 56,
      presentTruth: 72,
      identityRule: 48,
      beatTitle: 14,
      beatNarrative: 72,
      visualPrompt: 110,
    }
  );
  const modelBeat = normalized.targetBeat;
  if (!modelBeat) return invalidAIResponse("精确年份节点生成失败，请重试。");

  const targetBeat: StoryBeatPayload = {
    anchorYears: targetOffsetYears,
    title: modelBeat.title,
    narrative: modelBeat.narrative,
    visualPrompt: modelBeat.visualPrompt,
    exactTarget: input.target,
  };

  return { ok: true, targetBeat };
}

function invalidAIResponse(userMessage: string) {
  return {
    ok: false as const,
    errorCode: "invalid_ai_response",
    userMessage,
    retryable: true,
  };
}

function unavailable(errorCode: string, userMessage: string, retryable = true) {
  return { ok: false as const, errorCode, userMessage, retryable };
}
