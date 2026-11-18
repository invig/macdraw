import AppKit

/// Programmatic main menu. Standard selectors route through the responder chain to
/// NSDocumentController / NSDocument / the editor, so Save, Duplicate, Rename, Move To,
/// Revert To and Open Recent all come from AppKit for free.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        let appName = ProcessInfo.processInfo.processName

        // App
        let app = submenu(in: main, title: appName)
        app.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(withTitle: "Check for Updates…", action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "").target = Updater.shared
        app.addItem(withTitle: "Check for Updates Automatically", action: #selector(Updater.toggleAutomatic(_:)), keyEquivalent: "").target = Updater.shared
        app.addItem(.separator())
        let services = NSMenu()
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File
        let file = submenu(in: main, title: "File")
        file.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recentItem = file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        let recent = NSMenu(title: "Open Recent")
        // Tells AppKit to manage this submenu as the recent-documents list.
        recent.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
        recent.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        recentItem.submenu = recent
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        file.addItem(withTitle: "Duplicate", action: #selector(NSDocument.duplicate(_:)), keyEquivalent: "S")
        let saveAs = file.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift, .option]
        saveAs.isAlternate = true
        file.addItem(withTitle: "Rename…", action: #selector(NSDocument.rename(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Move To…", action: #selector(NSDocument.move(_:)), keyEquivalent: "")
        let revertItem = file.addItem(withTitle: "Revert To", action: nil, keyEquivalent: "")
        let revert = NSMenu(title: "Revert To")
        revert.addItem(withTitle: "Last Saved Version", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        revert.addItem(withTitle: "Browse All Versions…", action: #selector(NSDocument.browseVersions(_:)), keyEquivalent: "")
        revertItem.submenu = revert
        file.addItem(.separator())
        let png = file.addItem(withTitle: "Export as PNG…", action: #selector(EditorViewController.exportImage(_:)), keyEquivalent: "e")
        png.keyEquivalentModifierMask = [.command, .option]  // ⇧⌘E is Excalidraw's own export dialog
        png.tag = 0
        file.addItem(withTitle: "Export as SVG…", action: #selector(EditorViewController.exportImage(_:)), keyEquivalent: "").tag = 1
        file.addItem(.separator())
        file.addItem(withTitle: "Show in Finder", action: #selector(EditorViewController.showInFinder(_:)), keyEquivalent: "")

        // Edit
        let edit = submenu(in: main, title: "Edit")
        edit.addItem(withTitle: "Undo", action: #selector(EditorWebView.undo(_:)), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: #selector(EditorWebView.redo(_:)), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View
        let view = submenu(in: main, title: "View")
        view.addItem(withTitle: "Show Tab Bar", action: #selector(NSWindow.toggleTabBar(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.command, .control]

        // Window
        let window = submenu(in: main, title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        // Help
        let help = submenu(in: main, title: "Help")
        NSApp.helpMenu = help

        return main
    }

    private static func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        return menu
    }
}
