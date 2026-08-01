# Claude Reconstruction Worker Protocol

## Overview

The Claude Reconstruction Worker is a batch job processor that transforms K230 camera images into 3D diorama scenes. Unlike always-running services, Claude is spawned on demand by the FUMIRA backend, processes a single reconstruction job, and exits.

## Worker Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  FUMIRA Backend                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
│  │ Job Queue   │───►│ Worker      │───►│ Asset Store │                     │
│  │ (Bull/Redis)│    │ Manager     │    │ (S3/Local)  │                     │
│  └─────────────┘    └──────┬──────┘    └──────┬──────┘                     │
│                            │                    │                           │
│                            ▼                    ▼                           │
│                     ┌─────────────┐      ┌─────────────┐                   │
│                     │ Claude      │      │ Callback    │                   │
│                     │ Subprocess  │      │ URL         │                   │
│                     └─────────────┘      └─────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────┘

1. Backend enqueues Reconstruction Job
2. Worker Manager spawns Claude subprocess (claude CLI)
3. Claude receives: job spec + source image path + previous assets (if refinement)
4. Claude produces: SceneFixture JSON + metadata
5. Worker Manager saves assets to Asset Store
6. Worker Manager notifies backend via callback URL
7. Subprocess exits
```

## 1. Worker Spawn Command

The Worker Manager invokes Claude via the Claude CLI in batch mode:

```typescript
// worker-spawn.ts
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';

interface SpawnWorkerOptions {
  jobId: string;
  sourceImagePath: string;
  targetYear: number;
  previousFixturePath?: string;  // For refinement jobs
  outputDir: string;
  callbackUrl: string;
  timeoutMs?: number;
}

export function spawnReconstructionWorker(options: SpawnWorkerOptions): Promise<WorkerResult> {
  const {
    jobId,
    sourceImagePath,
    targetYear,
    previousFixturePath,
    outputDir,
    callbackUrl,
    timeoutMs = 180_000  // 3 minutes default
  } = options;

  // Build the prompt that Claude will execute
  const prompt = buildReconstructionPrompt({
    jobId,
    sourceImagePath,
    targetYear,
    previousFixturePath,
    outputDir,
  });

  // Spawn Claude CLI in batch mode
  const child = spawn('claude', [
    '--print',                    // Non-interactive mode
    '--output-format', 'json',    // Structured output
    '--max-turns', '10',          // Limit tool use iterations
    '--prompt', prompt,
  ], {
    cwd: outputDir,
    env: {
      ...process.env,
      CLAUDE_JOB_ID: jobId,
      CLAUDE_OUTPUT_DIR: outputDir,
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      child.kill('SIGTERM');
      reject(new WorkerTimeoutError(jobId, timeoutMs));
    }, timeoutMs);

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });

    child.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) {
        resolve(parseWorkerOutput(stdout, outputDir));
      } else {
        reject(new WorkerCrashError(jobId, code, stderr));
      }
    });
  });
}

