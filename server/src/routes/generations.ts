import { createReadStream } from "node:fs";
import { access } from "node:fs/promises";
import type { FastifyInstance } from "fastify";
import {
  createGenerationJob,
  toClientGeneration,
} from "../queue.js";
import { getGeneration, getGeneratedAbsolutePath } from "../storage.js";
import { anchorNormalizedPositions, DEFAULT_TIER, listTierProfiles } from "../tiers.js";
import type { CreateGenerationBody } from "../types.js";

export async function registerGenerationRoutes(
  app: FastifyInstance
): Promise<void> {
  app.get("/v1/tiers", async () => ({
    schemaVersion: "generation-tiers.v1" as const,
    defaultTier: DEFAULT_TIER,
    tiers: listTierProfiles().map((tier) => ({
      ...tier,
      anchorPositions: anchorNormalizedPositions(tier),
    })),
  }));

  app.post<{ Body: Record<string, unknown> }>(
    "/v1/generations",
    async (request, reply) => {
      const body = request.body;
      if (!body || typeof body !== "object") {
        return reply.code(400).send({
          errorCode: "invalid_body",
          userMessage: "请求体无效。",
          retryable: false,
        });
      }

      // Runtime: pass raw body to createGenerationJob which handles
      // discriminated union validation and contextVersion detection.
      const result = createGenerationJob(body as unknown as CreateGenerationBody);
      if (!result.ok) {
        return reply.code(result.statusCode).send({
          errorCode: result.errorCode,
          userMessage: result.userMessage,
          retryable: result.retryable,
        });
      }

      return reply.code(202).send({
        generationId: result.record.generationId,
        status: "queued" as const,
        requestId: result.record.requestId,
      });
    }
  );

  app.get<{ Params: { id: string } }>(
    "/v1/generations/:id",
    async (request, reply) => {
      const record = getGeneration(request.params.id);
      if (!record) {
        return reply.code(404).send({
          errorCode: "not_found",
          userMessage: "找不到该生成任务。",
          retryable: false,
        });
      }
      return toClientGeneration(record);
    }
  );

  app.get<{ Params: { filename: string } }>(
    "/v1/results/:filename",
    async (request, reply) => {
      const absolute = getGeneratedAbsolutePath(request.params.filename);
      try {
        await access(absolute);
      } catch {
        return reply.code(404).send({
          errorCode: "not_found",
          userMessage: "结果图片不存在。",
          retryable: false,
        });
      }
      reply.header(
        "Content-Type",
        request.params.filename.toLowerCase().endsWith(".png")
          ? "image/png"
          : "image/jpeg"
      );
      return reply.send(createReadStream(absolute));
    }
  );
}
