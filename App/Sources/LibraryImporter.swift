import AppKit

/// Handles the links libraries.excalidraw.com sends back after "Add to Excalidraw":
///   macdraw://app/index.html#addLibrary=<library URL>&token=<token>
/// Fetches the library and hands it to the frontmost editor, which asks before adding it.
enum LibraryImporter {
    private static let maxBytes = 25 * 1024 * 1024

    @MainActor
    static func handle(_ url: URL) {
        NSApp.activate()
        guard url.scheme == BundleSchemeHandler.scheme,
              let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment else { return }
        var params = URLComponents()
        params.percentEncodedQuery = fragment
        guard let source = params.queryItems?.first(where: { $0.name == "addLibrary" })?.value else { return }

        guard let libraryURL = URL(string: source), isAllowed(libraryURL) else {
            return showError("This library link isn't from the Excalidraw library site, so it wasn't opened.\n\n\(source)")
        }

        Task { @MainActor in
            do {
                let json = try await fetchLibrary(libraryURL)
                let name = libraryURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
                targetEditor()?.importLibrary(json, name: name)
            } catch {
                showError("Couldn't download the library.\n\n\(error.localizedDescription)")
            }
        }
    }

    /// Same sources Excalidraw itself accepts by default.
    private static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        if host == "excalidraw.com" || host.hasSuffix(".excalidraw.com") { return true }
        return host == "raw.githubusercontent.com" && url.path.hasPrefix("/excalidraw/excalidraw-libraries/")
    }

    private static func fetchLibrary(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "The server returned an error."])
        }
        guard data.count <= maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "excalidrawlib" else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "That file isn't an Excalidraw library."])
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Frontmost drawing window, or a new untitled one.
    @MainActor
    private static func targetEditor() -> EditorViewController? {
        let frontmost = NSApp.orderedWindows.lazy
            .compactMap { $0.windowController?.document as? ExcalidrawDocument }.first
        if let doc = frontmost ?? NSDocumentController.shared.documents.first as? ExcalidrawDocument, let editor = doc.editor {
            editor.view.window?.makeKeyAndOrderFront(nil)
            return editor
        }
        let doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? ExcalidrawDocument
        return doc?.editor
    }

    @MainActor
    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Add Library"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
