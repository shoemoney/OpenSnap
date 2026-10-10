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
        var swatchColor: NSColor {
            let rgba = bits.map { CGFloat(Float(bitPattern: $0)) }
            return NSColor(calibratedRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3]) // token-exempt: original preset colour data
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

final class BezelColorButton: NSButton {
    var drawingColor: NSColor = .red { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).addClip()
        for row in 0..<Int(ceil(rect.height/6)) {
            for column in 0..<Int(ceil(rect.width/6)) {
                ((row+column)%2 == 0 ? NSColor.white : NSColor(white: 0.72, alpha: 1)).setFill() // token-exempt: transparency checkerboard behind a document colour
                NSRect(x: rect.minX+CGFloat(column)*6, y: rect.minY+CGFloat(row)*6, width: 6, height: 6).fill()
            }
        }
        drawingColor.setFill(); rect.fill()
        NSGraphicsContext.restoreGraphicsState()
        let outline = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        (state == .on ? DesignTokens.Palette.accent : DesignTokens.Palette.SwatchOutline.rest).setStroke()
        outline.lineWidth = state == .on ? 3 : 1; outline.stroke()
        if window?.firstResponder === self {
            DesignTokens.Palette.focusRing.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            focus.lineWidth = 2; focus.stroke()
        }
    }
}

/// The Size control: a 48 x 36 pill that draws the current stroke thickness as a horizontal line and opens a popover
/// with a track and five presets. The pill stays the one model object: the value, the target/action, the undo
/// grouping and the "Size N" tooltip all live here, and the popover drives them through the same gesture API.
/// Five ordinary steps from the recovered control; Shift gives continuous values throughout.
final class BezelSizeSlider: NSControl, NSPopoverDelegate {
    static let pillSize = NSSize(width: 48, height: 36)
    static let glyphLength: CGFloat = 24
    /// One preset step, the distance between neighbouring sizes.
    static let stepSize = 2.625
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
    override var acceptsFirstResponder: Bool { true }
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
        toolTip = "Five drawing sizes; hold Shift for continuous adjustment"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityValue() -> Any? { NSNumber(value: value) }
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

    override func draw(_ dirtyRect: NSRect) {
        let thickness = CGFloat(value)
        let line = NSRect(x: (bounds.width - Self.glyphLength) / 2, y: (bounds.height - thickness) / 2, width: Self.glyphLength, height: thickness)
        (isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor).setFill()
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
        endTracking()
        lastPopoverClose = ProcessInfo.processInfo.systemUptime
    }
    func popoverDidClose(_ notification: Notification) {
        popover = nil; popoverContent = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
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
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor }
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
final class SizeTrackView: NSControl {
    static let size = NSSize(width: 288, height: 36)
    static let knobDiameter: CGFloat = 20
    private weak var slider: BezelSizeSlider?
    override var acceptsFirstResponder: Bool { true }

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

    override func accessibilityValue() -> Any? { slider.map { NSNumber(value: $0.doubleValue) } }
    override func accessibilityMinValue() -> Any? { NSNumber(value: OriginalDrawingControls.minimum) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: OriginalDrawingControls.maximum) }
    override func accessibilityPerformIncrement() -> Bool { slider?.accessibilityPerformIncrement() ?? false }
    override func accessibilityPerformDecrement() -> Bool { slider?.accessibilityPerformDecrement() ?? false }

    override func draw(_ dirtyRect: NSRect) {
        guard let slider else { return }
        let midY = bounds.midY
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: Self.knobDiameter / 2, y: midY - 4, width: travel, height: 8), xRadius: 4, yRadius: 4).fill()
        NSColor.secondaryLabelColor.setFill()
        for step in OriginalDrawingControls.sizeSteps {
            let x = self.x(forFraction: slider.fraction(forSize: step))
            NSBezierPath(ovalIn: NSRect(x: x - 2, y: midY - 2, width: 4, height: 4)).fill()
        }
        let knobX = x(forFraction: slider.fraction(forSize: slider.doubleValue))
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX - Self.knobDiameter / 2, y: midY - Self.knobDiameter / 2, width: Self.knobDiameter, height: Self.knobDiameter)).fill()
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
        window?.makeFirstResponder(self)
        if event.clickCount > 1 { slider.resetValue() } else { track(event) }
    }
    override func mouseDragged(with event: NSEvent) { track(event) }
    override func mouseUp(with event: NSEvent) { slider?.endTracking() }
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

/// One of the five sizes. The selected one is marked by a thicker accent border and a tinted fill, never by colour alone.
final class SizePresetButton: NSButton {
    static let size = NSSize(width: 48, height: 36)
    let presetSize: Double
    private weak var slider: BezelSizeSlider?
    var isSelectedPreset: Bool { slider.map { abs($0.doubleValue - presetSize) < 0.01 } ?? false }

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
        setAccessibilityLabel(name); toolTip = name
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func choose() { slider?.performValueChange(presetSize, continuous: false) }
    override func isAccessibilitySelected() -> Bool { isSelectedPreset }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 1, dy: 1)
        let outline = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        if isSelectedPreset {
            NSColor.controlAccentColor.withAlphaComponent(0.20).setFill(); outline.fill()
            NSColor.controlAccentColor.setStroke(); outline.lineWidth = 2
        } else {
            if isHighlighted { NSColor.labelColor.withAlphaComponent(0.10).setFill(); outline.fill() }
            NSColor.separatorColor.setStroke(); outline.lineWidth = 1
        }
        outline.stroke()
        let thickness = CGFloat(presetSize)
        let line = NSRect(x: (bounds.width - BezelSizeSlider.glyphLength) / 2, y: (bounds.height - thickness) / 2, width: BezelSizeSlider.glyphLength, height: thickness)
        NSColor.labelColor.setFill()
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
    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); hoverTracking = area; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
final class BezelHoverPaletteView: NSView {
    var onHover: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); hoverTracking = area; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
