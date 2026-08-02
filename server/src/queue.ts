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
  ExactTarget,
  GenerationContext,
  GenerationRecord,
  GenerationValidationResult,
  ImageGenerationAdapter,
  ImageGenerationProvider,
  SceneUnderstandingPayload,
  StoryBeatPayload,
  StructuredGenerationBody,
  TimePositionPayload,
} from "./types.js";
import { resolveTier, type TierProfile } from "./tiers.js";
import {
  getPostGenerationValidationAdapter,
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
    tier: TierProfile;
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
  const tier = resolveTier((body as { tier?: unknown }).tier);
  const imageProvider: ImageGenerationProvider =
    body.imageProvider ?? tier.imageProvider;
  const adapter = getImageGenerationAdapter(imageProvider);
  const imageModel =
    imageProvider === "apimart"
      ? resolveAPIMartImageModel(body.imageModel, tier)
      : undefined;
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

  const timeValidation = validateTimePosition(body.timePosition);
  if (timeValidation) return timeValidation;
  const timePosition = canonicalTimePosition(body.timePosition.offsetDays);

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
    const ctx = injectTargetTime(structured, timePosition);
    built = compilePrompt({
      context: ctx,
      timePosition,
      aspectRatio,
      promptDetail: tier.promptDetail,
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
      ?? pickNearestBeat(legacy.temporalStory, timePosition.offsetYears)
      ?? null;
    understanding = legacy.understanding ?? null;

    if (legacy.understanding || legacy.temporalStory || legacy.storyBeat) {
      const corePrompt = forceMarker
        ?? compileStoryDrivenPrompt({
          time: timePosition,
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
        ?? makeTemporalImagePrompt(timePosition);
      built = buildPrompt({
        template: settings.promptTemplate,
        corePrompt,
        timePosition,
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
            timePosition,
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
    modelName:
      imageProvider === "apimart"
        ? (imageModel ?? tier.imageModel)
        : settings.modelName,
    imageProvider,
    aspectRatio,
    tier: tier.id,
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
    targetTime: timePosition,
    tier,
  });

  putGeneration(record);
  void processGeneration(record.generationId);

  console.info(
    JSON.stringify({
      event: "generation_queued",
      requestId: record.requestId,
      generationId: record.generationId,
      status: record.status,
      tier: tier.id,
      model: record.modelName,
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

export const MAXIMUM_TIME_OFFSET_DAYS = 36_525;
const TIME_POSITION_CURVE_EXPONENT = 2.35;
const TIME_POSITION_TOLERANCE_YEARS = 0.001;
const TIME_POSITION_TOLERANCE_NORMALIZED = 1e-9;

/**
 * Rebuild every derived time field from offsetDays, the generation contract's
 * sole time identity. Callers must range-check before invoking this helper.
 */
export function canonicalTimePosition(
  offsetDays: number,
  referenceDate = new Date()
): TimePositionPayload & { targetDateISO: string } {
  const normalized = offsetDays === 0
    ? 0
    : Math.sign(offsetDays) * Math.pow(
        Math.abs(offsetDays) / MAXIMUM_TIME_OFFSET_DAYS,
        1 / TIME_POSITION_CURVE_EXPONENT
      );
  const targetDate = new Date(
    referenceDate.getTime() + offsetDays * 86_400_000
  );
  return {
    normalized,
    offsetDays,
    offsetYears: offsetDays / 365.25,
    compactLabel: compactTimeLabel(offsetDays),
    targetDateISO: targetDate.toISOString().slice(0, 10),
  };
}

function compactTimeLabel(offsetDays: number): string {
  const days = Math.abs(offsetDays);
  if (days < 1 / 48) return "NOW";

  const direction = offsetDays < 0 ? "前" : "后";
  if (days < 1) return `${Math.round(days * 24)} 小时${direction}`;
  if (days < 31) return `${Math.round(days)} 天${direction}`;
  if (days < 365.25) return `${(days / 30.44).toFixed(1)} 个月${direction}`;
  if (days < 3_652.5) return `${(days / 365.25).toFixed(1)} 年${direction}`;
  return `${Math.round(days / 365.25)} 年${direction}`;
}

function validateTimePosition(
  timePosition: CreateGenerationBody["timePosition"] | undefined
): ReturnType<typeof contractError> | null {
  if (
    !timePosition
    || !Number.isFinite(timePosition.normalized)
    || !Number.isFinite(timePosition.offsetDays)
    || !Number.isFinite(timePosition.offsetYears)
    || typeof timePosition.compactLabel !== "string"
    || !timePosition.compactLabel.trim()
  ) {
    return contractError(400, "invalid_time_position", "时间位置无效。");
  }

  if (
    Math.abs(timePosition.normalized) > 1
    || Math.abs(timePosition.offsetDays) > MAXIMUM_TIME_OFFSET_DAYS
  ) {
    return contractError(400, "invalid_time_position", "时间超出可生成的前后一百年范围。");
  }

  const canonical = canonicalTimePosition(timePosition.offsetDays);
  if (
    Math.abs(timePosition.offsetYears - canonical.offsetYears)
      > TIME_POSITION_TOLERANCE_YEARS
    || Math.abs(timePosition.normalized - canonical.normalized)
      > TIME_POSITION_TOLERANCE_NORMALIZED
    || timePosition.compactLabel.trim() !== canonical.compactLabel
  ) {
    return contractError(400, "invalid_time_position", "时间位置字段彼此不一致。");
  }

  return null;
}

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
function injectTargetTime(
  body: StructuredGenerationBody,
  timePosition: TimePositionPayload & { targetDateISO: string }
): GenerationContext {
  const exactTarget: ExactTarget = {
    offsetDays: timePosition.offsetDays,
    targetDateISO: timePosition.targetDateISO,
    compactLabel: timePosition.compactLabel,
  };
  return {
    ...body.structuredContext,
    story: {
      ...body.structuredContext.story,
      targetBeat: {
        ...body.structuredContext.story.targetBeat,
        // Overwrite the LLM's anchorYears with the program-authoritative value.
        anchorYears: timePosition.offsetYears,
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
      modelName: current.modelName,
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

    const tier = stored?.tier ?? resolveTier(current.tier);
    const quality = await runQualityLoop({
      generationId,
      sourceAssetId: current.sourceAssetId,
      requestId: current.requestId,
      sourceBytes: asset.bytes,
      sourceContentType: asset.contentType,
      targetBytes: result.imageBytes,
      targetContentType: result.contentType,
      primaryRelativeUrl: resultRelativeUrl,
      targetTime: stored?.targetTime ?? {
        offsetYears: 0,
        compactLabel: "NOW",
      },
      understanding: stored?.understanding ?? null,
      storyBeat: stored?.storyBeat ?? null,
      aspectRatio: current.aspectRatio,
      adapter,
      modelName: current.modelName,
      useSubjectReference: Boolean(stored?.useSubjectReference),
      originalPrompt: prompt,
      validationEnabled: tier.validationEnabled,
      maxRounds: tier.repairRounds,
    });
    promptByGeneration.delete(generationId);

    updateGeneration(generationId, {
      status: "succeeded",
      finishedAt: new Date().toISOString(),
      durationMs: Date.now() - startedAt,
      resultRelativeUrl: quality.relativeUrl,
      repairedResultRelativeUrl:
        quality.relativeUrl === resultRelativeUrl
          ? undefined
          : quality.relativeUrl,
      repairAttempts: quality.repairAttempts,
      validationSummary: quality.lastSummary,
      qualityScore: quality.qualityScore,
      qualityHistory: quality.qualityHistory,
    });

    console.info(
      JSON.stringify({
        event: "generation_succeeded",
        requestId: current.requestId,
        generationId,
        durationMs: Date.now() - startedAt,
        model: current.modelName,
        provider: current.imageProvider,
        tier: tier.id,
        qualityScore: quality.qualityScore,
        repairAttempts: quality.repairAttempts,
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

interface QualityLoopOutcome {
  relativeUrl: string;
  qualityScore?: number;
  qualityHistory: number[];
  repairAttempts: number;
  lastSummary?: GenerationValidationResult;
}

const VALIDATION_METRICS = [
  "cameraConsistency",
  "anchorPreservation",
  "identityConsistency",
  "temporalCoverage",
  "environmentEvolution",
  "eraCoherence",
  "storyAlignment",
] as const;

function meanScore(value: GenerationValidationResult): number {
  const total = VALIDATION_METRICS.reduce(
    (sum, metric) => sum + value[metric],
    0
  );
  return total / VALIDATION_METRICS.length;
}

/**
 * Bounded validate → repair → re-validate loop.
 *
 * Each repair round sees both the source and the rejected attempt, and its
 * output is validated again rather than trusted. The highest-scoring image
 * across all rounds wins, so a repair can never make the served result worse.
 */
async function runQualityLoop(input: {
  generationId: string;
  sourceAssetId: string;
  requestId: string;
  sourceBytes: Buffer;
  sourceContentType: string;
  targetBytes: Buffer;
  targetContentType: string;
  primaryRelativeUrl: string;
  targetTime: { offsetYears: number; compactLabel: string };
  understanding: SceneUnderstandingPayload | null;
  storyBeat: StoryBeatPayload | null;
  aspectRatio: ImageGenerationAdapter["generate"] extends (args: infer A) => unknown
    ? (A extends { aspectRatio: infer R } ? R : never)
    : never;
  adapter: ImageGenerationAdapter;
  modelName: string;
  useSubjectReference: boolean;
  originalPrompt: string;
  validationEnabled: boolean;
  maxRounds: number;
}): Promise<QualityLoopOutcome> {
  const idle: QualityLoopOutcome = {
    relativeUrl: input.primaryRelativeUrl,
    qualityHistory: [],
    repairAttempts: 0,
  };
  if (!input.validationEnabled) return idle;
  if (!getPostGenerationValidationAdapter()) return idle;

  let currentBytes = input.targetBytes;
  let currentContentType = input.targetContentType;
  let currentUrl = input.primaryRelativeUrl;
  let bestUrl = input.primaryRelativeUrl;
  let bestScore = -1;
  let repairAttempts = 0;
  let lastSummary: GenerationValidationResult | undefined;
  const qualityHistory: number[] = [];

  for (let round = 0; round <= input.maxRounds; round += 1) {
    const validationStart = Date.now();
    const validation = await runPostGenerationValidation({
      sourceAssetId: input.sourceAssetId,
      sourceContentType: input.sourceContentType,
      targetBytes: currentBytes,
      targetContentType: currentContentType,
      targetTime: input.targetTime,
      understanding: input.understanding,
      storyBeat: input.storyBeat,
      requestId: input.requestId,
    }).catch(() => null);

    if (!validation || !validation.ok) {
      console.info(
        JSON.stringify({
          event: "validation_failed",
          requestId: input.requestId,
          generationId: input.generationId,
          round,
          errorCode: validation?.ok === false ? validation.errorCode : "no_result",
          durationMs: Date.now() - validationStart,
        })
      );
      break;
    }

    const value = validation.value;
    lastSummary = value;
    const score = meanScore(value);
    qualityHistory.push(Number(score.toFixed(4)));
    if (score > bestScore) {
      bestScore = score;
      bestUrl = currentUrl;
    }

    console.info(
      JSON.stringify({
        event: "validation_succeeded",
        requestId: input.requestId,
        generationId: input.generationId,
        round,
        score: Number(score.toFixed(4)),
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

    if (!shouldAttemptRepair(value)) break;
    if (round === input.maxRounds) break;

    const repairInstructions = value.repairInstructions.length
      ? value.repairInstructions
      : [DEFAULT_REPAIR_INSTRUCTION];
    const repairId = `${input.generationId}-repair-${round + 1}`;
    const repair = await input.adapter.generate({
      prompt: buildRepairPrompt(input.originalPrompt, repairInstructions),
      imageDataUrl: toJpegDataUrl(input.sourceBytes, input.sourceContentType),
      priorAttemptDataUrl: toJpegDataUrl(currentBytes, currentContentType),
      aspectRatio: input.aspectRatio as never,
      useSubjectReference: input.useSubjectReference,
      requestId: input.requestId,
      generationId: repairId,
      modelName: input.modelName,
    });

    if (!repair.ok) {
      console.info(
        JSON.stringify({
          event: "repair_failed",
          requestId: input.requestId,
          generationId: input.generationId,
          round: round + 1,
          errorCode: repair.errorCode,
        })
      );
      break;
    }

    repairAttempts += 1;
    currentBytes = repair.imageBytes;
    currentContentType = repair.contentType;
    currentUrl = await saveGeneratedImage({
      generationId: repairId,
      bytes: currentBytes,
      contentType: currentContentType,
    });

    console.info(
      JSON.stringify({
        event: "repair_succeeded",
        requestId: input.requestId,
        generationId: input.generationId,
        round: round + 1,
        repairUrl: currentUrl,
        problems: value.problems,
        repairInstructions,
      })
    );
  }

  return {
    relativeUrl: bestUrl,
    qualityScore: bestScore >= 0 ? Number(bestScore.toFixed(4)) : undefined,
    qualityHistory,
    repairAttempts,
    lastSummary,
  };
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
    tier: record.tier,
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
    tier: record.tier,
    promptTruncated: record.promptTruncated,
    promptCharCount: record.promptCharCount,
    promptVersion: record.promptVersion,
    promptHash: record.promptHash,
    sectionCharCounts: record.sectionCharCounts,
    truncatedSections: record.truncatedSections,
    qualityScore: record.qualityScore,
    qualityHistory: record.qualityHistory,
    repairAttempts: record.repairAttempts,
    validationSummary: record.validationSummary,
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

const APIMART_IMAGE_MODELS = new Set([
  "gpt-4o-image",
  "gpt-image-2",
  "gemini-3.1-flash-image-preview",
  "gemini-3-pro-image-preview",
  "doubao-seedream-5-0-pro",
  "flux-kontext-pro",
]);

function resolveAPIMartImageModel(
  raw: string | undefined,
  tier: TierProfile
): string {
  const trimmed = raw?.trim();
  if (trimmed && APIMART_IMAGE_MODELS.has(trimmed)) {
    return trimmed;
  }
  return APIMART_IMAGE_MODELS.has(tier.imageModel)
    ? tier.imageModel
    : "gpt-4o-image";
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
