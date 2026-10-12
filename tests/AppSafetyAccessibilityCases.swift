// OSN-060 and OSN-062 on the main window: the key-view loop, the Focus Toolbar command, the VoiceOver labels, the announcement call sites and
// the G10 audit of the main window and its menus. The walker itself is tests/AccessibilityAudit.swift; VoiceOver speech is a manual pass.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var accessibilityCases: [(String, () throws -> Void)] {
        [
            ("G10: the main window, the main menu and the status-item menu have no accessibility violations, in every upload state", mainWindowAudit),
            ("Tools, Upload, Toolbox, the status item and the status line carry their VoiceOver names and roles", mainWindowLabels),
            ("The Size pill is a slider named Drawing size with a whole-number value, one-preset steps and a Show size options action; its popover track agrees", mainWindowSizePill),
            ("Key-view loop: top bar left to right, the canvas, then the bottom bar left to right; walking it visits every control once and returns", mainWindowKeyLoop),
            ("Focus Toolbar (Window menu) puts the keyboard on the first top-bar control; on the canvas Tab leaves it and Control-Tab swaps the pencil", mainWindowFocusToolbar),
            ("The Size and Color popovers close their own key-view loops", mainWindowPopoverLoops),
            ("Capture success, Frame on and off, Undo and Redo are announced; an Undo with nothing to undo is silent", mainWindowAnnouncements),
            ("Announcement inventory: every state change a blind user must hear, driven through Announcer.poster; announced rows post exactly the expected text, pending rows post nothing yet", announcementInventory)
        ] + accessibilitySurfaceCases
    }

    private static func chromeFor(_ app: AppDelegate) throws -> ModernEditorChrome {
        guard let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        chrome.accessibility = .none
        return chrome
    }

    private static func everyView(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(everyView) }

    /// Runs `body` with Full Keyboard Access on, whatever the host says, so the loop can be walked on any machine.
    private static func withFullKeyboardAccess<T>(_ body: () throws -> T) rethrows -> T {
        let saved = KeyboardNavigation.fullKeyboardAccess
        KeyboardNavigation.fullKeyboardAccess = { true }
        defer { KeyboardNavigation.fullKeyboardAccess = saved; KeyboardNavigation.toolbarFocusActive = false }
        return try body()
    }

    static func mainWindowAudit() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeFor(app)
        app.window.contentView?.layoutSubtreeIfNeeded()
        let url = URL(string: "https://example.com/a.png")!
        for (name, state) in [("idle", UploadState.idle), ("uploading", .uploading(name: "Shot")), ("success", .success(url: url, copied: true)), ("failure", .failure(message: "Server said no."))] {
            app.uploadState = state
            app.window.contentView?.layoutSubtreeIfNeeded()
            let report = AccessibilityAudit.audit(app.window, surface: "Main (\(name))")
            try expect(report.violations.isEmpty, "Main window (\(name)) has accessibility violations:\n\(report.description)")
            try expect(report.controls > 30 && report.labelled > 25, "The walker really looked at the main window (\(report.controls) controls, \(report.labelled) labelled)")
        }
        app.uploadState = .idle
        // The strip of titles is the system's (OS-owned in progress.md); every dropdown under it is ours and is audited.
        let bar = try NSApp.mainMenu.unwrapped("main menu")
        var menuReport = AccessibilityAudit.Report()
        for item in bar.items {
            let dropdown = try item.submenu.unwrapped("dropdown of a menu-bar title")
            try expect(!dropdown.title.isEmpty, "Every menu-bar title has a name")
            menuReport.merge(AccessibilityAudit.audit(dropdown, surface: "Main menu > \(dropdown.title)"))
        }
        try expect(menuReport.violations.isEmpty && menuReport.controls > 60, "The main menu's dropdowns have no violations (\(menuReport.controls) items):\n\(menuReport.description)")
        let statusReport = AccessibilityAudit.audit(app.makeStatusMenu(), surface: "Status-item menu")
        try expect(statusReport.violations.isEmpty && statusReport.controls >= 4, "The status-item menu has no violations (\(statusReport.controls) items):\n\(statusReport.description)")
        let toolbox = try everyView(try (app.window.contentView).unwrapped("content")).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Toolbox" }.unwrapped("Toolbox")
        let toolboxReport = AccessibilityAudit.audit(try toolbox.menu.unwrapped("Toolbox items"), surface: "Toolbox")
        try expect(toolboxReport.violations.isEmpty, "The Toolbox menu has no violations:\n\(toolboxReport.description)")
        _ = chrome
    }

    static func mainWindowLabels() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeFor(app)
        for tool in SketchTool.allCases {
            let button = try app.toolButtons[tool].unwrapped("\(tool) button")
            try expect(button.accessibilityLabel() == tool.rawValue.capitalized + " tool", "\(tool.rawValue): the label is '\(tool.rawValue.capitalized) tool' (\(button.accessibilityLabel() ?? "nil"))")
        }
        try expect(chrome.shareButton.accessibilityLabel() == "Upload image" && AppToolTip.text(for: chrome.shareButton)?.hasPrefix("Upload image") == true, "Upload is 'Upload image', label and tooltip")
        let toolbox = try everyView(try (app.window.contentView).unwrapped("content")).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Toolbox" }
        try expect(toolbox != nil, "The Toolbox is named 'Toolbox menu'")
        try expect(app.status.accessibilityRole() == .staticText, "The editor status line is static text (\(String(describing: app.status.accessibilityRole())))")
        try expect(StatusIcon.accessibilityLabel == "Show or hide OpenSnap", "The menu-bar item says what it does")
        let button = NSButton(); StatusIcon.configure(button)
        try expect(button.accessibilityLabel() == "Show or hide OpenSnap", "and the button carries it")
        try expect(app.dragExportView?.accessibilityLabel() == "Drag image to another app" && app.dragExportView?.accessibilityRole() == .button, "The drag well keeps its name and role")
        try expect(app.dragFormatToggle.accessibilityLabel() == "Image format" && app.dragFormatToggle.accessibilityChildren()?.count == 2, "The format toggle is a group with two children")
    }

    static func mainWindowSizePill() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try chromeFor(app)
        let pill = app.widthControl
        try expect(pill.accessibilityRole() == .slider && pill.accessibilityLabel() == "Drawing size", "The pill is a slider named Drawing size")
        app.canvas.strokeWidth = 9.38; app.syncDrawingControls()
        try expect((pill.accessibilityValue() as? NSNumber)?.doubleValue == 9, "Its value is the whole number 9, not 9.38 (\(String(describing: pill.accessibilityValue())))")
        let start = pill.doubleValue
        try expect(pill.accessibilityPerformIncrement() && abs(pill.doubleValue - (start + BezelSizeSlider.stepSize)) < 0.01 || pill.doubleValue == OriginalDrawingControls.maximum, "Increment steps one preset (\(start) to \(pill.doubleValue))")
        let up = pill.doubleValue
        try expect(pill.accessibilityPerformDecrement() && pill.doubleValue < up, "Decrement steps one preset down (\(up) to \(pill.doubleValue))")
        let actions = pill.accessibilityCustomActions() ?? []
        try expect(actions.map(\.name) == ["Show size options"], "It has one custom action, Show size options (\(actions.map(\.name)))")
        try expect(!pill.isPopoverShown, "The panel is closed before the action")
        let action = try actions.first.unwrapped("action")
        try expect(action.handler?() == true && pill.isPopoverShown, "The action opens the panel")
        let content = try pill.popoverContent.unwrapped("panel content")
        try expect(content.trackView.accessibilityRole() == .slider && content.trackView.accessibilityLabel() == "Size", "The panel track is a second slider, named Size")
        try expect((content.trackView.accessibilityValue() as? NSNumber)?.doubleValue == (pill.accessibilityValue() as? NSNumber)?.doubleValue, "and it reads the same value as the pill")
        try expect(content.presetButtons.map { $0.accessibilityLabel() ?? "" } == ["Size 2", "Size 4", "Size 7", "Size 9", "Size 12"], "The five presets are 'Size N' (\(content.presetButtons.map { $0.accessibilityLabel() ?? "" }))")
        pill.dismissPopover()
    }

    /// The controls the loop should visit, in the order a user expects: top bar left to right, the canvas, the bottom bar left to right.
    private static func expectedLoopOrder(_ app: AppDelegate, _ chrome: ModernEditorChrome) throws -> [NSView] {
        var order: [NSView] = [chrome.hideButton, try everyView(chrome.header).compactMap { $0 as? NSPopUpButton }.first.unwrapped("Toolbox"), chrome.photosButton, chrome.snapButton]
        order += SketchTool.allCases.compactMap { app.toolButtons[$0] }.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
        order += [app.paletteButton, app.widthControl, chrome.fontButton, app.canvas]
        order += [chrome.undoButton, app.zoomControl, chrome.resizeButton, chrome.saveButton, chrome.historyButton, app.dragFormatToggle]
        order += [try app.dragExportView.unwrapped("drag well"), chrome.shareButton]
        // Wipe is disabled on a blank canvas (it reads Blank), and a disabled control is never a tab stop.
        return order.filter { ($0 as? NSControl)?.isEnabled ?? true }
    }

    static func mainWindowKeyLoop() throws {
        try withFullKeyboardAccess {
            let fixture = try Fixture(), app = fixture.app
            let chrome = try chromeFor(app)
            let window = app.window!
            // A blank document has nothing to undo, so Undo is dimmed and, being disabled, not a tab stop (audit F-J1-020): give it a change.
            app.canvas.setBackgroundColor(.blue)
            try expect(window.autorecalculatesKeyViewLoop && window.initialFirstResponder === app.canvas, "The loop is recalculated by AppKit and starts on the canvas")
            window.setFrame(CGRect(origin: window.frame.origin, size: CGSize(width: 1280, height: 760)), display: false)
            window.contentView?.layoutSubtreeIfNeeded()
            window.recalculateKeyViewLoop()
            let start = chrome.hideButton
            var visited: [NSView] = [], next: NSView? = start
            repeat {
                guard let view = next else { throw Failure(description: "The loop ended before it came back to Hide after \(visited.count) stops") }
                visited.append(view)
                next = view.nextValidKeyView
            } while next !== start && visited.count < 200
            try expect(next === start, "Walking nextValidKeyView from Hide returns to Hide (after \(visited.count) stops)")
            try expect(Set(visited.map(ObjectIdentifier.init)).count == visited.count, "No control is visited twice")
            let expected = try expectedLoopOrder(app, chrome)
            let reachable = everyView(window.contentView!).filter { $0.canBecomeKeyView && !$0.isHiddenOrHasHiddenAncestor && !($0 is NSScroller) && !($0 is NSScrollView) }
            let missed = reachable.filter { view in !visited.contains { $0 === view } }
            try expect(missed.isEmpty, "Every control that can take the keyboard is in the loop; missed: \(missed.map { String(describing: type(of: $0)) + "#" + ($0.accessibilityLabel() ?? "") })")
            for view in expected {
                try expect(visited.contains { $0 === view }, "\(String(describing: type(of: view))) '\(view.accessibilityLabel() ?? "")' is in the loop")
            }
            func index(_ view: NSView) -> Int { visited.firstIndex { $0 === view } ?? -1 }
            let order = expected.map(index)
            try expect(order == order.sorted(), "The loop runs in reading order: top bar, canvas, bottom bar (indexes \(order))")
            try expect(index(chrome.hideButton) < index(chrome.snapButton) && index(chrome.fontButton) < index(app.canvas) && index(app.canvas) < index(chrome.undoButton) && index(chrome.undoButton) < index(chrome.shareButton),
                       "Hide < Snap < Font < canvas < Undo < Upload")
            // Hidden controls are left out; Frame mode brings Cancel in right after Snap.
            try expect(!visited.contains { $0 === chrome.cancelFrameButton } && !visited.contains { $0 === app.dragOriginalControl }, "Cancel (Frame only) and Original size (large shots only) are not in the loop while hidden")
            app.enterFrame(keepingAnnotations: false, manualFlags: [])
            window.contentView?.layoutSubtreeIfNeeded(); window.recalculateKeyViewLoop()
            try expect(chrome.snapButton.nextValidKeyView === chrome.cancelFrameButton, "In Frame mode Cancel follows Snap")
            app.cancelFrame()
        }
        // With Full Keyboard Access off the buttons, the format toggle and the drag well are not tab stops; the canvas still is.
        let saved = KeyboardNavigation.fullKeyboardAccess
        KeyboardNavigation.fullKeyboardAccess = { false }
        defer { KeyboardNavigation.fullKeyboardAccess = saved }
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeFor(app)
        app.window.contentView?.layoutSubtreeIfNeeded()
        try expect(!chrome.undoButton.canBecomeKeyView && !chrome.hideButton.canBecomeKeyView && !app.zoomControl.canBecomeKeyView, "Without Full Keyboard Access buttons and pop-ups stay out of the loop, as in any AppKit window")
        try expect(app.canvas.canBecomeKeyView && !app.dragFormatToggle.canBecomeKeyView && !(app.dragExportView?.canBecomeKeyView ?? true), "the canvas stays in it, the format toggle and the drag well follow the setting too")
    }

    static func mainWindowFocusToolbar() throws {
        try withFullKeyboardAccess {
            let fixture = try Fixture(), app = fixture.app
            let chrome = try chromeFor(app)
            let windowMenu = try NSApp.mainMenu.unwrapped("main menu").items.compactMap(\.submenu).first { $0.title == "Window" }.unwrapped("Window menu")
            let item = try windowMenu.items.first { $0.title == "Focus Toolbar" }.unwrapped("Window > Focus Toolbar")
            try expect(item.action == #selector(AppDelegate.focusToolbar) && item.keyEquivalent == "t" && item.keyEquivalentModifierMask == [.command, .option], "Focus Toolbar is Option-Command-T in the Window menu")
            app.window.makeFirstResponder(app.canvas)
            try expect(app.window.firstResponder === app.canvas, "The keyboard starts on the canvas")
            if let window = app.window as? AppSafetyWindow { window.simulatesVisibility = true; window.shown = true }
            _ = NSApp.sendAction(try item.action.unwrapped("action"), to: item.target, from: item)
            try expect(app.window.firstResponder === chrome.firstToolbarControl && chrome.firstToolbarControl === chrome.hideButton, "Focus Toolbar puts the keyboard on the first top-bar control (\(String(describing: app.window.firstResponder)))")
            // A sheet or a quit in progress refuses it.
            app.window.makeFirstResponder(app.canvas)
            app.terminationStarted = true
            app.focusToolbar()
            try expect(app.window.firstResponder === app.canvas, "While quitting it does nothing")
            app.terminationStarted = false
        }
        // With Full Keyboard Access off, as on most Macs, the command still works: it is what makes the bars take Tab, until the window stops being key.
        do {
            let saved = KeyboardNavigation.fullKeyboardAccess
            KeyboardNavigation.fullKeyboardAccess = { KeyboardNavigation.toolbarFocusActive }
            defer { KeyboardNavigation.fullKeyboardAccess = saved; KeyboardNavigation.toolbarFocusActive = false }
            let fixture = try Fixture(), app = fixture.app
            let chrome = try chromeFor(app)
            app.canvas.setBackgroundColor(.blue)   // Undo is dimmed on a blank document and a disabled button is never a tab stop (audit F-J1-020)
            if let window = app.window as? AppSafetyWindow { window.simulatesVisibility = true; window.shown = true }
            app.window.contentView?.layoutSubtreeIfNeeded(); app.window.recalculateKeyViewLoop()
            app.window.makeFirstResponder(app.canvas)
            try expect(chrome.hideButton.acceptsFirstResponder && !chrome.hideButton.canBecomeKeyView && !chrome.undoButton.canBecomeKeyView, "With Full Keyboard Access off the bars can take the keyboard but are not tab stops")
            app.focusToolbar()
            try expect(app.window.firstResponder === chrome.hideButton, "Focus Toolbar still reaches Hide (\(String(describing: app.window.firstResponder)))")
            try expect(chrome.hideButton.nextValidKeyView != nil && chrome.undoButton.canBecomeKeyView && chrome.hideButton.nextValidKeyView !== app.canvas, "and from there Tab walks the bars (Hide is followed by \(String(describing: chrome.hideButton.nextValidKeyView)))")
            app.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: app.window))
            try expect(!KeyboardNavigation.toolbarFocusActive && !chrome.undoButton.canBecomeKeyView, "When the window stops being key the bars go back to the system setting")
        }
        // On the canvas Tab moves the keyboard on (the bars are tab stops here) and Control-Tab is the pencil swap (audit F-J1-007). The
        // full walk, both ways, and the Full-Keyboard-Access-off exception are in AppSafetyAuditCases.
        let fixture = try Fixture(), app = fixture.app
        _ = try chromeFor(app)
        app.window.makeFirstResponder(app.canvas)
        func tab(_ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: app.window.windowNumber, context: nil,
                                 characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48).unwrapped("tab event")
        }
        app.setTool(.arrow)
        app.window.makeFirstResponder(app.canvas)
        try withFullKeyboardAccess {
            app.window.recalculateKeyViewLoop()
            app.canvas.keyDown(with: try tab(.control))
            try expect(app.canvas.tool == .brush && app.window.firstResponder === app.canvas, "Control-Tab on the canvas swaps to the pencil (\(app.canvas.tool))")
            app.canvas.keyDown(with: try tab(.control))
            try expect(app.canvas.tool == .arrow && app.window.firstResponder === app.canvas, "and back, with the keyboard still on the canvas")
            app.canvas.keyDown(with: try tab([]))
            let following = app.window.firstResponder as? NSView
            try expect(following != nil && following !== app.canvas && app.canvas.tool == .arrow, "Plain Tab moves the keyboard off the canvas without touching the tool (\(String(describing: following)))")
        }
    }

    static func mainWindowPopoverLoops() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try chromeFor(app)
        let content = SizePopoverContent(slider: app.widthControl)
        func walk(from start: NSView) -> [NSView] {
            var seen: [NSView] = [start], next = start.nextKeyView
            while let view = next, view !== start, seen.count < 50 { seen.append(view); next = view.nextKeyView }
            return seen
        }
        let sizeLoop = walk(from: content.trackView)
        try expect(sizeLoop.count == 6 && sizeLoop[0] === content.trackView && zip(sizeLoop.dropFirst(), content.presetButtons).allSatisfy { $0 === $1 }
                   && sizeLoop.last?.nextKeyView === content.trackView, "Size panel: track, then the five presets in order, then round again (\(sizeLoop.count) stops)")
        if let window = app.window as? AppSafetyWindow { window.simulatesVisibility = true; window.shown = true }
        app.presentDrawingColors(hover: false)
        let palette = try app.colorPanel.unwrapped("Color panel").container
        let swatches = app.presetColorButtons
        try expect(!swatches.isEmpty, "The Color panel has its presets")
        let colorLoop = walk(from: swatches[0])
        let custom = try everyView(palette).compactMap { $0 as? NSButton }.first { $0.tag == 110 }.unwrapped("Custom color…")
        try expect(colorLoop.count == swatches.count + 1 && zip(colorLoop, swatches).allSatisfy { $0 === $1 } && colorLoop.last === custom && custom.nextKeyView === swatches[0],
                   "Color panel: the swatches in order, then Custom color…, then round again (\(colorLoop.count) stops for \(swatches.count) swatches)")
        app.closeDrawingColors()
    }

    static func mainWindowAnnouncements() throws {
        let saved = (Announcer.poster, Announcer.clock, Announcer.target)
        defer { (Announcer.poster, Announcer.clock, Announcer.target) = saved; Announcer.reset() }
        var posted: [(String, NSAccessibilityPriorityLevel)] = [], now = 0.0
        Announcer.reset()
        Announcer.poster = { _, text, priority in posted.append((text, priority)) }
        Announcer.clock = { now += 2; return now }
        let fixture = try Fixture(), app = fixture.app
        _ = try chromeFor(app)
        app.undo()
        try expect(posted.isEmpty, "Undo with nothing to undo says nothing (\(posted))")
        app.receiveCapture(.success(try image(size: CGSize(width: 40, height: 30))), discardAlreadyApproved: true)
        try expect(posted.map(\.0) == ["Screenshot captured"], "A capture that lands in the editor is announced (\(posted))")
        posted = []
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        try expect(posted.map(\.0) == ["Frame mode on. Drag to choose the area to capture."], "Entering Frame is announced (\(posted))")
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        try expect(posted.count == 1, "Entering it again says nothing more")
        app.cancelFrame()
        try expect(posted.map(\.0).last == "Frame mode off" && posted.count == 2, "Leaving Frame is announced (\(posted))")
        app.cancelFrame()
        try expect(posted.count == 2, "Leaving it when it is not on says nothing")
        posted = []
        app.canvas.setBackgroundColor(.yellow)
        app.undo()
        try expect(posted.map(\.0) == ["Undid Background Color"], "Undo names what it undid (\(posted))")
        app.redo()
        try expect(posted.map(\.0) == ["Undid Background Color", "Redid Background Color"], "Redo names what it redid (\(posted))")
        app.redo()
        try expect(posted.count == 2, "Redo with nothing to redo says nothing")
        try expect(posted.allSatisfy { $0.1 == .medium }, "These are medium priority; only errors are high")
    }
}

