import type {
  MiniMaxAdapter,
  MiniMaxGenerateInput,
  MiniMaxGenerateResult,
} from "../types.js";
import { config } from "../config.js";
import { outboundFetch } from "../http/outboundFetch.js";

const MINIMAX_URL = "https://api.minimaxi.com/v1/image_generation";

interface MiniMaxResponseBody {
  data?: {
    image_base64?: string[];
    image_urls?: string[];
  };
  base_resp?: {
    status_code?: number;
    status_msg?: string;
  };
}

function classifyStatusCode(statusCode: number, statusMsg?: string): {
  errorCode: string;
  userMessage: string;
  retryable: boolean;
} {
  if (statusCode === 2013) {
    return {
      errorCode: "invalid_params",
      userMessage: "生成参数无效，请调整时间或故事后重试。",
      retryable: false,
    };
  }

  // Other 2xxx: rate limit / balance / permission — treat as retryable when
  // the message suggests throttling; otherwise retryable for transient vendor faults.
  const msg = (statusMsg ?? "").toLowerCase();
  const rateLimited =
    msg.includes("rate") ||
    msg.includes("limit") ||
    msg.includes("throttle") ||
    msg.includes("too many") ||
    statusCode === 1002 ||
    statusCode === 1008;

  if (rateLimited) {
    return {
      errorCode: "rate_limited",
      userMessage: "生成服务繁忙，请稍后再试。",
      retryable: true,
    };
  }

  return {
    errorCode: `vendor_${statusCode}`,
    userMessage: "生成服务暂时不可用，请稍后重试。",
    retryable: true,
  };
}

async function sleep(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Real MiniMax image-01 I2I adapter.
 * - model fixed to image-01
 * - response_format fixed to base64
 * - HTTP timeout 240s
 * - Limited exponential backoff (max 2 retries) for retryable vendor errors / network
 * - Never logs Authorization or base64 payloads
 */
export class LiveMiniMaxAdapter implements MiniMaxAdapter {
  constructor(private readonly apiKey: string) {}

  async generate(input: MiniMaxGenerateInput): Promise<MiniMaxGenerateResult> {
    const started = Date.now();
    const maxAttempts = 3;
    let lastFailure: MiniMaxGenerateResult | null = null;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        const result = await this.singleAttempt(input);
        if (result.ok) {
          console.info(
            JSON.stringify({
              event: "minimax_ok",
              requestId: input.requestId,
              generationId: input.generationId,
              attempt,
              durationMs: Date.now() - started,
            })
          );
          return result;
        }

        lastFailure = result;
        console.info(
          JSON.stringify({
            event: "minimax_fail",
            requestId: input.requestId,
            generationId: input.generationId,
            attempt,
            errorCode: result.errorCode,
            durationMs: Date.now() - started,
          })
        );

        if (!result.retryable || attempt === maxAttempts) {
          return result;
        }
        await sleep(500 * 2 ** (attempt - 1));
      } catch (error) {
        const message =
          error instanceof Error ? error.message : "network_error";
        const isTimeout =
          message.includes("aborted") ||
          message.includes("timeout") ||
          message.includes("Timeout");
        lastFailure = {
          ok: false,
          errorCode: isTimeout ? "timeout" : "network_error",
          userMessage: isTimeout
            ? "生成超时，请稍后重试。"
            : "无法连接生成服务，请检查网络后重试。",
          retryable: true,
          statusMsg: message.slice(0, 200),
        };
        console.info(
          JSON.stringify({
            event: "minimax_network",
            requestId: input.requestId,
            generationId: input.generationId,
            attempt,
            errorCode: lastFailure.errorCode,
            durationMs: Date.now() - started,
          })
        );
        if (attempt === maxAttempts) return lastFailure;
        await sleep(500 * 2 ** (attempt - 1));
      }
    }

    return (
      lastFailure ?? {
        ok: false,
        errorCode: "unknown",
        userMessage: "生成失败，请稍后重试。",
        retryable: true,
      }
    );
  }

  private async singleAttempt(
    input: MiniMaxGenerateInput
  ): Promise<MiniMaxGenerateResult> {
    const body: Record<string, unknown> = {
      model: "image-01",
      prompt: input.prompt,
      aspect_ratio: input.aspectRatio,
      response_format: "base64",
      n: 1,
      image_file: input.imageDataUrl,
    };

    // subject_reference only when explicitly enabled for single-person portrait.
    if (input.useSubjectReference) {
      body.subject_reference = [
        {
          type: "character",
          image_file: input.imageDataUrl,
        },
      ];
    }

    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(),
      config.minimaxTimeoutMs
    );

    try {
      const response = await outboundFetch(MINIMAX_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      const text = await response.text();
      let parsed: MiniMaxResponseBody;
      try {
        parsed = JSON.parse(text) as MiniMaxResponseBody;
      } catch {
        return {
          ok: false,
          errorCode: "vendor_bad_response",
          userMessage: "生成服务返回异常，请稍后重试。",
          retryable: true,
          httpStatus: response.status,
          statusMsg: `non_json_http_${response.status}`,
        };
      }

      const statusCode = parsed.base_resp?.status_code ?? -1;
      const statusMsg = parsed.base_resp?.status_msg;

      if (statusCode === 0 && parsed.data?.image_base64?.[0]) {
        const imageBytes = Buffer.from(parsed.data.image_base64[0], "base64");
        return {
          ok: true,
          imageBytes,
          contentType: "image/jpeg",
        };
      }

      if (statusCode === 0) {
        return {
          ok: false,
          errorCode: "empty_result",
          userMessage: "生成完成但没有收到图片，请重试。",
          retryable: true,
          statusMsg,
        };
      }

      const classified = classifyStatusCode(statusCode, statusMsg);
      return {
        ok: false,
        ...classified,
        statusMsg,
        httpStatus: response.status,
      };
    } finally {
      clearTimeout(timer);
    }
  }
}
