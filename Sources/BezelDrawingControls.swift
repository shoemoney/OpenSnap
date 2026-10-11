import AppKit

enum OriginalDrawingControls {
    struct Preset {
        let tag: Int
        let name: String
        let bits: [UInt32]
        var color: NSColor {
            let rgba = bits.map { CGFloat(Float(bitPattern: $0)) }
            // The original DocumentController takes the raw table floats.
            // A calibrated swatch converted to deviceRGB would alter them.
            return NSColor(deviceRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3]) // token-exempt: original preset colour data
        }
    }
    // Original __GLOBAL__I_a at0x001dc570 initializes tags100...110.
    static let presets: [Preset] = [
        Preset(tag: 100, name: "Red", bits: [0x3f800000,0,0,0x3f800000]),
        Preset(tag: 101, name: "Yellow", bits: [0x3f800000,0x3f77f7f8,0,0x3f800000]),
        Preset(tag: 102, name: "Blue", bits: [0x3dc8c8c9,0x3eeeeeef,0x3f800000,0x3f800000]),
        Preset(tag: 103, name: "Pink", bits: [0x3f7cfcfd,0x3d40c0c1,0x3eb2b2b3,0x3f800000]),
        Preset(tag: 104, name: "Translucent gray", bits: [0,0,0,0x3edc28f6]),
        Preset(tag: 105, name: "Orange", bits: [0x3f800000,0x3f008081,0x3db8b8b9,0x3f800000]),
        Preset(tag: 106, name: "Green", bits: [0,0x3f68e8e9,0,0x3f800000]),
        Preset(tag: 107, name: "White", bits: [0x3f800000,0x3f800000,0x3f800000,0x3f800000]),
        Preset(tag: 108, name: "Black", bits: [0,0,0,0x3f800000]),
        Preset(tag: 109, name: "Highlighter", bits: [0x3f800000,0x3f800000,0,0x3eb33333])
    ]
    /// The original panel reads calibrated components into float RGBA storage.
    static func drawingColor(from panelColor: NSColor) -> NSColor? {
        guard let rgb = panelColor.usingColorSpace(.genericRGB) else { return nil }
        let values = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent].map { CGFloat(Float($0)) }
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return NSColor(deviceRed: values[0], green: values[1], blue: values[2], alpha: values[3]) // token-exempt: drawing colour data
    }
    static func legacyRGB(_ color: NSColor) -> String {
        let raw = SketchColor(color)
        return "rgb(\(Double(raw.red)*255),\(Double(raw.green)*255),\(Double(raw.blue)*255))"
    }
    static func legacyColor(_ value: String?, alpha: String?) -> NSColor? {
        guard let value, value.hasPrefix("rgb("), value.hasSuffix(")") else { return nil }
        let parts = value.dropFirst(4).dropLast().split(separator: ",", omittingEmptySubsequences: false)
        let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 3, values.allSatisfy({ $0.isFinite && (0...255).contains($0) }),
              let opacity = Double(alpha ?? "1"), opacity.isFinite, (0...1).contains(opacity) else { return nil }
        return NSColor(deviceRed: CGFloat(Float(values[0]/255)), green: CGFloat(Float(values[1]/255)), // token-exempt: stored drawing colour data
                       blue: CGFloat(Float(values[2]/255)), alpha: CGFloat(Float(opacity)))
    }
    static let minimum = 1.5, maximum = 12.0, initialSize = 6.75
    static let sizeSteps = (0..<5).map { minimum + Double($0) * (maximum - minimum) / 4 }
    static func size(_ raw: Double, continuous: Bool) -> Double {
        guard raw.isFinite else { return initialSize }
        let clamped = min(maximum, max(minimum, raw))
        return continuous ? clamped : minimum + ((clamped-minimum)/(maximum-minimum)*4).rounded()*(maximum-minimum)/4
    }
    // Recovered float polynomial at Document::fontSizeFromCurrentBrushSize,
    //0x001c2312. Annotation readability policy supplies the18-point floor.
    static func originalFontSize(_ brush: Double) -> Double {
        let x = (Float(size(brush, continuous: true)) - 1.5) / 10.5
        let x2 = x*x, x3 = x2*x
        let value = x * Float(bitPattern: 0xbf2aaaab) + x2*44 + x3*x*64 + x3*Float(bitPattern: 0xc2555555) + 10
        return Double((value*10).rounded()*Float(bitPattern: 0x3dcccccd))
    }
    static func readableFontSize(_ brush: Double, displayFontScale: CGFloat = 1) -> CGFloat {
        // Original Document::displayFontScale is output height / logical height,
        // independent of the editor zoom. Store logical points so Size stays
        // consistent when the document output has been resized.
        let scale = displayFontScale.isFinite && displayFontScale > 0 ? displayFontScale : 1
        return min(4096, max(18, max(18, CGFloat(originalFontSize(brush))) / scale))
    }
}

