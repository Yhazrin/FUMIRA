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
      ...(beat.exactTarget ? { exactTarget: beat.exactTarget } : {}),
    })),
  };

  if (story.targetBeat) {
    normalized.targetBeat = {
      anchorYears: story.targetBeat.anchorYears,
      title: limit(story.targetBeat.title, constraints.beatTitle),
      narrative: limit(story.targetBeat.narrative, constraints.beatNarrative),
      visualPrompt: limit(story.targetBeat.visualPrompt, constraints.visualPrompt),
      ...(story.targetBeat.exactTarget
        ? { exactTarget: story.targetBeat.exactTarget }
        : {}),
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
 * Promote a validated temporal story into generation.v2.
 *
 * V2 requires a model-produced exact target beat. Using a nearby canonical
 * browsing beat would silently render the wrong year, so this function is
 * deliberately strict and never fabricates a fallback.
 */
export function promoteToV2(
  story: TemporalStoryPayload,
  targetOffsetYears: number,
  constraints: StoryCopyConstraints
): TemporalStoryPayloadV2 {
  if (!story.targetBeat) {
    throw new Error("missing_exact_target_beat");
  }

  const normalized = normalizeTemporalStoryCopy(story, constraints);
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
      // Time identity is program-authoritative even when the model rounds it.
      anchorYears: targetOffsetYears,
    },
  };
}
