import AppKit

// The Settings window: four tabs (General, Drawing, Capture, Upload) on an app-owned strip at the top of the content, no Done
// button, every change applied at once. It is self-contained: the app hands it closures for the things it owns (stored
// preferences, the shortcut manager, the destination list, the destinations sheet) and it owns nothing else, so a test can build
// it with in-memory stand-ins. The strip is ours, not an NSToolbar's, because AppKit draws toolbar labels at about 13 pt and an
// app-owned label is 20 pt. The title bar text is the one thing the OS still sets; it follows the selected tab.

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
        GeneralSettingsTab.rowLabels + DrawingSettingsTab.rowLabels + ["Flash:", "Destinations:"] + GlobalHotkeyForm.labelTexts()
    }
    static var labelColumnWidth: CGFloat { labelWidth(for: rowLabels) }
    static var controlColumnWidth: CGFloat { gridWidth - labelColumnWidth - columnSpacing }

    /// The label column a tab needs for its own labels. A short form (General, Drawing) sizes to them and is centred; the long ones
    /// (Capture, Upload) use the widest label of all so they stay one column.
    static func labelWidth(for labels: [String]) -> CGFloat {
        let font = Typography.font(.bodyStrong)
        return ceil(labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
    }
    /// The widest a control column can be inside the content width once the label column is taken.
    static func availableControlWidth(labelWidth: CGFloat) -> CGFloat { gridWidth - labelWidth - columnSpacing }

    /// A row label: right-aligned in the label column, 20 pt semibold.
    static func rowLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = Typography.font(.bodyStrong); field.alignment = .right
        field.textColor = DesignTokens.Palette.Text.primary
        return field
    }

    /// Secondary text under a control, the only place the 18 pt caption is used.
    static func caption(_ text: String, width: CGFloat? = nil) -> NSTextField {
        let width = width ?? controlColumnWidth
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = Typography.font(.caption); field.textColor = DesignTokens.Palette.Text.secondary
        field.preferredMaxLayoutWidth = width
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    /// The width a caption takes on one line, so a tab can size its control column to hold it.
    static func captionWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: Typography.font(.caption)]).width)
    }

    /// A checkbox. With `wrapWidth` the title wraps inside that width (the checkbox glyph included).
    static func checkbox(_ title: String, identifier: String, target: AnyObject, action: Selector, wrapWidth: CGFloat? = nil) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: target, action: action)
        guard let wrapWidth else { configure(button, identifier: identifier); return button }
        let measured = (title as NSString).boundingRect(with: NSSize(width: wrapWidth - checkboxIndent, height: .greatestFiniteMagnitude),
                                                       options: .usesLineFragmentOrigin, attributes: [.font: Typography.font(.body)])
        configure(button, identifier: identifier, height: ceil(measured.height))
        button.cell?.wraps = true; button.cell?.isScrollable = false; button.cell?.lineBreakMode = .byWordWrapping
        button.widthAnchor.constraint(equalToConstant: wrapWidth).isActive = true
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

/// One tab: a form grid sized to its content, centred across the window and pinned to the top.
@MainActor
class SettingsTabViewController: NSViewController {
    private(set) var grid = NSGridView()
    /// A tab whose content changed height asks the window to refit.
    var onResize: (() -> Void)?
    /// The label and control column widths of this tab's grid. A subclass with a short form sets them in `makeRows`.
    var labelWidth = SettingsLayout.labelColumnWidth
    var controlWidth = SettingsLayout.controlColumnWidth

