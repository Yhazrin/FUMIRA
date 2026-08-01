import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

// ── RoundedBoxGeometry (beveled box for clay look) ─────────
// Minimal implementation — creates a box with rounded edges.
class RoundedBoxGeometry extends THREE.BufferGeometry {
  constructor(w = 1, h = 1, d = 1, segments = 2, radius = 0.1) {
    super();
    const hw = w/2, hh = h/2, hd = d/2;
    radius = Math.min(radius, hw, hh, hd);
    const shape = new THREE.Shape();
    const r = radius;
    shape.moveTo(-hw + r, -hh);
    shape.lineTo(hw - r, -hh);
    shape.quadraticCurveTo(hw, -hh, hw, -hh + r);
    shape.lineTo(hw, hh - r);
    shape.quadraticCurveTo(hw, hh, hw - r, hh);
    shape.lineTo(-hw + r, hh);
    shape.quadraticCurveTo(-hw, hh, -hw, hh - r);
    shape.lineTo(-hw, -hh + r);
    shape.quadraticCurveTo(-hw, -hh, -hw + r, -hh);

    const extrudeSettings = {
      steps: 1,
      depth: d - 2*r,
      bevelEnabled: true,
      bevelThickness: r,
      bevelSize: r,
      bevelOffset: 0,
      bevelSegments: segments,
    };
    const geo = new THREE.ExtrudeGeometry(shape, extrudeSettings);
    geo.translate(0, 0, -(d - 2*r)/2);

    // Copy to this geometry
    this.copy(geo);
  }
}

