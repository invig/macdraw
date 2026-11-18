import AppKit
import UniformTypeIdentifiers

/// Options for File > Export, remembered between exports.
struct ExportOptions: Codable {
    enum Format: String, Codable { case png, svg }
    var format: Format = .png
    var scale = 2
    var background = true
    var darkMode = false
    var embedScene = false
    var selectionOnly = false

    private static let key = "ExportOptions"

    static func load() -> ExportOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let options = try? JSONDecoder().decode(ExportOptions.self, from: data) else { return ExportOptions() }
        return options
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// Shape passed to window.macdraw.exportImage(opts).
    var scriptValue: [String: Any] {
        ["format": format.rawValue, "scale": scale, "background": background, "darkMode": darkMode,
         "embedScene": embedScene, "selectionOnly": selectionOnly]
    }

    var contentType: UTType { format == .png ? .png : .svg }
}

/// Save panel with an options accessory (format, scale, background, …), like Preview's export.
final class ExportPanel: NSObject {
    let panel = NSSavePanel()
    private(set) var options: ExportOptions

    private let formatPopup = NSPopUpButton()
    private let scalePopup = NSPopUpButton()
    private let backgroundBox = NSButton(checkboxWithTitle: "Background", target: nil, action: nil)
    private let darkBox = NSButton(checkboxWithTitle: "Dark mode", target: nil, action: nil)
    private let embedBox = NSButton(checkboxWithTitle: "Embed scene (re-editable in Excalidraw)", target: nil, action: nil)
    private let selectionBox = NSButton(checkboxWithTitle: "Selected shapes only", target: nil, action: nil)

    init(format: ExportOptions.Format?, hasSelection: Bool, baseName: String, directory: URL?) {
        var options = ExportOptions.load()
        if let format { options.format = format }
        if !hasSelection { options.selectionOnly = false }
        self.options = options
        super.init()

        formatPopup.addItems(withTitles: ["PNG", "SVG"])
        formatPopup.selectItem(at: options.format == .png ? 0 : 1)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)

        scalePopup.addItems(withTitles: ["1×", "2×", "3×", "4×"])
        scalePopup.selectItem(at: max(0, min(3, options.scale - 1)))

        backgroundBox.state = options.background ? .on : .off
        darkBox.state = options.darkMode ? .on : .off
        embedBox.state = options.embedScene ? .on : .off
        selectionBox.state = options.selectionOnly ? .on : .off
        selectionBox.isEnabled = hasSelection

        panel.title = "Export"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [options.contentType]
        panel.nameFieldStringValue = baseName
        panel.directoryURL = directory
        panel.accessoryView = makeAccessory()
        updateEnabledState()
    }

    /// Reads the controls back into `options` and remembers them.
    func commit() -> ExportOptions {
        options.format = formatPopup.indexOfSelectedItem == 0 ? .png : .svg
        options.scale = scalePopup.indexOfSelectedItem + 1
        options.background = backgroundBox.state == .on
        options.darkMode = darkBox.state == .on
        options.embedScene = embedBox.state == .on
        options.selectionOnly = selectionBox.isEnabled && selectionBox.state == .on
        options.save()
        return options
    }

    @objc private func formatChanged() {
        options.format = formatPopup.indexOfSelectedItem == 0 ? .png : .svg
        panel.allowedContentTypes = [options.contentType]
        updateEnabledState()
    }

    private func updateEnabledState() {
        scalePopup.isEnabled = options.format == .png  // SVG is resolution-independent
    }

    private func makeAccessory() -> NSView {
        func row(_ label: String, _ control: NSView) -> [NSView] {
            let text = NSTextField(labelWithString: label)
            text.alignment = .right
            return [text, control]
        }
        let grid = NSGridView(views: [
            row("Format:", formatPopup),
            row("Scale:", scalePopup),
            [NSGridCell.emptyContentView, backgroundBox],
            [NSGridCell.emptyContentView, darkBox],
            [NSGridCell.emptyContentView, embedBox],
            [NSGridCell.emptyContentView, selectionBox],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
        ])
        container.frame.size = container.fittingSize
        return container
    }
}
