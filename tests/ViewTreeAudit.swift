// G4: a reusable walker that collects every font a view, window or menu tree can draw, and judges it against the type floor.
// AppKit only, no @main, no #if: list this file among a suite's sources and call ViewTreeAudit.audit(...).
//
// The rule (DesignTokens.Typography): readable text is at least 18 pt; a control is at least 20 pt unless it is registered as a
// caption, in which case it is held to 18 pt. Nothing is exempt from 18 pt.
//
// What it reads, per class
//   NSTextField / NSSearchField / NSTokenField  .font and every .font span of attributedStringValue (empty static labels are skipped;
//                                               an editable field counts even when empty, because the user will type into it)
//   NSButton (checkbox, radio, push)            .font and every .font span of attributedTitle / attributedAlternateTitle; imageOnly buttons skipped
//   NSPopUpButton                               the button font, plus every item of its menu (attributed spans, else menu.font)
//   NSSegmentedControl                          .font, when any segment has a label
//   NSTextView                                  .font, every .font span of the text storage, and typingAttributes when editable
//   NSTableView / NSOutlineView                 header cells, and the cell view of every row and column (made if necessary)
//   NSCollectionView                            the view of every visible item (item views are also plain subviews once realised)
//   NSTabView                                   the tab-label font, and the content view of EVERY tab item, selected or not
//   NSBox                                       the title font
//   NSMenu                                      every item, recursively through submenus and custom item views
// It also follows window titlebar accessories and an attached sheet. Hidden views are walked too (a form page that is hidden now is
// one click from visible), and each finding records whether it is hidden.
//
// Not covered, by design: text a view draws itself in draw(_:) (register the strings via `Typography`), and system-owned surfaces
// (the title bar, the Open panel, tooltips, the system menu bar). Those need a hand-written check or the screenshot harness.
import AppKit

@MainActor
enum ViewTreeAudit {
    private typealias Typography = DesignTokens.Typography

    enum Role: String {
        /// Static text: held to the 18 pt readable floor.
        case readable
        /// Anything the user can press, edit or choose: held to 20 pt unless registered as a caption.
        case control
    }

    struct Finding: CustomStringConvertible {
        var surface: String
        var path: String
        var role: Role
        var pointSize: CGFloat
        var text: String
        var hidden: Bool
        var caption: Bool

        var floor: CGFloat { role == .control && !caption ? Typography.readableDefault : Typography.readableMinimum }
        var isViolation: Bool { pointSize < floor }
        var description: String {
            "\(surface): \(path) [\(role.rawValue)\(caption ? ", caption" : "")] \(pointSize) pt < \(floor) pt for \"\(text.prefix(40))\"\(hidden ? " (hidden)" : "")"
        }
    }

    struct Report {
        var findings: [Finding] = []
        var violations: [Finding] { findings.filter(\.isViolation) }
        /// The smallest size seen, so a test can show the walker really looked at text.
        var smallest: CGFloat? { findings.map(\.pointSize).min() }
        var description: String { violations.map(\.description).joined(separator: "\n") }
        mutating func merge(_ other: Report) { findings += other.findings }
    }

    // MARK: Caption registry

    private static var captionViews = Set<ObjectIdentifier>()
    private static var captionIdentifiers = Set<String>()

    /// Marks one control as a caption: it may sit at 18 pt (never below). Registering is explicit so a stray 18 pt control still fails.
    static func registerCaption(_ view: NSView) { captionViews.insert(ObjectIdentifier(view)) }
    /// Marks every view whose accessibilityIdentifier equals `identifier`.
    static func registerCaption(identifier: String) { captionIdentifiers.insert(identifier) }
    static func resetCaptions() { captionViews.removeAll(); captionIdentifiers.removeAll() }
    private static func isCaption(_ view: NSView) -> Bool {
        captionViews.contains(ObjectIdentifier(view)) || captionIdentifiers.contains(view.accessibilityIdentifier())
    }

    // MARK: Entry points

