// G10: a reusable accessibility walker over a window, view or menu tree. AppKit only, no @main, no #if: list this file among a
// suite's sources and call AccessibilityAudit.audit(...).
//
// What it asserts (each is a `Kind`)
//   missingLabel        an interactive control with no visible title has no AX label (explicit label, title, the image description
//                       AppKit reads from an icon, or the text of its accessibilityTitleUIElement); so does an accessibility-element
//                       CONTAINER that is not a control (a radio group such as GlassChoiceGroup, or a group of choice buttons),
//                       which the native NSSegmentedControl it replaces was judged as
//   missingRole         a control reports no AX role: standard controls get theirs from their cell, a custom control or a custom
//                       focusable view must call setAccessibilityRole itself
//   unlabelledSegment   a segmented control has a segment with neither text nor an image description
//   duplicateLabel      two controls that are on screen together share a label, unless the label is on the allow-list with a reason
//   retiredName         a label, title, help, description or static string contains the retired product name
//   notKeyboardReachable an enabled, visible control cannot take focus (refusesFirstResponder, no first-responder acceptance), unless
//                       an ancestor accepts first responder and owns the keys (a composite widget such as the Settings tab strip);
//                       an editable text input that cannot become a key view
//   undescribedImage    an NSImageView that holds an image has no description and is not marked decorative
//
// Judgement calls, on purpose
//   * Hidden views are walked and must be labelled (a form page that is hidden now is one click from visible) but are left out of
//     the uniqueness check, because VoiceOver never sees two pages at once.
//   * Controls inside a table or collection repeat by nature (two rows can share a name), so they are left out of uniqueness.
//   * `canBecomeKeyView` on a button follows the machine's Full Keyboard Access setting, so buttons are judged by whether they accept
//     first responder at all; only text inputs are held to `canBecomeKeyView`.
//   * A decorative image says so with an accessibilityIdentifier that starts with "decorative" (AppKit cannot tell an image that was
//     told it is not an element from one that never was, so the walker cannot read setAccessibilityElement(false)); an image inside a
//     row, tile or pill that carries its own label is part of that label and needs nothing.
//
// Not covered, by design: what VoiceOver actually speaks (that is the manual pass), text a view draws itself, and system-owned
// surfaces (the title bar, open/save panels, the system menu bar).
import AppKit

@MainActor
enum AccessibilityAudit {
    enum Kind: String {
        case missingLabel, missingRole, unlabelledSegment, duplicateLabel, retiredName, notKeyboardReachable, undescribedImage
    }

    struct Finding: CustomStringConvertible {
        var kind: Kind
        var surface: String
        var path: String
        var label: String
        var hidden: Bool
        var description: String { "\(surface): \(path) \(kind.rawValue) \"\(label.prefix(40))\"\(hidden ? " (hidden)" : "")" }
    }

    struct Report {
        var violations: [Finding] = []
        /// Controls (and images, menu items) the walker judged, so a test can show it really looked.
        var controls = 0
        /// How many of those carried a non-empty label.
        var labelled = 0
        var description: String { violations.map(\.description).joined(separator: "\n") }
        mutating func merge(_ other: Report) { violations += other.violations; controls += other.controls; labelled += other.labelled }
        func count(of kind: Kind) -> Int { violations.filter { $0.kind == kind }.count }
    }

    /// The retired product name, assembled so this file itself does not name it (the string gate scans tests/ too).
    static let retiredName = "Ski" + "tch"

    /// Labels two on-screen controls may share, with the reason. Empty until a surface genuinely needs it.
    static var deliberateDuplicates: [String: String] = [:]

    // MARK: Entry points

    static func audit(_ window: NSWindow, surface: String, allowedDuplicates: [String: String] = [:]) -> Report {
        var run = Run(surface: surface, allowed: allowedDuplicates.merging(deliberateDuplicates) { first, _ in first })
        if let content = window.contentView { run.walk(content, path: "window", hidden: false, repeating: false) }
        for (index, accessory) in window.titlebarAccessoryViewControllers.enumerated() {
            run.walk(accessory.view, path: "titlebarAccessory[\(index)]", hidden: false, repeating: false)
        }
        var report = run.finish()
        if let sheet = window.attachedSheet { report.merge(audit(sheet, surface: surface + " (sheet)", allowedDuplicates: allowedDuplicates)) }
        return report
    }

