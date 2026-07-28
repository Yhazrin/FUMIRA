import type {
  GenerationValidationResult,
  PostGenerationValidationAdapter,
  PostGenerationValidationInput,
  PostGenerationValidationResult,
} from "../types.js";

export interface MockValidationBehavior {
  result?: GenerationValidationResult;
  failure?: { errorCode: string; userMessage: string; retryable: boolean };
}

/**
 * Mock validator for tests. By default it produces a passing validation so
 * the generation pipeline behaves as before; tests inject failures or repair
 * requests to assert the auto-redraw logic.
 */
export class MockValidationAdapter implements PostGenerationValidationAdapter {
  readonly calls: PostGenerationValidationInput[] = [];
  public behavior: MockValidationBehavior;

  constructor(behavior: MockValidationBehavior = {}) {
    this.behavior = behavior;
  }

  async validate(
    input: PostGenerationValidationInput
  ): Promise<PostGenerationValidationResult> {
    this.calls.push(input);
    if (this.behavior.failure) {
      return {
        ok: false,
        errorCode: this.behavior.failure.errorCode,
        userMessage: this.behavior.failure.userMessage,
        retryable: this.behavior.failure.retryable,
      };
    }
    return {
      ok: true,
      value: this.behavior.result ?? defaultPassingResult(),
    };
  }
}

export function defaultPassingResult(): GenerationValidationResult {
  return {
    cameraConsistency: 0.96,
    anchorPreservation: 0.94,
    identityConsistency: 0.9,
    temporalCoverage: 0.85,
    eraCoherence: 0.88,
    storyAlignment: 0.9,
    problems: [],
    repairInstructions: [],
    shouldRegenerate: false,
  };
}
