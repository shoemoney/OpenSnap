import AppKit

// The Settings window: a toolbar of four tabs (General, Drawing, Capture, Upload), no Done button, every change applied at
// once. It is self-contained: the app hands it closures for the things it owns (stored preferences, the shortcut manager, the
// destination list, the destinations sheet) and it owns nothing else, so a test can build it with in-memory stand-ins.

/// Sizes and row builders shared by the four tabs, so every tab is the same aligned form grid.
@MainActor
enum SettingsLayout {
    private typealias Typography = DesignTokens.Typography
    private typealias Space = DesignTokens.Space

    static let tabTitles = ["General", "Drawing", "Capture", "Upload"]
    static let contentWidth: CGFloat = 640
    static let horizontalMargin = Space.s6, verticalMargin = Space.s5
    static let rowSpacing = Space.s4, columnSpacing = Space.s4
    /// The checkbox glyph and its gap, so a wrapped title is measured against the room it really has.
    static let checkboxIndent: CGFloat = 28

    static var gridWidth: CGFloat { contentWidth - 2 * horizontalMargin }

    /// Every row label in the window, so the widest one sets the label column of all four tabs.
    static var rowLabels: [String] {
        ["Show in:", "Snapping:", "Hints:", "Drawing precision:", "Arrow head:", "Flash:", "Destinations:"] + GlobalHotkeyForm.labelTexts()
    }
    static var labelColumnWidth: CGFloat {
        let font = Typography.font(.bodyStrong)
        return ceil(rowLabels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
    }
    static var controlColumnWidth: CGFloat { gridWidth - labelColumnWidth - columnSpacing }

    /// A row label: right-aligned in the label column, 20 pt semibold.
    static func rowLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = Typography.font(.bodyStrong); field.alignment = .right
        field.textColor = DesignTokens.Palette.Text.primary
        return field
    }

    /// Secondary text under a control, the only place the 18 pt caption is used.
    static func caption(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = Typography.font(.caption); field.textColor = DesignTokens.Palette.Text.secondary
        field.preferredMaxLayoutWidth = controlColumnWidth
        field.widthAnchor.constraint(equalToConstant: controlColumnWidth).isActive = true
        return field
    }

    static func checkbox(_ title: String, identifier: String, target: AnyObject, action: Selector, wraps: Bool = false) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: target, action: action)
        guard wraps else { configure(button, identifier: identifier); return button }
        let measured = (title as NSString).boundingRect(with: NSSize(width: controlColumnWidth - checkboxIndent, height: .greatestFiniteMagnitude),
                                                       options: .usesLineFragmentOrigin, attributes: [.font: Typography.font(.body)])
        configure(button, identifier: identifier, height: ceil(measured.height))
        button.cell?.wraps = true; button.cell?.isScrollable = false; button.cell?.lineBreakMode = .byWordWrapping
        button.widthAnchor.constraint(equalToConstant: controlColumnWidth).isActive = true
        return button
    }

    static func radio(_ title: String, tag: Int, identifier: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(radioButtonWithTitle: title, target: target, action: action)
        button.tag = tag
        configure(button, identifier: identifier)
        return button
    }

    static func pushButton(_ title: String, identifier: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        configure(button, identifier: identifier)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.Size.control).isActive = true
        return button
    }

    /// A checkbox or radio keeps its own intrinsic height, so a row's first baseline is the button's real one; a push button is at least a control tall.
    private static func configure(_ button: NSButton, identifier: String, height: CGFloat? = nil) {
        Typography.apply(.body, to: button)
        button.controlSize = .large
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        if let height { button.heightAnchor.constraint(equalToConstant: height).isActive = true }
    }

    static func choices(_ buttons: [NSButton]) -> NSStackView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal; stack.alignment = .firstBaseline; stack.spacing = Space.s4
        return stack
    }

    static func group(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = Space.s2
        return stack
    }
}

/// The values the General and Drawing tabs edit. It publishes an edit and never echoes a synchronize back as one, so a parent
/// that refreshes the form from its stored state inside `onChange` cannot recurse.
@MainActor
final class SettingsPreferencesModel {
    private(set) var state: GeneralPreferencesState
    var onChange: ((GeneralPreferencesState) -> Void)?
    private var observers: [() -> Void] = []

