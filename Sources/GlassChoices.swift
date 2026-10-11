import AppKit

// The shared glass choice primitives: a choice button (command, option, toggle, submenu), an inline exclusive group of them, the
// transparent child panel that floats a stack of group plates beside an anchor, and the menu adapter that fills such a panel from an
// NSMenu. Every plate is the only glass in its group (GlassSurfaceView); every button draws its own state fill (StatePlate), so there
// is never glass inside glass, and a panel holds exactly one NSGlassEffectContainerView.

// MARK: - Shortcut text

/// How a key equivalent is written beside a title: control, option, shift, command, then the key; an upper-case letter implies shift.
/// Named keys are spelled out where the system has no plain key-cap glyph (the arrows, Delete, Space, F-keys).
enum MenuShortcut {
    static func text(for item: NSMenuItem) -> String? {
        text(keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
    }

    static func text(keyEquivalent key: String, modifiers: NSEvent.ModifierFlags) -> String? {
        guard !key.isEmpty else { return nil }
        var mask = modifiers.intersection(.deviceIndependentFlagsMask)
        if key != key.lowercased() { mask.insert(.shift) }
        var text = ""
        if mask.contains(.control) { text += "⌃" }
        if mask.contains(.option) { text += "⌥" }
        if mask.contains(.shift) { text += "⇧" }
        if mask.contains(.command) { text += "⌘" }
        return text + keyName(key)
    }

    private static func keyName(_ key: String) -> String {
        let scalars = key.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return key.uppercased() }
        switch scalar.value {
        case 0x0D, 0x03: return "\u{21A9}\u{FE0E}"
        case 0x09: return "⇥"
        case 0x1B: return "⎋"
        case 0x20: return "Space"
        case 0x08, 0x7F, 0xF728: return "Delete"
        case 0xF700: return "Up"
        case 0xF701: return "Down"
        case 0xF702: return "Left"
        case 0xF703: return "Right"
        case 0xF704...0xF70F: return "F\(scalar.value - 0xF704 + 1)"
        case 0xF729: return "Home"
        case 0xF72B: return "End"
        case 0xF72C: return "Page Up"
        case 0xF72D: return "Page Down"
        default: return key.uppercased()
        }
    }
}

extension NSEvent {
    /// Whether a key carries a modifier that makes it a shortcut for someone else: Command, Option or Control. Shift keeps its own meaning
    /// (Shift-Tab), and the numeric-pad and function flags AppKit puts on every arrow key, and Caps Lock, are not modifiers at all, so a
    /// handler must never reject an arrow for carrying them (never intersect with `.deviceIndependentFlagsMask`).
    var hasShortcutModifier: Bool { !modifierFlags.intersection([.command, .option, .control]).isEmpty }
}

// MARK: - Passive content views

/// A glyph inside a choice row. It is decoration for the row, not an element of its own: clicks fall through to the row and
/// VoiceOver reads the row.
@MainActor
private final class RowGlyphView: NSImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyDown
        imageAlignment = .alignCenter
        isEditable = false
        animates = false
        isHidden = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private func makeRowLabel(_ style: DesignTokens.Typography.Style) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = DesignTokens.Typography.font(style)
    label.isSelectable = false
    label.isEditable = false
    label.drawsBackground = false
    label.isBordered = false
    label.allowsDefaultTighteningForTruncation = false
    label.setAccessibilityElement(false)
    return label
}

/// What a row label needs, measured the way it is drawn: by a real text field in the face that will be shown, so the cell's own padding is
/// counted (a bounding box of the string alone is about 4 pt short, and the label then truncates). Wrapping labels measure at `wrapWidth`.
@MainActor
private enum LabelMetrics {
    private static let probe = makeRowLabel(.body)

    static func fit(_ text: String, style: DesignTokens.Typography.Style, wrapWidth: CGFloat? = nil) -> NSSize {
        guard !text.isEmpty else { return .zero }
        let wraps = wrapWidth != nil
        probe.font = DesignTokens.Typography.font(style)
        probe.stringValue = text
        probe.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        probe.maximumNumberOfLines = wraps ? 0 : 1
        probe.cell?.wraps = wraps
        probe.preferredMaxLayoutWidth = wrapWidth ?? 0
        let size = probe.fittingSize
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    /// One line of 20 pt text, as the row's label draws it.
    static var lineHeight: CGFloat { fit("Mg", style: .bodyStrong).height }
}

// MARK: - Choice button

/// One glass choice: a titled button that is a command, an option of an exclusive set, a toggle, or a row that opens a submenu.
/// It is a `CommandButton`, so its rest, hover, pressed, selected, disabled and focus states are the shared `StateStyles.command`
/// fills drawn on its own layer (never another glass surface). "Chosen" is the selected look: the accent fill, its 1 pt border, the
/// Differentiate-Without-Color capsule, the semibold title and the indicator glyph, so it never rests on colour alone.
/// `isChosen` is `state == .on`, both ways, so a handler that reads `sender.state` keeps working.
@MainActor
final class GlassChoiceButton: CommandButton {
    enum Kind: Equatable { case command, option, toggle, submenu }
    enum Indicator: Equatable { case none, check, checkbox, radio, chevron }
    /// `.row` is full width with the title leading; `.segment` centres its content (a button of an inline set).
    enum Layout: Equatable { case row, segment }

    static let height = DesignTokens.Size.control
    static let padding = DesignTokens.Space.s3
    static let gap = DesignTokens.Space.s2
    /// Space between the title and the shortcut text.
    static let shortcutGap = DesignTokens.Space.s4
    /// Glyphs are drawn at the inline icon size on the same 1.25 canvas the chrome icons use.
    static let glyphPointSize = DesignTokens.Typography.iconInline
    static var glyphSide: CGFloat { ceil(glyphPointSize * 1.25) }

    /// Space between the button's edge and its first and last content. A control on a crowded bar tightens it (the Original size toggle);
    /// every other button keeps `padding`.
    var horizontalPadding: CGFloat = GlassChoiceButton.padding { didSet { if horizontalPadding != oldValue { contentDidChange() } } }
    /// Space between neighbouring content (mark, icon, title, trailing glyph). Defaults to `gap`.
    var contentGap: CGFloat = GlassChoiceButton.gap { didSet { if contentGap != oldValue { contentDidChange() } } }

    var kind: Kind { didSet { if kind != oldValue { kindDidChange() } } }
    var indicator: Indicator { didSet { if indicator != oldValue { indicatorDidChange() } } }
    /// Named `choiceLayout` because `layout` is NSView's own method.
    var choiceLayout: Layout { didSet { if choiceLayout != oldValue { needsLayout = true } } }
    /// Trailing shortcut text (20 pt, secondary; the content colour while chosen).
    var shortcutText: String? { didSet { shortcutLabel.stringValue = shortcutText ?? ""; shortcutLabel.isHidden = shortcutText == nil; contentDidChange() } }
    /// A leading image taken as it is (a menu item's image). `icon` (the Font Awesome chain) is used when this is nil.
    var leadingImage: NSImage? { didSet { refreshIcon() } }
    /// Wraps the title at this width and grows the row above 36 pt; nil keeps one truncating line.
    var wrapWidth: CGFloat? { didSet { wrapDidChange() } }
    /// Keeps the icon column even when this row has no icon, so the titles of a panel's rows line up.
    var reservesIconColumn = false { didSet { contentDidChange() } }
    /// Keeps the trailing check / chevron column even when this row has none, so shortcuts and glyphs line up.
    var reservesTrailingColumn = false { didSet { contentDidChange() } }
    var minimumWidth: CGFloat = 0 { didSet { invalidateIntrinsicContentSize() } }
    /// False for the buttons of an inline set that are not its one tab stop.
    var participatesInKeyLoop = true
    /// Offered every key before the button's own handling; returning true consumes it. The inline group and the panel navigate with it.
    var keyHandler: ((NSEvent) -> Bool)?

    let titleLabel = makeRowLabel(.body)
    let shortcutLabel = makeRowLabel(.body)
    private let iconView = RowGlyphView(frame: .zero)
    private let markView = RowGlyphView(frame: .zero)
    private let trailingView = RowGlyphView(frame: .zero)
    private var appliedIndicatorKey: IndicatorKey?

    private struct IndicatorKey: Equatable { let indicator: Indicator; let chosen: Bool }

    static func defaultIndicator(for kind: Kind) -> Indicator {
        switch kind {
        case .command: return .none
        case .option, .toggle: return .check
        case .submenu: return .chevron
        }
    }

    init(title: String, kind: Kind = .command, indicator: Indicator? = nil, layout: Layout = .row) {
        self.kind = kind
        self.indicator = indicator ?? Self.defaultIndicator(for: kind)
        self.choiceLayout = layout
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: Self.height))
        setButtonType(.momentaryPushIn)
        imagePosition = .noImage
        iconPointSize = Self.glyphPointSize
        // The visible words are the label subview; the name stays on `title` for VoiceOver without a tooltip that repeats them.
        makeIconOnly(name: title, derivesToolTip: false)
        titleLabel.stringValue = title
        shortcutLabel.isHidden = true
        for view in [markView, iconView, titleLabel, shortcutLabel, trailingView] { addSubview(view) }
        wrapDidChange()
        refreshIcon()
        refreshIndicatorImages()
        syncRole()
        // The button is its own accessibility element (its role, value and label are answered here). Left as a standard control it is ignored and
        // its cell stands in for it, but this class answers no children (the label and glyphs are not elements), so AppKit found neither the
        // button nor its cell: every choice button on a panel or a plate was dropped from the tree an assistive client reads.
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Same as `state == .on`; assigning it moves the selected look and never sends the action.
    var isChosen: Bool {
        get { state == .on }
        set { state = newValue ? .on : .off }
    }

