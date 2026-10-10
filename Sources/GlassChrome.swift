import AppKit

enum GlassShape: Equatable {
    case capsule, rounded(CGFloat), circle

    /// Capsule and circle round to half the short side; a fixed radius never exceeds it.
    func radius(for size: NSSize) -> CGFloat {
        let half = max(0, min(size.width, size.height) / 2)
        if case .rounded(let radius) = self { return min(max(0, radius), half) }
        return half
    }
}

/// The look of one control on a group plate: a fill on a rounded layer, never a nested glass surface. What each state draws is
/// `StateStyles.command`; this paints the result onto the control's own layer, so tests can read the style and the layer.
@MainActor
final class StatePlate {
    /// The paint on the layer: fill and border. The full style (content colour, alpha, indicator) is `stateStyle`.
    struct Style: Equatable {
        var fill: NSColor?
        var border: NSColor?
        var borderWidth: CGFloat
        static let none = Style(fill: nil, border: nil, borderWidth: 0)
    }

    /// 12: the group radius (16) minus the 4 pt inset between plate and control.
    static let radius = DesignTokens.Radius.concentric(outer: DesignTokens.Radius.xl, inset: DesignTokens.Space.s1)
    static let animationDuration: TimeInterval = 0.15

    private weak var view: NSView?
    var accessibility: ChromeAccessibility = .none { didSet { apply() } }
    private(set) var isHovered = false, isPressed = false, isSelected = false, isPrimary = false, isDisabled = false, isFocused = false
    private(set) var style = Style.none
    private(set) var stateStyle = StateStyles.command(.rest, primary: false, focused: false, highContrast: false, differentiate: false)
    private(set) var lastAnimationDuration: TimeInterval = 0
    /// Called after every repaint; lets a test watch the press bracket without a real event loop.
    var onApply: ((StatePlate) -> Void)?
    private var batching = false

    init(view: NSView) {
        self.view = view
        view.wantsLayer = true
        view.layer?.cornerRadius = Self.radius
        view.layer?.masksToBounds = false
    }

    /// The state to resolve: disabled beats everything, a press beats a hover, and a selected control keeps its selection under both.
    static func controlState(hovered: Bool, pressed: Bool, selected: Bool, disabled: Bool) -> ControlState {
        if disabled { return .disabled }
        if pressed { return .pressed }
        if hovered { return .hover }
        return selected ? .selected : .rest
    }

    /// Changes several flags with one repaint.
    func update(hovered: Bool? = nil, pressed: Bool? = nil, selected: Bool? = nil, primary: Bool? = nil, disabled: Bool? = nil, focused: Bool? = nil) {
        batching = true
        if let hovered { isHovered = hovered }
        if let pressed { isPressed = pressed }
        if let selected { isSelected = selected }
        if let primary { isPrimary = primary }
        if let disabled { isDisabled = disabled }
        if let focused { isFocused = focused }
        batching = false
        apply()
    }

    func apply() {
        guard !batching, let view, let layer = view.layer else { return }
        let state = Self.controlState(hovered: isHovered, pressed: isPressed, selected: isSelected, disabled: isDisabled)
        let resolved = StateStyles.command(state, primary: isPrimary, focused: isFocused, highContrast: accessibility.increaseContrast,
                                           differentiate: accessibility.differentiateWithoutColor, selected: isSelected, appearance: view.effectiveAppearance)
        let next = Style(fill: resolved.fill, border: resolved.border, borderWidth: resolved.borderWidth)
        let duration = accessibility.reduceMotion ? 0 : Self.animationDuration
        lastAnimationDuration = duration
        let changed = next.fill?.cgColor != style.fill?.cgColor
        if duration > 0, changed, view.window != nil {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            fade.duration = duration
            layer.add(fade, forKey: "plateFill")
        }
        style = next
        stateStyle = resolved
        layer.cornerRadius = Self.radius
        layer.backgroundColor = next.fill?.cgColor
        layer.borderWidth = next.borderWidth
        layer.borderColor = next.border?.cgColor
        onApply?(self)
    }
}

