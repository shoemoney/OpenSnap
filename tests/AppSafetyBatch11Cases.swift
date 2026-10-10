// Audit fix batch 11: the findings of independent review round 4 (docs/design/e2e/findings.md, R4-001 … R4-007) and what they turned up.
// Run through tools/test-app-safety.sh; no window or panel is ever put on screen, nothing touches the network or the general pasteboard.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var batch11Cases: [(String, () throws -> Void)] {
        [
            ("After a Resize or corner drag makes a snap bigger than the window, Actual Size is available and leaving it puts back the zoom and its automatic fit (R4-001)", b11ActualSizeAfterOversizedResize),
            ("Typing the picture's own width while Original size is unticked restores the picture's pixels, exactly and without a resample, at an exact or a rounded fit (R4-002)", b11NativeWidthWhileUnticked),
            ("A corner drag with Original size ticked scales the picture in its own pixels by the drag's proportion, and the title says so while dragging (R4-003)", b11CornerDragTicked),
            ("A Limit lands on its number, repeated or not, on a picture whose partner side rounds down by half a pixel", b11RepeatedLimit),
            ("The automatic zoom-to-fit is tracked after a document fit, in full screen and across Frame mode (R4-004)", b11FitZoomIsTracked),
            ("File > Export offers Original size only when the picture differs from the size it is shown at (R4-007)", b11ExportOffersOriginalOnlyWhenItDiffers)
        ]
    }

    private static let b11Capacity = CGSize(width: 1000, height: 700)
    private static let b11Snap = CGSize(width: 2560, height: 1800)

    private static func b11Large(_ app: AppDelegate, size: CGSize = b11Snap, capacity: CGSize = b11Capacity, ticked: Bool) throws {
        app.maximumNormalCanvasOverride = capacity
        try b6Large(app, size: size)
        app.dragOriginalControl.state = ticked ? .on : .off
        app.updateDragPreview(); app.updateViewportChrome()
    }

    private static func b11Apply(_ app: AppDelegate, width: Int) throws {
        let session = try app.makeResizeSession().b6Unwrap("the resize session")
        session.state.edit(.width, text: String(width))
        try expect(try session.commit(), "Apply \(width) wide")
        session.cancel()
    }

    // MARK: R4-001

    private static func b11ActualSizeAfterOversizedResize() throws {
        for corner in [false, true] {
            let fixture = try Fixture(), app = fixture.app
            try b11Large(app, ticked: false)
            let item = NSMenuItem(title: "Actual Size", action: #selector(AppDelegate.toggleActualSize), keyEquivalent: "")
            try expect(app.canToggleActualSize, "A snap shown smaller than it is already offers Actual Size")
            if corner {
                try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin the corner drag")
                app.previewBorderGesture(delta: CGPoint(x: 600, y: 0), flags: [])
                app.endWindowGesture()
            } else { try b11Apply(app, width: 1600) }
            let word = corner ? "dragged larger" : "resized to 1600"
            try expect(app.canvas.outputSize == app.canvas.fullResolutionOutputSize && app.canvas.zoom < 1 && !app.isLargeShot,
                       "\(word): the picture is the output and is shown by zoom (\(app.canvas.outputSize), \(app.canvas.zoom))")
            try expect(app.canToggleActualSize && app.validateMenuItem(item), "\(word): Image > Actual Size is enabled although output == source")
            let zoom = app.canvas.zoom, fit = app.pictureFitZoom
            try expect(fit != nil && abs((fit ?? 0) - zoom) < 0.0005, "\(word): the shown zoom is the automatic fit (\(String(describing: fit)))")
            app.toggleActualSize()
            try expect(app.isActualSize && app.canvas.zoom == 1 && app.canvas.outputSize == app.canvas.canvasSize, "\(word): Actual Size shows one image pixel per screen pixel (\(app.canvas.zoom))")
            app.pictureFitZoom = nil
            app.toggleActualSize()
            try expect(!app.isActualSize && abs(app.canvas.zoom - zoom) < 0.0005, "\(word): leaving puts the zoom back (\(app.canvas.zoom) vs \(zoom))")
            try expect(app.pictureFitZoom == fit, "\(word): …and the automatic fit it had (\(String(describing: app.pictureFitZoom)))")
            // So a Resize down afterwards still returns to 100%.
            try b11Apply(app, width: 400)
            try expect(app.canvas.zoom == 1, "\(word): a later Resize down is shown at 100% (\(app.canvas.zoom))")
        }
        // Nothing to show larger: a snap at its own size, 100%, or a blank canvas, keeps the item disabled.
        let fixture = try Fixture(), app = fixture.app
        app.maximumNormalCanvasOverride = b11Capacity
        app.canvas.newBlank(size: CGSize(width: 600, height: 400)); app.canvas.setBackground(try image(size: CGSize(width: 600, height: 400)))
        app.documentGeneration = UUID(); app.adoptRasterViewport()
        try expect(!app.canToggleActualSize, "A snap shown at its own size at 100% has nothing larger to show (zoom \(app.canvas.zoom))")
        app.canvas.newBlank(size: CGSize(width: 600, height: 400))
        app.canvas.setZoom(0.5)
        try expect(app.canvas.document.backgroundPNG == nil && !app.canToggleActualSize, "A blank canvas zoomed out is not a snap: no Actual Size")
    }

    // MARK: R4-002

    private static func b11NativeWidthWhileUnticked() throws {
        // Exact fit (768 × 540 for 2560 × 1800) and rounded fit (996 × 700).
        for (capacity, shown) in [(CGSize(width: 768, height: 540), CGSize(width: 768, height: 540)), (b11Capacity, CGSize(width: 996, height: 700))] {
            let fixture = try Fixture(), app = fixture.app
            let board = b6Pasteboard(app); defer { board.releaseGlobally() }
            try b11Large(app, capacity: capacity, ticked: false)
            try expect(app.canvas.outputSize == shown && app.isLargeShot, "The fixture is shown at \(shown) (\(app.canvas.outputSize))")
            let pixels = app.canvas.document.backgroundPNG
            try b11Apply(app, width: 2560)
            try expect(app.canvas.canvasSize == b11Snap && app.canvas.outputSize == b11Snap && app.canvas.document.renderSize == nil,
                       "\(shown): typing the native width leaves the picture at \(b11Snap), the output with it (\(app.canvas.canvasSize), \(app.canvas.outputSize))")
            try expect(app.canvas.document.backgroundPNG == pixels, "\(shown): the picture's pixels are the very ones it had, not a resample")
            try expect(!app.isLargeShot && app.canvas.zoom < 1 && app.titlePixelSize == b11Snap, "\(shown): shown by zoom, the title says \(b11Snap) (\(app.titlePixelSize), zoom \(app.canvas.zoom))")
            try b6AllAgree(app, board, b11Snap, "\(shown) restored")
            try expect(app.canvas.editingUndoManager.canUndo, "\(shown): it is an Undo step")
            app.undo()
            try expect(app.canvas.outputSize == shown && app.isLargeShot, "\(shown): Undo returns the fitted snap (\(app.canvas.outputSize))")
        }
        // Ticked, the title already says 2560 × 1800: typing it again changes nothing and leaves no step.
        let fixture = try Fixture(), app = fixture.app
        try b11Large(app, ticked: true)
        let session = try app.makeResizeSession().b6Unwrap("the resize session")
        session.state.edit(.width, text: "2560")
        try expect(try session.commit(), "Apply the title's own width")
        session.cancel()
        try expect(!app.canvas.editingUndoManager.canUndo && app.isLargeShot && app.canvas.outputSize.width < 2560, "Ticked, the same size is no change (\(app.canvas.outputSize))")
    }

    // MARK: R4-003

    private static func b11CornerDragTicked() throws {
        for ticked in [true, false] {
            let fixture = try Fixture(), app = fixture.app
            let board = b6Pasteboard(app); defer { board.releaseGlobally() }
            try b11Large(app, ticked: ticked)
            let shown = app.canvas.outputSize
            try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin the corner drag")
            app.previewBorderGesture(delta: CGPoint(x: -300, y: 0), flags: [])
            let dragged = SketchDocument.wholePixels(app.canvas.outputSize)
            // Ticked, the picture scales by the drag's proportion of its own pixels; unticked, the dragged size is the picture.
            let proportion = dragged.width / shown.width
            let expected = ticked ? SketchDocument.wholePixels(CGSize(width: b11Snap.width * proportion, height: b11Snap.height * proportion)) : dragged
            try expect(app.titlePixelSize == expected && app.window.subtitle.hasPrefix(PixelSizeText.text(expected)),
                       "Ticked \(ticked): mid-drag the title already says what release leaves, \(expected) (\(app.titlePixelSize), \(app.window.subtitle))")
            app.endWindowGesture()
            try expect(app.canvas.canvasSize == expected && app.canvas.outputSize == expected && app.canvas.document.renderSize == nil,
                       "Ticked \(ticked): the picture is \(expected) (\(app.canvas.canvasSize), \(app.canvas.outputSize))")
            if ticked {
                try expect(abs(app.canvas.canvasSize.width / b11Snap.width - dragged.width / shown.width) < 0.001, "…the proportion of its own pixels the drag was of the shown size")
                try expect(app.canvas.canvasSize.width > dragged.width, "…not the collapsed shown size \(dragged)")
            }
            try expect(app.canvas.zoom < 1 || expected.width <= b11Capacity.width, "Ticked \(ticked): the picture is shown within the room (\(app.canvas.zoom))")
            try b6AllAgree(app, board, expected, "Corner drag, ticked \(ticked)")
            app.undo()
            try expect(app.canvas.canvasSize == b11Snap && app.isLargeShot, "Ticked \(ticked): one Undo returns the snap")
            // Larger than the window holds: the ticked drag is still a proportion of the picture, shown by zoom.
            try expect(app.beginWindowGesture(.corner(.bottomRight)), "Begin a second drag")
            app.previewBorderGesture(delta: CGPoint(x: 400, y: 0), flags: [])
            let big = SketchDocument.wholePixels(app.canvas.outputSize)
            let want = ticked ? SketchDocument.wholePixels(CGSize(width: b11Snap.width * big.width / shown.width, height: b11Snap.height * big.width / shown.width)) : big
            app.endWindowGesture()
            try expect(app.canvas.canvasSize == want && app.canvas.outputSize == want && !app.isLargeShot, "Ticked \(ticked): dragged larger is \(want) (\(app.canvas.canvasSize))")
            try b6AllAgree(app, board, want, "Corner drag larger, ticked \(ticked)")
        }
    }

    // MARK: Limit

    private static func b11RepeatedLimit() throws {
        for (snap, first, second) in [(CGSize(width: 1981, height: 953), 1400, 1200), (CGSize(width: 2425, height: 900), 1400, 1400), (CGSize(width: 2351, height: 900), 1200, 1400)] {
            for ticked in [true, false] {
                let fixture = try Fixture(), app = fixture.app
                try b11Large(app, size: snap, ticked: ticked)
                let session = try app.makeResizeSession().b6Unwrap("a limit session")
                session.state.setMode(.limit)
                // One session, the Limit applied three times: its number each time, never a pixel short.
                for (number, limit) in [first, first, second].enumerated() {
                    session.state.limitText = String(limit)
                    try expect(try session.commit(), "Apply a limit of \(limit)")
                    let side = max(app.canvas.canvasSize.width, app.canvas.canvasSize.height)
                    try expect(side == CGFloat(limit) && app.titlePixelSize.width == app.canvas.canvasSize.width,
                               "\(snap), ticked \(ticked), Limit #\(number + 1) of \(limit): the longest side is \(limit) (\(app.canvas.canvasSize))")
                }
                session.cancel()
            }
        }
    }

    // MARK: R4-004

    private static func b11FitZoomIsTracked() throws {
        // A document fitted to the window (opening a file, History Open) is an automatic zoom: a Resize down afterwards is shown at 100%.
        do {
            let fixture = try Fixture(), app = fixture.app
            try b11Large(app, ticked: false)
            try b11Apply(app, width: 2000)
            app.fitCanvasToWindow()
            let fit = app.canvas.zoom
            try expect(fit < 1 && app.pictureFitZoom != nil && abs((app.pictureFitZoom ?? 0) - fit) < 0.0005, "A window fit of a big picture is recorded as the automatic zoom (\(fit), \(String(describing: app.pictureFitZoom)))")
            try b11Apply(app, width: 400)
            try expect(app.canvas.zoom == 1, "A Resize down afterwards is shown at 100%, not the old small zoom (\(app.canvas.zoom))")
        }
        // Full screen: a Resize there fits the Space, the zoom the window had is put back on the way out, and then the picture is fitted to the window.
        do {
            let fixture = try Fixture(), app = fixture.app
            guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
            app.maximumNormalCanvasOverride = b11Capacity
            app.canvas.newBlank(size: CGSize(width: 800, height: 600)); app.canvas.setBackground(try image(size: CGSize(width: 800, height: 600)))
            app.documentGeneration = UUID(); app.canvas.editingUndoManager.removeAllActions(); app.adoptRasterViewport()
            try expect(app.canvas.zoom == 1, "The 800 × 600 snap fits the room at 100%")
            window.setFrame(NSRect(x: 0, y: 0, width: 2056, height: 1329), display: false)
            window.contentView?.layoutSubtreeIfNeeded()
            window.simulatesFullScreen = true
            app.windowDidEnterFullScreen(Notification(name: NSWindow.didEnterFullScreenNotification, object: window))
            try expect(app.canvas.zoom > 1, "Full screen magnifies it (\(app.canvas.zoom))")
            try b11Apply(app, width: 1600)
            let normalFit = try app.zoomFitting(app.canvas.outputSize).b6Unwrap("the window's fit")
            try expect(app.canvas.zoom > normalFit + 0.05, "In full screen the 1600 wide picture is fitted to the Space, not squeezed into the normal window's room (\(app.canvas.zoom) vs \(normalFit))")
            let scroll = try app.canvas.enclosingScrollView.b6Unwrap("the scroll view")
            try expect(app.canvas.frame.width <= scroll.contentView.bounds.width + 0.5 && app.canvas.frame.height <= scroll.contentView.bounds.height + 0.5,
                       "…and it fits whole, not spilling past the Space (\(app.canvas.frame.size) in \(scroll.contentView.bounds.size))")
            try expect(abs((app.fullScreenZoom?.applied ?? -1) - app.canvas.zoom) < 0.0005, "…and full screen's record of the zoom it chose follows (\(String(describing: app.fullScreenZoom)))")
            window.simulatesFullScreen = false
            app.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
            try expect(app.fullScreenZoom == nil && abs(app.canvas.zoom - normalFit) < 0.0005, "Leaving full screen fits the picture to the window (\(app.canvas.zoom) vs \(normalFit))")
            try expect(app.pictureFitZoom != nil && abs((app.pictureFitZoom ?? 0) - app.canvas.zoom) < 0.0005, "…as the automatic zoom (\(String(describing: app.pictureFitZoom)))")
            try b11Apply(app, width: 300)
            try expect(app.canvas.zoom == 1, "A Resize down afterwards is shown at 100% (\(app.canvas.zoom))")
        }
        // Frame mode: an Undo made while Frame is up is fitted when Frame ends.
        do {
            let fixture = try Fixture(), app = fixture.app
            try b11Large(app, ticked: false)
            try b11Apply(app, width: 1600)
            try expect(app.canvas.zoom < 1, "The resized picture is shown by zoom (\(app.canvas.zoom))")
            app.frameSnap()
            try expect(app.frameMode, "Frame is up")
            app.undo()
            try expect(app.canvas.outputSize.width < 1600, "Undo took the Resize back (\(app.canvas.outputSize))")
            app.leaveFrame()
            try expect(!app.frameMode && app.canvas.zoom == 1, "Leaving Frame refits the restored snap to 100% (\(app.canvas.zoom))")
        }
    }

    // MARK: R4-007

    private static func b11ExportOffersOriginalOnlyWhenItDiffers() throws {
        func checkbox(_ view: NSView?) -> NSButton? {
            guard let view else { return nil }
            if let button = view as? NSButton, button.title == "Export at original size" { return button }
            return view.subviews.lazy.compactMap { checkbox($0) }.first
        }
        let fixture = try Fixture(), app = fixture.app
        try b11Large(app, ticked: false)
        try expect(app.isLargeShot, "A snap shown smaller than it is")
        var accessory = app.exportPanelAccessory()
        try expect(checkbox(accessory.view)?.isHidden == false, "…offers Export at original size")
        // The panel built by File > Export carries the same.
        var seen: Bool?
        let target = fixture.file("Offered").deletingPathExtension().appendingPathExtension("png")
        AppSafetyFilePanel.answers.append(.init(response: .OK, url: target, whileOpen: { panel in seen = checkbox(panel.accessoryView)?.isHidden == false }))
        app.exportFile()
        try expect(seen == true, "…and so does the panel File > Export shows (\(String(describing: seen)))")
        try b11Apply(app, width: 1600)
        try expect(!app.isLargeShot, "After a Resize the picture is the size it is shown at")
        accessory = app.exportPanelAccessory()
        try expect(checkbox(accessory.view)?.isHidden == true, "…so the accessory has no Export at original size to offer")
        seen = nil
        let second = fixture.file("NotOffered").deletingPathExtension().appendingPathExtension("png")
        AppSafetyFilePanel.answers.append(.init(response: .OK, url: second, whileOpen: { panel in seen = checkbox(panel.accessoryView)?.isHidden == true }))
        app.exportFile()
        try expect(seen == true, "…nor does the panel File > Export shows")
        let written = try b6Pixels(try Data(contentsOf: second))
        try expect(written == app.canvas.outputSize, "The file has the picture's pixels (\(written))")
    }
}
#endif
