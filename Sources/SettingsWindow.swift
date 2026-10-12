import AppKit

// The Settings window: four tabs (General, Drawing, Capture, Upload) on an app-owned strip at the top of the content, no Done
// button, every change applied at once. It is self-contained: the app hands it closures for the things it owns (stored
// preferences, the shortcut manager, the destination list, the destinations sheet) and it owns nothing else, so a test can build
// it with in-memory stand-ins. The strip is ours, not an NSToolbar's, because AppKit draws toolbar labels at about 13 pt and an
// app-owned label is 20 pt. The title bar text is the one thing the OS still sets; it follows the selected tab.
//
// Every choice the app owns is a Liquid Glass button: one glass plate per related group (the four tabs; each radio set; related
// check boxes; the Upload commands), and the buttons on a plate draw their own state fills, so there is never glass inside glass. The
// destination list and the shortcut recorders are content and form fields, and stay solid and native.

/// Sizes and row builders shared by the four tabs, so every tab is the same aligned form grid.
@MainActor
enum SettingsLayout {
    private typealias Typography = DesignTokens.Typography
    private typealias Space = DesignTokens.Space

    static let tabTitles = ["General", "Drawing", "Capture", "Upload"]
    static let contentWidth: CGFloat = 640
    static let horizontalMargin = Space.s6, verticalMargin = Space.s5
    static let rowSpacing = Space.s4, columnSpacing = Space.s4

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

    /// A row label: right-aligned in the label column, 20 pt semibold. When it names a control (`naming`), that control carries the name for
    /// assistive clients and this text is only drawn, so VoiceOver reads "Show in, radio group" once, not "Show in:" and then the group.
    static func rowLabel(_ text: String, naming target: NSView? = nil) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = Typography.font(.bodyStrong); field.alignment = .right
        field.textColor = DesignTokens.Palette.Text.primary
        if let target {
            if target.accessibilityLabel()?.isEmpty != false { target.setAccessibilityLabel(text.trimmingCharacters(in: CharacterSet(charactersIn: ": "))) }
            field.hideFromAccessibility("row-label")
        }
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

    /// A checkbox: a toggle choice (square glyph, filled with a check while on) that sends its action when it flips. With `wrapWidth` the title wraps
    /// at that width and the row grows to hold the lines.
    static func toggle(_ title: String, identifier: String, target: AnyObject, action: Selector, wrapWidth: CGFloat? = nil) -> GlassChoiceButton {
        let button = GlassChoiceButton(title: title, kind: .toggle, indicator: .checkbox, layout: .row)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = target; button.action = action
        button.accessibility = ChromeAccessibility.live
        button.wrapWidth = wrapWidth
        return button
    }

    /// The width a toggle's title may take inside a plate `plateWidth` wide: the plate's inset, the button's padding and its checkbox glyph are paid for first.
    static func toggleTextWidth(inPlateOfWidth plateWidth: CGFloat) -> CGFloat {
        plateWidth - 2 * togglePlateInset - 2 * GlassChoiceButton.padding - GlassChoiceButton.glyphSide - GlassChoiceButton.gap
    }

    /// A toggle row is as wide as its plate, so its keyboard focus ring (4 pt out from the row) would sit on the plate's border at the plate's
    /// usual 4 pt inset; a toggle plate is inset by 8 so the ring stands off it.
    static let togglePlateInset = DesignTokens.Space.s2

    /// One glass plate around related toggles, one row each. It is an accessibility group with a name.
    static func togglePlate(_ toggles: [GlassChoiceButton], identifier: String, label: String) -> GlassSurfaceView {
        let plate = GlassChrome.plate(toggles, identifier: identifier, accessibility: ChromeAccessibility.live, axis: .vertical, inset: togglePlateInset)
        plate.setAccessibilityElement(true); plate.setAccessibilityLabel(label); plate.setAccessibilityRole(.group)
        return plate
    }

