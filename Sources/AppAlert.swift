import AppKit

/// The app's own alert. NSAlert draws its text at a size the app cannot change, so every alert the app raises is this
/// panel instead: title in `headline`, message and buttons in `body` (20 pt), buttons at least 36 pt tall.
/// It keeps NSAlert's conventions: the first button is the default (Return), a Cancel button answers Escape,
/// "Don't Save" answers Command-D, and the answer is the same `alertFirstButtonReturn + index` response.
/// It is a sheet on the document window, so the app stays responsive and the window it belongs to stays in view.
@MainActor
final class AppAlert: NSObject {
    enum Role { case normal, cancel, destructive }
    struct Button: Equatable {
        var title: String
        var role: Role = .normal
        /// Cancel answers Escape. A button titled "Cancel" is one without being told, as in NSAlert.
        var answersEscape: Bool { role == .cancel || title == "Cancel" }
        /// "Don't Save" answers Command-D, as in NSAlert.
        var answersCommandD: Bool { title == "Don\u{2019}t Save" || title == "Don't Save" }
    }

    static let width: CGFloat = 560
    static let minimumButtonWidth: CGFloat = 96

    /// Test seam: replaces showing the panel. The closure must call `completion` with the response (now or later).
    static var presenter: (@MainActor (AppAlert, NSWindow?, @escaping @MainActor (NSApplication.ModalResponse) -> Void) -> Void)?
    /// Whether a window can carry a sheet right now: on screen and not in the Dock.
    static var hostIsPresentable: @MainActor (NSWindow) -> Bool = { $0.isVisible && !$0.isMiniaturized }
    /// Alerts on screen; the panel's buttons only hold their target weakly.
    private static var live: [AppAlert] = []
    /// The alerts on screen now, oldest first.
    static var presentedAlerts: [AppAlert] { live }

    let title: String
    let message: String
    let buttons: [Button]
    let accessoryView: NSView?
    let panel: AppAlertPanel
    let titleLabel: NSTextField
    let messageLabel: NSTextField
    private(set) var buttonViews: [NSButton] = []
    private(set) var response: NSApplication.ModalResponse?
    private weak var host: NSWindow?
    private var completion: (@MainActor (NSApplication.ModalResponse) -> Void)?
    private var presentedAsSheet = false