/// Anything on a group plate that draws its own state fill and follows the injected display options.
@MainActor
protocol ChromeFillable: AnyObject {
    var accessibility: ChromeAccessibility { get set }
}

/// The one command button of the chrome (T6): borderless, icon from the Font Awesome / SF Symbol chain, and its own rest, hover,
/// pressed, selected, disabled and focus state resolved by `StateStyles.command` and drawn as a fill on a rounded layer
/// (`StatePlate`), never as another glass surface. Available on macOS 13 so the unit tests run anywhere. Click, Control-click and
/// menu handling stay OriginalActionButton's.
@MainActor
class CommandButton: OriginalActionButton, ChromeFillable {
    var icon: FAIcon? { didSet { refreshIcon() } }
    /// Glyph shown while `state == .on` (Actual Size swaps maximize for minimize); falls back to `icon`.
    var selectedIcon: FAIcon? { didSet { refreshIcon() } }
    var iconFamily: FAFamily = .regular { didSet { refreshIcon() } }
    var selectedFamily: FAFamily = .solid { didSet { refreshIcon() } }
    var iconPointSize: CGFloat = 22 { didSet { refreshIcon() } }
    /// The single saturated command (Snap): its fill is the accent and its icon takes the contrasting color.
    var isPrimary = false { didSet { syncPlate() } }
    /// False for toggles that only change glyph (Actual Size): `.on` neither fills the button nor flips the label color.
    var selectionTints = true { didSet { syncPlate() } }
    /// The focus ring follows the state fill's rounded rectangle.
    var focusShape: GlassShape = .rounded(StatePlate.radius) { didSet { noteFocusRingMaskChanged() } }
    private(set) lazy var plate = StatePlate(view: self)
    var accessibility: ChromeAccessibility {
        get { plate.accessibility }
        set { plate.accessibility = newValue; syncPlate() }
    }
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?
    private(set) var iconSource: ChromeIconSource = .none
    private(set) var activeFamily: FAFamily = .regular
    /// The capsule under the glyph that marks a selected command when Differentiate Without Color is on.
    let indicatorLayer = CALayer()
    private(set) var showsIndicator = false
    /// The glyph scale currently rendered (0.96 while pressed, none under Reduce Motion).
    private(set) var glyphScale: CGFloat = 1
    private var hasKeyboardFocus = false
    /// Whether the button presents as selected. Assigning `state` always counts; AppKit's own flips count only for
    /// two-state button types, because a momentary button reads `.on` while it is merely being clicked.
    private(set) var showsSelection = false
    private(set) var tracksState = false
    var isPressing: Bool { primaryTracking || secondaryHighlight }
    private var primaryTracking = false, secondaryHighlight = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        isBordered = false
        focusRingType = .exterior
        imageHugsTitle = true
        imageScaling = .scaleProportionallyDown
        if (font?.pointSize ?? 0) < DesignTokens.Typography.readableMinimum { font = DesignTokens.Typography.font(.body) }
        syncPlate()
    }

    // NSButton's title convenience initializer assigns its small standard font after init(frame:);
    // keep the caller's face but never fall under the readable floor.
    override var font: NSFont? {
        didSet {
            if font == nil || font!.pointSize < DesignTokens.Typography.readableMinimum {
                super.font = DesignTokens.Typography.floored(font)
            }
        }
    }

    /// Icon-only commands keep their name here instead of drawing it: the name feeds the tooltip and VoiceOver, so
    /// retitles (Snap / Snap Frame, Actual Size / Normal View, Blank / Clear / Wipe) still land without showing text.
    private(set) var iconOnlyName: String?
    /// Keyboard shortcut appended to the derived tooltip, e.g. "⌘Z".
    var shortcutHint: String? { didSet { refreshDerivedToolTip() } }
    private var derivesToolTip = true

    /// What is actually drawn beside the glyph; empty for every icon-only command.
    var visibleTitle: String { super.title }

    override var title: String {
        get { iconOnlyName ?? super.title }
        set {
            if iconOnlyName != nil { iconOnlyName = newValue; refreshDerivedToolTip() } else { super.title = newValue }
            updatePresentation()
        }
    }

    func makeIconOnly(name: String, shortcut: String? = nil, derivesToolTip: Bool = true) {
        super.title = ""
        iconOnlyName = name
        self.derivesToolTip = derivesToolTip
        shortcutHint = shortcut
        refreshDerivedToolTip()
        updatePresentation()
    }

    private func refreshDerivedToolTip() {
        guard derivesToolTip, let name = iconOnlyName else { return }
        AppToolTip.setText(shortcutHint.map { "\(name) (\($0))" } ?? name, for: self)
    }

    private var explicitAccessibilityLabel: String?

    // Without Font Awesome the icon is an SF Symbol with no description of its own, and AppKit then reads the symbol's
    // ("download" for Save) instead of the command. An explicit label wins; otherwise the live title is what is read,
    // so Snap / Snap Frame, Actual Size / Normal View and Blank / Clear / Wipe follow their retitles like Classic's.
    override func setAccessibilityLabel(_ label: String?) {
        explicitAccessibilityLabel = label
        super.setAccessibilityLabel(label)
    }

    override func accessibilityLabel() -> String? {
        if let explicitAccessibilityLabel { return explicitAccessibilityLabel }
        return title.isEmpty ? super.accessibilityLabel() : title
    }

    // Symbol artwork carries alignment insets that make the frame outgrow the surface's constraints; the glass is the bezel here.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }

    override var state: NSControl.StateValue {
        didSet {
            showsSelection = state == .on
            refreshIcon()
            syncPlate()
        }
    }

    override func setButtonType(_ type: NSButton.ButtonType) {
        super.setButtonType(type)
        tracksState = [.toggle, .pushOnPushOff, .onOff, .switch, .radio].contains(type)
    }

    override var isEnabled: Bool {
        didSet {
            noteFocusRingMaskChanged()
            syncPlate()
        }
    }

    override var isHidden: Bool {
        didSet { syncPlate() }
    }

    func refreshIcon() {
        if tracksState { showsSelection = state == .on }
        let selected = showsSelection
        activeFamily = selected ? selectedFamily : iconFamily
        guard let glyph = (selected ? selectedIcon : nil) ?? icon else {
            iconSource = .none
            image = nil
            updatePresentation()
            return
        }
        let resolved = ChromeIcons.resolve(glyph, family: activeFamily, pointSize: iconPointSize * glyphScale)
        iconSource = resolved.source
        image = resolved.image
        updatePresentation()
    }

    private func updatePresentation() {
        imagePosition = image == nil ? .noImage : (visibleTitle.isEmpty ? .imageOnly : .imageLeading)
        syncPlate()
    }

    private var isShownSelected: Bool { selectionTints && showsSelection }

    /// Black or white for text on `background`, whichever reaches the WCAG 4.5:1 floor (white first), else the stronger.
    static func textColor(on background: NSColor) -> NSColor {
        DesignTokens.Palette.onAccent(fill: background, alpha: 1, over: .white)
    }

    /// Pushes this button's own state into its fill, glyph colour, glyph size, alpha and indicator; the group plate behind it never changes.
    private func syncPlate() {
        plate.update(hovered: isHovered, pressed: isPressing, selected: isShownSelected, primary: isPrimary, disabled: !isEnabled, focused: hasKeyboardFocus)
        let style = plate.stateStyle
        if contentTintColor != style.content { contentTintColor = style.content }
        alphaValue = style.contentAlpha
        showIndicator(style)
        let scale = accessibility.reduceMotion ? 1 : style.glyphScale
        if scale != glyphScale {
            glyphScale = scale
            refreshIcon()
        }
    }

    private func showIndicator(_ style: StateStyle) {
        showsIndicator = style.indicator
        guard let layer else { return }
        // The capsule appears and goes at once: no implicit fade, so it never lingers half-visible after the selection moves.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard style.indicator else { indicatorLayer.isHidden = true; return }
        let size = StateStyles.indicatorSize(highContrast: accessibility.increaseContrast)
        if indicatorLayer.superlayer !== layer { layer.addSublayer(indicatorLayer) }
        indicatorLayer.isHidden = false
        indicatorLayer.cornerRadius = size.height / 2
        indicatorLayer.backgroundColor = style.content.cgColor
        // A button's layer follows the view's flipped coordinates, so "under the glyph" is measured from whichever edge is the bottom.
        let y = isFlipped ? bounds.height - StateStyles.indicatorInset - size.height : StateStyles.indicatorInset
        indicatorLayer.frame = NSRect(x: (bounds.width - size.width) / 2, y: y, width: size.width, height: size.height)
    }

    override func layout() {
        super.layout()
        if showsIndicator { showIndicator(plate.stateStyle) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { hasKeyboardFocus = true; syncPlate() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { hasKeyboardFocus = false; syncPlate() }
        return resigned
    }

    /// Hover state entry point for the tracking area; tests drive it directly.
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        syncPlate()
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

    // A hidden or detached button never receives mouseExited, so drop transient state here.
    override func viewDidHide() {
        super.viewDidHide()
        setHovered(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        secondaryHighlight = flag
        syncPlate()
    }

    // NSButton highlights its cell directly while tracking a primary click and never calls highlight(_:),
    // so the press is bracketed here. The secondary and menu paths stay entirely OriginalActionButton's.
    override func mouseDown(with event: NSEvent) {
        let tracksPrimary = isEnabled && !event.modifierFlags.contains(.control) && !(showMenuOnLeftClick && menu != nil)
        if tracksPrimary { primaryTracking = true; syncPlate() }
        super.mouseDown(with: event)
        if primaryTracking { primaryTracking = false }
        syncIconToState()
        syncPlate()
    }

    // AppKit toggles a button's state inside its cell, bypassing the `state` override above.
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        syncIconToState()
        syncPlate()
        return super.sendAction(action, to: target)
    }

    private func syncIconToState() {
        if tracksState, showsSelection != (state == .on) { refreshIcon() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        syncPlate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncPlate()
    }

    private var focusBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }

    override var focusRingMaskBounds: NSRect {
        isEnabled && !focusBounds.isEmpty ? focusBounds : .zero
    }

    override func drawFocusRingMask() {
        guard isEnabled, !focusBounds.isEmpty else { return }
        let radius = focusShape.radius(for: focusBounds.size)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.black.setFill()
        NSBezierPath(roundedRect: focusBounds, xRadius: radius, yRadius: radius).fill()
    }
}

/// A non-button control on a group plate (a popup, the colour swatch, the size pill, the drag well). It carries no glass of its
/// own: at rest it is invisible, and hover draws the same rounded fill the buttons use. The control sits inside it, either
/// filling it or centred with a horizontal inset (popups only centre their text at their natural height).
@MainActor
final class ChromeFillCell: NSView, ChromeFillable {
    enum Fit { case fill, centered(inset: CGFloat) }

    let control: NSView
    let fixedSize: NSSize
    private(set) lazy var plate = StatePlate(view: self)
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?
    weak var focusTarget: NSView?

    var accessibility: ChromeAccessibility {
        get { plate.accessibility }
        set { plate.accessibility = newValue }
    }

    init(_ control: NSView, size: NSSize, fit: Fit = .fill) {
        self.control = control
        self.fixedSize = size
        super.init(frame: NSRect(origin: .zero, size: size))
        translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        var constraints = [widthAnchor.constraint(equalToConstant: size.width), heightAnchor.constraint(equalToConstant: size.height)]
        switch fit {
        case .fill:
            constraints += [control.leadingAnchor.constraint(equalTo: leadingAnchor), control.trailingAnchor.constraint(equalTo: trailingAnchor),
                            control.topAnchor.constraint(equalTo: topAnchor), control.bottomAnchor.constraint(equalTo: bottomAnchor)]
        case .centered(let inset):
            constraints += [control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
                            control.centerYAnchor.constraint(equalTo: centerYAnchor)]
        }
        NSLayoutConstraint.activate(constraints)
        plate.apply()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Hover state entry point for the tracking area; tests drive it directly.
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        plate.update(hovered: hovered)
    }

    /// A control that is a plain view or draws its own press (the Size pill, the drag well) reports it here so the cell fills for it too.
    func setPressed(_ pressed: Bool, disabled: Bool = false) {
        plate.update(pressed: pressed, disabled: disabled)
    }

    override func mouseDown(with event: NSEvent) {
        if let focusTarget { window?.makeFirstResponder(focusTarget) } else { super.mouseDown(with: event) }
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

    override func viewDidHide() {
        super.viewDidHide()
        setHovered(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        plate.apply()
    }
}

/// One Liquid Glass plate around one GROUP of controls. The plate is the only glass in the group: the buttons on it draw their own
/// hover, pressed and selected fills, so there is never glass inside glass. It sizes itself to its content, so a hidden control
/// (Cancel outside Frame mode) leaves no slot behind. Display options:
///  - Reduce Transparency: no tint, and an opaque `surface.content` plate with a 1 pt separator border behind the content;
///  - Increase Contrast: a 1 pt `labelColor` 0.6 border on the plate.
@MainActor
final class GlassSurfaceView: NSGlassEffectView {
    var shape: GlassShape { didSet { syncShape() } }
    var accessibility: ChromeAccessibility { didSet { applyDisplayOptions() } }
    let arrangedViews: [NSView]
    private let stack = NSStackView()
    private let host = NSView()
    private let solidPlate = NSView()

    /// The opaque fallback plate; nil while the glass material is in use.
    var transparencyPlate: NSView? { accessibility.reduceTransparency ? solidPlate : nil }
    var showsContrastBorder: Bool { accessibility.increaseContrast }

    init(views: [NSView], shape: GlassShape = .rounded(DesignTokens.Radius.xl), accessibility: ChromeAccessibility, spacing: CGFloat = GlassChrome.Metrics.groupSpacing) {
        self.shape = shape
        self.accessibility = accessibility
        self.arrangedViews = views
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        style = .regular
        // A plate is the container of interactive controls, which is what the system's press response is for (macOS 27 only).
        if #available(macOS 27, *) { effectIsInteractive = true }

        solidPlate.wantsLayer = true
        solidPlate.translatesAutoresizingMaskIntoConstraints = false
        solidPlate.isHidden = true
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        stack.distribution = .gravityAreas
        let inset = GlassChrome.Metrics.groupInset
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        for view in views { stack.addArrangedSubview(view) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(solidPlate)
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            solidPlate.leadingAnchor.constraint(equalTo: host.leadingAnchor), solidPlate.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            solidPlate.topAnchor.constraint(equalTo: host.topAnchor), solidPlate.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor), stack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            stack.topAnchor.constraint(equalTo: host.topAnchor), stack.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        contentView = host
        // The glass pins its content with weak constraints; the plate takes its width from the stack instead, so it hugs the group.
        // Every control on a plate is at most one command high, so every plate is one bar row high.
        NSLayoutConstraint.activate([widthAnchor.constraint(equalTo: stack.widthAnchor),
                                     heightAnchor.constraint(equalToConstant: GlassChrome.Metrics.commandHeight + 2 * inset)])
        syncShape()
        applyDisplayOptions()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Hidden arranged views leave the stack, so the plate narrows with them.
    func setSpacing(_ spacing: CGFloat) { stack.spacing = spacing }

    private func applyDisplayOptions() {
        // Nothing ever tints the plate; the saturated accent lives on one button's fill.
        if tintColor != nil { tintColor = nil }
        style = .regular
        solidPlate.isHidden = !accessibility.reduceTransparency
        let radius = shape.radius(for: bounds.size)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            solidPlate.layer?.backgroundColor = DesignTokens.Palette.Surface.content.cgColor
            solidPlate.layer?.borderColor = DesignTokens.Palette.separator.cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.6).cgColor
        }
        solidPlate.layer?.borderWidth = 1
        solidPlate.layer?.cornerRadius = radius
        layer?.borderWidth = accessibility.increaseContrast ? 1 : 0
    }

    private func syncShape() {
        let radius = shape.radius(for: bounds.size)
        if cornerRadius != radius { cornerRadius = radius }
        layer?.cornerRadius = radius
        solidPlate.layer?.cornerRadius = radius
    }

    override func layout() {
        super.layout()
        syncShape()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncShape()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDisplayOptions()
    }
}

@MainActor
enum GlassChrome {
    enum Metrics {
        // A control on a plate is 36 pt tall inside a 4 pt inset, so every plate is the 44 pt header / footer row.
        /// 44 pt wide so the ten tools, the capture group and the annotation group fit one row at the 980 pt minimum window.
        static let toolButton = NSSize(width: 44, height: DesignTokens.Size.control)
        /// Every icon-only command shares this size; Snap, the primary one, is the wider `primaryButton`.
        static let iconButton = NSSize(width: 48, height: DesignTokens.Size.control)
        /// The Toolbox glyph plus its chevron needs more room than a plain icon.
        static let toolboxButton = NSSize(width: 60, height: DesignTokens.Size.control)
        static let primaryButton = NSSize(width: 56, height: DesignTokens.Size.control)
        static let commandHeight: CGFloat = DesignTokens.Size.control
        static let headerHeight: CGFloat = 44
        static let iconPointSize: CGFloat = 22, primaryIconPointSize: CGFloat = 26
        /// Between two controls on one plate; wide enough that two neighbouring fills never touch.
        static let groupSpacing: CGFloat = 2
        /// Plate edge to control: group radius 16 minus this is the concentric control radius 12.
        static let groupInset: CGFloat = DesignTokens.Space.s1
        /// The smallest gap between two glass groups in one bar.
        static let groupGap: CGFloat = 12
        // NSGlassEffectContainerView merges glass closer than its spacing; Apple's default of 0 batches the plates without distorting them.
        static let containerSpacing: CGFloat = 0
    }

    /// Apple's over-glass Extra Large control size (36 pt) for every control that supports a control size;
    /// the caller's font survives the size change so text stays at 20 pt.
    static func useExtraLarge(_ control: NSControl) {
        let font = control.font
        control.controlSize = .extraLarge
        if let font { control.font = font }
    }

    /// Pins a control to an explicit size: glass collapses to its content's fitting size, so every control on a plate carries one.
    static func fix(_ view: NSView, _ size: NSSize) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: size.width), view.heightAnchor.constraint(equalToConstant: size.height)])
    }

    /// One glass plate holding a group of controls.
    static func plate(_ views: [NSView], identifier: String, accessibility: ChromeAccessibility) -> GlassSurfaceView {
        let plate = GlassSurfaceView(views: views, accessibility: accessibility)
        plate.identifier = NSUserInterfaceItemIdentifier(identifier)
        return plate
    }

    /// The one container for a bar: the plates inside it share a render pass so nearby glass blends instead of sampling itself.
    static func container(around content: NSView, identifier: String) -> NSGlassEffectContainerView {
        let container = NSGlassEffectContainerView()
        container.spacing = Metrics.containerSpacing
        container.contentView = content
        container.identifier = NSUserInterfaceItemIdentifier(identifier)
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }
}

