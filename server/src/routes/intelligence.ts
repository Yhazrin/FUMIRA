import type { FastifyInstance } from "fastify";
import { analyzeUploadedAsset, writeTargetBeat, writeTemporalStory } from "../intelligence.js";
import { resolveStoryCopyConstraints } from "../storyCopy.js";
import { resolveUnderstandingCopyConstraints } from "../understandingCopy.js";
import type {
  CameraObservationPayload,
  ExactTarget,
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
    narrativeAnchor?: { normalizedX?: number; normalizedY?: number };
    opticalContext?: Partial<CameraObservationPayload>;
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
      const narrativeAnchor = normalizeNarrativeAnchor(body.narrativeAnchor);
      const opticalContext = normalizeOpticalContext(body.opticalContext);
      const result = await analyzeUploadedAsset({
        sourceAssetId: body.sourceAssetId,
        targetTime: {
          offsetYears: body.targetTime.offsetYears as number,
          compactLabel: body.targetTime.compactLabel.trim(),
        },
        copyConstraints,
        requestId: body.requestId.trim(),
        narrativeAnchor,
        opticalContext,
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
    targetTime?: { offsetYears?: number; offsetDays?: number; compactLabel?: string };
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
      const offsetDays = body.targetTime.offsetDays ?? (body.targetTime.offsetYears as number) * 365.25;
      const now = new Date();
      const targetDate = new Date(now.getTime() + offsetDays * 86_400_000);
      const exactTarget: ExactTarget = {
        offsetDays,
        targetDateISO: targetDate.toISOString().slice(0, 10),
        compactLabel: body.targetTime.compactLabel.trim(),
      };
      const result = await writeTemporalStory({
        understanding: body.understanding,
        targetTime: exactTarget,
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

  app.post<{ Body: {
    understanding?: SceneUnderstandingPayload;
    storyContext?: {
      title?: string;
      presentTruth?: string;
      identityRules?: string[];
      canonicalBeats?: Array<{ anchorYears?: number; title?: string; narrative?: string; visualPrompt?: string }>;
    };
    target?: { offsetDays?: number; targetDateISO?: string; compactLabel?: string };
    requestId?: string;
  } }>(
    "/v1/target-beats",
    async (request, reply) => {
      const body = request.body;
      if (!body?.understanding || !body.requestId?.trim() || !body.target) {
        return reply.code(400).send(error("invalid_body", "缺少图片理解、目标时间或 requestId。", false));
      }
      const offsetDays = body.target.offsetDays;
      if (!Number.isFinite(offsetDays) || offsetDays === undefined) {
        return reply.code(400).send(error("invalid_body", "缺少精确目标天数 (offsetDays)。", false));
      }
      const now = new Date();
      const targetDate = new Date(now.getTime() + offsetDays * 86_400_000);
      const exactTarget: ExactTarget = {
        offsetDays,
        targetDateISO: body.target.targetDateISO ?? targetDate.toISOString().slice(0, 10),
        compactLabel: body.target.compactLabel?.trim() ?? `${Math.abs(offsetDays).toFixed(0)} 天${offsetDays < 0 ? "前" : "后"}`,
      };
      const storyContext = {
        title: body.storyContext?.title ?? "",
        presentTruth: body.storyContext?.presentTruth ?? "",
        identityRules: body.storyContext?.identityRules ?? [],
        canonicalBeats: (body.storyContext?.canonicalBeats ?? []).map((b) => ({
          anchorYears: b.anchorYears ?? 0,
          title: b.title ?? "",
          narrative: b.narrative ?? "",
          visualPrompt: b.visualPrompt ?? "",
        })),
      };
      const result = await writeTargetBeat({
        understanding: body.understanding,
        storyContext,
        target: exactTarget,
        requestId: body.requestId.trim(),
      });
      if (!result.ok) {
        logFailure("story", body.requestId.trim(), result);
        return reply.code(statusFor(result.errorCode)).send(error(result.errorCode, result.userMessage, result.retryable));
      }
      return {
        schemaVersion: "target-beat.v1" as const,
        target: exactTarget,
        targetBeat: result.targetBeat,
      };
    }
  );
}

function normalizeNarrativeAnchor(
  value: { normalizedX?: number; normalizedY?: number } | undefined
): { normalizedX: number; normalizedY: number } | undefined {
  if (
    !Number.isFinite(value?.normalizedX)
    || !Number.isFinite(value?.normalizedY)
  ) {
    return undefined;
  }
  return {
    normalizedX: Math.min(Math.max(value?.normalizedX as number, 0), 1),
    normalizedY: Math.min(Math.max(value?.normalizedY as number, 0), 1),
  };
}

function normalizeOpticalContext(
  value: Partial<CameraObservationPayload> | undefined
): CameraObservationPayload | undefined {
  if (!value) return undefined;
  const allowedLightConditions = new Set([
    "lowLight",
    "balanced",
    "bright",
    "unknown",
  ]);
  const lightCondition = allowedLightConditions.has(value.lightCondition ?? "")
    ? value.lightCondition as CameraObservationPayload["lightCondition"]
    : "unknown";
  const finite = (candidate: number | undefined): number | undefined =>
    Number.isFinite(candidate) ? candidate : undefined;
  return {
    lensPosition: value.lensPosition === "front" || value.lensPosition === "back"
      ? value.lensPosition
      : undefined,
    focusPosition: finite(value.focusPosition),
    exposureDurationSeconds: finite(value.exposureDurationSeconds),
    iso: finite(value.iso),
    exposureTargetOffset: finite(value.exposureTargetOffset),
    zoomFactor: finite(value.zoomFactor),
    lightCondition,
  };
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
