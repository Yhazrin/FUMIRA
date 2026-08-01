// ── worker-prompt.js ─────────────────────────────────────────
// Generates prompts for the Claude Reconstruction Worker.
// Pure ESM module — no side effects, no imports.
// ─────────────────────────────────────────────────────────────

/**
 * JSON Schema describing the exact output contract the Claude worker
 * must satisfy.  Scene Compiler and downstream consumers validate against this.
 */
export const OUTPUT_SCHEMA = {
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  title: 'TemporalWorldReconstructionOutput',
  type: 'object',
  required: ['scene', 'metadata'],
  properties: {
    scene: {
      type: 'object',
      required: ['entities', 'camera', 'lighting'],
      properties: {
        entities: {
          type: 'array',
          items: {
            type: 'object',
            required: ['id', 'type', 'geometry', 'material', 'temporalRange', 'confidence'],
            properties: {
              id: {
                type: 'string',
                pattern: '^entity_\\d{3,}$',
                description: 'Unique entity identifier, e.g. entity_001'
              },
              type: {
                type: 'string',
                enum: ['building', 'tree', 'vehicle', 'terrain', 'object']
              },
              geometry: {
                type: 'object',
                required: ['type', 'dimensions', 'position', 'rotation'],
                properties: {
                  type: {
                    type: 'string',
                    enum: ['box', 'sphere', 'cylinder', 'plane', 'custom']
                  },
                  dimensions: {
                    type: 'object',
                    required: ['width', 'height', 'depth'],
                    properties: {
                      width:  { type: 'number', minimum: 0 },
                      height: { type: 'number', minimum: 0 },
                      depth:  { type: 'number', minimum: 0 }
                    }
                  },
                  position: {
                    type: 'object',
                    required: ['x', 'y', 'z'],
                    properties: {
                      x: { type: 'number' },
                      y: { type: 'number' },
                      z: { type: 'number' }
                    }
                  },
                  rotation: {
                    type: 'object',
                    required: ['x', 'y', 'z'],
                    properties: {
                      x: { type: 'number' },
                      y: { type: 'number' },
                      z: { type: 'number' }
                    }
                  }
                }
              },
              material: {
                type: 'object',
                required: ['color', 'roughness', 'metalness', 'opacity'],
                properties: {
                  color:     { type: 'string', pattern: '^#[0-9A-Fa-f]{6}$' },
                  roughness: { type: 'number', minimum: 0, maximum: 1 },
                  metalness: { type: 'number', minimum: 0, maximum: 1 },
                  opacity:   { type: 'number', minimum: 0, maximum: 1 }
                }
              },
              temporalRange: {
                type: 'object',
                required: ['start', 'end'],
                properties: {
                  start: { type: 'number', minimum: -1, maximum: 1 },
                  end:   { type: 'number', minimum: -1, maximum: 1 }
                }
              },
              confidence: {
                type: 'number',
                minimum: 0,
                maximum: 1,
                description: 'Model confidence in this entity detection, 0..1'
              }
            }
          }
        },
        camera: {
          type: 'object',
          required: ['position', 'target'],
          properties: {
            position: {
              type: 'object',
              required: ['x', 'y', 'z'],
              properties: {
                x: { type: 'number' },
                y: { type: 'number' },
                z: { type: 'number' }
              }
            },
            target: {
              type: 'object',
              required: ['x', 'y', 'z'],
              properties: {
                x: { type: 'number' },
                y: { type: 'number' },
                z: { type: 'number' }
              }
            }
          }
        },
        lighting: {
          type: 'object',
          required: ['ambient', 'directional'],
          properties: {
            ambient: {
              type: 'object',
              required: ['color', 'intensity'],
              properties: {
                color:     { type: 'string', pattern: '^#[0-9A-Fa-f]{6}$' },
                intensity: { type: 'number', minimum: 0, maximum: 2 }
              }
            },
            directional: {
              type: 'object',
              required: ['color', 'intensity', 'position'],
              properties: {
                color:     { type: 'string', pattern: '^#[0-9A-Fa-f]{6}$' },
                intensity: { type: 'number', minimum: 0, maximum: 2 },
                position: {
                  type: 'object',
                  required: ['x', 'y', 'z'],
                  properties: {
                    x: { type: 'number' },
                    y: { type: 'number' },
                    z: { type: 'number' }
                  }
                }
              }
            }
          }
        }
      }
    },
    metadata: {
      type: 'object',
      required: ['sceneDescription', 'dominantColors', 'complexity', 'estimatedVertices'],
      properties: {
        sceneDescription: { type: 'string', maxLength: 500 },
        dominantColors: {
          type: 'array',
          items: { type: 'string', pattern: '^#[0-9A-Fa-f]{6}$' },
          minItems: 1,
          maxItems: 8
        },
        complexity: {
          type: 'string',
          enum: ['low', 'medium', 'high']
        },
        estimatedVertices: {
          type: 'integer',
          minimum: 0
        }
      }
    }
  }
};

