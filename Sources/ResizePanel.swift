import AppKit

enum ResizePanelMode: Int {
    case resize, crop, limit
}

enum ResizePanelLimitMode: Int, CaseIterable {
    case greatest, width, height
    var title: String {
        switch self { case .greatest: return "Longest side"; case .width: return "Width"; case .height: return "Height" }
    }
}

enum ResizePanelAnchor: Int, CaseIterable {
    case topLeft, topCenter, topRight, middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .center: return "Center"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }

    /// Normalized coordinates with the origin at the top left.
    var point: CGPoint {
        CGPoint(x: CGFloat(rawValue % 3) / 2, y: CGFloat(rawValue / 3) / 2)
    }
}

enum ResizePanelValidation {
    // UI admission limits, deliberately independent of the document model.
    static let maximumDimension: CGFloat = 16_384
    static let maximumPixelCount: CGFloat = 32_000_000

    enum Failure: LocalizedError, Equatable {
        case dimension, pixelCount

        var errorDescription: String? {
            switch self {
            case .dimension:
                return "Enter whole pixel dimensions from 1 to 16,384."
            case .pixelCount:
                return "Choose a size with no more than 32 million pixels."
            }
        }
    }

    /// The one rounding rule for a stored or shown pixel size: to the nearest whole pixel, halves up, never below 1
    /// (the same rule as `SketchDocument.wholePixels`, which the app-safety suite checks agrees).
    static func wholePixel(_ value: CGFloat) -> CGFloat { value.isFinite ? max(1, (value + 0.5).rounded(.down)) : 1 }

    static func isValidDimension(_ value: CGFloat) -> Bool {
        value.isFinite && value >= 1 && value <= maximumDimension && value.rounded() == value
    }

    static func dimension(from text: String) throws -> CGFloat {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let integer = Int(text), isValidDimension(CGFloat(integer)) else {
            throw Failure.dimension
        }
        return CGFloat(integer)
    }

    static func validate(_ size: CGSize) throws -> CGSize {
        guard isValidDimension(size.width), isValidDimension(size.height) else {
            throw Failure.dimension
        }
        guard size.width * size.height <= maximumPixelCount else { throw Failure.pixelCount }
        return size
    }

    static func size(width: String, height: String) throws -> CGSize {
        try validate(CGSize(width: dimension(from: width), height: dimension(from: height)))
    }

    static func text(for value: CGFloat) -> String {
        // Never convert nonfinite or unbounded floating-point input to Int.
        if isValidDimension(value) { return String(Int(value)) }
        return String(Double(value))
    }

    /// What a dimension field shows for a stored size. Whole pixels, rounded half up like `wholePixel` (1516.5 reads 1517,
    /// 1516.4 reads 1516). Only the shown text is rounded: `ResizePanelState` keeps the source size at full precision for
    /// the proportional math, and typed text still goes through `dimension(from:)` unchanged, so a typed 1516 stays 1516.
    static func displayText(for value: CGFloat) -> String {
        if value.isFinite, abs(value) < 1e15 { return String(Int(value.rounded())) }
        return text(for: value)
    }
}

struct ResizePanelSubmission: Equatable {
    let size: CGSize
    let isCrop: Bool
    let anchor: CGPoint
    var constrainProportions = true
}

/// What a Resize typed in the picture's own pixels does to the picture: scale it to `scaleTo` (nil: it already is that size), keep `crop`
/// of the scaled result (nil: all of it), and end at `size`.
struct ResizePicturePlan: Equatable {
    var scaleTo: CGSize?
    var crop: CGRect?
    var size: CGSize
}

enum ResizePanelGeometry {
    /// Original Scale first fits proportionally; an unconstrained request then
    /// expands/crops the centered viewport to the requested output dimensions.
    /// `displayed` is the whole-pixel size the sheet's fields were seeded with when that is not the output size (the title shows the
    /// picture's own pixel size while Original size is ticked). When `atPictureSize` the title is the picture itself (Original size ticked,
    /// or a snap shown at its own size): the request is then for that many pixels of the picture, and `picture` says how to get them
    /// (scale the picture, then crop). `rect` and `output` stay the answer in the output's terms for a request on the shown size.
    static func preview(source: CGSize, output: CGSize, displayed: CGSize? = nil, atPictureSize: Bool = false, request: ResizePanelSubmission) throws -> (rect: CGRect?, output: CGSize, picture: ResizePicturePlan?) {
        guard source.width.isFinite, source.height.isFinite, output.width.isFinite, output.height.isFinite,
              source.width > 0, source.height > 0, output.width > 0, output.height > 0 else { throw ResizePanelValidation.Failure.dimension }
        let typed = try ResizePanelValidation.validate(request.size)
        var target = typed
        var picture: ResizePicturePlan?
        if let displayed, displayed != output {
            guard displayed.width.isFinite, displayed.height.isFinite, displayed.width > 0, displayed.height > 0 else { throw ResizePanelValidation.Failure.dimension }
            target = try ResizePanelValidation.validate(CGSize(width: ResizePanelValidation.wholePixel(target.width * output.width / displayed.width),
                                                               height: ResizePanelValidation.wholePixel(target.height * output.height / displayed.height)))
        }
        if let displayed, atPictureSize {
            guard displayed.width.isFinite, displayed.height.isFinite, displayed.width > 0, displayed.height > 0 else { throw ResizePanelValidation.Failure.dimension }
            picture = try picturePlan(source: source, displayed: displayed, typed: typed, request: request)
        }
        if request.isCrop {
            let size = CGSize(width: target.width * source.width / output.width, height: target.height * source.height / output.height)
            return (CGRect(x: (source.width-size.width)*request.anchor.x, y: (source.height-size.height)*request.anchor.y,
                           width: size.width, height: size.height), target, picture)
        }
        let factor = min(target.width / output.width, target.height / output.height)
        var fitted = CGSize(width: ResizePanelValidation.wholePixel(output.width * factor), height: ResizePanelValidation.wholePixel(output.height * factor))
        // R5-004: the same rule as for a snap's picture: a partner that is the rounded proportion is the size as typed (no pixel short).
        if request.constrainProportions, partnerIsRoundedProportion(of: output, typed: target) { fitted = target }
        if request.constrainProportions { return (nil, try ResizePanelValidation.validate(fitted), picture) }
        let size = CGSize(width: target.width * source.width / (output.width * factor),
                          height: target.height * source.height / (output.height * factor))
        return (CGRect(x: (source.width-size.width)/2, y: (source.height-size.height)/2, width: size.width, height: size.height), target, picture)
    }

