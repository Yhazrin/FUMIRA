import { randomUUID } from "node:crypto";
import { config } from "./config.js";
import { critiqueGeneratedImage } from "./intelligence.js";
import { normalizeAspectRatio, toJpegDataUrl } from "./prompt.js";
import { buildLegacyPrompt } from "./promptCompiler.js";
import { buildCorrectionPromptV3, compilePromptV3 } from "./promptCompilerV3.js";
import {
  getAsset,
  getGeneration,
  getSettings,
  listGenerations,
  putGeneration,
  readAssetBytes,
  saveGeneratedImage,
  updateGeneration,
} from "./storage.js";
import {
  buildV3ContextFromV2,
  criticNeedsRegeneration,
  defaultQualityPolicy,
  normalizeRenderPlanTarget,
  validateSceneGraph,
  validateTemporalRenderPlan,
} from "./temporalV3.js";
import type {
  CreateGenerationBody,
  ExactTarget,
  GenerationContext,
  GenerationContextV3,
  GenerationRecord,
  MiniMaxAdapter,
  MiniMaxGenerateSuccess,
  QualityPolicy,
  SceneGraph,
  StructuredGenerationBodyV2,
  StructuredGenerationBodyV3,
  TemporalRenderPlan,
} from "./types.js";

let adapter: MiniMaxAdapter | null = null;
const processing = new Set<string>();

interface StoredGenerationContract {
  prompt: string;
  useSubjectReference: boolean;
  quality?: {
    sceneGraph: SceneGraph;
    targetPlan: TemporalRenderPlan;
    policy: QualityPolicy;
  };
}

const promptByGeneration = new Map<string, StoredGenerationContract>();

export function setMiniMaxAdapter(next: MiniMaxAdapter | null): void {
  adapter = next;
}

export function getMiniMaxAdapter(): MiniMaxAdapter | null {
  return adapter;
}

export function createGenerationJob(
  body: CreateGenerationBody
):
  | { ok: true; record: GenerationRecord }
  | {
      ok: false;
      statusCode: number;
      errorCode: string;
      userMessage: string;
      retryable: boolean;
    } {
  const settings = getSettings();
  if (!settings.remoteGenerationEnabled || !adapter) {
    return contractError(503, "generation_unavailable", "远程生成暂未就绪。", true);
  }

  const aspectRatio = normalizeAspectRatio(body.aspectRatio);
  if (!aspectRatio) return contractError(400, "invalid_aspect_ratio", "不支持的画幅比例。");
  if (!body.requestId?.trim()) return contractError(400, "missing_request_id", "缺少 requestId。");
  if (!body.sourceAssetId || !getAsset(body.sourceAssetId)) {
    return contractError(400, "invalid_source_asset", "源图片不存在或已过期。");
  }
  if (!body.timePosition || !Number.isFinite(body.timePosition.normalized) || !Number.isFinite(body.timePosition.offsetDays)) {
    return contractError(400, "invalid_time_position", "时间位置无效。");
  }

  if ((body as { contextVersion?: string }).contextVersion === undefined) {
    (body as unknown as { contextVersion: string }).contextVersion = "legacy.v1";
  }

  let built: {
    prompt: string;
    truncated: boolean;
    charCount: number;
    version?: string;
    hash?: string;
    sectionCharCounts?: Record<string, number>;
    truncatedSections?: string[];
  };
  let quality: StoredGenerationContract["quality"];
  let renderPlanId: string | undefined;

  if (body.contextVersion === "generation.v2") {
    const validation = validateV2Context(body.structuredContext);
    if (validation) return validation;
    const exactTarget = exactTargetFromTime(body.timePosition.offsetDays, body.timePosition.compactLabel);
    const v2Context = injectV2TargetTime(body, exactTarget);
    const v3Context = buildV3ContextFromV2({
      context: v2Context,
      timePosition: body.timePosition,
      exactTarget,
    });
    built = compilePromptV3({ context: v3Context, timePosition: body.timePosition, aspectRatio });
    const policy = defaultQualityPolicy(v3Context.qualityPolicy);
    quality = {
      sceneGraph: v3Context.sceneGraph,
      targetPlan: v3Context.targetPlan,
      policy,
    };
    renderPlanId = v3Context.targetPlan.planId;
  } else if (body.contextVersion === "generation.v3") {
    const exactTarget = exactTargetFromTime(body.timePosition.offsetDays, body.timePosition.compactLabel);
    const v3Context = injectV3TargetTime(body, exactTarget);
    const validation = validateV3Context(v3Context);
    if (validation) return validation;
    built = compilePromptV3({ context: v3Context, timePosition: body.timePosition, aspectRatio });
    const policy = defaultQualityPolicy(v3Context.qualityPolicy);
    quality = {
      sceneGraph: v3Context.sceneGraph,
      targetPlan: v3Context.targetPlan,
      policy,
    };
    renderPlanId = v3Context.targetPlan.planId;
  } else if (body.contextVersion === "legacy.v1") {
    if (typeof body.story !== "string" || !body.story.trim()) {
      return contractError(400, "missing_story", "缺少故事内容。");
    }
    built = buildLegacyPrompt({
      template: settings.promptTemplate,
      story: body.story,
      timePosition: body.timePosition,
      aspectRatio,
    });
  } else {
    return contractError(400, "unsupported_context_version", "不支持的上下文版本。");
  }

  const now = new Date().toISOString();
  const record: GenerationRecord = {
    generationId: randomUUID(),
    requestId: body.requestId.trim(),
    sourceAssetId: body.sourceAssetId,
    status: "queued",
    createdAt: now,
    updatedAt: now,
    modelName: settings.modelName,
    aspectRatio,
    promptTruncated: built.truncated,
    promptCharCount: built.charCount,
    promptVersion: built.version,
    promptHash: built.hash,
    sectionCharCounts: built.sectionCharCounts,
    truncatedSections: built.truncatedSections,
    renderPlanId,
    regenerationCount: 0,
  };

  promptByGeneration.set(record.generationId, {
    prompt: built.prompt,
    useSubjectReference: Boolean(body.useSubjectReference),
    quality,
  });
  putGeneration(record);
  void processGeneration(record.generationId);

  console.info(JSON.stringify({
    event: "generation_queued",
    requestId: record.requestId,
    generationId: record.generationId,
    status: record.status,
    promptTruncated: record.promptTruncated,
    promptVersion: built.version,
    renderPlanId,
    visualCriticEnabled: quality?.policy.visualCriticEnabled ?? false,
  }));

  return { ok: true, record };
}

