// diorama/clay-camera.ts — Camera framing for Desktop and iOS portrait.
// Provides OrbitControls setup, aspect-aware adjustments, and auto-framing.

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type { CameraSpec } from './contracts';

// ---------------------------------------------------------------------------
// Constants — Desktop
// ---------------------------------------------------------------------------

const DESKTOP_FOV = 45;
const DESKTOP_POSITION: [number, number, number] = [8, 6, 8];
const DESKTOP_TARGET: [number, number, number] = [0, 0.5, 0];

const DESKTOP_CONTROLS = {
  minPolarAngle: 0.2,        // don't go underground
  maxPolarAngle: 1.4,        // don't go too flat
  minDistance: 4,
  maxDistance: 20,
  enableDamping: true,
  dampingFactor: 0.08,
  rotateSpeed: 0.5,
} as const;

// ---------------------------------------------------------------------------
// Constants — iOS Portrait
// ---------------------------------------------------------------------------

const PORTRAIT_FOV = 55;                                   // wider for 9:16
const PORTRAIT_POSITION: [number, number, number] = [6, 5, 10]; // further back
const PORTRAIT_TARGET: [number, number, number] = [0, 1, 0];    // slightly higher

// Portrait inherits the same orbit constraints as desktop.
const PORTRAIT_CONTROLS = {
  ...DESKTOP_CONTROLS,
};

// Portrait aspect threshold: anything narrower than 3:4 is treated as portrait.
const PORTRAIT_ASPECT_THRESHOLD = 3 / 4;

// Margin factor for auto-framing (1.3 = 30 % padding around bounding box).
const FRAME_MARGIN = 1.3;

// ---------------------------------------------------------------------------
// Return type
// ---------------------------------------------------------------------------

export interface ClayCameraHandle {
  camera: THREE.PerspectiveCamera;
  controls: OrbitControls;
}

// ---------------------------------------------------------------------------
// Previous-frame state (for smooth transitions in frameScene)
// ---------------------------------------------------------------------------

let _prevCameraPos: THREE.Vector3 | null = null;
let _prevTarget: THREE.Vector3 | null = null;

// ---------------------------------------------------------------------------
// createClayCamera
// ---------------------------------------------------------------------------

/**
 * Create a PerspectiveCamera + OrbitControls pair tuned for the current
 * orientation.  Attach to `container` (controls bind to its first canvas or
 * to the container itself for pointer events).
 */
export function createClayCamera(
  container: HTMLElement,
  isPortrait: boolean,
  cameraSpec?: CameraSpec,
): ClayCameraHandle {
  const aspect = getAspect(container);

  // Resolve spec values with portrait overrides applied.
  const fov = resolveFov(isPortrait, cameraSpec);
  const position = resolvePosition(isPortrait, cameraSpec);
  const target = resolveTarget(isPortrait, cameraSpec);

  // Camera
  const camera = new THREE.PerspectiveCamera(fov, aspect, 0.1, 100);
  camera.position.set(...position);
  camera.lookAt(new THREE.Vector3(...target));

  // Controls — bind to the canvas if one already exists, otherwise the
  // container (the caller is expected to append a canvas later).
  const domElement = container.querySelector('canvas') ?? container;
  const ctrlOpts = isPortrait ? PORTRAIT_CONTROLS : DESKTOP_CONTROLS;

  const controls = new OrbitControls(camera, domElement);
  controls.target.set(...target);
  controls.minPolarAngle = ctrlOpts.minPolarAngle;
  controls.maxPolarAngle = ctrlOpts.maxPolarAngle;
  controls.minDistance = ctrlOpts.minDistance;
  controls.maxDistance = ctrlOpts.maxDistance;
  controls.enableDamping = ctrlOpts.enableDamping;
  controls.dampingFactor = ctrlOpts.dampingFactor;
  controls.rotateSpeed = ctrlOpts.rotateSpeed;
  controls.update();

  // Reset transition state for a fresh scene.
  _prevCameraPos = null;
  _prevTarget = null;

  return { camera, controls };
}

// ---------------------------------------------------------------------------
// updateCameraForAspect
// ---------------------------------------------------------------------------

/**
 * Update `camera` projection and position for the current container aspect.
 * Call on resize or orientation change.
 *
 * @param camera   The PerspectiveCamera to adjust.
 * @param aspect   Width / height of the container.
 * @param isPortrait  Whether the device is in portrait orientation.
 * @param cameraSpec  Optional scene graph camera spec for portrait offsets.
 */
export function updateCameraForAspect(
  camera: THREE.PerspectiveCamera,
  aspect: number,
  isPortrait: boolean,
  cameraSpec?: CameraSpec,
): void {
  camera.aspect = aspect;

  if (isPortrait) {
    camera.fov = PORTRAIT_FOV;
    const pos = resolvePosition(true, cameraSpec);
    const tgt = resolveTarget(true, cameraSpec);
    camera.position.set(...pos);
    camera.lookAt(new THREE.Vector3(...tgt));
  } else {
    camera.fov = DESKTOP_FOV;
    const pos = resolvePosition(false, cameraSpec);
    const tgt = resolveTarget(false, cameraSpec);
    camera.position.set(...pos);
    camera.lookAt(new THREE.Vector3(...tgt));
  }

  camera.updateProjectionMatrix();
}

