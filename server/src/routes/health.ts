import type { FastifyInstance } from "fastify";
import { config } from "../config.js";
import { getMiniMaxAdapter } from "../queue.js";
import { getMiniMaxIntelligenceAdapter } from "../intelligence.js";
import { getSettings } from "../storage.js";

export async function registerHealthRoutes(app: FastifyInstance): Promise<void> {
  const handler = async () => {
    const settings = getSettings();
    const hasGenerationAdapter = getMiniMaxAdapter() !== null;
    const intelligence = getMiniMaxIntelligenceAdapter();
    const generationReady = settings.remoteGenerationEnabled && hasGenerationAdapter;

    return {
      ok: true,
      service: "fumira-server",
      generation: {
        ready: generationReady,
        mode: !generationReady
          ? "unavailable"
          : config.minimaxMock
            ? "mock"
            : "live",
        promptCompiler: "v3",
      },
      intelligence: {
        ready: intelligence !== null,
        provider: intelligence !== null ? "minimax" : "unavailable",
        capabilities: {
          v2Understanding: Boolean(intelligence?.analyzeImage),
          story: Boolean(intelligence?.writeStory),
          sceneGraph: Boolean(intelligence?.analyzeSceneGraph),
          temporalRenderPlan: Boolean(intelligence?.planTemporalRender),
          visualCritic: Boolean(intelligence?.critiqueGeneration) && config.visualCriticEnabled,
        },
      },
      qualityPolicy: {
        visualCriticEnabled: config.visualCriticEnabled,
        maxRegenerations: config.visualCriticMaxRegenerations,
        thresholds: config.visualCriticThresholds,
      },
      timestamp: new Date().toISOString(),
    };
  };

  app.post("/health", handler);
  app.get("/health", handler);
}
