/**
 * @module scene-runtime
 *
 * Three.js Runtime for FUMIRA's temporal clay world.
 *
 * Receives scene manifests from the Scene Compiler via WebSocket,
 * creates/updates/removes Three.js Object3D entities, manages clay-style
 * materials, temporal interpolation, LOD switching, and GLB asset loading.
 *
 * Pipeline:
 *   Scene Compiler  --[WebSocket]-->  SceneRuntime  --[Three.js]-->  Canvas
 *
 * Usage (from desktop.html):
 *   import { SceneRuntime } from './scene-runtime.js';
 *   const runtime = new SceneRuntime(canvas, 'ws://localhost:3211/ws/scene');
 *   runtime.connect();
 *   runtime.setTimeValue(2026);
 */

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

// ──────────────────────────────────────────────────────────────────
//  Utilities
// ──────────────────────────────────────────────────────────────────

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function clamp01(t) {
  return Math.max(0, Math.min(1, t));
}

function hexColor(str) {
  if (typeof str === 'number') return str;
  return parseInt(str.replace('#', ''), 16);
}

// ──────────────────────────────────────────────────────────────────
//  Geometry Factory
//  Converts a SceneGeometryDefinition (from the compiler manifest)
//  into a live THREE.BufferGeometry instance.
// ──────────────────────────────────────────────────────────────────

function createGeometry(spec) {
  if (!spec) return new THREE.BoxGeometry(0.5, 0.5, 0.5);

  switch (spec.type) {
    case 'BoxGeometry':
      return new THREE.BoxGeometry(
        spec.width ?? 1, spec.height ?? 1, spec.depth ?? 1,
        spec.widthSegments, spec.heightSegments, spec.depthSegments,
      );

    case 'SphereGeometry':
      return new THREE.SphereGeometry(
        spec.radius ?? 0.5,
        spec.widthSegments ?? 16, spec.heightSegments ?? 12,
        spec.phiStart ?? 0, spec.phiLength ?? Math.PI * 2,
        spec.thetaStart ?? 0, spec.thetaLength ?? Math.PI,
      );

    case 'CylinderGeometry':
      return new THREE.CylinderGeometry(
        spec.radiusTop ?? 0.5, spec.radiusBottom ?? 0.5,
        spec.height ?? 1, spec.radialSegments ?? 16,
        spec.heightSegments ?? 1, spec.openEnded ?? false,
        spec.thetaStart ?? 0, spec.thetaLength ?? Math.PI * 2,
      );

    case 'PlaneGeometry':
      return new THREE.PlaneGeometry(
        spec.width ?? 1, spec.height ?? 1,
        spec.widthSegments, spec.heightSegments,
      );

    case 'CapsuleGeometry':
      return new THREE.CapsuleGeometry(
        spec.radius ?? 0.5, spec.length ?? 1,
        spec.capSegments ?? 4, spec.radialSegments ?? 8,
      );

    case 'TorusGeometry':
      return new THREE.TorusGeometry(
        spec.radius ?? 0.5, spec.tube ?? 0.2,
        spec.radialSegments ?? 8, spec.tubularSegments ?? 16,
      );

    case 'BufferGeometry':
      // GLB/GLTF loading is handled asynchronously — return a placeholder
      // that will be replaced once the asset loads.
      return new THREE.BoxGeometry(0.01, 0.01, 0.01);

    case 'MorphGeometry':
      // For morph targets, create the base geometry — morph targets
      // are applied later via temporal blending.
      return createGeometry(spec.base);

    default:
      console.warn(`[SceneRuntime] Unknown geometry type: ${spec.type}`);
      return new THREE.BoxGeometry(0.5, 0.5, 0.5);
  }
}

// ──────────────────────────────────────────────────────────────────
//  Material Factory
//  FUMIRA clay aesthetic: high roughness, low metalness, warm palette.
// ──────────────────────────────────────────────────────────────────

const CLAY_DEFAULTS = {
  roughness: 0.84,
  metalness: 0.0,
  flatShading: false,
};

