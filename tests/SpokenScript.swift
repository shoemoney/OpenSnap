// WP1a (OSN-062): what a screen reader would be told, in reading order, as plain text. AppKit only, no @main, no #if: list this file (with
// tests/AccessibilityTreeWalk.swift) among a suite's sources and call SpokenScript.render(...) or SpokenScript.write(...).
//
// The words follow VoiceOver's default verbosity as best it can be known without turning VoiceOver on: name, then value, then role, with
// the hint on a second line. The exact token order is confirmed once against a live pass (WP4) and then frozen; until then a wording-order
// mismatch is a renderer fix and a missing or wrong WORD is an app fix.
//
//   window                 {title}, window
//   button / menu button   {label}, button | {label}, menu button        (+ ", dimmed" when disabled)
//   checkbox               {label}, checked|unchecked|mixed, checkbox
//   radio group            {label}, radio group      then {label}, selected|not selected, radio button, {i} of {n}
//   slider                 {label}, {value}, slider
//   pop-up button          {value}, {label}, pop up button
//   text field             {label}, {value or "empty"}, edit text        (secure: "secure edit text", the value is never printed)
//   tab group              {label}, tab group        then {label}, selected tab|tab, {i} of {n}
//   static text            {text}
//   image                  {label}, image
//   group                  {label}, group
//   menu item              {title}{, shortcut}
//   any element with help  a second line "hint: {help}"
//
// Every line starts with its accessibility depth in brackets and is indented by it, so nesting is visible.
import AppKit

