import { createHash } from "node:crypto";
import { config } from "./config.js";
import type {
  AspectRatio,
  GenerationContext,
  SceneUnderstandingPayload,
  StoryBeatPayload,
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

const VERSION = "v2";
const TOTAL_BUDGET = config.promptMaxChars;
interface Section {
  id: string;
  retentionPriority: number;
  renderOrder: number;
  required: boolean;
  emergencyTemplate: string;
  build(ctx: CompileContext): string;
}
interface CompileContext {
  understanding: SceneUnderstandingPayload;
  story: TemporalStoryPayloadV2;
  targetBeat: StoryBeatPayload;
  timePosition: TimePositionPayload;
  aspectRatio: AspectRatio;
}

export function sanitizeUntrustedPromptData(value: string): string {
  return value.replaceAll("<", "\\u003c").replaceAll(">", "\\u003e")
    .replaceAll("\u0000", "").replace(/[\u0001-\u0008\u000B\u000C\u000E-\u001F]/g, "");
}
function sanitizeAll(strings: string[]): string[] { return strings.map(sanitizeUntrustedPromptData); }

const sections: Section[] = [
  {
    id: "objective", retentionPriority: 100, renderOrder: 10, required: true,
    emergencyTemplate: "EDIT OBJECTIVE\nRender the exact same camera view at the requested target time.",
    build(ctx) {
      return `EDIT OBJECTIVE\nTransform the source photograph into the exact same place at ${ctx.timePosition.compactLabel || "NOW"}. Treat this as a coherent world-state change, not a local edit.`;
    },
  },
  {
    id: "preserve", retentionPriority: 95, renderOrder: 20, required: true,
    emergencyTemplate: "PRESERVE\nKeep camera, framing, perspective, topology and plausible principal identity without freezing transient content.",
    build(ctx) {
      const lines = [
        "PRESERVE",
        "- Keep camera position, lens perspective, framing, horizon, vanishing points and major topology.",
        "- Preserve principal identity only when physically plausible; do not lock transient people, vehicles, signage, vegetation size or subject count.",
      ];
      const rules = sanitizeAll([...ctx.understanding.subjects.map((s) => s.identityRule), ...ctx.story.identityRules].filter(Boolean));
      if (rules.length) lines.push(...rules.map((r) => `- ${r}`));
      return lines.join("\n");
    },
  },
  {
    id: "temporalChanges", retentionPriority: 99, renderOrder: 30, required: true,
    emergencyTemplate: "TEMPORAL CHANGES\nApply the exact time change to both principal subject and surrounding environment.",
    build(ctx) {
      return `TEMPORAL CHANGES\n${sanitizeUntrustedPromptData(ctx.targetBeat.visualPrompt)} ${sanitizeUntrustedPromptData(ctx.targetBeat.narrative)}\nChange the environment as well as the salient subject whenever plausible.`;
    },
  },
  {
    id: "sceneCoverage", retentionPriority: 98, renderOrder: 40, required: true,
    emergencyTemplate: "SCENE-WIDE COVERAGE\nPropagate era-consistent change through visible foreground, midground and background.",
    build(ctx) {
      return [
        "SCENE-WIDE COVERAGE",
        "Evaluate foreground, midground, background and sky.",
        "Propagate time through present architecture, infrastructure, surfaces, vegetation, vehicles, signage, clothing, lighting and atmosphere.",
        "Permit era-justified additions, removals, renovation and replacement; explicitly preserve implausible-to-change regions.",
        ctx.understanding.changeDrivers.length ? `Drivers: ${sanitizeAll(ctx.understanding.changeDrivers).join(", ")}` : "",
      ].filter(Boolean).join("\n");
    },
  },
  {
    id: "temporalRealism", retentionPriority: 92, renderOrder: 50, required: true,
    emergencyTemplate: "TEMPORAL REALISM\nMatch change magnitude to the requested span and keep one coherent era.",
    build(ctx) {
      return `TEMPORAL REALISM\nOffset ${ctx.timePosition.offsetYears.toFixed(1)} years. Use material aging, maintenance, biological growth, construction history, technology turnover and local environmental processes.`;
    },
  },
  {
    id: "sceneDetails", retentionPriority: 55, renderOrder: 60, required: false, emergencyTemplate: "",
    build(ctx) {
      return `SCENE DETAILS\nLocation: ${sanitizeUntrustedPromptData(ctx.understanding.locationType)}. Mood: ${sanitizeUntrustedPromptData(ctx.understanding.visualMood)}.`;
    },
  },
  {
    id: "prohibit", retentionPriority: 90, renderOrder: 80, required: true,
    emergencyTemplate: "DO NOT\nNo camera drift, arbitrary elements, invented text, generic filters or subject-only transformation.",
    build() {
      return "DO NOT\n- No camera drift, arbitrary unrelated elements, invented readable text, generic vintage filter, neon cyberpunk, mixed eras, uniform aging or subject-only transformation.";
    },
  },
];

export function compilePrompt(input: { context: GenerationContext; timePosition: TimePositionPayload; aspectRatio: AspectRatio }): CompiledPrompt {
  const ctx: CompileContext = {
    understanding: input.context.understanding,
    story: input.context.story,
    targetBeat: input.context.story.targetBeat,
    timePosition: input.timePosition,
    aspectRatio: input.aspectRatio,
  };
  const built = sections.map((s) => ({ ...s, text: s.build(ctx) }));
  const included = new Map<string, { text: string; fullText: string }>();
  for (const s of built.filter((x) => x.required)) included.set(s.id, { text: s.emergencyTemplate, fullText: s.text });
  for (const s of built.filter((x) => x.required).sort((a, b) => b.retentionPriority - a.retentionPriority)) {
    const old = included.get(s.id)!;
    included.set(s.id, { text: s.text, fullText: s.text });
    if (render(included).length > TOTAL_BUDGET) included.set(s.id, old);
  }
  for (const s of built.filter((x) => !x.required).sort((a, b) => b.retentionPriority - a.retentionPriority)) {
    included.set(s.id, { text: s.text, fullText: s.text });
    if (render(included).length > TOTAL_BUDGET) included.delete(s.id);
  }
  const prompt = render(included);
  const sectionCharCounts: Record<string, number> = {};
  const truncatedSections: string[] = [];
  for (const s of built) {
    const entry = included.get(s.id);
    sectionCharCounts[s.id] = entry?.text.length ?? 0;
    if (!entry || entry.text !== entry.fullText) truncatedSections.push(s.id);
  }
  return {
    prompt, version: VERSION,
    hash: createHash("sha256").update(prompt).digest("hex").slice(0, 16),
    charCount: prompt.length, truncated: truncatedSections.length > 0,
    sectionCharCounts, truncatedSections,
  };
}

export function buildLegacyPrompt(params: { template: string; story: string; timePosition: TimePositionPayload; aspectRatio: AspectRatio }) {
  const filled = params.template.replaceAll("{{story}}", params.story.trim())
    .replaceAll("{{timeLabel}}", params.timePosition.compactLabel || "NOW")
    .replaceAll("{{aspectRatio}}", params.aspectRatio).trim();
  if (filled.length <= TOTAL_BUDGET) return { prompt: filled, truncated: false, charCount: filled.length };
  const footer = " Keep original composition, camera angle, and main subject identity.";
  const prompt = `${filled.slice(0, Math.max(0, TOTAL_BUDGET - footer.length)).trimEnd()}${footer}`.slice(0, TOTAL_BUDGET);
  return { prompt, truncated: true, charCount: prompt.length };
}

function render(included: Map<string, { text: string }>): string {
  return sections.filter((s) => included.has(s.id)).sort((a, b) => a.renderOrder - b.renderOrder).map((s) => included.get(s.id)!.text).join("\n\n");
}
