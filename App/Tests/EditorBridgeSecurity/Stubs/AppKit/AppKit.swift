@_exported import Foundation
import UniformTypeIdentifiers

#if !canImport(Darwin)
/// Linux Swift has no Objective-C runtime, so Foundation does not define Selector.
public struct Selector: Hashable {
    public let name: String
    public init(_ name: String) { self.name = name }
}
#endif

public struct NSPoint {
    public var x: CGFloat
    public var y: CGFloat
    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

public struct NSSize {
    public var width: CGFloat
    public var height: CGFloat
    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }
}

public struct NSRect {
    public var origin: NSPoint
    public var size: NSSize
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        origin = NSPoint(x: x, y: y)
        size = NSSize(width: width, height: height)
    }
}

open class NSResponder: NSObject {
    open func presentError(_ error: Error) {}
}

open class NSView: NSResponder {
    open var frame: NSRect = NSRect(x: 0, y: 0, width: 0, height: 0)
    open var fittingSize: NSSize { NSSize(width: 0, height: 0) }
    open weak var window: NSWindow?
    open var translatesAutoresizingMaskIntoConstraints: Bool = false
    public override init() { super.init() }
    public init(frame: NSRect) {
        self.frame = frame
        super.init()
    }
    open func addSubview(_ view: NSView) {}
    open var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor() }
    open var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor() }
    open var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor() }
    open var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor() }
}

open class NSLayoutConstraint: NSObject {
    public static func activate(_ constraints: [NSLayoutConstraint]) {}
}

open class NSLayoutAnchor<AnchorType>: NSObject {
    public func constraint(equalTo other: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint {
        NSLayoutConstraint()
    }
    public func constraint(equalTo other: NSLayoutAnchor<AnchorType>, constant: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint()
    }
    public func constraint(greaterThanOrEqualTo other: NSLayoutAnchor<AnchorType>, constant: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint()
    }
}

public typealias NSLayoutXAxisAnchor = NSLayoutAnchor<AnyObject>
public typealias NSLayoutYAxisAnchor = NSLayoutAnchor<AnyObject>

open class NSWindow: NSResponder {
    public enum TabbingMode { case automatic, preferred, disallowed }
    open var contentViewController: NSViewController?
    open var minSize: NSSize = NSSize(width: 0, height: 0)
    open var tabbingMode: TabbingMode = .automatic
    public override init() { super.init() }
    public init(contentViewController: NSViewController?) {
        super.init()
        self.contentViewController = contentViewController
    }
    open func setContentSize(_ size: NSSize) {}
    open func center() {}
    @discardableResult
    open func makeFirstResponder(_ responder: NSResponder?) -> Bool { true }
}

open class NSWindowController: NSObject {
    open var window: NSWindow?
    open var shouldCascadeWindows: Bool = true
    public init(window: NSWindow?) {
        self.window = window
        super.init()
    }
}

open class NSViewController: NSResponder {
    private var storedView: NSView?
    private var didLoad = false
    public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    open func loadView() { storedView = NSView() }
    open var view: NSView {
        get {
            if storedView == nil { loadView() }
            if !didLoad {
                didLoad = true
                viewDidLoad()
            }
            return storedView!
        }
        set { storedView = newValue }
    }
    open func viewDidLoad() {}
    open func viewDidAppear() {}
}

open class NSCoder: NSObject {}

open class NSDocument: NSObject {
    public enum ChangeType { case changeDone, changeUndone, changeCleared, changeReadOtherContents }
    open class var autosavesInPlace: Bool { false }
    open var fileURL: URL?
    open var displayName: String { "Drawing" }
    /// Test-visible count of `updateChangeCount` calls. AppKit does not have this property.
    public private(set) var testChangeCount = 0
    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    open func makeWindowControllers() {}
    open func read(from data: Data, ofType typeName: String) throws {}
    open func data(ofType typeName: String) throws -> Data { Data() }
    open func save(_ sender: Any?) {}
    open func saveAs(_ sender: Any?) {}
    open func duplicate(_ sender: Any?) {}
    open func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {}
    open func addWindowController(_ windowController: NSWindowController) {}
    open func updateChangeCount(_ change: ChangeType) { testChangeCount += 1 }
}

public enum NSApplication {
    public struct ModalResponse: Equatable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let OK = ModalResponse(rawValue: 1)
        public static let cancel = ModalResponse(rawValue: 0)
        public static let alertFirstButtonReturn = ModalResponse(rawValue: 1000)
        public static let alertSecondButtonReturn = ModalResponse(rawValue: 1001)
    }
}

