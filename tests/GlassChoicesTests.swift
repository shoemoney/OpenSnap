// The shared glass choice primitives (GlassChoices.swift) as behaviour: the pure placement function, the choice button's kind / state /
// accessibility semantics, the inline exclusive group, the panel host (one container, dismissal, focus restoration, only one shown) and the
// NSMenu adapter (groups, validation, close-before-perform, popup selection, submenus, keyboard). Every window is a never-ordered
// window and the host's presenter seam replaces ordering, so nothing reaches the desktop and no input is sent.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D GLASS_CHOICES_TESTS \
//   Sources/DesignTokens.swift Sources/DisplayOptions.swift Sources/DisplayOptions+ChromeAccessibility.swift Sources/OriginalActionButton.swift \
//   Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift Sources/FontAwesomeFree.swift Sources/SVGPath.swift Sources/AppToolTip.swift \
//   Sources/StateStyles.swift Sources/GlassChrome.swift Sources/GlassChoices.swift \
//   tests/ContrastProbe.swift tests/ViewTreeAudit.swift tests/AccessibilityAudit.swift tests/GlassChoicesTests.swift -o build/glass-choices-tests
#if GLASS_CHOICES_TESTS
import AppKit

/// The selected fill's alpha for the appearance a view is drawn under: 0.20 in light, 0.34 in dark (0.32 / 0.40 under Increase Contrast).
@MainActor
private func selectedAlpha(of view: NSView, hc: Bool = false) -> CGFloat {
    DesignTokens.Palette.resolve(DesignTokens.Palette.State.selectedFill, arm: StateStyles.arm(for: view.effectiveAppearance, highContrast: hc)).alphaComponent
}

// MARK: - Fixtures

/// Any attempt to order a window front or to attach a child window fails: the presenter seam must replace it.
@MainActor
private class NonorderingWindow: NSWindow {
    override func orderFront(_ sender: Any?) { preconditionFailure("No desktop windows") }
    override func orderFrontRegardless() { preconditionFailure("No desktop windows") }
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("No desktop windows") }
    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) { preconditionFailure("The presenter seam replaces ordering") }
}

@MainActor
private final class FocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private final class Log {
    var lines: [String] = []
    func add(_ line: String) { lines.append(line) }
    func index(of line: String) -> Int? { lines.firstIndex(of: line) }
    func count(_ line: String) -> Int { lines.filter { $0 == line }.count }
}

/// Menu delegate, validator and action target in one: everything it sees lands in one ordered log.
@MainActor
private final class MenuFixture: NSObject, NSMenuDelegate, NSMenuItemValidation {
    let log: Log
    var disabledTitles: Set<String> = []
    var onNeedsUpdate: ((NSMenu) -> Void)?
    var onAction: ((NSMenuItem) -> Void)?
    init(log: Log) { self.log = log }
    func menuNeedsUpdate(_ menu: NSMenu) { log.add("needsUpdate"); onNeedsUpdate?(menu) }
    func menuWillOpen(_ menu: NSMenu) { log.add("willOpen") }
    func menuDidClose(_ menu: NSMenu) { log.add("didClose") }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { log.add("validate:\(item.title)"); return !disabledTitles.contains(item.title) }
    @objc func act(_ sender: NSMenuItem) { log.add("act:\(sender.title)"); onAction?(sender) }
    @objc func popChanged(_ sender: NSPopUpButton) { log.add("popAction:\(sender.indexOfSelectedItem)") }
}

@MainActor
private final class ClickTarget: NSObject {
    var states: [NSControl.StateValue] = []
    var senders: [String] = []
    @objc func clicked(_ sender: Any?) {
        states.append((sender as? NSButton)?.state ?? .off)
        senders.append((sender as? NSView)?.identifier?.rawValue ?? "?")
    }
}

@MainActor
private final class Rig {
    static let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let window = NonorderingWindow(contentRect: NSRect(x: 200, y: 300, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    let anchor = NSButton(frame: NSRect(x: 40, y: 500, width: 80, height: 36))
    let focus = FocusView(frame: NSRect(x: 40, y: 100, width: 80, height: 30))
    let other = FocusView(frame: NSRect(x: 140, y: 100, width: 80, height: 30))
    var presented: [(GlassChoiceWindow, NSWindow?)] = []
    var panelIsKey = false

    init() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = content
        for view in [anchor, focus, other] { content.addSubview(view) }
        anchor.setAccessibilityLabel("Opener")
        _ = window.makeFirstResponder(focus)
    }

    /// Points a host at this rig: no ordering, a fixed screen, pinned display options, and a key probe the test controls.
    func attach(_ host: GlassPanelHost) {
        host.presenter = { [unowned self] panel, parent in presented.append((panel, parent)) }
        host.visibleFrameOverride = Self.visible
        host.accessibility = .none
        host.keyStateProbe = { [unowned self] in panelIsKey }
    }

    var anchorOnScreen: NSRect { window.convertToScreen(anchor.convert(anchor.bounds, to: nil)) }
}

/// A key-down the way AppKit delivers it: the arrow keys carry the numeric-pad and function flags and their private-use characters, Home / End /
/// Page keys the function flag, Return its carriage return. (A handler that rejected an event for carrying those flags would never see a real
/// arrow, and a key with no characters crashes AppKit's key-equivalent search when it reaches the window.)
private func key(_ code: UInt16, chars: String = "", modifiers: NSEvent.ModifierFlags = [], timestamp: TimeInterval = 0) -> NSEvent {
    var flags = modifiers
    var characters = chars
    switch code {
    case 123: flags.formUnion([.numericPad, .function]); if chars.isEmpty { characters = "\u{F702}" }
    case 124: flags.formUnion([.numericPad, .function]); if chars.isEmpty { characters = "\u{F703}" }
    case 125: flags.formUnion([.numericPad, .function]); if chars.isEmpty { characters = "\u{F701}" }
    case 126: flags.formUnion([.numericPad, .function]); if chars.isEmpty { characters = "\u{F700}" }
    case 115: flags.insert(.function); if chars.isEmpty { characters = "\u{F729}" }
    case 119: flags.insert(.function); if chars.isEmpty { characters = "\u{F72B}" }
    case 36, 76: if chars.isEmpty { characters = "\r" }
    case 48: if chars.isEmpty { characters = "\t" }
    case 49: if chars.isEmpty { characters = " " }
    case 53: if chars.isEmpty { characters = "\u{1B}" }
    default: break
    }
    return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: timestamp, windowNumber: 0, context: nil,
                            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
}

@MainActor
private final class LongFacePopUp: GlassPopUpButton {
    override var faceTitle: String { "A deliberately long face title that cannot possibly fit" }
}

/// An app-owned group element, as a panel's root is.
@MainActor
private final class AuditContainer: NSView {}

/// Records the key-downs that reach it: what the pop-up did not take.
@MainActor
private final class KeyProbeView: NSView {
    var keys: [UInt16] = []
    /// Let the key go on to the window, as an unhandled key does (a default button fires there); off, the probe swallows it (no beep).
    var forwardsToWindow = false
    override var acceptsFirstResponder: Bool { false }
    override func keyDown(with event: NSEvent) {
        keys.append(event.keyCode)
        if forwardsToWindow { super.keyDown(with: event) }
    }
}

private enum Keys {
    static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126, tab: UInt16 = 48, space: UInt16 = 49
    static let enter: UInt16 = 36, keypadEnter: UInt16 = 76, escape: UInt16 = 53, home: UInt16 = 115, end: UInt16 = 119
}

// MARK: - Tests

@main
@MainActor
private enum GlassChoicesTests {
    private static var checks = 0

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    private static let plain = ChromeAccessibility.none
    private static let differentiate = ChromeAccessibility(reduceTransparency: false, increaseContrast: false, reduceMotion: false, differentiateWithoutColor: true)

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        // The key-view loop follows the system's Full Keyboard Access setting; the rig pins it on, and pins the display options.
        let savedKeyboard = KeyboardNavigation.fullKeyboardAccess
        KeyboardNavigation.fullKeyboardAccess = { true }
        DisplayOptions.override = .none
        defer { KeyboardNavigation.fullKeyboardAccess = savedKeyboard; DisplayOptions.override = nil }

        labelSizingTests()
        placementTests()
        containerPlacementTests()
        containmentHostTests()
        shortcutTests()
        surfaceAxisTests()
        buttonSemanticsTests()
        buttonAppearanceTests()
        buttonLayoutTests()
        buttonSpacingKnobTests()
        rowTitleTests()
        indicatorGlyphTests()
        groupTests()
        hostTests()
        dismissalTests()
        focusRestorationTests()
        scrollingTests()
        menuBuildTests()
        menuLifecycleTests()
        menuActivationTests()
        menuKeyboardTests()
        submenuTests()
        externalTreeTests()
        menuIconTests()
        returnKeyTests()
        typeAheadTests()
        rebuiltMenuTests()
        hostReleaseTests()
        displayOptionTests()
        popUpButtonTests()
        auditTests()
        print("PASS glass-choices-tests (\(checks) checks)")
    }

    // MARK: helpers

    private static func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    private static func labels(in view: NSView) -> [NSTextField] { descendants(view).compactMap { $0 as? NSTextField } }

    private static func place(_ view: NSView, in window: NSWindow, width: CGFloat? = nil) {
        view.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(view)
        var constraints = [view.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
                           view.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20)]
        if let width { constraints.append(view.widthAnchor.constraint(equalToConstant: width)) }
        NSLayoutConstraint.activate(constraints)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// Alpha channel of an image drawn into a `scale`-pixels-per-point bitmap, rows top to bottom.
    private static func alpha(_ image: NSImage, scale: Int = 2) -> (pixels: Int, alpha: [UInt8]) {
        let pixels = Int(image.size.width) * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var values = [UInt8](repeating: 0, count: pixels * pixels)
        for y in 0..<pixels { for x in 0..<pixels { values[y * pixels + x] = rep.bitmapData![y * rep.bytesPerRow + x * 4 + 3] } }
        return (pixels, values)
    }

    /// What a label needs for `text`: an independent text-field probe, so the code under test and its test do not share a measuring path.
    private static func needed(_ text: String, _ style: DesignTokens.Typography.Style, wrap: CGFloat? = nil) -> NSSize {
        let probe = NSTextField(labelWithString: text)
        probe.font = DesignTokens.Typography.font(style)
        probe.lineBreakMode = wrap == nil ? .byTruncatingTail : .byWordWrapping
        probe.maximumNumberOfLines = wrap == nil ? 1 : 0
        probe.preferredMaxLayoutWidth = wrap ?? 0
        let size = probe.fittingSize
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private static func sameImage(_ a: NSImage?, _ b: NSImage?) -> Bool {
        guard let a, let b, a.size == b.size else { return false }
        return alpha(a).alpha == alpha(b).alpha
    }

    private static func coverage(_ image: NSImage) -> Int { alpha(image).alpha.reduce(0) { $0 + Int($1) } }

    // MARK: placement (the pure function)

    private static func placementTests() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let anchor = NSRect(x: 100, y: 400, width: 80, height: 36)
        let size = NSSize(width: 240, height: 200)

        let below = GlassPanelHost.frame(contentSize: size, anchor: anchor, preferredEdge: .minY, visible: visible)
        expect(below.edge == .minY && !below.scrolls, "A panel that fits below its anchor goes below")
        expect(below.frame == NSRect(x: 100, y: 400 - 6 - 200, width: 240, height: 200), "Below: 6 pt under the anchor, leading edges aligned (\(below.frame))")

        let above = GlassPanelHost.frame(contentSize: size, anchor: anchor, preferredEdge: .maxY, visible: visible)
        expect(above.edge == .maxY && above.frame == NSRect(x: 100, y: 436 + 6, width: 240, height: 200), "Above: 6 pt over the anchor (\(above.frame))")

        // Flips when the preferred side lacks room but the other has it.
        let lowAnchor = NSRect(x: 100, y: 60, width: 80, height: 36)
        let flippedUp = GlassPanelHost.frame(contentSize: size, anchor: lowAnchor, preferredEdge: .minY, visible: visible)
        expect(flippedUp.edge == .maxY && flippedUp.frame.minY == lowAnchor.maxY + 6 && !flippedUp.scrolls, "No room below flips above (\(flippedUp))")
        let highAnchor = NSRect(x: 100, y: 720, width: 80, height: 36)
        let flippedDown = GlassPanelHost.frame(contentSize: size, anchor: highAnchor, preferredEdge: .maxY, visible: visible)
        expect(flippedDown.edge == .minY && flippedDown.frame.maxY == highAnchor.minY - 6 && !flippedDown.scrolls, "No room above flips below (\(flippedDown))")

        // Clamps x into the visible frame with an 8 pt margin.
        let right = GlassPanelHost.frame(contentSize: size, anchor: NSRect(x: 930, y: 400, width: 60, height: 36), preferredEdge: .minY, visible: visible)
        expect(right.frame.maxX == 1000 - 8 && right.frame.width == 240, "Clamped to the right margin (\(right.frame))")
        let left = GlassPanelHost.frame(contentSize: size, anchor: NSRect(x: -30, y: 400, width: 60, height: 36), preferredEdge: .minY, visible: visible)
        expect(left.frame.minX == 8, "Clamped to the left margin (\(left.frame))")
        let offsetVisible = NSRect(x: 1440, y: 100, width: 1000, height: 800)
        let second = GlassPanelHost.frame(contentSize: size, anchor: NSRect(x: 1400, y: 400, width: 60, height: 36), preferredEdge: .minY, visible: offsetVisible)
        expect(second.frame.minX == 1448, "The margin is measured from the visible frame of a second screen (\(second.frame))")

        // Caps the height to the room on the chosen side and scrolls. The larger side wins when neither fits.
        let tall = NSSize(width: 240, height: 900)
        let capped = GlassPanelHost.frame(contentSize: tall, anchor: anchor, preferredEdge: .minY, visible: visible)
        expect(capped.scrolls && capped.edge == .minY, "A panel taller than both sides scrolls on the larger side (below has 386, above has 350): \(capped)")
        expect(capped.frame.height == 400 - 6 - 8 && capped.frame.minY == 8, "The capped height is exactly the room below, down to the 8 pt margin (\(capped.frame))")
        let cappedUp = GlassPanelHost.frame(contentSize: tall, anchor: NSRect(x: 100, y: 300, width: 80, height: 36), preferredEdge: .minY, visible: visible)
        expect(cappedUp.scrolls && cappedUp.edge == .maxY && cappedUp.frame.maxY == 800 - 8, "The side with more room takes the capped panel (\(cappedUp))")
        let exact = GlassPanelHost.frame(contentSize: NSSize(width: 240, height: 386), anchor: anchor, preferredEdge: .minY, visible: visible)
        expect(!exact.scrolls && exact.frame.height == 386, "A panel exactly as tall as the room does not scroll")
        let wide = GlassPanelHost.frame(contentSize: NSSize(width: 2000, height: 100), anchor: anchor, preferredEdge: .minY, visible: visible)
        expect(wide.frame.width == 1000 - 16 && wide.frame.minX == 8, "A panel wider than the screen is cut to the margins (\(wide.frame))")

        // Alignment.
        let centered = GlassPanelHost.frame(contentSize: size, anchor: anchor, preferredEdge: .minY, visible: visible, alignment: .center)
        expect(centered.frame.midX == anchor.midX, "Centre alignment centres on the anchor")
        let trailing = GlassPanelHost.frame(contentSize: size, anchor: anchor, preferredEdge: .minY, visible: visible, alignment: .trailing)
        expect(trailing.frame.maxX == anchor.maxX || trailing.frame.minX == 8, "Trailing alignment ends at the anchor's trailing edge")

        // Sideways.
        let beside = GlassPanelHost.frame(contentSize: size, anchor: anchor, preferredEdge: .maxX, visible: visible)
        expect(beside.edge == .maxX && beside.frame.minX == anchor.maxX + 6 && beside.frame.maxY == anchor.maxY, "Sideways: 6 pt to the right, tops aligned (\(beside.frame))")
        let besideFlipped = GlassPanelHost.frame(contentSize: size, anchor: NSRect(x: 900, y: 400, width: 80, height: 36), preferredEdge: .maxX, visible: visible)
        expect(besideFlipped.edge == .minX && besideFlipped.frame.maxX == 900 - 6, "No room on the right flips to the left (\(besideFlipped))")

        // The invariant, over a grid: the frame is always inside the visible frame less its margin, and never taller than the content.
        var checked = 0
        let area = visible.insetBy(dx: 8, dy: 8)
        for anchorX in stride(from: -40.0, through: 1000.0, by: 130.0) {
            for anchorY in stride(from: -20.0, through: 800.0, by: 97.0) {
                for height in [60.0, 200.0, 500.0, 760.0, 1200.0] {
                    for edge in [NSRectEdge.minY, .maxY, .minX, .maxX] {
                        let result = GlassPanelHost.frame(contentSize: NSSize(width: 300, height: height), anchor: NSRect(x: anchorX, y: anchorY, width: 70, height: 36),
                                                          preferredEdge: edge, visible: visible)
                        expect(area.insetBy(dx: -0.001, dy: -0.001).contains(result.frame), "Inside the visible frame for anchor (\(anchorX), \(anchorY)) height \(height) edge \(edge.rawValue): \(result.frame)")
                        expect(result.frame.height <= height + 0.001 && result.scrolls == (result.frame.height < height - 0.001), "scrolls says whether the panel was cut: \(result)")
                        checked += 1
                    }
                }
            }
        }
        expect(checked > 800, "The placement grid ran (\(checked) cases)")
    }


    // MARK: placement inside the parent window

    /// The panel stays inside the window it was opened from whenever it fits: an opener near the window's right edge gets a panel that ends at
    /// the opener's trailing edge, not one that hangs far out past the window.
    private static func containerPlacementTests() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let container = NSRect(x: 200, y: 100, width: 600, height: 500)   // x 200...800
        let size = NSSize(width: 240, height: 200)
        func place(_ anchor: NSRect, edge: NSRectEdge = .minY, alignment: GlassPanelHost.Alignment = .leading, in container: NSRect? = container,
                   screen: NSRect = visible, size: NSSize = size) -> GlassPanelHost.Placement {
            GlassPanelHost.frame(contentSize: size, anchor: anchor, preferredEdge: edge, visible: screen, alignment: alignment, container: container)
        }

        // 1. An opener near the container's right edge: the panel ends at the opener's trailing edge, inside the container.
        let right = NSRect(x: 700, y: 400, width: 80, height: 36)
        func same(_ a: GlassPanelHost.Placement, _ b: GlassPanelHost.Placement) -> Bool { a.frame == b.frame && a.edge == b.edge && a.scrolls == b.scrolls }
        let nearRight = place(right)
        let leadingOnly = place(right, in: nil)
        expect(leadingOnly.containment == .screenFallback, "(setup) without a container nothing is contained")
        expect(leadingOnly.frame.maxX == 940 && leadingOnly.frame.maxX > container.maxX, "(setup) leading-only would hang out 140 pt past the window (\(leadingOnly.frame))")
        expect(nearRight.frame.maxX <= container.maxX && nearRight.frame.maxX == right.maxX && nearRight.frame.width == 240 && nearRight.containment == .parent,
               "Near the container's right edge, with the window fully on screen, the panel is trailing-aligned, inside the container, and contained (\(nearRight))")
        expect(nearRight.frame.minY == leadingOnly.frame.minY && nearRight.frame.height == leadingOnly.frame.height && nearRight.edge == leadingOnly.edge && nearRight.scrolls == leadingOnly.scrolls,
               "...with the vertical placement untouched")
        // The same from a bottom-right opener whose panel flips above, and from an opener that would hang out by only a little.
        let bottomRight = place(NSRect(x: 700, y: 110, width: 80, height: 36))
        expect(bottomRight.edge == .maxY && bottomRight.frame.maxX == 780 && bottomRight.frame.maxX <= container.maxX, "A bottom-right opener flips the panel above and still keeps it inside (\(bottomRight))")
        let slight = place(NSRect(x: 570, y: 400, width: 80, height: 36))
        expect(slight.frame.maxX == 650 && slight.frame.maxX <= container.maxX, "An opener that overflows by 10 pt also switches to the trailing edge (\(slight.frame))")

        // 2. An opener near the left edge, and one in the middle, are unchanged.
        for anchor in [NSRect(x: 210, y: 400, width: 80, height: 36), NSRect(x: 400, y: 400, width: 80, height: 36)] {
            expect(same(place(anchor), place(anchor, in: nil)) && place(anchor).frame.minX == anchor.minX && place(anchor).containment == .parent,
                   "A panel that fits leading-aligned inside the container is unchanged, and is contained (\(place(anchor).frame))")
        }

        // An explicit alignment is the first try: trailing near the left edge flips to leading, centre near either edge takes the side that fits.
        let left = NSRect(x: 210, y: 400, width: 80, height: 36)
        expect(place(left, alignment: .trailing).frame.minX == left.minX, "Trailing near the left edge overflows the container, so leading is used (\(place(left, alignment: .trailing).frame))")
        expect(place(NSRect(x: 400, y: 400, width: 80, height: 36), alignment: .trailing).frame.maxX == 480, "Trailing that fits stays trailing")
        expect(place(left, alignment: .center).frame.minX == left.minX, "Centre near the left edge takes leading")
        expect(place(right, alignment: .center).frame.maxX == right.maxX, "Centre near the right edge takes trailing")
        expect(place(NSRect(x: 400, y: 400, width: 80, height: 36), alignment: .center).frame.midX == 440, "Centre that fits stays centred")

        // 3. Neither alignment fits the container but the panel does: clamped into it.
        let narrow = NSRect(x: 200, y: 100, width: 300, height: 500)   // x 200...500
        let squeezed = place(NSRect(x: 400, y: 400, width: 20, height: 36), in: narrow)
        expect(squeezed.frame.minX == 260 && squeezed.frame.maxX == narrow.maxX, "Neither edge fits a 300 pt container, so the panel is clamped into it (\(squeezed.frame))")

        // 4. A panel wider than the container falls back to the screen rules alone.
        let tiny = NSRect(x: 200, y: 100, width: 200, height: 500)
        for anchor in [NSRect(x: 210, y: 400, width: 80, height: 36), NSRect(x: 350, y: 400, width: 40, height: 36)] {
            expect(same(place(anchor, in: tiny), place(anchor, in: nil)) && place(anchor, in: tiny).containment == .screenFallback,
                   "A panel wider than the container (240 vs 200) is placed by the screen rules alone and says so (\(place(anchor, in: tiny).frame))")
        }
        expect(place(NSRect(x: 900, y: 400, width: 80, height: 36), in: tiny).frame.maxX == 992, "...and the screen margin still clamps it")

