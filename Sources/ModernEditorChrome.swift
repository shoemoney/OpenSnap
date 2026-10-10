import AppKit

/// Text fields and popups only center their text at their natural height, so inside a taller glass surface
/// they sit in this holder at that height; clicks on the holder's padding still reach the control.
@MainActor
private final class ControlHolderView: NSView {
    weak var focusTarget: NSView?

    init(_ control: NSView, inset: CGFloat) {
        super.init(frame: .zero)
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            control.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        if let focusTarget { window?.makeFirstResponder(focusTarget) } else { super.mouseDown(with: event) }
    }
}

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

/// The Modern editor layout: a window backdrop, a top bar holding capture and annotation, the canvas across the full
/// width and a bottom bar holding document and output. Glass sits only on the command layer and never over the canvas;
/// every control is owned by the caller and re-parented here.
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
    private(set) var toolButtons: [String: GlassChromeButton] = [:]
    let hideButton, photosButton, saveButton, historyButton, snapButton, cancelFrameButton,
        fontButton, undoButton, wipeButton, resizeButton, shareButton: GlassChromeButton
    var backdropIsVisible: Bool { !backdrop.isHidden }
    var bleedIsVisible: Bool { !bleed.isHidden }

    /// Snap becomes Snap Frame, Cancel appears beside it, and the translucent backdrop gives way to the Frame-mode hole.
    var frameMode = false {
        didSet { if frameMode != oldValue { applyFrameMode() } }
    }

    var accessibility: ChromeAccessibility {
        didSet {
            for surface in surfaceList { surface.accessibility = accessibility }
            updateBackdropAndBleed()
        }
    }

    private let controls: SharedControls
    private let hideAction: Selector, undoAction: Selector
    private let toolOrder: [String]
    private let accessibilityProvider: @MainActor () -> ChromeAccessibility
    private let backdrop = NSVisualEffectView()
    private let bleed = NSBackgroundExtensionView()
    private let bleedImage = NSImageView()
    private var surfaces: [ObjectIdentifier: GlassSurfaceView] = [:]
    private var surfaceList: [GlassSurfaceView] = []

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
            if let toolTip { button.toolTip = toolTip }
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
        // Icon-only upload command: a native SF Symbol, no title, so nothing but the explicit label is read aloud.
        shareButton = GlassChromeButton(title: "", target: actions.target, action: actions.share)
        GlassChrome.useExtraLarge(shareButton)
        shareButton.image = NSImage(systemSymbolName: Self.uploadSymbolName, accessibilityDescription: "Upload")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: GlassChrome.Metrics.iconPointSize, weight: .regular))
        shareButton.imagePosition = .imageOnly
        shareButton.toolTip = "Upload"
        super.init(frame: .zero)
        build(actions: actions)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
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

    @objc private func displayOptionsChanged(_ notification: Notification) {
        accessibility = accessibilityProvider()
    }

    /// The thumbnail that bleeds under the bars; nil, Frame mode, Reduce Transparency or the flag hide it.
    func updateCanvasBleed(_ image: NSImage?) {
        bleedImage.image = image
        updateBackdropAndBleed()
    }

    func surface(for control: NSView) -> GlassSurfaceView? {
        if let known = surfaces[ObjectIdentifier(control)] { return known }
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
        updateBackdropAndBleed()
    }

    /// The app re-titles and re-tips Snap itself when entering or leaving Frame mode; this puts the Modern icon, name and tooltip back.
    func syncSnapPresentation() {
        snapButton.icon = frameMode ? .frameViewfinder : .crosshairs
        snapButton.title = frameMode ? "Snap Frame" : "Snap"
        snapButton.iconPointSize = GlassChrome.Metrics.primaryIconPointSize
        snapButton.toolTip = frameMode ? Self.snapFrameToolTip : Self.snapToolTip
    }

    private func updateBackdropAndBleed() {
        backdrop.isHidden = frameMode
        bleed.isHidden = !(GlassChrome.usesCanvasBleed && !accessibility.reduceTransparency && !frameMode && bleedImage.image != nil)
    }

    // MARK: construction

    static let uploadSymbolName = "icloud.and.arrow.up"

    private func register(_ surface: GlassSurfaceView, for views: NSView...) {
        if !surfaceList.contains(where: { $0 === surface }) { surfaceList.append(surface) }
        for view in views { surfaces[ObjectIdentifier(view)] = surface }
    }

    /// Every icon-only command shares one glass size so the bars read as one set.
    private func iconPill(_ control: NSView, size: NSSize = GlassChrome.Metrics.iconButton) -> GlassSurfaceView {
        let surface = GlassChrome.surface(control, shape: .capsule, accessibility: accessibility, size: size)
        register(surface, for: control)
        return surface
    }

    private func readable(_ control: NSControl) {
        control.font = DesignTokens.Typography.floored(control.font)
    }

    private func build(actions: Actions) {
        typealias Metrics = GlassChrome.Metrics
        let margin: CGFloat = 12, gap: CGFloat = 8, groupGap = Metrics.groupGap
        let headerTop: CGFloat = 4, rowHeight: CGFloat = 44, footerBottom: CGFloat = 8

        for control in [controls.dragFormatControl, controls.toolbox, controls.paletteButton] as [NSControl] { GlassChrome.useExtraLarge(control) }
        for control in [controls.dragFormatControl, controls.toolbox, controls.status, controls.zoomControl, controls.dragOriginalControl, controls.widthControl] as [NSControl] { readable(control) }
        // Color shows only its swatch: the title stays on the control (and its accessibility label) but is never drawn.
        controls.paletteButton.isBordered = false
        controls.paletteButton.imagePosition = .imageOnly
        controls.paletteButton.toolTip = "Color: " + (controls.paletteButton.toolTip.map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? "pick a drawing color")
        controls.widthControl.toolTip = "Size"
        controls.status.textColor = .labelColor
        controls.status.lineBreakMode = .byTruncatingTail
        controls.status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controls.status.setContentHuggingPriority(.defaultLow, for: .horizontal)

        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        bleedImage.imageScaling = .scaleAxesIndependently
        bleed.contentView = bleedImage
        bleed.alphaValue = 0.6
        bleed.isHidden = true
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = controls.canvas
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Top bar: [Hide][Toolbox][Photos] · [Snap][Cancel] · ten tools · [Color][Size][Font]
        header.identifier = NSUserInterfaceItemIdentifier("OpenSnapHeader")
        let toolboxIcon = ChromeIcons.resolve(.toolbox, family: .regular, pointSize: Metrics.iconPointSize)
        if let image = toolboxIcon.image, let first = controls.toolbox.itemArray.first {
            first.image = image
            controls.toolbox.imagePosition = .imageOnly
        }
        controls.toolbox.isBordered = false
        controls.toolbox.contentTintColor = .labelColor
        let hideSurface = iconPill(hideButton)
        let toolboxHolder = ControlHolderView(controls.toolbox, inset: 8)
        let toolboxSurface = GlassChrome.surface(toolboxHolder, shape: .capsule, accessibility: accessibility,
                                                 size: Metrics.toolboxButton)
        register(toolboxSurface, for: controls.toolbox, toolboxHolder)
        let photosSurface = iconPill(photosButton)
        let leadingGroup = GlassChrome.group([hideSurface, toolboxSurface, photosSurface], orientation: .horizontal, identifier: "GlassHeaderLeading")

        // Capture: Snap stays put; Cancel joins it on the right in Frame mode only (a hidden surface collapses out of the stack).
        snapButton.isPrimary = true
        snapButton.toolTip = Self.snapToolTip
        cancelFrameButton.isHidden = true
        let snapSurface = iconPill(snapButton, size: Metrics.primaryButton)
        snapSurface.prominence = .primary
        let cancelSurface = iconPill(cancelFrameButton)
        let captureGroup = GlassChrome.group([snapSurface, cancelSurface], orientation: .horizontal, identifier: "GlassCaptureGroup")

        // The ten tools, archive order, icon only.
        var toolSurfaces: [GlassSurfaceView] = []
        for id in toolOrder {
            guard let icon = Self.toolIcons[id] else { continue }
            let button = GlassChromeButton(title: "", target: actions.target, action: actions.chooseTool)
            button.identifier = NSUserInterfaceItemIdentifier(id)
            button.setButtonType(.toggle)
            button.iconPointSize = Metrics.iconPointSize
            button.icon = icon
            button.setAccessibilityLabel(id.capitalized)
            button.toolTip = id.capitalized + " tool"
            let surface = GlassChrome.surface(button, shape: .rounded(Metrics.toolRadius), accessibility: accessibility, size: Metrics.toolButton)
            register(surface, for: button)
            toolButtons[id] = button
            toolSurfaces.append(surface)
        }
        let toolGroup = GlassChrome.group(toolSurfaces, orientation: .horizontal, identifier: "GlassToolBar", spacing: Metrics.toolSpacing)

        // Annotation: Color, Size (a pill that opens its popover) and Font sit beside the tools they modify.
        let colorSurface = iconPill(controls.paletteButton)
        let sizeSurface = iconPill(controls.widthControl)
        let fontSurface = iconPill(fontButton)
        let annotationGroup = GlassChrome.group([colorSurface, sizeSurface, fontSurface], orientation: .horizontal, identifier: "GlassAnnotationGroup")

        let headerGroups = [leadingGroup, captureGroup, toolGroup, annotationGroup]
        for view in headerGroups {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
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
        let undoSurface = iconPill(undoButton)
        let wipeSurface = iconPill(wipeButton)
        let undoWipeGroup = GlassChrome.group([undoSurface, wipeSurface], orientation: .horizontal, identifier: "GlassUndoWipeGroup")

        // The zoom popup sits in a glass capsule, sized once for its widest face (the percentage alone) so it never jumps.
        let zoomInset: CGFloat = 4
        controls.zoomControl.isBordered = false
        let zoomHolder = ControlHolderView(controls.zoomControl, inset: zoomInset)
        let selectedZoom = controls.zoomControl.indexOfSelectedItem
        let widestZoom = (0..<controls.zoomControl.numberOfItems).filter { controls.zoomControl.item(at: $0)?.tag != ZoomPopUpButton.actualSizeTag && controls.zoomControl.item(at: $0)?.isSeparatorItem == false }.map { index -> CGFloat in
            controls.zoomControl.selectItem(at: index); return controls.zoomControl.fittingSize.width
        }.max() ?? 0
        if selectedZoom >= 0 { controls.zoomControl.selectItem(at: selectedZoom) }
        let zoomSurface = GlassChrome.surface(zoomHolder, shape: .capsule, accessibility: accessibility,
                                              size: NSSize(width: ceil(widestZoom) + 2 * zoomInset, height: Metrics.commandHeight))
        register(zoomSurface, for: controls.zoomControl, zoomHolder)
        let resizeSurface = iconPill(resizeButton)
        let viewGroup = GlassChrome.group([zoomSurface, resizeSurface], orientation: .horizontal, identifier: "GlassViewGroup")

        let saveSurface = iconPill(saveButton)
        let historySurface = iconPill(historyButton)
        let saveGroup = GlassChrome.group([saveSurface, historySurface], orientation: .horizontal, identifier: "GlassSaveGroup")

        let formatControl = controls.dragFormatControl
        let formatInset: CGFloat = 4
        let formatHolder = ControlHolderView(formatControl, inset: formatInset)
        (formatControl as? NSPopUpButton)?.isBordered = false
        // A popup sizes to its selected title, so measure every title and size the capsule once for the widest: it hugs the content and never jumps.
        let widestFormat: CGFloat
        if let popup = formatControl as? NSPopUpButton {
            let selectedFormat = popup.indexOfSelectedItem
            widestFormat = (0..<popup.numberOfItems).map { index -> CGFloat in popup.selectItem(at: index); return popup.fittingSize.width }.max() ?? 0
            popup.selectItem(at: selectedFormat)
        } else { widestFormat = formatControl.fittingSize.width }
        let formatSurface = GlassChrome.surface(formatHolder, shape: .capsule, accessibility: accessibility,
                                                size: NSSize(width: ceil(widestFormat) + 2 * formatInset, height: Metrics.commandHeight))
        register(formatSurface, for: controls.dragFormatControl, formatHolder)
        let dragSurface = GlassChrome.surface(controls.dragExportView, shape: .capsule, accessibility: accessibility,
                                              size: Metrics.iconButton)
        register(dragSurface, for: controls.dragExportView)
        let shareSurface = iconPill(shareButton)
        shareButton.setAccessibilityLabel("Upload to destination")
        let footerGroup = GlassChrome.group([formatSurface, dragSurface, shareSurface], orientation: .horizontal, identifier: "GlassFooterRow")
        if let stack = footerGroup.contentView as? NSStackView { stack.distribution = .fill }

        // The status takes whatever width the groups leave; the Original size checkbox only exists for a large shot.
        let statusRow = NSStackView(views: [controls.dragOriginalControl, controls.status])
        statusRow.orientation = .horizontal
        statusRow.spacing = 12
        statusRow.alignment = .centerY
        statusRow.identifier = NSUserInterfaceItemIdentifier("OpenSnapStatusRow")

        let footer = NSView()
        footer.identifier = NSUserInterfaceItemIdentifier("OpenSnapFooter")
        let footerParts: [NSView] = [undoWipeGroup, viewGroup, statusRow, saveGroup, footerGroup]
        for part in footerParts {
            part.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(part)
        }
        let all: [NSView] = [backdrop, bleed, scrollView, header, footer]
        for view in all { view.translatesAutoresizingMaskIntoConstraints = false }
        for view in all { addSubview(view) }
        addSubview(controls.canvasBorder)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor), backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor), backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            bleed.leadingAnchor.constraint(equalTo: leadingAnchor), bleed.trailingAnchor.constraint(equalTo: trailingAnchor),
            bleed.topAnchor.constraint(equalTo: topAnchor), bleed.bottomAnchor.constraint(equalTo: bottomAnchor),

            header.topAnchor.constraint(equalTo: topAnchor, constant: headerTop),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            header.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -footerBottom),
            footer.heightAnchor.constraint(equalToConstant: rowHeight),
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
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: gap),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -gap)
        ])

        // Only the mirrored edge of the thumbnail shows under the bars; the canvas area itself stays clear.
        bleed.additionalSafeAreaInsets = NSEdgeInsets(
            top: headerTop + Metrics.headerHeight + gap, left: margin,
            bottom: footerBottom + rowHeight + gap, right: margin)
        updateBackdropAndBleed()
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