// MARK: - Announcement inventory (OSN-062 WP2)
//
// ONE table of the state changes a blind user must hear. Each row is driven on a fresh Fixture through the Announcer.poster seam and
// compared with what was posted. A row is in exactly one state:
//   announced      the app posts it today: the posted [text, priority] sequence must equal `expected`, exactly
//   pendingWP3     it should be announced and is not yet: NOTHING may be posted. The row fails the moment something is, so a site that
//                  WP3 adds forces this row to be promoted to `announced` (a stale entry fails), and `fired` proves the event really ran
//   silentByDesign nothing is posted on purpose (an Undo with nothing to undo)
// Rows driven by another suite (the countdown and AppAlert have no Fixture) name it; rows that cannot be driven here say why.
// Breadth is a decision for the owner: delete a row to narrow what is announced; the integrity check only needs ids 1...23 to stay present.

extension AppSafetyTests {
    typealias Heard = (String, NSAccessibilityPriorityLevel)

    @MainActor
    final class AnnouncementRun {
        var posted: [Heard] = []
        var fixture: Fixture?
        var file: URL?
        var cleanups: [() -> Void] = []
        func app() throws -> AppDelegate {
            if fixture == nil { fixture = try Fixture() }
            return try fixture.unwrapped("the fixture").app
        }
    }

