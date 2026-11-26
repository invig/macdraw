import XCTest
@testable import MacDrawApp
import WebKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Messages a drawing's script-enabled iframe can post once WebKit has installed
/// `window.webkit.messageHandlers.macdraw` in that frame. The native handler must
/// ignore every message that is not from the main frame whose URL is the bundled
/// macdraw page. These tests fail while that check is missing.
final class EditorBridgeSecurityTests: XCTestCase {
    private let victimLibrary = #"{"type":"excalidrawlib","version":2,"libraryItems":[{"id":"victim-shape"}]}"#
    private let attackerLibrary = #"{"type":"excalidrawlib","version":2,"libraryItems":[]}"#
    private let benignLibrary = #"{"type":"excalidrawlib","version":2,"libraryItems":[{"id":"benign-shape"}]}"#
    private let victimScene = #"{"type":"excalidraw","version":2,"elements":[{"id":"kept"}]}"#
    private let attackerScene = #"{"type":"excalidraw","version":2,"elements":[]}"#

    override func setUp() {
        super.setUp()
        TestHome.prepare()
        try? FileManager.default.removeItem(at: LibraryStore.url)
    }

    // MARK: Library

    func testSubframeLibraryMessageDoesNotReplaceStoredLibrary() {
        LibraryStore.save(victimLibrary)
        let (document, editor) = makeEditor()
        _ = document
        deliver(editor, ["type": "library", "json": attackerLibrary], from: srcdocFrame())
        XCTAssertEqual(LibraryStore.load(), victimLibrary)
    }

    func testSubframeLibraryMessageDoesNotCreateLibraryFile() {
        let (_, editor) = makeEditor()
        deliver(editor, ["type": "library", "json": attackerLibrary], from: srcdocFrame())
        XCTAssertFalse(FileManager.default.fileExists(atPath: LibraryStore.url.path))
    }

    func testSubframeLibraryMessageDoesNotPushLibraryIntoOtherDrawings() {
        LibraryStore.save(victimLibrary)
        let (_, sender) = makeEditor()
        let (_, receiver) = makeEditor()
        becomeReady(sender)
        becomeReady(receiver)
        let receiverWeb = webView(receiver)
        receiverWeb.removeAllScriptCalls()

        deliver(sender, ["type": "library", "json": attackerLibrary], from: srcdocFrame())

        XCTAssertEqual(LibraryStore.load(), victimLibrary)
        XCTAssertFalse(receiverWeb.scriptCalls.contains(where: { $0.functionBody.contains("setLibrary") }))
    }

    func testSubframeLoadedWithTheAppURLDoesNotReplaceLibrary() {
        LibraryStore.save(victimLibrary)
        let (_, editor) = makeEditor()
        // The navigation delegate allows the macdraw scheme in every frame, so an
        // embedded frame can sit on the same URL as the main page.
        deliver(editor, ["type": "library", "json": attackerLibrary], from: frame(main: false, url: BundleSchemeHandler.startURL))
        XCTAssertEqual(LibraryStore.load(), victimLibrary)
    }

    func testMainFrameOnAnotherURLDoesNotReplaceLibrary() {
        LibraryStore.save(victimLibrary)
        let (_, editor) = makeEditor()
        let web = webView(editor)
        XCTAssertEqual(web.url, BundleSchemeHandler.startURL)
        deliver(editor, ["type": "library", "json": attackerLibrary], from: frame(main: true, url: URL(string: "https://evil.example/index.html")!))
        XCTAssertEqual(LibraryStore.load(), victimLibrary)
    }

    func testMainFrameOnAnotherMacDrawURLDoesNotReplaceLibrary() {
        LibraryStore.save(victimLibrary)
        let (_, editor) = makeEditor()
        deliver(editor, ["type": "library", "json": attackerLibrary], from: frame(main: true, url: URL(string: "macdraw://app/other.html")!))
        XCTAssertEqual(LibraryStore.load(), victimLibrary)
        deliver(editor, ["type": "library", "json": attackerLibrary], from: frame(main: true, url: URL(string: "macdraw://evil/index.html")!))
        XCTAssertEqual(LibraryStore.load(), victimLibrary)
    }

