import { randomUUID } from "node:crypto";
import { config } from "./config.js";
import {
  buildPrompt,
  normalizeAspectRatio,
  toJpegDataUrl,
} from "./prompt.js";
import { compilePrompt, buildLegacyPrompt } from "./promptCompiler.js";
import {
  compileStoryDrivenPrompt,
  makeTemporalImagePrompt,
  pickNearestBeat,
} from "./temporalImagePrompt.js";
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
import type {
  CreateGenerationBody,
  GenerationContext,
  GenerationRecord,
  ImageGenerationAdapter,
  ImageGenerationProvider,
  SceneUnderstandingPayload,
  StoryBeatPayload,
  StructuredGenerationBody,
} from "./types.js";
import {
  getPostGenerationValidationAdapter,
  planFromValidation,
  runPostGenerationValidation,
} from "./validationService.js";
import { shouldAttemptRepair, DEFAULT_REPAIR_INSTRUCTION } from "./validation.js";

const adapters = new Map<ImageGenerationProvider, ImageGenerationAdapter>();
const processing = new Set<string>();
const promptByGeneration = new Map<
  string,
  {
    prompt: string;
    useSubjectReference: boolean;
    understanding: SceneUnderstandingPayload | null;
    storyBeat: StoryBeatPayload | null;
    targetTime: { offsetYears: number; compactLabel: string };
  }
>();

export function setImageGenerationAdapter(
  provider: ImageGenerationProvider,
  next: ImageGenerationAdapter | null
): void {
  if (next) {
    adapters.set(provider, next);
  } else {
    adapters.delete(provider);
  }
}

export function setMiniMaxAdapter(next: ImageGenerationAdapter | null): void {
  setImageGenerationAdapter("minimax", next);
}

export function getImageGenerationAdapter(
  provider: ImageGenerationProvider
): ImageGenerationAdapter | null {
  return adapters.get(provider) ?? null;
}