    /// Whether a proportional request is the base size's proportion with one side rounded: fitting by the smaller ratio would land a pixel
    /// short on the side that was typed, so such a request is used as typed.
    private static func partnerIsRoundedProportion(of base: CGSize, typed: CGSize) -> Bool {
        let heightOff = abs(base.height * typed.width / base.width - typed.height)
        let widthOff = abs(base.width * typed.height / base.height - typed.width)
        return (heightOff <= 1 && widthOff <= 1) || min(heightOff, widthOff) <= 0.5 + 1e-6
    }

    private static func picturePlan(source: CGSize, displayed: CGSize, typed: CGSize, request: ResizePanelSubmission) throws -> ResizePicturePlan {
        if request.isCrop {
            let crop = CGRect(x: (displayed.width - typed.width) * request.anchor.x, y: (displayed.height - typed.height) * request.anchor.y,
                              width: typed.width, height: typed.height)
            return ResizePicturePlan(scaleTo: displayed == source ? nil : displayed, crop: crop, size: typed)
        }
        let factor = min(typed.width / displayed.width, typed.height / displayed.height)
        var scaled = try ResizePanelValidation.validate(CGSize(width: ResizePanelValidation.wholePixel(displayed.width * factor),
                                                               height: ResizePanelValidation.wholePixel(displayed.height * factor)))
        // A proportional size typed on a shown size that was itself rounded to whole pixels (996 × 700 for a 2560 × 1800 snap) comes back
        // a pixel short on the other side; the picture is then exactly what was typed, so the title reads the number that was entered (R3-001).
        // Fitting by the smaller ratio also lands a pixel short on the side that was typed when the partner rounded down by half a pixel
        // (a Limit of 1400 on 1981 × 953 pairs 673, and 1981 × 673 fits at 1399): a request whose partner is the rounded proportion on
        // either side is the picture exactly as typed.
        if request.constrainProportions {
            if partnerIsRoundedProportion(of: displayed, typed: typed) { scaled = typed }
            // R4-002: one side the picture's own and the partner its rounded proportion (2560 × 1799 of a 2560 × 1800 snap) is the
            // picture itself, not a resample a pixel short.
            if (typed.width == source.width && abs(typed.height - source.height) <= 1)
                || (typed.height == source.height && abs(typed.width - source.width) <= 1) { scaled = source }
        }
        let scaleTo = scaled == source ? nil : scaled
        if request.constrainProportions { return ResizePicturePlan(scaleTo: scaleTo, crop: nil, size: scaled) }
        return ResizePicturePlan(scaleTo: scaleTo,
            crop: CGRect(x: (scaled.width - typed.width) / 2, y: (scaled.height - typed.height) / 2, width: typed.width, height: typed.height),
            size: typed)
    }
}

/// Pure edit state used by the sheet and by tests without AppKit controls.
struct ResizePanelState {
    enum Dimension { case width, height }

    private(set) var mode: ResizePanelMode = .resize
    private(set) var preserveRatio: Bool
    private(set) var widthText: String
    private(set) var heightText: String
    var anchor: ResizePanelAnchor = .center
    var limitMode: ResizePanelLimitMode = .greatest
    var limitText: String { didSet { untouched.remove(.limit) } }
    private let originalSize: CGSize
    private let originalRatio: CGFloat?
    private var lastEdited: Dimension = .width
    /// Fields still holding the untouched formatting of the source size; only these are shown rounded to whole pixels.
    private enum Field { case width, height, limit }
    private var untouched: Set<Field> = [.width, .height, .limit]

    init(size: CGSize) {
        originalSize = size
        limitText = ResizePanelValidation.text(for: max(size.width, size.height))
        widthText = ResizePanelValidation.text(for: size.width)
        heightText = ResizePanelValidation.text(for: size.height)
        originalRatio = (try? ResizePanelValidation.validate(size)) == nil ? nil : size.width / size.height
        preserveRatio = originalRatio != nil
    }

    var locksProportions: Bool { mode == .resize && preserveRatio }

    var displayWidthText: String { untouched.contains(.width) ? ResizePanelValidation.displayText(for: originalSize.width) : widthText }
    var displayHeightText: String { untouched.contains(.height) ? ResizePanelValidation.displayText(for: originalSize.height) : heightText }
    var displayLimitText: String {
        untouched.contains(.limit) ? ResizePanelValidation.displayText(for: max(originalSize.width, originalSize.height)) : limitText
    }

    /// What submission reads. A field still holding the untouched source size submits exactly what it displays (whole
    /// pixels), so the panel never rejects a value it showed. Typed text is passed through unchanged and still goes
    /// through `dimension(from:)`, so a typed `12.5` or `abc` keeps failing.
    /// Proportional lock: the partner of an edited field is recomputed from the exact original ratio (`originalRatio`,
    /// which only exists for a whole-pixel source), so an untouched partner never feeds that math. A fractional source
    /// has no ratio, the lock stays off, and an untouched partner submits its displayed (rounded) value.
    private var submittedWidthText: String { displayWidthText }
    private var submittedHeightText: String { displayHeightText }
    private var submittedLimitText: String { displayLimitText }

    /// The same sheet settings over a picture that now has `size`: what Apply leaves behind, so the fields show the new title size.
    func rebased(to size: CGSize) -> ResizePanelState {
        var next = ResizePanelState(size: size)
        next.mode = mode; next.anchor = anchor; next.limitMode = limitMode
        next.preserveRatio = preserveRatio && next.originalRatio != nil
        return next
    }

    mutating func setMode(_ mode: ResizePanelMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        synchronizeProportions()
    }

    mutating func setPreserveRatio(_ preserve: Bool) {
        preserveRatio = preserve && originalRatio != nil
        synchronizeProportions()
    }

    mutating func edit(_ dimension: Dimension, text: String) {
        lastEdited = dimension
        untouched.remove(dimension == .width ? .width : .height)
        switch dimension {
        case .width: widthText = text
        case .height: heightText = text
        }
        synchronizeProportions()
    }