// ── Internal helpers ─────────────────────────────────────────

const TEMPORAL_LABELS = {
  '-1': 'the past (decayed, ancient, overgrown, ruins)',
  '0':  'the present (current state)',
  '1':  'the future (futuristic, advanced, evolved, sci-fi)'
};

/**
 * Build a temporal modification instruction block.
 */
function temporalInstruction(target) {
  const label = TEMPORAL_LABELS[String(target)] ?? `time offset ${target}`;
  return [
    `TEMPORAL TARGET: ${label} (value: ${target})`,
    '',
    'For every entity, assign a temporalRange that reflects when the entity',
    'exists in the scene.  An entity that is always present should span the',
    'full range [-1, 1].  An entity unique to the target time should span a',
    'narrow band around that value.  Morph the appearance, colour, material,',
    'and geometry of each entity so it plausibly belongs in the target time.'
  ].join('\n');
}

/**
 * Build the constraint block (optional).
 */
function constraintBlock(constraints = {}) {
  const lines = [];
  if (constraints.maxEntities) {
    lines.push(`- Limit output to at most ${constraints.maxEntities} entities.`);
  }
  if (constraints.maxComplexity) {
    lines.push(`- Scene complexity must be "${constraints.maxComplexity}" or lower.`);
  }
  if (constraints.excludeTypes?.length) {
    lines.push(`- Exclude entity types: ${constraints.excludeTypes.join(', ')}.`);
  }
  if (constraints.biasMaterials) {
    lines.push(`- Bias material properties toward: ${constraints.biasMaterials}.`);
  }
  if (constraints.focusArea) {
    lines.push(`- Focus reconstruction on area: ${JSON.stringify(constraints.focusArea)}.`);
  }
  return lines.length ? `\nADDITIONAL CONSTRAINTS:\n${lines.join('\n')}` : '';
}

/**
 * Build the previous-assets hint block (optional).
 */
function previousAssetsBlock(previousAssets) {
  if (!previousAssets?.length) return '';
  const summary = previousAssets
    .map((a, i) => `  ${i + 1}. [${a.type}] id=${a.id} — ${a.description ?? 'no description'}`)
    .join('\n');
  return [
    '',
    'PREVIOUSLY DETECTED ASSETS (reuse or refine these where appropriate):',
    summary,
    ''
  ].join('\n');
}

/**
 * Return a canonical string of the expected JSON shape so Claude sees
 * the contract inline with the prompt.
 */
const OUTPUT_EXAMPLE = `{
  "scene": {
    "entities": [
      {
        "id": "entity_001",
        "type": "building",
        "geometry": {
          "type": "box",
          "dimensions": { "width": 1, "height": 1, "depth": 1 },
          "position": { "x": 0, "y": 0, "z": 0 },
          "rotation": { "x": 0, "y": 0, "z": 0 }
        },
        "material": {
          "color": "#8B7355",
          "roughness": 0.8,
          "metalness": 0.1,
          "opacity": 1.0
        },
        "temporalRange": { "start": -1, "end": 1 },
        "confidence": 0.85
      }
    ],
    "camera": {
      "position": { "x": 0, "y": 5, "z": 10 },
      "target": { "x": 0, "y": 0, "z": 0 }
    },
    "lighting": {
      "ambient": { "color": "#F7F5EF", "intensity": 0.6 },
      "directional": { "color": "#FFE4B5", "intensity": 0.8, "position": { "x": 5, "y": 10, "z": 5 } }
    }
  },
  "metadata": {
    "sceneDescription": "A clay-style village scene with soft buildings",
    "dominantColors": ["#8B7355", "#4A90D9", "#B7D83D"],
    "complexity": "medium",
    "estimatedVertices": 1200
  }
}`;

// ── Public API ───────────────────────────────────────────────

