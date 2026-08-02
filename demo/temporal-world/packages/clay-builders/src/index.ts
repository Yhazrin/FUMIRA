import * as THREE from 'three';
import type { EntitySpec, Palette, ClayMatDefaults } from '@fumira/contracts';

const DEFAULT_CLAY: ClayMatDefaults = {
  roughness: 0.84,
  metalness: 0,
  flatShading: false,
};

export function clayMat(
  color: number | string,
  opts: Partial<THREE.MeshStandardMaterialParameters> = {},
  defaults: ClayMatDefaults = DEFAULT_CLAY,
): THREE.MeshStandardMaterial {
  const mat = new THREE.MeshStandardMaterial({
    color,
    roughness: opts.roughness ?? defaults.roughness,
    metalness: opts.metalness ?? defaults.metalness,
    flatShading: opts.flatShading ?? defaults.flatShading,
    ...opts,
  });
  mat.userData = { baseColor: new THREE.Color(color) };
  return mat;
}

function hex(paletteColor: string): number {
  return parseInt(paletteColor.replace('#', ''), 16);
}

// ── Building ─────────────────────────────────────────────────

export function createBuilding(entity: EntitySpec, palette: Palette): THREE.Group {
  const group = new THREE.Group();
  group.userData = { category: 'building', id: entity.id };

  const bW = (entity.size as number[])?.[0] ?? 4.2;
  const bH = (entity.size as number[])?.[1] ?? 3.2;
  const bD = (entity.size as number[])?.[2] ?? 1.6;

  const body = new THREE.Mesh(
    new THREE.BoxGeometry(bW, bH, bD, 2, 2, 2),
    clayMat(hex(palette.warmWhite)),
  );
  body.position.set(0, bH / 2, 0);
  body.castShadow = true;
  body.receiveShadow = true;
  group.add(body);

  const bRim = new THREE.Mesh(
    new THREE.BoxGeometry(bW + 0.12, 0.2, bD + 0.12),
    clayMat(hex(palette.warmWhiteR)),
  );
  bRim.position.set(0, 0.1, 0);
  bRim.castShadow = true;
  group.add(bRim);

  const arch = new THREE.Mesh(
    new THREE.BoxGeometry(1.6, 2.2, bD + 0.15),
    clayMat(hex(palette.orange)),
  );
  arch.position.set(0, 1.1, 0);
  arch.castShadow = true;
  group.add(arch);

  const archTop = new THREE.Mesh(
    new THREE.CylinderGeometry(0.8, 0.8, bD + 0.15, 16, 1, false, 0, Math.PI),
    clayMat(hex(palette.orange)),
  );
  archTop.rotation.x = Math.PI / 2;
  archTop.rotation.z = Math.PI / 2;
  archTop.position.set(0, 2.2, 0);
  group.add(archTop);

  for (let side = -1; side <= 1; side += 2) {
    for (let i = 0; i < 2; i++) {
      const win = new THREE.Mesh(
        new THREE.BoxGeometry(0.45, 0.6, 0.08),
        clayMat(hex(palette.charcoal), { roughness: 0.4 }),
      );
      win.position.set(side * (1.1 + i * 0.65), 1.8, bD / 2 + 0.04);
      group.add(win);

      const frame = new THREE.Mesh(
        new THREE.BoxGeometry(0.52, 0.67, 0.04),
        clayMat(hex(palette.warmWhiteR)),
      );
      frame.position.copy(win.position);
      frame.position.z += 0.03;
      group.add(frame);
    }
  }

  const roof = new THREE.Mesh(
    new THREE.BoxGeometry(bW + 0.2, 0.18, bD + 0.2),
    clayMat(hex(palette.orangeRim)),
  );
  roof.position.set(0, bH + 0.09, 0);
  roof.castShadow = true;
  group.add(roof);

  const signBoard = new THREE.Mesh(
    new THREE.BoxGeometry(2.0, 0.45, 0.08),
    clayMat(hex(palette.orange)),
  );
  signBoard.position.set(0, bH - 0.35, bD / 2 + 0.08);
  signBoard.castShadow = true;
  group.add(signBoard);

  for (let side = -1; side <= 1; side += 2) {
    const pillar = new THREE.Mesh(
      new THREE.CylinderGeometry(0.12, 0.14, bH, 8),
      clayMat(hex(palette.warmWhiteR)),
    );
    pillar.position.set(side * (bW / 2 - 0.15), bH / 2, bD / 2 + 0.08);
    pillar.castShadow = true;
    group.add(pillar);
  }

  group.position.set(entity.position[0], entity.position[1], entity.position[2]);
  return group;
}

