import type { SceneFixture, TimelineInterval } from '@fumira/contracts';
import * as THREE from 'three';
import {
  createScene,
  loadEntities,
  startAnimationLoop,
  type AnimationController,
  type EntityHandle,
  type SceneHandle,
} from '@fumira/scene-runtime';
import QRCode from 'qrcode';
import fixtureData from '../../../fixtures/street-scene/scene.json';

// ── Config ─────────────────────────────────────────────────
const API_BASE = window.location.origin;
const WS_BASE = `ws://${window.location.host}`;
const CURRENT_YEAR = 2026;

// ── UI ─────────────────────────────────────────────────────

function updateUI(year: number, intervals: TimelineInterval[]): void {
  const y = Math.round(year);
  const yearLabel = document.getElementById('year-label');
  const eraLabel = document.getElementById('era-label');
  const intervalCard = document.getElementById('interval-card');
  const intervalLabel = document.getElementById('interval-label');

  if (yearLabel) yearLabel.textContent = String(y);
  if (eraLabel) {
    eraLabel.textContent =
      y < 2020 ? 'PAST' : y <= 2028 ? 'PRESENT' : y <= 2040 ? 'NEAR FUTURE' : 'FUTURE';
  }

  const iv = intervals.find(iv => year >= iv.startYear && year <= iv.endYear);
  if (iv) {
    const icons: Record<string, string> = {
      stable: '●',
      gradual: '◐',
      event: '⚡',
      transition: '◑',
      settled: '○',
    };
    if (intervalCard) {
      intervalCard.innerHTML = `<span style="color:var(--fumira-orange)">${icons[iv.mode]} ${iv.mode.toUpperCase()}</span> — ${iv.narrative}`;
      intervalCard.classList.add('visible');
    }
    if (intervalLabel) intervalLabel.textContent = iv.narrative;
  } else {
    intervalCard?.classList.remove('visible');
    if (intervalLabel) intervalLabel.textContent = '';
  }
}

// ── Session (WebSocket + QR) ───────────────────────────────

let ws: WebSocket | null = null;
let sessionId: string | null = null;
let animationController: AnimationController | null = null;
let sceneHandle: SceneHandle | null = null;
let sceneEntities: EntityHandle[] = [];
let currentFixture = fixtureData as unknown as SceneFixture;
let heartbeatTimer: number | null = null;

function disposeObject(object: THREE.Object3D): void {
  object.traverse((child) => {
    const mesh = child as THREE.Mesh;
    mesh.geometry?.dispose?.();
    if (Array.isArray(mesh.material)) mesh.material.forEach(material => material.dispose());
    else (mesh.material as THREE.Material | undefined)?.dispose?.();
  });
}

function mountFixture(fixture: SceneFixture, source: 'initial' | 'server' | 'hot'): void {
  animationController?.dispose();
  animationController = null;
  if (sceneHandle) {
    sceneHandle.controls.dispose();
    disposeObject(sceneHandle.scene);
    sceneHandle.scene.clear();
  }

  const canvas = document.getElementById('canvas') as HTMLCanvasElement;
  currentFixture = fixture;
  sceneHandle = createScene(fixture, canvas);
  sceneEntities = loadEntities(fixture, sceneHandle.scene, sceneHandle);
  animationController = startAnimationLoop(sceneHandle, sceneEntities, fixture, {
    onUpdateUI: (year) => updateUI(year, fixture.temporalSpec.timelineIntervals),
  });
  updateSceneStatus(source === 'hot' ? 'HOT SWAPPED · SCENE GRAPH READY' : source === 'server' ? 'SERVER FIXTURE · SCENE GRAPH READY' : 'LOCAL FIXTURE · SCENE GRAPH READY');
}

function updateSceneStatus(text: string): void {
  const status = document.getElementById('scene-status');
  if (status) status.textContent = text;
}

async function reloadSceneFromServer(source: 'server' | 'hot' = 'hot'): Promise<void> {
  if (!sessionId) return;
  try {
    const res = await fetch(`${API_BASE}/api/scene/${sessionId}`, { cache: 'no-store' });
    if (!res.ok) return;
    const next = await res.json() as SceneFixture;
    if (!next || !Array.isArray(next.entities) || !next.sceneGraph) {
      updateSceneStatus('SERVER SCENE REJECTED · MISSING SCENE GRAPH');
      return;
    }
    mountFixture(next, source);
  } catch {
    updateSceneStatus('SCENE SERVER UNAVAILABLE · LOCAL FIXTURE ACTIVE');
  }
}

