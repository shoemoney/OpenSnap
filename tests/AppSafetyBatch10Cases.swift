// Audit fix batch 10: the findings of independent review round 3 (docs/design/e2e/findings.md, R3-001 … R3-009).
// Run through tools/test-app-safety.sh; no window or panel is ever put on screen, nothing touches the network or the general pasteboard.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var batch10Cases: [(String, () throws -> Void)] {
        [
            ("A Resize or Limit above what the window holds makes the picture the output: title, export, upload, copy and drag carry the typed size, ticked or not (R3-001)", b10OversizedResize),
            ("File > Export seeds its Original size from the footer choice and hands the answer back to it (R3-003)", b10ExportAccessoryMatchesFooter),
            ("A corner drag on a snap resizes the picture, one Undo step: title and every output follow the dragged size, ticked or not (R3-002)", b10CornerDragResizesPicture)
        ]
    }

    private static let b10Capacity = CGSize(width: 1000, height: 700)
    private static let b10Snap = CGSize(width: 2560, height: 1800)

    /// A 2560 × 1800 snap on a screen that holds 1000 × 700, so it is shown at 1000 × 703 until something rewrites it.
    private static func b10Snap(_ app: AppDelegate, ticked: Bool) throws {
        app.maximumNormalCanvasOverride = b10Capacity
        try b6Large(app, size: b10Snap)
        app.dragOriginalControl.state = ticked ? .on : .off
        app.updateDragPreview(); app.updateViewportChrome()
        try expect(app.isLargeShot && !app.dragOriginalControl.isHidden && app.canvas.zoom == 1, "The fixture is a large shot with the box showing (\(app.canvas.outputSize))")
    }

    /// The picture is the output: nothing apart from it for the box to bring back, and the window shows it by zoom.
    private static func b10ExpectPictureIsOutput(_ app: AppDelegate, _ size: CGSize, _ what: String) throws {
        try expect(app.canvas.canvasSize == size && app.canvas.outputSize == size && app.canvas.document.renderSize == nil,
                   "\(what): the picture and the output are both \(size) with no separate shown size (\(app.canvas.canvasSize), \(app.canvas.outputSize), \(String(describing: app.canvas.document.renderSize)))")
        try expect(!app.isLargeShot && app.dragOriginalControl.isHidden, "\(what): the box has nothing to offer")
        try expect(app.canvas.zoom < 1 && size.width * app.canvas.zoom <= b10Capacity.width + 1 && size.height * app.canvas.zoom <= b10Capacity.height + 1,
                   "\(what): the window shows it by zoom, within the room (\(app.canvas.zoom))")
        try expect(app.titlePixelSize == size && app.window.subtitle.hasPrefix(PixelSizeText.text(size)), "\(what): the title says \(size) (\(app.window.subtitle))")
    }

    private static func b10OversizedResize() throws {
        for ticked in [true, false] {
            let fixture = try Fixture(), app = fixture.app
            let board = b6Pasteboard(app); defer { board.releaseGlobally() }
            try b10Snap(app, ticked: ticked)
            let session = try app.makeResizeSession().b6Unwrap("the resize session")
            session.state.edit(.width, text: "1600")
            try expect(try session.commit(), "Apply 1600 wide, ticked \(ticked)")
            // The sheet pairs the typed width with the height of the size it opened at: the title's 2560 × 1800, or the shown 996 × 700.
            let resized = CGSize(width: 1600, height: ticked ? 1125 : 1124)
            try b10ExpectPictureIsOutput(app, resized, "Resized, ticked \(ticked)")
            try b6AllAgree(app, board, resized, "Resized, ticked \(ticked)")
            for on in [true, false] {
                app.dragOriginalControl.state = on ? .on : .off; app.updateDragPreview()
                try b6AllAgree(app, board, resized, "Resized, then box \(on ? "ticked" : "unticked")")
            }
            // A Limit above the room does the same.
            session.cancel()
            let limit = try app.makeResizeSession().b6Unwrap("a limit session")
            let limited = CGSize(width: 1200, height: ticked ? 844 : 843)
            limit.state.setMode(.limit); limit.state.limitText = "1200"
            try expect(try limit.commit(), "Apply a limit of 1200")
            try b10ExpectPictureIsOutput(app, limited, "Limited, ticked \(ticked)")
            try b6AllAgree(app, board, limited, "Limited, ticked \(ticked)")
            limit.cancel()
            // Undo gives the snap back as it was: its own pixels, shown fitted, the box offered again.
            while app.canvas.editingUndoManager.canUndo { app.undo() }
            try expect(app.canvas.canvasSize == b10Snap && app.canvas.outputSize.width <= b10Capacity.width && app.canvas.zoom == 1 && app.isLargeShot,
                       "Undo returns the snap fitted at 100% zoom (\(app.canvas.canvasSize), \(app.canvas.outputSize), zoom \(app.canvas.zoom))")
            app.updateViewportChrome()
            try expect(!app.dragOriginalControl.isHidden, "…and the box is back")
        }
    }

    private static func b10ExportAccessoryMatchesFooter() throws {
        let fixture = try Fixture(), app = fixture.app
        try b10Snap(app, ticked: true)
        func checkbox(_ view: NSView?) -> NSButton? {
            guard let view else { return nil }
            if let button = view as? NSButton, button.title == "Export at original size" { return button }
            return view.subviews.lazy.compactMap { checkbox($0) }.first
        }
        // The footer says it covers export, so the accessory opens on the same answer, whichever way it is set.
        for ticked in [true, false] {
            app.dragOriginalControl.state = ticked ? .on : .off; app.updateDragPreview()
            let accessory = app.exportPanelAccessory()
            _ = accessory.view
            try expect(accessory.originalSize == ticked && (checkbox(accessory.view)?.state == .on) == ticked, "The accessory opens \(ticked ? "ticked" : "unticked") like the footer box")
        }
        // Changing the box in the panel and exporting changes the footer box, the stored default and the pixels written.
        for (start, end) in [(true, false), (false, true)] {
            app.dragOriginalControl.state = start ? .on : .off; app.updateDragPreview()
            let target = fixture.file("Export\(start)").deletingPathExtension().appendingPathExtension("png")
            var seeded: Bool?
            AppSafetyFilePanel.answers.append(.init(response: .OK, url: target, whileOpen: { panel in
                guard let box = checkbox(panel.accessoryView) else { return }
                seeded = box.state == .on
                box.performClick(nil)
            }))
            app.exportFile()
            try expect(seeded == start, "The panel opened on the footer's \(start) (\(String(describing: seeded)))")
            let written = try b6Pixels(try Data(contentsOf: target))
            try expect(written == (end ? b10Snap : app.canvas.outputSize), "The file has the pixels the accessory asked for (\(written))")
            try expect((app.dragOriginalControl.state == .on) == end && UserDefaults.standard.bool(forKey: "DragOriginalSize") == end,
                       "The footer box and its default follow the accessory's answer (\(end))")
            try expect(app.titlePixelSize == (end ? b10Snap : app.canvas.outputSize), "…and the title says the same size")
        }
    }

    private static func b10CornerDragResizesPicture() throws {
        for ticked in [true, false] {
            let fixture = try Fixture(), app = fixture.app
            let board = b6Pasteboard(app); defer { board.releaseGlobally() }
            try b10Snap(app, ticked: ticked)
            let steps = { app.canvas.editingUndoManager.canUndo }
            // R4-003: ticked, the picture scales by the drag's proportion of its own pixels; unticked, the dragged shown size is the picture.
            let shownWidth = app.canvas.outputSize.width
            func picture(forDragged dragged: CGSize) -> CGSize {
                ticked ? SketchDocument.wholePixels(CGSize(width: b10Snap.width * dragged.width / shownWidth, height: b10Snap.height * dragged.width / shownWidth)) : dragged
            }
            // Smaller than the shown size.
            try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin the corner drag")
            app.previewBorderGesture(delta: CGPoint(x: -300, y: 0), flags: [])
            let dragged = SketchDocument.wholePixels(app.canvas.outputSize)
            try expect(dragged.width < app.canvas.fullResolutionOutputSize.width && dragged.width < 996, "The drag previews narrower than the shown size (\(dragged))")
            app.endWindowGesture()
            try expect(app.canvas.canvasSize == picture(forDragged: dragged) && app.canvas.document.renderSize == nil && !app.isLargeShot,
                       "Ticked \(ticked): the dragged size scales the picture's own pixels (\(app.canvas.canvasSize), render \(String(describing: app.canvas.document.renderSize)))")
            try b6AllAgree(app, board, picture(forDragged: dragged), "Dragged smaller, ticked \(ticked)")
            app.dragOriginalControl.state = ticked ? .off : .on; app.updateDragPreview()
            try b6AllAgree(app, board, picture(forDragged: dragged), "Dragged smaller, box flipped")
            app.dragOriginalControl.state = ticked ? .on : .off; app.updateDragPreview()
            try expect(steps(), "The drag is an Undo step")
            app.undo()
            try expect(app.canvas.canvasSize == b10Snap && !steps() && app.isLargeShot, "One Undo returns the snap (\(app.canvas.canvasSize))")
            // Larger than the window holds: shown by zoom, still the dragged pixels.
            try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin a second corner drag")
            app.previewBorderGesture(delta: CGPoint(x: 600, y: 0), flags: [])
            let bigger = picture(forDragged: SketchDocument.wholePixels(app.canvas.outputSize))
            app.endWindowGesture()
            try b10ExpectPictureIsOutput(app, bigger, "Dragged larger, ticked \(ticked)")
            try b6AllAgree(app, board, bigger, "Dragged larger, ticked \(ticked)")
            app.undo()
            try expect(app.canvas.canvasSize == b10Snap && app.canvas.zoom == 1, "Undo restores the snap and its 100% zoom (\(app.canvas.zoom))")
            // Escape still takes the whole drag back with no step.
            try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin a third corner drag")
            app.previewBorderGesture(delta: CGPoint(x: -200, y: 0), flags: [])
            app.endWindowGesture(cancelled: true)
            try expect(app.canvas.canvasSize == b10Snap && app.isLargeShot && !steps(), "Cancelled leaves the snap and no step")
        }
    }
}
#endif
