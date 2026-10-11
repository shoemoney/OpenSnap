// G3 (dynamic): every string the real main window, the main menu, the Toolbox, the zoom menu and the status item can show names no retired
// product. Whatever else the run opens (every window left open by a case, every alert the app raises) is observed by the harness loop and checked
// once at the end; the strings leave a JSON dump for tools/check-user-strings.py.
// Run through tools/test-app-safety.sh; no window is ever put on screen.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var userStringCases: [(String, () throws -> Void)] {
        [
            ("Dynamic G3: the main window, menus, Toolbox, zoom menu and status item show no string naming the retired product", userStringsMainSurfaces)
        ]
    }

    private static func userStringsMainSurfaces() throws {
        let fixture = try Fixture(), app = fixture.app
        guard let mainMenu = NSApp.mainMenu, let zoomMenu = app.zoomControl.menu else { throw Failure(description: "Missing main or zoom menu") }
        UserStrings.observe(app.window, surface: "main window")
        UserStrings.observe(mainMenu, surface: "main menu")
        UserStrings.observe(try toolboxMenu(app), surface: "Toolbox menu")
        UserStrings.observe(zoomMenu, surface: "zoom menu")
        UserStrings.observe(app.makeStatusMenu(), surface: "status menu")
        let button = NSButton(title: "", target: nil, action: nil)
        StatusIcon.configure(button)
        UserStrings.observe(button, surface: "status item button")
        let strings = UserStrings.entries.map(\.text)
        try expect(strings.contains("Save As…") && strings.contains("OpenSnap"), "The string walk really visited menu and status strings")
        try expect(strings.count > 150, "The string walk visited the real surfaces (\(strings.count) distinct strings)")
        try expect(UserStrings.hits.isEmpty, "A user-visible string names the retired product: \(UserStrings.hits.map { "\($0.surface) \($0.kind) '\($0.text)'" })")
        // The walk can fail: a menu row added by the test is found, then taken away.
        let seeded = NSMenu(title: "seed"); seeded.addItem(withTitle: "Import from " + "Ski" + "tch", action: nil, keyEquivalent: "")
        UserStrings.observe(seeded, surface: "seeded menu")
        try expect(UserStrings.hits.count == 1, "The string walk finds a seeded violation (\(UserStrings.hits.count))")
        UserStrings.removeSeeded(surface: "seeded menu")
        try expect(UserStrings.hits.isEmpty, "The seeded violation is removed again")
    }
}
#endif
