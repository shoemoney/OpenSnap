// The app-owned About window and its license window. Windows are built but never ordered on screen; no network, no desktop input.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D ABOUT_WINDOW_TESTS \
//   Sources/DesignTokens.swift Sources/AboutWindow.swift tests/AboutWindowTests.swift -o build/about-window-tests
#if ABOUT_WINDOW_TESTS
import AppKit

@main
@MainActor
private enum AboutWindowTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    private static let info: [String: Any] = ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "45"]
    private static let sampleLicense = "MIT License\n\nPermission is hereby granted, free of charge."

    static func main() {
        _ = NSApplication.shared
        strings()
        fonts()
        dismissal()
        licenseWindow()
        noNetwork()
        print("AboutWindowTests: \(checks) checks passed (windows never ordered on screen)")
    }

    private static func make(license: @escaping @MainActor () -> String = { sampleLicense }) -> AboutWindow {
        AboutWindow(icon: NSImage(size: NSSize(width: 64, height: 64)), info: info, licenseText: license)
    }

    private static func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }

    private static func event(_ type: NSEvent.EventType, keyCode: UInt16, characters: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    /// How many times `window` announced it was closing while `body` ran.
    private static func closings(of window: NSWindow, during body: () -> Void) -> Int {
        var count = 0
        let token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { _ in count += 1 }
        body()
        NotificationCenter.default.removeObserver(token)
        return count
    }

    private static func strings() {
        let about = make()
        expect(about.nameLabel.stringValue == "OpenSnap" && about.nameLabel.stringValue == DesignTokens.Brand.name, "The name is the brand constant")
        expect(about.versionLabel.stringValue == "Version 1.2.3 (build 45)", "Version and build come from the Info.plist values: \(about.versionLabel.stringValue)")
        expect(about.creditLabel.stringValue == "Capture, annotate, share.", "The credit line")
        expect(about.licenseButton.attributedTitle.string == "MIT License", "The license link reads MIT License")
        expect(about.title == "About OpenSnap", "The window title for accessibility is About OpenSnap")
        expect(AboutWindow.versionLine(["CFBundleShortVersionString": "0.4.0"]) == "Version 0.4.0", "No build number: version only")
        expect(AboutWindow.versionLine(nil) == "Development build", "No bundle information (a bare binary) says so instead of inventing a number")
        let everything = ([about.title] + allViews(about.contentView!).compactMap { ($0 as? NSTextField)?.stringValue } +
                          allViews(about.contentView!).compactMap { ($0 as? NSButton)?.attributedTitle.string }).joined(separator: "|")
        expect(!everything.lowercased().contains(["ski", "tch"].joined()), "No retired name anywhere in the About window: \(everything)")
    }

    private static func fonts() {
        let about = make()
        expect(about.nameLabel.font?.pointSize == DesignTokens.Typography.font(.title).pointSize, "The name uses the title style")
        for label in [about.versionLabel, about.creditLabel] {
            expect(label.font?.pointSize == 20, "\(label.stringValue) is body size (20 pt)")
        }
        let button = about.licenseButton.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        expect(button?.pointSize == 20, "The license link is body size")
        expect(about.licenseButton.font?.pointSize == 20, "The button's own font is body size too")
        for view in allViews(about.contentView!) {
            // A button draws through a private label that only takes the button's font at draw time; the button itself is checked above.
            if let field = view as? NSTextField, !(field.superview is NSButton) { expect((field.font?.pointSize ?? 0) >= 18, "\(field.stringValue) is at least 18 pt") }
        }
        let license = about.makeLicenseWindow()
        expect(license.textView.font?.pointSize == 20, "The license text is body size")
    }

    private static func dismissal() {
        let escape = event(.keyDown, keyCode: 53, characters: "\u{1B}")
        expect(closings(of: make(), during: {}) == 0, "A window does not close by itself")
        let viaEvent = make()
        expect(closings(of: viaEvent, during: { viaEvent.sendEvent(escape) }) == 1, "Escape closes the About window")
        let viaAction = make()
        expect(closings(of: viaAction, during: { viaAction.cancelOperation(nil) }) == 1, "cancelOperation closes it")
        let command = make()
        let cmdW = event(.keyDown, keyCode: 13, characters: "w", flags: .command)
        var handled = false
        expect(closings(of: command, during: { handled = command.performKeyEquivalent(with: cmdW) }) == 1 && handled, "Command-W closes it")
        let other = make()
        let plainW = event(.keyDown, keyCode: 13, characters: "w")
        expect(closings(of: other, during: { _ = other.performKeyEquivalent(with: plainW) }) == 0, "W alone does not")
        let shifted = make()
        expect(closings(of: shifted, during: { _ = shifted.performKeyEquivalent(with: event(.keyDown, keyCode: 13, characters: "w", flags: [.command, .shift])) }) == 0,
               "Shift-Command-W is left to the app")
    }

    private static func licenseWindow() {
        let about = make()
        expect(about.licenseButton.target === about && about.licenseButton.action == #selector(AboutWindow.showLicense), "The link opens the license window")
        let license = about.makeLicenseWindow()
        expect(license.textView.string == sampleLicense && !license.textView.isEditable, "The license window shows the supplied text, read-only")
        expect(license.title == "MIT License", "Titled MIT License")
        expect(about.makeLicenseWindow() === license, "A second click reuses the same window")
        expect(closings(of: license, during: { license.sendEvent(event(.keyDown, keyCode: 53, characters: "\u{1B}")) }) == 1, "Escape closes the license window")
        let again = make()
        let child = again.makeLicenseWindow()
        expect(closings(of: child, during: { again.close() }) == 1, "Closing About closes the license window with it")
        expect(AboutWindow.bundledLicenseText() == AboutWindow.missingLicense, "Outside an app bundle the license falls back to a note, not a network fetch")
        expect(!AboutWindow.missingLicense.lowercased().contains(["ski", "tch"].joined()), "The fallback names no retired product")
    }

    /// The About window must work offline: nothing in its source reaches for a URL loader or the browser.
    private static func noNetwork() {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidates = [here, here.deletingLastPathComponent().appendingPathComponent("Sources", isDirectory: true)]
        guard let source = candidates.map({ $0.appendingPathComponent("AboutWindow.swift") }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let text = try? String(contentsOf: source, encoding: .utf8) else { return expect(false, "AboutWindow.swift was not found; the offline check must not skip") }
        for forbidden in ["URLSession", "NSWorkspace", "http://", "https://", "NSURLConnection", "WKWebView", "String(contentsOf: URL(string"] {
            expect(!text.contains(forbidden), "AboutWindow.swift must not contain \(forbidden)")
        }
    }
}
#endif