open class NSControl: NSView {
    public struct StateValue: Equatable {
        public static let on = StateValue()
        public static let off = StateValue()
        public static let mixed = StateValue()
    }
    open var state: StateValue = .off
    open var isEnabled: Bool = true
    open weak var target: AnyObject?
    open var action: Selector?
    public enum TextAlignment { case left, right, center, natural }
    open var alignment: TextAlignment = .natural
}

open class NSButton: NSControl {
    public convenience init(checkboxWithTitle title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        self.target = target
        self.action = action
    }
}

open class NSPopUpButton: NSControl {
    public private(set) var itemTitles: [String] = []
    public private(set) var indexOfSelectedItem: Int = -1
    open func addItems(withTitles titles: [String]) { itemTitles.append(contentsOf: titles) }
    open func selectItem(at index: Int) { indexOfSelectedItem = index }
}

open class NSTextField: NSControl {
    public convenience init(labelWithString stringValue: String) {
        self.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
    }
}

open class NSGridColumn: NSObject {
    public enum Placement { case none, leading, center, trailing, fill }
    public var xPlacement: Placement = .fill
}

public enum NSGridCell {
    public static let emptyContentView = NSView()
}

open class NSGridView: NSView {
    public init(views: [[NSView]]) {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
    }
    open var rowSpacing: CGFloat = 0
    open var columnSpacing: CGFloat = 0
    private let columns = [NSGridColumn(), NSGridColumn()]
    open func column(at index: Int) -> NSGridColumn { columns[index] }
}

open class NSAlert: NSObject {
    open var messageText: String = ""
    open var informativeText: String = ""
    public override init() { super.init() }
    public init(error: Error) { super.init() }
    @discardableResult
    open func addButton(withTitle title: String) -> NSButton { NSButton() }
    open func beginSheetModal(for window: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        handler?(.alertSecondButtonReturn)
    }
    open func runModal() -> NSApplication.ModalResponse { .alertSecondButtonReturn }
}

open class NSSavePanel: NSObject {
    open var title: String = ""
    open var prompt: String = ""
    open var nameFieldStringValue: String = ""
    open var directoryURL: URL?
    open var canCreateDirectories: Bool = false
    open var isExtensionHidden: Bool = false
    open var allowedContentTypes: [UTType] = []
    open var accessoryView: NSView?
    open var url: URL?
    public override init() { super.init() }
    open func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        handler(.cancel)
    }
    open func runModal() -> NSApplication.ModalResponse { .cancel }
}

open class NSOpenPanel: NSSavePanel {
    open var allowsMultipleSelection: Bool = false
    open var canChooseDirectories: Bool = false
    open var canChooseFiles: Bool = true
    open var urls: [URL] = []
}

open class NSMenuItem: NSObject {
    open var title: String = ""
    open var action: Selector?
    open var tag: Int = 0
    public override init() { super.init() }
}

public protocol NSMenuItemValidation: NSObjectProtocol {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
}

public enum NSSound {
    public static func beep() {}
}

open class NSWorkspace: NSObject {
    public static let shared = NSWorkspace()
    open func activateFileViewerSelecting(_ fileURLs: [URL]) {}
    @discardableResult
    open func open(_ url: URL) -> Bool { false }
}
