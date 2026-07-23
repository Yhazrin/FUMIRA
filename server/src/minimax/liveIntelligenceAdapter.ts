import { config } from "../config.js";
import { outboundFetch } from "../http/outboundFetch.js";
import type {
  MiniMaxIntelligenceAdapter,
  MiniMaxIntelligenceResult,
  SceneUnderstandingPayload,
  TemporalStoryPayload,
} from "../types.js";


type JSONRecord = Record<string, unknown>;

/// Uses the same documented MiniMax Coding Plan VLM endpoint that powers the
/// official `understand_image` MCP tool, then uses MiniMax M2.7 for the story.
/// Keys remain in the relay process; images and prompts are never logged.
export class LiveMiniMaxIntelligenceAdapter implements MiniMaxIntelligenceAdapter {
  constructor(
    private readonly apiKey: string,
    private readonly vlmApiKey: string = ""
  ) {}

  async analyzeImage(input: {
    imageDataUrl: string;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<SceneUnderstandingPayload>> {
    const response = await this.requestJSON(`${config.minimaxApiBaseUrl}/v1/coding_plan/vlm`, {
      prompt: [
        "Analyze this photo for a time-camera transformation.",
        "Return JSON only, with this exact shape:",
        '{"summary":"","locationType":"","visualMood":"","timeClues":[""],"changeDrivers":[""],"subjects":[{"name":"","confidence":0.0,"identityRule":""}]}',
        "Describe actual visible subjects, composition, scene, and plausible long-term change drivers.",
        "Use concise Simplified Chinese. Never identify a person by name.",
      ].join(" "),
      image_url: input.imageDataUrl,
    }, "vision", this.vlmApiKey || this.apiKey);

    if (!response.ok) return response;
    const understanding = parseJSONObjects(withoutReasoning(response.value))
      .map(parseUnderstanding)
      .find((value): value is SceneUnderstandingPayload => value !== null) ?? null;
    if (!understanding) return invalidJSON("图片理解返回格式异常，请重试。");
    return { ok: true, value: understanding };
  }

  async writeStory(input: {
    understanding: SceneUnderstandingPayload;
    requestId: string;
  }): Promise<MiniMaxIntelligenceResult<TemporalStoryPayload>> {
    const response = await this.requestStoryJSON({
      model: config.minimaxStoryModel,
      // Seven narratives plus seven visual prompts exceed 1,600 tokens in
      // Chinese. M3 has thinking disabled here, so 4,000 leaves ample room
      // without the long reasoning latency of M2.x.
      max_tokens: 4_000,
      // M3 defaults to no thinking; make this explicit so its text block is
      // available promptly for a user-facing story request.
      thinking: { type: "disabled" },
      system: "You write grounded, visually specific time-camera narratives. Output JSON only, never markdown or reasoning.",
      messages: [
        {
          role: "user",
          content: [{
            type: "text",
            text: [
            "Based only on this image analysis, write one coherent time story for a camera app.",
            `Analysis: ${JSON.stringify(input.understanding)}`,
            "Return exactly this JSON shape in Simplified Chinese:",
            '{"title":"","logline":"","presentTruth":"","identityRules":[""],"beats":[{"anchorYears":-100,"title":"","narrative":"","visualPrompt":""}]}.',
            "Provide exactly seven beats at -100,-30,-10,0,10,30,100. Keep each narrative under 80 Chinese characters and each visualPrompt under 100 Chinese characters. Keep people and places anonymous; preserve composition and visible identity rules.",
            ].join("\n"),
          }],
        },
      ],
    });

    if (!response.ok) return response;
    // M2 reasoning can put a schema-shaped object inside <think> before the
    // actual answer. Validate every complete JSON object instead of taking
    // the first one blindly.
    const story = parseJSONObjects(withoutReasoning(response.value))
      .map(parseStory)
      .find((value): value is TemporalStoryPayload => value !== null) ?? null;
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
  return raw.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
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

function parseUnderstanding(value: JSONRecord): SceneUnderstandingPayload | null {
  const subjects = Array.isArray(value.subjects) ? value.subjects.map(asRecord).filter(Boolean) : [];
  const summary = string(value.summary);
  const locationType = string(value.locationType);
  const visualMood = string(value.visualMood);
  if (!summary || !locationType || !visualMood) return null;
  return {
    summary,
    locationType,
    visualMood,
    timeClues: strings(value.timeClues),
    changeDrivers: strings(value.changeDrivers),
    subjects: subjects.map((subject) => ({
      name: string(subject?.name) || "画面主体",
      confidence: clampNumber(subject?.confidence),
      identityRule: string(subject?.identityRule) || "保留主体与画面相对位置",
    })).slice(0, 6),
  };
}

function parseStory(value: JSONRecord): TemporalStoryPayload | null {
  const beats = Array.isArray(value.beats) ? value.beats.map(asRecord).filter(Boolean) : [];
  const title = string(value.title);
  const logline = string(value.logline);
  const presentTruth = string(value.presentTruth);
  if (!title || !logline || !presentTruth || beats.length !== 7) return null;
  const normalized = beats.map((beat) => ({
    anchorYears: numberValue(beat?.anchorYears),
    title: string(beat?.title),
    narrative: string(beat?.narrative),
    visualPrompt: string(beat?.visualPrompt),
  }));
  const requiredAnchors = [-100, -30, -10, 0, 10, 30, 100];
  if (
    normalized.some((beat) => !Number.isFinite(beat.anchorYears) || !beat.title || !beat.narrative || !beat.visualPrompt) ||
    normalized
      .map((beat) => beat.anchorYears)
      .sort((a, b) => a - b)
      .some((value, index) => value !== requiredAnchors[index])
  ) return null;
  return { title, logline, presentTruth, identityRules: strings(value.identityRules), beats: normalized };
}

function asRecord(value: unknown): JSONRecord | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JSONRecord : undefined;
}

function string(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function strings(value: unknown): string[] {
  return Array.isArray(value) ? value.map(string).filter(Boolean).slice(0, 8) : [];
}

function clampNumber(value: unknown): number {
  const number = typeof value === "number" ? value : 0.8;
  return Math.min(1, Math.max(0, number));
}

function numberValue(value: unknown): number {
  if (typeof value === "number") return value;
  if (typeof value === "string") return Number(value);
  return Number.NaN;
}

function invalidJSON<T>(userMessage: string): MiniMaxIntelligenceResult<T> {
  return { ok: false, errorCode: "invalid_ai_response", userMessage, retryable: true };
}
