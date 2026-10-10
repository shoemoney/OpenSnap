// The Settings window, built standalone with in-memory stand-ins for everything the app owns. No window is ordered onto the
// desktop, no hotkey is registered with the system, no defaults domain is opened, no network, Keychain or real store is read.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D SETTINGS_WINDOW_TESTS \
//   Sources/SettingsWindow.swift Sources/GeneralPreferencesForm.swift Sources/GlobalHotkeys.swift Sources/AppToolTip.swift \
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
        expect(controller.tabs.tabStyle == .toolbar, "the tabs live in the window toolbar")
        expect(controller.tabItems.map(\.label) == ["General", "Drawing", "Capture", "Upload"], "four tabs in order: \(controller.tabItems.map(\.label))")
        expect(controller.tabItems.allSatisfy { $0.image != nil && $0.image!.size.width > 0 }, "every tab has an icon")
        expect(window.contentViewController === controller.tabs, "the tab controller is the window's content")
        for index in controller.tabItems.indices {
            controller.select(index)
            expect(window.title == controller.tabItems[index].label, "the window title follows the tab: '\(window.title)' on \(controller.tabItems[index].label)")
        }
        controller.select(0)
        expect(!window.styleMask.contains(.resizable), "width is fixed; height follows the tab")
        expect(SettingsWindowController.autosaveName == "OpenSnap.Settings" && window.frameAutosaveName.isEmpty,
               "the frame name is supplied by the app; a test passes none and nothing is saved")
        let buttons = controller.tabItems.flatMap { descendants($0.viewController!.view) }.compactMap { $0 as? NSButton }
        expect(!buttons.contains { $0.title == "Done" || $0.keyEquivalent == "\r" }, "no Done button, and no default button to take Return")
        let all = controller.tabItems.flatMap { texts(in: $0.viewController!.view) }
        for word in ["Appearance", "Sounds", "Play sounds", "Relaunch", "Modern", "Classic"] {
            expect(!all.contains { $0.localizedCaseInsensitiveContains(word) }, "no row or control mentions \(word)")
        }
        expect(controller.window.delegate === controller, "the controller is the window's delegate")
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
        let (controller, _, _, _, _, _) = makeController()
        let window = controller.window
        window.setFrameTopLeftPoint(NSPoint(x: 100, y: fakeVisible.maxY - 20))
        var heights: [CGFloat] = []
        for index in controller.tabItems.indices {
            let top = window.frame.maxY
            controller.select(index)
            let height = controller.windowHeight(forTabAt: index)
            heights.append(height)
            expect(height <= fakeVisible.height, "\(controller.tabItems[index].label) needs \(height) pt; the fake 1280 x 800 screen shows \(fakeVisible.height)")
            expect(abs(window.frame.height - height) < 0.5, "the window is the height its tab asks for (\(window.frame.height) vs \(height))")
            expect(abs(window.contentLayoutRect.width - SettingsLayout.contentWidth) < 0.5, "the content is 640 wide on every tab")
            expect(abs(window.frame.maxY - top) < 0.5, "switching tabs keeps the top edge where it was")
            window.contentView?.layoutSubtreeIfNeeded()
            let tabView = controller.selectedTab.view
            for control in descendants(tabView).compactMap({ $0 as? NSControl }) where !control.isHidden && control.bounds.width > 0 {
                let box = frame(of: control, in: tabView)
                expect(tabView.bounds.insetBy(dx: -0.5, dy: -0.5).contains(box), "\(controller.tabItems[index].label): \(control.className) at \(box) is outside the \(tabView.bounds) tab")
            }
        }
        expect(Set(heights).count == 4, "each tab sizes to its own content, not one shared height: \(heights)")
        expect(heights[2] > heights[0] && heights[2] > heights[3], "Capture, the longest form, is the tallest: \(heights)")
        // A tab switch animates; a second switch while the first is under way replaces it, and the window ends on the later size.
        controller.reduceMotion = { false }; controller.animatesWhenHidden = true
        controller.select(0); spin(0.5)
        let general = controller.windowHeight(forTabAt: 0), capture = controller.windowHeight(forTabAt: 2), drawing = controller.windowHeight(forTabAt: 1)
        expect(abs(window.frame.height - general) < 0.5 && Set([general, capture, drawing]).count == 3, "the General tab's size is settled (\(window.frame.height))")
        controller.select(2)
        spin(0.06)
        expect(window.frame.height > general + 1 && window.frame.height < capture - 1, "the switch to Capture is animating (\(general) < \(window.frame.height) < \(capture))")
        controller.select(1)
        spin(0.6)
        expect(abs(window.frame.height - drawing) < 0.5, "after a second switch the window is \(window.frame.height), not the first target \(capture) (Drawing wants \(drawing))")
        controller.select(2); spin(0.6)
        expect(abs(window.frame.height - capture) < 0.5, "an undisturbed switch arrives at its target (\(window.frame.height) vs \(capture))")
        // The same when the later change is immediate (a refit that is not animated): the earlier animation must not step on past it.
        controller.select(0); spin(0.6)
        controller.select(2); spin(0.06)
        controller.reduceMotion = { true }
        controller.select(1)
        spin(0.6)
        expect(abs(window.frame.height - drawing) < 0.5, "an immediate resize is not undone by the animation it interrupted: \(window.frame.height) vs \(drawing)")
        controller.reduceMotion = { false }
        controller.select(2); spin(0.6)
        controller.reduceMotion = { true }
        controller.select(0)
        expect(abs(window.frame.height - general) < 0.5, "under Reduce Motion the window is its new size at once (\(window.frame.height))")
        controller.reduceMotion = { false }; controller.animatesWhenHidden = false
        // A screen too short for a tab limits the window instead of letting it run off the bottom.
        controller.visibleFrame = { NSRect(x: 0, y: 0, width: 1280, height: 400) }
        controller.select(2)
        expect(window.frame.height <= 400, "a 400 pt screen caps the window at \(window.frame.height)")
        controller.visibleFrame = { fakeVisible }
        controller.fit(animated: false)
    }

    // MARK: Alignment and type

    private static func alignmentAndTypography() {
        let (controller, _, _, _, _, _) = makeController(destinations: sampleDestinations(count: 2))
        for index in controller.tabItems.indices {
            controller.select(index)
            controller.window.contentView?.layoutSubtreeIfNeeded()
            let tab = controller.tabItems[index].viewController!.view
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
            let tabLeft = (tab.bounds.width - SettingsLayout.gridWidth) / 2
            let controlColumn = tabLeft + SettingsLayout.labelColumnWidth + SettingsLayout.columnSpacing
            let grid = controller.tabItems[index].viewController as! SettingsTabViewController
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
            strings += texts(in: controller.tabItems[index].viewController!.view)
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
            let viewReport = ViewTreeAudit.audit(controller.tabItems[index].viewController!.view, surface: name + " (tab view)")
            expect(!viewReport.findings.isEmpty, "\(name): the walker found text, so zero violations means something")
            expect(windowReport.violations.isEmpty && viewReport.violations.isEmpty, "\(name) breaks the type floor:\n\(windowReport.description)\n\(viewReport.description)")
            judged += viewReport.findings.count
        }
        expect(judged > 20, "the audit judged the controls of every tab (\(judged))")
        print("  Settings window: \(judged) text items judged across four tabs, 0 violations")
    }
}
#endif
