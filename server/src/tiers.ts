import type { ImageGenerationProvider } from "./types.js";

/**
 * A tier is the single user-facing quality dial. It resolves the image model,
 * the anchor keyframe density, the prompt detail level, and how much of the
 * validate/repair budget a generation is allowed to spend.
 */
export type GenerationTier = "swift" | "balanced" | "faithful" | "cinematic";

export const DEFAULT_TIER: GenerationTier = "balanced";

export type PromptDetail = "compact" | "standard" | "full";

export interface TierProfile {
  id: GenerationTier;
  displayName: string;
  tagline: string;
  imageProvider: ImageGenerationProvider;
  imageModel: string;
  /** Odd count, always symmetric around NOW. Drives client-side prefetch. */
  anchorCount: number;
  validationEnabled: boolean;
  /** Maximum validate → repair → re-validate rounds. */
  repairRounds: number;
  promptDetail: PromptDetail;
  /** Rough cost multiple against the cheapest tier, for UI copy only. */
  relativeCost: number;
  estimatedSecondsPerFrame: number;
}

export const TIER_PROFILES: Record<GenerationTier, TierProfile> = {
  swift: {
    id: "swift",
    displayName: "极速",
    tagline: "最快、最省，先看到大概的样子",
    imageProvider: "apimart",
    imageModel: "gemini-3.1-flash-image-preview",
    anchorCount: 3,
    validationEnabled: false,
    repairRounds: 0,
    promptDetail: "compact",
    relativeCost: 1,
    estimatedSecondsPerFrame: 15,
  },
  balanced: {
    id: "balanced",
    displayName: "标准",
    tagline: "默认档，速度与还原度的平衡点",
    imageProvider: "apimart",
    imageModel: "gpt-4o-image",
    anchorCount: 5,
    validationEnabled: false,
    repairRounds: 0,
    promptDetail: "standard",
    relativeCost: 3,
    estimatedSecondsPerFrame: 35,
  },
  faithful: {
    id: "faithful",
    displayName: "高保真",
    tagline: "专用图像编辑模型，自动校验构图与年代，必要时重画",
    imageProvider: "apimart",
    imageModel: "gpt-image-2",
    anchorCount: 7,
    validationEnabled: true,
    repairRounds: 1,
    promptDetail: "full",
    relativeCost: 6,
    estimatedSecondsPerFrame: 70,
  },
  cinematic: {
    id: "cinematic",
    displayName: "电影级",
    tagline: "最强编辑模型配最密的时间锚点与最多修复轮次",
    imageProvider: "apimart",
    imageModel: "gpt-image-2",
    anchorCount: 9,
    validationEnabled: true,
    repairRounds: 2,
    promptDetail: "full",
    relativeCost: 12,
    estimatedSecondsPerFrame: 150,
  },
};

export const TIER_ORDER: GenerationTier[] = [
  "swift",
  "balanced",
  "faithful",
  "cinematic",
];

export function isGenerationTier(value: unknown): value is GenerationTier {
  return typeof value === "string" && value in TIER_PROFILES;
}

export function resolveTier(value: unknown): TierProfile {
  return TIER_PROFILES[isGenerationTier(value) ? value : DEFAULT_TIER];
}

export function listTierProfiles(): TierProfile[] {
  return TIER_ORDER.map((id) => TIER_PROFILES[id]);
}

/**
 * Normalized positions of the anchor keyframes for a tier, symmetric around
 * NOW on the same `|p|^2.35` curve the client time rail uses. The client
 * pre-generates these and interpolates between them while scrubbing.
 */
export function anchorNormalizedPositions(tier: TierProfile): number[] {
  const sideCount = (tier.anchorCount - 1) / 2;
  if (sideCount <= 0) return [0];
  const positions: number[] = [];
  for (let step = sideCount; step >= 1; step -= 1) {
    positions.push(-(step / sideCount));
  }
  positions.push(0);
  for (let step = 1; step <= sideCount; step += 1) {
    positions.push(step / sideCount);
  }
  return positions;
}