    struct AnnouncementRow {
        enum Status { case announced, pendingWP3, silentByDesign }
        enum Driver {
            case app(setup: (AnnouncementRun) throws -> Void, act: (AnnouncementRun) throws -> Void, fired: (AnnouncementRun) throws -> Bool)
            case suite(String)
            case notDriven(String)
        }
        let id: String, event: String, trigger: String
        let expected: [Heard]
        let status: Status
        let driver: Driver
    }

    private static func tinyImage() throws -> NSImage { try image(size: CGSize(width: 40, height: 30)) }

    private static func row(_ id: String, _ event: String, _ trigger: String, _ expected: [Heard], _ status: AnnouncementRow.Status,
                            setup: @escaping (AnnouncementRun) throws -> Void = { _ in }, fired: @escaping (AnnouncementRun) throws -> Bool = { _ in true },
                            act: @escaping (AnnouncementRun) throws -> Void) -> AnnouncementRow {
        AnnouncementRow(id: id, event: event, trigger: trigger, expected: expected, status: status, driver: .app(setup: setup, act: act, fired: fired))
    }
    private static func elsewhere(_ id: String, _ event: String, _ trigger: String, _ expected: [Heard], _ status: AnnouncementRow.Status, suite: String) -> AnnouncementRow {
        AnnouncementRow(id: id, event: event, trigger: trigger, expected: expected, status: status, driver: .suite(suite))
    }
    private static func undriven(_ id: String, _ event: String, _ trigger: String, _ expected: [Heard], _ status: AnnouncementRow.Status, why: String) -> AnnouncementRow {
        AnnouncementRow(id: id, event: event, trigger: trigger, expected: expected, status: status, driver: .notDriven(why))
    }

