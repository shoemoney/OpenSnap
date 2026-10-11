// G3 (dynamic): every string a window, view tree or menu can show the user, collected from the LIVE objects and checked for the retired product name.
// AppKit only, no @main, no #if: list this file (with AppToolTip.swift) among a suite's sources and call UserStrings.observe(...).
//
// What it reads, per class: window titles; NSTextField text, placeholders and attributed text; button titles; pop-up items; segment labels;
// NSTextView text; box titles; tab labels; table cells; menu item titles, attributed titles, tooltips and custom views; and, for EVERY view,
// the tooltip (system and app-owned) and the accessibility label, title, help, value description and placeholder, plus the label and help of
// the non-view accessibility elements a custom view hands out.
//
// Strings are deduplicated by (kind, text), keeping the first surface that showed them, so a whole app-safety run stays small. Set
// OPENSNAP_USER_STRINGS_DIR and call `writeDump(name:)` to leave the collection as JSON for tools/check-user-strings.py.
import AppKit

@MainActor
enum UserStrings {
    struct Entry {
        var surface: String
        var path: String
        var kind: String
        var text: String
    }

    /// The retired product name, case-insensitively, and the old repository name that contains it.
    static let forbidden = try! NSRegularExpression(pattern: "skitch", options: .caseInsensitive)

    private(set) static var entries: [Entry] = []
    private static var known = Set<String>()
    /// Windows and menus already walked in full, so a run that observes every open window each case stays cheap.
    private static var walked = Set<ObjectIdentifier>()

    /// Forgets what one surface contributed (a test's own seeded violation), so it cannot fail the run's final check.
    static func removeSeeded(surface: String) {
        for entry in entries where entry.surface == surface { known.remove(entry.kind + "\u{1}" + entry.text) }
        entries.removeAll { $0.surface == surface }
    }

    static func reset() { entries = []; known = []; walked = [] }

