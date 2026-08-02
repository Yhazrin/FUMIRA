import * as THREE from 'three';

export type ProceduralModelOptions = {
  wireframe?: boolean;
  castShadow?: boolean;
  receiveShadow?: boolean;
  textureSize?: number;
  textureAnisotropy?: number;
  qualityPriority?: 'reference-fidelity' | 'balanced';
};

export type ProceduralModelRuntime = {
  nodes: Record<string, THREE.Object3D>;
  meshes: Record<string, THREE.Mesh>;
  sockets: Record<string, THREE.Object3D>;
  colliders: Record<string, unknown>;
  destructionGroups: Record<string, THREE.Object3D[]>;
};

type SculptMaterialSpec = Record<string, any>;

function hashString(value: string): number {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function readLayerNumber(value: unknown, keys: string[], fallback: number): number {
  if (typeof value === 'number') return value;
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    for (const key of keys) {
      if (typeof record[key] === 'number') return record[key] as number;
    }
  }
  return fallback;
}

function hexToRgb(hex: string): [number, number, number] {
  const normalized = /^#[0-9a-f]{3}$/i.test(hex)
    ? '#' + hex.slice(1).split('').map((part) => part + part).join('')
    : hex;
  const value = /^#[0-9a-f]{6}$/i.test(normalized) ? Number.parseInt(normalized.slice(1), 16) : 0x8a7a5f;
  return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
}

