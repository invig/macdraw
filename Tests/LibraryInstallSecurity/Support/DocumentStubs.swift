import Foundation

/// Stand-in for the document type LibraryImporter asks for an editor.
/// The library-install path only reads `editor` and `sceneJSON` off this object.
final class ExcalidrawDocument: NSDocument {
    var sceneJSON: String?
    weak var editor: EditorViewController?
    func editorDidChange() {}
    func editorDidSerialize(_ json: String) {}
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