    init(state: GeneralPreferencesState) { self.state = Self.normalized(state) }

    static func normalized(_ state: GeneralPreferencesState) -> GeneralPreferencesState {
        var result = state
        if ![1, 2].contains(result.arrowHead) { result.arrowHead = 2 }
        if ![0, 1, 2].contains(result.statusMenu) { result.statusMenu = 0 }
        return result
    }

    func observe(_ refresh: @escaping () -> Void) { observers.append(refresh) }

    /// Refreshes the controls without delivering an edit.
    func synchronize(_ new: GeneralPreferencesState) {
        state = Self.normalized(new)
        observers.forEach { $0() }
    }

    func edit(_ change: (inout GeneralPreferencesState) -> Void) {
        change(&state)
        synchronize(state)
        onChange?(state)
    }
}

/// One tab: a fixed-width form grid pinned to the top, sized to its content.
@MainActor
class SettingsTabViewController: NSViewController {
    private(set) var grid = NSGridView()
    /// A tab whose content changed height asks the window to refit.
    var onResize: (() -> Void)?

    /// Rows of [label, control]; a row with no label uses `NSGridCell.emptyContentView`. Subclasses override.
    func makeRows() -> [[NSView]] { [] }
    /// Re-reads whatever the tab shows from its source of truth. Delivers nothing.
    func refresh() {}

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.widthAnchor.constraint(equalToConstant: SettingsLayout.contentWidth).isActive = true
        grid = NSGridView(views: makeRows())
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = SettingsLayout.rowSpacing; grid.columnSpacing = SettingsLayout.columnSpacing
        grid.column(at: 0).xPlacement = .trailing; grid.column(at: 0).width = SettingsLayout.labelColumnWidth
        grid.column(at: 1).xPlacement = .leading; grid.column(at: 1).width = SettingsLayout.controlColumnWidth
        for index in 0..<grid.numberOfRows { grid.row(at: index).rowAlignment = .firstBaseline }
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: SettingsLayout.verticalMargin),
            grid.centerXAnchor.constraint(equalTo: root.centerXAnchor)])
        view = root
    }

    /// The height the tab asks for: its grid plus the vertical margins.
    var fittingHeight: CGFloat {
        if !isViewLoaded { loadView() }
        return gridHeight
    }
    private var gridHeight: CGFloat {
        grid.layoutSubtreeIfNeeded()
        return ceil(grid.fittingSize.height + 2 * SettingsLayout.verticalMargin)
    }

    /// The tab's content changed height; the window refits. The controller sizes the window itself, so no tab sets a
    /// `preferredContentSize`: AppKit would resize the window to it the moment the tab is selected, ahead of the animation.
    func contentChanged() { onResize?() }
}

@MainActor
final class GeneralSettingsTab: SettingsTabViewController {
    let model: SettingsPreferencesModel
    private(set) var presenceButtons: [NSButton] = []
    private(set) var snapCheckbox: NSButton!, hoverHintsCheckbox: NSButton!, keyboardTipsCheckbox: NSButton!

    init(model: SettingsPreferencesModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = "General"
        model.observe { [weak self] in self?.refresh() }
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }

