import ApplicationServices
import Foundation
let app=AXUIElementCreateApplication(Int32(CommandLine.arguments[1])!)
func attr(_ e:AXUIElement,_ k:String)->CFTypeRef? { var v:CFTypeRef?;return AXUIElementCopyAttributeValue(e,k as CFString,&v) == .success ? v:nil }
func title(_ e:AXUIElement)->String { attr(e,kAXTitleAttribute) as? String ?? "" }
func kids(_ e:AXUIElement)->[AXUIElement] { attr(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] }
guard let bar=attr(app,kAXMenuBarAttribute) else { exit(2) }
let menuBar=unsafeBitCast(bar,to:AXUIElement.self)
guard let windowMenu=kids(menuBar).first(where:{title($0)=="Window"}) else { exit(3) }
func knownCommand(_ e:AXUIElement)->AXUIElement? { if title(e)=="Focus Toolbar" { return e };return kids(e).compactMap(knownCommand).first }
guard let item=knownCommand(windowMenu) else { exit(4) }
let error=AXUIElementPerformAction(item,kAXPressAction as CFString)
print("Known Window > Focus Toolbar AXPress error=\(error.rawValue)")
exit(error == .success ? 0:5)
