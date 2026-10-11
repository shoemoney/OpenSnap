// Offscreen controls, glass views and a never-ordered window only; no desktop windows and no input.
// Set OPENSNAP_FA_FONT_DIR (or keep build/fonts) to also run the layout with the Font Awesome glyph branch.
// xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete -target arm64-apple-macosx26.0 -D GLASS_CHROME_TESTS \
//   Sources/OriginalActionButton.swift Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift \
//   Sources/BezelDrawingControls.swift Sources/SVGPath.swift Sources/DocumentModel.swift Sources/GlassChrome.swift Sources/ModernEditorChrome.swift \
//   tests/GlassChromeTests.swift -o build/glass-chrome-tests
// build/glass-chrome-tests
#if GLASS_CHROME_TESTS
import AppKit

@MainActor
private final class ActionTarget: NSObject {
    var hits: [String] = []
    @objc func hide(_ sender: Any?) { hits.append("hide") }
    @objc func photos(_ sender: Any?) { hits.append("photos") }
    @objc func saveHistory(_ sender: Any?) { hits.append("saveHistory") }
    @objc func showHistory(_ sender: Any?) { hits.append("showHistory") }
    @objc func chooseTool(_ sender: Any?) { hits.append("tool:" + ((sender as? NSControl)?.identifier?.rawValue ?? "?")) }
    @objc func snap(_ sender: Any?) { hits.append("snap") }
    @objc func cancelFrame(_ sender: Any?) { hits.append("cancelFrame") }
    @objc func font(_ sender: Any?) { hits.append("font") }
    @objc func undo(_ sender: Any?) { hits.append("undo") }
    @objc func wipe(_ sender: Any?) { hits.append("wipe") }
    @objc func actualSize(_ sender: Any?) { hits.append("actualSize") }
    @objc func resize(_ sender: Any?) { hits.append("resize") }
    @objc func share(_ sender: Any?) { hits.append("share") }
    @objc func alternate(_ sender: Any?) { hits.append("alternate") }
    @objc func sizeChanged(_ sender: Any?) { hits.append("size") }
    @objc func formatChanged(_ sender: Any?) { hits.append("format:" + String((sender as? SegmentedToggle)?.selectedSegment ?? -1)) }
}

@MainActor
private final class PalettePressTarget: NSObject {
    var hits = 0
    var onPress: (() -> Void)?
    @objc func press(_ sender: Any?) { hits += 1; onPress?() }
}

/// What a panel needs to open on a never-ordered window: a presenter that shows nothing, and a screen big enough to sit below its anchor.
@MainActor
private func offscreenPanel(_ host: GlassPanelHost) {
    host.presenter = { _, _ in }
    host.visibleFrameOverride = NSRect(x: -4000, y: -4000, width: 8000, height: 8000)
}

@MainActor
private final class SwatchView: NSView {
    let color: NSColor
    init(frame: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

@MainActor
private final class AccessibilityBox {
    var value = ChromeAccessibility.none
}

/// Target of the menu rows in the choice-panel checks: records what ran (and whether the panel was still open when it did), disables rows by
/// selector name, and reports Actual Size as on or off through `validateMenuItem`, the way the app's validation does.
@MainActor
private final class MenuTarget: NSObject, NSMenuItemValidation {
    var hits: [String] = []
    var openWhenPerformed: [Bool] = []
    var disabled: Set<String> = []
    var actualSizeOn = false
    var fillOn = true
    var isOpen: () -> Bool = { false }
    private func note(_ name: String) { hits.append(name); openWhenPerformed.append(isOpen()) }
    @objc func save(_ sender: Any?) { note("save") }
    @objc func export(_ sender: Any?) { note("export") }
    @objc func copyIt(_ sender: Any?) { note("copy") }
    @objc func paste(_ sender: Any?) { note("paste") }
    @objc func fill(_ sender: Any?) { note("fill") }
    @objc func shadow(_ sender: Any?) { note("shadow") }
    @objc func font(_ sender: Any?) { note("font") }
    @objc func actualSize(_ sender: Any?) { note("actualSize") }
    @objc func zoomChanged(_ sender: Any?) { note("zoom") }
    @objc func originalChanged(_ sender: Any?) { note("original:" + String((sender as? NSButton)?.state.rawValue ?? -1)) }
    @objc func upload(_ sender: Any?) { note("upload") }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return true }
        if action == #selector(actualSize(_:)) { item.state = actualSizeOn ? .on : .off }
        if action == #selector(fill(_:)) { item.state = fillOn ? .on : .off }
        return !disabled.contains(NSStringFromSelector(action))
    }
}

/// Counts native menu tracking (a dropdown, a pop-up or a context menu) so a test can prove the glass panel was used instead.
/// `NSMenu.didBeginTrackingNotification` is posted by AppKit when a menu starts tracking and by nothing else, so the glass panel
/// (which runs a menu's delegate hooks but never tracks it) cannot trip it.
@MainActor
private final class NativeMenuProbe {
    private(set) var began = 0
    private var token: NSObjectProtocol?
    private var guardTimers: [Timer] = []
    init() {
        token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.began += 1 }
        }
    }
    /// A route that wrongly falls back to the native menu would track until the user answers; this lets the run end instead of hanging.
    func guardAgainstHang(_ menu: NSMenu?) {
        let timer = Timer(timeInterval: 0.5, repeats: false) { _ in MainActor.assumeIsolated { menu?.cancelTracking() } }
        for mode in [RunLoop.Mode.common, .eventTracking] { RunLoop.main.add(timer, forMode: mode) }
        guardTimers.append(timer)
    }
    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        for timer in guardTimers { timer.invalidate() }
    }
}

/// The two pop-ups whose choices are a glass panel: the panel they open, and whether it is open.
@MainActor
private protocol PanelOwner: NSPopUpButton { var choicePanel: MenuChoicePanel { get } }
extension PanelOwner { var isOpen: Bool { choicePanel.host.isShown } }
extension ToolboxPopUpButton: PanelOwner {}
extension ZoomPopUpButton: PanelOwner {}

@MainActor
private final class NonorderingWindow: NSWindow {
    override func orderFront(_ sender: Any?) { preconditionFailure("No desktop windows") }
    override func orderFrontRegardless() { preconditionFailure("No desktop windows") }
    override func makeKeyAndOrderFront(_ sender: Any?) { preconditionFailure("No desktop windows") }
}

