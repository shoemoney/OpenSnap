import AppKit

/// The formats the Export panel offers, in the order it lists them (T9). The encoder still reads GIF and BMP (ImageExport), and Save As
/// writes the .opensnap document; neither is an export choice any more, and a stored "gif", "bmp" or "opensnap" choice falls back to PNG.
enum ExportAccessoryFormat: String, CaseIterable {
    case png, jpeg, pdf, tiff, svg

    var title: String { self == .jpeg ? "JPG" : rawValue.uppercased() }

    static func validated(_ value: String) -> ExportAccessoryFormat {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "jpg": return .jpeg
        case "tif": return .tiff
        case let value: return ExportAccessoryFormat(rawValue: value) ?? .png
        }
    }
}

/// Value validation and selection persistence independent of any exporter or preferences.
struct ExportAccessoryOptions: Equatable {
    // File export starts at 70%; the separate drag-export default is 60%.
    static let defaultJPEGQuality = 0.7
    static let minimumJPEGQuality = 0.1
    static let maximumJPEGQuality = 1.0
    static let jpegTickCount = 10

    private(set) var selectedFormat: ExportAccessoryFormat
    private(set) var originalSize: Bool
    private(set) var jpegQuality: Double

    init(format: String = "png", originalSize: Bool = false,
         jpegQuality: Double = defaultJPEGQuality) {
        selectedFormat = ExportAccessoryFormat.validated(format)
        self.originalSize = originalSize
        self.jpegQuality = Self.validatedQuality(jpegQuality)
    }

    var format: String { selectedFormat.rawValue }
    var jpegControlsEnabled: Bool { selectedFormat == .jpeg }
    var qualityLabel: String { "JPEG quality: \(Int((jpegQuality * 100).rounded()))%" }

    static func validatedQuality(_ quality: Double) -> Double {
        guard quality.isFinite else { return defaultJPEGQuality }
        let bounded = min(maximumJPEGQuality, max(minimumJPEGQuality, quality))
        return (bounded * 10).rounded() / 10
    }

    @discardableResult
    mutating func setFormat(_ value: String) -> Bool {
        let format = ExportAccessoryFormat.validated(value)
        guard selectedFormat != format else { return false }
        selectedFormat = format
        return true
    }

    @discardableResult
    mutating func setOriginalSize(_ value: Bool) -> Bool {
        guard originalSize != value else { return false }
        originalSize = value
        return true
    }

    @discardableResult
    mutating func setJPEGQuality(_ value: Double) -> Bool {
        let quality = Self.validatedQuality(value)
        guard jpegQuality != quality else { return false }
        jpegQuality = quality
        return true
    }
}

/// Displays only caller-supplied preview results; never estimates encoded bytes.
struct ExportAccessoryPreview: Equatable {
    private(set) var byteCount: Int?
    private(set) var size: CGSize?

    init(byteCount: Int? = nil, size: CGSize? = nil) {
        self.byteCount = byteCount.flatMap { $0 >= 0 ? $0 : nil }
        if let size, let width = Int(exactly: size.width), let height = Int(exactly: size.height),
           width > 0, height > 0 {
            self.size = size
        } else {
            self.size = nil
        }
    }

    var dimensionsLabel: String {
        guard let size, let width = Int(exactly: size.width), let height = Int(exactly: size.height) else {
            return "Dimensions: Not available"
        }
        return "Dimensions: " + PixelSizeText.text(width: width, height: height) + " pixels"
    }

    var byteCountLabel: String {
        guard let byteCount else { return "Encoded size: Not available" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.includesActualByteCount = true
        return "Encoded size: " + formatter.string(fromByteCount: Int64(byteCount))
    }
}

@MainActor
final class ExportAccessory: NSObject {
    private var options: ExportAccessoryOptions
    private(set) var preview = ExportAccessoryPreview()
    var onChange: () -> Void
    private var contentView: NSView?
    private var formatPopup: NSPopUpButton?
    private var qualityLabel: NSTextField?
    private var originalSizeCheckbox: NSButton?
    private var dimensionsLabel: NSTextField?
    private var byteCountLabel: NSTextField?

    init(format: String = "png", originalSize: Bool = false, jpegQuality: Double = 0.7,
         onChange: @escaping () -> Void = {}) {
        options = ExportAccessoryOptions(format: format, originalSize: originalSize, jpegQuality: jpegQuality)
        self.onChange = onChange
        super.init()
    }

    /// Assign this stable view to NSSavePanel.accessoryView. UI creation is lazy.
    var view: NSView {
        if let contentView { return contentView }
        let content = buildContent()
        contentView = content
        return content
    }

    /// Canonical lowercase format; jpg/tif inputs normalize to jpeg/tiff.
    var format: String {
        get { options.format }
        set { optionsChanged(options.setFormat(newValue)) }
    }

