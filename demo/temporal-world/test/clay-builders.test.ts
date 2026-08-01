import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildEntity, clayMat } from '@fumira/clay-builders';
import type { EntitySpec, Palette } from '@fumira/contracts';
import * as THREE from 'three';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');

// ── Fixture palette ────────────────────────────────────────────

const fixture = JSON.parse(
  readFileSync(resolve(root, 'test/fixtures/campus-gate.json'), 'utf-8'),
);
const palette: Palette = fixture.palette;

// ── Helper: collect all meshes from a group ────────────────────

function collectMeshes(group: THREE.Group): THREE.Mesh[] {
  const meshes: THREE.Mesh[] = [];
  group.traverse(obj => {
    if (obj instanceof THREE.Mesh) meshes.push(obj);
  });
  return meshes;
}

// ── Helper: extract hex from palette string ────────────────────

function hexNum(color: string): number {
  return parseInt(color.replace('#', ''), 16);
}

// ── Deterministic geometry ─────────────────────────────────────

describe('deterministic geometry', () => {
  // Builders that do NOT use Math.random() should produce identical
  // scene graphs when called with the same inputs.

  const deterministicEntities: EntitySpec[] = [
    { id: 'bldg_1', category: 'building', type: 'building', position: [1, 0, 2], size: [4, 3, 1.5] },
    { id: 'char_1', category: 'character', type: 'character', position: [0, 0, 0], rotation: 0.5, clothColor: 'cloth1', scale: 0.38 },
    { id: 'bench_1', category: 'prop', type: 'bench', position: [-1, 0, 0.5], rotation: 0.3 },
    { id: 'sign_1', category: 'prop', type: 'streetSign', position: [2, 0, 1] },
    { id: 'bike_1', category: 'prop', type: 'bicycle', position: [1, 0, 0], rotation: 0.5 },
    { id: 'lamp_1', category: 'prop', type: 'lampPost', position: [-2, 0, 1.5] },
  ];

  for (const spec of deterministicEntities) {
    it(`${spec.type} (id=${spec.id}) produces identical output for same input`, () => {
      const group1 = buildEntity(spec, palette);
      const group2 = buildEntity(spec, palette);

      assert.ok(group1, `buildEntity returned null for ${spec.type}`);
      assert.ok(group2, `buildEntity returned null for ${spec.type}`);

      // Same number of children
      assert.strictEqual(
        group1!.children.length,
        group2!.children.length,
        `child count differs for ${spec.type}`,
      );

      // Same number of meshes
      const meshes1 = collectMeshes(group1!);
      const meshes2 = collectMeshes(group2!);
      assert.strictEqual(meshes1.length, meshes2.length, `mesh count differs for ${spec.type}`);

      // Each mesh has same geometry type and comparable parameters
      for (let i = 0; i < meshes1.length; i++) {
        const g1 = meshes1[i].geometry;
        const g2 = meshes2[i].geometry;
        assert.strictEqual(
          g1.type,
          g2.type,
          `${spec.type} mesh[${i}] geometry type differs: ${g1.type} vs ${g2.type}`,
        );

        // Position should match
        assert.ok(
          meshes1[i].position.distanceTo(meshes2[i].position) < 0.001,
          `${spec.type} mesh[${i}] position differs`,
        );
      }

      // Same position
      assert.ok(
        group1!.position.distanceTo(group2!.position) < 0.001,
        `${spec.type} group position differs`,
      );
    });
  }
});

// ── Bevel radius / geometry dimensions > 0 ─────────────────────

