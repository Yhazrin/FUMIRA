import Fastify from "fastify";
import multipart from "@fastify/multipart";
import { config, isGenerationReady } from "./config.js";
import { LiveAPIMartAdapter } from "./apimart/liveAdapter.js";
import { LiveMiniMaxAdapter } from "./minimax/liveAdapter.js";
import { LiveMiniMaxIntelligenceAdapter } from "./minimax/liveIntelligenceAdapter.js";
import { setMiniMaxIntelligenceAdapter } from "./intelligence.js";
import { LiveMiniMaxValidationAdapter } from "./minimax/liveValidationAdapter.js";
import { MockValidationAdapter } from "./minimax/mockValidationAdapter.js";
import { setPostGenerationValidationAdapter } from "./validationService.js";
import { MockMiniMaxAdapter } from "./minimax/mockAdapter.js";
import {
  setImageGenerationAdapter,
  setMiniMaxAdapter,
} from "./queue.js";
import { registerAdminRoutes } from "./routes/admin.js";
import { registerGenerationRoutes } from "./routes/generations.js";
import { registerHealthRoutes } from "./routes/health.js";
import { registerIntelligenceRoutes } from "./routes/intelligence.js";
import { registerUploadRoutes } from "./routes/uploads.js";
import { initStorage } from "./storage.js";
import type { MiniMaxAdapter } from "./types.js";

export interface BuildAppOptions {
  /** Force a specific adapter (tests). */
  adapter?: MiniMaxAdapter | null;
  /** Force a specific API Mart adapter (tests). */
  apiMartAdapter?: MiniMaxAdapter | null;
  /** Force a specific image-understanding / story adapter (tests). */
  intelligenceAdapter?: import("./types.js").MiniMaxIntelligenceAdapter | null;
  /** Force a specific dual-image validation adapter (tests). */
  validationAdapter?: import("./types.js").PostGenerationValidationAdapter | null;
  /** Disable the live validation binding even when keys exist (tests). */
  disableLiveValidation?: boolean;
  /** Skip binding listen — for inject() tests. */
  skipListen?: boolean;
}

export async function buildApp(options: BuildAppOptions = {}) {
  await initStorage();

  if (options.adapter !== undefined) {
    setMiniMaxAdapter(options.adapter);
  } else if (config.minimaxMock) {
    setMiniMaxAdapter(new MockMiniMaxAdapter());
  } else if (config.minimaxApiKey) {
    setMiniMaxAdapter(new LiveMiniMaxAdapter(config.minimaxApiKey));
  } else {
    setMiniMaxAdapter(null);
  }

  if (options.apiMartAdapter !== undefined) {
    setImageGenerationAdapter("apimart", options.apiMartAdapter);
  } else if (config.minimaxMock) {
    setImageGenerationAdapter("apimart", new MockMiniMaxAdapter());
  } else if (config.apiMartApiKey) {
    setImageGenerationAdapter(
      "apimart",
      new LiveAPIMartAdapter(config.apiMartApiKey)
    );
  } else {
    setImageGenerationAdapter("apimart", null);
  }

  if (options.intelligenceAdapter !== undefined) {
    setMiniMaxIntelligenceAdapter(options.intelligenceAdapter);
  } else if (config.minimaxApiKey) {
    setMiniMaxIntelligenceAdapter(new LiveMiniMaxIntelligenceAdapter(
      config.minimaxApiKey,
      config.minimaxVlmApiKey
    ));
  } else {
    setMiniMaxIntelligenceAdapter(null);
  }

  if (options.validationAdapter !== undefined) {
    setPostGenerationValidationAdapter(options.validationAdapter);
  } else if (options.disableLiveValidation) {
    setPostGenerationValidationAdapter(null);
  } else if (config.minimaxMock) {
    // Default to a passing mock validator in mock mode so the queue can
    // exercise the validation pipeline without a live VLM round-trip.
    setPostGenerationValidationAdapter(new MockValidationAdapter());
  } else if (config.minimaxApiKey) {
    setPostGenerationValidationAdapter(new LiveMiniMaxValidationAdapter(
      config.minimaxApiKey,
      config.minimaxVlmApiKey
    ));
  } else {
    setPostGenerationValidationAdapter(null);
  }

  const app = Fastify({
    logger: false,
    bodyLimit: config.maxUploadBytes + 1024 * 64,
  });

  await app.register(multipart, {
    limits: {
      fileSize: config.maxUploadBytes,
      files: 1,
    },
  });

  await registerHealthRoutes(app);
  await registerIntelligenceRoutes(app);
  await registerUploadRoutes(app);
  await registerGenerationRoutes(app);
  await registerAdminRoutes(app);

  app.setErrorHandler((error, _request, reply) => {
    const code = (error as { code?: string }).code;
    if (code === "FST_REQ_FILE_TOO_LARGE") {
      return reply.code(413).send({
        errorCode: "file_too_large",
        userMessage: "图片不能超过 10MB。",
        retryable: false,
      });
    }
    console.info(
      JSON.stringify({
        event: "request_error",
        errorCode: code ?? "internal_error",
        message: error instanceof Error ? error.message.slice(0, 120) : "error",
      })
    );
    return reply.code(500).send({
      errorCode: "internal_error",
      userMessage: "服务暂时不可用。",
      retryable: true,
    });
  });

  return app;
}

async function main() {
  const app = await buildApp();
  await app.listen({ port: config.port, host: "0.0.0.0" });
  console.info(
    JSON.stringify({
      event: "server_started",
      port: config.port,
      generationReady: isGenerationReady(),
      mode: config.minimaxMock
        ? "mock"
        : config.minimaxApiKey || config.apiMartApiKey
          ? "live"
          : "unavailable",
    })
  );
}

const isDirectRun =
  process.argv[1] &&
  (process.argv[1].endsWith("index.ts") || process.argv[1].endsWith("index.js"));

if (isDirectRun) {
  main().catch((error) => {
    console.error(
      JSON.stringify({
        event: "server_crash",
        message: error instanceof Error ? error.message : "crash",
      })
    );
    process.exit(1);
  });
}