function buildReconstructionPrompt(ctx: {
  jobId: string;
  sourceImagePath: string;
  targetYear: number;
  previousFixturePath?: string;
  outputDir: string;
}): string {
  return `
You are a FUMIRA Scene Reconstruction Worker. Your task is to analyze a K230 camera image
and produce a SceneFixture JSON that can be rendered as a 3D clay diorama.

## Job Context
- Job ID: ${ctx.jobId}
- Source Image: ${ctx.sourceImagePath}
- Target Year: ${ctx.targetYear}
- Output Directory: ${ctx.outputDir}
${ctx.previousFixturePath ? `- Previous Fixture (for refinement): ${ctx.previousFixturePath}` : ''}

## Instructions

1. **Read the source image** at ${ctx.sourceImagePath}
2. **Analyze the scene** to identify:
   - Buildings (position, size, architectural style)
   - Vegetation (trees, gardens, hedges)
   - Characters (people, their positions)
   - Props (benches, signs, bicycles, lamp posts)
   - Road/ground infrastructure
3. **Determine the current era** from visual clues (architecture style, vehicles, clothing)
4. **Generate the SceneFixture JSON** following the schema in /packages/contracts/src/index.ts
5. **Write temporal specifications** for the target year, including:
   - How buildings weather/age/renovate
   - How trees grow/shrink
   - How characters appear/disappear
   - Seasonal changes based on the target year's season

## Output Requirements

Write the following files to ${ctx.outputDir}:

### scene-fixture.json
The complete SceneFixture JSON conforming to @fumira/contracts.

### metadata.json
Job completion metadata:
{
  "jobId": "${ctx.jobId}",
  "status": "completed" | "partial",
  "entitiesCount": number,
  "temporalAnchorsCount": number,
  "confidence": number,  // 0-1
  "warnings": string[],
  "processingTimeMs": number
}

## Important Rules

- Position entities in a coordinate system where (0, 0, 0) is the scene center
- Use meters as the unit (1 unit = 1 meter)
- Buildings should be 3-8 meters tall
- Characters should be 0.38 scale (clay figure scale)
- The scene should fit within a 20x20 meter area
- Use the FUMIRA palette colors from @fumira/contracts
- Each entity needs a unique ID (e.g., "building_01", "tree_01", "person_01")
- Temporal anchors should cover at least 3 time points for smooth interpolation

When done, output the metadata.json file path and exit.
`.trim();
}
```

## 2. Input Contract

The Worker receives a job specification that includes all context needed for reconstruction.

```typescript
// packages/contracts/src/reconstruction.ts

/**
 * A ReconstructionJob is the complete input specification for a Claude
 * Reconstruction Worker. It is serialized to JSON and passed as context
 * to the Claude subprocess.
 */
export interface ReconstructionJob {
  /** Unique job identifier */
  jobId: string;

  /** Job creation timestamp (ISO 8601) */
  createdAt: string;

  /** Priority level (higher = more urgent) */
  priority: 'low' | 'normal' | 'high';

  /** Source image from K230 camera */
  source: SourceImageSpec;

  /** Target temporal specification */
  temporal: TemporalTargetSpec;

  /** Previous reconstruction (for refinement jobs) */
  refinement?: RefinementSpec;

  /** Output configuration */
  output: OutputSpec;

  /** Callback URL for completion notification */
  callbackUrl: string;

  /** Optional: scene constraints from the iOS app */
  constraints?: SceneConstraints;
}

export interface SourceImageSpec {
  /** Absolute path to the K230 JPEG image */
  path: string;

  /** Image dimensions */
  width: number;
  height: number;

  /** K230 frame metadata */
  metadata: {
    frameId: string | null;
    timestamp: string | null;
    deviceId?: string;
  };

  /** SHA-256 hash of the image for integrity verification */
  hash: string;
}

export interface TemporalTargetSpec {
  /** Target year for the reconstruction (e.g., 2050, 1920) */
  targetYear: number;

  /** Normalized position on the time rail [-1, 1] */
  normalizedPosition: number;

  /** Human-readable label (e.g., "+25 years", "-50 years") */
  compactLabel: string;

  /** Optional: specific season to render */
  season?: 'spring' | 'summer' | 'autumn' | 'winter';

  /** Optional: time of day */
  timeOfDay?: 'dawn' | 'morning' | 'noon' | 'afternoon' | 'dusk' | 'night';
}

export interface RefinementSpec {
  /** Path to the previous SceneFixture JSON */
  previousFixturePath: string;

  /** What to improve in this refinement */
  refinementInstructions: string[];

  /** Number of previous refinement attempts */
  attemptNumber: number;

  /** Maximum allowed refinement attempts */
  maxAttempts: number;
}

export interface OutputSpec {
  /** Directory where output files should be written */
  outputDir: string;

  /** Expected output file names */
  files: {
    fixture: string;      // e.g., "scene-fixture.json"
    metadata: string;     // e.g., "metadata.json"
    thumbnail?: string;   // e.g., "thumbnail.png"
  };

