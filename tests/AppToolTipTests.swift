// App-owned tooltip checks. Windows stay off screen: the plate is never ordered onto the desktop (the `present` seam records it).
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D APP_TOOLTIP_TESTS \
//   Sources/DesignTokens.swift Sources/AppToolTip.swift tests/AppToolTipTests.swift -o build/app-tooltip-tests
#if APP_TOOLTIP_TESTS
import AppKit

@main
@MainActor
private enum AppToolTipTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    private static func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Runs the loop until `condition` holds. A fixed `spin` is wrong for "the timer has fired": when the process is descheduled
    /// for the whole spin (a cold full run starts dozens of compiles at once), the run loop times out with the due timer unfired.
    /// A timer that is merely late still fires on the next pass, so this waits for the event and only a real failure runs out the 10 s.
    private static func wait(_ condition: @autoclosure () -> Bool, _ message: String, within seconds: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        expect(condition(), message)
    }

    private struct Rig {
        let window: NSWindow, root: NSView, plain: NSButton, nested: NSButton, segmented: NSSegmentedControl, bare: NSButton
    }

    private static func rig() -> Rig {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 600, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        window.contentView = root
        let plain = NSButton(title: "Plain", target: nil, action: nil); plain.frame = NSRect(x: 20, y: 240, width: 120, height: 36)
        plain.toolTip = "Plain tip"
        let nested = NSButton(title: "Nested", target: nil, action: nil)
        let box = NSView(frame: NSRect(x: 160, y: 200, width: 200, height: 80)); nested.frame = NSRect(x: 10, y: 10, width: 120, height: 36)
        nested.toolTip = "Nested tip"; nested.setAccessibilityHelp("kept help")
        box.addSubview(nested)
        let segmented = NSSegmentedControl(labels: ["PNG", "JPG"], trackingMode: .selectOne, target: nil, action: nil)
        segmented.frame = NSRect(x: 380, y: 240, width: 160, height: 36)
        segmented.setToolTip("Format tip", forSegment: 0); segmented.setToolTip("Format tip", forSegment: 1)
        let bare = NSButton(title: "Bare", target: nil, action: nil); bare.frame = NSRect(x: 20, y: 150, width: 120, height: 36)
        for view in [plain, box, segmented, bare] { root.addSubview(view) }
        return Rig(window: window, root: root, plain: plain, nested: nested, segmented: segmented, bare: bare)
    }

    private static func fresh() -> AppToolTip {
        let tip = AppToolTip.shared
        tip.dismiss()
        tip.reduceMotion = { true }
        tip.suppressed = { _ in false }
        tip.delay = 0.05
        tip.visibleFrame = { _ in NSRect(x: 0, y: 0, width: 1440, height: 900) }
        tip.present = { _ in }
        return tip
    }

    static func main() {
        _ = NSApplication.shared
        storage()
        installing()
        plate()
        geometry()
        motion()
        hovering()
        liveText()
        print("AppToolTipTests: \(checks) checks passed (no panel ordered on screen, no desktop input)")
    }

    private static func storage() {
        let r = rig()
        AppToolTip.setText("Hello", for: r.bare)
        expect(AppToolTip.text(for: r.bare) == "Hello" && r.bare.toolTip == nil, "setText stores the text and leaves no system tooltip")
        expect(r.bare.accessibilityHelp() == "Hello", "setText mirrors the text into accessibilityHelp for VoiceOver")
        AppToolTip.setText("Changed", for: r.bare)
        expect(r.bare.accessibilityHelp() == "Changed", "A later setText replaces the help it wrote itself")
        r.bare.toolTip = "system again"
        AppToolTip.setText("Third", for: r.bare)
        expect(r.bare.toolTip == nil, "setText clears a system tooltip written after the last call")
        AppToolTip.setText(nil, for: r.bare)
        expect(AppToolTip.text(for: r.bare) == nil && r.bare.accessibilityHelp() == nil, "Clearing removes the text and its help")
        AppToolTip.setText("", for: r.bare)
        expect(AppToolTip.text(for: r.bare) == nil, "Empty text counts as none")

        r.bare.setAccessibilityHelp("own spoken help")
        AppToolTip.setText("tip words", for: r.bare)
        expect(r.bare.accessibilityHelp() == "own spoken help", "Help the control already speaks is never overwritten")
        AppToolTip.setText("status words", for: r.plain, mirrorsToAccessibility: false)
        expect(r.plain.accessibilityHelp() == nil, "mirrorsToAccessibility: false leaves help alone")
    }

    private static func installing() {
        let tip = fresh()
        let r = rig()
        AppToolTip.install(on: r.root)
        expect(AppToolTip.text(for: r.plain) == "Plain tip" && r.plain.toolTip == nil && r.plain.accessibilityHelp() == "Plain tip",
               "install moves a control's tooltip into the registry, clears the system tooltip and keeps it as help")
        expect(AppToolTip.text(for: r.nested) == "Nested tip" && r.nested.toolTip == nil, "install walks nested views")
        expect(r.nested.accessibilityHelp() == "kept help", "install keeps help the control already had")
        expect(AppToolTip.text(for: r.segmented) == "Format tip" && r.segmented.toolTip == nil
               && r.segmented.toolTip(forSegment: 0) == nil && r.segmented.toolTip(forSegment: 1) == nil,
               "install folds per-segment system tooltips into one control tooltip")
        expect(AppToolTip.text(for: r.bare) == nil, "A control without a tooltip stays without one")
        func systemTips(_ view: NSView) -> [String] {
            ([view.toolTip].compactMap { $0 } + view.subviews.flatMap(systemTips))
        }
        expect(systemTips(r.root).isEmpty, "After install no view in the tree has a system tooltip")
        let before = AppToolTip.watcher(for: r.root)
        AppToolTip.install(on: r.root)
        expect(AppToolTip.watcher(for: r.root) === before && r.root.trackingAreas.count == 1, "install is idempotent: one watcher, one tracking area")

        // A tooltip written after install is adopted as the pointer passes over it, before the system tooltip's own delay.
        r.bare.toolTip = "late write"
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 40, y: 160), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        let watcher = AppToolTip.watcher(for: r.root) as! AppToolTip.Watcher
        expect(watcher.tipView(for: event) === r.bare && r.bare.toolTip == nil && AppToolTip.text(for: r.bare) == "late write",
               "A late system tooltip is adopted when the pointer reaches it")
        let outside = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 590, y: 5), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        expect(watcher.tipView(for: outside) == nil, "The pointer over empty space has no tooltip")
        _ = tip
    }

    private static func plate() {
        let tip = fresh()
        let r = rig()
        AppToolTip.setText("A short tip", for: r.plain)
        tip.show(for: r.plain)
        expect(tip.isShown && tip.shownText == "A short tip", "show puts the text on the plate")
        let font = tip.label?.font
        expect((font?.pointSize ?? 0) >= 18, "The tooltip font is at least 18 pt")
        expect(font?.pointSize == DesignTokens.Typography.font(.body).pointSize && font?.pointSize == 20, "The tooltip font is the body style, 20 pt")
        let long = String(repeating: "A long tooltip sentence that has to wrap. ", count: 12)
        AppToolTip.setText(long, for: r.plain)
        tip.show(for: r.plain)
        let size = tip.panel!.frame.size
        expect(size.width <= AppToolTip.maxWidth + 0.5 && size.height > 60, "Long text wraps at the 420 pt maximum width (\(size))")
        expect(tip.label!.frame.maxX <= size.width && tip.label!.frame.maxY <= size.height, "The wrapped text fits inside the plate")
        func needed(_ field: NSTextField) -> CGFloat {
            field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.frame.width, height: .greatestFiniteMagnitude)).height
        }
        expect(needed(tip.label!) <= tip.label!.frame.height + 0.5, "The label's frame is tall enough for every wrapped line (\(needed(tip.label!)) needed, \(tip.label!.frame.height) given)")
        for sentence in ["Snap: drag an area or click a window; right-click or Control-click for Fullscreen", "Hover for original preset colors; hold Shift to change the canvas background",
                         "Capture the area inside the frame; hold Shift for a six-second timer", "Upload and copy link · Right-click for destinations"] {
            AppToolTip.setText(sentence, for: r.plain)
            tip.show(for: r.plain)
            expect(needed(tip.label!) <= tip.label!.frame.height + 0.5, "No wrapped line of '\(sentence.prefix(24))…' is clipped (\(needed(tip.label!)) needed, \(tip.label!.frame.height) given)")
        }
        AppToolTip.setText(long, for: r.plain)
        tip.show(for: r.plain)
        let plain = tip.panel!.contentView
        expect(plain != nil && !(tip.panel!.canBecomeKey) && tip.panel!.ignoresMouseEvents && !tip.panel!.isOpaque, "The plate is a non-activating panel that ignores the mouse")
        expect(tip.panel!.styleMask.contains(.nonactivatingPanel) && tip.panel!.styleMask.contains(.borderless), "The plate is borderless and non-activating")
        expect(tip.panel!.level.rawValue > r.window.level.rawValue, "The plate sits above its window")

        // Light and dark: the plate takes the owner window's appearance.
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            r.window.appearance = NSAppearance(named: name)
            AppToolTip.setText("Adaptive", for: r.plain)
            tip.show(for: r.plain)
            expect(tip.panel!.appearance?.name == name, "The plate follows the window's appearance (\(name.rawValue))")
        }
        // Contrast, measured from the drawn plate: the body text reads at 4.5:1 in light, dark and both Increase Contrast arms.
        AppToolTip.setText("A short tip", for: r.plain)
        tip.show(for: r.plain)
        let plateView = tip.panel!.contentView!, plateLabel = tip.label!
        for (name, appearance) in ContrastProbe.appearances {
            let reading = ContrastProbe.measure(plateView, appearance: appearance, plateAt: NSPoint(x: 5, y: plateView.bounds.midY), textFrames: [plateLabel.frame])
            expect(reading.plateOpaque && reading.textRatios[0] >= 4.5, "The tooltip plate is opaque and its text reads at 4.5:1 (\(name): opaque \(reading.plateOpaque), \(reading.textRatios[0]))")
        }
        let plateFill = DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.content, for: NSAppearance(named: .aqua)!)
        let darkFill = DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.content, for: NSAppearance(named: .darkAqua)!)
        expect(plateFill != darkFill, "The plate's surface role resolves to different colours in light and dark")
        tip.dismiss()
    }

    private static func geometry() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let size = NSSize(width: 300, height: 60)
        func check(_ anchor: NSRect, _ label: String) {
            let frame = AppToolTip.frame(size: size, anchor: anchor, visible: visible)
            expect(visible.contains(frame), "\(label): the plate stays on screen \(frame)")
            expect(!frame.intersects(anchor), "\(label): the plate never covers the control \(frame) vs \(anchor)")
        }
        let control = NSSize(width: 48, height: 36)
        let top = visible.maxY - control.height - 2, bottom = visible.minY + 2, left = visible.minX + 2, right = visible.maxX - control.width - 2
        check(NSRect(origin: NSPoint(x: 500, y: bottom), size: control), "bottom edge")
        check(NSRect(origin: NSPoint(x: 500, y: top), size: control), "top edge")
        check(NSRect(origin: NSPoint(x: left, y: 300), size: control), "left edge")
        check(NSRect(origin: NSPoint(x: right, y: 300), size: control), "right edge")
        check(NSRect(origin: NSPoint(x: right, y: bottom), size: control), "bottom-right corner")
        check(NSRect(origin: NSPoint(x: left, y: top), size: control), "top-left corner")
        let below = AppToolTip.frame(size: size, anchor: NSRect(x: 500, y: 400, width: 48, height: 36), visible: visible)
        expect(below.maxY <= 400 - AppToolTip.gap + 0.5, "With room, the plate is below the control")
        let above = AppToolTip.frame(size: size, anchor: NSRect(x: 500, y: bottom, width: 48, height: 36), visible: visible)
        expect(above.minY >= bottom + 36 + AppToolTip.gap - 0.5, "With no room below, the plate is above the control")
        // A control as tall as the screen leaves no room above or below: the plate goes beside it.
        let tall = NSRect(x: 400, y: 0, width: 100, height: 700)
        let beside = AppToolTip.frame(size: size, anchor: tall, visible: visible)
        expect(visible.contains(beside) && !beside.intersects(tall), "A full-height control gets the plate beside it")
        // Sweep: every anchor on a grid, three plate sizes.
        for plateSize in [NSSize(width: 120, height: 36), size, NSSize(width: 420, height: 160)] {
            var worst = 0
            for x in stride(from: CGFloat(0), through: 952, by: 56) {
                for y in stride(from: CGFloat(0), through: 664, by: 41) {
                    let anchor = NSRect(x: x, y: y, width: 48, height: 36)
                    let frame = AppToolTip.frame(size: plateSize, anchor: anchor, visible: visible)
                    if !visible.contains(frame) || frame.intersects(anchor) { worst += 1 }
                }
            }
            expect(worst == 0, "Sweep with a \(plateSize) plate: every anchor keeps the plate on screen and off the control (\(worst) bad)")
        }
        // The same through show(): the real screen rect of a control in a window at the screen's edge.
        let tip = fresh()
        let r = rig()
        tip.visibleFrame = { _ in NSRect(x: 0, y: 0, width: 760, height: 500) }
        r.window.setFrameOrigin(NSPoint(x: 120, y: 2))
        AppToolTip.setText("Edge tip", for: r.bare)
        tip.show(for: r.bare)
        let anchor = AppToolTip.anchorRect(of: r.bare, in: r.window)
        expect(NSRect(x: 0, y: 0, width: 760, height: 500).contains(tip.panel!.frame) && !tip.panel!.frame.intersects(anchor),
               "show() keeps the plate on screen and off the control at the screen edge")
        tip.dismiss()
    }

    private static func motion() {
        let tip = fresh()
        let r = rig()
        AppToolTip.setText("Motion", for: r.plain)
        var alphaAtPresent: CGFloat = -1
        tip.present = { alphaAtPresent = $0.alphaValue }
        tip.reduceMotion = { true }
        tip.show(for: r.plain)
        expect(alphaAtPresent == 1 && !tip.lastShowWasAnimated, "Under Reduce Motion the plate appears at once, at full alpha, with no fade")
        tip.dismiss()
        tip.reduceMotion = { false }
        tip.show(for: r.plain)
        expect(alphaAtPresent == 0 && tip.lastShowWasAnimated, "Without Reduce Motion the plate starts clear and fades in")
        tip.dismiss()
    }

    private static func hovering() {
        let tip = fresh()
        let r = rig()
        AppToolTip.install(on: r.root)
        // tools/test-tooltip-stall.py freezes the process while this wait is in flight; it keys on this line.
        FileHandle.standardError.write(Data("AppToolTipTests: hover wait begins\n".utf8))
        tip.hover(over: r.plain)
        expect(tip.isPending && !tip.isShown && tip.pendingTarget === r.plain, "Hovering starts a wait, it does not show at once")
        wait(tip.isShown, "After the hover delay the plate is shown")
        expect(tip.target === r.plain && !tip.isPending, "The plate is shown for the hovered control and nothing is pending")
        tip.hover(over: nil)
        expect(!tip.isShown && !tip.isPending, "Moving off the control (mouse exit) hides the plate")

        tip.hover(over: r.plain)
        tip.hover(over: nil)
        spin(0.3)  // a cancelled timer stays cancelled however long the process is frozen, so a fixed spin cannot flake here
        expect(!tip.isShown, "Leaving before the delay cancels the pending tooltip")

        tip.hover(over: r.bare)
        expect(!tip.isPending && !tip.isShown, "A control with no text never starts a tooltip")

        tip.hover(over: r.plain)
        wait(tip.target === r.plain, "The first control's plate is shown before moving on")
        tip.hover(over: r.nested)
        expect(!tip.isShown && tip.pendingTarget === r.nested, "Moving to another control hides the first and waits for the second")
        wait(tip.target === r.nested, "The second control's plate is shown")
        expect(tip.shownText == "Nested tip", "The second control's text is shown")

        // The root's tracking area drives the same machine: moved over a control waits, then shows; exit hides.
        // Events go through the Objective-C runtime to the tracking area's owner, the way AppKit delivers them. Calling the
        // Swift methods directly is how a selector mismatch (`mouseEnteredWith:` vs `mouseEntered:`) shipped as a hover crash.
        let area = r.root.trackingAreas.first { $0.owner is AppToolTip.Watcher }
        expect(area != nil && area!.owner === AppToolTip.watcher(for: r.root), "The root's tracking area is owned by its watcher")
        let owner = area!.owner as! NSObject
        expect(area!.options.contains(.mouseMoved) && area!.options.contains(.mouseEnteredAndExited), "The tracking area asks for moves, enters and exits")
        for name in ["mouseEntered:", "mouseExited:", "mouseMoved:"] {
            expect(owner.responds(to: NSSelectorFromString(name)), "The tracking area owner responds to \(name) as AppKit sends it")
            expect(!owner.responds(to: NSSelectorFromString(name.replacingOccurrences(of: ":", with: "With:"))), "\(name) is not exported under the Swift-mangled name")
        }
        func deliver(_ name: String, _ event: NSEvent) { _ = owner.perform(NSSelectorFromString(name), with: event) }
        func pointer(_ x: CGFloat, _ y: CGFloat, _ type: NSEvent.EventType = .mouseMoved) -> NSEvent {
            switch type {
            case .mouseEntered, .mouseExited:
                return NSEvent.enterExitEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0,
                                              context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            default:
                return NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            }
        }
        tip.dismiss()
        deliver("mouseMoved:", pointer(40, 250))
        expect(tip.isPending && tip.pendingTarget === r.plain, "The tracking area's pointer move over a control starts its tooltip")
        wait(tip.target === r.plain, "The tooltip appears for the control under the pointer")
        deliver("mouseMoved:", pointer(590, 5))
        expect(!tip.isShown, "Moving onto empty space hides the plate")
        deliver("mouseMoved:", pointer(40, 250))
        wait(tip.isShown, "The plate shows again on re-entry")
        deliver("mouseExited:", pointer(40, 250, .mouseExited))
        expect(!tip.isShown && !tip.isPending, "The tracking area's mouse exit hides the plate")
        deliver("mouseEntered:", pointer(40, 250, .mouseEntered))
        expect(tip.isPending, "The tracking area's mouse enter over a control starts the wait")
        tip.dismiss()

        // Click, scroll and key press hide the plate (a local event monitor); a window resigning key does too.
        for (name, type) in [("mouse down", NSEvent.EventType.leftMouseDown), ("right mouse down", .rightMouseDown), ("scroll", .scrollWheel), ("key press", .keyDown)] {
            tip.show(for: r.plain)
            expect(tip.isShown, "\(name): the plate is up before the event")
            let event: NSEvent?
            switch type {
            case .keyDown: event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)
            case .scrollWheel: event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0).flatMap { NSEvent(cgEvent: $0) }
            default: event = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            }
            if let event { NSApp.sendEvent(event) }
            expect(event != nil && !tip.isShown, "\(name) hides the plate")
        }
        tip.show(for: r.plain)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: r.window)
        wait(!tip.isShown, "A window resigning key hides the plate")
        tip.show(for: r.plain)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        wait(!tip.isShown, "The app resigning active hides the plate")

        // After a click the control stays quiet until the pointer leaves it and comes back.
        tip.hover(over: nil)
        tip.show(for: r.plain)
        NSApp.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        tip.hover(over: r.plain)
        expect(!tip.isPending && !tip.isShown, "After a click the same control does not start a new tooltip while the pointer stays on it")
        tip.hover(over: nil)
        tip.hover(over: r.plain)
        expect(tip.isPending, "Leaving and re-entering the control allows a tooltip again")
        tip.dismiss()

        // The hover-hint bevel replaces the tooltip on the controls it covers.
        tip.suppressed = { $0 === r.plain }
        tip.hover(over: nil)
        tip.hover(over: r.plain)
        expect(!tip.isPending && !tip.isShown, "A control covered by the hint bevel gets no tooltip")
        tip.hover(over: r.nested)
        expect(tip.isPending, "A control the bevel does not cover still gets one")
        tip.dismiss()
    }

    private static func liveText() {
        let tip = fresh()
        let r = rig()
        AppToolTip.setText("Size 4", for: r.plain)
        tip.show(for: r.plain)
        AppToolTip.setText("Size 9", for: r.plain)
        expect(tip.shownText == "Size 9" && tip.label?.stringValue == "Size 9", "A live text change updates the visible plate")
        AppToolTip.setText("Size 9, and a much longer description of what it means", for: r.plain)
        let widened = tip.panel!.frame.width
        AppToolTip.setText("Size 9", for: r.plain)
        expect(tip.panel!.frame.width < widened, "The plate resizes to the new text")
        AppToolTip.setText(nil, for: r.plain)
        expect(!tip.isShown, "Clearing the text of the shown control hides the plate")
        // A change on a control that is not shown never shows anything.
        AppToolTip.setText("Elsewhere", for: r.nested)
        expect(!tip.isShown, "Writing another control's text does not show a plate")
    }
}
#endif
