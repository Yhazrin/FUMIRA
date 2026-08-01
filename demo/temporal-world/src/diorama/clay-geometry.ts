// diorama/clay-geometry.ts — Beveled & organic geometry builders for the Diorama.
// Every shape has proper rounded edges — no raw BoxGeometry anywhere.
// All randomness is deterministic via seeded PRNG — never Math.random.
//
// Geometry catalog:
//   createBeveledBox       — buildings, vehicles, props (ExtrudeGeometry + rounded rect)
//   createBeveledCylinder  — columns, podiums, barrels (LatheGeometry + beveled profile)
//   createOrganicBlob      — trees, foliage (IcosahedronGeometry + simplex noise)
//   createGroundPlane      — scene base (subdivided plane + noise + edge rounding)
//   createRoad             — paths, streets (ExtrudeGeometry along curved path)

import * as THREE from 'three';
import { mulberry32 } from './clay-materials';

// ═══════════════════════════════════════════════════════════════════════════════
// Seed helpers
// ═══════════════════════════════════════════════════════════════════════════════

/** Combine multiple numbers into a single deterministic seed. */
function hashSeed(...args: number[]): number {
  let h = 0x811c9dc5; // FNV-1a offset basis
  for (const a of args) {
    const n = (a * 2654435761) | 0; // Knuth multiplicative hash
    h = Math.imul(h ^ (n & 0xff), 0x01000193);
    h = Math.imul(h ^ ((n >>> 8) & 0xff), 0x01000193);
    h = Math.imul(h ^ ((n >>> 16) & 0xff), 0x01000193);
    h = Math.imul(h ^ ((n >>> 24) & 0xff), 0x01000193);
  }
  return h | 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3D Simplex Noise — seeded permutation table via mulberry32
// Based on the Stefan Gustavson / Ken Perlin reference implementation.
// Returns values in approximately [-1, 1].
// ═══════════════════════════════════════════════════════════════════════════════

function createNoise3D(seed: number): (x: number, y: number, z: number) => number {
  const rand = mulberry32(seed);

  // 12 gradient directions for 3D simplex noise
  const grad3: ReadonlyArray<readonly number[]> = [
    [1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0],
    [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
    [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1],
  ];

  // Build permutation table (seeded Fisher-Yates shuffle)
  const p = new Uint8Array(256);
  for (let i = 0; i < 256; i++) p[i] = i;
  for (let i = 255; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    const tmp = p[i]; p[i] = p[j]; p[j] = tmp;
  }

  // Duplicate to avoid modulo in the hot loop
  const perm = new Uint8Array(512);
  const permMod12 = new Uint8Array(512);
  for (let i = 0; i < 512; i++) {
    perm[i] = p[i & 255];
    permMod12[i] = perm[i] % 12;
  }

  // Skewing / unskewing constants
  const F3 = 1.0 / 3.0;
  const G3 = 1.0 / 6.0;

  function dot3(g: readonly number[], x: number, y: number, z: number): number {
    return g[0] * x + g[1] * y + g[2] * z;
  }

  return (xin: number, yin: number, zin: number): number => {
    // Skew the input space to determine which simplex we're in
    const s = (xin + yin + zin) * F3;
    const i = Math.floor(xin + s);
    const j = Math.floor(yin + s);
    const k = Math.floor(zin + s);

    const t = (i + j + k) * G3;
    const x0 = xin - (i - t);
    const y0 = yin - (j - t);
    const z0 = zin - (k - t);

    // Determine which simplex we are in
    let i1: number, j1: number, k1: number; // second corner
    let i2: number, j2: number, k2: number; // third corner

    if (x0 >= y0) {
      if (y0 >= z0) {
        i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0; // XYZ
      } else if (x0 >= z0) {
        i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1; // XZY
      } else {
        i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1; // ZXY
      }
    } else {
      if (y0 < z0) {
        i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1; // ZYX
      } else if (x0 < z0) {
        i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1; // YZX
      } else {
        i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0; // YXZ
      }
    }

    // Offsets for corners
    const x1 = x0 - i1 + G3;
    const y1 = y0 - j1 + G3;
    const z1 = z0 - k1 + G3;
    const x2 = x0 - i2 + 2.0 * G3;
    const y2 = y0 - j2 + 2.0 * G3;
    const z2 = z0 - k2 + 2.0 * G3;
    const x3 = x0 - 1.0 + 3.0 * G3;
    const y3 = y0 - 1.0 + 3.0 * G3;
    const z3 = z0 - 1.0 + 3.0 * G3;

    // Hash coordinates of the four corners
    const ii = i & 255;
    const jj = j & 255;
    const kk = k & 255;

    const gi0 = permMod12[ii + perm[jj + perm[kk]]];
    const gi1 = permMod12[ii + i1 + perm[jj + j1 + perm[kk + k1]]];
    const gi2 = permMod12[ii + i2 + perm[jj + j2 + perm[kk + k2]]];
    const gi3 = permMod12[ii + 1 + perm[jj + 1 + perm[kk + 1]]];

    // Corner contributions
    let n0 = 0, n1 = 0, n2 = 0, n3 = 0;

    let t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0;
    if (t0 >= 0) { t0 *= t0; n0 = t0 * t0 * dot3(grad3[gi0], x0, y0, z0); }

    let t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1;
    if (t1 >= 0) { t1 *= t1; n1 = t1 * t1 * dot3(grad3[gi1], x1, y1, z1); }

    let t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2;
    if (t2 >= 0) { t2 *= t2; n2 = t2 * t2 * dot3(grad3[gi2], x2, y2, z2); }

    let t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3;
    if (t3 >= 0) { t3 *= t3; n3 = t3 * t3 * dot3(grad3[gi3], x3, y3, z3); }

    // Scale to [-1, 1]
    return 32.0 * (n0 + n1 + n2 + n3);
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/** Hermite smoothstep interpolation. */
function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = Math.max(0, Math.min(1, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

/**
 * Create a 2D rounded rectangle THREE.Shape centered on the origin.
 * The shape lies in the XY plane: width along X, height along Y.
 */
function createRoundedRectShape(
  width: number,
  height: number,
  radius: number,
): THREE.Shape {
  const hw = width / 2;
  const hh = height / 2;
  // Clamp radius so it never exceeds half the shortest side
  const r = Math.min(radius, hw, hh);

  const shape = new THREE.Shape();

  if (r <= 0.0001) {
    // Degenerate: sharp rectangle
    shape.moveTo(-hw, -hh);
    shape.lineTo(hw, -hh);
    shape.lineTo(hw, hh);
    shape.lineTo(-hw, hh);
    shape.closePath();
    return shape;
  }

  // Start at bottom-left, going clockwise
  shape.moveTo(-hw + r, -hh);
  shape.lineTo(hw - r, -hh);
  shape.quadraticCurveTo(hw, -hh, hw, -hh + r);
  shape.lineTo(hw, hh - r);
  shape.quadraticCurveTo(hw, hh, hw - r, hh);
  shape.lineTo(-hw + r, hh);
  shape.quadraticCurveTo(-hw, hh, -hw, hh - r);
  shape.lineTo(-hw, -hh + r);
  shape.quadraticCurveTo(-hw, -hh, -hw + r, -hh);

  return shape;
}

/**
 * Sample points along a quarter-circle arc for bevel profiles.
 * Angles in radians. Returns segments+1 points (including endpoints).
 */
function quarterArcPoints(
  cx: number,
  cy: number,
  radius: number,
  startAngle: number,
  endAngle: number,
  segments: number,
): THREE.Vector2[] {
  const points: THREE.Vector2[] = [];
  for (let i = 0; i <= segments; i++) {
    const t = i / segments;
    const angle = startAngle + (endAngle - startAngle) * t;
    points.push(new THREE.Vector2(
      cx + radius * Math.cos(angle),
      cy + radius * Math.sin(angle),
    ));
  }
  return points;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 1. createBeveledBox
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Beveled box — the workhorse geometry for buildings, vehicles, and props.
 *
 * Creates a rounded rectangle cross-section (width x depth) and extrudes it
 * along the Y axis with bevel enabled.  Every edge of the resulting box is
 * smoothly chamfered — no sharp 90-degree corners anywhere.
 *
 * @param w Width  (X axis)
 * @param h Height (Y axis)
 * @param d Depth  (Z axis)
 * @param bevelRadius Desired bevel radius — clamped to min(w, h) * 0.1 and a floor of 0.02.
 * @param segments  Number of bevel segments (3 gives a smooth chamfer without excess polys).
 */
export function createBeveledBox(
  w: number,
  h: number,
  d: number,
  bevelRadius: number,
  segments: number = 3,
): THREE.BufferGeometry {
  // Bevel must be at least 0.02 (clay softness floor) and at most min(w,h) * 0.1
  const maxBevel = Math.min(w, h) * 0.1;
  const clampedBevel = Math.max(0.02, Math.min(bevelRadius, maxBevel));
  const segs = Math.max(1, Math.round(segments));

  // Cross-section: rounded rectangle in the XZ plane (width x depth)
  const shape = createRoundedRectShape(w, d, clampedBevel);

  // Extrude along Z, then rotate so extrusion goes along Y (height)
  const geom = new THREE.ExtrudeGeometry(shape, {
    depth: h,
    bevelEnabled: true,
    bevelThickness: clampedBevel,
    bevelSize: clampedBevel,
    bevelSegments: segs,
    curveSegments: segs * 2,
  });

  // Rotate so that the extrusion direction becomes Y (height axis).
  // Before: shape in XY, extruded along +Z.
  // After rotateX(-PI/2): X stays, Z becomes -Y, Y becomes Z → extrusion along -Y.
  // Then translate to center vertically.
  geom.rotateX(-Math.PI / 2);

  // Center the geometry on all three axes
  geom.computeBoundingBox();
  const center = new THREE.Vector3();
  geom.boundingBox!.getCenter(center);
  geom.translate(-center.x, -center.y, -center.z);

  return geom;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2. createBeveledCylinder
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Beveled cylinder with smooth edge transitions at top and bottom.
 *
 * Uses LatheGeometry with a hand-built profile that includes:
 *   - flat bottom face   (from center to edge)
 *   - quarter-circle bevel at the bottom rim
 *   - tapered side wall  (straight line from radiusBottom to radiusTop)
 *   - quarter-circle bevel at the top rim
 *   - flat top face      (from edge to center)
 *
 * This produces a solid, closed cylinder with rounded edges, suitable for
 * podiums, barrels, columns, and cylindrical building elements.
 *
 * @param radiusTop     Top radius.
 * @param radiusBottom  Bottom radius (set equal to radiusTop for uniform cylinder).
 * @param height        Total height.
 * @param segments      Circumferential segments (minimum 8 for smoothness).
 * @param bevelRadius   Edge bevel radius — clamped to 0.02 minimum.
 */
export function createBeveledCylinder(
  radiusTop: number,
  radiusBottom: number,
  height: number,
  segments: number,
  bevelRadius: number,
): THREE.BufferGeometry {
  const rt = Math.max(0.001, radiusTop);
  const rb = Math.max(0.001, radiusBottom);
  const h = Math.max(0.001, height);
  const segs = Math.max(8, Math.round(segments));

  // Bevel must fit within the geometry: no larger than the smallest radius or half-height
  const b = Math.max(0.02, Math.min(bevelRadius, Math.min(rt, rb, h / 2) * 0.4));
  const bevelSegs = 4; // quarter-circle resolution

  // Build the 2D profile (Vector2: x = radius, y = height)
  const profile: THREE.Vector2[] = [];

  // 1. Bottom center → bottom face edge (before bevel)
  profile.push(new THREE.Vector2(0, 0));
  profile.push(new THREE.Vector2(rb - b, 0));

  // 2. Bottom bevel: quarter-circle from (rb-b, 0) to (rb, b)
  //    Center of arc: (rb-b, b), radius = b, angle: -PI/2 → 0
  const bottomArc = quarterArcPoints(rb - b, b, b, -Math.PI / 2, 0, bevelSegs);
  // Skip the first point (it equals the last pushed point)
  for (let i = 1; i < bottomArc.length; i++) {
    profile.push(bottomArc[i]);
  }

  // 3. Side wall: straight line from (rb, b) to (rt, h - b)
  //    Add intermediate points for tapered geometry
  const wallSteps = Math.abs(rt - rb) > 0.001 ? 4 : 1;
  for (let i = 1; i <= wallSteps; i++) {
    const t = i / wallSteps;
    const r = rb + (rt - rb) * t;
    const y = b + (h - 2 * b) * t;
    profile.push(new THREE.Vector2(r, y));
  }

  // 4. Top bevel: quarter-circle from (rt, h-b) to (rt-b, h)
  //    Center of arc: (rt-b, h-b), radius = b, angle: 0 → PI/2
  const topArc = quarterArcPoints(rt - b, h - b, b, 0, Math.PI / 2, bevelSegs);
  for (let i = 1; i < topArc.length; i++) {
    profile.push(topArc[i]);
  }

  // 5. Top face edge → top center
  profile.push(new THREE.Vector2(rt - b, h));
  profile.push(new THREE.Vector2(0, h));

  // Create the surface of revolution
  const geom = new THREE.LatheGeometry(profile, segs);

  // Center vertically
  geom.translate(0, -h / 2, 0);

  return geom;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. createOrganicBlob
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Organic blob shape for trees, bushes, and foliage.
 *
 * Starts with an IcosahedronGeometry (even vertex distribution) and
 * displaces each vertex outward using multi-octave 3D simplex noise.
 * The result is a lumpy, natural-looking solid.
 *
 * Deterministic: same seed always produces the same shape.
 *
 * @param radius  Base radius before noise displacement.
 * @param squash  0 = sphere, 1 = fully flattened pancake along Y.
 * @param seed    Deterministic seed for the PRNG and noise.
 * @param detail  Icosahedron subdivision level (1–5). Higher = smoother blob, more polys.
 */
export function createOrganicBlob(
  radius: number,
  squash: number,
  seed: number,
  detail: number,
): THREE.BufferGeometry {
  const r = Math.max(0.001, radius);
  const detailLevel = Math.max(1, Math.min(5, Math.round(detail)));
  const clamp = Math.max(0, Math.min(1, squash));

  // IcosahedronGeometry gives even vertex distribution — better for noise displacement
  const geom = new THREE.IcosahedronGeometry(r, detailLevel);

  // Create two noise functions at different seeds for multi-octave displacement
  const noise1 = createNoise3D(seed);
  const noise2 = createNoise3D(hashSeed(seed, 0x9e3779b9));

  const pos = geom.attributes.position;
  const vertex = new THREE.Vector3();

  for (let i = 0; i < pos.count; i++) {
    vertex.fromBufferAttribute(pos, i);

    // First octave: large features
    const n1 = noise1(
      vertex.x * 2.0,
      vertex.y * 2.0,
      vertex.z * 2.0,
    ) * 0.18;

    // Second octave: fine detail
    const n2 = noise2(
      vertex.x * 4.5 + 17.3,
      vertex.y * 4.5 + 31.7,
      vertex.z * 4.5 + 47.1,
    ) * 0.07;

    // Displace outward from center
    const displacement = 1.0 + n1 + n2;
    vertex.x *= displacement;
    vertex.y *= displacement;
    vertex.z *= displacement;

    // Squash along Y: 0 = no effect, 1 = pancake
    if (clamp > 0.001) {
      vertex.y *= 1.0 - clamp * 0.65;
    }

    pos.setXYZ(i, vertex.x, vertex.y, vertex.z);
  }

  geom.computeVertexNormals();
  return geom;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4. createGroundPlane
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Ground plane for the diorama base.
 *
 * Creates a subdivided horizontal plane with:
 *   - subtle height variation from seeded simplex noise
 *   - soft edge rounding via smooth vertex falloff (edges taper to flat)
 *
 * The edge rounding is achieved by blending out noise displacement near
 * the perimeter using a smoothstep falloff — this avoids sharp edges at
 * the boundary while keeping the geometry a single clean mesh.
 *
 * @param width        Total width (X axis).
 * @param depth        Total depth (Z axis).
 * @param subdivisions Grid subdivisions per side (minimum 4 for visible noise).
 */
export function createGroundPlane(
  width: number,
  depth: number,
  subdivisions: number,
): THREE.BufferGeometry {
  const w = Math.max(0.1, width);
  const d = Math.max(0.1, depth);
  const segs = Math.max(4, Math.round(subdivisions));

  // Deterministic seed from parameters
  const seed = hashSeed(w * 1000 | 0, d * 7919 | 0, segs * 104729 | 0);
  const noise = createNoise3D(seed);
  const noise2 = createNoise3D(hashSeed(seed, 0x517cc1b7));

  // Create the subdivided plane
  const geom = new THREE.PlaneGeometry(w, d, segs, segs);

  // Rotate to horizontal: plane is initially in XY, we want XZ
  geom.rotateX(-Math.PI / 2);

  const pos = geom.attributes.position;
  const hw = w / 2;
  const hd = d / 2;

  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const z = pos.getZ(i);

    // Normalized distance from center (0 at center, 1 at edge)
    const nx = Math.abs(x) / hw;
    const nz = Math.abs(z) / hd;
    const edgeDist = Math.max(nx, nz);

    // Smooth falloff: full noise in center, fading to flat at edges
    // The 0.65 threshold means the outer 35% of the plane smoothly tapers
    const falloff = 1.0 - smoothstep(0.55, 1.0, edgeDist);

    // Two octaves of noise for natural terrain variation
    const h1 = noise(x * 1.8, z * 1.8, 0.5) * 0.025;
    const h2 = noise2(x * 4.0 + 50, z * 4.0 + 50, 1.0) * 0.008;

    // Apply displacement with edge falloff
    pos.setY(i, (h1 + h2) * falloff);
  }

  geom.computeVertexNormals();
  return geom;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 5. createRoad
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Road geometry — extruded rounded rectangle along a curved path.
 *
 * The cross-section is a thin rounded rectangle (the road surface), extruded
 * along a CatmullRomCurve3 path that bends based on the `curve` parameter.
 * The road is slightly raised above y=0.
 *
 * @param width       Road width (perpendicular to travel direction).
 * @param length      Road length along the path.
 * @param curve       Lateral curvature: 0 = straight, positive = curves right, negative = left.
 * @param bevelRadius Edge rounding radius for the cross-section (clamped to 0.02 minimum).
 */
export function createRoad(
  width: number,
  length: number,
  curve: number,
  bevelRadius: number,
): THREE.BufferGeometry {
  const w = Math.max(0.05, width);
  const len = Math.max(0.1, length);
  const clampedBevel = Math.max(0.02, Math.min(bevelRadius, Math.min(w, 0.04) * 0.5));

  // Road thickness: thin slab, at least enough to show the bevel
  const thickness = Math.max(clampedBevel * 2.5, 0.03);

  // Cross-section: thin rounded rectangle (width x thickness)
  // The shape's X axis = road width, Y axis = road thickness
  const crossSection = createRoundedRectShape(w, thickness, clampedBevel);

  // Build the path: a smooth curve through 3 control points
  const halfLen = len / 2;
  const yOffset = thickness / 2 + 0.005; // slightly raised above ground

  const pathPoints = [
    new THREE.Vector3(0, yOffset, -halfLen),
    new THREE.Vector3(curve, yOffset, 0),
    new THREE.Vector3(0, yOffset, halfLen),
  ];
  const path = new THREE.CatmullRomCurve3(pathPoints, false, 'catmullrom', 0.5);

  // Extrude the cross-section along the curved path
  const steps = Math.max(16, Math.round(len * 12));
  const geom = new THREE.ExtrudeGeometry(crossSection, {
    extrudePath: path,
    steps: steps,
    bevelEnabled: false, // cross-section already has rounded corners
  });

  return geom;
}
