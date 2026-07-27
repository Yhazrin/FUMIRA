import { config } from "../config.js";
import { outboundFetch } from "../http/outboundFetch.js";
import type {
  MiniMaxIntelligenceAdapter,
  MiniMaxIntelligenceResult,
  SceneUnderstandingPayload,
  SpatialAnchorPayload,
  StoryBeatPayload,
  StoryCopyConstraints,
  TemporalLayerPayload,
  TemporalStoryPayload,
  UnderstandingCopyConstraints,
} from "../types.js";


type JSONRecord = Record<string, unknown>;

/// Uses the same documented MiniMax Coding Plan VLM endpoint that powers the
/// official `understand_image` MCP tool, then uses MiniMax M3 for the story.
/// Keys remain in the relay process; images and prompts are never logged.
export class LiveMiniMaxIntelligenceAdapter implements MiniMaxIntelligenceAdapter {
  constructor(
    private readonly apiKey: string,
    private readonly vlmApiKey: string = ""
  ) {}

  async analyzeImage(input: {
    imageDataUrl: string;
    targetTime: { offsetYears: number; compactLabel: string };
    copyConstraints: UnderstandingCopyConstraints;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<SceneUnderstandingPayload>> {
    const endpoint = `${config.minimaxApiBaseUrl}/v1/coding_plan/vlm`;
    const response = await this.requestJSON(endpoint, {
      prompt: [
        `This image is the SOURCE photograph at the present moment (NOW). Build a Scene Bible that will drive temporal generation toward ${input.targetTime.compactLabel} (${input.targetTime.offsetYears.toFixed(2)} years from now).`,
        "Do not describe a already-generated future/past result; lock what is visibly true right now.",
        "Return JSON only, with this exact shape:",
        '{"summary":"","locationType":"","visualMood":"","timeClues":[""],"changeDrivers":[""],"subjects":[{"name":"","confidence":0.0,"identityRule":""}],"cameraLock":{"viewpoint":"","lensAndPerspective":"","horizon":"","depthStructure":""},"spatialAnchors":[{"name":"","depth":"foreground|midground|background","position":"","geometry":"","identityLock":""}],"temporalLayers":[{"layer":"architecture|infrastructure|surfaces|vegetation|movableObjects|peopleAndUse","visibleEvidence":"","pastPotential":"","futurePotential":"","confidence":0.0}],"storySeeds":[""],"hardConstraints":[""]}',
        "summary must describe only what is visibly present, including foreground/midground/background structure and camera viewpoint.",
        "cameraLock must freeze viewpoint, lens/perspective, horizon, and depth structure so later generations cannot drift.",
        "spatialAnchors: list 3-6 recognizable anchors across depth layers. identityLock must keep geometry/position recognizable across time.",
        "temporalLayers must cover architecture, infrastructure, surfaces, vegetation, movableObjects, and peopleAndUse when visible. Check every layer; decide what may change vs must stay. Do not invent unseen facilities.",
        "timeClues are present-day visible age cues. changeDrivers and storySeeds are bounded hypotheses for later temporal evolution, not asserted events.",
        "List 2-6 visually important subjects in foreground-to-background order. Each identityRule must lock spatial position, relative scale, silhouette/material/color when visible, and the feature allowed to age or change.",
        "hardConstraints must include composition locks and forbid unrelated or attention-stealing subjects without causal basis.",
        "Confidence measures visual certainty, not narrative importance. Omit uncertain subjects instead of inventing them.",
        `Strict character budgets (punctuation counts): summary <= ${input.copyConstraints.summary}; locationType <= ${input.copyConstraints.locationType}; visualMood <= ${input.copyConstraints.visualMood}; each timeClue <= ${input.copyConstraints.timeClue}; each changeDriver <= ${input.copyConstraints.changeDriver}; each subject name <= ${input.copyConstraints.subjectName}; each identityRule <= ${input.copyConstraints.identityRule}.`,
        "Use concise Simplified Chinese and complete short phrases. Never identify a person by name or infer sensitive traits.",
      ].join(" "),
      image_url: input.imageDataUrl,
    }, "vision", this.vlmApiKey || this.apiKey);

    if (!response.ok) return response;
    let understanding = parseUnderstandingResponse(response.value);
    if (!understanding) {
      const retry = await this.requestJSON(endpoint, {
        prompt: [
          `Analyze this SOURCE photograph at NOW for Scene Bible fields used to reach ${input.targetTime.compactLabel}.`,
          "Your previous response could not be parsed. Return one raw JSON object only: no markdown, code fence, commentary, or reasoning.",
          'Use exactly {"summary":"","locationType":"","visualMood":"","timeClues":[],"changeDrivers":[],"subjects":[{"name":"","confidence":0.0,"identityRule":""}],"cameraLock":{"viewpoint":"","lensAndPerspective":"","horizon":"","depthStructure":""},"spatialAnchors":[{"name":"","depth":"","position":"","geometry":"","identityLock":""}],"temporalLayers":[{"layer":"","visibleEvidence":"","pastPotential":"","futurePotential":"","confidence":0.0}],"storySeeds":[],"hardConstraints":[]}.',
          "All three string fields are required. Include 2-6 certain visible subjects. Use concise Simplified Chinese and do not invent unseen events or identities.",
        ].join(" "),
        image_url: input.imageDataUrl,
      }, "vision", this.vlmApiKey || this.apiKey);
      if (!retry.ok) return retry;
      understanding = parseUnderstandingResponse(retry.value);
    }
    if (!understanding) return invalidJSON("图片理解返回格式异常，请重试。");
    return { ok: true, value: understanding };
  }

  async writeStory(input: {
    understanding: SceneUnderstandingPayload;
    targetTime: { offsetYears: number; compactLabel: string };
    copyConstraints: StoryCopyConstraints;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<TemporalStoryPayload>> {
    const requestBody = (isStructureRetry: boolean): JSONRecord => ({
      model: config.minimaxStoryModel,
      // Seven narratives plus layered deltas exceed 1,600 tokens in Chinese.
      // M3 has thinking disabled here, so 4,000 leaves ample room.
      max_tokens: 4_000,
      thinking: { type: "disabled" },
      system: [
        "You are the temporal narrative director of a time-camera experience.",
        "Create one evidence-grounded story whose world, place, subjects, and environmental state evolve continuously across time.",
        "A timeline is not seven independent captions: every beat must inherit the previous state, introduce a visible causal transition, and prepare the next state.",
        "Treat the entire scene as a system, including foreground, midground, background, architecture, surfaces, vegetation, infrastructure, movable objects, and traces of human use.",
        "Human emotion may provide meaning, but one person must not become the only carrier of time.",
        "Preserve spatial anchors and camera continuity while allowing historically plausible scene-wide evolution.",
        "Do not add unrelated, attention-stealing, or causally unsupported people, vehicles, buildings, or facilities.",
        "Output JSON only, never markdown or reasoning.",
      ].join(" "),
      messages: [
        {
          role: "user",
          content: [{
            type: "text",
            text: [
              isStructureRetry
                ? "The previous response could not be parsed. Return one raw JSON object only, with no markdown, code fence, commentary, or omitted field."
                : "Based only on this SOURCE Scene Bible, write one coherent and causally continuous time story for a camera app. Treat observed details as present-day facts and changeDrivers/storySeeds only as bounded hypotheses.",
              `Scene Bible: ${JSON.stringify(input.understanding)}`,
              `Target browsing time is ${input.targetTime.compactLabel} (${input.targetTime.offsetYears.toFixed(2)} years from now). The seven-beat timeline must remain continuous through that offset: adjacent beat narratives and visual prompts must interpolate without contradicting the Scene Bible.`,
              "Build one coherent temporal arc with a beginning, accumulation, turning point, and emotional resolution.",
              "Each beat narrative must state what changed since the previous beat, what caused it, and what remains recognizable.",
              "Each visualPrompt must separately account for foreground, midground, background, environmental systems, and main-subject continuity.",
              "Do not write seven generic descriptions of old, modern, and futuristic scenery.",
              "Do not let aging a person or object serve as the only evidence of elapsed time.",
              "Changes introduced in one beat persist into later beats unless a later beat explicitly replaces, removes, repairs, or transforms them.",
              "All beats must share one spatial history and one causal chain.",
              "Return exactly this JSON shape in Simplified Chinese:",
              '{"title":"","logline":"","presentTruth":"","identityRules":[""],"beats":[{"anchorYears":-100,"title":"","narrative":"","transitionCause":"","unchangedAnchors":[""],"foregroundDelta":"","midgroundDelta":"","backgroundDelta":"","subjectDelta":"","environmentDelta":"","visualPrompt":""}]}.',
              "Provide exactly seven beats at -100,-30,-10,0,10,30,100.",
              "The 0-year beat and presentTruth are a conservative inferred baseline grounded in the source Scene Bible. Avoid unsupported specifics. Past beats must avoid anachronisms; future beats may only accumulate changes justified by earlier beats and changeDrivers.",
              "identityRules must consolidate the Scene Bible identity locks without contradiction or invented detail.",
              `Strict character budgets (punctuation counts): title <= ${input.copyConstraints.title}; logline <= ${input.copyConstraints.logline}; presentTruth <= ${input.copyConstraints.presentTruth}; each identityRule <= ${input.copyConstraints.identityRule}; each beat title <= ${input.copyConstraints.beatTitle}; each narrative <= ${input.copyConstraints.beatNarrative}; each visualPrompt <= ${input.copyConstraints.visualPrompt}.`,
              "Keep people and places anonymous; preserve composition and visible identity rules. Prefer complete short sentences instead of filling the limit.",
            ].join("\n"),
          }],
        },
      ],
    });
    const response = await this.requestStoryJSON(requestBody(false));

    if (!response.ok) return response;
    let story = parseStoryResponse(response.value);
    if (!story) {
      const retry = await this.requestStoryJSON(requestBody(true));
      if (!retry.ok) return retry;
      story = parseStoryResponse(retry.value);
    }
    if (!story) return invalidJSON("时间故事返回格式异常，请重试。");
    return { ok: true, value: story };
  }

  private async requestJSON(
    url: string,
    body: JSONRecord,
    kind: "vision" | "story",
    apiKey: string
  ): Promise<MiniMaxIntelligenceResult<string>> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 90_000);
    try {
      const response = await outboundFetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "MM-API-Source": "Minimax-MCP",
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      const payload = await response.json().catch(() => null) as JSONRecord | null;
      const base = asRecord(payload?.base_resp);
      const statusCode = typeof base?.status_code === "number" ? base.status_code : -1;
      const statusMsg = typeof base?.status_msg === "string" ? base.status_msg : undefined;
      if (!response.ok || statusCode !== 0) {
        return {
          ok: false,
          errorCode: statusCode === 1004 ? "unauthorized" : `${kind}_unavailable`,
          userMessage: kind === "vision" ? "图片理解服务暂不可用，请重试。" : "时间故事服务暂不可用，请重试。",
          retryable: statusCode !== 2013 && statusCode !== 1004,
          statusMsg,
        };
      }

      const text = kind === "vision"
        ? (typeof payload?.content === "string" ? payload.content : "")
        : messageContent(payload);
      if (!text) return invalidJSON(kind === "vision" ? "图片理解没有返回内容。" : "时间故事没有返回内容。");
      return { ok: true, value: text };
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 160) : "network_error";
      return {
        ok: false,
        errorCode: "intelligence_network",
        userMessage: kind === "vision" ? "无法连接图片理解服务，请检查网络后重试。" : "无法连接时间故事服务，请检查网络后重试。",
        retryable: true,
        statusMsg: message,
      };
    } finally {
      clearTimeout(timer);
    }
  }

  private async requestStoryJSON(body: JSONRecord): Promise<MiniMaxIntelligenceResult<string>> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 90_000);
    try {
      const response = await outboundFetch(`${config.minimaxApiBaseUrl}/anthropic/v1/messages`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      const payload = await response.json().catch(() => null) as JSONRecord | null;
      const base = asRecord(payload?.base_resp);
      const statusCode = typeof base?.status_code === "number" ? base.status_code : -1;
      const statusMsg = typeof base?.status_msg === "string" ? base.status_msg : undefined;
      if (!response.ok || statusCode !== 0) {
        return {
          ok: false,
          errorCode: statusCode === 1004 ? "unauthorized" : "story_unavailable",
          userMessage: "时间故事服务暂不可用，请重试。",
          retryable: statusCode !== 2013 && statusCode !== 1004,
          statusMsg,
        };
      }
      const text = anthropicTextContent(payload);
      if (!text) return invalidJSON("时间故事没有返回内容。");
      return { ok: true, value: text };
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 160) : "network_error";
      return {
        ok: false,
        errorCode: "intelligence_network",
        userMessage: "无法连接时间故事服务，请检查网络后重试。",
        retryable: true,
        statusMsg: message,
      };
    } finally {
      clearTimeout(timer);
    }
  }
}