// ── Tree ──────────────────────────────────────────────────────

export function createTree(entity: EntitySpec, palette: Palette): THREE.Group {
  const s = entity.scale ?? 1;
  const tH = (entity.trunkHeight as number) ?? 1.0;
  const cR = (entity.crownRadius as number) ?? 0.7;

  const tree = new THREE.Group();
  tree.userData = { category: 'vegetation', id: entity.id };

  const trunk = new THREE.Mesh(
    new THREE.CylinderGeometry(0.06 * s, 0.1 * s, tH * s, 8),
    clayMat(hex(palette.trunk)),
  );
  trunk.position.y = (tH * s) / 2;
  trunk.castShadow = true;
  tree.add(trunk);

  for (let i = 0; i < 4; i++) {
    const r = cR * s * (0.6 + Math.random() * 0.5);
    const blob = new THREE.Mesh(
      new THREE.SphereGeometry(r, 12, 10),
      clayMat(hex(i % 2 === 0 ? palette.foliage1 : palette.foliage2)),
    );
    blob.position.set(
      (Math.random() - 0.5) * cR * s * 0.6,
      tH * s + cR * s * 0.3 + (Math.random() - 0.3) * cR * s * 0.5,
      (Math.random() - 0.5) * cR * s * 0.6,
    );
    blob.scale.y = 0.7 + Math.random() * 0.3;
    blob.castShadow = true;
    tree.add(blob);
  }

  tree.position.set(entity.position[0], entity.position[1], entity.position[2]);
  return tree;
}

// ── Character ─────────────────────────────────────────────────

export function createCharacter(entity: EntitySpec, palette: Palette): THREE.Group {
  const clothColor = hex(palette[(entity.clothColor as keyof Palette) ?? 'cloth1'] ?? entity.clothColor as string);
  const s = entity.scale ?? 0.38;

  const c = new THREE.Group();
  c.userData = { category: 'character', id: entity.id };

  for (let side = -1; side <= 1; side += 2) {
    const leg = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.08 * s, 0.35 * s, 4, 8),
      clayMat(hex(palette.cloth2)),
    );
    leg.position.set(side * 0.1 * s, 0.2 * s, 0);
    c.add(leg);
  }

  const torso = new THREE.Mesh(
    new THREE.CapsuleGeometry(0.18 * s, 0.3 * s, 4, 8),
    clayMat(clothColor),
  );
  torso.position.y = 0.55 * s;
  torso.castShadow = true;
  c.add(torso);

  for (let side = -1; side <= 1; side += 2) {
    const arm = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.055 * s, 0.28 * s, 4, 8),
      clayMat(clothColor),
    );
    arm.position.set(side * 0.24 * s, 0.52 * s, 0);
    arm.rotation.z = side * 0.15;
    c.add(arm);
  }

  const head = new THREE.Mesh(
    new THREE.SphereGeometry(0.15 * s, 10, 8),
    clayMat(hex(palette.skin)),
  );
  head.position.y = 0.88 * s;
  head.scale.y = 1.05;
  head.castShadow = true;
  c.add(head);

  const hair = new THREE.Mesh(
    new THREE.SphereGeometry(0.16 * s, 10, 8, 0, Math.PI * 2, 0, Math.PI * 0.6),
    clayMat(hex(palette.charcoal)),
  );
  hair.position.y = 0.9 * s;
  c.add(hair);

  c.position.set(entity.position[0], entity.position[1], entity.position[2]);
  c.rotation.y = entity.rotation ?? 0;
  return c;
}

// ── Props ─────────────────────────────────────────────────────

function createBench(entity: EntitySpec, palette: Palette): THREE.Group {
  const b = new THREE.Group();
  b.userData = { category: 'prop', id: entity.id };

  const seat = new THREE.Mesh(
    new THREE.BoxGeometry(0.8, 0.06, 0.3),
    clayMat(hex(palette.trunk)),
  );
  seat.position.y = 0.32;
  b.add(seat);

  const back = new THREE.Mesh(
    new THREE.BoxGeometry(0.8, 0.35, 0.05),
    clayMat(hex(palette.trunk)),
  );
  back.position.set(0, 0.48, -0.12);
  b.add(back);

  for (let lx = -1; lx <= 1; lx += 2) {
    const leg = new THREE.Mesh(
      new THREE.BoxGeometry(0.05, 0.32, 0.25),
      clayMat(hex(palette.warmWhiteR)),
    );
    leg.position.set(lx * 0.32, 0.16, 0);
    b.add(leg);
  }

  b.position.set(entity.position[0], entity.position[1], entity.position[2]);
  b.rotation.y = entity.rotation ?? 0;
  return b;
}