function createMaterial(spec) {
  if (!spec) {
    return new THREE.MeshStandardMaterial({
      color: 0xF2EEE5,
      ...CLAY_DEFAULTS,
    });
  }

  const color = spec.color ? hexColor(spec.color) : 0xF2EEE5;

  const mat = new THREE.MeshStandardMaterial({
    color,
    roughness: spec.roughness ?? CLAY_DEFAULTS.roughness,
    metalness: spec.metalness ?? CLAY_DEFAULTS.metalness,
    flatShading: spec.flatShading ?? CLAY_DEFAULTS.flatShading,
    transparent: spec.transparent ?? false,
    opacity: spec.opacity ?? 1.0,
    wireframe: spec.wireframe ?? false,
    emissive: spec.emissive ? hexColor(spec.emissive) : undefined,
    emissiveIntensity: spec.emissiveIntensity,
  });

  if (spec.side === 'double') mat.side = THREE.DoubleSide;
  else if (spec.side === 'back') mat.side = THREE.BackSide;

  // Store base color for temporal tinting (weathering, seasons, etc.)
  mat.userData = {
    ...spec.userData,
    baseColor: new THREE.Color(color),
  };

  return mat;
}

/**
 * Convenience: create a clay material from a color number + overrides.
 * Matches the clayMat() signature used in desktop.html and clay-builders.
 */
export function clayMat(color, opts = {}) {
  const mat = new THREE.MeshStandardMaterial({
    color,
    roughness: opts.roughness ?? CLAY_DEFAULTS.roughness,
    metalness: opts.metalness ?? CLAY_DEFAULTS.metalness,
    flatShading: opts.flatShading ?? CLAY_DEFAULTS.flatShading,
    ...opts,
  });
  mat.userData = { baseColor: new THREE.Color(color) };
  return mat;
}

// ──────────────────────────────────────────────────────────────────
//  Entity Creation
//  Hydrates a SceneNodeDefinition tree into live THREE.Object3D nodes.
// ──────────────────────────────────────────────────────────────────

/**
 * Recursively create a Three.js object from a SceneNodeDefinition.
 * Handles groups, meshes, LOD groups, and lights.
 */
function hydrateNode(nodeDef, gltfLoader, assetCache) {
  let object;

  switch (nodeDef.type) {
    case 'mesh': {
      const geometry = createGeometry(nodeDef.mesh?.geometry);
      const material = createMaterial(nodeDef.mesh?.material);
      const mesh = new THREE.Mesh(geometry, material);
      mesh.castShadow = nodeDef.mesh?.castShadow ?? true;
      mesh.receiveShadow = nodeDef.mesh?.receiveShadow ?? true;
      if (nodeDef.mesh?.userData) {
        Object.assign(mesh.userData, nodeDef.mesh.userData);
      }
      object = mesh;

      // If this is a BufferGeometry (GLB), kick off async loading
      if (nodeDef.mesh?.geometry?.type === 'BufferGeometry' && nodeDef.mesh.geometry.assetId) {
        loadGLBAsset(nodeDef.mesh.geometry.assetId, mesh, gltfLoader, assetCache);
      }
      break;
    }

    case 'lod-group': {
      const lod = new THREE.LOD();
      if (nodeDef.lodEntries) {
        for (const entry of nodeDef.lodEntries) {
          const lodMesh = new THREE.Mesh(
            createGeometry(entry.mesh?.geometry),
            createMaterial(entry.mesh?.material),
          );
          lodMesh.castShadow = entry.mesh?.castShadow ?? true;
          lodMesh.receiveShadow = entry.mesh?.receiveShadow ?? true;
          lod.addLevel(lodMesh, entry.distance ?? 0);
        }
      }
      object = lod;
      break;
    }

    case 'ambient-light': {
      const lightDef = nodeDef.light;
      const light = new THREE.AmbientLight(
        hexColor(lightDef?.color ?? '#F2EEE5'),
        lightDef?.intensity ?? 0.35,
      );
      object = light;
      break;
    }

    case 'directional-light': {
      const lightDef = nodeDef.light;
      const light = new THREE.DirectionalLight(
        hexColor(lightDef?.color ?? '#FFF5E8'),
        lightDef?.intensity ?? 1.0,
      );
      if (lightDef?.position) {
        light.position.fromArray(lightDef.position);
      }
      if (lightDef?.castShadow) {
        light.castShadow = true;
        const shadow = lightDef.shadow;
        if (shadow) {
          light.shadow.mapSize.set(
            shadow.mapSize?.[0] ?? 2048,
            shadow.mapSize?.[1] ?? 2048,
          );
          if (shadow.camera) {
            light.shadow.camera.near = shadow.camera.near ?? 0.5;
            light.shadow.camera.far = shadow.camera.far ?? 25;
            light.shadow.camera.left = shadow.camera.left ?? -8;
            light.shadow.camera.right = shadow.camera.right ?? 8;
            light.shadow.camera.top = shadow.camera.top ?? 8;
            light.shadow.camera.bottom = shadow.camera.bottom ?? -8;
          }
          light.shadow.radius = shadow.radius ?? 4;
        }
      }
      object = light;
      break;
    }

    case 'point-light': {
      const lightDef = nodeDef.light;
      const light = new THREE.PointLight(
        hexColor(lightDef?.color ?? '#FFFFFF'),
        lightDef?.intensity ?? 1.0,
        lightDef?.distance,
        lightDef?.decay,
      );
      object = light;
      break;
    }

    case 'group':
    default: {
      object = new THREE.Group();
      break;
    }
  }

  // Apply transform
  if (nodeDef.position) object.position.fromArray(nodeDef.position);
  if (nodeDef.rotation) object.rotation.fromArray(nodeDef.rotation);
  if (nodeDef.scale !== undefined) {
    if (typeof nodeDef.scale === 'number') {
      object.scale.setScalar(nodeDef.scale);
    } else {
      object.scale.fromArray(nodeDef.scale);
    }
  }
  if (nodeDef.visible !== undefined) object.visible = nodeDef.visible;

  // Carry over userData
  if (nodeDef.userData) {
    Object.assign(object.userData, nodeDef.userData);
  }
  object.userData.nodeId = nodeDef.id;

  // Recurse into children
  if (nodeDef.children) {
    for (const childDef of nodeDef.children) {
      const child = hydrateNode(childDef, gltfLoader, assetCache);
      object.add(child);
    }
  }

  return object;
}

