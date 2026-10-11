import Foundation
import ApplicationServices

guard CommandLine.arguments.count >= 2, let pid = Int32(CommandLine.arguments[1]) else { exit(2) }
let app = AXUIElementCreateApplication(pid)
func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
}
func label(_ element: AXUIElement) -> String {
    [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attr(element, $0) as? String }.first { !$0.isEmpty } ?? ""
}
let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
func children(_ element: AXUIElement) -> [AXUIElement] { attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func find(_ element: AXUIElement, _ wanted: String, _ depth: Int = 0) -> AXUIElement? {
    guard depth < 32 else { return nil }
    let role = attr(element, kAXRoleAttribute) as? String ?? ""
    if label(element) == wanted && ["AXButton", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXSlider", "AXTextField", "AXTabGroup"].contains(role) { return element }
    return children(element).compactMap { find($0, wanted, depth + 1) }.first
}
func dump(_ element: AXUIElement, _ parent: AXUIElement?, _ depth: Int = 0) {
    guard depth < 32 else { print("DEPTH LIMIT"); return }
    let role = attr(element, kAXRoleAttribute) as? String ?? "?"
    let kids = children(element)
    let state = attr(element, kAXValueAttribute).map { String(describing: $0) } ?? ""
    let enabled = attr(element, kAXEnabledAttribute).map { String(describing: $0) } ?? ""
    var parentOK = true
    if let parent, let reported = attr(element, kAXParentAttribute) {
        parentOK = CFEqual(reported, parent)
    } else if parent != nil { parentOK = false }
    print(String(repeating: "  ", count: depth) + role + " " + label(element) + " value=" + state + " enabled=" + enabled + " children=" + String(kids.count) + " focused=" + String(describing: attr(element, kAXFocusedAttribute)) + " parentOK=" + String(parentOK))
    for kid in kids { dump(kid, element, depth + 1) }
}
print("AX trusted=" + String(AXIsProcessTrusted()) + " windows=" + String(windows.count))
if CommandLine.arguments.count >= 4 {
    let mode = CommandLine.arguments[2], wanted = CommandLine.arguments[3]
    guard let target = windows.compactMap({ find($0, wanted) }).first else { print("MISSING " + wanted); exit(3) }
    let error: AXError
    if mode == "attrs" {
        var actions: CFArray?; AXUIElementCopyActionNames(target, &actions); print("actions=", actions as Any)
        for key in [kAXTitleAttribute,kAXDescriptionAttribute,kAXRoleAttribute,kAXValueAttribute,kAXEnabledAttribute,kAXFocusedAttribute] { print(key, attr(target,key) as Any) }; exit(0)
    } else if mode == "focus" {
        error = AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    } else {
        error = AXUIElementPerformAction(target, (mode == "show" ? kAXShowMenuAction : kAXPressAction) as CFString)
    }
    print("AX " + mode + " " + wanted + " error=" + String(error.rawValue))
    if error != .success { exit(4) }
} else {
    for window in windows { dump(window, nil) }
}
