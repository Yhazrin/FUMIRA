/**
 * Continuous change budget.
 *
 * The old prompt bucketed time into five prose bands (<1 day, <1 year, <10y,
 * <50y, >=50y), so a continuous time rail produced discontinuous instructions.
 * This maps `offsetDays` to a per-layer 0-100 scalar on a log-compressed curve,
 * which the compiler renders as a short quantitative block instead of prose.
 */

const MAXIMUM_OFFSET_YEARS = 100;
const PROGRESS_DENOMINATOR = Math.log10(1 + MAXIMUM_OFFSET_YEARS);

export type ChangeLayer =
  | "vegetation"
  | "humanUse"
  | "surfaces"
  | "builtEnvironment"
  | "terrain"
  | "principalSubject";

/**
 * `ceiling` is the budget at the full +/-100 year range. `gamma` shapes how
 * early the layer starts moving: <1 reacts fast, >1 needs decades.
 */
const LAYER_CURVES: Record<ChangeLayer, { ceiling: number; gamma: number; label: string }> = {
  vegetation: { ceiling: 85, gamma: 0.65, label: "vegetation & natural growth" },
  humanUse: { ceiling: 80, gamma: 0.8, label: "people, vehicles & use traces" },
  surfaces: { ceiling: 75, gamma: 1.0, label: "surfaces, materials & wear" },
  builtEnvironment: { ceiling: 90, gamma: 1.9, label: "buildings & infrastructure" },
  terrain: { ceiling: 45, gamma: 2.6, label: "terrain & landform" },
  principalSubject: { ceiling: 70, gamma: 1.1, label: "principal subject" },
};

/** Layers that must never move, regardless of time offset. */
export const LOCKED_LAYERS = ["camera & framing", "weather, season & light direction"];

export interface ChangeBudget {
  offsetDays: number;
  offsetYears: number;
  /** 0 at NOW, 1 at the +/-100 year bound. */
  progress: number;
  direction: "past" | "future" | "now";
  layers: Record<ChangeLayer, number>;
  /** Coarse label for logs and telemetry, derived from the same curve. */
  magnitude: "none" | "subtle" | "moderate" | "major" | "transformative";
}

export function computeChangeBudget(offsetDays: number): ChangeBudget {
  const safeDays = Number.isFinite(offsetDays) ? offsetDays : 0;
  const offsetYears = safeDays / 365.25;
  const absYears = Math.min(Math.abs(offsetYears), MAXIMUM_OFFSET_YEARS);
  const progress =
    Math.abs(safeDays) < 1
      ? // Sub-day offsets stay in a near-zero band so NOW is visually stable.
        (Math.abs(safeDays) / 1) * (Math.log10(1 + 1 / 365.25) / PROGRESS_DENOMINATOR)
      : Math.log10(1 + absYears) / PROGRESS_DENOMINATOR;

  const layers = {} as Record<ChangeLayer, number>;
  for (const [layer, curve] of Object.entries(LAYER_CURVES) as Array<
    [ChangeLayer, (typeof LAYER_CURVES)[ChangeLayer]]
  >) {
    layers[layer] = Math.round(curve.ceiling * Math.pow(progress, curve.gamma));
  }

  return {
    offsetDays: safeDays,
    offsetYears,
    progress,
    direction: Math.abs(safeDays) < 1 / 48 ? "now" : safeDays < 0 ? "past" : "future",
    layers,
    magnitude: magnitudeFor(progress),
  };
}

function magnitudeFor(progress: number): ChangeBudget["magnitude"] {
  if (progress <= 0.01) return "none";
  if (progress < 0.2) return "subtle";
  if (progress < 0.45) return "moderate";
  if (progress < 0.75) return "major";
  return "transformative";
}

/**
 * Render the budget as a compact, positive, quantitative prompt block.
 * Detail level trims the block for the cheaper tiers.
 */
export function renderChangeBudget(
  budget: ChangeBudget,
  detail: "compact" | "standard" | "full" = "standard"
): string {
  const directionLine =
    budget.direction === "now"
      ? "Target is the present moment: keep the scene essentially unchanged."
      : budget.direction === "future"
        ? "Move forward in time: accumulate growth, wear, maintenance and replacement."
        : "Move backward in time: reverse wear and growth, and remove anything that did not exist yet.";

  const entries = (Object.keys(LAYER_CURVES) as ChangeLayer[])
    .map((layer) => `${LAYER_CURVES[layer].label}: ${budget.layers[layer]}`)
    .join("\n- ");

  if (detail === "compact") {
    const dominant = dominantLayers(budget, 3)
      .map((layer) => `${LAYER_CURVES[layer].label} ${budget.layers[layer]}`)
      .join(", ");
    return [
      "CHANGE BUDGET (0-100, how much each layer may differ)",
      directionLine,
      `- ${dominant}`,
      `- locked at 0: ${LOCKED_LAYERS.join(", ")}`,
    ].join("\n");
  }

  const lines = [
    "CHANGE BUDGET (0-100, how much each layer may differ)",
    directionLine,
    `- ${entries}`,
    `- locked at 0: ${LOCKED_LAYERS.join(", ")}`,
  ];

  if (detail === "full") {
    lines.push(
      "Treat these as targets, not maxima to skip: every layer above 15 must show visible, causally consistent evidence."
    );
  }

  return lines.join("\n");
}

function dominantLayers(budget: ChangeBudget, count: number): ChangeLayer[] {
  return (Object.keys(budget.layers) as ChangeLayer[])
    .sort((a, b) => budget.layers[b] - budget.layers[a])
    .slice(0, count);
}