    /// Rows of [label, control]; a row with no label uses `NSGridCell.emptyContentView`. Subclasses override.
    func makeRows() -> [[NSView]] { [] }
    /// Re-reads whatever the tab shows from its source of truth. Delivers nothing.
    func refresh() {}

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        // Content width unless the scroll view says otherwise: a scroll bar that takes room leaves the grid centred in what is left.
        let width = root.widthAnchor.constraint(equalToConstant: SettingsLayout.contentWidth)
        width.priority = .defaultHigh; width.isActive = true
        grid = NSGridView(views: makeRows())
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = SettingsLayout.rowSpacing; grid.columnSpacing = SettingsLayout.columnSpacing
        grid.column(at: 0).xPlacement = .trailing; grid.column(at: 0).width = labelWidth
        grid.column(at: 1).xPlacement = .leading; grid.column(at: 1).width = controlWidth
        for index in 0..<grid.numberOfRows { grid.row(at: index).rowAlignment = .firstBaseline }
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: SettingsLayout.verticalMargin),
            grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -SettingsLayout.verticalMargin),
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
    static let rowLabels = ["Show in:", "Snapping:", "Hints:"]
    /// Wide enough that the snap sentence wraps to two lines, not three.
    private static let minimumControlWidth: CGFloat = 420
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
        hoverHintsCheckbox = SettingsLayout.checkbox("Show hover hints for tools", identifier: "showToolTips", target: self, action: #selector(changeHoverHints(_:)))
        keyboardTipsCheckbox = SettingsLayout.checkbox("Show keyboard tip overlay", identifier: "showKeyboardTips", target: self, action: #selector(changeKeyboardTips(_:)))
        let presence = SettingsLayout.choices(presenceButtons)
        // The form is as wide as its widest control and no wider, so the window centres it; the long snap sentence wraps inside that width.
        labelWidth = SettingsLayout.labelWidth(for: Self.rowLabels)
        let available = SettingsLayout.availableControlWidth(labelWidth: labelWidth)
        controlWidth = min(available, ceil(max(presence.fittingSize.width, hoverHintsCheckbox.fittingSize.width, keyboardTipsCheckbox.fittingSize.width, Self.minimumControlWidth)))
        snapCheckbox = SettingsLayout.checkbox("Show OpenSnap window in fullscreen and crosshair snaps", identifier: "includeApp",
                                               target: self, action: #selector(changeSnap(_:)), wrapWidth: controlWidth)
        let rows: [[NSView]] = [
            [SettingsLayout.rowLabel("Show in:"), presence],
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
    static let rowLabels = ["Drawing precision:", "Arrow head:"]
    private static let note = "Holding Option reverses the setting."
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
        let precision = SettingsLayout.choices(precisionButtons), arrow = SettingsLayout.choices(arrowButtons)
        labelWidth = SettingsLayout.labelWidth(for: Self.rowLabels)
        controlWidth = min(SettingsLayout.availableControlWidth(labelWidth: labelWidth),
                           ceil(max(precision.fittingSize.width, arrow.fittingSize.width, SettingsLayout.captionWidth(Self.note))))
        let rows: [[NSView]] = [
            [SettingsLayout.rowLabel("Drawing precision:"), precision],
            [SettingsLayout.rowLabel("Arrow head:"), arrow],
            [NSGridCell.emptyContentView, SettingsLayout.caption(Self.note, width: controlWidth)]]
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
        hotkeyForm = GlobalHotkeyForm(manager: hotkeys, labelWidth: SettingsLayout.labelColumnWidth, width: SettingsLayout.gridWidth)
        hotkeyForm.translatesAutoresizingMaskIntoConstraints = false
        hotkeyForm.onResize = { [weak self] in
            // The status line wraps to one line or more; the grid has not laid it out yet.
            DispatchQueue.main.async { self?.contentChanged() }
        }
        hotkeyForm.setShortcutsPaused(shortcutsPaused)
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

    /// Whether the shortcuts are paused now; kept here so a form built after the window went key still opens in the right state.
    private(set) var shortcutsPaused = false
    func setShortcutsPaused(_ paused: Bool) { shortcutsPaused = paused; hotkeyForm?.setShortcutsPaused(paused) }

    /// The shortcuts are re-read from the manager only when the window opens, so an error beside an edit survives a refresh.
    func reloadShortcuts() { hotkeyForm?.reload() }

    @objc private func changeFlash(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: OriginalCaptureFlashTiming.showFlashKey)
    }
}

/// The framed surface the destination rows sit on: content colour, a hairline border, a medium radius. The rows sit in a scroll view
/// so a list taller than `maximumHeight` scrolls inside the frame instead of pushing the rest of the tab off the screen.
@MainActor
final class SettingsListSurface: NSView {
    let stack = NSStackView()
    let scroll = NSScrollView()
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)
    /// The tallest the frame grows; the rows scroll past it.
    var maximumHeight: CGFloat = .greatestFiniteMagnitude { didSet { updateHeight() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = DesignTokens.Radius.md; layer?.borderWidth = 1; layer?.masksToBounds = true
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView = SettingsClipView()
        scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.scrollerStyle = .overlay
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        addSubview(scroll)
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: clip.topAnchor), stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor), heightConstraint])
        updateHeight()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The height the rows ask for, however tall the frame is allowed to be.
    var contentHeight: CGFloat { stack.layoutSubtreeIfNeeded(); return ceil(stack.fittingSize.height) }
    /// The frame is as tall as its rows, up to the maximum.
    func updateHeight() { heightConstraint.constant = min(contentHeight, maximumHeight) }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = DesignTokens.Palette.Surface.content.cgColor
            layer?.borderColor = DesignTokens.Palette.separator.cgColor
        }
    }
}

/// The bar ahead of a selected row's name under Differentiate Without Color: a solid 4 pt bar in the text colour, 28 pt tall.
@MainActor
final class SettingsSelectionBar: NSView {
    static let size = CGSize(width: DesignTokens.Space.s1, height: DesignTokens.Size.row - DesignTokens.Space.s4)
    override var wantsUpdateLayer: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.cornerRadius = DesignTokens.Space.s1 / 2
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = DesignTokens.Palette.Text.primary.cgColor }
    }
}

