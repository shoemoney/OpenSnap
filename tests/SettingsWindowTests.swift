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
import Carbon

@MainActor
private final class FakeHotkeyBackend: GlobalHotkeyBackend {
    var bindings: [UInt32: GlobalHotkeyBinding] = [:]
    /// Another app has taken the key: registering fails while this is set.
    var failRegister = false
    /// The status Carbon answers with for a key another app holds, put through the app's own mapping to words.
    var failRegisterStatus: OSStatus?
    var registeredIDs: Set<UInt32> { Set(bindings.keys) }
    func installHandler(onEvent: @escaping @MainActor @Sendable (UInt32) -> Void) throws {}
    func systemReservedBindings() throws -> Set<GlobalHotkeyBinding> { [] }
    func register(_ binding: GlobalHotkeyBinding, id: UInt32) throws {
        if let failRegisterStatus { throw carbonHotkeyFailure("RegisterEventHotKey for \(binding.displayName)", failRegisterStatus, shortcut: binding.displayName) }
        if failRegister { throw NSError(domain: "FakeHotkeyBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "That key is already taken by another app."]) }
        bindings[id] = binding
    }
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
                                       actions: SettingsDestinationActions = SettingsDestinationActions()) -> (SettingsWindowController, TestDefaults, GlobalHotkeyManager, FakeHotkeyBackend, Box<GeneralPreferencesState>, Box<[GeneralPreferencesState]>) {
        let defaults = TestDefaults(name: name)
        let backend = FakeHotkeyBackend()
        let manager = GlobalHotkeyManager(defaults: defaults, backend: backend)
        let current = Box(state), delivered = Box<[GeneralPreferencesState]>([])
        let controller = SettingsWindowController(state: { current.value }, hotkeys: manager, defaults: defaults,
                                                  destinations: { destinations }, destinationActions: actions)
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
        upload()
        uploadActionPlates()
        uploadWithPublishing()
        shortcutPause()
        shortcutPauseFailureAndNotification()
        liveDifferentiateOutline()
        liveDifferentiateRow()
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

    /// The tabs read on their plate in light, dark and both Increase Contrast arms. Glass is a live material an offscreen render cannot
    /// sample, so a resting label is judged against the two surfaces the plate can be: the window surface it floats over and the opaque
    /// plate Reduce Transparency draws; the current tab's label is judged against its own accent fill, blended over the window.
    private static func tabStripContrast() {
        typealias Palette = DesignTokens.Palette
        for (name, appearance) in ContrastProbe.appearances {
            let highContrast = name.contains("Contrast")
            appearance.performAsCurrentDrawingAppearance {
                let window = Palette.resolve(Palette.Surface.window, for: appearance)
                let plate = Palette.resolve(Palette.Surface.content, for: appearance)
                let rest = StateStyles.command(.rest, primary: false, focused: false, highContrast: highContrast, differentiate: false, appearance: appearance)
                for (surfaceName, surface) in [("window", window), ("opaque plate", plate)] {
                    let ratio = Palette.contrastRatio(rest.content, Palette.rgb(surface).rgb)
                    expect(ratio >= 4.5, "a resting tab label reads at 4.5:1 on the \(surfaceName) (\(name): \(ratio))")
                }
                let selected = StateStyles.command(.selected, primary: false, focused: false, highContrast: highContrast, differentiate: false, appearance: appearance)
                let fill = selected.fill ?? .clear
                let backdrop = Palette.blend(fill, alpha: fill.alphaComponent, over: window)
                let ratio = Palette.contrastRatio(selected.content, backdrop)
                expect(selected.strongText && ratio >= 4.5, "the current tab's label is semibold and reads on its own fill (\(name): \(ratio))")
            }
        }
        // The same through the strip a user sees: Reduce Transparency draws an opaque plate under the tabs, so the drawn pixels can be judged.
        defer { DisplayOptions.override = nil }
        DisplayOptions.override = DisplayOptions(reduceTransparency: true)
        let (controller, _, _, _, _, _) = makeController()
        let strip = controller.strip
        controller.select(1)
        strip.frame = NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsTabStrip.height)
        strip.layoutSubtreeIfNeeded()
        expect(strip.plate.transparencyPlate != nil, "Reduce Transparency puts the opaque plate behind the tabs")
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
        // Differentiate Without Color: the current tab also carries the capsule under its glyph, a shape and not a tint alone.
        func capsules(_ options: DisplayOptions?) -> [Bool] {
            DisplayOptions.override = options
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            strip.select(0); strip.select(1)
            return strip.buttons.map { $0.showsIndicator && !$0.indicatorLayer.isHidden }
        }
        let plainTabs = capsules(.none), outlinedTabs = capsules(DisplayOptions(differentiateWithoutColor: true))
        DisplayOptions.override = nil
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(plainTabs == [false, false, false, false] && outlinedTabs == [false, true, false, false],
               "the current tab gains the capsule under Differentiate Without Color and the others stay bare (\(plainTabs) -> \(outlinedTabs))")
        strip.select(0)
        expect(strip.contentWidth + 2 * DesignTokens.Space.s3 <= SettingsLayout.contentWidth, "the four tabs fit the 640 pt window: \(strip.contentWidth)")
        let stripBox = strip.convert(strip.bounds, to: window.contentView), rowBox = strip.buttons.map { $0.convert($0.bounds, to: window.contentView) }.reduce(NSRect.null) { $0.union($1) }
        expect(abs((rowBox.midX) - stripBox.midX) < 1, "the tabs are centred across the window")
        expect(abs(window.contentLayoutRect.maxY - strip.convert(strip.bounds, to: nil).maxY) < 1.5 || strip.frame.maxY >= (window.contentView?.bounds.maxY ?? 0) - 0.5,
               "the strip is at the top of the content")

        // The four tabs share ONE glass plate in the bar's container, over a solid window surface with a separator below; no glass nests.
        expect(strip.plate.arrangedViews.count == 4 && zip(strip.plate.arrangedViews, strip.buttons).allSatisfy { $0 === $1 } && strip.buttons.allSatisfy { $0.isDescendant(of: strip.plate) },
               "the four tabs sit on one plate, in order")
        expect(plates(in: strip).count == 1 && strip.plate.superview != nil && strip.plate.isDescendant(of: strip.container) && strip.container.superview === strip,
               "that is the strip's only plate, held in its glass container")
        expect(nestedGlass(in: strip).isEmpty && strip.plate.tintColor == nil && strip.plate.identifier?.rawValue == "SettingsTabBar", "no glass inside the plate, and the plate carries no tint")
        expect(!strip.buttons.contains { $0.superview is NSVisualEffectView } && !(strip is NSVisualEffectView) && !(strip is NSGlassEffectView), "the strip itself is a plain view; the plate is its glass")
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

        // States: rest, hover, pressed and selected are fills StatePlate draws from StateStyles; selected adds a border, a semibold label and a solid glyph (not colour alone).
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            controller.select(1)
            // The glass hands its content its own appearance (the material decides), so each tab is judged under the appearance it really has.
            func expected(_ state: ControlState, _ button: NSView) -> StateStyle {
                StateStyles.command(state, primary: false, focused: false, highContrast: false, differentiate: false, appearance: button.effectiveAppearance)
            }
            for (index, button) in strip.buttons.enumerated() {
                let layer = button.layer!
                let fill = rgb(layer.backgroundColor, in: button)
                let runFont = button.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                if index == 1 {
                    expect(layer.borderWidth == 1 && rgb(layer.borderColor, in: button) == resolved(Palette.accent, in: button), "\(appearance.rawValue): the selected tab has a 1 pt accent border")
                    expect(fill == resolved(expected(.selected, button).fill!, in: button) && abs(fill.last! - 0.20) < 0.001, "\(appearance.rawValue): the selected tab has the selected fill: \(fill)")
                    expect(button.plate.stateStyle.strongText && runFont == DesignTokens.Typography.font(.bodyStrong), "\(appearance.rawValue): the selected label is semibold, not colour alone")
                    expect(button.contentTintColor.map { resolved($0, in: button) } == resolved(expected(.selected, button).content, in: button), "\(appearance.rawValue): the selected glyph takes the state's content colour")
                    expect(button.iconSource != .none && button.activeFamily == .solid, "\(appearance.rawValue): the selected glyph is the solid one")
                    expect(button.accessibilityValue() as? Int == 1 && button.isCurrent, "the selected tab reports value 1")
                } else {
                    expect(layer.borderWidth == 0 && (fill.last ?? 0) == 0, "\(appearance.rawValue): \(button.title) rests with no fill and no border (\(fill))")
                    expect(runFont == DesignTokens.Typography.font(.body) && !button.plate.stateStyle.strongText, "\(appearance.rawValue): a resting label is regular weight")
                    expect(button.contentTintColor.map { resolved($0, in: button) } == resolved(expected(.rest, button).content, in: button), "\(appearance.rawValue): a resting glyph takes the rest content colour")
                    expect(button.accessibilityValue() as? Int == 0 && !button.isCurrent, "an unselected tab reports value 0")
                }
            }
            let rest = strip.buttons[2]
            rest.setHovered(true)
            expect(rgb(rest.layer?.backgroundColor, in: rest) == resolved(Palette.State.hover, in: rest), "\(appearance.rawValue): hover fills with the hover colour")
            rest.highlight(true)
            expect(rgb(rest.layer?.backgroundColor, in: rest) == resolved(Palette.State.pressed, in: rest), "\(appearance.rawValue): pressed fills with the pressed colour")
            rest.highlight(false); rest.setHovered(false)
            expect((rgb(rest.layer?.backgroundColor, in: rest).last ?? 0) == 0, "\(appearance.rawValue): the fill clears when the pointer leaves")
            let current = strip.buttons[1]
            current.setHovered(true)
            expect(rgb(current.layer?.backgroundColor, in: current) == resolved(expected(.selected, current).fill!, in: current) && current.layer?.borderWidth == 1,
                   "\(appearance.rawValue): hover never washes out the selected tab")
            current.highlight(true)
            expect((rgb(current.layer?.backgroundColor, in: current).last ?? 0) >= 0.32 - 0.001, "\(appearance.rawValue): pressing the selected tab deepens its fill")
            current.highlight(false); current.setHovered(false)
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
        // The animation runs on a clock the test owns: each frame is asked for at a chosen moment and waited for as a condition, so no
        // assertion depends on how many timer ticks a loaded machine happens to deliver in a fixed time.
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        controller.clock = { now }
        controller.reduceMotion = { false }; controller.animatesWhenHidden = true
        func settle(_ what: String, _ condition: () -> Bool) {
            spin(10, until: condition)
            expect(condition(), "timed out waiting for \(what) (height \(window.frame.height))")
        }
        func finishAnimation(toTabAt index: Int) {
            now = now.addingTimeInterval(SettingsWindowController.resizeDuration + 1)
            settle("the window to reach tab \(index)'s height") { abs(window.frame.height - controller.windowHeight(forTabAt: index)) < 0.5 }
        }
        controller.select(0); finishAnimation(toTabAt: 0)
        let top = window.frame.maxY, startHeight = window.frame.height
        let targetHeight = controller.windowHeight(forTabAt: 3)
        controller.select(3)
        let began = now
        for fraction in [0.25, 0.5, 0.75] {
            now = began.addingTimeInterval(SettingsWindowController.resizeDuration * fraction)
            let eased = CGFloat(fraction * fraction * (3 - 2 * fraction))
            let expected = startHeight + (targetHeight - startHeight) * eased
            settle("the frame \(Int(fraction * 100))% of the way (\(expected))") { abs(window.frame.height - expected) < 1 }
            expect(window.frame.height > startHeight + 1 && window.frame.height < targetHeight - 1, "the resize is animated, not a jump (\(window.frame.height) between \(startHeight) and \(targetHeight))")
            expect(abs(window.frame.maxY - top) < 0.5, "the title bar stays put while the window resizes (top \(window.frame.maxY) vs \(top))")
        }
        finishAnimation(toTabAt: 3)
        expect(abs(window.frame.height - targetHeight) < 0.5 && abs(window.frame.maxY - top) < 0.5, "the animation lands on the tab's height with the top where it was")
        // A tab picked mid-animation replaces the one before it and the last choice wins.
        controller.select(2)
        now = now.addingTimeInterval(SettingsWindowController.resizeDuration * 0.5)
        let midway = window.frame.height
        settle("a frame on the way to tab 2") { abs(window.frame.height - midway) > 0.5 }
        controller.select(1)
        finishAnimation(toTabAt: 1)
        expect(abs(window.frame.height - controller.windowHeight(forTabAt: 1)) < 0.5 && abs(window.frame.maxY - top) < 0.5, "the last tab chosen mid-animation sets the final size")
        controller.select(0); finishAnimation(toTabAt: 0)
        controller.clock = Date.init
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
        let errorHeight = { window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsContentView.chromeHeight + controller.capture.fittingHeight)).height }
        spin(10) { form.statusField.stringValue.hasPrefix("Error: ") && abs(window.frame.height - errorHeight()) < 0.5 }
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
        let refitHeight = { abs(window.frame.height - controller.windowHeight(forTabAt: 2)) < 0.5 }
        spin(10) { field.stringValue == GlobalHotkeyForm.idleLiveStatus && refitHeight() }
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
            if index == SettingsWindowController.uploadTabIndex {
                // R2-016: the list takes the whole width under a heading; there is no label column.
                let heading = descendants(tab).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Destinations" }
                expect(heading?.font == DesignTokens.Typography.font(.bodyStrong) && heading?.alignment != .right && labels.isEmpty, "\(name): a 20 pt heading, not a right-aligned row label")
                let list = controller.upload.listScroll.superview ?? tab
                expect(controller.upload.labelWidth == 0 && UploadSettingsTab.listWidth == SettingsLayout.gridWidth, "\(name): the list is as wide as the content (\(UploadSettingsTab.listWidth))")
                _ = list
            } else {
            expect(!labels.isEmpty, "\(name) has row labels")
            for label in labels {
                expect(label.alignment == .right, "\(name): '\(label.stringValue)' is right-aligned")
                expect(label.font == DesignTokens.Typography.font(.bodyStrong) && label.font?.pointSize == 20, "\(name): '\(label.stringValue)' is 20 pt bodyStrong")
            }
            let edges = Set(labels.map { (frame(of: $0, in: tab).maxX * 2).rounded() })
            expect(edges.count == 1, "\(name): row labels share one right edge (VF-18); edges \(edges)")
            }
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
            let controlColumn = gridBox.minX + (grid.labelWidth == 0 ? 0 : grid.labelWidth + SettingsLayout.columnSpacing)   // the Upload tab has no label column
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
        expect(controller.capture.labelWidth == labelWidth, "Capture keeps the shared label column (its shortcut rows need the longest labels)")
        // Upload has one label; sizing the column to it gives the list and its Add…, Edit…, Remove and Make Default row the room they need.
        expect(controller.upload.labelWidth == UploadSettingsTab.labelColumnWidth && controller.upload.labelWidth < labelWidth && controller.upload.controlWidth == UploadSettingsTab.listWidth,
               "Upload sizes its label column to 'Destinations:' (\(controller.upload.labelWidth) vs \(labelWidth)) and gives the rest to the list (\(controller.upload.controlWidth))")
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
        expect(form.isDescendant(of: controller.capture.view), "the shortcut form is embedded in the Capture tab")
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
        form.clearButton.performClick(nil)
        expect(manager.settings == .defaults && form.enabledCheckbox.state == .on && GlobalHotkeyAction.allCases.allSatisfy { manager.settings[$0] == .none }, "Clear All sets every key to None at once")
        expect(form.clearButton.title == "Clear All" && !descendants(form).contains { ($0 as? NSButton)?.title == "Disable All" || ($0 as? NSButton)?.title == "Reset Defaults" },
               "Reset Defaults is Clear All, and Disable All is gone: the enable box is the one switch")
        // F-J2-020: a duplicate the manager refused leaves a red line; unticking the box answers it instead of validating the same draft again.
        for action in [GlobalHotkeyAction.screen, .window] {
            let key = form.keyPopup(for: action), mods = form.modifierControl(for: action)
            key.selectItem(at: k); _ = key.target?.perform(key.action, with: key)
            mods.setSelected(true, forSegment: 0); _ = mods.target?.perform(mods.action, with: mods)
        }
        expect(form.statusField.stringValue.hasPrefix("Error: ") && form.statusField.stringValue.contains("same shortcut"), "the duplicate leaves its error on screen: '\(form.statusField.stringValue)'")
        form.enabledCheckbox.state = .off; _ = form.enabledCheckbox.target?.perform(form.enabledCheckbox.action, with: form.enabledCheckbox)
        expect(!manager.settings.enabled && form.enabledCheckbox.state == .off && form.statusField.stringValue == GlobalHotkeyForm.idleLiveStatus && form.statusField.textColor == DesignTokens.Palette.Text.primary,
               "Unticking the box clears the stale duplicate error: '\(form.statusField.stringValue)'")
        expect(form.keyPopup(for: .window).indexOfSelectedItem == 0, "the rejected draft is dropped, not kept beside a disabled form")
        expect(GlobalHotkeyAction.allCases.allSatisfy { form.modifierControl(for: $0).selectedSegmentBezelColor == DesignTokens.Palette.accent }, "a chosen modifier is drawn in the accent")
        controller.show(); controller.window.orderOut(nil)
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
        var edits: [(String?, NSWindow)] = [], defaults: [String] = [], removed: [String] = []
        var actions = SettingsDestinationActions()
        actions.edit = { edits.append(($0?.name, $1)) }
        actions.makeDefault = { defaults.append($0) }
        actions.remove = { removed.append($0) }
        let (controller, _, _, _, _, _) = makeController(destinations: list, actions: actions)
        controller.select(3)
        let tab = controller.upload
        _ = tab.view
        tab.refresh()
        expect(tab.listedNames == ["Destination 0", "Destination 1"], "the tab lists the saved destinations: \(tab.listedNames)")
        expect(tab.rows[1].pill != nil && tab.rows[0].pill == nil, "the default destination carries the Default pill")
        expect(tab.rows[0].transportField.stringValue == PublishingProtocol.webDAV.title && tab.rows[1].transportField.stringValue == PublishingProtocol.s3.title, "each row names its transport")
        expect(tab.emptyStateText == nil && tab.emptyAddButton.isHidden, "no empty state while destinations exist")
        expect(tab.hintIsVisible, "R2-016: the line about switching destinations shows once there are destinations")
        if let pill = tab.rows.compactMap(\.pill).first {
            pill.layoutSubtreeIfNeeded(); pill.updateLayer()
            expect(pill.layer?.backgroundColor == NSColor.clear.cgColor, "R2-016: the Default pill is outlined, not filled with the selection colour")
        }
        controller.window.contentView?.layoutSubtreeIfNeeded()
        for button in [tab.addButton!, tab.editButton!, tab.removeButton!, tab.defaultButton!] {
            let titleWidth = (button.title as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.body)]).width
            expect(button.frame.width >= titleWidth + 8 && tab.view.bounds.contains(button.convert(button.bounds, to: tab.view)), "\(button.title) is whole inside the tab (\(button.frame.width) pt for \(titleWidth) of text)")
        }
        expect(["Add…", "Edit…", "Remove", "Make Default"] == [tab.addButton, tab.editButton, tab.removeButton, tab.defaultButton].map(\.title)
               && !tab.addButton.title.contains("..."), "the list has Add…, Edit…, Remove and Make Default with a real ellipsis")
        expect(tab.selectedID == list.defaultID && tab.rows[1].isSelected && !tab.rows[0].isSelected, "the default destination starts selected, so the buttons are ready")
        expect(tab.editButton.isEnabled && tab.removeButton.isEnabled && !tab.defaultButton.isEnabled, "Make Default is off for the destination that already is the default")
        tab.rows[0].onClick?(1)
        expect(tab.selectedID == list.destinations[0].id && tab.rows[0].isSelected && !tab.rows[1].isSelected && tab.defaultButton.isEnabled, "a click selects a row and turns Make Default on")
        expect(tab.rows[0].accessibilityRole() == .row && tab.rows[0].isAccessibilitySelected() && !tab.rows[1].isAccessibilitySelected(), "the selected row is said to be selected")
        tab.defaultButton.performClick(nil)
        expect(defaults == [list.destinations[0].id], "Make Default hands the selected destination to the owner")
        tab.addButton.performClick(nil)
        expect(edits.count == 1 && edits[0].0 == nil && edits[0].1 === controller.window, "Add… opens the editor on the Settings window with no destination")
        tab.editButton.performClick(nil)
        expect(edits.count == 2 && edits[1].0 == "Destination 0" && edits[1].1 === controller.window, "Edit… opens the selected destination on the Settings window")
        tab.rows[1].onClick?(2)
        expect(edits.count == 3 && edits[2].0 == "Destination 1", "a double click edits that row")
        // A sheet already open is not stacked on.
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        controller.window.beginSheet(sheet)
        tab.addButton.performClick(nil); tab.editButton.performClick(nil)
        expect(edits.count == 3, "Add… and Edit… do nothing while a sheet is attached")
        controller.window.endSheet(sheet); sheet.orderOut(nil)

        // Remove asks first, as an app-owned sheet on Settings: Cancel is the default, Remove is destructive, and nothing is removed before the answer.
        var shown: [(alert: AppAlert, host: NSWindow?)] = []
        AppAlert.presenter = { alert, host, _ in shown.append((alert, host)) }
        defer { AppAlert.presenter = nil }
        tab.select(id: list.destinations[0].id)
        tab.removeButton.performClick(nil)
        expect(shown.count == 1 && controller.pendingRemoval === shown[0].alert && shown[0].host === controller.window, "Remove opens one app-owned alert hanging from the Settings window")
        let alert = shown[0].alert
        expect(alert.title == "Remove “Destination 0”?" && alert.buttons == [.init(title: "Cancel", role: .cancel), .init(title: "Remove", role: .destructive)], "the title names the destination; Cancel first, Remove destructive")
        expect(alert.buttonViews[0].keyEquivalent == "\r" && alert.buttonViews[1].keyEquivalent.isEmpty && alert.unansweredResponse == .alertFirstButtonReturn, "a stray Return or Escape is Cancel, never Remove")
        tab.removeButton.performClick(nil)
        expect(shown.count == 1 && removed.isEmpty, "a second Remove does not stack another question, and nothing is removed before the answer")
        alert.dismiss(withButton: 0)
        expect(controller.pendingRemoval == nil && removed.isEmpty, "Cancel removes nothing and frees the window")
        tab.removeButton.performClick(nil)
        shown[1].alert.dismiss(withButton: 1)
        expect(removed == [list.destinations[0].id] && controller.pendingRemoval == nil, "Remove removes exactly the selected destination")

        let empty = makeController()
        empty.0.select(3); _ = empty.0.upload.view; empty.0.upload.refresh()
        expect(empty.0.upload.listedNames.isEmpty && empty.0.upload.emptyStateText == "No destinations yet", "an empty list says so: \(String(describing: empty.0.upload.emptyStateText))")
        expect(!empty.0.upload.hintIsVisible, "R2-016: with nothing to switch to, the line about right-clicking Upload is not shown")
        expect(!empty.0.upload.emptyAddButton.isHidden && empty.0.upload.emptyAddButton.title == "Add…" && empty.0.upload.emptyAddButton.isDescendant(of: empty.0.upload.listScroll),
               "the empty list carries its own Add… button inside the list")
        expect(empty.0.upload.view.subviews.isEmpty == false && empty.0.upload.addButton.isHiddenOrHasHiddenAncestor && empty.0.upload.removeButton.isHiddenOrHasHiddenAncestor, "the four-button row steps aside while the list is empty, so there is one Add…")
        var addedFromEmpty = 0
        empty.0.upload.onAdd = { addedFromEmpty += 1 }
        empty.0.upload.emptyAddButton.performClick(nil)
        expect(addedFromEmpty == 1, "the in-list Add… adds")
        let many = makeController(destinations: sampleDestinations(count: 8))
        many.0.select(3); _ = many.0.upload.view; many.0.upload.refresh()
        expect(many.0.upload.listedNames.count == 8, "every destination is listed, none is summarised away: \(many.0.upload.listedNames.count)")
        expect(many.0.windowHeight(forTabAt: 3) <= fakeVisible.height, "even a long list fits the fake screen")
        // F-J2-012: the Upload tab grows with its rows, and its caption is never below the fold.
        let emptyHeight = empty.0.windowHeight(forTabAt: 3), fullHeight = many.0.windowHeight(forTabAt: 3)
        expect(fullHeight > emptyHeight + 20 && abs(many.0.window.frame.height - fullHeight) < 0.5, "the Upload window grows with its list: empty \(emptyHeight), full \(fullHeight)")
        many.0.window.contentView?.layoutSubtreeIfNeeded()
        expect(many.0.content.scrollableExtent < 0.5 && captionInside(many.0.upload), "the caption under a full list is on screen without scrolling")
        uploadOnShortScreens()
    }

    // MARK: Glass choices

    /// Every glass view that sits inside another glass plate: there must be none, the plate is the only glass and the controls draw fills.
    private static func nestedGlass(in view: NSView) -> [NSView] {
        descendants(view).filter { candidate in
            guard candidate is NSGlassEffectView else { return false }
            var up = candidate.superview
            while let ancestor = up { if ancestor is NSGlassEffectView { return true }; up = ancestor.superview }
            return false
        }
    }
    private static func plates(in view: NSView) -> [GlassSurfaceView] { descendants(view).compactMap { $0 as? GlassSurfaceView } }
    private static func resolvedAlpha(_ color: NSColor?, in view: NSView) -> CGFloat? {
        var alpha: CGFloat?
        view.effectiveAppearance.performAsCurrentDrawingAppearance { alpha = color?.usingColorSpace(.sRGB)?.alphaComponent }
        return alpha
    }

    /// Add…, Edit…, Remove and Make Default are titled command buttons on ONE glass plate, drawing their own fills; the lone Add… in an
    /// empty list has a plate of its own that goes with it.
    private static func uploadActionPlates() {
        let list = sampleDestinations(count: 2)
        let (controller, _, _, _, _, _) = makeController(destinations: list)
        controller.select(3)
        let tab = controller.upload
        _ = tab.view; tab.refresh()
        controller.window.contentView?.layoutSubtreeIfNeeded()
        let plate = tab.actionPlate!
        let buttons = [tab.addButton!, tab.editButton!, tab.removeButton!, tab.defaultButton!]
        expect(plate.arrangedViews.count == 4 && zip(plate.arrangedViews, buttons).allSatisfy { $0 === $1 }, "the four commands share one plate, in reading order")
        expect(plate.identifier?.rawValue == "SettingsDestinationActions" && plate.isDescendant(of: tab.view) && !plate.isHiddenOrHasHiddenAncestor, "the plate is on the tab and on screen")
        expect(plate.tintColor == nil && plate.accessibilityRole() == .group && plate.accessibilityLabel() == "Destination actions", "the plate carries no tint and is a named group for VoiceOver")
        expect(buttons.allSatisfy { $0 is CommandButton && $0.isDescendant(of: plate) && $0.font?.pointSize == 20 && $0.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) is NSFont },
               "each command is a CommandButton with a 20 pt label")
        expect(buttons.allSatisfy { $0.frame.height == GlassChrome.Metrics.commandHeight && $0.frame.width >= SettingsActionButton.width(for: $0.title) - 0.5 }, "each is a control tall and wide enough for its label")
        expect(nestedGlass(in: tab.view).isEmpty && plates(in: tab.view).filter { !$0.isHiddenOrHasHiddenAncestor }.count == 1, "one visible plate and no glass inside glass")
        // The enabled and disabled logic is unchanged, and a disabled command dims through the state alpha.
        expect(tab.editButton.isEnabled && tab.removeButton.isEnabled && !tab.defaultButton.isEnabled && tab.addButton.isEnabled, "Make Default is off for the default destination")
        expect(tab.defaultButton.alphaValue == StateStyles.disabledAlpha && tab.defaultButton.plate.isDisabled && tab.defaultButton.plate.style.fill == nil, "a disabled command dims and draws no fill")
        expect(tab.editButton.alphaValue == 1 && !tab.editButton.plate.isDisabled, "an enabled one is at full strength")
        tab.editButton.setHovered(true)
        expect(abs((resolvedAlpha(tab.editButton.plate.style.fill, in: tab.editButton) ?? 0) - 0.08) < 0.001 && tab.editButton.layer?.backgroundColor != nil, "hover fills the command, not the plate")
        tab.editButton.setHovered(false)
        expect(tab.editButton.plate.style.fill == nil, "the fill clears when the pointer leaves")
        tab.rows[0].onClick?(1)
        expect(tab.defaultButton.isEnabled && tab.defaultButton.alphaValue == 1, "choosing another row turns Make Default on at full strength")
        // The plates follow the display options while the window is up.
        defer { DisplayOptions.override = nil }
        DisplayOptions.override = DisplayOptions(reduceTransparency: true, increaseContrast: true)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(plate.transparencyPlate != nil && plate.showsContrastBorder && buttons.allSatisfy { $0.accessibility.increaseContrast }, "Reduce Transparency and Increase Contrast reach the plate and its commands live")
        DisplayOptions.override = nil
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(plate.transparencyPlate == nil && !plate.showsContrastBorder, "and they go again when the options do")

        // An empty list: the lone Add… sits on its own plate inside the list, and the four-command plate steps aside.
        let empty = makeController()
        empty.0.select(3)
        let blank = empty.0.upload
        _ = blank.view; blank.refresh()
        empty.0.window.contentView?.layoutSubtreeIfNeeded()
        expect(!blank.emptyAddPlate.isHiddenOrHasHiddenAncestor && blank.emptyAddPlate.arrangedViews.count == 1 && blank.emptyAddPlate.arrangedViews[0] === blank.emptyAddButton
               && blank.emptyAddPlate.isDescendant(of: blank.listScroll), "the empty list's Add… sits on its own plate inside the list")
        expect(blank.actionPlate.isHiddenOrHasHiddenAncestor && nestedGlass(in: blank.view).isEmpty, "the four-command plate is out of the layout while the list is empty, and nothing nests")
        expect(!blank.emptyAddButton.isHidden && blank.emptyAddButton.title == "Add…" && blank.emptyAddButton.identifier?.rawValue == "addFirstDestination", "the in-list Add… keeps its title and identifier")
        // Once a destination exists the lone plate goes with its button.
        let filled = makeController(destinations: sampleDestinations(count: 1))
        filled.0.select(3)
        _ = filled.0.upload.view; filled.0.upload.refresh()
        expect(filled.0.upload.emptyAddButton.isHidden && filled.0.upload.emptyAddPlate.isHidden && !filled.0.upload.actionPlate.isHiddenOrHasHiddenAncestor, "with a destination the lone plate is hidden and the four-command plate shows")
    }

    private static func captionInside(_ tab: UploadSettingsTab) -> Bool {
        tab.view.layoutSubtreeIfNeeded()
        guard let caption = descendants(tab.view).compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == "Uploads go to the default destination. Right-click Upload to switch." }) else { return false }
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
            let add = tab.addButton.convert(tab.addButton.bounds, to: tab.view)
            expect(tab.view.bounds.contains(add), "\(label): the Add… button row is visible")
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

    /// The real coordinator: the editor attaches to the Settings window as a sheet, the list refreshes when it ends, a save closes it, and the
    /// shutdown barrier still runs.
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
        var actions = SettingsDestinationActions()
        actions.edit = { publisher.showEditor(editing: $0, relativeTo: $1) }
        actions.makeDefault = { try publisher.setDefaultDestination($0) }
        actions.remove = { try publisher.removeDestination($0) }
        let controller = SettingsWindowController(state: { initialState }, hotkeys: GlobalHotkeyManager(defaults: defaults, backend: FakeHotkeyBackend()), defaults: defaults,
                                                  destinations: { publisher.destinations() }, destinationActions: actions)
        controller.visibleFrame = { fakeVisible }
        var closes = 0
        controller.onClose = { closes += 1 }
        controller.select(3)
        controller.upload.refresh()
        expect(controller.upload.listedNames == ["Work"], "the tab reads the coordinator's saved list: \(controller.upload.listedNames)")
        controller.upload.addButton.performClick(nil)
        guard let sheet = controller.window.attachedSheet else { return expect(false, "the editor sheet did not attach to the Settings window") }
        expect(sheet.title == "Add Destination" && publisher.destinationsView?.editing == nil, "Add… opens the editor for a new destination: '\(sheet.title)'")
        controller.window.cancelOperation(nil)
        expect(closes == 0 && controller.window.attachedSheet === sheet, "Escape on the Settings window leaves its sheet alone")
        // Adding a destination while the editor is open shows up in the list as soon as the sheet ends.
        let second = PublishingDestination(name: "Backup", settings: dav)
        try? publisher.store.save(second, password: "")
        publisher.cancelSettings()
        spin(2) { controller.window.attachedSheet == nil && controller.upload.listedNames.count == 2 }
        expect(controller.window.attachedSheet == nil, "closing the sheet detaches it")
        expect(controller.upload.listedNames == ["Work", "Backup"], "the list refreshes when the sheet ends: \(controller.upload.listedNames)")

        // Edit opens the selected destination; Make Default and Remove go through the coordinator and the list follows.
        controller.upload.select(id: second.id)
        controller.upload.editButton.performClick(nil)
        expect(controller.window.attachedSheet?.title == "Edit Destination" && publisher.destinationsView?.editing?.name == "Backup" && publisher.destinationsView?.nameField.stringValue == "Backup", "Edit… opens the selected destination")
        publisher.cancelSettings(); spin(2) { controller.window.attachedSheet == nil }
        controller.upload.defaultButton.performClick(nil)
        expect(publisher.destinations().defaultID == second.id && controller.upload.rows[1].pill != nil && controller.upload.rows[0].pill == nil, "Make Default stores the choice and the pill follows")
        var shown: [AppAlert] = []
        AppAlert.presenter = { alert, _, _ in shown.append(alert) }
        defer { AppAlert.presenter = nil }
        controller.upload.select(id: first.id)
        controller.upload.removeButton.performClick(nil)
        shown.last?.dismiss(withButton: 1)
        expect(publisher.destinations().destinations.map(\.name) == ["Backup"] && controller.upload.listedNames == ["Backup"], "Remove removes it from storage and from the list")

        // The shutdown barrier with the Settings window as the sheet's parent.
        controller.upload.addButton.performClick(nil)
        expect(controller.window.attachedSheet != nil, "the editor opens again")
        var acknowledged = false
        publisher.shutdown { acknowledged = true }
        spin(5) { acknowledged && controller.window.attachedSheet == nil }
        expect(acknowledged, "shutdown acknowledged with the editor sheet attached to Settings")
        expect(controller.window.attachedSheet == nil, "shutdown dismissed the sheet from the Settings window")
        controller.upload.addButton.performClick(nil)
        expect(controller.window.attachedSheet == nil, "no sheet opens after shutdown")
        TestDefaults.dispose(defaults, name: name)
    }

    /// R1-017: while the Capture tab is open the shortcuts are paused; leaving the tab or hiding the window lets them go live again.
    private static func shortcutPause() {
        let (controller, _, manager, backend, _, _) = makeController()
        try? manager.install(globalScreen: {}, globalWindow: {}, globalFullscreen: {}, globalFrame: {}, globalUpload: {}, globalShow: {})
        var custom = GlobalHotkeySettings(); custom.screen = .init(keyCode: UInt32(GlobalHotkeyKeys.choices.first { $0.name == "K" }!.code), modifiers: .command)
        try? manager.apply(custom)
        expect(backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil && !manager.editing, "a saved shortcut is live while Settings is closed")
        controller.show(tab: SettingsWindowController.captureTabIndex)
        controller.activityChanged(key: false, appActive: false)
        // F-J7-004: the Capture note says whether the shortcuts are paused, to the eye and to VoiceOver, and always agrees with the manager.
        func note() -> String { controller.capture.hotkeyForm.statusField.stringValue }
        func agrees(_ what: String) {
            let paused = manager.editing
            let field = controller.capture.hotkeyForm.statusField
            expect(note() == (paused ? GlobalHotkeyForm.pausedStatus : GlobalHotkeyForm.idleLiveStatus) && (field.accessibilityValue() as? String) == note() && controller.capture.hotkeyForm.shortcutsPaused == paused,
                   "\(what): the note and its accessibility value say \(paused ? "paused" : "not paused") like the manager (\(note()))")
        }
        expect(!manager.editing && backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil, "Settings merely shown on Capture, behind another window or app, pauses nothing (R2-001)")
        agrees("shown, not key")
        controller.activityChanged(key: true, appActive: true)
        expect(manager.editing && backend.bindings.isEmpty, "Settings key and the app active on Capture pauses every shortcut")
        agrees("key and active")
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: controller.window))
        expect(!manager.editing && backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil, "another window becoming key puts them back")
        agrees("resigned key")
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: controller.window))
        controller.activityChanged(key: true, appActive: true)
        expect(manager.editing, "key again pauses again")
        agrees("key again")
        controller.activityChanged(appActive: false)
        expect(!manager.editing && backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil, "the app resigning active puts them back")
        agrees("app deactivated")
        controller.activityChanged(key: true, appActive: true)
        controller.select(0)
        expect(!manager.editing && backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil, "switching to another tab lets them go live again")
        agrees("other tab")
        controller.select(SettingsWindowController.captureTabIndex)
        expect(manager.editing && backend.bindings.isEmpty, "coming back to Capture pauses them again")
        agrees("back on Capture")
        // An error keeps the line until an edit is accepted; the pause state is still tracked underneath it.
        let form = controller.capture.hotkeyForm!
        let key = form.keyPopup(for: .window), other = form.keyPopup(for: .fullscreen)
        other.selectItem(at: 1); _ = other.target?.perform(other.action, with: other)
        key.selectItem(at: 1); _ = key.target?.perform(key.action, with: key)
        expect(note().hasPrefix("Error: "), "two actions on one key put an error on the note (\(note()))")
        controller.activityChanged(key: false)
        expect(note().hasPrefix("Error: ") && !controller.capture.hotkeyForm.shortcutsPaused, "an error is not overwritten by the pause note when focus leaves, and the pause state is still tracked")
        other.selectItem(at: 0); _ = other.target?.perform(other.action, with: other)
        key.selectItem(at: 0); _ = key.target?.perform(key.action, with: key)
        controller.activityChanged(key: true, appActive: true)
        agrees("after edits")
        controller.windowHidden()
        expect(!manager.editing && backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil, "hiding the window resumes them")
        agrees("hidden")
        controller.window.orderOut(nil)
    }

    /// R3-008: the real application notification drives the pause, and a failure to put the shortcuts back reaches the note.
    private static func shortcutPauseFailureAndNotification() {
        let (controller, _, manager, backend, _, _) = makeController()
        try? manager.install(globalScreen: {}, globalWindow: {}, globalFullscreen: {}, globalFrame: {}, globalUpload: {}, globalShow: {})
        var custom = GlobalHotkeySettings(); custom.screen = .init(keyCode: UInt32(GlobalHotkeyKeys.choices.first { $0.name == "K" }!.code), modifiers: .command)
        try? manager.apply(custom)
        let form = { controller.capture.hotkeyForm! }
        func note() -> String { form().statusField.stringValue }
        controller.show(tab: SettingsWindowController.captureTabIndex)
        controller.activityChanged(key: true, appActive: true)
        expect(manager.editing && note() == GlobalHotkeyForm.pausedStatus, "key and active on Capture: paused (\(note()))")
        // The observer wiring itself: the notification AppKit posts, not the controller's own entry point.
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
        spin(2) { !manager.editing }
        expect(!manager.editing && backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil && note() == GlobalHotkeyForm.idleLiveStatus,
               "the real did-resign-active notification puts the shortcuts back and the note follows (\(note()))")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        controller.activityChanged(key: true)
        spin(2) { manager.editing }
        expect(manager.editing, "did-become-active with the window key pauses again")
        // Putting them back fails: the note says so, to the eye and to VoiceOver, instead of promising they are saved and live.
        backend.failRegister = true
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
        spin(2) { !manager.editing }
        expect(!manager.editing && manager.lastError != nil, "the manager could not re-register (\(String(describing: manager.lastError)))")
        expect(note().hasPrefix("Error: ") && note().contains("already taken") && (form().statusField.accessibilityValue() as? String) == note(),
               "the note and its accessibility value carry the manager's error when the pause lifts (\(note()))")
        expect(form().statusField.textColor == DesignTokens.Palette.feedbackError, "…in the error colour")
        // R4: the real Carbon status reads as words on the note, with the call and the raw status kept on the help, not as "OSStatus -9878".
        backend.failRegister = false
        backend.failRegisterStatus = OSStatus(eventHotKeyExistsErr)
        controller.activityChanged(key: true, appActive: true)
        controller.activityChanged(key: false)
        let screenName = (manager.settings.screen).displayName
        expect(note() == "Error: \(screenName) is already used by another app. Choose a different shortcut." && !note().contains("OSStatus") && !note().contains("RegisterEventHotKey"),
               "an exclusive-key conflict reads in plain words (\(note()))")
        expect(form().statusField.accessibilityHelp()?.contains("RegisterEventHotKey for \(screenName) failed (OSStatus -9878)") == true,
               "…and the raw call and status ride on the spoken help (\(String(describing: form().statusField.accessibilityHelp())))")
        backend.failRegisterStatus = OSStatus(eventHotKeyInvalidErr)
        controller.activityChanged(key: true, appActive: true)
        controller.activityChanged(key: false)
        expect(note() == "Error: macOS cannot register \(screenName). Choose a different shortcut.", "an invalid-key status reads in words too (\(note()))")
        expect(carbonHotkeyFailure("Op", -50).localizedDescription == "Op failed (OSStatus -50)." && carbonHotkeyFailure("Op", -50).hotkeyTechnicalDetail == "Op failed (OSStatus -50).",
               "a status with no plain-word copy keeps the raw message")
        // Once the key is free the next pause and release restores the plain note.
        backend.failRegisterStatus = nil
        controller.activityChanged(key: true, appActive: true)
        controller.activityChanged(key: false)
        expect(!manager.editing && manager.lastError == nil && note() == GlobalHotkeyForm.idleLiveStatus, "a later successful release clears the error from the note (\(note()))")
        controller.windowHidden()
        controller.window.orderOut(nil)
    }

    /// R1-018: the current tab's non-colour cue follows Differentiate Without Color while the window is up, not only when the tab is next selected.
    private static func liveDifferentiateOutline() {
        let (controller, _, _, _, _, _) = makeController()
        let tab = controller.strip.buttons[0]
        DisplayOptions.override = DisplayOptions.none
        defer { DisplayOptions.override = nil }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        tab.setCurrent(true)
        expect(tab.layer?.borderWidth == 1 && !tab.showsIndicator, "the current tab has a 1 pt accent edge and no capsule by default (\(tab.layer?.borderWidth ?? -1))")
        DisplayOptions.override = DisplayOptions(differentiateWithoutColor: true)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(tab.showsIndicator && !tab.indicatorLayer.isHidden, "turning Differentiate Without Color on adds the capsule at once, with no tab change")
        DisplayOptions.override = DisplayOptions.none
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(!tab.showsIndicator && tab.indicatorLayer.isHidden, "and turning it off takes the capsule away")
    }

    /// F-R-003: the selected destination row has a cue that is not hue under Differentiate Without Color (a 2 pt edge in the text colour and
    /// a check ahead of the name), measured on drawn pixels, and it follows the option while the window is up.
    private static func liveDifferentiateRow() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 2))
        controller.select(3)
        let tab = controller.upload
        _ = tab.view
        tab.refresh()
        controller.window.contentView?.layoutSubtreeIfNeeded()
        DisplayOptions.override = DisplayOptions.none
        defer { DisplayOptions.override = nil }
        let selected = tab.rows[1], other = tab.rows[0]
        expect(selected.isSelected && !other.isSelected, "the default destination starts selected")

        /// The edge pixel and an interior pixel of the row as drawn, in sRGB, for one appearance.
        func drawn(_ name: NSAppearance.Name) -> (edge: DesignTokens.Palette.RGB, inside: DesignTokens.Palette.RGB, border: CGFloat) {
            let appearance = NSAppearance(named: name)!
            selected.appearance = appearance
            appearance.performAsCurrentDrawingAppearance { selected.updateLayer() }
            let scale: CGFloat = 2, width = Int(selected.bounds.width * scale), height = Int(selected.bounds.height * scale)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // The row sits on the list surface, so its translucent fill is judged over that, not over nothing.
            context.setFillColor(DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.content, for: appearance).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            appearance.performAsCurrentDrawingAppearance { selected.layer?.render(in: context) }
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            func pixel(_ x: Int, _ y: Int) -> DesignTokens.Palette.RGB {
                let offset = (y * width + x) * 4
                return .init(red: CGFloat(data[offset]) / 255, green: CGFloat(data[offset + 1]) / 255, blue: CGFloat(data[offset + 2]) / 255)
            }
            return (pixel(1, height / 2), pixel(Int(6 * scale), height / 2), selected.layer?.borderWidth ?? -1)
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let plain = drawn(name)
            let plainRatio = DesignTokens.Palette.contrastRatio(plain.edge, plain.inside)
            // Light only: the accent edge is 1.95:1 there (the finding), while dark already reads at 6:1 or better.
            expect(plain.border == 1 && (name == .darkAqua || plainRatio < 3) && selected.selectionMark.isHidden, "\(name.rawValue): by default the selected row is a 1 pt accent edge (\(plainRatio):1 against its fill) and no bar")
        }
        DisplayOptions.override = DisplayOptions(differentiateWithoutColor: true)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(!selected.selectionMark.isHidden && selected.selectionMark.alphaValue == 1 && selected.selectionMark.intrinsicContentSize == SettingsSelectionBar.size, "turning the option on shows the bar on the selected row at once")
        expect(!other.selectionMark.isHidden && other.selectionMark.alphaValue == 0, "an unselected row keeps the slot, empty, so the names stay aligned")
        expect(selected.selectionMark.subviews.isEmpty && !(selected.selectionMark is NSImageView), "the selection mark is a bar, never a check glyph like the Default pill's")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let marked = drawn(name)
            let ratio = DesignTokens.Palette.contrastRatio(marked.edge, marked.inside)
            expect(marked.border == 2 && ratio >= 3, "\(name.rawValue): under Differentiate Without Color the selected row's edge is 2 pt and \(ratio):1 against the row (needs 3:1)")
        }
        tab.rows[0].onClick?(1)
        expect(other.selectionMark.alphaValue == 1 && selected.selectionMark.alphaValue == 0, "the bar follows the selection")
        tab.rows[1].onClick?(1)
        DisplayOptions.override = DisplayOptions.none
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(selected.selectionMark.isHidden && other.selectionMark.isHidden, "turning the option off takes the bar and its slot away again")
        selected.appearance = NSAppearance(named: .aqua)
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { selected.updateLayer() }
        expect(selected.layer?.borderWidth == 1, "and the edge returns to 1 pt")
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
        expect(strings.contains("Add…") && strings.contains("Make Default") && strings.contains("Show capture flash") && strings.contains("Holding Option reverses the setting."), "the walk saw the real strings")
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