    static func audit(_ view: NSView, surface: String, allowedDuplicates: [String: String] = [:]) -> Report {
        var run = Run(surface: surface, allowed: allowedDuplicates.merging(deliberateDuplicates) { first, _ in first })
        run.walk(view, path: "view", hidden: view.isHidden, repeating: false)
        return run.finish()
    }

    static func audit(_ menu: NSMenu, surface: String, allowedDuplicates: [String: String] = [:]) -> Report {
        var run = Run(surface: surface, allowed: allowedDuplicates.merging(deliberateDuplicates) { first, _ in first })
        run.walkMenu(menu, path: "menu")
        return run.finish()
    }

    // MARK: What the accessibility layer says about a view

    private static func text(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// The role VoiceOver gets. A standard control reports it through its cell; a custom view must set it.
    static func role(of view: NSView) -> NSAccessibility.Role? {
        if let role = view.accessibilityRole(), role != .unknown { return role }
        if let role = (view as? NSControl)?.cell?.accessibilityRole(), role != .unknown { return role }
        return nil
    }

    /// The label VoiceOver speaks: the explicit one, else the title, else what the cell derives (button title, icon description),
    /// else the text of the element that titles it.
    static func label(of view: NSView) -> String {
        if let explicit = text(view.accessibilityLabel()) { return explicit }
        if let title = text(view.accessibilityTitle()) { return title }
        if let control = view as? NSControl, let derived = text(control.cell?.accessibilityLabel()) { return derived }
        // A popup is an NSButton whose title is its current value, not its name, so it needs a label of its own.
        if let button = view as? NSButton, !(view is NSPopUpButton), button.imagePosition != .imageOnly, let title = text(button.title) { return title }
        switch view.accessibilityTitleUIElement() {
        case let field as NSTextField: if let found = text(field.stringValue) { return found }
        case let other as NSView: if let found = text(other.accessibilityLabel()) { return found }
        default: break
        }
        return ""
    }

    private static func isDecorative(_ view: NSView) -> Bool { view.accessibilityIdentifier().hasPrefix("decorative") }

    // MARK: The walk

    @MainActor
    private struct Run {
        let surface: String
        let allowed: [String: String]
        var report = Report()
        /// Every label that is on screen together, for the uniqueness pass.
        var onScreen: [(label: String, path: String)] = []
        private var seen = Set<ObjectIdentifier>()

        init(surface: String, allowed: [String: String]) { self.surface = surface; self.allowed = allowed }

        mutating func flag(_ kind: Kind, _ path: String, _ label: String, hidden: Bool) {
            report.violations.append(Finding(kind: kind, surface: surface, path: path, label: label, hidden: hidden))
        }

        mutating func finish() -> Report {
            var byLabel: [String: [String]] = [:]
            for entry in onScreen { byLabel[entry.label.lowercased(), default: []].append(entry.path) }
            for (label, paths) in byLabel.sorted(by: { $0.key < $1.key }) where paths.count > 1 && allowed.keys.contains(where: { $0.lowercased() == label }) == false {
                for path in paths { flag(.duplicateLabel, path, label, hidden: false) }
            }
            return report
        }

        private func name(_ view: NSView) -> String {
            let type = String(describing: Swift.type(of: view))
            let id = view.accessibilityIdentifier()
            return id.isEmpty ? type : "\(type)#\(id)"
        }

        /// A string VoiceOver can read must never carry the retired product name. One finding per element, however many strings carry it.
        private mutating func checkRetired(_ strings: [String?], path: String, hidden: Bool) {
            if let hit = strings.compactMap({ $0 }).first(where: { $0.range(of: AccessibilityAudit.retiredName, options: .caseInsensitive) != nil }) {
                flag(.retiredName, path, hit, hidden: hidden)
            }
        }

        private static func isAppKit(_ view: NSView) -> Bool { Bundle(for: Swift.type(of: view)) === Bundle(for: NSView.self) }

        /// An accessibility element that groups choices without being a control or taking focus itself: a radio group (the inline
        /// GlassChoiceGroup), or a group whose accessibility children are choice buttons. VoiceOver announces its label before the choices,
        /// so it needs one, and a role.
        private static func isChoiceContainer(_ view: NSView) -> Bool {
            guard !(view is NSControl), !isAppKit(view), view.isAccessibilityElement() else { return false }
            let role = view.accessibilityRole()
            if role == .radioGroup { return true }
            return role == .group && hasChoiceButton(below: view)
        }

        /// Whether a choice button (radio button, checkbox, button, menu button) is among the descendants, looking through plain layout views.
        private static func hasChoiceButton(below view: NSView) -> Bool {
            let choices: [NSAccessibility.Role] = [.radioButton, .checkBox, .button, .menuButton]
            for sub in view.subviews {
                if let role = sub.accessibilityRole(), choices.contains(role) { return true }   // a button reports element-ness only once hosted
                if hasChoiceButton(below: sub) { return true }
            }
            return false
        }

        /// Standard AppKit furniture that is an NSControl but not an element the audit holds to a label.
        private static func isFurniture(_ view: NSView) -> Bool {
            if view is NSScroller { return true }
            if let field = view as? NSTextField, !field.isEditable { return true }   // static text is content, not a control
            return false
        }

        mutating func walk(_ view: NSView, path parent: String, hidden inheritedHidden: Bool, repeating inheritedRepeating: Bool) {
            guard seen.insert(ObjectIdentifier(view)).inserted else { return }
            let path = parent + ">" + name(view)
            let hidden = inheritedHidden || view.isHidden
            let repeating = inheritedRepeating || view is NSTableView || view is NSCollectionView

            if let field = view as? NSTextField, !field.isEditable {
                checkRetired([field.stringValue, label(of: field)], path: path, hidden: hidden)
            }
            if let image = view as? NSImageView { judgeImage(image, path: path, hidden: hidden) }
            else if let control = view as? NSControl, !Self.isFurniture(control) { judgeControl(control, path: path, hidden: hidden, repeating: repeating) }
            else if !(view is NSControl), !Self.isAppKit(view), view.acceptsFirstResponder, !(view is NSTextView), !(view is NSClipView), !(view is NSScrollView) {
                judgeCustomFocusable(view, path: path, hidden: hidden, repeating: repeating)
            }
            else if Self.isChoiceContainer(view) {
                judgeCustomFocusable(view, path: path, hidden: hidden, repeating: repeating)
            }

            switch view {
            case let tab as NSTabView:
                for (index, item) in tab.tabViewItems.enumerated() {
                    if let content = item.view { walk(content, path: path + ">tab[\(index)]", hidden: hidden || item !== tab.selectedTabViewItem, repeating: repeating) }
                }
                return
            case let table as NSTableView:
                for row in 0..<table.numberOfRows {
                    for column in 0..<table.numberOfColumns {
                        if let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) {
                            walk(cell, path: path + ">cell[\(row),\(column)]", hidden: hidden, repeating: true)
                        }
                    }
                }
            case let collection as NSCollectionView:
                for item in collection.visibleItems() { walk(item.view, path: path + ">item", hidden: hidden, repeating: true) }
            default: break
            }
            // The internals of a text field, popup or segmented control are system-owned.
            if view is NSTextField || view is NSPopUpButton || view is NSSegmentedControl { return }
            for sub in view.subviews { walk(sub, path: path, hidden: hidden, repeating: repeating) }
        }

        private mutating func judgeControl(_ control: NSControl, path: String, hidden: Bool, repeating: Bool) {
            report.controls += 1
            let text = AccessibilityAudit.label(of: control)
            if text.isEmpty { flag(.missingLabel, path, "", hidden: hidden) } else { report.labelled += 1 }
            if AccessibilityAudit.role(of: control) == nil { flag(.missingRole, path, text, hidden: hidden) }
            if let segmented = control as? NSSegmentedControl {
                for index in 0..<segmented.segmentCount {
                    let segmentLabel = AccessibilityAudit.text(segmented.label(forSegment: index))
                    let described = AccessibilityAudit.text(segmented.image(forSegment: index)?.accessibilityDescription)
                    if segmentLabel == nil, described == nil { flag(.unlabelledSegment, path + ">segment[\(index)]", text, hidden: hidden) }
                    checkRetired([segmentLabel, described], path: path + ">segment[\(index)]", hidden: hidden)
                }
            }
            checkRetired([text, control.accessibilityHelp(), (control as? NSButton)?.title, control.toolTip], path: path, hidden: hidden)
            if !hidden, !repeating, !text.isEmpty { onScreen.append((text, path)) }

            // Keyboard: an enabled, visible control must be operable without the pointer.
            guard control.isEnabled, !hidden else { return }
            let editableInput = (control as? NSTextField)?.isEditable == true
            // A view outside any window is never a key view, so this check needs the control to be hosted.
            if editableInput, control.window != nil, !control.canBecomeKeyView { flag(.notKeyboardReachable, path + " (text input is not a key view)", text, hidden: hidden) }
            if !control.acceptsFirstResponder || control.refusesFirstResponder, !ownedByFocusableAncestor(control) {
                flag(.notKeyboardReachable, path, text, hidden: hidden)
            }
        }

        private mutating func judgeCustomFocusable(_ view: NSView, path: String, hidden: Bool, repeating: Bool) {
            report.controls += 1
            let text = AccessibilityAudit.label(of: view)
            if text.isEmpty { flag(.missingLabel, path, "", hidden: hidden) } else { report.labelled += 1 }
            if AccessibilityAudit.role(of: view) == nil { flag(.missingRole, path, text, hidden: hidden) }
            checkRetired([text, view.accessibilityHelp()], path: path, hidden: hidden)
            if !hidden, !repeating, !text.isEmpty { onScreen.append((text, path)) }
        }

        private mutating func judgeImage(_ imageView: NSImageView, path: String, hidden: Bool) {
            guard imageView.image != nil, !AccessibilityAudit.isDecorative(imageView), !ownedByLabelledAncestor(imageView) else { return }
            report.controls += 1
            let described = AccessibilityAudit.text(imageView.accessibilityLabel()) ?? AccessibilityAudit.text(imageView.image?.accessibilityDescription)
            if let described { report.labelled += 1; checkRetired([described], path: path, hidden: hidden) }
            else { flag(.undescribedImage, path, "", hidden: hidden) }
        }

        /// A glyph or thumbnail inside a row, tile or pill that carries its own label is part of that label (the Default pill's check).
        private func ownedByLabelledAncestor(_ view: NSView) -> Bool {
            var current = view.superview
            while let ancestor = current {
                if AccessibilityAudit.text(ancestor.accessibilityLabel()) != nil { return true }
                current = ancestor.superview
            }
            return false
        }

        /// A composite widget (the Settings tab strip) owns the keys for the controls drawn inside it.
        private func ownedByFocusableAncestor(_ view: NSView) -> Bool {
            var current = view.superview
            while let ancestor = current {
                if ancestor.acceptsFirstResponder, !(ancestor is NSScrollView), !(ancestor is NSClipView) { return true }
                current = ancestor.superview
            }
            return false
        }

        // MARK: Menus

        mutating func walkMenu(_ menu: NSMenu, path parent: String) {
            guard seen.insert(ObjectIdentifier(menu)).inserted else { return }
            var titles: [(label: String, path: String)] = []
            for (index, item) in menu.items.enumerated() where !item.isSeparatorItem {
                let path = "\(parent)>item[\(index)]"
                if let custom = item.view { walk(custom, path: path, hidden: item.isHidden, repeating: false); continue }
                report.controls += 1
                let text = AccessibilityAudit.text(item.title) ?? AccessibilityAudit.text(item.accessibilityLabel()) ?? ""
                if text.isEmpty { flag(.missingLabel, path, "", hidden: item.isHidden) } else { report.labelled += 1 }
                checkRetired([item.title, item.accessibilityLabel(), item.toolTip], path: path, hidden: item.isHidden)
                if !item.isHidden, !text.isEmpty { titles.append((text, path)) }
                if let submenu = item.submenu { walkMenu(submenu, path: path + ">submenu") }
            }
            // Two items in one menu level with the same title are indistinguishable by ear.
            var byTitle: [String: [String]] = [:]
            for entry in titles { byTitle[entry.label.lowercased(), default: []].append(entry.path) }
            for (title, paths) in byTitle.sorted(by: { $0.key < $1.key }) where paths.count > 1 && allowed.keys.contains(where: { $0.lowercased() == title }) == false {
                for path in paths { flag(.duplicateLabel, path, title, hidden: false) }
            }
        }
    }
}
