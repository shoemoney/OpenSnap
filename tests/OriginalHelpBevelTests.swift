// Nonordering host/panel and deterministic timers: no desktop input/permissions.
// rtk proxy xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete \
//   -target arm64-apple-macosx13.0 -D ORIGINAL_HELP_BEVEL_TESTS \
//   Sources/OriginalHelpBevel.swift tests/OriginalHelpBevelTests.swift -o build/original-help-bevel-tests
// rtk proxy build/original-help-bevel-tests
#if ORIGINAL_HELP_BEVEL_TESTS
import AppKit

private final class HelpHost: NSWindow {
    var shown = true
    var key = true
    var minimized = false
    var simulatedSheet: NSWindow?
    var attachments: [(NSWindow, NSWindow.OrderingMode)] = []
    override var isVisible: Bool { shown }
    override var isKeyWindow: Bool { key }
    override var isMiniaturized: Bool { minimized }
    override var attachedSheet: NSWindow? { simulatedSheet }
    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        attachments.append((childWin, place))
        (childWin as? HelpPanel)?.host = self
    }
    override func removeChildWindow(_ childWin: NSWindow) {
        attachments.removeAll { $0.0 === childWin }
        (childWin as? HelpPanel)?.host = nil
    }
    override func orderFront(_ sender: Any?) {}
    override func orderOut(_ sender: Any?) {}
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("must not focus host") }
}

private final class HelpPanel: NSPanel {
    weak var host: HelpHost?
    var fronts = 0
    var outs = 0
    var closes = 0
    /// Every alpha the bevel assigned, in order (the first 0 is the panel's creation).
    var alphaLog: [CGFloat] = []
    override var alphaValue: CGFloat { didSet { alphaLog.append(alphaValue) } }
    override var parent: NSWindow? {
        get { host }
        set { host = newValue as? HelpHost }
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func orderFront(_ sender: Any?) { fronts += 1 }
    override func orderFrontRegardless() { preconditionFailure("must not order regardless of host") }
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("must not focus help") }
    override func orderOut(_ sender: Any?) { outs += 1 }
    override func close() { closes += 1 }
}

@MainActor
private final class ControlledHelpScheduler: OriginalHelpBevelScheduling {
    struct Entry {
        let interval: TimeInterval
        let repeats: Bool
        let timer: Timer
        let action: @MainActor @Sendable () -> Bool
    }
    var entries: [Entry] = []
    var active: Int { entries.filter { $0.timer.isValid }.count }
    func timer(interval: TimeInterval, repeats: Bool,
               action: @escaping @MainActor @Sendable () -> Bool) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { timer in
            if !MainActor.assumeIsolated({ action() }) { timer.invalidate() }
        }
        entries.append(Entry(interval: interval, repeats: repeats, timer: timer, action: action))
        return timer // Deliberately never register a test timer with a run loop.
    }
    func latest(_ interval: TimeInterval) -> Int {
        entries.lastIndex { $0.interval == interval }!
    }
    func fire(_ index: Int, stale: Bool = false) {
        let entry = entries[index]
        guard stale || entry.timer.isValid else { return }
        if !entry.action() || !entry.repeats { entry.timer.invalidate() }
    }
    func finishFade() -> Int {
        let index = latest(0.02)
        var ticks = 0
        while entries[index].timer.isValid && ticks < 20 { fire(index); ticks += 1 }
        return ticks
    }
}

