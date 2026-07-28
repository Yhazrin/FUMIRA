import type { FastifyInstance } from "fastify";
import {
  analyzeUploadedAsset,
  analyzeUploadedSceneGraph,
  planTemporalRender,
  writeTargetBeat,
  writeTemporalStory,
} from "../intelligence.js";
import { resolveStoryCopyConstraints } from "../storyCopy.js";
import { resolveUnderstandingCopyConstraints } from "../understandingCopy.js";
import type {
  ExactTarget,
  SceneGraph,
  SceneUnderstandingPayload,
  StoryContinuityContext,
  StoryCopyConstraints,
  SubjectContinuityMode,
  UnderstandingCopyConstraints,
} from "../types.js";

const CONTINUITY_MODES = new Set<SubjectContinuityMode>([
  "identity_persists",
  "age_progression",
  "lineage_or_successor",
  "object_remains",
  "site_only",
  "time_traveler",
]);

export async function registerIntelligenceRoutes(app: FastifyInstance): Promise<void> {
  app.post<{ Body: {
    sourceAssetId?: string;
    copyConstraints?: Partial<UnderstandingCopyConstraints>;
    requestId?: string;
  } }>(
    "/v1/understand",
    async (request, reply) => {
      const body = request.body;
      if (!body?.sourceAssetId || !body.requestId?.trim()) {
        return reply.code(400).send(error("invalid_body", "缺少图片或 requestId。", false));
      }
      const copyConstraints = resolveUnderstandingCopyConstraints(body.copyConstraints);
      const result = await analyzeUploadedAsset({
        sourceAssetId: body.sourceAssetId,
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

  app.post<{ Body: { sourceAssetId?: string; requestId?: string } }>(
    "/v1/scene-graphs",
    async (request, reply) => {
      const body = request.body;
      if (!body?.sourceAssetId || !body.requestId?.trim()) {
        return reply.code(400).send(error("invalid_body", "缺少图片或 requestId。", false));
      }
      const result = await analyzeUploadedSceneGraph({
        sourceAssetId: body.sourceAssetId,
        requestId: body.requestId.trim(),
      });
      if (!result.ok) {
        logFailure("scene_graph", body.requestId.trim(), result);
        return reply.code(statusFor(result.errorCode)).send(error(result.errorCode, result.userMessage, result.retryable));
      }
      return {
        schemaVersion: "scene-graph-response.v1" as const,
        requestId: body.requestId.trim(),
        derivedFromV2: result.derivedFromV2,
        sceneGraph: result.value,
      };
    }
  );

  app.post<{ Body: {
    sceneGraph?: SceneGraph;
    target?: {
      offsetDays?: number;
      targetDateISO?: string;
      compactLabel?: string;
      sourceDateISO?: string;
    };
    storyContext?: Partial<StoryContinuityContext>;
    continuityMode?: SubjectContinuityMode;
    requestId?: string;
  } }>(
    "/v1/render-plans",
    async (request, reply) => {
      const body = request.body;
      if (!body?.sceneGraph || !body.requestId?.trim() || !Number.isFinite(body.target?.offsetDays)) {
        return reply.code(400).send(error("invalid_body", "缺少场景图、精确目标时间或 requestId。", false));
      }
      if (body.continuityMode && !CONTINUITY_MODES.has(body.continuityMode)) {
        return reply.code(400).send(error("invalid_continuity_mode", "主体连续性模式无效。", false));
      }
      const exactTarget = resolveExactTarget(body.target!);
      const result = await planTemporalRender({
        sceneGraph: body.sceneGraph,
        exactTarget,
        storyContext: normalizeStoryContext(body.storyContext),
        continuityMode: body.continuityMode,
        requestId: body.requestId.trim(),
      });
      if (!result.ok) {
        logFailure("render_plan", body.requestId.trim(), result);
        return reply.code(statusFor(result.errorCode)).send(error(result.errorCode, result.userMessage, result.retryable));
      }
      return {
        schemaVersion: "render-plan-response.v1" as const,
        requestId: body.requestId.trim(),
        deterministicFallback: result.deterministicFallback,
        targetPlan: result.value,
      };
    }
  );

  app.post<{ Body: {
    understanding?: SceneUnderstandingPayload;
    targetTime?: {
      offsetYears?: number;
      offsetDays?: number;
      compactLabel?: string;
      sourceDateISO?: string;
    };
    copyConstraints?: Partial<StoryCopyConstraints>;
    requestId?: string;
  } }>(
    "/v1/stories",
    async (request, reply) => {
      const body = request.body;
      if (
        !body?.understanding
        || !body.requestId?.trim()
        || !Number.isFinite(body.targetTime?.offsetYears)
        || !body.targetTime?.compactLabel?.trim()
      ) {
        return reply.code(400).send(error("invalid_body", "缺少图片理解、目标年份或 requestId。", false));
      }
      const copyConstraints = resolveStoryCopyConstraints(body.copyConstraints);
      const offsetDays = body.targetTime.offsetDays
        ?? (body.targetTime.offsetYears as number) * 365.25;
      const exactTarget = resolveExactTarget({
        offsetDays,
        compactLabel: body.targetTime.compactLabel,
        sourceDateISO: body.targetTime.sourceDateISO,
      });
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
    storyContext?: Partial<StoryContinuityContext>;
    target?: {
      offsetDays?: number;
      targetDateISO?: string;
      compactLabel?: string;
      sourceDateISO?: string;
    };
    requestId?: string;
  } }>(
    "/v1/target-beats",
    async (request, reply) => {
      const body = request.body;
      if (!body?.understanding || !body.requestId?.trim() || !Number.isFinite(body.target?.offsetDays)) {
        return reply.code(400).send(error("invalid_body", "缺少图片理解、目标时间或 requestId。", false));
      }
      const exactTarget = resolveExactTarget(body.target!);
      const result = await writeTargetBeat({
        understanding: body.understanding,
        storyContext: normalizeStoryContext(body.storyContext) ?? emptyStoryContext(),
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

function resolveExactTarget(target: {
  offsetDays?: number;
  targetDateISO?: string;
  compactLabel?: string;
  sourceDateISO?: string;
}): ExactTarget {
  const offsetDays = target.offsetDays as number;
  const explicitTarget = parseISODate(target.targetDateISO);
  const sourceDate = parseISODate(target.sourceDateISO) ?? new Date();
  const calculated = new Date(sourceDate.getTime() + offsetDays * 86_400_000);
  return {
    offsetDays,
    targetDateISO: explicitTarget
      ? explicitTarget.toISOString().slice(0, 10)
      : calculated.toISOString().slice(0, 10),
    compactLabel: target.compactLabel?.trim()
      || `${Math.abs(offsetDays).toFixed(0)} 天${offsetDays < 0 ? "前" : "后"}`,
  };
}

function parseISODate(value: string | undefined): Date | undefined {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return undefined;
  const date = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(date.getTime()) ? date : undefined;
}

function normalizeStoryContext(
  input: Partial<StoryContinuityContext> | undefined
): StoryContinuityContext | undefined {
  if (!input) return undefined;
  return {
    title: input.title ?? "",
    presentTruth: input.presentTruth ?? "",
    identityRules: Array.isArray(input.identityRules)
      ? input.identityRules.filter((item): item is string => typeof item === "string")
      : [],
    canonicalBeats: Array.isArray(input.canonicalBeats)
      ? input.canonicalBeats.map((beat) => ({
          anchorYears: Number.isFinite(beat?.anchorYears) ? beat.anchorYears as number : 0,
          title: beat?.title ?? "",
          narrative: beat?.narrative ?? "",
          visualPrompt: beat?.visualPrompt ?? "",
        }))
      : [],
  };
}

function emptyStoryContext(): StoryContinuityContext {
  return { title: "", presentTruth: "", identityRules: [], canonicalBeats: [] };
}

function error(errorCode: string, userMessage: string, retryable: boolean) {
  return { errorCode, userMessage, retryable };
}

function statusFor(errorCode: string): number {
  if (
    errorCode === "invalid_source_asset"
    || errorCode === "invalid_image"
    || errorCode === "invalid_ai_response"
  ) return 400;
  if (
    errorCode === "understanding_unavailable"
    || errorCode === "scene_graph_unavailable"
    || errorCode === "temporal_planner_unavailable"
    || errorCode === "story_unavailable"
    || errorCode === "vision_credentials_required"
  ) return 503;
  return 502;
}

function logFailure(
  stage: "understanding" | "scene_graph" | "render_plan" | "story",
  requestId: string,
  result: { errorCode: string; retryable: boolean; statusMsg?: string }
) {
  console.info(JSON.stringify({
    event: "intelligence_failed",
    stage,
    requestId,
    errorCode: result.errorCode,
    retryable: result.retryable,
    providerMessage: result.statusMsg?.slice(0, 160),
  }));
}
