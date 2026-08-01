import Fastify from 'fastify';
import fastifyWebsocket from '@fastify/websocket';
import fastifyStatic from '@fastify/static';
import { nanoid } from 'nanoid';
import path from 'path';
import { fileURLToPath } from 'url';
import { JobDispatcher } from './job-dispatcher.js';
import { SceneCompiler } from './scene-compiler.js';
import { XiaomiProvider } from './xiaomi-provider.js';
import { ClaudeWorker } from './claude-worker.js';
import { JobOrchestrator } from './orchestrator.js';
import { TemporalEngine } from './temporal-engine.js';
import { CONFIG } from '../config.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = Fastify({ logger: false });
await app.register(fastifyWebsocket);
await app.register(fastifyStatic, {
  root: path.join(__dirname, '../clients'),
  prefix: '/'
});
await app.register(fastifyStatic, {
  root: path.join(__dirname, '../src'),
  prefix: '/src/',
  decorateReply: false
});

// ── Reconstruction Pipeline ────────────────────────────────
const ASSET_DIR = path.resolve(__dirname, CONFIG.ASSET_DIR);
const K230_BASE_URL = CONFIG.K230_URL;

const sceneCompiler = new SceneCompiler();
const jobDispatcher = new JobDispatcher(ASSET_DIR, K230_BASE_URL);

// Forward scene updates from compiler to all desktop WebSocket clients
sceneCompiler.onSceneUpdate((update) => {
  for (const session of sessions.values()) {
    const targets = [session.desktop, session.mobile];
    const msg = JSON.stringify(update);
    for (const ws of targets) {
      if (ws && ws.readyState === 1) {
        ws.send(msg);
      }
    }
  }
});

// Forward job events as reconstruction.progress to all clients
jobDispatcher.on('job:queued', (data) => {
  broadcastGlobal({ type: 'scene.reconstruction.progress', phase: 'queued', ...data });
});
jobDispatcher.on('job:completed', (data) => {
  broadcastGlobal({ type: 'scene.reconstruction.progress', phase: 'completed', ...data });
  // Compile scene result and broadcast updates to all clients
  if (data.result) {
    const updates = sceneCompiler.compileReconstructionResult(data.result);
    if (Array.isArray(updates)) {
      for (const update of updates) {
        broadcastGlobal(update);
      }
    }
  }
});
jobDispatcher.on('job:failed', (data) => {
  broadcastGlobal({ type: 'scene.reconstruction.progress', phase: 'failed', ...data });
});

// Start job dispatcher (begins polling K230 receiver)
jobDispatcher.start().then(() => {
  console.log('JobDispatcher started — polling K230 receiver at', K230_BASE_URL);
}).catch(err => {
  console.warn('JobDispatcher failed to start:', err.message);
});

// ── Orchestrator Pipeline ──────────────────────────────────
// The orchestrator coordinates the full two-phase pipeline:
//   FAST PATH  : Xiaomi vision -> CanonicalSceneSpec -> Clay blockout -> instant display
//   REFINEMENT : Claude Worker -> refined geometry -> hot swap

const JOBS_DIR = path.resolve(__dirname, '../runtime/jobs');

const xiaomiProvider = new XiaomiProvider({
  apiKey: process.env.XIAOMI_API_KEY || '',
  mock: !process.env.XIAOMI_API_KEY, // mock mode by default for demo
});

// ClaudeWorker needs a forge scripts dir; fall back to the scripts dir if not set
const forgeScriptsDir = process.env.FORGE_SCRIPTS_DIR || path.resolve(__dirname, '../scripts');
const claudeWorker = new ClaudeWorker({
  forgeScriptsDir,
  maxConcurrent: 1,
  defaultTimeoutMs: 120_000,
});

const orchestrator = new JobOrchestrator({
  xiaomiProvider,
  claudeWorker,
  sceneCompiler,
  jobsDir: JOBS_DIR,
  maxConcurrent: 1,
});

// Forward orchestrator events to all WebSocket clients
orchestrator.on('blockout:ready', (data) => {
  broadcastGlobal({
    type: 'scene.update',
    action: 'blockout',
    ...data,
  });
  // Also broadcast on the scene WS channel
  broadcastSceneWs({
    type: 'scene.update',
    action: 'blockout',
    ...data,
  });
});