/// A preset colour swatch in the Drawing colors panel. Rest is a 1 pt separator outline, hover strengthens it, a press fills it, and
/// the selected swatch gets a 3 pt accent outline plus a check glyph, so the choice is never colour alone (`StateStyles.swatch`).
/// Behind the swatch sits the same rounded hover and pressed fill every glass choice draws (`StateStyles.command`); selection stays the
/// outline and check, so that fill never takes the selected look. The fill is drawn, not put on a layer of its own: a layer would convert
/// the swatch's device-RGB colour on its way to the window and the swatch would stop matching the toolbar's.
@MainActor
final class BezelColorButton: NSButton {
    static let checkPointSize: CGFloat = 16
    var drawingColor: NSColor = .red { didSet { needsDisplay = true } }
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?
    private var primaryTracking = false

    /// The fill behind the swatch right now: the command hover or pressed fill, nil at rest, selected or disabled.
    var plateFill: NSColor? {
        guard isEnabled else { return nil }
        let state: ControlState = primaryTracking || isHighlighted ? .pressed : (isHovered ? .hover : .rest)
        let options = DisplayOptions.current
        return StateStyles.command(state, primary: false, focused: false, highContrast: options.increaseContrast,
                                   differentiate: options.differentiateWithoutColor, appearance: effectiveAppearance).fill
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }
    /// The panel a swatch sits in is often not key (a hover-opened palette never is): the first press must pick the colour, not just make
    /// the panel key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // NSButton highlights its cell directly while tracking a primary click and never calls highlight(_:), so the press is bracketed here.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        primaryTracking = true; needsDisplay = true
        super.mouseDown(with: event)
        primaryTracking = false; needsDisplay = true
    }

    var controlState: ControlState {
        if !isEnabled { return .disabled }
        if state == .on { return .selected }
        if isHighlighted { return .pressed }
        return isHovered ? .hover : .rest
    }

    /// What this swatch draws right now, under the live display options.
    var swatchStyle: SwatchStyle {
        StateStyles.swatch(controlState, highContrast: DisplayOptions.current.increaseContrast, appearance: effectiveAppearance)
    }

    /// Hover entry point for the tracking area; tests drive it directly.
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewDidHide() { super.viewDidHide(); setHovered(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false) }
        super.viewWillMove(toWindow: newWindow)
    }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let style = swatchStyle
        let rect = bounds.insetBy(dx: 3, dy: 3)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        if let fill = plateFill {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: StatePlate.radius, yRadius: StatePlate.radius).fill()
        }
        NSGraphicsContext.saveGraphicsState()
        if style.alpha < 1 { NSGraphicsContext.current?.cgContext.setAlpha(style.alpha) }
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        for row in 0..<Int(ceil(rect.height/6)) {
            for column in 0..<Int(ceil(rect.width/6)) {
                ((row+column)%2 == 0 ? NSColor.white : NSColor(white: 0.72, alpha: 1)).setFill() // token-exempt: transparency checkerboard behind a document colour
                NSRect(x: rect.minX+CGFloat(column)*6, y: rect.minY+CGFloat(row)*6, width: 6, height: 6).fill()
            }
        }
        drawingColor.setFill(); rect.fill()
        if let fill = style.fill { fill.setFill(); rect.fill() }
        NSGraphicsContext.restoreGraphicsState()
        style.outline.setStroke()
        shape.lineWidth = style.outlineWidth; shape.stroke()
        if style.check, let glyph = ChromeIcons.resolve(.check, family: .solid, pointSize: Self.checkPointSize).image {
            Self.drawTinted(glyph, color: StateStyles.checkColor(on: drawingColor), centeredIn: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        if window?.firstResponder === self {
            DesignTokens.Palette.focusRing.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            focus.lineWidth = 2; focus.stroke()
        }
    }

    /// A template glyph filled with one colour, centred in `rect`.
    static func drawTinted(_ image: NSImage, color: NSColor, centeredIn rect: NSRect) {
        let tinted = NSImage(size: image.size, flipped: false) { bounds in
            image.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2, width: image.size.width, height: image.size.height))
    }
}

/// The "Custom color…" row of the Drawing colors panel: a `GlassChoiceButton` on a plate of its own. While the stroke colour is none of
/// the presets, the row is the chosen option and carries the colour in use: a chip of it with the check glyph leading the title, next to
/// the selected fill, border and semibold title every chosen glass choice gets, so the panel always shows which colour is active and the
/// choice is never colour alone. With a preset current it is the plain row it always was.
@MainActor
enum BezelCustomColorButton {
    static let title = "Custom color…"
    /// The tag the row has always carried.
    static let tag = 110
    static let chipSize = NSSize(width: GlassChoiceButton.glyphSide, height: 18)

    static func make(target: AnyObject?, action: Selector?) -> GlassChoiceButton {
        let row = GlassChoiceButton(title: title, kind: .option, indicator: GlassChoiceButton.Indicator.none, layout: .row)
        row.tag = tag
        row.identifier = NSUserInterfaceItemIdentifier("color.custom")
        row.reservesIconColumn = true
        row.target = target; row.action = action
        row.accessibility = .live
        return row
    }

    /// Marks the row as the current choice with `color`'s chip, or clears the mark (nil).
    static func apply(_ color: NSColor?, to row: GlassChoiceButton) {
        row.leadingImage = color.map(chip(for:))
        row.isChosen = color != nil
    }