@main
@MainActor
private enum GlassChromeTests {
    private static var checks = 0, notes: [String] = [], faNotes: [String] = []
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    private static func waitForMain(_ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 1)
        while !condition(), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return condition()
    }

    private static let toolOrder = ["select", "brush", "line", "ellipse", "rectangle", "fill", "eraser", "text", "arrow", "crop"]
    private static let snapToolTip = "Snap: drag an area or click a window; right-click or Control-click for Fullscreen"
    private static let snapFrameToolTip = "Snap Frame: capture the area inside the frame; hold Shift for a six-second timer"
    private static let plain = ChromeAccessibility.none
    private static let contrast = ChromeAccessibility(reduceTransparency: false, increaseContrast: true, reduceMotion: false)
    private static let calm = ChromeAccessibility(reduceTransparency: false, increaseContrast: false, reduceMotion: true)
    private static let differentiate = ChromeAccessibility(reduceTransparency: false, increaseContrast: false, reduceMotion: false, differentiateWithoutColor: true)

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        // The chrome reads Hide's and Undo's shortcuts from the real menu bar, so the rig has one.
        let bar = NSMenu()
        for (action, key) in [(#selector(ActionTarget.hide(_:)), "m"), (#selector(ActionTarget.undo(_:)), "z")] {
            let item = NSMenuItem(), menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Item", action: action, keyEquivalent: key))
            item.submenu = menu; bar.addItem(item)
        }
        NSApp.mainMenu = bar
        FontAwesomeFont.resetForTesting()
        buttonTests()
        sliderTests()
        // The state tests pin the display options so the machine's own settings (Reduce Motion, Increase Contrast) cannot change them.
        DisplayOptions.override = .none
        commandButtonStateTests()
        controlStateTests()
        toggleTests()
        differentiateTests()
        glyphContrastTests()
        DisplayOptions.override = nil
        do {
            surfaceTests()
            let fonts = fontDirectory()
            chromeTests(glyphs: false)
            uploadVariantChecks()
            uploadOutcomeChecks()
            formatCompactionChecks()
            menuChoiceChecks()
            originalSizeChecks()
            externalTreeChecks()
            if let fonts {
                for family in FAFamily.allCases {
                    expect(FontAwesomeFont.register(url: fonts.appendingPathComponent(family.resourceName + ".ttf"), family: family), "Subset font \(family) registers")
                }
                buttonGlyphTests()
                chromeTests(glyphs: true)
                FontAwesomeFont.resetForTesting()
            } else {
                faNotes.append("glyph branch")
            }
        }
        let note = (faNotes.isEmpty ? "" : "; SKIPPED (FA not bundled): " + faNotes.joined(separator: ", ")) + (notes.isEmpty ? "" : "; SKIPPED (macOS < 27): " + notes.joined(separator: ", "))
        print("GlassChromeTests: \(checks) checks passed (offscreen; no desktop input)\(note)")
    }

    // MARK: helpers

    private static func fontDirectory() -> URL? {
        var candidates: [URL] = []
        if let path = ProcessInfo.processInfo.environment["OPENSNAP_FA_FONT_DIR"], !path.isEmpty {
            candidates.append(URL(fileURLWithPath: path, isDirectory: true))
        }
        var parent = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(parent.appendingPathComponent("build/fonts", isDirectory: true))
            parent = parent.deletingLastPathComponent()
        }
        return candidates.first { directory in
            FAFamily.allCases.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.resourceName + ".ttf").path) }
        }
    }

    private static func rgb(_ color: NSColor?) -> [CGFloat]? {
        guard let converted = color?.usingColorSpace(.deviceRGB) else { return nil }
        return [converted.redComponent, converted.greenComponent, converted.blueComponent]
    }

    /// The accent as an aqua view resolves it; a dynamic colour converted outside a drawing context follows the process appearance instead.
    private static var accentAqua: NSColor { DesignTokens.Palette.resolve(NSColor.controlAccentColor, for: NSAppearance(named: .aqua)!) }

    private static func sameColor(_ a: NSColor?, _ b: NSColor?, tolerance: CGFloat = 0.01) -> Bool {
        guard let x = rgb(a), let y = rgb(b) else { return a == nil && b == nil }
        return zip(x, y).allSatisfy { abs($0 - $1) <= tolerance }
    }

    private static func window(_ size: NSSize) -> (NonorderingWindow, NSView) {
        let window = NonorderingWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = content
        return (window, content)
    }

    private static func event(_ type: NSEvent.EventType, in window: NSWindow, at point: NSPoint = NSPoint(x: 5, y: 5), flags: NSEvent.ModifierFlags = [], number: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: number, clickCount: 1, pressure: 1)!
    }

    // MARK: CommandButton (available on every supported macOS)

    private static func buttonTests() {
        // Font floor: the title initializer assigns a small system font after init(frame:).
        let titled = CommandButton(title: "Wipe", target: nil, action: nil)
        expect((titled.font?.pointSize ?? 0) >= 18, "Title initializer never leaves a font under 18 pt")
        expect((CommandButton(frame: .zero).font?.pointSize ?? 0) == 20, "Default label size is 20 pt")
        titled.font = .systemFont(ofSize: 9)
        expect(titled.font?.pointSize == 18, "Assigning a small font floors at 18 pt")
        titled.font = nil
        expect(titled.font?.pointSize == 20, "Clearing the font restores 20 pt")
        titled.font = .systemFont(ofSize: 24)
        expect(titled.font?.pointSize == 24, "Larger fonts are kept")
        expect(!titled.isBordered && titled.focusRingType == .exterior, "The glass is the bezel; the focus ring stays AppKit's exterior ring")
        expect(titled.alignmentRectInsets.top == 0 && titled.alignmentRectInsets.left == 0 && titled.alignmentRectInsets.bottom == 0 && titled.alignmentRectInsets.right == 0,
               "No alignment insets, so the frame equals what the surface constrains")

        // Icon family follows the state; Actual Size swaps the glyph as well.
        let tool = CommandButton(title: "", target: nil, action: nil)
        tool.setButtonType(.toggle)
        tool.icon = .paintbrush
        expect(tool.activeFamily == .regular && tool.iconFamily == .regular && tool.selectedFamily == .solid, "Regular off, solid selected by default")
        expect(tool.image != nil && tool.imagePosition == .imageOnly, "Icon-only tool shows an image only")
        let offImage = tool.image
        tool.state = .on
        expect(tool.activeFamily == .solid, "Selecting switches to the selected family")
        expect(tool.image !== offImage, "Selecting re-renders the glyph")
        tool.state = .off
        expect(tool.activeFamily == .regular, "Deselecting restores the regular family")
        tool.selectedFamily = .regular
        tool.state = .on
        expect(tool.activeFamily == .regular, "selectedFamily is honored")
        tool.state = .off
        tool.selectedFamily = .solid

        let actual = CommandButton(title: "Actual Size", target: nil, action: nil)
        actual.setButtonType(.toggle)
        actual.icon = .eyeSlash
        actual.selectedIcon = .xmark
        expect(actual.imagePosition == .imageLeading, "Icon beside a label leads it")
        if case .fontAwesomeFree(let name) = actual.iconSource { expect(name == FAIcon.eyeSlash.freeSource.name, "Off shows the icon") }
        actual.state = .on
        if case .fontAwesomeFree(let name) = actual.iconSource { expect(name == FAIcon.xmark.freeSource.name, "On shows the selected icon") }
        expect(actual.activeFamily == .solid, "Actual Size on is the solid family")
        let blank = CommandButton(title: "Plain", target: nil, action: nil)
        expect(blank.iconSource == .none && blank.image == nil && blank.imagePosition == .noImage, "Without an icon the title stands alone")

        // contentTintColor per state: a selected button is an accent fill at 0.20 (HC 0.32), so its glyph is black or white, whichever the
        // blended fill needs (OSN-044: computed against the blend, never the opaque accent); the primary button contrasts with its saturated fill.
        let tinted = CommandButton(title: "Snap", target: nil, action: nil)
        tinted.setButtonType(.toggle)
        tinted.icon = .crosshairs
        tinted.appearance = NSAppearance(named: .aqua)
        let accentContrast = DesignTokens.Palette.onAccent(fill: accentAqua, alpha: 1, over: .white)
        expect(sameColor(tinted.contentTintColor, .labelColor), "Normal content uses the label color")
        tinted.state = .on
        for (name, appearance) in [("aqua", NSAppearance.Name.aqua), ("darkAqua", .darkAqua)] {
            tinted.appearance = NSAppearance(named: appearance)
            let arm = DesignTokens.Palette.arm(for: tinted.effectiveAppearance)
            let blended = DesignTokens.Palette.blend(DesignTokens.Palette.resolve(DesignTokens.Palette.accent, arm: arm), alpha: 0.20, over: DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.window, arm: arm))
            let ratio = DesignTokens.Palette.contrastRatio(DesignTokens.Palette.resolve(tinted.contentTintColor ?? .clear, for: tinted.effectiveAppearance), blended)
            expect(ratio >= 4.5, "A selected glyph reads at \(ratio):1 on its blended accent fill in \(name)")
        }
        tinted.appearance = NSAppearance(named: .aqua)
        tinted.accessibility = contrast
        let hcBlend = DesignTokens.Palette.blend(accentAqua, alpha: 0.32, over: DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.window, arm: .highContrastAqua))
        expect(DesignTokens.Palette.contrastRatio(DesignTokens.Palette.resolve(tinted.contentTintColor ?? .clear, for: tinted.effectiveAppearance), hcBlend) >= 4.5, "Increase Contrast keeps the selected glyph readable on the stronger fill")
        tinted.accessibility = plain
        tinted.selectionTints = false
        expect(sameColor(tinted.contentTintColor, .labelColor) && tinted.plate.style == .none, "A glyph-only toggle keeps the label color and no fill when on")
        tinted.selectionTints = true
        tinted.state = .off
        tinted.isPrimary = true
        expect(sameColor(tinted.contentTintColor, accentContrast), "Primary content contrasts with the accent")
        tinted.isEnabled = false
        expect(sameColor(tinted.contentTintColor, accentContrast) && tinted.alphaValue == 0.38, "A disabled Snap keeps its glyph colour and dims through alpha 0.38")
        tinted.isEnabled = true
        tinted.isPrimary = false
        expect(sameColor(tinted.contentTintColor, .labelColor), "Re-enabling restores the label color")

        // The button draws its own state fill on a rounded layer; no surface is involved.
        let fill = CommandButton(title: "", target: nil, action: nil)
        fill.setButtonType(.toggle)
        fill.icon = .paintbrush
        fill.appearance = NSAppearance(named: .aqua)
        expect(fill.layer != nil && fill.layer?.cornerRadius == 12 && fill.layer?.backgroundColor == nil, "A button is layer backed with a 12 pt radius and no fill at rest")
        fill.setHovered(true)
        expect(abs((fill.plate.style.fill?.alphaComponent ?? 0) - 0.08) < 0.001 && fill.layer?.backgroundColor != nil, "Hover is a 0.08 label-color fill")
        fill.highlight(true)
        expect(abs((fill.plate.style.fill?.alphaComponent ?? 0) - 0.16) < 0.001, "Press is a 0.16 label-color fill")
        fill.highlight(false)
        fill.setHovered(false)
        expect(fill.plate.style == .none && fill.layer?.backgroundColor == nil, "Back to no fill")
        fill.state = .on
        expect(abs((fill.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001 && fill.layer?.borderWidth == 1, "Selected is a 0.20 accent fill with a 1 pt border")
        expect(sameColor(fill.plate.style.border, accentAqua) && sameColor(fill.plate.style.fill, accentAqua), "Both are the accent")
        fill.setHovered(true)
        expect(abs((fill.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001, "Hover does not wash out a selected button")
        fill.highlight(true)
        expect(abs((fill.plate.style.fill?.alphaComponent ?? 0) - 0.32) < 0.001, "Pressing a selected button deepens it")
        fill.highlight(false)
        fill.setHovered(false)
        fill.accessibility = contrast
        expect(abs((fill.plate.style.fill?.alphaComponent ?? 0) - 0.32) < 0.001 && fill.layer?.borderWidth == 1, "Increase Contrast strengthens the selected fill")
        fill.accessibility = plain
        fill.state = .off
        expect(fill.layer?.borderWidth == 0 && fill.layer?.backgroundColor == nil, "Deselecting removes fill and border")
        fill.isPrimary = true
        expect(fill.plate.style.fill?.alphaComponent == 1 && fill.layer?.borderWidth == 0, "Primary is the one saturated accent and never gets the selection border")
        fill.isPrimary = false
        fill.isEnabled = false
        fill.setHovered(true)
        fill.highlight(true)
        expect(fill.plate.style == .none && fill.alphaValue == 0.38, "Disabled ignores hover and press and dims through alpha 0.38")
        fill.highlight(false)
        fill.setHovered(false)
        fill.isEnabled = true
        expect(fill.alphaValue == 1, "Enabling restores alpha")
        let animated = CommandButton(title: "", target: nil, action: nil)
        animated.setHovered(true)
        expect(animated.plate.lastAnimationDuration == 0.15, "State changes animate over 0.15 s")
        animated.accessibility = calm
        expect(animated.plate.lastAnimationDuration == 0, "Reduce Motion makes state changes instant")
        animated.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: false, reduceMotion: false)
        expect(animated.plate.lastAnimationDuration == 0.15, "Reduce Transparency alone keeps the animation")
        animated.setHovered(false)
        let hidden = CommandButton(title: "", target: nil, action: nil)
        hidden.setHovered(true)
        hidden.isHidden = true
        expect(!hidden.isHovered, "Hiding a button clears hover")

        // Focus ring mask follows the host shape and vanishes while disabled.
        let ring = CommandButton(title: "", target: nil, action: nil)
        ring.frame = NSRect(x: 0, y: 0, width: 148, height: 40)
        expect(!ring.focusRingMaskBounds.isEmpty, "Enabled button has focus-ring bounds")
        func mask(_ shape: GlassShape) -> NSBitmapImageRep {
            ring.focusShape = shape
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 148, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.cgContext.clear(ring.bounds)
            ring.drawFocusRingMask()
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        let capsule = mask(.capsule), rounded = mask(.rounded(6))
        expect(alpha(capsule, 74, 20) > 0.9, "Mask covers the center")
        expect(alpha(capsule, 3, 3) < 0.1, "A capsule mask leaves the corner clear")
        expect(alpha(rounded, 3, 3) > 0.5, "A small radius fills the corner a capsule leaves clear")
        ring.isEnabled = false
        expect(ring.focusRingMaskBounds.isEmpty, "Disabled button has no focus ring")
        expect(alpha(mask(.capsule), 74, 20) == 0, "Disabled button draws no focus mask")
        ring.isEnabled = true

        // Primary clicks are bracketed because NSButton never calls highlight(_:) for them; the action still fires once.
        let target = ActionTarget()
        let (_, content) = window(NSSize(width: 200, height: 80))
        let click = CommandButton(title: "Snap", target: target, action: #selector(ActionTarget.snap(_:)))
        click.frame = NSRect(x: 10, y: 10, width: 120, height: 40)
        content.addSubview(click)
        var pressing: [Bool] = []
        click.plate.onApply = { _ in pressing.append(click.isPressing) }
        let down = event(.leftMouseDown, in: content.window!, at: NSPoint(x: 30, y: 30))
        NSApp.postEvent(event(.leftMouseUp, in: content.window!, at: NSPoint(x: 30, y: 30)), atStart: false)
        click.mouseDown(with: down)
        expect(pressing.first == true && pressing.last == false && !click.isPressing, "A primary click presses then releases the surface state")
        expect(target.hits == ["snap"], "The primary action fires exactly once")

        // OriginalActionButton's secondary routing is untouched and also reports its press.
        let secondary = CommandButton(title: "Snap", target: target, action: #selector(ActionTarget.snap(_:)))
        secondary.frame = NSRect(x: 10, y: 10, width: 120, height: 40)
        secondary.alternateTarget = target
        secondary.alternateAction = #selector(ActionTarget.alternate(_:))
        content.addSubview(secondary)
        target.hits.removeAll()
        var secondaryPress: [Bool] = []
        secondary.plate.onApply = { _ in secondaryPress.append(secondary.isPressing) }
        secondary.rightMouseDown(with: event(.rightMouseDown, in: content.window!, number: 2))
        expect(secondary.isPressing && target.hits.isEmpty, "Secondary press highlights without dispatching")
        secondary.rightMouseUp(with: event(.rightMouseUp, in: content.window!, number: 2))
        expect(target.hits == ["alternate"], "The alternate action still fires on release")
        expect(secondaryPress.contains(true) && secondaryPress.last == false && !secondary.isPressing, "The secondary press is reported and cleared")

        // A momentary click reads .on inside AppKit; that must never look like a selection. Assigning state still does.
        let momentary = CommandButton(title: "Undo", target: target, action: #selector(ActionTarget.undo(_:)))
        momentary.icon = .arrowRotateLeft
        content.addSubview(momentary)
        target.hits.removeAll()
        momentary.performClick(nil)
        expect(target.hits == ["undo"] && !momentary.tracksState, "A momentary button is not a two-state button")
        expect(!momentary.showsSelection && momentary.activeFamily == .regular && sameColor(momentary.contentTintColor, .labelColor), "A momentary click never reads as selected")
        momentary.icon = .font
        momentary.refreshIcon()
        expect(!momentary.showsSelection && momentary.activeFamily == .regular, "Redrawing a clicked momentary button keeps the regular glyph")
        momentary.state = .on
        expect(momentary.showsSelection && momentary.activeFamily == .solid, "Assigning state is always honored")
        momentary.state = .off

        // Toggles flip state inside the cell, so the glyph syncs when the action is sent.
        let toggled = CommandButton(title: "", target: target, action: #selector(ActionTarget.chooseTool(_:)))
        toggled.setButtonType(.toggle)
        toggled.identifier = NSUserInterfaceItemIdentifier("brush")
        toggled.icon = .paintbrush
        content.addSubview(toggled)
        target.hits.removeAll()
        toggled.performClick(nil)
        expect(target.hits == ["tool:brush"], "A tool click delivers its identifier to the action")
        expect(toggled.state == .on && toggled.activeFamily == .solid, "A click-toggled button switches to the selected glyph")
    }

    @available(macOS 13, *)
    private static func buttonGlyphTests() {
        let tool = CommandButton(title: "", target: nil, action: nil)
        tool.setButtonType(.toggle)
        tool.icon = .paintbrush
        expect(tool.iconSource == .fontAwesome(.regular), "With the subset registered, off renders Font Awesome Regular")
        tool.state = .on
        expect(tool.iconSource == .fontAwesome(.solid), "On renders Font Awesome Solid")
        tool.state = .off
        expect(tool.iconSource == .fontAwesome(.regular), "Off returns to Regular")
        tool.iconPointSize = 30
        expect((tool.image?.size.width ?? 0) == ceil(30 * 1.25), "iconPointSize drives the rendered canvas")
    }

    // MARK: BezelSizeSlider

    private static func keyEvent(_ code: UInt16, in window: NSWindow, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    private static func sliderTests() {
        let slider = BezelSizeSlider(frame: NSRect(origin: .zero, size: BezelSizeSlider.pillSize))
        let (window, content) = window(NSSize(width: 80, height: 60))
        window.appearance = NSAppearance(named: .aqua)
        content.addSubview(slider)
        slider.frame = NSRect(x: 16, y: 12, width: 48, height: 36)
        let target = ActionTarget()
        slider.target = target; slider.action = #selector(ActionTarget.sizeChanged(_:))
        var begins = 0, ends = 0
        slider.onBegin = { begins += 1; return true }
        slider.onEnd = { ends += 1 }
        slider.panelSetup = offscreenPanel
        func groups() -> String { "begin \(begins) end \(ends)" }

        // Semantics: a real slider to assistive technology, with the five original steps.
        expect(OriginalDrawingControls.sizeSteps == [1.5, 4.125, 6.75, 9.375, 12], "There are five steps")
        expect(slider.accessibilityRole() == .slider && slider.accessibilityLabel() == "Drawing size" && slider.isAccessibilityElement(), "The pill is an accessible slider")
        expect((slider.accessibilityMinValue() as? NSNumber)?.doubleValue == 1.5 && (slider.accessibilityMaxValue() as? NSNumber)?.doubleValue == 12
               && (slider.accessibilityValue() as? NSNumber)?.doubleValue == 7, "Min, max and the whole-number value are exposed (6.75 reads 7)")
        expect(slider.acceptsFirstResponder && slider.frame.height >= 36, "The pill takes the keyboard and is at least 36 pt tall")

        // Pixels: the glyph is a horizontal line whose thickness is the value.
        func raster() -> NSBitmapImageRep {
            let rep = slider.bitmapImageRepForCachingDisplay(in: slider.bounds)!
            slider.cacheDisplay(in: slider.bounds, to: rep)
            return rep
        }
        func inkedRun(_ rep: NSBitmapImageRep, column: Int? = nil) -> Int {
            let scale = CGFloat(rep.pixelsWide) / slider.bounds.width
            let x = column ?? rep.pixelsWide / 2
            var count = 0
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 1 }
            return Int((CGFloat(count) / scale).rounded())
        }
        func inkedWidth(_ rep: NSBitmapImageRep) -> Int {
            let row = rep.pixelsHigh / 2
            var count = 0
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: row)?.alphaComponent ?? 0) > 0.5 { count += 1 }
            return Int((CGFloat(count) / (CGFloat(rep.pixelsWide) / slider.bounds.width)).rounded())
        }
        slider.doubleValue = 1.5
        let thin = raster()
        slider.doubleValue = 12
        let thick = raster()
        expect(inkedRun(thin) >= 1 && inkedRun(thin) <= 3, "The thinnest size draws a hairline (\(inkedRun(thin)) pt)")
        expect(inkedRun(thick) >= 11 && inkedRun(thick) <= 13, "The thickest size draws a 12 pt bar (\(inkedRun(thick)) pt)")
        expect(inkedWidth(thin) >= 23 && inkedWidth(thin) <= 28 && inkedWidth(thick) >= 23, "Both glyphs are a 24 pt long horizontal line")
        slider.doubleValue = 6.75

        // Every route that changes the value is exactly one begin/end pair.
        target.hits.removeAll()
        expect(slider.accessibilityPerformIncrement() && slider.doubleValue == 9.375 && begins == 1 && ends == 1, "Increment steps +2.625 in one group: \(groups())")
        expect(slider.accessibilityPerformDecrement() && slider.accessibilityPerformDecrement() && slider.doubleValue == 4.125 && begins == 3 && ends == 3, "Decrement steps -2.625: \(groups())")
        expect(target.hits == ["size", "size", "size"], "Every change reaches the action once")
        slider.doubleValue = 6.75; begins = 0; ends = 0
        slider.keyDown(with: keyEvent(124, in: window))
        expect(slider.doubleValue == 9.375 && begins == 1 && ends == 1, "Right is larger by one preset: \(slider.doubleValue)")
        slider.keyDown(with: keyEvent(126, in: window))
        expect(slider.doubleValue == 12 && begins == 2 && ends == 2, "Up is larger too, clamped at the maximum")
        slider.keyDown(with: keyEvent(123, in: window))
        expect(slider.doubleValue == 9.375, "Left is smaller")
        slider.keyDown(with: keyEvent(125, in: window))
        expect(slider.doubleValue == 6.75 && begins == 4 && ends == 4, "Down is smaller: each key is one group \(groups())")
        slider.keyDown(with: keyEvent(124, in: window, flags: [.shift]))
        expect(abs(slider.doubleValue - 6.85) < 0.0001 && !OriginalDrawingControls.sizeSteps.contains(slider.doubleValue), "Shift steps 0.1, a non-preset value: \(slider.doubleValue)")
        slider.performValueChange(.nan, continuous: true)
        expect(slider.doubleValue.isFinite && begins == 5, "A non-finite value is ignored")
        slider.doubleValue = 6.75
        slider.performValueChange(12, continuous: false)
        slider.performValueChange(1.5, continuous: false)
        expect(slider.doubleValue == 1.5, "Value changes behave")
        slider.doubleValue = 6.75

        // The panel: opens below the pill as glass, with the readout, the track and five presets, and leaves the keyboard on the pill.
        begins = 0; ends = 0
        expect(!slider.isPopoverShown, "The panel starts closed")
        slider.keyDown(with: keyEvent(49, in: window))
        guard slider.isPopoverShown, let host = slider.panel, let panel = slider.popoverContent else { expect(false, "Space opens the panel"); return }
        expect(host.placement?.edge == .minY && host.anchor === slider && host.alignment == .center, "It opens below the pill, centred on it")
        expect(!host.requestedKey, "Opening it does not take the keyboard from the pill")
        expect(slider.panelWindow === host.window, "The panel has its own window")
        host.window.contentView?.layoutSubtreeIfNeeded()
        expect(panel.trackPlate.frame.width == 320 && panel.presetPlate.frame.width == 320 && panel.trackPlate.frame.height == 82 && panel.presetPlate.frame.height == 44,
               "Two plates, 320 wide: the track plate 82 tall and the preset plate 44 (\(panel.trackPlate.frame.size), \(panel.presetPlate.frame.size))")
        expect(host.contentSize == NSSize(width: 320, height: 134), "The panel is 320 x 134 (\(host.contentSize))")
        let structure = glassStructure(host.container)
        expect(structure.containers == 1 && structure.plates == 2 && structure.nested == 0, "One glass container holding two plates, and no glass inside glass (\(structure))")
        // G5 can fail: glass seeded inside glass is counted, and the same walk still reports clean glass as clean.
        let outer = NSGlassEffectView(), inner = NSGlassEffectView(), seeded = NSView()
        outer.contentView = seeded; seeded.addSubview(inner)
        expect(glassStructure(outer).nested == 1 && glassStructure(inner).nested == 0, "The glass-depth walk finds a seeded plate inside a plate (\(glassStructure(outer)))")
        expect(host.plates == panel.plates && panel.plates.allSatisfy { $0.axis == .vertical }, "The two plates are the panel's groups")
        expect(textFonts(in: host.container).allSatisfy { $0 >= 18 } && !textFonts(in: host.container).isEmpty, "Every text is 18 pt or more (\(textFonts(in: host.container)))")
        panel.sync()
        expect(panel.titleLabel.stringValue == "Size" && panel.titleLabel.font?.pointSize == 20 && panel.readout.font?.pointSize == 20, "Title and readout are 20 pt")
        expect(panel.readout.stringValue == "7", "The readout shows the rounded size")
        slider.doubleValue = 9.375
        expect(panel.readout.stringValue == "9", "The readout follows the value")
        slider.doubleValue = 6.75
        var track = panel.trackView
        expect(track.frame.size == NSSize(width: 288, height: 36) && panel.presetButtons.count == 5 && panel.presetButtons.allSatisfy { $0.frame.height == 36 && $0.frame.width > 56 },
               "A 288 x 36 track and five 36 pt tall presets sharing the row (\(panel.presetButtons.map { $0.frame.width }))")
        expect(panel.presetButtons.map { $0.accessibilityLabel() ?? "" } == ["Size 2", "Size 4", "Size 7", "Size 9", "Size 12"], "Presets are spoken Size 2/4/7/9/12")
        expect(panel.presetButtons.map(\.isSelectedPreset) == [false, false, true, false, false], "Only the current preset is selected")
        let panelWindow = host.window
        expect(track.acceptsFirstMouse(for: nil) && panel.presetButtons.allSatisfy { $0.acceptsFirstMouse(for: nil) }, "The track and the presets act on the press that makes the panel key")
        func pointer(_ type: NSEvent.EventType, fraction: CGFloat, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
            let location = track.convert(NSPoint(x: track.x(forFraction: fraction), y: 18), to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: 0, windowNumber: panelWindow.windowNumber,
                                      context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
        }
        // One drag is one group, whatever it passes through; a plain drag only returns the five steps.
        begins = 0; ends = 0; target.hits.removeAll()
        track.mouseDown(with: pointer(.leftMouseDown, fraction: 0.75))
        expect(slider.doubleValue == 9.375 && begins == 1 && ends == 0, "Mouse down starts the group on the clicked step: \(groups())")
        var seen = Set<Double>()
        for fraction in stride(from: 0.75, through: 0.0, by: -0.07) {
            track.mouseDragged(with: pointer(.leftMouseDragged, fraction: CGFloat(fraction)))
            seen.insert(slider.doubleValue)
        }
        expect(seen.isSubset(of: Set(OriginalDrawingControls.sizeSteps)) && seen.count >= 3, "A plain drag snaps to the five steps: \(seen.sorted())")
        track.mouseDragged(with: pointer(.leftMouseDragged, fraction: 0.6, flags: [.shift]))
        expect(abs(slider.doubleValue - 7.8) < 0.0001, "Shift keeps the drag continuous: \(slider.doubleValue)")
        track.mouseUp(with: pointer(.leftMouseUp, fraction: 0.6))
        expect(begins == 1 && ends == 1, "The whole drag is one begin/end pair: \(groups())")
        expect(Set(target.hits) == ["size"], "Dragging reaches the action")
        track.mouseDown(with: pointer(.leftMouseDown, fraction: 0.2, clicks: 2))
        track.mouseUp(with: pointer(.leftMouseUp, fraction: 0.2))
        expect(slider.doubleValue == 6.75, "A double-click resets to the default size: \(slider.doubleValue)")
        // A preset click is one group; the selection moves with it.
        begins = 0; ends = 0
        panel.presetButtons[3].performClick(nil)
        expect(waitForMain { ends == 1 }, "The preset action finishes after dispatch")
        expect(slider.doubleValue == 9.375 && begins == 1 && ends == 1 && panel.presetButtons.map(\.isSelectedPreset) == [false, false, false, true, false], "A preset click is one group: \(groups())")
        expect(!slider.isPopoverShown && slider.popoverContent == nil && slider.panel == nil, "A preset pick closes the panel, as a colour pick closes the colour panel (F-J1-019)")
        // Reopened, another preset is another group.
        slider.showPopover()
        guard let reopened = slider.popoverContent else { expect(false, "The panel reopens"); return }
        reopened.presetButtons[0].performClick(nil)
        expect(waitForMain { ends == 2 }, "The reopened preset action finishes after dispatch")
        expect(slider.doubleValue == 1.5 && begins == 2 && ends == 2 && reopened.readout.stringValue == "2" && !slider.isPopoverShown, "Another preset: \(groups())")
        // A preset that is already the value is still a group and still closes the panel.
        slider.showPopover()
        slider.popoverContent?.presetButtons[0].performClick(nil)
        expect(waitForMain { ends == 3 }, "The unchanged preset action still finishes after dispatch")
        expect(begins == 3 && ends == 3 && !slider.isPopoverShown, "Choosing the current preset again still closes the panel: \(groups())")
        // Dismissing mid-drag closes the group, and the late mouse-up cannot close it twice.
        slider.showPopover()
        guard let live = slider.popoverContent else { expect(false, "The panel reopens for the drag"); return }
        slider.panel?.window.contentView?.layoutSubtreeIfNeeded()
        track = live.trackView
        begins = 0; ends = 0
        track.mouseDown(with: pointer(.leftMouseDown, fraction: 1))
        track.mouseDragged(with: pointer(.leftMouseDragged, fraction: 0.5))
        expect(begins == 1 && ends == 0 && slider.isPopoverShown, "A drag is open and keeps the panel open: \(groups())")
        slider.dismissPopover()
        expect(ends == 1 && !slider.isPopoverShown && slider.popoverContent == nil, "Dismissing mid-drag ends the group and releases the panel: \(groups())")
        track.mouseUp(with: pointer(.leftMouseUp, fraction: 0.5))
        expect(begins == 1 && ends == 1, "The stale mouse-up adds nothing: \(groups())")
        // The host closing the panel by any other route ends the group too (an outside click, the app resigning).
        slider.showPopover()
        slider.panel?.window.contentView?.layoutSubtreeIfNeeded()
        track = slider.popoverContent!.trackView
        begins = 0; ends = 0
        track.mouseDown(with: pointer(.leftMouseDown, fraction: 1))
        expect(begins == 1 && ends == 0, "Another drag is open: \(groups())")
        slider.panel?.handleMouseDown(in: window, at: NSPoint(x: 2, y: 2))
        expect(ends == 1 && !slider.isPopoverShown, "A click outside the panel ends the open group: \(groups())")
        // Escape closes the panel from the pill; leaving the window closes it too.
        slider.doubleValue = 6.75
        slider.showPopover()
        expect(slider.isPopoverShown, "It opens again")
        slider.keyDown(with: keyEvent(53, in: window))
        expect(!slider.isPopoverShown, "Escape on the pill closes the panel")
        // A click on the pill while the panel is up only closes it: the host consumes the press, so the pill never reopens it.
        slider.showPopover()
        let onPill = slider.convert(NSPoint(x: 24, y: 18), to: nil)
        expect(slider.panel?.handleMouseDown(in: window, at: onPill) == true && !slider.isPopoverShown, "A click on the pill closes the panel and is consumed")
        // Should a press arrive anyway within the same click (a host that lets it through), the pill stays closed.
        let stray = NSEvent.mouseEvent(with: .leftMouseDown, location: onPill, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        slider.mouseDown(with: stray); slider.mouseUp(with: stray)
        expect(!slider.isPopoverShown, "The same click cannot reopen the panel it just closed")
        slider.showPopover()
        slider.removeFromSuperview()
        expect(!slider.isPopoverShown, "Leaving the window closes the panel")
        content.addSubview(slider)
        slider.isEnabled = false
        slider.showPopover()
        expect(!slider.isPopoverShown && !slider.accessibilityPerformPress() && slider.beginGesture() == false, "A disabled pill neither opens nor tracks")
        slider.isEnabled = true

        // Escape inside the panel closes it and gives the keyboard back to where it was.
        window.makeFirstResponder(slider)
        slider.showPopover()
        guard let escapable = slider.panel else { expect(false, "The panel opens for Escape"); return }
        escapable.keyStateProbe = { true }
        window.makeFirstResponder(nil)
        escapable.window.sendEvent(keyEvent(53, in: escapable.window))
        expect(!slider.isPopoverShown && window.firstResponder === slider, "Escape in the panel closes it and the keyboard returns to the pill (\(String(describing: window.firstResponder)))")
        slider.removeFromSuperview()
    }

    /// The glass views under `root`: containers, plates, and how many plates or containers sit inside another glass view.
    private static func glassStructure(_ root: NSView) -> (containers: Int, plates: Int, nested: Int) {
        var containers = 0, plates = 0, nested = 0
        func walk(_ view: NSView, insideGlass: Bool) {
            let isContainer = view is NSGlassEffectContainerView, isPlate = view is NSGlassEffectView
            if isContainer { containers += 1 }
            if isPlate { plates += 1 }
            if (isContainer || isPlate) && insideGlass { nested += 1 }
            for child in view.subviews { walk(child, insideGlass: insideGlass || isPlate) }
        }
        walk(root, insideGlass: false)
        return (containers, plates, nested)
    }

    /// The point size of every piece of text a view tree can draw.
    private static func textFonts(in root: NSView) -> [CGFloat] {
        var sizes: [CGFloat] = []
        func walk(_ view: NSView) {
            if let field = view as? NSTextField, !field.stringValue.isEmpty { sizes.append(field.font?.pointSize ?? 0) }
            if let button = view as? NSButton, !button.title.isEmpty, button.imagePosition != .imageOnly, let font = button.font { sizes.append(font.pointSize) }
            for child in view.subviews { walk(child) }
        }
        walk(root)
        return sizes
    }


    // MARK: component states (OSN-044)

    private static func srgb(_ color: CGColor?) -> NSColor? { color.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) } }

    /// `color` is `base` at `alpha`, within a rounding error.
    private static func isFill(_ color: NSColor?, base: NSColor, alpha: CGFloat) -> Bool {
        guard let x = color?.usingColorSpace(.sRGB), let b = base.usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - b.redComponent) < 0.012 && abs(x.greenComponent - b.greenComponent) < 0.012
            && abs(x.blueComponent - b.blueComponent) < 0.012 && abs(x.alphaComponent - alpha) < 0.006
    }

    private static func fill(_ view: NSView) -> NSColor? { srgb(view.layer?.backgroundColor) }

    /// The ratio of a content colour on the fill that is on screen: the layer's fill blended over the window colour.
    private static func glyphRatio(_ button: CommandButton, arm: DesignTokens.Palette.Arm) -> CGFloat {
        typealias P = DesignTokens.Palette
        let window = P.resolve(P.Surface.window, arm: arm)
        let shown = fill(button).map { P.blend($0, alpha: 1, over: window) } ?? P.rgb(window).rgb
        return P.contrastRatio(P.resolve(button.contentTintColor ?? .clear, for: button.effectiveAppearance), shown)
    }

    private static func commandButtonStateTests() {
        typealias P = DesignTokens.Palette
        for (name, appearanceName) in [("aqua", NSAppearance.Name.aqua), ("darkAqua", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)!
            let label = P.resolve(NSColor.labelColor, for: appearance), accent = P.resolve(NSColor.controlAccentColor, for: appearance)
            for (optionName, options) in [("plain", plain), ("increaseContrast", contrast), ("differentiate", differentiate)] {
                let hc = options.increaseContrast, dwc = options.differentiateWithoutColor
                let tag = "\(name)/\(optionName)"
                let hover: CGFloat = hc ? 0.16 : 0.08, pressed: CGFloat = hc ? 0.28 : 0.16, selected: CGFloat = hc ? 0.32 : 0.20
                let arm = StateStyles.arm(for: appearance, highContrast: hc)

                let tool = CommandButton(title: "", target: nil, action: nil)
                tool.setButtonType(.toggle)
                tool.icon = .paintbrush
                tool.appearance = appearance
                tool.accessibility = options
                expect(tool.layer?.backgroundColor == nil && !tool.showsIndicator && tool.alphaValue == 1, "\(tag): rest has no fill and no indicator")
                tool.setHovered(true)
                expect(isFill(fill(tool), base: label, alpha: hover), "\(tag): hover is label@\(hover) on the layer")
                tool.highlight(true)
                expect(isFill(fill(tool), base: label, alpha: pressed) && tool.glyphScale == 0.96, "\(tag): pressed is label@\(pressed) with the glyph at 0.96")
                tool.highlight(false); tool.setHovered(false)
                expect(tool.layer?.backgroundColor == nil && tool.glyphScale == 1, "\(tag): released returns to rest")

                tool.state = .on
                expect(isFill(fill(tool), base: accent, alpha: selected) && tool.layer?.borderWidth == 1, "\(tag): selected is accent@\(selected) with a 1 pt border")
                expect(tool.showsIndicator == dwc && tool.indicatorLayer.isHidden == !dwc, "\(tag): the selected indicator is on exactly when Differentiate Without Color is")
                if dwc {
                    let size = StateStyles.indicatorSize(highContrast: hc)
                    expect(tool.indicatorLayer.superlayer === tool.layer && tool.indicatorLayer.frame.size == size && size == NSSize(width: 16, height: 2)
                           && abs(tool.indicatorLayer.frame.midX - tool.bounds.midX) < 0.5
                           && (tool.isFlipped ? tool.bounds.height - tool.indicatorLayer.frame.maxY : tool.indicatorLayer.frame.minY) == StateStyles.indicatorInset,
                           "\(tag): a 2 x 16 pt capsule under the glyph, centred (\(tool.indicatorLayer.frame))")
                    expect(tool.indicatorLayer.cornerRadius == 1 && tool.indicatorLayer.backgroundColor != nil, "\(tag): the indicator is a capsule with a fill")
                }
                expect(glyphRatio(tool, arm: arm) >= 4.5, "\(tag): the selected glyph reads at \(glyphRatio(tool, arm: arm)):1 on its blended fill")
                tool.setHovered(true)
                expect(isFill(fill(tool), base: accent, alpha: selected), "\(tag): hover does not wash out the selection")
                tool.highlight(true)
                expect(isFill(fill(tool), base: accent, alpha: selected + 0.12), "\(tag): pressing a selected button deepens it by 0.12")
                tool.highlight(false); tool.setHovered(false)
                tool.isEnabled = false
                expect(tool.layer?.backgroundColor == nil && tool.alphaValue == StateStyles.disabledAlpha(highContrast: hc) && !tool.showsIndicator, "\(tag): disabled has no fill and no indicator and dims to 0.38 (0.55 under Increase Contrast)")
                tool.setHovered(true); tool.highlight(true)
                expect(tool.layer?.backgroundColor == nil && tool.glyphScale == 1, "\(tag): disabled ignores hover and press")
                tool.highlight(false); tool.setHovered(false)
                tool.isEnabled = true
                tool.state = .off
                expect(tool.layer?.backgroundColor == nil && !tool.showsIndicator, "\(tag): deselected returns to bare")

                let snap = CommandButton(title: "", target: nil, action: nil)
                snap.icon = .crosshairs
                snap.isPrimary = true
                snap.appearance = appearance
                snap.accessibility = options
                expect(isFill(fill(snap), base: accent, alpha: 1) && glyphRatio(snap, arm: arm) >= 4.5, "\(tag): Snap rests on the opaque accent and its glyph reads at \(glyphRatio(snap, arm: arm)):1")
                let restFill = fill(snap)!
                snap.setHovered(true)
                let hoverFill = fill(snap)!
                expect(hoverFill.redComponent + hoverFill.greenComponent + hoverFill.blueComponent > restFill.redComponent + restFill.greenComponent + restFill.blueComponent
                       && glyphRatio(snap, arm: arm) >= 4.5, "\(tag): Snap brightens on hover and keeps its contrast")
                snap.highlight(true)
                let pressedFill = fill(snap)!
                expect(pressedFill.redComponent + pressedFill.greenComponent + pressedFill.blueComponent < restFill.redComponent + restFill.greenComponent + restFill.blueComponent
                       && glyphRatio(snap, arm: arm) >= 4.5, "\(tag): Snap darkens on press and keeps its contrast")
                snap.highlight(false); snap.setHovered(false)
                snap.isEnabled = false
                expect(isFill(fill(snap), base: accent, alpha: 1) && snap.alphaValue == StateStyles.disabledAlpha(highContrast: hc), "\(tag): a disabled Snap is the accent dimmed to 0.38 (0.55 under Increase Contrast) through alpha")
            }
        }

        // The glyph scale is a real re-render, and Reduce Motion removes it.
        let scaled = CommandButton(title: "", target: nil, action: nil)
        scaled.icon = .paintbrush
        let restImage = scaled.image
        scaled.highlight(true)
        expect(scaled.glyphScale == 0.96 && scaled.image !== restImage, "A pressed button re-renders its glyph at 0.96")
        scaled.highlight(false)
        expect(scaled.glyphScale == 1, "The glyph returns to full size")
        scaled.accessibility = calm
        scaled.highlight(true)
        expect(scaled.glyphScale == 1, "No glyph scale under Reduce Motion")
        scaled.highlight(false)

        // Keyboard focus is carried into the style; the ring itself stays AppKit's, drawn from the mask.
        let (focusWindow, focusContent) = window(NSSize(width: 120, height: 60))
        let focus = CommandButton(title: "", target: nil, action: nil)
        focus.icon = .paintbrush
        focus.frame = NSRect(x: 10, y: 10, width: 48, height: 36)
        focusContent.addSubview(focus)
        expect(!focus.plate.stateStyle.focusRing, "No ring while unfocused")
        expect(focusWindow.makeFirstResponder(focus) && focus.plate.stateStyle.focusRing && focus.focusRingType == .exterior && !focus.focusRingMaskBounds.isEmpty, "Focus puts the ring in the style and keeps the mask")
        focus.isEnabled = false
        expect(!focus.plate.stateStyle.focusRing && focus.focusRingMaskBounds.isEmpty, "A disabled button shows no ring")
        focus.isEnabled = true
        focusWindow.makeFirstResponder(nil)
        expect(!focus.plate.stateStyle.focusRing, "Resigning focus clears it")
    }

    private static func controlStateTests() {
        typealias P = DesignTokens.Palette
        let aqua = NSAppearance(named: .aqua)!
        let (window, content) = window(NSSize(width: 420, height: 240))
        window.appearance = aqua

        // MARK: the Size pill
        let slider = BezelSizeSlider(frame: NSRect(x: 16, y: 12, width: 48, height: 36))
        content.addSubview(slider)
        slider.panelSetup = offscreenPanel
        let cell = ChromeFillCell(BezelSizeSlider(frame: .zero), size: GlassChrome.Metrics.iconButton)
        let cellSlider = cell.control as! BezelSizeSlider
        cellSlider.onInteractionChange = { [weak cell, weak cellSlider] in
            guard let cell, let cellSlider else { return }
            cell.setPressed(cellSlider.isPressed, disabled: !cellSlider.isEnabled)
        }
        expect(slider.controlState == .rest && slider.pillStyle.contentAlpha == 1 && slider.pillStyle.glyphScale == 1, "The pill rests")
        slider.setPressed(true)
        expect(slider.controlState == .pressed && slider.pillStyle.glyphScale == 0.96, "A pressed pill draws its stroke at 0.96")
        slider.setPressed(false)
        func centreAlpha() -> CGFloat {
            let rep = slider.bitmapImageRepForCachingDisplay(in: slider.bounds)!
            slider.cacheDisplay(in: slider.bounds, to: rep)
            return rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.alphaComponent ?? -1
        }
        let restAlpha = centreAlpha()
        slider.isEnabled = false
        expect(slider.controlState == .disabled && slider.pillStyle.contentAlpha == 0.38 && !slider.acceptsFirstResponder, "A disabled pill is dimmed to 0.38 and leaves the key loop")
        expect(abs(centreAlpha() / max(restAlpha, 0.001) - 0.38) < 0.05, "The disabled stroke is drawn at 0.38 of the rest alpha (\(centreAlpha()) vs \(restAlpha))")
        expect(!slider.beginGesture(), "A disabled pill is not draggable")
        slider.isEnabled = true
        cellSlider.setPressed(true)
        expect(cell.plate.isPressed && abs((cell.plate.style.fill?.alphaComponent ?? 0) - 0.16) < 0.001, "The cell behind the pill fills while the pill is pressed")
        cellSlider.setPressed(false)
        cellSlider.isEnabled = false
        expect(cell.plate.isDisabled && cell.plate.style.fill == nil, "The cell behind a disabled pill draws no fill")

        // MARK: the panel track and the presets
        slider.showPopover()
        guard let panel = slider.popoverContent, let host = slider.panel else { expect(false, "The panel opens"); return }
        host.window.appearance = aqua
        host.window.contentView?.layoutSubtreeIfNeeded()
        let panelWindow = host.window
        let track = panel.trackView
        let rest = track.knobRect
        expect(abs(rest.width - 20) < 0.001 && track.controlState == .rest, "The knob rests at 20 pt")
        track.setHovered(true)
        expect(abs(track.knobRect.width - 20 * 1.15) < 0.001 && abs(track.knobRect.midX - rest.midX) < 0.001 && abs(track.knobRect.midY - rest.midY) < 0.001, "Hover grows the knob to 1.15 around the same centre")
        track.setPressed(true)
        expect(abs(track.knobRect.width - 20 * 1.25) < 0.001 && track.controlState == .pressed, "A held knob is 1.25")
        func trackRaster() -> NSBitmapImageRep {
            let rep = track.bitmapImageRepForCachingDisplay(in: track.bounds)!
            track.cacheDisplay(in: track.bounds, to: rep)
            return rep
        }
        func alphaAt(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> CGFloat {
            let scale = CGFloat(rep.pixelsWide) / track.bounds.width
            return rep.colorAt(x: Int(x * scale), y: Int((track.bounds.height - y) * scale))?.alphaComponent ?? -1
        }
        // Pixels, not just geometry: the point 10.8 pt right of the knob centre is outside the rest knob and inside the held one.
        let probe = NSPoint(x: rest.midX + 10.8, y: rest.midY)
        let heldRaster = trackRaster(), heldTrack = alphaAt(heldRaster, x: 24, y: rest.midY)
        track.setPressed(false); track.setHovered(false)
        let restRaster = trackRaster()
        expect(alphaAt(heldRaster, x: probe.x, y: probe.y) > 0.9 && alphaAt(restRaster, x: probe.x, y: probe.y) < 0.5, "The held knob really paints wider than the resting one")
        expect(heldTrack > alphaAt(restRaster, x: 24, y: rest.midY) + 0.1, "A held knob washes the track with the accent (\(heldTrack) vs \(alphaAt(restRaster, x: 24, y: rest.midY)))")
        expect(track.trackStyle.highlight == nil && track.trackStyle.alpha == 1, "Released, the track is plain")

        // Each preset is a glass choice: the same StatePlate fills as every other, and a chosen state that is more than colour.
        let presets = panel.presetButtons
        expect(presets[2].controlState == .selected && presets[0].controlState == .rest, "The current preset is selected, the others rest")
        expect(presets[0].plate.style.fill == nil && presets[0].plate.style.borderWidth == 0, "A resting preset draws no fill and no border on its plate")
        presets[0].setHovered(true)
        expect(presets[0].controlState == .hover && abs((presets[0].commandStyle.fill?.alphaComponent ?? 0) - 0.08) < 0.004, "A hovered preset takes the command hover fill")
        expect(abs((presets[0].plate.style.fill?.alphaComponent ?? 0) - 0.08) < 0.004 && presets[0].layer?.backgroundColor != nil, "...and its plate layer paints it")
        presets[0].highlight(true)
        expect(presets[0].controlState == .pressed && abs((presets[0].commandStyle.fill?.alphaComponent ?? 0) - 0.16) < 0.004, "A pressed preset takes the command pressed fill")
        expect(abs((presets[0].plate.style.fill?.alphaComponent ?? 0) - 0.16) < 0.004, "...and its plate layer paints that")
        presets[0].highlight(false); presets[0].setHovered(false)
        expect(abs((presets[2].commandStyle.fill?.alphaComponent ?? 0) - 0.20) < 0.004 && presets[2].commandStyle.border != nil, "The selected preset takes the command selected fill and border")
        expect(abs((presets[2].plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.004 && presets[2].plate.style.borderWidth == 1 && presets[2].layer?.borderWidth == 1,
               "...painted on its own layer as a fill and a 1 pt border")
        expect(presets[2].glyphLength - presets[0].glyphLength >= 4, "The chosen preset also draws a longer stroke (\(presets[2].glyphLength) vs \(presets[0].glyphLength))")
        DisplayOptions.override = DisplayOptions(differentiateWithoutColor: true)
        presets[2].sync()
        expect(presets[2].commandStyle.indicator && presets[2].plate.stateStyle.indicator, "Differentiate Without Color adds the capsule under the chosen preset")
        DisplayOptions.override = .none
        presets[2].sync()
        slider.dismissPopover()

        // A disabled slider's track is dimmed and ignores the pointer.
        let offSlider = BezelSizeSlider(frame: NSRect(x: 0, y: 0, width: 48, height: 36))
        var begins = 0
        offSlider.onBegin = { begins += 1; return true }
        offSlider.isEnabled = false
        let offTrack = SizeTrackView(slider: offSlider)
        expect(offTrack.controlState == .disabled && offTrack.trackStyle.alpha == 0.38 && !offTrack.isEnabled && !offTrack.acceptsFirstResponder, "A disabled slider's track is dimmed to 0.38")
        offTrack.setHovered(true)
        expect(offTrack.controlState == .disabled && offTrack.trackStyle.knobScale == 1, "A disabled track never grows its knob")
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 100, y: 18), modifierFlags: [], timestamp: 0, windowNumber: panelWindow.windowNumber,
                                      context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        offTrack.mouseDown(with: down)
        expect(begins == 0 && offSlider.doubleValue == OriginalDrawingControls.initialSize && !offTrack.isPressed, "A disabled track is not draggable")

        // MARK: the colour swatch
        let swatch = BezelColorButton(frame: NSRect(x: 100, y: 100, width: 42, height: 32))
        expect(swatch.acceptsFirstMouse(for: nil), "A swatch acts on the press that makes its panel key")
        swatch.title = ""; swatch.isBordered = false
        swatch.drawingColor = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1) // token-exempt: a test swatch colour
        content.addSubview(swatch)
        func swatchRaster() -> NSBitmapImageRep {
            let rep = swatch.bitmapImageRepForCachingDisplay(in: swatch.bounds)!
            swatch.cacheDisplay(in: swatch.bounds, to: rep)
            return rep
        }
        func darkPixels(_ rep: NSBitmapImageRep) -> Int {
            let scale = rep.pixelsWide / Int(swatch.bounds.width)
            var count = 0
            for x in (13 * scale)..<(29 * scale) {
                for y in (8 * scale)..<(24 * scale) {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent < 0.3 && color.alphaComponent > 0.9 { count += 1 }
                }
            }
            return count
        }
        func outlineAlpha(_ rep: NSBitmapImageRep) -> CGFloat {
            let scale = CGFloat(rep.pixelsWide) / swatch.bounds.width
            return rep.colorAt(x: Int(2.75 * scale), y: Int(16 * scale))?.alphaComponent ?? -1
        }
        let restSwatch = swatchRaster()
        expect(swatch.controlState == .rest && !swatch.swatchStyle.check && darkPixels(restSwatch) == 0, "A resting swatch has no check glyph")
        swatch.setHovered(true)
        expect(swatch.controlState == .hover && swatch.swatchStyle.outlineWidth == 1 && abs(swatch.swatchStyle.outline.alphaComponent - 0.5) < 0.004, "Hover outlines the swatch with label@0.5")
        expect(outlineAlpha(swatchRaster()) > outlineAlpha(restSwatch) + 0.1, "The hover outline paints stronger than the rest outline")
        expect(abs((swatch.plateFill?.alphaComponent ?? 0) - 0.08) < 0.004, "A hovered swatch also takes the hover fill every glass choice has")
        func halo(_ rep: NSBitmapImageRep) -> CGFloat {
            let scale = CGFloat(rep.pixelsWide) / swatch.bounds.width
            return rep.colorAt(x: Int(1.2 * scale), y: Int(16 * scale))?.alphaComponent ?? -1
        }
        expect(halo(restSwatch) < 0.01 && halo(swatchRaster()) > 0.04, "...painted in the 3 pt margin around the swatch (\(halo(restSwatch)) at rest, \(halo(swatchRaster())) hovered)")
        swatch.highlight(true)
        expect(swatch.controlState == .pressed && abs((swatch.swatchStyle.fill?.alphaComponent ?? 0) - 0.16) < 0.004, "A pressed swatch takes a label@0.16 fill")
        expect(abs((swatch.plateFill?.alphaComponent ?? 0) - 0.16) < 0.004, "...and the pressed fill behind it")
        let pressedPixel = swatchRaster().colorAt(x: Int(21 * CGFloat(restSwatch.pixelsWide) / swatch.bounds.width), y: Int(5 * CGFloat(restSwatch.pixelsWide) / swatch.bounds.width))?.usingColorSpace(.deviceRGB)
        let restPixel = restSwatch.colorAt(x: Int(21 * CGFloat(restSwatch.pixelsWide) / swatch.bounds.width), y: Int(5 * CGFloat(restSwatch.pixelsWide) / swatch.bounds.width))?.usingColorSpace(.deviceRGB)
        expect((pressedPixel?.redComponent ?? 1) < (restPixel?.redComponent ?? 0) - 0.05, "The pressed fill darkens the swatch")
        swatch.highlight(false); swatch.setHovered(false)
        swatch.state = .on
        let selectedSwatch = swatchRaster()
        expect(swatch.controlState == .selected && swatch.swatchStyle.check && swatch.swatchStyle.outlineWidth == 3, "The selected swatch is a 3 pt accent outline plus a check")
        expect(swatch.plateFill == nil, "...and nothing is filled behind it: selection is the outline and the check, never the selected fill")
        expect(darkPixels(selectedSwatch) >= 8, "The check glyph is drawn on the selected swatch (\(darkPixels(selectedSwatch)) glyph pixels)")
        expect(outlineAlpha(selectedSwatch) > 0.9, "The 3 pt accent outline is opaque")
        swatch.state = .off
        expect(darkPixels(swatchRaster()) == 0, "Deselecting removes the check")
        swatch.isEnabled = false
        expect(swatch.swatchStyle.alpha == 0.38 && swatch.controlState == .disabled && swatch.plateFill == nil, "A disabled swatch dims to 0.38")
        swatch.isEnabled = true
        DisplayOptions.override = DisplayOptions(increaseContrast: true)
        expect(swatch.swatchStyle.outline.alphaComponent > StateStyles.swatch(.rest, highContrast: false, appearance: aqua).outline.alphaComponent, "Increase Contrast strengthens the rest outline")
        DisplayOptions.override = .none
        swatch.removeFromSuperview(); slider.removeFromSuperview()
    }

    private static func toggleTests() {
        typealias P = DesignTokens.Palette
        let aqua = NSAppearance(named: .aqua)!
        let (window, content) = window(NSSize(width: 300, height: 100))
        window.appearance = aqua
        let target = ActionTarget()
        let toggle = SegmentedToggle(titles: ["PNG", "JPG"])
        toggle.target = target; toggle.action = #selector(ActionTarget.formatChanged(_:))
        GlassChrome.fix(toggle, NSSize(width: ceil(toggle.intrinsicContentSize.width), height: 36))
        content.addSubview(toggle)
        toggle.frame.origin = NSPoint(x: 20, y: 20)
        content.layoutSubtreeIfNeeded()

        // Size: it must be no wider than the system capsule it replaces (149 pt measured in the same rig) and exactly one command high.
        expect(toggle.frame.height == 36 && toggle.frame.width <= 149 && toggle.frame.width > 100, "The toggle is 36 pt tall and no wider than the capsule it replaces (\(toggle.frame.width) pt)")
        expect(abs(toggle.segmentRect(0).width - toggle.segmentRect(1).width) < 0.001 && toggle.segmentRect(1).minX - toggle.segmentRect(0).maxX == SegmentedToggle.segmentGap, "Two equal segments, 2 pt apart")
        expect(toggle.segmentCount == 2 && toggle.label(forSegment: 0) == "PNG" && toggle.label(forSegment: 1) == "JPG" && toggle.selectedSegment == 0, "PNG | JPG with PNG selected")

        // Accessibility: a group "Image format" with two radio-button children.
        expect(toggle.isAccessibilityElement() && toggle.accessibilityRole() == .radioGroup && toggle.accessibilityLabel() == "Image format", "The toggle is the group Image format")
        let kids = (toggle.accessibilityChildren() as? [NSAccessibilityElement]) ?? []
        expect(kids.map { $0.accessibilityLabel() ?? "" } == ["PNG", "JPG"] && kids.allSatisfy { $0.accessibilityRole() == .radioButton && ($0.accessibilityParent() as AnyObject?) === toggle }, "Two children, PNG and JPG, radio buttons parented to the group")
        expect(kids.map { ($0.accessibilityValue() as? NSNumber)?.intValue ?? -1 } == [1, 0], "The selected child reads 1 and the other 0")
        expect(kids.allSatisfy { toggle.bounds.contains($0.accessibilityFrameInParentSpace()) } && kids[1].accessibilityFrameInParentSpace().minX > kids[0].accessibilityFrameInParentSpace().maxX - 0.5, "Each child's frame is its own segment")
        target.hits.removeAll()
        expect(kids[1].accessibilityPerformPress() && toggle.selectedSegment == 1 && target.hits == ["format:1"], "Pressing the JPG child selects it and sends the action once")
        expect((kids[0].accessibilityValue() as? NSNumber)?.intValue == 0 && (kids[1].accessibilityValue() as? NSNumber)?.intValue == 1, "The children follow the selection")
        toggle.selectedSegment = 0
        expect(target.hits == ["format:1"], "Assigning the selection does not send the action")
        toggle.selectedSegment = 9
        expect(toggle.selectedSegment == 1, "The selection clamps to a real segment")
        toggle.selectedSegment = 0

        // Keyboard: one tab stop; Left and Right move, Space switches.
        expect(toggle.acceptsFirstResponder && window.makeFirstResponder(toggle) && window.firstResponder === toggle, "The toggle takes keyboard focus")
        expect(toggle.style(ofSegment: 0).focusRing && !toggle.focusRingMaskBounds.isEmpty && toggle.focusRingType == .exterior, "Focus rings the control")
        target.hits.removeAll()
        toggle.keyDown(with: keyEvent(124, in: window))
        expect(toggle.selectedSegment == 1 && target.hits == ["format:1"], "Right selects JPG")
        toggle.keyDown(with: keyEvent(124, in: window))
        expect(toggle.selectedSegment == 1 && target.hits == ["format:1"], "Right at the end does nothing")
        toggle.keyDown(with: keyEvent(123, in: window))
        expect(toggle.selectedSegment == 0 && target.hits == ["format:1", "format:0"], "Left selects PNG")
        toggle.keyDown(with: keyEvent(123, in: window))
        expect(toggle.selectedSegment == 0 && target.hits.count == 2, "Left at the start does nothing")
        toggle.keyDown(with: keyEvent(49, in: window))
        expect(toggle.selectedSegment == 1 && target.hits.last == "format:1", "Space switches to the other segment")
        toggle.keyDown(with: keyEvent(49, in: window))
        expect(toggle.selectedSegment == 0 && target.hits.last == "format:0", "Space switches back")

        // Mouse: a click on a segment selects it; a press that slides off cancels.
        func point(_ segment: Int, dx: CGFloat = 0) -> (NSEvent.EventType) -> NSEvent {
            let centre = toggle.convert(NSPoint(x: toggle.segmentRect(segment).midX + dx, y: 18), to: nil)
            return { type in NSEvent.mouseEvent(with: type, location: centre, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)! }
        }
        target.hits.removeAll()
        toggle.mouseDown(with: point(1)(.leftMouseDown))
        expect(toggle.pressedSegment == 1 && toggle.state(ofSegment: 1) == .pressed && toggle.selectedSegment == 0, "Pressing JPG shows it pressed without selecting yet")
        expect(abs(toggle.style(ofSegment: 1).fill!.alphaComponent - 0.16) < 0.004, "A pressed segment is label@0.16")
        toggle.mouseUp(with: point(1)(.leftMouseUp))
        expect(toggle.selectedSegment == 1 && toggle.pressedSegment == nil && target.hits == ["format:1"], "Releasing on it selects JPG")
        toggle.mouseDown(with: point(0)(.leftMouseDown))
        toggle.mouseDragged(with: point(1)(.leftMouseDragged))
        expect(toggle.pressedSegment == nil, "Sliding off cancels the press")
        toggle.mouseUp(with: point(1)(.leftMouseUp))
        expect(toggle.selectedSegment == 1 && target.hits == ["format:1"], "Releasing elsewhere changes nothing")
        toggle.mouseDown(with: point(1)(.leftMouseDown)); toggle.mouseUp(with: point(1)(.leftMouseUp))
        expect(target.hits == ["format:1"], "Choosing the selected segment sends nothing")
        toggle.selectedSegment = 0

        // States and styles.
        toggle.setHoveredSegment(1)
        expect(toggle.state(ofSegment: 1) == .hover && toggle.state(ofSegment: 0) == .selected && abs(toggle.style(ofSegment: 1).fill!.alphaComponent - 0.08) < 0.004, "A hovered segment is label@0.08")
        toggle.setHoveredSegment(nil)
        expect(toggle.state(ofSegment: 1) == .rest && abs(toggle.style(ofSegment: 1).fill!.alphaComponent - 0.06) < 0.004, "An unselected segment rests on label@0.06")
        expect(abs(toggle.style(ofSegment: 0).fill!.alphaComponent - 0.20) < 0.004 && toggle.style(ofSegment: 0).strongText, "The selected segment is accent@0.20")
        expect(toggle.textFont(forSegment: 0).pointSize == 20 && toggle.textFont(forSegment: 1).pointSize == 20, "Both titles are 20 pt")
        let selectedWeight = (toggle.textFont(forSegment: 0).fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
        let restWeight = (toggle.textFont(forSegment: 1).fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
        expect(selectedWeight > restWeight, "The selected title is heavier (bodyStrong), not just tinted")
        func raster() -> NSBitmapImageRep {
            let rep = toggle.bitmapImageRepForCachingDisplay(in: toggle.bounds)!
            toggle.cacheDisplay(in: toggle.bounds, to: rep)
            return rep
        }
        let scale = CGFloat(raster().pixelsWide) / toggle.bounds.width
        func plateAlpha(_ rep: NSBitmapImageRep, segment: Int) -> CGFloat {
            let rect = toggle.segmentRect(segment)
            return rep.colorAt(x: Int((rect.minX + 6) * scale), y: Int(18 * scale))?.alphaComponent ?? -1
        }
        let drawn = raster()
        expect(plateAlpha(drawn, segment: 0) > plateAlpha(drawn, segment: 1) + 0.08, "The selected segment's plate is visibly stronger than the unselected one's (\(plateAlpha(drawn, segment: 0)) vs \(plateAlpha(drawn, segment: 1)))")
        expect(plateAlpha(drawn, segment: 1) > 0.02, "The unselected segment still rests on a faint plate")

        // Display options.
        toggle.accessibility = contrast
        expect(abs(toggle.style(ofSegment: 1).fill!.alphaComponent - 0.06) < 0.004 && toggle.style(ofSegment: 1).borderWidth == 1 && abs(toggle.style(ofSegment: 0).fill!.alphaComponent - 0.32) < 0.004,
               "Increase Contrast outlines the unselected plate and strengthens the selected one; the unselected fill stays 0.06 so its label keeps its contrast")
        toggle.accessibility = differentiate
        expect(toggle.style(ofSegment: 0).strongText && toggle.style(ofSegment: 0).indicator && toggle.style(ofSegment: 0).borderWidth == 2 && !toggle.style(ofSegment: 1).indicator,
               "Differentiate Without Color adds a 2 pt outline and the capsule to the selected segment only")
        // Pixels: the drawn selected segment differs from the plain drawing by more than hue, and the unselected one is untouched.
        toggle.accessibility = .none
        let plainRaster = raster()
        toggle.accessibility = differentiate
        let dwcRaster = raster()
        func changedPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, segment: Int) -> Int {
            let rect = toggle.segmentRect(segment); var count = 0
            for y in 0..<a.pixelsHigh { for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), let q = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(p.redComponent - q.redComponent) + abs(p.greenComponent - q.greenComponent) + abs(p.blueComponent - q.blueComponent) > 0.12 { count += 1 }
            } }
            return count
        }
        expect(changedPixels(plainRaster, dwcRaster, segment: 0) > 200 && changedPixels(plainRaster, dwcRaster, segment: 1) == 0,
               "Under Differentiate Without Color the selected segment is drawn differently (\(changedPixels(plainRaster, dwcRaster, segment: 0)) px) and the other is not")
        toggle.accessibility = .none

        // Disabled.
        toggle.isEnabled = false
        target.hits.removeAll()
        toggle.keyDown(with: keyEvent(124, in: window))
        toggle.mouseDown(with: point(1)(.leftMouseDown)); toggle.mouseUp(with: point(1)(.leftMouseUp))
        expect(toggle.selectedSegment == 0 && target.hits.isEmpty && toggle.state(ofSegment: 1) == .disabled && !toggle.acceptsFirstResponder, "A disabled toggle ignores keys and clicks")
        expect(toggle.style(ofSegment: 1).contentAlpha == 0.38 && !kids[1].accessibilityPerformPress() && !kids[1].isAccessibilityEnabled(), "A disabled toggle dims its content and refuses VoiceOver presses")
        toggle.isEnabled = true
        toggle.removeFromSuperview()
    }

    /// Pixels, not tokens: a tool glyph drawn on the window colour, in each of the four appearances, with and without Increase Contrast.
    /// The tools are two-state buttons like the real ones: a toggle cell dims its own image under the tint, which a momentary button
    /// never does (F-R-002: an unselected tool sat near 4:1 whatever Increase Contrast asked for).
    private static func glyphContrastTests() {
        func drawn(_ appearance: NSAppearance, options: ChromeAccessibility, enabled: Bool, toggle: Bool) -> CGFloat {
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 70))
            host.wantsLayer = true; host.appearance = appearance
            appearance.performAsCurrentDrawingAppearance { host.layer?.backgroundColor = DesignTokens.Palette.Surface.window.cgColor }
            let tool = CommandButton(title: "", target: nil, action: nil)
            if toggle { tool.setButtonType(.toggle); tool.state = .off }
            tool.icon = .paintbrush; tool.accessibility = options; tool.isEnabled = enabled
            GlassChrome.fix(tool, GlassChrome.Metrics.iconButton)
            tool.frame.origin = NSPoint(x: 28, y: 12)
            host.addSubview(tool)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false; window.appearance = appearance; window.contentView = host
            host.layoutSubtreeIfNeeded(); tool.display()
            return ContrastProbe.measure(host, appearance: appearance, plateAt: NSPoint(x: 3, y: 3), textFrames: [tool.frame]).textRatios[0]
        }
        for toggle in [false, true] {
            let kind = toggle ? "two-state tool" : "command"
            for (name, appearance) in ContrastProbe.appearances {
                let high = name.contains("increaseContrast")
                let options = high ? contrast : plain
                let enabled = drawn(appearance, options: options, enabled: true, toggle: toggle), off = drawn(appearance, options: options, enabled: false, toggle: toggle)
                expect(enabled >= 7, "An enabled \(kind) glyph is drawn at \(enabled):1 or better on the window colour (\(name))")
                expect(off > 1.2 && enabled / off >= 2, "A disabled \(kind) glyph is visibly distinct from an enabled one (\(name): \(off) against \(enabled))")
                // Increase Contrast: the unselected glyph is near the full label colour and a disabled one still reads at 3:1.
                if high { expect(enabled >= 14 && off >= 3, "Increase Contrast: \(kind) glyph \(enabled):1 enabled and \(off):1 disabled (\(name))") }
            }
            for (name, appearance) in [("light", ContrastProbe.appearances[0].appearance), ("dark", ContrastProbe.appearances[1].appearance)] {
                let base = drawn(appearance, options: plain, enabled: true, toggle: toggle), high = drawn(appearance, options: contrast, enabled: true, toggle: toggle)
                expect(high >= base && high >= 14, "Increase Contrast keeps the \(kind) glyph at full label strength (\(name): \(base) -> \(high))")
                let offBase = drawn(appearance, options: plain, enabled: false, toggle: toggle), offHigh = drawn(appearance, options: contrast, enabled: false, toggle: toggle)
                expect(offHigh >= offBase + 1, "Increase Contrast lifts a disabled \(kind) glyph (\(name): \(offBase) -> \(offHigh))")
            }
        }
    }

    private static func differentiateTests() {
        DisplayOptions.override = DisplayOptions(differentiateWithoutColor: true)
        defer { DisplayOptions.override = .none }
        expect(ChromeAccessibility.live.differentiateWithoutColor && !ChromeAccessibility.live.increaseContrast, "The live chrome options read the injected Differentiate Without Color")
        let rig = makeRig(NSSize(width: 980, height: 640))
        let brush = rig.chrome.toolButtons["brush"]!
        brush.state = .on
        expect(!brush.showsIndicator, "Before the options are observed the chrome still has the old ones")
        rig.box.value = .live
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(brush.showsIndicator && brush.indicatorLayer.superlayer === brush.layer && !brush.indicatorLayer.isHidden, "Observing Differentiate Without Color shows the capsule under the selected tool")
        expect(rig.chrome.toolButtons.filter { $0.value.showsIndicator }.keys.sorted() == ["brush"], "Only the selected tool carries it")
        rig.chrome.toolButtons["line"]!.state = .on
        brush.state = .off
        expect(!brush.showsIndicator && brush.indicatorLayer.isHidden && rig.chrome.toolButtons["line"]!.showsIndicator, "The capsule follows the selection and the old one is hidden at once")
        DisplayOptions.override = .none
        rig.box.value = .live
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(!rig.chrome.toolButtons["line"]!.showsIndicator, "Switching it off removes the capsule")
        expect(rig.chrome.snapButton.isPrimary && !rig.chrome.snapButton.showsIndicator, "Snap never carries the capsule")
        DisplayOptions.override = DisplayOptions(differentiateWithoutColor: true)
        rig.box.value = .live
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(!rig.chrome.snapButton.showsIndicator, "Not even under Differentiate Without Color")
    }

    // MARK: GlassSurfaceView (one plate per group) and ChromeFillCell

    private static func button(_ title: String = "", size: NSSize = GlassChrome.Metrics.iconButton) -> CommandButton {
        let button = CommandButton(title: title, target: nil, action: nil)
        button.setButtonType(.toggle)
        button.icon = .crosshairs
        GlassChrome.fix(button, size)
        return button
    }

    private static func borderAlpha(_ layer: CALayer?) -> CGFloat {
        layer?.borderColor.flatMap { NSColor(cgColor: $0)?.alphaComponent } ?? -1
    }

    private static func surfaceTests() {
        typealias M = GlassChrome.Metrics
        let (_, content) = window(NSSize(width: 400, height: 200))
        func place(_ plate: GlassSurfaceView, y: CGFloat) {
            content.addSubview(plate)
            plate.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10).isActive = true
            plate.topAnchor.constraint(equalTo: content.topAnchor, constant: y).isActive = true
        }
        let first = button(), second = button()
        let plate = GlassChrome.plate([first, second], identifier: "Pair", accessibility: plain)
        place(plate, y: 10)
        content.layoutSubtreeIfNeeded()
        expect(plate.identifier?.rawValue == "Pair" && plate.arrangedViews.count == 2, "A plate carries its identifier and its controls")
        expect(plate.frame.size == NSSize(width: M.groupInset * 2 + 48 * 2 + M.groupSpacing, height: 44), "A plate hugs its controls: 4 pt inset, 2 pt between (\(plate.frame.size))")
        expect(plate.cornerRadius == DesignTokens.Radius.xl && plate.layer?.cornerRadius == 16, "A group plate is rounded at Radius.xl (16)")
        expect(first.layer?.cornerRadius == DesignTokens.Radius.concentric(outer: plate.cornerRadius, inset: M.groupInset), "The fills inside are concentric with the plate: 16 - 4 = 12")
        expect(abs(first.frame.minX - M.groupInset) < 0.5 && abs(first.frame.minY - M.groupInset) < 0.5 && first.frame.size == M.iconButton, "A control sits 4 pt inside the plate at its own size")
        expect(plate.style == .regular && plate.tintColor == nil, "One glass variant, never tinted")
        if #available(macOS 27, *) {
            expect(plate.effectIsInteractive, "A plate holds interactive controls, so it opts into the system press response on macOS 27")
        } else {
            notes.append("effectIsInteractive (macOS 27 only)")
        }
        expect(plate.transparencyPlate == nil && plate.layer?.borderWidth == 0, "Default: material glass, no plate, no border")
        expect(plate.contentView?.subviews.contains { $0 is NSGlassEffectView } == false, "No glass inside the plate")

        // A hidden control leaves no slot: the plate narrows and the first control does not move.
        second.isHidden = true
        content.layoutSubtreeIfNeeded()
        expect(plate.frame.width == M.groupInset * 2 + 48 && first.frame.minX == M.groupInset, "A hidden control collapses out of the plate without moving its neighbour (\(plate.frame.width))")
        second.isHidden = false
        content.layoutSubtreeIfNeeded()
        expect(plate.frame.width == M.groupInset * 2 + 48 * 2 + M.groupSpacing, "Showing it widens the plate again")

        // Increase Contrast: a 1 pt label-color border at 0.6 on the plate.
        plate.accessibility = contrast
        expect(plate.showsContrastBorder && plate.layer?.borderWidth == 1 && abs(borderAlpha(plate.layer) - 0.6) < 0.01, "Increase Contrast borders the plate: 1 pt, label color at 0.6")
        expect(plate.transparencyPlate == nil, "Increase Contrast alone keeps the glass")
        plate.accessibility = plain
        expect(plate.layer?.borderWidth == 0, "Clearing Increase Contrast removes the border")

        // Reduce Transparency: no tint, an opaque content-colored plate with a 1 pt separator border, same radius.
        let calmer = ChromeAccessibility(reduceTransparency: true, increaseContrast: false, reduceMotion: false)
        plate.appearance = NSAppearance(named: .aqua)
        plate.accessibility = calmer
        content.layoutSubtreeIfNeeded()
        expect(plate.tintColor == nil && plate.style == .regular, "Reduce Transparency: regular style, no tint")
        guard let solid = plate.transparencyPlate else { expect(false, "Reduce Transparency inserts a solid plate"); return }
        expect(!solid.isHidden && solid.layer?.backgroundColor?.alpha == 1, "The solid plate is opaque")
        expect(sameColor(solid.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }, DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.content, for: NSAppearance(named: .aqua)!)), "The plate is surface.content")
        expect(solid.layer?.borderWidth == 1 && solid.layer?.cornerRadius == plate.cornerRadius, "It has a 1 pt border and the plate's radius")
        expect(solid.frame == plate.contentView?.bounds && plate.contentView?.subviews.first === solid, "It sits behind the content and fills the plate")
        plate.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: true, reduceMotion: false)
        expect(plate.transparencyPlate != nil && plate.layer?.borderWidth == 1, "Both options: the solid plate and the contrast border")
        plate.accessibility = plain
        expect(plate.transparencyPlate == nil && solid.isHidden, "Clearing Reduce Transparency hides the plate again")

        // Shape: a radius never exceeds half the short side.
        expect(GlassShape.rounded(99).radius(for: NSSize(width: 48, height: 40)) == 20 && GlassShape.capsule.radius(for: NSSize(width: 148, height: 36)) == 18, "Shapes clamp: rounded to half the short side, capsule is height / 2")
        plate.shape = .capsule
        expect(plate.cornerRadius == 22, "A capsule plate rounds to half its 44 pt height")
        plate.shape = .rounded(16)
        expect(plate.cornerRadius == 16, "Changing the shape updates the radius")

        // ChromeFillCell: invisible at rest, the same 0.08 hover fill as a button, explicit size.
        let swatch = NSView()
        let cell = ChromeFillCell(swatch, size: M.iconButton)
        let (_, cellContent) = window(NSSize(width: 100, height: 60))
        cellContent.addSubview(cell)
        cell.appearance = NSAppearance(named: .aqua)
        cellContent.layoutSubtreeIfNeeded()
        expect(cell.frame.size == M.iconButton && swatch.frame == cell.bounds, "A cell has its explicit size and its control fills it")
        expect(cell.layer?.backgroundColor == nil && cell.layer?.cornerRadius == 12, "A cell draws nothing at rest and is 12 pt round")
        cell.setHovered(true)
        expect(abs((cell.plate.style.fill?.alphaComponent ?? 0) - 0.08) < 0.001 && cell.layer?.backgroundColor != nil, "Hover is the 0.08 label-color fill")
        cell.accessibility = contrast
        expect(abs((cell.plate.style.fill?.alphaComponent ?? 0) - 0.16) < 0.001, "Increase Contrast doubles it")
        cell.accessibility = plain
        cell.setHovered(false)
        expect(cell.layer?.backgroundColor == nil, "Leaving clears the fill")
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["100%"])
        let centered = ChromeFillCell(popup, size: NSSize(width: 70, height: 36), fit: .centered(inset: 4))
        cellContent.addSubview(centered)
        centered.frame.origin = NSPoint(x: 0, y: 20)
        cellContent.layoutSubtreeIfNeeded()
        expect(abs(popup.frame.minX - 4) < 0.5 && abs(popup.frame.midY - 18) < 1 && abs(popup.frame.maxX - 66) < 0.5, "A centred cell insets the control horizontally and centres it vertically")
        centered.setHovered(true)
        centered.isHidden = true
        expect(!centered.isHovered, "Hiding a cell clears hover")

        // The factory: a plate is the only glass; the container around a bar only groups plates.
        let bar = NSView()
        let container = GlassChrome.container(around: bar, identifier: "Bar")
        expect(container.identifier?.rawValue == "Bar" && container.spacing == M.containerSpacing && container.contentView === bar, "A bar container holds the bar view with the container spacing")
        expect(M.containerSpacing < M.groupGap, "Container spacing stays below the group gap so plates never fuse")
        expect(M.toolButton == NSSize(width: 44, height: 36) && M.iconButton == NSSize(width: 48, height: 36) && M.commandHeight == 36 && M.headerHeight == 44 && M.groupGap == 12,
               "Metrics match the plan: 36 pt controls on 44 pt plates")
        expect(M.iconPointSize == 22 && M.groupSpacing == 2 && M.groupInset == 4 && DesignTokens.Size.hitMin == 36, "Spacing, inset and type metrics match the plan; every control keeps a 36 pt hit height")
    }


    // MARK: what an external client sees

    /// The editor bar, the Size panel and the Color panel walked from their windows down, the way the AX server publishes them: every plate's controls
    /// are reachable with a name, a role and a value, AXPress works on a reached control, and every parent agrees with the tree.
    private static func externalTreeChecks() {
        func reach(_ tree: AXTree.Tree, _ role: NSAccessibility.Role, _ label: String, _ what: String) -> AXTree.Node? {
            let node = tree.find(role, label)
            expect(node != nil, "\(what): \(role.rawValue) \"\(label)\" is reachable from the window. Tree:\n\(tree.outline)")
            return node
        }

        // The bar: plates that are not labelled elements. A regression guard: the controls were reachable before and must stay so.
        let rig = makeRig(NSSize(width: 1100, height: 700))
        var tree = AXTree.walk(rig.window)
        let buttons = ["Hide", "Photos", "Snap", "Select tool", "Brush tool", "Line tool", "Ellipse tool", "Rectangle tool", "Fill tool", "Eraser tool", "Text tool", "Arrow tool",
                       "Crop tool", "Drawing colors", "Font", "Undo", "Clear image", "Resize…", "Save", "History", "Upload image"]
        for name in buttons { _ = reach(tree, .button, name, "bar") }
        _ = reach(tree, .menuButton, "Toolbox", "bar"); _ = reach(tree, .slider, "Drawing size", "bar")
        _ = reach(tree, .popUpButton, "Canvas zoom", "bar"); _ = reach(tree, .checkBox, "Export at original size", "bar")
        if let format = reach(tree, .radioGroup, "Image format", "bar") {
            expect(tree.children(of: format).map { $0.label ?? "" } == ["PNG", "JPG"], "bar: the format toggle shows PNG and JPG")
        }
        let tools = tree.nodes.filter { ($0.label ?? "").hasSuffix(" tool") }
        expect(tools.count == 10 && tools.map { $0.label ?? "" } == buttons.filter { $0.hasSuffix(" tool") }, "bar: the ten tools come in reading order (\(tools.count))")
        let barNames = Set(buttons + ["Toolbox", "Drawing size", "Canvas zoom", "Export at original size", "Image format"])
        let barProblems = tree.parentProblems { barNames.contains($0.label ?? "") }
        expect(barProblems.isEmpty, "bar: the named controls' parents agree with the tree and lead back to the window: \(barProblems.prefix(3))")

        // The Size panel: the track and the five presets.
        let (window, content) = window(NSSize(width: 400, height: 300))
        let slider = BezelSizeSlider(frame: NSRect(x: 40, y: 200, width: 48, height: 36))
        content.addSubview(slider)
        slider.panelSetup = offscreenPanel
        slider.showPopover()
        guard let sizeWindow = slider.panelWindow else { return expect(false, "The Size panel is up") }
        tree = AXTree.walk(sizeWindow)
        if let group = reach(tree, .group, "Size", "Size panel") {
            expect(tree.children(of: group).count == 4, "Size panel: the panel group holds the title, the value, the track and the presets (\(tree.children(of: group).count))")
        }
        if let track = reach(tree, .slider, "Size", "Size panel") { expect(track.value != nil && track.enabled, "Size panel: the track has a value and is enabled") }
        if let presets = reach(tree, .radioGroup, "Size presets", "Size panel") {
            expect(tree.children(of: presets).map { $0.label ?? "" } == ["Size 2", "Size 4", "Size 7", "Size 9", "Size 12"], "Size panel: the five presets come in order: \(tree.children(of: presets).map { $0.label ?? "" })")
            if let seven = tree.children(of: presets).first(where: { $0.label == "Size 12" }) {
                let before = slider.doubleValue
                expect(AXTree.press(seven) && slider.doubleValue == before, "Size accepts AXPress before closing its panel")
                expect(waitForMain { slider.doubleValue != before }, "The accepted Size AXPress applies the reached preset")
            }
        }
        expect(tree.parentProblems().isEmpty, "Size panel: every parent agrees with the tree: \(tree.parentProblems().prefix(3))")
        expect(tree.shapeProblems().isEmpty, "Size panel: no AXUnknown wrapper, role-less node (\(tree.shapeProblems().count)): \(tree.shapeProblems().prefix(3))")
        slider.dismissPopover()

        // The Color panel: ten swatches and the Custom colour row.
        var picked: [Int] = []
        let swatches = (0..<10).map { index -> BezelColorButton in
            let swatch = BezelColorButton(frame: NSRect(x: 0, y: 0, width: 42, height: 32))
            swatch.title = ""; swatch.isBordered = false
            swatch.setAccessibilityLabel("Color \(index + 1)")
            swatch.tag = index
            return swatch
        }
        let swatchTarget = SwatchTarget { picked.append($0) }
        for swatch in swatches { swatch.target = swatchTarget; swatch.action = #selector(SwatchTarget.picked(_:)) }
        let custom = GlassChoiceButton(title: "Custom color…", kind: .command)
        let palette = ColorPaletteContent(title: NSTextField(labelWithString: "Drawing colors"), swatches: swatches, custom: custom, accessibility: .none)
        let host = GlassPanelHost(plates: palette.plates, identifier: "Color", accessibilityLabel: "Drawing colors")
        offscreenPanel(host)
        host.accessibility = .none
        host.show(relativeTo: slider.bounds, of: slider, preferredEdge: .minY, makeKey: false)
        tree = AXTree.walk(host.window)
        if let group = reach(tree, .group, "Drawing colors", "Color panel") {
            let kids = tree.children(of: group).filter { $0.role != .staticText }
            expect(kids.map { $0.label ?? "" } == (1...10).map { "Color \($0)" } + ["Custom color…"], "Color panel: ten swatches and Custom color… in reading order: \(kids.map { $0.label ?? "" })")
            expect(kids.dropLast().allSatisfy { $0.role == .radioButton } && kids.last?.role == .button, "Color panel: the swatches are radio choices and Custom is a button")
        }
        expect(tree.find(.radioButton, "Color 1")?.value as? NSNumber == 0, "Unchosen production-style Color presets expose value zero")
        swatches[0].state = .on
        expect(AXTree.walk(host.window).find(.radioButton, "Color 1")?.value as? NSNumber == 1, "Chosen Color presets expose value one")
        if let third = tree.find(.radioButton, "Color 3") {
            expect(AXTree.press(third) && picked.isEmpty, "Color accepts preset AXPress before closing its panel")
            expect(waitForMain { picked == [2] }, "The accepted Color AXPress chooses the reached swatch exactly once")
        }
        expect(tree.parentProblems().isEmpty, "Color panel: every parent agrees with the tree: \(tree.parentProblems().prefix(3))")
        expect(tree.shapeProblems().isEmpty, "Color panel: no AXUnknown wrapper, role-less node (\(tree.shapeProblems().count)): \(tree.shapeProblems().prefix(3))")
        host.close()
        let opener = BezelHoverButton(frame: NSRect(x: 40, y: 200, width: 48, height: 36))
        opener.setAccessibilityLabel("Drawing colors")
        let target = PalettePressTarget()
        opener.target = target; opener.action = #selector(PalettePressTarget.press(_:))
        content.addSubview(opener)
        target.onPress = { host.show(relativeTo: opener.bounds, of: opener, preferredEdge: .minY, makeKey: false) }
        func awaitPress(_ hits: Int) {
            let deadline = Date(timeIntervalSinceNow: 1)
            while target.hits < hits, Date() < deadline {
                _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        }
        let accepted = opener.accessibilityPerformPress()
        expect(accepted && !host.isShown && target.hits == 0, "Color accepts AXPress before refreshing its button representation")
        awaitPress(1)
        expect(host.isShown && target.hits == 1, "The accepted Color press opens its panel exactly once (shown=\(host.isShown), hits=\(target.hits))")
        host.close()
        opener.performClick(nil)
        expect(!host.isShown && target.hits == 1, "The button-cell click route also waits for the accessibility reply")
        awaitPress(2)
        expect(host.isShown && target.hits == 2, "The button-cell click route opens Color exactly once")
        host.close()
        let openerTree = AXTree.walk(window)
        if let reached = reach(openerTree, .button, "Drawing colors", "Color opener") {
            expect(reached.object === opener, "The Color opener publishes its own accessibility action")
            expect(AXTree.press(reached) && !host.isShown && target.hits == 2, "Reached AXPress succeeds before dispatch")
            awaitPress(3)
            expect(host.isShown && target.hits == 3, "Reached AXPress opens Color and dispatches exactly once")
            host.close()
            opener.isEnabled = false
            expect(!AXTree.press(reached) && !host.isShown && target.hits == 3, "A disabled Color opener sends no action")
        }
        _ = window
    }

    @MainActor
    private final class SwatchTarget: NSObject {
        let handler: (Int) -> Void
        init(_ handler: @escaping (Int) -> Void) { self.handler = handler }
        @objc func picked(_ sender: NSButton) { handler(sender.tag) }
    }

    // MARK: ModernEditorChrome

    private struct Rig {
        let window: NSWindow, content: NSView, chrome: ModernEditorChrome, controls: ModernEditorChrome.SharedControls
        let target: ActionTarget, box: AccessibilityBox, size: NSSize
    }

    private static let longStatus = "Brush · Unsaved changes · 1000 × 700 · 48 KB and then some more words so it can never fit"

    private static func makeRig(_ size: NSSize, status: String? = nil) -> Rig {
        let target = ActionTarget(), box = AccessibilityBox()
        let (window, content) = window(size)
        // The rig builds the shared controls with the same type styles App+ModernChrome gives them, so the width budget is the real one.
        func label(_ text: String, _ style: DesignTokens.Typography.Style) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = DesignTokens.Typography.font(style)
            return field
        }
        let zoom = ZoomPopUpButton(frame: .zero, pullsDown: false)
        zoom.addItems(withTitles: ["25%", "50%", "75%", "100%", "150%", "200%"])
        zoom.font = DesignTokens.Typography.font(.body)
        zoom.setAccessibilityLabel("Canvas zoom")
        let format = SegmentedToggle(titles: ["PNG", "JPG"])
        let toolbox = NSPopUpButton(frame: .zero, pullsDown: true)
        toolbox.addItems(withTitles: ["Toolbox", "About OpenSnap", "Quit OpenSnap"])
        toolbox.font = .systemFont(ofSize: 20)
        toolbox.setAccessibilityLabel("Toolbox")
        let palette = BezelHoverButton(title: "Color…", target: nil, action: nil)
        palette.font = DesignTokens.Typography.font(.body)
        palette.setAccessibilityLabel("Drawing colors")
        palette.image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        let original = GlassChoiceButton(title: "Original size", kind: .toggle, indicator: .checkbox, layout: .row)
        original.font = DesignTokens.Typography.font(.body)
        original.setAccessibilityLabel("Export at original size")
        let controls = ModernEditorChrome.SharedControls(
            canvas: NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700)), canvasBorder: NSView(),
            status: label(status ?? longStatus, .caption), sizeLabel: label("Size · 6.75", .body),
            widthControl: BezelSizeSlider(frame: .zero), paletteButton: palette, zoomControl: zoom, dragFormatControl: format,
            dragOriginalControl: original, dragExportView: NSView(), toolbox: toolbox)
        let actions = ModernEditorChrome.Actions(
            target: target, hide: #selector(ActionTarget.hide(_:)), photos: #selector(ActionTarget.photos(_:)), saveHistory: #selector(ActionTarget.saveHistory(_:)),
            showHistory: #selector(ActionTarget.showHistory(_:)), chooseTool: #selector(ActionTarget.chooseTool(_:)), snap: #selector(ActionTarget.snap(_:)),
            cancelFrame: #selector(ActionTarget.cancelFrame(_:)), font: #selector(ActionTarget.font(_:)),
            undo: #selector(ActionTarget.undo(_:)), wipe: #selector(ActionTarget.wipe(_:)),
            resize: #selector(ActionTarget.resize(_:)), share: #selector(ActionTarget.share(_:)))
        let chrome = ModernEditorChrome(controls: controls, actions: actions, toolOrder: toolOrder, accessibility: { box.value })
        chrome.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor), chrome.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: content.topAnchor), chrome.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        content.layoutSubtreeIfNeeded()
        return Rig(window: window, content: content, chrome: chrome, controls: controls, target: target, box: box, size: size)
    }

    private static func visibleControls(_ rig: Rig) -> [NSControl] {
        var found: [NSControl] = []
        func walk(_ view: NSView) {
            if view.isHidden || view === rig.chrome.scrollView || view === rig.controls.canvasBorder { return }
            if let control = view as? NSControl { found.append(control); return }
            for child in view.subviews { walk(child) }
        }
        walk(rig.chrome)
        return found
    }

    private static func containers(_ rig: Rig) -> [NSGlassEffectContainerView] {
        var found: [NSGlassEffectContainerView] = []
        func walk(_ view: NSView) {
            if view.isHidden { return }
            if let container = view as? NSGlassEffectContainerView { found.append(container) }
            if view === rig.chrome.scrollView { return }
            for child in view.subviews { walk(child) }
        }
        walk(rig.chrome)
        return found
    }

    private static func allButtons(in view: NSView) -> [NSButton] {
        let own: [NSButton] = (view as? NSButton).map { [$0] } ?? []
        return own + view.subviews.flatMap { allButtons(in: $0) }
    }

    private static func descendantsOf(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendantsOf) }

    private static func surfaces(_ rig: Rig) -> [GlassSurfaceView] {
        var found: [GlassSurfaceView] = []
        func walk(_ view: NSView) {
            if view.isHidden { return }
            if let glass = view as? GlassSurfaceView { found.append(glass) }
            for child in view.subviews { walk(child) }
        }
        walk(rig.chrome)
        return found
    }

    private static func rect(_ view: NSView, in rig: Rig) -> NSRect { view.convert(view.bounds, to: rig.content) }

    private static func describe(_ view: NSView) -> String {
        (view.identifier?.rawValue).map { "#" + $0 } ?? (view as? NSButton).map { "'" + $0.title + "'" } ?? String(describing: type(of: view))
    }

    private static func verifyLayout(_ rig: Rig, _ label: String) {
        rig.content.layoutSubtreeIfNeeded()
        expect(rig.content.bounds.size == rig.size, "\(label): the chrome fits without growing the window (\(rig.content.bounds.size) vs \(rig.size))")
        let chrome = rig.chrome
        let controls = visibleControls(rig)
        expect(controls.count >= 24, "\(label): the visible controls were found (\(controls.count))")
        for control in controls {
            let frame = rect(control, in: rig)
            expect(rig.content.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(label): \(describe(control)) lies inside the window content \(frame)")
            if let parent = control.superview {
                // Layout places alignment rects; a label's frame legitimately extends 2 pt past it for its text inset.
                let placed = control.alignmentRect(forFrame: control.frame)
                expect(parent.bounds.insetBy(dx: -0.5, dy: -0.5).contains(placed), "\(label): \(describe(control)) lies inside its superview \(placed) in \(parent.bounds)")
            }
            expect(!frame.isEmpty && frame.height >= 18, "\(label): \(describe(control)) has a real size \(frame)")
            if !(control is NSImageView) {
                expect((control.font?.pointSize ?? 0) >= 18, "\(label): \(describe(control)) is at least 18 pt (\(control.font?.pointSize ?? 0))")
            }
            if let button = control as? CommandButton, !button.visibleTitle.isEmpty {
                expect(button.fittingSize.width <= button.frame.width + 0.5, "\(label): \(describe(button)) title fits its surface (\(button.fittingSize.width) in \(button.frame.width))")
            }
        }
        for (index, a) in controls.enumerated() {
            for b in controls[(index + 1)...] {
                let overlap = rect(a, in: rig).intersection(rect(b, in: rig))
                expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): \(describe(a)) overlaps \(describe(b)) by \(overlap)")
            }
        }
        let plates = surfaces(rig)
        expect(plates.count == 8, "\(label): eight glass plates, one per group (\(plates.count))")
        for glass in plates {
            let frame = rect(glass, in: rig)
            expect(rig.content.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(label): plate \(describe(glass)) lies inside the content")
            expect(abs(frame.height - 44) < 0.5, "\(label): plate \(describe(glass)) is the 44 pt bar row (\(frame.height))")
            expect(frame.height >= 36 && frame.width >= 36, "\(label): no plate collapsed below 36 pt \(frame.size)")
            let want = glass.arrangedViews.filter { !$0.isHidden }.map { $0.frame.width }.reduce(0, +) + CGFloat(max(0, glass.arrangedViews.filter { !$0.isHidden }.count - 1)) * GlassChrome.Metrics.groupSpacing + 2 * GlassChrome.Metrics.groupInset
            expect(abs(frame.width - want) < 0.5, "\(label): plate \(describe(glass)) hugs its controls (\(frame.width) vs \(want))")
            for control in glass.arrangedViews where !control.isHidden {
                expect(control.frame.height <= frame.height - 2 * GlassChrome.Metrics.groupInset + 0.5, "\(label): \(describe(control)) is inset 4 pt inside its plate")
            }
        }
        let scroll = rect(chrome.scrollView, in: rig)
        expect(scroll.width > 300 && scroll.height > 300, "\(label): the canvas keeps room \(scroll.size)")
        let glassContainers = containers(rig)
        expect(glassContainers.count == 2, "\(label): exactly two glass containers, one per bar (\(glassContainers.count))")
        for container in glassContainers {
            let frame = rect(container, in: rig)
            let overlap = frame.intersection(scroll)
            expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): scroll view is disjoint from \(describe(container)) \(frame) vs \(scroll)")
        }
        for glass in plates {
            let overlap = rect(glass, in: rig).intersection(scroll)
            expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): no plate touches the canvas well (\(describe(glass)))")
        }
        for (index, a) in plates.enumerated() {
            for b in plates[(index + 1)...] {
                let overlap = rect(a, in: rig).intersection(rect(b, in: rig))
                expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): glass plates \(describe(a)) and \(describe(b)) are disjoint")
            }
        }
        // Order: top bar left to right (capture, tools, annotation), then bottom bar left to right (document, view, output).
        expect(!chrome.header.subviews.contains { $0.identifier?.rawValue == "OpenSnapBrand" }, "\(label): the logo is not in the header (no room at minimum width)")
        let toolsAcross = chrome.toolButtons.values.sorted { rect($0, in: rig).minX < rect($1, in: rig).minX }
        expect(toolsAcross.map { $0.identifier?.rawValue ?? "" } == toolOrder, "\(label): tools run left to right in archive order, crop last")
        let topOrder: [NSView] = [chrome.hideButton, rig.controls.toolbox, chrome.photosButton, chrome.snapButton] + toolsAcross
            + [rig.controls.paletteButton, rig.controls.widthControl, chrome.fontButton]
        let topX = topOrder.map { rect($0, in: rig).minX }
        expect(topX == topX.sorted() && Set(topX).count == topX.count, "\(label): top bar order is Hide, Toolbox, Photos, Snap, ten tools, Color, Size, Font (\(topX))")
        let toolbar = rect(chrome.header, in: rig)
        for view in topOrder {
            expect(toolbar.contains(rect(view, in: rig).insetBy(dx: 0.5, dy: 0.5)), "\(label): \(describe(view)) sits inside the top bar")
        }
        let original = rig.controls.dragOriginalControl
        let bottomOrder: [NSView] = [chrome.undoButton, chrome.wipeButton, rig.controls.zoomControl, chrome.resizeButton] + (original.isHidden ? [] : [original])
            + [rig.controls.status, chrome.saveButton, chrome.historyButton, rig.controls.dragFormatControl, rig.controls.dragExportView, chrome.shareButton]
        let bottomX = bottomOrder.map { rect($0, in: rig).minX }
        expect(bottomX == bottomX.sorted() && Set(bottomX).count == bottomX.count,
               "\(label): bottom bar order is Undo, Wipe, Zoom, Resize, Original size, status, Save, History, format, Drag, Upload (\(bottomX))")
        let bottomBar = rect(descendantsOf(chrome).first { $0.identifier?.rawValue == "OpenSnapFooter" }!, in: rig)
        for view in bottomOrder {
            expect(bottomBar.contains(rect(view, in: rig).insetBy(dx: 0.5, dy: 0.5)), "\(label): \(describe(view)) sits inside the bottom bar")
        }
        let formatControl = rig.controls.dragFormatControl, formatFit = formatControl.fittingSize.width
        let formatWidth = rect(formatControl, in: rig).width
        expect(formatWidth >= formatFit - 0.5 && formatWidth <= formatFit + 2, "\(label): the format toggle hugs its segments (\(formatWidth) pt for a \(formatFit) pt control)")
        expect(formatControl.superview is NSStackView && chrome.surface(for: formatControl)?.identifier?.rawValue == "GlassFooterRow", "\(label): PNG | JPG sits on the footer plate itself, with no plate or cell of its own")
        let footerY = rect(chrome.shareButton, in: rig).midY
        expect(abs(footerY - rect(rig.controls.dragExportView, in: rig).midY) < 0.5 && abs(footerY - rect(rig.controls.zoomControl, in: rig).midY) < 3, "\(label): footer controls share a baseline")
        // The canvas border lives where classic puts it, beside the scroll view and above everything.
        expect(rig.controls.canvasBorder.superview === chrome.scrollView.superview && chrome.subviews.last === rig.controls.canvasBorder, "\(label): the canvas border is a topmost sibling of the scroll view")
        expect(chrome.scrollView.documentView === rig.controls.canvas && chrome.wellIsSolid == !chrome.frameMode, "\(label): the scroll view hosts the canvas on a solid well (a hole in Frame mode)")
    }

    private static func chromeTests(glyphs: Bool) {
        let tag = glyphs ? "glyphs" : "symbols"
        let minimum = NSWindow.contentRect(forFrameRect: NSRect(x: 0, y: 0, width: ModernEditorChrome.minimumWindowWidth, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable]).size
        for size in [minimum, NSSize(width: 1024, height: 740)] {
            let label = "\(tag) \(Int(size.width))x\(Int(size.height))"
            let rig = makeRig(size)
            verifyLayout(rig, label)
            glassDepthChecks(rig, label)
            tintChecks(rig, label)
            displayOptionChecks(rig, label)
            semantics(rig, label)
            glassNeckChecks(rig, label)
            redesignChecks(rig, label)
            noRailChecks(rig, label)
            relocatedControlChecks(rig, label, frame: false)
            rig.chrome.frameMode = true
            verifyLayout(rig, label + " frame mode")
            glassDepthChecks(rig, label + " frame mode")
            frameModeChecks(rig, label)
            relocatedControlChecks(rig, label + " frame mode", frame: true)
            rig.chrome.frameMode = false
            verifyLayout(rig, label + " after frame mode")
            toolGroupBalanceChecks(rig, label)
            canvasCentreChecks(rig, label)
            footerUploadChecks(rig, label)
            if size == minimum {
                widthBudgetChecks(rig, label)
                accessibilityChecks(rig, label)
                wellChecks(rig, label)
            }
        }
        canvasReachesMarginChecks(tag, minimum: minimum)
        adaptiveCheckboxChecks(tag, minimum: minimum)
    }

    /// Audit fix 1 (item 3): the Original size checkbox steps aside during an upload only where the measured slot cannot hold it beside the
    /// status minimum and the commands. At 980 it cannot (in every state); at 1440 it can, and everything then fits without overlap.
    private static func unwrapState(_ value: String?) throws -> String {
        guard let value else { throw NSError(domain: "GlassChromeTests", code: 1) }
        return value
    }
    private static func adaptiveCheckboxChecks(_ tag: String, minimum: NSSize) {
        let url = URL(string: "https://cdn.example.com/pics/x.png")!
        let states: [(String, UploadState)] = [("uploading", .uploading(name: String(repeating: "A long screenshot name ", count: 4))), ("Link copied", .success(url: url, copied: true)),
                                               ("error", .failure(message: "Upload to Example S3 failed: the connection was refused."))]
        for width in [980, 1440] as [CGFloat] {
            let rig = makeRig(NSSize(width: width, height: width == 980 ? minimum.height : 740))
            let chrome = rig.chrome, shared = rig.controls, upload = chrome.uploadControls
            let checkbox = shared.dragOriginalControl.fittingSize.width
            let save = rect(group(rig, "GlassSaveGroup"), in: rig), view = rect(group(rig, "GlassViewGroup"), in: rig)
            let measured = save.minX - 12 - (view.maxX + 12)
            expect(abs(chrome.statusSlotWidth() - measured) < 0.5, "\(tag) \(Int(width)): statusSlotWidth is the room the laid-out bar leaves (\(chrome.statusSlotWidth()) vs \(measured))")
            for (name, state) in states {
                let label = "\(tag) \(Int(width)) \(name)"
                upload.apply(state)
                let fits = chrome.slotHasRoomForCheckbox(during: state)
                shared.dragOriginalControl.isHidden = false // forced on: what the bar would do if the rule did not step in
                shared.status.stringValue = state.statusText ?? ""
                shared.status.invalidateIntrinsicContentSize()
                rig.content.layoutSubtreeIfNeeded()
                let status = rect(shared.status, in: rig), box = rect(shared.dragOriginalControl, in: rig)
                if width == 980 && state.isFailure {
                    // F-J7-006: an error gives up its words, not the checkbox. Its narrowest form is "Failed", and the slot holds that beside the box and both commands.
                    let narrowest = try! unwrapState(state.statusVariants.last)
                    expect(fits, "\(label): at 980 the \(Int(chrome.statusSlotWidth())) pt slot holds the checkbox (\(Int(checkbox)) pt) with the error at its narrowest and the commands (\(Int(chrome.slotNeed(for: state))) pt)")
                    expect(narrowest == "Failed" && chrome.statusCellWidth(of: narrowest) <= status.width + 0.5, "\(label): the status (\(Int(status.width)) pt) holds \"\(narrowest)\" whole (\(Int(chrome.statusCellWidth(of: narrowest))) pt)")
                    expect(box.intersection(status).width <= 0.5 && box.maxX <= status.minX + 0.5 && box.width >= checkbox - 0.5, "\(label): the checkbox stands whole and clear of the status (\(box) vs \(status))")
                } else if width == 980 {
                    expect(!fits, "\(label): at 980 the \(Int(chrome.statusSlotWidth())) pt slot cannot hold the checkbox (\(Int(checkbox)) pt) with the status minimum and commands (\(Int(chrome.slotNeed(for: state))) pt)")
                    expect(status.width < ModernEditorChrome.minimumUploadStatusWidth, "\(label): the rule is not vacuous, with the checkbox forced on the status would drop to \(Int(status.width)) pt")
                } else {
                    expect(fits, "\(label): at 1440 the \(Int(chrome.statusSlotWidth())) pt slot holds the checkbox (\(Int(checkbox)) pt) and \(Int(chrome.slotNeed(for: state))) pt of message and commands")
                    expect(status.width >= ModernEditorChrome.minimumUploadStatusWidth - 0.5, "\(label): with the checkbox shown the status keeps \(Int(status.width)) pt")
                    expect(box.intersection(status).width <= 0.5 && box.maxX <= status.minX + 0.5, "\(label): the checkbox stands clear of the status (\(box) vs \(status))")
                }
            }
            upload.apply(.idle)
        }
        // A window between the two: the answer follows the measured width, flipping exactly where the slot grows past the need.
        var previous = false
        for width in stride(from: 980 as CGFloat, through: 1500, by: 20) {
            let rig = makeRig(NSSize(width: width, height: 740))
            let state = UploadState.failure(message: "Upload to Example S3 failed: the connection was refused.")
            let fits = rig.chrome.slotHasRoomForCheckbox(during: state)
            // The toggle sits on the View plate, so the slot the bar leaves with it showing is already net of its place: the need is the message and commands.
            let need = rig.chrome.slotNeed(for: state)
            expect(!rig.controls.dragOriginalControl.isHidden && fits == (rig.chrome.statusSlotWidth() >= need) && (fits || !previous), "\(tag) \(Int(width)): the answer is the measured comparison and never flips back as the window grows")
            expect(fits, "\(tag) \(Int(width)): from the 980 floor up an error keeps the toggle beside it (F-J7-006)")
            previous = fits
        }
        expect(previous, "\(tag): by 1500 pt the checkbox stays beside an error")
    }

    /// R2-014: below 1100 pt the PNG | JPG toggle is one compact button (about 64 pt) that shows the current format and flips on a click; the
    /// room it frees goes to the status line. Wide windows keep both segments.
    private static func formatCompactionChecks() {
        var widths: [CGFloat: CGFloat] = [:]
        for width in [980.0, 1024, 1099, 1100, 1440] as [CGFloat] {
            let rig = makeRig(NSSize(width: width, height: 640))
            rig.chrome.layoutSubtreeIfNeeded()
            guard let toggle = rig.controls.dragFormatControl as? SegmentedToggle else { expect(false, "the format control is the toggle"); return }
            let compact = width < 1100
            widths[width] = toggle.frame.width
            expect(toggle.isCompact == compact, "\(Int(width)): the toggle is \(compact ? "compact" : "two segments") (\(toggle.frame.width) pt)")
            if compact { expect(toggle.frame.width < 80 && toggle.frame.width > 50, "\(Int(width)): the compact toggle is about 64 pt (\(toggle.frame.width))") }
            else { expect(toggle.frame.width > 100, "\(Int(width)): the full toggle keeps both segments (\(toggle.frame.width))") }
        }
        let compact = SegmentedToggle(titles: ["PNG", "JPG"]), target = ActionTarget()
        compact.target = target; compact.action = #selector(ActionTarget.formatChanged(_:))
        let (window, content) = window(NSSize(width: 300, height: 100))
        content.addSubview(compact); compact.frame = NSRect(x: 20, y: 20, width: 64, height: 36)
        compact.isCompact = true
        expect(compact.segmentRect(0) == compact.bounds && compact.segmentRect(1).isEmpty, "Compact draws only the selected format, filling the control")
        compact.setPressedSegment(0); compact.choose(compact.isCompact ? 1 : 0)
        expect(compact.selectedSegment == 1 && target.hits == ["format:1"] && compact.segmentRect(1) == compact.bounds && compact.segmentRect(0).isEmpty, "Choosing switches to the other format, which is then the one shown")
        expect(compact.accessibilityHelp()?.contains("JPG") == true && compact.accessibilityHelp()?.contains("PNG") == true, "The compact button says what it shows and what pressing does")
        _ = window
    }

    /// Audit fix 1 (item 2): "Link copied" shows the link itself, cut in the middle as the slot narrows, and gives up the link before itself.
    // MARK: Toolbox and Zoom as glass choice panels

    private struct ChoiceRig {
        let window: NonorderingWindow, content: NSView, target: MenuTarget, probe: NativeMenuProbe
        var shown: [GlassChoiceWindow] = []
    }

    /// A never-ordered window at a known place on a large screen, so an open panel's frame is placed the way it would be on screen.
    private static func choiceWindow() -> (NonorderingWindow, NSView) {
        let (window, content) = window(NSSize(width: 600, height: 400))
        window.setFrameOrigin(NSPoint(x: 300, y: 300))
        return (window, content)
    }

    private static func anchorOnScreen(_ view: NSView) -> NSRect { view.window!.convertToScreen(view.convert(view.bounds, to: nil)) }

    /// Keeps a panel off screen: a presenter that orders nothing, the panel taken as holding the keyboard, and a large screen.
    private static func offScreen(_ panel: MenuChoicePanel) {
        panel.host.presenter = { _, _ in }
        panel.host.keyStateProbe = { true }
        panel.host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1800, height: 1200)
    }

    /// A fresh open, whatever state the panel was left in.
    private static func reopen(_ button: any PanelOwner) {
        button.choicePanel.host.close()
        button.performClick(nil)
    }

    private static func mouse(_ type: NSEvent.EventType, on view: NSView, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        event(type, in: view.window!, at: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil), flags: flags)
    }

    private static func menuItem(_ title: String, _ action: Selector, key: String = "", target: AnyObject, symbol: String = "square") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private static func toolboxFixture(_ target: MenuTarget) -> (ToolboxPopUpButton, NSWindow, NSView) {
        let (window, content) = choiceWindow()
        let toolbox = ToolboxPopUpButton()
        toolbox.frame = NSRect(x: 20, y: 340, width: 60, height: 36)
        toolbox.setAccessibilityLabel("Toolbox")
        content.addSubview(toolbox)
        let menu = NSMenu(title: "Toolbox")
        menu.addItem(menuItem("Save to History", #selector(MenuTarget.save(_:)), key: "s", target: target))
        menu.addItem(menuItem("Export…", #selector(MenuTarget.export(_:)), key: "e", target: target))
        menu.addItem(.separator())
        menu.addItem(menuItem("Copy", #selector(MenuTarget.copyIt(_:)), key: "c", target: target))
        menu.addItem(menuItem("Paste", #selector(MenuTarget.paste(_:)), key: "v", target: target))
        menu.addItem(.separator())
        menu.addItem(menuItem("Filled Shapes", #selector(MenuTarget.fill(_:)), target: target))
        menu.addItem(menuItem("Shadow", #selector(MenuTarget.shadow(_:)), target: target))
        menu.addItem(menuItem("Text Style…", #selector(MenuTarget.font(_:)), key: "t", target: target))
        toolbox.install(menu, toggles: [#selector(MenuTarget.fill(_:)), #selector(MenuTarget.shadow(_:)), #selector(MenuTarget.font(_:))])
        return (toolbox, window, content)
    }

    private static func zoomFixture(_ target: MenuTarget) -> (ZoomPopUpButton, NSWindow, NSView) {
        let (window, content) = choiceWindow()
        let zoom = ZoomPopUpButton(frame: NSRect(x: 20, y: 20, width: 87, height: 36), pullsDown: false)
        zoom.addItems(withTitles: ["25%", "50%", "75%", "100%", "150%", "200%"])
        for (index, item) in zoom.itemArray.enumerated() { item.representedObject = [0.25, 0.5, 0.75, 1, 1.5, 2][index] }
        zoom.menu?.addItem(.separator())
        let actual = menuItem("Actual Size", #selector(MenuTarget.actualSize(_:)), key: "0", target: target)
        actual.tag = ZoomPopUpButton.actualSizeTag
        zoom.menu?.addItem(actual)
        let computed = NSMenuItem(title: "83%", action: nil, keyEquivalent: "")
        computed.tag = ZoomPopUpButton.computedZoomTag; computed.toolTip = "Fit, 83%"; computed.representedObject = 0.83
        zoom.menu?.insertItem(computed, at: 0)
        zoom.select(computed)
        zoom.target = target; zoom.action = #selector(MenuTarget.zoomChanged(_:))
        zoom.setAccessibilityLabel("Canvas zoom")
        content.addSubview(zoom)
        return (zoom, window, content)
    }

    private static func menuChoiceChecks() {
        // Toolbox: five-group shape in miniature (three plates), rows from the menu, validation, choosing, dismissal, focus.
        let target = MenuTarget(), probe = NativeMenuProbe()
        defer { probe.stop() }
        let (toolbox, window, _) = toolboxFixture(target)
        let panel = toolbox.choicePanel
        offScreen(panel)
        target.isOpen = { toolbox.isOpen }
        target.disabled = ["paste:"]
        toolbox.mouseDown(with: mouse(.leftMouseDown, on: toolbox))
        expect(toolbox.isOpen && panel.host.requestedKey, "toolbox: a click opens the glass panel and takes the keyboard")
        expect(panel.focusedRow == nil, "toolbox: a pointer open focuses no row")
        expect(panel.host.plates.count == 3 && panel.rows.count == 7, "toolbox: one plate per group of the menu (\(panel.host.plates.count)) and one row per item (\(panel.rows.count))")
        expect(panel.host.plates.map { $0.arrangedViews.count } == [2, 2, 3], "toolbox: the separators split the plates 2 / 2 / 3")
        expect(panel.rows.map(\.kind) == [.command, .command, .command, .command, .toggle, .toggle, .toggle], "toolbox: toggles are toggles, the rest commands (\(panel.rows.map(\.kind)))")
        expect(panel.rows[0].title == "Save to History" && panel.rows[0].shortcutText == "⌘S" && panel.rows[0].leadingImage === toolbox.menu?.items[0].image, "toolbox: a row shows the item's title, shortcut and own icon")
        expect(panel.rows[4].isChosen && !panel.rows[5].isChosen, "toolbox: a toggle row shows the item's state (\(panel.rows.map(\.isChosen)), item states \(toolbox.menu?.items.map(\.state.rawValue) ?? []))")
        target.fillOn = false
        toolbox.performClick(nil); toolbox.performClick(nil)
        expect(!panel.rows[4].isChosen, "toolbox: the state is read again on every open (Filled Shapes off)")
        target.fillOn = true
        toolbox.performClick(nil); toolbox.performClick(nil)
        expect(panel.rows[4].accessibilityRole() == .checkBox && (panel.rows[4].accessibilityValue() as? NSNumber) == 1, "toolbox: a toggle row speaks as a checkbox with value 1")
        expect(!panel.rows[3].isEnabled && panel.rows[2].isEnabled && !panel.rows[3].acceptsFirstResponder, "toolbox: the row validation disables (Paste) is dimmed and never takes focus")
        let anchor = anchorOnScreen(toolbox)
        expect(panel.host.placement.map { $0.edge == .minY && $0.frame.maxY <= anchor.minY } == true, "toolbox: the panel opens below the button, not over it")
        expect(toolbox.accessibilityRole() == .menuButton && toolbox.accessibilityLabel() == "Toolbox" && toolbox.accessibilityValue() == nil, "toolbox: still a menu button named Toolbox with no value")
        // A second request closes; the click on the anchor the host consumes cannot reopen it.
        toolbox.performClick(nil)
        expect(!toolbox.isOpen, "toolbox: a second press closes the panel")
        toolbox.performClick(nil)
        expect(panel.host.handleMouseDown(in: window, at: window.convertPoint(fromScreen: NSPoint(x: anchor.midX, y: anchor.midY))) && !toolbox.isOpen,
               "toolbox: a click on the anchor while open only closes it and is consumed")
        toolbox.performClick(nil)
        expect(!panel.host.handleMouseDown(in: window, at: NSPoint(x: 400, y: 100)) && !toolbox.isOpen, "toolbox: a click elsewhere closes it and passes through")
        // Choosing a row closes first, then performs the item's own command.
        toolbox.performClick(nil)
        panel.rows[1].performClick(nil)
        expect(target.hits == ["export"] && target.openWhenPerformed == [false] && !toolbox.isOpen, "toolbox: choosing a row closes the panel, then runs the command (\(target.hits))")
        toolbox.performClick(nil)
        panel.rows[3].performClick(nil)
        expect(target.hits == ["export"] && toolbox.isOpen, "toolbox: a disabled row does nothing and the panel stays open")
        toolbox.performClick(nil)
        // Keyboard: opens on Return, Space, Down, Up and the accessibility press with the first row focused; arrows move; Return chooses.
        // (Nothing is switched on here, so there is no chosen row to land on.)
        target.fillOn = false
        for code: UInt16 in [36, 49, 76, 125, 126] {
            toolbox.keyDown(with: keyEvent(code, in: window))
            expect(toolbox.isOpen && panel.focusedRow === panel.rows[0], "toolbox: key \(code) opens the panel on the first enabled row")
            toolbox.performClick(nil)
        }
        expect(toolbox.accessibilityPerformPress() && toolbox.isOpen && panel.focusedRow === panel.rows[0], "toolbox: the accessibility press opens it on the first row")
        let panelWindow = panel.host.window
        panelWindow.sendEvent(keyEvent(125, in: panelWindow))
        expect(panel.focusedRow === panel.rows[1], "toolbox: Down moves to the next row")
        panelWindow.sendEvent(keyEvent(125, in: panelWindow))
        panelWindow.sendEvent(keyEvent(125, in: panelWindow))
        expect(panel.focusedRow === panel.rows[4], "toolbox: Down skips the disabled row")
        panelWindow.sendEvent(keyEvent(36, in: panelWindow))
        expect(target.hits == ["export", "fill"] && !toolbox.isOpen, "toolbox: Return on the focused row runs it and closes (\(target.hits))")
        // Escape closes and the opener has the keyboard again.
        window.makeFirstResponder(toolbox)
        toolbox.keyDown(with: keyEvent(49, in: window))
        panelWindow.sendEvent(keyEvent(53, in: panelWindow))
        expect(!toolbox.isOpen && window.firstResponder === toolbox, "toolbox: Escape closes the panel and the Toolbox has the focus again")
        // The test seam still replaces the panel.
        var requested = 0
        toolbox.popUpHandler = { _, _ in requested += 1 }
        toolbox.performClick(nil)
        expect(requested == 1 && !toolbox.isOpen, "toolbox: popUpHandler replaces showing the panel")
        toolbox.popUpHandler = nil
        // A disabled button opens nothing.
        toolbox.isEnabled = false
        toolbox.performClick(nil)
        expect(!toolbox.isOpen && toolbox.accessibilityPerformPress() == false, "toolbox: a disabled Toolbox does not open")
        toolbox.isEnabled = true
        expect(probe.began == 0, "toolbox: nothing above tracked a native menu")

        // A long list scrolls and a small screen caps the height.
        let (longWindow, longContent) = choiceWindow()
        let long = ToolboxPopUpButton()
        long.frame = NSRect(x: 20, y: 340, width: 60, height: 36)
        longContent.addSubview(long)
        let longMenu = NSMenu(title: "Long")
        for index in 0..<40 { longMenu.addItem(menuItem("Command \(index)", #selector(MenuTarget.save(_:)), target: target)) }
        long.install(longMenu)
        long.choicePanel.host.presenter = { _, _ in }
        long.choicePanel.host.visibleFrameOverride = NSRect(x: 0, y: 0, width: 1800, height: 500)
        long.performClick(nil)
        let longHost = long.choicePanel.host
        expect(longHost.placement.map { $0.scrolls && $0.frame.height <= 500 - 2 * GlassPanelHost.screenMargin } == true && longHost.scrolls == true,
               "toolbox: forty rows on a 500 pt screen scroll inside a capped panel (\(String(describing: longHost.placement?.frame)))")
        longHost.close()
        _ = longWindow

        zoomChoiceChecks()
        choiceRouteChecks()
    }

    private static func zoomChoiceChecks() {
        let target = MenuTarget(), probe = NativeMenuProbe()
        defer { probe.stop() }
        let (zoom, window, _) = zoomFixture(target)
        let panel = zoom.choicePanel
        offScreen(panel)
        target.isOpen = { zoom.isOpen }
        target.actualSizeOn = false
        zoom.performClick(nil)
        expect(zoom.isOpen && panel.host.plates.count == 2 && panel.rows.count == 8, "zoom: percentages and the computed row on one plate, Actual Size on the next (\(panel.host.plates.count) plates, \(panel.rows.count) rows)")
        expect(panel.rows.dropLast().allSatisfy { $0.kind == .option } && panel.rows.last?.kind == .toggle, "zoom: the percentages are options and Actual Size is a toggle")
        expect(panel.rows[0].title == "Fit, 83%" && panel.rows[0].accessibilityLabel() == "Fit, 83%" && panel.rows[0].isChosen && panel.rows.dropFirst().dropLast().allSatisfy { !$0.isChosen },
               "zoom: the computed row says its mode in the panel (visible and spoken) and is the chosen one (\(panel.rows[0].title))")
        expect(panel.rows.dropFirst().dropLast().map(\.title) == ["25%", "50%", "75%", "100%", "150%", "200%"] && zoom.titleOfSelectedItem == "83%" && zoom.menu?.items[0].title == "83%",
               "zoom: the fixed rows read as before and the face and the menu's own title stay the percentage alone")
        expect(panel.rows.allSatisfy { $0.titleLabel.frame.width >= $0.titleLabel.intrinsicContentSize.width - 0.5 && $0.frame.width >= $0.intrinsicContentSize.width - 0.5 },
               "zoom: the panel is wide enough for every row, the longer computed one included")
        expect(panel.rows.last?.title == "Actual Size" && panel.rows.last?.shortcutText == "⌘0" && panel.rows.last?.isChosen == false, "zoom: Actual Size shows its own shortcut and, when off, no check")
        let anchor = anchorOnScreen(zoom)
        expect(panel.host.placement.map { $0.edge == .maxY && $0.frame.minY >= anchor.maxY } == true, "zoom: the panel opens above the footer button")
        // A percentage: selects it in the pop-up and sends the pop-up's action; the face is that percentage.
        panel.rows.first { $0.title == "50%" }?.performClick(nil)
        expect(zoom.titleOfSelectedItem == "50%" && target.hits == ["zoom"] && target.openWhenPerformed == [false] && !zoom.isOpen, "zoom: choosing 50% selects it and sends the zoom action after closing (\(target.hits))")
        // Actual Size: performs its own command, leaves the selection and the percentage face alone.
        zoom.performClick(nil)
        expect(panel.rows.first { $0.title == "50%" }?.isChosen == true && panel.rows[0].isChosen == false, "zoom: reopened, the chosen row is the selected percentage")
        target.actualSizeOn = true
        reopen(zoom)
        expect(panel.rows.last?.isChosen == true, "zoom: Actual Size shows on while the command is on")
        panel.rows.last?.performClick(nil)
        expect(target.hits == ["zoom", "actualSize"] && zoom.titleOfSelectedItem == "50%" && zoom.selectedItem?.tag != ZoomPopUpButton.actualSizeTag && !zoom.isOpen,
               "zoom: Actual Size runs its own command and the face stays a percentage (\(zoom.titleOfSelectedItem ?? "nil"))")
        // Keyboard: the chosen row is focused on a keyboard open.
        window.makeFirstResponder(zoom)
        zoom.keyDown(with: keyEvent(125, in: window))
        expect(zoom.isOpen && panel.focusedRow?.title == "50%", "zoom: Down opens it on the chosen percentage")
        panel.host.window.sendEvent(keyEvent(53, in: panel.host.window))
        expect(!zoom.isOpen && window.firstResponder === zoom, "zoom: Escape closes it and the focus returns to the zoom")
        // Disabled (Actual Size is up): nothing opens.
        zoom.isEnabled = false
        zoom.performClick(nil)
        expect(!zoom.isOpen && !zoom.accessibilityPerformPress(), "zoom: a disabled zoom does not open")
        zoom.isEnabled = true
        expect(zoom.accessibilityValue() as? String == "Fit, 83%" || zoom.accessibilityValue() as? String == "50%", "zoom: the spoken value is still the item's tooltip or title")
        expect(probe.began == 0, "zoom: nothing above tracked a native menu")
    }

    /// Every route that could show a pop-up's native dropdown opens the glass panel instead, and AppKit never starts menu tracking.
    private static func choiceRouteChecks() {
        let target = MenuTarget()
        let toolbox = toolboxFixture(target), zoom = zoomFixture(target)
        let buttons: [(String, any PanelOwner, NSWindow)] = [("Toolbox", toolbox.0, toolbox.1), ("Zoom", zoom.0, zoom.1)]
        let probe = NativeMenuProbe()
        defer { probe.stop() }
        for (name, button, window) in buttons {
            offScreen(button.choicePanel)
            probe.guardAgainstHang(button.menu)
            // AppKit asks the view for a contextual menu on a right-click and on a Control-click; with none to show it cannot present the rows.
            expect(button.menu(for: mouse(.rightMouseDown, on: button)) == nil && button.menu(for: mouse(.leftMouseDown, on: button, flags: .control)) == nil && button.menu != nil,
                   "\(name): a right-click or Control-click has no contextual menu to show (the menu itself stays as the panel's source)")
            // What the control exposes to assistive technology: the actions are enumerated, and each is routed to the panel.
            let actions = button.accessibilityActionNames()
            expect(actions.contains(.press) || actions.contains(.showMenu), "\(name): exposes a way to open it (\(actions.map(\.rawValue)))")
            if actions.contains(.press) { expect(button.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformPress)), "\(name): AXPress is allowed") }
            var routes: [(String, Bool, () -> Void)] = [
                ("performClick", true, { button.performClick(nil) }),
                ("middle click", false, { button.otherMouseDown(with: mouse(.otherMouseDown, on: button)) }),
                ("left click", false, { button.mouseDown(with: mouse(.leftMouseDown, on: button)) }),
                ("right click", false, { button.rightMouseDown(with: mouse(.rightMouseDown, on: button)) }),
                ("Control-click", false, { button.mouseDown(with: mouse(.leftMouseDown, on: button, flags: .control)) }),
                ("AXPress", true, { _ = button.accessibilityPerformPress() }),
                ("AXShowMenu", true, { _ = button.accessibilityPerformShowMenu() }),
                ("context-menu key", true, { button.showContextMenuForSelection(nil) }),
                ("Return", true, { button.keyDown(with: keyEvent(36, in: window)) }),
                ("Space", true, { button.keyDown(with: keyEvent(49, in: window)) }),
                ("Down", true, { button.keyDown(with: keyEvent(125, in: window)) }),
                ("Up", true, { button.keyDown(with: keyEvent(126, in: window)) }),
            ]
            // Whatever other actions the control lists must also end in the panel (or in nothing), never in a native menu.
            for action in actions where ![NSAccessibility.Action.press, .showMenu].contains(action) { routes.append(("action " + action.rawValue, true, { _ = button.accessibilityPerformAction(action) })) }
            if actions.contains(.showMenu) { expect(button.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformShowMenu)), "\(name): AXShowMenu is allowed") }
            for (route, keyboard, run) in routes {
                button.choicePanel.host.close()
                run()
                expect(button.isOpen, "\(name): \(route) presents the glass panel")
                expect(keyboard == (button.choicePanel.focusedRow != nil), "\(name): \(route) \(keyboard ? "focuses a row" : "leaves every row unfocused")")
                expect(probe.began == 0, "\(name): \(route) started no native menu tracking")
            }
            button.choicePanel.host.close()
            // Typing is not a route to a menu: AppKit's type-ahead would select a row without asking, so the key goes up the responder chain.
            button.keyDown(with: keyEvent(0, in: window))
            expect(!button.isOpen && probe.began == 0, "\(name): a letter key opens nothing")
        }
    }

    /// The Original size toggle in the real chrome: a checkbox-role glass toggle on the View plate that flips, acts, and gives its room back.
    private static func originalSizeChecks() {
        let rig = makeRig(NSSize(width: 1100, height: 700))
        let toggle = rig.controls.dragOriginalControl, chrome = rig.chrome
        guard let choice = toggle as? GlassChoiceButton else { expect(false, "the Original size control is a glass choice"); return }
        let target = MenuTarget()
        toggle.target = target; toggle.action = #selector(MenuTarget.originalChanged(_:))
        expect(choice.kind == .toggle && choice.indicator == .checkbox && choice.title == "Original size" && choice.accessibilityRole() == .checkBox, "original size: a checkbox-role toggle titled Original size")
        expect(choice.accessibilityLabel() == "Export at original size" && (choice.titleLabel.font?.pointSize ?? 0) >= 18, "original size: spoken as Export at original size and drawn at the readable size")
        expect(chrome.surface(for: toggle)?.identifier?.rawValue == "GlassViewGroup", "original size: it sits on the View plate")
        choice.state = .off
        expect(!choice.isChosen && (choice.accessibilityValue() as? NSNumber) == 0, "original size: off reads 0")
        _ = choice.sendAction(choice.action, to: choice.target)
        expect(choice.state == .on && choice.isChosen && (choice.accessibilityValue() as? NSNumber) == 1 && target.hits == ["original:1"], "original size: a click turns it on and the action sees state on (\(target.hits))")
        _ = choice.sendAction(choice.action, to: choice.target)
        expect(choice.state == .off && target.hits == ["original:1", "original:0"], "original size: a second click turns it off")
        // Space and the VoiceOver press reach the same code as a click: performClick and AXPress flip it and the action sees the new state.
        target.hits = []
        choice.performClick(nil)
        expect(choice.state == .on && target.hits == ["original:1"], "original size: performClick (Space) turns it on and the action sees state on (\(target.hits))")
        expect(choice.accessibilityPerformPress() && choice.state == .off && target.hits == ["original:1", "original:0"], "original size: the accessibility press flips it back (\(target.hits))")
        _ = choice.plate
        // Its room: hidden it leaves the View plate and the status slot grows by exactly that much; shown again it takes it back.
        rig.content.layoutSubtreeIfNeeded()
        let shownPlate = group(rig, "GlassViewGroup").frame.width, shownSlot = chrome.statusSlotWidth()
        toggle.isHidden = true
        rig.content.layoutSubtreeIfNeeded()
        let hiddenPlate = group(rig, "GlassViewGroup").frame.width, hiddenSlot = chrome.statusSlotWidth()
        expect(abs((shownPlate - hiddenPlate) - chrome.originalSizeWidth) < 0.5 && abs((hiddenSlot - shownSlot) - chrome.originalSizeWidth) < 0.5,
               "original size: hiding it shrinks the View plate and grows the status slot by its width (\(shownPlate - hiddenPlate), \(hiddenSlot - shownSlot) vs \(chrome.originalSizeWidth))")
        toggle.isHidden = false
        rig.content.layoutSubtreeIfNeeded()
        expect(abs(group(rig, "GlassViewGroup").frame.width - shownPlate) < 0.5, "original size: showing it again restores the plate")
    }

    private static func uploadVariantChecks() {
        let url = URL(string: "https://cdn.shoemoney.com/pics/Shot-20261010-153012.png")!
        let variants = UploadState.success(url: url, copied: true).statusVariants
        expect(variants.first == "Link copied · cdn.shoemoney.com/pics/Shot-20261010-153012.png", "The longest variant is Link copied · the address without its scheme (\(variants.first ?? ""))")
        expect(variants.count > 5 && variants.last == variants.first, "There are middle-cut steps, and the whole sentence comes last so the cell cuts it at its tail when nothing fits (\(variants.count))")
        expect(zip(variants.dropLast(), variants.dropLast().dropFirst()).allSatisfy { $0.count > $1.count }, "The steps only get shorter")
        let middle = Array(variants.dropFirst().dropLast())
        expect(middle.allSatisfy { ($0.hasPrefix("Link copied · ") || $0.hasPrefix("Copied · …")) && $0.contains("…") }, "Every step after the first keeps the lead and cuts the address (or, narrowest, shortens the lead and keeps the file name's end)")
        let longSteps = middle.filter { $0.hasPrefix("Link copied · ") }
        expect(longSteps.allSatisfy { ($0.hasPrefix("Link copied · cdn") || $0.hasPrefix("Link copied · Sh")) && $0.hasSuffix("png") }, "The host's start (or, narrower, the file name's start) and the file name's end survive the cuts (\(variants[3]))")
        let nameSteps = middle.filter { $0.hasPrefix("Link copied · Sh") }
        expect(nameSteps.count >= 3 && nameSteps.allSatisfy { !$0.contains("cdn") }, "At 980 the later steps keep the file name, middle-cut, rather than a host stump (\(nameSteps))")
        // R1-014: narrower still, "Copied · …" and the end of the file name, which is what tells one upload from the next.
        let tailSteps = middle.filter { $0.hasPrefix("Copied · …") }
        expect(tailSteps.count >= 2 && tailSteps.allSatisfy { $0.hasSuffix("12.png") } && variants.dropLast().last == tailSteps.last && tailSteps.last!.count <= "Copied · …".count + UploadState.minimumNameCharacters,
               "The last steps are Copied · …<end of the name>, down to \(UploadState.minimumNameCharacters) characters (\(tailSteps))")
        expect(UploadState.minimumNameCharacters == 6 && tailSteps.last == "Copied · …12.png", "the shortest step is 'Copied · …12.png' (\(tailSteps.last ?? "nil"))")
        expect(UploadState.success(url: url, copied: true).detailText == "Link copied: " + url.absoluteString, "The full URL stays in the tooltip and the VoiceOver help")
        expect(UploadState.success(url: url, copied: false).statusVariants == ["Published image"] && UploadState.idle.statusVariants.isEmpty, "An uncopied link and idle have no link text")
        expect(UploadState.uploading(name: "Shot").statusVariants == ["Uploading Shot…", "Uploading…"] && UploadState.failure(message: "No.\nMore").statusVariants == ["No."], "Uploading gives up the file name before the verb; an error is its first line")
        expect(UploadState.middleTruncated("abcdefghij", to: 6) == "ab…hij" && UploadState.middleTruncated("abc", to: 6) == "abc", "middleTruncated keeps the end a little longer than the start")
        let field = StatusTextField(labelWithString: "")
        field.font = DesignTokens.Typography.font(.body)
        field.lineBreakMode = .byTruncatingTail
        field.setVariants(variants)
        func shown(_ width: CGFloat) -> String { field.setFrameSize(NSSize(width: width, height: 24)); return field.stringValue }
        expect(shown(2000) == variants.first, "A wide slot shows the whole sentence")
        let mid = shown(340)
        expect(mid != variants.first && mid != "Link copied" && mid.hasPrefix("Link copied · ") && mid.contains("…"), "A narrower slot cuts the middle of the link (\(mid))")
        expect(shown(150) == variants.first && !shown(150).dropFirst(11).contains("……") && field.spokenValue == nil, "A slot too narrow for any step shows the whole sentence and lets the cell cut its tail, so Link copied leads and no second ellipsis appears")
        expect(field.cell?.cellSize.width ?? 0 > 150 && field.lineBreakMode == .byTruncatingTail, "...that cut is the status line's own tail truncation")
    }

    /// Audit batch 3b (F-J2-021, F-J2-022): a long error is the sentence whole, its code, or "Upload failed" and never a cut sentence, the Details text has no second "Error:", a retry is named, the success line
    /// lasts, and "Upload cancelled" is a notice that outlives the next status refresh.
    private static func uploadOutcomeChecks() {
        let long = "The publishing password could not be read from macOS Keychain (-25300).\nSecond line."
        let failure = UploadState.failure(message: long)
        let variants = failure.statusVariants
        expect(variants.first == "The publishing password could not be read from macOS Keychain (-25300).", "The longest variant is the whole first line (\(variants.first ?? ""))")
        expect(variants == [long.components(separatedBy: "\n")[0], "Upload failed · -25300", "Upload failed", "Failed"], "The sentence whole, then its code, then the plain fallback, then the bare word (\(variants))")
        expect(variants.allSatisfy { !$0.contains("…") && !$0.hasPrefix("Error: ") }, "No error variant is a cut sentence or spends twelve characters on an Error: lead (R2-014)")
        let samples: [(String, String?)] = [
            ("The server returned HTTP 403 for this request and refused it.", "HTTP 403"),
            ("Upload to the bucket failed: 403 Forbidden", "HTTP 403"),
            ("http/1.1 503 Service Unavailable while sending the file to the destination", "HTTP 503"),
            ("HTTP PUT returned status 403; a completed upload was not confirmed.", "HTTP 403"),
            ("S3 returned status 507; the upload was not confirmed.", "HTTP 507"),
            ("curl: (6) Could not resolve host: uploads.example.com and no fallback was set", "curl 6"),
            ("curl exited with status 28 after waiting for the destination to answer", "curl 28"),
            ("The publishing password could not be read from macOS Keychain (-25300).", "-25300"),
            ("Keychain returned OSStatus -34018 when reading the saved password", "-34018"),
            ("curl 7.88.1 is installed but the destination refused the connection", nil),
            ("The destination answered after 1403 milliseconds and then went away", nil),
            ("Connection reset by the destination before the whole picture was sent", nil),
        ]
        for (message, code) in samples {
            expect(UploadState.errorCode(in: message) == code, "\(code ?? "no code") is read from \"\(message)\" (got \(UploadState.errorCode(in: message) ?? "none"))")
            let steps = UploadState.failure(message: message).statusVariants
            expect(steps == [message] + (code.map { ["Upload failed · " + $0] } ?? []) + ["Upload failed", "Failed"] && steps.allSatisfy { !$0.contains("…") }, "\"\(message)\" has the sentence, its code if any, then Upload failed; never an ellipsis (\(steps))")
        }
        expect(UploadState.failure(message: "HTTP 403 Forbidden for the upload").statusVariants == ["HTTP 403 Forbidden for the upload", "Upload failed · HTTP 403", "Upload failed", "Failed"], "A code already in the sentence is still offered when the sentence no longer fits")
        expect(UploadState.failure(message: "Upload failed · HTTP 403\ncurl: (22) The requested URL returned error: 403").statusVariants == ["Upload failed · HTTP 403", "Upload failed", "Failed"], "A transfer refused with an HTTP status reads Upload failed · HTTP 403 in the footer (F-J7-002)")
        expect(UploadState.failure(message: "HTTP 403").statusVariants == ["HTTP 403", "Failed"] && UploadState.failure(message: "Upload failed").statusVariants == ["Upload failed", "Failed"], "A line no longer than its fallback offers only the bare word below it")
        expect(UploadState.failure(message: "No.").statusVariants == ["No."] && UploadState.failure(message: "Error: Prefixed.\nMore").statusVariants == ["Prefixed.", "Failed"], "A short error is one sentence, and a message that carries Error: loses it from the footer")
        let field = StatusTextField(labelWithString: "")
        field.font = DesignTokens.Typography.font(.body); field.lineBreakMode = .byTruncatingTail
        field.setVariants(variants)
        func shown(_ width: CGFloat) -> String { field.setFrameSize(NSSize(width: width, height: 24)); return field.stringValue }
        expect(shown(2000) == variants.first, "A wide slot shows the whole error")
        let narrow = shown(420)
        expect(narrow == "Upload failed · -25300" && !narrow.contains("…") && shown(150) == "Upload failed" && shown(70) == "Failed" && field.spokenValue == long.components(separatedBy: "\n")[0], "A narrower slot gives the code, then the plain fallback, then the bare word, and VoiceOver still gets the whole line (\(narrow))")
        // The Details sheet's text drops the prefix its title makes redundant; the tooltip and VoiceOver help keep it.
        expect(failure.failureBody == long && UploadState.failure(message: "Error: Twice.").failureBody == "Twice.", "The Details text has no leading Error:")
        expect(failure.failureDetail == "Error: " + long && UploadState.idle.failureBody == nil, "The tooltip text still leads with Error:")
        // A retry is named.
        UploadState.retryingName = nil
        expect(UploadState.uploading(name: "Shot").statusVariants == ["Uploading Shot…", "Uploading…"], "A first attempt says Uploading")
        UploadState.retryingName = "Shot"
        expect(UploadState.uploading(name: "Shot").statusVariants == ["Retrying Shot…", "Retrying…"] && UploadState.uploading(name: "Other").statusVariants == ["Uploading Other…", "Uploading…"], "A retry says Retrying, only for its own file")
        UploadState.retryingName = nil
        // The success line lasts long enough to read.
        expect(UploadState.successDuration >= 10, "Link copied stays at least ten seconds (\(UploadState.successDuration))")
        // The cancelled notice.
        var changes = 0
        UploadNotice.onChange = { changes += 1 }
        defer { UploadNotice.onChange = nil; UploadNotice.clear() }
        UploadNotice.post("Upload cancelled")
        expect(UploadNotice.text == "Upload cancelled" && changes == 1 && UploadNotice.duration >= 8, "Cancelling posts a notice that lasts (\(UploadNotice.duration) s)")
        UploadNotice.clear()
        expect(UploadNotice.text == nil && changes == 2, "A new upload clears it")
        UploadNotice.clear()
        expect(changes == 2, "Clearing nothing changes nothing")
        UploadNotice.post("Upload cancelled", duration: 0.05)
        let end = Date().addingTimeInterval(10)
        while UploadNotice.text != nil && Date() < end { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        expect(UploadNotice.text == nil, "The notice expires by itself")
    }

    // MARK: T15 regression tests (each fails if the rail, its blank column or an overflow comes back)

    private static func group(_ rig: Rig, _ id: String) -> GlassSurfaceView {
        guard let found = surfaces(rig).first(where: { $0.identifier?.rawValue == id }) else { preconditionFailure("No glass group " + id); }
        return found
    }

    /// No permanent right column: no rail view, no 64 pt strip against the trailing margin, and the canvas is tied to the chrome alone.
    private static func noRailChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        let names = Set(descendantsOf(chrome).compactMap { $0.identifier?.rawValue })
        expect(names.isDisjoint(with: ["GlassDrawingGroup", "GlassHistoryGroup", "GlassToolRail", "GlassHeaderTrailing"]), "\(label): no rail or vertical group exists (\(names.sorted()))")
        expect(chrome.subviews.count == 4, "\(label): the chrome holds the canvas, the two bars and the border only (\(chrome.subviews.count))")
        for view in chrome.subviews {
            let frame = view.frame
            expect(!(abs(frame.width - 64) < 0.5 && abs(frame.maxX - (chrome.bounds.width - 12)) < 0.5), "\(label): \(describe(view)) is not a 64 pt strip against the trailing margin")
        }
        let tie = chrome.constraints.filter { $0.firstItem === chrome.scrollView && $0.firstAttribute == .trailing }
        expect(tie.count == 1 && tie[0].secondItem === chrome && tie[0].constant == -12 && tie[0].relation == .equal, "\(label): the canvas trailing edge is tied to the chrome's margin alone")
    }

    /// At each width the canvas viewport runs to the 12 pt margin and sits between the two bars.
    private static func canvasReachesMarginChecks(_ tag: String, minimum: NSSize) {
        for width in [980, 1024, 1280, 1440] as [CGFloat] {
            let rig = makeRig(NSSize(width: width, height: width == 980 ? minimum.height : 740))
            let scroll = rect(rig.chrome.scrollView, in: rig)
            let label = "\(tag) \(Int(width)) wide"
            expect(abs(scroll.maxX - (width - 12)) < 0.5 && abs(scroll.minX - 12) < 0.5, "\(label): the viewport spans margin to margin (\(scroll.minX) to \(scroll.maxX))")
            let header = rect(rig.chrome.header, in: rig), footer = rect(descendantsOf(rig.chrome).first { $0.identifier?.rawValue == "OpenSnapFooter" }!, in: rig)
            expect(abs(scroll.width - (width - 24)) < 0.5, "\(label): the viewport is \(width - 24) pt wide, nothing reserved at the side (\(scroll.width))")
            expect(abs((header.minY - scroll.maxY) - 8) < 0.5 && abs((scroll.minY - footer.maxY) - 8) < 0.5, "\(label): 8 pt between the viewport and each bar")
        }
    }

    /// Every relocated control is visible, fully inside its bar and clear of every other control, with the Original size checkbox shown.
    private static func relocatedControlChecks(_ rig: Rig, _ label: String, frame: Bool) {
        let chrome = rig.chrome, shared = rig.controls
        rig.content.layoutSubtreeIfNeeded()
        let top = rect(chrome.header, in: rig)
        let bottom = rect(descendantsOf(chrome).first { $0.identifier?.rawValue == "OpenSnapFooter" }!, in: rig)
        var topControls: [(String, NSView)] = [("Snap", chrome.snapButton), ("Color", shared.paletteButton), ("Size", shared.widthControl), ("Font", chrome.fontButton),
                                               ("Hide", chrome.hideButton), ("Toolbox", shared.toolbox), ("Photos", chrome.photosButton)] + chrome.toolButtons.map { ($0.key, $0.value) }
        if frame { topControls.append(("Cancel", chrome.cancelFrameButton)) }
        let bottomControls: [(String, NSView)] = [("Undo", chrome.undoButton), ("Wipe", chrome.wipeButton), ("Resize…", chrome.resizeButton), ("Save", chrome.saveButton),
                                                  ("History", chrome.historyButton), ("Zoom", shared.zoomControl), ("PNG | JPG", shared.dragFormatControl), ("Drag", shared.dragExportView),
                                                  ("Upload", chrome.shareButton), ("Original size", shared.dragOriginalControl), ("Status", shared.status)]
        for (name, view) in topControls {
            expect(!view.isHiddenOrHasHiddenAncestor, "\(label): \(name) is visible")
            expect(top.insetBy(dx: -0.5, dy: -0.5).contains(rect(view, in: rig)), "\(label): \(name) lies inside the top bar \(rect(view, in: rig)) vs \(top)")
        }
        for (name, view) in bottomControls {
            expect(!view.isHiddenOrHasHiddenAncestor, "\(label): \(name) is visible")
            expect(bottom.insetBy(dx: -0.5, dy: -0.5).contains(rect(view, in: rig)), "\(label): \(name) lies inside the bottom bar \(rect(view, in: rig)) vs \(bottom)")
        }
        expect(frame || chrome.cancelFrameButton.isHidden, "\(label): Cancel exists only in Frame mode")
        let everything = topControls + bottomControls
        for (index, a) in everything.enumerated() {
            for b in everything[(index + 1)...] {
                let overlap = rect(a.1, in: rig).intersection(rect(b.1, in: rig))
                expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): \(a.0) overlaps \(b.0) by \(overlap)")
            }
        }
        for (name, view) in everything where view !== shared.dragOriginalControl && view !== shared.status {
            // A popup sits centred in its cell and a segmented control is 36 pt itself; the cell is the 36 pt target.
            let target = rect((view.superview as? ChromeFillCell) ?? view, in: rig)
            expect(target.height >= 36, "\(label): \(name) has a hit target at least 36 pt tall (\(target.height))")
        }
        if rig.size.width <= ModernEditorChrome.minimumWindowWidth + 0.5 {
            expect(rect(shared.status, in: rig).width >= 120, "\(label): the status keeps 120 pt beside the Original size checkbox (\(rect(shared.status, in: rig).width))")
        }
    }

    /// FooterLayoutTests (OSN-054): an upload swaps what sits in the status slot and never widens the bar. In each state the commands that
    /// belong to it are icon buttons on one plate, inside the bar, whole and clear of every other control, the status gives way (truncating
    /// at its tail) before any control clips, the Original size checkbox is out of the way exactly where the slot cannot hold it (the
    /// measured rule, `slotHasRoomForCheckbox`), and the PNG | JPG toggle still exposes its two children.
    private static func footerUploadChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome, shared = rig.controls, upload = chrome.uploadControls
        let footer = rect(descendantsOf(chrome).first { $0.identifier?.rawValue == "OpenSnapFooter" }!, in: rig)
        let url = URL(string: "https://cdn.example.com/pics/x.png")!
        let longName = String(repeating: "A very long screenshot name ", count: 6)
        let fixed: [NSView] = [chrome.undoButton, chrome.wipeButton, shared.zoomControl, chrome.resizeButton, chrome.saveButton, chrome.historyButton,
                               shared.dragFormatControl, shared.dragExportView, chrome.shareButton]
        let widthBefore = chrome.measuredWindowWidth()
        let all: [(String, CommandButton)] = [("Cancel upload", upload.cancelButton), ("Open link", upload.openButton), ("Copy link", upload.copyButton), ("Retry", upload.retryButton), ("Details", upload.detailsButton)]
        let states: [(String, UploadState, [String])] = [
            ("uploading", .uploading(name: longName), ["Cancel upload"]),
            ("uploading a short name", .uploading(name: "Shot"), ["Cancel upload"]),
            ("success", .success(url: url, copied: true), ["Open link", "Copy link"]),
            ("failure", .failure(message: "The file uploaded, but public URL verification failed or timed out. No link was copied."), ["Retry", "Details"])
        ]
        for (name, state, commands) in states {
            let tag = "\(label) \(name)"
            upload.apply(state)
            // The app keeps the checkbox only where the measured slot holds it beside the message and the commands.
            let checkboxFits = chrome.slotHasRoomForCheckbox(during: state)
            shared.dragOriginalControl.isHidden = state.occupiesStatusSlot && !checkboxFits
            shared.status.stringValue = state.statusText ?? ""
            shared.status.invalidateIntrinsicContentSize()
            rig.content.layoutSubtreeIfNeeded()
            let spinnerShown = state.isUploading
            expect(upload.spinner.isHiddenOrHasHiddenAncestor == !spinnerShown, "\(tag): the spinner is shown only while uploading")
            if spinnerShown {
                let spinner = rect(upload.spinner, in: rig)
                expect(abs(spinner.width - 20) < 0.5 && abs(spinner.height - 20) < 0.5 && footer.insetBy(dx: -0.5, dy: -0.5).contains(spinner), "\(tag): the spinner is 20 pt and inside the bar (\(spinner))")
            }
            var occupied: [(String, NSRect)] = fixed.map { ("control", rect($0, in: rig)) }
            if spinnerShown { occupied.append(("spinner", rect(upload.spinner, in: rig))) }
            for (title, button) in all {
                let shown = commands.contains(title)
                expect(button.isHiddenOrHasHiddenAncestor == !shown, "\(tag): \(title) is \(shown ? "shown" : "hidden")")
                guard shown else { continue }
                let frame = rect(button, in: rig)
                expect(footer.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(tag): \(title) lies inside the bottom bar (\(frame) vs \(footer))")
                expect(abs(frame.width - GlassChrome.Metrics.iconButton.width) < 0.5, "\(tag): \(title) is not squeezed (\(frame.width) of \(GlassChrome.Metrics.iconButton.width))")
                expect(frame.height >= 36 && button.visibleTitle.isEmpty && button.icon != nil, "\(tag): \(title) is a 36 pt icon button")
                expect(button.showsRestPlate && button.plate.style.fill != nil, "\(tag): \(title) carries a rest plate, so it reads as a button before the pointer arrives")
                occupied.append((title, frame))
            }
            expect(surfaces(rig).count == 8 && surfaces(rig).allSatisfy { $0.identifier?.rawValue != "GlassUploadCommands" }, "\(tag): the upload adds no glass plate; the bars still hold eight")
            let spinnerPart: CGFloat = state.isUploading ? UploadStatusControls.spinnerSide + ModernEditorChrome.statusRowSpacing : 0
            expect(abs(chrome.slotNeed(for: state) - (chrome.minimumMessageWidth(for: state) + spinnerPart + CGFloat(commands.count) * (GlassChrome.Metrics.iconButton.width + ModernEditorChrome.statusRowSpacing))) < 0.5,
                   "\(tag): slotNeed counts the message minimum (an error counts its narrowest form), the spinner and each command with its gap")
            let status = rect(shared.status, in: rig)
            occupied.append(("status", status))
            for (index, a) in occupied.enumerated() {
                for b in occupied[(index + 1)...] {
                    let overlap = a.1.intersection(b.1)
                    expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(tag): \(a.0) overlaps \(b.0) by \(overlap)")
                }
            }
            let slot = rect(descendantsOf(chrome).first { $0.identifier?.rawValue == "OpenSnapStatusRow" }!, in: rig)
            expect(status.width >= 60 && footer.insetBy(dx: -0.5, dy: -0.5).contains(status), "\(tag): the status keeps at least 60 pt (\(status.width); the slot is \(slot.width) pt wide, the checkbox \(shared.dragOriginalControl.isHidden ? "hidden" : "shown"))")
            if name == "uploading" || name == "failure" {
                let needed = shared.status.cell?.cellSize.width ?? 0
                expect(needed > status.width + 0.5 && shared.status.lineBreakMode == .byTruncatingTail, "\(tag): the status truncates at its tail (\(needed) wanted, \(status.width) given) before any command clips")
            }
            if let first = all.first(where: { commands.contains($0.0) }) {
                expect(status.maxX <= rect(first.1, in: rig).minX + 0.5, "\(tag): the status ends before the first command (\(status.maxX) vs \(rect(first.1, in: rig).minX))")
            }
            expect(shared.dragOriginalControl.isHidden == !checkboxFits, "\(tag): the Original size checkbox is \(checkboxFits ? "kept" : "out of the way") where the slot \(checkboxFits ? "holds" : "cannot hold") it (slot \(Int(chrome.statusSlotWidth())) pt, needs \(Int(chrome.slotNeed(for: state) + 12 + shared.dragOriginalControl.fittingSize.width)))")
            if name != "uploading a short name" { print("  footer @\(Int(rig.size.width)) \(name): the status gets \(Int(status.width)) of the \(Int(slot.width)) pt slot") }
            expect(abs(chrome.measuredWindowWidth() - widthBefore) < 0.5, "\(tag): the bar does not widen (\(chrome.measuredWindowWidth()) vs \(widthBefore))")
            let children = shared.dragFormatControl.accessibilityChildren() ?? []
            expect(children.count == 2 && (children as? [NSAccessibilityElement])?.compactMap { $0.accessibilityLabel() } == ["PNG", "JPG"], "\(tag): the toggle still exposes two children, PNG and JPG")
        }
        upload.apply(.idle)
        shared.dragOriginalControl.isHidden = false
        shared.status.stringValue = longStatus
        rig.content.layoutSubtreeIfNeeded()
        expect(upload.commandButtons.allSatisfy { $0.isHiddenOrHasHiddenAncestor } && upload.spinner.isHiddenOrHasHiddenAncestor, "\(label): idle shows none of the upload controls")
    }

    /// The sums of the width budget, from live Metrics and from the real laid-out plates; the minimum window width must cover the worst case.
    private static func widthBudgetChecks(_ rig: Rig, _ label: String) {
        typealias M = GlassChrome.Metrics
        let chrome = rig.chrome, shared = rig.controls
        let tools = CGFloat(toolOrder.count)
        let pad = 2 * M.groupInset, spacing = M.groupSpacing
        let leading = pad + 2 * M.iconButton.width + M.toolboxButton.width + 2 * spacing
        let capture = pad + M.primaryButton.width, captureFrame = capture + spacing + M.iconButton.width
        let toolRow = pad + tools * M.toolButton.width + (tools - 1) * spacing
        let annotation = pad + 3 * M.iconButton.width + 2 * spacing
        let usable = ModernEditorChrome.minimumWindowWidth - 24
        let normal = leading + capture + toolRow + annotation + 3 * M.groupGap, frame = leading + captureFrame + toolRow + annotation + 3 * M.groupGap
        expect(normal <= usable && frame <= usable, "\(label): the top bar needs \(normal) (Frame \(frame)) of \(usable) usable points")
        // The real plates match the arithmetic, so a metric changed without the oracle cannot slip through.
        let measured = ["GlassHeaderLeading": leading, "GlassCaptureGroup": capture, "GlassToolBar": toolRow, "GlassAnnotationGroup": annotation]
        for (id, expected) in measured {
            expect(abs(rect(group(rig, id), in: rig).width - expected) < 0.5, "\(label): \(id) is \(expected) pt wide (is \(rect(group(rig, id), in: rig).width))")
        }
        chrome.frameMode = true
        rig.content.layoutSubtreeIfNeeded()
        expect(abs(rect(group(rig, "GlassCaptureGroup"), in: rig).width - captureFrame) < 0.5, "\(label): Snap and Cancel are \(captureFrame) pt wide")
        let topFrameSlack = rect(chrome.header, in: rig).width - frame
        chrome.frameMode = false
        rig.content.layoutSubtreeIfNeeded()
        expect(topFrameSlack >= -0.5, "\(label): the Frame-mode top bar fits at the minimum with \(topFrameSlack) pt to spare")
        // Bottom bar, measured: the Original size toggle (on the View plate) and a 120 pt status are the worst case.
        let zoomWidth = rect(shared.zoomControl.superview!, in: rig).width
        let formatWidth = rect(shared.dragFormatControl, in: rig).width
        let checkbox = shared.dragOriginalControl.fittingSize.width
        let icons = pad + 2 * M.iconButton.width + spacing
        let resizeWidth = rect(chrome.resizeButton, in: rig).width
        let bottom = icons + (pad + zoomWidth + spacing + resizeWidth + spacing + checkbox) + icons + (pad + formatWidth + 2 * spacing + 2 * M.iconButton.width)
            + 4 * M.groupGap + 120
        expect(bottom <= usable, "\(label): the bottom bar with the checkbox and a 120 pt status needs \(bottom) of \(usable) (zoom \(zoomWidth), format \(formatWidth), checkbox \(checkbox))")
        expect(ModernEditorChrome.minimumWindowWidth >= max(frame, bottom) + 24, "\(label): the minimum window width \(ModernEditorChrome.minimumWindowWidth) covers the worst case \(max(frame, bottom) + 24)")
        // The window's minimum is measured from the live plates and agrees with this arithmetic.
        expect(abs(chrome.measuredWindowWidth() - (ceil(max(frame, bottom)) + 24)) < 1 && chrome.requiredWindowWidth() == max(ModernEditorChrome.minimumWindowWidth, chrome.measuredWindowWidth()), "\(label): the measured minimum window width \(chrome.requiredWindowWidth()) is the worst case plus both margins (\(max(frame, bottom) + 24))")
        print("  width budget @980: top \(normal)/\(frame) Frame of \(usable) (slack \(usable - normal)/\(usable - frame)); bottom \(bottom) of \(usable) (slack \(usable - bottom)); zoom \(zoomWidth), format \(formatWidth), checkbox \(checkbox), status \(rect(shared.status, in: rig).width)")
    }

    /// The tool row is centred between the capture and annotation groups, and Snap does not move when Cancel appears.
    private static func toolGroupBalanceChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        func gaps() -> (before: CGFloat, after: CGFloat) {
            let capture = rect(group(rig, "GlassCaptureGroup"), in: rig), tools = rect(group(rig, "GlassToolBar"), in: rig), annotation = rect(group(rig, "GlassAnnotationGroup"), in: rig)
            return (tools.minX - capture.maxX, annotation.minX - tools.maxX)
        }
        rig.content.layoutSubtreeIfNeeded()
        let normal = gaps(), snapBefore = rect(chrome.snapButton, in: rig).minX, toolsBefore = rect(group(rig, "GlassToolBar"), in: rig).minX
        expect(abs(normal.before - normal.after) <= 0.5 && normal.before >= GlassChrome.Metrics.groupGap, "\(label): the tool row is balanced between its neighbours (\(normal))")
        chrome.frameMode = true
        rig.content.layoutSubtreeIfNeeded()
        let frame = gaps(), shift = rect(group(rig, "GlassToolBar"), in: rig).minX - toolsBefore
        expect(abs(rect(chrome.snapButton, in: rig).minX - snapBefore) < 0.5, "\(label): Snap does not move when Cancel appears")
        expect(abs(frame.before - frame.after) <= 0.5 && frame.before >= GlassChrome.Metrics.groupGap, "\(label): still balanced in Frame mode (\(frame))")
        let half = (GlassChrome.Metrics.iconButton.width + GlassChrome.Metrics.groupSpacing) / 2
        expect(abs(shift - half) < 0.5, "\(label): the tool row shifts by half of Cancel's slot (\(shift) vs \(half))")
        chrome.frameMode = false
        rig.content.layoutSubtreeIfNeeded()
    }

    /// A canvas smaller than the viewport sits in the middle of it, and a click at the centre of the viewport lands on it.
    private static func canvasCentreChecks(_ rig: Rig, _ label: String) {
        let canvas = rig.controls.canvas, scroll = rig.chrome.scrollView
        let original = canvas.frame
        defer { canvas.frame = original; rig.content.layoutSubtreeIfNeeded() }
        canvas.setFrameSize(NSSize(width: 200, height: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        rig.content.layoutSubtreeIfNeeded()
        scroll.contentView.layoutSubtreeIfNeeded()
        let area = scroll.contentView.frame, doc = scroll.convert(canvas.bounds, from: canvas)
        let margins = (left: doc.minX - area.minX, right: area.maxX - doc.maxX, top: doc.minY - area.minY, bottom: area.maxY - doc.maxY)
        expect(margins.left > 100 && abs(margins.left - margins.right) <= 1 && margins.top > 100 && abs(margins.top - margins.bottom) <= 1, "\(label): a small canvas has equal margins \(margins)")
        let centre = rig.content.convert(NSPoint(x: area.midX, y: area.midY), from: scroll)
        expect(rig.content.hitTest(centre) === canvas || (rig.content.hitTest(centre)?.isDescendant(of: canvas) ?? false), "\(label): the centre of the viewport hits the centred canvas")
    }

    /// The owner redesign: capture, tools and annotation in the top bar, document and output in the bottom bar, no rail, one footer row, no name field.
    private static func redesignChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        func ancestors(_ view: NSView) -> [NSView] { view.superview.map { [$0] + ancestors($0) } ?? [] }
        let descendants = descendantsOf
        for (id, button) in chrome.toolButtons {
            expect(ancestors(button).contains { $0 === chrome.header }, "\(label): tool \(id) lives in the top bar container")
        }
        for (name, view) in [("Snap", chrome.snapButton), ("Cancel", chrome.cancelFrameButton), ("Color", rig.controls.paletteButton), ("Size", rig.controls.widthControl), ("Font", chrome.fontButton)] as [(String, NSView)] {
            expect(ancestors(view).contains { $0 === chrome.header }, "\(label): \(name) lives in the top bar container")
        }
        expect(!descendants(chrome).contains { $0.identifier?.rawValue == "GlassToolRail" }, "\(label): there is no left tool rail")
        let scroll = rect(chrome.scrollView, in: rig)
        expect(abs(scroll.minX - 12) < 0.5, "\(label): the canvas viewport starts at the left margin (\(scroll.minX))")
        expect(abs(scroll.maxX - (rig.content.bounds.width - 12)) < 0.5, "\(label): the viewport ends at the right margin (\(scroll.maxX) vs \(rig.content.bounds.width - 12))")
        let footer = descendants(chrome).first { $0.identifier?.rawValue == "OpenSnapFooter" }
        expect(footer != nil, "\(label): the footer row exists")
        if let footer {
            let parts = [chrome.undoButton, chrome.wipeButton, rig.controls.zoomControl, chrome.resizeButton, rig.controls.status, chrome.saveButton, chrome.historyButton,
                         rig.controls.dragFormatControl, rig.controls.dragExportView, chrome.shareButton] as [NSView]
            for part in parts { expect(ancestors(part).contains { $0 === footer }, "\(label): \(describe(part)) is in the single footer row") }
            expect(footer.subviews.count == 5 && footer.frame.height <= 44.5, "\(label): the footer is one row of four glass plates and the status row (\(footer.frame.height) pt)")
            let known = Set(parts.map(ObjectIdentifier.init) + [ObjectIdentifier(rig.controls.dragOriginalControl), ObjectIdentifier(chrome.uploadControls.spinner)] + chrome.uploadControls.commandButtons.map(ObjectIdentifier.init))
            let leaves = descendants(footer).filter { ($0 is NSControl) && !($0 is NSStackView) && $0.window != nil && !$0.isHidden }
            let strays = leaves.filter { leaf in !known.contains(ObjectIdentifier(leaf)) && !ancestors(leaf).contains { known.contains(ObjectIdentifier($0)) } }
            expect(strays.isEmpty, "\(label): the footer holds only its own controls (strays: \(strays.map(describe)))")
        }
        expect(!descendants(chrome).contains { ($0 as? NSTextField)?.isEditable == true }, "\(label): Modern has no editable file-name field")
        expect(!allButtons(in: chrome).contains { $0.title.contains("Actual Size") || $0.title.contains("Normal View") }, "\(label): the Actual Size button is gone")
        let frames = rect(chrome.header, in: rig)
        let ids = ["GlassHeaderLeading", "GlassCaptureGroup", "GlassToolBar", "GlassAnnotationGroup"]
        let groups = surfaces(rig).filter { ids.contains($0.identifier?.rawValue ?? "") }
        expect(groups.count == 4 && groups.allSatisfy { frames.contains(rect($0, in: rig).insetBy(dx: 0.5, dy: 0.5)) }, "\(label): the four top bar plates fit inside the bar with no clipping")
        expect(chrome.header.subviews.count == 4, "\(label): the top bar holds exactly its four plates (\(chrome.header.subviews.count))")
        let bottomIds = ["GlassUndoWipeGroup", "GlassViewGroup", "GlassSaveGroup", "GlassFooterRow"]
        expect(surfaces(rig).filter { bottomIds.contains($0.identifier?.rawValue ?? "") }.count == 4, "\(label): the four bottom bar plates exist")
    }

    /// Glass shapes fuse into a "neck" when their container's spacing reaches the gap between them.
    private static func glassNeckChecks(_ rig: Rig, _ label: String) {
        let found = containers(rig)
        expect(found.count == 2, "\(label): the chrome builds one glass container per bar (found \(found.count))")
        for container in found {
            let id = container.identifier?.rawValue ?? "?"
            guard let bar = container.contentView else { expect(false, "\(label): \(id) wraps its bar"); continue }
            let plates = bar.subviews.compactMap { $0 as? GlassSurfaceView }.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
            expect(plates.count == 4, "\(label): \(id) holds four plates")
            var smallest = CGFloat.greatestFiniteMagnitude
            for (index, plate) in plates.enumerated() where index < plates.count - 1 { smallest = min(smallest, plates[index + 1].frame.minX - plate.frame.maxX) }
            expect(container.spacing < smallest, "\(label): \(id) container spacing \(container.spacing) stays below its smallest plate gap \(smallest) so neighbours do not fuse")
        }
    }

    private static func semantics(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        expect(chrome.header.identifier?.rawValue == "OpenSnapHeader", "\(label): header identifier")
        expect(chrome.toolButtons.count == 10 && Set(chrome.toolButtons.keys) == Set(toolOrder), "\(label): ten tool buttons, crop included")
        for id in toolOrder {
            guard let button = chrome.toolButtons[id] else { continue }
            expect(button.identifier?.rawValue == id, "\(label): tool identifier \(id)")
            expect(button.accessibilityLabel() == id.capitalized + " tool", "\(label): tool AX label \(id)")
            expect(AppToolTip.text(for: button) == id.capitalized + " tool", "\(label): tool tooltip \(id)")
            expect(button.imagePosition == .imageOnly && button.image != nil, "\(label): tool \(id) is icon only")
            expect(button.action == #selector(ActionTarget.chooseTool(_:)) && button.target === rig.target, "\(label): tool \(id) sends chooseTool")
            expect(button.isEnabled && !button.isHidden, "\(label): tool \(id) is live")
            expect(chrome.surface(for: button)?.identifier?.rawValue == "GlassToolBar" && button.superview is NSStackView, "\(label): tool \(id) sits on the shared tool plate, not on glass of its own")
            expect(button.plate.style == .none || id == "arrow", "\(label): tool \(id) has no fill at rest")
            expect(button.layer?.cornerRadius == 12 && abs(rect(button, in: rig).width - 44) < 0.5 && abs(rect(button, in: rig).height - 36) < 0.5, "\(label): tool \(id) is 44x36 with a 12 pt fill")
            expect(rect(button, in: rig).height >= DesignTokens.Size.hitMin, "\(label): tool \(id) keeps a 36 pt hit height")
        }
        expect(Set(chrome.toolButtons.values.compactMap { chrome.surface(for: $0).map(ObjectIdentifier.init) }).count == 1, "\(label): the ten tools share one plate")
        for (button, title, hit) in [(chrome.hideButton, "Hide", "hide"), (chrome.photosButton, "Photos", "photos"), (chrome.saveButton, "Save", "saveHistory"),
                                     (chrome.historyButton, "History", "showHistory"), (chrome.snapButton, "Snap", "snap"),
                                     (chrome.cancelFrameButton, "Cancel", "cancelFrame"), (chrome.fontButton, "Font", "font"), (chrome.undoButton, "Undo", "undo"),
                                     (chrome.wipeButton, "Clear image", "wipe")] {
            expect(button.title == title, "\(label): \(title) keeps its name")
            expect(button.accessibilityLabel() == title, "\(label): \(title) is read by its title")
            expect(button.controlSize == .extraLarge, "\(label): \(title) uses Apple's Extra Large control size")
            expect(button.icon != nil && button.image != nil && button.imagePosition == .imageOnly && button.visibleTitle.isEmpty, "\(label): \(title) is icon-only")
            expect(button.identifier == nil, "\(label): \(title) has no identifier, as in classic")
            let size = button === chrome.snapButton ? GlassChrome.Metrics.primaryButton : GlassChrome.Metrics.iconButton
            expect(chrome.surface(for: button)?.cornerRadius == 16, "\(label): \(title) sits on a 16 pt group plate")
            expect(abs(rect(button, in: rig).height - size.height) < 0.5 && (button === chrome.cancelFrameButton && button.isHidden || abs(rect(button, in: rig).width - size.width) < 0.5), "\(label): \(title) is one consistent size \(size)")
            rig.target.hits.removeAll()
            button.performClick(nil)
            expect(rig.target.hits == [hit], "\(label): \(title) sends its action (\(rig.target.hits))")
            expect(!button.plate.isSelected, "\(label): clicking \(title) never leaves it selected")
        }
        // R1-006: Resize… is the one command that wears its name, because its glyph read as "expand" or "full screen".
        let resize = chrome.resizeButton
        expect(resize.visibleTitle == "Resize…" && resize.icon == nil && resize.imagePosition == .noImage && resize.accessibilityLabel() == "Resize…" && resize.controlSize == .extraLarge,
               "\(label): Resize… is a text button with no glyph")
        expect((resize.font?.pointSize ?? 0) >= 20 && abs(rect(resize, in: rig).height - GlassChrome.Metrics.iconButton.height) < 0.5 && chrome.surface(for: resize)?.cornerRadius == 16,
               "\(label): Resize… is 20 pt text on the group plate, as tall as its neighbours (\(rect(resize, in: rig).size))")
        let titleWidth = (resize.visibleTitle as NSString).size(withAttributes: [.font: resize.font as Any]).width
        expect(rect(resize, in: rig).width >= titleWidth + DesignTokens.Space.s3 && AppToolTip.text(for: resize) == "Resize or crop the picture", "\(label): Resize… fits its label with room (\(rect(resize, in: rig).width) pt for \(titleWidth)) and explains itself")
        rig.target.hits.removeAll(); resize.performClick(nil)
        expect(rig.target.hits == ["resize"] && !resize.plate.isSelected, "\(label): Resize… sends its action (\(rig.target.hits))")
        expect(chrome.shareButton.accessibilityLabel() == "Upload image" && chrome.shareButton.title.isEmpty && chrome.shareButton.imagePosition == .imageOnly,
               "\(label): the upload button is icon-only with an explicit label")
        rig.target.hits.removeAll(); chrome.shareButton.performClick(nil)
        expect(rig.target.hits == ["share"], "\(label): the upload button sends its action")
        expect(AppToolTip.text(for: chrome.snapButton) == snapToolTip, "\(label): Snap keeps its classic tooltip")
        expect(chrome.snapButton.isPrimary, "\(label): Snap is the primary command")
        let primaries = allButtons(in: chrome).compactMap { $0 as? CommandButton }.filter { $0.isPrimary }
        expect(primaries.count == 1 && primaries[0] === chrome.snapButton, "\(label): exactly one primary control")
        expect(chrome.cancelFrameButton.isHidden, "\(label): Cancel starts hidden")
        expect(!chrome.frameMode, "\(label): starts outside Frame mode")
        let controlTitles = allButtons(in: chrome).flatMap { [$0.title, $0.accessibilityLabel() ?? "", AppToolTip.text(for: $0) ?? ""] }
        expect(!controlTitles.contains { $0.lowercased().contains("cam") }, "\(label): no Cam/Camera button exists in the Modern rail (screen capture only)")
        expect(Mirror(reflecting: chrome).children.allSatisfy { $0.label?.lowercased().contains("camera") != true }, "\(label): the chrome owns no camera control")
        iconOnlyChecks(rig, label)

        // Shared controls: re-parented, floors applied, caller-owned strings untouched.
        let shared = rig.controls
        expect(shared.toolbox.accessibilityLabel() == "Toolbox" && shared.paletteButton.accessibilityLabel() == "Drawing colors" && shared.zoomControl.accessibilityLabel() == "Canvas zoom" && shared.dragFormatControl.accessibilityLabel() == "Image format", "\(label): caller labels are untouched")
        for control in [shared.toolbox, shared.dragFormatControl, shared.paletteButton] as [NSControl] {
            expect(control.controlSize == .extraLarge && (control.font?.pointSize ?? 0) >= 18, "\(label): \(describe(control)) is Extra Large and keeps its readable font")
        }
        expect(shared.toolbox.imagePosition == .imageOnly && shared.toolbox.itemArray.first?.image != nil, "\(label): Toolbox shows its icon")
        expect(shared.sizeLabel.superview == nil && chrome.surface(for: shared.widthControl)?.identifier?.rawValue == "GlassAnnotationGroup", "\(label): the Size pill sits on the annotation plate and the Size text is not shown")
        expect(abs(rect(shared.widthControl, in: rig).width - 48) < 0.5 && abs(rect(shared.widthControl, in: rig).height - 36) < 0.5, "\(label): the Size pill is 48 x 36, like the other icon pills")
        expect(chrome.surface(for: shared.dragExportView)?.identifier?.rawValue == "GlassFooterRow" && shared.dragExportView.superview is ChromeFillCell, "\(label): Drag Me is a compact cell on the footer plate")
        expect(chrome.surface(for: shared.dragFormatControl)?.identifier?.rawValue == "GlassFooterRow", "\(label): the format toggle sits on the footer plate")
        expect(chrome.surface(for: shared.paletteButton)?.identifier?.rawValue == "GlassAnnotationGroup" && chrome.surface(for: chrome.fontButton)?.identifier?.rawValue == "GlassAnnotationGroup", "\(label): Color and Font share the annotation plate")
        let originalSize = shared.dragOriginalControl
        expect(chrome.surface(for: originalSize)?.identifier?.rawValue == "GlassViewGroup" && originalSize.superview is NSStackView && chrome.surface(for: originalSize)?.arrangedViews.contains(originalSize) == true,
               "\(label): the Original size toggle is a choice on the View plate, beside Zoom and Resize")
        expect(chrome.surface(for: shared.status) == nil && shared.status.superview is NSStackView && !(shared.status.superview?.superview is GlassSurfaceView),
               "\(label): the status stays plain, outside any glass, in the status row")
        expect(chrome.surface(for: shared.zoomControl)?.identifier?.rawValue == "GlassViewGroup" && (shared.zoomControl.superview as? ChromeFillCell)?.fixedSize.height == 36, "\(label): the zoom popup sits in a 36 pt cell on the view plate")
        if let zoom = shared.zoomControl as? ZoomPopUpButton {
            let item = NSMenuItem(title: "83%", action: nil, keyEquivalent: "")
            item.toolTip = "Fit, 83%"
            zoom.menu?.insertItem(item, at: 0); zoom.select(item)
            expect(zoom.titleOfSelectedItem == "83%" && (zoom.accessibilityValue() as? String) == "Fit, 83%", "\(label): the zoom face is the percentage; VoiceOver hears the mode too")
            zoom.selectItem(withTitle: "100%")
            expect((zoom.accessibilityValue() as? String) == "100%", "\(label): a plain zoom item is spoken as its title")
            zoom.menu?.removeItem(item)
            // The cell is what the face needs: every face the zoom can show is drawn whole in the real footer frame, at 20 pt, never truncated.
            let wide = NSMenuItem(title: "200%", action: nil, keyEquivalent: ""); wide.tag = ZoomPopUpButton.computedZoomTag
            zoom.menu?.insertItem(wide, at: 0)
            for face in zoom.itemArray where face.tag != ZoomPopUpButton.actualSizeTag && !face.isSeparatorItem {
                zoom.select(face)
                rig.content.layoutSubtreeIfNeeded()
                let metrics = zoom.faceTextMetrics
                expect(zoom.faceTextFits && metrics.font.pointSize == 20, "\(label): the zoom face \(face.title) is drawn whole at 20 pt: needs \(metrics.needed), has \(metrics.available) in a \(zoom.frame.size) face")
            }
            zoom.menu?.removeItem(wide)
            zoom.selectItem(withTitle: "100%")
        }
        expect(sameColor(shared.status.textColor, .labelColor), "\(label): status text uses the label color")
        expect(chrome.surface(for: shared.canvas) == nil, "\(label): the canvas never sits in glass")
        var ancestor: NSView? = shared.canvas
        var insideGlass = false
        while let view = ancestor { if view is NSGlassEffectView || view is NSGlassEffectContainerView { insideGlass = true }; ancestor = view.superview }
        expect(!insideGlass, "\(label): no glass above the canvas")
        let order = chrome.subviews
        func position(_ view: NSView?) -> Int { view.flatMap { order.firstIndex(of: $0) } ?? -1 }
        expect(!order.contains { $0 is NSVisualEffectView || $0 is NSBackgroundExtensionView }, "\(label): no material backdrop and no canvas bleed")
        expect(position(chrome.scrollView) == 0 && containers(rig).count == 2 && position(containers(rig)[0]) == 1, "\(label): canvas, then glass")
        expect(!surfaces(rig).contains { $0.contentView === rig.controls.canvas || $0.contentView === chrome.scrollView }, "\(label): glass never wraps the scroll view")
        expect(surfaces(rig).allSatisfy { $0.style == .regular }, "\(label): one glass variant")

        // Selecting a tool fills its button with accent at 0.20 plus a 1 pt accent border and flips its glyph; the others stay quiet.
        let brush = chrome.toolButtons["brush"]!
        brush.appearance = NSAppearance(named: .aqua)
        brush.state = .on
        expect(brush.plate.isSelected && abs((brush.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001 && brush.layer?.borderWidth == 1, "\(label): the selected tool has a 0.20 accent fill and a 1 pt border")
        expect(brush.activeFamily == .solid, "\(label): the selected tool uses the solid family (not colour alone)")
        let selectedBlend = DesignTokens.Palette.blend(accentAqua, alpha: 0.20, over: DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.window, arm: .aqua))
        expect(DesignTokens.Palette.contrastRatio(DesignTokens.Palette.resolve(brush.contentTintColor ?? .clear, for: brush.effectiveAppearance), selectedBlend) >= 4.5, "\(label): the selected glyph reads at 4.5:1 on its blended fill")
        expect(toolOrder.filter { $0 != "brush" }.allSatisfy { !(chrome.toolButtons[$0]!.plate.isSelected) }, "\(label): other tools stay unfilled")
        brush.state = .off
        expect(!brush.plate.isSelected && brush.plate.style == .none, "\(label): deselecting clears the fill")

        // Hiding Cancel leaves no slot: Snap's plate narrows and nothing glass is left behind in the capture group.
        chrome.cancelFrameButton.isHidden = false
        expect(!chrome.cancelFrameButton.isHidden, "\(label): a shown Cancel returns")
        chrome.cancelFrameButton.isHidden = true
        let captureGlass = descendantsOf(group(rig, "GlassCaptureGroup")).filter { $0 is NSGlassEffectView }
        expect(captureGlass.isEmpty, "\(label): the capture group holds no glass surface inside its plate, hidden or not (phantom capsule)")
        expect((shared.toolbox.superview as? ChromeFillCell)?.fixedSize == GlassChrome.Metrics.toolboxButton, "\(label): the Toolbox cell is wide enough for its glyph and chevron")
    }

    /// Every Modern command is icon-only, with a tooltip (name plus real shortcut) and the old title as its VoiceOver label.
    private static func iconOnlyChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        let expected: [(NSButton, String, String)] = [
            (chrome.hideButton, "Hide", "Hide (⌘M)"), (chrome.photosButton, "Photos", "Photos"), (chrome.saveButton, "Save", "Save to History"),
            (chrome.historyButton, "History", "History"), (chrome.snapButton, "Snap", snapToolTip), (chrome.cancelFrameButton, "Cancel", "Cancel"),
            (chrome.fontButton, "Font", "Font"), (chrome.undoButton, "Undo", "Undo (⌘Z)"), (chrome.wipeButton, "Clear image", "Clear image"),
            (chrome.shareButton, "Upload image", "Upload image")]
        for (button, name, tip) in expected {
            expect(button.imagePosition == .imageOnly, "\(label): \(name) draws only its icon")
            expect((button as? CommandButton).map { $0.visibleTitle.isEmpty } ?? button.title.isEmpty, "\(label): \(name) shows no title text")
            expect(AppToolTip.text(for: button) == tip, "\(label): \(name) tooltip is '\(tip)' (is '\(AppToolTip.text(for: button) ?? "nil")')")
            expect(button.accessibilityLabel() == name, "\(label): \(name) accessibility label (is '\(button.accessibilityLabel() ?? "nil")')")
        }
        let shared = rig.controls
        expect(shared.paletteButton.imagePosition == .imageOnly && shared.paletteButton.image != nil && shared.paletteButton.accessibilityLabel() == "Drawing colors"
               && AppToolTip.text(for: shared.paletteButton)?.hasPrefix("Color") == true, "\(label): Color shows only its swatch, with a tooltip and label")
        expect(shared.toolbox.imagePosition == .imageOnly && shared.toolbox.accessibilityLabel() == "Toolbox", "\(label): Toolbox is icon-only")
        expect(shared.sizeLabel.superview == nil && AppToolTip.text(for: shared.widthControl) == "Size", "\(label): the Size text is gone; the pill keeps a tooltip")
        // Retitles move the tooltip and label, not drawn text.
        chrome.wipeButton.title = "Remove annotations"
        expect(AppToolTip.text(for: chrome.wipeButton) == "Remove annotations" && chrome.wipeButton.accessibilityLabel() == "Remove annotations" && chrome.wipeButton.visibleTitle.isEmpty, "\(label): Wipe's staged name becomes its tooltip and label")
        chrome.wipeButton.title = "Clear image"
    }

    private static func frameModeChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        expect(chrome.snapButton.title == "Snap Frame" && chrome.snapButton.icon == .frameViewfinder, "\(label): Snap becomes Snap Frame with the viewfinder")
        expect(AppToolTip.text(for: chrome.snapButton) == snapFrameToolTip, "\(label): Snap Frame tooltip")
        expect(chrome.snapButton.isPrimary, "\(label): Snap Frame stays primary")
        expect(!chrome.cancelFrameButton.isHidden, "\(label): Cancel appears in Frame mode")
        expect(!chrome.wellIsSolid && !chrome.scrollView.drawsBackground && !chrome.scrollView.contentView.drawsBackground, "\(label): the solid well gives way to the Frame hole")
        let cancel = rect(chrome.cancelFrameButton, in: rig), snap = rect(chrome.snapButton, in: rig)
        expect(abs(cancel.width - 48) < 0.5 && abs(cancel.height - 36) < 0.5 && cancel.minX >= snap.maxX && abs(cancel.midY - snap.midY) < 0.5, "\(label): Cancel is an icon pill to the right of Snap Frame")
        expect(abs(snap.width - 56) < 0.5 && abs(snap.height - 36) < 0.5, "\(label): Snap Frame keeps the wider primary button")
        expect(chrome.snapButton.accessibilityLabel() == "Snap Frame" && chrome.snapButton.visibleTitle.isEmpty, "\(label): Snap Frame is read aloud, never drawn")
        expect(rig.controls.canvas.window === rig.window && chrome.scrollView.frame.size != .zero, "\(label): the canvas stays in place in Frame mode")
    }

    // MARK: G5 glass depth (OSN-042): one plate per group, no nested glass, a solid well, display-option fallbacks

    private static func allGlass(in view: NSView) -> [NSGlassEffectView] {
        ((view as? NSGlassEffectView).map { [$0] } ?? []) + view.subviews.flatMap { allGlass(in: $0) }
    }

    private static func fillOwners(in view: NSView) -> [NSView] {
        (view is CommandButton || view is ChromeFillCell ? [view] : []) + view.subviews.flatMap { fillOwners(in: $0) }
    }

    private static func plateOf(_ view: NSView) -> StatePlate? { (view as? CommandButton)?.plate ?? (view as? ChromeFillCell)?.plate }

    /// (1) depth, (2) budget, (3) no overlap with the canvas well. Run in every window state.
    private static func glassDepthChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        rig.content.layoutSubtreeIfNeeded()
        let glass = allGlass(in: chrome)
        expect(glass.count <= 8, "\(label): at most 8 glass surfaces in the window (\(glass.count))")
        expect(glass.count == 8 && glass.allSatisfy { $0 is GlassSurfaceView }, "\(label): they are exactly the eight group plates (\(glass.count))")
        for view in glass {
            var ancestor = view.superview
            while let current = ancestor {
                expect(!(current is NSGlassEffectView), "\(label): \(describe(view)) has a glass ancestor \(describe(current))")
                ancestor = current.superview
            }
            expect(allGlass(in: view.contentView ?? view).isEmpty, "\(label): \(describe(view)) has a glass descendant")
        }
        let containerCount = containers(rig).count
        expect(containerCount <= 2, "\(label): the plates live in at most the two bar containers (\(containerCount))")
        for view in glass {
            var inContainer = false
            var ancestor = view.superview
            while let current = ancestor { if current is NSGlassEffectContainerView { inContainer = true }; ancestor = current.superview }
            expect(inContainer, "\(label): plate \(describe(view)) sits inside a glass container")
        }
        let scroll = rect(chrome.scrollView, in: rig)
        for view in glass where !view.isHiddenOrHasHiddenAncestor {
            let overlap = rect(view, in: rig).intersection(scroll)
            expect(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5, "\(label): glass \(describe(view)) \(rect(view, in: rig)) never overlaps the canvas well \(scroll)")
        }
        expect(!descendantsOf(chrome).contains { $0 is NSVisualEffectView }, "\(label): no NSVisualEffectView anywhere in the chrome")
        expect(!chrome.subviews.contains { $0 is NSVisualEffectView }, "\(label): no NSVisualEffectView behind the canvas")
    }

    /// (6) exactly one saturated accent at rest (Snap), the selected tool at 0.20 with a border, hover and press never saturated.
    private static func tintChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        let owners = fillOwners(in: chrome)
        for view in owners { (view as? ChromeFillCell)?.setHovered(false); (view as? CommandButton)?.setHovered(false) }
        for button in chrome.toolButtons.values { button.state = .off }
        func saturated() -> [NSView] { owners.filter { ($0.isHiddenOrHasHiddenAncestor == false) && (plateOf($0)?.style.fill?.alphaComponent ?? 0) > 0.5 } }
        expect(saturated().count == 1 && saturated()[0] === chrome.snapButton, "\(label): at rest exactly one saturated accent exists: Snap (\(saturated().map(describe)))")
        expect(chrome.snapButton.plate.style.fill?.alphaComponent == 1, "\(label): Snap's fill is the accent at 1.0")
        for view in owners where view !== chrome.snapButton {
            if let restPlated = view as? CommandButton, restPlated.showsRestPlate {
                // The upload's commands sit on the bar and carry the faint rest plate on purpose (audit fix 1); it is never a saturated accent.
                expect(abs((restPlated.plate.style.fill?.alphaComponent ?? 0) - StateStyles.restPlateAlpha(highContrast: false)) < 0.001, "\(label): \(describe(view)) rests on the faint plate (0.06)")
            } else {
                expect(plateOf(view)?.style.fill == nil, "\(label): \(describe(view)) has no fill at rest")
            }
        }
        chrome.toolButtons["ellipse"]?.appearance = NSAppearance(named: .aqua)
        chrome.toolButtons["ellipse"]?.state = .on
        let tool = chrome.toolButtons["ellipse"]!
        expect(abs((tool.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001 && tool.layer?.borderWidth == 1 && sameColor(tool.plate.style.border, accentAqua), "\(label): the selected tool is accent 0.20 with a 1 pt accent border")
        expect(saturated().count == 1, "\(label): selecting a tool adds no second saturated element")
        for view in owners { (view as? CommandButton)?.setHovered(true); (view as? ChromeFillCell)?.setHovered(true) }
        expect(saturated().count == 1 && owners.filter { plateOf($0)?.style.fill != nil }.count == owners.count, "\(label): hovering everything fills everything faintly but adds no saturated accent")
        for view in owners { (view as? CommandButton)?.setHovered(false); (view as? ChromeFillCell)?.setHovered(false) }
        tool.state = .off
    }

    /// (4) Reduce Transparency and (5) Increase Contrast, by injection.
    private static func displayOptionChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        let plates = surfaces(rig)
        chrome.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: false, reduceMotion: false)
        for plate in plates {
            let solid = plate.transparencyPlate
            expect(plate.tintColor == nil, "\(label): Reduce Transparency: \(describe(plate)) has no tint")
            expect(solid != nil && !solid!.isHidden && solid!.layer?.backgroundColor?.alpha == 1 && solid!.layer?.borderWidth == 1, "\(label): Reduce Transparency: \(describe(plate)) has an opaque plate with a 1 pt border")
            expect(solid?.layer?.cornerRadius == plate.cornerRadius, "\(label): the plate matches \(describe(plate))'s radius")
        }
        chrome.accessibility = ChromeAccessibility(reduceTransparency: false, increaseContrast: true, reduceMotion: false)
        for plate in plates {
            expect(plate.layer?.borderWidth == 1 && abs(borderAlpha(plate.layer) - 0.6) < 0.01, "\(label): Increase Contrast: \(describe(plate)) has a 1 pt label-color border")
            expect(plate.transparencyPlate == nil, "\(label): Increase Contrast alone keeps the glass on \(describe(plate))")
        }
        let snapFill = chrome.snapButton.plate.style.fill
        expect(snapFill?.alphaComponent == 1, "\(label): Increase Contrast keeps Snap saturated")
        chrome.accessibility = .none
        expect(plates.allSatisfy { $0.transparencyPlate == nil && $0.layer?.borderWidth == 0 }, "\(label): clearing the options restores the glass")
    }

    /// (7) The well is solid: the scroll view and its clip view draw `surface.canvasWell`, opaque, scroller corner included.
    private static func wellChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        let scroll = chrome.scrollView
        expect(chrome.wellIsSolid && scroll.drawsBackground && scroll.contentView.drawsBackground, "\(label): the scroll view and its clip view both draw the well")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: name)!
            let well = DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.canvasWell, for: appearance)
            let used = DesignTokens.Palette.resolve(scroll.backgroundColor, for: appearance)
            let clip = DesignTokens.Palette.resolve(scroll.contentView.backgroundColor, for: appearance)
            expect(well.alphaComponent == 1 && sameColor(used, well, tolerance: 0.002) && sameColor(clip, well, tolerance: 0.002), "\(label): the well is the opaque canvasWell colour in \(name.rawValue)")
        }
        // The legacy scroller's corner box takes the well colour instead of white.
        rig.window.appearance = NSAppearance(named: .aqua)
        scroll.scrollerStyle = .legacy
        rig.content.layoutSubtreeIfNeeded()
        scroll.tile()
        guard let rep = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else { expect(false, "\(label): the well renders"); return }
        scroll.cacheDisplay(in: scroll.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / scroll.bounds.width
        func pixel(_ x: CGFloat, fromBottom y: CGFloat) -> NSColor? {
            rep.colorAt(x: Int(x * scale), y: rep.pixelsHigh - 1 - Int(y * scale))?.usingColorSpace(.sRGB)
        }
        let well = DesignTokens.Palette.resolve(DesignTokens.Palette.Surface.canvasWell, for: NSAppearance(named: .aqua)!)
        if scroll.verticalScroller?.isHidden == false && scroll.horizontalScroller?.isHidden == false, let vertical = scroll.verticalScroller, let horizontal = scroll.horizontalScroller {
            let corner = pixel(vertical.frame.midX, fromBottom: horizontal.frame.midY)
            expect(corner.map { sameColor($0, well, tolerance: 0.03) } == true, "\(label): the scroller corner is the well colour (\(String(describing: corner)) vs \(well))")
        } else {
            expect(false, "\(label): both legacy scrollers show in the rig, so the corner exists to test")
        }
        scroll.scrollerStyle = NSScroller.preferredScrollerStyle
        rig.window.appearance = nil
    }

    private static func accessibilityChecks(_ rig: Rig, _ label: String) {
        let chrome = rig.chrome
        let hovered = chrome.undoButton
        hovered.appearance = NSAppearance(named: .aqua)
        hovered.setHovered(true)
        expect(abs((hovered.plate.style.fill?.alphaComponent ?? 0) - 0.08) < 0.001, "\(label): hover fill before injection")
        chrome.toolButtons["line"]?.state = .on
        let selected = chrome.toolButtons["line"]!
        selected.appearance = NSAppearance(named: .aqua)
        expect(abs((selected.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001, "\(label): selected fill before Increase Contrast")

        chrome.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: true, reduceMotion: true)
        expect(abs((hovered.plate.style.fill?.alphaComponent ?? 0) - 0.16) < 0.001, "\(label): Increase Contrast strengthens the hover fill")
        expect(abs((selected.plate.style.fill?.alphaComponent ?? 0) - 0.32) < 0.001 && selected.layer?.borderWidth == 1, "\(label): Increase Contrast strengthens the selected fill (0.32) and keeps its border")
        expect(surfaces(rig).allSatisfy { $0.accessibility.increaseContrast && $0.accessibility.reduceMotion && $0.accessibility.reduceTransparency }, "\(label): every plate receives the injected options")
        expect(fillOwners(in: chrome).allSatisfy { plateOf($0)?.accessibility == chrome.accessibility }, "\(label): every button and cell receives them too")
        expect(hovered.plate.lastAnimationDuration == 0, "\(label): Reduce Motion reaches the fills")
        chrome.accessibility = .none
        expect(abs((hovered.plate.style.fill?.alphaComponent ?? 0) - 0.08) < 0.001 && abs((selected.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001, "\(label): clearing the options restores everything")
        hovered.setHovered(false)
        chrome.toolButtons["line"]?.state = .off

        // The live path: the provider is read again when the system posts a display-options change.
        rig.box.value = ChromeAccessibility(reduceTransparency: true, increaseContrast: false, reduceMotion: false)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        expect(chrome.accessibility.reduceTransparency && surfaces(rig).allSatisfy { $0.transparencyPlate != nil }, "\(label): the display-options notification re-reads the provider")
        rig.box.value = .none
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        expect(chrome.accessibility == .none && surfaces(rig).allSatisfy { $0.transparencyPlate == nil }, "\(label): and again when the options clear")
    }
}

#endif