    /// The value this button owns. AppKit also flips a button's cell state on every click and does it behind the `state` property, so
    /// the cell's value cannot be trusted at click time; `chosen` only follows writes made through `state` / `isChosen` and the click
    /// rules in `sendAction`, which is how one click moves a toggle exactly once.
    private var chosen = false

    // MARK: title

    override var title: String {
        get { super.title }
        set {
            super.title = newValue
            titleLabel.stringValue = newValue
            contentDidChange()
        }
    }

    // MARK: content

    private func contentDidChange() {
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func wrapDidChange() {
        let wraps = wrapWidth != nil
        titleLabel.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        titleLabel.maximumNumberOfLines = wraps ? 0 : 1
        titleLabel.cell?.wraps = wraps
        titleLabel.cell?.isScrollable = false
        contentDidChange()
    }

    private func kindDidChange() {
        syncRole()
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func indicatorDidChange() {
        refreshIndicatorImages()
        contentDidChange()
    }

    /// Where the leading glyph came from: the Font Awesome chain's answer (Pro, embedded Free, or the SF fallback) for an `icon`, or `.none` for
    /// no glyph or for a raw `leadingImage` (a menu item's own image, which is not from the chain).
    private(set) var leadingIconSource: ChromeIconSource = .none

    // The cell never draws a glyph: the leading icon is a subview, so the title, shortcut and glyphs lay out as one row.
    override func refreshIcon() {
        let glyph = (showsSelection ? selectedIcon : nil) ?? icon
        let family = showsSelection ? selectedFamily : iconFamily
        if let leadingImage {
            iconView.image = leadingImage
            leadingIconSource = .none
        } else if let glyph {
            let resolved = ChromeIcons.resolve(glyph, family: family, pointSize: iconPointSize)
            iconView.image = resolved.image
            leadingIconSource = resolved.image == nil ? .none : resolved.source
        } else {
            iconView.image = nil
            leadingIconSource = .none
        }
        iconView.isHidden = iconView.image == nil
        contentDidChange()
    }

    private var hasIcon: Bool { iconView.image != nil }
    private var hasMark: Bool { indicator == .checkbox || indicator == .radio }
    private var hasTrailing: Bool { indicator == .check || indicator == .chevron }

    /// The glyph that marks an unchosen or chosen state; nil for indicators with no leading mark.
    var markImage: NSImage? { markView.image }
    /// The trailing check or chevron image, whether or not it is currently shown.
    var trailingImage: NSImage? { trailingView.image }
    /// Whether the trailing check / chevron is drawn right now (a check only while chosen).
    var showsTrailingGlyph: Bool { !trailingView.isHidden }
    var showsMark: Bool { !markView.isHidden }
    var leadingIconImage: NSImage? { iconView.image }

    private func refreshIndicatorImages() {
        appliedIndicatorKey = IndicatorKey(indicator: indicator, chosen: isChosen)
        switch indicator {
        case .checkbox: markView.image = Self.checkboxImage(on: isChosen)
        case .radio: markView.image = Self.radioImage(on: isChosen)
        default: markView.image = nil
        }
        markView.isHidden = markView.image == nil
        switch indicator {
        case .check: trailingView.image = Self.checkImage()
        case .chevron: trailingView.image = Self.chevronImage()
        default: trailingView.image = nil
        }
        trailingView.isHidden = trailingView.image == nil || (indicator == .check && !isChosen)
    }

    // MARK: glyphs, from the Font Awesome assets only

    private static func glyph(_ icon: FAIcon, _ family: FAFamily, scale: CGFloat = 1) -> NSImage? {
        ChromeIcons.resolve(icon, family: family, pointSize: glyphPointSize * scale).image
    }

    /// Off: the regular square outline. On: the solid square with the check knocked out, so the box and the mark are one template shape.
    static func checkboxImage(on: Bool) -> NSImage? {
        guard on else { return glyph(.square, .regular) }
        guard let box = glyph(.square, .solid), let check = glyph(.check, .solid, scale: 0.55) else { return glyph(.square, .solid) }
        return knockedOut(box, with: check)
    }

    /// Off: the regular circle. On: the solid circle with its check cut out.
    static func radioImage(on: Bool) -> NSImage? { on ? glyph(.circleCheck, .solid) : glyph(.circle, .regular) }
    static func checkImage() -> NSImage? { glyph(.check, .solid) }
    static func chevronImage() -> NSImage? { glyph(FAIcon.chevronRight, .solid, scale: 0.8) }

    private static func knockedOut(_ base: NSImage, with hole: NSImage) -> NSImage {
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            let holeRect = NSRect(x: rect.midX - hole.size.width / 2, y: rect.midY - hole.size.height / 2, width: hole.size.width, height: hole.size.height)
            hole.draw(in: holeRect, from: .zero, operation: .destinationOut, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: recolouring

    override func plateDidSync(_ style: StateStyle) {
        if appliedIndicatorKey != IndicatorKey(indicator: indicator, chosen: isChosen) { refreshIndicatorImages() }
        let font = DesignTokens.Typography.font(isChosen ? .bodyStrong : .body)
        if titleLabel.font != font { titleLabel.font = font }
        titleLabel.textColor = style.content
        shortcutLabel.textColor = isChosen && selectionTints ? style.content : DesignTokens.Palette.Text.secondary
        for view in [iconView, markView, trailingView] where view.contentTintColor != style.content { view.contentTintColor = style.content }
    }

    // MARK: size and layout

    private var singleLineHeight: CGFloat { LabelMetrics.lineHeight }

    /// The title as its label needs it: measured in the strong face by a real text field, so choosing a row never changes its width and
    /// the label never truncates (single line) or clips (wrapped: the height of every line it needs).
    private func titleSize() -> NSSize { LabelMetrics.fit(title, style: .bodyStrong, wrapWidth: wrapWidth) }

    private func shortcutWidth() -> CGFloat {
        guard let shortcutText, !shortcutText.isEmpty else { return 0 }
        return LabelMetrics.fit(shortcutText, style: .body).width
    }

    private struct Parts {
        var mark: CGFloat, icon: CGFloat, text: NSSize, shortcut: CGFloat, trailing: CGFloat
        /// Content width between the side padding, with a gap between neighbours.
        func width(gap: CGFloat, shortcutGap: CGFloat) -> CGFloat {
            var total: CGFloat = 0
            func add(_ part: CGFloat, spacing: CGFloat) { if part > 0 { total += (total > 0 ? spacing : 0) + part } }
            add(mark, spacing: gap); add(icon, spacing: gap); add(text.width, spacing: gap)
            add(shortcut, spacing: shortcutGap); add(trailing, spacing: gap)
            return total
        }
    }

    private func parts() -> Parts {
        Parts(mark: hasMark ? Self.glyphSide : 0,
              icon: hasIcon || reservesIconColumn ? Self.glyphSide : 0,
              text: titleSize(), shortcut: shortcutWidth(),
              trailing: hasTrailing || reservesTrailingColumn ? Self.glyphSide : 0)
    }

    override var intrinsicContentSize: NSSize {
        let parts = parts()
        let multiline = parts.text.height > singleLineHeight + 1
        let height = multiline ? parts.text.height + 2 * DesignTokens.Space.s2 : Self.height
        return NSSize(width: max(minimumWidth, 2 * horizontalPadding + parts.width(gap: contentGap, shortcutGap: Self.shortcutGap)), height: max(Self.height, height))
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    private func layoutContent() {
        let parts = parts()
        let side = Self.glyphSide, gap = contentGap
        func centred(_ height: CGFloat) -> CGFloat { ((bounds.height - height) / 2).rounded() }
        let trailingBlock = parts.trailing > 0 ? parts.trailing + gap : 0
        let shortcutBlock = parts.shortcut > 0 ? parts.shortcut + Self.shortcutGap : 0
        var x = horizontalPadding
        if choiceLayout == .segment {
            let content = parts.width(gap: gap, shortcutGap: Self.shortcutGap)
            x = max(horizontalPadding, ((bounds.width - content) / 2).rounded())
        }
        if parts.mark > 0 { markView.frame = NSRect(x: x, y: centred(side), width: side, height: side); x += side + gap }
        if parts.icon > 0 { iconView.frame = NSRect(x: x, y: centred(side), width: side, height: side); x += side + gap }
        let textHeight = max(parts.text.height, singleLineHeight)
        let available: CGFloat
        if choiceLayout == .segment {
            available = parts.text.width
        } else {
            available = max(0, bounds.width - horizontalPadding - x - shortcutBlock - trailingBlock)
        }
        titleLabel.frame = NSRect(x: x, y: centred(textHeight), width: available, height: textHeight)
        x += choiceLayout == .segment ? parts.text.width : available
        if parts.shortcut > 0 {
            let origin = choiceLayout == .segment ? x + Self.shortcutGap : bounds.width - horizontalPadding - trailingBlock - parts.shortcut
            shortcutLabel.frame = NSRect(x: origin, y: centred(singleLineHeight), width: parts.shortcut, height: singleLineHeight)
            x = origin + parts.shortcut
        }
        if parts.trailing > 0 {
            let origin = choiceLayout == .segment ? x + gap : bounds.width - horizontalPadding - side
            trailingView.frame = NSRect(x: origin, y: centred(side), width: side, height: side)
        }
    }

    // MARK: clicks and keys

    // A click anywhere on the row, including over its label and glyphs, is the button's own.
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }

    // VoiceOver moves the focus to a row by making it first responder; one below the fold of a scrolling panel must come into view with it.
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds) }
        return accepted
    }
    override var canBecomeKeyView: Bool { participatesInKeyLoop && super.canBecomeKeyView }

    /// A toggle flips once, an option becomes chosen (and never un-chooses), a command and a submenu row keep their state; then the
    /// action goes out and the handler already sees the new `state`. Every click path (mouse, Space, VoiceOver press, `performClick`)
    /// ends here, and the value is written explicitly, so whatever AppKit did to the cell on the way is overwritten, not added to.
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        guard isEnabled else { return false }
        let next: Bool
        switch kind {
        case .toggle: next = !chosen
        case .option: next = true
        case .command, .submenu: next = chosen
        }
        state = next ? .on : .off
        let sent = super.sendAction(action, to: target)
        // Should AppKit touch the cell after the action, the owned value wins.
        if (state == .on) != chosen { state = chosen ? .on : .off }
        return sent
    }

