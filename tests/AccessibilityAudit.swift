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
// Added by OSN-062 WP1a, judged on the tree an external client sees (AXTree, tests/AccessibilityTreeWalk.swift) and rendered as a spoken
// script by tests/SpokenScript.swift. List both files with this one.
//   genericLabel        a label that names the kind of thing instead of the thing: a role word ("button", "image"), a symbol, file or
//                       identifier ("camera.viewfinder", "shot.png", "cloud-arrow-up"), or the class name
//   missingValue        a slider, checkbox, radio button, pop-up, combo box, stepper or progress indicator that reports no value
//                       (an indeterminate spinner opts out with an identifier that starts with "indeterminate")
//   readingOrderMismatch  within one AX parent the children are listed in a different order than the eye reads them (rows from the
//                       top, left to right); a parent opts out with an identifier that starts with "order-free". Hosted surfaces only
//   keyLoopDisagreesWithAXOrder  the key-view loop visits focusable elements in an order that is not the accessibility order
//                       (any rotation of it is fine). Windows only
//   ignoredButFocusable a focusable, enabled, visible view that is not an accessibility element and holds none: VoiceOver cannot land on it
//   duplicateInGroup    the same label twice under one AX parent, even where the window-wide allow-list permits it
// Those six are the "tracked" kinds: findings that existed on today's surfaces when they were introduced are listed, each with its reason,
// in tools/accessibility-baseline.tsv, so the gate fails on a NEW finding and on a stale entry (tools/check-spoken-scripts.py) while the
// pending fixes are burned down. Findings the baseline covers are reported in `Report.baselined`, never in `Report.violations`.
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
        case genericLabel, missingValue, readingOrderMismatch, keyLoopDisagreesWithAXOrder, ignoredButFocusable, duplicateInGroup

        /// The kinds introduced by OSN-062 WP1a, the only ones the baseline file can cover.
        var isTracked: Bool {
            switch self {
            case .genericLabel, .missingValue, .readingOrderMismatch, .keyLoopDisagreesWithAXOrder, .ignoredButFocusable, .duplicateInGroup: return true
            default: return false
            }
        }
    }

    struct Finding: CustomStringConvertible {
        var kind: Kind
        var surface: String
        var path: String
        var label: String
        var hidden: Bool
        /// Why, for the kinds that need more than a path to read (reading order, key loop).
        var detail = ""
        var description: String { "\(surface): \(path) \(kind.rawValue) \"\(label.prefix(40))\"\(hidden ? " (hidden)" : "")\(detail.isEmpty ? "" : " [\(detail)]")" }
    }

    struct Report {
        var violations: [Finding] = []
        /// Tracked findings the baseline file covers ("pending WP3"); they do not fail the audit, and a stale baseline line fails the gate.
        var baselined: [Finding] = []
        /// Controls (and images, menu items) the walker judged, so a test can show it really looked.
        var controls = 0
        /// How many of those carried a non-empty label.
        var labelled = 0
        var description: String { violations.map(\.description).joined(separator: "\n") }
        mutating func merge(_ other: Report) { violations += other.violations; baselined += other.baselined; controls += other.controls; labelled += other.labelled }
        func count(of kind: Kind) -> Int { violations.filter { $0.kind == kind }.count }
        /// Every finding of a tracked kind, covered by the baseline or not.
        var trackedFindings: [Finding] { (violations + baselined).filter { $0.kind.isTracked } }
    }

    /// The retired product name, assembled so this file itself does not name it (the string gate scans tests/ too).
    static let retiredName = "Ski" + "tch"

    /// Labels two on-screen controls may share, with the reason. Empty until a surface genuinely needs it.
    static var deliberateDuplicates: [String: String] = [:]

    // MARK: Entry points

    /// False while a test audits a deliberately broken tree: nothing is then written to the spoken-script folder or the findings dump.
    static var recording = true

    static func audit(_ window: NSWindow, surface: String, allowedDuplicates: [String: String] = [:]) -> Report {
        UserStrings.observe(window, surface: surface)
        var run = Run(surface: surface, allowed: allowedDuplicates.merging(deliberateDuplicates) { first, _ in first })
        if let content = window.contentView { run.walk(content, path: "window", hidden: false, repeating: false) }
        for (index, accessory) in window.titlebarAccessoryViewControllers.enumerated() {
            run.walk(accessory.view, path: "titlebarAccessory[\(index)]", hidden: false, repeating: false)
        }
        var report = run.finish()
        let tree = AXTree.walk(window)
        report.violations += trackedFindings(in: tree, surface: surface, allowed: run.allowed, hosted: true, window: window)
        report = conclude(report, surface: surface, script: SpokenScript.render(tree, surface: surface, suite: suiteName))
        if let sheet = window.attachedSheet { report.merge(audit(sheet, surface: surface + " (sheet)", allowedDuplicates: allowedDuplicates)) }
        return report
    }

    static func audit(_ view: NSView, surface: String, allowedDuplicates: [String: String] = [:]) -> Report {
        UserStrings.observe(view, surface: surface)
        var run = Run(surface: surface, allowed: allowedDuplicates.merging(deliberateDuplicates) { first, _ in first })
        run.walk(view, path: "view", hidden: view.isHidden, repeating: false)
        var report = run.finish()
        let tree = AXTree.walk(view)
        report.violations += trackedFindings(in: tree, surface: surface, allowed: run.allowed, hosted: view.window != nil, window: nil)
        return conclude(report, surface: surface, script: SpokenScript.render(tree, surface: surface, suite: suiteName, windowLine: false))
    }

    static func audit(_ menu: NSMenu, surface: String, allowedDuplicates: [String: String] = [:]) -> Report {
        UserStrings.observe(menu, surface: surface)
        var run = Run(surface: surface, allowed: allowedDuplicates.merging(deliberateDuplicates) { first, _ in first })
        run.walkMenu(menu, path: "menu")
        return conclude(run.finish(), surface: surface, script: SpokenScript.render(menu, surface: surface, suite: suiteName))
    }

    // MARK: Tracked kinds: baseline, observation and the spoken script

    static var suiteName: String { ProcessInfo.processInfo.environment["OPENSNAP_SUITE_NAME"] ?? ProcessInfo.processInfo.processName }

    /// The baseline, as the count of allowed findings per `surface | kind | path | label`. The file is tools/accessibility-baseline.tsv (tab
    /// separated: surface, kind, path, label, reason), found from the working directory unless OPENSNAP_A11Y_BASELINE names another.
    static let baseline: [String: Int] = {
        let path = ProcessInfo.processInfo.environment["OPENSNAP_A11Y_BASELINE"] ?? "tools/accessibility-baseline.tsv"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var counts: [String: Int] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5 else { continue }
            counts[key(surface: fields[0], kind: fields[1], path: fields[2], label: fields[3]), default: 0] += 1
        }
        return counts
    }()

    /// OPENSNAP_A11Y_DISCOVER=1 treats every tracked finding as covered, so a full run can list them all for `check-spoken-scripts.py
    /// --write-baseline`. tools/test.py removes it from the environment: the gate never runs in this mode.
    private static let discovering = ProcessInfo.processInfo.environment["OPENSNAP_A11Y_DISCOVER"] == "1"

    static func key(surface: String, kind: String, path: String, label: String) -> String { [surface, kind, path, label].joined(separator: "\u{1}") }

    /// Every surface audited with recording on, in this process: what the findings dump holds.
    private static var observed: [(surface: String, findings: [Finding])] = []

    /// Sorts the tracked findings into new and baselined, then records the surface (its findings and its script) when recording is on.
    private static func conclude(_ report: Report, surface: String, script: String) -> Report {
        var report = report
        var remaining = baseline
        var fresh: [Finding] = []
        for finding in report.violations {
            guard finding.kind.isTracked else { fresh.append(finding); continue }
            let k = key(surface: finding.surface, kind: finding.kind.rawValue, path: finding.path, label: finding.label)
            if discovering { report.baselined.append(finding) }
            else if let left = remaining[k], left > 0 { remaining[k] = left - 1; report.baselined.append(finding) }
            else { fresh.append(finding) }
        }
        report.violations = fresh
        if recording, let directory = SpokenScript.directory {
            SpokenScript.write(script, surface: surface)
            observed.removeAll { $0.surface == surface }
            observed.append((surface, report.trackedFindings))
            let surfaces = observed.map { entry -> [String: Any] in
                ["surface": entry.surface, "slug": SpokenScript.slug(entry.surface),
                 "findings": entry.findings.map { ["kind": $0.kind.rawValue, "path": $0.path, "label": $0.label] }]
            }
            let folder = directory.appendingPathComponent("_findings", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: ["suite": suiteName, "surfaces": surfaces], options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: folder.appendingPathComponent(suiteName + ".json"))
            }
        }
        return report
    }

    // MARK: The tree an external client sees

    private static let judgedRoles: Set<NSAccessibility.Role> = [.button, .menuButton, .checkBox, .radioButton, .radioGroup, .popUpButton, .comboBox, .slider,
                                                                  .textField, .textArea, .image, .group, .tabGroup, .incrementor, .link]
    private static let valuedRoles: Set<NSAccessibility.Role> = [.slider, .checkBox, .radioButton, .popUpButton, .comboBox, .incrementor, .progressIndicator]
    private static let windowFurniture: Set<NSAccessibility.Subrole> = [.closeButton, .minimizeButton, .zoomButton, .fullScreenButton, .toolbarButton]
    private static let repeatingRoles: Set<NSAccessibility.Role> = [.table, .outline, .list, .row, .cell, .column, .browser]
    private static let controlRoles: Set<NSAccessibility.Role> = [.button, .menuButton, .checkBox, .radioButton, .popUpButton, .comboBox, .slider, .textField, .textArea, .incrementor, .link]

    /// A label that names the kind of thing, or a symbol, file or identifier, instead of the thing.
    static func isGeneric(_ label: String, className: String = "") -> Bool {
        let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let lower = text.lowercased()
        if ["button", "image", "view", "control", "item", "group", "icon", "untitled"].contains(lower) { return true }
        if !className.isEmpty, lower == className.lowercased() { return true }
        let patterns = [#"^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)+$"#,       // camera.viewfinder, shot.png
                        #"^[a-z][a-z0-9]*(-[a-z0-9]+)+$"#,                       // cloud-arrow-up
                        #"^[a-z][a-z0-9]*(_[a-z0-9]+)+$"#,                       // cloud_arrow_up
                        #"^[a-z]+([A-Z][a-z0-9]*)+$"#]                           // cloudArrowUp
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func trackedFindings(in tree: AXTree.Tree, surface: String, allowed: [String: String], hosted: Bool, window: NSWindow?) -> [Finding] {
        var found: [Finding] = []
        func add(_ kind: Kind, _ index: Int, _ label: String, detail: String = "") {
            found.append(Finding(kind: kind, surface: surface, path: tree.path(of: index), label: label, hidden: false, detail: detail))
        }
        for (index, node) in tree.nodes.enumerated() {
            guard let role = node.role else { continue }
            let label = node.label ?? ""
            if let subrole = node.subrole, windowFurniture.contains(subrole) { continue }
            if judgedRoles.contains(role), isGeneric(label, className: String(describing: type(of: node.object))) { add(.genericLabel, index, label) }
            if valuedRoles.contains(role), node.value == nil, !(role == .progressIndicator && node.identifier.hasPrefix("indeterminate")) { add(.missingValue, index, label) }
        }
        // The same label twice under one AX parent. The window-wide pass (duplicateLabel) already names the ones the allow-list does not
        // cover; this one is for the allowed ones, which are only allowed to share a window, not a group.
        var groups: [Int?: [String: [Int]]] = [:]
        for (index, node) in tree.nodes.enumerated() {
            guard let role = node.role, controlRoles.contains(role), let label = node.label, !label.isEmpty, !isRepeating(index, in: tree) else { continue }
            groups[node.reachedFrom, default: [:]][label.lowercased(), default: []].append(index)
        }
        for (_, labels) in groups.sorted(by: { ($0.key ?? -1) < ($1.key ?? -1) }) {
            for (label, indices) in labels.sorted(by: { $0.key < $1.key }) where indices.count > 1 && allowed.keys.contains(where: { $0.lowercased() == label }) {
                for index in indices { add(.duplicateInGroup, index, tree.nodes[index].label ?? label) }
            }
        }
        if hosted {
            for problem in tree.readingOrderProblems() {
                found.append(Finding(kind: .readingOrderMismatch, surface: surface, path: problem.path, label: problem.label, hidden: false, detail: problem.message))
            }
        }
        if let window, let problem = keyLoopProblem(in: tree, window: window) {
            found.append(Finding(kind: .keyLoopDisagreesWithAXOrder, surface: surface, path: "window", label: window.title, hidden: false, detail: problem))
        }
        return found
    }

    private static func isRepeating(_ index: Int, in tree: AXTree.Tree) -> Bool {
        var current = tree.nodes[index].reachedFrom
        while let step = current {
            if let role = tree.nodes[step].role, repeatingRoles.contains(role) { return true }
            current = tree.nodes[step].reachedFrom
        }
        return false
    }

    /// The key-view loop the app built by hand: the `nextKeyView` chain from the initial first responder (else the content view). Not
    /// `nextValidKeyView`, which follows the machine's Full Keyboard Access setting. A window with no explicit chain gets the loop AppKit
    /// derives from geometry, which is the eye's order by construction and is judged by readingOrderMismatch instead.
    private static func keyLoop(of window: NSWindow) -> [NSView] {
        var views: [NSView] = [], seen = Set<ObjectIdentifier>()
        var view: NSView? = window.initialFirstResponder ?? window.contentView
        while let current = view, views.count < 800, seen.insert(ObjectIdentifier(current)).inserted { views.append(current); view = current.nextKeyView }
        return views
    }

    /// Nil when the focusable elements are visited in accessibility order (starting anywhere: the loop is a circle), else the first pair that is not.
    private static func keyLoopProblem(in tree: AXTree.Tree, window: NSWindow) -> String? {
        var visits: [(index: Int, view: NSView)] = []
        for view in keyLoop(of: window) where view.acceptsFirstResponder && (view as? NSControl)?.refusesFirstResponder != true {
            if let index = tree.nodes.firstIndex(where: { $0.hostView === view }) { visits.append((index, view)) }
        }
        guard visits.count > 2 else { return nil }
        var descents: [(from: Int, to: Int)] = []
        for position in visits.indices {
            let next = visits[(position + 1) % visits.count]
            if next.index < visits[position].index { descents.append((visits[position].index, next.index)) }
        }
        guard descents.count > 1, let second = descents.last else { return nil }
        func name(_ index: Int) -> String { "\(tree.nodes[index].role?.rawValue ?? "?") \"\(tree.nodes[index].label ?? "")\"" }
        return "the key loop goes from \(name(second.from)) to \(name(second.to)), against the accessibility order (\(descents.count) turns back)"
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

        /// A standard control is published as its cell, so the cell's element-ness counts for the control.
        private static func isElement(_ view: NSView) -> Bool {
            view.isAccessibilityElement() || (view as? NSControl)?.cell?.isAccessibilityElement() == true
        }

        private static func hasElement(below view: NSView) -> Bool { view.subviews.contains { isElement($0) || hasElement(below: $0) } }

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

            if !hidden, view.window != nil, view.acceptsFirstResponder, (view as? NSControl)?.isEnabled ?? true,
               !(view is NSScrollView), !(view is NSClipView), !(view is NSTextView), !Self.isElement(view), !Self.hasElement(below: view) {
                flag(.ignoredButFocusable, path, AccessibilityAudit.label(of: view), hidden: false)
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
                if !item.isHidden, AccessibilityAudit.isGeneric(text, className: "NSMenuItem") { flag(.genericLabel, path, text, hidden: false) }
                if !item.isHidden, !text.isEmpty { titles.append((text, path)) }
                if let submenu = item.submenu { walkMenu(submenu, path: path + ">submenu") }
            }
            // Two items in one menu level with the same title are indistinguishable by ear.
            var byTitle: [String: [String]] = [:]
            for entry in titles { byTitle[entry.label.lowercased(), default: []].append(entry.path) }
            for (title, paths) in byTitle.sorted(by: { $0.key < $1.key }) where paths.count > 1 {
                let permitted = allowed.keys.contains(where: { $0.lowercased() == title })
                for path in paths { flag(permitted ? .duplicateInGroup : .duplicateLabel, path, title, hidden: false) }
            }
        }
    }
}
