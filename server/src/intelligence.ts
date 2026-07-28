import { getAsset, readAssetBytes } from "./storage.js";
import { toJpegDataUrl } from "./prompt.js";
import type {
  ExactTarget,
  MiniMaxIntelligenceAdapter,
  QualityPolicy,
  SceneGraph,
  SceneUnderstandingPayload,
  StoryBeatPayload,
  StoryContinuityContext,
  StoryCopyConstraints,
  SubjectContinuityMode,
  TemporalRenderPlan,
  TemporalStoryPayloadV2,
  UnderstandingCopyConstraints,
  VisualCriticResult,
} from "./types.js";
import { normalizeTemporalStoryCopy, promoteToV2 } from "./storyCopy.js";
import { normalizeSceneUnderstandingCopy } from "./understandingCopy.js";
import {
  deriveRenderPlanFromV2,
  deriveSceneGraphFromV2,
  validateSceneGraph,
  validateTemporalRenderPlan,
} from "./temporalV3.js";

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
  const asset = await sourceAsset(input.sourceAssetId);
  if (!asset.ok) return asset;
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

export async function analyzeUploadedSceneGraph(input: {
  sourceAssetId: string;
  requestId: string;
}): Promise<
  | { ok: true; value: SceneGraph; derivedFromV2: boolean }
  | { ok: false; errorCode: string; userMessage: string; retryable: boolean; statusMsg?: string }
> {
  if (!adapter) return unavailable("scene_graph_unavailable", "场景图分析暂未就绪。");
  const asset = await sourceAsset(input.sourceAssetId);
  if (!asset.ok) return asset;
  const imageDataUrl = toJpegDataUrl(asset.bytes, asset.contentType);

  if (adapter.analyzeSceneGraph) {
    const result = await adapter.analyzeSceneGraph({
      imageDataUrl,
      requestId: input.requestId,
    });
    if (result.ok) {
      const issues = validateSceneGraph(result.value);
      if (!issues.length) return { ok: true, value: result.value, derivedFromV2: false };
      console.info(JSON.stringify({
        event: "scene_graph_invalid",
        requestId: input.requestId,
        issues,
      }));
    }
  }

  // Compatibility fallback: use the mature V2 analyzer and deterministically
  // expand its concise output into a conservative SceneGraph.
  const v2 = await adapter.analyzeImage({
    imageDataUrl,
    copyConstraints: {
      summary: 160,
      locationType: 40,
      visualMood: 80,
      timeClue: 60,
      changeDriver: 80,
      subjectName: 50,
      identityRule: 120,
    },
    requestId: input.requestId,
  });
  if (!v2.ok) return v2;
  return {
    ok: true,
    value: deriveSceneGraphFromV2(v2.value),
    derivedFromV2: true,
  };
}

export async function planTemporalRender(input: {
  sceneGraph: SceneGraph;
  exactTarget: ExactTarget;
  storyContext?: StoryContinuityContext;
  continuityMode?: SubjectContinuityMode;
  requestId: string;
}): Promise<
  | { ok: true; value: TemporalRenderPlan; deterministicFallback: boolean }
  | { ok: false; errorCode: string; userMessage: string; retryable: boolean; statusMsg?: string }
> {
  const graphIssues = validateSceneGraph(input.sceneGraph);
  if (graphIssues.length) {
    return invalidAIResponse(`场景图不完整：${graphIssues.slice(0, 4).join(", ")}`);
  }

  if (adapter?.planTemporalRender) {
    const result = await adapter.planTemporalRender(input);
    if (result.ok) {
      const issues = validateTemporalRenderPlan(input.sceneGraph, result.value);
      if (!issues.length) return { ok: true, value: result.value, deterministicFallback: false };
      console.info(JSON.stringify({
        event: "render_plan_invalid",
        requestId: input.requestId,
        issues,
      }));
    }
  }

  // Deterministic fallback keeps the endpoint executable during provider
  // degradation and gives V2 clients a complete region-by-region contract.
  const visualPrompt = input.storyContext?.canonicalBeats
    .map((beat) => beat.visualPrompt)
    .filter(Boolean)
    .join("；") || "让时间变化传播到主体、材料、环境、基础设施和背景，同时保持相机几何";
  const fallback = deriveRenderPlanFromV2({
    sceneGraph: input.sceneGraph,
    exactTarget: input.exactTarget,
    story: {
      schemaVersion: "temporal-story.v2",
      title: input.storyContext?.title || "时间场景",
      logline: "同一视角下的可信时间演化",
      presentTruth: input.storyContext?.presentTruth || "源图是当前世界状态",
      identityRules: input.storyContext?.identityRules || [],
      beats: [-100, -30, -10, 0, 10, 30, 100].map((anchorYears) => ({
        anchorYears,
        title: `${anchorYears}`,
        narrative: "时间沿同一地点连续演化",
        visualPrompt,
      })),
      targetBeat: {
        anchorYears: input.exactTarget.offsetDays / 365.25,
        title: input.exactTarget.compactLabel,
        narrative: "精确目标世界状态",
        visualPrompt,
        exactTarget: input.exactTarget,
      },
    },
  });
  if (input.continuityMode) fallback.subjectContinuityMode = input.continuityMode;
  return { ok: true, value: fallback, deterministicFallback: true };
}

