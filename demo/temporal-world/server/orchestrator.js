/**
 * JobOrchestrator — Central service that coordinates all pipeline stages.
 *
 * Receives a photo (from K230 or mobile upload), runs a two-phase pipeline:
 *   FAST PATH  : Xiaomi vision → CanonicalSceneSpec → Clay Builders → instant display
 *   REFINEMENT : Claude Worker → refined geometry → hot swap
 *
 * Manages job lifecycle, retries, directory structure, and progress reporting.
 * Emits events that the HTTP/WS layer forwards to connected clients.
 *
 * @module orchestrator
 */

import { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import { mkdir, writeFile, readFile, copyFile, readdir } from 'node:fs/promises';
import path from 'node:path';

// ── Defaults ─────────────────────────────────────────────────

const CONFIDENCE_THRESHOLD = 0.9;
const DEFAULT_MAX_RETRIES = 2;
const DEFAULT_MAX_CONCURRENT = 1;
const REFINE_TIMEOUT_MS = 60_000;
const REFINE_MAX_TURNS = 8;

// ── JobOrchestrator ──────────────────────────────────────────

export class JobOrchestrator extends EventEmitter {
  /** @type {Map<string, JobRecord>} */
  #jobs = new Map();

  /** External service providers (injected). */
  #xiaomiProvider;
  #claudeWorker;
  #useClayWorker = false;
  #sceneCompiler;

  /** Root directory under which per-job folders are created. */
  #jobsDir;

  /** Concurrency gate — number of jobs currently inside #processJob. */
  #activeJobs = 0;
  #maxConcurrent;

  /** Jobs waiting for a concurrency slot. */
  #pendingQueue = [];

  /**
   * @param {object} opts
   * @param {object} opts.xiaomiProvider – Xiaomi vision provider (analyzePhoto, generateSceneSpec, reviewScene)
   * @param {object} opts.claudeWorker   – Claude Worker service (executeTask)
   * @param {object} opts.sceneCompiler  – SceneCompiler instance (loadSceneSpec)
   * @param {string} opts.jobsDir        – Absolute path to the jobs root directory
   * @param {number} [opts.maxConcurrent=1] – Maximum concurrent jobs
   */
  constructor({ xiaomiProvider, claudeWorker, clayWorker, sceneCompiler, jobsDir, maxConcurrent }) {
    super();
    this.#xiaomiProvider = xiaomiProvider;
    // ClayWorker is preferred (clay style, faster); fall back to generic ClaudeWorker.
    this.#claudeWorker = clayWorker || claudeWorker;
    this.#useClayWorker = !!clayWorker;
    this.#sceneCompiler = sceneCompiler;
    this.#jobsDir = path.resolve(jobsDir);
    this.#maxConcurrent = maxConcurrent ?? DEFAULT_MAX_CONCURRENT;
  }

  // ── Public API ─────────────────────────────────────────────

  /**
   * Submit a new photo for full reconstruction.
   *
   * @param {string}  photoPath – Absolute path to the source photo
   * @param {object}  [options]
   * @param {string}  [options.source]       – 'k230' | 'mobile' | 'upload'
   * @param {number}  [options.temporalTarget]
   * @param {string}  [options.priority]     – 'normal' | 'high'
   * @param {object}  [options.constraints]  – Forwarded to the scene spec generation
   * @returns {Promise<string>} jobId
   */
  async submitPhoto(photoPath, options = {}) {
    const jobId = `scene-${Date.now().toString(36)}-${randomUUID().slice(0, 6)}`;
    const jobDir = path.join(this.#jobsDir, jobId);

    // Prepare on-disk directory structure.
    await this.#setupJobDir(jobDir, photoPath);

    const job = {
      id: jobId,
      type: 'full-reconstruction',
      status: 'pending',
      input: { photoPath, ...options },
      progress: { phase: 'queued', percent: 0, message: 'Job queued' },
      result: null,
      error: null,
      createdAt: Date.now(),
      completedAt: null,
      retryCount: 0,
      maxRetries: options.maxRetries ?? DEFAULT_MAX_RETRIES,
    };

    this.#jobs.set(jobId, job);
    this.emit('job:created', { jobId, createdAt: job.createdAt });

    // Persist initial state.
    await this.#persistJob(job, jobDir);

    // Try to start immediately or queue.
    this.#enqueue(job, jobDir);

    return jobId;
  }

  /**
   * Get a snapshot of a single job.
   * @param {string} jobId
   * @returns {object | undefined}
   */
  getJob(jobId) {
    const job = this.#jobs.get(jobId);
    return job ? structuredClone(job) : undefined;
  }

  /**
   * List jobs, optionally filtered by status.
   * @param {{ status?: string }} [filter]
   * @returns {object[]}
   */
  listJobs(filter = {}) {
    let jobs = Array.from(this.#jobs.values());
    if (filter.status) {
      jobs = jobs.filter(j => j.status === filter.status);
    }
    return jobs.map(j => structuredClone(j));
  }

  /**
   * Cancel a running or queued job.
   * @param {string} jobId
   * @returns {boolean} true if the job was found and cancelled
   */
  async cancelJob(jobId) {
    const job = this.#jobs.get(jobId);
    if (!job) return false;
    if (job.status === 'completed' || job.status === 'failed') return false;

    // Remove from pending queue if present.
    this.#pendingQueue = this.#pendingQueue.filter(entry => entry.job.id !== jobId);

    job.status = 'failed';
    job.error = 'cancelled';
    job.completedAt = Date.now();

    const jobDir = path.join(this.#jobsDir, jobId);
    await this.#persistJob(job, jobDir);

    this.emit('job:cancelled', { jobId });
    return true;
  }

  // ── Concurrency gate ───────────────────────────────────────

  #enqueue(job, jobDir) {
    if (this.#activeJobs < this.#maxConcurrent) {
      this.#dispatch(job, jobDir);
    } else {
      this.#pendingQueue.push({ job, jobDir });
    }
  }

  #dispatch(job, jobDir) {
    this.#activeJobs++;
    this.#processJob(job, jobDir)
      .catch(err => {
        job.status = 'failed';
        job.error = err.message ?? String(err);
        job.completedAt = Date.now();
        this.emit('job:failed', { jobId: job.id, error: job.error });
      })
      .finally(() => {
        this.#activeJobs--;
        this.#drainQueue();
      });
  }

  #drainQueue() {
    while (this.#activeJobs < this.#maxConcurrent && this.#pendingQueue.length > 0) {
      const next = this.#pendingQueue.shift();
      if (next) this.#dispatch(next.job, next.jobDir);
    }
  }

  // ── Pipeline ───────────────────────────────────────────────

  /**
   * Run both paths for a single job.
   */
  async #processJob(job, jobDir) {
    await this.#runFastPath(job, jobDir);

    // Refinement runs asynchronously — errors are caught internally.
    this.#runRefinementPath(job, jobDir).catch(err => {
      this.emit('job:refinement-error', { jobId: job.id, error: err.message });
    });
  }

  // ── Fast Path ──────────────────────────────────────────────

  async #runFastPath(job, jobDir) {
    // 1. Xiaomi vision analysis
    this.#updateProgress(job, 'analyzing', 10, 'Analyzing photo with vision model...');
    const vision = await this.#xiaomiProvider.analyzePhoto(job.input.photoPath);
    await writeFile(
      path.join(jobDir, 'state', 'vision-analysis.json'),
      JSON.stringify(vision, null, 2),
    );

    // 2. Generate CanonicalSceneSpec
    this.#updateProgress(job, 'planning', 30, 'Planning scene structure...');
    const sceneSpec = await this.#xiaomiProvider.generateSceneSpec(vision, job.input.constraints);
    await writeFile(
      path.join(jobDir, 'state', 'canonical-scene.json'),
      JSON.stringify(sceneSpec, null, 2),
    );

    // 3. Build blockout with Clay Builders
    this.#updateProgress(job, 'blockouting', 60, 'Building clay blockout...');
    const blockout = this.#buildBlockout(sceneSpec);
    await writeFile(
      path.join(jobDir, 'output', 'blockout.json'),
      JSON.stringify(blockout, null, 2),
    );

    // 4. Load into SceneCompiler so the live scene updates.
    this.#updateProgress(job, 'displaying', 80, 'Displaying scene...');
    this.#sceneCompiler.loadSceneSpec(sceneSpec);

    this.#updateProgress(job, 'refining', 90, 'Starting refinement...');

    this.emit('blockout:ready', {
      jobId: job.id,
      sceneSpec,
      blockout,
    });
  }

  // ── Refinement Path ────────────────────────────────────────

  async #runRefinementPath(job, jobDir) {
    const sceneSpecPath = path.join(jobDir, 'state', 'canonical-scene.json');
    const raw = await readFile(sceneSpecPath, 'utf-8');
    const sceneSpec = JSON.parse(raw);

    if (!Array.isArray(sceneSpec.entities)) return;

    for (const entity of sceneSpec.entities) {
      // Skip entities that are already confident or already refined.
      if (entity.confidence >= CONFIDENCE_THRESHOLD) continue;
      if (entity.buildStatus === 'refined') continue;

      try {
        // Build task — ClayWorker uses entitySpecPath, generic ClaudeWorker uses sceneSpecPath.
        const task = {
          taskType: 'REFINE_ENTITY',
          jobId: job.id,
          entityId: entity.id,
          referenceImagePath: job.input.photoPath,
          outputDirectory: path.join(jobDir, 'output', 'entities', entity.id),
          maxTurns: this.#useClayWorker ? 4 : REFINE_MAX_TURNS,
          timeoutMs: this.#useClayWorker ? 90_000 : REFINE_TIMEOUT_MS,
        };
        if (this.#useClayWorker) {
          // ClayWorker expects the entity spec path; write entity to disk for it.
          const entitySpecPath = path.join(jobDir, 'output', 'entities', entity.id, 'entity-spec.json');
          await mkdir(path.dirname(entitySpecPath), { recursive: true });
          await writeFile(entitySpecPath, JSON.stringify(entity, null, 2));
          task.entitySpecPath = entitySpecPath;
        } else {
          task.sceneSpecPath = sceneSpecPath;
        }

        const refined = await this.#claudeWorker.executeTask(task);

        if (refined.success) {
          entity.buildStatus = 'refined';
          // ClayWorker returns entityPatch (singular), generic returns entityPatches (plural).
          const patches = this.#useClayWorker
            ? (refined.entityPatch ? [refined.entityPatch] : [])
            : (refined.entityPatches || []);
          this.emit('entity:refined', {
            jobId: job.id,
            entityId: entity.id,
            patches,
          });
        }
      } catch (err) {
        entity.buildLog = err.message ?? String(err);
        this.emit('entity:refine-failed', {
          jobId: job.id,
          entityId: entity.id,
          error: entity.buildLog,
        });
      }
    }

    // Final visual review.
    this.#updateProgress(job, 'reviewing', 95, 'Running visual review...');
    const review = await this.#xiaomiProvider.reviewScene(sceneSpec);

    job.status = 'completed';
    job.completedAt = Date.now();
    job.progress = { phase: 'completed', percent: 100, message: 'Job completed' };
    job.result = {
      reviewReport: review,
      artifacts: this.#collectArtifacts(jobDir),
    };

    await this.#persistJob(job, jobDir);
    this.emit('job:completed', { jobId: job.id, result: job.result });
  }

  // ── Blockout builder ───────────────────────────────────────

  /**
   * Convert a CanonicalSceneSpec into a Three.js-ready blockout descriptor.
   * This produces a lightweight JSON representation that the SceneCompiler
   * and client SceneRuntime can render without waiting for Claude refinement.
   */
  #buildBlockout(sceneSpec) {
    return {
      type: 'scene.blockout',
      sceneId: sceneSpec.sceneId,
      entities: (sceneSpec.entities ?? []).map(e => ({
        id: e.id,
        geometry: e.geometry ?? { type: 'BoxGeometry', args: [1, 1, 1] },
        material: e.material ?? { color: '#888888', roughness: 0.8 },
        position: e.position ?? [0, 0, 0],
        rotation: e.rotation ?? [0, 0, 0],
        scale: e.scale ?? [1, 1, 1],
      })),
      camera: sceneSpec.camera ?? { position: [0, 5, 10], target: [0, 0, 0] },
      lighting: sceneSpec.lighting ?? {
        ambient: { color: '#F7F5EF', intensity: 0.6 },
        directional: { color: '#FFE4B5', intensity: 0.8, position: [5, 10, 5] },
      },
    };
  }

  // ── Progress & persistence ─────────────────────────────────

  #updateProgress(job, phase, percent, message) {
    job.status = phase;
    job.progress = { phase, percent, message };
    this.emit('job:progress', { jobId: job.id, ...job.progress });
  }

  async #setupJobDir(jobDir, photoPath) {
    const dirs = [
      'input',
      'state',
      'output/entities',
      'output/scene-patches',
      'output/renders',
      'logs',
    ];
    for (const d of dirs) {
      await mkdir(path.join(jobDir, d), { recursive: true });
    }

    // Copy source photo into the job's input directory.
    const ext = path.extname(photoPath) || '.jpg';
    await copyFile(photoPath, path.join(jobDir, 'input', `photo${ext}`));
  }

  async #persistJob(job, jobDir) {
    try {
      await writeFile(
        path.join(jobDir, 'state', 'job.json'),
        JSON.stringify(job, null, 2),
      );
    } catch {
      // Best-effort — the job can still proceed even if persistence fails.
    }
  }

  /**
   * Collect a list of artifact paths produced by the job.
   * Returns relative paths from the job root.
   */
  #collectArtifacts(jobDir) {
    // Synchronous stat is acceptable here since the directory is small.
    // We return a placeholder that the caller can resolve asynchronously.
    return [
      'output/blockout.json',
      'state/canonical-scene.json',
      'state/vision-analysis.json',
    ];
  }
}

export default JobOrchestrator;