// ── Contact shadow helper ──────────────────────────────────
function addContactShadow(parent, radius, opacity = 0.1) {
  const geo = new THREE.CircleGeometry(radius, 20);
  const mat = new THREE.MeshBasicMaterial({
    color: 0x000000, transparent: true, opacity, depthWrite: false,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.rotation.x = -Math.PI / 2;
  mesh.position.y = 0.005;
  parent.add(mesh);
  return mesh;
}

// ── Config ─────────────────────────────────────────────────
const API_BASE = window.location.origin;
const WS_BASE = `ws://${window.location.host}`;

// ── Scene state machine ────────────────────────────────────
// States: 'waiting' | 'processing' | 'loaded' | 'error'
let sceneState = 'waiting';
let currentFixture = null;
let loadedEntities = [];
let grassMeshes = [];
let keyLight = null;
let timelineIntervals = [];

function setSceneState(state, detail) {
  sceneState = state;
  const statusEl = document.getElementById('scene-status');
  const pill = statusEl.querySelector('.status-pill');

  switch (state) {
    case 'waiting':
      statusEl.classList.remove('hidden');
      statusEl.classList.remove('error');
      pill.innerHTML = '<div class="status-dot-idle"></div><div class="status-text">Waiting for capture...</div>';
      break;
    case 'processing':
      statusEl.classList.remove('hidden');
      statusEl.classList.remove('error');
      pill.innerHTML = '<div class="pulse-dot"></div><div class="status-text">Processing scene...</div>';
      break;
    case 'loaded':
      statusEl.classList.add('hidden');
      break;
    case 'error':
      statusEl.classList.remove('hidden');
      statusEl.classList.add('error');
      pill.innerHTML = '<div class="pulse-dot"></div><div class="status-text">Error: ' + (detail?.message || 'Unknown error') + '</div>';
      break;
  }
}

// ── State ──────────────────────────────────────────────────
let sessionId = null;
let ws = null;
let isConnectedToMobile = false;

// ── Initialize Session ─────────────────────────────────────
async function initSession() {
  try {
    const res = await fetch(`${API_BASE}/api/session`);
    const data = await res.json();
    sessionId = data.sessionId;
    document.getElementById('session-id').textContent = sessionId;

    const mobileUrl = `${API_BASE}/mobile.html?session=${sessionId}`;
    const qrEl = document.getElementById('qr-code');
    QRCode.toCanvas(qrEl, mobileUrl, {
      width: 160, margin: 1,
      color: { dark: '#202425', light: '#FFFFFF' }
    });

    connectWebSocket();
    fetchSceneData(sessionId);
  } catch (e) {
    console.log('Running in standalone mode (no server)');
    document.getElementById('qr-panel').classList.add('hidden');
    setSceneState('waiting');
  }
}

async function fetchSceneData(sid) {
  setSceneState('processing');
  // Try per-session scene first, then fall back to global scene
  const urls = [`${API_BASE}/api/scene/${sid}`, `${API_BASE}/api/scene`];
  for (const url of urls) {
    try {
      const res = await fetch(url);
      if (res.status === 404) continue;
      if (!res.ok) continue;
      let data = await res.json();
      if (!data) continue;

      // Handle SceneRuntime manifest format (sceneGraph + entities object)
      // Convert to fixture format (entities array)
      if (data.sceneGraph && data.entities && !Array.isArray(data.entities)) {
        data = manifestToFixture(data);
      }

      if (!data.entities || data.entities.length === 0) continue;
      loadFixture(data);
      return;
    } catch { /* try next URL */ }
  }
  setSceneState('waiting');
}

// Convert SceneRuntime manifest → desktop fixture format
function manifestToFixture(manifest) {
  const nodesById = {};
  for (const node of (manifest.sceneGraph || [])) {
    nodesById[node.id] = node;
  }

  const entities = [];
  for (const [entityId, compiled] of Object.entries(manifest.entities || {})) {
    const node = nodesById[compiled.sceneNodeId] || {};
    const spec = compiled.spec || {};
    entities.push({
      id: entityId,
      type: spec.type || 'prop',
      label: spec.label || entityId,
      position: node.position || [0, 0, 0],
      rotation: node.rotation || [0, 0, 0],
      scale: node.scale || [1, 1, 1],
      geometry: {
        builder: node.geometry?.type || 'box',
        parameters: {
          width: node.geometry?.args?.[0] ?? 1,
          height: node.geometry?.args?.[1] ?? 1,
          depth: node.geometry?.args?.[2] ?? 1,
        },
      },
      material: node.material || { color: '#C4A882', roughness: 0.65 },
      confidence: 1.0,
    });
  }

  return {
    id: 'manifest-scene',
    name: 'Reconstructed Scene',
    entities,
    camera: manifest.defaultCamera,
    temporalSpec: manifest.temporalSpec,
    palette: {}, // use entity material colors directly
  };
}

let pollTimer = null;
function startPollingForScene() {
  if (pollTimer) return;
  pollTimer = setInterval(async () => {
    if (sceneState !== 'waiting') {
      clearInterval(pollTimer);
      pollTimer = null;
      return;
    }
    try {
      const res = await fetch(`${API_BASE}/api/scene/${sessionId}`);
      if (res.ok) {
        const fixture = await res.json();
        if (fixture && fixture.entities && fixture.entities.length > 0) {
          clearInterval(pollTimer);
          pollTimer = null;
          loadFixture(fixture);
        }
      }
    } catch { /* retry next interval */ }
  }, 5000);
}

function connectWebSocket() {
  ws = new WebSocket(`${WS_BASE}/ws?session=${sessionId}&role=desktop`);

  ws.onopen = () => { console.log('Desktop WebSocket connected'); };

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    handleWSMessage(msg);
  };

  ws.onclose = () => {
    updateConnectionStatus('disconnected');
    setTimeout(connectWebSocket, 3000);
  };
}

function handleWSMessage(msg) {
  switch (msg.type) {
    case 'connected':
      console.log('Desktop registered for session', msg.sessionId);
      break;
    case 'peer.connected':
      isConnectedToMobile = true;
      updateConnectionStatus('connected');
      document.getElementById('qr-panel').classList.add('connected');
      document.getElementById('qr-panel').classList.remove('waiting');
      document.getElementById('qr-status').textContent = 'PHONE CONNECTED';
      document.getElementById('qr-status').className = 'connected';
      break;
    case 'peer.disconnected':
      isConnectedToMobile = false;
      updateConnectionStatus('disconnected');
      document.getElementById('qr-panel').classList.remove('connected');
      document.getElementById('qr-panel').classList.add('waiting');
      document.getElementById('qr-status').textContent = 'PHONE DISCONNECTED';
      document.getElementById('qr-status').className = 'waiting';
      break;
    case 'time.seek':
      applyTimeFromRemote(msg.value);
      break;
    case 'scene.ready':
      console.log('[Desktop] Scene ready, fetching...');
      fetchSceneData(sessionId);
      break;
    case 'capture.uploaded':
      setSceneState('processing');
      setTimeout(() => fetchSceneData(sessionId), 2000);
      break;
  }
}

function updateConnectionStatus(status) {
  const dot = document.getElementById('connection-dot');
  const label = document.getElementById('connection-label');
  dot.className = status;
  label.textContent = status === 'connected' ? 'PHONE CONNECTED' :
    status === 'disconnected' ? 'PHONE DISCONNECTED' : 'STANDALONE';
}

// ── Three.js Scene ─────────────────────────────────────────
const canvas = document.getElementById('canvas');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.VSMShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.1;
renderer.setClearColor(0xF7F5EF);

const scene = new THREE.Scene();
scene.fog = new THREE.FogExp2(0xF7F5EF, 0.012);

const camera = new THREE.PerspectiveCamera(38, window.innerWidth / window.innerHeight, 0.1, 100);
camera.position.set(5.5, 4.8, 6.2);

const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;
controls.dampingFactor = 0.06;
controls.minDistance = 3;
controls.maxDistance = 16;
controls.maxPolarAngle = Math.PI * 0.48;
controls.target.set(0, 0.6, 0);
controls.update();

// Base lighting
const ambient = new THREE.AmbientLight(0xF2EEE5, 0.35);
scene.add(ambient);

keyLight = new THREE.DirectionalLight(0xFFF5E8, 1.4);
keyLight.position.set(4, 8, 3);
keyLight.castShadow = true;
keyLight.shadow.mapSize.set(2048, 2048);
keyLight.shadow.camera.near = 0.5;
keyLight.shadow.camera.far = 25;
keyLight.shadow.camera.left = -8;
keyLight.shadow.camera.right = 8;
keyLight.shadow.camera.top = 8;
keyLight.shadow.camera.bottom = -8;
keyLight.shadow.radius = 4;
scene.add(keyLight);

const fill = new THREE.DirectionalLight(0xF2EEE5, 0.3);
fill.position.set(-3, 4, -2);
scene.add(fill);

// Rim light — subtle backlight for depth separation
const rim = new THREE.DirectionalLight(0xFFF5E6, 0.25);
rim.position.set(0, 6, -5);
scene.add(rim);

// ── Seeded RNG (deterministic per entity) ─────────────────
function mulberry32(seed) {
  let s = seed | 0;
  return function() {
    s = (s + 0x6D2B79F5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hashStr(str) {
  let h = 0;
  for (let i = 0; i < str.length; i++) h = ((h << 5) - h + str.charCodeAt(i)) | 0;
  return h;
}

// ── Clay material helper ───────────────────────────────────
// Soft molded vinyl / matte toy plastic look.
// - metalness = 0 (clay doesn't reflect metal)
// - clearcoat gives subtle vinyl sheen (0.05–0.15)
// - roughness varies per entity via seeded random
// - flatShading: true for faceted clay feel
function hex(color) {
  if (typeof color === 'number') return color;
  return parseInt(String(color).replace('#', ''), 16);
}

const CLAY_RANGES = {
  building: [0.42, 0.52],
  tree:     [0.60, 0.75],
  ground:   [0.70, 0.80],
  prop:     [0.35, 0.45],
  path:     [0.55, 0.65],
  person:   [0.45, 0.55],
  default:  [0.50, 0.70],
};

function clayMat(color, opts = {}) {
  const entityType = opts.entityType || 'default';
  const seed = opts.seed ?? hashStr(String(color));
  const rng = mulberry32(seed);
  const range = CLAY_RANGES[entityType] || CLAY_RANGES.default;
  const roughness = opts.roughness ?? (range[0] + rng() * (range[1] - range[0]));
  const clearcoat = opts.clearcoat ?? (entityType === 'prop' ? 0.12 : entityType === 'building' ? 0.08 : 0.05);

  const mat = new THREE.MeshPhysicalMaterial({
    color: hex(color),
    roughness,
    metalness: 0,
    clearcoat,
    clearcoatRoughness: 0.4,
    flatShading: true,
    ...opts,
  });
  mat.userData = { baseColor: new THREE.Color(hex(color)) };
  return mat;
}

// ── Empty state: soft clay ground plane ─────────────────────
const emptyGround = new THREE.Mesh(
  new THREE.PlaneGeometry(60, 60),
  clayMat(0xD6CEBF, { roughness: 1 })
);
emptyGround.rotation.x = -Math.PI / 2;
emptyGround.position.y = -0.52;
emptyGround.receiveShadow = true;
scene.add(emptyGround);

const gridGeo = new THREE.PlaneGeometry(20, 20, 20, 20);
const gridMat = new THREE.MeshBasicMaterial({
  color: 0x202425, wireframe: true, transparent: true, opacity: 0.03
});
const gridMesh = new THREE.Mesh(gridGeo, gridMat);
gridMesh.rotation.x = -Math.PI / 2;
gridMesh.position.y = -0.51;
scene.add(gridMesh);

const emptyBase = new THREE.Mesh(
  new THREE.BoxGeometry(4, 0.3, 4, 4, 1, 4),
  clayMat(0xCEC7B8)
);
emptyBase.position.y = -0.35;
emptyBase.receiveShadow = true;
scene.add(emptyBase);

// ── Load a SceneFixture dynamically ────────────────────────
function loadFixture(fixture) {
  console.log('[Desktop] Loading fixture:', fixture.name || fixture.id);
  currentFixture = fixture;

  clearLoadedEntities();

  scene.remove(emptyGround);
  scene.remove(gridMesh);
  scene.remove(emptyBase);

  if (fixture.style) {
    if (fixture.style.clearColor) renderer.setClearColor(hex(fixture.style.clearColor));
    if (fixture.style.fog) scene.fog = new THREE.FogExp2(hex(fixture.style.fog.color), fixture.style.fog.density);
  }

  const P = fixture.palette || {};
  // Default palette fallback for when entities carry their own colors
  const defaults = {
    charcoal: 0x202425, warmWhite: 0xF2EEE5, warmWhiteR: 0xCEC7B8,
    orange: 0xFF672A, orangeRim: 0xC9441D, lime: 0xB7D83D,
    yellow: 0xFFC52A, trunk: 0x6B4E3D, foliage1: 0x7E9A27,
    foliage2: 0xB7D83D, foliage3: 0x5B8C3E, skin: 0xF2D5B5,
    cloth1: 0xFF672A, cloth2: 0x3A3E3F, road: 0x9E9688,
    sidewalk: 0xC8C0B2, grass: 0x8FCB7E,
  };
  for (const [k, v] of Object.entries(defaults)) {
    if (P[k] === undefined) P[k] = v;
  }
  timelineIntervals = fixture.temporalSpec?.timelineIntervals || [];

  // Add ground
  const groundEntity = fixture.entities.find(e => e.type === 'ground' || e.type === 'terrain');
  if (groundEntity) {
    const gw = groundEntity.size?.[0] ?? groundEntity.geometry?.parameters?.width ?? 60;
    const gd = groundEntity.size?.[1] ?? groundEntity.geometry?.parameters?.depth ?? 60;
    const g = new THREE.Mesh(
      new THREE.PlaneGeometry(gw, gd),
      clayMat(groundEntity.material?.color ?? (P.charcoal ?? 0x202425), { entityType: 'ground', seed: 999 })
    );
    g.rotation.x = -Math.PI / 2;
    g.position.y = groundEntity.position?.[1] ?? -0.52;
    g.receiveShadow = true;
    scene.add(g);
  }

  // Add grid
  const gridG2 = new THREE.Mesh(
    new THREE.PlaneGeometry(20, 20, 20, 20),
    new THREE.MeshBasicMaterial({ color: hex(P.charcoal ?? 0x202425), wireframe: true, transparent: true, opacity: 0.03 })
  );
  gridG2.rotation.x = -Math.PI / 2;
  gridG2.position.y = -0.51;
  scene.add(gridG2);

  // Build all entities
  for (const entity of fixture.entities) {
    if (entity.type === 'ground' || entity.type === 'terrain') continue;
    if (entity.type === 'base') {
      const w = entity.size?.[0] ?? 7, d = entity.size?.[1] ?? 7, h = entity.size?.[2] ?? 0.5;
      const baseG = new THREE.Group();
      const bodyGeo = new RoundedBoxGeometry(w, h, d, 3, 0.12);
      const body = new THREE.Mesh(bodyGeo, clayMat(P.warmWhiteR ?? 0xCEC7B8, { entityType: 'ground', seed: 500 }));
      body.position.y = -h / 2; body.castShadow = true; body.receiveShadow = true;
      baseG.add(body);
      const topGeo = new RoundedBoxGeometry(w - 0.08, 0.06, d - 0.08, 2, 0.03);
      const top = new THREE.Mesh(topGeo, clayMat(P.warmWhite ?? 0xF2EEE5, { entityType: 'ground', seed: 501 }));
      top.position.y = 0.03; top.receiveShadow = true;
      baseG.add(top);
      scene.add(baseG);
      continue;
    }
    if (entity.type === 'road') {
      scene.add(buildRoadFromFixture(entity, P));
      continue;
    }
    const group = buildEntityFromFixture(entity, P);
    if (group) {
      group.userData = { category: entity.category, id: entity.id };
      scene.add(group);
      loadedEntities.push({ id: entity.id, category: entity.category, group, spec: entity });
    }
  }

  if (fixture.temporalSpec?.anchorYears?.length > 0) applyTemporalState(2026, fixture);
  setSceneState('loaded');
  console.log('[Desktop] Fixture loaded:', loadedEntities.length, 'entities');
}

function clearLoadedEntities() {
  for (const ent of loadedEntities) scene.remove(ent.group);
  loadedEntities = [];
  grassMeshes = [];
}

function buildRoadFromFixture(entity, P) {
  const group = new THREE.Group();
  const w = entity.size?.[0] ?? 6.4, d = entity.size?.[2] ?? 2.2;
  const road = new THREE.Mesh(new THREE.BoxGeometry(w, 0.04, d), clayMat(P.road ?? 0x9E9688));
  road.position.set(0, 0.06, 0); road.receiveShadow = true; group.add(road);
  const dashCount = entity.dashes?.count ?? 7, dashSpacing = entity.dashes?.spacing ?? 1.2;
  for (let i = -Math.floor(dashCount / 2); i <= Math.floor(dashCount / 2); i++) {
    const dash = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.045, 0.08), clayMat(P.yellow ?? 0xFFC52A));
    dash.position.set(i * dashSpacing, 0.07, 0); group.add(dash);
  }
  for (const sw of (entity.sidewalks || [])) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(sw.size[0], sw.size[1], sw.size[2]), clayMat(P.sidewalk ?? 0xC8C0B2));
    mesh.position.set(sw.position[0], sw.position[1], sw.position[2]); mesh.castShadow = true; mesh.receiveShadow = true; group.add(mesh);
  }
  for (const gs of (entity.grass || [])) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(gs.size[0], gs.size[1], gs.size[2]), clayMat(P.grass ?? 0x8FCB7E));
    mesh.position.set(gs.position[0], gs.position[1], gs.position[2]); mesh.receiveShadow = true; group.add(mesh); grassMeshes.push(mesh);
  }
  return group;
}