    /// {w} {h} are the canvas output size in whole pixels after the event, {file} the saved file's name.
    private static func filled(_ text: String, _ run: AnnouncementRun) -> String {
        guard let app = try? run.app() else { return text }
        let size = SketchDocument.wholePixels(app.canvas.outputSize)
        return text.replacingOccurrences(of: "{w}", with: String(Int(size.width))).replacingOccurrences(of: "{h}", with: String(Int(size.height)))
            .replacingOccurrences(of: "{file}", with: run.file?.lastPathComponent ?? "")
    }

    private static func withContent(_ run: AnnouncementRun) throws {
        try run.app().receiveCapture(.success(try tinyImage()), discardAlreadyApproved: true)
    }
    private static func withUndoable(_ run: AnnouncementRun) throws {
        try run.app().canvas.setBackgroundColor(.yellow)
    }
    private static func uploadURL() -> URL { URL(string: "https://example.com/pics/a.png")! }
    private static let failedCapture = NSError(domain: "OpenSnap", code: 9, userInfo: [NSLocalizedDescriptionKey: "The screen could not be captured."])
    private static let migrationNotice = "Your old settings were moved to OpenSnap."

    // swiftlint:disable function_body_length
    static var announcementTable: [AnnouncementRow] {
        [
            row("1", "Capture finished and opened in the editor", "receiveCapture(.success)", [("Screenshot captured", .medium)], .announced) { run in
                try run.app().receiveCapture(.success(try tinyImage()), discardAlreadyApproved: true) },
            row("1b", "Frame capture finished (frame mode ends first)", "receiveFrameCapture(.success)", [("Frame mode off", .medium), ("Screenshot captured", .medium)], .announced,
                setup: { try $0.app().enterFrame(keepingAnnotations: false, manualFlags: []) }) { run in
                let app = try run.app()
                app.receiveFrameCapture(.success(try tinyImage()), keepingAnnotations: false, expectedGeneration: app.documentGeneration) },
            row("2", "Capture cancelled (picker Escape)", "receiveCapture(.failure(NSUserCancelledError))", [("Capture cancelled", .medium)], .pendingWP3,
                fired: { _ in AppSafetyAlert.seen.isEmpty }) { run in
                try run.app().receiveCapture(.failure(AppSafetyCaptureCoordinator.cancellation)) },
            row("3", "Capture failed (error alert)", "receiveCapture(.failure(error))", [("Error: The screen could not be captured.", .high)], .pendingWP3,
                setup: { run in AppSafetyAlert.answers = [.init(title: failedCapture.localizedDescription, response: .alertFirstButtonReturn)]; _ = try run.app()
                    run.cleanups.append { AppSafetyAlert.reset() } },
                fired: { _ in AppSafetyAlert.seen == [failedCapture.localizedDescription] }) { run in
                try run.app().receiveCapture(.failure(failedCapture)) },
            row("4", "Picker opened (crosshair)", "startCapture(\"crosshair\")",
                [("Choose an area to capture. Drag to select, Space for the window under the pointer, Escape to cancel", .medium)], .pendingWP3,
                fired: { _ in AppSafetyCaptureCoordinator.requests.last == "crosshair" }) { run in
                try run.app().startCapture("crosshair") },
            elsewhere("5", "Countdown 3, 2, 1", "OriginalCaptureCountdown tick", [("3", .high), ("2", .high), ("1", .high)], .announced, suite: "OriginalCaptureCountdownTests"),
            elsewhere("6", "Countdown cancelled", "OriginalCaptureCountdown.cancel()", [("Capture cancelled", .medium)], .pendingWP3, suite: "OriginalCaptureCountdownTests"),
            row("7a", "Upload started", "uploadState = .uploading", [("Uploading Shot 1", .medium)], .announced) { run in
                try run.app().uploadState = .uploading(name: "Shot 1") },
            row("7b", "Upload retrying", "uploadState = .uploading (retry)", [("Retrying Shot 1", .medium)], .announced,
                setup: { run in UploadState.retryingName = "Shot 1"; run.cleanups.append { UploadState.retryingName = nil } }) { run in
                try run.app().uploadState = .uploading(name: "Shot 1") },
            row("8a", "Upload succeeded, link copied", "uploadState = .success(copied: true)", [("Upload complete. Link copied.", .medium)], .announced) { run in
                try run.app().uploadState = .success(url: uploadURL(), copied: true) },
            row("8b", "Upload succeeded, link not copied", "uploadState = .success(copied: false)", [("Upload complete", .medium)], .announced) { run in
                try run.app().uploadState = .success(url: uploadURL(), copied: false) },
            row("9", "Upload failed", "uploadState = .failure", [("Error: The server refused it", .high)], .announced) { run in
                try run.app().uploadState = .failure(message: "The server refused it\nSecond line is not read") },
            row("10", "Upload cancelled", "receivePublishing(.failure(NSUserCancelledError))", [("Upload cancelled", .medium)], .pendingWP3,
                setup: { run in run.cleanups.append { UploadNotice.clear() } }, fired: { _ in UploadNotice.text == "Upload cancelled" }) { run in
                try run.app().receivePublishing(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))) },
            row("11a", "Upload refused: one is already running", "publishImage() while busy", [("An upload is already running", .medium)], .announced,
                setup: { run in
                    let app = try run.app(), gate = DispatchSemaphore(value: 0)
                    app.publishing.uploader = { _, _, plan, _ in gate.wait(); return plan.publicURL ?? plan.remoteURL }
                    run.cleanups.append { gate.signal(); try? waitForMain("the blocked upload ends") { !app.publishing.isBusy } }
                    try withContent(run); app.publishImage()
                    try waitForMain("the first upload is running") { app.publishing.isBusy } },
                fired: { run in try run.app().publishing.isBusy }) { run in
                try run.app().publishImage() },
            row("11b", "Upload refused: no destination", "publishImage() with no destination", [(AppDelegate.noDestinationNotice, .medium)], .pendingWP3,
                setup: { run in let app = try run.app(); try configureDestinations(app, []); app.sharingSettingsPresenter = {} },
                fired: { run in try run.app().statusNotice == AppDelegate.noDestinationNotice }) { run in
                try run.app().publishImage() },
            row("12a", "Saved to file", "save()", [("Saved {file}", .medium)], .pendingWP3,
                setup: { run in let app = try run.app(); app.canvas.newBlank(size: NSSize(width: 200, height: 150)); run.file = run.fixture?.file("Row12a"); app.currentURL = run.file },
                fired: { run in try run.app().statusNotice?.hasPrefix("Saved ") == true }) { run in
                _ = try run.app().save() },
            row("12b", "Saved to History", "saveHistory()", [("Saved to History", .medium)], .pendingWP3,
                setup: { try withContent($0) }, fired: { run in try run.app().statusNotice == "Saved to History" }) { run in
                try run.app().saveHistory() },
            row("12c", "Nothing to save to History", "saveHistory() on a blank canvas", [(AppDelegate.nothingToSaveNotice, .medium)], .pendingWP3,
                setup: { try $0.app().canvas.newBlank(size: NSSize(width: 200, height: 150)) }, fired: { run in try run.app().statusNotice == AppDelegate.nothingToSaveNotice }) { run in
                try run.app().saveHistory() },
            undriven("12d", "Exported", "exportAs", [("Exported {file}", .medium)], .pendingWP3, why: "Export runs a modal NSSavePanel that the fixture cannot answer"),
            row("13a", "Undo", "undo()", [("Undid Background Color", .medium)], .announced, setup: { try withUndoable($0) }) { run in try run.app().undo() },
            row("13b", "Redo", "redo()", [("Redid Background Color", .medium)], .announced,
                setup: { run in try withUndoable(run); try run.app().undo() }) { run in try run.app().redo() },
            row("13c", "Undo with nothing to undo", "undo() on a fresh canvas", [], .silentByDesign) { run in try run.app().undo() },
            row("14", "Tool changed from the keyboard or a menu", "setTool(.brush)", [("Brush tool", .low)], .pendingWP3,
                fired: { run in try run.app().canvas.tool == .brush }) { run in
                try run.app().setTool(.brush) },
            undriven("15", "Image format toggled (PNG or JPG)", "the format radio", [], .silentByDesign,
                     why: "VoiceOver reads the radio change itself; GlassChoiceGroup posts valueChanged, asserted by the glass choices suites"),
            row("16a", "Frame mode on", "enterFrame()", [("Frame mode on. Drag to choose the area to capture.", .medium)], .announced) { run in
                try run.app().enterFrame(keepingAnnotations: false, manualFlags: []) },
            row("16b", "Frame mode off", "cancelFrame()", [("Frame mode off", .medium)], .announced,
                setup: { try $0.app().enterFrame(keepingAnnotations: false, manualFlags: []) }) { run in
                try run.app().cancelFrame() },
            row("17a", "Frame cannot start in full screen", "enterFrame() while full screen", [(MainWindowFrame.exitFullScreenForFrame, .high)], .pendingWP3,
                setup: { run in let app = try run.app(); let window = try (app.window as? AppSafetyWindow).unwrapped("the fixture window")
                    window.simulatesFullScreen = true
                    try expect(app.isFullScreen, "the fixture window reports full screen")
                    run.cleanups.append { window.simulatesFullScreen = false } },
                fired: { run in try run.app().statusNotice == MainWindowFrame.exitFullScreenForFrame }) { run in
                try run.app().enterFrame(keepingAnnotations: false, manualFlags: []) },
            row("17b", "Re-Snap needs the whole drawing visible", "performFrameSnap() with annotations kept", [("Error: Re-Snap needs the whole drawing visible. Reduce zoom or enlarge the window, then try again.", .high)], .pendingWP3,
                setup: { run in let app = try run.app(); try b6Large(app); app.enterFrame(keepingAnnotations: true, manualFlags: [])
                    app.setCanvasDisplayZoom(4, label: "Zoom")
                    try expect(!app.canvasIsFullyVisible, "the zoomed drawing does not fit the fixture window (visible \(app.canvas.visibleRect), bounds \(app.canvas.bounds))") },
                fired: { run in try run.app().statusNotice?.hasPrefix("Re-Snap needs") == true }) { run in
                try run.app().performFrameSnap() },
            undriven("17c", "Re-Snap: the drawing view changed during the capture", "performFrameSnap() completion", [("Error: The drawing view changed during Re-Snap. Position the frame and try again.", .high)], .pendingWP3,
                     why: "needs a held capture completion that also moves the view; WP3 drives it with the fake coordinator's held callbacks"),
            row("18a", "Actual Size on", "toggleActualSize()", [("Actual size on", .medium)], .pendingWP3,
                setup: { run in try b6Large(run.app()) }, fired: { run in try run.app().isActualSize }) { run in
                try run.app().toggleActualSize() },
            row("18b", "Actual Size off", "toggleActualSize() again", [("Actual size off", .medium)], .pendingWP3,
                setup: { run in let app = try run.app(); try b6Large(app); app.toggleActualSize() }, fired: { run in try !run.app().isActualSize }) { run in
                try run.app().toggleActualSize() },
            row("19a", "Crop applied", "canvas.crop(to:)", [("Cropped to {w} by {h}", .medium)], .pendingWP3,
                setup: { try $0.app().canvas.newBlank(size: NSSize(width: 400, height: 300)) },
                fired: { run in let size = try run.app().canvas.outputSize; return size.width == 200 && size.height == 100 }) { run in
                try run.app().canvas.crop(to: CGRect(x: 10, y: 10, width: 200, height: 100)) },
            row("19b", "Resize applied", "the Size sheet's Apply", [("Resized to {w} by {h}", .medium)], .pendingWP3,
                setup: { try $0.app().canvas.newBlank(size: NSSize(width: 400, height: 300)) },
                fired: { run in try run.app().canvas.outputSize.width == 200 }) { run in
                let session = try run.app().makeResizeSession().unwrapped("the resize session")
                session.state.edit(.width, text: "200")
                try expect(try session.commit(), "Apply 200 wide")
                session.cancel() },
            undriven("20a", "Deleting a web post", "Delete from Web confirmed", [("Deleting web post…", .medium)], .pendingWP3,
                     why: "needs a History entry bound to a web post and the Delete from Web sheet"),
            undriven("20b", "Web post deleted / refused", "historyRemoteDeletion result", [("Deleted from example.com. Cached copies of the link can persist for a while.", .medium), ("Error: …", .high)], .pendingWP3,
                     why: "same History flow as 20a; the success line already goes to the History footer"),
            row("21", "Migration notice at launch", "applicationDidFinishLaunching with OpenSnapMigration.launchNotice", [(migrationNotice, .high)], .pendingWP3,
                setup: { run in let saved = OpenSnapMigration.launchNotice; OpenSnapMigration.launchNotice = migrationNotice
                    run.cleanups.append { OpenSnapMigration.launchNotice = saved } },
                fired: { run in try run.app().status.stringValue == migrationNotice }) { run in
                _ = try run.app() },
            elsewhere("22a", "Alert sheet presented (title and message)", "AppAlert.present", [("Error: …", .high)], .pendingWP3, suite: "AppAlertTests"),
            elsewhere("22b", "Alert inline validation error", "AppAlert OK with a wrong entry", [("Error: Enter a number of seconds from 0 to 120.", .high)], .announced, suite: "AppAlertTests"),
            row("23", "Any status notice (generic path)", "postStatusNotice(text)", [("Row twenty-three probe notice", .medium)], .pendingWP3,
                fired: { run in try run.app().statusNotice == "Row twenty-three probe notice" }) { run in
                try run.app().postStatusNotice("Row twenty-three probe notice") }
        ]
    }
    // swiftlint:enable function_body_length

    static func announcementInventory() throws {
        let rows = announcementTable
        // Integrity: the table is the single source, so it must be well formed before any row is driven.
        try expect(Set(rows.map(\.id)).count == rows.count, "Inventory ids are unique")
        let numbers = Set(rows.compactMap { Int($0.id.prefix { $0.isNumber }) })
        try expect(numbers == Set(1...23), "Inventory covers state changes 1 through 23 (\(numbers.sorted()))")
        for row in rows {
            switch row.status {
            case .announced, .pendingWP3: try expect(!row.expected.isEmpty, "Row \(row.id) names the text it announces or must announce")
            case .silentByDesign: try expect(row.expected.isEmpty, "Row \(row.id) is silent by design, so it expects no text")
            }
            for (text, _) in row.expected { try expect(!text.lowercased().contains("ski" + "tch"), "Row \(row.id) text does not name the retired product") }
        }

        let saved = (Announcer.poster, Announcer.clock, Announcer.target)
        defer { (Announcer.poster, Announcer.clock, Announcer.target) = saved; Announcer.reset() }
        var driven = 0, announced = 0, pending = 0
        for row in rows {
            guard case .app(let setup, let act, let fired) = row.driver else { continue }
            let run = AnnouncementRun()
            var now = 0.0
            Announcer.reset()
            Announcer.clock = { now += 2; return now }
            Announcer.poster = { _, _, _ in }
            defer { run.cleanups.reversed().forEach { $0() }; Announcer.poster = { _, _, _ in }; AppSafetyAlert.reset() }
            AppSafetyAlert.reset()
            try setup(run)
            run.posted = []
            Announcer.poster = { _, text, priority in run.posted.append((text, priority)) }
            try act(run)
            let got = run.posted.map { "\($0.0) [\($0.1.rawValue)]" }
            let want = row.expected.map { "\(filled($0.0, run)) [\($0.1.rawValue)]" }
            try expect(try fired(run), "Row \(row.id) (\(row.event)): the event did not actually happen, so the row proves nothing")
            switch row.status {
            case .announced:
                try expect(got == want, "Row \(row.id) (\(row.event)) must post exactly \(want) but posted \(got)")
                announced += 1
            case .silentByDesign:
                try expect(got.isEmpty, "Row \(row.id) (\(row.event)) is silent by design but posted \(got)")
            case .pendingWP3:
                try expect(got.isEmpty, "Row \(row.id) (\(row.event)) is listed pending WP3 but now posts \(got): promote it to .announced with that text")
                pending += 1
            }
            driven += 1
        }
        let elsewhere = rows.filter { if case .suite = $0.driver { return true } else { return false } }.count
        let undrivenCount = rows.filter { if case .notDriven = $0.driver { return true } else { return false } }.count
        print("announcement inventory: \(rows.count) rows, \(driven) driven here (\(announced) announced, \(pending) pending WP3), \(elsewhere) in other suites, \(undrivenCount) not drivable")
    }
}

private extension Optional {
    func unwrapped(_ name: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing \(name)") }
        return self
    }
}
#endif