    /// A radio set: exclusive choices on ONE plate with a radio glyph each, one tab stop, arrows move the choice. The plate is inset like a toggle
    /// plate, so the ring of the segment at either end stands off the plate's edge instead of sitting on it. Each button keeps its own
    /// `tag` (the stored value it stands for) and identifier; `action` goes to `target` once per user change, with the group as sender.
    static func radioGroup(_ choices: [(title: String, tag: Int, identifier: String)], label: String, identifier: String, target: AnyObject, action: Selector) -> GlassChoiceGroup {
        let group = GlassChoiceGroup(choices: choices.map { GlassChoiceGroup.Choice($0.title, identifier: $0.identifier) }, selectedIndex: -1, layout: .segment,
                                     axis: .horizontal, indicator: .radio, accessibilityLabel: label, identifier: identifier,
                                     plateInset: togglePlateInset)
        for (button, choice) in zip(group.buttons, choices) { button.tag = choice.tag }
        group.target = target; group.action = action
        return group
    }

    /// The stored value of the chosen button, or nil when nothing is chosen.
    static func chosenTag(of group: GlassChoiceGroup) -> Int? { group.buttons.indices.contains(group.selectedIndex) ? group.buttons[group.selectedIndex].tag : nil }
    /// Chooses the button that stands for `tag` without sending the action; none matches, none is chosen.
    static func choose(tag: Int, in group: GlassChoiceGroup) { group.selectedIndex = group.buttons.firstIndex { $0.tag == tag } ?? -1 }

    /// Where the first line of a choice's text sits below the top of its plate: the plate's inset, the padding above the line and the line's
    /// own baseline. A grid row aligns its label to this, so the label sits on the same baseline as the first choice and not on the plate's edge.
    static func firstChoiceBaseline(of button: GlassChoiceButton?, inset: CGFloat = GlassChrome.Metrics.groupInset) -> CGFloat {
        let font = Typography.font(.bodyStrong)
        let line = ceil(font.boundingRectForFont.height)
        let probe = NSTextField(labelWithString: "Ag")
        probe.font = font; probe.frame = NSRect(x: 0, y: 0, width: 120, height: line)
        let rowHeight = button?.intrinsicContentSize.height ?? GlassChoiceButton.height
        // A wrapped row is its lines plus the row padding; a one-line row is a control high with the line centred.
        let above = rowHeight > GlassChoiceButton.height ? Space.s2 : ((GlassChoiceButton.height - line) / 2).rounded()
        return inset + above + probe.firstBaselineOffsetFromTop
    }

    /// A titled command for an action plate: the chrome's command button, so it draws its own rest, hover, pressed, focus and disabled fills.
    static func actionButton(_ title: String, identifier: String, target: AnyObject, action: Selector) -> SettingsActionButton {
        let button = SettingsActionButton(title: title, target: target, action: action)
        button.configure()
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        return button
    }

    /// One glass plate around a group of commands. It is an accessibility group with a name, so VoiceOver announces what the buttons belong to.
    static func actionPlate(_ buttons: [SettingsActionButton], identifier: String, label: String) -> GlassSurfaceView {
        let plate = GlassChrome.plate(buttons, identifier: identifier, accessibility: ChromeAccessibility.live)
        plate.setAccessibilityElement(true); plate.setAccessibilityLabel(label); plate.setAccessibilityRole(.group)
        return plate
    }
}

/// A grid cell around a plate (or a radio group): the cell reports the first line of the plate's text as its baseline, so a row's label
/// lines up with the first choice. A glass plate has no baseline of its own, and the grid would sit the label on the plate's bottom edge.
@MainActor
final class SettingsPlateCell: NSView {
    let content: NSView
    private let baseline: CGFloat

