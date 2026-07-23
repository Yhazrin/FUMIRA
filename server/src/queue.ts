import { randomUUID } from "node:crypto";
import { config } from "./config.js";
import { buildPrompt, normalizeAspectRatio, toJpegDataUrl } from "./prompt.js";
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
  GenerationRecord,
  MiniMaxAdapter,
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
  // Runtime readiness = admin kill-switch + an attached adapter.
  // Startup attaches live/mock adapters based on env; tests may inject adapters.
  if (!settings.remoteGenerationEnabled || !adapter) {
    return {
      ok: false,
      statusCode: 503,
      errorCode: "generation_unavailable",
      userMessage: "远程生成暂未就绪。",
      retryable: true,
    };
  }

  const aspectRatio = normalizeAspectRatio(body.aspectRatio);
  if (!aspectRatio) {
    return {
      ok: false,
      statusCode: 400,
      errorCode: "invalid_aspect_ratio",
      userMessage: "不支持的画幅比例。",
      retryable: false,
    };
  }

  if (!body.requestId?.trim()) {
    return {
      ok: false,
      statusCode: 400,
      errorCode: "missing_request_id",
      userMessage: "缺少 requestId。",
      retryable: false,
    };
  }

  if (!body.sourceAssetId || !getAsset(body.sourceAssetId)) {
    return {
      ok: false,
      statusCode: 400,
      errorCode: "invalid_source_asset",
      userMessage: "源图片不存在或已过期。",
      retryable: false,
    };
  }

  if (typeof body.story !== "string" || !body.story.trim()) {
    return {
      ok: false,
      statusCode: 400,
      errorCode: "missing_story",
      userMessage: "缺少故事内容。",
      retryable: false,
    };
  }

  if (!body.timePosition || typeof body.timePosition.normalized !== "number") {
    return {
      ok: false,
      statusCode: 400,
      errorCode: "invalid_time_position",
      userMessage: "时间位置无效。",
      retryable: false,
    };
  }

  const built = buildPrompt({
    template: settings.promptTemplate,
    story: body.story,
    timePosition: body.timePosition,
    aspectRatio,
  });

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
    })
  );

  return { ok: true, record };
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