    /// The colour as a small rounded chip over the transparency checkerboard (the colour may be translucent), with the check on it.
    static func chip(for color: NSColor) -> NSImage {
        NSImage(size: chipSize, flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            for row in 0..<Int(ceil(rect.height / 5)) {
                for column in 0..<Int(ceil(rect.width / 5)) {
                    ((row + column) % 2 == 0 ? NSColor.white : NSColor(white: 0.72, alpha: 1)).setFill() // token-exempt: transparency checkerboard behind a document colour
                    NSRect(x: CGFloat(column) * 5, y: CGFloat(row) * 5, width: 5, height: 5).fill()
                }
            }
            color.setFill(); rect.fill()
            NSGraphicsContext.restoreGraphicsState()
            DesignTokens.Palette.SwatchOutline.rest.setStroke(); shape.lineWidth = 1; shape.stroke()
            if let glyph = ChromeIcons.resolve(.check, family: .solid, pointSize: 12).image {
                BezelColorButton.drawTinted(glyph, color: StateStyles.checkColor(on: color), centeredIn: rect)
            }
            return true
        }
    }
}

/// The Size control: a 48 x 36 pill that draws the current stroke thickness as a horizontal line and opens a glass panel
/// (`GlassPanelHost`) with a track and five presets. The pill stays the one model object: the value, the target/action, the undo
/// grouping and the "Size N" tooltip all live here, and the panel drives them through the same gesture API.
/// Five ordinary steps from the recovered control; Shift gives continuous values throughout.
@MainActor
final class BezelSizeSlider: NSControl {
    static let pillSize = NSSize(width: 48, height: 36)
    static let glyphLength: CGFloat = 24
    /// One preset step, the distance between neighbouring sizes.
    static let stepSize = 2.625
    /// The VoiceOver action that opens the panel with the five presets and the track.
    static let showOptionsActionName = "Show size options"
    var onBegin: (() -> Bool)?
    var onEnd: (() -> Void)?
    /// Runs on every new panel before it is shown. A test gives it a presenter, so the panel never reaches the screen.
    var panelSetup: (GlassPanelHost) -> Void = { _ in }
    private(set) var panel: GlassPanelHost?
    private(set) var popoverContent: SizePopoverContent?
    var isPopoverShown: Bool { panel?.isShown == true }
    /// The panel's own window, while it is up (the screenshot harness orders it front).
    var panelWindow: NSWindow? { isPopoverShown ? panel?.window : nil }
    private var tracking = false
    private var value = OriginalDrawingControls.initialSize
    private var lastPopoverClose: TimeInterval = -.infinity
    /// Hover, press and enabled changes, so the cell the pill sits in can draw its plate fill for the same state.
    var onInteractionChange: (() -> Void)?
    private(set) var isPressed = false
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { KeyboardNavigation.reaches(self) }
    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { dismissPopover(); isPressed = false; isHovered = false }
            needsDisplay = true
            popoverContent?.sync()
            onInteractionChange?()
        }
    }
    var controlState: ControlState {
        if !isEnabled { return .disabled }
        return isPressed ? .pressed : (isHovered ? .hover : .rest)
    }
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
        onInteractionChange?()
    }
    func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else { return }
        isPressed = pressed
        needsDisplay = true
        onInteractionChange?()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func mouseUp(with event: NSEvent) { setPressed(false) }
    override func viewDidHide() { super.viewDidHide(); setHovered(false); setPressed(false) }
    override var doubleValue: Double {
        get { value }
        set { value = OriginalDrawingControls.size(newValue, continuous: true); needsDisplay = true; popoverContent?.sync() }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = NSActionCell(); isEnabled = true
        font = DesignTokens.Typography.font(.body)
        focusRingType = .exterior
        setAccessibilityElement(true); setAccessibilityRole(.slider)
        setAccessibilityLabel("Drawing size")
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: Self.showOptionsActionName) { [weak self] in
            guard let self, self.isEnabled else { return false }
            if !self.isPopoverShown { self.showPopover() }
            return true
        }])
        AppToolTip.setText("Five drawing sizes; hold Shift for continuous adjustment", for: self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// The whole-number size, as the tooltip and the old Size text read it; the stored value keeps its fraction.
    override func accessibilityValue() -> Any? { NSNumber(value: value.rounded()) }
    override func accessibilityMinValue() -> Any? { NSNumber(value: OriginalDrawingControls.minimum) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: OriginalDrawingControls.maximum) }
    override func setAccessibilityValue(_ value: Any?) {
        guard let number = value as? NSNumber else { return }
        performValueChange(number.doubleValue, continuous: true)
    }
    override func accessibilityPerformIncrement() -> Bool { performValueChange(value + Self.stepSize, continuous: false); return isEnabled }
    override func accessibilityPerformDecrement() -> Bool { performValueChange(value - Self.stepSize, continuous: false); return isEnabled }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        if isPopoverShown { dismissPopover() } else { showPopover() }
        return true
    }

    /// The stroke the pill draws: the command content colour, 0.96 shorter while pressed, dimmed to 0.38 when disabled.
    var pillStyle: StateStyle {
        let options = DisplayOptions.current
        return StateStyles.command(controlState, primary: false, focused: false, highContrast: options.increaseContrast,
                                   differentiate: options.differentiateWithoutColor, appearance: effectiveAppearance)
    }

    override func draw(_ dirtyRect: NSRect) {
        let style = pillStyle
        let thickness = CGFloat(value)
        let length = Self.glyphLength * (DisplayOptions.current.reduceMotion ? 1 : style.glyphScale)
        let line = NSRect(x: (bounds.width - length) / 2, y: (bounds.height - thickness) / 2, width: length, height: thickness)
        style.content.withAlphaComponent(style.contentAlpha).setFill()
        NSBezierPath(roundedRect: line, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }

    private var focusBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override var focusRingMaskBounds: NSRect { isEnabled && !focusBounds.isEmpty ? focusBounds : .zero }
    override func drawFocusRingMask() {
        guard isEnabled, !focusBounds.isEmpty else { return }
        NSColor.black.setFill()
        NSBezierPath(roundedRect: focusBounds, xRadius: focusBounds.height / 2, yRadius: focusBounds.height / 2).fill()
    }

    // MARK: gesture API shared by the pill and the panel

    /// Opens the undo group for one gesture; false when the app declines (terminating, capturing, a sheet is up).
    @discardableResult func beginGesture() -> Bool {
        guard isEnabled else { return false }
        if tracking { return true }
        guard onBegin?() ?? true else { return false }
        tracking = true; return true
    }
    func endTracking() { guard tracking else { return }; tracking = false; onEnd?() }
    /// A position along the track (0 is the smallest size). Plain values snap to the five steps; Shift keeps them continuous.
    func trackValue(fraction: CGFloat, modifiers: NSEvent.ModifierFlags) {
        guard tracking, fraction.isFinite else { return }
        let span = OriginalDrawingControls.maximum - OriginalDrawingControls.minimum
        update(OriginalDrawingControls.minimum + Double(min(1, max(0, fraction))) * span, continuous: modifiers.contains(.shift))
    }
    func resetValue() {
        guard tracking else { return }
        update(OriginalDrawingControls.initialSize, continuous: true)
    }
    func fraction(forSize size: Double) -> CGFloat {
        CGFloat((size - OriginalDrawingControls.minimum) / (OriginalDrawingControls.maximum - OriginalDrawingControls.minimum))
    }
    private func update(_ raw: Double, continuous: Bool) {
        let chosen = OriginalDrawingControls.size(raw, continuous: continuous)
        guard chosen != value else { return }
        doubleValue = chosen; _ = sendAction(action, to: target)
    }
    /// One complete change: begin, update, end. A preset click, a keypress and an assistive increment are each one undo step.
    func performValueChange(_ raw: Double, continuous: Bool) {
        guard raw.isFinite, beginGesture() else { return }
        update(raw, continuous: continuous); endTracking()
    }

    // MARK: panel

    /// Opens the Size panel below the pill. It does not take the keyboard: the pill keeps it (arrows step, Space and Return toggle,
    /// Escape closes), and a click inside the panel hands the panel the keyboard as it does any floating panel.
    func showPopover() {
        guard isEnabled, let window, window.attachedSheet == nil, !isPopoverShown else { return }
        let content = SizePopoverContent(slider: self)
        let host = GlassPanelHost(plates: content.plates, identifier: "Size", accessibilityLabel: "Size")
        host.alignment = .center
        host.willClose = { [weak self] in self?.panelWillClose() }
        host.didClose = { [weak self] in self?.panelDidClose() }
        panelSetup(host)
        panel = host; popoverContent = content
        content.sync()
        AppToolTip.install(on: host.container)
        host.show(relativeTo: bounds, of: self, preferredEdge: .minY, makeKey: false)
    }
    /// Closes the panel and ends any gesture it still has open, so a dismissal mid-drag cannot leave an undo group behind.
    func dismissPopover() {
        endTracking()
        let host = panel
        host?.close()
    }
    private func panelWillClose() {
        setPressed(false)
        endTracking()
        lastPopoverClose = ProcessInfo.processInfo.systemUptime
    }
    private func panelDidClose() {
        panel = nil; popoverContent = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(true)
        // The original slider does not end native annotation typing. Keep that editor's focus.
        if !(window?.firstResponder is NSTextView) { window?.makeFirstResponder(self) }
        if isPopoverShown { dismissPopover() }
        // The panel's host swallows a click on the pill while it is up, so the pill never sees that press. Should a press still arrive
        // within the same click (a host that lets it through), reopening the panel would make the pill unable to toggle.
        else if event.timestamp - lastPopoverClose > 0.3 || event.timestamp < lastPopoverClose { showPopover() }
    }
    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift), step = shift ? 0.1 : Self.stepSize
        switch event.keyCode {
        case 124, 126: performValueChange(value + step, continuous: shift)
        case 123, 125: performValueChange(value - step, continuous: shift)
        case 49, 36, 76: if isPopoverShown { dismissPopover() } else { showPopover() }
        case 53: if isPopoverShown { dismissPopover() } else { endTracking() }
        default: super.keyDown(with: event)
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { dismissPopover() }
        super.viewWillMove(toWindow: newWindow)
    }
}