    mutating func selectPreset(_ preset: ResizePreset) {
        switch preset.mode { case .scale: mode = .resize; case .crop: mode = .crop; case .limit: mode = .limit }
        widthText = String(preset.width); heightText = String(preset.height)
        untouched = []
        preserveRatio = preset.proportions && originalRatio != nil
        anchor = ResizePanelAnchor(rawValue: preset.anchor) ?? .center
        limitMode = ResizePanelLimitMode(rawValue: preset.limitMode.rawValue) ?? .greatest
        limitText = String(preset.limitSize)
    }

    func preset(id: String = UUID().uuidString, name: String, format: Int = 0) throws -> ResizePreset {
        let dimensions = try ResizePanelValidation.size(width: submittedWidthText, height: submittedHeightText)
        let resizeMode: PresetResizeMode
        switch mode { case .resize: resizeMode = .scale; case .crop: resizeMode = .crop; case .limit: resizeMode = .limit }
        let preset = ResizePreset(id: id, name: name, width: Int(dimensions.width), height: Int(dimensions.height),
            mode: resizeMode, format: format, anchor: anchor.rawValue, proportions: preserveRatio,
            limitSize: Int(try ResizePanelValidation.dimension(from: submittedLimitText)),
            limitMode: ResizeLimitMode(rawValue: limitMode.rawValue) ?? .greatest)
        try preset.validate()
        return preset
    }

    func submission() throws -> ResizePanelSubmission {
        if mode == .limit {
            let limit = try ResizePanelValidation.dimension(from: submittedLimitText)
            let reference: CGFloat
            switch limitMode { case .greatest: reference = max(originalSize.width, originalSize.height)
            case .width: reference = originalSize.width; case .height: reference = originalSize.height }
            guard reference.isFinite, reference > 0 else { throw ResizePanelValidation.Failure.dimension }
            let factor = limit / reference
            let size = CGSize(width: ResizePanelValidation.wholePixel(originalSize.width * factor), height: ResizePanelValidation.wholePixel(originalSize.height * factor))
            return ResizePanelSubmission(size: try ResizePanelValidation.validate(size), isCrop: false, anchor: anchor.point)
        }
        return ResizePanelSubmission(size: try ResizePanelValidation.size(width: submittedWidthText, height: submittedHeightText),
                              isCrop: mode == .crop, anchor: anchor.point, constrainProportions: preserveRatio)
    }

    private mutating func synchronizeProportions() {
        guard locksProportions, let ratio = originalRatio else { return }
        switch lastEdited {
        case .width:
            guard let width = try? ResizePanelValidation.dimension(from: widthText) else { return }
            heightText = pixelText(width / ratio); untouched.remove(.height)
        case .height:
            guard let height = try? ResizePanelValidation.dimension(from: heightText) else { return }
            widthText = pixelText(height * ratio); untouched.remove(.width)
        }
    }

    private func pixelText(_ value: CGFloat) -> String {
        // Round the paired dimension once against the original ratio, avoiding
        // cumulative drift. A subpixel result occupies at least one pixel.
        let rounded = ResizePanelValidation.wholePixel(value)
        if rounded.isFinite && rounded <= ResizePanelValidation.maximumDimension {
            return String(Int(rounded))
        }
        // Keep an oversized result invalid; never silently clamp the ratio.
        return String(Double(rounded))
    }
}

/// Callback lifetime is also testable without constructing a window.
@MainActor
final class ResizePanelSession {
    var state: ResizePanelState
    private(set) var isFinished = false
    private var onApply: ((CGSize, Bool, CGPoint) -> Void)?
    private var onPreview: ((ResizePanelSubmission) throws -> Void)?
    private var onFinish: ((Bool) -> Void)?
    private var onCommit: (() -> CGSize)?
    private var isDelivering = false
    private(set) var lastPreview: ResizePanelSubmission?
    var onCompletion: ((Bool) -> Void)?

    init(size: CGSize, onApply: @escaping (CGSize, Bool, CGPoint) -> Void) {
        state = ResizePanelState(size: size)
        self.onApply = onApply
    }

    init(size: CGSize, onPreview: @escaping (ResizePanelSubmission) throws -> Void,
         onFinish: @escaping (Bool) -> Void, onCommit: (() -> CGSize)? = nil) {
        state = ResizePanelState(size: size)
        self.onPreview = onPreview
        self.onFinish = onFinish
        self.onCommit = onCommit
    }

    /// Apply: what the sheet shows becomes a finished edit (one Undo step) and the sheet stays open on the new picture. Cancel afterwards
    /// only takes back what is typed from here on; OK closes with the latest size.
    @discardableResult
    func commit() throws -> Bool {
        guard !isFinished, !isDelivering, let commit = onCommit else { return false }
        guard try preview() else { return false }
        let size = commit()
        state = state.rebased(to: size)
        lastPreview = nil
        return true
    }

    @discardableResult
    func preview(force: Bool = false) throws -> Bool {
        guard !isFinished, !isDelivering, let callback = onPreview else { return false }
        let submission = try state.submission()
        guard force || submission != lastPreview else { return true }
        isDelivering = true
        defer { isDelivering = false }
        try callback(submission)
        guard !isFinished else { return false }
        lastPreview = submission
        return true
    }

    @discardableResult
    func apply(beforeDelivery: () -> Void = {}) throws -> Bool {
        guard !isFinished, !isDelivering else { return false }
        let submission = try state.submission()
        if onPreview != nil, try !preview(force: true) { return false }
        let callback = onApply
        let finish = onFinish
        let completion = onCompletion
        isFinished = true
        onApply = nil
        onPreview = nil
        onFinish = nil
        onCommit = nil
        onCompletion = nil
        beforeDelivery()
        callback?(submission.size, submission.isCrop, submission.anchor)
        finish?(false)
        completion?(false)
        return true
    }

    func cancel() {
        guard !isFinished else { return }
        let finish = onFinish
        let completion = onCompletion
        isFinished = true
        onApply = nil
        onPreview = nil
        onFinish = nil
        onCommit = nil
        onCompletion = nil
        finish?(true)
        completion?(true)
    }
}