/// One saved destination: its name over its transport, and the Default pill when Upload uses it. The name never shares a line
/// with the transport, so a long name truncates only when it is longer than the row.
@MainActor
final class SettingsDestinationRow: NSView {
    static let height = DesignTokens.Size.row + DesignTokens.Space.s3
    let nameField: NSTextField, transportField: NSTextField
    private(set) var pill: DefaultPillView?
    /// Called on a click (the count says whether it was a double click, which edits).
    var onClick: ((Int) -> Void)?
    /// The row the buttons below act on: a filled plate with an accent edge, and "selected" for VoiceOver, so it never relies on colour alone.
    /// Differentiate Without Color adds a 2 pt edge in the text colour and a bar ahead of the name: shapes, not a tint. The bar is not a
    /// check: the Default pill already carries one, and two checks on two rows would mean two different things (R3-007).
    var isSelected = false {
        didSet { guard isSelected != oldValue else { return }; refreshMark(); needsDisplay = true; setAccessibilitySelected(isSelected) }
    }
    /// The bar ahead of the name. Hidden (and out of the layout) unless Differentiate Without Color is on; then every row keeps the
    /// slot and only the selected one shows the bar, so the names stay aligned.
    let selectionMark = SettingsSelectionBar()
    private var displayObservation: DisplayOptions.Observation?
    private var differentiates: Bool { DisplayOptions.current.differentiateWithoutColor }

