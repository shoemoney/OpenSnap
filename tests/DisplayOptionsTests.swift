// DisplayOptions: precedence, observation, the harness gate and the ChromeAccessibility bridge. No windows, no desktop input,
// and no system setting is ever written. The consumers (countdown, flash, hint bevel) are covered in their own suites.
// rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D DISPLAY_OPTIONS_TESTS \
//   Sources/DisplayOptions.swift Sources/DisplayOptions+ChromeAccessibility.swift Sources/OriginalActionButton.swift \
//   Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift Sources/GlassChrome.swift Sources/DesignTokens.swift \
//   tests/DisplayOptionsTests.swift -o /tmp/opensnap-display-options-tests
#if DISPLAY_OPTIONS_TESTS
import AppKit

@main
@MainActor
private enum DisplayOptionsTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

    private static let rt = DisplayOptions(reduceTransparency: true)
    private static let ic = DisplayOptions(increaseContrast: true)
    private static let rm = DisplayOptions(reduceMotion: true)
    private static let dwc = DisplayOptions(differentiateWithoutColor: true)

    static func main() throws {
        // First: the process-wide default injection is resolved lazily and cached, so prove it ignores a hostile variable
        // before anything else in this process reads DisplayOptions.current.
        try defaultProcessIgnoresTheVariable()
        try value()
        try precedence()
        try observation()
        try harnessGate()
        try bridge()
        print("DisplayOptionsTests: \(checks) checks passed")
    }

    // MARK: a normal launch

    private static func defaultProcessIgnoresTheVariable() throws {
        setenv(DisplayOptions.harnessEnvironmentKey, "reduceMotion,reduceTransparency,increaseContrast,differentiateWithoutColor", 1)
        defer { unsetenv(DisplayOptions.harnessEnvironmentKey) }
        try expect(DisplayOptions.harnessInjection() == nil, "this test process is not a harness copy, so the variable is ignored")
        try expect(DisplayOptions.injection() == nil, "the cached process injection is nil without the gate, even with the variable set")
        try expect(DisplayOptions.current == DisplayOptions.readWorkspace(), "a normal process reads the workspace, never the variable")
    }

    // MARK: the value

    private static func value() throws {
        try expect(DisplayOptions.none == DisplayOptions() && DisplayOptions.none.activeNames.isEmpty, "none has nothing on")
        try expect(DisplayOptions.names == ["reduceTransparency", "increaseContrast", "differentiateWithoutColor", "reduceMotion"], "canonical name order")
        let all = DisplayOptions(reduceMotion: true, reduceTransparency: true, increaseContrast: true, differentiateWithoutColor: true)
        try expect(all.activeNames == DisplayOptions.names, "active names follow the canonical order, not set order")
        try expect(all.stemSuffix == "-rt-ic-dwc-rm" && DisplayOptions.none.stemSuffix == "", "stem suffixes are -rt -ic -dwc -rm in order, empty for none, got \(all.stemSuffix)")
        try expect(rt.stemSuffix == "-rt" && ic.stemSuffix == "-ic" && dwc.stemSuffix == "-dwc" && rm.stemSuffix == "-rm", "one suffix per option")
        try expect(DisplayOptions.parse("increaseContrast,reduceTransparency") == DisplayOptions(reduceTransparency: true, increaseContrast: true), "parse is order independent")
        try expect(DisplayOptions.parse(" reduceMotion , bogus,") == rm, "parse trims, ignores unknown names and empty items")
        try expect(DisplayOptions.parse("") == .none, "parse of nothing is none")
        for name in DisplayOptions.names {
            try expect(DisplayOptions.parse(name).activeNames == [name], "\(name) parses to exactly itself")
            try expect(DisplayOptions.parse(name).isOn(name) && !DisplayOptions.none.isOn(name), "isOn(\(name))")
        }
        try expect(!all.isOn("nonsense"), "an unknown name is never on")
    }

    // MARK: precedence

    private static func precedence() throws {
        let savedOverride = DisplayOptions.override, savedInjection = DisplayOptions.injection, savedReader = DisplayOptions.workspaceReader
        defer { DisplayOptions.override = savedOverride; DisplayOptions.injection = savedInjection; DisplayOptions.workspaceReader = savedReader }
        DisplayOptions.override = nil
        DisplayOptions.injection = { nil }
        DisplayOptions.workspaceReader = { rt }
        try expect(DisplayOptions.current == rt, "with no override and no injection the workspace reader decides")
        DisplayOptions.injection = { ic }
        try expect(DisplayOptions.current == ic, "the harness injection beats the workspace")
        try expect(DisplayOptions.current != rt, "the workspace value is replaced, not merged with the injection")
        DisplayOptions.override = rm
        try expect(DisplayOptions.current == rm, "an override beats the injection and the workspace")
        DisplayOptions.override = DisplayOptions.none
        try expect(DisplayOptions.current == .none, "an override of all-off still wins (it is a value, not a missing value)")
        DisplayOptions.override = nil
        try expect(DisplayOptions.current == ic, "clearing the override falls back to the injection")
        DisplayOptions.injection = { nil }
        try expect(DisplayOptions.current == rt, "clearing the injection falls back to the workspace")
        // The default reader is the live system state, read-only.
        DisplayOptions.workspaceReader = savedReader
        try expect(DisplayOptions.current == DisplayOptions.readWorkspace(.shared), "the default reader is NSWorkspace")
    }

    // MARK: observation

    private static func observation() throws {
        let savedOverride = DisplayOptions.override
        defer { DisplayOptions.override = savedOverride }
        DisplayOptions.override = rt
        var seen: [DisplayOptions] = []
        let observation = DisplayOptions.observe { seen.append($0) }
        try expect(seen.isEmpty, "subscribing does not fire")
        DisplayOptions.override = ic
        post()
        try expect(seen == [ic], "the notification fires the handler with the freshly re-read value, got \(seen)")
        DisplayOptions.override = DisplayOptions(reduceMotion: true, increaseContrast: true)
        post()
        try expect(seen.count == 2 && seen[1] == DisplayOptions(reduceMotion: true, increaseContrast: true), "a second change is re-read again")
        post()
        try expect(seen.count == 3 && seen[2] == seen[1], "an unchanged re-post still fires (the handler decides what changed)")
        observation.invalidate()
        post()
        try expect(seen.count == 3, "an invalidated observation never fires again")
        observation.invalidate()

        var released = 0
        var token: DisplayOptions.Observation? = DisplayOptions.observe { _ in released += 1 }
        post()
        try expect(released == 1, "a live observation fires")
        token = nil
        post()
        try expect(released == 1 && token == nil, "releasing the observation unsubscribes it")

        var other: [DisplayOptions] = []
        let first = DisplayOptions.observe { other.append($0) }
        var second: [DisplayOptions] = []
        let secondToken = DisplayOptions.observe { second.append($0) }
        DisplayOptions.override = dwc
        post()
        try expect(other == [dwc] && second == [dwc], "every observer is told")
        first.invalidate()
        post()
        try expect(other.count == 1 && second.count == 2, "invalidating one observer leaves the others")
        secondToken.invalidate()
    }

    private static func post() {
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    }

    // MARK: the harness gate

    private static func harnessGate() throws {
        let support = NSTemporaryDirectory() + "display-options-tests-\(getpid())"
        try FileManager.default.createDirectory(atPath: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: support) }
        let flagged = ["OpenSnap", "--eye-dump-audit", "/tmp/audit-out"]
        let key = DisplayOptions.harnessEnvironmentKey
        let isolated = ["OPENSNAP_APP_SUPPORT": support, "CFFIXED_USER_HOME": "/tmp/audit-home", key: "reduceTransparency,increaseContrast"]
        let throwaway = HarnessGate.bundlePrefix + "4242"
        func injection(_ arguments: [String] = flagged, _ environment: [String: String] = isolated, _ bundle: String? = throwaway) -> DisplayOptions? {
            DisplayOptions.harnessInjection(arguments: arguments, environment: environment, bundleIdentifier: bundle)
        }

        try expect(injection() == DisplayOptions(reduceTransparency: true, increaseContrast: true), "a fully isolated harness copy honours the variable")
        try expect(injection(flagged, isolated.merging([key: "differentiateWithoutColor"]) { $1 }) == dwc, "any single option")
        try expect(injection(flagged, isolated.merging([key: "reduceMotion,differentiateWithoutColor,reduceTransparency,increaseContrast"]) { $1 })?.activeNames == DisplayOptions.names, "all four")

        try expect(injection(flagged, isolated, "com.shoemoney.opensnap") == nil, "the real bundle id: the variable is ignored")
        try expect(injection(flagged, isolated, "com.shoemoney") == nil, "a bare vendor prefix: ignored")
        try expect(injection(flagged, isolated, "com.example.other") == nil, "any non-harness bundle id: ignored")
        try expect(injection(flagged, isolated, nil) == nil, "a bare binary without a bundle id: ignored")
        try expect(injection(flagged, isolated, String(HarnessGate.bundlePrefix.dropLast()) + "x") == nil, "a near-miss prefix: ignored")
        try expect(injection(["OpenSnap"], isolated) == nil, "no --eye-dump-audit flag: ignored")
        try expect(injection(["OpenSnap", "--eye-dump-audit"], isolated) == nil, "the flag without its output folder: ignored")
        var withoutSupport = isolated; withoutSupport["OPENSNAP_APP_SUPPORT"] = nil
        try expect(injection(flagged, withoutSupport) == nil, "no isolated support folder: ignored")
        try expect(injection(flagged, isolated.merging(["OPENSNAP_APP_SUPPORT": support + "/missing"]) { $1 }) == nil, "a support folder that does not exist: ignored")
        try expect(injection(flagged, isolated.merging(["OPENSNAP_APP_SUPPORT": ""]) { $1 }) == nil, "an empty support folder variable: ignored")
        var withoutHome = isolated; withoutHome["CFFIXED_USER_HOME"] = nil
        try expect(injection(flagged, withoutHome) == nil, "no isolated home: ignored")
        try expect(injection(flagged, isolated.merging(["OPENSNAP_FIXTURE": "/tmp/doc.opensnap"]) { $1 }) == nil, "a document fixture: ignored")
        try expect(injection(flagged, isolated.merging(["OPENSNAP_FIXTURE": ""]) { $1 }) != nil, "an empty fixture variable counts as none")

        var withoutVariable = isolated; withoutVariable[key] = nil
        try expect(injection(flagged, withoutVariable) == nil, "a harness copy launched without --display: no injection (the system state shows)")
        try expect(injection(flagged, isolated.merging([key: ""]) { $1 }) == nil, "an empty variable: no injection")
        try expect(injection(flagged, isolated.merging([key: "bogus"]) { $1 }) == DisplayOptions.none, "only unknown names: an injection of nothing, never the system state by accident")

        // The gate decides exactly what the audit itself requires.
        for bundle in [throwaway, "com.shoemoney.opensnap", nil] as [String?] {
            let audit = HarnessGate.auditDirectory(arguments: flagged, environment: isolated, bundleIdentifier: bundle) != nil
            try expect(audit == (injection(flagged, isolated, bundle) != nil), "the injection and the audit share one gate (bundle \(bundle ?? "nil"))")
        }

        // End to end through `current`: an injection replaces the workspace value entirely.
        let savedOverride = DisplayOptions.override, savedInjection = DisplayOptions.injection, savedReader = DisplayOptions.workspaceReader
        defer { DisplayOptions.override = savedOverride; DisplayOptions.injection = savedInjection; DisplayOptions.workspaceReader = savedReader }
        DisplayOptions.override = nil
        DisplayOptions.workspaceReader = { DisplayOptions(reduceMotion: true, differentiateWithoutColor: true) }
        DisplayOptions.injection = { injection() }
        try expect(DisplayOptions.current == DisplayOptions(reduceTransparency: true, increaseContrast: true), "gated: current is the injected set, not merged with the system")
        DisplayOptions.injection = { injection(flagged, isolated, "com.shoemoney.opensnap") }
        try expect(DisplayOptions.current == DisplayOptions(reduceMotion: true, differentiateWithoutColor: true), "ungated: current is the system state")
    }

    // MARK: the ChromeAccessibility bridge

    private static func bridge() throws {
        try expect(DisplayOptions(ChromeAccessibility.none) == .none && DisplayOptions.none.chrome == ChromeAccessibility.none, "none maps to none both ways")
        for bits in 0..<16 {
            let chrome = ChromeAccessibility(reduceTransparency: bits & 1 != 0, increaseContrast: bits & 2 != 0, reduceMotion: bits & 4 != 0, differentiateWithoutColor: bits & 8 != 0)
            let options = DisplayOptions(chrome)
            try expect(options.reduceTransparency == chrome.reduceTransparency && options.increaseContrast == chrome.increaseContrast && options.reduceMotion == chrome.reduceMotion
                       && options.differentiateWithoutColor == chrome.differentiateWithoutColor, "chrome -> options keeps every field (case \(bits))")
            try expect(options.chrome == chrome, "chrome -> options -> chrome is the identity (case \(bits))")
        }
        let all = DisplayOptions(reduceMotion: true, reduceTransparency: true, increaseContrast: true, differentiateWithoutColor: true)
        try expect(all.chrome == ChromeAccessibility(reduceTransparency: true, increaseContrast: true, reduceMotion: true, differentiateWithoutColor: true), "options -> chrome carries all four options")
        try expect(dwc.chrome == ChromeAccessibility(reduceTransparency: false, increaseContrast: false, reduceMotion: false, differentiateWithoutColor: true), "Differentiate Without Color alone reaches the chrome and nothing else")
        try expect(rt.chrome.reduceTransparency && !rt.chrome.increaseContrast && !rt.chrome.reduceMotion, "reduceTransparency maps to the matching chrome field only")
        try expect(!ic.chrome.reduceTransparency && ic.chrome.increaseContrast && !ic.chrome.reduceMotion, "increaseContrast maps to the matching chrome field only")
        try expect(!rm.chrome.reduceTransparency && !rm.chrome.increaseContrast && rm.chrome.reduceMotion, "reduceMotion maps to the matching chrome field only")
        // Today's live chrome value equals the bridge of the live options when nothing is injected.
        try expect(DisplayOptions.readWorkspace().chrome == ChromeAccessibility.live, "ChromeAccessibility.live and DisplayOptions agree on the system state")
    }
}
#endif
