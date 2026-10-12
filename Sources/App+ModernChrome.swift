import AppKit

/// The main window's size and memory. The numbers are decisions, not measurements: see OSN-043 in docs/design/progress.md.
enum MainWindowFrame {
    /// AppKit stores a window's frame under "NSWindow Frame <autosave name>" in the app's defaults.
    static let autosaveName = "OpenSnap.Main"
    static func defaultsKey(_ name: String) -> String { "NSWindow Frame " + name }
    static func savedFrame(named name: String, in defaults: UserDefaults) -> String? {
        defaults.string(forKey: defaultsKey(name)).flatMap { $0.isEmpty ? nil : $0 }
    }

    static let untitled = "Untitled"
    /// A fresh window's content size.
    static let defaultContentSize = NSSize(width: 1120, height: 780)
    /// Window height, title bar included: content 608 plus the 32 pt title bar. Every 980 x 640 fit and capture is measured here,
    /// so the 680 pt of the T8 draft is not adopted.
    static let minimumHeight: CGFloat = 640
    /// What Frame says when it is refused in full screen.
    static let exitFullScreenForFrame = "Exit full screen to use Frame"

    /// The default size, brought down to a small screen: never taller or wider than the visible area leaves room for.
    static func defaultContentSize(fittingScreen visible: NSSize) -> NSSize {
        NSSize(width: min(defaultContentSize.width, visible.width), height: min(defaultContentSize.height, visible.height - 32))
    }
}

extension AppDelegate {
    /// Frame mode already shows and hides Cancel in AppDelegate; the chrome mirrors it into the glass layer.
    func setModernFrameMode(_ on: Bool) {
        let chrome = modernChrome as? ModernEditorChrome
        chrome?.frameMode = on
        chrome?.syncSnapPresentation()
        if !on { AppToolTip.setText(nil, for: status); status.spokenValue = nil; status.setAccessibilityHelp(nil) }
    }

    /// Modern has no name field: the window title is the document name ("Untitled" for a new one), not the app's name.
    func showDocumentName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        window.title = trimmed.isEmpty ? MainWindowFrame.untitled : trimmed
    }

    /// The title bar reads as part of the chrome: no separator line, and the title bar shows the window's own surface colour
    /// instead of its material (measured: the opaque title bar is 41/40/39 over a 30/30/30 window in dark, with a 1 pt line).
    /// Frame mode makes it opaque again (enterFrame) because the clear window would otherwise clear it too.
    /// The title and subtitle text themselves are drawn by the system, at the system's size.
    func configureWindowChrome() {
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.backgroundColor = DesignTokens.Palette.Surface.window
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.representedURL = currentURL
    }

    /// Shows the window where it was left. With no saved frame it opens centred at the default size.
    /// The saved frame is read from `frameDefaults` and applied here; AppKit then keeps saving every move and resize under the name.
    func restoreWindowFrame() {
        guard let name = frameAutosaveName else { window.center(); return }
        if let saved = MainWindowFrame.savedFrame(named: name, in: frameDefaults) { window.setFrame(from: saved) }
        else { window.center() }
        window.setFrameAutosaveName(name)
    }

    /// What this process's window is built from, so tools/test-native-startup.py can tell the glass chrome really built.
    func appearanceEvidence() -> [String: Any] {
        var glassSurfaces = 0
        func count(_ view: NSView) {
            if view is NSGlassEffectView { glassSurfaces += 1 }
            view.subviews.forEach(count)
        }
        if let content = window.contentView { count(content) }
        return ["modernChrome": modernChrome != nil,
                "toolButtonClass": toolButtons[.brush].map { String(describing: type(of: $0)) } ?? "none",
                "glassSurfaces": glassSurfaces]
    }
}