export function getMiniMaxAdapter(): ImageGenerationAdapter | null {
  return getImageGenerationAdapter("minimax");
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
  if (
    body.imageProvider !== undefined
    && body.imageProvider !== "minimax"
    && body.imageProvider !== "apimart"
  ) {
    return {
      ok: false,
      statusCode: 400,
      errorCode: "invalid_image_provider",
      userMessage: "不支持的图片生成服务。",
      retryable: false,
    };
  }
  const imageProvider: ImageGenerationProvider =
    body.imageProvider === "apimart" ? "apimart" : "minimax";
  const adapter = getImageGenerationAdapter(imageProvider);
  // Runtime readiness = admin kill-switch + the specifically requested adapter.
  if (!settings.remoteGenerationEnabled || !adapter) {
    return {
      ok: false,
      statusCode: 503,
      errorCode: "generation_unavailable",
      userMessage: imageProvider === "apimart"
        ? "中转站图片服务暂未配置。"
        : "MiniMax 图片服务暂未配置。",
      retryable: true,
    };
  }

  const aspectRatio = normalizeAspectRatio(body.aspectRatio);
  if (!aspectRatio) {
    return contractError(400, "invalid_aspect_ratio", "不支持的画幅比例。");
  }

  if (!body.requestId?.trim()) {
    return contractError(400, "missing_request_id", "缺少 requestId。");
  }

  if (!body.sourceAssetId || !getAsset(body.sourceAssetId)) {
    return contractError(400, "invalid_source_asset", "源图片不存在或已过期。");
  }

  if (!body.timePosition || typeof body.timePosition.normalized !== "number") {
    return contractError(400, "invalid_time_position", "时间位置无效。");
  }

  const contextVersion =
    (body as { contextVersion?: string }).contextVersion ?? "legacy.v1";
  let built: {
    prompt: string;
    truncated: boolean;
    charCount: number;
    version?: string;
    hash?: string;
    sectionCharCounts?: Record<string, number>;
    truncatedSections?: string[];
  };
  let understanding: SceneUnderstandingPayload | null = null;
  let beat: StoryBeatPayload | null = null;

  if (contextVersion === "generation.v2" || contextVersion === "generation.v3") {
    const structured = body as StructuredGenerationBody;
    const validation = validateStructuredContext(structured.structuredContext);
    if (validation) return validation;
    const ctx = injectTargetTime(structured);
    built = compilePrompt({
      context: ctx,
      timePosition: body.timePosition,
      aspectRatio,
    });
    understanding = ctx.understanding;
    beat = ctx.story.targetBeat;
  } else if (contextVersion === "legacy.v1") {
    const legacy = body as Extract<CreateGenerationBody, { contextVersion: "legacy.v1" }>;
    const clientPrompt =
      typeof legacy.prompt === "string" && legacy.prompt.trim()
        ? legacy.prompt.trim()
        : typeof legacy.story === "string" && legacy.story.trim()
          ? legacy.story.trim()
          : "";
    const forceMarker = /__FORCE_[A-Z0-9_]+__/.test(clientPrompt)
      ? clientPrompt
      : null;
    beat = legacy.storyBeat
      ?? pickNearestBeat(legacy.temporalStory, body.timePosition.offsetYears)
      ?? null;
    understanding = legacy.understanding ?? null;

    if (legacy.understanding || legacy.temporalStory || legacy.storyBeat) {
      const corePrompt = forceMarker
        ?? compileStoryDrivenPrompt({
          time: body.timePosition,
          understanding: legacy.understanding,
          story: legacy.temporalStory
            ? {
                identityRules: legacy.temporalStory.identityRules,
                logline: legacy.temporalStory.logline,
                presentTruth: legacy.temporalStory.presentTruth,
              }
            : null,
          beat,
        })
        ?? makeTemporalImagePrompt(body.timePosition);
      built = buildPrompt({
        template: settings.promptTemplate,
        corePrompt,
        timePosition: body.timePosition,
        aspectRatio,
      });
    } else {
      if (!clientPrompt) {
        return contractError(400, "missing_story", "缺少故事内容。");
      }
      built = forceMarker
        ? {
            prompt: forceMarker,
            truncated: false,
            charCount: forceMarker.length,
          }
        : buildLegacyPrompt({
            template: settings.promptTemplate,
            story: clientPrompt,
            timePosition: body.timePosition,
            aspectRatio,
          });
    }
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
    modelName: imageProvider === "apimart" ? "gpt-image-2" : settings.modelName,
    imageProvider,
    aspectRatio,
    promptTruncated: built.truncated,
    promptCharCount: built.charCount,
    promptVersion: built.version,
    promptHash: built.hash,
    sectionCharCounts: built.sectionCharCounts,
    truncatedSections: built.truncatedSections,
  };

  promptByGeneration.set(record.generationId, {
    prompt: built.prompt,
    useSubjectReference: Boolean(body.useSubjectReference),
    understanding,
    storyBeat: beat,
    targetTime: body.timePosition,
  });

  putGeneration(record);
  void processGeneration(record.generationId);

  console.info(
    JSON.stringify({
      event: "generation_queued",
      requestId: record.requestId,
      generationId: record.generationId,
      status: record.status,
      promptTruncated: record.promptTruncated,
      promptVersion: built.version,
    })
  );

  return { ok: true, record };
}

// ---------------------------------------------------------------------------
// Contract validation (Task 7)
// ---------------------------------------------------------------------------

function contractError(
  statusCode: number,
  errorCode: string,
  userMessage: string,
  retryable = false
) {
  return { ok: false as const, statusCode, errorCode, userMessage, retryable };
}

const VALID_GENERATION_MODES = new Set([
  "captured_target",
  "story_preview_target",
  "regenerate_same_target",
]);

const VALID_SCHEMA_VERSIONS = new Set([
  "generation-context.v2",
  "generation-context.v3",
]);

