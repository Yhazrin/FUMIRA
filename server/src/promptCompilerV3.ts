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
  let included: PromptSection[] = [
    ...fixedSections.slice(0, 3),
    regionSection,
    ...fixedSections.slice(3),
  ];

  for (const optional of optionalSections) {
    if (renderSections([...included, optional]).length <= TOTAL_BUDGET) {
      included.push(optional);
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

  const allSections = [...fixedSections, regionSection, ...optionalSections];
  const sectionCharCounts: Record<string, number> = {};
  const truncatedSections: string[] = [];
  for (const section of allSections) {
    const rendered = included.find((item) => item.id === section.id);
    sectionCharCounts[section.id] = emergency ? 0 : rendered?.text.length ?? 0;
    if (emergency || !rendered || rendered.text !== section.text) {
      truncatedSections.push(section.id);
    }
  }
  if (emergency) {
    sectionCharCounts.emergency = prompt.length;
  }

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
    correctionLines.push(
      `Restore camera geometry: ${clip(input.critic.cameraDrift.join("; "), 180)}.`
    );
  }
  for (const change of missing.slice(0, 16)) {
    const region = input.graph.regions.find((item) => item.id === change.regionId);
    correctionLines.push(formatChange(region, change, 105));
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
        `${safe(plan.exactTarget.compactLabel)}; exact date ${safe(plan.exactTarget.targetDateISO)}; offset ${(timePosition.offsetDays / 365.25).toFixed(2)} years; aspect ${aspectRatio}.`,
        `Render plan ${safe(plan.planId)}. Same viewpoint, one coherent target world.`,
      ].join("\n"),
    },
    {
      id: "camera",
      required: true,
      text: [
        "CAMERA LOCK",
        clip(
          `${camera.viewpoint}; ${camera.framing}; ${camera.horizon}; ${camera.perspective}; ${camera.depthLayout}`,
          260
        ),
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
        clip(
          `${plan.globalWorldState.eraSummary}; ${plan.globalWorldState.environmentalState}; ${plan.globalWorldState.technologyState}; ${plan.globalWorldState.humanActivityState}`,
          300
        ),
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

  // Phase 1: every planned region receives a non-droppable compact action.
  const compactLines = ordered.map((change) => {
    const region = graph.regions.find((item) => item.id === change.regionId);
    return formatCompactChange(region, change);
  });
  const compactCost = compactLines.join("\n").length;
  if (compactCost > remaining) {
    // Force the compiler into the emergency representation, which is designed
    // to carry all region IDs under the hard provider budget.
    return {
      id: "regionEdits",
      required: true,
      text: `${header}${compactLines.join("\n")}\n${unchanged}`.trimEnd(),
    };
  }

  // Phase 2: spend remaining detail budget on high-salience regions without
  // ever deleting the compact instruction for a lower-salience region.
  const lines = [...compactLines];
  let detailRemaining = remaining - compactCost;
  for (let index = 0; index < ordered.length; index++) {
    const change = ordered[index];
    const region = graph.regions.find((item) => item.id === change.regionId);
    const expanded = formatChange(region, change, 165);
    const delta = expanded.length - lines[index].length;
    if (delta <= detailRemaining) {
      lines[index] = expanded;
      detailRemaining -= delta;
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
        ...plan.crossRegionCouplings.slice(0, 5).map((item) =>
          `${item.regionIds.map(safe).join("+")}: ${clip(item.rule, 150)}`
        ),
      ].join("\n"),
    });
  }
  if (plan.additions.length || plan.removals.length) {
    sections.push({
      id: "addRemove",
      required: false,
      text: [
        "JUSTIFIED ADDITIONS / REMOVALS",
        ...plan.additions.slice(0, 4).map((item) =>
          `ADD ${safe(item.id)} ${item.screenZone}/${item.depth}: ${clip(item.description, 120)}; because ${clip(item.causalReason, 80)}`
        ),
        ...plan.removals.slice(0, 4).map((item) =>
          `REMOVE ${safe(item.regionId)}: ${clip(item.causalReason, 120)}`
        ),
      ].join("\n"),
    });
  }
  sections.push({
    id: "coverage",
    required: false,
    text: [
      "COVERAGE CHECK",
      `Evaluated ${plan.coverage.evaluatedRegionIds.map(safe).join(",")}; changed domains ${plan.coverage.changedDomains.join(",") || "none"}.`,
      "Do not finish until every listed region has either its edit or explicit unchanged treatment visible in the output.",
    ].join("\n"),
  });
  if (graph.uncertainties.some(Boolean)) {
    sections.push({
      id: "uncertainty",
      required: false,
      text: `UNCERTAINTY\n${clip(graph.uncertainties.join("; "), 220)}. Prefer conservative visible edits over invented hidden facts.`,
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
  const prompt = [
    "TARGET",
    `${safe(plan.exactTarget.compactLabel)} ${safe(plan.exactTarget.targetDateISO)}; ${(timePosition.offsetDays / 365.25).toFixed(1)}y; ${aspectRatio}.`,
    "CAMERA LOCK",
    "Keep viewpoint, crop, horizon, perspective, vanishing points, scale and occlusion topology.",
    `CONTINUITY ${plan.subjectContinuityMode}.`,
    "REGION EDITS",
    ...changes,
    plan.unchangedRegionIds.length
      ? `UNCHANGED ${plan.unchangedRegionIds.map(safe).join(",")}.`
      : "",
    "COHERENCE",
    "One era and one light/weather/material system. Apply environment changes, not only the salient subject.",
    "PROHIBITED",
    "No camera drift, arbitrary additions, filters, mixed eras, invented text or subject-only edit.",
  ].filter(Boolean).join("\n");
  return prompt.slice(0, TOTAL_BUDGET);
}

function formatChange(
  region: SceneRegion | undefined,
  change: RegionTemporalChange,
  detailBudget: number
): string {
  const locator = region
    ? `${safe(region.id)} ${region.screenZone}/${region.depth}/${region.category}`
    : safe(change.regionId);
  const detail = clip(
    `${change.targetState}; cause: ${change.causalReason}`,
    detailBudget
  );
  return `${locator} -> ${change.action.toUpperCase()} ${change.magnitude}: ${detail}`;
}

function formatCompactChange(
  region: SceneRegion | undefined,
  change: RegionTemporalChange
): string {
  const locator = region
    ? `${safe(region.id)} ${region.screenZone}/${region.depth}`
    : safe(change.regionId);
  return `${locator} ${change.action.toUpperCase()} ${change.magnitude}: ${clip(change.targetState, 54)}`;
}

function formatEmergencyChange(
  region: SceneRegion | undefined,
  change: RegionTemporalChange
): string {
  const locator = region
    ? `${safe(region.id)} ${region.screenZone}/${region.depth}`
    : safe(change.regionId);
  return `${locator} ${change.action.toUpperCase()}: ${clip(change.targetState, 38)}`;
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
