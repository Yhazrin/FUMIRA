#!/usr/bin/env node

/**
 * reconstruct-cli.js — CLI tool for submitting reconstruction jobs.
 *
 * Usage:
 *   node scripts/reconstruct-cli.js <photo-path> [options]
 *
 * Options:
 *   --source <source>       Source type: upload, k230, mobile (default: upload)
 *   --temporal <target>     Temporal target float (default: 0.0)
 *   --priority <priority>   Priority: normal, high (default: normal)
 *   --server <url>          Server URL (default: http://localhost:3210)
 *   --ws                    Use WebSocket instead of REST
 *
 * Examples:
 *   node scripts/reconstruct-cli.js /path/to/photo.jpg
 *   node scripts/reconstruct-cli.js /path/to/photo.jpg --priority high --temporal 0.5
 *   node scripts/reconstruct-cli.js /path/to/photo.jpg --ws
 */

import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ── Parse arguments ──────────────────────────────────────

const args = process.argv.slice(2);

if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
  console.log(`
reconstruct-cli.js — Submit a photo for temporal reconstruction

Usage:
  node scripts/reconstruct-cli.js <photo-path> [options]

Options:
  --source <source>       Source type: upload, k230, mobile (default: upload)
  --temporal <target>     Temporal target float in [-1, 1] (default: 0.0)
  --priority <priority>   Priority: normal, high (default: normal)
  --server <url>          Server URL (default: http://localhost:3210)
  --ws                    Use WebSocket instead of REST API
  --watch                 Watch job progress after submission
  --help, -h              Show this help

Examples:
  node scripts/reconstruct-cli.js /path/to/photo.jpg
  node scripts/reconstruct-cli.js /path/to/photo.jpg --priority high --temporal 0.5
  node scripts/reconstruct-cli.js /path/to/photo.jpg --ws --watch
`);
  process.exit(0);
}

function getArg(flag, defaultValue) {
  const idx = args.indexOf(flag);
  if (idx === -1 || idx >= args.length - 1) return defaultValue;
  return args[idx + 1];
}

const photoPath = args[0];
const source = getArg('--source', 'upload');
const temporalTarget = parseFloat(getArg('--temporal', '0.0'));
const priority = getArg('--priority', 'normal');
const serverUrl = getArg('--server', 'http://localhost:3210');
const useWs = args.includes('--ws');
const watch = args.includes('--watch');

// ── Validate ─────────────────────────────────────────────

if (!photoPath) {
  console.error('Error: photo path is required');
  process.exit(1);
}

const resolvedPath = path.resolve(photoPath);
if (!existsSync(resolvedPath)) {
  console.error(`Error: file not found: ${resolvedPath}`);
  process.exit(1);
}

// ── Submit via REST ──────────────────────────────────────

async function submitViaRest() {
  const url = `${serverUrl}/api/orchestrator/reconstruct`;
  console.log(`Submitting to ${url}...`);
  console.log(`  Photo: ${resolvedPath}`);
  console.log(`  Source: ${source}, Priority: ${priority}, Temporal: ${temporalTarget}`);

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      photoPath: resolvedPath,
      source,
      temporalTarget,
      priority,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    console.error(`Error: ${response.status} ${text}`);
    process.exit(1);
  }

  const result = await response.json();
  console.log(`Job submitted: ${result.jobId}`);
  console.log(`Status: ${result.status}`);

  if (watch) {
    await pollJob(result.jobId);
  }

  return result;
}

// ── Submit via WebSocket ─────────────────────────────────

async function submitViaWs() {
  const wsUrl = serverUrl.replace(/^http/, 'ws') + '/ws/scene';
  console.log(`Connecting to ${wsUrl}...`);

  // Dynamic import for ws (may not be installed)
  let WebSocket;
  try {
    const ws = await import('ws');
    WebSocket = ws.default;
  } catch {
    // Fall back to native WebSocket (Node 21+)
    WebSocket = globalThis.WebSocket;
    if (!WebSocket) {
      console.error('Error: "ws" package not available and native WebSocket not supported.');
      console.error('Install ws: npm install ws');
      process.exit(1);
    }
  }

  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);

    ws.on('open', () => {
      console.log('Connected. Submitting job...');
      ws.send(JSON.stringify({
        type: 'orchestrator.reconstruct',
        photoPath: resolvedPath,
        source,
        temporalTarget,
        priority,
      }));
    });

    ws.on('message', (data) => {
      const msg = JSON.parse(data.toString());

      if (msg.type === 'orchestrator.queued') {
        console.log(`Job submitted: ${msg.jobId}`);
        if (!watch) {
          ws.close();
          resolve(msg);
        }
      } else if (msg.type === 'scene.reconstruction.progress') {
        const pct = msg.percent != null ? ` (${msg.percent}%)` : '';
        console.log(`  [${msg.phase || msg.type}]${pct} ${msg.message || ''}`);
        if (msg.phase === 'completed' || msg.phase === 'failed') {
          ws.close();
          resolve(msg);
        }
      } else if (msg.type === 'scene.update') {
        console.log(`  [scene.update] action=${msg.action}, jobId=${msg.jobId}`);
      } else if (msg.type === 'scene.entity.updated') {
        console.log(`  [entity.refined] entityId=${msg.entityId}`);
      }
    });

    ws.on('error', (err) => {
      console.error('WebSocket error:', err.message);
      reject(err);
    });

    ws.on('close', () => {
      resolve();
    });
  });
}

// ── Poll job status ──────────────────────────────────────

async function pollJob(jobId) {
  console.log(`\nWatching job ${jobId}...`);
  let lastPhase = '';

  const poll = async () => {
    try {
      const res = await fetch(`${serverUrl}/api/orchestrator/jobs/${jobId}`);
      if (!res.ok) return null;
      return await res.json();
    } catch {
      return null;
    }
  };

  while (true) {
    const job = await poll();
    if (!job) {
      process.stdout.write('.');
      await new Promise(r => setTimeout(r, 2000));
      continue;
    }

    const phase = job.progress?.phase || job.status;
    const pct = job.progress?.percent;
    const msg = job.progress?.message || '';

    if (phase !== lastPhase) {
      console.log(`\n  [${phase}]${pct != null ? ` ${pct}%` : ''} ${msg}`);
      lastPhase = phase;
    } else if (pct != null) {
      process.stdout.write(`\r  ${pct}% ${msg}    `);
    }

    if (phase === 'completed' || phase === 'failed') {
      console.log('\n');
      console.log(JSON.stringify(job, null, 2));
      break;
    }

    await new Promise(r => setTimeout(r, 2000));
  }
}

// ── Main ─────────────────────────────────────────────────

async function main() {
  console.log('FUMIRA Temporal Reconstruction CLI\n');

  if (useWs) {
    await submitViaWs();
  } else {
    await submitViaRest();
  }
}

main().catch(err => {
  console.error('Fatal:', err.message);
  process.exit(1);
});
