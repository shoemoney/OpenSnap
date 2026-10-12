import AppKit

/// The status line. When its visible text is a shortened hint, `spokenValue` carries the full sentence for VoiceOver
/// (NSTextField would otherwise always speak its string value).
///
/// `setVariants` hands it the same status from longest to shortest; it shows the first one that fits whole in its
/// current width, so a narrow window drops the low-priority parts (bytes, then tool) instead of tail-cutting the state.
/// If even the last variant does not fit, plain tail truncation applies to it. Any direct `stringValue` write is a single
/// fixed text and clears the variants.
final class StatusTextField: NSTextField {
    var spokenValue: String?
    private(set) var variants: [String] = []
    private var settingVariant = false

    override var stringValue: String {
        get { super.stringValue }
        set {
            if !settingVariant { variants = Self.withShortForm([newValue]).count > 1 ? Self.withShortForm([newValue]) : [] }
            super.stringValue = newValue
        }
    }

    /// A save notice names its file ("Saved Quarterly mockup.opensnap"), which the window title already says; where the slot cannot hold the
    /// whole line it keeps the word alone ("Saved") and the tooltip keeps the name, instead of cutting the name mid-word.
    static func withShortForm(_ texts: [String]) -> [String] {
        guard let last = texts.last, last.hasPrefix("Saved "), last.count > "Saved ".count else { return texts }
        return texts + ["Saved"]
    }

    func setVariants(_ texts: [String]) {
        var unique: [String] = []
        for text in Self.withShortForm(texts) where unique.last != text { unique.append(text) }
        variants = unique
        // Show the whole text until the next layout pass has decided how much room it really gets.
        settingVariant = true
        super.stringValue = unique.first ?? ""
        settingVariant = false
        spokenValue = nil
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func accessibilityValue() -> String? { spokenValue ?? super.accessibilityValue() }

    /// The width the longest variant wants, whichever one is showing, so the label grows back when room returns.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        if let full = variants.first { size.width = cellWidth(of: full) }
        return size
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitVariant()
    }

    override func layout() {
        super.layout()
        fitVariant()
    }

    private func cellWidth(of text: String) -> CGFloat {
        guard let probe = cell?.copy() as? NSCell else { return 0 }
        probe.stringValue = text
        return ceil(probe.cellSize.width)
    }

    private func fitVariant() {
        guard let full = variants.first else { return }
        let width = bounds.width
        let shown = width <= 0 ? full : (variants.first { cellWidth(of: $0) <= width + 0.5 } ?? variants[variants.count - 1])
        settingVariant = true; defer { settingVariant = false }
        if super.stringValue != shown { super.stringValue = shown }
        spokenValue = shown == full ? nil : full
    }
}

/// Where a choice panel opens relative to its anchor, in screen terms whatever the anchor's flippedness (`.minY` is below it, `.maxY` above).
/// The top bar's Toolbox opens downward and the footer's Zoom and Upload upward; the host flips either when the screen has no room.
enum ChoiceEdge {
    static let below = NSRectEdge.minY
    static let above = NSRectEdge.maxY
}

/// The zoom pop-up. Its face shows only the percentage, so the mode word of a computed zoom (Fit, Frame, Normal, ...)
/// travels on the item's tooltip and in the spoken value instead. It is a `GlassPopUpButton`: every way of opening it (a click, a right or
/// Control-click, Space, Return, Down, Up, `performClick`, VoiceOver's press and Show Menu, the context-menu key) opens one glass panel
/// built from its own menu, which stays the source of truth. The percentages and the computed row are options (the selected item is the
/// chosen one); Actual Size is a toggle that performs its own command and never becomes the face.
final class ZoomPopUpButton: GlassPopUpButton {
    /// The menu-only Actual Size command: it never becomes the face, so it is not part of the capsule's width budget.
    static let actualSizeTag = 998
    /// The computed Fit / Frame / Normal row `setCanvasDisplayZoom` keeps first in the menu.
    static let computedZoomTag = 999

    override init(frame frameRect: NSRect, pullsDown flag: Bool) {
        super.init(frame: frameRect, pullsDown: flag)
        configureChoices()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureChoices()
    }

    private func configureChoices() {
        panelIdentifier = "Zoom"
        panelLabel = "Canvas zoom"
        minimumPanelWidth = 200
        // The zoom sits in the footer, so its choices open above it (the host flips them when the screen has no room).
        preferredEdge = ChoiceEdge.above
        // The footer is crowded (the status line takes what the plates leave), so the face is tight: the percentage, its chevron, and no more.
        facePadding = DesignTokens.Space.s1
        chevronColumn = 25
        kind = { $0.tag == ZoomPopUpButton.actualSizeTag ? .toggle : .option }
        // The face is the percentage alone, so the computed row (Fit, Frame, Normal, Actual) says its mode in the panel, using the words the
        // item already carries on its tooltip; otherwise it and the fixed row of the same percentage would read alike. The menu is unchanged.
        rowTitle = { $0.tag == ZoomPopUpButton.computedZoomTag ? ($0.toolTip ?? $0.title) : $0.title }
    }

    override func accessibilityValue() -> Any? { selectedItem?.toolTip ?? titleOfSelectedItem }

    /// The capsule is sized for the percentage alone, not for the longest row of the menu ("Actual Size"), which is never the face: choosing
    /// it sends its command through the application and leaves the pop-up's selection where it was.
    override var intrinsicContentSize: NSSize {
        let width = ceil((faceTitle as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.body)]).width)
        return NSSize(width: 2 * facePadding + width + chevronColumn, height: GlassChoiceButton.height)
    }
}