function buildEntityFromFixture(entity, P) {
  // Map canonical scene types to desktop builder types
  const typeMap = {
    'building': 'gate', 'tree': 'tree', 'path': 'road', 'terrain': 'ground',
    'road': 'road', 'vehicle': 'bicycle', 'person': 'character', 'prop': 'bench',
    'furniture': 'bench', 'sign': 'streetSign', 'light-pole': 'lampPost',
  };
  const t = typeMap[entity.type] || entity.type;

  switch (t) {
    case 'gate': return buildGate(entity, P);
    case 'tree': return buildTree(entity, P);
    case 'character': return buildCharacter(entity, P);
    case 'bench': return buildBench(entity, P);
    case 'streetSign': return buildStreetSign(entity, P);
    case 'bicycle': return buildBicycle(entity, P);
    case 'lampPost': return buildLampPost(entity, P);
    case 'flowerBed': return buildFlowerBed(entity, P);
    case 'road': return buildRoadFromEntity(entity, P);
    default: {
      const g = new THREE.Group();
      g.add(new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.5, 0.5), clayMat(P.warmWhite ?? 0xF2EEE5)));
      g.position.set(entity.position?.[0] ?? 0, (entity.position?.[1] ?? 0) + 0.25, entity.position?.[2] ?? 0);
      return g;
    }
  }
}

