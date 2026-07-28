import { createHash } from "node:crypto";
import { config } from "./config.js";
import type { CompiledPrompt } from "./promptCompiler.js";
import type {
  AspectRatio,
  GenerationContextV3,
  RegionTemporalChange,
  SceneGraph,
  SceneRegion,
  TemporalRenderPlan,
  TimePositionPayload,
  VisualCriticResult,
} from "./types.js";

const VERSION = "v3";
const TOTAL_BUDGET = config.promptMaxChars;

interface PromptSection {
  id: string;
  text: string;
  required: boolean;
}

export function compilePromptV3(input: {
  context: GenerationContextV3;
  timePosition: TimePositionPayload;
  aspectRatio: AspectRatio;
}): CompiledPrompt {
  const { context, timePosition, aspectRatio } = input;
  const graph = context.sceneGraph;
  const plan = context.targetPlan;

  const fixedSections = buildFixedSections(graph, plan, timePosition, aspectRatio);
  const regionSection = buildRegionSection(graph, plan, fixedSections);
  const optionalSections = buildOptionalSections(graph, plan);

  const included: PromptSection[] = [...fixedSections.slice(0, 3), regionSection];
  for (const section of fixedSections.slice(3)) included.push(section);

  for (const optional of optionalSections) {
    const candidate = renderSections([...included, optional]);
    if (candidate.length <= TOTAL_BUDGET) included.push(optional);
  }

  let prompt = renderSections(included);
  if (prompt.length > TOTAL_BUDGET) {
    prompt = emergencyPrompt(graph, plan, timePosition, aspectRatio);
  }
  if (prompt.length > TOTAL_BUDGET) {
    throw new Error("prompt_v3_required_contract_exceeds_budget");
  }

  const sectionCharCounts: Record<string, number> = {};
  for (const section of [...fixedSections, regionSection, ...optionalSections]) {
    const rendered = included.find((item) => item.id === section.id);
    sectionCharCounts[section.id] = rendered?.text.length ?? 0;
  }
  const truncatedSections = [...fixedSections, regionSection, ...optionalSections]
    .filter((section) => !included.some((item) => item.id === section.id) || included.find((item) => item.id === section.id)?.text !== section.text)
    .map((section) => section.id);

  return {
    prompt,
    version: VERSION,
    hash: createHash("sha256").update(prompt).digest("hex").slice(0, 16),
    charCount: prompt.length,
    truncated: truncatedSections.length > 0,
    sectionCharCounts,
    truncatedSections,
  };
}

export function buildCorrectionPromptV3(input: {
  originalPrompt: string;
  graph: SceneGraph;
  plan: TemporalRenderPlan;
  critic: VisualCriticResult;
}): string {
  const missing = input.critic.missedRegionChanges
    .map((id) => input.plan.regionChanges.find((change) => change.regionId === id))
    .filter((change): change is RegionTemporalChange => Boolean(change));

  const correctionLines = [
    "CORRECTION PASS",
    "Keep every successful camera, topology and principal-identity property from the first attempt.",
  ];
  if (input.critic.cameraDrift.length) {
    correctionLines.push(`Restore camera geometry: ${clip(input.critic.cameraDrift.join("; "), 180)}.`);
  }
  for (const change of missing.slice(0, 8)) {
    const region = input.graph.regions.find((item) => item.id === change.regionId);
    correctionLines.push(formatChange(region, change, 130));
  }
  if (!missing.length && input.critic.correctionInstruction) {
    correctionLines.push(clip(input.critic.correctionInstruction, 360));
  }
  correctionLines.push(
    "Do not alter already-correct regions merely to create novelty.",
    "Do not solve missing environmental evolution by changing only the main person, applying a filter, or moving the camera."
  );

  const correction = correctionLines.join("\n");
  const reserve = correction.length + 2;
  const baseBudget = Math.max(0, TOTAL_BUDGET - reserve);
  const base = input.originalPrompt.slice(0, baseBudget).trimEnd();
  return `${base}\n\n${correction}`.slice(0, TOTAL_BUDGET);
}

