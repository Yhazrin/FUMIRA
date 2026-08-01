import Foundation
import WebKit

// MARK: - Delegate

/// Receives lifecycle and event callbacks from the Diorama Bridge.
protocol DioramaBridgeDelegate: AnyObject {
    func dioramaBridgeDidBecomeReady(_ bridge: DioramaBridge)
    func dioramaBridge(_ bridge: DioramaBridge, didSelectEntity entityId: String)
    func dioramaBridge(_ bridge: DioramaBridge, didEncounterError error: Error)
}

// MARK: - Pending Message

/// A message queued before the JS runtime signals readiness.
private struct PendingMessage {
    let script: String
    let description: String
}

// MARK: - Bridge Errors

enum DioramaBridgeError: LocalizedError {
    case webViewDeallocated
    case javaScriptEvaluationFailed(String, underlying: Error)
    case invalidPayload(String)
    case runtimeError(String)

    var errorDescription: String? {
        switch self {
        case .webViewDeallocated:
            return "WKWebView was deallocated before message could be sent."
        case .javaScriptEvaluationFailed(let script, let underlying):
            return "JS evaluation failed for \(script): \(underlying.localizedDescription)"
        case .invalidPayload(let reason):
            return "Invalid message payload: \(reason)"
        case .runtimeError(let message):
            return "Diorama runtime error: \(message)"
        }
    }
}

// MARK: - Diorama Bridge

/// Manages bidirectional communication between native Swift and the
/// TypeScript Diorama Runtime running inside a WKWebView.
///
/// Outbound messages (Swift -> JS):
///   - `time.set`       : pushes a normalized time value [-1, 1]
///   - `entity.select`  : highlights an entity by id
///   - `entity.clear`   : clears the current selection
///
/// Inbound messages (JS -> Swift):
///   - `diorama.ready`      : runtime finished initialization
///   - `entity.selected`    : user tapped an entity in the scene
///   - `runtime.error`      : unhandled JS error
///
/// Messages sent before `diorama.ready` is received are queued and
/// flushed in order once the runtime signals readiness.
final class DioramaBridge {

    // MARK: - Protocol version

    /// Current bridge protocol version. Embedded in every message.
    static let protocolVersion = 1

    // MARK: - Public state

    weak var delegate: DioramaBridgeDelegate?

    private(set) var isReady: Bool = false

    // MARK: - Private state

    private weak var webView: WKWebView?
    private var pendingMessages: [PendingMessage] = []
    private let queue = DispatchQueue(label: "com.fumira.diorama-bridge", qos: .userInitiated)

    // MARK: - Init