const VALID_GENERATION_MODES = new Set([
  "captured_target",
  "story_preview_target",
  "regenerate_same_target",
]);

function validateV2Context(
  ctx: GenerationContext | undefined
): ReturnType<typeof contractError> | null {
  if (!ctx) return contractError(400, "invalid_generation_contract", "缺少结构化上下文。");
  if (ctx.schemaVersion !== "generation-context.v2") {
    return contractError(400, "unsupported_schema_version", `不支持的 schema 版本: ${ctx.schemaVersion ?? "undefined"}`);
  }
  if (!ctx.understanding) return contractError(400, "invalid_generation_contract", "缺少图片理解数据。");
  if (!ctx.story || ctx.story.schemaVersion !== "temporal-story.v2") {
    return contractError(400, "unsupported_schema_version", "故事 schema 版本不匹配。");
  }
  if (!ctx.story.targetBeat || !Number.isFinite(ctx.story.targetBeat.anchorYears) || !ctx.story.targetBeat.visualPrompt) {
    return contractError(400, "invalid_target_beat", "V2 故事缺少有效的精确目标节点。");
  }
  if (ctx.story.beats.length !== 7) {
    return contractError(400, "invalid_generation_contract", `需要恰好 7 个浏览节点，收到 ${ctx.story.beats.length} 个。`);
  }
  if (!VALID_GENERATION_MODES.has(ctx.generationMode)) {
    return contractError(400, "invalid_generation_mode", `不支持的生成模式: ${ctx.generationMode}`);
  }
  if (ctx.understanding.subjects.length > 16 || ctx.story.identityRules.length > 16) {
    return contractError(400, "invalid_generation_contract", "V2 场景主体或身份规则超过上限。");
  }
  return null;
}

function validateV3Context(
  ctx: GenerationContextV3
): ReturnType<typeof contractError> | null {
  if (ctx.schemaVersion !== "generation-context.v3") {
    return contractError(400, "unsupported_schema_version", `不支持的 schema 版本: ${ctx.schemaVersion ?? "undefined"}`);
  }
  if (!VALID_GENERATION_MODES.has(ctx.generationMode)) {
    return contractError(400, "invalid_generation_mode", `不支持的生成模式: ${ctx.generationMode}`);
  }
  const graphIssues = validateSceneGraph(ctx.sceneGraph);
  if (graphIssues.length) {
    return contractError(400, "invalid_scene_graph", `场景图无效: ${graphIssues.slice(0, 5).join(", ")}`);
  }
  const planIssues = validateTemporalRenderPlan(ctx.sceneGraph, ctx.targetPlan);
  if (planIssues.length) {
    return contractError(400, "invalid_render_plan", `时间渲染计划无效: ${planIssues.slice(0, 5).join(", ")}`);
  }
  return null;
}

