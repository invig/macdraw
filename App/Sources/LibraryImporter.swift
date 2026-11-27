import AppKit

/// Handles the links libraries.excalidraw.com sends back after "Add to Excalidraw":
///   macdraw://app/index.html#addLibrary=<library URL>&token=<token>
/// Fetches the library and hands it to the frontmost editor, which asks before adding it.
/// Any app or website can open a macdraw link, so only links carrying a token this app
/// issued (see `libraryBrowserURL(_:)`) are followed.
enum LibraryImporter {
    private static let maxBytes = 25 * 1024 * 1024
    static let librarySiteHost = "libraries.excalidraw.com"

    /// Token -> the URL it was issued for. A token issued for a library file authorizes only
    /// that file; one issued for the library site's browse page authorizes the files that site
    /// links back to, which it serves from its own host.
    private static var issuedTokens: [String: URL] = [:]
    private static let issuedTokensLock = NSLock()

    @MainActor
    static func handle(_ url: URL) {
        NSApp.activate()
        guard url.scheme == BundleSchemeHandler.scheme,
              let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment else { return }
        var params = URLComponents()
        params.percentEncodedQuery = fragment
        guard let source = params.queryItems?.first(where: { $0.name == "addLibrary" })?.value else { return }
        let token = params.queryItems?.first(where: { $0.name == "token" })?.value

        guard let libraryURL = URL(string: source), isAllowed(libraryURL), let host = libraryURL.host else {
            return showError("This library link isn't from the Excalidraw library site, so it wasn't opened.\n\n\(source)")
        }
        guard isAuthorized(libraryURL, token: token) else {
            return showError("This library link wasn't opened from MacDraw's “Browse libraries”, so it wasn't opened.\n\n\(source)")
        }

        Task { @MainActor in
            do {
                let json = try await fetchLibrary(libraryURL)
                let name = libraryURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
                targetEditor()?.importLibrary(json, name: name, host: host)
            } catch {
                showError("Couldn't download the library.\n\n\(error.localizedDescription)")
            }
        }
    }

    /// Returns a token that lets a macdraw link install from `url` (see `issuedTokens`).
    static func issueAddLibraryToken(for url: URL) -> String {
        var generator = SystemRandomNumberGenerator()
        let token = (0..<4).map { _ in String(generator.next() as UInt64, radix: 16) }.joined(separator: "-")
        issuedTokensLock.lock()
        issuedTokens[token] = url
        issuedTokensLock.unlock()
        return token
    }

    /// Excalidraw's "Browse libraries" link, with a token this app issued and this app as the
    /// page the site links back to. Other URLs are returned unchanged.
    static func libraryBrowserURL(_ url: URL) -> URL {
        guard url.scheme == "https", url.host?.lowercased() == librarySiteHost, isBrowsePage(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != "token" && $0.name != "referrer" }
        items.append(URLQueryItem(name: "referrer", value: BundleSchemeHandler.startURL.absoluteString))
        items.append(URLQueryItem(name: "token", value: issueAddLibraryToken(for: URL(string: "https://\(librarySiteHost)/")!)))
        components.queryItems = items
        return components.url ?? url
    }

    private static func isAuthorized(_ libraryURL: URL, token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        issuedTokensLock.lock()
        let issuedFor = issuedTokens[token]
        issuedTokensLock.unlock()
        guard let issuedFor else { return false }
        if issuedFor.absoluteString == libraryURL.absoluteString { return true }
        return issuedFor.host?.lowercased() == librarySiteHost && isBrowsePage(issuedFor)
            && libraryURL.host?.lowercased() == librarySiteHost
    }

    private static func isBrowsePage(_ url: URL) -> Bool {
        url.path.isEmpty || url.path == "/"
    }

    /// Published libraries only: the library site, or the default branch of its GitHub
    /// repository (pull-request refs, other branches and commits there are unreviewed).
    private static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              let host = url.host?.lowercased(), let segments = pathSegments(url), !segments.isEmpty else { return false }
        if host == librarySiteHost || host == "excalidraw.com" { return true }
        guard host == "raw.githubusercontent.com" else { return false }
        let publishedRefs = [["excalidraw", "excalidraw-libraries", "main"],
                             ["excalidraw", "excalidraw-libraries", "refs", "heads", "main"]]
        return publishedRefs.contains { ref in
            segments.count > ref.count && Array(segments.prefix(ref.count)) == ref
        }
    }

    /// Decoded path segments, or nil if any of them could make the server resolve the
    /// path somewhere other than where it reads (empty, `.`, `..`, or an encoded separator).
    private static func pathSegments(_ url: URL) -> [String]? {
        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              path.hasPrefix("/") else { return nil }
        var segments: [String] = []
        for raw in path.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            guard let segment = String(raw).removingPercentEncoding, !segment.isEmpty, segment != ".", segment != "..",
                  !segment.contains("/"), !segment.contains("\\") else { return nil }
            segments.append(segment)
        }
        return segments
    }

    private static func fetchLibrary(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "The server returned an error."])
        }
        guard http.url?.absoluteString == url.absoluteString else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "The library was served from a different address."])
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

/// The library must come from the URL that was checked, not wherever it redirects.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
