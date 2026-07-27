import { randomUUID } from "node:crypto";
import { config } from "./config.js";
import { buildPrompt, normalizeAspectRatio, toJpegDataUrl } from "./prompt.js";
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
  GenerationRecord,
  ImageGenerationAdapter,
  ImageGenerationProvider,
} from "./types.js";
// TODO(P2 validation): wire `buildValidationPrompt` / `shouldAttemptRepair`
// from `./validation.js` after first successful generation when dual-image
// VLM compare is available. Keep generation succeeding without auto-redraw for now.

const adapters = new Map<ImageGenerationProvider, ImageGenerationAdapter>();
const processing = new Set<string>();
const promptByGeneration = new Map<
  string,
  { prompt: string; useSubjectReference: boolean }
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

  if (!body.timePosition || typeof body.timePosition.normalized !== "number") {
    return {
      ok: false,
      statusCode: 400,
      errorCode: "invalid_time_position",
      userMessage: "时间位置无效。",
      retryable: false,
    };
  }

  // Server is the sole prompt author. Client `prompt` / `story` strings are
  // ignored except for mock/test force markers (`__FORCE_*__`).
  const clientPrompt =
    typeof body.prompt === "string" && body.prompt.trim()
      ? body.prompt.trim()
      : typeof body.story === "string" && body.story.trim()
        ? body.story.trim()
        : "";
  const forceMarker = /__FORCE_[A-Z0-9_]+__/.test(clientPrompt) ? clientPrompt : null;
  if (clientPrompt && !forceMarker) {
    console.info(
      JSON.stringify({
        event: "client_prompt_ignored",
        requestId: body.requestId.trim(),
        clientPromptChars: clientPrompt.length,
      })
    );
  }

  const beat =
    body.storyBeat
    ?? pickNearestBeat(body.temporalStory, body.timePosition.offsetYears);
  const corePrompt = forceMarker
    ?? (compileStoryDrivenPrompt({
      time: body.timePosition,
      understanding: body.understanding,
      story: body.temporalStory
        ? {
            identityRules: body.temporalStory.identityRules,
            logline: body.temporalStory.logline,
            presentTruth: body.temporalStory.presentTruth,
          }
        : null,
      beat,
    }) || makeTemporalImagePrompt(body.timePosition));

  const built = buildPrompt({
    template: settings.promptTemplate,
    corePrompt,
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
    modelName: imageProvider === "apimart" ? "gpt-image-2" : settings.modelName,
    imageProvider,
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
      return;
    }

    const resultRelativeUrl = await saveGeneratedImage({
      generationId,
      bytes: result.imageBytes,
      contentType: result.contentType,
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
