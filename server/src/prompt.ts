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
 * 1. Fill template placeholders.
 * 2. If over 1500 chars, keep the head (composition lock + story start)
 *    and append an explicit continuity footer that fits in the remaining budget.
 * 3. Record `truncated` for admin metadata; never silently drop without the flag.
 */
export function buildPrompt(params: {
  template: string;
  story: string;
  timePosition: TimePositionPayload;
  aspectRatio: AspectRatio;
}): BuiltPrompt {
  const filled = params.template
    .replaceAll("{{story}}", params.story.trim())
    .replaceAll("{{timeLabel}}", params.timePosition.compactLabel || "NOW")
    .replaceAll("{{aspectRatio}}", params.aspectRatio)
    .trim();

  if (filled.length <= PROMPT_HARD_LIMIT) {
    return {
      prompt: filled,
      truncated: false,
      charCount: filled.length,
    };
  }

  const footer =
    " Keep original composition, camera angle, and main subject identity.";
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
