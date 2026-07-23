import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, describe, it } from "node:test";

const TINY_JPEG = Buffer.from(
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBEQCEAwEPwAB//9k=",
  "base64"
);

function multipartBody(
  fields: Record<string, string>,
  file?: { name: string; contentType: string; bytes: Buffer }
) {
  const boundary = "----fumiratestboundary";
  const chunks: Buffer[] = [];

  for (const [key, value] of Object.entries(fields)) {
    chunks.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="${key}"\r\n\r\n${value}\r\n`
      )
    );
  }

  if (file) {
    chunks.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${file.name}"\r\nContent-Type: ${file.contentType}\r\n\r\n`
      )
    );
    chunks.push(file.bytes);
    chunks.push(Buffer.from("\r\n"));
  }

  chunks.push(Buffer.from(`--${boundary}--\r\n`));
  return {
    payload: Buffer.concat(chunks),
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
}

describe("fumira-server", () => {
  let app: Awaited<ReturnType<typeof import("../src/index.js").buildApp>>;
  let tempRoot: string;
  let waitForGeneration: typeof import("../src/queue.js").waitForGeneration;
  let buildPrompt: typeof import("../src/prompt.js").buildPrompt;
  let MockMiniMaxAdapter: typeof import("../src/minimax/mockAdapter.js").MockMiniMaxAdapter;

  before(async () => {
    tempRoot = await mkdtemp(path.join(tmpdir(), "fumira-server-"));
    process.env.MINIMAX_MOCK = "true";
    process.env.REMOTE_GENERATION_ENABLED = "true";
    process.env.ADMIN_TOKEN = "test-admin-token";
    process.env.PUBLIC_BASE_URL = "http://127.0.0.1:8787";
    process.env.UPLOADS_DIR = path.join(tempRoot, "uploads");
    process.env.GENERATED_DIR = path.join(tempRoot, "generated");
    process.env.DATA_DIR = path.join(tempRoot, "data");
    delete process.env.MINIMAX_API_KEY;

    const mockMod = await import("../src/minimax/mockAdapter.js");
    MockMiniMaxAdapter = mockMod.MockMiniMaxAdapter;
    const promptMod = await import("../src/prompt.js");
    buildPrompt = promptMod.buildPrompt;
    const queueMod = await import("../src/queue.js");
    waitForGeneration = queueMod.waitForGeneration;
    const { buildApp } = await import("../src/index.js");
    app = await buildApp({ adapter: new MockMiniMaxAdapter() });
  });

  after(async () => {
    await app.close();
    await rm(tempRoot, { recursive: true, force: true });
  });

  it("POST /health reports generation readiness without leaking key details", async () => {
    const res = await app.inject({ method: "POST", url: "/health" });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.ok, true);
    assert.equal(body.generation.ready, true);
    assert.equal(body.generation.mode, "mock");
    assert.equal("apiKey" in body, false);
    assert.equal(JSON.stringify(body).includes("MINIMAX_API_KEY"), false);
  });

  it("rejects uploads over 10MB", async () => {
    const big = Buffer.alloc(10 * 1024 * 1024 + 1, 0xff);
    big[0] = 0xff;
    big[1] = 0xd8;
    const { payload, contentType } = multipartBody(
      {},
      { name: "big.jpg", contentType: "image/jpeg", bytes: big }
    );
    const res = await app.inject({
      method: "POST",
      url: "/v1/uploads",
      headers: { "content-type": contentType },
      payload,
    });
    assert.equal(res.statusCode, 413);
    assert.equal(res.json().errorCode, "file_too_large");
  });

  it("rejects invalid JPEG payloads", async () => {
    const { payload, contentType } = multipartBody(
      {},
      {
        name: "bad.jpg",
        contentType: "image/jpeg",
        bytes: Buffer.from("not-a-jpeg"),
      }
    );
    const res = await app.inject({
      method: "POST",
      url: "/v1/uploads",
      headers: { "content-type": contentType },
      payload,
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().errorCode, "invalid_image");
  });

  it("uploads JPEG and completes mock I2I generation", async () => {
    const { payload, contentType } = multipartBody(
      {},
      { name: "scene.jpg", contentType: "image/jpeg", bytes: TINY_JPEG }
    );
    const upload = await app.inject({
      method: "POST",
      url: "/v1/uploads",
      headers: { "content-type": contentType },
      payload,
    });
    assert.equal(upload.statusCode, 201);
    const { assetId, byteLength } = upload.json();
    assert.ok(assetId);
    assert.equal(byteLength, TINY_JPEG.byteLength);

    const create = await app.inject({
      method: "POST",
      url: "/v1/generations",
      payload: {
        sourceAssetId: assetId,
        requestId: "req-flow-1",
        aspectRatio: "3:4",
        story: "A quiet park path growing into the future.",
        timePosition: {
          normalized: 0.5,
          offsetDays: 9000,
          offsetYears: 25,
          compactLabel: "25 年后",
        },
      },
    });
    assert.equal(create.statusCode, 202);
    const { generationId, status } = create.json();
    assert.equal(status, "queued");

    const finished = await waitForGeneration(generationId, 3000);
    assert.ok(finished);
    assert.equal(finished.status, "succeeded");

    const poll = await app.inject({
      method: "GET",
      url: `/v1/generations/${generationId}`,
    });
    assert.equal(poll.statusCode, 200);
    const body = poll.json();
    assert.equal(body.status, "succeeded");
    assert.match(body.resultUrl, /\/v1\/results\//);
  });

  it("maps MiniMax 2013 to non-retryable invalid_params", async () => {
    const { payload, contentType } = multipartBody(
      {},
      { name: "scene.jpg", contentType: "image/jpeg", bytes: TINY_JPEG }
    );
    const upload = await app.inject({
      method: "POST",
      url: "/v1/uploads",
      headers: { "content-type": contentType },
      payload,
    });
    const { assetId } = upload.json();

    const create = await app.inject({
      method: "POST",
      url: "/v1/generations",
      payload: {
        sourceAssetId: assetId,
        requestId: "req-2013",
        aspectRatio: "3:4",
        story: "__FORCE_2013__",
        timePosition: {
          normalized: 0,
          offsetDays: 0,
          offsetYears: 0,
          compactLabel: "NOW",
        },
      },
    });
    const { generationId } = create.json();
    const finished = await waitForGeneration(generationId, 3000);
    assert.equal(finished?.status, "failed");
    assert.equal(finished?.errorCode, "invalid_params");
    assert.equal(finished?.retryable, false);

    const poll = await app.inject({
      method: "GET",
      url: `/v1/generations/${generationId}`,
    });
    const body = poll.json();
    assert.equal(body.errorCode, "invalid_params");
    assert.equal(body.retryable, false);
  });

  it("maps timeout failures as retryable", async () => {
    const { payload, contentType } = multipartBody(
      {},
      { name: "scene.jpg", contentType: "image/jpeg", bytes: TINY_JPEG }
    );
    const upload = await app.inject({
      method: "POST",
      url: "/v1/uploads",
      headers: { "content-type": contentType },
      payload,
    });
    const { assetId } = upload.json();

    const create = await app.inject({
      method: "POST",
      url: "/v1/generations",
      payload: {
        sourceAssetId: assetId,
        requestId: "req-timeout",
        aspectRatio: "3:4",
        story: "__FORCE_TIMEOUT__",
        timePosition: {
          normalized: 0.2,
          offsetDays: 100,
          offsetYears: 0.3,
          compactLabel: "100 天后",
        },
      },
    });
    const { generationId } = create.json();
    const finished = await waitForGeneration(generationId, 3000);
    assert.equal(finished?.status, "failed");
    assert.equal(finished?.errorCode, "timeout");
    assert.equal(finished?.retryable, true);
  });

  it("truncates prompts over 1500 characters and records metadata", () => {
    const longStory = "x".repeat(2000);
    const built = buildPrompt({
      template: "Story: {{story}}. Time: {{timeLabel}}. Ratio: {{aspectRatio}}.",
      story: longStory,
      timePosition: {
        normalized: 1,
        offsetDays: 36525,
        offsetYears: 100,
        compactLabel: "100 年后",
      },
      aspectRatio: "3:4",
    });
    assert.equal(built.truncated, true);
    assert.ok(built.charCount <= 1500);
    assert.ok(built.prompt.length <= 1500);
  });

  it("admin generations requires bearer token and redacts secrets", async () => {
    const denied = await app.inject({
      method: "GET",
      url: "/v1/admin/generations",
    });
    assert.equal(denied.statusCode, 401);

    const ok = await app.inject({
      method: "GET",
      url: "/v1/admin/generations",
      headers: { authorization: "Bearer test-admin-token" },
    });
    assert.equal(ok.statusCode, 200);
    const body = ok.json();
    assert.ok(Array.isArray(body.items));
    const serialized = JSON.stringify(body);
    assert.equal(serialized.includes("Authorization"), false);
    assert.equal(serialized.includes("base64"), false);
    assert.equal(serialized.includes("MINIMAX"), false);
  });

  it("admin can toggle remote generation and edit prompt template", async () => {
    const patched = await app.inject({
      method: "PATCH",
      url: "/v1/admin/settings",
      headers: { authorization: "Bearer test-admin-token" },
      payload: {
        remoteGenerationEnabled: false,
        promptTemplate: "Keep identity. {{story}} at {{timeLabel}}.",
      },
    });
    assert.equal(patched.statusCode, 200);
    assert.equal(patched.json().remoteGenerationEnabled, false);

    const create = await app.inject({
      method: "POST",
      url: "/v1/generations",
      payload: {
        sourceAssetId: "missing",
        requestId: "req-disabled",
        story: "x",
        timePosition: {
          normalized: 0,
          offsetDays: 0,
          offsetYears: 0,
          compactLabel: "NOW",
        },
      },
    });
    assert.equal(create.statusCode, 503);

    await app.inject({
      method: "PATCH",
      url: "/v1/admin/settings",
      headers: { authorization: "Bearer test-admin-token" },
      payload: { remoteGenerationEnabled: true },
    });
  });
});

describe("health without adapter", () => {
  it("reports generation unavailable when no adapter is attached", async () => {
    const tempRoot = await mkdtemp(path.join(tmpdir(), "fumira-unavail-"));
    process.env.UPLOADS_DIR = path.join(tempRoot, "uploads");
    process.env.GENERATED_DIR = path.join(tempRoot, "generated");
    process.env.DATA_DIR = path.join(tempRoot, "data");

    const { buildApp } = await import("../src/index.js");
    const lonely = await buildApp({ adapter: null });
    const res = await lonely.inject({ method: "POST", url: "/health" });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.generation.ready, false);
    assert.equal(body.generation.mode, "unavailable");
    assert.equal(JSON.stringify(body).includes("apiKey"), false);
    await lonely.close();
    await rm(tempRoot, { recursive: true, force: true });
  });
});
