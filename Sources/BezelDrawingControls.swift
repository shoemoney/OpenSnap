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

/// A preset colour swatch in the Drawing colours popover. Rest is a 1 pt separator outline, hover strengthens it, a press fills it, and
/// the selected swatch gets a 3 pt accent outline plus a check glyph, so the choice is never colour alone (`StateStyles.swatch`).
@MainActor
final class BezelColorButton: NSButton {
    static let checkPointSize: CGFloat = 16
    var drawingColor: NSColor = .red { didSet { needsDisplay = true } }
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?

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

/// The "Custom color…" row of the Drawing colors popover. While the stroke colour is none of the presets, this row carries the colour in
/// use: a chip of it with the check glyph beside the title, and the 3 pt accent outline a selected preset swatch gets, so the popover always
/// shows which colour is active and the choice is never colour alone. With a preset current it is the plain button it always was.
@MainActor
final class BezelCustomColorButton: OriginalActionButton {
    static let chipSize = NSSize(width: 28, height: 20)
    static let cornerRadius: CGFloat = 7
    /// The stroke colour while it is a custom one; nil while a preset is current.
    var currentColor: NSColor? { didSet { refreshCurrent() } }
    var isCurrentChoice: Bool { currentColor != nil }

    private func refreshCurrent() {
        if let currentColor {
            image = Self.chip(for: currentColor)
            imagePosition = .imageLeading
        } else {
            image = nil
            imagePosition = .noImage
        }
        needsDisplay = true
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isCurrentChoice else { return }
        let style = StateStyles.swatch(.selected, highContrast: DisplayOptions.current.increaseContrast, appearance: effectiveAppearance)
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: style.outlineWidth / 2, dy: style.outlineWidth / 2), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        style.outline.setStroke(); outline.lineWidth = style.outlineWidth; outline.stroke()
    }

    override func accessibilityValue() -> Any? { isCurrentChoice ? "Selected" : super.accessibilityValue() }
}

/// The Size control: a 48 x 36 pill that draws the current stroke thickness as a horizontal line and opens a popover
/// with a track and five presets. The pill stays the one model object: the value, the target/action, the undo
/// grouping and the "Size N" tooltip all live here, and the popover drives them through the same gesture API.
/// Five ordinary steps from the recovered control; Shift gives continuous values throughout.
@MainActor
final class BezelSizeSlider: NSControl, NSPopoverDelegate {
    static let pillSize = NSSize(width: 48, height: 36)
    static let glyphLength: CGFloat = 24
    /// One preset step, the distance between neighbouring sizes.
    static let stepSize = 2.625
    /// The VoiceOver action that opens the popover with the five presets and the track.
    static let showOptionsActionName = "Show size options"
    var onBegin: (() -> Bool)?
    var onEnd: (() -> Void)?
    /// Tests hand in a popover that never reaches the screen.
    var popoverProvider: () -> NSPopover = { NSPopover() }
    private(set) var popover: NSPopover?
    private(set) var popoverContent: SizePopoverContent?
    var isPopoverShown: Bool { popover?.isShown == true }
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

    // MARK: gesture API shared by the pill and the popover

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

    // MARK: popover