extension AppDelegate {
    /// The Modern counterpart of buildWindow(): the same controls and behaviors, laid out by ModernEditorChrome.
    /// The chrome sizes the shared controls and owns the canvas border.
    func buildModernWindowContent() {
        FontAwesomeFont.registerBundledFonts()
        let content = FrameChromeView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = content
        let toolbox = bezelToolbox()

        colorWell.color = OriginalDrawingControls.presets[0].color; colorWell.target = self; colorWell.action = #selector(changeColor(_:))
        paletteButton.font = DesignTokens.Typography.font(.body); paletteButton.target = self; paletteButton.action = #selector(showDrawingColors(_:))
        paletteButton.imagePosition = .imageLeading; paletteButton.setAccessibilityLabel("Drawing colors")
        AppToolTip.setText("Hover for original preset colors; hold Shift to change the canvas background", for: paletteButton)
        paletteButton.setAccessibilityHelp("Opens the preset colors. Hold Shift to change the canvas background instead.")
        paletteButton.onHover = { [weak self] inside in self?.drawingColorHover(inside, palette: false) }
        sizeLabel.font = DesignTokens.Typography.font(.body)
        widthControl.target = self; widthControl.action = #selector(changeWidth(_:))
        widthControl.onBegin = { [weak self] in
            guard let self, !self.terminationStarted, !self.frameCaptureInProgress, self.window.attachedSheet == nil else { return false }
            self.canvas.editingUndoManager.beginUndoGrouping(); self.sizeUndoGrouping = true; return true
        }
        widthControl.onEnd = { [weak self] in self?.endDrawingSizeGesture() }
        dragOriginalControl.title = "Original size"; dragOriginalControl.font = DesignTokens.Typography.font(.body)
        dragOriginalControl.target = self; dragOriginalControl.action = #selector(changeDragOptions(_:))
        dragOriginalControl.state = (UserDefaults.standard.object(forKey: "DragOriginalSize") as? Bool ?? true) ? .on : .off
        dragOriginalControl.setAccessibilityLabel("Export at original size")
        // The box sits beside the zoom, so it says what it measures: the size of the dragged-out, exported and uploaded picture.
        AppToolTip.setText("Drag out, copy, export and upload the picture at its own pixel size, not the size it is shown at", for: dragOriginalControl)
        nameField.placeholderString = "Image name"
        zoomControl.addItems(withTitles: ["25%", "50%", "75%", "100%", "150%", "200%"])
        for (index, item) in zoomControl.itemArray.enumerated() { item.representedObject = [0.25, 0.5, 0.75, 1, 1.5, 2][index] }
        zoomControl.selectItem(withTitle: "100%"); zoomControl.font = DesignTokens.Typography.font(.body)
        // Actual Size is the live main-menu command (same action, target and key equivalent), copied so the menu stays the source of truth.
        if let actual = copiedMainMenuItem(#selector(toggleActualSize)) {
            actual.tag = ZoomPopUpButton.actualSizeTag
            zoomControl.menu?.addItem(.separator()); zoomControl.menu?.addItem(actual)
        }
        if let zoomMenu = zoomControl.menu { MenuTypography.apply(to: zoomMenu) }
        zoomControl.target = self; zoomControl.action = #selector(changeZoom(_:)); zoomControl.setAccessibilityLabel("Canvas zoom")
        AppToolTip.setText(Self.zoomTooltip(spoken: nil), for: zoomControl)
        let drag = DragExportView(); dragExportView = drag
        drag.drawsBackground = false
        configureDragExport(drag)
        drag.showsHandIconOnly = true
        AppToolTip.setText("Drag the drawing into Finder or another app", for: drag)
        AppToolTip.setText(FormatToggle.toolTip, for: dragFormatToggle)
        dragFormatToggle.target = self; dragFormatToggle.action = #selector(changeDragOptions(_:))
        dragFormatToggle.selectedSegment = FormatToggle.segment(forStoredChoice: UserDefaults.standard.integer(forKey: FormatToggle.defaultsKey))
        status.font = DesignTokens.Typography.font(.caption); status.lineBreakMode = .byTruncatingTail
        status.setAccessibilityRole(.staticText)

        let controls = ModernEditorChrome.SharedControls(
            canvas: canvas, canvasBorder: canvasBorder, status: status, sizeLabel: sizeLabel,
            widthControl: widthControl, paletteButton: paletteButton, zoomControl: zoomControl, dragFormatControl: dragFormatToggle,
            dragOriginalControl: dragOriginalControl, dragExportView: drag, toolbox: toolbox)
        let actions = ModernEditorChrome.Actions(
            target: self, hide: #selector(vanish), photos: #selector(showPhotos), saveHistory: #selector(saveHistory),
            showHistory: #selector(showHistory), chooseTool: #selector(chooseTool(_:)), snap: #selector(snapButtonPressed),
            cancelFrame: #selector(cancelFrame), font: #selector(chooseFont), undo: #selector(undo),
            wipe: #selector(wipe), resize: #selector(resize), share: #selector(share(_:)))
        let originalToolOrder: [SketchTool] = [.select, .brush, .line, .ellipse, .rectangle, .fill, .eraser, .text, .arrow]
        let chrome = ModernEditorChrome(controls: controls, actions: actions, toolOrder: (originalToolOrder + [.crop]).map(\.rawValue))
        chrome.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor), chrome.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: content.topAnchor), chrome.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        content.canvasScrollView = chrome.scrollView
        modernChrome = chrome
        chrome.fontButton.spokenValue = { [weak self] in self?.spokenTextStyle }
        window.minSize = NSSize(width: chrome.requiredWindowWidth(), height: MainWindowFrame.minimumHeight)
        nameField.onChange = { [weak self] name in self?.showDocumentName(name) }
        showDocumentName(nameField.stringValue)
        configureWebpostButton(chrome.shareButton)
        wireUploadControls(chrome.uploadControls)

        snapButton = chrome.snapButton; cancelFrameButton = chrome.cancelFrameButton
        resizeButton = chrome.resizeButton
        // The drag well draws its own glyph; the cell behind it fills for its press.
        drag.onInteractionChange = { [weak drag] in
            guard let drag, let cell = drag.superview as? ChromeFillCell else { return }
            cell.setPressed(drag.isPressed)
        }
        chrome.snapButton.alternateTarget = self
        chrome.snapButton.alternateAction = #selector(fullscreenSnap)
        for tool in SketchTool.allCases {
            guard let button = chrome.toolButtons[tool.rawValue] else { continue }
            toolButtons[tool] = button
            trackHint(button, owner: "tool-" + tool.rawValue) { OriginalHintMessages.hover(tool: tool) }
        }
        trackHint(chrome.wipeButton, owner: "wipe") { OriginalHintMessages.hover(actionTag: 50) }
        trackHint(widthControl, owner: "drawing-size") { OriginalHintMessages.hover(actionTag: 20) }

        wireEditorChrome(scroll: chrome.scrollView)
        setTool(.arrow, source: .launch)
        AppToolTip.install(on: content)
    }
}
