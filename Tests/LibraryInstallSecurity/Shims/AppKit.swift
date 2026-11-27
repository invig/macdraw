import Foundation

public struct Selector: Equatable, Hashable {
    public init(_ value: String) {}
    public static func == (lhs: Selector, rhs: Selector) -> Bool { false }
    public func hash(into hasher: inout Hasher) {}
}

public class NSCoder: NSObject {}

public protocol NSMenuItemValidation: NSObjectProtocol {
    func validateMenuItem(_ item: NSMenuItem) -> Bool
}

public struct NSPoint {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct NSSize {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct NSRect {
    public var origin: NSPoint
    public var size: NSSize
    public init(x: Double, y: Double, width: Double, height: Double) {
        origin = NSPoint(x: x, y: y)
        size = NSSize(width: width, height: height)
    }
}

public enum AlertChoice {
    case firstButton
    case secondButton
}

public enum AlertRecorder {
    public static var choice: AlertChoice = .firstButton
    public static var sheets: [(message: String, info: String, buttons: [String])] = []
    public static var modals: [(message: String, info: String)] = []
    public static func reset() {
        choice = .firstButton
        sheets = []
        modals = []
    }
}

open class NSView: NSObject {
    public weak var window: NSWindow?
}

open class NSViewController: NSObject {
    public override init() { super.init() }
    public init(nibName: String?, bundle: Bundle?) { super.init() }
    open var view: NSView = NSView()
    open func loadView() {}
    open func viewDidLoad() {}
    open func viewDidAppear() {}
    open func presentError(_ error: Error) {}
}

open class NSWindow: NSObject {
    public var windowController: NSWindowController?
    public var contentViewController: NSViewController?
    open func makeKeyAndOrderFront(_ sender: Any?) {}
    open func makeFirstResponder(_ responder: NSView?) -> Bool { true }
}

extension NotificationCenter {
    public func addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?) {}
}

open class NSWindowController: NSObject {
    public var document: AnyObject?
    public var window: NSWindow?
    public var shouldCascadeWindows: Bool = false
    public init(window: NSWindow?) {
        self.window = window
        super.init()
        window?.windowController = self
    }
}

open class NSDocument: NSObject {
    public var fileURL: URL?
    public var displayName: String?
}

open class NSDocumentController: NSObject {
    public static let shared = NSDocumentController()
    public var documents: [NSDocument] = []
    open func openUntitledDocumentAndDisplay(_ displayDocument: Bool) throws -> NSDocument {
        throw CocoaError(.fileNoSuchFile)
    }
}

open class NSApplication: NSObject {
    public static let shared = NSApplication()
    public var orderedWindows: [NSWindow] = []
    open func activate() {}
    public struct ModalResponse: Equatable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let OK = ModalResponse(rawValue: 1)
        public static let cancel = ModalResponse(rawValue: 0)
        public static let alertFirstButtonReturn = ModalResponse(rawValue: 1000)
        public static let alertSecondButtonReturn = ModalResponse(rawValue: 1001)
        public static func == (lhs: ModalResponse, rhs: ModalResponse) -> Bool { lhs.rawValue == rhs.rawValue }
    }
}

public let NSApp = NSApplication.shared

open class NSAlert: NSObject {
    public enum Style { case warning, informational, critical }
    public var messageText: String = ""
    public var informativeText: String = ""
    public var alertStyle: Style = .warning
    public var buttons: [String] = []
    public override init() { super.init() }
    public convenience init(error: Error) {
        self.init()
        messageText = (error as NSError).localizedDescription
    }
    open func addButton(withTitle title: String) { buttons.append(title) }
    open func runModal() -> NSApplication.ModalResponse {
        AlertRecorder.modals.append((messageText, informativeText))
        return .OK
    }
    open func beginSheetModal(for window: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        AlertRecorder.sheets.append((messageText, informativeText, buttons))
        let response: NSApplication.ModalResponse = AlertRecorder.choice == .firstButton ? .alertFirstButtonReturn : .alertSecondButtonReturn
        handler?(response)
    }
}

open class NSSavePanel: NSObject {
    public var nameFieldStringValue: String = ""
    public var directoryURL: URL?
    public var canCreateDirectories: Bool = false
    public var title: String = ""
    public var prompt: String = ""
    public var isExtensionHidden: Bool = false
    public var url: URL?
    public var accessoryView: NSView?
    open func beginSheetModal(for window: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        handler?(.cancel)
    }
    open func runModal() -> NSApplication.ModalResponse { .cancel }
}

open class NSOpenPanel: NSSavePanel {
    public var allowsMultipleSelection: Bool = false
    public var canChooseDirectories: Bool = false
    public var canChooseFiles: Bool = false
    public var urls: [URL] = []
}

open class NSMenuItem: NSObject {
    public var action: Selector?
    public var tag: Int = 0
}

open class NSSound: NSObject {
    open class func beep() {}
}

open class NSWorkspace: NSObject {
    public static let shared = NSWorkspace()
    open func open(_ url: URL) -> Bool { true }
    open func activateFileViewerSelecting(_ urls: [URL]) {}
}

open class NSButton: NSView {
    public convenience init(checkboxWithTitle title: String, target: Any?, action: Selector?) { self.init() }
    public var state: Int = 0
    public var isEnabled: Bool = true
    public static let on = 1
    public static let off = 0
}

open class NSPopUpButton: NSView {
    open func addItems(withTitles titles: [String]) {}
    open func selectItem(at index: Int) {}
    public var target: AnyObject?
    public var action: Selector?
}
