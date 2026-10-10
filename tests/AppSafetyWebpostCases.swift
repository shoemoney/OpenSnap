// Webpost one-click upload. Every transfer is an in-process fake; nothing touches the network.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var fakeDestination: () throws -> PublishingSettings {
        {
            var settings = PublishingSettings()
            settings.transport = .sftp; settings.sshAlias = "test-host"; settings.sftpRemoteRoot = "/srv/imgs"
            settings.publicBaseURL = "https://cdn.example.com/imgs"
            return settings
        }
    }

    /// Replaces every saved destination with these (first is the default) in an isolated store with in-memory secrets.
    static func configureDestinations(_ app: AppDelegate, _ settings: [PublishingSettings], names: [String]? = nil, defaultIndex: Int = 0) throws {
        let store = PublishingDestinationStore(directory: app.support.appendingPathComponent("Publishing"), secrets: PublishingMemorySecrets())
        try? FileManager.default.removeItem(at: store.directory)
        var ids: [String] = []
        for (index, value) in settings.enumerated() {
            let destination = PublishingDestination(name: names?[index] ?? value.suggestedName, settings: value)
            try store.save(destination, password: "")
            ids.append(destination.id)
        }
        if !ids.isEmpty { try store.setDefault(ids[defaultIndex]) }
        app.publishing.store = store
    }

    static var webpostCases: [(String, () throws -> Void)] {
        [
            ("Webpost uploads at once with no sheet, shows progress, copies the public link and reports it", webpostUploadsImmediately),
            ("A second Webpost click during a running upload is ignored with a status message and starts nothing", webpostIgnoresSecondClick),
            ("Webpost with no destination opens Sharing Settings instead of uploading", webpostUnconfiguredOpensSettings),
            ("A failed upload surfaces the error and Webpost works again", webpostFailureRecovers),
            ("The upload button's right-click menu lists the default destination, settings and Share with macOS", webpostMenu),
            ("File menu keeps Share… and Publish… goes straight to upload", webpostFileMenu),
            ("Upload progress survives tool changes and edits, then the result replaces it", webpostProgressSurvivesStatusUpdates),
            ("Cancel Upload appears only while busy, cancels quietly with no clipboard write or alert", webpostCancel),
            ("Without a public base URL nothing is copied and the status says Uploaded image to destination", webpostNoPublicURLNoClipboard),
            ("The upload right-click menu uses the 20 pt menu font", webpostMenuFont),
            ("The right-click menu lists every destination; choosing one persists it and the next Webpost click uploads there", webpostMultipleDestinations),
            ("Destination settings: Add, Make Default and Remove round-trip through storage with an S3 profile destination", webpostDestinationSettingsRoundTrip),
            ("--eye-dump-audit needs the throwaway harness bundle id, an isolated home and support folder, and no fixture", webpostEyeDumpAuditGate),
            ("The upload button is icon-only with the iCloud upload symbol and an explicit label", webpostModernIconOnly)
        ]
    }

    private static func webpostButton(_ app: AppDelegate) throws -> NSButton {
        try (app.webpostButton).unwrap("Webpost button")
    }

    private final class UploadProbe: @unchecked Sendable {
        let lock = NSLock(); var calls = 0; var copied: [URL] = []; var transports: [PublishingProtocol] = []; var uploaded: [URL] = []
        let gate = DispatchSemaphore(value: 0); var blocks = false; var failure: Error?
        func begin() -> (Bool, Error?) { lock.lock(); defer { lock.unlock() }; calls += 1; return (blocks, failure) }
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    }

    private static func install(_ probe: UploadProbe, on app: AppDelegate) {
        app.publishing.uploader = { _, settings, plan, _ in
            probe.lock.lock(); probe.transports.append(settings.transport); probe.uploaded.append(plan.remoteURL); probe.lock.unlock()
            let (blocks, failure) = probe.begin()
            if blocks { probe.gate.wait() }
            if let failure { throw failure }
            return plan.publicURL ?? plan.remoteURL
        }
        app.publishing.clipboardWriter = { url in probe.lock.lock(); probe.copied.append(url); probe.lock.unlock() }
    }

    static func webpostUploadsImmediately() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); install(probe, on: app)
        app.nameField.stringValue = "Shot"
        try webpostButton(app).performClick(nil)
        try expect(app.window.attachedSheet == nil && app.status.stringValue == "Uploading Shot…", "Webpost starts at once: no sheet, status reads Uploading Shot… (\(app.status.stringValue))")
        try waitForMain("The upload finishes") { !app.publishing.isBusy && probe.count == 1 }
        try waitForMain("Success is reported") { app.status.stringValue.hasPrefix("Link copied") }
        try expect(probe.copied.count == 1 && probe.copied[0].absoluteString.hasPrefix("https://cdn.example.com/imgs/Shot-")
                   && app.uploadState == .success(url: probe.copied[0], copied: true) && AppToolTip.text(for: app.status) == "Link copied: " + probe.copied[0].absoluteString,
                   "The verified public URL is copied; the status says Link copied · the link, and the full link rides on the tooltip (audit fix 1: the status shows the link, middle-cut to the slot)")
        try expect(app.window.attachedSheet == nil && AppSafetyAlert.seen.isEmpty, "No sheet or alert at any point")
    }

    static func webpostIgnoresSecondClick() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); probe.blocks = true; install(probe, on: app)
        let button = try webpostButton(app)
        button.performClick(nil)
        try waitForMain("The first upload reaches the transfer") { probe.count == 1 }
        try expect(app.publishing.isBusy, "The coordinator is busy during the transfer")
        button.performClick(nil)
        try expect(app.status.stringValue.hasPrefix("Uploading") && app.window.attachedSheet == nil && AppSafetyAlert.seen.isEmpty,
                   "A second click changes nothing on screen: the running upload keeps the status line (\(app.status.stringValue))")
        probe.gate.signal()
        try waitForMain("The first upload completes") { !app.publishing.isBusy && app.status.stringValue.hasPrefix("Link copied") }
        try expect(probe.count == 1 && probe.copied.count == 1, "Exactly one upload ran (\(probe.count))")
    }

    static func webpostUnconfiguredOpensSettings() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); install(probe, on: app)
        try configureDestinations(app, [])
        var opened = 0
        app.sharingSettingsPresenter = { opened += 1 }
        try webpostButton(app).performClick(nil)
        try expect(opened == 1 && probe.count == 0 && !app.publishing.isBusy && app.window.attachedSheet == nil, "Settings open, nothing uploads")
        try FileManager.default.createDirectory(at: app.publishing.store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: app.publishing.store.file)
        try webpostButton(app).performClick(nil)
        try expect(opened == 2 && probe.count == 0, "An unreadable destination also opens settings")
    }

    static func webpostFailureRecovers() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); probe.failure = PublishingFailure("Server said no."); install(probe, on: app)
        let button = try webpostButton(app)
        button.performClick(nil)
        try waitForMain("The failure is surfaced inline") { app.status.stringValue == "Server said no." && !app.publishing.isBusy }
        try expect(probe.copied.isEmpty && AppSafetyAlert.seen.isEmpty && app.window.attachedSheet == nil, "A failed upload copies nothing and raises no alert (OSN-054 moved the error inline)")
        probe.failure = nil
        button.performClick(nil)
        try waitForMain("Webpost works again after a failure") { probe.count == 2 && app.status.stringValue.hasPrefix("Link copied") }
    }


    private static func s3Destination() -> PublishingSettings {
        var settings = PublishingSettings()
        settings.transport = .s3; settings.remoteFolder = "pics"; settings.publicBaseURL = "https://cdn.example.com/pics/"
        var options = S3Options(); options.bucket = "cdn.example.com"; options.credentialsProfile = "default"
        settings.s3 = options
        return settings
    }

    static func webpostMultipleDestinations() throws {
        let fixture = try Fixture(), app = fixture.app
        try configureDestinations(app, [try fakeDestination(), s3Destination()], names: ["Home SFTP", "AWS cdn"])
        let probe = UploadProbe(); install(probe, on: app)
        try expect(try menuLayout(app) == ["✓ Home SFTP", "AWS cdn", "-", "Destination Settings…", "Share with macOS…"], "Both destinations are listed, the default checked: \(try menuLayout(app))")
        let menu = try webpostButton(app).menu.unwrap("menu"); app.menuNeedsUpdate(menu)
        let other = try menu.items.first { $0.title == "AWS cdn" }.unwrap("AWS cdn item")
        _ = NSApp.sendAction(try other.action.unwrap("action"), to: other.target, from: other)
        try expect(try menuLayout(app) == ["Home SFTP", "✓ AWS cdn", "-", "Destination Settings…", "Share with macOS…"], "Choosing a destination moves the check: \(try menuLayout(app))")
        let reopened = PublishingDestinationStore(directory: app.publishing.store.directory, secrets: PublishingMemorySecrets())
        try expect(try reopened.defaultDestination()?.name == "AWS cdn", "The default is persisted on disk, not just in the menu")
        app.nameField.stringValue = "Shot"
        try webpostButton(app).performClick(nil)
        try waitForMain("The upload finishes") { !app.publishing.isBusy && probe.count == 1 && app.status.stringValue.hasPrefix("Link copied") }
        try expect(probe.transports == [.s3], "The next Webpost click uploaded to the S3 destination (\(probe.transports))")
        try expect(probe.uploaded[0].absoluteString.hasPrefix("https://s3.us-east-1.amazonaws.com/cdn.example.com/pics/Shot-"), "It used the path-style S3 URL (\(probe.uploaded[0]))")
        try expect(probe.copied.count == 1 && probe.copied[0].absoluteString.hasPrefix("https://cdn.example.com/pics/Shot-"), "The public link comes from the S3 destination's public base URL")
        // Switching back sends the next click to the first destination again.
        let first = try menu.items.first { $0.title == "Home SFTP" }.unwrap("Home SFTP item")
        _ = NSApp.sendAction(try first.action.unwrap("action"), to: first.target, from: first)
        try webpostButton(app).performClick(nil)
        try waitForMain("The second upload finishes") { !app.publishing.isBusy && probe.count == 2 && app.status.stringValue.hasPrefix("Link copied") }
        try expect(probe.transports == [.s3, .sftp], "Switching back uploads over SFTP again (\(probe.transports))")
    }

    static func webpostDestinationSettingsRoundTrip() throws {
        let fixture = try Fixture(), app = fixture.app
        try configureDestinations(app, [try fakeDestination()], names: ["Home SFTP"])
        let (_, view) = app.publishing.buildEditor(editing: nil)
        defer { app.publishing.cancelSettings() }
        try expect(app.publishing.destinations().destinations.map(\.name) == ["Home SFTP"], "The saved destination is there to start with")
        // Add an S3 destination the way a user would: Add…, fill the form, Save. A saved editor closes itself.
        view.nameField.stringValue = "AWS cdn"
        view.protocolPopup.selectItem(withTitle: PublishingProtocol.s3.title); view.formChanged()
        view.bucketField.stringValue = "cdn.example.com"; view.regionField.stringValue = "us-east-1"
        view.folderField.stringValue = "pics"; view.publicField.stringValue = "https://cdn.example.com/pics/"
        view.sourcePopup.selectItem(at: 0); view.formChanged(); view.profileField.stringValue = "default"
        view.saveTapped()
        try waitForMain("The new destination is saved") { app.publishing.destinations().destinations.count == 2 && app.publishing.destinationsView == nil }
        let list = app.publishing.destinations()
        let saved = try list.destinations.first { $0.name == "AWS cdn" }.unwrap("saved S3 destination")
        try expect(saved.settings.transport == .s3 && saved.settings.s3?.credentialsProfile == "default" && saved.settings.s3?.bucket == "cdn.example.com", "S3 fields round-trip")
        try expect(try app.publishing.store.load() == list && list.defaultDestination?.name == "Home SFTP", "Storage matches and the default is unchanged")
        // Make Default, through the Settings › Upload button.
        app.openPreferences(tab: SettingsWindowController.uploadTabIndex)
        let settings = try app.settingsController.unwrap("Settings controller")
        try expect(settings.upload.listedNames == ["Home SFTP", "AWS cdn"], "Settings, Upload lists both (\(settings.upload.listedNames))")
        settings.upload.select(id: saved.id); settings.upload.defaultButton.performClick(nil)
        try expect(try app.publishing.store.defaultDestination()?.id == saved.id && settings.upload.rows[1].pill != nil, "Make Default persists and the pill moves")
        // A bad edit is refused and nothing changes.
        let (_, editView) = app.publishing.buildEditor(editing: saved)
        editView.bucketField.stringValue = "NOT_VALID"; editView.saveTapped()
        try waitForMain("The invalid edit is refused") { editView.formResult.kind == .failure }
        try expect(try app.publishing.store.load().destinations.first { $0.id == saved.id }?.settings.s3?.bucket == "cdn.example.com", "An invalid bucket is not saved")
        app.publishing.cancelSettings()
        // Remove the default: the prompt names the destination and the next default; declining removes nothing.
        let prompt = app.publishing.destinations().removalPrompt(for: saved)
        try expect(prompt.title == "Remove “AWS cdn”?" && prompt.detail.contains("default") , "the prompt names the destination and says what becomes the default (\(prompt))")
        settings.upload.select(id: saved.id)
        AppSafetyAlert.answers.append(.init(title: "Remove “AWS cdn”?", response: .alertFirstButtonReturn))
        settings.upload.removeButton.performClick(nil)
        try expect(app.publishing.destinations().destinations.count == 2, "Declining the confirmation removes nothing")
        AppSafetyAlert.answers.append(.init(title: "Remove “AWS cdn”?", response: .alertSecondButtonReturn))
        settings.upload.removeButton.performClick(nil)
        try expect(app.publishing.destinations().destinations.map(\.name) == ["Home SFTP"] && (try app.publishing.store.defaultDestination()?.name) == "Home SFTP" && settings.upload.listedNames == ["Home SFTP"],
                   "Removing the default promotes the remaining destination, and the list follows")
        try expect(app.publishing.isConfigured, "The remaining destination keeps Webpost configured")
        app.closePreferences()
    }

    private static func menuLayout(_ app: AppDelegate) throws -> [String] {
        let menu = try webpostButton(app).menu.unwrap("Upload menu")
        app.menuNeedsUpdate(menu)
        return menu.items.map { $0.isSeparatorItem ? "-" : ($0.state == .on ? "✓ " : "") + $0.title + ($0.isEnabled ? "" : " (disabled)") }
    }

    static func webpostMenu() throws {
        let fixture = try Fixture(), app = fixture.app
        let button = try webpostButton(app)
        try expect(button.menu != nil && (button as? OriginalActionButton)?.showMenuOnLeftClick == false
                   && AppToolTip.text(for: button) == "Upload image and copy link · Right-click for destinations", "The button has a right-click menu, left-click stays the action, and the tooltip says so")
        try expect(try menuLayout(app) == ["✓ SFTP · test-host", "-", "Destination Settings…", "Share with macOS…"], "Configured menu: \(try menuLayout(app))")
        try configureDestinations(app, [])
        try expect(try menuLayout(app) == ["No destination configured (disabled)", "-", "Destination Settings…", "Share with macOS…"], "Unconfigured menu: \(try menuLayout(app))")
        // The builder takes any list, so more destinations only add rows; only the default is checked.
        let items = app.uploadDestinationMenuItems(destinations: [.init(id: "a", title: "A"), .init(id: "b", title: "B")], defaultID: "b")
        try expect(items.map(\.state).prefix(2) == [.off, .on] && items.count == 5, "Only the default destination is checked")
        // Items reach the settings sheet and the macOS picker through their seams.
        var opened = 0, shared = 0
        app.sharingSettingsPresenter = { opened += 1 }
        app.sharePickerPresenter = { _, anchor in if anchor === button { shared += 1 } }
        let menu = try button.menu.unwrap("menu"); app.menuNeedsUpdate(menu)
        for title in ["Destination Settings…", "Share with macOS…"] {
            let item = try menu.items.first { $0.title == title }.unwrap(title)
            _ = NSApp.sendAction(try item.action.unwrap("action"), to: item.target, from: item)
        }
        try expect(opened == 1 && shared == 1, "Settings and Share items each fire once, Share relative to the button")
    }

    static func webpostFileMenu() throws {
        let fixture = try Fixture(), app = fixture.app
        let file = try NSApp.mainMenu.unwrap("main menu").items.compactMap(\.submenu).first { $0.title == "File" }.unwrap("File menu")
        let share = try file.items.first { $0.title == "Share…" }.unwrap("File › Share…")
        try expect(share.action == #selector(AppDelegate.shareFromMenu), "File › Share… opens the macOS picker")
        let probe = UploadProbe(); install(probe, on: app)
        let publish = try file.items.first { $0.title == "Publish…" }.unwrap("Publish…")
        _ = NSApp.sendAction(try publish.action.unwrap("action"), to: app, from: publish)
        try expect(app.window.attachedSheet == nil && app.status.stringValue.hasPrefix("Uploading"), "Publish… uploads without a confirmation sheet")
        try waitForMain("it finishes") { !app.publishing.isBusy && probe.count == 1 }
    }

    static func webpostProgressSurvivesStatusUpdates() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); probe.blocks = true; install(probe, on: app)
        app.nameField.stringValue = "Held"
        try webpostButton(app).performClick(nil)
        try waitForMain("The transfer starts") { probe.count == 1 }
        app.canvas.tool = .rectangle
        app.updateStatus()
        var box = SketchElement(kind: .rectangle); box.rect = CGRect(x: 10, y: 10, width: 40, height: 30)
        app.canvas.document.elements.append(box)
        app.dirty = true
        app.updateStatus()
        try expect(app.status.stringValue == "Uploading Held…", "A tool change and an edit keep the upload text (\(app.status.stringValue))")
        probe.gate.signal()
        try waitForMain("The upload finishes") { !app.publishing.isBusy && app.status.stringValue.hasPrefix("Link copied") }
        app.expireUploadSuccess() // the 4 s of "Link copied" are over
        try expect(app.status.stringValue.contains("Unsaved changes") || app.status.stringValue.contains("Saved"), "After completion the normal status returns (\(app.status.stringValue))")
    }

    static func webpostCancel() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); probe.blocks = true; install(probe, on: app)
        try expect(try menuLayout(app).first != "Cancel Upload", "No Cancel Upload while idle")
        try webpostButton(app).performClick(nil)
        try waitForMain("The transfer starts") { probe.count == 1 }
        let menu = try webpostButton(app).menu.unwrap("menu"); app.menuNeedsUpdate(menu)
        let cancel = try menu.items.first.unwrap("first item")
        try expect(cancel.title == "Cancel Upload" && cancel.isEnabled && menu.items[1].isSeparatorItem, "Cancel Upload leads the busy menu and is enabled")
        _ = NSApp.sendAction(try cancel.action.unwrap("action"), to: cancel.target, from: cancel)
        probe.gate.signal()
        try waitForMain("The upload is cancelled") { !app.publishing.isBusy && app.status.stringValue == "Upload cancelled" }
        try expect(probe.copied.isEmpty && AppSafetyAlert.seen.isEmpty && app.window.attachedSheet == nil, "Cancelling copies nothing and raises no alert")
        app.menuNeedsUpdate(menu)
        try expect(menu.items.first?.title != "Cancel Upload", "Cancel Upload leaves the menu once idle")
    }

    static func webpostNoPublicURLNoClipboard() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = UploadProbe(); install(probe, on: app)
        var bare = try fakeDestination(); bare.publicBaseURL = ""
        try configureDestinations(app, [bare])
        try webpostButton(app).performClick(nil)
        try waitForMain("The upload finishes") { !app.publishing.isBusy && probe.count == 1 && app.status.stringValue != "" && !app.status.stringValue.hasPrefix("Uploading") }
        try expect(probe.copied.isEmpty, "No public URL means nothing reaches the clipboard (\(probe.copied))")
        try expect(app.status.stringValue == "Uploaded image to destination", "Status reads Uploaded image to destination (\(app.status.stringValue))")
    }

    static func webpostMenuFont() throws {
        let fixture = try Fixture(), app = fixture.app
        try expect(try webpostButton(app).menu.unwrap("menu").font.pointSize >= 20, "The right-click menu is 20 pt like the other menus")
    }

    static func webpostEyeDumpAuditGate() throws {
        let args = ["OpenSnap", "--eye-dump-audit", "/tmp/audit-out"]
        let support = NSTemporaryDirectory()
        let isolated = ["OPENSNAP_APP_SUPPORT": support, "CFFIXED_USER_HOME": "/tmp/audit-home"]
        let throwaway = AppDelegate.auditBundlePrefix + "123"
        try expect(AppDelegate.eyeDumpAuditDirectory(arguments: args, environment: isolated, bundleIdentifier: throwaway)?.path == "/tmp/audit-out", "Fully isolated harness copy: honoured")
        try expect(AppDelegate.eyeDumpAuditDirectory(arguments: args, environment: isolated, bundleIdentifier: "com.shoemoney.opensnap") == nil, "The real bundle id: ignored")
        try expect(AppDelegate.eyeDumpAuditDirectory(arguments: args, environment: isolated, bundleIdentifier: nil) == nil, "A bare binary without a bundle id: ignored")
        try expect(AppDelegate.eyeDumpAuditDirectory(arguments: args, environment: isolated, bundleIdentifier: "com.example.other") == nil, "Any non-harness bundle id: ignored")
        try expect(AppDelegate.eyeDumpAuditDirectory(arguments: args, environment: isolated.merging(["OPENSNAP_FIXTURE": "/tmp/doc.opensnap"]) { $1 }, bundleIdentifier: throwaway) == nil, "A document fixture: ignored")
        try expect(AppDelegate.eyeDumpAuditDirectory(arguments: args, environment: ["OPENSNAP_APP_SUPPORT": support], bundleIdentifier: throwaway) == nil, "No isolated home: ignored")
        try expect(AppDelegate.eyeDumpAuditDirectory(arguments: args, environment: ["CFFIXED_USER_HOME": "/tmp/audit-home"], bundleIdentifier: throwaway) == nil, "No isolated support folder: ignored")
        try expect(AppDelegate.eyeDumpAuditDirectory(arguments: ["OpenSnap"], environment: isolated, bundleIdentifier: throwaway) == nil, "No flag: nil")
    }

    static func webpostModernIconOnly() throws {
        let fixture = try Fixture(), app = fixture.app
        guard let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "Modern chrome required") }
        let button = chrome.shareButton
        try expect(button.title.isEmpty && button.imagePosition == .imageOnly && button.icon == nil && button.image?.isTemplate == true,
                   "The upload button has no title and a native symbol image")
        try expect(ModernEditorChrome.uploadSymbolName == "icloud.and.arrow.up" && NSImage(systemSymbolName: ModernEditorChrome.uploadSymbolName, accessibilityDescription: nil) != nil
                   && button.image?.accessibilityDescription == "Upload image", "It shows icloud.and.arrow.up")
        try expect(button.accessibilityLabel() == "Upload image", "VoiceOver reads the label, not the symbol name")
        try expect(button.action == #selector(AppDelegate.share(_:)) && button.menu != nil, "It uploads on click and carries the destination menu")
        try expect(button.frame.width <= 48 && button.frame.height == 36 && button.frame.height >= DesignTokens.Size.hitMin, "It is a compact icon button, not a labelled capsule (\(button.frame.size))")
    }
}

private extension Optional {
    func unwrap(_ name: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing \(name)") }
        return self
    }
}
#endif