    override func keyDown(with event: NSEvent) {
        if let keyHandler, keyHandler(event) { return }
        // Space is a click on the focused button, handled here (not left to AppKit) so it is the same path in a key or a background window.
        if event.keyCode == 49, isEnabled, !event.hasShortcutModifier {
            performClick(nil)
            return
        }
        // Return and Enter are the window's default button's (a sheet's OK), never this button's.
        if event.keyCode == 36 || event.keyCode == 76, window?.defaultButtonCell != nil {
            nextResponder?.keyDown(with: event)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: accessibility

    private func syncRole() {
        setAccessibilityRole(Self.role(for: kind))
    }

    static func role(for kind: Kind) -> NSAccessibility.Role {
        switch kind {
        case .command: return .button
        case .option: return .radioButton
        case .toggle: return .checkBox
        case .submenu: return .menuButton
        }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { Self.role(for: kind) }

    override func accessibilityValue() -> Any? {
        switch kind {
        case .option, .toggle: return NSNumber(value: isChosen ? 1 : 0)
        case .command, .submenu: return nil
        }
    }

    /// VoiceOver's press is a click: it moves the state and sends the action through the same path as the mouse.
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }

    override func isAccessibilitySelected() -> Bool { kind == .option && isChosen }
    override func isAccessibilityEnabled() -> Bool { isEnabled }
    override func accessibilityChildren() -> [Any]? { [] }

    override var state: NSControl.StateValue {
        didSet {
            let was = chosen
            chosen = state == .on
            if was != chosen, kind == .option || kind == .toggle { NSAccessibility.post(element: self, notification: .valueChanged) }
        }
    }
}

// MARK: - Non-interactive label

/// A section header inside a choice panel: 20 pt, not a control, not focusable.
@MainActor
final class GlassChoiceLabel: NSView {
    let label = makeRowLabel(.bodyStrong)

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: GlassChoiceButton.height))
        label.stringValue = title
        label.textColor = DesignTokens.Palette.Text.secondary
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var title: String { label.stringValue }
    override func isAccessibilityEnabled() -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: LabelMetrics.fit(label.stringValue, style: .bodyStrong).width + 2 * GlassChoiceButton.padding, height: GlassChoiceButton.height)
    }

    override func layout() {
        super.layout()
        let height = LabelMetrics.lineHeight
        label.frame = NSRect(x: GlassChoiceButton.padding, y: ((bounds.height - height) / 2).rounded(),
                             width: max(0, bounds.width - 2 * GlassChoiceButton.padding), height: height)
    }

    func apply(_ accessibility: ChromeAccessibility) {
        label.textColor = accessibility.increaseContrast ? NSColor.labelColor : DesignTokens.Palette.Text.secondary
    }
}

// MARK: - Inline exclusive group

/// An inline exclusive set of option buttons on ONE glass plate: the category filter, the Resize / Crop / Limit mode, a settings radio set.
/// `selectedIndex` is the choice; assigning it moves the look and sends nothing. A user change (click, Space / Return, an arrow key)
/// sets it and sends `action` to `target` once. The group is one tab stop: only the chosen button is in the key-view loop, and Left,
/// Right, Up and Down move the choice (and the focus) to the next enabled button.
@MainActor
final class GlassChoiceGroup: NSView, ChromeFillable {
    struct Choice {
        var title: String
        var icon: FAIcon?
        var identifier: String?
        init(_ title: String, icon: FAIcon? = nil, identifier: String? = nil) { self.title = title; self.icon = icon; self.identifier = identifier }
    }

    let buttons: [GlassChoiceButton]
    let plate: GlassSurfaceView
    let axis: NSUserInterfaceLayoutOrientation
    weak var target: AnyObject?
    var action: Selector?
    private var enabledFlags: [Bool]

    /// -1 for no choice. Assigning never sends the action.
    var selectedIndex: Int {
        didSet {
            selectedIndex = min(max(-1, selectedIndex), buttons.count - 1)
            guard selectedIndex != oldValue || buttons.contains(where: { $0.isChosen != ($0 === chosenButton) }) else { return }
            applySelection()
            if selectedIndex != oldValue { NSAccessibility.post(element: self, notification: .valueChanged) }
        }
    }

    var isEnabled = true { didSet { applyEnabled() } }

    var accessibility: ChromeAccessibility {
        get { plate.accessibility }
        set {
            plate.accessibility = newValue
            for button in buttons { button.accessibility = newValue }
        }
    }

    var selectedTitle: String? { chosenButton?.title }
    private var chosenButton: GlassChoiceButton? { buttons.indices.contains(selectedIndex) ? buttons[selectedIndex] : nil }

    /// - Parameters:
    ///   - layout: `.segment` for a horizontal set with equal centred segments, `.row` for full-width rows.
    ///   - indicator: the glyph on each button (`.radio` for a radio set); `.none` leaves the fill, border and weight to say it.
    init(choices: [Choice], selectedIndex: Int = 0, layout: GlassChoiceButton.Layout = .segment, axis: NSUserInterfaceLayoutOrientation = .horizontal,
         indicator: GlassChoiceButton.Indicator = .none, accessibilityLabel: String, identifier: String, accessibility: ChromeAccessibility? = nil) {
        let accessibility = accessibility ?? .live
        let made = choices.enumerated().map { index, choice -> GlassChoiceButton in
            let button = GlassChoiceButton(title: choice.title, kind: .option, indicator: indicator, layout: layout)
            button.icon = choice.icon
            button.identifier = NSUserInterfaceItemIdentifier(choice.identifier ?? "\(identifier).\(index)")
            button.accessibility = accessibility
            return button
        }
        self.buttons = made
        self.axis = axis
        self.enabledFlags = Array(repeating: true, count: made.count)
        self.selectedIndex = min(max(-1, selectedIndex), made.count - 1)
        self.plate = GlassChrome.plate(made, identifier: identifier, accessibility: accessibility, axis: axis)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(plate)
        NSLayoutConstraint.activate([plate.leadingAnchor.constraint(equalTo: leadingAnchor), plate.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     plate.topAnchor.constraint(equalTo: topAnchor), plate.bottomAnchor.constraint(equalTo: bottomAnchor)])
        if axis == .horizontal, let first = made.first {
            // The segments share one width, the widest title's, so choosing one never moves the others.
            for button in made.dropFirst() { button.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true }
        }
        for (index, button) in made.enumerated() {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.tag = index
            button.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(accessibilityLabel)
        self.identifier = NSUserInterfaceItemIdentifier(identifier + ".group")
        applySelection()
    }

    convenience init(titles: [String], selectedIndex: Int = 0, layout: GlassChoiceButton.Layout = .segment, axis: NSUserInterfaceLayoutOrientation = .horizontal,
                     indicator: GlassChoiceButton.Indicator = .none, accessibilityLabel: String, identifier: String, accessibility: ChromeAccessibility? = nil) {
        self.init(choices: titles.map { Choice($0) }, selectedIndex: selectedIndex, layout: layout, axis: axis, indicator: indicator,
                  accessibilityLabel: accessibilityLabel, identifier: identifier, accessibility: accessibility)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { plate.fittingSize }

    // MARK: enabling

    func setEnabled(_ enabled: Bool, at index: Int) {
        guard enabledFlags.indices.contains(index) else { return }
        enabledFlags[index] = enabled
        applyEnabled()
    }

    func isEnabled(at index: Int) -> Bool { enabledFlags.indices.contains(index) && enabledFlags[index] && isEnabled }

    private func applyEnabled() {
        for (index, button) in buttons.enumerated() { button.isEnabled = isEnabled(at: index) }
        applyKeyLoop()
    }

    // MARK: selection

    private func applySelection() {
        for (index, button) in buttons.enumerated() where button.isChosen != (index == selectedIndex) { button.isChosen = index == selectedIndex }
        applyKeyLoop()
    }

    /// The chosen button is the group's one tab stop; with no choice (or a disabled one) the first enabled button is.
    private func applyKeyLoop() {
        let stop = buttons.indices.contains(selectedIndex) && isEnabled(at: selectedIndex) ? selectedIndex : buttons.indices.first { isEnabled(at: $0) }
        for (index, button) in buttons.enumerated() { button.participatesInKeyLoop = index == stop }
    }

    /// The user's choice: selects and sends the action once. Choosing the chosen button, or a disabled one, does nothing.
    func choose(_ index: Int) {
        guard buttons.indices.contains(index), isEnabled(at: index), index != selectedIndex else { return }
        let hadFocus = window?.firstResponder === chosenButton
        selectedIndex = index
        if hadFocus { window?.makeFirstResponder(buttons[index]) }
        if let action { NSApplication.shared.sendAction(action, to: target, from: self) }
    }

    @objc private func buttonClicked(_ sender: GlassChoiceButton) {
        guard let index = buttons.firstIndex(of: sender) else { return }
        if index == selectedIndex {
            sender.isChosen = true
            return
        }
        choose(index)
    }

    // MARK: keyboard

    /// Arrow keys step to the next enabled button (no wrap); Space chooses the focused one, and so do Return and Enter unless the window has a
    /// default button (a sheet's OK), which keeps them, as it does for a native radio group.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard !event.hasShortcutModifier else { return false }
        switch event.keyCode {
        case 123, 126: return step(-1)
        case 124, 125: return step(1)
        case 49: return chooseFocused()
        case 36, 76: return window?.defaultButtonCell == nil && chooseFocused()
        default: return false
        }
    }

    private func chooseFocused() -> Bool {
        guard let focused = window?.firstResponder as? GlassChoiceButton, let index = buttons.firstIndex(of: focused) else { return false }
        choose(index)
        return true
    }

    private func step(_ delta: Int) -> Bool {
        let start = selectedIndex < 0 ? (delta > 0 ? -1 : buttons.count) : selectedIndex
        var index = start + delta
        while buttons.indices.contains(index) {
            if isEnabled(at: index) { choose(index); return true }
            index += delta
        }
        return true
    }

    // MARK: accessibility

    override func accessibilityChildren() -> [Any]? { buttons }
    override func accessibilityValue() -> Any? { selectedTitle }
    override func accessibilitySelectedChildren() -> [Any]? { chosenButton.map { [$0] } ?? [] }
    override func isAccessibilityEnabled() -> Bool { isEnabled }
}

// MARK: - Floating panel window

/// The borderless, transparent window of a choice panel. It can be key (so the keyboard works) but is never main, never activates the
/// app, and keeps working above a modal parent.
@MainActor
final class GlassChoiceWindow: NSPanel {
    /// Offered every key-down before the window handles it; returning true consumes the event.
    var keyHandler: ((NSEvent) -> Bool)?
    /// Called for Escape when `keyHandler` did not take it.
    var escapeHandler: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        animationBehavior = .none
        isMovable = false
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { escapeHandler?() }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if keyHandler?(event) == true { return }
            if event.keyCode == 53 { escapeHandler?(); return }
        }
        super.sendEvent(event)
    }
}

