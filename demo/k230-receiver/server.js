import Fastify from 'fastify';
import multipart from '@fastify/multipart';
import fastifyStatic from '@fastify/static';
import { randomUUID } from 'node:crypto';
import { writeFile, mkdir, readdir, stat } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// ─── K230 Camera Receiver ────────────────────────────────────────────────────
// Receives JPEG frames from Canaan Kendryte K230 AI vision boards.
//
// K230 typical send (C/Python):
//   POST http://<host>:19999/k230/frame
//   Content-Type: image/jpeg
//   X-K230-Frame-Id: 42
//   X-K230-Timestamp: 1722500000
//   <raw jpeg bytes>
//
// Endpoints:
//   POST /k230/frame      — raw JPEG body (primary, matches K230 SDK习惯)
//   POST /k230/upload      — multipart form (备选)
//   GET  /k230/latest       — 最新帧 (for polling)
//   GET  /k230/list         — 已接收帧列表
//   GET  /                  — Web dashboard

const __dirname = dirname(fileURLToPath(import.meta.url));
const UPLOAD_DIR = join(__dirname, 'received');
const PORT = Number(process.env.PORT || '19999');

await mkdir(UPLOAD_DIR, { recursive: true });

const app = Fastify({ logger: true });

// K230 boards POST raw JPEG bytes with Content-Type: image/jpeg.
// Fastify's default body parser doesn't handle binary, so we add
// image/jpeg and application/octet-stream as raw-parseable types.
app.addContentTypeParser('image/jpeg', { parseAs: 'buffer' }, (req, body, done) => {
  done(null, body);
});
app.addContentTypeParser('image/png', { parseAs: 'buffer' }, (req, body, done) => {
  done(null, body);
});
app.addContentTypeParser('application/octet-stream', { parseAs: 'buffer' }, (req, body, done) => {
  done(null, body);
});

await app.register(multipart, {
  limits: { fileSize: 50 * 1024 * 1024 },
});

await app.register(fastifyStatic, {
  root: UPLOAD_DIR,
  prefix: '/frames/',
  decorateReply: false,
});

// Track latest frame for /k230/latest
let latestFrame = null;

// ─── Health ──────────────────────────────────────────────────────────────────
app.get('/health', async () => ({
  status: 'ok',
  board: 'k230',
  receivedFrames: (await readdir(UPLOAD_DIR)).filter(f => f.endsWith('.jpg')).length,
  latestFrame,
}));

// ─── K230 raw JPEG frame (primary endpoint) ─────────────────────────────────
// K230 SDK typically does:
//   http_post(url, jpeg_bytes, headers={"Content-Type": "image/jpeg"})
app.post('/k230/frame', async (request, reply) => {
  // Body is parsed as Buffer by the custom content-type parser above.
  const buffer = Buffer.isBuffer(request.body) ? request.body : null;

  if (!buffer || buffer.byteLength === 0) {
    return reply.code(400).send({ error: 'empty_body' });
  }

  // Validate JPEG magic bytes (FFD8)
  if (buffer[0] !== 0xFF || buffer[1] !== 0xD8) {
    return reply.code(400).send({ error: 'not_jpeg', message: 'Expected JPEG (FF D8)' });
  }

  // Extract K230 metadata from headers
  const frameId = request.headers['x-k230-frame-id'] || null;
  const ts = request.headers['x-k230-timestamp'] || null;

  const filename = buildFilename(frameId);
  await writeFile(join(UPLOAD_DIR, filename), buffer);
  latestFrame = filename;

  app.log.info({
    event: 'k230_frame',
    filename,
    size: buffer.byteLength,
    frameId,
    timestamp: ts,
  });

  return reply.code(201).send({
    ok: true,
    filename,
    size: buffer.byteLength,
    frameId,
    url: `/frames/${filename}`,
  });
});

// ─── K230 multipart upload (备选) ───────────────────────────────────────────
app.post('/k230/upload', async (request, reply) => {
  const file = await request.file();
  if (!file) {
    return reply.code(400).send({ error: 'no_file' });
  }

  const buffer = await file.toBuffer();
  if (buffer.byteLength === 0) {
    return reply.code(400).send({ error: 'empty_file' });
  }

  const frameId = request.headers['x-k230-frame-id'] || null;
  const filename = buildFilename(frameId);
  await writeFile(join(UPLOAD_DIR, filename), buffer);
  latestFrame = filename;

  app.log.info({ event: 'k230_upload', filename, size: buffer.byteLength });

  return reply.code(201).send({
    ok: true,
    filename,
    size: buffer.byteLength,
    url: `/frames/${filename}`,
  });
});

// ─── Latest frame (for polling from iOS app) ─────────────────────────────────
app.get('/k230/latest', async (request, reply) => {
  if (!latestFrame) {
    return reply.code(404).send({ error: 'no_frames' });
  }
  return reply.redirect(`/frames/${latestFrame}`);
});

// ─── Frame list ──────────────────────────────────────────────────────────────
app.get('/k230/list', async (request) => {
  const limit = Math.min(Number(request.query.limit || 100), 500);
  const files = (await readdir(UPLOAD_DIR))
    .filter(f => f.endsWith('.jpg'))
    .sort()
    .reverse()
    .slice(0, limit);

  return { count: files.length, files, latestFrame };
});

