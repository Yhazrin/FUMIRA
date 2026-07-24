import type {
  StoryCopyConstraints,
  TemporalStoryPayload,
  TemporalStoryPayloadV2,
} from "./types.js";

type ConstraintKey = keyof StoryCopyConstraints;

const bounds: Record<
  ConstraintKey,
  { defaultValue: number; minimum: number; maximum: number }
> = {
  title: { defaultValue: 16, minimum: 6, maximum: 32 },
  logline: { defaultValue: 56, minimum: 20, maximum: 120 },
  presentTruth: { defaultValue: 72, minimum: 24, maximum: 140 },
  identityRule: { defaultValue: 48, minimum: 16, maximum: 100 },
  beatTitle: { defaultValue: 14, minimum: 4, maximum: 28 },
  beatNarrative: { defaultValue: 72, minimum: 24, maximum: 140 },
  visualPrompt: { defaultValue: 110, minimum: 40, maximum: 180 },
};

export function resolveStoryCopyConstraints(
  requested?: Partial<StoryCopyConstraints>
): StoryCopyConstraints {
  return {
    title: resolve("title", requested?.title),
    logline: resolve("logline", requested?.logline),
    presentTruth: resolve("presentTruth", requested?.presentTruth),
    identityRule: resolve("identityRule", requested?.identityRule),
    beatTitle: resolve("beatTitle", requested?.beatTitle),
    beatNarrative: resolve("beatNarrative", requested?.beatNarrative),
    visualPrompt: resolve("visualPrompt", requested?.visualPrompt),
  };
}

export function normalizeTemporalStoryCopy(
  story: TemporalStoryPayload,
  constraints: StoryCopyConstraints
): TemporalStoryPayload {
  const normalized: TemporalStoryPayload = {
    title: limit(story.title, constraints.title),
    logline: limit(story.logline, constraints.logline),
    presentTruth: limit(story.presentTruth, constraints.presentTruth),
    identityRules: story.identityRules
      .slice(0, 8)
      .map((rule) => limit(rule, constraints.identityRule))
      .filter(Boolean),
    beats: story.beats.map((beat) => ({
      anchorYears: beat.anchorYears,
      title: limit(beat.title, constraints.beatTitle),
      narrative: limit(beat.narrative, constraints.beatNarrative),
      visualPrompt: limit(beat.visualPrompt, constraints.visualPrompt),
    })),
  };

  if (story.targetBeat) {
    normalized.targetBeat = {
      anchorYears: story.targetBeat.anchorYears,
      title: limit(story.targetBeat.title, constraints.beatTitle),
      narrative: limit(story.targetBeat.narrative, constraints.beatNarrative),
      visualPrompt: limit(story.targetBeat.visualPrompt, constraints.visualPrompt),
    };
  }

  return normalized;
}

function resolve(key: ConstraintKey, requested: unknown): number {
  const rule = bounds[key];
  if (typeof requested !== "number" || !Number.isFinite(requested)) {
    return rule.defaultValue;
  }
  return Math.min(rule.maximum, Math.max(rule.minimum, Math.round(requested)));
}

function limit(value: string, maximum: number): string {
  const normalized = value.trim().replace(/\s+/g, " ");
  const characters = Array.from(normalized);
  if (characters.length <= maximum) return normalized;
  if (maximum <= 1) return characters.slice(0, maximum).join("");
  return `${characters.slice(0, maximum - 1).join("")}…`;
}

/**
 * Promote a V1 TemporalStoryPayload (optional targetBeat) to V2 (required).
 * If targetBeat is missing, uses the nearest canonical beat — but only for
 * the adapter layer. The validation layer should reject this and require
 * the model to produce a real targetBeat.
 */
export function promoteToV2(
  story: TemporalStoryPayload,
  targetOffsetYears: number,
  constraints: StoryCopyConstraints
): TemporalStoryPayloadV2 {
  const targetBeat = story.targetBeat ?? nearestBeat(story.beats, targetOffsetYears);
  const normalized = normalizeTemporalStoryCopy(story, constraints);
  return {
    schemaVersion: "temporal-story.v2",
    title: normalized.title,
    logline: normalized.logline,
    presentTruth: normalized.presentTruth,
    identityRules: normalized.identityRules,
    beats: normalized.beats,
    targetBeat: {
      anchorYears: targetBeat.anchorYears,
      title: limit(targetBeat.title, constraints.beatTitle),
      narrative: limit(targetBeat.narrative, constraints.beatNarrative),
      visualPrompt: limit(targetBeat.visualPrompt, constraints.visualPrompt),
    },
  };
}

function nearestBeat(
  beats: TemporalStoryPayload["beats"],
  offsetYears: number
) {
  if (!beats.length) {
    return { anchorYears: offsetYears, title: "", narrative: "", visualPrompt: "" };
  }
  return beats.reduce((best, beat) =>
    Math.abs(beat.anchorYears - offsetYears) < Math.abs(best.anchorYears - offsetYears)
      ? beat
      : best
  );
}
