// diorama/clay-lighting.ts — Warm photographic studio lighting for the Diorama.
// Three-point rig (key / fill / rim) + hemisphere ambient + contact shadows.
// All assets are self-contained; no external textures needed.

import * as THREE from 'three';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Warm cream background — NOT pure white, NOT dark. */
const BACKGROUND_COLOR = '#F7F5EF';

/** Key light — moccasin / warm white. */
const KEY_COLOR = '#FFE4B5';
const KEY_INTENSITY = 1.2;
const KEY_POSITION: [number, number, number] = [5, 8, 3];

/** Fill light — warm grey. */
const FILL_COLOR = '#E8E0D4';
const FILL_INTENSITY = 0.4;
const FILL_POSITION: [number, number, number] = [-3, 4, -2];

/** Rim light — warm white. */
const RIM_COLOR = '#FFF5E6';
const RIM_INTENSITY = 0.3;
const RIM_POSITION: [number, number, number] = [0, 6, -5];

/** Hemisphere ambient — sky / ground. */
const AMBIENT_SKY = '#F7F5EF';
const AMBIET_GROUND = '#D4C5A9';
const AMBIENT_INTENSITY = 0.5;

/** Subtle animation parameters for the update() loop. */
const KEY_SWAY_AMPLITUDE = 0.15;   // positional drift in world units
const KEY_SWAY_SPEED = 0.0003;     // radians per ms — very slow

// ---------------------------------------------------------------------------
// LightingRig — owns every light and exposes a single update() tick
// ---------------------------------------------------------------------------

export class LightingRig {
  /** All lights managed by this rig. */
  public readonly keyLight: THREE.DirectionalLight;
  public readonly fillLight: THREE.DirectionalLight;
  public readonly rimLight: THREE.DirectionalLight;
  public readonly ambientLight: THREE.HemisphereLight;

  /** The scene this rig was added to (for teardown). */
  private scene: THREE.Scene;

  /** Original key-light position (used as anchor for sway animation). */
  private readonly keyOrigin: THREE.Vector3;

  /** Elapsed time accumulator (ms). */
  private elapsed = 0;

  constructor(scene: THREE.Scene) {
    this.scene = scene;

    // -- Key Light (warm, casts shadows) --------------------------------------
    this.keyLight = new THREE.DirectionalLight(
      new THREE.Color(KEY_COLOR),
      KEY_INTENSITY,
    );
    this.keyLight.position.set(...KEY_POSITION);
    this.keyLight.castShadow = true;
    this.keyLight.shadow.mapSize.set(2048, 2048);
    this.keyLight.shadow.bias = -0.0001;
    this.keyLight.shadow.radius = 4; // soft PCF edges
    // Shadow frustum — generous default; callers may tighten after framing.
    const d = 12;
    this.keyLight.shadow.camera.near = 0.5;
    this.keyLight.shadow.camera.far = 40;
    this.keyLight.shadow.camera.left = -d;
    this.keyLight.shadow.camera.right = d;
    this.keyLight.shadow.camera.top = d;
    this.keyLight.shadow.camera.bottom = -d;
    this.keyOrigin = this.keyLight.position.clone();

    // -- Fill Light (soft, no shadow) -----------------------------------------
    this.fillLight = new THREE.DirectionalLight(
      new THREE.Color(FILL_COLOR),
      FILL_INTENSITY,
    );
    this.fillLight.position.set(...FILL_POSITION);

    // -- Rim Light (subtle back light, no shadow) -----------------------------
    this.rimLight = new THREE.DirectionalLight(
      new THREE.Color(RIM_COLOR),
      RIM_INTENSITY,
    );
    this.rimLight.position.set(...RIM_POSITION);

    // -- Hemisphere ambient ----------------------------------------------------
    this.ambientLight = new THREE.HemisphereLight(
      new THREE.Color(AMBIENT_SKY),
      new THREE.Color(AMBIET_GROUND),
      AMBIENT_INTENSITY,
    );

    // -- Add to scene ---------------------------------------------------------
    scene.add(this.keyLight);
    scene.add(this.fillLight);
    scene.add(this.rimLight);
    scene.add(this.ambientLight);

    // -- Scene background -----------------------------------------------------
    scene.background = new THREE.Color(BACKGROUND_COLOR);
  }

  // -------------------------------------------------------------------------
  // Per-frame update — subtle key-light sway for life-like warmth
  // -------------------------------------------------------------------------

