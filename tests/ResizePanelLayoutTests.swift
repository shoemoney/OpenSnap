// The Resize or Crop sheet's layout (F-J1-014) and its glass choices: mode choice and dimensions first, presets folded away, no dead band above
// the buttons, the buttons on one trailing plate in the standard order, a 3 x 3 anchor grid for Crop, the preset list in a choice panel. A sheet on an
// off-screen parent; nothing is ordered front.
#if RESIZE_PANEL_LAYOUT_TESTS
import AppKit

@main
@MainActor
private enum ResizePanelLayoutTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(description: message) }
        checks += 1
    }
    private static func private_<T>(_ object: Any, _ name: String, as: T.Type = T.self) -> T? {
        Mirror(reflecting: object).children.first { $0.label == name }.flatMap { $0.value as? T }
    }
    private static func find<T: NSView>(_ type: T.Type, in root: NSView, where match: (T) -> Bool = { _ in true }) -> T? {
        if let hit = root as? T, match(hit) { return hit }
        for child in root.subviews { if let hit = find(type, in: child, where: match) { return hit } }
        return nil
    }

    static func main() {
        _ = NSApplication.shared
        KeyboardNavigation.fullKeyboardAccess = { true }
        do { try run(); try behaviour(); print("ResizePanelLayoutTests: \(checks) checks passed") }
        catch { print("FAIL \(error)"); exit(1) }
    }

    private static func run() throws {
        let suite = "OpenSnapResizeLayout." + UUID().uuidString
        let defaults = TestDefaults(name: suite)
        defer { TestDefaults.dispose(defaults, name: suite) }
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        parent.isReleasedWhenClosed = false
        var applied: [(CGSize, Bool, CGPoint)] = []
        let resize = ResizePanel(session: ResizePanelSession(size: CGSize(width: 1517, height: 1011), onApply: { applied.append(($0, $1, $2)) }),
                                 presets: ResizePresetStore(defaults: defaults))
        resize.show(attachedTo: parent)
        guard let panel: NSPanel = private_(resize, "panel"), let content = panel.contentView,
              let mode: GlassChoiceGroup = private_(resize, "modeControl"), let width: NSTextField = private_(resize, "widthField"),
              let grid: ResizeAnchorGrid = private_(resize, "anchorGrid"), let presetFace: GlassChoiceButton = private_(resize, "presetFace") else {
            throw Failure(description: "the sheet and its controls exist")
        }
        func button(_ title: String) -> NSButton? { find(NSButton.self, in: content) { $0.title == title } }
        guard let cancel = button("Cancel"), let apply = button("Apply"), let ok = button("OK") else { throw Failure(description: "Cancel, Apply and OK exist") }
        func select(_ index: Int) {
            mode.choose(index)
            content.layoutSubtreeIfNeeded()
        }
        func frame(_ view: NSView) -> NSRect { content.convert(view.bounds, from: view) }
        let inset: CGFloat = 28
        var heights: [CGFloat] = []

        for (index, name) in ["Resize", "Crop", "Limit"].enumerated() {
            select(index)
            heights.append(content.frame.height)
            // Mode first, then the dimensions (or the limit), then the preset row, then the buttons: top to bottom.
            let modeFrame = frame(mode), presetFrame = frame(presetFace), okFrame = frame(ok)
            let first: NSView = index == 2 ? (find(NSTextField.self, in: content) { $0.accessibilityLabel() == "Size limit in pixels" } ?? width) : width
            try expect(modeFrame.minY > frame(first).maxY && frame(first).minY > presetFrame.maxY && presetFrame.minY > okFrame.maxY,
                       "\(name): mode control, then the dimensions, then presets, then the buttons, top to bottom")
            // No dead band: the buttons sit one inset above the bottom edge, and the sheet is exactly as tall as its content.
            let actions = plate(of: ok).map { frame($0) } ?? .zero
            try expect(abs(actions.minY - inset) < 1.5, "\(name): the button plate is \(inset) pt from the bottom edge, no blank band under or above it (\(actions.minY))")
            // Trailing edge, standard order.
            try expect(abs(actions.maxX - (content.frame.width - inset)) < 1.5, "\(name): the button plate ends on the trailing margin (\(actions.maxX) of \(content.frame.width))")
            try expect(frame(cancel).maxX < frame(apply).minX && frame(apply).maxX < okFrame.minX, "\(name): Cancel, Apply, OK left to right")
            try expect(panel.defaultButtonCell === ok.cell && cancel.keyEquivalent == "\u{1b}" && apply.keyEquivalent.isEmpty, "\(name): OK is the default, Escape is Cancel, Apply is plain")
            try expect(find(NSTextField.self, in: content) { $0.accessibilityLabel() == "Preset name" && !$0.isHiddenOrHasHiddenAncestor } == nil, "\(name): preset naming is folded away until asked for")
        }
        try expect(heights[0] < heights[1], "Resize is a shorter sheet than Crop: the sheet is as tall as what it shows (\(heights))")

        // Crop: a 3 x 3 grid, the centre by default, picked by the pointer's cell and the arrow keys.
        select(1)
        try expect(!grid.isHidden && grid.anchor == .center && ResizePanelAnchor.allCases.count == 9, "Crop shows a 3 x 3 anchor grid on the centre")
        try expect(find(NSPopUpButton.self, in: content) == nil, "…and no native pop-up anywhere on the sheet")
        grid.select(.bottomRight)
        try expect(resize_state(resize).anchor == .bottomRight, "Picking the bottom-right cell sets the anchor")
        func arrow(_ code: UInt16) throws {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                               characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) else { throw Failure(description: "key event") }
            grid.keyDown(with: event)
        }
        try arrow(123); try arrow(126)
        try expect(grid.anchor == .center, "Left then Up from the bottom-right cell moves to the centre (\(grid.anchor))")
        try expect(grid.accessibilityChildren()?.count == 9 && grid.accessibilityRole() == .radioGroup, "VoiceOver sees a radio group of nine named cells")
        for (index, cell) in ResizePanelAnchor.allCases.enumerated() {
            let frame = grid.frame(of: cell)
            try expect(frame.width == ResizeAnchorGrid.cellSize.width && frame.height == ResizeAnchorGrid.cellSize.height
                       && grid.cell(at: NSPoint(x: frame.midX, y: frame.midY)) == cell && cell.rawValue == index, "Cell \(cell.title) is where the 3 x 3 layout puts it")
        }

        // The preset row opens its management on request, and the sheet grows to hold it.
        let before = content.frame.height
        resize.setPresetManagementShown(true)
        try expect(find(NSTextField.self, in: content) { $0.accessibilityLabel() == "Preset name" && !$0.isHiddenOrHasHiddenAncestor } != nil && content.frame.height > before, "Manage presets opens the naming row and the sheet grows with it")
        resize.setPresetManagementShown(false)
        try expect(content.frame.height == before, "…and folds back to the same height")

        // An error shows in place and the sheet makes room for it.
        select(0)
        let calm = content.frame.height
        width.stringValue = "abc"
        resize.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: width))
        ok.performClick(nil)
        guard let errorLabel: NSTextField = private_(resize, "errorLabel") else { throw Failure(description: "error label") }
        try expect(!errorLabel.isHidden && errorLabel.stringValue.hasPrefix("Error: ") && panel.sheetParent === parent, "An invalid width keeps the sheet and shows an Error: line (\(errorLabel.stringValue))")
        try expect(content.frame.height > calm && abs((plate(of: ok).map { frame($0) } ?? .zero).minY - inset) < 1.5, "The sheet grows to hold the message and the buttons stay one inset from the bottom (\(content.frame.height) vs \(calm))")
        width.stringValue = "400"
        resize.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: width))
        try expect(errorLabel.isHidden && content.frame.height == calm, "Typing a valid size takes the message and its room away again")
        if let parentSheet = parent.attachedSheet { parent.endSheet(parentSheet) }
    }

    /// The glass plate a control sits on.
    private static func plate(of view: NSView) -> GlassSurfaceView? {
        var current: NSView? = view
        while let next = current?.superview { if let plate = next as? GlassSurfaceView { return plate }; current = next }
        return nil
    }
    private static func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    private static func key(_ code: UInt16, _ text: String = "", window: NSWindow? = nil) throws -> NSEvent {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
                                           characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) else { throw Failure(description: "key event") }
        return event
    }

    @MainActor private final class Rig {
        let defaults: TestDefaults, suite: String, parent: NSWindow, resize: ResizePanel
        var applied: [(CGSize, Bool, CGPoint)] = []
        init(size: CGSize = CGSize(width: 1517, height: 1011), seed: ((UserDefaults) -> Void)? = nil) {
            suite = "OpenSnapResizeLayout." + UUID().uuidString
            defaults = TestDefaults(name: suite)
            seed?(defaults)
            parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
            parent.isReleasedWhenClosed = false
            let box = AppliedBox()
            resize = ResizePanel(session: ResizePanelSession(size: size, onApply: { box.values.append(($0, $1, $2)) }), presets: ResizePresetStore(defaults: defaults))
            appliedBox = box
            resize.show(attachedTo: parent)
            panel = private_(resize, "panel", as: NSPanel.self)!
        }
        let appliedBox: AppliedBox
        /// The sheet, held from the start: the panel forgets it when the sheet ends.
        let panel: NSPanel
        var content: NSView { panel.contentView! }
        var isFinished: Bool { (private_(resize, "session", as: ResizePanelSession.self))?.isFinished ?? false }
        func state() -> ResizePanelState { ResizePanelLayoutTests.resize_state(resize) }
        func close() {
            if let sheet = parent.attachedSheet { parent.endSheet(sheet) }
            TestDefaults.dispose(defaults, name: suite)
        }
    }
    @MainActor private final class AppliedBox { var values: [(CGSize, Bool, CGPoint)] = [] }

    private static func behaviour() throws {
        // Mode choice: the glass group re-renders the rows and the sheet fits each mode.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let mode: GlassChoiceGroup = private_(rig.resize, "modeControl"), let dimensions: NSStackView = private_(rig.resize, "dimensionRow"),
                  let limitRow: NSStackView = private_(rig.resize, "limitRow"), let anchorRow: NSStackView = private_(rig.resize, "anchorRow"),
                  let ratioPlate: GlassSurfaceView = private_(rig.resize, "ratioPlate") else { throw Failure(description: "the sheet's rows exist") }
            try expect(mode.selectedTitle == "Resize" && mode.buttons.map(\.title) == ["Resize", "Crop", "Limit"] && mode.accessibilityLabel() == "Size operation",
                       "The mode is a glass choice group named Size operation: \(mode.buttons.map(\.title))")
            try expect(mode.accessibilityRole() == .radioGroup && mode.buttons.allSatisfy { $0.accessibilityRole() == .radioButton }, "…a radio group of radio buttons")
            var heights: [CGFloat] = []
            for (index, expectation) in [(1, "Crop"), (2, "Limit"), (0, "Resize")] as [(Int, String)] {
                mode.choose(index)
                rig.content.layoutSubtreeIfNeeded()
                heights.append(rig.content.frame.height)
                try expect(mode.selectedIndex == index && mode.buttons[index].isChosen, "Choosing \(expectation) moves the chosen button")
                try expect(rig.state().mode.rawValue == index, "Choosing \(expectation) sets the session mode")
                try expect(dimensions.isHidden == (index == 2) && limitRow.isHidden == (index != 2) && anchorRow.isHidden == (index != 1) && ratioPlate.isHidden == (index != 0),
                           "\(expectation): rows shown are dimensions \(!dimensions.isHidden), limit \(!limitRow.isHidden), anchor \(!anchorRow.isHidden), lock \(!ratioPlate.isHidden)")
                let stack: NSStackView? = private_(rig.resize, "contentStack")
                try expect(abs(rig.content.frame.height - ((stack?.fittingSize.height ?? 0) + 56)) < 1.5, "\(expectation): the sheet is exactly as tall as its content")
            }
            try expect(heights[0] > heights[1] && heights[0] != heights[2] || heights[0] != heights[1], "Each mode sizes the sheet to what it shows (\(heights))")
            try expect(rig.content.frame.width == ResizePanel.sheetWidth, "The sheet stays \(ResizePanel.sheetWidth) pt wide")

            // Limit by: the choice persists in the session and drives the submission.
            mode.choose(2)
            guard let limitBy: GlassChoiceGroup = private_(rig.resize, "limitControl"), let limitField: NSTextField = private_(rig.resize, "limitField") else { throw Failure(description: "limit controls") }
            try expect(limitBy.buttons.map(\.title) == ResizePanelLimitMode.allCases.map(\.title) && limitBy.accessibilityLabel() == "Limit by" && limitBy.selectedIndex == 0,
                       "Limit by lists Longest side, Width and Height and starts on the first")
            limitField.stringValue = "500"
            rig.resize.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: limitField))
            for (index, mode, size) in [(1, ResizePanelLimitMode.width, CGSize(width: 500, height: 333)), (2, .height, CGSize(width: 750, height: 500)), (0, .greatest, CGSize(width: 500, height: 333))] {
                limitBy.choose(index)
                try expect(rig.state().limitMode == mode && limitBy.selectedIndex == index, "Choosing \(mode.title) is stored as the limit mode")
                try expect((try? rig.state().submission().size) == size, "…and the submission follows it: \(String(describing: try? rig.state().submission().size)) for \(mode.title)")
            }
            limitBy.choose(1); mode.choose(0); mode.choose(2)
            try expect(limitBy.selectedIndex == 1 && rig.state().limitMode == .width, "The limit choice survives leaving and re-entering the mode")
        }

        // Lock proportions: a checkbox-role toggle; its state is the session's.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let ratio: GlassChoiceButton = private_(rig.resize, "ratioButton") else { throw Failure(description: "lock button") }
            try expect(ratio.kind == .toggle && ratio.indicator == .checkbox && ratio.accessibilityRole() == .checkBox && ratio.title == "Lock proportions", "Lock proportions is a checkbox-role toggle")
            try expect(ratio.isChosen && rig.state().preserveRatio && (ratio.accessibilityValue() as? NSNumber) == 1, "…on by default, value 1")
            ratio.performClick(nil)
            try expect(!ratio.isChosen && !rig.state().preserveRatio && (ratio.accessibilityValue() as? NSNumber) == 0, "A click turns it off in the session (value 0)")
            ratio.performClick(nil)
            try expect(ratio.isChosen && rig.state().preserveRatio, "A second click turns it back on")
            guard let width: NSTextField = private_(rig.resize, "widthField"), let height: NSTextField = private_(rig.resize, "heightField") else { throw Failure(description: "fields") }
            ratio.performClick(nil)
            width.stringValue = "400"
            rig.resize.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: width))
            try expect(height.stringValue == "1011", "Unlocked, a width edit leaves the height alone")
            ratio.performClick(nil)
            try expect(ratio.isChosen && height.stringValue == "267", "Locking again recomputes the partner from the last edit (\(height.stringValue))")
        }

        // Anchor: cells draw from the command state, the arrows move the choice.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let mode: GlassChoiceGroup = private_(rig.resize, "modeControl"), let grid: ResizeAnchorGrid = private_(rig.resize, "anchorGrid") else { throw Failure(description: "grid") }
            mode.choose(1)
            try expect(plate(of: grid) != nil && plate(of: grid)?.identifier?.rawValue == "ResizeAnchorPlate", "The anchor grid sits on one glass plate")
            let rest = grid.style(of: .topLeft), chosen = grid.style(of: .center)
            try expect(rest.fill == nil && chosen.fill != nil && chosen.border != nil && chosen.borderWidth > 0 && chosen.strongText,
                       "The chosen cell is the command selected style (fill, border); a resting cell is plain")
            grid.setHovered(.topLeft)
            try expect(grid.style(of: .topLeft).fill != nil && grid.style(of: .topLeft).border == nil, "A hovered cell draws the hover fill")
            grid.setPressed(.topLeft)
            try expect(grid.style(of: .topLeft) != grid.style(of: .topLeft) || grid.pressed == .topLeft, "A pressed cell is tracked")
            grid.setHovered(nil); grid.setPressed(nil)
            grid.accessibility = ChromeAccessibility(reduceTransparency: false, increaseContrast: true, reduceMotion: false, differentiateWithoutColor: true)
            try expect(grid.style(of: .center).indicator && grid.style(of: .center).borderWidth > 0, "Differentiate Without Color adds the capsule on the chosen cell")
            grid.accessibility = .none
            for (code, expected) in [(124, ResizePanelAnchor.middleRight), (125, .bottomRight), (123, .bottomCenter), (126, .center)] as [(UInt16, ResizePanelAnchor)] {
                grid.keyDown(with: try key(code))
                try expect(grid.anchor == expected && rig.state().anchor == expected, "Arrow \(code) moves the anchor to \(expected.title)")
            }
            try expect(grid.accessibilityRole() == .radioGroup && grid.accessibilityLabel() == "Crop anchor" && grid.accessibilityChildren()?.count == 9, "The grid stays a named radio group of nine cells")
        }

        // Preset: the glass face opens a choice panel over the pop-up model; choosing a row applies the preset.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let face: GlassChoiceButton = private_(rig.resize, "presetFace"), let choices: MenuChoicePanel = private_(rig.resize, "presetChoices"),
                  let popup: NSPopUpButton = private_(rig.resize, "presetPopup"), let width: NSTextField = private_(rig.resize, "widthField"),
                  let save: GlassChoiceButton = private_(rig.resize, "savePresetButton"), let remove: GlassChoiceButton = private_(rig.resize, "removePresetButton"),
                  let name: NSTextField = private_(rig.resize, "presetName") else { throw Failure(description: "preset controls") }
            choices.host.presenter = { _, _ in }
            try expect(face.title == "Custom size" && face.accessibilityLabel() == "Size preset" && face.kind == .submenu && face.indicator == .chevron && !face.isHiddenOrHasHiddenAncestor,
                       "The preset is a glass face with a chevron, named Size preset, showing the pop-up's selection")
            try expect(popup.menu?.items.count == 1 + ResizePreset.builtins.count && popup.superview == nil, "The pop-up stays the model and is not on screen")
            try expect(!save.isEnabled && !remove.isEnabled && name.isEnabled, "Custom size: Save and Remove are off")
            // Pointer open: the panel lists Custom size and every built-in, Custom size chosen.
            face.performClick(nil)
            try expect(choices.host.isShown && choices.rows.count == 1 + ResizePreset.builtins.count, "Pressing the face opens the preset panel (\(choices.rows.count) rows)")
            try expect(choices.rows.first?.isChosen == true && choices.rows.filter(\.isChosen).count == 1 && choices.rows.allSatisfy { $0.kind == .option }, "…with the current preset the one chosen option")
            try expect(choices.host.plates.count == 1 && choices.host.container.identifier?.rawValue.hasPrefix("GlassChoicePanel") == true, "…on one plate in one glass container")
            face.performClick(nil)
            try expect(!choices.host.isShown, "A second press on the face while its panel is shown closes it instead of reopening")
            // A real pointer press on the face while open: the host swallows it (so the face cannot reopen the panel) and closes.
            face.performClick(nil)
            let centre = face.convert(NSPoint(x: face.bounds.midX, y: face.bounds.midY), to: nil)
            try expect(choices.host.isShown && choices.host.handleMouseDown(in: face.window, at: centre) && !choices.host.isShown,
                       "A pointer press on the opener while open is consumed and only closes")
            // Choose a built-in through the panel.
            guard let preset = ResizePreset.builtins.first(where: { $0.name == "Ad: Leaderboard" }) else { throw Failure(description: "builtin") }
            rig.resize.showPresetChoices(keyboard: false)
            guard let row = choices.rows.first(where: { $0.title == preset.name }) else { throw Failure(description: "leaderboard row") }
            choices.activate(row)
            try expect(!choices.host.isShown, "Choosing a row closes the panel")
            try expect(rig.state().widthText == "728" && rig.state().heightText == "90" && (try rig.state().submission().size) == preset.size,
                       "Choosing Ad: Leaderboard applies it to the session: \(rig.state().widthText) x \(rig.state().heightText)")
            try expect(width.stringValue == "728" && face.title == preset.name && popup.titleOfSelectedItem == preset.name, "The sheet shows the preset and the face names it")
            try expect(!save.isEnabled && !remove.isEnabled && !name.isEnabled, "A built-in preset is read-only: Save, Remove and the name field are off")
            // Keyboard: Down opens with the chosen row focused; Down then Return picks the next row.
            let consumed = face.keyHandler?(try key(125)) ?? false
            try expect(consumed && choices.host.isShown && choices.focusedRow?.title == preset.name, "Down on the face opens the panel with the chosen row focused")
            _ = choices.handleKey(try key(125))
            _ = choices.handleKey(try key(36, "\r"))
            try expect(!choices.host.isShown && face.title == "Ad: Banner (Full)", "Down, Return chooses the row after the chosen one: \(face.title)")
            // Add a custom preset: it is editable, Save and Remove come on, and removing returns to Custom size.
            guard let addButton = descendants(rig.content).compactMap({ $0 as? GlassChoiceButton }).first(where: { $0.title == "Add Preset" }) else { throw Failure(description: "add") }
            addButton.performClick(nil)
            try expect(face.title == "Ad: Banner (Full) Copy" && save.isEnabled && remove.isEnabled && name.isEnabled, "Adding from a built-in makes an editable copy: Save and Remove on (\(face.title))")
            remove.performClick(nil)
            try expect(face.title == "Custom size" && !save.isEnabled && !remove.isEnabled, "Remove returns to Custom size with Save and Remove off")
            // VoiceOver press opens it too.
            try expect(face.accessibilityPerformPress() && choices.host.isShown, "VoiceOver pressing the face opens the panel")
            choices.host.close()
        }

        // A malformed saved-presets blob still shows its error, and Save and Remove stay off.
        do {
            let rig = Rig(seed: { $0.set("not an array", forKey: ResizePresetKeys.defaults) }); defer { rig.close() }
            guard let error: NSTextField = private_(rig.resize, "errorLabel"), let save: GlassChoiceButton = private_(rig.resize, "savePresetButton") else { throw Failure(description: "error label") }
            try expect(!error.isHidden && error.stringValue == "Error: " + ResizePresetError.malformedDefaults.localizedDescription && !save.isEnabled,
                       "Malformed defaults show the error on open: \(error.stringValue)")
        }

        // Manage: a chevron toggle that exposes its expanded state and grows the sheet.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let manage: GlassChoiceButton = private_(rig.resize, "presetDisclosure") else { throw Failure(description: "manage") }
            let before = rig.content.frame.height
            try expect(manage.kind == .toggle && manage.indicator == .chevron && manage.accessibilityLabel() == "Manage presets" && !manage.isAccessibilityExpanded(), "Manage is a collapsed chevron toggle")
            manage.performClick(nil)
            try expect(manage.isChosen && manage.isAccessibilityExpanded() && rig.content.frame.height > before, "A click expands it and the sheet grows")
            manage.performClick(nil)
            try expect(!manage.isChosen && !manage.isAccessibilityExpanded() && rig.content.frame.height == before, "A second click folds it back to the same height")
        }

        // Buttons: one trailing plate, OK the only tinted control, Return and keypad Enter = OK, Escape = Cancel, with a glass face focused.
        for (name, code, text, applies) in [("Return", UInt16(36), "\r", true), ("Enter", UInt16(76), "\u{3}", true), ("Escape", UInt16(53), "\u{1b}", false)] {
            let rig = Rig(); defer { rig.close() }
            let buttons = descendants(rig.content).compactMap { $0 as? GlassChoiceButton }
            guard let cancel = buttons.first(where: { $0.title == "Cancel" }), let apply = buttons.first(where: { $0.title == "Apply" }), let ok = buttons.first(where: { $0.title == "OK" }),
                  let face: GlassChoiceButton = private_(rig.resize, "presetFace"), let choices: MenuChoicePanel = private_(rig.resize, "presetChoices") else { throw Failure(description: "buttons") }
            try expect(plate(of: cancel) === plate(of: apply) && plate(of: apply) === plate(of: ok), "Cancel, Apply and OK share one glass plate")
            try expect(ok.isPrimary && !cancel.isPrimary && !apply.isPrimary && buttons.filter(\.isPrimary).count == 1, "OK is the only primary (tinted) control")
            try expect(rig.panel.defaultButtonCell === ok.cell && cancel.keyEquivalent == "\u{1b}", "OK is the default button; Escape is Cancel")
            choices.host.presenter = { _, _ in }
            try expect(rig.panel.makeFirstResponder(face) && rig.panel.firstResponder === face, "The keyboard is on the Preset face")
            let event = try key(code, text, window: rig.panel)
            if applies {
                // AppKit parks a Return key equivalent while a sheet is not on screen, so the sheet's own routing cannot be driven here: what is
                // proved is that the focused face does not take the key for itself (no panel opens, nothing is chosen) and that the window's
                // default button, which is what Return fires, is OK and applies.
                face.keyDown(with: event)
                try expect(!choices.host.isShown && rig.appliedBox.values.isEmpty, "\(name) on a focused face does not open the panel or act by itself")
                guard let cell = rig.panel.defaultButtonCell, cell.isEnabled else { throw Failure(description: "default cell") }
                cell.performClick(nil)
                try expect(rig.appliedBox.values.count == 1 && rig.appliedBox.values[0].0 == CGSize(width: 1517, height: 1011) && rig.panel.sheetParent == nil,
                           "\(name) runs the default button: OK applies once with the sheet's size and ends the sheet")
            } else {
                rig.panel.sendEvent(event)
                try expect(rig.appliedBox.values.isEmpty && rig.panel.sheetParent == nil, "\(name) with a glass face focused is Cancel: applies nothing and ends the sheet")
            }
        }

        // Escape with the preset panel open closes only the panel; a second Escape is Cancel. Space and Down open a focused face.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let face: GlassChoiceButton = private_(rig.resize, "presetFace"), let choices: MenuChoicePanel = private_(rig.resize, "presetChoices") else { throw Failure(description: "face") }
            choices.host.presenter = { _, _ in }
            _ = rig.panel.makeFirstResponder(face)
            rig.panel.sendEvent(try key(49, " ", window: rig.panel))
            try expect(choices.host.isShown, "Space on the focused face opens the preset panel")
            choices.host.window.sendEvent(try key(53, "\u{1b}", window: choices.host.window))
            try expect(!choices.host.isShown && rig.panel.sheetParent === rig.parent && rig.appliedBox.values.isEmpty && !rig.isFinished,
                       "Escape with the panel open closes the panel; the sheet stays up and Cancel does not run")
            rig.panel.sendEvent(try key(125, "", window: rig.panel))
            try expect(choices.host.isShown && choices.focusedRow?.isChosen == true, "Down on the focused face opens the panel on the chosen row")
            choices.host.close()
            rig.panel.sendEvent(try key(53, "\u{1b}", window: rig.panel))
            try expect(rig.panel.sheetParent == nil && rig.appliedBox.values.isEmpty, "A second Escape (panel closed) runs Cancel and ends the sheet")
        }

        // Fonts, glass nesting and the key-view loop.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let mode: GlassChoiceGroup = private_(rig.resize, "modeControl") else { throw Failure(description: "mode") }
            for index in [1, 2, 0] {
                mode.choose(index)
                for view in descendants(rig.content) {
                    if let field = view as? NSTextField, !field.isHiddenOrHasHiddenAncestor { try expect((field.font?.pointSize ?? 0) >= 18, "Text '\(field.stringValue)' is at least 18 pt") }
                    if let button = view as? GlassChoiceButton, !button.isHiddenOrHasHiddenAncestor { try expect((button.titleLabel.font?.pointSize ?? 0) >= 20, "'\(button.title)' is 20 pt") }
                }
                let glass = descendants(rig.content).filter { $0 is NSGlassEffectView }
                try expect(glass.allSatisfy { view in glass.allSatisfy { $0 === view || !descendants($0).contains(view) } }, "Mode \(index): no glass inside glass")
            }
            // Tab walks Width, Height, Lock, Preset, Manage, Cancel, Apply, OK and the mode group's one stop, once each.
            mode.choose(0)
            let panel = rig.panel
            panel.recalculateKeyViewLoop()
            guard let width: NSTextField = private_(rig.resize, "widthField"), let ratio: GlassChoiceButton = private_(rig.resize, "ratioButton"),
                  let face: GlassChoiceButton = private_(rig.resize, "presetFace"), let manage: GlassChoiceButton = private_(rig.resize, "presetDisclosure"),
                  let limitField: NSTextField = private_(rig.resize, "limitField") else { throw Failure(description: "loop controls") }
            try expect(panel.initialFirstResponder === width && panel.firstResponder === width.currentEditor() || panel.firstResponder === width || panel.initialFirstResponder === width, "Focus starts in Width")
            var visited: [NSView] = [], next: NSView? = width
            while let view = next, !visited.contains(where: { $0 === view }), visited.count < 40 { visited.append(view); next = view.nextValidKeyView }
            let titles = visited.compactMap { ($0 as? GlassChoiceButton)?.title }
            try expect(titles.contains("Resize") && titles.contains("Lock proportions") && titles.contains("Cancel") && titles.contains("Apply") && titles.contains("OK") && titles.contains("Manage"),
                       "Tab reaches the glass choices: \(titles)")
            try expect(titles.filter { ["Resize", "Crop", "Limit"].contains($0) }.count == 1, "The mode group is one tab stop: \(titles)")
            try expect(visited.contains { $0 === ratio } && visited.contains { $0 === face } && visited.contains { $0 === manage } && !visited.contains { $0 === limitField }, "The loop skips what the mode hides")
            let order = [width, ratio, face, manage].compactMap { target in visited.firstIndex { $0 === target } }
            try expect(order == order.sorted() && order.count == 4, "Width, Lock, Preset, Manage come in reading order")
        }
    }

    fileprivate static func resize_state(_ panel: ResizePanel) -> ResizePanelState {
        guard let session: ResizePanelSession = private_(panel, "session") else { fatalError("session") }
        return session.state
    }
}
#endif