/// The display options the glass chrome adapts to, as a value so tests can inject them. The live value is
/// `DisplayOptions.current` (injection, then the system), so the screenshot harness can simulate them too; this value is the
/// chrome's view of it (`DisplayOptions.chrome`). Differentiate Without Color feeds the selected indicator of the state styles.
struct ChromeAccessibility: Equatable, Sendable {
    var reduceTransparency: Bool, increaseContrast: Bool, reduceMotion: Bool
    var differentiateWithoutColor = false
    static let none = ChromeAccessibility(reduceTransparency: false, increaseContrast: false, reduceMotion: false)
    @MainActor static var live: ChromeAccessibility { DisplayOptions.current.chrome }
}

/// One VoiceOver child of the format toggle: a radio button named after its segment that presses through the toggle.
@MainActor
final class SegmentedToggleElement: NSAccessibilityElement {
    private weak var toggle: SegmentedToggle?
    let index: Int

    init(toggle: SegmentedToggle, index: Int) {
        self.toggle = toggle
        self.index = index
        super.init()
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(toggle.label(forSegment: index))
        setAccessibilityParent(toggle)
    }

    override func accessibilityValue() -> Any? { NSNumber(value: toggle?.selectedSegment == index ? 1 : 0) }
    override func isAccessibilityEnabled() -> Bool { toggle?.isEnabled ?? false }
    override func accessibilityPerformPress() -> Bool {
        guard let toggle, toggle.isEnabled else { return false }
        toggle.choose(index)
        return true
    }
}

