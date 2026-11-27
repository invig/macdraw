import Foundation

// swift-corelibs-foundation does not provide URLRequest. The editor only
// constructs one from a URL and reads action.request.url.
struct URLRequest {
    var url: URL?
    init(url: URL) { self.url = url }
    init() { self.url = nil }
}

// Stand-ins for the AppKit and WebKit types EditorViewController.swift touches.
// WKNavigationAction / WKFrameInfo / WKNavigationType match the public WebKit headers
// (sourceFrame non-optional, targetFrame optional, WKNavigationTypeOther == -1).
// NSWorkspace.shared.open records the URL instead of calling Launch Services.

struct Selector: Equatable, Hashable {
    let name: String
    init(_ name: String) { self.name = name }
}

extension NotificationCenter {
    func addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?) {}
}

struct NSPoint {
    var x: Double
    var y: Double
}

struct NSSize {
    var width: Double
    var height: Double
    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

struct NSRect {
    var origin: NSPoint
    var size: NSSize
    init(x: Double, y: Double, width: Double, height: Double) {
        origin = NSPoint(x: x, y: y)
        size = NSSize(width: width, height: height)
    }
    init(origin: NSPoint, size: NSSize) {
        self.origin = origin
        self.size = size
    }
}

struct NSEvent {
    struct ModifierFlags: OptionSet {
        let rawValue: UInt
        static let command = ModifierFlags(rawValue: 1 << 20)
        static let shift = ModifierFlags(rawValue: 1 << 17)
    }
}

class NSResponder: NSObject {}

class NSView: NSResponder {
    var frame: NSRect
    weak var window: NSWindow?
    init(frame: NSRect) { self.frame = frame }
}

class NSViewController: NSObject {
    var view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
    init(nibName: String?, bundle: Bundle?) {}
    func loadView() {}
    func viewDidLoad() {}
    func viewDidAppear() {}
    func presentError(_ error: Error) {}
}

class NSWindow: NSObject {
    @discardableResult
    func makeFirstResponder(_ responder: NSResponder?) -> Bool { true }
}

struct NSApplication {
    struct ModalResponse: Equatable {
        let raw: Int
        static let OK = ModalResponse(raw: 1)
        static let cancel = ModalResponse(raw: 0)
        static let alertFirstButtonReturn = ModalResponse(raw: 1000)
        static let alertSecondButtonReturn = ModalResponse(raw: 1001)
    }
}

class NSSound: NSObject {
    static func beep() {}
}

class NSAlert: NSObject {
    var messageText = ""
    var informativeText = ""
    override init() {}
    convenience init(error: Error) { self.init() }
    func addButton(withTitle title: String) {}
    func beginSheetModal(for window: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {}
    func runModal() -> NSApplication.ModalResponse { .cancel }
}

class NSSavePanel: NSObject {
    var nameFieldStringValue = ""
    var directoryURL: URL?
    var canCreateDirectories = false
    var url: URL?
    func beginSheetModal(for window: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {}
    func runModal() -> NSApplication.ModalResponse { .cancel }
}

class NSOpenPanel: NSSavePanel {
    var allowsMultipleSelection = false
    var canChooseDirectories = false
    var canChooseFiles = false
    var urls: [URL] = []
}

class NSMenuItem: NSObject {
    var tag = 0
    var action: Selector?
}

protocol NSMenuItemValidation: AnyObject {
    func validateMenuItem(_ item: NSMenuItem) -> Bool
}

class NSWorkspace: NSObject {
    static let shared = NSWorkspace()
    /// URLs passed to open(_:). Tests read and reset this; Launch Services is not called.
    static var openedURLs: [URL] = []

    @discardableResult
    func open(_ url: URL) -> Bool {
        Self.openedURLs.append(url)
        return true
    }

    func activateFileViewerSelecting(_ fileURLs: [URL]) {}
}

protocol WKURLSchemeHandler: AnyObject {}

class WKUserContentController: NSObject {
    func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {}
}

class WKWebViewConfiguration: NSObject {
    var userContentController = WKUserContentController()
    func setURLSchemeHandler(_ urlSchemeHandler: WKURLSchemeHandler, forURLScheme urlScheme: String) {}
}

class WKContentWorld: NSObject {
    static let page = WKContentWorld()
}

class WKWebView: NSView {
    var navigationDelegate: WKNavigationDelegate?
    var uiDelegate: WKUIDelegate?
    var allowsMagnification = false
    var isInspectable = false
    let configuration: WKWebViewConfiguration

