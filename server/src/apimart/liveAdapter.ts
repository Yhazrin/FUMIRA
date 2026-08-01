import { config } from "../config.js";
import { outboundFetch } from "../http/outboundFetch.js";
import { Agent } from "undici";
import type {
  ImageGenerationAdapter,
  MiniMaxGenerateInput,
  MiniMaxGenerateResult,
} from "../types.js";

interface APIErrorBody {
  error?: {
    code?: number;
    message?: string;
    type?: string;
  };
}

interface SubmitBody extends APIErrorBody {
  code?: number;
  data?: Array<{
    status?: string;
    task_id?: string;
  }>;
}

interface TaskBody extends APIErrorBody {
  code?: number;
  data?: {
    status?: string;
    progress?: number;
    result?: {
      images?: Array<{
        url?: string[];
      }>;
    };
  };
}

type ImageGenerateFailure = Exclude<MiniMaxGenerateResult, { ok: true }>;

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function failureForStatus(
  status: number,
  body?: APIErrorBody
): ImageGenerateFailure {
  const statusMsg = body?.error?.message?.slice(0, 200);
  if (status === 400) {
    return {
      ok: false,
      errorCode: "invalid_params",
      userMessage: "中转站生成参数无效，请调整后重试。",
      retryable: false,
      statusMsg,
      httpStatus: status,
    };
  }
  if (status === 401 || status === 402) {
    return {
      ok: false,
      errorCode: status === 401 ? "unauthorized" : "insufficient_balance",
      userMessage: status === 401
        ? "中转站鉴权失败，请检查后台配置。"
        : "中转站额度不足，请检查后台账户。",
      retryable: false,
      statusMsg,
      httpStatus: status,
    };
  }
  if (status === 429) {
    return {
      ok: false,
      errorCode: "rate_limited",
      userMessage: "中转站请求繁忙，请稍后重试。",
      retryable: true,
      statusMsg,
      httpStatus: status,
    };
  }
  return {
    ok: false,
    errorCode: "apimart_unavailable",
    userMessage: "中转站图片服务暂时不可用，请稍后重试。",
    retryable: true,
    statusMsg,
    httpStatus: status,
  };
}

/**
 * API Mart GPT-Image-2 image-to-image adapter.
 * Submits one reference image, polls the asynchronous task, then downloads the
 * expiring result URL while keeping the vendor credential inside the relay.
 */
export class LiveAPIMartAdapter implements ImageGenerationAdapter {
  private readonly dispatcher = config.apiMartResolveIp
    ? new Agent({
        connect: {
          lookup: (_hostname, _options, callback) => {
            callback(null, [
              {
                address: config.apiMartResolveIp,
                family: 4,
              },
            ]);
          },
        },
      })
    : undefined;

  constructor(private readonly apiKey: string) {}

  async generate(input: MiniMaxGenerateInput): Promise<MiniMaxGenerateResult> {
    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(),
      config.apiMartTimeoutMs
    );

    try {
      const submitted = await this.submit(input, controller.signal);
      if (!submitted.ok) return submitted;

      const resultURL = await this.poll(submitted.taskId, controller.signal);
      if (!resultURL.ok) return resultURL;

      const imageResponse = await outboundFetch(resultURL.url, {
        method: "GET",
        signal: controller.signal,
        dispatcher: this.dispatcher,
      });
      if (!imageResponse.ok) {
        return failureForStatus(imageResponse.status);
      }

      return {
        ok: true,
        imageBytes: Buffer.from(await imageResponse.arrayBuffer()),
        contentType: imageResponse.headers.get("content-type")?.split(";")[0]
          || "image/png",
      };
    } catch (error) {
      const cause = (error as {
        cause?: { code?: string; message?: string };
      })?.cause;
      const message = cause?.code
        || cause?.message
        || (error instanceof Error ? error.message : "network_error");
      const timedOut = controller.signal.aborted;
      return {
        ok: false,
        errorCode: timedOut ? "timeout" : "network_error",
        userMessage: timedOut
          ? "中转站生成超时，请稍后重试。"
          : "无法连接中转站图片服务，请检查网络后重试。",
        retryable: true,
        statusMsg: message.slice(0, 200),
      };
    } finally {
      clearTimeout(timer);
    }
  }

  private async submit(
    input: MiniMaxGenerateInput,
    signal: AbortSignal
  ): Promise<
    | { ok: true; taskId: string }
    | ImageGenerateFailure
  > {
    const response = await outboundFetch(
      `${config.apiMartApiBaseUrl}/v1/images/generations`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: input.modelName?.trim() || "gpt-image-2",
          prompt: input.prompt,
          n: 1,
          size: input.aspectRatio,
          resolution: "2k",
          image_urls: [input.imageDataUrl],
        }),
        signal,
        dispatcher: this.dispatcher,
      }
    );
    const body = await response.json().catch(() => null) as SubmitBody | null;
    if (!response.ok) {
      return failureForStatus(response.status, body ?? undefined);
    }
    const taskId = body?.data?.[0]?.task_id;
    if (!taskId) {
      return {
        ok: false,
        errorCode: "vendor_bad_response",
        userMessage: "中转站没有返回任务编号，请稍后重试。",
        retryable: true,
      };
    }
    return { ok: true, taskId };
  }

  private async poll(
    taskId: string,
    signal: AbortSignal
  ): Promise<
    | { ok: true; url: string }
    | ImageGenerateFailure
  > {
    while (!signal.aborted) {
      const response = await outboundFetch(
        `${config.apiMartApiBaseUrl}/v1/tasks/${encodeURIComponent(taskId)}`,
        {
          method: "GET",
          headers: {
            Authorization: `Bearer ${this.apiKey}`,
          },
          signal,
          dispatcher: this.dispatcher,
        }
      );
      const body = await response.json().catch(() => null) as TaskBody | null;
      if (!response.ok) {
        return failureForStatus(response.status, body ?? undefined);
      }

      switch (body?.data?.status) {
      case "completed": {
        const url = body.data.result?.images?.[0]?.url?.[0];
        if (!url) {
          return {
            ok: false,
            errorCode: "empty_result",
            userMessage: "中转站任务完成但没有返回图片。",
            retryable: true,
          };
        }
        return { ok: true, url };
      }
      case "failed":
        return {
          ok: false,
          errorCode: "apimart_generation_failed",
          userMessage: body.error?.message?.trim()
            || "中转站图片生成失败，请调整后重试。",
          retryable: false,
          statusMsg: body.error?.message?.slice(0, 200),
        };
      default:
        await sleep(config.apiMartPollIntervalMs);
      }
    }
    throw new Error("apimart_timeout");
  }
}
