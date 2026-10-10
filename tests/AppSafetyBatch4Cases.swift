// Audit fix batch 4: the App-side findings of the E2E journeys J2 and J3 (docs/design/e2e/findings.md).
// Run through tools/test-app-safety.sh; no window or panel is ever put on screen and nothing touches the network.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var batch4Cases: [(String, () throws -> Void)] {
        [
            ("A fitted screenshot is stored, titled, archived and resized in whole pixels, never a fraction of the fit scale (F-J3-006)", b4WholePixelSizes),
            ("A freshly opened History entry shows its own size in the title and status at once, not the previous document's (F-J4-006)", b4SizeTextOnOpen),
            ("Capture Shortcuts… opens Settings on the Capture tab; no second shortcut sheet exists (F-J2-020)", b4CaptureShortcutsSingleSurface),
            ("Resize wears the official Font Awesome Free resize glyph, not a ruler, and its menu symbol follows (F-J3-011)", b4ResizeGlyph),
            ("The zoom and Original size controls say what they measure in their tooltips and spoken help (F-J3-005)", b4ZoomAndOriginalLabels),
            ("The normal status line gives up format and bytes first, then the tool, and always keeps the state whole (F-J3-007)", b4StatusPriority),
            ("Delete from Web and Move to Trash put Cancel first: it is the default button and holds the initial focus (F-J4-005)", b4DestructiveSheetsFocusCancel)
        ]
    }

    // MARK: Sizes

    private static func b4WholePixelSizes() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let source = CGSize(width: 6001, height: 3999)
        app.canvas.newBlank(size: source)
        app.canvas.setBackground(try image(size: source))
        app.documentGeneration = UUID(); app.canvas.editingUndoManager.removeAllActions()
        app.adoptRasterViewport()
        let output = app.canvas.outputSize, capacity = try app.maximumNormalCanvas.b4Unwrap("the fit capacity")
        try expect(output.width < source.width && capacity.width < source.width, "The fixture needs a source larger than the screen (\(output), \(capacity))")
        func whole(_ size: CGSize) -> Bool { size.width == size.width.rounded() && size.height == size.height.rounded() }
        try expect(whole(output), "The fitted output is whole pixels (\(output.width) × \(output.height))")
        let exact = CGSize(width: source.width * min(capacity.width / source.width, capacity.height / source.height),
                           height: source.height * min(capacity.width / source.width, capacity.height / source.height))
        try expect(abs(output.width - exact.width) <= 0.5 && abs(output.height - exact.height) <= 0.5, "Rounded to the nearest pixel (\(output) vs \(exact))")
        // The size the editor titles, the History entry records and the Resize sheet opens with all agree on integers.
        app.updateDragPreview()
        let label = app.dragSizeLabel.stringValue
        let shown = app.dragAtOriginalSize ? source : output
        try expect(label.hasPrefix("\(Int(shown.width)) × \(Int(shown.height)) · "), "The status and title read whole pixels (\(label))")
        let snapshot = try app.historySnapshot()
        try expect(whole(snapshot.size) && snapshot.size == output, "The History entry records the whole output size (\(snapshot.size))")
        let session = try app.makeResizeSession().b4Unwrap("the resize session")
        try expect(session.state.widthText == String(Int(output.width)) && session.state.heightText == String(Int(output.height)),
                   "The Resize sheet opens on the whole output size (\(session.state.widthText) × \(session.state.heightText))")
        session.cancel()
        _ = store
    }

    private static func b4Snapshot(size: CGSize, title: String) throws -> HistoryStore.Snapshot {
        var document = SketchDocument(size: size)
        var text = SketchElement(kind: .text)
        text.text = title; text.rect = CGRect(x: 10, y: 10, width: 100, height: 40)
        document.elements = [text]
        return try HistoryStore.Snapshot(canvasData: document.encoded(), drawingDefaults: DrawingDefaults(values: [:]), preview: nil)
    }

    private static func b4SizeTextOnOpen() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let big = try store.archive(try b4Snapshot(size: CGSize(width: 900, height: 600), title: "Big"), name: "Big", action: .archived)
        app.canvas.newBlank(size: NSSize(width: 400, height: 300)); app.updateStatus(); app.updateDragPreview()
        try expect(app.dragSizeLabel.stringValue.hasPrefix("400 × 300 · PNG"), "The previous document reads 400 × 300 (\(app.dragSizeLabel.stringValue))")
        app.dirty = false
        app.openHistory(big)
        try expect(app.canvas.outputSize == CGSize(width: 900, height: 600), "The entry is open (\(app.canvas.outputSize))")
        try expect(app.dragSizeLabel.stringValue.hasPrefix("900 × 600 · PNG") && app.window.subtitle.hasPrefix("900 × 600 · PNG"),
                   "Title and size label are the new document's before the timer measures bytes: \(app.dragSizeLabel.stringValue) / \(app.window.subtitle)")
        try expect(app.status.stringValue.contains("900 × 600") || app.status.stringValue.contains("Saved"), "The status line never shows the old size (\(app.status.stringValue))")
        try expect(!app.status.stringValue.contains("400 × 300"), "The status line has dropped 400 × 300 (\(app.status.stringValue))")
    }

    private static func b4CaptureShortcutsSingleSurface() throws {
        let fixture = try Fixture(), app = fixture.app
        let item = try NSApp.mainMenu.b4Unwrap("main").items.compactMap(\.submenu).flatMap(\.items).first { $0.action == #selector(AppDelegate.shortcutSettings) }.b4Unwrap("Capture Shortcuts… item")
        try expect(app.validateMenuItem(item), "The item is enabled")
        app.shortcutSettings()
        let settings = try app.settingsController.b4Unwrap("Settings controller")
        try expect(settings.selectedIndex == SettingsWindowController.captureTabIndex && settings.window.title == "Capture", "The item opens Settings on the Capture tab (\(settings.window.title))")
        try expect(settings.capture.hotkeyForm.isDescendant(of: settings.capture.view) && app.window.attachedSheet == nil && settings.window.attachedSheet == nil,
                   "The shortcuts are the live form in that tab, with no sheet anywhere")
        settings.select(0); app.shortcutSettings()
        try expect(settings.selectedIndex == SettingsWindowController.captureTabIndex, "Used again from another tab it returns to Capture")
        app.closePreferences()
        let original = ProcessInfo.processInfo.environment["APP_SAFETY_EVIDENCE"]! + "/original-sources/"
        let source = try String(contentsOfFile: original + "GlobalHotkeys.swift", encoding: .utf8)
        try expect(!source.contains("GlobalHotkeySettingsPanel") && !source.contains("func showSettings") && !source.contains("Save applies your changes"),
                   "The duplicate sheet and its Save/Cancel form are gone from the sources")
    }

    private static func b4DestructiveSheetsFocusCancel() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let url = URL(string: "https://cdn.example.com/pics/a.png")!
        let bound = try store.archive(try historyDrawing("Bound"), name: "Bound", action: .shared, destination: url.absoluteString, remoteURL: url,
                                      remoteBinding: ["version": "1", "destinationSHA256": String(repeating: "a", count: 64), "publicURL": url.absoluteString])
        AppSafetyAlert.holdAnswers = true
        defer { AppSafetyAlert.holdAnswers = false }
        app.deleteHistoryRemote([bound]); app.removeHistory([bound], deleteFiles: true)
        let alerts = AppSafetyAlert.pending.map(\.alert)
        try expect(alerts.count == 2, "Both destructive questions are on screen (\(alerts.count))")
        for alert in alerts {
            try expect(alert.buttons.first?.role == .cancel && alert.buttons.last?.role == .destructive, "\(alert.title): Cancel first, the destructive action last")
            try expect(alert.panel.initialFirstResponder === alert.buttonViews[0] && alert.buttonViews[0].keyEquivalent == "\r" && alert.buttonViews[0].title == "Cancel",
                       "\(alert.title): Return and the initial focus are on Cancel")
            try expect(alert.buttonViews.last?.hasDestructiveAction == true && alert.buttonViews.last?.keyEquivalent != "\r", "\(alert.title): the destructive button is styled and is not the Return button")
        }
        b4Answer(.alertFirstButtonReturn); b4Answer(.alertFirstButtonReturn)
        try expect(store.entry(bound)?.remoteURL != nil && store.entries.count == 1, "Cancel on both removes nothing")
    }
    /// Whether a menu row draws an icon: an `image`, or (in the Toolbox pull-down, which does not draw item images) a text attachment in its title.
    static func b4RowHasIcon(_ item: NSMenuItem) -> Bool {
        if item.image != nil { return true }
        var found = false
        item.attributedTitle?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: item.attributedTitle?.length ?? 0)) { value, _, _ in
            if let attachment = value as? NSTextAttachment, attachment.image != nil { found = true }
        }
        return found
    }

    private static func b4Chrome(_ app: AppDelegate) throws -> ModernEditorChrome {
        guard let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        return chrome
    }

    private static func b4ResizeGlyph() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try b4Chrome(app)
        try expect(chrome.resizeButton.icon == .resizeDiagonal, "Resize… draws the resize glyph (\(String(describing: chrome.resizeButton.icon)))")
        try expect(chrome.resizeButton.icon != chrome.toolButtons["crop"]?.icon, "and it is not the Crop tool's glyph")
        try expect(chrome.resizeButton.iconSource == .fontAwesomeFree("up-right-and-down-left-from-center") || { if case .fontAwesome = chrome.resizeButton.iconSource { return true } else { return false } }(),
                   "It is the Font Awesome Free vector (or the Pro glyph in a dev build), not an SF Symbol (\(chrome.resizeButton.iconSource))")
        try expect(MenuSymbols.map[#selector(AppDelegate.resize)] == "arrow.up.right.and.arrow.down.left", "The Image › Resize… menu symbol is the matching resize arrows, not a ruler")
        try expect(FAIcon.resizeDiagonal.sfSymbolFallback == "arrow.up.right.and.arrow.down.left" && FAIcon.allCases.allSatisfy { $0.rawValue != "ruler-combined" }, "The SF fallback matches and the ruler is gone from the icon set")
    }

    private static func b4ZoomAndOriginalLabels() throws {
        let fixture = try Fixture(), app = fixture.app
        let zoomTip = AppToolTip.text(for: app.zoomControl) ?? ""
        try expect(zoomTip.contains("how large the drawing is shown") && zoomTip.contains("one image pixel per screen pixel"), "The zoom explains what its percentage is: \(zoomTip)")
        try expect(app.zoomControl.accessibilityHelp() == zoomTip, "Spoken help carries it too")
        app.setCanvasDisplayZoom(0.83, label: "Fit")
        let fitTip = AppToolTip.text(for: app.zoomControl) ?? ""
        try expect(fitTip.hasPrefix("Fit, 83%.") && fitTip.hasSuffix("one image pixel per screen pixel."), "A mode word leads the explanation: \(fitTip)")
        try expect(app.dragOriginalControl.title == "Original size" && app.dragOriginalControl.accessibilityLabel() == "Export at original size", "The box keeps its short title and is spoken as what it does")
        let tip = AppToolTip.text(for: app.dragOriginalControl) ?? ""
        try expect(tip.contains("own pixel size") && tip.contains("export") && tip.contains("upload"), "Its tooltip says it governs the dragged, exported and uploaded picture: \(tip)")
    }

    private static func b4StatusPriority() throws {
        let fixture = try Fixture(), app = fixture.app
        app.canvas.newBlank(size: NSSize(width: 800, height: 600)); app.setTool(.arrow); app.dirty = true
        app.updateDragPreview()
        let variants = app.status.variants
        try expect(variants.count == 5 && variants[0].components(separatedBy: " · ").count == 5, "The full line has tool, state, size, format and bytes (\(variants))")
        try expect(variants[1] == "Arrow · Unsaved changes · 800 × 600", "Format and bytes go first: \(variants[1])")
        try expect(variants[2] == "Unsaved changes · 800 × 600" && variants[3] == "Arrow · Unsaved changes" && variants[4] == "Unsaved changes",
                   "then the tool, then the size, and the state is the last thing standing: \(variants)")
        try expect(variants.dropFirst().allSatisfy { !$0.contains("PNG") && !$0.contains("KB") && !$0.contains("MB") && !$0.contains("bytes") }, "No shortened step carries the format or the bytes")
        try expect(variants.allSatisfy { $0.contains("Unsaved changes") }, "Every step keeps the state whole")
        app.dirty = false; app.updateStatus()
        try expect(app.status.variants.last == "Saved" && app.status.variants.dropFirst().allSatisfy { $0.contains("Saved") }, "A saved drawing is the same")
    }

    private static func b4Answer(_ response: NSApplication.ModalResponse) {
        let held = AppSafetyAlert.pending.removeFirst()
        withExtendedLifetime(held) { held.reply(response) }
    }
}

extension Optional {
    func b4Unwrap(_ what: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing \(what)") }
        return self
    }
}
#endif
