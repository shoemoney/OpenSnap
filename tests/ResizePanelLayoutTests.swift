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
        do { try run(); try behaviour(); try externalTree(); print("ResizePanelLayoutTests: \(checks) checks passed") }
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
              let grid: ResizeAnchorGrid = private_(resize, "anchorGrid"), let presetFace: GlassPopUpButton = private_(resize, "presetPopup") else {
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
        try expect(find(NSPopUpButton.self, in: content) { !($0 is GlassPopUpButton) } == nil && find(NSSegmentedControl.self, in: content) == nil, "…and no native pop-up or segmented control anywhere on the sheet")
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
    /// A key the way the application delivers it: the key window's key equivalents first (the default button's Return, Cancel's Escape), and only
    /// when none takes it, the window's sendEvent to the focused control. The sheet is not on screen and the app is not active, so it is told it
    /// became key, which is what arms its default button's Return. This is window and responder routing on an offscreen, inactive sheet; it is not
    /// proof of on-screen or active-application behaviour. It also pre-routes Return to the default button, so a test of what a control does
    /// with Return itself must use `sendEvent` alone.
    private static func deliver(_ event: NSEvent, to window: NSWindow) {
        window.becomeKey()
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }
    private static func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    /// A key-down as AppKit builds it: arrows carry their private-use character and the numeric-pad and function flags; every event has characters.
    private static func key(_ code: UInt16, _ text: String = "", window: NSWindow? = nil) throws -> NSEvent {
        let arrows: [UInt16: UInt32] = [123: 0xF702, 124: 0xF703, 125: 0xF701, 126: 0xF700]
        let characters = arrows[code].flatMap { UnicodeScalar($0) }.map { String($0) } ?? text
        let flags: NSEvent.ModifierFlags = arrows[code] == nil ? [] : [.numericPad, .function]
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
                                           characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { throw Failure(description: "key event") }
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

    /// The sheet as an external client sees it, walked from its window down: the action plates are named groups of their buttons, the choices on
    /// unlabelled single-control plates (Lock proportions) are reachable, and every parent agrees with the tree.
    private static func externalTree() throws {
        let suite = "OpenSnapResizeTree." + UUID().uuidString
        let defaults = TestDefaults(name: suite)
        defer { TestDefaults.dispose(defaults, name: suite) }
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        parent.isReleasedWhenClosed = false
        var applied: [(CGSize, Bool, CGPoint)] = []
        let resize = ResizePanel(session: ResizePanelSession(size: CGSize(width: 1517, height: 1011), onApply: { applied.append(($0, $1, $2)) }),
                                 presets: ResizePresetStore(defaults: defaults))
        resize.show(attachedTo: parent)
        guard let panel: NSPanel = private_(resize, "panel"), let content = panel.contentView, let mode: GlassChoiceGroup = private_(resize, "modeControl") else {
            throw Failure(description: "the sheet exists")
        }
        content.layoutSubtreeIfNeeded()
        var tree = AXTree.walk(panel)
        func need(_ role: NSAccessibility.Role, _ label: String) throws -> AXTree.Node {
            guard let node = tree.find(role, label) else { throw Failure(description: "\(role.rawValue) \"\(label)\" is reachable from the sheet's window. Tree:\n\(tree.outline)") }
            return node
        }
        let actions = try need(.group, "Resize actions")
        try expectTree(tree.children(of: actions).map { $0.label ?? "" } == ["Cancel", "Apply", "OK"] && tree.children(of: actions).allSatisfy { $0.role == .button },
                       "the Resize actions plate shows Cancel, Apply and OK in order: \(tree.children(of: actions).map { $0.label ?? "" })")
        let modeGroup = try need(.radioGroup, mode.accessibilityLabel() ?? "")
        try expectTree(tree.children(of: modeGroup).map { $0.label ?? "" } == ["Resize", "Crop", "Limit"] && tree.children(of: modeGroup).compactMap { $0.number } == [1, 0, 0],
                       "the mode group shows its three radio buttons, Resize chosen: \(tree.children(of: modeGroup).map { "\($0.label ?? "") \(String(describing: $0.value))" })")
        let lock = try need(.checkBox, "Lock proportions")
        try expectTree(lock.number != nil, "the Lock proportions toggle on its own unlabelled plate is reachable, with a value")
        _ = try need(.checkBox, "Manage presets")
        _ = try need(.popUpButton, "Size preset")
        // Choosing a mode from outside moves the tree: Crop adds its anchor grid.
        let crop = try need(.radioButton, "Crop")
        try expectTree(AXTree.press(crop), "AXPress on the Crop radio button is performed")
        content.layoutSubtreeIfNeeded()
        tree = AXTree.walk(panel)
        _ = try need(.radioGroup, "Crop anchor")
        try expectTree(tree.find(.radioButton, "Crop")?.number == 1 && mode.selectedIndex == 1, "AXPress chose Crop (the group says so)")
        let problems = tree.parentProblems()
        try expectTree(problems.isEmpty, "every parent agrees with the tree and leads back to the window: \(problems.prefix(3))")
    }

    private static func expectTree(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

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

        // Preset: the glass pop-up opens a choice panel over its own menu; choosing a row applies the preset.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let face: GlassPopUpButton = private_(rig.resize, "presetPopup"), let width: NSTextField = private_(rig.resize, "widthField"),
                  let save: GlassChoiceButton = private_(rig.resize, "savePresetButton"), let remove: GlassChoiceButton = private_(rig.resize, "removePresetButton"),
                  let name: NSTextField = private_(rig.resize, "presetName") else { throw Failure(description: "preset controls") }
            let choices = face.choicePanel
            choices.host.presenter = { _, _ in }
            try expect(face.faceTitle == "Custom size" && face.accessibilityLabel() == "Size preset" && face.accessibilityRole() == .popUpButton && face.accessibilityValue() as? String == "Custom size" && !face.isHiddenOrHasHiddenAncestor,
                       "The preset is a glass pop-up button named Size preset whose value is the selection")
            try expect(face.menu?.items.count == 1 + ResizePreset.builtins.count && face.superview is ChromeFillCell && plate(of: face) != nil && !(face.menu is NSMenu && face.menu(for: try key(0)) != nil), "It sits on a glass plate and has no contextual menu")
            try expect(!save.isEnabled && !remove.isEnabled && name.isEnabled, "Custom size: Save and Remove are off")
            // Pointer open: the panel lists Custom size and every built-in, Custom size chosen.
            face.performClick(nil)
            try expect(choices.host.isShown && choices.rows.count == 1 + ResizePreset.builtins.count, "Pressing the pop-up opens the preset panel (\(choices.rows.count) rows)")
            try expect(choices.rows.first?.isChosen == true && choices.rows.filter(\.isChosen).count == 1 && choices.rows.allSatisfy { $0.kind == .option && $0.accessibilityRole() == .radioButton },
                       "…with the current preset the one chosen option, every row a radio button")
            try expect(choices.rows.map { ($0.accessibilityValue() as? NSNumber)?.intValue ?? -1 } == [1] + Array(repeating: 0, count: ResizePreset.builtins.count), "…value 1 on the chosen row and 0 on the others")
            try expect(choices.host.plates.count == 1 && choices.host.container.identifier?.rawValue.hasPrefix("GlassChoicePanel") == true, "…on one plate in one glass container")
            face.performClick(nil)
            try expect(!choices.host.isShown, "A second press on the pop-up while its panel is shown closes it instead of reopening")
            // A real pointer press on the opener while open: the host swallows it (so it cannot reopen the panel) and closes.
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
            try expect(width.stringValue == "728" && face.faceTitle == preset.name, "The sheet shows the preset and the pop-up names it")
            try expect(!save.isEnabled && !remove.isEnabled && !name.isEnabled, "A built-in preset is read-only: Save, Remove and the name field are off")
            // Keyboard: Down opens with the chosen row focused; Down then Return picks the next row.
            face.keyDown(with: try key(125))
            try expect(choices.host.isShown && choices.focusedRow?.title == preset.name, "Down on the pop-up opens the panel with the chosen row focused")
            _ = choices.handleKey(try key(125))
            _ = choices.handleKey(try key(36, "\r"))
            try expect(!choices.host.isShown && face.faceTitle == "Ad: Banner (Full)", "Down, Return chooses the row after the chosen one: \(face.faceTitle)")
            // Add a custom preset: it is editable, Save and Remove come on, and removing returns to Custom size.
            guard let addButton = descendants(rig.content).compactMap({ $0 as? GlassChoiceButton }).first(where: { $0.title == "Add Preset" }) else { throw Failure(description: "add") }
            addButton.performClick(nil)
            try expect(face.faceTitle == "Ad: Banner (Full) Copy" && save.isEnabled && remove.isEnabled && name.isEnabled, "Adding from a built-in makes an editable copy: Save and Remove on (\(face.faceTitle))")
            remove.performClick(nil)
            try expect(face.faceTitle == "Custom size" && !save.isEnabled && !remove.isEnabled, "Remove returns to Custom size with Save and Remove off")
            // VoiceOver press opens it too.
            try expect(face.accessibilityPerformPress() && choices.host.isShown, "VoiceOver pressing the pop-up opens the panel")
            choices.host.close()
        }

        // No route to the preset pop-up reaches the native dropdown. In a sheet with a default button, Return and Enter are left for OK.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let popup: GlassPopUpButton = private_(rig.resize, "presetPopup") else { throw Failure(description: "popup") }
            let choices = popup.choicePanel
            choices.host.presenter = { _, _ in }
            var tracking = 0
            let token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { _ in tracking += 1 }
            defer { NotificationCenter.default.removeObserver(token); choices.host.close() }
            func mouse(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
                guard let event = NSEvent.mouseEvent(with: type, location: popup.convert(NSPoint(x: 5, y: 5), to: nil), modifierFlags: flags, timestamp: 0, windowNumber: rig.panel.windowNumber,
                                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw Failure(description: "mouse event") }
                return event
            }
            func opens(_ route: String, _ act: () throws -> Void) throws {
                try act()
                try expect(choices.host.isShown, "Preset pop-up: \(route) opens the glass panel")
                choices.host.close()
            }
            try expect(popup.menu(for: try mouse(.rightMouseDown)) == nil && popup.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformShowMenu)),
                       "There is no contextual menu to pop up, and Show Menu is offered")
            try opens("mouse down") { popup.mouseDown(with: try mouse(.leftMouseDown)) }
            try opens("right mouse down") { popup.rightMouseDown(with: try mouse(.rightMouseDown)) }
            try opens("Control-click") { popup.mouseDown(with: try mouse(.leftMouseDown, .control)) }
            try opens("other mouse down") { popup.otherMouseDown(with: try mouse(.otherMouseDown)) }
            try opens("performClick") { popup.performClick(nil) }
            try opens("AXPress") { try expect(popup.accessibilityPerformPress(), "AXPress succeeds") }
            try opens("AXShowMenu") { try expect(popup.accessibilityPerformShowMenu(), "AXShowMenu succeeds") }
            try opens("the context-menu command") { popup.showContextMenuForSelection(nil) }
            _ = rig.panel.makeFirstResponder(popup)
            for (code, text, label) in [(UInt16(49), " ", "Space"), (125, "", "Down"), (126, "", "Up")] {
                try opens(label) { deliver(try key(code, text, window: rig.panel), to: rig.panel) }
            }
            // Return and keypad Enter belong to the default button (OK) while the sheet has one, as with a native pop-up.
            for (code, text, label) in [(UInt16(36), "\r", "Return"), (76, "\u{3}", "Enter")] {
                popup.keyDown(with: try key(code, text, window: rig.panel))
                try expect(!choices.host.isShown, "\(label) on the focused pop-up does not open the panel: it is left for OK")
            }
            popup.keyDown(with: try key(0, "a"))
            try expect(!choices.host.isShown && tracking == 0, "Type-ahead opens nothing and no native menu tracking began on any route (\(tracking))")
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

        // Buttons: one trailing plate, OK the only tinted control, Return and keypad Enter = OK, Escape = Cancel. The keys take the route a real
        // key takes (the key window's key equivalents, then its sendEvent to the focused control), with the keyboard on each kind of glass
        // control in turn.
        do {
            let rig = Rig(); defer { rig.close() }
            let buttons = descendants(rig.content).compactMap { $0 as? GlassChoiceButton }
            guard let cancel = buttons.first(where: { $0.title == "Cancel" }), let apply = buttons.first(where: { $0.title == "Apply" }), let ok = buttons.first(where: { $0.title == "OK" }) else { throw Failure(description: "buttons") }
            try expect(plate(of: cancel) === plate(of: apply) && plate(of: apply) === plate(of: ok), "Cancel, Apply and OK share one glass plate")
            try expect(ok.isPrimary && !cancel.isPrimary && !apply.isPrimary && buttons.filter(\.isPrimary).count == 1, "OK is the only primary (tinted) control")
            try expect(rig.panel.defaultButtonCell === ok.cell && cancel.keyEquivalent == "\u{1b}", "OK is the default button; Escape is Cancel")
        }
        for focus in ["Apply", "lock toggle", "preset pop-up", "manage toggle", "limit group", "mode group"] {
            for (name, code, text, applies) in [("Return", UInt16(36), "\r", true), ("Enter", UInt16(76), "\u{3}", true), ("Escape", UInt16(53), "\u{1b}", false)] {
                let rig = Rig(); defer { rig.close() }
                guard let mode: GlassChoiceGroup = private_(rig.resize, "modeControl"), let limit: GlassChoiceGroup = private_(rig.resize, "limitControl"),
                      let lock: GlassChoiceButton = private_(rig.resize, "ratioButton"), let popup: GlassPopUpButton = private_(rig.resize, "presetPopup"),
                      let manage: GlassChoiceButton = private_(rig.resize, "presetDisclosure"),
                      let apply = descendants(rig.content).compactMap({ $0 as? GlassChoiceButton }).first(where: { $0.title == "Apply" }) else { throw Failure(description: "controls") }
                popup.choicePanel.host.presenter = { _, _ in }
                let target: NSView
                switch focus {
                case "mode group": target = mode.buttons[mode.selectedIndex]
                case "limit group": mode.choose(2); target = limit.buttons[limit.selectedIndex]
                case "lock toggle": target = lock
                case "preset pop-up": target = popup
                case "manage toggle": target = manage
                default: target = apply
                }
                try expect(rig.panel.makeFirstResponder(target) && rig.panel.firstResponder === target, "The keyboard is on the \(focus)")
                let before = (mode.selectedIndex, limit.selectedIndex, lock.isChosen, manage.isChosen)
                deliver(try key(code, text, window: rig.panel), to: rig.panel)
                let after = (mode.selectedIndex, limit.selectedIndex, lock.isChosen, manage.isChosen)
                if applies {
                    // Return reaches the window's default button before the focused control sees it, so OK runs and nothing else moves.
                    try expect(rig.appliedBox.values.count == 1 && rig.panel.sheetParent == nil && before == after && !popup.choicePanel.host.isShown,
                               "\(name) with the \(focus) focused runs OK (applied \(rig.appliedBox.values.count), sheet \(rig.panel.sheetParent == nil ? "ended" : "up"), choices \(before) -> \(after))")
                } else {
                    try expect(rig.appliedBox.values.isEmpty && rig.panel.sheetParent == nil, "\(name) with the \(focus) focused is Cancel: applies nothing and ends the sheet")
                }
            }
        }

        // A glass group in a sheet with a default button does not take Return or Enter for itself. This one goes through the window's sendEvent
        // ONLY (no key-equivalent pre-call, so the default button cannot have taken the key first), with the keyboard on a segment that is not the
        // chosen one: a group that took the key would choose it and the mode would change.
        do {
            for (name, code, text) in [("Return", UInt16(36), "\r"), ("Enter", UInt16(76), "\u{3}")] {
                let rig = Rig(); defer { rig.close() }
                guard let mode: GlassChoiceGroup = private_(rig.resize, "modeControl") else { throw Failure(description: "mode") }
                try expect(rig.panel.makeFirstResponder(mode.buttons[1]) && rig.panel.firstResponder === mode.buttons[1] && mode.selectedIndex == 0, "The keyboard is on the Crop segment while Resize is chosen")
                rig.panel.sendEvent(try key(code, text, window: rig.panel))
                try expect(mode.selectedIndex == 0 && rig.state().mode == .resize, "\(name) reaching the group through sendEvent does not choose the focused segment (mode \(rig.state().mode))")
            }
            let rig = Rig(); defer { rig.close() }
            guard let mode: GlassChoiceGroup = private_(rig.resize, "modeControl") else { throw Failure(description: "mode") }
            _ = rig.panel.makeFirstResponder(mode.buttons[1])
            rig.panel.sendEvent(try key(49, " ", window: rig.panel))
            try expect(mode.selectedIndex == 1, "…while Space through the same route does choose it")
        }

        // Arrow keys in a glass group move the choice and the keyboard goes with it: the next arrow moves again. Real arrow events carry the
        // numeric-pad and function flags.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let mode: GlassChoiceGroup = private_(rig.resize, "modeControl"), let limit: GlassChoiceGroup = private_(rig.resize, "limitControl") else { throw Failure(description: "groups") }
            func arrow(_ code: UInt16) throws -> NSEvent { try key(code, window: rig.panel) }
            try expect(rig.panel.makeFirstResponder(mode.buttons[0]), "The keyboard is on the chosen mode segment")
            deliver(try arrow(124), to: rig.panel)
            try expect(mode.selectedIndex == 1 && rig.state().mode == .crop && rig.panel.firstResponder === mode.buttons[1], "→ chooses Crop and the keyboard stays on the Crop segment (\(String(describing: rig.panel.firstResponder)))")
            deliver(try arrow(124), to: rig.panel)
            try expect(mode.selectedIndex == 2 && rig.state().mode == .limit && rig.panel.firstResponder === mode.buttons[2], "A second → moves again, to Limit, and the keyboard follows")
            deliver(try arrow(123), to: rig.panel)
            try expect(mode.selectedIndex == 1 && rig.panel.firstResponder === mode.buttons[1], "← moves back")
            deliver(try arrow(124), to: rig.panel)
            // Limit by is the same: the arrow chooses Width and the next one Height.
            try expect(rig.panel.makeFirstResponder(limit.buttons[0]), "The keyboard is on Longest side")
            deliver(try arrow(124), to: rig.panel)
            try expect(limit.selectedIndex == 1 && rig.state().limitMode == .width && rig.panel.firstResponder === limit.buttons[1], "→ in Limit by chooses Width and keeps the keyboard")
            deliver(try arrow(124), to: rig.panel)
            try expect(limit.selectedIndex == 2 && rig.state().limitMode == .height && rig.panel.firstResponder === limit.buttons[2], "…and again chooses Height")
            // Typing in a field still ends its editing when a choice changes: the field's text is committed and the field editor goes.
            guard let width: NSTextField = private_(rig.resize, "widthField") else { throw Failure(description: "width") }
            mode.choose(0)
            try expect(rig.panel.makeFirstResponder(width) && rig.panel.firstResponder is NSTextView, "The keyboard is in the Width field editor")
            mode.choose(1)
            try expect(!(rig.panel.firstResponder is NSTextView), "Choosing a mode while typing ends the field editor")
        }

        // Escape with the preset panel open closes only the panel; a second Escape is Cancel. Space and Down open a focused face.
        do {
            let rig = Rig(); defer { rig.close() }
            guard let face: GlassPopUpButton = private_(rig.resize, "presetPopup") else { throw Failure(description: "face") }
            let choices = face.choicePanel
            choices.host.presenter = { _, _ in }
            _ = rig.panel.makeFirstResponder(face)
            deliver(try key(49, " ", window: rig.panel), to: rig.panel)
            try expect(choices.host.isShown, "Space on the focused face opens the preset panel")
            choices.host.window.sendEvent(try key(53, "\u{1b}", window: choices.host.window))
            try expect(!choices.host.isShown && rig.panel.sheetParent === rig.parent && rig.appliedBox.values.isEmpty && !rig.isFinished,
                       "Escape with the panel open closes the panel; the sheet stays up and Cancel does not run")
            deliver(try key(125, "", window: rig.panel), to: rig.panel)
            try expect(choices.host.isShown && choices.focusedRow?.isChosen == true, "Down on the focused face opens the panel on the chosen row")
            choices.host.close()
            deliver(try key(53, "\u{1b}", window: rig.panel), to: rig.panel)
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
                for button in descendants(rig.content).compactMap({ $0 as? GlassChoiceButton }) where !button.isHiddenOrHasHiddenAncestor {
                    let needed = ceil(button.titleLabel.intrinsicContentSize.width)
                    try expect(needed <= button.titleLabel.frame.width + 0.5 && button.titleLabel.frame.maxX <= button.bounds.maxX + 0.5, "Mode \(index): '\(button.title)' is not truncated (\(needed) needed in \(button.titleLabel.frame.width))")
                }
                if let popup: GlassPopUpButton = private_(rig.resize, "presetPopup") {
                    let attributes: [NSAttributedString.Key: Any] = [.font: DesignTokens.Typography.font(.body)]
                    let room = popup.bounds.width - 2 * GlassChoiceButton.padding - GlassChoiceButton.gap - GlassChoiceButton.glyphSide
                    let longest = popup.itemTitles.map { ceil(($0 as NSString).size(withAttributes: attributes).width) }.max() ?? 0
                    try expect(longest <= room + 0.5, "Mode \(index): the preset pop-up shows its longest name whole (\(longest) in \(room))")
                }
                let glass = descendants(rig.content).filter { $0 is NSGlassEffectView }
                try expect(glass.allSatisfy { view in glass.allSatisfy { $0 === view || !descendants($0).contains(view) } }, "Mode \(index): no glass inside glass")
            }
            // Tab walks Width, Height, Lock, Preset, Manage, Cancel, Apply, OK and the mode group's one stop, once each.
            mode.choose(0)
            let panel = rig.panel
            panel.recalculateKeyViewLoop()
            guard let width: NSTextField = private_(rig.resize, "widthField"), let ratio: GlassChoiceButton = private_(rig.resize, "ratioButton"),
                  let face: GlassPopUpButton = private_(rig.resize, "presetPopup"), let manage: GlassChoiceButton = private_(rig.resize, "presetDisclosure"),
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