  /** Maximum total output size in bytes */
  maxOutputBytes: number;
}

export interface SceneConstraints {
  /** Entities the user wants to preserve (by ID or category) */
  preserveEntities?: string[];

  /** Entities the user wants to remove */
  removeEntities?: string[];

  /** Style preferences */
  style?: {
    palette?: 'warm' | 'cool' | 'neutral';
    detail?: 'minimal' | 'standard' | 'detailed';
  };

  /** Narrative constraints from the story */
  narrativeConstraints?: string[];
}
```

## 3. Output Contract

The Worker must produce a SceneFixture JSON and metadata.

```typescript
// packages/contracts/src/reconstruction-output.ts

/**
 * The complete output of a Claude Reconstruction Worker.
 * Written to the output directory as separate JSON files.
 */
export interface ReconstructionOutput {
  /** The SceneFixture that can be rendered by scene-runtime */
  fixture: SceneFixture;

  /** Job completion metadata */
  metadata: ReconstructionMetadata;
}

export interface ReconstructionMetadata {
  /** Job ID that produced this output */
  jobId: string;

  /** Completion status */
  status: 'completed' | 'partial' | 'failed';

  /** Timestamp when processing completed */
  completedAt: string;

  /** Total processing time in milliseconds */
  processingTimeMs: number;

  /** Number of entities in the fixture */
  entitiesCount: number;

  /** Number of temporal anchor states */
  temporalAnchorsCount: number;

  /** Overall confidence score (0-1) */
  confidence: number;

  /** Warnings generated during reconstruction */
  warnings: ReconstructionWarning[];

  /** Entity-level confidence breakdown */
  entityConfidence: Record<string, number>;

  /** Source analysis summary */
  sourceAnalysis: {
    detectedEra: string;
    detectedSeason: string;
    detectedTimeOfDay: string;
    primaryMaterials: string[];
    architecturalStyle: string;
  };

  /** Refinement information (if this was a refinement job) */
  refinement?: {
    previousJobId: string;
    attemptNumber: number;
    improvements: string[];
  };
}

export interface ReconstructionWarning {
  code: ReconstructionWarningCode;
  message: string;
  entityId?: string;
  severity: 'low' | 'medium' | 'high';
}

export type ReconstructionWarningCode =
  | 'LOW_CONFIDENCE_ENTITY'
  | 'AMBIGUOUS_SCALE'
  | 'MISSING_TEMPORAL_DATA'
  | 'PARTIAL_SCENE_ANALYSIS'
  | 'STYLE_INCONSISTENCY'
  | 'SPATIAL_CROWDING'
  | 'UNRECOGNIZED_OBJECT';

/**
 * File structure in the output directory:
 *
 * <outputDir>/
 *   scene-fixture.json    — Complete SceneFixture
 *   metadata.json         — ReconstructionMetadata
 *   thumbnail.png         — Optional preview image
 *   analysis/
 *     source-analysis.json  — Raw scene analysis
 *     entity-detections.json — Detected entities with bounding boxes
 */
```

## 4. Error Handling

```typescript
// packages/contracts/src/reconstruction-errors.ts

/**
 * Error types that can occur during reconstruction.
 * The Worker Manager uses these to determine retry strategy.
 */
export type ReconstructionErrorCode =
  /** Claude subprocess crashed or exited with non-zero code */
  | 'WORKER_CRASH'
  /** Processing exceeded timeout */
  | 'WORKER_TIMEOUT'
  /** Output JSON failed schema validation */
  | 'INVALID_OUTPUT_SCHEMA'
  /** Output files are missing */
  | 'MISSING_OUTPUT_FILES'
  /** Output exceeds size limits */
  | 'OUTPUT_TOO_LARGE'
  /** Source image is corrupted or unreadable */
  | 'INVALID_SOURCE_IMAGE'
  /** Claude could not analyze the scene (e.g., blank image) */
  | 'SCENE_ANALYSIS_FAILED'
  /** Generated fixture has no entities */
  | 'EMPTY_FIXTURE'
  /** Disk space or I/O error */
  | 'STORAGE_ERROR'
  /** Job was cancelled by the backend */
  | 'CANCELLED'
  /** Unknown error */
  | 'UNKNOWN';

