import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  computeChangeBudget,
  renderChangeBudget,
  type ChangeLayer,
} from "../src/changeBudget.js";
import { anchorNormalizedPositions, TIER_PROFILES, resolveTier } from "../src/tiers.js";

const YEAR_DAYS = 365.25;

describe("change budget", () => {
  it("is zero at NOW and saturates at the 100 year bound", () => {
    const now = computeChangeBudget(0);
    for (const value of Object.values(now.layers)) {
      assert.equal(value, 0);
    }
    assert.equal(now.direction, "now");
    assert.equal(now.magnitude, "none");

    const century = computeChangeBudget(100 * YEAR_DAYS);
    assert.equal(century.layers.builtEnvironment, 90);
    assert.equal(century.layers.vegetation, 85);
    assert.equal(century.magnitude, "transformative");
  });

  it("is monotonic and continuous along the time rail", () => {
    const layers: ChangeLayer[] = [
      "vegetation",
      "humanUse",
      "surfaces",
      "builtEnvironment",
      "terrain",
      "principalSubject",
    ];
    // Step through the rail the way a user drags it, not through raw days:
    // the rail is `36525 * |p|^2.35`, so equal drag distance is the invariant.
    const step = 0.005;
    const daysFor = (p: number) => 36_525 * Math.pow(p, 2.35);
    let previous = computeChangeBudget(0);
    for (let p = step; p <= 1 + 1e-9; p += step) {
      const current = computeChangeBudget(daysFor(p));
      for (const layer of layers) {
        assert.ok(
          current.layers[layer] >= previous.layers[layer],
          `${layer} regressed at p=${p.toFixed(3)}`
        );
        assert.ok(
          current.layers[layer] - previous.layers[layer] <= 3,
          `${layer} jumped ${current.layers[layer] - previous.layers[layer]} at p=${p.toFixed(3)}`
        );
      }
      previous = current;
    }
    assert.equal(previous.layers.builtEnvironment, 90);
  });

  it("lets fast layers move long before slow layers do", () => {
    const oneYear = computeChangeBudget(YEAR_DAYS);
    assert.ok(oneYear.layers.vegetation > 15);
    assert.ok(oneYear.layers.builtEnvironment < 10);

    const fiftyYears = computeChangeBudget(50 * YEAR_DAYS);
    assert.ok(fiftyYears.layers.builtEnvironment > 50);
    assert.ok(fiftyYears.layers.terrain < fiftyYears.layers.builtEnvironment);
  });

  it("keeps sub-day offsets visually stable", () => {
    const hours = computeChangeBudget(0.5);
    for (const value of Object.values(hours.layers)) {
      assert.ok(value <= 1, "sub-day offset must not move any layer");
    }
  });

  it("labels direction and renders a bounded prompt block", () => {
    assert.equal(computeChangeBudget(-10 * YEAR_DAYS).direction, "past");
    assert.equal(computeChangeBudget(10 * YEAR_DAYS).direction, "future");

    const budget = computeChangeBudget(25 * YEAR_DAYS);
    const compact = renderChangeBudget(budget, "compact");
    const full = renderChangeBudget(budget, "full");
    assert.ok(compact.length < full.length);
    assert.ok(full.includes("locked at 0"));
    assert.ok(full.length < 600);
  });
});

describe("generation tiers", () => {
  it("falls back to the balanced tier for unknown input", () => {
    assert.equal(resolveTier(undefined).id, "balanced");
    assert.equal(resolveTier("nope").id, "balanced");
    assert.equal(resolveTier("cinematic").id, "cinematic");
  });

  it("defaults to relay GPT-4o image on the standard tier", () => {
    assert.equal(TIER_PROFILES.balanced.imageProvider, "apimart");
    assert.equal(TIER_PROFILES.balanced.imageModel, "gpt-4o-image");
  });

  it("reserves the dedicated image editing model for the top tiers", () => {
    assert.equal(TIER_PROFILES.faithful.imageModel, "gpt-image-2");
    assert.equal(TIER_PROFILES.cinematic.imageModel, "gpt-image-2");
  });

  it("orders cost, anchors and repair budget monotonically", () => {
    const order = ["swift", "balanced", "faithful", "cinematic"] as const;
    for (let index = 1; index < order.length; index += 1) {
      const previous = TIER_PROFILES[order[index - 1]];
      const current = TIER_PROFILES[order[index]];
      assert.ok(current.relativeCost > previous.relativeCost);
      assert.ok(current.anchorCount > previous.anchorCount);
      assert.ok(current.repairRounds >= previous.repairRounds);
      assert.ok(
        current.estimatedSecondsPerFrame > previous.estimatedSecondsPerFrame
      );
    }
  });

  it("produces symmetric anchor positions including NOW", () => {
    for (const tier of Object.values(TIER_PROFILES)) {
      const positions = anchorNormalizedPositions(tier);
      assert.equal(positions.length, tier.anchorCount);
      assert.equal(positions[0], -1);
      assert.equal(positions.at(-1), 1);
      assert.ok(positions.includes(0));
      for (let index = 1; index < positions.length; index += 1) {
        assert.ok(positions[index] > positions[index - 1]);
      }
    }
  });
});
