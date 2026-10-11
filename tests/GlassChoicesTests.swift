// The shared glass choice primitives (GlassChoices.swift) as behaviour: the pure placement function, the choice button's kind / state /
// accessibility semantics, the inline exclusive group, the panel host (one container, dismissal, focus restoration, only one shown) and the
// NSMenu adapter (groups, validation, close-before-perform, popup selection, submenus, keyboard). Every window is a never-ordered
// window and the host's presenter seam replaces ordering, so nothing reaches the desktop and no input is sent.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D GLASS_CHOICES_TESTS \
//   Sources/DesignTokens.swift Sources/DisplayOptions.swift Sources/DisplayOptions+ChromeAccessibility.swift Sources/OriginalActionButton.swift \
//   Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift Sources/FontAwesomeFree.swift Sources/SVGPath.swift Sources/AppToolTip.swift \
//   Sources/StateStyles.swift Sources/GlassChrome.swift Sources/GlassChoices.swift tests/ContrastProbe.swift tests/GlassChoicesTests.swift \
//   -o build/glass-choices-tests
#if GLASS_CHOICES_TESTS
import AppKit

// MARK: - Fixtures

/// Any attempt to order a window front or to attach a child window fails: the presenter seam must replace it.
@MainActor
private final class NonorderingWindow: NSWindow {
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

private func key(_ code: UInt16, chars: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
}

/// Records the key-downs that reach it: what the pop-up did not take.
@MainActor
private final class KeyProbeView: NSView {
    var keys: [UInt16] = []
    override var acceptsFirstResponder: Bool { false }
    override func keyDown(with event: NSEvent) { keys.append(event.keyCode) }
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

        placementTests()
        shortcutTests()
        surfaceAxisTests()
        buttonSemanticsTests()
        buttonAppearanceTests()
        buttonLayoutTests()
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
        displayOptionTests()
        popUpButtonTests()
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
        expect(abs((button.plate.style.fill?.usingColorSpace(.sRGB)?.alphaComponent ?? 0) - 0.20) < 0.005, "...at the 0.20 accent fill")
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

    private static func buttonLayoutTests() {
        let plainButton = makeButton("Sample", .command)
        let intrinsic = plainButton.intrinsicContentSize
        let textWidth = ceil(("Sample" as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.bodyStrong)]).width)
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
        let shortcutWidth = ceil(("⇧⌘K" as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.body)]).width)
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
        expect(height > 36 && wrapped.intrinsicContentSize.width <= 140 + 24, "A wrapping title grows the row above 36 pt within its width (\(wrapped.intrinsicContentSize))")
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

        // A flipped anchor view reads the edge in its own coordinates: .minY is its top, so the panel opens above it.
        let flipped = FlippedAnchor(frame: NSRect(x: 300, y: 300, width: 80, height: 36))
        rig.window.contentView?.addSubview(flipped)
        host.show(relativeTo: flipped.bounds, of: flipped, preferredEdge: .minY, makeKey: true)
        let flippedFrame = rig.window.convertToScreen(flipped.convert(flipped.bounds, to: nil))
        expect(host.placement?.edge == .maxY && abs(panel.frame.minY - (flippedFrame.maxY + 6)) < 0.5, "In a flipped view .minY is the top edge, so the panel sits above (\(panel.frame) vs \(flippedFrame))")
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

        // keyboard: true focuses the chosen row.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        expect(panel.focusedRow?.title == "Beta" && panel.host.window.firstResponder === panel.focusedRow, "A keyboard open focuses the chosen row")
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
        expect(panel.focusedRow?.title == "Beta", "The first arrow key focuses the chosen row")
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: false)
        press(Keys.up)
        expect(panel.focusedRow?.title == "Beta", "...for Up as well")
        // With no chosen row it is the first enabled one.
        menu.items[1].state = .off
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        expect(panel.focusedRow?.title == "Alpha", "With nothing chosen a keyboard open focuses the first enabled row")
        menu.items[1].state = .on
        // Unhandled keys fall through to the window.
        expect(!panel.handleKey(key(0, chars: "a")), "Keys the panel does not use are not consumed")
        panel.host.close()

        // Hover fills come from the button itself and never move the keyboard focus.
        panel.present(relativeTo: rig.anchor, preferredEdge: .minY, keyboard: true)
        let alpha = panel.rows.first { $0.title == "Alpha" }!
        alpha.setHovered(true)
        expect(alpha.plate.style.fill != nil && panel.focusedRow?.title == "Beta", "Hovering a row fills it without moving the keyboard focus")
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
