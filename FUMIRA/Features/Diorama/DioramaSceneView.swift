import SwiftUI
import WebKit

// MARK: - Diorama Scene View

/// SwiftUI wrapper for the Three.js clay diorama.
/// Internally owns a `WKWebView` and a `DioramaBridge` that handles
/// bidirectional JS communication with proper error handling and
/// message queuing.
struct DioramaSceneView: UIViewRepresentable {

    // MARK: - Bindings

    /// Normalized time value in the range [-1, 1].
    @Binding var timeValue: Double

    /// Currently selected entity id, or `nil` when nothing is selected.
    @Binding var selectedEntityId: String?

    // MARK: - Callbacks

    /// Called once when the JS runtime signals `diorama.ready`.
    var onReady: (() -> Void)?

    /// Called when the JS runtime reports an unrecoverable error.
    var onError: ((Error) -> Void)?

    /// Called when the user taps an entity inside the 3D scene.
    var onEntitySelected: ((String) -> Void)?

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // -- Playback / media --
        config.allowsInlineMediaPlayback = true

        // -- Disable magnification for smooth pan/zoom interaction --
        config.preferences.isElementFullscreenEnabled = false
        if #available(iOS 16.4, *) {
            config.preferences.isTextInteractionEnabled = false
        }

        // -- JS bridge for receiving events from the TS runtime --
        config.userContentController.add(
            context.coordinator,
            name: "dioramaBridge"
        )

        // -- Disable the page-level zoom gesture that interferes
        //    with the Three.js OrbitControls --
        let disableZoomScript = WKUserScript(
            source: """
            var meta = document.querySelector('meta[name="viewport"]');
            if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                document.head.appendChild(meta);
            }
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(disableZoomScript)

        // -- Create web view --
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        // -- Disable magnification gesture recognizer --
        for recognizer in webView.scrollView.gestureRecognizers ?? [] {
            if let pinch = recognizer as? UIPinchGestureRecognizer {
                pinch.isEnabled = false
            }
        }

        // -- Load bundled diorama assets --
        if let url = Bundle.main.url(forResource: "diorama", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        // -- Hand the web view to the bridge --
        let bridge = DioramaBridge(webView: webView)
        bridge.delegate = context.coordinator
        context.coordinator.bridge = bridge
        context.coordinator.webView = webView

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Sync bindings to JS through the bridge.
        // The bridge queues messages automatically if the runtime is not yet ready.
        guard let bridge = context.coordinator.bridge else { return }

        // Always push the latest time value.
        bridge.setTimeValue(timeValue)

        // Push selection state. We track the last-pushed value to avoid
        // redundant JS calls on every SwiftUI update cycle.
        let desired = selectedEntityId
        if desired != context.coordinator.lastPushedSelection {
            bridge.selectEntity(desired)
            context.coordinator.lastPushedSelection = desired
        }

        // Update the parent reference so the coordinator always has the
        // latest callbacks.
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.bridge?.invalidate()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, DioramaBridgeDelegate, WKNavigationDelegate, WKScriptMessageHandler {

        var parent: DioramaSceneView
        var bridge: DioramaBridge?
        weak var webView: WKWebView?

        /// Tracks the last entity id pushed to JS to avoid redundant calls.
        var lastPushedSelection: String? = "__initial__" // sentinel: forces first push

        init(parent: DioramaSceneView) {
            self.parent = parent
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            bridge?.handleScriptMessage(message)
        }

        // MARK: DioramaBridgeDelegate

        func dioramaBridgeDidBecomeReady(_ bridge: DioramaBridge) {
            // Push the current state now that the runtime is listening.
            bridge.setTimeValue(parent.timeValue)
            bridge.selectEntity(parent.selectedEntityId)
            lastPushedSelection = parent.selectedEntityId

            DispatchQueue.main.async { [weak self] in
                self?.parent.onReady?()
            }
        }

        func dioramaBridge(_ bridge: DioramaBridge, didSelectEntity entityId: String) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.selectedEntityId = entityId
                self.lastPushedSelection = entityId
                self.parent.onEntitySelected?(entityId)
            }
        }

        func dioramaBridge(_ bridge: DioramaBridge, didEncounterError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.onError?(error)
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Push initial state once the page finishes loading.
            // The bridge will queue these until diorama.ready arrives.
            bridge?.setTimeValue(parent.timeValue)
            bridge?.selectEntity(parent.selectedEntityId)
            lastPushedSelection = parent.selectedEntityId
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onError?(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onError?(error)
        }
    }
}