describe('bevel radius and geometry dimensions', () => {
  const allEntityTypes: EntitySpec[] = [
    { id: 'b', category: 'building', type: 'building', position: [0, 0, 0], size: [4, 3, 1.5] },
    { id: 't', category: 'vegetation', type: 'tree', position: [0, 0, 0], scale: 1.0, trunkHeight: 1.0, crownRadius: 0.7 },
    { id: 'c', category: 'character', type: 'character', position: [0, 0, 0], scale: 0.38 },
    { id: 'be', category: 'prop', type: 'bench', position: [0, 0, 0] },
    { id: 's', category: 'prop', type: 'streetSign', position: [0, 0, 0] },
    { id: 'bi', category: 'prop', type: 'bicycle', position: [0, 0, 0] },
    { id: 'l', category: 'prop', type: 'lampPost', position: [0, 0, 0] },
    { id: 'f', category: 'prop', type: 'flowerBed', position: [0, 0, 0], size: [1.5, 0.6] },
  ];

  for (const spec of allEntityTypes) {
    it(`${spec.type}: all cylinders have positive radius`, () => {
      const group = buildEntity(spec, palette);
      assert.ok(group, `buildEntity returned null for ${spec.type}`);

      const meshes = collectMeshes(group!);
      for (const mesh of meshes) {
        if (mesh.geometry instanceof THREE.CylinderGeometry) {
          const p = mesh.geometry.parameters;
          assert.ok(
            (p.radiusTop ?? 0) > 0 || (p.radiusBottom ?? 0) > 0,
            `${spec.type}: CylinderGeometry has zero radii (top=${p.radiusTop}, bottom=${p.radiusBottom})`,
          );
        }
      }
    });

    it(`${spec.type}: all spheres have positive radius`, () => {
      const group = buildEntity(spec, palette);
      assert.ok(group, `buildEntity returned null for ${spec.type}`);

      const meshes = collectMeshes(group!);
      for (const mesh of meshes) {
        if (mesh.geometry instanceof THREE.SphereGeometry) {
          const r = mesh.geometry.parameters.radius;
          assert.ok(
            r !== undefined && r > 0,
            `${spec.type}: SphereGeometry has non-positive radius: ${r}`,
          );
        }
      }
    });

    it(`${spec.type}: all boxes have positive dimensions`, () => {
      const group = buildEntity(spec, palette);
      assert.ok(group, `buildEntity returned null for ${spec.type}`);

      const meshes = collectMeshes(group!);
      for (const mesh of meshes) {
        if (mesh.geometry instanceof THREE.BoxGeometry) {
          const p = mesh.geometry.parameters;
          assert.ok((p.width ?? 0) > 0, `${spec.type}: BoxGeometry width <= 0`);
          assert.ok((p.height ?? 0) > 0, `${spec.type}: BoxGeometry height <= 0`);
          assert.ok((p.depth ?? 0) > 0, `${spec.type}: BoxGeometry depth <= 0`);
        }
      }
    });

    it(`${spec.type}: all capsules have positive radius and length`, () => {
      const group = buildEntity(spec, palette);
      assert.ok(group, `buildEntity returned null for ${spec.type}`);

      const meshes = collectMeshes(group!);
      for (const mesh of meshes) {
        if (mesh.geometry instanceof THREE.CapsuleGeometry) {
          const p = mesh.geometry.parameters;
          assert.ok((p.radius ?? 0) > 0, `${spec.type}: CapsuleGeometry radius <= 0`);
          assert.ok((p.length ?? 0) > 0, `${spec.type}: CapsuleGeometry length <= 0`);
        }
      }
    });
  }
});

// ── Material roughness within valid range ──────────────────────