/// The crop anchor: nine cells laid out like the picture they stand for, the chosen one marking the part of the image that is kept.
/// One tab stop; the arrow keys move the choice, the pointer picks a cell, and VoiceOver sees a radio group of nine named cells.
@MainActor
final class ResizeAnchorGrid: NSView, ChromeFillable {
    static let cellSize = NSSize(width: 56, height: 40)
    static let spacing: CGFloat = DesignTokens.Space.s2
    var anchor: ResizePanelAnchor = .center { didSet { if anchor != oldValue { needsDisplay = true; invalidateAccessibility() } } }
    var onChange: ((ResizePanelAnchor) -> Void)?
    var accessibility: ChromeAccessibility = .live { didSet { needsDisplay = true } }
    private(set) var hovered: ResizePanelAnchor?
    private(set) var pressed: ResizePanelAnchor?
    private var hoverArea: NSTrackingArea?
    private var cellElements: [ResizeAnchorCellElement] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Self.intrinsic))
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Crop anchor")
        cellElements = ResizePanelAnchor.allCases.map { ResizeAnchorCellElement(grid: self, anchor: $0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static var intrinsic: NSSize {
        NSSize(width: 3 * cellSize.width + 2 * spacing, height: 3 * cellSize.height + 2 * spacing)
    }
    override var intrinsicContentSize: NSSize { Self.intrinsic }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func frame(of cell: ResizePanelAnchor) -> NSRect {
        let column = cell.rawValue % 3, row = cell.rawValue / 3
        return NSRect(x: CGFloat(column) * (Self.cellSize.width + Self.spacing), y: CGFloat(row) * (Self.cellSize.height + Self.spacing),
                      width: Self.cellSize.width, height: Self.cellSize.height)
    }
    func cell(at point: NSPoint) -> ResizePanelAnchor? { ResizePanelAnchor.allCases.first { frame(of: $0).contains(point) } }

    func select(_ cell: ResizePanelAnchor) {
        guard cell != anchor else { return }
        anchor = cell
        onChange?(cell)
    }

    /// What a cell draws: the shared command state (rest, hover, pressed, selected) resolved by `StateStyles.command`, so a cell reads like
    /// every other button on a glass plate and follows Increase Contrast and Differentiate Without Color.
    func style(of cell: ResizePanelAnchor) -> StateStyle {
        StateStyles.command(StatePlate.controlState(hovered: cell == hovered, pressed: cell == pressed, selected: cell == anchor, disabled: false),
                            primary: false, focused: false, highContrast: accessibility.increaseContrast,
                            differentiate: accessibility.differentiateWithoutColor, selected: cell == anchor, appearance: effectiveAppearance)
    }

    override func draw(_ dirtyRect: NSRect) {
        for cell in ResizePanelAnchor.allCases {
            let rect = frame(of: cell).insetBy(dx: 1, dy: 1)
            let style = style(of: cell)
            let selected = cell == anchor
            let path = NSBezierPath(roundedRect: rect, xRadius: StatePlate.radius, yRadius: StatePlate.radius)
            // A resting cell keeps a hairline so the nine read as cells on the plate; the selected one is the accent fill and border.
            if let fill = style.fill { fill.setFill(); path.fill() }
            if let border = style.border, style.borderWidth > 0 { border.setStroke(); path.lineWidth = style.borderWidth; path.stroke() }
            else { DesignTokens.Palette.separator.setStroke(); path.lineWidth = 1; path.stroke() }
            // The dot is the kept part; a selected cell carries a ring as well, so the choice never rests on colour alone.
            let dot = NSRect(x: rect.midX - 6, y: rect.midY - 6, width: 12, height: 12)
            style.content.setFill()
            if selected {
                NSBezierPath(ovalIn: dot).fill()
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -4, dy: -4)); ring.lineWidth = 1.5; style.content.setStroke(); ring.stroke()
            } else {
                style.content.withAlphaComponent(0.6).setFill()
                NSBezierPath(ovalIn: dot.insetBy(dx: 3, dy: 3)).fill()
            }
        }
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSColor.black.setFill()
        let rect = frame(of: anchor)
        NSBezierPath(roundedRect: rect, xRadius: DesignTokens.Radius.md, yRadius: DesignTokens.Radius.md).fill()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let cell = cell(at: convert(event.locationInWindow, from: nil)) { setPressed(cell); select(cell) }
    }
    override func mouseUp(with event: NSEvent) { setPressed(nil) }
    /// Press and hover entry points; the pointer events and the tests both go through them.
    func setPressed(_ cell: ResizePanelAnchor?) { if cell != pressed { pressed = cell; needsDisplay = true } }
    func setHovered(_ cell: ResizePanelAnchor?) { if cell != hovered { hovered = cell; needsDisplay = true } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseMoved(with event: NSEvent) {
        setHovered(cell(at: convert(event.locationInWindow, from: nil)))
    }
    override func mouseExited(with event: NSEvent) { setHovered(nil); setPressed(nil) }
    override func keyDown(with event: NSEvent) {
        let column = anchor.rawValue % 3, row = anchor.rawValue / 3
        let moved: (Int, Int)?
        switch event.keyCode {
        case 123: moved = (max(0, column - 1), row)
        case 124: moved = (min(2, column + 1), row)
        case 126: moved = (column, max(0, row - 1))
        case 125: moved = (column, min(2, row + 1))
        default: moved = nil
        }
        if let (c, r) = moved, let next = ResizePanelAnchor(rawValue: r * 3 + c) { select(next) } else { super.keyDown(with: event) }
    }

    private func invalidateAccessibility() {
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
    override func accessibilityValue() -> Any? { anchor.title }
    override func accessibilityChildren() -> [Any]? { cellElements }
    override func accessibilitySelectedChildren() -> [Any]? { cellElements.filter { $0.anchor == anchor } }
}

/// One cell of the anchor grid as VoiceOver sees it: a named radio button that says whether it is the part kept, and presses to choose it.
final class ResizeAnchorCellElement: NSAccessibilityElement {
    let anchor: ResizePanelAnchor
    private weak var grid: ResizeAnchorGrid?
    @MainActor init(grid: ResizeAnchorGrid, anchor: ResizePanelAnchor) {
        self.grid = grid; self.anchor = anchor
        super.init()
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(anchor.title)
        setAccessibilityParent(grid)
    }
    override func accessibilityFrameInParentSpace() -> NSRect { MainActor.assumeIsolated { grid?.frame(of: anchor) ?? .zero } }
    override func accessibilityValue() -> Any? { MainActor.assumeIsolated { grid?.anchor == anchor ? 1 : 0 } }
    override func isAccessibilitySelected() -> Bool { MainActor.assumeIsolated { grid?.anchor == anchor } }
    override func accessibilityPerformPress() -> Bool { MainActor.assumeIsolated { grid?.select(anchor); return grid != nil } }
}

@MainActor
final class ResizePanel: NSObject, NSTextFieldDelegate, NSWindowDelegate, NSMenuDelegate {
    private let session: ResizePanelSession
    private var panel: NSPanel?
    private var widthField: NSTextField?
    private var heightField: NSTextField?
    private var ratioButton: GlassChoiceButton?
    private var ratioPlate: GlassSurfaceView?
    private var modeControl: GlassChoiceGroup?
    private var anchorGrid: ResizeAnchorGrid?
    private var anchorRow: NSStackView?
    private var dimensionRow: NSStackView?
    private var contentStack: NSStackView?
    private var presetDisclosure: GlassChoiceButton?
    private var presetManagement: NSStackView?
    private var errorLabel: NSTextField?
    private var helpLabel: NSTextField?
    private var limitRow: NSStackView?
    private var limitField: NSTextField?
    private var limitControl: GlassChoiceGroup?
    private var previewTimer: Timer?
    private let presets: ResizePresetStore
    private var selectedPresetID: String?
    /// The preset choice's model: its menu is what the preset panel lists and selecting an item in it is what applies a preset. It is never
    /// put on screen; the glass face and the choice panel stand in for it.
    private var presetPopup: NSPopUpButton?
    private var presetFace: GlassChoiceButton?
    private var presetChoices: MenuChoicePanel?
    private var presetName: NSTextField?
    private var savePresetButton: GlassChoiceButton?
    private var removePresetButton: GlassChoiceButton?
    /// The glass plates and the controls on them that follow the display options (Reduce Transparency, Increase Contrast...).
    private var plates: [GlassSurfaceView] = []
    private var fillables: [ChromeFillable] = []
    private var displayObservation: DisplayOptions.Observation?

    init(size: CGSize, onApply: @escaping (CGSize, Bool, CGPoint) -> Void) {
        session = ResizePanelSession(size: size, onApply: onApply)
        presets = ResizePresetStore()
        super.init()
    }

    init(session: ResizePanelSession, presets: ResizePresetStore = ResizePresetStore()) {
        self.session = session
        self.presets = presets
        super.init()
    }

    init(size: CGSize, onPreview: @escaping (ResizePanelSubmission) throws -> Void,
         onFinish: @escaping (Bool) -> Void) {
        session = ResizePanelSession(size: size, onPreview: onPreview, onFinish: onFinish)
        presets = ResizePresetStore()
        super.init()
    }

    func show(attachedTo parent: NSWindow) {
        guard panel == nil, !session.isFinished else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.sheetWidth, height: 520),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Resize or Crop"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        self.panel = panel
        session.onCompletion = { [weak self] cancelled in
            self?.persistSelectedPreset()
            self?.previewTimer?.invalidate(); self?.previewTimer = nil
            self?.endSheet(cancelled ? .cancel : .OK)
        }
        buildContent(in: panel)
        // Retain the controller until sheet completion, even for a temporary caller.
        parent.beginSheet(panel) { [self] _ in
            session.cancel()
            self.panel = nil
            panel.orderOut(nil)
        }
        panel.makeFirstResponder(widthField)
    }

    /// The sheet reads top to bottom as the job is done: what to do (Resize, Crop or Limit), how big, then the optional extras. Presets sit
    /// one row below with their management folded away, so the dimensions are the first thing under the mode choice. Every choice is a glass
    /// button; each related group is one plate, so the plate is the only glass in the group.
    private func buildContent(in panel: NSPanel) {
        let content = NSView()
        panel.contentView = content
        let options = ChromeAccessibility.live
        let heading = label("Resize or Crop", style: .title)
        let mode = GlassChoiceGroup(titles: ["Resize", "Crop", "Limit"], selectedIndex: session.state.mode.rawValue, accessibilityLabel: "Size operation",
                                    identifier: "ResizeMode", accessibility: options)
        mode.target = self; mode.action = #selector(changeMode(_:))
        for button in mode.buttons { button.minimumWidth = 150 }
        fillables.append(mode)
        modeControl = mode

        let help = NSTextField(wrappingLabelWithString: "")
        help.font = DesignTokens.Typography.font(.body)
        help.textColor = DesignTokens.Palette.Text.secondary
        helpLabel = help

        // Dimensions: Width and Height side by side, so the two fields cost one row.
        let width = dimensionField(value: session.state.displayWidthText, name: "Width in pixels")
        let height = dimensionField(value: session.state.displayHeightText, name: "Height in pixels")
        widthField = width; heightField = height
        let dimensions = NSStackView(views: [label("Width"), width, label("Height"), height, label("pixels")])
        dimensions.orientation = .horizontal; dimensions.alignment = .firstBaseline
        dimensions.spacing = DesignTokens.Space.s3
        dimensions.setCustomSpacing(DesignTokens.Space.s5, after: width)
        dimensions.setCustomSpacing(DesignTokens.Space.s2, after: height)
        dimensionRow = dimensions
        let ratio = choiceButton("Lock proportions", kind: .toggle, indicator: .checkbox, layout: .row, identifier: "ResizeLockProportions", action: #selector(changeRatio(_:)))
        ratioButton = ratio
        let ratioGroup = plate([ratio], identifier: "ResizeLockPlate", label: "Lock proportions")
        ratioPlate = ratioGroup

        // Limit: what it limits, then one size.
        let limit = dimensionField(value: session.state.displayLimitText, name: "Size limit in pixels")
        limitField = limit
        let limitChoice = GlassChoiceGroup(titles: ResizePanelLimitMode.allCases.map(\.title), selectedIndex: session.state.limitMode.rawValue,
                                           accessibilityLabel: "Limit by", identifier: "ResizeLimitBy", accessibility: options)
        limitChoice.target = self; limitChoice.action = #selector(changeLimit(_:))
        fillables.append(limitChoice)
        limitControl = limitChoice
        let limitBy = NSStackView(views: [label("Limit by"), limitChoice])
        limitBy.orientation = .horizontal; limitBy.alignment = .centerY; limitBy.spacing = DesignTokens.Space.s3
        let limitSize = NSStackView(views: [label("Limit"), limit, label("pixels")])
        limitSize.orientation = .horizontal; limitSize.alignment = .firstBaseline; limitSize.spacing = DesignTokens.Space.s3
        let limitControls = NSStackView(views: [limitBy, limitSize])
        limitControls.orientation = .vertical; limitControls.alignment = .leading; limitControls.spacing = DesignTokens.Space.s3
        limitRow = limitControls

        // Crop: the 3 x 3 grid is the picture; the cell picked is the part of the image that stays. The grid sits on one plate.
        let grid = ResizeAnchorGrid()
        grid.onChange = { [weak self] anchor in self?.chooseAnchor(anchor) }
        grid.accessibility = options
        fillables.append(grid)
        anchorGrid = grid
        let gridPlate = plate([grid], identifier: "ResizeAnchorPlate", label: "Crop anchor", axis: .vertical)
        let anchorCaption = NSTextField(wrappingLabelWithString: "The marked cell is the part of the image that stays.")
        anchorCaption.font = DesignTokens.Typography.font(.body)
        anchorCaption.textColor = DesignTokens.Palette.Text.secondary
        anchorCaption.preferredMaxLayoutWidth = 300
        let anchor = NSStackView(views: [gridPlate, anchorCaption])
        anchor.orientation = .horizontal; anchor.alignment = .centerY; anchor.spacing = DesignTokens.Space.s4
        anchorRow = anchor

        // Presets: the choice is one glass face over a pop-up model; naming, saving and removing are behind the disclosure.
        let presetChoice = NSPopUpButton(frame: .zero, pullsDown: false)
        presetChoice.target = self; presetChoice.action = #selector(selectPreset(_:))
        presetChoice.setAccessibilityLabel("Size preset")
        presetChoice.menu?.delegate = self
        presetPopup = presetChoice
        let face = choiceButton("Custom size", kind: .submenu, indicator: .chevron, layout: .row, identifier: "ResizePresetFace", action: #selector(openPresetChoices(_:)))
        face.setAccessibilityLabel("Size preset")
        face.minimumWidth = Self.presetFaceWidth
        face.keyHandler = { [weak self] event in
            guard event.keyCode == 125 || event.keyCode == 126 else { return false }
            self?.showPresetChoices(keyboard: true)
            return true
        }
        presetFace = face
        let panelOfChoices = MenuChoicePanel(menu: presetChoice.menu ?? NSMenu(), identifier: "ResizePreset", accessibilityLabel: "Size preset",
                                             kind: { _ in .option }, popUp: presetChoice, minimumWidth: Self.presetFaceWidth)
        presetChoices = panelOfChoices
        let facePlate = plate([face], identifier: "ResizePresetPlate", label: "Size preset")
        let disclosure = choiceButton("Manage", kind: .toggle, indicator: .chevron, layout: .row, identifier: "ResizeManagePresets", action: #selector(togglePresetManagement(_:)))
        disclosure.setAccessibilityLabel("Manage presets")
        disclosure.setAccessibilityExpanded(false)
        presetDisclosure = disclosure
        let disclosurePlate = plate([disclosure], identifier: "ResizeManagePlate", label: "Manage presets")
        let presetLine = NSStackView(views: [label("Preset"), facePlate, disclosurePlate])
        presetLine.orientation = .horizontal; presetLine.alignment = .centerY; presetLine.spacing = DesignTokens.Space.s3
        presetLine.setCustomSpacing(DesignTokens.Space.s5, after: facePlate)
        let presetTitle = dimensionField(value: "New Size", name: "Preset name")
        presetName = presetTitle
        let addPreset = choiceButton("Add Preset", kind: .command, identifier: "ResizeAddPreset", action: #selector(addPreset(_:)))
        let savePreset = choiceButton("Save Preset", kind: .command, identifier: "ResizeSavePreset", action: #selector(savePreset(_:)))
        let removePreset = choiceButton("Remove", kind: .command, identifier: "ResizeRemovePreset", action: #selector(removePreset(_:)))
        savePresetButton = savePreset; removePresetButton = removePreset
        let presetActionsPlate = plate([addPreset, savePreset, removePreset], identifier: "ResizePresetActionsPlate", label: "Preset actions")
        presetActionsPlate.setContentHuggingPriority(NSLayoutConstraint.Priority(760), for: .horizontal)
        presetActionsPlate.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(760), for: .horizontal)
        let presetActions = NSStackView(views: [presetTitle, presetActionsPlate])
        presetActions.orientation = .horizontal; presetActions.alignment = .centerY; presetActions.spacing = DesignTokens.Space.s3
        presetManagement = presetActions
        reloadPresets()

        let error = NSTextField(wrappingLabelWithString: "")
        error.font = DesignTokens.Typography.font(.body)
        error.textColor = DesignTokens.Palette.feedbackError
        error.setAccessibilityRole(.staticText)  // the message is the label: VoiceOver reads "Error: ...", never a fixed caption over it
        errorLabel = error

        // One action plate on the trailing edge in the standard order: Cancel, Apply, OK (the default and the only tinted control).
        let cancel = choiceButton("Cancel", kind: .command, identifier: "ResizeCancel", action: #selector(cancelSheet(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let apply = choiceButton("Apply", kind: .command, identifier: "ResizeApply", action: #selector(previewSheet(_:)))
        let ok = choiceButton("OK", kind: .command, identifier: "ResizeOK", action: #selector(applySheet(_:)))
        ok.isPrimary = true
        ok.keyEquivalent = "\r"
        for button in [cancel, apply, ok] { button.minimumWidth = 96 }
        panel.defaultButtonCell = ok.cell as? NSButtonCell
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let sheetActions = plate([cancel, apply, ok], identifier: "ResizeSheetActionsPlate", label: "Resize actions")
        let buttons = NSStackView(views: [spacer, sheetActions])
        buttons.orientation = .horizontal; buttons.alignment = .centerY; buttons.spacing = DesignTokens.Space.s4

        let separator = NSBox(); separator.boxType = .separator
        let stack = NSStackView(views: [heading, mode, help, dimensions, ratioGroup, limitControls, anchor, separator, presetLine, presetActions, error, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DesignTokens.Space.s4
        stack.setCustomSpacing(DesignTokens.Space.s2, after: dimensions)
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentStack = stack
        content.addSubview(stack)
        let inset = DesignTokens.Space.s5 + DesignTokens.Space.s1
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -inset),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            error.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presetActions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presetTitle.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            width.widthAnchor.constraint(equalToConstant: 120), height.widthAnchor.constraint(equalToConstant: 120),
            width.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.Size.control),
            height.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.Size.control),
            limit.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.Size.control),
            limit.widthAnchor.constraint(equalToConstant: 140),
            presetTitle.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.Size.control)
        ])
        renderState()
        if presets.hasMalformedData { showError(ResizePresetError.malformedDefaults.localizedDescription) }
        // The glass choices are not in a hand-made chain: Tab follows the layout, one stop per group, and starts in Width.
        panel.autorecalculatesKeyViewLoop = true
        panel.initialFirstResponder = width
        displayObservation = DisplayOptions.observe { [weak self] options in self?.applyDisplayOptions(options.chrome) }
        fitPanelToContent()
    }

    /// The sheet is exactly as tall as what it shows: a mode with less to ask is a shorter sheet, never a sheet with a gap in it.
    private func fitPanelToContent() {
        guard let panel, let stack = contentStack else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        let inset = DesignTokens.Space.s5 + DesignTokens.Space.s1
        let size = NSSize(width: Self.sheetWidth, height: ceil(stack.fittingSize.height + 2 * inset))
        if panel.contentView?.frame.size != size { panel.setContentSize(size) }
        panel.contentView?.layoutSubtreeIfNeeded()
    }
    static let sheetWidth: CGFloat = 620
    /// The preset face and its choice panel share this width, wide enough for the longest built-in preset.
    static let presetFaceWidth: CGFloat = 300

    private func label(_ text: String, style: DesignTokens.Typography.Style = .body) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = DesignTokens.Typography.font(style)
        return label
    }

    private func dimensionField(value: String, name: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.font = DesignTokens.Typography.font(.body)
        field.delegate = self
        field.setAccessibilityLabel(name)
        return field
    }

    /// A glass choice button of the sheet, wired to this panel and following the live display options.
    private func choiceButton(_ title: String, kind: GlassChoiceButton.Kind, indicator: GlassChoiceButton.Indicator? = nil,
                              layout: GlassChoiceButton.Layout = .segment, identifier: String, action: Selector) -> GlassChoiceButton {
        let button = GlassChoiceButton(title: title, kind: kind, indicator: indicator, layout: layout)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = self; button.action = action
        button.accessibility = .live
        fillables.append(button)
        return button
    }

    /// One glass plate around a related group of controls. The plate is the only glass in the group.
    private func plate(_ views: [NSView], identifier: String, label: String, axis: NSUserInterfaceLayoutOrientation = .horizontal) -> GlassSurfaceView {
        let group = GlassChrome.plate(views, identifier: identifier, accessibility: .live, axis: axis)
        // A plate of several buttons is a named group; a plate around one control adds no level of its own.
        if views.count > 1, !(views[0] is ResizeAnchorGrid) {
            group.setAccessibilityElement(true); group.setAccessibilityLabel(label); group.setAccessibilityRole(.group)
        }
        plates.append(group)
        return group
    }

    private func applyDisplayOptions(_ options: ChromeAccessibility) {
        for plate in plates { plate.accessibility = options }
        for fillable in fillables { fillable.accessibility = options }
    }

    /// Errors say "Error:" in words, so they never rest on the red colour alone.
    private func showError(_ text: String) {
        errorLabel?.stringValue = text.hasPrefix("Error:") ? text : "Error: " + text
        errorLabel?.isHidden = false
        fitPanelToContent()
    }

    private func renderState(editing field: NSTextField? = nil) {
        modeControl?.selectedIndex = session.state.mode.rawValue
        if field !== widthField { widthField?.stringValue = session.state.displayWidthText }
        if field !== heightField { heightField?.stringValue = session.state.displayHeightText }
        let crop = session.state.mode == .crop
        let limit = session.state.mode == .limit
        if field !== limitField { limitField?.stringValue = session.state.displayLimitText }
        limitControl?.selectedIndex = session.state.limitMode.rawValue
        dimensionRow?.isHidden = limit
        limitRow?.isHidden = !limit
        ratioPlate?.isHidden = crop || limit
        ratioButton?.isChosen = session.state.preserveRatio
        anchorRow?.isHidden = !crop
        anchorGrid?.anchor = session.state.anchor
        helpLabel?.stringValue = crop ? "Choose the crop size and which part of the image to keep."
            : limit ? "Set the width, height, or longest side. Larger limits enlarge the image."
            : "Fit the image to these dimensions. Unlock proportions to add space around it without stretching."
        presetManagement?.isHidden = presetDisclosure?.isChosen != true
        errorLabel?.stringValue = ""; errorLabel?.isHidden = true
        fitPanelToContent()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === widthField { session.state.edit(.width, text: field.stringValue) }
        else if field === heightField { session.state.edit(.height, text: field.stringValue) }
        else if field === limitField { session.state.limitText = field.stringValue }
        else if field === presetName { return }
        else { return }
        renderState(editing: field)
        schedulePreview()
    }

    /// Return in a size field commits like the OK button and Escape cancels, whether or not the sheet's key equivalents are live: the field editor
    /// is where the keyboard is while someone types a size, so it answers for them (the preset name field keeps Return for its own text).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === widthField || control === heightField || control === limitField else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)): applySheet(nil); return true
        case #selector(NSResponder.cancelOperation(_:)): cancelSheet(nil); return true
        default: return false
        }
    }

    @objc private func changeMode(_ sender: GlassChoiceGroup) {
        guard let mode = ResizePanelMode(rawValue: sender.selectedIndex) else { return }
        panel?.makeFirstResponder(nil)
        session.state.setMode(mode)
        renderState()
        panel?.contentView?.layoutSubtreeIfNeeded()
        panel?.display()
        schedulePreview()
    }

    @objc private func changeRatio(_ sender: GlassChoiceButton) {
        panel?.makeFirstResponder(nil)
        session.state.setPreserveRatio(sender.isChosen)
        renderState()
        schedulePreview()
    }

    private func chooseAnchor(_ anchor: ResizePanelAnchor) {
        panel?.makeFirstResponder(anchorGrid)
        session.state.anchor = anchor
        schedulePreview()
    }

    @objc private func togglePresetManagement(_ sender: GlassChoiceButton) {
        setPresetManagementShown(sender.isChosen)
    }
    /// Test seam and keyboard path: opens or folds the preset management row.
    func setPresetManagementShown(_ shown: Bool) {
        presetDisclosure?.isChosen = shown
        presetDisclosure?.setAccessibilityExpanded(shown)
        presetManagement?.isHidden = !shown
        fitPanelToContent()
    }

    @objc private func changeLimit(_ sender: GlassChoiceGroup) {
        guard let mode = ResizePanelLimitMode(rawValue: sender.selectedIndex) else { return }
        session.state.limitMode = mode
        schedulePreview()
    }

    private func schedulePreview() {
        previewTimer?.invalidate()
        guard !session.isFinished else { return }
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.previewTimer = nil
                self.persistSelectedPreset()
                do { _ = try self.session.preview() }
                catch { self.showError(error.localizedDescription) }
            }
        }
        previewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
    }

    private func reloadPresets() {
        guard let popup = presetPopup else { return }
        popup.removeAllItems(); popup.addItem(withTitle: "Custom size")
        for preset in presets.presets {
            popup.addItem(withTitle: preset.name); popup.lastItem?.representedObject = preset.id
        }
        if let id = selectedPresetID, let item = popup.itemArray.first(where: { ($0.representedObject as? String) == id }) { popup.select(item) }
        else { popup.selectItem(at: 0) }
        markChosenPreset()
        let current = popup.titleOfSelectedItem ?? "Custom size"
        presetFace?.title = current
        presetFace?.setAccessibilityHelp("Current preset: \(current). Opens the list of size presets.")
        let selected = presets.presets.first(where: { $0.id == selectedPresetID })
        presetName?.stringValue = selected?.name ?? "New Size"
        presetName?.isEnabled = selected == nil || selected?.editable == true
        savePresetButton?.isEnabled = selected?.editable == true && !presets.hasMalformedData
        removePresetButton?.isEnabled = selected?.editable == true && !presets.hasMalformedData
    }

    /// The pop-up's checked item is the chosen row of the preset panel.
    private func markChosenPreset() {
        guard let popup = presetPopup else { return }
        for item in popup.itemArray { item.state = item === popup.selectedItem ? .on : .off }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { markChosenPreset() }

    /// Opens the preset panel under the face. A pointer press leaves the keyboard where it was; Space, Return, Down and Up (and VoiceOver)
    /// put it on the chosen row.
    @objc private func openPresetChoices(_ sender: Any?) {
        let pointer: [NSEvent.EventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        showPresetChoices(keyboard: !(NSApp?.currentEvent.map { pointer.contains($0.type) } ?? false))
    }

    func showPresetChoices(keyboard: Bool) {
        guard let face = presetFace, let choices = presetChoices else { return }
        if choices.host.isShown { choices.host.close(); return }
        choices.present(relativeTo: face, preferredEdge: .minY, keyboard: keyboard)
    }

    @objc private func selectPreset(_ sender: NSPopUpButton) {
        persistSelectedPreset()
        selectedPresetID = sender.selectedItem?.representedObject as? String
        if let preset = presets.presets.first(where: { $0.id == selectedPresetID }) { session.state.selectPreset(preset) }
        reloadPresets(); renderState(); schedulePreview()
    }

    @objc private func addPreset(_ sender: Any?) {
        panel?.makeFirstResponder(nil)
        do {
            let selected = presets.presets.first(where: { $0.id == selectedPresetID })
            let name = selected?.editable == false ? (selected?.name ?? "New Size") + " Copy" : (presetName?.stringValue ?? "New Size")
            let preset = try session.state.preset(name: name, format: selected?.format ?? 0)
            try presets.add(preset); selectedPresetID = preset.id
            reloadPresets(); errorLabel?.stringValue = ""; errorLabel?.isHidden = true; fitPanelToContent()
        } catch { showError(error.localizedDescription) }
    }

    @objc private func savePreset(_ sender: Any?) {
        panel?.makeFirstResponder(nil)
        persistSelectedPreset(); reloadPresets()
    }

    private func persistSelectedPreset() {
        guard let selected = presets.presets.first(where: { $0.id == selectedPresetID }), selected.editable else { return }
        do {
            let replacement = try session.state.preset(id: selected.id, name: presetName?.stringValue ?? selected.name, format: selected.format)
            if replacement != selected { try presets.update(replacement) }
        } catch { showError(error.localizedDescription) }
    }

    @objc private func removePreset(_ sender: Any?) {
        guard let id = selectedPresetID else { return }
        do { try presets.remove(id: id); selectedPresetID = nil; reloadPresets(); errorLabel?.stringValue = ""; errorLabel?.isHidden = true; fitPanelToContent() }
        catch { showError(error.localizedDescription) }
    }

    @objc private func applySheet(_ sender: Any?) {
        previewTimer?.invalidate(); previewTimer = nil
        panel?.makeFirstResponder(nil)
        do {
            try session.apply(beforeDelivery: { self.endSheet(.OK) })
        } catch {
            // Failed admission never ends the sheet or delivers the callback.
            showError(error.localizedDescription)
        }
    }

    @objc private func previewSheet(_ sender: Any?) {
        previewTimer?.invalidate(); previewTimer = nil
        panel?.makeFirstResponder(nil)
        do {
            // Apply keeps the change (one Undo step) and leaves the sheet open on the new size; Cancel then undoes only what is typed next.
            if try session.commit() { renderState() } else { _ = try session.preview() }
        } catch { showError(error.localizedDescription) }
    }

    @objc private func cancelSheet(_ sender: Any?) {
        previewTimer?.invalidate(); previewTimer = nil
        session.cancel()
        endSheet(.cancel)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelSheet(nil)
        return false
    }

    private func endSheet(_ response: NSApplication.ModalResponse) {
        guard let panel else { return }
        // The preset panel is a child of the sheet and goes with it.
        presetChoices?.host.close(restoreFocus: false)
        displayObservation?.invalidate(); displayObservation = nil
        panel.sheetParent?.endSheet(panel, returnCode: response)
        panel.orderOut(nil)
    }
}
