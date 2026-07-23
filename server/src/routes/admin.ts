import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { config } from "../config.js";
import { adminList } from "../queue.js";
import { getSettings, updateSettings } from "../storage.js";

function requireAdmin(
  request: FastifyRequest,
  reply: FastifyReply
): boolean {
  if (!config.adminToken) {
    void reply.code(503).send({
      errorCode: "admin_unconfigured",
      userMessage: "管理端未配置。",
    });
    return false;
  }

  const header = request.headers.authorization ?? "";
  const token =
    header.startsWith("Bearer ")
      ? header.slice("Bearer ".length).trim()
      : String(request.headers["x-admin-token"] ?? "").trim();

  if (token !== config.adminToken) {
    void reply.code(401).send({
      errorCode: "unauthorized",
      userMessage: "管理端认证失败。",
    });
    return false;
  }
  return true;
}

export async function registerAdminRoutes(app: FastifyInstance): Promise<void> {
  app.get("/v1/admin/generations", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    return {
      items: adminList(),
      settings: {
        remoteGenerationEnabled: getSettings().remoteGenerationEnabled,
        modelName: getSettings().modelName,
        // Expose template for editing; never expose API keys.
        promptTemplate: getSettings().promptTemplate,
      },
    };
  });

  app.patch<{
    Body: {
      remoteGenerationEnabled?: boolean;
      promptTemplate?: string;
    };
  }>("/v1/admin/settings", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;

    const body = request.body ?? {};
    const patch: {
      remoteGenerationEnabled?: boolean;
      promptTemplate?: string;
    } = {};

    if (typeof body.remoteGenerationEnabled === "boolean") {
      patch.remoteGenerationEnabled = body.remoteGenerationEnabled;
    }
    if (typeof body.promptTemplate === "string") {
      const trimmed = body.promptTemplate.trim();
      if (!trimmed) {
        return reply.code(400).send({
          errorCode: "invalid_prompt_template",
          userMessage: "提示词模板不能为空。",
        });
      }
      if (trimmed.length > 4000) {
        return reply.code(400).send({
          errorCode: "invalid_prompt_template",
          userMessage: "提示词模板过长。",
        });
      }
      patch.promptTemplate = trimmed;
    }

    const settings = await updateSettings(patch);
    return {
      remoteGenerationEnabled: settings.remoteGenerationEnabled,
      modelName: settings.modelName,
      promptTemplate: settings.promptTemplate,
    };
  });
}
