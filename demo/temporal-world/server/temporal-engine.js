export class TemporalEngine {
  #sceneSpec;
  #anchors = [];
  #entities = new Map();

  constructor(sceneSpec) {
    this.#sceneSpec = sceneSpec;
    this.#anchors = (sceneSpec.temporalAnchors || []).sort(
      (a, b) => a.normalizedTime - b.normalizedTime,
    );

    // Index entities
    for (const entity of sceneSpec.entities) {
      this.#entities.set(entity.id, entity);
    }
  }

  // Get interpolated state for all entities at a given time
  getStateAtTime(normalizedTime) {
    const clamped = Math.max(-1, Math.min(1, normalizedTime));
    const state = {};

    for (const [entityId, entity] of this.#entities) {
      state[entityId] = this.#interpolateEntity(entity, clamped);
    }

    return state;
  }

  // Get state for a single entity
  getEntityAtTime(entityId, normalizedTime) {
    const entity = this.#entities.get(entityId);
    if (!entity) return null;
    return this.#interpolateEntity(entity, Math.max(-1, Math.min(1, normalizedTime)));
  }

  // Pre-compute states for specific years (for runtime caching)
  precomputeYears(years) {
    const result = {};
    for (const year of years) {
      const normalized = this.#yearToNormalized(year);
      result[year] = this.getStateAtTime(normalized);
    }
    return result;
  }

  // Get all anchor years
  getAnchorYears() {
    return this.#anchors.map(a => a.year);
  }

  // ─── Interpolation ────────────────────────────────────────────────────

  #interpolateEntity(entity, time) {
    // Find bounding anchors
    const lower = this.#findLowerAnchor(time);
    const upper = this.#findUpperAnchor(time);

    if (!lower && !upper) {
      // No anchors — return default state
      return this.#defaultEntityState(entity);
    }

    if (!upper) return this.#getAnchorState(entity, lower);
    if (!lower) return this.#getAnchorState(entity, upper);

    if (lower.normalizedTime === upper.normalizedTime) {
      return this.#getAnchorState(entity, lower);
    }

    // Interpolate between anchors
    const t = (time - lower.normalizedTime) / (upper.normalizedTime - lower.normalizedTime);
    const eased = this.#ease(t, entity.temporalBehavior);

    const lowerState = this.#getAnchorState(entity, lower);
    const upperState = this.#getAnchorState(entity, upper);

    return this.#lerpStates(lowerState, upperState, eased);
  }

  #findLowerAnchor(time) {
    let result = null;
    for (const anchor of this.#anchors) {
      if (anchor.normalizedTime <= time) result = anchor;
    }
    return result;
  }

  #findUpperAnchor(time) {
    for (const anchor of this.#anchors) {
      if (anchor.normalizedTime >= time) return anchor;
    }
    return null;
  }

  #getAnchorState(entity, anchor) {
    const state = anchor.entityStates[entity.id];
    if (!state) return this.#defaultEntityState(entity);

    return {
      visible: state.visible !== false,
      position: state.position || entity.position,
      scale: state.scale || entity.scale,
      rotation: entity.rotation,
      material: { ...entity.material, ...(state.material || {}) },
      variantId: state.variantId,
    };
  }

  #defaultEntityState(entity) {
    return {
      visible: true,
      position: entity.position,
      scale: entity.scale,
      rotation: entity.rotation,
      material: entity.material,
      variantId: null,
    };
  }

  #lerpStates(a, b, t) {
    return {
      visible: t < 0.5 ? a.visible : b.visible,
      position: this.#lerpVec3(a.position, b.position, t),
      scale: this.#lerpVec3(a.scale, b.scale, t),
      rotation: this.#lerpVec3(a.rotation, b.rotation, t),
      material: {
        ...a.material,
        color: t < 0.5 ? a.material.color : b.material.color,
        roughness: a.material.roughness + (b.material.roughness - a.material.roughness) * t,
      },
      variantId: t < 0.5 ? a.variantId : b.variantId,
    };
  }

  #lerpVec3(a, b, t) {
    return [
      a[0] + (b[0] - a[0]) * t,
      a[1] + (b[1] - a[1]) * t,
      a[2] + (b[2] - a[2]) * t,
    ];
  }

  #ease(t, behavior) {
    const mode = behavior?.mode || 'linear';
    switch (mode) {
      case 'grow': return t * t; // ease-in (slow start, fast growth)
      case 'decay': return 1 - (1 - t) * (1 - t); // ease-out (fast decay, slow end)
      case 'transform': return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      default: return t;
    }
  }

  #yearToNormalized(year) {
    if (this.#anchors.length < 2) return 0;
    const first = this.#anchors[0];
    const last = this.#anchors[this.#anchors.length - 1];
    return (
      ((year - first.year) / (last.year - first.year)) *
        (last.normalizedTime - first.normalizedTime) +
      first.normalizedTime
    );
  }
}
