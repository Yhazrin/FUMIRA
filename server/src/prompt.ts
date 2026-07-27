import { config, type AspectRatio } from "./config.js";
import type { TimePositionPayload } from "./types.js";

const PROMPT_HARD_LIMIT = config.promptMaxChars;

export interface BuiltPrompt {
  prompt: string;
  truncated: boolean;
  charCount: number;
}

/**
 * Truncation strategy:
 * 1. Fill template placeholders with the server-authored core prompt.
 * 2. Always append continuityFooter.
 * 3. If over promptMaxChars, keep the head and preserve the footer.
 * 4. Record `truncated` for admin metadata; never silently drop without the flag.
 */
export function buildPrompt(params: {
  template: string;
  corePrompt: string;
  timePosition: TimePositionPayload;
  aspectRatio: AspectRatio;
}): BuiltPrompt {
  const corePrompt = params.corePrompt.trim();
  const includesCorePrompt =
    params.template.includes("{{prompt}}")
    || params.template.includes("{{story}}");
  const filledTemplate = params.template
    .replaceAll("{{prompt}}", corePrompt)
    .replaceAll("{{story}}", corePrompt)
    .replaceAll("{{timeLabel}}", params.timePosition.compactLabel || "NOW")
    .replaceAll("{{aspectRatio}}", params.aspectRatio)
    .trim();
  const continuityFooter = [
    `Exact target time: ${params.timePosition.compactLabel || "NOW"} (${params.timePosition.offsetYears.toFixed(1)} years).`,
    `Output aspect ratio: ${params.aspectRatio}.`,
    "Preserve source camera, perspective, composition, spatial hierarchy, and recognizable scene anchors.",
    "Evaluate foreground, midground, background, architecture, surfaces, vegetation, movable objects, and human-use traces.",
    "Do not use one person or one object as the sole temporal cue for a medium or long time span.",
    "All visible changes must belong to one coherent date, maintenance level, and causal history.",
    "No unrelated subjects, text, logos, watermarks, fantasy, or unsupported sci-fi elements.",
  ].join(" ");
  const promptBody = includesCorePrompt
    ? filledTemplate
    : [filledTemplate, corePrompt].filter(Boolean).join("\n");
  const filled = `${promptBody}\n${continuityFooter}`.trim();

  if (filled.length <= PROMPT_HARD_LIMIT) {
    return {
      prompt: filled,
      truncated: false,
      charCount: filled.length,
    };
  }

  const footer = `\n${continuityFooter}`;
  const budget = Math.max(0, PROMPT_HARD_LIMIT - footer.length);
  const head = filled.slice(0, budget).trimEnd();
  const prompt = `${head}${footer}`.slice(0, PROMPT_HARD_LIMIT);
  return {
    prompt,
    truncated: true,
    charCount: prompt.length,
  };
}

export function normalizeAspectRatio(
  value: string | undefined
): AspectRatio | null {
  const candidate = (value ?? "3:4") as AspectRatio;
  if ((config.allowedAspectRatios as readonly string[]).includes(candidate)) {
    return candidate;
  }
  return null;
}

export function toJpegDataUrl(bytes: Buffer, contentType: string): string {
  // MiniMax I2I accepts data:image/jpeg;base64,... — convert HEIC to labeled
  // JPEG data URL only when already JPEG; otherwise pass the JPEG MIME hint.
  // (real HEIC should be transcoded before MiniMax; mock adapter accepts any).
  const mime =
    contentType === "image/jpeg" || contentType === "image/jpg"
      ? "image/jpeg"
      : contentType === "image/png"
        ? "image/png"
        : "image/jpeg";
  return `data:${mime};base64,${bytes.toString("base64")}`;
}