    static func audit(_ window: NSWindow, surface: String) -> Report {
        var report = Report()
        var seen = Set<ObjectIdentifier>()
        if let content = window.contentView { walk(content, surface: surface, path: "window", hidden: false, seen: &seen, into: &report) }
        for (index, accessory) in window.titlebarAccessoryViewControllers.enumerated() {
            walk(accessory.view, surface: surface, path: "titlebarAccessory[\(index)]", hidden: false, seen: &seen, into: &report)
        }
        if let sheet = window.attachedSheet { report.merge(audit(sheet, surface: surface + " (sheet)")) }
        return report
    }

    static func audit(_ view: NSView, surface: String) -> Report {
        var report = Report()
        var seen = Set<ObjectIdentifier>()
        walk(view, surface: surface, path: "view", hidden: false, seen: &seen, into: &report)
        return report
    }

    static func audit(_ menu: NSMenu, surface: String) -> Report {
        var report = Report()
        var seen = Set<ObjectIdentifier>()
        walkMenu(menu, surface: surface, path: "menu", seen: &seen, into: &report)
        return report
    }

    // MARK: Fonts of attributed text

    /// A control with no font set draws in the system control font (13 pt), which is exactly what the floor exists to catch.
    private static func resolved(_ font: NSFont?) -> NSFont { font ?? .systemFont(ofSize: NSFont.systemFontSize) }

