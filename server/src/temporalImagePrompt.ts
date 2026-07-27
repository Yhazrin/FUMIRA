import type {
  SceneUnderstandingPayload,
  StoryBeatPayload,
  TemporalStoryPayload,
  TimePositionPayload,
} from "./types.js";

/**
 * Authoritative first-pass / story-driven image prompts.
 * The iOS app must not assemble these strings for live generation.
 */

export function makeTemporalImagePrompt(time: TimePositionPayload): string {
  const years = Math.abs(time.offsetYears);
  const days = Math.abs(time.offsetDays);
  const label = time.compactLabel || "NOW";
  const offsetYears = Number.isFinite(time.offsetYears) ? time.offsetYears : 0;
  const offsetDaysRounded = Number.isFinite(time.offsetDays)
    ? Math.round(time.offsetDays)
    : 0;

  const directionRule =
    days < 1
      ? "目标接近此刻：画面应几乎不变，只修正极轻微且必要的时间一致性差异。"
      : time.offsetDays > 0
        ? "未来方向：按跨度累积现实可解释的维护、磨损、更新、植被生长、基础设施与使用方式变化；没有视觉依据时不要加入科幻设施。"
        : "过去方向：保守逆推材料、磨损、植被、设施与使用状态；移除目标年代尚未出现的元素，并依据现有空间结构推演其合理前身，避免时代错置。";

  const spanRule =
    days < 1
      ? "不足一天：原则上不产生可辨识结构变化。"
      : years < 1
        ? "一年以内：只允许细微使用痕迹、维护状态和自然生长差异。"
        : years < 10
          ? "1至10年：原图存在依据时，应在至少两个相关环境系统中体现协调变化。"
          : years < 50
            ? "10至50年：必须检查前景、中景和背景，使材料、植被、设施与使用方式形成统一年代状态。"
            : "50年以上：允许合理替换、消失、重建或生态演替，但必须保留关键空间结构、地形关系和可追溯历史痕迹。";

  return [
    `任务：将输入照片编辑为同一地点、同一机位在精确目标时间「${label}」拍摄的一张真实照片。时间偏移 ${offsetYears.toFixed(2)} 年（${offsetDaysRounded} 天）。`,
    "",
    "执行方式：先在内部完成“空间锚点锁定 → 全景分层 → 时间因果推演 → 年代一致性检查”，不要输出分析过程。",
    "",
    "空间连续性：保持原画幅、机位、焦段、透视、地平线、景深、遮挡关系、主体相对位置和空间层级；不得裁切、旋转、扩图、换镜头或整体重构。优先锁定前景、中景、背景中至少三处可辨识锚点，如道路边界、墙体轮廓、门窗位置、树干或天际线，使目标图仍能一眼认出是同一场景。",
    "",
    "全景时间变化：必须检查整幅画面，而不是只修改最显眼的人或物。分别评估前景、中景、背景，以及建筑与基础设施、地表与材料、植被、可移动物、人物与活动痕迹。只改变有视觉依据或符合通用时间规律的部分，但不能在改变一个主体后停止；人物或单件物体不得成为中长跨度唯一的时间证据。原图存在相应内容时，中长跨度变化应分布在多个景深层和多个环境系统中，并保持同一年代、同一维护水平和同一因果链。",
    "",
    `时间方向：${directionRule}`,
    `跨度规则：${spanRule}`,
    "",
    "主体连续性：保持可见建筑、物件与人物的可辨识特征。人物仅在合理生命跨度内自然增龄或减龄；超出生命期限可自然缺席，不得以陌生人物替代。公共场景可维持原有人流规模和空间关系，但不得新增抢镜主体。",
    "",
    "事实边界：不编造具体地点历史、人物身份或重大事件。证据不足时保守推演，但仍须检查全画面的年代一致性，避免“主体变了、环境没变”或“环境各部分属于不同年代”。",
    "",
    "光影连续性：保持原天气、季节、昼夜、光向、色调、清晰度与摄影风格，除非目标时间只需要极轻微的自然差异。",
    "",
    `禁止：无关、抢镜或缺乏时间因果依据的人物、动物、车辆、建筑、设施、文字、数字、标志、边框、拼贴、水印、UI、插画感、科幻化、灾难化和过度戏剧化。输出一张完整、自然、可信、全场景年代一致的照片，只呈现「${label}」。`,
  ].join("\n");
}