    private func refreshMark() {
        selectionMark.isHidden = !differentiates
        selectionMark.alphaValue = isSelected ? 1 : 0
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let outline = differentiates
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isSelected ? DesignTokens.Palette.State.selectedFill : NSColor.clear).cgColor
            layer?.borderColor = (outline ? DesignTokens.Palette.Text.primary : DesignTokens.Palette.accent).cgColor
        }
        layer?.borderWidth = isSelected ? (outline ? 2 : 1) : 0
    }
    override func mouseDown(with event: NSEvent) { onClick?(event.clickCount) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(name: String, transport: String, isDefault: Bool) {
        nameField = NSTextField(labelWithString: name); transportField = NSTextField(labelWithString: transport)
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = DesignTokens.Radius.sm
        nameField.font = DesignTokens.Typography.font(.body); nameField.textColor = DesignTokens.Palette.Text.primary
        nameField.lineBreakMode = .byTruncatingTail
        transportField.font = DesignTokens.Typography.font(.caption); transportField.textColor = DesignTokens.Palette.Text.secondary
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSStackView(views: [nameField, transportField])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 0
        let flexible = NSView(); flexible.setContentHuggingPriority(.init(1), for: .horizontal)
        var views: [NSView] = [selectionMark, text, flexible]
        if isDefault { let pill = DefaultPillView(); self.pill = pill; views.append(pill) }
        let row = NSStackView(views: views)
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = DesignTokens.Space.s3
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Space.s4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Space.s3),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)])
        setAccessibilityElement(true); setAccessibilityRole(.row); setAccessibilitySelected(false)
        setAccessibilityLabel([name, transport, isDefault ? "Default" : nil].compactMap { $0 }.joined(separator: ", "))
        refreshMark()
        displayObservation = DisplayOptions.observe { [weak self] _ in self?.refreshMark(); self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// What the Upload tab's buttons do, supplied by the owner. The defaults do nothing, so a bare Settings window is inert.
struct SettingsDestinationActions {
    /// Opens the destination editor sheet on the given window: `nil` adds a destination, a destination edits it.
    var edit: (PublishingDestination?, NSWindow) -> Void = { _, _ in }
    var makeDefault: (String) throws -> Void = { _ in }
    var remove: (String) throws -> Void = { _ in }
    /// The wording of the question asked before a destination is removed.
    var removalPrompt: (PublishingDestination) -> (title: String, detail: String) = { ("Remove “\($0.name)”?", "This cannot be undone.") }
}

@MainActor
final class UploadSettingsTab: SettingsTabViewController {
    /// This tab has no label column: "Destinations" is a heading over a list that takes the whole content width, with its four buttons under
    /// it (Add…, Edit…, Remove and Make Default need about 410 pt at 20 pt).
    static var labelColumnWidth: CGFloat { 0 }
    static var listWidth: CGFloat { SettingsLayout.gridWidth }
    static let hint = "Uploads go to the default destination. Right-click Upload to switch."
    private let destinations: () -> PublishingDestinationList
    private let listSurface = SettingsListSurface()
    private var listStack: NSStackView { listSurface.stack }
    private let emptyLabel = NSTextField(wrappingLabelWithString: "No destinations yet")
    private(set) var addButton: NSButton!, editButton: NSButton!, removeButton: NSButton!, defaultButton: NSButton!
    /// The Add… button inside an empty list; with destinations the row of four buttons below the list takes over.
    private(set) var emptyAddButton: NSButton!
    private var buttonRow: NSStackView!
    private(set) var rows: [SettingsDestinationRow] = []
    private var listed: [PublishingDestination] = []
    private var defaultID: String?
    /// The destination the Edit…, Remove and Make Default buttons act on.
    private(set) var selectedID: String?

    /// What the buttons do. The owner supplies them; the tab owns no storage.
    var onAdd: () -> Void = {}
    var onEdit: (PublishingDestination) -> Void = { _ in }
    var onRemove: (PublishingDestination) -> Void = { _ in }
    var onMakeDefault: (PublishingDestination) -> Void = { _ in }

    init(destinations: @escaping () -> PublishingDestinationList) {
        self.destinations = destinations
        super.init(nibName: nil, bundle: nil)
        title = "Upload"
    }
    required init?(coder: NSCoder) { fatalError("Use init(destinations:)") }

    /// What the list shows, row by row: name, transport, default.
    var listedNames: [String] { rows.map { $0.nameField.stringValue } }
    var emptyStateText: String? { emptyLabel.isHidden ? nil : emptyLabel.stringValue }
    var selectedDestination: PublishingDestination? { listed.first { $0.id == selectedID } }

    override func makeRows() -> [[NSView]] {
        labelWidth = Self.labelColumnWidth; controlWidth = Self.listWidth
        emptyLabel.font = DesignTokens.Typography.font(.body); emptyLabel.textColor = DesignTokens.Palette.Text.secondary
        emptyLabel.preferredMaxLayoutWidth = Self.listWidth - 2 * DesignTokens.Space.s4
        listSurface.translatesAutoresizingMaskIntoConstraints = false
        listSurface.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
        addButton = SettingsLayout.pushButton("Add…", identifier: "addDestination", target: self, action: #selector(addTapped))
        editButton = SettingsLayout.pushButton("Edit…", identifier: "editDestination", target: self, action: #selector(editTapped))
        removeButton = SettingsLayout.pushButton("Remove", identifier: "removeDestination", target: self, action: #selector(removeTapped))
        defaultButton = SettingsLayout.pushButton("Make Default", identifier: "makeDefaultDestination", target: self, action: #selector(makeDefaultTapped))
        emptyAddButton = SettingsLayout.pushButton("Add…", identifier: "addFirstDestination", target: self, action: #selector(addTapped))
        buttonRow = NSStackView(views: [addButton, editButton, removeButton, defaultButton])
        buttonRow.orientation = .horizontal; buttonRow.spacing = DesignTokens.Space.s2
        hintLabel = SettingsLayout.caption(Self.hint, width: Self.listWidth)
        defer { refresh() }
        let heading = NSTextField(labelWithString: "Destinations")
        heading.font = DesignTokens.Typography.font(.bodyStrong); heading.textColor = DesignTokens.Palette.Text.primary
        heading.setAccessibilityRole(.staticText)
        return [[NSGridCell.emptyContentView, heading],
                [NSGridCell.emptyContentView, listSurface],
                [NSGridCell.emptyContentView, buttonRow],
                [NSGridCell.emptyContentView, hintLabel]]
    }

    override func loadView() {
        super.loadView()
        grid.column(at: 0).isHidden = true
        grid.row(at: 1).rowAlignment = .none
        grid.row(at: 1).yPlacement = .top
        grid.row(at: 2).isHidden = listed.isEmpty
        grid.row(at: 3).isHidden = listed.isEmpty
    }
    private var hintLabel: NSTextField!
    /// Whether the line about switching destinations shows: it only means something once there is one to switch to.
    var hintIsVisible: Bool { isViewLoaded ? !grid.row(at: 3).isHidden : false }

    override func refresh() {
        guard addButton != nil else { return }
        render(destinations())
    }

    /// The tallest the destination list grows before it scrolls inside its frame. The window sets it from the screen it has.
    var listMaximumHeight: CGFloat = .greatestFiniteMagnitude { didSet { listSurface.maximumHeight = listMaximumHeight } }
    /// The height the list asks for, and the height it takes now.
    var listContentHeight: CGFloat { listSurface.contentHeight }
    var listHeight: CGFloat { listSurface.frame.height }
    /// The list's scroll view, so a test can see whether it has something to scroll.
    var listScroll: NSScrollView { listSurface.scroll }

    /// Selects a row, as a click does.
    func select(id: String?) {
        selectedID = id
        for (index, row) in rows.enumerated() { row.isSelected = listed.indices.contains(index) && listed[index].id == id }
        let selected = selectedDestination
        editButton.isEnabled = selected != nil; removeButton.isEnabled = selected != nil
        defaultButton.isEnabled = selected != nil && selected?.id != defaultID
    }

    private func render(_ list: PublishingDestinationList) {
        defaultID = list.defaultDestination?.id
        listed = list.destinations
        for view in listStack.arrangedSubviews { listStack.removeArrangedSubview(view); view.removeFromSuperview() }
        rows = []
        for (index, destination) in list.destinations.enumerated() {
            if index > 0 {
                let line = NSBox(); line.boxType = .separator; line.translatesAutoresizingMaskIntoConstraints = false
                listStack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
            }
            let row = SettingsDestinationRow(name: destination.name, transport: destination.settings.transport.title, isDefault: destination.id == defaultID)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: SettingsDestinationRow.height).isActive = true
            row.widthAnchor.constraint(equalToConstant: Self.listWidth).isActive = true
            row.onClick = { [weak self] count in
                self?.select(id: destination.id)
                if count > 1 { self?.onEdit(destination) }
            }
            listStack.addArrangedSubview(row); rows.append(row)
        }
        let empty = list.destinations.isEmpty
        emptyLabel.isHidden = !empty
        emptyAddButton.isHidden = !empty
        if empty {
            let column = NSStackView(views: [emptyLabel, emptyAddButton])
            column.orientation = .vertical; column.alignment = .leading; column.spacing = DesignTokens.Space.s3
            let wrapper = NSView(); wrapper.translatesAutoresizingMaskIntoConstraints = false
            column.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(column)
            NSLayoutConstraint.activate([
                column.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: DesignTokens.Space.s4),
                column.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -DesignTokens.Space.s4),
                column.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: DesignTokens.Space.s3),
                column.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -DesignTokens.Space.s3),
                wrapper.widthAnchor.constraint(equalToConstant: Self.listWidth)])
            listStack.addArrangedSubview(wrapper)
        }
        // With destinations the four buttons sit under the list; with none the Add… inside the list is the only command.
        if isViewLoaded { grid.row(at: 2).isHidden = empty; grid.row(at: 3).isHidden = empty }
        let keep = selectedID.flatMap { id in list.destinations.first { $0.id == id }?.id }
        select(id: keep ?? defaultID ?? list.destinations.first?.id)
        listSurface.updateHeight()
        if isViewLoaded { contentChanged() }
    }

    @objc private func addTapped() { onAdd() }
    @objc private func editTapped() { if let selected = selectedDestination { onEdit(selected) } }
    @objc private func removeTapped() { if let selected = selectedDestination { onRemove(selected) } }
    @objc private func makeDefaultTapped() { if let selected = selectedDestination { onMakeDefault(selected) } }
}

/// One tab on the strip: an icon and a 20 pt label. It is a real NSButton with a title, so the G4 walker judges its text.
/// Rest, hover, pressed and selected are drawn as fills; selected adds a 1 pt accent border and an accent icon, the same cues
/// as the selected tool in the main chrome, so the state is never colour alone.
@MainActor
final class SettingsTabButton: NSButton {
    static let height = DesignTokens.Size.row
    static let horizontalPadding = DesignTokens.Space.s3
    private typealias Palette = DesignTokens.Palette

    let icon: FAIcon
    private(set) var isCurrent = false
    private(set) var isHovered = false
    private(set) var isPressed = false
    private var trackingArea: NSTrackingArea?
    /// The outline for Differentiate Without Color follows the system setting as it changes, not only when the tab is next selected.
    private var displayObservation: DisplayOptions.Observation?

    init(title: String, icon: FAIcon) {
        self.icon = icon
        super.init(frame: .zero)
        self.title = title
        isBordered = false; setButtonType(.momentaryChange); imagePosition = .imageLeading; imageHugsTitle = true
        image = ChromeIcons.resolve(icon, family: .solid, pointSize: DesignTokens.Typography.iconRegular).image
        refusesFirstResponder = true; focusRingType = .none
        wantsLayer = true; layer?.cornerRadius = DesignTokens.Radius.md
        identifier = NSUserInterfaceItemIdentifier("settingsTab." + title)
        setAccessibilityElement(true); setAccessibilityRole(.radioButton); setAccessibilityLabel(title)
        applyTitle()
        applyState()
        displayObservation = DisplayOptions.observe { [weak self] _ in self?.applyState() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 2 * Self.horizontalPadding, height: Self.height)
    }

    /// The title is attributed so its size and colour are ours and not the button style's.
    private func applyTitle() {
        let font = DesignTokens.Typography.font(.body)
        self.font = font; cell?.font = font
        attributedTitle = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: Palette.Text.primary])
    }

    func setCurrent(_ current: Bool) {
        isCurrent = current
        applyState()
    }

    override func accessibilityValue() -> Any? { isCurrent ? 1 : 0 }
    override func accessibilityPerformPress() -> Bool { performClick(nil); return true }

    // MARK: State

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyState()
    }

    private func applyState() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = Palette.accent
            contentTintColor = isCurrent ? accent : Palette.Text.secondary
            guard let layer else { return }
            if isCurrent {
                layer.backgroundColor = (isPressed ? accent.withAlphaComponent(0.32) : Palette.State.selectedFill).cgColor
                // Differentiate Without Color: the current tab is also a 2 pt outline in the text colour, a shape and not a tint alone.
                let outline = DisplayOptions.current.differentiateWithoutColor
                layer.borderColor = (outline ? Palette.Text.primary : accent).cgColor; layer.borderWidth = outline ? 2 : 1
            } else {
                layer.borderWidth = 0; layer.borderColor = nil
                layer.backgroundColor = (isPressed ? Palette.State.pressed : (isHovered ? Palette.State.hover : NSColor.clear)).cgColor
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); trackingArea = area
    }
    func setHovered(_ hovered: Bool) { isHovered = hovered; applyState() }
    func setPressed(_ pressed: Bool) { isPressed = pressed; applyState() }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    /// `super.mouseDown` tracks the whole click, so the pressed fill is on for exactly as long as the mouse is down.
    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        super.mouseDown(with: event)
        setPressed(false)
    }
}

