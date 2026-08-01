import { EventEmitter } from 'node:events';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdir, writeFile, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';

/**
 * JobDispatcher — Backend job dispatcher for FUMIRA's reconstruction pipeline.
 *
 * Receives K230 frame notifications, queues reconstruction jobs, spawns
 * Claude CLI workers, and stores results in the asset directory.
 */
export class JobDispatcher extends EventEmitter {
  /** @type {Map<string, object>} */
  #jobs = new Map();
  /** @type {Array<{jobId: string, proc: import('node:child_process').ChildProcess}>} */
  #activeWorkers = [];
  /** @type {Array<string>} pending job ids sorted high-first */
  #pendingQueue = [];
  /** @type {Set<string>} */
  #processingIds = new Set();
  /** @type {Array<Function>} */
  #completionHandlers = [];

  #assetDir;
  #k230BaseUrl;
  #pollTimer = null;
  #pollIntervalMs = 3000;
  #maxConcurrentWorkers = 2;
  #lastK230Timestamp = 0;
  #started = false;

  /**
   * @param {string} assetDir  — absolute path to the asset store directory
   * @param {string} k230BaseUrl — base URL of the K230 receiver (e.g. http://localhost:19999)
   */
  constructor(assetDir, k230BaseUrl) {
    super();
    this.#assetDir = path.resolve(assetDir);
    this.#k230BaseUrl = k230BaseUrl.replace(/\/+$/, '');
  }

  // ── Public API ─────────────────────────────────────────────