function materialPalette(spec: SculptMaterialSpec): string[] {
  const palette = spec.colorVariation?.palette;
  if (Array.isArray(palette) && palette.length > 0) return palette.filter((value) => typeof value === 'string');
  const secondary = spec.albedo?.secondary;
  const colors = [spec.baseColor ?? spec.color ?? spec.albedo?.dominant, ...(Array.isArray(secondary) ? secondary : [])];
  return colors.filter((value): value is string => typeof value === 'string' && value.startsWith('#'));
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function smoothCurve(value: number): number {
  return value * value * (3 - 2 * value);
}

function periodicHash(x: number, y: number, seed: number, periodX: number, periodY: number): number {
  const wrappedX = ((x % periodX) + periodX) % periodX;
  const wrappedY = ((y % periodY) + periodY) % periodY;
  let value = Math.imul(wrappedX + seed * 17, 374761393) ^ Math.imul(wrappedY + seed * 31, 668265263);
  value = Math.imul(value ^ (value >>> 13), 1274126177);
  return ((value ^ (value >>> 16)) >>> 0) / 4294967295;
}

function periodicValueNoise(u: number, v: number, seed: number, periodX: number, periodY: number): number {
  const x = u * periodX;
  const y = v * periodY;
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const tx = smoothCurve(x - x0);
  const ty = smoothCurve(y - y0);
  const a = periodicHash(x0, y0, seed, periodX, periodY);
  const b = periodicHash(x0 + 1, y0, seed, periodX, periodY);
  const c = periodicHash(x0, y0 + 1, seed, periodX, periodY);
  const d = periodicHash(x0 + 1, y0 + 1, seed, periodX, periodY);
  return THREE.MathUtils.lerp(THREE.MathUtils.lerp(a, b, tx), THREE.MathUtils.lerp(c, d, tx), ty);
}

type SurfaceBand = {
  frequency: number;
  amplitude: number;
  stretchX: number;
  stretchY: number;
  ridge: boolean;
};

function surfaceBands(spec: SculptMaterialSpec): SurfaceBand[] {
  const source = Array.isArray(spec.surfaceFrequencyBands) ? spec.surfaceFrequencyBands : [];
  const parsed = source.flatMap((item: unknown) => {
    if (!item || typeof item !== 'object') return [];
    const band = item as Record<string, unknown>;
    const frequency = typeof band.frequency === 'number' ? band.frequency : 0;
    const amplitude = typeof band.amplitude === 'number' ? band.amplitude : 0;
    if (frequency <= 0 || amplitude <= 0) return [];
    const stretch = Array.isArray(band.stretch) ? band.stretch : [1, 1];
    const description = `${String(band.pattern ?? '')} ${String(band.role ?? '')}`.toLowerCase();
    return [{
      frequency,
      amplitude,
      stretchX: typeof stretch[0] === 'number' ? Math.max(0.1, stretch[0]) : 1,
      stretchY: typeof stretch[1] === 'number' ? Math.max(0.1, stretch[1]) : 1,
      ridge: /(ridge|groove|grain|fiber|striated|crack)/.test(description),
    }];
  });
  return parsed.length > 0 ? parsed : [
    { frequency: 2, amplitude: 0.42, stretchX: 1, stretchY: 1, ridge: false },
    { frequency: 12, amplitude: 0.22, stretchX: 1, stretchY: 1, ridge: false },
    { frequency: 56, amplitude: 0.08, stretchX: 1, stretchY: 1, ridge: false },
  ];
}

function sampleSurface(u: number, v: number, bands: SurfaceBand[], seed: number): number {
  let value = 0;
  let weight = 0;
  for (let index = 0; index < bands.length; index += 1) {
    const band = bands[index];
    const periodX = Math.max(1, Math.round(band.frequency * band.stretchX));
    const periodY = Math.max(1, Math.round(band.frequency * band.stretchY));
    let sample = periodicValueNoise(u, v, seed + index * 1013, periodX, periodY);
    if (band.ridge) sample = 1 - Math.abs(sample * 2 - 1);
    value += sample * band.amplitude;
    weight += band.amplitude;
  }
  return weight > 0 ? clamp01(value / weight) : 0.5;
}

function mixPalette(colors: [number, number, number][], value: number): [number, number, number] {
  if (colors.length === 1) return colors[0];
  const scaled = clamp01(value) * (colors.length - 1);
  const index = Math.min(colors.length - 2, Math.floor(scaled));
  const mix = scaled - index;
  const a = colors[index];
  const b = colors[index + 1];
  return [
    Math.round(THREE.MathUtils.lerp(a[0], b[0], mix)),
    Math.round(THREE.MathUtils.lerp(a[1], b[1], mix)),
    Math.round(THREE.MathUtils.lerp(a[2], b[2], mix)),
  ];
}

function writePixel(data: Uint8ClampedArray, offset: number, red: number, green: number, blue: number): void {
  data[offset] = Math.max(0, Math.min(255, Math.round(red)));
  data[offset + 1] = Math.max(0, Math.min(255, Math.round(green)));
  data[offset + 2] = Math.max(0, Math.min(255, Math.round(blue)));
  data[offset + 3] = 255;
}

function makeCanvas(size: number): HTMLCanvasElement {
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  return canvas;
}

function createMapTexture(
  canvas: HTMLCanvasElement,
  colorSpace: THREE.ColorSpace,
  spec: SculptMaterialSpec,
  options: ProceduralModelOptions,
): THREE.CanvasTexture {
  const texture = new THREE.CanvasTexture(canvas);
  const projection = spec.textureProjection && typeof spec.textureProjection === 'object' ? spec.textureProjection : {};
  const repeat = Array.isArray(projection.repeat) ? projection.repeat : [2, 2];
  texture.colorSpace = colorSpace;
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(
    typeof repeat[0] === 'number' ? repeat[0] : 2,
    typeof repeat[1] === 'number' ? repeat[1] : 2,
  );
  texture.anisotropy = Math.max(1, Math.round(options.textureAnisotropy ?? projection.anisotropy ?? 8));
  texture.needsUpdate = true;
  return texture;
}

type ProceduralTextureSet = {
  albedo: THREE.Texture;
  roughness: THREE.Texture;
  height: THREE.Texture;
  normal: THREE.Texture;
  ao: THREE.Texture;
  source: 'reference-pixel-extraction' | 'procedural';
};

function referenceMapUrl(spec: SculptMaterialSpec, channel: string): string | null {
  const reference = spec.referencePbr;
  if (!reference || typeof reference !== 'object') return null;
  if (reference.usable === false) return null;
  const confidence = typeof reference.confidence === 'number'
    ? reference.confidence
    : (typeof reference.estimatedFidelity === 'number' ? reference.estimatedFidelity : 0);
  const threshold = typeof reference.targetThreshold === 'number' ? reference.targetThreshold : 0.7;
  if (confidence < threshold) return null;
  const maps = reference.maps;
  if (!maps || typeof maps !== 'object') return null;
  const map = (maps as Record<string, unknown>)[channel];
  if (!map || typeof map !== 'object') return null;
  const record = map as Record<string, unknown>;
  const url = typeof record.url === 'string' && record.url.trim() ? record.url : record.path;
  return typeof url === 'string' && url.trim() ? url : null;
}

function createLoadedMapTexture(
  url: string,
  colorSpace: THREE.ColorSpace,
  spec: SculptMaterialSpec,
  options: ProceduralModelOptions,
): THREE.Texture {
  const texture = new THREE.TextureLoader().load(url);
  const projection = spec.textureProjection && typeof spec.textureProjection === 'object' ? spec.textureProjection : {};
  const repeat = Array.isArray(projection.repeat) ? projection.repeat : [1, 1];
  texture.colorSpace = colorSpace;
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(
    typeof repeat[0] === 'number' ? repeat[0] : 1,
    typeof repeat[1] === 'number' ? repeat[1] : 1,
  );
  texture.anisotropy = Math.max(1, Math.round(options.textureAnisotropy ?? projection.anisotropy ?? 8));
  texture.needsUpdate = true;
  return texture;
}

function makeReferenceTextureSet(spec: SculptMaterialSpec, options: ProceduralModelOptions): ProceduralTextureSet | null {
  const albedo = referenceMapUrl(spec, 'albedo');
  const roughness = referenceMapUrl(spec, 'roughness');
  const height = referenceMapUrl(spec, 'height');
  const normal = referenceMapUrl(spec, 'normal');
  const ao = referenceMapUrl(spec, 'ao');
  if (!albedo || !roughness || !height || !normal || !ao) return null;
  return {
    albedo: createLoadedMapTexture(albedo, THREE.SRGBColorSpace, spec, options),
    roughness: createLoadedMapTexture(roughness, THREE.NoColorSpace, spec, options),
    height: createLoadedMapTexture(height, THREE.NoColorSpace, spec, options),
    normal: createLoadedMapTexture(normal, THREE.NoColorSpace, spec, options),
    ao: createLoadedMapTexture(ao, THREE.NoColorSpace, spec, options),
    source: 'reference-pixel-extraction',
  };
}

function makeProceduralTextureSet(
  id: string,
  spec: SculptMaterialSpec,
  options: ProceduralModelOptions,
): ProceduralTextureSet | null {
  if (typeof document === 'undefined') return null;
  const qualityFirst = (options.qualityPriority ?? 'reference-fidelity') === 'reference-fidelity';
  const requested = options.textureSize ?? spec.textureResolution;
  const requestedSize = typeof requested === 'number' && Number.isFinite(requested)
    ? requested
    : (qualityFirst ? 1024 : 512);
  const size = Math.max(256, Math.min(2048, 2 ** Math.round(Math.log2(requestedSize))));
  const canvases = {
    albedo: makeCanvas(size),
    roughness: makeCanvas(size),
    height: makeCanvas(size),
    normal: makeCanvas(size),
    ao: makeCanvas(size),
  };
  const contexts = {
    albedo: canvases.albedo.getContext('2d'),
    roughness: canvases.roughness.getContext('2d'),
    height: canvases.height.getContext('2d'),
    normal: canvases.normal.getContext('2d'),
    ao: canvases.ao.getContext('2d'),
  };
  if (!contexts.albedo || !contexts.roughness || !contexts.height || !contexts.normal || !contexts.ao) return null;
  const images = {
    albedo: contexts.albedo.createImageData(size, size),
    roughness: contexts.roughness.createImageData(size, size),
    height: contexts.height.createImageData(size, size),
    normal: contexts.normal.createImageData(size, size),
    ao: contexts.ao.createImageData(size, size),
  };
  const seed = hashString(id);
  const bands = surfaceBands(spec);
  const heightField = new Float32Array(size * size);
  const roughnessField = new Float32Array(size * size);
  const palette = materialPalette(spec);
  const fallback = typeof spec.baseColor === 'string' ? spec.baseColor : '#8A7A5F';
  const colors = (palette.length >= 2 ? palette : [fallback, '#6E614B', '#A08F70']).map(hexToRgb);
  const baseRoughness = clamp01(readLayerNumber(spec.roughness, ['base'], 0.76));
  const roughnessVariation = clamp01(readLayerNumber(spec.roughness, ['variation'], 0.18));
  const colorAmplitude = clamp01(readLayerNumber(spec.colorVariation, ['amplitude', 'variation'], 0.18));
  const heightCorrelation = clamp01(readLayerNumber(spec.colorVariation, ['heightCorrelation'], 0.3));
  for (let y = 0; y < size; y += 1) {
    const v = y / size;
    for (let x = 0; x < size; x += 1) {
      const u = x / size;
      const index = y * size + x;
      const height = sampleSurface(u, v, bands, seed + 101);
      const roughNoise = sampleSurface(u, v, bands, seed + 7001);
      const colorNoise = sampleSurface(u, v, bands, seed + 15013);
      heightField[index] = height;
      roughnessField[index] = clamp01(baseRoughness + (roughNoise - 0.5) * roughnessVariation * 2);
      const paletteValue = clamp01(
        0.5 + (colorNoise - 0.5) * colorAmplitude * 2 + (height - 0.5) * heightCorrelation
      );
      const color = mixPalette(colors, paletteValue);
      writePixel(images.albedo.data, index * 4, color[0], color[1], color[2]);
    }
  }
  const normalStrength = Math.max(0.05, readLayerNumber(spec.normal, ['strength', 'amplitude'], 0.35));
  const aoStrength = clamp01(readLayerNumber(spec.ambientOcclusion, ['cavityStrength', 'strength'], 0.35));
  for (let y = 0; y < size; y += 1) {
    const up = ((y - 1 + size) % size) * size;
    const down = ((y + 1) % size) * size;
    for (let x = 0; x < size; x += 1) {
      const left = (x - 1 + size) % size;
      const right = (x + 1) % size;
      const index = y * size + x;
      const center = heightField[index];
      const dx = (heightField[y * size + right] - heightField[y * size + left]) * normalStrength * 6;
      const dy = (heightField[down + x] - heightField[up + x]) * normalStrength * 6;
      const inverseLength = 1 / Math.sqrt(dx * dx + dy * dy + 1);
      const normalX = -dx * inverseLength;
      const normalY = -dy * inverseLength;
      const normalZ = inverseLength;
      const neighborAverage = (
        heightField[y * size + left] + heightField[y * size + right]
        + heightField[up + x] + heightField[down + x]
      ) * 0.25;
      const cavity = Math.max(0, neighborAverage - center);
      const ao = clamp01(1 - aoStrength * (cavity * 12 + (1 - center) * 0.16));
      const offset = index * 4;
      const heightByte = center * 255;
      const roughnessByte = roughnessField[index] * 255;
      writePixel(images.height.data, offset, heightByte, heightByte, heightByte);
      writePixel(images.roughness.data, offset, roughnessByte, roughnessByte, roughnessByte);
      writePixel(
        images.normal.data, offset,
        (normalX * 0.5 + 0.5) * 255,
        (normalY * 0.5 + 0.5) * 255,
        (normalZ * 0.5 + 0.5) * 255,
      );
      writePixel(images.ao.data, offset, ao * 255, ao * 255, ao * 255);
    }
  }
  contexts.albedo.putImageData(images.albedo, 0, 0);
  contexts.roughness.putImageData(images.roughness, 0, 0);
  contexts.height.putImageData(images.height, 0, 0);
  contexts.normal.putImageData(images.normal, 0, 0);
  contexts.ao.putImageData(images.ao, 0, 0);
  return {
    albedo: createMapTexture(canvases.albedo, THREE.SRGBColorSpace, spec, options),
    roughness: createMapTexture(canvases.roughness, THREE.NoColorSpace, spec, options),
    height: createMapTexture(canvases.height, THREE.NoColorSpace, spec, options),
    normal: createMapTexture(canvases.normal, THREE.NoColorSpace, spec, options),
    ao: createMapTexture(canvases.ao, THREE.NoColorSpace, spec, options),
    source: 'procedural',
  };
}

function createSculptMaterial(id: string, spec: SculptMaterialSpec, options: ProceduralModelOptions): THREE.MeshPhysicalMaterial {
  const textures = makeReferenceTextureSet(spec, options) ?? makeProceduralTextureSet(id, spec, options);
  const material = new THREE.MeshPhysicalMaterial({
    color: textures ? 0xffffff : new THREE.Color(typeof spec.baseColor === 'string' ? spec.baseColor : '#8A7A5F'),
    roughness: textures ? 1 : clamp01(readLayerNumber(spec.roughness, ['base'], 0.76)),
    metalness: clamp01(readLayerNumber(spec.metalness, ['base'], 0.0)),
    clearcoat: clamp01(readLayerNumber(spec.clearcoat, ['base', 'amount'], 0)),
    clearcoatRoughness: clamp01(readLayerNumber(spec.clearcoatRoughness, ['base'], 0.25)),
    transmission: clamp01(readLayerNumber(spec.transmission, ['base', 'amount'], 0)),
    opacity: clamp01(readLayerNumber(spec.opacity, ['base'], 1)),
    transparent: readLayerNumber(spec.transmission, ['base', 'amount'], 0) > 0 || readLayerNumber(spec.opacity, ['base'], 1) < 1,
    alphaTest: Math.max(0, readLayerNumber(spec.alpha, ['cutoff', 'alphaTest'], 0)),
    wireframe: options.wireframe ?? false,
    side: spec.doubleSided === true ? THREE.DoubleSide : THREE.FrontSide,
  });
  if (textures) {
    material.map = textures.albedo;
    material.roughnessMap = textures.roughness;
    material.normalMap = textures.normal;
    material.normalScale.setScalar(Math.max(0.05, readLayerNumber(spec.normal, ['strength', 'amplitude'], 0.35)));
    material.aoMap = textures.ao;
    material.aoMap.channel = 0;
    material.aoMapIntensity = readLayerNumber(spec.ambientOcclusion, ['cavityStrength', 'strength'], 0.35);
    const bumpScale = Math.max(0, readLayerNumber(spec.bump, ['amplitude', 'strength'], 0));
    if (bumpScale > 0) {
      material.bumpMap = textures.height;
      material.bumpScale = bumpScale;
    }
    const displacementScale = Math.max(0, readLayerNumber(spec.displacement, ['amplitude', 'strength'], 0));
    if (displacementScale > 0) {
      material.displacementMap = textures.height;
      material.displacementScale = displacementScale;
      material.displacementBias = -displacementScale * 0.5;
    }
  }
  material.envMapIntensity = readLayerNumber(spec, ['envMapIntensity'], 0.8);
  material.userData.sculptMaterial = spec;
  material.userData.proceduralMapsIndependent = true;
  material.userData.pbrTextureSource = textures?.source ?? 'flat-fallback';
  material.userData.referencePbr = spec.referencePbr ?? null;
  material.needsUpdate = true;
  return material;
}

type AttachmentEndpoint = {
  start: THREE.Vector3;
  midpoint: THREE.Vector3;
  quaternion: THREE.Quaternion;
  length: number;
  baseRadius: number;
  endRadius: number;
};

function readVector3(value: unknown, fallback: [number, number, number]): THREE.Vector3 {
  if (Array.isArray(value) && value.length === 3 && value.every((item) => typeof item === 'number')) {
    return new THREE.Vector3(value[0], value[1], value[2]);
  }
  return new THREE.Vector3(fallback[0], fallback[1], fallback[2]);
}

function readNumber(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function makeAttachmentEndpoint(attachment: unknown): AttachmentEndpoint | null {
  if (!attachment || typeof attachment !== 'object') return null;
  const record = attachment as Record<string, unknown>;
  const start = readVector3(record.localStart, [0, 0, 0]);
  const end = readVector3(record.localEnd, [0, 1, 0]);
  const delta = end.clone().sub(start);
  const length = delta.length();
  if (length <= 0.0001) return null;
  const direction = delta.clone().normalize();
  const quaternion = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), direction);
  const baseRadius = Math.max(0.005, readNumber(record.baseRadius, 0.06));
  const endRadius = Math.max(0.003, readNumber(record.endRadius, baseRadius * 0.55));
  return {
    start,
    midpoint: delta.multiplyScalar(0.5),
    quaternion,
    length,
    baseRadius,
    endRadius,
  };
}