export interface ReconstructionError {
  code: ReconstructionErrorCode;
  message: string;
  jobId: string;
  attemptNumber: number;
  maxAttempts: number;
  retryable: boolean;
  details?: Record<string, unknown>;
  stack?: string;
}

export class WorkerTimeoutError extends Error {
  constructor(
    public readonly jobId: string,
    public readonly timeoutMs: number,
  ) {
    super(`Worker for job ${jobId} timed out after ${timeoutMs}ms`);
    this.name = 'WorkerTimeoutError';
  }
}

export class WorkerCrashError extends Error {
  constructor(
    public readonly jobId: string,
    public readonly exitCode: number | null,
    public readonly stderr: string,
  ) {
    super(`Worker for job ${jobId} crashed with exit code ${exitCode}`);
    this.name = 'WorkerCrashError';
  }
}

export class OutputValidationError extends Error {
  constructor(
    public readonly jobId: string,
    public readonly validationErrors: string[],
  ) {
    super(`Output validation failed: ${validationErrors.join(', ')}`);
    this.name = 'OutputValidationError';
  }
}

/**
 * Determines if an error is retryable.
 */
export function isRetryableError(error: ReconstructionError): boolean {
  const retryableCodes: ReconstructionErrorCode[] = [
    'WORKER_CRASH',
    'WORKER_TIMEOUT',
    'STORAGE_ERROR',
    'UNKNOWN',
  ];
  return retryableCodes.includes(error.code);
}

/**
 * Maps exit codes to error types.
 */
export function classifyExitCode(
  jobId: string,
  exitCode: number | null,
  stderr: string,
): ReconstructionError {
  if (exitCode === null) {
    return {
      code: 'WORKER_CRASH',
      message: 'Worker process was killed by signal',
      jobId,
      attemptNumber: 0,
      maxAttempts: 0,
      retryable: true,
    };
  }

  switch (exitCode) {
    case 137:  // SIGKILL (OOM or timeout)
      return {
        code: 'WORKER_TIMEOUT',
        message: 'Worker was killed (likely OOM or timeout)',
        jobId,
        attemptNumber: 0,
        maxAttempts: 0,
        retryable: true,
      };
    case 1:  // General error
      if (stderr.includes('SCENE_ANALYSIS_FAILED')) {
        return {
          code: 'SCENE_ANALYSIS_FAILED',
          message: 'Could not analyze the source image',
          jobId,
          attemptNumber: 0,
          maxAttempts: 0,
          retryable: false,
        };
      }
      return {
        code: 'WORKER_CRASH',
        message: `Worker exited with code 1: ${stderr.slice(0, 200)}`,
        jobId,
        attemptNumber: 0,
        maxAttempts: 0,
        retryable: true,
      };
    default:
      return {
        code: 'WORKER_CRASH',
        message: `Worker exited with code ${exitCode}`,
        jobId,
        attemptNumber: 0,
        maxAttempts: 0,
        retryable: true,
      };
  }
}
```

## 5. Retry Strategy

```typescript
// packages/contracts/src/reconstruction-retry.ts

export interface RetryPolicy {
  /** Maximum number of retry attempts (including initial) */
  maxAttempts: number;

  /** Base delay between retries in milliseconds */
  baseDelayMs: number;

  /** Maximum delay (cap for exponential backoff) */
  maxDelayMs: number;

  /** Backoff multiplier */
  backoffMultiplier: number;

  /** Jitter range (0-1) to add randomness to delay */
  jitterFactor: number;

  /** Errors that should NOT be retried */
  nonRetryableErrors: ReconstructionErrorCode[];
}