export async function critiqueGeneratedImage(input: {
  sourceSceneGraph: SceneGraph;
  targetPlan: TemporalRenderPlan;
  generatedBytes: Buffer;
  generatedContentType: string;
  qualityPolicy: QualityPolicy;
  requestId: string;
}): Promise<VisualCriticResult | null> {
  if (!adapter?.analyzeSceneGraph || !adapter.critiqueGeneration) return null;
  const generatedGraph = await adapter.analyzeSceneGraph({
    imageDataUrl: toJpegDataUrl(input.generatedBytes, input.generatedContentType),
    requestId: `${input.requestId}-generated-graph`,
  });
  if (!generatedGraph.ok) {
    console.info(JSON.stringify({
      event: "visual_critic_skipped",
      requestId: input.requestId,
      reason: generatedGraph.errorCode,
    }));
    return null;
  }
  const result = await adapter.critiqueGeneration({
    sourceSceneGraph: input.sourceSceneGraph,
    generatedSceneGraph: generatedGraph.value,
    targetPlan: input.targetPlan,
    qualityPolicy: input.qualityPolicy,
    requestId: `${input.requestId}-critic`,
  });
  if (!result.ok) {
    console.info(JSON.stringify({
      event: "visual_critic_skipped",
      requestId: input.requestId,
      reason: result.errorCode,
    }));
    return null;
  }
  return result.value;
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
  if (!result.value.targetBeat) {
    return invalidAIResponse("时间故事缺少精确目标节点，请重试。");
  }
  const targetOffsetYears = input.targetTime.offsetDays / 365.25;
  return {
    ok: true,
    value: promoteToV2(result.value, targetOffsetYears, input.copyConstraints),
  };
}

export async function writeTargetBeat(input: {
  understanding: SceneUnderstandingPayload;
  storyContext: StoryContinuityContext;
  target: ExactTarget;
  requestId: string;
}): Promise<
  | { ok: true; targetBeat: StoryBeatPayload }
  | { ok: false; errorCode: string; userMessage: string; retryable: boolean; statusMsg?: string }
> {
  if (!adapter) return unavailable("story_unavailable", "时间故事暂未就绪。");
  const targetOffsetYears = input.target.offsetDays / 365.25;
  const constraints: StoryCopyConstraints = {
    title: 16,
    logline: 56,
    presentTruth: 72,
    identityRule: 48,
    beatTitle: 14,
    beatNarrative: 72,
    visualPrompt: 110,
  };
  const result = await adapter.writeStory({
    understanding: input.understanding,
    targetTime: input.target,
    copyConstraints: constraints,
    requestId: input.requestId,
    storyContext: input.storyContext,
    exactTargetOnly: true,
  });
  if (!result.ok) return result;
  if (!result.value.targetBeat) return invalidAIResponse("精确年份节点生成失败，请重试。");

  const normalized = normalizeTemporalStoryCopy(result.value, constraints);
  const modelBeat = normalized.targetBeat;
  if (!modelBeat) return invalidAIResponse("精确年份节点生成失败，请重试。");
  return {
    ok: true,
    targetBeat: {
      anchorYears: targetOffsetYears,
      title: modelBeat.title,
      narrative: modelBeat.narrative,
      visualPrompt: modelBeat.visualPrompt,
      exactTarget: input.target,
    },
  };
}

async function sourceAsset(sourceAssetId: string): Promise<
  | { ok: true; bytes: Buffer; contentType: string }
  | { ok: false; errorCode: string; userMessage: string; retryable: boolean }
> {
  if (!sourceAssetId || !getAsset(sourceAssetId)) {
    return unavailable("invalid_source_asset", "源图片不存在或已过期。", false);
  }
  const asset = await readAssetBytes(sourceAssetId);
  if (!asset) return unavailable("invalid_image", "源图片无法读取。", false);
  return { ok: true, ...asset };
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
