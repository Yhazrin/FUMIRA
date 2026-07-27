import { mkdir, writeFile, readFile, access } from "node:fs/promises";
import path from "node:path";
import { config } from "./config.js";
import type { AdminSettings, GenerationRecord, UploadedAsset } from "./types.js";

async function ensureDirs(): Promise<void> {
  await mkdir(config.uploadsDir, { recursive: true });
  await mkdir(config.generatedDir, { recursive: true });
  await mkdir(config.dataDir, { recursive: true });
}

const assets = new Map<string, UploadedAsset>();
const generations = new Map<string, GenerationRecord>();

let settings: AdminSettings = {
  remoteGenerationEnabled: config.remoteGenerationEnabled,
  promptTemplate: config.promptTemplate,
  modelName: config.modelName,
};

const settingsPath = () => path.join(config.dataDir, "admin-settings.json");
const generationsPath = () => path.join(config.dataDir, "generations.json");

export async function initStorage(): Promise<void> {
  await ensureDirs();
  try {
    const raw = await readFile(settingsPath(), "utf8");
    const parsed = JSON.parse(raw) as Partial<AdminSettings>;
    settings = {
      remoteGenerationEnabled:
        parsed.remoteGenerationEnabled ?? config.remoteGenerationEnabled,
      promptTemplate: parsed.promptTemplate ?? config.promptTemplate,
      modelName: parsed.modelName ?? config.modelName,
    };
  } catch {
    // first boot
  }

  try {
    const raw = await readFile(generationsPath(), "utf8");
    const list = JSON.parse(raw) as GenerationRecord[];
    for (const item of list) {
      generations.set(item.generationId, {
        ...item,
        imageProvider: item.imageProvider ?? "minimax",
      });
    }
  } catch {
    // first boot
  }
}

async function persistGenerations(): Promise<void> {
  const list = [...generations.values()].sort((a, b) =>
    a.createdAt < b.createdAt ? 1 : -1
  );
  await writeFile(generationsPath(), JSON.stringify(list, null, 2), "utf8");
}

async function persistSettings(): Promise<void> {
  await writeFile(settingsPath(), JSON.stringify(settings, null, 2), "utf8");
}

export function getSettings(): AdminSettings {
  return { ...settings };
}

export async function updateSettings(
  patch: Partial<AdminSettings>
): Promise<AdminSettings> {
  settings = {
    ...settings,
    ...patch,
    promptTemplate:
      typeof patch.promptTemplate === "string" && patch.promptTemplate.trim()
        ? patch.promptTemplate.trim()
        : settings.promptTemplate,
  };
  await persistSettings();
  return getSettings();
}

export async function saveUpload(params: {
  assetId: string;
  contentType: string;
  bytes: Buffer;
}): Promise<UploadedAsset> {
  await ensureDirs();
  const ext =
    params.contentType === "image/heic" || params.contentType === "image/heif"
      ? "heic"
      : "jpg";
  const absolutePath = path.join(config.uploadsDir, `${params.assetId}.${ext}`);
  await writeFile(absolutePath, params.bytes);
  const asset: UploadedAsset = {
    assetId: params.assetId,
    contentType: params.contentType,
    byteLength: params.bytes.byteLength,
    absolutePath,
    createdAt: new Date().toISOString(),
  };
  assets.set(asset.assetId, asset);
  return asset;
}

export function getAsset(assetId: string): UploadedAsset | undefined {
  return assets.get(assetId);
}

export async function readAssetBytes(
  assetId: string
): Promise<{ bytes: Buffer; contentType: string } | undefined> {
  const asset = assets.get(assetId);
  if (!asset) return undefined;
  try {
    await access(asset.absolutePath);
    const bytes = await readFile(asset.absolutePath);
    return { bytes, contentType: asset.contentType };
  } catch {
    return undefined;
  }
}

export async function saveGeneratedImage(params: {
  generationId: string;
  bytes: Buffer;
  contentType: string;
}): Promise<string> {
  await ensureDirs();
  const extension = params.contentType === "image/png" ? "png" : "jpg";
  const absolutePath = path.join(
    config.generatedDir,
    `${params.generationId}.${extension}`
  );
  await writeFile(absolutePath, params.bytes);
  return `/v1/results/${params.generationId}.${extension}`;
}

export function getGeneratedAbsolutePath(filename: string): string {
  const safe = path.basename(filename);
  return path.join(config.generatedDir, safe);
}

export function putGeneration(record: GenerationRecord): void {
  generations.set(record.generationId, record);
  void persistGenerations();
}

export function getGeneration(
  generationId: string
): GenerationRecord | undefined {
  return generations.get(generationId);
}

export function listGenerations(): GenerationRecord[] {
  return [...generations.values()].sort((a, b) =>
    a.createdAt < b.createdAt ? 1 : -1
  );
}

export function updateGeneration(
  generationId: string,
  patch: Partial<GenerationRecord>
): GenerationRecord | undefined {
  const current = generations.get(generationId);
  if (!current) return undefined;
  const next: GenerationRecord = {
    ...current,
    ...patch,
    updatedAt: new Date().toISOString(),
  };
  generations.set(generationId, next);
  void persistGenerations();
  return next;
}