function validateStructuredContext(
  ctx: GenerationContext | undefined
): ReturnType<typeof contractError> | null {
  if (!ctx) {
    return contractError(400, "invalid_generation_contract", "缺少结构化上下文。");
  }
  if (!VALID_SCHEMA_VERSIONS.has(ctx.schemaVersion)) {
    return contractError(400, "unsupported_schema_version", `不支持的 schema 版本: ${ctx.schemaVersion ?? "undefined"}`);
  }
  if (!ctx.understanding) {
    return contractError(400, "invalid_generation_contract", "缺少图片理解数据。");
  }
  if (!ctx.story) {
    return contractError(400, "invalid_generation_contract", "缺少时间故事数据。");
  }
  if (
    ctx.story.schemaVersion !== "temporal-story.v2"
    && ctx.story.schemaVersion !== "temporal-story.v3"
  ) {
    return contractError(400, "unsupported_schema_version", `故事 schema 版本不匹配: ${ctx.story.schemaVersion ?? "undefined"}`);
  }
  if (!ctx.story.targetBeat) {
    return contractError(400, "missing_target_beat", "V2 故事缺少精确目标节点 (targetBeat)。");
  }
  const tb = ctx.story.targetBeat;
  if (!Number.isFinite(tb.anchorYears) || !tb.visualPrompt) {
    return contractError(400, "invalid_target_beat", "targetBeat 缺少必要字段 (anchorYears, visualPrompt)。");
  }
  if (ctx.schemaVersion === "generation-context.v3") {
    if (ctx.story.schemaVersion !== "temporal-story.v3") {
      return contractError(400, "unsupported_schema_version", "V3 生成上下文需要 temporal-story.v3。");
    }
    if (!ctx.understanding.sceneGraph?.regions.length) {
      return contractError(400, "missing_scene_graph", "V3 上下文缺少分层场景图。");
    }
    if (!tb.renderPlan?.regionChanges.length) {
      return contractError(400, "missing_temporal_render_plan", "V3 目标节点缺少分区域渲染计划。");
    }
  }
  if (ctx.story.beats.length !== 7) {
    return contractError(400, "invalid_generation_contract", `需要恰好 7 个浏览节点，收到 ${ctx.story.beats.length} 个。`);
  }
  if (!VALID_GENERATION_MODES.has(ctx.generationMode)) {
    return contractError(400, "invalid_generation_mode", `不支持的生成模式: ${ctx.generationMode}`);
  }
  // Validate subject count bounds.
  if (ctx.understanding.subjects.length > 10) {
    return contractError(400, "invalid_generation_contract", "主体数量超过上限 (10)。");
  }
  if (ctx.story.identityRules.length > 10) {
    return contractError(400, "invalid_generation_contract", "身份规则数量超过上限 (10)。");
  }
  return null;
}

/**
 * Inject program-authoritative time values into the targetBeat.
 * The LLM's anchorYears is a hint; offsetDays is the truth.
 */
function injectTargetTime(body: StructuredGenerationBody): GenerationContext {
  const offsetDays = body.timePosition.offsetDays;
  const now = new Date();
  const targetDate = new Date(now.getTime() + offsetDays * 86_400_000);
  const exactTarget: import("./types.js").ExactTarget = {
    offsetDays,
    targetDateISO: targetDate.toISOString().slice(0, 10),
    compactLabel: body.timePosition.compactLabel,
  };
  return {
    ...body.structuredContext,
    story: {
      ...body.structuredContext.story,
      targetBeat: {
        ...body.structuredContext.story.targetBeat,
        // Overwrite the LLM's anchorYears with the program-authoritative value.
        anchorYears: offsetDays / 365.25,
        exactTarget,
        renderPlan: body.structuredContext.story.targetBeat.renderPlan
          ? {
              ...body.structuredContext.story.targetBeat.renderPlan,
              exactTarget,
            }
          : undefined,
      },
    },
  };
}

