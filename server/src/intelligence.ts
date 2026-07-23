import { getAsset, readAssetBytes } from "./storage.js";
import { toJpegDataUrl } from "./prompt.js";
import type {
  MiniMaxIntelligenceAdapter,
  SceneUnderstandingPayload,
} from "./types.js";

let adapter: MiniMaxIntelligenceAdapter | null = null;

export function setMiniMaxIntelligenceAdapter(next: MiniMaxIntelligenceAdapter | null): void {
  adapter = next;
}

export function getMiniMaxIntelligenceAdapter(): MiniMaxIntelligenceAdapter | null {
  return adapter;
}

export async function analyzeUploadedAsset(input: {
  sourceAssetId: string;
  requestId: string;
}) {
  if (!adapter) return unavailable("understanding_unavailable", "图片理解暂未就绪。");
  if (!input.sourceAssetId || !getAsset(input.sourceAssetId)) {
    return unavailable("invalid_source_asset", "源图片不存在或已过期。", false);
  }
  const asset = await readAssetBytes(input.sourceAssetId);
  if (!asset) return unavailable("invalid_image", "源图片无法读取。", false);
  return adapter.analyzeImage({
    imageDataUrl: toJpegDataUrl(asset.bytes, asset.contentType),
    requestId: input.requestId,
  });
}

export async function writeTemporalStory(input: {
  understanding: SceneUnderstandingPayload;
  requestId: string;
}) {
  if (!adapter) return unavailable("story_unavailable", "时间故事暂未就绪。");
  return adapter.writeStory(input);
}

function unavailable(errorCode: string, userMessage: string, retryable = true) {
  return { ok: false as const, errorCode, userMessage, retryable };
}