function messageContent(payload: JSONRecord | null): string {
  const choices = payload?.choices;
  if (!Array.isArray(choices)) return "";
  const first = asRecord(choices[0]);
  const message = asRecord(first?.message);
  return typeof message?.content === "string" ? message.content : "";
}

function anthropicTextContent(payload: JSONRecord | null): string {
  const content = payload?.content;
  if (!Array.isArray(content)) return "";
  const textBlock = content.map(asRecord).find((block) => block?.type === "text");
  return typeof textBlock?.text === "string" ? textBlock.text : "";
}

function withoutReasoning(raw: string): string {
  return raw
    .replace(/<think>[\s\S]*?<\/think>/gi, "")
    .replace(/<think>[\s\S]*$/gi, "")
    .trim();
}

function parseJSONObjects(raw: string): JSONRecord[] {
  const objects: JSONRecord[] = [];
  for (let start = raw.indexOf("{"); start >= 0; start = raw.indexOf("{", start + 1)) {
    let depth = 0;
    let quoted = false;
    let escaped = false;
    for (let index = start; index < raw.length; index++) {
      const character = raw[index];
      if (quoted) {
        if (escaped) escaped = false;
        else if (character === "\\") escaped = true;
        else if (character === '"') quoted = false;
        continue;
      }
      if (character === '"') quoted = true;
      else if (character === "{") depth++;
      else if (character === "}") {
        depth--;
        if (depth === 0) {
          try {
            const parsed = asRecord(JSON.parse(raw.slice(start, index + 1)));
            if (parsed) objects.push(parsed);
          } catch {
            // A reasoning block can contain partial JSON; continue scanning.
          }
          break;
        }
      }
    }
  }
  return objects;
}