    init(frame: NSRect, configuration: WKWebViewConfiguration) {
        self.configuration = configuration
        super.init(frame: frame)
    }

    func load(_ request: URLRequest) {}

    func callAsyncJavaScript(
        _ functionBody: String,
        arguments: [String: Any],
        in frame: WKFrameInfo?,
        in contentWorld: WKContentWorld,
        completionHandler: ((Result<Any, Error>) -> Void)? = nil
    ) {}
}

protocol WKNavigationDelegate: AnyObject {}
protocol WKUIDelegate: AnyObject {}
protocol WKDownloadDelegate: AnyObject {}
protocol WKScriptMessageHandler: AnyObject {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage)
}

enum WKNavigationType: Int {
    case linkActivated = 0
    case formSubmitted = 1
    case backForward = 2
    case reload = 3
    case formResubmitted = 4
    case other = -1
}

enum WKNavigationActionPolicy {
    case cancel
    case allow
    case download
}

enum WKNavigationResponsePolicy {
    case cancel
    case allow
    case download
}

class WKFrameInfo: NSObject {
    let isMainFrame: Bool
    let request: URLRequest
    init(isMainFrame: Bool, url: URL) {
        self.isMainFrame = isMainFrame
        self.request = URLRequest(url: url)
    }
}

class WKNavigationAction: NSObject {
    let navigationType: WKNavigationType
    let request: URLRequest
    let sourceFrame: WKFrameInfo
    let targetFrame: WKFrameInfo?
    let shouldPerformDownload: Bool
    let modifierFlags: NSEvent.ModifierFlags
    let buttonNumber: Int

    init(
        testURL: URL?,
        navigationType: WKNavigationType,
        sourceIsMainFrame: Bool,
        targetIsMainFrame: Bool?,
        shouldPerformDownload: Bool = false,
        buttonNumber: Int = 0
    ) {
        self.navigationType = navigationType
        if let testURL {
            self.request = URLRequest(url: testURL)
        } else {
            self.request = URLRequest()
        }
        let sourceURL = sourceIsMainFrame
            ? URL(string: "macdraw://app/index.html")!
            : URL(string: "about:srcdoc")!
        self.sourceFrame = WKFrameInfo(isMainFrame: sourceIsMainFrame, url: sourceURL)
        if let targetIsMainFrame {
            let targetURL = targetIsMainFrame ? sourceURL : URL(string: "about:srcdoc")!
            self.targetFrame = WKFrameInfo(isMainFrame: targetIsMainFrame, url: targetURL)
        } else {
            self.targetFrame = nil
        }
        self.shouldPerformDownload = shouldPerformDownload
        self.modifierFlags = []
        self.buttonNumber = buttonNumber
    }
}

class WKNavigationResponse: NSObject {
    var canShowMIMEType = true
}

class WKDownload: NSObject {
    weak var delegate: WKDownloadDelegate?
}

/// Not Foundation's URLResponse (that typealias is unavailable without FoundationNetworking).
class StubURLResponse: NSObject {}

class WKOpenPanelParameters: NSObject {
    var allowsMultipleSelection = false
    var allowsDirectories = false
}

class WKWindowFeatures: NSObject {}

class WKScriptMessage: NSObject {
    var body: Any = [:]
}

// Types from other MacDraw sources that EditorViewController references.

class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "macdraw"
    static let startURL = URL(string: "macdraw://app/index.html")!
}

final class ExcalidrawDocument: NSObject {
    var sceneJSON: String?
    var fileURL: URL?
    var displayName: String? = "Drawing"
    func editorDidChange() {}
    func editorDidSerialize(_ json: String) {}
}

enum LibraryStore {
    static func load() -> String? { nil }
    @discardableResult
    static func save(_ json: String) -> Bool { true }
}

struct ExportOptions {
    enum Format { case png, svg }
    var format: Format = .png
    var scriptValue: [String: Any] { [:] }
}

final class ExportPanel: NSObject {
    let panel = NSSavePanel()
    init(format: ExportOptions.Format?, hasSelection: Bool, baseName: String, directory: URL?) {}
    func commit() -> ExportOptions { ExportOptions() }
}