function createStreetSign(entity: EntitySpec, palette: Palette): THREE.Group {
  const s = new THREE.Group();
  s.userData = { category: 'prop', id: entity.id };

  const pole = new THREE.Mesh(
    new THREE.CylinderGeometry(0.03, 0.03, 1.2, 6),
    clayMat(hex(palette.warmWhiteR)),
  );
  pole.position.y = 0.6;
  s.add(pole);

  const board = new THREE.Mesh(
    new THREE.BoxGeometry(0.5, 0.25, 0.04),
    clayMat(hex(palette.orange)),
  );
  board.position.y = 1.1;
  board.castShadow = true;
  s.add(board);

  s.position.set(entity.position[0], entity.position[1], entity.position[2]);
  return s;
}

function createBicycle(entity: EntitySpec, palette: Palette): THREE.Group {
  const bike = new THREE.Group();
  bike.userData = { category: 'prop', id: entity.id };

  const wR = 0.18;
  for (let wx = -1; wx <= 1; wx += 2) {
    const wheel = new THREE.Mesh(
      new THREE.TorusGeometry(wR, 0.025, 8, 16),
      clayMat(hex(palette.charcoal)),
    );
    wheel.rotation.y = Math.PI / 2;
    wheel.position.set(wx * 0.25, wR, 0);
    bike.add(wheel);
  }

  const frame = new THREE.Mesh(
    new THREE.CylinderGeometry(0.02, 0.02, 0.4, 6),
    clayMat(hex(palette.lime)),
  );
  frame.position.set(0, wR + 0.1, 0);
  frame.rotation.z = 0.3;
  bike.add(frame);

  const bar = new THREE.Mesh(
    new THREE.CylinderGeometry(0.015, 0.015, 0.2, 6),
    clayMat(hex(palette.warmWhiteR)),
  );
  bar.position.set(0.2, wR + 0.25, 0);
  bar.rotation.z = Math.PI / 2;
  bike.add(bar);

  bike.position.set(entity.position[0], entity.position[1], entity.position[2]);
  bike.rotation.y = entity.rotation ?? 0;
  bike.scale.setScalar(0.8);
  return bike;
}

// ── Street-scene props ───────────────────────────────────────

function materialColor(entity: EntitySpec, fallback: string): number {
  const material = entity.material as { color?: string } | undefined;
  return hex(material?.color ?? fallback);
}

/**
 * A deliberately readable electric moped blockout. It is not intended to
 * recover hidden mechanical geometry from one photograph; the seat, red body,
 * two wheels, handlebar and rear rack are the recognition cues that survive
 * the clay treatment and the desktop camera distance.
 */
