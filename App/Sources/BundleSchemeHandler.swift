import UniformTypeIdentifiers
import WebKit

/// Serves the bundled web editor from `Resources/web` at macdraw://app/…
/// (ES modules and fonts don't load reliably over file:// in WKWebView).
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "macdraw"
    static let startURL = URL(string: "macdraw://app/index.html")!

    private let root: URL = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true).standardizedFileURL

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let fileURL = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL

        guard fileURL.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: fileURL) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(response)
            task.didFinish()
            return
        }
        let headers = [
            "Content-Type": Self.mimeType(for: fileURL),
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "html": return "text/html; charset=utf-8"
        case "json": return "application/json"
        case "woff2": return "font/woff2"
        case "wasm": return "application/wasm"
        default: return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