export function parseUnderstandingResponse(
  raw: string
): SceneUnderstandingPayload | null {
  return parseJSONObjects(withoutReasoning(raw))
    .map(parseUnderstanding)
    .find((value): value is SceneUnderstandingPayload => value !== null) ?? null;
}

function parseUnderstanding(value: JSONRecord): SceneUnderstandingPayload | null {
  const nested = asRecord(value.result) ?? asRecord(value.data) ?? value;
  const rawSubjects = arrayValue(nested, [
    "subjects",
    "mainSubjects",
    "main_subjects",
    "主体",
    "主要主体",
  ]);
  const summary = stringValue(nested, [
    "summary",
    "sceneSummary",
    "scene_summary",
    "description",
    "场景总结",
    "场景概述",
  ]);
  if (!summary) return null;
  const locationType = stringValue(nested, [
    "locationType",
    "location_type",
    "sceneType",
    "scene_type",
    "地点类型",
    "场景类型",
  ]) || "未判定";
  const visualMood = stringValue(nested, [
    "visualMood",
    "visual_mood",
    "mood",
    "视觉氛围",
    "画面氛围",
  ]) || "中性纪实";

  const cameraLockRecord = asRecord(valueFor(nested, ["cameraLock", "camera_lock", "机位锁定"]));
  const cameraLock = cameraLockRecord
    ? {
        viewpoint: stringValue(cameraLockRecord, ["viewpoint", "view", "视点"]) || undefined,
        lensAndPerspective:
          stringValue(cameraLockRecord, ["lensAndPerspective", "lens_and_perspective", "lens", "透视"])
          || undefined,
        horizon: stringValue(cameraLockRecord, ["horizon", "地平线"]) || undefined,
        depthStructure:
          stringValue(cameraLockRecord, ["depthStructure", "depth_structure", "depth", "景深结构"])
          || undefined,
      }
    : undefined;

  const spatialAnchors = arrayValue(nested, [
    "spatialAnchors",
    "spatial_anchors",
    "anchors",
    "空间锚点",
  ]).flatMap((rawAnchor): SpatialAnchorPayload[] => {
    const anchor = asRecord(rawAnchor);
    if (!anchor) return [];
    const name = stringValue(anchor, ["name", "名称"]);
    if (!name) return [];
    return [{
      name,
      depth: stringValue(anchor, ["depth", "layer", "景深"]) || undefined,
      position: stringValue(anchor, ["position", "位置"]) || undefined,
      geometry: stringValue(anchor, ["geometry", "几何"]) || undefined,
      identityLock: stringValue(anchor, ["identityLock", "identity_lock", "锁定"]) || undefined,
    }];
  }).slice(0, 8);

  const temporalLayers = arrayValue(nested, [
    "temporalLayers",
    "temporal_layers",
    "layers",
    "时间层",
  ]).flatMap((rawLayer): TemporalLayerPayload[] => {
    const layer = asRecord(rawLayer);
    if (!layer) return [];
    const name = stringValue(layer, ["layer", "name", "系统"]);
    if (!name) return [];
    return [{
      layer: name,
      visibleEvidence: stringValue(layer, ["visibleEvidence", "visible_evidence", "证据"]) || undefined,
      pastPotential: stringValue(layer, ["pastPotential", "past_potential", "过去"]) || undefined,
      futurePotential: stringValue(layer, ["futurePotential", "future_potential", "未来"]) || undefined,
      confidence: clampNumber(valueFor(layer, ["confidence", "score", "置信度"])),
    }];
  }).slice(0, 8);

  return {
    summary,
    locationType,
    visualMood,
    timeClues: stringsValue(nested, [
      "timeClues",
      "time_clues",
      "visibleTimeClues",
      "时间线索",
      "可见时间线索",
    ]),
    changeDrivers: stringsValue(nested, [
      "changeDrivers",
      "change_drivers",
      "drivers",
      "变化驱动",
      "变化因素",
    ]),
    subjects: rawSubjects.map((rawSubject) => {
      if (typeof rawSubject === "string") {
        return {
          name: rawSubject.trim() || "画面主体",
          confidence: 0.8,
          identityRule: "保留主体与画面相对位置",
        };
      }
      const subject = asRecord(rawSubject);
      return {
        name: stringValue(subject, ["name", "subjectName", "subject_name", "名称", "主体"]) || "画面主体",
        confidence: clampNumber(valueFor(subject, ["confidence", "score", "置信度"])),
        identityRule: stringValue(subject, [
          "identityRule",
          "identity_rule",
          "continuityRule",
          "continuity_rule",
          "连续性规则",
          "身份规则",
        ]) || "保留主体与画面相对位置",
      };
    }).slice(0, 6),
    cameraLock,
    spatialAnchors: spatialAnchors.length ? spatialAnchors : undefined,
    temporalLayers: temporalLayers.length ? temporalLayers : undefined,
    storySeeds: stringsValue(nested, ["storySeeds", "story_seeds", "故事种子"]) || undefined,
    hardConstraints: stringsValue(nested, ["hardConstraints", "hard_constraints", "硬约束"]) || undefined,
  };
}

