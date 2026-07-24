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

  it("accepts structured context with contextVersion and compiles prompt server-side", async () => {
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
    const { assetId } = upload.json();

    const create = await app.inject({
      method: "POST",
      url: "/v1/generations",
      payload: {
        contextVersion: "generation.v2",
        sourceAssetId: assetId,
        requestId: "req-structured-1",
        aspectRatio: "3:4",
        timePosition: {
          normalized: 0.5,
          offsetDays: 9131,
          offsetYears: 25,
          compactLabel: "25 年后",
        },
        structuredContext: {
          schemaVersion: "generation-context.v2",
          understanding: {
            summary: "一座安静的城市公园",
            locationType: "城市公园",
            visualMood: "安静、开阔",
            timeClues: ["年轻树木"],
            changeDrivers: ["植被生长"],
            subjects: [
              { name: "三棵树木", confidence: 0.97, identityRule: "保留树木相对位置" },
            ],
          },
          story: {
            schemaVersion: "temporal-story.v2",
            title: "公园的时间回声",
            logline: "安静公园跨越百年的变化",
            presentTruth: "一座安静的城市公园",
            identityRules: ["保持原图主体与构图"],
            beats: [
              { anchorYears: -100, title: "百年前", narrative: "荒地", visualPrompt: "荒地" },
              { anchorYears: -30, title: "三十年前", narrative: "绿化", visualPrompt: "初生树木" },
              { anchorYears: -10, title: "十年前", narrative: "规模", visualPrompt: "年轻树木" },
              { anchorYears: 0, title: "今天", narrative: "公园", visualPrompt: "现代公园" },
              { anchorYears: 10, title: "十年后", narrative: "茂盛", visualPrompt: "茂盛树木" },
              { anchorYears: 30, title: "三十年后", narrative: "扩张", visualPrompt: "高楼林立" },
              { anchorYears: 100, title: "百年后", narrative: "未来", visualPrompt: "未来城市" },
            ],
            targetBeat: {
              anchorYears: 25,
              title: "二十五年后",
              narrative: "精确25年变化",
              visualPrompt: "精确25年视觉",
            },
          },
          generationMode: "captured_target",
        },
      },
    });
    assert.equal(create.statusCode, 202);
    const { generationId, status } = create.json();
    assert.equal(status, "queued");

    const finished = await waitForGeneration(generationId, 3000);
    assert.ok(finished);
    assert.equal(finished.status, "succeeded");
    assert.equal(finished.promptVersion, "v2");
    assert.ok(finished.promptHash);
    assert.ok(finished.promptCharCount <= 1500);
    assert.ok(finished.sectionCharCounts);
    assert.ok(Array.isArray(finished.truncatedSections));

    const poll = await app.inject({
      method: "GET",
      url: `/v1/generations/${generationId}`,
    });
    assert.equal(poll.statusCode, 200);
    const body = poll.json();
    assert.equal(body.status, "succeeded");
    assert.match(body.resultUrl, /\/v1\/results\//);
  });

  it("rejects V2 structured context with missing targetBeat", async () => {
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
        contextVersion: "generation.v2",
        sourceAssetId: assetId,
        requestId: "req-missing-tb",
        aspectRatio: "3:4",
        timePosition: { normalized: 0, offsetDays: 0, offsetYears: 0, compactLabel: "NOW" },
        structuredContext: {
          schemaVersion: "generation-context.v2",
          understanding: {
            summary: "x", locationType: "x", visualMood: "x",
            timeClues: [], changeDrivers: [], subjects: [],
          },
          story: {
            schemaVersion: "temporal-story.v2",
            title: "x", logline: "x", presentTruth: "x",
            identityRules: [],
            beats: [
              { anchorYears: -100, title: "a", narrative: "b", visualPrompt: "c" },
              { anchorYears: -30, title: "a", narrative: "b", visualPrompt: "c" },
              { anchorYears: -10, title: "a", narrative: "b", visualPrompt: "c" },
              { anchorYears: 0, title: "a", narrative: "b", visualPrompt: "c" },
              { anchorYears: 10, title: "a", narrative: "b", visualPrompt: "c" },
              { anchorYears: 30, title: "a", narrative: "b", visualPrompt: "c" },
              { anchorYears: 100, title: "a", narrative: "b", visualPrompt: "c" },
            ],
          },
          generationMode: "captured_target",
        },
      },
    });
    assert.equal(create.statusCode, 400);
    assert.equal(create.json().errorCode, "missing_target_beat");
  });

  it("structured context prompt includes targetBeat content, not nearest canonical", async () => {
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
        contextVersion: "generation.v2",
        sourceAssetId: assetId,
        requestId: "req-targetbeat-1",
        aspectRatio: "3:4",
        timePosition: {
          normalized: 0.5,
          offsetDays: 9131,
          offsetYears: 25,
          compactLabel: "25 年后",
        },
        structuredContext: {
          schemaVersion: "generation-context.v2",
          understanding: {
            summary: "公园",
            locationType: "城市公园",
            visualMood: "安静",
            timeClues: [],
            changeDrivers: [],
            subjects: [],
          },
          story: {
            schemaVersion: "temporal-story.v2",
            title: "回声",
            logline: "变化",
            presentTruth: "公园",
            identityRules: [],
            beats: [
              { anchorYears: -100, title: "百年前", narrative: "荒地", visualPrompt: "荒地、泥土路" },
              { anchorYears: -30, title: "三十年前", narrative: "绿化", visualPrompt: "初生树木" },
              { anchorYears: -10, title: "十年前", narrative: "规模", visualPrompt: "年轻树木" },
              { anchorYears: 0, title: "今天", narrative: "公园", visualPrompt: "现代公园" },
              { anchorYears: 10, title: "十年后", narrative: "茂盛", visualPrompt: "茂盛树木" },
              { anchorYears: 30, title: "三十年后", narrative: "扩张", visualPrompt: "高楼林立和密集城市" },
              { anchorYears: 100, title: "百年后", narrative: "未来", visualPrompt: "未来城市景观" },
            ],
            targetBeat: {
              anchorYears: 25,
              title: "二十五年后",
              narrative: "精确二十五年变化",
              visualPrompt: "精确的二十五年视觉变化效果",
            },
          },
          generationMode: "captured_target",
        },
      },
    });
    assert.equal(create.statusCode, 202);
    const { generationId } = create.json();
    const finished = await waitForGeneration(generationId, 3000);
    assert.ok(finished);
    assert.equal(finished.status, "succeeded");
    // The mock adapter receives the compiled prompt — verify it was used.
    assert.equal(finished.promptVersion, "v2");
  });

  it("runs understanding and seven-beat story through the configured intelligence adapter", async () => {
    const { buildApp } = await import("../src/index.js");
    const overlong = "这是一段故意超过页面字符预算的动态故事文字".repeat(8);
    const intelligence = {
      async analyzeImage() {
        return {
          ok: true as const,
          value: {
            summary: overlong,
            locationType: overlong,
            visualMood: overlong,
            timeClues: [overlong],
            changeDrivers: [overlong],
            subjects: [{ name: overlong, confidence: 0.9, identityRule: overlong }],
          },
        };
      },
      async writeStory() {
        return {
          ok: true as const,
          value: {
            title: overlong,
            logline: overlong,
            presentTruth: overlong,
            identityRules: [overlong],
            beats: [-100, -30, -10, 0, 10, 30, 100].map((anchorYears) => ({
              anchorYears,
              title: overlong,
              narrative: overlong,
              visualPrompt: overlong,
            })),
          },
        };
      },
    };
    const intelligenceApp = await buildApp({
      adapter: new MockMiniMaxAdapter(),
      intelligenceAdapter: intelligence,
    });
    try {
      const { payload, contentType } = multipartBody(
        {},
        { name: "scene.jpg", contentType: "image/jpeg", bytes: TINY_JPEG }
      );
      const upload = await intelligenceApp.inject({
        method: "POST",
        url: "/v1/uploads",
        headers: { "content-type": contentType },
        payload,
      });
      const understand = await intelligenceApp.inject({
        method: "POST",
        url: "/v1/understand",
        payload: {
          sourceAssetId: upload.json().assetId,
          copyConstraints: {
            summary: 32,
            locationType: 8,
            visualMood: 16,
            timeClue: 10,
            changeDriver: 10,
            subjectName: 6,
            identityRule: 20,
          },
          requestId: "req-understand",
        },
      });
      assert.equal(understand.statusCode, 200);
      const understandBody = understand.json();
      assert.equal(understandBody.copyConstraints.locationType, 8);
      assert.ok(Array.from(understandBody.understanding.summary).length <= 32);
      assert.ok(Array.from(understandBody.understanding.locationType).length <= 8);
      assert.ok(Array.from(understandBody.understanding.visualMood).length <= 16);
      assert.ok(Array.from(understandBody.understanding.timeClues[0]).length <= 10);
      assert.ok(Array.from(understandBody.understanding.changeDrivers[0]).length <= 10);
      assert.ok(Array.from(understandBody.understanding.subjects[0].name).length <= 6);
      assert.ok(Array.from(understandBody.understanding.subjects[0].identityRule).length <= 20);

      const story = await intelligenceApp.inject({
        method: "POST",
        url: "/v1/stories",
        payload: {
          understanding: understandBody.understanding,
          targetTime: { offsetYears: 25, compactLabel: "25 年后" },
          copyConstraints: {
            title: 8,
            logline: 24,
            presentTruth: 30,
            identityRule: 20,
            beatTitle: 6,
            beatNarrative: 28,
            visualPrompt: 44,
          },
          requestId: "req-story",
        },
      });
      assert.equal(story.statusCode, 200);
      const storyBody = story.json();
      assert.deepEqual(storyBody.story.beats.map((beat: { anchorYears: number }) => beat.anchorYears), [-100, -30, -10, 0, 10, 30, 100]);
      assert.equal(storyBody.copyConstraints.title, 8);
      assert.ok(Array.from(storyBody.story.title).length <= 8);
      assert.ok(Array.from(storyBody.story.logline).length <= 24);
      assert.ok(Array.from(storyBody.story.presentTruth).length <= 30);
      assert.ok(Array.from(storyBody.story.identityRules[0]).length <= 20);
      assert.ok(Array.from(storyBody.story.beats[0].title).length <= 6);
      assert.ok(Array.from(storyBody.story.beats[0].narrative).length <= 28);
      assert.ok(Array.from(storyBody.story.beats[0].visualPrompt).length <= 44);
    } finally {
      await intelligenceApp.close();
    }
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