    func testMainFrameAppPageLibraryIsStoredAndPushed() {
        LibraryStore.save(victimLibrary)
        let (_, sender) = makeEditor()
        let (_, receiver) = makeEditor()
        becomeReady(sender)
        becomeReady(receiver)
        let receiverWeb = webView(receiver)
        receiverWeb.removeAllScriptCalls()

        deliver(sender, ["type": "library", "json": benignLibrary], from: appFrame())

        XCTAssertEqual(LibraryStore.load(), benignLibrary)
        let pushed = receiverWeb.scriptCalls.filter { $0.functionBody.contains("setLibrary") }
        XCTAssertEqual(pushed.count, 1)
        XCTAssertEqual(pushed[0].arguments["json"] as? String, benignLibrary)
    }

    func testAcceptedLibraryMessageDoesNotAuthorizeTheNextFrame() {
        LibraryStore.save(victimLibrary)
        let (_, editor) = makeEditor()
        deliver(editor, ["type": "library", "json": benignLibrary], from: appFrame())
        XCTAssertEqual(LibraryStore.load(), benignLibrary)
        deliver(editor, ["type": "library", "json": attackerLibrary], from: srcdocFrame())
        XCTAssertEqual(LibraryStore.load(), benignLibrary)
    }

    /// The frame identity and the body have to be the pair captured together.
    /// Reading either one again returns a different value, the way a path can
    /// change between a check and the later use of that path.
    func testLibraryActionUsesTheSameFrameAndBodySnapshot() {
        LibraryStore.save(victimLibrary)
        let (_, editor) = makeEditor()
        let web = webView(editor)
        let message = RebindingScriptMessage(
            name: "macdraw",
            webView: web,
            firstBody: ["type": "library", "json": benignLibrary],
            laterBody: ["type": "library", "json": attackerLibrary],
            firstFrame: appFrame(),
            laterFrame: srcdocFrame()
        )
        web.configuration.userContentController.deliver(message)
        XCTAssertEqual(LibraryStore.load(), benignLibrary)
        XCTAssertGreaterThanOrEqual(message.bodyReads, 1)
        XCTAssertGreaterThanOrEqual(message.frameReads, 1)
    }

    // MARK: Scene, dirty, ready, log

    func testSubframeSceneMessageDoesNotReplaceTheDocument() {
        let (document, editor) = makeEditor()
        document.editorDidSerialize(victimScene)
        deliver(editor, ["type": "scene", "json": attackerScene], from: srcdocFrame())
        XCTAssertEqual(document.sceneJSON, victimScene)
    }

    func testMainFrameAppPageSceneMessageUpdatesTheDocument() {
        let (document, editor) = makeEditor()
        document.editorDidSerialize(victimScene)
        deliver(editor, ["type": "scene", "json": benignScene], from: appFrame())
        XCTAssertEqual(document.sceneJSON, benignScene)
    }

    func testSubframeDirtyMessageDoesNotMarkTheDocumentChanged() {
        let (document, editor) = makeEditor()
        let before = document.testChangeCount
        deliver(editor, ["type": "dirty"], from: srcdocFrame())
        XCTAssertEqual(document.testChangeCount, before)
    }

    func testMainFrameAppPageDirtyMessageMarksTheDocumentChanged() {
        let (document, editor) = makeEditor()
        let before = document.testChangeCount
        deliver(editor, ["type": "dirty"], from: appFrame())
        XCTAssertEqual(document.testChangeCount, before + 1)
    }

    func testSubframeReadyMessageDoesNotReloadTheEditor() {
        let (_, editor) = makeEditor()
        becomeReady(editor)
        let web = webView(editor)
        web.removeAllScriptCalls()
        deliver(editor, ["type": "ready"], from: srcdocFrame())
        XCTAssertFalse(web.scriptCalls.contains(where: { $0.functionBody.contains("macdraw.load") }))
        XCTAssertTrue(editor.isReady)
    }

