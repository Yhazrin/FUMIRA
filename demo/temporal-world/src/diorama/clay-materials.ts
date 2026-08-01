// diorama/clay-materials.ts — Soft Clay material system.
// Target: molded vinyl / matte toy plastic.
// Every entity gets its OWN material instance with seeded-unique roughness.
// Uses MeshPhysicalMaterial for clearcoat support.

import * as THREE from 'three';
import type { MaterialSpec } from './contracts';

// ---------------------------------------------------------------------------
// Seeded PRNG — mulberry32 (fast, deterministic, 32-bit)
// ---------------------------------------------------------------------------

/** Deterministic hash from a string. FNV-1a variant. */
export function hashString(str: string): number {
  let h = 0x811c9dc5; // FNV offset basis
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193); // FNV prime
  }
  return h >>> 0;
}

/** mulberry32 PRNG — returns a function that yields [0, 1) floats. */
export function mulberry32(seed: number): () => number {
  let s = seed | 0;
  return () => {
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---------------------------------------------------------------------------
// Clay presets — roughness is a [min, max] range, sampled per-entity
// ---------------------------------------------------------------------------

export const CLAY_PRESETS = {
  building: {
    roughness: [0.42, 0.52] as [number, number],
    metalness: 0,
    clearcoat: 0.08,
    clearcoatRoughness: 0.4,
  },
  tree: {
    roughness: [0.60, 0.75] as [number, number],
    metalness: 0,
    clearcoat: 0.05,
    clearcoatRoughness: 0.6,
  },
  ground: {
    roughness: [0.70, 0.80] as [number, number],
    metalness: 0,
    clearcoat: 0.02,
    clearcoatRoughness: 0.8,
  },
  prop: {
    roughness: [0.35, 0.45] as [number, number],
    metalness: 0,
    clearcoat: 0.12,
    clearcoatRoughness: 0.3,
  },
  path: {
    roughness: [0.55, 0.65] as [number, number],
    metalness: 0,
    clearcoat: 0.06,
    clearcoatRoughness: 0.5,
  },
} as const;

export type ClayPresetKey = keyof typeof CLAY_PRESETS;

// ---------------------------------------------------------------------------
// Entity type -> preset mapping
// ---------------------------------------------------------------------------

const ENTITY_TO_PRESET: Record<string, ClayPresetKey> = {
  building: 'building',
  tree: 'tree',
  vehicle: 'prop',   // vehicles are shiny-ish props
  terrain: 'ground',
  prop: 'prop',
  path: 'path',
};

function presetForEntityType(entityType: string): ClayPresetKey {
  return ENTITY_TO_PRESET[entityType] ?? 'prop';
}

// ---------------------------------------------------------------------------
// Material factory
// ---------------------------------------------------------------------------

/**
 * Creates a MeshPhysicalMaterial with the soft-clay look.
 * Each call produces a unique roughness value within the preset range,
 * driven by the seed (derived from entity ID). No two entities share
 * the exact same roughness.
 *
 * metalness is ALWAYS 0 — clay does not reflect metal.
 */
export function createClayMaterial(
  spec: MaterialSpec,
  entityType: string,
  seed: number,
): THREE.MeshPhysicalMaterial {
  const presetKey = presetForEntityType(entityType);
  const preset = CLAY_PRESETS[presetKey];

  // Seeded random within roughness range
  const rand = mulberry32(seed);
  const roughness = preset.roughness[0] + rand() * (preset.roughness[1] - preset.roughness[0]);

  const mat = new THREE.MeshPhysicalMaterial({
    color: new THREE.Color(spec.color),
    roughness,
    metalness: preset.metalness, // always 0
    clearcoat: preset.clearcoat,
    clearcoatRoughness: preset.clearcoatRoughness,
    transparent: spec.opacity < 1,
    opacity: spec.opacity,
    envMapIntensity: 0.6,
  });

  if (spec.emissive) {
    mat.emissive = new THREE.Color(spec.emissive);
    mat.emissiveIntensity = spec.emissiveIntensity ?? 1;
  }

  return mat;
}
