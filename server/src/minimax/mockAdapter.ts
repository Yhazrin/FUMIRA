import type {
  MiniMaxAdapter,
  MiniMaxGenerateInput,
  MiniMaxGenerateResult,
} from "../types.js";

/**
 * Deterministic mock MiniMax adapter for CI / local flow tests.
 * Supports injectable failure modes via prompt markers (test-only).
 */
export class MockMiniMaxAdapter implements MiniMaxAdapter {
  async generate(input: MiniMaxGenerateInput): Promise<MiniMaxGenerateResult> {
    if (input.prompt.includes("__FORCE_2013__")) {
      return {
        ok: false,
        errorCode: "invalid_params",
        userMessage: "生成参数无效，请调整时间或故事后重试。",
        retryable: false,
        statusMsg: "invalid params, prompt length must be less than 1500",
      };
    }
    if (input.prompt.includes("__FORCE_TIMEOUT__")) {
      return {
        ok: false,
        errorCode: "timeout",
        userMessage: "生成超时，请稍后重试。",
        retryable: true,
        statusMsg: "mock timeout",
      };
    }
    if (input.prompt.includes("__FORCE_RATE__")) {
      return {
        ok: false,
        errorCode: "rate_limited",
        userMessage: "生成服务繁忙，请稍后再试。",
        retryable: true,
        statusMsg: "rate limit",
      };
    }

    // 1x1 JPEG
    const jpeg = Buffer.from(
      "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBEQCEAwEPwAB//9k=",
      "base64"
    );

    return {
      ok: true,
      imageBytes: jpeg,
      contentType: "image/jpeg",
    };
  }
}

export function createMiniMaxAdapter(options: {
  mock: boolean;
  apiKey: string;
}): MiniMaxAdapter {
  if (options.mock || !options.apiKey) {
    // Caller decides readiness separately; when mock flag is on we always mock.
    // When key missing and mock off, live adapter still constructed only if ready.
  }
  if (options.mock) {
    return new MockMiniMaxAdapter();
  }
  // Dynamic import avoided — live adapter constructed by caller when key present.
  throw new Error("use createAdapterFromConfig");
}
