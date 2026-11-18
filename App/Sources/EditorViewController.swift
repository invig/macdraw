import AppKit
import WebKit

/// Hosts the Excalidraw web editor for one document and bridges it to AppKit.
final class EditorViewController: NSViewController {
    private weak var document: ExcalidrawDocument?
    private var webView: EditorWebView!
    /// True once the page has received the document contents.
    private(set) var isReady = false
    /// Libraries to import once the page is ready (a link can arrive before the editor loads).
    private var pendingLibraryImports: [String] = []

    static let libraryDidChange = Notification.Name("MacDrawLibraryDidChange")

    init(document: ExcalidrawDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        config.userContentController.add(WeakMessageHandler(self), name: "macdraw")

        webView = EditorWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820), configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: BundleSchemeHandler.startURL))
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChangedElsewhere(_:)),
                                               name: Self.libraryDidChange, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(webView)
    }

    // MARK: Native -> page

    private func sendDocumentToPage() {
        let scene: Any = document?.sceneJSON ?? NSNull()
        let library: Any = LibraryStore.load() ?? NSNull()
        webView.callAsyncJavaScript("window.macdraw.load(scene, library)",
                                    arguments: ["scene": scene, "library": library],
                                    in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { NSLog("MacDraw: load failed: \(error)") }
            guard let self else { return }
            self.isReady = true
            let pending = self.pendingLibraryImports
            self.pendingLibraryImports.removeAll()
            pending.forEach(self.importLibrary)
        }
    }

    /// Merges a downloaded .excalidrawlib into the library; Excalidraw asks the user first.
    func importLibrary(_ json: String) {
        guard isReady else { return pendingLibraryImports.append(json) }
        webView.callAsyncJavaScript("return await window.macdraw.importLibrary(json)", arguments: ["json": json],
                                    in: nil, in: .page) { [weak self] result in
            guard case .failure(let error) = result, let self else { return }
            NSLog("MacDraw: library import failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't add the library"
            alert.informativeText = error.localizedDescription
            if let window = self.view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
    }

    /// The shared library changed in another window: show the same items here.
    @objc private func libraryChangedElsewhere(_ note: Notification) {
        guard (note.object as AnyObject?) !== self, isReady, let json = note.userInfo?["json"] as? String else { return }
        webView.callAsyncJavaScript("await window.macdraw.setLibrary(json)", arguments: ["json": json],
                                    in: nil, in: .page, completionHandler: nil)
    }

    /// Called after Revert / Browse Versions replaced the document's contents.
    func reloadFromDocument() {
        guard isReady else { return }  // page will pull contents itself on "ready"
        sendDocumentToPage()
    }

    /// Asks the page for the current scene as .excalidraw JSON.
    func serialize(_ completion: @escaping (String?) -> Void) {
        webView.callAsyncJavaScript("return window.macdraw.serialize()", arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value): completion(value as? String)
            case .failure(let error):
                NSLog("MacDraw: serialize failed: \(error)")
                completion(nil)
            }
        }
    }

    // MARK: Actions

    @objc func showInFinder(_ sender: Any?) {
        guard let url = document?.fileURL else { return NSSound.beep() }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// File > Export as PNG… / SVG… (menu item tag: 0 = PNG, 1 = SVG).
    @objc func exportImage(_ sender: Any?) {
        let format: ExportOptions.Format? = (sender as? NSMenuItem).map { $0.tag == 1 ? .svg : .png }
        webView.callAsyncJavaScript("return window.macdraw.exportInfo()", arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result, let info = value as? [String: Any] else { return NSSound.beep() }
            if info["isEmpty"] as? Bool ?? true {
                let alert = NSAlert()
                alert.messageText = "Nothing to export"
                alert.informativeText = "This drawing is empty."
                if let window = self.view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
                return
            }
            self.presentExportPanel(format: format, hasSelection: info["hasSelection"] as? Bool ?? false)
        }
    }

    private func presentExportPanel(format: ExportOptions.Format?, hasSelection: Bool) {
        let baseName = document?.fileURL?.deletingPathExtension().lastPathComponent ?? document?.displayName ?? "Drawing"
        let export = ExportPanel(format: format, hasSelection: hasSelection, baseName: baseName,
                                 directory: document?.fileURL?.deletingLastPathComponent())
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = export.panel.url, let self else { return }
            self.writeExport(options: export.commit(), to: url)
        }
        if let window = view.window { export.panel.beginSheetModal(for: window, completionHandler: finish) }
        else { finish(export.panel.runModal()) }
    }

    private func writeExport(options: ExportOptions, to url: URL) {
        webView.callAsyncJavaScript("return await window.macdraw.exportImage(opts)",
                                    arguments: ["opts": options.scriptValue], in: nil, in: .page) { [weak self] result in
            do {
                guard case .success(let value) = result, let string = value as? String else {
                    if case .failure(let error) = result { throw error }
                    throw CocoaError(.fileWriteUnknown)
                }
                let data: Data?
                switch options.format {
                case .png: data = Data(base64Encoded: string)
                case .svg: data = Data(string.utf8)
                }
                guard let data else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("MacDraw: export failed: \(error)")
                if let window = self?.view.window { NSAlert(error: error).beginSheetModal(for: window) }
            }
        }
    }
}

