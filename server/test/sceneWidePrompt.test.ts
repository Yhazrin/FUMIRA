import assert from "node:assert/strict";
import { describe, it } from "node:test";

process.env.MINIMAX_MOCK = "true";

const { compilePrompt } = await import("../src/promptCompiler.js");
const { promoteToV2 } = await import("../src/storyCopy.js");

import type {
  GenerationContext,
  SceneUnderstandingPayload,
  StoryCopyConstraints,
  TemporalStoryPayload,
  TemporalStoryPayloadV2,
  TimePositionPayload,
} from "../src/types.js";

const constraints: StoryCopyConstraints = {
  title: 16,
  logline: 56,
  presentTruth: 72,
  identityRule: 48,
  beatTitle: 14,
  beatNarrative: 72,
  visualPrompt: 110,
};

function understanding(
  overrides?: Partial<SceneUnderstandingPayload>
): SceneUnderstandingPayload {
  return {
    summary: "人物站在城市车站前，前景有铺装地面，中景有树木，背景有站房与天际线",
    locationType: "城市车站",
    visualMood: "真实自然的城市日常",
    timeClues: ["现代铺装", "年轻行道树", "当前车型"],
    changeDrivers: ["人物成长", "树木生长", "设施翻修", "城市扩张"],
    subjects: [
      {
        name: "前景人物",
        confidence: 0.98,
        identityRule: "保留人物身份、站位与轮廓，允许年龄和服装变化",
      },
      {
        name: "前景铺装",
        confidence: 0.91,
        identityRule: "保留道路透视，允许磨损、维修和材料替换",
      },
      {
        name: "中景树木",
        confidence: 0.93,
        identityRule: "保留种植位置，允许自然生长、死亡或合理替换",
      },
      {
        name: "背景站房",
        confidence: 0.95,
        identityRule: "保留主体位置和识别轮廓，允许翻修与扩建",
      },
    ],
    ...overrides,
  };
}

function story(
  overrides?: Partial<TemporalStoryPayloadV2>
): TemporalStoryPayloadV2 {
  return {
    schemaVersion: "temporal-story.v2",
    title: "站前的时间回声",
    logline: "同一车站在人物成长与城市更新中持续变化",
    presentTruth: "人物、树木、铺装、站房和远处城市共同组成当前车站景象",
    identityRules: ["锁定机位和主要空间拓扑", "保留人物身份与车站识别轮廓"],
    beats: [
      { anchorYears: -100, title: "百年前", narrative: "道路和站场尚未成形", visualPrompt: "土路、低矮建筑、稀疏植被" },
      { anchorYears: -30, title: "三十年前", narrative: "旧站房承担早期客流", visualPrompt: "旧铺装、早期车辆、幼树" },
      { anchorYears: -10, title: "十年前", narrative: "站前空间逐步完善", visualPrompt: "较新铺装、年轻树木、较低天际线" },
      { anchorYears: 0, title: "现在", narrative: "人物站在当前车站前", visualPrompt: "保持当前真实状态" },
      { anchorYears: 10, title: "十年后", narrative: "树冠扩大，设施开始更新", visualPrompt: "成熟树冠、更新灯具、轻度翻修" },
      { anchorYears: 30, title: "三十年后", narrative: "车站与城市共同扩展", visualPrompt: "扩建站房、密集天际线、新交通设施" },
      { anchorYears: 100, title: "百年后", narrative: "站址经历重建与生态更替", visualPrompt: "重建结构、成熟生态、时代基础设施" },
    ],
    targetBeat: {
      anchorYears: 25,
      title: "二十五年后",
      narrative: "人物自然变老，车站翻修，树冠成熟，城市背景增密",
      visualPrompt: "人物增龄；铺装翻修；树冠扩大；站房升级；车辆与天际线同步更新",
    },
    ...overrides,
  };
}

function context(
  storyOverrides?: Partial<TemporalStoryPayloadV2>,
  understandingOverrides?: Partial<SceneUnderstandingPayload>
): GenerationContext {
  return {
    schemaVersion: "generation-context.v2",
    understanding: understanding(understandingOverrides),
    story: story(storyOverrides),
    generationMode: "captured_target",
  };
}

function time(offsetYears = 25): TimePositionPayload {
  return {
    normalized: 0.5,
    offsetDays: offsetYears * 365.25,
    offsetYears,
    compactLabel: `${Math.abs(offsetYears)} 年${offsetYears < 0 ? "前" : "后"}`,
  };
}

describe("scene-wide temporal prompt contract", () => {
  it("always retains exact temporal changes and whole-scene coverage", () => {
    const result = compilePrompt({
      context: context(),
      timePosition: time(),
      aspectRatio: "3:4",
    });

    assert.ok(result.prompt.includes("TEMPORAL CHANGES"));
    assert.ok(result.prompt.includes("SCENE-WIDE COVERAGE"));
    assert.ok(result.prompt.includes("TEMPORAL REALISM"));
    assert.ok(result.prompt.includes("人物增龄"));
    assert.ok(result.prompt.includes("铺装翻修"));
    assert.ok(result.prompt.includes("站房升级"));
    assert.ok(result.charCount <= 1500);
  });

  it("keeps scene-wide contracts under extreme prompt pressure", () => {
    const long = "极长的场景变化与身份规则描述".repeat(150);
    const result = compilePrompt({
      context: context(
        {
          presentTruth: long,
          identityRules: Array(8).fill(long),
          targetBeat: {
            anchorYears: 25,
            title: "二十五年后",
            narrative: long,
            visualPrompt: long,
          },
        },
        {
          summary: long,
          visualMood: long,
          changeDrivers: Array(8).fill(long),
          subjects: Array(6).fill({
            name: "环境区域",
            confidence: 0.9,
            identityRule: long,
          }),
        }
      ),
      timePosition: time(),
      aspectRatio: "3:4",
    });

    assert.ok(result.charCount <= 1500);
    assert.ok(result.prompt.includes("EDIT OBJECTIVE"));
    assert.ok(result.prompt.includes("PRESERVE"));
    assert.ok(result.prompt.includes("TEMPORAL CHANGES"));
    assert.ok(result.prompt.includes("SCENE-WIDE COVERAGE"));
    assert.ok(result.prompt.includes("TEMPORAL REALISM"));
    assert.ok(result.prompt.includes("DO NOT"));
  });

  it("removes blanket rules that freeze subject count and environmental additions", () => {
    const result = compilePrompt({
      context: context(),
      timePosition: time(),
      aspectRatio: "3:4",
    });

    assert.ok(!result.prompt.includes("Keep the same principal subjects and subject count"));
    assert.ok(!result.prompt.includes("Do not add unrelated people, vehicles, animals or buildings."));
    assert.ok(result.prompt.includes("Do not transform only one salient"));
  });
});

describe("strict exact target promotion", () => {
  it("rejects stories that omit targetBeat", () => {
    const legacy: TemporalStoryPayload = {
      title: "缺少目标节点",
      logline: "错误响应",
      presentTruth: "当前场景",
      identityRules: [],
      beats: story().beats,
    };

    assert.throws(
      () => promoteToV2(legacy, 25, constraints),
      /missing_exact_target_beat/
    );
  });

  it("uses program-authoritative target years", () => {
    const promoted = promoteToV2(story(), 25.25, constraints);
    assert.equal(promoted.targetBeat.anchorYears, 25.25);
  });
});