function exactTargetFromTime(offsetDays: number, compactLabel: string): ExactTarget {
  const now = new Date();
  const targetDate = new Date(now.getTime() + offsetDays * 86_400_000);
  return {
    offsetDays,
    targetDateISO: targetDate.toISOString().slice(0, 10),
    compactLabel: compactLabel || `${Math.abs(offsetDays).toFixed(0)} 天${offsetDays < 0 ? "前" : "后"}`,
  };
}

function injectV2TargetTime(
  body: StructuredGenerationBodyV2,
  exactTarget: ExactTarget
): GenerationContext {
  return {
    ...body.structuredContext,
    story: {
      ...body.structuredContext.story,
      targetBeat: {
        ...body.structuredContext.story.targetBeat,
        anchorYears: exactTarget.offsetDays / 365.25,
        exactTarget,
      },
    },
  };
}

function injectV3TargetTime(
  body: StructuredGenerationBodyV3,
  exactTarget: ExactTarget
): GenerationContextV3 {
  return {
    ...body.structuredContext,
    targetPlan: normalizeRenderPlanTarget(body.structuredContext.targetPlan, exactTarget),
  };
}

async function processGeneration(generationId: string): Promise<void> {
  if (processing.has(generationId)) return;
  processing.add(generationId);
  const startedAt = Date.now();
  const current = getGeneration(generationId);
  if (!current || !adapter) {
    processing.delete(generationId);
    return;
  }

  updateGeneration(generationId, {
    status: "processing",
    startedAt: new Date().toISOString(),
  });

  try {
    const asset = await readAssetBytes(current.sourceAssetId);
    if (!asset) {
      failGeneration(generationId, startedAt, "invalid_image", "源图片无法读取。", false);
      return;
    }

    const stored = promptByGeneration.get(generationId);
    if (!stored?.prompt) {
      failGeneration(generationId, startedAt, "missing_prompt", "生成提示上下文已丢失。", true);
      return;
    }

    const imageDataUrl = toJpegDataUrl(asset.bytes, asset.contentType);
    const first = await adapter.generate({
      prompt: stored.prompt,
      imageDataUrl,
      aspectRatio: current.aspectRatio,
      useSubjectReference: stored.useSubjectReference,
      requestId: current.requestId,
      generationId,
    });

    if (!first.ok) {
      failGeneration(
        generationId,
        startedAt,
        first.errorCode,
        first.userMessage,
        first.retryable,
        first.statusMsg
      );
      return;
    }

    let selected: MiniMaxGenerateSuccess = first;
    let critic = stored.quality
      ? await critiqueGeneratedImage({
          sourceSceneGraph: stored.quality.sceneGraph,
          targetPlan: stored.quality.targetPlan,
          generatedBytes: first.imageBytes,
          generatedContentType: first.contentType,
          qualityPolicy: stored.quality.policy,
          requestId: current.requestId,
        })
      : null;
    let regenerationCount = 0;

    if (stored.quality && critic && criticNeedsRegeneration(critic, stored.quality.policy)) {
      const correctionPrompt = buildCorrectionPromptV3({
        originalPrompt: stored.prompt,
        graph: stored.quality.sceneGraph,
        plan: stored.quality.targetPlan,
        critic,
      });
      const retry = await adapter.generate({
        prompt: correctionPrompt,
        imageDataUrl,
        aspectRatio: current.aspectRatio,
        useSubjectReference: stored.useSubjectReference,
        requestId: `${current.requestId}-repair`,
        generationId,
      });
      if (retry.ok) {
        regenerationCount = 1;
        const retryCritic = await critiqueGeneratedImage({
          sourceSceneGraph: stored.quality.sceneGraph,
          targetPlan: stored.quality.targetPlan,
          generatedBytes: retry.imageBytes,
          generatedContentType: retry.contentType,
          qualityPolicy: stored.quality.policy,
          requestId: `${current.requestId}-repair`,
        });
        if (!retryCritic || criticScore(retryCritic) >= criticScore(critic)) {
          selected = retry;
          critic = retryCritic ?? critic;
        }
      }
    }

    const resultRelativeUrl = await saveGeneratedImage({
      generationId,
      bytes: selected.imageBytes,
    });
    updateGeneration(generationId, {
      status: "succeeded",
      finishedAt: new Date().toISOString(),
      durationMs: Date.now() - startedAt,
      resultRelativeUrl,
      visualCritic: critic ?? undefined,
      regenerationCount,
    });

    console.info(JSON.stringify({
      event: "generation_succeeded",
      requestId: current.requestId,
      generationId,
      durationMs: Date.now() - startedAt,
      model: config.modelName,
      renderPlanId: current.renderPlanId,
      regenerationCount,
      criticPassed: critic?.passed,
      environmentEvolution: critic?.environmentEvolution,
      requiredChangeCompletion: critic?.requiredChangeCompletion,
    }));
  } catch (error) {
    failGeneration(
      generationId,
      startedAt,
      "internal_error",
      "生成过程出现内部错误。",
      true,
      error instanceof Error ? error.message.slice(0, 200) : "unknown"
    );
  } finally {
    promptByGeneration.delete(generationId);
    processing.delete(generationId);
  }
}

