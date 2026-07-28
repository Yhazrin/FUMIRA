import { createHash } from "node:crypto";
import { config } from "./config.js";
import type {
  AspectRatio,
  GenerationContext,
  RegionTemporalChange,
  SceneRegionPayload,
  SceneUnderstandingPayload,
  StoryBeatPayload,
  TemporalRenderPlan,
  TemporalStoryPayloadV2,
  TimePositionPayload,
} from "./types.js";

export interface CompiledPrompt {
  prompt: string;
  version: string;
  hash: string;
  charCount: number;
  truncated: boolean;
  sectionCharCounts: Record<string, number>;
  truncatedSections: string[];
}

const VERSION = "v3";
const TOTAL_BUDGET = config.promptMaxChars;

interface CompileContext {
  understanding: SceneUnderstandingPayload;
  story: TemporalStoryPayloadV2;
  targetBeat: StoryBeatPayload;
  plan: TemporalRenderPlan;
  timePosition: TimePositionPayload;
  aspectRatio: AspectRatio;
}

interface Section {
  id: string;
  retentionPriority: number;
  renderOrder: number;
  required: boolean;
  buildFull(ctx: CompileContext): string;
  buildCompact(ctx: CompileContext): string;
}

export function sanitizeUntrustedPromptData(value: string): string {
  return value
    .replaceAll("<", "\\u003c")
    .replaceAll(">", "\\u003e")
    .replaceAll("\0", "")
    .replace(/[\x01-\x08\x0B\x0C\x0E-\x1F]/g, "");
}

function clean(value: string | undefined): string {
  return sanitizeUntrustedPromptData(value?.trim() ?? "");
}

