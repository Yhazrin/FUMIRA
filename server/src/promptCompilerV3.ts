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
  const fixed = buildFixedSections(graph, plan, timePosition, aspectRatio);
  const regions = buildRegionSection(graph, plan, fixed);
  const optional = buildOptionalSections(graph, plan);
  let included: PromptSection[] = [
    fixed[0],
    fixed[1],
    fixed[2],
    regions,
    fixed[3],
    fixed[4],
  ];

  for (const section of optional) {
    if (renderSections([...included, section]).length <= TOTAL_BUDGET) {
      included.push(section);
    }
  }

  let prompt = renderSections(included);
  let emergency = false;
  if (prompt.length > TOTAL_BUDGET) {
    emergency = true;
    prompt = emergencyPrompt(graph, plan, timePosition, aspectRatio);
    included = [];
  }
  if (prompt.length > TOTAL_BUDGET) {
    throw new Error("prompt_v3_required_contract_exceeds_budget");
  }

  const all = [...fixed, regions, ...optional];
  const sectionCharCounts: Record<string, number> = {};
  const truncatedSections: string[] = [];
  for (const section of all) {
    const rendered = included.find((item) => item.id === section.id);
    sectionCharCounts[section.id] = emergency ? 0 : rendered?.text.length ?? 0;
    if (emergency || !rendered || rendered.text !== section.text) {
      truncatedSections.push(section.id);
    }
  }
  if (emergency) sectionCharCounts.emergency = prompt.length;

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
  const lines = [
    "CORRECTION PASS",
    "Keep successful camera, topology, identity and already-correct regions.",
  ];
  if (input.critic.cameraDrift.length) {
    lines.push(`RESTORE CAMERA: ${clip(input.critic.cameraDrift.join("; "), 150)}`);
  }
  for (const change of missing.slice(0, 16)) {
    const region = input.graph.regions.find((item) => item.id === change.regionId);
    lines.push(formatChange(region, change, 92));
  }
  if (!missing.length && input.critic.correctionInstruction) {
    lines.push(clip(input.critic.correctionInstruction, 300));
  }
  lines.push(
    "Do not alter already-correct regions merely to create novelty.",
    "Do not repair environment coverage by changing only the main subject, adding a filter, or moving the camera."
  );
  const correction = lines.join("\n");
  const baseBudget = Math.max(0, TOTAL_BUDGET - correction.length - 2);
  return `${input.originalPrompt.slice(0, baseBudget).trimEnd()}\n\n${correction}`
    .slice(0, TOTAL_BUDGET);
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
        `${safe(plan.exactTarget.compactLabel)} | ${safe(plan.exactTarget.targetDateISO)} | ${(timePosition.offsetDays / 365.25).toFixed(2)}y | ${aspectRatio} | plan ${safe(plan.planId)}. Same viewpoint, one target world.`,
      ].join("\n"),
    },
    {
      id: "camera",
      required: true,
      text: [
        "CAMERA LOCK",
        clip(`${camera.viewpoint}; ${camera.framing}; ${camera.horizon}; ${camera.perspective}; ${camera.depthLayout}`, 155),
        "Keep screen coordinates, vanishing points, scale, crop and occlusion order.",
      ].join("\n"),
    },
    {
      id: "continuity",
      required: true,
      text: `CONTINUITY\n${plan.subjectContinuityMode}: preserve identity only where region policy requires; release transient entities.`,
    },
    {
      id: "coherence",
      required: true,
      text: [
        "WORLD COHERENCE",
        clip(`${plan.globalWorldState.eraSummary}; ${plan.globalWorldState.environmentalState}; ${plan.globalWorldState.technologyState}; ${plan.globalWorldState.humanActivityState}`, 175),
        "One era, light, weather, material logic and causal history across all edits.",
      ].join("\n"),
    },
    {
      id: "prohibited",
      required: true,
      text: [
        "PROHIBITED",
        "No camera drift, arbitrary objects, invented text, uniform aging, mixed eras, vintage filter, neon cyberpunk, identity replacement or subject-only transformation.",
        clip(plan.prohibitedDrift.join("; "), 115),
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
  const unchanged = plan.unchangedRegionIds.length
    ? `UNCHANGED ${plan.unchangedRegionIds.map(safe).join(",")}: preserve source state and spatial role.\n`
    : "";
  const reserved = renderSections(fixed).length + 2 + header.length + unchanged.length;
  const remaining = Math.max(0, TOTAL_BUDGET - reserved);
  const ordered = [...plan.regionChanges].sort((a, b) => {
    const aSalience = graph.regions.find((region) => region.id === a.regionId)?.salience ?? 0;
    const bSalience = graph.regions.find((region) => region.id === b.regionId)?.salience ?? 0;
    return bSalience - aSalience;
  });

  // Every changed region first receives a compact instruction. Detail is added
  // only after complete region coverage is secured.
  const lines = ordered.map((change) => {
    const region = graph.regions.find((item) => item.id === change.regionId);
    return formatCompactChange(region, change);
  });
  const compactCost = lines.join("\n").length;
  if (compactCost <= remaining) {
    let detailBudget = remaining - compactCost;
    for (let index = 0; index < ordered.length; index++) {
      const change = ordered[index];
      const region = graph.regions.find((item) => item.id === change.regionId);
      const expanded = formatChange(region, change, 135);
      const delta = expanded.length - lines[index].length;
      if (delta <= detailBudget) {
        lines[index] = expanded;
        detailBudget -= delta;
      }
    }
  }

  if (!lines.length) {
    lines.push("No local edit may replace the required world-state transformation.");
  }
  return {
    id: "regionEdits",
    required: true,
    text: `${header}${lines.join("\n")}\n${unchanged}`.trimEnd(),
  };
}

function buildOptionalSections(
  graph: SceneGraph,
  plan: TemporalRenderPlan
): PromptSection[] {
  const sections: PromptSection[] = [];
  if (plan.crossRegionCouplings.length) {
    sections.push({
      id: "couplings",
      required: false,
      text: [
        "CROSS-REGION RULES",
        ...plan.crossRegionCouplings.slice(0, 4).map((item) =>
          `${item.regionIds.map(safe).join("+")}: ${clip(item.rule, 120)}`
        ),
      ].join("\n"),
    });
  }
  if (plan.additions.length || plan.removals.length) {
    sections.push({
      id: "addRemove",
      required: false,
      text: [
        "JUSTIFIED ADD / REMOVE",
        ...plan.additions.slice(0, 3).map((item) =>
          `ADD ${safe(item.id)} ${item.screenZone}/${item.depth}: ${clip(item.description, 90)}; ${clip(item.causalReason, 55)}`
        ),
        ...plan.removals.slice(0, 3).map((item) =>
          `REMOVE ${safe(item.regionId)}: ${clip(item.causalReason, 90)}`
        ),
      ].join("\n"),
    });
  }
  sections.push({
    id: "coverage",
    required: false,
    text: `COVERAGE\nEvaluated ${plan.coverage.evaluatedRegionIds.map(safe).join(",")}; domains ${plan.coverage.changedDomains.join(",") || "none"}. Every region needs its edit or explicit unchanged treatment.`,
  });
  if (graph.uncertainties.some(Boolean)) {
    sections.push({
      id: "uncertainty",
      required: false,
      text: `UNCERTAINTY\n${clip(graph.uncertainties.join("; "), 165)}. Prefer conservative visible edits over invented hidden facts.`,
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
  const changes = plan.regionChanges.slice(0, 16).map((change) => {
    const region = graph.regions.find((item) => item.id === change.regionId);
    return formatEmergencyChange(region, change);
  });
  return [
    "TARGET",
    `${safe(plan.exactTarget.compactLabel)} ${safe(plan.exactTarget.targetDateISO)} ${(timePosition.offsetDays / 365.25).toFixed(1)}y ${aspectRatio}.`,
    "CAMERA LOCK",
    "Keep viewpoint, crop, horizon, perspective, vanishing points, scale and occlusion topology.",
    `CONTINUITY ${plan.subjectContinuityMode}.`,
    "REGION EDITS",
    ...changes,
    plan.unchangedRegionIds.length
      ? `UNCHANGED ${plan.unchangedRegionIds.map(safe).join(",")}.`
      : "",
    "WORLD COHERENCE",
    "One era/light/weather/material system. Apply environment changes, not only the salient subject.",
    "PROHIBITED",
    "No camera drift, arbitrary additions, filters, mixed eras, invented text or subject-only transformation.",
  ].filter(Boolean).join("\n").slice(0, TOTAL_BUDGET);
}

function formatChange(
  region: SceneRegion | undefined,
  change: RegionTemporalChange,
  detailBudget: number
): string {
  const locator = region
    ? `${safe(region.id)} ${region.screenZone}/${region.depth}/${region.category}`
    : safe(change.regionId);
  return `${locator} -> ${change.action.toUpperCase()} ${change.magnitude}: ${clip(`${change.targetState}; cause: ${change.causalReason}`, detailBudget)}`;
}

function formatCompactChange(
  region: SceneRegion | undefined,
  change: RegionTemporalChange
): string {
  const locator = region
    ? `${safe(region.id)} ${region.screenZone}/${region.depth}`
    : safe(change.regionId);
  return `${locator} ${change.action.toUpperCase()} ${change.magnitude}: ${clip(change.targetState, 45)}`;
}

function formatEmergencyChange(
  region: SceneRegion | undefined,
  change: RegionTemporalChange
): string {
  const locator = region
    ? `${safe(region.id)} ${region.screenZone}/${region.depth}`
    : safe(change.regionId);
  return `${locator} ${change.action.toUpperCase()}: ${clip(change.targetState, 32)}`;
}

function renderSections(sections: PromptSection[]): string {
  return sections.map((section) => section.text).join("\n\n");
}

function clip(value: string, max: number): string {
  const normalized = safe(value).replace(/\s+/g, " ").trim();
  if (normalized.length <= max) return normalized;
  return `${normalized.slice(0, Math.max(0, max - 1)).trimEnd()}…`;
}

function safe(value: string): string {
  return String(value ?? "")
    .replaceAll("<", "\\u003c")
    .replaceAll(">", "\\u003e")
    .replaceAll("\u0000", "")
    .replace(/[\u0001-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, " ");
}
