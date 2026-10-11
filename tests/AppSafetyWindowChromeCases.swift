// OSN-043 window chrome and OSN-041 app-owned alerts, on the real AppDelegate launch.
// The alert panel itself (fonts, keys, sheet) is tested in AppAlertTests.swift; these cases test what the app does with it.
// Frame memory: tests inject a TestDefaults suite and their own autosave name, never the real "OpenSnap.Main" entry.
#if APP_SAFETY_TESTS
import AppKit
import UniformTypeIdentifiers

extension AppSafetyTests {
    static var windowChromeCases: [(String, () throws -> Void)] {
        [
            ("The window title is the document name (Untitled when new), the proxy icon follows the file, and the subtitle is the live size", windowTitleFollowsDocument),
            ("The title bar has no separator and shows the window surface colour; Frame mode makes it opaque and leaving restores it", windowTitlebarReadsAsChrome),
            ("A fresh window opens centred at 1120 x 780; a saved frame is restored and centring is skipped; the key format is AppKit's", windowFrameAutosave),
            ("The minimum window is the width the live bars need (never below 980) and 640 high; the worst case does not depend on Frame mode", windowMinimumIsMeasured),
            ("Full screen is on for the window, refused by Frame with a status line, switched off while Frame is up, and ends Frame if it starts anyway", windowFullScreenExcludesFrame),
            ("In full screen the status-item zoom is off and the window is not fitted to a document", windowFullScreenQuietsZoomAndFitting),
            ("Every document-scoped question is a sheet on the document window: Discard, Rename, History confirmations and errors", windowAlertsAreSheetsOnTheDocumentWindow),
            ("One Discard question at a time from New, Open and captures; answering Cancel keeps the document", windowDiscardQuestionIsSingle),
            ("Quit during an open Discard question asks its own question: Cancel keeps the app, Don't Save approves and the answer reaches AppKit later", windowQuitDuringOpenAlert),
            ("Sheets that end without a button (endSheet, panel close) answer Cancel, free the question bookkeeping, and Quit still completes", windowQuitAfterSheetsEndWithoutAnswer),
            ("Quit with Save: the save panel cancelling refuses the quit; the answer arrives after applicationShouldTerminate returned", windowQuitSaveRefused),
            ("An error raised while a Discard sheet is open stacks on it instead of waiting out of sight", windowErrorStacksOnOpenSheet),
            ("Rename and Timed Snapshot prompts take their text from the sheet's field and ignore Cancel", windowPromptsTakeSheetText),
            ("Timed Snapshot and Snap from Link keep their sheet open with an Error: line for a wrong entry instead of closing without a word (F-J5-001)", windowPromptsExplainWrongEntries),
            ("Save to History on a blank canvas says there is nothing to save (F-J5-003)", windowSaveHistoryBlankSaysSo)
        ]
    }

    private static func chromeOf(_ app: AppDelegate) throws -> ModernEditorChrome {
        guard let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        return chrome
    }

    /// An app with its own frame memory: a unique autosave name and an in-memory defaults suite.
    private static func rememberingFixture(frame saved: String? = nil) throws -> (Fixture, name: String, defaults: UserDefaults) {
        let name = "OpenSnap.Main.test-" + UUID().uuidString
        let defaults = TestDefaults(name: name)
        if let saved { defaults.set(saved, forKey: MainWindowFrame.defaultsKey(name)) }
        let fixture = try Fixture { $0.frameAutosaveName = name; $0.frameDefaults = defaults }
        return (fixture, name, defaults)
    }

    // MARK: title, proxy icon, subtitle

