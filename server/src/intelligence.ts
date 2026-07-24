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
  // Promote V1 (optional targetBeat) → V2 (required targetBeat).
  // If the model returned a targetBeat, keep it; otherwise fall back to
  // nearest canonical — but the validation layer should catch this.
  const targetOffsetYears = input.targetTime.offsetDays / 365.25;
  const v2 = promoteToV2(result.value, targetOffsetYears, input.copyConstraints);
  return { ok: true, value: v2 };
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

  const targetOffsetYears = input.target.offsetDays / 365.25;

  // Use the story adapter to generate a single beat for the exact target.
  // We construct a minimal story request with the target as the only beat.
  const result = await adapter.writeStory({
    understanding: input.understanding,
    targetTime: input.target,
    copyConstraints: {
      title: 16, logline: 56, presentTruth: 72, identityRule: 48,
      beatTitle: 14, beatNarrative: 72, visualPrompt: 110,
    },
    requestId: input.requestId,
  });

  if (!result.ok) return result;

  // Find the targetBeat from the model response, or fall back to nearest canonical.
  const modelBeat = result.value.targetBeat ?? nearestBeat(result.value.beats, targetOffsetYears);

  // Overwrite with program-authoritative time identity.
  const targetBeat: StoryBeatPayload = {
    anchorYears: targetOffsetYears,
    title: modelBeat.title,
    narrative: modelBeat.narrative,
    visualPrompt: modelBeat.visualPrompt,
    exactTarget: input.target,
  };

  return { ok: true, targetBeat };
}

function nearestBeat(beats: StoryBeatPayload[], offsetYears: number): StoryBeatPayload {
  if (!beats.length) {
    return { anchorYears: offsetYears, title: "", narrative: "", visualPrompt: "" };
  }
  return beats.reduce((best, beat) =>
    Math.abs(beat.anchorYears - offsetYears) < Math.abs(best.anchorYears - offsetYears)
      ? beat
      : best
  );
}

function unavailable(errorCode: string, userMessage: string, retryable = true) {
  return { ok: false as const, errorCode, userMessage, retryable };
}
