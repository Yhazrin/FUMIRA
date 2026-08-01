// ──────────────────────────────────────────────────────────────────────────────
// FUMIRA Reconstruction Job Contract
// ──────────────────────────────────────────────────────────────────────────────
// Defines the schema for jobs dispatched by the local backend to the Claude
// Reconstruction Worker.  A job describes a single 3D reconstruction request
// derived from a K230 camera frame, and carries everything the worker needs
// to produce mesh / texture / metadata assets that the Scene Compiler can
// consume.
// ──────────────────────────────────────────────────────────────────────────────

/** UUIDv4 string, e.g. "3a1b9c04-7f22-4d81-b6e0-c9f3a22d1e7b". */
export type JobId = string;

/**
 * Reference to a JPEG frame already stored by the K230 receiver on port 19999.
 * This is the filename returned by `POST /k230/frame`, e.g.
 * `"k230_20260801_143022_f000042.jpg"`.
 */
export type FrameFilename = string;

/**
 * The nature of the reconstruction pass.
 *
 * - `initial_reconstruction` — first-pass depth + mesh from a brand-new frame.
 * - `refinement`            — re-run with additional frames or better
 *                              heuristics; may replace a prior mesh.
 * - `correction`            — user-directed fix (see `userConstraints`).
 */
export type JobType =
  | "initial_reconstruction"
  | "refinement"
  | "correction";

/**
 * Normalised temporal position on the FUMIRA timeline.
 * Range: **-100** (deep past) .. **0** (present) .. **+100** (far future).
 * Interpolation uses this value to blend entity states from
 * `TemporalAnchorState` entries in the scene fixture.
 */
export type TemporalPosition = number & { readonly __brand: "TemporalPosition" };

/** Factory helper — clamps to [-100, +100] and brands the value. */
export function temporalPosition(raw: number): TemporalPosition {
  return Math.max(-100, Math.min(100, raw)) as TemporalPosition;
}

/**
 * K230-specific camera intrinsics.
 * The worker uses these to estimate the projection matrix for depth
 * unprojection.  Values are best-effort hints — the worker will attempt
 * self-calibration if they are absent.
 */
export interface CameraIntrinsicsHint {
  /** Focal length in pixels (x). */
  fx: number | null;
  /** Focal length in pixels (y). */
  fy: number | null;
  /** Principal point x (pixels from left).  Defaults to width/2 when null. */
  cx: number | null;
  /** Principal point y (pixels from top).   Defaults to height/2 when null. */
  cy: number | null;
  /** Horizontal resolution of the source frame in pixels. */
  width: number;
  /** Vertical resolution of the source frame in pixels. */
  height: number;
}

/**
 * User-supplied constraints for `correction` jobs.
 * Only meaningful when `jobType === "correction"`.
 */
export interface UserConstraints {
  /**
   * Free-text instruction, e.g. "the roof geometry is wrong — it should be
   * flat, not pitched" or "remove the tree that occludes the doorway".
   */
  instruction: string;

  /**
   * Optional 2-D mask (PNG, base64) highlighting the region of the frame
   * the correction applies to.  The worker should focus its edits there.
   */
  maskBase64?: string;

  /**
   * Optional list of entity IDs from the scene fixture that are relevant
   * to the correction, e.g. `["building_01", "tree_03"]`.
   */
  targetEntityIds?: string[];
}

/**
 * Processing priority of the job.
 *
 * - `normal` — default; processed in FIFO order.
 * - `high`   — user-initiated corrections jump the queue.
 */
export type JobPriority = "normal" | "high";

export type JobStatus =
  | "pending"
  | "processing"
  | "completed"
  | "failed";

/**
 * Output artifacts produced by a successful reconstruction.
 * The Scene Compiler fetches these to update the Three.js scene.
 */
export interface ReconstructionResult {
  /** Relative path (or URL) to the generated mesh (e.g. `.glb`). */
  meshUrl: string;
  /** Relative path (or URL) to the baked texture atlas. */
  textureUrl: string;
  /** Free-form metadata the worker wants to pass through. */
  metadata: Record<string, unknown>;
}

// ──────────────────────────────────────────────────────────────────────────────
// ReconstructionJob — the primary transport object
// ──────────────────────────────────────────────────────────────────────────────

export interface ReconstructionJob {
  /** Unique job identifier (UUIDv4). */
  id: JobId;

  /** Filename of the source JPEG frame as stored by the K230 receiver. */
  sourceFrame: FrameFilename;

  /** What kind of reconstruction pass this is. */
  jobType: JobType;

  /**
   * Best-guess intrinsics from the K230 board.  The worker may override
   * these after self-calibration.
   */
  cameraIntrinsics: CameraIntrinsicsHint;

  /**
   * Normalised temporal position on the FUMIRA timeline.
   * The worker uses this to apply weathering, growth, and structural
   * variants matching the requested era.
   */
  temporalPosition: TemporalPosition;

  /**
   * User constraints — required for `correction` jobs, absent otherwise.
   * Discriminated by `jobType`.
   */
  userConstraints: UserConstraints | null;

  /** Queue priority.  `high` jobs are dequeued before `normal` ones. */
  priority: JobPriority;

  /**
   * URL the worker POSTs a status notification to when the job completes
   * or fails.  Typically `http://localhost:19999/callback/reconstruction`.
   */
  callbackUrl: string;

  /** Current processing status. */
  status: JobStatus;

  /** ISO-8601 timestamp when the job was enqueued. */
  createdAt: string;

  /** ISO-8601 timestamp when processing started (null if pending). */
  startedAt: string | null;

  /** ISO-8601 timestamp when processing ended (null if not yet finished). */
  completedAt: string | null;

  /**
   * Present only when `status === "completed"`.
   * Contains the output artifacts the Scene Compiler consumes.
   */
  result: ReconstructionResult | null;

  /**
   * Present only when `status === "failed"`.
   * Human-readable description of the failure.
   */
  error: string | null;
}

// ──────────────────────────────────────────────────────────────────────────────
// Job Queue interface
// ──────────────────────────────────────────────────────────────────────────────

/**
 * In-process job queue.  The local backend owns a singleton implementation;
 * workers and the Scene Compiler interact with it via the REST surface
 * (not shown here — this is the typed contract only).
 */
export interface JobQueue {
  /**
   * Add a new job to the queue.
   * The job must have `status: "pending"`.  Returns the assigned job ID.
   */
  enqueue(job: Omit<ReconstructionJob, "status" | "createdAt" | "startedAt" | "completedAt" | "result" | "error">): JobId;

  /**
   * Dequeue the highest-priority pending job and transition it to
   * `processing`.  Returns `null` when the queue is empty.
   */
  dequeue(): ReconstructionJob | null;

  /**
   * Retrieve the current state of a job by ID, including its result or
   * error payload.
   */
  getJob(id: JobId): ReconstructionJob | null;

  /**
   * Cancel a pending or in-progress job.  The job transitions to `failed`
   * with `error: "cancelled"`.  Returns `true` if the job was found and
   * cancelled, `false` if it was already completed or did not exist.
   */
  cancelJob(id: JobId): boolean;
}

// ──────────────────────────────────────────────────────────────────────────────
// Callback payload (what the worker POSTs to `callbackUrl`)
// ──────────────────────────────────────────────────────────────────────────────

/**
 * The worker sends this JSON body to the `callbackUrl` when a job finishes
 * (successfully or not).  The backend uses it to update the job record and
 * notify the Scene Compiler.
 */
export interface ReconstructionCallback {
  jobId: JobId;
  status: "completed" | "failed";
  result: ReconstructionResult | null;
  error: string | null;
}