const sections: Section[] = [
  {
    id: "objective",
    retentionPriority: 100,
    renderOrder: 10,
    required: true,
    buildFull(ctx) {
      return [
        "EDIT OBJECTIVE",
        `Render the exact same camera view at ${clean(ctx.timePosition.compactLabel || "NOW")} (${targetDateISO(ctx.timePosition)}), aspect ratio ${ctx.aspectRatio}.`,
      ].join("\n");
    },
    buildCompact(ctx) {
      return [
        "EDIT OBJECTIVE",
        `Same camera view at ${clean(ctx.timePosition.compactLabel || "NOW")}.`,
      ].join("\n");
    },
  },
  {
    id: "cameraLock",
    retentionPriority: 100,
    renderOrder: 20,
    required: true,
    buildFull(ctx) {
      const lock =
        ctx.understanding.sceneGraph?.cameraLock
        ?? ctx.understanding.cameraLock;
      return boundedLines([
        "CAMERA AND COMPOSITION LOCK",
        "- Keep camera position, framing, crop, horizon, lens perspective and vanishing points.",
        "- Keep the major spatial topology and depth ordering.",
        lock?.viewpoint ? `- Viewpoint: ${clean(lock.viewpoint)}` : "",
        lock?.lensAndPerspective
          ? `- Lens/perspective: ${clean(lock.lensAndPerspective)}`
          : "",
        lock?.horizon ? `- Horizon: ${clean(lock.horizon)}` : "",
        lock?.depthStructure
          ? `- Depth layout: ${clean(lock.depthStructure)}`
          : "",
      ], 330);
    },
    buildCompact(_ctx) {
      return [
        "CAMERA AND COMPOSITION LOCK",
        "Keep camera position, crop, horizon, perspective, vanishing points and major spatial topology.",
      ].join("\n");
    },
  },
  {
    id: "temporalPlan",
    retentionPriority: 98,
    renderOrder: 40,
    required: true,
    buildFull(ctx) {
      return formatTemporalPlan(ctx, false);
    },
    buildCompact(ctx) {
      return formatTemporalPlan(ctx, true);
    },
  },
  {
    id: "anchorPolicy",
    retentionPriority: 95,
    renderOrder: 30,
    required: true,
    buildFull(ctx) {
      const lines = [
        "TEMPORAL ANCHOR POLICY",
        `- Subject continuity mode: ${ctx.plan.subjectContinuityMode}.`,
      ];
      for (const region of prioritizedRegions(ctx.understanding)) {
        lines.push(
          `- ${clean(region.id)} (${region.depth}/${region.category}): ${region.temporalPolicy}; ${clean(region.spatialAnchor)}`
        );
      }
      for (const rule of ctx.story.identityRules) {
        lines.push(`- Identity: ${clean(rule)}`);
      }
      return boundedLines(lines, 430);
    },
    buildCompact(ctx) {
      const firstAnchor =
        ctx.plan.mustPreserve[0]
        ?? ctx.story.identityRules[0]
        ?? "principal identity and recognizable spatial anchors";
      return [
        "TEMPORAL ANCHOR POLICY",
        `Use ${ctx.plan.subjectContinuityMode}; preserve ${clean(firstAnchor)}. Transient entities and their count may change by era.`,
      ].join("\n");
    },
  },
  {
    id: "sceneCoverage",
    retentionPriority: 92,
    renderOrder: 50,
    required: true,
    buildFull(ctx) {
      const coverage = ctx.plan.coverage;
      const requiredLayers = [
        coverage.foreground ? "foreground" : "",
        coverage.midground ? "midground" : "",
        coverage.background ? "background" : "",
        coverage.builtEnvironment ? "built environment" : "",
        coverage.naturalEnvironment ? "natural environment" : "",
        coverage.principalSubject ? "principal subject" : "",
      ].filter(Boolean);
      return [
        "SCENE-WIDE COHERENCE",
        `Apply one era consistently across ${requiredLayers.join(", ") || "all visible regions"}.`,
        "Do not finish after changing only the most salient person or object.",
      ].join("\n");
    },
    buildCompact(_ctx) {
      return [
        "SCENE-WIDE COHERENCE",
        "Coordinate foreground, midground, background, subject and environment in one era; do not change only one salient object.",
      ].join("\n");
    },
  },
  {
    id: "temporalRealism",
    retentionPriority: 70,
    renderOrder: 60,
    required: false,
    buildFull(ctx) {
      return [
        "TEMPORAL REALISM",
        `Horizon: ${ctx.plan.horizonBand}; offset ${ctx.timePosition.offsetYears.toFixed(2)} years.`,
        evolutionRules(ctx.plan.horizonBand),
        "Use material-specific aging and causal maintenance; avoid aging every surface equally.",
      ].join("\n");
    },
    buildCompact(ctx) {
      return `TEMPORAL REALISM\n${evolutionRules(ctx.plan.horizonBand)}`;
    },
  },
  {
    id: "narrative",
    retentionPriority: 20,
    renderOrder: 70,
    required: false,
    buildFull(ctx) {
      return boundedLines([
        "NARRATIVE CONTEXT",
        clean(ctx.story.presentTruth),
        clean(ctx.targetBeat.narrative),
      ], 260);
    },
    buildCompact(ctx) {
      return `NARRATIVE CONTEXT\n${clean(ctx.targetBeat.narrative)}`;
    },
  },
  {
    id: "prohibit",
    retentionPriority: 88,
    renderOrder: 80,
    required: true,
    buildFull(ctx) {
      const lines = [
        "DO NOT",
        "- Do not change camera angle, crop, horizon, perspective or major spatial layout.",
        "- Do not replace the principal identity when its continuity mode requires persistence.",
        "- Do not add arbitrary elements unrelated to the location, target era or documented scene evolution.",
        "- Do not freeze transient subject counts or block causally required era replacements.",
        "- Do not use generic sepia/vintage filters, cyberpunk styling, invented text, logos or watermarks.",
        "- Do not leave planned environmental regions unchanged while transforming only one salient subject.",
      ];
      for (const item of ctx.plan.prohibitedDrift) {
        lines.push(`- ${clean(item)}`);
      }
      return boundedLines(lines, 460);
    },
    buildCompact(_ctx) {
      return [
        "DO NOT",
        "Do not drift camera geometry or principal identity; do not block causally required era replacements; do not add arbitrary elements, generic era filters, invented text, or change only one salient subject.",
      ].join("\n");
    },
  },
];

