// diorama/native-bridge.ts — Bidirectional Swift<->JS communication layer.
// Every message is a BridgeMessage with version + timestamp for compatibility.
//
// Two transport targets:
//   - WKWebView:  window.webkit.messageHandlers.iOSBridge.postMessage(msg)
//   - Desktop:    window.parent.postMessage(msg, '*')  (iframe fallback)
//
// Incoming messages arrive via:
//   - window.addEventListener('message', ...)         (postMessage)
//   - window.dioramaBridge.receiveMessage(jsonString)  (WKWebView evaluateJavaScript)

import type {
  BridgeMessage,
  SceneState,
  ReadyPayload,
  TimeSetPayload,
  EntitySelectPayload,
  EntityClearPayload,
  EntitySelectedPayload,
  RuntimeErrorPayload,
} from './contracts';
import type { DioramaRuntime } from './scene-runtime';

// Re-declare minimal globals so the file is self-contained for type-checking
// even when three/addons types aren't in scope.
declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        dioramaBridge?: {
          postMessage: (message: any) => void;
        };
      };
    };
    /** Injected by WKWebView host to allow direct calls from native. */
    dioramaBridge?: {
      receiveMessage: (jsonString: string) => void;
    };
  }
}

export class NativeBridge {
  private runtime: DioramaRuntime;
  private disposed = false;

  constructor(runtime: DioramaRuntime) {
    this.runtime = runtime;
    this.installListeners();

    // Expose a global hook so native Swift can call:
    //   window.dioramaBridge.receiveMessage(JSON.stringify(msg))
    window.dioramaBridge = {
      receiveMessage: (jsonString: string) => {
        try {
          const msg = JSON.parse(jsonString) as BridgeMessage;
          this.handleIncoming(msg);
        } catch (err) {
          this.sendError(
            err instanceof Error ? err : new Error('Invalid bridge JSON'),
          );
        }
      },
    };
  }

  // ---------------------------------------------------------------------------
  // Outbound: Runtime -> Native
  // ---------------------------------------------------------------------------

  /**
   * Post a message to the native host (Swift) or parent iframe.
   */
  postToNative(type: string, payload: any): void {
    const msg: BridgeMessage = {
      version: 1,
      type: type as BridgeMessage['type'],
      payload,
      timestamp: Date.now(),
    };

    const json = JSON.stringify(msg);

    // WKWebView path — handler name must match Swift's
    // WKUserContentController.add(_:name: "dioramaBridge")
    if (window.webkit?.messageHandlers?.dioramaBridge) {
      window.webkit.messageHandlers.dioramaBridge.postMessage(json);
      return;
    }

    // Desktop iframe path
    if (window.parent && window.parent !== window) {
      window.parent.postMessage(msg, '*');
      return;
    }

    // Fallback: log to console when no bridge target is available
    console.warn('[DioramaBridge] No native target — message dropped:', type);
  }

  // Convenience senders for typed messages --------------------------------

  sendReady(): void {
    const state: SceneState = this.runtime.getSceneState();
    const payload: ReadyPayload = { sceneState: state };
    this.postToNative('diorama.ready', payload);
  }

  sendEntitySelected(entityId: string | null, label?: string): void {
    const payload: EntitySelectedPayload = { entityId, label };
    this.postToNative('entity.selected', payload);
  }

  sendError(error: Error): void {
    const payload: RuntimeErrorPayload = {
      message: error.message,
      stack: error.stack,
    };
    this.postToNative('runtime.error', payload);
  }

  // ---------------------------------------------------------------------------
  // Inbound: Native -> Runtime
  // ---------------------------------------------------------------------------

  /**
   * Called when a message arrives from native Swift or parent iframe.
   */
  handleMessageFromNative(type: string, payload: any): void {
    const msg: BridgeMessage = {
      version: 1,
      type: type as BridgeMessage['type'],
      payload,
      timestamp: Date.now(),
    };
    this.handleIncoming(msg);
  }

  private handleIncoming(msg: BridgeMessage): void {
    if (msg.version !== 1) {
      console.warn('[DioramaBridge] Unknown message version:', msg.version);
      return;
    }

    switch (msg.type) {
      case 'time.set': {
        const p = msg.payload as TimeSetPayload;
        if (typeof p.normalized === 'number') {
          this.runtime.setTimeValue(p.normalized);
        }
        break;
      }
      case 'entity.select': {
        const p = msg.payload as EntitySelectPayload;
        if (typeof p.entityId === 'string') {
          this.runtime.selectEntity(p.entityId);
        }
        break;
      }
      case 'entity.clear': {
        this.runtime.selectEntity(null);
        break;
      }
      default:
        console.warn('[DioramaBridge] Unhandled message type:', msg.type);
    }
  }

  // ---------------------------------------------------------------------------
  // Event listeners (postMessage from parent iframe)
  // ---------------------------------------------------------------------------

  private installListeners(): void {
    window.addEventListener('message', this.onWindowMessage);
  }

  private onWindowMessage = (event: MessageEvent): void => {
    // Accept messages from parent only
    if (event.source !== window.parent) return;

    const data = event.data;
    if (
      data &&
      typeof data === 'object' &&
      data.version === 1 &&
      typeof data.type === 'string'
    ) {
      this.handleIncoming(data as BridgeMessage);
    }
  };

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    window.removeEventListener('message', this.onWindowMessage);
    delete window.dioramaBridge;
  }
}