/// The Toolbox: a menu button. It keeps NSPopUpButton as its base so the chrome's sizing and the key-view loop stay as they were, but it
/// never uses the selection-style pop-up behaviour: that style laid the chosen row over its own button, so the open menu covered the
/// Toolbox, Photos and the first tools, and exposed a "value" (it read "Select All"). The rows now open below the button as a glass panel
/// of group plates, the button has no value and reads as a menu button named "Toolbox" (R2-004, F-J6-009). The menu is a copy of the
/// menu-bar rows, icons and all, and stays the source of truth for titles, shortcuts and validation; the panel only draws it.
///
/// Like `GlassPopUpButton` it takes every way of showing the menu natively and opens the panel instead: a click or Control-click, a right
/// or other button (`menu(for:)` is nil), Space, Return, Down, Up, `performClick`, the accessibility press and Show Menu, and the context-menu
/// key. It is not a `GlassPopUpButton` because its face is the Toolbox icon and chevron (a `faceItem` image), not the selected title.
final class ToolboxPopUpButton: NSPopUpButton, NSMenuDelegate {
    let faceItem = NSMenuItem(title: "Toolbox", action: nil, keyEquivalent: "")
    /// Test seam: where the last open put the top-left of the menu, in this view's coordinates.
    private(set) var lastPopUpOrigin: NSPoint?
    /// Test seam: replaces showing the panel (the panel is a window, so a test can record the request instead).
    var popUpHandler: ((NSMenu, NSPoint) -> Void)?
    /// The rows that switch something on or off (Filled Shapes, Shadow, Text Style), by action; the rest are plain commands.
    private(set) var toggleActions: Set<Selector> = []
    private var cachedPanel: MenuChoicePanel?

    convenience init() {
        self.init(frame: .zero, pullsDown: false)
        if let popUpCell = cell as? NSPopUpButtonCell { popUpCell.usesItemFromMenu = false; popUpCell.menuItem = faceItem; popUpCell.arrowPosition = .noArrow }
        imagePosition = .imageOnly
        setAccessibilityRole(.menuButton)
    }
    override var canBecomeKeyView: Bool { KeyboardNavigation.reaches(self) }
    override func accessibilityValue() -> Any? { nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .menuButton }

    /// Rows go in `menu`; the closed button shows `image`.
    func setFace(_ image: NSImage?) { faceItem.image = image; needsDisplay = true }
    func install(_ rows: NSMenu, toggles: Set<Selector> = []) {
        cachedPanel?.host.close(restoreFocus: false)
        cachedPanel = nil
        rows.delegate = self
        menu = rows
        toggleActions = toggles
        select(nil)
    }

    // MARK: the panel

    /// The panel over the installed rows: a submenu drills in, a toggle shows its state, the rest are commands.
    var choicePanel: MenuChoicePanel {
        if let cachedPanel, cachedPanel.menu === menu { return cachedPanel }
        let toggles = toggleActions
        let panel = MenuChoicePanel(menu: menu ?? NSMenu(), identifier: "Toolbox", accessibilityLabel: "Toolbox", kind: { item in
            if item.submenu != nil { return .submenu }
            return item.action.map(toggles.contains) == true ? .toggle : .command
        })
        cachedPanel = panel
        return panel
    }
    var isChoicesOpen: Bool { cachedPanel?.host.isShown == true }

    /// The rows open just under the button, aligned to its leading edge, so nothing on the bar is covered; a second request while they are
    /// open only closes them. `keyboard` focuses the first enabled row (or the chosen one).
    func openMenu(keyboard: Bool = false) { openChoices(keyboard: keyboard) }
    func openChoices(keyboard: Bool) {
        guard isEnabled, window != nil, let rows = menu, rows.numberOfItems > 0 else { return }
        if isChoicesOpen { cachedPanel?.host.close(); return }
        if let popUpHandler {
            let origin = NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : bounds.minY - 4)
            lastPopUpOrigin = origin
            popUpHandler(rows, origin)
            return
        }
        choicePanel.present(relativeTo: self, preferredEdge: ChoiceEdge.below, keyboard: keyboard)
    }

    // MARK: every opening route

    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override func mouseDown(with event: NSEvent) { openChoices(keyboard: false) }
    override func rightMouseDown(with event: NSEvent) { openChoices(keyboard: false) }
    override func otherMouseDown(with event: NSEvent) { openChoices(keyboard: false) }
    override func performClick(_ sender: Any?) { openChoices(keyboard: true) }
    override func accessibilityPerformPress() -> Bool { guard isEnabled else { return false }; openChoices(keyboard: true); return true }
    override func accessibilityPerformShowMenu() -> Bool { guard isEnabled else { return false }; openChoices(keyboard: true); return true }
    @available(macOS 15.0, *)
    override func showContextMenuForSelection(_ sender: Any?) { openChoices(keyboard: true) }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76, 125, 126: openChoices(keyboard: true)      // Return, Space, keypad Enter, Down, Up
        default: nextResponder?.keyDown(with: event)                // never AppKit's type-ahead, which would select a row without asking
        }
    }
    func menuDidClose(_ menu: NSMenu) { DispatchQueue.main.async { [weak self] in self?.select(nil) } }
}

/// The Modern editor layout: a top bar holding capture and annotation, the solid canvas well across the full width and a
/// bottom bar holding document and output. Each bar is one glass container holding one glass plate per group (four on top, four
/// below); the controls on a plate draw their own state fills. Glass sits only on the command layer and never over the
/// canvas; every control is owned by the caller and re-parented here.
@MainActor
final class ModernEditorChrome: NSView {
    struct SharedControls {
        let canvas: NSView, canvasBorder: NSView, status: NSTextField, sizeLabel: NSTextField
        let widthControl: NSControl, paletteButton: NSButton, zoomControl: NSPopUpButton, dragFormatControl: NSControl
        let dragOriginalControl: NSButton, dragExportView: NSView, toolbox: NSPopUpButton
    }

    struct Actions {
        weak var target: AnyObject?
        var hide, photos, saveHistory, showHistory, chooseTool, snap, cancelFrame, font, undo, wipe, resize, share: Selector
    }

