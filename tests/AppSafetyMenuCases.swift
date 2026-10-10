// Menu identity, Toolbox parity, symbols, app-owned menu text size and the status-item menu (OSN-031, OSN-055).
// The menu-bar strip itself is the only menu not walked: its title size belongs to the system.
// Run through tools/test-app-safety.sh; no status item or window is ever put on screen.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var menuCases: [(String, () throws -> Void)] {
        [
            ("App, File and Text menus use the OpenSnap wording", menuWording),
            ("No menu, Toolbox or status string uses three ASCII dots or the retired name", menuStringHygiene),
            ("Toolbox rows are copies of main-menu rows: subset by action, same titles", menuToolboxParity),
            ("Every menu and Toolbox row has an SF symbol or a named exemption, and no exemption is stale", menuSymbolCoverage),
            ("Every app-owned dropdown renders at body size: main, Toolbox, zoom, upload and status menus", menuDropdownFonts),
            ("The status item opens a menu: Show or Hide, Snap, Settings, Quit", menuStatusItems),
            ("The status menu's first row follows the editor and the app being in front", menuStatusDynamicTitle),
        ]
    }

    private static func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.filter { !$0.isSeparatorItem }.flatMap { [$0] + ($0.submenu.map(menuItems) ?? []) }
    }

    private static func dropdown(_ title: String) throws -> NSMenu {
        try (NSApp.mainMenu?.items.first { $0.submenu?.title == title }?.submenu).unwrap("\(title) menu")
    }

    private static func firstView<T: NSView>(_ type: T.Type, label: String, in root: NSView?) -> T? {
        guard let root else { return nil }
        if let match = root as? T, match.accessibilityLabel() == label { return match }
        for child in root.subviews { if let found = firstView(type, label: label, in: child) { return found } }
        return nil
    }

    private static func toolboxMenu(_ app: AppDelegate) throws -> NSMenu {
        try firstView(NSPopUpButton.self, label: "Toolbox", in: app.window.contentView).unwrap("Toolbox popup").menu.unwrap("Toolbox menu")
    }

    private static func menuWording() throws {
        let fixture = try Fixture(), app = fixture.app
        let name = DesignTokens.Brand.name
        let bar = try NSApp.mainMenu.unwrap("main menu")
        try expect(bar.items.first?.submenu?.title == name && name == "OpenSnap", "The app menu is titled by the brand constant")
        let titles = { (menu: NSMenu) in menu.items.filter { !$0.isSeparatorItem }.map(\.title) }
        let appMenu = try dropdown(name)
        for title in ["About OpenSnap", "Settings…", "Hide OpenSnap", "Quit OpenSnap"] {
            try expect(titles(appMenu).contains(title), "App menu has \(title): \(titles(appMenu))")
        }
        let settings = try appMenu.items.first { $0.title == "Settings…" }.unwrap("Settings…")
        try expect(settings.keyEquivalent == "," && settings.keyEquivalentModifierMask.contains(.command) && settings.action == #selector(AppDelegate.showPreferences),
                   "Settings… is Command-comma and opens Settings")
        try expect(!titles(appMenu).contains("Preferences…"), "No Preferences… row is left behind")
        let file = try dropdown("File")
        for title in ["New", "Open…", "Save", "Save As…", "Rename…", "Export…", "Print…", "Publish…"] {
            try expect(titles(file).contains(title), "File menu has \(title): \(titles(file))")
        }
        let rename = try file.items.first { $0.title == "Rename…" }.unwrap("Rename…")
        try expect(rename.action == #selector(AppDelegate.renameDocument) && app.validateMenuItem(rename), "Rename… is unconditional")
        let text = try dropdown("Text")
        try expect(titles(text).contains("Text Style…") && titles(text).contains("Default Text Style"), "Text menu has Text Style… and Default Text Style: \(titles(text))")
        let style = try text.items.first { $0.title == "Text Style…" }.unwrap("Text Style…")
        _ = app.validateMenuItem(style)
        try expect(style.title == "Text Style…", "Validation never rewrites Text Style… to a Show or Hide wording")
    }

    private static func menuStringHygiene() throws {
        let fixture = try Fixture(), app = fixture.app
        let menus: [(String, NSMenu)] = [("main", try NSApp.mainMenu.unwrap("main")), ("toolbox", try toolboxMenu(app)),
                                         ("zoom", try app.zoomControl.menu.unwrap("zoom")), ("status", app.makeStatusMenu())]
        var strings: [String] = []
        for (_, menu) in menus {
            for item in menuItems(menu) { strings += [item.title, item.toolTip ?? "", item.submenu?.title ?? ""] }
            strings += MenuTypography.menus(under: menu).map(\.title)
        }
        let button = NSButton(title: "", target: nil, action: nil)
        StatusIcon.configure(button)
        strings += [button.toolTip ?? "", button.accessibilityLabel() ?? ""]
        for string in strings {
            try expect(!string.contains("..."), "'\(string)' uses three ASCII dots; use the ellipsis character")
            try expect(!string.lowercased().contains(["ski", "tch"].joined()), "'\(string)' names the retired product")
        }
        try expect(strings.contains("Save As…") && strings.contains("OpenSnap"), "The scan really visited menu and status strings")
    }

    private static func menuToolboxParity() throws {
        let fixture = try Fixture(), app = fixture.app
        let main = menuItems(try NSApp.mainMenu.unwrap("main")).filter { $0.action != nil && $0.submenu == nil }
        // The first row of a pull-down is the button's own title, not a command.
        let toolbox = menuItems(try toolboxMenu(app)).dropFirst().filter { $0.action != nil && $0.submenu == nil }
        try expect(toolbox.count >= 25, "The Toolbox has its rows (\(toolbox.count))")
        for row in toolbox {
            let sameAction = main.filter { $0.action == row.action }
            try expect(!sameAction.isEmpty, "Toolbox row '\(row.title)' has no main-menu row with action \(String(describing: row.action))")
            let match = try sameAction.first { $0.title == row.title }.unwrap("a main-menu row titled '\(row.title)' (the menu says \(sameAction.map(\.title)))")
            try expect(row.keyEquivalent == match.keyEquivalent, "'\(row.title)' key equivalent differs from the menu")
        }
        let drawing = menuItems(try dropdown("Drawing")).map(\.title)
        try expect(drawing.contains("Filled Shapes") && drawing.contains("Shadow"), "Filled Shapes and Shadow live in the Drawing menu, so the Toolbox can mirror them: \(drawing)")
        try expect(toolbox.contains { $0.action == #selector(AppDelegate.toggleBezelFill(_:)) } && toolbox.contains { $0.action == #selector(AppDelegate.chooseFont) },
                   "The Toolbox still offers Filled Shapes and Text Style…")
    }

    /// Rows that deliberately carry no symbol, each with the reason. A row appearing here that has a symbol (or no longer exists) fails the test.
    private static let symbolExemptions: [String: String] = [
        "showGuessPanel:": "system spelling row", "checkSpelling:": "system spelling row", "toggleContinuousSpellChecking:": "system spelling row",
        "toggleBezelFill:": "checkmark row: a symbol would sit beside the check", "toggleBezelShadow:": "checkmark row",
        "changeSmoothing:": "radio row with a checkmark", "changeArrowHead:": "radio row with a checkmark",
    ]

    private static func menuSymbolCoverage() throws {
        let fixture = try Fixture(), app = fixture.app
        let rows = (menuItems(try NSApp.mainMenu.unwrap("main")) + menuItems(try toolboxMenu(app)).dropFirst() + menuItems(app.makeStatusMenu())).filter { $0.submenu == nil }
        var missing: [String] = [], exempted = Set<String>()
        for row in rows {
            guard let action = row.action else { continue }
            if row.image != nil { continue }
            let name = NSStringFromSelector(action)
            if symbolExemptions[name] != nil { exempted.insert(name) } else { missing.append("\(row.title) [\(name)]") }
        }
        try expect(missing.isEmpty, "Rows with neither an SF symbol nor an exemption: \(missing)")
        try expect(exempted == Set(symbolExemptions.keys), "Stale exemptions (the row has a symbol or is gone): \(Set(symbolExemptions.keys).subtracting(exempted))")
    }

    private static func menuDropdownFonts() throws {
        let fixture = try Fixture(), app = fixture.app
        let bar = try NSApp.mainMenu.unwrap("main")
        // The strip of menu-bar titles is skipped: it is system-owned. Every dropdown below it is walked.
        for top in bar.items {
            let submenu = try top.submenu.unwrap("dropdown under \(top.title)")
            try expect(MenuTypography.menus(under: submenu).allSatisfy { $0.font.pointSize >= 20 }, "\(submenu.title) and its submenus render at 20 pt")
            try expect(MenuTypography.belowReadableMinimum(in: submenu).isEmpty, "\(submenu.title): \(MenuTypography.belowReadableMinimum(in: submenu))")
        }
        let upload = try (app.webpostButton?.menu).unwrap("upload menu")
        app.menuNeedsUpdate(upload)
        let named: [(String, NSMenu)] = [("Toolbox", try toolboxMenu(app)), ("zoom", try app.zoomControl.menu.unwrap("zoom")), ("upload", upload), ("status", app.makeStatusMenu())]
        for (label, menu) in named {
            try expect(MenuTypography.menus(under: menu).allSatisfy { $0.font.pointSize >= 20 }, "\(label) menu and its submenus render at 20 pt")
            try expect(MenuTypography.belowReadableMinimum(in: menu).isEmpty, "\(label): \(MenuTypography.belowReadableMinimum(in: menu))")
        }
        let more = try menuItems(try toolboxMenu(app)).first { $0.title == "More Commands" }.unwrap("More Commands")
        try expect(more.submenu?.font.pointSize == 20, "More Commands is 20 pt")
        // OSN-041: the zoom face is body text now, 20 pt like the menu it opens.
        try expect(app.zoomControl.font?.pointSize == 20 && app.zoomControl.menu?.font.pointSize == 20, "The zoom popup face and its menu are 20 pt body text")
    }

    private static func menuStatusItems() throws {
        let fixture = try Fixture(), app = fixture.app
        let menu = app.makeStatusMenu()
        let rows = menu.items
        try expect(rows.map(\.title) == ["Show OpenSnap", "", "Snap…", "Settings…", "", "Quit OpenSnap"], "Status menu rows: \(rows.map(\.title))")
        try expect(rows.map(\.isSeparatorItem) == [false, true, false, false, true, false], "Separators sit after Show or Hide and before Quit")
        let expected: [Selector?] = [#selector(AppDelegate.statusShowHide), nil, #selector(AppDelegate.screenSnap), #selector(AppDelegate.showPreferences), nil, #selector(AppDelegate.quit)]
        try expect(rows.map(\.action) == expected, "Status menu actions")
        try expect(rows.filter { !$0.isSeparatorItem }.allSatisfy { $0.target === app && $0.image != nil && $0.isEnabled || $0.target === app }, "Rows target the app")
        try expect(rows.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil }, "Every status row has a symbol")
        try expect(app.statusMenu === menu, "The app keeps the menu it installed")
        try expect(menu.font.pointSize == 20, "The status menu uses the 20 pt menu font")
        try expect(menu.title == "OpenSnap", "Titled with the brand")
    }

    private static func menuStatusDynamicTitle() throws {
        let fixture = try Fixture(), app = fixture.app
        let window = try (app.window as? AppSafetyWindow).unwrap("test window")
        let item = try app.makeStatusMenu().items.first.unwrap("first row")
        let wasActive = AppSafetyActivation.isActive
        defer { AppSafetyActivation.isActive = wasActive }

        window.simulatesVisibility = true; window.shown = false; AppSafetyActivation.isActive = true
        _ = app.validateMenuItem(item)
        try expect(item.title == "Show OpenSnap", "A hidden editor offers Show: \(item.title)")
        window.shown = true; AppSafetyActivation.isActive = false
        _ = app.validateMenuItem(item)
        try expect(item.title == "Show OpenSnap", "A visible editor behind other apps still offers Show (it brings the editor forward): \(item.title)")
        AppSafetyActivation.isActive = true
        _ = app.validateMenuItem(item)
        try expect(item.title == "Hide OpenSnap", "A visible, frontmost editor offers Hide: \(item.title)")
        window.minimized = true
        _ = app.validateMenuItem(item)
        try expect(item.title == "Show OpenSnap", "A minimized editor offers Show: \(item.title)")
        window.minimized = false
        _ = app.validateMenuItem(item)
        try expect(item.title == "Hide OpenSnap", "Back to Hide when restored: \(item.title)")

        // The row reaches the existing toggle: choosing Hide hides the editor, choosing Show shows it again.
        app.statusShowHide()
        try expect(!window.isVisible, "Choosing Hide hides the editor")
        _ = app.validateMenuItem(item)
        try expect(item.title == "Show OpenSnap", "After hiding, the row reads Show: \(item.title)")
        app.statusShowHide()
        try expect(window.isVisible, "Choosing Show shows the editor again")
    }
}

private extension Optional {
    func unwrap(_ what: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing " + what) }
        return self
    }
}
#endif