// Build a road/path from canonical entity spec
function buildRoadFromEntity(entity, P) {
  const g = new THREE.Group();
  const w = entity.geometry?.parameters?.width ?? 2;
  const l = entity.geometry?.parameters?.length ?? 8;
  const road = new THREE.Mesh(
    new RoundedBoxGeometry(w, 0.04, l, 2, 0.01),
    clayMat(entity.material?.color ?? (P.road ?? 0x9E9688), { entityType: 'path', seed: hashStr(entity.id || 'road') })
  );
  road.position.y = 0.02; road.receiveShadow = true;
  g.add(road);
  g.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  return g;
}

function buildGate(entity, P) {
  const g = new THREE.Group();
  const bW = entity.size?.[0] ?? entity.geometry?.parameters?.width ?? 4.2;
  const bH = entity.size?.[1] ?? entity.geometry?.parameters?.height ?? 3.2;
  const bD = entity.size?.[2] ?? entity.geometry?.parameters?.depth ?? 1.6;
  const bevel = entity.geometry?.parameters?.cornerRadius ?? 0.14;
  const matColor = entity.material?.color ?? (P.warmWhite ?? 0xF2EEE5);

  // Main building body — rounded box
  const bodyGeo = new RoundedBoxGeometry(bW, bH, bD, 3, bevel);
  const body = new THREE.Mesh(bodyGeo, clayMat(matColor, { entityType: 'building', seed: hashStr(entity.id || 'gate') }));
  body.position.y = bH/2; body.castShadow = true; body.receiveShadow = true;
  g.add(body);

  // Base plinth — rounded
  const baseGeo = new RoundedBoxGeometry(bW+0.12, 0.2, bD+0.12, 2, 0.06);
  const base = new THREE.Mesh(baseGeo, clayMat(P.warmWhiteR ?? 0xCEC7B8, { entityType: 'building', seed: 101 }));
  base.position.y = 0.1; base.castShadow = true;
  g.add(base);

  // Door arch — orange accent
  const doorGeo = new RoundedBoxGeometry(1.6, 2.2, bD+0.15, 2, 0.08);
  const door = new THREE.Mesh(doorGeo, clayMat(P.orange ?? 0xFF672A, { entityType: 'building', seed: 102 }));
  door.position.y = 1.1; door.castShadow = true;
  g.add(door);

  // Arch top
  const archTop = new THREE.Mesh(
    new THREE.CylinderGeometry(0.8, 0.8, bD+0.15, 16, 1, false, 0, Math.PI),
    clayMat(P.orange ?? 0xFF672A, { entityType: 'building', seed: 103 })
  );
  archTop.rotation.x = Math.PI/2; archTop.rotation.z = Math.PI/2;
  archTop.position.set(0, 2.2, 0);
  g.add(archTop);

  // Windows — recessed with frames
  for (let side = -1; side <= 1; side += 2) {
    for (let i = 0; i < 2; i++) {
      const win = new THREE.Mesh(
        new THREE.BoxGeometry(0.45, 0.6, 0.08),
        clayMat(P.charcoal ?? 0x202425, { entityType: 'prop', seed: 200 + side*10 + i })
      );
      win.position.set(side*(1.1+i*0.65), 1.8, bD/2+0.04);
      g.add(win);
      const frame = new THREE.Mesh(
        new RoundedBoxGeometry(0.52, 0.67, 0.04, 1, 0.03),
        clayMat(P.warmWhiteR ?? 0xCEC7B8, { entityType: 'building', seed: 210 + side*10 + i })
      );
      frame.position.copy(win.position); frame.position.z += 0.03;
      g.add(frame);
    }
  }

  // Top cornice — rounded
  const corniceGeo = new RoundedBoxGeometry(bW+0.2, 0.18, bD+0.2, 2, 0.05);
  const cornice = new THREE.Mesh(corniceGeo, clayMat(P.orangeRim ?? 0xC9441D, { entityType: 'building', seed: 300 }));
  cornice.position.y = bH+0.09; cornice.castShadow = true;
  g.add(cornice);

  // Sign plate
  const signGeo = new RoundedBoxGeometry(2.0, 0.45, 0.08, 2, 0.04);
  const sign = new THREE.Mesh(signGeo, clayMat(P.orange ?? 0xFF672A, { entityType: 'prop', seed: 301 }));
  sign.position.set(0, bH-0.35, bD/2+0.08); sign.castShadow = true;
  g.add(sign);

  // Pillars
  for (let side = -1; side <= 1; side += 2) {
    const pillar = new THREE.Mesh(
      new THREE.CylinderGeometry(0.12, 0.14, bH, 8),
      clayMat(P.warmWhiteR ?? 0xCEC7B8, { entityType: 'building', seed: 400 + side })
    );
    pillar.position.set(side*(bW/2-0.15), bH/2, bD/2+0.08);
    pillar.castShadow = true;
    g.add(pillar);
  }

  // Contact shadow under building
  addContactShadow(g, Math.max(bW, bD) * 0.55, 0.15);

  g.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  return g;
}