extension EditorViewController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(showInFinder(_:)): return document?.fileURL != nil
        case #selector(exportImage(_:)): return isReady
        default: return true
        }
    }
}

// MARK: - Page -> native messages

extension EditorViewController: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = false
            sendDocumentToPage()
        case "dirty":
            document?.editorDidChange()
        case "scene":
            if let json = body["json"] as? String { document?.editorDidSerialize(json) }
        case "library":
            if let json = body["json"] as? String, LibraryStore.save(json) {
                NotificationCenter.default.post(name: Self.libraryDidChange, object: self, userInfo: ["json": json])
            }
        case "log":
            NSLog("MacDraw[web]: \(body["message"] ?? "")")
        default:
            break
        }
    }
}

// MARK: - Navigation, downloads (image export), file pickers, external links

extension EditorViewController: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload { return decisionHandler(.download) }
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        switch url.scheme {
        case BundleSchemeHandler.scheme, "blob", "data", "about":
            decisionHandler(.allow)
        default:
            // Links in drawings, "Browse libraries", help: open in the default browser.
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    /// Excalidraw's "Export image" saves via a browser download; route it through a native Save panel.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFilename(suggested: suggestedFilename)
        panel.directoryURL = document?.fileURL?.deletingLastPathComponent()
        panel.canCreateDirectories = true
        let finish: (NSApplication.ModalResponse) -> Void = { result in
            guard result == .OK, let url = panel.url else { return completionHandler(nil) }
            try? FileManager.default.removeItem(at: url)  // user already confirmed replace
            completionHandler(url)
        }
        if let window = view.window { panel.beginSheetModal(for: window, completionHandler: finish) }
        else { finish(panel.runModal()) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        presentError(error)
    }

    private func exportFilename(suggested: String) -> String {
        guard let docName = document?.fileURL?.deletingPathExtension().lastPathComponent else { return suggested }
        let ext = (suggested as NSString).pathExtension
        return ext.isEmpty ? docName : "\(docName).\(ext)"
    }

    /// <input type="file"> (Insert image).
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        let finish: (NSApplication.ModalResponse) -> Void = { completionHandler($0 == .OK ? panel.urls : nil) }
        if let window = view.window { panel.beginSheetModal(for: window, completionHandler: finish) }
        else { finish(panel.runModal()) }
    }

    /// window.open / target=_blank -> default browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        if let window = view.window { alert.beginSheetModal(for: window) { _ in completionHandler() } }
        else { alert.runModal(); completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if let window = view.window {
            alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
        } else {
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    /// If the web process dies, reload; the page re-requests the latest contents on "ready".
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        webView.load(URLRequest(url: BundleSchemeHandler.startURL))
    }
}

// MARK: - Web view with native Undo/Redo routed to Excalidraw's history

final class EditorWebView: WKWebView {
    @objc func undo(_ sender: Any?) {
        callAsyncJavaScript("window.macdraw?.undo()", arguments: [:], in: nil, in: .page)
    }

    @objc func redo(_ sender: Any?) {
        callAsyncJavaScript("window.macdraw?.redo()", arguments: [:], in: nil, in: .page)
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