// MARK: - Panel host

/// The panel's content root: an element of its own (a labelled group), and an app class so the accessibility audit judges its label. Its children
/// are the panel's real controls, from every plate in visual order (the rows scrolled out of view included), so the list is explicit rather than
/// whatever AppKit finds below the glass container.
private final class PanelRootView: NSView {
    weak var host: GlassPanelHost?

    override func accessibilityChildren() -> [Any]? {
        guard let host else { return super.accessibilityChildren() }
        return GlassAccessibility.elements(in: host.plates)
    }
}

/// The scrolling panel's document: flipped, so a panel taller than its window starts at its first row instead of its last.
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// The floating, transparent child panel that holds ONE `NSGlassEffectContainerView` with a vertical stack of group plates.
/// It is a child of the anchor's window while shown (so it moves with it), is placed by the pure `frame(contentSize:anchor:preferredEdge:visible:)`
/// (preferred edge, flips when there is no room, clamps into the visible screen, caps its height and scrolls), and goes away on Escape,
/// a click anywhere else in the app, the app resigning active, its parent closing, miniaturising, entering full screen or presenting a
/// sheet, or the anchor leaving its window. A click on the anchor itself only closes (and is consumed, so it cannot reopen).
@MainActor
final class GlassPanelHost: NSObject {
    enum Alignment { case leading, center, trailing }

    /// Where the panel ended up relative to the window it was opened from.
    enum Containment: Equatable {
        /// Horizontally inside the parent window (as much of it as the screen shows): the panel did not hang out past it.
        case parent
        /// Not contained, and legitimately so: no parent was given, the panel sits beside its anchor, or it is wider than the parent (or than
        /// the part of it the screen shows), so the screen's visible frame alone decided where it went.
        case screenFallback
    }

    struct Placement: Equatable {
        var frame: NSRect
        /// The edge of the anchor the panel sits on, in screen terms (`.minY` is below the anchor).
        var edge: NSRectEdge
        var scrolls: Bool
        var containment = Containment.screenFallback
    }

    /// The panel that is shown now; showing another closes it.
    static weak var current: GlassPanelHost?
    /// How many hosts have a click monitor installed right now: one per shown host, none once they are closed or released.
    private(set) static var installedMonitors = 0
    static let gap: CGFloat = 6
    static let screenMargin: CGFloat = DesignTokens.Space.s2
    /// When the room on a side is smaller than this the panel keeps this much (or its own height) and overlaps the anchor.
    static let minimumVisibleHeight: CGFloat = 3 * DesignTokens.Size.row

    private static func opposite(_ edge: NSRectEdge) -> NSRectEdge {
        switch edge {
        case .minY: return .maxY
        case .maxY: return .minY
        case .minX: return .maxX
        case .maxX: return .minX
        @unknown default: return .minY
        }
    }

    /// Where a panel of `contentSize` goes next to `anchor` (all in screen coordinates, y up).
    ///
    /// `container` is the window the anchor sits in. Above or below the anchor the panel stays inside it horizontally whenever it fits:
    /// the requested `alignment` first; if that overflows the container, the anchor's opposite edge (a panel opened from the right edge of
    /// a window ends at the anchor's trailing edge instead of hanging out past the window); if neither fits, clamped into the container.
    /// A panel wider than the container (or no container) keeps the screen rules alone, and the screen margin is always the final clamp.
    static func frame(contentSize: NSSize, anchor: NSRect, preferredEdge: NSRectEdge, visible: NSRect, alignment: Alignment = .leading,
                      container: NSRect? = nil) -> Placement {
        let area = visible.insetBy(dx: screenMargin, dy: screenMargin)
        let width = min(contentSize.width, area.width)
        func room(_ edge: NSRectEdge) -> CGFloat {
            switch edge {
            case .minY: return anchor.minY - gap - area.minY
            case .maxY: return area.maxY - (anchor.maxY + gap)
            case .minX: return anchor.minX - gap - area.minX
            case .maxX: return area.maxX - (anchor.maxX + gap)
            @unknown default: return 0
            }
        }
        let vertical = preferredEdge == .minY || preferredEdge == .maxY
        let needed = vertical ? contentSize.height : width
        var edge = preferredEdge
        if room(edge) < needed {
            let other = opposite(edge)
            if room(other) >= needed || room(other) > room(edge) { edge = other }
        }
        var size = NSSize(width: width, height: contentSize.height)
        var scrolls = false
        if vertical {
            let available = max(room(edge), min(contentSize.height, minimumVisibleHeight))
            if size.height > available { size.height = min(available, area.height); scrolls = true }
        } else if size.height > area.height {
            size.height = area.height
            scrolls = true
        }
        var origin = NSPoint.zero
        var containment = Containment.screenFallback
        if vertical {
            func originX(_ alignment: Alignment) -> CGFloat {
                switch alignment {
                case .leading: return anchor.minX
                case .center: return anchor.midX - size.width / 2
                case .trailing: return anchor.maxX - size.width
                }
            }
            origin.x = originX(alignment)
            if let container {
                // The container as far as the screen allows it: a window half off the screen is not room to put a panel.
                let low = max(container.minX, area.minX), high = min(container.maxX, area.maxX)
                if size.width <= high - low + 0.001 {
                    containment = .parent
                    func fits(_ x: CGFloat) -> Bool { x >= low - 0.001 && x + size.width <= high + 0.001 }
                    if !fits(origin.x) {
                        let others: [Alignment] = alignment == .leading ? [.trailing] : (alignment == .trailing ? [.leading] : [.leading, .trailing])
                        if let other = others.first(where: { fits(originX($0)) }) {
                            origin.x = originX(other)
                        } else {
                            origin.x = min(max(origin.x, low), high - size.width)
                        }
                    }
                }
            }
            origin.y = edge == .minY ? anchor.minY - gap - size.height : anchor.maxY + gap
        } else {
            origin.x = edge == .minX ? anchor.minX - gap - size.width : anchor.maxX + gap
            origin.y = anchor.maxY - size.height
        }
        origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
        origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
        return Placement(frame: NSRect(origin: origin, size: size), edge: edge, scrolls: scrolls, containment: containment)
    }

    // MARK: state

    let window = GlassChoiceWindow()
    let container: NSGlassEffectContainerView
    let identifier: String
    let accessibilityLabel: String
    private(set) var plates: [GlassSurfaceView] = []
    private(set) var isShown = false
    private(set) var contentSize = NSSize.zero
    private(set) var placement: Placement?
    private(set) weak var anchor: NSView?
    private(set) weak var parent: NSWindow?
    /// Whether the last `show` asked for the keyboard (a hover open never does).
    private(set) var requestedKey = false
    var willClose: (() -> Void)?
    var didClose: (() -> Void)?
    var alignment: Alignment = .leading
    var minimumWidth: CGFloat = 0 { didSet { minimumWidthConstraint.constant = minimumWidth; relayout() } }
    /// Test seam: replaces ordering the window front. It receives the panel and the window it belongs to.
    var presenter: ((GlassChoiceWindow, NSWindow?) -> Void)?
    /// Test seam: replaces the screen's visible frame.
    var visibleFrameOverride: NSRect?
    /// Test seam: replaces "the panel is the key window" when deciding whether closing hands the keyboard back.
    var keyStateProbe: (() -> Bool)?

    var keyHandler: ((NSEvent) -> Bool)? {
        get { window.keyHandler }
        set { window.keyHandler = newValue }
    }

    var accessibility: ChromeAccessibility = .live { didSet { pushAccessibility() } }

