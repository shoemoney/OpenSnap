// G3 (dynamic) can-fail proof: the string walker (tests/UserStringWalk.swift) must catch the retired product name in every kind of text it claims
// to read, must stay quiet on clean text, and must leave a dump the checker (tools/check-user-strings.py) can read. Windows are built, never shown.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D USER_STRING_WALK_TESTS \
//   Sources/DesignTokens.swift Sources/AppToolTip.swift tests/ContrastProbe.swift tests/UserStringWalk.swift tests/UserStringWalkTests.swift -o /tmp/opensnap-user-string-walk-tests
#if USER_STRING_WALK_TESTS
import AppKit

@main
@MainActor
private enum UserStringWalkTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    /// Built from pieces so this file never spells the retired name itself.
    private static let bad = "Ski" + "tch"

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        everyKindIsCaught()
        cleanTextIsQuiet()
        dumpIsReadable()
        print("UserStringWalkTests: \(checks) checks passed (windows never ordered on screen)")
    }

    private static func collect(_ build: () -> NSView) -> [UserStrings.Entry] {
        UserStrings.reset()
        UserStrings.observe(build(), surface: "seed")
        return UserStrings.hits
    }

    private static func caught(_ kind: String, _ build: () -> NSView) {
        let found = collect(build)
        expect(found.contains { $0.kind == kind }, "a seeded \(kind) naming the retired product is found (found: \(found.map(\.kind)))")
    }

    private static func everyKindIsCaught() {
        caught("text") { NSTextField(labelWithString: "Open \(bad) files") }
        caught("placeholder") { let field = NSTextField(); field.placeholderString = bad; return field }
        caught("button-title") { NSButton(title: bad.uppercased(), target: nil, action: nil) }
        caught("tooltip") { let view = NSView(); view.toolTip = "the \(bad.lowercased()) thing"; return view }
        caught("tooltip") { let view = NSView(); AppToolTip.setText("from \(bad)", for: view); return view }
        caught("ax-label") { let view = NSView(); view.setAccessibilityLabel(bad); return view }
        caught("ax-help") { let view = NSView(); view.setAccessibilityHelp("About \(bad)"); return view }
        caught("ax-title") { let view = NSView(); view.setAccessibilityTitle(bad); return view }
        caught("box-title") { let box = NSBox(); box.title = bad; return box }
        caught("popup-title") { let popup = NSPopUpButton(); popup.addItem(withTitle: bad); return popup }
        caught("menu-item") { let popup = NSPopUpButton(); popup.addItems(withTitles: ["Fine", "Old \(bad)"]); popup.selectItem(at: 0); return popup }
        caught("segment-label") { let control = NSSegmentedControl(labels: ["A", bad], trackingMode: .selectOne, target: nil, action: nil); return control }
        caught("tab-label") {
            let tabs = NSTabView(); let item = NSTabViewItem(); item.label = bad; item.view = NSView(); tabs.addTabViewItem(item); return tabs
        }
        caught("text") { let text = NSTextView(); text.string = "legacy \(bad)"; return text }
        caught("text") { let stack = NSStackView(views: [NSView(), NSTextField(labelWithString: "nested \(bad)")]); return stack }

        UserStrings.reset()
        let menu = NSMenu(title: "m"); let item = NSMenuItem(title: "Import \(bad)", action: nil, keyEquivalent: ""); menu.addItem(item)
        UserStrings.observe(menu, surface: "seed menu")
        expect(UserStrings.hits.contains { $0.kind == "menu-item" }, "a seeded menu row naming the retired product is found")
        UserStrings.reset()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.title = bad
        UserStrings.observe(window, surface: "seed window")
        expect(UserStrings.hits.contains { $0.kind == "window-title" }, "a seeded window title naming the retired product is found")
    }

    private static func cleanTextIsQuiet() {
        let found = collect {
            let stack = NSStackView(views: [NSTextField(labelWithString: "OpenSnap"), NSButton(title: "Save", target: nil, action: nil)])
            stack.toolTip = "Save the picture"
            return stack
        }
        expect(found.isEmpty, "clean text has no hits")
        expect(UserStrings.entries.contains { $0.text == "OpenSnap" } && UserStrings.entries.contains { $0.text == "Save the picture" }, "the walk really visited the strings")
    }

    private static func dumpIsReadable() {
        _ = collect { NSTextField(labelWithString: "OpenSnap") }
        let directory = NSTemporaryDirectory() + "opensnap-user-string-walk-" + UUID().uuidString
        setenv("OPENSNAP_USER_STRINGS_DIR", directory, 1)
        defer { unsetenv("OPENSNAP_USER_STRINGS_DIR"); try? FileManager.default.removeItem(atPath: directory) }
        expect(UserStrings.writeDump(name: "walk"), "the dump was written")
        let data = try? Data(contentsOf: URL(fileURLWithPath: directory + "/walk.json"))
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let strings = json?["strings"] as? [[String: String]]
        expect(strings?.contains { $0["text"] == "OpenSnap" && $0["kind"] == "text" } == true, "the dump lists the walked strings with their kind")
    }
}
#endif
