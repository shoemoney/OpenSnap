// Menu identity, Toolbox parity, symbols, app-owned menu text size and the status-item menu (OSN-031, OSN-055).
// The menu-bar strip itself is the only menu not walked: its title size belongs to the system.
// Run through tools/test-app-safety.sh; no status item or window is ever put on screen.
#if APP_SAFETY_TESTS
import AppKit

/// The two pop-ups whose choices are a glass panel: the panel they open, and whether it is open.
@MainActor
protocol AppSafetyPanelOwner: NSPopUpButton { var choicePanel: MenuChoicePanel { get } }
extension AppSafetyPanelOwner { var isOpen: Bool { choicePanel.host.isShown } }
extension ToolboxPopUpButton: AppSafetyPanelOwner {}
extension ZoomPopUpButton: AppSafetyPanelOwner {}

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
            ("The Toolbox opens a glass panel of its five groups: 18 rows with the menu's icons, shortcuts and validation, choosing runs the command, Escape returns the focus", menuToolboxPanel),
            ("Every route to the Toolbox, Zoom and Upload choices opens the glass panel and starts no native menu: click, right-click, Control-click, AX press and Show Menu, the context-menu key, Return, Space, Up and Down", menuNoNativeRoutes),
            ("Focus Toolbar survives a keyboard-opened glass panel: the editor resigning key to it keeps the bars as tab stops, and a window that really takes the keyboard turns them off", menuToolboxPanelKeepsFocusToolbar),
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

    /// Keeps a choice panel off screen: it records the window it would show, treats the panel as holding the keyboard, and has a large screen.
    static func offScreen(_ panel: MenuChoicePanel) {
        panel.host.presenter = { _, _ in }
        panel.host.keyStateProbe = { true }
        panel.host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 2400, height: 1600)
    }

    /// A key-down for the open panel's own window.
    static func panelKey(_ code: UInt16, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    /// A pointer event at the middle of a view, for the handlers a test calls directly.
    static func pointer(_ type: NSEvent.EventType, on view: NSView, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        return NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
                                  context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }

    /// Counts native menu tracking (a dropdown, a pop-up or a context menu). AppKit posts `NSMenu.didBeginTrackingNotification` when a menu
    /// starts tracking and the glass panel never tracks a menu, so a route that fell back to the native rows would be counted here.
    @MainActor
    final class NativeMenuProbe {
        private(set) var began = 0
        private var token: NSObjectProtocol?
        private var timers: [Timer] = []
        init() {
            token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.began += 1 }
            }
        }
        /// A route that wrongly fell back to the native menu would track until someone answers; this lets the run end instead of hanging.
        func guardAgainstHang(_ menu: NSMenu?) {
            let timer = Timer(timeInterval: 0.5, repeats: false) { _ in MainActor.assumeIsolated { menu?.cancelTracking() } }
            for mode in [RunLoop.Mode.common, .eventTracking] { RunLoop.main.add(timer, forMode: mode) }
            timers.append(timer)
        }
        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            for timer in timers { timer.invalidate() }
        }
    }

    private static func menuToolboxPanelKeepsFocusToolbar() throws {
        let saved = KeyboardNavigation.fullKeyboardAccess
        KeyboardNavigation.fullKeyboardAccess = { KeyboardNavigation.toolbarFocusActive }   // the system setting is off; Focus Toolbar still counts
        defer { KeyboardNavigation.fullKeyboardAccess = saved; KeyboardNavigation.toolbarFocusActive = false }
        let fixture = try Fixture(), app = fixture.app
        let toolbox = try toolboxButton(app), panel = toolbox.choicePanel
        offScreen(panel)
        if let window = app.window as? AppSafetyWindow { window.simulatesVisibility = true; window.shown = true }
        app.window.contentView?.layoutSubtreeIfNeeded(); app.window.recalculateKeyViewLoop()
        app.focusToolbar()
        app.window.makeFirstResponder(toolbox)
        try expect(KeyboardNavigation.toolbarFocusActive && app.window.firstResponder === toolbox, "Focus Toolbar is on with the keyboard on the Toolbox")
        toolbox.keyDown(with: panelKey(49, in: app.window))
        try expect(toolbox.isOpen, "Space opens the Toolbox panel")
        // The panel takes the keyboard, so the editor resigns key: the focus has not left the bars.
        app.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: app.window))
        try expect(KeyboardNavigation.toolbarFocusActive, "The editor resigning key to its own open panel keeps Focus Toolbar on")
        panel.host.window.sendEvent(panelKey(53, in: panel.host.window))
        try expect(!toolbox.isOpen && app.window.firstResponder === toolbox, "Escape closes the panel and the Toolbox has the focus again")
        try expect(KeyboardNavigation.toolbarFocusActive && toolbox.canBecomeKeyView && toolbox.nextValidKeyView != nil && toolbox.nextValidKeyView !== app.canvas,
                   "Tab still stops on the bar controls (the Toolbox is followed by \(String(describing: toolbox.nextValidKeyView)))")
        // With no panel open the editor resigning key is the focus genuinely leaving.
        app.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: app.window))
        try expect(!KeyboardNavigation.toolbarFocusActive, "Another window taking the keyboard turns Focus Toolbar off")
        // And the app going to the background turns it off even if a panel were the last thing key.
        KeyboardNavigation.toolbarFocusActive = true
        toolbox.keyDown(with: panelKey(49, in: app.window))
        app.applicationWillResignActive(Notification(name: NSApplication.willResignActiveNotification))
        try expect(!KeyboardNavigation.toolbarFocusActive, "The app resigning active turns Focus Toolbar off")
        panel.host.close()
    }

    private static func toolboxButton(_ app: AppDelegate) throws -> ToolboxPopUpButton {
        try (firstView(NSPopUpButton.self, label: "Toolbox", in: app.window.contentView) as? ToolboxPopUpButton).unwrap("Toolbox button")
    }

    static func toolboxMenu(_ app: AppDelegate) throws -> NSMenu {
        try firstView(NSPopUpButton.self, label: "Toolbox", in: app.window.contentView).unwrap("Toolbox popup").menu.unwrap("Toolbox")
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
        let toolbox = menuItems(try toolboxMenu(app)).filter { $0.action != nil && $0.submenu == nil }
        try expect(toolbox.count == 18, "The Toolbox has its short list of drawing-session rows (\(toolbox.count))")
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
        "changeSmoothing:": "radio row with a checkmark", "changeArrowHead:": "radio row with a checkmark",
    ]

    private static func menuSymbolCoverage() throws {
        let fixture = try Fixture(), app = fixture.app
        let rows = (menuItems(try NSApp.mainMenu.unwrap("main")) + menuItems(try toolboxMenu(app)) + menuItems(app.makeStatusMenu())).filter { $0.submenu == nil }
        var missing: [String] = [], exempted = Set<String>()
        for row in rows {
            guard let action = row.action else { continue }
            if b4RowHasIcon(row) { continue }
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

    private static func menuToolboxPanel() throws {
        let fixture = try Fixture(), app = fixture.app
        let toolbox = try toolboxButton(app), probe = NativeMenuProbe()
        defer { probe.stop() }
        let panel = toolbox.choicePanel
        offScreen(panel)
        toolbox.performClick(nil)
        let menu = try toolbox.menu.unwrap("Toolbox menu")
        let items = menu.items.filter { !$0.isSeparatorItem }
        try expect(toolbox.isOpen && panel.host.plates.count == 5 && panel.rows.count == 18 && items.count == 18,
                   "A click opens five group plates holding 18 rows (\(panel.host.plates.count) plates, \(panel.rows.count) rows)")
        try expect(panel.host.plates.map { $0.arrangedViews.count } == [2, 5, 4, 4, 3], "The plates follow the menu's groups: \(panel.host.plates.map { $0.arrangedViews.count })")
        for (row, item) in zip(panel.rows, items) {
            // The copied item still carries the menu bar's SF Symbol; the glass row is app-owned UI and draws the action's Font Awesome glyph instead.
            var drawsFontAwesome = false
            if case .fontAwesomeFree = row.leadingIconSource { drawsFontAwesome = true }
            if case .fontAwesome = row.leadingIconSource { drawsFontAwesome = true }
            try expect(panel.item(for: row) === item && row.title == item.title && row.shortcutText == MenuShortcut.text(for: item)
                       && row.isEnabled == item.isEnabled, "'\(item.title)' shows the menu item's own title, shortcut and enabled state")
            try expect(item.image != nil && row.leadingImage == nil && row.icon != nil && row.icon == MenuChoiceIcons.icon(for: item) && drawsFontAwesome && row.leadingIconImage !== item.image,
                       "'\(item.title)' draws its Font Awesome glyph (\(row.leadingIconSource)), not the menu item's SF Symbol")
        }
        let toggles: Set<Selector> = [#selector(AppDelegate.toggleBezelFill(_:)), #selector(AppDelegate.toggleBezelShadow(_:)), #selector(AppDelegate.chooseFont)]
        try expect(panel.rows.allSatisfy { row in
            let isToggle = panel.item(for: row)?.action.map(toggles.contains) == true
            return row.kind == (isToggle ? .toggle : .command)
        } && panel.rows.filter { $0.kind == .toggle }.count == 3, "Filled Shapes, Shadow and Text Style are toggles; the other 15 are commands")
        try expect(!app.window.isVisible && probe.began == 0, "Nothing was ordered on screen and no native menu started")
        // Validation: the app's own rule, read again at every open.
        func row(_ action: Selector) throws -> GlassChoiceButton {
            try (panel.rows.first { panel.item(for: $0)?.action == action }).unwrap(NSStringFromSelector(action))
        }
        let fill = #selector(AppDelegate.toggleBezelFill(_:)), save = #selector(AppDelegate.saveHistory)
        let fillItem = try menu.items.first { $0.action == fill }.unwrap("fill item")
        try expect(try row(fill).isEnabled == app.validateMenuItem(fillItem), "Filled Shapes follows validateMenuItem")
        app.canvas.filled = true
        toolbox.performClick(nil); toolbox.performClick(nil)
        try expect(try row(fill).isChosen, "Filled Shapes shows on while the pen fills")
        app.canvas.filled = false
        app.frameCaptureInProgress = true
        toolbox.performClick(nil); toolbox.performClick(nil)
        try expect(Set(panel.rows.filter { !$0.isEnabled }.compactMap { panel.item(for: $0)?.action }).isSuperset(of: [#selector(AppDelegate.toggleBezelFill(_:)), #selector(AppDelegate.toggleBezelShadow(_:))]),
                   "While a Frame capture runs Filled Shapes and Shadow are disabled (a state the screenshot harness can set)")
        app.frameCaptureInProgress = false
        app.terminationStarted = true
        toolbox.performClick(nil); toolbox.performClick(nil)
        let disabled = panel.rows.filter { !$0.isEnabled }.compactMap { panel.item(for: $0)?.action }
        let fillOff = try row(fill)
        try expect(Set(disabled).isSuperset(of: toggles) && !fillOff.isChosen, "While the app is quitting the three toggles are disabled (\(disabled.map(NSStringFromSelector)))")
        try expect(fillOff.acceptsFirstResponder == false, "A disabled row never takes the keyboard")
        app.terminationStarted = false
        toolbox.performClick(nil); toolbox.performClick(nil)
        let fillRow = try row(fill), saveRow = try row(save)
        try expect(fillRow.isEnabled && saveRow.isEnabled, "and enabled again once it is not")
        // Choosing a row closes the panel, then runs the main-menu command.
        try expect(!app.canvas.filled, "Fill starts off")
        try row(fill).performClick(nil)
        try expect(app.canvas.filled && !toolbox.isOpen, "Choosing Filled Shapes closes the panel and turns the pen fill on")
        // Escape returns the focus to the opener; a click on the opener only closes.
        app.canvas.filled = false
        app.window.makeFirstResponder(toolbox)
        toolbox.keyDown(with: try NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49).unwrap("a key"))
        try expect(toolbox.isOpen && panel.focusedRow?.isEnabled == true, "Space opens it with an enabled row focused (\(panel.focusedRow?.title ?? "none"))")
        panel.host.window.sendEvent(panelKey(53, in: panel.host.window))
        try expect(!toolbox.isOpen && app.window.firstResponder === toolbox, "Escape closes it and the Toolbox has the focus again")
        toolbox.performClick(nil)
        let click = pointer(.leftMouseDown, on: toolbox)
        try expect(panel.host.handleMouseDown(in: app.window, at: click.locationInWindow) && !toolbox.isOpen, "A click on the Toolbox while it is open only closes it and is consumed")
        // The recorded request seam still stands in for the panel.
        var requests = 0
        toolbox.popUpHandler = { _, _ in requests += 1 }
        toolbox.performClick(nil)
        try expect(requests == 1 && !toolbox.isOpen && probe.began == 0, "popUpHandler records the open request and shows nothing")
    }

    private static func menuNoNativeRoutes() throws {
        let fixture = try Fixture(), app = fixture.app
        let probe = NativeMenuProbe()
        defer { probe.stop() }
        let toolbox = try toolboxButton(app), zoom = app.zoomControl
        // The two pop-ups: every way AppKit or an assistive tool could show the dropdown opens the panel instead.
        for (name, button) in [("Toolbox", toolbox as any AppSafetyPanelOwner), ("Zoom", zoom as any AppSafetyPanelOwner)] {
            offScreen(button.choicePanel)
            probe.guardAgainstHang(button.menu)
            try expect(button.menu(for: pointer(.rightMouseDown, on: button)) == nil && button.menu(for: pointer(.leftMouseDown, on: button, flags: .control)) == nil && button.menu != nil,
                       "\(name): AppKit finds no contextual menu for a right-click or Control-click")
            let actions = button.accessibilityActionNames()
            try expect(actions.contains(.press) || actions.contains(.showMenu), "\(name) exposes \(actions.map(\.rawValue)) to assistive tools")
            var routes: [(String, Bool, () -> Void)] = [
                ("click", false, { button.mouseDown(with: pointer(.leftMouseDown, on: button)) }),
                ("performClick", true, { button.performClick(nil) }),
                ("right-click", false, { button.rightMouseDown(with: pointer(.rightMouseDown, on: button)) }),
                ("Control-click", false, { button.mouseDown(with: pointer(.leftMouseDown, on: button, flags: .control)) }),
                ("middle click", false, { button.otherMouseDown(with: pointer(.otherMouseDown, on: button)) }),
                ("AXPress", true, { _ = button.accessibilityPerformPress() }),
                ("AXShowMenu", true, { _ = button.accessibilityPerformShowMenu() }),
                ("context-menu key", true, { button.showContextMenuForSelection(nil) }),
            ]
            for (key, code) in [("Return", 36), ("Space", 49), ("Down", 125), ("Up", 126)] as [(String, UInt16)] {
                routes.append((key, true, { button.keyDown(with: panelKey(code, in: app.window)) }))
            }
            for action in actions where ![NSAccessibility.Action.press, .showMenu].contains(action) { routes.append(("action " + action.rawValue, true, { _ = button.accessibilityPerformAction(action) })) }
            for (route, keyboard, run) in routes {
                button.choicePanel.host.close()
                run()
                try expect(button.isOpen, "\(name): \(route) presents the glass panel")
                try expect(keyboard == (button.choicePanel.focusedRow != nil), "\(name): \(route) \(keyboard ? "focuses a row" : "leaves every row unfocused")")
                try expect(probe.began == 0, "\(name): \(route) started no native menu")
            }
            button.choicePanel.host.close()
            button.keyDown(with: panelKey(0, in: app.window))
            try expect(!button.isOpen && probe.began == 0, "\(name): a letter key opens nothing (no type-ahead into a native menu)")
        }
        // The Upload button: right-click, Control-click, AX Show Menu and the context-menu key open the panel; a click uploads.
        let upload = try (app.webpostButton as? OriginalActionButton).unwrap("Upload button")
        app.uploadChoices.panelSetup = offScreen
        probe.guardAgainstHang(upload.menu)
        try expect(upload.menu(for: pointer(.rightMouseDown, on: upload)) == nil && upload.showMenuOnLeftClick == false, "Upload: no contextual menu for AppKit, and a left click is the upload")
        let uploadActions = upload.accessibilityActionNames()
        try expect(uploadActions.contains(.showMenu), "Upload exposes Show Menu (\(uploadActions.map(\.rawValue)))")
        let uploadRoutes: [(String, Bool, () -> Void)] = [
            ("right-click", false, { upload.rightMouseDown(with: pointer(.rightMouseDown, on: upload)); upload.rightMouseUp(with: pointer(.rightMouseUp, on: upload)) }),
            ("Control-click", false, { upload.mouseDown(with: pointer(.leftMouseDown, on: upload, flags: .control)); upload.mouseUp(with: pointer(.leftMouseUp, on: upload, flags: .control)) }),
            ("AXShowMenu", true, { _ = upload.accessibilityPerformShowMenu() }),
            ("context-menu key", true, { upload.showContextMenuForSelection(nil) }),
        ]
        for (route, keyboard, run) in uploadRoutes {
            app.uploadChoices.panel?.host.close()
            run()
            try expect(app.uploadChoices.isOpen, "Upload: \(route) presents the glass panel")
            try expect(keyboard == (app.uploadChoices.panel?.focusedRow != nil), "Upload: \(route) \(keyboard ? "focuses a row" : "leaves every row unfocused")")
            try expect(probe.began == 0, "Upload: \(route) started no native menu")
        }
        app.uploadChoices.panel?.host.close()
        var uploads = 0
        app.publishing.uploader = { _, _, plan, _ in uploads += 1; return plan.publicURL ?? plan.remoteURL }
        upload.performClick(nil)
        try expect(!app.uploadChoices.isOpen && probe.began == 0 && (app.publishing.isBusy || uploads == 1 || app.status.stringValue.hasPrefix("Uploading")), "Upload: a click starts the upload and opens no menu")
        try waitForMain("The upload finishes") { !app.publishing.isBusy }
        try expect(probe.began == 0, "No route started a native menu")
    }
}

private extension Optional {
    func unwrap(_ what: String) throws -> Wrapped {
        guard let self else { throw AppSafetyTests.Failure(description: "Missing " + what) }
        return self
    }
}
#endif