/// The content of the Size panel, as two glass plates for one `GlassPanelHost`: the title with its numeric readout and the track on the
/// first, the five presets on the second. The plates are the only glass; the track and the presets draw their own states on top.
@MainActor
final class SizePopoverContent {
    /// The rows are this wide, so each plate is this plus its 4 pt inset on either side.
    static let rowWidth: CGFloat = 312
    static let rowHeight = GlassChrome.Metrics.commandHeight
    static let horizontalPadding = DesignTokens.Space.s3
    static let presetSpacing = GlassChrome.Metrics.groupSpacing
    private weak var slider: BezelSizeSlider?
    let titleLabel = NSTextField(labelWithString: "Size")
    let readout = NSTextField(labelWithString: "")
    let trackView: SizeTrackView
    let presetButtons: [SizePresetButton]
    let headerRow = NSView(), trackRow = NSView(), presetRow = NSView()
    let trackPlate: GlassSurfaceView, presetPlate: GlassSurfaceView
    var plates: [GlassSurfaceView] { [trackPlate, presetPlate] }

    init(slider: BezelSizeSlider, accessibility: ChromeAccessibility? = nil) {
        let accessibility = accessibility ?? .live
        self.slider = slider
        trackView = SizeTrackView(slider: slider)
        presetButtons = OriginalDrawingControls.sizeSteps.map { SizePresetButton(size: $0, slider: slider) }
        titleLabel.font = DesignTokens.Typography.font(.bodyStrong)
        titleLabel.textColor = DesignTokens.Palette.Text.primary
        readout.font = .monospacedDigitSystemFont(ofSize: DesignTokens.Typography.readableDefault, weight: .regular)
        readout.textColor = DesignTokens.Palette.Text.primary
        readout.alignment = .right
        readout.setAccessibilityLabel("Size value")

        let pad = Self.horizontalPadding
        for view in [titleLabel, readout] { view.translatesAutoresizingMaskIntoConstraints = false; headerRow.addSubview(view) }
        trackView.translatesAutoresizingMaskIntoConstraints = false
        trackRow.addSubview(trackView)
        let presets = NSStackView(views: presetButtons)
        presets.orientation = .horizontal; presets.spacing = Self.presetSpacing; presets.distribution = .fillEqually
        presets.translatesAutoresizingMaskIntoConstraints = false
        presetRow.addSubview(presets)
        presetRow.setAccessibilityElement(true); presetRow.setAccessibilityRole(.radioGroup); presetRow.setAccessibilityLabel("Size presets")
        var constraints = [
            titleLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: pad), titleLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            readout.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor, constant: -pad), readout.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            readout.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: DesignTokens.Space.s2),
            trackView.centerXAnchor.constraint(equalTo: trackRow.centerXAnchor), trackView.centerYAnchor.constraint(equalTo: trackRow.centerYAnchor),
            trackView.widthAnchor.constraint(equalToConstant: SizeTrackView.size.width), trackView.heightAnchor.constraint(equalToConstant: SizeTrackView.size.height),
            presets.leadingAnchor.constraint(equalTo: presetRow.leadingAnchor), presets.trailingAnchor.constraint(equalTo: presetRow.trailingAnchor),
            presets.topAnchor.constraint(equalTo: presetRow.topAnchor), presets.bottomAnchor.constraint(equalTo: presetRow.bottomAnchor)
        ]
        for row in [headerRow, trackRow, presetRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            constraints += [row.widthAnchor.constraint(equalToConstant: Self.rowWidth), row.heightAnchor.constraint(equalToConstant: Self.rowHeight)]
        }
        constraints += presetButtons.map { $0.heightAnchor.constraint(equalToConstant: SizePresetButton.size.height) }
        NSLayoutConstraint.activate(constraints)
        trackPlate = GlassChrome.plate([headerRow, trackRow], identifier: "GlassSizeTrack", accessibility: accessibility, axis: .vertical)
        presetPlate = GlassChrome.plate([presetRow], identifier: "GlassSizePresets", accessibility: accessibility, axis: .vertical)
        // The panel is its own window, so the main window's loop does not reach it: the track, then the five presets, then round again.
        let order: [NSView] = [trackView] + presetButtons
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }
    }

    /// Re-reads the slider: readout, knob and the selected preset.
    func sync() {
        guard let slider else { return }
        readout.stringValue = String(format: "%.0f", slider.doubleValue.rounded())
        trackView.needsDisplay = true
        for button in presetButtons { button.sync() }
    }
}