    static let snapToolTip = "Snap: drag an area or click a window; right-click or Control-click for Fullscreen"
    static let snapFrameToolTip = "Snap Frame: capture the area inside the frame; hold Shift for a six-second timer"
    private static let toolIcons: [String: FAIcon] = [
        "select": .arrowPointer, "brush": .paintbrush, "line": .slashForward, "ellipse": .circle, "rectangle": .square,
        "fill": .fillDrip, "eraser": .eraser, "text": .text, "arrow": .arrowUpRight, "crop": .cropSimple
    ]

    /// The closed Toolbox: its icon and a small chevron after it, both template, so the button reads as a menu and follows the tint.
    static func toolboxFace(icon: NSImage) -> NSImage {
        let chevron = ChromeIcons.resolve(.chevronDown, family: .solid, pointSize: GlassChrome.Metrics.iconPointSize * 0.5).image
        let gap: CGFloat = DesignTokens.Space.s1
        let width = icon.size.width + (chevron.map { gap + $0.size.width } ?? 0)
        let face = NSImage(size: NSSize(width: width, height: icon.size.height), flipped: false) { rect in
            icon.draw(in: NSRect(x: 0, y: 0, width: icon.size.width, height: rect.height))
            if let chevron { chevron.draw(in: NSRect(x: icon.size.width + gap, y: (rect.height - chevron.size.height) / 2, width: chevron.size.width, height: chevron.size.height)) }
            return true
        }
        face.isTemplate = true
        return face
    }

    /// Narrowest window both one-row bars fit in without clipping. The Frame-mode top bar is the widest at about 970 pt
    /// (see GlassChromeTests' width budget), so 980 is a floor derived from `Metrics`, not a guess.
    static let minimumWindowWidth: CGFloat = 980

    /// The narrowest window both bars fit in, measured from the live groups rather than assumed: the Frame-mode top bar (Cancel shown),
    /// and the bottom bar with the Original size checkbox beside a status that keeps `minimumStatusWidth`, each plus the two margins,
    /// and never below `minimumWindowWidth`. At 20 pt this is the 980 floor.
    func requiredWindowWidth() -> CGFloat { max(Self.minimumWindowWidth, measuredWindowWidth()) }
    /// What the bars alone need, before the 980 floor: the number a metric change moves.
    func measuredWindowWidth() -> CGFloat {
        typealias M = GlassChrome.Metrics
        let cancel = cancelFrameButton.isHidden ? M.groupSpacing + M.iconButton.width : 0
        let top = fit("GlassHeaderLeading") + fit("GlassCaptureGroup") + cancel + fit("GlassToolBar") + fit("GlassAnnotationGroup") + 3 * M.groupGap
        return ceil(max(top, fitFooterGroups(withOriginalSize: true, atMinimumWidth: true) + Self.minimumStatusWidth)) + 2 * DesignTokens.Layout.margin
    }
    private func fit(_ id: String) -> CGFloat { surfaceList.first { $0.identifier?.rawValue == id }?.fittingSize.width ?? 0 }
    /// The Original size toggle's side padding and the gap between its checkbox mark and its title. The mark's box has a few points of
    /// room of its own around the glyph, so these read as roomier than they are. With the 87 pt zoom they leave the 980 pt floor 5 pt more
    /// than an upload error at its narrowest ("Failed" and both commands, with the status at its 60 pt minimum) needs beside the toggle.
    static let originalSizePadding: CGFloat = 6
    static let originalSizeGap: CGFloat = DesignTokens.Space.s1

    /// What the Original size toggle adds to the View plate while it shows: its own width and the spacing before it. The toggle sits on that
    /// plate, so it takes its room from the status slot (the plate grows, the slot shrinks) instead of from inside it.
    var originalSizeWidth: CGFloat { controls.dragOriginalControl.fittingSize.width + GlassChrome.Metrics.groupSpacing }

    /// The four plates of the bottom bar and the gaps between them and the status slot. `withOriginalSize` states whether the View plate is
    /// counted with the toggle on it or without, whatever the toggle is doing now, so the answer to "would it fit" never depends on the answer.
    /// `atMinimumWidth` counts the PNG | JPG toggle in its compact form, the form it has in any window narrower than `compactFormatBelow`,
    /// which is where the minimum window sits; it is measured the same whatever width the window has when the number is asked for.
    private func fitFooterGroups(withOriginalSize: Bool? = nil, atMinimumWidth: Bool = false) -> CGFloat {
        var view = fit("GlassViewGroup")
        if let withOriginalSize {
            let showing = !controls.dragOriginalControl.isHidden
            if withOriginalSize && !showing { view += originalSizeWidth } else if !withOriginalSize && showing { view -= originalSizeWidth }
        }
        return fit("GlassUndoWipeGroup") + view + fit("GlassSaveGroup") + (atMinimumWidth ? footerRowAtMinimumWidth() : fit("GlassFooterRow")) + 4 * GlassChrome.Metrics.groupGap
    }

    /// The footer plate with the PNG | JPG toggle compact, however wide it is now.
    private func footerRowAtMinimumWidth() -> CGFloat {
        guard let toggle = controls.dragFormatControl as? SegmentedToggle, let constraint = formatWidthConstraint else { return fit("GlassFooterRow") }
        let compact = SegmentedToggle(titles: toggle.titles)
        compact.isCompact = true
        return fit("GlassFooterRow") - constraint.constant + ceil(compact.intrinsicContentSize.width) + Self.formatSwapCueWidth
    }

    /// The width the bottom bar leaves for the status slot at the window's current width: the bar's width less its four plates and gaps.
    func statusSlotWidth() -> CGFloat { bounds.width - 2 * DesignTokens.Layout.margin - fitFooterGroups() }

