import type { FastifyInstance } from "fastify";
import { config } from "../config.js";
import { getMiniMaxAdapter } from "../queue.js";
import { getMiniMaxIntelligenceAdapter } from "../intelligence.js";
import { getSettings } from "../storage.js";

export async function registerHealthRoutes(app: FastifyInstance): Promise<void> {
  const handler = async () => {
    const settings = getSettings();
    const hasAdapter = getMiniMaxAdapter() !== null;
    const generationReady = settings.remoteGenerationEnabled && hasAdapter;

    return {
      ok: true,
      service: "fumira-server",
      generation: {
        ready: generationReady,
        // Coarse mode only — never reveal whether MINIMAX_API_KEY is set.
        mode: !generationReady
          ? "unavailable"
          : config.minimaxMock
            ? "mock"
            : "live",
      },
      intelligence: {
        ready: getMiniMaxIntelligenceAdapter() !== null,
        provider: getMiniMaxIntelligenceAdapter() !== null ? "minimax" : "unavailable",
      },
      timestamp: new Date().toISOString(),
    };
  };

  app.post("/health", handler);
  app.get("/health", handler);
}
