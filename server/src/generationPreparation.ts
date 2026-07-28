import {
  analyzeUploadedSceneGraph,
  planTemporalRender,
} from "./intelligence.js";
import { createGenerationJob } from "./queue.js";
import {
  defaultQualityPolicy,
  deriveSceneGraphFromV2,
} from "./temporalV3.js";
import type {
  CreateGenerationBody,
  ExactTarget,
  StoryContinuityContext,
  StructuredGenerationBodyV2,
  StructuredGenerationBodyV3,
  SubjectContinuityMode,
} from "./types.js";

/**
 * Upgrade current iOS generation.v2 requests before queueing. Existing clients
 * keep their stable contract, while the server performs full source-image scene
 * decomposition and exact temporal planning before image generation.
 */
export async function prepareAndCreateGenerationJob(body: CreateGenerationBody) {
  if (body.contextVersion !== "generation.v2") {
    return createGenerationJob(body);
  }

  const v2 = body as StructuredGenerationBodyV2;
  if (
    !v2.structuredContext?.understanding
    || !v2.structuredContext?.story?.targetBeat
    || !v2.timePosition
    || !Number.isFinite(v2.timePosition.offsetDays)
  ) {
    return createGenerationJob(body);
  }

  const graphResult = await analyzeUploadedSceneGraph({
    sourceAssetId: v2.sourceAssetId,
    requestId: `${v2.requestId}-source-scene`,
  });
  const sceneGraph = graphResult.ok
    ? graphResult.value
    : deriveSceneGraphFromV2(v2.structuredContext.understanding);

  const exactTarget = exactTargetFromTime(
    v2.timePosition.offsetDays,
    v2.timePosition.compactLabel
  );
  const storyContext: StoryContinuityContext = {
    title: v2.structuredContext.story.title,
    presentTruth: v2.structuredContext.story.presentTruth,
    identityRules: v2.structuredContext.story.identityRules,
    canonicalBeats: v2.structuredContext.story.beats.map((beat) => ({
      anchorYears: beat.anchorYears,
      title: beat.title,
      narrative: beat.narrative,
      visualPrompt: beat.visualPrompt,
    })),
  };

  const planned = await planTemporalRender({
    sceneGraph,
    exactTarget,
    storyContext,
    requestId: `${v2.requestId}-render-plan`,
  });
  if (!planned.ok) {
    // Direct V2 queueing still performs a deterministic V3 conversion, so a
    // planner outage never restores the old flat visualPrompt behavior.
    return createGenerationJob(body);
  }

  const upgraded: StructuredGenerationBodyV3 = {
    contextVersion: "generation.v3",
    sourceAssetId: v2.sourceAssetId,
    timePosition: v2.timePosition,
    aspectRatio: v2.aspectRatio,
    requestId: v2.requestId,
    useSubjectReference: allowSubjectReference(
      Boolean(v2.useSubjectReference),
      planned.value.subjectContinuityMode
    ),
    structuredContext: {
      schemaVersion: "generation-context.v3",
      sceneGraph,
      targetPlan: planned.value,
      temporalStory: v2.structuredContext.story,
      generationMode: v2.structuredContext.generationMode,
      qualityPolicy: defaultQualityPolicy(),
    },
  };
  return createGenerationJob(upgraded);
}

function allowSubjectReference(
  requested: boolean,
  mode: SubjectContinuityMode
): boolean {
  if (!requested) return false;
  return mode === "identity_persists"
    || mode === "age_progression"
    || mode === "object_remains"
    || mode === "time_traveler";
}

function exactTargetFromTime(offsetDays: number, compactLabel: string): ExactTarget {
  const now = new Date();
  const targetDate = new Date(now.getTime() + offsetDays * 86_400_000);
  return {
    offsetDays,
    targetDateISO: targetDate.toISOString().slice(0, 10),
    compactLabel: compactLabel || `${Math.abs(offsetDays).toFixed(0)} 天${offsetDays < 0 ? "前" : "后"}`,
  };
}
