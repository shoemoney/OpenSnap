import AppKit

/// The conditions under which the process is a screenshot-harness copy. One definition: the audit itself and every harness-only
/// behaviour (the injected display options) pass through it, so none of them can be reached from a normal launch.
enum HarnessGate {
    /// Every bundle id a harness copy may carry. The real ids (com.shoemoney.opensnap, and the retired product's) never match.
    static let bundlePrefix = "com.shoemoney.opensnap.eyedump-"
    static let auditFlag = "--eye-dump-audit"

    /// The audit output folder, or nil unless the process is fully isolated: `--eye-dump-audit <dir>`, an isolated support
    /// folder, an isolated home, a throwaway bundle id (its own defaults domain) and no document fixture.
    static func auditDirectory(arguments: [String], environment: [String: String], bundleIdentifier: String?) -> URL? {
        guard let flag = arguments.firstIndex(of: auditFlag), arguments.indices.contains(flag + 1) else { return nil }
        var isDirectory: ObjCBool = false
        guard let support = environment["OPENSNAP_APP_SUPPORT"], !support.isEmpty,
              FileManager.default.fileExists(atPath: support, isDirectory: &isDirectory), isDirectory.boolValue,
              let home = environment["CFFIXED_USER_HOME"], !home.isEmpty,
              (environment["OPENSNAP_FIXTURE"] ?? "").isEmpty,
              let bundleIdentifier, bundleIdentifier.hasPrefix(bundlePrefix) else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    }
}

/// The four system display options the interface adapts to, as one value. It is only ever read: the app never writes a system
/// accessibility setting, and tests and the screenshot harness inject values instead of changing the machine.
///
/// `current` resolves, first match wins:
///   1. `override`: a test or a harness-internal pin;
///   2. `injection`: the harness environment variable, honoured only behind `HarnessGate`;
///   3. `workspaceReader`: `NSWorkspace.shared.accessibilityDisplayShould*`.
struct DisplayOptions: Equatable, Sendable {
    var reduceMotion = false
    var reduceTransparency = false
    var increaseContrast = false
    var differentiateWithoutColor = false

    static let none = DisplayOptions()

    /// Names in the canonical order used by the harness variable, manifests and capture suffixes.
    static let names = ["reduceTransparency", "increaseContrast", "differentiateWithoutColor", "reduceMotion"]
    private static let suffixes = ["reduceTransparency": "rt", "increaseContrast": "ic", "differentiateWithoutColor": "dwc", "reduceMotion": "rm"]

    /// Environment variable the harness script sets on its throwaway copy: a comma-separated subset of `names`.
    static let harnessEnvironmentKey = "OPENSNAP_AUDIT_DISPLAY_OPTIONS"

    func isOn(_ name: String) -> Bool {
        switch name {
        case "reduceMotion": return reduceMotion
        case "reduceTransparency": return reduceTransparency
        case "increaseContrast": return increaseContrast
        case "differentiateWithoutColor": return differentiateWithoutColor
        default: return false
        }
    }

    /// The options that are on, in canonical order.
    var activeNames: [String] { Self.names.filter(isOn) }

    /// "-rt-ic" style tail for a capture file stem; empty when nothing is on.
    var stemSuffix: String { activeNames.compactMap { Self.suffixes[$0] }.map { "-" + $0 }.joined() }

    /// Parses a comma-separated list of option names. Unknown names are ignored: the harness records what was applied.
    static func parse(_ list: String) -> DisplayOptions {
        var options = DisplayOptions()
        for raw in list.split(separator: ",") {
            switch raw.trimmingCharacters(in: .whitespaces) {
            case "reduceMotion": options.reduceMotion = true
            case "reduceTransparency": options.reduceTransparency = true
            case "increaseContrast": options.increaseContrast = true
            case "differentiateWithoutColor": options.differentiateWithoutColor = true
            default: break
            }
        }
        return options
    }

    /// The options a harness copy was told to simulate, or nil. Honoured ONLY when `HarnessGate` is satisfied, so a normal
    /// launch can never be put into a fake accessibility state by an environment variable.
    static func harnessInjection(arguments: [String] = CommandLine.arguments,
                                 environment: [String: String] = ProcessInfo.processInfo.environment,
                                 bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> DisplayOptions? {
        guard HarnessGate.auditDirectory(arguments: arguments, environment: environment, bundleIdentifier: bundleIdentifier) != nil else { return nil }
        guard let list = environment[harnessEnvironmentKey], !list.isEmpty else { return nil }
        return parse(list)
    }

    /// Reads the live system values. Never writes anything.
    @MainActor static func readWorkspace(_ workspace: NSWorkspace = .shared) -> DisplayOptions {
        DisplayOptions(reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                       reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                       increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                       differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor)
    }

    // MARK: sources, in precedence order

    /// 1. A test or harness-internal pin. Tests set it and clear it in a `defer`.
    @MainActor static var override: DisplayOptions?
    /// 2. The harness environment, resolved once for the process (the environment cannot change after launch).
    @MainActor static var injection: () -> DisplayOptions? = { processInjection }
    /// 3. The system.
    @MainActor static var workspaceReader: () -> DisplayOptions = { readWorkspace() }

    private static let processInjection = harnessInjection()

    @MainActor static var current: DisplayOptions { override ?? injection() ?? workspaceReader() }

    // MARK: observation

    /// Subscription to display-option changes; ends when released or invalidated.
    @MainActor final class Observation {
        private var token: NSObjectProtocol?
        fileprivate init(token: NSObjectProtocol) { self.token = token }
        func invalidate() {
            guard let token else { return }
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            self.token = nil
        }
        deinit {
            if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        }
    }

    /// Calls `handler` on the main thread with the freshly read `current` each time the system posts
    /// `accessibilityDisplayOptionsDidChangeNotification`. It does not fire at subscription time.
    @MainActor static func observe(_ handler: @escaping @MainActor (DisplayOptions) -> Void) -> Observation {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: nil) { _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { handler(DisplayOptions.current) }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { handler(DisplayOptions.current) } }
            }
        }
        return Observation(token: token)
    }
}
