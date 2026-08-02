import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type {
  SceneFixture,
  Palette,
  TemporalAnchorState,
  TemporalEntityState,
  InterpolatedState,
  InterpolatedEntityState,
  EntitySpec,
} from '@fumira/contracts';
import { buildEntity, clayMat } from '@fumira/clay-builders';

export { clayMat } from '@fumira/clay-builders';

function hex(color: string): number {
  return parseInt(color.replace('#', ''), 16);
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function clamp01(t: number): number {
  return Math.max(0, Math.min(1, t));
}

// ── Temporal interpolation ────────────────────────────────────

export function getInterpolatedState(year: number, fixture: SceneFixture): InterpolatedState {
  const anchors = fixture.temporalSpec.anchorYears;
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

// ── Scene creation ────────────────────────────────────────────

export interface SceneHandle {
  renderer: THREE.WebGLRenderer;
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  controls: OrbitControls;
  key: THREE.DirectionalLight;
  ground: THREE.Mesh;
  grassMeshes: THREE.Mesh[];
}

export function createScene(fixture: SceneFixture, canvas: HTMLCanvasElement): SceneHandle {
  const palette = fixture.palette;

  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.VSMShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.1;
  renderer.setClearColor(hex(fixture.style.clearColor));

  const scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(hex(fixture.style.fog.color), fixture.style.fog.density);

  const camera = new THREE.PerspectiveCamera(
    fixture.camera?.fov ?? 38,
    window.innerWidth / window.innerHeight,
    0.1,
    100,
  );
  const cameraPosition = fixture.camera?.position ?? [5.5, 4.8, 6.2];
  const cameraTarget = fixture.camera?.target ?? [0, 0.6, 0];
  camera.position.set(cameraPosition[0], cameraPosition[1], cameraPosition[2]);

  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.dampingFactor = 0.06;
  controls.minDistance = 3;
  controls.maxDistance = 16;
  controls.maxPolarAngle = Math.PI * 0.48;
  controls.target.set(cameraTarget[0], cameraTarget[1], cameraTarget[2]);
  controls.update();

  // Lighting
  const ambient = new THREE.AmbientLight(hex(palette.warmWhite), 0.35);
  scene.add(ambient);

  const key = new THREE.DirectionalLight(0xFFF5E8, 1.4);
  key.position.set(4, 8, 3);
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 2048);
  key.shadow.camera.near = 0.5;
  key.shadow.camera.far = 25;
  key.shadow.camera.left = -8;
  key.shadow.camera.right = 8;
  key.shadow.camera.top = 8;
  key.shadow.camera.bottom = -8;
  key.shadow.radius = 4;
  scene.add(key);

  const fill = new THREE.DirectionalLight(hex(palette.warmWhite), 0.3);
  fill.position.set(-3, 4, -2);
  scene.add(fill);

  // Ground
  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(60, 60),
    clayMat(hex(palette.charcoal), { roughness: 1 }),
  );
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = -0.52;
  ground.receiveShadow = true;
  scene.add(ground);

  // Grid
  const gridSize = 20;
  const gridDiv = 20;
  const gridGeo = new THREE.PlaneGeometry(gridSize, gridSize, gridDiv, gridDiv);
  const gridMat = new THREE.MeshBasicMaterial({
    color: hex(palette.charcoal),
    wireframe: true,
    transparent: true,
    opacity: 0.03,
  });
  const gridMesh = new THREE.Mesh(gridGeo, gridMat);
  gridMesh.rotation.x = -Math.PI / 2;
  gridMesh.position.y = -0.51;
  scene.add(gridMesh);

  // Grass meshes (for temporal color changes)
  const grassMeshes: THREE.Mesh[] = [];

  return { renderer, scene, camera, controls, key, ground, grassMeshes };
}

// ── Entity loading ────────────────────────────────────────────

export interface EntityHandle {
  id: string;
  category: string;
  type: string;
  group: THREE.Group;
  spec: EntitySpec;
}

export function loadEntities(
  fixture: SceneFixture,
  scene: THREE.Scene,
  sceneHandle: SceneHandle,
): EntityHandle[] {
  const entities: EntityHandle[] = [];
  const palette = fixture.palette;

  for (const entitySpec of fixture.entities) {
    // Skip ground/base/road — handled by createScene infrastructure
    if (entitySpec.type === 'ground') continue;

    // Special: road + infrastructure
    if (entitySpec.type === 'road') {
      const roadGroup = buildRoadInfrastructure(entitySpec, palette);
      scene.add(roadGroup);
      // Extract grass meshes
      roadGroup.children.forEach(child => {
        if (child instanceof THREE.Mesh && child.userData.isGrass) {
          sceneHandle.grassMeshes.push(child);
        }
      });
      continue;
    }

    if (entitySpec.type === 'base') {
      const baseGroup = buildBase(entitySpec, palette);
      scene.add(baseGroup);
      continue;
    }

    const group = buildEntity(entitySpec, palette);
    if (!group) continue;

    scene.add(group);
    entities.push({
      id: entitySpec.id,
      category: entitySpec.category,
      type: entitySpec.type,
      group,
      spec: entitySpec,
    });
  }

  return entities;
}

