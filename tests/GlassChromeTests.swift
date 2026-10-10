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
}

/// A popover that never reaches the screen but still reports its edge, its anchor and its close notifications.
@MainActor
private final class TestPopover: NSPopover {
    var open = false
    private(set) var edge: NSRectEdge?
    private(set) weak var anchor: NSView?
    override var isShown: Bool { open }
    override func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        open = true; edge = preferredEdge; anchor = positioningView
    }
    override func performClose(_ sender: Any?) { close() }
    override func close() {
        guard open else { return }
        delegate?.popoverWillClose?(Notification(name: NSPopover.willCloseNotification, object: self))
        open = false
        delegate?.popoverDidClose?(Notification(name: NSPopover.didCloseNotification, object: self))
    }
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

    private static let toolOrder = ["select", "brush", "line", "ellipse", "rectangle", "fill", "eraser", "text", "arrow", "crop"]
    private static let snapToolTip = "Snap: drag an area or click a window; right-click or Control-click for Fullscreen"
    private static let snapFrameToolTip = "Snap Frame: capture the area inside the frame; hold Shift for a six-second timer"
    private static let plain = ChromeAccessibility.none
    private static let contrast = ChromeAccessibility(reduceTransparency: false, increaseContrast: true, reduceMotion: false)
    private static let calm = ChromeAccessibility(reduceTransparency: false, increaseContrast: false, reduceMotion: true)

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
        do {
            surfaceTests()
            let fonts = fontDirectory()
            chromeTests(glyphs: false)
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

    // MARK: GlassChromeButton (available on every supported macOS)

    private static func buttonTests() {
        // Font floor: the title initializer assigns a small system font after init(frame:).
        let titled = GlassChromeButton(title: "Wipe", target: nil, action: nil)
        expect((titled.font?.pointSize ?? 0) >= 18, "Title initializer never leaves a font under 18 pt")
        expect((GlassChromeButton(frame: .zero).font?.pointSize ?? 0) == 20, "Default label size is 20 pt")
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
        let tool = GlassChromeButton(title: "", target: nil, action: nil)
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

        let actual = GlassChromeButton(title: "Actual Size", target: nil, action: nil)
        actual.setButtonType(.toggle)
        actual.icon = .maximize
        actual.selectedIcon = .minimize
        expect(actual.imagePosition == .imageLeading, "Icon beside a label leads it")
        if case .sfSymbol(let name) = actual.iconSource { expect(name == FAIcon.maximize.sfSymbolFallback, "Off shows maximize") }
        actual.state = .on
        if case .sfSymbol(let name) = actual.iconSource { expect(name == FAIcon.minimize.sfSymbolFallback, "On shows minimize") }
        expect(actual.activeFamily == .solid, "Actual Size on is the solid family")
        let blank = GlassChromeButton(title: "Plain", target: nil, action: nil)
        expect(blank.iconSource == .none && blank.image == nil && blank.imagePosition == .noImage, "Without an icon the title stands alone")

        // contentTintColor per state: a selected button is only a 0.20 accent fill, so its glyph is the accent itself;
        // the one primary button sits on a saturated fill and contrasts with it.
        let accentContrast = GlassChromeButton.textColor(on: .controlAccentColor)
        let tinted = GlassChromeButton(title: "Snap", target: nil, action: nil)
        tinted.setButtonType(.toggle)
        tinted.icon = .crosshairs
        expect(sameColor(tinted.contentTintColor, .labelColor), "Normal content uses the label color")
        tinted.state = .on
        expect(sameColor(tinted.contentTintColor, .controlAccentColor), "A selected glyph is the accent")
        tinted.accessibility = contrast
        expect(sameColor(tinted.contentTintColor, .labelColor), "Increase Contrast keeps the selected glyph in the label color")
        tinted.accessibility = plain
        tinted.selectionTints = false
        expect(sameColor(tinted.contentTintColor, .labelColor) && tinted.plate.style == .none, "A glyph-only toggle keeps the label color and no fill when on")
        tinted.selectionTints = true
        tinted.state = .off
        tinted.isPrimary = true
        expect(sameColor(tinted.contentTintColor, accentContrast), "Primary content contrasts with the accent")
        tinted.isEnabled = false
        expect(sameColor(tinted.contentTintColor, .disabledControlTextColor), "Disabled content uses the disabled color")
        tinted.isEnabled = true
        tinted.isPrimary = false
        expect(sameColor(tinted.contentTintColor, .labelColor), "Re-enabling restores the label color")

        // The button draws its own state fill on a rounded layer; no surface is involved.
        let fill = GlassChromeButton(title: "", target: nil, action: nil)
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
        expect(fill.plate.style == .none && fill.alphaValue == 0.5, "Disabled ignores hover and press and dims through alpha")
        fill.highlight(false)
        fill.setHovered(false)
        fill.isEnabled = true
        expect(fill.alphaValue == 1, "Enabling restores alpha")
        let animated = GlassChromeButton(title: "", target: nil, action: nil)
        animated.setHovered(true)
        expect(animated.plate.lastAnimationDuration == 0.15, "State changes animate over 0.15 s")
        animated.accessibility = calm
        expect(animated.plate.lastAnimationDuration == 0, "Reduce Motion makes state changes instant")
        animated.accessibility = ChromeAccessibility(reduceTransparency: true, increaseContrast: false, reduceMotion: false)
        expect(animated.plate.lastAnimationDuration == 0.15, "Reduce Transparency alone keeps the animation")
        animated.setHovered(false)
        let hidden = GlassChromeButton(title: "", target: nil, action: nil)
        hidden.setHovered(true)
        hidden.isHidden = true
        expect(!hidden.isHovered, "Hiding a button clears hover")

        // Focus ring mask follows the host shape and vanishes while disabled.
        let ring = GlassChromeButton(title: "", target: nil, action: nil)
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
        let click = GlassChromeButton(title: "Snap", target: target, action: #selector(ActionTarget.snap(_:)))
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
        let secondary = GlassChromeButton(title: "Snap", target: target, action: #selector(ActionTarget.snap(_:)))
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
        let momentary = GlassChromeButton(title: "Undo", target: target, action: #selector(ActionTarget.undo(_:)))
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
        let toggled = GlassChromeButton(title: "", target: target, action: #selector(ActionTarget.chooseTool(_:)))
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
        let tool = GlassChromeButton(title: "", target: nil, action: nil)
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
        slider.popoverProvider = { TestPopover() }
        func groups() -> String { "begin \(begins) end \(ends)" }

        // Semantics: a real slider to assistive technology, with the five original steps.
        expect(OriginalDrawingControls.sizeSteps == [1.5, 4.125, 6.75, 9.375, 12], "There are five steps")
        expect(slider.accessibilityRole() == .slider && slider.accessibilityLabel() == "Drawing size" && slider.isAccessibilityElement(), "The pill is an accessible slider")
        expect((slider.accessibilityMinValue() as? NSNumber)?.doubleValue == 1.5 && (slider.accessibilityMaxValue() as? NSNumber)?.doubleValue == 12
               && (slider.accessibilityValue() as? NSNumber)?.doubleValue == 6.75, "Min, max and value are exposed")
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

        // The popover: opens below the pill, solid, with the readout, the track and five presets.
        begins = 0; ends = 0
        expect(!slider.isPopoverShown, "The popover starts closed")
        slider.keyDown(with: keyEvent(49, in: window))
        guard slider.isPopoverShown, let popover = slider.popover as? TestPopover, let panel = slider.popoverContent else { expect(false, "Space opens the popover"); return }
        expect(popover.edge == .minY && popover.anchor === slider && popover.behavior == .transient, "It opens below the pill and closes on an outside click")
        expect(panel.frame.size == NSSize(width: 320, height: 156), "The popover is 320 x 156")
        let (panelWindow, panelContent) = Self.window(NSSize(width: 320, height: 156))
        panelContent.addSubview(panel)
        panelContent.layoutSubtreeIfNeeded()
        var glass = 0
        func countGlass(_ view: NSView) { if view is NSGlassEffectView || view is NSGlassEffectContainerView { glass += 1 }; view.subviews.forEach(countGlass) }
        countGlass(panel)
        expect(glass == 0 && panel.wantsUpdateLayer, "The popover content is solid, never glass")
        panel.appearance = NSAppearance(named: .aqua)
        panel.updateLayer()
        expect((panel.layer?.backgroundColor?.alpha ?? 0) == 1, "The popover surface is opaque")
        let lightBackground = panel.layer?.backgroundColor
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.updateLayer()
        expect(panel.layer?.backgroundColor != lightBackground, "The popover surface follows light and dark")
        panel.appearance = nil
        expect(panel.titleLabel.stringValue == "Size" && panel.titleLabel.font?.pointSize == 20 && panel.readout.font?.pointSize == 20, "Title and readout are 20 pt")
        expect(panel.readout.stringValue == "7", "The readout shows the rounded size")
        slider.doubleValue = 9.375
        expect(panel.readout.stringValue == "9", "The readout follows the value")
        slider.doubleValue = 6.75
        let track = panel.trackView
        expect(track.frame.size == NSSize(width: 288, height: 36) && panel.presetButtons.count == 5 && panel.presetButtons.allSatisfy { $0.frame.size == NSSize(width: 48, height: 36) },
               "A 288 x 36 track and five 48 x 36 presets")
        expect(panel.presetButtons.map { $0.accessibilityLabel() ?? "" } == ["Size 2", "Size 4", "Size 7", "Size 9", "Size 12"], "Presets are spoken Size 2/4/7/9/12")
        expect(panel.presetButtons.map(\.isSelectedPreset) == [false, false, true, false, false], "Only the current preset is selected")
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
        expect(slider.doubleValue == 9.375 && begins == 1 && ends == 1 && panel.presetButtons.map(\.isSelectedPreset) == [false, false, false, true, false], "A preset click is one group: \(groups())")
        panel.presetButtons[0].performClick(nil)
        expect(slider.doubleValue == 1.5 && begins == 2 && ends == 2 && panel.readout.stringValue == "2", "Another preset: \(groups())")
        // Dismissing mid-drag closes the group, and the late mouse-up cannot close it twice.
        begins = 0; ends = 0
        track.mouseDown(with: pointer(.leftMouseDown, fraction: 1))
        track.mouseDragged(with: pointer(.leftMouseDragged, fraction: 0.5))
        expect(begins == 1 && ends == 0, "A drag is open: \(groups())")
        slider.dismissPopover()
        expect(ends == 1 && !slider.isPopoverShown && slider.popoverContent == nil, "Dismissing mid-drag ends the group and releases the popover: \(groups())")
        track.mouseUp(with: pointer(.leftMouseUp, fraction: 0.5))
        expect(begins == 1 && ends == 1, "The stale mouse-up adds nothing: \(groups())")
        // Escape closes the popover; leaving the window closes it too.
        slider.doubleValue = 6.75
        slider.showPopover()
        expect(slider.isPopoverShown, "It opens again")
        slider.keyDown(with: keyEvent(53, in: window))
        expect(!slider.isPopoverShown, "Escape closes the popover")
        slider.showPopover()
        slider.removeFromSuperview()
        expect(!slider.isPopoverShown, "Leaving the window closes the popover")
        content.addSubview(slider)
        slider.isEnabled = false
        slider.showPopover()
        expect(!slider.isPopoverShown && !slider.accessibilityPerformPress() && slider.beginGesture() == false, "A disabled pill neither opens nor tracks")
        slider.isEnabled = true
        slider.removeFromSuperview()
    }

    // MARK: GlassSurfaceView (one plate per group) and ChromeFillCell

    private static func button(_ title: String = "", size: NSSize = GlassChrome.Metrics.iconButton) -> GlassChromeButton {
        let button = GlassChromeButton(title: title, target: nil, action: nil)
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
        let format = NSSegmentedControl(labels: ["PNG", "JPG"], trackingMode: .selectOne, target: nil, action: nil)
        format.selectedSegment = 0
        format.font = .systemFont(ofSize: 20)
        format.setAccessibilityLabel("Image format")
        let toolbox = NSPopUpButton(frame: .zero, pullsDown: true)
        toolbox.addItems(withTitles: ["Toolbox", "About OpenSnap", "Quit OpenSnap"])
        toolbox.font = .systemFont(ofSize: 20)
        toolbox.setAccessibilityLabel("Toolbox")
        let palette = BezelHoverButton(title: "Color…", target: nil, action: nil)
        palette.font = DesignTokens.Typography.font(.body)
        palette.setAccessibilityLabel("Drawing colors")
        palette.image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        let original = NSButton(checkboxWithTitle: "Original size", target: nil, action: nil)
        original.font = DesignTokens.Typography.font(.body)
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
            if let button = control as? GlassChromeButton, !button.visibleTitle.isEmpty {
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
            if size == minimum {
                widthBudgetChecks(rig, label)
                accessibilityChecks(rig, label)
                wellChecks(rig, label)
            }
        }
        canvasReachesMarginChecks(tag, minimum: minimum)
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
        // Bottom bar, measured: the checkbox and a 120 pt status are the worst case.
        let zoomWidth = rect(shared.zoomControl.superview!, in: rig).width
        let formatWidth = rect(shared.dragFormatControl, in: rig).width
        let checkbox = shared.dragOriginalControl.fittingSize.width
        let icons = pad + 2 * M.iconButton.width + spacing
        let bottom = icons + (pad + zoomWidth + spacing + M.iconButton.width) + icons + (pad + formatWidth + 2 * spacing + 2 * M.iconButton.width)
            + 4 * M.groupGap + checkbox + 12 + 120
        expect(bottom <= usable, "\(label): the bottom bar with the checkbox and a 120 pt status needs \(bottom) of \(usable) (zoom \(zoomWidth), format \(formatWidth), checkbox \(checkbox))")
        expect(ModernEditorChrome.minimumWindowWidth >= max(frame, bottom) + 24, "\(label): the minimum window width \(ModernEditorChrome.minimumWindowWidth) covers the worst case \(max(frame, bottom) + 24)")
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
            let known = Set(parts.map(ObjectIdentifier.init) + [ObjectIdentifier(rig.controls.dragOriginalControl)])
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
            expect(button.accessibilityLabel() == id.capitalized, "\(label): tool AX label \(id)")
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
                                     (chrome.wipeButton, "Wipe", "wipe"), (chrome.resizeButton, "Resize…", "resize")] {
            expect(button.title == title, "\(label): \(title) keeps its classic name")
            expect(button.accessibilityLabel() == title, "\(label): \(title) is read by its old title")
            expect(button.controlSize == .extraLarge, "\(label): \(title) uses Apple's Extra Large control size")
            expect(button.icon != nil && button.image != nil && button.imagePosition == .imageOnly && button.visibleTitle.isEmpty, "\(label): \(title) is icon-only")
            expect(button.identifier == nil, "\(label): \(title) has no identifier, as in classic")
            let size = button === chrome.snapButton ? GlassChrome.Metrics.primaryButton : GlassChrome.Metrics.iconButton
            expect(chrome.surface(for: button)?.cornerRadius == 16, "\(label): \(title) sits on a 16 pt group plate")
            expect(abs(rect(button, in: rig).height - size.height) < 0.5 && (button === chrome.cancelFrameButton && button.isHidden || abs(rect(button, in: rig).width - size.width) < 0.5), "\(label): \(title) is one consistent size \(size)")
            rig.target.hits.removeAll()
            button.performClick(nil)
            expect(rig.target.hits == [hit], "\(label): \(title) sends its action (\(rig.target.hits))")
            expect((button as? GlassChromeButton)?.plate.isSelected == false, "\(label): clicking \(title) never leaves it selected")
        }
        expect(chrome.shareButton.accessibilityLabel() == "Upload to destination" && chrome.shareButton.title.isEmpty && chrome.shareButton.imagePosition == .imageOnly,
               "\(label): the upload button is icon-only with an explicit label")
        rig.target.hits.removeAll(); chrome.shareButton.performClick(nil)
        expect(rig.target.hits == ["share"], "\(label): the upload button sends its action")
        expect(AppToolTip.text(for: chrome.snapButton) == snapToolTip, "\(label): Snap keeps its classic tooltip")
        expect(chrome.snapButton.isPrimary, "\(label): Snap is the primary command")
        let primaries = allButtons(in: chrome).compactMap { $0 as? GlassChromeButton }.filter { $0.isPrimary }
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
        for plainControl in [shared.dragOriginalControl, shared.status] as [NSControl] {
            expect(chrome.surface(for: plainControl) == nil, "\(label): \(describe(plainControl)) stays plain, outside any glass")
            expect(plainControl.superview is NSStackView && !(plainControl.superview?.superview is GlassSurfaceView), "\(label): \(describe(plainControl)) lives in the plain status row")
        }
        expect(chrome.surface(for: shared.zoomControl)?.identifier?.rawValue == "GlassViewGroup" && (shared.zoomControl.superview as? ChromeFillCell)?.fixedSize.height == 36, "\(label): the zoom popup sits in a 36 pt cell on the view plate")
        if let zoom = shared.zoomControl as? ZoomPopUpButton {
            let item = NSMenuItem(title: "83%", action: nil, keyEquivalent: "")
            item.toolTip = "Fit, 83%"
            zoom.menu?.insertItem(item, at: 0); zoom.select(item)
            expect(zoom.titleOfSelectedItem == "83%" && (zoom.accessibilityValue() as? String) == "Fit, 83%", "\(label): the zoom face is the percentage; VoiceOver hears the mode too")
            zoom.selectItem(withTitle: "100%")
            expect((zoom.accessibilityValue() as? String) == "100%", "\(label): a plain zoom item is spoken as its title")
            zoom.menu?.removeItem(item)
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
        expect(sameColor(brush.contentTintColor, .controlAccentColor), "\(label): the selected glyph is the accent")
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
            (chrome.fontButton, "Font", "Font"), (chrome.undoButton, "Undo", "Undo (⌘Z)"), (chrome.wipeButton, "Wipe", "Wipe"),
            (chrome.resizeButton, "Resize…", "Resize…"),
            (chrome.shareButton, "Upload to destination", "Upload")]
        for (button, name, tip) in expected {
            expect(button.imagePosition == .imageOnly, "\(label): \(name) draws only its icon")
            expect((button as? GlassChromeButton).map { $0.visibleTitle.isEmpty } ?? button.title.isEmpty, "\(label): \(name) shows no title text")
            expect(AppToolTip.text(for: button) == tip, "\(label): \(name) tooltip is '\(tip)' (is '\(AppToolTip.text(for: button) ?? "nil")')")
            expect(button.accessibilityLabel() == name, "\(label): \(name) accessibility label (is '\(button.accessibilityLabel() ?? "nil")')")
        }
        let shared = rig.controls
        expect(shared.paletteButton.imagePosition == .imageOnly && shared.paletteButton.image != nil && shared.paletteButton.accessibilityLabel() == "Drawing colors"
               && AppToolTip.text(for: shared.paletteButton)?.hasPrefix("Color") == true, "\(label): Color shows only its swatch, with a tooltip and label")
        expect(shared.toolbox.imagePosition == .imageOnly && shared.toolbox.accessibilityLabel() == "Toolbox", "\(label): Toolbox is icon-only")
        expect(shared.sizeLabel.superview == nil && AppToolTip.text(for: shared.widthControl) == "Size", "\(label): the Size text is gone; the pill keeps a tooltip")
        // Retitles move the tooltip and label, not drawn text.
        chrome.wipeButton.title = "Blank"
        expect(AppToolTip.text(for: chrome.wipeButton) == "Blank" && chrome.wipeButton.accessibilityLabel() == "Blank" && chrome.wipeButton.visibleTitle.isEmpty, "\(label): Wipe's staged title becomes its tooltip and label")
        chrome.wipeButton.title = "Wipe"
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
        (view is GlassChromeButton || view is ChromeFillCell ? [view] : []) + view.subviews.flatMap { fillOwners(in: $0) }
    }

    private static func plateOf(_ view: NSView) -> StatePlate? { (view as? GlassChromeButton)?.plate ?? (view as? ChromeFillCell)?.plate }

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
        for view in owners { (view as? ChromeFillCell)?.setHovered(false); (view as? GlassChromeButton)?.setHovered(false) }
        for button in chrome.toolButtons.values { button.state = .off }
        func saturated() -> [NSView] { owners.filter { ($0.isHiddenOrHasHiddenAncestor == false) && (plateOf($0)?.style.fill?.alphaComponent ?? 0) > 0.5 } }
        expect(saturated().count == 1 && saturated()[0] === chrome.snapButton, "\(label): at rest exactly one saturated accent exists: Snap (\(saturated().map(describe)))")
        expect(chrome.snapButton.plate.style.fill?.alphaComponent == 1, "\(label): Snap's fill is the accent at 1.0")
        for view in owners where view !== chrome.snapButton {
            expect(plateOf(view)?.style.fill == nil, "\(label): \(describe(view)) has no fill at rest")
        }
        chrome.toolButtons["ellipse"]?.appearance = NSAppearance(named: .aqua)
        chrome.toolButtons["ellipse"]?.state = .on
        let tool = chrome.toolButtons["ellipse"]!
        expect(abs((tool.plate.style.fill?.alphaComponent ?? 0) - 0.20) < 0.001 && tool.layer?.borderWidth == 1 && sameColor(tool.plate.style.border, accentAqua), "\(label): the selected tool is accent 0.20 with a 1 pt accent border")
        expect(saturated().count == 1, "\(label): selecting a tool adds no second saturated element")
        for view in owners { (view as? GlassChromeButton)?.setHovered(true); (view as? ChromeFillCell)?.setHovered(true) }
        expect(saturated().count == 1 && owners.filter { plateOf($0)?.style.fill != nil }.count == owners.count, "\(label): hovering everything fills everything faintly but adds no saturated accent")
        for view in owners { (view as? GlassChromeButton)?.setHovered(false); (view as? ChromeFillCell)?.setHovered(false) }
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
