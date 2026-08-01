import type { SceneFixture, TimelineInterval } from '@fumira/contracts';
import {
  createScene,
  loadEntities,
  startAnimationLoop,
  type AnimationController,
} from '@fumira/scene-runtime';
import QRCode from 'qrcode';
// import fixtureData from '../../../fixtures/campus-gate/scene.json';
import fixtureData from '../../../fixtures/reconstruct-demo/scene.json';

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
let heartbeatTimer: number | null = null;

async function initSession(fixture: SceneFixture): Promise<void> {
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

    connectWebSocket(fixture);
  } catch {
    console.log('Running in standalone mode (no server)');
    document.getElementById('qr-panel')?.classList.add('hidden');
  }
}

function connectWebSocket(fixture: SceneFixture): void {
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
    handleWSMessage(msg, fixture);
  };

  ws.onclose = () => {
    if (heartbeatTimer !== null) window.clearInterval(heartbeatTimer);
    heartbeatTimer = null;
    updateConnectionStatus('disconnected');
    setTimeout(() => connectWebSocket(fixture), 3000);
  };
}

function handleWSMessage(msg: {
  type: string;
  value?: number;
  entityId?: string;
  sessionId?: string;
  state?: 'paired' | 'waiting_for_phone' | 'waiting_for_desktop' | 'idle';
}, fixture: SceneFixture): void {
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
  const fixture = fixtureData as unknown as SceneFixture;

  // Create scene
  const canvas = document.getElementById('canvas') as HTMLCanvasElement;
  const sceneHandle = createScene(fixture, canvas);

  // Load entities
  const entities = loadEntities(fixture, sceneHandle.scene, sceneHandle);

  // Start animation
  animationController = startAnimationLoop(sceneHandle, entities, fixture, {
    onUpdateUI: (year) => updateUI(year, fixture.temporalSpec.timelineIntervals),
  });

  // Session (WebSocket + QR)
  initSession(fixture);

  // Hide loading screen
  setTimeout(() => {
    document.getElementById('loading')?.classList.add('done');
  }, 800);
}

main();