export const DEFAULT_RETRY_POLICY: RetryPolicy = {
  maxAttempts: 3,
  baseDelayMs: 5_000,      // 5 seconds
  maxDelayMs: 60_000,      // 1 minute
  backoffMultiplier: 2,
  jitterFactor: 0.2,
  nonRetryableErrors: [
    'INVALID_SOURCE_IMAGE',
    'SCENE_ANALYSIS_FAILED',
    'CANCELLED',
  ],
};

/**
 * Calculate the delay before the next retry attempt.
 * Uses exponential backoff with jitter.
 */
export function calculateRetryDelay(
  attemptNumber: number,
  policy: RetryPolicy = DEFAULT_RETRY_POLICY,
): number {
  const exponentialDelay = policy.baseDelayMs * Math.pow(
    policy.backoffMultiplier,
    attemptNumber - 1,
  );
  const cappedDelay = Math.min(exponentialDelay, policy.maxDelayMs);

  // Add jitter: ±jitterFactor of the delay
  const jitter = cappedDelay * policy.jitterFactor * (Math.random() * 2 - 1);
  return Math.max(0, Math.round(cappedDelay + jitter));
}

/**
 * Determine if a failed job should be retried.
 */
export function shouldRetry(
  error: ReconstructionError,
  attemptNumber: number,
  policy: RetryPolicy = DEFAULT_RETRY_POLICY,
): { retry: boolean; delayMs: number } {
  // Check if we've exhausted attempts
  if (attemptNumber >= policy.maxAttempts) {
    return { retry: false, delayMs: 0 };
  }

  // Check if error is non-retryable
  if (policy.nonRetryableErrors.includes(error.code)) {
    return { retry: false, delayMs: 0 };
  }

  // Check if error is retryable
  if (!isRetryableError(error)) {
    return { retry: false, delayMs: 0 };
  }

  return {
    retry: true,
    delayMs: calculateRetryDelay(attemptNumber, policy),
  };
}

/**
 * Build a refinement spec for a retry attempt.
 * Includes the previous attempt's output (if partial) and error context.
 */
export function buildRetryRefinement(
  previousJob: ReconstructionJob,
  previousError: ReconstructionError,
  attemptNumber: number,
): RefinementSpec | undefined {
  // Only include refinement if we have partial output
  if (previousError.code !== 'INVALID_OUTPUT_SCHEMA' &&
      previousError.code !== 'EMPTY_FIXTURE') {
    return undefined;
  }

  return {
    previousFixturePath: `${previousJob.output.outputDir}/scene-fixture.json`,
    refinementInstructions: [
      `Previous attempt failed with: ${previousError.message}`,
      'Please fix the issues and produce a valid SceneFixture.',
    ],
    attemptNumber,
    maxAttempts: previousJob.refinement?.maxAttempts ?? 3,
  };
}
```

## 6. Concurrency Limits

```typescript
// packages/contracts/src/reconstruction-concurrency.ts

export interface ConcurrencyConfig {
  /** Maximum number of Claude workers running simultaneously */
  maxConcurrentWorkers: number;

  /** Maximum jobs in the queue waiting for a worker */
  maxQueueSize: number;

  /** Memory limit per worker in MB */
  memoryLimitMbPerWorker: number;

  /** Total system memory budget for all workers in MB */
  totalMemoryBudgetMb: number;

  /** CPU cores to reserve per worker */
  cpuCoresPerWorker: number;

  /** Priority queue weights */
  priorityWeights: Record<string, number>;

  /** Cooldown period between spawning workers (ms) */
  spawnCooldownMs: number;
}

export const DEFAULT_CONCURRENCY: ConcurrencyConfig = {
  maxConcurrentWorkers: 4,        // Max 4 Claude instances at once
  maxQueueSize: 50,               // Up to 50 jobs waiting
  memoryLimitMbPerWorker: 2048,   // 2GB per worker
  totalMemoryBudgetMb: 8192,      // 8GB total budget
  cpuCoresPerWorker: 2,           // 2 cores per worker
  priorityWeights: {
    high: 3,
    normal: 2,
    low: 1,
  },
  spawnCooldownMs: 1_000,         // 1 second between spawns
};