orchestrator.on('entity:refined', (data) => {
  broadcastGlobal({
    type: 'scene.entity.updated',
    action: 'refined',
    ...data,
  });
  broadcastSceneWs({
    type: 'scene.entity.updated',
    action: 'refined',
    ...data,
  });
});

orchestrator.on('job:progress', (data) => {
  broadcastGlobal({
    type: 'scene.reconstruction.progress',
    ...data,
  });
});

orchestrator.on('job:completed', (data) => {
  broadcastGlobal({
    type: 'scene.reconstruction.progress',
    phase: 'completed',
    ...data,
  });
});

orchestrator.on('job:failed', (data) => {
  broadcastGlobal({
    type: 'scene.reconstruction.progress',
    phase: 'failed',
    ...data,
  });
});

orchestrator.on('job:refinement-error', (data) => {
  broadcastGlobal({
    type: 'scene.reconstruction.progress',
    phase: 'refinement-error',
    ...data,
  });
});

// TemporalEngine instance (lazily created when a scene is loaded)
let temporalEngine = null;

console.log('Orchestrator pipeline initialized (mock mode:', !process.env.XIAOMI_API_KEY, ')');
console.log('Jobs directory:', JOBS_DIR);

// ── Session Store ──────────────────────────────────────────
const sessions = new Map();

function createSession() {
  const id = nanoid(6).toUpperCase();
  const session = {
    id,
    desktop: null,
    mobile: null,
    state: {
      timeValue: 0,
      selectedEntity: null,
      isReady: false
    },
    createdAt: Date.now()
  };
  sessions.set(id, session);
  return session;
}

function getSession(id) {
  return sessions.get(id);
}

// Broadcast to all clients in a session except sender
function broadcast(session, sender, data) {
  const msg = JSON.stringify(data);
  [session.desktop, session.mobile].forEach(ws => {
    if (ws && ws !== sender && ws.readyState === 1) {
      ws.send(msg);
    }
  });
}

// Broadcast to all connected clients across all sessions
function broadcastGlobal(data) {
  const msg = JSON.stringify(data);
  for (const session of sessions.values()) {
    [session.desktop, session.mobile].forEach(ws => {
      if (ws && ws.readyState === 1) {
        ws.send(msg);
      }
    });
  }
}

// Broadcast to all scene WebSocket clients
function broadcastSceneWs(data) {
  const msg = JSON.stringify(data);
  for (const ws of sceneWsClients) {
    if (ws.readyState === 1) {
      ws.send(msg);
    }
  }
}

// ── REST API ───────────────────────────────────────────────

app.get('/api/session', (req, reply) => {
  const session = createSession();
  return { sessionId: session.id };
});

app.get('/api/session/:id', (req, reply) => {
  const session = getSession(req.params.id);
  if (!session) return reply.code(404).send({ error: 'Session not found' });
  return {
    sessionId: session.id,
    hasDesktop: !!session.desktop,
    hasMobile: !!session.mobile,
    state: session.state
  };
});

// ── Reconstruction API ────────────────────────────────────

app.post('/api/reconstruct', async (req, reply) => {
  const { imageUrl, temporalTarget, type, priority } = req.body || {};
  if (!imageUrl) {
    return reply.code(400).send({ error: 'imageUrl is required' });
  }

  // Derive a frame info object from the image URL
  const filename = imageUrl.split('/').pop() || 'capture.jpg';
  const frameInfo = {
    filename,
    path: imageUrl,
    timestamp: Date.now(),
  };

  const jobId = jobDispatcher.enqueueJob(
    frameInfo,
    type || 'initial_reconstruction',
    temporalTarget ?? 0.0,
    priority || 'normal',
  );

  return { jobId, status: 'pending' };
});

app.get('/api/jobs', (req, reply) => {
  const { status, type, priority } = req.query || {};
  const jobs = jobDispatcher.listJobs({ status, type, priority });
  return { jobs };
});

app.get('/api/jobs/:id', (req, reply) => {
  const job = jobDispatcher.getJobStatus(req.params.id);
  if (!job) return reply.code(404).send({ error: 'Job not found' });
  return job;
});