/**
 * Generate the full reconstruction prompt for the Claude worker.
 *
 * @param {string}       imagePath          – absolute path to the K230 input image
 * @param {number}       temporalTarget     – -1 (past), 0 (present), or 1 (future)
 * @param {Array=}       previousAssets     – optional array of previously detected assets
 * @param {Object=}      constraints        – optional generation constraints
 * @param {number=}      constraints.maxEntities
 * @param {string=}      constraints.maxComplexity
 * @param {string[]=}    constraints.excludeTypes
 * @param {string=}      constraints.biasMaterials
 * @param {Object=}      constraints.focusArea
 * @returns {string} The prompt string to pipe into the Claude CLI
 */
export function generateReconstructionPrompt(
  imagePath,
  temporalTarget,
  previousAssets,
  constraints
) {
  return `You are the Temporal World Reconstruction Worker.  Your job is to analyse a photograph and produce a structured 3D scene description that the Scene Compiler will render in Three.js.

INPUT IMAGE (filesystem path — read this file):
  ${imagePath}

TASK
1. Open and analyse the image at the path above.
2. Identify every distinct visual entity (buildings, trees, vehicles, terrain, objects).
3. For each entity infer approximate geometry (primitive type + dimensions), world-space position, rotation, and material properties (PBR colour, roughness, metalness, opacity).
4. Place a virtual camera that best reproduces the photo viewpoint.
5. Estimate ambient + directional lighting that matches the scene mood.
${temporalInstruction(temporalTarget)}
${previousAssetsBlock(previousAssets)}
${constraintBlock(constraints)}
OUTPUT FORMAT
Return ONLY a single JSON object (no markdown fences, no commentary) that matches the schema below.  Every field listed as required MUST be present.

EXPECTED JSON SHAPE:
${OUTPUT_EXAMPLE}

VALIDATION RULES
- Every entity id must match pattern ^entity_\\d{3,}$ and be unique.
- Geometry dimensions, position, and rotation values must be finite numbers.
- Material colour must be a 7-character hex string (#RRGGBB).
- Roughness, metalness, opacity must each be between 0 and 1 inclusive.
- Confidence must be between 0 and 1 inclusive.
- temporalRange.start must be <= temporalRange.end, both within [-1, 1].
- metadata.estimatedVertices must be a non-negative integer.
- metadata.complexity must be one of: "low", "medium", "high".

Begin analysis now.  Output the JSON and nothing else.`;
}

/**
 * Generate a refinement prompt that iterates on an existing scene
 * based on user feedback.
 *
 * @param {string}  imagePath      – absolute path to the original K230 image
 * @param {Object}  currentAssets  – the current scene JSON (previous reconstruction output)
 * @param {string}  userFeedback   – natural-language feedback from the user
 * @returns {string} The refinement prompt string
 */
export function generateRefinementPrompt(imagePath, currentAssets, userFeedback) {
  const currentJson = typeof currentAssets === 'string'
    ? currentAssets
    : JSON.stringify(currentAssets, null, 2);

  return `You are the Temporal World Reconstruction Worker (refinement pass).  You previously produced a scene description; the user has feedback.

ORIGINAL INPUT IMAGE (read this file):
  ${imagePath}

CURRENT SCENE JSON:
${currentJson}

USER FEEDBACK:
"${userFeedback}"

TASK
1. Re-read the original image.
2. Apply the user feedback by adjusting entity geometries, materials, positions, temporal ranges, camera, or lighting as needed.
3. If the user requests removal of an entity, remove it and renumber subsequent ids so the sequence remains contiguous (entity_001, entity_002, ...).
4. If the user requests a new entity, add it in a plausible location with appropriate properties.
5. Preserve all entities and properties that the feedback does not touch.

OUTPUT FORMAT
Return ONLY the updated JSON object — same schema, same validation rules as the original reconstruction.  No markdown fences, no commentary.

EXPECTED JSON SHAPE:
${OUTPUT_EXAMPLE}

VALIDATION RULES (same as original pass)
- Every entity id must match pattern ^entity_\\d{3,}$ and be unique.
- Geometry dimensions, position, and rotation values must be finite numbers.
- Material colour must be a 7-character hex string (#RRGGBB).
- Roughness, metalness, opacity must each be between 0 and 1 inclusive.
- Confidence must be between 0 and 1 inclusive.
- temporalRange.start must be <= temporalRange.end, both within [-1, 1].
- metadata.estimatedVertices must be a non-negative integer.
- metadata.complexity must be one of: "low", "medium", "high".

Begin refinement now.  Output the JSON and nothing else.`;
}
