// Audit fix batch 3c: the App-side findings of the E2E journeys J1 and J2 (docs/design/e2e/findings.md).
// Run through tools/test-app-safety.sh; no window or panel is ever put on screen and nothing touches the network.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var batch3cCases: [(String, () throws -> Void)] {
        [
            ("History's Hide and Trash questions are sheets on History, one at a time, and History is never left waiting (F-J2-001, F-J2-006)", b3cHistoryQuestionsOnHistory),
            ("A refused Delete from Web says why on History; one with a recorded destination asks first (F-J2-002)", b3cDeleteFromWebRefusal),
            ("An upload keeps its deletion binding only while the published URL captures the same four stable fields (F-J2-002)", b3cBindingRetention),
            ("History Open asks about unsaved changes on History like File > New does, and a freshly opened entry is clean (F-J2-003, F-J2-005)", b3cHistoryOpenGuard),
            ("Command-1 to Command-4 belong to Settings' tabs while Settings is the key window, and to Capture otherwise (F-J2-011)", b3cSettingsOwnsTabKeys),
            ("The Toolbox is the short drawing-session list with an icon on every row, and the menu bar keeps the rest (F-J1-009)", b3cToolbox),
            ("Edit has Clear Image and Remove Snap Picture, an Arrange submenu holds the stacking commands, and Image is left with picture commands (F-J1-017)", b3cMenuNaming),
            ("Add Shadow is disabled without a snap picture and enabled with one (F-J1-025)", b3cAddShadowNeedsSnap),
            ("Status messages expire, clear on the next edit or tool change, and Frame mode gets its hint back (F-J1-010)", b3cStatusNotices),
            ("Full screen zooms a small drawing up to fill the Space and gives the zoom back on exit; the bars stay one group at any width (F-J1-018)", b3cFullScreenLayout),
            ("A size preset closes the Size popover as a colour pick closes the colour popover; the track keeps it open (F-J1-019)", b3cPopoverDismissal)
        ]
    }


    private static func b3cFind<T: NSView>(_ type: T.Type, in root: NSView?, where match: (T) -> Bool) -> T? {
        guard let root else { return nil }
        if let hit = root as? T, match(hit) { return hit }
        for child in root.subviews { if let hit = b3cFind(type, in: child, where: match) { return hit } }
        return nil
    }

    /// Answers the oldest held alert. The alert is kept alive across the call: the answer closure only holds it weakly.
    private static func b3cAnswerNext(_ response: NSApplication.ModalResponse) {
        let held = AppSafetyAlert.pending.removeFirst()
        withExtendedLifetime(held) { held.reply(response) }
    }

    // MARK: History

    private static func b3cShowHistory(_ app: AppDelegate) throws -> AppSafetyWindow {
        app.showHistory()
        guard let history = app.historyWindow as? AppSafetyWindow else { throw Failure(description: "History window") }
        history.simulatesVisibility = true; history.shown = true
        return history
    }

    private static func b3cHistoryQuestionsOnHistory() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let id = try store.archive(historyDrawing("A"), name: "A", action: .archived)
        // History is created but not on screen: the question falls back to the editor, never to a window nobody can see.
        app.showHistory()
        AppSafetyAlert.answers = [.init(title: "Hide drawings from History?", response: .alertSecondButtonReturn)]
        app.removeHistory([id], deleteFiles: false)
        try expect(AppSafetyAlert.hosts.last.flatMap { $0 } === app.window, "With History off screen the question is on the editor")
        let history = try b3cShowHistory(app)
        AppSafetyAlert.answers = [.init(title: "Hide drawings from History?", response: .alertSecondButtonReturn),
                                  .init(title: "Move archived drawings to Trash?", response: .alertFirstButtonReturn)]
        app.removeHistory([id], deleteFiles: false); app.removeHistory([id], deleteFiles: true)
        try expect(AppSafetyAlert.hosts.suffix(2).allSatisfy { $0 === history }, "Hide and Trash are sheets on the History window the click came from")
        try expect(store.entries.contains { $0.id == id }, "Cancel removes nothing")
        // One question at a time: a second click while one is open changes nothing, and answering frees the command again.
        AppSafetyAlert.holdAnswers = true
        app.removeHistory([id], deleteFiles: false); app.removeHistory([id], deleteFiles: false)
        try expect(AppSafetyAlert.pending.count == 1, "A second Hide while its sheet is open raises no second sheet (\(AppSafetyAlert.pending.count))")
        app.removeHistory([id], deleteFiles: true)
        try expect(AppSafetyAlert.pending.count == 2, "A different question is its own sheet")
        b3cAnswerNext(.alertSecondButtonReturn)   // Hide: Cancel is second
        b3cAnswerNext(.alertFirstButtonReturn)    // Trash: Cancel is first
        app.removeHistory([id], deleteFiles: false)
        try expect(AppSafetyAlert.pending.count == 1, "After the answer the same question can be asked again")
        b3cAnswerNext(.alertFirstButtonReturn)
        AppSafetyAlert.holdAnswers = false
        try expect(!store.entries.contains { $0.id == id }, "Hide removes the entry from the list")
        try expect(history.attachedSheet == nil, "History is left with no sheet")
    }

    /// A destination saved the way a person would, and the binding an upload to it records, so Delete from Web is really available for it.
    static func b3cRealBinding(_ app: AppDelegate, url: URL) throws -> [String: String] {
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.com/files"; dav.remoteFolder = "pics"; dav.publicBaseURL = "https://cdn.example.com/pics"
        try configureDestinations(app, [dav], names: ["Pics"])
        app.historyRemoteDeletion = HistoryRemoteDeletionCoordinator(destinationBinding: nil, store: app.publishing.store)
        return try app.historyRemoteDeletion.captureBinding(for: url)
    }

    private static func b3cDeleteFromWebRefusal() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let history = try b3cShowHistory(app)
        let snapshot = try historyDrawing("Shared")
        let local = try store.archive(snapshot, name: "Local", action: .archived)
        let url = try XCTestURL("https://cdn.example.com/pics/a.png")
        let unbound = try store.archive(snapshot, name: "Old", action: .shared, destination: url.absoluteString, remoteURL: url)
        let bound = try store.archive(snapshot, name: "New", action: .shared, destination: url.absoluteString, remoteURL: url, remoteBinding: try b3cRealBinding(app, url: url))
        // R1-010: a binding for a destination that is no longer the default is refused with the reason, not offered and then failed.
        let stale = try store.archive(snapshot, name: "Moved", action: .shared, destination: url.absoluteString, remoteURL: url,
                                      remoteBinding: ["version": "1", "destinationSHA256": String(repeating: "a", count: 64), "publicURL": url.absoluteString])
        let refusal = "Can\u{2019}t delete this from the web"
        var messages: [String] = []
        AppSafetyAlert.holdAnswers = true
        for ids in [[local], [unbound], [unbound, bound]] {
            app.deleteHistoryRemote(ids)
            messages.append(AppSafetyAlert.pending.last?.alert.message ?? "")
            b3cAnswerNext(.alertFirstButtonReturn)
        }
        app.deleteHistoryRemote([stale])
        messages.append(AppSafetyAlert.pending.last?.alert.message ?? "")
        b3cAnswerNext(.alertFirstButtonReturn)
        AppSafetyAlert.holdAnswers = false
        AppSafetyAlert.answers = [.init(title: "Delete this web post?", response: .alertFirstButtonReturn)]
        app.deleteHistoryRemote([bound])
        try expect(AppSafetyAlert.hosts.allSatisfy { $0 === history }, "Every Delete from Web answer is on History, never a dead click")
        try expect(AppSafetyAlert.seen == [refusal, refusal, refusal, refusal, "Delete this web post?"], "Refused four times (never uploaded, unrecorded, several at once, destination changed) with a reason, asked once with a live binding: \(AppSafetyAlert.seen)")
        try expect(messages.count == 4 && messages[2].contains("one post at a time") && messages[3].contains("no longer the server, bucket or folder it was published to"), "A destination that moved says so: \(messages[3])")
        try expect(app.historyRemoteDeletion.deletionBlocks(for: [(stale, url, store.entry(stale)?.remoteBinding ?? [:])])[stale] != nil && app.historyRemoteDeletion.deletionBlocks(for: [(bound, url, store.entry(bound)?.remoteBinding ?? [:])]).isEmpty,
                   "The History button is off, with that reason, for the moved one only")
        try expect(messages.count == 4 && messages[2].contains("one post at a time"), "A multiple selection is told it is one post at a time: \(messages)")
        try expect(AppDelegate.deleteFromWebRefusal(for: store.entry(local)).contains("never uploaded"), "A local drawing says it was never uploaded")
        try expect(AppDelegate.deleteFromWebRefusal(for: store.entry(unbound)).contains("before OpenSnap recorded"), "An upload without a recorded destination says so")
        try expect(store.entry(bound)?.remoteURL != nil && store.entry(unbound)?.remoteURL != nil, "Cancel and refusal change nothing")
    }

    private static func XCTestURL(_ text: String) throws -> URL {
        guard let url = URL(string: text) else { throw Failure(description: "URL \(text)") }
        return url
    }

    private static func b3cBindingRetention() throws {
        let planned = ["version": "1", "destinationSHA256": String(repeating: "a", count: 64), "publicURL": "https://cdn.example.com/pics/x.png"]
        var otherDestination = planned; otherDestination["destinationSHA256"] = String(repeating: "b", count: 64)
        var otherURL = planned; otherURL["publicURL"] = "https://cdn.example.com/pics/y.png"
        var withSSH = planned; withSSH["sshConfigSHA256"] = String(repeating: "c", count: 64)
        try expect(AppDelegate.retainedBinding(planned: planned, published: planned) == planned, "The same four fields keep the binding")
        try expect(AppDelegate.retainedBinding(planned: planned, published: otherDestination) == nil, "A different destination digest drops it")
        try expect(AppDelegate.retainedBinding(planned: planned, published: otherURL) == nil, "A different public URL drops it")
        try expect(AppDelegate.retainedBinding(planned: planned, published: withSSH) == nil, "A different SSH digest drops it")
        try expect(AppDelegate.retainedBinding(planned: nil, published: planned) == nil && AppDelegate.retainedBinding(planned: planned, published: nil) == nil,
                   "A capture that failed on either side keeps nothing")

        // Through the real upload path: the archived entry carries the binding the capture seams produced.
        for (published, kept) in [(planned, true), (otherDestination, false)] {
            let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
            app.plannedBindingCapture = { _ in planned }
            app.publishedBindingCapture = { _ in published }
            _ = try editor(app, text: "Share me"); app.canvas.commitPendingTextEditing()
            app.publishImage()
            try waitForMain("The upload is archived") { store.entries.contains { $0.action == .shared } }
            let entry = try store.entries.first { $0.action == .shared }.b3cUnwrap("shared entry")
            try expect((entry.remoteBinding == planned) == kept && (entry.remoteBinding == nil) == !kept, "The archived entry \(kept ? "keeps" : "drops") the binding (\(String(describing: entry.remoteBinding)))")
        }
    }

    private static func b3cHistoryOpenGuard() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let history = try b3cShowHistory(app)
        _ = try editor(app, text: "Unsaved work"); app.canvas.commitPendingTextEditing()
        try expect(app.dirty, "The document starts with unsaved changes")
        let idB = try store.archive(historyDrawing("B", color: .green), name: "B", action: .archived)
        let idC = try store.archive(historyDrawing("C", color: .blue), name: "C", action: .archived)
        let before = try app.canvas.snapshotDocumentData()
        // Cancel: nothing opens, the sheet is on History.
        AppSafetyAlert.answers = [.init(title: "Save your drawing?", response: .alertSecondButtonReturn)]
        app.openHistory(idB)
        try expect(AppSafetyAlert.hosts.last.flatMap { $0 } === history && app.currentArchiveID != idB && app.dirty, "Cancel keeps the document and asks on History")
        try expect(try app.canvas.snapshotDocumentData() == before, "Cancel leaves the artwork exactly as it was")
        // Don't Save: it opens, and nothing is unsaved afterwards.
        AppSafetyAlert.answers = [.init(title: "Save your drawing?", response: .alertThirdButtonReturn)]
        app.openHistory(idB)
        try expect(app.currentArchiveID == idB && !app.dirty && !app.window.isDocumentEdited, "Don't Save opens the entry as a clean document")
        try expect(!app.status.stringValue.contains("Unsaved"), "The status does not claim unsaved changes (\(app.status.stringValue))")
        // A clean document opens the next entry with no question at all.
        let asked = AppSafetyAlert.seen.count
        app.openHistory(idC)
        try expect(AppSafetyAlert.seen.count == asked && app.currentArchiveID == idC, "A clean document opens another entry without a prompt")
        // An edit makes it dirty again, so the guard comes back.
        app.canvas.setBackgroundColor(.yellow)
        try expect(app.dirty, "An edit marks the opened entry dirty")
        AppSafetyAlert.answers = [.init(title: "Save your drawing?", response: .alertSecondButtonReturn)]
        app.openHistory(idB)
        try expect(app.currentArchiveID == idC, "The guard asks again after an edit")
    }

    // MARK: Menus

    private static func b3cSettingsOwnsTabKeys() throws {
        let fixture = try Fixture(), app = fixture.app
        app.showPreferences()
        guard let settings = app.preferencesWindow else { throw Failure(description: "Settings window") }
        let capture = try NSApp.mainMenu.b3cUnwrap("main").items.compactMap(\.submenu).first { $0.title == "Capture" }.b3cUnwrap("Capture menu")
        let snaps = capture.items.filter { ["1", "2", "3", "4"].contains($0.keyEquivalent) }
        try expect(snaps.count == 4, "Capture owns Command-1 to Command-4 (\(snaps.map(\.title)))")
        func keyEvent(_ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                                 charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 18).b3cUnwrap("key event")
        }
        let mouse = try NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1).b3cUnwrap("mouse event")
        for item in snaps {
            try expect(AppDelegate.settingsOwnsKeyEquivalent(of: item, event: try keyEvent(item.keyEquivalent, .command), keyWindow: settings, settingsWindow: settings),
                       "\(item.title): a key press while Settings is key is Settings'")
            try expect(!AppDelegate.settingsOwnsKeyEquivalent(of: item, event: try keyEvent(item.keyEquivalent, .command), keyWindow: app.window, settingsWindow: settings),
                       "\(item.title): with the editor key it is still Capture's")
            try expect(!AppDelegate.settingsOwnsKeyEquivalent(of: item, event: mouse, keyWindow: settings, settingsWindow: settings),
                       "\(item.title): picking it with the pointer still captures, whatever window is key")
        }
        let quit = try NSApp.mainMenu.b3cUnwrap("main").items.compactMap(\.submenu).flatMap(\.items).first { $0.keyEquivalent == "q" }.b3cUnwrap("Quit")
        try expect(!AppDelegate.settingsOwnsKeyEquivalent(of: quit, event: try keyEvent("q", .command), keyWindow: settings, settingsWindow: settings), "Only the four tab keys are Settings'")
        // Through the menu validation the app really uses: Settings is key and a key event is current.
        app.keyWindowProvider = { settings }
        AppSafetyEvents.current = try keyEvent("1", .command)
        try expect(snaps.allSatisfy { !app.validateMenuItem($0) }, "While Settings is key, a Command-digit key event finds the Capture items disabled")
        AppSafetyEvents.current = mouse
        try expect(snaps.allSatisfy { app.validateMenuItem($0) }, "Opened with the pointer the same items are enabled")
        AppSafetyEvents.current = try keyEvent("1", .command)
        app.keyWindowProvider = { app.window }
        try expect(snaps.allSatisfy { app.validateMenuItem($0) }, "With the editor key they are enabled for the key press too")
        AppSafetyEvents.current = nil
    }

    private static func b3cToolbox() throws {
        let fixture = try Fixture(), app = fixture.app
        let toolbox = try b3cFind(NSPopUpButton.self, in: app.window.contentView) { $0.accessibilityLabel() == "Toolbox menu" }.b3cUnwrap("Toolbox")
        let rows = (toolbox.menu?.items ?? []).filter { !$0.isSeparatorItem }
        try expect(rows.count == 18 && rows.count < 33, "The Toolbox is \(rows.count) rows, not the old 33")
        // R1-005: AppKit draws a row's image only in a selection-style pop-up, so the Toolbox is one, with real NSMenuItem images.
        try expect(toolbox is ToolboxPopUpButton && !toolbox.pullsDown && toolbox.selectedItem == nil, "The Toolbox is a selection-style pop-up with nothing selected, not a pull-down")
        let toggles: Set<Selector> = [#selector(AppDelegate.toggleBezelFill(_:)), #selector(AppDelegate.toggleBezelShadow(_:))]
        try expect(rows.allSatisfy { $0.image != nil || ($0.action.map(toggles.contains) ?? false) },
                   "Every row carries its menu symbol as its image (the two checkmark rows keep the check instead): \(rows.filter { $0.image == nil }.map(\.title))")
        let text = DesignTokens.Typography.font(.body).pointSize
        try expect(rows.compactMap(\.image).allSatisfy { $0.isTemplate && $0.size.height >= text * 0.6 && $0.size.height <= text * 1.5 },
                   "The symbols are template images sized to the 20 pt menu text, not the 13 pt default: \(rows.compactMap { $0.image?.size })")
        try expect(rows.allSatisfy { $0.attributedTitle == nil && !$0.title.contains("\u{FFFC}") }, "No text-attachment workaround is left in the row titles")
        let face = try (toolbox.cell as? NSPopUpButtonCell).b3cUnwrap("popup cell")
        try expect(!face.usesItemFromMenu && face.menuItem === (toolbox as? ToolboxPopUpButton)?.faceItem && (toolbox as? ToolboxPopUpButton)?.faceItem.image != nil,
                   "The closed button shows its own face item (icon and chevron), whatever row was last chosen")
        let titles = rows.map(\.title)
        try expect(["About OpenSnap", "Settings…", "Quit OpenSnap", "New", "Open…", "Print…"].allSatisfy { !titles.contains($0) }, "No app or file plumbing in the Toolbox: \(titles)")
        let bar = try NSApp.mainMenu.b3cUnwrap("main").items.compactMap(\.submenu).flatMap(\.items)
        try expect(bar.contains { $0.action == #selector(AppDelegate.about) } && bar.contains { $0.action == #selector(AppDelegate.quit) }, "The menu bar still has them")
    }

    private static func b3cMenuNaming() throws {
        let fixture = try Fixture(), app = fixture.app
        _ = app
        let menus = try NSApp.mainMenu.b3cUnwrap("main").items.compactMap(\.submenu)
        let edit = try menus.first { $0.title == "Edit" }.b3cUnwrap("Edit"), image = try menus.first { $0.title == "Image" }.b3cUnwrap("Image")
        let editTitles = edit.items.map(\.title)
        try expect(editTitles.contains("Clear Image") && editTitles.contains("Remove Snap Picture"), "Edit names what each clear command removes: \(editTitles)")
        try expect(!editTitles.contains("Wipe Snap Only") && !editTitles.contains("Clear Annotations"), "The near-synonyms Wipe Snap Only and Clear Annotations are gone: \(editTitles)")
        let arrange = try edit.items.first { $0.title == "Arrange" }.b3cUnwrap("Arrange").submenu.b3cUnwrap("Arrange submenu")
        try expect(arrange.items.filter { !$0.isSeparatorItem }.map(\.title) == ["Bring to Front", "Send to Back", "Group", "Ungroup"], "Arrange holds the stacking and grouping commands")
        let imageTitles = image.items.map(\.title)
        try expect(["Bring to Front", "Send to Back", "Group", "Ungroup"].allSatisfy { !imageTitles.contains($0) }, "Image keeps only picture commands: \(imageTitles)")
        try expect(arrange.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil && $0.target === app }, "The Arrange rows keep their symbols and target")
    }

    private static func b3cAddShadowNeedsSnap() throws {
        let fixture = try Fixture(), app = fixture.app
        let image = try (try SketchRenderer.bitmap(size: CGSize(width: 60, height: 40)) { NSColor.blue.setFill(); CGRect(x: 0, y: 0, width: 60, height: 40).fill() }.b3cUnwrap("bitmap")).representation(using: .png, properties: [:]).b3cUnwrap("png")
        let item = try NSApp.mainMenu.b3cUnwrap("main").items.compactMap(\.submenu).flatMap(\.items).first { $0.action == #selector(AppDelegate.addShadow) }.b3cUnwrap("Add Shadow")
        try expect(app.canvas.document.backgroundPNG == nil && !app.validateMenuItem(item), "A plain drawing has nothing to shadow, so the item is disabled")
        app.canvas.setBackground(try NSImage(data: image).b3cUnwrap("image"))
        try expect(app.canvas.document.backgroundPNG != nil && app.validateMenuItem(item), "With a snap picture the item is enabled")
    }

    // MARK: Status, full screen, popovers

    private static func b3cStatusNotices() throws {
        let fixture = try Fixture(), app = fixture.app
        app.canvas.newBlank(size: NSSize(width: 400, height: 300)); app.updateStatus()
        let normal = app.status.stringValue
        app.statusNoticeDuration = 0.05
        app.postStatusNotice("Exit full screen to use Frame")
        try expect(app.status.stringValue == "Exit full screen to use Frame", "A notice shows in the status slot (\(app.status.stringValue))")
        try waitForMain("The notice expires on its own") { app.status.stringValue == normal }
        try expect(app.statusNotice == nil, "Expired: the normal status is back (\(app.status.stringValue))")
        app.statusNoticeDuration = 60
        app.postStatusNotice("Saved to History")
        app.canvas.setBackgroundColor(.yellow)
        try expect(app.statusNotice == nil && !app.status.stringValue.contains("Saved to History"), "The next edit clears it (\(app.status.stringValue))")
        app.postStatusNotice("Saved to History"); app.setTool(.brush)
        try expect(app.statusNotice == nil && app.status.stringValue.hasPrefix("Brush"), "Changing tool clears it (\(app.status.stringValue))")
        app.postStatusNotice("Exit full screen to use Frame")
        guard let window = app.window as? AppSafetyWindow else { throw Failure(description: "Isolated window") }
        app.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
        try expect(app.statusNotice == nil, "Leaving full screen clears the Frame refusal")
        // Frame mode owns the slot: a notice shows over its hint and the hint returns.
        app.frameMode = true; app.frameKeepsAnnotations = false
        app.postStatusNotice("Re-Snap needs the whole drawing visible.", duration: 0.05)
        try expect(app.status.stringValue == "Re-Snap needs the whole drawing visible.", "A notice shows in Frame mode too")
        try waitForMain("The Frame hint comes back") { app.status.stringValue == "Frame: position, then Snap" }
        app.frameMode = false
    }

    private static func b3cFullScreenLayout() throws {
        let fixture = try Fixture(), app = fixture.app
        guard let window = app.window as? AppSafetyWindow, let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "Isolated window and chrome") }
        app.canvas.newBlank(size: NSSize(width: 800, height: 600)); app.fitCanvasToWindow()
        let before = app.canvas.zoom
        window.setFrame(NSRect(x: 0, y: 0, width: 2056, height: 1329), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        window.simulatesFullScreen = true
        app.windowDidEnterFullScreen(Notification(name: NSWindow.didEnterFullScreenNotification, object: window))
        try expect(app.canvas.zoom > 1 && app.canvas.zoom <= AppDelegate.fullScreenMaximumScale, "Full screen zooms the 800 x 600 drawing up to use the room, not 100% in the middle (\(app.canvas.zoom))")
        let scroll = try app.canvas.enclosingScrollView.b3cUnwrap("scroll view")
        try expect(app.canvas.frame.width <= scroll.contentView.bounds.width && app.canvas.frame.height <= scroll.contentView.bounds.height + 0.5, "It still fits whole (\(app.canvas.frame.size) in \(scroll.contentView.bounds.size))")
        // The bars stay one group in the middle instead of drifting to the corners.
        let header = try b3cFind(NSView.self, in: chrome) { $0.identifier?.rawValue == "GlassTopBar" }.b3cUnwrap("top bar"), footer = try b3cFind(NSView.self, in: chrome) { $0.identifier?.rawValue == "GlassBottomBar" }.b3cUnwrap("bottom bar")
        for (name, bar) in [("top", header), ("bottom", footer)] {
            let frame = chrome.convert(bar.frame, from: bar.superview)
            try expect(frame.width <= ModernEditorChrome.maximumBarWidth + 0.5 && abs(frame.midX - chrome.bounds.midX) < 1, "The \(name) bar is capped at \(Int(ModernEditorChrome.maximumBarWidth)) pt and centred (\(frame))")
        }
        window.simulatesFullScreen = false
        app.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
        try expect(abs(app.canvas.zoom - before) < 0.001, "Leaving full screen puts the zoom back (\(app.canvas.zoom) vs \(before))")
        // Below the cap the bars span the window as before.
        window.setFrame(NSRect(x: 0, y: 0, width: 1120, height: 780), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        let frame = chrome.convert(header.frame, from: header.superview)
        try expect(abs(frame.width - (chrome.bounds.width - 2 * DesignTokens.Layout.margin)) < 1, "At an ordinary width the bar spans the window less its margins (\(frame.width) of \(chrome.bounds.width))")
    }

    private static func b3cPopoverDismissal() throws {
        let fixture = try Fixture(), app = fixture.app
        app.widthControl.showPopover()
        try expect(app.widthControl.isPopoverShown, "The Size popover is open")
        let content = try app.widthControl.popoverContent.b3cUnwrap("popover content")
        content.presetButtons[2].performClick(nil)
        try expect(!app.widthControl.isPopoverShown, "Picking a size preset closes the popover, as picking a colour closes the colour popover")
        try expect(abs(app.widthControl.doubleValue - content.presetButtons[2].presetSize) < 0.01, "…and the preset was applied")
        app.widthControl.showPopover()
        let track = try app.widthControl.popoverContent.b3cUnwrap("content").trackView
        _ = track
        try expect(app.widthControl.beginGesture(), "A drag on the track begins a gesture")
        app.widthControl.trackValue(fraction: 0.5, modifiers: [])
        try expect(app.widthControl.isPopoverShown, "Dragging the track keeps the popover open")
        app.widthControl.endTracking(); app.widthControl.dismissPopover()
    }
}

private extension Optional {
    func b3cUnwrap(_ what: String) throws -> Wrapped {
        guard let value = self else { throw AppSafetyTests.Failure(description: "Missing \(what)") }
        return value
    }
}
#endif
