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

/// The license (or third-party notice) text in a window of its own, so reading it never leaves the app or touches the network.
@MainActor
final class LicenseWindow: DismissibleWindow {
    let textView = NSTextView()

    /// The file wraps its paragraphs at about 80 columns; the window wraps them at its own width. Lines of one paragraph are joined with
    /// a space. Blank lines, indented lines (a block that is laid out on purpose), underlines of a title and the title above one all stay.
    nonisolated static func reflowed(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        func isRule(_ line: String) -> Bool { line.count >= 3 && line.allSatisfy { $0 == "-" || $0 == "=" } }
        func isProse(_ line: String) -> Bool { !line.isEmpty && !(line.first?.isWhitespace ?? true) && !isRule(line) }
        var result: [String] = []
        var takesContinuation = false // the last line written is prose and is not a title, so the next prose line belongs to it
        for (index, line) in lines.enumerated() {
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            if takesContinuation, isProse(line) { result[result.count - 1] += " " + line } else { result.append(line) }
            takesContinuation = isProse(line) && !isRule(next)
        }
        return result.joined(separator: "\n")
    }

    init(text: String, title: String = "MIT License") {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560), styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: true)
        self.title = title
        isReleasedWhenClosed = false
        minSize = NSSize(width: 480, height: 360)
        textView.isEditable = false; textView.isSelectable = true
        textView.font = Typography.font(.body)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = Self.reflowed(text)
        textView.setAccessibilityLabel(title + " text")
        let scroll = NSScrollView(frame: contentRect(forFrameRect: frame))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = textView
        contentView = scroll
        center()
    }
}

/// The app-owned About window: icon, name, version and build, one credit line, the license link and the third-party notices link.
/// Everything readable is body size or larger; the title bar text is the system's.
@MainActor
final class AboutWindow: DismissibleWindow {
    static let credit = "Capture, annotate, share."
    static let licenseLinkTitle = "MIT License"
    static let missingLicense = "The license text is not bundled in this build. OpenSnap is released under the MIT License."
    static let noticesLinkTitle = "Third-party notices"
    static let noticesWindowTitle = "Third-Party Notices"
    static let missingNotices = "The notices are not bundled in this build. Icons are Font Awesome Free 7.3.1 by Fonticons, Inc., licensed CC BY 4.0 (fontawesome.com/license/free)."

    let nameLabel: NSTextField, versionLabel: NSTextField, creditLabel: NSTextField
    let licenseButton: NSButton, noticesButton: NSButton
    let iconView: NSImageView
    private let licenseText: @MainActor () -> String, noticesText: @MainActor () -> String
    private(set) var licenseWindow: LicenseWindow?, noticesWindow: LicenseWindow?

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

    /// THIRD_PARTY_NOTICES.txt in the app's Resources; `nil` outside a built bundle.
    static func bundledNoticesText() -> String {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return missingNotices }
        return text
    }

    init(icon: NSImage?, info: [String: Any]?, licenseText: @escaping @MainActor () -> String = AboutWindow.bundledLicenseText,
         noticesText: @escaping @MainActor () -> String = AboutWindow.bundledNoticesText) {
        self.licenseText = licenseText
        self.noticesText = noticesText
        iconView = NSImageView(image: icon ?? NSImage())
        nameLabel = NSTextField(labelWithString: DesignTokens.Brand.name)
        versionLabel = NSTextField(labelWithString: Self.versionLine(info))
        creditLabel = NSTextField(labelWithString: Self.credit)
        licenseButton = NSButton(title: "", target: nil, action: nil)
        noticesButton = NSButton(title: "", target: nil, action: nil)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        title = "About " + DesignTokens.Brand.name
        // The title stays visible: a window with no title text has no name for a person to find it by (Window menu, Mission Control).
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        for button in [.miniaturizeButton, .zoomButton] as [NSWindow.ButtonType] { standardWindowButton(button)?.isHidden = true }

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false); iconView.setAccessibilityIdentifier("decorative.about-icon")  // the name beside it says it all
        nameLabel.font = Typography.font(.title)
        for label in [versionLabel, creditLabel] { label.font = Typography.font(.body); label.textColor = .secondaryLabelColor }
        nameLabel.setAccessibilityIdentifier("about.name"); versionLabel.setAccessibilityIdentifier("about.version")
        creditLabel.setAccessibilityIdentifier("about.credit")

        for (button, title) in [(licenseButton, Self.licenseLinkTitle), (noticesButton, Self.noticesLinkTitle)] {
            button.isBordered = false
            button.font = Typography.font(.body)
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: Typography.font(.body), .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue])
            button.setAccessibilityLabel(title)
        }
        licenseButton.target = self; licenseButton.action = #selector(showLicense)
        licenseButton.toolTip = "Read the license text"
        noticesButton.target = self; noticesButton.action = #selector(showNotices)
        noticesButton.toolTip = "Read the third-party notices"

        let stack = NSStackView(views: [iconView, nameLabel, versionLabel, creditLabel, licenseButton, noticesButton])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 8
        stack.setCustomSpacing(12, after: iconView)
        stack.setCustomSpacing(16, after: creditLabel)
        stack.setCustomSpacing(4, after: licenseButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 340))
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

    /// The notices window, kept like the license window so a second click brings the same one forward.
    func makeNoticesWindow() -> LicenseWindow {
        if let existing = noticesWindow { return existing }
        let made = LicenseWindow(text: noticesText(), title: Self.noticesWindowTitle)
        noticesWindow = made
        return made
    }

    @objc func showLicense() { makeLicenseWindow().makeKeyAndOrderFront(nil) }
    @objc func showNotices() { makeNoticesWindow().makeKeyAndOrderFront(nil) }

    override func close() {
        licenseWindow?.close()
        noticesWindow?.close()
        super.close()
    }
}