    private static func windowTitleFollowsDocument() throws {
        let fixture = try Fixture(), app = fixture.app
        try expect(app.window.title == "Untitled" && app.window.title != DesignTokens.Brand.name, "A new document is titled Untitled, not with the app's name (\(app.window.title))")
        try expect(app.window.representedURL == nil && app.currentURL == nil, "A new document has no file behind it")
        // Save As: the file becomes the document, so the title and the proxy icon follow it.
        let target = fixture.file("Report")
        AppSafetyFilePanel.answers.append(.init(response: .OK, url: target))
        _ = try editor(app, text: "x"); app.canvas.commitPendingTextEditing()
        app.saveAs()
        let stem = target.deletingPathExtension().lastPathComponent
        try expect(app.currentURL == target && app.window.representedURL == target, "Save As points the proxy icon at the new file")
        try expect(app.window.title == stem, "Save As titles the window with the file's name (\(app.window.title) vs \(stem))")
        // Rename changes the name, not the file.
        AppSafetyAlert.answers.append(.init(title: "Rename", response: .alertFirstButtonReturn, text: "Quarterly"))
        app.renameDocument()
        try expect(app.window.title == "Quarterly" && app.window.representedURL == target, "Rename retitles the window and leaves the proxy icon on the same file (\(app.window.title))")
        AppSafetyAlert.answers.append(.init(title: "Rename", response: .alertFirstButtonReturn, text: "   "))
        app.renameDocument()
        try expect(app.window.title == "Quarterly", "A blank name is ignored")
        // New clears both.
        app.dirty = false
        app.newFile()
        try expect(app.window.title == "Untitled" && app.window.representedURL == nil && app.currentURL == nil, "New returns to Untitled with no proxy icon (\(app.window.title))")
        // Open: title and proxy icon come from the file.
        app.openURL(target)
        try expect(app.window.title == stem && app.window.representedURL == target, "Open titles the window with the file and shows it as the proxy icon (\(app.window.title))")
        // An empty name never leaves the title bar blank.
        app.nameField.stringValue = "  "
        try expect(app.window.title == "Untitled", "A blank document name shows Untitled")
        // The subtitle is the live size: W × H · bytes.
        app.newFile()
        app.updateDragPreview()
        let subtitle = app.window.subtitle
        try expect(subtitle == app.dragSizeLabel.stringValue && subtitle.range(of: #"^\d+ × \d+ · .+"#, options: .regularExpression) != nil,
                   "The subtitle is the size and the byte count (\(subtitle))")
        let before = app.canvas.canvasSize
        app.canvas.newBlank(size: NSSize(width: 640, height: 480)); app.updateDragPreview()
        try expect(before != NSSize(width: 640, height: 480) && app.window.subtitle.hasPrefix("640 × 480 · "), "The subtitle follows the document's size (\(app.window.subtitle))")
        try expect(app.status.stringValue.contains("Saved") || app.status.stringValue.contains("Unsaved"), "The status line keeps its own adaptive text (\(app.status.stringValue))")
    }

    private static func windowTitlebarReadsAsChrome() throws {
        let fixture = try Fixture(), app = fixture.app
        try expect(app.window.titlebarSeparatorStyle == .none, "No separator line under the title bar")
        try expect(app.window.backgroundColor == DesignTokens.Palette.Surface.window, "The window background is the chrome surface colour")
        try expect(app.window.titlebarAppearsTransparent, "Outside Frame the title bar shows the window surface colour, so there is no grey strip")
        try expect(!app.window.styleMask.contains(.fullSizeContentView), "Content does not run under the title bar (a full-size content view would cost 78 pt beside the traffic lights)")
        app.frameSnap()
        try expect(app.window.backgroundColor == .clear && !app.window.titlebarAppearsTransparent, "Frame clears the window and makes the title bar opaque (its title backdrop depends on it)")
        app.leaveFrame()
        try expect(app.window.backgroundColor == DesignTokens.Palette.Surface.window && app.window.titlebarAppearsTransparent, "Leaving Frame restores the surface colour and the seamless title bar")
    }

    // MARK: size and memory

    private static func windowFrameAutosave() throws {
        // A fresh window: default content size, centred once, named for autosave.
        let (fresh, name, _) = try rememberingFixture()
        let window = fresh.app.window as! AppSafetyWindow
        try expect(window.centerCalls == 1, "With no saved frame the window is centred (\(window.centerCalls))")
        try expect(window.frameAutosaveName == name, "The window is registered for autosave under the injected name")
        let content = window.contentRect(forFrameRect: window.frame).size
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1120, height: 812)
        try expect(content == MainWindowFrame.defaultContentSize(fittingScreen: visible), "A fresh window opens at the default content size \(MainWindowFrame.defaultContentSize(fittingScreen: visible)) (is \(content))")
        try expect(MainWindowFrame.defaultContentSize == NSSize(width: 1120, height: 780), "The default is 1120 x 780")
        try expect(MainWindowFrame.defaultContentSize(fittingScreen: NSSize(width: 800, height: 600)) == NSSize(width: 800, height: 568), "A small screen brings the default down to what fits")
        // A saved frame: restored, and centring skipped.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let target = NSRect(x: screen.minX + 37, y: screen.minY + 53, width: 1111, height: 701)
        let reference = NSWindow(contentRect: target, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        reference.setFrame(target, display: false)
        let (restored, restoredName, _) = try rememberingFixture(frame: reference.frameDescriptor)
        let back = restored.app.window as! AppSafetyWindow
        try expect(back.centerCalls == 0, "A saved frame means the window is not centred over it (\(back.centerCalls) centre calls)")
        try expect(abs(back.frame.width - target.width) < 1 && abs(back.frame.height - target.height) < 1 && abs(back.frame.minX - target.minX) < 1 && abs(back.frame.minY - target.minY) < 1,
                   "The saved frame comes back: \(back.frame) vs \(target)")
        try expect(back.frameAutosaveName == restoredName, "The restored window keeps saving under its name")
        // The key the app looks under is the one AppKit writes: save a frame with the real API and read it back by that key.
        // The app-safety binary's standard defaults are a throwaway domain named for the process, removed when the run ends.
        let probe = "OpenSnap.Main.keyprobe-" + UUID().uuidString
        defer { NSWindow.removeFrame(usingName: probe) }
        reference.saveFrame(usingName: probe)
        try expect(MainWindowFrame.savedFrame(named: probe, in: .standard) == reference.frameDescriptor,
                   "AppKit stores a frame under \(MainWindowFrame.defaultsKey(probe)); the app reads the same key")
        try expect(MainWindowFrame.savedFrame(named: probe + "-other", in: .standard) == nil && MainWindowFrame.autosaveName == "OpenSnap.Main", "An unsaved name has no frame; the shipped name is OpenSnap.Main")
        // The default Fixture does not remember, so no test run writes the real entry.
        let plain = try Fixture()
        try expect(plain.app.frameAutosaveName == nil && plain.app.window.frameAutosaveName.isEmpty, "A fixture without configuration registers no autosave name")
    }

    private static func windowMinimumIsMeasured() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeOf(app)
        typealias M = GlassChrome.Metrics
        // The oracle is the arithmetic from the metrics, as in the width budget of GlassChromeTests, not the code under test.
        let pad = 2 * M.groupInset, spacing = M.groupSpacing, gap = M.groupGap
        let tools = CGFloat(app.toolButtons.count)
        let top = (pad + 2 * M.iconButton.width + M.toolboxButton.width + 2 * spacing) + (pad + M.primaryButton.width + spacing + M.iconButton.width)
            + (pad + tools * M.toolButton.width + (tools - 1) * spacing) + (pad + 3 * M.iconButton.width + 2 * spacing) + 3 * gap
        let required = chrome.requiredWindowWidth()
        // The bottom bar at its worst: the Original size toggle on the View plate and a status that keeps 120 pt, with Resize… wearing its name.
        app.window.contentView?.layoutSubtreeIfNeeded()
        // The minimum window is narrower than 1100 pt, where the PNG | JPG toggle is the compact one, so that is the width it is measured at.
        let compactFormat = SegmentedToggle(titles: app.dragFormatToggle.titles); compactFormat.isCompact = true
        let zoomWidth = (app.zoomControl.superview?.frame.width ?? 0), formatWidth = ceil(compactFormat.intrinsicContentSize.width)
        let icons = pad + 2 * M.iconButton.width + spacing
        let bottom = icons + (pad + zoomWidth + spacing + chrome.resizeButton.frame.width + spacing + app.dragOriginalControl.fittingSize.width) + icons + (pad + formatWidth + 2 * spacing + 2 * M.iconButton.width)
            + 4 * gap + 120
        // The measured width (before the floor) is the wider of the Frame-mode top bar and that bottom bar; a metric or a group that changes moves it.
        try expect(abs(chrome.measuredWindowWidth() - (ceil(max(top, bottom)) + 24)) < 1, "The measured width \(chrome.measuredWindowWidth()) is the wider of the Frame-mode top bar (\(ceil(top))) and the bottom bar (\(ceil(bottom))) plus both margins")
        try expect(required == max(ModernEditorChrome.minimumWindowWidth, chrome.measuredWindowWidth()), "The required width is the measured one, floored at 980")
        try expect(required >= ModernEditorChrome.minimumWindowWidth, "Never below the 980 floor (\(required))")
        try expect(app.window.minSize.width == required && app.window.minSize.height == MainWindowFrame.minimumHeight && MainWindowFrame.minimumHeight == 640,
                   "The window's minimum is the measured width by the 640 pt height (\(app.window.minSize))")
        try expect(app.window.minSize.width == 980, "At 20 pt the measured minimum is the 980 floor today (\(app.window.minSize.width)); a change here must be a decision")
        chrome.frameMode = true
        try expect(chrome.requiredWindowWidth() == required, "The worst case is the same in Frame mode as out of it")
        chrome.frameMode = false
        try expect(chrome.requiredWindowWidth() == required, "...and after leaving it")
        let content = app.window.contentRect(forFrameRect: NSRect(origin: .zero, size: app.window.minSize)).height
        try expect(content == 608, "The minimum window is 608 pt of content under the 32 pt title bar (\(content))")
    }