// ──────────────────────────────────────────────────────────────────
//  GLB Asset Loading
// ──────────────────────────────────────────────────────────────────

const gltfLoaderSingleton = new GLTFLoader();
const assetCacheGlobal = new Map();

/**
 * Asynchronously load a GLB/GLTF asset and replace placeholder geometry.
 */
function loadGLBAsset(assetId, targetMesh, loader, cache) {
  const _loader = loader || gltfLoaderSingleton;
  const _cache = cache || assetCacheGlobal;

  if (_cache.has(assetId)) {
    applyGLBGeometry(targetMesh, _cache.get(assetId));
    return;
  }

  // The asset URL convention: /assets/<assetId>.glb
  // The Scene Compiler provides the URL in the manifest assetVersions,
  // but for now we use the convention directly.
  const url = `/assets/${assetId}.glb`;

  _loader.load(
    url,
    (gltf) => {
      _cache.set(assetId, gltf);
      applyGLBGeometry(targetMesh, gltf);
    },
    undefined,
    (err) => {
      console.warn(`[SceneRuntime] Failed to load GLB asset "${assetId}":`, err);
    },
  );
}

/**
 * Replace a mesh's geometry and optionally its material with data from a GLB.
 */
function applyGLBGeometry(targetMesh, gltf) {
  const scene = gltf.scene;
  if (!scene) return;

  // Find the first mesh in the GLB scene
  let glbMesh = null;
  scene.traverse((child) => {
    if (!glbMesh && child.isMesh) glbMesh = child;
  });

  if (!glbMesh) return;

  // Swap geometry
  targetMesh.geometry.dispose();
  targetMesh.geometry = glbMesh.geometry;

  // Optionally swap material if the GLB includes one
  // and the target doesn't already have a clay material with a custom color
  if (glbMesh.material && !targetMesh.material.userData?.baseColor) {
    targetMesh.material.dispose();
    targetMesh.material = glbMesh.material;
  }
}

// ──────────────────────────────────────────────────────────────────
//  Temporal Interpolation
//  Computes entity states between anchor years by lerping properties.
// ──────────────────────────────────────────────────────────────────