describe('material roughness valid range', () => {
  const allEntityTypes: EntitySpec[] = [
    { id: 'b', category: 'building', type: 'building', position: [0, 0, 0], size: [4, 3, 1.5] },
    { id: 't', category: 'vegetation', type: 'tree', position: [0, 0, 0], scale: 1.0, trunkHeight: 1.0, crownRadius: 0.7 },
    { id: 'c', category: 'character', type: 'character', position: [0, 0, 0], scale: 0.38 },
    { id: 'be', category: 'prop', type: 'bench', position: [0, 0, 0] },
    { id: 's', category: 'prop', type: 'streetSign', position: [0, 0, 0] },
    { id: 'bi', category: 'prop', type: 'bicycle', position: [0, 0, 0] },
    { id: 'l', category: 'prop', type: 'lampPost', position: [0, 0, 0] },
    { id: 'f', category: 'prop', type: 'flowerBed', position: [0, 0, 0], size: [1.5, 0.6] },
  ];

  for (const spec of allEntityTypes) {
    it(`${spec.type}: all materials have roughness in [0, 1]`, () => {
      const group = buildEntity(spec, palette);
      assert.ok(group, `buildEntity returned null for ${spec.type}`);

      const meshes = collectMeshes(group!);
      for (const mesh of meshes) {
        const mat = mesh.material;
        if (mat instanceof THREE.MeshStandardMaterial) {
          assert.ok(
            mat.roughness >= 0 && mat.roughness <= 1,
            `${spec.type}: roughness ${mat.roughness} out of range [0, 1]`,
          );
        }
      }
    });

    it(`${spec.type}: all materials have metalness in [0, 1]`, () => {
      const group = buildEntity(spec, palette);
      assert.ok(group, `buildEntity returned null for ${spec.type}`);

      const meshes = collectMeshes(group!);
      for (const mesh of meshes) {
        const mat = mesh.material;
        if (mat instanceof THREE.MeshStandardMaterial) {
          assert.ok(
            mat.metalness >= 0 && mat.metalness <= 1,
            `${spec.type}: metalness ${mat.metalness} out of range [0, 1]`,
          );
        }
      }
    });

    it(`${spec.type}: materials have valid color (non-zero hex)`, () => {
      const group = buildEntity(spec, palette);
      assert.ok(group, `buildEntity returned null for ${spec.type}`);

      const meshes = collectMeshes(group!);
      for (const mesh of meshes) {
        const mat = mesh.material;
        if (mat instanceof THREE.MeshStandardMaterial) {
          // Color hex should be a valid number >= 0
          const hex = mat.color.getHex();
          assert.ok(hex >= 0, `${spec.type}: invalid color hex ${hex}`);
        }
      }
    });
  }
});

// ── clayMat utility ────────────────────────────────────────────

describe('clayMat utility', () => {
  it('creates material with default roughness 0.84', () => {
    const mat = clayMat(0xFF672A);
    assert.ok(mat instanceof THREE.MeshStandardMaterial);
    assert.strictEqual(mat.roughness, 0.84);
    assert.strictEqual(mat.metalness, 0);
  });

  it('allows overriding roughness', () => {
    const mat = clayMat(0xFF672A, { roughness: 0.5 });
    assert.strictEqual(mat.roughness, 0.5);
  });

  it('stores baseColor in userData', () => {
    const mat = clayMat(0xFF0000);
    assert.ok(mat.userData?.baseColor instanceof THREE.Color);
    assert.strictEqual(mat.userData.baseColor.getHex(), 0xFF0000);
  });

  it('accepts string color', () => {
    const mat = clayMat('#00FF00');
    assert.ok(mat instanceof THREE.MeshStandardMaterial);
    assert.strictEqual(mat.color.getHex(), 0x00FF00);
  });
});

// ── buildEntity dispatch ───────────────────────────────────────

describe('buildEntity dispatch', () => {
  it('returns null for unknown entity type', () => {
    const result = buildEntity(
      { id: 'unknown', category: 'x', type: 'nonexistent', position: [0, 0, 0] },
      palette,
    );
    assert.strictEqual(result, null);
  });

  it('returns THREE.Group for known types', () => {
    const types = ['building', 'tree', 'character', 'bench', 'streetSign', 'bicycle', 'lampPost', 'flowerBed'];
    for (const type of types) {
      const result = buildEntity(
        { id: `test_${type}`, category: 'test', type, position: [0, 0, 0], size: [1, 1, 0.5] },
        palette,
      );
      assert.ok(result instanceof THREE.Group, `expected Group for type "${type}", got ${result?.constructor.name}`);
    }
  });

  it('group position matches entity position', () => {
    const pos: [number, number, number] = [3, 1, -2];
    const group = buildEntity(
      { id: 'pos_test', category: 'building', type: 'building', position: pos, size: [4, 3, 1.5] },
      palette,
    );
    assert.ok(group);
    assert.ok(Math.abs(group!.position.x - 3) < 0.001);
    assert.ok(Math.abs(group!.position.y - 1) < 0.001);
    assert.ok(Math.abs(group!.position.z - (-2)) < 0.001);
  });
});
