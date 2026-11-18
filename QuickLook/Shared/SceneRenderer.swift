import WebKit

/// Renders an .excalidraw scene to PNG with Excalidraw's own exporter, in an offscreen
/// WKWebView loaded from this extension's bundled `web/render.html`. One web view is kept
/// per extension process and reused across requests.
@MainActor
final class SceneRenderer: NSObject {
    static let shared = SceneRenderer()

    enum RenderError: Error { case pageFailed(Error?), badResult }

    private var webView: WKWebView?
    private var isLoaded = false
    private var waiting: [CheckedContinuation<Void, Error>] = []

    /// Returns PNG data whose longest side is `maxPixels`, or nil if the drawing is empty.
    func renderPNG(sceneJSON: String, maxPixels: Int) async throws -> Data? {
        try await loadPage()
        let result = try await webView!.callAsyncJavaScript(
            "return await window.macdrawRender(scene, maxSize)",
            arguments: ["scene": sceneJSON, "maxSize": maxPixels],
            in: nil, contentWorld: .page)
        guard let base64 = result as? String else { return nil }  // null => empty drawing
        guard let data = Data(base64Encoded: base64) else { throw RenderError.badResult }
        return data
    }

    private func loadPage() async throws {
        if isLoaded { return }
        if webView == nil {
            let config = WKWebViewConfiguration()
            config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
            view.navigationDelegate = self
            webView = view
            view.load(URLRequest(url: URL(string: "\(BundleSchemeHandler.scheme)://app/render.html")!))
        }
        try await withCheckedThrowingContinuation { waiting.append($0) }
    }

    private func finishLoading(_ error: Error?) {
        isLoaded = error == nil
        if error != nil { webView = nil }
        let continuations = waiting
        waiting.removeAll()
        for c in continuations {
            if let error { c.resume(throwing: RenderError.pageFailed(error)) } else { c.resume() }
        }
    }
}

extension SceneRenderer: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finishLoading(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishLoading(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishLoading(error) }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            isLoaded = false
            self.webView = nil
        }
    }
}
