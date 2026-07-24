import { getAsset, readAssetBytes } from "./storage.js";
import { toJpegDataUrl } from "./prompt.js";
import type {
  MiniMaxIntelligenceAdapter,
  SceneUnderstandingPayload,
  StoryCopyConstraints,
  UnderstandingCopyConstraints,
} from "./types.js";
import { normalizeTemporalStoryCopy } from "./storyCopy.js";
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
  targetTime: { offsetYears: number; compactLabel: string };
  copyConstraints: StoryCopyConstraints;
  requestId: string;
}) {
  if (!adapter) return unavailable("story_unavailable", "时间故事暂未就绪。");
  const result = await adapter.writeStory(input);
  if (!result.ok) return result;
  return {
    ok: true as const,
    value: normalizeTemporalStoryCopy(result.value, input.copyConstraints),
  };
}

function unavailable(errorCode: string, userMessage: string, retryable = true) {
  return { ok: false as const, errorCode, userMessage, retryable };
}