    // MARK: full screen

    private static func windowFullScreenExcludesFrame() throws {
        let fixture = try Fixture(), app = fixture.app
        let window = app.window as! AppSafetyWindow
        try expect(window.collectionBehavior.contains(.fullScreenPrimary), "The editor can go full screen")
        // Refused in full screen.
        window.simulatesFullScreen = true
        app.status.stringValue = ""
        app.frameSnap()
        try expect(!app.frameMode && app.status.stringValue == "Exit full screen to use Frame", "Frame in full screen is refused with a line that says what to do (\(app.status.stringValue))")
        app.resnap()
        try expect(!app.frameMode, "Re-Snap is refused too")
        try expect(app.window.level == .normal && app.window.alphaValue == 1, "A refused Frame leaves the window alone")
        window.simulatesFullScreen = false
        // In Frame, full screen is off the table.
        app.frameSnap()
        try expect(app.frameMode && !window.collectionBehavior.contains(.fullScreenPrimary), "While Frame is up the window cannot enter full screen")
        app.leaveFrame()
        try expect(window.collectionBehavior.contains(.fullScreenPrimary), "Leaving Frame brings full screen back")
        // If it starts anyway (a stray toggle), Frame ends.
        app.frameSnap()
        app.windowWillEnterFullScreen(Notification(name: NSWindow.willEnterFullScreenNotification, object: window))
        try expect(!app.frameMode && window.collectionBehavior.contains(.fullScreenPrimary) && window.level == .normal && window.alphaValue == 1,
                   "Entering full screen ends Frame and restores the window")
        app.windowWillEnterFullScreen(Notification(name: NSWindow.willEnterFullScreenNotification, object: NSWindow()))
        try expect(!app.frameMode, "A notification from another window changes nothing")
    }

