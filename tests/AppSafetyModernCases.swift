// Glass-chrome integration cases: the real AppDelegate launch, with ModernEditorChrome as the window content.
#if APP_SAFETY_TESTS
import AppKit
import UniformTypeIdentifiers

extension AppSafetyTests {
    static var modernCases: [(String, () throws -> Void)] {
        return [
            ("Modern chrome fills the Frame-aware content view and replaces the old controls", modernWindowStructure),
            ("Modern shared controls keep the recovered accessibility labels, tooltips, titles and hint tracking", modernControlStrings),
            ("Every Modern command is icon-only with a native tooltip and its old title as the VoiceOver label, whatever the overlay preference says", modernIconOnlyCommands),
            ("setTool fills exactly one tool button and uses the solid family for every path that changes the tool", modernToolSelection),
            ("Frame enter and leave swap Snap and Cancel, clear and restore the Fullscreen alternate, and dim Resize", modernFrameMode),
            ("Modern Frame mode drops the window shadow, raises the level and sets alpha 0.8, and leaving restores the pre-Frame values", modernFrameWindowShadowLevelAlpha),
            ("The canvas well is solid surface.canvasWell; Frame mode punches the hole and leaving restores it; no backdrop or bleed remains", modernCanvasWell),
            ("G5 on the real window: 8 plates, no nested glass, no overlap with the well at default, minimum and Frame, one accent, no phantom", modernGlassDepth),
            ("Injected display options reach every glass surface and clear again", modernAccessibilityInjection),
            ("Header and footer buttons reach the real AppDelegate actions", modernActionRouting),
            ("Modern Wipe presses follow the blank/clear/wipe stages with the dimmed glass and the action spoken (Clear image, Remove annotations, Nothing to clear)", modernWipeStages),
            ("writeLayoutEvidence reports the Modern style and finds the header and brand one level deeper", modernLayoutEvidence),
            ("Main menu items carry symbols in Modern only and keep validating", modernMenus),
            ("Color panel hangs below the Color control, off the system appearance, as one glass container of two plates", modernPalettePopover),
            ("Color panel text is 20 pt, and under Reduce Transparency its plates are opaque and the text reads at 4.5:1 in light, dark and both Increase Contrast arms (audit fix 2)", modernPalettePopoverContrast),
            ("Color panel always shows the active colour: a checked preset, or the Custom color… row chosen with the colour's chip, a check, the selected fill and border; the plates are even", modernPaletteShowsActiveColor),
            ("Modern centres a small canvas in the editor area at default and minimum size and leaves larger and wide documents panning unconstrained", modernCanvasCentred),
            ("A small canvas is centred when only the document or zoom changes, with no window resize", modernCanvasCentresWithoutWindowResize),
            ("Hide and Undo tooltips read their shortcuts from the real menu items", modernShortcutHintsFollowMenu),
            ("Rename is unavailable during Frame capture and termination", modernRenameAvailability),
            ("The short Frame status hint fits whole at 980 and 1024 and the full sentence is its tooltip and accessibility value", modernFrameStatusFits),
            ("The Frame keyline outlines the canvas: four edges when it fits, the visible left and top when it overflows the hole", modernFrameKeylineFollowsCanvasEdges),
            ("Frame mode hides the Original size checkbox for a large shot and leaving Frame restores it", modernFrameHidesOriginalSize),
            ("The status drops bytes then tool, never the saved state, at every width with and without the Original size checkbox, and keeps the full text as tooltip and spoken value", modernStatusKeepsStateWhenNarrow),
            ("The zoom popup offers the main menu's Actual Size command, keeps a percentage face and follows the command's availability", modernZoomActualSize),
            ("A click at the visual centre of the centred canvas selects the element at the document centre", modernCanvasCentredHitTest),
            ("Modern puts capture, tools and annotation in the top bar, document and output in the bottom bar, and no rail", modernTopBarLayout),
            ("Modern has one footer row and no file-name field; the window title is the document name and Rename changes the export name", modernDocumentNameInTitle),
            ("Modern canvas border corner and edge mouse drags resize and crop with one Undo each, and Escape cancels", modernBorderGestures),
            ("The Size pill opens its panel below and every gesture, preset, key and assistive step is exactly one undo step, even when the panel is dismissed mid-drag", modernSizePopoverUndo),
            ("Frame mode snaps exactly the viewport (or the centred canvas inside the hole), hides the scrollers and restores them", modernFrameCaptureRect),
            ("The status carries the export size once, truncates with the full text as tooltip, and the drag-preview timer is not re-armed by it", modernStatusMergesDragSize),
            ("The zoom face is the percentage alone while VoiceOver and the tooltip carry the mode word", modernZoomFace),
            ("Every relocated control keeps its target and action, and the top and bottom bars run in reading order", modernRelocatedOwnership),
            ("OSN-041: controls are 20 pt body text; only the status line is the 18 pt caption", modernBodyType),
            ("The chrome's tooltips are app-owned at 20 pt: none left on the system, VoiceOver keeps the words, dynamic text stays live", modernAppToolTips),
            ("The two bars render in light and dark, normal and Frame mode, with the Size popover, and the bitmaps land in the evidence folder", modernLayoutBitmaps),
            ("Modern footer is a [PNG | JPG] toggle: PNG on a fresh install, JPG encodes drag, export and upload at 0.75, and a stored JPEG row reads as JPG", modernFormatToggle),
            ("OSN-044: the drag well is a keyboard-operable button: it takes focus, Space and Return open the Export panel, VoiceOver presses it, hover and press change its cursor and cell", modernDragWellKeyboard),
            ("OSN-044: the PNG | JPG toggle takes Left, Right and Space and a click through changeDragOptions and stores the same format as before", modernFormatToggleInput),
            ("OSN-044: the canvas border is a hairline at rest and shows its handles on hover or while the crop tool is chosen", modernBorderHandlesFollowTool),
            ("OSN-044: Differentiate Without Color and Increase Contrast reach the real tool buttons, the toggle and the Snap button", modernStateOptionsReachControls),
            ("The zoom opens a glass panel above the footer: percentages and the computed row are options, Actual Size is a toggle that keeps the percentage face and its refusal path", modernZoomPanel),
            ("Original size is a glass checkbox toggle on the View plate: it persists DragOriginalSize, shows only for a large shot, and gives the status slot its room back", modernOriginalSizeToggle)
        ]
    }