function getInterpolatedState(year, anchorYears) {
  if (!anchorYears || anchorYears.length === 0) return { states: {}, lowerYear: 0, upperYear: 0 };

  let lower = anchorYears[0];
  let upper = anchorYears[anchorYears.length - 1];

  for (let i = 0; i < anchorYears.length - 1; i++) {
    if (anchorYears[i].year <= year && anchorYears[i + 1].year >= year) {
      lower = anchorYears[i];
      upper = anchorYears[i + 1];
      break;
    }
  }

  const span = upper.year - lower.year;
  const t = span > 0 ? clamp01((year - lower.year) / span) : 0;

  const allIds = new Set([
    ...Object.keys(lower.entities || {}),
    ...Object.keys(upper.entities || {}),
  ]);

  const states = {};
  for (const id of allIds) {
    const a = (lower.entities || {})[id] || {};
    const b = (upper.entities || {})[id] || {};

    states[id] = {
      presence: lerp(a.presence ?? 1, b.presence ?? 1, t),
      growth: lerp(a.growth ?? b.growth ?? 0, b.growth ?? a.growth ?? 0, t),
      crownVolume: lerp(a.crownVolume ?? b.crownVolume ?? 0, b.crownVolume ?? a.crownVolume ?? 0, t),
      weathering: lerp(a.weathering ?? b.weathering ?? 0, b.weathering ?? a.weathering ?? 0, t),
      height: lerp(a.height ?? b.height ?? 0, b.height ?? a.height ?? 0, t),
      structuralVariant: t < 0.5 ? (a.structuralVariant || 'original') : (b.structuralVariant || 'original'),
      newWindows: t >= 0.7 ? (b.newWindows || false) : (a.newWindows || false),
      bodyStage: t < 0.5 ? (a.bodyStage || 'adult') : (b.bodyStage || 'adult'),
      positionOffset: b.positionOffset
        ? b.positionOffset.map(v => lerp(0, v, t))
        : [0, 0, 0],
    };
  }

  return { states, lowerYear: lower.year, upperYear: upper.year };
}

// ──────────────────────────────────────────────────────────────────
//  SceneRuntime  (Main export)
// ──────────────────────────────────────────────────────────────────

/**
 * The SceneRuntime class manages the Three.js scene lifecycle,
 * WebSocket connection to the Scene Compiler, and temporal state.
 */
export class SceneRuntime {
  /**
   * @param {HTMLCanvasElement} canvasElement — target canvas
   * @param {string} wsUrl — WebSocket URL of the Scene Compiler (e.g. 'ws://localhost:3211/ws/scene')
   * @param {object} [options]
   * @param {THREE.Scene} [options.scene] — reuse an existing scene (otherwise a new one is created)
   * @param {THREE.WebGLRenderer} [options.renderer] — reuse an existing renderer
   */
  constructor(canvasElement, wsUrl, options = {}) {
    // ── Core Three.js ──
    this.canvas = canvasElement;
    this.wsUrl = wsUrl;

    this.renderer = options.renderer || new THREE.WebGLRenderer({
      canvas: canvasElement,
      antialias: true,
    });
    if (!options.renderer) {
      this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
      this.renderer.setSize(window.innerWidth, window.innerHeight);
      this.renderer.shadowMap.enabled = true;
      this.renderer.shadowMap.type = THREE.VSMShadowMap;
      this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
      this.renderer.toneMappingExposure = 1.1;
      this.renderer.setClearColor(0xF7F5EF);
    }

    this.scene = options.scene || new THREE.Scene();
    if (!options.scene) {
      this.scene.fog = new THREE.FogExp2(0xF7F5EF, 0.012);
    }

    // ── State ──
    this._ws = null;
    this._entities = new Map();       // entityId -> { object3d, spec, interpolationTables }
    this._nodesById = new Map();      // sceneNodeId -> Object3D
    this._manifest = null;
    this._currentTime = 2026;
    this._gltfLoader = new GLTFLoader();
    this._assetCache = new Map();
    this._listeners = new Map();      // event -> Set<callback>
    this._disposed = false;

    // ── Resize ──
    this._onResize = () => {
      if (this._disposed) return;
      const w = window.innerWidth;
      const h = window.innerHeight;
      this.renderer.setSize(w, h);
    };
    window.addEventListener('resize', this._onResize);
  }

  // ────────────────────────────────────────────────────────────────
  //  Public API
  // ────────────────────────────────────────────────────────────────

  /**
   * Establish WebSocket connection to the Scene Compiler.
   * Automatically reconnects on disconnect.
   */
  connect() {
    if (this._disposed) return;
    this._disconnect();

    const ws = new WebSocket(this.wsUrl);
    this._ws = ws;

    ws.onopen = () => {
      console.log('[SceneRuntime] WebSocket connected:', this.wsUrl);
      this._emit('connected');

      // Request the current manifest on connect
      ws.send(JSON.stringify({
        type: 'scene.manifest.request',
        timestamp: new Date().toISOString(),
      }));
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        this._handleMessage(msg);
      } catch (e) {
        console.warn('[SceneRuntime] Failed to parse WS message:', e);
      }
    };

