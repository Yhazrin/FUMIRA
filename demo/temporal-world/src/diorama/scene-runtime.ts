// diorama/scene-runtime.ts — The single Diorama Runtime.
// Both Desktop (browser iframe) and iOS (WKWebView) use this identical code.
// Platform differences are absorbed by the `isNative` flag, not separate files.

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type {
  SceneGraph,
  SceneState,
  Entity,
  CameraSpec,
  LightingSpec,
  LightSpec,
} from './contracts';
import { createGeometry, createClayMaterial, hashString } from './clay-builders';
import { NativeBridge } from './native-bridge';

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

export interface DioramaRuntimeOptions {
  /** true when running inside WKWebView on iOS; false for browser/iframe. */
  isNative?: boolean;
  /** Override pixel ratio (defaults to devicePixelRatio, capped at 2 on native). */
  pixelRatio?: number;
}

// ---------------------------------------------------------------------------
// Internal bookkeeping
// ---------------------------------------------------------------------------

interface EntityMesh {
  id: string;
  mesh: THREE.Mesh;
  label: string;
  temporalRange: [number, number];
}

// ---------------------------------------------------------------------------
// DioramaRuntime
// ---------------------------------------------------------------------------

export class DioramaRuntime {
  // Core Three.js objects
  private renderer: THREE.WebGLRenderer | null = null;
  private scene: THREE.Scene;
  private camera: THREE.PerspectiveCamera;
  private controls: OrbitControls | null = null;

  // Container
  private container: HTMLElement;
  private canvas: HTMLCanvasElement | null = null;

  // State
  private entityMeshes: Map<string, EntityMesh> = new Map();
  private currentTime: number = 0;
  private selectedEntityId: string | null = null;
  private isReady: boolean = false;
  private isDisposed: boolean = false;

  // Platform
  private isNative: boolean;
  private pixelRatio: number;

  // Lighting references (so we can update them if needed)
  private lights: THREE.Light[] = [];

  // Bridge
  public readonly bridge: NativeBridge;

  // Raycasting for entity selection
  private raycaster: THREE.Raycaster;
  private pointer: THREE.Vector2;

  // Animation
  private animationFrameId: number | null = null;
  private resizeObserver: ResizeObserver | null = null;

  // Selection highlight
  private selectionOutlineMesh: THREE.Mesh | null = null;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  constructor(container: HTMLElement, options?: DioramaRuntimeOptions) {
    this.container = container;
    this.isNative = options?.isNative ?? false;
    this.pixelRatio =
      options?.pixelRatio ??
      Math.min(window.devicePixelRatio, this.isNative ? 2 : 3);

    // Three.js scene
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color('#e8e0d8'); // warm clay paper

    // Camera — will be overwritten by loadScene, but we need a default
    this.camera = new THREE.PerspectiveCamera(50, 1, 0.1, 100);
    this.camera.position.set(5, 4, 6);
    this.camera.lookAt(0, 0, 0);

    // Raycaster
    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2();

    // Bridge must exist before any event handlers fire
    this.bridge = new NativeBridge(this);

    // Kick off renderer setup (async-ish but synchronous in practice)
    this.initRenderer();
  }

  // ---------------------------------------------------------------------------
  // Renderer initialisation
  // ---------------------------------------------------------------------------

  private initRenderer(): void {
    this.canvas = document.createElement('canvas');
    this.container.appendChild(this.canvas);

    this.renderer = new THREE.WebGLRenderer({
      canvas: this.canvas,
      antialias: true,
      alpha: false,
      powerPreference: this.isNative ? 'high-performance' : 'default',
    });

    this.renderer.setPixelRatio(this.pixelRatio);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.1;

    // Size to container
    this.resize();

    // Controls
    this.controls = new OrbitControls(this.camera, this.canvas);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.controls.minDistance = 1;
    this.controls.maxDistance = 50;
    this.controls.maxPolarAngle = Math.PI / 2.1; // don't go below ground
    this.controls.target.set(0, 0, 0);

    // Touch adjustments for iOS
    if (this.isNative) {
      this.controls.rotateSpeed = 0.6;
      this.controls.zoomSpeed = 0.8;
      this.controls.panSpeed = 0.6;
      this.controls.touches = {
        ONE: THREE.TOUCH.ROTATE,
        TWO: THREE.TOUCH.DOLLY_PAN,
      };
    }

    // Resize observer
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(this.container);

    // Click/tap for entity selection
    this.canvas.addEventListener('pointerdown', this.onPointerDown);
    this.canvas.addEventListener('pointerup', this.onPointerUp);

    // Track pointer for tap-vs-drag detection
    this._pointerDownPos = new THREE.Vector2();

    // Start render loop
    this.animate();
  }

