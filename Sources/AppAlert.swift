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
    /// Whether the app is the active one; a test replaces it.
    static var appIsActive: @MainActor () -> Bool = { NSApp?.isActive == true }
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
    private(set) var buttonViews: [GlassChoiceButton] = []
    /// The glass plates the buttons sit on: the trailing pair, then a lone third button at the leading edge.
    private(set) var actionPlates: [GlassSurfaceView] = []
    /// Asked when a button is pressed (not for Escape or a dismissal): a message keeps the sheet open and shows it under the accessory
    /// as "Error: …"; nil lets the answer through. A prompt uses it so a wrong entry is explained instead of closing the sheet.
    var validator: ((_ buttonIndex: Int) -> String?)?
    /// The inline error line, once one has been shown.
    private(set) var errorLabel: NSTextField?
    private var layoutInset: CGFloat = 0, layoutGap: CGFloat = 0
    private(set) var response: NSApplication.ModalResponse?
    private weak var host: NSWindow?
    private var completion: (@MainActor (NSApplication.ModalResponse) -> Void)?
    private var presentedAsSheet = false
    /// Closing the panel or the window it hangs from ends the alert; removed as soon as it has been answered.
    private var closeObservers: [NSObjectProtocol] = []

    init(title: String, message: String = "", buttons: [Button] = [Button(title: "OK")], accessoryView: NSView? = nil) {
        typealias Typography = DesignTokens.Typography
        precondition(!buttons.isEmpty && buttons.count <= 3, "An alert has one to three buttons")
        self.title = title
        self.message = message
        self.buttons = buttons
        self.accessoryView = accessoryView
        let inset = DesignTokens.Space.s5, gap = DesignTokens.Space.s4, spacing = DesignTokens.Space.s3
        layoutInset = inset; layoutGap = gap
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

        // The sheet's buttons are the same capsule commands as the Resize and Destination sheets: a 36 pt glass choice button on an action plate.
        for (index, spec) in buttons.enumerated() {
            let button = GlassChoiceButton(title: spec.title, kind: .command, layout: .segment)
            button.target = self
            button.action = #selector(pressed(_:))
            button.tag = index
            button.accessibility = .live
            button.minimumWidth = Self.minimumButtonWidth
            // The first button is the default and the only tinted one, unless it is the destructive choice.
            button.isPrimary = index == 0 && spec.role != .destructive
            button.hasDestructiveAction = spec.role == .destructive
            // The system does not paint a destructive control, so the label carries the warning colour (with its words).
            if spec.role == .destructive { button.titleColorOverride = DesignTokens.Palette.feedbackError }
            button.setAccessibilityLabel(spec.title)
            if index == 0 { button.keyEquivalent = "\r" }
            else if spec.answersEscape { button.keyEquivalent = "\u{1b}" }
            else if spec.answersCommandD { button.keyEquivalent = "d"; button.keyEquivalentModifierMask = .command }
            button.frame.size = button.intrinsicContentSize
            buttonViews.append(button)
        }
        // One action plate on the trailing edge (first button rightmost); a third button stands apart on a plate of its own at the leading edge.
        let trailingPlate = GlassChrome.plate(Array(buttonViews.prefix(2).reversed()), identifier: "AppAlertActionsPlate", accessibility: .live)
        actionPlates = [trailingPlate]
        if buttonViews.count > 2 {
            actionPlates.append(GlassChrome.plate([buttonViews[2]], identifier: "AppAlertLeadingPlate", accessibility: .live))
        }
        for plate in actionPlates { plate.layoutSubtreeIfNeeded(); plate.frame.size = plate.fittingSize }

        // The sheet is as wide as its buttons need, never narrower than the standard width.
        let buttonRow = actionPlates.reduce(0) { $0 + $1.frame.width } + CGFloat(actionPlates.count - 1) * spacing
        let width = max(Self.width, buttonRow + 2 * inset)
        let inner = width - 2 * inset
        for field in [titleLabel, messageLabel] { field.preferredMaxLayoutWidth = inner }
        func height(_ field: NSTextField) -> CGFloat {
            field.stringValue.isEmpty ? 0 : ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: .greatestFiniteMagnitude)).height ?? 0)
        }
        let buttonHeight = actionPlates.map(\.frame.height).max() ?? DesignTokens.Size.control
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
        // The trailing plate holds the first two buttons; a third stands apart at the leading edge, as in NSAlert.
        actionPlates[0].frame.origin = NSPoint(x: width - inset - actionPlates[0].frame.width, y: inset)
        if actionPlates.count > 1 { actionPlates[1].frame.origin = NSPoint(x: inset, y: inset) }
        for plate in actionPlates { content.addSubview(plate) }
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = DesignTokens.Palette.Surface.sheet
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
            watchForClose(of: [parent, panel])
            // Whoever ends the sheet (endSheet, a window close) answers it; only a button used to.
            parent.beginSheet(panel) { [weak self] _ in self?.endedWithoutAnswer() }
            // A sheet takes the keys only when its parent had them: a question hung from History while the editor was key left Return and
            // Command-D going to the wrong window (F-J5-002). It is the question now, so it takes them.
            if Self.appIsActive() { panel.makeKey() }
        } else {
            watchForClose(of: [panel])
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

    @objc private func pressed(_ sender: NSButton) {
        if let message = validator?(sender.tag) {
            showInlineError(message)
            if let field = accessoryView as? NSTextField { panel.makeFirstResponder(field); field.selectText(nil) }
            return
        }
        dismiss(withButton: sender.tag)
    }

    /// Shows (or replaces) the "Error: …" line under the accessory and grows the sheet to hold it, its top edge fixed. Assistive technology is told.
    func showInlineError(_ message: String) {
        let text = message.hasPrefix("Error:") ? message : "Error: " + message
        guard let content = panel.contentView else { return }
        let inner = content.frame.width - 2 * layoutInset
        let field: NSTextField
        if let existing = errorLabel { field = existing } else {
            field = NSTextField(wrappingLabelWithString: text)
            field.font = DesignTokens.Typography.font(.body); field.textColor = DesignTokens.Palette.feedbackError
            field.isSelectable = false; field.preferredMaxLayoutWidth = inner
            field.setAccessibilityRole(.staticText)
            errorLabel = field
        }
        field.stringValue = text; field.setAccessibilityLabel(text)
        let height = ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: .greatestFiniteMagnitude)).height ?? 0)
        let isNew = field.superview == nil
        let growth = isNew ? height + layoutGap : height - field.frame.height
        // A new line sits where the accessory's bottom edge was; a taller or shorter one keeps its bottom edge.
        let y = isNew ? (accessoryView ?? messageLabel).frame.minY : field.frame.minY
        if growth != 0 {
            let buttonIDs = Set(actionPlates.map(ObjectIdentifier.init))
            for view in content.subviews where view !== field && !buttonIDs.contains(ObjectIdentifier(view)) { view.frame.origin.y += growth }
            let top = panel.frame.maxY
            content.frame.size.height += growth
            panel.setContentSize(content.frame.size)
            var frame = panel.frame; frame.origin.y = top - frame.height
            panel.setFrame(frame, display: true)
        }
        field.frame = NSRect(x: layoutInset, y: y, width: inner, height: height)
        if isNew { content.addSubview(field) }
        Announcer.announce(text, priority: .high)
    }

    /// What Escape does: the Cancel button, or the only button.
    func cancel() {
        if let index = buttons.firstIndex(where: \.answersEscape) { dismiss(withButton: index) }
        else if buttons.count == 1 { dismiss(withButton: 0) }
    }

    /// What the alert answers when it ends with no button chosen: Cancel, else the only button, else plain `.cancel`
    /// (an alert with no Cancel button never chooses for the user; callers treat anything but the first button as "no").
    var unansweredResponse: NSApplication.ModalResponse {
        let index = buttons.firstIndex(where: \.answersEscape) ?? (buttons.count == 1 ? 0 : nil)
        return index.map { NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + $0) } ?? .cancel
    }

    private func endedWithoutAnswer() { finish(unansweredResponse) }

    private func watchForClose(of windows: [NSWindow]) {
        closeObservers = windows.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.endedWithoutAnswer() }
            }
        }
    }

    private func finish(_ answer: NSApplication.ModalResponse) {
        guard response == nil else { return }
        response = answer
        for observer in closeObservers { NotificationCenter.default.removeObserver(observer) }
        closeObservers = []
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
    /// How many times the panel was asked to become key.
    private(set) var keyRequests = 0
    override func makeKey() { keyRequests += 1; super.makeKey() }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
