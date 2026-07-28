import assert from "node:assert/strict";
import { describe, it } from "node:test";

process.env.MINIMAX_MOCK = "true";

const { compilePromptV3 } = await import("../src/promptCompilerV3.js");
const { buildV3ContextFromV2 } = await import("../src/temporalV3.js");

import type {
  ExactTarget,
  GenerationContext,
  TimePositionPayload,
} from "../src/types.js";

function context(): GenerationContext {
  const beats = [-100, -30, -10, 0, 10, 30, 100].map((anchorYears) => ({
    anchorYears,
    title: `${anchorYears}`,
    narrative: "同一地点连续变化",
    visualPrompt: "树木生长，建筑翻修，路面更新",
  }));
  return {
    schemaVersion: "generation-context.v2",
    generationMode: "captured_target",
    understanding: {
      summary: "旧照片中的街道",
      locationType: "城市街道",
      visualMood: "日光",
      timeClues: ["旧式店铺"],
      changeDrivers: ["建筑维护", "植被生长"],
      subjects: [
        { name: "街道建筑", confidence: 0.9, identityRule: "保持位置，允许翻修" },
        { name: "路边树木", confidence: 0.9, identityRule: "保持位置，允许生长" },
      ],
    },
    story: {
      schemaVersion: "temporal-story.v2",
      title: "街道时间",
      logline: "同一街道的时间演化",
      presentTruth: "源图可能并非今天拍摄",
      identityRules: ["保持机位"],
      beats,
      targetBeat: {
        anchorYears: 25,
        title: "二十五年后",
        narrative: "街道环境变化",
        visualPrompt: "建筑、路面、树木和标牌共同变化",
      },
    },
  };
}

function target(): ExactTarget {
  return {
    offsetDays: 25 * 365.25,
    targetDateISO: "2035-07-28",
    compactLabel: "25 年后",
  };
}

function time(sourceDateISO?: string): TimePositionPayload {
  return {
    normalized: 0.5,
    offsetDays: 25 * 365.25,
    offsetYears: 25,
    compactLabel: "25 年后",
    ...(sourceDateISO ? { sourceDateISO } : {}),
  };
}

describe("trusted temporal baseline", () => {
  it("does not present a calendar target when source date is unknown", () => {
    const position = time();
    const v3 = buildV3ContextFromV2({
      context: context(),
      timePosition: position,
      exactTarget: target(),
    });
    const compiled = compilePromptV3({
      context: v3,
      timePosition: position,
      aspectRatio: "3:4",
    });
    assert.ok(compiled.prompt.includes("25.00y relative to source"));
    assert.ok(!compiled.prompt.includes("2035-07-28"));
  });

  it("includes the calculated target date when source date is explicit", () => {
    const position = time("2010-07-28");
    const v3 = buildV3ContextFromV2({
      context: context(),
      timePosition: position,
      exactTarget: target(),
    });
    const compiled = compilePromptV3({
      context: v3,
      timePosition: position,
      aspectRatio: "3:4",
    });
    assert.ok(compiled.prompt.includes("2035-07-28"));
  });
});