/// The strip of tabs: a solid surface (Settings is a content window, and glass is for navigation), one key-view stop, the
/// Left and Right arrows move between tabs while it has focus, and it presents itself as a tab group.
@MainActor
final class SettingsTabStrip: NSView {
    static let verticalPadding = DesignTokens.Space.s2
    static let height = SettingsTabButton.height + 2 * verticalPadding

    let buttons: [SettingsTabButton]
    private(set) var selectedIndex = -1
    /// Called with the index the user asked for, by click or arrow key.
    var onSelect: ((Int) -> Void)?
    private let row: NSStackView

    init(items: [(title: String, icon: FAIcon)]) {
        buttons = items.map { SettingsTabButton(title: $0.title, icon: $0.icon) }
        row = NSStackView(views: buttons)
        super.init(frame: .zero)
        wantsLayer = true
        focusRingType = .none
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = DesignTokens.Space.s1
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor), row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: DesignTokens.Space.s3),
            heightAnchor.constraint(equalToConstant: Self.height)])
        for (index, button) in buttons.enumerated() {
            button.tag = index; button.target = self; button.action = #selector(tabClicked(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: SettingsTabButton.height).isActive = true
        }
        setAccessibilityElement(true); setAccessibilityRole(.tabGroup); setAccessibilityLabel("Settings sections")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The width the four tabs take side by side, so a test can hold it against the window width.
    var contentWidth: CGFloat { row.fittingSize.width }

    func select(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        for (position, button) in buttons.enumerated() { button.setCurrent(position == index) }
        noteFocusRingMaskChanged()
    }

    @objc private func tabClicked(_ sender: NSButton) { onSelect?(sender.tag) }

    // MARK: Surface

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = DesignTokens.Palette.Surface.window.cgColor }
    }

    // MARK: Keyboard

    override var acceptsFirstResponder: Bool { true }
    /// Like a system control, the strip shows its focus ring only when the keyboard put focus there (Tab, an arrow key, Full Keyboard
    /// Access) and not when the window merely opens with it as the first key view.
    private(set) var showsKeyboardFocus = false
    private func setKeyboardFocus(_ on: Bool) {
        guard showsKeyboardFocus != on else { return }
        showsKeyboardFocus = on
        focusRingType = on ? .exterior : .none
        noteFocusRingMaskChanged(); needsDisplay = true
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, NSApp.currentEvent?.type == .keyDown || NSApp.isFullKeyboardAccessEnabled { setKeyboardFocus(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        setKeyboardFocus(false)
        return super.resignFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, selectedIndex >= 0 else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123: setKeyboardFocus(true); onSelect?(max(0, selectedIndex - 1))
        case 124: setKeyboardFocus(true); onSelect?(min(buttons.count - 1, selectedIndex + 1))
        default: super.keyDown(with: event)
        }
    }

    private var focusRect: NSRect {
        guard buttons.indices.contains(selectedIndex) else { return .zero }
        return convert(buttons[selectedIndex].bounds, from: buttons[selectedIndex])
    }
    override var focusRingMaskBounds: NSRect { focusRect }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRect, xRadius: DesignTokens.Radius.md, yRadius: DesignTokens.Radius.md).fill()
    }

    // MARK: Accessibility

    override func accessibilityTabs() -> [Any]? { buttons }
    override func accessibilityValue() -> Any? { buttons.indices.contains(selectedIndex) ? buttons[selectedIndex] : nil }
    override func accessibilityChildren() -> [Any]? { buttons }
}