    /// The gap between neighbours in the status row.
    static let statusRowSpacing: CGFloat = 12
    /// What an upload's message keeps beside the Original size checkbox: about twenty characters of an error or a name. The message is the
    /// news and the checkbox is an option, so the checkbox steps aside before the message is squeezed further.
    static let minimumUploadStatusWidth: CGFloat = 200

    /// The width the status line's cell wants for `text`.
    func statusCellWidth(of text: String) -> CGFloat {
        guard let probe = controls.status.cell?.copy() as? NSCell else { return 0 }
        probe.stringValue = text
        return ceil(probe.cellSize.width)
    }
    /// The least room a message needs. An error has a whole-line, a coded and a bare ("Failed") form and is read at the narrowest of them;
    /// the others keep the twenty characters.
    func minimumMessageWidth(for state: UploadState) -> CGFloat {
        guard state.isFailure, let narrowest = state.statusVariants.last else { return Self.minimumUploadStatusWidth }
        return min(Self.minimumUploadStatusWidth, statusCellWidth(of: narrowest))
    }

    /// What a transfer needs of the slot besides the Original size checkbox: the spinner when one runs, the message at its minimum, and the
    /// commands (one icon for Cancel, two for Open and Copy or Retry and Details), each with the gap before it.
    func slotNeed(for state: UploadState) -> CGFloat {
        let commands = state.isUploading ? 1 : (state.isFailure || state.link != nil ? 2 : 0)
        var need = minimumMessageWidth(for: state)
        if state.isUploading { need += UploadStatusControls.spinnerSide + Self.statusRowSpacing }
        // The commands sit on one plate: its inset on each side, the gap between icons, and the gap before the plate.
        guard commands > 0 else { return need }
        typealias M = GlassChrome.Metrics
        return need + CGFloat(commands) * M.iconButton.width + CGFloat(commands - 1) * M.groupSpacing + 2 * M.groupInset + Self.statusRowSpacing
    }

    /// The most any upload state asks of the slot: a transfer under way, a copied link and an error each have their own spinner, message and
    /// commands, and the dearest sets the bar for all of them.
    var slotNeedDuringAnyUpload: CGFloat {
        let sample = URL(string: "https://cdn.example.com/pics/shot.png")!
        return [UploadState.uploading(name: ""), .success(url: sample, copied: true), .failure(message: "Failed")].map(slotNeed(for:)).max() ?? 0
    }

    /// Whether the Original size checkbox can stay beside an upload's message and commands: only when the slot, measured at the window's
    /// current width, holds the checkbox as well as the dearest state `slotNeedDuringAnyUpload` lists. The answer is the same for every state,
    /// so the checkbox is hidden for the whole life of an upload or shown for all of it: the bar never jumps as a transfer goes from running
    /// to done or failed. At 980 it steps aside throughout; from about 1100 on it stays.
    func slotHasRoomForCheckbox(during state: UploadState) -> Bool {
        bounds.width - 2 * DesignTokens.Layout.margin - fitFooterGroups(withOriginalSize: true) >= slotNeedDuringAnyUpload
    }
    /// The status line keeps at least this much beside the Original size checkbox at the minimum window.
    static let minimumStatusWidth: CGFloat = 120

    let scrollView = NSScrollView()
    let header = NSView()
    let footer = NSView()
    private(set) var toolButtons: [String: CommandButton] = [:]
    /// The first control of the top bar, where "Focus Toolbar" puts the keyboard.
    var firstToolbarControl: NSControl { hideButton }
    let hideButton, photosButton, saveButton, historyButton, snapButton, cancelFrameButton,
        fontButton, undoButton, wipeButton, resizeButton, shareButton: CommandButton
    /// The canvas well is the solid `surface.canvasWell` colour, drawn by the scroll view and its clip view (corner included).
    var wellIsSolid: Bool { scrollView.drawsBackground && scrollView.contentView.drawsBackground }

    /// Snap becomes Snap Frame, Cancel appears beside it, and the solid well gives way to the Frame-mode hole.
    var frameMode = false {
        didSet { if frameMode != oldValue { applyFrameMode() } }
    }

    var accessibility: ChromeAccessibility {
        didSet {
            for surface in surfaceList { surface.accessibility = accessibility }
            for fill in fillList { fill.accessibility = accessibility }
        }
    }

    private let controls: SharedControls
    /// The spinner and inline commands that take over the status slot while an upload runs, succeeds or fails (OSN-054).
    let uploadControls = UploadStatusControls()
    private let hideAction: Selector, undoAction: Selector
    private let toolOrder: [String]
    private let accessibilityProvider: @MainActor () -> ChromeAccessibility
    private var displayOptionsObservation: DisplayOptions.Observation?
    private var surfaceList: [GlassSurfaceView] = []
    private var fillList: [ChromeFillable] = []