    init(_ content: NSView, firstChoice: GlassChoiceButton?) {
        self.content = content
        baseline = SettingsLayout.firstChoiceBaseline(of: firstChoice, inset: (content as? GlassSurfaceView)?.inset ?? (content as? GlassChoiceGroup)?.plate.inset ?? GlassChrome.Metrics.groupInset)
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var firstBaselineOffsetFromTop: CGFloat { baseline }
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
    /// The container the tab's grid sits in, and with it every glass plate of the tab.
    private(set) var glassContainer = NSGlassEffectContainerView()
    /// A tab whose content changed height asks the window to refit.
    var onResize: (() -> Void)?
    /// The label and control column widths of this tab's grid. A subclass with a short form sets them in `makeRows`.
    var labelWidth = SettingsLayout.labelColumnWidth
    var controlWidth = SettingsLayout.controlColumnWidth

    /// Rows of [label, control]; a row with no label uses `NSGridCell.emptyContentView`. Subclasses override.
    func makeRows() -> [[NSView]] { [] }

    /// The glass plates of this tab and the controls drawn on them, kept in step with the display options (Reduce Transparency, Increase
    /// Contrast, Reduce Motion, Differentiate Without Color) for as long as the tab lives.
    private(set) var plates: [GlassSurfaceView] = []
    private var plateControls: [ChromeFillable] = []
    private var displayObservation: DisplayOptions.Observation?

    /// Registers plates and the controls drawn on them (a radio group is both); they take the live display options now and whenever the user changes them.
    func adopt(plates newPlates: [GlassSurfaceView] = [], controls: [ChromeFillable] = []) {
        plates += newPlates; plateControls += controls
        applyDisplayOptions()
    }
    private func applyDisplayOptions() {
        let options = ChromeAccessibility.live
        for plate in plates { plate.accessibility = options }
        for control in plateControls { control.accessibility = options }
    }
    /// Re-reads whatever the tab shows from its source of truth. Delivers nothing.
    func refresh() {}

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        // Content width unless the scroll view says otherwise: a scroll bar that takes room leaves the grid centred in what is left.
        let width = root.widthAnchor.constraint(equalToConstant: SettingsLayout.contentWidth)
        width.priority = .defaultHigh; width.isActive = true
        grid = NSGridView(views: makeRows())
        displayObservation = DisplayOptions.observe { [weak self] _ in self?.applyDisplayOptions() }
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = SettingsLayout.rowSpacing; grid.columnSpacing = SettingsLayout.columnSpacing
        grid.column(at: 0).xPlacement = .trailing; grid.column(at: 0).width = labelWidth
        grid.column(at: 1).xPlacement = .leading; grid.column(at: 1).width = controlWidth
        for index in 0..<grid.numberOfRows { grid.row(at: index).rowAlignment = .firstBaseline }
        // The glass plates of a tab share one container, so nearby glass is drawn in one pass and never samples another plate.
        glassContainer = GlassChrome.container(around: grid, identifier: "SettingsTabPlates")
        root.addSubview(glassContainer)
        NSLayoutConstraint.activate([
            glassContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: SettingsLayout.verticalMargin),
            glassContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -SettingsLayout.verticalMargin),
            glassContainer.centerXAnchor.constraint(equalTo: root.centerXAnchor)])
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
    /// Where OpenSnap shows: Dock (2), Menu bar (1), Both (0). One radio set on one plate.
    private(set) var presenceGroup: GlassChoiceGroup!
    var presenceButtons: [NSButton] { presenceGroup?.buttons ?? [] }
    private(set) var snapCheckbox: GlassChoiceButton!, hoverHintsCheckbox: GlassChoiceButton!, keyboardTipsCheckbox: GlassChoiceButton!
    /// The plates the toggles sit on: the snap sentence on its own, the two hint options together.
    private(set) var snapPlate: GlassSurfaceView!, hintsPlate: GlassSurfaceView!

    init(model: SettingsPreferencesModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = "General"
        model.observe { [weak self] in self?.refresh() }
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }

    override func makeRows() -> [[NSView]] {
        presenceGroup = SettingsLayout.radioGroup([("Dock", 2, "presenceDock"), ("Menu bar", 1, "presenceMenuBar"), ("Both", 0, "presenceBoth")],
                                                  label: "Show in", identifier: "SettingsPresence", target: self, action: #selector(changePresence(_:)))
        hoverHintsCheckbox = SettingsLayout.toggle("Show hover hints for tools", identifier: "showToolTips", target: self, action: #selector(changeHoverHints(_:)))
        keyboardTipsCheckbox = SettingsLayout.toggle("Show keyboard tip overlay", identifier: "showKeyboardTips", target: self, action: #selector(changeKeyboardTips(_:)))
        hintsPlate = SettingsLayout.togglePlate([hoverHintsCheckbox, keyboardTipsCheckbox], identifier: "SettingsHints", label: "Hints")
        // The form is as wide as its widest control and no wider, so the window centres it; the long snap sentence wraps inside that width.
        labelWidth = SettingsLayout.labelWidth(for: Self.rowLabels)
        let available = SettingsLayout.availableControlWidth(labelWidth: labelWidth)
        controlWidth = min(available, ceil(max(presenceGroup.fittingSize.width, hintsPlate.fittingSize.width, Self.minimumControlWidth)))
        snapCheckbox = SettingsLayout.toggle("Show OpenSnap window in fullscreen and crosshair snaps", identifier: "includeApp", target: self,
                                             action: #selector(changeSnap(_:)), wrapWidth: SettingsLayout.toggleTextWidth(inPlateOfWidth: controlWidth))
        snapPlate = SettingsLayout.togglePlate([snapCheckbox], identifier: "SettingsSnapping", label: "Snapping")
        adopt(plates: [snapPlate, hintsPlate], controls: [presenceGroup, snapCheckbox, hoverHintsCheckbox, keyboardTipsCheckbox])
        let rows: [[NSView]] = [
            [SettingsLayout.rowLabel("Show in:", naming: presenceGroup), SettingsPlateCell(presenceGroup, firstChoice: presenceGroup.buttons.first)],
            [SettingsLayout.rowLabel("Snapping:", naming: snapPlate), SettingsPlateCell(snapPlate, firstChoice: snapCheckbox)],
            [SettingsLayout.rowLabel("Hints:", naming: hintsPlate), SettingsPlateCell(hintsPlate, firstChoice: hoverHintsCheckbox)]]
        defer { refresh() }
        return rows
    }

    override func loadView() {
        super.loadView()
        // A checked option is a filled chip as wide as its plate: every checkbox plate of the tab is as wide as the widest, so the
        // chips match whichever options are on.
        hintsPlate.widthAnchor.constraint(equalTo: snapPlate.widthAnchor).isActive = true
    }

    override func refresh() {
        guard presenceGroup != nil else { return }
        let state = model.state
        SettingsLayout.choose(tag: state.statusMenu, in: presenceGroup)
        snapCheckbox.state = state.includeApp ? .on : .off
        hoverHintsCheckbox.state = state.showToolTips ? .on : .off
        keyboardTipsCheckbox.state = state.showKeyboardTips ? .on : .off
    }

    @objc private func changePresence(_ sender: GlassChoiceGroup) {
        guard let tag = SettingsLayout.chosenTag(of: sender) else { return }
        model.edit { $0.statusMenu = tag }
    }
    @objc private func changeSnap(_ sender: NSButton) { model.edit { $0.includeApp = sender.state == .on } }
    @objc private func changeHoverHints(_ sender: NSButton) { model.edit { $0.showToolTips = sender.state == .on } }
    @objc private func changeKeyboardTips(_ sender: NSButton) { model.edit { $0.showKeyboardTips = sender.state == .on } }
}

@MainActor
final class DrawingSettingsTab: SettingsTabViewController {
    static let rowLabels = ["Drawing precision:", "Arrow head:"]
    private static let note = "Holding Option reverses the setting."
    let model: SettingsPreferencesModel
    /// Precise (0), Medium (1), Loose (2); End (2), Start (1). Each is one radio set on one plate.
    private(set) var precisionGroup: GlassChoiceGroup!, arrowGroup: GlassChoiceGroup!
    var precisionButtons: [NSButton] { precisionGroup?.buttons ?? [] }
    var arrowButtons: [NSButton] { arrowGroup?.buttons ?? [] }

    init(model: SettingsPreferencesModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = "Drawing"
        model.observe { [weak self] in self?.refresh() }
    }
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }

    override func makeRows() -> [[NSView]] {
        precisionGroup = SettingsLayout.radioGroup([("Precise", 0, "precisionPrecise"), ("Medium", 1, "precisionMedium"), ("Loose", 2, "precisionLoose")],
                                                   label: "Drawing precision", identifier: "SettingsPrecision", target: self, action: #selector(changePrecision(_:)))
        arrowGroup = SettingsLayout.radioGroup([("End", 2, "arrowEnd"), ("Start", 1, "arrowStart")],
                                               label: "Arrow head", identifier: "SettingsArrowHead", target: self, action: #selector(changeArrow(_:)))
        adopt(controls: [precisionGroup, arrowGroup])
        labelWidth = SettingsLayout.labelWidth(for: Self.rowLabels)
        controlWidth = min(SettingsLayout.availableControlWidth(labelWidth: labelWidth),
                           ceil(max(precisionGroup.fittingSize.width, arrowGroup.fittingSize.width, SettingsLayout.captionWidth(Self.note))))
        let rows: [[NSView]] = [
            [SettingsLayout.rowLabel("Drawing precision:", naming: precisionGroup), SettingsPlateCell(precisionGroup, firstChoice: precisionGroup.buttons.first)],
            [SettingsLayout.rowLabel("Arrow head:", naming: arrowGroup), SettingsPlateCell(arrowGroup, firstChoice: arrowGroup.buttons.first)],
            [NSGridCell.emptyContentView, SettingsLayout.caption(Self.note, width: controlWidth)]]
        defer { refresh() }
        return rows
    }

    override func refresh() {
        guard precisionGroup != nil else { return }
        let state = model.state
        let precision: Int
        switch state.drawingPrecision { case .precise: precision = 0; case .medium: precision = 1; case .loose: precision = 2 }
        SettingsLayout.choose(tag: precision, in: precisionGroup)
        SettingsLayout.choose(tag: state.arrowHead, in: arrowGroup)
    }

    @objc private func changePrecision(_ sender: GlassChoiceGroup) {
        guard let tag = SettingsLayout.chosenTag(of: sender) else { return }
        model.edit {
            switch tag { case 0: $0.drawingPrecision = .precise; case 2: $0.drawingPrecision = .loose; default: $0.drawingPrecision = .medium }
        }
    }
    @objc private func changeArrow(_ sender: GlassChoiceGroup) {
        guard let tag = SettingsLayout.chosenTag(of: sender) else { return }
        model.edit { $0.arrowHead = tag }
    }
}

@MainActor
final class CaptureSettingsTab: SettingsTabViewController {
    private let defaults: UserDefaults
    private let hotkeys: any GlobalHotkeyEditing
    private(set) var flashCheckbox: GlassChoiceButton!
    private(set) var flashPlate: GlassSurfaceView!
    private(set) var hotkeyForm: GlobalHotkeyForm!

    init(defaults: UserDefaults, hotkeys: any GlobalHotkeyEditing) {
        self.defaults = defaults; self.hotkeys = hotkeys
        super.init(nibName: nil, bundle: nil)
        title = "Capture"
    }
    required init?(coder: NSCoder) { fatalError("Use init(defaults:hotkeys:)") }

    override func makeRows() -> [[NSView]] {
        flashCheckbox = SettingsLayout.toggle("Show capture flash", identifier: "showCaptureFlash", target: self, action: #selector(changeFlash(_:)))
        flashPlate = SettingsLayout.togglePlate([flashCheckbox], identifier: "SettingsFlash", label: "Flash")
        adopt(plates: [flashPlate], controls: [flashCheckbox])
        hotkeyForm = GlobalHotkeyForm(manager: hotkeys, labelWidth: SettingsLayout.labelColumnWidth, width: SettingsLayout.gridWidth)
        hotkeyForm.translatesAutoresizingMaskIntoConstraints = false
        hotkeyForm.onResize = { [weak self] in
            // The status line wraps to one line or more; the grid has not laid it out yet.
            DispatchQueue.main.async { self?.contentChanged() }
        }
        hotkeyForm.setShortcutsPaused(shortcutsPaused)
        defer { refresh() }
        return [[SettingsLayout.rowLabel("Flash:", naming: flashPlate), SettingsPlateCell(flashPlate, firstChoice: flashCheckbox)], [hotkeyForm, NSGridCell.emptyContentView]]
    }

    override func loadView() {
        super.loadView()
        grid.row(at: 1).mergeCells(in: NSRange(location: 0, length: 2))
        grid.row(at: 1).yPlacement = .top
        // Flash and Shortcuts are both one checkbox on a plate: the same width, so a checked chip is the same size on either.
        if let enabledPlate = hotkeyForm.enabledPlate { flashPlate.widthAnchor.constraint(equalTo: enabledPlate.widthAnchor).isActive = true }
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
        transportField.textColor = isSelected ? DesignTokens.Palette.Text.secondaryOnSelected : DesignTokens.Palette.Text.secondary
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
    /// Which row the buttons below act on, said in words as well as by the selected trait.
    override func accessibilityValue() -> Any? { isSelected ? "Selected" : nil }

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
        setAccessibilityLabel([name, transport.replacingOccurrences(of: " · ", with: ", "), isDefault ? "Default" : nil].compactMap { $0 }.joined(separator: ", "))
        refreshMark()
        displayObservation = DisplayOptions.observe { [weak self] _ in self?.refreshMark(); self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The row reads as one element, "Work, WebDAV, Default", in the order the eye reads it. The name, transport and Default pill are
    /// not exposed separately: the pill is taller than the name, so as a sibling it was read first.
    override func accessibilityChildren() -> [Any]? { [] }
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
    private(set) var addButton: SettingsActionButton!, editButton: SettingsActionButton!, removeButton: SettingsActionButton!, defaultButton: SettingsActionButton!
    /// The Add… button inside an empty list; with destinations the plate of four buttons below the list takes over.
    private(set) var emptyAddButton: SettingsActionButton!
    /// The glass plates the buttons sit on: one for the four commands, one for the lone Add… in the empty list.
    private(set) var actionPlate: GlassSurfaceView!, emptyAddPlate: GlassSurfaceView!
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
        addButton = SettingsLayout.actionButton("Add…", identifier: "addDestination", target: self, action: #selector(addTapped))
        editButton = SettingsLayout.actionButton("Edit…", identifier: "editDestination", target: self, action: #selector(editTapped))
        removeButton = SettingsLayout.actionButton("Remove", identifier: "removeDestination", target: self, action: #selector(removeTapped))
        defaultButton = SettingsLayout.actionButton("Make Default", identifier: "makeDefaultDestination", target: self, action: #selector(makeDefaultTapped))
        emptyAddButton = SettingsLayout.actionButton("Add…", identifier: "addFirstDestination", target: self, action: #selector(addTapped))
        actionPlate = SettingsLayout.actionPlate([addButton, editButton, removeButton, defaultButton], identifier: "SettingsDestinationActions", label: "Destination actions")
        emptyAddPlate = SettingsLayout.actionPlate([emptyAddButton], identifier: "SettingsFirstDestinationAction", label: "First destination")
        adopt(plates: [actionPlate, emptyAddPlate], controls: [addButton, editButton, removeButton, defaultButton, emptyAddButton])
        hintLabel = SettingsLayout.caption(Self.hint, width: Self.listWidth)
        defer { refresh() }
        let heading = NSTextField(labelWithString: "Destinations")
        heading.font = DesignTokens.Typography.font(.bodyStrong); heading.textColor = DesignTokens.Palette.Text.primary
        heading.setAccessibilityRole(.staticText)
        return [[NSGridCell.emptyContentView, heading],
                [NSGridCell.emptyContentView, listSurface],
                [NSGridCell.emptyContentView, actionPlate],
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
        emptyAddButton.isHidden = !empty; emptyAddPlate.isHidden = !empty
        if empty {
            let column = NSStackView(views: [emptyLabel, emptyAddPlate])
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

/// One tab on the strip: an icon and a 20 pt label on the strip's glass plate. It is the chrome's `CommandButton`, so it is a real
/// NSButton with a title (the G4 walker judges its text) and its rest, hover, pressed and selected states are the fills `StatePlate` draws
/// from `StateStyles.command`: selected is the accent fill, a 1 pt accent border, a semibold label and a solid glyph, and Differentiate
/// Without Color adds the capsule under the glyph, so the current tab is never colour alone.
@MainActor
final class SettingsTabButton: CommandButton {
    static let height = GlassChrome.Metrics.commandHeight
    static let horizontalPadding = DesignTokens.Space.s3
    private typealias Typography = DesignTokens.Typography

    init(title: String, icon: FAIcon) {
        super.init(frame: .zero)
        GlassChrome.useExtraLarge(self)
        Typography.apply(.body, to: self)
        iconPointSize = Typography.iconInline
        iconFamily = .solid; selectedFamily = .solid
        self.icon = icon
        self.title = title
        refusesFirstResponder = true
        identifier = NSUserInterfaceItemIdentifier("settingsTab." + title)
        setAccessibilityElement(true); setAccessibilityRole(.radioButton); setAccessibilityLabel(title)
        // The label is drawn from an attributed string: the button's own title field would keep the system's 13 pt and take no state colour.
        plate.onApply = { [weak self] _ in self?.styleTitle() }
        styleTitle()
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.width(for: title)).isActive = true
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The width of a tab: its glyph, the gap, the label in the strong weight (so choosing a tab never moves its neighbours) and the padding.
    static func width(for title: String) -> CGFloat {
        let label = ceil((title as NSString).size(withAttributes: [.font: Typography.font(.bodyStrong)]).width)
        return label + Typography.iconInline + DesignTokens.Space.s2 + 2 * horizontalPadding
    }

    /// The label in the weight and colour the state resolved: semibold while this is the current tab.
    private func styleTitle() {
        let text = visibleTitle
        guard !text.isEmpty else { return }
        let style = plate.stateStyle
        attributedTitle = NSAttributedString(string: text, attributes: [.font: Typography.font(style.strongText ? .bodyStrong : .body), .foregroundColor: style.content])
    }

    var isCurrent: Bool { state == .on }
    func setCurrent(_ current: Bool) { state = current ? .on : .off }

    override var title: String {
        didSet { styleTitle() }
    }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.width(for: visibleTitle), height: Self.height) }

    override func accessibilityValue() -> Any? { isCurrent ? 1 : 0 }
    override func accessibilityPerformPress() -> Bool { performClick(nil); return true }
}

/// The strip of tabs: the four tabs share ONE glass plate (the only glass in it; the tabs draw their own state fills) in the bar's glass
/// container, over the window surface. It is one key-view stop, the Left and Right arrows move between tabs while it has focus, and it
/// presents itself as a tab group.
@MainActor
final class SettingsTabStrip: NSView, TokenFocusRinged {
    static let verticalPadding = DesignTokens.Space.s2
    static let height = GlassChrome.Metrics.headerHeight + 2 * verticalPadding

    let buttons: [SettingsTabButton]
    /// The one glass plate the tabs sit on, and the container that shares its render pass.
    let plate: GlassSurfaceView
    let container: NSGlassEffectContainerView
    private(set) var selectedIndex = -1
    /// Called with the index the user asked for, by click or arrow key.
    var onSelect: ((Int) -> Void)?
    private var displayObservation: DisplayOptions.Observation?

    init(items: [(title: String, icon: FAIcon)]) {
        buttons = items.map { SettingsTabButton(title: $0.title, icon: $0.icon) }
        plate = GlassChrome.plate(buttons, identifier: "SettingsTabBar", accessibility: ChromeAccessibility.live)
        container = GlassChrome.container(around: plate, identifier: "SettingsTabs")
        super.init(frame: .zero)
        wantsLayer = true
        _ = tokenRing
        addSubview(container)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: centerXAnchor), container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: DesignTokens.Space.s3),
            heightAnchor.constraint(equalToConstant: Self.height)])
        for (index, button) in buttons.enumerated() {
            button.tag = index; button.target = self; button.action = #selector(tabClicked(_:))
            button.accessibility = ChromeAccessibility.live
        }
        displayObservation = DisplayOptions.observe { [weak self] _ in
            guard let self else { return }
            let options = ChromeAccessibility.live
            self.plate.accessibility = options
            for button in self.buttons { button.accessibility = options }
        }
        setAccessibilityElement(true); setAccessibilityRole(.tabGroup); setAccessibilityLabel("Settings sections")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The width the four tabs take side by side, so a test can hold it against the window width.
    var contentWidth: CGFloat { plate.fittingSize.width }

    func select(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        for (position, button) in buttons.enumerated() { button.setCurrent(position == index) }
        tokenRing.refresh()
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
    /// The ring is the app's token ring around the selected tab, shown only for keyboard focus.
    private(set) lazy var tokenRing = TokenFocusRing(view: self, target: { [unowned self] in focusRect })
    override var focusRingType: NSFocusRingType { get { .none } set {} }
    private func setKeyboardFocus(_ on: Bool) {
        guard showsKeyboardFocus != on else { return }
        showsKeyboardFocus = on
        tokenRing.setFocused(on)
        needsDisplay = true
    }
    override func layout() { super.layout(); tokenRing.refresh() }
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
        guard event.chordModifiers.isEmpty, selectedIndex >= 0 else { return super.keyDown(with: event) }
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
    /// Called just before a sheet hangs from this window, so the owner can make room for it.
    var onSheetWillBegin: ((NSWindow) -> Void)?
    override func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        onSheetWillBegin?(sheetWindow)
        super.beginSheet(sheetWindow, completionHandler: handler)
    }

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
        if event.keyCode == 53, event.chordModifiers.isEmpty { cancelOperation(nil) }
        else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.chordModifiers == .command {
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
    static let resizeDuration: TimeInterval = 0.2
    /// The animation's clock. A test replaces it, so the frames of the resize are asked for at chosen moments instead of waited for.
    var clock: () -> Date = Date.init
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
            MainActor.assumeIsolated { self?.upload.refresh(); self?.sheetDidEnd() }
        })
        window.onSheetWillBegin = { [weak self] sheet in self?.sheetWillBegin(sheet) }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The key came back from this window's own choice panel: nothing outside changed, so nothing is re-read (a draft the manager rejected stays).
                if self.choicePanelHasKey { self.choicePanelHasKey = false } else { self.refresh() }
            }
        })
        // A window other than this one and its panel took the key while a panel held it: the panel's close did not bring the key back here.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.choicePanelHasKey, let other = note.object as? NSWindow, other !== self.window, !(other is GlassChoiceWindow) else { return }
                self.choicePanelHasKey = false
                self.activityChanged(key: false)
            }
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
    /// Whether the application is active, when a test needs to say so (a test application never is). Nil reads the real application.
    var applicationActivity: (() -> Bool)?
    func windowDidBecomeKey(_ notification: Notification) { activityChanged(key: true, appActive: applicationActivity?() ?? NSApp?.isActive ?? appIsActive) }

    /// A choice panel that is a child of this window (a key pop-up's glass panel) takes the key while the user chooses. Settings is still the
    /// window in use then: the shortcuts stay paused, the note stays as it is and a rejected draft keeps its error, so nothing is re-registered
    /// or re-read under the panel.
    private var choicePanelHasKey = false
    private var hasChoicePanel: Bool { window.childWindows?.contains { $0 is GlassChoiceWindow } ?? false }

    func windowDidResignKey(_ notification: Notification) {
        if hasChoicePanel { choicePanelHasKey = true; return }
        activityChanged(key: false)
    }

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

    // MARK: A sheet is never larger than the window it hangs from

    /// The size of the sheet hanging from the window now. The window grows tall enough to hold it (a taller sheet would hang off the bottom
    /// edge; the width is the sheet's own business, `PublishingDestinationsView.sheetWidth(forHostWidth:)` keeps it within the window) and goes back to the tab's own size when the sheet is gone.
    private(set) var sheetSize: NSSize?
    private var sheetResizeObserver: NSObjectProtocol?

    func sheetWillBegin(_ sheet: NSWindow) {
        sheetSize = sheet.frame.size
        if let sheetResizeObserver { NotificationCenter.default.removeObserver(sheetResizeObserver) }
        // The destination form hugs its content, so the sheet changes height as the protocol changes; the window follows it.
        sheetResizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: sheet, queue: .main) { [weak self, weak sheet] _ in
            MainActor.assumeIsolated {
                guard let self, let sheet, self.sheetSize != nil else { return }
                self.sheetSize = sheet.frame.size
                self.fit(animated: false)
            }
        }
        fit(animated: false)
    }

    func sheetDidEnd() {
        if let sheetResizeObserver { NotificationCenter.default.removeObserver(sheetResizeObserver) }
        sheetResizeObserver = nil
        guard sheetSize != nil else { return }
        sheetSize = nil
        fit(animated: false)
    }

    func fit(animated: Bool) {
        guard selectedIndex >= 0 else { return }
        var target = frame(forTabAt: selectedIndex, keepingTopOf: window.frame)
        if let sheetSize {
            // The sheet hangs from the content's top edge: its bottom is the title bar plus its own height below the window's top.
            let titleBar = window.frameRect(forContentRect: .zero).height
            let height = max(target.height, sheetSize.height + titleBar)
            target.origin.y = target.maxY - height; target.size.height = height
        }
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
        let began = clock()
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let progress = min(1, self.clock().timeIntervalSince(began) / Self.resizeDuration)
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
