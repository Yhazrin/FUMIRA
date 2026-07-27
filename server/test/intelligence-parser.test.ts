import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  parseStoryResponse,
  parseUnderstandingResponse,
} from "../src/minimax/liveIntelligenceAdapter.js";

describe("live intelligence response parsing", () => {
  it("accepts fenced, nested, snake_case understanding JSON", () => {
    const parsed = parseUnderstandingResponse(`
      <think>{"summary":"reasoning placeholder"}</think>
      \`\`\`json
      {
        "result": {
          "scene_summary": "画面显示同一办公室在目标年份的可见状态。",
          "location_type": "办公室",
          "visual_mood": "自然纪实",
          "time_clues": ["设备外观变化"],
          "change_drivers": ["日常使用与更新"],
          "main_subjects": [{
            "subject_name": "桌面设备",
            "confidence": "92%",
            "identity_rule": "保留桌面位置、比例与机位"
          }]
        }
      }
      \`\`\`
    `);

    assert.ok(parsed);
    assert.equal(parsed.summary, "画面显示同一办公室在目标年份的可见状态。");
    assert.equal(parsed.locationType, "办公室");
    assert.equal(parsed.subjects[0]?.confidence, 0.92);
  });

  it("uses neutral optional-field fallbacks instead of discarding visible analysis", () => {
    const parsed = parseUnderstandingResponse(
      '{"description":"可见桌面、显示器与远处工位。","subjects":["桌面","显示器"]}'
    );

    assert.ok(parsed);
    assert.equal(parsed.locationType, "未判定");
    assert.equal(parsed.visualMood, "中性纪实");
    assert.equal(parsed.subjects.length, 2);
  });

  it("normalizes story aliases and selects the seven required anchors", () => {
    const anchors = ["-100年", "-30年", "-10年", "NOW", "+10年", "+30年", "+100年"];
    const response = JSON.stringify({
      story_title: "时间回声",
      summary: "同一场景沿可见线索连续变化。",
      present_truth: "当下仅作为保守推断基线。",
      continuity_rules: ["保持机位和空间关系"],
      timeline: [
        ...anchors.map((anchor) => ({
          year_offset: anchor,
          beat_title: `${anchor}节点`,
          story: "变化保持连续且有据可循。",
          image_prompt: "保持构图，仅呈现与该年代相称的可见变化。",
        })),
        {
          year_offset: 50,
          beat_title: "额外节点",
          story: "不会进入固定七节点。",
          image_prompt: "不会进入固定七节点。",
        },
      ],
    });

    const parsed = parseStoryResponse(response);
    assert.ok(parsed);
    assert.deepEqual(
      parsed.beats.map((beat) => beat.anchorYears),
      [-100, -30, -10, 0, 10, 30, 100]
    );
  });
});