  // ---------------------------------------------------------------------------
  // Resize
  // ---------------------------------------------------------------------------

  private resize(): void {
    if (!this.renderer || !this.canvas) return;
    const rect = this.container.getBoundingClientRect();
    const w = rect.width || 800;
    const h = rect.height || 600;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  // ---------------------------------------------------------------------------
  // Animation loop
  // ---------------------------------------------------------------------------

  private animate = (): void => {
    if (this.isDisposed) return;
    this.animationFrameId = requestAnimationFrame(this.animate);
    this.controls?.update();
    this.renderer?.render(this.scene, this.camera);
  };

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /**
   * Load a complete scene graph. Replaces any existing scene content.
   */
  loadScene(graph: SceneGraph): void {
    // Clear existing
    this.clearEntities();
    this.clearLights();

    // Camera
    this.applyCamera(graph.camera);

    // Lighting
    this.applyLighting(graph.lighting);

    // Ground plane (implicit, soft)
    this.addGroundPlane();

    // Entities
    for (const entity of graph.entities) {
      this.addEntity(entity);
    }

    this.isReady = true;

    // Notify bridge
    this.bridge.sendReady();
  }

  /**
   * Set the normalised time value (-1 to 1).
   * Entities outside their temporal range are hidden.
   */
  setTimeValue(normalized: number): void {
    this.currentTime = Math.max(-1, Math.min(1, normalized));
    this.updateEntityVisibility();
  }

  /**
   * Select an entity by id, or null to clear selection.
   */
  selectEntity(id: string | null): void {
    this.selectedEntityId = id;
    this.updateSelectionHighlight();

    const selected = id ? this.entityMeshes.get(id) : null;
    this.bridge.sendEntitySelected(id, selected?.label);
  }

  /**
   * Read-only snapshot of current runtime state.
   */
  getSceneState(): SceneState {
    return {
      currentTime: this.currentTime,
      selectedEntityId: this.selectedEntityId,
      entityCount: this.entityMeshes.size,
      isReady: this.isReady,
    };
  }

  /**
   * Tear down everything — call before removing from DOM.
   */
  dispose(): void {
    this.isDisposed = true;

    if (this.animationFrameId !== null) {
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }

    this.resizeObserver?.disconnect();
    this.canvas?.removeEventListener('pointerdown', this.onPointerDown);
    this.canvas?.removeEventListener('pointerup', this.onPointerUp);

    this.clearEntities();
    this.clearLights();
    this.controls?.dispose();
    this.renderer?.dispose();
    this.canvas?.remove();

    this.isReady = false;
  }

  // ---------------------------------------------------------------------------
  // Internal: Camera
  // ---------------------------------------------------------------------------

  private applyCamera(spec: CameraSpec): void {
    this.camera.fov = spec.fov;
    this.camera.near = spec.near;
    this.camera.far = spec.far;
    this.camera.position.set(...spec.position);
    this.camera.lookAt(new THREE.Vector3(...spec.target));
    this.camera.updateProjectionMatrix();

    this.controls?.target.set(...spec.target);
    this.controls?.update();
  }

  // ---------------------------------------------------------------------------
  // Internal: Lighting
  // ---------------------------------------------------------------------------

  private applyLighting(spec: LightingSpec): void {
    this.addDirectionalLight(spec.key, 'key');
    this.addDirectionalLight(spec.fill, 'fill');
    this.addDirectionalLight(spec.rim, 'rim');

    // Ambient
    const ambient = new THREE.AmbientLight(
      new THREE.Color(spec.ambient.color),
      spec.ambient.intensity,
    );
    this.scene.add(ambient);
    this.lights.push(ambient);

    // Contact shadows via ground plane (simplified — no shadow-casting setup per light)
    if (spec.contactShadow) {
      this.scene.traverse((obj) => {
        if (obj instanceof THREE.DirectionalLight) {
          obj.castShadow = true;
          obj.shadow.mapSize.set(1024, 1024);
          obj.shadow.camera.near = 0.1;
          obj.shadow.camera.far = 30;
          obj.shadow.camera.left = -10;
          obj.shadow.camera.right = 10;
          obj.shadow.camera.top = 10;
          obj.shadow.camera.bottom = -10;
        }
      });
    }
  }

  private addDirectionalLight(spec: LightSpec, _name: string): void {
    const light = new THREE.DirectionalLight(
      new THREE.Color(spec.color),
      spec.intensity,
    );
    light.position.set(...spec.position);
    this.scene.add(light);
    this.lights.push(light);
  }

  private clearLights(): void {
    for (const l of this.lights) {
      this.scene.remove(l);
      l.dispose();
    }
    this.lights = [];
  }

  // ---------------------------------------------------------------------------
  // Internal: Entities
  // ---------------------------------------------------------------------------

  private addEntity(entity: Entity): void {
    try {
      const geometry = createGeometry(entity.geometry);
      const material = createClayMaterial(entity.material, entity.type, hashString(entity.id));
      const mesh = new THREE.Mesh(geometry, material);

      mesh.position.set(...entity.transform.position);
      mesh.rotation.set(...entity.transform.rotation);
      mesh.scale.set(...entity.transform.scale);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      mesh.name = entity.id;

      // Store entity id on the mesh for raycasting
      mesh.userData = { entityId: entity.id };

      this.scene.add(mesh);
      this.entityMeshes.set(entity.id, {
        id: entity.id,
        mesh,
        label: entity.label,
        temporalRange: entity.temporalRange,
      });
    } catch (err) {
      this.bridge.sendError(err instanceof Error ? err : new Error(String(err)));
    }
  }

  private clearEntities(): void {
    for (const [, entry] of this.entityMeshes) {
      this.scene.remove(entry.mesh);
      if (entry.mesh.geometry) entry.mesh.geometry.dispose();
      if (entry.mesh.material) {
        const m = entry.mesh.material;
        if (Array.isArray(m)) m.forEach((mat) => mat.dispose());
        else m.dispose();
      }
    }
    this.entityMeshes.clear();
    this.removeSelectionHighlight();
  }

  // ---------------------------------------------------------------------------
  // Internal: Temporal visibility
  // ---------------------------------------------------------------------------

  private updateEntityVisibility(): void {
    for (const [, entry] of this.entityMeshes) {
      const [lo, hi] = entry.temporalRange;
      entry.mesh.visible = this.currentTime >= lo && this.currentTime <= hi;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal: Selection highlight (outline ring)
  // ---------------------------------------------------------------------------

  private updateSelectionHighlight(): void {
    this.removeSelectionHighlight();
    if (!this.selectedEntityId) return;
    const entry = this.entityMeshes.get(this.selectedEntityId);
    if (!entry) return;

    // Clone geometry scaled slightly up for outline effect
    const outlineGeom = entry.mesh.geometry.clone();
    const outlineMat = new THREE.MeshBasicMaterial({
      color: 0x4a90d9,
      transparent: true,
      opacity: 0.3,
      side: THREE.BackSide,
    });
    const outline = new THREE.Mesh(outlineGeom, outlineMat);
    outline.position.copy(entry.mesh.position);
    outline.rotation.copy(entry.mesh.rotation);

    const s = entry.mesh.scale;
    outline.scale.set(s.x * 1.08, s.y * 1.08, s.z * 1.08);
    outline.name = '__selection_outline__';

    this.scene.add(outline);
    this.selectionOutlineMesh = outline;
  }

  private removeSelectionHighlight(): void {
    if (this.selectionOutlineMesh) {
      this.scene.remove(this.selectionOutlineMesh);
      this.selectionOutlineMesh.geometry?.dispose();
      (this.selectionOutlineMesh.material as THREE.Material)?.dispose();
      this.selectionOutlineMesh = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal: Ground plane
  // ---------------------------------------------------------------------------

  private addGroundPlane(): void {
    const groundGeom = new THREE.PlaneGeometry(40, 40);
    groundGeom.rotateX(-Math.PI / 2);
    const groundMat = new THREE.MeshStandardMaterial({
      color: 0xd4c9bc,
      roughness: 0.95,
      metalness: 0,
    });
    const ground = new THREE.Mesh(groundGeom, groundMat);
    ground.position.y = -0.01;
    ground.receiveShadow = true;
    ground.name = '__ground__';
    this.scene.add(ground);
  }

  // ---------------------------------------------------------------------------
  // Internal: Pointer interaction -> entity selection
  // ---------------------------------------------------------------------------

  private _pointerDownPos!: THREE.Vector2;

  private onPointerDown = (e: PointerEvent): void => {
    this._pointerDownPos.set(e.clientX, e.clientY);
  };

  private onPointerUp = (e: PointerEvent): void => {
    // Ignore if pointer moved (it was a drag, not a tap)
    const dx = e.clientX - this._pointerDownPos.x;
    const dy = e.clientY - this._pointerDownPos.y;
    if (Math.sqrt(dx * dx + dy * dy) > 5) return;

    if (!this.canvas) return;
    const rect = this.canvas.getBoundingClientRect();
    this.pointer.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
    this.pointer.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

    this.raycaster.setFromCamera(this.pointer, this.camera);
    const hits = this.raycaster.intersectObjects(
      Array.from(this.entityMeshes.values()).map((e) => e.mesh),
      false,
    );

    if (hits.length > 0) {
      const hitId = hits[0].object.userData?.entityId as string | undefined;
      if (hitId) {
        this.selectEntity(hitId);
      }
    } else {
      this.selectEntity(null);
    }
  };
}
