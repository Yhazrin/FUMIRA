import { randomUUID } from "node:crypto";
import { config } from "./config.js";
import { normalizeAspectRatio, toJpegDataUrl } from "./prompt.js";
import { compilePrompt, buildLegacyPrompt } from "./promptCompiler.js";
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
  MiniMaxAdapter,
  StructuredGenerationBody,
  TemporalStoryPayloadV2,
} from "./types.js";

let adapter: MiniMaxAdapter | null = null;
const processing = new Set<string>();
const promptByGeneration = new Map<
  string,
  { prompt: string; useSubjectReference: boolean }
>();

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

  // Discriminated union: reject mixed input (Task 4 & 6).
  if ((body as any).contextVersion === undefined) {
    // Legacy body without contextVersion — treat as legacy.v1
    (body as any).contextVersion = "legacy.v1";
  }

  // V2 structured path: server-side prompt compilation.
  // Legacy path: client sends a flat story string, server wraps in template.
  let built: {
    prompt: string;
    truncated: boolean;
    charCount: number;
    version?: string;
    hash?: string;
    sectionCharCounts?: Record<string, number>;
    truncatedSections?: string[];
  };

  if (body.contextVersion === "generation.v2") {
    // V2: validate structured context contract.
    const v2Validation = validateStructuredContext(body.structuredContext);
    if (v2Validation) return v2Validation;

    // Inject program-authoritative time values into targetBeat (Task 5).
    // The LLM's anchorYears is a hint; offsetDays is the truth.
    const ctx = injectTargetTime(body as StructuredGenerationBody);
    built = compilePrompt({
      context: ctx,
      timePosition: body.timePosition,
      aspectRatio,
    });
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
  };

  promptByGeneration.set(record.generationId, {
    prompt: built.prompt,
    useSubjectReference: Boolean(body.useSubjectReference),
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
  "temporal-story.v2",
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
  if (ctx.story.schemaVersion !== "temporal-story.v2") {
    return contractError(400, "unsupported_schema_version", `故事 schema 版本不匹配: ${ctx.story.schemaVersion ?? "undefined"}`);
  }
  if (!ctx.story.targetBeat) {
    return contractError(400, "missing_target_beat", "V2 故事缺少精确目标节点 (targetBeat)。");
  }
  const tb = ctx.story.targetBeat;
  if (!Number.isFinite(tb.anchorYears) || !tb.visualPrompt) {
    return contractError(400, "invalid_target_beat", "targetBeat 缺少必要字段 (anchorYears, visualPrompt)。");
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
      },
    },
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
      return;
    }

    const resultRelativeUrl = await saveGeneratedImage({
      generationId,
      bytes: result.imageBytes,
    });

    updateGeneration(generationId, {
      status: "succeeded",
      finishedAt: new Date().toISOString(),
      durationMs: Date.now() - startedAt,
      resultRelativeUrl,
    });

    console.info(
      JSON.stringify({
        event: "generation_succeeded",
        requestId: current.requestId,
        generationId,
        durationMs: Date.now() - startedAt,
        model: config.modelName,
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
