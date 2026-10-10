import AppKit

extension AppDelegate {
    /// Frame mode already shows and hides Cancel in AppDelegate; the chrome mirrors it into the glass layer.
    func setModernFrameMode(_ on: Bool) {
        let chrome = modernChrome as? ModernEditorChrome
        chrome?.frameMode = on
        chrome?.syncSnapPresentation()
        if !on { AppToolTip.setText(nil, for: status); status.spokenValue = nil; status.setAccessibilityHelp(nil) }
    }

    /// The Drag Me thumbnail doubles as the canvas bleed under the bars.
    func feedCanvasBleed() {
        (modernChrome as? ModernEditorChrome)?.updateCanvasBleed(dragExportView?.overview)
    }

    /// Modern has no name field: the window title is the document name.
    func showDocumentName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        window.title = trimmed.isEmpty ? DesignTokens.Brand.name : trimmed
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
        window.minSize.width = max(window.minSize.width, ModernEditorChrome.minimumWindowWidth)
        let content = FrameChromeView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = content
        let toolbox = bezelToolbox()

        colorWell.color = OriginalDrawingControls.presets[0].color; colorWell.target = self; colorWell.action = #selector(changeColor(_:))
        paletteButton.font = DesignTokens.Typography.font(.body); paletteButton.target = self; paletteButton.action = #selector(showDrawingColors(_:))
        paletteButton.imagePosition = .imageLeading; paletteButton.setAccessibilityLabel("Drawing colors")
        AppToolTip.setText("Hover for original preset colors; hold Shift to change the canvas background", for: paletteButton)
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
        dragOriginalControl.setAccessibilityLabel("Drag out at original size")
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
        let drag = DragExportView(); dragExportView = drag
        drag.drawsBackground = false
        configureDragExport(drag)
        drag.showsHandIconOnly = true
        AppToolTip.setText("Drag the drawing into Finder or another app", for: drag)
        dragFormatToggle.segmentStyle = .capsule
        dragFormatToggle.font = DesignTokens.Typography.font(.body)
        dragFormatToggle.setAccessibilityLabel("Image format")
        AppToolTip.setText(FormatToggle.toolTip, for: dragFormatToggle)
        for (index, title) in FormatToggle.titles.enumerated() { dragFormatToggle.setLabel(title, forSegment: index); dragFormatToggle.setWidth(0, forSegment: index) }
        dragFormatToggle.target = self; dragFormatToggle.action = #selector(changeDragOptions(_:))
        dragFormatToggle.selectedSegment = FormatToggle.segment(forStoredChoice: UserDefaults.standard.integer(forKey: FormatToggle.defaultsKey))
        status.font = DesignTokens.Typography.font(.caption); status.lineBreakMode = .byTruncatingTail

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
        nameField.onChange = { [weak self] name in self?.showDocumentName(name) }
        showDocumentName(nameField.stringValue)
        configureWebpostButton(chrome.shareButton)

        snapButton = chrome.snapButton; cancelFrameButton = chrome.cancelFrameButton
        resizeButton = chrome.resizeButton
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
        setTool(.arrow)
        AppToolTip.install(on: content)
    }
}
