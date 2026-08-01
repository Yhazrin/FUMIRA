/**
 * Xiaomi Vision Provider
 *
 * Interfaces with Xiaomi's multimodal model for scene understanding.
 * Supports two modes:
 *   MOCK  - returns canned responses (for testing / offline demo)
 *   LIVE  - calls the actual Xiaomi vision API via fetch()
 *
 * Public surface:
 *   analyzePhoto(photoPath)        -> PhotoAnalysis
 *   generateSceneSpec(vision)       -> CanonicalSceneSpec
 *   generateStory(sceneSpec, range) -> Story
 *   generateReferenceImages(sceneSpec, years) -> RenderResult[]
 *   reviewScene(sceneSpec)          -> ReviewResult
 */

export class XiaomiProvider {
  #apiKey;
  #baseUrl;
  #isMock;

  /**
   * @param {object}  opts
   * @param {string}  opts.apiKey  - Xiaomi API key (falsy => mock mode)
   * @param {string}  [opts.baseUrl] - API base URL
   * @param {boolean} [opts.mock]  - force mock mode even when apiKey is set
   */
  constructor({ apiKey, baseUrl, mock = false }) {
    this.#apiKey = apiKey;
    this.#baseUrl = baseUrl || 'https://api.xiaomi.com/vision/v1';
    this.#isMock = mock || !apiKey;
  }

  // ── Public API ──────────────────────────────────────────────────────────

