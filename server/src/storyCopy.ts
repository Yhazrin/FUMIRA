import type {
  StoryCopyConstraints,
  TemporalStoryPayload,
  TemporalStoryPayloadV2,
} from "./types.js";

export const DEFAULT_STORY_COPY_CONSTRAINTS: StoryCopyConstraints = {
  title: 16,
  logline: 56,
  presentTruth: 72,
  identityRule: 48,
  beatTitle: 14,
  beatNarrative: 72,
  visualPrompt: 180,
};

export function resolveStoryCopyConstraints(
  partial: Partial<StoryCopyConstraints> | undefined
): StoryCopyConstraints {
  return {
    title: clamp(partial?.title, 8, 30, DEFAULT_STORY_COPY_CONSTRAINTS.title),
    logline: clamp(partial?.logline, 24, 100, DEFAULT_STORY_COPY_CONSTRAINTS.logline),
    presentTruth: clamp(partial?.presentTruth, 36, 120, DEFAULT_STORY_COPY_CONSTRAINTS.presentTruth),
    identityRule: clamp(partial?.identityRule, 24, 80, DEFAULT_STORY_COPY_CONSTRAINTS.identityRule),
    beatTitle: clamp(partial?.beatTitle, 8, 28, DEFAULT_STORY_COPY_CONSTRAINTS.beatTitle),
    beatNarrative: clamp(partial?.beatNarrative, 36, 130, DEFAULT_STORY_COPY_CONSTRAINTS.beatNarrative),
    visualPrompt: clamp(partial?.visualPrompt, 110, 360, DEFAULT_STORY_COPY_CONSTRAINTS.visualPrompt),
  };
}

export function normalizeTemporalStoryCopy(
  payload: TemporalStoryPayload,
  constraints: StoryCopyConstraints
): TemporalStoryPayload {
  return {
    title: trim(payload.title, constraints.title),
    logline: trim(payload.logline, constraints.logline),
    presentTruth: trim(payload.presentTruth, constraints.presentTruth),
    identityRules: payload.identityRules
      .filter(Boolean)
      .slice(0, 16)
      .map((rule) => trim(rule, constraints.identityRule)),
    beats: payload.beats.slice(0, 7).map((beat) => ({
      anchorYears: beat.anchorYears,
      title: trim(beat.title, constraints.beatTitle),
      narrative: trim(beat.narrative, constraints.beatNarrative),
      visualPrompt: trim(beat.visualPrompt, constraints.visualPrompt),
    })),
    ...(payload.targetBeat
      ? {
          targetBeat: {
            anchorYears: payload.targetBeat.anchorYears,
            title: trim(payload.targetBeat.title, constraints.beatTitle),
            narrative: trim(payload.targetBeat.narrative, constraints.beatNarrative),
            visualPrompt: trim(payload.targetBeat.visualPrompt, constraints.visualPrompt),
            ...(payload.targetBeat.exactTarget
              ? { exactTarget: payload.targetBeat.exactTarget }
              : {}),
          },
        }
      : {}),
  };
}

/** Missing exact target nodes are rejected instead of substituted. */
export function promoteToV2(
  payload: TemporalStoryPayload,
  expectedTargetYears: number,
  constraints: StoryCopyConstraints
): TemporalStoryPayloadV2 {
  const normalized = normalizeTemporalStoryCopy(payload, constraints);
  if (!normalized.targetBeat) {
    throw new Error("missing_exact_target_beat");
  }
  return {
    schemaVersion: "temporal-story.v2",
    title: normalized.title,
    logline: normalized.logline,
    presentTruth: normalized.presentTruth,
    identityRules: normalized.identityRules,
    beats: normalized.beats,
    targetBeat: {
      ...normalized.targetBeat,
      anchorYears: expectedTargetYears,
    },
  };
}

function clamp(value: number | undefined, min: number, max: number, fallback: number): number {
  if (!Number.isFinite(value)) return fallback;
  return Math.max(min, Math.min(max, Math.round(value as number)));
}

function trim(value: string, max: number): string {
  const clean = String(value ?? "").replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  return clean.slice(0, max).trimEnd();
}