    /// Creates a bridge bound to the given WKWebView.
    /// The web view's content controller must already include a
    /// `WKScriptMessageHandler` named `"dioramaBridge"` that forwards
    /// to `handleScriptMessage(_:)`.
    init(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Outbound: Time

    /// Sends a normalized time value to the JS runtime.
    /// - Parameter normalized: Value in the range [-1, 1].
    func setTimeValue(_ normalized: Double) {
        let clamped = max(-1, min(1, normalized))
        // Protocol: field is "normalized" (not "value") to match TypeScript contract.
        let script = """
        window.dioramaBridge.receiveMessage(JSON.stringify({
            type: 'time.set',
            version: \(Self.protocolVersion),
            payload: { normalized: \(clamped) },
            timestamp: Date.now()
        }));
        """
        enqueueOrSend(script: script, description: "time.set(\(clamped))")
    }

    // MARK: - Outbound: Entity Selection

    /// Selects an entity by id, or clears the selection when `nil`.
    func selectEntity(_ entityId: String?) {
        let script: String
        if let id = entityId {
            let escaped = id.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
            script = """
            window.dioramaBridge.receiveMessage(JSON.stringify({
                type: 'entity.select',
                version: \(Self.protocolVersion),
                payload: { entityId: '\(escaped)' },
                timestamp: Date.now()
            }));
            """
            enqueueOrSend(script: script, description: "entity.select(\(id))")
        } else {
            script = """
            window.dioramaBridge.receiveMessage(JSON.stringify({
                type: 'entity.clear',
                version: \(Self.protocolVersion),
                payload: {},
                timestamp: Date.now()
            }));
            """
            enqueueOrSend(script: script, description: "entity.clear")
        }
    }

    // MARK: - Outbound: Custom

    /// Sends an arbitrary message to the JS runtime.
    /// - Parameters:
    ///   - type: The message type identifier.
    ///   - payload: A JSON-serializable dictionary.
    func sendCustomMessage(type: String, payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload) else {
            delegate?.dioramaBridge(
                self,
                didEncounterError: DioramaBridgeError.invalidPayload("Payload is not valid JSON.")
            )
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: data, encoding: .utf8) else {
            delegate?.dioramaBridge(
                self,
                didEncounterError: DioramaBridgeError.invalidPayload("Failed to serialize payload.")
            )
            return
        }
        let escapedType = type.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        window.dioramaBridge.receiveMessage(JSON.stringify({
            type: '\(escapedType)',
            version: \(Self.protocolVersion),
            payload: \(jsonString),
            timestamp: Date.now()
        }));
        """
        enqueueOrSend(script: script, description: "custom(\(type))")
    }

    // MARK: - Inbound: Script Message Handler Entry Point

    /// Call this from the `WKScriptMessageHandler` delegate method.
    /// Protocol: TS sends `{ type, version, payload, timestamp }`.
    /// Fields like entityId live inside `payload`, not at the top level.
    func handleScriptMessage(_ message: WKScriptMessage) {
        // The bridge may receive a JSON string (from postMessage) or a
        // dictionary (from evaluateJavaScript callback). Normalize to dict.
        let body: [String: Any]
        if let jsonString = message.body as? String,
           let data = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            body = parsed
        } else if let dict = message.body as? [String: Any] {
            body = dict
        } else {
            return
        }

        guard let type = body["type"] as? String else { return }
        let version = body["version"] as? Int ?? 0
        let payload = body["payload"] as? [String: Any] ?? [:]

        switch type {
        case "diorama.ready":
            handleReady(version: version)

        case "entity.selected":
            // entityId lives inside payload (TS: { entityId, label })
            if let entityId = payload["entityId"] as? String {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.dioramaBridge(self, didSelectEntity: entityId)
                }
            }

        case "runtime.error":
            let errorMessage = payload["message"] as? String ?? "Unknown runtime error"
            let error = DioramaBridgeError.runtimeError(errorMessage)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.dioramaBridge(self, didEncounterError: error)
            }

        default:
            break
        }
    }

    // MARK: - Reset

    /// Tears down the bridge state. Call before releasing the bridge.
    func invalidate() {
        isReady = false
        pendingMessages.removeAll()
    }

    // MARK: - Private: Message Dispatch

    private func enqueueOrSend(script: String, description: String) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isReady {
                self.evaluateJS(script)
            } else {
                self.pendingMessages.append(PendingMessage(script: script, description: description))
            }
        }
    }

    private func handleReady(version: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isReady = true
            self.flushPendingMessages()
            DispatchQueue.main.async {
                self.delegate?.dioramaBridgeDidBecomeReady(self)
            }
        }
    }

    private func flushPendingMessages() {
        // Must be called on `queue`.
        let messages = pendingMessages
        pendingMessages.removeAll()
        for message in messages {
            evaluateJS(message.script)
        }
    }

    // MARK: - Private: JS Evaluation with Error Handling

    /// Wraps `evaluateJavaScript` with structured error handling.
    /// Must be called on the main thread (WKWebView requirement).
    private func evaluateJS(_ script: String) {
        let webView = self.webView
        DispatchQueue.main.async { [weak self] in
            guard let self, let webView else {
                if let self {
                    let error = DioramaBridgeError.webViewDeallocated
                    self.delegate?.dioramaBridge(self, didEncounterError: error)
                }
                return
            }
            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error {
                    guard let self else { return }
                    let bridgeError = DioramaBridgeError.javaScriptEvaluationFailed(
                        script.count > 120 ? String(script.prefix(120)) + "..." : script,
                        underlying: error
                    )
                    DispatchQueue.main.async {
                        self.delegate?.dioramaBridge(self, didEncounterError: bridgeError)
                    }
                }
            }
        }
    }
}