function buildTree(entity, P) {
  const scale = entity.scale?.[0] ?? entity.scale ?? 1;
  const tH = entity.geometry?.parameters?.height ?? entity.trunkHeight ?? 1.0;
  const cR = entity.geometry?.parameters?.crownRadius ?? entity.crownRadius ?? 0.7;
  const seed = entity.seed ?? hashStr(entity.id || 'tree');
  const rng = mulberry32(seed);
  const tree = new THREE.Group();
  const matColor = entity.material?.color ?? (P.foliage2 ?? 0xB7D83D);

  // Trunk — slight taper, 6-sided for organic feel
  const trunk = new THREE.Mesh(
    new THREE.CylinderGeometry(0.06*scale, 0.12*scale, tH*scale, 6),
    clayMat(P.trunk ?? 0x6B4E3D, { entityType: 'tree', seed: seed + 1 })
  );
  trunk.position.y = tH*scale/2; trunk.castShadow = true; tree.add(trunk);

  // Crown — organic blobs with seeded squash
  const blobCount = 3 + Math.floor(rng() * 3);
  for (let i = 0; i < blobCount; i++) {
    const r = cR*scale*(0.45 + rng()*0.4);
    // Squashed sphere = organic blob shape
    const geo = new THREE.SphereGeometry(r, 10, 8);
    // Displace vertices for organic feel
    const pos = geo.attributes.position;
    for (let v = 0; v < pos.count; v++) {
      const x = pos.getX(v), y = pos.getY(v), z = pos.getZ(v);
      const noise = 0.85 + rng() * 0.3;
      pos.setXYZ(v, x * noise, y * (0.6 + rng()*0.35), z * noise);
    }
    geo.computeVertexNormals();

    const color = i % 3 === 0 ? matColor :
                  i % 3 === 1 ? (P.foliage1 ?? 0x7E9A27) :
                                 (P.foliage3 ?? 0x5B8C3E);
    const blob = new THREE.Mesh(geo, clayMat(color, { entityType: 'tree', seed: seed + 10 + i }));
    blob.position.set(
      (rng()-0.5)*cR*scale*0.5,
      tH*scale + cR*scale*0.2 + (rng()-0.3)*cR*scale*0.4,
      (rng()-0.5)*cR*scale*0.5
    );
    blob.castShadow = true;
    tree.add(blob);
  }

  // Contact shadow (dark circle under tree)
  const shadowGeo = new THREE.CircleGeometry(cR*scale*0.9, 16);
  const shadowMat = new THREE.MeshBasicMaterial({
    color: 0x000000, transparent: true, opacity: 0.12, depthWrite: false
  });
  const shadow = new THREE.Mesh(shadowGeo, shadowMat);
  shadow.rotation.x = -Math.PI/2; shadow.position.y = 0.01;
  tree.add(shadow);

  tree.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  return tree;
}

