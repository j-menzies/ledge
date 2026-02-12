import SwiftUI
import WebKit

/// NSViewRepresentable wrapper for WKWebView.
///
/// Suppresses alerts and popups via WKUIDelegate to prevent
/// the app from being activated (which would break the non-activating panel).
struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    var zoomLevel: Double = 1.0
    var customCSS: String?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        // Inject custom CSS if provided
        if let css = customCSS, !css.isEmpty {
            let script = WKUserScript(
                source: "var style = document.createElement('style'); style.textContent = `\(css.replacingOccurrences(of: "`", with: "\\`"))`; document.head.appendChild(style);",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(script)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.pageZoom = zoomLevel
        webView.setValue(false, forKey: "drawsBackground")

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
        if webView.pageZoom != zoomLevel {
            webView.pageZoom = zoomLevel
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        // Suppress new windows (popups)
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                      for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Load in same view instead of opening new window
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // Suppress JavaScript alerts
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                      initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                      initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(false)
        }
    }
}
