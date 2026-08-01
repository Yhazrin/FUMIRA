// ── claude-worker.js ─────────────────────────────────────────
// Claude Reconstruction Worker — wraps @anthropic-ai/claude-code
// for on-demand 3D modeling tasks.
//
// NOT an always-on service.  Batch job processor that spawns
// Claude Code for each task, in an isolated job directory,
// with strict tool whitelisting, timeout/abort control, and
// structured JSON output parsing.
//
// Pure ESM module.
// ─────────────────────────────────────────────────────────────

import { EventEmitter } from 'node:events';
import { mkdir, readdir, readFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

// The SDK import may not be installed yet — that is fine; the
// module is only resolved at runtime when executeTask() is called.
let _query;
async function loadQuery() {
  if (!_query) {
    const mod = await import('@anthropic-ai/claude-code');
    _query = mod.query;
  }
  return _query;
}

/**
 * @typedef {'REFINE_ENTITY'|'BUILD_BASE_SCENE'|'BUILD_CHARACTER_VARIANT'|'REVIEW_CONTINUITY'} TaskType
 */

/**
 * @typedef {Object} ClaudeTask
 * @property {string}   jobId             — parent job id (from JobDispatcher)
 * @property {TaskType}  taskType         — kind of reconstruction task
 * @property {string}   [entityId]        — target entity (for REFINE_ENTITY / BUILD_CHARACTER_VARIANT)
 * @property {string}   [sceneSpecPath]   — path to the current scene spec JSON
 * @property {string}   [referenceImagePath] — path to the reference photo
 * @property {string}   outputDirectory   — absolute path where output files are written
 * @property {number}   [maxTurns=8]      — max agentic turns
 * @property {number}   [timeoutMs]       — per-task timeout (overrides default)
 */

/**
 * @typedef {Object} TaskResult
 * @property {boolean}  success
 * @property {string}   taskId
 * @property {string}   jobId
 * @property {string[]} outputFiles       — filenames written to outputDirectory
 * @property {Object|null} sceneSpec      — parsed canonical-scene.json (if present)
 * @property {Object[]} entityPatches     — parsed entity-patch.json entries
 * @property {Object|null} reviewReport   — parsed review-report.json (if present)
 * @property {number}   turnsUsed
 * @property {number}   durationMs
 * @property {string}   [error]           — error message on failure
 */

export class ClaudeWorker extends EventEmitter {
  /** @type {Map<string, object>} */
  #activeTasks = new Map();

  /** @type {number} */
  #maxConcurrent;

  /** @type {number} */
  #defaultTimeout;

  /** @type {string} */
  #forgeScriptsDir;

  /** @type {string} */
  #scratchDir;

  /**
   * @param {object}  opts
   * @param {number}  [opts.maxConcurrent=1]    — max parallel Claude sessions
   * @param {number}  [opts.defaultTimeoutMs=120000] — per-task timeout
   * @param {string}  opts.forgeScriptsDir       — absolute path to forge script directory
   * @param {string}  [opts.scratchDir]          — base directory for per-task scratch dirs
   */
  constructor({ maxConcurrent = 1, defaultTimeoutMs = 120_000, forgeScriptsDir, scratchDir }) {
    super();
    if (!forgeScriptsDir) {
      throw new Error('ClaudeWorker: forgeScriptsDir is required');
    }
    this.#maxConcurrent = maxConcurrent;
    this.#defaultTimeout = defaultTimeoutMs;
    this.#forgeScriptsDir = path.resolve(forgeScriptsDir);
    this.#scratchDir = scratchDir
      ? path.resolve(scratchDir)
      : path.join(path.dirname(new URL(import.meta.url).pathname), '.scratch');
  }

  // ── Public API ─────────────────────────────────────────────

  /**
   * Execute a Claude Worker task.  Returns a structured TaskResult.
   *
   * @param {ClaudeTask} task
   * @returns {Promise<TaskResult>}
   */
  async executeTask(task) {
    if (this.#activeTasks.size >= this.#maxConcurrent) {
      throw new Error(`ClaudeWorker: max concurrent tasks (${this.#maxConcurrent}) reached`);
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
      // Ensure the output directory exists.
      await mkdir(task.outputDirectory, { recursive: true });

      // Set up timeout.
      const timeoutMs = task.timeoutMs || this.#defaultTimeout;
      const timeout = setTimeout(() => {
        abortController.abort();
      }, timeoutMs);

      // Build the prompt.
      const prompt = this.#buildPrompt(task);

      // Execute Claude Code.
      const messages = [];
      const result = await this.#executeClaude(prompt, task, abortController, (msg) => {
        messages.push(msg);
        taskState.turnsUsed++;
        this.emit('task:progress', {
          taskId,
          turnsUsed: taskState.turnsUsed,
          message: msg,
        });
      });

      clearTimeout(timeout);

      // Parse and validate output.
      const output = await this.#parseOutput(task);

      this.#activeTasks.delete(taskId);
      this.emit('task:completed', { taskId, success: true, output });

      return {
        success: true,
        taskId,
        jobId: task.jobId,
        outputFiles: output.files || [],
        sceneSpec: output.sceneSpec,
        entityPatches: output.entityPatches || [],
        reviewReport: output.reviewReport,
        turnsUsed: taskState.turnsUsed,
        durationMs: Date.now() - taskState.startedAt,
      };
    } catch (error) {
      this.#activeTasks.delete(taskId);

      const message = error?.name === 'AbortError'
        ? 'Task aborted (timeout or manual cancel)'
        : (error?.message || String(error));

      this.emit('task:failed', { taskId, error: message });

      return {
        success: false,
        taskId,
        jobId: task.jobId,
        outputFiles: [],
        sceneSpec: null,
        entityPatches: [],
        reviewReport: null,
        turnsUsed: taskState.turnsUsed,
        durationMs: Date.now() - taskState.startedAt,
        error: message,
      };
    }
  }

  /**
   * Cancel a running task by id.
   * @param {string} taskId
   * @returns {boolean} true if the task was found and cancelled
   */
  cancelTask(taskId) {
    const task = this.#activeTasks.get(taskId);
    if (!task) return false;

    task.abortController.abort();
    this.#activeTasks.delete(taskId);
    this.emit('task:cancelled', { taskId });
    return true;
  }

  /**
   * Cancel all running tasks.
   */
  cancelAll() {
    for (const [id, task] of this.#activeTasks) {
      task.abortController.abort();
      this.emit('task:cancelled', { taskId: id });
    }
    this.#activeTasks.clear();
  }

  /**
   * Number of currently active tasks.
   * @returns {number}
   */
  get activeTaskCount() {
    return this.#activeTasks.size;
  }

  /**
   * Snapshot of active task ids.
   * @returns {string[]}
   */
  get activeTaskIds() {
    return [...this.#activeTasks.keys()];
  }

  // ── Private — Task ID ──────────────────────────────────────

  #makeTaskId(task) {
    const parts = [
      task.jobId || 'job',
      task.taskType || 'unknown',
      task.entityId || 'scene',
      Date.now().toString(36),
      randomUUID().slice(0, 8),
    ];
    return parts.join('--');
  }

  // ── Private — Claude execution ─────────────────────────────

  /**
   * Spawn Claude Code via the SDK query() API.
   *
   * @param {string}       prompt
   * @param {ClaudeTask}   task
   * @param {AbortController} abortController
   * @param {Function}     onMessage — called for each streamed message
   * @returns {Promise<object[]>}   — full message array
   */
  async #executeClaude(prompt, task, abortController, onMessage) {
    const query = await loadQuery();

    const messages = [];

    for await (const message of query({
      prompt,
      abortController,
      options: {
        cwd: task.outputDirectory,
        maxTurns: task.maxTurns || 8,
        allowedTools: [
          'Read',
          'Write',
          `Bash(python3 ${this.#forgeScriptsDir}/*)`,
        ],
      },
    })) {
      messages.push(message);
      if (onMessage) onMessage(message);
    }

    return messages;
  }

  // ── Private — Prompt builder ───────────────────────────────

  /**
   * Build the task-specific prompt string.
   *
   * @param {ClaudeTask} task
   * @returns {string}
   */
  #buildPrompt(task) {
    switch (task.taskType) {
      case 'REFINE_ENTITY':
        return this.#promptRefineEntity(task);
      case 'BUILD_BASE_SCENE':
        return this.#promptBuildBaseScene(task);
      case 'BUILD_CHARACTER_VARIANT':
        return this.#promptBuildCharacterVariant(task);
      case 'REVIEW_CONTINUITY':
        return this.#promptReviewContinuity(task);
      default:
        return this.#promptRefineEntity(task);
    }
  }

  #promptRefineEntity(task) {
    return [
      `You are a 3D modeling specialist for a clay-style temporal world.`,
      ``,
      `Task: Refine the geometry of entity "${task.entityId}" in the scene.`,
      ``,
      `Read the scene spec from: ${task.sceneSpecPath ?? '(not provided)'}`,
      `Look at the reference photo: ${task.referenceImagePath ?? '(not provided)'}`,
      `Find the entity "${task.entityId}" and create a refined version.`,
      ``,
      `Output a JSON file at: ${task.outputDirectory}/entity-patch.json`,
      `The file must contain:`,
      `  {`,
      `    "entityId": "${task.entityId ?? 'entity_001'}",`,
      `    "patchType": "geometry",`,
      `    "patchData": {`,
      `      "geometry": { "builder": "...", "parameters": { ... } },`,
      `      "material": { "color": "...", "roughness": 0.X }`,
      `    },`,
      `    "confidence": 0.X`,
      `  }`,
      ``,
      `Use the forge scripts if needed for procedural geometry.`,
      `Do NOT write arbitrary JavaScript.  Output JSON only.`,
    ].join('\n');
  }

  #promptBuildBaseScene(task) {
    return [
      `You are a scene planner for a clay-style temporal world.`,
      ``,
      `Read the vision analysis from: ${task.sceneSpecPath ?? '(not provided)'}`,
      `Generate a complete CanonicalSceneSpec.`,
      ``,
      `Output: ${task.outputDirectory}/canonical-scene.json`,
      ``,
      `Follow the schema exactly.  Use only these builders:`,
      `  stylized-building, organic-tree, flat-path, ground-plane,`,
      `  clay-vehicle, clay-person, clay-bench, clay-sign`,
      ``,
      `Output JSON only.  No code.`,
    ].join('\n');
  }

  #promptBuildCharacterVariant(task) {
    return [
      `Create a character variant for "${task.entityId}" at a different time period.`,
      ``,
      `Read the current scene spec from: ${task.sceneSpecPath ?? '(not provided)'}`,
      `Create a variant reflecting the new temporal context.`,
      ``,
      `Output: ${task.outputDirectory}/variant.json`,
      ``,
      `JSON only.  No code.`,
    ].join('\n');
  }

  #promptReviewContinuity(task) {
    return [
      `Review the temporal continuity of the scene.`,
      `Check that entity changes between time anchors are smooth and logical.`,
      ``,
      `Read the scene spec from: ${task.sceneSpecPath ?? '(not provided)'}`,
      ``,
      `Output: ${task.outputDirectory}/review-report.json`,
      `The report must contain:`,
      `  {`,
      `    "continuityScore": 0.X,`,
      `    "issues": [`,
      `      { "entityId": "...", "severity": "low|medium|high", "description": "..." }`,
      `    ],`,
      `    "suggestions": [ "..." ]`,
      `  }`,
      ``,
      `JSON only.  No code.`,
    ].join('\n');
  }

  // ── Private — Output parsing ───────────────────────────────

  /**
   * Read and parse JSON output files from the task output directory.
   *
   * @param {ClaudeTask} task
   * @returns {Promise<{ files: string[], sceneSpec: Object|null, entityPatches: Object[], reviewReport: Object|null }>}
   */
  async #parseOutput(task) {
    const result = {
      files: [],
      sceneSpec: null,
      entityPatches: [],
      reviewReport: null,
    };

    let entries;
    try {
      entries = await readdir(task.outputDirectory);
    } catch {
      // Output directory may not have been created — that is fine.
      return result;
    }

    const jsonFiles = entries.filter((f) => f.endsWith('.json'));

    for (const filename of jsonFiles) {
      const filePath = path.join(task.outputDirectory, filename);
      try {
        const raw = await readFile(filePath, 'utf-8');
        const parsed = JSON.parse(raw);

        result.files.push(filename);

        // Classify by known filenames.
        if (filename === 'canonical-scene.json') {
          result.sceneSpec = parsed;
        } else if (filename === 'entity-patch.json') {
          result.entityPatches.push(parsed);
        } else if (filename === 'review-report.json') {
          result.reviewReport = parsed;
        }
      } catch {
        // Skip files that are not valid JSON.
      }
    }

    return result;
  }
}
