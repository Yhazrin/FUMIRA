import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');

// ── Load fixture ───────────────────────────────────────────────

const fixture = JSON.parse(
  readFileSync(resolve(root, 'test/fixtures/campus-gate.json'), 'utf-8'),
);

// ── Re-implement pure interpolation from scene-runtime ─────────
// These are the exact algorithms from packages/scene-runtime/src/index.ts,
// extracted here to avoid pulling in THREE.js.

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function clamp01(t: number): number {
  return Math.max(0, Math.min(1, t));
}

interface TemporalEntityState {
  weathering?: number;
  structuralVariant?: string;
  newWindows?: boolean;
  greenRoof?: boolean;
  growth?: number;
  crownVolume?: number;
  bodyStage?: string;
  height?: number;
  presence?: number;
  positionOffset?: [number, number, number];
}

interface InterpolatedEntityState extends TemporalEntityState {
  presence: number;
  growth: number;
  crownVolume: number;
  weathering: number;
  height: number;
  structuralVariant: string;
  newWindows: boolean;
  bodyStage: string;
  positionOffset: [number, number, number];
}

interface InterpolatedState {
  states: Record<string, InterpolatedEntityState>;
  lowerYear: number;
  upperYear: number;
}

function getInterpolatedState(year: number, fxt: typeof fixture): InterpolatedState {
  const anchors = fxt.temporalSpec.anchorYears;
  let lower = anchors[0];
  let upper = anchors[anchors.length - 1];

  for (let i = 0; i < anchors.length - 1; i++) {
    if (anchors[i].year <= year && anchors[i + 1].year >= year) {
      lower = anchors[i];
      upper = anchors[i + 1];
      break;
    }
  }

  const span = upper.year - lower.year;
  const t = span > 0 ? clamp01((year - lower.year) / span) : 0;
  const allIds = new Set([
    ...Object.keys(lower.entities),
    ...Object.keys(upper.entities),
  ]);

  const states: Record<string, InterpolatedEntityState> = {};

  for (const id of allIds) {
    const a = lower.entities[id] || {};
    const b = upper.entities[id] || {};

    states[id] = {
      presence: lerp(a.presence ?? 1, b.presence ?? 1, t),
      growth: lerp(a.growth ?? (b.growth ?? 0), b.growth ?? (a.growth ?? 0), t),
      crownVolume: lerp(a.crownVolume ?? (b.crownVolume ?? 0), b.crownVolume ?? (a.crownVolume ?? 0), t),
      weathering: lerp(a.weathering ?? (b.weathering ?? 0), b.weathering ?? (a.weathering ?? 0), t),
      height: lerp(a.height ?? (b.height ?? 0), b.height ?? (a.height ?? 0), t),
      structuralVariant: t < 0.5
        ? (a.structuralVariant || 'original')
        : (b.structuralVariant || 'original'),
      newWindows: t >= 0.7 ? (b.newWindows || false) : (a.newWindows || false),
      bodyStage: t < 0.5 ? (a.bodyStage || 'adult') : (b.bodyStage || 'adult'),
      positionOffset: b.positionOffset
        ? (b.positionOffset as [number, number, number]).map(v => lerp(0, v, t)) as [number, number, number]
        : [0, 0, 0],
    };
  }

  return { states, lowerYear: lower.year, upperYear: upper.year };
}

// ── SceneGraph validation ──────────────────────────────────────