    /// The point size of every run of `text`; a run with no .font attribute draws in `fallback`.
    private static func sizes(of text: NSAttributedString, fallback: NSFont?) -> [CGFloat] {
        guard text.length > 0 else { return [] }
        var found: [CGFloat] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let font = (value as? NSFont) ?? fallback { found.append(font.pointSize) }
        }
        return found
    }

    private static func label(_ view: NSView) -> String {
        let name = String(describing: type(of: view))
        let id = view.accessibilityIdentifier()
        return id.isEmpty ? name : "\(name)#\(id)"
    }

    private static func record(_ report: inout Report, surface: String, path: String, role: Role, size: CGFloat, text: String, hidden: Bool, caption: Bool) {
        report.findings.append(Finding(surface: surface, path: path, role: role, pointSize: size, text: text, hidden: hidden, caption: caption))
    }

    // MARK: View walk

    private static func walk(_ view: NSView, surface: String, path parent: String, hidden inheritedHidden: Bool,
                             seen: inout Set<ObjectIdentifier>, into report: inout Report) {
        guard seen.insert(ObjectIdentifier(view)).inserted else { return }
        let path = parent + ">" + label(view)
        let hidden = inheritedHidden || view.isHidden
        let caption = isCaption(view)
        func add(_ role: Role, _ size: CGFloat, _ text: String, _ suffix: String = "") {
            record(&report, surface: surface, path: path + suffix, role: role, size: size, text: text, hidden: hidden, caption: caption)
        }

        switch view {
        case let popup as NSPopUpButton:
            add(.control, resolved(popup.font).pointSize, popup.titleOfSelectedItem ?? "", " (face)")
            if let menu = popup.menu { walkMenu(menu, surface: surface, path: path + ">menu", seen: &seen, into: &report, forcedCaption: caption) }
        case let button as NSButton where button.imagePosition == .imageOnly:
            break  // draws its image only; the title is an accessibility fallback, not drawn text
        case let button as NSButton:
            let fallback = resolved(button.font)
            let title = button.attributedTitle
            let alternate = button.attributedAlternateTitle
            for size in sizes(of: title, fallback: fallback) + sizes(of: alternate, fallback: fallback) { add(.control, size, title.string) }
            if title.length == 0, !button.title.isEmpty { add(.control, fallback.pointSize, button.title) }
        case let segmented as NSSegmentedControl:
            let labelled = (0..<segmented.segmentCount).map { segmented.label(forSegment: $0) ?? "" }.filter { !$0.isEmpty }
            if !labelled.isEmpty { add(.control, resolved(segmented.font).pointSize, labelled.joined(separator: "|")) }
        case let combo as NSComboBox:
            add(.control, resolved(combo.font).pointSize, combo.stringValue)
        case let field as NSTextField:
            // NSBox draws its title through a private text field child; the box case below already judged it.
            if let box = field.superview as? NSBox, box.contentView !== field, field.stringValue == box.title { break }
            let editable = field.isEditable
            let attributed = field.attributedStringValue
            var found = sizes(of: attributed, fallback: resolved(field.font))
            if found.isEmpty, editable { found = [resolved(field.font).pointSize] }
            for size in found { add(editable ? .control : .readable, size, attributed.string) }
        case let textView as NSTextView:
            let role: Role = textView.isEditable ? .control : .readable
            var found = sizes(of: textView.attributedString(), fallback: resolved(textView.font))
            if textView.isEditable {
                if let typing = textView.typingAttributes[.font] as? NSFont { found.append(typing.pointSize) }
                if found.isEmpty { found = [resolved(textView.font).pointSize] }
            }
            for size in found { add(role, size, textView.string) }
        case let box as NSBox where box.boxType != .separator && !box.title.isEmpty:
            add(.readable, box.titleFont.pointSize, box.title)
        case let tab as NSTabView:
            if tab.tabViewItems.contains(where: { !$0.label.isEmpty }) { add(.control, tab.font.pointSize, tab.tabViewItems.map(\.label).joined(separator: "|"), " (tab labels)") }
            for (index, item) in tab.tabViewItems.enumerated() {
                if let content = item.view { walk(content, surface: surface, path: path + ">tab[\(index)]", hidden: hidden || item !== tab.selectedTabViewItem, seen: &seen, into: &report) }
            }
        case let table as NSTableView:
            walkTable(table, surface: surface, path: path, hidden: hidden, seen: &seen, into: &report)
        case let collection as NSCollectionView:
            for item in collection.visibleItems() { walk(item.view, surface: surface, path: path + ">item", hidden: hidden, seen: &seen, into: &report) }
        default:
            break
        }
        // A text field's own subviews are system internals (the search field's magnifier button, the field editor).
        if view is NSTextField { return }
        for sub in view.subviews { walk(sub, surface: surface, path: path, hidden: hidden, seen: &seen, into: &report) }
    }

    private static func walkTable(_ table: NSTableView, surface: String, path: String, hidden: Bool,
                                  seen: inout Set<ObjectIdentifier>, into report: inout Report) {
        let caption = isCaption(table)
        for (index, column) in table.tableColumns.enumerated() where table.headerView != nil {  // no header view, no drawn header text
            let header = column.headerCell
            for size in sizes(of: header.attributedStringValue, fallback: header.font) {
                record(&report, surface: surface, path: path + ">header[\(index)]", role: .readable, size: size, text: header.stringValue, hidden: hidden, caption: caption)
            }
        }
        for row in 0..<table.numberOfRows {
            for column in 0..<table.numberOfColumns {
                if let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) {
                    walk(cell, surface: surface, path: path + ">cell[\(row),\(column)]", hidden: hidden, seen: &seen, into: &report)
                }
            }
        }
    }

    // MARK: Menu walk

    private static func walkMenu(_ menu: NSMenu, surface: String, path parent: String, seen: inout Set<ObjectIdentifier>,
                                 into report: inout Report, forcedCaption: Bool = false) {
        guard seen.insert(ObjectIdentifier(menu)).inserted else { return }
        let fallback = menu.font
        for (index, item) in menu.items.enumerated() where !item.isSeparatorItem {
            let path = "\(parent)>item[\(index)]"
            if let custom = item.view {
                walk(custom, surface: surface, path: path, hidden: item.isHidden, seen: &seen, into: &report)
            } else {
                let title = item.attributedTitle ?? NSAttributedString(string: item.title)
                for size in sizes(of: title, fallback: fallback) {
                    record(&report, surface: surface, path: path, role: .control, size: size, text: title.string, hidden: item.isHidden, caption: forcedCaption)
                }
            }
            if let submenu = item.submenu { walkMenu(submenu, surface: surface, path: path + ">submenu", seen: &seen, into: &report, forcedCaption: forcedCaption) }
        }
    }
}