    private static func windowFullScreenQuietsZoomAndFitting() throws {
        let fixture = try Fixture(), app = fixture.app
        let window = app.window as! AppSafetyWindow
        let saved = AppSafetyAnimations.reduceMotion
        defer { AppSafetyAnimations.reduceMotion = saved }
        AppSafetyAnimations.reduceMotion = false
        try expect(app.animatesWindowZoom, "With motion allowed the status-item zoom animates")
        window.simulatesFullScreen = true
        try expect(!app.animatesWindowZoom && app.isFullScreen, "In full screen the zoom is off even with motion allowed")
        let frame = window.frame
        app.setWindowFrame(frame.insetBy(dx: 40, dy: 40))
        try expect(window.frame == frame, "A full-screen window is not fitted to a document")
        window.simulatesFullScreen = false
        app.setWindowFrame(frame.insetBy(dx: 0, dy: 0))
        try expect(app.animatesWindowZoom, "Out of full screen the zoom animates again")
    }

    // MARK: alerts are sheets

    private static func windowAlertsAreSheetsOnTheDocumentWindow() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try editor(app, text: "Unsaved")
        AppSafetyAlert.answers = [.init(title: "Save your drawing?", response: .alertSecondButtonReturn)]
        app.newFile()
        AppSafetyAlert.answers.append(.init(title: "Fake failure", response: .alertFirstButtonReturn))
        app.error(NSError(domain: "AppSafety", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fake failure"]))
        AppSafetyAlert.answers.append(.init(title: "Rename", response: .alertSecondButtonReturn))
        app.renameDocument()
        let store = try app.archiveStore()
        if let snapshot = try? app.historySnapshot() { _ = try store.archive(snapshot, name: "Sheet demo", action: .archived) }
        guard let id = store.entries.first?.id else { throw Failure(description: "A History entry is needed for the confirmations") }
        AppSafetyAlert.answers.append(.init(title: "Hide drawings from History?", response: .alertFirstButtonReturn))
        app.removeHistory([id], deleteFiles: false)
        AppSafetyAlert.answers.append(.init(title: "Move archived drawings to Trash?", response: .alertFirstButtonReturn))
        app.removeHistory([id], deleteFiles: true)
        try expect(AppSafetyAlert.seen == ["Save your drawing?", "Fake failure", "Rename", "Hide drawings from History?", "Move archived drawings to Trash?"],
                   "The app raised exactly these alerts: \(AppSafetyAlert.seen)")
        try expect(AppSafetyAlert.hosts.allSatisfy { $0 === app.window }, "Every one is presented on the document window")
        try expect(store.entries.contains { $0.id == id }, "Cancel on the History confirmations removes nothing")
        // No source path still reaches for NSAlert or runs an alert modally.
        let source = try String(contentsOfFile: ProcessInfo.processInfo.environment["APP_SAFETY_EVIDENCE"]! + "/original-sources/App.swift", encoding: .utf8)
        try expect(!source.contains("NSAlert") && source.components(separatedBy: "runModal()").count - 1 == 3,
                   "App.swift has no NSAlert; runModal is left only for the open, save and export panels")
    }

    private static func windowDiscardQuestionIsSingle() throws {
        let fixture = try Fixture(), app = fixture.app
        let text = try editor(app, text: "Keep me")
        let before = app.canvas.document
        AppSafetyAlert.holdAnswers = true
        app.newFile()
        try expect(AppSafetyAlert.pending.count == 1 && app.discardQuestionOpen && app.canvas.document == before, "New asks and waits; nothing has changed yet")
        app.newFile()
        app.openURL(fixture.file("Nowhere"))
        try expect(AppSafetyAlert.pending.count == 1, "New and Open again, while the question is open, do not stack more questions (\(AppSafetyAlert.pending.count))")
        let pending = AppSafetyAlert.pending.removeFirst()
        // The labels and order are NSAlert's: default Save, Cancel on Escape, Don't Save on Command-D.
        let buttons = pending.alert.buttonViews
        try expect(buttons.map(\.title) == ["Save", "Cancel", "Don\u{2019}t Save"] && buttons[0].keyEquivalent == "\r" && buttons[1].keyEquivalent == "\u{1b}"
                   && buttons[2].keyEquivalent == "d" && buttons[2].keyEquivalentModifierMask == .command, "Return, Escape and Command-D reach Save, Cancel and Don't Save")
        try expect(pending.alert.title == "Save your drawing?" && pending.alert.message == "This document has changes that have not been saved.", "The question and its message are unchanged")
        pending.reply(.alertSecondButtonReturn)
        try expect(!app.discardQuestionOpen && app.canvas.document == before && text.superview === app.canvas && app.dirty, "Cancel keeps the document and its live editor, and the question can be asked again")
        AppSafetyAlert.holdAnswers = false
        AppSafetyAlert.answers = [.init(title: "Save your drawing?", response: .alertThirdButtonReturn)]
        app.newFile()
        try expect(app.canvas.document != before && !app.dirty, "Don't Save lets New carry on")
        // The labels and order are NSAlert's: default Save, Cancel on Escape, Don't Save on Command-D.
    }

    private static func windowQuitDuringOpenAlert() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try editor(app, text: "Quit while asked")
        let before = app.canvas.document
        AppSafetyAlert.holdAnswers = true
        app.newFile()
        try expect(AppSafetyAlert.pending.count == 1 && AppSafetyTermination.replies.isEmpty, "The New question is open")
        // Quit now: its own question, answered later. AppKit is told to wait.
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater && AppSafetyTermination.replies.isEmpty, "Quit with a question open waits for the answer rather than deciding")
        try expect(AppSafetyAlert.pending.count == 2 && !app.terminationStarted && AppSafetyCaptureCoordinator.shutdownRequests == 0, "The Quit question is open beside the New one; no cleanup has started")
        let newQuestion = AppSafetyAlert.pending[0], quitQuestion = AppSafetyAlert.pending[1]
        // Cancel the Quit: the app stays, AppKit is told no.
        quitQuestion.reply(.alertSecondButtonReturn)
        try expect(AppSafetyTermination.replies == [false] && !app.terminationStarted && !app.discardedForTermination && app.dirty && app.canvas.document == before,
                   "Cancel on the Quit question refuses the quit and keeps the document (replies \(AppSafetyTermination.replies))")
        // Quit again, this time Don't Save: cleanup runs and the approval reaches AppKit after the sheet closes.
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater, "A second Quit asks again")
        let second = AppSafetyAlert.pending.last!
        second.reply(.alertThirdButtonReturn)
        try waitForMain("The approval reaches AppKit") { AppSafetyTermination.replies == [false, true] }
        try expect(AppSafetyTermination.replies == [false, true] && app.terminationStarted && app.discardedForTermination && !app.dirty && AppSafetyCaptureCoordinator.shutdownRequests == 1,
                   "Don't Save on the Quit question starts cleanup once and approves the quit (replies \(AppSafetyTermination.replies))")
        // The stale New question, answered now, must not touch a document that is being quit.
        newQuestion.reply(.alertFirstButtonReturn)
        try expect(app.canvas.document == before && AppSafetyFilePanel.answers.isEmpty, "A New question answered after Quit started does nothing")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    /// Real sheets (not the answer seam): the paths that ended an alert with no button used to leave its completion, the
    /// one-question flag and Quit's reply hanging.
    private static func windowQuitAfterSheetsEndWithoutAnswer() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try editor(app, text: "Ended by hand")
        let before = app.canvas.document
        let savedPresenter = AppAlert.presenter, savedPresentable = AppAlert.hostIsPresentable
        AppAlert.presenter = nil; AppAlert.hostIsPresentable = { _ in true }
        defer { AppAlert.presenter = savedPresenter; AppAlert.hostIsPresentable = savedPresentable }
        // New asks; the sheet is ended from outside with no button.
        app.newFile()
        try expect(AppAlert.presentedAlerts.count == 1 && app.discardQuestionOpen && app.window.attachedSheet === AppAlert.presentedAlerts[0].panel,
                   "New raises a real sheet on the document window and marks the question open")
        app.window.endSheet(AppAlert.presentedAlerts[0].panel)
        try expect(AppAlert.presentedAlerts.isEmpty && !app.discardQuestionOpen && app.canvas.document == before && app.dirty,
                   "endSheet with no button answers Cancel: the question is no longer open, nothing is discarded")
        // Quit asks; the sheet's panel is closed with no button. AppKit must be told no, not left waiting.
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater && AppAlert.presentedAlerts.count == 1 && AppSafetyTermination.replies.isEmpty,
                   "Quit raises its real question and waits")
        AppAlert.presentedAlerts[0].panel.close()
        try waitForMain("The Quit question's end reaches AppKit") { AppSafetyTermination.replies == [false] }
        try expect(AppSafetyTermination.replies == [false] && AppAlert.presentedAlerts.isEmpty && !app.terminationStarted && app.shutdownPending.isEmpty && app.dirty,
                   "A closed Quit question refuses the quit once; no cleanup is pending (replies \(AppSafetyTermination.replies))")
        // Quit once more and let the user answer: the decision completes and nothing stays pending.
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater && AppAlert.presentedAlerts.count == 1, "A later Quit asks again")
        AppAlert.presentedAlerts[0].buttonViews[2].performClick(nil)
        try waitForMain("The approval reaches AppKit") { AppSafetyTermination.replies == [false, true] }
        try expect(app.shutdownPending.isEmpty && AppAlert.presentedAlerts.isEmpty, "Don't Save approves; no shutdown participant or alert is left pending")
        try expect(app.applicationShouldTerminate(NSApp) == .terminateNow, "The termination decision completes: terminateNow, no terminateLater left")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    private static func windowQuitSaveRefused() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try editor(app, text: "Save at quit")
        AppSafetyAlert.holdAnswers = true
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater, "A dirty document asks first and waits")
        // The user says Save; the save panel is cancelled: the quit is refused and nothing is lost.
        AppSafetyFilePanel.answers.append(.init(response: .cancel))
        AppSafetyAlert.pending[0].reply(.alertFirstButtonReturn)
        try expect(AppSafetyTermination.replies == [false] && !app.terminationStarted && app.dirty && !app.discardedForTermination, "A cancelled save refuses the quit (replies \(AppSafetyTermination.replies))")
        // Save succeeds: approved.
        AppSafetyAlert.pending.removeAll()
        try expect(app.applicationShouldTerminate(NSApp) == .terminateLater, "Asked again")
        let target = fixture.file("QuitSave")
        AppSafetyFilePanel.answers.append(.init(response: .OK, url: target))
        AppSafetyAlert.pending[0].reply(.alertFirstButtonReturn)
        try waitForMain("The approval reaches AppKit") { AppSafetyTermination.replies == [false, true] }
        try expect(AppSafetyTermination.replies == [false, true] && FileManager.default.fileExists(atPath: target.path) && !app.dirty, "Save, then quit: the file exists and the quit is approved (replies \(AppSafetyTermination.replies))")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    private static func windowErrorStacksOnOpenSheet() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try editor(app, text: "Open sheet")
        AppSafetyAlert.holdAnswers = true
        app.newFile()
        app.error(NSError(domain: "AppSafety", code: 2, userInfo: [NSLocalizedDescriptionKey: "Upload failed"]))
        try expect(AppSafetyAlert.pending.map { $0.alert.title } == ["Save your drawing?", "Upload failed"], "The error is raised at once, beside the open question (\(AppSafetyAlert.pending.map { $0.alert.title }))")
        // Presentation picks the topmost sheet as the parent.
        let host = AppSafetyWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        let first = AppSafetyWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        let savedPresentable = AppAlert.hostIsPresentable
        AppAlert.hostIsPresentable = { _ in true }
        defer { AppAlert.hostIsPresentable = savedPresentable }
        try expect(AppAlert.sheetParent(of: host) === host, "A window with no sheet is its own parent")
        host.simulatedSheet = first
        try expect(AppAlert.sheetParent(of: host) === first, "With a sheet already up, the alert hangs from that sheet and stays in view")
        host.simulatedSheet = nil
        try expect(AppAlert.sheetParent(of: nil) == nil, "No window, no sheet: the alert becomes a panel of its own")
        AppAlert.hostIsPresentable = { _ in false }
        try expect(AppAlert.sheetParent(of: host) == nil, "A hidden or minimised window cannot carry a sheet: the alert is a panel of its own, so Quit never waits on an unseen question")
    }

    private static func windowPromptsTakeSheetText() throws {
        let fixture = try Fixture(), app = fixture.app
        AppSafetyAlert.answers = [.init(title: "Rename", response: .alertFirstButtonReturn, text: "  Mockup v2  ")]
        app.renameDocument()
        try expect(app.nameField.stringValue == "Mockup v2" && app.window.title == "Mockup v2", "OK renames with the field's text, trimmed (\(app.window.title))")
        AppSafetyAlert.answers = [.init(title: "Rename", response: .alertSecondButtonReturn, text: "Ignored")]
        app.renameDocument()
        try expect(app.window.title == "Mockup v2", "Cancel changes nothing")
        // The sheet's field carries the current value at body size, and OK hands it back.
        var answer: String??
        AppSafetyAlert.holdAnswers = true
        app.prompt("Timed Snapshot", text: "Delay in seconds", value: "6") { answer = .some($0) }
        guard let sheet = AppSafetyAlert.pending.first, let field = sheet.alert.accessoryView as? NSTextField else { throw Failure(description: "The prompt did not raise a sheet with a field") }
        try expect(field.stringValue == "6" && field.font?.pointSize == 20 && sheet.alert.buttons.map(\.title) == ["OK", "Cancel"], "The field shows the current value at 20 pt; buttons are OK and Cancel")
        try expect(answer == nil, "Nothing is decided until the sheet is answered")
        field.stringValue = "12"
        sheet.reply(.alertFirstButtonReturn)
        try expect(answer == .some(.some("12")), "OK hands back what was typed (\(String(describing: answer)))")
        AppSafetyAlert.holdAnswers = false; AppSafetyAlert.pending = []
        var cancelled: String??
        AppSafetyAlert.answers = [.init(title: "Timed Snapshot", response: .alertSecondButtonReturn)]
        app.prompt("Timed Snapshot", text: "Delay in seconds", value: "6") { cancelled = .some($0) }
        try expect(cancelled == .some(nil), "Cancel hands back nil")
        // Window zoom state unaffected by prompts: still one window, still not terminating.
        try expect(!app.terminationStarted, "Prompts never start a shutdown")
    }

    static func windowPromptsExplainWrongEntries() throws {
        let fixture = try Fixture(), app = fixture.app
        AppSafetyAlert.holdAnswers = true
        defer { AppSafetyAlert.holdAnswers = false; AppSafetyAlert.pending = [] }
        app.timedSnap()
        guard let sheet = AppSafetyAlert.pending.last, let field = sheet.alert.accessoryView as? NSTextField else { throw Failure(description: "Timed Snapshot raised no sheet with a field") }
        let requests = AppSafetyCaptureCoordinator.screenRequests.count
        for wrong in ["abc", "", "-1", "121", "NaN"] {
            field.stringValue = wrong
            sheet.alert.buttonViews[0].performClick(nil)
            try expect(sheet.alert.response == nil && sheet.alert.errorLabel?.stringValue == "Error: Enter a number of seconds from 0 to 120." && AppSafetyCaptureCoordinator.screenRequests.count == requests,
                       "'\(wrong)': the sheet stays open and says why, and no capture starts (\(sheet.alert.errorLabel?.stringValue ?? "no line"))")
        }
        field.stringValue = "0"
        sheet.alert.buttonViews[0].performClick(nil)
        try expect(sheet.alert.response == .alertFirstButtonReturn && AppSafetyCaptureCoordinator.screenRequests.last?.delay == 0, "0 is a valid delay and starts the capture")
        AppSafetyAlert.pending = []
        app.webSnap()
        guard let link = AppSafetyAlert.pending.last, let address = link.alert.accessoryView as? NSTextField else { throw Failure(description: "Snap from Link raised no sheet with a field") }
        address.stringValue = "ftp://example.com/a.png"
        link.alert.buttonViews[0].performClick(nil)
        try expect(link.alert.response == nil && link.alert.errorLabel?.stringValue.contains("http://") == true, "A web address that is not http or https is explained (\(link.alert.errorLabel?.stringValue ?? "no line"))")
        link.alert.buttonViews[1].performClick(nil)
        try expect(link.alert.response == .alertSecondButtonReturn, "Cancel always closes it")
    }

    static func windowSaveHistoryBlankSaysSo() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = try app.archiveStore()
        app.canvas.newBlank(size: CGSize(width: 400, height: 300))
        let before = try app.archiveStore().entries.count
        app.saveHistory()
        try expect(try app.archiveStore().entries.count == before && app.status.stringValue == AppDelegate.nothingToSaveNotice, "A blank canvas saves nothing and says so (\(app.status.stringValue))")
        var shape = SketchElement(kind: .rectangle); shape.rect = CGRect(x: 10, y: 10, width: 50, height: 50)
        app.canvas.document.elements.append(shape)
        app.saveHistory()
        try expect(try app.archiveStore().entries.count == before + 1 && app.status.stringValue == "Saved to History", "With something drawn it saves and says so (\(app.status.stringValue))")
    }
}
#endif