    func testMainFrameAppPageReadyMessageLoadsTheEditor() {
        let (_, editor) = makeEditor()
        let web = webView(editor)
        web.removeAllScriptCalls()
        deliver(editor, ["type": "ready"], from: appFrame())
        XCTAssertTrue(web.scriptCalls.contains(where: { $0.functionBody.contains("macdraw.load") }))
        XCTAssertTrue(editor.isReady)
    }

    func testSubframeLogMessageIsNotLogged() {
        let (_, editor) = makeEditor()
        let logged = captureStderr {
            deliver(editor, ["type": "log", "message": "iframe-log-marker"], from: srcdocFrame())
        }
        XCTAssertFalse(logged.contains("iframe-log-marker"))
    }

    func testMainFrameAppPageLogMessageIsLogged() {
        let (_, editor) = makeEditor()
        let logged = captureStderr {
            deliver(editor, ["type": "log", "message": "main-log-marker"], from: appFrame())
        }
        XCTAssertTrue(logged.contains("main-log-marker"))
    }

    private let benignScene = #"{"type":"excalidraw","version":2,"elements":[{"id":"kept"},{"id":"added"}]}"#

    // MARK: Harness

    private func makeEditor() -> (ExcalidrawDocument, EditorViewController) {
        let document = ExcalidrawDocument()
        let editor = EditorViewController(document: document)
        document.editor = editor
        _ = editor.view
        return (document, editor)
    }

    private func webView(_ editor: EditorViewController) -> WKWebView {
        editor.view as! WKWebView
    }

    private func becomeReady(_ editor: EditorViewController) {
        deliver(editor, ["type": "ready"], from: appFrame())
        XCTAssertTrue(editor.isReady)
    }

    @discardableResult
    private func deliver(_ editor: EditorViewController, _ body: [String: Any], from frame: WKFrameInfo) -> WKScriptMessage {
        let web = webView(editor)
        let message = WKScriptMessage(body: body, name: "macdraw", frameInfo: frame, webView: web)
        web.configuration.userContentController.deliver(message)
        return message
    }

    private func appFrame() -> WKFrameInfo {
        frame(main: true, url: BundleSchemeHandler.startURL)
    }

    private func srcdocFrame() -> WKFrameInfo {
        // WebKit's URL for an iframe whose content came from srcdoc.
        frame(main: false, url: URL(string: "about:srcdoc")!)
    }

    private func frame(main: Bool, url: URL) -> WKFrameInfo {
        WKFrameInfo(isMainFrame: main, url: url)
    }
}

/// First read of `body` and of `frameInfo` is the authorized pair. A later read
/// is a different frame and a different payload.
private final class RebindingScriptMessage: WKScriptMessage {
    let firstBody: [String: Any]
    let laterBody: [String: Any]
    let firstFrame: WKFrameInfo
    let laterFrame: WKFrameInfo
    private(set) var bodyReads = 0
    private(set) var frameReads = 0

    init(name: String, webView: WKWebView?, firstBody: [String: Any], laterBody: [String: Any], firstFrame: WKFrameInfo, laterFrame: WKFrameInfo) {
        self.firstBody = firstBody
        self.laterBody = laterBody
        self.firstFrame = firstFrame
        self.laterFrame = laterFrame
        super.init(body: firstBody, name: name, frameInfo: firstFrame, webView: webView)
    }

    override var body: Any {
        bodyReads += 1
        return bodyReads == 1 ? firstBody : laterBody
    }

    override var frameInfo: WKFrameInfo {
        frameReads += 1
        return frameReads == 1 ? firstFrame : laterFrame
    }
}

private enum TestHome {
    static let root: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("macdraw-bridge-tests-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        setenv("HOME", url.path, 1)
        return url
    }()

    static func prepare() { _ = root }
}

private func captureStderr(_ body: () -> Void) -> String {
    let pipe = Pipe()
    fflush(stderr)
    let saved = dup(STDERR_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    body()
    fflush(stderr)
    pipe.fileHandleForWriting.closeFile()
    dup2(saved, STDERR_FILENO)
    close(saved)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
