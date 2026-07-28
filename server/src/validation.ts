/**
 * Post-generation validation skeleton.
 * Full auto-repair redraw is intentionally deferred; queue/process can call
 * `shouldAttemptRepair` once a VLM validator is wired.
 */

export interface GenerationValidationResult {
  cameraConsistency: number;
  anchorPreservation: number;
  identityConsistency: number;
  temporalCoverage: number;
  environmentEvolution: number;
  eraCoherence: number;
  storyAlignment: number;
  unexplainedAdditions: string[];
  missedRequiredChanges: string[];
  problems: string[];
  repairInstructions: string[];
  shouldRegenerate: boolean;
}

export const DEFAULT_REPAIR_INSTRUCTION =
  "上一结果的时间变化过度集中在人物或单个物体。保持当前构图与身份锚点，重新生成，并将符合目标年代的变化协调分布到可见的前景、中景、背景、材料、植被、设施和使用痕迹中。不要增加无关、抢镜或缺乏时间因果依据的主体。";

export function buildValidationPrompt(params: {
  targetLabel: string;
  offsetYears: number;
}): string {
  return [
    `Compare the SOURCE photograph with the GENERATED target-time result at ${params.targetLabel} (${params.offsetYears.toFixed(2)} years).`,
    "Return JSON only with this exact shape:",
    '{"cameraConsistency":0.0,"anchorPreservation":0.0,"identityConsistency":0.0,"temporalCoverage":0.0,"environmentEvolution":0.0,"eraCoherence":0.0,"storyAlignment":0.0,"unexplainedAdditions":[""],"missedRequiredChanges":[""],"problems":[""],"repairInstructions":[""],"shouldRegenerate":false}',
    "Score each metric from 0 to 1. environmentEvolution measures whether planned non-subject regions actually evolved. Fail temporalCoverage or eraCoherence when time evidence is concentrated on one person/object, or when depth layers belong to different eras.",
    "Compare against every required render-plan region. List arbitrary additions and missed required changes explicitly.",
    "repairInstructions must be concise Simplified Chinese actionable edits. Prefer shouldRegenerate=true when temporalCoverage, environmentEvolution or eraCoherence < 0.55.",
  ].join(" ");
}

export function shouldAttemptRepair(
  result: Pick<
    GenerationValidationResult,
    "temporalCoverage" | "environmentEvolution" | "eraCoherence" | "shouldRegenerate"
  >
): boolean {
  if (result.shouldRegenerate) return true;
  return result.temporalCoverage < 0.55
    || result.environmentEvolution < 0.55
    || result.eraCoherence < 0.55;
}

/** Parse loosely; returns null when required numeric fields are missing. */
export function parseValidationResponse(raw: unknown): GenerationValidationResult | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const value = raw as Record<string, unknown>;
  const cameraConsistency = number01(value.cameraConsistency);
  const anchorPreservation = number01(value.anchorPreservation);
  const identityConsistency = number01(value.identityConsistency);
  const temporalCoverage = number01(value.temporalCoverage);
  const environmentEvolution = number01(value.environmentEvolution);
  const eraCoherence = number01(value.eraCoherence);
  const storyAlignment = number01(value.storyAlignment);
  if (
    cameraConsistency === null
    || anchorPreservation === null
    || identityConsistency === null
    || temporalCoverage === null
    || environmentEvolution === null
    || eraCoherence === null
    || storyAlignment === null
  ) {
    return null;
  }
  const problems = stringList(value.problems);
  const repairInstructions = stringList(value.repairInstructions);
  const unexplainedAdditions = stringList(value.unexplainedAdditions);
  const missedRequiredChanges = stringList(value.missedRequiredChanges);
  const shouldRegenerate = typeof value.shouldRegenerate === "boolean"
    ? value.shouldRegenerate
    : temporalCoverage < 0.55
      || environmentEvolution < 0.55
      || eraCoherence < 0.55;
  return {
    cameraConsistency,
    anchorPreservation,
    identityConsistency,
    temporalCoverage,
    environmentEvolution,
    eraCoherence,
    storyAlignment,
    unexplainedAdditions,
    missedRequiredChanges,
    problems,
    repairInstructions: repairInstructions.length
      ? repairInstructions
      : shouldRegenerate
        ? [DEFAULT_REPAIR_INSTRUCTION]
        : [],
    shouldRegenerate,
  };
}

function number01(value: unknown): number | null {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string"
      ? Number(value)
      : Number.NaN;
  if (!Number.isFinite(parsed)) return null;
  return Math.min(1, Math.max(0, parsed));
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter(Boolean)
    .slice(0, 8);
}