        // 5. The container reaching past the screen edge: the screen margin is still the final clamp.
        let overhang = NSRect(x: 600, y: 100, width: 600, height: 500)   // x 600...1200, the screen ends at 1000
        let onScreenEdge = place(NSRect(x: 900, y: 400, width: 80, height: 36), in: overhang)
        expect(onScreenEdge.frame.maxX <= 1000 - 8 && onScreenEdge.frame.maxX == 980, "A container that overhangs the screen is only as roomy as the screen: leading would pass the margin, so the panel ends at the opener (\(onScreenEdge.frame))")
        let atEdge = NSRect(x: 400, y: 100, width: 600, height: 500)     // x 400...1000, exactly the screen edge
        let edgeOpener = place(NSRect(x: 915, y: 400, width: 80, height: 36), in: atEdge)
        expect(edgeOpener.frame.maxX == 992 && edgeOpener.frame.minX >= atEdge.minX, "A window flush with the screen edge: the panel ends at the screen margin, not at the window edge (\(edgeOpener.frame))")
        let offLeft = NSRect(x: -100, y: 100, width: 600, height: 500)   // x -100...500, partly off the screen
        let leftEdge = place(NSRect(x: -90, y: 400, width: 80, height: 36), in: offLeft)
        expect(leftEdge.frame.minX == 8 && leftEdge.frame.maxX <= offLeft.maxX && leftEdge.containment == .parent,
               "A window half off the left of the screen: the panel fits the part that shows, so it is contained in it, at the screen margin (\(leftEdge))")
        let offLeftRight = place(NSRect(x: 400, y: 400, width: 80, height: 36), in: offLeft)
        expect(offLeftRight.frame.maxX == 480 && offLeftRight.frame.minX >= 8 && offLeftRight.containment == .parent, "...and an opener near the window's right edge there is trailing-aligned (\(offLeftRight))")
        let sliver = NSRect(x: -200, y: 100, width: 300, height: 500)    // only x 8...100 shows: too narrow for the 240 pt panel
        for anchor in [NSRect(x: -190, y: 400, width: 80, height: 36), NSRect(x: 20, y: 400, width: 40, height: 36)] {
            let narrowPart = place(anchor, in: sliver)
            expect(narrowPart.containment == .screenFallback && narrowPart.frame.minX >= 8 && narrowPart.frame.maxX <= 992 && narrowPart.frame.width == 240,
                   "A window whose visible part is too narrow falls back to the screen, fully visible (\(narrowPart))")
        }
        let tooWide = place(NSRect(x: 900, y: 400, width: 80, height: 36), in: tiny)
        expect(tooWide.containment == .screenFallback && tooWide.frame.minX >= 8 && tooWide.frame.maxX <= 992, "A panel wider than the parent is .screenFallback and fully on screen (\(tooWide))")

        // Sideways panels (left or right of the anchor) ignore the container, as before.
        let beside = place(right, edge: .maxX)
        expect(same(beside, place(right, edge: .maxX, in: nil)) && beside.containment == .screenFallback, "A panel beside its anchor is placed as before and is not a containment case")