    ws.onclose = () => {
      console.log('[SceneRuntime] WebSocket closed, reconnecting in 3s...');
      this._emit('disconnected');
      if (!this._disposed) {
        setTimeout(() => this.connect(), 3000);
      }
    };

    ws.onerror = (err) => {
      console.warn('[SceneRuntime] WebSocket error:', err);
    };
  }

  /**
   * Disconnect from the Scene Compiler.
   */
  disconnect() {
    this._disconnect();
  }

  /**
   * Update the temporal position (year value).
   * Applies interpolated temporal state to all entities in the scene.
   *
   * @param {number} normalized — a year value (e.g. 2026, 2036.5)
   */
  setTimeValue(normalized) {
    this._currentTime = normalized;
    this._applyTemporalState(normalized);
    this._emit('timeChanged', normalized);
  }

  /**
   * Get the interpolated temporal state for a specific entity at a given time.
   *
   * @param {string} entityId — entity identifier
   * @param {number} time — year value
   * @returns {object|null} interpolated state or null
   */
  getEntityAtTime(entityId, time) {
    const temporal = this._manifest?.temporalSpec;
    if (!temporal?.raw?.anchorYears) return null;
    const { states } = getInterpolatedState(time, temporal.raw.anchorYears);
    return states[entityId] || null;
  }

  /**
   * Get the current scene state snapshot.
   *
   * @returns {{ entities: Map, currentTime: number, manifest: object|null }}
   */
  getSceneState() {
    return {
      entities: new Map(this._entities),
      currentTime: this._currentTime,
      manifest: this._manifest,
    };
  }

  /**
   * Load a SceneManifest directly (without WebSocket).
   * Useful for initial load or offline mode.
   *
   * @param {object} manifest — a SceneManifest from the Scene Compiler
   */
  loadManifest(manifest) {
    this._applyManifest(manifest);
  }

  /**
   * Get the Three.js scene (for integration with existing renderers).
   */
  getScene() {
    return this.scene;
  }

  /**
   * Get the Three.js renderer.
   */
  getRenderer() {
    return this.renderer;
  }

  /**
   * Subscribe to runtime events.
   *
   * Events:
   *   - 'connected'        — WebSocket connected
   *   - 'disconnected'     — WebSocket disconnected
   *   - 'manifestLoaded'   — new manifest applied
   *   - 'entityAdded'      — entity added to scene
   *   - 'entityUpdated'    — entity updated
   *   - 'entityRemoved'    — entity removed
   *   - 'timeChanged'      — temporal position changed
   *   - 'reconstructing'   — full recompilation in progress
   *
   * @param {string} event
   * @param {Function} callback
   * @returns {Function} unsubscribe function
   */
  on(event, callback) {
    if (!this._listeners.has(event)) {
      this._listeners.set(event, new Set());
    }
    this._listeners.get(event).add(callback);
    return () => this._listeners.get(event)?.delete(callback);
  }

  /**
   * Dispose of all resources.
   */
  dispose() {
    this._disposed = true;
    this._disconnect();
    window.removeEventListener('resize', this._onResize);

    // Dispose Three.js objects
    this._entities.forEach(({ object3d }) => {
      this.scene.remove(object3d);
      this._disposeObject(object3d);
    });
    this._entities.clear();
    this._nodesById.clear();

    this.renderer.dispose();
    this._listeners.clear();
  }

  // ────────────────────────────────────────────────────────────────
  //  Internal: WebSocket Message Handling
  // ────────────────────────────────────────────────────────────────

  _disconnect() {
    if (this._ws) {
      this._ws.onclose = null; // prevent reconnect loop
      this._ws.close();
      this._ws = null;
    }
  }

  _handleMessage(msg) {
    switch (msg.type) {
      case 'scene.entity.added':
        this._handleEntityAdded(msg.payload);
        break;

      case 'scene.entity.updated':
        this._handleEntityUpdated(msg.payload);
        break;

      case 'scene.entity.removed':
        this._handleEntityRemoved(msg.payload);
        break;

      case 'scene.reconstruction.progress':
        this._emit('reconstructing', msg.payload);
        break;

      case 'scene.reconstruction.complete':
        this._handleReconstructionComplete(msg.payload);
        break;

      case 'scene.response':
        this._handleResponse(msg);
        break;

      default:
        // Ignore unknown message types (time.seek, entity.select, etc. — handled by desktop.html)
        break;
    }
  }

  _handleEntityAdded(payload) {
    const { entity, node, parentId } = payload;
    if (!entity || !node) return;

    const object3d = hydrateNode(node, this._gltfLoader, this._assetCache);

    // Attach to parent or scene root
    if (parentId && this._nodesById.has(parentId)) {
      this._nodesById.get(parentId).add(object3d);
    } else {
      this.scene.add(object3d);
    }

    // Register
    this._nodesById.set(node.id, object3d);
    this._entities.set(entity.spec?.id || node.id, {
      object3d,
      spec: entity.spec,
      interpolationTables: entity.temporalInterpolationTables,
    });

    // Apply current temporal state to the new entity
    this._applyTemporalState(this._currentTime);

    this._emit('entityAdded', { entityId: entity.spec?.id || node.id, object3d });
  }

  _handleEntityUpdated(payload) {
    const { entityId, nodePatch, interpolationTables } = payload;
    const entry = this._entities.get(entityId);
    if (!entry) return;

    // Apply partial node patch
    if (nodePatch) {
      if (nodePatch.position) entry.object3d.position.fromArray(nodePatch.position);
      if (nodePatch.rotation) entry.object3d.rotation.fromArray(nodePatch.rotation);
      if (nodePatch.scale !== undefined) {
        if (typeof nodePatch.scale === 'number') {
          entry.object3d.scale.setScalar(nodePatch.scale);
        } else {
          entry.object3d.scale.fromArray(nodePatch.scale);
        }
      }
      if (nodePatch.visible !== undefined) entry.object3d.visible = nodePatch.visible;
      if (nodePatch.userData) Object.assign(entry.object3d.userData, nodePatch.userData);

      // Mesh-level patches
      if (nodePatch.mesh && entry.object3d.isMesh) {
        if (nodePatch.mesh.material) {
          const newMat = createMaterial(nodePatch.mesh.material);
          entry.object3d.material.dispose();
          entry.object3d.material = newMat;
        }
      }
    }

    // Update interpolation tables
    if (interpolationTables) {
      entry.interpolationTables = interpolationTables;
    }

    // Re-apply temporal state
    this._applyTemporalState(this._currentTime);

    this._emit('entityUpdated', { entityId, object3d: entry.object3d });
  }

  _handleEntityRemoved(payload) {
    const { entityId, sceneNodeId } = payload;

    // Remove from scene
    const object3d = this._nodesById.get(sceneNodeId);
    if (object3d) {
      object3d.parent?.remove(object3d);
      this._disposeObject(object3d);
      this._nodesById.delete(sceneNodeId);
    }

    this._entities.delete(entityId);
    this._emit('entityRemoved', { entityId });
  }

  _handleReconstructionComplete(payload) {
    const { manifest, diff } = payload;
    console.log('[SceneRuntime] Reconstruction complete:', diff);
    this._applyManifest(manifest);
  }

  _handleResponse(msg) {
    const { requestId, payload } = msg;
    if (!requestId) return;

    // If the response contains a manifest (from scene.manifest.request)
    if (payload.success && payload.data?.manifest) {
      this._applyManifest(payload.data.manifest);
    }
  }

  // ────────────────────────────────────────────────────────────────
  //  Internal: Manifest Application
  // ────────────────────────────────────────────────────────────────

  _applyManifest(manifest) {
    if (!manifest) return;

    this._manifest = manifest;

    // Clear existing entities
    this._entities.forEach(({ object3d }) => {
      this.scene.remove(object3d);
      this._disposeObject(object3d);
    });
    this._entities.clear();
    this._nodesById.clear();

    // Hydrate scene graph
    if (manifest.sceneGraph) {
      for (const nodeDef of manifest.sceneGraph) {
        const object3d = hydrateNode(nodeDef, this._gltfLoader, this._assetCache);
        this.scene.add(object3d);
        this._nodesById.set(nodeDef.id, object3d);
      }
    }

    // Register entities from the manifest lookup table
    if (manifest.entities) {
      for (const [entityId, compiledEntity] of Object.entries(manifest.entities)) {
        const object3d = this._nodesById.get(compiledEntity.sceneNodeId);
        if (object3d) {
          this._entities.set(entityId, {
            object3d,
            spec: compiledEntity.spec,
            interpolationTables: compiledEntity.temporalInterpolationTables,
          });
        }
      }
    }

    // Apply current temporal state
    this._applyTemporalState(this._currentTime);

    this._emit('manifestLoaded', manifest);
  }

  // ────────────────────────────────────────────────────────────────
  //  Internal: Temporal State Application
  // ────────────────────────────────────────────────────────────────

  _applyTemporalState(year) {
    const temporal = this._manifest?.temporalSpec;
    if (!temporal?.raw?.anchorYears) return;

    const { states } = getInterpolatedState(year, temporal.raw.anchorYears);

    for (const [entityId, entry] of this._entities) {
      const entityState = states[entityId];
      if (!entityState) continue;

      const obj = entry.object3d;

      // Presence (visibility)
      if (entityState.presence !== undefined) {
        obj.visible = entityState.presence > 0.1;
      }

      // Height scaling (characters)
      if (entityState.height !== undefined && entityState.height > 0) {
        if (entry.spec?.category === 'character') {
          obj.scale.setScalar(entityState.height);
        }
      }

      // Position offset
      if (entityState.positionOffset && entry.spec?.position) {
        const base = entry.spec.position;
        const off = entityState.positionOffset;
        obj.position.set(base[0] + off[0], base[1] + (off[1] || 0), base[2] + off[2]);
      }

      // Tree growth
      if (entityState.growth !== undefined && entry.spec?.category === 'vegetation') {
        obj.children.forEach(child => {
          if (child.isMesh) {
            if (child.geometry?.type === 'CylinderGeometry') {
              child.scale.set(entityState.growth, entityState.growth, entityState.growth);
            } else if (child.geometry?.type === 'SphereGeometry') {
              child.scale.setScalar(entityState.growth * (entityState.crownVolume || 1));
            }
          }
        });
      }

      // Building weathering
      if (entityState.weathering !== undefined && entry.spec?.category === 'building') {
        const w = entityState.weathering;
        obj.traverse(child => {
          if (child.isMesh && child.material?.userData?.baseColor) {
            const base = child.material.userData.baseColor;
            const weathered = new THREE.Color(0xCEC7B8); // warmWhiteR
            child.material.color.copy(base.clone().lerp(weathered, w));
          }
        });
      }

      // Growth color shift (tree foliage seasonal variation)
      if (entry.spec?.category === 'vegetation') {
        const seasonCycle = ((year % 1) + 1) % 1;
        obj.children.forEach(child => {
          if (child.isMesh && child.geometry?.type === 'SphereGeometry') {
            const base = child.material.userData?.baseColor || new THREE.Color(0xB7D83D);
            const autumn = new THREE.Color(0xC18B14);
            const winter = new THREE.Color(0xCEC7B8);
            let c;
            if (seasonCycle < 0.25) c = base.clone().lerp(winter, seasonCycle * 4);
            else if (seasonCycle < 0.5) c = winter.clone().lerp(base, (seasonCycle - 0.25) * 4);
            else if (seasonCycle < 0.75) c = base.clone().lerp(autumn, (seasonCycle - 0.5) * 4);
            else c = autumn.clone().lerp(winter, (seasonCycle - 0.75) * 4);
            child.material.color.copy(c);
          }
        });
      }
    }
  }

  // ────────────────────────────────────────────────────────────────
  //  Internal: Utilities
  // ────────────────────────────────────────────────────────────────

  _emit(event, data) {
    const listeners = this._listeners.get(event);
    if (listeners) {
      for (const cb of listeners) {
        try { cb(data); } catch (e) { console.error('[SceneRuntime] Listener error:', e); }
      }
    }
  }

  _disposeObject(obj) {
    obj.traverse((child) => {
      if (child.isMesh) {
        child.geometry?.dispose();
        if (child.material) {
          if (Array.isArray(child.material)) {
            child.material.forEach(m => m.dispose());
          } else {
            child.material.dispose();
          }
        }
      }
    });
  }
}

// ──────────────────────────────────────────────────────────────────
//  Default export for convenience
// ──────────────────────────────────────────────────────────────────

export default SceneRuntime;
