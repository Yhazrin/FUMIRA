import { planTemporalRender } from "./intelligence.js";
import { createGenerationJob } from "./queue.js";
import { defaultQualityPolicy, deriveSceneGraphFromV2 } from "./temporalV3.js";
import type {
  CreateGenerationBody,
  ExactTarget,
  StoryContinuityContext,
  StructuredGenerationBodyV2,
  StructuredGenerationBodyV3,
} from "./types.js";

/**
 * Upgrade current iOS generation.v2 requests before queueing. The client keeps
 * its stable contract, while the server obtains a full SceneGraph and an exact
 * machine-facing TemporalRenderPlan from the V3 planner. Direct queue callers
 * still retain the deterministic compatibility fallback.
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

  const sceneGraph = deriveSceneGraphFromV2(v2.structuredContext.understanding);
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
    // The queue's deterministic V2 converter remains a safe degradation path.
    return createGenerationJob(body);
  }

  const upgraded: StructuredGenerationBodyV3 = {
    contextVersion: "generation.v3",
    sourceAssetId: v2.sourceAssetId,
    timePosition: v2.timePosition,
    aspectRatio: v2.aspectRatio,
    requestId: v2.requestId,
    useSubjectReference: v2.useSubjectReference,
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

function exactTargetFromTime(offsetDays: number, compactLabel: string): ExactTarget {
  const now = new Date();
  const targetDate = new Date(now.getTime() + offsetDays * 86_400_000);
  return {
    offsetDays,
    targetDateISO: targetDate.toISOString().slice(0, 10),
    compactLabel: compactLabel || `${Math.abs(offsetDays).toFixed(0)} 天${offsetDays < 0 ? "前" : "后"}`,
  };
}
