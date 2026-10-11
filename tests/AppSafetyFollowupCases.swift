// Follow-ups to the audit: the full-screen edge cases recorded after round 6, the stale size text after History > Open (F-J4-006) and the
// accessibility of the in-place text editor (F-J1-023).
// Run through tools/test-app-safety.sh; no window or panel is ever put on screen, nothing touches the network or the general pasteboard.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var followupCases: [(String, () throws -> Void)] {
        [
            ("Leaving full screen with the Resize sheet up, then Cancel, restores the picture and leaves the window with its own zoom and size, not full screen's (FS-A)", fuCancelResizeAfterFullScreenExit),
            ("A size change made in full screen resizes the window on the way out even when the zoom comes back unchanged (FS-B)", fuWindowFollowsSizeChangeMadeInFullScreen),
            ("Full screen entered during Actual Size and left from it returns a window that still holds its canvas, not the navigator-nudged one (FS-C)", fuWindowAfterNudgeAndFullScreen),
            ("History > Open, with or without Don't Save, shows the opened document's size and format in the title and footer before the first draw (F-J4-006)", fuHistoryOpenShowsNewSize),
            ("The in-place text editor is a standard AX text area: a readable value, a readable and settable selection, reachable from the window (F-J1-023)", fuTextEditorAccessibility)
        ]
    }

    private static let fuCapacity = CGSize(width: 1000, height: 700)

    private static func fuWindow(_ app: AppDelegate) throws -> AppSafetyWindow {
        guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
        return window
    }

    /// A snap bigger than the window's room, shown fitted, at 100% zoom in a window sized to hold it.
    private static func fuLarge(_ app: AppDelegate, size: CGSize = CGSize(width: 2560, height: 1800), capacity: CGSize = fuCapacity) throws {
        app.maximumNormalCanvasOverride = capacity
        try b6Large(app, size: size)
        app.dragOriginalControl.state = .off
        app.updateDragPreview(); app.updateViewportChrome()
    }

    /// A snap that fits the window at its own size.
    private static func fuSmall(_ app: AppDelegate, size: CGSize) throws {
        app.maximumNormalCanvasOverride = fuCapacity
        app.canvas.newBlank(size: size); app.canvas.setBackground(try image(size: size))
        app.documentGeneration = UUID(); app.canvas.editingUndoManager.removeAllActions()
        app.adoptRasterViewport()
        app.dragOriginalControl.state = .off
        app.updateDragPreview(); app.updateViewportChrome()
    }

    private static func fuEnterFullScreen(_ app: AppDelegate, _ window: AppSafetyWindow, frame: NSRect) {
        window.setFrame(frame, display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        window.simulatesFullScreen = true
        app.windowDidEnterFullScreen(Notification(name: NSWindow.didEnterFullScreenNotification, object: window))
    }

    /// AppKit puts the frame the window had before full screen back, then says it is done.
    private static func fuLeaveFullScreen(_ app: AppDelegate, _ window: AppSafetyWindow, restoring frame: NSRect) {
        window.simulatesFullScreen = false
        window.setFrame(frame, display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        app.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
    }

    private static func fuViewportWidth(_ app: AppDelegate) -> CGFloat { app.canvas.enclosingScrollView?.frame.width ?? 0 }

    // MARK: Full screen, Resize sheet up (A)

    private static func fuCancelResizeAfterFullScreenExit() throws {
        let fixture = try Fixture(), app = fixture.app
        let window = try fuWindow(app)
        try fuLarge(app)
        let windowed = window.frame, zoom = app.canvas.zoom, picture = app.canvas.outputSize, dirty = app.dirty
        fuEnterFullScreen(app, window, frame: NSRect(x: 0, y: 0, width: 2056, height: 1329))
        let fullScreenZoom = app.canvas.zoom
        try expect(fullScreenZoom > 1.2 && app.fullScreenZoom != nil, "Full screen magnifies the shot (\(fullScreenZoom))")
        let session = try app.makeResizeSession().b6Unwrap("the resize session")
        session.state.edit(.width, text: "1600")
        try expect(try session.preview(), "A preview in full screen")
        try expect(app.canvas.outputSize.width == 1600, "The sheet shows 1600 wide (\(app.canvas.outputSize))")
        fuLeaveFullScreen(app, window, restoring: windowed)
        session.cancel()
        try expect(app.canvas.outputSize == picture, "Cancel takes the picture back (\(app.canvas.outputSize), was \(picture))")
        try expect(abs(app.canvas.zoom - zoom) < 0.0005, "…and the window shows it at the zoom it had before full screen, not full screen's \(fullScreenZoom) (\(app.canvas.zoom) vs \(zoom))")
        try expect(abs(window.frame.width - windowed.width) < 1 && abs(window.frame.height - windowed.height) < 1,
                   "…in a window sized for it, not full screen's frame (\(window.frame.size) vs \(windowed.size))")
        try expect(app.fullScreenZoom == nil && app.dirty == dirty, "Full screen's record is gone and Cancel left the document as unsaved as it was (\(app.dirty))")
    }

    // MARK: Full screen, size change made there (B)

    private static func fuWindowFollowsSizeChangeMadeInFullScreen() throws {
        let fixture = try Fixture(), app = fixture.app
        let window = try fuWindow(app)
        // Wider than the window's minimum, so a window sized for the snap is not just the minimum.
        try fuSmall(app, size: CGSize(width: 900, height: 600))
        let windowed = window.frame
        try expect(app.canvas.zoom == 1, "The snap is shown at 100% (\(app.canvas.zoom))")
        fuEnterFullScreen(app, window, frame: NSRect(x: 0, y: 0, width: 2056, height: 1329))
        try expect(app.canvas.zoom > 1 && app.fullScreenZoom != nil, "Full screen magnifies it (\(app.canvas.zoom))")
        let session = try app.makeResizeSession().b6Unwrap("the resize session")
        session.state.edit(.width, text: "1000")
        try expect(try session.commit(), "Apply 1000 wide in full screen")
        session.cancel()
        try expect(app.canvas.outputSize.width == 1000, "The picture is 1000 wide (\(app.canvas.outputSize))")
        fuLeaveFullScreen(app, window, restoring: windowed)
        try expect(app.fullScreenZoom == nil && abs(app.canvas.zoom - 1) < 0.0005, "The window's own zoom is back, unchanged (\(app.canvas.zoom))")
        let room = app.canvas.outputSize.width * app.canvas.zoom
        try expect(fuViewportWidth(app) >= room - 0.5, "The window holds the 1000-wide picture: viewport \(fuViewportWidth(app)) for \(room)")
        try expect(window.frame.width > windowed.width, "…so it grew from the 900-wide snap's window (\(window.frame.width) vs \(windowed.width))")
    }

    // MARK: Full screen entered during Actual Size (C)

    private static func fuWindowAfterNudgeAndFullScreen() throws {
        let fixture = try Fixture(), app = fixture.app
        let window = try fuWindow(app)
        let screen = try (window.screen ?? NSScreen.main).b6Unwrap("a screen")
        let visible = screen.visibleFrame
        // A canvas that nearly spans the screen, in a window at its left edge: the navigator's room costs the window width.
        try fuLarge(app, size: CGSize(width: 6000, height: 1200), capacity: CGSize(width: visible.width - 120, height: 700))
        var frame = window.frame
        frame.origin.x = visible.minX
        window.setFrame(frame, display: false); window.contentView?.layoutSubtreeIfNeeded()
        let holding = window.frame, room = app.canvas.outputSize.width * app.canvas.zoom
        try expect(fuViewportWidth(app) >= room - 0.5, "The window holds its canvas to begin with (\(fuViewportWidth(app)) for \(room))")
        app.toggleActualSize()
        try expect(app.isActualSize && window.frame.width < holding.width - 1, "The navigator's nudge narrowed the window (\(holding.width) → \(window.frame.width))")
        let nudged = window.frame
        fuEnterFullScreen(app, window, frame: NSRect(x: 0, y: 0, width: 2056, height: 1329))
        try expect(app.isActualSize && app.isFullScreen, "Full screen is entered during Actual Size")
        app.toggleActualSize()
        try expect(!app.isActualSize, "Actual Size is left inside full screen")
        fuLeaveFullScreen(app, window, restoring: nudged)
        let restoredRoom = app.canvas.outputSize.width * app.canvas.zoom
        try expect(fuViewportWidth(app) >= restoredRoom - 0.5, "The window is not narrower than its canvas (viewport \(fuViewportWidth(app)) for \(restoredRoom))")
    }

    // MARK: History > Open (F-J4-006)

    private static func fuHistoryOpenShowsNewSize() throws {
        func snapshot(_ size: CGSize) throws -> HistoryStore.Snapshot {
            try HistoryStore.Snapshot(canvasData: SketchDocument(size: size).encoded(), drawingDefaults: DrawingDefaults(values: [:]), preview: nil)
        }
        for dirty in [false, true] {
            for jpeg in [false, true] {
                let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
                let id = try store.archive(try snapshot(CGSize(width: 940, height: 600)), name: "Mockup", action: .archived)
                app.canvas.newBlank(size: NSSize(width: 400, height: 300))
                app.dragFormatToggle.selectedSegment = jpeg ? 1 : 0
                app.updateStatus(); app.updateDragPreview()
                let format = jpeg ? "JPG" : "PNG", tag = "dirty \(dirty), \(format)"
                try expect(app.dragSizeLabel.stringValue.hasPrefix("400 × 300 · \(format)") && app.window.subtitle.hasPrefix("400 × 300 · \(format)"),
                           "\(tag): the previous document reads 400 × 300 (\(app.window.subtitle))")
                app.dirty = dirty
                if dirty { AppSafetyAlert.answers = [.init(title: "Save your drawing?", response: .alertThirdButtonReturn)] }
                app.openHistory(id)
                try expect(app.canvas.outputSize == CGSize(width: 940, height: 600) && app.currentArchiveID == id, "\(tag): the entry is open (\(app.canvas.outputSize))")
                let head = "940 × 600 · \(format)"
                try expect(app.window.subtitle.hasPrefix(head) && app.dragSizeLabel.stringValue.hasPrefix(head),
                           "\(tag): title and size label read \(head) the moment the call returns (\(app.window.subtitle) / \(app.dragSizeLabel.stringValue))")
                try expect(!app.status.stringValue.contains("400 × 300") && !app.status.variants.contains { $0.contains("400 × 300") },
                           "\(tag): the footer never says the old size (\(app.status.stringValue))")
                let window = try fuWindow(app)
                window.simulatesFullScreen = true
                app.refreshStatusText()
                try expect(app.status.stringValue.contains("940 × 600") && app.status.stringValue.contains(format),
                           "\(tag): with the title bar gone the footer carries the new size and format (\(app.status.stringValue))")
                window.simulatesFullScreen = false
            }
        }
    }

    // MARK: The in-place text editor (F-J1-023)

    private static func fuTextEditorAccessibility() throws {
        let fixture = try Fixture(), app = fixture.app
        let editor = try editor(app, text: "Quarterly")
        try expect(editor.isAccessibilityElement() && editor.accessibilityRole() == .textArea, "The editor is a text area element (\(String(describing: editor.accessibilityRole())))")
        try expect(editor.accessibilityLabel() == "Annotation text", "…labelled for what it is (\(String(describing: editor.accessibilityLabel())))")
        try expect(editor.accessibilityValue() as? String == "Quarterly", "…whose value is the text (\(String(describing: editor.accessibilityValue())))")
        try expect(editor.accessibilityAttributeNames().contains(.selectedTextRange), "…exposing the selection attribute")
        try expect(editor.accessibilityIsAttributeSettable(.selectedTextRange)
                   && editor.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.setAccessibilitySelectedTextRange(_:))),
                   "…as settable")
        editor.setAccessibilitySelectedTextRange(NSRange(location: 2, length: 3))
        try expect(editor.accessibilitySelectedTextRange() == NSRange(location: 2, length: 3) && editor.selectedRange() == NSRange(location: 2, length: 3),
                   "Setting the selection through AX lands on the text view (\(editor.selectedRange()))")
        try expect(editor.accessibilitySelectedText() == "art", "…and AX reads back the selected text (\(String(describing: editor.accessibilitySelectedText())))")
        // Reachable the way a client walks: window > scroll area > … > text area.
        func contains(_ element: Any?, _ target: AnyObject, depth: Int = 0) -> Bool {
            guard depth < 10, let element = element as? NSAccessibilityProtocol else { return false }
            if (element as AnyObject) === target { return true }
            return (element.accessibilityChildren() ?? []).contains { contains($0, target, depth: depth + 1) }
        }
        try expect(contains(app.window, editor), "A client walking the window's children reaches the editor")
        app.canvas.commitPendingTextEditing()
        try expect(!contains(app.window, editor), "…and it is gone from the tree once the text is committed")
    }
}
#endif