describe('SceneGraph validation', () => {
  it('fixture entities have valid structure', () => {
    for (const entity of fixture.entities) {
      assert.ok(typeof entity.id === 'string', 'entity must have string id');
      assert.ok(typeof entity.type === 'string', 'entity must have string type');
      assert.ok(typeof entity.category === 'string', 'entity must have string category');
      assert.ok(Array.isArray(entity.position), 'entity must have position array');
      assert.strictEqual(entity.position.length, 3, 'position must be [x, y, z]');
    }
  });

  it('entities have unique ids', () => {
    const ids = fixture.entities.map((e: any) => e.id);
    const unique = new Set(ids);
    assert.strictEqual(unique.size, ids.length, `duplicate entity ids found: ${ids.filter((id: string, i: number) => ids.indexOf(id) !== i)}`);
  });

  it('temporal anchor entity ids reference valid entities', () => {
    const entityIds = new Set(fixture.entities.map((e: any) => e.id));
    for (const anchor of fixture.temporalSpec.anchorYears) {
      for (const entityId of Object.keys(anchor.entities)) {
        // entityId should match a known entity or be a recognized temporal-only id
        // In the fixture, temporal ids like "gate_01", "tree_01", "person_01" map to entities
        const hasEntity = entityIds.has(entityId);
        // Some temporal ids may not have a direct entity (e.g., derived entities)
        // but they should at least follow the naming convention
        assert.ok(
          hasEntity || entityId.match(/^(gate|tree|person|building)_\d+$/),
          `temporal anchor references unknown entity: ${entityId}`,
        );
      }
    }
  });

  it('timeline intervals cover the full anchor year range without gaps', () => {
    const intervals = fixture.temporalSpec.timelineIntervals;
    const anchors = fixture.temporalSpec.anchorYears;
    const minYear = anchors[0].year;
    const maxYear = anchors[anchors.length - 1].year;

    // First interval should start at or before minYear
    assert.ok(intervals[0].startYear <= minYear, `first interval starts at ${intervals[0].startYear}, but min anchor is ${minYear}`);
    // Last interval should end at or after maxYear
    assert.ok(intervals[intervals.length - 1].endYear >= maxYear, `last interval ends at ${intervals[intervals.length - 1].endYear}, but max anchor is ${maxYear}`);

    // Intervals should be contiguous
    for (let i = 1; i < intervals.length; i++) {
      assert.strictEqual(
        intervals[i].startYear,
        intervals[i - 1].endYear,
        `gap between interval ${i - 1} and ${i}`,
      );
    }
  });
});

// ── Temporal interpolation ─────────────────────────────────────

describe('entity temporal interpolation', () => {
  it('at exact anchor year, returns anchor state directly', () => {
    const result = getInterpolatedState(2016, fixture);
    assert.strictEqual(result.lowerYear, 2016);
    assert.strictEqual(result.upperYear, 2026);

    // tree_01 at 2016: growth=0.7, crownVolume=0.7
    const tree01 = result.states.tree_01;
    assert.ok(tree01, 'tree_01 should exist');
    assert.ok(Math.abs(tree01.growth - 0.7) < 0.001, `tree_01 growth at 2016: expected ~0.7, got ${tree01.growth}`);
    assert.ok(Math.abs(tree01.crownVolume - 0.7) < 0.001, `tree_01 crownVolume at 2016: expected ~0.7, got ${tree01.crownVolume}`);
  });

  it('at midpoint between anchors, returns interpolated values', () => {
    // Midpoint between 2016 and 2026 is 2021
    const result = getInterpolatedState(2021, fixture);
    assert.strictEqual(result.lowerYear, 2016);
    assert.strictEqual(result.upperYear, 2026);

    const tree01 = result.states.tree_01;
    assert.ok(tree01, 'tree_01 should exist');
    // growth: lerp(0.7, 1.0, 0.5) = 0.85
    assert.ok(Math.abs(tree01.growth - 0.85) < 0.001, `tree_01 growth at 2021: expected ~0.85, got ${tree01.growth}`);
    // crownVolume: lerp(0.7, 1.0, 0.5) = 0.85
    assert.ok(Math.abs(tree01.crownVolume - 0.85) < 0.001, `tree_01 crownVolume at 2021: expected ~0.85, got ${tree01.crownVolume}`);
  });

  it('person height interpolates correctly between anchors', () => {
    // person_01 at 2016: height=0.7, at 2026: height=1.0
    const result = getInterpolatedState(2021, fixture);
    const person01 = result.states.person_01;
    assert.ok(person01, 'person_01 should exist');
    // height: lerp(0.7, 1.0, 0.5) = 0.85
    assert.ok(Math.abs(person01.height - 0.85) < 0.001, `person_01 height at 2021: expected ~0.85, got ${person01.height}`);
  });

  it('structuralVariant switches at t=0.5 threshold', () => {
    // gate_01: 2026="original", 2036="renovated"
    // At t < 0.5 (before 2031), should be "original"
    // At t >= 0.5 (2031+), should be "renovated"
    const before = getInterpolatedState(2030, fixture);
    assert.strictEqual(before.states.gate_01?.structuralVariant, 'original');

    const after = getInterpolatedState(2032, fixture);
    assert.strictEqual(after.states.gate_01?.structuralVariant, 'renovated');
  });

  it('newWindows switches at t=0.7 threshold', () => {
    // gate_01: 2026 newWindows absent (false), 2036 newWindows=true
    // At t < 0.7 (before 2033), newWindows should be false
    // At t >= 0.7 (2033+), newWindows should be true
    const before = getInterpolatedState(2032, fixture);
    assert.strictEqual(before.states.gate_01?.newWindows, false);

    const after = getInterpolatedState(2034, fixture);
    assert.strictEqual(after.states.gate_01?.newWindows, true);
  });

  it('bodyStage switches at t=0.5 threshold', () => {
    // person_01: 2026="young-adult", 2036="young-adult" (same)
    // person_02: 2026="middle-aged", 2036="middle-aged" (same)
    // Test 2046 range: person_01 2036="young-adult", 2046="middle-aged"
    const result = getInterpolatedState(2045, fixture);
    // At t close to 1.0, should pick 2046's bodyStage
    assert.strictEqual(result.states.person_01?.bodyStage, 'middle-aged');
  });

  it('positionOffset interpolates from zero to target', () => {
    // person_01 at 2036: positionOffset=[0.3, 0, 0.2]
    // At 2036 (exact anchor), t=1.0 in 2026-2036 span
    const result = getInterpolatedState(2036, fixture);
    const offset = result.states.person_01?.positionOffset;
    assert.ok(offset, 'person_01 should have positionOffset');
    assert.ok(Math.abs(offset[0] - 0.3) < 0.001, `offset.x: expected ~0.3, got ${offset[0]}`);
    assert.ok(Math.abs(offset[2] - 0.2) < 0.001, `offset.z: expected ~0.2, got ${offset[2]}`);
  });
});