/// The footer's PNG | JPG toggle, drawn from `StateStyles.toggleSegment` instead of the system capsule track: two 12 pt rounded
/// segments on faint plates, the selected one an accent tint with `bodyStrong` text, so selection is also a weight. It is one tab stop;
/// Left and Right move the selection, Space switches to the other segment. It sends its action on every change, like the control
/// it replaces, and exposes two radio-button children ("PNG", "JPG") under the group "Image format".
@MainActor
final class SegmentedToggle: NSControl, ChromeFillable {
    static let segmentGap: CGFloat = 2, segmentPadding: CGFloat = 12

    let titles: [String]
    var segmentCount: Int { titles.count }
    func label(forSegment index: Int) -> String { titles[index] }
    /// Assigning moves the selection without sending the action, like NSSegmentedControl.
    var selectedSegment = 0 {
        didSet {
            selectedSegment = min(max(0, selectedSegment), titles.count - 1)
            guard selectedSegment != oldValue else { return }
            needsDisplay = true
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
    var accessibility: ChromeAccessibility = .none { didSet { needsDisplay = true } }
    private(set) var hoveredSegment: Int?, pressedSegment: Int?
    private var hasKeyboardFocus = false
    private var hoverArea: NSTrackingArea?
    private(set) lazy var elements: [SegmentedToggleElement] = titles.indices.map { SegmentedToggleElement(toggle: self, index: $0) }

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        cell = NSActionCell()
        isEnabled = true
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Image format")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { isEnabled }
    override var isFlipped: Bool { false }
    override var isEnabled: Bool { didSet { needsDisplay = true; noteFocusRingMaskChanged() } }

    // MARK: geometry

    /// Both segments share the width of the wider title set in the strong weight, so choosing one never moves the other.
    private var segmentWidth: CGFloat {
        let strong = DesignTokens.Typography.font(.bodyStrong)
        return ceil(titles.map { ($0 as NSString).size(withAttributes: [.font: strong]).width }.max() ?? 0) + 2 * Self.segmentPadding
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: segmentWidth * CGFloat(titles.count) + Self.segmentGap * CGFloat(titles.count - 1), height: GlassChrome.Metrics.commandHeight)
    }

    func segmentRect(_ index: Int) -> NSRect {
        let width = (bounds.width - Self.segmentGap * CGFloat(titles.count - 1)) / CGFloat(titles.count)
        return NSRect(x: CGFloat(index) * (width + Self.segmentGap), y: 0, width: width, height: bounds.height)
    }

    func segment(at point: NSPoint) -> Int? { titles.indices.first { segmentRect($0).contains(point) } }

    // MARK: state

    func state(ofSegment index: Int) -> ControlState {
        if !isEnabled { return .disabled }
        if selectedSegment == index { return .selected }
        if pressedSegment == index { return .pressed }
        return hoveredSegment == index ? .hover : .rest
    }

    /// The face a segment's title is drawn in: 20 pt, semibold while the segment is selected.
    func textFont(forSegment index: Int) -> NSFont {
        DesignTokens.Typography.font(style(ofSegment: index).strongText ? .bodyStrong : .body)
    }

    func style(ofSegment index: Int) -> StateStyle {
        StateStyles.toggleSegment(state(ofSegment: index), focused: hasKeyboardFocus, highContrast: accessibility.increaseContrast,
                                  differentiate: accessibility.differentiateWithoutColor, appearance: effectiveAppearance)
    }

    /// Hover entry point for the tracking area; tests drive it directly.
    func setHoveredSegment(_ index: Int?) {
        guard hoveredSegment != index else { return }
        hoveredSegment = index
        needsDisplay = true
    }

    /// Press entry point for mouseDown and mouseDragged; tests drive it directly.
    func setPressedSegment(_ index: Int?) {
        guard pressedSegment != index else { return }
        pressedSegment = index
        needsDisplay = true
    }

    /// Selects a segment and sends the action; choosing the selected segment does nothing.
    func choose(_ index: Int) {
        guard isEnabled, titles.indices.contains(index), index != selectedSegment else { return }
        selectedSegment = index
        _ = sendAction(action, to: target)
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        for index in titles.indices {
            let style = style(ofSegment: index), rect = segmentRect(index)
            let radius = StatePlate.radius
            let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            if style.contentAlpha < 1 { NSGraphicsContext.current?.cgContext.setAlpha(style.contentAlpha) }
            if let fill = style.fill { fill.setFill(); shape.fill() }
            if let border = style.border, style.borderWidth > 0 {
                let inset = NSBezierPath(roundedRect: rect.insetBy(dx: style.borderWidth / 2, dy: style.borderWidth / 2), xRadius: radius - style.borderWidth / 2, yRadius: radius - style.borderWidth / 2)
                border.setStroke(); inset.lineWidth = style.borderWidth; inset.stroke()
            }
            let font = textFont(forSegment: index)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.content]
            let size = (titles[index] as NSString).size(withAttributes: attributes)
            (titles[index] as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHoveredSegment(segment(at: convert(event.locationInWindow, from: nil))) }
    override func mouseMoved(with event: NSEvent) { setHoveredSegment(segment(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { setHoveredSegment(nil) }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressedSegment(segment(at: convert(event.locationInWindow, from: nil)))
    }

    // A press that slides off its segment is cancelled, like a button.
    override func mouseDragged(with event: NSEvent) {
        guard let pressed = pressedSegment else { return }
        let inside = segment(at: convert(event.locationInWindow, from: nil)) == pressed
        if !inside { setPressedSegment(nil); pressedOutside = pressed }
        else if pressedOutside == pressed { setPressedSegment(pressed); pressedOutside = nil }
    }

    private var pressedOutside: Int?

    override func mouseUp(with event: NSEvent) {
        let pressed = pressedSegment ?? pressedOutside
        let released = segment(at: convert(event.locationInWindow, from: nil))
        setPressedSegment(nil)
        pressedOutside = nil
        if let pressed, pressed == released { choose(pressed) }
    }

    override func viewDidHide() {
        super.viewDidHide()
        setHoveredSegment(nil); setPressedSegment(nil)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHoveredSegment(nil); setPressedSegment(nil) }
        super.viewWillMove(toWindow: newWindow)
    }

    // MARK: keyboard

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123: choose(selectedSegment - 1)
        case 124: choose(selectedSegment + 1)
        case 49: choose(selectedSegment == 0 ? 1 : 0)
        default: super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { hasKeyboardFocus = true; needsDisplay = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { hasKeyboardFocus = false; needsDisplay = true }
        return resigned
    }

    override var focusRingMaskBounds: NSRect { isEnabled && !bounds.isEmpty ? bounds.insetBy(dx: 1, dy: 1) : .zero }

    override func drawFocusRingMask() {
        guard isEnabled, !bounds.isEmpty else { return }
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: StatePlate.radius, yRadius: StatePlate.radius).fill()
    }

    // MARK: accessibility

    override func accessibilityChildren() -> [Any]? {
        for element in elements { element.setAccessibilityFrameInParentSpace(segmentRect(element.index)) }
        return elements
    }

    override func accessibilityValue() -> Any? { titles[selectedSegment] }
    override func isAccessibilitySelected() -> Bool { false }
}