// ---------------------------------------------------------------------------
// frameScene
// ---------------------------------------------------------------------------

/**
 * Auto-frame the camera to fit all supplied entities within view with margin.
 * On the first call the jump is instant; subsequent calls animate smoothly
 * from the previous camera state.
 */
export function frameScene(
  camera: THREE.PerspectiveCamera,
  controls: OrbitControls,
  entities: { mesh: THREE.Object3D }[],
): void {
  if (entities.length === 0) return;

  // 1. Compute bounding box of all entities.
  const box = new THREE.Box3();
  for (const ent of entities) {
    box.expandByObject(ent.mesh);
  }

  if (box.isEmpty()) return;

  const center = new THREE.Vector3();
  box.getCenter(center);

  const size = new THREE.Vector3();
  box.getSize(size);

  // 2. Determine the distance needed to fit the bounding sphere.
  const maxExtent = Math.max(size.x, size.y, size.z);
  const fovRad = THREE.MathUtils.degToRad(camera.fov);
  const fitRadius = (maxExtent * FRAME_MARGIN) / 2;

  // Distance to fit vertically.
  let distance = fitRadius / Math.sin(fovRad / 2);

  // Also account for horizontal extent if the aspect is wide.
  const aspect = camera.aspect;
  const hFov = 2 * Math.atan(Math.tan(fovRad / 2) * aspect);
  const hDist = fitRadius / Math.sin(hFov / 2);
  distance = Math.max(distance, hDist);

  // Ensure we stay within orbit distance constraints.
  distance = Math.max(distance, controls.minDistance);
  distance = Math.min(distance, controls.maxDistance);

  // 3. Position camera along its current direction vector (keep viewing angle).
  const direction = new THREE.Vector3();
  camera.getWorldDirection(direction);
  direction.normalize();

  const newCameraPos = new THREE.Vector3()
    .copy(center)
    .sub(direction.multiplyScalar(distance));

  // Ensure minimum height to avoid ground clipping.
  newCameraPos.y = Math.max(newCameraPos.y, 0.5);

  // 4. Animate or jump.
  if (_prevCameraPos && _prevTarget) {
    animateTransition(camera, controls, newCameraPos, center);
  } else {
    // First frame — jump instantly.
    camera.position.copy(newCameraPos);
    controls.target.copy(center);
    controls.update();
  }

  // Store for next transition.
  _prevCameraPos = newCameraPos.clone();
  _prevTarget = center.clone();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getAspect(container: HTMLElement): number {
  const rect = container.getBoundingClientRect();
  const w = rect.width || 800;
  const h = rect.height || 600;
  return w / h;
}

function resolveFov(isPortrait: boolean, spec?: CameraSpec): number {
  if (isPortrait) return PORTRAIT_FOV;
  return spec?.fov ?? DESKTOP_FOV;
}

function resolvePosition(
  isPortrait: boolean,
  spec?: CameraSpec,
): [number, number, number] {
  if (isPortrait) {
    const base = [...PORTRAIT_POSITION] as [number, number, number];
    if (spec?.portraitOffset) {
      base[0] += spec.portraitOffset[0];
      base[2] += spec.portraitOffset[1];
    }
    return base;
  }
  return spec?.position ?? DESKTOP_POSITION;
}

function resolveTarget(
  isPortrait: boolean,
  spec?: CameraSpec,
): [number, number, number] {
  return isPortrait ? PORTRAIT_TARGET : (spec?.target ?? DESKTOP_TARGET);
}

// ---------------------------------------------------------------------------
// Smooth transition
// ---------------------------------------------------------------------------

const ANIM_DURATION_MS = 600;

function animateTransition(
  camera: THREE.PerspectiveCamera,
  controls: OrbitControls,
  targetPos: THREE.Vector3,
  targetLookAt: THREE.Vector3,
): void {
  const startPos = camera.position.clone();
  const startTarget = controls.target.clone();
  const startTime = performance.now();

  function tick() {
    const elapsed = performance.now() - startTime;
    const t = Math.min(elapsed / ANIM_DURATION_MS, 1);
    // Ease-out cubic.
    const e = 1 - Math.pow(1 - t, 3);

    camera.position.lerpVectors(startPos, targetPos, e);
    controls.target.lerpVectors(startTarget, targetLookAt, e);
    controls.update();

    if (t < 1) {
      requestAnimationFrame(tick);
    }
  }

  requestAnimationFrame(tick);
}

// ---------------------------------------------------------------------------
// Convenience: detect portrait from window (for callers that don't know yet)
// ---------------------------------------------------------------------------

export function detectPortrait(): boolean {
  if (typeof window === 'undefined') return false;
  const aspect = window.innerWidth / window.innerHeight;
  return aspect < PORTRAIT_ASPECT_THRESHOLD;
}