function buildCharacter(entity, P) {
  const s = entity.scale || 0.38;
  const seed = entity.seed ?? hashStr(entity.id || 'char');
  const clothColor = P[entity.clothColor] ?? P.cloth1 ?? 0xFF672A;
  const c = new THREE.Group();

  for (let side = -1; side <= 1; side += 2) {
    const leg = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.08*s, 0.35*s, 4, 8),
      clayMat(P.cloth2 ?? 0x3A3E3F, { entityType: 'person', seed: seed + side })
    );
    leg.position.set(side*0.1*s, 0.2*s, 0);
    c.add(leg);
  }
  const torso = new THREE.Mesh(
    new THREE.CapsuleGeometry(0.18*s, 0.3*s, 4, 8),
    clayMat(clothColor, { entityType: 'person', seed: seed + 10 })
  );
  torso.position.y = 0.55*s; torso.castShadow = true;
  c.add(torso);

  for (let side = -1; side <= 1; side += 2) {
    const arm = new THREE.Mesh(
      new THREE.CapsuleGeometry(0.055*s, 0.28*s, 4, 8),
      clayMat(clothColor, { entityType: 'person', seed: seed + 20 + side })
    );
    arm.position.set(side*0.24*s, 0.52*s, 0); arm.rotation.z = side*0.15;
    c.add(arm);
  }

  const head = new THREE.Mesh(
    new THREE.SphereGeometry(0.15*s, 10, 8),
    clayMat(P.skin ?? 0xF2D5B5, { entityType: 'person', seed: seed + 30 })
  );
  head.position.y = 0.88*s; head.scale.y = 1.05; head.castShadow = true;
  c.add(head);

  const hair = new THREE.Mesh(
    new THREE.SphereGeometry(0.16*s, 10, 8, 0, Math.PI*2, 0, Math.PI*0.6),
    clayMat(P.charcoal ?? 0x202425, { entityType: 'person', seed: seed + 40 })
  );
  hair.position.y = 0.9*s;
  c.add(hair);

  // Tiny contact shadow
  addContactShadow(c, 0.2*s, 0.08);

  c.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  c.rotation.y = entity.rotation || 0;
  return c;
}

function buildBench(entity, P) {
  const b = new THREE.Group();
  b.add(Object.assign(new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.06, 0.3), clayMat(P.trunk ?? 0x6B4E3D)), { position: new THREE.Vector3(0, 0.32, 0) }));
  b.add(Object.assign(new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.35, 0.05), clayMat(P.trunk ?? 0x6B4E3D)), { position: new THREE.Vector3(0, 0.48, -0.12) }));
  for (let lx = -1; lx <= 1; lx += 2) {
    const leg = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.32, 0.25), clayMat(P.warmWhiteR ?? 0xCEC7B8));
    leg.position.set(lx*0.32, 0.16, 0); b.add(leg);
  }
  b.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  b.rotation.y = entity.rotation || 0;
  return b;
}

function buildStreetSign(entity, P) {
  const s = new THREE.Group();
  s.add(Object.assign(new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 1.2, 6), clayMat(P.warmWhiteR ?? 0xCEC7B8)), { position: new THREE.Vector3(0, 0.6, 0) }));
  const board = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.25, 0.04), clayMat(P.orange ?? 0xFF672A));
  board.position.y = 1.1; board.castShadow = true; s.add(board);
  s.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  return s;
}

