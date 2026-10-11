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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Same as `state == .on`; assigning it moves the selected look.
    var isChosen: Bool {
        get { state == .on }
        set { state = newValue ? .on : .off }
    }

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

    // The cell never draws a glyph: the leading icon is a subview, so the title, shortcut and glyphs lay out as one row.
    override func refreshIcon() {
        let glyph = (showsSelection ? selectedIcon : nil) ?? icon
        let family = showsSelection ? selectedFamily : iconFamily
        if let leadingImage {
            iconView.image = leadingImage
        } else if let glyph {
            iconView.image = ChromeIcons.resolve(glyph, family: family, pointSize: iconPointSize).image
        } else {
            iconView.image = nil
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

    private var singleLineHeight: CGFloat { ceil(DesignTokens.Typography.font(.bodyStrong).boundingRectForFont.height) }

    /// The title measured in the strong face, so choosing a row never changes its width.
    private func titleSize() -> NSSize {
        let text = title
        guard !text.isEmpty else { return .zero }
        let limit = wrapWidth ?? .greatestFiniteMagnitude
        let box = (text as NSString).boundingRect(with: NSSize(width: limit, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                 attributes: [.font: DesignTokens.Typography.font(.bodyStrong)])
        return NSSize(width: ceil(min(box.width, limit)), height: ceil(box.height))
    }

    private func shortcutWidth() -> CGFloat {
        guard let shortcutText, !shortcutText.isEmpty else { return 0 }
        return ceil((shortcutText as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.body)]).width)
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
        return NSSize(width: max(minimumWidth, 2 * Self.padding + parts.width(gap: Self.gap, shortcutGap: Self.shortcutGap)), height: max(Self.height, height))
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    private func layoutContent() {
        let parts = parts()
        let side = Self.glyphSide, gap = Self.gap
        func centred(_ height: CGFloat) -> CGFloat { ((bounds.height - height) / 2).rounded() }
        let trailingBlock = parts.trailing > 0 ? parts.trailing + gap : 0
        let shortcutBlock = parts.shortcut > 0 ? parts.shortcut + Self.shortcutGap : 0
        var x = Self.padding
        if choiceLayout == .segment {
            let content = parts.width(gap: gap, shortcutGap: Self.shortcutGap)
            x = max(Self.padding, ((bounds.width - content) / 2).rounded())
        }
        if parts.mark > 0 { markView.frame = NSRect(x: x, y: centred(side), width: side, height: side); x += side + gap }
        if parts.icon > 0 { iconView.frame = NSRect(x: x, y: centred(side), width: side, height: side); x += side + gap }
        let textHeight = max(parts.text.height, singleLineHeight)
        let available: CGFloat
        if choiceLayout == .segment {
            available = parts.text.width
        } else {
            available = max(0, bounds.width - Self.padding - x - shortcutBlock - trailingBlock)
        }
        titleLabel.frame = NSRect(x: x, y: centred(textHeight), width: min(available, max(parts.text.width, available)), height: textHeight)
        x += choiceLayout == .segment ? parts.text.width : available
        if parts.shortcut > 0 {
            let origin = choiceLayout == .segment ? x + Self.shortcutGap : bounds.width - Self.padding - trailingBlock - parts.shortcut
            shortcutLabel.frame = NSRect(x: origin, y: centred(singleLineHeight), width: parts.shortcut, height: singleLineHeight)
            x = origin + parts.shortcut
        }
        if parts.trailing > 0 {
            let origin = choiceLayout == .segment ? x + gap : bounds.width - Self.padding - side
            trailingView.frame = NSRect(x: origin, y: centred(side), width: side, height: side)
        }
    }

    // MARK: clicks and keys

    // A click anywhere on the row, including over its label and glyphs, is the button's own.
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { participatesInKeyLoop && super.canBecomeKeyView }

    /// A toggle flips, an option becomes chosen (and never un-chooses), a command and a submenu row leave their state alone; then the
    /// action goes out. Every click path (mouse, Space, VoiceOver press, `performClick`) ends here.
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        guard isEnabled else { return false }
        switch kind {
        case .toggle: isChosen.toggle()
        case .option: isChosen = true
        case .command, .submenu: break
        }
        return super.sendAction(action, to: target)
    }

    override func keyDown(with event: NSEvent) {
        if let keyHandler, keyHandler(event) { return }
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

    override func isAccessibilitySelected() -> Bool { kind == .option && isChosen }
    override func isAccessibilityEnabled() -> Bool { isEnabled }
    override func accessibilityChildren() -> [Any]? { [] }

    override var state: NSControl.StateValue {
        didSet {
            if state != oldValue, kind == .option || kind == .toggle { NSAccessibility.post(element: self, notification: .valueChanged) }
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

    override var intrinsicContentSize: NSSize {
        let width = ceil((label.stringValue as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.bodyStrong)]).width)
        return NSSize(width: width + 2 * GlassChoiceButton.padding, height: GlassChoiceButton.height)
    }

    override func layout() {
        super.layout()
        let height = ceil(DesignTokens.Typography.font(.bodyStrong).boundingRectForFont.height)
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

    /// Arrow keys step to the next enabled button (no wrap); Space, Return and Enter choose the focused one.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123, 126: return step(-1)
        case 124, 125: return step(1)
        case 49, 36, 76:
            guard let focused = window?.firstResponder as? GlassChoiceButton, let index = buttons.firstIndex(of: focused) else { return false }
            choose(index)
            return true
        default: return false
        }
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

/// The floating, transparent child panel that holds ONE `NSGlassEffectContainerView` with a vertical stack of group plates.
/// It is a child of the anchor's window while shown (so it moves with it), is placed by the pure `frame(contentSize:anchor:preferredEdge:visible:)`
/// (preferred edge, flips when there is no room, clamps into the visible screen, caps its height and scrolls), and goes away on Escape,
/// a click anywhere else in the app, the app resigning active, its parent closing, miniaturising, entering full screen or presenting a
/// sheet, or the anchor leaving its window. A click on the anchor itself only closes (and is consumed, so it cannot reopen).
@MainActor
final class GlassPanelHost: NSObject {
    enum Alignment { case leading, center, trailing }

    struct Placement: Equatable {
        var frame: NSRect
        /// The edge of the anchor the panel sits on, in screen terms (`.minY` is below the anchor).
        var edge: NSRectEdge
        var scrolls: Bool
    }

    /// The panel that is shown now; showing another closes it.
    nonisolated(unsafe) static weak var current: GlassPanelHost?
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
    static func frame(contentSize: NSSize, anchor: NSRect, preferredEdge: NSRectEdge, visible: NSRect, alignment: Alignment = .leading) -> Placement {
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
        if vertical {
            switch alignment {
            case .leading: origin.x = anchor.minX
            case .center: origin.x = anchor.midX - size.width / 2
            case .trailing: origin.x = anchor.maxX - size.width
            }
            origin.y = edge == .minY ? anchor.minY - gap - size.height : anchor.maxY + gap
        } else {
            origin.x = edge == .minX ? anchor.minX - gap - size.width : anchor.maxX + gap
            origin.y = anchor.maxY - size.height
        }
        origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
        origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
        return Placement(frame: NSRect(origin: origin, size: size), edge: edge, scrolls: scrolls)
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
    private let root = NSView()
    private var scrollView: NSScrollView?
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var plateConstraints: [NSLayoutConstraint] = []
    private let minimumWidthConstraint: NSLayoutConstraint
    private var displayObservation: DisplayOptions.Observation?
    private var tokens: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private weak var savedResponder: NSResponder?
    private var restoresFocus = true

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
        root.addSubview(container)
        layoutConstraints = pin(container, to: root)
        NSLayoutConstraint.activate(layoutConstraints)
        setPlates(plates)
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
        if wanted {
            let scroll = NSScrollView()
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.verticalScrollElasticity = .allowed
            root.addSubview(scroll)
            scroll.documentView = container
            let clip = scroll.contentView
            layoutConstraints = pin(scroll, to: root) + [container.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                                                         container.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
                                                         container.topAnchor.constraint(equalTo: clip.topAnchor)]
            scrollView = scroll
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

    /// `preferredEdge` is in the anchor view's own coordinates, like `NSPopover`: `.minY` of an unflipped view is below the rect, of a flipped view above it.
    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge edge: NSRectEdge, makeKey: Bool) {
        guard let parent = view.window else { return }
        if isShown { close(restoreFocus: false) }
        if let other = Self.current, other !== self { other.close() }
        anchor = view
        anchorRect = rect
        preferredEdge = view.isFlipped ? Self.opposite(edge) : edge
        self.parent = parent
        savedResponder = parent.firstResponder
        requestedKey = makeKey
        restoresFocus = true
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
                              visible: visibleFrame(for: parent), alignment: alignment)
        placement = next
        applyScroll(next.scrolls)
        if window.frame != next.frame { window.setFrame(next.frame, display: false) }
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
        func observe(_ name: Notification.Name, object: Any?, restoresFocus: Bool = false, _ body: @escaping @MainActor (GlassPanelHost) -> Void) {
            tokens.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
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
    }

    private func removeObservers() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
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

    deinit {
        MainActor.assumeIsolated {
            displayObservation?.invalidate()
        }
    }
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
    var popUp: NSPopUpButton?
    var minimumWidth: CGFloat { didSet { host.minimumWidth = minimumWidth } }
    private let kindFor: @MainActor (NSMenuItem) -> GlassChoiceButton.Kind
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

    func item(for row: GlassChoiceButton) -> NSMenuItem? { itemForRow[ObjectIdentifier(row)] }
    var isBackRowShown: Bool { backRow != nil }

    // MARK: opening

    /// Rebuilds the rows from the menu's current state and shows the panel next to `view`. `keyboard: true` focuses the chosen row, else the
    /// first enabled one; `false` takes the keyboard with no row focused (the first arrow key focuses the chosen / first row).
    func present(relativeTo view: NSView, preferredEdge: NSRectEdge, keyboard: Bool) {
        if host.isShown { host.close(restoreFocus: false) }
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
        let hasImage = items.contains { $0.image != nil }
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
            let row = GlassChoiceButton(title: item.title, kind: kind, layout: .row)
            row.identifier = NSUserInterfaceItemIdentifier("choice.\(index)")
            row.isEnabled = item.isEnabled
            if kind == .option || kind == .toggle { row.isChosen = item.state != .off }
            row.leadingImage = item.image
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

    private func hasOwnAction(_ item: NSMenuItem) -> Bool {
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
        let owner = item.menu ?? menu
        let index = owner.index(of: item)
        host.close()
        if let popUp, owner === popUp.menu, !hasOwnAction(item) {
            popUp.select(item)
            _ = popUp.sendAction(popUp.action, to: popUp.target)
        } else if index >= 0 {
            owner.performActionForItem(at: index)
        }
    }

    private var window: NSWindow? { host.window }

    private func drillIn(_ submenu: NSMenu, keyboard: Bool) {
        path.append(submenu)
        refresh(submenu)
        focusedRow = nil
        rebuild()
        if keyboard { focus(chosenRow() ?? rows.first { $0 !== backRow && $0.isEnabled } ?? firstEnabledRow()) }
    }

    func goBack() {
        guard path.count > 1, let left = path.popLast() else { return }
        let parentItem = path.last?.items.first { $0.submenu === left }
        left.delegate?.menuDidClose?(left)
        focusedRow = nil
        rebuild()
        if let parentItem, let row = rows.first(where: { item(for: $0) === parentItem }) { focus(row) }
    }

    // MARK: keyboard

    private func enabledRows() -> [GlassChoiceButton] { rows.filter { $0.isEnabled } }
    private func firstEnabledRow() -> GlassChoiceButton? { enabledRows().first }
    private func chosenRow() -> GlassChoiceButton? { rows.first { $0.isEnabled && $0.isChosen && $0 !== backRow } }

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

    /// Up, Down, Tab, Shift-Tab, Home, End move the focus (wrapping, enabled rows only); Return, Space and keypad Enter choose the focused
    /// row; Right enters a submenu and Left or Escape leaves one; Escape at the top level is left to the panel, which closes.
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: move(by: 1)
        case 126: move(by: -1)
        case 48: move(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 115: focus(firstEnabledRow())
        case 119: focus(enabledRows().last)
        case 36, 76, 49:
            if let focusedRow { activate(focusedRow) }
        case 124:
            if let focusedRow, focusedRow.kind == .submenu { activate(focusedRow) }
        case 123:
            if path.count > 1 { goBack() }
        case 53:
            guard path.count > 1 else { return false }
            goBack()
        default: return false
        }
        return true
    }
}