/// The scroll view's clip: top-down, so a tab shorter than the window sits at the top and a taller one starts at its first row.
@MainActor
final class SettingsClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// The window's content: the tab strip, a separator under it, and the selected tab in a scroll view. The scroll view only has
/// something to scroll when a screen is too short for the tab.
@MainActor
final class SettingsContentView: NSView {
    static let separatorHeight: CGFloat = 1
    static var chromeHeight: CGFloat { SettingsTabStrip.height + separatorHeight }

    let strip: SettingsTabStrip
    let scroll = NSScrollView()
    private let separator = NSBox()
    private(set) var tab: SettingsTabViewController?

    init(strip: SettingsTabStrip) {
        self.strip = strip
        super.init(frame: .zero)
        separator.boxType = .separator
        scroll.contentView = SettingsClipView()
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false; scroll.verticalScrollElasticity = .automatic
        for view in [strip, separator, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor), strip.leadingAnchor.constraint(equalTo: leadingAnchor), strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: strip.bottomAnchor), separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor), separator.heightAnchor.constraint(equalToConstant: Self.separatorHeight),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ tab: SettingsTabViewController) {
        self.tab = tab
        let document = tab.view
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: clip.topAnchor), document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor)])
        clip.scroll(to: .zero)
        scroll.reflectScrolledClipView(clip)
    }

    /// How far the shown tab runs past the bottom of the window; zero when it fits.
    var scrollableExtent: CGFloat {
        guard let document = scroll.documentView else { return 0 }
        layoutSubtreeIfNeeded()
        return max(0, document.frame.height - scroll.contentView.bounds.height)
    }
}