function buildBicycle(entity, P) {
  const bike = new THREE.Group(), wR = 0.18;
  for (let wx = -1; wx <= 1; wx += 2) {
    const wheel = new THREE.Mesh(new THREE.TorusGeometry(wR, 0.025, 8, 16), clayMat(P.charcoal ?? 0x202425));
    wheel.rotation.y = Math.PI/2; wheel.position.set(wx*0.25, wR, 0); bike.add(wheel);
  }
  const frame = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.02, 0.4, 6), clayMat(P.lime ?? 0xB7D83D));
  frame.position.set(0, wR+0.1, 0); frame.rotation.z = 0.3; bike.add(frame);
  const bar = new THREE.Mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.2, 6), clayMat(P.warmWhiteR ?? 0xCEC7B8));
  bar.position.set(0.2, wR+0.25, 0); bar.rotation.z = Math.PI/2; bike.add(bar);
  bike.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  bike.rotation.y = entity.rotation || 0; bike.scale.setScalar(0.8);
  return bike;
}

function buildLampPost(entity, P) {
  const lp = new THREE.Group();
  lp.add(Object.assign(new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.05, 2.0, 8), clayMat(P.warmWhiteR ?? 0xCEC7B8)), { position: new THREE.Vector3(0, 1.0, 0) }));
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.12, 10, 8), clayMat(P.yellow ?? 0xFFC52A));
  head.position.y = 2.1; head.castShadow = true; lp.add(head);
  lp.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  return lp;
}

function buildFlowerBed(entity, P) {
  const w = entity.size?.[0] ?? 1.5, d = entity.size?.[1] ?? 0.6;
  const bed = new THREE.Group();
  bed.add(Object.assign(new THREE.Mesh(new THREE.BoxGeometry(w, 0.12, d), clayMat(P.warmWhiteR ?? 0xCEC7B8)), { position: new THREE.Vector3(0, 0.06, 0), receiveShadow: true }));
  bed.add(Object.assign(new THREE.Mesh(new THREE.BoxGeometry(w-0.1, 0.08, d-0.1), clayMat(P.trunk ?? 0x6B4E3D, { roughness: 0.95 })), { position: new THREE.Vector3(0, 0.08, 0) }));
  for (let i = 0; i < 5; i++) {
    const flower = new THREE.Mesh(new THREE.SphereGeometry(0.08, 8, 6), clayMat([P.orange ?? 0xFF672A, P.yellow ?? 0xFFC52A, P.lime ?? 0xB7D83D][i%3]));
    flower.position.set((Math.random()-0.5)*(w-0.3), 0.18, (Math.random()-0.5)*(d-0.3)); flower.castShadow = true; bed.add(flower);
  }
  bed.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  return bed;
}

// ── Temporal System ────────────────────────────────────────

function lerp(a, b, t) { return a + (b - a) * t; }
function clamp01(t) { return Math.max(0, Math.min(1, t)); }

function getInterpolatedState(year, fixture) {
  const anchors = fixture.temporalSpec?.anchorYears;
  if (!anchors || anchors.length === 0) return { states: {}, lowerYear: year, upperYear: year };
  let lower = anchors[0], upper = anchors[anchors.length - 1];
  for (let i = 0; i < anchors.length - 1; i++) {
    if (anchors[i].year <= year && anchors[i + 1].year >= year) { lower = anchors[i]; upper = anchors[i + 1]; break; }
  }
  const span = upper.year - lower.year;
  const t = span > 0 ? clamp01((year - lower.year) / span) : 0;
  const allIds = new Set([...Object.keys(lower.entities), ...Object.keys(upper.entities)]);
  const result = {};
  for (const id of allIds) {
    const a = lower.entities[id] || {}, b = upper.entities[id] || {};
    result[id] = { presence: lerp(a.presence ?? 1, b.presence ?? 1, t) };
    for (const k of ['growth', 'crownVolume', 'weathering', 'height']) {
      if (a[k] !== undefined || b[k] !== undefined) result[id][k] = lerp(a[k] ?? b[k] ?? 0, b[k] ?? a[k] ?? 0, t);
    }
    result[id].structuralVariant = t < 0.5 ? (a.structuralVariant || 'original') : (b.structuralVariant || 'original');
    result[id].newWindows = t >= 0.7 ? (b.newWindows || false) : (a.newWindows || false);
    result[id].bodyStage = t < 0.5 ? (a.bodyStage || 'adult') : (b.bodyStage || 'adult');
    result[id].positionOffset = b.positionOffset ? b.positionOffset.map(v => lerp(0, v, t)) : [0, 0, 0];
  }
  return { states: result, lowerYear: lower.year, upperYear: upper.year };
}