@main
@MainActor
private enum OriginalHelpBevelTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }
    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.000001 }

    @MainActor
    private struct Rig {
        let host: HelpHost
        let scheduler: ControlledHelpScheduler
        let bevel: OriginalHelpBevel
        let factoryCalls: NSMutableArray
        var panel: HelpPanel { bevel.panel as! HelpPanel }
    }
    private static func make(reduceMotion: Bool = false, screen: NSRect? = nil) -> Rig {
        let host = HelpHost(contentRect: NSRect(x: -700, y: 100, width: 800, height: 500),
                            styleMask: [.borderless], backing: .buffered, defer: true)
        host.isReleasedWhenClosed = false
        let scheduler = ControlledHelpScheduler()
        let factoryCalls = NSMutableArray()
        let bevel = OriginalHelpBevel(host: host, makePanel: {
            factoryCalls.add(true)
            return HelpPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        }, scheduler: scheduler, reduceMotion: { reduceMotion }, screenFrame: { _ in screen })
        return Rig(host: host, scheduler: scheduler, bevel: bevel, factoryCalls: factoryCalls)
    }

    static func main() {
        _ = NSApplication.shared
        gates()
        slotsAndStaleEvents()
        fadesAndReversal()
        layoutAndRendering()
        reduceMotionSkipsFade()
        plateFitsText()
        tokensOnly()
        staysOnScreen()
        teardownAndReachability()
        nativeRunLoopModes()
        print("PASS OriginalHelpBevelTests (\(checks) checks; injected nonordering panels, no desktop input or permissions)")
    }

    private static func gates() {
        let rig = make()
        defer { rig.bevel.shutdown() }
        expect(rig.bevel.panel == nil && rig.bevel.displayedMessage == nil && !rig.bevel.enabled,
               "Construction is lazy and disabled")
        rig.bevel.hover(owner: "tool", message: "Draw")
        rig.bevel.modifiers(message: "Constrain")
        expect(rig.factoryCalls.count == 0 && rig.scheduler.active == 0, "Disabled cannot allocate or schedule")
        rig.bevel.enabled = true
        for gate in 0..<4 {
            rig.host.shown = gate != 0
            rig.host.key = gate != 1
            rig.host.minimized = gate == 2
            rig.host.simulatedSheet = gate == 3 ? rig.host : nil
            rig.bevel.hover(owner: "tool", message: "Draw")
            rig.bevel.modifiers(message: "Constrain")
            expect(rig.factoryCalls.count == 0 && rig.scheduler.active == 0 && rig.bevel.displayedMessage == nil,
                   "Hidden/nonkey/miniaturized/sheet host cannot allocate or schedule")
        }
        rig.host.shown = true; rig.host.key = true; rig.host.minimized = false; rig.host.simulatedSheet = nil
        rig.bevel.reposition()
        expect(rig.bevel.panel == nil, "Regaining eligibility does not resurrect denied messages")
        rig.bevel.modifiers(message: "Constrain")
        expect(rig.factoryCalls.count == 1 && rig.bevel.displayedMessage == "Constrain", "Modifier is immediate")
        expect(!rig.panel.canBecomeKey && !rig.panel.canBecomeMain && rig.panel.ignoresMouseEvents,
               "Overlay never consumes focus or pointer interactions")
        expect(rig.panel.styleMask.contains(.nonactivatingPanel) && !rig.panel.isOpaque && !rig.panel.isFloatingPanel,
               "Native help is transparent, nonactivating and parent-owned")
        expect(rig.host.attachments.count == 1 && rig.host.attachments[0].1 == .below && rig.panel.host === rig.host,
               "Eligible overlay is attached below its host")
        for gate in 0..<4 {
            rig.host.shown = true; rig.host.key = true; rig.host.minimized = false; rig.host.simulatedSheet = nil
            rig.bevel.modifiers(message: "Live help")
            if gate == 0 { rig.host.shown = false }
            if gate == 1 { rig.host.key = false }
            if gate == 2 { rig.host.minimized = true }
            if gate == 3 { rig.host.simulatedSheet = rig.host }
            rig.bevel.reposition()
            expect(rig.bevel.displayedMessage == nil && rig.host.attachments.isEmpty && rig.scheduler.active == 0,
                   "Lifecycle gate clears a shown or fading child and all queued work")
        }
    }

    private static func slotsAndStaleEvents() {
        let rig = make()
        defer { rig.bevel.shutdown() }
        rig.bevel.enabled = true
        rig.bevel.hover(owner: "A", message: "A hover")
        let first = rig.scheduler.latest(0.25)
        expect(rig.bevel.displayedMessage == nil && rig.bevel.panel == nil, "Hover waits the recovered quarter second")
        expect(!rig.scheduler.entries[first].repeats, "Hover uses one delayed delivery")
        rig.bevel.hover(owner: "B", message: "B hover")
        let second = rig.scheduler.latest(0.25)
        expect(!rig.scheduler.entries[first].timer.isValid, "New hover invalidates old pending timer")
        rig.bevel.exit(owner: "A")
        rig.scheduler.fire(first, stale: true)
        expect(rig.bevel.displayedMessage == nil && rig.bevel.panel == nil, "Stale exit and stale timer cannot show old owner")
        rig.bevel.modifiers(message: "Modifier")
        expect(rig.bevel.displayedMessage == "Modifier", "Immediate slot outranks pending hover")
        rig.scheduler.fire(second)
        expect(rig.bevel.displayedMessage == "Modifier", "Ready hover cannot override modifier")
        rig.bevel.exit(owner: "A")
        expect(rig.bevel.displayedMessage == "Modifier", "Stale exit cannot clear either current slot")
        rig.bevel.hover(owner: "C", message: "C hover")
        rig.scheduler.fire(rig.scheduler.latest(0.25))
        expect(rig.bevel.displayedMessage == "Modifier", "Replacing delayed slot retains modifier priority")
        rig.bevel.modifiers(message: nil)
        expect(rig.bevel.displayedMessage == nil && rig.scheduler.active == 0 && rig.host.attachments.isEmpty,
               "Modifier release clears BOTH slots immediately, with no hover fallback")
        rig.scheduler.fire(second, stale: true)
        rig.bevel.reposition()
        expect(rig.bevel.displayedMessage == nil, "Cleared hover never resurrects from a late callback")
        for message in ["", "  \n  "] {
            rig.bevel.hover(owner: "D", message: "Pending")
            let pending = rig.scheduler.latest(0.25)
            rig.bevel.modifiers(message: "Immediate")
            rig.bevel.modifiers(message: message)
            rig.scheduler.fire(pending, stale: true)
            expect(rig.bevel.displayedMessage == nil && rig.scheduler.active == 0,
                   "Empty modifier help also clears both queued/live slots")
        }
        rig.bevel.hover(owner: "E", message: "Hover")
        rig.scheduler.fire(rig.scheduler.latest(0.25))
        expect(rig.bevel.displayedMessage == "Hover", "Delayed slot alone becomes visible")
        rig.bevel.modifiers(message: "Key help")
        rig.bevel.exit(owner: "E")
        expect(rig.bevel.displayedMessage == nil, "Current owner exit uses original hideHelp, clearing both slots")
        rig.bevel.clear()
        rig.bevel.enabled = false
        rig.bevel.enabled = true
        rig.bevel.reposition()
        expect(rig.bevel.displayedMessage == nil && rig.scheduler.active == 0, "Re-enable cannot replay old help")
    }

    private static func fadesAndReversal() {
        let rig = make()
        defer { rig.bevel.shutdown() }
        rig.bevel.enabled = true
        rig.bevel.hover(owner: "A", message: "Hover")
        rig.scheduler.fire(rig.scheduler.latest(0.25))
        let show = rig.scheduler.latest(0.02)
        expect(rig.panel.alphaValue == 0 && rig.scheduler.entries[show].repeats, "Show starts from transparent at 20ms ticks")
        rig.scheduler.fire(show)
        expect(near(rig.panel.alphaValue, 0.15), "Original first show tick adds 0.15")
        rig.scheduler.fire(show)
        expect(near(rig.panel.alphaValue, 0.30), "Original second show tick adds 0.15")
        rig.bevel.exit(owner: "A")
        let hide = rig.scheduler.latest(0.02)
        expect(!rig.scheduler.entries[show].timer.isValid, "Hide replaces and invalidates show timer")
        rig.scheduler.fire(hide)
        expect(near(rig.panel.alphaValue, 0.20), "Original hide tick subtracts 0.1")
        rig.scheduler.fire(show, stale: true)
        expect(near(rig.panel.alphaValue, 0.20), "Cancelled show callback cannot alter fading child")
        rig.bevel.modifiers(message: "Replacement")
        let replacement = rig.scheduler.latest(0.02)
        expect(!rig.scheduler.entries[hide].timer.isValid, "New help reverses fade from current alpha")
        rig.scheduler.fire(hide, stale: true)
        expect(rig.bevel.displayedMessage == "Replacement" && near(rig.panel.alphaValue, 0.20),
               "Cancelled hide callback cannot detach or darken replacement help")
        expect(rig.scheduler.finishFade() == 6 && rig.panel.alphaValue == 1 && rig.scheduler.active == 0,
               "Reversed show is bounded, clamps to one and stops its timer")
        rig.bevel.hover(owner: "B", message: "Hover")
        rig.scheduler.fire(rig.scheduler.latest(0.25))
        rig.bevel.exit(owner: "B")
        expect(rig.scheduler.finishFade() == 10 && rig.panel.alphaValue == 0 && rig.host.attachments.isEmpty,
               "Original float arithmetic gives ten hide ticks and detaches at zero")
        rig.bevel.modifiers(message: "Again")
        expect(rig.scheduler.finishFade() == 7 && rig.panel.alphaValue == 1,
               "Show from zero is seven recovered ticks")
        expect(replacement != show && rig.panel.fronts == 2, "Reuse does not duplicate attachment or order while already attached")
        rig.bevel.modifiers(message: nil)
        expect(rig.bevel.displayedMessage == nil && rig.scheduler.active == 1 && rig.host.attachments.count == 1,
               "Modifier release clears both slots through original fade-out, retaining child until zero")
        let release = rig.scheduler.latest(0.02)
        rig.scheduler.fire(release)
        expect(near(rig.panel.alphaValue, 0.9), "Modifier release uses recovered -0.1 alpha step")
        expect(rig.scheduler.finishFade() == 9 && rig.host.attachments.isEmpty,
               "Remaining modifier hide ticks detach without bringing hover back")
        rig.bevel.modifiers(message: "Before preference toggle")
        rig.bevel.hover(owner: "C", message: "Queued")
        let pending = rig.scheduler.latest(0.25)
        rig.bevel.enabled = false
        rig.scheduler.fire(pending, stale: true)
        expect(rig.bevel.displayedMessage == nil && rig.panel.alphaValue == 0 && rig.scheduler.active == 0 && rig.host.attachments.isEmpty,
               "Turning off cancels every delay/fade and immediately removes child")
    }

    private static func layoutAndRendering() {
        let rig = make()
        defer { rig.bevel.shutdown() }
        rig.bevel.enabled = true
        rig.bevel.modifiers(message: "Hold Shift to constrain")
        let view = rig.panel.contentView as! OriginalHelpBevelView
        let singleLine = view.attributedMessage.boundingRect(with: NSSize(width: 714, height: CGFloat.greatestFiniteMagnitude),
                                                             options: [.usesLineFragmentOrigin, .usesFontLeading])
        let body = max(44, ceil(singleLine.height) + 16), plateHeight = body + 3
        expect(rig.panel.frame == NSRect(x: -660, y: 600, width: 720, height: plateHeight),
               "Host +40/top/width-80, text height plus 8 pt above and below plus the 3 pt allowance, including negative display coordinates")
        expect(view.textRect.minX == 3 && view.textRect.width == 714 && view.bounds.contains(view.textRect),
               "Recovered three-point inner inset and all text within readable body")
        let font = view.attributedMessage.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        let paragraph = view.attributedMessage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        expect(font.pointSize == 20 && paragraph.alignment == .center && paragraph.lineBreakMode == .byWordWrapping && paragraph.lineHeightMultiple >= 1.5,
               "Readable centered 20-point multiline text replaces original 14-point middle truncation")
        expect(view.accessibilityValue() as? String == "Hold Shift to constrain", "Full message is accessible")
        let path = view.backgroundPath
        expect(path.bounds == NSRect(x: 1, y: -11, width: 718, height: plateHeight - 2 + 12) && path.lineWidth == 2,
               "Original inset1/y-12/height+12 stroke2 extends behind host join")
        rig.host.setFrame(NSRect(x: 50, y: -100, width: 440, height: 300), display: false)
        rig.bevel.reposition()
        expect(rig.panel.frame.minX == 90 && rig.panel.frame.minY == 200 && rig.panel.frame.width == 360,
               "Parent move/resize repositions same attachment using original constants")
        let long = String(repeating: "Hold Option to sample a color, then continue drawing. ", count: 8)
        rig.bevel.modifiers(message: long)
        expect(rig.panel.frame.height > plateHeight && view.message == long && view.bounds.contains(view.textRect),
               "Long message grows vertically without clipping, truncating or shrinking font")
        let measured = view.attributedMessage.boundingRect(with: NSSize(width: view.textRect.width, height: .greatestFiniteMagnitude),
                                                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        expect(ceil(measured.height) <= view.textRect.height && rig.panel.frame.height == max(44, ceil(measured.height) + 16) + 3,
               "Actual text measurement determines sufficient multiline body height plus original allowance")
        let raster = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: raster)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let color = raster.colorAt(x: Int(view.bounds.midX), y: 2)!.usingColorSpace(.deviceRGB)!
        expect(abs(color.alphaComponent - 0.85) < 0.03 && color.redComponent < 0.1,
               "Offscreen production renderer uses recovered translucent black background")
        let stroke = raster.colorAt(x: 1, y: Int(view.bounds.midY))!.usingColorSpace(.deviceRGB)!
        expect(abs(stroke.redComponent - 0.95) < 0.03 && stroke.alphaComponent > 0.99,
               "Offscreen production renderer uses recovered opaque 0.95 gray stroke")
        expect(raster.bitmapData!.withMemoryRebound(to: UInt8.self, capacity: raster.bytesPerRow * raster.pixelsHigh) {
            buffer in (0..<(raster.bytesPerRow * raster.pixelsHigh)).contains { buffer[$0] > 220 }
        }, "Production raster includes visible light text/stroke")
        rig.host.setFrame(NSRect(x: 0, y: 0, width: 85, height: 200), display: false)
        rig.bevel.reposition()
        expect(rig.bevel.displayedMessage == nil && rig.host.attachments.isEmpty && rig.scheduler.active == 0,
               "Exhausted original width clears instead of producing an unreadable or resurrected child")
    }


    /// Reduce Motion: no fade at all. The alpha goes straight to its final value, and no 20 ms timer is ever scheduled.
    private static func reduceMotionSkipsFade() {
        let rig = make(reduceMotion: true)
        defer { rig.bevel.shutdown() }
        rig.bevel.enabled = true
        rig.bevel.hover(owner: "A", message: "Hover")
        rig.scheduler.fire(rig.scheduler.latest(0.25))
        let shown = rig.panel
        expect(shown.alphaLog.first == 0 && Array(shown.alphaLog.dropFirst()) == [1],
               "Reduce Motion: the show tick sequence is just the final alpha, got \(shown.alphaLog)")
        expect(rig.scheduler.entries.allSatisfy { $0.interval != 0.02 }, "Reduce Motion schedules no fade timer")
        rig.bevel.exit(owner: "A")
        expect(shown.alphaLog.last == 0 && shown.alphaLog.count == 3 && rig.host.attachments.isEmpty && rig.scheduler.entries.allSatisfy { $0.interval != 0.02 },
               "Reduce Motion: hiding goes straight to 0 and detaches, got \(shown.alphaLog)")
        // Switching message while visible keeps the plate at 1 without stepping.
        rig.bevel.modifiers(message: "One")
        rig.bevel.modifiers(message: "Two")
        expect(shown.alphaValue == 1 && Set(shown.alphaLog.dropFirst(3)) == [1], "Replacing the message under Reduce Motion never dips below 1")
        // The same run with motion allowed is stepped, so the single frame above is the setting's doing.
        let motion = make()
        defer { motion.bevel.shutdown() }
        motion.bevel.enabled = true
        motion.bevel.modifiers(message: "One")
        _ = motion.scheduler.finishFade()
        expect(Array(motion.panel.alphaLog.dropFirst()).count == 7 && motion.panel.alphaLog.last == 1, "Normal motion fades in over seven steps")
    }

    /// The plate is as tall as its text needs plus air, never less: no line sits on or past an edge.
    private static func plateFitsText() {
        let rig = make()
        defer { rig.bevel.shutdown() }
        rig.bevel.enabled = true
        let messages = ["Hold Shift to constrain",
                        String(repeating: "Hold Option to sample a color, then continue drawing. ", count: 4)]
        for message in messages {
            rig.bevel.modifiers(message: message)
            let view = rig.panel.contentView as! OriginalHelpBevelView
            let measured = ceil(view.attributedMessage.boundingRect(with: NSSize(width: view.textRect.width, height: .greatestFiniteMagnitude),
                                                                   options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            expect(view.textRect.height >= measured, "Text rect holds every line of '\(message.prefix(12))…'")
            expect(view.textRect.minY >= OriginalHelpBevelView.verticalPadding && view.bounds.maxY - view.textRect.maxY >= OriginalHelpBevelView.verticalPadding,
                   "At least 8 pt of plate above and below the text: \(view.textRect) in \(view.bounds)")
            // Pixels: the lit text never touches the top or bottom edge of the plate.
            let raster = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: raster)
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            var firstRow = Int.max, lastRow = -1
            for y in 0..<raster.pixelsHigh { for x in 20..<(raster.pixelsWide - 20) {
                guard let c = raster.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.9, c.redComponent > 0.9 else { continue }
                // Skip the 2 pt outline: only rows inside the plate by more than the stroke count as text.
                if y > 3 && y < raster.pixelsHigh - 3 { firstRow = min(firstRow, y); lastRow = max(lastRow, y) }
            } }
            expect(lastRow >= 0 && firstRow >= 8 && raster.pixelsHigh - 1 - lastRow >= 8,
                   "Rendered text keeps 8 px clear of the plate's top and bottom: rows \(firstRow)...\(lastRow) of \(raster.pixelsHigh)")
        }
    }

    /// Only token values: HUD type, HUD text colour, HUD fill, HUD stroke, the lg radius.
    private static func tokensOnly() {
        typealias T = DesignTokens
        let rig = make()
        defer { rig.bevel.shutdown() }
        rig.bevel.enabled = true
        rig.bevel.modifiers(message: "Tokens")
        let view = rig.panel.contentView as! OriginalHelpBevelView
        expect(OriginalHelpBevelView.font == T.Typography.font(.hud), "Hint type is the HUD token (20 pt medium)")
        let attributes = view.attributedMessage.attributes(at: 0, effectiveRange: nil)
        expect((attributes[.font] as! NSFont) == T.Typography.font(.hud), "Message drawn in the HUD font")
        expect((attributes[.foregroundColor] as! NSColor) == T.Palette.Overlay.hudText, "Message drawn in the HUD text colour")
        expect(attributes[.shadow] == nil, "No text shadow on a solid plate")
        // The outline's corner is the lg radius: a point on the 12 pt arc is on the path, one outside it is not.
        view.joinsHost = false
        let path = view.backgroundPath
        let inset = view.bounds.insetBy(dx: 1, dy: 1)
        let lg = T.Radius.lg
        expect(lg == 12 && !path.contains(NSPoint(x: inset.minX + 0.5, y: inset.minY + 0.5)), "Plate corner is cut with the lg radius (12)")
        expect(path.contains(NSPoint(x: inset.minX + lg, y: inset.minY + lg)), "Plate is solid just inside the corner arc")
        view.joinsHost = true
        let fill = T.Palette.resolve(T.Palette.Overlay.hudFill, arm: .aqua), stroke = T.Palette.resolve(T.Palette.Overlay.hudStroke, arm: .aqua)
        expect(abs(fill.alphaComponent - 0.85) < 0.001 && fill.redComponent == 0, "Fill token is black at 0.85")
        expect(abs(stroke.alphaComponent - 0.95) < 0.001 && stroke.redComponent == 1, "Stroke token is white at 0.95")
    }

    /// A host at the very top of the screen leaves no room above it: the plate then sits inside the host's top edge, in front of
    /// it, rounded on all four corners, and is never cut off by the screen edge.
    private static func staysOnScreen() {
        let screen = NSRect(x: -700, y: 0, width: 1400, height: 700)
        // Roomy: host top at 600 leaves 100 pt, plate hangs above, behind the host.
        let roomy = make(screen: screen)
        defer { roomy.bevel.shutdown() }
        roomy.bevel.enabled = true
        roomy.bevel.modifiers(message: "Hold Shift to constrain")
        let view = roomy.panel.contentView as! OriginalHelpBevelView
        expect(roomy.panel.frame.minY == 600 && view.joinsHost && roomy.host.attachments.first?.1 == .below,
               "With room above, the plate hangs from the host's top, behind it")
        expect(screen.contains(roomy.panel.frame), "Plate fully on screen when there is room")
        // Tight: host top at the screen top.
        let tight = make(screen: NSRect(x: -700, y: 0, width: 1400, height: 600))
        defer { tight.bevel.shutdown() }
        tight.bevel.enabled = true
        tight.bevel.modifiers(message: "Hold Shift to constrain")
        let tightView = tight.panel.contentView as! OriginalHelpBevelView
        let visible = NSRect(x: -700, y: 0, width: 1400, height: 600)
        expect(visible.contains(tight.panel.frame), "Plate stays inside the visible screen: \(tight.panel.frame) in \(visible)")
        expect(!tightView.joinsHost && tight.host.attachments.first?.1 == .above,
               "Pushed inside the host: rounded on all corners and ordered in front of it")
        expect(abs(tight.panel.frame.maxY - 600) < 0.001, "Sits flush under the screen's top edge")
        // Growing taller than the room still keeps the whole plate on screen.
        tight.bevel.modifiers(message: String(repeating: "Hold Option to sample a color, then continue drawing. ", count: 8))
        expect(visible.contains(tight.panel.frame) && tight.host.attachments.count == 1, "A long message stays on screen too, with one attachment")
        // Moving the host (reposition, not a new message) re-attaches on the other side too.
        tight.bevel.modifiers(message: "Hold Shift to constrain")
        tight.host.setFrame(NSRect(x: -700, y: 100, width: 800, height: 400), display: false)
        tight.bevel.reposition()
        expect((tight.panel.contentView as! OriginalHelpBevelView).joinsHost && tight.host.attachments.count == 1 && tight.host.attachments[0].1 == .below,
               "Host moved away from the top edge: reposition re-attaches the plate below it")
        tight.host.setFrame(NSRect(x: -700, y: 300, width: 800, height: 300), display: false)
        tight.bevel.reposition()
        expect(!(tight.panel.contentView as! OriginalHelpBevelView).joinsHost && tight.host.attachments.count == 1 && tight.host.attachments[0].1 == .above
               && visible.contains(tight.panel.frame), "Host moved to the top edge: reposition brings the plate inside, in front of it, on screen")
        // Moving the host down makes room again: the plate goes back above it.
        tight.host.setFrame(NSRect(x: -700, y: 100, width: 800, height: 400), display: false)
        tight.bevel.modifiers(message: "Hold Shift to constrain")
        expect((tight.panel.contentView as! OriginalHelpBevelView).joinsHost && tight.host.attachments.first?.1 == .below && tight.host.attachments.count == 1,
               "With room again the plate returns to hanging from the host, re-attached once")
    }

    private static func teardownAndReachability() {
        let rig = make()
        rig.bevel.enabled = true
        rig.bevel.hover(owner: "A", message: "Pending")
        let pending = rig.scheduler.latest(0.25)
        rig.bevel.modifiers(message: "Live")
        let fade = rig.scheduler.latest(0.02)
        let panel = rig.panel
        rig.bevel.shutdown()
        rig.scheduler.fire(pending, stale: true); rig.scheduler.fire(fade, stale: true)
        rig.bevel.enabled = true
        rig.bevel.hover(owner: "B", message: "Rejected")
        rig.bevel.modifiers(message: "Rejected")
        rig.bevel.reposition()
        rig.bevel.shutdown()
        expect(panel.closes == 1 && rig.bevel.panel == nil && rig.bevel.displayedMessage == nil,
               "Permanent idempotent shutdown closes exactly one owned panel")
        expect(rig.factoryCalls.count == 1 && rig.scheduler.active == 0 && rig.host.attachments.isEmpty,
               "Late events and timers cannot reopen or allocate after shutdown")
        var bevel: OriginalHelpBevel?
        weak var observedHost: HelpHost?
        autoreleasepool {
            let host = HelpHost(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
            host.isReleasedWhenClosed = false
            observedHost = host
            bevel = OriginalHelpBevel(host: host, makePanel: {
                preconditionFailure("unreachable host cannot construct panel")
            }, scheduler: rig.scheduler)
            // Close the never-ordered native host and drain AppKit's temporary
            // autoreleased registration references before checking our ownership.
            host.close()
        }
        weak let observedBevel = bevel
        expect(observedHost == nil, "Controller does not retain its parent's host")
        bevel!.enabled = true
        bevel!.modifiers(message: "Gone host")
        expect(bevel!.panel == nil && bevel!.displayedMessage == nil, "Released host safely blocks rendering")
        bevel!.shutdown(); bevel = nil
        expect(observedBevel == nil, "No scheduler or callback retains a shut down controller")
    }

    private static func nativeRunLoopModes() {
        for mode in [RunLoop.Mode.default, .modalPanel, .eventTracking] {
            let host = HelpHost(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                                styleMask: [.borderless], backing: .buffered, defer: true)
            host.isReleasedWhenClosed = false
            let bevel = OriginalHelpBevel(host: host, makePanel: {
                HelpPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            })
            bevel.enabled = true
            bevel.modifiers(message: "Mode test")
            let end = Date().addingTimeInterval(0.6)
            while bevel.panel!.alphaValue < 1 && Date() < end {
                _ = RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.03))
            }
            expect(bevel.panel!.alphaValue == 1, "Real native fade timer services \(mode.rawValue) without ordering real windows")
            bevel.shutdown()
        }
    }
}
#endif