// Generated from ObjectSculptSpec target: Clay Red Electric Moped
// Sculpt build pass: blockout
// This factory is intentionally pass-gated. Finish browser screenshot review before unlocking deeper passes.
export function createClayRedElectricMopedModel(options: ProceduralModelOptions = {}): THREE.Group {
  const root = new THREE.Group();
  root.name = "Clay Red Electric Moped";

  const materialMap: Record<string, THREE.Material> = {};
  materialMap["clay_moped_body"] = createSculptMaterial(
    "clay_moped_body",
    {"id": "clay_moped_body", "baseColor": "#FF672A", "roughness": {"base": 0.44, "variation": 0.08}, "metalness": {"base": 0.0}, "clearcoat": {"base": 0.15}, "clearcoatRoughness": {"base": 0.6}, "normal": {"strength": 0.15}, "ambientOcclusion": {"cavityStrength": 0.2}, "colorVariation": {"palette": ["#FF672A"], "amplitude": 0.05, "heightCorrelation": 0.1}, "surfaceFrequencyBands": [{"id": "clay-base", "frequency": 3, "amplitude": 0.15, "stretch": [1, 1], "pattern": "smooth", "role": "clay-base"}, {"id": "clay-grain", "frequency": 18, "amplitude": 0.06, "stretch": [1, 1], "pattern": "grain", "role": "clay-grain"}]},
    options
  );
  materialMap["clay_moped_seat"] = createSculptMaterial(
    "clay_moped_seat",
    {"id": "clay_moped_seat", "baseColor": "#202425", "roughness": {"base": 0.6, "variation": 0.05}, "metalness": {"base": 0.0}, "clearcoat": {"base": 0.05}, "clearcoatRoughness": {"base": 0.8}, "normal": {"strength": 0.1}, "ambientOcclusion": {"cavityStrength": 0.15}, "colorVariation": {"palette": ["#202425"], "amplitude": 0.02, "heightCorrelation": 0.05}, "surfaceFrequencyBands": [{"id": "seat-base", "frequency": 3, "amplitude": 0.1, "stretch": [1, 1], "pattern": "smooth", "role": "seat-base"}]},
    options
  );
  materialMap["clay_moped_wheel"] = createSculptMaterial(
    "clay_moped_wheel",
    {"id": "clay_moped_wheel", "baseColor": "#202425", "roughness": {"base": 0.76, "variation": 0.1}, "metalness": {"base": 0.0}, "clearcoat": {"base": 0.0}, "clearcoatRoughness": {"base": 0.9}, "normal": {"strength": 0.2}, "ambientOcclusion": {"cavityStrength": 0.25}, "colorVariation": {"palette": ["#202425", "#3A3E3F"], "amplitude": 0.08, "heightCorrelation": 0.15}, "surfaceFrequencyBands": [{"id": "tire-base", "frequency": 3, "amplitude": 0.2, "stretch": [1, 1], "pattern": "smooth", "role": "tire-base"}, {"id": "tire-tread", "frequency": 24, "amplitude": 0.08, "stretch": [1, 1], "pattern": "grain", "role": "tire-tread"}]},
    options
  );
  materialMap["clay_moped_dark"] = createSculptMaterial(
    "clay_moped_dark",
    {"id": "clay_moped_dark", "baseColor": "#202425", "roughness": {"base": 0.52, "variation": 0.06}, "metalness": {"base": 0.0}, "clearcoat": {"base": 0.1}, "clearcoatRoughness": {"base": 0.7}, "normal": {"strength": 0.12}, "ambientOcclusion": {"cavityStrength": 0.18}, "colorVariation": {"palette": ["#202425"], "amplitude": 0.04, "heightCorrelation": 0.08}, "surfaceFrequencyBands": [{"id": "dark-base", "frequency": 3, "amplitude": 0.12, "stretch": [1, 1], "pattern": "smooth", "role": "dark-base"}]},
    options
  );
  materialMap["clay_moped_chrome"] = createSculptMaterial(
    "clay_moped_chrome",
    {"id": "clay_moped_chrome", "baseColor": "#CEC7B8", "roughness": {"base": 0.3, "variation": 0.05}, "metalness": {"base": 0.0}, "clearcoat": {"base": 0.25}, "clearcoatRoughness": {"base": 0.4}, "normal": {"strength": 0.08}, "ambientOcclusion": {"cavityStrength": 0.12}, "colorVariation": {"palette": ["#CEC7B8"], "amplitude": 0.03, "heightCorrelation": 0.05}, "surfaceFrequencyBands": [{"id": "chrome-base", "frequency": 3, "amplitude": 0.08, "stretch": [1, 1], "pattern": "smooth", "role": "chrome-base"}]},
    options
  );
  materialMap["clay_moped_light"] = createSculptMaterial(
    "clay_moped_light",
    {"id": "clay_moped_light", "baseColor": "#F2EEE5", "roughness": {"base": 0.2, "variation": 0.03}, "metalness": {"base": 0.0}, "clearcoat": {"base": 0.3}, "clearcoatRoughness": {"base": 0.3}, "normal": {"strength": 0.05}, "ambientOcclusion": {"cavityStrength": 0.1}, "colorVariation": {"palette": ["#F2EEE5"], "amplitude": 0.02, "heightCorrelation": 0.03}, "surfaceFrequencyBands": [{"id": "light-base", "frequency": 3, "amplitude": 0.05, "stretch": [1, 1], "pattern": "smooth", "role": "light-base"}]},
    options
  );
  materialMap["clay_moped_taillight"] = createSculptMaterial(
    "clay_moped_taillight",
    {"id": "clay_moped_taillight", "baseColor": "#CC2020", "roughness": {"base": 0.25, "variation": 0.03}, "metalness": {"base": 0.0}, "clearcoat": {"base": 0.25}, "clearcoatRoughness": {"base": 0.35}, "normal": {"strength": 0.05}, "ambientOcclusion": {"cavityStrength": 0.1}, "colorVariation": {"palette": ["#CC2020"], "amplitude": 0.02, "heightCorrelation": 0.03}, "surfaceFrequencyBands": [{"id": "tail-base", "frequency": 3, "amplitude": 0.05, "stretch": [1, 1], "pattern": "smooth", "role": "tail-base"}]},
    options
  );

  const nodes: Record<string, THREE.Object3D> = { root };
  const meshes: Record<string, THREE.Mesh> = {};
  const sockets: Record<string, THREE.Object3D> = {};
  const colliders: Record<string, unknown> = {};
  const destructionGroups: Record<string, THREE.Object3D[]> = {};

  const attachment_body_shell_0 = null;
  const endpoint_body_shell_0 = makeAttachmentEndpoint(attachment_body_shell_0);
  const node_body_shell_0 = new THREE.Group();
  node_body_shell_0.name = "Body Shell__pivot";
  if (endpoint_body_shell_0) {
    node_body_shell_0.position.copy(endpoint_body_shell_0.start);
    node_body_shell_0.rotation.set(0, 0, 0);
    node_body_shell_0.scale.set(1, 1, 1);
  } else {
    node_body_shell_0.position.set(0.0, 0.28, 0.05);
    node_body_shell_0.rotation.set(0.0, 0.0, 0.0);
    node_body_shell_0.scale.set(1.0, 1.0, 1.0);
  }
  node_body_shell_0.userData.sculptComponent = {"id": "body_shell", "name": "Body Shell", "level": "macro", "primitive": "box", "dimensions": {"width": 0.42, "height": 0.32, "depth": 0.65}, "transform": {"position": [0, 0.28, 0.05], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_body", "topologyClass": "hard-surface", "topologyRationale": "Main red cowling covering the rear half of the moped"};
  node_body_shell_0.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_body_shell_0);
  nodes["body_shell"] = node_body_shell_0;
  const mesh_body_shell_0Geometry = endpoint_body_shell_0
    ? new THREE.CylinderGeometry(endpoint_body_shell_0.endRadius, endpoint_body_shell_0.baseRadius, endpoint_body_shell_0.length, 32, 12)
    : new THREE.BoxGeometry(1, 1, 1, 12, 12, 12);
  const mesh_body_shell_0 = new THREE.Mesh(
    mesh_body_shell_0Geometry,
    materialMap["clay_moped_body"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_body_shell_0.name = "Body Shell";
  if (endpoint_body_shell_0) {
    mesh_body_shell_0.position.copy(endpoint_body_shell_0.midpoint);
    mesh_body_shell_0.quaternion.copy(endpoint_body_shell_0.quaternion);
  }
  mesh_body_shell_0.castShadow = options.castShadow ?? true;
  mesh_body_shell_0.receiveShadow = options.receiveShadow ?? true;
  mesh_body_shell_0.userData.sculptComponent = {"id": "body_shell", "name": "Body Shell", "level": "macro", "primitive": "box", "dimensions": {"width": 0.42, "height": 0.32, "depth": 0.65}, "transform": {"position": [0, 0.28, 0.05], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_body", "topologyClass": "hard-surface", "topologyRationale": "Main red cowling covering the rear half of the moped"};
  node_body_shell_0.add(mesh_body_shell_0);
  meshes["body_shell"] = mesh_body_shell_0;
  colliders["body_shell"] = {};

  const attachment_front_shield_1 = null;
  const endpoint_front_shield_1 = makeAttachmentEndpoint(attachment_front_shield_1);
  const node_front_shield_1 = new THREE.Group();
  node_front_shield_1.name = "Front Leg Shield__pivot";
  if (endpoint_front_shield_1) {
    node_front_shield_1.position.copy(endpoint_front_shield_1.start);
    node_front_shield_1.rotation.set(0, 0, 0);
    node_front_shield_1.scale.set(1, 1, 1);
  } else {
    node_front_shield_1.position.set(0.0, 0.3, -0.25);
    node_front_shield_1.rotation.set(-0.15, 0.0, 0.0);
    node_front_shield_1.scale.set(1.0, 1.0, 1.0);
  }
  node_front_shield_1.userData.sculptComponent = {"id": "front_shield", "name": "Front Leg Shield", "level": "macro", "primitive": "box", "dimensions": {"width": 0.38, "height": 0.35, "depth": 0.08}, "transform": {"position": [0, 0.3, -0.25], "rotation": [-0.15, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_body", "topologyClass": "hard-surface", "topologyRationale": "Vertical front panel protecting the rider's legs"};
  node_front_shield_1.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_front_shield_1);
  nodes["front_shield"] = node_front_shield_1;
  const mesh_front_shield_1Geometry = endpoint_front_shield_1
    ? new THREE.CylinderGeometry(endpoint_front_shield_1.endRadius, endpoint_front_shield_1.baseRadius, endpoint_front_shield_1.length, 32, 12)
    : new THREE.BoxGeometry(1, 1, 1, 12, 12, 12);
  const mesh_front_shield_1 = new THREE.Mesh(
    mesh_front_shield_1Geometry,
    materialMap["clay_moped_body"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_front_shield_1.name = "Front Leg Shield";
  if (endpoint_front_shield_1) {
    mesh_front_shield_1.position.copy(endpoint_front_shield_1.midpoint);
    mesh_front_shield_1.quaternion.copy(endpoint_front_shield_1.quaternion);
  }
  mesh_front_shield_1.castShadow = options.castShadow ?? true;
  mesh_front_shield_1.receiveShadow = options.receiveShadow ?? true;
  mesh_front_shield_1.userData.sculptComponent = {"id": "front_shield", "name": "Front Leg Shield", "level": "macro", "primitive": "box", "dimensions": {"width": 0.38, "height": 0.35, "depth": 0.08}, "transform": {"position": [0, 0.3, -0.25], "rotation": [-0.15, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_body", "topologyClass": "hard-surface", "topologyRationale": "Vertical front panel protecting the rider's legs"};
  node_front_shield_1.add(mesh_front_shield_1);
  meshes["front_shield"] = mesh_front_shield_1;
  colliders["front_shield"] = {};

  const attachment_floorboard_2 = null;
  const endpoint_floorboard_2 = makeAttachmentEndpoint(attachment_floorboard_2);
  const node_floorboard_2 = new THREE.Group();
  node_floorboard_2.name = "Floorboard__pivot";
  if (endpoint_floorboard_2) {
    node_floorboard_2.position.copy(endpoint_floorboard_2.start);
    node_floorboard_2.rotation.set(0, 0, 0);
    node_floorboard_2.scale.set(1, 1, 1);
  } else {
    node_floorboard_2.position.set(0.0, 0.12, -0.08);
    node_floorboard_2.rotation.set(0.0, 0.0, 0.0);
    node_floorboard_2.scale.set(1.0, 1.0, 1.0);
  }
  node_floorboard_2.userData.sculptComponent = {"id": "floorboard", "name": "Floorboard", "level": "meso", "primitive": "box", "dimensions": {"width": 0.36, "height": 0.03, "depth": 0.35}, "transform": {"position": [0, 0.12, -0.08], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_dark", "topologyClass": "hard-surface", "topologyRationale": "Flat platform for the rider's feet"};
  node_floorboard_2.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_floorboard_2);
  nodes["floorboard"] = node_floorboard_2;
  const mesh_floorboard_2Geometry = endpoint_floorboard_2
    ? new THREE.CylinderGeometry(endpoint_floorboard_2.endRadius, endpoint_floorboard_2.baseRadius, endpoint_floorboard_2.length, 32, 12)
    : new THREE.BoxGeometry(1, 1, 1, 12, 12, 12);
  const mesh_floorboard_2 = new THREE.Mesh(
    mesh_floorboard_2Geometry,
    materialMap["clay_moped_dark"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_floorboard_2.name = "Floorboard";
  if (endpoint_floorboard_2) {
    mesh_floorboard_2.position.copy(endpoint_floorboard_2.midpoint);
    mesh_floorboard_2.quaternion.copy(endpoint_floorboard_2.quaternion);
  }
  mesh_floorboard_2.castShadow = options.castShadow ?? true;
  mesh_floorboard_2.receiveShadow = options.receiveShadow ?? true;
  mesh_floorboard_2.userData.sculptComponent = {"id": "floorboard", "name": "Floorboard", "level": "meso", "primitive": "box", "dimensions": {"width": 0.36, "height": 0.03, "depth": 0.35}, "transform": {"position": [0, 0.12, -0.08], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_dark", "topologyClass": "hard-surface", "topologyRationale": "Flat platform for the rider's feet"};
  node_floorboard_2.add(mesh_floorboard_2);
  meshes["floorboard"] = mesh_floorboard_2;
  colliders["floorboard"] = {};

  const attachment_seat_3 = null;
  const endpoint_seat_3 = makeAttachmentEndpoint(attachment_seat_3);
  const node_seat_3 = new THREE.Group();
  node_seat_3.name = "Seat Cushion__pivot";
  if (endpoint_seat_3) {
    node_seat_3.position.copy(endpoint_seat_3.start);
    node_seat_3.rotation.set(0, 0, 0);
    node_seat_3.scale.set(1, 1, 1);
  } else {
    node_seat_3.position.set(0.0, 0.48, 0.1);
    node_seat_3.rotation.set(0.0, 0.0, 0.0);
    node_seat_3.scale.set(1.0, 1.0, 1.0);
  }
  node_seat_3.userData.sculptComponent = {"id": "seat", "name": "Seat Cushion", "level": "meso", "primitive": "box", "dimensions": {"width": 0.28, "height": 0.08, "depth": 0.45}, "transform": {"position": [0, 0.48, 0.1], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_seat", "topologyClass": "hard-surface", "topologyRationale": "Elongated black seat cushion"};
  node_seat_3.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_seat_3);
  nodes["seat"] = node_seat_3;
  const mesh_seat_3Geometry = endpoint_seat_3
    ? new THREE.CylinderGeometry(endpoint_seat_3.endRadius, endpoint_seat_3.baseRadius, endpoint_seat_3.length, 32, 12)
    : new THREE.BoxGeometry(1, 1, 1, 12, 12, 12);
  const mesh_seat_3 = new THREE.Mesh(
    mesh_seat_3Geometry,
    materialMap["clay_moped_seat"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_seat_3.name = "Seat Cushion";
  if (endpoint_seat_3) {
    mesh_seat_3.position.copy(endpoint_seat_3.midpoint);
    mesh_seat_3.quaternion.copy(endpoint_seat_3.quaternion);
  }
  mesh_seat_3.castShadow = options.castShadow ?? true;
  mesh_seat_3.receiveShadow = options.receiveShadow ?? true;
  mesh_seat_3.userData.sculptComponent = {"id": "seat", "name": "Seat Cushion", "level": "meso", "primitive": "box", "dimensions": {"width": 0.28, "height": 0.08, "depth": 0.45}, "transform": {"position": [0, 0.48, 0.1], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_seat", "topologyClass": "hard-surface", "topologyRationale": "Elongated black seat cushion"};
  node_seat_3.add(mesh_seat_3);
  meshes["seat"] = mesh_seat_3;
  colliders["seat"] = {};

  const attachment_rear_wheel_4 = null;
  const endpoint_rear_wheel_4 = makeAttachmentEndpoint(attachment_rear_wheel_4);
  const node_rear_wheel_4 = new THREE.Group();
  node_rear_wheel_4.name = "Rear Wheel__pivot";
  if (endpoint_rear_wheel_4) {
    node_rear_wheel_4.position.copy(endpoint_rear_wheel_4.start);
    node_rear_wheel_4.rotation.set(0, 0, 0);
    node_rear_wheel_4.scale.set(1, 1, 1);
  } else {
    node_rear_wheel_4.position.set(0.0, 0.16, 0.35);
    node_rear_wheel_4.rotation.set(0.0, 0.0, 1.5708);
    node_rear_wheel_4.scale.set(1.0, 1.0, 1.0);
  }
  node_rear_wheel_4.userData.sculptComponent = {"id": "rear_wheel", "name": "Rear Wheel", "level": "meso", "primitive": "cylinder", "dimensions": {"radius": 0.16, "height": 0.08}, "transform": {"position": [0, 0.16, 0.35], "rotation": [0, 0, 1.5708], "scale": [1, 1, 1]}, "material": "clay_moped_wheel", "topologyClass": "hard-surface", "topologyRationale": "Rear wheel, oriented horizontally"};
  node_rear_wheel_4.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_rear_wheel_4);
  nodes["rear_wheel"] = node_rear_wheel_4;
  const mesh_rear_wheel_4Geometry = endpoint_rear_wheel_4
    ? new THREE.CylinderGeometry(endpoint_rear_wheel_4.endRadius, endpoint_rear_wheel_4.baseRadius, endpoint_rear_wheel_4.length, 32, 12)
    : new THREE.CylinderGeometry(0.5, 0.5, 1, 48, 16);
  const mesh_rear_wheel_4 = new THREE.Mesh(
    mesh_rear_wheel_4Geometry,
    materialMap["clay_moped_wheel"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_rear_wheel_4.name = "Rear Wheel";
  if (endpoint_rear_wheel_4) {
    mesh_rear_wheel_4.position.copy(endpoint_rear_wheel_4.midpoint);
    mesh_rear_wheel_4.quaternion.copy(endpoint_rear_wheel_4.quaternion);
  }
  mesh_rear_wheel_4.castShadow = options.castShadow ?? true;
  mesh_rear_wheel_4.receiveShadow = options.receiveShadow ?? true;
  mesh_rear_wheel_4.userData.sculptComponent = {"id": "rear_wheel", "name": "Rear Wheel", "level": "meso", "primitive": "cylinder", "dimensions": {"radius": 0.16, "height": 0.08}, "transform": {"position": [0, 0.16, 0.35], "rotation": [0, 0, 1.5708], "scale": [1, 1, 1]}, "material": "clay_moped_wheel", "topologyClass": "hard-surface", "topologyRationale": "Rear wheel, oriented horizontally"};
  node_rear_wheel_4.add(mesh_rear_wheel_4);
  meshes["rear_wheel"] = mesh_rear_wheel_4;
  colliders["rear_wheel"] = {};

  const attachment_front_wheel_5 = null;
  const endpoint_front_wheel_5 = makeAttachmentEndpoint(attachment_front_wheel_5);
  const node_front_wheel_5 = new THREE.Group();
  node_front_wheel_5.name = "Front Wheel__pivot";
  if (endpoint_front_wheel_5) {
    node_front_wheel_5.position.copy(endpoint_front_wheel_5.start);
    node_front_wheel_5.rotation.set(0, 0, 0);
    node_front_wheel_5.scale.set(1, 1, 1);
  } else {
    node_front_wheel_5.position.set(0.0, 0.16, -0.38);
    node_front_wheel_5.rotation.set(0.0, 0.0, 1.5708);
    node_front_wheel_5.scale.set(1.0, 1.0, 1.0);
  }
  node_front_wheel_5.userData.sculptComponent = {"id": "front_wheel", "name": "Front Wheel", "level": "meso", "primitive": "cylinder", "dimensions": {"radius": 0.16, "height": 0.08}, "transform": {"position": [0, 0.16, -0.38], "rotation": [0, 0, 1.5708], "scale": [1, 1, 1]}, "material": "clay_moped_wheel", "topologyClass": "hard-surface", "topologyRationale": "Front wheel, oriented horizontally"};
  node_front_wheel_5.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_front_wheel_5);
  nodes["front_wheel"] = node_front_wheel_5;
  const mesh_front_wheel_5Geometry = endpoint_front_wheel_5
    ? new THREE.CylinderGeometry(endpoint_front_wheel_5.endRadius, endpoint_front_wheel_5.baseRadius, endpoint_front_wheel_5.length, 32, 12)
    : new THREE.CylinderGeometry(0.5, 0.5, 1, 48, 16);
  const mesh_front_wheel_5 = new THREE.Mesh(
    mesh_front_wheel_5Geometry,
    materialMap["clay_moped_wheel"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_front_wheel_5.name = "Front Wheel";
  if (endpoint_front_wheel_5) {
    mesh_front_wheel_5.position.copy(endpoint_front_wheel_5.midpoint);
    mesh_front_wheel_5.quaternion.copy(endpoint_front_wheel_5.quaternion);
  }
  mesh_front_wheel_5.castShadow = options.castShadow ?? true;
  mesh_front_wheel_5.receiveShadow = options.receiveShadow ?? true;
  mesh_front_wheel_5.userData.sculptComponent = {"id": "front_wheel", "name": "Front Wheel", "level": "meso", "primitive": "cylinder", "dimensions": {"radius": 0.16, "height": 0.08}, "transform": {"position": [0, 0.16, -0.38], "rotation": [0, 0, 1.5708], "scale": [1, 1, 1]}, "material": "clay_moped_wheel", "topologyClass": "hard-surface", "topologyRationale": "Front wheel, oriented horizontally"};
  node_front_wheel_5.add(mesh_front_wheel_5);
  meshes["front_wheel"] = mesh_front_wheel_5;
  colliders["front_wheel"] = {};

  const attachment_front_fork_6 = null;
  const endpoint_front_fork_6 = makeAttachmentEndpoint(attachment_front_fork_6);
  const node_front_fork_6 = new THREE.Group();
  node_front_fork_6.name = "Front Fork__pivot";
  if (endpoint_front_fork_6) {
    node_front_fork_6.position.copy(endpoint_front_fork_6.start);
    node_front_fork_6.rotation.set(0, 0, 0);
    node_front_fork_6.scale.set(1, 1, 1);
  } else {
    node_front_fork_6.position.set(0.0, 0.3, -0.36);
    node_front_fork_6.rotation.set(0.0, 0.0, 0.0);
    node_front_fork_6.scale.set(1.0, 1.0, 1.0);
  }
  node_front_fork_6.userData.sculptComponent = {"id": "front_fork", "name": "Front Fork", "level": "meso", "primitive": "cylinder", "dimensions": {"radius": 0.02, "height": 0.3}, "transform": {"position": [0, 0.3, -0.36], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_dark", "topologyClass": "hard-surface", "topologyRationale": "Vertical fork connecting front wheel to handlebars"};
  node_front_fork_6.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_front_fork_6);
  nodes["front_fork"] = node_front_fork_6;
  const mesh_front_fork_6Geometry = endpoint_front_fork_6
    ? new THREE.CylinderGeometry(endpoint_front_fork_6.endRadius, endpoint_front_fork_6.baseRadius, endpoint_front_fork_6.length, 32, 12)
    : new THREE.CylinderGeometry(0.5, 0.5, 1, 48, 16);
  const mesh_front_fork_6 = new THREE.Mesh(
    mesh_front_fork_6Geometry,
    materialMap["clay_moped_dark"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_front_fork_6.name = "Front Fork";
  if (endpoint_front_fork_6) {
    mesh_front_fork_6.position.copy(endpoint_front_fork_6.midpoint);
    mesh_front_fork_6.quaternion.copy(endpoint_front_fork_6.quaternion);
  }
  mesh_front_fork_6.castShadow = options.castShadow ?? true;
  mesh_front_fork_6.receiveShadow = options.receiveShadow ?? true;
  mesh_front_fork_6.userData.sculptComponent = {"id": "front_fork", "name": "Front Fork", "level": "meso", "primitive": "cylinder", "dimensions": {"radius": 0.02, "height": 0.3}, "transform": {"position": [0, 0.3, -0.36], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_dark", "topologyClass": "hard-surface", "topologyRationale": "Vertical fork connecting front wheel to handlebars"};
  node_front_fork_6.add(mesh_front_fork_6);
  meshes["front_fork"] = mesh_front_fork_6;
  colliders["front_fork"] = {};

  const attachment_handlebar_7 = null;
  const endpoint_handlebar_7 = makeAttachmentEndpoint(attachment_handlebar_7);
  const node_handlebar_7 = new THREE.Group();
  node_handlebar_7.name = "Handlebar__pivot";
  if (endpoint_handlebar_7) {
    node_handlebar_7.position.copy(endpoint_handlebar_7.start);
    node_handlebar_7.rotation.set(0, 0, 0);
    node_handlebar_7.scale.set(1, 1, 1);
  } else {
    node_handlebar_7.position.set(0.0, 0.5, -0.34);
    node_handlebar_7.rotation.set(0.0, 0.0, 0.0);
    node_handlebar_7.scale.set(1.0, 1.0, 1.0);
  }
  node_handlebar_7.userData.sculptComponent = {"id": "handlebar", "name": "Handlebar", "level": "meso", "primitive": "box", "dimensions": {"width": 0.4, "height": 0.03, "depth": 0.03}, "transform": {"position": [0, 0.5, -0.34], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_dark", "topologyClass": "hard-surface", "topologyRationale": "Horizontal handlebar spanning the width"};
  node_handlebar_7.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_handlebar_7);
  nodes["handlebar"] = node_handlebar_7;
  const mesh_handlebar_7Geometry = endpoint_handlebar_7
    ? new THREE.CylinderGeometry(endpoint_handlebar_7.endRadius, endpoint_handlebar_7.baseRadius, endpoint_handlebar_7.length, 32, 12)
    : new THREE.BoxGeometry(1, 1, 1, 12, 12, 12);
  const mesh_handlebar_7 = new THREE.Mesh(
    mesh_handlebar_7Geometry,
    materialMap["clay_moped_dark"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_handlebar_7.name = "Handlebar";
  if (endpoint_handlebar_7) {
    mesh_handlebar_7.position.copy(endpoint_handlebar_7.midpoint);
    mesh_handlebar_7.quaternion.copy(endpoint_handlebar_7.quaternion);
  }
  mesh_handlebar_7.castShadow = options.castShadow ?? true;
  mesh_handlebar_7.receiveShadow = options.receiveShadow ?? true;
  mesh_handlebar_7.userData.sculptComponent = {"id": "handlebar", "name": "Handlebar", "level": "meso", "primitive": "box", "dimensions": {"width": 0.4, "height": 0.03, "depth": 0.03}, "transform": {"position": [0, 0.5, -0.34], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_dark", "topologyClass": "hard-surface", "topologyRationale": "Horizontal handlebar spanning the width"};
  node_handlebar_7.add(mesh_handlebar_7);
  meshes["handlebar"] = mesh_handlebar_7;
  colliders["handlebar"] = {};

  const attachment_front_basket_8 = null;
  const endpoint_front_basket_8 = makeAttachmentEndpoint(attachment_front_basket_8);
  const node_front_basket_8 = new THREE.Group();
  node_front_basket_8.name = "Front Basket__pivot";
  if (endpoint_front_basket_8) {
    node_front_basket_8.position.copy(endpoint_front_basket_8.start);
    node_front_basket_8.rotation.set(0, 0, 0);
    node_front_basket_8.scale.set(1, 1, 1);
  } else {
    node_front_basket_8.position.set(0.0, 0.42, -0.42);
    node_front_basket_8.rotation.set(0.0, 0.0, 0.0);
    node_front_basket_8.scale.set(1.0, 1.0, 1.0);
  }
  node_front_basket_8.userData.sculptComponent = {"id": "front_basket", "name": "Front Basket", "level": "micro", "primitive": "box", "dimensions": {"width": 0.25, "height": 0.1, "depth": 0.18}, "transform": {"position": [0, 0.42, -0.42], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_dark", "topologyClass": "hard-surface", "topologyRationale": "Wire basket mounted on front"};
  node_front_basket_8.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_front_basket_8);
  nodes["front_basket"] = node_front_basket_8;
  const mesh_front_basket_8Geometry = endpoint_front_basket_8
    ? new THREE.CylinderGeometry(endpoint_front_basket_8.endRadius, endpoint_front_basket_8.baseRadius, endpoint_front_basket_8.length, 32, 12)
    : new THREE.BoxGeometry(1, 1, 1, 12, 12, 12);
  const mesh_front_basket_8 = new THREE.Mesh(
    mesh_front_basket_8Geometry,
    materialMap["clay_moped_dark"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_front_basket_8.name = "Front Basket";
  if (endpoint_front_basket_8) {
    mesh_front_basket_8.position.copy(endpoint_front_basket_8.midpoint);
    mesh_front_basket_8.quaternion.copy(endpoint_front_basket_8.quaternion);
  }
  mesh_front_basket_8.castShadow = options.castShadow ?? true;
  mesh_front_basket_8.receiveShadow = options.receiveShadow ?? true;
  mesh_front_basket_8.userData.sculptComponent = {"id": "front_basket", "name": "Front Basket", "level": "micro", "primitive": "box", "dimensions": {"width": 0.25, "height": 0.1, "depth": 0.18}, "transform": {"position": [0, 0.42, -0.42], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_dark", "topologyClass": "hard-surface", "topologyRationale": "Wire basket mounted on front"};
  node_front_basket_8.add(mesh_front_basket_8);
  meshes["front_basket"] = mesh_front_basket_8;
  colliders["front_basket"] = {};

  const attachment_rear_rack_9 = null;
  const endpoint_rear_rack_9 = makeAttachmentEndpoint(attachment_rear_rack_9);
  const node_rear_rack_9 = new THREE.Group();
  node_rear_rack_9.name = "Rear Rack__pivot";
  if (endpoint_rear_rack_9) {
    node_rear_rack_9.position.copy(endpoint_rear_rack_9.start);
    node_rear_rack_9.rotation.set(0, 0, 0);
    node_rear_rack_9.scale.set(1, 1, 1);
  } else {
    node_rear_rack_9.position.set(0.0, 0.46, 0.38);
    node_rear_rack_9.rotation.set(0.0, 0.0, 0.0);
    node_rear_rack_9.scale.set(1.0, 1.0, 1.0);
  }
  node_rear_rack_9.userData.sculptComponent = {"id": "rear_rack", "name": "Rear Rack", "level": "micro", "primitive": "box", "dimensions": {"width": 0.2, "height": 0.02, "depth": 0.15}, "transform": {"position": [0, 0.46, 0.38], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_chrome", "topologyClass": "hard-surface", "topologyRationale": "Chrome rear grab rack"};
  node_rear_rack_9.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_rear_rack_9);
  nodes["rear_rack"] = node_rear_rack_9;
  const mesh_rear_rack_9Geometry = endpoint_rear_rack_9
    ? new THREE.CylinderGeometry(endpoint_rear_rack_9.endRadius, endpoint_rear_rack_9.baseRadius, endpoint_rear_rack_9.length, 32, 12)
    : new THREE.BoxGeometry(1, 1, 1, 12, 12, 12);
  const mesh_rear_rack_9 = new THREE.Mesh(
    mesh_rear_rack_9Geometry,
    materialMap["clay_moped_chrome"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_rear_rack_9.name = "Rear Rack";
  if (endpoint_rear_rack_9) {
    mesh_rear_rack_9.position.copy(endpoint_rear_rack_9.midpoint);
    mesh_rear_rack_9.quaternion.copy(endpoint_rear_rack_9.quaternion);
  }
  mesh_rear_rack_9.castShadow = options.castShadow ?? true;
  mesh_rear_rack_9.receiveShadow = options.receiveShadow ?? true;
  mesh_rear_rack_9.userData.sculptComponent = {"id": "rear_rack", "name": "Rear Rack", "level": "micro", "primitive": "box", "dimensions": {"width": 0.2, "height": 0.02, "depth": 0.15}, "transform": {"position": [0, 0.46, 0.38], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_chrome", "topologyClass": "hard-surface", "topologyRationale": "Chrome rear grab rack"};
  node_rear_rack_9.add(mesh_rear_rack_9);
  meshes["rear_rack"] = mesh_rear_rack_9;
  colliders["rear_rack"] = {};

  const attachment_headlight_10 = null;
  const endpoint_headlight_10 = makeAttachmentEndpoint(attachment_headlight_10);
  const node_headlight_10 = new THREE.Group();
  node_headlight_10.name = "Headlight__pivot";
  if (endpoint_headlight_10) {
    node_headlight_10.position.copy(endpoint_headlight_10.start);
    node_headlight_10.rotation.set(0, 0, 0);
    node_headlight_10.scale.set(1, 1, 1);
  } else {
    node_headlight_10.position.set(0.0, 0.42, -0.4);
    node_headlight_10.rotation.set(0.0, 0.0, 0.0);
    node_headlight_10.scale.set(1.0, 1.0, 1.0);
  }
  node_headlight_10.userData.sculptComponent = {"id": "headlight", "name": "Headlight", "level": "micro", "primitive": "sphere", "dimensions": {"radius": 0.04}, "transform": {"position": [0, 0.42, -0.4], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_light", "topologyClass": "hard-surface", "topologyRationale": "Small round headlight on the front"};
  node_headlight_10.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_headlight_10);
  nodes["headlight"] = node_headlight_10;
  const mesh_headlight_10Geometry = endpoint_headlight_10
    ? new THREE.CylinderGeometry(endpoint_headlight_10.endRadius, endpoint_headlight_10.baseRadius, endpoint_headlight_10.length, 32, 12)
    : new THREE.SphereGeometry(0.5, 64, 40);
  const mesh_headlight_10 = new THREE.Mesh(
    mesh_headlight_10Geometry,
    materialMap["clay_moped_light"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_headlight_10.name = "Headlight";
  if (endpoint_headlight_10) {
    mesh_headlight_10.position.copy(endpoint_headlight_10.midpoint);
    mesh_headlight_10.quaternion.copy(endpoint_headlight_10.quaternion);
  }
  mesh_headlight_10.castShadow = options.castShadow ?? true;
  mesh_headlight_10.receiveShadow = options.receiveShadow ?? true;
  mesh_headlight_10.userData.sculptComponent = {"id": "headlight", "name": "Headlight", "level": "micro", "primitive": "sphere", "dimensions": {"radius": 0.04}, "transform": {"position": [0, 0.42, -0.4], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_light", "topologyClass": "hard-surface", "topologyRationale": "Small round headlight on the front"};
  node_headlight_10.add(mesh_headlight_10);
  meshes["headlight"] = mesh_headlight_10;
  colliders["headlight"] = {};

  const attachment_taillight_11 = null;
  const endpoint_taillight_11 = makeAttachmentEndpoint(attachment_taillight_11);
  const node_taillight_11 = new THREE.Group();
  node_taillight_11.name = "Taillight__pivot";
  if (endpoint_taillight_11) {
    node_taillight_11.position.copy(endpoint_taillight_11.start);
    node_taillight_11.rotation.set(0, 0, 0);
    node_taillight_11.scale.set(1, 1, 1);
  } else {
    node_taillight_11.position.set(0.0, 0.38, 0.44);
    node_taillight_11.rotation.set(0.0, 0.0, 0.0);
    node_taillight_11.scale.set(1.0, 1.0, 1.0);
  }
  node_taillight_11.userData.sculptComponent = {"id": "taillight", "name": "Taillight", "level": "micro", "primitive": "box", "dimensions": {"width": 0.06, "height": 0.04, "depth": 0.02}, "transform": {"position": [0, 0.38, 0.44], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_taillight", "topologyClass": "hard-surface", "topologyRationale": "Small red taillight at the rear"};
  node_taillight_11.userData.actionProfile = {};
  (nodes["root"] ?? root).add(node_taillight_11);
  nodes["taillight"] = node_taillight_11;
  const mesh_taillight_11Geometry = endpoint_taillight_11
    ? new THREE.CylinderGeometry(endpoint_taillight_11.endRadius, endpoint_taillight_11.baseRadius, endpoint_taillight_11.length, 32, 12)
    : new THREE.BoxGeometry(1, 1, 1, 12, 12, 12);
  const mesh_taillight_11 = new THREE.Mesh(
    mesh_taillight_11Geometry,
    materialMap["clay_moped_taillight"] ?? new THREE.MeshStandardMaterial({ color: 0x888888 })
  );
  mesh_taillight_11.name = "Taillight";
  if (endpoint_taillight_11) {
    mesh_taillight_11.position.copy(endpoint_taillight_11.midpoint);
    mesh_taillight_11.quaternion.copy(endpoint_taillight_11.quaternion);
  }
  mesh_taillight_11.castShadow = options.castShadow ?? true;
  mesh_taillight_11.receiveShadow = options.receiveShadow ?? true;
  mesh_taillight_11.userData.sculptComponent = {"id": "taillight", "name": "Taillight", "level": "micro", "primitive": "box", "dimensions": {"width": 0.06, "height": 0.04, "depth": 0.02}, "transform": {"position": [0, 0.38, 0.44], "rotation": [0, 0, 0], "scale": [1, 1, 1]}, "material": "clay_moped_taillight", "topologyClass": "hard-surface", "topologyRationale": "Small red taillight at the rear"};
  node_taillight_11.add(mesh_taillight_11);
  meshes["taillight"] = mesh_taillight_11;
  colliders["taillight"] = {};

  root.userData.sculptRuntime = { nodes, meshes, sockets, colliders, destructionGroups } satisfies ProceduralModelRuntime;
  root.userData.lookDevTargets = {};
  root.userData.actionReadiness = {
    note: 'Use root.userData.sculptRuntime.nodes for transforms, sockets for attachments, colliders for physics proxies, and destructionGroups for breakable sets.',
  };
  return root;
}

export function createClayRedElectricMopedLookDevLights(
  mode: 'neutral' | 'grazing' | 'reference' = 'neutral',
): THREE.Group {
  const lights = new THREE.Group();
  lights.name = "Clay Red Electric Moped look-dev lights";
  const hemi = new THREE.HemisphereLight(
    mode === 'reference' ? 0xfff0d6 : 0xf2f4ff,
    0x363b42,
    mode === 'grazing' ? 0.28 : mode === 'reference' ? 0.72 : 0.85,
  );
  lights.add(hemi);
  const key = new THREE.DirectionalLight(
    mode === 'reference' ? 0xffcf8a : 0xfff4e8,
    mode === 'grazing' ? 4.2 : mode === 'reference' ? 2.6 : 2.15,
  );
  if (mode === 'grazing') key.position.set(7.5, 1.1, 4.0);
  else if (mode === 'reference') key.position.set(-4.5, 7.5, 5.0);
  else key.position.set(-4.0, 6.0, 5.5);
  key.castShadow = true;
  key.shadow.mapSize.set(4096, 4096);
  key.shadow.bias = -0.00025;
  key.shadow.normalBias = 0.018;
  lights.add(key);
  const fill = new THREE.DirectionalLight(0xa8c4ff, mode === 'grazing' ? 0.12 : 0.42);
  fill.position.set(4.0, 3.0, 3.5);
  lights.add(fill);
  const rim = new THREE.DirectionalLight(0xfff1c4, mode === 'grazing' ? 0.28 : 0.85);
  rim.position.set(0.5, 4.5, -6.0);
  lights.add(rim);
  lights.userData.reviewMode = mode;
  lights.userData.lightingFromPhoto = [];
  lights.userData.lookDevTargets = {};
  return lights;
}