  /**
   * Begin polling the K230 receiver for new frames.
   * Resolves once the first poll cycle is scheduled.
   */
  async start() {
    if (this.#started) return;
    this.#started = true;

    await mkdir(this.#assetDir, { recursive: true });
    await this.#recoverPersistedJobs();

    this.#pollTimer = setInterval(() => this.#pollK230(), this.#pollIntervalMs);
    // Fire immediately so we don't wait for the first interval.
    this.#pollK230();

    this.emit('started');
  }

  /**
   * Create and enqueue a reconstruction job.
   *
   * @param {{ filename: string, path: string, timestamp: number }} frameInfo
   * @param {'initial_reconstruction' | 'refinement' | 'correction'} type
   * @param {number} temporalTarget  — normalised value in [-1, 1]
   * @param {'normal' | 'high'} [priority='normal']
   * @returns {string} the new job id
   */
  enqueueJob(frameInfo, type, temporalTarget = 0.0, priority = 'normal') {
    const job = this.#createJob(frameInfo, type, temporalTarget, priority);
    this.#jobs.set(job.id, job);
    this.#addToQueue(job.id, priority);
    this.#persistJob(job);

    this.emit('job:queued', { jobId: job.id, type, priority });

    // Try to dispatch immediately.
    this.#dispatch();

    return job.id;
  }

  /**
   * Get the current state of a job.
   * @param {string} jobId
   * @returns {object | undefined}
   */
  getJobStatus(jobId) {
    const job = this.#jobs.get(jobId);
    return job ? { ...job } : undefined;
  }

  /**
   * List jobs matching optional filters.
   *
   * @param {{ status?: string, type?: string, priority?: string }} [filters]
   * @returns {object[]}
   */
  listJobs(filters = {}) {
    let jobs = Array.from(this.#jobs.values());

    if (filters.status)   jobs = jobs.filter(j => j.status   === filters.status);
    if (filters.type)     jobs = jobs.filter(j => j.type     === filters.type);
    if (filters.priority) jobs = jobs.filter(j => j.priority === filters.priority);

    return jobs.map(j => ({ ...j }));
  }

  /**
   * Cancel a job. If it is currently processing the worker is killed.
   * @param {string} jobId
   * @returns {boolean} true if the job was found and cancelled
   */
  cancelJob(jobId) {
    const job = this.#jobs.get(jobId);
    if (!job) return false;

    if (job.status === 'completed' || job.status === 'failed') return false;

    // Kill worker if active.
    const workerIdx = this.#activeWorkers.findIndex(w => w.jobId === jobId);
    if (workerIdx !== -1) {
      const { proc } = this.#activeWorkers[workerIdx];
      proc.kill('SIGTERM');
      this.#activeWorkers.splice(workerIdx, 1);
      this.#processingIds.delete(jobId);
    }

    // Remove from pending queue.
    this.#pendingQueue = this.#pendingQueue.filter(id => id !== jobId);

    job.status = 'failed';
    job.error = 'cancelled';
    job.completedAt = Date.now();
    this.#persistJob(job);

    this.emit('job:cancelled', { jobId });
    return true;
  }

  /**
   * Register a callback invoked whenever a job completes (success or failure).
   * @param {(job: object) => void} callback
   */
  onJobComplete(callback) {
    this.#completionHandlers.push(callback);
  }

  // ── Private — Job lifecycle ────────────────────────────────

  #createJob(frameInfo, type, temporalTarget, priority) {
    return {
      id: randomUUID(),
      type,
      sourceFrame: {
        filename: frameInfo.filename,
        path: frameInfo.path,
        timestamp: frameInfo.timestamp,
      },
      temporalTarget: Math.max(-1, Math.min(1, temporalTarget)),
      constraints: null,
      priority,
      status: 'pending',
      createdAt: Date.now(),
      completedAt: null,
      result: null,
      error: null,
    };
  }

  #addToQueue(jobId, priority) {
    // Insert high-priority jobs before normal ones.
    if (priority === 'high') {
      // Find first normal-priority job and insert before it.
      let insertIdx = this.#pendingQueue.length;
      for (let i = 0; i < this.#pendingQueue.length; i++) {
        const queuedJob = this.#jobs.get(this.#pendingQueue[i]);
        if (queuedJob && queuedJob.priority === 'normal') {
          insertIdx = i;
          break;
        }
      }
      this.#pendingQueue.splice(insertIdx, 0, jobId);
    } else {
      this.#pendingQueue.push(jobId);
    }
  }

  // ── Private — K230 polling ─────────────────────────────────

  async #pollK230() {
    try {
      const res = await fetch(`${this.#k230BaseUrl}/frames?since=${this.#lastK230Timestamp}`, {
        signal: AbortSignal.timeout(5000),
      });
      if (!res.ok) return;

      const data = await res.json();
      if (!Array.isArray(data.frames) || data.frames.length === 0) return;

      for (const frame of data.frames) {
        const frameInfo = {
          filename: frame.filename,
          path: frame.path,
          timestamp: frame.timestamp,
        };

        // Automatically enqueue initial reconstruction for new frames.
        if (frame.timestamp > this.#lastK230Timestamp) {
          this.#lastK230Timestamp = frame.timestamp;
        }

        this.enqueueJob(frameInfo, 'initial_reconstruction', 0.0, 'normal');
      }
    } catch {
      // K230 receiver may not be running — that's fine, we'll retry.
    }
  }

  // ── Private — Dispatching / workers ────────────────────────

