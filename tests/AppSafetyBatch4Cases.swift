// Audit fix batch 4: the App-side findings of the E2E journeys J2 and J3 (docs/design/e2e/findings.md).
// Run through tools/test-app-safety.sh; no window or panel is ever put on screen and nothing touches the network.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var batch4Cases: [(String, () throws -> Void)] {
        [
            ("A fitted screenshot is stored, titled, archived and resized in whole pixels, never a fraction of the fit scale (F-J3-006)", b4WholePixelSizes),
            ("The Resize sheet opens on the size the title shows, with or without Original size, and what is typed maps back to the output (R1-003)", b4ResizeMatchesTitle),
            ("A freshly opened History entry shows its own size in the title and status at once, not the previous document's (F-J4-006)", b4SizeTextOnOpen),
            ("Capture Shortcuts… opens Settings on the Capture tab; no second shortcut sheet exists (F-J2-020)", b4CaptureShortcutsSingleSurface),
            ("Resize… is a 20 pt text button that fits at 980 and 1440, and its menu symbol is its own (F-J3-011, R1-006)", b4ResizeGlyph),
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
        try expect(session.state.widthText == String(Int(shown.width)) && session.state.heightText == String(Int(shown.height)),
                   "The Resize sheet opens on the size the title shows (\(session.state.widthText) × \(session.state.heightText), title \(label))")
        session.cancel()
        _ = store
    }

    /// R1-003: the sheet's fields and the title agree whether or not "Original size" applies, and a size typed in the title's pixels lands in the output.
    private static func b4ResizeMatchesTitle() throws {
        let fixture = try Fixture(), app = fixture.app
        let source = CGSize(width: 2400, height: 1600)
        app.canvas.newBlank(size: source)
        app.canvas.setBackground(try image(size: source))
        app.documentGeneration = UUID(); app.canvas.editingUndoManager.removeAllActions()
        app.adoptRasterViewport()
        let output = app.canvas.outputSize
        try expect(app.isLargeShot && output.width < source.width, "The fixture is a large shot shown smaller than it is (\(output))")
        for ticked in [true, false] {
            app.dragOriginalControl.state = ticked ? .on : .off
            app.updateDragPreview()
            let title = ticked ? source : output
            try expect(app.dragAtOriginalSize == ticked && app.titlePixelSize == title && app.dragSizeLabel.stringValue.hasPrefix("\(Int(title.width)) × \(Int(title.height)) · "),
                       "Ticked \(ticked): the title reads \(title) (\(app.dragSizeLabel.stringValue))")
            let session = try app.makeResizeSession().b4Unwrap("the resize session")
            try expect(session.state.displayWidthText == String(Int(title.width)) && session.state.displayHeightText == String(Int(title.height)),
                       "Ticked \(ticked): the sheet opens on the title's \(Int(title.width)) × \(Int(title.height)) (\(session.state.displayWidthText) × \(session.state.displayHeightText))")
            session.state.edit(.width, text: String(Int(title.width) / 2))
            try expect(try session.preview(force: true), "Ticked \(ticked): half the title width previews")
            let half = app.canvas.outputSize
            if ticked {
                // The fields are the picture's own pixels, so half of them is a picture half as big (R2-002); what is shown follows.
                try expect(app.canvas.canvasSize == CGSize(width: source.width / 2, height: source.height / 2),
                           "Ticked: half of the title's pixels is a picture half as big (\(app.canvas.canvasSize))")
            } else {
                try expect(abs(half.width - output.width / 2) <= 1 && abs(half.height - output.height / 2) <= 1,
                           "Unticked: half of the shown pixels is half the output (\(half), output \(output))")
            }
            session.cancel()
            try expect(app.canvas.outputSize == output, "Ticked \(ticked): Cancel restores the output (\(app.canvas.outputSize))")
            let again = try app.makeResizeSession().b4Unwrap("a second resize session")
            try expect(try again.state.submission().size == title, "Ticked \(ticked): Apply without a change submits exactly the title's size (\(try again.state.submission().size))")
            try expect(SketchDocument.wholePixels(CGSize(width: 1516.5, height: 1011.4)) == CGSize(width: 1517, height: 1011), "wholePixels is the half-up rule the Resize sheet shares")
            again.cancel()
        }
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
        // The title bar carries the size, so the footer does not repeat it; in full screen the title bar is gone and the footer carries it.
        try expect(!app.status.stringValue.contains("×") && app.status.stringValue.hasSuffix("Saved"), "With the title bar up the footer is the tool and the state only (\(app.status.stringValue))")
        let window = try (app.window as? AppSafetyWindow).b4Unwrap("isolated window")
        window.simulatesFullScreen = true
        defer { window.simulatesFullScreen = false }
        app.refreshStatusText()
        try expect(app.status.stringValue.contains("900 × 600") && !app.status.stringValue.contains("400 × 300"), "In full screen the footer shows the new size and never the old one (\(app.status.stringValue))")
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
        // One surface that applies as it is edited: the tab has Clear All and no Save, Cancel, Disable All or Reset Defaults.
        func titles(_ view: NSView) -> [String] { ((view as? NSButton).map { [$0.title] } ?? []) + view.subviews.flatMap(titles) }
        let captureTab = titles(settings.capture.view)
        try expect(captureTab.contains("Clear All") && Set(captureTab).isDisjoint(with: ["Save", "Cancel", "Disable All", "Reset Defaults"]),
                   "The Capture tab applies edits as they are made, so it has no Save or Cancel (\(captureTab))")
        // R1-022: with a sheet up the Settings commands are off in the menu instead of enabled and silent, and calling them changes nothing.
        let window = try (app.window as? AppSafetyWindow).b4Unwrap("isolated window")
        let commands = [#selector(AppDelegate.shortcutSettings), #selector(AppDelegate.sharingSettings), #selector(AppDelegate.showPreferences)]
        let menuItems = try NSApp.mainMenu.b4Unwrap("main").items.compactMap(\.submenu).flatMap(\.items)
        try expect(commands.allSatisfy { command in menuItems.first { $0.action == command }.map { app.validateMenuItem($0) } == true }, "With nothing else asking a question, Settings, Sharing Settings… and Capture Shortcuts… are enabled")
        window.simulatedSheet = AppSafetyWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        defer { window.simulatedSheet = nil }
        try expect(commands.allSatisfy { command in menuItems.first { $0.action == command }.map { app.validateMenuItem($0) } == false }, "With a sheet on the editor they are all disabled")
        settings.select(0); app.shortcutSettings()
        try expect(settings.selectedIndex == 0, "…and choosing one anyway changes nothing")
    }

    private static func b4DestructiveSheetsFocusCancel() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let url = URL(string: "https://cdn.example.com/pics/a.png")!
        let bound = try store.archive(try historyDrawing("Bound"), name: "Bound", action: .shared, destination: url.absoluteString, remoteURL: url,
                                      remoteBinding: try b3cRealBinding(app, url: url))
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
    /// Whether a menu row draws an icon: it carries an image (every menu now draws item images, the Toolbox included).
    static func b4RowHasIcon(_ item: NSMenuItem) -> Bool { item.image != nil }

    private static func b4Chrome(_ app: AppDelegate) throws -> ModernEditorChrome {
        guard let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        return chrome
    }

    private static func b4ResizeGlyph() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try b4Chrome(app)
        let content = try (app.window.contentView).b4Unwrap("content view")
        // R1-006: the diagonal-arrows glyph read as "expand" or "full screen", so the command wears its name.
        try expect(chrome.resizeButton.visibleTitle == "Resize…" && chrome.resizeButton.icon == nil && chrome.resizeButton.accessibilityLabel() == "Resize…",
                   "Resize… is a text button with no glyph (\(chrome.resizeButton.visibleTitle), icon \(String(describing: chrome.resizeButton.icon)))")
        try expect((chrome.resizeButton.font?.pointSize ?? 0) >= 20, "and its text is 20 pt (\(chrome.resizeButton.font?.pointSize ?? 0))")
        for width in [ModernEditorChrome.minimumWindowWidth, 1440] as [CGFloat] {
            let frame = app.window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: content.bounds.height))
            app.window.setFrame(NSRect(origin: app.window.frame.origin, size: frame.size), display: false)
            content.layoutSubtreeIfNeeded(); app.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: app.window)); content.layoutSubtreeIfNeeded()
            let box = chrome.resizeButton.convert(chrome.resizeButton.bounds, to: content), title = (chrome.resizeButton.visibleTitle as NSString).size(withAttributes: [.font: chrome.resizeButton.font as Any])
            try expect(content.bounds.contains(box) && box.width >= title.width + 16 && box.height >= DesignTokens.Size.hitMin,
                       "\(Int(width)): the label fits its button with room, unclipped, and is a full-size target (\(box.size), text \(title))")
        }
        try expect(MenuSymbols.map[#selector(AppDelegate.resize)] == "square.resize" && FAIcon.allCases.allSatisfy { $0.rawValue != "ruler-combined" && $0.rawValue != "up-right-and-down-left-from-center" },
                   "The Image › Resize… menu symbol is its own, and neither the ruler nor the ambiguous arrows remain in the icon set")
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
        app.footerShowsPictureFactsOverride = true   // full screen: no title bar, so the footer carries the size
        app.updateDragPreview()
        let variants = app.status.variants
        try expect(variants.count == 6 && variants[0].components(separatedBy: " · ").count == 5, "The full line has tool, state, size, format and bytes (\(variants))")
        try expect(variants[1] == "Arrow · Unsaved changes · 800 × 600", "Format and bytes go first: \(variants[1])")
        try expect(variants[2] == "Unsaved changes · 800 × 600" && variants[3] == "Arrow · Unsaved changes" && variants[4] == "Unsaved changes" && variants[5] == "Unsaved",
                   "then the tool, then the size, and the state is the last thing standing, in one word at the narrowest: \(variants)")
        try expect(variants.dropFirst().allSatisfy { !$0.contains("PNG") && !$0.contains("KB") && !$0.contains("MB") && !$0.contains("bytes") }, "No shortened step carries the format or the bytes")
        try expect(variants.allSatisfy { $0.contains("Unsaved") }, "Every step keeps the state whole (the last in one word)")
        app.dirty = false; app.updateStatus()
        app.footerShowsPictureFactsOverride = nil
        app.updateStatus()
        try expect(app.status.variants == ["Arrow · Saved", "Saved"], "With the title bar up the footer is just tool and state (\(app.status.variants))")
        app.footerShowsPictureFactsOverride = true
        app.updateStatus()
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
