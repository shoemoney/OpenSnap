// OSN-062 WP1b: the surfaces of the real app that WP1a did not script. Every one is walked by the accessibility audit (G10 + the tracked kinds),
// read as a spoken script (build/spoken/<slug>.md) and checked for a well-formed tree. A real finding is NOT silenced here: it is a line in
// tools/accessibility-baseline.tsv marked "pending WP3", the explicit burn-down list. Windows and panels are built, never ordered on screen.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var accessibilitySurfaceCases: [(String, () throws -> Void)] {
        [
            ("WP1b: the editor with annotations, a selection, text being edited and Frame mode (with and without kept drawing) is walked and scripted", surfaceEditorStates),
            ("WP1b: the Actual Size overview panel, the Frame full-screen prompt and the top and bottom bars are walked and scripted", surfaceEditorParts),
            ("WP1b: the real Size, Color, Upload destinations and Zoom panels are walked and scripted", surfacePanels),
            ("WP1b: the permission alert, the status-item button and the Upload menu are walked and scripted", surfaceSmall),
            ("WP1b: the countdown numeral and the capture picker overlay are walked and scripted", surfaceCapture),
            ("WP1b: the canvas value summarises its annotations (No annotations, 3 annotations: arrow, rectangle, text \"hello\"); pending WP3", surfaceCanvasValue),
        ]
    }

    // MARK: Helpers

    private static func surfaceChrome(_ app: AppDelegate) throws -> ModernEditorChrome {
        guard let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        chrome.accessibility = .none
        return chrome
    }

    private static func surfaceViews(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(surfaceViews) }

    /// Walks one surface. A violation the baseline does not cover fails, and so does a tree that is not well formed for an external client.
    @discardableResult
    private static func walked(_ surface: String, expecting expected: [AccessibilityAudit.Kind] = [], isSubtree: Bool = false, _ audit: (String) -> AccessibilityAudit.Report, tree: () -> AXTree.Tree) throws -> AccessibilityAudit.Report {
        let report = audit(surface)
        let kinds = report.violations.map(\.kind)
        try expect(kinds == expected, "\(surface): expected violations \(expected.map(\.rawValue)), got \(kinds.map(\.rawValue)):\n\(report.description)")
        let tree = tree()
        // A window that exposes no element must be explained by a finding (the capture picker overlay: focusable, nameless, not an element).
        try expect(!tree.nodes.isEmpty || !report.trackedFindings.isEmpty, "\(surface): the walker saw no element and found nothing wrong, so a clean result would prove nothing")
        // A subtree is handed to the walker as its own root, which is a plain container; only the window's list of roots is judged for that.
        let shape = tree.shapeProblems().filter { !(isSubtree && $0.hasPrefix("the window lists")) }
        try expect(shape.isEmpty, "\(surface): the tree is malformed: \(shape)")
        try expect(tree.parentProblems().isEmpty, "\(surface): children and parents disagree: \(tree.parentProblems())")
        return report
    }

    @discardableResult
    private static func walkedWindow(_ window: NSWindow, _ surface: String, expecting expected: [AccessibilityAudit.Kind] = []) throws -> AccessibilityAudit.Report {
        window.contentView?.layoutSubtreeIfNeeded()
        return try walked(surface, expecting: expected, { AccessibilityAudit.audit(window, surface: $0) }, tree: { AXTree.walk(window) })
    }

    @discardableResult
    private static func walkedView(_ view: NSView, _ surface: String, expecting expected: [AccessibilityAudit.Kind] = []) throws -> AccessibilityAudit.Report {
        view.layoutSubtreeIfNeeded()
        return try walked(surface, expecting: expected, isSubtree: true, { AccessibilityAudit.audit(view, surface: $0) }, tree: { AXTree.walk(view) })
    }

    private static func canvasMouse(_ canvas: CanvasView, _ type: NSEvent.EventType, _ point: CGPoint, clicks: Int = 1) throws -> NSEvent {
        let location = canvas.convert(CGPoint(x: point.x * canvas.displayScale.width, y: point.y * canvas.displayScale.height), to: nil)
        return try NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0, context: nil,
                                      eventNumber: 1, clickCount: clicks, pressure: 1).unwrapped("a mouse event")
    }

    /// An arrow, a rectangle and the text "hello", on a 400 x 300 document: the three the canvas value example names.
    private static func annotate(_ canvas: CanvasView) -> [SketchElement] {
        canvas.newBlank(size: NSSize(width: 400, height: 300)); canvas.editingUndoManager.removeAllActions()
        var arrow = SketchElement(kind: .arrow); arrow.points = [CGPoint(x: 30, y: 40), CGPoint(x: 160, y: 110)]
        var box = SketchElement(kind: .rectangle); box.rect = CGRect(x: 200, y: 30, width: 120, height: 70)
        var label = SketchElement(kind: .text); label.text = "hello"; label.rect = CGRect(x: 40, y: 180, width: 140, height: 40)
        canvas.document.elements = [arrow, box, label]
        return [arrow, box, label]
    }

    // MARK: Editor states

    private static func surfaceEditorStates() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try surfaceChrome(app)
        let elements = annotate(app.canvas)
        app.window.contentView?.layoutSubtreeIfNeeded()
        try walkedWindow(app.window, "Editor (populated)", expecting: [])
        app.canvas.selection = [elements[1].id]
        try walkedWindow(app.window, "Editor (selection)", expecting: [])
        app.canvas.selection = []
        app.canvas.tool = .select
        app.canvas.mouseDown(with: try canvasMouse(app.canvas, .leftMouseDown, CGPoint(x: 60, y: 195), clicks: 2))
        try expect(app.canvas.subviews.contains { $0 is NSTextView }, "Double-clicking the text opens its editor")
        try walkedWindow(app.window, "Editor (text editing)", expecting: [])
        app.canvas.commitPendingTextEditing()
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        try expect(app.frameMode, "Frame mode is on")
        try walkedWindow(app.window, "Editor (frame mode)", expecting: [])
        app.cancelFrame()
        app.enterFrame(keepingAnnotations: true, manualFlags: [])
        try expect(app.frameMode && app.frameKeepsAnnotations && app.canvas.document.elements.count == 3, "Re-Snap keeps the three annotations")
        try walkedWindow(app.window, "Editor (frame keeps annotations)", expecting: [])
        app.cancelFrame()
    }

    private static func surfaceEditorParts() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try surfaceChrome(app)
        _ = annotate(app.canvas)
        app.window.contentView?.layoutSubtreeIfNeeded()
        try walkedView(chrome.header, "Top bar")
        try walkedView(chrome.footer, "Bottom bar")
        // Actual Size: the overview card that floats beside the editor.
        let big = try Fixture(), large = big.app
        _ = try surfaceChrome(large)
        try b6Large(large)
        large.toggleActualSize()
        try expect(large.isActualSize, "Actual Size is on")
        let overview = try large.navigatorWindow.unwrapped("the Actual Size overview panel")
        try expect(overview.title == "Actual Size overview" && overview.isExcludedFromWindowsMenu, "The overview window reads as a titled window, not a bare \"window\", and stays out of the Window menu (\(overview.title))")
        try walkedWindow(overview, "Editor (actual size)")
        large.toggleActualSize()
        // Frame cannot start in full screen: the editor says so in its status line.
        let window = try (app.window as? AppSafetyWindow).unwrapped("isolated window")
        window.simulatesFullScreen = true
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        try expect(!app.frameMode, "Frame refuses to start in full screen")
        try walkedWindow(app.window, "Editor (fullscreen prompt)")
        window.simulatesFullScreen = false
    }

    // MARK: The panels as the app builds them

    private static func surfacePanels() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try surfaceChrome(app)
        _ = annotate(app.canvas)
        app.window.contentView?.layoutSubtreeIfNeeded()
        if let window = app.window as? AppSafetyWindow { window.simulatesVisibility = true; window.shown = true }
        // Size
        let pill = app.widthControl
        pill.showPopover()
        let sizeWindow = try pill.panelWindow.unwrapped("the Size panel window")
        try walkedWindow(sizeWindow, "Size popover")
        pill.dismissPopover()
        // Color
        app.presentDrawingColors(hover: false)
        let colorWindow = try app.colorPanelWindow.unwrapped("the Color panel window")
        try walkedWindow(colorWindow, "Color popover")
        app.closeDrawingColors()
        // Zoom
        let zoom = app.zoomControl
        offScreen(zoom.choicePanel)
        zoom.performClick(nil)
        try expect(zoom.isOpen, "The Zoom panel is open")
        try walkedWindow(zoom.choicePanel.host.window, "Zoom panel")
        zoom.choicePanel.host.close()
        // Upload destinations
        let upload = try (app.webpostButton as? OriginalActionButton).unwrapped("Upload button")
        app.uploadChoices.panelSetup = offScreen
        try expect(upload.accessibilityPerformShowMenu(), "Upload offers Show Menu")
        let uploadPanel = try app.uploadChoices.panel.unwrapped("the Upload panel")
        try expect(app.uploadChoices.isOpen, "The Upload panel is open")
        try walkedWindow(uploadPanel.host.window, "Upload destinations panel")
        uploadPanel.host.close()
        _ = chrome
    }

    // MARK: Small surfaces

    private static func surfaceSmall() throws {
        let sheet = ScreenRecordingPermissionSheet(openURL: { _ in })
        try walkedWindow(sheet.panel, "Permission alert")
        // The menu-bar button: the real item's button is a status-bar button configured by StatusIcon; the same configuration, hosted.
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
        StatusIcon.configure(button)
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 40), styleMask: [.borderless], backing: .buffered, defer: true)
        host.isReleasedWhenClosed = false
        host.contentView = NSView(frame: host.contentRect(forFrameRect: host.frame))
        host.contentView?.addSubview(button)
        try walkedWindow(host, "Status-item button")
        // What the app sets. (What an external client reads is judged by nameMismatch above, baselined pending WP3.)
        try expect(button.accessibilityLabel() == "Show or hide OpenSnap" && AXTree.walk(host).nodes.first?.role == .button,
                   "The menu-bar button carries \"Show or hide OpenSnap\" (\(button.accessibilityLabel() ?? "nil"))")
        // The Upload button's own menu (right-click / Show Menu lists it as the destination choices).
        let fixture = try Fixture(), app = fixture.app
        _ = try surfaceChrome(app)
        let upload = try (app.webpostButton as? OriginalActionButton).unwrapped("Upload button")
        let menu = try upload.menu.unwrapped("the Upload menu")
        let report = AccessibilityAudit.audit(menu, surface: "Upload context menu")
        try expect(report.violations.isEmpty && report.controls >= 1, "The Upload menu has no violations (\(report.controls) items):\n\(report.description)")
    }

    // MARK: Capture

    @MainActor
    private final class UnorderedCountdownPanel: OriginalCountdownPanel {
        override func orderFrontRegardless() {}
        override func orderFront(_ sender: Any?) {}
        override func orderOut(_ sender: Any?) {}
        override func makeKey() {}
        override func makeMain() {}
        override func makeKeyAndOrderFront(_ sender: Any?) {}
    }

    @MainActor
    private final class UnorderedOverlayPanel: OriginalCaptureOverlayPanel {
        override func orderFrontRegardless() {}
        override func orderFront(_ sender: Any?) {}
        override func orderOut(_ sender: Any?) {}
        override func makeKey() {}
        override func makeMain() {}
        override func makeKeyAndOrderFront(_ sender: Any?) {}
    }

    private static func surfaceCapture() throws {
        // Countdown: the numeral panel as the countdown builds it, with a clock that never ticks and an announcer that records.
        var panels: [NSPanel] = [], spoken: [String] = []
        let countdown = OriginalCaptureCountdown(panelFactory: { rect in
            let panel = UnorderedCountdownPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panels.append(panel); return panel
        }, scheduler: { _, _ in { } }, screenFrames: { [NSRect(x: 0, y: 23, width: 1440, height: 847)] },
        reduceMotion: { true }, increaseContrast: { false }, announce: { spoken.append($0) })
        countdown.start(rect: NSRect(x: 200, y: 100, width: 400, height: 300), parent: nil, delay: 3, cue: {}, completion: {})
        defer { countdown.cancel() }
        let panel = try panels.first.unwrapped("the countdown panel")
        try expect(spoken == ["3"], "The countdown speaks its first numeral (\(spoken))")
        try expect(panel.title == "Capture countdown" && panel.isExcludedFromWindowsMenu, "The countdown panel is a titled window for assistive clients (\(panel.title))")
        try walkedWindow(panel, "Countdown")
        // Capture picker overlay: one named, focusable group with its help (Escape, and the non-drag alternatives) and a live selection value.
        let suite = "OpenSnapAccessibilitySurfaces." + UUID().uuidString
        let defaults = TestDefaults(name: suite)
        defer { TestDefaults.dispose(defaults, name: suite) }
        let frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        let overlay = UnorderedOverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        overlay.isReleasedWhenClosed = false
        overlay.contentView = OriginalCaptureSelectionView(frame: frame, windowOnly: false, defaults: defaults)
        defer { overlay.close() }
        try expect(overlay.title == "Capture area" && overlay.isExcludedFromWindowsMenu, "The overlay panel is a titled window for assistive clients (\(overlay.title))")
        try walkedWindow(overlay, "Capture picker overlay")
        let picker = try AXTree.walk(overlay).find(.group, "Capture area picker").unwrapped("the picker group in the overlay's tree")
        try expect(picker.value as? String == "No selection" && (picker.help ?? "").contains("Escape") && (picker.help ?? "").contains("Capture menu"), "The picker reads its value and how to leave or capture without dragging (\(String(describing: picker.value)), \(picker.help ?? "no hint"))")
    }

    // MARK: The canvas says what it holds

    /// What the canvas must answer to accessibilityValue: the annotation count, then their kinds in drawing order, a text by its words.
    static func expectedCanvasSummary(_ elements: [SketchElement]) -> String {
        guard !elements.isEmpty else { return "No annotations" }
        let parts = elements.map { $0.kind == .text ? "text \"\($0.text)\"" : $0.kind.rawValue }
        return "\(elements.count) annotation\(elements.count == 1 ? "" : "s"): " + parts.joined(separator: ", ")
    }

    private static func surfaceCanvasValue() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try surfaceChrome(app)
        try expect(expectedCanvasSummary([]) == "No annotations", "The empty summary")
        let elements = annotate(app.canvas)
        try expect(expectedCanvasSummary(elements) == "3 annotations: arrow, rectangle, text \"hello\"", "The summary names the kinds, a text by its words (\(expectedCanvasSummary(elements)))")
        try expect(expectedCanvasSummary([elements[0]]) == "1 annotation: arrow", "One annotation is singular")
        // Pending WP3 (Canvas.swift sets a role and a label only): the audit reports the canvas as a missingValue, baselined, which goes STALE the
        // moment it answers; from then on its answer must equal the summary.
        let value = app.canvas.accessibilityValue() as? String
        try expect(value == nil || value == expectedCanvasSummary(elements), "The canvas value, once it exists, equals the summary: \(String(describing: value))")
        app.canvas.document.elements = []
        let empty = app.canvas.accessibilityValue() as? String
        try expect(empty == nil || empty == "No annotations", "An empty canvas says No annotations once it speaks: \(String(describing: empty))")
    }
}

private extension Optional {
    func unwrapped(_ name: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing \(name)") }
        return self
    }
}
#endif