async function initSession(): Promise<void> {
  try {
    const res = await fetch(`${API_BASE}/api/session`);
    const data = await res.json();
    sessionId = data.sessionId;
    const sessionIdEl = document.getElementById('session-id');
    if (sessionIdEl) sessionIdEl.textContent = sessionId;

    const mobileUrl = typeof data.pairingURL === 'string'
      ? data.pairingURL
      : `${API_BASE}/mobile.html?session=${sessionId}`;
    const qrEl = document.getElementById('qr-code');
    if (qrEl) {
      await QRCode.toCanvas(qrEl as HTMLCanvasElement, mobileUrl, {
        width: 160,
        margin: 1,
        color: { dark: '#202425', light: '#F2EEE5' },
      });
    }

    connectWebSocket();
    await reloadSceneFromServer('server');
  } catch {
    console.log('Running in standalone mode (no server)');
    document.getElementById('qr-panel')?.classList.add('hidden');
    updateSceneStatus('STANDALONE · LOCAL SCENE GRAPH');
  }
}

function connectWebSocket(): void {
  ws = new WebSocket(`${WS_BASE}/ws?session=${sessionId}&role=desktop`);

  ws.onopen = () => {
    console.log('Desktop WebSocket connected');
    ws?.send(JSON.stringify({ type: 'hello', role: 'desktop', protocolVersion: 1 }));
    heartbeatTimer = window.setInterval(() => {
      if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping' }));
    }, 10_000);
  };

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    handleWSMessage(msg);
  };

  ws.onclose = () => {
    if (heartbeatTimer !== null) window.clearInterval(heartbeatTimer);
    heartbeatTimer = null;
    updateConnectionStatus('disconnected');
    setTimeout(() => connectWebSocket(), 3000);
  };
}

function handleWSMessage(msg: {
  type: string;
  value?: number;
  entityId?: string;
  sessionId?: string;
  fixture?: SceneFixture;
  state?: 'paired' | 'waiting_for_phone' | 'waiting_for_desktop' | 'idle';
}): void {
  switch (msg.type) {
    case 'connected':
      console.log('Desktop registered for session', msg.sessionId);
      break;
    case 'handshake.accepted':
      updateConnectionStatus('waiting');
      break;
    case 'pairing.status':
      updatePairingStatus(msg.state ?? 'idle');
      break;
    case 'peer.connected':
      updateConnectionStatus('connected');
      document.getElementById('qr-panel')?.classList.add('connected');
      document.getElementById('qr-panel')?.classList.remove('waiting');
      const statusEl = document.getElementById('qr-status');
      if (statusEl) {
        statusEl.textContent = 'PHONE CONNECTED';
        statusEl.className = 'connected';
      }
      break;
    case 'peer.disconnected':
      updateConnectionStatus('disconnected');
      document.getElementById('qr-panel')?.classList.remove('connected');
      document.getElementById('qr-panel')?.classList.add('waiting');
      const statusEl2 = document.getElementById('qr-status');
      if (statusEl2) {
        statusEl2.textContent = 'PHONE DISCONNECTED';
        statusEl2.className = 'waiting';
      }
      break;
    case 'scene.ready':
    case 'scene.update':
      if (msg.fixture?.sceneGraph) mountFixture(msg.fixture, 'hot');
      else void reloadSceneFromServer('hot');
      break;
    case 'time.seek':
      if (msg.value !== undefined) {
        applyTimeFromRemote(msg.value);
      }
      break;
  }
}

function updatePairingStatus(state: 'paired' | 'waiting_for_phone' | 'waiting_for_desktop' | 'idle'): void {
  const panel = document.getElementById('qr-panel');
  const statusEl = document.getElementById('qr-status');
  if (!panel || !statusEl) return;

  const paired = state === 'paired';
  panel.classList.toggle('connected', paired);
  panel.classList.toggle('waiting', !paired);
  statusEl.className = paired ? 'connected' : 'waiting';
  statusEl.textContent = paired
    ? 'PHONE PAIRED · HANDSHAKE OK'
    : state === 'waiting_for_phone'
      ? 'WAITING FOR PHONE'
      : state === 'waiting_for_desktop'
        ? 'PHONE WAITING FOR DESKTOP'
        : 'PAIRING SERVER READY';
  updateConnectionStatus(paired ? 'connected' : 'waiting');
}

function updateConnectionStatus(status: string): void {
  const dot = document.getElementById('connection-dot');
  const label = document.getElementById('connection-label');
  if (dot) dot.className = status === 'connected' ? 'connected' : status === 'disconnected' ? 'disconnected' : 'offline';
  if (label) {
    label.textContent =
      status === 'connected' ? 'PHONE CONNECTED' :
      status === 'disconnected' ? 'SERVER DISCONNECTED' : 'WAITING FOR PHONE';
  }
}

function applyTimeFromRemote(p: number): void {
  const years = Math.sign(p) * 36525 * Math.pow(Math.abs(p), 2.35) / 365.25;
  animationController?.setYear(CURRENT_YEAR + years);
}

// ── Bootstrap ──────────────────────────────────────────────

async function main(): Promise<void> {
  mountFixture(currentFixture, 'initial');

  // Session (WebSocket + QR)
  initSession();

  // Hide loading screen
  setTimeout(() => {
    document.getElementById('loading')?.classList.add('done');
  }, 800);
}

main();
