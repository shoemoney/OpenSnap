import AppKit

@MainActor
protocol OriginalHelpBevelScheduling {
    func timer(interval: TimeInterval, repeats: Bool,
               action: @escaping @MainActor @Sendable () -> Bool) -> Timer
}

@MainActor
private struct NativeHelpBevelScheduler: OriginalHelpBevelScheduling {
    func timer(interval: TimeInterval, repeats: Bool,
               action: @escaping @MainActor @Sendable () -> Bool) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { timer in
            let keepRunning = MainActor.assumeIsolated { action() }
            if !keepRunning { timer.invalidate() }
        }
        // SKTopBevelWindow_setFadeTimer:, including mouse tracking/modal loops.
        for mode in [RunLoop.Mode.default, .modalPanel, .eventTracking] {
            RunLoop.main.add(timer, forMode: mode)
        }
        return timer
    }
}

private final class OriginalHelpPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OriginalHelpBevelView: NSView {
    static var font: NSFont { DesignTokens.Typography.font(.hud) }
    static let originalBodyHeight: CGFloat = 44
    static let heightAllowance: CGFloat = 3
    static let horizontalInset: CGFloat = 3
    /// Air above and below the text block: the line box of a 1.5x line height is exactly as tall as the measured text, so
    /// without it the first line sits on the plate edge and reads as clipped.
    static let verticalPadding = DesignTokens.Space.s2
    /// The plate hangs from the top of the host and its bottom corners join it; false when it has to sit inside the host
    /// instead, where all four corners are rounded.
    var joinsHost = true { didSet { needsDisplay = true } }
    private(set) var message = ""
    private(set) var attributedMessage = NSAttributedString(string: "")
    private(set) var textRect = NSRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var isOpaque: Bool { false }

    func update(message: String, width: CGFloat) -> CGFloat {
        self.message = message
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = 1.5
        attributedMessage = NSAttributedString(string: message, attributes: [
            .font: Self.font, .foregroundColor: DesignTokens.Palette.Overlay.hudText,
            .paragraphStyle: paragraph
        ])
        let textWidth = max(1, width - 2 * Self.horizontalInset)
        let measured = attributedMessage.boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let bodyHeight = max(Self.originalBodyHeight, ceil(measured.height) + 2 * Self.verticalPadding)
        let height = bodyHeight + Self.heightAllowance
        frame = NSRect(x: 0, y: 0, width: width, height: height)
        textRect = NSRect(x: Self.horizontalInset, y: (height - ceil(measured.height)) / 2,
                          width: textWidth, height: ceil(measured.height))
        setAccessibilityValue(message)
        needsDisplay = true
        return height
    }

