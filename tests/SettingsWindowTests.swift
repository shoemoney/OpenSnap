// The Settings window, built standalone with in-memory stand-ins for everything the app owns. No window is ordered onto the
// desktop, no hotkey is registered with the system, no defaults domain is opened, no network, Keychain or real store is read.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D SETTINGS_WINDOW_TESTS \
//   Sources/SettingsWindow.swift Sources/GeneralPreferencesState.swift Sources/GlobalHotkeys.swift Sources/AppToolTip.swift \
//   Sources/DesignTokens.swift Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift Sources/FontAwesomeFree.swift \
//   Sources/SVGPath.swift Sources/StrokeFitting.swift Sources/DisplayOptions.swift Sources/OriginalCaptureFlash.swift \
//   Sources/Publishing.swift Sources/PublishingS3.swift Sources/PublishingDestinations.swift Sources/PublishingDestinationsView.swift \
//   tests/TestDefaults.swift tests/ViewTreeAudit.swift tests/SettingsWindowTests.swift -o build/settings-window-tests
#if SETTINGS_WINDOW_TESTS
import AppKit

@MainActor
private final class FakeHotkeyBackend: GlobalHotkeyBackend {
    var bindings: [UInt32: GlobalHotkeyBinding] = [:]
    var registeredIDs: Set<UInt32> { Set(bindings.keys) }
    func installHandler(onEvent: @escaping @MainActor @Sendable (UInt32) -> Void) throws {}
    func systemReservedBindings() throws -> Set<GlobalHotkeyBinding> { [] }
    func register(_ binding: GlobalHotkeyBinding, id: UInt32) throws { bindings[id] = binding }
    func unregister(id: UInt32) throws { bindings.removeValue(forKey: id) }
    func shutdown() throws { bindings = [:] }
}