/**
 * Worker Pool Manager
 * Manages the lifecycle of Claude worker subprocesses.
 */
export interface WorkerPool {
  /** Currently running workers */
  activeWorkers: Map<string, ActiveWorker>;

  /** Jobs waiting for a worker */
  queuedJobs: QueuedJob[];

  /** Pool configuration */
  config: ConcurrencyConfig;
}

export interface ActiveWorker {
  /** Job being processed */
  jobId: string;

  /** Process ID of the Claude subprocess */
  pid: number;

  /** When the worker was spawned */
  startedAt: Date;

  /** Current memory usage in MB */
  memoryUsageMb: number;

  /** Current CPU usage percentage */
  cpuUsagePercent: number;

  /** AbortController for cancellation */
  abortController: AbortController;
}

export interface QueuedJob {
  /** Job to process */
  job: ReconstructionJob;

  /** When the job was enqueued */
  enqueuedAt: Date;

  /** Priority score for ordering */
  priorityScore: number;
}

/**
 * Determines if a new worker can be spawned given current pool state.
 */
export function canSpawnWorker(pool: WorkerPool): {
  allowed: boolean;
  reason?: string;
} {
  const { config, activeWorkers } = pool;

  // Check max concurrent workers
  if (activeWorkers.size >= config.maxConcurrentWorkers) {
    return {
      allowed: false,
      reason: `Max concurrent workers reached (${config.maxConcurrentWorkers})`,
    };
  }

  // Check total memory budget
  const totalMemoryUsed = Array.from(activeWorkers.values())
    .reduce((sum, w) => sum + w.memoryUsageMb, 0);
  if (totalMemoryUsed + config.memoryLimitMbPerWorker > config.totalMemoryBudgetMb) {
    return {
      allowed: false,
      reason: `Total memory budget would be exceeded (${totalMemoryUsed}MB used)`,
    };
  }

  // Check spawn cooldown
  const lastSpawn = Array.from(activeWorkers.values())
    .sort((a, b) => b.startedAt.getTime() - a.startedAt.getTime())[0];
  if (lastSpawn) {
    const timeSinceLastSpawn = Date.now() - lastSpawn.startedAt.getTime();
    if (timeSinceLastSpawn < config.spawnCooldownMs) {
      return {
        allowed: false,
        reason: `Spawn cooldown active (${config.spawnCooldownMs - timeSinceLastSpawn}ms remaining)`,
      };
    }
  }

  return { allowed: true };
}

/**
 * Priority queue ordering: higher priority first, then FIFO.
 */
export function compareQueuedJobs(a: QueuedJob, b: QueuedJob): number {
  // Higher priority score first
  if (a.priorityScore !== b.priorityScore) {
    return b.priorityScore - a.priorityScore;
  }
  // Earlier enqueue time first (FIFO)
  return a.enqueuedAt.getTime() - b.enqueuedAt.getTime();
}
```

## 7. Progress Reporting

```typescript
// packages/contracts/src/reconstruction-progress.ts

/**
 * Progress events emitted by the Worker Manager.
 * These are sent via the callback URL and also logged.
 */
export type ReconstructionProgressEvent =
  | JobQueuedEvent
  | JobStartedEvent
  | AnalysisProgressEvent
  | EntityDetectedEvent
  | TemporalAnalysisEvent
  | FixtureGeneratedEvent
  | ValidationProgressEvent
  | JobCompletedEvent
  | JobFailedEvent
  | JobRetryingEvent;

export interface JobQueuedEvent {
  type: 'job.queued';
  jobId: string;
  timestamp: string;
  queuePosition: number;
  estimatedWaitMs: number;
}

export interface JobStartedEvent {
  type: 'job.started';
  jobId: string;
  timestamp: string;
  workerPid: number;
  attemptNumber: number;
}

export interface AnalysisProgressEvent {
  type: 'analysis.progress';
  jobId: string;
  timestamp: string;
  phase: 'scene_detection' | 'entity_recognition' | 'temporal_analysis' | 'fixture_generation';
  progress: number;  // 0-100
  message: string;
}