    var backgroundPath: NSBezierPath {
        // SKTopBevelAttachmentBackgroundView_drawRect:. Mach-O floats at
        // 0x2609e0 / 0x260aec are -12 / +12: bottom corners join the host.
        var rect = bounds.insetBy(dx: 1, dy: 1)
        if joinsHost {
            rect.origin.y -= DesignTokens.Radius.lg
            rect.size.height += DesignTokens.Radius.lg
        }
        let path = NSBezierPath(roundedRect: rect, xRadius: DesignTokens.Radius.lg, yRadius: DesignTokens.Radius.lg)
        path.lineWidth = 2
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let path = backgroundPath
        DesignTokens.Palette.Overlay.hudFill.setFill()
        path.fill()
        DesignTokens.Palette.Overlay.hudStroke.setStroke()
        path.stroke()
        attributedMessage.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

/// Where the hint plate may sit inside its host, all in screen coordinates: the title bar and the two chrome bars it must never
/// cover, and the canvas viewport between them.
struct OriginalHelpBevelBands: Equatable {
    var content: NSRect
    var titleBar: NSRect
    var header: NSRect
    var footer: NSRect
    var viewport: NSRect
}

/// Which bar the hinted control lives in; a plate that has to sit inside the window goes under the top bar or over the bottom bar.
enum OriginalHelpBevelAnchor { case top, bottom }

/// Parent supplies local hover/modifier events and clears on focus, hide, sheet,
/// miniaturization and termination. This controller installs no event monitors.
@MainActor
final class OriginalHelpBevel {
    static let hoverDelay: TimeInterval = 0.25 // OriginalCropView_mouseEntered:.
    static let fadeInterval: TimeInterval = 0.02
    static let showStep: CGFloat = 0.15 // Mach-O double DAT_00260af8.
    static let hideStep: CGFloat = 0.1 // Negated DAT_00260b00.

    typealias ReduceMotion = () -> Bool
    typealias ScreenFrame = @MainActor (NSWindow) -> NSRect?
    typealias Bands = @MainActor (NSWindow) -> OriginalHelpBevelBands
    typealias Pointer = @MainActor () -> NSPoint
    /// Clear air between the plate and the bar or viewport edge it sits against when it is inside the window.
    static let insideMargin = DesignTokens.Space.s3

    var enabled = false { didSet { if !enabled { clear() } } }
    private(set) var displayedMessage: String?
    private(set) var panel: NSPanel?
    private weak var host: NSWindow?
    private let makePanel: () -> NSPanel
    private let scheduler: any OriginalHelpBevelScheduling
    private let reduceMotion: ReduceMotion
    private let screenFrame: ScreenFrame
    private let bands: Bands
    /// Where the pointer is when a hint starts; the harness points it at a bar to show each placement.
    var pointer: Pointer
    private var anchor = OriginalHelpBevelAnchor.top
    private var attachedAbove = false
    private var hoverOwner: String?
    private var hoverMessage: String?
    private var hoverReady = false
    private var modifierMessage: String?
    private var hoverTimer: Timer?
    private var fadeTimer: Timer?
    private var hoverGeneration = UUID()
    private var fadeGeneration = UUID()
    private var fadingIn = false
    private var stopped = false

    /// `reduceMotion` defaults to the system setting, `screenFrame` to the host's visible screen area, `bands` to the host's
    /// title bar and chrome bars found by identifier, and `pointer` to the mouse; tests force all four.
    /// OSN-061 replaces the Reduce Motion closure with the shared display options.
    init(host: NSWindow, makePanel: (() -> NSPanel)? = nil,
         scheduler: (any OriginalHelpBevelScheduling)? = nil,
         reduceMotion: ReduceMotion? = nil, screenFrame: ScreenFrame? = nil,
         bands: Bands? = nil, pointer: Pointer? = nil) {
        self.host = host
        self.reduceMotion = reduceMotion ?? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        self.screenFrame = screenFrame ?? { $0.screen?.visibleFrame }
        self.bands = bands ?? { Self.discoverBands(in: $0) }
        self.pointer = pointer ?? { NSEvent.mouseLocation }
        self.makePanel = makePanel ?? {
            OriginalHelpPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        }
        self.scheduler = scheduler ?? NativeHelpBevelScheduler()
    }

    private var canRender: Bool {
        guard enabled, !stopped, let host else { return false }
        return host.isVisible && host.isKeyWindow && !host.isMiniaturized && host.attachedSheet == nil
    }

    private func normalized(_ message: String?) -> String? {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return message
    }

    func hover(owner: String, message: String?) {
        guard canRender else { clear(); return }
        cancelHover()
        latchAnchor()
        hoverOwner = owner
        hoverMessage = normalized(message)
        hoverReady = false
        updateDisplay()
        guard hoverMessage != nil else { return }
        let generation = hoverGeneration
        hoverTimer = scheduler.timer(interval: Self.hoverDelay, repeats: false) { [weak self] in
            guard let self, self.hoverGeneration == generation else { return false }
            self.cancelHover()
            guard self.canRender else { self.clear(); return false }
            self.hoverReady = true
            self.updateDisplay()
            return false
        }
    }

    func exit(owner: String) {
        guard hoverOwner == owner else { return }
        resetMessages()
        updateDisplay() // Original matched mouse exit calls hideHelp (both slots).
    }

    func modifiers(message: String?) {
        guard canRender else { clear(); return }
        guard let message = normalized(message) else {
            resetMessages()
            updateDisplay() // Original hideHelp clears both slots, then fades out.
            return
        }
        latchAnchor()
        modifierMessage = message
        updateDisplay()
    }

    /// Lifecycle clearing is immediate, so hidden/unfocused hosts have no child
    /// left fading onscreen and no delayed message can reappear after a sheet.
    func clear() {
        resetMessages()
        cancelFade()
        displayedMessage = nil
        hidePanel()
    }

    func reposition() {
        guard canRender else { clear(); return }
        guard let message = displayedMessage, layout(message) else { return }
        syncAttachment()
    }

    func shutdown() {
        stopped = true
        enabled = false
        clear()
        panel?.close()
        panel = nil
    }

    private func resetMessages() {
        cancelHover()
        hoverOwner = nil; hoverMessage = nil; hoverReady = false
        modifierMessage = nil
    }

    private func updateDisplay() {
        guard canRender else { clear(); return }
        let message = modifierMessage ?? (hoverReady ? hoverMessage : nil)
        guard let message else {
            displayedMessage = nil
            fade(show: false)
            return
        }
        displayedMessage = message
        guard layout(message) else { return }
        syncAttachment()
        fade(show: true)
    }

    /// Attached below the host while the plate hangs above it, in front of it while it had to move inside; re-attached whenever
    /// a move or resize of the host flips that.
    private func syncAttachment() {
        guard let panel, let host else { return }
        let inside = (panel.contentView as? OriginalHelpBevelView)?.joinsHost == false
        if panel.parent != nil, attachedAbove != inside { host.removeChildWindow(panel) }
        if panel.parent == nil {
            attachedAbove = inside
            panel.orderFront(nil)
            host.addChildWindow(panel, ordered: inside ? .above : .below)
        }
    }

    private func layout(_ message: String) -> Bool {
        guard let host else { clear(); return false }
        // SKTopBevelAttachmentController_updateAttachedWindowSize:
        // DAT_002609d4 = 40, DAT_00260af0 = -80, read via Mach-O VM/file map.
        let width = host.frame.width - 80
        guard width.isFinite, width > 2 * OriginalHelpBevelView.horizontalInset,
              host.frame.minX.isFinite, host.frame.maxY.isFinite else { clear(); return false }
        if panel == nil {
            let panel = makePanel()
            panel.styleMask = [.borderless, .nonactivatingPanel]
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = false
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0
            panel.contentView = OriginalHelpBevelView(frame: .zero)
            self.panel = panel
        }
        guard let panel, let view = panel.contentView as? OriginalHelpBevelView else { return false }
        let height = view.update(message: message, width: width)
        // Hangs from the host's top edge. A host at the top of the screen leaves no room above it, and the plate would be
        // cut off by the screen edge; then it sits inside the window, in front of it, fully rounded, clear of the title bar
        // and both chrome bars.
        let top = host.frame.maxY
        view.joinsHost = true
        if let visible = screenFrame(host), top + height > visible.maxY {
            view.joinsHost = false
            panel.setFrame(insideFrame(host: host, width: width, height: height, visible: visible), display: false)
            return true
        }
        panel.setFrame(NSRect(x: host.frame.minX + 40, y: top, width: width, height: height), display: false)
        return true
    }

    private func latchAnchor() {
        guard let host else { return }
        anchor = pointer().y < bands(host).viewport.minY ? .bottom : .top
    }

    /// Centred in the window, inset by the margin from the top bar (hint for a top-bar control or the canvas) or from the bottom
    /// bar (hint for a bottom-bar control), then held inside the content rect and the visible screen.
    private func insideFrame(host: NSWindow, width: CGFloat, height: CGFloat, visible: NSRect) -> NSRect {
        let zones = bands(host)
        let margin = Self.insideMargin
        let fit = zones.content.intersection(visible)
        var y: CGFloat
        switch anchor {
        case .top:
            y = min(zones.viewport.maxY, zones.header.minY) - margin - height
        case .bottom:
            y = max(zones.viewport.minY, zones.footer.maxY) + margin
        }
        y = min(y, fit.maxY - height)
        y = max(y, fit.minY)
        var x = zones.content.midX - width / 2
        x = min(x, fit.maxX - width)
        x = max(x, fit.minX)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// The title bar is the strip above the layout rect; the bars are the views the editor chrome names; the viewport is its
    /// scroll view. Anything missing collapses to an empty strip at the edge of the content rect.
    static func discoverBands(in host: NSWindow) -> OriginalHelpBevelBands {
        let frame = host.frame
        let content = host.convertToScreen(host.contentLayoutRect)
        let titleBar = NSRect(x: frame.minX, y: content.maxY, width: frame.width, height: max(0, frame.maxY - content.maxY))
        func screenRect(of view: NSView) -> NSRect { host.convertToScreen(view.convert(view.bounds, to: nil)) }
        func find(_ matches: (NSView) -> Bool, in view: NSView?) -> NSView? {
            guard let view else { return nil }
            if matches(view) { return view }
            for sub in view.subviews { if let found = find(matches, in: sub) { return found } }
            return nil
        }
        let root = host.contentView
        let header = find({ $0.identifier?.rawValue == "OpenSnapHeader" }, in: root).map(screenRect)
            ?? NSRect(x: content.minX, y: content.maxY, width: content.width, height: 0)
        let footer = find({ $0.identifier?.rawValue == "OpenSnapFooter" }, in: root).map(screenRect)
            ?? NSRect(x: content.minX, y: content.minY, width: content.width, height: 0)
        let viewport = find({ $0 is NSScrollView }, in: root).map(screenRect)
            ?? NSRect(x: content.minX, y: footer.maxY, width: content.width, height: max(0, header.minY - footer.maxY))
        return OriginalHelpBevelBands(content: content, titleBar: titleBar, header: header, footer: footer, viewport: viewport)
    }

    private func fade(show: Bool) {
        cancelFade()
        guard let panel else { return }
        fadingIn = show
        // Reduce Motion: no ramp, the plate is simply there or gone.
        if reduceMotion() {
            if show { panel.alphaValue = 1 } else { hidePanel() }
            return
        }
        if show && panel.alphaValue >= 1 { return }
        if !show && panel.alphaValue <= 0 { hidePanel(); return }
        let generation = fadeGeneration
        fadeTimer = scheduler.timer(interval: Self.fadeInterval, repeats: true) { [weak self] in
            guard let self, self.fadeGeneration == generation else { return false }
            guard self.canRender else { self.clear(); return false }
            guard let panel = self.panel else { self.cancelFade(); return false }
            // Original fpret alpha is rounded to float before/after its double
            // step. Preserve that arithmetic (ten hide ticks, seven show ticks).
            let stepped = CGFloat(Float(Double(Float(panel.alphaValue)) +
                                        (self.fadingIn ? Double(Self.showStep) : -Double(Self.hideStep))))
            let alpha = self.fadingIn ? min(1, stepped) : max(0, stepped)
            panel.alphaValue = alpha
            if (self.fadingIn && alpha >= 1) || (!self.fadingIn && alpha <= 0) {
                self.cancelFade()
                if !self.fadingIn { self.hidePanel() }
                return false
            }
            return true
        }
    }

    private func cancelHover() {
        hoverGeneration = UUID()
        hoverTimer?.invalidate(); hoverTimer = nil
    }

    private func cancelFade() {
        fadeGeneration = UUID()
        fadeTimer?.invalidate(); fadeTimer = nil
    }

    private func hidePanel() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.alphaValue = 0
    }
}