    private let stack = NSStackView()
    private let root = PanelRootView()
    private(set) var scrollView: NSScrollView?
    private var document: FlippedDocumentView?
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var plateConstraints: [NSLayoutConstraint] = []
    private let minimumWidthConstraint: NSLayoutConstraint
    private var displayObservation: DisplayOptions.Observation?
    private var tokens: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private weak var savedResponder: NSResponder?

    init(plates: [GlassSurfaceView], identifier: String, accessibilityLabel: String) {
        self.identifier = identifier
        self.accessibilityLabel = accessibilityLabel
        stack.orientation = .vertical
        stack.spacing = DesignTokens.Space.s2
        stack.alignment = .leading
        stack.distribution = .gravityAreas
        stack.translatesAutoresizingMaskIntoConstraints = false
        container = GlassChrome.container(around: stack, identifier: "GlassChoicePanel.\(identifier).container")
        minimumWidthConstraint = stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        super.init()
        minimumWidthConstraint.isActive = true
        window.contentView = root
        window.identifier = NSUserInterfaceItemIdentifier("GlassChoicePanel.\(identifier)")
        window.title = accessibilityLabel
        window.setAccessibilityLabel(accessibilityLabel)
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.group)
        root.setAccessibilityLabel(accessibilityLabel)
        window.escapeHandler = { [weak self] in self?.close() }
        root.host = self
        root.addSubview(container)
        layoutConstraints = pin(container, to: root)
        NSLayoutConstraint.activate(layoutConstraints)
        setPlates(plates)
        followDisplayOptions()
    }

    private func followDisplayOptions() {
        guard displayObservation == nil else { return }
        displayObservation = DisplayOptions.observe { [weak self] options in self?.accessibility = options.chrome }
    }

    // MARK: content

    /// Replaces the group plates (a menu panel rebuilds them on every open and when it drills into a submenu).
    func setPlates(_ new: [GlassSurfaceView]) {
        NSLayoutConstraint.deactivate(plateConstraints)
        plateConstraints = []
        for old in stack.arrangedSubviews {
            stack.removeArrangedSubview(old)
            old.removeFromSuperview()
        }
        plates = new
        for plate in new {
            stack.addArrangedSubview(plate)
            // One width for every plate in the panel, at a priority a lone fixed-width plate can outrank.
            let same = plate.widthAnchor.constraint(equalTo: stack.widthAnchor)
            same.priority = .defaultHigh
            same.isActive = true
            plateConstraints.append(same)
        }
        relayout()
    }

    private func relayout() {
        stack.layoutSubtreeIfNeeded()
        contentSize = stack.fittingSize
        if isShown { reposition() }
    }

    private func pin(_ view: NSView, to other: NSView) -> [NSLayoutConstraint] {
        [view.leadingAnchor.constraint(equalTo: other.leadingAnchor), view.trailingAnchor.constraint(equalTo: other.trailingAnchor),
         view.topAnchor.constraint(equalTo: other.topAnchor), view.bottomAnchor.constraint(equalTo: other.bottomAnchor)]
    }

    private func pushAccessibility() {
        func walk(_ view: NSView) {
            if let fillable = view as? ChromeFillable, !(view is GlassSurfaceView) { fillable.accessibility = accessibility }
            if let label = view as? GlassChoiceLabel { label.apply(accessibility) }
            for child in view.subviews { walk(child) }
        }
        for plate in plates {
            plate.accessibility = accessibility
            walk(plate)
        }
    }

    /// Brings a view of a scrolling panel into view (keyboard focus moving to a row below the fold).
    func reveal(_ view: NSView) {
        guard scrollView != nil else { return }
        view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -DesignTokens.Space.s1))
    }

    var scrolls: Bool { scrollView != nil }

    private func applyScroll(_ wanted: Bool) {
        guard wanted != (scrollView != nil) else { return }
        NSLayoutConstraint.deactivate(layoutConstraints)
        container.removeFromSuperview()
        scrollView?.removeFromSuperview()
        scrollView = nil
        document = nil
        if wanted {
            let scroll = NSScrollView()
            scroll.translatesAutoresizingMaskIntoConstraints = false
            // The rows are the root's own children (see PanelRootView), so the scroll area stays out of the accessibility tree: a row's parent is the panel.
            scroll.setAccessibilityElement(false)
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.verticalScrollElasticity = .allowed
            root.addSubview(scroll)
            let document = FlippedDocumentView(frame: NSRect(origin: .zero, size: contentSize))
            document.autoresizingMask = [.width]
            document.addSubview(container)
            scroll.documentView = document
            layoutConstraints = pin(scroll, to: root) + pin(container, to: document)
            scrollView = scroll
            self.document = document
        } else {
            root.addSubview(container)
            layoutConstraints = pin(container, to: root)
        }
        NSLayoutConstraint.activate(layoutConstraints)
    }

    // MARK: showing

    private func visibleFrame(for parent: NSWindow) -> NSRect {
        visibleFrameOverride ?? parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var anchorRect = NSRect.zero
    private var preferredEdge = NSRectEdge.minY

    private func screenAnchor(of view: NSView, in parent: NSWindow) -> NSRect {
        parent.convertToScreen(view.convert(anchorRect, to: nil))
    }

    /// `preferredEdge` is in screen terms whatever the anchor view's flippedness (NSPopover reads it in view coordinates, where an NSButton may or may not
    /// be flipped): `.minY` is below the anchor, `.maxY` above it, `.minX` left, `.maxX` right. The panel flips when the preferred side lacks room.
    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge edge: NSRectEdge, makeKey: Bool) {
        guard let parent = view.window else { return }
        if isShown { close(restoreFocus: false) }
        if let other = Self.current, other !== self { other.close() }
        anchor = view
        anchorRect = rect
        preferredEdge = edge
        self.parent = parent
        savedResponder = parent.firstResponder
        requestedKey = makeKey
        followDisplayOptions()
        pushAccessibility()
        window.level = parent.level
        isShown = true
        Self.current = self
        reposition()
        installObservers(on: parent)
        if let presenter {
            presenter(window, parent)
        } else {
            parent.addChildWindow(window, ordered: .above)
            if makeKey { window.makeKeyAndOrderFront(nil) } else { window.orderFront(nil) }
        }
        window.invalidateShadow()
    }

    private func reposition() {
        guard let anchor, let parent = anchor.window ?? self.parent else { return }
        let next = Self.frame(contentSize: contentSize, anchor: screenAnchor(of: anchor, in: parent), preferredEdge: preferredEdge,
                              visible: visibleFrame(for: parent), alignment: alignment, container: parent.frame)
        placement = next
        applyScroll(next.scrolls)
        if window.frame != next.frame { window.setFrame(next.frame, display: false) }
        document?.setFrameSize(NSSize(width: next.frame.width, height: contentSize.height))
    }

    /// Closes when the anchor has left its window or is hidden; follows it when it moved. Runs on every update of the parent window.
    func revalidate() {
        guard isShown else { return }
        guard let anchor, let parent, anchor.window === parent, !anchor.isHiddenOrHasHiddenAncestor else {
            close()
            return
        }
        reposition()
    }

    // MARK: dismissing

    /// A mouse press somewhere in the app while the panel is shown. Returns true when the press must be swallowed: a press on the anchor
    /// only closes, so the anchor's own handling cannot open the panel again.
    @discardableResult
    func handleMouseDown(in clicked: NSWindow?, at point: NSPoint) -> Bool {
        guard isShown, clicked !== window else { return false }
        var onAnchor = false
        if let anchor, let clicked, clicked === anchor.window {
            onAnchor = anchor.bounds.contains(anchor.convert(point, from: nil))
        }
        close()
        return onAnchor
    }

    private func installObservers(on parent: NSWindow) {
        removeObservers()
        let center = NotificationCenter.default
        // Posted on the main thread and handled on it, synchronously: the panel is gone before the window that triggered it moves on.
        func observe(_ name: Notification.Name, object: Any?, _ body: @escaping @MainActor (GlassPanelHost) -> Void) {
            tokens.append(center.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            })
        }
        observe(NSApplication.didResignActiveNotification, object: nil) { $0.close(restoreFocus: false) }
        observe(NSWindow.willCloseNotification, object: parent) { $0.close(restoreFocus: false) }
        observe(NSWindow.willMiniaturizeNotification, object: parent) { $0.close(restoreFocus: false) }
        observe(NSWindow.willEnterFullScreenNotification, object: parent) { $0.close(restoreFocus: false) }
        observe(NSWindow.willBeginSheetNotification, object: parent) { $0.close(restoreFocus: false) }
        observe(NSWindow.didUpdateNotification, object: parent) { $0.revalidate() }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.handleMouseDown(in: event.window, at: event.locationInWindow) }
            return consumed ? nil : event
        }
        if mouseMonitor != nil { Self.installedMonitors += 1 }
    }

    private func removeObservers() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            Self.installedMonitors -= 1
        }
        mouseMonitor = nil
    }

    /// Closes the panel. If it held the keyboard, the parent window gets it back and the responder that had it when the panel opened
    /// gets focus again (when it is still in that window).
    func close() { close(restoreFocus: true) }

    func close(restoreFocus restore: Bool) {
        guard isShown else { return }
        willClose?()
        isShown = false
        removeObservers()
        let hadKey = keyStateProbe?() ?? window.isKeyWindow
        if Self.current === self { Self.current = nil }
        let parent = self.parent
        parent?.removeChildWindow(window)
        window.orderOut(nil)
        if restore, hadKey, let parent {
            parent.makeKey()
            if let responder = savedResponder, (responder as? NSView)?.window === parent || responder === parent { parent.makeFirstResponder(responder) }
        }
        savedResponder = nil
        didClose?()
    }

    /// For an owner that replaces or drops this host: closes it without handing the keyboard anywhere, and stops following the display
    /// options. A host that is simply released does the equivalent in `deinit`, so no child window or click monitor outlives its owner.
    func invalidate() {
        close(restoreFocus: false)
        displayObservation?.invalidate()
        displayObservation = nil
    }

    deinit {
        MainActor.assumeIsolated {
            removeObservers()
            displayObservation?.invalidate()
            if isShown {
                parent?.removeChildWindow(window)
                window.orderOut(nil)
            }
        }
    }
}