    init(title: String, message: String = "", buttons: [Button] = [Button(title: "OK")], accessoryView: NSView? = nil) {
        typealias Typography = DesignTokens.Typography
        precondition(!buttons.isEmpty && buttons.count <= 3, "An alert has one to three buttons")
        self.title = title
        self.message = message
        self.buttons = buttons
        self.accessoryView = accessoryView
        let inset = DesignTokens.Space.s5, gap = DesignTokens.Space.s4, spacing = DesignTokens.Space.s3
        func label(_ text: String, _ style: Typography.Style, lines: Int) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = Typography.font(style)
            field.textColor = DesignTokens.Palette.Text.primary
            field.maximumNumberOfLines = lines
            // Word wrap, then an ellipsis on the last allowed line; a truncating break mode would keep it to one line.
            field.lineBreakMode = .byWordWrapping
            (field.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
            field.isSelectable = false
            return field
        }
        titleLabel = label(title, .headline, lines: 4)
        messageLabel = label(message, .body, lines: 12)
        panel = AppAlertPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        super.init()

        for (index, spec) in buttons.enumerated() {
            let button = NSButton(title: spec.title, target: self, action: #selector(pressed(_:)))
            button.bezelStyle = .push
            button.tag = index
            Typography.apply(.body, to: button)
            button.sizeToFit()
            button.frame.size = NSSize(width: max(Self.minimumButtonWidth, button.frame.width + 2 * DesignTokens.Space.s2),
                                       height: max(button.frame.height, DesignTokens.Size.control))
            button.hasDestructiveAction = spec.role == .destructive
            button.setAccessibilityLabel(spec.title)
            if index == 0 { button.keyEquivalent = "\r" }
            else if spec.answersEscape { button.keyEquivalent = "\u{1b}" }
            else if spec.answersCommandD { button.keyEquivalent = "d"; button.keyEquivalentModifierMask = .command }
            buttonViews.append(button)
        }

        // The sheet is as wide as its buttons need, never narrower than the standard width.
        let buttonRow = buttonViews.reduce(0) { $0 + $1.frame.width } + CGFloat(buttons.count - 1) * spacing
        let width = max(Self.width, buttonRow + 2 * inset)
        let inner = width - 2 * inset
        for field in [titleLabel, messageLabel] { field.preferredMaxLayoutWidth = inner }
        func height(_ field: NSTextField) -> CGFloat {
            field.stringValue.isEmpty ? 0 : ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: .greatestFiniteMagnitude)).height ?? 0)
        }
        let buttonHeight = buttonViews.map(\.frame.height).max() ?? DesignTokens.Size.control
        let accessoryHeight = accessoryView?.frame.height ?? 0
        var stack: [CGFloat] = [height(titleLabel)]
        if height(messageLabel) > 0 { stack.append(height(messageLabel)) }
        if accessoryHeight > 0 { stack.append(accessoryHeight) }
        let total = inset + stack.reduce(0, +) + CGFloat(stack.count) * gap + buttonHeight + inset
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: total))
        // Top-down layout in AppKit's bottom-up coordinates.
        var y = total - inset
        y -= height(titleLabel); titleLabel.frame = NSRect(x: inset, y: y, width: inner, height: height(titleLabel)); y -= gap
        content.addSubview(titleLabel)
        if height(messageLabel) > 0 {
            y -= height(messageLabel); messageLabel.frame = NSRect(x: inset, y: y, width: inner, height: height(messageLabel)); y -= gap
            content.addSubview(messageLabel)
        }
        if let accessoryView {
            y -= accessoryHeight
            accessoryView.frame = NSRect(x: inset, y: y, width: min(accessoryView.frame.width, inner), height: accessoryHeight); y -= gap
            content.addSubview(accessoryView)
        }
        // First button rightmost, the second to its left; a third stands apart at the leading edge, as in NSAlert.
        var x = width - inset
        for (index, button) in buttonViews.enumerated() {
            if index == 2 { button.frame.origin = NSPoint(x: inset, y: inset) }
            else { x -= button.frame.width; button.frame.origin = NSPoint(x: x, y: inset); x -= spacing }
            content.addSubview(button)
        }
        panel.isReleasedWhenClosed = false
        panel.title = DesignTokens.Brand.name
        let size = content.frame.size // Assigning the content view resizes it to the (still empty) window.
        panel.contentView = content
        panel.setContentSize(size)
        panel.defaultButtonCell = buttonViews[0].cell as? NSButtonCell
        panel.initialFirstResponder = (accessoryView as? NSTextField) ?? buttonViews[0]
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.setAccessibilityLabel(title)
        panel.setAccessibilityHelp(message.isEmpty ? nil : message)
        messageLabel.setAccessibilityLabel(message)
        titleLabel.setAccessibilityLabel(title)
    }

    /// What NSAlert(error:) shows: the description as the title, the recovery suggestion as the message.
    convenience init(error: Error) {
        self.init(title: error.localizedDescription, message: (error as NSError).localizedRecoverySuggestion ?? "")
    }

    // MARK: presenting

    /// The window to hang the sheet from: the topmost sheet already on `host`, so alerts stack instead of queueing unseen.
    static func sheetParent(of host: NSWindow?) -> NSWindow? {
        guard var parent = host, hostIsPresentable(parent) else { return nil }
        while let attached = parent.attachedSheet { parent = attached }
        return parent
    }

    /// Shows the alert as a sheet on `host` (or as a panel of its own when there is no window to hang it from) and reports the
    /// response once. Never blocks.
    func present(on host: NSWindow?, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        guard response == nil, self.completion == nil else { return }
        if let presenter = Self.presenter {
            self.completion = completion
            presenter(self, host) { [weak self] answer in self?.finish(answer) }
            return
        }
        self.completion = completion
        Self.live.append(self)
        if let parent = Self.sheetParent(of: host) {
            self.host = parent
            presentedAsSheet = true
            panel.setAccessibilityRole(.sheet)
            parent.beginSheet(panel)
        } else {
            panel.setAccessibilityRole(.window)
            panel.setAccessibilitySubrole(.dialog)
            panel.level = .modalPanel
            panel.center()
            NSApplication.shared.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
        panel.makeFirstResponder(panel.initialFirstResponder)
        if let field = panel.initialFirstResponder as? NSTextField { field.selectText(nil) }
    }

    /// Ends the alert as if the button at `index` had been pressed.
    func dismiss(withButton index: Int) {
        guard buttons.indices.contains(index) else { return }
        finish(NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index))
    }

    @objc private func pressed(_ sender: NSButton) { dismiss(withButton: sender.tag) }

    /// What Escape does: the Cancel button, or the only button.
    func cancel() {
        if let index = buttons.firstIndex(where: \.answersEscape) { dismiss(withButton: index) }
        else if buttons.count == 1 { dismiss(withButton: 0) }
    }

    private func finish(_ answer: NSApplication.ModalResponse) {
        guard response == nil else { return }
        response = answer
        if presentedAsSheet, let host, host.attachedSheet === panel { host.endSheet(panel) }
        panel.orderOut(nil)
        Self.live.removeAll { $0 === self }
        let done = completion
        completion = nil
        done?(answer)
    }
}

/// Escape reaches a panel with no Cancel button (an alert with one OK) through `cancelOperation`.
final class AppAlertPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