async function processGeneration(generationId: string): Promise<void> {
  if (processing.has(generationId)) return;
  processing.add(generationId);

  const startedAt = Date.now();
  const current = getGeneration(generationId);

  const adapter = current
    ? getImageGenerationAdapter(current.imageProvider ?? "minimax")
    : null;
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
      updateGeneration(generationId, {
        status: "failed",
        finishedAt: new Date().toISOString(),
        durationMs: Date.now() - startedAt,
        errorCode: "invalid_image",
        userMessage: "源图片无法读取。",
        retryable: false,
      });
      return;
    }

    const stored = promptByGeneration.get(generationId);
    const prompt = stored?.prompt ?? "";
    const result = await adapter.generate({
      prompt,
      imageDataUrl: toJpegDataUrl(asset.bytes, asset.contentType),
      aspectRatio: current.aspectRatio,
      useSubjectReference: Boolean(stored?.useSubjectReference),
      requestId: current.requestId,
      generationId,
    });

    promptByGeneration.delete(generationId);

    if (!result.ok) {
      updateGeneration(generationId, {
        status: "failed",
        finishedAt: new Date().toISOString(),
        durationMs: Date.now() - startedAt,
        errorCode: result.errorCode,
        userMessage: result.userMessage,
        retryable: result.retryable,
        statusMsg: result.statusMsg,
      });
      console.info(
        JSON.stringify({
          event: "generation_failed",
          requestId: current.requestId,
          generationId,
          errorCode: result.errorCode,
          durationMs: Date.now() - startedAt,
        })
      );
      promptByGeneration.delete(generationId);
      return;
    }

    const resultRelativeUrl = await saveGeneratedImage({
      generationId,
      bytes: result.imageBytes,
      contentType: result.contentType,
    });

    const primaryRelativeUrl = resultRelativeUrl;
    updateGeneration(generationId, {
      status: "succeeded",
      finishedAt: new Date().toISOString(),
      durationMs: Date.now() - startedAt,
      resultRelativeUrl: primaryRelativeUrl,
    });

    // Post-generation validation + at-most-one repair, only when validation is
    // enabled and we have enough metadata to compare source vs target.
    const finalRelativeUrl = await maybeRepair({
      generationId,
      sourceAssetId: current.sourceAssetId,
      requestId: current.requestId,
      sourceBytes: asset.bytes,
      sourceContentType: asset.contentType,
      targetBytes: result.imageBytes,
      targetContentType: result.contentType,
      targetTime: stored?.targetTime ?? {
        offsetYears: 0,
        compactLabel: "NOW",
      },
      understanding: stored?.understanding ?? null,
      storyBeat: stored?.storyBeat ?? null,
      aspectRatio: current.aspectRatio,
      adapter,
      useSubjectReference: Boolean(stored?.useSubjectReference),
      originalPrompt: prompt,
    });
    const finalUrl = finalRelativeUrl ?? primaryRelativeUrl;
    promptByGeneration.delete(generationId);

    updateGeneration(generationId, {
      resultRelativeUrl: finalUrl,
      updatedAt: new Date().toISOString(),
    });

    updateGeneration(generationId, {
      status: "succeeded",
      finishedAt: new Date().toISOString(),
      durationMs: Date.now() - startedAt,
      resultRelativeUrl: finalUrl,
    });

    console.info(
      JSON.stringify({
        event: "generation_succeeded",
        requestId: current.requestId,
        generationId,
        durationMs: Date.now() - startedAt,
        model: current.modelName,
        provider: current.imageProvider,
      })
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown";
    updateGeneration(generationId, {
      status: "failed",
      finishedAt: new Date().toISOString(),
      durationMs: Date.now() - startedAt,
      errorCode: "internal_error",
      userMessage: "生成过程出现内部错误。",
      retryable: true,
      statusMsg: message.slice(0, 200),
    });
  } finally {
    processing.delete(generationId);
  }
}

/**
 * Run an optional dual-image VLM validate against the just-generated image,
 * and at most once trigger a regenerate with a repair-instruction augmented
 * prompt. Returns the relative URL of the chosen final image, or `null`
 * when no validation was performed / the primary result is the final image.
 */
