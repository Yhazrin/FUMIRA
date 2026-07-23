import Fastify from "fastify";
import multipart from "@fastify/multipart";
import { config, isGenerationReady } from "./config.js";
import { LiveMiniMaxAdapter } from "./minimax/liveAdapter.js";
import { MockMiniMaxAdapter } from "./minimax/mockAdapter.js";
import { setMiniMaxAdapter } from "./queue.js";
import { registerAdminRoutes } from "./routes/admin.js";
import { registerGenerationRoutes } from "./routes/generations.js";
import { registerHealthRoutes } from "./routes/health.js";
import { registerUploadRoutes } from "./routes/uploads.js";
import { initStorage } from "./storage.js";
import type { MiniMaxAdapter } from "./types.js";

export interface BuildAppOptions {
  /** Force a specific adapter (tests). */
  adapter?: MiniMaxAdapter | null;
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
        : config.minimaxApiKey
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