export function parseStoryResponse(raw: string): TemporalStoryPayload | null {
  return parseJSONObjects(withoutReasoning(raw))
    .map(parseStory)
    .find((value): value is TemporalStoryPayload => value !== null) ?? null;
}

function parseStory(value: JSONRecord): TemporalStoryPayload | null {
  const beats = arrayValue(value, [
    "beats",
    "storyBeats",
    "story_beats",
    "timeline",
    "时间节点",
    "时间线",
  ]).map(asRecord).filter((beat): beat is JSONRecord => Boolean(beat));
  const title = stringValue(value, ["title", "storyTitle", "story_title", "标题"]);
  const logline = stringValue(value, ["logline", "summary", "故事梗概", "一句话故事"]);
  const presentTruth = stringValue(value, [
    "presentTruth",
    "present_truth",
    "baseline",
    "当前事实",
    "当下基线",
  ]);
  if (!title || !logline || !presentTruth) return null;
  const normalized = beats.map((beat): StoryBeatPayload => ({
    anchorYears: numberValue(valueFor(beat, [
      "anchorYears",
      "anchor_years",
      "yearOffset",
      "year_offset",
      "年份",
      "时间锚点",
    ])),
    title: stringValue(beat, ["title", "beatTitle", "beat_title", "标题"]),
    narrative: stringValue(beat, ["narrative", "story", "description", "叙事", "故事"]),
    visualPrompt: stringValue(beat, [
      "visualPrompt",
      "visual_prompt",
      "imagePrompt",
      "image_prompt",
      "视觉提示词",
      "画面提示词",
    ]),
    transitionCause: stringValue(beat, [
      "transitionCause",
      "transition_cause",
      "cause",
      "变迁原因",
    ]) || undefined,
    unchangedAnchors: stringsValue(beat, [
      "unchangedAnchors",
      "unchanged_anchors",
      "anchors",
      "保持锚点",
    ]) || undefined,
    foregroundDelta: stringValue(beat, ["foregroundDelta", "foreground_delta", "前景"]) || undefined,
    midgroundDelta: stringValue(beat, ["midgroundDelta", "midground_delta", "中景"]) || undefined,
    backgroundDelta: stringValue(beat, ["backgroundDelta", "background_delta", "背景"]) || undefined,
    subjectDelta: stringValue(beat, ["subjectDelta", "subject_delta", "主体变化"]) || undefined,
    environmentDelta: stringValue(beat, ["environmentDelta", "environment_delta", "环境变化"]) || undefined,
  }));
  const requiredAnchors = [-100, -30, -10, 0, 10, 30, 100];
  const requiredBeats = requiredAnchors.map(
    (anchor) => normalized.find((beat) => beat.anchorYears === anchor)
  );
  if (
    requiredBeats.some(
      (beat) => !beat || !beat.title || !beat.narrative || !beat.visualPrompt
    )
  ) return null;
  return {
    title,
    logline,
    presentTruth,
    identityRules: stringsValue(value, [
      "identityRules",
      "identity_rules",
      "continuityRules",
      "continuity_rules",
      "连续性规则",
      "身份规则",
    ]),
    beats: requiredBeats as TemporalStoryPayload["beats"],
  };
}