export interface EntityDetectedEvent {
  type: 'entity.detected';
  jobId: string;
  timestamp: string;
  entityId: string;
  entityCategory: string;
  confidence: number;
  boundingBox?: { x: number; y: number; width: number; height: number };
}

export interface TemporalAnalysisEvent {
  type: 'temporal.analysis';
  jobId: string;
  timestamp: string;
  detectedEra: string;
  detectedYear: number;
  confidence: number;
}

export interface FixtureGeneratedEvent {
  type: 'fixture.generated';
  jobId: string;
  timestamp: string;
  entitiesCount: number;
  temporalAnchorsCount: number;
}

export interface ValidationProgressEvent {
  type: 'validation.progress';
  jobId: string;
  timestamp: string;
  checksPassed: number;
  checksTotal: number;
  warnings: string[];
}

export interface JobCompletedEvent {
  type: 'job.completed';
  jobId: string;
  timestamp: string;
  processingTimeMs: number;
  fixturePath: string;
  metadataPath: string;
  confidence: number;
}

export interface JobFailedEvent {
  type: 'job.failed';
  jobId: string;
  timestamp: string;
  errorCode: ReconstructionErrorCode;
  message: string;
  attemptNumber: number;
  maxAttempts: number;
  willRetry: boolean;
}

export interface JobRetryingEvent {
  type: 'job.retrying';
  jobId: string;
  timestamp: string;
  attemptNumber: number;
  nextRetryAt: string;
  delayMs: number;
  reason: string;
}

/**
 * Callback URL payload sent to the backend.
 * The backend uses this to update job status and notify the iOS app.
 */
export interface ReconstructionCallback {
  /** The progress event */
  event: ReconstructionProgressEvent;

  /** Job context */
  job: {
    jobId: string;
    sourceAssetId: string;
    targetYear: number;
  };

  /** Optional: updated output paths (on completion) */
  outputs?: {
    fixtureUrl: string;
    metadataUrl: string;
    thumbnailUrl?: string;
  };
}

/**
 * Worker progress reporter.
 * Claude emits structured progress via stderr, which the Worker Manager
 * parses and forwards to the callback URL.
 */
export interface ProgressReporter {
  /** Emit a progress event */
  emit(event: ReconstructionProgressEvent): Promise<void>;

  /** Close the reporter and flush pending events */
  close(): Promise<void>;
}

/**
 * Parse Claude's stderr output for progress markers.
 * Claude is instructed to emit progress in a specific format:
 *
 *   [PROGRESS] phase=entity_recognition progress=45 message="Detected 3 buildings"
 *   [ENTITY] id=building_01 category=architecture confidence=0.92
 *   [TEMPORAL] era="Modern" year=2024 confidence=0.85
 */
export function parseProgressLine(line: string): ReconstructionProgressEvent | null {
  const progressMatch = line.match(
    /\[PROGRESS\] phase=(\w+) progress=(\d+) message="([^"]+)"/
  );
  if (progressMatch) {
    return {
      type: 'analysis.progress',
      jobId: '',  // Filled by caller
      timestamp: new Date().toISOString(),
      phase: progressMatch[1] as AnalysisProgressEvent['phase'],
      progress: parseInt(progressMatch[2]),
      message: progressMatch[3],
    };
  }

  const entityMatch = line.match(
    /\[ENTITY\] id=(\w+) category=(\w+) confidence=([\d.]+)/
  );
  if (entityMatch) {
    return {
      type: 'entity.detected',
      jobId: '',
      timestamp: new Date().toISOString(),
      entityId: entityMatch[1],
      entityCategory: entityMatch[2],
      confidence: parseFloat(entityMatch[3]),
    };
  }

  const temporalMatch = line.match(
    /\[TEMPORAL\] era="([^"]+)" year=(\d+) confidence=([\d.]+)/
  );
  if (temporalMatch) {
    return {
      type: 'temporal.analysis',
      jobId: '',
      timestamp: new Date().toISOString(),
      detectedEra: temporalMatch[1],
      detectedYear: parseInt(temporalMatch[2]),
      confidence: parseFloat(temporalMatch[3]),
    };
  }

  return null;
}
```

## Worker Manager Implementation

```typescript
// packages/contracts/src/reconstruction-manager.ts