    override func makeRows() -> [[NSView]] {
        presenceButtons = [SettingsLayout.radio("Dock", tag: 2, identifier: "presenceDock", target: self, action: #selector(changePresence(_:))),
                           SettingsLayout.radio("Menu bar", tag: 1, identifier: "presenceMenuBar", target: self, action: #selector(changePresence(_:))),
                           SettingsLayout.radio("Both", tag: 0, identifier: "presenceBoth", target: self, action: #selector(changePresence(_:)))]
        snapCheckbox = SettingsLayout.checkbox("Show OpenSnap window in fullscreen and crosshair snaps", identifier: "includeApp",
                                               target: self, action: #selector(changeSnap(_:)), wraps: true)
        hoverHintsCheckbox = SettingsLayout.checkbox("Show hover hints for tools", identifier: "showToolTips", target: self, action: #selector(changeHoverHints(_:)))
        keyboardTipsCheckbox = SettingsLayout.checkbox("Show keyboard tip overlay", identifier: "showKeyboardTips", target: self, action: #selector(changeKeyboardTips(_:)))
        let rows: [[NSView]] = [
            [SettingsLayout.rowLabel("Show in:"), SettingsLayout.choices(presenceButtons)],
            [SettingsLayout.rowLabel("Snapping:"), snapCheckbox],
            [SettingsLayout.rowLabel("Hints:"), SettingsLayout.group([hoverHintsCheckbox, keyboardTipsCheckbox])]]
        defer { refresh() }
        return rows
    }

    override func refresh() {
        guard isViewLoaded || !presenceButtons.isEmpty else { return }
        let state = model.state
        for button in presenceButtons { button.state = button.tag == state.statusMenu ? .on : .off }
        snapCheckbox.state = state.includeApp ? .on : .off
        hoverHintsCheckbox.state = state.showToolTips ? .on : .off
        keyboardTipsCheckbox.state = state.showKeyboardTips ? .on : .off
    }

    @objc private func changePresence(_ sender: NSButton) { model.edit { $0.statusMenu = sender.tag } }
    @objc private func changeSnap(_ sender: NSButton) { model.edit { $0.includeApp = sender.state == .on } }
    @objc private func changeHoverHints(_ sender: NSButton) { model.edit { $0.showToolTips = sender.state == .on } }
    @objc private func changeKeyboardTips(_ sender: NSButton) { model.edit { $0.showKeyboardTips = sender.state == .on } }
}

@MainActor
final class DrawingSettingsTab: SettingsTabViewController {
    let model: SettingsPreferencesModel
    private(set) var precisionButtons: [NSButton] = []
    private(set) var arrowButtons: [NSButton] = []

    init(model: SettingsPreferencesModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = "Drawing"
        model.observe { [weak self] in self?.refresh() }
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }

    override func makeRows() -> [[NSView]] {
        precisionButtons = [SettingsLayout.radio("Precise", tag: 0, identifier: "precisionPrecise", target: self, action: #selector(changePrecision(_:))),
                            SettingsLayout.radio("Medium", tag: 1, identifier: "precisionMedium", target: self, action: #selector(changePrecision(_:))),
                            SettingsLayout.radio("Loose", tag: 2, identifier: "precisionLoose", target: self, action: #selector(changePrecision(_:)))]
        arrowButtons = [SettingsLayout.radio("End", tag: 2, identifier: "arrowEnd", target: self, action: #selector(changeArrow(_:))),
                        SettingsLayout.radio("Start", tag: 1, identifier: "arrowStart", target: self, action: #selector(changeArrow(_:)))]
        let rows: [[NSView]] = [
            [SettingsLayout.rowLabel("Drawing precision:"), SettingsLayout.choices(precisionButtons)],
            [SettingsLayout.rowLabel("Arrow head:"), SettingsLayout.choices(arrowButtons)],
            [NSGridCell.emptyContentView, SettingsLayout.caption("Holding Option reverses the setting.")]]
        defer { refresh() }
        return rows
    }

    override func refresh() {
        guard !precisionButtons.isEmpty else { return }
        let state = model.state
        let precision: Int
        switch state.drawingPrecision { case .precise: precision = 0; case .medium: precision = 1; case .loose: precision = 2 }
        for button in precisionButtons { button.state = button.tag == precision ? .on : .off }
        for button in arrowButtons { button.state = button.tag == state.arrowHead ? .on : .off }
    }

    @objc private func changePrecision(_ sender: NSButton) {
        model.edit {
            switch sender.tag { case 0: $0.drawingPrecision = .precise; case 2: $0.drawingPrecision = .loose; default: $0.drawingPrecision = .medium }
        }
    }
    @objc private func changeArrow(_ sender: NSButton) { model.edit { $0.arrowHead = sender.tag } }
}

@MainActor
final class CaptureSettingsTab: SettingsTabViewController {
    private let defaults: UserDefaults
    private let hotkeys: any GlobalHotkeyEditing
    private(set) var flashCheckbox: NSButton!
    private(set) var hotkeyForm: GlobalHotkeyForm!

    init(defaults: UserDefaults, hotkeys: any GlobalHotkeyEditing) {
        self.defaults = defaults; self.hotkeys = hotkeys
        super.init(nibName: nil, bundle: nil)
        title = "Capture"
    }
    required init?(coder: NSCoder) { fatalError("Use init(defaults:hotkeys:)") }

    override func makeRows() -> [[NSView]] {
        flashCheckbox = SettingsLayout.checkbox("Show capture flash", identifier: "showCaptureFlash", target: self, action: #selector(changeFlash(_:)))
        hotkeyForm = GlobalHotkeyForm(manager: hotkeys, mode: .live, labelWidth: SettingsLayout.labelColumnWidth, width: SettingsLayout.gridWidth)
        hotkeyForm.translatesAutoresizingMaskIntoConstraints = false
        hotkeyForm.onResize = { [weak self] in
            // The status line wraps to one line or more; the grid has not laid it out yet.
            DispatchQueue.main.async { self?.contentChanged() }
        }
        defer { refresh() }
        return [[SettingsLayout.rowLabel("Flash:"), flashCheckbox], [hotkeyForm, NSGridCell.emptyContentView]]
    }

    override func loadView() {
        super.loadView()
        grid.row(at: 1).mergeCells(in: NSRange(location: 0, length: 2))
        grid.row(at: 1).yPlacement = .top
    }

    override func refresh() {
        guard flashCheckbox != nil else { return }
        flashCheckbox.state = OriginalCaptureFlashTiming.showFlash(defaults: defaults) ? .on : .off
    }

    /// The shortcuts are re-read from the manager only when the window opens, so an error beside an edit survives a refresh.
    func reloadShortcuts() { hotkeyForm?.reload() }

    @objc private func changeFlash(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: OriginalCaptureFlashTiming.showFlashKey)
    }
}

/// The framed surface the destination rows sit on: content colour, a hairline border, a medium radius.
@MainActor
final class SettingsListSurface: NSView {
    let stack = NSStackView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = DesignTokens.Radius.md; layer?.borderWidth = 1; layer?.masksToBounds = true
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = DesignTokens.Palette.Surface.content.cgColor
            layer?.borderColor = DesignTokens.Palette.separator.cgColor
        }
    }
}

/// One saved destination: its name over its transport, and the Default pill when Upload uses it. The name never shares a line
/// with the transport, so a long name truncates only when it is longer than the row.
@MainActor
final class SettingsDestinationRow: NSView {
    static let height = DesignTokens.Size.row + DesignTokens.Space.s3
    let nameField: NSTextField, transportField: NSTextField
    private(set) var pill: DefaultPillView?

    init(name: String, transport: String, isDefault: Bool) {
        nameField = NSTextField(labelWithString: name); transportField = NSTextField(labelWithString: transport)
        super.init(frame: .zero)
        nameField.font = DesignTokens.Typography.font(.body); nameField.textColor = DesignTokens.Palette.Text.primary
        nameField.lineBreakMode = .byTruncatingTail
        transportField.font = DesignTokens.Typography.font(.caption); transportField.textColor = DesignTokens.Palette.Text.secondary
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSStackView(views: [nameField, transportField])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 0
        let flexible = NSView(); flexible.setContentHuggingPriority(.init(1), for: .horizontal)
        var views: [NSView] = [text, flexible]
        if isDefault { let pill = DefaultPillView(); self.pill = pill; views.append(pill) }
        let row = NSStackView(views: views)
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = DesignTokens.Space.s3
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Space.s4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Space.s3),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)])
        setAccessibilityElement(true); setAccessibilityRole(.row)
        setAccessibilityLabel([name, transport, isDefault ? "Default" : nil].compactMap { $0 }.joined(separator: ", "))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
final class UploadSettingsTab: SettingsTabViewController {
    /// More destinations than this are summarised; the full list is in the sheet.
    static let visibleRows = 5
    private let destinations: () -> PublishingDestinationList
    private let manage: () -> Void
    private let listSurface = SettingsListSurface()
    private var listStack: NSStackView { listSurface.stack }
    private let emptyLabel = NSTextField(wrappingLabelWithString: "No upload destination yet.")
    private let moreLabel = NSTextField(labelWithString: "")
    private(set) var manageButton: NSButton!
    private(set) var rows: [SettingsDestinationRow] = []

    init(destinations: @escaping () -> PublishingDestinationList, manage: @escaping () -> Void) {
        self.destinations = destinations; self.manage = manage
        super.init(nibName: nil, bundle: nil)
        title = "Upload"
    }
    required init?(coder: NSCoder) { fatalError("Use init(destinations:manage:)") }

    /// What the list shows, row by row: name, transport, default.
    var listedNames: [String] { rows.map { $0.nameField.stringValue } }
    var emptyStateText: String? { emptyLabel.isHidden ? nil : emptyLabel.stringValue }
    var summaryText: String? { moreLabel.isHidden ? nil : moreLabel.stringValue }

    override func makeRows() -> [[NSView]] {
        emptyLabel.font = DesignTokens.Typography.font(.body); emptyLabel.textColor = DesignTokens.Palette.Text.secondary
        emptyLabel.preferredMaxLayoutWidth = SettingsLayout.controlColumnWidth - 2 * DesignTokens.Space.s4
        moreLabel.font = DesignTokens.Typography.font(.caption); moreLabel.textColor = DesignTokens.Palette.Text.secondary
        listSurface.translatesAutoresizingMaskIntoConstraints = false
        listSurface.widthAnchor.constraint(equalToConstant: SettingsLayout.controlColumnWidth).isActive = true
        manageButton = SettingsLayout.pushButton("Manage Destinations…", identifier: "manageDestinations", target: self, action: #selector(manageTapped))
        let caption = SettingsLayout.caption("Uploads go to the default destination.")
        defer { refresh() }
        // The label sits level with the first destination row, not with the middle of a tall list.
        let label = SettingsLayout.rowLabel("Destinations:")
        let labelCell = NSView(); labelCell.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false; labelCell.addSubview(label)
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: labelCell.trailingAnchor), label.leadingAnchor.constraint(greaterThanOrEqualTo: labelCell.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: labelCell.topAnchor, constant: SettingsDestinationRow.height / 2),
            labelCell.heightAnchor.constraint(equalToConstant: SettingsDestinationRow.height)])
        return [[labelCell, listSurface],
                [NSGridCell.emptyContentView, manageButton],
                [NSGridCell.emptyContentView, caption]]
    }

    override func loadView() {
        super.loadView()
        grid.row(at: 0).rowAlignment = .none
        grid.row(at: 0).yPlacement = .top
    }

    override func refresh() {
        guard manageButton != nil else { return }
        let list = destinations()
        let defaultID = list.defaultDestination?.id
        for view in listStack.arrangedSubviews { listStack.removeArrangedSubview(view); view.removeFromSuperview() }
        rows = []
        for (index, destination) in list.destinations.prefix(Self.visibleRows).enumerated() {
            if index > 0 {
                let line = NSBox(); line.boxType = .separator; line.translatesAutoresizingMaskIntoConstraints = false
                listStack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalToConstant: SettingsLayout.controlColumnWidth).isActive = true
            }
            let row = SettingsDestinationRow(name: destination.name, transport: destination.settings.transport.title, isDefault: destination.id == defaultID)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: SettingsDestinationRow.height).isActive = true
            row.widthAnchor.constraint(equalToConstant: SettingsLayout.controlColumnWidth).isActive = true
            listStack.addArrangedSubview(row); rows.append(row)
        }
        emptyLabel.isHidden = !list.destinations.isEmpty
        if list.destinations.isEmpty {
            let wrapper = NSView(); wrapper.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(emptyLabel)
            NSLayoutConstraint.activate([
                emptyLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: DesignTokens.Space.s4),
                emptyLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -DesignTokens.Space.s4),
                emptyLabel.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: DesignTokens.Space.s3),
                emptyLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -DesignTokens.Space.s3),
                wrapper.widthAnchor.constraint(equalToConstant: SettingsLayout.controlColumnWidth)])
            listStack.addArrangedSubview(wrapper)
        }
        let hidden = list.destinations.count - Self.visibleRows
        moreLabel.isHidden = hidden <= 0
        if hidden > 0 {
            moreLabel.stringValue = "and \(hidden) more in Manage Destinations…"
            let wrapper = NSView(); wrapper.translatesAutoresizingMaskIntoConstraints = false
            moreLabel.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(moreLabel)
            NSLayoutConstraint.activate([
                moreLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: DesignTokens.Space.s4),
                moreLabel.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                wrapper.heightAnchor.constraint(equalToConstant: DesignTokens.Size.row),
                wrapper.widthAnchor.constraint(equalToConstant: SettingsLayout.controlColumnWidth)])
            listStack.addArrangedSubview(wrapper)
        }
        if isViewLoaded { contentChanged() }
    }

    @objc private func manageTapped() { manage() }
}

/// Escape and Command-W close it; so does the close button. It calls `onClose` so the owner decides what closing means.
@MainActor
class SettingsWindow: NSWindow {
    var onClose: (() -> Void)?

