// F-J2-002 end to end: an S3 profile destination uploads, History keeps the deletion binding, Delete from Web is on, and one signed
// DELETE goes to the path-style object URL. Every curl is a recorder; the AWS credentials are a fake file in the isolated support folder.
// Nothing touches the network, ~/.aws, the Keychain or the owner's destinations.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var s3EndToEndCases: [(String, () throws -> Void)] {
        [
            ("S3 end to end: upload keeps a binding, Delete from Web is on, and one signed DELETE hits the path-style object URL (F-J2-002)", s3UploadBindDelete)
        ]
    }

    /// Stands in for /usr/bin/curl. It answers like S3 would and writes down every config it was given.
    private final class FakeCurl: @unchecked Sendable {
        let lock = NSLock()
        private(set) var configs: [String] = []
        private var uploaded = Data()
        func run(_ config: Data) -> PublishingProcess.Output {
            let text = String(decoding: config, as: UTF8.self)
            lock.lock(); configs.append(text); lock.unlock()
            func value(_ key: String) -> String? {
                text.components(separatedBy: "\n").first { $0.hasPrefix(key + " = \"") }
                    .map { String($0.dropFirst(key.count + 4).dropLast()) }
            }
            let url = value("url") ?? ""
            if text.contains("request = \"GET\""), let output = value("output") {
                // The post-upload check of the public URL: serve back exactly the bytes the PUT carried.
                lock.lock(); let served = uploaded; lock.unlock()
                try? served.write(to: URL(fileURLWithPath: output))
                return .init(stdout: "200\n\(url)\n\(served.count)\n", stderr: "", code: 0)
            }
            if text.contains("request = \"DELETE\"") { return .init(stdout: "204\n\(url)\n0\n", stderr: "", code: 0) }
            if let file = value("upload-file"), let bytes = try? Data(contentsOf: URL(fileURLWithPath: file)) { lock.lock(); uploaded = bytes; lock.unlock() }
            let size = value("upload-file").flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? Int } ?? 0
            return .init(stdout: "200\n\(url)\n\(size)\n", stderr: "", code: 0)
        }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return configs }
    }

    /// The deletion side as the app builds it, minus the system tools: settings from the app's own destination store, credentials from the
    /// same fake file the upload used, and the recorder instead of curl.
    private struct S3DeletionAdapter: HistoryRemoteDeletionAdapter {
        let store: PublishingDestinationStore, credentialsFile: URL, curl: FakeCurl
        func loadSettings() throws -> PublishingSettings {
            guard let settings = try store.defaultDestination()?.settings else { throw PublishingFailure("No default destination.") }
            return settings
        }
        func sshSourceFingerprint() throws -> String { throw PublishingFailure("S3 never reads SSH config.") }
        func capabilities(cancellation: PublishingCancellation) throws -> PublishingCapabilities {
            try PublishingCapabilities(versionOutput: "curl 8.7.1 fake\nProtocols: http https\nFeatures: SSL\n")
        }
        func inspectSSH(_ plan: PublishingSFTPPlan, cancellation: PublishingCancellation) throws -> HistoryDeletionSSHConfiguration {
            throw PublishingFailure("S3 never resolves an SSH alias.")
        }
        func password(credentialID: String) throws -> String { throw PublishingFailure("S3 has no WebDAV password.") }
        func s3Credentials(settings: PublishingSettings) throws -> S3Credentials {
            try PublishingS3Credentials.resolve(settings: settings, secrets: store.secrets, credentialsFile: credentialsFile)
        }
        func execute(_ command: HistoryRemoteDeletionCommand, cancellation: PublishingCancellation) throws -> PublishingProcess.Output {
            guard command.executable == "/usr/bin/curl", command.arguments == PublishingS3Operations.curlArguments else {
                throw PublishingFailure("Unexpected command \(command.executable) \(command.arguments)")
            }
            return curl.run(command.input)
        }
    }

    private static func s3EndToEndDestination() -> PublishingSettings {
        var settings = PublishingSettings()
        settings.transport = .s3; settings.remoteFolder = "pics"; settings.publicBaseURL = "https://cdn.example.com/pics/"
        var options = S3Options(); options.bucket = "cdn.example.com"; options.credentialsProfile = "default"
        settings.s3 = options
        return settings
    }

    static func s3UploadBindDelete() throws {
        let fixture = try Fixture(), app = fixture.app, store = try isolatedHistory(app)
        let key = "AKIAFAKEFAKEFAKE0001", secret = "fake-secret-key-for-the-e2e-test-only"
        let credentials = app.support.appendingPathComponent("fake-aws-credentials")
        try Data("[default]\naws_access_key_id = \(key)\naws_secret_access_key = \(secret)\n".utf8).write(to: credentials)
        try configureDestinations(app, [s3EndToEndDestination()], names: ["AWS cdn"])
        let curl = FakeCurl()
        let savedRunner = PublishingS3Operations.curlRunner, savedCapabilities = PublishingCurl.capabilitiesOverride
        let savedCheck = PublishingTransfer.publicCheckRunner
        PublishingS3Operations.curlRunner = { config, _, _ in curl.run(config) }
        PublishingTransfer.publicCheckRunner = { config, _ in curl.run(config) }
        PublishingCurl.capabilitiesOverride = try PublishingCapabilities(versionOutput: "curl 8.7.1 fake\nProtocols: http https\nFeatures: SSL\n")
        defer { PublishingS3Operations.curlRunner = savedRunner; PublishingTransfer.publicCheckRunner = savedCheck; PublishingCurl.capabilitiesOverride = savedCapabilities }

        // The production uploader (plan, credentials from the profile, signed PUT, verification), not the fixture's stub.
        let real = PublishingCoordinator()
        real.store = app.publishing.store; real.awsCredentialsFile = { credentials }
        app.publishing.awsCredentialsFile = { credentials }
        app.publishing.uploader = real.uploader
        app.historyRemoteDeletion = HistoryRemoteDeletionCoordinator(adapter: S3DeletionAdapter(store: app.publishing.store, credentialsFile: credentials, curl: curl))

        try withExtendedLifetime(real) {
            // An empty canvas archives nothing, so the upload has a drawing to keep.
            var drawing = SketchDocument(size: CGSize(width: 120, height: 90))
            var shape = SketchElement(kind: .rectangle)
            shape.rect = CGRect(x: 12, y: 15, width: 30, height: 20); shape.filled = true; shape.color = SketchColor(.red)
            drawing.elements = [shape]
            try app.canvas.loadDocument(data: drawing.encoded())
            app.nameField.stringValue = "Shot"
            try webpostClick(app)
            try? waitForMain("upload") { !app.publishing.isBusy && store.entries.count == 1 }
            try expect(!app.publishing.isBusy && store.entries.count == 1, "The S3 upload is archived in History (status \(app.status.stringValue), state \(app.uploadState), curl \(curl.all.count), entries \(store.entries.count))")
            let entry = try store.entries.first.s3Unwrap("archived entry")
            let uploads = curl.all.filter { $0.contains("upload-file") }
            try expect(curl.all.count == 2 && curl.all.filter({ $0.contains("request = \"GET\"") }).count == 1 && !curl.all[1].contains(secret),
                       "The PUT is followed by one unsigned GET of the public link, which carries no key (\(curl.all.count) requests)")
            try expect(uploads.count == 1 && uploads[0].contains("upload-file") && uploads[0].contains("aws-sigv4") && uploads[0].contains("\(key):\(secret)"),
                       "One signed PUT, with the key pair from the profile file: \(uploads)")
            try expect(uploads[0].contains("url = \"https://s3.us-east-1.amazonaws.com/cdn.example.com/pics/Shot-"), "The PUT goes to the path-style URL")
            let link = try entry.remoteURL.s3Unwrap("public link")
            try expect(link.absoluteString.hasPrefix("https://cdn.example.com/pics/Shot-") && entry.destination == link.absoluteString, "History records the public link (\(link))")
            let binding = try entry.remoteBinding.s3Unwrap("The archive kept a deletion binding for the S3 upload")
            try expect(binding["publicURL"] == link.absoluteString && binding["version"] == "1" && binding["sshConfigSHA256"] == nil
                       && !binding.values.joined().contains(secret) && !binding.values.joined().contains(key), "The binding names the object, not the keys: \(binding)")

            app.showHistory()
            guard let history = app.historyWindow as? AppSafetyWindow, let browser = app.historyBrowser else { throw Failure(description: "History window") }
            history.simulatesVisibility = true; history.shown = true
            browser.select(ids: [entry.id])
            let button = try browser.actionRow.arrangedSubviews.compactMap { $0 as? NSButton }
                .first { $0.accessibilityLabel() == HistoryBrowser.Action.deleteRemote.title }.s3Unwrap("Delete from Web button")
            try expect(browser.canPerform(.deleteRemote) && button.isEnabled, "Delete from Web is enabled for the S3 upload")

            AppSafetyAlert.answers = [.init(title: "Delete this web post?", response: .alertSecondButtonReturn)]
            button.performClick(nil)
            try waitForMain("The web post is deleted and its remote fields are cleared") { store.entry(entry.id)?.remoteURL == nil }
            let requests = curl.all
            let deletes = requests.filter { $0.contains("request = \"DELETE\"") }
            try expect(requests.count == 3 && deletes.count == 1, "Exactly one DELETE after the PUT and the public check: \(requests.count) requests in all")
            let delete = deletes[0]
            try expect(delete.contains("request = \"DELETE\"") && delete.contains("aws-sigv4") && !delete.contains("upload-file"), "It is a signed DELETE, not an upload: \(delete)")
            let objectName = link.lastPathComponent
            try expect(delete.contains("url = \"https://s3.us-east-1.amazonaws.com/cdn.example.com/pics/\(objectName)\""), "It targets the path-style URL of the uploaded object: \(delete)")
            try expect(delete.contains("\(key):\(secret)"), "It is signed with the profile's keys")
            let after = try store.entry(entry.id).s3Unwrap("History copy kept")
            try expect(after.remoteURL == nil && after.remoteBinding == nil && after.destination == entry.destination, "The remote fields are cleared and the editable copy stays")
            try expect(!browser.canPerform(.deleteRemote) && !button.isEnabled, "Delete from Web is off once there is no web post")
            try expect(AppSafetyAlert.seen == ["Delete this web post?"] && browser.statusLine == AppDelegate.deletedFromWebNotice(host: link.host) && browser.statusLine.contains("Cached copies"), "One question, then the History footer says where it was deleted from and that caches may linger (\(AppSafetyAlert.seen), \(browser.statusLine))")
        }
    }

    private static func webpostClick(_ app: AppDelegate) throws {
        try (app.webpostButton).s3Unwrap("Webpost button").performClick(nil)
    }
}
private extension Optional {
    func s3Unwrap(_ what: String) throws -> Wrapped {
        guard let value = self else { throw AppSafetyTests.Failure(description: "Missing \(what)") }
        return value
    }
}
#endif