export function compilePrompt(input: {
  context: GenerationContext;
  timePosition: TimePositionPayload;
  aspectRatio: AspectRatio;
}): CompiledPrompt {
  const targetBeat = input.context.story.targetBeat;
  const ctx: CompileContext = {
    understanding: input.context.understanding,
    story: input.context.story,
    targetBeat,
    plan: targetBeat.renderPlan
      ?? synthesizeLegacyPlan(
        input.context.understanding,
        targetBeat,
        input.timePosition
      ),
    timePosition: input.timePosition,
    aspectRatio: input.aspectRatio,
  };

  const built = sections.map((section) => ({
    ...section,
    fullText: section.buildFull(ctx),
    compactText: section.buildCompact(ctx),
  }));

  const included = new Map<string, string>();
  for (const section of built.filter((item) => item.required)) {
    included.set(section.id, section.compactText);
  }

  for (const section of [...built]
    .filter((item) => item.required)
    .sort((a, b) => b.retentionPriority - a.retentionPriority)) {
    const candidate = new Map(included);
    candidate.set(section.id, section.fullText);
    if (renderLength(candidate) <= TOTAL_BUDGET) {
      included.set(section.id, section.fullText);
    }
  }

  for (const section of [...built]
    .filter((item) => !item.required && item.fullText)
    .sort((a, b) => b.retentionPriority - a.retentionPriority)) {
    const candidate = new Map(included);
    candidate.set(section.id, section.fullText);
    if (renderLength(candidate) <= TOTAL_BUDGET) {
      included.set(section.id, section.fullText);
    }
  }

  const ordered = sections
    .filter((section) => included.has(section.id))
    .sort((a, b) => a.renderOrder - b.renderOrder)
    .map((section) => included.get(section.id)!);
  const prompt = ordered.join("\n\n");
  const sectionCharCounts: Record<string, number> = {};
  const truncatedSections: string[] = [];

  for (const section of built) {
    const text = included.get(section.id);
    sectionCharCounts[section.id] = text?.length ?? 0;
    if (!text || text !== section.fullText) {
      truncatedSections.push(section.id);
    }
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

function renderLength(values: Map<string, string>): number {
  const texts = sections
    .filter((section) => values.has(section.id))
    .sort((a, b) => a.renderOrder - b.renderOrder)
    .map((section) => values.get(section.id)!);
  return texts.join("\n\n").length;
}

function formatTemporalPlan(ctx: CompileContext, compact: boolean): string {
  const regions = new Map(
    (ctx.understanding.sceneGraph?.regions ?? []).map((region) => [
      region.id,
      region,
    ])
  );
  const changes = compact
    ? selectMinimumCoverageChanges(ctx.plan.regionChanges, regions)
    : ctx.plan.regionChanges;
  const lines = [
    "SCENE-WIDE TARGET PLAN",
    `Global era state: ${clip(clean(ctx.plan.globalEraState), compact ? 96 : 220)}`,
  ];
  for (const change of changes) {
    const region = regions.get(change.regionId);
    const depth = region?.depth ? `${region.depth}: ` : "";
    lines.push(
      `${depth}${clean(change.regionId)} — ${change.action}/${change.magnitude}: ${clip(clean(change.targetAppearance), compact ? 72 : 180)}; because ${clip(clean(change.causalReason), compact ? 54 : 140)}`
    );
  }
  if (!compact) {
    for (const coupling of ctx.plan.crossRegionCouplings) {
      lines.push(`Coupling: ${clean(coupling)}`);
    }
    for (const addition of ctx.plan.allowedEraAdditions) {
      lines.push(`Allowed when causal: ${clean(addition)}`);
    }
  }
  return boundedLines(lines, compact ? 390 : 760);
}

function selectMinimumCoverageChanges(
  changes: RegionTemporalChange[],
  regions: Map<string, SceneRegionPayload>
): RegionTemporalChange[] {
  const selected: RegionTemporalChange[] = [];
  const take = (predicate: (change: RegionTemporalChange) => boolean) => {
    const match = changes.find(
      (change) => !selected.includes(change) && predicate(change)
    );
    if (match) selected.push(match);
  };

  for (const depth of ["foreground", "midground", "background"] as const) {
    take((change) => regions.get(change.regionId)?.depth === depth);
  }
  take((change) => {
    const category = regions.get(change.regionId)?.category;
    return category === "person" || category === "animal";
  });
  take((change) => {
    const category = regions.get(change.regionId)?.category;
    return category !== "person" && category !== "animal";
  });
  if (!selected.length && changes[0]) selected.push(changes[0]);
  return selected.slice(0, 5);
}

function prioritizedRegions(
  understanding: SceneUnderstandingPayload
): SceneRegionPayload[] {
  return [...(understanding.sceneGraph?.regions ?? [])]
    .sort((a, b) => {
      if (a.temporalPolicy === "lock_geometry" && b.temporalPolicy !== "lock_geometry") {
        return -1;
      }
      return b.salience - a.salience;
    })
    .slice(0, 7);
}

function boundedLines(lines: string[], maximum: number): string {
  const filtered = lines.filter(Boolean);
  const output: string[] = [];
  for (const line of filtered) {
    const separator = output.length ? 1 : 0;
    const remaining = maximum - output.join("\n").length - separator;
    if (remaining <= 0) break;
    output.push(line.length <= remaining ? line : line.slice(0, remaining));
  }
  return output.join("\n");
}

function clip(value: string, maximum: number): string {
  return value.length <= maximum ? value : value.slice(0, maximum);
}

function synthesizeLegacyPlan(
  understanding: SceneUnderstandingPayload,
  beat: StoryBeatPayload,
  time: TimePositionPayload
): TemporalRenderPlan {
  const regions = understanding.sceneGraph?.regions ?? [];
  const firstAt = (depth: SceneRegionPayload["depth"], fallback: string) =>
    regions.find((region) => region.depth === depth)?.id ?? fallback;
  const candidates = [
    [firstAt("foreground", "foreground"), beat.foregroundDelta],
    [firstAt("midground", "midground"), beat.midgroundDelta],
    [firstAt("background", "background"), beat.backgroundDelta],
    [regions.find((region) => region.category === "person")?.id ?? "principal_subject", beat.subjectDelta],
    [regions.find((region) => region.category !== "person")?.id ?? "environment", beat.environmentDelta],
  ] as const;
  const regionChanges = candidates
    .filter((entry): entry is readonly [string, string] => Boolean(entry[1]))
    .map(([regionId, delta]) => ({
      regionId,
      action: "age" as const,
      magnitude: "moderate" as const,
      targetAppearance: delta,
      causalReason: beat.transitionCause ?? "elapsed time and documented scene drivers",
    }));
  if (!regionChanges.length) {
    regionChanges.push({
      regionId: regions[0]?.id ?? "whole_scene",
      action: "age",
      magnitude: "moderate",
      targetAppearance: beat.visualPrompt,
      causalReason: "elapsed time and documented scene drivers",
    });
  }
  return {
    exactTarget: beat.exactTarget ?? {
      offsetDays: time.offsetDays,
      targetDateISO: targetDateISO(time),
      compactLabel: time.compactLabel,
    },
    horizonBand: horizonBandForDays(time.offsetDays),
    subjectContinuityMode: "identity_persists",
    globalEraState: beat.visualPrompt,
    regionChanges,
    crossRegionCouplings: [],
    mustPreserve: beat.unchangedAnchors ?? understanding.subjects.map((item) => item.identityRule),
    allowedEraAdditions: [
      "era-consistent architecture, infrastructure, vegetation, vehicles and signage",
    ],
    prohibitedDrift: [],
    coverage: {
      foreground: true,
      midground: true,
      background: true,
      builtEnvironment: true,
      naturalEnvironment: true,
      principalSubject: true,
    },
  };
}

function evolutionRules(band: TemporalRenderPlan["horizonBand"]): string {
  switch (band) {
  case "hours_days":
    return "Prioritize light, weather, temporary objects and people; permanent structures barely change.";
  case "months":
    return "Prioritize season, vegetation state, temporary construction and decoration.";
  case "years":
    return "Prioritize wear, maintenance, clothing, vehicles, signage and modest growth.";
  case "decades":
    return "Prioritize age, tree growth, renovation, infrastructure and technology replacement.";
  case "centuries":
    return "Allow rebuilding, ecological succession, cultural change and site continuity over short-lived subjects.";
  case "millennia":
    return "Prioritize ruins, reconstruction, ecology, landform and plausible civilization continuity.";
  case "deep_time":
    return "Prioritize geology and climate; do not assume people or short-lived objects persist unless explicitly anchored.";
  }
}

function horizonBandForDays(daysValue: number): TemporalRenderPlan["horizonBand"] {
  const days = Math.abs(daysValue);
  if (days <= 14) return "hours_days";
  if (days < 365) return "months";
  if (days < 5 * 365.25) return "years";
  if (days < 100 * 365.25) return "decades";
  if (days < 1_000 * 365.25) return "centuries";
  if (days < 100_000 * 365.25) return "millennia";
  return "deep_time";
}

export function requiredChangeDomains(yearsValue: number): number {
  const years = Math.abs(yearsValue);
  if (years < 0.1) return 1;
  if (years < 2) return 2;
  if (years < 20) return 3;
  if (years < 100) return 4;
  return 5;
}

export function buildLegacyPrompt(params: {
  template: string;
  story: string;
  timePosition: TimePositionPayload;
  aspectRatio: AspectRatio;
}): {
  prompt: string;
  truncated: boolean;
  charCount: number;
} {
  const filled = params.template
    .replaceAll("{{story}}", params.story.trim())
    .replaceAll("{{timeLabel}}", params.timePosition.compactLabel || "NOW")
    .replaceAll("{{aspectRatio}}", params.aspectRatio)
    .trim();
  if (filled.length <= TOTAL_BUDGET) {
    return { prompt: filled, truncated: false, charCount: filled.length };
  }
  const footer =
    " Keep original composition, camera angle, and main subject identity.";
  const budget = Math.max(0, TOTAL_BUDGET - footer.length);
  const prompt = `${filled.slice(0, budget).trimEnd()}${footer}`.slice(
    0,
    TOTAL_BUDGET
  );
  return { prompt, truncated: true, charCount: prompt.length };
}

function targetDateISO(timePosition: TimePositionPayload): string {
  const now = new Date();
  return new Date(
    now.getTime() + timePosition.offsetDays * 86_400_000
  ).toISOString().slice(0, 10);
}
