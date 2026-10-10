import AppKit
import Foundation

// Standalone pure checks for multi-destination storage and S3 transport. No network, no Keychain,
// no real ~/.aws and no real Application Support: every path is a fresh temp folder, secrets are in memory.
// xcrun swiftc -swift-version 5 Sources/Publishing.swift Sources/PublishingS3.swift Sources/PublishingDestinations.swift Sources/PublishingDestinationsView.swift tests/PublishingDestinationsTests.swift -o /tmp/opensnap-destinations-tests
// /tmp/opensnap-destinations-tests --test
// Explicit integration path (never run by --test):
// /tmp/opensnap-destinations-tests --live-s3 "AWS cdn"
@main
enum PublishingDestinationsTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw PublishingFailure("SELF-CHECK FAILED: " + message) }
        checks += 1
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { checks += 1; return }
        throw PublishingFailure("SELF-CHECK FAILED: accepted " + message)
    }
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("opensnap-destinations-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func main() throws {
        if CommandLine.arguments.contains("--live-s3") { try liveS3(); return }
        guard CommandLine.arguments.contains("--test") else { print("Run with --test for pure destination and S3 self-checks."); return }
        try s3Plan()
        try s3Responses()
        try credentialsFile()
        try memorySecretsMessage()
        try migration()
        try storeOperations()
        try MainActor.assumeIsolated { try destinationsSheet() }
        try MainActor.assumeIsolated { try formCopyAndLabels() }
        try MainActor.assumeIsolated { try resultBandAndSheetWidth() }
        try connectionTests()
        print("Destination and S3 self-checks passed: \(checks). No uploads were executed.")
    }

    static let capabilities = try! PublishingCapabilities(versionOutput: "curl 8.7.1 test\nProtocols: ftp ftps http https sftp\nFeatures: SSL\n")

    static func awsCDN() -> PublishingSettings {
        var settings = PublishingSettings()
        settings.transport = .s3; settings.remoteFolder = "pics"; settings.publicBaseURL = "https://cdn.shoemoney.com/pics/"
        var options = S3Options(); options.region = "us-east-1"; options.bucket = "cdn.shoemoney.com"; options.credentialsProfile = "default"
        settings.s3 = options
        return settings
    }

    // MARK: S3 request generation

    static func s3Plan() throws {
        let plan = try PublishingPlan(settings: awsCDN(), fileName: "My Shot #1 café-0a1b.png", capabilities: capabilities)
        try expect(PublishingS3Plan.safeFileName("My Shot #1 café.png") == "My-Shot-1-caf-.png", "unsafe characters become single hyphens")
        try expect(PublishingS3Plan.safeFileName("..hidden") == "hidden" && PublishingS3Plan.safeFileName("") == "image.png", "leading dots stripped, empty falls back")
        try expect(plan.remoteURL.absoluteString == "https://s3.us-east-1.amazonaws.com/cdn.shoemoney.com/pics/My-Shot-1-caf-0a1b.png",
                   "AWS URL is path-style even for a bucket name containing dots (\(plan.remoteURL))")
        try expect(plan.publicURL?.absoluteString == "https://cdn.shoemoney.com/pics/My-Shot-1-caf-0a1b.png", "public URL is base + the same safe name")
        try expect(plan.s3?.signingProvider == "aws:amz:us-east-1:s3", "sigv4 provider string")
        let file = URL(fileURLWithPath: "/tmp/image"), response = URL(fileURLWithPath: "/tmp/response")
        let secret = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
        let text = String(decoding: try plan.curlConfig(file: file, username: "AKIAIOSFODNN7EXAMPLE", password: secret, sessionToken: "FwoGZXIvYXdzEXAMPLE", responseFile: response), as: UTF8.self)
        try expect(text.contains("aws-sigv4 = \"aws:amz:us-east-1:s3\"\n"), "config carries the sigv4 provider")
        try expect(text.components(separatedBy: "\n").filter { $0.hasPrefix("user = ") } == ["user = \"AKIAIOSFODNN7EXAMPLE:\(secret)\""], "key pair appears once, in the stdin config")
        try expect(text.contains("header = \"x-amz-security-token: FwoGZXIvYXdzEXAMPLE\"\n"), "session token is a header")
        try expect(text.contains("header = \"Content-Type: image/png\"\n") && text.contains("upload-file = \"/tmp/image\"\n"), "PUT of the file with its content type")
        try expect(text.contains("header = \"x-amz-content-sha256: UNSIGNED-PAYLOAD\"\n"), "the PUT sends the explicit unsigned-payload hash header (curl 7.86+ honours it)")
        try expect(!text.lowercased().contains("x-amz-acl"), "no ACL header by default")
        try expect(text.contains("url = \"https://s3.us-east-1.amazonaws.com/cdn.shoemoney.com/pics/My-Shot-1-caf-0a1b.png\"\n"), "config url is the path-style object URL")
        try expect(!text.contains("insecure") && !text.contains("location") && !text.contains("\nfail\n"), "no insecure TLS, redirects or --fail (the body is needed for diagnostics)")
        try expect(PublishingS3Operations.curlArguments == ["--disable", "--config", "-"], "argv never carries a secret")
        let bare = String(decoding: try plan.curlConfig(file: file, username: "AKIAIOSFODNN7EXAMPLE", password: secret, responseFile: response), as: UTF8.self)
        try expect(!bare.contains("x-amz-security-token"), "no token header without a session token")
        var acl = awsCDN(); acl.s3?.publicReadACL = true
        let aclText = String(decoding: try PublishingPlan(settings: acl, fileName: "a.png", capabilities: capabilities).curlConfig(file: file, username: "AKIAIOSFODNN7EXAMPLE", password: secret, responseFile: response), as: UTF8.self)
        try expect(aclText.contains("x-amz-acl: public-read"), "the public-read ACL header exists only when opted in")

        var r2 = awsCDN(); r2.endpoint = "https://acct123.r2.cloudflarestorage.com"; r2.s3?.region = "auto"; r2.s3?.bucket = "shots"; r2.remoteFolder = "a/b"
        let r2Plan = try PublishingPlan(settings: r2, fileName: "x.jpg", capabilities: capabilities)
        try expect(r2Plan.remoteURL.absoluteString == "https://acct123.r2.cloudflarestorage.com/shots/a/b/x.jpg", "custom endpoint is <endpoint>/<bucket>/<key>")
        try expect(r2Plan.s3?.contentType == "image/jpeg" && r2Plan.s3?.signingProvider == "aws:amz:auto:s3", "content type by extension, region in the provider")
        var minio = r2; minio.endpoint = "http://192.168.1.10:9000/base"
        try expect(try PublishingPlan(settings: minio, fileName: "x.png", capabilities: capabilities).remoteURL.absoluteString == "http://192.168.1.10:9000/base/shots/a/b/x.png", "http MinIO endpoint with a base path")

        for host in ["localhost", "127.0.0.1", "127.8.9.1", "[::1]", "10.0.0.5", "172.16.0.1", "172.31.255.1", "192.168.1.10", "nas.local"] {
            var local = r2; local.endpoint = "http://\(host):9000"
            _ = try PublishingPlan(settings: local, fileName: "x.png", capabilities: capabilities)
        }
        for host in ["s3.example.com", "8.8.8.8", "172.32.0.1", "172.15.0.1", "192.169.1.1", "11.0.0.1", "10.0.0", "evil.local.example.com", "1.2.3.4.5"] {
            var open = r2; open.endpoint = "http://\(host)"
            try rejects("plain http to \(host)") { _ = try PublishingPlan(settings: open, fileName: "x.png", capabilities: capabilities) }
        }
        var httpsPublic = r2; httpsPublic.endpoint = "https://8.8.8.8"
        _ = try PublishingPlan(settings: httpsPublic, fileName: "x.png", capabilities: capabilities)

        var keyed = awsCDN(); keyed.s3?.credentialsProfile = ""; keyed.username = "AKIAIOSFODNN7EXAMPLE"
        _ = try PublishingPlan(settings: keyed, fileName: "x.png", capabilities: capabilities)
        keyed.username = ""
        try rejects("an empty access key ID without a profile") { _ = try PublishingPlan(settings: keyed, fileName: "x.png", capabilities: capabilities) }
        for bucket in ["", "ab", "Upper", "under_score", "a..b", "-start", "end-", "x/y", "a b"] {
            var invalid = awsCDN(); invalid.s3?.bucket = bucket
            try rejects("bucket \(bucket)") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: capabilities) }
        }
        for region in ["", "U S", "us/east", "../x", "x"] {
            var invalid = awsCDN(); invalid.s3?.region = region
            try rejects("region \(region)") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: capabilities) }
        }
        for folder in ["../x", "a/./b", "my pics", "a%2Fb", "a\nb"] {
            var invalid = awsCDN(); invalid.remoteFolder = folder
            try rejects("key prefix \(folder)") { _ = try PublishingPlan(settings: invalid, fileName: "x.png", capabilities: capabilities) }
        }
        var badProfile = awsCDN(); badProfile.s3?.credentialsProfile = "bad profile\n"
        try rejects("profile with whitespace") { _ = try PublishingPlan(settings: badProfile, fileName: "x.png", capabilities: capabilities) }
        try rejects("missing curl capabilities") { _ = try PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: nil) }
        let old = try PublishingCapabilities(versionOutput: "curl 7.74.0 test\nProtocols: http https\nFeatures: SSL\n")
        try rejects("curl older than 7.75") { _ = try PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: old) }
        let oldish = try PublishingCapabilities(versionOutput: "curl 7.85.0 test\nProtocols: http https\nFeatures: SSL\n")
        try rejects("curl older than 7.86") { _ = try PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: oldish) }
        let floor = try PublishingCapabilities(versionOutput: "curl 7.86.0 test\nProtocols: http https\nFeatures: SSL\n")
        _ = try PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: floor)
        let noHTTPS = try PublishingCapabilities(versionOutput: "curl 8.7.1 test\nProtocols: http\nFeatures: SSL\n")
        try rejects("curl without https") { _ = try PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: noHTTPS) }

        // Test button and live-check requests.
        let s3 = try unwrap(plan.s3)
        let check = String(decoding: try s3.checkConfig(credentials: S3Credentials(accessKeyID: "AK", secretAccessKey: "SK", sessionToken: ""), responseFile: response), as: UTF8.self)
        try expect(try s3.checkURL().absoluteString == "https://s3.us-east-1.amazonaws.com/cdn.shoemoney.com?list-type=2&max-keys=0&prefix=pics%2F", "bucket check is a max-keys=0 listing under the prefix")
        try expect(check.contains("request = \"GET\"") && !check.contains("upload-file") && check.contains("aws-sigv4"), "the check is a signed GET, not an upload")
        let delete = String(decoding: try s3.deleteConfig(credentials: S3Credentials(accessKeyID: "AK", secretAccessKey: "SK", sessionToken: "T"), responseFile: response), as: UTF8.self)
        try expect(delete.contains("request = \"DELETE\"") && delete.contains("url = \"\(s3.objectURL.absoluteString)\"") && delete.contains("x-amz-security-token: T"), "signed DELETE of the exact object")
    }

    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw PublishingFailure("SELF-CHECK FAILED: unexpected nil") }
        return value
    }

    static func s3Responses() throws {
        let plan = try unwrap(PublishingPlan(settings: awsCDN(), fileName: "x.png", capabilities: capabilities).s3)
        let url = plan.objectURL.absoluteString
        try plan.verifiedUpload(stdout: "200\n\(url)\n5\n", exitCode: 0, stderr: "", body: "", byteCount: 5, username: "AK", password: "SK")
        let denied = "<Error><Code>AccessDenied</Code><Message>Access Denied</Message><RequestId>ABC</RequestId></Error>"
        do { try plan.verifiedUpload(stdout: "403\n\(url)\n5\n", exitCode: 0, stderr: "", body: denied, byteCount: 5, username: "AK", password: "SK"); throw PublishingFailure("SELF-CHECK FAILED: 403 accepted") }
        catch let error as PublishingFailure { try expect(error.message.contains("403") && error.message.contains("AccessDenied: Access Denied") && !error.message.contains("RequestId"), "status and S3 code/message shown, nothing else") }
        for status in ["201", "204", "301", "500"] {
            try rejects("status \(status)") { try plan.verifiedUpload(stdout: "\(status)\n\(url)\n5\n", exitCode: 0, stderr: "", body: "", byteCount: 5, username: "AK", password: "SK") }
        }
        try rejects("size mismatch") { try plan.verifiedUpload(stdout: "200\n\(url)\n4\n", exitCode: 0, stderr: "", body: "", byteCount: 5, username: "AK", password: "SK") }
        try rejects("other effective URL") { try plan.verifiedUpload(stdout: "200\nhttps://evil.example/x\n5\n", exitCode: 0, stderr: "", body: "", byteCount: 5, username: "AK", password: "SK") }
        do { try plan.verifiedUpload(stdout: "", exitCode: 6, stderr: "could not resolve host SKSECRETVALUE for AKIDVALUE", body: "", byteCount: 5, username: "AKIDVALUE", password: "SKSECRETVALUE"); throw PublishingFailure("SELF-CHECK FAILED: curl failure accepted") }
        catch let error as PublishingFailure { try expect(!error.message.contains("SKSECRETVALUE") && !error.message.contains("AKIDVALUE") && error.message.contains("curl 6"), "curl failures redact the key pair") }

        do { try plan.verifiedUpload(stdout: "", exitCode: 35, stderr: "tls failure while sending FwoGZXIvYXdzTOKEN123", body: "", byteCount: 5, username: "AKIDVALUE", password: "SKSECRETVALUE", sessionToken: "FwoGZXIvYXdzTOKEN123"); throw PublishingFailure("SELF-CHECK FAILED: curl failure accepted") }
        catch let error as PublishingFailure { try expect(!error.message.contains("TOKEN123") && error.message.contains("curl 35"), "curl failures redact the session token") }
        do { try plan.verifiedUpload(stdout: "403\n\(url)\n5\n", exitCode: 0, stderr: "", body: "<Error><Code>X</Code><Message>bad FwoGZXIvYXdzTOKEN123 here</Message></Error>", byteCount: 5, username: "AK", password: "SK", sessionToken: "FwoGZXIvYXdzTOKEN123"); throw PublishingFailure("SELF-CHECK FAILED: 403 accepted") }
        catch let error as PublishingFailure { try expect(!error.message.contains("TOKEN123"), "S3 error bodies redact the session token") }

        try expect(PublishingS3Plan.interpretCheck(code: 200, body: "<ListBucketResult/>").ok, "200 passes the check")
        let limited = PublishingS3Plan.interpretCheck(code: 403, body: denied)
        try expect(limited.ok && limited.message.contains("PutObject"), "AccessDenied still proves the signature, with a caveat")
        let bad = PublishingS3Plan.interpretCheck(code: 403, body: "<Error><Code>SignatureDoesNotMatch</Code><Message>The request signature we calculated does not match.</Message><StringToSign>SECRET</StringToSign></Error>")
        try expect(!bad.ok && bad.message == "SignatureDoesNotMatch: The request signature we calculated does not match.", "bad credentials fail with the S3 code and message only")
        try expect(!PublishingS3Plan.interpretCheck(code: 404, body: "<Error><Code>NoSuchBucket</Code><Message>The specified bucket does not exist</Message></Error>").ok, "missing bucket fails")
        try expect(PublishingS3Plan.interpretCheck(code: 500, body: "oops").message == "The server answered HTTP 500.", "non-XML failures fall back to the status")
    }

    // MARK: AWS shared credentials

    static func credentialsFile() throws {
        let text = """
        # top comment
        ; another comment

        [default]
        aws_access_key_id = AKIADEFAULT
          aws_secret_access_key=  default/secret+key
        region = us-west-2

        [ work ]
        AWS_ACCESS_KEY_ID = AKIAWORK
        aws_secret_access_key = work-secret
        aws_session_token = tok/en==
        # trailing comment

        [nosecret]
        aws_access_key_id = AKIAONLY
        """
        let standard = try AWSSharedCredentials.parse(text, profile: "default")
        try expect(standard == S3Credentials(accessKeyID: "AKIADEFAULT", secretAccessKey: "default/secret+key", sessionToken: ""), "default profile with odd whitespace")
        let work = try AWSSharedCredentials.parse(text, profile: "work")
        try expect(work == S3Credentials(accessKeyID: "AKIAWORK", secretAccessKey: "work-secret", sessionToken: "tok/en=="), "named profile with a session token and uppercase keys")
        do { _ = try AWSSharedCredentials.parse(text, profile: "missing"); throw PublishingFailure("SELF-CHECK FAILED: missing profile accepted") }
        catch let error as PublishingFailure { try expect(error.message.contains("“missing”") && error.message.contains("not found"), "missing profile error names it") }
        do { _ = try AWSSharedCredentials.parse(text, profile: "nosecret"); throw PublishingFailure("SELF-CHECK FAILED: partial profile accepted") }
        catch let error as PublishingFailure { try expect(error.message.contains("aws_secret_access_key") && !error.message.contains("AKIAONLY"), "a profile without a secret is rejected without echoing keys") }
        do { _ = try AWSSharedCredentials.parse("[profile cli]\naws_access_key_id=AKIACLIKEY\naws_secret_access_key=B\n", profile: "cli"); throw PublishingFailure("SELF-CHECK FAILED: [profile x] accepted in the credentials file") }
        catch let error as PublishingFailure { try expect(error.message.contains("[profile cli]") && error.message.contains("config file") && !error.message.contains("AKIACLIKEY"), "[profile name] is rejected in the credentials file with an explanation") }
        try expect(try AWSSharedCredentials.parse("[profile cli]\naws_access_key_id=X\naws_secret_access_key=Y\n[cli]\naws_access_key_id=A\naws_secret_access_key=B\n", profile: "cli").secretAccessKey == "B", "the bare [name] section is used, the [profile name] one ignored")

        let home = URL(fileURLWithPath: "/fake-home")
        try expect(AWSSharedCredentials.defaultFile(environment: [:], home: home).path == "/fake-home/.aws/credentials", "default location under the injected home")
        try expect(AWSSharedCredentials.defaultFile(environment: ["AWS_SHARED_CREDENTIALS_FILE": "/tmp/custom-creds"], home: home).path == "/tmp/custom-creds", "AWS_SHARED_CREDENTIALS_FILE is honoured when passed in")
        try expect(AWSSharedCredentials.defaultFile(environment: ["AWS_SHARED_CREDENTIALS_FILE": ""], home: home).path == "/fake-home/.aws/credentials", "an empty variable is ignored")

        let directory = try temporaryDirectory(), file = directory.appendingPathComponent("credentials")
        try text.write(to: file, atomically: true, encoding: .utf8)
        try expect(try AWSSharedCredentials.load(profile: "work", from: file).accessKeyID == "AKIAWORK", "loads from an injected file")
        try rejects("unreadable credentials file") { _ = try AWSSharedCredentials.load(profile: "default", from: directory.appendingPathComponent("nope")) }

        // resolve(): profile reads the file, Keychain source reads the secret store; neither touches ~/.aws.
        let secrets = PublishingMemorySecrets()
        var viaProfile = awsCDN(); viaProfile.s3?.credentialsProfile = "work"
        try expect(try PublishingS3Credentials.resolve(settings: viaProfile, secrets: secrets, credentialsFile: file).sessionToken == "tok/en==", "profile credentials via the injected path")
        var viaKeychain = awsCDN(); viaKeychain.s3?.credentialsProfile = ""; viaKeychain.username = "AKIAKEYCHAIN"
        try secrets.add("keychain-secret", id: viaKeychain.credentialID)
        let resolved = try PublishingS3Credentials.resolve(settings: viaKeychain, secrets: secrets, credentialsFile: directory.appendingPathComponent("never-read"))
        try expect(resolved == S3Credentials(accessKeyID: "AKIAKEYCHAIN", secretAccessKey: "keychain-secret", sessionToken: ""), "access key plus Keychain secret")
    }

    // MARK: Storage

    /// F-J4 note 7: the in-memory store never touches the Keychain, so its failure must not claim it did.
    static func memorySecretsMessage() throws {
        let secrets = PublishingMemorySecrets()
        do { _ = try secrets.read("missing", allowMissing: false); throw PublishingFailure("SELF-CHECK FAILED: a missing secret was returned") }
        catch let failure as PublishingFailure {
            try expect(failure.localizedDescription == "No password is stored for this destination in this session.", "The in-memory store says what is true: \(failure.localizedDescription)")
            try expect(!failure.localizedDescription.contains("Keychain") && !failure.localizedDescription.contains("-25300"), "It does not blame the Keychain")
        }
        try expect(try secrets.read("missing", allowMissing: true) == "", "A missing secret that is allowed still reads empty")
    }

    static func legacyJSON(_ settings: PublishingSettings) throws -> Data { try JSONEncoder().encode(settings) }

    static func migration() throws {
        // The owner's SFTP destination.
        let directory = try temporaryDirectory(), secrets = PublishingMemorySecrets()
        var sftp = PublishingSettings(); sftp.transport = .sftp; sftp.sshAlias = "shoemoney.com"
        sftp.sftpRemoteRoot = "/var/www/shoemoney.com/shared/imgs"; sftp.publicBaseURL = "https://shoemoney.com/imgs/"
        sftp.credentialID = "00000000-0000-0000-0000-0000000000AA"
        let original = try legacyJSON(sftp)
        try original.write(to: directory.appendingPathComponent("destination.json"))
        let store = PublishingDestinationStore(directory: directory, secrets: secrets)
        let list = try store.load()
        try expect(list.destinations.count == 1 && list.defaultDestination?.id == list.destinations[0].id && list.defaultID == list.destinations[0].id, "the old destination becomes the only entry and the default")
        try expect(list.destinations[0].settings == sftp && list.destinations[0].settings.credentialID == sftp.credentialID, "SFTP settings and credentialID survive unchanged")
        try expect(list.destinations[0].name == "SFTP · shoemoney.com", "migrated name is readable")
        try expect(try Data(contentsOf: store.backupFile) == original, "the old file is kept byte for byte as a backup")
        try expect(try Data(contentsOf: store.legacyFile) == original && FileManager.default.fileExists(atPath: store.file.path), "the legacy file is copied, never moved: its bytes are unchanged once the list is written")
        try expect(try store.load() == list, "a second load is stable")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try expect(!String(decoding: try encoder.encode(list.destinations[0].settings), as: UTF8.self).contains("s3"), "non-S3 settings encode exactly as before, so history fingerprints still match")

        // A password destination keeps its Keychain item (same credentialID, same secret).
        let directory2 = try temporaryDirectory(), secrets2 = PublishingMemorySecrets()
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.com/up"; dav.username = "me"
        dav.credentialID = "00000000-0000-0000-0000-0000000000BB"
        try secrets2.add("dav-password", id: dav.credentialID)
        let davBytes = try legacyJSON(dav)
        try davBytes.write(to: directory2.appendingPathComponent("destination.json"))
        let migrated = try PublishingDestinationStore(directory: directory2, secrets: secrets2).load()
        try expect(secrets2.items == [dav.credentialID: "dav-password"] && migrated.destinations[0].settings.credentialID == dav.credentialID, "the Keychain item is neither moved nor deleted")

        // Downgrade safety: the legacy file still points at this Keychain item, so edit and remove keep it.
        let migratedStore = PublishingDestinationStore(directory: directory2, secrets: secrets2)
        var edited = migrated.destinations[0]; edited.name = "Renamed DAV"
        try migratedStore.save(edited, password: "new-password")
        try expect(secrets2.items[dav.credentialID] == "dav-password" && secrets2.items.count == 2, "editing a migrated destination never deletes the item the legacy file references")
        try migratedStore.remove(edited.id)
        try expect(secrets2.items[dav.credentialID] == "dav-password" && secrets2.items.count == 1, "removing it deletes only the new item")
        try expect(try Data(contentsOf: directory2.appendingPathComponent("destination.json")) == davBytes, "the legacy file is still untouched")
        // Removing a freshly migrated, never-edited destination must keep the item the legacy file uses.
        let directoryLegacy = try temporaryDirectory(), secrets4 = PublishingMemorySecrets()
        try secrets4.add("dav-password", id: dav.credentialID)
        try davBytes.write(to: directoryLegacy.appendingPathComponent("destination.json"))
        let fresh = PublishingDestinationStore(directory: directoryLegacy, secrets: secrets4)
        let unedited = try fresh.load().destinations[0]
        try fresh.remove(unedited.id)
        try expect(secrets4.items[dav.credentialID] == "dav-password", "removing an unedited migrated destination keeps the legacy Keychain item")
        try expect(try Data(contentsOf: directoryLegacy.appendingPathComponent("destination.json")) == davBytes, "and leaves the legacy file byte-identical")

        // Isolation: OPENSNAP_APP_SUPPORT puts the store inside that folder with in-memory secrets.
        let support = try temporaryDirectory()
        let isolated = PublishingDestinationStore.forEnvironment(["OPENSNAP_APP_SUPPORT": support.path])
        try expect(isolated.directory.standardizedFileURL.path == support.appendingPathComponent("Publishing").standardizedFileURL.path && isolated.secrets is PublishingMemorySecrets,
                   "an isolated support folder holds the store and its secrets stay in memory")
        let production = PublishingDestinationStore.forEnvironment([:])
        try expect(production.directory.path.hasSuffix("/Application Support/OpenSnap/Publishing") && production.secrets is PublishingKeychain, "no environment means the real folder and Keychain")

        // An unreadable old file blocks migration and is left alone.
        let directory3 = try temporaryDirectory()
        let junk = Data("{ not json".utf8)
        try junk.write(to: directory3.appendingPathComponent("destination.json"))
        let broken = PublishingDestinationStore(directory: directory3, secrets: PublishingMemorySecrets())
        try rejects("a corrupt legacy file") { _ = try broken.load() }
        try expect(try Data(contentsOf: broken.legacyFile) == junk && !FileManager.default.fileExists(atPath: broken.file.path), "the corrupt file is preserved and nothing is written")

        // An existing backup is never overwritten.
        let directory4 = try temporaryDirectory()
        try Data("older backup".utf8).write(to: directory4.appendingPathComponent("destination.json.pre-destinations.bak"))
        try original.write(to: directory4.appendingPathComponent("destination.json"))
        _ = try PublishingDestinationStore(directory: directory4, secrets: PublishingMemorySecrets()).load()
        try expect(try Data(contentsOf: directory4.appendingPathComponent("destination.json.pre-destinations.bak")) == Data("older backup".utf8)
                   && (try FileManager.default.contentsOfDirectory(atPath: directory4.path)).filter { $0.hasSuffix(".bak") }.count == 2, "a second backup gets its own name")

        // Removal prompt wording (the list builds it; the alert in Settings only displays it).
        var keyed = PublishingDestination(name: "Work DAV", settings: dav)
        let other = PublishingDestination(name: "Backup", settings: awsCDN())
        keyed.settings.credentialID = "00000000-0000-0000-0000-0000000000CC"
        let two = PublishingDestinationList(defaultID: keyed.id, destinations: [keyed, other])
        let promptDefault = two.removalPrompt(for: keyed)
        try expect(promptDefault.title == "Remove “Work DAV”?" && promptDefault.detail.contains("Keychain") && promptDefault.detail.contains("“Backup” becomes the default"), "removing the default names the new default and the secret")
        let promptOther = two.removalPrompt(for: other)
        try expect(!promptOther.detail.contains("becomes the default") && !promptOther.detail.contains("Keychain"), "a non-default, secret-free destination gets no default or Keychain wording")
        let promptLast = PublishingDestinationList(defaultID: keyed.id, destinations: [keyed]).removalPrompt(for: keyed)
        try expect(promptLast.detail.contains("only destination"), "removing the last destination says so")
        let promptLegacy = two.removalPrompt(for: keyed, legacyCredentialID: keyed.settings.credentialID)
        try expect(!promptLegacy.detail.contains("Keychain"), "a secret the legacy file still uses is not claimed to be removed")

        let empty = try PublishingDestinationStore(directory: try temporaryDirectory(), secrets: PublishingMemorySecrets()).load()
        try expect(empty.destinations.isEmpty && empty.defaultDestination == nil, "a fresh install has no destinations")
    }

    static func storeOperations() throws {
        let directory = try temporaryDirectory(), secrets = PublishingMemorySecrets()
        let store = PublishingDestinationStore(directory: directory, secrets: secrets)
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.com"; dav.username = "me"
        let first = PublishingDestination(name: "Work DAV", settings: dav)
        try store.save(first, password: "pw1")
        try expect(try store.load().defaultID == first.id, "the first destination becomes the default")
        try expect(secrets.items.count == 1 && secrets.items.values.first == "pw1", "its password went to the secret store")
        let storedID = try unwrap(store.load().destinations.first?.settings.credentialID)
        var s3 = awsCDN(); s3.s3?.credentialsProfile = ""; s3.username = "AKIAEXAMPLE"
        let second = PublishingDestination(name: "AWS cdn", settings: s3)
        try store.save(second, password: "s3-secret")
        try expect(try store.load().destinations.map(\.name) == ["Work DAV", "AWS cdn"] && (try store.load().defaultID) == first.id, "adding keeps the default")
        try expect(secrets.items.count == 2, "a Keychain-source S3 destination stores its secret")
        try rejects("a duplicate name") { try store.save(PublishingDestination(name: "aws CDN", settings: dav), password: "") }
        try rejects("an empty name") { try store.save(PublishingDestination(name: "  ", settings: dav), password: "") }

        try store.setDefault(second.id)
        let reopened = PublishingDestinationStore(directory: directory, secrets: secrets)
        try expect(try reopened.defaultDestination()?.name == "AWS cdn", "the default survives a fresh store on the same folder")
        try rejects("an unknown default") { try store.setDefault("nope") }

        var edited = first; edited.settings.endpoint = "https://dav2.example.com"
        try store.save(edited, password: "pw2")
        try expect(secrets.items[storedID] == nil && secrets.items.count == 2 && secrets.items.values.contains("pw2"), "editing rotates the secret and drops the old item")
        try expect(try store.load().destinations.count == 2 && (try store.load().destinations[0].settings.endpoint) == "https://dav2.example.com", "editing replaces in place")

        // R1-010: a save that leaves the secret alone keeps the Keychain item (so older History posts still find their destination);
        // a new secret or a new protocol makes a new item and drops the old one.
        let rotatedID = try unwrap(store.load().destinations.first { $0.id == first.id }?.settings.credentialID)
        try expect(rotatedID != storedID, "the changed password got its own Keychain item")
        var renamed = edited; renamed.name = "Work DAV (renamed)"; renamed.settings.remoteFolder = "other-folder"
        try store.save(renamed, password: "pw2")
        let afterRename = try unwrap(store.load().destinations.first { $0.id == first.id })
        try expect(afterRename.settings.credentialID == rotatedID && afterRename.name == "Work DAV (renamed)" && secrets.items.count == 2 && secrets.items[rotatedID] == "pw2",
                   "renaming and moving the folder with the same password keeps the credential id and the Keychain item")
        var otherProtocol = renamed; otherProtocol.settings.transport = .ftp; otherProtocol.settings.endpoint = "ftp://ftp.example.com/up"
        try store.save(otherProtocol, password: "pw2")
        let afterProtocol = try unwrap(store.load().destinations.first { $0.id == first.id })
        try expect(afterProtocol.settings.credentialID != rotatedID && secrets.items[rotatedID] == nil && secrets.items.count == 2 && secrets.items[afterProtocol.settings.credentialID] == "pw2",
                   "a different protocol is a new credential: new item, old one dropped")
        edited = otherProtocol

        var profile = awsCDN(); profile.s3?.credentialsProfile = "default"
        let third = PublishingDestination(name: "Profile", settings: profile)
        try store.save(third, password: "")
        try expect(secrets.items.count == 2, "an AWS-profile destination stores no secret")

        try store.remove(second.id)
        try expect(try store.load().destinations.map(\.name) == ["Work DAV (renamed)", "Profile"] && (try store.load().defaultID) == (try store.load().destinations[0].id), "removing the default promotes the first remaining")
        try expect(secrets.items.count == 1, "removing deletes its secret")
        try store.remove(first.id); try store.remove(third.id)
        try expect(try store.load().destinations.isEmpty && secrets.items.isEmpty && (try store.load().defaultID) == nil, "removing everything leaves an empty list")
        try expect(!(try Data(contentsOf: store.file).isEmpty) && !String(decoding: try Data(contentsOf: store.file), as: UTF8.self).contains("s3-secret"), "the file never holds a secret")
    }

    // MARK: Live check

    // MARK: Audit batch 3b: per-protocol copy, accessible names, reserved result band, sheet width, Test for every protocol

    /// F-J2-015, 016, 017: each protocol's form speaks for itself, S3 keys are not "optional", and every field keeps its name once filled.
    @MainActor static func formCopyAndLabels() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let publisher = try coordinator(destinations: fixtureDestinations())
        let (panel, view) = publisher.buildEditor(editing: nil, visibleFrame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        defer { panel.orderOut(nil) }
        typealias View = PublishingDestinationsView
        let copies = Dictionary(uniqueKeysWithValues: PublishingProtocol.allCases.map { ($0, View.formCopy(for: $0)) })
        try expect(copies[.webDAV]?.endpointPlaceholder.hasPrefix("http") == true && copies[.ftp]?.endpointPlaceholder.hasPrefix("ftp://") == true
                   && copies[.ftps]?.endpointPlaceholder.hasPrefix("ftps://") == true && copies[.sftp]?.endpointPlaceholder.hasPrefix("sftp://") == true,
                   "the endpoint placeholder names each protocol's own scheme")
        try expect(Set(copies.values.map(\.endpointPlaceholder)).count == 5 && Set(copies.values.map(\.help)).count == 5, "no two protocols share an endpoint placeholder or a help paragraph")
        try expect(!(copies[.webDAV]?.help.contains("FTPS") ?? true) && copies[.ftps]?.help.contains("explicit TLS") == true && copies[.ftp]?.help.contains("unencrypted") == true,
                   "the WebDAV form no longer carries the FTPS help")
        for (transport, copy) in copies {
            try expect(copy.testNote.hasSuffix("never uploads.") && !copy.help.isEmpty, "\(transport) says what Test does and never uploads")
        }
        try expect(copies[.s3]?.usernameCaption == "Access key ID" && copies[.s3]?.usernamePlaceholder.lowercased().contains("optional") == false
                   && copies[.s3]?.usernamePlaceholder.hasPrefix("AKIA") == true, "S3 keys are not offered as optional: \(copies[.s3]?.usernamePlaceholder ?? "")")
        try expect(copies[.s3]?.passwordPlaceholder == "Saved in the macOS Keychain" && copies[.s3]?.passwordCaption == "Secret access key", "the S3 secret placeholder fits a secret key")
        try expect(copies[.webDAV]?.usernamePlaceholder.contains("anonymous") == true, "WebDAV may be anonymous, and its placeholder says so")

        // SFTP: one place for the host. The Endpoint row is gone for a new destination and present only to show an older saved URL.
        view.showForm(for: nil)
        view.protocolPopup.selectItem(withTitle: PublishingProtocol.sftp.title); view.formChanged(); panel.contentView?.layoutSubtreeIfNeeded()
        try expect(view.endpointField.isHiddenOrHasHiddenAncestor && !view.aliasField.isHiddenOrHasHiddenAncestor, "a new SFTP destination asks for the SSH host, not an endpoint as well")
        view.endpointField.stringValue = "https://stale.example.com"; view.nameField.stringValue = "S"; view.aliasField.stringValue = "myserver"; view.remoteRootField.stringValue = "/srv/up"
        try expect(try view.makeDraft().destination.settings.endpoint.isEmpty, "a stale hidden endpoint never reaches an SFTP destination")
        view.cancelFormTapped()
        var legacy = PublishingSettings(); legacy.transport = .sftp; legacy.endpoint = "sftp://old.example.com/uploads"
        publisher.store = PublishingDestinationStore(directory: try temporaryDirectory(), secrets: PublishingMemorySecrets())
        try publisher.store.save(PublishingDestination(name: "Old SFTP", settings: legacy), password: "")
        view.showForm(for: try publisher.store.load().destinations[0])
        try expect(!view.endpointField.isHiddenOrHasHiddenAncestor && view.endpointField.stringValue == "sftp://old.example.com/uploads", "an SFTP destination saved with an sftp:// endpoint still shows it")
        view.cancelFormTapped()

        // R2-017: Test with an empty required address says which field, outlines it and focuses it, and never starts a test.
        view.showForm(for: nil)
        view.protocolPopup.selectItem(withTitle: PublishingProtocol.webDAV.title); view.formChanged(); panel.contentView?.layoutSubtreeIfNeeded()
        var started = 0
        view.onTest = { _, _ in started += 1 }
        view.nameField.stringValue = "Web"; view.endpointField.stringValue = "  "
        view.testTapped()
        try expect(started == 0 && view.formResult.text.stringValue.contains("Endpoint URL is empty"), "an empty endpoint is named, not tested (\(view.formResult.text.stringValue))")
        try expect(view.endpointField.layer?.borderWidth == 2 && (panel.firstResponder as? NSTextView)?.delegate === view.endpointField, "…the field is outlined and holds the keyboard")
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: view.endpointField)
        try expect(view.endpointField.layer?.borderWidth == 0, "…and the outline goes when the field is edited")
        view.endpointField.stringValue = "https://dav.example.com/files"; view.testTapped()
        try expect(started == 1, "a filled endpoint is tested")
        view.protocolPopup.selectItem(withTitle: PublishingProtocol.sftp.title); view.formChanged(); view.aliasField.stringValue = ""; view.testTapped()
        try expect(started == 1 && view.formResult.text.stringValue.contains("SSH host is empty"), "an SFTP destination without a host is named too (\(view.formResult.text.stringValue))")
        view.onTest = nil
        view.cancelFormTapped()

        // Every protocol and credential source: the form shows its own copy, and every filled field still has its caption as its name.
        view.showForm(for: nil)
        for transport in PublishingProtocol.allCases {
            for source in 0...1 {
                view.protocolPopup.selectItem(withTitle: transport.title); view.sourcePopup.selectItem(at: source); view.formChanged()
                panel.contentView?.layoutSubtreeIfNeeded()
                let copy = View.formCopy(for: transport)
                try expect(view.folderField.placeholderString == copy.folderPlaceholder && view.usernameField.placeholderString == copy.usernamePlaceholder
                           && view.passwordField.placeholderString == copy.passwordPlaceholder, "\(transport) form shows its own placeholders")
                try expect(!view.testButton.isHidden && !view.testButton.isHiddenOrHasHiddenAncestor, "\(transport) has a Test button")
                try expect(view.formResult.kind == .hint && view.formResult.text.stringValue == copy.testNote, "\(transport) says what Test does before it is pressed: \(view.formResult.text.stringValue)")
                // Fill every visible text field, as a person would, then ask for its name.
                let fields = descendants(view).compactMap { $0 as? NSTextField }.filter { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor }
                try expect(fields.count >= 4, "\(transport)/\(source): only \(fields.count) editable fields")
                for field in fields { field.stringValue = "filled in" }
                let captions = Set(view.visibleFormCaptions.map(\.stringValue))
                for field in fields {
                    let name = field.accessibilityLabel() ?? ""
                    try expect(captions.contains(name), "\(transport)/\(source): a filled field is named “\(name)”, not one of \(captions.sorted())")
                }
                for popup in [view.protocolPopup, view.sourcePopup] where !popup.isHiddenOrHasHiddenAncestor {
                    try expect(captions.contains(popup.accessibilityLabel() ?? ""), "\(transport)/\(source): a pop-up has no caption as its name")
                }
                for field in fields { field.stringValue = "" }
            }
        }
        view.cancelFormTapped()

        // The expected scheme is in the error, for the endpoint and for the public base URL.
        func message(_ text: String, _ schemes: Set<String>) -> String {
            do { _ = try PublishingPlan.baseURL(text, schemes: schemes); return "" } catch { return error.localizedDescription }
        }
        try expect(message("ftp.example.com", PublishingProtocol.ftps.schemes).contains("ftp:// or ftps://"), "an FTPS endpoint error names ftp:// or ftps://")
        try expect(message("http://x.example.com", PublishingProtocol.ftp.schemes).contains("ftp://") && !message("http://x.example.com", PublishingProtocol.ftp.schemes).contains("http://"), "an FTP endpoint error names ftp://")
        try expect(message("sftp://x", PublishingProtocol.webDAV.schemes).contains("http:// or https://"), "a WebDAV endpoint error names http:// or https://")
        try expect(!message("ftp://x.example.com", ["http", "https"]).contains("matching scheme"), "the vague wording is gone")
    }

    /// F-J2-013 and 018: the sheet never overhangs its parent, and a result has a band of its own that nothing grows into.
    @MainActor static func resultBandAndSheetWidth() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        typealias View = PublishingDestinationsView
        try expect(View.sheetWidth(forHostWidth: 640) == 640 && View.sheetWidth(forHostWidth: 1200) == 720 && View.sheetWidth(forHostWidth: 300) == View.sheetMinWidth,
                   "the sheet is as wide as its parent, between \(View.sheetMinWidth) and 720")
        let publisher = try coordinator(destinations: fixtureDestinations())
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let (narrow, narrowView) = publisher.buildEditor(editing: nil, visibleFrame: screen, hostWidth: 640)
        defer { narrow.orderOut(nil) }
        narrow.contentView?.layoutSubtreeIfNeeded()
        try expect(narrow.contentRect(forFrameRect: narrow.frame).width == 640 && narrowView.width == 640, "under the 640 pt Settings window the sheet is 640 wide, not 720")
        narrowView.showForm(for: nil); narrow.contentView?.layoutSubtreeIfNeeded()
        for transport in PublishingProtocol.allCases {
            narrowView.protocolPopup.selectItem(withTitle: transport.title); narrowView.formChanged(); narrow.contentView?.layoutSubtreeIfNeeded()
            for caption in narrowView.visibleFormCaptions {
                let natural = try unwrap(caption.cell).cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 1_000))
                try expect(natural.width <= caption.frame.width + 0.5 && caption.frame.height <= natural.height + 0.5, "“\(caption.stringValue)” does not fit its column in the 640 pt sheet (\(transport.title))")
            }
            let document = try unwrap(narrowView.scrollView.documentView)
            try expect(document.frame.width <= narrowView.scrollView.contentView.bounds.width + 0.5, "the \(transport.title) form is wider than the 640 pt sheet")
        }
        narrowView.cancelFormTapped()

        // The result band is as tall as its text: one line at idle, up to three for an error. The form above shrinks and scrolls by the
        // difference, the band never runs over the buttons or the form, and the idle form keeps the room an empty band would waste.
        let (panel, view) = publisher.buildEditor(editing: nil, visibleFrame: screen, hostWidth: 900)
        defer { panel.orderOut(nil) }
        view.showForm(for: nil); view.protocolPopup.selectItem(withTitle: PublishingProtocol.s3.title); view.formChanged()
        panel.contentView?.layoutSubtreeIfNeeded()
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: DesignTokens.Typography.font(.body)))
        func box(_ row: NSView) -> NSRect { row.convert(row.bounds, to: view) }
        func buttonsTop() -> CGFloat { min(box(view.testButton).maxY, box(view.saveButton).maxY) }
        let scrollHeight = view.scrollView.frame.height, idle = box(view.formResult)
        try expect(view.formResult.kind == .hint && idle.height < 1.6 * lineHeight, "at idle the band is one line (\(idle.height) pt), not three")
        try expect(idle.minY >= buttonsTop() - 0.5 && abs(box(view.scrollView).minY - (idle.maxY + DesignTokens.Space.s3)) < 12, "the idle hint sits between the form and the buttons: \(idle) vs scroll \(box(view.scrollView))")
        let longError = "The bucket could not be reached (curl 7).\ncurl: (7) Failed to connect to a-rather-long-host-name.example.test port 443 after 54 ms: Couldn't connect to server and then went on to say a good deal more than one sheet can show"
        view.showTestResult(ok: false, message: longError)
        panel.contentView?.layoutSubtreeIfNeeded()
        let errorFrame = box(view.formResult)
        try expect(errorFrame.height > idle.height + lineHeight && errorFrame.height <= 3 * lineHeight + 2 * 2 + 4, "the error band grows to its lines, three at most: \(errorFrame.height) pt")
        try expect(view.scrollView.frame.height < scrollHeight - lineHeight, "the form above shrinks to make room (\(scrollHeight) to \(view.scrollView.frame.height))")
        try expect(errorFrame.minY >= buttonsTop() - 0.5 && errorFrame.maxY <= box(view.scrollView).minY + 0.5 + DesignTokens.Space.s3 + 1,
                   "the error sits between the form and the buttons and covers neither: \(errorFrame) buttons top \(buttonsTop()) form bottom \(box(view.scrollView).minY)")
        try expect(view.formResult.text.stringValue.hasPrefix("Error: ") && view.formResult.accessibilityLabel()?.contains("went on") == true, "the whole message stays available to VoiceOver")
        try expect(view.formResult.text.maximumNumberOfLines == 3, "a Test error is capped at three lines")
        view.showTestResult(ok: true, message: "Reached the server (HTTP 200) and the folder was not refused. Nothing was uploaded.")
        panel.contentView?.layoutSubtreeIfNeeded()
        let successFrame = box(view.formResult)
        try expect(successFrame.minY >= buttonsTop() - 0.5 && successFrame.height < errorFrame.height, "a success is shorter than the error and still clear of the buttons: \(successFrame)")
        // F-J7-001: every WebDAV Test note that can come back, with a login and without, is shown whole at the narrowest and the widest
        // sheet: the field's wrapped height at its laid-out width equals its frame, so nothing is cut with an ellipsis.
        func webDAV(_ code: String, user: String) -> String { PublishingConnectionTest.webDAVOutcome(stdout: code, exitCode: 0, stderr: "", username: user, password: user.isEmpty ? "" : "pw").message }
        let notes = [webDAV("207", user: "me"), webDAV("200", user: ""), webDAV("405", user: "me"), webDAV("501", user: "")]
        try expect(notes[0].hasSuffix("Nothing was uploaded.") && notes[0].contains("(HTTP 207)"), "the login note ends with its closing sentence: \(notes[0])")
        for (hostWidth, label) in [(CGFloat(640), "640"), (CGFloat(900), "900")] {
            let (widthPanel, widthView) = publisher.buildEditor(editing: nil, visibleFrame: screen, hostWidth: hostWidth)
            defer { widthPanel.orderOut(nil) }
            widthView.showForm(for: nil); widthView.protocolPopup.selectItem(withTitle: PublishingProtocol.webDAV.title); widthView.formChanged()
            for note in notes {
                widthView.showTestResult(ok: true, message: note)
                widthPanel.contentView?.layoutSubtreeIfNeeded()
                let field = widthView.formResult.detail
                // Measured without the field's own line cap, so a note that needs a fourth line cannot hide behind it.
                let natural = (note as NSString).boundingRect(with: NSSize(width: field.frame.width, height: 10_000), options: .usesLineFragmentOrigin, attributes: [.font: try unwrap(field.font)])
                let captionLine = ceil(NSLayoutManager().defaultLineHeight(for: DesignTokens.Typography.font(.caption)))
                try expect(natural.height <= 3 * captionLine + 1, "the note needs more than three lines at \(label) pt: \(natural.height) pt for “\(note)”")
                try expect(field.frame.height >= natural.height - 0.5 && field.stringValue == note && field.maximumNumberOfLines >= 3,
                           "the whole note is visible at \(label) pt (frame \(field.frame.height) pt, needs \(natural.height) pt): “\(note)”")
            }
        }
        // A result for a form is gone with the form: the band returns to its one idle line and the form its room.
        view.showForm(for: nil); view.protocolPopup.selectItem(withTitle: PublishingProtocol.s3.title); view.formChanged()
        panel.contentView?.layoutSubtreeIfNeeded()
        try expect(abs(view.scrollView.frame.height - scrollHeight) < 0.5 && box(view.formResult).height < 1.6 * lineHeight, "a fresh form is back to the idle band (\(view.scrollView.frame.height) vs \(scrollHeight))")
    }

    // MARK: Test for every protocol, against local stubs only

    /// A loopback HTTP server on 127.0.0.1 that answers by a rule and records what it was asked.
    final class LoopbackHTTP: @unchecked Sendable {
        let port: UInt16
        private let listener: Int32
        private let lock = NSLock()
        private var seen: [(line: String, auth: String?, length: Int)] = []
        var requests: [(line: String, auth: String?, length: Int)] { lock.lock(); defer { lock.unlock() }; return seen }
        init(respond: @escaping @Sendable (String, String?) -> Int) throws {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = 0
            let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            guard bound == 0, listen(fd, 8) == 0 else { throw PublishingFailure("loopback server could not start") }
            var assigned = sockaddr_in(); var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &assigned) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) } }
            var timeout = timeval(tv_sec: 15, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            listener = fd; port = UInt16(bigEndian: assigned.sin_port)
            Thread.detachNewThread { [self] in
                while true {
                    let client = accept(fd, nil, nil)
                    if client < 0 { return }
                    var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                    while !data.contains(Data("\r\n\r\n".utf8)) {
                        let count = read(client, &buffer, buffer.count)
                        if count <= 0 { break }
                        data.append(contentsOf: buffer[0..<count])
                    }
                    let head = String(decoding: data, as: UTF8.self), lines = head.components(separatedBy: "\r\n")
                    let auth = lines.first { $0.lowercased().hasPrefix("authorization:") }
                    let length = lines.first { $0.lowercased().hasPrefix("content-length:") }.flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                    lock.lock(); seen.append((lines.first ?? "", auth, length)); lock.unlock()
                    let code = respond(lines.first ?? "", auth)
                    let reply = "HTTP/1.1 \(code) Stub\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    _ = reply.withCString { write(client, $0, strlen($0)) }
                    close(client)
                }
            }
        }
        func stop() { close(listener) }
    }

    static func connectionTests() throws {
        typealias Test = PublishingConnectionTest
        func settings(_ transport: PublishingProtocol, endpoint: String, folder: String = "shots") -> PublishingSettings {
            var value = PublishingSettings(); value.transport = transport; value.endpoint = endpoint; value.remoteFolder = folder; return value
        }
        func plan(_ value: PublishingSettings) throws -> PublishingPlan { try PublishingPlan(settings: value, fileName: "check.png", capabilities: capabilities, sftpAvailable: true) }
        func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

        // The requests are questions: no upload-file, no PUT, no body, a folder URL.
        let dav = try plan(settings(.webDAV, endpoint: "https://dav.example.com/files"))
        let davConfig = text(try Test.curlConfig(plan: dav, username: "me", password: "pw"))
        try expect(davConfig.contains("request = \"PROPFIND\"") && davConfig.contains("header = \"Depth: 0\"") && !davConfig.contains("OPTIONS") && davConfig.contains("url = \"https://dav.example.com/files/shots/\"") && !davConfig.contains("upload-file") && !davConfig.contains("PUT"),
                   "the WebDAV test is a PROPFIND (Depth 0) on the folder, which a server with a login answers only to the login: \(davConfig)")
        let ftp = try plan(settings(.ftp, endpoint: "ftp://ftp.example.com/up"))
        let ftpConfig = text(try Test.curlConfig(plan: ftp, username: "me", password: "pw"))
        try expect(ftpConfig.contains("list-only") && ftpConfig.contains("url = \"ftp://ftp.example.com/up/shots/\"") && !ftpConfig.contains("upload-file") && !ftpConfig.contains("ssl-reqd"), "the FTP test lists the folder: \(ftpConfig)")
        let ftps = try plan(settings(.ftps, endpoint: "ftp://ftp.example.com/up"))
        try expect(text(try Test.curlConfig(plan: ftps, username: "", password: "")).contains("ssl-reqd") && !text(try Test.curlConfig(plan: ftps, username: "", password: "")).contains("user ="), "the FTPS test requires TLS, and an anonymous test sends no login")
        try rejects("a password without a username") { _ = try Test.curlConfig(plan: dav, username: "", password: "pw") }
        try rejects("the curl config for SFTP") { _ = try Test.curlConfig(plan: try plan(settings(.sftp, endpoint: "")), username: "", password: "") }
        var sftpSettings = settings(.sftp, endpoint: ""); sftpSettings.sshAlias = "myserver"; sftpSettings.sftpRemoteRoot = "/var/www/up"
        let sftp = try unwrap(plan(sftpSettings).keyedSFTP)
        let batch = text(try sftp.listBatch())
        try expect(batch == "@ls \"/var/www/up/shots\"\n@bye\n" && !batch.contains("put") && !batch.contains("mkdir") && !batch.contains("rm") && !batch.contains("chmod"), "the SFTP test only lists: \(batch)")

        // What the answers mean.
        func web(_ code: String, exit: Int32 = 0, stderr: String = "") -> PublishingS3Plan.CheckResult { Test.webDAVOutcome(stdout: code + "\n", exitCode: exit, stderr: stderr, username: "me", password: "hunter2") }
        try expect(web("200").ok && web("207").ok && web("405").ok && web("501").ok, "an answer that does not refuse the login or the folder is a connection")
        try expect(web("200").message.contains("did not reject the login") && !web("200").message.contains("accepted") && web("200").message.contains("does not prove") && web("405").message.contains("login could not be checked"), "a 2xx says only that the login was not rejected (R2-018); a PUT-only endpoint says it could not check it")
        try expect(!web("301").ok && !web("302").ok && !web("308").ok && web("301").message.contains("redirected") && web("301").message.contains("does not follow redirects"), "a redirect is a failure with its reason, not a pass")
        try expect(Test.webDAVOutcome(stdout: "401", exitCode: 0, stderr: "", username: "", password: "").message.contains("asks for a user name and password"), "an anonymous test that meets a login says to enter one")
        try expect(!web("401").ok && web("401").message.contains("user name or password"), "401 is a login problem")
        try expect(!web("403").ok && !web("404").ok && web("404").message.contains("Create it first") && !web("500").ok, "403, 404 and 500 are failures with a reason")
        try expect(!Test.webDAVOutcome(stdout: "", exitCode: 0, stderr: "", username: "", password: "").ok, "no status line is not a success")
        let refused = web("000", exit: 7, stderr: "curl: (7) Failed to connect to dav.example.com port 443 as me:hunter2")
        try expect(!refused.ok && refused.message.hasPrefix("Could not connect to the server (curl 7).") && !refused.message.contains("hunter2"), "a refused connection is named and the secret is redacted: \(refused.message)")
        try expect(Test.ftpOutcome(exitCode: 67, stderr: "", username: "", password: "").message.contains("user name or password") && Test.ftpOutcome(exitCode: 9, stderr: "", username: "", password: "").message.contains("folder does not exist")
                   && Test.ftpOutcome(exitCode: 0, stderr: "", username: "", password: "").ok && Test.ftpOutcome(exitCode: 60, stderr: "", username: "", password: "").message.hasPrefix("The secure connection"), "FTP exit codes read as causes")
        try expect(Test.sftpOutcome(exitCode: 0, stderr: "", username: "").ok && Test.sftpOutcome(exitCode: 255, stderr: "Host key verification failed.", username: "").message.contains("Host key verification failed."), "SFTP answers")

        // Stubbed tool runs: the right tool, the right arguments, the batch on stdin; no network.
        let original = Test.processRunner
        defer { Test.processRunner = original }
        nonisolated(unsafe) var ran: [(String, [String], String, Bool)] = []
        nonisolated(unsafe) var answer = PublishingProcess.Output(stdout: "", stderr: "", code: 0)
        Test.processRunner = { executable, arguments, input, agent, _ in ran.append((executable, arguments, String(decoding: input, as: UTF8.self), agent)); return answer }
        let sftpResult = try Test.run(plan: plan(sftpSettings), username: "", password: "", cancellation: PublishingCancellation())
        try expect(sftpResult.ok && ran.last?.0 == "/usr/bin/sftp" && ran.last?.2 == batch && ran.last?.3 == true && ran.last?.1.contains("BatchMode=yes") == true, "SFTP Test runs /usr/bin/sftp with the list batch and the agent")
        answer = PublishingProcess.Output(stdout: "", stderr: "curl: (67) Access denied: 530", code: 67)
        let ftpResult = try Test.run(plan: ftp, username: "me", password: "pw", cancellation: PublishingCancellation())
        try expect(!ftpResult.ok && ran.last?.0 == "/usr/bin/curl" && ran.last?.1 == ["--disable", "--config", "-"] && ran.last?.2.contains("list-only") == true && ran.last?.3 == false
                   && ftpResult.message.contains("user name or password"), "FTP Test runs curl on stdin config and reports the refused login")
        Test.processRunner = original

        // The real curl against a loopback server: PROPFIND, with and without the right login, against a server that answers OPTIONS to anyone.
        // Nothing leaves the machine.
        let server = try LoopbackHTTP { line, auth in
            if line.hasPrefix("OPTIONS ") { return 200 }
            guard line.hasPrefix("PROPFIND ") else { return 400 }
            if line.contains("/missing/") { return 404 }
            if line.contains("/moved/") { return 301 }
            return auth?.contains(Data("me:pw".utf8).base64EncodedString()) == true ? 200 : 401
        }
        defer { server.stop() }
        let base = "http://127.0.0.1:\(server.port)/dav"
        func live(_ folder: String, user: String, password: String) throws -> PublishingS3Plan.CheckResult {
            let live = try plan(settings(.webDAV, endpoint: base, folder: folder))
            nonisolated(unsafe) var outcome: Result<PublishingS3Plan.CheckResult, Error>?
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                outcome = Result { try Test.run(plan: live, username: user, password: password, cancellation: PublishingCancellation()) }
                done.signal()
            }
            guard done.wait(timeout: .now() + 40) == .success else { throw PublishingFailure("SELF-CHECK FAILED: the loopback test hung") }
            return try outcome!.get()
        }
        let good = try live("shots", user: "me", password: "pw")
        try expect(good.ok && good.message.contains("HTTP 200") && good.message.contains("Nothing was uploaded"), "a right login reaches the stub: \(good.message)")
        let bad = try live("shots", user: "me", password: "wrong")
        try expect(!bad.ok && bad.message.contains("HTTP 401") && !bad.message.contains("wrong"), "a wrong password is a 401: \(bad.message)")
        let missing = try live("missing", user: "me", password: "pw")
        try expect(!missing.ok && missing.message.contains("HTTP 404"), "a missing folder is a 404: \(missing.message)")
        let moved = try live("moved", user: "me", password: "pw")
        try expect(!moved.ok && moved.message.contains("HTTP 301") && moved.message.contains("redirected"), "a redirect is reported as such, not as a connection: \(moved.message)")
        let asked = server.requests
        try expect(asked.count == 4 && asked.allSatisfy { $0.line.hasPrefix("PROPFIND /dav/") && $0.length == 0 }, "the stub saw four PROPFIND and no body, and no OPTIONS: \(asked.map(\.line))")
        try expect(asked.allSatisfy { !$0.line.hasPrefix("PUT ") && !$0.line.hasPrefix("POST ") && !$0.line.hasPrefix("DELETE ") && !$0.line.hasPrefix("MKCOL ") }, "no request wrote anything")
    }

    /// --live-s3 "<destination name>": upload a tiny PNG, verify its public URL, print it, then DELETE the object.
    /// Reads the saved destination (and AWS profile or Keychain secret) exactly as the app would.
    // MARK: Destinations sheet (OSN-052): size, scrolling, keys, result row, Default pill, placeholders, message sheets, shutdown barrier

    static func keyEvent(_ characters: String, keyCode: UInt16, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }
    @MainActor static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    @MainActor static func spin(_ seconds: Double, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while !done() && Date() < end { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    }
    @MainActor static func coordinator(destinations: [PublishingDestination]) throws -> PublishingCoordinator {
        let coordinator = PublishingCoordinator()
        coordinator.store = PublishingDestinationStore(directory: try temporaryDirectory(), secrets: PublishingMemorySecrets())
        for destination in destinations { try coordinator.store.save(destination, password: "") }
        return coordinator
    }
    @MainActor static func fixtureDestinations() -> [PublishingDestination] {
        var s3 = awsCDN(); s3.s3?.credentialsProfile = "default"
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.com/files"; dav.publicBaseURL = "https://dav.example.com/files"
        return [PublishingDestination(name: "Example S3", settings: s3), PublishingDestination(name: "Example WebDAV", settings: dav)]
    }

    /// The editor sheet: sized from the screen and its parent, hugging its form, scrolling when the screen is short, with Return saving and
    /// Escape cancelling. (The list, Remove and Make Default live in Settings, Upload; SettingsWindowTests covers them.)
    @MainActor static func destinationsSheet() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let fake = NSRect(x: 0, y: 0, width: 1280, height: 800)

        // Size: 720 wide, min(720, visible height - 120), never taller than the screen.
        let size = PublishingDestinationsView.sheetSize(visibleFrame: fake)
        try expect(size.width == 720 && size.height == 680, "1280 x 800 gives a 720 x 680 sheet, got \(size)")
        try expect(PublishingDestinationsView.sheetSize(visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1200)).height == 760, "a tall screen caps the sheet at 760")
        let short = NSRect(x: 0, y: 0, width: 1280, height: 500)
        try expect(PublishingDestinationsView.sheetSize(visibleFrame: short).height == 380 && PublishingDestinationsView.sheetSize(visibleFrame: short).height <= 500, "a short screen shrinks the sheet")
        try expect(PublishingDestinationsView.sheetSize(visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 300)).height <= 300, "the sheet never exceeds a tiny screen")

        let destinations = fixtureDestinations()
        let publisher = try coordinator(destinations: destinations)
        let (panel, view) = publisher.buildEditor(editing: nil, visibleFrame: fake)
        defer { panel.orderOut(nil) }
        panel.contentView?.layoutSubtreeIfNeeded()
        try expect(view.scrollView.hasVerticalScroller && !view.scrollView.hasHorizontalScroller && view.scrollView.documentView != nil, "the form lives in a vertical NSScrollView")
        try expect(panel.title == "Add Destination" && publisher.buildEditor(editing: destinations[0]).0.title == "Edit Destination", "the sheet is titled for what it does")
        func contentHeight(_ p: NSPanel) -> CGFloat { p.contentRect(forFrameRect: p.frame).height }
        let panelWidth = panel.contentRect(forFrameRect: panel.frame).width
        try expect(panelWidth == 720 && panel.frame.height <= fake.height, "the sheet is 720 wide: \(panelWidth)")
        // The sheet is sized to the protocol's form (top edge fixed).
        let topEdge = panel.frame.maxY
        view.showForm(for: nil); panel.contentView?.layoutSubtreeIfNeeded()
        let webDAVHeight = contentHeight(panel)
        try expect(webDAVHeight < 680 && abs(webDAVHeight - view.preferredHeight) <= 0.5 && panel.frame.maxY == topEdge,
                   "the new-destination form hugs its rows instead of the 680 maximum: \(webDAVHeight), top \(panel.frame.maxY) vs \(topEdge)")
        func blankBand(_ p: NSPanel, _ v: PublishingDestinationsView) throws -> CGFloat {
            p.contentView?.layoutSubtreeIfNeeded()
            let help = try unwrap(descendants(v).compactMap { $0 as? NSTextField }.first { !$0.isHiddenOrHasHiddenAncestor && $0.stringValue == PublishingDestinationsView.formCopy(for: v.selectedProtocol).help })
            let helpBottom = help.convert(help.bounds, to: v).minY, footerTop = v.testButton.convert(v.testButton.bounds, to: v).maxY
            return helpBottom - footerTop
        }
        let webDAVBand = try blankBand(panel, view)
        try expect(webDAVBand < 120, "the WebDAV form leaves \(webDAVBand) pt of blank band above the buttons")
        var heights: [PublishingProtocol: CGFloat] = [:]
        for (index, transport) in PublishingProtocol.allCases.enumerated() {
            view.protocolPopup.selectItem(at: index); view.formChanged(); panel.contentView?.layoutSubtreeIfNeeded()
            heights[transport] = contentHeight(panel)
            let help = try unwrap(descendants(view).compactMap { $0 as? NSTextField }.first { !$0.isHiddenOrHasHiddenAncestor && $0.stringValue == PublishingDestinationsView.formCopy(for: transport).help })
            let needed = ceil(help.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: help.frame.width, height: .greatestFiniteMagnitude)).height ?? 0)
            try expect(help.frame.height + 0.5 >= needed, "\(transport) help is clipped: \(help.frame.height) of \(needed)")
            try expect(abs(heights[transport]! - view.preferredHeight) <= 0.5 && panel.frame.maxY == topEdge && panel.frame.height <= fake.height, "\(transport) sheet \(heights[transport]!) follows its form")
            let band = try blankBand(panel, view)
            try expect(band < 120, "\(transport) leaves \(band) pt of blank band")
        }
        try expect(heights[.s3]! > heights[.webDAV]! && heights[.sftp]! != heights[.s3]!, "the sheet height follows the protocol: \(heights)")
        view.protocolPopup.selectItem(at: 0); view.formChanged()
        // A Test error grows the result band, the sheet follows it, and Cancel leaves no trace of it.
        let beforeError = contentHeight(panel)
        view.showTestResult(ok: false, message: String(repeating: "The server answered with an error that needs a long explanation. ", count: 4))
        panel.contentView?.layoutSubtreeIfNeeded()
        try expect(contentHeight(panel) > beforeError && abs(contentHeight(panel) - view.preferredHeight) <= 0.5, "the sheet grows by the result band")
        view.cancelFormTapped()
        panel.contentView?.layoutSubtreeIfNeeded()
        try expect(view.formResult.isHidden && !descendants(view).contains { ($0 as? NSTextField)?.stringValue.hasPrefix("Error:") == true && !$0.isHiddenOrHasHiddenAncestor },
                   "Cancel clears the form's error (F-J4-001)")

        // A short screen: the S3 form is taller than the sheet, so it scrolls, and Save/Cancel stay on screen.
        let (shortPanel, shortView) = publisher.buildEditor(editing: destinations[0], visibleFrame: short)
        defer { shortPanel.orderOut(nil) }
        shortPanel.contentView?.layoutSubtreeIfNeeded()
        let document = try unwrap(shortView.scrollView.documentView), clip = shortView.scrollView.contentView.bounds
        try expect(shortPanel.contentRect(forFrameRect: shortPanel.frame).height <= short.height, "the short-screen sheet fits the visible frame")
        try expect(document.frame.height > clip.height, "the S3 form (\(document.frame.height)) is not taller than the visible scroll area (\(clip.height)): nothing would need to scroll")
        try expect(document.frame.width <= clip.width + 0.5, "the form is wider than the sheet and would scroll sideways")
        let bounds = try unwrap(shortPanel.contentView).bounds
        for button in [shortView.saveButton, shortView.cancelButton] {
            let frame = button.convert(button.bounds, to: shortPanel.contentView)
            try expect(bounds.contains(frame) && !button.isHiddenOrHasHiddenAncestor, "\(button.title) scrolled out of the short sheet: \(frame) in \(bounds)")
        }

        // Section headers group the rows.
        view.showForm(for: nil); panel.contentView?.layoutSubtreeIfNeeded()
        try expect(view.sectionHeaders.map(\.stringValue) == ["Connection", "Credentials"], "section headers: \(view.sectionHeaders.map(\.stringValue))")
        try expect(view.sectionHeaders.allSatisfy { $0.font?.pointSize == 22 && !$0.isHiddenOrHasHiddenAncestor }, "section headers use the headline style")
        let doc = try unwrap(view.scrollView.documentView)
        func y(_ item: NSView) -> CGFloat { item.convert(item.bounds, to: doc).minY }
        try expect(y(view.sectionHeaders[0]) < y(view.endpointField) && y(view.endpointField) < y(view.sectionHeaders[1]) && y(view.sectionHeaders[1]) < y(view.usernameField),
                   "Connection rows sit under Connection and Credentials rows under Credentials")

        // Text sizes: body everywhere readable, headline for headers.
        for control in descendants(view).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor {
            try expect((control.font?.pointSize ?? 20) >= 18, "\(type(of: control)) is below 18 pt")
        }
        try expect([view.saveButton, view.cancelButton, view.testButton].allSatisfy { $0.font?.pointSize == 20 }, "dialog buttons are body size (20 pt)")

        // Placeholders are neutral.
        let fields = descendants(view).compactMap { $0 as? NSTextField }.compactMap(\.placeholderString)
        try expect(!fields.isEmpty && !fields.contains { $0.lowercased().contains("shoemoney") }, "a placeholder names the owner: \(fields.filter { $0.lowercased().contains("shoemoney") })")
        try expect(view.aliasField.placeholderString == "myserver or host.example.com" && view.remoteRootField.placeholderString == "/var/www/site/uploads"
                   && view.endpointField.placeholderString == "https://example.com/uploads" && view.folderField.placeholderString?.hasPrefix("screenshots") == true,
                   "neutral SSH alias, SFTP root, endpoint and folder placeholders")

        // The product word is Upload: no user-visible string on the form says Webpost.
        func visibleStrings(_ root: NSView) -> [String] {
            var strings: [String] = []
            for item in descendants(root) {
                strings.append(contentsOf: [item.toolTip, item.accessibilityLabel()].compactMap { $0 })
                if let field = item as? NSTextField { strings.append(contentsOf: [field.stringValue, field.placeholderString].compactMap { $0 }) }
                if let button = item as? NSButton { strings.append(button.title) }
                if let popup = item as? NSPopUpButton { strings.append(contentsOf: popup.itemArray.flatMap { [$0.title, $0.toolTip ?? ""] }) }
            }
            return strings
        }
        for transport in PublishingProtocol.allCases {
            view.showForm(for: nil); view.protocolPopup.selectItem(withTitle: transport.title); view.formChanged()
            let offenders = visibleStrings(view).filter { $0.lowercased().contains("webpost") }
            try expect(offenders.isEmpty, "\(transport.title) form still says Webpost: \(offenders)")
        }
        let lastOne = PublishingDestinationList(defaultID: destinations[0].id, destinations: [destinations[0]])
        try expect(!lastOne.removalPrompt(for: destinations[0]).detail.lowercased().contains("webpost"), "the remove prompt still says Webpost")

        // No form label wraps or truncates at 720 wide, for any protocol and credential source, and the Protocol popup shows every title whole.
        view.showForm(for: nil)
        for transport in PublishingProtocol.allCases {
            for source in 0...1 {
                view.protocolPopup.selectItem(withTitle: transport.title); view.sourcePopup.selectItem(at: source); view.formChanged()
                panel.contentView?.layoutSubtreeIfNeeded()
                let captions = view.visibleFormCaptions
                try expect(captions.count >= 6, "\(transport.title)/\(source): only \(captions.count) form captions found")
                for caption in captions {
                    let cell = try unwrap(caption.cell)
                    let natural = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 1_000))
                    try expect(natural.width <= caption.frame.width + 0.5,
                               "“\(caption.stringValue)” needs \(natural.width) pt on one line but its column is \(caption.frame.width) (\(transport.title)/\(source))")
                    try expect(caption.frame.height <= natural.height + 0.5, "“\(caption.stringValue)” wraps to \(caption.frame.height) pt tall (\(transport.title)/\(source))")
                }
            }
        }
        view.protocolPopup.selectItem(withTitle: PublishingProtocol.s3.title); view.formChanged()
        try expect(view.visibleFormCaptions.contains { $0.stringValue == "Endpoint" } && view.endpointField.placeholderString?.contains("Blank for AWS") == true,
                   "the S3 endpoint row is labelled Endpoint with the AWS hint as its placeholder")
        panel.contentView?.layoutSubtreeIfNeeded()
        let popupFont = try unwrap(view.protocolPopup.font)
        for item in view.protocolPopup.itemArray {
            let width = (item.title as NSString).size(withAttributes: [.font: popupFont]).width
            try expect(width + 30 <= view.protocolPopup.frame.width && view.protocolPopup.frame.width >= view.protocolPopup.intrinsicContentSize.width - 0.5,
                       "the Protocol item “\(item.title)” (\(width) pt) truncates in a \(view.protocolPopup.frame.width) pt popup that wants \(view.protocolPopup.intrinsicContentSize.width)")
            try expect(item.toolTip?.isEmpty == false && item.title.count <= 16, "“\(item.title)” is a short title with the provider detail in its tooltip")
        }

        view.showForm(for: nil); panel.contentView?.layoutSubtreeIfNeeded()
        // Return saves, Escape cancels.
        var saved: [String] = [], cancelled = 0
        view.onSave = { destination, _ in saved.append(destination.name) }
        view.onCancel = { cancelled += 1 }
        view.nameField.stringValue = "Keys"; view.endpointField.stringValue = "https://dav.example.com/up"
        try expect(view.saveButton.keyEquivalent == "\r" && view.cancelButton.keyEquivalent == "\u{1b}", "Save is the Return button and Cancel the Escape button")
        panel.contentView?.layoutSubtreeIfNeeded()
        try expect(panel.contentView?.performKeyEquivalent(with: keyEvent("\r", keyCode: 36, window: panel)) == true && saved == ["Keys"], "Return did not save (saved \(saved))")
        try expect(panel.contentView?.performKeyEquivalent(with: keyEvent("\u{1b}", keyCode: 53, window: panel)) == true && cancelled == 1, "Escape did not cancel the editor")

        // Test result: glyph and words together.
        view.showForm(for: nil)
        view.showTestResult(ok: true, message: "OK: credentials and bucket verified. Nothing was uploaded.")
        var row = view.formResult
        try expect(!row.isHiddenOrHasHiddenAncestor && row.kind == .success && row.text.stringValue == "Connected" && row.glyph.image != nil && !row.glyph.isHidden, "success shows a glyph and the word Connected")
        try expect(row.detail.stringValue.contains("Nothing was uploaded") && !row.detail.isHidden, "the server's detail follows the word Connected")
        let successGlyph = row.glyph.image
        view.showTestResult(ok: false, message: "AccessDenied: no such bucket")
        row = view.formResult
        try expect(row.kind == .failure && row.text.stringValue == "Error: AccessDenied: no such bucket" && row.glyph.image != nil && !row.glyph.isHidden, "failure shows a glyph and an Error: line")
        try expect(row.glyph.image !== successGlyph, "success and failure use different glyphs")
        for icon in [FAIcon.circleCheck, .xmarkCircle, .check] {
            if case .sfSymbol = ChromeIcons.resolve(icon, family: .solid).source { throw PublishingFailure("\(icon) is an SF Symbol here; Destinations must use the chrome icon family") }
        }
        try expect(row.glyph.image?.isTemplate == true && successGlyph?.isTemplate == true, "status glyphs are template images that take the text colour")
        view.showStatus("Network is down")
        try expect(view.formResult.text.stringValue == "Error: Network is down" && view.formResult.glyph.image != nil, "a coordinator failure is prefixed and carries the failure glyph")
        view.protocolPopup.selectItem(withTitle: PublishingProtocol.s3.title); view.formChanged()
        view.sourcePopup.selectItem(at: 0); view.formChanged(); view.profileField.stringValue = ""
        view.saveTapped()
        try expect(view.formResult.text.stringValue.hasPrefix("Error: ") && view.formResult.glyph.image != nil, "a validation error also gets the prefix and glyph: \(view.formResult.text.stringValue)")

        // Editing a saved destination opens its own values, and saving it keeps the Keychain item while the secret is unchanged.
        let edited = try unwrap(try publisher.store.load().destinations.first { $0.name == "Example WebDAV" })
        let (editPanel, editView) = publisher.buildEditor(editing: edited)
        defer { editPanel.orderOut(nil) }
        try expect(editView.editing?.id == edited.id && editView.nameField.stringValue == "Example WebDAV" && editView.endpointField.stringValue == edited.settings.endpoint, "Edit opens the saved values")

        // The shutdown barrier still runs with the editor open.
        let shutdownParent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        shutdownParent.isReleasedWhenClosed = false
        let closing = try coordinator(destinations: destinations)
        closing.showEditor(editing: nil, relativeTo: shutdownParent)
        try expect(shutdownParent.attachedSheet != nil, "the editor sheet did not open")
        var acknowledged = false
        closing.shutdown { acknowledged = true }
        spin(5) { acknowledged && shutdownParent.attachedSheet == nil }
        try expect(acknowledged, "shutdown never acknowledged with the sheet open")
        try expect(shutdownParent.attachedSheet == nil, "shutdown left the editor sheet attached")
        closing.showEditor(editing: nil, relativeTo: shutdownParent)
        try expect(shutdownParent.attachedSheet == nil, "a sheet opened after shutdown")

        // An editor sheet begun on a window directly (no completion handler, as the screenshot harness does) must not hold Quit forever.
        let bareParent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        bareParent.isReleasedWhenClosed = false
        let bare = try coordinator(destinations: destinations)
        let (barePanel, _) = bare.buildEditor(editing: nil)
        bareParent.beginSheet(barePanel)
        try expect(bareParent.attachedSheet === barePanel, "the bare sheet did not open")
        bare.cancelSettings()
        var bareAcknowledged = false
        bare.shutdown { bareAcknowledged = true }
        spin(5) { bareAcknowledged }
        try expect(bareAcknowledged, "shutdown never acknowledged after an editor sheet ended without its completion handler")
        try expect(bareParent.attachedSheet == nil, "the bare sheet stayed attached")
    }

    static func liveS3() throws {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--live-s3"), flag + 1 < arguments.count else {
            throw PublishingFailure("--live-s3 requires a saved destination name, e.g. --live-s3 \"AWS cdn\".")
        }
        let wanted = arguments[flag + 1]
        let store = PublishingDestinationStore.system
        let list = try store.load()
        guard let destination = list.destinations.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) else {
            throw PublishingFailure("No saved destination is named “\(wanted)”. Saved: " + list.destinations.map(\.name).joined(separator: ", "))
        }
        guard destination.settings.transport == .s3 else { throw PublishingFailure("“\(wanted)” is not an S3 destination.") }
        let credentials = try PublishingS3Credentials.resolve(
            settings: destination.settings, secrets: store.secrets,
            credentialsFile: AWSSharedCredentials.defaultFile(environment: ProcessInfo.processInfo.environment, home: URL(fileURLWithPath: NSHomeDirectory())))
        let name = "opensnap-live-check-" + UUID().uuidString.lowercased() + ".png"
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jS1cAAAAASUVORK5CYII=")!
        let worker = PublishingWorkController()
        func run<T>(_ body: @escaping (PublishingCancellation) throws -> T) throws -> T {
            var outcome: Result<T, Error>?
            worker.start(work: body) { outcome = $0 }
            while outcome == nil { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
            return try outcome!.get()
        }
        let capabilities = try run { try PublishingCurl.capabilities(cancellation: $0) }
        let plan = try PublishingPlan(settings: destination.settings, fileName: name, capabilities: capabilities)
        let s3 = try unwrap(plan.s3)
        print("Uploading " + s3.key + " to bucket " + s3.bucket + " (" + s3.region + ")…")
        var failure: Error?
        do {
            let url = try run {
                try PublishingTransfer.upload(data: png, plan: plan, username: credentials.accessKeyID, password: credentials.secretAccessKey,
                                              sessionToken: credentials.sessionToken, cancellation: $0)
            }
            print("Uploaded and verified exact bytes at the public URL: " + url.absoluteString)
        } catch { failure = error }
        // The object is removed whether or not verification passed, so a failed check leaves nothing behind.
        do {
            try run { try PublishingS3Operations.delete(plan: s3, credentials: credentials, cancellation: $0) }
            print("Deleted " + s3.key + " (signed DELETE accepted).")
        } catch {
            print("WARNING: could not delete " + s3.key + ": " + error.localizedDescription)
            if failure == nil { failure = error }
        }
        if let failure { throw failure }
        print("LIVE S3 CHECK PASSED")
    }
}
