import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.mainMenu = MainMenu.build()
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // macdraw:// links (libraries.excalidraw.com "Add to Excalidraw"). Registered early so a
        // link that launches the app is caught; file opening is unaffected.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        MainActor.assumeIsolated { LibraryImporter.handle(url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        Updater.shared.start()   // Developer ID builds only
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
}