function createMoped(entity: EntitySpec, palette: Palette): THREE.Group {
  const moped = new THREE.Group();
  moped.userData = { category: 'vehicle', id: entity.id };
  const bodyColor = materialColor(entity, palette.orangeRim);
  const dark = hex(palette.charcoal);
  const rim = hex(palette.warmWhiteR);
  const wheelRadius = 0.28;

  for (const x of [-0.58, 0.58]) {
    const wheel = new THREE.Mesh(
      new THREE.TorusGeometry(wheelRadius, 0.075, 10, 18),
      clayMat(dark, { roughness: 0.9 }),
    );
    wheel.rotation.y = Math.PI / 2;
    wheel.position.set(x, wheelRadius + 0.02, 0);
    wheel.castShadow = true;
    moped.add(wheel);
  }

  const body = new THREE.Mesh(
    new THREE.BoxGeometry(0.95, 0.42, 0.42, 3, 2, 3),
    clayMat(bodyColor, { roughness: 0.58 }),
  );
  body.position.set(0, 0.52, 0);
  body.castShadow = true;
  moped.add(body);

  const footboard = new THREE.Mesh(
    new THREE.BoxGeometry(0.72, 0.09, 0.48, 2, 1, 2),
    clayMat(rim),
  );
  footboard.position.set(0.02, 0.78, 0);
  moped.add(footboard);

  const seat = new THREE.Mesh(
    new THREE.BoxGeometry(0.6, 0.16, 0.38, 3, 2, 3),
    clayMat(dark, { roughness: 0.72 }),
  );
  seat.position.set(-0.12, 1.0, 0);
  seat.castShadow = true;
  moped.add(seat);

  const stem = new THREE.Mesh(
    new THREE.CylinderGeometry(0.045, 0.06, 0.54, 8),
    clayMat(bodyColor),
  );
  stem.position.set(0.48, 0.92, 0);
  stem.rotation.z = -0.18;
  moped.add(stem);

  const handlebar = new THREE.Mesh(
    new THREE.CylinderGeometry(0.035, 0.035, 0.42, 8),
    clayMat(dark),
  );
  handlebar.position.set(0.55, 1.2, 0);
  handlebar.rotation.x = Math.PI / 2;
  moped.add(handlebar);

  const mirror = new THREE.Mesh(
    new THREE.SphereGeometry(0.09, 10, 8),
    clayMat(rim, { roughness: 0.46 }),
  );
  mirror.position.set(0.55, 1.42, 0.16);
  moped.add(mirror);

  const rack = new THREE.Mesh(
    new THREE.BoxGeometry(0.62, 0.05, 0.5, 2, 1, 2),
    clayMat(rim, { roughness: 0.7 }),
  );
  rack.position.set(-0.52, 1.08, 0);
  moped.add(rack);

  moped.position.set(entity.position[0], entity.position[1], entity.position[2]);
  moped.rotation.y = entity.rotation ?? 0;
  moped.scale.setScalar(entity.scale ?? 1);
  return moped;
}

function createUtilityBox(entity: EntitySpec, palette: Palette): THREE.Group {
  const box = new THREE.Group();
  box.userData = { category: 'infrastructure', id: entity.id };
  const warm = hex(palette.warmWhite);
  const rim = hex(palette.warmWhiteR);
  const dark = hex(palette.charcoal);
  const size = (entity.size as number[]) ?? [1.45, 2.2, 0.5];

  const cabinet = new THREE.Mesh(
    new THREE.BoxGeometry(size[0], size[1], size[2], 3, 3, 2),
    clayMat(warm, { roughness: 0.68 }),
  );
  cabinet.position.y = size[1] / 2 + 0.5;
  cabinet.castShadow = true;
  cabinet.receiveShadow = true;
  box.add(cabinet);

  const cap = new THREE.Mesh(
    new THREE.BoxGeometry(size[0] + 0.12, 0.12, size[2] + 0.12, 2, 1, 2),
    clayMat(rim),
  );
  cap.position.y = size[1] + 0.56;
  box.add(cap);

  for (const x of [-size[0] * 0.32, size[0] * 0.32]) {
    const leg = new THREE.Mesh(
      new THREE.BoxGeometry(0.08, 0.48, 0.08),
      clayMat(rim),
    );
    leg.position.set(x, 0.24, 0);
    box.add(leg);
  }

  const lock = new THREE.Mesh(
    new THREE.BoxGeometry(0.08, 0.16, 0.03),
    clayMat(dark, { roughness: 0.5 }),
  );
  lock.position.set(size[0] * 0.28, size[1] * 0.58 + 0.5, size[2] / 2 + 0.03);
  box.add(lock);

  box.position.set(entity.position[0], entity.position[1], entity.position[2]);
  box.rotation.y = entity.rotation ?? 0;
  return box;
}

function createHedge(entity: EntitySpec, palette: Palette): THREE.Group {
  const hedge = new THREE.Group();
  hedge.userData = { category: 'vegetation', id: entity.id };
  const size = (entity.size as number[]) ?? [3.4, 0.9, 0.75];
  const base = new THREE.Mesh(
    new THREE.BoxGeometry(size[0], size[1], size[2], 4, 3, 4),
    clayMat(hex(palette.foliage1), { roughness: 0.92 }),
  );
  base.position.y = size[1] / 2;
  base.castShadow = true;
  base.receiveShadow = true;
  hedge.add(base);
  for (let i = 0; i < 6; i += 1) {
    const blob = new THREE.Mesh(
      new THREE.SphereGeometry(0.28, 10, 8),
      clayMat(hex(palette.foliage2), { roughness: 0.95 }),
    );
    blob.position.set(-size[0] / 2 + 0.3 + i * (size[0] - 0.6) / 5, size[1] + 0.05, 0);
    blob.scale.y = 0.7;
    hedge.add(blob);
  }
  hedge.position.set(entity.position[0], entity.position[1], entity.position[2]);
  return hedge;
}

