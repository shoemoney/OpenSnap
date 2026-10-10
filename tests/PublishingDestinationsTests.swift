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
        try migration()
        try storeOperations()
        try MainActor.assumeIsolated { try destinationsSheet() }
        try MainActor.assumeIsolated { try removalSheet() }
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

        // Removal prompt wording (the view builds it; the alert only displays it).
        var keyed = PublishingDestination(name: "Work DAV", settings: dav)
        let other = PublishingDestination(name: "Backup", settings: awsCDN())
        keyed.settings.credentialID = "00000000-0000-0000-0000-0000000000CC"
        let two = PublishingDestinationList(defaultID: keyed.id, destinations: [keyed, other])
        let promptDefault = PublishingDestinationsView.removalPrompt(for: keyed, in: two)
        try expect(promptDefault.title == "Remove “Work DAV”?" && promptDefault.detail.contains("Keychain") && promptDefault.detail.contains("“Backup” becomes the default"), "removing the default names the new default and the secret")
        let promptOther = PublishingDestinationsView.removalPrompt(for: other, in: two)
        try expect(!promptOther.detail.contains("becomes the default") && !promptOther.detail.contains("Keychain"), "a non-default, secret-free destination gets no default or Keychain wording")
        let promptLast = PublishingDestinationsView.removalPrompt(for: keyed, in: PublishingDestinationList(defaultID: keyed.id, destinations: [keyed]))
        try expect(promptLast.detail.contains("only destination"), "removing the last destination says so")
        let promptLegacy = PublishingDestinationsView.removalPrompt(for: keyed, in: two, legacyCredentialID: keyed.settings.credentialID)
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

        var profile = awsCDN(); profile.s3?.credentialsProfile = "default"
        let third = PublishingDestination(name: "Profile", settings: profile)
        try store.save(third, password: "")
        try expect(secrets.items.count == 2, "an AWS-profile destination stores no secret")

        try store.remove(second.id)
        try expect(try store.load().destinations.map(\.name) == ["Work DAV", "Profile"] && (try store.load().defaultID) == (try store.load().destinations[0].id), "removing the default promotes the first remaining")
        try expect(secrets.items.count == 1, "removing deletes its secret")
        try store.remove(first.id); try store.remove(third.id)
        try expect(try store.load().destinations.isEmpty && secrets.items.isEmpty && (try store.load().defaultID) == nil, "removing everything leaves an empty list")
        try expect(!(try Data(contentsOf: store.file).isEmpty) && !String(decoding: try Data(contentsOf: store.file), as: UTF8.self).contains("s3-secret"), "the file never holds a secret")
    }

    // MARK: Live check

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

    /// Audit fix 1 (item 5): removing a destination asks through an app-owned `AppAlert` (a sheet, text at the app's size), not a system
    /// NSAlert. Title names the destination, Remove is destructive and the default, Cancel answers Escape, nothing is removed until the
    /// answer, and closing the destinations sheet answers an open question as Cancel first (the shutdown barrier).
    @MainActor static func removalSheet() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let destinations = fixtureDestinations()
        let publisher = try coordinator(destinations: destinations)
        let (panel, view) = try publisher.buildSettings(visibleFrame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        defer { panel.orderOut(nil) }
        var shown: [(alert: AppAlert, host: NSWindow?)] = []
        AppAlert.presenter = { alert, host, completion in
            shown.append((alert, host))
            // The presenter owns the answer; the test gives it by pressing a button, as the sheet would.
            _ = completion
        }
        defer { AppAlert.presenter = nil }
        let target = destinations[0]
        try expect(view.confirmRemoval == nil, "the view asks through its own AppAlert unless a test replaces the seam")
        view.select(id: target.id); view.removeTapped()
        try expect(shown.count == 1 && view.pendingRemoval === shown[0].alert, "Remove opens exactly one app-owned alert")
        let alert = shown[0].alert
        try expect(alert.title == "Remove “\(target.name)”?" && alert.message == PublishingDestinationsView.removalPrompt(for: target, in: view.list).detail,
                   "the title names the destination and the message is the removal prompt (\(alert.title))")
        try expect(alert.buttons == [.init(title: "Remove", role: .destructive), .init(title: "Cancel", role: .cancel)], "buttons are a destructive Remove and a Cancel")
        try expect(alert.buttonViews[0].keyEquivalent == "\r" && alert.buttonViews[0].hasDestructiveAction && alert.buttonViews[1].keyEquivalent == "\u{1b}", "Return removes, it is marked destructive, and Escape cancels")
        try expect((alert.titleLabel.font?.pointSize ?? 0) >= 18 && (alert.messageLabel.font?.pointSize ?? 0) >= 18 && alert.buttonViews.allSatisfy { ($0.font?.pointSize ?? 0) >= 18 },
                   "the text is the app's size, not the system alert's")
        try expect(shown[0].host === panel, "the question hangs from the destinations sheet")
        try expect(view.list.destinations.count == 2 && (try publisher.store.load().destinations.count) == 2, "nothing is removed before the answer")
        view.removeTapped()
        try expect(shown.count == 1, "a second Remove while the question is open does not stack another")
        alert.dismiss(withButton: 1)
        try expect(view.pendingRemoval == nil && view.list.destinations.count == 2 && (try publisher.store.load().destinations.count) == 2, "Cancel removes nothing and frees the view")
        // Escape is Cancel.
        view.removeTapped(); shown.last?.alert.cancel()
        try expect(shown.count == 2 && view.list.destinations.count == 2, "Escape answers Cancel")
        // Closing the destinations sheet answers an open question as Cancel before the sheet goes.
        view.removeTapped()
        try expect(shown.count == 3 && view.pendingRemoval === shown[2].alert, "the question is open again")
        publisher.cancelSettings()
        try expect(view.pendingRemoval == nil && shown[2].alert.response == .alertSecondButtonReturn && (try publisher.store.load().destinations.count) == 2,
                   "closing the sheet answers the open question as Cancel and removes nothing")
        // Remove removes.
        let (panel2, view2) = try publisher.buildSettings(visibleFrame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        defer { panel2.orderOut(nil) }
        view2.select(id: target.id); view2.removeTapped()
        try expect(shown.count == 4, "a fresh sheet asks again")
        shown[3].alert.dismiss(withButton: 0)
        try expect(view2.list.destinations.map(\.id) == [destinations[1].id] && (try publisher.store.load().destinations.map(\.id)) == [destinations[1].id], "Remove removes the destination from the sheet and from storage")
    }

    @MainActor static func destinationsSheet() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let fake = NSRect(x: 0, y: 0, width: 1280, height: 800)

        // Size: 720 wide, min(720, visible height - 120), never taller than the screen.
        let size = PublishingDestinationsView.sheetSize(visibleFrame: fake)
        try expect(size.width == 720 && size.height == 680, "1280 x 800 gives a 720 x 680 sheet, got \(size)")
        try expect(PublishingDestinationsView.sheetSize(visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1200)).height == 720, "a tall screen caps the sheet at 720")
        let short = NSRect(x: 0, y: 0, width: 1280, height: 500)
        try expect(PublishingDestinationsView.sheetSize(visibleFrame: short).height == 380 && PublishingDestinationsView.sheetSize(visibleFrame: short).height <= 500, "a short screen shrinks the sheet")
        try expect(PublishingDestinationsView.sheetSize(visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 300)).height <= 300, "the sheet never exceeds a tiny screen")

        let destinations = fixtureDestinations()
        let publisher = try coordinator(destinations: destinations)
        let (panel, view) = try publisher.buildSettings(visibleFrame: fake)
        defer { panel.orderOut(nil) }
        panel.contentView?.layoutSubtreeIfNeeded()
        try expect(view.scrollView.hasVerticalScroller && !view.scrollView.hasHorizontalScroller && view.scrollView.documentView != nil, "the form lives in a vertical NSScrollView")

        // The list page hugs its content: table, buttons and footer, with no blank slab under them (two rows here, shown as the four-row minimum).
        func contentHeight(_ p: NSPanel) -> CGFloat { p.contentRect(forFrameRect: p.frame).height }
        func listSlack(_ p: NSPanel, _ v: PublishingDestinationsView) throws -> (slack: CGFloat, height: CGFloat) {
            p.contentView?.layoutSubtreeIfNeeded()
            let title = try unwrap(descendants(v).compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("Upload destinations") })
            let add = try unwrap(descendants(v).compactMap { $0 as? NSButton }.first { $0.title == "Add…" })
            let table = try unwrap(v.table.enclosingScrollView)
            // Title, table and buttons plus the two gaps between them, the page margins, separator, footer gap, footer and its bottom margin.
            let needed = title.frame.height + table.frame.height + add.frame.height + 2 * DesignTokens.Space.s4
                + 2 * DesignTokens.Space.s5 + 1 + DesignTokens.Space.s3 + v.doneButton.frame.height + DesignTokens.Space.s4
            return (contentHeight(p) - needed, contentHeight(p))
        }
        let hugged = try listSlack(panel, view)
        try expect(hugged.slack <= 40 && hugged.slack >= -1, "the list page has \(hugged.slack) pt of slack (sheet \(hugged.height)); it should hug table, buttons and footer")
        try expect(hugged.height < 600, "the list sheet is \(hugged.height) tall; it must not stretch to the form's 680")
        let listRowHeight = DesignTokens.Size.row + view.table.intercellSpacing.height
        try expect((view.table.enclosingScrollView?.frame.height ?? 0) >= 4 * listRowHeight, "the table shows fewer than four rows")
        let listPanelWidth = panel.contentRect(forFrameRect: panel.frame).width
        try expect(listPanelWidth == 720 && panel.frame.height <= fake.height, "the sheet is 720 wide: \(listPanelWidth)")
        // Paging to the form grows the sheet to the full height (top edge fixed); Cancel hugs the list again.
        let topEdge = panel.frame.maxY
        view.addTapped(); panel.contentView?.layoutSubtreeIfNeeded()
        try expect(contentHeight(panel) == 680 && panel.frame.maxY == topEdge, "the form page is 720 wide by 680 with the top edge fixed: \(contentHeight(panel)), top \(panel.frame.maxY) vs \(topEdge)")
        view.cancelFormTapped()
        let back = try listSlack(panel, view)
        try expect(abs(back.height - hugged.height) <= 0.5 && panel.frame.maxY == topEdge, "Cancel did not return to the hugged list height: \(back.height) vs \(hugged.height)")
        // A long list stops growing at eight rows and scrolls.
        let many = try coordinator(destinations: (0..<12).map { PublishingDestination(name: "Destination \($0)", settings: destinations[1].settings) })
        let (manyPanel, manyView) = try many.buildSettings(visibleFrame: fake)
        defer { manyPanel.orderOut(nil) }
        manyPanel.contentView?.layoutSubtreeIfNeeded()
        let manyHeight = try unwrap(manyView.table.enclosingScrollView).frame.height
        try expect(abs(manyHeight - (CGFloat(PublishingDestinationsView.maxListRows) * listRowHeight + 4)) <= 0.5 && contentHeight(manyPanel) <= 680,
                   "twelve destinations show \(manyHeight) pt of table in a \(contentHeight(manyPanel)) sheet; the cap is eight rows")

        // A short screen: the S3 form is taller than the sheet, so it scrolls, and Save/Cancel stay on screen.
        let (shortPanel, shortView) = try publisher.buildSettings(visibleFrame: short)
        defer { shortPanel.orderOut(nil) }
        shortPanel.contentView?.layoutSubtreeIfNeeded()
        shortView.select(id: destinations[0].id); shortView.editTapped()
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
        view.addTapped(); panel.contentView?.layoutSubtreeIfNeeded()
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
        try expect([view.saveButton, view.cancelButton, view.doneButton, view.testButton].allSatisfy { $0.font?.pointSize == 20 }, "dialog buttons are body size (20 pt)")

        // Placeholders are neutral.
        let fields = descendants(view).compactMap { $0 as? NSTextField }.compactMap(\.placeholderString)
        try expect(!fields.isEmpty && !fields.contains { $0.lowercased().contains("shoemoney") }, "a placeholder names the owner: \(fields.filter { $0.lowercased().contains("shoemoney") })")
        try expect(view.aliasField.placeholderString == "myserver (from ~/.ssh/config)" && view.remoteRootField.placeholderString == "/var/www/site/uploads"
                   && view.endpointField.placeholderString == "https://example.com/uploads" && view.folderField.placeholderString?.hasPrefix("screenshots") == true,
                   "neutral SSH alias, SFTP root, endpoint and folder placeholders")

        // The product word is Upload: no user-visible string on either page says Webpost.
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
        func noWebpost(_ page: String) throws {
            let offenders = visibleStrings(view).filter { $0.lowercased().contains("webpost") }
            try expect(offenders.isEmpty, "\(page) page still says Webpost: \(offenders)")
        }
        view.cancelFormTapped()
        try noWebpost("list")
        try expect(visibleStrings(view).contains { $0.contains("Upload click") }, "the list intro names the Upload click")
        for transport in PublishingProtocol.allCases {
            view.addTapped(); view.protocolPopup.selectItem(withTitle: transport.title); view.formChanged()
            try noWebpost("\(transport.title) form")
            view.cancelFormTapped()
        }
        let lastOne = PublishingDestinationList(defaultID: destinations[0].id, destinations: [destinations[0]])
        try expect(!PublishingDestinationsView.removalPrompt(for: destinations[0], in: lastOne).detail.lowercased().contains("webpost"), "the remove prompt still says Webpost")

        // No form label wraps or truncates at 720 wide, for any protocol and credential source, and the Protocol popup shows every title whole.
        view.addTapped()
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
        try expect(view.visibleFormCaptions.contains { $0.stringValue == "Endpoint" } && view.endpointField.placeholderString?.contains("blank for AWS") == true,
                   "the S3 endpoint row is labelled Endpoint with the AWS hint as its placeholder")
        panel.contentView?.layoutSubtreeIfNeeded()
        let popupFont = try unwrap(view.protocolPopup.font)
        for item in view.protocolPopup.itemArray {
            let width = (item.title as NSString).size(withAttributes: [.font: popupFont]).width
            try expect(width + 30 <= view.protocolPopup.frame.width && view.protocolPopup.frame.width >= view.protocolPopup.intrinsicContentSize.width - 0.5,
                       "the Protocol item “\(item.title)” (\(width) pt) truncates in a \(view.protocolPopup.frame.width) pt popup that wants \(view.protocolPopup.intrinsicContentSize.width)")
            try expect(item.toolTip?.isEmpty == false && item.title.count <= 16, "“\(item.title)” is a short title with the provider detail in its tooltip")
        }
        view.cancelFormTapped()

        view.addTapped(); panel.contentView?.layoutSubtreeIfNeeded()
        // Return saves, Escape cancels (form page).
        var saved: [String] = []
        view.onSave = { destination, _ in saved.append(destination.name) }
        view.nameField.stringValue = "Keys"; view.endpointField.stringValue = "https://dav.example.com/up"
        try expect(view.saveButton.keyEquivalent == "\r" && view.cancelButton.keyEquivalent == "\u{1b}", "Save is the Return button and Cancel the Escape button")
        panel.contentView?.layoutSubtreeIfNeeded()
        try expect(panel.contentView?.performKeyEquivalent(with: keyEvent("\r", keyCode: 36, window: panel)) == true && saved == ["Keys"], "Return did not save (saved \(saved))")
        try expect(panel.contentView?.performKeyEquivalent(with: keyEvent("\u{1b}", keyCode: 53, window: panel)) == true && view.editing == nil && view.cancelButton.isHiddenOrHasHiddenAncestor,
                   "Escape did not cancel the form back to the list")
        // List page: Return and Escape both finish.
        var done = 0
        view.onDone = { done += 1 }
        try expect(!view.doneButton.isHiddenOrHasHiddenAncestor && view.doneButton.keyEquivalent == "\r", "Done is the list sheet's Return button")
        try expect(panel.contentView?.performKeyEquivalent(with: keyEvent("\r", keyCode: 36, window: panel)) == true && done == 1, "Return did not finish the list sheet")
        try expect(panel.contentView?.performKeyEquivalent(with: keyEvent("\u{1b}", keyCode: 53, window: panel)) == true && done == 2, "Escape did not finish the list sheet")

        // Test result: glyph and words together.
        view.addTapped()
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
        view.cancelFormTapped()

        // Default pill instead of the "(Default)" suffix.
        view.reload(try publisher.store.load())
        let defaultRow = try unwrap(view.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? DestinationRowView)
        let otherRow = try unwrap(view.table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? DestinationRowView)
        let pill = try unwrap(defaultRow.pill)
        try expect(pill.label.stringValue == "Default" && pill.glyph.image != nil, "the Default pill has the word and a check glyph")
        try expect(otherRow.pill == nil, "a non-default destination has no pill")
        try expect(!defaultRow.nameField.stringValue.contains("(Default)") && defaultRow.nameField.stringValue == "Example S3" && defaultRow.transportField.stringValue == "S3", "the name no longer carries a (Default) suffix")
        try publisher.setDefaultDestination(destinations[1].id); view.reload(try publisher.store.load())
        let moved = try unwrap(view.table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? DestinationRowView)
        try expect(moved.pill != nil && (view.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? DestinationRowView)?.pill == nil, "the pill follows the default")

        // Message sheets are at least 560 wide.
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let messenger = PublishingCoordinator()
        messenger.presentMessage("The sharing settings could not be opened because the destination list is unreadable.", relativeTo: parent)
        let message = try unwrap(parent.attachedSheet)
        try expect(message.frame.width >= 560 && PublishingCoordinator.messageSheetMinimumWidth == 560, "message sheet is \(message.frame.width) wide, below 560")
        try expect(message.contentMinSize.width >= 560, "message sheet minimum width is below 560")
        messenger.cancelSettings(); spin(1) { parent.attachedSheet == nil }

        // The shutdown barrier still runs with the Destinations sheet open.
        let shutdownParent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        shutdownParent.isReleasedWhenClosed = false
        let closing = try coordinator(destinations: destinations)
        closing.showSettings(relativeTo: shutdownParent)
        try expect(shutdownParent.attachedSheet != nil, "the Destinations sheet did not open")
        var acknowledged = false
        closing.shutdown { acknowledged = true }
        spin(5) { acknowledged && shutdownParent.attachedSheet == nil }
        try expect(acknowledged, "shutdown never acknowledged with the sheet open")
        try expect(shutdownParent.attachedSheet == nil, "shutdown left the Destinations sheet attached")
        closing.showSettings(relativeTo: shutdownParent)
        try expect(shutdownParent.attachedSheet == nil, "a sheet opened after shutdown")
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
