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

    /// Every save (Cmd-S, autosave, Save As, close, quit) funnels through here. Pull the
    /// freshest scene from the editor first, so nothing drawn in the last instant is lost.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        guard let editor, editor.isReady else {
            super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
            return
        }
        editor.serialize { json in
            if let json, !json.isEmpty { self.sceneJSON = json }
            self.performSave(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
        }
    }

    private func performSave(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                             completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    // MARK: Called by the editor

    func editorDidChange() {
        updateChangeCount(.changeDone)
    }

    func editorDidSerialize(_ json: String) {
        sceneJSON = json
    }
}