// MARK: - Menu icons

/// The semantic Font Awesome glyph for a menu command, by action. A choice panel is app-owned UI, so a row for a mapped command draws this
/// (Pro, then the embedded Free vector, then the SF Symbol, through `ChromeIcons`) and ignores the item's own image: the Toolbox and the zoom's
/// Actual Size are copies of main-menu items, and the native menu bar keeps its SF Symbols, model, actions, wording and shortcuts untouched.
/// An action that is not listed keeps `item.image`. Keys are the real @objc selector names in App.swift, as in `MenuSymbols`.
@MainActor
enum MenuChoiceIcons {
    static let map: [Selector: FAIcon] = Dictionary(uniqueKeysWithValues: [
        // Keep and share
        ("saveHistory", FAIcon.boxArchive),            // the footer's Save
        ("exportFile", FAIcon.fileExport),             // a file leaving the app
        // Edit
        ("copyArtwork", FAIcon.copy),
        ("paste", FAIcon.paste),
        ("duplicate", FAIcon.clone),
        ("deleteSelection", FAIcon.trash),
        ("selectAll", FAIcon.objectGroup),             // every object drawn as one group
        // Capture
        ("screenSnap", FAIcon.crosshairs),             // the Snap button
        ("fullscreenSnap", FAIcon.display),            // the whole display
        ("frameSnap", FAIcon.frameViewfinder),         // the Snap Frame button
        ("resnap", FAIcon.cameraRotate),               // take the same snap again
        // Adjust the picture
        ("rotateCW", FAIcon.arrowRotateRight),
        ("flipH", FAIcon.leftRight),                   // a flip is a left-right exchange
        ("trimSnap", FAIcon.cropSimple),
        ("wipeSnap", FAIcon.broom),                    // the footer's Clear image
        // Pen settings
        ("toggleBezelFill:", FAIcon.shapes),           // filled shapes
        ("toggleBezelShadow:", FAIcon.layerGroup),     // a shadow is a layer behind
        ("chooseFont", FAIcon.font),
        // View
        ("toggleActualSize", FAIcon.magnifyingGlass),
    ].map { (Selector($0.0), $0.1) })

    static func icon(for item: NSMenuItem) -> FAIcon? { item.action.flatMap { map[$0] } }
}

// MARK: - Menu adapter

/// Fills a `GlassPanelHost` from an `NSMenu`, which stays the source of truth: every open runs the delegate's `menuNeedsUpdate` and
/// `menuWillOpen` and the menu's `update()` (validation, dynamic titles, state) BEFORE the panel takes the keyboard; separators split the
/// group plates, hidden items are skipped, a disabled item shows disabled, `state` is "chosen", `image` the leading image,
/// `keyEquivalent` the shortcut text, `toolTip` the accessibility help, and a submenu is a row that drills in (with a Back row first).
/// Choosing a row closes the panel first (so focus is back where it was), then performs the item through the menu, or, for a pop-up's
/// plain item, selects it in the pop-up and sends the pop-up's action.
@MainActor
final class MenuChoicePanel: NSObject {
    let menu: NSMenu
    let host: GlassPanelHost
    let identifier: String
    weak var popUp: NSPopUpButton?
    var minimumWidth: CGFloat { didSet { host.minimumWidth = minimumWidth } }
    private let kindFor: @MainActor (NSMenuItem) -> GlassChoiceButton.Kind
    /// The words a row shows (and VoiceOver reads) for an item. The item's own title by default; a menu whose face must stay short can have its
    /// panel say more (the zoom's computed row says "Fit, 83%" where the face says "83%"). The menu's titles are never changed.
    var rowTitle: @MainActor (NSMenuItem) -> String = { $0.title }
    /// The glyph a row shows for an item, first: a call site's own choice, ahead of `MenuChoiceIcons`. nil falls back to the map, and an item
    /// the map does not know keeps its own image.
    var rowIcon: @MainActor (NSMenuItem) -> FAIcon? = { _ in nil }
    private func glyph(for item: NSMenuItem) -> FAIcon? { rowIcon(item) ?? MenuChoiceIcons.icon(for: item) }
    /// The rows on screen now, top to bottom (the Back row first while inside a submenu).
    private(set) var rows: [GlassChoiceButton] = []
    private(set) var headers: [GlassChoiceLabel] = []
    /// The row the keyboard is on; nil until an arrow key (or a keyboard open) puts it on one.
    private(set) var focusedRow: GlassChoiceButton?
    /// The menus entered so far: the root first, then each submenu drilled into.
    private(set) var path: [NSMenu] = []
    private var itemForRow: [ObjectIdentifier: NSMenuItem] = [:]
    private var backRow: GlassChoiceButton?
    private var opened = false

    static func defaultKind(_ item: NSMenuItem) -> GlassChoiceButton.Kind {
        if item.submenu != nil { return .submenu }
        return item.state != .off ? .toggle : .command
    }

    init(menu: NSMenu, identifier: String, accessibilityLabel: String, kind: @escaping @MainActor (NSMenuItem) -> GlassChoiceButton.Kind = MenuChoicePanel.defaultKind,
         popUp: NSPopUpButton? = nil, minimumWidth: CGFloat = 240) {
        self.menu = menu
        self.identifier = identifier
        self.kindFor = kind
        self.popUp = popUp
        self.minimumWidth = minimumWidth
        host = GlassPanelHost(plates: [], identifier: identifier, accessibilityLabel: accessibilityLabel)
        super.init()
        host.minimumWidth = minimumWidth
        host.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        host.didClose = { [weak self] in self?.panelDidClose() }
    }

    /// For an owner that replaces or drops this panel: closes it and detaches its host. Releasing the panel does the same.
    func invalidate() { host.invalidate() }

    func item(for row: GlassChoiceButton) -> NSMenuItem? { itemForRow[ObjectIdentifier(row)] }
    var isBackRowShown: Bool { backRow != nil }

    // MARK: opening

    /// Rebuilds the rows from the menu's current state and shows the panel next to `view`. `keyboard: true` focuses the chosen row, else the
    /// first enabled one; `false` takes the keyboard with no row focused (the first arrow key focuses the chosen / first row).
    func present(relativeTo view: NSView, preferredEdge: NSRectEdge, keyboard: Bool) {
        guard view.window != nil else { return }
        if host.isShown { host.close(restoreFocus: false) }
        resetTypeAhead()
        path = [menu]
        refresh(menu)
        opened = true
        rebuild()
        host.show(relativeTo: view.bounds, of: view, preferredEdge: preferredEdge, makeKey: true)
        focusedRow = nil
        if keyboard { focus(chosenRow() ?? firstEnabledRow()) }
    }

    /// The delegate hooks and validation that make the menu current, in the order a real menu runs them.
    private func refresh(_ menu: NSMenu) {
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.delegate?.menuWillOpen?(menu)
        menu.update()
    }

    private func panelDidClose() {
        guard opened else { return }
        opened = false
        resetTypeAhead()
        for open in path.reversed() { open.delegate?.menuDidClose?(open) }
        path = []
        focusedRow = nil
    }

    // MARK: building

    private func rebuild() {
        guard let current = path.last else { return }
        itemForRow = [:]
        rows = []
        headers = []
        backRow = nil
        var groups: [[NSView]] = [[]]
        if path.count > 1 {
            let back = GlassChoiceButton(title: "Back", kind: .command, indicator: GlassChoiceButton.Indicator.none, layout: .row)
            back.icon = .chevronLeft
            back.identifier = NSUserInterfaceItemIdentifier("choice.back")
            wire(back)
            backRow = back
            rows.append(back)
            groups[0].append(back)
        }
        let items = current.items.filter { !$0.isSeparatorItem && !$0.isHidden && !$0.isAlternate && !$0.isSectionHeader }
        let hasImage = items.contains { $0.image != nil || glyph(for: $0) != nil }
        let hasTrailing = items.contains { item in
            let kind = kindFor(item)
            return kind == .option || kind == .toggle || kind == .submenu
        }
        for (index, item) in current.items.enumerated() {
            if item.isSeparatorItem {
                if !groups[groups.count - 1].isEmpty { groups.append([]) }
                continue
            }
            if item.isHidden || item.isAlternate { continue }
            if item.isSectionHeader {
                let header = GlassChoiceLabel(title: item.title)
                headers.append(header)
                groups[groups.count - 1].append(header)
                continue
            }
            let kind = kindFor(item)
            let row = GlassChoiceButton(title: rowTitle(item), kind: kind, layout: .row)
            row.identifier = NSUserInterfaceItemIdentifier("choice.\(index)")
            row.isEnabled = item.isEnabled
            if kind == .option || kind == .toggle { row.isChosen = item.state != .off }
            if let icon = glyph(for: item) { row.icon = icon } else { row.leadingImage = item.image }
            row.shortcutText = MenuShortcut.text(for: item)
            row.reservesIconColumn = hasImage
            row.reservesTrailingColumn = hasTrailing
            row.setAccessibilityHelp(item.toolTip)
            wire(row)
            itemForRow[ObjectIdentifier(row)] = item
            rows.append(row)
            groups[groups.count - 1].append(row)
        }
        let plates = groups.enumerated().filter { !$0.element.isEmpty }.map { number, views in
            GlassChrome.plate(views, identifier: "\(identifier).group.\(number)", accessibility: host.accessibility, axis: .vertical)
        }
        host.setPlates(plates)
    }