    init(controls: SharedControls, actions: Actions, toolOrder: [String],
         accessibility: @escaping @MainActor () -> ChromeAccessibility = { .live }) {
        self.controls = controls
        self.hideAction = actions.hide
        self.undoAction = actions.undo
        self.toolOrder = toolOrder
        self.accessibilityProvider = accessibility
        self.accessibility = accessibility()
        // Every command is icon-only: the old title survives as the VoiceOver label and (with the shortcut) the native tooltip.
        func make(_ name: String, _ icon: FAIcon, _ action: Selector, shortcut: String? = nil, toolTip: String? = nil,
                  pointSize: CGFloat = GlassChrome.Metrics.iconPointSize) -> CommandButton {
            let button = CommandButton(title: "", target: actions.target, action: action)
            GlassChrome.useExtraLarge(button)
            button.iconPointSize = pointSize
            button.icon = icon
            button.makeIconOnly(name: name, shortcut: shortcut, derivesToolTip: toolTip == nil)
            if let toolTip { AppToolTip.setText(toolTip, for: button) }
            return button
        }
        hideButton = make("Hide", .eyeSlash, actions.hide, shortcut: Self.menuShortcut(for: actions.hide))
        photosButton = make("Photos", .images, actions.photos)
        saveButton = make("Save", .boxArchive, actions.saveHistory, toolTip: "Save to History")
        historyButton = make("History", .clockRotateLeft, actions.showHistory)
        snapButton = make("Snap", .crosshairs, actions.snap, toolTip: Self.snapToolTip, pointSize: GlassChrome.Metrics.primaryIconPointSize)
        cancelFrameButton = make("Cancel", .xmark, actions.cancelFrame)
        fontButton = make("Font", .font, actions.font)
        undoButton = make("Undo", .arrowRotateLeft, actions.undo, shortcut: Self.menuShortcut(for: actions.undo))
        wipeButton = make("Clear image", .broom, actions.wipe)
        // Resize… is the one command in the bars that wears its name: the diagonal-arrows glyph read as "expand" or "full screen" (R1-006).
        resizeButton = CommandButton(title: "Resize…", target: actions.target, action: actions.resize)
        GlassChrome.useExtraLarge(resizeButton)
        resizeButton.font = DesignTokens.Typography.font(.body)
        AppToolTip.setText("Resize or crop the picture", for: resizeButton)
        // Icon-only upload command: the semantic Upload icon, no title, so nothing but the explicit label is read aloud.
        shareButton = CommandButton(title: "", target: actions.target, action: actions.share)
        GlassChrome.useExtraLarge(shareButton)
        shareButton.image = ChromeIcons.resolve(.upload, family: .regular, pointSize: GlassChrome.Metrics.iconPointSize).image
        shareButton.image?.accessibilityDescription = Self.uploadLabel
        shareButton.imagePosition = .imageOnly
        AppToolTip.setText(Self.uploadLabel, for: shareButton)
        super.init(frame: .zero)
        build(actions: actions)
        displayOptionsObservation = DisplayOptions.observe { [weak self] _ in
            guard let self else { return }
            self.accessibility = self.accessibilityProvider()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The key equivalent the main menu gives an action, written the way menus show it (⌃⌥⇧⌘ then the key); nil when no item has one.
    static func menuShortcut(for action: Selector) -> String? {
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.action == action, !item.keyEquivalent.isEmpty { return item }
                if let submenu = item.submenu, let found = find(submenu) { return found }
            }
            return nil
        }
        guard let item = (NSApp as NSApplication?)?.mainMenu.flatMap(find) else { return nil }
        var mask = item.keyEquivalentModifierMask
        if item.keyEquivalent != item.keyEquivalent.lowercased() { mask.insert(.shift) }
        var text = ""
        if mask.contains(.control) { text += "⌃" }
        if mask.contains(.option) { text += "⌥" }
        if mask.contains(.shift) { text += "⇧" }
        if mask.contains(.command) { text += "⌘" }
        return text + item.keyEquivalent.uppercased()
    }

    /// Re-reads Hide's and Undo's shortcuts from the menu bar, so a changed key equivalent changes the tooltip.
    func refreshShortcutHints() {
        hideButton.shortcutHint = Self.menuShortcut(for: hideAction)
        undoButton.shortcutHint = Self.menuShortcut(for: undoAction)
    }

    /// The glass plate a control sits on, found by walking up from it; nil for controls that sit outside any glass.
    func surface(for control: NSView) -> GlassSurfaceView? {
        var view: NSView? = control
        while let current = view {
            if let glass = current as? GlassSurfaceView { return glass }
            view = current.superview
        }
        return nil
    }

    // MARK: state

    private func applyFrameMode() {
        syncSnapPresentation()
        cancelFrameButton.isHidden = !frameMode
        // Frame mode punches the transparent hole through the well; leaving it restores the solid colour.
        scrollView.drawsBackground = !frameMode
        scrollView.contentView.drawsBackground = !frameMode
    }

    /// The app re-titles and re-tips Snap itself when entering or leaving Frame mode; this puts the Modern icon, name and tooltip back.
    func syncSnapPresentation() {
        snapButton.icon = frameMode ? .frameViewfinder : .crosshairs
        snapButton.title = frameMode ? "Snap Frame" : "Snap"
        snapButton.iconPointSize = GlassChrome.Metrics.primaryIconPointSize
        AppToolTip.setText(frameMode ? Self.snapFrameToolTip : Self.snapToolTip, for: snapButton)
    }

    // MARK: construction

    static let uploadSymbolName = "icloud.and.arrow.up"
    /// What VoiceOver and the tooltip call the Upload command (T7).
    static let uploadLabel = "Upload image"

    private func readable(_ control: NSControl) {
        control.font = DesignTokens.Typography.floored(control.font)
    }

    /// A button on a plate: fixed size, state fill registered for display-option updates.
    private func fixed(_ button: CommandButton, _ size: NSSize = GlassChrome.Metrics.iconButton) -> CommandButton {
        GlassChrome.fix(button, size)
        fillList.append(button)
        return button
    }

    /// A non-button control on a plate, in a cell that draws the same hover fill.
    private func cell(_ control: NSView, size: NSSize = GlassChrome.Metrics.iconButton, fit: ChromeFillCell.Fit = .fill) -> ChromeFillCell {
        let cell = ChromeFillCell(control, size: size, fit: fit)
        cell.focusTarget = control as? NSControl
        // The Size pill draws its own glyph; the cell behind it fills for its press and disabled state.
        if let slider = control as? BezelSizeSlider {
            slider.onInteractionChange = { [weak cell, weak slider] in
                guard let cell, let slider else { return }
                cell.setPressed(slider.isPressed, disabled: !slider.isEnabled)
            }
        }
        fillList.append(cell)
        return cell
    }