// ── Orchestrator Reconstruction API ────────────────────────────
// These endpoints use the full orchestrator pipeline (Xiaomi -> Clay -> Claude).

app.post('/api/orchestrator/reconstruct', async (req, reply) => {
  const { photoPath, source, temporalTarget, priority, constraints } = req.body || {};
  if (!photoPath) {
    return reply.code(400).send({ error: 'photoPath is required (absolute path to photo file)' });
  }

  try {
    const jobId = await orchestrator.submitPhoto(photoPath, {
      source: source || 'upload',
      temporalTarget,
      priority: priority || 'normal',
      constraints,
    });
    return { jobId, status: 'pending' };
  } catch (err) {
    return reply.code(500).send({ error: err.message });
  }
});

app.get('/api/orchestrator/jobs', (req, reply) => {
  const { status } = req.query || {};
  const jobs = orchestrator.listJobs({ status });
  return { jobs };
});

app.get('/api/orchestrator/jobs/:id', (req, reply) => {
  const job = orchestrator.getJob(req.params.id);
  if (!job) return reply.code(404).send({ error: 'Job not found' });
  return job;
});

app.get('/api/scene', (req, reply) => {
  const manifest = sceneCompiler.getSceneManifest();
  return manifest;
});

// Per-session scene endpoint — returns a SceneFixture for the desktop to render.
// If the SceneCompiler has entities for this session, returns them as a fixture.
// Otherwise returns 404 so the desktop shows its waiting state.
app.get('/api/scene/:sessionId', (req, reply) => {
  const session = getSession(req.params.sessionId);
  if (!session) return reply.code(404).send({ error: 'Session not found' });

  // If the session has a stored fixture, return it
  if (session.sceneFixture) {
    return session.sceneFixture;
  }

  // Fall back to the compiler manifest — if it has entities, wrap as fixture
  const manifest = sceneCompiler.getSceneManifest();
  if (manifest.entities && manifest.entities.length > 0) {
    return manifest;
  }

  return reply.code(404).send({ error: 'No scene available yet' });
});

// ── WebSocket ──────────────────────────────────────────────

