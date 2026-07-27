import type { FastifyInstance } from "fastify";
import { analyzeUploadedAsset, writeTemporalStory } from "../intelligence.js";
import { resolveStoryCopyConstraints } from "../storyCopy.js";
import { resolveUnderstandingCopyConstraints } from "../understandingCopy.js";
import type {
  SceneUnderstandingPayload,
  StoryCopyConstraints,
  UnderstandingCopyConstraints,
} from "../types.js";

export async function registerIntelligenceRoutes(app: FastifyInstance): Promise<void> {
  app.post<{ Body: {
    sourceAssetId?: string;
    targetTime?: { offsetYears?: number; compactLabel?: string };
    copyConstraints?: Partial<UnderstandingCopyConstraints>;
    requestId?: string;
  } }>(
    "/v1/understand",
    async (request, reply) => {
      const body = request.body;
      if (
        !body?.sourceAssetId
        || !body.requestId?.trim()
        || !Number.isFinite(body.targetTime?.offsetYears)
        || !body.targetTime?.compactLabel?.trim()
      ) {
        return reply.code(400).send(error("invalid_body", "缺少目标图片、目标时间或 requestId。", false));
      }
      const copyConstraints = resolveUnderstandingCopyConstraints(body.copyConstraints);
      const result = await analyzeUploadedAsset({
        sourceAssetId: body.sourceAssetId,
        targetTime: {
          offsetYears: body.targetTime.offsetYears as number,
          compactLabel: body.targetTime.compactLabel.trim(),
        },
        copyConstraints,
        requestId: body.requestId.trim(),
      });
      if (!result.ok) {
        logFailure("understanding", body.requestId.trim(), result);
        return reply.code(statusFor(result.errorCode)).send(error(result.errorCode, result.userMessage, result.retryable));
      }
      return {
        requestId: body.requestId.trim(),
        copyConstraints,
        understanding: result.value,
      };
    }
  );

  app.post<{ Body: {
    understanding?: SceneUnderstandingPayload;
    targetTime?: { offsetYears?: number; compactLabel?: string };
    copyConstraints?: Partial<StoryCopyConstraints>;
    requestId?: string;
  } }>(
    "/v1/stories",
    async (request, reply) => {
      const body = request.body;
      if (!body?.understanding || !body.requestId?.trim() || !Number.isFinite(body.targetTime?.offsetYears) || !body.targetTime?.compactLabel?.trim()) {
        return reply.code(400).send(error("invalid_body", "缺少图片理解、目标年份或 requestId。", false));
      }
      const copyConstraints = resolveStoryCopyConstraints(body.copyConstraints);
      const result = await writeTemporalStory({
        understanding: body.understanding,
        targetTime: {
          offsetYears: body.targetTime.offsetYears as number,
          compactLabel: body.targetTime.compactLabel.trim(),
        },
        copyConstraints,
        requestId: body.requestId.trim(),
      });
      if (!result.ok) {
        logFailure("story", body.requestId.trim(), result);
        return reply.code(statusFor(result.errorCode)).send(error(result.errorCode, result.userMessage, result.retryable));
      }
      return {
        requestId: body.requestId.trim(),
        copyConstraints,
        story: result.value,
      };
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
