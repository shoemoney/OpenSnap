// OSN-054 UploadStateTests: the upload state machine and what it puts in the bottom bar's status slot, on the real AppDelegate launch.
// Every transfer is an in-process stub behind publishing.uploader; nothing touches the network, the clipboard or a browser. Announcements
// go to an injected poster, the browser to an injected opener.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var uploadCases: [(String, () throws -> Void)] {
        [
            ("Upload state: idle, then uploading with a spinner and Cancel and no Original size checkbox, then Link copied with Open and Copy, then idle with the checkbox back after the timer", uploadHappyPath),
            ("A failed upload shows Error: <message> inline with Retry and Details…, raises no alert, announces at high priority, and Details opens the whole error", uploadFailureInline),
            ("Retry sends the same bytes under the same file name; success clears it; a different document drops the failure and its Retry", uploadRetrySamePayload),
            ("Cancel returns to idle with Upload cancelled, no alert and nothing copied", uploadCancelReturnsToIdle),
            ("Quitting after a failed upload leaves the inline error alone, and a refused Quit keeps Retry working", uploadQuitAfterFailure),
            ("Quitting during a running upload cancels it, clears the spinner, raises no alert and replies to AppKit", uploadQuitDuringUpload),
            ("A second click while uploading changes nothing; an unconfigured destination opens Settings and stays idle", uploadSecondClickAndUnconfigured),
            ("Upload status commands are named for VoiceOver, 20 pt text, and only the commands of the current state are shown", uploadCommandsAreLabelled)
        ]
    }

    private final class Stub: @unchecked Sendable {
        let lock = NSLock()
        var calls = 0, copied: [URL] = [], datas: [Data] = [], names: [String] = []
        let gate = DispatchSemaphore(value: 0)
        var blocks = false, failure: Error?
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
        func record(_ data: Data, _ plan: PublishingPlan) -> (Bool, Error?) {
            lock.lock(); defer { lock.unlock() }
            calls += 1; datas.append(data); names.append(plan.remoteURL.lastPathComponent)
            return (blocks, failure)
        }
    }

    private static func install(_ stub: Stub, on app: AppDelegate) {
        app.publishing.uploader = { data, _, plan, _ in
            let (blocks, failure) = stub.record(data, plan)
            if blocks { stub.gate.wait() }
            if let failure { throw failure }
            return plan.publicURL ?? plan.remoteURL
        }
        app.publishing.clipboardWriter = { url in stub.lock.lock(); stub.copied.append(url); stub.lock.unlock() }
    }

    private final class Posted { var items: [(text: String, priority: NSAccessibilityPriorityLevel)] = []; var texts: [String] { items.map(\.text) } }

    /// Announcements land in `log` instead of reaching VoiceOver; the clock moves two seconds per call so the repeat filter never decides a result.
    private static func announcing(_ body: (Posted) throws -> Void) throws {
        let saved = (Announcer.poster, Announcer.clock, Announcer.target)
        defer { (Announcer.poster, Announcer.clock, Announcer.target) = saved; Announcer.reset() }
        let log = Posted(); var now = 0.0
        Announcer.reset()
        Announcer.poster = { _, text, priority in log.items.append((text, priority)) }
        Announcer.clock = { now += 2; return now }
        try body(log)
    }

    private static func chromeOf(_ app: AppDelegate) throws -> ModernEditorChrome {
        guard let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        return chrome
    }

    private static func uploadButton(_ app: AppDelegate) throws -> NSButton {
        guard let button = app.webpostButton else { throw Failure(description: "Missing Upload button") }
        return button
    }

    private static func visibleCommands(_ chrome: ModernEditorChrome) -> [String] {
        let controls = chrome.uploadControls
        var shown: [String] = []
        if !controls.spinner.isHidden { shown.append("spinner") }
        for (name, button) in [("cancel", controls.cancelButton), ("open", controls.openButton), ("copy", controls.copyButton),
                               ("retry", controls.retryButton), ("details", controls.detailsButton)] where !button.isHidden { shown.append(name) }
        return shown
    }

    private static func largeUploadShot(_ app: AppDelegate) throws {
        guard let capacity = app.maximumNormalCanvas else { throw Failure(description: "Missing screen capacity") }
        app.receiveCapture(.success(try image(size: CGSize(width: ceil(capacity.width + 300), height: ceil(capacity.height + 150)))), discardAlreadyApproved: true)
        app.dirty = false
        app.updateViewportChrome()
    }

    static func uploadHappyPath() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeOf(app)
        try largeUploadShot(app)
        let stub = Stub(); stub.blocks = true; install(stub, on: app)
        var opened: [URL] = []
        app.linkOpener = { opened.append($0) }
        app.uploadSuccessDuration = 0.1
        app.nameField.stringValue = "Shot"
        try announcing { log in
            try expect(app.uploadState == .idle && visibleCommands(chrome).isEmpty && !app.dragOriginalControl.isHidden, "At rest: idle, no upload command shown, the Original size checkbox is there for a large shot")
            try uploadButton(app).performClick(nil)
            try waitForMain("The transfer starts") { stub.count == 1 }
            try expect(app.uploadState == .uploading(name: "Shot") && app.status.stringValue == "Uploading Shot…", "Uploading: the state and the status read Uploading Shot… (\(app.status.stringValue))")
            try expect(visibleCommands(chrome) == ["spinner", "cancel"], "Uploading shows a spinner and Cancel only (\(visibleCommands(chrome)))")
            try expect(chrome.uploadControls.spinner.style == .spinning && chrome.uploadControls.spinner.isIndeterminate, "The spinner is the indeterminate kind")
            try expect(chrome.uploadControls.spinner.frame.size == NSSize(width: 20, height: 20), "The spinner is 20 pt (\(chrome.uploadControls.spinner.frame.size))")
            try expect(app.dragOriginalControl.isHidden && app.isLargeShot, "The Original size checkbox is hidden for the duration of the upload")
            try expect(log.texts.contains("Uploading Shot") && log.items.first { $0.text == "Uploading Shot" }?.priority == .medium, "The start is announced: \(log.texts)")
            stub.gate.signal()
            try waitForMain("The upload succeeds") { if case .success = app.uploadState { return true } else { return false } }
            guard case .success(let url, let copied) = app.uploadState else { throw Failure(description: "Not a success") }
            try expect(copied && stub.copied == [url] && app.status.stringValue == "Link copied", "Success: Link copied, and the clipboard behaviour is unchanged (\(app.status.stringValue))")
            try expect(visibleCommands(chrome) == ["open", "copy"], "Success shows Open and Copy (\(visibleCommands(chrome)))")
            try expect(app.dragOriginalControl.isHidden, "The checkbox stays out of the way while Link copied and its commands are showing")
            try expect(log.texts.contains("Upload complete. Link copied."), "Success is announced: \(log.texts)")
            try expect(AppToolTip.text(for: app.status) == "Link copied: " + url.absoluteString && app.status.accessibilityHelp() == "Link copied: " + url.absoluteString, "The link itself rides on the tooltip and the VoiceOver help")
            chrome.uploadControls.openButton.performClick(nil)
            try expect(opened == [url], "Open hands the link to the browser seam")
            chrome.uploadControls.copyButton.performClick(nil)
            try expect(stub.copied == [url, url], "Copy puts the link on the clipboard again")
            // Four seconds in production; 0.1 s here through the same timer.
            try waitForMain("The success expires") { app.uploadState == .idle }
            try expect(visibleCommands(chrome).isEmpty && (app.status.stringValue.contains("Saved") || app.status.stringValue.contains("Unsaved")), "After the timer the normal adaptive status is back (\(app.status.stringValue))")
            try expect(!app.dragOriginalControl.isHidden, "and the Original size checkbox with it")
            try expect(AppSafetyAlert.seen.isEmpty && app.window.attachedSheet == nil, "No sheet or alert at any point")
        }
    }

    static func uploadFailureInline() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeOf(app)
        let stub = Stub(); stub.failure = PublishingFailure("Server said no.\nThe second line has the detail."); install(stub, on: app)
        try announcing { log in
            try uploadButton(app).performClick(nil)
            try waitForMain("The failure arrives") { app.uploadState.isFailure && !app.publishing.isBusy }
            try expect(app.status.stringValue == "Error: Server said no.", "The status is Error: and the first line only (\(app.status.stringValue))")
            try expect(visibleCommands(chrome) == ["retry", "details"], "Failure shows Retry and Details… (\(visibleCommands(chrome)))")
            try expect(AppSafetyAlert.seen.isEmpty && app.window.attachedSheet == nil && stub.copied.isEmpty, "No alert, no sheet, nothing copied")
            try expect(log.items.contains { $0.text == "Error: Server said no." && $0.priority == .high }, "The error is announced at high priority: \(log.items)")
            try expect(app.status.accessibilityHelp() == "Error: Server said no.\nThe second line has the detail.", "The whole error is the VoiceOver help")
            AppSafetyAlert.holdAnswers = true
            chrome.uploadControls.detailsButton.performClick(nil)
            try expect(AppSafetyAlert.pending.count == 1 && AppSafetyAlert.pending[0].alert.title == "Upload failed"
                       && AppSafetyAlert.pending[0].alert.message == "Error: Server said no.\nThe second line has the detail.", "Details opens an alert with the whole error (\(AppSafetyAlert.pending.map { $0.alert.message }))")
            AppSafetyAlert.pending.removeFirst().reply(.alertFirstButtonReturn)
            AppSafetyAlert.holdAnswers = false
            try expect(app.uploadState.isFailure, "Closing Details leaves the error in place")
        }
    }

    static func uploadRetrySamePayload() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeOf(app)
        let stub = Stub(); stub.failure = PublishingFailure("Timed out."); install(stub, on: app)
        app.nameField.stringValue = "Again"
        try uploadButton(app).performClick(nil)
        try waitForMain("The first attempt fails") { app.uploadState.isFailure && !app.publishing.isBusy }
        stub.failure = nil
        chrome.uploadControls.retryButton.performClick(nil)
        try expect(app.uploadState == .uploading(name: "Again"), "Retry goes back to uploading (\(app.uploadState))")
        try waitForMain("The retry succeeds") { if case .success = app.uploadState { return true } else { return false } }
        try expect(stub.count == 2 && stub.datas[0] == stub.datas[1] && !stub.datas[0].isEmpty, "Retry re-invoked the uploader with the same bytes")
        try expect(stub.names[0] == stub.names[1] && stub.names[0].hasPrefix("Again-"), "and the same file name (\(stub.names))")
        try expect(app.retryablePayload == nil && visibleCommands(chrome) == ["open", "copy"], "Success clears the retry payload and the Retry command")
        // A failure belongs to the document it was raised for.
        app.expireUploadSuccess()
        stub.failure = PublishingFailure("Again.")
        try uploadButton(app).performClick(nil)
        try waitForMain("Another failure") { app.uploadState.isFailure && !app.publishing.isBusy }
        app.dirty = false
        app.newFile()
        try expect(app.uploadState == .idle && app.retryablePayload == nil && visibleCommands(chrome).isEmpty, "A new document drops the failure and its Retry (\(app.uploadState))")
        let before = stub.count
        app.retryUpload()
        try expect(stub.count == before && app.uploadState == .idle, "Retry with nothing to retry does nothing")
    }

    static func uploadCancelReturnsToIdle() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeOf(app)
        let stub = Stub(); stub.blocks = true; install(stub, on: app)
        try announcing { log in
            try uploadButton(app).performClick(nil)
            try waitForMain("The transfer starts") { stub.count == 1 }
            chrome.uploadControls.cancelButton.performClick(nil)
            stub.gate.signal()
            try waitForMain("The upload is cancelled") { app.uploadState == .idle && !app.publishing.isBusy && app.status.stringValue == "Upload cancelled" }
            try expect(visibleCommands(chrome).isEmpty && stub.copied.isEmpty && AppSafetyAlert.seen.isEmpty, "Cancelling hides the upload commands, copies nothing and raises no alert")
            try expect(!log.texts.contains { $0.hasPrefix("Error") }, "Cancelling announces no error: \(log.texts)")
            try expect(app.retryablePayload == nil, "A cancelled upload is not offered for Retry")
        }
    }

    static func uploadQuitAfterFailure() throws {
        // A Quit the cleanup refuses: the inline error must survive the barrier unchanged.
        do {
            let fixture = try Fixture(), app = fixture.app
            let chrome = try chromeOf(app)
            let stub = Stub(); stub.failure = PublishingFailure("Refused."); install(stub, on: app)
            try uploadButton(app).performClick(nil)
            try waitForMain("The failure arrives") { app.uploadState.isFailure && !app.publishing.isBusy }
            let cleanup = NSError(domain: "AppSafety", code: 9, userInfo: [NSLocalizedDescriptionKey: "Cleanup could not finish."])
            AppSafetyCaptureCoordinator.shutdownResult = .failure(cleanup)
            AppSafetyAlert.answers.append(.init(title: cleanup.localizedDescription, response: .alertFirstButtonReturn))
            let reply = app.applicationShouldTerminate(NSApp)
            try expect(reply == .terminateCancel, "The refused Quit is answered at once (\(reply.rawValue))")
            try waitForMain("The cleanup error is shown") { AppSafetyAlert.seen.contains(cleanup.localizedDescription) }
            try expect(!app.terminationStarted && app.uploadState == .failure(message: "Refused.") && app.status.stringValue == "Error: Refused.",
                       "A refused Quit keeps the inline error (\(app.status.stringValue))")
            try expect(visibleCommands(chrome) == ["retry", "details"] && AppSafetyAlert.seen == [cleanup.localizedDescription], "and its Retry and Details…, and raises no alert of its own")
            AppSafetyCaptureCoordinator.shutdownResult = .success(())
        }
        // A Quit that goes ahead with an error showing: the barrier completes and the error does not turn into an alert on the way out.
        do {
            let fixture = try Fixture(), app = fixture.app
            let stub = Stub(); stub.failure = PublishingFailure("Refused."); install(stub, on: app)
            AppSafetyAlert.reset(); AppSafetyAlert.install()
            try uploadButton(app).performClick(nil)
            try waitForMain("The failure arrives") { app.uploadState.isFailure && !app.publishing.isBusy }
            try expect(app.applicationShouldTerminate(NSApp) == .terminateNow && app.shutdownPending.isEmpty, "Quitting with an inline error terminates at once")
            try expect(AppSafetyAlert.seen.isEmpty, "The error did not become an alert (\(AppSafetyAlert.seen))")
            app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
    }

    static func uploadQuitDuringUpload() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeOf(app)
        let stub = Stub(); stub.blocks = true; install(stub, on: app)
        try uploadButton(app).performClick(nil)
        try waitForMain("The transfer starts") { stub.count == 1 }
        try expect(app.uploadState.isUploading && visibleCommands(chrome) == ["spinner", "cancel"], "An upload is running")
        let reply = app.applicationShouldTerminate(NSApp)
        try expect(reply == .terminateLater, "Quit waits for the running upload to stop (\(reply.rawValue))")
        stub.gate.signal()
        try waitForMain("AppKit is told the Quit may go ahead") { AppSafetyTermination.replies == [true] }
        try expect(app.terminationStarted && app.shutdownPending.isEmpty, "The shutdown barrier completed")
        try expect(app.uploadState == .idle && visibleCommands(chrome).isEmpty, "The spinner does not outlive the transfer (\(app.uploadState))")
        try expect(AppSafetyAlert.seen.isEmpty && stub.copied.isEmpty, "Quitting raises no alert and copies nothing")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    static func uploadSecondClickAndUnconfigured() throws {
        let fixture = try Fixture(), app = fixture.app
        let stub = Stub(); stub.blocks = true; install(stub, on: app)
        let button = try uploadButton(app)
        button.performClick(nil)
        try waitForMain("The transfer starts") { stub.count == 1 }
        let state = app.uploadState
        button.performClick(nil)
        try expect(app.uploadState == state && stub.count == 1 && app.status.stringValue == "An upload is already running…", "A second click starts nothing and leaves the state alone (\(app.status.stringValue))")
        stub.gate.signal()
        try waitForMain("The upload finishes") { if case .success = app.uploadState { return true } else { return false } }
        app.expireUploadSuccess()
        try configureDestinations(app, [])
        var opened = 0
        app.sharingSettingsPresenter = { opened += 1 }
        button.performClick(nil)
        try expect(opened == 1 && app.uploadState == .idle && stub.count == 1, "With no destination the click opens Settings, as before, and the state stays idle")
    }

    static func uploadCommandsAreLabelled() throws {
        let fixture = try Fixture(), app = fixture.app
        let chrome = try chromeOf(app)
        let controls = chrome.uploadControls
        let expected: [(CommandButton, String)] = [(controls.cancelButton, "Cancel upload"), (controls.openButton, "Open link in browser"), (controls.copyButton, "Copy link"),
                                                    (controls.retryButton, "Retry"), (controls.detailsButton, "Details…")]
        for (button, name) in expected {
            try expect(button.accessibilityLabel() == name, "\(name): VoiceOver label (\(button.accessibilityLabel() ?? "nil"))")
            try expect(button.frame.height >= DesignTokens.Size.hitMin && (button.font?.pointSize ?? 0) >= DesignTokens.Typography.readableMinimum, "\(name): at least \(DesignTokens.Size.hitMin) pt tall with a readable font")
        }
        try expect(controls.cancelButton.icon == .xmark && controls.openButton.icon == .openExternal && controls.copyButton.icon == .copy, "Cancel, Open and Copy use the semantic Font Awesome icons")
        try expect(controls.retryButton.visibleTitle == "Retry" && controls.detailsButton.visibleTitle == "Details…", "Retry and Details… are text")
        let url = URL(string: "https://example.com/a.png")!
        for (state, shown) in [(UploadState.idle, []), (.uploading(name: "x"), ["spinner", "cancel"]), (.success(url: url, copied: true), ["open", "copy"]),
                               (.success(url: url, copied: false), []), (.failure(message: "m"), ["retry", "details"])] {
            app.uploadState = state
            try expect(visibleCommands(chrome) == shown, "\(state): shows \(shown) (\(visibleCommands(chrome)))")
        }
        app.uploadState = .idle
    }
}
#endif
