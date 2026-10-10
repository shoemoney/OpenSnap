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

    /// Narrowest window both one-row bars fit in without clipping. The Frame-mode top bar is the widest at about 970 pt
    /// (see GlassChromeTests' width budget), so 980 is a floor derived from `Metrics`, not a guess.
    static let minimumWindowWidth: CGFloat = 980

    let scrollView = NSScrollView()
    let header = NSView()
    let footer = NSView()
    private(set) var toolButtons: [String: GlassChromeButton] = [:]
    let hideButton, photosButton, saveButton, historyButton, snapButton, cancelFrameButton,
        fontButton, undoButton, wipeButton, resizeButton, shareButton: GlassChromeButton
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
                  pointSize: CGFloat = GlassChrome.Metrics.iconPointSize) -> GlassChromeButton {
            let button = GlassChromeButton(title: "", target: actions.target, action: action)
            GlassChrome.useExtraLarge(button)
            button.iconPointSize = pointSize
            button.icon = icon
            button.makeIconOnly(name: name, shortcut: shortcut, derivesToolTip: toolTip == nil)
            if let toolTip { AppToolTip.setText(toolTip, for: button) }
            return button
        }
        hideButton = make("Hide", .eyeSlash, actions.hide, shortcut: Self.menuShortcut(for: actions.hide))
        photosButton = make("Photos", .images, actions.photos)
        saveButton = make("Save", .floppyDisk, actions.saveHistory, toolTip: "Save to History")
        historyButton = make("History", .clockRotateLeft, actions.showHistory)
        snapButton = make("Snap", .crosshairs, actions.snap, toolTip: Self.snapToolTip, pointSize: GlassChrome.Metrics.primaryIconPointSize)
        cancelFrameButton = make("Cancel", .xmark, actions.cancelFrame)
        fontButton = make("Font", .font, actions.font)
        undoButton = make("Undo", .arrowRotateLeft, actions.undo, shortcut: Self.menuShortcut(for: actions.undo))
        wipeButton = make("Wipe", .broom, actions.wipe)
        resizeButton = make("Resize…", .rulerCombined, actions.resize)
        // Icon-only upload command: the semantic Upload icon, no title, so nothing but the explicit label is read aloud.
        shareButton = GlassChromeButton(title: "", target: actions.target, action: actions.share)
        GlassChrome.useExtraLarge(shareButton)
        shareButton.image = ChromeIcons.resolve(.upload, family: .regular, pointSize: GlassChrome.Metrics.iconPointSize).image
        shareButton.image?.accessibilityDescription = "Upload"
        shareButton.imagePosition = .imageOnly
        AppToolTip.setText("Upload", for: shareButton)
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

    private func readable(_ control: NSControl) {
        control.font = DesignTokens.Typography.floored(control.font)
    }

    /// A button on a plate: fixed size, state fill registered for display-option updates.
    private func fixed(_ button: GlassChromeButton, _ size: NSSize = GlassChrome.Metrics.iconButton) -> GlassChromeButton {
        GlassChrome.fix(button, size)
        fillList.append(button)
        return button
    }

    /// A non-button control on a plate, in a cell that draws the same hover fill.
    private func cell(_ control: NSView, size: NSSize = GlassChrome.Metrics.iconButton, fit: ChromeFillCell.Fit = .fill) -> ChromeFillCell {
        let cell = ChromeFillCell(control, size: size, fit: fit)
        cell.focusTarget = control as? NSControl
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
        if let image = toolboxIcon.image, let first = controls.toolbox.itemArray.first {
            first.image = image
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
            let button = GlassChromeButton(title: "", target: actions.target, action: actions.chooseTool)
            button.identifier = NSUserInterfaceItemIdentifier(id)
            button.setButtonType(.toggle)
            button.iconPointSize = Metrics.iconPointSize
            button.icon = icon
            button.setAccessibilityLabel(id.capitalized)
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
        let viewGroup = plate([zoomCell, fixed(resizeButton)], "GlassViewGroup")

        let saveGroup = plate([fixed(saveButton), fixed(historyButton)], "GlassSaveGroup")

        // The PNG | JPG control sits on the footer plate itself: no plate or cell of its own behind it.
        let formatControl = controls.dragFormatControl
        (formatControl as? NSPopUpButton)?.isBordered = false
        // Only Snap is saturated at rest: the selected segment takes the selected-fill rule (accent at 0.20) instead of the system's full accent.
        (formatControl as? NSSegmentedControl)?.selectedSegmentBezelColor = DesignTokens.Palette.State.selectedFill
        let formatWidth: CGFloat
        if let popup = formatControl as? NSPopUpButton {
            // A popup sizes to its selected title, so measure every title and size it once for the widest: it hugs the content and never jumps.
            let selectedFormat = popup.indexOfSelectedItem
            formatWidth = (0..<popup.numberOfItems).map { index -> CGFloat in popup.selectItem(at: index); return popup.fittingSize.width }.max() ?? 0
            popup.selectItem(at: selectedFormat)
        } else { formatWidth = formatControl.fittingSize.width }
        GlassChrome.fix(formatControl, NSSize(width: ceil(formatWidth), height: Metrics.commandHeight))
        shareButton.setAccessibilityLabel("Upload to destination")
        let footerGroup = plate([formatControl, cell(controls.dragExportView), fixed(shareButton)], "GlassFooterRow")

        // The status takes whatever width the groups leave; the Original size checkbox only exists for a large shot.
        let statusRow = NSStackView(views: [controls.dragOriginalControl, controls.status])
        statusRow.orientation = .horizontal
        statusRow.spacing = 12
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
            headerGlass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            headerGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            headerGlass.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            footerGlass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            footerGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
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
        for fill in fillList { fill.accessibility = accessibility }
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