    var originalSize: Bool {
        get { options.originalSize }
        set { optionsChanged(options.setOriginalSize(newValue)) }
    }

    /// Finite 0.1...1.0 value, snapped to ten 10% steps.
    var jpegQuality: Double {
        get { options.jpegQuality }
        set { optionsChanged(options.setJPEGQuality(newValue)) }
    }

    /// When set (the app always sets it), JPG encodes at this quality and the panel states it as text.
    var fixedJPEGQuality: Double? { didSet { render() } }
    var effectiveJPEGQuality: Double { fixedJPEGQuality ?? options.jpegQuality }

    /// Whether "Export at original size" has anything to choose between: false when the picture is the size it is shown at, where the box
    /// would promise a difference that is not there (R4-007). Set before the view is first read.
    var offersOriginalSize = true { didSet { render() } }

    func updateByteCount(_ count: Int?, size: CGSize) {
        preview = ExportAccessoryPreview(byteCount: count, size: size)
        render()
    }

    private func optionsChanged(_ changed: Bool) {
        guard changed else { return }
        // Old bytes and dimensions describe the old options, not the new ones.
        // The callback can synchronously provide a fresh actual encoded preview.
        preview = ExportAccessoryPreview()
        render()
        onChange()
    }

    private func buildContent() -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
        let heading = label("Export options", style: .title)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = DesignTokens.Typography.font(.body)
        popup.addItems(withTitles: ExportAccessoryFormat.allCases.map(\.title))
        for (item, format) in zip(popup.itemArray, ExportAccessoryFormat.allCases) {
            item.representedObject = format.rawValue
            item.attributedTitle = NSAttributedString(string: format.title,
                attributes: [.font: DesignTokens.Typography.font(.body)])
        }
        popup.target = self
        popup.action = #selector(selectFormat(_:))
        popup.setAccessibilityLabel("Export format")
        formatPopup = popup
        let formatLabel = NSTextField(labelWithString: "Format:")
        formatLabel.font = DesignTokens.Typography.font(.body)
        formatLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let formatRow = NSStackView(views: [formatLabel, popup])
        formatRow.orientation = .horizontal
        formatRow.alignment = .centerY
        formatRow.spacing = 20

        // JPG is always written at one fixed quality, so it is a statement here, not a control.
        let quality = label(Self.qualityText(effectiveJPEGQuality))
        qualityLabel = quality

        let checkbox = NSButton(checkboxWithTitle: "Export at original size", target: self,
                                action: #selector(selectOriginalSize(_:)))
        checkbox.font = DesignTokens.Typography.font(.body)
        originalSizeCheckbox = checkbox
        let dimensions = label(preview.dimensionsLabel)
        dimensionsLabel = dimensions
        let bytes = label(preview.byteCountLabel)
        byteCountLabel = bytes
        dimensions.setAccessibilityLabel("Export dimensions")
        bytes.setAccessibilityLabel("Actual encoded file size")

        let stack = NSStackView(views: [heading, formatRow, quality, checkbox, dimensions, bytes])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            popup.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            checkbox.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            dimensions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bytes.widthAnchor.constraint(equalTo: stack.widthAnchor),
            // Reserve wrapping space for exact byte counts without shrinking text.
            bytes.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
        render()
        content.setFrameSize(NSSize(width: 600, height: stack.fittingSize.height + 40))
        stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20).isActive = true
        popup.nextKeyView = checkbox
        return content
    }

    /// "JPG quality 75%": the quality a JPG is written at, whole percent.
    static func qualityText(_ quality: Double) -> String { "JPG quality \(Int((quality * 100).rounded()))%" }

    private func label(_ text: String, style: DesignTokens.Typography.Style = .body) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = DesignTokens.Typography.font(style)
        return label
    }

    private func render() {
        // Optional controls keep property changes and preview tests UI-free.
        if let index = ExportAccessoryFormat.allCases.firstIndex(of: options.selectedFormat) {
            formatPopup?.selectItem(at: index)
        }
        // A statement about JPG has nothing to say while PNG is chosen, and a control-less line at full strength reads as a setting that does not apply.
        qualityLabel?.isEnabled = options.jpegControlsEnabled
        qualityLabel?.isHidden = !options.jpegControlsEnabled
        qualityLabel?.stringValue = Self.qualityText(effectiveJPEGQuality)
        originalSizeCheckbox?.state = options.originalSize ? .on : .off
        originalSizeCheckbox?.isHidden = !offersOriginalSize
        dimensionsLabel?.stringValue = preview.dimensionsLabel
        byteCountLabel?.stringValue = preview.byteCountLabel
    }

    @objc private func selectFormat(_ sender: NSPopUpButton) {
        guard let selected = sender.selectedItem?.representedObject as? String else { return }
        format = selected
    }

    @objc private func selectOriginalSize(_ sender: NSButton) {
        originalSize = sender.state == .on
    }
}