        // Over a grid: the vertical result is identical with and without the container, and a panel that fits the container and whose opener is
        // inside it is always inside it.
        var checked = 0, insideChecked = 0
        let window = NSRect(x: 100, y: 50, width: 700, height: 650)
        for anchorX in stride(from: 100.0, through: 720.0, by: 31.0) {
            for anchorY in stride(from: 60.0, through: 640.0, by: 83.0) {
                for height in [60.0, 200.0, 500.0, 900.0] {
                    for panelWidth in [120.0, 240.0, 420.0, 760.0] {
                        for alignment in [GlassPanelHost.Alignment.leading, .center, .trailing] {
                            let anchor = NSRect(x: anchorX, y: anchorY, width: 80, height: 36)
                            let content = NSSize(width: panelWidth, height: height)
                            let with = place(anchor, alignment: alignment, in: window, size: content), without = place(anchor, alignment: alignment, in: nil, size: content)
                            expect(with.edge == without.edge && with.scrolls == without.scrolls && with.frame.minY == without.frame.minY && with.frame.height == without.frame.height
                                   && with.frame.width == without.frame.width, "The container never changes the vertical rules or the size (anchor \(anchor), \(content), \(alignment))")
                            expect((with.containment == .parent) == (content.width <= window.width), "containment says whether the panel was containable: width \(panelWidth) in a \(window.width) pt window gives \(with.containment)")
                            expect(visible.insetBy(dx: 8, dy: 8).insetBy(dx: -0.001, dy: -0.001).contains(with.frame), "...and the screen margin always holds: \(with.frame)")
                            if panelWidth <= window.width, anchor.minX >= window.minX, anchor.maxX <= window.maxX {
                                expect(with.frame.minX >= window.minX - 0.001 && with.frame.maxX <= window.maxX + 0.001,
                                       "A panel that fits the window, opened from inside it, stays inside it: anchor \(anchor) width \(panelWidth) \(alignment) gives \(with.frame)")
                                insideChecked += 1
                            }
                            checked += 1
                        }
                    }
                }
            }
        }
        expect(checked > 1500 && insideChecked > 700, "The container grid ran (\(checked) cases, \(insideChecked) inside checks)")
    }


    /// The host passes the window the anchor sits in: a panel opened from the right edge of its window stays inside it, and says so.
    private static func containmentHostTests() {
        let rig = Rig()
        let right = NSButton(frame: NSRect(x: 700, y: 500, width: 80, height: 36))      // content x 700...780 of 800
        rig.window.contentView?.addSubview(right)
        let host = GlassPanelHost(plates: [plate(["Alpha", "A rather longer second row"])], identifier: "Contain", accessibilityLabel: "Contain")
        rig.attach(host)
        let panel = host.window
        func screenFrame(of view: NSView) -> NSRect { rig.window.convertToScreen(view.convert(view.bounds, to: nil)) }

        host.show(relativeTo: right.bounds, of: right, preferredEdge: .minY, makeKey: true)
        let opener = screenFrame(of: right)
        expect(opener.minX + panel.frame.width > rig.window.frame.maxX, "(setup) a leading-aligned panel would hang out past the window (opener \(opener), panel width \(panel.frame.width), window \(rig.window.frame))")
        expect(panel.frame.maxX <= rig.window.frame.maxX + 0.001 && abs(panel.frame.maxX - opener.maxX) < 0.5 && host.placement?.containment == .parent,
               "An opener at the window's right edge gets a trailing-aligned panel inside the window: panel \(panel.frame), window \(rig.window.frame), containment \(String(describing: host.placement?.containment))")
        host.close()

        // The same host from an opener near the left edge is leading-aligned as before.
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        expect(abs(panel.frame.minX - rig.anchorOnScreen.minX) < 0.5 && host.placement?.containment == .parent, "An opener near the left edge keeps a leading-aligned panel, contained")
        host.close()

        // Following the window: when it moves the panel is re-placed against its new frame.
        host.show(relativeTo: right.bounds, of: right, preferredEdge: .minY, makeKey: true)
        rig.window.setFrameOrigin(NSPoint(x: rig.window.frame.minX + 100, y: rig.window.frame.minY))
        host.revalidate()
        expect(host.isShown && panel.frame.maxX <= rig.window.frame.maxX + 0.001 && abs(panel.frame.maxX - screenFrame(of: right).maxX) < 0.5, "After the window moves the panel is still inside it (\(panel.frame) vs \(rig.window.frame))")
        host.close()

        // A panel wider than its window is a legitimate fallback: placed by the screen alone, fully visible, and it says so.
        host.minimumWidth = 900
        host.show(relativeTo: right.bounds, of: right, preferredEdge: .minY, makeKey: true)
        expect(host.placement?.containment == .screenFallback && panel.frame.width >= 900 - 0.5, "(setup) a 900 pt panel does not fit an 800 pt window")
        expect(Rig.visible.insetBy(dx: 8, dy: 8).insetBy(dx: -0.001, dy: -0.001).contains(panel.frame), "...and falls back to the screen: fully on screen (\(panel.frame))")
        host.close()
        host.minimumWidth = 0
        right.removeFromSuperview()
    }

    // MARK: shortcut text

    private static func shortcutTests() {
        func text(_ key: String, _ mask: NSEvent.ModifierFlags) -> String? { MenuShortcut.text(keyEquivalent: key, modifiers: mask) }
        expect(text("a", .command) == "⌘A", "Command-A")
        expect(text("B", .command) == "⇧⌘B", "An upper-case key implies shift")
        expect(text("z", [.command, .shift]) == "⇧⌘Z", "Shift is written once, before command")
        expect(text("k", [.control, .option, .shift, .command]) == "⌃⌥⇧⌘K", "Control, option, shift, command, in menu order")
        expect(text("", .command) == nil, "No key equivalent, no text")
        expect(text("\r", .command) == "⌘\u{21A9}\u{FE0E}", "Return uses the text-presentation return glyph")
        expect(text(" ", []) == "Space" && text("\u{F700}", .command) == "⌘Up" && text("\u{F703}", .command) == "⌘Right", "Named keys are spelled out")
        expect(text("\u{7F}", .command) == "⌘Delete" && text("\u{F704}", []) == "F1" && text("\u{F70F}", []) == "F12", "Delete and function keys")
        expect(text("\t", []) == "⇥" && text("\u{1B}", []) == "⎋", "Tab and Escape key caps")
        let item = NSMenuItem(title: "Item", action: nil, keyEquivalent: "d")
        item.keyEquivalentModifierMask = [.command, .option]
        expect(MenuShortcut.text(for: item) == "⌥⌘D", "The item form reads the key equivalent and its modifier mask")
        expect(MenuShortcut.text(for: NSMenuItem(title: "Plain", action: nil, keyEquivalent: "")) == nil, "An item with no key equivalent has no text")
    }

    // MARK: plate axis

    private static func surfaceAxisTests() {
        let window = NonorderingWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))

        // Horizontal stays the bar plate: one fixed 44 pt row, whatever the content.
        let bars = [NSButton(title: "A", target: nil, action: nil), NSButton(title: "B", target: nil, action: nil)]
        for bar in bars { GlassChrome.fix(bar, NSSize(width: 48, height: 36)) }
        let horizontal = GlassChrome.plate(bars, identifier: "H", accessibility: plain)
        place(horizontal, in: window)
        expect(horizontal.axis == .horizontal && horizontal.frame.height == 44 && horizontal.frame.width == 48 * 2 + 2 + 8, "A horizontal plate is the 44 pt bar row (\(horizontal.frame))")
        expect(bars[0].frame.minX == 4 && bars[1].frame.minX == 4 + 48 + 2 && bars[0].frame.midY == horizontal.frame.height / 2, "...with its controls centred on the row")

        // Vertical: rows keep their own height, every row takes the plate's inner width, and the height comes from the content.
        let rows = [("Short", 100), ("A considerably longer row", 260), ("Mid", 140)].map { title, width -> NSView in
            let row = NSView(); row.translatesAutoresizingMaskIntoConstraints = false
            row.addConstraint(row.heightAnchor.constraint(equalToConstant: 36))
            let intrinsic = row.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(width)); intrinsic.priority = .defaultHigh; intrinsic.isActive = true
            row.identifier = NSUserInterfaceItemIdentifier(title)
            return row
        }
        let vertical = GlassChrome.plate(rows, identifier: "V", accessibility: plain, axis: .vertical)
        place(vertical, in: window)
        expect(vertical.axis == .vertical, "The axis is kept")
        expect(vertical.frame.height == 3 * 36 + 2 * 2 + 8, "A vertical plate's height is its content: three rows, two 2 pt gaps and the 4 pt insets (\(vertical.frame.height))")
        expect(rows.allSatisfy { abs($0.frame.width - (vertical.frame.width - 8)) < 0.5 && $0.frame.minX == 4 }, "Every row takes the plate's inner width (\(rows.map { $0.frame.width }) in \(vertical.frame.width))")
        expect(rows.map { $0.frame.maxY }.sorted(by: >) == rows.map { $0.frame.maxY }, "Rows stack top to bottom in the order given")
        expect(vertical.frame.width >= 260 + 8 - 0.5, "The widest row sets the plate width (\(vertical.frame.width))")

        // Any single view goes on a vertical plate (a swatch grid): it keeps its own size and the plate wraps it.
        let grid = NSView(); grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([grid.widthAnchor.constraint(equalToConstant: 200), grid.heightAnchor.constraint(equalToConstant: 96)])
        let gridPlate = GlassChrome.plate([grid], identifier: "Grid", accessibility: plain, axis: .vertical)
        place(gridPlate, in: window)
        expect(gridPlate.frame.size == NSSize(width: 208, height: 104) && grid.frame.size == NSSize(width: 200, height: 96), "A lone fixed-size view sits on a vertical plate (\(gridPlate.frame))")

        // The default init is still the bar plate.
        let legacy = GlassSurfaceView(views: [NSButton(title: "A", target: nil, action: nil)], accessibility: plain)
        expect(legacy.axis == .horizontal, "GlassSurfaceView defaults to the horizontal axis")
    }

    // MARK: button semantics

    private static func makeButton(_ title: String, _ kind: GlassChoiceButton.Kind, indicator: GlassChoiceButton.Indicator? = nil,
                                   layout: GlassChoiceButton.Layout = .row, target: ClickTarget? = nil) -> GlassChoiceButton {
        let button = GlassChoiceButton(title: title, kind: kind, indicator: indicator, layout: layout)
        button.accessibility = plain
        if let target { button.target = target; button.action = #selector(ClickTarget.clicked(_:)) }
        return button
    }

    private static func buttonSemanticsTests() {
        // command: never changes state.
        let target = ClickTarget()
        let command = makeButton("Copy", .command, target: target)
        command.performClick(nil)
        command.performClick(nil)
        expect(target.states == [.off, .off] && command.state == .off && !command.isChosen, "A command sends its action and never changes state")

        // option: becomes chosen, never un-chooses, sends every time.
        let optionTarget = ClickTarget()
        let option = makeButton("Fit", .option, target: optionTarget)
        option.performClick(nil)
        expect(option.isChosen && option.state == .on && optionTarget.states == [.on], "Clicking an option chooses it, and the handler already sees state == .on")
        option.performClick(nil)
        expect(option.isChosen && option.state == .on && optionTarget.states == [.on, .on], "Clicking a chosen option keeps it chosen and still sends")

        // toggle: flips, then sends, so a handler reading sender.state sees the new value.
        let toggleTarget = ClickTarget()
        let toggle = makeButton("Lock", .toggle, indicator: .checkbox, target: toggleTarget)
        toggle.performClick(nil)
        expect(toggle.isChosen && toggleTarget.states == [.on], "A toggle flips on, then sends")
        toggle.performClick(nil)
        expect(!toggle.isChosen && toggleTarget.states == [.on, .off], "A toggle flips off, then sends (the handler read .off)")

        toggleSingleFlipTests()

        // submenu rows are commands as far as state goes.
        let submenuTarget = ClickTarget()
        let submenu = makeButton("More", .submenu, target: submenuTarget)
        submenu.performClick(nil)
        expect(!submenu.isChosen && submenuTarget.states == [.off], "A submenu row sends and keeps its state")

        // isChosen mirrors state both ways.
        let mirror = makeButton("Mirror", .option)
        mirror.state = .on
        expect(mirror.isChosen, "Assigning state moves isChosen")
        mirror.isChosen = false
        expect(mirror.state == .off, "Assigning isChosen moves state")

        // Disabled: no action, no state change, dimmed, not focusable, hidden from accessibility as enabled.
        let disabledTarget = ClickTarget()
        let disabled = makeButton("Gone", .toggle, target: disabledTarget)
        disabled.isEnabled = false
        disabled.performClick(nil)
        expect(!disabled.sendAction(disabled.action, to: disabled.target), "A disabled button refuses a programmatic action")
        expect(disabledTarget.states.isEmpty && !disabled.isChosen, "A disabled toggle neither sends nor flips")
        expect(!disabled.acceptsFirstResponder && !disabled.canBecomeKeyView && !disabled.isAccessibilityEnabled(), "A disabled button takes no focus and is not an enabled accessibility element")
        expect(disabled.alphaValue == StateStyles.disabledAlpha, "A disabled button uses the shared disabled alpha (\(disabled.alphaValue))")
        disabled.isEnabled = true
        expect(disabled.acceptsFirstResponder && disabled.alphaValue == 1 && disabled.isAccessibilityEnabled(), "Enabling it restores focus, alpha and accessibility")

        // Accessibility roles and values by kind.
        let roles: [(GlassChoiceButton.Kind, NSAccessibility.Role)] = [(.command, .button), (.option, .radioButton), (.toggle, .checkBox), (.submenu, .menuButton)]
        for (kind, role) in roles {
            let button = makeButton("Named", kind)
            expect(button.accessibilityRole() == role, "\(kind) reads as \(role.rawValue)")
            expect(button.accessibilityLabel() == "Named", "\(kind) is labelled with its title")
            switch kind {
            case .option, .toggle:
                expect((button.accessibilityValue() as? NSNumber) == 0, "\(kind) has value 0 when off")
                button.isChosen = true
                expect((button.accessibilityValue() as? NSNumber) == 1, "\(kind) has value 1 when chosen")
            default:
                expect(button.accessibilityValue() == nil, "\(kind) has no value")
            }
        }
        let retitled = makeButton("Before", .command)
        retitled.title = "After"
        expect(retitled.title == "After" && retitled.titleLabel.stringValue == "After" && retitled.accessibilityLabel() == "After", "Retitling updates the label and the spoken name")
        // The words are drawn once, by the label: no tooltip repeats them, and the cell draws no title of its own.
        expect(AppToolTip.text(for: retitled) == nil && retitled.toolTip == nil, "No derived tooltip duplicates the visible title")
        expect(retitled.visibleTitle.isEmpty && retitled.image == nil, "The cell itself draws neither a title nor an image")
        let helped = makeButton("Helped", .command)
        helped.setAccessibilityHelp("Does the thing")
        expect(helped.accessibilityHelp() == "Does the thing", "Accessibility help is kept")
        expect(helped.accessibilityChildren()?.isEmpty == true, "The row's label and glyphs are not separate accessibility elements")

        // A row is clicked anywhere on it, including over its label.
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        let big = makeButton("Wide row with a label", .command)
        big.frame = NSRect(x: 10, y: 10, width: 280, height: 36)
        holder.addSubview(big)
        big.layoutSubtreeIfNeeded()
        expect(holder.hitTest(NSPoint(x: 30, y: 28)) === big && holder.hitTest(NSPoint(x: 150, y: 28)) === big, "A click over the label or glyph column lands on the button")
        expect(holder.hitTest(NSPoint(x: 5, y: 5)) !== big, "A click outside the row does not")
        expect(big.acceptsFirstMouse(for: nil), "The first click on an inactive panel works")

        // A key handler sees keys first and can consume them.
        let handled = makeButton("Keyed", .command)
        var seen: [UInt16] = []
        handled.keyHandler = { event in seen.append(event.keyCode); return event.keyCode == Keys.down }
        handled.keyDown(with: key(Keys.down))
        expect(seen == [Keys.down], "The key handler is offered the key")
    }

    /// AppKit flips a button's cell on every click behind the `state` property; the button owns its value, so ONE activation moves a
    /// toggle exactly one step on every path, and the handler sees the new value.
    private static func toggleSingleFlipTests() {
        let rig = Rig()
        let target = ClickTarget()
        let toggle = makeButton("Lock", .toggle, indicator: .checkbox, target: target)
        toggle.frame = NSRect(x: 300, y: 300, width: 200, height: 36)
        rig.window.contentView?.addSubview(toggle)
        toggle.layoutSubtreeIfNeeded()

        toggle.state = .on
        toggle.performClick(nil)
        expect(toggle.state == .off && !toggle.isChosen && target.states == [.off], "performClick on an on toggle turns it off, and the handler saw off (\(target.states))")
        toggle.performClick(nil)
        expect(toggle.state == .on && toggle.isChosen && target.states == [.off, .on], "...and the next click turns it back on (\(target.states))")
        toggle.performClick(nil)
        toggle.performClick(nil)
        expect(toggle.state == .on && target.states == [.off, .on, .off, .on], "Four clicks are four flips")

        // VoiceOver's press.
        target.states = []
        expect(toggle.accessibilityPerformPress(), "The accessibility press is performed")
        expect(toggle.state == .off && target.states == [.off], "accessibilityPerformPress flips a toggle exactly once (\(target.states))")
        _ = toggle.accessibilityPerformPress()
        expect(toggle.state == .on && target.states == [.off, .on], "...and again")

        // Space on the focused toggle.
        target.states = []
        _ = rig.window.makeFirstResponder(toggle)
        toggle.keyDown(with: key(Keys.space, chars: " "))
        expect(toggle.state == .off && target.states == [.off], "Space flips a toggle exactly once (\(target.states))")
        toggle.keyDown(with: key(Keys.space, chars: " "))
        expect(toggle.state == .on && target.states == [.off, .on], "...and again")

        // A real press and release through the button's own tracking loop.
        target.states = []
        let centre = toggle.convert(NSPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: nil)
        func click() {
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: centre, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: rig.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: centre, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: rig.window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
            NSApp.postEvent(up, atStart: false)
            toggle.mouseDown(with: down)
        }
        click()
        expect(toggle.state == .off && target.states == [.off], "A mouse click flips a toggle exactly once (\(target.states))")
        click()
        expect(toggle.state == .on && target.states == [.off, .on], "...and again")

        // The report that a toggle clicked twice stayed off: a button that was never in a window, three clicks from off.
        let loneTarget = ClickTarget()
        let lone = makeButton("Lone", .toggle, indicator: .checkbox, target: loneTarget)
        lone.performClick(nil)
        lone.performClick(nil)
        lone.performClick(nil)
        expect(loneTarget.states == [.on, .off, .on] && lone.state == .on, "A toggle outside any window: performClick x3 reads on, off, on and ends on (\(loneTarget.states))")
        _ = lone.accessibilityPerformPress()
        _ = lone.accessibilityPerformPress()
        expect(loneTarget.states == [.on, .off, .on, .off, .on] && lone.state == .on, "...and so does the accessibility press (\(loneTarget.states))")
        let inWindow = ClickTarget()
        let placed = makeButton("Placed", .toggle, indicator: .checkbox, target: inWindow)
        placed.frame = NSRect(x: 300, y: 250, width: 200, height: 36)
        rig.window.contentView?.addSubview(placed)
        for _ in 0..<3 { placed.performClick(nil) }
        expect(inWindow.states == [.on, .off, .on] && placed.state == .on, "A toggle in a window: performClick x3 reads on, off, on (\(inWindow.states))")
        _ = rig.window.makeFirstResponder(placed)
        placed.keyDown(with: key(Keys.space, chars: " "))
        placed.keyDown(with: key(Keys.space, chars: " "))
        expect(inWindow.states == [.on, .off, .on, .off, .on] && placed.state == .on, "...and Space with the button as first responder flips once per press (\(inWindow.states))")
        placed.removeFromSuperview()

        // Programmatic writes never send.
        target.states = []
        toggle.state = .off
        toggle.isChosen = true
        toggle.isChosen = false
        expect(target.states.isEmpty && !toggle.isChosen, "Assigning state or isChosen never sends the action")

        // A command is never moved by a click, whatever AppKit does underneath; an option never un-chooses.
        let commandTarget = ClickTarget()
        let command = makeButton("Copy", .command, target: commandTarget)
        command.performClick(nil)
        _ = command.accessibilityPerformPress()
        expect(command.state == .off && commandTarget.states == [.off, .off], "A command stays off through every click")
        command.state = .on
        command.performClick(nil)
        expect(command.state == .on && commandTarget.states.last == .on, "A command that was set on stays on through a click")
        let optionTarget = ClickTarget()
        let option = makeButton("Fit", .option, target: optionTarget)
        option.isChosen = true
        option.performClick(nil)
        _ = option.accessibilityPerformPress()
        option.keyDown(with: key(Keys.space, chars: " "))
        expect(option.state == .on && optionTarget.states == [.on, .on, .on], "A click never un-chooses an option, on any path (\(optionTarget.states))")
        let unchosen = makeButton("Fit", .option, target: ClickTarget())
        unchosen.performClick(nil)
        expect(unchosen.isChosen, "Clicking an unchosen option chooses it")
        rig.window.contentView?.subviews.forEach { if $0 === toggle { $0.removeFromSuperview() } }
    }

    // MARK: button appearance

    private static func buttonAppearanceTests() {
        let button = makeButton("Fit to window", .option)
        button.shortcutText = "⌘9"
        expect(button.titleLabel.font == DesignTokens.Typography.font(.body) && button.titleLabel.font?.pointSize == 20, "The title is 20 pt body text")
        expect(button.shortcutLabel.font == DesignTokens.Typography.font(.body) && button.shortcutLabel.stringValue == "⌘9", "The shortcut is 20 pt text")
        button.isChosen = true
        expect(button.titleLabel.font == DesignTokens.Typography.font(.bodyStrong), "A chosen title is the semibold face")

        // The selected look is the shared command-selected style: accent fill, 1 pt accent border, strong text.
        let appearance = button.effectiveAppearance
        let expected = StateStyles.command(.selected, primary: false, focused: false, highContrast: false, differentiate: false, selected: true, appearance: appearance)
        expect(button.plate.stateStyle == expected, "A chosen button draws StateStyles.command selected")
        expect(button.plate.style.fill != nil && button.plate.style.borderWidth == 1 && button.plate.style.border != nil, "...as a fill and a 1 pt border")
        expect(abs((button.plate.style.fill?.usingColorSpace(.sRGB)?.alphaComponent ?? 0) - selectedAlpha(of: button)) < 0.005, "...at the accent fill (0.20 light, 0.34 dark)")
        expect(button.plate.stateStyle.strongText, "...with strong text")
        expect(!button.showsIndicator, "The capsule is only for Differentiate Without Color")
        button.accessibility = differentiate
        expect(button.showsIndicator && !button.indicatorLayer.isHidden, "Differentiate Without Color adds the capsule to a chosen button")
        button.isChosen = false
        expect(!button.showsIndicator && button.plate.style.fill == nil && button.plate.style.borderWidth == 0, "An unchosen button is bare at rest")
        expect(button.titleLabel.font == DesignTokens.Typography.font(.body), "...and its title returns to the regular face")

        // Hover and press keep the selection; shortcut text takes the content colour while chosen and the secondary colour otherwise.
        button.accessibility = plain
        button.isChosen = true
        button.setHovered(true)
        expect(button.plate.stateStyle == StateStyles.command(.hover, primary: false, focused: false, highContrast: false, differentiate: false, selected: true, appearance: appearance),
               "Hovering a chosen button keeps the selected look")
        expect(button.shortcutLabel.textColor == button.plate.stateStyle.content, "A chosen row's shortcut takes the content colour")
        button.isChosen = false
        button.setHovered(false)
        expect(button.shortcutLabel.textColor == DesignTokens.Palette.Text.secondary, "An unchosen row's shortcut is secondary text")
        expect(button.titleLabel.textColor == button.plate.stateStyle.content, "The title takes the state's content colour")

        // Every text in the choice views is at least the 18 pt floor, and the body text is 20.
        let group = GlassChoiceGroup(titles: ["One", "Two"], accessibilityLabel: "Pair", identifier: "pair", accessibility: plain)
        let heading = GlassChoiceLabel(title: "Section")
        for text in labels(in: group) + labels(in: heading) + [button.titleLabel, button.shortcutLabel] {
            expect((text.font?.pointSize ?? 0) >= DesignTokens.Typography.readableMinimum, "Text is at least 18 pt: \(text.stringValue)")
            expect(text.font?.pointSize == 20, "Choice text is 20 pt: \(text.stringValue)")
        }
        expect(heading.title == "Section" && heading.accessibilityRole() == .staticText, "A section header is a static label")
    }

    // MARK: button layout

    /// `horizontalPadding` and `contentGap` are per-button knobs for a crowded bar: they default to the roomy values and, when tightened, move
    /// the measured width and the laid-out content by exactly the same amounts, so what is budgeted is what is drawn.
    private static func buttonSpacingKnobTests() {
        let roomy = makeButton("Original size", .toggle, indicator: .checkbox)
        expect(roomy.horizontalPadding == GlassChoiceButton.padding && roomy.contentGap == GlassChoiceButton.gap, "The knobs default to the row padding and gap")
        let text = needed("Original size", .bodyStrong).width
        let side = GlassChoiceButton.glyphSide
        expect(roomy.intrinsicContentSize.width == 2 * 12 + side + 8 + text, "By default a checkbox toggle is 12 + mark + 8 + title + 12 (\(roomy.intrinsicContentSize.width))")
        let tight = makeButton("Original size", .toggle, indicator: .checkbox)
        tight.horizontalPadding = 8
        tight.contentGap = 4
        expect(tight.intrinsicContentSize.width == 2 * 8 + side + 4 + text, "Tightened it is 8 + mark + 4 + title + 8 (\(tight.intrinsicContentSize.width))")
        expect(roomy.intrinsicContentSize.width - tight.intrinsicContentSize.width == 2 * (12 - 8) + (8 - 4), "and exactly the two savings narrower")
        expect(tight.intrinsicContentSize.height == 36 && (tight.titleLabel.font?.pointSize ?? 0) >= 20, "The row stays 36 pt tall and its title 20 pt")
        tight.frame = NSRect(x: 0, y: 0, width: tight.intrinsicContentSize.width, height: 36)
        tight.layoutSubtreeIfNeeded()
        expect(tight.markImage != nil && tight.showsMark, "The checkbox mark is there")
        let mark = descendants(tight).compactMap { $0 as? NSImageView }.first { $0.image === tight.markImage }
        expect(mark?.frame.minX == 8 && tight.titleLabel.frame.minX == 8 + side + 4, "The mark starts at the tightened padding and the title follows one tightened gap later (\(String(describing: mark?.frame)), \(tight.titleLabel.frame))")
        expect(abs(tight.titleLabel.frame.maxX - (tight.bounds.width - 8)) < 0.5, "The title ends at the tightened trailing padding (\(tight.titleLabel.frame), width \(tight.bounds.width))")
        // A trailing glyph and a shortcut follow the same knobs.
        let trailing = makeButton("Sample", .toggle, indicator: .check)
        trailing.horizontalPadding = 6
        trailing.contentGap = 2
        expect(trailing.intrinsicContentSize.width == 2 * 6 + needed("Sample", .bodyStrong).width + 2 + side, "A trailing check column uses the tightened padding and gap (\(trailing.intrinsicContentSize.width))")
        trailing.frame = NSRect(x: 0, y: 0, width: 300, height: 36)
        trailing.isChosen = true
        trailing.layoutSubtreeIfNeeded()
        let check = descendants(trailing).compactMap { $0 as? NSImageView }.first { $0.image === trailing.trailingImage }
        expect(trailing.titleLabel.frame.minX == 6 && check.map { abs($0.frame.maxX - (300 - 6)) < 0.5 } == true, "A row's title starts at the padding and its check ends at the trailing padding (\(trailing.titleLabel.frame), \(String(describing: check?.frame)))")
    }

    /// `rowTitle` lets a menu's panel say more than the item's title: the visible row and the spoken label, with the menu itself untouched.
    private static func rowTitleTests() {
        let menu = NSMenu(title: "Zoom")
        let plainItem = NSMenuItem(title: "100%", action: nil, keyEquivalent: "")
        let computed = NSMenuItem(title: "100%", action: nil, keyEquivalent: ""); computed.tag = 999; computed.toolTip = "Fit, 100%"
        menu.addItem(computed); menu.addItem(plainItem)
        let panel = MenuChoicePanel(menu: menu, identifier: "RowTitle", accessibilityLabel: "Zoom")
        let (window, content) = (NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true), NSView())
        window.contentView = content
        panel.host.presenter = { _, _ in }
        panel.host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let anchor = NSButton(title: "", target: nil, action: nil)
        anchor.frame = NSRect(x: 20, y: 250, width: 80, height: 36)
        content.addSubview(anchor)
        panel.present(relativeTo: anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.rows.map(\.title) == ["100%", "100%"] && panel.rows.map { $0.accessibilityLabel() } == ["100%", "100%"], "By default a row says its item's title, to the eye and to VoiceOver")
        panel.host.close()
        panel.rowTitle = { $0.tag == 999 ? ($0.toolTip ?? $0.title) : $0.title }
        panel.present(relativeTo: anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.rows.map(\.title) == ["Fit, 100%", "100%"] && panel.rows.map { $0.accessibilityLabel() } == ["Fit, 100%", "100%"], "With a row title hook the computed row says its mode, visibly and to VoiceOver")
        expect(menu.items.map(\.title) == ["100%", "100%"] && panel.rows.allSatisfy { $0.frame.width >= $0.intrinsicContentSize.width - 0.5 }, "The menu's own titles are untouched and the panel is wide enough for the longer row")
        panel.host.close()
        // The pop-up passes the hook through, and changing it makes a new panel.
        let popUp = GlassPopUpButton(frame: NSRect(x: 20, y: 200, width: 120, height: 36), pullsDown: false)
        popUp.addItems(withTitles: ["25%", "100%"])
        popUp.menu?.items[1].tag = 999; popUp.menu?.items[1].toolTip = "Fit, 100%"
        content.addSubview(popUp)
        let before = popUp.choicePanel
        popUp.rowTitle = { $0.tag == 999 ? ($0.toolTip ?? $0.title) : $0.title }
        expect(popUp.choicePanel !== before && popUp.choicePanel.rowTitle(popUp.menu!.items[1]) == "Fit, 100%" && popUp.choicePanel.rowTitle(popUp.menu!.items[0]) == "25%", "A pop-up passes its row title hook to its panel")
        _ = window
    }

    private static func buttonLayoutTests() {
        let plainButton = makeButton("Sample", .command)
        let intrinsic = plainButton.intrinsicContentSize
        let textWidth = needed("Sample", .bodyStrong).width
        expect(intrinsic.height == 36 && intrinsic.width == textWidth + 24, "A plain row is 36 pt tall with 12 pt padding either side (\(intrinsic))")
        let chosenWidth = { () -> CGFloat in plainButton.isChosen = true; defer { plainButton.isChosen = false }; return plainButton.intrinsicContentSize.width }()
        expect(chosenWidth == intrinsic.width, "Choosing a row never changes its width (the title is measured in the strong face)")

        let withIcon = makeButton("Sample", .command)
        withIcon.icon = .copy
        expect(withIcon.leadingIconImage != nil && withIcon.image == nil, "An FAIcon is the leading glyph, drawn by a subview")
        expect(withIcon.intrinsicContentSize.width == intrinsic.width + GlassChoiceButton.glyphSide + 8, "The icon column adds the glyph and one 8 pt gap")
        let reserved = makeButton("Sample", .command)
        reserved.reservesIconColumn = true
        expect(reserved.intrinsicContentSize.width == withIcon.intrinsicContentSize.width && reserved.leadingIconImage == nil, "A reserved icon column takes the same room with no glyph")
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
        let withImage = makeButton("Sample", .command)
        withImage.leadingImage = image
        expect(withImage.leadingIconImage === image, "A menu item's image is used as it is")

        let shortcut = makeButton("Sample", .command)
        shortcut.shortcutText = "⇧⌘K"
        let shortcutWidth = needed("⇧⌘K", .body).width
        expect(shortcut.intrinsicContentSize.width == intrinsic.width + 16 + shortcutWidth, "A shortcut adds a 16 pt gap and its width")

        let checked = makeButton("Sample", .toggle, indicator: .check)
        expect(checked.intrinsicContentSize.width == intrinsic.width + 8 + GlassChoiceButton.glyphSide, "A trailing check column is reserved even while the check is hidden")

        // Row: title leading, shortcut and glyph trailing. Segment: the content is centred.
        let row = makeButton("Sample", .toggle, indicator: .check)
        row.shortcutText = "⌘K"
        row.frame = NSRect(x: 0, y: 0, width: 400, height: 36)
        row.isChosen = true
        row.layoutSubtreeIfNeeded()
        expect(row.titleLabel.frame.minX == 12, "A row's title starts after the 12 pt padding (\(row.titleLabel.frame))")
        expect(row.trailingImage != nil && row.showsTrailingGlyph, "A chosen check row shows its check")
        expect(abs(row.shortcutLabel.frame.maxX - (400 - 12 - GlassChoiceButton.glyphSide - 8)) < 0.5, "The shortcut is right-aligned before the trailing glyph (\(row.shortcutLabel.frame))")
        expect(row.titleLabel.frame.midY == 18 || abs(row.titleLabel.frame.midY - 18) < 1, "The title is centred in the row height")
        let segment = makeButton("Mode", .option, indicator: GlassChoiceButton.Indicator.none, layout: .segment)
        segment.frame = NSRect(x: 0, y: 0, width: 300, height: 36)
        segment.layoutSubtreeIfNeeded()
        let textSize = segment.titleLabel.frame
        expect(abs(textSize.midX - 150) < 1.5, "A segment centres its content (\(textSize))")

        // Wrapping grows the row.
        let wrapped = makeButton("A title long enough that it must wrap onto several lines", .command)
        wrapped.wrapWidth = 140
        let height = wrapped.intrinsicContentSize.height
        expect(height > 36 && wrapped.intrinsicContentSize.width <= 140 + 4 + 24, "A wrapping title grows the row above 36 pt within its width (\(wrapped.intrinsicContentSize))")
        expect(wrapped.titleLabel.maximumNumberOfLines == 0 && makeButton("x", .command).titleLabel.maximumNumberOfLines == 1, "Only a wrapping title may use several lines")
        wrapped.wrapWidth = nil
        expect(wrapped.intrinsicContentSize.height == 36, "Without a wrap width the row is one 36 pt line again")
    }

    // MARK: indicator glyphs

    private static func indicatorGlyphTests() {
        let side = GlassChoiceButton.glyphPointSize
        func asset(_ icon: FAIcon, _ family: FAFamily, scale: CGFloat = 1) -> NSImage? { ChromeIcons.resolve(icon, family: family, pointSize: side * scale).image }

        // checkbox: off is the regular square, on is the solid square with the check knocked out.
        let box = makeButton("Box", .toggle, indicator: .checkbox)
        expect(sameImage(box.markImage, asset(.square, .regular)) && box.showsMark, "An unchecked box is the regular square outline")
        box.isChosen = true
        guard let on = box.markImage, let solid = asset(.square, .solid), let tick = asset(.check, .solid, scale: 0.55) else { return expect(false, "The checkbox glyphs resolve") }
        expect(on.isTemplate && on.size == solid.size, "The checked box is a template image on the glyph canvas")
        let onAlpha = alpha(on), solidAlpha = alpha(solid), tickAlpha = alpha(tick)
        expect(coverage(on) < coverage(solid) && coverage(on) > coverage(asset(.square, .regular)!), "Checked: more ink than the outline, less than the solid square (the tick is cut out)")
        // The tick is canvas-centred on the box: wherever the tick has ink, the checked box is transparent; away from it the box is solid.
        let offset = (onAlpha.pixels - tickAlpha.pixels) / 2
        var knocked = 0, solidElsewhere = 0
        for y in 0..<tickAlpha.pixels { for x in 0..<tickAlpha.pixels where tickAlpha.alpha[y * tickAlpha.pixels + x] > 240 {
            expect(onAlpha.alpha[(y + offset) * onAlpha.pixels + (x + offset)] < 30, "The tick is knocked out of the box at (\(x), \(y))")
            knocked += 1
        } }
        for y in 0..<solidAlpha.pixels { for x in 0..<solidAlpha.pixels where solidAlpha.alpha[y * solidAlpha.pixels + x] > 250 {
            let inTick = x >= offset && y >= offset && x < offset + tickAlpha.pixels && y < offset + tickAlpha.pixels && tickAlpha.alpha[(y - offset) * tickAlpha.pixels + (x - offset)] > 8
            if !inTick { expect(onAlpha.alpha[y * onAlpha.pixels + x] > 240, "The box stays solid away from the tick at (\(x), \(y))"); solidElsewhere += 1 }
        } }
        expect(knocked > 20 && solidElsewhere > 200, "The knockout test looked at real pixels (\(knocked) tick pixels, \(solidElsewhere) box pixels)")

        // radio: off is the regular circle, on is the solid circle-check.
        let radio = makeButton("Dot", .option, indicator: .radio)
        expect(sameImage(radio.markImage, asset(.circle, .regular)), "An unselected radio is the regular circle")
        radio.isChosen = true
        expect(sameImage(radio.markImage, asset(.circleCheck, .solid)), "A selected radio is the solid circle-check")

        // check: trailing, solid, only while chosen. chevron: right-pointing, always.
        let check = makeButton("Tick", .option, indicator: .check)
        expect(!check.showsTrailingGlyph && !check.showsMark, "An unchosen check row shows nothing trailing")
        check.isChosen = true
        expect(check.showsTrailingGlyph && sameImage(check.trailingImage, asset(.check, .solid)), "A chosen check row shows the solid check")
        check.isChosen = false
        expect(!check.showsTrailingGlyph, "...and hides it again")
        let chevron = makeButton("More", .submenu)
        expect(chevron.indicator == .chevron && chevron.showsTrailingGlyph && sameImage(chevron.trailingImage, asset(.chevronRight, .solid, scale: 0.8)), "A submenu row ends in the right chevron")
        let none = makeButton("Plain", .command)
        expect(none.indicator == .none && !none.showsMark && !none.showsTrailingGlyph, "A command has no indicator")

        // Defaults by kind.
        expect(GlassChoiceButton.defaultIndicator(for: .command) == .none && GlassChoiceButton.defaultIndicator(for: .option) == .check
               && GlassChoiceButton.defaultIndicator(for: .toggle) == .check && GlassChoiceButton.defaultIndicator(for: .submenu) == .chevron, "Default indicators by kind")

        // Chevron direction on the pixels: at mid height the ink is further right than near the top.
        let image = chevron.trailingImage!
        let chevronAlpha = alpha(image)
        func meanX(_ rows: ClosedRange<Double>) -> Double {
            var sum = 0.0, total = 0.0
            for y in Int(rows.lowerBound * Double(chevronAlpha.pixels))..<Int(rows.upperBound * Double(chevronAlpha.pixels)) { for x in 0..<chevronAlpha.pixels {
                let a = Double(chevronAlpha.alpha[y * chevronAlpha.pixels + x]); sum += Double(x) * a; total += a
            } }
            return sum / max(total, 1)
        }
        expect(meanX(0.45...0.55) - meanX(0.2...0.35) > 2, "The chevron points right")
        // Every glyph in the choice views is a Font Awesome (or its SF Symbol fallback) template.
        for glyph in [box.markImage, radio.markImage, check.trailingImage, chevron.trailingImage] { expect(glyph?.isTemplate == true, "Indicator glyphs are template images") }
    }

    // MARK: inline group

    private static func groupTests() {
        let window = NonorderingWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let target = ClickTarget()
        let group = GlassChoiceGroup(titles: ["Resize", "Crop", "Limit"], selectedIndex: 0, accessibilityLabel: "Mode", identifier: "mode", accessibility: plain)
        group.target = target
        group.action = #selector(ClickTarget.clicked(_:))
        place(group, in: window)

        expect(group.buttons.count == 3 && group.selectedIndex == 0 && group.buttons.map(\.isChosen) == [true, false, false], "The first segment starts chosen")
        expect(group.buttons.map { $0.identifier?.rawValue } == ["mode.0", "mode.1", "mode.2"], "Each button has an identifier")
        expect(group.buttons.allSatisfy { $0.kind == .option && $0.choiceLayout == .segment }, "A group is a set of option segments")

        // One plate, one glass.
        let glass = descendants(group).filter { $0 is NSGlassEffectView }
        expect(glass.count == 1 && glass[0] === group.plate, "The whole group is ONE glass plate")
        expect(group.plate.axis == .horizontal && group.plate.frame.height == 44, "A horizontal group is the 44 pt plate row (\(group.plate.frame))")
        expect(Set(group.buttons.map { $0.frame.width }).count == 1, "The segments share one width, so choosing one moves nothing (\(group.buttons.map { $0.frame.width }))")

        // Assigning the selection sends nothing; the look follows.
        group.selectedIndex = 2
        expect(target.senders.isEmpty && group.buttons.map(\.isChosen) == [false, false, true], "Assigning selectedIndex moves the choice and sends nothing")
        group.selectedIndex = 9
        expect(group.selectedIndex == 2, "An out-of-range selection is refused")
        group.selectedIndex = -1
        expect(group.selectedIndex == -1 && group.buttons.allSatisfy { !$0.isChosen }, "-1 means no choice")
        group.selectedIndex = 0

        // A click changes the choice and sends once; clicking the chosen one sends nothing.
        group.buttons[1].performClick(nil)
        expect(group.selectedIndex == 1 && target.senders.count == 1 && group.buttons.map(\.isChosen) == [false, true, false], "A click chooses and sends once")
        group.buttons[1].performClick(nil)
        expect(target.senders.count == 1 && group.buttons[1].isChosen, "Clicking the chosen segment sends nothing and keeps it chosen")
        expect(target.senders == ["mode.group"], "The action's sender is the group")

        // Keys: arrows move the choice and the focus, one action per change; no wrap; disabled segments are skipped.
        _ = window.makeFirstResponder(group.buttons[1])
        target.senders = []
        group.buttons[1].keyDown(with: key(Keys.right))
        expect(group.selectedIndex == 2 && target.senders.count == 1 && window.firstResponder === group.buttons[2], "Right moves the choice and the focus and sends once")
        group.buttons[2].keyDown(with: key(Keys.right))
        expect(group.selectedIndex == 2 && target.senders.count == 1, "Right at the end does nothing (no wrap, no action)")
        group.buttons[2].keyDown(with: key(Keys.up))
        expect(group.selectedIndex == 1 && target.senders.count == 2, "Up moves back")
        group.buttons[1].keyDown(with: key(Keys.down))
        expect(group.selectedIndex == 2 && target.senders.count == 3, "Down moves forward")
        group.setEnabled(false, at: 1)
        group.selectedIndex = 0
        _ = window.makeFirstResponder(group.buttons[0])
        group.buttons[0].keyDown(with: key(Keys.right))
        expect(group.selectedIndex == 2 && target.senders.count == 4, "A disabled segment is skipped by the arrow keys")
        group.setEnabled(true, at: 1)

        // Space and Return choose the focused button.
        group.selectedIndex = 0
        _ = window.makeFirstResponder(group.buttons[2])
        target.senders = []
        group.buttons[2].keyDown(with: key(Keys.space, chars: " "))
        expect(group.selectedIndex == 2 && target.senders.count == 1, "Space chooses the focused segment")
        group.selectedIndex = 0
        _ = window.makeFirstResponder(group.buttons[1])
        group.buttons[1].keyDown(with: key(Keys.enter))
        expect(group.selectedIndex == 1 && target.senders.count == 2, "Return chooses the focused segment")
        _ = window.makeFirstResponder(group.buttons[1])
        group.buttons[1].keyDown(with: key(Keys.keypadEnter))
        expect(target.senders.count == 2, "Choosing the chosen segment again sends nothing")

        // One tab stop: only the chosen button is in the key-view loop.
        group.selectedIndex = 1
        expect(group.buttons.map(\.canBecomeKeyView) == [false, true, false], "Only the chosen segment is a tab stop")
        group.selectedIndex = 2
        expect(group.buttons.map(\.canBecomeKeyView) == [false, false, true], "...and the stop follows the choice")
        group.selectedIndex = -1
        expect(group.buttons.map(\.canBecomeKeyView) == [true, false, false], "With no choice the first enabled segment is the stop")
        group.selectedIndex = 1
        group.setEnabled(false, at: 1)
        expect(group.buttons.map(\.canBecomeKeyView) == [true, false, false] && !group.buttons[1].acceptsFirstResponder, "A disabled chosen segment hands the stop to the first enabled one")
        group.setEnabled(true, at: 1)
        window.recalculateKeyViewLoop()
        let after = group.buttons[1].nextValidKeyView
        expect(after == nil || !group.buttons.contains { $0 === after }, "Tab leaves the group after its one stop")

        // Enabled state.
        group.isEnabled = false
        expect(group.buttons.allSatisfy { !$0.isEnabled } && !group.isAccessibilityEnabled(), "A disabled group disables every segment")
        target.senders = []
        group.choose(2)
        expect(target.senders.isEmpty, "A disabled group cannot be chosen from")
        group.isEnabled = true
        expect(group.buttons.allSatisfy(\.isEnabled), "Enabling the group enables every segment again")

        // Accessibility: a radio group with a label, radio-button children with 0 / 1.
        group.selectedIndex = 1
        expect(group.accessibilityRole() == .radioGroup && group.accessibilityLabel() == "Mode" && group.isAccessibilityElement(), "The group is a labelled radio group")
        expect((group.accessibilityChildren() as? [GlassChoiceButton]) == group.buttons && group.buttons.allSatisfy { $0.accessibilityRole() == .radioButton }, "Its children are the radio buttons")
        expect(group.buttons.map { ($0.accessibilityValue() as? NSNumber)?.intValue } == [0, 1, 0], "Radio values are 0 and 1")
        expect(group.accessibilityValue() as? String == "Crop" && (group.accessibilitySelectedChildren() as? [GlassChoiceButton]) == [group.buttons[1]], "The group's value and selected child are the chosen segment")

        // Display options reach the plate and every button.
        group.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: true, reduceMotion: true, differentiateWithoutColor: true)
        expect(group.plate.transparencyPlate != nil && group.plate.showsContrastBorder && group.buttons.allSatisfy { $0.accessibility.reduceMotion && $0.accessibility.differentiateWithoutColor }, "Display options are pushed to the plate and the buttons")
        expect(group.buttons[1].showsIndicator, "...so Differentiate Without Color reaches the chosen segment")
        group.accessibility = plain

        // A vertical radio group: full-width rows with a radio glyph, stacked in order.
        let radios = GlassChoiceGroup(titles: ["Always", "Only when needed", "Never"], selectedIndex: 1, layout: .row, axis: .vertical, indicator: .radio,
                                      accessibilityLabel: "Presence", identifier: "presence", accessibility: plain)
        place(radios, in: window, width: 320)
        expect(radios.plate.axis == .vertical && radios.buttons.allSatisfy { abs($0.frame.width - (radios.plate.frame.width - 8)) < 0.5 }, "A vertical group's rows take the plate width")
        expect(radios.buttons.map { $0.frame.maxY }.sorted(by: >) == radios.buttons.map { $0.frame.maxY }, "...stacked in order")
        expect(sameImage(radios.buttons[1].markImage, ChromeIcons.resolve(.circleCheck, family: .solid, pointSize: GlassChoiceButton.glyphPointSize).image)
               && sameImage(radios.buttons[0].markImage, ChromeIcons.resolve(.circle, family: .regular, pointSize: GlassChoiceButton.glyphPointSize).image), "Radio rows show the circle and the circle-check")
        expect(radios.buttons.allSatisfy { $0.titleLabel.frame.minX == 12 + GlassChoiceButton.glyphSide + 8 }, "Radio titles start after the radio glyph")
        expect(radios.plate.frame.height == 3 * 36 + 2 * 2 + 8, "The vertical plate is as tall as its three rows (\(radios.plate.frame.height))")
    }

    // MARK: host

    private static func plate(_ titles: [String], axis: NSUserInterfaceLayoutOrientation = .vertical, target: ClickTarget? = nil) -> GlassSurfaceView {
        let rows = titles.map { makeButton($0, .command, target: target) }
        return GlassChrome.plate(rows, identifier: "plate.\(titles.first ?? "")", accessibility: plain, axis: axis)
    }

    private static func hostTests() {
        let rig = Rig()
        let first = plate(["One", "Two"]), second = plate(["Three"])
        let host = GlassPanelHost(plates: [first, second], identifier: "Probe", accessibilityLabel: "Probe choices")
        rig.attach(host)

        // The window.
        let panel = host.window
        expect(panel.styleMask.contains(.borderless) && !panel.isOpaque && panel.backgroundColor == .clear && panel.hasShadow, "A borderless, transparent window with a shadow")
        expect(panel.canBecomeKey && !panel.canBecomeMain, "It can be key, never main")
        expect(panel.identifier?.rawValue == "GlassChoicePanel.Probe" && panel.accessibilityLabel() == "Probe choices", "It is identified and labelled")
        expect(panel.isReleasedWhenClosed == false && panel.worksWhenModal, "It survives close and works above a modal parent")

        // ONE container with the plates inside it, and glass never inside glass.
        let tree = descendants(panel.contentView!)
        expect(tree.filter { $0 is NSGlassEffectContainerView }.count == 1 && tree.first(where: { $0 is NSGlassEffectContainerView }) === host.container, "A panel holds exactly one NSGlassEffectContainerView")
        expect(host.container.identifier?.rawValue == "GlassChoicePanel.Probe.container", "...identified")
        let glass = tree.compactMap { $0 as? NSGlassEffectView }
        expect(glass.count == 2 && glass.allSatisfy { $0 is GlassSurfaceView }, "One glass plate per group, nothing else is glass")
        for plate in glass { expect(descendants(plate).allSatisfy { !($0 is NSGlassEffectView) && !($0 is NSGlassEffectContainerView) }, "No glass inside glass") }
        expect(host.plates == [first, second], "The plates are exposed in order")

        // Shown: placed under the anchor, presented through the seam, current.
        var events: [String] = []
        host.willClose = { events.append("willClose") }
        host.didClose = { events.append("didClose") }
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        expect(host.isShown && GlassPanelHost.current === host && rig.presented.count == 1 && rig.presented[0].0 === panel && rig.presented[0].1 === rig.window, "Showing presents the panel for the anchor's window and makes it current")
        let anchorFrame = rig.anchorOnScreen
        expect(host.placement?.edge == .minY && abs(panel.frame.maxY - (anchorFrame.minY - 6)) < 0.5 && abs(panel.frame.minX - anchorFrame.minX) < 0.5, "Placed 6 pt below the anchor, leading edge aligned (\(panel.frame) for \(anchorFrame))")
        expect(host.requestedKey, "A click-open asks for the keyboard")
        expect(abs(first.frame.width - second.frame.width) < 0.5 && abs((first.frame.minY - second.frame.maxY) - DesignTokens.Space.s2) < 0.5, "Plates share a width and sit 8 pt apart (\(first.frame), \(second.frame))")
        expect(abs(panel.frame.width - first.frame.width) < 0.5 && abs(panel.frame.height - (first.frame.height + 8 + second.frame.height)) < 0.5, "The window is exactly the plates' size")
        expect(panel.level == rig.window.level, "It sits at its parent's level")

        // Showing again from another anchor re-places it.
        host.close()
        expect(events == ["willClose", "didClose"] && !host.isShown && GlassPanelHost.current == nil, "Close reports willClose then didClose and clears current")
        host.close()
        expect(events.count == 2, "Closing twice reports once")

        // A hover open never asks for the keyboard.
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: false)
        expect(host.isShown && !host.requestedKey, "makeKey: false (hover open) never asks for the keyboard")
        host.close()

        // The preferred edge is in screen terms: a flipped anchor view opens below on .minY just like an unflipped one.
        let flipped = FlippedAnchor(frame: NSRect(x: 300, y: 300, width: 80, height: 36))
        rig.window.contentView?.addSubview(flipped)
        host.show(relativeTo: flipped.bounds, of: flipped, preferredEdge: .minY, makeKey: true)
        let flippedFrame = rig.window.convertToScreen(flipped.convert(flipped.bounds, to: nil))
        expect(host.placement?.edge == .minY && abs(panel.frame.maxY - (flippedFrame.minY - 6)) < 0.5, "A flipped anchor view still opens below on .minY (\(panel.frame) vs \(flippedFrame))")
        host.close()
        host.show(relativeTo: flipped.bounds, of: flipped, preferredEdge: .maxY, makeKey: true)
        expect(host.placement?.edge == .maxY && abs(panel.frame.minY - (flippedFrame.maxY + 6)) < 0.5, "...and above on .maxY")
        host.close()

        // An anchor with no window cannot show a panel.
        let loose = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        host.show(relativeTo: loose.bounds, of: loose, preferredEdge: .minY, makeKey: true)
        expect(!host.isShown, "A view with no window cannot anchor a panel")

        // Only one host is shown at a time.
        let a = GlassPanelHost(plates: [plate(["A"])], identifier: "A", accessibilityLabel: "A")
        let b = GlassPanelHost(plates: [plate(["B"])], identifier: "B", accessibilityLabel: "B")
        rig.attach(a); rig.attach(b)
        var aEvents: [String] = []
        a.willClose = { aEvents.append("willClose") }
        a.didClose = { aEvents.append("didClose") }
        a.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        b.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        expect(!a.isShown && b.isShown && GlassPanelHost.current === b && aEvents == ["willClose", "didClose"], "Showing a second host closes the first: only one is ever shown")
        a.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        expect(a.isShown && !b.isShown && GlassPanelHost.current === a, "...in either direction")
        a.close()

        // Replacing the plates of a shown panel re-fits it.
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        let before = panel.frame.height
        host.setPlates([plate(["Only"])])
        expect(host.plates.count == 1 && panel.frame.height < before && descendants(panel.contentView!).filter { $0 is NSGlassEffectContainerView }.count == 1, "Replacing the plates re-fits the shown panel and keeps one container")
        host.close()

        // Minimum width.
        host.minimumWidth = 400
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        expect(panel.frame.width >= 400 - 0.5 && host.plates.allSatisfy { $0.frame.width >= 400 - 0.5 }, "A minimum width stretches every plate (\(panel.frame.width))")
        host.close()
    }

    // MARK: dismissal

    private static func dismissalTests() {
        let rig = Rig()
        let host = GlassPanelHost(plates: [plate(["One", "Two"])], identifier: "Dismiss", accessibilityLabel: "Dismiss")
        rig.attach(host)
        func open(key: Bool = true) { host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: key) }
        var closes = 0
        host.didClose = { closes += 1 }

        // Escape: the window's cancel and the key event both close.
        open()
        host.window.cancelOperation(nil)
        expect(!host.isShown && closes == 1, "Escape (cancelOperation) closes")
        open()
        host.window.sendEvent(key(Keys.escape))
        expect(!host.isShown && closes == 2, "The Escape key event closes")
        open()
        host.keyHandler = { event in event.keyCode == Keys.escape }
        host.window.sendEvent(key(Keys.escape))
        expect(host.isShown, "A key handler that takes Escape keeps the panel open (a submenu goes back instead)")
        host.keyHandler = nil
        host.close()
        closes = 0

        // Clicks: inside the panel nothing happens; elsewhere closes and passes; the anchor closes and is consumed.
        open()
        expect(!host.handleMouseDown(in: host.window, at: NSPoint(x: 10, y: 10)) && host.isShown, "A click inside the panel keeps it open and is not consumed")
        let elsewhere = NonorderingWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        expect(!host.handleMouseDown(in: elsewhere, at: NSPoint(x: 10, y: 10)) && !host.isShown && closes == 1, "A click in another window closes it and lets the click through")
        open()
        expect(!host.handleMouseDown(in: rig.window, at: NSPoint(x: 600, y: 300)) && !host.isShown, "A click elsewhere in the parent window closes it and lets the click through")
        open()
        let onAnchor = rig.anchor.convert(NSPoint(x: 10, y: 10), to: nil)
        expect(host.handleMouseDown(in: rig.window, at: onAnchor) && !host.isShown, "A click on the anchor closes the panel and is consumed")
        open()
        expect(!host.handleMouseDown(in: nil, at: .zero) && !host.isShown, "A click with no window closes it")

        // The anchor cannot reopen it: the opener that runs on a click only sees an event the panel did not consume.
        var reopened = false
        func anchorClick() {
            if host.isShown {
                if host.handleMouseDown(in: rig.window, at: onAnchor) { return }
            }
            open(); reopened = true
        }
        open()
        reopened = false
        anchorClick()
        expect(!host.isShown && !reopened, "Clicking the opener while its panel is open closes it and does not reopen it")
        anchorClick()
        expect(host.isShown && reopened, "A later click opens it again")
        host.close()

        // The real local monitor is installed while shown and removed after.
        open()
        let outside = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0, windowNumber: -1, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        NSApp.sendEvent(outside)
        expect(!host.isShown, "The event monitor closes the panel on a click it sees")
        let closesAfter = closes
        NSApp.sendEvent(outside)
        expect(closes == closesAfter, "...and is gone once the panel is closed")

        // Notifications: app deactivation and the parent closing, miniaturising, entering full screen, or beginning a sheet.
        let center = NotificationCenter.default
        let cases: [(String, Notification.Name, Any?)] = [
            ("the app resigning active", NSApplication.didResignActiveNotification, NSApp),
            ("the parent window closing", NSWindow.willCloseNotification, rig.window),
            ("the parent window miniaturising", NSWindow.willMiniaturizeNotification, rig.window),
            ("the parent window entering full screen", NSWindow.willEnterFullScreenNotification, rig.window),
            ("the parent window beginning a sheet", NSWindow.willBeginSheetNotification, rig.window),
        ]
        for (label, name, object) in cases {
            open()
            center.post(name: name, object: object)
            expect(!host.isShown, "Closes on \(label)")
        }
        open()
        center.post(name: NSWindow.willCloseNotification, object: elsewhere)
        expect(host.isShown, "Another window closing is none of its business")
        center.post(name: NSWindow.willMiniaturizeNotification, object: elsewhere)
        expect(host.isShown, "...nor another window miniaturising")
        host.close()
        let count = closes
        center.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        expect(closes == count, "Observers are removed when the panel closes")

        // The anchor leaving its window, or being hidden, closes it; moving it re-places it.
        open()
        rig.anchor.frame.origin.x += 60
        host.revalidate()
        let moved = rig.anchorOnScreen
        expect(host.isShown && abs(host.window.frame.minX - moved.minX) < 0.5, "Moving the anchor re-places the panel")
        rig.anchor.isHidden = true
        host.revalidate()
        expect(!host.isShown, "Hiding the anchor closes the panel")
        rig.anchor.isHidden = false
        open()
        rig.anchor.removeFromSuperview()
        host.revalidate()
        expect(!host.isShown, "The anchor leaving its window closes the panel")
        rig.window.contentView?.addSubview(rig.anchor)
        open()
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: rig.window)
        expect(host.isShown, "A parent update with the anchor in place leaves it open")
        rig.anchor.removeFromSuperview()
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: rig.window)
        expect(!host.isShown, "A parent update after the anchor left closes it")
        rig.window.contentView?.addSubview(rig.anchor)
    }

    // MARK: focus restoration

    private static func focusRestorationTests() {
        let rig = Rig()
        let host = GlassPanelHost(plates: [plate(["One"])], identifier: "Focus", accessibilityLabel: "Focus")
        rig.attach(host)

        // The panel held the keyboard: the parent gets it back and the responder from show time is restored.
        _ = rig.window.makeFirstResponder(rig.focus)
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        rig.panelIsKey = true
        _ = rig.window.makeFirstResponder(rig.other)
        host.window.cancelOperation(nil)
        expect(rig.window.firstResponder === rig.focus, "Escape restores the responder that had focus when the panel opened")

        // Same through an ordinary close.
        _ = rig.window.makeFirstResponder(rig.focus)
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        _ = rig.window.makeFirstResponder(rig.other)
        host.close()
        expect(rig.window.firstResponder === rig.focus, "close() restores it too")

        // A hover open never had the keyboard, so closing it moves nothing.
        rig.panelIsKey = false
        _ = rig.window.makeFirstResponder(rig.focus)
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: false)
        _ = rig.window.makeFirstResponder(rig.other)
        host.close()
        expect(rig.window.firstResponder === rig.other, "Closing a panel that never held the keyboard leaves focus alone")

        // The saved responder left the window: nothing is restored (and nothing breaks).
        rig.panelIsKey = true
        let leaving = FocusView(frame: NSRect(x: 300, y: 100, width: 40, height: 30))
        rig.window.contentView?.addSubview(leaving)
        _ = rig.window.makeFirstResponder(leaving)
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        _ = rig.window.makeFirstResponder(rig.other)
        leaving.removeFromSuperview()
        host.close()
        expect(rig.window.firstResponder === rig.other, "A responder that left the window is not brought back")

        // Dismissals that are not the user's choice (app deactivation) do not shuffle focus either.
        _ = rig.window.makeFirstResponder(rig.focus)
        host.show(relativeTo: rig.anchor.bounds, of: rig.anchor, preferredEdge: .minY, makeKey: true)
        _ = rig.window.makeFirstResponder(rig.other)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        expect(!host.isShown && rig.window.firstResponder === rig.other, "A dismissal by app deactivation restores nothing")
    }

    private final class FlippedAnchor: NSView { override var isFlipped: Bool { true } }

    // MARK: scrolling

    private static func manyItems(_ count: Int) -> [NSMenuItem] {
        (0..<count).map { NSMenuItem(title: "Row number \($0)", action: nil, keyEquivalent: "") }
    }

    private static func scrollingTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        let menu = NSMenu()
        for index in 0..<40 {
            let item = NSMenuItem(title: "Row number \(index)", action: #selector(MenuFixture.act(_:)), keyEquivalent: "")
            item.target = fixture
            menu.addItem(item)
        }
        let panel = MenuChoicePanel(menu: menu, identifier: "Long", accessibilityLabel: "Long list")
        rig.attach(panel.host)
        panel.host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1440, height: 600)
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        let host = panel.host
        expect(host.scrolls && host.scrollView != nil && host.placement?.scrolls == true, "A list taller than the screen scrolls")
        expect(host.window.frame.height <= 600 - 16 + 0.001 && host.window.frame.height < host.contentSize.height, "...in a window capped to the room (\(host.window.frame.height) of \(host.contentSize.height))")
        expect(descendants(host.window.contentView!).filter { $0 is NSGlassEffectContainerView }.count == 1, "A scrolling panel still holds one glass container")
        expect(descendants(host.window.contentView!).compactMap { $0 as? NSGlassEffectView }.allSatisfy { $0 is GlassSurfaceView }, "...and no nested glass")
        guard let scroll = host.scrollView, let first = panel.rows.first, let last = panel.rows.last else { return expect(false, "The scroll view and rows exist") }
        host.window.contentView?.layoutSubtreeIfNeeded()
        expect(scroll.documentVisibleRect.minY == 0 && scroll.documentVisibleRect.intersects(first.convert(first.bounds, to: scroll.documentView!)), "A scrolling panel starts at its first row")
        expect(panel.focusedRow === first, "A keyboard open focuses the first row")
        panel.focus(last)
        host.window.contentView?.layoutSubtreeIfNeeded()
        let lastFrame = last.convert(last.bounds, to: scroll.documentView!)
        expect(scroll.documentVisibleRect.intersection(lastFrame).height >= lastFrame.height - 0.5, "Focusing the last row scrolls it into view")
        expect(scroll.contentView.bounds.origin.y > 0, "...by moving the document")
        _ = panel.handleKey(key(Keys.down))
        expect(panel.focusedRow === first, "Down from the last row wraps to the first")
        host.window.contentView?.layoutSubtreeIfNeeded()
        expect(scroll.documentVisibleRect.minY == 0, "...and scrolls back to the top")
        host.close()

        // A list that fits does not scroll, and drops the scroll view again.
        let short = NSMenu()
        short.addItem(NSMenuItem(title: "Only", action: #selector(MenuFixture.act(_:)), keyEquivalent: ""))
        short.items[0].target = fixture
        let shortPanel = MenuChoicePanel(menu: short, identifier: "Short", accessibilityLabel: "Short")
        rig.attach(shortPanel.host)
        shortPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(!shortPanel.host.scrolls && shortPanel.host.scrollView == nil, "A short list does not scroll")
        shortPanel.host.close()
    }

    // MARK: menu panel: building

    private static func standardMenu(_ fixture: MenuFixture) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = fixture
        func add(_ title: String, key: String = "", mask: NSEvent.ModifierFlags = .command, state: NSControl.StateValue = .off) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(MenuFixture.act(_:)), keyEquivalent: key)
            item.target = fixture
            item.state = state
            item.keyEquivalentModifierMask = mask
            menu.addItem(item)
            return item
        }
        _ = add("Alpha", key: "a")                                    // 0
        _ = add("Beta", key: "B", state: .on)                         // 1
        menu.addItem(.separator())                                    // 2
        _ = add("Gamma")                                              // 3
        add("Hidden").isHidden = true                                 // 4
        menu.addItem(.separator())                                    // 5
        menu.addItem(.separator())                                    // 6
        menu.addItem(NSMenuItem.sectionHeader(title: "Section"))      // 7
        let delta = add("Delta", key: "d", mask: [.command, .option]) // 8
        delta.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
        delta.toolTip = "Does the delta thing"
        let alternate = add("Alternate", key: "x", mask: [.command, .option]) // 9
        alternate.isAlternate = true
        menu.addItem(.separator())                                    // 10
        return menu
    }

    private static func menuBuildTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        fixture.disabledTitles = ["Gamma"]
        let menu = standardMenu(fixture)
        let panel = MenuChoicePanel(menu: menu, identifier: "Build", accessibilityLabel: "Build choices")
        rig.attach(panel.host)
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)

        let plates = panel.host.plates
        expect(plates.count == 3, "Separators split the rows into group plates; hidden items, alternates and runs of separators add none (\(plates.count))")
        expect(panel.rows.map(\.title) == ["Alpha", "Beta", "Gamma", "Delta"], "Hidden and alternate items are skipped: \(panel.rows.map(\.title))")
        expect(panel.rows.map { $0.identifier?.rawValue } == ["choice.0", "choice.1", "choice.3", "choice.8"], "Rows are identified by their menu index")
        expect(plates.map { $0.arrangedViews.count } == [2, 1, 2], "Plate sizes follow the separators (the header and Delta share the last)")
        expect(plates.allSatisfy { $0.axis == .vertical }, "Every group plate is vertical")
        expect(panel.headers.count == 1 && panel.headers[0].title == "Section" && plates[2].arrangedViews.first === panel.headers[0], "A section header is a non-interactive label at the head of its group")
        expect(!(panel.headers[0] is NSControl) && !panel.headers[0].acceptsFirstResponder && panel.headers[0].label.font?.pointSize == 20, "...20 pt, not a control, not focusable")

        // Item state is carried to the rows.
        let rows = Dictionary(uniqueKeysWithValues: panel.rows.map { ($0.title, $0) })
        expect(rows["Alpha"]?.kind == .command && rows["Beta"]?.kind == .toggle, "The default kind is command, or toggle where the item has state")
        expect(rows["Beta"]?.isChosen == true && rows["Alpha"]?.isChosen == false, "state is chosen")
        expect(rows["Gamma"]?.isEnabled == false && rows["Gamma"]?.isAccessibilityEnabled() == false, "An item disabled by validation shows disabled")
        expect(rows["Alpha"]?.shortcutText == "⌘A" && rows["Beta"]?.shortcutText == "⇧⌘B" && rows["Delta"]?.shortcutText == "⌥⌘D" && rows["Gamma"]?.shortcutText == nil, "keyEquivalent and mask become shortcut text")
        expect(rows["Delta"]?.leadingIconImage === menu.items[8].image, "The item's image is the leading image")
        expect(rows["Delta"]?.accessibilityHelp() == "Does the delta thing", "toolTip becomes accessibility help")
        expect(panel.rows.allSatisfy { $0.reservesIconColumn }, "One row has an image, so every row reserves the icon column and the titles line up")
        expect(panel.rows.allSatisfy { $0.reservesTrailingColumn }, "A toggle row has a check column, so every row reserves it")
        for row in panel.rows { expect(panel.item(for: row) != nil, "Every row maps to its menu item") }

        // Rows are real choice buttons laid out on the plates.
        panel.host.window.contentView?.layoutSubtreeIfNeeded()
        expect(panel.rows.allSatisfy { abs($0.frame.width - (plates[0].frame.width - 8)) < 0.5 }, "Rows fill their plates")
        expect(plates.allSatisfy { abs($0.frame.width - plates[0].frame.width) < 0.5 } && plates[0].frame.width >= 240 - 0.5, "Plates share a width of at least the minimum, 240 pt")
        let titleX = Set(panel.rows.map { $0.titleLabel.frame.minX })
        expect(titleX.count == 1, "Titles share one x across rows and plates (\(titleX))")

        // The kind closure decides roles exactly.
        let kinds = MenuChoicePanel(menu: menu, identifier: "Kinds", accessibilityLabel: "Kinds", kind: { item in item.title == "Alpha" ? .option : (item.title == "Delta" ? .submenu : .toggle) })
        rig.attach(kinds.host)
        kinds.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(kinds.rows.map(\.kind) == [.option, .toggle, .toggle, .submenu], "A kind closure sets each row's role")
        expect(kinds.rows[0].accessibilityRole() == .radioButton && kinds.rows[1].accessibilityRole() == .checkBox && kinds.rows[3].accessibilityRole() == .menuButton, "...and so its accessibility role")
        kinds.host.close()

        // Fonts.
        let texts = labels(in: panel.host.window.contentView!)
        expect(!texts.isEmpty && texts.allSatisfy { ($0.font?.pointSize ?? 0) >= 18 }, "Every label in the panel is at least 18 pt")
        expect(texts.allSatisfy { $0.font?.pointSize == 20 }, "...and 20 pt in practice")
        panel.host.close()
    }

    // MARK: menu panel: lifecycle

    private static func menuLifecycleTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        let menu = standardMenu(fixture)
        let panel = MenuChoicePanel(menu: menu, identifier: "Life", accessibilityLabel: "Life")
        rig.attach(panel.host)
        let presenter = panel.host.presenter
        panel.host.presenter = { window, parent in log.add("present"); presenter?(window, parent) }

        // The menu's own machinery runs on every open, and before the panel is shown.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        let needs = log.index(of: "needsUpdate"), will = log.index(of: "willOpen"), shown = log.index(of: "present"), validated = log.lines.firstIndex { $0.hasPrefix("validate:") }
        expect(needs != nil && will != nil && shown != nil && validated != nil, "An open runs menuNeedsUpdate, menuWillOpen, validation and presents: \(log.lines)")
        expect(needs! < will! && will! < validated! && validated! < shown!, "...in that order, with validation before the panel is shown: \(log.lines)")
        expect(log.count("needsUpdate") == 1 && log.count("willOpen") == 1, "...once each")

        // It reflects the menu as it is now, each time.
        fixture.onNeedsUpdate = { menu in menu.items[0].title = "Alpha renamed"; menu.items[3].state = .on }
        panel.host.close()
        expect(log.count("didClose") == 1 && !panel.host.isShown, "Closing calls menuDidClose")
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.rows[0].title == "Alpha renamed" && panel.rows[2].title == "Gamma" && panel.rows[2].kind == .toggle && panel.rows[2].isChosen, "A reopen rebuilds from the menu's current titles and state")
        expect(log.count("needsUpdate") == 2 && log.count("willOpen") == 2, "...after running the delegate again")
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(log.count("didClose") == 2 && log.count("needsUpdate") == 3, "Presenting while shown closes the old open first")

        // Validation changes between opens show up.
        fixture.disabledTitles = ["Alpha renamed"]
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.rows[0].isEnabled == false, "An item that validation now disables shows disabled")
        fixture.disabledTitles = []
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.rows[0].isEnabled, "...and enabled again on the next open")

        // An anchor with no window opens nothing and calls no hooks.
        let hooks = log.lines.count
        panel.host.close()
        let before = log.lines.count
        panel.present(relativeTo: NSView(), preferredEdge: .minY, keyboard: false)
        expect(!panel.host.isShown && log.lines.count == before && hooks <= before, "A view with no window opens nothing and runs no menu hooks")

        // Only one panel is shown at a time, and the other's menu is told it closed.
        let otherLog = Log()
        let otherFixture = MenuFixture(log: otherLog)
        let otherMenu = standardMenu(otherFixture)
        let second = MenuChoicePanel(menu: otherMenu, identifier: "Second", accessibilityLabel: "Second")
        rig.attach(second.host)
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        let closedBefore = log.count("didClose")
        second.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(!panel.host.isShown && second.host.isShown && GlassPanelHost.current === second.host && log.count("didClose") == closedBefore + 1, "Presenting a second menu panel closes the first, and its menu gets menuDidClose")
        second.host.close()

        // Escape closes and restores the focus the opener had.
        _ = rig.window.makeFirstResponder(rig.focus)
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        rig.panelIsKey = true
        _ = rig.window.makeFirstResponder(rig.other)
        panel.host.window.sendEvent(key(Keys.escape))
        expect(!panel.host.isShown && rig.window.firstResponder === rig.focus, "Escape closes the menu panel and gives the opener its focus back")

        // Clicking the opener while the panel is open closes it and consumes the click.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.host.handleMouseDown(in: rig.window, at: rig.anchor.convert(NSPoint(x: 5, y: 5), to: nil)) && !panel.host.isShown, "A click on the opener closes the panel and is swallowed, so it cannot reopen it")
        rig.panelIsKey = false
    }

    // MARK: menu panel: activation

    private static func menuActivationTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        let menu = standardMenu(fixture)
        let panel = MenuChoicePanel(menu: menu, identifier: "Act", accessibilityLabel: "Act")
        rig.attach(panel.host)

        // Close FIRST (focus restored), then perform: the action runs with the panel gone and the opener focused again.
        var atAction: (shown: Bool, responder: NSResponder?)?
        fixture.onAction = { _ in atAction = (panel.host.isShown, rig.window.firstResponder) }
        _ = rig.window.makeFirstResponder(rig.focus)
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        rig.panelIsKey = true
        _ = rig.window.makeFirstResponder(rig.other)
        guard let alpha = panel.rows.first(where: { $0.title == "Alpha" }) else { return expect(false, "Alpha row") }
        panel.activate(alpha)
        expect(atAction?.shown == false, "The panel is closed before the item's action runs")
        expect(atAction?.responder === rig.focus, "Focus is back on the opener when the action runs")
        let closeIndex = log.index(of: "didClose"), actIndex = log.index(of: "act:Alpha")
        expect(closeIndex != nil && actIndex != nil && closeIndex! < actIndex!, "menuDidClose comes before the action: \(log.lines)")
        expect(log.count("act:Alpha") == 1, "The item's own action ran exactly once")
        rig.panelIsKey = false

        // A click on the row (the real path) is the same thing.
        log.lines = []
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        panel.rows.first { $0.title == "Delta" }!.performClick(nil)
        expect(log.count("act:Delta") == 1 && !panel.host.isShown, "Clicking a row performs its item once and closes")

        // A disabled row does nothing.
        fixture.disabledTitles = ["Gamma"]
        log.lines = []
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        let gamma = panel.rows.first { $0.title == "Gamma" }!
        panel.activate(gamma)
        gamma.performClick(nil)
        expect(panel.host.isShown && log.count("act:Gamma") == 0, "Activating a disabled row does nothing and leaves the panel open")
        panel.host.close()
        fixture.disabledTitles = []

        // Pop-up: a plain item selects itself in the pop-up and sends the pop-up's action; an item with its own action just performs it.
        let popLog = Log()
        let popFixture = MenuFixture(log: popLog)
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 100, height: 30), pullsDown: false)
        pop.addItems(withTitles: ["25%", "50%", "100%"])
        pop.target = popFixture
        pop.action = #selector(MenuFixture.popChanged(_:))
        pop.selectItem(at: 2)
        let own = NSMenuItem(title: "Actual Size", action: #selector(MenuFixture.act(_:)), keyEquivalent: "")
        own.target = popFixture
        pop.menu!.addItem(own)
        pop.menu!.delegate = popFixture
        var popAtAction: Bool?
        popFixture.onAction = { _ in popAtAction = rig.window.firstResponder === rig.focus }
        _ = rig.window.makeFirstResponder(rig.focus)
        let popPanel = MenuChoicePanel(menu: pop.menu!, identifier: "Zoom", accessibilityLabel: "Zoom", kind: { _ in .option }, popUp: pop)
        rig.attach(popPanel.host)
        popPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        expect(popPanel.rows.map(\.title) == ["25%", "50%", "100%", "Actual Size"] && popPanel.rows[2].isChosen && popPanel.rows.filter(\.isChosen).count == 1, "A pop-up's selected item is the chosen row")
        expect(popPanel.focusedRow === popPanel.rows[2], "A keyboard open lands on the chosen row")
        popPanel.activate(popPanel.rows[0])
        expect(pop.indexOfSelectedItem == 0, "A plain pop-up item selects itself in the pop-up")
        expect(popLog.lines.filter { $0 == "didClose" || $0.hasPrefix("popAction") || $0.hasPrefix("act:") } == ["didClose", "popAction:0"], "...after the panel closed, and sends the pop-up's action once with the new selection: \(popLog.lines)")
        expect(popAtAction == nil, "...without running any item action")

        popLog.lines = []
        popPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        popPanel.activate(popPanel.rows[3])
        expect(popLog.lines.filter { $0 == "didClose" || $0.hasPrefix("popAction") || $0.hasPrefix("act:") } == ["didClose", "act:Actual Size"] && pop.indexOfSelectedItem == 0, "An item with its own action performs it and leaves the pop-up's selection and action alone: \(popLog.lines) selected=\(pop.indexOfSelectedItem)")
        expect(popAtAction == true, "...with the opener focused again")

        // Choosing the chosen option again still performs.
        popLog.lines = []
        popPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        popPanel.activate(popPanel.rows[0])
        expect(popLog.lines.filter { $0 == "didClose" || $0.hasPrefix("popAction") || $0.hasPrefix("act:") } == ["didClose", "popAction:0"], "Choosing the already chosen option still sends the pop-up's action")
    }

    // MARK: menu panel: keyboard

    private static func menuKeyboardTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        fixture.disabledTitles = ["Gamma"]
        let menu = standardMenu(fixture)
        let panel = MenuChoicePanel(menu: menu, identifier: "Keys", accessibilityLabel: "Keys")
        rig.attach(panel.host)
        func press(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) { panel.host.window.sendEvent(key(code, modifiers: modifiers)) }

        // keyboard: true starts on the first enabled row: Beta is a toggle that happens to be on (state, not a choice), so it is not preferred.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        expect(panel.focusedRow?.title == "Alpha" && panel.host.window.firstResponder === panel.focusedRow, "A keyboard open on a command menu focuses the first enabled row, not the toggle that is on")
        press(Keys.down)
        expect(panel.focusedRow?.title == "Beta", "Down moves on to the next row")
        // Down skips the disabled Gamma, wraps; Up goes back the same way.
        press(Keys.down)
        expect(panel.focusedRow?.title == "Delta", "Down skips a disabled row (Gamma): \(panel.focusedRow?.title ?? "nil")")
        press(Keys.down)
        expect(panel.focusedRow?.title == "Alpha", "Down from the last row wraps to the first")
        press(Keys.up)
        expect(panel.focusedRow?.title == "Delta", "Up from the first row wraps to the last")
        press(Keys.up)
        expect(panel.focusedRow?.title == "Beta", "Up skips the disabled row too")
        press(Keys.tab)
        expect(panel.focusedRow?.title == "Delta", "Tab moves down")
        press(Keys.tab, modifiers: .shift)
        expect(panel.focusedRow?.title == "Beta", "Shift-Tab moves up")
        press(Keys.home)
        expect(panel.focusedRow?.title == "Alpha", "Home focuses the first enabled row")
        press(Keys.end)
        expect(panel.focusedRow?.title == "Delta", "End focuses the last enabled row")

        // Return, Space and keypad Enter choose the focused row; the panel closes first.
        for (code, label) in [(Keys.enter, "Return"), (Keys.space, "Space"), (Keys.keypadEnter, "keypad Enter")] {
            log.lines = []
            panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
            press(Keys.down)
            press(Keys.down)
            expect(panel.focusedRow?.title == "Delta", "(setup for \(label))")
            press(code)
            expect(!panel.host.isShown && log.count("act:Delta") == 1, "\(label) chooses the focused row")
        }

        // keyboard: false takes the keyboard with no row focused; the first arrow focuses the chosen row (or the first).
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.focusedRow == nil && !(panel.host.window.firstResponder is GlassChoiceButton), "A pointer open focuses no row")
        press(Keys.enter)
        expect(panel.host.isShown, "Return with no row focused does nothing")
        press(Keys.down)
        expect(panel.focusedRow?.title == "Alpha", "The first arrow key focuses the first enabled row of a command menu (the toggle that is on is not a choice)")
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        press(Keys.up)
        expect(panel.focusedRow?.title == "Alpha", "...for Up as well")

        // In a menu of options the chosen option is where the keyboard starts, on open and on the first arrow key.
        let optionPanel = MenuChoicePanel(menu: menu, identifier: "Options", accessibilityLabel: "Options", kind: { _ in .option })
        rig.attach(optionPanel.host)
        optionPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        expect(optionPanel.focusedRow?.title == "Beta" && optionPanel.rows.first { $0.isChosen }?.title == "Beta", "A keyboard open focuses the chosen option")
        optionPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(optionPanel.focusedRow == nil, "A pointer open focuses nothing")
        _ = optionPanel.handleKey(key(Keys.up))
        expect(optionPanel.focusedRow?.title == "Beta", "The first arrow key starts from the chosen option")
        optionPanel.host.close()
        // A chosen option wins over a toggle that is on, whatever their order.
        let mixed = MenuChoicePanel(menu: menu, identifier: "Mixed", accessibilityLabel: "Mixed", kind: { $0.title == "Delta" ? .option : .toggle })
        rig.attach(mixed.host)
        menu.items[8].state = .on
        mixed.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        expect(mixed.rows.filter(\.isChosen).map(\.title) == ["Beta", "Delta"] && mixed.focusedRow?.title == "Delta", "With a toggle on and an option chosen, the option takes the keyboard (\(mixed.focusedRow?.title ?? "nil"))")
        menu.items[8].state = .off
        mixed.host.close()
        // With no chosen row it is the first enabled one.
        menu.items[1].state = .off
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        expect(panel.focusedRow?.title == "Alpha", "With nothing chosen a keyboard open focuses the first enabled row")
        menu.items[1].state = .on
        // Unhandled keys fall through to the window.
        expect(!panel.handleKey(key(122, chars: "\u{F704}")) && !panel.handleKey(key(0, chars: "a", modifiers: .command)) && !panel.handleKey(key(125, modifiers: .control)),
               "Function keys and Command / Control combinations are not the panel's: they are not consumed")
        expect(panel.handleKey(key(125, modifiers: [.numericPad, .function, .capsLock])), "...but an arrow with the flags AppKit adds (and Caps Lock) is")
        panel.host.close()

        // Hover fills come from the button itself and never move the keyboard focus.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        let alpha = panel.rows.first { $0.title == "Alpha" }!
        alpha.setHovered(true)
        expect(alpha.plate.style.fill != nil && panel.focusedRow?.title == "Alpha", "Hovering a row fills it")
        let delta = panel.rows.first { $0.title == "Delta" }!
        delta.setHovered(true)
        expect(delta.plate.style.fill != nil && panel.focusedRow?.title == "Alpha", "...without moving the keyboard focus")
        delta.setHovered(false)
        alpha.setHovered(false)
        panel.host.close()

        // Disabled-only panel: nothing to focus, nothing crashes.
        let dead = NSMenu()
        let off = NSMenuItem(title: "Off", action: #selector(MenuFixture.act(_:)), keyEquivalent: "")
        off.target = fixture
        fixture.disabledTitles = ["Off"]
        dead.addItem(off)
        let deadPanel = MenuChoicePanel(menu: dead, identifier: "Dead", accessibilityLabel: "Dead")
        rig.attach(deadPanel.host)
        deadPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        _ = deadPanel.handleKey(key(Keys.down))
        _ = deadPanel.handleKey(key(Keys.enter))
        expect(deadPanel.focusedRow == nil && deadPanel.host.isShown, "A panel of disabled rows focuses nothing and chooses nothing")
        deadPanel.host.close()
    }

    // MARK: menu panel: submenus

    private static func submenuTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        let menu = NSMenu()
        menu.delegate = fixture
        let plain = NSMenuItem(title: "Plain", action: #selector(MenuFixture.act(_:)), keyEquivalent: "")
        plain.target = fixture
        let parent = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "More")
        let subLog = Log()
        let subFixture = MenuFixture(log: subLog)
        sub.delegate = subFixture
        for title in ["Inner one", "Inner two"] {
            let item = NSMenuItem(title: title, action: #selector(MenuFixture.act(_:)), keyEquivalent: "")
            item.target = subFixture
            sub.addItem(item)
        }
        parent.submenu = sub
        menu.addItem(plain)
        menu.addItem(.separator())
        menu.addItem(parent)
        let panel = MenuChoicePanel(menu: menu, identifier: "Sub", accessibilityLabel: "Sub")
        rig.attach(panel.host)
        func press(_ code: UInt16) { panel.host.window.sendEvent(key(code)) }

        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        let more = panel.rows.first { $0.title == "More" }!
        expect(more.kind == .submenu && more.indicator == .chevron && more.accessibilityRole() == .menuButton && more.showsTrailingGlyph, "A submenu item is a submenu row with a chevron")
        expect(!panel.isBackRowShown && panel.path.count == 1, "The top level has no Back row")

        // Drilling in replaces the rows with the submenu's, led by a Back row; the submenu's hooks run.
        panel.activate(more)
        expect(panel.host.isShown && panel.path.count == 2 && panel.isBackRowShown, "Activating a submenu row drills in without closing")
        expect(panel.rows.map(\.title) == ["Back", "Inner one", "Inner two"] && panel.rows[0].identifier?.rawValue == "choice.back", "The submenu's rows follow a leading Back row: \(panel.rows.map(\.title))")
        expect(panel.rows[0].icon == .chevronLeft && panel.rows[0].leadingIconImage != nil, "The Back row carries the left chevron")
        expect(subLog.index(of: "needsUpdate") != nil && subLog.index(of: "willOpen") != nil, "The submenu's delegate runs on entry")
        expect(panel.host.plates.count == 1 && descendants(panel.host.window.contentView!).filter { $0 is NSGlassEffectContainerView }.count == 1, "The panel rebuilt its plates inside the same container")

        // Left goes back; so does Escape; the submenu row regains focus.
        press(Keys.left)
        expect(panel.path.count == 1 && !panel.isBackRowShown && panel.rows.map(\.title) == ["Plain", "More"] && panel.focusedRow?.title == "More", "Left leaves the submenu and focuses the row it came from")
        expect(subLog.count("didClose") == 1, "...telling the submenu's delegate it closed")
        press(Keys.right)
        expect(panel.path.count == 2 && panel.focusedRow?.title == "Inner one", "Right on a submenu row enters it and focuses its first row")
        press(Keys.escape)
        expect(panel.host.isShown && panel.path.count == 1, "Escape inside a submenu goes back instead of closing")
        press(Keys.escape)
        expect(!panel.host.isShown, "Escape at the top level closes")

        // Back row activation, and choosing an inner item closes everything and performs it.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        panel.activate(panel.rows.first { $0.title == "More" }!)
        panel.activate(panel.rows[0])
        expect(panel.path.count == 1 && panel.host.isShown, "The Back row goes back")
        panel.activate(panel.rows.first { $0.title == "More" }!)
        subLog.lines = []
        panel.activate(panel.rows.first { $0.title == "Inner two" }!)
        expect(!panel.host.isShown && subLog.count("act:Inner two") == 1 && subLog.count("didClose") == 1, "Choosing an inner item closes the panel and performs it through its own menu: \(subLog.lines)")
        expect(panel.path.isEmpty, "A closed panel has left every menu")

        // A fresh open starts at the top again.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.path.count == 1 && panel.rows.map(\.title) == ["Plain", "More"], "A fresh open starts at the top level")
        panel.host.close()
    }





    // MARK: the tree an external client sees

    /// Reached rows: role, label and value, found by walking the tree the AX server publishes (window.accessibilityChildren() down), never from the row objects.
    private static func expectRow(_ tree: AXTree.Tree, _ role: NSAccessibility.Role, _ label: String, value: Int? = nil, enabled: Bool = true, in context: String) {
        guard let node = tree.find(role, label) else { return expect(false, "\(context): \(role.rawValue) \"\(label)\" is not reachable from the window. Tree:\n\(tree.outline)") }
        if let value { expect(node.number == value, "\(context): \"\(label)\" has value \(value) (got \(String(describing: node.value)))") }
        expect(node.enabled == enabled, "\(context): \"\(label)\" is \(enabled ? "enabled" : "disabled") for assistive technology")
    }

    private static func expectCoherent(_ tree: AXTree.Tree, _ context: String) {
        let problems = tree.parentProblems()
        expect(problems.isEmpty, "\(context): parents agree with the tree and lead back to the window: \(problems.prefix(4))")
        // The shape a client sees: every list an element hands out holds real elements (no raw views the server would wrap as AXUnknown), no node of
        // unknown role.
        let shape = tree.shapeProblems()
        expect(shape.isEmpty, "\(context): the tree has no AXUnknown wrapper, role-less node (\(shape.count)): \(shape.prefix(4))")
    }

    private static func externalTreeTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        func item(_ menu: NSMenu, _ title: String, state: NSControl.StateValue = .off, enabled: Bool = true) {
            let made = NSMenuItem(title: title, action: #selector(MenuFixture.act(_:)), keyEquivalent: "")
            made.target = fixture
            made.state = state
            menu.addItem(made)
            if !enabled { fixture.disabledTitles.insert(title) }
        }

        // The Toolbox: five groups, 18 rows, three of them toggles.
        let toolboxTitles = [["Save to History", "Export…"], ["Copy", "Paste", "Duplicate", "Delete", "Select All"], ["Snap", "Fullscreen Snapshot", "Frame Snapshot", "Re-snap"],
                             ["Rotate Clockwise", "Flip Horizontal", "Crop Snap at Current Edges", "Remove Snap Picture"], ["Filled Shapes", "Shadow", "Text Style…"]]
        let toolbox = NSMenu(title: "Toolbox")
        for (index, group) in toolboxTitles.enumerated() {
            if index > 0 { toolbox.addItem(.separator()) }
            for title in group { item(toolbox, title, state: title == "Shadow" ? .on : .off) }
        }
        let toggles: Set<String> = ["Filled Shapes", "Shadow", "Text Style…"]
        let toolboxPanel = MenuChoicePanel(menu: toolbox, identifier: "Toolbox", accessibilityLabel: "Toolbox", kind: { toggles.contains($0.title) ? .toggle : .command })
        rig.attach(toolboxPanel.host)
        toolboxPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        var tree = AXTree.walk(toolboxPanel.host.window)
        guard let root = tree.find(.group, "Toolbox") else { return expect(false, "The Toolbox panel's group is reachable from its window:\n\(tree.outline)") }
        expect(tree.children(of: root).count == 18 && tree.descendants(of: root).count == 18, "The Toolbox group holds the 18 rows and nothing else (\(tree.children(of: root).count)):\n\(tree.outline)")
        for title in toolboxTitles.joined() {
            expectRow(tree, toggles.contains(title) ? .checkBox : .button, title, value: toggles.contains(title) ? (title == "Shadow" ? 1 : 0) : nil, in: "Toolbox")
        }
        expect(tree.children(of: root).map { $0.label ?? "" } == Array(toolboxTitles.joined()), "The rows come in the panel's visual order, top to bottom")
        expectCoherent(tree, "Toolbox")
        // AXPress on a row reached from the window performs it and closes the panel.
        log.lines = []
        guard let paste = tree.find(.button, "Paste") else { return expect(false, "Paste is reachable") }
        expect(AXTree.press(paste) && log.count("act:Paste") == 1 && !toolboxPanel.host.isShown, "AXPress on the reached Paste row performs the command and closes the panel")

        // The zoom: percentages are options (value 0/1), Actual Size is a toggle command.
        let zoom = GlassPopUpButton(frame: NSRect(x: 300, y: 300, width: 120, height: 36), pullsDown: false)
        zoom.menu?.autoenablesItems = false
        zoom.addItems(withTitles: ["25%", "50%", "75%", "100%", "150%", "200%"])
        zoom.selectItem(withTitle: "100%")
        zoom.menu?.addItem(.separator())
        let actualSize = NSMenuItem(title: "Actual Size", action: #selector(MenuFixture.act(_:)), keyEquivalent: ""); actualSize.target = fixture
        zoom.menu?.addItem(actualSize)
        zoom.panelIdentifier = "Zoom"; zoom.panelLabel = "Canvas zoom"
        rig.window.contentView?.addSubview(zoom)
        rig.attach(zoom.choicePanel.host)
        zoom.performClick(nil)
        tree = AXTree.walk(zoom.choicePanel.host.window)
        for percent in ["25%", "50%", "75%", "100%", "150%", "200%"] { expectRow(tree, .radioButton, percent, value: percent == "100%" ? 1 : 0, in: "Zoom") }
        expectRow(tree, .button, "Actual Size", in: "Zoom")
        expect(tree.find(.group, "Canvas zoom").map { tree.children(of: $0).count } == 7, "The zoom group holds six percentages and Actual Size")
        expectCoherent(tree, "Zoom")
        zoom.choicePanel.host.close()
        zoom.removeFromSuperview()

        // A pop-up on a window is published as itself (its value, its name, its actions), so an assistive client's AXPress and AXShowMenu reach the
        // glass panel and not AppKit's own pop-up tracking.
        let face = GlassPopUpButton(frame: NSRect(x: 300, y: 200, width: 160, height: 36), pullsDown: false)
        face.addItems(withTitles: ["One", "Two", "Three"])
        face.selectItem(withTitle: "Two")
        face.setAccessibilityLabel("Preset")
        face.panelIdentifier = "AXFace"; face.panelLabel = "Preset"
        rig.window.contentView?.addSubview(face)
        rig.attach(face.choicePanel.host)
        rig.presented = []
        tree = AXTree.walk(rig.window)
        guard let faceNode = tree.find(.popUpButton, "Preset") else { return expect(false, "The pop-up is reachable from its window:\n\(tree.outline)") }
        expect(faceNode.text == "Two" && faceNode.enabled && faceNode.object === face, "The pop-up is published as itself, with its selected title as the value (\(String(describing: faceNode.value)))")
        expect(AXTree.press(faceNode) && face.choicePanel.host.isShown && rig.presented.count == 1, "AXPress on the reached pop-up opens the glass panel")
        face.choicePanel.host.close()
        rig.presented = []
        expect(faceNode.element.accessibilityPerformShowMenu() && face.choicePanel.host.isShown && rig.presented.count == 1, "AXShowMenu on the reached pop-up opens the glass panel")
        face.choicePanel.host.close()
        face.removeFromSuperview()

        // The Upload panel: destinations are options (the default chosen), the rest commands, one row disabled.
        let upload = NSMenu(title: "Upload")
        item(upload, "AWS cdn", state: .on); item(upload, "Backup SFTP"); upload.addItem(.separator())
        item(upload, "Destination Settings…"); item(upload, "Share with macOS…"); item(upload, "No destination configured", enabled: false)
        let uploadPanel = MenuChoicePanel(menu: upload, identifier: "Upload", accessibilityLabel: "Upload destinations",
                                          kind: { ["AWS cdn", "Backup SFTP"].contains($0.title) ? .option : .command })
        rig.attach(uploadPanel.host)
        uploadPanel.present(relativeTo: rig.anchor, preferredEdge: .maxY, keyboard: false)
        tree = AXTree.walk(uploadPanel.host.window)
        expectRow(tree, .radioButton, "AWS cdn", value: 1, in: "Upload"); expectRow(tree, .radioButton, "Backup SFTP", value: 0, in: "Upload")
        expectRow(tree, .button, "Destination Settings…", in: "Upload"); expectRow(tree, .button, "Share with macOS…", in: "Upload")
        expectRow(tree, .button, "No destination configured", enabled: false, in: "Upload")
        expectCoherent(tree, "Upload")
        uploadPanel.host.close()

        // The Capture key list: None plus fifty keys in a scrolling panel; every row is reachable, the scrolled-off ones too.
        let keys = GlassPopUpButton(frame: NSRect(x: 300, y: 300, width: 200, height: 36), pullsDown: false)
        keys.menu?.autoenablesItems = false
        let keyTitles = ["None"] + (1...12).map { "F\($0)" } + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) } + (0...9).map { String($0) }
        keys.addItems(withTitles: keyTitles)
        keys.selectItem(withTitle: "F5")
        keys.panelIdentifier = "CaptureKey"; keys.panelLabel = "Screen shortcut key"
        rig.window.contentView?.addSubview(keys)
        rig.attach(keys.choicePanel.host)
        keys.choicePanel.host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1440, height: 500)
        keys.performClick(nil)
        expect(keys.choicePanel.host.scrolls, "(setup) the key list scrolls in a 500 pt screen")
        tree = AXTree.walk(keys.choicePanel.host.window)
        expect(tree.nodes(role: .radioButton).count == keyTitles.count, "All \(keyTitles.count) key rows are reachable, scrolled-off ones included (got \(tree.nodes(role: .radioButton).count))")
        expectRow(tree, .radioButton, "F5", value: 1, in: "Capture key"); expectRow(tree, .radioButton, "None", value: 0, in: "Capture key"); expectRow(tree, .radioButton, "9", value: 0, in: "Capture key")
        expect(tree.nodes.allSatisfy { $0.role != .scrollArea }, "The scroll area is not a level of its own in the tree")
        expectCoherent(tree, "Capture key")
        keys.choicePanel.host.close()
        keys.removeFromSuperview()

        // A section header is static text in the tree.
        let sectioned = NSMenu()
        sectioned.addItem(NSMenuItem.sectionHeader(title: "Recent"))
        item(sectioned, "One"); item(sectioned, "Two")
        let sectionPanel = MenuChoicePanel(menu: sectioned, identifier: "Sectioned", accessibilityLabel: "Sectioned")
        rig.attach(sectionPanel.host)
        sectionPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        tree = AXTree.walk(sectionPanel.host.window)
        expectRow(tree, .staticText, "Recent", in: "Sectioned"); expectRow(tree, .button, "One", in: "Sectioned"); expectCoherent(tree, "Sectioned")
        sectionPanel.host.close()

        // Ordinary windows: a labelled plate of toggles (Settings' Snapping), an unlabelled one, and a radio group.
        let window = NonorderingWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let snap = makeButton("Snap to the nearest edge", .toggle, indicator: .checkbox), crosshair = makeButton("Show a crosshair", .toggle, indicator: .checkbox)
        crosshair.isChosen = true
        let snapping = GlassChrome.plate([snap, crosshair], identifier: "Snapping", accessibility: plain, axis: .vertical)
        snapping.setAccessibilityElement(true); snapping.setAccessibilityLabel("Snapping"); snapping.setAccessibilityRole(.group)
        let hint = makeButton("Hover hints", .toggle, indicator: .checkbox)
        let plain = GlassChrome.plate([hint], identifier: "Hints", accessibility: self.plain, axis: .vertical)
        let showIn = GlassChoiceGroup(titles: ["Dock", "Menu bar", "Both"], selectedIndex: 1, accessibilityLabel: "Show in", identifier: "showIn", accessibility: self.plain)
        for view in [snapping, plain, showIn] as [NSView] { place(view, in: window) }
        window.contentView?.subviews.enumerated().forEach { $0.element.setFrameOrigin(NSPoint(x: 20, y: 20 + 120 * CGFloat($0.offset))) }
        window.contentView?.layoutSubtreeIfNeeded()
        tree = AXTree.walk(window)
        guard let snappingGroup = tree.find(.group, "Snapping") else { return expect(false, "The labelled Snapping plate is reachable:\n\(tree.outline)") }
        expect(tree.children(of: snappingGroup).count == 2, "The labelled plate shows its two toggles (a glass plate that is an element used to answer with none): \(tree.children(of: snappingGroup).count)\n\(tree.outline)")
        expectRow(tree, .checkBox, "Snap to the nearest edge", value: 0, in: "Settings plate"); expectRow(tree, .checkBox, "Show a crosshair", value: 1, in: "Settings plate")
        expectRow(tree, .checkBox, "Hover hints", value: 0, in: "unlabelled plate")
        expect(tree.find(.group, "Snapping").map { tree.index(of: $0) } != nil && tree.descendants(of: snappingGroup).allSatisfy { $0.role == .checkBox }, "Only the toggles are below the plate")
        guard let radios = tree.find(.radioGroup, "Show in") else { return expect(false, "The Show-in radio group is reachable") }
        expect(tree.children(of: radios).map { $0.label ?? "" } == ["Dock", "Menu bar", "Both"] && tree.children(of: radios).map { $0.number } == [0, 1, 0], "The radio group shows its three radio buttons with value 0 / 1")
        expectCoherent(tree, "Settings-style window")
        guard let press = tree.find(.checkBox, "Snap to the nearest edge") else { return expect(false, "toggle reachable") }
        expect(AXTree.press(press) && snap.isChosen, "AXPress on a toggle reached from the window flips it")
        guard let radioPress = tree.find(.radioButton, "Both") else { return expect(false, "radio reachable") }
        expect(AXTree.press(radioPress) && showIn.selectedIndex == 2, "AXPress on a radio button reached from the window chooses it")
    }

    // MARK: Font Awesome glyphs on glass rows

    /// The Toolbox and the zoom's Actual Size are copies of main-menu items, which carry SF Symbols in the native menu bar. Their glass rows are
    /// app-owned UI and draw semantic Font Awesome glyphs instead, resolved through the icon chain; the native menu keeps everything it has.
    private static func menuIconTests() {
        // Action -> Free vector the default build (no Pro fonts) must draw. frame snap's Pro glyph camera-viewfinder is drawn by the Free `expand`.
        let table: [(action: String, title: String, free: String)] = [
            ("saveHistory", "Save to History", "box-archive"), ("exportFile", "Export…", "file-export"),
            ("copyArtwork", "Copy", "copy"), ("paste", "Paste", "paste"), ("duplicate", "Duplicate", "clone"), ("deleteSelection", "Delete", "trash"),
            ("selectAll", "Select All", "object-group"),
            ("screenSnap", "Snap", "crosshairs"), ("fullscreenSnap", "Fullscreen Snapshot", "display"), ("frameSnap", "Frame Snapshot", "expand"),
            ("resnap", "Re-snap", "camera-rotate"),
            ("rotateCW", "Rotate Clockwise", "arrow-rotate-right"), ("flipH", "Flip Horizontal", "left-right"),
            ("trimSnap", "Crop Snap at Current Edges", "crop-simple"), ("wipeSnap", "Remove Snap Picture", "broom"),
            ("toggleBezelFill:", "Filled Shapes", "shapes"), ("toggleBezelShadow:", "Shadow", "layer-group"), ("chooseFont", "Text Style…", "font"),
        ]
        expect(!FontAwesomeFont.isAvailable(.regular) && !FontAwesomeFont.isAvailable(.solid), "(setup) no Pro font is registered: the default build")
        let rig = Rig()

        // The "main menu": items with SF Symbols from MenuSymbols, the way the menu bar has them.
        let bar = NSMenu()
        bar.autoenablesItems = false
        var originals: [NSMenuItem] = []
        for (index, row) in table.enumerated() {
            let item = NSMenuItem(title: row.title, action: Selector(row.action), keyEquivalent: ["s", "e", "c", "v", "d", "\u{8}", "a", "1", "2", "3", "4", "r", "f", "t", "w", "i", "h", "y"][index])
            bar.addItem(item)
            originals.append(item)
        }
        MenuSymbols.apply(to: bar)
        expect(originals.allSatisfy { $0.image != nil && $0.image?.isTemplate == true }, "(setup) every native menu-bar item has its SF Symbol image")
        struct Snapshot: Equatable { var title: String, key: String, mask: UInt, action: Selector?, image: ObjectIdentifier?, state: Int }
        func snapshot(_ item: NSMenuItem) -> Snapshot {
            Snapshot(title: item.title, key: item.keyEquivalent, mask: item.keyEquivalentModifierMask.rawValue, action: item.action, image: item.image.map(ObjectIdentifier.init), state: item.state.rawValue)
        }
        let before = originals.map(snapshot)

        // The Toolbox: live copies of those items, five groups.
        let toolbox = NSMenu(title: "Toolbox")
        toolbox.autoenablesItems = false
        for (index, item) in originals.enumerated() {
            if [2, 7, 11, 15].contains(index) { toolbox.addItem(.separator()) }
            toolbox.addItem(item.copy() as! NSMenuItem)
        }
        let copies = toolbox.items.filter { !$0.isSeparatorItem }
        expect(copies.count == 18 && copies.allSatisfy { $0.image != nil }, "(setup) the copies carry the SF images too, as the app's Toolbox rows do")
        let toggles: Set<Selector> = [Selector("toggleBezelFill:"), Selector("toggleBezelShadow:"), Selector("chooseFont")]
        let panel = MenuChoicePanel(menu: toolbox, identifier: "IconsToolbox", accessibilityLabel: "Toolbox", kind: { $0.action.map(toggles.contains) == true ? .toggle : .command })
        rig.attach(panel.host)
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.rows.count == 18, "(setup) the Toolbox panel has its 18 rows")
        for (row, expected) in zip(panel.rows, table) {
            expect(row.title == expected.title, "(row order) \(expected.title)")
            expect(row.leadingIconImage !== panel.item(for: row)?.image, "Toolbox \"\(expected.title)\" shows the menu item's SF Symbol image instead of its Font Awesome glyph")
            expect(row.leadingIconSource == .fontAwesomeFree(expected.free), "Toolbox \"\(expected.title)\" draws the Free vector \(expected.free), not an SF Symbol (got \(row.leadingIconSource))")
            if case .sfSymbol = row.leadingIconSource { expect(false, "\(expected.title) must never resolve to an SF Symbol") }
            expect(row.leadingIconImage != nil && row.leadingIconImage?.isTemplate == true && row.leadingIconImage !== panel.item(for: row)?.image, "\(expected.title) shows the glyph, not the item's own image")
            expect(row.icon == MenuChoiceIcons.icon(for: panel.item(for: row)!) && row.icon != nil, "\(expected.title) is mapped by its action")
        }
        expect(MenuChoiceIcons.map.count == table.count + 1 && table.allSatisfy { MenuChoiceIcons.map[Selector($0.action)] != nil }, "The map covers the 18 Toolbox actions and Actual Size, nothing else")
        expect(panel.rows.allSatisfy { $0.reservesIconColumn }, "Every row reserves the icon column, so the titles line up")
        panel.activate(panel.rows[0])

        // The native menu bar is untouched by any of it: same SF images, titles, shortcuts, masks and actions.
        expect(originals.map(snapshot) == before, "The native menu-bar items keep their SF images, titles, shortcuts and actions")
        expect(originals.allSatisfy { $0.image?.isTemplate == true } && originals.map { $0.image }.allSatisfy { $0 != nil }, "...and still have an image")


        // Zoom's Actual Size: a copy of the main-menu item added to a pop-up of percentages.
        let actualOriginal = NSMenuItem(title: "Actual Size", action: Selector("toggleActualSize"), keyEquivalent: "0")
        let actualBar = NSMenu(); actualBar.autoenablesItems = false; actualBar.addItem(actualOriginal)
        MenuSymbols.apply(to: actualBar)
        expect(actualOriginal.image != nil, "(setup) the menu bar's Actual Size has its SF Symbol")
        let zoom = GlassPopUpButton(frame: NSRect(x: 300, y: 300, width: 120, height: 36), pullsDown: false)
        zoom.menu?.autoenablesItems = false
        zoom.addItems(withTitles: ["25%", "50%", "100%"])
        let actual = actualOriginal.copy() as! NSMenuItem
        actual.tag = 998
        zoom.menu?.addItem(.separator()); zoom.menu?.addItem(actual)
        rig.window.contentView?.addSubview(zoom)
        zoom.panelIdentifier = "IconsZoom"
        rig.attach(zoom.choicePanel.host)
        zoom.performClick(nil)
        let actualRow = zoom.choicePanel.rows.last!
        expect(actualRow.title == "Actual Size" && actualRow.leadingIconSource == .fontAwesomeFree("magnifying-glass") && actualRow.icon == .magnifyingGlass,
               "The zoom's Actual Size row draws the Free magnifying-glass (got \(actualRow.leadingIconSource))")
        expect(zoom.choicePanel.rows.dropLast().allSatisfy { $0.leadingIconImage == nil }, "...and the percentages have no glyph")
        expect(actualOriginal.image != nil && actualOriginal.title == "Actual Size" && actualOriginal.keyEquivalent == "0" && actualOriginal.action == Selector("toggleActualSize"), "The native Actual Size item is unchanged")
        zoom.choicePanel.host.close()
        zoom.removeFromSuperview()

        // An action the map does not know keeps the item's own image; a call site's hook goes ahead of the map.
        let other = NSMenu(); other.autoenablesItems = false
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
        let unknown = NSMenuItem(title: "Something else", action: Selector("notInTheMap"), keyEquivalent: ""); unknown.image = image
        let mapped = NSMenuItem(title: "Paste", action: Selector("paste"), keyEquivalent: ""); mapped.image = image
        let hooked = NSMenuItem(title: "Hooked", action: Selector("saveHistory"), keyEquivalent: ""); hooked.image = image
        for item in [unknown, mapped, hooked] { other.addItem(item) }
        let mixed = MenuChoicePanel(menu: other, identifier: "IconsMixed", accessibilityLabel: "Mixed")
        rig.attach(mixed.host)
        mixed.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(mixed.rows[0].leadingIconImage === image && mixed.rows[0].leadingIconSource == .none && mixed.rows[0].icon == nil, "An unmapped action keeps the item's image")
        expect(mixed.rows[1].leadingIconSource == .fontAwesomeFree("paste") && mixed.rows[1].leadingIconImage !== image, "A mapped action ignores the item's image")
        mixed.host.close()
        mixed.rowIcon = { $0.title == "Hooked" ? FAIcon.gear : (nil as FAIcon?) }
        mixed.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(mixed.rows[2].leadingIconSource == .fontAwesomeFree("gear") && mixed.rows[1].leadingIconSource == .fontAwesomeFree("paste"), "A rowIcon hook wins over the map, and falls back to it when it returns nil")
        mixed.host.close()
        let pop = GlassPopUpButton(frame: NSRect(x: 300, y: 300, width: 120, height: 36), pullsDown: false)
        pop.menu?.autoenablesItems = false
        pop.addItems(withTitles: ["One", "Two"])
        pop.rowIcon = { $0.title == "Two" ? FAIcon.globe : (nil as FAIcon?) }
        rig.window.contentView?.addSubview(pop)
        rig.attach(pop.choicePanel.host)
        pop.performClick(nil)
        expect(pop.choicePanel.rows[1].leadingIconSource == .fontAwesomeFree("globe") && pop.choicePanel.rows[0].leadingIconImage == nil, "A pop-up passes its rowIcon hook through")
        pop.choicePanel.host.close()
        pop.removeFromSuperview()

        // The chain: when the Free vector misses, the same row falls back to the icon's SF Symbol (never to nothing).
        let savedFree = ChromeIcons.freeGlyph
        ChromeIcons.freeGlyph = { _, _ in nil }
        defer { ChromeIcons.freeGlyph = savedFree }
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(zip(panel.rows, table).allSatisfy { row, expected in row.leadingIconSource == .sfSymbol(row.icon!.sfSymbolFallback) && row.leadingIconImage != nil },
               "With no Free vector a mapped row falls back to the icon's SF Symbol through the chain")
        panel.host.close()
    }

    // MARK: Return belongs to the default button

    /// A sheet with a default button: Return and Enter on a focused choice go to the button, never to the choice. Tested two ways: the key
    /// delivered straight to the focused control (proving the handler itself lets Return go up the responder chain, to a probe that stands in for
    /// the window), and through `window.sendEvent` (AppKit offers a key equivalent to the OK button before the control ever sees it).
    private static func returnKeyTests() {
        let window = NonorderingWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let probe = KeyProbeView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        window.contentView = probe
        let okTarget = ClickTarget()
        let ok = NSButton(title: "OK", target: okTarget, action: #selector(ClickTarget.clicked(_:)))
        ok.frame = NSRect(x: 560, y: 20, width: 100, height: 36)
        ok.identifier = NSUserInterfaceItemIdentifier("OK")
        probe.addSubview(ok)
        let groupTarget = ClickTarget()
        let group = GlassChoiceGroup(titles: ["Resize", "Crop", "Limit"], selectedIndex: 0, accessibilityLabel: "Mode", identifier: "mode", accessibility: plain)
        group.target = groupTarget
        group.action = #selector(ClickTarget.clicked(_:))
        place(group, in: window)
        let toggleTarget = ClickTarget()
        let toggle = makeButton("Lock proportions", .toggle, indicator: .checkbox, target: toggleTarget)
        toggle.frame = NSRect(x: 20, y: 200, width: 260, height: 36)
        probe.addSubview(toggle)
        let pop = GlassPopUpButton(frame: NSRect(x: 20, y: 260, width: 170, height: 36), pullsDown: false)
        pop.addItems(withTitles: ["Fixed", "Free"])
        probe.addSubview(pop)
        let rig = Rig()
        rig.attach(pop.choicePanel.host)
        func setDefault(_ on: Bool) {
            ok.keyEquivalent = on ? "\r" : ""
            window.defaultButtonCell = on ? ok.cell as? NSButtonCell : nil
            probe.forwardsToWindow = on
        }

        // Without a default button, Return and Enter choose the focused segment.
        setDefault(false)
        _ = window.makeFirstResponder(group.buttons[1])
        window.sendEvent(key(Keys.enter, chars: "\r"))
        expect(group.selectedIndex == 1 && groupTarget.senders.count == 1 && okTarget.senders.isEmpty && probe.keys.isEmpty, "With no default button Return chooses the focused segment (selected \(group.selectedIndex), ok \(okTarget.senders))")
        window.sendEvent(key(Keys.keypadEnter, chars: "\r"))
        expect(groupTarget.senders.count == 1, "...and choosing the chosen segment again sends nothing")
        group.selectedIndex = 0
        groupTarget.senders = []

        // With one, the handler does not take the key: it goes up the responder chain and the choice stays.
        setDefault(true)
        for (name, code) in [("Return", Keys.enter), ("keypad Enter", Keys.keypadEnter)] {
            _ = window.makeFirstResponder(group.buttons[1])
            probe.keys = []
            group.buttons[1].keyDown(with: key(code, chars: "\r"))
            expect(group.selectedIndex == 0 && groupTarget.senders.isEmpty && !group.buttons[1].isChosen, "\(name) on a focused segment does not move the choice when the window has a default button")
            expect(probe.keys == [code], "...and the key goes up the responder chain to the window (\(probe.keys))")
            okTarget.senders = []
            window.sendEvent(key(code, chars: "\r"))
            expect(group.selectedIndex == 0 && groupTarget.senders.isEmpty && okTarget.senders == ["OK"], "...and through the window the default button fires exactly once (\(okTarget.senders))")
        }
        // Space still chooses, and the arrows (with the flags AppKit adds) still move.
        _ = window.makeFirstResponder(group.buttons[2])
        window.sendEvent(key(Keys.space, chars: " "))
        expect(group.selectedIndex == 2 && groupTarget.senders.count == 1, "Space still chooses the focused segment next to a default button")
        window.sendEvent(key(Keys.left, modifiers: [.numericPad, .function]))
        expect(group.selectedIndex == 1 && groupTarget.senders.count == 2 && window.firstResponder === group.buttons[1], "A real arrow event (numeric pad + function flags) moves the choice and the focus")
        window.sendEvent(key(Keys.right, modifiers: [.numericPad, .function, .capsLock]))
        expect(group.selectedIndex == 2 && groupTarget.senders.count == 3, "...Caps Lock does not matter either")
        window.sendEvent(key(Keys.left, modifiers: [.numericPad, .function, .command]))
        window.sendEvent(key(Keys.left, modifiers: [.numericPad, .function, .option]))
        expect(group.selectedIndex == 2 && groupTarget.senders.count == 3, "A Command or Option arrow is someone else's shortcut: the group leaves it alone")

        // A focused toggle: Return is the default button's; Space flips.
        _ = window.makeFirstResponder(toggle)
        probe.keys = []
        toggle.keyDown(with: key(Keys.enter, chars: "\r"))
        expect(!toggle.isChosen && toggleTarget.states.isEmpty && probe.keys == [Keys.enter], "Return on a focused toggle goes up the chain and does not flip it (\(probe.keys))")
        okTarget.senders = []
        window.sendEvent(key(Keys.enter, chars: "\r"))
        expect(!toggle.isChosen && toggleTarget.states.isEmpty && okTarget.senders == ["OK"], "...and through the window it fires the default button")
        window.sendEvent(key(Keys.space, chars: " "))
        expect(toggle.isChosen && toggleTarget.states == [.on], "Space flips it")

        // A pop-up: Return and Enter go to the default button, Space / Down / Up open it (with AppKit's arrow flags).
        _ = window.makeFirstResponder(pop)
        probe.keys = []
        rig.presented = []
        pop.keyDown(with: key(Keys.enter, chars: "\r"))
        pop.keyDown(with: key(Keys.keypadEnter, chars: "\r"))
        expect(rig.presented.isEmpty && probe.keys == [Keys.enter, Keys.keypadEnter], "Return and Enter on a focused pop-up go up the chain and open nothing (\(probe.keys))")
        okTarget.senders = []
        window.sendEvent(key(Keys.enter, chars: "\r"))
        expect(rig.presented.isEmpty && okTarget.senders == ["OK"], "...and through the window they fire the default button")
        window.sendEvent(key(Keys.down, modifiers: [.numericPad, .function]))
        expect(pop.choicePanel.host.isShown && rig.presented.count == 1, "A real Down arrow opens the pop-up")
        pop.choicePanel.host.close()
        window.sendEvent(key(Keys.down, modifiers: [.numericPad, .function, .command]))
        expect(!pop.choicePanel.host.isShown, "Command-Down is not the pop-up's")
        setDefault(false)
    }

    // MARK: type to select

    private static func typeAheadTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        fixture.disabledTitles = ["Delete"]
        let menu = NSMenu()
        for title in ["None", "Escape", "Delete", "Return", "Right Command", "Right Option", "Éclair", "Echo", "F1", "Space bar"] {
            let item = NSMenuItem(title: title, action: #selector(MenuFixture.act(_:)), keyEquivalent: "")
            item.target = fixture
            menu.addItem(item)
        }
        let panel = MenuChoicePanel(menu: menu, identifier: "Type", accessibilityLabel: "Type")
        rig.attach(panel.host)
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        var clock: TimeInterval = 100
        func type(_ text: String, after gap: TimeInterval = 0.2) {
            clock += gap
            for character in text {
                clock += gap == 0 ? 0 : 0.05
                panel.host.window.sendEvent(key(character == " " ? Keys.space : 0, chars: String(character), timestamp: clock))
            }
        }
        expect(panel.focusedRow?.title == "None", "(setup) the keyboard open starts on the first row")

        type("r", after: 2)
        expect(panel.focusedRow?.title == "Return", "r focuses the first row starting with r, searching from the row after the focused one")
        type("i")
        expect(panel.focusedRow?.title == "Right Command", "ri extends the prefix and moves on to the first match (\(panel.focusedRow?.title ?? "nil"))")
        type("ght o")
        expect(panel.focusedRow?.title == "Right Option", "Space is part of the prefix while one is being typed: \"right o\" finds Right Option (\(panel.focusedRow?.title ?? "nil"))")
        // The prefix lives about a second: after a pause a new one starts, searching on from the row after the focused one.
        type("e", after: 1.5)
        expect(panel.focusedRow?.title == "Éclair", "After a pause a new prefix starts: e finds the next row starting with e, ignoring the accent (\(panel.focusedRow?.title ?? "nil"))")
        type("e", after: 1.5)
        expect(panel.focusedRow?.title == "Echo", "...and the same letter again cycles on (\(panel.focusedRow?.title ?? "nil"))")
        type("e", after: 1.5)
        expect(panel.focusedRow?.title == "Escape", "...wrapping round the end of the list (\(panel.focusedRow?.title ?? "nil"))")
        type("e", after: 1.5)
        type("c")
        expect(panel.focusedRow?.title == "Éclair", "ec keeps Éclair: a longer prefix stays on the focused row while it still matches (\(panel.focusedRow?.title ?? "nil"))")
        type("h")
        expect(panel.focusedRow?.title == "Echo", "ech moves on to Echo (\(panel.focusedRow?.title ?? "nil"))")
        type("É", after: 1.5)
        expect(panel.focusedRow?.title == "Escape", "An upper-case accented letter matches case- and diacritic-insensitively: the first e-row after Echo, wrapping (\(panel.focusedRow?.title ?? "nil"))")
        // A disabled row is never found, and an unmatched prefix keeps the focus.
        type("d", after: 1.5)
        expect(panel.focusedRow?.title == "Escape", "Delete is disabled: d finds nothing and the focus stays")
        type("z", after: 1.5)
        expect(panel.focusedRow?.title == "Escape", "A prefix nothing starts with leaves the focus alone")
        // Printable keys are consumed (no beep); function keys are not typed characters.
        clock += 5
        expect(panel.handleKey(key(0, chars: "q", timestamp: clock)), "A printable key is consumed even when nothing matches")
        expect(!panel.handleKey(key(122, chars: "\u{F704}")), "A function key is not a typed character")
        // An arrow ends the prefix: the next letter starts a new one.
        type("r", after: 2)
        expect(panel.focusedRow?.title == "Return", "(setup) r from Escape finds Return")
        _ = panel.handleKey(key(Keys.down, timestamp: clock + 0.1))
        expect(panel.focusedRow?.title == "Right Command", "A real Down arrow still moves the focus")
        type("e", after: 0.2)
        expect(panel.focusedRow?.title == "Éclair", "A letter right after an arrow is a fresh prefix, not \"re\" (which would go back to Return): \(panel.focusedRow?.title ?? "nil")")
        // Space chooses when no prefix is being typed, and does not when one is.
        type("f", after: 3)
        expect(panel.focusedRow?.title == "F1", "(setup) f finds F1")
        log.lines = []
        panel.host.window.sendEvent(key(Keys.space, chars: " ", timestamp: clock + 3))
        expect(!panel.host.isShown && log.count("act:F1") == 1, "Space with no prefix being typed chooses the focused row")
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        clock += 10
        type("s", after: 0)
        expect(panel.focusedRow?.title == "Space bar" && panel.host.isShown, "s finds Space bar")
        log.lines = []
        panel.host.window.sendEvent(key(Keys.space, chars: " ", timestamp: clock + 0.1))
        expect(panel.host.isShown && log.count("act:Space bar") == 0 && panel.focusedRow?.title == "Space bar", "Space right after a typed letter is part of the prefix, not a choice")
        panel.host.window.sendEvent(key(Keys.enter, chars: "\r", timestamp: clock + 0.2))
        expect(!panel.host.isShown && log.count("act:Space bar") == 1, "Return chooses")
        // A Command letter is a shortcut, not a type.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        expect(!panel.handleKey(key(0, chars: "r", modifiers: .command, timestamp: clock + 20)) && panel.focusedRow?.title == "None", "Command-r is not type-to-select")
        // The prefix does not leak into the next open: \"r\" then a reopen then \"i\" is just \"i\" (not \"ri\", which would find Right Command).
        type("r", after: 30)
        expect(panel.focusedRow?.title == "Return", "(setup) r finds Return")
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        type("i", after: 0.1)
        expect(panel.focusedRow?.title == "None", "A new open starts a new prefix (\(panel.focusedRow?.title ?? "nil"))")
        panel.host.close()
    }

    // MARK: a menu rebuilt while the panel is open

    private static func rebuiltMenuTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        func build(_ menu: NSMenu, titles: [String]) {
            menu.removeAllItems()
            for title in titles {
                let item = NSMenuItem(title: title, action: #selector(MenuFixture.act(_:)), keyEquivalent: "")
                item.target = fixture
                item.representedObject = "id-\(title.prefix(5))"
                menu.addItem(item)
            }
        }
        let menu = NSMenu()
        build(menu, titles: ["Alpha one", "Beta two", "Gamma three"])
        let panel = MenuChoicePanel(menu: menu, identifier: "Rebuilt", accessibilityLabel: "Rebuilt")
        rig.attach(panel.host)
        var senders: [NSMenuItem] = []
        fixture.onAction = { senders.append($0) }

        // Still in the menu: the row's own item is performed.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        let stable = panel.rows[1]
        let stableItem = panel.item(for: stable)
        panel.activate(stable)
        expect(log.count("act:Beta two") == 1 && senders.last === stableItem, "(setup) an item still in the menu is performed as itself")

        // Rebuilt with equivalent items (same action, represented object and title): the NEW item is performed, not nothing.
        senders = []
        log.lines = []
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        let staleRow = panel.rows[1], staleItem = panel.item(for: staleRow)!
        build(menu, titles: ["Alpha one", "Beta two", "Gamma three"])
        expect(staleItem.menu == nil && menu.index(of: staleItem) == -1, "(setup) the row's item left the menu")
        panel.activate(staleRow)
        expect(!panel.host.isShown && log.count("act:Beta two") == 1, "A row whose item was replaced by an equivalent one still performs it (\(log.lines))")
        expect(senders.count == 1 && senders[0] !== staleItem && senders[0] === menu.items[1], "...as the menu's current item, not the stale one")

        // The title changed with the state, but the action and represented object still identify it.
        senders = []
        log.lines = []
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        let renamedRow = panel.rows[2]
        build(menu, titles: ["Alpha one", "Beta two", "Gamma three (new)"])
        menu.items[2].representedObject = "id-Gamma"
        panel.activate(renamedRow)
        expect(log.count("act:Gamma three (new)") == 1 && senders.first === menu.items[2], "A changed title is matched by action and represented object (\(log.lines))")

        // Nothing equivalent is left: the chosen item's own action is still sent, rather than silently doing nothing.
        senders = []
        log.lines = []
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        let orphanRow = panel.rows[0], orphan = panel.item(for: orphanRow)!
        menu.removeAllItems()
        panel.activate(orphanRow)
        expect(!panel.host.isShown && log.count("act:Alpha one") == 1 && senders.first === orphan, "With no equivalent left the chosen item's own action still runs (\(log.lines))")

        // A pop-up whose menu was rebuilt: the equivalent new item is the one selected.
        let popLog = Log()
        let popFixture = MenuFixture(log: popLog)
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 100, height: 30), pullsDown: false)
        pop.addItems(withTitles: ["25%", "50%", "100%"])
        pop.target = popFixture
        pop.action = #selector(MenuFixture.popChanged(_:))
        let popPanel = MenuChoicePanel(menu: pop.menu!, identifier: "RebuiltPop", accessibilityLabel: "Zoom", kind: { _ in .option }, popUp: pop)
        rig.attach(popPanel.host)
        popPanel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        let staleChoice = popPanel.rows[1]
        pop.removeAllItems()
        pop.addItems(withTitles: ["25%", "50%", "100%"])
        popPanel.activate(staleChoice)
        expect(pop.indexOfSelectedItem == 1 && popLog.lines.contains("popAction:1"), "A rebuilt pop-up menu: the equivalent new item is selected and the pop-up's action sent (\(popLog.lines), selected \(pop.indexOfSelectedItem))")
    }

    // MARK: a host that is released or replaced while shown

    private final class RecordingWindow: NonorderingWindow {
        var removedChildren: [NSWindow] = []
        override func removeChildWindow(_ childWin: NSWindow) { removedChildren.append(childWin) }
    }

    private static func hostReleaseTests() {
        let parent = RecordingWindow(contentRect: NSRect(x: 200, y: 300, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        parent.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let anchor = NSButton(frame: NSRect(x: 40, y: 500, width: 80, height: 36))
        parent.contentView?.addSubview(anchor)
        let baseline = GlassPanelHost.installedMonitors
        var shownWindow: GlassChoiceWindow?
        weak var weakHost: GlassPanelHost?

        func makeHost(_ identifier: String) -> GlassPanelHost {
            let host = GlassPanelHost(plates: [plate(["One", "Two"])], identifier: identifier, accessibilityLabel: identifier)
            host.presenter = { window, _ in shownWindow = window }
            host.visibleFrameOverride = Rig.visible
            host.accessibility = .none
            return host
        }

        // Released while shown: the click monitor and the observers go, and the child window is taken off its parent.
        autoreleasepool {
            let host = makeHost("Released")
            host.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY, makeKey: true)
            weakHost = host
            expect(GlassPanelHost.installedMonitors == baseline + 1 && host.isShown, "(setup) a shown host has one click monitor")
        }
        expect(weakHost == nil, "A shown host is not kept alive by its own observers, monitor or callbacks")
        expect(GlassPanelHost.installedMonitors == baseline, "Releasing a shown host removes its click monitor (\(GlassPanelHost.installedMonitors) vs \(baseline))")
        expect(parent.removedChildren.contains { $0 === shownWindow }, "...and takes its window off the parent, so no orphan child window stays behind")
        // The notification observers are gone too: a late event reaches nothing.
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: parent)
        shownWindow = nil

        // An owner that replaces its host calls invalidate(): closed, no monitor, no keyboard handed anywhere.
        let first = makeHost("Replaced")
        var closes = 0
        first.didClose = { closes += 1 }
        first.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY, makeKey: true)
        expect(GlassPanelHost.installedMonitors == baseline + 1, "(setup) the replaced host is shown")
        first.invalidate()
        expect(!first.isShown && closes == 1 && GlassPanelHost.installedMonitors == baseline, "invalidate() closes a shown host and removes its monitor")
        first.invalidate()
        expect(closes == 1 && GlassPanelHost.installedMonitors == baseline, "...and is harmless twice")
        // An invalidated host can be shown again (it follows the display options once more).
        first.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY, makeKey: true)
        first.close()
        expect(GlassPanelHost.installedMonitors == baseline, "Showing and closing again leaves no monitor behind")

        // A menu panel released while open does the same through its host; a pop-up that replaces its menu invalidates the old panel.
        weak var weakPanel: MenuChoicePanel?
        autoreleasepool {
            let log = Log()
            let panel = MenuChoicePanel(menu: standardMenu(MenuFixture(log: log)), identifier: "ReleasedMenu", accessibilityLabel: "Menu")
            panel.host.presenter = { window, _ in shownWindow = window }
            panel.host.visibleFrameOverride = Rig.visible
            panel.present(relativeTo: anchor, preferredEdge: .minY, keyboard: false)
            weakPanel = panel
            expect(GlassPanelHost.installedMonitors == baseline + 1, "(setup) the menu panel is open")
        }
        expect(weakPanel == nil && GlassPanelHost.installedMonitors == baseline, "A released menu panel leaves no monitor behind")
        let pop = GlassPopUpButton(frame: NSRect(x: 300, y: 300, width: 160, height: 36), pullsDown: false)
        pop.addItems(withTitles: ["One", "Two"])
        parent.contentView?.addSubview(pop)
        let old = pop.choicePanel
        old.host.presenter = { window, _ in shownWindow = window }
        old.host.visibleFrameOverride = Rig.visible
        old.present(relativeTo: pop, preferredEdge: .minY, keyboard: false)
        expect(old.host.isShown && GlassPanelHost.installedMonitors == baseline + 1, "(setup) the pop-up's panel is open")
        pop.panelLabel = "Another label"
        expect(!old.host.isShown && GlassPanelHost.installedMonitors == baseline, "A pop-up that replaces its panel closes the old one and removes its monitor")
        pop.removeFromSuperview()
        shownWindow = nil
    }

    // MARK: glass pop-up button

    private static func mouse(_ type: NSEvent.EventType, on view: NSView, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let point = view.convert(NSPoint(x: min(20, view.bounds.midX), y: view.bounds.midY), to: nil)
        return NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: view.window?.windowNumber ?? -1, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }

    private static func popUpButtonTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        let probe = KeyProbeView(frame: NSRect(x: 300, y: 400, width: 200, height: 60))
        let pop = GlassPopUpButton(frame: NSRect(x: 10, y: 10, width: 170, height: 36), pullsDown: false)
        pop.addItems(withTitles: ["25%", "50%", "100%"])
        pop.target = fixture
        pop.action = #selector(MenuFixture.popChanged(_:))
        pop.selectItem(at: 2)
        pop.menu!.delegate = fixture
        pop.panelIdentifier = "Zoom"
        pop.panelLabel = "Zoom"
        probe.addSubview(pop)
        rig.window.contentView?.addSubview(probe)
        rig.attach(pop.choicePanel.host)
        expect(pop.preferredEdge == .minY && pop.choicePanel.host.window.identifier?.rawValue == "GlassChoicePanel.Zoom", "A glass pop-up opens below by default, into its own identified panel")

        // Every opening route presents the glass panel, once, and never starts AppKit's own pop-up tracking (the menu's willOpen would
        // fire a second time, and a click would block in the tracking loop).
        let routes: [(String, Bool, () -> Void)] = [
            ("click", false, { pop.mouseDown(with: mouse(.leftMouseDown, on: pop)) }),
            ("Control-click", false, { pop.mouseDown(with: mouse(.leftMouseDown, on: pop, modifiers: .control)) }),
            ("right click", false, { pop.rightMouseDown(with: mouse(.rightMouseDown, on: pop)) }),
            ("other button", false, { pop.otherMouseDown(with: mouse(.otherMouseDown, on: pop)) }),
            ("performClick", true, { pop.performClick(nil) }),
            ("Space", true, { pop.keyDown(with: key(Keys.space, chars: " ")) }),
            ("Return", true, { pop.keyDown(with: key(Keys.enter, chars: "\r")) }),
            ("keypad Enter", true, { pop.keyDown(with: key(Keys.keypadEnter, chars: "\r")) }),
            ("Down", true, { pop.keyDown(with: key(Keys.down)) }),
            ("Up", true, { pop.keyDown(with: key(Keys.up)) }),
            ("Down sent to the window", true, { _ = rig.window.makeFirstResponder(pop); rig.window.sendEvent(key(Keys.down)) }),
            ("accessibility press", true, { expect(pop.accessibilityPerformPress(), "AXPress is performed") }),
            ("accessibility Show Menu", true, { expect(pop.accessibilityPerformShowMenu(), "AXShowMenu is performed") }),
            ("keyboard context-menu command", true, { pop.showContextMenuForSelection(nil) }),
        ]
        for (name, keyboard, open) in routes {
            log.lines = []
            rig.presented = []
            open()
            let panel = pop.choicePanel
            expect(panel.host.isShown && rig.presented.count == 1 && rig.presented[0].0 === panel.host.window, "\(name) presents the glass panel (\(rig.presented.count) presents)")
            expect(log.count("needsUpdate") == 1 && log.count("willOpen") == 1, "\(name) runs the menu's open hooks once, so AppKit's own tracking never started: \(log.lines)")
            expect((panel.focusedRow != nil) == keyboard, "\(name) \(keyboard ? "focuses a row" : "leaves the rows unfocused")")
            if keyboard { expect(panel.focusedRow?.title == "100%", "\(name) lands on the selected choice") }
            panel.host.close()
        }
        expect(probe.keys.isEmpty, "None of the opening keys went on up the responder chain")
        expect(pop.menu(for: mouse(.rightMouseDown, on: pop)) == nil, "The pop-up has no context menu of its own")

        // A second click on the face while the panel is shown dismisses it and does not reopen it (the event monitor consumes the click).
        log.lines = []
        rig.presented = []
        pop.mouseDown(with: mouse(.leftMouseDown, on: pop))
        expect(pop.choicePanel.host.isShown && rig.presented.count == 1, "(setup) the panel is open")
        // What the app's event loop does with a press: the panel's local monitor first (a press it consumes is never dispatched), then
        // the window. (A manual NSApp.sendEvent runs monitors only as observers, so the two steps are spelled out.)
        func dispatch(_ event: NSEvent) {
            let host = pop.choicePanel.host
            if host.isShown, host.handleMouseDown(in: event.window, at: event.locationInWindow) { return }
            pop.mouseDown(with: event)   // the window would hit-test the face and send it the press
        }
        dispatch(mouse(.leftMouseDown, on: pop))
        expect(!pop.choicePanel.host.isShown && rig.presented.count == 1 && log.count("willOpen") == 1,
               "A second click on the face dismisses the panel and does not reopen it: \(log.lines) presents=\(rig.presented.count)")
        dispatch(mouse(.leftMouseDown, on: pop))
        expect(pop.choicePanel.host.isShown && rig.presented.count == 2, "The next click opens it again")
        pop.choicePanel.host.close()
        // Asking to open while it is open (VoiceOver pressing again) closes it.
        pop.performClick(nil)
        pop.performClick(nil)
        expect(!pop.choicePanel.host.isShown, "Opening an open pop-up closes it")

        // Return and keypad Enter belong to a default button; Space, Down and Up still open.
        let okTarget = ClickTarget()
        let ok = NSButton(title: "OK", target: okTarget, action: #selector(ClickTarget.clicked(_:)))
        ok.keyEquivalent = "\r"
        ok.frame = NSRect(x: 500, y: 100, width: 80, height: 30)
        rig.window.contentView?.addSubview(ok)
        rig.window.defaultButtonCell = ok.cell as? NSButtonCell
        _ = rig.window.makeFirstResponder(pop)
        for (name, code) in [("Return", Keys.enter), ("keypad Enter", Keys.keypadEnter)] {
            log.lines = []
            rig.presented = []
            probe.keys = []
            rig.window.sendEvent(key(code, chars: "\r"))
            expect(!pop.choicePanel.host.isShown && rig.presented.isEmpty && log.count("willOpen") == 0, "\(name) does not open the panel in a window with a default button")
            expect(probe.keys == [code], "\(name) is left for the default button: it went up the responder chain (\(probe.keys))")
        }
        for (name, code) in [("Space", Keys.space), ("Down", Keys.down), ("Up", Keys.up)] {
            rig.presented = []
            rig.window.sendEvent(key(code, chars: code == Keys.space ? " " : ""))
            expect(pop.choicePanel.host.isShown && rig.presented.count == 1, "\(name) still opens the panel next to a default button")
            pop.choicePanel.host.close()
        }
        rig.window.defaultButtonCell = nil
        probe.keys = []
        rig.presented = []
        rig.window.sendEvent(key(Keys.enter, chars: "\r"))
        expect(pop.choicePanel.host.isShown && probe.keys.isEmpty, "With no default button Return opens the panel")
        pop.choicePanel.host.close()
        // Other keys are not the pop-up's: they go up the chain (AppKit's type-ahead would open its native menu).
        probe.keys = []
        rig.window.sendEvent(key(0, chars: "a"))
        expect(probe.keys == [0] && !pop.choicePanel.host.isShown, "Other keys go up the responder chain and open nothing")
        ok.removeFromSuperview()

        // Not enabled, no window, nothing to choose: nothing opens.
        pop.isEnabled = false
        rig.presented = []
        pop.performClick(nil); pop.mouseDown(with: mouse(.leftMouseDown, on: pop)); _ = pop.accessibilityPerformPress(); _ = pop.accessibilityPerformShowMenu()
        expect(rig.presented.isEmpty && !pop.accessibilityPerformShowMenu() && !pop.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformPress)), "A disabled pop-up opens nothing and refuses the accessibility actions")
        expect(!pop.acceptsFirstResponder && !pop.canBecomeKeyView, "...and takes no focus")
        pop.isEnabled = true
        let empty = GlassPopUpButton(frame: NSRect(x: 0, y: 0, width: 100, height: 36), pullsDown: false)
        rig.window.contentView?.addSubview(empty)
        rig.attach(empty.choicePanel.host)
        empty.performClick(nil)
        expect(!empty.choicePanel.host.isShown, "A pop-up with no items opens nothing")
        empty.removeFromSuperview()
        let loose = GlassPopUpButton(frame: NSRect(x: 0, y: 0, width: 100, height: 36), pullsDown: false)
        loose.addItem(withTitle: "One")
        loose.performClick(nil)
        expect(!loose.choicePanel.host.isShown, "A pop-up not in a window opens nothing")

        // The presentation seam replaces presenting.
        var handled: [(MenuChoicePanel, Bool)] = []
        pop.presentHandler = { handled.append(($0, $1)) }
        pop.performClick(nil)
        pop.mouseDown(with: mouse(.leftMouseDown, on: pop))
        expect(handled.count == 2 && handled[0].1 && !handled[1].1 && handled[0].0 === pop.choicePanel && !pop.choicePanel.host.isShown, "presentHandler gets the panel and whether the keyboard opened it")
        pop.presentHandler = nil

        // Roles: plain items are options (radio buttons, value 0 / 1), the selected one chosen; items with their own action keep the default.
        let own = NSMenuItem(title: "Actual Size", action: #selector(MenuFixture.act(_:)), keyEquivalent: "")
        own.target = fixture
        pop.menu!.addItem(own)
        let withSubmenu = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        withSubmenu.submenu = NSMenu(title: "More")
        withSubmenu.submenu!.addItem(NSMenuItem(title: "Inner", action: nil, keyEquivalent: ""))
        pop.menu!.addItem(withSubmenu)
        pop.performClick(nil)
        let panel = pop.choicePanel
        expect(panel.rows.map(\.kind) == [.option, .option, .option, .command, .submenu], "Plain items are options, an own-action item a command, a submenu item a submenu row: \(panel.rows.map(\.kind))")
        expect(panel.rows.prefix(3).map { $0.accessibilityRole() } == [.radioButton, .radioButton, .radioButton], "Plain items read as radio buttons")
        expect(panel.rows.prefix(3).map { ($0.accessibilityValue() as? NSNumber)?.intValue } == [0, 0, 1], "...with value 1 on the selected item")
        panel.host.close()
        pop.selectItem(at: 0)
        pop.performClick(nil)
        expect(pop.choicePanel.rows.prefix(3).map(\.isChosen) == [true, false, false], "The chosen row follows the pop-up's selection")
        pop.choicePanel.activate(pop.choicePanel.rows[1])
        expect(pop.indexOfSelectedItem == 1 && !pop.choicePanel.host.isShown, "Choosing a plain item selects it and closes")
        expect(log.lines.last == "popAction:1", "...and sends the pop-up's own action")
        pop.kind = { _ in .toggle }
        rig.attach(pop.choicePanel.host)
        pop.performClick(nil)
        expect(pop.choicePanel.rows.allSatisfy { $0.kind == .toggle }, "A kind closure overrides the defaults")
        pop.choicePanel.host.close()
        pop.kind = nil
        rig.attach(pop.choicePanel.host)

        // The menu is the source of truth: a new menu gets a new panel, and the old one is closed.
        pop.performClick(nil)
        let before = pop.choicePanel
        let replacement = NSMenu()
        replacement.addItem(NSMenuItem(title: "Solo", action: nil, keyEquivalent: ""))
        pop.menu = replacement
        expect(!before.host.isShown && pop.choicePanel !== before && pop.choicePanel.menu === replacement, "Replacing the menu closes the old panel and builds a new one")
        pop.menu = before.menu
        rig.attach(pop.choicePanel.host)

        // Accessibility.
        expect(pop.accessibilityRole() == .popUpButton && (pop.accessibilityValue() as? String) == pop.titleOfSelectedItem && pop.accessibilityLabel() != nil, "A pop-up button with its selected title as the value, and a name")
        KeyboardNavigation.fullKeyboardAccess = { false }
        expect(!pop.canBecomeKeyView, "Tab reaches the pop-up only with Full Keyboard Access, like every chrome control")
        KeyboardNavigation.fullKeyboardAccess = { true }
        expect(pop.canBecomeKeyView, "...and does with it")

        // Face metrics: the defaults are the roomy ones; a tight face measures title + 2 x padding + chevron column and never truncates.
        expect(pop.facePadding == 12 && pop.chevronColumn == 33, "The default face metrics are unchanged: 12 pt padding, a 33 pt chevron column")
        let bodyAttributes: [NSAttributedString.Key: Any] = [.font: DesignTokens.Typography.font(.body)]
        func width(_ text: String) -> CGFloat { ceil((text as NSString).size(withAttributes: bodyAttributes).width) }
        let allTitles = pop.menu!.items.map(\.title)
        let widest = allTitles.map(width).max() ?? 0
        expect(pop.intrinsicContentSize.width == 2 * 12 + widest + 33, "...so the default face measures title + 2 x 12 + 33 (\(pop.intrinsicContentSize.width))")
        let tight = GlassPopUpButton(frame: .zero, pullsDown: false)
        tight.addItems(withTitles: ["25%", "50%", "100%", "200%", "Fit"])
        tight.selectItem(at: 2)
        tight.facePadding = 4
        tight.chevronColumn = 25
        let tightWidest = tight.menu!.items.map { width($0.title) }.max() ?? 0
        expect(tight.intrinsicContentSize.width == 2 * 4 + tightWidest + 25 && tight.intrinsicContentSize.height == 36, "A tight face measures title + 2 x 4 + 25 (\(tight.intrinsicContentSize))")
        expect(tight.intrinsicContentSize.width < pop.intrinsicContentSize.width, "...and is narrower than the roomy one")
        tight.frame = NSRect(origin: NSPoint(x: 10, y: 60), size: tight.intrinsicContentSize)
        rig.window.contentView?.addSubview(tight)
        for index in 0..<tight.numberOfItems {
            tight.selectItem(at: index)
            tight.layoutSubtreeIfNeeded()
            expect(tight.titleRect.width >= width(tight.faceTitle), "The 20 pt title \"\(tight.faceTitle)\" has room in a tight face: \(width(tight.faceTitle)) of \(tight.titleRect.width)")
        }
        expect(tight.fittingSize.width <= tight.frame.width + 0.01, "A tight face never needs more than its own width")
        expect(tight.titleRect.minX == 4 && tight.chevronRect.maxX == tight.bounds.width - 4 && tight.chevronRect.minX >= tight.titleRect.maxX - 0.01 && tight.bounds.contains(tight.chevronRect),
               "The tight chevron sits at the trailing end, after the title, inside the face (\(tight.titleRect), \(tight.chevronRect))")
        expect(!tight.subviews.isEmpty && tight.subviews.contains { $0.frame == tight.chevronRect && !$0.isHidden }, "The chevron view is where the metrics say, and visible")
        expect(tight.focusRingMaskBounds == tight.bounds.insetBy(dx: 1, dy: 1), "The focus ring still follows the whole face")
        guard let tightRep = tight.bitmapImageRepForCachingDisplay(in: tight.bounds) else { return expect(false, "The tight face renders") }
        tight.cacheDisplay(in: tight.bounds, to: tightRep)
        func tightInk(_ x0: Int, _ x1: Int) -> Int {
            var count = 0
            for y in 0..<tightRep.pixelsHigh { for x in max(0, x0)..<min(tightRep.pixelsWide, x1) where (tightRep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 1 } }
            return count
        }
        let scale = Double(tightRep.pixelsWide) / Double(tight.bounds.width)
        expect(tightInk(Int(4 * scale), Int((4 + width(tight.faceTitle)) * scale)) > 40, "The tight face draws its title")
        expect(tightInk(Int(Double(tight.chevronRect.minX + 4) * scale), Int(Double(tight.bounds.width) * scale)) > 20, "...and its chevron")
        // Changing the metrics re-measures.
        let tightBefore = tight.intrinsicContentSize.width
        tight.chevronColumn = 33
        expect(tight.intrinsicContentSize.width == tightBefore + 8, "Changing the chevron column re-measures the face")
        // The face's text metrics are what draw(_:) uses: normal titles fit at the default and tight metrics, a long one in a narrow frame does not.
        for face in [pop, tight] {
            face.frame = NSRect(origin: NSPoint(x: 10, y: 60), size: face.intrinsicContentSize)
            rig.window.contentView?.addSubview(face)
            for index in 0..<face.numberOfItems {
                face.selectItem(at: index)
                let metrics = face.faceTextMetrics
                expect(metrics.title == face.faceTitle && metrics.font == DesignTokens.Typography.font(.body) && metrics.font.pointSize == 20, "The metrics name the title and the 20 pt face")
                expect(metrics.needed.width == width(face.faceTitle) && metrics.needed.height >= 20 && metrics.available == face.titleRect, "...the real text size and the rectangle that is drawn into (\(metrics.needed) in \(metrics.available))")
                expect(face.faceTextFits, "\"\(face.faceTitle)\" fits its face at padding \(face.facePadding) / chevron column \(face.chevronColumn)")
            }
            face.removeFromSuperview()
        }
        let long = LongFacePopUp(frame: NSRect(x: 10, y: 60, width: 100, height: 36), pullsDown: false)
        long.addItem(withTitle: "Short")
        rig.window.contentView?.addSubview(long)
        let longMetrics = long.faceTextMetrics
        expect(!long.faceTextFits && longMetrics.needed.width > longMetrics.available.width, "A long title in a narrow frame reports that it does not fit (needs \(longMetrics.needed.width) of \(longMetrics.available.width))")
        long.frame.size.width = long.intrinsicContentSize.width
        expect(long.faceTextFits, "...and fits once the face has its own width")
        let squat = GlassPopUpButton(frame: NSRect(x: 10, y: 60, width: 200, height: 20), pullsDown: false)
        squat.addItem(withTitle: "Short")
        expect(!squat.faceTextFits && squat.faceTextMetrics.needed.height > squat.faceTextMetrics.available.height, "A face too short for a 20 pt line reports that it does not fit")
        long.removeFromSuperview()
        tight.removeFromSuperview()

        // The face: the selected title at 20 pt and a chevron, drawn without a bezel.
        pop.selectItem(at: 1)
        expect(pop.faceTitle == "50%" && pop.intrinsicContentSize.height == 36, "The face shows the selected title in a 36 pt control")
        let titleWidth = ceil(("Actual Size" as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.body)]).width)
        expect(pop.intrinsicContentSize.width >= titleWidth + 2 * 12 + 8 + GlassChoiceButton.glyphSide, "...wide enough for its longest title and the chevron (\(pop.intrinsicContentSize.width))")
        pop.frame = NSRect(x: 10, y: 10, width: 170, height: 36)
        pop.layoutSubtreeIfNeeded()
        guard let rep = pop.bitmapImageRepForCachingDisplay(in: pop.bounds) else { return expect(false, "The face renders") }
        pop.cacheDisplay(in: pop.bounds, to: rep)
        func ink(_ x0: Double, _ x1: Double) -> Int {
            var count = 0
            for y in 0..<rep.pixelsHigh { for x in Int(x0 * Double(rep.pixelsWide))..<Int(x1 * Double(rep.pixelsWide)) {
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 1 }
            } }
            return count
        }
        expect(ink(0.05, 0.45) > 40, "The title is drawn on the left of the face")
        expect(ink(0.85, 1.0) > 20, "The chevron is drawn on the right of the face")
    }



    // MARK: label sizing

    /// A row's label is sized by a real text field in the strong face: its text never truncates (the cell needs about 4 pt more than the
    /// string's own bounding box), a wrapped title gets the height of every line, and choosing a row never changes its width.
    private static func labelSizingTests() {
        let titles = ["Dock", "Browser", "Both", "Precise", "Loose", "Window title", "Resize", "Crop", "Limit", "B", "E", "St", "Do", "Preci", "Loo"]
        for layout in [GlassChoiceButton.Layout.segment, .row] {
            for title in titles {
                for shortcut in [nil, "⇧⌘K"] {
                    let button = makeButton(title, .option, indicator: GlassChoiceButton.Indicator.none, layout: layout)
                    button.shortcutText = shortcut
                    button.frame = NSRect(origin: .zero, size: button.intrinsicContentSize)
                    var widths: [CGFloat] = []
                    for chosen in [false, true] {
                        button.isChosen = chosen
                        widths.append(button.intrinsicContentSize.width)
                        button.frame = NSRect(origin: .zero, size: button.intrinsicContentSize)
                        button.layoutSubtreeIfNeeded()
                        let label = button.titleLabel
                        expect(label.fittingSize.width <= label.frame.width + 0.01,
                               "\"\(title)\" (\(layout), chosen \(chosen)) is not truncated: the label needs \(label.fittingSize.width) of \(label.frame.width)")
                        expect(label.fittingSize.height <= label.frame.height + 0.01, "\"\(title)\" is not clipped: needs \(label.fittingSize.height) of \(label.frame.height)")
                        expect(label.frame.width >= needed(title, .bodyStrong).width, "\"\(title)\" has room for the strong face even while unchosen")
                        if shortcut != nil {
                            expect(button.shortcutLabel.fittingSize.width <= button.shortcutLabel.frame.width + 0.01, "The shortcut next to \"\(title)\" is not truncated")
                            expect(button.shortcutLabel.frame.maxX <= button.bounds.width - 12 + 0.01 && button.shortcutLabel.frame.minX >= label.frame.maxX - 0.01,
                                   "...and sits inside the row, after the title")
                        }
                        expect(label.frame.minX >= 0 && label.frame.maxX <= button.bounds.width + 0.01, "\"\(title)\" stays inside its row")
                    }
                    expect(widths[0] == widths[1], "\"\(title)\" (\(layout)) has the same width chosen and unchosen (\(widths))")
                }
            }
        }

        // Wrapped: the snap toggle's long title at a wide wrap width (and a narrow one) gets every line it needs.
        let sentence = "Snap the pointer to the nearest edge of the canvas while drawing, and show a crosshair where the pointer snaps"
        for width in [349.0, 220.0, 140.0] {
            let button = makeButton(sentence, .toggle, indicator: .checkbox)
            button.wrapWidth = width
            let size = button.intrinsicContentSize
            button.frame = NSRect(origin: .zero, size: size)
            button.layoutSubtreeIfNeeded()
            let label = button.titleLabel
            label.preferredMaxLayoutWidth = label.frame.width
            let lines = Int(round(label.frame.height / 24))
            expect(lines >= 2 && label.fittingSize.height <= label.frame.height + 0.01, "A title wrapped at \(width) gets all its lines: \(lines) lines, needs \(label.fittingSize.height) of \(label.frame.height)")
            expect(size.height >= label.frame.height + 2 * DesignTokens.Space.s2 - 0.01 && size.height > 36, "...and the row grows to hold them (\(size.height))")
            expect(label.frame.minY >= 0 && label.frame.maxY <= button.bounds.height + 0.01, "...inside the row")
            expect(needed(sentence, .bodyStrong, wrap: width).height <= label.frame.height + 0.01, "...as an independent measure agrees")
            button.isChosen = true
            expect(button.intrinsicContentSize == size, "Choosing a wrapped row changes neither its width nor its height")
        }
        let twoLines = makeButton("A title that needs exactly two lines at this width, no more than that really", .command)
        twoLines.wrapWidth = 349
        twoLines.frame = NSRect(origin: .zero, size: twoLines.intrinsicContentSize)
        twoLines.layoutSubtreeIfNeeded()
        expect(twoLines.titleLabel.frame.height == 48 && twoLines.frame.height == 48 + 16, "Two lines are 48 pt of label in a 64 pt row (\(twoLines.titleLabel.frame.height), \(twoLines.frame.height))")

        // An inline group's segments fit their titles, in either state of the selection, and keep their widths when the choice moves.
        let window = NonorderingWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 300))
        let show = GlassChoiceGroup(titles: ["Dock", "Browser", "Both"], accessibilityLabel: "Show in", identifier: "showIn", accessibility: plain)
        let precision = GlassChoiceGroup(titles: ["Precise", "Normal", "Loose"], accessibilityLabel: "Precision", identifier: "precision", accessibility: plain)
        let radios = GlassChoiceGroup(titles: ["Only when needed", "Always"], layout: .row, axis: .vertical, indicator: .radio, accessibilityLabel: "Presence", identifier: "presence", accessibility: plain)
        for (index, group) in [show, precision, radios].enumerated() {
            group.setFrameOrigin(.zero)
            place(group, in: window)
            window.contentView?.subviews.last.map { $0.setFrameOrigin(NSPoint(x: 20, y: 20 + 80 * CGFloat(index))) }
            var before: [CGFloat] = []
            for selected in 0..<group.buttons.count {
                group.selectedIndex = selected
                group.layoutSubtreeIfNeeded()
                window.contentView?.layoutSubtreeIfNeeded()
                let widths = group.buttons.map { $0.frame.width }
                if selected == 0 { before = widths } else { expect(widths == before, "Moving the choice moves no segment (\(widths) vs \(before))") }
                for button in group.buttons {
                    expect(button.titleLabel.fittingSize.width <= button.titleLabel.frame.width + 0.01,
                           "\"\(button.title)\" fits its segment (choice \(selected)): needs \(button.titleLabel.fittingSize.width) of \(button.titleLabel.frame.width)")
                }
            }
        }

        // Section headers and the pop-up face measure the same way.
        let header = GlassChoiceLabel(title: "Destinations and sharing")
        header.frame = NSRect(origin: .zero, size: header.intrinsicContentSize)
        header.layoutSubtreeIfNeeded()
        expect(header.label.fittingSize.width <= header.label.frame.width + 0.01, "A section header is not truncated at its own width")
        expect(header.intrinsicContentSize.width >= needed("Destinations and sharing", .bodyStrong).width + 24, "...and its width counts the label's padding")
    }

    // MARK: the shared audits

    /// The same walkers the settings, history and resize suites run: type floor and accessibility, over every primitive on screen.
    private static func auditTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        let group = GlassChoiceGroup(titles: ["Resize", "Crop", "Limit"], accessibilityLabel: "Mode", identifier: "mode", accessibility: plain)
        let radios = GlassChoiceGroup(titles: ["Always", "Never"], layout: .row, axis: .vertical, indicator: .radio, accessibilityLabel: "Presence", identifier: "presence", accessibility: plain)
        let box = makeButton("Lock proportions", .toggle, indicator: .checkbox)
        let pop = GlassPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 36), pullsDown: false)
        pop.addItems(withTitles: ["25%", "50%"])
        pop.setAccessibilityLabel("Zoom")
        let panel = MenuChoicePanel(menu: standardMenu(fixture), identifier: "Audit", accessibilityLabel: "Audit choices")
        rig.attach(panel.host)
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        let views: [(String, NSView)] = [("group", group), ("vertical group", radios), ("toggle", box), ("pop-up", pop), ("panel", panel.host.window.contentView!)]
        for (name, view) in views {
            if name != "panel" {
                view.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
                rig.window.contentView?.addSubview(view)
                view.layoutSubtreeIfNeeded()
            }
            let type = ViewTreeAudit.audit(view, surface: name)
            expect(type.violations.isEmpty && type.smallest != nil, "The type-floor audit is clean for the \(name): \(type.description)")
            let access = AccessibilityAudit.audit(view, surface: name)
            expect(access.violations.isEmpty && access.controls > 0, "The accessibility audit is clean for the \(name): \(access.description)")
        }
        panel.host.close()

        // The walker judges an inline group itself: a group that lost its name is flagged, a named one is not, and the buttons inside are
        // still judged on their own.
        let nameless = GlassChoiceGroup(titles: ["Resize", "Crop"], accessibilityLabel: "", identifier: "nameless", accessibility: plain)
        let named = GlassChoiceGroup(titles: ["Resize", "Crop"], accessibilityLabel: "Size operation", identifier: "named", accessibility: plain)
        let namelessReport = AccessibilityAudit.audit(nameless, surface: "nameless group")
        expect(namelessReport.count(of: .missingLabel) == 1 && namelessReport.violations.first?.path.contains("GlassChoiceGroup") == true,
               "A GlassChoiceGroup with an empty accessibility label is flagged missingLabel: \(namelessReport.description)")
        let namedReport = AccessibilityAudit.audit(named, surface: "named group")
        expect(namedReport.violations.isEmpty && namedReport.controls == 3 && namedReport.labelled == 3, "A named group is clean and counts as a control with its two buttons (\(namedReport.controls) controls)")
        nameless.buttons[0].setAccessibilityLabel("")
        nameless.buttons[0].title = ""
        let both = AccessibilityAudit.audit(nameless, surface: "nameless group, unlabelled button")
        expect(both.count(of: .missingLabel) == 2, "...and a button inside it that lost its name is still flagged too (\(both.description))")
        // A choice panel's group role is judged as well: a labelled container passes, an unlabelled one fails.
        let rootPlate = GlassChrome.plate([makeButton("One", .command)], identifier: "container", accessibility: plain, axis: .vertical)
        let container = AuditContainer()
        container.addSubview(rootPlate)
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.group)
        container.setAccessibilityLabel("")
        expect(AccessibilityAudit.audit(container, surface: "unlabelled panel").count(of: .missingLabel) == 1, "An unlabelled group of choice buttons is flagged")
        container.setAccessibilityLabel("Choices")
        expect(AccessibilityAudit.audit(container, surface: "labelled panel").violations.isEmpty, "...and a labelled one is clean")
    }

    // MARK: display options

    private static func displayOptionTests() {
        let rig = Rig()
        let log = Log()
        let fixture = MenuFixture(log: log)
        let panel = MenuChoicePanel(menu: standardMenu(fixture), identifier: "Display", accessibilityLabel: "Display")
        rig.attach(panel.host)
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.host.plates.allSatisfy { $0.transparencyPlate == nil } && panel.rows.allSatisfy { !$0.accessibility.reduceMotion }, "Plain display options at first")

        // The system changing its display options reaches the plates and every row of a shown panel.
        DisplayOptions.override = DisplayOptions(reduceMotion: true, reduceTransparency: true, increaseContrast: true, differentiateWithoutColor: true)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(panel.host.accessibility == DisplayOptions.current.chrome, "The host follows DisplayOptions")
        expect(panel.host.plates.allSatisfy { $0.transparencyPlate != nil && $0.showsContrastBorder }, "Reduce Transparency and Increase Contrast reach every plate")
        expect(panel.rows.allSatisfy { $0.accessibility.reduceMotion && $0.accessibility.differentiateWithoutColor && $0.plate.lastAnimationDuration == 0 }, "Reduce Motion and Differentiate Without Color reach every row: no animation")
        let beta = panel.rows.first { $0.title == "Beta" }!
        expect(beta.isChosen && beta.showsIndicator, "...so the chosen row shows its non-colour capsule")
        expect(labels(in: panel.host.window.contentView!).allSatisfy { ($0.font?.pointSize ?? 0) >= 18 }, "Text stays at the floor under every option")

        // A reopen builds with the options now in force.
        panel.host.close()
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        expect(panel.rows.allSatisfy { $0.accessibility.reduceMotion } && panel.host.plates.allSatisfy { $0.transparencyPlate != nil }, "A reopened panel is built with the current options")
        panel.host.close()
        DisplayOptions.override = .none
    }
}
#endif
