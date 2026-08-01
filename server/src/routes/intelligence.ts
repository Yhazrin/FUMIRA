import type { FastifyInstance } from "fastify";
import { analyzeUploadedAsset, writeTargetBeat, writeTemporalStory } from "../intelligence.js";
import {
  canonicalTimePosition,
  MAXIMUM_TIME_OFFSET_DAYS,
} from "../queue.js";
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
    targetTime?: {
      normalized?: number;
      offsetYears?: number;
      offsetDays?: number;
      compactLabel?: string;
    };
    copyConstraints?: Partial<StoryCopyConstraints>;
    requestId?: string;
  } }>(
    "/v1/stories",
    async (request, reply) => {
      const body = request.body;
      if (!body?.understanding || !body.requestId?.trim() || !body.targetTime) {
        return reply.code(400).send(error("invalid_body", "缺少图片理解、目标年份或 requestId。", false));
      }
      const resolvedTime = resolveExactTime(body.targetTime, {
        requireOffsetYears: true,
        requireCompactLabel: true,
      });
      if (!resolvedTime.ok) {
        return reply.code(400).send(error(
          "invalid_time_position",
          resolvedTime.userMessage,
          false
        ));
      }
      const copyConstraints = resolveStoryCopyConstraints(body.copyConstraints);
      const result = await writeTemporalStory({
        understanding: body.understanding,
        targetTime: resolvedTime.value,
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
    target?: {
      normalized?: number;
      offsetYears?: number;
      offsetDays?: number;
      targetDateISO?: string;
      compactLabel?: string;
    };
    requestId?: string;
  } }>(
    "/v1/target-beats",
    async (request, reply) => {
      const body = request.body;
      if (!body?.understanding || !body.requestId?.trim() || !body.target) {
        return reply.code(400).send(error("invalid_body", "缺少图片理解、目标时间或 requestId。", false));
      }
      const resolvedTime = resolveExactTime(body.target);
      if (!resolvedTime.ok) {
        return reply.code(400).send(error(
          "invalid_time_position",
          resolvedTime.userMessage,
          false
        ));
      }
      const exactTarget = resolvedTime.value;
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

const TIME_POSITION_TOLERANCE_YEARS = 0.001;
const TIME_POSITION_TOLERANCE_NORMALIZED = 1e-9;

type ExactTimeInput = {
  normalized?: number;
  offsetYears?: number;
  offsetDays?: number;
  compactLabel?: string;
};

function resolveExactTime(
  input: ExactTimeInput,
  requirements: {
    requireOffsetYears?: boolean;
    requireCompactLabel?: boolean;
  } = {}
):
  | { ok: true; value: ExactTarget }
  | { ok: false; userMessage: string } {
  if (!Number.isFinite(input.offsetDays)) {
    return { ok: false, userMessage: "缺少精确目标天数 (offsetDays)。" };
  }

  const offsetDays = input.offsetDays as number;
  if (Math.abs(offsetDays) > MAXIMUM_TIME_OFFSET_DAYS) {
    return { ok: false, userMessage: "时间超出可生成的前后一百年范围。" };
  }

  const canonical = canonicalTimePosition(offsetDays);
  if (
    requirements.requireOffsetYears
    && !Number.isFinite(input.offsetYears)
  ) {
    return { ok: false, userMessage: "缺少目标年份 (offsetYears)。" };
  }
  if (
    input.offsetYears !== undefined
    && (
      !Number.isFinite(input.offsetYears)
      || Math.abs(input.offsetYears - canonical.offsetYears)
        > TIME_POSITION_TOLERANCE_YEARS
    )
  ) {
    return { ok: false, userMessage: "目标时间字段彼此不一致。" };
  }
  if (
    input.normalized !== undefined
    && (
      !Number.isFinite(input.normalized)
      || Math.abs(input.normalized - canonical.normalized)
        > TIME_POSITION_TOLERANCE_NORMALIZED
    )
  ) {
    return { ok: false, userMessage: "目标时间字段彼此不一致。" };
  }

  const compactLabel = input.compactLabel?.trim();
  if (requirements.requireCompactLabel && !compactLabel) {
    return { ok: false, userMessage: "缺少目标时间标签 (compactLabel)。" };
  }
  if (compactLabel !== undefined && compactLabel !== canonical.compactLabel) {
    return { ok: false, userMessage: "目标时间字段彼此不一致。" };
  }

  return {
    ok: true,
    value: {
      offsetDays: canonical.offsetDays,
      targetDateISO: canonical.targetDateISO,
      compactLabel: canonical.compactLabel,
    },
  };
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
