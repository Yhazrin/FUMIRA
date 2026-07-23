import type { FastifyInstance } from "fastify";
import { analyzeUploadedAsset, writeTemporalStory } from "../intelligence.js";
import type { SceneUnderstandingPayload } from "../types.js";

export async function registerIntelligenceRoutes(app: FastifyInstance): Promise<void> {
  app.post<{ Body: { sourceAssetId?: string; requestId?: string } }>(
    "/v1/understand",
    async (request, reply) => {
      const body = request.body;
      if (!body?.sourceAssetId || !body.requestId?.trim()) {
        return reply.code(400).send(error("invalid_body", "缺少图片或 requestId。", false));
      }
      const result = await analyzeUploadedAsset({
        sourceAssetId: body.sourceAssetId,
        requestId: body.requestId.trim(),
      });
      if (!result.ok) {
        logFailure("understanding", body.requestId.trim(), result);
        return reply.code(statusFor(result.errorCode)).send(error(result.errorCode, result.userMessage, result.retryable));
      }
      return { requestId: body.requestId.trim(), understanding: result.value };
    }
  );

  app.post<{ Body: { understanding?: SceneUnderstandingPayload; requestId?: string } }>(
    "/v1/stories",
    async (request, reply) => {
      const body = request.body;
      if (!body?.understanding || !body.requestId?.trim()) {
        return reply.code(400).send(error("invalid_body", "缺少图片理解结果或 requestId。", false));
      }
      const result = await writeTemporalStory({
        understanding: body.understanding,
        requestId: body.requestId.trim(),
      });
      if (!result.ok) {
        logFailure("story", body.requestId.trim(), result);
        return reply.code(statusFor(result.errorCode)).send(error(result.errorCode, result.userMessage, result.retryable));
      }
      return { requestId: body.requestId.trim(), story: result.value };
    }
  );
}

function error(errorCode: string, userMessage: string, retryable: boolean) {
  return { errorCode, userMessage, retryable };
}

function statusFor(errorCode: string): number {
  if (errorCode === "invalid_source_asset" || errorCode === "invalid_image") return 400;
  if (
    errorCode === "understanding_unavailable" ||
    errorCode === "story_unavailable" ||
    errorCode === "vision_credentials_required"
  ) return 503;
  return 502;
}

function logFailure(
  stage: "understanding" | "story",
  requestId: string,
  result: { errorCode: string; retryable: boolean; statusMsg?: string }
) {
  // Diagnostic only: never log the image, prompt, authorization header, or key.
  console.info(JSON.stringify({
    event: "intelligence_failed",
    stage,
    requestId,
    errorCode: result.errorCode,
    retryable: result.retryable,
    providerMessage: result.statusMsg?.slice(0, 160),
  }));
}