function createLampPost(entity: EntitySpec, palette: Palette): THREE.Group {
  const lp = new THREE.Group();
  lp.userData = { category: 'prop', id: entity.id };

  const pole = new THREE.Mesh(
    new THREE.CylinderGeometry(0.04, 0.05, 2.0, 8),
    clayMat(hex(palette.warmWhiteR)),
  );
  pole.position.y = 1.0;
  lp.add(pole);

  const head = new THREE.Mesh(
    new THREE.SphereGeometry(0.12, 10, 8),
    clayMat(hex(palette.yellow)),
  );
  head.position.y = 2.1;
  head.castShadow = true;
  lp.add(head);

  lp.position.set(entity.position[0], entity.position[1], entity.position[2]);
  return lp;
}

function createFlowerBed(entity: EntitySpec, palette: Palette): THREE.Group {
  const bed = new THREE.Group();
  bed.userData = { category: 'prop', id: entity.id };

  const w = (entity.size as number[])?.[0] ?? 1.5;
  const d = (entity.size as number[])?.[1] ?? 0.6;

  const border = new THREE.Mesh(
    new THREE.BoxGeometry(w, 0.12, d),
    clayMat(hex(palette.warmWhiteR)),
  );
  border.position.y = 0.06;
  border.receiveShadow = true;
  bed.add(border);

  const soil = new THREE.Mesh(
    new THREE.BoxGeometry(w - 0.1, 0.08, d - 0.1),
    clayMat(hex(palette.trunk), { roughness: 0.95 }),
  );
  soil.position.y = 0.08;
  bed.add(soil);

  const flowerColors = [hex(palette.orange), hex(palette.yellow), hex(palette.lime)];
  for (let i = 0; i < 5; i++) {
    const flower = new THREE.Mesh(
      new THREE.SphereGeometry(0.08, 8, 6),
      clayMat(flowerColors[i % 3]),
    );
    flower.position.set(
      (Math.random() - 0.5) * (w - 0.3),
      0.18,
      (Math.random() - 0.5) * (d - 0.3),
    );
    flower.castShadow = true;
    bed.add(flower);
  }

  bed.position.set(entity.position[0], entity.position[1], entity.position[2]);
  return bed;
}

// ── Cube ─────────────────────────────────────────────────────

function createCube(entity: EntitySpec, palette: Palette): THREE.Group {
  const group = new THREE.Group();
  group.userData = { category: 'prop', id: entity.id };

  const w = (entity.size as number[])?.[0] ?? 1;
  const h = (entity.size as number[])?.[1] ?? 1;
  const d = (entity.size as number[])?.[2] ?? 1;

  // Resolve material color: if entity has a material.color, use it;
  // otherwise fall back to palette lookup or default warmWhite.
  const mat = entity.material as unknown as Record<string, unknown> | undefined;
  const matColor = mat?.color
    ? hex(mat.color as string)
    : hex(palette.warmWhite);

  const mesh = new THREE.Mesh(
    new THREE.BoxGeometry(w, h, d, 2, 2, 2),
    clayMat(matColor, {
      roughness: (mat?.roughness as number) ?? 0.52,
      metalness: (mat?.metalness as number) ?? 0,
    }),
  );
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  group.add(mesh);

  group.position.set(entity.position[0], entity.position[1], entity.position[2]);
  group.rotation.y = entity.rotation ?? 0;
  return group;
}

// ── Dispatch ──────────────────────────────────────────────────

export type EntityBuilder = (entity: EntitySpec, palette: Palette) => THREE.Group;

const builders: Record<string, EntityBuilder> = {
  building: createBuilding,
  tree: createTree,
  character: createCharacter,
  bench: createBench,
  streetSign: createStreetSign,
  bicycle: createBicycle,
  moped: createMoped,
  utilityBox: createUtilityBox,
  hedge: createHedge,
  lampPost: createLampPost,
  flowerBed: createFlowerBed,
  cube: createCube,
};

export function buildEntity(entity: EntitySpec, palette: Palette): THREE.Group | null {
  const builder = builders[entity.type];
  if (!builder) {
    console.warn(`Unknown entity type: ${entity.type}`);
    return null;
  }
  return builder(entity, palette);
}