function buildBase(entity: EntitySpec, palette: Palette): THREE.Group {
  const group = new THREE.Group();
  const w = (entity.size as number[])?.[0] ?? 7;
  const d = (entity.size as number[])?.[1] ?? 7;
  const h = (entity.size as number[])?.[2] ?? 0.5;

  const baseBody = new THREE.Mesh(
    new THREE.BoxGeometry(w, h, d, 4, 2, 4),
    clayMat(hex(palette.warmWhiteR)),
  );
  baseBody.position.y = -h / 2;
  baseBody.castShadow = true;
  baseBody.receiveShadow = true;
  group.add(baseBody);

  const baseTop = new THREE.Mesh(
    new THREE.BoxGeometry(w - 0.08, 0.06, d - 0.08, 4, 1, 4),
    clayMat(hex(palette.warmWhite)),
  );
  baseTop.position.y = 0.03;
  baseTop.receiveShadow = true;
  group.add(baseTop);

  return group;
}

function buildRoadInfrastructure(entity: EntitySpec, palette: Palette): THREE.Group {
  const group = new THREE.Group();
  const w = (entity.size as number[])?.[0] ?? 6.4;
  const d = (entity.size as number[])?.[2] ?? 2.2;
  const baseW = 7;

  const road = new THREE.Mesh(
    new THREE.BoxGeometry(w, 0.04, d),
    clayMat(hex(palette.road)),
  );
  road.position.set(0, 0.06, 0);
  road.receiveShadow = true;
  group.add(road);

  // Dashes
  for (let i = -3; i <= 3; i += 1.2) {
    const dash = new THREE.Mesh(
      new THREE.BoxGeometry(0.5, 0.045, 0.08),
      clayMat(hex(palette.yellow)),
    );
    dash.position.set(i, 0.07, 0);
    group.add(dash);
  }

  // Sidewalks
  const sidewalks = (entity.sidewalks as Array<{ position: number[]; size: number[] }>) ?? [];
  for (const sw of sidewalks) {
    const mesh = new THREE.Mesh(
      new THREE.BoxGeometry(sw.size[0], sw.size[1], sw.size[2]),
      clayMat(hex(palette.sidewalk)),
    );
    mesh.position.set(sw.position[0], sw.position[1], sw.position[2]);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    group.add(mesh);
  }

  // Grass
  const grassSpecs = (entity.grass as Array<{ position: number[]; size: number[] }>) ?? [];
  for (const g of grassSpecs) {
    const mesh = new THREE.Mesh(
      new THREE.BoxGeometry(g.size[0], g.size[1], g.size[2]),
      clayMat(hex(palette.grass)),
    );
    mesh.position.set(g.position[0], g.position[1], g.position[2]);
    mesh.receiveShadow = true;
    mesh.userData.isGrass = true;
    group.add(mesh);
  }

  return group;
}

// ── Apply temporal state ──────────────────────────────────────