@MainActor
enum SpokenScript {
    /// The surface name as a file name: lower case, letters and digits, single hyphens.
    static func slug(_ surface: String) -> String {
        var out = "", pendingHyphen = false
        for scalar in surface.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII { if pendingHyphen, !out.isEmpty { out += "-" }; pendingHyphen = false; out.unicodeScalars.append(scalar) }
            else { pendingHyphen = true }
        }
        return out.isEmpty ? "surface" : out
    }

    // MARK: Lines

    private static func line(_ depth: Int, _ text: String) -> String { "[\(depth)] " + String(repeating: "  ", count: depth) + text }

    private static func join(_ parts: [String?]) -> String { parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }

    private static func stateWord(_ value: Any?) -> String? {
        guard let number = value as? NSNumber else { return nil }
        switch number.intValue { case 0: return "unchecked"; case 2: return "mixed"; default: return "checked" }
    }

    /// The text of a node's value, as spoken.
    private static func spokenValue(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text.isEmpty ? nil : text
        case let number as NSNumber: return number.stringValue
        case .some(let other): return "\(other)"
        case nil: return nil
        }
    }

    /// The window's own title-bar buttons are named by their subrole, not by a label.
    private static let windowButtons: [NSAccessibility.Subrole: String] = [.closeButton: "close", .minimizeButton: "minimize", .zoomButton: "zoom", .fullScreenButton: "full screen", .toolbarButton: "toolbar"]

    static func lines(for tree: AXTree.Tree) -> [String] {
        var out: [String] = []
        for node in tree.nodes where node.role != .valueIndicator {   // a slider's thumb is part of the slider: VoiceOver says the value once
            let label = node.label ?? ""
            let siblings = tree.nodes.filter { $0.reachedFrom == node.reachedFrom && $0.role == node.role }
            let position = (siblings.firstIndex { $0.object === node.object } ?? 0) + 1
            let parentRole = node.reachedFrom.flatMap { tree.nodes[$0].role }
            var dimmed: String? = node.enabled ? nil : "dimmed"
            let interactive: Set<NSAccessibility.Role> = [.button, .menuButton, .checkBox, .radioButton, .slider, .popUpButton, .comboBox, .textField, .textArea, .incrementor]
            if let role = node.role, !interactive.contains(role) { dimmed = nil }
            var text: String
            if let furniture = node.subrole.flatMap({ windowButtons[$0] }) { out.append(line(node.depth, join([furniture, "button", dimmed]))); continue }
            switch node.role {
            case .button?: text = join([label, "button", dimmed])
            case .menuButton?: text = join([label, "menu button", dimmed])
            case .checkBox?: text = join([label, stateWord(node.value), "checkbox", dimmed])
            case .radioGroup?: text = join([label, "radio group", dimmed])
            case .radioButton? where parentRole == .tabGroup:
                text = join([label, node.selected || node.number == 1 ? "selected tab" : "tab", "\(position) of \(siblings.count)", dimmed])
            case .radioButton?:
                text = join([label, (node.selected || node.number == 1) ? "selected" : "not selected", "radio button", "\(position) of \(siblings.count)", dimmed])
            case .slider?: text = join([label, spokenValue(node.value), "slider", dimmed])
            case .popUpButton?: text = join([spokenValue(node.value), label, "pop up button", dimmed])
            case .comboBox?: text = join([label, spokenValue(node.value), "combo box", dimmed])
            case .textField?, .textArea?:
                let secure = node.subrole == .secureTextField
                let kind = secure ? "secure edit text" : "edit text"
                text = join([label, secure ? nil : (spokenValue(node.value) ?? "empty"), kind, dimmed])
            case .tabGroup?: text = join([label, "tab group"])
            case .staticText?: text = spokenValue(node.value) ?? label
            case .image?: text = join([label, "image"])
            case .group?: text = join([label, "group"])
            case .menuItem?: text = join([label, dimmed])
            case .progressIndicator?: text = join([label, spokenValue(node.value), "progress indicator"])
            case .incrementor?: text = join([label, spokenValue(node.value), "stepper", dimmed])
            default:
                let word = (node.role?.rawValue ?? "unknown").replacingOccurrences(of: "AX", with: "")
                    .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).lowercased()
                text = join([label, spokenValue(node.value), word, dimmed])
            }
            out.append(line(node.depth, text))
            if let help = node.help { out.append(line(node.depth, "  hint: \(help)")) }
        }
        return out
    }

    static func lines(for menu: NSMenu, depth: Int = 0) -> [String] {
        var out: [String] = []
        for item in menu.items where !item.isSeparatorItem && !item.isHidden {
            var shortcut: String?
            if !item.keyEquivalent.isEmpty {
                let flags = item.keyEquivalentModifierMask
                var words: [String] = []
                if flags.contains(.control) { words.append("Control") }
                if flags.contains(.option) { words.append("Option") }
                if flags.contains(.shift) { words.append("Shift") }
                if flags.contains(.command) { words.append("Command") }
                words.append(item.keyEquivalent.uppercased())
                shortcut = words.joined(separator: " ")
            }
            let state = item.state == .on ? "checked" : (item.state == .mixed ? "mixed" : nil)
            out.append(line(depth, join([item.title.isEmpty ? (item.accessibilityLabel() ?? "") : item.title, shortcut, state, item.isEnabled ? nil : "dimmed", item.submenu != nil ? "submenu" : nil])))
            if let help = item.accessibilityHelp() ?? item.toolTip, !help.isEmpty { out.append(line(depth, "  hint: \(help)")) }
            if let submenu = item.submenu { out += lines(for: submenu, depth: depth + 1) }
        }
        return out
    }

    // MARK: Documents

    private static func header(_ surface: String, suite: String, count: Int) -> [String] {
        let sha = ProcessInfo.processInfo.environment["OPENSNAP_BUILD_SHA"] ?? "unknown"
        return ["# \(surface)", "", "- Surface: \(surface)", "- Suite: \(suite)", "- Build: \(sha)", "- Nodes: \(count)", "", "```"]
    }

    /// `windowLine: false` for a script of one view, which has no window of its own to announce.
    static func render(_ tree: AXTree.Tree, surface: String, suite: String, windowLine: Bool = true) -> String {
        var out = header(surface, suite: suite, count: tree.nodes.count)
        if windowLine { out.append(line(0, tree.window.title.isEmpty ? "window" : "\(tree.window.title), window")) }
        out += lines(for: tree)
        out.append("```")
        return out.joined(separator: "\n") + "\n"
    }

    static func render(_ menu: NSMenu, surface: String, suite: String) -> String {
        let body = lines(for: menu)
        return (header(surface, suite: suite, count: body.count) + body + ["```"]).joined(separator: "\n") + "\n"
    }

    /// Where the suites leave their scripts, or nil when OPENSNAP_SPOKEN_SCRIPT_DIR is not set.
    static var directory: URL? {
        ProcessInfo.processInfo.environment["OPENSNAP_SPOKEN_SCRIPT_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    }

    @discardableResult
    static func write(_ text: String, surface: String) -> Bool {
        guard let directory else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: directory.appendingPathComponent(slug(surface) + ".md"), atomically: true, encoding: .utf8)
            return true
        } catch { return false }
    }
}
