import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Spec for library-link installs.
///
/// A macdraw link may install a library only when all of the following hold:
/// - the library URL is https on libraries.excalidraw.com, excalidraw.com, or
///   raw.githubusercontent.com for the excalidraw/excalidraw-libraries repository
/// - the GitHub ref is the default branch (`main` or `refs/heads/main`)
/// - the URL that actually supplied the bytes is that same allowed URL
///   (a redirect, or a `..` path the origin resolves elsewhere, does not count)
/// - the fragment carries the token `LibraryImporter.issueAddLibraryToken(for:)`
///   returned for that exact library URL
/// - the confirmation sheet names the host the bytes came from
///
/// The victim's Add click is simulated. Cancel must not write the shared library.

final class LibraryURLProtocol: URLProtocol {
    struct Outcome {
        var status: Int
        var body: Data
        var responseURL: URL
    }

    static var outcomes: [String: Outcome] = [:]
    static var requested: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        LibraryURLProtocol.requested.append(url.absoluteString)
        let outcome = LibraryURLProtocol.outcomes[url.absoluteString]
            ?? Outcome(status: 404, body: Data("missing".utf8), responseURL: url)
        let response = HTTPURLResponse(
            url: outcome.responseURL,
            statusCode: outcome.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: outcome.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class SecuritySuite {
    private var failures: [String] = []
    private var editor: EditorViewController!
    private var document: ExcalidrawDocument!

    func run() async -> Int {
        URLProtocol.registerClass(LibraryURLProtocol.self)
        prepareEditor()
        WebKitCapture.onImportLibrary = { [weak editor] json in
            guard let editor else { return }
            let message = WKScriptMessage(body: ["type": "library", "json": json])
            editor.userContentController(WKUserContentController(), didReceive: message)
        }

        await pullRequestRefIsNotInstalled()
        await pullMergeRefIsNotInstalled()
        await otherBranchIsNotInstalled()
        await commitShaIsNotInstalled()
        await dotDotPathIsNotInstalled()
        await redirectToOtherHostIsNotInstalled()
        await redirectFromMainToPullRefIsNotInstalled()
        await missingTokenIsNotInstalled()
        await emptyTokenIsNotInstalled()
        await attackerTokenIsNotInstalled()
        await tokenForADifferentURLIsNotInstalled()
        await mainBranchInstallsAndNamesRealHost()
        await refsHeadsMainInstallsAndNamesRealHost()
        await officialSiteInstallsAndNamesThatHost()
        await unrelatedHostIsNotRequested()
        await httpLinkIsNotInstalled()
        await userinfoHostIsNotInstalled()
        await siblingRepositoryPrefixIsNotInstalled()
        await cancelDoesNotWriteTheSharedLibrary()
        await acceptedLibraryIsSharedByEveryDocument()

        if failures.isEmpty {
            print("ALL TESTS PASSED")
            return 0
        }
        print("\(failures.count) TEST(S) FAILED")
        for failure in failures { print("FAIL \(failure)") }
        return 1
    }

    private func prepareEditor() {
        document = ExcalidrawDocument()
        editor = EditorViewController(document: document)
        document.editor = editor
        editor.loadView()
        let window = NSWindow()
        editor.view.window = window
        let controller = NSWindowController(window: window)
        controller.document = document
        NSApp.orderedWindows = [window]
        NSDocumentController.shared.documents = [document]
        editor.viewDidLoad()
        let ready = WKScriptMessage(body: ["type": "ready"])
        editor.userContentController(WKUserContentController(), didReceive: ready)
    }

    private func reset(_ outcomes: [String: LibraryURLProtocol.Outcome]) throws {
        LibraryURLProtocol.outcomes = outcomes
        LibraryURLProtocol.requested = []
        WebKitCapture.scripts = []
        AlertRecorder.reset()
        let directory = LibraryStore.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"sentinel\":true}\n".utf8).write(to: LibraryStore.url, options: .atomic)
    }

    private func library(_ marker: String) -> Data {
        let json = """
        {"type":"excalidrawlib","version":2,"libraryItems":[{"id":"\(marker)","status":"unpublished","created":1,"elements":[{"id":"el-\(marker)","type":"iframe","x":0,"y":0,"width":240,"height":140,"customData":{"generationData":{"status":"done","html":"<!doctype html><p>\(marker)</p>"}}}]}]}
        """
        return Data(json.utf8)
    }

    private func outcome(_ url: URL, body: Data, responseURL: URL? = nil, status: Int = 200) -> (String, LibraryURLProtocol.Outcome) {
        (url.absoluteString, LibraryURLProtocol.Outcome(status: status, body: body, responseURL: responseURL ?? url))
    }

    private func link(to library: URL, token: String?) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }
        var fragment = "addLibrary=\(encode(library.absoluteString))"
        if let token { fragment += "&token=\(encode(token))" }
        let string = "macdraw://app/index.html#\(fragment)"
        guard let url = URL(string: string) else { fatalError("could not form macdraw link") }
        return url
    }

    private func openLikeTheAppDelegate(_ url: URL) {
        // AppDelegate.handleGetURL turns the event's string into a URL and calls this.
        guard let roundTrip = URL(string: url.absoluteString) else { fatalError("url string") }
        LibraryImporter.handle(roundTrip)
    }

    private func importedJSON() -> [String] {
        WebKitCapture.scripts.compactMap { script in
            guard script.body.contains("importLibrary") else { return nil }
            return script.arguments["json"] as? String
        }
    }

    private func libraryFile() -> String {
        (try? String(contentsOf: LibraryStore.url, encoding: .utf8)) ?? ""
    }

    private func waitForImport() async -> Bool {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if !importedJSON().isEmpty { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    private func waitForQuiescence() async {
        _ = await waitForImport()
    }

    private func check(_ name: String, _ condition: Bool, _ detail: String) {
        if condition {
            print("PASS \(name)")
        } else {
            print("FAIL \(name): \(detail)")
            failures.append("\(name): \(detail)")
        }
    }

    private func expectNotInstalled(_ name: String, library: URL, token: String?, forbiddenMarker: String) async {
        openLikeTheAppDelegate(link(to: library, token: token))
        await waitForQuiescence()
        let imported = importedJSON().joined(separator: "\n")
        let stored = libraryFile()
        check(name, !imported.contains(forbiddenMarker) && stored == "{\"sentinel\":true}\n" && !stored.contains(forbiddenMarker),
              "imported=\(imported.contains(forbiddenMarker)) stored=\(stored.contains(forbiddenMarker)) file=\(stored)")
    }

    private func sheetText() -> String {
        AlertRecorder.sheets.map(\.info).joined(separator: "\n")
    }

    // MARK: Unpublished refs

    private func pullRequestRefIsNotInstalled() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/refs/pull/3038/head/libraries/alefy/geometria-espacial.excalidrawlib")!
        let marker = "PULL-HEAD"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectNotInstalled("pull request head ref is not installed", library: url, token: token, forbiddenMarker: marker)
    }

    private func pullMergeRefIsNotInstalled() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/refs/pull/3038/merge/libraries/alefy/geometria-espacial.excalidrawlib")!
        let marker = "PULL-MERGE"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectNotInstalled("pull request merge ref is not installed", library: url, token: token, forbiddenMarker: marker)
    }

    private func otherBranchIsNotInstalled() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/feature-branch/libraries/evil.excalidrawlib")!
        let marker = "OTHER-BRANCH"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectNotInstalled("non-default branch is not installed", library: url, token: token, forbiddenMarker: marker)
    }

    private func commitShaIsNotInstalled() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/a4fd9f7ac518cb88457b0bf9fe1cf6481023d7a3/libraries/alefy/geometria-espacial.excalidrawlib")!
        let marker = "COMMIT-SHA"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectNotInstalled("commit sha ref is not installed", library: url, token: token, forbiddenMarker: marker)
    }

    private func dotDotPathIsNotInstalled() async {
        let requested = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/../../evil-user/evil-repo/pwn.excalidrawlib")!
        let resolved = URL(string: "https://raw.githubusercontent.com/excalidraw/evil-user/evil-repo/pwn.excalidrawlib")!
        let marker = "DOTDOT"
        let body = library(marker)
        try? reset([requested.absoluteString: LibraryURLProtocol.Outcome(status: 200, body: body, responseURL: resolved)])
        let token = LibraryImporter.issueAddLibraryToken(for: requested)
        await expectNotInstalled("dot-dot path is not installed from the resolved URL", library: requested, token: token, forbiddenMarker: marker)
    }

    private func redirectToOtherHostIsNotInstalled() async {
        let requested = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries/safe.excalidrawlib")!
        let final = URL(string: "https://evil.example/payload.excalidrawlib")!
        let marker = "REDIRECT-HOST"
        try? reset([requested.absoluteString: LibraryURLProtocol.Outcome(status: 200, body: library(marker), responseURL: final)])
        let token = LibraryImporter.issueAddLibraryToken(for: requested)
        await expectNotInstalled("redirect to another host is not installed", library: requested, token: token, forbiddenMarker: marker)
    }

    private func redirectFromMainToPullRefIsNotInstalled() async {
        let requested = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries/listed.excalidrawlib")!
        let final = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/refs/pull/9/head/libraries/unreviewed.excalidrawlib")!
        let marker = "REDIRECT-PULL"
        try? reset([requested.absoluteString: LibraryURLProtocol.Outcome(status: 200, body: library(marker), responseURL: final)])
        let token = LibraryImporter.issueAddLibraryToken(for: requested)
        await expectNotInstalled("redirect from main onto a pull ref is not installed", library: requested, token: token, forbiddenMarker: marker)
    }

    // MARK: Token

    private func missingTokenIsNotInstalled() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries/safe.excalidrawlib")!
        let marker = "NO-TOKEN"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        await expectNotInstalled("link with no token is not installed", library: url, token: nil, forbiddenMarker: marker)
    }

    private func emptyTokenIsNotInstalled() async {
        let url = URL(string: "https://libraries.excalidraw.com/libraries/safe.excalidrawlib")!
        let marker = "EMPTY-TOKEN"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        await expectNotInstalled("link with an empty token is not installed", library: url, token: "", forbiddenMarker: marker)
    }

    private func attackerTokenIsNotInstalled() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/refs/heads/main/libraries/safe.excalidrawlib")!
        let marker = "ATTACKER-TOKEN"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        await expectNotInstalled("link with an attacker chosen token is not installed", library: url, token: "attacker-chosen", forbiddenMarker: marker)
    }

    private func tokenForADifferentURLIsNotInstalled() async {
        let authorized = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries/one.excalidrawlib")!
        let other = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries/two.excalidrawlib")!
        let marker = "OTHER-URL"
        try? reset([
            outcome(authorized, body: library("AUTHORIZED")).0: outcome(authorized, body: library("AUTHORIZED")).1,
            outcome(other, body: library(marker)).0: outcome(other, body: library(marker)).1,
        ])
        let token = LibraryImporter.issueAddLibraryToken(for: authorized)
        await expectNotInstalled("token for a different library URL is not installed", library: other, token: token, forbiddenMarker: marker)
    }

    // MARK: Published libraries

    private func expectInstalled(_ name: String, library: URL, token: String, marker: String, hostInPrompt: String, hostAbsentFromPrompt: String?) async {
        openLikeTheAppDelegate(link(to: library, token: token))
        let arrived = await waitForImport()
        let imported = importedJSON().joined(separator: "\n")
        let stored = libraryFile()
        let prompt = sheetText()
        var problems: [String] = []
        if !arrived || !imported.contains(marker) { problems.append("library was not imported") }
        if !stored.contains(marker) { problems.append("shared library file does not contain the library") }
        if !prompt.contains(hostInPrompt) { problems.append("prompt \(prompt.debugDescription) does not name \(hostInPrompt)") }
        if let hostAbsentFromPrompt, prompt.contains(hostAbsentFromPrompt) {
            problems.append("prompt claims \(hostAbsentFromPrompt)")
        }
        check(name, problems.isEmpty, problems.joined(separator: "; "))
    }

    private func mainBranchInstallsAndNamesRealHost() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries/safe.excalidrawlib")!
        let marker = "MAIN-OK"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectInstalled("default branch installs and the prompt names the real host", library: url, token: token, marker: marker, hostInPrompt: "raw.githubusercontent.com", hostAbsentFromPrompt: "libraries.excalidraw.com")
    }

    private func refsHeadsMainInstallsAndNamesRealHost() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/refs/heads/main/libraries/safe.excalidrawlib")!
        let marker = "REFS-HEADS-MAIN"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectInstalled("refs/heads/main installs and the prompt names the real host", library: url, token: token, marker: marker, hostInPrompt: "raw.githubusercontent.com", hostAbsentFromPrompt: "libraries.excalidraw.com")
    }

    private func officialSiteInstallsAndNamesThatHost() async {
        let url = URL(string: "https://libraries.excalidraw.com/libraries/safe.excalidrawlib")!
        let marker = "OFFICIAL-SITE"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectInstalled("libraries.excalidraw.com installs and the prompt names that host", library: url, token: token, marker: marker, hostInPrompt: "libraries.excalidraw.com", hostAbsentFromPrompt: nil)
    }

    // MARK: Hosts that are already rejected

    private func unrelatedHostIsNotRequested() async {
        let url = URL(string: "https://evil.example/excalidraw/excalidraw-libraries/main/libraries/x.excalidrawlib")!
        let marker = "EVIL-HOST"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        openLikeTheAppDelegate(link(to: url, token: token))
        await waitForQuiescence()
        check("unrelated host is not requested", !LibraryURLProtocol.requested.contains(url.absoluteString) && libraryFile() == "{\"sentinel\":true}\n",
              "requested=\(LibraryURLProtocol.requested)")
    }

    private func httpLinkIsNotInstalled() async {
        let url = URL(string: "http://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries/x.excalidrawlib")!
        let marker = "PLAIN-HTTP"
        try? reset([:])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectNotInstalled("http library link is not installed", library: url, token: token, forbiddenMarker: marker)
    }

    private func userinfoHostIsNotInstalled() async {
        let url = URL(string: "https://raw.githubusercontent.com@evil.example/excalidraw/excalidraw-libraries/main/libraries/x.excalidrawlib")!
        let marker = "USERINFO"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectNotInstalled("userinfo host confusion is not installed", library: url, token: token, forbiddenMarker: marker)
    }

    private func siblingRepositoryPrefixIsNotInstalled() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries-evil/main/libraries/x.excalidrawlib")!
        let marker = "SIBLING"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectNotInstalled("sibling repository prefix is not installed", library: url, token: token, forbiddenMarker: marker)
    }

    private func cancelDoesNotWriteTheSharedLibrary() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries/safe.excalidrawlib")!
        let marker = "CANCELLED"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        AlertRecorder.choice = .secondButton
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        await expectNotInstalled("cancel does not write the shared library", library: url, token: token, forbiddenMarker: marker)
    }

    private func acceptedLibraryIsSharedByEveryDocument() async {
        let url = URL(string: "https://raw.githubusercontent.com/excalidraw/excalidraw-libraries/main/libraries/shared.excalidrawlib")!
        let marker = "SHARED"
        try? reset([outcome(url, body: library(marker)).0: outcome(url, body: library(marker)).1])
        let token = LibraryImporter.issueAddLibraryToken(for: url)
        openLikeTheAppDelegate(link(to: url, token: token))
        _ = await waitForImport()
        let first = LibraryStore.load()
        let second = LibraryStore.load()
        let sharedPath = LibraryStore.url.path
        check("accepted library is stored once for every drawing",
              first == second && (first?.contains(marker) ?? false) && sharedPath.contains("MacDraw/library.excalidrawlib"),
              "path=\(sharedPath) first=\(first ?? "nil")")
    }
}

@main
struct SecurityTestMain {
    static func main() async {
        let failures = await SecuritySuite().run()
        if failures != 0 { exit(1) }
    }
}
