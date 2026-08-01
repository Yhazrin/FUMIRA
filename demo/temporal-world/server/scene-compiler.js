/**
 * Scene Compiler — temporal world reconstruction to Three.js scene data
 *
 * Receives reconstruction results from Claude Worker, compiles them into
 * Three.js-compatible scene data, manages entity lifecycle with temporal
 * interpolation, and broadcasts updates via registered callbacks.
 *
 * @module scene-compiler
 */

// ── Helpers ─────────────────────────────────────────────────

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function lerp(a, b, t) {
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.map((v, i) => v + (b[i] - v) * t);
  }
  return a + (b - a) * t;
}

function lerpMaterial(matA, matB, t) {
  return {
    color: lerpColor(matA.color, matB.color, t),
    roughness: lerp(matA.roughness ?? 0.5, matB.roughness ?? 0.5, t),
    metalness: lerp(matA.metalness ?? 0, matB.metalness ?? 0, t),
    opacity: lerp(matA.opacity ?? 1, matB.opacity ?? 1, t),
    ...(matA.transparent !== undefined || matB.transparent !== undefined
      ? { transparent: (matA.transparent ?? false) || (matB.transparent ?? false) }
      : {}),
    ...(matA.emissive !== undefined || matB.emissive !== undefined
      ? { emissive: lerpColor(matA.emissive ?? '#000000', matB.emissive ?? '#000000', t) }
      : {}),
  };
}

/**
 * Linear interpolation between two hex color strings.
 * Returns a hex color string.
 */
function lerpColor(colorA, colorB, t) {
  const a = hexToRgb(colorA);
  const b = hexToRgb(colorB);
  const r = Math.round(lerp(a.r, b.r, t));
  const g = Math.round(lerp(a.g, b.g, t));
  const bl = Math.round(lerp(a.b, b.b, t));
  return rgbToHex(r, g, bl);
}