    private func wire(_ row: GlassChoiceButton) {
        row.target = self
        row.action = #selector(rowClicked(_:))
        row.accessibility = host.accessibility
    }

    @objc private func rowClicked(_ sender: GlassChoiceButton) { activate(sender) }

    // MARK: choosing

    /// Whether the item has an action of its own, as opposed to the internal one a pop-up gives every plain item.
    func hasOwnAction(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return false }
        if let popUp, item.target === popUp || item.target === popUp.cell || NSStringFromSelector(action) == "_popUpItemAction:" { return false }
        return true
    }

    /// Chooses a row: Back and submenu rows navigate; any other row closes the panel (focus is restored) and then performs its item.
    func activate(_ row: GlassChoiceButton) {
        guard row.isEnabled else { return }
        if row === backRow { goBack(); return }
        guard let item = item(for: row) else { return }
        if row.kind == .submenu, let submenu = item.submenu {
            drillIn(submenu, keyboard: window?.firstResponder === row)
            return
        }
        // The menu may have been rebuilt while the panel was open (a dynamic menu): then the row's item is no longer in any menu.
        let found = current(item)
        host.close()
        guard let (item, owner, index) = found else {
            // Nothing equivalent is left to perform through a menu; the item the user chose still carries its own action.
            if let action = item.action { _ = NSApplication.shared.sendAction(action, to: item.target, from: item) }
            return
        }
        if let popUp, owner === popUp.menu {
            if let action = item.action, hasOwnAction(item) {
                // Not performActionForItem: on a pop-up's menu AppKit also selects the item in the pop-up, and an item with its own
                // action (Actual Size) must leave the selection alone.
                _ = NSApplication.shared.sendAction(action, to: item.target, from: item)
            } else {
                popUp.select(item)
                _ = popUp.sendAction(popUp.action, to: popUp.target)
            }
        } else {
            owner.performActionForItem(at: index)
        }
    }

    /// The item to perform for a row, with the menu it is in and its index there. The row's own item when it is still in a menu; when the
    /// menu was rebuilt, the equivalent new item: the same action, represented object and title, else the only item with that action and
    /// represented object (a title that changed with the state).
    private func current(_ item: NSMenuItem) -> (NSMenuItem, NSMenu, Int)? {
        var menus: [NSMenu] = []
        for candidate in [item.menu] + path.reversed() + [menu] {
            if let candidate, !menus.contains(where: { $0 === candidate }) { menus.append(candidate) }
        }
        for owner in menus {
            let index = owner.index(of: item)
            if index >= 0 { return (item, owner, index) }
        }
        func sameObject(_ a: Any?, _ b: Any?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case let (x as NSObject, y as NSObject): return x.isEqual(y)
            default: return false
            }
        }
        guard let action = item.action else { return nil }
        for owner in menus {
            let same = owner.items.enumerated().filter { _, candidate in
                !candidate.isSeparatorItem && candidate.action == action && sameObject(candidate.representedObject, item.representedObject)
            }
            if let exact = same.first(where: { $0.element.title == item.title }) { return (exact.element, owner, exact.offset) }
            if same.count == 1 { return (same[0].element, owner, same[0].offset) }
        }
        return nil
    }

    private var window: NSWindow? { host.window }

    private func drillIn(_ submenu: NSMenu, keyboard: Bool) {
        resetTypeAhead()
        path.append(submenu)
        refresh(submenu)
        focusedRow = nil
        rebuild()
        if keyboard { focus(chosenRow() ?? rows.first { $0 !== backRow && $0.isEnabled } ?? firstEnabledRow()) }
    }

    func goBack() {
        guard path.count > 1, let left = path.popLast() else { return }
        resetTypeAhead()
        let parentItem = path.last?.items.first { $0.submenu === left }
        left.delegate?.menuDidClose?(left)
        focusedRow = nil
        rebuild()
        if let parentItem, let row = rows.first(where: { item(for: $0) === parentItem }) { focus(row) }
    }

    // MARK: keyboard

    private func enabledRows() -> [GlassChoiceButton] { rows.filter { $0.isEnabled } }
    private func firstEnabledRow() -> GlassChoiceButton? { enabledRows().first }
    /// The row a keyboard open starts on: the chosen OPTION. A toggle that is on (Filled Shapes in a command menu) is state, not a choice,
    /// so a command menu opens on its first enabled row, as native menus do.
    private func chosenRow() -> GlassChoiceButton? { rows.first { $0.isEnabled && $0.isChosen && $0.kind == .option } }

    func focus(_ row: GlassChoiceButton?) {
        focusedRow = row
        guard let row else { return }
        host.window.makeFirstResponder(row)
        host.reveal(row)
    }

    private func move(by delta: Int) {
        let candidates = enabledRows()
        guard !candidates.isEmpty else { return }
        guard let focused = focusedRow, let index = candidates.firstIndex(of: focused) else {
            focus(chosenRow() ?? candidates[0])
            return
        }
        focus(candidates[(index + delta + candidates.count) % candidates.count])
    }

    // MARK: type-ahead

    /// How long a typed prefix lives: a key typed later than this after the last one starts a new prefix.
    static let typeAheadInterval: TimeInterval = 1
    private var typedPrefix = ""
    private var typedAt = -TimeInterval.infinity

    private func isTyping(at time: TimeInterval) -> Bool { !typedPrefix.isEmpty && time - typedAt <= Self.typeAheadInterval }
    private func resetTypeAhead() { typedPrefix = ""; typedAt = -.infinity }

    /// The characters of a printable key: none for the arrows and other function keys (private-use characters) and control characters.
    private func printable(_ event: NSEvent) -> String? {
        guard let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) }) else { return nil }
        return characters
    }

    /// Type to select, as in a native menu: printable keys build a prefix (it restarts after a second) and focus the first enabled row whose
    /// title starts with it, ignoring case and diacritics. A new prefix searches on from the row after the focused one, wrapping, so a
    /// repeated letter cycles through the rows that start with it; a longer prefix keeps the focused row while it still matches.
    private func typeAhead(_ characters: String, at time: TimeInterval) {
        let continuing = isTyping(at: time)
        typedPrefix = (continuing ? typedPrefix : "") + characters
        typedAt = time
        let candidates = rows.filter { $0.isEnabled && $0 !== backRow }
        guard !candidates.isEmpty else { return }
        let current = focusedRow.flatMap { candidates.firstIndex(of: $0) }
        func search(_ prefix: String, from start: Int) -> GlassChoiceButton? {
            for offset in 0..<candidates.count {
                let row = candidates[((start + offset) % candidates.count + candidates.count) % candidates.count]
                if row.title.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil { return row }
            }
            return nil
        }
        if let match = search(typedPrefix, from: continuing ? (current ?? 0) : (current ?? -1) + 1) {
            focus(match)
        } else if typedPrefix.count > 1, Set(typedPrefix.lowercased()).count == 1, let match = search(String(typedPrefix.prefix(1)), from: (current ?? -1) + 1) {
            focus(match)   // the same letter again cycles
        }
    }

    // MARK: keys

    /// Up, Down, Tab, Shift-Tab, Home, End move the focus (wrapping, enabled rows only); Return, Space and keypad Enter choose the focused
    /// row; Right enters a submenu and Left or Escape leaves one; Escape at the top level is left to the panel, which closes. Any other
    /// printable key is type-to-select, and while a prefix is being typed (within a second) Space is part of it, not a choice.
    func handleKey(_ event: NSEvent) -> Bool {
        guard !event.hasShortcutModifier else { return false }
        let typing = isTyping(at: event.timestamp)
        if event.keyCode == 49, typing, let characters = printable(event) {
            typeAhead(characters, at: event.timestamp)
            return true
        }
        switch event.keyCode {
        case 125: resetTypeAhead(); move(by: 1)
        case 126: resetTypeAhead(); move(by: -1)
        case 48: resetTypeAhead(); move(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 115: resetTypeAhead(); focus(firstEnabledRow())
        case 119: resetTypeAhead(); focus(enabledRows().last)
        case 36, 76, 49:
            resetTypeAhead()
            if let focusedRow { activate(focusedRow) }
        case 124:
            resetTypeAhead()
            if let focusedRow, focusedRow.kind == .submenu { activate(focusedRow) }
        case 123:
            resetTypeAhead()
            if path.count > 1 { goBack() }
        case 53:
            resetTypeAhead()
            guard path.count > 1 else { return false }
            goBack()
        default:
            guard let characters = printable(event) else { return false }
            typeAhead(characters, at: event.timestamp)
        }
        return true
    }
}

// MARK: - Pop-up