    private static func keyDown(_ code: UInt16, in app: AppDelegate) throws -> NSEvent {
        try (NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: app.window.windowNumber, context: nil,
                              characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)).unwrap("key event")
    }

    private static func modernDragWellKeyboard() throws {
        let (fixture, _) = try modernFixture()
        let app = fixture.app
        let drag = try (app.dragExportView).unwrap("drag well")
        try expect(drag.acceptsFirstResponder && drag.isAccessibilityElement() && drag.accessibilityRole() == .button && drag.accessibilityLabel() == DragExportView.accessibilityName
                   && DragExportView.accessibilityName == "Drag image to another app", "The drag well is a button named for what it does")
        try expect(app.window.makeFirstResponder(drag) && app.window.firstResponder === drag, "The drag well takes keyboard focus")
        try expect(drag.focusRingType == .exterior && !drag.focusRingMaskBounds.isEmpty, "It draws a focus ring through its mask")
        drag.updateTrackingAreas()
        try expect(drag.trackingAreas.contains { $0.options.contains(.mouseEnteredAndExited) && $0.options.contains(.inVisibleRect) }, "It tracks the pointer over its visible rect")

        // The real wiring: Space and Return reach the Export panel; the fake panel consumes the one answer queued for it.
        AppSafetyFilePanel.answers = [.init(response: .cancel), .init(response: .cancel), .init(response: .cancel)]
        try expect(drag.onActivate != nil, "The app wires the drag well to the Export panel")
        drag.keyDown(with: try keyDown(49, in: app))
        try expect(AppSafetyFilePanel.answers.count == 2, "Space opens the Export panel")
        drag.keyDown(with: try keyDown(36, in: app))
        try expect(AppSafetyFilePanel.answers.count == 1, "Return opens the Export panel")
        try expect(drag.accessibilityPerformPress() && AppSafetyFilePanel.answers.isEmpty, "VoiceOver's press opens the Export panel")
        AppSafetyFilePanel.answers = [.init(response: .cancel)]
        app.frameCaptureInProgress = true
        drag.keyDown(with: try keyDown(49, in: app))
        app.frameCaptureInProgress = false
        try expect(AppSafetyFilePanel.answers.count == 1, "Space does nothing while a Frame capture is running")
        AppSafetyFilePanel.answers = []

        // The seam, so Space, Return and keypad Enter are each exactly one press and other keys are not.
        var presses = 0
        let original = drag.onActivate
        drag.onActivate = { presses += 1 }
        for code: UInt16 in [49, 36, 76] { drag.keyDown(with: try keyDown(code, in: app)) }
        try expect(presses == 3, "Space, Return and Enter each press once (\(presses))")
        drag.keyDown(with: try keyDown(0, in: app))
        try expect(presses == 3 && drag.accessibilityPerformPress() && presses == 4, "Other keys do nothing; the assistive press runs the same action")
        drag.onActivate = nil
        try expect(!drag.accessibilityPerformPress(), "With nothing wired the press reports failure")
        drag.onActivate = original

        // Hover and press: open hand, closed hand, and the cell behind the well fills for the press.
        let cell = try (drag.superview as? ChromeFillCell).unwrap("the well's cell")
        try expect(drag.wellCursor === NSCursor.openHand && !cell.plate.isPressed, "At rest the pointer is an open hand")
        let down = try (NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: app.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)).unwrap("mouse down")
        drag.mouseEntered(with: down)
        try expect(drag.isHovered, "Hover is tracked by the well")
        drag.mouseExited(with: down)
        try expect(!drag.isHovered, "And cleared on exit")
        drag.mouseDown(with: down)
        try expect(drag.isPressed && drag.wellCursor === NSCursor.closedHand && cell.plate.isPressed && abs((cell.plate.style.fill?.alphaComponent ?? 0) - 0.16) < 0.004, "Held, the pointer is a closed hand and the cell shows the pressed fill")
        drag.mouseUp(with: down)
        try expect(!drag.isPressed && drag.wellCursor === NSCursor.openHand && !cell.plate.isPressed, "Released, it is open again")
    }

    private static func modernFormatToggleInput() throws {
        let defaults = UserDefaults.standard, key = FormatToggle.defaultsKey
        let saved = defaults.object(forKey: key)
        defer { if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) } }
        defaults.removeObject(forKey: key)
        let (fixture, _) = try modernFixture()
        let app = fixture.app, toggle = app.dragFormatToggle
        try expect(toggle.target === app && toggle.action == #selector(AppDelegate.changeDragOptions(_:)), "The toggle still routes to changeDragOptions")
        try expect(app.window.makeFirstResponder(toggle) && app.window.firstResponder === toggle, "The toggle takes keyboard focus")
        try expect(toggle.selectedSegment == 0 && app.dragFormat == "png" && app.dragQuality == 1.0, "PNG is the default and keeps transparency (quality 1)")
        toggle.keyDown(with: try keyDown(124, in: app))
        try expect(toggle.selectedSegment == 1 && app.dragFormat == "jpeg" && app.dragQuality == 0.75 && defaults.integer(forKey: key) == FormatToggle.jpgStoredChoice, "Right chooses JPG at 0.75 and stores a JPEG row")
        toggle.keyDown(with: try keyDown(123, in: app))
        try expect(toggle.selectedSegment == 0 && app.dragFormat == "png" && defaults.integer(forKey: key) == 0, "Left chooses PNG and stores row 0")
        toggle.keyDown(with: try keyDown(49, in: app))
        try expect(app.dragFormat == "jpeg" && defaults.integer(forKey: key) == FormatToggle.jpgStoredChoice, "Space switches to JPG")
        toggle.keyDown(with: try keyDown(49, in: app))
        try expect(app.dragFormat == "png", "Space switches back")
        func click(_ segment: Int) throws {
            let point = toggle.convert(NSPoint(x: toggle.segmentRect(segment).midX, y: toggle.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try (NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: app.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)).unwrap("click")
                type == .leftMouseDown ? toggle.mouseDown(with: event) : toggle.mouseUp(with: event)
            }
        }
        try click(1)
        try expect(toggle.selectedSegment == 1 && app.dragFormat == "jpeg" && defaults.integer(forKey: key) == FormatToggle.jpgStoredChoice, "A click on JPG chooses it")
        try click(0)
        try expect(toggle.selectedSegment == 0 && app.dragFormat == "png", "A click on PNG chooses it")
        // A finer stored JPEG row is kept when the segment is already JPG.
        defaults.set(4, forKey: key)
        toggle.selectedSegment = 1
        toggle.keyDown(with: try keyDown(123, in: app)); toggle.keyDown(with: try keyDown(124, in: app))
        try expect(defaults.integer(forKey: key) == FormatToggle.jpgStoredChoice, "Going PNG then JPG stores the standard JPEG row")
        // The footer must not grow: the toggle is narrower than the capsule it replaces.
        try expect(toggle.fittingSize.width <= 149 && toggle.fittingSize.height == 36, "The toggle is no wider than the 149 pt system capsule (\(toggle.fittingSize))")
    }

    private static func modernBorderHandlesFollowTool() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, border = app.canvasBorder
        app.setTool(.arrow)
        try expect(!border.showsHandles && !border.revealsHandles, "At rest with the arrow tool the border is a hairline")
        try (chrome.toolButtons["crop"]).unwrap("crop tool").performClick(nil)
        try expect(app.canvas.tool == .crop && border.showsHandles && border.revealsHandles, "Choosing the crop tool shows the handles")
        app.setTool(.brush)
        try expect(!border.showsHandles && !border.revealsHandles, "Leaving the crop tool hides them")
        app.canvas.tool = .crop
        try expect(border.showsHandles, "A tool change that does not come from the toolbar (Tab) counts too")
        app.canvas.tool = .arrow
        try expect(!border.showsHandles, "And back")
        border.setHovered(true)
        try expect(border.revealsHandles && !border.showsHandles, "Hovering the border reveals the handles without the crop tool")
        border.setHovered(false)
        try expect(!border.revealsHandles, "Moving away hides them")
    }

    private static func modernStateOptionsReachControls() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let buttons = collect(CommandButton.self, in: app.window.contentView!)
        for button in buttons { button.appearance = NSAppearance(named: .aqua) }
        app.dragFormatToggle.appearance = NSAppearance(named: .aqua)
        app.setTool(.brush)
        let brush = try (app.toolButtons[.brush] as? CommandButton).unwrap("brush")
        try expect(!brush.showsIndicator && abs((app.dragFormatToggle.style(ofSegment: 0).fill?.alphaComponent ?? 0) - 0.20) < 0.004, "Without options: no capsule, a 0.20 toggle fill")
        DisplayOptions.override = DisplayOptions(increaseContrast: true, differentiateWithoutColor: true)
        defer { DisplayOptions.override = nil }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try expect(brush.showsIndicator && brush.indicatorLayer.frame.size == NSSize(width: 16, height: 3), "The selected tool shows the capsule, 3 pt tall under Increase Contrast")
        try expect(abs((brush.plate.style.fill?.alphaComponent ?? 0) - 0.32) < 0.004, "Its fill is the strong 0.32")
        try expect(chrome.snapButton.layer?.borderWidth == 1 && !chrome.snapButton.showsIndicator, "Snap gains an Increase Contrast outline and no capsule")
        try expect(abs((app.dragFormatToggle.style(ofSegment: 0).fill?.alphaComponent ?? 0) - 0.32) < 0.004 && app.dragFormatToggle.accessibility.increaseContrast, "The toggle re-resolves for Increase Contrast")
        DisplayOptions.override = DisplayOptions.none
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try expect(!brush.showsIndicator && chrome.snapButton.layer?.borderWidth == 0 && abs((app.dragFormatToggle.style(ofSegment: 0).fill?.alphaComponent ?? 0) - 0.20) < 0.004, "Clearing the options clears all three")
    }

    private static func modernFormatToggle() throws {
        let defaults = UserDefaults.standard, key = FormatToggle.defaultsKey
        let saved = defaults.object(forKey: key)
        defer { if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) } }
        func isJPEG(_ d: Data) -> Bool { d.prefix(3) == Data([0xFF, 0xD8, 0xFF]) }
        func isPNG(_ d: Data) -> Bool { d.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) }

        defaults.removeObject(forKey: key)
        let (fresh, chrome) = try modernFixture()
        let app = fresh.app, toggle = app.dragFormatToggle
        try expect(toggle.segmentCount == 2 && toggle.label(forSegment: 0) == "PNG" && toggle.label(forSegment: 1) == "JPG", "The toggle has exactly the PNG and JPG segments")
        let segments = try (toggle.accessibilityChildren() as? [NSAccessibilityElement]).unwrap("the toggle's accessibility children")
        try expect(toggle.accessibilityRole() == .radioGroup && toggle.accessibilityLabel() == "Image format" && AppToolTip.text(for: toggle) == "Format for drag, export and upload", "Group role, label and tooltip")
        try expect(segments.map { $0.accessibilityLabel() ?? "" } == ["PNG", "JPG"] && segments.allSatisfy { $0.accessibilityRole() == .radioButton }, "VoiceOver reads two radio buttons, PNG and JPG, under Image format")
        try expect((0..<2).allSatisfy { toggle.textFont(forSegment: $0).pointSize >= 18 } && toggle.superview != nil && chrome.surface(for: toggle) != nil, "Text is at least 18 pt and the toggle sits in the glass footer")
        try expect(toggle.selectedSegment == 0 && app.dragFormat == "png", "PNG is selected on a fresh defaults domain")

        app.canvas.setBackgroundColor(.clear)
        var shape = SketchElement(kind: .rectangle)
        shape.rect = CGRect(x: 20, y: 20, width: 60, height: 40)
        shape.filled = true; shape.color = SketchColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
        app.canvas.document.elements.append(shape)
        let png = try app.exportData(format: app.dragFormat, originalSize: false, jpegQuality: app.dragQuality)
        let pngRep = try (NSBitmapImageRep(data: png)).unwrap("PNG decodes")
        try expect(isPNG(png) && pngRep.hasAlpha, "The PNG payload has an alpha channel")
        try expect((pngRep.colorAt(x: 2, y: 2)?.alphaComponent ?? 1) < 0.01 && (pngRep.colorAt(x: 50, y: 40)?.alphaComponent ?? 0) > 0.99, "A transparent pixel stays alpha 0 and the drawn pixel is opaque")
        try expect(app.uploadEncoding.format == "png" && app.uploadEncoding.fileExtension == "png", "Upload is PNG by default")

        toggle.selectedSegment = 1
        app.changeDragOptions(toggle)
        try expect(app.dragFormat == "jpeg" && app.dragQuality == 0.75, "JPG selects JPEG at quality 0.75")
        let jpg = try app.exportData(format: app.dragFormat, originalSize: false, jpegQuality: app.dragQuality)
        try expect(isJPEG(jpg), "The JPG payload starts with the JPEG magic bytes")
        let want = try app.canvas.imageData(format: "jpeg", jpegQuality: 0.75).unwrap("reference")
        let other = [0.7, 1.0].compactMap { app.canvas.imageData(format: "jpeg", jpegQuality: $0) }
        try expect(jpg == want && other.allSatisfy { $0 != want }, "The JPG payload is exactly the 0.75 encoding, not 0.7 or 1.0")
        let flat = try (NSBitmapImageRep(data: jpg)).unwrap("JPEG decodes")
        try expect((flat.colorAt(x: 2, y: 2)?.redComponent ?? 0) > 0.97 && (flat.colorAt(x: 2, y: 2)?.greenComponent ?? 0) > 0.97, "JPG composites transparency onto white")
        let drag = try (app.dragExportView).unwrap("drag"), payload = try (drag.prepare?()).unwrap("drag payload")
        try expect(payload.format == "jpeg" && payload.data == want, "The real drag payload bytes are exactly the 0.75 encoding")
        let provider = NSFilePromiseProvider(fileType: UTType.jpeg.identifier, delegate: drag)
        try expect(drag.beginExport(provider: provider, payload: payload, controlRect: .zero), "The drag begins")
        let promised = drag.filePromiseProvider(provider, fileNameForType: UTType.jpeg.identifier)
        drag.endExport(provider: ObjectIdentifier(provider), succeeded: false)
        try expect(promised == payload.name + ".jpg", "The dragged JPEG file is named .jpg like uploads: \(promised)")
        let upload = try app.uploadPayload().unwrap("upload payload")
        try expect(upload.0 == want && upload.1 == "jpg", "The real upload bytes are the 0.75 encoding with a .jpg name")
        try expect(app.uploadEncoding.format == "jpeg" && app.uploadEncoding.quality == 0.75 && app.uploadEncoding.fileExtension == "jpg", "Upload follows the toggle")
        defaults.set(0.3, forKey: "ExportQuality")
        defer { defaults.removeObject(forKey: "ExportQuality") }
        let accessory = app.exportPanelAccessory()
        try expect(accessory.format == "jpeg" && accessory.effectiveJPEGQuality == 0.75, "The real export accessory is JPEG at 0.75 despite a stored 0.3")
        accessory.jpegQuality = 0.3
        func everyView(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(everyView) }
        let panelViews = everyView(accessory.view)
        try expect(panelViews.compactMap { $0 as? NSSlider }.isEmpty && panelViews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "JPG quality 75%" },
                   "The export quality is stated as 'JPG quality 75%', not offered as a slider (OSN-054)")
        try expect(try app.exportPanelData(accessory) == want, "The real export bytes are exactly the 0.75 encoding")
        let historyID = try app.archiveStore().archive(try app.historySnapshot(), name: "Toggle", action: .archived)
        let history = try app.historyExport(historyID, format: "jpeg")
        let stored = CanvasView(frame: .zero)
        try stored.loadDocument(data: try app.archiveStore().read(historyID).canvasData)
        let historyWant = try stored.imageData(format: "jpeg", jpegQuality: 0.75).unwrap("history reference")
        let historyOther = try stored.imageData(format: "jpeg", jpegQuality: 0.7).unwrap("history 0.7")
        try expect(history == historyWant && history != historyOther, "The real History export is the 0.75 encoding, not 0.7")
        try expect(defaults.integer(forKey: key) == FormatToggle.jpgStoredChoice, "Choosing JPG stores a JPEG row in the shared preference")

        for (stored, segment) in [(0, 0), (1, 1), (3, 1), (5, 1), (6, 0), (11, 0), (-1, 0), (99, 0)] {
            try expect(FormatToggle.segment(forStoredChoice: stored) == segment, "Stored row \(stored) maps to segment \(segment)")
        }
        defaults.set(4, forKey: key)
        let legacy = try Fixture()
        try expect(legacy.app.dragFormatToggle.selectedSegment == 1 && legacy.app.dragFormat == "jpeg" && legacy.app.dragQuality == 0.75, "A legacy stored JPEG quality row shows as JPG at 0.75")
        legacy.app.dragFormatToggle.selectedSegment = 0
        legacy.app.changeDragOptions(nil)
        try expect(defaults.integer(forKey: key) == 0, "Choosing PNG stores row 0")
    }

    // MARK: fixtures and walkers

    private static func canvasMargins(_ app: AppDelegate, _ chrome: ModernEditorChrome) -> (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let area = chrome.scrollView.contentView.frame
        let rect = chrome.scrollView.convert(app.canvas.bounds, from: app.canvas)
        return (rect.minX - area.minX, area.maxX - rect.maxX, rect.minY - area.minY, area.maxY - rect.maxY)
    }

    private static func modernTopBarLayout() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let content = try (app.window.contentView).unwrap("content view")
        let defaultFrame = app.window.frame
        for (name, frame) in [("default", defaultFrame), ("minimum", CGRect(origin: defaultFrame.origin, size: app.window.minSize))] {
            app.setWindowFrame(frame)
            content.layoutSubtreeIfNeeded(); app.updateViewportChrome()
            let bar = chrome.header.convert(chrome.header.bounds, to: content)
            let footer = try descendant(chrome, identifier: "OpenSnapFooter").unwrap("bottom bar")
            let bottom = footer.convert(footer.bounds, to: content)
            let topControls: [(String, NSView)] = Array(chrome.toolButtons).map { ($0.key, $0.value) } + [("snap", chrome.snapButton), ("color", app.paletteButton), ("size", app.widthControl),
                ("font", chrome.fontButton), ("hide", chrome.hideButton), ("photos", chrome.photosButton)]
            for (id, view) in topControls {
                let frame = view.convert(view.bounds, to: content)
                try expect(bar.insetBy(dx: -0.5, dy: -0.5).contains(frame) && content.bounds.contains(frame), "\(name): \(id) sits unclipped in the top bar")
            }
            let bottomControls: [(String, NSView)] = [("undo", chrome.undoButton), ("wipe", chrome.wipeButton), ("resize", chrome.resizeButton), ("zoom", app.zoomControl), ("status", app.status),
                ("save", chrome.saveButton), ("history", chrome.historyButton), ("format", app.dragFormatToggle), ("drag", try (app.dragExportView).unwrap("drag")), ("upload", chrome.shareButton)]
            for (id, view) in bottomControls {
                let frame = view.convert(view.bounds, to: content)
                try expect(bottom.insetBy(dx: -0.5, dy: -0.5).contains(frame) && content.bounds.contains(frame), "\(name): \(id) sits unclipped in the bottom bar")
            }
            try expect(!chrome.resizeButton.isDescendant(of: chrome.header), "\(name): Resize left the tool row for the bottom bar")
            let ordered = chrome.header.subviews.sorted { $0.frame.minX < $1.frame.minX }
            for pair in zip(ordered, ordered.dropFirst()) {
                try expect(pair.0.frame.maxX <= pair.1.frame.minX + 0.5, "\(name): top bar groups do not overlap")
            }
            try expect(chrome.header.subviews.count == 4, "\(name): the top bar is [Hide/Toolbox/Photos], [Snap/Cancel], the tools and [Color/Size/Font]")
            var all: [NSView] = []
            func walk(_ view: NSView) { all.append(view); view.subviews.forEach(walk) }
            walk(chrome)
            let ids = Set(all.compactMap { $0.identifier?.rawValue })
            try expect(ids.isDisjoint(with: ["GlassToolRail", "GlassDrawingGroup", "GlassHistoryGroup", "GlassHeaderTrailing"]), "\(name): no rail or vertical group (\(ids.sorted()))")
            let area = chrome.scrollView.convert(chrome.scrollView.bounds, to: content)
            try expect(abs(area.minX - 12) < 0.5, "\(name): the canvas viewport starts at the left margin (\(area.minX))")
            try expect(abs(area.maxX - (content.bounds.width - 12)) < 0.5, "\(name): the viewport runs to the right margin (\(area.maxX) vs \(content.bounds.width - 12))")
            try expect(area.maxY <= bar.minY - 7.5 && area.minY >= bottom.maxY + 7.5, "\(name): the viewport sits between the bars with 8 pt gaps")
            let undo = chrome.undoButton.convert(chrome.undoButton.bounds, to: content), wipe = chrome.wipeButton.convert(chrome.wipeButton.bounds, to: content)
            try expect(undo.maxX < wipe.minX && abs(undo.midY - wipe.midY) < 0.5, "\(name): Wipe sits beside Undo")
        }
    }

    private static func modernDocumentNameInTitle() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let content = try (app.window.contentView).unwrap("content view")
        var all: [NSView] = []
        func walk(_ view: NSView) { all.append(view); view.subviews.forEach(walk) }
        walk(content)
        try expect(app.nameField.superview == nil && !all.contains { ($0 as? NSTextField)?.isEditable == true }, "Modern has no editable file-name field on screen")
        try expect(!all.contains { ($0 as? NSButton)?.title == "Actual Size" }, "Modern has no Actual Size button")
        let footer = try all.first { $0.identifier?.rawValue == "OpenSnapFooter" }.unwrap("footer row")
        let row = footer.convert(footer.bounds, to: content)
        for part in [chrome.undoButton, chrome.wipeButton, app.zoomControl, chrome.resizeButton, app.status, chrome.saveButton, chrome.historyButton,
                     app.dragFormatToggle, try (app.dragExportView).unwrap("drag"), chrome.shareButton] as [NSView] {
            let frame = part.convert(part.bounds, to: content)
            try expect(row.insetBy(dx: -0.5, dy: -0.5).contains(frame) && abs(frame.midY - row.midY) <= 6, "The footer row holds \(part)")
        }
        try expect(footer.subviews.count == 5, "The footer is one row of four glass plates and the status")
        try expect(app.window.title == app.nameField.stringValue, "The window title shows the document name: \(app.window.title)")
        let file = try NSApp.mainMenu.unwrap("main menu").items.compactMap(\.submenu).first { $0.title == "File" }.unwrap("File menu")
        try expect(file.items.contains { $0.action == #selector(AppDelegate.renameDocument) && $0.title == "Rename…" }, "File has a Rename… command")
        app.applyDocumentName("  Quarterly report ")
        try expect(app.window.title == "Quarterly report" && app.nameField.stringValue == "Quarterly report", "Renaming updates the title: \(app.window.title)")
        app.applyDocumentName("   ")
        try expect(app.window.title == "Quarterly report", "A blank rename is ignored")
        let payload = try (app.dragExportView?.prepare?()).unwrap("drag payload")
        try expect(payload.name == "Quarterly report" && app.safeName() == "Quarterly report", "The drag and export file name follows the rename: \(payload.name)")
        app.nameField.stringValue = "Direct"
        try expect(app.window.title == "Direct" && app.safeName() == "Direct", "Setting the document name directly also updates the title")
    }

    private static func modernCanvasCentred() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        try viewportFixture(app)
        let defaultFrame = app.window.frame
        for (name, frame) in [("default", defaultFrame), ("minimum", CGRect(origin: defaultFrame.origin, size: app.window.minSize))] {
            app.setWindowFrame(frame)
            app.window.contentView?.layoutSubtreeIfNeeded(); app.updateViewportChrome()
            let m = canvasMargins(app, chrome)
            try expect(app.canvas.frame.width < chrome.scrollView.contentView.frame.width - 100 && app.canvas.frame.height < chrome.scrollView.contentView.frame.height - 100,
                       "Fixture canvas is smaller than the \(name) editor area")
            try expect(abs(m.left - m.right) <= 1 && abs(m.top - m.bottom) <= 1 && m.left > 20 && m.top > 20,
                       "At \(name) size the canvas has equal margins: \(m)")
            let border = app.canvasBorder.frame, canvasInBorderSpace = app.canvas.convert(app.canvas.bounds, to: app.canvasBorder.superview)
            try expect(abs(border.midX - canvasInBorderSpace.midX) <= 1 && abs(border.midY - canvasInBorderSpace.midY) <= 1, "The border follows the centred canvas at \(name) size")
        }
        // Larger than the view: constrained exactly like NSClipView, never centred, and the pan survives a resize.
        app.setWindowFrame(defaultFrame)
        app.canvas.newBlank(size: CGSize(width: 3000, height: 2000))
        app.setCanvasDisplayZoom(1, label: "Test")
        app.window.contentView?.layoutSubtreeIfNeeded()
        guard let clip = chrome.scrollView.contentView as? CenteringClipView else { throw Failure(description: "Modern scroll view lacks the centring clip view") }
        let panned = CGPoint(x: 120, y: 80)
        try expect(app.canvas.frame.width > clip.frame.width && app.canvas.frame.height > clip.frame.height, "The larger fixture exceeds the viewport on both axes")
        try expect(clip.constrainBoundsRect(NSRect(origin: panned, size: clip.bounds.size)).origin == panned,
                   "A larger document keeps a proposed pan origin untouched by the centring clip view")
        app.canvas.scroll(panned); chrome.scrollView.reflectScrolledClipView(clip)
        try expect(clip.bounds.origin == panned, "Panning through the canvas reaches the clip view unchanged: \(clip.bounds.origin)")
        for (name, frame) in [("minimum", CGRect(origin: defaultFrame.origin, size: app.window.minSize)), ("default", defaultFrame)] {
            app.setWindowFrame(frame)
            app.window.contentView?.layoutSubtreeIfNeeded(); app.updateViewportChrome()
            try expect(clip.bounds.origin == panned, "The panned origin survives a resize to \(name) size: \(clip.bounds.origin)")
        }
        // A wide, short document centres on y only; x keeps panning.
        app.canvas.newBlank(size: CGSize(width: 3000, height: 200))
        app.setCanvasDisplayZoom(1, label: "Test")
        app.window.contentView?.layoutSubtreeIfNeeded()
        let doc = app.canvas.frame
        try expect(doc.width > clip.bounds.width && doc.height < clip.bounds.height - 100, "The wide fixture is wider and shorter than the viewport")
        let centredY = doc.minY - (clip.bounds.height - doc.height) / 2
        let constrained = clip.constrainBoundsRect(NSRect(origin: CGPoint(x: 120, y: 0), size: clip.bounds.size)).origin
        try expect(constrained.x == 120 && abs(constrained.y - centredY) < 0.5, "A wide document pans on x and centres on y: \(constrained) vs y \(centredY)")
        app.canvas.scroll(CGPoint(x: 120, y: 0)); chrome.scrollView.reflectScrolledClipView(clip)
        try expect(clip.bounds.origin.x == 120 && abs(clip.bounds.origin.y - centredY) < 0.5, "Panning a wide document keeps x and the y centre: \(clip.bounds.origin)")
    }

    /// The document changing under a window that is not resized (new snap, open, crop, zoom) must centre too.
    private static func modernCanvasCentresWithoutWindowResize() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, content = try (app.window.contentView).unwrap("content view")
        let defaultFrame = app.window.frame
        for (name, frame) in [("minimum", CGRect(origin: defaultFrame.origin, size: app.window.minSize)), ("default", defaultFrame)] {
            app.setWindowFrame(frame)
            app.canvas.newBlank(size: CGSize(width: 3000, height: 2000))
            app.setCanvasDisplayZoom(1, label: "Test")
            content.layoutSubtreeIfNeeded(); app.updateViewportChrome()
            // From a canvas that fills the view to a small one: nothing resizes the window in between.
            try viewportFixture(app)
            content.layoutSubtreeIfNeeded(); app.updateViewportChrome()
            var m = canvasMargins(app, chrome)
            try expect(app.canvas.frame.width < chrome.scrollView.contentView.frame.width - 100 && app.canvas.frame.height < chrome.scrollView.contentView.frame.height - 100,
                       "The new document is smaller than the \(name) editor area")
            try expect(abs(m.left - m.right) <= 1 && abs(m.top - m.bottom) <= 1 && m.left > 20 && m.top > 20,
                       "A small document replaces a large one at \(name) size and is centred without a window resize: \(m)")
            // Zooming in and out re-centres the same way.
            for zoom: CGFloat in [2, 0.5, 1] {
                app.setCanvasDisplayZoom(zoom, label: "Test")
                content.layoutSubtreeIfNeeded(); app.updateViewportChrome()
                m = canvasMargins(app, chrome)
                try expect(abs(m.left - m.right) <= 1 && abs(m.top - m.bottom) <= 1 && m.left > 20 && m.top > 20,
                           "At \(name) size and zoom \(zoom) the canvas is centred: \(m)")
            }
            // A new snap: the window is already as small as a small shot allows, so adopting the picture resizes nothing.
            app.receiveCapture(.success(try image(size: CGSize(width: 300, height: 180))), discardAlreadyApproved: true)
            content.layoutSubtreeIfNeeded(); app.updateViewportChrome()
            m = canvasMargins(app, chrome)
            try expect(abs(m.left - m.right) <= 1 && abs(m.top - m.bottom) <= 1 && m.left > 20 && m.top > 20,
                       "A new small snap at \(name) size is centred without a window resize: \(m)")
            // A crop or Resize changes only the document frame.
            app.canvas.newBlank(size: CGSize(width: 150, height: 90))
            app.setCanvasDisplayZoom(1, label: "Test")
            content.layoutSubtreeIfNeeded()
            m = canvasMargins(app, chrome)
            try expect(abs(m.left - m.right) <= 1 && abs(m.top - m.bottom) <= 1 && m.left > 20 && m.top > 20,
                       "A smaller replacement document at \(name) size is centred: \(m)")
        }
        // Frame mode sizes the window to the canvas plus a margin: the canvas sits in the middle of the hole.
        try viewportFixture(app)
        app.setWindowFrame(CGRect(origin: defaultFrame.origin, size: app.window.minSize))
        content.layoutSubtreeIfNeeded()
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        defer { app.cancelFrame() }
        content.layoutSubtreeIfNeeded()
        let m = canvasMargins(app, chrome)
        try expect(abs(m.left - m.right) <= 1 && abs(m.top - m.bottom) <= 1, "In Frame mode the small canvas is centred in the hole: \(m)")
    }

    /// The Frame keyline is the canvas's own outline: all four edges for a canvas that fits, only the edges on screen for a larger one.
    private static func modernFrameKeylineFollowsCanvasEdges() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, content = try (app.window.contentView).unwrap("content view")
        func alphaAt(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let scale = CGFloat(rep.pixelsWide) / rep.size.width
            return rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? -1
        }
        func render(_ rect: NSRect) throws -> NSBitmapImageRep {
            let rep = try app.canvas.bitmapImageRepForCachingDisplay(in: rect).unwrap("bitmap")
            app.canvas.cacheDisplay(in: rect, to: rep)
            return rep
        }
        app.setWindowFrame(CGRect(origin: app.window.frame.origin, size: app.window.minSize))
        app.canvas.newBlank(size: CGSize(width: 300, height: 180)); app.setCanvasDisplayZoom(1, label: "Test")
        content.layoutSubtreeIfNeeded()
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        defer { app.cancelFrame() }
        content.layoutSubtreeIfNeeded()
        let small = try render(app.canvas.visibleRect.intersection(app.canvas.bounds)), size = small.size
        for (name, x, y) in [("left", 1.0, size.height / 2), ("right", size.width - 1, size.height / 2), ("top", size.width / 2, 1.0), ("bottom", size.width / 2, size.height - 1)] {
            try expect(alphaAt(small, x, y) > 0.9, "A canvas that fits has its keyline on the \(name) edge")
        }
        try expect(alphaAt(small, size.width / 2, size.height / 2) < 0.1, "The canvas interior stays clear")
        // A canvas larger than the hole: the clip view shows the left and top edges, and the others are off screen.
        app.cancelFrame()
        app.canvas.newBlank(size: CGSize(width: 3000, height: 2000)); app.setCanvasDisplayZoom(1, label: "Test")
        content.layoutSubtreeIfNeeded()
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        content.layoutSubtreeIfNeeded()
        let visible = app.canvas.visibleRect
        let big = try render(visible), shown = big.size
        try expect(visible.minX == 0 && visible.minY == 0 && visible.width < 3000 && visible.height < 2000, "The large canvas overflows the hole on the right and bottom: \(visible)")
        try expect(alphaAt(big, 1, shown.height / 2) > 0.9 && alphaAt(big, shown.width / 2, 1) > 0.9, "The visible left and top edges carry the keyline")
        try expect(alphaAt(big, shown.width - 1, shown.height / 2) < 0.1 && alphaAt(big, shown.width / 2, shown.height - 1) < 0.1,
                   "The right and bottom keyline are off screen, not clipped by the margin")
        _ = chrome
    }

    private static func modernCanvasCentredHitTest() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        app.canvas.newBlank(size: CGSize(width: 150, height: 90))
        app.setCanvasDisplayZoom(1, label: "Test")
        app.window.contentView?.layoutSubtreeIfNeeded()
        var element = SketchElement(kind: .rectangle)
        element.rect = CGRect(x: 65, y: 35, width: 20, height: 20)
        element.color = SketchColor(.red)
        app.canvas.document.elements = [element]; app.canvas.selection = []
        app.canvas.tool = .select
        let area = chrome.scrollView.convert(chrome.scrollView.contentView.frame, to: nil)
        let point = CGPoint(x: area.midX, y: area.midY)
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            guard let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: app.window.windowNumber,
                                             context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { throw Failure(description: "mouse event") }
            return e
        }
        app.canvas.mouseDown(with: try event(.leftMouseDown)); app.canvas.mouseUp(with: try event(.leftMouseUp))
        try expect(app.canvas.selection == [element.id], "A click at the visual centre selects the element at the document centre: \(app.canvas.selection)")
    }

    private static func modernFixture() throws -> (Fixture, ModernEditorChrome) {
        let fixture = try Fixture()
        guard let chrome = fixture.app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        // The host's Reduce Transparency or Increase Contrast must never decide a result.
        chrome.accessibility = .none
        return (fixture, chrome)
    }

    private static func collect<T: NSView>(_ type: T.Type, in root: NSView) -> [T] {
        var found: [T] = []
        func walk(_ view: NSView) {
            if let match = view as? T { found.append(match) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    private static func descendant(_ root: NSView, identifier: String) -> NSView? {
        if root.identifier?.rawValue == identifier { return root }
        var children = root.subviews
        if let tabs = root as? NSTabView { children += tabs.tabViewItems.compactMap(\.view) }
        for child in children { if let found = descendant(child, identifier: identifier) { return found } }
        return nil
    }

    private static func surface(_ chrome: ModernEditorChrome, _ control: NSView?) throws -> GlassSurfaceView {
        guard let control, let surface = chrome.surface(for: control) else { throw Failure(description: "A control has no glass surface") }
        return surface
    }

    private static func sameColor(_ a: NSColor?, _ b: NSColor) -> Bool {
        guard let a = a?.usingColorSpace(.deviceRGB), let b = b.usingColorSpace(.deviceRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01 && abs(a.alphaComponent - b.alphaComponent) < 0.01
    }

    private static let toolOrder = ["select", "brush", "line", "ellipse", "rectangle", "fill", "eraser", "text", "arrow", "crop"]

    // MARK: Control facts

    /// The 10 command buttons, each found by the action it sends.
    private static let commandActions: [(name: String, action: Selector)] = [
        ("hide", #selector(AppDelegate.vanish)), ("photos", #selector(AppDelegate.showPhotos)), ("save", #selector(AppDelegate.saveHistory)),
        ("history", #selector(AppDelegate.showHistory)), ("snap", #selector(AppDelegate.snapButtonPressed)),
        ("cancel", #selector(AppDelegate.cancelFrame)), ("font", #selector(AppDelegate.chooseFont)), ("undo", #selector(AppDelegate.undo)),
        ("wipe", #selector(AppDelegate.wipe)), ("resize", #selector(AppDelegate.resize))
    ]

    private static func controlFacts(_ app: AppDelegate) -> [String: String] {
        guard let content = app.window.contentView else { return [:] }
        var facts: [String: String] = [:]
        for tool in SketchTool.allCases {
            let button = app.toolButtons[tool]
            facts["tool.\(tool.rawValue).id"] = button?.identifier?.rawValue ?? "<nil>"
            facts["tool.\(tool.rawValue).label"] = button?.accessibilityLabel() ?? "<nil>"
            facts["tool.\(tool.rawValue).tip"] = button.flatMap { AppToolTip.text(for: $0) } ?? "<nil>"
        }
        facts["snap.tip"] = AppToolTip.text(for: app.snapButton) ?? "<nil>"
        facts["palette.label"] = app.paletteButton.accessibilityLabel() ?? "<nil>"
        facts["palette.tip"] = AppToolTip.text(for: app.paletteButton) ?? "<nil>"
        facts["zoom.label"] = app.zoomControl.accessibilityLabel() ?? "<nil>"
        facts["format.label"] = app.dragFormatToggle.accessibilityLabel() ?? "<nil>"
        facts["drag.label"] = app.dragExportView?.accessibilityLabel() ?? "<nil>"
        facts["drag.tip"] = app.dragExportView.flatMap { AppToolTip.text(for: $0) } ?? "<nil>"
        facts["original.title"] = app.dragOriginalControl.title
        facts["original.label"] = app.dragOriginalControl.accessibilityLabel() ?? "<nil>"
        facts["size.label"] = app.widthControl.accessibilityLabel() ?? "<nil>"
        facts["size.tip"] = AppToolTip.text(for: app.widthControl) ?? "<nil>"
        facts["name.placeholder"] = app.nameField.placeholderString ?? "<nil>"
        facts["status.font"] = String(Double(app.status.font?.pointSize ?? 0))
        let toolbox = collect(NSPopUpButton.self, in: content).first { $0.accessibilityLabel() == "Toolbox" }
        facts["toolbox.label"] = toolbox?.accessibilityLabel() ?? "<nil>"
        facts["toolbox.tip"] = toolbox.flatMap { AppToolTip.text(for: $0) } ?? "<nil>"
        facts["toolbox.items"] = toolbox?.itemTitles.joined(separator: "|") ?? "<nil>"
        let tools = Set(app.toolButtons.values.map(ObjectIdentifier.init))
        // The upload status commands (Cancel upload, Open link, Copy link, Retry, Details…) are covered by the upload cases.
        let uploadCommands = Set(((app.modernChrome as? ModernEditorChrome)?.uploadControls.commandButtons ?? []).map(ObjectIdentifier.init))
        let plain = collect(NSButton.self, in: content).filter { !($0 is NSPopUpButton) && !tools.contains(ObjectIdentifier($0)) && !uploadCommands.contains(ObjectIdentifier($0)) }
        // Modern's upload command is icon-only with its own label; webpostModernIconOnly covers it.
        let upload = #selector(AppDelegate.share(_:))
        facts["buttons"] = plain.filter { $0.action != upload && $0.action != #selector(AppDelegate.toggleActualSize) }.map(\.title).sorted().joined(separator: "|")
        // What VoiceOver reads for each command. Buttons read their titles; a symbol fallback must not read its own name instead.
        for (name, action) in commandActions { facts["axLabel.\(name)"] = plain.first { $0.action == action }?.accessibilityLabel() ?? "<nil>" }
        facts["resize.title"] = app.resizeButton?.title ?? "<nil>"
        return facts
    }

    // MARK: cases

    private static func modernWindowStructure() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let content = app.window.contentView as? FrameChromeView else { throw Failure(description: "The content view must stay the Frame-aware FrameChromeView") }
        content.layoutSubtreeIfNeeded()
        try expect(chrome.superview === content && !chrome.translatesAutoresizingMaskIntoConstraints, "The chrome is a constrained child of the content view")
        try expect(chrome.frame == content.bounds, "The chrome is pinned to all four content edges at origin 0: \(chrome.frame) vs \(content.bounds)")
        try expect(content.appearance == nil, "The window never forces aqua")
        try expect(content.canvasScrollView === chrome.scrollView && app.canvas.enclosingScrollView === chrome.scrollView && chrome.scrollView.documentView === app.canvas,
                   "The Frame hole and the canvas both use the chrome's scroll view")
        try expect(app.canvasBorder.superview === chrome && chrome.subviews.last === app.canvasBorder, "The canvas border stays the topmost sibling in chrome coordinates")
        try expect(app.window.minSize == NSSize(width: ModernEditorChrome.minimumWindowWidth, height: 640), "The Modern minimum width is raised just enough for the one-row top bar; the height is unchanged")

        // Controls the app keeps by reference are the chrome's own.
        try expect(app.snapButton === chrome.snapButton && app.cancelFrameButton === chrome.cancelFrameButton
                   && app.resizeButton === chrome.resizeButton, "AppDelegate controls Snap, Cancel and Resize through the chrome's buttons")
        let tools = toolOrder.compactMap { SketchTool(rawValue: $0).flatMap { app.toolButtons[$0] } }
        try expect(tools.count == 10 && app.toolButtons.count == 10, "All ten tools, Crop included, are registered")
        try expect(tools.allSatisfy { $0 is CommandButton }, "Tools are glass buttons")
        try expect(tools.map { $0.identifier?.rawValue ?? "" } == toolOrder, "Tool identifiers keep the archive order and raw values")
        let across = tools.sorted { $0.convert($0.bounds, to: content).minX < $1.convert($1.bounds, to: content).minX }
        try expect(across.map { $0.identifier?.rawValue ?? "" } == toolOrder, "The top bar runs the tools left to right in archive order with Crop last")
        try expect(zip(tools, toolOrder).allSatisfy { button, id in chrome.toolButtons[id] === button }, "Registered tool buttons are the chrome's")
        try expect(tools.allSatisfy { $0.target === app && $0.action == #selector(AppDelegate.chooseTool(_:)) }, "Every tool sends chooseTool to the AppDelegate")

        // Shared controls take the Modern treatment but keep their behavior.
        try expect(app.dragExportView?.drawsBackground == false, "Drag Me draws no plate of its own")
        try expect((app.dragExportView?.superview as? ChromeFillCell)?.fixedSize == NSSize(width: 48, height: 36) && (try surface(chrome, app.dragExportView)).identifier?.rawValue == "GlassFooterRow",
                   "Drag Me is a compact 48x36 cell on the footer plate like the other icon buttons")
        try expect((app.paletteButton.superview as? ChromeFillCell)?.fixedSize == NSSize(width: 48, height: 36)
                   && chrome.surface(for: app.dragFormatToggle)?.identifier?.rawValue == "GlassFooterRow" && app.dragFormatToggle.superview is NSStackView, "Color is a 48x36 cell; the format toggle sits on the footer plate with no plate of its own")
        try expect(chrome.surface(for: app.zoomControl)?.identifier?.rawValue == "GlassViewGroup" && chrome.surface(for: app.status) == nil && chrome.surface(for: app.canvas) == nil, "Zoom sits on the view plate; status and the canvas stay outside glass")
        try expect((app.status.font?.pointSize ?? 0) >= 18 && (app.zoomControl.font?.pointSize ?? 0) >= 18, "Text stays at its readable sizes")
        try expect(app.widthControl.target === app && app.widthControl.action == #selector(AppDelegate.changeWidth(_:)) && app.widthControl.onBegin != nil && app.widthControl.onEnd != nil
                   && (try surface(chrome, app.widthControl)).identifier?.rawValue == "GlassAnnotationGroup" && app.widthControl.frame.size == BezelSizeSlider.pillSize,
                   "The size pill keeps its undo-grouping callbacks and is a 48x36 control on the annotation plate")
        try expect(app.zoomControl.target === app && app.zoomControl.action == #selector(AppDelegate.changeZoom(_:)) && app.zoomControl.titleOfSelectedItem == "100%", "Zoom keeps its action and 100% default")
        try expect(app.dragFormatToggle.target === app && app.dragFormatToggle.segmentCount == 2 && app.dragOriginalControl.target === app, "Drag format and original-size controls keep their actions")
        try expect(app.paletteButton.target === app && app.paletteButton.action == #selector(AppDelegate.showDrawingColors(_:)) && app.paletteButton.onHover != nil, "Color keeps its click and hover routes")
        try expect(app.colorWell.target === app && app.colorWell.action == #selector(AppDelegate.changeColor(_:)), "The hidden color well keeps its route")
        let drag = try (app.dragExportView).unwrap("Drag Me view")
        try expect(drag.prepare != nil && drag.onBegin != nil && drag.onLeaveControl != nil && drag.onEnd != nil && drag.onDeliveryFailure != nil, "Drag Me keeps every export callback")
        try expect(app.canvasBorder.onBegin != nil && app.canvasBorder.onDrag != nil && app.canvasBorder.onEnd != nil && app.navigator.onNavigate != nil, "Canvas border and navigator callbacks are wired")
        try expect(app.canvas.tool == .arrow && app.helpBevel != nil && app.canvas.onHintHover != nil, "Launch ends on the Arrow tool with the hint shell attached")
        try expect(app.sizeLabel.stringValue.hasPrefix("Size · ") && (app.paletteButton.image?.size.width ?? 0) > 0, "Drawing controls were synchronized after the chrome was built")
        app.canvas.strokeWidth = 9.38; app.syncDrawingControls()
        try expect(app.sizeLabel.stringValue == "Size · 9" && abs(app.widthControl.doubleValue - 9.38) < 0.001, "Size label shows a whole number while the stored value keeps its fraction")
    }

    private static func modernControlStrings() throws {
        let (fixture, _) = try modernFixture()
        let app = fixture.app
        let modern = controlFacts(app)
        let expectedFacts: [String: String] = [
            "axLabel.cancel": "Cancel",
            "axLabel.font": "Font",
            "axLabel.hide": "Hide",
            "axLabel.history": "History",
            "axLabel.photos": "Photos",
            "axLabel.resize": "Resize…",
            "axLabel.save": "Save",
            "axLabel.snap": "Snap",
            "axLabel.undo": "Undo",
            "axLabel.wipe": "Clear image",
            "buttons": "Cancel|Clear image|Color…|Font|Hide|History|Original size|Photos|Resize…|Save|Snap|Undo",
            "drag.label": "Drag image to another app",
            "drag.tip": "Drag the drawing into Finder or another app",
            "format.label": "Image format",
            "name.placeholder": "Image name",
            "original.label": "Export at original size",
            "original.title": "Original size",
            "palette.label": "Drawing colors",
            "palette.tip": "Color: hover for original preset colors; hold Shift to change the canvas background",
            "resize.title": "Resize…",
            "size.label": "Drawing size",
            "size.tip": "Size 7",
            "snap.tip": "Snap: drag an area or click a window; right-click or Control-click for Fullscreen",
            "status.font": "18.0",
            "tool.arrow.id": "arrow",
            "tool.arrow.label": "Arrow tool",
            "tool.arrow.tip": "Arrow tool (selected); Option reverses direction, Shift constrains the angle",
            "tool.brush.id": "brush",
            "tool.brush.label": "Brush tool",
            "tool.brush.tip": "Brush tool",
            "tool.crop.id": "crop",
            "tool.crop.label": "Crop tool",
            "tool.crop.tip": "Crop tool",
            "tool.ellipse.id": "ellipse",
            "tool.ellipse.label": "Ellipse tool",
            "tool.ellipse.tip": "Ellipse tool",
            "tool.eraser.id": "eraser",
            "tool.eraser.label": "Eraser tool",
            "tool.eraser.tip": "Eraser tool",
            "tool.fill.id": "fill",
            "tool.fill.label": "Fill tool",
            "tool.fill.tip": "Fill tool",
            "tool.line.id": "line",
            "tool.line.label": "Line tool",
            "tool.line.tip": "Line tool",
            "tool.rectangle.id": "rectangle",
            "tool.rectangle.label": "Rectangle tool",
            "tool.rectangle.tip": "Rectangle tool",
            "tool.select.id": "select",
            "tool.select.label": "Select tool",
            "tool.select.tip": "Select tool",
            "tool.text.id": "text",
            "tool.text.label": "Text tool",
            "tool.text.tip": "Text tool",
            "toolbox.items": "Save to History|Export…||Copy|Paste|Duplicate|Delete|Select All||Crosshair Snapshot|Fullscreen Snapshot|Frame Snapshot|Re-snap (Keep Pen)||Rotate Clockwise|Flip Horizontal|Crop Snap at Current Edges|Remove Snap Picture||Filled Shapes|Shadow|Text Style…",
            "toolbox.label": "Toolbox",
            "toolbox.tip": "Drawing, edit and capture commands; everything else is in the menu bar",
            "zoom.label": "Canvas zoom"
        ]
        let differing = expectedFacts.keys.sorted().filter { expectedFacts[$0] != modern[$0] }
            .map { "\($0): expected '\(expectedFacts[$0] ?? "")' but found '\(modern[$0] ?? "<missing>")'" }
        try expect(differing.isEmpty && modern.count == expectedFacts.count, "Control strings differ from the recovered ones (\(modern.count) vs \(expectedFacts.count) facts): " + differing.joined(separator: "; "))
        try expect(modern["tool.arrow.label"] == "Arrow tool" && modern["tool.crop.tip"] == "Crop tool"
                   && modern["toolbox.label"] == "Toolbox" && modern["drag.label"] == "Drag image to another app" && modern["format.label"] == "Image format", "The strings are the recovered ones, not merely equal to each other")
        // At launch Wipe reads its blank stage (a dimmed Clear image); every other command reads its title (the icon-only upload button is checked on its own).
        let spoken = ["hide": "Hide", "photos": "Photos", "save": "Save", "history": "History", "snap": "Snap", "cancel": "Cancel", "font": "Font",
                      "undo": "Undo", "wipe": "Clear image", "resize": "Resize…"]
        let misread = spoken.keys.sorted().filter { modern["axLabel.\($0)"] != spoken[$0] }
            .map { "\($0): '\(modern["axLabel.\($0)"] ?? "")' instead of '\(spoken[$0] ?? "")'" }
        try expect(misread.isEmpty && spoken.count == commandActions.count, "VoiceOver reads the wrong command labels: " + misread.joined(separator: "; "))
        let hinted: [(String, NSView?)] = SketchTool.allCases.map { ("tool " + $0.rawValue, app.toolButtons[$0]) }
            + [("Wipe", collect(NSButton.self, in: app.window.contentView!).first { $0.action == #selector(AppDelegate.wipe) }), ("size slider", app.widthControl), ("Drag Me", app.dragExportView)]
        for (name, view) in hinted {
            try expect(view?.subviews.contains { $0 is HintTrackingView } == true, "\(name) registers contextual hint tracking")
        }
    }

    private static func modernIconOnlyCommands() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let content = try (app.window.contentView).unwrap("content view")
        let wipe = try collect(NSButton.self, in: content).first { $0.action == #selector(AppDelegate.wipe) }.unwrap("Wipe")
        // action -> (VoiceOver label, tooltip); shortcuts come from the real menu key equivalents (Minimize is vanish, Undo is Edit > Undo).
        let expected: [(Selector, String, String)] = [
            (#selector(AppDelegate.vanish), "Hide", "Hide (⌘M)"), (#selector(AppDelegate.showPhotos), "Photos", "Photos"),
            (#selector(AppDelegate.saveHistory), "Save", "Save to History"), (#selector(AppDelegate.showHistory), "History", "History"),
            (#selector(AppDelegate.snapButtonPressed), "Snap", ModernEditorChrome.snapToolTip), (#selector(AppDelegate.chooseFont), "Font", "Font"),
            (#selector(AppDelegate.undo), "Undo", "Undo (⌘Z)"), (#selector(AppDelegate.wipe), "Clear image", "Nothing to clear"),
            (#selector(AppDelegate.share(_:)), "Upload image", AppDelegate.webpostHelp)]
        func verify(_ label: String) throws {
            let buttons = collect(NSButton.self, in: content)
            // R1-006: Resize… is the one command that wears its name (its glyph read as expand or full screen), with a tooltip that explains it.
            let resize = try buttons.first { $0.action == #selector(AppDelegate.resize) }.unwrap("Resize… button")
            try expect((resize as? CommandButton)?.visibleTitle == "Resize…" && resize.accessibilityLabel() == "Resize…" && AppToolTip.text(for: resize) == "Resize or crop the picture", "\(label): Resize… shows its name and explains itself")
            for (action, name, tip) in expected {
                let button = try buttons.first { $0.action == action }.unwrap("\(name) button")
                try expect(button.imagePosition == .imageOnly && ((button as? CommandButton)?.visibleTitle ?? button.title).isEmpty, "\(label): \(name) shows no title text")
                try expect(AppToolTip.text(for: button) == tip, "\(label): \(name) tooltip is '\(tip)', not '\(AppToolTip.text(for: button) ?? "nil")'")
                try expect(button.accessibilityLabel() == name, "\(label): \(name) VoiceOver label, not '\(button.accessibilityLabel() ?? "nil")'")
            }
            try expect(AppToolTip.text(for: wipe) == "Nothing to clear" && wipe.accessibilityHelp() == "Nothing to clear", "\(label): a blank canvas's Wipe says why it is dimmed, as tooltip and help")
            try expect(app.paletteButton.imagePosition == .imageOnly && app.paletteButton.accessibilityLabel() == "Drawing colors" && (AppToolTip.text(for: app.paletteButton) ?? "").hasPrefix("Color"),
                       "\(label): Color is a swatch with a tooltip and its label")
            try expect(app.sizeLabel.superview == nil, "\(label): the Size text is not shown")
            try expect(chrome.header.subviews.flatMap { collect(NSTextField.self, in: $0) }.isEmpty, "\(label): the top bar has no title text")
        }
        try verify("default")
        // The overlay preference governs the original overlay hints, never the native tooltips.
        var settings = app.generalPreferences.state
        for show in [true, false] {
            settings.showToolTips = show; app.applyGeneralPreferences(settings)
            try verify("overlay preference \(show)")
        }
        app.canvas.strokeWidth = 9.38; app.syncDrawingControls()
        try expect(AppToolTip.text(for: app.widthControl) == "Size 9" && (app.widthControl.accessibilityValue() as? NSNumber)?.doubleValue == 9,
                   "The slider tooltip and VoiceOver both read the whole-number size (OSN-062: it was the fraction 9.38)")
        let before = AppToolTip.text(for: app.widthControl)
        app.canvas.strokeWidth = 3; app.syncDrawingControls()
        try expect(AppToolTip.text(for: app.widthControl) == "Size " + String(format: "%.0f", app.widthControl.doubleValue.rounded()) && AppToolTip.text(for: app.widthControl) != before, "The Size tooltip follows the slider (\(AppToolTip.text(for: app.widthControl) ?? "nil"))")
        let drag = try (app.dragExportView).unwrap("drag well")
        try expect(drag.showsHandIconOnly && AppToolTip.text(for: drag) == "Drag the drawing into Finder or another app" && drag.accessibilityLabel() == "Drag image to another app" && drag.accessibilityRole() == .button, "The drag well is an open-hand icon with a tooltip and a button role named for what it does")
        try expect(NSImage(systemSymbolName: DragExportView.handSymbolName, accessibilityDescription: nil) != nil, "The hand symbol exists")
        try expect(drag.prepare != nil && drag.onBegin != nil && drag.onEnd != nil, "The icon-only well is still the drag source")
        let size = NSSize(width: 48, height: 36)
        drag.frame = NSRect(origin: .zero, size: size)
        func inkedPixels() throws -> Int {
            guard let rep = drag.bitmapImageRepForCachingDisplay(in: drag.bounds) else { throw Failure(description: "No bitmap for the drag well") }
            drag.cacheDisplay(in: drag.bounds, to: rep)
            var count = 0
            for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { count += 1 } }
            return count
        }
        let inked = try inkedPixels()
        try expect(inked > 20, "The well draws the hand glyph (\(inked) inked pixels)")
        app.dragExportView?.overview = try image(size: CGSize(width: 60, height: 40))
        let withThumb = try inkedPixels()
        try expect(withThumb == inked, "A thumbnail never changes the icon-only well (\(withThumb) vs \(inked))")
    }

    private static func modernShortcutHintsFollowMenu() throws {
        let (fixture, chrome) = try modernFixture()
        _ = fixture
        func item(_ action: Selector) throws -> NSMenuItem {
            var found: NSMenuItem?
            func walk(_ menu: NSMenu) { for i in menu.items { if i.action == action { found = i }; if let sub = i.submenu { walk(sub) } } }
            walk(try NSApp.mainMenu.unwrap("main menu"))
            return try found.unwrap("menu item for \(action)")
        }
        let minimize = try item(#selector(AppDelegate.vanish)), undo = try item(#selector(AppDelegate.undo))
        let (oldKey, oldMask) = (minimize.keyEquivalent, minimize.keyEquivalentModifierMask)
        defer { minimize.keyEquivalent = oldKey; minimize.keyEquivalentModifierMask = oldMask }
        try expect(AppToolTip.text(for: chrome.hideButton) == "Hide (⌘" + minimize.keyEquivalent.uppercased() + ")", "Hide's tooltip suffix is Minimize's key equivalent: \(AppToolTip.text(for: chrome.hideButton) ?? "nil")")
        try expect(AppToolTip.text(for: chrome.undoButton) == "Undo (⌘" + undo.keyEquivalent.uppercased() + ")", "Undo's tooltip suffix is Undo's key equivalent: \(AppToolTip.text(for: chrome.undoButton) ?? "nil")")
        minimize.keyEquivalent = "h"; minimize.keyEquivalentModifierMask = [.command, .option, .shift]
        chrome.refreshShortcutHints()
        try expect(AppToolTip.text(for: chrome.hideButton) == "Hide (⌥⇧⌘H)", "Changing Minimize's shortcut changes Hide's tooltip: \(AppToolTip.text(for: chrome.hideButton) ?? "nil")")
    }

    private static func modernRenameAvailability() throws {
        let (fixture, _) = try modernFixture()
        let app = fixture.app
        let rename = try NSApp.mainMenu.unwrap("main menu").items.compactMap(\.submenu).flatMap(\.items).first { $0.action == #selector(AppDelegate.renameDocument) }.unwrap("Rename item")
        try expect(app.validateMenuItem(rename), "Rename is available at rest")
        app.frameCaptureInProgress = true
        try expect(!app.validateMenuItem(rename), "Rename is disabled during a Frame capture")
        let name = app.nameField.stringValue
        app.renameDocument()
        try expect(app.nameField.stringValue == name, "renameDocument does nothing during a Frame capture")
        app.frameCaptureInProgress = false
        app.terminationStarted = true
        try expect(!app.validateMenuItem(rename), "Rename is disabled while terminating")
        app.terminationStarted = false
        try expect(app.validateMenuItem(rename), "Rename returns after the state clears")
    }

    private static func modernFrameStatusFits() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let shortHint = "Frame: position, then Snap", fullHint = "Frame: position the window, then Snap"
        let minimum = app.window.minSize
        for (width, height) in [(minimum.width, minimum.height), (1024, app.window.frame.height)] {
            app.setWindowFrame(CGRect(origin: app.window.frame.origin, size: CGSize(width: width, height: height)))
            app.enterFrame(keepingAnnotations: false, manualFlags: [])
            defer { app.cancelFrame() }
            app.window.contentView?.layoutSubtreeIfNeeded()
            let measured = app.status.attributedStringValue.size().width
            try expect(measured <= app.status.frame.width + 0.5,
                       "The Frame hint '\(app.status.stringValue)' fits whole at \(Int(width)) wide (\(measured) vs \(app.status.frame.width))")
            try expect(app.status.stringValue == shortHint, "The Frame status shows the short hint: \(app.status.stringValue)")
            try expect(AppToolTip.text(for: app.status) == fullHint, "The full sentence is the Frame status tooltip: \(AppToolTip.text(for: app.status) ?? "nil")")
            try expect(app.status.accessibilityValue() == fullHint && app.status.accessibilityHelp() == fullHint,
                       "The full sentence is the Frame status accessibility value and help: \(String(describing: app.status.accessibilityValue())) / \(String(describing: app.status.accessibilityHelp())) / \(fullHint)")
        }
        try expect(app.status.accessibilityValue() == app.status.stringValue && app.status.accessibilityHelp() == nil,
                   "Leaving Frame hands the status its own accessibility value back")
        _ = chrome
    }

    /// The Original size checkbox is meaningless while framing: a large shot hides it so the hint has the room.
    private static func modernFrameHidesOriginalSize() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, content = try (app.window.contentView).unwrap("content view")
        try largeShot(app)
        app.setWindowFrame(CGRect(origin: app.window.frame.origin, size: app.window.minSize))
        app.updateViewportChrome(); content.layoutSubtreeIfNeeded()
        try expect(app.isLargeShot && !app.dragOriginalControl.isHidden, "A large shot shows the Original size checkbox before Frame")
        for keeping in [false, true] {
            app.enterFrame(keepingAnnotations: keeping, manualFlags: [])
            content.layoutSubtreeIfNeeded()
            try expect(app.isLargeShot && app.dragOriginalControl.isHidden, "Frame mode (keeping: \(keeping)) hides the Original size checkbox for a large shot")
            let hint = app.status.stringValue
            try expect(hint.hasPrefix("Frame: ") && !hint.contains("…"), "The Frame hint is the short sentence: \(hint)")
            let measured = app.status.cell?.cellSize.width ?? .infinity
            try expect(measured <= app.status.frame.width + 0.5, "At 980 the Frame hint '\(hint)' fits whole beside no checkbox (\(measured) vs \(app.status.frame.width))")
            app.cancelFrame()
            content.layoutSubtreeIfNeeded()
            try expect(!app.dragOriginalControl.isHidden, "Leaving Frame brings the Original size checkbox back for a large shot")
        }
        // A small shot never had the checkbox, in Frame or out of it.
        app.canvas.newBlank(size: CGSize(width: 300, height: 180))
        app.canvas.setBackground(try image(size: CGSize(width: 300, height: 180)))   // shown at its own size: nothing to choose
        app.updateViewportChrome()
        try expect(app.dragOriginalControl.isHidden, "A small shot has no checkbox")
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        try expect(app.dragOriginalControl.isHidden, "A small shot has no checkbox in Frame")
        app.cancelFrame()
        try expect(app.dragOriginalControl.isHidden, "A small shot has no checkbox after Frame")
        _ = chrome
    }

    /// At every width the status shows the longest variant that fits whole, and the saved state is never the part cut.
    private static func modernStatusKeepsStateWhenNarrow() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, content = try (app.window.contentView).unwrap("content view")
        try largeShot(app)
        // The long status (size, format, bytes) is what the footer says where the title bar is not on screen, in full screen; it is swept
        // here at every window width. A windowed footer is checked at the end.
        app.footerShowsPictureFactsOverride = true
        app.dragPreviewTimer?.invalidate(); app.dragPreviewTimer = nil
        let origin = app.window.frame.origin
        var sawShortened = false, sawWhole = false
        for (tool, dirty) in [(SketchTool.arrow, true), (.brush, false)] {
            app.setTool(tool); app.dirty = dirty
            app.dragPreviewTimer?.invalidate(); app.dragPreviewTimer = nil
            app.updateDragPreview()
            let state = dirty ? "Unsaved changes" : "Saved"
            let full = AppToolTip.text(for: app.status) ?? ""
            let parts = full.components(separatedBy: " · ")
            try expect(parts.count == 5 && parts[1] == state && parts[2].contains("×") && parts[3] == "PNG" && parts[4].hasSuffix("B"), "The full status has tool, state, size, format and bytes: \(full)")
            let expected = [full, parts[0...2].joined(separator: " · "), parts[1...2].joined(separator: " · "), parts[0...1].joined(separator: " · "), state]
            for width in stride(from: app.window.minSize.width, through: 1440, by: 20) {
                app.setWindowFrame(CGRect(origin: origin, size: CGSize(width: width, height: app.window.frame.height)))
                app.updateViewportChrome(); content.layoutSubtreeIfNeeded()
                let label = "\(tool.rawValue) \(state) at \(Int(width)) wide with\(app.dragOriginalControl.isHidden ? "out" : "") the checkbox"
                let shown = app.status.stringValue, room = app.status.frame.width
                func need(_ text: String) -> CGFloat { let probe = app.status.cell!.copy() as! NSCell; probe.stringValue = text; return probe.cellSize.width }
                try expect(expected.contains(shown), "\(label): the status is one of the five variants, got '\(shown)'")
                try expect(shown.contains(state), "\(label): the state '\(state)' is whole in '\(shown)'")
                try expect(need(shown) <= room + 0.5 || shown == state, "\(label): '\(shown)' fits whole in \(room) pt")
                let index = expected.firstIndex(of: shown) ?? 0
                try expect(expected[..<index].allSatisfy { need($0) > room + 0.5 }, "\(label): every longer variant really is too wide for \(room) pt")
                try expect(AppToolTip.text(for: app.status) == full && (app.status.accessibilityValue() as? String) == full, "\(label): the tooltip and spoken value are the full text: tip=\(AppToolTip.text(for: app.status) ?? "nil") ax=\(String(describing: app.status.accessibilityValue())) spoken=\(app.status.spokenValue ?? "nil") shown=\(shown) full=\(full)")
                try expect(!shown.contains("…"), "\(label): no ellipsis was typed into the text")
                if index > 0 { sawShortened = true } else { sawWhole = true }
            }
        }
        try expect(sawShortened && sawWhole, "The sweep covered both a shortened and a whole status")
        // The reported case: 980 wide with the checkbox, an unsaved Arrow.
        app.setTool(.arrow); app.dirty = true; app.updateDragPreview()
        app.setWindowFrame(CGRect(origin: origin, size: CGSize(width: app.window.minSize.width, height: app.window.frame.height)))
        app.updateViewportChrome(); content.layoutSubtreeIfNeeded()
        try expect(!app.dragOriginalControl.isHidden && app.status.stringValue.contains("Unsaved changes"), "At 980 with the checkbox the unsaved state is whole: \(app.status.stringValue)")
        // A window that grows gives the longer text back; the label's width does not depend on what it shows.
        app.setWindowFrame(CGRect(origin: origin, size: CGSize(width: 1440, height: app.window.frame.height)))
        content.layoutSubtreeIfNeeded()
        try expect(app.status.stringValue == AppToolTip.text(for: app.status), "A wide window shows the whole status again: \(app.status.stringValue)")

        // R1-013: with the title bar up (windowed) the footer does not repeat "W × H · PNG · bytes": the tool and the state only, whole at every width.
        app.footerShowsPictureFactsOverride = nil
        app.setTool(.arrow); app.dirty = true; app.updateDragPreview()
        try expect(app.status.variants == ["Arrow · Unsaved changes", "Unsaved changes", "Unsaved"] && !(AppToolTip.text(for: app.status) ?? "").contains("×") && (app.window.subtitle.contains("×")),
                   "Windowed, the footer is the tool and state while the title bar carries the size (\(app.status.variants), title \(app.window.subtitle))")
        for width in [app.window.minSize.width, 1024, 1440] {
            app.setWindowFrame(CGRect(origin: origin, size: CGSize(width: width, height: app.window.frame.height)))
            app.updateViewportChrome(); content.layoutSubtreeIfNeeded()
            // Beside the Original size checkbox at 980 the slot holds only the state, which is never the part given up; wider, the tool comes back.
            let shown = app.status.stringValue
            try expect(shown.contains("Unsaved") && !shown.contains("…") && !shown.contains("×") && (width < 1100 || shown == "Arrow · Unsaved changes"), "\(Int(width)): the windowed footer keeps the state whole and drops the tool only where it must (\(shown))")
        }
        // An upload message is one text: it keeps its priority and is cut only at its tail. A plain write is one fixed text too.
        let field = StatusTextField(labelWithString: "")
        field.font = .systemFont(ofSize: 18); field.lineBreakMode = .byTruncatingTail
        field.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        let upload = "Uploading 2 of 3 to the bucket, please wait for the last part"
        field.setVariants([upload])
        try expect(field.stringValue == upload && field.lineBreakMode == .byTruncatingTail, "A one-text status keeps all its text and truncates at the tail")
        field.setVariants(["Arrow · Saved · 100 × 80 · 1 KB", "Saved"]); field.frame.size.width = 20
        try expect(field.stringValue == "Saved", "When nothing fits the last variant stays and truncates at its tail: \(field.stringValue)")
        field.stringValue = "Frame: hint"; field.frame.size.width = 400
        try expect(field.stringValue == "Frame: hint" && field.variants.isEmpty, "A direct write replaces the variants")
        _ = chrome
    }

    private static func modernZoomActualSize() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        try viewportFixture(app)
        func live(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.action == #selector(AppDelegate.toggleActualSize) { return item }
                if let submenu = item.submenu, let found = live(submenu) { return found }
            }
            return nil
        }
        guard let main = NSApp.mainMenu.flatMap(live) else { throw Failure(description: "The main menu has no Actual Size command") }
        guard let menu = app.zoomControl.menu, let index = (0..<menu.numberOfItems).first(where: { menu.item(at: $0)?.tag == ZoomPopUpButton.actualSizeTag }),
              let item = menu.item(at: index) else { throw Failure(description: "The zoom menu has no Actual Size item") }
        try expect(item.title == main.title && item.action == main.action && item.target === main.target && item.target === app,
                   "The zoom item is the main-menu Actual Size command (\(item.title), \(String(describing: item.action)))")
        try expect(item.keyEquivalent == main.keyEquivalent && item.keyEquivalentModifierMask == main.keyEquivalentModifierMask,
                   "The zoom item carries exactly the key equivalent the main menu has ('\(main.keyEquivalent)')")
        try expect(app.validateMenuItem(item) == app.canToggleActualSize && app.canToggleActualSize, "The zoom item is enabled when Actual Size is available")
        app.terminationStarted = true
        try expect(!app.validateMenuItem(item), "The zoom item follows the command's disabled state")
        app.terminationStarted = false
        try expect(app.zoomControl.titleOfSelectedItem?.hasSuffix("%") == true, "The popup face is a percentage before the choice: \(app.zoomControl.titleOfSelectedItem ?? "nil")")
        // A popup selects the chosen item first and then sends its action; do the same.
        app.zoomControl.select(item)
        menu.performActionForItem(at: index)
        defer { if app.isActualSize { app.leaveActualSize() } }
        try expect(app.isActualSize && app.canvas.zoom == 1 && app.canvas.outputSize == app.canvas.fullResolutionOutputSize,
                   "Choosing the zoom item puts the canvas at Actual Size (zoom \(app.canvas.zoom), output \(app.canvas.outputSize))")
        try expect(app.zoomControl.titleOfSelectedItem == "100%" && app.zoomControl.selectedItem?.tag != ZoomPopUpButton.actualSizeTag,
                   "The popup face stays a percentage after the choice: \(app.zoomControl.titleOfSelectedItem ?? "nil")")
        _ = chrome
    }

    private static func modernToolSelection() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        func verify(_ selected: SketchTool, _ label: String) throws {
            for tool in SketchTool.allCases {
                guard let button = app.toolButtons[tool] as? CommandButton else { throw Failure(description: "\(label): \(tool) is not a glass button") }
                let isOn = tool == selected
                try expect(button.state == (isOn ? .on : .off), "\(label): \(tool) state")
                try expect(button.plate.isSelected == isOn, "\(label): \(tool) selection")
                try expect((button.plate.style.fill != nil) == isOn, "\(label): only the selected tool is filled (\(tool))")
                try expect(button.activeFamily == (isOn ? .solid : .regular), "\(label): \(tool) glyph family")
                try expect(AppToolTip.text(for: button)?.contains("(selected)") == isOn, "\(label): \(tool) tooltip '\(AppToolTip.text(for: button) ?? "")'")
                if isOn {
                    try expect(abs((button.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001 && button.layer?.borderWidth == 1, "\(label): \(tool) carries the 0.20 accent fill and a 1 pt border")
                    typealias P = DesignTokens.Palette
                    let arm = P.arm(for: button.effectiveAppearance)
                    let blended = P.blend(P.resolve(P.accent, arm: arm), alpha: 0.20, over: P.resolve(P.Surface.window, arm: arm))
                    let glyph = P.contrastRatio(P.resolve(button.contentTintColor ?? .clear, for: button.effectiveAppearance), blended)
                    try expect(glyph >= 4.5, "\(label): \(tool) glyph reads at \(glyph):1 on its blended accent fill")
                    let free = button.icon.flatMap { FontAwesomeFree.glyph(for: $0, family: .solid) }
                    let expected: ChromeIconSource = FontAwesomeFont.isAvailable(.solid) ? .fontAwesome(.solid) : free.map { .fontAwesomeFree($0.name) } ?? .sfSymbol(button.icon?.sfSymbolFallback ?? "")
                    try expect(button.iconSource == expected, "\(label): \(tool) icon source \(button.iconSource)")
                }
            }
            try expect(app.canvas.tool == selected, "\(label): the canvas tool")
        }
        try verify(.arrow, "launch")
        app.setTool(.brush)
        try verify(.brush, "setTool")
        app.canvas.tool = .ellipse
        try verify(.ellipse, "canvas tool change")
        guard let rectangle = app.toolButtons[.rectangle] as? CommandButton else { throw Failure(description: "Rectangle button") }
        rectangle.performClick(nil)
        try verify(.rectangle, "click")
        rectangle.performClick(nil)
        try verify(.rectangle, "second click on the selected tool")
        app.setTool(.crop)
        try verify(.crop, "Crop")
    }

    private static func modernFrameWindowShadowLevelAlpha() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        let alpha = CGFloat(Float32(bitPattern: 0x3f4ccccd))
        app.window.hasShadow = true; app.window.alphaValue = 0.9; app.window.level = .floating
        app.frameSnap()
        try expect(chrome.frameMode && !app.window.hasShadow && app.window.level == level && app.window.alphaValue == alpha,
                   "Modern Frame must drop the shadow, use the screen-saver level and alpha 0.8 while the glass chrome mirrors Frame")
        app.leaveFrame()
        try expect(!chrome.frameMode && app.window.hasShadow && app.window.level == .floating && app.window.alphaValue == 0.9,
                   "Leaving Modern Frame must restore the pre-Frame values and clear the chrome mirror")
        app.frameSnap(); app.cancelFrame()
        try expect(app.window.hasShadow && app.window.level == .floating && app.window.alphaValue == 0.9, "Cancel must restore them too")
    }

    private static func modernFrameMode() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let content = app.window.contentView as? FrameChromeView else { throw Failure(description: "Frame content view") }
        let fullscreen = #selector(AppDelegate.fullscreenSnap)
        let snap = chrome.snapButton, cancel = chrome.cancelFrameButton
        func state(_ label: String, frame: Bool) throws {
            try expect(app.frameMode == frame && chrome.frameMode == frame, "\(label): both layers agree on Frame mode")
            try expect(snap.title == (frame ? "Snap Frame" : "Snap") && snap.icon == (frame ? .frameViewfinder : .crosshairs), "\(label): Snap title and glyph '\(snap.title)'")
            try expect(snap.accessibilityLabel() == (frame ? "Snap Frame" : "Snap"), "\(label): VoiceOver reads '\(snap.accessibilityLabel() ?? "nil")' for Snap")
            try expect(cancel.accessibilityLabel() == "Cancel", "\(label): Cancel keeps its spoken label")
            try expect(AppToolTip.text(for: snap) == (frame ? ModernEditorChrome.snapFrameToolTip : ModernEditorChrome.snapToolTip), "\(label): Snap tooltip")
            try expect(snap.alternateAction == (frame ? nil : fullscreen), "\(label): the Fullscreen alternate is \(frame ? "cleared" : "restored")")
            try expect(snap.alternateTarget === app, "\(label): the alternate target")
            try expect(snap.isPrimary && snap.plate.isPrimary, "\(label): Snap stays the one primary command")
            try expect(cancel.isHidden == !frame, "\(label): Cancel \(frame ? "shows" : "hides")")
            try expect(chrome.wellIsSolid == !frame && content.showsCanvasHole == frame, "\(label): the solid well gives way to the Frame hole")
            app.updateViewportChrome()
            try expect(chrome.resizeButton.isEnabled == !frame && chrome.resizeButton.plate.isDisabled == frame, "\(label): Resize is \(frame ? "dimmed" : "live")")
        }
        try state("launch", frame: false)
        app.frameSnap()
        try state("frameSnap", frame: true)
        app.leaveFrame()
        try state("leaveFrame", frame: false)
        app.frameSnap(); app.cancelFrame()
        try state("cancelFrame", frame: false)
        app.frameSnap(); app.resnap()
        try state("resnap", frame: true)
        app.newFile()
        try state("newFile", frame: false)
    }

    /// Renders the window content and returns the pixel `point` points from the content's bottom-left corner.
    private static func pixel(in content: NSView, at point: NSPoint) throws -> NSColor {
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw Failure(description: "The window content does not render") }
        content.cacheDisplay(in: content.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / content.bounds.width
        guard let color = rep.colorAt(x: Int(point.x * scale), y: rep.pixelsHigh - 1 - Int(point.y * scale)) else { throw Failure(description: "No pixel at \(point)") }
        return color.usingColorSpace(.sRGB) ?? color
    }

    private static func modernCanvasWell() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let content = app.window.contentView as? FrameChromeView else { throw Failure(description: "Frame content view") }
        app.window.appearance = NSAppearance(named: .aqua)
        defer { app.window.appearance = nil }
        let tree = collect(NSView.self, in: content)
        try expect(!tree.contains { $0 is NSVisualEffectView || $0 is NSBackgroundExtensionView }, "No material backdrop and no canvas bleed anywhere in the window")
        try expect(chrome.wellIsSolid && !content.showsCanvasHole, "At launch the well is solid and there is no hole")
        let scroll = chrome.scrollView
        let well = DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.canvasWell, for: NSAppearance(named: .aqua)!)
        try expect(well.alphaComponent == 1 && sameColor(DesignTokens.Palette.resolve(scroll.backgroundColor, for: NSAppearance(named: .aqua)!), well)
                   && sameColor(DesignTokens.Palette.resolve(scroll.contentView.backgroundColor, for: NSAppearance(named: .aqua)!), well), "The scroll view and clip view draw the opaque canvasWell colour")
        content.layoutSubtreeIfNeeded()
        // A point inside the well, just under its top-left corner, away from any centred canvas.
        let corner = scroll.convert(NSPoint(x: 4, y: scroll.bounds.height - 4), to: content)
        let solid = try pixel(in: content, at: corner)
        try expect(solid.alphaComponent == 1 && sameColor(solid, well), "The well renders as the opaque canvasWell colour (\(solid) vs \(well))")
        // Outside the well and outside any bar the window is the solid window surface.
        let windowColor = DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.window, for: NSAppearance(named: .aqua)!)
        let margin = try pixel(in: content, at: NSPoint(x: 5, y: content.bounds.midY))
        try expect(margin.alphaComponent == 1 && sameColor(margin, windowColor), "The margin around the well is the solid window surface (\(margin) vs \(windowColor))")
        try expect(!sameColor(well, windowColor), "The well is distinguishable from the window surface")

        app.frameSnap()
        content.layoutSubtreeIfNeeded()
        try expect(content.showsCanvasHole && !chrome.wellIsSolid && !scroll.drawsBackground && !scroll.contentView.drawsBackground, "Frame mode clears the scroll view and clip view backgrounds")
        let hole = try pixel(in: content, at: corner)
        try expect(hole.alphaComponent == 0, "Frame mode shows a transparent hole where the well was (alpha \(hole.alphaComponent))")
        let framedMargin = try pixel(in: content, at: NSPoint(x: 5, y: content.bounds.midY))
        try expect(framedMargin.alphaComponent == 1, "Frame mode keeps the chrome margin opaque")
        app.leaveFrame()
        content.layoutSubtreeIfNeeded()
        try expect(chrome.wellIsSolid && !content.showsCanvasHole, "Leaving Frame mode restores the solid well")
        let restored = try pixel(in: content, at: corner)
        try expect(restored.alphaComponent == 1 && sameColor(restored, well), "And it renders opaque again")
    }

    private static func modernGlassDepth() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let content = app.window.contentView else { throw Failure(description: "content view") }
        func glass(in view: NSView) -> [NSGlassEffectView] { ((view as? NSGlassEffectView).map { [$0] } ?? []) + view.subviews.flatMap { glass(in: $0) } }
        func check(_ label: String) throws {
            content.layoutSubtreeIfNeeded()
            let found = glass(in: content)
            try expect(found.count == 8 && found.allSatisfy { $0 is GlassSurfaceView }, "\(label): exactly the eight group plates (\(found.count))")
            for view in found {
                var ancestor = view.superview
                while let current = ancestor { try expect(!(current is NSGlassEffectView), "\(label): no glass ancestor above a plate"); ancestor = current.superview }
                try expect(glass(in: view.contentView ?? view).isEmpty, "\(label): no glass inside a plate")
            }
            try expect(collect(NSGlassEffectContainerView.self, in: content).count == 2, "\(label): inside the two bar containers")
            let well = chrome.scrollView.convert(chrome.scrollView.bounds, to: content)
            for view in found where !view.isHiddenOrHasHiddenAncestor {
                let overlap = view.convert(view.bounds, to: content).intersection(well)
                try expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): glass never overlaps the canvas well")
            }
            let capture = try surface(chrome, chrome.snapButton)
            try expect(capture.identifier?.rawValue == "GlassCaptureGroup" && glass(in: capture.contentView ?? capture).isEmpty, "\(label): no glass capsule hides in the capture group (phantom)")
            let owners = collect(CommandButton.self, in: content).filter { !$0.isHiddenOrHasHiddenAncestor }.map { $0.plate } + collect(ChromeFillCell.self, in: content).map { $0.plate }
            let saturated = collect(CommandButton.self, in: content).filter { !$0.isHiddenOrHasHiddenAncestor && ($0.plate.style.fill?.alphaComponent ?? 0) > 0.5 }
            try expect(saturated.count == 1 && saturated[0] === chrome.snapButton, "\(label): Snap is the only saturated accent at rest (\(saturated.count))")
            try expect(owners.count > 20, "\(label): the state fills were found (\(owners.count))")
            let selected = app.toolButtons.values.compactMap { $0 as? CommandButton }.filter { $0.plate.isSelected }
            try expect(selected.count == 1 && abs((selected[0].plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001 && selected[0].layer?.borderWidth == 1, "\(label): the one selected tool is the 0.20 fill with a border")
        }
        try check("default size")
        let minimum = app.window.contentRect(forFrameRect: NSRect(origin: .zero, size: app.window.minSize)).size
        let original = app.window.contentView?.frame.size ?? .zero
        app.window.setContentSize(minimum)
        try check("minimum size")
        app.frameSnap()
        try check("Frame mode at the minimum")
        try expect(chrome.cancelFrameButton.superview != nil && !chrome.cancelFrameButton.isHidden, "Cancel is visible in Frame mode")
        app.leaveFrame()
        app.window.setContentSize(original)
        try check("restored default size")

        // Reduce Transparency and Increase Contrast, injected, on the real window.
        chrome.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: true, reduceMotion: false)
        for plate in glass(in: content).compactMap({ $0 as? GlassSurfaceView }) {
            try expect(plate.tintColor == nil && plate.transparencyPlate?.layer?.backgroundColor?.alpha == 1 && plate.layer?.borderWidth == 1, "Every plate is solid, untinted and bordered under both options")
        }
        chrome.accessibility = .none
    }

    /// Real mouse and key events into the CanvasBorderView that ModernEditorChrome hosts, compared with the same
    /// gesture driven through beginWindowGesture/previewBorderGesture/endWindowGesture .
    private static func modernBorderGestures() throws {
        enum Handle { case corner(CanvasCorner), edge(CanvasEdge) }
        struct Outcome { var data: Data; var geometry: [CGRect]; var background: Data?; var output: CGSize; var canvas: CGSize; var frame: CGRect; var undoName: String? }
        let corners: [CanvasCorner] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let edges: [CanvasEdge] = [.left, .right, .top, .bottom]
        let handles: [Handle] = corners.map { .corner($0) } + edges.map { .edge($0) }

        func run(_ handle: Handle, viaMouse: Bool, cancel: Bool) throws -> (Outcome, before: Data, undoneClean: Bool, borderOK: Bool, begun: Bool) {
            let (fixture, chrome) = try modernFixture()
            let app = fixture.app
            try viewportFixture(app)
            let border = app.canvasBorder
            try expect(border.superview === chrome, "canvasBorder lives inside ModernEditorChrome")
            app.window.contentView?.layoutSubtreeIfNeeded(); app.updateViewportChrome()
            let before = try app.canvas.snapshotDocumentData()
            let flags: NSEvent.ModifierFlags = { if case .edge = handle { return [.option] } else { return [] } }()
            let delta = CGPoint(x: 20, y: 12)
            var begun = true
            if viaMouse {
                let inset = CanvasBorderView.border / 2
                let local: CGPoint
                switch handle {
                case .corner(.topLeft): local = CGPoint(x: inset, y: inset)
                case .corner(.topRight): local = CGPoint(x: border.bounds.width - inset, y: inset)
                case .corner(.bottomLeft): local = CGPoint(x: inset, y: border.bounds.height - inset)
                case .corner(.bottomRight): local = CGPoint(x: border.bounds.width - inset, y: border.bounds.height - inset)
                case .edge(.left): local = CGPoint(x: inset, y: border.bounds.midY)
                case .edge(.right): local = CGPoint(x: border.bounds.width - inset, y: border.bounds.midY)
                case .edge(.top): local = CGPoint(x: border.bounds.midX, y: inset)
                case .edge(.bottom): local = CGPoint(x: border.bounds.midX, y: border.bounds.height - inset)
                }
                // The window moves and resizes mid-drag, so each event is built from a fixed screen point like a real mouse.
                let start = app.window.convertPoint(toScreen: border.convert(local, to: nil))
                func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                    guard let event = NSEvent.mouseEvent(with: type, location: app.window.convertPoint(fromScreen: point), modifierFlags: flags, timestamp: 0,
                        windowNumber: app.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
                        throw Failure(description: "Internal border mouse event allocation")
                    }
                    return event
                }
                // Screen space is y-up; the gesture delta is right/down.
                let step1 = CGPoint(x: start.x + delta.x / 2, y: start.y - delta.y / 2)
                let end = CGPoint(x: start.x + delta.x, y: start.y - delta.y)
                border.mouseDown(with: try mouse(.leftMouseDown, start))
                begun = app.windowGesture != nil
                border.mouseDragged(with: try mouse(.leftMouseDragged, step1))
                border.mouseDragged(with: try mouse(.leftMouseDragged, end))
                if cancel {
                    try expect(app.canvas.editingUndoManager.canUndo == false, "Preview registers no Undo before the gesture ends")
                    guard let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: app.window.windowNumber, context: nil, characters: "\u{1b}",
                        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else {
                        throw Failure(description: "Internal Escape event allocation")
                    }
                    border.keyDown(with: esc)
                } else {
                    border.mouseUp(with: try mouse(.leftMouseUp, end))
                }
            } else {
                let h: CanvasBorderHandle = { switch handle { case .corner(let c): return .corner(c); case .edge(let e): return .edge(e) } }()
                begun = app.beginWindowGesture(h, flags: flags)
                app.previewBorderGesture(delta: CGPoint(x: delta.x / 2, y: delta.y / 2), flags: flags)
                app.previewBorderGesture(delta: delta, flags: flags)
                app.endWindowGesture(cancelled: cancel)
            }
            let content = try app.window.contentView.unwrap("content view")
            let expectedFrame = app.canvas.convert(app.canvas.bounds, to: content).insetBy(dx: -8, dy: -8)
            let borderOK = border.frame == expectedFrame && !expectedFrame.isEmpty
            let outcome = Outcome(data: try app.canvas.snapshotDocumentData(), geometry: app.canvas.document.elements.flatMap { [$0.rect, $0.bounds] },
                                  background: app.canvas.document.backgroundPNG, output: app.canvas.outputSize,
                                  canvas: app.canvas.canvasSize, frame: app.window.frame,
                                  undoName: app.canvas.editingUndoManager.undoActionName)
            var clean = true
            if !cancel {
                let after = outcome.data
                try expect(app.canvas.editingUndoManager.canUndo, "A committed border gesture registers an Undo")
                app.undo()
                clean = try app.canvas.snapshotDocumentData() == before && !app.canvas.editingUndoManager.canUndo
                app.redo()
                let redone = try app.canvas.snapshotDocumentData() == after; clean = clean && redone
            } else {
                clean = !app.canvas.editingUndoManager.canUndo && outcome.data == before
            }
            return (outcome, before, clean, borderOK, begun)
        }

        for handle in handles {
            let reference = try run(handle, viaMouse: false, cancel: false)
            let mouse = try run(handle, viaMouse: true, cancel: false)
            try expect(mouse.begun, "Mouse down on \(handle) begins a border gesture")
            try expect(reference.0.output != CGSize(width: 150, height: 90) || reference.0.canvas != CGSize(width: 300, height: 180),
                       "\(handle) reference gesture changes the canvas")
            try expect(mouse.0.output == reference.0.output && mouse.0.canvas == reference.0.canvas &&
                       mouse.0.geometry == reference.0.geometry && mouse.0.background == reference.0.background &&
                       mouse.0.undoName == reference.0.undoName,
                       "Mouse drag on \(handle) yields the same outputSize/crop result as the direct gesture API (\(mouse.0.output) vs \(reference.0.output))")
            try expect(mouse.undoneClean, "\(handle) mouse gesture is exactly one Undo and Redo restores it")
            try expect(mouse.borderOK, "canvasBorder.frame tracks the canvas after the \(handle) gesture")
            let escaped = try run(handle, viaMouse: true, cancel: true)
            try expect(escaped.begun && escaped.undoneClean && escaped.0.output == CGSize(width: 150, height: 90) &&
                       escaped.0.canvas == CGSize(width: 300, height: 180) && escaped.borderOK,
                       "Escape during a \(handle) drag restores the document, leaves no Undo and keeps the border on the canvas")
        }
        for corner in corners {
            let width: CGFloat = (corner == .topLeft || corner == .bottomLeft) ? 130 : 170
            let result = try run(.corner(corner), viaMouse: true, cancel: false)
            try expect(result.0.output == CGSize(width: width, height: (width * 0.6).rounded()),
                       "Mouse-dragged \(corner) corner matches the width-driven numbers")
        }
    }

    private static func modernAccessibilityInjection() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let surfaces = collect(GlassSurfaceView.self, in: app.window.contentView!)
        let buttons = collect(CommandButton.self, in: app.window.contentView!)
        try expect(surfaces.count == 8, "Both bars have their eight plates (\(surfaces.count))")
        let snap = chrome.snapButton, arrow = try (app.toolButtons[.arrow] as? CommandButton).unwrap("arrow"), undo = chrome.undoButton
        for button in buttons { button.appearance = NSAppearance(named: .aqua) }
        // Undo is dimmed on a blank document (audit F-J1-020) and a dimmed button shows no hover fill: give it something to undo.
        app.canvas.setBackgroundColor(.blue)
        undo.setHovered(true)
        try expect(buttons.allSatisfy { $0.plate.accessibility == .none && $0.plate.lastAnimationDuration == StatePlate.animationDuration }, "Buttons start with no display options and animate")
        try expect(abs((undo.plate.style.fill?.alphaComponent ?? 0) - 0.08) < 0.001 && snap.plate.style.fill?.alphaComponent == 1, "Baseline hover fill and primary accent")
        try expect(arrow.plate.isSelected && abs((arrow.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001, "Arrow is selected at 0.20")
        let options = ChromeAccessibility(reduceTransparency: true, increaseContrast: true, reduceMotion: true)
        chrome.accessibility = options
        try expect(surfaces.allSatisfy { $0.accessibility == options && $0.transparencyPlate != nil && $0.layer?.borderWidth == 1 }, "Every plate receives the injected options: solid plate and contrast border")
        try expect(buttons.allSatisfy { $0.plate.accessibility == options && $0.plate.lastAnimationDuration == 0 }, "Every button receives them and stops animating")
        try expect(abs((undo.plate.style.fill?.alphaComponent ?? 0) - 0.16) < 0.001 && snap.plate.style.fill?.alphaComponent == 1, "Increase Contrast strengthens the hover fill; Snap stays the accent")
        try expect(abs((arrow.plate.style.fill?.alphaComponent ?? 0) - 0.32) < 0.001 && arrow.layer?.borderWidth == 1, "Increase Contrast strengthens the selected tool and keeps its border")
        chrome.accessibility = .none
        try expect(surfaces.allSatisfy { $0.accessibility == .none && $0.transparencyPlate == nil && $0.layer?.borderWidth == 0 }, "Clearing the options restores every plate")
        try expect(buttons.allSatisfy { $0.plate.accessibility == .none && $0.plate.lastAnimationDuration == StatePlate.animationDuration }, "And every button")
        try expect(abs((undo.plate.style.fill?.alphaComponent ?? 0) - 0.08) < 0.001 && abs((arrow.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001, "And the fills")
        undo.setHovered(false)
    }

    private static func modernActionRouting() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let routes: [(String, CommandButton, Selector)] = [
            ("Hide", chrome.hideButton, #selector(AppDelegate.vanish)), ("Photos", chrome.photosButton, #selector(AppDelegate.showPhotos)),
            ("Save", chrome.saveButton, #selector(AppDelegate.saveHistory)), ("History", chrome.historyButton, #selector(AppDelegate.showHistory)),
            ("Snap", chrome.snapButton, #selector(AppDelegate.snapButtonPressed)),
            ("Cancel", chrome.cancelFrameButton, #selector(AppDelegate.cancelFrame)), ("Font", chrome.fontButton, #selector(AppDelegate.chooseFont)),
            ("Undo", chrome.undoButton, #selector(AppDelegate.undo)), ("Wipe", chrome.wipeButton, #selector(AppDelegate.wipe)),
            ("Resize…", chrome.resizeButton, #selector(AppDelegate.resize)),
            ("Webpost…", chrome.shareButton, #selector(AppDelegate.share(_:)))
        ]
        for (name, button, action) in routes {
            try expect(button.target === app && button.action == action, "\(name) sends its recovered action to the AppDelegate")
        }
        try expect(chrome.snapButton.menu == nil && chrome.snapButton.alternateTarget === app && chrome.snapButton.alternateAction == #selector(AppDelegate.fullscreenSnap),
                   "Snap keeps a primary crosshair with the Fullscreen secondary and no menu")
        // Screen capture only: no Cam/Camera button or selector exists in the Modern chrome.
        try expect(!app.responds(to: NSSelectorFromString("cameraSnap")) && !app.responds(to: NSSelectorFromString("runCameraSnap:")), "The AppDelegate has no camera action")
        let modernButtons = collect(NSButton.self, in: app.window.contentView!)
        try expect(!modernButtons.contains { $0.title.lowercased().contains("cam") || ($0.accessibilityLabel() ?? "").lowercased().contains("camera") },
                   "No Cam or Camera button exists in the Modern chrome")
        // The route reaches behavior, not only selectors.
        let before = app.canvas.document
        app.canvas.setBackgroundColor(.yellow)
        try expect(app.canvas.document != before && app.validateMenuItem(NSMenuItem(title: "Undo", action: #selector(AppDelegate.undo), keyEquivalent: "z")), "A drawing edit is undoable")
        chrome.undoButton.performClick(nil)
        try expect(app.canvas.document == before, "The Modern Undo button undoes the edit")
        // Hidden/disabled state reaches the glass the way AppDelegate toggles it for the viewport.
        app.updateViewportChrome()
        chrome.resizeButton.isEnabled = false
        try expect(chrome.resizeButton.plate.isDisabled, "A disabled command dims itself")
        chrome.resizeButton.isEnabled = true
    }

    /// The stage cases, driven through the glass button: what the title, the enabled state, the glass and VoiceOver each report.
    private static func modernWipeStages() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, canvas = app.canvas
        let button = chrome.wipeButton
        guard app.wipeButton === button, button.action == #selector(AppDelegate.wipe), button.target === app else {
            throw Failure(description: "The Wipe button must be the chrome's, located by its action")
        }
        func reads(_ stage: WipeStage) -> Bool {
            let title = stage.actionName, enabled = stage.isEnabled
            return button.title == title && button.isEnabled == enabled && button.accessibilityLabel() == title
                && AppToolTip.text(for: button) == stage.toolTip && button.accessibilityHelp() == stage.toolTip
                && button.isAccessibilityEnabled() == enabled
                && button.plate.isDisabled == !enabled && button.alphaValue == (enabled ? 1 : 0.38) && button.plate.style.fill == nil
        }
        func detail() -> String {
            "title '\(button.title)', enabled \(button.isEnabled), VoiceOver '\(button.accessibilityLabel() ?? "nil")' enabled \(button.isAccessibilityEnabled()), "
                + "disabled \(button.plate.isDisabled), alpha \(button.alphaValue), fill \(String(describing: button.plate.style.fill))"
        }
        let shape = SketchElement(kind: .rectangle)
        let untouched = canvas.editingUndoManager.undoActionName
        try expect(reads(.blank), "A fresh drawing reads a dimmed, disabled Blank: " + detail())
        button.performClick(nil)
        try expect(reads(.blank) && canvas.editingUndoManager.undoActionName == untouched, "A disabled Blank button ignores presses")
        app.wipe()
        try expect(reads(.blank) && canvas.editingUndoManager.undoActionName == untouched,
                   "The Wipe menu command on a blank drawing changes nothing")

        canvas.setBackground(try image(size: CGSize(width: 120, height: 80)))
        try expect(reads(.clear) && canvas.document.backgroundPNG != nil, "A snap image alone reads a live Clear: " + detail())
        canvas.document.elements = [shape]
        try expect(reads(.wipe), "Artwork over a snap reads a live Wipe: " + detail())
        button.performClick(nil)
        try expect(canvas.document.elements.isEmpty && canvas.document.backgroundPNG != nil && reads(.clear),
                   "Wipe removes only the artwork and the glass reads Clear: " + detail())
        button.performClick(nil)
        try expect(canvas.document.backgroundPNG == nil && canvas.document.backgroundColor == .white && reads(.blank),
                   "Clear removes the snap and the glass dims to Blank: " + detail())
        button.performClick(nil)
        try expect(reads(.blank), "The disabled Blank button stays Blank after the last stage")

                canvas.document.elements = [shape]
        try expect(reads(.wipe), "Artwork over a white drawing without a snap reads Wipe: " + detail())
        button.performClick(nil)
        try expect(canvas.document.elements.isEmpty && reads(.blank), "Wiping artwork with no snap lands on a dimmed Blank: " + detail())

                canvas.setBackgroundColor(.red)
        try expect(reads(.clear), "A coloured backdrop alone reads Clear: " + detail())
        app.undo(); try expect(reads(.blank), "Undo returns the glass to the dimmed Blank: " + detail())
        app.redo(); try expect(reads(.clear), "Redo brings the live Clear back: " + detail())
        _ = try editor(app, text: "Typing")
        try expect(reads(.wipe), "Field editing over a coloured backdrop reads Wipe: " + detail())
        button.performClick(nil)
        try expect(canvas.document.elements.isEmpty && canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty && reads(.clear),
                   "Wipe commits and removes the field and leaves the coloured backdrop as Clear: " + detail())
    }

    private static func modernLayoutEvidence() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        app.writeLayoutEvidence()
        let folder = ProcessInfo.processInfo.environment["OPENSNAP_EVIDENCE_DIR"] ?? app.support.path
        let data = try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("layout.json"))
        guard let evidence = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(description: "layout.json is not an object") }
        let appearance = evidence["appearance"] as? [String: Any]
        try expect(appearance?["modernChrome"] as? Bool == true, "appearance reports the glass chrome: \(String(describing: appearance))")
        try expect(evidence["bezelHeader"] == nil, "Modern has no logo, so the brand-centred header evidence is absent")
        let tools = evidence["toolButtons"] as? [[String: Any]] ?? []
        try expect(tools.count == 10 && tools.allSatisfy { ($0["fontSize"] as? Double ?? 0) >= 18 }, "Ten tool buttons report readable fonts")
        try expect(tools.filter { $0["selected"] as? Bool == true }.compactMap { $0["tool"] as? String } == ["arrow"], "Exactly the Arrow tool reports selected")
        let controls = evidence["bezelControls"] as? [[String: Any]] ?? []
        try expect(controls.count >= 24, "The Modern controls are inspected (\(controls.count))")
        // AppKit hosts each button's title in a private text field that reports its own 13 pt default
        // while drawing at the button's font; only a control whose parent is a button gets that exemption.
        let rects = controls.map { NSRectFromString($0["frame"] as? String ?? "") }
        for (index, entry) in controls.enumerated() where entry["hidden"] as? Bool != true {
            let label = entry["label"] as? String ?? "?"
            let frame = rects[index], visible = NSRectFromString(entry["visibleFrame"] as? String ?? "")
            let isButtonInternal = entry["parentIsButton"] as? Bool == true
            if !isButtonInternal { try expect((entry["fontSize"] as? Double ?? 0) >= 18, "\(label) is at least 18 pt: \(entry)") }
            try expect(!frame.isEmpty && abs(frame.width - visible.width) < 0.5 && abs(frame.height - visible.height) < 0.5, "\(label) is not clipped (\(frame) vs \(visible))")
        }
        try expect(!chrome.header.subviews.contains { $0.identifier?.rawValue == "OpenSnapBrand" }, "The top bar carries no logo")
        try expect(app.window.contentView?.subviews.contains { $0.identifier?.rawValue == "OpenSnapHeader" } == false, "The header lives inside the chrome, which the evidence accommodates")
    }

    private static func modernMenus() throws {
        let (fixture, _) = try modernFixture()
        let app = fixture.app
        guard let bar = NSApp.mainMenu else { throw Failure(description: "Main menu") }
        var items: [NSMenuItem] = []
        func walk(_ menu: NSMenu) { for item in menu.items { items.append(item); if let sub = item.submenu { walk(sub) } } }
        walk(bar)
        let mapped = items.filter { !$0.isSeparatorItem && $0.action.map { MenuSymbols.map[$0] != nil } == true }
        try expect(mapped.count >= 40, "The main menu holds the mapped commands (\(mapped.count))")
        let missing = mapped.filter { $0.image == nil }.map(\.title)
        try expect(missing.isEmpty, "Modern menu items without a symbol: \(missing)")
        try expect(mapped.allSatisfy { $0.image?.isTemplate == true }, "Menu symbols are template images")
        try expect(items.filter(\.isSeparatorItem).allSatisfy { $0.image == nil }, "Separators stay bare")
        guard let preferences = items.first(where: { $0.action == #selector(AppDelegate.showPreferences) }),
              let cancel = items.first(where: { $0.action == #selector(AppDelegate.cancelSnapshot) }),
              let undo = items.first(where: { $0.action == #selector(AppDelegate.undo) }) else { throw Failure(description: "Expected menu items") }
        try expect(app.validateMenuItem(preferences) && !app.validateMenuItem(cancel) && !app.validateMenuItem(undo), "Symbols do not change which commands are available")
        app.canvas.setBackgroundColor(.yellow)
        try expect(app.validateMenuItem(undo), "Undo becomes available after an edit")
        let toolbox = collect(NSPopUpButton.self, in: app.window.contentView!).first { $0.accessibilityLabel() == "Toolbox" }
        try expect(toolbox?.menu?.items.contains { $0.action == #selector(AppDelegate.saveHistory) } == true, "The Toolbox menu keeps Save to History")
    }

    // MARK: T15 cases

    /// The Size panel opened off the screen (the fixture gives its host a presenter that shows nothing), so mouse events can be handed to its track and presets.
    private static func hostSizePopover(_ app: AppDelegate) throws -> (GlassPanelHost, SizePopoverContent, remove: () -> Void) {
        let slider = app.widthControl
        slider.showPopover()
        guard let host = slider.panel, let panel = slider.popoverContent else { throw Failure(description: "The Size panel did not open") }
        host.window.contentView?.layoutSubtreeIfNeeded()
        return (host, panel, { slider.dismissPopover() })
    }

    private static func sizeKey(_ code: UInt16, in app: AppDelegate, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: app.window.windowNumber, context: nil,
                                           characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) else { throw Failure(description: "Key event") }
        return event
    }

    private static func modernSizePopoverUndo() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, slider = app.widthControl
        guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
        var text = SketchElement(kind: .text); text.text = "Size proof"; text.fontName = "Courier"; text.fontSize = 26; text.outlined = false; text.shadowed = false
        let undo = app.canvas.editingUndoManager
        func fresh() {
            app.canvas.document.elements = [text]; app.canvas.selection = [text.id]
            app.canvas.strokeWidth = 6.75; app.syncDrawingControls()
            undo.removeAllActions()
        }
        func oneStep(_ label: String, _ gesture: () throws -> Void) throws {
            fresh()
            let before = app.canvas.document.elements
            try gesture()
            try expect(undo.groupingLevel == 0 && !app.sizeUndoGrouping, "\(label): no undo group is left open (level \(undo.groupingLevel))")
            try expect(app.canvas.document.elements != before && app.canvas.document.elements[0].fontSize != 26, "\(label): the selected text changed size")
            app.undo()
            try expect(app.canvas.document.elements == before && !undo.canUndo, "\(label): one Undo restored the original size and nothing else was recorded")
            app.redo()
            try expect(app.canvas.document.elements != before, "\(label): Redo reapplies the whole gesture")
        }

        // The pill opens its panel below itself, in the top bar.
        fresh()
        let (host, panel, remove) = try hostSizePopover(app)
        defer { slider.dismissPopover(); remove() }
        try expect(host.placement?.edge == .minY && host.anchor === slider && slider.isDescendant(of: chrome.header) && !host.requestedKey,
                   "The Size panel opens below the pill in the top bar and leaves the keyboard on the pill")
        func pointer(_ type: NSEvent.EventType, _ fraction: CGFloat, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            let track = panel.trackView
            let location = track.convert(NSPoint(x: track.x(forFraction: fraction), y: 18), to: nil)
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: 0, windowNumber: app.window.windowNumber,
                                                 context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { throw Failure(description: "Mouse event") }
            return event
        }
        try oneStep("A pointer drag across the track") {
            try panel.trackView.mouseDown(with: pointer(.leftMouseDown, 1))
            try expect(undo.groupingLevel == 1 && app.sizeUndoGrouping, "Mouse down opens exactly one undo group")
            for fraction in [0.9, 0.75, 0.5, 1.0] { try panel.trackView.mouseDragged(with: pointer(.leftMouseDragged, CGFloat(fraction))) }
            try panel.trackView.mouseUp(with: pointer(.leftMouseUp, 1))
        }
        try expect(app.canvas.strokeWidth == 12, "The drag ended on the largest size")
        try oneStep("A preset click") { panel.presetButtons[4].performClick(nil) }
        try oneStep("An arrow key on the pill") { try slider.keyDown(with: sizeKey(124, in: app)) }
        try oneStep("An assistive increment") { _ = slider.accessibilityPerformIncrement() }
        try oneStep("A Shift arrow") { try slider.keyDown(with: sizeKey(124, in: app, flags: [.shift])) }
        // Dismissing the panel in the middle of a drag closes the group; the late mouse-up cannot close it twice.
        try oneStep("A panel dismissed mid-drag") {
            try panel.trackView.mouseDown(with: pointer(.leftMouseDown, 1))
            try panel.trackView.mouseDragged(with: pointer(.leftMouseDragged, 0.75))
            try expect(undo.groupingLevel == 1, "The drag is open")
            slider.dismissPopover()
            try expect(undo.groupingLevel == 0 && !app.sizeUndoGrouping && !slider.isPopoverShown, "Dismissal closed the group")
            try panel.trackView.mouseUp(with: pointer(.leftMouseUp, 0.75))
        }
        // The hide and terminate paths close the panel and any open group too.
        window.simulatesVisibility = true; window.shown = true
        fresh()
        slider.showPopover()
        try expect(slider.beginGesture() && undo.groupingLevel == 1, "A gesture is open")
        app.vanish()
        try expect(!slider.isPopoverShown && undo.groupingLevel == 0 && !app.sizeUndoGrouping, "Hiding the window dismisses the panel and ends the group")
        window.shown = true
        fresh()
        slider.showPopover()
        try expect(slider.beginGesture(), "A gesture is open again")
        app.canvas.strokeWidth = 12; app.syncDrawingControls()
        answer(.alertSecondButtonReturn)
        try expect(app.applicationShouldTerminate(NSApp) == .terminateCancel, "Cancel keeps the app running")
        try expect(!slider.isPopoverShown && undo.groupingLevel == 0 && !app.sizeUndoGrouping, "Quit dismisses the panel and ends the group before it decides")
        // The pill toggles with Space and Escape and never opens while disabled.
        try expect(!slider.isPopoverShown, "Closed")
        try slider.keyDown(with: sizeKey(49, in: app)); try expect(slider.isPopoverShown, "Space opens the panel")
        try slider.keyDown(with: sizeKey(53, in: app)); try expect(!slider.isPopoverShown, "Escape closes it")
    }

    private static func modernFrameCaptureRect() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let content = app.window.contentView as? FrameChromeView else { throw Failure(description: "Frame content view") }
        defer { AppSafetyCaptureCoordinator.holdCapture = false; AppSafetyCaptureCoordinator.captureCallbacks = []; AppSafetyCaptureCoordinator.requests = [] }
        let scroll = chrome.scrollView
        try expect(scroll.hasHorizontalScroller && scroll.hasVerticalScroller, "The editor scrolls normally outside Frame mode")
        let defaultFrame = app.window.frame
        for (name, frame) in [("minimum", CGRect(origin: defaultFrame.origin, size: app.window.minSize)), ("default", defaultFrame)] {
            for canvas in [CGSize(width: 3000, height: 2000), CGSize(width: 220, height: 100)] {
                app.setWindowFrame(frame)
                app.canvas.newBlank(size: canvas)
                app.setCanvasDisplayZoom(1, label: "Test")
                content.layoutSubtreeIfNeeded()
                app.enterFrame(keepingAnnotations: false, manualFlags: [])
                content.layoutSubtreeIfNeeded(); app.updateViewportChrome()
                let label = "\(name) \(Int(canvas.width))x\(Int(canvas.height))"
                let hole = scroll.convert(scroll.bounds, to: content)
                try expect(abs(hole.minX - 12) < 0.5 && abs(hole.maxX - (content.bounds.width - 12)) < 0.5, "\(label): the Frame hole spans margin to margin (\(hole.minX) to \(hole.maxX))")
                try expect(!scroll.hasHorizontalScroller && !scroll.hasVerticalScroller && scroll.contentView.frame == scroll.bounds, "\(label): no scroller can sit in the hole")
                let holeOnScreen = app.window.convertToScreen(scroll.convert(scroll.bounds, to: nil))
                let rect = app.frameViewportScreenRect
                // What the user sees through the hole is what is captured: the whole viewport, with a smaller canvas centred inside it.
                try expect(abs(rect.minX - holeOnScreen.minX) < 0.5 && abs(rect.maxX - holeOnScreen.maxX) < 0.5 && abs(rect.minY - holeOnScreen.minY) < 0.5 && abs(rect.maxY - holeOnScreen.maxY) < 0.5,
                           "\(label): the snap rect is the whole hole (\(rect) vs \(holeOnScreen))")
                let canvasOnScreen = app.window.convertToScreen(app.canvas.convert(app.canvas.bounds, to: nil))
                if canvas.width < scroll.contentView.frame.width {
                    try expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(canvasOnScreen) && abs(canvasOnScreen.midX - holeOnScreen.midX) < 1 && abs(canvasOnScreen.midY - holeOnScreen.midY) < 1,
                               "\(label): a small canvas sits centred inside the snapped hole (\(canvasOnScreen) in \(rect))")
                }
                AppSafetyCaptureCoordinator.holdCapture = true
                app.performFrameSnap()
                try expect(AppSafetyCaptureCoordinator.captureCallbacks.count == 1, "\(label): the Frame snap reached the capture")
                let top = NSScreen.screens.first?.frame.maxY ?? rect.maxY
                let sent = try (app.capture.frameRect).unwrap("capture rect")
                try expect(sent == NSRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height), "\(label): the capture is sent exactly the viewport rect (\(sent))")
                try expect(!scroll.hasHorizontalScroller && !scroll.hasVerticalScroller, "\(label): the scrollers stay hidden during the snap")
                AppSafetyCaptureCoordinator.captureCallbacks.removeFirst()(.failure(AppSafetyCaptureCoordinator.cancellation))
                AppSafetyCaptureCoordinator.holdCapture = false
                app.cancelFrame()
                try expect(scroll.hasHorizontalScroller && scroll.hasVerticalScroller, "\(label): leaving Frame mode restores the scrollers")
            }
        }
    }

    /// A capture larger than the screen allows: the Original size checkbox appears for it.
    private static func largeShot(_ app: AppDelegate) throws {
        let capacity = try app.maximumNormalCanvas.unwrap("screen capacity")
        app.receiveCapture(.success(try image(size: CGSize(width: ceil(capacity.width + 300), height: ceil(capacity.height + 150)))), discardAlreadyApproved: true)
        app.dirty = false
    }

    private static func modernStatusMergesDragSize() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let content = app.window.contentView else { throw Failure(description: "content") }
        app.dragPreviewTimer?.invalidate(); app.dragPreviewTimer = nil
        app.footerShowsPictureFactsOverride = true   // the footer carries the picture's facts only where the title bar is gone (full screen)
        app.updateDragPreview()
        let text = app.status.stringValue
        try expect(text.hasPrefix("Arrow · ") && text.contains("×") && text.components(separatedBy: " · ").count == 5 && text.contains(" · PNG · ") && text.hasSuffix("KB"), "The status reads tool, state, export size and format in one line: \(text)")
        try expect(app.dragSizeLabel.superview == nil && AppToolTip.text(for: app.status) == text && (app.status.accessibilityValue() as? String) == text, "The full text is the tooltip and the spoken value; no separate size label exists on screen")
        try expect(app.status.lineBreakMode == .byTruncatingTail, "A narrow status truncates its tail")
        try expect(app.dragPreviewTimer == nil, "Writing the size into the status does not re-arm the one-second drag-preview timer")
        app.updateStatus()
        try expect(app.dragPreviewTimer != nil, "An ordinary status update still schedules the preview")
        app.dragPreviewTimer?.invalidate(); app.dragPreviewTimer = nil
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        let hint = app.status.stringValue
        app.updateDragPreview(); app.updateStatus()
        try expect(app.status.stringValue == hint && app.status.stringValue.hasPrefix("Frame"), "Frame mode keeps its own hint when the status refreshes")
        app.cancelFrame()
        try expect(app.status.stringValue.hasPrefix("Arrow · ") && app.status.stringValue.contains("×"), "Leaving Frame brings the merged status back")
        app.dragPreviewTimer?.invalidate(); app.dragPreviewTimer = nil
        // A large shot shows the Original size checkbox; at the minimum width the status still keeps 120 pt next to it.
        try largeShot(app)
        app.setWindowFrame(CGRect(origin: app.window.frame.origin, size: app.window.minSize))
        app.updateDragPreview(); app.updateViewportChrome()
        content.layoutSubtreeIfNeeded()
        try expect(!app.dragOriginalControl.isHidden && app.isLargeShot, "A large shot shows the Original size checkbox")
        let full = (app.status.cell?.copy() as? NSCell).map { $0.stringValue = AppToolTip.text(for: app.status) ?? ""; return $0.cellSize.width } ?? 0
        try expect(app.status.frame.width >= 120 && app.status.frame.width <= full + 0.5, "At the minimum width with the checkbox the status keeps \(app.status.frame.width) pt (needs 120)")
        // A label's frame reaches 2 pt past the alignment rect layout places; the 12 pt group gap is measured on the alignment rect.
        let placed = app.status.superview!.convert(app.status.alignmentRect(forFrame: app.status.frame), to: nil)
        try expect(placed.maxX <= chrome.saveButton.convert(chrome.saveButton.bounds, to: nil).minX - 12 + 0.5, "The status keeps its 12 pt gap before Save")
    }

    private static func modernZoomPanel() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, zoom = app.zoomControl
        let probe = NativeMenuProbe()
        defer { probe.stop() }
        offScreen(zoom.choicePanel)
        // A blank canvas has no Actual Size to offer: the row is there, dimmed, and choosing it changes nothing.
        zoom.performClick(nil)
        var panel = zoom.choicePanel
        let actualRow = try (panel.rows.first { $0.title == "Actual Size" }).unwrap("the Actual Size row")
        try expect(!actualRow.isEnabled && !app.canToggleActualSize && actualRow.kind == .toggle, "Without a snap picture the Actual Size row is a dimmed toggle")
        actualRow.performClick(nil)
        try expect(!app.isActualSize && zoom.titleOfSelectedItem == "100%", "Choosing a dimmed Actual Size does nothing and keeps the 100% face")
        zoom.choicePanel.host.close()
        try viewportFixture(app)
        app.setCanvasDisplayZoom(0.83, label: "Fit")
        zoom.performClick(nil)
        panel = zoom.choicePanel
        try expect(zoom.isOpen && panel.host.plates.count == 2 && panel.rows.count == 8, "Percentages and the computed row on one plate, Actual Size on its own (\(panel.host.plates.count) plates, \(panel.rows.count) rows)")
        try expect(panel.rows.map(\.title) == ["83%", "25%", "50%", "75%", "100%", "150%", "200%", "Actual Size"], "Rows in menu order: \(panel.rows.map(\.title))")
        try expect(panel.rows.dropLast().allSatisfy { $0.kind == .option } && panel.rows.last?.kind == .toggle, "Percent rows (and the computed Fit row) are options; Actual Size is a toggle")
        try expect(panel.rows.filter(\.isChosen).map(\.title) == ["83%"], "The computed Fit row is the chosen one: \(panel.rows.filter(\.isChosen).map(\.title))")
        try expect(panel.rows.last?.isEnabled == true && panel.rows.last?.shortcutText == MenuShortcut.text(for: try (zoom.menu?.items.last).unwrap("last item")), "With a snap picture Actual Size is enabled and shows the main-menu shortcut")
        let footer = zoom.window!.convertToScreen(zoom.convert(zoom.bounds, to: nil))
        try expect(panel.host.placement.map { $0.edge == .maxY && $0.frame.minY >= footer.maxY } == true, "The panel opens above the footer, not over it")
        // A percentage reaches the canvas through changeZoom, and the pop-up shows it.
        try (panel.rows.first { $0.title == "150%" }).unwrap("150% row").performClick(nil)
        try expect(abs(app.canvas.zoom - 1.5) < 0.001 && zoom.titleOfSelectedItem == "150%" && !zoom.isOpen, "Choosing 150% zooms the canvas and the face reads 150% (zoom \(app.canvas.zoom))")
        zoom.performClick(nil)
        try expect(panel.rows.filter(\.isChosen).map(\.title) == ["150%"], "Reopened, 150% is the chosen row: \(panel.rows.filter(\.isChosen).map(\.title))")
        // Actual Size: the main-menu command runs; the face stays a percentage and the zoom dims while it is up.
        try (panel.rows.first { $0.title == "Actual Size" }).unwrap("Actual Size row").performClick(nil)
        try waitForMain("The face is a percentage again") { zoom.titleOfSelectedItem?.hasSuffix("%") == true && zoom.selectedItem?.tag != ZoomPopUpButton.actualSizeTag }
        defer { if app.isActualSize { app.leaveActualSize() } }
        try expect(app.isActualSize && app.canvas.zoom == 1 && !zoom.isEnabled, "Actual Size is up and the zoom is dimmed (zoom \(app.canvas.zoom))")
        zoom.performClick(nil)
        try expect(!zoom.isOpen, "A dimmed zoom opens nothing")
        // The screenshot harness can still show the state: the panel presents without the button's own gate, and Actual Size reads on.
        zoom.choicePanel.present(relativeTo: zoom, preferredEdge: ChoiceEdge.above, keyboard: false)
        try expect(zoom.isOpen && zoom.choicePanel.rows.last?.title == "Actual Size" && zoom.choicePanel.rows.last?.isChosen == true && zoom.choicePanel.rows.last?.isEnabled == true,
                   "Presented directly, the panel shows Actual Size chosen while it is up")
        zoom.choicePanel.host.close()
        app.leaveActualSize()
        zoom.performClick(nil)
        try expect(zoom.isOpen && panel.rows.last?.isChosen == false, "Back out of Actual Size the toggle is off")
        // Escape returns the focus to the zoom.
        zoom.choicePanel.host.close()
        app.window.makeFirstResponder(zoom)
        zoom.keyDown(with: try keyDown(125, in: app))
        try expect(zoom.isOpen && panel.focusedRow?.isChosen == true, "Down opens it on the chosen row")
        panel.host.window.sendEvent(panelKey(53, in: panel.host.window))
        try expect(!zoom.isOpen && app.window.firstResponder === zoom, "Escape closes it and the zoom has the focus again")
        try expect(probe.began == 0 && zoom.target === app && zoom.action == #selector(AppDelegate.changeZoom(_:)), "No native menu started and the zoom keeps its action")
        _ = chrome
    }

    private static func modernOriginalSizeToggle() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, toggle = app.dragOriginalControl
        try expect(toggle.kind == .toggle && toggle.indicator == .checkbox && toggle.title == "Original size" && toggle.accessibilityLabel() == "Export at original size" && toggle.accessibilityRole() == .checkBox,
                   "A checkbox toggle titled Original size and spoken as Export at original size")
        try expect(AppToolTip.text(for: toggle)?.hasPrefix("Drag out, copy, export and upload the picture at its own pixel size") == true, "It keeps its tooltip")
        try expect(chrome.surface(for: toggle)?.identifier?.rawValue == "GlassViewGroup" && toggle.target === app && toggle.action == #selector(AppDelegate.changeDragOptions(_:)), "It sits on the View plate and keeps its action")
        // A small shot has nothing to offer: hidden, and the View plate is as narrow as it was without the box.
        app.window.contentView?.layoutSubtreeIfNeeded()
        try expect(!app.isLargeShot && toggle.isHidden, "A blank canvas hides the toggle")
        func plateWidth() -> CGFloat { app.window.contentView?.layoutSubtreeIfNeeded(); return chrome.surface(for: toggle)?.frame.width ?? 0 }
        let withoutBox = plateWidth()
        // A large shot shows it; a click flips it once, stores the choice and changes what a drag, export or upload sends.
        try viewportFixture(app)
        app.dragOriginalControl.state = .off; app.changeDragOptions(nil); app.updateViewportChrome()
        try expect(app.isLargeShot && !toggle.isHidden, "A large shot shows the toggle")
        try expect(abs(plateWidth() - withoutBox - chrome.originalSizeWidth) < 0.5, "The View plate widens by exactly the toggle's width (\(plateWidth() - withoutBox) vs \(chrome.originalSizeWidth))")
        toggle.performClick(nil)
        try expect(toggle.state == .on && toggle.isChosen && UserDefaults.standard.bool(forKey: "DragOriginalSize") && app.dragAtOriginalSize, "A click turns it on once: stored, and drag, export and upload use the picture's own pixels")
        try expect((toggle.accessibilityValue() as? NSNumber) == 1, "VoiceOver reads it on")
        _ = toggle.accessibilityPerformPress()
        try expect(toggle.state == .off && !UserDefaults.standard.bool(forKey: "DragOriginalSize") && !app.dragAtOriginalSize, "The accessibility press turns it back off and stores that")
        toggle.state = .on; app.changeDragOptions(nil)
        try expect(UserDefaults.standard.bool(forKey: "DragOriginalSize") && toggle.state == .on, "Setting the state and sending the action stores it (the path every other test and tool uses)")
        // Actual Size and Frame take it away again.
        app.toggleActualSize()
        try expect(toggle.isHidden, "Actual Size hides the toggle")
        app.leaveActualSize()
        try expect(!toggle.isHidden, "and leaving it brings the toggle back")
    }

    private static func modernZoomFace() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app, zoom = app.zoomControl
        app.setCanvasDisplayZoom(0.83, label: "Fit")
        try expect(zoom.titleOfSelectedItem == "83%" && zoom.selectedItem?.toolTip == "Fit, 83%" && (zoom.accessibilityValue() as? String) == "Fit, 83%",
                   "The face is the percentage; the mode word travels on the tooltip and the spoken value (\(zoom.titleOfSelectedItem ?? "nil"))")
        try expect(AppToolTip.text(for: zoom) == AppDelegate.zoomTooltip(spoken: "Fit, 83%") && AppToolTip.text(for: zoom)?.hasPrefix("Fit, 83%") == true && zoom.toolTip == nil, "The zoom face's app tooltip carries the live mode word and what the percentage is, with no system tooltip")
        app.setCanvasDisplayZoom(1, label: "Normal")
        try expect(zoom.titleOfSelectedItem == "100%" && (zoom.accessibilityValue() as? String) == "Normal, 100%", "Normal reads 100%")
        let index = try (zoom.itemArray.firstIndex { $0.title == "150%" }).unwrap("150% item")
        zoom.selectItem(at: index); app.changeZoom(zoom)
        try expect((zoom.accessibilityValue() as? String) == "150%" && abs(app.canvas.zoom - 1.5) < 0.001, "Picking a plain zoom speaks only its percentage, never the previous mode word")
        try expect(AppToolTip.text(for: zoom) == AppDelegate.zoomTooltip(spoken: nil) && !(AppToolTip.text(for: zoom) ?? "").contains("Fit"), "Picking a plain zoom clears the previous mode word and keeps the explanation")
        // The capsule is sized once for the widest face, so no title is ever clipped. The menu-only Actual Size command is never a face.
        let cell = try (zoom.superview as? ChromeFillCell).unwrap("zoom cell")
        for item in zoom.itemArray where item.tag != ZoomPopUpButton.actualSizeTag && !item.isSeparatorItem {
            let title = item.title
            zoom.select(item)
            try expect(zoom.fittingSize.width <= cell.frame.width + 0.5, "\(title) fits the zoom cell (\(zoom.fittingSize.width) in \(cell.frame.width))")
        }
        try expect((AppToolTip.text(for: zoom) ?? "").hasSuffix("one image pixel per screen pixel."), "Zoom keeps a tooltip that says what the percentage measures")
        // The cell is what the face needs: in the real footer, at the minimum window and at 1100, every face the zoom can show is drawn whole at 20 pt.
        let computed = NSMenuItem(title: "200%", action: nil, keyEquivalent: ""); computed.tag = ZoomPopUpButton.computedZoomTag
        for width in [ModernEditorChrome.minimumWindowWidth, 1100] as [CGFloat] {
            try resizeWindow(app, contentWidth: width)
            zoom.menu?.insertItem(computed, at: 0)
            defer { zoom.menu?.removeItem(computed); zoom.selectItem(withTitle: "100%") }
            for item in zoom.itemArray where item.tag != ZoomPopUpButton.actualSizeTag && !item.isSeparatorItem {
                zoom.select(item)
                app.window.contentView?.layoutSubtreeIfNeeded()
                let metrics = zoom.faceTextMetrics
                try expect(zoom.faceTextFits && metrics.font.pointSize == 20, "\(Int(width)): the zoom face \(item.title) is drawn whole at 20 pt: needs \(metrics.needed), the face draws it in \(metrics.available) (face \(zoom.frame.size))")
            }
        }
    }

    private static func modernBodyType() throws {
        let (fixture, _) = try modernFixture()
        let app = fixture.app
        let content = try (app.window.contentView).unwrap("content")
        let body = DesignTokens.Typography.font(.body).pointSize, caption = DesignTokens.Typography.font(.caption).pointSize
        let controls: [(String, NSControl)] = [("zoom popup", app.zoomControl), ("Original size checkbox", app.dragOriginalControl), ("Color button", app.paletteButton),
                                               ("Toolbox", try collect(NSPopUpButton.self, in: content).first { $0.accessibilityLabel() == "Toolbox" }.unwrap("Toolbox")), ("PNG | JPG", app.dragFormatToggle)]
        for (name, control) in controls {
            try expect(control.font?.pointSize == body && body == 20, "\(name) is body text, 20 pt (is \(control.font?.pointSize ?? 0))")
        }
        try expect(app.status.font?.pointSize == caption && caption == 18, "The status line is the 18 pt caption")
        try expect(app.zoomControl.menu?.font.pointSize == 20, "The zoom menu is 20 pt")
        for button in collect(NSButton.self, in: content) {
            try expect((button.font?.pointSize ?? 0) >= 18, "\(type(of: button)) '\(button.accessibilityLabel() ?? button.title)' keeps at least the readable floor")
        }
    }

    private static func modernAppToolTips() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let content = try (app.window.contentView).unwrap("content view")
        AppToolTip.install(on: content)
        var all: [NSView] = []
        func walk(_ view: NSView) { all.append(view); view.subviews.forEach(walk) }
        walk(content)
        let withText = all.filter { AppToolTip.text(for: $0) != nil }
        try expect(withText.count >= 20, "The chrome carries app tooltips on its controls (\(withText.count))")
        try expect(all.filter { $0.toolTip != nil }.isEmpty, "No view in the main window has a system tooltip: \(all.filter { $0.toolTip != nil }.map { "\(type(of: $0)) \($0.toolTip ?? "")" })")
        for view in withText where view !== app.status {
            let text = AppToolTip.text(for: view) ?? ""
            let help = view.accessibilityHelp() ?? ""
            try expect(help == text, "\(type(of: view)) '\(view.accessibilityLabel() ?? "")' keeps spoken help for its tooltip '\(text)'")
        }
        for view in [app.snapButton!, chrome.undoButton, chrome.hideButton, chrome.wipeButton, app.widthControl] as [NSView] {
            try expect(view.accessibilityHelp() == AppToolTip.text(for: view), "\(view.accessibilityLabel() ?? "") has accessibilityHelp equal to its former tooltip")
        }
        try expect(app.status.accessibilityHelp() == nil && (app.status.accessibilityValue() as? String) == AppToolTip.text(for: app.status),
                   "The status line speaks its full text as its value, so it is not repeated as help")
        for view in [app.snapButton!, chrome.undoButton, app.widthControl] as [NSView] {
            let anchor = AppToolTip.anchorRect(of: view, in: app.window)
            try expect(anchor.width < 200 && anchor.height < 100 && app.window.frame.insetBy(dx: -1, dy: -1).contains(anchor),
                       "The tooltip anchors on the control itself, not its window: \(view.accessibilityLabel() ?? "") \(anchor) in \(app.window.frame) (bounds \(view.bounds), visible \(view.visibleRect), window \(String(describing: view.window === app.window)))")
        }
        // The plate itself: 20 pt, and the dynamic Size text follows the control.
        let tip = AppToolTip.shared
        tip.dismiss(); tip.present = { _ in }; tip.reduceMotion = { true }
        tip.show(for: app.widthControl)
        try expect(tip.shownText == AppToolTip.text(for: app.widthControl) && (tip.label?.font?.pointSize ?? 0) >= 18 && tip.label?.font?.pointSize == 20,
                   "The Size tooltip is shown on an app plate at 20 pt (\(tip.shownText ?? "nil"))")
        app.canvas.strokeWidth = 12
        app.syncDrawingControls()
        try expect(tip.shownText == "Size 12", "The shown Size plate follows the control live (\(tip.shownText ?? "nil"))")
        tip.dismiss()
        // The hover-hint bevel replaces the tooltip on the controls it covers, and only while it is enabled.
        let brush = try app.toolButtons[.brush].unwrap("Brush")
        app.helpBevel?.enabled = true
        try expect(tip.suppressed(brush) && tip.suppressed(chrome.wipeButton) && !tip.suppressed(chrome.undoButton),
                   "With the hint bevel on, covered controls yield their tooltip and the rest keep it")
        app.helpBevel?.enabled = false
        try expect(!tip.suppressed(brush), "With the hint bevel off, tooltips show on every control")
    }

    private static func modernRelocatedOwnership() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let content = try (app.window.contentView).unwrap("content view")
        let routes: [(String, NSControl, Selector)] = [
            ("Color", app.paletteButton, #selector(AppDelegate.showDrawingColors(_:))), ("Size", app.widthControl, #selector(AppDelegate.changeWidth(_:))),
            ("Zoom", app.zoomControl, #selector(AppDelegate.changeZoom(_:))), ("Original size", app.dragOriginalControl, #selector(AppDelegate.changeDragOptions(_:))),
            ("PNG | JPG", app.dragFormatToggle, #selector(AppDelegate.changeDragOptions(_:))),
            ("Snap", chrome.snapButton, #selector(AppDelegate.snapButtonPressed)), ("Cancel", chrome.cancelFrameButton, #selector(AppDelegate.cancelFrame)),
            ("Font", chrome.fontButton, #selector(AppDelegate.chooseFont)), ("Undo", chrome.undoButton, #selector(AppDelegate.undo)), ("Wipe", chrome.wipeButton, #selector(AppDelegate.wipe)),
            ("Resize…", chrome.resizeButton, #selector(AppDelegate.resize)), ("Save", chrome.saveButton, #selector(AppDelegate.saveHistory)),
            ("History", chrome.historyButton, #selector(AppDelegate.showHistory)), ("Upload", chrome.shareButton, #selector(AppDelegate.share(_:)))
        ]
        for (name, control, action) in routes {
            try expect(control.target === app && control.action == action, "\(name) still sends its action to the AppDelegate after the move")
        }
        func minX(_ view: NSView) -> CGFloat { view.convert(view.bounds, to: content).minX }
        let toolbox = try collect(NSPopUpButton.self, in: content).first { $0.accessibilityLabel() == "Toolbox" }.unwrap("Toolbox")
        let tools = toolOrder.compactMap { app.toolButtons[SketchTool(rawValue: $0)!] as NSView? }
        let top: [NSView] = [chrome.hideButton, toolbox, chrome.photosButton, chrome.snapButton] + tools + [app.paletteButton, app.widthControl, chrome.fontButton]
        let topX = top.map(minX)
        try expect(topX == topX.sorted(), "The top bar reads Hide, Toolbox, Photos, Snap, ten tools, Color, Size, Font from left to right")
        let bottom: [NSView] = [chrome.undoButton, chrome.wipeButton, app.zoomControl, chrome.resizeButton, app.status, chrome.saveButton, chrome.historyButton,
                                app.dragFormatToggle, try (app.dragExportView).unwrap("drag"), chrome.shareButton]
        let bottomX = bottom.map(minX)
        try expect(bottomX == bottomX.sorted(), "The bottom bar reads Undo, Wipe, Zoom, Resize, status, Save, History, format, Drag, Upload from left to right")
        let canvasTop = chrome.scrollView.convert(chrome.scrollView.bounds, to: content).maxY, headerBottom = chrome.header.convert(chrome.header.bounds, to: content).minY
        try expect(canvasTop <= headerBottom, "The canvas sits between the two bars")
    }

    /// Renders the offscreen window (never ordered) to PNGs for a human to look at; asserts only that they are not blank.
    private static func modernLayoutBitmaps() throws {
        guard let folder = ProcessInfo.processInfo.environment["OPENSNAP_EVIDENCE_DIR"] else { return }
        let directory = URL(fileURLWithPath: folder).appendingPathComponent("t15-bitmaps")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        let content = try (app.window.contentView).unwrap("content view")
        func write(_ view: NSView, _ name: String) throws {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(description: "No bitmap for \(name)") }
            view.cacheDisplay(in: view.bounds, to: rep)
            var colours = Set<UInt32>()
            for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
                    let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                    colours.insert(UInt32((c?.redComponent ?? 0) * 255) << 16 | UInt32((c?.greenComponent ?? 0) * 255) << 8 | UInt32((c?.blueComponent ?? 0) * 255))
                }
            }
            try expect(colours.count > 8, "\(name) is not a blank bitmap (\(colours.count) distinct colours)")
            try (rep.representation(using: .png, properties: [:])).unwrap("PNG for \(name)").write(to: directory.appendingPathComponent(name + ".png"))
        }
        let minimum = app.window.minSize
        for (appearance, tag) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            app.window.appearance = NSAppearance(named: appearance)
            for (width, height, size) in [(minimum.width, minimum.height, "980"), (1280, 800, "1280")] {
                app.setWindowFrame(CGRect(origin: app.window.frame.origin, size: CGSize(width: width, height: height)))
                try viewportFixture(app)
                content.layoutSubtreeIfNeeded(); app.updateViewportChrome()
                try write(content, "normal-\(size)-\(tag)")
                try largeShot(app)
                app.setWindowFrame(CGRect(origin: app.window.frame.origin, size: CGSize(width: width, height: height)))
                app.updateDragPreview(); app.updateViewportChrome(); content.layoutSubtreeIfNeeded()
                try write(content, "largeshot-\(size)-\(tag)")
                try viewportFixture(app)
                app.enterFrame(keepingAnnotations: false, manualFlags: [])
                content.layoutSubtreeIfNeeded()
                try write(content, "frame-\(size)-\(tag)")
                app.cancelFrame()
            }
            let (host, _, remove) = try hostSizePopover(app)
            host.window.appearance = app.window.appearance
            try write(host.container, "size-popover-\(tag)")
            app.widthControl.dismissPopover(); remove()
        }
        app.window.appearance = nil
        _ = chrome
    }

    /// Audit fix 1 (items 6 and 7): the panel marks the current colour whether or not it is a preset, and its plates are even.
    private static func modernPaletteShowsActiveColor() throws {
        let (fixture, _) = try modernFixture()
        let app = fixture.app
        guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
        window.simulatesVisibility = true; window.shown = true
        defer { app.closeDrawingColors() }
        let custom = NSColor(deviceRed: 0.18, green: 0.62, blue: 0.55, alpha: 1)
        // A preset colour: its swatch carries the check, and the Custom color… row is the plain row.
        let red = OriginalDrawingControls.presets[0]
        app.applyChosenColor(red.color, modifiers: [])
        app.presentDrawingColors(hover: false)
        let row = try (app.customColorButton).unwrap("Custom color… row")
        try expect(app.presetColorButtons.filter { $0.state == .on }.map { $0.accessibilityLabel() ?? "" } == [red.name], "A preset colour checks exactly its own swatch (\(app.presetColorButtons.filter { $0.state == .on }.count))")
        try expect(!row.isChosen && row.leadingIconImage == nil && (row.accessibilityValue() as? NSNumber)?.intValue == 0, "...and the Custom color… row is the plain row")
        try expect(row.plate.style.fill == nil && row.plate.style.borderWidth == 0 && row.titleLabel.font?.pointSize == 20 && row.titleLabel.font != DesignTokens.Typography.font(.bodyStrong),
                   "...drawn with no fill, no border and the regular face")
        // A colour that is no preset: no swatch is checked, and the Custom color… row is chosen and carries the colour, a check and the selected look.
        app.applyChosenColor(custom, modifiers: [])
        try expect(app.presetColorButtons.allSatisfy { $0.state == .off }, "A custom colour checks no preset swatch")
        try expect(row.isChosen && row.leadingIconImage != nil && row.kind == .option && row.title == "Custom color…",
                   "The Custom color… row is the chosen option, carries the active colour and keeps its name")
        try expect((row.accessibilityValue() as? NSNumber)?.intValue == 1 && row.isAccessibilitySelected() && row.accessibilityRole() == .radioButton,
                   "VoiceOver hears the row as selected, still named Custom color…")
        try expect(row.plate.style.fill != nil && row.plate.style.borderWidth == 1 && row.titleLabel.font == DesignTokens.Typography.font(.bodyStrong),
                   "The chosen row has the selected fill, a 1 pt border and the semibold face: more than colour")
        // The chip really is that colour with a check on it.
        let chip = BezelCustomColorButton.chip(for: custom)
        func pixels(_ image: NSImage) throws -> NSBitmapImageRep { try (NSBitmapImageRep(data: try (image.tiffRepresentation).unwrap("chip bitmap"))).unwrap("chip rep") }
        for (label, image) in [("chip", chip), ("row", try row.leadingIconImage.unwrap("row image"))] {
            let rep = try pixels(image)
            func pixel(_ x: Double, _ y: Double) -> NSColor? { rep.colorAt(x: Int(x * Double(rep.pixelsWide)), y: Int(y * Double(rep.pixelsHigh)))?.usingColorSpace(.deviceRGB) }
            let corner = try pixel(0.2, 0.3).unwrap("\(label) pixel")
            try expect(abs(corner.redComponent - 0.18) < 0.06 && abs(corner.greenComponent - 0.62) < 0.06, "The \(label) is filled with the custom colour (\(corner))")
            let centre = try pixel(0.5, 0.5).unwrap("\(label) centre")
            try expect(abs(centre.redComponent - corner.redComponent) > 0.2 || abs(centre.greenComponent - corner.greenComponent) > 0.2 || abs(centre.blueComponent - corner.blueComponent) > 0.2,
                       "...with a check glyph drawn over its middle (\(centre))")
        }
        // Back to a preset: the mark moves home.
        app.applyChosenColor(OriginalDrawingControls.presets[2].color, modifiers: [])
        try expect(!row.isChosen && row.leadingIconImage == nil && app.presetColorButtons.filter { $0.state == .on }.count == 1, "Choosing a preset again clears the Custom color… mark")
        // Geometry (item 7): two plates of one width, the swatches centred in the first, the Custom row filling the second.
        guard let host = app.colorPanel else { throw Failure(description: "No colour panel") }
        host.window.contentView?.layoutSubtreeIfNeeded()
        let plates = host.plates
        try expect(plates.count == 2 && plates[0].frame.width == plates[1].frame.width && plates[0].frame.width == ColorPaletteContent.rowWidth + 8, "Two plates of one width (\(plates.map { $0.frame.width }))")
        let grid = plates[0].convert(app.presetColorButtons[0].bounds.insetBy(dx: 3, dy: 3), from: app.presetColorButtons[0])
        let lastColumn = plates[0].convert(app.presetColorButtons[4].bounds.insetBy(dx: 3, dy: 3), from: app.presetColorButtons[4])
        try expect(abs(grid.minX - (plates[0].bounds.width - lastColumn.maxX)) < 0.5, "The drawn swatches have equal left and right margins (\(grid.minX) and \(plates[0].bounds.width - lastColumn.maxX))")
        let title = plates[0].convert(app.presetColorButtons[0].bounds, from: app.presetColorButtons[0]).minX
        try expect(title >= 4 + ColorPaletteContent.horizontalPadding - 0.5, "The swatch grid starts inside the plate's padding (\(title))")
        let rowFrame = plates[1].convert(row.bounds, from: row)
        try expect(abs(rowFrame.minX - 4) < 0.5 && abs(plates[1].bounds.width - rowFrame.maxX - 4) < 0.5 && rowFrame.height == 36, "The Custom color… row fills its plate to the 4 pt inset and is 36 pt tall (\(rowFrame))")
        let rows = Set(app.presetColorButtons.map { $0.frame.minY })
        try expect(rows.count == 2 && abs((rows.max() ?? 0) - (rows.min() ?? 0) - 34) < 0.5, "The two swatch rows are evenly stacked (\(rows.sorted()))")
    }

    /// Audit fix 2: the glass panel has no pixel of its own to measure, so what is held is the text size, and the opaque fallback plates under
    /// Reduce Transparency, whose pixels are measured per appearance.
    private static func modernPalettePopoverContrast() throws {
        let (fixture, _) = try modernFixture()
        let app = fixture.app
        guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
        window.simulatesVisibility = true; window.shown = true
        defer { app.closeDrawingColors(); DisplayOptions.override = nil }
        for custom in [false, true] {
            app.applyChosenColor(custom ? NSColor(deviceRed: 0.18, green: 0.62, blue: 0.55, alpha: 1) : OriginalDrawingControls.presets[0].color, modifiers: [])
            app.presentDrawingColors(hover: false)
            guard let host = app.colorPanel else { throw Failure(description: "No colour panel") }
            host.window.contentView?.layoutSubtreeIfNeeded()
            let row = try (app.customColorButton).unwrap("Custom color… row")
            let sizes = textSizes(in: host.container)
            try expect(!sizes.isEmpty && sizes.allSatisfy { $0 >= 20 } && row.titleLabel.font?.pointSize ?? 0 >= 20, "All the panel's text is 20 pt or more (\(sizes))")
            // Reduce Transparency: each plate shows its opaque fallback, and the title and the row's text read on it in every appearance.
            DisplayOptions.override = DisplayOptions(reduceTransparency: true)
            host.accessibility = DisplayOptions.current.chrome
            host.window.contentView?.layoutSubtreeIfNeeded()
            for plate in host.plates { try expect(plate.transparencyPlate != nil, "Reduce Transparency gives each plate an opaque fallback") }
            let first = host.plates[0], second = host.plates[1]
            let title = try (first.arrangedViews.first?.subviews.compactMap { $0 as? NSTextField }.first).unwrap("Drawing colors title")
            for (name, appearance) in ContrastProbe.appearances {
                let label = "\(custom ? "custom" : "preset") colour, \(name)"
                let titleReading = ContrastProbe.measure(first, appearance: appearance, plateAt: NSPoint(x: first.bounds.width - 24, y: first.bounds.height - 22),
                                                         textFrames: [first.convert(title.bounds, from: title)])
                try expect(titleReading.plateOpaque, "The first plate draws an opaque fallback (\(label))")
                try expect(titleReading.textRatios[0] >= 4.5, "\"Drawing colors\" reads at 4.5:1 on its plate (\(label): \(titleReading.textRatios[0]))")
                let rowReading = ContrastProbe.measure(second, appearance: appearance, plateAt: NSPoint(x: second.bounds.width - 24, y: second.bounds.height / 2),
                                                       textFrames: [second.convert(row.titleLabel.bounds, from: row.titleLabel)])
                try expect(rowReading.plateOpaque, "The second plate draws an opaque fallback (\(label))")
                try expect(rowReading.textRatios[0] >= 4.5, "\"Custom color…\" reads at 4.5:1 on its plate (\(label): \(rowReading.textRatios[0]))")
            }
            DisplayOptions.override = nil
            app.closeDrawingColors()
        }
    }

    /// The point size of every piece of text a view tree can draw.
    private static func textSizes(in root: NSView) -> [CGFloat] {
        var sizes: [CGFloat] = []
        func walk(_ view: NSView) {
            if let field = view as? NSTextField, !field.stringValue.isEmpty { sizes.append(field.font?.pointSize ?? 0) }
            for child in view.subviews { walk(child) }
        }
        walk(root)
        return sizes
    }

    private static func modernPalettePopover() throws {
        let (fixture, chrome) = try modernFixture()
        let app = fixture.app
        guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
        window.simulatesVisibility = true; window.shown = true
        app.showDrawingColors(app.paletteButton)
        guard let host = app.colorPanel, host.isShown else { throw Failure(description: "The Modern Color panel did not open") }
        try expect(host.placement?.edge == .minY && host.anchor === app.paletteButton && app.paletteButton.isDescendant(of: chrome.header),
                   "Color sits in the top bar, so its panel opens below it (edge \(String(describing: host.placement?.edge)), frame \(String(describing: host.placement?.frame)), anchor \(String(describing: host.anchor)), inHeader \(app.paletteButton.isDescendant(of: chrome.header)))")
        try expect(host.alignment == .center && host.requestedKey, "It is centred under the control and takes the keyboard when opened on purpose")
        let control = window.convertToScreen(app.paletteButton.convert(app.paletteButton.bounds, to: nil))
        try expect(host.placement.map { $0.frame.maxY <= control.minY && abs($0.frame.midX - control.midX) < 1 } == true,
                   "The panel really hangs below the control and is centred on it (panel \(String(describing: host.placement?.frame)), control \(control))")
        try expect(host.window.appearance == nil && host.container.appearance == nil, "Modern leaves the panel on the system appearance")
        try expect(host.window.backgroundColor == .clear && !host.window.isOpaque, "The panel window is transparent: only the glass plates are drawn")
        host.window.contentView?.layoutSubtreeIfNeeded()
        var containers = 0, plates = 0, nested = 0
        func walk(_ view: NSView, insideGlass: Bool) {
            let isContainer = view is NSGlassEffectContainerView, isPlate = view is NSGlassEffectView
            if isContainer { containers += 1 }
            if isPlate { plates += 1 }
            if (isContainer || isPlate) && insideGlass { nested += 1 }
            for child in view.subviews { walk(child, insideGlass: insideGlass || isPlate) }
        }
        walk(host.container, insideGlass: false)
        try expect(containers == 1 && plates == 2 && nested == 0, "One glass container with two plates, and no glass inside glass (\(containers), \(plates), \(nested))")
        try expect(app.presetColorButtons.count == OriginalDrawingControls.presets.count, "The presets are all there")
        app.closeDrawingColors()
    }
}

private extension Optional {
    func unwrap(_ what: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing " + what) }
        return self
    }
}
#endif