    private func plate(_ views: [NSView], _ identifier: String) -> GlassSurfaceView {
        let plate = GlassChrome.plate(views, identifier: identifier, accessibility: accessibility)
        surfaceList.append(plate)
        return plate
    }

    private func build(actions: Actions) {
        typealias Metrics = GlassChrome.Metrics
        let margin = DesignTokens.Layout.margin, gap = DesignTokens.Layout.gap, groupGap = Metrics.groupGap
        let headerTop: CGFloat = 4, footerBottom: CGFloat = 8

        for control in [controls.dragFormatControl, controls.toolbox, controls.paletteButton] as [NSControl] { GlassChrome.useExtraLarge(control) }
        for control in [controls.dragFormatControl, controls.toolbox, controls.status, controls.zoomControl, controls.dragOriginalControl, controls.widthControl] as [NSControl] { readable(control) }
        // Color shows only its swatch: the title stays on the control (and its accessibility label) but is never drawn.
        controls.paletteButton.isBordered = false
        controls.paletteButton.imagePosition = .imageOnly
        AppToolTip.setText("Color: " + (AppToolTip.text(for: controls.paletteButton).map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? "pick a drawing color"), for: controls.paletteButton)
        AppToolTip.setText("Size", for: controls.widthControl)
        controls.status.textColor = .labelColor
        controls.status.lineBreakMode = .byTruncatingTail
        controls.status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controls.status.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // The canvas well is solid. The scroll view and its clip view both draw it, so the scroller corner is the same colour.
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = controls.canvas
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = DesignTokens.Palette.Surface.canvasWell
        scrollView.drawsBackground = true
        scrollView.contentView.backgroundColor = DesignTokens.Palette.Surface.canvasWell
        scrollView.contentView.drawsBackground = true
        scrollView.borderType = .noBorder

        // Top bar: [Hide][Toolbox][Photos] · [Snap][Cancel] · ten tools · [Color][Size][Font], one plate per group.
        header.identifier = NSUserInterfaceItemIdentifier("OpenSnapHeader")
        let toolboxIcon = ChromeIcons.resolve(.toolbox, family: .regular, pointSize: Metrics.iconPointSize)
        if let image = toolboxIcon.image {
            if let toolbox = controls.toolbox as? ToolboxPopUpButton {
                toolbox.setFace(Self.toolboxFace(icon: image))
            } else if let first = controls.toolbox.itemArray.first {
                first.image = image
            }
            controls.toolbox.imagePosition = .imageOnly
        }
        controls.toolbox.isBordered = false
        controls.toolbox.contentTintColor = .labelColor
        let toolboxCell = cell(controls.toolbox, size: Metrics.toolboxButton, fit: .centered(inset: DesignTokens.Space.s2))
        let leadingGroup = plate([fixed(hideButton), toolboxCell, fixed(photosButton)], "GlassHeaderLeading")

        // Capture: Snap stays put; Cancel joins it on the right in Frame mode only (a hidden control leaves the stack).
        snapButton.isPrimary = true
        AppToolTip.setText(Self.snapToolTip, for: snapButton)
        cancelFrameButton.isHidden = true
        let captureGroup = plate([fixed(snapButton, Metrics.primaryButton), fixed(cancelFrameButton)], "GlassCaptureGroup")

        // The ten tools, archive order, icon only.
        var toolViews: [NSView] = []
        for id in toolOrder {
            guard let icon = Self.toolIcons[id] else { continue }
            let button = CommandButton(title: "", target: actions.target, action: actions.chooseTool)
            button.identifier = NSUserInterfaceItemIdentifier(id)
            button.setButtonType(.toggle)
            button.iconPointSize = Metrics.iconPointSize
            button.icon = icon
            button.setAccessibilityLabel(id.capitalized + " tool")
            AppToolTip.setText(id.capitalized + " tool", for: button)
            toolButtons[id] = button
            toolViews.append(fixed(button, Metrics.toolButton))
        }
        let toolGroup = plate(toolViews, "GlassToolBar")

        // Annotation: Color, Size (a pill that opens its popover) and Font sit beside the tools they modify.
        let annotationGroup = plate([cell(controls.paletteButton), cell(controls.widthControl), fixed(fontButton)], "GlassAnnotationGroup")

        let headerGroups = [leadingGroup, captureGroup, toolGroup, annotationGroup]
        for view in headerGroups { header.addSubview(view) }
        // The tool row is centred between the capture and annotation groups by two equal spacers, so Snap never moves.
        let beforeTools = NSLayoutGuide(), afterTools = NSLayoutGuide()
        header.addLayoutGuide(beforeTools)
        header.addLayoutGuide(afterTools)
        NSLayoutConstraint.activate([
            leadingGroup.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            captureGroup.leadingAnchor.constraint(equalTo: leadingGroup.trailingAnchor, constant: groupGap),
            annotationGroup.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            beforeTools.leadingAnchor.constraint(equalTo: captureGroup.trailingAnchor),
            beforeTools.trailingAnchor.constraint(equalTo: toolGroup.leadingAnchor),
            afterTools.leadingAnchor.constraint(equalTo: toolGroup.trailingAnchor),
            afterTools.trailingAnchor.constraint(equalTo: annotationGroup.leadingAnchor),
            beforeTools.widthAnchor.constraint(equalTo: afterTools.widthAnchor),
            beforeTools.widthAnchor.constraint(greaterThanOrEqualToConstant: groupGap)
        ] + headerGroups.map { $0.centerYAnchor.constraint(equalTo: header.centerYAnchor) })

        // Bottom bar: [Undo][Wipe] · [Zoom][Resize…] · [Original size] status · [Save][History] · [PNG|JPG][Drag][Upload]
        let undoWipeGroup = plate([fixed(undoButton), fixed(wipeButton)], "GlassUndoWipeGroup")

        // The zoom popup is sized once for its widest face (the percentage alone, with its own padding and chevron) so it never jumps.
        let zoomInset: CGFloat = 0
        controls.zoomControl.isBordered = false
        let selectedZoom = controls.zoomControl.indexOfSelectedItem
        let faceTitles = (0..<controls.zoomControl.numberOfItems).filter { controls.zoomControl.item(at: $0)?.tag != ZoomPopUpButton.actualSizeTag && controls.zoomControl.item(at: $0)?.isSeparatorItem == false }
        let widestZoom: CGFloat
        if let face = controls.zoomControl as? GlassPopUpButton {
            // The face draws its title between its padding and its chevron column, so the cell is what the widest face needs of both: every
            // percentage, the computed Fit / Frame row at its widest ("200%"), and "Actual", which the face reads while Actual Size is on.
            let font = DesignTokens.Typography.font(.body)
            let computed = ["200%", "Actual"].map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
            let text = faceTitles.map { index -> CGFloat in face.selectItem(at: index); return face.faceTextMetrics.needed.width }.max() ?? 0
            widestZoom = max(text, computed) + 2 * face.facePadding + face.chevronColumn
        } else {
            widestZoom = faceTitles.map { index -> CGFloat in controls.zoomControl.selectItem(at: index); return controls.zoomControl.fittingSize.width }.max() ?? 0
        }
        if selectedZoom >= 0 { controls.zoomControl.selectItem(at: selectedZoom) }
        let zoomCell = cell(controls.zoomControl, size: NSSize(width: ceil(widestZoom) + 2 * zoomInset, height: Metrics.commandHeight), fit: .centered(inset: zoomInset))
        let resizeWidth = ceil((resizeButton.visibleTitle as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.body)]).width) + 2 * DesignTokens.Space.s2
        // Original size is a glass toggle at the end of the View plate (it explains what the percentage beside it measures). The app hides it
        // for a small shot, in Frame and at Actual Size; the plate's stack drops a hidden view, so the plate shrinks and the slot grows back.
        let originalSize = controls.dragOriginalControl
        if let toggle = originalSize as? ChromeFillable { fillList.append(toggle) }
        // The footer is crowded (an upload error keeps this toggle beside it on the 980 pt floor), so the toggle's content sits closer to its
        // edge and its mark closer to its title than a menu row's does; the type stays 20 pt.
        if let toggle = originalSize as? GlassChoiceButton { toggle.horizontalPadding = Self.originalSizePadding; toggle.contentGap = Self.originalSizeGap }
        let viewGroup = plate([zoomCell, fixed(resizeButton, NSSize(width: resizeWidth, height: Metrics.commandHeight)), originalSize], "GlassViewGroup")

        let saveGroup = plate([fixed(saveButton), fixed(historyButton)], "GlassSaveGroup")

        // The PNG | JPG control sits on the footer plate itself: no plate or cell of its own behind it.
        let formatControl = controls.dragFormatControl
        (formatControl as? NSPopUpButton)?.isBordered = false
        // Only Snap is saturated at rest: the toggle draws its selected segment from the same state styles as the commands.
        if let toggle = formatControl as? ChromeFillable { fillList.append(toggle) }
        let formatWidth: CGFloat
        if let popup = formatControl as? NSPopUpButton {
            // A popup sizes to its selected title, so measure every title and size it once for the widest: it hugs the content and never jumps.
            let selectedFormat = popup.indexOfSelectedItem
            formatWidth = (0..<popup.numberOfItems).map { index -> CGFloat in popup.selectItem(at: index); return popup.fittingSize.width }.max() ?? 0
            popup.selectItem(at: selectedFormat)
        } else { formatWidth = formatControl.fittingSize.width }
        GlassChrome.fix(formatControl, NSSize(width: ceil(formatWidth), height: Metrics.commandHeight))
        formatWidthConstraint = formatControl.constraints.first { $0.firstAttribute == .width && $0.secondItem == nil }
        regularFormatWidth = ceil(formatWidth)
        shareButton.setAccessibilityLabel(Self.uploadLabel)
        let footerGroup = plate([formatControl, cell(controls.dragExportView), fixed(shareButton)], "GlassFooterRow")

        // The status takes whatever width the groups leave; the Original size checkbox only exists for a large shot.
        // An upload swaps what sits here (spinner and Cancel, Open and Copy, Retry and Details) and hides the checkbox; the slot never grows.
        uploadControls.attach(plate: plate(uploadControls.commandButtons, "GlassUploadCommands"))
        let statusRow = NSStackView(views: uploadControls.leadingViews + [controls.status] + uploadControls.trailingViews)
        statusRow.orientation = .horizontal
        statusRow.spacing = Self.statusRowSpacing
        statusRow.alignment = .centerY
        statusRow.identifier = NSUserInterfaceItemIdentifier("OpenSnapStatusRow")

        footer.identifier = NSUserInterfaceItemIdentifier("OpenSnapFooter")
        let footerParts: [NSView] = [undoWipeGroup, viewGroup, statusRow, saveGroup, footerGroup]
        for part in footerParts {
            part.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(part)
        }
        let headerGlass = GlassChrome.container(around: header, identifier: "GlassTopBar")
        let footerGlass = GlassChrome.container(around: footer, identifier: "GlassBottomBar")
        let all: [NSView] = [scrollView, headerGlass, footerGlass]
        for view in all { view.translatesAutoresizingMaskIntoConstraints = false }
        for view in all { addSubview(view) }
        addSubview(controls.canvasBorder)

        NSLayoutConstraint.activate([
            headerGlass.topAnchor.constraint(equalTo: topAnchor, constant: headerTop),
            headerGlass.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            footerGlass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -footerBottom),
            footerGlass.heightAnchor.constraint(equalToConstant: DesignTokens.Layout.footer),
            undoWipeGroup.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            viewGroup.leadingAnchor.constraint(equalTo: undoWipeGroup.trailingAnchor, constant: groupGap),
            statusRow.leadingAnchor.constraint(equalTo: viewGroup.trailingAnchor, constant: groupGap),
            statusRow.trailingAnchor.constraint(lessThanOrEqualTo: saveGroup.leadingAnchor, constant: -groupGap),
            saveGroup.trailingAnchor.constraint(equalTo: footerGroup.leadingAnchor, constant: -groupGap),
            footerGroup.trailingAnchor.constraint(equalTo: footer.trailingAnchor)
        ] + footerParts.map { $0.centerYAnchor.constraint(equalTo: footer.centerYAnchor) } + [

            // The canvas runs edge to edge between the bars; nothing is reserved on either side of it.
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            scrollView.topAnchor.constraint(equalTo: headerGlass.bottomAnchor, constant: gap),
            scrollView.bottomAnchor.constraint(equalTo: footerGlass.topAnchor, constant: -gap)
        ])
        fillList.append(contentsOf: uploadControls.commandButtons)
        for fill in fillList { fill.accessibility = accessibility }
        for bar in [headerGlass, footerGlass] { constrainBarWidth(bar, margin: margin) }
    }

    /// The widest a bar gets. Past it (a full-screen window) the bar stays this wide in the middle, so its groups stay together
    /// instead of drifting to the corners of the screen; below it the bar spans the window less the margins, as before.
    static let maximumBarWidth: CGFloat = 1440

    /// The bars' width is a constant the chrome keeps in step with its own width in `layout()`, so the cap never becomes a relationship that
    /// limits how wide the window itself may grow.
    private var barWidthConstraints: [NSLayoutConstraint] = []

    private func constrainBarWidth(_ bar: NSView, margin: CGFloat) {
        let width = bar.widthAnchor.constraint(equalToConstant: Self.minimumWindowWidth - 2 * margin)
        width.priority = NSLayoutConstraint.Priority(rawValue: 999)
        barWidthConstraints.append(width)
        NSLayoutConstraint.activate([width, bar.centerXAnchor.constraint(equalTo: centerXAnchor)])
    }

    /// The width a bar takes at the chrome's current width.
    var barWidth: CGFloat { min(Self.maximumBarWidth, max(0, bounds.width - 2 * DesignTokens.Layout.margin)) }

    /// Below this window width the PNG | JPG toggle is the one compact button (R2-014).
    static let compactFormatBelow: CGFloat = 1100
    /// What the compact button adds for its swap cue: a small left-right glyph at its trailing edge, so one button that shows "PNG" does not
    /// look like the selected segment of the two-segment toggle but like a control that flips to the other format.
    static let formatSwapCueWidth: CGFloat = 28
    private let formatSwapCue = FormatSwapCue()
    /// Whether the swap cue shows: only while the toggle is the one compact button.
    var formatSwapCueVisible: Bool { !formatSwapCue.isHidden }
    private var formatWidthConstraint: NSLayoutConstraint?
    private var regularFormatWidth: CGFloat = 0
    /// Collapses or restores the format toggle for the window's current width; the bar's own layout pass calls it.
    func updateFormatCompaction() {
        guard let toggle = controls.dragFormatControl as? SegmentedToggle, let constraint = formatWidthConstraint else { return }
        let compact = bounds.width > 0 && bounds.width < Self.compactFormatBelow
        if toggle.isCompact != compact { toggle.isCompact = compact }
        if formatSwapCue.superview !== toggle { installSwapCue(on: toggle) }
        formatSwapCue.isHidden = !compact
        let width = compact ? ceil(toggle.intrinsicContentSize.width) + Self.formatSwapCueWidth : regularFormatWidth
        if constraint.constant != width { constraint.constant = width }
    }
    private func installSwapCue(on toggle: SegmentedToggle) {
        formatSwapCue.image = ChromeIcons.resolve(.leftRight, family: .regular, pointSize: GlassChrome.Metrics.iconPointSize * 0.6).image
        formatSwapCue.contentTintColor = DesignTokens.Palette.Text.secondary
        formatSwapCue.translatesAutoresizingMaskIntoConstraints = false
        toggle.addSubview(formatSwapCue)
        NSLayoutConstraint.activate([formatSwapCue.trailingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: -DesignTokens.Space.s2),
                                     formatSwapCue.centerYAnchor.constraint(equalTo: toggle.centerYAnchor)])
    }
    override func layout() {
        updateFormatCompaction()
        let target = barWidth
        if target > 0 { for constraint in barWidthConstraints where constraint.constant != target { constraint.constant = target } }
        super.layout()
    }
}


/// The glyph on the compact format button. It never takes a click: the toggle underneath does.
final class FormatSwapCue: NSImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleNone; isHidden = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Modern only: a document smaller than the visible area sits in the middle of it, per axis. A larger one is
/// constrained exactly as NSClipView does, so scrolling, panning and the scroll origin are unchanged.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let frame = documentView?.frame else { return rect }
        if frame.width < rect.width { rect.origin.x = frame.minX - (rect.width - frame.width) / 2 }
        if frame.height < rect.height { rect.origin.y = frame.minY - (rect.height - frame.height) / 2 }
        return rect
    }

    /// Programmatic scrolls (a new snap scrolls to the origin) go through the same constraint a drag does.
    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: constrainBoundsRect(NSRect(origin: newOrigin, size: bounds.size)).origin)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recentre()
    }

    override func viewFrameChanged(_ notification: Notification) {
        super.viewFrameChanged(notification)
        recentre()
    }

    override func layout() {
        super.layout()
        recentre()
    }

    override func viewBoundsChanged(_ notification: Notification) {
        super.viewBoundsChanged(notification)
        recentre()
    }

    private func recentre() {
        let target = constrainBoundsRect(bounds).origin
        if target != bounds.origin { scroll(to: target) }
    }
}
