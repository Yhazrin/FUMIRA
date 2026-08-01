import SwiftUI
import WebKit

/// Bridge between SwiftUI and the Three.js clay diorama.
/// Loads the embedded HTML and exposes JS-native communication.
struct DioramaWebView: UIViewRepresentable {
    @Binding var timeValue: Double
    @Binding var selectedEntityID: String?
    let onEntitySelected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // JS bridge for receiving events from Three.js
        config.userContentController.add(
            context.coordinator,
            name: "fumiraBridge"
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        // Load the embedded diorama HTML
        if let url = Bundle.main.url(
            forResource: "diorama",
            withExtension: "html"
        ) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Push time value changes to Three.js
        let js = "window.updateTimeFromNative(\(timeValue))"
        webView.evaluateJavaScript(js, completionHandler: nil)

        // Push selection
        if let entityID = selectedEntityID {
            let escaped = entityID.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript(
                "window.selectEntityFromNative('\(escaped)')",
                completionHandler: nil
            )
        } else {
            webView.evaluateJavaScript(
                "window.clearSelectionFromNative()",
                completionHandler: nil
            )
        }
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: DioramaWebView
        weak var webView: WKWebView?

        init(parent: DioramaWebView) {
            self.parent = parent
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "fumiraBridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            switch type {
            case "entitySelected":
                if let id = body["entityId"] as? String {
                    DispatchQueue.main.async {
                        self.parent.onEntitySelected(id)
                    }
                }
            case "timeChanged":
                if let p = body["value"] as? Double {
                    DispatchQueue.main.async {
                        self.parent.timeValue = p
                    }
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Push initial time value once page loads
            let js = "window.updateTimeFromNative(\(parent.timeValue))"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