function hexToRgb(hex) {
  if (typeof hex !== 'string') hex = '#000000';
  hex = hex.replace(/^#/, '');
  if (hex.length === 3) {
    hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
  }
  const num = parseInt(hex, 16);
  return {
    r: (num >> 16) & 255,
    g: (num >> 8) & 255,
    b: num & 255,
  };
}

function rgbToHex(r, g, b) {
  return '#' + [r, g, b].map(v => clamp(v, 0, 255).toString(16).padStart(2, '0')).join('');
}

/**
 * Deep-clone a plain object (structuredClone polyfill for simple data).
 */
function cloneState(state) {
  return JSON.parse(JSON.stringify(state));
}

/**
 * Find the two temporal variants that bracket the given time value.
 * Returns { before, after, t } where t is the interpolation factor (0..1).
 * If only one variant exists or time is outside the range, returns null for the missing bound.
 */
function bracketVariants(variants, timeValue) {
  if (variants.length === 0) return { before: null, after: null, t: 0 };
  if (variants.length === 1) return { before: variants[0], after: null, t: 0 };

  // Sort by time
  const sorted = [...variants].sort((a, b) => a.time - b.time);

  // Before the earliest
  if (timeValue <= sorted[0].time) {
    return { before: sorted[0], after: null, t: 0 };
  }

  // After the latest
  if (timeValue >= sorted[sorted.length - 1].time) {
    return { before: sorted[sorted.length - 1], after: null, t: 0 };
  }

  // Find the bracketing pair
  for (let i = 0; i < sorted.length - 1; i++) {
    if (timeValue >= sorted[i].time && timeValue <= sorted[i + 1].time) {
      const range = sorted[i + 1].time - sorted[i].time;
      const t = range === 0 ? 0 : (timeValue - sorted[i].time) / range;
      return { before: sorted[i], after: sorted[i + 1], t };
    }
  }

  return { before: sorted[sorted.length - 1], after: null, t: 0 };
}

/**
 * Interpolate two mesh states.
 */
function interpolateMesh(meshA, meshB, t) {
  if (!meshB) return cloneState(meshA);
  if (!meshA) return cloneState(meshB);

  return {
    geometry: { ...meshA.geometry }, // geometry type/args don't interpolate
    position: lerp(meshA.position, meshB.position, t),
    rotation: lerp(meshA.rotation, meshB.rotation, t),
    scale: meshA.scale
      ? lerp(meshA.scale, meshB.scale ?? [1, 1, 1], t)
      : meshB.scale
        ? cloneState(meshB.scale)
        : [1, 1, 1],
    material: lerpMaterial(
      meshA.material ?? {},
      meshB.material ?? {},
      t
    ),
  };
}

// ── SceneCompiler ───────────────────────────────────────────

export class SceneCompiler {
  /** @type {Map<string, EntityRecord>} */
  #entities = new Map();

  /** @type {Set<function>} */
  #listeners = new Set();

  /** Monotonic update counter for ordering. */
  #revision = 0;

  constructor() {}

  // ── Reconstruction Result Handling ──────────────────────

  /**
   * Compile a reconstruction result (from Claude Worker) into scene updates.
   *
   * Expected result shape:
   * ```
   * {
   *   entities: [
   *     {
   *       id: 'entity_001',
   *       label: 'Clay Building',
   *       temporalRange: [-1, 1],
   *       time: 0,                    // optional, defaults to 0
   *       mesh: {
   *         geometry: { type: 'BoxGeometry', args: [1, 2, 1] },
   *         position: [0, 1, 0],
   *         rotation: [0, 0, 0],
   *         material: { color: '#8B7355', roughness: 0.8 }
   *       }
   *     }
   *   ],
   *   camera: { position: [0, 5, 10], target: [0, 0, 0] },   // optional
   *   replace: false  // optional — if true, clear all entities first
   * }
   * ```
   *
   * @param {object} result — reconstruction result JSON
   * @returns {SceneUpdateMessage[]} — array of scene update messages to broadcast
   */
  compileReconstructionResult(result) {
    if (!result || !Array.isArray(result.entities)) {
      return [];
    }

    const updates = [];

    if (result.replace) {
      // Remove all existing entities
      for (const id of this.#entities.keys()) {
        this.#entities.delete(id);
        updates.push(this.#makeUpdate('remove', [{ id }], result.camera));
      }
    }

    for (const raw of result.entities) {
      const id = raw.id;
      if (!id) continue;

      const time = raw.time ?? 0;
      const existing = this.#entities.get(id);

      if (!existing) {
        // ── New entity ──
        const record = {
          id,
          label: raw.label ?? null,
          temporalRange: raw.temporalRange ?? [-1, 1],
          variants: [{
            time,
            mesh: normalizeMesh(raw.mesh),
          }],
        };
        this.#entities.set(id, record);
        updates.push(this.#makeUpdate('add', [this.#entityToPayload(record)], result.camera));
      } else {
        // ── Update existing entity ──
        if (raw.label !== undefined) existing.label = raw.label;
        if (raw.temporalRange) existing.temporalRange = raw.temporalRange;

        // Upsert temporal variant at this time
        const vi = existing.variants.findIndex(v => v.time === time);
        const newVariant = { time, mesh: normalizeMesh(raw.mesh) };
        if (vi >= 0) {
          existing.variants[vi] = newVariant;
        } else {
          existing.variants.push(newVariant);
        }

        updates.push(this.#makeUpdate('update', [this.#entityToPayload(existing)], result.camera));
      }
    }

    return updates;
  }

  // ── Entity Queries ──────────────────────────────────────

  /**
   * Get the full entity record (all temporal variants).
   * @param {string} entityId
   * @returns {object|null}
   */
  getEntity(entityId) {
    const record = this.#entities.get(entityId);
    return record ? this.#entityToPayload(record) : null;
  }

  /**
   * Get an entity interpolated to a specific time value.
   * @param {string} entityId
   * @param {number} timeValue — normalized time in [-1, 1]
   * @returns {object|null}
   */
  getEntityAtTime(entityId, timeValue) {
    const record = this.#entities.get(entityId);
    if (!record) return null;

    const { before, after, t } = bracketVariants(record.variants, timeValue);
    if (!before) return null;

    const mesh = after ? interpolateMesh(before.mesh, after.mesh, t) : cloneState(before.mesh);

    return {
      id: record.id,
      mesh,
      temporalRange: record.temporalRange,
      label: record.label,
    };
  }

  /**
   * Get all entities interpolated to a specific time value.
   * Only includes entities whose temporal range contains the given time.
   * @param {number} timeValue
   * @returns {object[]}
   */
  getSceneAtTime(timeValue) {
    const results = [];
    for (const [id, record] of this.#entities) {
      const [lo, hi] = record.temporalRange;
      if (timeValue < lo || timeValue > hi) continue;

      const entity = this.getEntityAtTime(id, timeValue);
      if (entity) results.push(entity);
    }
    return results;
  }

  /**
   * List all entities (latest state, no time interpolation).
   * @returns {object[]}
   */
  listEntities() {
    const results = [];
    for (const record of this.#entities.values()) {
      results.push(this.#entityToPayload(record));
    }
    return results;
  }

  /**
   * Remove an entity by ID.
   * @param {string} entityId
   * @returns {boolean} — true if entity existed and was removed
   */
  removeEntity(entityId) {
    const existed = this.#entities.delete(entityId);
    if (existed) {
      this.#broadcast(this.#makeUpdate('remove', [{ id: entityId }]));
    }
    return existed;
  }

  // ── Listeners & Manifest ────────────────────────────────

  /**
   * Register a callback that receives every SceneUpdateMessage.
   * @param {function(object): void} callback
   * @returns {function} — unsubscribe function
   */
  onSceneUpdate(callback) {
    this.#listeners.add(callback);
    return () => this.#listeners.delete(callback);
  }

  /**
   * Full scene manifest for newly connecting clients.
   * Returns all entities at time 0 plus camera defaults.
   * @returns {object}
   */
  getSceneManifest() {
    // Transform flat entity list into the hierarchical format SceneRuntime expects
    const sceneGraph = [];
    const entities = {};
    const allTimeValues = new Set();

    for (const record of this.#entities.values()) {
      const sceneNodeId = `node_${record.id}`;
      const currentVariant = record.variants[record.variants.length - 1];
      const mesh = currentVariant?.mesh || {};

      // Build scene graph node
      sceneGraph.push({
        id: sceneNodeId,
        type: 'mesh',
        geometry: mesh.geometry || { type: 'BoxGeometry', args: [1, 1, 1] },
        position: mesh.position || [0, 0, 0],
        rotation: mesh.rotation || [0, 0, 0],
        material: mesh.material || { color: '#8B7355', roughness: 0.8 },
        children: [],
      });

      // Build temporal interpolation tables
      const interpolationTables = {};
      for (const variant of record.variants) {
        allTimeValues.add(variant.time);
        interpolationTables[variant.time] = {
          position: variant.mesh?.position || [0, 0, 0],
          rotation: variant.mesh?.rotation || [0, 0, 0],
          scale: [1, 1, 1],
        };
      }

      entities[record.id] = {
        sceneNodeId,
        spec: {
          id: record.id,
          type: record.type || 'prop',
          label: record.label,
          temporalRange: record.temporalRange,
        },
        temporalInterpolationTables: interpolationTables,
      };
    }

    return {
      type: 'scene.manifest',
      revision: this.#revision,
      sceneGraph,
      entities,
      temporalSpec: {
        raw: {
          anchorYears: [...allTimeValues].sort((a, b) => a - b),
        }
      },
      defaultCamera: { position: [0, 5, 10], target: [0, 0, 0] },
      timestamp: Date.now(),
    };
  }

  // ── Private ─────────────────────────────────────────────

  #makeUpdate(action, entities, camera) {
    this.#revision++;
    // Map action to granular message type matching SceneRuntime expectations
    const typeMap = { add: 'scene.entity.added', update: 'scene.entity.updated', remove: 'scene.entity.removed' };
    const msg = {
      type: typeMap[action] || `scene.entity.${action}`,
      entities,
      revision: this.#revision,
      timestamp: Date.now(),
    };
    if (camera) msg.camera = camera;
    return msg;
  }

  #broadcast(update) {
    for (const cb of this.#listeners) {
      try {
        cb(update);
      } catch {
        // listener threw — ignore
      }
    }
  }

  #entityToPayload(record) {
    // Return entity with the "latest" variant (highest time) as its mesh
    const sorted = [...record.variants].sort((a, b) => b.time - a.time);
    const latest = sorted[0];

    return {
      id: record.id,
      mesh: cloneState(latest.mesh),
      temporalRange: record.temporalRange,
      label: record.label,
      variantCount: record.variants.length,
    };
  }
}

// ── Mesh Normalization ──────────────────────────────────────

const DEFAULT_GEOMETRY = { type: 'BoxGeometry', args: [1, 1, 1] };
const DEFAULT_POSITION = [0, 0, 0];
const DEFAULT_ROTATION = [0, 0, 0];
const DEFAULT_SCALE = [1, 1, 1];
const DEFAULT_MATERIAL = { color: '#888888', roughness: 0.7 };

function normalizeMesh(raw) {
  if (!raw) {
    return {
      geometry: { ...DEFAULT_GEOMETRY },
      position: [...DEFAULT_POSITION],
      rotation: [...DEFAULT_ROTATION],
      scale: [...DEFAULT_SCALE],
      material: { ...DEFAULT_MATERIAL },
    };
  }

  return {
    geometry: raw.geometry ? { type: raw.geometry.type ?? DEFAULT_GEOMETRY.type, args: raw.geometry.args ?? DEFAULT_GEOMETRY.args } : { ...DEFAULT_GEOMETRY },
    position: raw.position ?? [...DEFAULT_POSITION],
    rotation: raw.rotation ?? [...DEFAULT_ROTATION],
    scale: raw.scale ?? [...DEFAULT_SCALE],
    material: raw.material ? { ...DEFAULT_MATERIAL, ...raw.material } : { ...DEFAULT_MATERIAL },
  };
}

export default SceneCompiler;