/** Compress Scene Bible + target beat into a story-driven core prompt. */
export function compileStoryDrivenPrompt(params: {
  time: TimePositionPayload;
  understanding?: SceneUnderstandingPayload | null;
  story?: Pick<TemporalStoryPayload, "identityRules" | "logline" | "presentTruth"> | null;
  beat?: StoryBeatPayload | null;
}): string {
  const base = makeTemporalImagePrompt(params.time);
  const understanding = params.understanding;
  const beat = params.beat;
  if (!understanding && !beat) return base;

  const chunks: string[] = [base, "", "—— 场景圣经与目标状态（压缩）——"];

  if (understanding) {
    chunks.push(`场景基准：${compact(understanding.summary, 120)}`);
    if (understanding.locationType) {
      chunks.push(`地点类型：${compact(understanding.locationType, 28)}`);
    }
    if (understanding.cameraLock) {
      const lock = [
        understanding.cameraLock.viewpoint,
        understanding.cameraLock.lensAndPerspective,
        understanding.cameraLock.horizon,
        understanding.cameraLock.depthStructure,
      ]
        .map((part) => compact(part ?? "", 48))
        .filter(Boolean)
        .join("；");
      if (lock) chunks.push(`机位锁定：${lock}`);
    }
    if (understanding.spatialAnchors?.length) {
      const anchors = understanding.spatialAnchors
        .slice(0, 4)
        .map((anchor) => {
          const bits = [
            compact(anchor.name, 18),
            compact(anchor.depth ?? "", 12),
            compact(anchor.identityLock || anchor.geometry || anchor.position || "", 40),
          ].filter(Boolean);
          return bits.join("/");
        })
        .join("｜");
      if (anchors) chunks.push(`空间锚点：${anchors}`);
    }
    if (understanding.hardConstraints?.length) {
      chunks.push(
        `硬约束：${understanding.hardConstraints
          .slice(0, 4)
          .map((item) => compact(item, 40))
          .join("；")}`
      );
    }
    const subjectIdentity = understanding.subjects
      .slice(0, 4)
      .map((subject) => compact(subject.identityRule, 40))
      .filter(Boolean)
      .join("；");
    if (subjectIdentity) chunks.push(`主体连续性：${subjectIdentity}`);
    const drivers = (understanding.changeDrivers ?? [])
      .slice(0, 4)
      .map((item) => compact(item, 28))
      .filter(Boolean)
      .join("；");
    if (drivers) chunks.push(`允许变化驱动：${drivers}`);
  }

  if (params.story?.identityRules?.length) {
    chunks.push(
      `故事连续性：${params.story.identityRules
        .slice(0, 4)
        .map((rule) => compact(rule, 40))
        .join("；")}`
    );
  } else if (params.story?.logline) {
    chunks.push(`故事连续性：${compact(params.story.logline, 80)}`);
  }

  if (beat) {
    chunks.push(`目标拍叙事：${compact(beat.narrative, 100)}`);
    if (beat.transitionCause) {
      chunks.push(`变迁原因：${compact(beat.transitionCause, 80)}`);
    }
    const layerDeltas = [
      ["前景", beat.foregroundDelta],
      ["中景", beat.midgroundDelta],
      ["背景", beat.backgroundDelta],
      ["主体", beat.subjectDelta],
      ["环境", beat.environmentDelta],
    ]
      .map(([label, value]) =>
        value ? `${label}:${compact(value, 56)}` : ""
      )
      .filter(Boolean)
      .join("；");
    if (layerDeltas) chunks.push(`分层变化：${layerDeltas}`);
    if (beat.unchangedAnchors?.length) {
      chunks.push(
        `保持锚点：${beat.unchangedAnchors
          .slice(0, 4)
          .map((item) => compact(item, 28))
          .join("；")}`
      );
    }
    if (beat.visualPrompt) {
      chunks.push(`年代画面：${compact(beat.visualPrompt, 160)}`);
    }
  }

  chunks.push(
    "编译规则：以上结构化状态与主 Prompt 一并生效；每个时间点都从同一源图推演，禁止链式漂移；只改变有依据的部分，但不能在改变一个主体后停止。"
  );

  return chunks.join("\n");
}

export function pickNearestBeat(
  story: TemporalStoryPayload | null | undefined,
  offsetYears: number
): StoryBeatPayload | null {
  if (!story?.beats?.length) return null;
  return story.beats.reduce((best, beat) =>
    Math.abs(beat.anchorYears - offsetYears) < Math.abs(best.anchorYears - offsetYears)
      ? beat
      : best
  );
}

/** Smoke-check every direction/span branch stays under a soft ceiling. */
export function measureTemporalPromptBranches(
  softLimit = 2_200
): Array<{ branch: string; length: number; ok: boolean }> {
  const samples: Array<{ branch: string; time: TimePositionPayload }> = [
    {
      branch: "near-now",
      time: {
        normalized: 0.5,
        offsetDays: 0.2,
        offsetYears: 0.0005,
        compactLabel: "此刻",
      },
    },
    {
      branch: "future-<1y",
      time: {
        normalized: 0.55,
        offsetDays: 120,
        offsetYears: 0.33,
        compactLabel: "4 个月后",
      },
    },
    {
      branch: "future-1-10y",
      time: {
        normalized: 0.65,
        offsetDays: 5 * 365.25,
        offsetYears: 5,
        compactLabel: "5 年后",
      },
    },
    {
      branch: "future-10-50y",
      time: {
        normalized: 0.8,
        offsetDays: 25 * 365.25,
        offsetYears: 25,
        compactLabel: "25 年后",
      },
    },
    {
      branch: "future-50+",
      time: {
        normalized: 1,
        offsetDays: 100 * 365.25,
        offsetYears: 100,
        compactLabel: "100 年后",
      },
    },
    {
      branch: "past-10-50y",
      time: {
        normalized: 0.2,
        offsetDays: -30 * 365.25,
        offsetYears: -30,
        compactLabel: "30 年前",
      },
    },
    {
      branch: "past-50+",
      time: {
        normalized: 0,
        offsetDays: -100 * 365.25,
        offsetYears: -100,
        compactLabel: "100 年前",
      },
    },
  ];

  return samples.map(({ branch, time }) => {
    const length = makeTemporalImagePrompt(time).length;
    return { branch, length, ok: length <= softLimit };
  });
}

function compact(value: string, maximum: number): string {
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length <= maximum) return normalized;
  if (maximum <= 1) return normalized.slice(0, maximum);
  return `${normalized.slice(0, maximum - 1)}…`;
}
