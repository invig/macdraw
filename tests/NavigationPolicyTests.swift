import Foundation

/// Security spec for EditorViewController's navigation and window.open delegates.
/// These assertions fail while every non-bundle URL is handed to NSWorkspace.shared.open,
/// including navigations started by a subframe or by script.
enum NavigationPolicyTests {
    static let iframeHTTPS = "https://attacker.example/from-iframe"
    static let iframeSMB = "smb://attacker.example/share"
    static let iframeErrorHTTPS = "https://attacker.example/from-error"
    static let popupSMB = "smb://attacker.example/popup"
    static let libraries = "https://libraries.excalidraw.com"

    static func run() -> Int {
        var failed = 0
        func check(_ name: String, _ ok: Bool, _ detail: String) {
            if ok {
                print("PASS \(name)")
            } else {
                failed += 1
                print("FAIL \(name) \(detail)")
            }
        }

        let editor = EditorViewController(document: ExcalidrawDocument())
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            configuration: WKWebViewConfiguration()
        )

        func decide(_ action: WKNavigationAction) -> (WKNavigationActionPolicy?, [URL]) {
            NSWorkspace.openedURLs.removeAll()
            var policy: WKNavigationActionPolicy?
            editor.webView(webView, decidePolicyFor: action) { policy = $0 }
            return (policy, NSWorkspace.openedURLs)
        }

        func popup(_ action: WKNavigationAction) -> (WKWebView?, [URL]) {
            NSWorkspace.openedURLs.removeAll()
            let created = editor.webView(
                webView,
                createWebViewWith: WKWebViewConfiguration(),
                for: action,
                windowFeatures: WKWindowFeatures()
            )
            return (created, NSWorkspace.openedURLs)
        }

        func action(
            _ urlString: String?,
            type: WKNavigationType,
            sourceMain: Bool,
            targetMain: Bool?,
            download: Bool = false
        ) -> WKNavigationAction {
            WKNavigationAction(
                testURL: urlString.flatMap { URL(string: $0) },
                navigationType: type,
                sourceIsMainFrame: sourceMain,
                targetIsMainFrame: targetMain,
                shouldPerformDownload: download
            )
        }

        func expectOpen(_ name: String, _ urlString: String, _ result: (WKNavigationActionPolicy?, [URL]), policy: WKNavigationActionPolicy) {
            let opened = result.1.map(\.absoluteString)
            check(
                name,
                result.0 == policy && opened == [urlString],
                "policy=\(String(describing: result.0)) opened=\(opened)"
            )
        }

        func expectNoOpen(_ name: String, _ result: (WKNavigationActionPolicy?, [URL]), policy: WKNavigationActionPolicy) {
            let opened = result.1.map(\.absoluteString)
            check(
                name,
                result.0 == policy && opened.isEmpty,
                "policy=\(String(describing: result.0)) opened=\(opened)"
            )
        }

        // A click on an http(s) link in the main frame is still handed to the system browser.
        expectOpen(
            "mainFrameLinkClickOpensHTTPS",
            libraries,
            decide(action(libraries, type: .linkActivated, sourceMain: true, targetMain: true)),
            policy: .cancel
        )
        expectOpen(
            "mainFrameLinkClickOpensHTTP",
            "http://example.com/help",
            decide(action("http://example.com/help", type: .linkActivated, sourceMain: true, targetMain: true)),
            policy: .cancel
        )

        // The editor's own pages, blob/data/about (including about:srcdoc), stay inside the view.
        for (name, url, sourceMain, targetMain) in [
            ("mainFrameMacdrawLoadStaysInView", "macdraw://app/index.html", true, true),
            ("subframeAboutSrcdocStaysInView", "about:srcdoc", false, false),
            ("subframeBlobStaysInView", "blob:https://example/uuid", false, false),
            ("mainFrameDataStaysInView", "data:text/html,hi", true, true),
        ] as [(String, String, Bool, Bool?)] {
            expectNoOpen(
                name,
                decide(action(url, type: .other, sourceMain: sourceMain, targetMain: targetMain)),
                policy: .allow
            )
        }

        expectNoOpen(
            "downloadIsNotLaunched",
            decide(action(iframeHTTPS, type: .other, sourceMain: true, targetMain: true, download: true)),
            policy: .download
        )
        expectNoOpen(
            "missingURLIsCancelled",
            decide(action(nil, type: .linkActivated, sourceMain: true, targetMain: true)),
            policy: .cancel
        )

