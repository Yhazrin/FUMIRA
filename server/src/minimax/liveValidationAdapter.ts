import { config } from "../config.js";
import { outboundFetch } from "../http/outboundFetch.js";
import type {
  PostGenerationValidationAdapter,
  PostGenerationValidationInput,
  PostGenerationValidationResult,
  SceneUnderstandingPayload,
  StoryBeatPayload,
} from "../types.js";
import { buildValidationPrompt, parseValidationResponse } from "../validation.js";

type JSONRecord = Record<string, unknown>;

/**
 * Live validator that reuses the same MiniMax VLM endpoint as image
 * understanding and asks it to compare the source photograph against the
 * generated target-time result. Returns a {@link PostGenerationValidationResult}
 * with a parsed JSON object containing six scoring metrics and an explicit
 * `shouldRegenerate` boolean.
 *
 * Auth: uses the VLM-Token-Plan key (`config.minimaxVlmApiKey`) when set,
 * otherwise falls back to the pay-as-you-go intelligence key. Keys never
 * leave the relay and are never logged.
 */
export class LiveMiniMaxValidationAdapter implements PostGenerationValidationAdapter {
  constructor(
    private readonly apiKey: string,
    private readonly vlmApiKey: string = ""
  ) {}

  async validate(
    input: PostGenerationValidationInput
  ): Promise<PostGenerationValidationResult> {
    const endpoint = `${config.minimaxApiBaseUrl}/v1/coding_plan/vlm`;
    const payload = JSON.stringify({
      prompt: [
        buildValidationPrompt({
          targetLabel: input.targetTime.compactLabel,
          offsetYears: input.targetTime.offsetYears,
        }),
        sceneBibleBrief(input.understanding, input.storyBeat),
        "IMAGE A is the SOURCE photograph. IMAGE B is the GENERATED result.",
      ].filter(Boolean).join(" "),
      image_urls: [sourceDataUrl(input), targetDataUrl(input)],
    });
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 90_000);
    try {
      const response = await outboundFetch(endpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.vlmApiKey || this.apiKey}`,
          "Content-Type": "application/json",
          "MM-API-Source": "Minimax-MCP",
        },
        body: payload,
        signal: controller.signal,
      });
      const payloadJson = (await response.json().catch(() => null)) as JSONRecord | null;
      const base = asRecord(payloadJson?.base_resp);
      const statusCode = typeof base?.status_code === "number" ? base.status_code : -1;
      if (!response.ok || statusCode !== 0) {
        return {
          ok: false,
          errorCode: statusCode === 1004 ? "unauthorized" : "validation_unavailable",
          userMessage: "生成后校验暂不可用，本轮结果保留。",
          retryable: statusCode !== 2013 && statusCode !== 1004,
        };
      }
      const content = typeof payloadJson?.content === "string"
        ? payloadJson.content
        : "";
      if (!content) {
        return {
          ok: false,
          errorCode: "invalid_validation_response",
          userMessage: "校验模型没有返回内容。",
          retryable: true,
        };
      }
      const parsed = parseValidationContent(content);
      if (!parsed) {
        return {
          ok: false,
          errorCode: "invalid_validation_response",
          userMessage: "校验返回的格式无法识别。",
          retryable: true,
        };
      }
      const validated = parseValidationResponse(parsed);
      if (!validated) {
        return {
          ok: false,
          errorCode: "invalid_validation_response",
          userMessage: "校验返回的字段不完整。",
          retryable: true,
        };
      }
      return { ok: true, value: validated };
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 160) : "network_error";
      return {
        ok: false,
        errorCode: "validation_network",
        userMessage: "无法连接校验服务。",
        retryable: true,
        statusMsg: message,
      };
    } finally {
      clearTimeout(timer);
    }
  }
}

function sourceDataUrl(input: PostGenerationValidationInput): string {
  if (input.sourceContentType === "image/png") {
    return `data:image/png;base64,${input.sourceBytes.toString("base64")}`;
  }
  return `data:image/jpeg;base64,${input.sourceBytes.toString("base64")}`;
}

function targetDataUrl(input: PostGenerationValidationInput): string {
  if (input.targetContentType === "image/png") {
    return `data:image/png;base64,${input.targetBytes.toString("base64")}`;
  }
  return `data:image/jpeg;base64,${input.targetBytes.toString("base64")}`;
}

function sceneBibleBrief(
  understanding: SceneUnderstandingPayload | null | undefined,
  beat: StoryBeatPayload | null | undefined
): string {
  if (!understanding && !beat) return "";
  const chunks: string[] = [];
  if (understanding?.summary) chunks.push(`Scene summary: ${understanding.summary}`);
  if (understanding?.hardConstraints?.length) {
    chunks.push(`Hard constraints: ${understanding.hardConstraints.join("; ")}`);
  }
  if (beat) {
    if (beat.title) chunks.push(`Story beat title: ${beat.title}`);
    if (beat.narrative) chunks.push(`Story beat narrative: ${beat.narrative}`);
  }
  return chunks.join(" ");
}

/**
 * Pull the first JSON object out of a possibly noisy VLM payload.
 * Reuses the same robust JSON scanning as the intelligence adapter so that
 * reasoning blocks or stray prose never cause a false invalid_response.
 */
export function parseValidationContent(raw: string): unknown | null {
  return scanJsonObjects(stripReasoning(raw))[0] ?? null;
}

function stripReasoning(raw: string): string {
  return raw
    .replace(/<think[\s\S]*?<\/think>/gi, "")
    .replace(/<think[\s\S]*$/gi, "")
    .trim();
}

function scanJsonObjects(raw: string): unknown[] {
  const objects: unknown[] = [];
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
            objects.push(JSON.parse(raw.slice(start, index + 1)));
          } catch {
            // ignore and keep scanning
          }
          break;
        }
      }
    }
  }
  return objects;
}

function asRecord(value: unknown): JSONRecord | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as JSONRecord)
    : undefined;
}