    required override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    func requestClose() {
        guard attachedSheet == nil else { return }
        if let onClose { onClose() } else { orderOut(nil) }
    }
    override func cancelOperation(_ sender: Any?) { requestClose() }
    /// A key nothing in the chain wanted ends up here; Escape is the one this window does.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty { cancelOperation(nil) }
        else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            requestClose(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// An `NSTabViewController` that tells its owner when the selection changes.
@MainActor
final class SettingsTabs: NSTabViewController {
    var onSelect: ((NSTabViewItem?) -> Void)?
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelect?(tabViewItem)
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Where the window's frame is stored. The app passes it; a test leaves it out so nothing is written to defaults.
    static let autosaveName = "OpenSnap.Settings"
    /// The window class a new controller builds. The app's isolated tests substitute a subclass that never reaches the screen.
    static var windowClass: SettingsWindow.Type = SettingsWindow.self
    private static let icons: [(String, FAIcon)] = [("General", .toolbox), ("Drawing", .paintbrush), ("Capture", .crosshairs), ("Upload", .upload)]

    let window: SettingsWindow
    let tabs = SettingsTabs()
    let model: SettingsPreferencesModel
    let general: GeneralSettingsTab, drawing: DrawingSettingsTab, capture: CaptureSettingsTab, upload: UploadSettingsTab
    private let stateProvider: () -> GeneralPreferencesState
    private var hasSavedFrame = false
    private var observers: [NSObjectProtocol] = []
    private var resizeTimer: Timer?
    private static let resizeDuration: TimeInterval = 0.2
    /// The visible area of the screen the window is on. A test replaces it with a fake screen.
    /// A window that is not on screen resizes at once; a test turns this on to watch the animation without ordering a window front.
    var animatesWhenHidden = false
    /// Under Reduce Motion the window changes size at once. A test replaces it.
    var reduceMotion: () -> Bool = { DisplayOptions.current.reduceMotion }
    var visibleFrame: () -> NSRect = { NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900) }

    /// Called for Escape, Command-W and the close button. The owner hides the window.
    var onClose: (() -> Void)? {
        get { window.onClose }
        set { window.onClose = newValue }
    }
    /// Every edit on General and Drawing, as the complete current state.
    var onChange: ((GeneralPreferencesState) -> Void)? {
        get { model.onChange }
        set { model.onChange = newValue }
    }

    init(state: @escaping () -> GeneralPreferencesState, hotkeys: any GlobalHotkeyEditing, defaults: UserDefaults,
         destinations: @escaping () -> PublishingDestinationList, manageDestinations: @escaping (NSWindow) -> Void,
         frameAutosaveName: String? = nil) {
        stateProvider = state
        model = SettingsPreferencesModel(state: state())
        window = Self.windowClass.init(contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: 300),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        general = GeneralSettingsTab(model: model); drawing = DrawingSettingsTab(model: model)
        capture = CaptureSettingsTab(defaults: defaults, hotkeys: hotkeys)
        var presentManage: () -> Void = {}
        upload = UploadSettingsTab(destinations: destinations, manage: { presentManage() })
        super.init()
        presentManage = { [weak self] in
            guard let self, self.window.attachedSheet == nil else { return }
            manageDestinations(self.window)
        }

        window.isReleasedWhenClosed = false
        window.delegate = self
        window.toolbarStyle = .preference
        tabs.tabStyle = .toolbar
        // The tab view's own strip is not drawn in toolbar style; the toolbar draws the labels at the system's size.
        tabs.tabView.font = DesignTokens.Typography.font(.body)
        let all: [SettingsTabViewController] = [general, drawing, capture, upload]
        for (index, tab) in all.enumerated() {
            let item = NSTabViewItem(viewController: tab)
            item.label = Self.icons[index].0
            item.identifier = Self.icons[index].0
            item.image = ChromeIcons.resolve(Self.icons[index].1, family: .solid, pointSize: DesignTokens.Typography.iconPrimary).image
            tabs.addTabViewItem(item)
            _ = tab.fittingHeight
            tab.onResize = { [weak self] in self?.fit(animated: self?.window.isVisible ?? false) }
        }
        tabs.onSelect = { [weak self] _ in self?.selectionChanged() }
        window.contentViewController = tabs
        selectionChanged(animated: false)
        if let frameAutosaveName { hasSavedFrame = window.setFrameAutosaveName(frameAutosaveName) }
        AppToolTip.install(on: window.contentView ?? tabs.view)

        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.upload.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    var selectedIndex: Int { tabs.selectedTabViewItemIndex }
    var selectedTab: SettingsTabViewController { tabs.tabViewItems[max(0, selectedIndex)].viewController as! SettingsTabViewController }
    var tabItems: [NSTabViewItem] { tabs.tabViewItems }

    func select(_ index: Int) { tabs.selectedTabViewItemIndex = index }

    /// Shows what the parent stored: General and Drawing, the flash, the destinations. Delivers no edit.
    func refresh() {
        model.synchronize(stateProvider())
        capture.refresh(); upload.refresh()
    }

    /// The parent changed the stored preferences itself (a menu command), so the controls follow.
    func synchronize(_ state: GeneralPreferencesState) { model.synchronize(state) }

    func show() {
        refresh(); capture.reloadShortcuts()
        fit(animated: false)
        if !hasSavedFrame { window.center(); hasSavedFrame = true }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Sizing

    /// The window frame a tab asks for: 640 wide, its own height, the top edge kept where it is.
    func frame(forTabAt index: Int, keepingTopOf current: NSRect) -> NSRect {
        let tab = tabs.tabViewItems[index].viewController as! SettingsTabViewController
        let size = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: tab.fittingHeight)).size
        return NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
    }

    /// The whole window height a tab needs, title bar and toolbar included.
    func windowHeight(forTabAt index: Int) -> CGFloat { frame(forTabAt: index, keepingTopOf: window.frame).height }

    func fit(animated: Bool) {
        guard selectedIndex >= 0 else { return }
        var target = frame(forTabAt: selectedIndex, keepingTopOf: window.frame)
        let visible = visibleFrame()
        if target.height > visible.height { target.size.height = visible.height }
        if target.minY < visible.minY { target.origin.y = visible.minY }
        guard abs(target.height - window.frame.height) > 0.5 || abs(target.width - window.frame.width) > 0.5 else { return }
        setFrame(target, animated: animated && !reduceMotion())
    }

    /// The one writer for the window's size. A change that arrives while an earlier one is still animating replaces it, so the last
    /// size asked for is the one the window ends on (AppKit's own frame animation keeps stepping toward its first target).
    private func setFrame(_ target: NSRect, animated: Bool) {
        resizeTimer?.invalidate(); resizeTimer = nil
        let start = window.frame
        guard animated, start != target else { window.setFrame(target, display: true); return }
        let began = Date()
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let progress = min(1, Date().timeIntervalSince(began) / Self.resizeDuration)
                let eased = CGFloat(progress * progress * (3 - 2 * progress))
                func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * eased }
                self.window.setFrame(NSRect(x: mix(start.minX, target.minX), y: mix(start.minY, target.minY),
                                            width: mix(start.width, target.width), height: mix(start.height, target.height)), display: true)
                if progress >= 1 { timer.invalidate(); self.resizeTimer = nil }
            }
        }
    }

    private func selectionChanged(animated: Bool = true) {
        guard selectedIndex >= 0 else { return }
        window.title = tabs.tabViewItems[selectedIndex].label
        fit(animated: animated && (window.isVisible || animatesWhenHidden))
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard window.onClose != nil else { return true }
        window.requestClose()
        return false
    }
}
