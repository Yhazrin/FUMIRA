import type {
  StoryCopyConstraints,
  TemporalStoryPayload,
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
  visualPrompt: { defaultValue: 140, minimum: 40, maximum: 220 },
};

const beatDeltaLimit = 72;

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
  return {
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
      transitionCause: optionalLimit(beat.transitionCause, beatDeltaLimit),
      unchangedAnchors: beat.unchangedAnchors
        ?.slice(0, 6)
        .map((item) => limit(item, 28))
        .filter(Boolean),
      foregroundDelta: optionalLimit(beat.foregroundDelta, beatDeltaLimit),
      midgroundDelta: optionalLimit(beat.midgroundDelta, beatDeltaLimit),
      backgroundDelta: optionalLimit(beat.backgroundDelta, beatDeltaLimit),
      subjectDelta: optionalLimit(beat.subjectDelta, beatDeltaLimit),
      environmentDelta: optionalLimit(beat.environmentDelta, beatDeltaLimit),
    })),
  };
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

function optionalLimit(value: string | undefined, maximum: number): string | undefined {
  if (!value) return undefined;
  const limited = limit(value, maximum);
  return limited || undefined;
}
