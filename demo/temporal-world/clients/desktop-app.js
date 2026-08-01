import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

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
  try {
    const res = await fetch(`${API_BASE}/api/scene/${sid}`);
    if (res.status === 404) {
      setSceneState('waiting');
      return;
    }
    if (!res.ok) {
      setSceneState('error', { message: `Server error (${res.status})` });
      return;
    }
    const fixture = await res.json();
    if (!fixture || !fixture.entities || fixture.entities.length === 0) {
      setSceneState('waiting');
      return;
    }
    loadFixture(fixture);
  } catch (e) {
    console.warn('[Desktop] Failed to fetch scene:', e);
    setSceneState('error', { message: 'Could not load scene' });
  }
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

// ── Clay material helper ───────────────────────────────────
function hex(color) {
  if (typeof color === 'number') return color;
  return parseInt(String(color).replace('#', ''), 16);
}

function clayMat(color, opts = {}) {
  const mat = new THREE.MeshStandardMaterial({
    color: hex(color), roughness: opts.roughness ?? 0.84, metalness: 0, flatShading: false, ...opts
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
  timelineIntervals = fixture.temporalSpec?.timelineIntervals || [];

  // Add ground
  const groundEntity = fixture.entities.find(e => e.type === 'ground');
  if (groundEntity) {
    const g = new THREE.Mesh(
      new THREE.PlaneGeometry(groundEntity.size?.[0] ?? 60, groundEntity.size?.[1] ?? 60),
      clayMat(P.charcoal ?? 0x202425, { roughness: 1 })
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
    if (entity.type === 'ground') continue;
    if (entity.type === 'base') {
      const w = entity.size?.[0] ?? 7, d = entity.size?.[1] ?? 7, h = entity.size?.[2] ?? 0.5;
      const baseG = new THREE.Group();
      const body = new THREE.Mesh(new THREE.BoxGeometry(w, h, d, 4, 2, 4), clayMat(P.warmWhiteR ?? 0xCEC7B8));
      body.position.y = -h / 2; body.castShadow = true; body.receiveShadow = true;
      baseG.add(body);
      const top = new THREE.Mesh(new THREE.BoxGeometry(w - 0.08, 0.06, d - 0.08, 4, 1, 4), clayMat(P.warmWhite ?? 0xF2EEE5));
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
  switch (entity.type) {
    case 'gate': return buildGate(entity, P);
    case 'tree': return buildTree(entity, P);
    case 'character': return buildCharacter(entity, P);
    case 'bench': return buildBench(entity, P);
    case 'streetSign': return buildStreetSign(entity, P);
    case 'bicycle': return buildBicycle(entity, P);
    case 'lampPost': return buildLampPost(entity, P);
    case 'flowerBed': return buildFlowerBed(entity, P);
    default: {
      const g = new THREE.Group();
      g.add(new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.5, 0.5), clayMat(P.warmWhite ?? 0xF2EEE5)));
      g.position.set(entity.position?.[0] ?? 0, (entity.position?.[1] ?? 0) + 0.25, entity.position?.[2] ?? 0);
      return g;
    }
  }
}

function buildGate(entity, P) {
  const g = new THREE.Group();
  const bW = entity.size?.[0] ?? 4.2, bH = entity.size?.[1] ?? 3.2, bD = entity.size?.[2] ?? 1.6;
  g.add(Object.assign(new THREE.Mesh(new THREE.BoxGeometry(bW, bH, bD, 2, 2, 2), clayMat(P.warmWhite ?? 0xF2EEE5)), { position: new THREE.Vector3(0, bH/2, 0), castShadow: true, receiveShadow: true }));
  g.add(Object.assign(new THREE.Mesh(new THREE.BoxGeometry(bW+0.12, 0.2, bD+0.12), clayMat(P.warmWhiteR ?? 0xCEC7B8)), { position: new THREE.Vector3(0, 0.1, 0), castShadow: true }));
  g.add(Object.assign(new THREE.Mesh(new THREE.BoxGeometry(1.6, 2.2, bD+0.15), clayMat(P.orange ?? 0xFF672A)), { position: new THREE.Vector3(0, 1.1, 0), castShadow: true }));
  const archTop = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 0.8, bD+0.15, 16, 1, false, 0, Math.PI), clayMat(P.orange ?? 0xFF672A));
  archTop.rotation.x = Math.PI/2; archTop.rotation.z = Math.PI/2; archTop.position.set(0, 2.2, 0); g.add(archTop);
  for (let side = -1; side <= 1; side += 2) {
    for (let i = 0; i < 2; i++) {
      const win = new THREE.Mesh(new THREE.BoxGeometry(0.45, 0.6, 0.08), clayMat(P.charcoal ?? 0x202425, { roughness: 0.4 }));
      win.position.set(side*(1.1+i*0.65), 1.8, bD/2+0.04); g.add(win);
      const frame = new THREE.Mesh(new THREE.BoxGeometry(0.52, 0.67, 0.04), clayMat(P.warmWhiteR ?? 0xCEC7B8));
      frame.position.copy(win.position); frame.position.z += 0.03; g.add(frame);
    }
  }
  g.add(Object.assign(new THREE.Mesh(new THREE.BoxGeometry(bW+0.2, 0.18, bD+0.2), clayMat(P.orangeRim ?? 0xC9441D)), { position: new THREE.Vector3(0, bH+0.09, 0), castShadow: true }));
  g.add(Object.assign(new THREE.Mesh(new THREE.BoxGeometry(2.0, 0.45, 0.08), clayMat(P.orange ?? 0xFF672A)), { position: new THREE.Vector3(0, bH-0.35, bD/2+0.08), castShadow: true }));
  for (let side = -1; side <= 1; side += 2) {
    const pillar = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.14, bH, 8), clayMat(P.warmWhiteR ?? 0xCEC7B8));
    pillar.position.set(side*(bW/2-0.15), bH/2, bD/2+0.08); pillar.castShadow = true; g.add(pillar);
  }
  g.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  return g;
}

