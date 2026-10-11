import Foundation
import ApplicationServices
let app = AXUIElementCreateApplication(pid_t(CommandLine.arguments[1])!)
func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, key as CFString, &result)
    return error == .success ? result : nil
}
func dump(_ element: AXUIElement, _ depth: Int) {
    if depth > 8 { return }
    let role = value(element, kAXRoleAttribute) as? String ?? "?"
    let title = value(element, kAXTitleAttribute) as? String ?? value(element, kAXDescriptionAttribute) as? String ?? ""
    let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    print(String(repeating: " ", count: depth * 2) + role + " " + title + " children=" + String(children.count))
    for child in children { dump(child, depth + 1) }
}
if let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] {
    if CommandLine.arguments.count > 3 {
        let mode = CommandLine.arguments[2], label = CommandLine.arguments[3]
        func find(_ element: AXUIElement) -> AXUIElement? {
            let title = value(element, kAXTitleAttribute) as? String ?? value(element, kAXDescriptionAttribute) as? String ?? ""
            if title == label { return element }
            for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let match = find(child) { return match }
            }
            return nil
        }
        guard let target = windows.compactMap({ find($0) }).first else { fatalError("Observed control missing: " + label) }
        if mode == "focus" {
            let error = AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            print("AX focus", label, error.rawValue)
        } else if mode == "press" {
            let error = AXUIElementPerformAction(target, kAXPressAction as CFString)
            print("AX press", label, error.rawValue)
        }
    } else {
        for window in windows { dump(window, 0) }
    }
}