function buildFixedSections(
  graph: SceneGraph,
  plan: TemporalRenderPlan,
  timePosition: TimePositionPayload,
  aspectRatio: AspectRatio
): PromptSection[] {
  const camera = graph.camera;
  return [
    {
      id: "target",
      required: true,
      text: [
        "TARGET",
        `${plan.exactTarget.compactLabel}; exact date ${plan.exactTarget.targetDateISO}; offset ${(timePosition.offsetDays / 365.25).toFixed(2)} years; aspect ${aspectRatio}.`,
        `Render plan ${plan.planId}. Same viewpoint, one coherent target world.`,
      ].join("\n"),
    },
    {
      id: "camera",
      required: true,
      text: [
        "CAMERA LOCK",
        clip(`${camera.viewpoint}; ${camera.framing}; ${camera.horizon}; ${camera.perspective}; ${camera.depthLayout}`, 260),
        "Preserve screen coordinates, vanishing points, scale, occlusion order and edge crop of persistent anchors.",
      ].join("\n"),
    },
    {
      id: "continuity",
      required: true,
      text: [
        "CONTINUITY",
        `Mode: ${plan.subjectContinuityMode}. Preserve identity only where this mode and the region policy require it; do not freeze transient entities.`,
      ].join("\n"),
    },
    {
      id: "coherence",
      required: true,
      text: [
        "WORLD COHERENCE",
        clip(`${plan.globalWorldState.eraSummary}; ${plan.globalWorldState.environmentalState}; ${plan.globalWorldState.technologyState}; ${plan.globalWorldState.humanActivityState}`, 300),
        "Every changed region must share one era, light direction, weather, material logic, perspective and causal history.",
      ].join("\n"),
    },
    {
      id: "prohibited",
      required: true,
      text: [
        "PROHIBITED",
        "No camera drift, reframing, identity replacement, arbitrary objects, invented readable text, uniform material aging, generic vintage filter, neon cyberpunk, or subject-only transformation.",
        clip(plan.prohibitedDrift.join("; "), 260),
      ].join("\n"),
    },
  ];
}

function buildRegionSection(
  graph: SceneGraph,
  plan: TemporalRenderPlan,
  fixed: PromptSection[]
): PromptSection {
  const header = "REGION EDITS\n";
  const fixedLength = renderSections(fixed).length + 2;
  const unchanged = plan.unchangedRegionIds.length
    ? `UNCHANGED ${plan.unchangedRegionIds.join(",")}: explicitly preserve source state and spatial role.\n`
    : "";
  const reserved = fixedLength + header.length + unchanged.length;
  let remaining = Math.max(120, TOTAL_BUDGET - reserved);
  const ordered = [...plan.regionChanges].sort((a, b) => {
    const ar = graph.regions.find((region) => region.id === a.regionId)?.salience ?? 0;
    const br = graph.regions.find((region) => region.id === b.regionId)?.salience ?? 0;
    return br - ar;
  });

  const lines: string[] = [];
  for (const change of ordered) {
    const region = graph.regions.find((item) => item.id === change.regionId);
    const full = formatChange(region, change, 190);
    const compact = formatChange(region, change, 78);
    const line = full.length + 1 <= remaining ? full : compact;
    if (line.length + 1 > remaining) {
      const fallback = `${change.regionId} ${change.action.toUpperCase()}: apply planned target state.`;
      if (fallback.length + 1 <= remaining) {
        lines.push(fallback);
        remaining -= fallback.length + 1;
      }
      continue;
    }
    lines.push(line);
    remaining -= line.length + 1;
  }

  if (!lines.length) lines.push("No local edit may replace the required world-state transformation.");
  return {
    id: "regionEdits",
    required: true,
    text: `${header}${lines.join("\n")}\n${unchanged}`.trimEnd(),
  };
}