/// The horizontal track in the Size panel: drag anywhere. A plain drag snaps to the five sizes, Shift keeps it continuous.
/// The knob grows to 1.15 on hover and 1.25 while held, the track takes an accent wash while held, and a disabled pill
/// dims the whole track to 0.38 and ignores the pointer (`StateStyles.track`).
@MainActor
final class SizeTrackView: NSControl {
    static let size = NSSize(width: 288, height: 36)
    static let knobDiameter: CGFloat = 20
    private weak var slider: BezelSizeSlider?
    private(set) var isHovered = false, isPressed = false
    private var hoverArea: NSTrackingArea?
    override var acceptsFirstResponder: Bool { isEnabled }
    override var isEnabled: Bool {
        get { slider?.isEnabled ?? false }
        set { }
    }

    var controlState: ControlState {
        if !isEnabled { return .disabled }
        return isPressed ? .pressed : (isHovered ? .hover : .rest)
    }
    var trackStyle: TrackStyle { StateStyles.track(controlState, highContrast: DisplayOptions.current.increaseContrast, appearance: effectiveAppearance) }
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered; needsDisplay = true
    }
    func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else { return }
        isPressed = pressed; needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewDidHide() { super.viewDidHide(); setHovered(false); setPressed(false) }

    init(slider: BezelSizeSlider) {
        self.slider = slider
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        font = DesignTokens.Typography.font(.body)
        focusRingType = .exterior
        setAccessibilityElement(true); setAccessibilityRole(.slider)
        setAccessibilityLabel("Size")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var travel: CGFloat { bounds.width - Self.knobDiameter }
    func fraction(forX x: CGFloat) -> CGFloat { travel > 0 ? (x - Self.knobDiameter / 2) / travel : 0 }
    func x(forFraction fraction: CGFloat) -> CGFloat { Self.knobDiameter / 2 + fraction * travel }

    override func accessibilityValue() -> Any? { slider.map { NSNumber(value: $0.doubleValue.rounded()) } }
    override func accessibilityMinValue() -> Any? { NSNumber(value: OriginalDrawingControls.minimum) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: OriginalDrawingControls.maximum) }
    override func accessibilityPerformIncrement() -> Bool { slider?.accessibilityPerformIncrement() ?? false }
    override func accessibilityPerformDecrement() -> Bool { slider?.accessibilityPerformDecrement() ?? false }

    /// The knob as drawn now: its rest diameter times the state's scale, centred on the value.
    var knobRect: NSRect {
        guard let slider else { return .zero }
        let diameter = Self.knobDiameter * trackStyle.knobScale
        let knobX = x(forFraction: slider.fraction(forSize: slider.doubleValue))
        return NSRect(x: knobX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let slider else { return }
        let style = trackStyle, midY = bounds.midY
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if style.alpha < 1 { NSGraphicsContext.current?.cgContext.setAlpha(style.alpha) }
        let track = NSRect(x: Self.knobDiameter / 2, y: midY - 4, width: travel, height: 8)
        style.track.setFill()
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        if let highlight = style.highlight { highlight.setFill(); NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill() }
        style.dots.setFill()
        for step in OriginalDrawingControls.sizeSteps {
            let x = self.x(forFraction: slider.fraction(forSize: step))
            NSBezierPath(ovalIn: NSRect(x: x - 2, y: midY - 2, width: 4, height: 4)).fill()
        }
        let knob = NSBezierPath(ovalIn: knobRect)
        style.knob.setFill(); knob.fill()
        if let border = style.knobBorder { border.setStroke(); knob.lineWidth = 1.5; knob.stroke() }
    }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
    }

    private func track(_ event: NSEvent) {
        slider?.trackValue(fraction: fraction(forX: convert(event.locationInWindow, from: nil).x), modifiers: event.modifierFlags)
    }
    /// The Size panel is not key until it is clicked: the first press must start the drag, not just make the panel key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let slider, slider.beginGesture() else { return }
        setPressed(true)
        window?.makeFirstResponder(self)
        if event.clickCount > 1 { slider.resetValue() } else { track(event) }
    }
    override func mouseDragged(with event: NSEvent) { track(event) }
    override func mouseUp(with event: NSEvent) { setPressed(false); slider?.endTracking() }
    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift), step = shift ? 0.1 : BezelSizeSlider.stepSize
        guard let slider else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 124, 126: slider.performValueChange(slider.doubleValue + step, continuous: shift)
        case 123, 125: slider.performValueChange(slider.doubleValue - step, continuous: shift)
        default: super.keyDown(with: event)
        }
    }
}

