@_exported import AppKit
@_exported import FoundationNetworking

/// Stand-in for the WebKit objects the editor bridge touches.
///
/// Message delivery matches WebKit-7619.1.26.31.6: the UI process builds a
/// WKScriptMessage from the posting frame and invokes the registered handler
/// with no main-frame filter
/// (WebUserContentControllerProxy.didPostMessage, WKUserContentController.mm
/// ScriptMessageHandlerDelegate.didPostMessage). `frameInfo` and `body` are
/// fixed when the message is created (WKScriptMessage._initWithBody:frameInfo:).

public struct MacDrawScriptCall {
    public let functionBody: String
    public let arguments: [String: Any]
}

open class WKContentWorld: NSObject {
    public static let pageWorld = WKContentWorld()
    public static var page: WKContentWorld { pageWorld }
}

open class WKFrameInfo: NSObject {
    public let isMainFrame: Bool
    public let request: URLRequest
    public init(isMainFrame: Bool, url: URL) {
        self.isMainFrame = isMainFrame
        self.request = URLRequest(url: url)
        super.init()
    }
}

open class WKScriptMessage: NSObject {
    public let name: String
    open private(set) var webView: WKWebView?
    private let storedBody: Any
    private let storedFrameInfo: WKFrameInfo

    public init(body: Any, name: String, frameInfo: WKFrameInfo, webView: WKWebView?) {
        self.storedBody = body
        self.name = name
        self.storedFrameInfo = frameInfo
        self.webView = webView
        super.init()
    }

    /// One snapshot, as WKScriptMessage retains the body and frame info from delivery.
    open var body: Any { storedBody }
    open var frameInfo: WKFrameInfo { storedFrameInfo }
}

public protocol WKScriptMessageHandler: NSObjectProtocol {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage)
}

open class WKUserContentController: NSObject {
    public private(set) var scriptHandlers: [(handler: WKScriptMessageHandler, name: String)] = []

    open func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        scriptHandlers.append((scriptMessageHandler, name))
    }

    /// Delivers `message` the way ScriptMessageHandlerDelegate does: every
    /// handler registered for that name, with the message's own frame info.
    public func deliver(_ message: WKScriptMessage) {
        for entry in scriptHandlers where entry.name == message.name {
            entry.handler.userContentController(self, didReceive: message)
        }
    }
}

open class WKWebViewConfiguration: NSObject {
    public let userContentController = WKUserContentController()
    public override init() { super.init() }
    open func setURLSchemeHandler(_ urlSchemeHandler: (any WKURLSchemeHandler)?, forURLScheme urlScheme: String) {}
}

open class WKNavigation: NSObject {}

open class WKWebView: NSView {
    public let configuration: WKWebViewConfiguration
    open var navigationDelegate: (any WKNavigationDelegate)?
    open var uiDelegate: (any WKUIDelegate)?
    open var allowsMagnification: Bool = false
    open var isInspectable: Bool = false
    /// URL of the main frame. Independent of a script message's frame info.
    open var url: URL?
    public private(set) var scriptCalls: [MacDrawScriptCall] = []

    public init(frame: NSRect, configuration: WKWebViewConfiguration) {
        self.configuration = configuration
        super.init(frame: frame)
    }

    @discardableResult
    open func load(_ request: URLRequest) -> WKNavigation? {
        url = request.url
        return WKNavigation()
    }

    public func removeAllScriptCalls() { scriptCalls.removeAll() }

    open func callAsyncJavaScript(
        _ functionBody: String,
        arguments: [String: Any] = [:],
        in frame: WKFrameInfo? = nil,
        in contentWorld: WKContentWorld,
        completionHandler: ((Result<Any, Error>) -> Void)? = nil
    ) {
        scriptCalls.append(MacDrawScriptCall(functionBody: functionBody, arguments: arguments))
        completionHandler?(.success(NSNull()))
    }
}

public protocol WKURLSchemeHandler: NSObjectProtocol {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask)
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask)
}

public protocol WKURLSchemeTask: AnyObject {
    var request: URLRequest { get }
    func didReceive(_ response: URLResponse)
    func didReceive(_ data: Data)
    func didFinish()
}

open class WKNavigationAction: NSObject {
    open var request: URLRequest = URLRequest(url: URL(string: "about:blank")!)
    open var shouldPerformDownload: Bool = false
}

open class WKNavigationResponse: NSObject {
    open var canShowMIMEType: Bool = true
}

public enum WKNavigationActionPolicy { case cancel, allow, download }
public enum WKNavigationResponsePolicy { case cancel, allow, download }

open class WKDownload: NSObject {
    open weak var delegate: (any WKDownloadDelegate)?
}

public protocol WKDownloadDelegate: NSObjectProtocol {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void)
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?)
}

public protocol WKNavigationDelegate: NSObjectProtocol {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload)
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView)
}

open class WKOpenPanelParameters: NSObject {
    open var allowsMultipleSelection: Bool = false
    open var allowsDirectories: Bool = false
}

open class WKWindowFeatures: NSObject {}

public protocol WKUIDelegate: NSObjectProtocol {
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView?
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void)
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void)
}