  #dispatch() {
    while (
      this.#activeWorkers.length < this.#maxConcurrentWorkers &&
      this.#pendingQueue.length > 0
    ) {
      const jobId = this.#pendingQueue.shift();
      const job = this.#jobs.get(jobId);
      if (!job || job.status !== 'pending') continue;

      job.status = 'processing';
      this.#processingIds.add(jobId);
      this.#persistJob(job);
      this.#spawnWorker(job);
    }
  }

  #spawnWorker(job) {
    const reconstructionPrompt = this.#buildPrompt(job);

    const worker = spawn('claude', [
      '--print',
      '--output-format', 'json',
      '--dangerously-skip-permissions',
      '-p', reconstructionPrompt,
    ], {
      cwd: this.#assetDir,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    const record = { jobId: job.id, proc: worker };
    this.#activeWorkers.push(record);

    let stdout = '';
    let stderr = '';

    worker.stdout.on('data', (chunk) => { stdout += chunk; });
    worker.stderr.on('data', (chunk) => { stderr += chunk; });

    worker.on('close', (code) => {
      this.#activeWorkers = this.#activeWorkers.filter(w => w.jobId !== job.id);
      this.#processingIds.delete(job.id);

      if (code === 0) {
        this.#handleSuccess(job, stdout);
      } else {
        this.#handleFailure(job, stderr || `exit code ${code}`);
      }

      // Dispatch the next job.
      this.#dispatch();
    });

    worker.on('error', (err) => {
      this.#activeWorkers = this.#activeWorkers.filter(w => w.jobId !== job.id);
      this.#processingIds.delete(job.id);
      this.#handleFailure(job, err.message);
      this.#dispatch();
    });
  }

  #buildPrompt(job) {
    const parts = [
      `You are a FUMIRA reconstruction worker.`,
      `Job type: ${job.type}`,
      `Source frame: ${job.sourceFrame.filename} (path: ${job.sourceFrame.path})`,
      `Temporal target: ${job.temporalTarget}`,
    ];

    if (job.constraints) {
      parts.push(`Constraints: ${JSON.stringify(job.constraints)}`);
    }

    parts.push(
      `Load the source frame from the asset directory, perform ${job.type} reconstruction,`,
      `write output artifacts to the asset directory,`,
      `and print a JSON summary to stdout: { "assets": [...], "metrics": {...} }`
    );

    return parts.join('\n');
  }

  // ── Private — Completion ───────────────────────────────────

  #handleSuccess(job, stdout) {
    let result = null;

    try {
      // The worker prints a JSON summary as the last line of stdout.
      const lines = stdout.trim().split('\n');
      result = JSON.parse(lines[lines.length - 1]);
    } catch {
      result = { raw: stdout.slice(0, 4096) };
    }

    job.status = 'completed';
    job.result = result;
    job.completedAt = Date.now();
    this.#persistJob(job);

    this.emit('job:completed', { jobId: job.id, result });
    this.#notifyCompletionHandlers(job);
  }

  #handleFailure(job, errorMsg) {
    job.status = 'failed';
    job.error = typeof errorMsg === 'string' ? errorMsg.slice(0, 2048) : String(errorMsg);
    job.completedAt = Date.now();
    this.#persistJob(job);

    this.emit('job:failed', { jobId: job.id, error: job.error });
    this.#notifyCompletionHandlers(job);
  }

  #notifyCompletionHandlers(job) {
    const snapshot = { ...job };
    for (const handler of this.#completionHandlers) {
      try {
        handler(snapshot);
      } catch { /* handler errors are swallowed */ }
    }
  }

  // ── Private — Persistence ──────────────────────────────────

  async #persistJob(job) {
    try {
      const jobsDir = path.join(this.#assetDir, '.jobs');
      await mkdir(jobsDir, { recursive: true });
      await writeFile(
        path.join(jobsDir, `${job.id}.json`),
        JSON.stringify(job, null, 2),
      );
    } catch {
      // Best-effort persistence.
    }
  }

  async #recoverPersistedJobs() {
    try {
      const jobsDir = path.join(this.#assetDir, '.jobs');
      await mkdir(jobsDir, { recursive: true });
      const files = await readdir(jobsDir);

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const raw = await readFile(path.join(jobsDir, file), 'utf8');
          const job = JSON.parse(raw);
          this.#jobs.set(job.id, job);

          // Re-enqueue any jobs that were pending or processing at shutdown.
          if (job.status === 'pending') {
            this.#addToQueue(job.id, job.priority);
          } else if (job.status === 'processing') {
            // Mark as pending so it gets re-dispatched.
            job.status = 'pending';
            this.#addToQueue(job.id, job.priority);
          }
        } catch {
          // Corrupted job file — skip.
        }
      }
    } catch {
      // Asset dir may not exist yet — that's fine.
    }
  }
}