/// One of the five sizes, a glass choice in the Size panel. The rounded fill and border behind it are the same `StatePlate` every glass
/// choice draws (hover, pressed, selected); the view itself draws only the stroke glyph, a line as thick as the size. The chosen one
/// is marked three ways, never colour alone: the selected fill with its accent border, a longer line (visual weight), and, under
/// Differentiate Without Color, the capsule `StateStyles.command` adds under the glyph.
@MainActor
final class SizePresetButton: NSButton {
    static let size = NSSize(width: 48, height: 36)
    /// How much longer the chosen preset's line is drawn than the others'.
    static let chosenGlyphExtra: CGFloat = 6
    let presetSize: Double
    private weak var slider: BezelSizeSlider?
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?
    private var primaryTracking = false, hasKeyboardFocus = false
    private(set) lazy var plate = StatePlate(view: self)
    var isSelectedPreset: Bool { slider.map { abs($0.doubleValue - presetSize) < 0.01 } ?? false }

    var controlState: ControlState {
        if slider?.isEnabled == false { return .disabled }
        if primaryTracking || isHighlighted { return .pressed }
        if isSelectedPreset { return .selected }
        return isHovered ? .hover : .rest
    }
    /// The command style this preset draws right now, under the live display options.
    var commandStyle: StateStyle {
        let options = DisplayOptions.current
        return StateStyles.command(controlState, primary: false, focused: hasKeyboardFocus, highContrast: options.increaseContrast,
                                   differentiate: options.differentiateWithoutColor, selected: isSelectedPreset, appearance: effectiveAppearance)
    }
    /// The length of the stroke glyph as drawn now.
    var glyphLength: CGFloat {
        let style = commandStyle
        let base = BezelSizeSlider.glyphLength * (DisplayOptions.current.reduceMotion ? 1 : style.glyphScale)
        return base + (isSelectedPreset ? Self.chosenGlyphExtra : 0)
    }
    /// Re-reads the slider and the pointer into the fill, the border and the glyph.
    func sync() {
        plate.accessibility = DisplayOptions.current.chrome
        plate.update(hovered: isHovered, pressed: primaryTracking || isHighlighted, selected: isSelectedPreset,
                     disabled: slider?.isEnabled == false, focused: hasKeyboardFocus)
        needsDisplay = true
    }
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered; sync()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewDidHide() { super.viewDidHide(); setHovered(false) }
    override func highlight(_ flag: Bool) { super.highlight(flag); sync() }
    /// The Size panel is not key until it is clicked: the first press must choose the size, not just make the panel key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // NSButton highlights its cell directly while tracking a primary click and never calls highlight(_:), so the press is bracketed here.
    override func mouseDown(with event: NSEvent) {
        guard slider?.isEnabled != false else { return }
        primaryTracking = true; sync()
        super.mouseDown(with: event)
        primaryTracking = false; sync()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); sync() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); sync() }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { hasKeyboardFocus = true; sync() }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { hasKeyboardFocus = false; sync() }
        return resigned
    }
    override var acceptsFirstResponder: Bool { slider?.isEnabled ?? false }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }

    init(size: Double, slider: BezelSizeSlider) {
        presetSize = size
        self.slider = slider
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        isBordered = false
        title = ""
        font = DesignTokens.Typography.font(.body)
        focusRingType = .exterior
        target = self; action = #selector(choose)
        let name = "Size " + String(format: "%.0f", size.rounded())
        setAccessibilityLabel(name); AppToolTip.setText(name, for: self)
        sync()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A preset is a discrete pick, so it closes the panel as a colour pick does; dragging the track is continuous and keeps it open.
    @objc private func choose() { slider?.performValueChange(presetSize, continuous: false); slider?.dismissPopover() }
    override func isAccessibilitySelected() -> Bool { isSelectedPreset }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilityValue() -> Any? { NSNumber(value: isSelectedPreset ? 1 : 0) }

    override func draw(_ dirtyRect: NSRect) {
        let style = commandStyle
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if style.contentAlpha < 1 { NSGraphicsContext.current?.cgContext.setAlpha(style.contentAlpha) }
        let thickness = CGFloat(presetSize), length = glyphLength
        let line = NSRect(x: (bounds.width - length) / 2, y: (bounds.height - thickness) / 2, width: length, height: thickness)
        style.content.setFill()
        NSBezierPath(roundedRect: line, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        if style.indicator {
            let mark = StateStyles.indicatorSize(highContrast: DisplayOptions.current.increaseContrast)
            let y = isFlipped ? bounds.height - StateStyles.indicatorInset - mark.height : StateStyles.indicatorInset
            NSBezierPath(roundedRect: NSRect(x: bounds.midX - mark.width / 2, y: y, width: mark.width, height: mark.height),
                         xRadius: mark.height / 2, yRadius: mark.height / 2).fill()
        }
    }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() {
        NSColor.black.setFill()
        let frame = bounds.insetBy(dx: 1, dy: 1)
        NSBezierPath(roundedRect: frame, xRadius: StatePlate.radius, yRadius: StatePlate.radius).fill()
    }
}

/// Original color-container/palette tracking is active without taking text focus.
/// It acts on the press, not the release, as a pop-up does: a press on the Color control closes the hover-opened palette (the panel host
/// closes on any outside press) and the same press must then open the pinned one, with no gap between the two.
final class BezelHoverButton: NSButton {
    var onHover: ((Bool) -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _ = sendAction(on: .leftMouseDown)
        setAccessibilityElement(true)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        _ = sendAction(on: .leftMouseDown)
        setAccessibilityElement(true)
    }
    /// Assistive activation dispatches the same action once, without the cell's mouse-tracking path. This button acts on mouse-down;
    /// the standard cell's accessibility press could open the panel yet report an unsupported attribute to the outside client.
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let action else { return false }
        return sendAction(action, to: target)
    }
    override var canBecomeKeyView: Bool { KeyboardNavigation.reaches(self) }
    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); hoverTracking = area; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