function criticScore(critic: NonNullable<GenerationRecord["visualCritic"]>): number {
  return (
    critic.cameraConsistency * 1.25
    + critic.spatialTopologyConsistency
    + critic.principalIdentityConsistency
    + critic.requiredChangeCompletion * 1.4
    + critic.environmentEvolution * 1.4
    + critic.eraCoherence
  ) / 7.05;
}

function failGeneration(
  generationId: string,
  startedAt: number,
  errorCode: string,
  userMessage: string,
  retryable: boolean,
  statusMsg?: string
): void {
  updateGeneration(generationId, {
    status: "failed",
    finishedAt: new Date().toISOString(),
    durationMs: Date.now() - startedAt,
    errorCode,
    userMessage,
    retryable,
    statusMsg,
  });
  console.info(JSON.stringify({
    event: "generation_failed",
    generationId,
    errorCode,
    durationMs: Date.now() - startedAt,
  }));
}

function contractError(
  statusCode: number,
  errorCode: string,
  userMessage: string,
  retryable = false
) {
  return { ok: false as const, statusCode, errorCode, userMessage, retryable };
}

export function toClientGeneration(record: GenerationRecord) {
  const base: Record<string, unknown> = {
    generationId: record.generationId,
    status: record.status,
    requestId: record.requestId,
    modelName: record.modelName,
    aspectRatio: record.aspectRatio,
    promptTruncated: record.promptTruncated,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    durationMs: record.durationMs,
    qualityStatus: record.visualCritic
      ? record.visualCritic.passed ? "passed" : "best_effort"
      : record.renderPlanId ? "not_scored" : undefined,
    regenerationCount: record.regenerationCount ?? 0,
  };
  if (record.status === "succeeded" && record.resultRelativeUrl) {
    base.resultUrl = `${config.publicBaseUrl}${record.resultRelativeUrl}`;
  }
  if (record.status === "failed") {
    base.errorCode = record.errorCode;
    base.userMessage = record.userMessage;
    base.retryable = record.retryable ?? false;
  }
  return base;
}

export function toAdminGeneration(record: GenerationRecord) {
  return {
    generationId: record.generationId,
    requestId: record.requestId,
    status: record.status,
    modelName: record.modelName,
    aspectRatio: record.aspectRatio,
    promptTruncated: record.promptTruncated,
    promptCharCount: record.promptCharCount,
    promptVersion: record.promptVersion,
    promptHash: record.promptHash,
    sectionCharCounts: record.sectionCharCounts,
    truncatedSections: record.truncatedSections,
    renderPlanId: record.renderPlanId,
    visualCritic: record.visualCritic,
    regenerationCount: record.regenerationCount,
    durationMs: record.durationMs,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    errorCode: record.errorCode,
    statusMsg: record.statusMsg,
  };
}

export function adminList() {
  return listGenerations().map(toAdminGeneration);
}

export async function waitForGeneration(
  generationId: string,
  timeoutMs = 5000
): Promise<GenerationRecord | undefined> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const record = getGeneration(generationId);
    if (record && (record.status === "succeeded" || record.status === "failed")) return record;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  return getGeneration(generationId);
}