@main
@MainActor
private enum SettingsWindowTests {
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fputs("FAIL SettingsWindowTests: \(message)\n", stderr); exit(1) }
        checks += 1
    }

    /// 1280 x 800 with a 24 pt menu bar and a 70 pt Dock: what a window may use.
    private static let fakeVisible = NSRect(x: 0, y: 70, width: 1280, height: 706)

    private final class Box<T> { var value: T; init(_ value: T) { self.value = value } }

    private static func makeController(state: GeneralPreferencesState = initialState, destinations: PublishingDestinationList = PublishingDestinationList(),
                                       name: String = "OpenSnap.SettingsTests." + UUID().uuidString,
                                       manage: @escaping (NSWindow) -> Void = { _ in }) -> (SettingsWindowController, TestDefaults, GlobalHotkeyManager, FakeHotkeyBackend, Box<GeneralPreferencesState>, Box<[GeneralPreferencesState]>) {
        let defaults = TestDefaults(name: name)
        let backend = FakeHotkeyBackend()
        let manager = GlobalHotkeyManager(defaults: defaults, backend: backend)
        let current = Box(state), delivered = Box<[GeneralPreferencesState]>([])
        let controller = SettingsWindowController(state: { current.value }, hotkeys: manager, defaults: defaults,
                                                  destinations: { destinations }, manageDestinations: manage)
        controller.visibleFrame = { fakeVisible }
        controller.onChange = { delivered.value.append($0); current.value = $0 }
        return (controller, defaults, manager, backend, current, delivered)
    }

    private static let initialState = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2, includeApp: true, statusMenu: 0)

    private static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private static func texts(in view: NSView) -> [String] {
        descendants(view).flatMap { view -> [String] in
            var result: [String] = []
            if let field = view as? NSTextField { result.append(field.stringValue) }
            if let button = view as? NSButton { result.append(button.title) }
            if let popup = view as? NSPopUpButton { result += popup.itemTitles }
            if let segmented = view as? NSSegmentedControl { result += (0..<segmented.segmentCount).compactMap { segmented.label(forSegment: $0) } }
            if let tip = view.toolTip { result.append(tip) }
            if let tip = AppToolTip.text(for: view) { result.append(tip) }
            return result
        }
    }
    private static func spin(_ seconds: Double, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while !done() && Date() < end { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    }
    private static func keyEvent(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }
    private static func frame(of view: NSView, in root: NSView) -> NSRect { view.convert(view.bounds, to: root) }
    /// Where the control's visible edge is: the alignment rect, which is what a grid column aligns.
    private static func alignment(of view: NSView, in root: NSView) -> NSRect {
        view.convert(view.alignmentRect(forFrame: view.bounds), to: root)
    }
    private static func button(_ id: String, in root: NSView) -> NSButton {
        let matches = descendants(root).compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue == id }
        expect(matches.count == 1, "exactly one control identified \(id), found \(matches.count)")
        return matches[0]
    }
    private static func hotkeySettings(_ defaults: UserDefaults) -> GlobalHotkeySettings { (try? GlobalHotkeyStore(defaults: defaults).load()) ?? .defaults }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        structure()
        tabStrip()
        tabStripContrast()
        closing()
        fit()
        alignmentAndTypography()
        preferenceControls()
        flash()
        shortcuts()
        shortcutSheet()
        upload()
        uploadWithPublishing()
        words()
        viewTreeAudit()
        print("SettingsWindowTests: \(checks) checks passed (standalone controller; no window ordered onto the desktop)")
    }

    // MARK: Structure

    private static func structure() {
        let (controller, _, _, _, _, _) = makeController()
        let window = controller.window
        expect(window.toolbar == nil && controller.strip.superview === controller.content && window.contentView === controller.content,
               "the tabs are an app-owned strip at the top of the window's content, not a toolbar")
        expect(controller.tabItems.map(\.label) == ["General", "Drawing", "Capture", "Upload"], "four tabs in order: \(controller.tabItems.map(\.label))")
        expect(controller.tabItems.map(\.icon) == [.gear, .paintbrush, .crosshairs, .upload], "General is the gear; the others keep their icons")
        expect(controller.strip.buttons.allSatisfy { $0.image != nil && $0.image!.size.width > 0 }, "every tab has an icon")
        for index in controller.tabItems.indices {
            controller.select(index)
            expect(window.title == controller.tabItems[index].label, "the window title follows the tab: '\(window.title)' on \(controller.tabItems[index].label)")
        }
        controller.select(0)
        expect(!window.styleMask.contains(.resizable), "width is fixed; height follows the tab")
        expect(SettingsWindowController.autosaveName == "OpenSnap.Settings" && window.frameAutosaveName.isEmpty,
               "the frame name is supplied by the app; a test passes none and nothing is saved")
        let buttons = controller.tabItems.flatMap { descendants($0.viewController.view) }.compactMap { $0 as? NSButton }
        expect(!buttons.contains { $0.title == "Done" || $0.keyEquivalent == "\r" }, "no Done button, and no default button to take Return")
        let all = controller.tabItems.flatMap { texts(in: $0.viewController.view) }
        for word in ["Appearance", "Sounds", "Play sounds", "Relaunch", "Modern", "Classic"] {
            expect(!all.contains { $0.localizedCaseInsensitiveContains(word) }, "no row or control mentions \(word)")
        }
        expect(controller.window.delegate === controller, "the controller is the window's delegate")
    }

    // MARK: The tab strip

    private static func accent(_ view: NSView) -> NSColor {
        var resolved = NSColor.clear
        view.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = DesignTokens.Palette.accent.usingColorSpace(.deviceRGB) ?? .clear }
        return resolved
    }
    private static func rgb(_ cg: CGColor?, in view: NSView) -> [CGFloat] {
        var out: [CGFloat] = []
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            if let cg, let color = NSColor(cgColor: cg)?.usingColorSpace(.deviceRGB) { out = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent] }
        }
        return out
    }
    private static func resolved(_ color: NSColor, in view: NSView) -> [CGFloat] {
        var out: [CGFloat] = []
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            if let c = color.usingColorSpace(.deviceRGB) { out = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent] }
        }
        return out
    }

    /// Audit fix 2: the strip's tabs read on its plate in light, dark and both Increase Contrast arms; the selected tab is held on its own fill too.
    private static func tabStripContrast() {
        typealias Palette = DesignTokens.Palette
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 2))
        let strip = controller.strip
        controller.select(1)
        strip.frame = NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsTabStrip.height)
        strip.layoutSubtreeIfNeeded()
        for (name, appearance) in ContrastProbe.appearances {
            let reading = ContrastProbe.measure(strip, appearance: appearance, plateAt: NSPoint(x: 3, y: strip.bounds.midY),
                                                textFrames: strip.buttons.map { strip.convert($0.bounds, from: $0) })
            expect(reading.plateOpaque, "the strip draws an opaque plate (\(name))")
            for (button, ratio) in zip(strip.buttons, reading.textRatios) { expect(ratio >= 4.5, "\(button.title) reads at 4.5:1 on the strip (\(name): \(ratio))") }
            appearance.performAsCurrentDrawingAppearance {
                let window = Palette.resolve(Palette.Surface.window, for: appearance)
                let selected = Palette.blend(Palette.State.selectedFill, alpha: 1, over: window)
                let backdrop = NSColor(srgbRed: selected.red, green: selected.green, blue: selected.blue, alpha: 1)
                let ratio = Palette.contrastRatio(Palette.resolve(Palette.Text.primary, for: appearance), Palette.rgb(backdrop).rgb)
                expect(ratio >= 4.5, "the selected tab's title reads on its own fill (\(name): \(ratio))")
            }
        }
    }

    private static func tabStrip() {
        typealias Palette = DesignTokens.Palette
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 2))
        let window = controller.window, strip = controller.strip
        window.contentView?.layoutSubtreeIfNeeded()

        // Size: every label is 20 pt body in a real button, so the type walker judges it.
        expect(strip.buttons.map(\.title) == ["General", "Drawing", "Capture", "Upload"], "the strip has the four tab buttons: \(strip.buttons.map(\.title))")
        for button in strip.buttons {
            expect(button.font == DesignTokens.Typography.font(.body) && button.font?.pointSize == 20, "\(button.title): the tab label is 20 pt body (\(button.font?.pointSize ?? 0))")
            let runs = button.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            expect(runs?.pointSize == 20, "\(button.title): the drawn title run is 20 pt (\(runs?.pointSize ?? 0))")
            expect(button.imagePosition == .imageLeading && button.image != nil, "\(button.title): an icon beside the label")
            expect(button.frame.height >= DesignTokens.Size.hitMin, "\(button.title): the tab is at least \(DesignTokens.Size.hitMin) pt tall (\(button.frame.height))")
        }
        expect(strip.contentWidth + 2 * DesignTokens.Space.s3 <= SettingsLayout.contentWidth, "the four tabs fit the 640 pt window: \(strip.contentWidth)")
        let stripBox = strip.convert(strip.bounds, to: window.contentView), rowBox = strip.buttons.map { $0.convert($0.bounds, to: window.contentView) }.reduce(NSRect.null) { $0.union($1) }
        expect(abs((rowBox.midX) - stripBox.midX) < 1, "the tabs are centred across the window")
        expect(abs(window.contentLayoutRect.maxY - strip.convert(strip.bounds, to: nil).maxY) < 1.5 || strip.frame.maxY >= (window.contentView?.bounds.maxY ?? 0) - 0.5,
               "the strip is at the top of the content")

        // A solid surface with a separator below, and no glass anywhere in it.
        let kinds = descendants(strip).map { String(describing: type(of: $0)) }
        expect(!kinds.contains { $0.contains("Glass") || $0.contains("VisualEffect") } && !(strip is NSVisualEffectView), "the strip is solid, not glass: \(Set(kinds))")
        var surface: [CGFloat] = []
        strip.effectiveAppearance.performAsCurrentDrawingAppearance { strip.updateLayer(); surface = rgb(strip.layer?.backgroundColor, in: strip) }
        expect(surface == resolved(Palette.Surface.window, in: strip) && surface.last == 1, "the strip fills with the opaque window surface: \(surface)")
        let separator = window.contentView!.subviews.compactMap { $0 as? NSBox }.first { $0.boxType == .separator }
        expect(separator != nil, "a separator under the strip")
        if let separator {
            let line = separator.alignmentRect(forFrame: separator.frame)
            expect(abs(line.height - SettingsContentView.separatorHeight) < 0.5, "the separator is 1 pt (\(line.height))")
            expect(abs(line.maxY - strip.frame.minY) < 0.5, "the separator sits directly under the strip (\(line) vs \(strip.frame))")
        }

        // States: rest, hover, pressed and selected are fills; selected adds a border and an accent icon (not colour alone).
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            controller.select(1)
            for (index, button) in strip.buttons.enumerated() {
                let layer = button.layer!
                let fill = rgb(layer.backgroundColor, in: button)
                if index == 1 {
                    expect(layer.borderWidth == 1 && rgb(layer.borderColor, in: button) == resolved(Palette.accent, in: button), "\(appearance.rawValue): the selected tab has a 1 pt accent border")
                    expect(fill == resolved(Palette.State.selectedFill, in: button), "\(appearance.rawValue): the selected tab has the selected fill: \(fill)")
                    expect(button.contentTintColor.map { resolved($0, in: button) } == resolved(Palette.accent, in: button), "\(appearance.rawValue): the selected icon is accent")
                    expect(button.accessibilityValue() as? Int == 1, "the selected tab reports value 1")
                } else {
                    expect(layer.borderWidth == 0 && fill.last == 0, "\(appearance.rawValue): \(button.title) rests with no fill and no border (\(fill))")
                    expect(button.contentTintColor.map { resolved($0, in: button) } == resolved(Palette.Text.secondary, in: button), "\(appearance.rawValue): a resting icon is secondary")
                    expect(button.accessibilityValue() as? Int == 0, "an unselected tab reports value 0")
                }
            }
            let rest = strip.buttons[2]
            rest.setHovered(true)
            expect(rgb(rest.layer?.backgroundColor, in: rest) == resolved(Palette.State.hover, in: rest), "\(appearance.rawValue): hover fills with the hover colour")
            rest.setPressed(true)
            expect(rgb(rest.layer?.backgroundColor, in: rest) == resolved(Palette.State.pressed, in: rest), "\(appearance.rawValue): pressed fills with the pressed colour")
            rest.setPressed(false); rest.setHovered(false)
            expect(rgb(rest.layer?.backgroundColor, in: rest).last == 0, "\(appearance.rawValue): the fill clears when the pointer leaves")
            let current = strip.buttons[1]
            current.setHovered(true)
            expect(rgb(current.layer?.backgroundColor, in: current) == resolved(Palette.State.selectedFill, in: current), "\(appearance.rawValue): hover never washes out the selected tab")
            current.setPressed(true)
            expect((rgb(current.layer?.backgroundColor, in: current).last ?? 0) >= 0.32 - 0.001, "\(appearance.rawValue): pressing the selected tab deepens its fill")
            current.setPressed(false); current.setHovered(false)
        }
        window.appearance = nil
        controller.select(0)

        // Clicking a tab selects it and the title follows.
        strip.buttons[2].performClick(nil)
        expect(controller.selectedIndex == 2 && window.title == "Capture" && strip.selectedIndex == 2, "clicking Capture selects it and the title follows: \(window.title)")
        controller.select(0)

        // Keyboard: Command-1 to Command-4.
        for (offset, code) in [UInt16(18), 19, 20, 21].enumerated() {
            let event = keyEvent(String(offset + 1), code: code, flags: .command, window: window)
            expect(window.performKeyEquivalent(with: event), "Command-\(offset + 1) is handled")
            expect(controller.selectedIndex == offset && window.title == SettingsLayout.tabTitles[offset], "Command-\(offset + 1) selects \(SettingsLayout.tabTitles[offset])")
        }
        controller.select(0)
        for (characters, code, flags) in [("1", UInt16(18), NSEvent.ModifierFlags([])), ("2", 19, [.command, .shift]), ("3", 20, [.command, .option]), ("5", 23, .command), ("0", 29, .command)] {
            _ = window.performKeyEquivalent(with: keyEvent(characters, code: code, flags: flags, window: window))
            expect(controller.selectedIndex == 0, "\(flags.rawValue) \(characters) does not switch tabs")
        }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
        _ = window.performKeyEquivalent(with: keyEvent("3", code: 20, flags: .command, window: window))
        expect(controller.selectedIndex == 0, "Command-3 does nothing under the window's own sheet")
        window.endSheet(sheet); sheet.orderOut(nil)

        // Keyboard: the strip is one key-view stop and the arrows move between tabs.
        expect(strip.acceptsFirstResponder && strip.canBecomeKeyView && strip.buttons.allSatisfy(\.refusesFirstResponder), "the strip is the one key-view stop; its buttons do not take focus")
        expect(window.makeFirstResponder(strip) && window.firstResponder === strip, "the strip can hold focus")
        expect(!strip.showsKeyboardFocus && strip.focusRingType == .none, "focus that arrives without a key press (the window opening) draws no ring")
        func arrow(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
            strip.keyDown(with: keyEvent(code == 123 ? "\u{F702}" : "\u{F703}", code: code, flags: flags, window: window))
        }
        arrow(124); expect(controller.selectedIndex == 1, "Right moves to Drawing")
        expect(strip.showsKeyboardFocus && strip.focusRingType == .exterior && strip.focusRingMaskBounds == strip.convert(strip.buttons[1].bounds, from: strip.buttons[1]),
               "an arrow key shows the focus ring, around the selected tab")
        arrow(124); arrow(124); expect(controller.selectedIndex == 3, "Right walks on to Upload")
        arrow(124); expect(controller.selectedIndex == 3, "Right stops at the last tab")
        arrow(123); expect(controller.selectedIndex == 2 && window.title == "Capture", "Left moves back to Capture")
        arrow(123); arrow(123); arrow(123); expect(controller.selectedIndex == 0, "Left stops at the first tab")
        arrow(124, .option); arrow(124, .shift)
        expect(controller.selectedIndex == 0, "a modified arrow is not a tab move")
        var closes = 0
        controller.onClose = { closes += 1 }
        window.keyDown(with: keyEvent("\u{1b}", code: 53, flags: [], window: window))
        expect(closes == 1 && controller.selectedIndex == 0, "Escape still closes with the strip focused")
        controller.onClose = nil
        _ = window.makeFirstResponder(nil)
        expect(!strip.showsKeyboardFocus, "the ring goes when focus leaves the strip")

        // Accessibility: a tab group of tabs, each with its label, the selection exposed as the group's value.
        expect(strip.accessibilityRole() == .tabGroup && strip.isAccessibilityElement(), "the strip is a tab group")
        expect((strip.accessibilityTabs() ?? []).count == 4, "the group exposes four tabs")
        for (index, button) in strip.buttons.enumerated() {
            expect(button.accessibilityRole() == .radioButton && button.accessibilityLabel() == SettingsLayout.tabTitles[index], "\(button.title): a radio-button tab with its label")
        }
        for index in 0..<4 {
            controller.select(index)
            expect(strip.accessibilityValue() as AnyObject === strip.buttons[index], "the group's value is the selected tab (\(SettingsLayout.tabTitles[index]))")
            expect(strip.buttons.enumerated().allSatisfy { ($0.element.accessibilityValue() as? Int) == ($0.offset == index ? 1 : 0) }, "only the selected tab reports 1")
        }
        controller.select(0)

        // G4: the walker sees four 20 pt tab labels on the real window, and fails when one is made small.
        let report = ViewTreeAudit.audit(window, surface: "Settings tab strip")
        let labels = report.findings.filter { SettingsLayout.tabTitles.contains($0.text) && $0.role == .control }
        expect(Set(labels.map(\.text)) == Set(SettingsLayout.tabTitles) && labels.allSatisfy { $0.pointSize == 20 }, "the walker found the four tab labels at 20 pt: \(labels.map { "\($0.text) \($0.pointSize)" })")
        expect(report.violations.isEmpty, "no violation on the real window:\n\(report.description)")
        let victim = strip.buttons[2]
        let original = victim.attributedTitle
        victim.attributedTitle = NSAttributedString(string: victim.title, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let caught = ViewTreeAudit.audit(window, surface: "Settings tab strip (seeded)").violations
        expect(caught.count == 1 && caught[0].pointSize == 13 && caught[0].text == "Capture", "a 13 pt tab label fails the walker: \(caught)")
        victim.attributedTitle = NSAttributedString(string: victim.title, attributes: [.font: NSFont.systemFont(ofSize: 17)])
        expect(ViewTreeAudit.audit(window, surface: "Settings tab strip (17 pt)").violations.count == 1, "17 pt is under the 18 pt floor and fails")
        victim.attributedTitle = original
        expect(ViewTreeAudit.audit(window, surface: "Settings tab strip (restored)").violations.isEmpty, "restoring the label clears the violation")
    }

    // MARK: Escape, Command-W, the close button

    private static func closing() {
        let (controller, _, _, _, _, _) = makeController()
        let window = controller.window
        var closes = 0
        controller.onClose = { closes += 1 }
        window.cancelOperation(nil)
        expect(closes == 1, "Escape (cancelOperation) calls the close callback once")
        let escape = keyEvent("\u{1b}", code: 53, flags: [], window: window)
        window.makeFirstResponder(controller.general.view)
        window.keyDown(with: escape)
        expect(closes == 2, "an Escape key event reaches cancelOperation through the responder chain (\(closes))")
        let commandW = keyEvent("w", code: 13, flags: .command, window: window)
        expect(window.performKeyEquivalent(with: commandW), "Command-W is handled by the window")
        expect(closes == 3, "Command-W calls the close callback")
        let plainW = keyEvent("w", code: 13, flags: [], window: window)
        let shiftCommandW = keyEvent("w", code: 13, flags: [.command, .shift], window: window)
        _ = window.performKeyEquivalent(with: plainW); _ = window.performKeyEquivalent(with: shiftCommandW)
        expect(closes == 3, "W alone and Shift-Command-W do not close the Settings window")
        expect(!controller.windowShouldClose(window) && closes == 4, "the close button asks the owner and keeps the window")

        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
        window.cancelOperation(nil)
        expect(closes == 4, "Escape never closes the window under its own sheet")
        window.endSheet(sheet); sheet.orderOut(nil)
        controller.onClose = nil
        expect(controller.windowShouldClose(window), "without an owner the close button just closes")
    }

    // MARK: Fit

    private static func fit() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 3))
        let window = controller.window
        window.setFrameTopLeftPoint(NSPoint(x: 100, y: fakeVisible.maxY - 20))
        var heights: [CGFloat] = []
        for index in controller.tabItems.indices {
            let top = window.frame.maxY
            controller.select(index)
            window.contentView?.layoutSubtreeIfNeeded()
            let name = controller.tabItems[index].label, tab = controller.selectedTab
            let wanted = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsContentView.chromeHeight + tab.fittingHeight)).height
            heights.append(wanted)
            expect(wanted <= fakeVisible.height, "\(name) needs \(wanted) pt; the fake 1280 x 800 screen shows \(fakeVisible.height)")
            // F-J2-012: each tab is as tall as its own form and the standard margins, no more.
            expect(abs(window.frame.height - wanted) < 0.5 && abs(controller.windowHeight(forTabAt: index) - wanted) < 0.5, "\(name): the window is the height its own tab asks for (\(window.frame.height) vs \(wanted))")
            expect(abs(window.contentLayoutRect.width - SettingsLayout.contentWidth) < 0.5, "the content is 640 wide on every tab")
            expect(abs(window.contentLayoutRect.height - (SettingsContentView.chromeHeight + tab.fittingHeight)) < 0.5, "\(name): the content is the strip, a separator and the tab's own height: \(window.contentLayoutRect.height)")
            expect(controller.content.scrollableExtent < 0.5, "\(name) fits the fake screen, so it does not scroll")
            expect(abs(window.frame.maxY - top) < 0.5, "\(name): switching tabs keeps the top edge where it was")
            let tabView = tab.view
            expect(abs(tabView.frame.height - tab.fittingHeight) < 0.5, "\(name): the tab fills its window with nothing left over (\(tabView.frame.height) vs \(tab.fittingHeight))")
            let controls = descendants(tabView).compactMap { $0 as? NSControl }.filter { !$0.isHidden && $0.bounds.width > 0 }
            let lowest = controls.map { frame(of: $0, in: tabView).minY }.min() ?? 0
            expect(lowest >= SettingsLayout.verticalMargin - 0.5 && lowest <= SettingsLayout.verticalMargin + 12, "\(name): no blank band under the last control (it ends \(lowest) pt from the bottom; the margin is \(SettingsLayout.verticalMargin))")
            for control in controls {
                let box = frame(of: control, in: tabView)
                expect(tabView.bounds.insetBy(dx: -0.5, dy: -0.5).contains(box), "\(name): \(control.className) at \(box) is outside the \(tabView.bounds) tab")
            }
        }
        expect(heights[0] < heights[3] && heights[1] < heights[2] && heights[0] < heights[2] && Set(heights.map { $0.rounded() }).count >= 3,
               "the tabs are different heights, each its own: \(heights)")
        // The window follows the tab with an animation, its top edge fixed the whole way.
        controller.reduceMotion = { false }; controller.animatesWhenHidden = true
        controller.select(0); spin(0.4)
        let top = window.frame.maxY, startHeight = window.frame.height
        let targetHeight = controller.windowHeight(forTabAt: 3)
        controller.select(3)
        var sawBetween = false
        for _ in 0..<8 {
            spin(0.02)
            expect(abs(window.frame.maxY - top) < 0.5, "the title bar stays put while the window resizes (top \(window.frame.maxY) vs \(top))")
            if window.frame.height > startHeight + 1 && window.frame.height < targetHeight - 1 { sawBetween = true }
        }
        spin(0.5)
        expect(sawBetween, "the resize is animated, not a jump")
        expect(abs(window.frame.height - targetHeight) < 0.5 && abs(window.frame.maxY - top) < 0.5, "the animation lands on the tab's height with the top where it was")
        // A tab picked mid-animation replaces the one before it and the last choice wins.
        controller.select(2); spin(0.03); controller.select(1); spin(0.5)
        expect(abs(window.frame.height - controller.windowHeight(forTabAt: 1)) < 0.5 && abs(window.frame.maxY - top) < 0.5, "the last tab chosen mid-animation sets the final size")
        controller.select(0); spin(0.5)
        // Reduce Motion: the size changes at once.
        controller.reduceMotion = { true }
        controller.select(2)
        expect(abs(window.frame.height - controller.windowHeight(forTabAt: 2)) < 0.5, "under Reduce Motion the window changes size at once")
        controller.reduceMotion = { false }; controller.animatesWhenHidden = false
        // A screen too short for a tab limits the window instead of letting it run off the bottom.
        controller.visibleFrame = { NSRect(x: 0, y: 0, width: 1280, height: 400) }
        controller.fit(animated: false)
        expect(window.frame.height <= 400, "a 400 pt screen caps the window at \(window.frame.height)")
        controller.visibleFrame = { fakeVisible }
        controller.fit(animated: false)
        captureShortcutError()
        shortScreen()
    }

    // MARK: A wrapped shortcut message

    private static func captureShortcutError() {
        let (controller, _, manager, _, _, _) = makeController()
        controller.select(2)
        let form = controller.capture.hotkeyForm!
        try? manager.install(globalScreen: {}, globalWindow: {}, globalFullscreen: {}, globalFrame: {}, globalUpload: {}, globalShow: {})
        let window = controller.window
        window.setFrameTopLeftPoint(NSPoint(x: 100, y: fakeVisible.maxY - 20)); controller.fit(animated: false)
        let idle = window.frame.height
        expect(abs(idle - controller.windowHeight(forTabAt: 2)) < 0.5, "Capture at idle is its own fitted height")
        let top = window.frame.maxY
        let k = GlobalHotkeyKeys.choices.firstIndex { $0.name == "K" }! + 1
        let popup = form.keyPopup(for: .screen)
        popup.selectItem(at: k); _ = popup.target?.perform(popup.action, with: popup)
        spin(0.3) { abs(window.frame.height - idle) > 0.5 }
        window.contentView?.layoutSubtreeIfNeeded()
        let withError = form.statusField.stringValue
        expect(withError.hasPrefix("Error: "), "the refused key shows an error: '\(withError)'")
        let wanted = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsContentView.chromeHeight + controller.capture.fittingHeight)).height
        expect(abs(window.frame.height - wanted) < 0.5 && abs(window.frame.maxY - top) < 0.5, "the Capture tab refits when the error appears (\(window.frame.height) vs \(wanted)), top fixed")
        expect(controller.content.scrollableExtent < 0.5, "the error is not clipped: nothing scrolls")
        let field = form.statusField
        let box = field.convert(field.bounds, to: controller.capture.view)
        expect(controller.capture.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(box) && box.height >= field.intrinsicContentSize.height - 0.5,
               "the whole wrapped message sits inside the tab: \(box) in \(controller.capture.view.bounds)")
        // Choosing None again clears the error and the window gives the room back.
        popup.selectItem(at: 0); _ = popup.target?.perform(popup.action, with: popup)
        spin(0.3) { abs(window.frame.height - wanted) > 0.5 || field.stringValue == GlobalHotkeyForm.idleLiveStatus }
        spin(0.1)
        expect(abs(window.frame.height - controller.windowHeight(forTabAt: 2)) < 0.5, "the Capture tab refits when the error goes: \(window.frame.height)")
    }

    // MARK: A screen shorter than the tab

    private static func shortScreen() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 3))
        let window = controller.window
        let short = NSRect(x: 0, y: 40, width: 1280, height: 500)
        controller.visibleFrame = { short }
        controller.fit(animated: false)
        for index in controller.tabItems.indices {
            controller.select(index)
            window.contentView?.layoutSubtreeIfNeeded()
            let name = controller.tabItems[index].label
            let tab = controller.selectedTab
            // What this tab needs on its own, with the window's title bar and strip: the window itself is the same height for every tab.
            let wanted = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsContentView.chromeHeight + tab.fittingHeight)).height
            expect(window.frame.height <= short.height + 0.5 && window.frame.minY >= short.minY - 0.5 && window.frame.maxY <= short.maxY + 0.5,
                   "\(name): the window stays on a 500 pt screen (\(window.frame) in \(short))")
            let document = tab.view, clip = controller.content.scroll.contentView
            expect(controller.content.scroll.documentView === document, "\(name): the tab sits in the scroll view")
            let controls = descendants(document).filter { ($0 is NSControl) && !$0.isHidden && $0.bounds.width > 0 }
            let lowest = controls.min { frame(of: $0, in: document).minY < frame(of: $1, in: document).minY }!
            let box = frame(of: lowest, in: document)
            if wanted > short.height + 0.5 {
                expect(abs(window.frame.height - short.height) < 0.5, "\(name): a tab that needs \(wanted) pt sits in the whole 500 pt screen (\(window.frame.height))")
                expect(controller.content.scrollableExtent > 1, "\(name): the rest of the tab scrolls (\(controller.content.scrollableExtent) pt)")
                expect(clip.bounds.origin.y < 0.5, "\(name): a tab opens at its top (clip origin \(clip.bounds.origin.y))")
                expect(!clip.documentVisibleRect.contains(box), "\(name): the last control starts below the fold (\(box) vs \(clip.documentVisibleRect))")
                let bottom = NSPoint(x: 0, y: document.frame.height - clip.bounds.height)
                clip.scroll(to: bottom); controller.content.scroll.reflectScrolledClipView(clip)
                expect(clip.documentVisibleRect.contains(box), "\(name): scrolling to the end reaches the last control (\(box) vs \(clip.documentVisibleRect))")
                expect(abs(clip.bounds.maxY - document.frame.height) < 1, "\(name): nothing is clipped past the end")
                clip.scroll(to: .zero); controller.content.scroll.reflectScrolledClipView(clip)
            } else {
                expect(controller.content.scrollableExtent < 0.5, "\(name): a tab that fits is not scrolled (\(controller.content.scrollableExtent))")
            }
        }
        // A scrolled tab goes back to its top when it is chosen again.
        controller.select(2)
        let clip = controller.content.scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: 80)); controller.content.scroll.reflectScrolledClipView(clip)
        controller.select(0); controller.select(2)
        expect(clip.bounds.origin.y < 0.5, "choosing a tab again starts it at the top (\(clip.bounds.origin.y))")
        // The screen grows: the window and the scrolling follow.
        controller.visibleFrame = { fakeVisible }
        controller.fit(animated: false)
        expect(abs(window.frame.height - controller.windowHeight(forTabAt: 2)) < 0.5 && controller.content.scrollableExtent < 0.5, "a taller screen shows the whole tab without scrolling")
    }

    // MARK: Alignment and type

    private static func alignmentAndTypography() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 2))
        for index in controller.tabItems.indices {
            controller.select(index)
            controller.window.contentView?.layoutSubtreeIfNeeded()
            let tab = controller.tabItems[index].viewController.view
            let name = controller.tabItems[index].label
            let labels = descendants(tab).compactMap { $0 as? NSTextField }.filter { SettingsLayout.rowLabels.contains($0.stringValue) }
            expect(!labels.isEmpty, "\(name) has row labels")
            for label in labels {
                expect(label.alignment == .right, "\(name): '\(label.stringValue)' is right-aligned")
                expect(label.font == DesignTokens.Typography.font(.bodyStrong) && label.font?.pointSize == 20, "\(name): '\(label.stringValue)' is 20 pt bodyStrong")
            }
            let edges = Set(labels.map { (frame(of: $0, in: tab).maxX * 2).rounded() })
            expect(edges.count == 1, "\(name): row labels share one right edge (VF-18); edges \(edges)")
            let controls = descendants(tab).compactMap { $0 as? NSControl }.filter { !($0 is NSTextField) }
            for control in controls {
                if let font = control.font { expect(font.pointSize >= 20, "\(name): \(control.className) is \(font.pointSize) pt") }
            }
            for caption in descendants(tab).compactMap({ $0 as? NSTextField }).filter({ $0.font?.pointSize == 18 }) {
                expect(caption.font == DesignTokens.Typography.font(.caption), "\(name): the only 18 pt text is a caption ('\(caption.stringValue)')")
            }
            // Every control starts at the control column, not the label column: one left edge for the whole tab.
            let grid = controller.tabItems[index].viewController
            let gridBox = frame(of: grid.grid, in: tab)
            let controlColumn = gridBox.minX + grid.labelWidth + SettingsLayout.columnSpacing
            // The form is centred across the window, with as much room on its left as on its right.
            expect(abs(gridBox.minX - (tab.bounds.maxX - gridBox.maxX)) < 1.5, "\(name): the form grid is centred (left \(gridBox.minX), right \(tab.bounds.maxX - gridBox.maxX))")
            expect(gridBox.width <= SettingsLayout.gridWidth + 0.5, "\(name): the form fits the content width (\(gridBox.width))")
            if index < 2 {
                // A short form is as wide as its widest control: its ink sits in the middle, not against the left.
                let ink = descendants(tab).filter { ($0 is NSControl) && !$0.isHidden && $0.bounds.width > 0 }.map { alignment(of: $0, in: tab) }.reduce(NSRect.null) { $0.union($1) }
                let left = ink.minX, right = tab.bounds.maxX - ink.maxX
                expect(abs(left - right) < 4, "\(name): the controls and labels are centred in the window (left room \(left), right room \(right))")
                expect(left > 30 && ink.width / tab.bounds.width > 0.7, "\(name): the form takes its share of the width, not a left-hand corner (\(ink.width / tab.bounds.width))")
            }
            var cells = 0
            for row in 0..<grid.grid.numberOfRows {
                guard let content = grid.grid.cell(atColumnIndex: 1, rowIndex: row).contentView, !(content is GlobalHotkeyForm) else { continue }
                var leaf = content
                if content is NSStackView { leaf = descendants(content).first { $0 is NSButton || $0 is NSPopUpButton } ?? content }
                guard leaf.bounds.width > 0 else { continue }
                let left = alignment(of: leaf, in: tab).minX
                expect(abs(left - controlColumn) < 1.5, "\(name) row \(row): the control starts at \(left); the control column starts at \(controlColumn)")
                cells += 1
            }
            expect(cells >= (index == 2 ? 1 : 2), "\(name): the grid rows were checked (\(cells))")
            if index == 2 {
                let form = controller.capture.hotkeyForm!
                let box = alignment(of: form.enabledCheckbox, in: tab)
                expect(abs(box.minX - controlColumn) < 1.5, "Capture: the embedded Enable checkbox starts at the control column (\(box.minX) vs \(controlColumn))")
            }
        }
        // The Capture tab's shortcut rows sit in the same label column as the rows above them.
        controller.select(2)
        let tab = controller.capture.view
        let flashLabel = descendants(tab).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Flash:" }!
        let screenLabel = descendants(tab).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Screen region:" }!
        expect(abs(frame(of: flashLabel, in: tab).maxX - frame(of: screenLabel, in: tab).maxX) < 0.5, "the embedded shortcut rows line up with the Flash row")
        let flashBox = alignment(of: controller.capture.flashCheckbox, in: tab)
        let popupBox = alignment(of: controller.capture.hotkeyForm.keyPopup(for: .screen), in: tab)
        expect(abs(flashBox.minX - popupBox.minX) < 1.5, "the checkbox and the key popup share the control column: \(flashBox.minX) vs \(popupBox.minX)")
        let labelWidth = SettingsLayout.labelColumnWidth
        let widest = SettingsLayout.rowLabels.map { ($0 as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.bodyStrong)]).width }.max()!
        expect(labelWidth >= widest, "the label column is wide enough for the longest row label (\(labelWidth) vs \(widest))")
        for (index, labels) in [GeneralSettingsTab.rowLabels, DrawingSettingsTab.rowLabels].enumerated() {
            let own = SettingsLayout.labelWidth(for: labels)
            expect(controller.tabItems[index].viewController.labelWidth == own && own <= labelWidth && (index != 0 || own < labelWidth), "\(controller.tabItems[index].label) sizes its label column to its own labels (\(own) vs \(labelWidth))")
        }
        expect(controller.capture.labelWidth == labelWidth && controller.upload.labelWidth == labelWidth, "Capture and Upload keep the shared label column")
    }

    // MARK: General and Drawing

    private static func preferenceControls() {
        var current = initialState
        let (controller, defaults, _, _, _, _) = makeController(state: current)
        _ = defaults
        var delivered: [GeneralPreferencesState] = []
        controller.onChange = { delivered.append($0); current = $0 }
        controller.select(0)
        let general = controller.general, drawing = controller.drawing
        _ = general.view; _ = drawing.view
        func state(_ buttons: [NSButton]) -> [Int] { buttons.filter { $0.state == .on }.map(\.tag) }
        expect(state(general.presenceButtons) == [0] && state(drawing.precisionButtons) == [1] && state(drawing.arrowButtons) == [2], "initial radios mirror the stored state")
        expect(general.snapCheckbox.state == .on && general.hoverHintsCheckbox.state == .off && general.keyboardTipsCheckbox.state == .off, "initial checkboxes mirror the stored state")
        expect(general.hoverHintsCheckbox.title == "Show hover hints for tools", "the tool-tip overlay is labelled clearly: '\(general.hoverHintsCheckbox.title)'")
        expect(general.snapCheckbox.title == "Show OpenSnap window in fullscreen and crosshair snaps", "the snap row uses the specified wording")
        func click(_ control: NSButton, _ edit: (inout GeneralPreferencesState) -> Void) {
            var expected = current; edit(&expected)
            let count = delivered.count
            control.performClick(nil)
            expect(delivered.count == count + 1, "one edit for \(control.title)")
            expect(delivered.last == expected, "the complete state for \(control.title): \(String(describing: delivered.last)) vs \(expected)")
        }
        click(general.presenceButtons[0]) { $0.statusMenu = 2 }
        click(general.presenceButtons[1]) { $0.statusMenu = 1 }
        click(general.snapCheckbox) { $0.includeApp = false }
        click(general.hoverHintsCheckbox) { $0.showToolTips = true }
        click(general.keyboardTipsCheckbox) { $0.showKeyboardTips = true }
        click(drawing.precisionButtons[0]) { $0.drawingPrecision = .precise }
        click(drawing.precisionButtons[2]) { $0.drawingPrecision = .loose }
        click(drawing.arrowButtons[1]) { $0.arrowHead = 1 }
        expect(state(general.presenceButtons) == [1] && state(drawing.precisionButtons) == [2] && state(drawing.arrowButtons) == [1], "radio groups stay exclusive")
        // A synchronize (menu command, reopened window) refreshes the controls and delivers nothing.
        let count = delivered.count
        controller.synchronize(GeneralPreferencesState(drawingPrecision: .precise, arrowHead: 99, includeApp: true, statusMenu: -4, showToolTips: false, showKeyboardTips: false))
        expect(delivered.count == count, "synchronize never publishes an edit")
        expect(state(drawing.precisionButtons) == [0] && state(drawing.arrowButtons) == [2] && state(general.presenceButtons) == [0], "invalid stored tags fall back to End and Both")
        expect(general.hoverHintsCheckbox.state == .off && general.keyboardTipsCheckbox.state == .off && general.snapCheckbox.state == .on, "synchronize updates the checkboxes")
        // A parent that re-synchronizes from inside the callback cannot recurse.
        var reentrant = 0
        controller.onChange = { value in reentrant += 1; controller.synchronize(value) }
        general.hoverHintsCheckbox.performClick(nil)
        expect(reentrant == 1 && general.hoverHintsCheckbox.state == .on, "echoing the state inside onChange does not recurse")
        // The window re-reads the owner's stored state when it is shown.
        controller.onChange = nil
        controller.refresh()
        expect(state(drawing.precisionButtons) == [1] && general.hoverHintsCheckbox.state == .off, "refresh re-reads the owner's stored state (still Medium, hints off), not the last edit")
    }

    // MARK: Capture flash

    private static func flash() {
        let (controller, defaults, _, _, _, _) = makeController()
        let key = OriginalCaptureFlashTiming.showFlashKey
        controller.select(2)
        let checkbox = controller.capture.flashCheckbox!
        expect(key == "showCaptureFlash" && checkbox.title == "Show capture flash", "the flash row is bound to showCaptureFlash")
        expect(defaults.object(forKey: key) == nil && checkbox.state == .on, "an absent preference reads as on")
        checkbox.performClick(nil)
        expect(defaults.object(forKey: key) as? Bool == false && !OriginalCaptureFlashTiming.showFlash(defaults: defaults), "switching it off stores false, which the capture path reads as no flash")
        checkbox.performClick(nil)
        expect(defaults.object(forKey: key) as? Bool == true && OriginalCaptureFlashTiming.showFlash(defaults: defaults), "switching it back on stores true")
        defaults.set(false, forKey: key)
        controller.refresh()
        expect(checkbox.state == .off, "a stored false shows as off when the window is shown")
        defaults.removeObject(forKey: key)
        controller.refresh()
        expect(checkbox.state == .on, "removing the preference shows on again")
        expect(UserDefaults.standard.object(forKey: key) == nil, "the process's own defaults were never written")
    }

    // MARK: Shortcuts embedded in Capture

    private static func shortcuts() {
        let (controller, defaults, manager, backend, _, _) = makeController()
        controller.select(2)
        let form = controller.capture.hotkeyForm!
        expect(form.mode == .live && form.isDescendant(of: controller.capture.view), "the shortcut form is embedded in the Capture tab")
        expect(form.saveButton == nil && form.cancelButton == nil, "the embedded form has no Save or Cancel: edits apply as they are made")
        try? manager.install(globalScreen: {}, globalWindow: {}, globalFullscreen: {}, globalFrame: {}, globalUpload: {}, globalShow: {})
        let popup = form.keyPopup(for: .screen), modifiers = form.modifierControl(for: .screen)
        let k = GlobalHotkeyKeys.choices.firstIndex { $0.name == "K" }! + 1
        expect(popup.indexOfSelectedItem == 0 && !modifiers.isEnabled, "an action with no key starts at None with its modifiers off")
        popup.selectItem(at: k); _ = popup.target?.perform(popup.action, with: popup)
        expect(modifiers.isEnabled, "choosing a key enables its modifiers")
        expect(manager.settings.screen == .none && form.statusField.stringValue.hasPrefix("Error: "), "a key without Command or Control is refused and said so: '\(form.statusField.stringValue)'")
        expect(hotkeySettings(defaults).screen == .none && backend.bindings.isEmpty, "the refused edit changed nothing stored or registered")
        modifiers.setSelected(true, forSegment: 0); _ = modifiers.target?.perform(modifiers.action, with: modifiers)
        expect(manager.settings.screen == .init(keyCode: GlobalHotkeyKeys.choices[k - 1].code, modifiers: .command), "Command plus K reaches the GlobalHotkeys model: \(manager.settings.screen)")
        expect(hotkeySettings(defaults).screen == manager.settings.screen, "and is persisted through the model's own store")
        expect(backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil && !form.statusField.stringValue.hasPrefix("Error"), "a running manager registers it at once and the error clears")
        modifiers.setSelected(true, forSegment: 3); _ = modifiers.target?.perform(modifiers.action, with: modifiers)
        expect(manager.settings.screen.modifiers == [.command, .shift], "a second modifier is added")
        let other = form.keyPopup(for: .window)
        other.selectItem(at: k); _ = other.target?.perform(other.action, with: other)
        form.modifierControl(for: .window).setSelected(true, forSegment: 0); form.modifierControl(for: .window).setSelected(true, forSegment: 3)
        _ = form.modifierControl(for: .window).target?.perform(form.modifierControl(for: .window).action, with: form.modifierControl(for: .window))
        expect(manager.settings.window == .none && form.statusField.stringValue.contains("same shortcut"), "a duplicate shortcut is refused with the manager's own message: '\(form.statusField.stringValue)'")
        popup.selectItem(at: 0); _ = popup.target?.perform(popup.action, with: popup)
        expect(!modifiers.isEnabled && (0..<4).allSatisfy { !modifiers.isSelected(forSegment: $0) }, "None clears and disables the modifiers")
        form.enabledCheckbox.state = .off; _ = form.enabledCheckbox.target?.perform(form.enabledCheckbox.action, with: form.enabledCheckbox)
        expect(!manager.settings.enabled && !hotkeySettings(defaults).enabled, "the enable box turns every shortcut off")
        form.resetButton.performClick(nil)
        expect(manager.settings == .defaults && form.enabledCheckbox.state == .on, "Reset Defaults applies the defaults at once")
        form.disableButton.performClick(nil)
        expect(!manager.settings.enabled, "Disable All applies at once")
        // F-J2-020: a duplicate the manager refused leaves a red line; Disable All answers it instead of validating the same draft again.
        form.resetButton.performClick(nil)
        for action in [GlobalHotkeyAction.screen, .window] {
            let key = form.keyPopup(for: action), mods = form.modifierControl(for: action)
            key.selectItem(at: k); _ = key.target?.perform(key.action, with: key)
            mods.setSelected(true, forSegment: 0); _ = mods.target?.perform(mods.action, with: mods)
        }
        expect(form.statusField.stringValue.hasPrefix("Error: ") && form.statusField.stringValue.contains("same shortcut"), "the duplicate leaves its error on screen: '\(form.statusField.stringValue)'")
        form.disableButton.performClick(nil)
        expect(!manager.settings.enabled && form.enabledCheckbox.state == .off && form.statusField.stringValue == GlobalHotkeyForm.idleLiveStatus && form.statusField.textColor == DesignTokens.Palette.Text.primary,
               "Disable All clears the stale duplicate error: '\(form.statusField.stringValue)'")
        expect(form.keyPopup(for: .window).indexOfSelectedItem == 0, "the rejected draft is dropped, not kept beside a disabled form")
        expect(GlobalHotkeyAction.allCases.allSatisfy { form.modifierControl(for: $0).selectedSegmentBezelColor == DesignTokens.Palette.accent }, "a chosen modifier is drawn in the accent")
        controller.show(); controller.window.orderOut(nil)
    }

    // MARK: The same form as a sheet

    private static func shortcutSheet() {
        let name = "OpenSnap.SettingsTests.sheet." + UUID().uuidString
        let defaults = TestDefaults(name: name)
        let manager = GlobalHotkeyManager(defaults: defaults, backend: FakeHotkeyBackend())
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        manager.showSettings(attachedTo: parent)
        guard let sheet = parent.attachedSheet else { return expect(false, "the shortcut sheet still attaches to a parent window") }
        guard let form = descendants(sheet.contentView!).compactMap({ $0 as? GlobalHotkeyForm }).first else { return expect(false, "the sheet holds the shortcut form") }
        // A window adopts the Return button as its default button cell (and then reports its key equivalent as empty).
        expect(form.mode == .sheet && sheet.defaultButtonCell === form.saveButton?.cell && form.cancelButton?.keyEquivalent == "\u{1b}", "the sheet keeps Save on Return and Cancel on Escape")
        expect(sheet.title == "Global Capture Shortcuts" && sheet.frame.width >= 760, "the sheet is titled and 760 wide: \(sheet.frame.width)")
        sheet.contentView?.layoutSubtreeIfNeeded()
        if let save = form.saveButton, let content = sheet.contentView, (NSScreen.main?.visibleFrame.height ?? 0) >= 840 {
            let box = save.convert(save.bounds, to: content)
            expect(content.bounds.contains(box), "Save is inside the sheet without scrolling when the screen has room: \(box) in \(content.bounds)")
        }
        let k = GlobalHotkeyKeys.choices.firstIndex { $0.name == "L" }! + 1
        form.keyPopup(for: .upload).selectItem(at: k)
        _ = form.keyPopup(for: .upload).target?.perform(form.keyPopup(for: .upload).action, with: form.keyPopup(for: .upload))
        form.modifierControl(for: .upload).setSelected(true, forSegment: 0)
        _ = form.modifierControl(for: .upload).target?.perform(form.modifierControl(for: .upload).action, with: form.modifierControl(for: .upload))
        expect(manager.settings.upload == .none, "a sheet edit stays in the draft until Save")
        form.cancelButton?.performClick(nil)
        spin(1) { parent.attachedSheet == nil }
        expect(parent.attachedSheet == nil && manager.settings.upload == .none, "Cancel closes the sheet and discards the draft")
        manager.showSettings(attachedTo: parent)
        guard let again = parent.attachedSheet, let reopened = descendants(again.contentView!).compactMap({ $0 as? GlobalHotkeyForm }).first else { return expect(false, "the sheet reopens") }
        expect(reopened.keyPopup(for: .upload).indexOfSelectedItem == 0, "a reopened sheet shows what is stored, not the cancelled draft")
        reopened.keyPopup(for: .upload).selectItem(at: k)
        _ = reopened.keyPopup(for: .upload).target?.perform(reopened.keyPopup(for: .upload).action, with: reopened.keyPopup(for: .upload))
        reopened.modifierControl(for: .upload).setSelected(true, forSegment: 0)
        reopened.saveButton?.performClick(nil)
        spin(1) { parent.attachedSheet == nil }
        expect(manager.settings.upload == .init(keyCode: GlobalHotkeyKeys.choices[k - 1].code, modifiers: .command) && parent.attachedSheet == nil, "Save applies through the model and closes the sheet")
        TestDefaults.dispose(defaults, name: name)
    }

    // MARK: Upload

    private static func sampleDestinations(count: Int) -> PublishingDestinationList {
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.invalid/shots"
        var s3 = PublishingSettings(); s3.transport = .s3; s3.s3 = S3Options()
        let items = (0..<count).map { PublishingDestination(name: "Destination \($0)", settings: $0 % 2 == 0 ? dav : s3) }
        return PublishingDestinationList(defaultID: items.dropFirst().first?.id ?? items.first?.id, destinations: items)
    }

    private static func upload() {
        let list = sampleDestinations(count: 2)
        let managed = Box<[NSWindow]>([])
        let (controller, _, _, _, _, _) = makeController(destinations: list, manage: { managed.value.append($0) })
        controller.select(3)
        let tab = controller.upload
        _ = tab.view
        tab.refresh()
        expect(tab.listedNames == ["Destination 0", "Destination 1"], "the tab lists the saved destinations: \(tab.listedNames)")
        expect(tab.rows[1].pill != nil && tab.rows[0].pill == nil, "the default destination carries the Default pill")
        expect(tab.rows[0].transportField.stringValue == PublishingProtocol.webDAV.title && tab.rows[1].transportField.stringValue == PublishingProtocol.s3.title, "each row names its transport")
        expect(tab.emptyStateText == nil && tab.summaryText == nil, "no empty state while destinations exist")
        expect(tab.manageButton.title == "Manage Destinations…" && !tab.manageButton.title.contains("..."), "the Manage button uses a real ellipsis")
        tab.manageButton.performClick(nil)
        expect(managed.value.count == 1 && managed.value[0] === controller.window, "Manage hands the Settings window to the sheet opener, so the sheet attaches to it")
        // A sheet already open is not stacked on.
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        controller.window.beginSheet(sheet)
        tab.manageButton.performClick(nil)
        expect(managed.value.count == 1, "Manage does nothing while a sheet is attached")
        controller.window.endSheet(sheet); sheet.orderOut(nil)

        let empty = makeController()
        empty.0.select(3); _ = empty.0.upload.view; empty.0.upload.refresh()
        expect(empty.0.upload.listedNames.isEmpty && empty.0.upload.emptyStateText == "No upload destination yet.", "an empty list says so")
        let many = makeController(destinations: sampleDestinations(count: 8))
        many.0.select(3); _ = many.0.upload.view; many.0.upload.refresh()
        expect(many.0.upload.listedNames.count == UploadSettingsTab.visibleRows && many.0.upload.summaryText == "and 3 more in Manage Destinations…", "a long list is summarised, not scrolled: \(String(describing: many.0.upload.summaryText))")
        expect(many.0.windowHeight(forTabAt: 3) <= fakeVisible.height, "even a long list fits the fake screen")
        // F-J2-012: the Upload tab grows with its rows, and its caption is never below the fold.
        let emptyHeight = empty.0.windowHeight(forTabAt: 3), fullHeight = many.0.windowHeight(forTabAt: 3)
        expect(fullHeight > emptyHeight + 20 && abs(many.0.window.frame.height - fullHeight) < 0.5, "the Upload window grows with its list: empty \(emptyHeight), full \(fullHeight)")
        many.0.window.contentView?.layoutSubtreeIfNeeded()
        expect(many.0.content.scrollableExtent < 0.5 && captionInside(many.0.upload), "the caption under a full list is on screen without scrolling")
        expect(many.0.upload.listScroll.documentView.map { $0.frame.height <= many.0.upload.listScroll.contentView.bounds.height + 0.5 } == true, "a list that fits its screen does not scroll inside")
        uploadOnShortScreens()
    }

    private static func captionInside(_ tab: UploadSettingsTab) -> Bool {
        tab.view.layoutSubtreeIfNeeded()
        guard let caption = descendants(tab.view).compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == "Uploads go to the default destination." }) else { return false }
        let box = frame(of: caption, in: tab.view)
        return !caption.isHidden && box.height >= caption.intrinsicContentSize.height - 0.5 && tab.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(box)
    }

    /// The list is capped by the screen: 640 pt tall screens (with and without a Dock) and a very short one. The list scrolls inside
    /// its frame; the window stays on the screen and the caption stays visible.
    private static func uploadOnShortScreens() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 12))
        let window = controller.window, tab = controller.upload
        controller.select(3)
        window.setFrameTopLeftPoint(NSPoint(x: 100, y: fakeVisible.maxY - 20))
        let natural = controller.windowHeight(forTabAt: 3)
        var capped: [CGFloat] = []
        for (label, screen) in [("640 pt screen, Dock hidden", NSRect(x: 0, y: 0, width: 1136, height: 616)), ("640 pt screen with a Dock", NSRect(x: 0, y: 70, width: 1136, height: 546)),
                                ("a 420 pt screen", NSRect(x: 0, y: 0, width: 1136, height: 420))] {
            controller.visibleFrame = { screen }
            window.setFrameTopLeftPoint(NSPoint(x: 100, y: screen.maxY - 20))
            controller.fit(animated: false)
            window.contentView?.layoutSubtreeIfNeeded()
            expect(window.frame.height <= screen.height + 0.5 && window.frame.maxY <= screen.maxY + 0.5 && window.frame.minY >= screen.minY - 0.5, "\(label): the window stays on the screen (\(window.frame) in \(screen))")
            expect(controller.content.scrollableExtent < 0.5, "\(label): the tab does not scroll as a whole (\(controller.content.scrollableExtent))")
            expect(captionInside(tab), "\(label): the caption 'Uploads go to the default destination.' is visible")
            let manage = tab.manageButton.convert(tab.manageButton.bounds, to: tab.view)
            expect(tab.view.bounds.contains(manage), "\(label): the Manage button is visible")
            let overflow = tab.listScroll.documentView!.frame.height - tab.listScroll.contentView.bounds.height
            if natural > screen.height + 0.5 {
                expect(overflow > 1, "\(label): the list scrolls inside its frame (\(overflow) pt past it)")
                expect(tab.listHeight >= 2 * SettingsDestinationRow.height - 0.5, "\(label): the list keeps at least two rows (\(tab.listHeight))")
            } else {
                expect(overflow < 0.5, "\(label): the list fits without scrolling")
            }
            capped.append(tab.listHeight)
        }
        expect(capped[2] < capped[1] + 0.5 && capped[1] <= capped[0] + 0.5, "a shorter screen gives the list less room: \(capped)")
        // The list opens at its first row, and the screen growing gives the list its room back.
        controller.visibleFrame = { fakeVisible }
        window.setFrameTopLeftPoint(NSPoint(x: 100, y: fakeVisible.maxY - 20))
        controller.fit(animated: false)
        window.contentView?.layoutSubtreeIfNeeded()
        expect(abs(window.frame.height - natural) < 0.5 && tab.listScroll.contentView.bounds.origin.y < 0.5, "a taller screen shows the whole list again")
    }

    /// The real coordinator: the sheet attaches to the Settings window, the list refreshes when it ends, and the shutdown barrier still runs.
    private static func uploadWithPublishing() {
        func coordinator(_ destinations: [PublishingDestination]) -> PublishingCoordinator {
            let publisher = PublishingCoordinator()
            publisher.store = PublishingDestinationStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("opensnap-settings-" + UUID().uuidString, isDirectory: true),
                                                         secrets: PublishingMemorySecrets())
            for destination in destinations { try? publisher.store.save(destination, password: "") }
            return publisher
        }
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.invalid/shots"; dav.publicBaseURL = "https://dav.example.invalid/shots"
        let first = PublishingDestination(name: "Work", settings: dav)
        let publisher = coordinator([first])
        let name = "OpenSnap.SettingsTests.publishing." + UUID().uuidString
        let defaults = TestDefaults(name: name)
        let controller = SettingsWindowController(state: { initialState }, hotkeys: GlobalHotkeyManager(defaults: defaults, backend: FakeHotkeyBackend()), defaults: defaults,
                                                  destinations: { publisher.destinations() }, manageDestinations: { publisher.showSettings(relativeTo: $0) })
        controller.visibleFrame = { fakeVisible }
        var closes = 0
        controller.onClose = { closes += 1 }
        controller.select(3)
        controller.upload.refresh()
        expect(controller.upload.listedNames == ["Work"], "the tab reads the coordinator's saved list: \(controller.upload.listedNames)")
        controller.upload.manageButton.performClick(nil)
        guard let sheet = controller.window.attachedSheet else { return expect(false, "the Destinations sheet did not attach to the Settings window") }
        expect(sheet.title == "Upload Destinations", "the existing Destinations sheet is the one that opens: '\(sheet.title)'")
        controller.window.cancelOperation(nil)
        expect(closes == 0 && controller.window.attachedSheet === sheet, "Escape on the Settings window leaves its sheet alone")
        // Adding a destination while the sheet is open shows up in the list as soon as the sheet ends.
        let second = PublishingDestination(name: "Backup", settings: dav)
        try? publisher.store.save(second, password: "")
        publisher.cancelSettings()
        spin(2) { controller.window.attachedSheet == nil && controller.upload.listedNames.count == 2 }
        expect(controller.window.attachedSheet == nil, "closing the sheet detaches it")
        expect(controller.upload.listedNames == ["Work", "Backup"], "the list refreshes when the sheet ends: \(controller.upload.listedNames)")

        // The shutdown barrier with the Settings window as the sheet's parent.
        controller.upload.manageButton.performClick(nil)
        expect(controller.window.attachedSheet != nil, "the sheet opens again")
        var acknowledged = false
        publisher.shutdown { acknowledged = true }
        spin(5) { acknowledged && controller.window.attachedSheet == nil }
        expect(acknowledged, "shutdown acknowledged with the Destinations sheet attached to Settings")
        expect(controller.window.attachedSheet == nil, "shutdown dismissed the sheet from the Settings window")
        controller.upload.manageButton.performClick(nil)
        expect(controller.window.attachedSheet == nil, "no sheet opens after shutdown")
        TestDefaults.dispose(defaults, name: name)
    }

    // MARK: Words

    private static func words() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 1))
        var strings: [String] = []
        for index in controller.tabItems.indices {
            controller.select(index)
            strings += texts(in: controller.tabItems[index].viewController.view)
            strings.append(controller.window.title)
        }
        strings += controller.tabItems.map(\.label)
        expect(strings.count > 40, "the text walk found the window's words (\(strings.count))")
        let retired = ["ski", "tch"].joined()
        for string in strings {
            expect(!string.localizedCaseInsensitiveContains(retired), "no retired product name anywhere: '\(string)'")
            expect(!string.contains("..."), "no ASCII ellipsis: '\(string)'")
        }
        expect(strings.contains("Manage Destinations…") && strings.contains("Show capture flash") && strings.contains("Holding Option reverses the setting."), "the walk saw the real strings")
    }

    // MARK: The font floor (G4)

    private static func viewTreeAudit() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 3))
        var judged = 0
        for index in controller.tabItems.indices {
            controller.select(index)
            controller.window.contentView?.layoutSubtreeIfNeeded()
            let name = "Settings: " + controller.tabItems[index].label
            let windowReport = ViewTreeAudit.audit(controller.window, surface: name)
            let viewReport = ViewTreeAudit.audit(controller.tabItems[index].viewController.view, surface: name + " (tab view)")
            expect(!viewReport.findings.isEmpty, "\(name): the walker found text, so zero violations means something")
            expect(windowReport.violations.isEmpty && viewReport.violations.isEmpty, "\(name) breaks the type floor:\n\(windowReport.description)\n\(viewReport.description)")
            judged += viewReport.findings.count
        }
        expect(judged > 20, "the audit judged the controls of every tab (\(judged))")
        print("  Settings window: \(judged) text items judged across four tabs, 0 violations")
    }
}
#endif