/// Reports the pointer entering and leaving the Drawing colors panel without taking the keyboard, so the hover bridge in the app can
/// keep a hover-opened palette up while the pointer crosses from the Color control into it. It tracks the plates, not the panel window,
/// so the panel needs no solid content view of its own.
@MainActor
final class PaletteHoverTracker: NSObject {
    var onHover: ((Bool) -> Void)?
    private var areas: [(view: NSView, area: NSTrackingArea)] = []

    func attach(to view: NSView) {
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .enabledDuringMouseDrag], owner: self, userInfo: nil)
        view.addTrackingArea(area)
        areas.append((view, area))
    }

    /// Stops tracking for good: a retired panel can no longer report into a replacement.
    func detach() {
        onHover = nil
        for (view, area) in areas { view.removeTrackingArea(area) }
        areas.removeAll()
    }

    // An NSTrackingArea owner is sent `mouseEntered:` and `mouseExited:`; Swift would export these as `mouseEnteredWith:` and so on.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { onHover?(true) }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// The content of the Drawing colors panel, as two glass plates for one `GlassPanelHost`: the title and the 5 x 2 swatch grid on the
/// first, the "Custom color…" choice on the second. The swatches and the Custom row are made by the app (they carry its targets and
/// hints); this lays them out.
@MainActor
final class ColorPaletteContent {
    static let swatchPitch = NSSize(width: 45, height: 34)
    static let columns = 5
    /// 12 pt margins around five 42 pt swatches 3 pt apart (each draws 3 pt inside its frame); every row is this wide, so the title,
    /// the grid and the Custom row share their edges.
    static let rowWidth: CGFloat = 246
    static let horizontalPadding = DesignTokens.Space.s3
    static let rowHeight = GlassChrome.Metrics.commandHeight
    let titleLabel: NSTextField
    let swatches: [BezelColorButton]
    let customButton: GlassChoiceButton
    let titleRow = NSView(), gridRow = NSView()
    let palettePlate: GlassSurfaceView, customPlate: GlassSurfaceView
    var plates: [GlassSurfaceView] { [palettePlate, customPlate] }
    /// The swatches in reading order, then Custom color…: the loop Tab walks inside the panel.
    var keyLoop: [NSView] { swatches + [customButton] }

