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
            if !settingVariant { variants = [] }
            super.stringValue = newValue
        }
    }

    func setVariants(_ texts: [String]) {
        var unique: [String] = []
        for text in texts where unique.last != text { unique.append(text) }
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

/// The zoom popup. Its face shows only the percentage, so the mode word of a computed zoom (Fit, Frame, Normal, ...)
/// travels on the item's tooltip and in the spoken value instead.
final class ZoomPopUpButton: NSPopUpButton {
    /// The menu-only Actual Size command: it never becomes the face, so it is not part of the capsule's width budget.
    static let actualSizeTag = 998
    override func accessibilityValue() -> Any? { selectedItem?.toolTip ?? titleOfSelectedItem }
    override var canBecomeKeyView: Bool { KeyboardNavigation.reaches(self) }
}

/// The Toolbox: a menu button. It keeps NSPopUpButton as its base so the chrome's sizing and the key-view loop stay as they were, but it
/// never uses the selection-style pop-up behaviour: that style laid the chosen row over its own button, so the open menu covered the
/// Toolbox, Photos and the first tools, and exposed a "value" (it read "Select All"). The rows now open below the button like any menu, the
/// button has no value and reads as a menu button named "Toolbox" (R2-004, F-J6-009). The menu is a copy of the menu-bar rows, icons and all.
final class ToolboxPopUpButton: NSPopUpButton, NSMenuDelegate {
    let faceItem = NSMenuItem(title: "Toolbox", action: nil, keyEquivalent: "")
    /// Test seam: where the last open put the top-left of the menu, in this view's coordinates.
    private(set) var lastPopUpOrigin: NSPoint?
    /// Test seam: replaces showing the menu (a menu tracks until it closes, so a test records the request instead).
    var popUpHandler: ((NSMenu, NSPoint) -> Void)?

    convenience init() {
        self.init(frame: .zero, pullsDown: false)
        if let popUpCell = cell as? NSPopUpButtonCell { popUpCell.usesItemFromMenu = false; popUpCell.menuItem = faceItem; popUpCell.arrowPosition = .noArrow }
        imagePosition = .imageOnly
        setAccessibilityRole(.menuButton)
    }
    override var canBecomeKeyView: Bool { KeyboardNavigation.reaches(self) }
    override func accessibilityValue() -> Any? { nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .menuButton }
    override func accessibilityPerformPress() -> Bool { openMenu(); return true }

    /// Rows go in `menu`; the closed button shows `image`.
    func setFace(_ image: NSImage?) { faceItem.image = image; needsDisplay = true }
    func install(_ rows: NSMenu) {
        rows.delegate = self
        menu = rows
        select(nil)
    }
    /// Opens the rows just under the button, aligned to its leading edge, so nothing on the bar is covered.
    func openMenu() {
        guard isEnabled, let rows = menu else { return }
        let origin = NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : bounds.minY - 4)
        lastPopUpOrigin = origin
        if let popUpHandler { popUpHandler(rows, origin) } else { rows.popUp(positioning: nil, at: origin, in: self) }
    }
    override func mouseDown(with event: NSEvent) { openMenu() }
    override func performClick(_ sender: Any?) { openMenu() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76, 125, 126: openMenu()      // Return, Space, keypad Enter, Down, Up
        default: super.keyDown(with: event)
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
        let status = controls.dragOriginalControl.fittingSize.width + 12 + Self.minimumStatusWidth
        return ceil(max(top, fitFooterGroups() + status)) + 2 * DesignTokens.Layout.margin
    }
    private func fit(_ id: String) -> CGFloat { surfaceList.first { $0.identifier?.rawValue == id }?.fittingSize.width ?? 0 }
    /// The four plates of the bottom bar and the gaps between them and the status slot.
    private func fitFooterGroups() -> CGFloat {
        fit("GlassUndoWipeGroup") + fit("GlassViewGroup") + fit("GlassSaveGroup") + fit("GlassFooterRow") + 4 * GlassChrome.Metrics.groupGap
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
    /// The least room a message needs. An error has a whole-line, a coded and a bare ("Failed") form and is read at the narrowest of them, so
    /// at 980 pt it gives up its words before the Original size checkbox is asked to leave (F-J7-006); the others keep the twenty characters.
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
        return need + CGFloat(commands) * (GlassChrome.Metrics.iconButton.width + Self.statusRowSpacing)
    }

    /// Whether the Original size checkbox can stay beside the upload's message and commands: only when the slot, measured at the window's
    /// current width, holds the checkbox as well as everything `slotNeed` lists. At 980 an error keeps it (the message shrinks to "Failed"); an upload
    /// in progress or done does not have the room, so the checkbox steps aside there; from about 1100 on it stays.
    func slotHasRoomForCheckbox(during state: UploadState) -> Bool {
        statusSlotWidth() >= slotNeed(for: state) + Self.statusRowSpacing + controls.dragOriginalControl.fittingSize.width
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

        // The zoom popup is sized once for its widest face (the percentage alone) so it never jumps.
        let zoomInset = DesignTokens.Space.s1
        controls.zoomControl.isBordered = false
        let selectedZoom = controls.zoomControl.indexOfSelectedItem
        let widestZoom = (0..<controls.zoomControl.numberOfItems).filter { controls.zoomControl.item(at: $0)?.tag != ZoomPopUpButton.actualSizeTag && controls.zoomControl.item(at: $0)?.isSeparatorItem == false }.map { index -> CGFloat in
            controls.zoomControl.selectItem(at: index); return controls.zoomControl.fittingSize.width
        }.max() ?? 0
        if selectedZoom >= 0 { controls.zoomControl.selectItem(at: selectedZoom) }
        let zoomCell = cell(controls.zoomControl, size: NSSize(width: ceil(widestZoom) + 2 * zoomInset, height: Metrics.commandHeight), fit: .centered(inset: zoomInset))
        let resizeWidth = ceil((resizeButton.visibleTitle as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.body)]).width) + 2 * DesignTokens.Space.s2
        let viewGroup = plate([zoomCell, fixed(resizeButton, NSSize(width: resizeWidth, height: Metrics.commandHeight))], "GlassViewGroup")

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
        let statusRow = NSStackView(views: uploadControls.leadingViews + [controls.dragOriginalControl, controls.status] + uploadControls.trailingViews)
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
    private var formatWidthConstraint: NSLayoutConstraint?
    private var regularFormatWidth: CGFloat = 0
    /// Collapses or restores the format toggle for the window's current width; the bar's own layout pass calls it.
    func updateFormatCompaction() {
        guard let toggle = controls.dragFormatControl as? SegmentedToggle, let constraint = formatWidthConstraint else { return }
        let compact = bounds.width > 0 && bounds.width < Self.compactFormatBelow
        if toggle.isCompact != compact { toggle.isCompact = compact }
        let width = compact ? ceil(toggle.intrinsicContentSize.width) : regularFormatWidth
        if constraint.constant != width { constraint.constant = width }
    }
    override func layout() {
        updateFormatCompaction()
        let target = barWidth
        if target > 0 { for constraint in barWidthConstraints where constraint.constant != target { constraint.constant = target } }
        super.layout()
    }
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
