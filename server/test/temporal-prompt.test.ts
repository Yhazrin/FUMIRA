import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { config } from "../src/config.js";
import { buildPrompt } from "../src/prompt.js";
import {
  makeTemporalImagePrompt,
  measureTemporalPromptBranches,
} from "../src/temporalImagePrompt.js";
import type { TimePositionPayload } from "../src/types.js";

const samples: Record<string, TimePositionPayload> = {
  "near-now": {
    normalized: 0.5,
    offsetDays: 0.2,
    offsetYears: 0.0005,
    compactLabel: "此刻",
  },
  "future-<1y": {
    normalized: 0.55,
    offsetDays: 120,
    offsetYears: 0.33,
    compactLabel: "4 个月后",
  },
  "future-1-10y": {
    normalized: 0.65,
    offsetDays: 5 * 365.25,
    offsetYears: 5,
    compactLabel: "5 年后",
  },
  "future-10-50y": {
    normalized: 0.8,
    offsetDays: 25 * 365.25,
    offsetYears: 25,
    compactLabel: "25 年后",
  },
  "future-50+": {
    normalized: 1,
    offsetDays: 100 * 365.25,
    offsetYears: 100,
    compactLabel: "100 年后",
  },
  "past-10-50y": {
    normalized: 0.2,
    offsetDays: -30 * 365.25,
    offsetYears: -30,
    compactLabel: "30 年前",
  },
  "past-50+": {
    normalized: 0,
    offsetDays: -100 * 365.25,
    offsetYears: -100,
    compactLabel: "100 年前",
  },
};

describe("temporal image prompt V2", () => {
  it("keeps every span/direction branch under the soft ceiling", () => {
    const branches = measureTemporalPromptBranches(2_200);
    for (const branch of branches) {
      assert.ok(
        branch.ok,
        `${branch.branch} length ${branch.length} exceeds soft ceiling`
      );
    }
  });

  it("builds panoramic Chinese V2 prompts with relaxed causal bans", () => {
    const prompt = makeTemporalImagePrompt(samples["future-10-50y"]);
    assert.match(prompt, /精确目标时间「25 年后」/);
    assert.match(prompt, /空间锚点锁定/);
    assert.match(prompt, /不能在改变一个主体后停止/);
    assert.match(prompt, /10至50年/);
    assert.match(prompt, /无关、抢镜或缺乏时间因果依据/);
    assert.ok(prompt.length < config.promptMaxChars);
  });

  it("fits V2 core + upgraded footer under promptMaxChars", () => {
    for (const branch of measureTemporalPromptBranches()) {
      const time = samples[branch.branch];
      assert.ok(time, branch.branch);
      const built = buildPrompt({
        template: "{{prompt}}",
        corePrompt: makeTemporalImagePrompt(time),
        timePosition: time,
        aspectRatio: "3:4",
      });
      assert.equal(built.truncated, false, `${branch.branch} truncated at ${built.charCount}`);
      assert.ok(built.charCount <= config.promptMaxChars);
      assert.match(built.prompt, /Do not use one person or one object/);
    }
  });
});