    init(title: NSTextField, swatches: [BezelColorButton], custom: GlassChoiceButton, accessibility: ChromeAccessibility? = nil) {
        let accessibility = accessibility ?? .live
        titleLabel = title; self.swatches = swatches; customButton = custom
        title.font = DesignTokens.Typography.font(.bodyStrong)
        title.textColor = DesignTokens.Palette.Text.primary
        title.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addSubview(title)
        var constraints = [title.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor, constant: Self.horizontalPadding),
                           title.trailingAnchor.constraint(lessThanOrEqualTo: titleRow.trailingAnchor, constant: -Self.horizontalPadding),
                           title.centerYAnchor.constraint(equalTo: titleRow.centerYAnchor)]
        let swatchSize = NSSize(width: 42, height: 32)
        for (index, swatch) in swatches.enumerated() {
            swatch.translatesAutoresizingMaskIntoConstraints = false
            gridRow.addSubview(swatch)
            constraints += [swatch.leadingAnchor.constraint(equalTo: gridRow.leadingAnchor, constant: Self.horizontalPadding + CGFloat(index % Self.columns) * Self.swatchPitch.width),
                            swatch.topAnchor.constraint(equalTo: gridRow.topAnchor, constant: CGFloat(index / Self.columns) * Self.swatchPitch.height),
                            swatch.widthAnchor.constraint(equalToConstant: swatchSize.width), swatch.heightAnchor.constraint(equalToConstant: swatchSize.height)]
        }
        let gridRows = (swatches.count + Self.columns - 1) / Self.columns
        let gridHeight = CGFloat(max(0, gridRows - 1)) * Self.swatchPitch.height + swatchSize.height
        custom.translatesAutoresizingMaskIntoConstraints = false
        for row in [titleRow, gridRow] { row.translatesAutoresizingMaskIntoConstraints = false }
        constraints += [titleRow.widthAnchor.constraint(equalToConstant: Self.rowWidth), titleRow.heightAnchor.constraint(equalToConstant: Self.rowHeight),
                        gridRow.widthAnchor.constraint(equalToConstant: Self.rowWidth), gridRow.heightAnchor.constraint(equalToConstant: gridHeight),
                        custom.widthAnchor.constraint(equalToConstant: Self.rowWidth), custom.heightAnchor.constraint(equalToConstant: Self.rowHeight)]
        NSLayoutConstraint.activate(constraints)
        palettePlate = GlassChrome.plate([titleRow, gridRow], identifier: "GlassColorPalette", accessibility: accessibility, axis: .vertical)
        customPlate = GlassChrome.plate([custom], identifier: "GlassColorCustom", accessibility: accessibility, axis: .vertical)
        let loop = keyLoop
        for (index, view) in loop.enumerated() { view.nextKeyView = loop[(index + 1) % loop.count] }
    }
}
