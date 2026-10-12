// The Settings window, built standalone with in-memory stand-ins for everything the app owns. No window is ordered onto the
// desktop, no hotkey is registered with the system, no defaults domain is opened, no network, Keychain or real store is read.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D SETTINGS_WINDOW_TESTS \
//   Sources/SettingsWindow.swift Sources/GeneralPreferencesState.swift Sources/GlobalHotkeys.swift Sources/AppToolTip.swift \
//   Sources/DesignTokens.swift Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift Sources/FontAwesomeFree.swift \
//   Sources/SVGPath.swift Sources/StrokeFitting.swift Sources/DisplayOptions.swift Sources/DisplayOptions+ChromeAccessibility.swift \
//   Sources/OriginalActionButton.swift Sources/StateStyles.swift Sources/GlassChrome.swift Sources/GlassChoices.swift \
//   Sources/OriginalCaptureFlash.swift Sources/AppAlert.swift Sources/Publishing.swift Sources/PublishingS3.swift \
//   Sources/PublishingDestinations.swift Sources/PublishingDestinationsView.swift \
//   tests/TestDefaults.swift tests/ViewTreeAudit.swift tests/ContrastProbe.swift tests/SettingsWindowTests.swift -o build/settings-window-tests
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

/// A shortcut manager that only records: whether the editor is up (`setEditing`), and a rule that refuses a key with no Command or Control, so a
/// rejected draft can be made. Re-registering on `setEditing(false)` clears a stale error, as the real manager does.
@MainActor
private final class RecordingHotkeys: GlobalHotkeyEditing {
    var settings = GlobalHotkeySettings()
    var lastError: Error?
    var editingLog: [Bool] = []
    var editing: Bool { editingLog.last ?? false }
    func apply(_ candidate: GlobalHotkeySettings) throws {
        for action in GlobalHotkeyAction.allCases {
            let binding = candidate[action]
            if binding.keyCode != nil, binding.modifiers.isDisjoint(with: [.command, .control]) {
                let error = NSError(domain: "RecordingHotkeys", code: 1, userInfo: [NSLocalizedDescriptionKey: "A shortcut needs Command or Control."])
                lastError = error; throw error
            }
        }
        settings = candidate; lastError = nil
    }
    func setEditing(_ value: Bool) { editingLog.append(value); if !value { lastError = nil } }
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
    /// What AppKit puts on every real arrow key: it reports the function and numeric-pad flags with no modifier held.
    private static let realArrowFlags: NSEvent.ModifierFlags = [.numericPad, .function]
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
        sheetNeverLargerThanParent()
        alignmentAndTypography()
        preferenceControls()
        radioGroups()
        toggles()
        glassStructure()
        rowBaselines()
        flash()
        shortcuts()
        shortcutForm()
        modifierKeyboard()
        modifierGlyphs()
        modifierLabelsFit()
        realKeyFlags()
        keyPanelKeepsEditing()
        upload()
        uploadActionPlates()
        uploadWithPublishing()
        shortcutPause()
        shortcutPauseFailureAndNotification()
        liveDifferentiateOutline()
        liveDifferentiateRow()
        words()
        viewTreeAudit()
        externalTree()
        print("SettingsWindowTests: \(checks) checks passed (standalone controller; no window ordered onto the desktop)")
    }

    // MARK: What an external client sees

    /// The tree the AX server publishes, walked from the window down: the glass plates' controls reach assistive technology (a labelled plate
    /// used to answer with no children, and a choice on an unlabelled plate was dropped), with names, roles, values and a coherent parent chain.
    private static func externalTree() {
        let list = sampleDestinations(count: 2)
        let (controller, _, _, _, _, _) = makeController(destinations: list)
        let window = controller.window
        func reached(_ tree: AXTree.Tree, _ role: NSAccessibility.Role, _ label: String, _ what: String) -> AXTree.Node? {
            let node = tree.find(role, label)
            expect(node != nil, "\(what): \(role.rawValue) \"\(label)\" is reachable from the window. Tree:\n\(tree.outline)")
            return node
        }
        func children(_ tree: AXTree.Tree, _ group: AXTree.Node) -> [String] { tree.children(of: group).map { $0.label ?? "" } }

        // General: Show in radios, the Snapping plate (one toggle) and the Hints plate (two).
        controller.select(0)
        window.contentView?.layoutSubtreeIfNeeded()
        var tree = AXTree.walk(window)
        if let showIn = reached(tree, .radioGroup, "Show in", "General") {
            expect(tree.children(of: showIn).count == 3 && tree.children(of: showIn).allSatisfy { $0.role == .radioButton }, "Show in holds its three radio buttons")
        }
        if let snapping = reached(tree, .group, "Snapping", "General") {
            expect(tree.children(of: snapping).count == 1 && tree.children(of: snapping)[0].role == .checkBox, "the Snapping plate shows its toggle (it used to be an empty group): \(children(tree, snapping))")
            expect(tree.children(of: snapping).first?.number == (general(controller).snapCheckbox.isChosen ? 1 : 0), "the snap toggle's value is its state")
        }
        if let hints = reached(tree, .group, "Hints", "General") {
            let kids = tree.children(of: hints)
            expect(kids.count == 2 && kids.allSatisfy { $0.role == .checkBox } && kids.compactMap { $0.number } == [general(controller).hoverHintsCheckbox.isChosen ? 1 : 0, general(controller).keyboardTipsCheckbox.isChosen ? 1 : 0] && kids.map { $0.label ?? "" } == [general(controller).hoverHintsCheckbox.title, general(controller).keyboardTipsCheckbox.title],
                   "the Hints plate shows its two toggles in order, with their values: \(kids.map { "\($0.label ?? "") \(String(describing: $0.value))" })")
            if let first = kids.first {
                let toggle = general(controller).hoverHintsCheckbox!
                let before = toggle.isChosen
                expect(AXTree.press(first) && toggle.isChosen != before, "AXPress on a toggle reached from the window flips it")
                _ = AXTree.press(first)
            }
        }
        expect(tree.parentProblems().isEmpty, "General: every parent agrees with the tree: \(tree.parentProblems().prefix(3))")
        expect(tree.shapeProblems().isEmpty, "General: no AXUnknown wrapper, role-less node (\(tree.shapeProblems().count)): \(tree.shapeProblems().prefix(3))")

        // Capture: the enable toggle, a modifier group per shortcut and Clear All.
        controller.select(2)
        window.contentView?.layoutSubtreeIfNeeded()
        tree = AXTree.walk(window)
        if let shortcuts = reached(tree, .group, "Shortcuts", "Capture") {
            expect(tree.children(of: shortcuts).count == 1 && tree.children(of: shortcuts)[0].role == .checkBox, "the Shortcuts plate shows its enable toggle: \(children(tree, shortcuts))")
        }
        let rowGroups = tree.nodes.filter { $0.role == .group && ($0.label ?? "").hasSuffix(" shortcut") }
        expect(rowGroups.count >= 3, "each capture shortcut has a row plate (\(rowGroups.count))")
        for row in rowGroups {
            let kids = tree.descendants(of: row)
            expect(kids.contains { $0.role == .popUpButton } && kids.contains { $0.role == .group && ($0.label ?? "").hasSuffix(" modifiers") },
                   "\(row.label ?? ""): the key pop-up and the modifier group are inside its plate: \(kids.map { $0.role?.rawValue ?? "?" })")
        }
        if let modifiers = tree.nodes.first(where: { $0.role == .group && ($0.label ?? "").hasSuffix(" modifiers") }) {
            expect(tree.children(of: modifiers).count == 4 && tree.children(of: modifiers).allSatisfy { $0.role == .checkBox }, "a modifier group holds its four toggles")
        }
        if let clear = reached(tree, .group, "Clear shortcuts", "Capture") {
            expect(children(tree, clear) == ["Clear All"], "the Clear plate shows Clear All: \(children(tree, clear))")
        }
        expect(tree.parentProblems().isEmpty, "Capture: every parent agrees with the tree: \(tree.parentProblems().prefix(3))")
        expect(tree.shapeProblems().isEmpty, "Capture: no AXUnknown wrapper, role-less node (\(tree.shapeProblems().count)): \(tree.shapeProblems().prefix(3))")

        // Upload: the destination action plate.
        controller.select(3)
        let tab = controller.upload
        _ = tab.view; tab.refresh()
        window.contentView?.layoutSubtreeIfNeeded()
        tree = AXTree.walk(window)
        if let actions = reached(tree, .group, "Destination actions", "Upload") {
            let kids = tree.children(of: actions)
            expect(kids.count == 4 && kids.allSatisfy { $0.role == .button } && kids.map { $0.label ?? "" } == tab.actionPlate.arrangedViews.compactMap { ($0 as? NSButton)?.title },
                   "the action plate shows Add, Edit, Remove and Make Default in order: \(kids.map { $0.label ?? "" })")
            expect(kids.map { $0.enabled } == tab.actionPlate.arrangedViews.compactMap { ($0 as? NSButton)?.isEnabled }, "...and which of them is disabled")
        }
        expect(tree.parentProblems().isEmpty, "Upload: every parent agrees with the tree: \(tree.parentProblems().prefix(3))")
        expect(tree.shapeProblems().isEmpty, "Upload: no AXUnknown wrapper, role-less node (\(tree.shapeProblems().count)): \(tree.shapeProblems().prefix(3))")
    }

    private static func general(_ controller: SettingsWindowController) -> GeneralSettingsTab { controller.general }

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
        // Every control keeps the identifier it had, and each resolves to exactly one button in its own tab (or on the strip).
        let identifiers: [(tab: Int, ids: [String])] = [
            (0, ["presenceDock", "presenceMenuBar", "presenceBoth", "includeApp", "showToolTips", "showKeyboardTips"]),
            (1, ["precisionPrecise", "precisionMedium", "precisionLoose", "arrowEnd", "arrowStart"]),
            (2, ["showCaptureFlash"]),
            (3, ["addDestination", "editDestination", "removeDestination", "makeDefaultDestination", "addFirstDestination"])]
        for (index, group) in identifiers.enumerated() {
            controller.select(index)
            for id in group.ids { _ = button(id, in: controller.tabItems[index].viewController.view) }
        }
        for title in SettingsLayout.tabTitles { _ = button("settingsTab." + title, in: controller.strip) }
        controller.select(0)
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
        expect(!strip.showsKeyboardFocus && strip.focusRingType == .none && strip.tokenRing.layer.isHidden, "focus that arrives without a key press (the window opening) draws no ring")
        func arrow(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
            strip.keyDown(with: keyEvent(code == 123 ? "\u{F702}" : "\u{F703}", code: code, flags: flags.union(realArrowFlags), window: window))
        }
        arrow(124); expect(controller.selectedIndex == 1, "Right moves to Drawing")
        let ringTarget = strip.convert(strip.buttons[1].bounds, from: strip.buttons[1])
        expect(strip.showsKeyboardFocus && strip.focusRingType == .none && !strip.tokenRing.layer.isHidden && strip.tokenRing.target() == ringTarget,
               "an arrow key shows the token focus ring (not AppKit's), around the selected tab")
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

    /// Signoff: a sheet that hangs from Settings is never bigger than Settings. The window grows to hold it, and goes back when the sheet is gone.
    private static func sheetNeverLargerThanParent() {
        let (controller, _, _, _, _, _) = makeController()
        let window = controller.window
        let tall = NSRect(x: 0, y: 0, width: 1280, height: 1100)
        controller.visibleFrame = { tall }
        controller.select(3)
        controller.fit(animated: false)
        window.setFrameTopLeftPoint(NSPoint(x: 100, y: tall.maxY - 20))
        let before = window.frame
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        expect(sheet.frame.height > before.height, "the fixture sheet (\(sheet.frame.height) pt) is taller than the Settings window (\(before.height) pt)")
        window.beginSheet(sheet)
        let titleBar = window.frameRect(forContentRect: .zero).height
        expect(window.frame.height >= sheet.frame.height + titleBar - 0.5, "Settings grows to hold the sheet: window \(window.frame.height) pt, sheet \(sheet.frame.height) pt + \(titleBar) pt title bar")
        expect(abs(window.frame.maxY - before.maxY) < 0.5 && window.frame.minY >= tall.minY - 0.5, "the top edge stays put and the window stays on the screen (\(window.frame), was \(before))")
        // The destination form changes height as its protocol changes; the window follows the sheet.
        sheet.setContentSize(NSSize(width: 640, height: 500)); spin(0.05)
        expect(window.frame.height >= sheet.frame.height + titleBar - 0.5, "a sheet that resizes is still held (window \(window.frame.height), sheet \(sheet.frame.height))")
        // A tiny screen caps the window to the screen.
        controller.sheetDidEnd()
        expect(abs(window.frame.height - before.height) < 0.5 && abs(window.frame.width - before.width) < 0.5, "the window goes back to its tab's size once the sheet is gone (\(window.frame) vs \(before))")
        window.endSheet(sheet); sheet.orderOut(nil)
        controller.sheetDidEnd()
        controller.visibleFrame = { NSRect(x: 0, y: 0, width: 1280, height: 420) }
        controller.sheetWillBegin(sheet)
        expect(window.frame.height <= 420 + 0.5, "on a short screen the window is capped to it (\(window.frame.height))")
        controller.sheetDidEnd()
    }

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
                // Ink is what is seen: the labels, the plates and the other controls (a choice inside a plate is inset by the plate, which is the shape drawn).
                let ink = descendants(tab).filter { (($0 is NSControl && !($0 is GlassChoiceButton)) || $0 is GlassSurfaceView) && !$0.isHidden && $0.bounds.width > 0 }
                    .map { alignment(of: $0, in: tab) }.reduce(NSRect.null) { $0.union($1) }
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
                let box = alignment(of: form.enabledPlate, in: tab)
                expect(abs(box.minX - controlColumn) < 1.5, "Capture: the embedded Enable plate starts at the control column (\(box.minX) vs \(controlColumn))")
            }
        }
        // The Capture tab's shortcut rows sit in the same label column as the rows above them.
        controller.select(2)
        let tab = controller.capture.view
        let flashLabel = descendants(tab).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Flash:" }!
        let screenLabel = descendants(tab).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Screen region:" }!
        expect(abs(frame(of: flashLabel, in: tab).maxX - frame(of: screenLabel, in: tab).maxX) < 0.5, "the embedded shortcut rows line up with the Flash row")
        let flashBox = alignment(of: controller.capture.flashPlate, in: tab)
        let popupBox = alignment(of: controller.capture.hotkeyForm.rowPlate(for: .screen), in: tab)
        expect(abs(flashBox.minX - popupBox.minX) < 1.5, "the Flash plate and the shortcut rows share the control column: \(flashBox.minX) vs \(popupBox.minX)")
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

    /// A choice's label is drawn whole: its frame is at least what the text field itself says it needs (the text plus the cell's own padding),
    /// and a wrapped label has the height of every line at the width it was given. A label cut short ends in an ellipsis or loses its last line.
    private static func labelIsWhole(_ button: GlassChoiceButton) -> Bool {
        let label = button.titleLabel
        guard label.frame.width > 0 else { return false }
        if button.wrapWidth == nil { return label.fittingSize.width <= label.frame.width + 0.01 && label.fittingSize.height <= label.frame.height + 0.01 }
        let kept = label.preferredMaxLayoutWidth
        label.preferredMaxLayoutWidth = label.frame.width
        defer { label.preferredMaxLayoutWidth = kept }
        return label.fittingSize.height <= label.frame.height + 0.01
    }

    // MARK: Radio sets

    private static func arrowEvent(_ code: UInt16, window: NSWindow) -> NSEvent {
        keyEvent(code == 123 ? "\u{F702}" : (code == 124 ? "\u{F703}" : (code == 125 ? "\u{F701}" : "\u{F700}")), code: code, flags: realArrowFlags, window: window)
    }
    private static func chosen(_ group: GlassChoiceGroup) -> [Int] { group.buttons.filter { $0.state == .on }.map(\.tag) }

    /// Presence, Precision and Arrow head are radio sets, each on ONE plate: a click or an arrow key changes the stored preference once,
    /// the choice is a glyph and a fill and a weight, and each set is one tab stop.
    private static func radioGroups() {
        var current = initialState
        let (controller, _, _, _, _, _) = makeController(state: current)
        var delivered: [GeneralPreferencesState] = []
        controller.onChange = { delivered.append($0); current = $0 }
        let window = controller.window
        let saved = KeyboardNavigation.fullKeyboardAccess
        KeyboardNavigation.fullKeyboardAccess = { true }
        defer { KeyboardNavigation.fullKeyboardAccess = saved }

        func check(_ name: String, tab: Int, group: GlassChoiceGroup, identifiers: [String], titles: [String], tags: [Int], label: String) {
            controller.select(tab)
            window.contentView?.layoutSubtreeIfNeeded()
            expect(group.buttons.map { $0.identifier?.rawValue ?? "" } == identifiers, "\(name): the identifiers stay on the buttons: \(group.buttons.map { $0.identifier?.rawValue ?? "" })")
            expect(group.buttons.map(\.title) == titles && group.buttons.map(\.tag) == tags, "\(name): titles and stored values are unchanged")
            expect(group.buttons.allSatisfy { $0.kind == .option && $0.indicator == .radio && $0.markImage != nil && $0.showsMark }, "\(name): every choice is an option with a radio glyph")
            expect(plates(in: group).count == 1 && group.plate.arrangedViews.count == titles.count && group.plate.axis == .horizontal && group.plate.tintColor == nil, "\(name): the set is ONE untinted horizontal plate")
            expect(group.buttons.allSatisfy { $0.titleLabel.font?.pointSize == 20 && $0.frame.height == GlassChoiceButton.height }, "\(name): each choice is a 20 pt label in a control-high button")
            expect(group.buttons.allSatisfy { labelIsWhole($0) }, "\(name): no choice label is cut short: \(group.buttons.map { "\($0.title) \($0.titleLabel.frame.width) of \($0.titleLabel.fittingSize.width)" })")
            expect(group.accessibilityRole() == .radioGroup && group.accessibilityLabel() == label, "\(name): VoiceOver gets a radio group named '\(label)'")
            expect(group.buttons.allSatisfy { $0.accessibilityRole() == .radioButton && $0.accessibilityLabel() == $0.title }, "\(name): every choice is a radio button with its own name")
            let on = group.buttons.filter { $0.accessibilityValue() as? NSNumber == 1 }
            expect(on.count == 1 && on[0].isAccessibilitySelected() && group.accessibilityValue() as? String == on[0].title, "\(name): exactly one radio reports 1, and the group's value is its name")
            // The choice is not colour alone: a filled glyph, an accent fill with its border, and the semibold face.
            let chosenButton = on[0], others = group.buttons.filter { $0 !== chosenButton }
            expect(chosenButton.markImage !== others[0].markImage && chosenButton.plate.stateStyle.strongText && chosenButton.plate.stateStyle.fill != nil && chosenButton.plate.stateStyle.borderWidth == 1
                   && chosenButton.titleLabel.font == DesignTokens.Typography.font(.bodyStrong), "\(name): the choice has its own glyph, fill, border and semibold face")
            expect(others.allSatisfy { $0.titleLabel.font == DesignTokens.Typography.font(.body) && $0.plate.stateStyle.fill == nil && $0.plate.stateStyle.borderWidth == 0 }, "\(name): the others rest bare in the regular face")
            // OSN-071 r4 (S56): the ring of the segment at either end stood on the plate's edge (the plate's 4 pt inset is exactly the ring's 4 pt reach).
            // Like a toggle row, the ring must stand off the plate: more than its reach between each end button and the plate's edge.
            let reach = StateStyles.focusRingOutset + StateStyles.focusRingWidth
            if let first = group.buttons.first, let last = group.buttons.last {
                let plateFrame = group.plate.bounds
                let leading = first.convert(first.bounds, to: group.plate).minX - plateFrame.minX
                let trailing = plateFrame.maxX - last.convert(last.bounds, to: group.plate).maxX
                let top = abs(plateFrame.maxY - first.convert(first.bounds, to: group.plate).maxY), bottom = abs(first.convert(first.bounds, to: group.plate).minY - plateFrame.minY)
                expect(min(leading, trailing, top, bottom) > reach, "\(name): the focus ring (\(reach) pt out) stands off the plate's edge: gaps \(leading), \(trailing), \(top), \(bottom)")
            }
            // One tab stop per set: the chosen button, and only it.
            let stops = group.buttons.filter(\.canBecomeKeyView)
            expect(stops.count == 1 && stops[0] === chosenButton, "\(name): the set is one tab stop, on the chosen choice (\(stops.map(\.title)))")
        }
        let general = controller.general, drawing = controller.drawing
        check("Show in", tab: 0, group: general.presenceGroup, identifiers: ["presenceDock", "presenceMenuBar", "presenceBoth"], titles: ["Dock", "Menu bar", "Both"], tags: [2, 1, 0], label: "Show in")
        check("Drawing precision", tab: 1, group: drawing.precisionGroup, identifiers: ["precisionPrecise", "precisionMedium", "precisionLoose"], titles: ["Precise", "Medium", "Loose"], tags: [0, 1, 2], label: "Drawing precision")
        check("Arrow head", tab: 1, group: drawing.arrowGroup, identifiers: ["arrowEnd", "arrowStart"], titles: ["End", "Start"], tags: [2, 1], label: "Arrow head")

        // A click chooses it and stores it, once; clicking the chosen one again stores nothing.
        controller.select(0)
        var count = delivered.count
        general.presenceGroup.buttons[0].performClick(nil)
        expect(delivered.count == count + 1 && delivered.last?.statusMenu == 2 && chosen(general.presenceGroup) == [2], "clicking Dock stores Dock once (\(delivered.count - count) edits)")
        general.presenceGroup.buttons[0].performClick(nil)
        expect(delivered.count == count + 1 && chosen(general.presenceGroup) == [2], "clicking the chosen choice again stores nothing")
        // Arrow keys move the choice and the stored value, one edit per step, and stop at the ends.
        controller.select(1)
        window.contentView?.layoutSubtreeIfNeeded()
        let precision = drawing.precisionGroup!
        expect(window.makeFirstResponder(precision.buttons[1]) && window.firstResponder === precision.buttons[1], "the chosen precision can take the keyboard")
        count = delivered.count
        precision.buttons[1].keyDown(with: arrowEvent(124, window: window))
        expect(delivered.count == count + 1 && delivered.last?.drawingPrecision == .loose && chosen(precision) == [2] && window.firstResponder === precision.buttons[2],
               "Right moves to Loose, stores it once and takes the focus with it")
        precision.buttons[2].keyDown(with: arrowEvent(124, window: window))
        expect(delivered.count == count + 1 && chosen(precision) == [2], "Right stops at the last choice and stores nothing")
        precision.buttons[2].keyDown(with: arrowEvent(123, window: window)); precision.buttons[1].keyDown(with: arrowEvent(123, window: window))
        expect(delivered.count == count + 3 && delivered.last?.drawingPrecision == .precise && chosen(precision) == [0], "Left walks back to Precise, one edit a step")
        precision.buttons[0].keyDown(with: arrowEvent(126, window: window))
        expect(delivered.count == count + 3 && chosen(precision) == [0], "Up at the first choice stores nothing")
        precision.buttons[0].keyDown(with: arrowEvent(125, window: window))
        expect(delivered.last?.drawingPrecision == .medium && chosen(precision) == [1], "Down moves on like Right")
        // Space chooses the focused choice.
        let arrow = drawing.arrowGroup!
        expect(window.makeFirstResponder(arrow.buttons[0]), "the chosen arrow head can take the keyboard")
        arrow.buttons[0].keyDown(with: arrowEvent(124, window: window))
        expect(delivered.last?.arrowHead == 1 && chosen(arrow) == [1], "Right chooses Start")
        // Stored values that came from outside move the set without an edit (a menu command).
        count = delivered.count
        controller.synchronize(GeneralPreferencesState(drawingPrecision: .loose, arrowHead: 2, includeApp: true, statusMenu: 1))
        expect(delivered.count == count && chosen(precision) == [2] && chosen(arrow) == [2] && chosen(general.presenceGroup) == [1], "a synchronize moves the sets and sends nothing")
        // The only tab stop moves with the choice.
        expect(precision.buttons.filter(\.canBecomeKeyView).map(\.tag) == [2], "the tab stop follows the choice")
        // The tab's key-view loop passes through each set once.
        controller.select(0)
        window.contentView?.layoutSubtreeIfNeeded()
        window.recalculateKeyViewLoop()
        var seen: [NSView] = [], view: NSView? = controller.strip
        for _ in 0..<30 { view = view?.nextValidKeyView; guard let next = view, next !== controller.strip else { break }; seen.append(next) }
        let titlesSeen = seen.compactMap { ($0 as? GlassChoiceButton)?.identifier?.rawValue }
        expect(titlesSeen.filter { $0.hasPrefix("presence") }.count == 1, "Tab passes through the Show in set once (\(titlesSeen))")
    }

    // MARK: Toggles

    private static func toggles() {
        var current = initialState
        let (controller, defaults, _, _, _, _) = makeController(state: current)
        var delivered: [GeneralPreferencesState] = []
        controller.onChange = { delivered.append($0); current = $0 }
        let window = controller.window
        let general = controller.general
        controller.select(0)
        window.contentView?.layoutSubtreeIfNeeded()
        let hover = general.hoverHintsCheckbox!, keys = general.keyboardTipsCheckbox!, snap = general.snapCheckbox!
        for (name, toggle, id) in [("hover hints", hover, "showToolTips"), ("keyboard tips", keys, "showKeyboardTips"), ("snap", snap, "includeApp")] {
            expect(toggle.kind == .toggle && toggle.indicator == .checkbox && toggle.identifier?.rawValue == id, "\(name): a checkbox toggle that keeps its identifier \(id)")
            expect(toggle.accessibilityRole() == .checkBox && toggle.accessibilityLabel() == toggle.title && toggle.titleLabel.font?.pointSize == 20, "\(name): VoiceOver gets a named check box and the label is 20 pt")
        }
        // Related toggles share one plate; the long snap sentence has its own.
        expect(general.hintsPlate.arrangedViews.count == 2 && general.hintsPlate.arrangedViews[0] === hover && general.hintsPlate.arrangedViews[1] === keys && general.hintsPlate.axis == .vertical,
               "the two hint options share one vertical plate")
        expect(general.snapPlate.arrangedViews.count == 1 && general.snapPlate.arrangedViews[0] === snap && general.snapPlate !== general.hintsPlate && plates(in: general.view).count == 3,
               "the snap option has its own plate, and the General tab has three: Show in, Snapping, Hints")
        expect(general.hintsPlate.accessibilityRole() == .group && general.hintsPlate.accessibilityLabel() == "Hints", "the plate is a named group")
        // OSN-071 r3: a toggle row is as wide as its plate, so its focus ring (outset + stroke = 4 pt) must stand clear of the plate's border (S56-settings-toggles-focus).
        let ringReach = StateStyles.focusRingOutset + StateStyles.focusRingWidth
        for (plateName, plate) in [("Snapping", general.snapPlate!), ("Hints", general.hintsPlate!)] {
            for toggle in plate.arrangedViews {
                let row = plate.convert(toggle.bounds, from: toggle)
                let clearance = min(row.minX - plate.bounds.minX, plate.bounds.maxX - row.maxX, row.minY - plate.bounds.minY, plate.bounds.maxY - row.maxY)
                expect(clearance >= ringReach + 1, "\(plateName): the focus ring (\(ringReach) pt) stands at least 1 pt clear of the plate border; the row has \(clearance) pt")
            }
        }
        expect([hover, keys, snap].allSatisfy { labelIsWhole($0) }, "no check box label is cut short, and the wrapped one keeps every line: \([hover, keys, snap].map { "\($0.title.prefix(12)) \($0.titleLabel.frame.size) needs \($0.titleLabel.fittingSize)" })")
        // The sentence wraps: two readable lines, wholly inside its row, the plate no wider than the control column.
        window.contentView?.layoutSubtreeIfNeeded()
        let lines = ceil(snap.titleLabel.frame.height / ceil(DesignTokens.Typography.font(.bodyStrong).boundingRectForFont.height))
        expect(snap.wrapWidth != nil && lines >= 2 && snap.bounds.insetBy(dx: -0.5, dy: -0.5).contains(snap.titleLabel.frame) && snap.frame.height > GlassChoiceButton.height,
               "the long sentence wraps onto \(lines) lines inside a taller row and nothing is cut: \(snap.titleLabel.frame) in \(snap.bounds)")
        expect(general.snapPlate.frame.width <= general.controlWidth + 0.5 && general.snapPlate.frame.maxX <= general.grid.bounds.maxX + 0.5, "the wrapped plate stays inside the control column (\(general.snapPlate.frame.width) of \(general.controlWidth))")
        expect(abs(general.hintsPlate.frame.width - general.snapPlate.frame.width) < 0.5, "a checked option is a chip as wide as the others: Hints \(general.hintsPlate.frame.width) pt, Snapping \(general.snapPlate.frame.width) pt")
        controller.select(2); window.contentView?.layoutSubtreeIfNeeded()
        let capture = controller.capture
        expect(abs(capture.flashPlate.frame.width - capture.hotkeyForm.enabledPlate.frame.width) < 0.5,
               "Flash and Shortcuts checkboxes sit on plates of one width: \(capture.flashPlate.frame.width) and \(capture.hotkeyForm.enabledPlate.frame.width) pt")
        controller.select(0); window.contentView?.layoutSubtreeIfNeeded()
        expect(snap.titleLabel.frame.width + 0.5 >= (snap.title as NSString).boundingRect(with: NSSize(width: snap.wrapWidth!, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin,
                                                                                         attributes: [.font: DesignTokens.Typography.font(.bodyStrong)]).width,
               "the label is as wide as the wrapped text needs")
        // Each click flips its own preference, once, with the complete state; the glyph changes with it.
        func click(_ toggle: GlassChoiceButton, _ edit: (inout GeneralPreferencesState) -> Void, _ name: String) {
            var expected = current; edit(&expected)
            let count = delivered.count, before = toggle.markImage, wasOn = toggle.state == .on
            toggle.performClick(nil)
            expect(delivered.count == count + 1 && delivered.last == expected, "\(name): one edit with the complete state (\(delivered.count - count) edits; \(String(describing: delivered.last)) vs \(expected))")
            expect((toggle.state == .on) == !wasOn && toggle.isChosen == !wasOn && toggle.accessibilityValue() as? NSNumber == (wasOn ? 0 : 1), "\(name): the check box now reads \(wasOn ? "off" : "on")")
            expect(toggle.markImage !== before && (toggle.titleLabel.font == DesignTokens.Typography.font(wasOn ? .body : .bodyStrong)), "\(name): the glyph and the weight changed with the state")
        }
        click(hover, { $0.showToolTips = true }, "hover hints on")
        click(hover, { $0.showToolTips = false }, "hover hints off")
        click(keys, { $0.showKeyboardTips = true }, "keyboard tips on")
        click(snap, { $0.includeApp = false }, "snap off")
        click(snap, { $0.includeApp = true }, "snap on")
        // A VoiceOver press on the check box flips it exactly as a click does.
        let count = delivered.count
        _ = hover.accessibilityPerformPress()
        expect(delivered.count == count + 1 && delivered.last?.showToolTips == true && hover.state == .on && hover.accessibilityValue() as? NSNumber == 1,
               "a VoiceOver press flips the check box once (\(delivered.count - count) edits)")
        // The flash toggle on the Capture tab persists its own key and nothing else.
        controller.select(2)
        let flash = controller.capture.flashCheckbox!
        expect(flash.kind == .toggle && flash.indicator == .checkbox && flash.accessibilityRole() == .checkBox && flash.identifier?.rawValue == "showCaptureFlash", "the flash option is a checkbox toggle")
        expect(controller.capture.flashPlate.arrangedViews.count == 1 && controller.capture.flashPlate.arrangedViews[0] === flash, "it sits on a plate of its own")
        flash.performClick(nil)
        expect(defaults.object(forKey: OriginalCaptureFlashTiming.showFlashKey) as? Bool == false && flash.state == .off && flash.accessibilityValue() as? NSNumber == 0, "clicking it stores false and it reads off")
        flash.performClick(nil)
        expect(defaults.object(forKey: OriginalCaptureFlashTiming.showFlashKey) as? Bool == true && flash.state == .on, "clicking again stores true and it reads on")
    }

    // MARK: Glass structure

    /// Every tab holds its plates in one container and no plate is inside another; the choices draw fills, never glass.
    private static func glassStructure() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 2))
        let expectedPlates = [3, 2, 9, 1]
        for index in controller.tabItems.indices {
            controller.select(index)
            let tab = controller.tabItems[index].viewController, name = controller.tabItems[index].label
            tab.view.layoutSubtreeIfNeeded()
            let visible = plates(in: tab.view).filter { !$0.isHiddenOrHasHiddenAncestor }
            expect(visible.count == expectedPlates[index], "\(name): \(expectedPlates[index]) plates, one per related group (found \(visible.count))")
            expect(nestedGlass(in: tab.view).isEmpty, "\(name): no glass view inside another")
            expect(tab.glassContainer.contentView === tab.grid && tab.glassContainer.superview === tab.view, "\(name): the plates share one container around the form")
            expect(visible.allSatisfy { $0.isDescendant(of: tab.glassContainer) && $0.tintColor == nil }, "\(name): every plate sits in that container and carries no tint")
            expect(descendants(tab.view).compactMap { $0 as? NSGlassEffectContainerView }.count == 1, "\(name): exactly one glass container")
        }
        // The destination list and the shortcut recorders stay solid and native.
        controller.select(3)
        expect(!descendants(controller.upload.listScroll).contains { $0 is NSGlassEffectView }, "the destination list is solid content")
        // The shortcut form is glass too: the enable box, one plate per action (key pop-up and four modifier toggles) and Clear All.
        controller.select(2)
        let form = controller.capture.hotkeyForm!
        let formPlates = plates(in: form)
        expect(formPlates.count == 8 && formPlates.contains { $0 === form.enabledPlate } && formPlates.contains { $0 === form.clearPlate } && form.rowPlates.count == 6 && form.rowPlates.allSatisfy { p in formPlates.contains { $0 === p } },
               "the form has eight plates: Shortcuts, six actions, Clear All (\(formPlates.count))")
        expect(GlobalHotkeyAction.allCases.allSatisfy { action in
            let plate = form.rowPlate(for: action)
            let group = form.modifierGroup(for: action)
            return plate.arrangedViews.count == 2 && plate.arrangedViews[0] is ChromeFillCell && plate.arrangedViews[1] === group && form.keyPopup(for: action).isDescendant(of: plate)
                && group.arrangedSubviews.count == 4 && zip(group.arrangedSubviews, form.modifierToggles(for: action)).allSatisfy { $0 === $1 }
        }, "each action's key and its four modifiers (grouped) share ONE plate, in order")
        expect(form.enabledPlate.arrangedViews.count == 1 && form.enabledPlate.arrangedViews[0] === form.enabledCheckbox && form.clearPlate.arrangedViews.count == 1 && form.clearPlate.arrangedViews[0] === form.clearButton,
               "the enable box and Clear All each have a plate of their own")
        expect(nestedGlass(in: form).isEmpty && !descendants(form).contains { $0 is NSSegmentedControl } && form.rowPlates.allSatisfy { $0.tintColor == nil }, "no glass inside glass, no segmented control left, no tint")
        // The display options reach every set and toggle while the window is up.
        defer { DisplayOptions.override = nil }
        controller.select(0)
        let general = controller.general
        DisplayOptions.override = DisplayOptions(reduceTransparency: true, increaseContrast: true, differentiateWithoutColor: true)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        let all: [GlassSurfaceView] = [general.presenceGroup.plate, general.snapPlate, general.hintsPlate]
        expect(all.allSatisfy { $0.transparencyPlate != nil && $0.showsContrastBorder }, "Reduce Transparency and Increase Contrast reach the General plates live")
        let chosenRadio = general.presenceGroup.buttons.first { $0.isChosen }!
        expect(chosenRadio.showsIndicator && general.snapCheckbox.showsIndicator, "Differentiate Without Color adds the capsule to the chosen radio and the checked box")
        expect(!general.hoverHintsCheckbox.showsIndicator, "an unchecked box stays bare")
        DisplayOptions.override = nil
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(all.allSatisfy { $0.transparencyPlate == nil } && !chosenRadio.showsIndicator, "and they go again with the options")
    }

    // MARK: Baselines

    /// A row's label sits on the same baseline as the first line of its choices, whatever the plate around them: measured from where the
    /// grid really put the label and where the button really put its text.
    private static func rowBaselines() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 1))
        // A text field is flipped: its baseline offset is measured down from the top edge, so the point is that far from the top in its own space.
        func baseline(_ field: NSTextField, in root: NSView) -> CGFloat {
            field.convert(NSPoint(x: 0, y: field.isFlipped ? field.firstBaselineOffsetFromTop : field.bounds.height - field.firstBaselineOffsetFromTop), to: root).y
        }
        let rows: [(tab: Int, label: String, first: () -> GlassChoiceButton?)] = [
            (0, "Show in:", { controller.general.presenceGroup.buttons.first }), (0, "Snapping:", { controller.general.snapCheckbox }),
            (0, "Hints:", { controller.general.hoverHintsCheckbox }), (1, "Drawing precision:", { controller.drawing.precisionGroup.buttons.first }),
            (1, "Arrow head:", { controller.drawing.arrowGroup.buttons.first }), (2, "Flash:", { controller.capture.flashCheckbox }),
            (2, "Shortcuts:", { controller.capture.hotkeyForm.enabledCheckbox }), (2, "Screen region:", { controller.capture.hotkeyForm.modifierToggles(for: .screen)[0] }),
            (2, "Show OpenSnap:", { controller.capture.hotkeyForm.modifierToggles(for: .show)[0] })]
        for row in rows {
            controller.select(row.tab)
            controller.window.contentView?.layoutSubtreeIfNeeded()
            let tab = controller.tabItems[row.tab].viewController.view
            guard let label = descendants(tab).compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == row.label }), let button = row.first() else {
                expect(false, "\(row.label): the label and its first choice were found"); continue
            }
            let delta = abs(baseline(label, in: tab) - baseline(button.titleLabel, in: tab))
            expect(delta <= 1.5, "\(row.label) shares a baseline with its first choice (off by \(delta) pt)")
        }
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
        let popup = form.keyPopup(for: .screen), modifiers = form.modifierToggles(for: .screen)
        let k = GlobalHotkeyKeys.choices.firstIndex { $0.name == "K" }! + 1
        func press(_ toggle: GlassChoiceButton) { toggle.performClick(nil) }
        func pick(_ popup: GlassPopUpButton, _ index: Int) { popup.selectItem(at: index); _ = popup.target?.perform(popup.action, with: popup) }
        expect(popup.indexOfSelectedItem == 0 && modifiers.allSatisfy { !$0.isEnabled && $0.state == .off }, "an action with no key starts at None with its modifiers off")
        pick(popup, k)
        expect(modifiers.allSatisfy(\.isEnabled), "choosing a key enables its modifiers")
        expect(manager.settings.screen == .none && form.statusField.stringValue.hasPrefix("Error: "), "a key without Command or Control is refused and said so: '\(form.statusField.stringValue)'")
        expect(hotkeySettings(defaults).screen == .none && backend.bindings.isEmpty, "the refused edit changed nothing stored or registered")
        press(modifiers[0])
        expect(manager.settings.screen == .init(keyCode: GlobalHotkeyKeys.choices[k - 1].code, modifiers: .command), "Command plus K reaches the GlobalHotkeys model: \(manager.settings.screen)")
        expect(hotkeySettings(defaults).screen == manager.settings.screen, "and is persisted through the model's own store")
        expect(backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil && !form.statusField.stringValue.hasPrefix("Error"), "a running manager registers it at once and the error clears")
        press(modifiers[3])
        expect(manager.settings.screen.modifiers == [.command, .shift], "a second modifier is added")
        let other = form.keyPopup(for: .window), otherMods = form.modifierToggles(for: .window)
        pick(other, k)
        press(otherMods[0])
        let keyCodeK = GlobalHotkeyKeys.choices[k - 1].code
        expect(manager.settings.window == .init(keyCode: keyCodeK, modifiers: .command), "Command plus K on Window is its own shortcut, so it is accepted")
        press(otherMods[3])
        expect(manager.settings.window == .init(keyCode: keyCodeK, modifiers: .command) && manager.settings.screen.modifiers == [.command, .shift] && form.statusField.stringValue.contains("same shortcut"),
               "adding Shift makes it Screen region's shortcut: refused with the manager's own message, and nothing saved changes: '\(form.statusField.stringValue)'")
        pick(popup, 0)
        expect(modifiers.allSatisfy { !$0.isEnabled && $0.state == .off }, "None clears and disables the modifiers")
        form.enabledCheckbox.performClick(nil)
        expect(!manager.settings.enabled && !hotkeySettings(defaults).enabled && form.enabledCheckbox.state == .off, "the enable box turns every shortcut off")
        form.clearButton.performClick(nil)
        expect(manager.settings == .defaults && form.enabledCheckbox.state == .on && GlobalHotkeyAction.allCases.allSatisfy { manager.settings[$0] == .none }, "Clear All sets every key to None at once")
        expect(form.clearButton.title == "Clear All" && !descendants(form).contains { ($0 as? NSButton)?.title == "Disable All" || ($0 as? NSButton)?.title == "Reset Defaults" },
               "Reset Defaults is Clear All, and Disable All is gone: the enable box is the one switch")
        // F-J2-020: a duplicate the manager refused leaves a red line; unticking the box answers it instead of validating the same draft again.
        for action in [GlobalHotkeyAction.screen, .window] {
            pick(form.keyPopup(for: action), k)
            press(form.modifierToggles(for: action)[0])
        }
        expect(form.statusField.stringValue.hasPrefix("Error: ") && form.statusField.stringValue.contains("same shortcut"), "the duplicate leaves its error on screen: '\(form.statusField.stringValue)'")
        // A chosen modifier reads as chosen on its plate: the accent fill and border and the semibold face, not colour alone.
        let chosenToggle = form.modifierToggles(for: .window)[0], bareToggle = form.modifierToggles(for: .window)[1]
        expect(chosenToggle.state == .on && chosenToggle.plate.stateStyle.fill != nil && chosenToggle.plate.stateStyle.borderWidth == 1 && chosenToggle.plate.stateStyle.strongText
               && chosenToggle.titleLabel.font == DesignTokens.Typography.font(.bodyStrong), "a chosen modifier is the accent fill, a border and a semibold symbol")
        expect(bareToggle.state == .off && bareToggle.plate.stateStyle.fill == nil && bareToggle.titleLabel.font == DesignTokens.Typography.font(.body), "an unchosen one rests bare")
        form.enabledCheckbox.performClick(nil)
        expect(!manager.settings.enabled && form.enabledCheckbox.state == .off && form.statusField.stringValue == GlobalHotkeyForm.idleLiveStatus && form.statusField.textColor == DesignTokens.Palette.Text.primary,
               "Unticking the box clears the stale duplicate error: '\(form.statusField.stringValue)'")
        expect(form.keyPopup(for: .window).indexOfSelectedItem == 0, "the rejected draft is dropped, not kept beside a disabled form")
        controller.show(); controller.window.orderOut(nil)
    }

    // MARK: The shortcut form's glass choices

    /// The enable box, each row's key pop-up and four modifier toggles, and Clear All: what they store, how they are named, and that none is cut short.
    private static func shortcutForm() {
        let (controller, defaults, manager, backend, _, _) = makeController()
        controller.select(2)
        let window = controller.window, form = controller.capture.hotkeyForm!
        window.contentView?.layoutSubtreeIfNeeded()
        try? manager.install(globalScreen: {}, globalWindow: {}, globalFullscreen: {}, globalFrame: {}, globalUpload: {}, globalShow: {})
        let k = GlobalHotkeyKeys.choices.firstIndex { $0.name == "K" }! + 1

        // Names and roles: six rows of Command are told apart by ear, every toggle is a check box with a value, the key is a pop-up button.
        var names: [String] = []
        for action in GlobalHotkeyAction.allCases {
            let toggles = form.modifierToggles(for: action), key = form.keyPopup(for: action)
            expect(toggles.map(\.title) == ["\u{2318}", "\u{2325}", "\u{2303}", "\u{21E7}"], "\(action.title): the four modifiers are drawn as their symbols, Command first")
            expect(toggles.map { $0.accessibilityLabel() ?? "" } == ["\(action.title) Command", "\(action.title) Option", "\(action.title) Control", "\(action.title) Shift"], "\(action.title): each modifier is spoken with its action")
            names += toggles.map { $0.accessibilityLabel() ?? "" }
            expect(toggles.allSatisfy { $0.kind == .toggle && $0.indicator == GlassChoiceButton.Indicator.none && $0.accessibilityRole() == .checkBox && ($0.accessibilityValue() as? NSNumber)?.intValue == 0 && AppToolTip.text(for: $0) == GlobalHotkeyForm.modifierToolTip },
                   "\(action.title): the modifiers are check boxes, off, with the modifier tooltip: \(toggles.map { "\($0.kind) \($0.indicator) \(String(describing: $0.accessibilityRole())) \(String(describing: $0.accessibilityValue())) \(String(describing: AppToolTip.text(for: $0)))" })")
            expect(key.accessibilityRole() == .popUpButton && key.accessibilityLabel() == "\(action.title) key" && key.indexOfSelectedItem == 0 && key.numberOfItems == GlobalHotkeyKeys.choices.count + 1 && key.itemTitle(at: 0) == "None",
                   "\(action.title): the key is a pop-up named '\(action.title) key', None first, then every key")
            let plate = form.rowPlate(for: action)
            expect(plate.accessibilityRole() == .group && plate.accessibilityLabel() == "\(action.title) shortcut" && plate.identifier?.rawValue == "GlobalHotkeyRow." + action.rawValue, "\(action.title): the plate is a named group")
        }
        expect(Set(names).count == names.count, "all \(names.count) modifier names are unique")
        expect(form.enabledCheckbox.kind == .toggle && form.enabledCheckbox.indicator == .checkbox && form.enabledCheckbox.accessibilityRole() == .checkBox && form.enabledCheckbox.accessibilityValue() as? NSNumber == 1
               && form.enabledCheckbox.title == "Enable global capture shortcuts", "the enable box is a labelled check box, on")
        expect(form.clearButton is CommandButton && form.clearButton.title == "Clear All" && form.clearButton.cell?.accessibilityRole() == .button && (form.clearButton.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 20, "Clear All is a titled command button at 20 pt")

        // With no key the modifiers are off, dimmed and skipped by the keyboard.
        let screenMods = form.modifierToggles(for: .screen), screenKey = form.keyPopup(for: .screen)
        let saved = KeyboardNavigation.fullKeyboardAccess
        KeyboardNavigation.fullKeyboardAccess = { true }
        defer { KeyboardNavigation.fullKeyboardAccess = saved }
        expect(screenMods.allSatisfy { !$0.isEnabled && $0.alphaValue == StateStyles.disabledAlpha && !$0.canBecomeKeyView && !$0.acceptsFirstResponder }, "with no key the modifiers dim and take no focus")
        expect(screenKey.canBecomeKeyView && screenKey.acceptsFirstResponder, "the key pop-up is on the Tab loop")

        // The key is chosen through the panel: a long list that scrolls, rows named like the keys, the chosen one marked, one action sent.
        let host = screenKey.choicePanel.host
        var presented = 0
        host.presenter = { _, _ in presented += 1 }
        host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1440, height: 900)
        host.accessibility = .none
        screenKey.performClick(nil)
        let panel = screenKey.choicePanel
        expect(host.isShown && presented == 1 && panel.rows.count == GlobalHotkeyKeys.choices.count + 1 && panel.rows.first?.title == "None" && panel.rows.last?.title == "Space",
               "the key pop-up opens a glass panel of None and every key (\(panel.rows.count) rows)")
        expect(host.contentSize.height > 900 && host.placement?.scrolls == true && (host.placement?.frame.height ?? .infinity) <= 900, "the long list is taller than the screen, so the panel caps and scrolls (\(host.contentSize.height) pt in \(String(describing: host.placement)))")
        expect(panel.rows.filter(\.isChosen).map(\.title) == ["None"], "None is the chosen row to start")
        let before = manager.settings
        panel.activate(panel.rows.first { $0.title == "K" }!)
        expect(!host.isShown && screenKey.indexOfSelectedItem == k && screenKey.titleOfSelectedItem == "K", "choosing a row closes the panel and sets the pop-up to K")
        expect(screenMods.allSatisfy { $0.isEnabled && $0.alphaValue == 1 } && manager.settings == before && form.statusField.stringValue.hasPrefix("Error: "),
               "a key alone is refused (no Command or Control), and the modifiers wake up")
        screenKey.performClick(nil)
        expect(panel.rows.filter(\.isChosen).map(\.title) == ["K"], "the panel marks the current key")
        host.close()
        expect(KeyboardNavigation.reaches(screenMods[0]), "an enabled modifier is on the Tab loop")

        // Every combination of the four modifiers stores exactly those flags; the ones the manager refuses leave the saved value alone.
        let all = GlobalHotkeyForm.modifierSegments.map(\.0)
        var accepted = 0, refused = 0
        for mask in 0..<16 {
            let wanted = GlobalHotkeyModifiers(all.indices.filter { mask & (1 << $0) != 0 }.map { all[$0] })
            let previous = manager.settings.screen   // the steps toward a refused set can pass through accepted ones, so only "an accepted shortcut stays" is asserted
            for (index, toggle) in screenMods.enumerated() where (toggle.state == .on) != (wanted.contains(all[index])) { toggle.performClick(nil) }
            expect(zip(screenMods, all).allSatisfy { ($0.state == .on) == wanted.contains($1) } && form.draft().screen.modifiers == wanted, "the toggles show \(wanted.rawValue) and the draft holds the same flags")
            if wanted.contains(.command) || wanted.contains(.control) {
                expect(manager.settings.screen == .init(keyCode: GlobalHotkeyKeys.choices[k - 1].code, modifiers: wanted) && hotkeySettings(defaults).screen == manager.settings.screen && !form.statusField.stringValue.hasPrefix("Error"),
                       "flags \(wanted.rawValue) with K are stored and registered exactly as chosen"); accepted += 1
            } else {
                let standing = manager.settings.screen
                expect(form.statusField.stringValue.hasPrefix("Error: ") && (standing == .none || (standing.keyCode == GlobalHotkeyKeys.choices[k - 1].code && !standing.modifiers.isDisjoint(with: [.command, .control]))) && hotkeySettings(defaults).screen == standing,
                       "flags \(wanted.rawValue) with K are refused with an error, and what stays saved is a shortcut the manager accepted (\(standing.modifiers.rawValue), was \(previous.modifiers.rawValue))"); refused += 1
            }
            expect(screenMods.map { ($0.accessibilityValue() as? NSNumber)?.intValue ?? -1 } == all.map { wanted.contains($0) ? 1 : 0 }, "the check boxes read the same flags")
        }
        expect(accepted == 12 && refused == 4, "twelve of the sixteen combinations carry Command or Control (\(accepted) and \(refused))")
        expect(backend.bindings[GlobalHotkeyAction.screen.carbonID] != nil, "the shortcut stays registered")
        // A chosen modifier carries the capsule under Differentiate Without Color, and the chosen look otherwise.
        defer { DisplayOptions.override = nil }
        for toggle in screenMods where toggle.state == .off { toggle.performClick(nil) }
        DisplayOptions.override = DisplayOptions(differentiateWithoutColor: true)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(screenMods.allSatisfy { $0.state == .on && $0.showsIndicator && $0.plate.stateStyle.strongText && $0.plate.stateStyle.fill != nil }, "chosen modifiers are the fill, the border, the semibold symbol and the capsule")
        expect(form.modifierToggles(for: .window).allSatisfy { !$0.showsIndicator }, "an unchosen row stays bare")
        DisplayOptions.override = nil
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)

        // Nothing is cut short: the symbols, the pop-up faces, the enable label and Clear All.
        window.contentView?.layoutSubtreeIfNeeded()
        let toggles = GlobalHotkeyAction.allCases.flatMap { form.modifierToggles(for: $0) } + [form.enabledCheckbox]
        expect(toggles.allSatisfy { labelIsWhole($0) }, "no modifier symbol and no enable label is cut short: \(toggles.filter { !labelIsWhole($0) }.map { "\($0.accessibilityLabel() ?? "") needs \($0.titleLabel.fittingSize) has \($0.titleLabel.frame.size)" })")
        expect(GlobalHotkeyAction.allCases.allSatisfy { action in
            let key = form.keyPopup(for: action)
            return key.frame.width + 0.5 >= key.intrinsicContentSize.width && key.frame.height == GlassChoiceButton.height
        }, "every key pop-up is wide enough for its widest key name and a control tall")
        expect(form.clearButton.frame.width + 0.5 >= SettingsActionButton.width(for: "Clear All"), "Clear All holds its label")
        expect(toggles.allSatisfy { $0.titleLabel.font?.pointSize == 20 } && form.clearButton.font?.pointSize == 20, "every label is 20 pt")

        // Clear All resets every key, the modifiers and the pop-ups together.
        form.clearButton.performClick(nil)
        expect(manager.settings == .defaults && GlobalHotkeyAction.allCases.allSatisfy { form.keyPopup(for: $0).indexOfSelectedItem == 0 && form.modifierToggles(for: $0).allSatisfy { !$0.isEnabled && $0.state == .off } },
               "Clear All sets every pop-up to None and every modifier off")
        expect(backend.bindings.isEmpty, "and nothing stays registered")
    }

    // MARK: The modifier toggles on the keyboard and to the eye

    private static func spaceKey(window: NSWindow) -> NSEvent { keyEvent(" ", code: 49, flags: [], window: window) }

    /// The Tab loop of the Capture tab, from the strip: each row's four modifiers are ONE stop (only when they are enabled), the arrows move within
    /// the row, Space and Return flip the focused one exactly once, and what is stored is exactly what the toggles show.
    private static func modifierKeyboard() {
        let (controller, defaults, manager, _, _, _) = makeController()
        controller.select(2)
        let window = controller.window, form = controller.capture.hotkeyForm!
        window.contentView?.layoutSubtreeIfNeeded()
        try? manager.install(globalScreen: {}, globalWindow: {}, globalFullscreen: {}, globalFrame: {}, globalUpload: {}, globalShow: {})
        let saved = KeyboardNavigation.fullKeyboardAccess
        KeyboardNavigation.fullKeyboardAccess = { true }
        defer { KeyboardNavigation.fullKeyboardAccess = saved }
        func loop() -> [NSView] {
            window.recalculateKeyViewLoop()
            var seen: [NSView] = [], view: NSView? = controller.strip
            for _ in 0..<120 { view = view?.nextValidKeyView; guard let next = view, next !== controller.strip else { break }; seen.append(next) }
            return seen
        }
        func modifierStops(_ views: [NSView]) -> [GlassChoiceButton] {
            let all = GlobalHotkeyAction.allCases.flatMap { form.modifierToggles(for: $0) }
            return views.compactMap { $0 as? GlassChoiceButton }.filter { toggle in all.contains { $0 === toggle } }
        }
        let k = GlobalHotkeyKeys.choices.firstIndex { $0.name == "K" }! + 1
        func pick(_ action: GlobalHotkeyAction, _ index: Int) { let popup = form.keyPopup(for: action); popup.selectItem(at: index); _ = popup.target?.perform(popup.action, with: popup) }

        // With no key nothing in a modifier group takes Tab; the rest of the tab is the strip, Flash, the enable box, six keys and Clear All.
        let bare = loop()
        let bareKinds = bare.map { String(describing: type(of: $0)) }
        expect(modifierStops(bare).isEmpty && bare.filter { $0 is GlassPopUpButton }.count == 6, "with no key chosen the modifier groups are out of the Tab loop and the six key pop-ups are in it: \(bareKinds)")
        // Each key chosen puts exactly one stop for that row's group into the loop, on the first toggle.
        for (index, action) in GlobalHotkeyAction.allCases.enumerated() {
            pick(action, k + index)
            let stops = modifierStops(loop())
            expect(stops.count == index + 1 && stops.last === form.modifierToggles(for: action)[0], "\(action.title): its four modifiers add ONE Tab stop, the first toggle (\(stops.count) stops)")
        }
        let full = loop()
        expect(full.count == bare.count + 6 && modifierStops(full).count == 6, "six rows of four modifiers are six Tab stops, not twenty-four (\(full.count) against \(bare.count) with no key)")
        expect(GlobalHotkeyAction.allCases.allSatisfy { action in form.modifierToggles(for: action).filter(\.canBecomeKeyView).count == 1 }, "exactly one toggle of each row can become the key view")

        // Arrows move the focus within the row, wrapping, and the toggle the keyboard is on becomes the stop.
        let action = GlobalHotkeyAction.window
        let toggles = form.modifierToggles(for: action)
        expect(window.makeFirstResponder(toggles[0]) && window.firstResponder === toggles[0], "the stop takes the keyboard")
        func arrow(_ code: UInt16, from toggle: GlassChoiceButton) { toggle.keyDown(with: arrowEvent(code, window: window)) }
        arrow(124, from: toggles[0])
        expect(window.firstResponder === toggles[1] && form.modifierStop(for: action) === toggles[1] && toggles[1].canBecomeKeyView && !toggles[0].canBecomeKeyView, "Right moves the focus to Option and Option becomes the stop")
        arrow(124, from: toggles[1]); arrow(124, from: toggles[2])
        expect(window.firstResponder === toggles[3], "Right walks on to Shift")
        arrow(124, from: toggles[3])
        expect(window.firstResponder === toggles[0] && form.modifierStop(for: action) === toggles[0], "Right wraps from Shift to Command")
        arrow(123, from: toggles[0])
        expect(window.firstResponder === toggles[3], "Left wraps from Command to Shift")
        expect(modifierStops(loop()).filter { toggles.contains($0) } == [toggles[3]], "Tab returns to where the keyboard was: Shift is the row's stop")
        // Nothing stored moved: arrows never change a modifier.
        let stored = manager.settings
        expect(toggles.allSatisfy { $0.state == .off } && manager.settings == stored, "arrows move the focus and change nothing stored")

        // Space, Return and Enter flip the focused toggle exactly once, and the manager stores exactly the flags the toggles show.
        func flags(_ action: GlobalHotkeyAction) -> GlobalHotkeyModifiers {
            var result: GlobalHotkeyModifiers = []
            for (toggle, entry) in zip(form.modifierToggles(for: action), GlobalHotkeyForm.modifierSegments) where toggle.state == .on { result.insert(entry.0) }
            return result
        }
        // (Every row holding a key with no modifier would refuse any edit, so start again from Clear All with only this row's key.)
        form.clearButton.performClick(nil)
        pick(action, k)
        expect(toggles.allSatisfy(\.isEnabled) && toggles.allSatisfy { $0.state == .off }, "Clear All and one key chosen: the row's modifiers are enabled and off")
        window.makeFirstResponder(toggles[0])
        toggles[0].keyDown(with: spaceKey(window: window))
        expect(toggles[0].state == .on && flags(action) == .command && manager.settings.window == .init(keyCode: GlobalHotkeyKeys.choices[k - 1].code, modifiers: .command),
               "Space flips Command once and Command plus the key is stored (\(manager.settings.window))")
        toggles[0].keyDown(with: spaceKey(window: window))
        expect(toggles[0].state == .off && flags(action).isEmpty && form.statusField.stringValue.hasPrefix("Error: ") && manager.settings.window.modifiers == .command,
               "a second Space flips it back; a key alone is refused, so the saved Command stands")
        window.makeFirstResponder(toggles[2])
        toggles[2].keyDown(with: keyEvent("\r", code: 36, flags: [], window: window))
        expect(toggles[2].state == .on && flags(action) == .control && manager.settings.window.modifiers == .control, "Return flips Control once and Control plus the key is stored")
        toggles[2].keyDown(with: keyEvent("\u{3}", code: 76, flags: [], window: window))
        expect(toggles[2].state == .off, "Enter flips it back")
        expect(hotkeySettings(defaults).window == manager.settings.window && form.draft().window.modifiers == flags(action), "what is stored is what the toggles show")
        // A key with a modifier held, and Tab, are the window's, not the toggle's.
        let before = toggles[1].state
        toggles[1].keyDown(with: keyEvent(" ", code: 49, flags: .command, window: window))
        expect(toggles[1].state == before, "Command-Space is not Space")
        expect(modifierStops(loop()).count == 1, "after Clear All and one key, the one enabled row has the one stop")

        // VoiceOver still finds four check boxes inside a group named after the row.
        for action in GlobalHotkeyAction.allCases {
            let group = form.modifierGroup(for: action)
            expect(group.accessibilityRole() == .group && group.accessibilityLabel() == "\(action.title) modifiers" && group.isAccessibilityElement(), "\(action.title): a group named '\(action.title) modifiers'")
            expect((group.accessibilityChildren() ?? []).count == 4 && form.modifierToggles(for: action).allSatisfy { $0.isDescendant(of: group) && $0.accessibilityRole() == .checkBox }, "\(action.title): four check boxes inside it")
        }
    }

    /// Each modifier symbol sits on the middle of its button: the ink of the drawn glyph, measured from pixels, is within a point of the button's
    /// centre (the control caret sits at the top of its em box and was 3.5 pt high).
    private static func modifierGlyphs() {
        let (controller, _, _, _, _, _) = makeController()
        controller.select(2)
        let window = controller.window, form = controller.capture.hotkeyForm!
        window.contentView?.layoutSubtreeIfNeeded()
        /// The vertical middle of the drawn ink of a toggle's label, in the toggle's own (y up) space.
        func inkMiddle(of toggle: GlassChoiceButton) -> CGFloat? {
            let label = toggle.titleLabel, color = label.textColor
            label.textColor = .black
            defer { label.textColor = color }
            guard let rep = label.bitmapImageRepForCachingDisplay(in: label.bounds) else { return nil }
            label.cacheDisplay(in: label.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / label.bounds.width
            var top: Int?, bottom: Int?
            for y in 0..<rep.pixelsHigh {
                let row = (0..<rep.pixelsWide).contains { rep.colorAt(x: $0, y: y)?.alphaComponent ?? 0 > 0.3 }
                if row { if top == nil { top = y }; bottom = y }
            }
            guard let top, let bottom else { return nil }
            return label.frame.maxY - CGFloat(top + bottom + 1) / 2 / scale
        }
        var worst: CGFloat = 0
        for action in GlobalHotkeyAction.allCases {
            for (index, toggle) in form.modifierToggles(for: action).enumerated() {
                guard let middle = inkMiddle(of: toggle) else { expect(false, "\(action.title) \(toggle.title): the symbol drew nothing"); continue }
                let delta = abs(middle - toggle.bounds.midY)
                worst = max(worst, delta)
                expect(delta <= 1, "\(action.title) \(toggle.accessibilityLabel() ?? ""): the symbol's ink is \(delta) pt off the button's centre")
                expect(toggle.titleLabel.font?.pointSize == 20 && toggle.titleLabel.attributedStringValue.string == GlobalHotkeyForm.modifierSegments[index].1, "the symbol keeps its size and its place in the order")
            }
        }
        // Chosen (the semibold face) it still holds, and the shift survives the state change.
        let toggles = form.modifierToggles(for: .screen)
        toggles.forEach { $0.state = .on }
        for toggle in toggles { if let middle = inkMiddle(of: toggle) { expect(abs(middle - toggle.bounds.midY) <= 1, "\(toggle.accessibilityLabel() ?? ""): chosen, the symbol's ink is \(abs(middle - toggle.bounds.midY)) pt off the centre") } }
        print("  Modifier symbols: 24 toggles, ink centre within \(String(format: "%.2f", worst)) pt of the button's centre")
    }

    /// Every modifier label, chosen and unchosen, is drawn in a frame that holds what the real label needs (its font, whatever shifts its ink, the
    /// semibold face): the optical centring moves the ink and never asks the 36 pt button for more line height than it gave the label.
    private static func modifierLabelsFit() {
        let (controller, _, _, _, _, _) = makeController()
        controller.select(2)
        let window = controller.window, form = controller.capture.hotkeyForm!
        window.contentView?.layoutSubtreeIfNeeded()
        var judged = 0
        for chosen in [false, true] {
            for action in GlobalHotkeyAction.allCases {
                for toggle in form.modifierToggles(for: action) {
                    toggle.state = chosen ? .on : .off
                    toggle.layoutSubtreeIfNeeded()
                    window.contentView?.layoutSubtreeIfNeeded()
                    let label = toggle.titleLabel, need = label.fittingSize
                    expect(need.height <= label.frame.height + 0.01 && need.width <= label.frame.width + 0.01,
                           "\(action.title) \(toggle.title) \(chosen ? "chosen" : "unchosen"): the label needs \(need.width) x \(need.height) pt and has \(label.frame.width) x \(label.frame.height)")
                    expect(label.frame.height <= toggle.bounds.height && toggle.frame.height == GlassChoiceButton.height && label.font?.pointSize == 20,
                           "\(action.title) \(toggle.title): the label sits inside the unchanged control-high button at 20 pt")
                    judged += 1
                }
            }
        }
        print("  Modifier labels: \(judged) judged (24 toggles, chosen and unchosen), every fitting size within its frame")
    }

    // MARK: Real key flags

    /// Only Command, Option, Control and Shift make a chord. The arrows carry the function and numeric-pad flags, and Caps Lock can be on for any
    /// key, so none of them may turn an arrow, Escape or Command-W into "a modified key".
    private static func realKeyFlags() {
        let (controller, _, _, _, _, _) = makeController()
        let window = controller.window
        expect(keyEvent("\u{F703}", code: 124, flags: realArrowFlags, window: window).chordModifiers.isEmpty, "a real arrow key holds no modifier")
        expect(keyEvent("a", code: 0, flags: [.capsLock, .function, .numericPad], window: window).chordModifiers.isEmpty, "Caps Lock, function and numeric pad are not chords")
        expect(keyEvent("\u{F703}", code: 124, flags: [.shift, .function, .numericPad], window: window).chordModifiers == .shift, "Shift is, whatever else the arrow carries")
        // The tab strip: arrows with the flags AppKit sends move between tabs, with Caps Lock too; a held modifier still does not.
        controller.select(0)
        let strip = controller.strip
        strip.keyDown(with: keyEvent("\u{F703}", code: 124, flags: realArrowFlags, window: window))
        expect(controller.selectedIndex == 1, "a real Right arrow moves to the next tab")
        strip.keyDown(with: keyEvent("\u{F703}", code: 124, flags: realArrowFlags.union(.capsLock), window: window))
        expect(controller.selectedIndex == 2, "and with Caps Lock on")
        strip.keyDown(with: keyEvent("\u{F702}", code: 123, flags: realArrowFlags, window: window))
        expect(controller.selectedIndex == 1, "a real Left arrow moves back")
        strip.keyDown(with: keyEvent("\u{F703}", code: 124, flags: realArrowFlags.union(.option), window: window))
        expect(controller.selectedIndex == 1, "Option with the arrow is not a tab move")
        // Escape and Command-W with Caps Lock on still close the window.
        var closes = 0
        controller.onClose = { closes += 1 }
        window.keyDown(with: keyEvent("\u{1b}", code: 53, flags: .capsLock, window: window))
        expect(closes == 1, "Escape with Caps Lock on closes")
        expect(window.performKeyEquivalent(with: keyEvent("w", code: 13, flags: [.command, .capsLock], window: window)) && closes == 2, "Command-W with Caps Lock on closes")
        window.keyDown(with: keyEvent("\u{1b}", code: 53, flags: .shift, window: window))
        expect(closes == 2, "Shift-Escape does not")
        controller.onClose = nil
        // The modifier toggles: a real Right arrow moves between Command, Option, Control and Shift (checked in modifierKeyboard with the same flags).
        controller.select(2)
        let form = controller.capture.hotkeyForm!
        let toggles = form.modifierToggles(for: .screen)
        let popup = form.keyPopup(for: .screen)
        popup.selectItem(at: 1); _ = popup.target?.perform(popup.action, with: popup)
        window.contentView?.layoutSubtreeIfNeeded()
        _ = window.makeFirstResponder(toggles[0])
        for index in 1...3 {
            toggles[index - 1].keyDown(with: keyEvent("\u{F703}", code: 124, flags: realArrowFlags, window: window))
            expect(window.firstResponder === toggles[index], "a real Right arrow reaches \(toggles[index].accessibilityLabel() ?? "") (Option, Control and Shift are reachable from the keyboard)")
        }
    }

    // MARK: A key pop-up's panel does not end the editing

    /// Opening a key pop-up's glass panel makes Settings resign key to its own child panel. That is still the window in use: the shortcuts stay
    /// paused, the note and a rejected draft's error stay, and nothing is re-read when the key comes back. A different window taking the key
    /// does end it.
    private static func keyPanelKeepsEditing() {
        let name = "OpenSnap.SettingsTests.panel." + UUID().uuidString
        let defaults = TestDefaults(name: name)
        defer { TestDefaults.dispose(defaults, name: name) }
        let hotkeys = RecordingHotkeys()
        let controller = SettingsWindowController(state: { initialState }, hotkeys: hotkeys, defaults: defaults, destinations: { PublishingDestinationList() })
        controller.visibleFrame = { fakeVisible }
        controller.applicationActivity = { true }
        controller.show(tab: SettingsWindowController.captureTabIndex)
        controller.activityChanged(key: true, appActive: true)
        let window = controller.window, form = controller.capture.hotkeyForm!
        window.contentView?.layoutSubtreeIfNeeded()
        expect(hotkeys.editing && form.shortcutsPaused, "Settings key on Capture pauses the shortcuts")
        let k = GlobalHotkeyKeys.choices.firstIndex { $0.name == "K" }! + 1
        let popup = form.keyPopup(for: .screen)
        popup.selectItem(at: k); _ = popup.target?.perform(popup.action, with: popup)
        let rejected = form.statusField.stringValue
        expect(rejected.hasPrefix("Error: ") && hotkeys.lastError != nil && popup.indexOfSelectedItem == k, "a key with no modifier is rejected and its draft stays on screen: '\(rejected)'")
        defaults.set(false, forKey: OriginalCaptureFlashTiming.showFlashKey)   // changed behind the window's back: a re-read would show it
        expect(controller.capture.flashCheckbox.state == .on, "(setup) the flash box still shows on")

        // The panel opens as a child of Settings and takes the key.
        let host = popup.choicePanel.host
        host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1440, height: 900)
        host.accessibility = .none
        host.presenter = { panel, parent in parent?.addChildWindow(panel, ordered: .above) }
        let logged = hotkeys.editingLog
        popup.performClick(nil)
        expect(host.isShown && window.childWindows?.contains { $0 is GlassChoiceWindow } == true, "the key panel is a child of the Settings window")
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: host.window)
        expect(!hotkeys.editingLog.dropFirst(logged.count).contains(false) && hotkeys.editing, "Settings resigning key to its own panel does not end the editing: nothing was re-registered (\(hotkeys.editingLog))")
        expect(form.shortcutsPaused && form.statusField.stringValue == rejected && hotkeys.lastError != nil, "the note, the pause and the error are as they were: '\(form.statusField.stringValue)'")

        // The panel closes and the key comes back: nothing is re-read, and the rejected draft and its error remain.
        host.close()
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        expect(!hotkeys.editingLog.dropFirst(logged.count).contains(false) && hotkeys.editing && form.shortcutsPaused, "the shortcuts never went live during the whole choice (\(hotkeys.editingLog))")
        expect(form.statusField.stringValue == rejected && popup.indexOfSelectedItem == k && form.draft().screen.keyCode == GlobalHotkeyKeys.choices[k - 1].code,
               "the rejected draft and its error remain after the panel closes: '\(form.statusField.stringValue)'")
        expect(controller.capture.flashCheckbox.state == .on, "and the key coming back from the panel re-read nothing")
        // A real key change (not from the panel) does re-read, as before.
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        expect(controller.capture.flashCheckbox.state == .off, "an ordinary key change still refreshes the window")

        // Another window taking the key while the panel is open does end it.
        controller.activityChanged(key: true, appActive: true)
        popup.performClick(nil)
        expect(host.isShown, "(setup) the panel is open again")
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        let elsewhere = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        elsewhere.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: elsewhere)
        expect(!hotkeys.editing, "another window becoming key, with the panel open, puts the shortcuts back")
        host.close()
        controller.windowHidden()
        window.orderOut(nil)
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
