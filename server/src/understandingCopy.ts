import type {
  SceneUnderstandingPayload,
  UnderstandingCopyConstraints,
} from "./types.js";

type ConstraintKey = keyof UnderstandingCopyConstraints;

const bounds: Record<
  ConstraintKey,
  { defaultValue: number; minimum: number; maximum: number }
> = {
  summary: { defaultValue: 80, minimum: 28, maximum: 160 },
  locationType: { defaultValue: 14, minimum: 4, maximum: 28 },
  visualMood: { defaultValue: 40, minimum: 12, maximum: 80 },
  timeClue: { defaultValue: 24, minimum: 8, maximum: 48 },
  changeDriver: { defaultValue: 24, minimum: 8, maximum: 48 },
  subjectName: { defaultValue: 18, minimum: 4, maximum: 36 },
  identityRule: { defaultValue: 48, minimum: 16, maximum: 100 },
};

export function resolveUnderstandingCopyConstraints(
  requested?: Partial<UnderstandingCopyConstraints>
): UnderstandingCopyConstraints {
  return {
    summary: resolve("summary", requested?.summary),
    locationType: resolve("locationType", requested?.locationType),
    visualMood: resolve("visualMood", requested?.visualMood),
    timeClue: resolve("timeClue", requested?.timeClue),
    changeDriver: resolve("changeDriver", requested?.changeDriver),
    subjectName: resolve("subjectName", requested?.subjectName),
    identityRule: resolve("identityRule", requested?.identityRule),
  };
}

export function normalizeSceneUnderstandingCopy(
  value: SceneUnderstandingPayload,
  constraints: UnderstandingCopyConstraints
): SceneUnderstandingPayload {
  return {
    summary: limit(value.summary, constraints.summary),
    locationType: limit(value.locationType, constraints.locationType),
    visualMood: limit(value.visualMood, constraints.visualMood),
    timeClues: value.timeClues
      .slice(0, 8)
      .map((item) => limit(item, constraints.timeClue))
      .filter(Boolean),
    changeDrivers: value.changeDrivers
      .slice(0, 8)
      .map((item) => limit(item, constraints.changeDriver))
      .filter(Boolean),
    subjects: value.subjects.slice(0, 6).map((subject) => ({
      name: limit(subject.name, constraints.subjectName),
      confidence: subject.confidence,
      identityRule: limit(subject.identityRule, constraints.identityRule),
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