function buildOptionalSections(graph: SceneGraph, plan: TemporalRenderPlan): PromptSection[] {
  const sections: PromptSection[] = [];
  if (plan.crossRegionCouplings.length) {
    sections.push({
      id: "couplings",
      required: false,
      text: [
        "CROSS-REGION RULES",
        ...plan.crossRegionCouplings.slice(0, 5).map((item) => `${item.regionIds.join("+")}: ${clip(item.rule, 150)}`),
      ].join("\n"),
    });
  }
  if (plan.additions.length || plan.removals.length) {
    sections.push({
      id: "addRemove",
      required: false,
      text: [
        "JUSTIFIED ADDITIONS / REMOVALS",
        ...plan.additions.slice(0, 4).map((item) => `ADD ${item.id} ${item.screenZone}/${item.depth}: ${clip(item.description, 120)}; because ${clip(item.causalReason, 80)}`),
        ...plan.removals.slice(0, 4).map((item) => `REMOVE ${item.regionId}: ${clip(item.causalReason, 120)}`),
      ].join("\n"),
    });
  }
  sections.push({
    id: "coverage",
    required: false,
    text: [
      "COVERAGE CHECK",
      `Evaluated ${plan.coverage.evaluatedRegionIds.join(",")}; changed domains ${plan.coverage.changedDomains.join(",") || "none"}.`,
      "Do not finish until every listed region has either its edit or explicit unchanged treatment visible in the output.",
    ].join("\n"),
  });
  const uncertainties = graph.uncertainties.filter(Boolean);
  if (uncertainties.length) {
    sections.push({
      id: "uncertainty",
      required: false,
      text: `UNCERTAINTY\n${clip(uncertainties.join("; "), 220)}. Prefer conservative visible edits over invented hidden facts.`,
    });
  }
  return sections;
}

function emergencyPrompt(
  graph: SceneGraph,
  plan: TemporalRenderPlan,
  timePosition: TimePositionPayload,
  aspectRatio: AspectRatio
): string {
  const changes = plan.regionChanges.slice(0, 12).map((change) => {
    const region = graph.regions.find((item) => item.id === change.regionId);
    return formatChange(region, change, 64);
  });
  return [
    "TARGET",
    `${plan.exactTarget.compactLabel} ${plan.exactTarget.targetDateISO}; ${(timePosition.offsetDays / 365.25).toFixed(1)}y; ${aspectRatio}.`,
    "CAMERA LOCK",
    "Keep viewpoint, crop, horizon, perspective, vanishing points, scale and occlusion topology.",
    `CONTINUITY ${plan.subjectContinuityMode}.`,
    "REGION EDITS",
    ...changes,
    plan.unchangedRegionIds.length ? `UNCHANGED ${plan.unchangedRegionIds.join(",")}.` : "",
    "COHERENCE",
    "One era, one light/weather/material system. Apply environment changes, not only the salient subject.",
    "PROHIBITED",
    "No camera drift, arbitrary additions, filters, mixed eras, invented text or subject-only edit.",
  ].filter(Boolean).join("\n").slice(0, TOTAL_BUDGET);
}

function formatChange(
  region: SceneRegion | undefined,
  change: RegionTemporalChange,
  detailBudget: number
): string {
  const locator = region
    ? `${region.id} ${region.screenZone}/${region.depth}/${region.category}`
    : change.regionId;
  const detail = clip(`${change.targetState}; cause: ${change.causalReason}`, detailBudget);
  return `${locator} -> ${change.action.toUpperCase()} ${change.magnitude}: ${detail}`;
}

function renderSections(sections: PromptSection[]): string {
  return sections.map((section) => section.text).join("\n\n");
}

function clip(value: string, max: number): string {
  const normalized = value.replace(/\s+/g, " ").trim();
  if (normalized.length <= max) return normalized;
  return `${normalized.slice(0, Math.max(0, max - 1)).trimEnd()}…`;
}