/// Escape and Command-W close it; so does the close button. It calls `onClose` so the owner decides what closing means.
/// Command-1 to Command-4 pick a tab.
@MainActor
class SettingsWindow: NSWindow {
    var onClose: (() -> Void)?
    /// Called with the tab index (0 to 3) for Command-1 to Command-4.
    var onSelectTab: ((Int) -> Void)?

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
        if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "w" { requestClose(); return true }
            if let key, let number = Int(key), (1...SettingsLayout.tabTitles.count).contains(number), attachedSheet == nil {
                onSelectTab?(number - 1); return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// One tab of the window: its label, its icon and the view controller that builds its form.
struct SettingsTabItem {
    let label: String
    let icon: FAIcon
    let viewController: SettingsTabViewController
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Where the window's frame is stored. The app passes it; a test leaves it out so nothing is written to defaults.
    static let autosaveName = "OpenSnap.Settings"
    /// The window class a new controller builds. The app's isolated tests substitute a subclass that never reaches the screen.
    static var windowClass: SettingsWindow.Type = SettingsWindow.self
    private static let icons: [FAIcon] = [.gear, .paintbrush, .crosshairs, .upload]

    let window: SettingsWindow
    let strip: SettingsTabStrip
    let content: SettingsContentView
    let model: SettingsPreferencesModel
    let general: GeneralSettingsTab, drawing: DrawingSettingsTab, capture: CaptureSettingsTab, upload: UploadSettingsTab
    let tabItems: [SettingsTabItem]
    private(set) var selectedIndex = -1
    private let stateProvider: () -> GeneralPreferencesState
    private var hasSavedFrame = false
    private var observers: [NSObjectProtocol] = []
    private var resizeTimer: Timer?
    private static let resizeDuration: TimeInterval = 0.2
    /// A window that is not on screen resizes at once; a test turns this on to watch the animation without ordering a window front.
    var animatesWhenHidden = false
    /// Under Reduce Motion the window changes size at once. A test replaces it.
    var reduceMotion: () -> Bool = { DisplayOptions.current.reduceMotion }
    /// The visible area of the screen the window is on. A test replaces it with a fake screen.
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
         destinations: @escaping () -> PublishingDestinationList, destinationActions: SettingsDestinationActions = SettingsDestinationActions(),
         frameAutosaveName: String? = nil) {
        self.destinationActions = destinationActions
        stateProvider = state
        model = SettingsPreferencesModel(state: state())
        window = Self.windowClass.init(contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: 300),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        general = GeneralSettingsTab(model: model); drawing = DrawingSettingsTab(model: model)
        capture = CaptureSettingsTab(defaults: defaults, hotkeys: hotkeys)
        self.hotkeys = hotkeys
        upload = UploadSettingsTab(destinations: destinations)
        let tabs: [SettingsTabViewController] = [general, drawing, capture, upload]
        tabItems = tabs.enumerated().map { SettingsTabItem(label: SettingsLayout.tabTitles[$0.offset], icon: Self.icons[$0.offset], viewController: $0.element) }
        strip = SettingsTabStrip(items: tabItems.map { ($0.label, $0.icon) })
        content = SettingsContentView(strip: strip)
        super.init()
        wireDestinationButtons()

        window.isReleasedWhenClosed = false
        window.delegate = self
        // The shortcuts pause only while this window is the one in front: leaving the app puts them back.
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.activityChanged(appActive: note.name == NSApplication.didBecomeActiveNotification) }
            }
        }
        window.contentView = content
        for tab in tabs {
            _ = tab.fittingHeight
            tab.onResize = { [weak self] in self?.fit(animated: self?.window.isVisible ?? false) }
        }
        strip.onSelect = { [weak self] in self?.select($0) }
        window.onSelectTab = { [weak self] in self?.select($0) }
        select(0, animated: false)
        if let frameAutosaveName { hasSavedFrame = window.setFrameAutosaveName(frameAutosaveName) }
        AppToolTip.install(on: content)

        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.upload.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    // MARK: Destinations

    private let destinationActions: SettingsDestinationActions
    private let hotkeys: any GlobalHotkeyEditing
    /// Whether the window is on screen, which with the Capture tab selected means the shortcut editor is open.
    private var isShown = false
    /// Whether this window is key and the app is active: the only time the shortcut editor can be in use.
    private var isKey = false, appIsActive = false
    /// The removal question on screen now, so a second click cannot stack another.
    private(set) var pendingRemoval: AppAlert?

    private func wireDestinationButtons() {
        upload.onAdd = { [weak self] in self?.editDestination(nil) }
        upload.onEdit = { [weak self] in self?.editDestination($0) }
        upload.onMakeDefault = { [weak self] destination in
            self?.perform { try $0.makeDefault(destination.id) }
        }
        upload.onRemove = { [weak self] destination in self?.confirmRemoval(of: destination) }
    }
    private func editDestination(_ destination: PublishingDestination?) {
        guard window.attachedSheet == nil else { return }
        destinationActions.edit(destination, window)
    }
    /// Runs a storage change, refreshes the list, and answers a failure with an alert on this window.
    private func perform(_ change: (SettingsDestinationActions) throws -> Void) {
        do { try change(destinationActions) } catch { AppAlert(error: error).present(on: window) { _ in } }
        upload.refresh()
    }
    /// "Remove “name”?" as a sheet on Settings. Cancel is first and the default, and Remove is the destructive second button, so a stray
    /// Return never deletes a destination.
    private func confirmRemoval(of destination: PublishingDestination) {
        guard pendingRemoval == nil, window.attachedSheet == nil else { return }
        let prompt = destinationActions.removalPrompt(destination)
        let alert = AppAlert(title: prompt.title, message: prompt.detail, buttons: [.init(title: "Cancel", role: .cancel), .init(title: "Remove", role: .destructive)])
        pendingRemoval = alert
        alert.present(on: window) { [weak self] response in
            guard let self else { return }
            self.pendingRemoval = nil
            guard response == .alertSecondButtonReturn else { return }
            self.perform { try $0.remove(destination.id) }
        }
    }

    var selectedTab: SettingsTabViewController { tabItems[max(0, selectedIndex)].viewController }

    func select(_ index: Int) { select(index, animated: true) }

    private func select(_ index: Int, animated: Bool) {
        guard tabItems.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        updateShortcutEditing()
        strip.select(index)
        content.show(tabItems[index].viewController)
        window.title = tabItems[index].label
        fit(animated: animated && (window.isVisible || animatesWhenHidden))
    }

    /// Shows what the parent stored: General and Drawing, the flash, the destinations. Delivers no edit.
    func refresh() {
        model.synchronize(stateProvider())
        capture.refresh(); upload.refresh()
    }

    /// The parent changed the stored preferences itself (a menu command), so the controls follow.
    func synchronize(_ state: GeneralPreferencesState) { model.synchronize(state) }

    /// The Capture tab: where the capture shortcuts are edited (the app menu's Capture Shortcuts… lands here).
    static let captureTabIndex = 2
    /// The Upload tab: where the destinations are listed and edited (the app menu's Sharing Settings… lands here).
    static let uploadTabIndex = 3

    func show(tab: Int? = nil) {
        if let tab { select(tab, animated: false) }
        refresh(); capture.reloadShortcuts()
        fit(animated: false)
        if !hasSavedFrame { window.center(); hasSavedFrame = true }
        window.makeKeyAndOrderFront(nil)
        isShown = true
        isKey = window.isKeyWindow; appIsActive = NSApp?.isActive ?? false
        updateShortcutEditing()
    }

    /// The owner took the window off screen (Escape, Command-W, the close button).
    func windowHidden() { isShown = false; isKey = false; updateShortcutEditing() }

    /// While the Capture tab is in front the global shortcuts are paused: edits are saved as they are made but go live as soon as the window
    /// is not the one being used (another window key, another app active, the tab left, the window hidden or closed), so a half-entered chord
    /// never starts working system-wide and pressing one to try it cannot start a capture. Merely leaving the window open pauses nothing (R2-001).
    private func updateShortcutEditing() {
        let editing = isShown && isKey && appIsActive && selectedIndex == Self.captureTabIndex
        hotkeys.setEditing(editing)
        capture.setShortcutsPaused(editing)
    }

    /// Window and app activity as the delegate and the application report it; a test drives it directly.
    func activityChanged(key: Bool? = nil, appActive: Bool? = nil) {
        if let key { isKey = key }
        if let appActive { appIsActive = appActive }
        updateShortcutEditing()
    }
    func windowDidBecomeKey(_ notification: Notification) { activityChanged(key: true, appActive: NSApp?.isActive ?? appIsActive) }
    func windowDidResignKey(_ notification: Notification) { activityChanged(key: false) }

    // MARK: Sizing

    /// The content height one tab asks for: its form plus the standard margins, so every tab is as tall as it needs and no taller (OSN
    /// F-J2-012). The window follows the tab it shows, top edge fixed.
    func contentHeight(forTabAt index: Int) -> CGFloat {
        if tabItems[index].viewController === upload { fitUploadList() }
        return tabItems[index].viewController.fittingHeight
    }

    /// Lets the destination list grow with its rows, up to what the screen leaves once the rest of the tab (margins, the Manage button,
    /// the caption) and the window's own title bar and strip are paid for. A longer list scrolls inside its frame, so the caption
    /// is never below the fold.
    private func fitUploadList() {
        upload.listMaximumHeight = .greatestFiniteMagnitude
        let others = upload.fittingHeight - upload.listHeight
        let chrome = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsContentView.chromeHeight)).height
        upload.listMaximumHeight = max(Self.minimumListHeight, visibleFrame().height - chrome - others)
    }
    /// Two destination rows: a screen too small for even that falls back to scrolling the whole tab.
    private static let minimumListHeight = 2 * SettingsDestinationRow.height

    /// The window frame a tab asks for: 640 wide, the strip plus the tab's own height, the top edge kept where it is.
    func frame(forTabAt index: Int, keepingTopOf current: NSRect) -> NSRect {
        let size = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth,
                                                           height: SettingsContentView.chromeHeight + contentHeight(forTabAt: index))).size
        return NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
    }

    /// The whole window height a tab needs, title bar and tab strip included.
    func windowHeight(forTabAt index: Int) -> CGFloat { frame(forTabAt: index, keepingTopOf: window.frame).height }

    func fit(animated: Bool) {
        guard selectedIndex >= 0 else { return }
        var target = frame(forTabAt: selectedIndex, keepingTopOf: window.frame)
        let visible = visibleFrame()
        // A tab taller than the screen is capped to it: the scroll view in the content scrolls the rest.
        if target.height > visible.height { target.size.height = visible.height }
        if target.maxY > visible.maxY { target.origin.y = visible.maxY - target.height }
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

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard window.onClose != nil else { return true }
        window.requestClose()
        return false
    }
}