/// A pop-up button whose choices are a glass `MenuChoicePanel`. It keeps `NSPopUpButton` as the model (items, selection, target and
/// action, the menu as the source of truth) and sends EVERY way of opening it to one panel: a click or Control-click, a right or other
/// button, Space, Return, Enter, Down and Up, `performClick`, VoiceOver's press and Show Menu, and the keyboard context-menu command.
/// None of them reaches AppKit's own pop-up tracking or `NSMenu.popUp`; `menu(for:)` is nil.
/// The face is the selected item's title (`faceTitle`) at 20 pt with a trailing chevron, drawn here, with no bezel of its own: it sits on a
/// plate or in a `ChromeFillCell`, which supply the hover and press fills.
@MainActor
class GlassPopUpButton: NSPopUpButton {
    var panelIdentifier = "Choices" { didSet { discardPanel() } }
    var panelLabel = "Choices" { didSet { discardPanel() } }
    private var choiceEdge = NSRectEdge.minY
    /// The edge of the button the panel prefers (below, by default); the host flips it when there is no room.
    override var preferredEdge: NSRectEdge {
        get { choiceEdge }
        set { choiceEdge = newValue }
    }
    var minimumPanelWidth: CGFloat = 240 { didSet { cachedPanel?.minimumWidth = minimumPanelWidth } }
    /// Overrides the default roles: a plain item is an option (the selected one is chosen), a submenu item a submenu row, and an item with
    /// its own action keeps `MenuChoicePanel.defaultKind`.
    var kind: (@MainActor (NSMenuItem) -> GlassChoiceButton.Kind)? { didSet { discardPanel() } }
    /// Passes through to the panel's `rowTitle`: what a row says for an item, when that is not the item's title.
    var rowTitle: (@MainActor (NSMenuItem) -> String)? { didSet { discardPanel() } }
    /// Passes through to the panel's `rowIcon`: the glyph a row shows for an item, ahead of the action map.
    var rowIcon: (@MainActor (NSMenuItem) -> FAIcon?)? { didSet { discardPanel() } }
    /// Test seam: replaces presenting the panel. It receives the panel and whether the keyboard opened it.
    var presentHandler: ((MenuChoicePanel, Bool) -> Void)?

    private var cachedPanel: MenuChoicePanel?
    private let chevronView = RowGlyphView(frame: .zero)

    override init(frame frameRect: NSRect, pullsDown flag: Bool) {
        super.init(frame: frameRect, pullsDown: flag)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isBordered = false
        focusRingType = .exterior
        DesignTokens.Typography.apply(.body, to: self)
        chevronView.image = ChromeIcons.resolve(.chevronDown, family: .solid, pointSize: GlassChoiceButton.glyphPointSize * 0.8).image
        chevronView.isHidden = false
        chevronView.contentTintColor = DesignTokens.Palette.Text.primary
        addSubview(chevronView)
        setAccessibilityRole(.popUpButton)
        // The pop-up is its own accessibility element: its name, value and actions are answered here, not by an ignored control's cell, which
        // knew neither the label a consumer set nor the panel it opens.
        setAccessibilityElement(true)
    }

    // MARK: the panel

    /// The panel for the current menu, rebuilt when the menu, the identifier or the label changes.
    var choicePanel: MenuChoicePanel {
        if let cachedPanel, cachedPanel.menu === menu { return cachedPanel }
        cachedPanel?.invalidate()
        let panel = MenuChoicePanel(menu: menu ?? NSMenu(), identifier: panelIdentifier, accessibilityLabel: panelLabel, kind: { [weak self] item in
            guard let self else { return MenuChoicePanel.defaultKind(item) }
            if let kind = self.kind { return kind(item) }
            if item.submenu != nil { return .submenu }
            return self.choicePanel.hasOwnAction(item) ? MenuChoicePanel.defaultKind(item) : .option
        }, popUp: self, minimumWidth: minimumPanelWidth)
        if let rowTitle { panel.rowTitle = rowTitle }
        if let rowIcon { panel.rowIcon = rowIcon }
        cachedPanel = panel
        return panel
    }

    // A different menu is a different panel: the old one goes away with it, not on the next open.
    override var menu: NSMenu? {
        didSet { menu?.font = DesignTokens.Typography.font(.body); if cachedPanel != nil, cachedPanel?.menu !== menu { discardPanel() } }
    }

    private func discardPanel() {
        cachedPanel?.invalidate()
        cachedPanel = nil
    }

    /// Opens the choices next to this button (or closes them when they are open). `keyboard: true` focuses the selected choice.
    func openChoices(keyboard: Bool) {
        guard isEnabled, window != nil, (menu?.numberOfItems ?? 0) > 0 else { return }
        let panel = choicePanel
        if panel.host.isShown, presentHandler == nil {
            panel.host.close()
            return
        }
        if let presentHandler { presentHandler(panel, keyboard) } else { panel.present(relativeTo: self, preferredEdge: preferredEdge, keyboard: keyboard) }
    }

    // MARK: every opening route

    override func mouseDown(with event: NSEvent) { openChoices(keyboard: false) }
    override func rightMouseDown(with event: NSEvent) { openChoices(keyboard: false) }
    override func otherMouseDown(with event: NSEvent) { openChoices(keyboard: false) }
    override func performClick(_ sender: Any?) { openChoices(keyboard: true) }
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    /// Space, Down and Up open the choices. Return and keypad Enter do too, unless the window has a default button (a sheet, a dialog):
    /// then they are left for it, as a native pop-up leaves them.
    override func keyDown(with event: NSEvent) {
        guard !event.hasShortcutModifier else { nextResponder?.keyDown(with: event); return }
        switch event.keyCode {
        case 49, 125, 126: openChoices(keyboard: true)
        case 36, 76:
            if window?.defaultButtonCell != nil { nextResponder?.keyDown(with: event) } else { openChoices(keyboard: true) }
        // Never AppKit's own pop-up key handling (type-ahead opens its native menu): the key goes up the responder chain.
        default: nextResponder?.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        openChoices(keyboard: true)
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard isEnabled else { return false }
        openChoices(keyboard: true)
        return true
    }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(accessibilityPerformShowMenu) || selector == #selector(accessibilityPerformPress) { return isEnabled }
        return super.isAccessibilitySelectorAllowed(selector)
    }

    @available(macOS 15.0, *)
    override func showContextMenuForSelection(_ sender: Any?) { openChoices(keyboard: true) }

    // MARK: face

    /// What the face shows; a subclass shortens or rewords it (the zoom pop-up shows only the percentage).
    var faceTitle: String { titleOfSelectedItem ?? "" }

    override var canBecomeKeyView: Bool { KeyboardNavigation.reaches(self) }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
    override func accessibilityValue() -> Any? { titleOfSelectedItem }
    override func accessibilityLabel() -> String? { super.accessibilityLabel() ?? panelLabel }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }

    override var isEnabled: Bool {
        didSet { chevronView.alphaValue = isEnabled ? 1 : StateStyles.disabledAlpha; needsDisplay = true; noteFocusRingMaskChanged() }
    }

    // The face is [facePadding][title][chevron column][facePadding]; the chevron glyph sits at the trailing end of its column. The defaults
    // are the roomy values of a choice row; a pop-up on a crowded bar (the zoom control) tightens both.
    static let defaultFacePadding = GlassChoiceButton.padding
    static let defaultChevronColumn = GlassChoiceButton.gap + GlassChoiceButton.glyphSide

    /// Space between the face's edge and its title (leading) and its chevron (trailing).
    var facePadding: CGFloat = GlassPopUpButton.defaultFacePadding { didSet { faceMetricsDidChange() } }
    /// Room the chevron takes at the trailing end, including its gap from the title.
    var chevronColumn: CGFloat = GlassPopUpButton.defaultChevronColumn { didSet { faceMetricsDidChange() } }

    private func faceMetricsDidChange() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    /// Where the title is drawn: the whole face between the padding and the chevron column, centred vertically.
    var titleRect: NSRect {
        let height = ceil(DesignTokens.Typography.font(.body).boundingRectForFont.height)
        return NSRect(x: facePadding, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - 2 * facePadding - chevronColumn), height: height)
    }

    /// Where the chevron glyph is: at the trailing end of its column.
    var chevronRect: NSRect {
        let side = min(GlassChoiceButton.glyphSide, chevronColumn)
        return NSRect(x: bounds.width - facePadding - side, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
    }

    override var intrinsicContentSize: NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: DesignTokens.Typography.font(.body)]
        let titles = (menu?.items.map(\.title) ?? []) + [faceTitle]
        let widest = titles.map { ceil(($0 as NSString).size(withAttributes: attributes).width) }.max() ?? 0
        return NSSize(width: 2 * facePadding + widest + chevronColumn, height: GlassChoiceButton.height)
    }

    override func layout() {
        super.layout()
        chevronView.frame = chevronRect
    }

    /// Exactly what `draw(_:)` draws with: the 20 pt body face, truncating at the tail.
    private func faceAttributes(color: NSColor? = nil) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [.font: DesignTokens.Typography.font(.body), .paragraphStyle: paragraph]
        if let color { attributes[.foregroundColor] = color }
        return attributes
    }

    /// The face's text as it is drawn right now: the title, its font, the room the text really needs, and the rectangle `draw(_:)` gives it
    /// (after the face padding and the chevron column, and no taller than the face itself). Read-only; the screenshot harness records it.
    var faceTextMetrics: (title: String, font: NSFont, needed: NSSize, available: NSRect) {
        let attributes = faceAttributes()
        let size = (faceTitle as NSString).size(withAttributes: attributes)
        return (faceTitle, DesignTokens.Typography.font(.body), NSSize(width: ceil(size.width), height: ceil(size.height)), titleRect.intersection(bounds))
    }

    /// Whether the title is drawn whole: it neither truncates nor is cut off vertically.
    var faceTextFits: Bool {
        let metrics = faceTextMetrics
        return metrics.needed.width <= metrics.available.width + 0.01 && metrics.needed.height <= metrics.available.height + 0.01
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = isEnabled ? DesignTokens.Palette.Text.primary : DesignTokens.Palette.Text.disabled
        (faceTitle as NSString).draw(in: titleRect, withAttributes: faceAttributes(color: color))
    }

    private var focusBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override var focusRingMaskBounds: NSRect { isEnabled && !focusBounds.isEmpty ? focusBounds : .zero }

    override func drawFocusRingMask() {
        guard isEnabled, !focusBounds.isEmpty else { return }
        NSColor.black.setFill()
        NSBezierPath(roundedRect: focusBounds, xRadius: StatePlate.radius, yRadius: StatePlate.radius).fill()
    }
}