async function maybeRepair(input: {
  generationId: string;
  sourceAssetId: string;
  requestId: string;
  sourceBytes: Buffer;
  sourceContentType: string;
  targetBytes: Buffer;
  targetContentType: string;
  targetTime: { offsetYears: number; compactLabel: string };
  understanding: SceneUnderstandingPayload | null;
  storyBeat: StoryBeatPayload | null;
  aspectRatio: ImageGenerationAdapter["generate"] extends (args: infer A) => unknown
    ? (A extends { aspectRatio: infer R } ? R : never)
    : never;
  adapter: ImageGenerationAdapter;
  useSubjectReference: boolean;
  originalPrompt: string;
}): Promise<string | null> {
  const validator = getPostGenerationValidationAdapter();
  if (!validator) return null;
  const validationStart = Date.now();
  const validation = await runPostGenerationValidation({
    sourceAssetId: input.sourceAssetId,
    sourceContentType: input.sourceContentType,
    targetBytes: input.targetBytes,
    targetContentType: input.targetContentType,
    targetTime: input.targetTime,
    understanding: input.understanding,
    storyBeat: input.storyBeat,
    requestId: input.requestId,
  }).catch(() => null);
  if (!validation) return null;
  if (!validation.ok) {
    console.info(
      JSON.stringify({
        event: "validation_failed",
        requestId: input.requestId,
        generationId: input.generationId,
        errorCode: validation.errorCode,
        durationMs: Date.now() - validationStart,
      })
    );
    return null;
  }
  const value = validation.value;
  console.info(
    JSON.stringify({
      event: "validation_succeeded",
      requestId: input.requestId,
      generationId: input.generationId,
      cameraConsistency: value.cameraConsistency,
      anchorPreservation: value.anchorPreservation,
      identityConsistency: value.identityConsistency,
      temporalCoverage: value.temporalCoverage,
      environmentEvolution: value.environmentEvolution,
      eraCoherence: value.eraCoherence,
      storyAlignment: value.storyAlignment,
      shouldRegenerate: value.shouldRegenerate,
      durationMs: Date.now() - validationStart,
    })
  );
  if (!shouldAttemptRepair(value)) return null;
  const plan = planFromValidation(value);
  const repairInstructions =
    plan?.repairInstructions ?? [DEFAULT_REPAIR_INSTRUCTION];
  const repairPrompt = buildRepairPrompt(
    input.originalPrompt,
    repairInstructions
  );
  const repair = await input.adapter.generate({
    prompt: repairPrompt,
    imageDataUrl: toJpegDataUrl(input.sourceBytes, input.sourceContentType),
    aspectRatio: input.aspectRatio as never,
    useSubjectReference: input.useSubjectReference,
    requestId: input.requestId,
    generationId: `${input.generationId}-repair`,
  });
  if (!repair.ok) {
    console.info(
      JSON.stringify({
        event: "repair_failed",
        requestId: input.requestId,
        generationId: input.generationId,
        errorCode: repair.errorCode,
      })
    );
    return null;
  }
  const repairedUrl = await saveGeneratedImage({
    generationId: `${input.generationId}-repair`,
    bytes: repair.imageBytes,
    contentType: repair.contentType,
  });
  console.info(
    JSON.stringify({
      event: "repair_succeeded",
      requestId: input.requestId,
      generationId: input.generationId,
      repairUrl: repairedUrl,
      problems: value.problems,
      repairInstructions,
    })
  );
  return repairedUrl;
}

function buildRepairPrompt(
  originalPrompt: string,
  instructions: string[]
): string {
  const repairBlock = [
    "REPAIR PASS",
    "上一轮结果被判定为时间分布不均，按下列修复指令重画：",
    ...instructions.map((line, index) => `${index + 1}. ${line}`),
    "其它约束（构图、空间锚点、相机、连续性约束）保持不变。",
  ].join("\n");
  const combined = `${originalPrompt}\n\n${repairBlock}`;
  if (combined.length <= config.promptMaxChars) return combined;

  const prohibitMarker = "\n\nDO NOT";
  const prohibitIndex = originalPrompt.lastIndexOf(prohibitMarker);
  const preserveTail = prohibitIndex >= 0
    ? originalPrompt.slice(prohibitIndex + 2)
    : "";
  const head = prohibitIndex >= 0
    ? originalPrompt.slice(0, prohibitIndex)
    : originalPrompt;
  const separators = preserveTail ? 4 : 2;
  const headBudget = Math.max(
    0,
    config.promptMaxChars
      - repairBlock.length
      - preserveTail.length
      - separators
  );
  return [
    head.slice(0, headBudget).trimEnd(),
    repairBlock,
    preserveTail,
  ].filter(Boolean).join("\n\n").slice(0, config.promptMaxChars);
}

export function toClientGeneration(record: GenerationRecord) {
  const base: Record<string, unknown> = {
    generationId: record.generationId,
    status: record.status,
    requestId: record.requestId,
    modelName: record.modelName,
    imageProvider: record.imageProvider ?? "minimax",
    aspectRatio: record.aspectRatio,
    promptTruncated: record.promptTruncated,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    durationMs: record.durationMs,
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
    imageProvider: record.imageProvider ?? "minimax",
    aspectRatio: record.aspectRatio,
    promptTruncated: record.promptTruncated,
    promptCharCount: record.promptCharCount,
    promptVersion: record.promptVersion,
    promptHash: record.promptHash,
    sectionCharCounts: record.sectionCharCounts,
    truncatedSections: record.truncatedSections,
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

/** Wait helper for tests. */
export async function waitForGeneration(
  generationId: string,
  timeoutMs = 5000
): Promise<GenerationRecord | undefined> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const record = getGeneration(generationId);
    if (record && (record.status === "succeeded" || record.status === "failed")) {
      return record;
    }
    await new Promise((r) => setTimeout(r, 20));
  }
  return getGeneration(generationId);
}
