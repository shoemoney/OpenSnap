// OSN-071 round 3: every focusable control draws the app's token focus ring (StateStyles.focusRingColor, >= 3:1), never AppKit's system ring
// (pale 1.4:1 on a light window, olive on a dark one). Walks the focusable controls of the Resize sheet, the destination form and a glass
// choices panel, focuses each one that rings itself and reads the ring it drew; windows are never ordered front.
// Built with -D BASELINE_PROOF it keeps only the checks the old code can answer, to prove they fail before the fix.
#if TOKEN_FOCUS_RING_TESTS
import AppKit

@main
@MainActor
private enum TokenFocusRingTests {
    typealias P = DesignTokens.Palette
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(description: message) }
        checks += 1
    }
    private static func private_<T>(_ object: Any, _ name: String, as: T.Type = T.self) -> T? {
        Mirror(reflecting: object).children.first { $0.label == name }.flatMap { $0.value as? T }
    }

    /// Everything in `root` the keyboard can focus: an editable field, a pop-up, the anchor grid. Selectable labels and the field editor are not controls.
    static func focusable(in root: NSView) -> [NSView] {
        var found: [NSView] = []
        func walk(_ view: NSView) {
            let isFocusControl: Bool
            if view is NSText { isFocusControl = false }
            else if let field = view as? NSTextField { isFocusControl = field.isEditable }
            else { isFocusControl = view.acceptsFirstResponder && !(view is NSScrollView) }
            if isFocusControl && !view.isHiddenOrHasHiddenAncestor { found.append(view) }
            for child in view.subviews { walk(child) }
        }
        walk(root)
        return found
    }

    static func main() {
        _ = NSApplication.shared
        KeyboardNavigation.fullKeyboardAccess = { true }
        do {
            try resizeSheet(); try destinationForm(); try choicesPanel(); try dragWellAndPrompt(); try sizeControls()
            print("TokenFocusRingTests: \(checks) checks passed")
        } catch { print("FAIL \(error)"); exit(1) }
    }

    /// The ring colour AppKit would use is the system's; the token ring is the palette role for the arm. Their contrast against the window is the number.
    private static func contrast(of color: NSColor, on surface: NSColor, arm: P.Arm) -> CGFloat {
        P.contrastRatio(color, P.rgb(P.resolve(surface, arm: arm)).rgb)
    }

    private static func sameColor(_ a: NSColor?, _ b: NSColor) -> Bool {
        guard let a = a?.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.003 && abs(a.greenComponent - b.greenComponent) < 0.003 && abs(a.blueComponent - b.blueComponent) < 0.003
    }

    /// No control uses the system ring; every one that rings itself draws the token colour once focused, in light and dark.
    private static func audit(_ controls: [NSView], in window: NSWindow, root: NSView, surface: String) throws {
        try expect(!controls.isEmpty, "\(surface): found focusable controls")
        for control in controls {
            try expect(control.focusRingType == .none, "\(surface): \(type(of: control)) draws AppKit's system focus ring (focusRingType \(control.focusRingType.rawValue))")
        }
        #if !BASELINE_PROOF
        for (name, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            root.appearance = appearance
            let arm: P.Arm = name == "light" ? .aqua : .darkAqua
            for control in controls {
                guard let ringed = control as? TokenFocusRinged else {
                    // The only other kind of control here rings through its own state plate, which is the same token.
                    try expect(control is CommandButton || control is SizePresetButton, "\(surface): \(type(of: control)) is neither a token-ringed control nor a chrome command")
                    continue
                }
                try expect(window.makeFirstResponder(control), "\(surface): \(type(of: control)) takes focus")
                let ring = ringed.tokenRing
                ring.refresh()
                try expect(ring.isFocused && !ring.layer.isHidden, "\(surface): focusing \(type(of: control)) shows its ring")
                let expected = StateStyles.focusRingColor(highContrast: false, appearance: appearance)
                try expect(sameColor(ring.layer.strokeColor.flatMap(NSColor.init(cgColor:)), expected), "\(surface): the \(name) ring is the token colour")
                let ratio = contrast(of: expected, on: P.Surface.window, arm: arm)
                try expect(ratio >= 3, "\(surface): the \(name) ring is \(ratio):1 on the window, needs 3:1")
                try expect(ring.layer.lineWidth == StateStyles.focusRingWidth, "\(surface): the ring is \(StateStyles.focusRingWidth) pt")
                _ = window.makeFirstResponder(nil)
                try expect(ring.layer.isHidden, "\(surface): the ring leaves with the focus")
            }
        }
        #endif
    }

    private static func resizeSheet() throws {
        let suite = "OpenSnapTokenRing." + UUID().uuidString
        let defaults = TestDefaults(name: suite)
        defer { TestDefaults.dispose(defaults, name: suite) }
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        parent.isReleasedWhenClosed = false
        let resize = ResizePanel(session: ResizePanelSession(size: CGSize(width: 1517, height: 1011), onApply: { _, _, _ in }), presets: ResizePresetStore(defaults: defaults))
        resize.show(attachedTo: parent)
        guard let panel: NSPanel = private_(resize, "panel"), let content = panel.contentView, let mode: GlassChoiceGroup = private_(resize, "modeControl") else {
            throw Failure(description: "the sheet exists")
        }
        // Crop shows the anchor grid.
        mode.choose(1); content.layoutSubtreeIfNeeded()
        let controls = focusable(in: content)
        try expect(controls.contains { $0 is ResizeAnchorGrid }, "Resize sheet: the anchor grid is a focusable control")
        try expect(controls.contains { $0 is NSTextField }, "Resize sheet: the dimension fields are focusable controls")
        try audit(controls, in: panel, root: content, surface: "Resize sheet")
    }

    private static func destinationForm() throws {
        var s3 = PublishingSettings(); s3.endpoint = "https://s3.example.com"; s3.publicBaseURL = "https://cdn.example.com"
        let view = PublishingDestinationsView(editing: PublishingDestination(name: "Example S3", settings: s3), width: PublishingDestinationsView.sheetWidth)
        view.frame = NSRect(x: 0, y: 0, width: PublishingDestinationsView.sheetWidth, height: 760)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = view
        view.layoutSubtreeIfNeeded()
        let controls = focusable(in: view)
        let fields = controls.compactMap { $0 as? NSTextField }
        try expect(fields.count >= 5, "Destination form: its text fields are focusable controls (found \(fields.count))")
        try audit(controls, in: window, root: view, surface: "Destination form")
    }

    /// The editor's drag well and the one-line prompt's field (Snap from Link) ring with the token too.
    private static func dragWellAndPrompt() throws {
        let well = DragExportView(frame: NSRect(x: 20, y: 20, width: 115, height: 50))
        let field = TokenTextField(string: "https://"); field.frame = NSRect(x: 20, y: 100, width: 300, height: 28)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = content
        content.addSubview(well); content.addSubview(field)
        content.layoutSubtreeIfNeeded()
        try audit([well, field], in: window, root: content, surface: "Drag well and prompt")
    }

    /// The Size pill, the Size panel's track and its five presets, and the PNG | JPG toggle: all of them drew AppKit's `.exterior` ring before.
    private static func sizeControls() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = content
        let slider = BezelSizeSlider(frame: NSRect(x: 20, y: 440, width: 48, height: 36))
        let panel = SizePopoverContent(slider: slider)
        let toggle = SegmentedToggle(titles: ["PNG", "JPG"])
        toggle.frame = NSRect(x: 20, y: 380, width: 130, height: 36)
        content.addSubview(slider); content.addSubview(toggle)
        panel.trackView.removeFromSuperview(); panel.trackView.frame = NSRect(x: 20, y: 300, width: 288, height: 36); content.addSubview(panel.trackView)
        for (index, preset) in panel.presetButtons.enumerated() {
            preset.removeFromSuperview(); preset.translatesAutoresizingMaskIntoConstraints = true
            preset.frame = NSRect(x: 20 + CGFloat(index) * 56, y: 240, width: 48, height: 36); content.addSubview(preset)
        }
        content.layoutSubtreeIfNeeded()
        let ringed: [NSView] = [slider, panel.trackView, toggle]
        try audit(ringed + panel.presetButtons, in: window, root: content, surface: "Size controls")
        #if !BASELINE_PROOF
        for preset in panel.presetButtons {
            try expect(window.makeFirstResponder(preset), "a Size preset takes focus")
            try expect(!preset.plate.ringLayer.isHidden, "a focused Size preset shows the state plate's token ring")
            _ = window.makeFirstResponder(nil)
            try expect(preset.plate.ringLayer.isHidden, "the preset ring leaves with the focus")
        }
        // OSN-071 r4 (S54): the Size panel opens outside the choices presenter, so its pill kept its ring beside the focused row: two rings.
        // The pill keeps its ring while it holds the keyboard alone, gives it up while a row of the panel holds it, and has it back on close.
        let opener = BezelSizeSlider(frame: NSRect(x: 20, y: 140, width: 48, height: 36))
        content.addSubview(opener)
        opener.panelSetup = { host in
            host.presenter = { _, _ in }
            host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1440, height: 1000)
            host.keyStateProbe = { false }
        }
        try expect(window.makeFirstResponder(opener) && opener.tokenRing.isVisible, "the Size pill rings while focused")
        opener.showPopover()
        guard let host = opener.panel, let sizePanel = opener.popoverContent, host.isShown else { throw Failure(description: "the Size panel opens") }
        try expect(opener.tokenRing.isVisible, "the pill keeps its ring while it alone holds the keyboard")
        try expect(host.window.makeFirstResponder(sizePanel.presetButtons[0]) && !sizePanel.presetButtons[0].plate.ringLayer.isHidden, "a Size row takes focus and rings")
        try expect(!opener.tokenRing.isVisible, "one ring at a time: the pill gives up its ring while a Size row has the focus")
        _ = host.window.makeFirstResponder(nil)
        try expect(opener.tokenRing.isVisible, "the pill's ring is back when the focus leaves the rows")
        _ = host.window.makeFirstResponder(sizePanel.presetButtons[1])
        try expect(!opener.tokenRing.isVisible, "a row focused again hides the pill's ring again")
        host.close()
        try expect(opener.tokenRing.isVisible, "the pill takes its ring back when the Size panel closes")
        #endif
    }

    private static func choicesPanel() throws {
        let menu = NSMenu()
        for title in ["One", "Two", "Three"] { menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        let face = GlassPopUpButton(frame: NSRect(x: 20, y: 20, width: 200, height: 36), pullsDown: false)
        face.menu = menu
        let upload = GlassChoiceButton(title: "Upload", kind: .command, layout: .segment)
        upload.frame = NSRect(x: 20, y: 80, width: 120, height: 36)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = content
        content.addSubview(face); content.addSubview(upload)
        content.layoutSubtreeIfNeeded()
        try audit([face, upload], in: window, root: content, surface: "Glass choices")

        #if !BASELINE_PROOF
        // One ring at a time: while the choices a button opened are on screen, the button gives up its ring; closing gives it back.
        for opener in [face as NSView, upload] {
            let panel = (opener as? GlassPopUpButton)?.choicePanel ?? MenuChoicePanel(menu: menu, identifier: "Opened", accessibilityLabel: "Opened", kind: { _ in .option })
            panel.host.presenter = { _, _ in }
            panel.host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1440, height: 1000)
            panel.host.keyStateProbe = { false }
            func ringShown() -> Bool {
                if let popUp = opener as? GlassPopUpButton { return popUp.tokenRing.isVisible }
                return !((opener as? CommandButton)?.plate.ringLayer.isHidden ?? true)
            }
            try expect(window.makeFirstResponder(opener), "\(type(of: opener)) takes focus")
            try expect(ringShown(), "\(type(of: opener)) rings while focused")
            panel.present(relativeTo: opener, preferredEdge: .minY, keyboard: false)
            try expect(panel.host.isShown, "the choices opened")
            try expect(!ringShown(), "\(type(of: opener)) gives up its ring while its choices are open")
            panel.host.close()
            try expect(ringShown(), "\(type(of: opener)) takes its ring back when the choices close")
        }
        #endif
    }
}
#endif