function applyTemporalState(year, fixture) {
  if (!fixture) fixture = currentFixture;
  if (!fixture) return;
  const { states } = getInterpolatedState(year, fixture);
  const P = fixture.palette || {};
  const seasonCycle = ((year % 1) + 1) % 1;

  for (const ent of loadedEntities) {
    if (ent.category === 'building') {
      const bs = states[ent.id];
      if (bs) {
        const w = bs.weathering || 0;
        ent.group.children.forEach(child => {
          if (child.material?.userData?.baseColor) child.material.color.copy(child.material.userData.baseColor.clone().lerp(new THREE.Color(hex(P.warmWhiteR ?? 0xCEC7B8)), w));
        });
      }
    }
  }

  loadedEntities.filter(e => e.category === 'vegetation').forEach((treeHandle, i) => {
    const ts = states[treeHandle.id]; if (!ts) return;
    const g = ts.growth || 1, cv = ts.crownVolume || 1;
    treeHandle.group.children.forEach(child => {
      if (child.geometry?.type === 'CylinderGeometry') child.scale.set(g, g, g);
      else if (child.geometry?.type === 'SphereGeometry') {
        child.scale.setScalar(g * cv);
        const base = child.material.userData?.baseColor || new THREE.Color(hex(P.foliage2 ?? 0xB7D83D));
        const autumn = new THREE.Color(hex(P.yellowRim ?? 0xC18B14)), winter = new THREE.Color(hex(P.warmWhiteR ?? 0xCEC7B8));
        let c;
        if (seasonCycle < 0.25) c = base.clone().lerp(winter, seasonCycle * 4);
        else if (seasonCycle < 0.5) c = winter.clone().lerp(base, (seasonCycle - 0.25) * 4);
        else if (seasonCycle < 0.75) c = base.clone().lerp(autumn, (seasonCycle - 0.5) * 4);
        else c = autumn.clone().lerp(winter, (seasonCycle - 0.75) * 4);
        child.material.color.copy(c);
      }
    });
  });

  loadedEntities.filter(e => e.category === 'character').forEach(charHandle => {
    const ps = states[charHandle.id]; if (!ps) return;
    charHandle.group.visible = (ps.presence || 0) > 0.1;
    if (!charHandle.group.visible) return;
    charHandle.group.scale.setScalar(ps.height || 1.0);
    const origPos = charHandle.spec.position || [0, 0, 0], off = ps.positionOffset || [0, 0, 0];
    charHandle.group.position.x = origPos[0] + off[0]; charHandle.group.position.z = origPos[2] + off[2];
  });

  const warm = new THREE.Color(0xFFF5E8), cool = new THREE.Color(0xE8F0FF);
  const sw = 0.5 + 0.5 * Math.sin(seasonCycle * Math.PI * 2);
  keyLight.color.copy(cool.clone().lerp(warm, sw)); keyLight.intensity = lerp(1.0, 1.5, sw);

  if (grassMeshes.length > 0) {
    const grassGreen = new THREE.Color(hex(P.grass ?? 0x8FCB7E)), grassAutumn = new THREE.Color(hex(P.yellowRim ?? 0xC18B14));
    const ss = (Math.sin(seasonCycle * Math.PI * 2) + 1) / 2 * 0.4;
    const gt = grassGreen.clone().lerp(grassAutumn, ss);
    grassMeshes.forEach(mesh => mesh.material.color.copy(gt));
  }

  updateUI(year);
}

function updateUI(year) {
  const y = Math.round(year);
  document.getElementById('year-label').textContent = y;
  document.getElementById('era-label').textContent = y < 2020 ? 'PAST' : y <= 2028 ? 'PRESENT' : y <= 2040 ? 'NEAR FUTURE' : 'FUTURE';
  const iv = timelineIntervals.find(iv => year >= iv.startYear && year <= iv.endYear);
  const card = document.getElementById('interval-card');
  const label = document.getElementById('interval-label');
  if (iv) {
    const icons = { stable: '●', gradual: '◐', event: '⚡', transition: '◑', settled: '○' };
    card.innerHTML = '<span style="color:#4A90D9">' + (icons[iv.mode] || '●') + ' ' + iv.mode.toUpperCase() + '</span> — ' + iv.narrative;
    card.classList.add('visible');
    if (label) label.textContent = iv.narrative;
  } else {
    card.classList.remove('visible');
    if (label) label.textContent = '';
  }
}

function applyTimeFromRemote(p) {
  if (!currentFixture) return;
  const years = Math.sign(p) * 36525 * Math.pow(Math.abs(p), 2.35) / 365.25;
  applyTemporalState(2026 + years, currentFixture);
}

// ── Animation Loop ─────────────────────────────────────────
const clock = new THREE.Clock();
let lastInteraction = 0;
canvas.addEventListener('pointerdown', () => { lastInteraction = performance.now(); });
canvas.addEventListener('wheel', () => { lastInteraction = performance.now(); });

function animate() {
  requestAnimationFrame(animate);
  const t = clock.getElapsedTime();
  const idle = (performance.now() - lastInteraction) / 1000;
  controls.autoRotate = idle > 5;
  controls.autoRotateSpeed = 0.4;
  controls.update();

  loadedEntities.filter(e => e.category === 'character').forEach((p, i) => {
    if (p.group.visible) p.group.children.forEach(c => {
      if (c.geometry?.type === 'CapsuleGeometry' && c.position.y > 0.3) c.rotation.z += Math.sin(t * 1.5 + i) * 0.0003;
    });
  });
  loadedEntities.filter(e => e.category === 'vegetation').forEach((tree, i) => {
    tree.group.children.forEach(c => {
      if (c.geometry?.type === 'SphereGeometry') {
        c.position.x += Math.sin(t * 0.8 + i * 1.5) * 0.0002;
        c.position.z += Math.cos(t * 0.6 + i * 2) * 0.0001;
      }
    });
  });

  renderer.render(scene, camera);
}

// ── Resize ─────────────────────────────────────────────────
window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// ── Start ──────────────────────────────────────────────────
animate();
initSession();
setTimeout(() => document.getElementById('loading').classList.add('done'), 800);
