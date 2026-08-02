/**
 * ClayWorker — FUMIRA clay-style 3D reconstruction worker.
 *
 * Wraps @anthropic-ai/claude-code with the `clay-reconstruct` skill
 * to produce CanonicalEntity patches from reference images.
 *
 * Replaces the generic ClaudeWorker for geometry refinement tasks.
 * Uses FUMIRA's Clay3DStyle design system and single-pass generation
 * for 3-5× faster reconstruction.
 *
 * @module clay-worker
 */

import { EventEmitter } from 'node:events';
import { mkdir, readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

// Lazy-load the Claude Code SDK.
let _query;
async function loadQuery() {
  if (!_query) {
    const mod = await import('@anthropic-ai/claude-code');
    _query = mod.query;
  }
  return _query;
}

/**
 * @typedef {'REFINE_ENTITY'|'BUILD_BASE_SCENE'|'REVIEW_CONTINUITY'} TaskType
 */

/**
 * @typedef {Object} ClayTask
 * @property {string}   jobId             — parent job id
 * @property {TaskType}  taskType         — kind of reconstruction task
 * @property {string}   [entityId]        — target entity id
 * @property {string}   [entitySpecPath]  — path to the CanonicalEntity JSON
 * @property {string}   [referenceImagePath] — path to the reference photo
 * @property {string}   outputDirectory   — absolute path for output files
 * @property {number}   [maxTurns=4]      — max agentic turns (clay is faster)
 * @property {number}   [timeoutMs]       — per-task timeout
 */

/**
 * @typedef {Object} ClayTaskResult
 * @property {boolean}  success
 * @property {string}   taskId
 * @property {string}   jobId
 * @property {string[]} outputFiles
 * @property {Object|null} entityPatch — parsed canonical-entity-patch.json
 * @property {number}   turnsUsed
 * @property {number}   durationMs
 * @property {string}   [error]
 */

export class ClayWorker extends EventEmitter {
  /** @type {Map<string, object>} */
  #activeTasks = new Map();

  /** @type {number} */
  #maxConcurrent;

  /** @type {number} */
  #defaultTimeout;

  /** @type {string} */
  #skillDir;

  /** @type {string} */
  #forgeDir;

  /**
   * @param {object}  opts
   * @param {number}  [opts.maxConcurrent=1]
   * @param {number}  [opts.defaultTimeoutMs=90_000] — 90s for clay (faster than 120s default)
   * @param {string}  opts.skillDir                  — absolute path to clay-reconstruct skill dir
   * @param {string}  opts.forgeDir                  — absolute path to img2threejs forge scripts
   */
  constructor({ maxConcurrent = 1, defaultTimeoutMs = 90_000, skillDir, forgeDir }) {
    super();
    if (!skillDir) throw new Error('ClayWorker: skillDir is required');
    if (!forgeDir) throw new Error('ClayWorker: forgeDir is required');

    this.#maxConcurrent = maxConcurrent;
    this.#defaultTimeout = defaultTimeoutMs;
    this.#skillDir = path.resolve(skillDir);
    this.#forgeDir = path.resolve(forgeDir);
  }

  // ── Public API ─────────────────────────────────────────────

  /**
   * Execute a clay reconstruction task.
   * @param {ClayTask} task
   * @returns {Promise<ClayTaskResult>}
   */
  async executeTask(task) {
    if (this.#activeTasks.size >= this.#maxConcurrent) {
      throw new Error(`ClayWorker: max concurrent tasks (${this.#maxConcurrent}) reached`);
    }

    const taskId = this.#makeTaskId(task);
    const abortController = new AbortController();

    const taskState = {
      id: taskId,
      task,
      abortController,
      startedAt: Date.now(),
      turnsUsed: 0,
    };

    this.#activeTasks.set(taskId, taskState);
    this.emit('task:started', { taskId, taskType: task.taskType, entityId: task.entityId });

    try {
      await mkdir(task.outputDirectory, { recursive: true });

      const timeoutMs = task.timeoutMs || this.#defaultTimeout;
      const timeout = setTimeout(() => abortController.abort(), timeoutMs);

      const prompt = this.#buildPrompt(task);
      const messages = [];

      const query = await loadQuery();
      for await (const message of query({
        prompt,
        abortController,
        options: {
          cwd: task.outputDirectory,
          maxTurns: task.maxTurns || 4,  // Clay pipeline is faster — 4 turns max
          allowedTools: [
            'Read',
            'Write',
            `Bash(python3 ${this.#skillDir}/*)`,
            `Bash(python3 ${this.#forgeDir}/stage2_spec/*)`,
            `Bash(python3 ${this.#forgeDir}/stage3_build/*)`,
          ],
        },
      })) {
        messages.push(message);
        taskState.turnsUsed++;
        this.emit('task:progress', {
          taskId,
          turnsUsed: taskState.turnsUsed,
          message,
        });
      }

      clearTimeout(timeout);

      const output = await this.#parseOutput(task);

      this.#activeTasks.delete(taskId);
      this.emit('task:completed', { taskId, success: true, output });

      return {
        success: true,
        taskId,
        jobId: task.jobId,
        outputFiles: output.files || [],
        entityPatch: output.entityPatch,
        turnsUsed: taskState.turnsUsed,
        durationMs: Date.now() - taskState.startedAt,
      };
    } catch (error) {
      this.#activeTasks.delete(taskId);

      const message = error?.name === 'AbortError'
        ? 'Clay task aborted (timeout or cancel)'
        : (error?.message || String(error));

      this.emit('task:failed', { taskId, error: message });

      return {
        success: false,
        taskId,
        jobId: task.jobId,
        outputFiles: [],
        entityPatch: null,
        turnsUsed: taskState.turnsUsed,
        durationMs: Date.now() - taskState.startedAt,
        error: message,
      };
    }
  }

  /**
   * Cancel a running task.
   * @param {string} taskId
   * @returns {boolean}
   */
  cancelTask(taskId) {
    const task = this.#activeTasks.get(taskId);
    if (!task) return false;
    task.abortController.abort();
    this.#activeTasks.delete(taskId);
    this.emit('task:cancelled', { taskId });
    return true;
  }

  /** Cancel all running tasks. */
  cancelAll() {
    for (const [id, task] of this.#activeTasks) {
      task.abortController.abort();
      this.emit('task:cancelled', { taskId: id });
    }
    this.#activeTasks.clear();
  }

  /** @returns {number} */
  get activeTaskCount() {
    return this.#activeTasks.size;
  }

  /** @returns {string[]} */
  get activeTaskIds() {
    return [...this.#activeTasks.keys()];
  }

  // ── Private ────────────────────────────────────────────────

  #makeTaskId(task) {
    return [
      task.jobId || 'clay',
      task.taskType || 'refine',
      task.entityId || 'scene',
      Date.now().toString(36),
      randomUUID().slice(0, 8),
    ].join('--');
  }

  /**
   * Build the task prompt for the clay-reconstruct skill.
   * @param {ClayTask} task
   * @returns {string}
   */
  #buildPrompt(task) {
    const skillPath = path.join(this.#skillDir, 'SKILL.md');

    switch (task.taskType) {
      case 'REFINE_ENTITY':
        return [
          `Read the skill definition at: ${skillPath}`,
          ``,
          `Task: Refine entity "${task.entityId ?? 'entity_001'}" using clay-style reconstruction.`,
          ``,
          `Inputs:`,
          `  Entity spec: ${task.entitySpecPath ?? '(not provided)'}`,
          `  Reference image: ${task.referenceImagePath ?? '(not provided)'}`,
          `  Output directory: ${task.outputDirectory}`,
          ``,
          `Follow the skill's pipeline steps exactly.`,
          `The entity ID is: ${task.entityId ?? 'entity_001'}`,
          `Output the canonical-entity-patch.json to the output directory.`,
        ].join('\n');

      case 'BUILD_BASE_SCENE':
        return [
          `Read the skill definition at: ${skillPath}`,
          ``,
          `Task: Build a base clay scene from the vision analysis.`,
          ``,
          `Inputs:`,
          `  Scene spec: ${task.entitySpecPath ?? '(not provided)'}`,
          `  Reference image: ${task.referenceImagePath ?? '(not provided)'}`,
          `  Output directory: ${task.outputDirectory}`,
          ``,
          `Analyze the image, create entity specs for each major object,`,
          `and generate clay-style canonical entity patches.`,
        ].join('\n');

      default:
        return this.#buildPrompt({ ...task, taskType: 'REFINE_ENTITY' });
    }
  }

  /**
   * Parse JSON output files from the task output directory.
   * @param {ClayTask} task
   * @returns {Promise<{files: string[], entityPatch: Object|null}>}
   */
  async #parseOutput(task) {
    const result = { files: [], entityPatch: null };

    let entries;
    try {
      entries = await readdir(task.outputDirectory);
    } catch {
      return result;
    }

    const jsonFiles = entries.filter(f => f.endsWith('.json'));

    for (const filename of jsonFiles) {
      const filePath = path.join(task.outputDirectory, filename);
      try {
        const raw = await readFile(filePath, 'utf-8');
        const parsed = JSON.parse(raw);
        result.files.push(filename);

        if (filename === 'canonical-entity-patch.json') {
          result.entityPatch = parsed;
        }
      } catch {
        // Skip non-JSON files
      }
    }

    return result;
  }
}

export default ClayWorker;
