// Audit fix batch 3a: the defects the real-click E2E journey J1 found in the editor core (docs/design/e2e/findings.md, F-J1-001 to 026).
// Run through tools/test-app-safety.sh; no window or panel is ever put on screen. The canvas-only halves (eraser pixels, crop overlay, text
// re-layout) live in CanvasTests.swift.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var auditCases: [(String, () throws -> Void)] {
        [
            ("Custom color… opens the Colors panel at the current drawing colour and only changes made while it is open apply (F-J1-003)", auditCustomColor),
            ("A swatch is drawn in exactly the colour it applies, and the picked preset shows its check when the popover reopens (F-J1-002)", auditSwatchesMatchAppliedColour),
            ("Choosing a size for selected or editing text moves the glyphs and the frame together, in one undo step (F-J1-005)", auditTextSizeThroughSizeControl),
            ("Drawing > Shadow and Filled Shapes change only their own flag on the selection, plus the pen default, in one undo step (F-J1-006)", auditStyleTogglesChangeOnlyTheirFlag),
            ("Tab and Shift-Tab leave the canvas and walk the whole loop both ways; Control-Tab is the pencil swap (F-J1-007)", auditKeyboardTrap),
            ("With nowhere for Tab to go, the legacy Tab pencil swap stays (F-J1-007)", auditTabSwapWithoutFullKeyboardAccess),
            ("Window > Enter/Exit Full Screen exists as Control-Command-F and its title follows the window (F-J1-008)", auditFullScreenMenu),
            ("A pending crop says Return applies and Esc cancels, through the adaptive status variants (F-J1-011)", auditCropStatus),
            ("Minimize and the Hide button hide a visible editor even while the app is not active; the Hide tooltip names the real shortcut (F-J1-022)", auditMinimize),
            ("The Undo button and menu item are dimmed with nothing to undo and follow the history (F-J1-020)", auditUndoAvailability),
            ("Save to History wears an archive-box icon, not a floppy disk, and its neighbour keeps the clock (F-J1-021)", auditSaveIcon),
            ("The harness input fence swallows a real key press and click before they reach a capture window, and still lets the harness drive the canvas directly (R1-001)", auditHarnessInputFence)
        ]
    }

    private static func auditChrome(_ app: AppDelegate) throws -> ModernEditorChrome {
        guard let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        chrome.accessibility = .none
        return chrome
    }

    private static func auditShow(_ app: AppDelegate) {
        if let window = app.window as? AppSafetyWindow { window.simulatesVisibility = true; window.shown = true }
    }

    private static func auditView(_ root: NSView, where match: (NSView) -> Bool) -> NSView? {
        if match(root) { return root }
        for sub in root.subviews { if let hit = auditView(sub, where: match) { return hit } }
        return nil
    }

    // MARK: F-J1-003

    private static func auditCustomColor() throws {
        let fixture = try Fixture(), app = fixture.app
        let panel = AppSafetyColorPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        app.colorPanelProvider = { panel }
        let black = OriginalDrawingControls.presets[8].color
        app.applyChosenColor(black, modifiers: [])
        let before = SketchColor(app.canvas.strokeColor), background = app.canvas.document.backgroundColor
        // The Colors panel is shared and remembers whatever it showed last (the E2E found pure blue there).
        panel.sampleColor = NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1)
        app.chooseCustomColor(app.paletteButton)
        try expect(SketchColor(OriginalDrawingControls.drawingColor(from: panel.color)!) == before,
                   "The panel opens at the current drawing colour, not at what it showed last (\(panel.color))")
        try expect(SketchColor(app.canvas.strokeColor) == before, "Opening the panel applies nothing (\(SketchColor(app.canvas.strokeColor)))")
        // Closing it without choosing anything changes nothing either.
        panel.orderOut(nil)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: panel)
        try expect(SketchColor(app.canvas.strokeColor) == before && app.canvas.document.backgroundColor == background, "Closing the panel unchanged leaves the colour and the background alone")
        try expect(!app.customColorPanelOpen, "Closing the panel ends its conversation with the editor")
        // The shared panel is still told colours after it is closed (a text box pushes its own colour into it whenever it takes focus or changes
        // selection, which is what repainted text and changed the pen in the E2E): those echoes are not choices.
        panel.sampleColor = NSColor(calibratedRed: 1, green: 0.2, blue: 0.6, alpha: 1)
        app.changeCustomColor(panel)
        app.changeColor(panel)
        try expect(SketchColor(app.canvas.strokeColor) == before, "A colour pushed into the closed panel changes nothing (\(SketchColor(app.canvas.strokeColor)))")
        app.chooseCustomColor(app.paletteButton)
        // A change made while it is open does apply.
        let chosen = NSColor(calibratedRed: 0.17, green: 0.43, blue: 0.91, alpha: 1)
        panel.sampleColor = chosen
        app.changeCustomColor(panel)
        try expect(SketchColor(app.canvas.strokeColor) == SketchColor(OriginalDrawingControls.drawingColor(from: chosen)!), "A colour chosen in the open panel becomes the drawing colour")
        // Reopening shows that colour; still nothing is applied by opening.
        app.applyChosenColor(black, modifiers: [])
        panel.sampleColor = chosen
        app.chooseCustomColor(app.paletteButton)
        try expect(SketchColor(OriginalDrawingControls.drawingColor(from: panel.color)!) == SketchColor(black) && SketchColor(app.canvas.strokeColor) == SketchColor(black),
                   "Every opening starts from the colour in use")
    }

    // MARK: F-J1-002

    private static func auditSwatchesMatchAppliedColour() throws {
        let fixture = try Fixture(), app = fixture.app
        auditShow(app)
        defer { app.closeDrawingColors() }
        app.presentDrawingColors(hover: false)
        for (button, preset) in zip(app.presetColorButtons, OriginalDrawingControls.presets) {
            try expect(SketchColor(button.drawingColor) == SketchColor(preset.color),
                       "\(preset.name): the swatch is drawn in the colour it applies, not a calibrated twin (swatch \(SketchColor(button.drawingColor)), applied \(SketchColor(preset.color)))")
        }
        // The pixels agree too: after the pick the popover swatch and the toolbar swatch are the same colour on screen. Both are rendered the
        // way a window renders them (cacheDisplay of the live view), because converting the toolbar's image to a TIFF would not be that.
        let blue = OriginalDrawingControls.presets[2]
        guard let swatch = app.presetColorButtons.first(where: { $0.tag == blue.tag }) else { throw Failure(description: "Blue swatch") }
        swatch.frame = NSRect(x: 0, y: 0, width: 42, height: 32)
        func centre(_ view: NSView, _ x: Int, _ y: Int) throws -> NSColor {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(description: "bitmap") }
            view.cacheDisplay(in: view.bounds, to: rep)
            return try (rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)).unwrapped("pixel")
        }
        let drawn = try centre(swatch, 10, 10)
        app.choosePresetColor(swatch)
        let image = try app.paletteButton.image.unwrapped("toolbar swatch image")
        let holder = NSImageView(frame: NSRect(origin: .zero, size: image.size)); holder.image = image; holder.imageScaling = .scaleNone
        let toolbar = try centre(holder, Int(image.size.width / 2), Int(image.size.height / 2))
        try expect(abs(drawn.redComponent - toolbar.redComponent) < 0.02 && abs(drawn.greenComponent - toolbar.greenComponent) < 0.02 && abs(drawn.blueComponent - toolbar.blueComponent) < 0.02,
                   "The Blue swatch pixel (\(drawn)) is the toolbar swatch's Blue pixel (\(toolbar))")
        // Reopening after the pick: Blue, and only Blue, is marked, with the check drawn.
        app.presentDrawingColors(hover: false)
        let marked = app.presetColorButtons.filter { $0.state == .on }
        try expect(marked.map(\.tag) == [blue.tag] && app.customColorButton?.isCurrentChoice == false, "Blue is the one marked preset after picking it (\(marked.map(\.tag)))")
        guard let again = marked.first else { throw Failure(description: "marked swatch") }
        again.frame = NSRect(x: 0, y: 0, width: 42, height: 32)
        try expect(again.controlState == .selected && again.swatchStyle.check, "and it draws as selected, with its check")
        let others = app.presetColorButtons.filter { $0 !== again }.allSatisfy { $0.controlState != .selected }
        try expect(others, "No other swatch is drawn selected")
    }

    // MARK: F-J1-005

    private static func auditTextSizeThroughSizeControl() throws {
        let colour = NSColor(deviceRed: 1, green: 0, blue: 1, alpha: 1)
        func ink(_ rep: NSBitmapImageRep, _ target: NSColor) -> CGRect {
            let t = target.usingColorSpace(.deviceRGB)!
            var box = CGRect.null
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.9 else { continue }
                if abs(c.redComponent - t.redComponent) < 0.05 && abs(c.greenComponent - t.greenComponent) < 0.05 && abs(c.blueComponent - t.blueComponent) < 0.05 {
                    box = box.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            } }
            return box
        }
        /// The glyphs on screen and the document the export renders must be the same size, and the element must carry the size last chosen.
        func verify(_ app: AppDelegate, _ name: String, colour target: NSColor) throws {
            let text = try app.canvas.document.elements.first { $0.kind == .text }.unwrapped("\(name): text element")
            try expect(text.rect.size == OriginalTextGeometry.size(for: text), "\(name): the frame is the natural size of the text at \(text.fontSize) pt (\(text.rect.size))")
            let exported = try SketchRenderer.bitmap(document: app.canvas.document).map { ink($0, target) }.unwrapped("\(name): export ink")
            let onScreen = try SketchRenderer.bitmap(size: app.canvas.bounds.size) { app.canvas.draw(app.canvas.bounds) }.map { ink($0, target) }.unwrapped("\(name): screen ink")
            try expect(!exported.isNull && abs(onScreen.height - exported.height) <= 2 && abs(onScreen.width - exported.width) <= 2,
                       "\(name): the glyphs on screen match the document at \(text.fontSize) pt: screen \(onScreen.size), exported \(exported.size)")
        }
        func fresh() throws -> (Fixture, AppDelegate) {
            let fixture = try Fixture(), app = fixture.app
            app.canvas.newBlank(size: NSSize(width: 800, height: 400)); app.canvas.editingUndoManager.removeAllActions()
            app.applyChosenColor(colour, modifiers: [])
            app.widthControl.performValueChange(OriginalDrawingControls.minimum, continuous: true)
            return (fixture, app)
        }
        // 1. Editing, then committed, then selected and resized (the E2E order).
        do {
            let (fixture, app) = try fresh(); _ = fixture
            let editor = try editor(app, text: "Hello OpenSnap")
            let scale = app.canvas.displayScale.height
            app.widthControl.performValueChange(OriginalDrawingControls.maximum, continuous: true)
            let live = try SketchDocument.decode(app.canvas.snapshotDocumentData()).elements[0]
            try expect(live.fontSize > 24, "The Size control raised the text size (\(live.fontSize))")
            try expect(abs((editor.font?.pointSize ?? 0) - max(18, live.fontSize * scale)) < 0.5,
                       "While editing, the glyphs follow the size: the editor shows \(editor.font?.pointSize ?? 0) for a \(live.fontSize) pt element")
            app.canvas.commitPendingTextEditing()
            try verify(app, "editing, then committed", colour: colour)
            app.canvas.tool = .select; app.canvas.selection = [app.canvas.document.elements[0].id]
            app.widthControl.performValueChange(OriginalDrawingControls.minimum + 3, continuous: true)
            try verify(app, "selected after commit", colour: colour)
            app.canvas.duplicateSelection()
            let sizes = app.canvas.document.elements.filter { $0.kind == .text }.map(\.fontSize)
            try expect(sizes.count == 2 && sizes[0] == sizes[1], "Duplicate is the same size as the original (\(sizes))")
        }
        // 2. A colour change and a first size while the box is still open, then a second size on the committed text.
        do {
            let (fixture, app) = try fresh(); _ = fixture
            _ = try editor(app, text: "Hello OpenSnap")
            let cyan = NSColor(deviceRed: 0, green: 1, blue: 1, alpha: 1)
            app.applyChosenColor(cyan, modifiers: [])
            app.widthControl.performValueChange(OriginalDrawingControls.sizeSteps[1], continuous: false)
            app.widthControl.performValueChange(OriginalDrawingControls.maximum, continuous: false)
            app.canvas.commitPendingTextEditing()
            try verify(app, "colour then two sizes while editing", colour: cyan)
            app.canvas.selection = [app.canvas.document.elements[0].id]
            app.widthControl.performValueChange(OriginalDrawingControls.sizeSteps[2], continuous: false)
            try verify(app, "then resized once committed", colour: cyan)
        }
        // 3. The Size popover keeps one undo group open across several presets, as it does while it is on screen.
        do {
            let (fixture, app) = try fresh(); _ = fixture
            _ = try editor(app, text: "Hello OpenSnap")
            app.canvas.commitPendingTextEditing()
            app.canvas.tool = .select; app.canvas.selection = [app.canvas.document.elements[0].id]
            try expect(app.widthControl.beginGesture(), "The pill opens a gesture")
            for fraction in [CGFloat(1), 0.75, 0.25, 1] {
                app.widthControl.trackValue(fraction: fraction, modifiers: [])
                try verify(app, "preset at \(fraction) inside one open gesture", colour: colour)
            }
            app.widthControl.endTracking()
            try expect(app.canvas.editingUndoManager.canUndo, "The gesture is undoable")
            app.undo()
            try expect(app.canvas.document.elements[0].fontSize == 18 || app.canvas.document.elements[0].fontSize < 30, "One Undo undoes the whole gesture (\(app.canvas.document.elements[0].fontSize))")
            try verify(app, "after the one Undo", colour: colour)
        }
    }

    // MARK: F-J1-006

    private static func auditStyleTogglesChangeOnlyTheirFlag() throws {
        let fixture = try Fixture(), app = fixture.app
        let canvas = app.canvas
        canvas.newBlank(size: NSSize(width: 400, height: 300)); canvas.editingUndoManager.removeAllActions()
        var box = SketchElement(kind: .rectangle); box.rect = CGRect(x: 20, y: 20, width: 100, height: 60)
        box.color = SketchColor(.red); box.strokeWidth = 3; box.filled = true; box.shadowed = true
        var ring = SketchElement(kind: .ellipse); ring.rect = CGRect(x: 160, y: 20, width: 100, height: 60)
        ring.color = SketchColor(.systemGreen); ring.strokeWidth = 5; ring.filled = false; ring.shadowed = true
        var line = SketchElement(kind: .line); line.points = [CGPoint(x: 20, y: 150), CGPoint(x: 200, y: 200)]
        line.color = SketchColor(.systemOrange); line.strokeWidth = 8; line.shadowed = true
        var raster = SketchElement(kind: .raster); raster.rect = CGRect(x: 250, y: 150, width: 20, height: 20); raster.imagePNG = Data([1]); raster.shadowed = true
        canvas.document.elements = [box, ring, line, raster]
        // The pen differs from every element, as in the E2E: blue, thick, unfilled.
        canvas.strokeColor = .blue; canvas.strokeWidth = 9; canvas.filled = false; canvas.shadowed = true
        canvas.selectAll()
        let item = NSMenuItem()
        app.toggleBezelShadow(item)
        let after = canvas.document.elements
        try expect(!canvas.shadowed, "The pen default toggled")
        for (old, new) in zip([box, ring, line, raster], after) {
            var expected = old; if old.kind != .raster { expected.shadowed = false }
            try expect(new == expected, "\(old.kind): Shadow changed the shadow flag and nothing else (colour \(new.color == old.color), width \(new.strokeWidth == old.strokeWidth), fill \(new.filled == old.filled), shadow \(new.shadowed))")
        }
        try expect(after[0...2].allSatisfy { !$0.shadowed }, "The selected shapes lost their shadow")
        canvas.undo()
        try expect(canvas.document.elements == [box, ring, line, raster], "One Undo restores the whole selection")
        canvas.redo()
        try expect(canvas.document.elements.map(\.color) == [box, ring, line, raster].map(\.color), "Redo repeats the same flag change")
        canvas.undo(); canvas.shadowed = false
        // Filled Shapes is the same kind of toggle: it must not repaint the selection in the pen colour either.
        canvas.selectAll()
        app.toggleBezelFill(item)
        let filled = canvas.document.elements
        try expect(canvas.filled && filled[0...2].map(\.color) == [box, ring, line].map(\.color) && filled[0...2].map(\.strokeWidth) == [box, ring, line].map(\.strokeWidth),
                   "Filled Shapes leaves colour and width alone")
        try expect(filled[1].filled && filled[0].filled && filled[0...2].map(\.shadowed) == [true, true, true], "and only sets the fill (the ellipse is filled, shadows untouched)")
    }

    // MARK: F-J1-007

    private static func auditTab(_ flags: NSEvent.ModifierFlags = [], app: AppDelegate) throws -> NSEvent {
        try NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: app.window.windowNumber, context: nil,
                             characters: flags.contains(.shift) ? "\u{19}" : "\t", charactersIgnoringModifiers: flags.contains(.shift) ? "\u{19}" : "\t", isARepeat: false, keyCode: 48).unwrapped("tab event")
    }

    /// One Tab or Shift-Tab press as AppKit routes it: to the first responder's keyDown; a control that has no use for the key hands it to the window.
    private static func auditPress(_ flags: NSEvent.ModifierFlags = [], app: AppDelegate) throws {
        let event = try auditTab(flags, app: app)
        if app.window.firstResponder === app.canvas { app.canvas.keyDown(with: event) }
        else if flags.contains(.shift) { app.window.selectPreviousKeyView(nil) }
        else { app.window.selectNextKeyView(nil) }
    }

    private static func auditKeyboardTrap() throws {
        let saved = KeyboardNavigation.fullKeyboardAccess
        KeyboardNavigation.fullKeyboardAccess = { true }
        defer { KeyboardNavigation.fullKeyboardAccess = saved; KeyboardNavigation.toolbarFocusActive = false }
        let fixture = try Fixture(), app = fixture.app
        let chrome = try auditChrome(app)
        auditShow(app)
        app.window.setFrame(CGRect(origin: app.window.frame.origin, size: CGSize(width: 1280, height: 760)), display: false)
        app.window.contentView?.layoutSubtreeIfNeeded(); app.window.recalculateKeyViewLoop()
        // A blank document dims Undo and Wipe, which takes them out of the loop; give it something to undo.
        app.canvas.newBlank(size: NSSize(width: 400, height: 300))
        var box = SketchElement(kind: .rectangle); box.rect = CGRect(x: 20, y: 20, width: 60, height: 40)
        app.canvas.document.elements = [box]; app.canvas.setBackgroundColor(.white); app.updateWipeButton()
        try expect(chrome.undoButton.isEnabled && chrome.wipeButton.isEnabled, "The fixture drawing has something to undo and to clear")
        app.window.contentView?.layoutSubtreeIfNeeded(); app.window.recalculateKeyViewLoop()
        app.setTool(.arrow)
        app.window.makeFirstResponder(app.canvas)
        func label(_ responder: NSResponder?) -> String {
            guard let view = responder as? NSView else { return "none" }
            return view === app.canvas ? "canvas" : (view.accessibilityLabel() ?? String(describing: type(of: view)))
        }
        // Forward: from the canvas Tab must reach the bottom bar, in reading order, and come round to Hide and on to the top bar again.
        var forward: [NSResponder?] = []
        for _ in 0..<60 {
            try auditPress(app: app)
            forward.append(app.window.firstResponder)
            if app.window.firstResponder === app.canvas { break }
        }
        try expect(forward.last.flatMap { $0 } === app.canvas, "Tab walks all the way round back to the canvas (\(forward.map(label)))")
        try expect(app.canvas.tool == .arrow, "Tab no longer swaps the tool while it can move the keyboard (\(app.canvas.tool))")
        let order: [(String, NSView)] = [("Undo", chrome.undoButton), ("Wipe", chrome.wipeButton), ("Zoom", app.zoomControl), ("Resize", chrome.resizeButton),
                                         ("Save", chrome.saveButton), ("History", chrome.historyButton), ("Upload", chrome.shareButton)]
        func position(_ view: NSView) -> Int { forward.firstIndex { $0 === view } ?? -1 }
        for (name, view) in order { try expect(position(view) >= 0, "Tab from the canvas reaches \(name) (\(forward.map(label)))") }
        let positions = order.map { position($0.1) }
        try expect(positions == positions.sorted(), "The bottom bar is walked left to right (\(positions))")
        try expect(position(chrome.hideButton) > position(chrome.shareButton) && position(chrome.hideButton) >= 0, "The loop returns to Hide after the last bottom-bar control (\(forward.map(label)))")
        try expect(position(chrome.fontButton) > position(chrome.hideButton), "and continues through the top bar to Font before the canvas")
        // Backward: Shift-Tab from the canvas goes through the same stops in reverse.
        app.window.makeFirstResponder(app.canvas)
        var backward: [NSResponder?] = []
        for _ in 0..<60 {
            try auditPress(.shift, app: app)
            backward.append(app.window.firstResponder)
            if app.window.firstResponder === app.canvas { break }
        }
        try expect(backward.last.flatMap { $0 } === app.canvas, "Shift-Tab walks all the way round too (\(backward.map(label)))")
        try expect(backward.map(label) == Array(forward.map(label).dropLast().reversed()) + ["canvas"],
                   "Shift-Tab visits the same stops as Tab, in reverse (\(backward.map(label)) vs \(forward.map(label)))")
        try expect(app.canvas.tool == .arrow, "Shift-Tab leaves the tool alone")
        // Control-Tab is the pencil swap, and keeps the keyboard on the canvas.
        app.window.makeFirstResponder(app.canvas)
        app.canvas.keyDown(with: try auditTab(.control, app: app))
        try expect(app.canvas.tool == .brush && app.window.firstResponder === app.canvas, "Control-Tab swaps to the pencil and stays on the canvas")
        app.canvas.keyDown(with: try auditTab(.control, app: app))
        try expect(app.canvas.tool == .arrow && app.window.firstResponder === app.canvas, "and back")
    }

    private static func auditTabSwapWithoutFullKeyboardAccess() throws {
        let saved = KeyboardNavigation.fullKeyboardAccess
        KeyboardNavigation.fullKeyboardAccess = { KeyboardNavigation.toolbarFocusActive }   // the system setting is off; Focus Toolbar still counts
        defer { KeyboardNavigation.fullKeyboardAccess = saved; KeyboardNavigation.toolbarFocusActive = false }
        let fixture = try Fixture(), app = fixture.app
        _ = try auditChrome(app)
        auditShow(app)
        app.window.contentView?.layoutSubtreeIfNeeded(); app.window.recalculateKeyViewLoop()
        app.setTool(.arrow); app.window.makeFirstResponder(app.canvas)
        app.canvas.keyDown(with: try auditTab(app: app))
        try expect(app.canvas.tool == .brush && app.window.firstResponder === app.canvas, "With Full Keyboard Access off the bars are not tab stops, so Tab keeps swapping to the pencil")
        app.canvas.keyDown(with: try auditTab(app: app))
        try expect(app.canvas.tool == .arrow, "and back")
        // Focus Toolbar turns the bars into tab stops, so Tab walks again until the window stops being key.
        app.focusToolbar()
        try expect(KeyboardNavigation.toolbarFocusActive, "Focus Toolbar asks for the keyboard on the bars")
        app.window.makeFirstResponder(app.canvas)
        app.canvas.keyDown(with: try auditTab(app: app))
        try expect(app.canvas.tool == .arrow && app.window.firstResponder !== app.canvas, "While the bars are live Tab leaves the canvas instead of swapping")
    }

    // MARK: F-J1-008

    private static func auditFullScreenMenu() throws {
        let fixture = try Fixture(), app = fixture.app
        guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
        let windowMenu = try NSApp.mainMenu.unwrapped("main menu").items.compactMap(\.submenu).first { $0.title == "Window" }.unwrapped("Window menu")
        let item = try windowMenu.items.first { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }.unwrapped("Window > Enter Full Screen")
        try expect(item.keyEquivalent == "f" && item.keyEquivalentModifierMask == [.command, .control], "Full Screen is Control-Command-F, the system shortcut")
        window.simulatesVisibility = true; window.shown = true
        defer { app.keyWindowProvider = { NSApp.keyWindow }; window.simulatesVisibility = false; window.simulatedSheet = nil }
        app.keyWindowProvider = { window }
        window.simulatesFullScreen = false
        try expect(app.validateMenuItem(item) && item.title == "Enter Full Screen", "Windowed, the item reads Enter Full Screen (\(item.title))")
        window.simulatesFullScreen = true
        try expect(app.validateMenuItem(item) && item.title == "Exit Full Screen", "In full screen it reads Exit Full Screen (\(item.title))")
        window.simulatesFullScreen = false
        // R1-020: Full Screen acts on the editor only while the editor is on screen, free of sheets, and the window the keys go to.
        let other = AppSafetyWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        try expect(app.validateMenuItem(item) && app.editorCanToggleFullScreen, "With the editor visible and key, Full Screen is available")
        app.keyWindowProvider = { other }
        try expect(!app.validateMenuItem(item) && !app.editorCanToggleFullScreen, "With History or Settings key, ⌃⌘F does not reach into the editor")
        window.simulatesFullScreen = true
        try expect(!app.validateMenuItem(item), "…not even to leave full screen from another window")
        window.simulatesFullScreen = false
        app.keyWindowProvider = { window }
        window.shown = false
        try expect(!app.validateMenuItem(item), "A hidden editor is not toggled")
        window.shown = true
        window.simulatedSheet = AppSafetyWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        try expect(!app.validateMenuItem(item), "With a sheet attached (Save your drawing?) it waits")
        window.simulatedSheet = nil
        try expect(app.validateMenuItem(item), "and is available again once the sheet is gone")
        // The item's own target is the app, and the action it sends reaches the window only when the editor may toggle.
        try expect(item.target === app, "The item is answered by the app itself, not by whatever is first in the responder chain")
        window.fullScreenToggles = 0
        try expect(NSApp.sendAction(try item.action.unwrapped("action"), to: item.target, from: item) && window.fullScreenToggles == 1, "Choosing it with the editor key asks the editor window to toggle (\(window.fullScreenToggles))")
        app.keyWindowProvider = { other }
        app.toggleFullScreen(item)
        try expect(window.fullScreenToggles == 1, "The same command with History key reaches no window, even called straight (\(window.fullScreenToggles))")
        window.shown = false; app.keyWindowProvider = { window }
        app.toggleFullScreen(item)
        try expect(window.fullScreenToggles == 1, "…nor a hidden editor")
    }

    // MARK: F-J1-011

    private static func auditCropStatus() throws {
        let fixture = try Fixture(), app = fixture.app
        let hint = "Crop: press Return to apply, Esc to cancel"
        app.canvas.newBlank(size: NSSize(width: 400, height: 300))
        app.setTool(.crop)
        try expect(app.status.variants.first?.hasPrefix("Crop · ") == true && !app.status.variants.contains(hint), "Before a crop is dragged the status is the plain tool line (\(app.status.variants))")
        app.canvas.cropRect = CGRect(x: 20, y: 20, width: 200, height: 120)
        try expect(app.status.variants.first == hint && app.status.stringValue == hint, "A pending crop says what Return and Esc do (\(app.status.variants))")
        try expect(app.status.variants.count >= 3 && (app.status.variants.last == "Unsaved changes" || app.status.variants.last == "Saved"), "Narrow windows still get shorter variants, ending at the saved state (\(app.status.variants))")
        try expect(AppToolTip.text(for: app.status) == hint, "The full sentence is the tooltip")
        app.setTool(.brush)
        try expect(app.canvas.cropRect == nil && !app.status.variants.contains(hint) && app.status.variants.first?.hasPrefix("Brush · ") == true, "Changing tool clears the crop and its hint (\(app.status.variants))")
    }

    // MARK: F-J1-022

    private static func auditMinimize() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try auditChrome(app)
        auditShow(app)
        guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
        let windowMenu = try NSApp.mainMenu.unwrapped("main menu").items.compactMap(\.submenu).first { $0.title == "Window" }.unwrapped("Window menu")
        let minimize = try windowMenu.items.first { $0.title == "Minimize" }.unwrapped("Window > Minimize")
        try expect(minimize.action == #selector(AppDelegate.vanish) && minimize.target === app && minimize.keyEquivalent == "m" && minimize.keyEquivalentModifierMask == [.command],
                   "Minimize is Command-M and goes to vanish on the app")
        try expect(app.validateMenuItem(minimize), "and it is enabled")
        try expect(AppToolTip.text(for: chrome.hideButton) == "Hide (⌘M)" && chrome.hideButton.action == #selector(AppDelegate.vanish), "The Hide button runs the same action and its tooltip names the shortcut that really does it")
        // Inactive app, visible editor (for example a key equivalent arriving while another app is still frontmost): Minimize hides, it never raises.
        AppSafetyActivation.isActive = false
        defer { AppSafetyActivation.isActive = true }
        _ = NSApp.sendAction(try minimize.action.unwrapped("action"), to: minimize.target, from: minimize)
        try expect(!window.isVisible, "Minimize hides the visible editor even while the app is not active")
        app.makeVisible()
        try expect(window.isVisible, "and it can be shown again")
        // The Hide-Others-style toggle keeps its own rule: inactive means bring it forward.
        app.toggleVisible()
        try expect(window.isVisible, "Hide OpenSnap (the toggle) still raises an inactive editor instead of hiding it")
    }

    // MARK: F-J1-020

    private static func auditUndoAvailability() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try auditChrome(app)
        let editMenu = try NSApp.mainMenu.unwrapped("main menu").items.compactMap(\.submenu).first { $0.title == "Edit" }.unwrapped("Edit menu")
        let undoItem = try editMenu.items.first { $0.action == #selector(AppDelegate.undo) }.unwrapped("Edit > Undo")
        app.canvas.newBlank(size: NSSize(width: 200, height: 150)); app.canvas.editingUndoManager.removeAllActions()
        app.updateWipeButton()
        try expect(!chrome.undoButton.isEnabled && !app.validateMenuItem(undoItem), "A blank document has nothing to undo: the button and the menu item are dimmed")
        app.canvas.setBackgroundColor(.blue)
        try expect(chrome.undoButton.isEnabled && app.validateMenuItem(undoItem), "A change enables both")
        app.undo()
        try expect(!chrome.undoButton.isEnabled && !app.validateMenuItem(undoItem), "Undoing the only change dims them again")
        app.redo()
        try expect(chrome.undoButton.isEnabled, "Redo brings the history back")
        app.canvas.newBlank(size: NSSize(width: 200, height: 150)); app.canvas.editingUndoManager.removeAllActions(); app.updateWipeButton()
        try expect(!chrome.undoButton.isEnabled, "A new blank drawing starts with Undo dimmed")
        // Typing in a text box has its own history, which Undo steps first.
        let editor = try editor(app, text: "typing")
        try expect(editor.undoManager?.canUndo == true && chrome.undoButton.isEnabled, "Typing makes Undo available")
    }

    // MARK: R1-001

    /// A real key or mouse event is dispatched through `NSApp.sendEvent`; the harness never is. The baseline half proves the probe really
    /// sees a delivered event, so the fenced half cannot pass merely because nothing could ever arrive.
    private static func auditHarnessInputFence() throws {
        let fixture = try Fixture(), app = fixture.app
        var menuFired = 0
        final class Probe: NSObject { var fired: () -> Void = {}; @objc func hit(_ sender: Any?) { fired() } }
        let probe = Probe(); probe.fired = { menuFired += 1 }
        let item = NSMenuItem(title: "Probe", action: #selector(Probe.hit(_:)), keyEquivalent: "j")
        item.keyEquivalentModifierMask = [.command]; item.target = probe
        let menu = NSMenu(title: "Main"), top = NSMenuItem(), sub = NSMenu(title: "Probe")
        sub.addItem(item); top.submenu = sub; menu.addItem(top)
        let savedMenu = NSApp.mainMenu
        NSApp.mainMenu = menu
        defer { NSApp.mainMenu = savedMenu }
        func realKey() -> NSEvent? {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                             characters: "j", charactersIgnoringModifiers: "j", isARepeat: false, keyCode: 38)
        }
        func realClick() -> NSEvent? {
            NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
        }
        guard let key = realKey(), let click = realClick() else { throw Failure(description: "Could not build the synthetic real events") }
        NSApp.sendEvent(key)
        try expect(menuFired == 1, "Baseline: without the fence a real key equivalent reaches the app (\(menuFired)); the probe works")

        let before = HarnessInputGuard.swallowedCount
        let token = HarnessInputGuard.install()
        defer { HarnessInputGuard.remove(token) }
        NSApp.sendEvent(key)
        NSApp.sendEvent(click)
        try expect(menuFired == 1, "With the fence a real key equivalent never reaches the app (\(menuFired))")
        try expect(HarnessInputGuard.swallowedCount == before + 2, "Both the key press and the click were swallowed and counted (\(HarnessInputGuard.swallowedCount - before))")
        for type: NSEvent.EventType in [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
                                        .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved, .scrollWheel] {
            try expect(HarnessInputGuard.blockedEvents.contains(NSEvent.EventTypeMask(rawValue: 1 << UInt64(type.rawValue))), "\(type) is fenced")
        }

        // The harness calls responders directly, which never passes through sendEvent, so the fence leaves it alone.
        var reached = 0
        app.canvas.onHintModifiers = { _ in reached += 1 }
        if let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                                        characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49) {
            app.canvas.keyDown(with: space)
        }
        try expect(reached == 1, "A direct harness-style keyDown still reaches the canvas while the fence is up (\(reached))")
    }

    // MARK: F-J1-021

    private static func auditSaveIcon() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try auditChrome(app)
        try expect(chrome.saveButton.icon == .boxArchive, "Save to History uses the archive box, which reads as filing a copy away (\(String(describing: chrome.saveButton.icon)))")
        try expect(chrome.historyButton.icon == .clockRotateLeft, "History keeps the clock, so the neighbours read as archive and browse")
        try expect(chrome.saveButton.icon != chrome.historyButton.icon, "the two neighbours never share a glyph")
        try expect(chrome.saveButton.accessibilityLabel() == "Save" && AppToolTip.text(for: chrome.saveButton) == "Save to History", "The names are unchanged: Save, with the tooltip Save to History")
    }
}

private extension Optional {
    func unwrapped(_ what: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing " + what) }
        return self
    }
}
#endif