function buildTree(entity, P) {
  const scale = entity.scale || 1, tH = entity.trunkHeight || 1.0, cR = entity.crownRadius || 0.7;
  const tree = new THREE.Group();
  const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.06*scale, 0.1*scale, tH*scale, 8), clayMat(P.trunk ?? 0x6B4E3D));
  trunk.position.y = tH*scale/2; trunk.castShadow = true; tree.add(trunk);
  for (let i = 0; i < 4; i++) {
    const r = cR*scale*(0.6+Math.random()*0.5);
    const blob = new THREE.Mesh(new THREE.SphereGeometry(r, 12, 10), clayMat(i%2===0 ? (P.foliage1 ?? 0x7E9A27) : (P.foliage2 ?? 0xB7D83D)));
    blob.position.set((Math.random()-0.5)*cR*scale*0.6, tH*scale+cR*scale*0.3+(Math.random()-0.3)*cR*scale*0.5, (Math.random()-0.5)*cR*scale*0.6);
    blob.scale.y = 0.7+Math.random()*0.3; blob.castShadow = true; tree.add(blob);
  }
  tree.position.set(entity.position?.[0] ?? 0, entity.position?.[1] ?? 0, entity.position?.[2] ?? 0);
  return tree;
}

function buildCharacter(entity, P) {
  const s = entity.scale || 0.38;
  const clothColor = P[entity.clothColor] ?? P.cloth1 ?? 0xFF672A;
  const c = new THREE.Group();
  for (let side = -1; side <= 1; side += 2) {
    const leg = new THREE.Mesh(new THREE.CapsuleGeometry(0.08*s, 0.35*s, 4, 8), clayMat(P.cloth2 ?? 0x3A3E3F));
    leg.position.set(side*0.1*s, 0.2*s, 0); c.add(leg);
  }
  const torso = new THREE.Mesh(new THREE.CapsuleGeometry(0.18*s, 0.3*s, 4, 8), clayMat(clothColor));
  torso.position.y = 0.55*s; torso.castShadow = true; c.add(torso);
  for (let side = -1; side <= 1; side += 2) {
    const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.055*s, 0.28*s, 4, 8), clayMat(clothColor));
    arm.position.set(side*0.24*s, 0.52*s, 0); arm.rotation.z = side*0.15; c.add(arm);
  }
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.15*s, 10, 8), clayMat(P.skin ?? 0xF2D5B5));
  head.position.y = 0.88*s; head.scale.y = 1.05; head.castShadow = true; c.add(head);
  const hair = new THREE.Mesh(new THREE.SphereGeometry(0.16*s, 10, 8, 0, Math.PI*2, 0, Math.PI*0.6), clayMat(P.charcoal ?? 0x202425));
  hair.position.y = 0.9*s; c.add(hair);
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
