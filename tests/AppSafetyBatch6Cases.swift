// Audit fix batch 6: the App-side findings of the J6 real-click retest and the independent review that followed (docs/design/e2e/findings.md).
// Run through tools/test-app-safety.sh; no window or panel is ever put on screen, nothing touches the network or the general pasteboard.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var batch6Cases: [(String, () throws -> Void)] {
        [
            ("With Original size ticked, Resize, Crop and Limit change the picture itself: title, status, export, drag, copy and upload all carry the new pixels (F-J6-001, R2-002)", b6TickedPictureSize),
            ("Unticked, Resize and Limit rewrite the picture exactly as when ticked: one rule, so ticking the box afterwards changes nothing (F-J6-001, F-J7-005)", b6UntickedShownSize),
            ("Copy Image sends the same pixels as export, drag and upload, with the box ticked and unticked (F-J6-002)", b6CopyImage),
            ("Apply keeps the change and the sheet; Cancel then undoes only what was typed after it; OK straight after Apply adds no second step (F-J6-007)", b6ApplyCommits),
            ("The title and the footer follow the Original size box in the same pass, before the byte-count timer (F-J6-005)", b6TitleFollowsBox),
            ("Original size is decided from the document: no snap, no box; a saved shown size keeps it on any display (R2-002, R2-003)", b6OriginalSizeFromDocument),
            ("The footer state is whole at 980, 1024 and 1440 with the box showing: Unsaved, Nothing to save, an error (F-J6-004, R2-014)", b6StatusWholeAtWidths),
            ("The PNG | JPG toggle is one compact button below 1100 pt and two segments from there (R2-014)", b6FormatCompaction),
            ("History's Delete from Web follows the destinations: edit, stale, restore (F-J6-003)", b6DeleteFromWebFollowsDestinations),
            ("Hide and Move to Trash are both Cancel-first sheets with Cancel as the default (F-J6-008)", b6ConfirmationsCancelFirst),
            ("The Toolbox is a menu button named Toolbox with no value, opens below itself, and every row has an icon (F-J6-009, R2-004)", b6Toolbox),
            ("One size formatter: the title, History Details, the Export panel and the Photos list write 2560 × 1800 the same way (F-J6-010)", b6OneSizeFormat)
        ]
    }

    // MARK: Fixtures

    static func b6Large(_ app: AppDelegate, size: CGSize = CGSize(width: 2400, height: 1600)) throws {
        app.canvas.newBlank(size: size)
        app.canvas.setBackground(try image(size: size))
        app.documentGeneration = UUID(); app.canvas.editingUndoManager.removeAllActions()
        app.adoptRasterViewport()
        try expect(app.canvas.outputSize.width < size.width, "The fixture is a large shot shown smaller than it is (\(app.canvas.outputSize))")
    }
    static func b6Pixels(_ data: Data?) throws -> CGSize {
        let bitmap = try NSBitmapImageRep(data: try data.b6Unwrap("image data")).b6Unwrap("a decodable image")
        return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    }
    static func b6Pasteboard(_ app: AppDelegate) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("opensnap-b6-" + UUID().uuidString))
        app.imagePasteboard = board
        return board
    }
    /// Every way a picture leaves the editor, as pixels.
    static func b6Outputs(_ app: AppDelegate, _ board: NSPasteboard) throws -> [String: CGSize] {
        app.imagePasteboard = board
        app.copyImage()
        let view = try app.dragExportView.b6Unwrap("the drag view")
        let prepare = try view.prepare.b6Unwrap("the drag view's prepare closure")
        let drag = try prepare().b6Unwrap("the drag payload (sheet \(String(describing: app.window.attachedSheet)), frame capture \(app.frameCaptureInProgress), snapshot \({ do { _ = try app.historySnapshot(); return "ok" } catch { return "\(error)" } }()), export \((try? app.exportData(format: app.dragFormat, originalSize: app.dragAtOriginalSize, jpegQuality: app.dragQuality)) != nil))")
        return [
            "title": app.titlePixelSize,
            "export": try b6Pixels(try app.exportData(format: "png", originalSize: app.dragAtOriginalSize, jpegQuality: 0.75)),
            "drag": try b6Pixels(drag.data),
            "upload": try b6Pixels(try app.uploadPayload().b6Unwrap("the upload payload").0),
            "copy": try b6Pixels(board.data(forType: .tiff)),
            "history": app.uploadPixelSize
        ]
    }
    static func b6AllAgree(_ app: AppDelegate, _ board: NSPasteboard, _ expected: CGSize?, _ what: String) throws {
        let outputs: [String: CGSize]
        do { outputs = try b6Outputs(app, board) } catch { throw Failure(description: "\(what): \(error) [size \(app.canvas.document.size), render \(String(describing: app.canvas.document.renderSize)), valid \(String(describing: try? app.canvas.document.validated().size))]") }
        let title = try outputs["title"].b6Unwrap("title")
        try expect(outputs.values.allSatisfy { $0 == title }, "\(what): title, export, drag, upload, copy and History all say the same size (\(outputs))")
        if let expected { try expect(title == expected, "\(what): and it is \(expected) (\(title))") }
    }
    static func b6Window(_ app: AppDelegate, width: CGFloat) {
        let content = app.window.contentView!
        let frame = app.window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: content.bounds.height))
        app.window.setFrame(NSRect(origin: app.window.frame.origin, size: frame.size), display: false)
        content.layoutSubtreeIfNeeded(); app.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: app.window)); content.layoutSubtreeIfNeeded()
    }

    // MARK: F-J6-001, F-J6-002, R2-002

    private static func b6TickedPictureSize() throws {
        let fixture = try Fixture(), app = fixture.app
        let board = b6Pasteboard(app); defer { board.releaseGlobally() }
        try b6Large(app)
        app.dragOriginalControl.state = .on; app.updateDragPreview()
        try b6AllAgree(app, board, CGSize(width: 2400, height: 1600), "Untouched, ticked")
        // Resize: typed in the title's pixels, so 1200 wide is 1200 × 800 of the picture, not half of what is shown.
        let session = try app.makeResizeSession().b6Unwrap("the resize session")
        session.state.edit(.width, text: "1200")
        try expect(try session.commit(), "Apply with a typed width")
        try expect(app.canvas.canvasSize == CGSize(width: 1200, height: 800), "The picture is now 1200 × 800 of its own pixels (\(app.canvas.canvasSize))")
        try b6AllAgree(app, board, CGSize(width: 1200, height: 800), "Resized, ticked")
        app.dragOriginalControl.state = .off; app.updateDragPreview()
        try b6AllAgree(app, board, app.canvas.outputSize, "Resized, unticked")
        try expect(app.canvas.outputSize.width <= 1200 && app.canvas.outputSize.width >= 1, "Unticked is the shown size of the resized picture (\(app.canvas.outputSize))")
        app.dragOriginalControl.state = .on; app.updateDragPreview()
        session.cancel()
        // Crop to exact pixels.
        let crop = try app.makeResizeSession().b6Unwrap("a crop session")
        crop.state.setMode(.crop); crop.state.edit(.width, text: "600"); crop.state.edit(.height, text: "400")
        try expect(try crop.commit(), "Apply a crop")
        try expect(app.canvas.canvasSize == CGSize(width: 600, height: 400), "Crop keeps exactly 600 × 400 pixels (\(app.canvas.canvasSize))")
        try b6AllAgree(app, board, CGSize(width: 600, height: 400), "Cropped, ticked")
        crop.cancel()
        // Limit the longest side.
        let limit = try app.makeResizeSession().b6Unwrap("a limit session")
        limit.state.setMode(.limit); limit.state.limitText = "300"
        try expect(try limit.commit(), "Apply a limit")
        try expect(app.canvas.canvasSize == CGSize(width: 300, height: 200), "Limit 300 on a 600 × 400 picture gives 300 × 200 (\(app.canvas.canvasSize))")
        try b6AllAgree(app, board, CGSize(width: 300, height: 200), "Limited, ticked")
        limit.cancel()
        // Every step is one Undo back to the start, and the picture's own pixels come back with it.
        while app.canvas.editingUndoManager.canUndo { app.undo() }
        try expect(app.canvas.canvasSize == CGSize(width: 2400, height: 1600), "Undo returns the original picture (\(app.canvas.canvasSize))")
    }

    private static func b6UntickedShownSize() throws {
        let fixture = try Fixture(), app = fixture.app
        let board = b6Pasteboard(app); defer { board.releaseGlobally() }
        try b6Large(app)
        app.dragOriginalControl.state = .off; app.updateDragPreview()
        let shown = app.canvas.outputSize
        // A request for the size already shown changes nothing: no edit, no Undo step, the picture keeps its pixels.
        let same = try app.makeResizeSession().b6Unwrap("a no-change session")
        _ = try same.commit()
        try expect(app.canvas.canvasSize == CGSize(width: 2400, height: 1600) && !app.canvas.editingUndoManager.canUndo, "Apply at the shown size is no edit (\(app.canvas.canvasSize))")
        same.cancel()
        let session = try app.makeResizeSession().b6Unwrap("the resize session")
        let half = Int(shown.width) / 2
        session.state.edit(.width, text: String(half))
        try expect(try session.commit(), "Apply half the shown width")
        // The picture itself is now the chosen size; there is no older, larger picture left behind for the box to bring back.
        let chosen = app.canvas.canvasSize
        try expect(abs(chosen.width - CGFloat(half)) <= 1 && abs(chosen.height / chosen.width - 1600.0 / 2400.0) < 0.01, "The picture is the chosen \(half) wide, in proportion (\(chosen))")
        try b6AllAgree(app, board, chosen, "Resized, unticked")
        try expect(app.canvas.outputSize == chosen && !app.isLargeShot && app.dragOriginalControl.isHidden, "Picture and shown size agree, so the box has nothing to offer (\(app.canvas.outputSize))")
        // Ticking is a no-op: nothing jumps back to 2400 × 1600.
        app.dragOriginalControl.state = .on; app.updateDragPreview()
        try b6AllAgree(app, board, chosen, "Resized, then ticked")
        app.dragOriginalControl.state = .off; app.updateDragPreview()
        try b6AllAgree(app, board, chosen, "Resized, ticked, unticked again")
        session.cancel()
        // The same size reached ticked gives the same picture, byte for byte in size.
        app.undo()
        try expect(app.canvas.canvasSize == CGSize(width: 2400, height: 1600), "One Undo returns the original (\(app.canvas.canvasSize))")
        app.dragOriginalControl.state = .on; app.updateDragPreview()
        let tickedSession = try app.makeResizeSession().b6Unwrap("a ticked session")
        tickedSession.state.edit(.width, text: String(Int(chosen.width)))
        try expect(try tickedSession.commit(), "Apply the same width ticked")
        try expect(app.canvas.canvasSize == chosen, "Ticked and unticked reach the same picture (\(app.canvas.canvasSize) vs \(chosen))")
        tickedSession.cancel()
        // Limit follows the same rule when unticked.
        while app.canvas.editingUndoManager.canUndo { app.undo() }
        app.dragOriginalControl.state = .off; app.updateDragPreview()
        let limit = try app.makeResizeSession().b6Unwrap("a limit session")
        limit.state.setMode(.limit); limit.state.limitText = "900"
        try expect(try limit.commit(), "Apply a limit unticked")
        try expect(app.canvas.canvasSize == CGSize(width: 900, height: 600), "Limit 900 rewrites the picture to 900 × 600 (\(app.canvas.canvasSize))")
        try b6AllAgree(app, board, CGSize(width: 900, height: 600), "Limited, unticked")
        app.dragOriginalControl.state = .on; app.updateDragPreview()
        try b6AllAgree(app, board, CGSize(width: 900, height: 600), "Limited, then ticked")
        limit.cancel()
    }

    private static func b6CopyImage() throws {
        let fixture = try Fixture(), app = fixture.app
        let board = b6Pasteboard(app); defer { board.releaseGlobally() }
        try b6Large(app)
        for ticked in [true, false] {
            app.dragOriginalControl.state = ticked ? .on : .off; app.updateDragPreview()
            app.copyImage()
            let copied = try b6Pixels(board.data(forType: .tiff))
            let expected = ticked ? CGSize(width: 2400, height: 1600) : app.canvas.outputSize
            try expect(copied == expected && app.titlePixelSize == expected, "Ticked \(ticked): Copy Image puts \(expected) on the pasteboard, as the title says (\(copied), title \(app.titlePixelSize))")
        }
    }

    // MARK: F-J6-007

    private static func b6ApplyCommits() throws {
        let fixture = try Fixture(), app = fixture.app
        try b6Large(app)
        app.dragOriginalControl.state = .on; app.updateDragPreview()
        app.dirty = false
        let history = app.canvas.editingUndoManager
        let session = try app.makeResizeSession().b6Unwrap("the resize session")
        session.state.edit(.width, text: "1200")
        try expect(try session.commit() && !session.isFinished && app.activeResizeSession === session, "Apply keeps the sheet open")
        try expect(history.canUndo && app.dirty && app.canvas.canvasSize == CGSize(width: 1200, height: 800), "…and the change is a finished edit with an Undo step")
        try expect(session.state.displayWidthText == "1200" && session.state.displayHeightText == "800", "The fields show the new title size (\(session.state.displayWidthText) × \(session.state.displayHeightText))")
        // More typing is only a preview until the next Apply; Cancel takes back just that.
        session.state.edit(.width, text: "300")
        _ = try session.preview()
        try expect(app.canvas.canvasSize == CGSize(width: 300, height: 200), "A later edit previews (\(app.canvas.canvasSize))")
        session.cancel()
        try expect(app.canvas.canvasSize == CGSize(width: 1200, height: 800) && app.dirty && history.canUndo && app.activeResizeSession == nil,
                   "Cancel returns to the applied 1200 × 800 and keeps it (\(app.canvas.canvasSize))")
        app.undo()
        try expect(app.canvas.canvasSize == CGSize(width: 2400, height: 1600) && !history.canUndo, "One Undo takes back the applied change and nothing else (\(app.canvas.canvasSize))")
        app.redo()
        // OK straight after Apply adds no second step.
        let second = try app.makeResizeSession().b6Unwrap("a second session")
        second.state.edit(.width, text: "600")
        try expect(try second.commit(), "Apply again")
        let steps = { () -> Int in var count = 0; while history.canUndo { history.undo(); count += 1 }; return count }
        _ = try second.apply()
        try expect(second.isFinished && app.canvas.canvasSize == CGSize(width: 600, height: 400), "OK after Apply closes on the applied size (\(app.canvas.canvasSize))")
        try expect(steps() == 2, "Two Applies are two Undo steps; OK added none")
    }

    // MARK: F-J6-005

    private static func b6TitleFollowsBox() throws {
        let fixture = try Fixture(), app = fixture.app
        try b6Large(app)
        app.dragOriginalControl.state = .on; app.changeDragOptions(nil)
        app.footerShowsPictureFactsOverride = true; app.refreshStatusText()
        let own = "2400 × 1600 · PNG", shown = "\(Int(app.canvas.outputSize.width)) × \(Int(app.canvas.outputSize.height)) · PNG"
        try expect(app.window.subtitle.hasPrefix(own) && app.dragSizeLabel.stringValue.hasPrefix(own) && app.status.stringValue.contains("2400 × 1600"),
                   "Ticked: title, label and footer read the picture's own size at once (\(app.window.subtitle) / \(app.status.stringValue))")
        app.dragOriginalControl.state = .off; app.changeDragOptions(nil)
        try expect(app.window.subtitle.hasPrefix(shown) && app.dragSizeLabel.stringValue.hasPrefix(shown) && app.status.stringValue.contains(shown.components(separatedBy: " · ")[0]),
                   "Unticked: all three follow in the same pass, before the timer measures bytes (\(app.window.subtitle) / \(app.status.stringValue))")
        try expect(app.dragPreviewTimer != nil, "The timer is still pending; it only adds the byte count")
        app.footerShowsPictureFactsOverride = nil
    }

    // MARK: R2-002, R2-003

    private static func b6OriginalSizeFromDocument() throws {
        let fixture = try Fixture(), app = fixture.app
        app.canvas.newBlank(size: CGSize(width: 800, height: 600)); app.updateStatus()
        try expect(!app.isLargeShot && app.dragOriginalControl.isHidden && !app.dragAtOriginalSize, "A blank canvas has no snap, so no Original size box")
        try b6Large(app)
        app.updateStatus()
        try expect(app.isLargeShot && !app.dragOriginalControl.isHidden, "A large snap shows it")
        app.canvas.wipeSnap(); app.updateStatus()
        try expect(!app.isLargeShot && app.dragOriginalControl.isHidden && !app.dragAtOriginalSize, "Remove Snap Picture takes the box away instead of leaving a box that does nothing")
        // A canvas that keeps a shown size smaller than its own size but has no snap still has no such choice.
        var bare = SketchDocument(size: CGSize(width: 800, height: 600)); bare.renderSize = CGSize(width: 400, height: 300)
        try app.canvas.loadDocument(data: try bare.encoded()); app.updateStatus()
        try expect(app.canvas.outputSize != app.canvas.canvasSize && !app.isLargeShot && app.dragOriginalControl.isHidden && !app.dragAtOriginalSize,
                   "A shown size with no snap behind it offers no Original size (\(app.canvas.outputSize) of \(app.canvas.canvasSize))")
        // A document that carries a shown size smaller than its picture keeps the choice whatever the screen: 800 × 600 fits any display.
        var document = SketchDocument(size: CGSize(width: 800, height: 600))
        document.backgroundPNG = SketchRenderer.png(image: try image(size: CGSize(width: 800, height: 600)))
        document.renderSize = CGSize(width: 400, height: 300)
        try app.canvas.loadDocument(data: try document.encoded())
        app.updateStatus()
        try expect(app.canvas.outputSize == CGSize(width: 400, height: 300) && app.isLargeShot && !app.isLargerThanScreen, "A saved shown size smaller than the picture is a choice on any display (screen-independent)")
        app.dragOriginalControl.state = .on
        try expect(app.exportPixelSize(originalSize: app.dragAtOriginalSize) == CGSize(width: 800, height: 600), "…and ticked it exports the picture's 800 × 600")
        app.dragOriginalControl.state = .off
        try expect(app.exportPixelSize(originalSize: app.dragAtOriginalSize) == CGSize(width: 400, height: 300), "…unticked the shown 400 × 300")
    }

    // MARK: F-J6-004, R2-014

    private static func b6StatusWholeAtWidths() throws {
        let fixture = try Fixture(), app = fixture.app
        try b6Large(app)
        app.dragOriginalControl.state = .on
        func whole(_ what: String) throws {
            app.window.contentView?.layoutSubtreeIfNeeded()
            let shown = app.status.stringValue, width = app.status.bounds.width
            let needed = ceil(((shown as NSString).size(withAttributes: [.font: app.status.font as Any])).width)
            try expect(!shown.contains("…") || app.status.variants.contains(shown), "\(what): the text is a whole variant, not a tail cut (\(shown))")
            try expect(needed <= width + 1, "\(what): '\(shown)' fits its slot whole (\(needed) in \(width))")
        }
        for width in [980.0, 1024, 1440] as [CGFloat] {
            b6Window(app, width: width)
            app.dirty = true; app.setTool(.arrow); app.updateStatus(); try whole("\(Int(width)) unsaved")
            app.dirty = false; app.updateStatus(); try whole("\(Int(width)) saved")
            app.postStatusNotice(AppDelegate.nothingToSaveNotice); try whole("\(Int(width)) nothing to save")
            app.clearStatusNotice()
            app.uploadState = .failure(message: "The server returned HTTP 403 for this request and refused it.")
            b6Window(app, width: width); try whole("\(Int(width)) error")
            try expect(!app.status.stringValue.hasPrefix("Error:") && (app.status.accessibilityValue() as? String)?.hasPrefix("Error: ") == true && app.status.accessibilityHelp()?.hasPrefix("Error: ") != true,
                       "\(Int(width)): the footer drops the Error: lead, the spoken value keeps it and the hint does not say it twice")
            app.uploadState = .idle
        }
        app.dirty = true; app.updateStatus()
        try expect(app.status.variants.contains("Unsaved") && AppDelegate.noticeVariants(for: AppDelegate.nothingToSaveNotice).contains("Nothing to save"), "Shorter forms exist for the state and the notice")
    }

    private static func b6FormatCompaction() throws {
        let fixture = try Fixture(), app = fixture.app
        for width in [980.0, 1024, 1099, 1100, 1440] as [CGFloat] {
            b6Window(app, width: width)
            let compact = width < 1100
            try expect(app.dragFormatToggle.isCompact == compact, "\(Int(width)): the format toggle is \(compact ? "one compact button" : "two segments") (\(app.dragFormatToggle.frame.width) pt)")
            if compact { try expect(app.dragFormatToggle.frame.width < 100, "\(Int(width)): one compact button with its swap cue, about 94 pt (\(app.dragFormatToggle.frame.width))") }
            else { try expect(app.dragFormatToggle.frame.width > 100, "\(Int(width)): both segments (\(app.dragFormatToggle.frame.width))") }
        }
    }

    // MARK: F-J6-003

    private static func b6DeleteFromWebFollowsDestinations() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        _ = try b3cShowHistory(app)
        let url = URL(string: "https://cdn.example.com/pics/a.png")!
        let bound = try store.archive(try historyDrawing("Bound"), name: "Bound", action: .shared, destination: url.absoluteString, remoteURL: url,
                                      remoteBinding: try b3cRealBinding(app, url: url))
        app.refreshHistory()
        let browser = try app.historyBrowser.b6Unwrap("the History browser")
        func item() throws -> HistoryBrowser.Item { try browser.visibleItems.first { $0.id == bound }.b6Unwrap("the entry") }
        try expect(try item().canDeleteFromWeb && browser.canPerform(.deleteRemote) == false, "A bound entry can be deleted from the web (nothing selected yet)")
        browser.select(ids: [bound])
        try expect(browser.canPerform(.deleteRemote), "…and the button is enabled with it selected")
        // Edit the default destination's folder: the entry is stale at once, while still selected, with the reason.
        let destinations = try app.publishing.store.load()
        var edited = try destinations.destinations[0]
        let original = edited.settings.remoteFolder
        edited.settings.remoteFolder = "pics-elsewhere"
        try app.publishing.store.save(edited, password: "")
        try expect(!(try item().canDeleteFromWeb) && (try item().deleteBlockedReason)?.contains("no longer the server") == true && !browser.canPerform(.deleteRemote),
                   "After the edit the button is off and says why, without reselecting")
        // Put the exact folder back: it is deletable again, again without reselecting or reloading.
        edited.settings.remoteFolder = original
        try app.publishing.store.save(edited, password: "")
        try expect(try item().canDeleteFromWeb && (try item().deleteBlockedReason) == nil && browser.canPerform(.deleteRemote),
                   "Restoring the exact folder makes it deletable again")
        // A rename is not a different destination.
        var renamed = edited; renamed.name = "Renamed"
        try app.publishing.store.save(renamed, password: "")
        try expect(try item().canDeleteFromWeb, "Renaming keeps it deletable")
    }

    // MARK: F-J6-008

    private static func b6ConfirmationsCancelFirst() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let id = try store.archive(try historyDrawing("A"), name: "A", action: .archived)
        AppSafetyAlert.holdAnswers = true
        defer { AppSafetyAlert.holdAnswers = false }
        app.removeHistory([id], deleteFiles: false); app.removeHistory([id], deleteFiles: true)
        let alerts = AppSafetyAlert.pending.map(\.alert)
        try expect(alerts.count == 2, "Both questions are on screen (\(alerts.count))")
        let orders = alerts.map { $0.buttons.map(\.title) }
        try expect(orders == [["Cancel", "Hide"], ["Cancel", "Move to Trash"]], "One order for both: Cancel, then the action (\(orders))")
        for alert in alerts {
            try expect(alert.panel.initialFirstResponder === alert.buttonViews[0] && alert.buttonViews[0].keyEquivalent == "\r" && alert.buttonViews[0].title == "Cancel",
                       "\(alert.title): Return and the initial focus are on Cancel")
        }
        b6Answer(.alertFirstButtonReturn); b6Answer(.alertFirstButtonReturn)
        try expect(store.entries.contains { $0.id == id }, "Cancel on both removes nothing")
        app.removeHistory([id], deleteFiles: false); b6Answer(.alertSecondButtonReturn)
        try expect(!store.entries.contains { $0.id == id }, "The second button, Hide, hides the entry")
    }
    private static func b6Answer(_ response: NSApplication.ModalResponse) {
        let held = AppSafetyAlert.pending.removeFirst()
        withExtendedLifetime(held) { held.reply(response) }
    }

    // MARK: F-J6-009, R2-004

    private static func b6Toolbox() throws {
        let fixture = try Fixture(), app = fixture.app
        let content = try app.window.contentView.b6Unwrap("content")
        func find(_ view: NSView) -> ToolboxPopUpButton? {
            if let found = view as? ToolboxPopUpButton { return found }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        let toolbox = try find(content).b6Unwrap("the Toolbox")
        try expect(toolbox.accessibilityRole() == .menuButton && toolbox.accessibilityLabel() == "Toolbox" && toolbox.accessibilityValue() as? String == "Commands",
                   "A menu button named Toolbox whose value is the constant Commands (\(String(describing: toolbox.accessibilityRole())), \(String(describing: toolbox.accessibilityValue())))")
        let rows = try toolbox.menu.b6Unwrap("the rows").items.filter { !$0.isSeparatorItem }
        let bare = rows.filter { $0.image == nil }.map(\.title)
        try expect(bare.isEmpty && rows.contains { $0.title == "Filled Shapes" } && rows.contains { $0.title == "Shadow" }, "Every row, the two check-mark toggles included, has an icon (without: \(bare))")
        try expect(Set(rows.compactMap { $0.action.map(NSStringFromSelector) }).count == rows.count, "…and every row is its own command")
        var opened: (NSMenu, NSPoint)?
        toolbox.popUpHandler = { opened = ($0, $1) }
        toolbox.performClick(nil)
        let origin = try opened.b6Unwrap("the open request").1
        try expect(opened?.0 === toolbox.menu && toolbox.lastPopUpOrigin == origin && (toolbox.isFlipped ? origin.y > toolbox.bounds.maxY : origin.y < toolbox.bounds.minY),
                   "A click opens the rows below the button, not over it (\(origin) for \(toolbox.bounds))")
        opened = nil
        toolbox.keyDown(with: try NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49).b6Unwrap("a key event"))
        try expect(opened != nil, "Space opens it from the keyboard")
        opened = nil
        _ = toolbox.accessibilityPerformPress()
        try expect(opened != nil, "VoiceOver's press opens it")
    }

    // MARK: F-J6-010

    private static func b6OneSizeFormat() throws {
        let size = CGSize(width: 2560, height: 1800)
        try expect(PixelSizeText.text(size) == "2560 × 1800" && PixelSizeText.text(CGSize(width: 1444.285714, height: 1011)) == "1444 × 1011" && PixelSizeText.text(CGSize(width: 0.2, height: .nan)) == "Unknown size",
                   "The formatter writes whole pixels without grouping")
        try expect(HistoryBrowser.sizeText(for: size) == PixelSizeText.text(size), "History Details uses it")
        try expect(ExportAccessoryPreview(byteCount: 10, size: size).dimensionsLabel == "Dimensions: 2560 × 1800 pixels", "The Export panel uses it (\(ExportAccessoryPreview(byteCount: 10, size: size).dimensionsLabel))")
        let fixture = try Fixture(), app = fixture.app
        try b6Large(app, size: CGSize(width: 2560, height: 1800))
        app.dragOriginalControl.state = .on; app.updateDragPreview()
        try expect(app.dragSizeLabel.stringValue.hasPrefix("2560 × 1800 · PNG"), "The title uses it (\(app.dragSizeLabel.stringValue))")
    }
}

extension Optional {
    func b6Unwrap(_ what: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing \(what)") }
        return self
    }
}
#endif
