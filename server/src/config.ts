import path from "node:path";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const SERVER_ROOT = path.resolve(__dirname, "..");

dotenv.config({ path: path.join(SERVER_ROOT, ".env") });

function boolEnv(name: string, fallback: boolean): boolean {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  return ["1", "true", "yes", "on"].includes(raw.toLowerCase());
}

function numberEnv(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
}

export const config = {
  port: Number(process.env.PORT ?? "8787"),
  publicBaseUrl: (process.env.PUBLIC_BASE_URL ?? "http://127.0.0.1:8787").replace(/\/$/, ""),
  minimaxApiKey: process.env.MINIMAX_API_KEY?.trim() ?? "",
  minimaxVlmApiKey: process.env.MINIMAX_VLM_API_KEY?.trim() ?? "",
  adminToken: process.env.ADMIN_TOKEN?.trim() ?? "",
  minimaxMock: boolEnv("MINIMAX_MOCK", false),
  remoteGenerationEnabled: boolEnv("REMOTE_GENERATION_ENABLED", true),
  promptTemplate:
    process.env.PROMPT_TEMPLATE?.trim() ||
    "Based on the source photo, generate the same place at {{timeLabel}}. Story: {{story}}. Keep original composition, camera angle, and main subject identity. No extra people or text.",
  uploadsDir: process.env.UPLOADS_DIR || path.join(SERVER_ROOT, "uploads"),
  generatedDir: process.env.GENERATED_DIR || path.join(SERVER_ROOT, "generated"),
  dataDir: process.env.DATA_DIR || path.join(SERVER_ROOT, "data"),
  maxUploadBytes: 10 * 1024 * 1024,
  minimaxTimeoutMs: 240_000,
  promptMaxChars: 1500,
  allowedAspectRatios: [
    "1:1",
    "16:9",
    "4:3",
    "3:2",
    "2:3",
    "3:4",
    "9:16",
    "21:9",
  ] as const,
  modelName: "image-01",
  minimaxApiBaseUrl: (process.env.MINIMAX_API_BASE_URL?.trim() || "https://api.minimaxi.com").replace(/\/$/, ""),
  minimaxTextModel: process.env.MINIMAX_TEXT_MODEL?.trim() || "MiniMax-M2.7-highspeed",
  minimaxStoryModel: process.env.MINIMAX_STORY_MODEL?.trim() || "MiniMax-M3",
  visualCriticEnabled: boolEnv("VISUAL_CRITIC_ENABLED", true),
  visualCriticMaxRegenerations: Math.max(0, Math.min(1, Math.round(numberEnv("VISUAL_CRITIC_MAX_REGENERATIONS", 1)))) as 0 | 1,
  visualCriticThresholds: {
    cameraConsistency: numberEnv("VISUAL_CRITIC_CAMERA_THRESHOLD", 0.78),
    requiredChangeCompletion: numberEnv("VISUAL_CRITIC_CHANGE_THRESHOLD", 0.72),
    environmentEvolution: numberEnv("VISUAL_CRITIC_ENVIRONMENT_THRESHOLD", 0.62),
    eraCoherence: numberEnv("VISUAL_CRITIC_ERA_THRESHOLD", 0.72),
  },
  /**
   * Optional explicit HTTPS proxy for MiniMax outbound calls.
   * Prefer env HTTPS_PROXY / HTTP_PROXY / MINIMAX_HTTPS_PROXY.
   */
  httpsProxy: process.env.MINIMAX_HTTPS_PROXY?.trim()
    || process.env.HTTPS_PROXY?.trim()
    || process.env.HTTP_PROXY?.trim()
    || "",
};

export type AspectRatio = (typeof config.allowedAspectRatios)[number];

export function isGenerationReady(): boolean {
  if (!config.remoteGenerationEnabled) return false;
  if (config.minimaxMock) return true;
  return config.minimaxApiKey.length > 0;
}