// ─── Dashboard ───────────────────────────────────────────────────────────────
app.get('/', async (request, reply) => {
  const files = (await readdir(UPLOAD_DIR))
    .filter(f => f.endsWith('.jpg'))
    .sort()
    .reverse()
    .slice(0, 60);

  const latestStat = latestFrame
    ? await stat(join(UPLOAD_DIR, latestFrame)).catch(() => null)
    : null;

  reply.type('text/html');
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>K230 Frame Receiver</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, system-ui, sans-serif; background: #1a1c1e; color: #F2EEE5; padding: 16px; }
    header { display: flex; align-items: center; gap: 12px; margin-bottom: 16px; }
    header h1 { font-size: 18px; font-weight: 600; }
    .chip { display: inline-block; background: #FF672A; color: #fff; font-size: 11px; font-weight: 700; padding: 2px 8px; border-radius: 4px; letter-spacing: 0.5px; }
    .stats { display: flex; gap: 20px; font-size: 13px; opacity: 0.7; margin-bottom: 16px; }
    .stats span { display: flex; align-items: center; gap: 4px; }
    .stats .dot { width: 6px; height: 6px; border-radius: 50%; background: #B7D83D; display: inline-block; }
    .endpoint { background: #2a2e2f; border-radius: 8px; padding: 12px 16px; margin-bottom: 16px; font-family: 'SF Mono', monospace; font-size: 12px; line-height: 1.6; }
    .endpoint code { color: #B7D83D; }
    .endpoint .label { color: #FF672A; font-weight: 600; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 8px; }
    .card { background: #2a2e2f; border-radius: 8px; overflow: hidden; position: relative; }
    .card img { width: 100%; aspect-ratio: 4/3; object-fit: cover; display: block; }
    .card .meta { padding: 6px 10px; font-size: 10px; opacity: 0.5; font-family: monospace; }
    .latest { position: relative; }
    .latest::after { content: 'LATEST'; position: absolute; top: 6px; right: 6px; background: #FF672A; color: #fff; font-size: 9px; font-weight: 700; padding: 2px 6px; border-radius: 3px; }
    .empty { opacity: 0.4; padding: 60px; text-align: center; font-size: 14px; }
    .refresh { position: fixed; bottom: 20px; right: 20px; background: #FF672A; color: #fff; border: none; width: 44px; height: 44px; border-radius: 50%; font-size: 18px; cursor: pointer; box-shadow: 0 2px 12px rgba(255,103,42,0.4); }
  </style>
</head>
<body>
  <header>
    <h1>K230 Frame Receiver</h1>
    <span class="chip">K230</span>
  </header>
  <div class="stats">
    <span><span class="dot"></span> Port ${PORT}</span>
    <span>📷 ${files.length} frames</span>
    ${latestFrame ? `<span>Latest: ${latestFrame}</span>` : ''}
  </div>
  <div class="endpoint">
    <div><span class="label">POST</span> <code>http://<ip>:${PORT}/k230/frame</code> — raw JPEG body</div>
    <div><span class="label">POST</span> <code>http://<ip>:${PORT}/k230/upload</code> — multipart form</div>
    <div><span class="label">GET</span>  <code>http://<ip>:${PORT}/k230/latest</code> — latest frame</div>
  </div>
  ${files.length === 0
    ? '<div class="empty">Waiting for K230 frames...</div>'
    : `<div class="grid">${files.map((f, i) => `
      <div class="card${i === 0 ? ' latest' : ''}">
        <a href="/frames/${f}" target="_blank"><img src="/frames/${f}" loading="lazy" alt="${f}"></a>
        <div class="meta">${f}</div>
      </div>`).join('')}</div>`}
  <button class="refresh" onclick="location.reload()" title="Refresh">↻</button>
  <script>
    // Auto-refresh every 3s when tab is visible
    let timer;
    function startAutoRefresh() { timer = setInterval(() => location.reload(), 3000); }
    function stopAutoRefresh() { clearInterval(timer); }
    document.addEventListener('visibilitychange', () => {
      document.hidden ? stopAutoRefresh() : startAutoRefresh();
    });
    if (!document.hidden) startAutoRefresh();
  </script>
</body>
</html>`;
});

// ─── Helpers ─────────────────────────────────────────────────────────────────
function buildFilename(frameId) {
  const ts = new Date();
  const tsStr = `${ts.getFullYear()}${String(ts.getMonth()+1).padStart(2,'0')}${String(ts.getDate()).padStart(2,'0')}_${String(ts.getHours()).padStart(2,'0')}${String(ts.getMinutes()).padStart(2,'0')}${String(ts.getSeconds()).padStart(2,'0')}`;
  const id = frameId ? `_f${String(frameId).padStart(6, '0')}` : `_${randomUUID().slice(0, 8)}`;
  return `k230_${tsStr}${id}.jpg`;
}

// ─── Start ───────────────────────────────────────────────────────────────────
app.listen({ port: PORT, host: '0.0.0.0' }, (err) => {
  if (err) { app.log.error(err); process.exit(1); }
  console.log(`\n  📷 K230 Frame Receiver`);
  console.log(`  ──────────────────────`);
  console.log(`  Local:   http://localhost:${PORT}`);
  console.log(`  Network: http://0.0.0.0:${PORT}`);
  console.log(`  POST     /k230/frame   — raw JPEG body (primary)`);
  console.log(`  POST     /k230/upload  — multipart form`);
  console.log(`  GET      /k230/latest  — latest frame redirect`);
  console.log(`  GET      /k230/list    — frame list JSON\n`);
});