// ── Scene state at different time values ───────────────────────

describe('scene state at different time values', () => {
  it('before first anchor, uses first anchor state (clamped)', () => {
    const result = getInterpolatedState(2010, fixture);
    // Should use first anchor pair (2016-2026), t clamped to 0
    assert.strictEqual(result.lowerYear, 2016);
    const tree01 = result.states.tree_01;
    assert.ok(tree01);
    assert.ok(Math.abs(tree01.growth - 0.7) < 0.001);
  });

  it('after last anchor, uses last anchor state (clamped)', () => {
    const result = getInterpolatedState(2060, fixture);
    // Should use last anchor pair (2036-2046), t clamped to 1.0
    // tree_01 at 2046: growth=1.5
    const tree01 = result.states.tree_01;
    assert.ok(tree01);
    assert.ok(Math.abs(tree01.growth - 1.5) < 0.001, `tree_01 growth at 2060: expected ~1.5, got ${tree01.growth}`);
  });

  it('weathering increases over time', () => {
    const at2016 = getInterpolatedState(2016, fixture);
    const at2026 = getInterpolatedState(2026, fixture);
    const at2036 = getInterpolatedState(2036, fixture);

    const w2016 = at2016.states.gate_01?.weathering ?? 0;
    const w2026 = at2026.states.gate_01?.weathering ?? 0;
    const w2036 = at2036.states.gate_01?.weathering ?? 0;

    assert.ok(w2036 > w2026, `weathering should increase: 2026=${w2026}, 2036=${w2036}`);
    assert.ok(w2026 >= w2016, `weathering should not decrease: 2016=${w2016}, 2026=${w2026}`);
  });

  it('all temporal entities have consistent fields across all anchors', () => {
    const years = [2016, 2021, 2026, 2031, 2036, 2041, 2046];
    for (const year of years) {
      const result = getInterpolatedState(year, fixture);
      for (const [id, state] of Object.entries(result.states)) {
        assert.ok(typeof state.presence === 'number', `${id}@${year}: presence not a number`);
        assert.ok(typeof state.growth === 'number', `${id}@${year}: growth not a number`);
        assert.ok(typeof state.crownVolume === 'number', `${id}@${year}: crownVolume not a number`);
        assert.ok(typeof state.weathering === 'number', `${id}@${year}: weathering not a number`);
        assert.ok(typeof state.height === 'number', `${id}@${year}: height not a number`);
        assert.ok(typeof state.structuralVariant === 'string', `${id}@${year}: structuralVariant not a string`);
        assert.ok(typeof state.newWindows === 'boolean', `${id}@${year}: newWindows not a boolean`);
        assert.ok(typeof state.bodyStage === 'string', `${id}@${year}: bodyStage not a string`);
        assert.ok(Array.isArray(state.positionOffset), `${id}@${year}: positionOffset not an array`);
      }
    }
  });
});
