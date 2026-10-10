// The Resize or Crop sheet's layout (F-J1-014): mode control and dimensions first, presets folded away, no dead band above the buttons,
// the buttons on the trailing edge in the standard order, and a 3 x 3 anchor grid for Crop. A sheet on an off-screen parent; nothing is ordered front.
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
        do { try run(); print("ResizePanelLayoutTests: \(checks) checks passed") }
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
              let mode: NSSegmentedControl = private_(resize, "modeControl"), let width: NSTextField = private_(resize, "widthField"),
              let grid: ResizeAnchorGrid = private_(resize, "anchorGrid"), let presetPopup: NSPopUpButton = private_(resize, "presetPopup") else {
            throw Failure(description: "the sheet and its controls exist")
        }
        func button(_ title: String) -> NSButton? { find(NSButton.self, in: content) { $0.title == title } }
        guard let cancel = button("Cancel"), let apply = button("Apply"), let ok = button("OK") else { throw Failure(description: "Cancel, Apply and OK exist") }
        func select(_ index: Int) {
            mode.selectedSegment = index
            _ = mode.target?.perform(mode.action, with: mode)
            content.layoutSubtreeIfNeeded()
        }
        func frame(_ view: NSView) -> NSRect { content.convert(view.bounds, from: view) }
        let inset: CGFloat = 28
        var heights: [CGFloat] = []

        for (index, name) in ["Resize", "Crop", "Limit"].enumerated() {
            select(index)
            heights.append(content.frame.height)
            // Mode first, then the dimensions (or the limit), then the preset row, then the buttons: top to bottom.
            let modeFrame = frame(mode), presetFrame = frame(presetPopup), okFrame = frame(ok)
            let first: NSView = index == 2 ? (find(NSTextField.self, in: content) { $0.accessibilityLabel() == "Size limit in pixels" } ?? width) : width
            try expect(modeFrame.minY > frame(first).maxY && frame(first).minY > presetFrame.maxY && presetFrame.minY > okFrame.maxY,
                       "\(name): mode control, then the dimensions, then presets, then the buttons, top to bottom")
            // No dead band: the buttons sit one inset above the bottom edge, and the sheet is exactly as tall as its content.
            try expect(abs(okFrame.minY - inset) < 1.5, "\(name): the buttons are \(inset) pt from the bottom edge, no blank band under or above them (\(okFrame.minY))")
            // Trailing edge, standard order.
            try expect(abs(okFrame.maxX - (content.frame.width - inset)) < 1.5, "\(name): OK ends on the trailing margin (\(okFrame.maxX) of \(content.frame.width))")
            try expect(frame(cancel).maxX < frame(apply).minX && frame(apply).maxX < okFrame.minX, "\(name): Cancel, Apply, OK left to right")
            try expect(panel.defaultButtonCell === ok.cell && cancel.keyEquivalent == "\u{1b}" && apply.keyEquivalent.isEmpty, "\(name): OK is the default, Escape is Cancel, Apply is plain")
            try expect(find(NSTextField.self, in: content) { $0.accessibilityLabel() == "Preset name" && !$0.isHiddenOrHasHiddenAncestor } == nil, "\(name): preset naming is folded away until asked for")
        }
        try expect(heights[0] < heights[1], "Resize is a shorter sheet than Crop: the sheet is as tall as what it shows (\(heights))")

        // Crop: a 3 x 3 grid, the centre by default, picked by the pointer's cell and the arrow keys.
        select(1)
        try expect(!grid.isHidden && grid.anchor == .center && ResizePanelAnchor.allCases.count == 9, "Crop shows a 3 x 3 anchor grid on the centre")
        try expect(find(NSPopUpButton.self, in: content) { $0.accessibilityLabel() == "Crop anchor" } == nil, "…and no anchor pop-up")
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
        try expect(content.frame.height > calm && abs(frame(ok).minY - inset) < 1.5, "The sheet grows to hold the message and the buttons stay one inset from the bottom (\(content.frame.height) vs \(calm))")
        width.stringValue = "400"
        resize.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: width))
        try expect(errorLabel.isHidden && content.frame.height == calm, "Typing a valid size takes the message and its room away again")
        if let parentSheet = parent.attachedSheet { parent.endSheet(parentSheet) }
    }

    private static func resize_state(_ panel: ResizePanel) -> ResizePanelState {
        guard let session: ResizePanelSession = private_(panel, "session") else { fatalError("session") }
        return session.state
    }
}
#endif
