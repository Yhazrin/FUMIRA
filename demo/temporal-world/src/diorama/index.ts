// diorama/index.ts — Single public surface for the Diorama Runtime.
// Both Desktop and iOS import from this barrel; they never reach into internals.

export { DioramaRuntime } from './scene-runtime';
export type { DioramaRuntimeOptions } from './scene-runtime';
export { NativeBridge } from './native-bridge';
export * from './contracts';
export {
  createClayBox,
  createClayCylinder,
  createClaySphere,
  createClayBlob,
  createClayPlane,
  createClayMaterial,
  createGeometry,
  hashString,
} from './clay-builders';
export {
  CLAY_PRESETS,
  mulberry32,
} from './clay-materials';
export type { ClayPresetKey } from './clay-materials';
export {
  createBeveledBox,
  createBeveledCylinder,
  createOrganicBlob,
  createGroundPlane,
  createRoad,
} from './clay-geometry';
export {
  createClayCamera,
  updateCameraForAspect,
  frameScene,
  detectPortrait,
} from './clay-camera';
export type { ClayCameraHandle } from './clay-camera';
export {
  createClayLighting,
  createContactShadow,
  addContactShadowToEntity,
  LightingRig,
} from './clay-lighting';
