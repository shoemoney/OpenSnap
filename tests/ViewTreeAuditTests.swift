// G4: the font-floor walker (tests/ViewTreeAudit.swift) must (a) catch a seeded violation on every control class it claims to read
// and (b) find zero violations on the real surfaces whose sources compile in isolation. Windows are built, never ordered on screen.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D VIEW_TREE_AUDIT_TESTS \
//   Sources/DesignTokens.swift Sources/AboutWindow.swift Sources/HistoryBrowser.swift Sources/ResizePresets.swift Sources/ResizePanel.swift \
//   Sources/Publishing.swift Sources/PublishingS3.swift Sources/PublishingDestinations.swift Sources/PublishingDestinationsView.swift \
//   Sources/SVGPath.swift Sources/StrokeFitting.swift Sources/GeneralPreferencesState.swift Sources/TextStyleForm.swift Sources/ExportAccessory.swift \
//   Sources/SettingsWindow.swift Sources/GlobalHotkeys.swift Sources/AppToolTip.swift Sources/DisplayOptions.swift Sources/OriginalCaptureFlash.swift \
//   Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift Sources/FontAwesomeFree.swift \
//   tests/TestDefaults.swift tests/ViewTreeAudit.swift tests/ViewTreeAuditTests.swift -o /tmp/opensnap-view-tree-audit-tests
#if VIEW_TREE_AUDIT_TESTS
import AppKit

/// A shortcut backend that registers nothing, so the Settings window can be built without touching the system.
@MainActor
private final class InertHotkeyBackend: GlobalHotkeyBackend {
    var registeredIDs: Set<UInt32> { [] }
    func installHandler(onEvent: @escaping @MainActor @Sendable (UInt32) -> Void) throws {}
    func systemReservedBindings() throws -> Set<GlobalHotkeyBinding> { [] }
    func register(_ binding: GlobalHotkeyBinding, id: UInt32) throws {}
    func unregister(id: UInt32) throws {}
    func shutdown() throws {}
}

