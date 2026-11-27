import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WebKitCapture {
    public static var scripts: [(body: String, arguments: [String: Any])] = []
    /// Stand-in for the page receiving `window.macdraw.importLibrary`. The test
    /// points this at the real native library-message handler.
    public static var onImportLibrary: ((String) -> Void)?
    public static func reset() {
        scripts = []
        onImportLibrary = nil
    }
}

open class WKFrameInfo: NSObject {}

open class WKContentWorld: NSObject {
    public static let page = WKContentWorld()
}

open class WKUserContentController: NSObject {
    open func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {}
}

public protocol WKScriptMessageHandler: NSObjectProtocol {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage)
}

open class WKScriptMessage: NSObject {
    public let body: Any
    public init(body: Any) {
        self.body = body
        super.init()
    }
}

open class WKWebViewConfiguration: NSObject {
    public let userContentController = WKUserContentController()
    open func setURLSchemeHandler(_ handler: WKURLSchemeHandler?, forURLScheme scheme: String) {}
}

public protocol WKURLSchemeHandler: NSObjectProtocol {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask)
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask)
}

public protocol WKURLSchemeTask: NSObjectProtocol {
    var request: URLRequest { get }
    func didReceive(_ response: URLResponse)
    func didReceive(_ data: Data)
    func didFinish()
}
public protocol WKNavigationDelegate: NSObjectProtocol {}
public protocol WKUIDelegate: NSObjectProtocol {}
public protocol WKDownloadDelegate: NSObjectProtocol {}

open class WKNavigationAction: NSObject {
    open var shouldPerformDownload: Bool { false }
    open var request: URLRequest { URLRequest(url: URL(string: "about:blank")!) }
}

public enum WKNavigationActionPolicy { case allow, cancel, download }
public enum WKNavigationResponsePolicy { case allow, cancel, download }

open class WKNavigationResponse: NSObject {
    open var canShowMIMEType: Bool { true }
}

open class WKDownload: NSObject {
    public weak var delegate: WKDownloadDelegate?
}

open class WKOpenPanelParameters: NSObject {
    open var allowsMultipleSelection: Bool { false }
    open var allowsDirectories: Bool { false }
}

open class WKWindowFeatures: NSObject {}

open class WKWebView: NSView {
    public var navigationDelegate: WKNavigationDelegate?
    public var uiDelegate: WKUIDelegate?
    public var allowsMagnification: Bool = false
    public var isInspectable: Bool = false
    public init(frame: NSRect, configuration: WKWebViewConfiguration) { super.init() }
    open func load(_ request: URLRequest) {}
    open func callAsyncJavaScript(
        _ functionBody: String,
        arguments: [String: Any] = [:],
        in frame: WKFrameInfo?,
        in contentWorld: WKContentWorld,
        completionHandler: ((Result<Any, Error>) -> Void)? = nil
    ) {
        WebKitCapture.scripts.append((functionBody, arguments))
        if functionBody.contains("importLibrary"), let json = arguments["json"] as? String {
            WebKitCapture.onImportLibrary?(json)
        }
        completionHandler?(.success(NSNull()))
    }
}