    func showPopover() {
        guard isEnabled, let window, window.attachedSheet == nil, !isPopoverShown else { return }
        let content = SizePopoverContent(slider: self)
        AppToolTip.install(on: content)
        let controller = NSViewController()
        controller.view = content
        let popover = popoverProvider()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.delegate = self
        self.popover = popover; popoverContent = content
        content.sync()
        popover.show(relativeTo: bounds, of: self, preferredEdge: .minY)
    }
    /// Closes the popover and ends any gesture it still has open, so a dismissal mid-drag cannot leave an undo group behind.
    func dismissPopover() {
        endTracking()
        popover?.performClose(nil)
    }
    func popoverWillClose(_ notification: Notification) {
        setPressed(false)
        endTracking()
        lastPopoverClose = ProcessInfo.processInfo.systemUptime
    }
    func popoverDidClose(_ notification: Notification) {
        popover = nil; popoverContent = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(true)
        // The original slider does not end native annotation typing. Keep that editor's focus.
        if !(window?.firstResponder is NSTextView) { window?.makeFirstResponder(self) }
        if isPopoverShown { dismissPopover() }
        // A transient popover already closed on this very click; reopening it would make the pill unable to toggle.
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

/// The solid (non-glass) content of the Size popover: a title and a numeric readout, a horizontal track and the five presets.
final class SizePopoverContent: NSView {
    static let size = NSSize(width: 320, height: 156)
    private weak var slider: BezelSizeSlider?
    let titleLabel = NSTextField(labelWithString: "Size")
    let readout = NSTextField(labelWithString: "")
    let trackView: SizeTrackView
    let presetButtons: [SizePresetButton]

    init(slider: BezelSizeSlider) {
        self.slider = slider
        trackView = SizeTrackView(slider: slider)
        presetButtons = OriginalDrawingControls.sizeSteps.map { SizePresetButton(size: $0, slider: slider) }
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        titleLabel.font = DesignTokens.Typography.font(.bodyStrong)
        readout.font = .monospacedDigitSystemFont(ofSize: DesignTokens.Typography.readableDefault, weight: .regular)
        readout.alignment = .right
        readout.setAccessibilityLabel("Size value")
        for view in [titleLabel, readout, trackView] + presetButtons {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        var constraints = [
            widthAnchor.constraint(equalToConstant: Self.size.width), heightAnchor.constraint(equalToConstant: Self.size.height),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.heightAnchor.constraint(equalToConstant: 28),
            readout.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), readout.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            readout.heightAnchor.constraint(equalToConstant: 28), readout.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), trackView.topAnchor.constraint(equalTo: topAnchor, constant: 56),
            trackView.widthAnchor.constraint(equalToConstant: SizeTrackView.size.width), trackView.heightAnchor.constraint(equalToConstant: SizeTrackView.size.height)
        ]
        let gap = (SizeTrackView.size.width - 5 * SizePresetButton.size.width) / 4
        for (index, button) in presetButtons.enumerated() {
            constraints += [
                button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16 + CGFloat(index) * (SizePresetButton.size.width + gap)),
                button.topAnchor.constraint(equalTo: topAnchor, constant: 104),
                button.widthAnchor.constraint(equalToConstant: SizePresetButton.size.width), button.heightAnchor.constraint(equalToConstant: SizePresetButton.size.height)
            ]
        }
        NSLayoutConstraint.activate(constraints)
        // A popover is its own window, so the main window's loop does not reach it: the track, then the five presets, then round again.
        let order: [NSView] = [trackView] + presetButtons
        for (index, view) in order.enumerated() { view.nextKeyView = order[(index + 1) % order.count] }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = DesignTokens.Palette.Surface.content.cgColor }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Re-reads the slider: readout, knob and the selected preset.
    func sync() {
        guard let slider else { return }
        readout.stringValue = String(format: "%.0f", slider.doubleValue.rounded())
        trackView.needsDisplay = true
        for button in presetButtons { button.needsDisplay = true }
    }
}

/// The horizontal track in the popover: drag anywhere. A plain drag snaps to the five sizes, Shift keeps it continuous.
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

/// One of the five sizes. It draws the command states (`StateStyles.command`); the selected one is marked by a thicker accent border
/// and a tinted fill, never by colour alone.
@MainActor
final class SizePresetButton: NSButton {
    static let size = NSSize(width: 48, height: 36)
    let presetSize: Double
    private weak var slider: BezelSizeSlider?
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?
    var isSelectedPreset: Bool { slider.map { abs($0.doubleValue - presetSize) < 0.01 } ?? false }

    var controlState: ControlState {
        if slider?.isEnabled == false { return .disabled }
        if isHighlighted { return .pressed }
        if isSelectedPreset { return .selected }
        return isHovered ? .hover : .rest
    }
    /// The command style this preset draws right now, under the live display options.
    var commandStyle: StateStyle {
        let options = DisplayOptions.current
        return StateStyles.command(controlState, primary: false, focused: false, highContrast: options.increaseContrast,
                                   differentiate: options.differentiateWithoutColor, selected: isSelectedPreset, appearance: effectiveAppearance)
    }
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered; needsDisplay = true
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
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A preset is a discrete pick, so it closes the popover as a colour pick does; dragging the track is continuous and keeps it open.
    @objc private func choose() { slider?.performValueChange(presetSize, continuous: false); slider?.dismissPopover() }
    override func isAccessibilitySelected() -> Bool { isSelectedPreset }

    override func draw(_ dirtyRect: NSRect) {
        let style = commandStyle
        let frame = bounds.insetBy(dx: 1, dy: 1)
        let outline = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if style.contentAlpha < 1 { NSGraphicsContext.current?.cgContext.setAlpha(style.contentAlpha) }
        if let fill = style.fill { fill.setFill(); outline.fill() }
        // A preset is a discrete option, so it keeps a hairline outline at rest; the selected one doubles it in the accent.
        (style.border ?? DesignTokens.Palette.separator).setStroke()
        outline.lineWidth = style.border == nil ? 1 : 2
        outline.stroke()
        let thickness = CGFloat(presetSize)
        let length = BezelSizeSlider.glyphLength * (DisplayOptions.current.reduceMotion ? 1 : style.glyphScale)
        let line = NSRect(x: (bounds.width - length) / 2, y: (bounds.height - thickness) / 2, width: length, height: thickness)
        style.content.setFill()
        NSBezierPath(roundedRect: line, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
}

/// Original color-container/palette tracking is active without taking text focus.
final class BezelHoverButton: NSButton {
    var onHover: ((Bool) -> Void)?
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
/// The Drawing colors popover's content. It paints its own opaque content plate, as the Size popover does, so its text and controls
/// never sit on the system popover material (which can come out dark under a light app); the plate follows the appearance.
final class BezelHoverPaletteView: NSView {
    var onHover: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = DesignTokens.Palette.Surface.content.cgColor }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); hoverTracking = area; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
