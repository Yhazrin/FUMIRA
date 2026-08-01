import type { StyleProfile } from './canonical-scene';

// Job types for the reconstruction pipeline

export type JobType =
  | 'full-reconstruction'    // photo → complete scene
  | 'refine-entity'          // refine single entity
  | 'build-variant'          // build entity variant
  | 'temporal-variant'       // build temporal anchor state
  | 'review-continuity'      // check temporal consistency
  | 'repair-failed';         // fix failed entity

export type JobStatus =
  | 'pending'
  | 'analyzing'       // Xiaomi vision running
  | 'blockouting'     // fast Clay Builders running
  | 'refining'        // Claude Worker running
  | 'reviewing'       // visual review running
  | 'completed'
  | 'failed'
  | 'cancelled';

export interface ReconstructionJob {
  id: string;
  type: JobType;
  status: JobStatus;

  // Input
  input: JobInput;

  // Progress
  progress: JobProgress;

  // Result
  result?: JobResult;
  error?: string;

  // Timing
  createdAt: number;
  startedAt?: number;
  completedAt?: number;

  // Retry
  retryCount: number;
  maxRetries: number;
}

export interface JobInput {
  photoPath?: string;
  sceneSpecPath?: string;
  entityId?: string;
  targetTime?: number;
  styleProfile?: StyleProfile;
  constraints?: Record<string, any>;
  parentJobId?: string;
}

export interface JobProgress {
  phase: string;
  percent: number;
  message: string;
  detail?: any;
}

export interface JobResult {
  sceneSpecPath?: string;
  entityPatches?: EntityPatch[];
  reviewReport?: ReviewReport;
  artifacts: Artifact[];
}

export interface EntityPatch {
  entityId: string;
  patchType: 'geometry' | 'material' | 'transform' | 'variant';
  patchData: any;
  confidence: number;
}

export interface ReviewReport {
  passed: boolean;
  score: number;
  issues: ReviewIssue[];
  suggestions: string[];
}

export interface ReviewIssue {
  entityId: string;
  severity: 'low' | 'medium' | 'high';
  description: string;
  suggestion: string;
}

export interface Artifact {
  type: 'scene-spec' | 'entity-geometry' | 'texture' | 'render' | 'report';
  path: string;
  size: number;
  hash: string;
}

// Claude Worker specific task types
export type ClaudeWorkerTaskType =
  | 'BUILD_BASE_SCENE'
  | 'REFINE_ENTITY'
  | 'BUILD_CHARACTER_VARIANT'
  | 'BUILD_TEMPORAL_VARIANT'
  | 'REVIEW_CONTINUITY'
  | 'REPAIR_FAILED_ENTITY';

export interface ClaudeWorkerTask {
  taskType: ClaudeWorkerTaskType;
  jobId: string;
  entityId?: string;
  sceneSpecPath: string;
  referenceImagePath?: string;
  styleProfilePath?: string;
  outputDirectory: string;
  maxTurns: number;
  timeoutMs: number;
  constraints?: Record<string, any>;
}

export interface ClaudeWorkerResult {
  success: boolean;
  taskId: string;
  jobId: string;
  outputFiles: string[];
  sceneSpec?: any;
  entityPatches?: EntityPatch[];
  reviewReport?: ReviewReport;
  turnsUsed: number;
  durationMs: number;
  error?: string;
}
