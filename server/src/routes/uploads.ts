import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { config } from "../config.js";
import { saveUpload } from "../storage.js";

const ALLOWED_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/heic",
  "image/heif",
]);

export async function registerUploadRoutes(app: FastifyInstance): Promise<void> {
  app.post("/v1/uploads", async (request, reply) => {
    const file = await request.file();
    if (!file) {
      return reply.code(400).send({
        errorCode: "missing_file",
        userMessage: "请上传一张 JPEG 或 HEIC 照片。",
        retryable: false,
      });
    }

    const contentType = (file.mimetype || "").toLowerCase();
    if (!ALLOWED_TYPES.has(contentType)) {
      return reply.code(400).send({
        errorCode: "unsupported_content_type",
        userMessage: "仅支持 JPEG 或 HEIC 图片。",
        retryable: false,
      });
    }

    const buffer = await file.toBuffer();
    if (buffer.byteLength === 0) {
      return reply.code(400).send({
        errorCode: "invalid_image",
        userMessage: "图片内容无效。",
        retryable: false,
      });
    }

    if (buffer.byteLength > config.maxUploadBytes) {
      return reply.code(413).send({
        errorCode: "file_too_large",
        userMessage: "图片不能超过 10MB。",
        retryable: false,
      });
    }

    // Basic JPEG magic-byte check when claimed as jpeg
    if (
      (contentType === "image/jpeg" || contentType === "image/jpg") &&
      !(buffer[0] === 0xff && buffer[1] === 0xd8)
    ) {
      return reply.code(400).send({
        errorCode: "invalid_image",
        userMessage: "JPEG 图片内容无效。",
        retryable: false,
      });
    }

    const assetId = randomUUID();
    const asset = await saveUpload({
      assetId,
      contentType: contentType === "image/jpg" ? "image/jpeg" : contentType,
      bytes: buffer,
    });

    console.info(
      JSON.stringify({
        event: "upload_ok",
        assetId: asset.assetId,
        contentType: asset.contentType,
        byteLength: asset.byteLength,
      })
    );

    return reply.code(201).send({
      assetId: asset.assetId,
      contentType: asset.contentType,
      byteLength: asset.byteLength,
    });
  });
}
