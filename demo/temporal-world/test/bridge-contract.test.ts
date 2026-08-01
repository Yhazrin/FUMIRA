import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');

// ── Load fixture for contract validation ───────────────────────

const fixture = JSON.parse(
  readFileSync(resolve(root, 'test/fixtures/campus-gate.json'), 'utf-8'),
);

// ── Helper: validate required fields ───────────────────────────

function assertHasFields(obj: Record<string, unknown>, fields: string[], label: string) {
  for (const f of fields) {
    assert.ok(f in obj, `${label} missing required field: ${f}`);
  }
}

// ── BridgeMessage type validation ──────────────────────────────

describe('BridgeMessage types', () => {
  // The WS protocol types are defined in packages/scene-compiler/src/types.ts.
  // We validate that the fixture's temporalSpec structure matches the contracts
  // that the bridge relies on.

  it('fixture has valid SceneFixture shape (id, name, version, palette, style, entities, temporalSpec)', () => {
    assertHasFields(fixture, ['id', 'name', 'version', 'palette', 'style', 'entities', 'temporalSpec'], 'SceneFixture');
    assert.ok(typeof fixture.id === 'string');
    assert.ok(typeof fixture.name === 'string');
    assert.ok(typeof fixture.version === 'string');
    assert.ok(Array.isArray(fixture.entities));
  });

  it('temporalSpec has anchorYears and timelineIntervals', () => {
    const ts = fixture.temporalSpec;
    assertHasFields(ts, ['anchorYears', 'timelineIntervals'], 'TemporalSpec');
    assert.ok(Array.isArray(ts.anchorYears));
    assert.ok(Array.isArray(ts.timelineIntervals));
  });

  it('each anchorYear has year (number) and entities (object)', () => {
    for (const anchor of fixture.temporalSpec.anchorYears) {
      assertHasFields(anchor, ['year', 'entities'], 'TemporalAnchorState');
      assert.ok(typeof anchor.year === 'number');
      assert.ok(typeof anchor.entities === 'object' && anchor.entities !== null);
    }
  });

  it('each timelineInterval has startYear, endYear, mode, narrative', () => {
    for (const interval of fixture.temporalSpec.timelineIntervals) {
      assertHasFields(interval, ['startYear', 'endYear', 'mode', 'narrative'], 'TimelineInterval');
      assert.ok(typeof interval.startYear === 'number');
      assert.ok(typeof interval.endYear === 'number');
      assert.ok(interval.endYear >= interval.startYear, 'endYear must be >= startYear');
    }
  });
});

// ── NativeBridge message serialization/deserialization ─────────

describe('NativeBridge message serialization', () => {
  // Simulate the message format the iOS native bridge uses:
  // JSON-serialized scene data sent over the bridge.

  it('fixture round-trips through JSON without data loss', () => {
    const serialized = JSON.stringify(fixture);
    const deserialized = JSON.parse(serialized);
    assert.deepStrictEqual(deserialized, fixture);
  });

  it('palette round-trips preserving all color tokens', () => {
    const paletteKeys = Object.keys(fixture.palette);
    assert.ok(paletteKeys.length > 0, 'palette must have color tokens');

    const roundTripped = JSON.parse(JSON.stringify(fixture.palette));
    for (const key of paletteKeys) {
      assert.strictEqual(roundTripped[key], fixture.palette[key], `palette.${key} changed during round-trip`);
      // Validate hex color format
      assert.match(
        roundTripped[key],
        /^#[0-9A-Fa-f]{6}$/,
        `palette.${key} is not a valid hex color: ${roundTripped[key]}`,
      );
    }
  });

  it('entities round-trip preserving position arrays', () => {
    const roundTripped = JSON.parse(JSON.stringify(fixture.entities));
    for (let i = 0; i < fixture.entities.length; i++) {
      const orig = fixture.entities[i];
      const rt = roundTripped[i];
      assert.strictEqual(rt.id, orig.id);
      assert.deepStrictEqual(rt.position, orig.position, `entity ${orig.id} position changed`);
    }
  });

  it('temporalSpec anchor entity states round-trip correctly', () => {
    const roundTripped = JSON.parse(JSON.stringify(fixture.temporalSpec));
    for (let i = 0; i < fixture.temporalSpec.anchorYears.length; i++) {
      const origAnchor = fixture.temporalSpec.anchorYears[i];
      const rtAnchor = roundTripped.anchorYears[i];
      assert.strictEqual(rtAnchor.year, origAnchor.year);
      for (const entityId of Object.keys(origAnchor.entities)) {
        assert.deepStrictEqual(
          rtAnchor.entities[entityId],
          origAnchor.entities[entityId],
          `anchor ${origAnchor.year} entity ${entityId} changed`,
        );
      }
    }
  });
});

// ── Version field presence ─────────────────────────────────────

describe('version field presence', () => {
  it('fixture has version string', () => {
    assert.ok(typeof fixture.version === 'string', 'fixture.version must be a string');
    assert.ok(fixture.version.length > 0, 'fixture.version must not be empty');
  });

  it('fixture version follows semver-like format', () => {
    assert.match(
      fixture.version,
      /^\d+\.\d+\.\d+$/,
      `version "${fixture.version}" does not match X.Y.Z`,
    );
  });

  it('all entities have id field', () => {
    for (const entity of fixture.entities) {
      assert.ok(typeof entity.id === 'string' && entity.id.length > 0, `entity missing id: ${JSON.stringify(entity)}`);
    }
  });

  it('palette has all required contract fields', () => {
    const requiredPaletteKeys = [
      'charcoal', 'warmWhite', 'warmWhiteR', 'orange', 'orangeRim',
      'lime', 'limeRim', 'yellow', 'yellowRim', 'ground', 'road',
      'sidewalk', 'grass', 'trunk', 'foliage1', 'foliage2', 'skin',
      'cloth1', 'cloth2',
    ];
    for (const key of requiredPaletteKeys) {
      assert.ok(key in fixture.palette, `palette missing required key: ${key}`);
    }
  });

  it('style has clayMat, fog, and clearColor', () => {
    assertHasFields(fixture.style, ['clayMat', 'fog', 'clearColor'], 'StyleSpec');
    assertHasFields(fixture.style.clayMat, ['roughness', 'metalness', 'flatShading'], 'ClayMatDefaults');
    assertHasFields(fixture.style.fog, ['color', 'density'], 'FogSpec');
  });
});
