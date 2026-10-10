import AppKit

private typealias Typography = DesignTokens.Typography

/// A utility window that closes on Escape and Command-W, whoever has focus inside it.
@MainActor
class DismissibleWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            close(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The license text in a window of its own, so reading it never leaves the app or touches the network.
@MainActor
final class LicenseWindow: DismissibleWindow {
    let textView = NSTextView()

    init(text: String) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560), styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: true)
        title = "MIT License"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 480, height: 360)
        textView.isEditable = false; textView.isSelectable = true
        textView.font = Typography.font(.body)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.setAccessibilityLabel("MIT License text")
        let scroll = NSScrollView(frame: contentRect(forFrameRect: frame))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = textView
        contentView = scroll
        center()
    }
}

/// The app-owned About window: icon, name, version and build, one credit line and the license link.
/// Everything readable is body size or larger; the title bar text is the system's.
@MainActor
final class AboutWindow: DismissibleWindow {
    static let credit = "Capture, annotate, share."
    static let licenseLinkTitle = "MIT License"
    static let missingLicense = "The license text is not bundled in this build. OpenSnap is released under the MIT License."

    let nameLabel: NSTextField, versionLabel: NSTextField, creditLabel: NSTextField
    let licenseButton: NSButton
    let iconView: NSImageView
    private let licenseText: @MainActor () -> String
    private(set) var licenseWindow: LicenseWindow?

    /// "Version 0.3.0 (build 3)", from the bundle's Info.plist values.
    static func versionLine(_ info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String, build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "Version \(version) (build \(build))"
        case let (version?, nil): return "Version \(version)"
        default: return "Development build"
        }
    }

    /// LICENSE.txt in the app's Resources; `nil` outside a built bundle.
    static func bundledLicenseText() -> String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return missingLicense }
        return text
    }

    init(icon: NSImage?, info: [String: Any]?, licenseText: @escaping @MainActor () -> String = AboutWindow.bundledLicenseText) {
        self.licenseText = licenseText
        iconView = NSImageView(image: icon ?? NSImage())
        nameLabel = NSTextField(labelWithString: DesignTokens.Brand.name)
        versionLabel = NSTextField(labelWithString: Self.versionLine(info))
        creditLabel = NSTextField(labelWithString: Self.credit)
        licenseButton = NSButton(title: "", target: nil, action: nil)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        title = "About " + DesignTokens.Brand.name
        titleVisibility = .hidden; titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        for button in [.miniaturizeButton, .zoomButton] as [NSWindow.ButtonType] { standardWindowButton(button)?.isHidden = true }

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        nameLabel.font = Typography.font(.title)
        for label in [versionLabel, creditLabel] { label.font = Typography.font(.body); label.textColor = .secondaryLabelColor }
        nameLabel.setAccessibilityIdentifier("about.name"); versionLabel.setAccessibilityIdentifier("about.version")
        creditLabel.setAccessibilityIdentifier("about.credit")

        licenseButton.isBordered = false
        licenseButton.font = Typography.font(.body)
        licenseButton.attributedTitle = NSAttributedString(string: Self.licenseLinkTitle, attributes: [
            .font: Typography.font(.body), .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue])
        licenseButton.target = self; licenseButton.action = #selector(showLicense)
        licenseButton.setAccessibilityLabel(Self.licenseLinkTitle)
        licenseButton.toolTip = "Read the license text"

        let stack = NSStackView(views: [iconView, nameLabel, versionLabel, creditLabel, licenseButton])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 8
        stack.setCustomSpacing(12, after: iconView)
        stack.setCustomSpacing(16, after: creditLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 300))
        content.addSubview(stack)
        contentView = content
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 96), iconView.heightAnchor.constraint(equalToConstant: 96),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 36),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
        ])
        content.layoutSubtreeIfNeeded()
        center()
    }

    /// The license window for the current text, kept so a second click brings the same window forward.
    func makeLicenseWindow() -> LicenseWindow {
        if let existing = licenseWindow { return existing }
        let made = LicenseWindow(text: licenseText())
        licenseWindow = made
        return made
    }

    @objc func showLicense() { makeLicenseWindow().makeKeyAndOrderFront(nil) }

    override func close() {
        licenseWindow?.close()
        super.close()
    }
}