app.get('/ws', { websocket: true }, (socket, req) => {
  const sessionId = req.query.session;
  const role = req.query.role; // 'desktop' or 'mobile'
  const session = getSession(sessionId);

  if (!session || !['desktop', 'mobile'].includes(role)) {
    socket.send(JSON.stringify({ type: 'error', message: 'Invalid session or role' }));
    socket.close();
    return;
  }

  // Register connection
  session[role] = socket;
  socket.send(JSON.stringify({ type: 'connected', role, sessionId }));

  // Notify peer
  const peer = role === 'desktop' ? session.mobile : session.desktop;
  if (peer && peer.readyState === 1) {
    peer.send(JSON.stringify({ type: 'peer.connected', role }));
  }

  // If desktop connects and scene is ready
  if (role === 'desktop') {
    session.state.isReady = true;
  }

  // Handle messages
  socket.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw);

      switch (msg.type) {
        case 'time.seek':
          session.state.timeValue = msg.value;
          broadcast(session, socket, {
            type: 'time.seek',
            value: msg.value,
            source: role
          });
          break;

        case 'entity.select':
          session.state.selectedEntity = msg.entityId;
          broadcast(session, socket, {
            type: 'entity.select',
            entityId: msg.entityId,
            source: role
          });
          break;

        case 'entity.deselect':
          session.state.selectedEntity = null;
          broadcast(session, socket, {
            type: 'entity.deselect',
            source: role
          });
          break;

        case 'capture.uploaded':
          // Forward photo metadata to desktop
          broadcast(session, socket, {
            type: 'capture.uploaded',
            imageUrl: msg.imageUrl,
            source: role
          });
          break;

        case 'reconstruction.start': {
          // Trigger a new reconstruction job from a WebSocket client
          const frameInfo = {
            filename: msg.filename || 'ws-capture.jpg',
            path: msg.imageUrl || msg.path || '',
            timestamp: Date.now(),
          };
          const jobId = jobDispatcher.enqueueJob(
            frameInfo,
            msg.reconstructionType || 'initial_reconstruction',
            msg.temporalTarget ?? 0.0,
            msg.priority || 'normal',
          );
          socket.send(JSON.stringify({ type: 'reconstruction.queued', jobId }));
          break;
        }

        case 'orchestrator.reconstruct': {
          // Full orchestrator pipeline: Xiaomi -> Clay blockout -> Claude refinement
          const photoPath = msg.photoPath || msg.path || '';
          if (!photoPath) {
            socket.send(JSON.stringify({ type: 'error', message: 'photoPath is required' }));
            break;
          }
          orchestrator.submitPhoto(photoPath, {
            source: msg.source || 'ws',
            temporalTarget: msg.temporalTarget,
            priority: msg.priority || 'normal',
            constraints: msg.constraints,
          }).then(jobId => {
            socket.send(JSON.stringify({ type: 'orchestrator.queued', jobId }));
          }).catch(err => {
            socket.send(JSON.stringify({ type: 'error', message: err.message }));
          });
          break;
        }

        case 'reconstruction.status': {
          // Query job status
          const job = msg.jobId ? jobDispatcher.getJobStatus(msg.jobId) : null;
          socket.send(JSON.stringify({
            type: 'reconstruction.status',
            jobId: msg.jobId,
            job: job || null,
            found: !!job,
          }));
          break;
        }

        case 'scene.manifest.request': {
          // Send full scene state to the requesting client
          const manifest = sceneCompiler.getSceneManifest();
          socket.send(JSON.stringify({
            type: 'scene.state',
            ...manifest,
          }));
          break;
        }

        case 'scene.update':
          // Scene update from an external source — re-broadcast to peers
          broadcast(session, socket, msg);
          break;

        case 'ping':
          socket.send(JSON.stringify({ type: 'pong' }));
          break;

        default:
          // Forward unknown messages
          broadcast(session, socket, msg);
      }
    } catch (e) {
      // ignore malformed
    }
  });

  socket.on('close', () => {
    session[role] = null;
    const otherRole = role === 'desktop' ? 'mobile' : 'desktop';
    const other = session[otherRole];
    if (other && other.readyState === 1) {
      other.send(JSON.stringify({ type: 'peer.disconnected', role }));
    }

    // Cleanup empty sessions after 5 min
    if (!session.desktop && !session.mobile) {
      setTimeout(() => {
        if (!session.desktop && !session.mobile) {
          sessions.delete(sessionId);
        }
      }, 5 * 60 * 1000);
    }
  });
});

// ── Scene WebSocket (SceneRuntime pipeline) ────────────────
// Dedicated endpoint for the Three.js SceneRuntime to receive
// scene updates without requiring a session.

const sceneWsClients = new Set();

// Forward scene updates from compiler to scene WebSocket clients
sceneCompiler.onSceneUpdate((update) => {
  const msg = JSON.stringify(update);
  for (const ws of sceneWsClients) {
    if (ws.readyState === 1) {
      ws.send(msg);
    }
  }
});

app.get('/ws/scene', { websocket: true }, (socket, req) => {
  sceneWsClients.add(socket);
  console.log('[Scene WS] Client connected. Total:', sceneWsClients.size);

  socket.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw);
      if (msg.type === 'scene.manifest.request') {
        const manifest = sceneCompiler.getSceneManifest();
        socket.send(JSON.stringify({
          type: 'scene.response',
          requestId: msg.timestamp,
          payload: { success: true, data: { manifest } },
        }));
      }
    } catch {
      // ignore
    }
  });

  socket.on('close', () => {
    sceneWsClients.delete(socket);
    console.log('[Scene WS] Client disconnected. Total:', sceneWsClients.size);
  });
});

// ── Start ──────────────────────────────────────────────────

app.listen({ port: CONFIG.API_PORT, host: '0.0.0.0' }, (err) => {
  if (err) {
    console.error(err);
    process.exit(1);
  }
  console.log(`Temporal World Server running on http://0.0.0.0:${CONFIG.API_PORT}`);
  console.log(`Desktop: http://localhost:${CONFIG.API_PORT}/desktop.html`);
  console.log(`Mobile:  http://localhost:${CONFIG.API_PORT}/mobile.html?session=XXXXXX`);
});