    static func names(_ text: String) -> Bool {
        forbidden.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The collected strings that name the retired product.
    static var hits: [Entry] { entries.filter { names($0.text) } }

    private static func add(_ surface: String, _ path: String, _ kind: String, _ text: String?) {
        guard let text, !text.isEmpty, known.insert(kind + "\u{1}" + text).inserted else { return }
        entries.append(Entry(surface: surface, path: path, kind: kind, text: text))
    }

    // MARK: Entry points

    static func observe(_ window: NSWindow, surface: String) {
        add(surface, "window", "window-title", window.title)
        add(surface, "window", "ax-label", window.accessibilityLabel())
        var seen = Set<ObjectIdentifier>()
        if let content = window.contentView { walk(content, surface: surface, path: "window", seen: &seen) }
        // Only a titled window has a title bar to carry accessories; asking any other style throws.
        for (index, accessory) in (window.styleMask.contains(.titled) ? window.titlebarAccessoryViewControllers : []).enumerated() {
            walk(accessory.view, surface: surface, path: "titlebarAccessory[\(index)]", seen: &seen)
        }
        if let sheet = window.attachedSheet { observe(sheet, surface: surface + " (sheet)") }
    }

    static func observe(_ view: NSView, surface: String) {
        var seen = Set<ObjectIdentifier>()
        walk(view, surface: surface, path: "view", seen: &seen)
    }

    static func observe(_ menu: NSMenu, surface: String) {
        var seen = Set<ObjectIdentifier>()
        walkMenu(menu, surface: surface, path: "menu", seen: &seen)
    }

    /// Every window the application owns now (ordered or not); each is walked once per object.
    static func observeOpenWindows(surface: String) {
        for window in NSApp.windows where walked.insert(ObjectIdentifier(window)).inserted {
            observe(window, surface: "\(surface): \(type(of: window))")
        }
    }

    // MARK: The walk

    private static func walk(_ view: NSView, surface: String, path parent: String, seen: inout Set<ObjectIdentifier>) {
        guard seen.insert(ObjectIdentifier(view)).inserted else { return }
        let path = parent + ">" + String(describing: type(of: view))
        func text(_ kind: String, _ value: String?) { add(surface, path, kind, value) }

        text("tooltip", view.toolTip)
        text("tooltip", AppToolTip.text(for: view))
        text("ax-label", view.accessibilityLabel())
        text("ax-title", view.accessibilityTitle())
        text("ax-help", view.accessibilityHelp())
        text("ax-value-description", view.accessibilityValueDescription())
        text("ax-placeholder", view.accessibilityPlaceholderValue())
        for element in view.accessibilityChildren() ?? [] where !(element is NSView) {
            if let element = element as? NSAccessibilityProtocol {
                text("ax-label", element.accessibilityLabel())
                text("ax-help", element.accessibilityHelp())
            }
        }

        switch view {
        case let popup as NSPopUpButton:
            text("popup-title", popup.titleOfSelectedItem)
            if let menu = popup.menu { walkMenu(menu, surface: surface, path: path + ">menu", seen: &seen) }
        case let button as NSButton:
            text("button-title", button.title)
            text("button-title", button.attributedTitle.string)
            text("button-title", button.alternateTitle)
        case let segmented as NSSegmentedControl:
            for index in 0..<segmented.segmentCount {
                text("segment-label", segmented.label(forSegment: index))
                text("tooltip", segmented.toolTip(forSegment: index))
            }
        case let combo as NSComboBox:
            text("text", combo.stringValue)
            text("placeholder", combo.placeholderString)
        case let field as NSTextField:
            text("text", field.stringValue)
            text("text", field.attributedStringValue.string)
            text("placeholder", field.placeholderString)
            text("placeholder", field.placeholderAttributedString?.string)
        case let textView as NSTextView:
            text("text", textView.string)
        case let box as NSBox:
            text("box-title", box.title)
        case let tab as NSTabView:
            for (index, item) in tab.tabViewItems.enumerated() {
                text("tab-label", item.label)
                text("tooltip", item.toolTip)
                if let content = item.view { walk(content, surface: surface, path: path + ">tab[\(index)]", seen: &seen) }
            }
        case let table as NSTableView:
            for (index, column) in table.tableColumns.enumerated() {
                text("table-header", column.headerCell.stringValue)
                text("tooltip", column.headerToolTip)
                _ = index
            }
            for row in 0..<table.numberOfRows {
                for column in 0..<table.numberOfColumns {
                    if let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) {
                        walk(cell, surface: surface, path: path + ">cell[\(row),\(column)]", seen: &seen)
                    }
                }
            }
        case let collection as NSCollectionView:
            for item in collection.visibleItems() { walk(item.view, surface: surface, path: path + ">item", seen: &seen) }
        default:
            break
        }
        if view is NSTextField { return }
        for sub in view.subviews { walk(sub, surface: surface, path: path, seen: &seen) }
    }

    private static func walkMenu(_ menu: NSMenu, surface: String, path parent: String, seen: inout Set<ObjectIdentifier>) {
        guard seen.insert(ObjectIdentifier(menu)).inserted else { return }
        add(surface, parent, "menu-title", menu.title)
        for (index, item) in menu.items.enumerated() where !item.isSeparatorItem {
            let path = "\(parent)>item[\(index)]"
            add(surface, path, "menu-item", item.title)
            add(surface, path, "menu-item", item.attributedTitle?.string)
            add(surface, path, "tooltip", item.toolTip)
            add(surface, path, "ax-label", item.image?.accessibilityDescription)
            if let custom = item.view { walk(custom, surface: surface, path: path, seen: &seen) }
            if let submenu = item.submenu { walkMenu(submenu, surface: surface, path: path + ">submenu", seen: &seen) }
        }
    }

    // MARK: Hand-off to tools/check-user-strings.py

    /// Writes `<OPENSNAP_USER_STRINGS_DIR>/<name>.json` when that variable is set; returns whether it wrote.
    @discardableResult
    static func writeDump(name: String) -> Bool {
        guard let directory = ProcessInfo.processInfo.environment["OPENSNAP_USER_STRINGS_DIR"], !directory.isEmpty else { return false }
        let records = entries.map { ["surface": $0.surface, "path": $0.path, "kind": $0.kind, "text": $0.text] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["name": name, "strings": records], options: [.sortedKeys, .prettyPrinted]) else { return false }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return (try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".json"))) != nil
    }
}