        // Custom schemes are not launched, even from a real click in the main frame.
        for (name, url) in [
            ("mainFrameClickDoesNotOpenSMB", iframeSMB),
            ("mainFrameClickDoesNotOpenFile", "file:///etc/passwd"),
            ("mainFrameClickDoesNotOpenJavaScript", "javascript:void(0)"),
        ] {
            expectNoOpen(
                name,
                decide(action(url, type: .linkActivated, sourceMain: true, targetMain: true)),
                policy: .cancel
            )
        }

        // Script and form navigations in the main frame are not launched.
        expectNoOpen(
            "mainFrameScriptNavigationDoesNotOpenHTTPS",
            decide(action(iframeHTTPS, type: .other, sourceMain: true, targetMain: true)),
            policy: .cancel
        )
        expectNoOpen(
            "mainFrameFormSubmitDoesNotOpenHTTPS",
            decide(action(iframeHTTPS, type: .formSubmitted, sourceMain: true, targetMain: true)),
            policy: .cancel
        )

        // The drawing's iframe generation HTML navigates its own frame (source and target
        // are the subframe) without a click. That must not reach Launch Services.
        expectNoOpen(
            "iframeScriptNavigationDoesNotOpenHTTPS",
            decide(action(iframeHTTPS, type: .other, sourceMain: false, targetMain: false)),
            policy: .cancel
        )
        expectNoOpen(
            "iframeScriptNavigationDoesNotOpenSMB",
            decide(action(iframeSMB, type: .other, sourceMain: false, targetMain: false)),
            policy: .cancel
        )
        expectNoOpen(
            "iframeErrorScriptNavigationDoesNotOpenHTTPS",
            decide(action(iframeErrorHTTPS, type: .other, sourceMain: false, targetMain: false)),
            policy: .cancel
        )
        // A click inside the embedded frame is still a subframe navigation.
        expectNoOpen(
            "iframeLinkClickDoesNotOpenHTTPS",
            decide(action(iframeHTTPS, type: .linkActivated, sourceMain: false, targetMain: false)),
            policy: .cancel
        )
        // A subframe that aims at the main frame (target=_top or top.location) is not a main-frame click.
        expectNoOpen(
            "subframeTopNavigationDoesNotOpenHTTPS",
            decide(action(iframeHTTPS, type: .other, sourceMain: false, targetMain: true)),
            policy: .cancel
        )
        // New-window navigations are decided in createWebViewWith, not by opening here too.
        expectNoOpen(
            "decidePolicyDoesNotOpenWhenTargetFrameIsNil",
            decide(action(iframeHTTPS, type: .other, sourceMain: false, targetMain: nil)),
            policy: .cancel
        )

        func expectPopupOpen(_ name: String, _ urlString: String, _ result: (WKWebView?, [URL])) {
            let opened = result.1.map(\.absoluteString)
            check(name, result.0 == nil && opened == [urlString], "view=\(result.0 == nil) opened=\(opened)")
        }
        func expectPopupClosed(_ name: String, _ result: (WKWebView?, [URL])) {
            let opened = result.1.map(\.absoluteString)
            check(name, result.0 == nil && opened.isEmpty, "view=\(result.0 == nil) opened=\(opened)")
        }

        expectPopupOpen(
            "mainFrameBlankLinkOpensHTTPS",
            libraries,
            popup(action(libraries, type: .linkActivated, sourceMain: true, targetMain: nil))
        )
        expectPopupClosed(
            "mainFrameBlankLinkDoesNotOpenSMB",
            popup(action(iframeSMB, type: .linkActivated, sourceMain: true, targetMain: nil))
        )
        expectPopupClosed(
            "windowOpenFromIframeDoesNotOpenHTTPS",
            popup(action(iframeHTTPS, type: .other, sourceMain: false, targetMain: nil))
        )
        expectPopupClosed(
            "windowOpenFromIframeDoesNotOpenSMB",
            popup(action(popupSMB, type: .other, sourceMain: false, targetMain: nil))
        )
        expectPopupClosed(
            "windowOpenFromMainFrameScriptDoesNotOpenHTTPS",
            popup(action(iframeHTTPS, type: .other, sourceMain: true, targetMain: nil))
        )
        expectPopupClosed(
            "windowOpenFromIframeClickDoesNotOpenHTTPS",
            popup(action(iframeHTTPS, type: .linkActivated, sourceMain: false, targetMain: nil))
        )

        // The URL that is launched is the URL on the action, not some other URL.
        let allowed = decide(action(libraries, type: .linkActivated, sourceMain: true, targetMain: true))
        check(
            "openedURLIsTheActionURL",
            allowed.1.map(\.absoluteString) == [libraries],
            "opened=\(allowed.1.map(\.absoluteString))"
        )

        print(failed == 0 ? "ALL PASSED" : "\(failed) FAILED")
        return failed
    }
}