export interface WorkerManager {
  /** Enqueue a new reconstruction job */
  enqueue(job: ReconstructionJob): Promise<string>;

  /** Cancel a running or queued job */
  cancel(jobId: string): Promise<boolean>;

  /** Get job status */
  getStatus(jobId: string): Promise<JobStatus>;

  /** Get pool statistics */
  getStats(): Promise<WorkerPoolStats>;
}

export type JobStatus =
  | 'queued'
  | 'processing'
  | 'completed'
  | 'failed'
  | 'cancelled'
  | 'retrying';

export interface JobStatusInfo {
  jobId: string;
  status: JobStatus;
  attemptNumber: number;
  maxAttempts: number;
  queuedAt: string;
  startedAt?: string;
  completedAt?: string;
  error?: ReconstructionError;
  outputs?: {
    fixturePath: string;
    metadataPath: string;
  };
}

export interface WorkerPoolStats {
  activeWorkers: number;
  maxWorkers: number;
  queuedJobs: number;
  completedJobs: number;
  failedJobs: number;
  averageProcessingTimeMs: number;
}
```

## Usage Example: Backend Enqueuing a Job

```typescript
// server/src/routes/reconstruction.ts

import { randomUUID } from 'node:crypto';
import type { ReconstructionJob } from '@fumira/contracts';

export async function handleK230Frame(frame: {
  imagePath: string;
  width: number;
  height: number;
  metadata: { frameId: string | null; timestamp: string | null };
}): Promise<string> {
  const jobId = randomUUID();

  const job: ReconstructionJob = {
    jobId,
    createdAt: new Date().toISOString(),
    priority: 'normal',
    source: {
      path: frame.imagePath,
      width: frame.width,
      height: frame.height,
      metadata: {
        frameId: frame.metadata.frameId,
        timestamp: frame.metadata.timestamp,
      },
      hash: await computeFileHash(frame.imagePath),
    },
    temporal: {
      targetYear: 2050,
      normalizedPosition: 0.5,
      compactLabel: '+24 years',
      season: 'summer',
      timeOfDay: 'afternoon',
    },
    output: {
      outputDir: `/data/reconstructions/${jobId}`,
      files: {
        fixture: 'scene-fixture.json',
        metadata: 'metadata.json',
        thumbnail: 'thumbnail.png',
      },
      maxOutputBytes: 10 * 1024 * 1024,  // 10MB
    },
    callbackUrl: `${process.env.PUBLIC_BASE_URL}/v1/reconstruction/callback`,
  };

  await workerManager.enqueue(job);
  return jobId;
}
```

## Integration with Scene Runtime

The output SceneFixture is directly consumable by the existing `@fumira/scene-runtime`:

```typescript
// apps/display/src/main.ts
import { createScene, loadEntities, startAnimationLoop } from '@fumira/scene-runtime';
import type { SceneFixture } from '@fumira/contracts';

// Load the fixture generated by Claude Reconstruction Worker
const fixture: SceneFixture = await fetch('/reconstructions/job-123/scene-fixture.json')
  .then(r => r.json());

const canvas = document.getElementById('canvas') as HTMLCanvasElement;
const sceneHandle = createScene(fixture, canvas);
const entities = loadEntities(fixture, sceneHandle.scene, sceneHandle);

// Start temporal animation
const controller = startAnimationLoop(sceneHandle, entities, fixture, {
  onUpdateUI: (year) => {
    document.getElementById('year-label')!.textContent = year.toFixed(0);
  },
});

// Time slider integration
document.getElementById('time-slider')!.addEventListener('input', (e) => {
  const target = e.target as HTMLInputElement;
  controller.setYear(parseFloat(target.value));
});
```
