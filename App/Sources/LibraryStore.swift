import Foundation

/// Persists the Excalidraw shape library (shared by all documents) in
/// ~/Library/Application Support/MacDraw/library.excalidrawlib
enum LibraryStore {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDraw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.excalidrawlib")
    }()

    static func load() -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    static func save(_ json: String) {
        do { try Data(json.utf8).write(to: url, options: .atomic) }
        catch { NSLog("MacDraw: failed to save library: \(error)") }
    }
}