export function applyTemporalState(
  year: number,
  fixture: SceneFixture,
  entities: EntityHandle[],
  sceneHandle: SceneHandle,
): void {
  const { states } = getInterpolatedState(year, fixture);
  const palette = fixture.palette;
  const seasonCycle = ((year % 1) + 1) % 1;

  // Building
  const bs = states.gate_01;
  if (bs) {
    const building = entities.find(e => e.id === 'gate_01');
    if (building) {
      const w = bs.weathering || 0;
      building.group.children.forEach(child => {
        if (child instanceof THREE.Mesh && child.material instanceof THREE.MeshStandardMaterial) {
          if (child.material.userData?.baseColor) {
            child.material.color.copy(
              child.material.userData.baseColor.clone().lerp(new THREE.Color(hex(palette.warmWhiteR)), w),
            );
          }
        }
      });
    }
  }

  // Trees
  const treeEntities = entities.filter(e => e.category === 'vegetation');
  treeEntities.forEach((treeHandle, i) => {
    const ts = states[`tree_0${i + 1}`];
    if (!ts) return;
    const g = ts.growth || 1;
    const cv = ts.crownVolume || 1;

    treeHandle.group.children.forEach(child => {
      if (child instanceof THREE.Mesh) {
        if (child.geometry?.type === 'CylinderGeometry') {
          child.scale.set(g, g, g);
        } else if (child.geometry?.type === 'SphereGeometry') {
          child.scale.setScalar(g * cv);
          const mat = child.material as THREE.MeshStandardMaterial;
          const base = mat.userData?.baseColor || new THREE.Color(hex(palette.foliage2));
          const autumn = new THREE.Color(hex(palette.yellowRim));
          const winter = new THREE.Color(hex(palette.warmWhiteR));
          let c: THREE.Color;
          if (seasonCycle < 0.25) c = base.clone().lerp(winter, seasonCycle * 4);
          else if (seasonCycle < 0.5) c = winter.clone().lerp(base, (seasonCycle - 0.25) * 4);
          else if (seasonCycle < 0.75) c = base.clone().lerp(autumn, (seasonCycle - 0.5) * 4);
          else c = autumn.clone().lerp(winter, (seasonCycle - 0.75) * 4);
          mat.color.copy(c);
        }
      }
    });
  });

  // Characters
  const charEntities = entities.filter(e => e.category === 'character');
  charEntities.forEach((charHandle, i) => {
    const ps = states[`person_0${i + 1}`];
    if (!ps) return;
    charHandle.group.visible = (ps.presence || 0) > 0.1;
    if (!charHandle.group.visible) return;
    charHandle.group.scale.setScalar(ps.height || 1.0);
    const origPos = charHandle.spec.position;
    const off = ps.positionOffset || [0, 0, 0];
    charHandle.group.position.x = origPos[0] + off[0];
    charHandle.group.position.z = origPos[2] + off[2];
  });

  // Light color
  const warm = new THREE.Color(0xFFF5E8);
  const cool = new THREE.Color(0xE8F0FF);
  const sw = 0.5 + 0.5 * Math.sin(seasonCycle * Math.PI * 2);
  sceneHandle.key.color.copy(cool.clone().lerp(warm, sw));
  sceneHandle.key.intensity = lerp(1.0, 1.5, sw);

  // Grass
  const grassGreen = new THREE.Color(hex(palette.grass));
  const grassAutumn = new THREE.Color(hex(palette.yellowRim));
  const ss = (Math.sin(seasonCycle * Math.PI * 2) + 1) / 2 * 0.4;
  const gt = grassGreen.clone().lerp(grassAutumn, ss);
  sceneHandle.grassMeshes.forEach(mesh => {
    (mesh.material as THREE.MeshStandardMaterial).color.copy(gt);
  });
}

// ── Animation ─────────────────────────────────────────────────

export interface AnimationCallbacks {
  onUpdateUI?: (year: number) => void;
}

export interface AnimationController {
  setYear(year: number): void;
  getYear(): number;
  dispose(): void;
}

export function startAnimationLoop(
  sceneHandle: SceneHandle,
  entities: EntityHandle[],
  fixture: SceneFixture,
  callbacks: AnimationCallbacks = {},
): AnimationController {
  const clock = new THREE.Clock();
  let lastInteraction = 0;
  let currentYear = 2026;
  let running = true;

  const canvas = sceneHandle.renderer.domElement;
  canvas.addEventListener('pointerdown', () => { lastInteraction = performance.now(); });
  canvas.addEventListener('wheel', () => { lastInteraction = performance.now(); });

  // Init temporal state
  applyTemporalState(currentYear, fixture, entities, sceneHandle);
  callbacks.onUpdateUI?.(currentYear);

  const charEntities = entities.filter(e => e.category === 'character');
  const treeEntities = entities.filter(e => e.category === 'vegetation');

  function animate() {
    if (!running) return;
    requestAnimationFrame(animate);

    const t = clock.getElapsedTime();
    const idle = (performance.now() - lastInteraction) / 1000;
    sceneHandle.controls.autoRotate = idle > 5;
    sceneHandle.controls.autoRotateSpeed = 0.4;
    sceneHandle.controls.update();

    // Idle sway for characters
    charEntities.forEach((p, i) => {
      if (p.group.visible) {
        p.group.children.forEach(c => {
          if (c instanceof THREE.Mesh && c.geometry?.type === 'CapsuleGeometry' && c.position.y > 0.3) {
            c.rotation.z += Math.sin(t * 1.5 + i) * 0.0003;
          }
        });
      }
    });

    // Idle sway for trees
    treeEntities.forEach((tree, i) => {
      tree.group.children.forEach(c => {
        if (c instanceof THREE.Mesh && c.geometry?.type === 'SphereGeometry') {
          c.position.x += Math.sin(t * 0.8 + i * 1.5) * 0.0002;
          c.position.z += Math.cos(t * 0.6 + i * 2) * 0.0001;
        }
      });
    });

    sceneHandle.renderer.render(sceneHandle.scene, sceneHandle.camera);
  }

  animate();

  // Resize handler
  const onResize = () => {
    sceneHandle.camera.aspect = window.innerWidth / window.innerHeight;
    sceneHandle.camera.updateProjectionMatrix();
    sceneHandle.renderer.setSize(window.innerWidth, window.innerHeight);
  };
  window.addEventListener('resize', onResize);

  // Public API
  return {
    setYear(year: number) {
      currentYear = year;
      applyTemporalState(year, fixture, entities, sceneHandle);
      callbacks.onUpdateUI?.(year);
    },
    getYear() {
      return currentYear;
    },
    dispose() {
      running = false;
      window.removeEventListener('resize', onResize);
      sceneHandle.renderer.dispose();
    },
  };
}