function asRecord(value: unknown): JSONRecord | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JSONRecord : undefined;
}

function string(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function strings(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(string).filter(Boolean).slice(0, 8);
  const single = string(value);
  return single ? [single] : [];
}

function valueFor(
  value: JSONRecord | undefined,
  keys: string[]
): unknown {
  if (!value) return undefined;
  for (const key of keys) {
    if (key in value) return value[key];
  }
  return undefined;
}

function stringValue(
  value: JSONRecord | undefined,
  keys: string[]
): string {
  return string(valueFor(value, keys));
}

function stringsValue(
  value: JSONRecord | undefined,
  keys: string[]
): string[] {
  return strings(valueFor(value, keys));
}

function arrayValue(
  value: JSONRecord | undefined,
  keys: string[]
): unknown[] {
  const found = valueFor(value, keys);
  return Array.isArray(found) ? found : [];
}

function clampNumber(value: unknown): number {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string"
      ? Number(value.replace("%", ""))
      : Number.NaN;
  const number = Number.isFinite(parsed)
    ? (typeof value === "string" && value.includes("%") ? parsed / 100 : parsed)
    : 0.8;
  return Math.min(1, Math.max(0, number));
}

function numberValue(value: unknown): number {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const normalized = value.trim().toUpperCase();
    if (normalized === "NOW" || normalized === "现在" || normalized === "当下") {
      return 0;
    }
    return Number(normalized.replace(/年/g, ""));
  }
  return Number.NaN;
}

function invalidJSON<T>(userMessage: string): MiniMaxIntelligenceResult<T> {
  return { ok: false, errorCode: "invalid_ai_response", userMessage, retryable: true };
}