  /**
   * Call once per frame with the frame delta in milliseconds.
   * Drives a gentle positional drift on the key light so the scene
   * never feels perfectly static.
   */
  update(deltaMs: number): void {
    this.elapsed += deltaMs;

    // Slow elliptical sway around the origin position
    const t = this.elapsed * KEY_SWAY_SPEED;
    this.keyLight.position.set(
      this.keyOrigin.x + Math.sin(t) * KEY_SWAY_AMPLITUDE,
      this.keyOrigin.y + Math.cos(t * 0.7) * KEY_SWAY_AMPLITUDE * 0.5,
      this.keyOrigin.z + Math.sin(t * 0.5) * KEY_SWAY_AMPLITUDE * 0.3,
    );
  }

  // -------------------------------------------------------------------------
  // Teardown
  // -------------------------------------------------------------------------

  dispose(): void {
    this.scene.remove(this.keyLight);
    this.scene.remove(this.fillLight);
    this.scene.remove(this.rimLight);
    this.scene.remove(this.ambientLight);

    this.keyLight.dispose();
    this.fillLight.dispose();
    this.rimLight.dispose();
    this.ambientLight.dispose();
  }
}

// ---------------------------------------------------------------------------
// Contact shadow — transparent plane with radial gradient
// ---------------------------------------------------------------------------

/**
 * Creates a contact-shadow mesh: a plane with a radial-gradient texture
 * (dark centre fading to transparent edges).  Place it just below each
 * entity for a grounding effect.
 *
 * @param width  Footprint width  (X axis).
 * @param depth  Footprint depth  (Z axis).
 * @returns      A Mesh ready to be added to the scene.
 */
export function createContactShadow(
  width: number,
  depth: number,
): THREE.Mesh {
  // Generate a radial gradient texture on a canvas
  const size = 256;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d')!;

  const cx = size / 2;
  const cy = size / 2;
  const radius = size / 2;

  const gradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
  gradient.addColorStop(0, 'rgba(60, 50, 40, 0.35)');   // dark centre
  gradient.addColorStop(0.4, 'rgba(60, 50, 40, 0.18)');
  gradient.addColorStop(1, 'rgba(60, 50, 40, 0.0)');    // transparent edge

  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);

  const texture = new THREE.CanvasTexture(canvas);
  texture.needsUpdate = true;

  const geometry = new THREE.PlaneGeometry(width, depth);
  geometry.rotateX(-Math.PI / 2);

  const material = new THREE.MeshBasicMaterial({
    map: texture,
    transparent: true,
    depthWrite: false,
    opacity: 1,
  });

  const mesh = new THREE.Mesh(geometry, material);
  mesh.renderOrder = -1; // draw before opaque geometry
  mesh.name = '__contact_shadow__';

  return mesh;
}

// ---------------------------------------------------------------------------
// Convenience factory — sets up everything in one call
// ---------------------------------------------------------------------------

/**
 * Creates the full warm-studio lighting rig, adds contact shadows under
 * every existing mesh in the scene, and sets the warm cream background.
 *
 * @param scene The THREE.Scene to light.
 * @returns     The LightingRig instance (call .update() each frame, .dispose() on teardown).
 */
export function createClayLighting(scene: THREE.Scene): LightingRig {
  const rig = new LightingRig(scene);

  // Add contact shadows under every existing mesh that isn't a special helper
  scene.traverse((child) => {
    if (child instanceof THREE.Mesh && !child.name.startsWith('__')) {
      addContactShadowToEntity(child, scene);
    }
  });

  return rig;
}

// ---------------------------------------------------------------------------
// Helper — compute footprint from bounding box and place contact shadow
// ---------------------------------------------------------------------------

/**
 * Adds a contact-shadow plane beneath a mesh based on its bounding box.
 * Shadow is parented to the same parent as the entity so it moves together.
 */
export function addContactShadowToEntity(
  entityMesh: THREE.Mesh,
  scene: THREE.Scene,
): void {
  const bbox = new THREE.Box3().setFromObject(entityMesh);
  const size = new THREE.Vector3();
  bbox.getSize(size);

  // Shadow should be slightly larger than the footprint
  const shadowWidth = Math.max(size.x * 1.3, 0.3);
  const shadowDepth = Math.max(size.z * 1.3, 0.3);

  const shadow = createContactShadow(shadowWidth, shadowDepth);

  // Position at the base of the entity
  shadow.position.set(
    entityMesh.position.x,
    bbox.min.y + 0.005, // just above ground to avoid z-fighting
    entityMesh.position.z,
  );

  scene.add(shadow);
}