@main
@MainActor
private enum ViewTreeAuditTests {
    typealias Audit = ViewTreeAudit
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        seededViolations()
        cleanTreeIsClean()
        captionRegistry()
        realSurfaces()
        print("ViewTreeAuditTests: \(checks) checks passed (windows never ordered on screen)")
    }

    // MARK: Builders

    private static func font(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size) }

    private static func label(_ text: String, _ size: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: text); field.font = font(size); return field
    }

    private static func button(_ title: String, _ size: CGFloat) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil); button.font = font(size); return button
    }

    private static func host(_ views: NSView...) -> NSView {
        let stack = NSStackView(views: views); stack.orientation = .vertical
        stack.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        return stack
    }

    private static func violations(in view: NSView) -> [Audit.Finding] { Audit.audit(view, surface: "seed").violations }

    /// A single-column table whose only cell holds `size`-point text.
    private final class OneCell: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let size: CGFloat
        init(_ size: CGFloat) { self.size = size }
        func numberOfRows(in tableView: NSTableView) -> Int { 1 }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = NSTableCellView(); let field = NSTextField(labelWithString: "Row text"); field.font = .systemFont(ofSize: size)
            cell.addSubview(field); cell.textField = field; return cell
        }
    }

    // MARK: A. The walker can fail

    private static func seededViolations() {
        // Each case: a tree with exactly one offending element and the role the walker must file it under.
        let cases: [(String, NSView, Audit.Role)] = [
            ("static label at 12 pt", host(label("Hint", 12)), .readable),
            ("static label at 17 pt", host(label("Hint", 17)), .readable),
            ("push button at 18 pt", host(button("Save", 18)), .control),
            ("push button at 12 pt", host(button("Save", 12)), .control),
            ("checkbox at 14 pt", host(NSButton(checkboxWithTitle: "Remember", target: nil, action: nil).with { $0.font = font(14) }), .control),
            ("editable field at 16 pt", host(NSTextField(string: "name").with { $0.font = font(16); $0.isEditable = true }), .control),
            ("empty editable field at 16 pt", host(NSTextField(string: "").with { $0.font = font(16); $0.isEditable = true }), .control),
            ("segmented control at 14 pt", host(NSSegmentedControl(labels: ["PNG", "JPG"], trackingMode: .selectOne, target: nil, action: nil).with { $0.font = font(14) }), .control),
            ("box title at 11 pt", host(NSBox().with { $0.title = "Group"; $0.titleFont = font(11) }), .readable),
        ]
        for (name, view, role) in cases {
            let found = violations(in: view)
            expect(found.count == 1, "\(name): expected exactly one violation, got \(found.count): \(found)")
            expect(found[0].role == role, "\(name): filed as \(found[0].role), expected \(role)")
        }

        // An attributed title or value: only the short run is wrong.
        let spans = NSMutableAttributedString(string: "Big small", attributes: [.font: font(20)])
        spans.addAttribute(.font, value: font(13), range: NSRange(location: 4, length: 5))
        let attributedButton = NSButton(title: "", target: nil, action: nil); attributedButton.attributedTitle = spans
        expect(violations(in: host(attributedButton)).map(\.pointSize) == [13], "an attributed button title is judged span by span")
        let attributedLabel = NSTextField(labelWithAttributedString: spans)
        expect(violations(in: host(attributedLabel)).map(\.pointSize) == [13], "an attributed label is judged span by span")

        // Popup: the face font and every menu item (attributed title, else the menu font), recursively through submenus.
        let popup = NSPopUpButton(frame: .zero, pullsDown: false); popup.font = font(20)
        popup.menu?.font = font(20)
        popup.addItems(withTitles: ["One", "Two"])
        let tiny = NSMenuItem(title: "Three", action: nil, keyEquivalent: "")
        tiny.attributedTitle = NSAttributedString(string: "Three", attributes: [.font: font(12)])
        popup.menu?.addItem(tiny)
        let parent = NSMenuItem(title: "More", action: nil, keyEquivalent: ""); parent.submenu = NSMenu(title: "More"); parent.submenu?.font = font(11)
        parent.submenu?.addItem(withTitle: "Deep", action: nil, keyEquivalent: "")
        popup.menu?.addItem(parent)
        let popupFound = violations(in: host(popup))
        expect(popupFound.count == 2 && popupFound.allSatisfy { $0.path.contains("menu") && $0.role == .control },
               "popup: the attributed 12 pt item and the submenu item at the 11 pt menu font are found: \(popupFound)")
        let smallFace = NSPopUpButton(frame: .zero, pullsDown: false); smallFace.font = font(13); smallFace.menu?.font = font(20); smallFace.addItem(withTitle: "Face")
        expect(violations(in: host(smallFace)).map(\.pointSize) == [13], "popup: a 13 pt face with 20 pt items is one violation")

        // A menu on its own, including a submenu and a custom item view.
        let menu = NSMenu(title: "Root"); menu.font = font(20)
        menu.addItem(withTitle: "Fine", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let sub = NSMenuItem(title: "Sub", action: nil, keyEquivalent: ""); sub.submenu = NSMenu(title: "Sub"); sub.submenu?.font = font(12)
        sub.submenu?.addItem(withTitle: "Small", action: nil, keyEquivalent: "")
        menu.addItem(sub)
        let custom = NSMenuItem(); custom.view = label("Custom view", 12); menu.addItem(custom)
        let menuFound = Audit.audit(menu, surface: "menu").violations
        expect(menuFound.count == 2, "menu: the submenu item and the custom item view are both found, nothing else: \(menuFound)")

        // Text view: one run, and the typing attributes of an editable one.
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100)); text.isEditable = false
        text.textStorage?.setAttributedString(NSAttributedString(string: "Body", attributes: [.font: font(20)]))
        text.textStorage?.append(NSAttributedString(string: " fine print", attributes: [.font: font(10)]))
        expect(violations(in: host(text)).map(\.pointSize) == [10], "text view: only the 10 pt run is a violation")
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100)); editor.isEditable = true
        editor.typingAttributes = [.font: font(14)]
        expect(violations(in: host(editor)).contains { $0.pointSize == 14 && $0.role == .control }, "text view: an editable one is judged by its typing attributes as a control")

        // Table: header cell and the made cell view.
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")); column.title = "Name"; column.headerCell.font = font(12)
        table.addTableColumn(column)
        let source = OneCell(11); table.dataSource = source; table.delegate = source; table.reloadData()
        let tableFound = violations(in: host(table))
        expect(tableFound.map(\.pointSize).sorted() == [11, 12], "table: the 12 pt header and the 11 pt cell are both found: \(tableFound)")

        // Tab view: a tab that is NOT selected must still be walked, and the tab labels have a font of their own.
        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 300, height: 200)); tabs.font = font(20)
        for (index, size) in [CGFloat(20), 11].enumerated() {
            let item = NSTabViewItem(identifier: index); item.label = "Tab \(index)"; item.view = host(label("Tab text", size)); tabs.addTabViewItem(item)
        }
        tabs.selectTabViewItem(at: 0)
        let tabFound = violations(in: tabs)
        expect(tabFound.count == 1 && tabFound[0].hidden && tabFound[0].path.contains("tab[1]"), "tab view: the unselected tab's 11 pt label is found and marked hidden: \(tabFound)")
        tabs.font = font(14)
        expect(violations(in: tabs).contains { $0.path.contains("tab labels") && $0.pointSize == 14 }, "tab view: the label font is judged")

        // Hidden and nested: still walked.
        let nested = host(host(host(label("Deep", 12).with { $0.isHidden = true })))
        let nestedFound = violations(in: nested)
        expect(nestedFound.count == 1 && nestedFound[0].hidden, "a hidden label three levels down is found and marked hidden")

        // Window level: content view and an attached titlebar accessory.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host(label("Window text", 20))
        let accessory = NSTitlebarAccessoryViewController(); accessory.view = host(label("Accessory", 13)); window.addTitlebarAccessoryViewController(accessory)
        let windowFound = Audit.audit(window, surface: "window").violations
        expect(windowFound.map(\.pointSize) == [13] && windowFound[0].path.contains("titlebarAccessory"), "window: a titlebar accessory is walked: \(windowFound)")

        // Boundaries: exactly at the floor is fine, one point below is not, images and empty labels carry no text.
        expect(violations(in: host(label("x", 18))).isEmpty, "a static label at exactly 18 pt passes")
        expect(violations(in: host(label("x", 17.9))).count == 1, "a static label at 17.9 pt fails")
        expect(violations(in: host(button("x", 20))).isEmpty, "a control at exactly 20 pt passes")
        expect(violations(in: host(button("x", 19.9))).count == 1, "a control at 19.9 pt fails")
        let iconOnly = NSButton(title: "", target: nil, action: nil); iconOnly.font = font(9)
        expect(violations(in: host(iconOnly, label("", 9))).isEmpty, "an icon-only button and an empty static label draw no text and are skipped")
    }

    // MARK: B. Nothing false

    private static func cleanTreeIsClean() {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false); DesignTokens.Typography.apply(.body, to: popup); popup.addItems(withTitles: ["A", "B"])
        let segmented = NSSegmentedControl(labels: ["PNG", "JPG"], trackingMode: .selectOne, target: nil, action: nil); segmented.font = font(20)
        let tree = host(label("Title", DesignTokens.Typography.font(.title).pointSize), label("Caption", 18), button("Save", 20), popup, segmented)
        let report = Audit.audit(tree, surface: "clean")
        expect(report.violations.isEmpty, "a clean tree has no violations: \(report.violations)")
        expect(report.findings.count >= 6, "the walker did look at the clean tree (\(report.findings.count) findings)")
        expect(report.smallest == 18, "the smallest text in the clean tree is the 18 pt caption")
    }

    private static func captionRegistry() {
        Audit.resetCaptions()
        let status = button("Unsaved changes", 18)
        let tree = host(status)
        expect(Audit.audit(tree, surface: "caption").violations.count == 1, "an unregistered 18 pt control is a violation")
        Audit.registerCaption(status)
        expect(Audit.audit(tree, surface: "caption").violations.isEmpty, "the same control registered as a caption passes at 18 pt")
        status.font = font(17)
        expect(Audit.audit(tree, surface: "caption").violations.count == 1, "a registered caption is still held to 18 pt")
        Audit.resetCaptions()
        let tagged = button("Tagged", 18); tagged.setAccessibilityIdentifier("caption.status")
        Audit.registerCaption(identifier: "caption.status")
        expect(Audit.audit(host(tagged), surface: "caption").violations.isEmpty, "registering by accessibilityIdentifier works")
        Audit.resetCaptions()
        expect(Audit.audit(host(tagged), surface: "caption").violations.count == 1, "resetCaptions removes the registration")
    }

    // MARK: C. The real surfaces

    private static func realSurfaces() {
        var reports: [(String, Audit.Report)] = []
        func record(_ surface: String, _ report: Audit.Report) { reports.append((surface, report)) }

        // About and its licence window.
        let about = AboutWindow(icon: NSImage(size: NSSize(width: 64, height: 64)),
                                info: ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "45"], licenseText: { "MIT License\n\nPermission is hereby granted." })
        record("About", Audit.audit(about, surface: "About"))
        let license = about.makeLicenseWindow()
        record("License", Audit.audit(license, surface: "License"))

        // History: empty state, then populated and filtered.
        let suite = "OpenSnapViewTreeAudit." + UUID().uuidString
        let defaults = TestDefaults(name: suite)
        defer { TestDefaults.dispose(defaults, name: suite) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let history = HistoryBrowser(defaults: defaults, calendar: calendar, now: { now })
        defer { history.close() }
        history.saveShortcut = { "\u{2318}S" }
        record("History (empty)", Audit.audit(history.window!, surface: "History (empty)"))
        var items: [HistoryBrowser.Item] = []
        for index in 0..<4 {
            let shared = index % 2 == 1
            let date = now.addingTimeInterval(TimeInterval(-index * 90_000))
            let link: URL? = shared ? URL(string: "https://example.invalid/shot") : nil
            items.append(HistoryBrowser.Item(id: UUID(), name: "Shot \(index)", date: date, size: CGSize(width: 640, height: 480),
                                             action: shared ? "Shared" : "Saved", text: "note", destination: nil,
                                             link: link, previewURL: nil, missing: index == 3))
        }
        history.update(items: items)
        history.window!.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: false)
        history.window!.contentView?.layoutSubtreeIfNeeded()
        record("History (populated)", Audit.audit(history.window!, surface: "History (populated)"))

        // Destinations: list page, the blank form, and the form for every protocol (the Protocol popup swaps rows).
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.invalid/shots"; dav.username = "user"
        var s3 = PublishingSettings(); s3.transport = .s3; s3.endpoint = "https://s3.example.invalid"; s3.s3 = S3Options()
        let first = PublishingDestination(name: "Work", settings: dav), second = PublishingDestination(name: "Backup", settings: s3)
        let destinations = PublishingDestinationsView(list: PublishingDestinationList(defaultID: first.id, destinations: [first, second]))
        destinations.frame = NSRect(x: 0, y: 0, width: PublishingDestinationsView.sheetWidth, height: 600)
        destinations.layoutSubtreeIfNeeded()
        record("Destinations (list)", Audit.audit(destinations, surface: "Destinations (list)"))
        destinations.addTapped()
        for (index, transport) in PublishingProtocol.allCases.enumerated() {
            destinations.protocolPopup.selectItem(at: index)
            _ = destinations.protocolPopup.target?.perform(destinations.protocolPopup.action, with: destinations.protocolPopup)
            destinations.layoutSubtreeIfNeeded()
            record("Destinations (form, \(transport.title))", Audit.audit(destinations, surface: "Destinations (form, \(transport.title))"))
        }

        // Resize or Crop: the sheet the panel attaches to a parent window.
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        parent.isReleasedWhenClosed = false
        let resizeSuite = "OpenSnapViewTreeAudit.resize." + UUID().uuidString
        let resizeDefaults = TestDefaults(name: resizeSuite)
        defer { TestDefaults.dispose(resizeDefaults, name: resizeSuite) }
        let resize = ResizePanel(session: ResizePanelSession(size: CGSize(width: 800, height: 600), onApply: { _, _, _ in }), presets: ResizePresetStore(defaults: resizeDefaults))
        resize.show(attachedTo: parent)
        // The panel is private and an unordered parent may not attach it, so read it back by reflection (test-only).
        let panel = Mirror(reflecting: resize).children.first { $0.label == "panel" }.flatMap { $0.value as? NSPanel }
        expect(panel != nil, "the Resize or Crop panel was built")
        if let panel {
            panel.contentView?.layoutSubtreeIfNeeded()
            record("Resize or Crop", Audit.audit(panel, surface: "Resize or Crop"))
        }
        if let sheet = parent.attachedSheet { parent.endSheet(sheet) }

        // The Settings window, every tab, as the user can reach it: the window walk follows the selected tab, the tab views are walked directly.
        let settingsSuite = "OpenSnapViewTreeAudit.settings." + UUID().uuidString
        let settingsDefaults = TestDefaults(name: settingsSuite)
        defer { TestDefaults.dispose(settingsDefaults, name: settingsSuite) }
        let settings = SettingsWindowController(state: { GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2, includeApp: true, statusMenu: 0, showToolTips: true) },
                                                hotkeys: GlobalHotkeyManager(defaults: settingsDefaults, backend: InertHotkeyBackend()), defaults: settingsDefaults,
                                                destinations: { PublishingDestinationList(defaultID: first.id, destinations: [first, second]) }, manageDestinations: { _ in })
        for (index, item) in settings.tabItems.enumerated() {
            settings.select(index)
            settings.window.contentView?.layoutSubtreeIfNeeded()
            record("Settings: \(item.label)", Audit.audit(settings.window, surface: "Settings: \(item.label)"))
            record("Settings: \(item.label) (tab view)", Audit.audit(item.viewController.view, surface: "Settings: \(item.label) (tab view)"))
        }
        // A seeded 14 pt row label on the real window is caught, so zero above is not the walker looking at nothing.
        settings.select(0)
        func rowLabel(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.stringValue == "Show in:" { return field }
            for child in view.subviews { if let hit = rowLabel(in: child) { return hit } }
            return nil
        }
        let seeded = rowLabel(in: settings.general.view)
        expect(seeded != nil, "the seeded row label exists")
        let seededFont = seeded?.font
        seeded?.font = font(14)
        expect(Audit.audit(settings.window, surface: "Settings (seeded)").violations.count == 1, "Settings: a 14 pt row label is caught on the real window")
        seeded?.font = seededFont
        // The same for a tab label on the strip: 13 pt, what AppKit's own toolbar labels were, is caught on the real window.
        let tabLabel = settings.strip.buttons[1]
        let tabTitle = tabLabel.attributedTitle
        tabLabel.attributedTitle = NSAttributedString(string: tabLabel.title, attributes: [.font: font(13)])
        let tabCaught = Audit.audit(settings.window, surface: "Settings (seeded tab)").violations
        expect(tabCaught.count == 1 && tabCaught[0].pointSize == 13 && tabCaught[0].text == "Drawing", "Settings: a 13 pt tab label is caught on the real window: \(tabCaught)")
        tabLabel.attributedTitle = tabTitle
        let style = TextStyleForm(outlined: nil, shadowed: nil)
        record("Text style", Audit.audit(style, surface: "Text style"))
        let accessory = ExportAccessory(format: "jpeg", originalSize: false, jpegQuality: 0.7)
        accessory.view.layoutSubtreeIfNeeded()
        record("Export accessory", Audit.audit(accessory.view, surface: "Export accessory"))

        // The same walker must fail when a real surface is made worse: shrink one label and one button, expect exactly those.
        about.versionLabel.font = font(12)
        let shrunkAbout = Audit.audit(about, surface: "About (seeded)").violations
        expect(shrunkAbout.count == 1 && shrunkAbout[0].pointSize == 12, "About: a 12 pt version label is caught on the real window: \(shrunkAbout)")
        destinations.doneButton.font = font(14)
        let shrunkDestinations = Audit.audit(destinations, surface: "Destinations (seeded)").violations
        expect(shrunkDestinations.count == 1 && shrunkDestinations[0].role == .control, "Destinations: a 14 pt Done button is caught on the real sheet: \(shrunkDestinations)")

        var total = 0
        for (surface, report) in reports {
            expect(!report.findings.isEmpty, "\(surface): the walker found no text at all, so a zero-violation result would prove nothing")
            expect(report.violations.isEmpty, "\(surface) breaks the type floor:\n\(report.description)")
            total += report.findings.count
            print("  \(surface): \(report.findings.count) text items, smallest \(report.smallest.map { String(format: "%g", $0) } ?? "-") pt, 0 violations")
        }
        print("  \(reports.count) surfaces, \(total) text items judged")
    }
}

private extension NSObject {
    /// Builder helper so a seeded view can be configured inside an expression.
    func with(_ configure: (Self) -> Void) -> Self { configure(self); return self }
}
#endif