  async analyzePhoto(photoPath) {
    if (this.#isMock) return this.#mockAnalyzePhoto(photoPath);

    const imageData = await this.#readImageAsBase64(photoPath);
    const response = await this.#callApi('/analyze', {
      image: imageData,
      features: ['objects', 'scene', 'style', 'colors', 'time_of_day', 'weather'],
    });
    return {
      objects: response.objects || [],
      scene: response.scene || '',
      style: response.style || '',
      dominantColors: response.dominant_colors || [],
      timeOfDay: response.time_of_day || 'unknown',
      weather: response.weather || 'unknown',
    };
  }

  async generateSceneSpec(visionAnalysis) {
    if (this.#isMock) return this.#mockGenerateScene(visionAnalysis);

    const prompt = [
      'Given the following vision analysis of a photograph, generate a CanonicalSceneSpec JSON object.',
      'The scene spec must include: version, sceneId, source, entities (each with id, type, label, position, rotation, scale, geometry, material, temporalBehavior, variants, buildStatus, confidence), ground, camera, lighting, temporalAnchors (at least 4 covering past-present-future), style, and metadata.',
      'Entities must use stylized clay-style geometry builders: stylized-building, organic-tree, flat-path, ground-plane.',
      'TemporalBehavior modes: grow, decay, static, transform.',
      'Return ONLY valid JSON, no commentary.',
      '',
      `Vision analysis: ${JSON.stringify(visionAnalysis)}`,
    ].join('\n');

    const response = await this.#callApi('/generate', {
      prompt,
      response_format: 'json',
      temperature: 0.4,
      max_tokens: 8000,
    });
    return this.#parseSceneSpecResponse(response);
  }

  async generateStory(sceneSpec, yearRange) {
    if (this.#isMock) return this.#mockStory(sceneSpec, yearRange);

    const entitySummary = (sceneSpec.entities || [])
      .map((e) => `${e.id} (${e.type}: ${e.label})`)
      .join(', ');

    const prompt = [
      'Generate a temporal story for a 3D scene.',
      `Entities: ${entitySummary}`,
      `Year range: ${yearRange.start || 2016} to ${yearRange.end || 2046}`,
      'Return JSON with: title, description, keyEvents (array of { time, year, title, description, affectedEntities }).',
      'time is a normalized float in [-1, 1]. Provide 4-6 key events spread across the timeline.',
      'Return ONLY valid JSON.',
    ].join('\n');

    const response = await this.#callApi('/generate', {
      prompt,
      response_format: 'json',
      temperature: 0.6,
      max_tokens: 2000,
    });

    if (typeof response === 'string') {
      return JSON.parse(this.#extractJson(response));
    }
    return response;
  }

  async generateReferenceImages(sceneSpec, years) {
    if (this.#isMock) return this.#mockReferenceImages(sceneSpec, years);

    const results = [];
    const styleDescription = `clay-style 3D render, soft rounded forms, matte material, warm lighting, ${sceneSpec.style?.name || 'soft-clay'} style`;

    for (const year of years) {
      const anchor = (sceneSpec.temporalAnchors || []).find((a) => a.year === year);
      const sceneDescription = this.#buildSceneDescriptionForYear(sceneSpec, anchor);

      const response = await this.#callApi('/image/generate', {
        prompt: `${styleDescription}. ${sceneDescription}. Year ${year}. Diorama view from above at 30 degrees.`,
        size: '1024x1024',
        quality: 'high',
      });

      results.push({
        year,
        path: response.output_path || `renders/reference-${year}.png`,
        generated: true,
        url: response.url || null,
      });
    }
    return results;
  }

  async reviewScene(sceneSpec) {
    if (this.#isMock) return this.#mockReview(sceneSpec);

    const prompt = [
      'Review the following CanonicalSceneSpec for quality issues.',
      'Check for: missing entities, inconsistent positions, broken temporal anchors, material issues, scale problems.',
      `Scene has ${sceneSpec.entities?.length || 0} entities and ${sceneSpec.temporalAnchors?.length || 0} temporal anchors.`,
      'Return JSON: { passed: bool, score: float 0-1, issues: [{ entityId, severity, description, suggestion }], suggestions: [string] }',
      `Scene: ${JSON.stringify(sceneSpec, null, 0).slice(0, 4000)}`,
    ].join('\n');

    const response = await this.#callApi('/generate', {
      prompt,
      response_format: 'json',
      temperature: 0.2,
      max_tokens: 1500,
    });

    if (typeof response === 'string') {
      return JSON.parse(this.#extractJson(response));
    }
    return response;
  }

  // ── Live API helpers ────────────────────────────────────────────────────

  async #callApi(endpoint, body) {
    const url = `${this.#baseUrl}${endpoint}`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.#apiKey}`,
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`Xiaomi API ${endpoint} failed: ${res.status} ${text}`);
    }
    const json = await res.json();
    // Some endpoints wrap the result in a `data` field
    return json.data ?? json;
  }

  async #readImageAsBase64(photoPath) {
    const { readFile } = await import('node:fs/promises');
    const buffer = await readFile(photoPath);
    return buffer.toString('base64');
  }

  #extractJson(text) {
    // Pull the first JSON object or array from possibly-markdown text
    const match = text.match(/[\[{][\s\S]*[\]}]/);
    return match ? match[0] : text;
  }

  #parseSceneSpecResponse(response) {
    if (typeof response === 'string') {
      return JSON.parse(this.#extractJson(response));
    }
    return response;
  }

  #buildSceneDescriptionForYear(sceneSpec, anchor) {
    const entities = sceneSpec.entities || [];
    const states = anchor?.entityStates || {};
    const parts = [];

    for (const entity of entities) {
      const state = states[entity.id];
      if (state && state.visible === false) continue;
      const scale = state?.scale || entity.scale || [1, 1, 1];
      const mat = state?.material || {};
      let desc = `${entity.label} at position (${entity.position?.join(', ')}) scale ${scale.join(', ')}`;
      if (mat.roughness) desc += ` roughness ${mat.roughness}`;
      parts.push(desc);
    }
    return parts.join('. ');
  }

  // ── Mock implementations ────────────────────────────────────────────────

  #mockAnalyzePhoto(photoPath) {
    return {
      objects: [
        { type: 'building', label: 'Campus Main Building', confidence: 0.92, bounds: { x: 0.3, y: 0.2, w: 0.4, h: 0.5 } },
        { type: 'tree', label: 'Oak Tree', confidence: 0.88, bounds: { x: 0.1, y: 0.3, w: 0.15, h: 0.3 } },
        { type: 'tree', label: 'Pine Tree', confidence: 0.85, bounds: { x: 0.75, y: 0.25, w: 0.12, h: 0.35 } },
        { type: 'road', label: 'Campus Path', confidence: 0.95, bounds: { x: 0.0, y: 0.7, w: 1.0, h: 0.3 } },
        { type: 'person', label: 'Student', confidence: 0.72, bounds: { x: 0.5, y: 0.5, w: 0.08, h: 0.2 } },
      ],
      scene: 'university campus with main building, trees, and walking paths',
      style: 'modern architecture with warm brick and glass',
      dominantColors: ['#8B7355', '#4A90D9', '#5B8C3E', '#D4C5A9'],
      timeOfDay: 'afternoon',
      weather: 'clear',
    };
  }

  #mockGenerateScene(vision) {
    return {
      version: 2,
      sceneId: `scene-${Date.now().toString(36)}`,
      createdAt: new Date().toISOString(),
      source: { type: 'photo', inputPath: 'input/photo.jpg', visionAnalysis: JSON.stringify(vision), generatedAt: new Date().toISOString() },
      entities: [
        {
          id: 'building_main',
          type: 'building',
          label: 'Main Building',
          position: [0, 0, -2],
          rotation: [0, 0, 0],
          scale: [1, 1, 1],
          geometry: { builder: 'stylized-building', parameters: { floors: 4, width: 5, depth: 2.5, cornerRadius: 0.14, windowColumns: 8 } },
          material: { color: '#C4A882', roughness: 0.45, metalness: 0, clearcoat: 0.08, opacity: 1 },
          temporalBehavior: { mode: 'decay', rate: 0.01 },
          variants: [],
          buildStatus: 'blockout',
          confidence: 0.92,
        },
        {
          id: 'tree_oak_1',
          type: 'tree',
          label: 'Oak Tree',
          position: [-3, 0, -1],
          rotation: [0, 0, 0],
          scale: [1, 1, 1],
          geometry: { builder: 'organic-tree', parameters: { height: 3.5, crownRadius: 1.8, trunkRadius: 0.15, seed: 42 } },
          material: { color: '#5B8C3E', roughness: 0.7, metalness: 0, clearcoat: 0.05, opacity: 1 },
          temporalBehavior: { mode: 'grow', rate: 0.05 },
          variants: [],
          buildStatus: 'blockout',
          confidence: 0.88,
        },
        {
          id: 'tree_pine_1',
          type: 'tree',
          label: 'Pine Tree',
          position: [3.5, 0, -1.5],
          rotation: [0, 0, 0],
          scale: [1, 1, 1],
          geometry: { builder: 'organic-tree', parameters: { height: 4, crownRadius: 1.2, trunkRadius: 0.12, seed: 77 } },
          material: { color: '#3E6B2E', roughness: 0.72, metalness: 0, clearcoat: 0.05, opacity: 1 },
          temporalBehavior: { mode: 'grow', rate: 0.03 },
          variants: [],
          buildStatus: 'blockout',
          confidence: 0.85,
        },
        {
          id: 'path_main',
          type: 'path',
          label: 'Campus Path',
          position: [0, 0.01, 2],
          rotation: [0, 0, 0],
          scale: [1, 1, 1],
          geometry: { builder: 'flat-path', parameters: { width: 2, length: 8, curve: 0.1 } },
          material: { color: '#D4C5A9', roughness: 0.65, metalness: 0, clearcoat: 0.04, opacity: 1 },
          temporalBehavior: { mode: 'static' },
          variants: [],
          buildStatus: 'blockout',
          confidence: 0.95,
        },
        {
          id: 'ground',
          type: 'terrain',
          label: 'Ground',
          position: [0, -0.05, 0],
          rotation: [0, 0, 0],
          scale: [1, 1, 1],
          geometry: { builder: 'ground-plane', parameters: { width: 16, depth: 16, subdivisions: 8 } },
          material: { color: '#8BC34A', roughness: 0.75, metalness: 0, clearcoat: 0.02, opacity: 1 },
          temporalBehavior: { mode: 'static' },
          variants: [],
          buildStatus: 'blockout',
          confidence: 1.0,
        },
      ],
      ground: { type: 'grass', color: '#8BC34A', size: 16 },
      camera: { position: [8, 6, 8], target: [0, 0.5, 0], fov: 45, near: 0.1, far: 100 },
      lighting: {
        key: { color: '#FFE4B5', intensity: 1.2, position: [5, 8, 3] },
        fill: { color: '#E8E0D4', intensity: 0.4, position: [-3, 4, -2] },
        rim: { color: '#FFF5E6', intensity: 0.3, position: [0, 6, -5] },
        ambient: { color: '#F7F5EF', intensity: 0.5, position: [0, 0, 0] },
        contactShadow: true,
        shadowIntensity: 0.3,
      },
      temporalAnchors: [
        {
          normalizedTime: -0.8,
          year: 2016,
          label: '2016',
          entityStates: {
            building_main: { visible: true, scale: [1, 1, 1] },
            tree_oak_1: { visible: true, scale: [0.7, 0.7, 0.7] },
            tree_pine_1: { visible: true, scale: [0.65, 0.65, 0.65] },
          },
        },
        {
          normalizedTime: 0,
          year: 2026,
          label: '2026',
          entityStates: {
            building_main: { visible: true, scale: [1, 1, 1] },
            tree_oak_1: { visible: true, scale: [1, 1, 1] },
            tree_pine_1: { visible: true, scale: [1, 1, 1] },
          },
        },
        {
          normalizedTime: 0.6,
          year: 2036,
          label: '2036',
          entityStates: {
            building_main: { visible: true, scale: [1, 1, 1], material: { roughness: 0.55 } },
            tree_oak_1: { visible: true, scale: [1.3, 1.3, 1.3] },
            tree_pine_1: { visible: true, scale: [1.25, 1.25, 1.25] },
          },
        },
        {
          normalizedTime: 1,
          year: 2046,
          label: '2046',
          entityStates: {
            building_main: { visible: true, scale: [1, 1, 1], material: { roughness: 0.65 } },
            tree_oak_1: { visible: true, scale: [1.6, 1.6, 1.6] },
            tree_pine_1: { visible: true, scale: [1.5, 1.5, 1.5] },
          },
        },
      ],
      style: {
        name: 'soft-clay',
        globalRoughness: [0.35, 0.8],
        globalMetalness: [0, 0],
        bevelRadius: [0.02, 0.2],
        colorPalette: ['#C4A882', '#8B7355', '#5B8C3E', '#3E6B2E', '#4A90D9', '#D4C5A9', '#8BC34A'],
        lightingMood: 'warm',
      },
      metadata: {
        description: 'University campus scene with main building and trees',
        dominantColors: ['#C4A882', '#5B8C3E', '#D4C5A9'],
        complexity: 'medium',
        estimatedEntities: 6,
      },
    };
  }

  #mockStory(sceneSpec, yearRange) {
    return {
      title: 'Campus Through Time',
      description: 'A university campus grows and ages across decades',
      keyEvents: [
        { time: -0.8, year: 2016, title: 'New Campus', description: 'Fresh buildings, young trees', affectedEntities: ['building_main', 'tree_oak_1'] },
        { time: 0, year: 2026, title: 'Present Day', description: 'Mature campus in full bloom', affectedEntities: [] },
        { time: 0.6, year: 2036, title: 'Growing Legacy', description: 'Trees tower, buildings weather gracefully', affectedEntities: ['tree_oak_1', 'tree_pine_1'] },
        { time: 1, year: 2046, title: 'Future Vision', description: 'A living campus, deeply rooted', affectedEntities: ['tree_oak_1', 'building_main'] },
      ],
    };
  }

  #mockReferenceImages(sceneSpec, years) {
    return years.map((y) => ({ year: y, path: `renders/reference-${y}.png`, generated: true }));
  }

  #mockReview(sceneSpec) {
    return {
      passed: true,
      score: 0.87,
      issues: [
        { entityId: 'tree_pine_1', severity: 'low', description: 'Pine tree could use more crown detail', suggestion: 'Add branch-level geometry' },
      ],
      suggestions: ['Consider adding a small bench near the path'],
    };
  }
}
