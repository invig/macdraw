import AppKit

/// One .excalidraw file. The scene lives in the web editor; this class keeps the latest
/// serialized JSON and lets AppKit handle saving, autosave, Versions and Revert.
final class ExcalidrawDocument: NSDocument {
    /// Latest known file contents. Nil for a new, untouched document.
    private(set) var sceneJSON: String?
    weak var editor: EditorViewController?

    static let emptyScene = """
    {"type":"excalidraw","version":2,"source":"MacDraw","elements":[],"appState":{"gridSize":20,"viewBackgroundColor":"#ffffff"},"files":{}}
    """

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let editor = EditorViewController(document: self)
        self.editor = editor
        let window = NSWindow(contentViewController: editor)
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.minSize = NSSize(width: 480, height: 360)
        window.tabbingMode = .preferred
        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = true
        addWindowController(controller)
        window.center()
    }

    // MARK: Reading & writing

    override func read(from data: Data, ofType typeName: String) throws {
        guard let json = String(data: data, encoding: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        sceneJSON = json
        // Revert / Versions re-read into an open document: push the new contents to the editor.
        if let editor { DispatchQueue.main.async { editor.reloadFromDocument() } }
    }

    override func data(ofType typeName: String) throws -> Data {
        Data((sceneJSON ?? Self.emptyScene).utf8)
    }

    // Saving itself never waits on the web page: AppKit can block the main thread waiting
    // for a save in progress (closing, quitting), and the page's reply needs the main thread,
    // so that would deadlock. Saves write `sceneJSON`, which the page keeps current (400 ms
    // after each edit); the entry points below pull the very latest scene first.

    /// Pulls the latest scene from the editor, giving up after `timeout` (page busy or stuck).
    func flushFromEditor(timeout: TimeInterval = 1.5, then done: @escaping () -> Void) {
        guard let editor, editor.isReady else { return done() }
        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            done()
        }
        editor.serialize { [weak self] json in
            if !finished, let json, !json.isEmpty { self?.sceneJSON = json }
            finish()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if !finished { NSLog("MacDraw: editor didn't answer in time; saving the last known scene") }
            finish()
        }
    }

    override func save(_ sender: Any?) {
        flushFromEditor { super.save(sender) }
    }

    override func saveAs(_ sender: Any?) {
        flushFromEditor { super.saveAs(sender) }
    }

    override func duplicate(_ sender: Any?) {
        flushFromEditor { super.duplicate(sender) }
    }

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        flushFromEditor {
            super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
    }

    // MARK: Called by the editor

    func editorDidChange() {
        updateChangeCount(.changeDone)
    }

    func editorDidSerialize(_ json: String) {
        sceneJSON = json
    }
}
