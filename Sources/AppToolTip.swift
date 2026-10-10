import AppKit
import ObjectiveC

/// App-owned tooltips. A system tooltip is drawn by AppKit at about 11 pt and its size cannot be changed, so the app's own
/// chrome shows a plate of its own at `Typography.body` (20 pt) instead.
///
/// How text gets here (the dynamic-text approach):
///  * `setText(_:for:)` is the one way to write a tooltip. It stores the text on the view, mirrors it into `accessibilityHelp`
///    (so VoiceOver keeps it) and clears the system `toolTip`, so the system tooltip never double-shows. Every live tooltip
///    (Size N, Snap / Snap Frame, the status line, Wipe stages, tool names) writes through it, so it always shows the latest text.
///  * `install(on:)` walks a view tree once and adopts every control that still carries a system `toolTip`.
///  * Safety net: while the pointer moves, every view under it is checked for a system `toolTip` written after install and
///    adopted before the system tooltip's own delay, so a straggler write is never shown at 11 pt.
///
/// Showing: one tracking area per installed root reports pointer moves; the view under the pointer is hit-tested and walked up
/// to the nearest view with text. After `hoverDelay` the plate appears below the control (above if there is no room), clamped
/// to the screen's visible frame and never over the control. Mouse exit, a click, scroll, key press, or a window resigning key
/// hides it. Under Reduce Motion it appears at once with no fade.
@MainActor
final class AppToolTip: NSObject {
    static let shared = AppToolTip()
    static let hoverDelay: TimeInterval = 0.7
    /// Moving from one control straight to another within `warmWindow` skips most of the wait, like a system tooltip.
    static let warmDelay: TimeInterval = 0.15, warmWindow: TimeInterval = 0.5
    static let maxWidth: CGFloat = 420, gap: CGFloat = 6, screenMargin: CGFloat = 4
    static let fadeDuration: TimeInterval = 0.12

    // MARK: Seams (tests and the harness replace these)
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// True when another hint already covers the view (the opt-in hover-hint bevel), so no tooltip shows for it.
    var suppressed: (NSView) -> Bool = { _ in false }
    var visibleFrame: (NSView) -> NSRect = { view in view.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900) }
    /// How the plate reaches the screen. Tests replace it so no panel is ever ordered onto the desktop.
    var present: (NSPanel) -> Void = { $0.orderFrontRegardless() }
    var delay: TimeInterval = AppToolTip.hoverDelay
    /// The screenshot harness pins a plate for a capture while it juggles window focus; nothing else turns this off.
    var dismissesOnWindowChanges = true

    // MARK: State
    private(set) var panel: NSPanel?
    private(set) var label: NSTextField?
    private(set) weak var target: NSView?
    private(set) weak var pendingTarget: NSView?
    private(set) var lastShowWasAnimated = false
    private var timer: Timer?
    private var lastDismissal = Date.distantPast
    /// After a click, scroll, key press or resign, the control that had the tooltip stays quiet until the pointer leaves it.
    private weak var lockedView: NSView?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    var isShown: Bool { target != nil }
    var isPending: Bool { timer != nil }
    var shownText: String? { target == nil ? nil : label?.stringValue }

    // MARK: Text storage
    nonisolated(unsafe) private static var textKey: UInt8 = 0
    nonisolated(unsafe) private static var watcherKey: UInt8 = 0

    /// The app tooltip text for a view, or nil.
    static func text(for view: NSView) -> String? {
        let text = objc_getAssociatedObject(view, &textKey) as? String
        return text?.isEmpty == false ? text : nil
    }

    /// Sets (or, for nil / empty, clears) the tooltip text of a view and keeps the system tooltip and VoiceOver in step.
    /// `mirrorsToAccessibility: false` is for a view whose spoken value already carries the same words (the status line).
    static func setText(_ text: String?, for view: NSView, mirrorsToAccessibility: Bool = true) {
        let previous = Self.text(for: view)
        let new = text?.isEmpty == false ? text : nil
        objc_setAssociatedObject(view, &textKey, new, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        if view.toolTip != nil { view.toolTip = nil }
        if mirrorsToAccessibility {
            let help = view.accessibilityHelp()
            // Never overwrite help the control already speaks on its own: only empty help or our own earlier text is replaced.
            if help == nil || help == "" || help == previous { view.setAccessibilityHelp(new) }
        }
        shared.refresh(view)
    }

    // MARK: Installing
    /// Moves every system tooltip under `root` into the app registry and arms pointer tracking for it. Idempotent.
    static func install(on root: NSView) {
        adoptTree(root)
        shared.ensureMonitoring()
        if watcher(for: root) == nil {
            let watcher = Watcher(root: root)
            objc_setAssociatedObject(root, &watcherKey, watcher, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            watcher.arm()
        }
    }

    static func watcher(for root: NSView) -> NSObject? { objc_getAssociatedObject(root, &watcherKey) as? NSObject }

    private static func adoptTree(_ view: NSView) {
        adopt(view)
        for child in view.subviews { adoptTree(child) }
    }

    /// Adopts a view's system tooltip (and, for a segmented control, its per-segment tooltips) as app text.
    static func adopt(_ view: NSView) {
        if let segmented = view as? NSSegmentedControl {
            var segmentTip: String?
            for index in 0..<segmented.segmentCount {
                if segmentTip == nil, let tip = segmented.toolTip(forSegment: index), !tip.isEmpty { segmentTip = tip }
                segmented.setToolTip(nil, forSegment: index)
            }
            if text(for: view) == nil, view.toolTip?.isEmpty != false, let segmentTip { setText(segmentTip, for: view); return }
        }
        if let tip = view.toolTip, !tip.isEmpty { setText(tip, for: view) }
    }

    // MARK: Hover state machine
    /// The view under the pointer, or nil when it left. Called by a root's tracking area; tests call it directly.
    func hover(over view: NSView?) {
        if let view, view === target || view === pendingTarget || view === lockedView { return }
        lockedView = nil
        let warm = target != nil || Date().timeIntervalSince(lastDismissal) < Self.warmWindow
        dismiss()
        guard let view, let text = Self.text(for: view), !text.isEmpty, !suppressed(view) else { return }
        pendingTarget = view
        let wait = warm ? min(Self.warmDelay, delay) : delay
        let fire = Timer(timeInterval: wait, repeats: false) { [weak self, weak view] _ in
            MainActor.assumeIsolated {
                guard let self, let view, self.pendingTarget === view else { return }
                self.show(for: view)
            }
        }
        RunLoop.main.add(fire, forMode: .common)
        timer = fire
    }

    /// Shows the plate for `view` now, ignoring the hover delay.
    func show(for view: NSView) {
        timer?.invalidate(); timer = nil; pendingTarget = nil
        guard let window = view.window, let text = Self.text(for: view), !text.isEmpty else { dismiss(); return }
        let plate = ensurePanel()
        let anchor = Self.anchorRect(of: view, in: window)
        let size = layout(text)
        plate.setFrame(Self.frame(size: size, anchor: anchor, visible: visibleFrame(view)), display: false)
        plate.appearance = window.effectiveAppearance
        plate.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        plate.contentView?.needsDisplay = true
        target = view
        lastShowWasAnimated = !reduceMotion()
        plate.alphaValue = lastShowWasAnimated ? 0 : 1
        present(plate)
        if lastShowWasAnimated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                plate.animator().alphaValue = 1
            }
        }
    }

    func dismiss(lockingView: Bool = false) {
        if lockingView { lockedView = target ?? pendingTarget }
        timer?.invalidate(); timer = nil; pendingTarget = nil
        if target != nil { lastDismissal = Date() }
        target = nil
        panel?.orderOut(nil)
    }

    /// A live text change while the plate is up (or about to be) follows the new text; clearing it hides the plate.
    private func refresh(_ view: NSView) {
        guard view === target else { return }
        if Self.text(for: view) == nil { dismiss() } else { show(for: view) }
    }

    // MARK: Geometry
    static func anchorRect(of view: NSView, in window: NSWindow) -> NSRect {
        // visibleRect can run far past a control's own bounds inside glass containers, so it only ever narrows the bounds.
        let clipped = view.bounds.intersection(view.visibleRect)
        let local = clipped.isNull || clipped.isEmpty ? view.bounds : clipped
        return window.convertToScreen(view.convert(local, to: nil))
    }

    /// Below the anchor, else above, else beside it; always inside `visible` (less a margin) and never over the anchor.
    static func frame(size: NSSize, anchor: NSRect, visible: NSRect) -> NSRect {
        let area = visible.insetBy(dx: screenMargin, dy: screenMargin)
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { max(low, min(value, high)) }
        let x = clamp(anchor.midX - size.width / 2, area.minX, area.maxX - size.width)
        let below = anchor.minY - gap - size.height, above = anchor.maxY + gap
        if below >= area.minY { return NSRect(origin: NSPoint(x: x, y: below), size: size) }
        if above + size.height <= area.maxY { return NSRect(origin: NSPoint(x: x, y: above), size: size) }
        var sideX = anchor.maxX + gap
        if sideX + size.width > area.maxX { sideX = anchor.minX - gap - size.width }
        return NSRect(x: clamp(sideX, area.minX, area.maxX - size.width),
                      y: clamp(anchor.midY - size.height / 2, area.minY, area.maxY - size.height), width: size.width, height: size.height)
    }

    // MARK: Plate
    private static let padding = NSSize(width: DesignTokens.Space.s3, height: DesignTokens.Space.s2)

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let plate = AppToolTipPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        plate.isOpaque = false
        plate.backgroundColor = .clear
        plate.hasShadow = true
        plate.ignoresMouseEvents = true
        plate.hidesOnDeactivate = false
        plate.isReleasedWhenClosed = false
        plate.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        plate.setAccessibilityElement(false)
        let view = AppToolTipPlateView()
        let text = NSTextField(wrappingLabelWithString: "")
        text.font = DesignTokens.Typography.font(.body)
        text.textColor = DesignTokens.Palette.Text.primary
        text.maximumNumberOfLines = 0
        text.lineBreakMode = .byWordWrapping
        text.setAccessibilityElement(false)
        view.addSubview(text)
        plate.contentView = view
        panel = plate; label = text
        return plate
    }

    /// Sizes the plate to the wrapped text (max width `maxWidth`) and returns the plate size.
    private func layout(_ text: String) -> NSSize {
        guard let label, let plate = panel else { return .zero }
        label.stringValue = text
        let available = Self.maxWidth - 2 * Self.padding.width
        // Measured with the label's own cell, so the frame always fits what the field really wraps to.
        func measure(_ width: CGFloat) -> NSSize {
            label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)) ?? .zero
        }
        // Narrow to the widest wrapped line, then measure again at that width: a tighter column can wrap onto one more line.
        let first = measure(available)
        let width = min(available, ceil(first.width) + 2)
        let textSize = NSSize(width: width, height: ceil(max(first.height, measure(width).height)))
        let size = NSSize(width: textSize.width + 2 * Self.padding.width, height: textSize.height + 2 * Self.padding.height)
        label.frame = NSRect(origin: NSPoint(x: Self.padding.width, y: Self.padding.height), size: textSize)
        plate.setContentSize(size)
        return size
    }

    // MARK: Dismissal sources
    private func ensureMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.dismiss(lockingView: true) }
            return event
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResignMainNotification, NSWindow.willCloseNotification,
                     NSWindow.didMiniaturizeNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.dismissesOnWindowChanges == true { self?.dismiss(lockingView: true) } }
            })
        }
    }

    // MARK: Pointer tracking
    /// One per installed root: a tracking area that reports where the pointer is, and walks up from the view under it.
    @MainActor
    final class Watcher: NSObject {
        private weak var root: NSView?
        private var area: NSTrackingArea?

        init(root: NSView) { self.root = root }

        func arm() {
            guard let root, area == nil else { return }
            let tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                          owner: self, userInfo: nil)
            root.addTrackingArea(tracking)
            area = tracking
        }

        /// The nearest view at or above the pointer that has tooltip text, adopting late system tooltips on the way.
        func tipView(for event: NSEvent) -> NSView? {
            guard let root else { return nil }
            let point = root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            var view = root.hitTest(point)
            while let current = view {
                AppToolTip.adopt(current)
                if AppToolTip.text(for: current) != nil { return current }
                if current === root { break }
                view = current.superview
            }
            return nil
        }

        // An NSTrackingArea owner is sent `mouseEntered:`, `mouseExited:` and `mouseMoved:`. Swift would export these as
        // `mouseEnteredWith:` and so on, so the selectors are spelled out; a mismatch is an unrecognized-selector crash on first hover.
        @objc(mouseMoved:) func mouseMoved(with event: NSEvent) { AppToolTip.shared.hover(over: tipView(for: event)) }
        @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { AppToolTip.shared.hover(over: tipView(for: event)) }
        @objc(mouseExited:) func mouseExited(with event: NSEvent) { AppToolTip.shared.hover(over: nil) }
    }
}

private final class AppToolTipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A solid plate: content surface, 1 pt separator border, `Radius.md` corners. Not a material, so it reads the same over anything.
private final class AppToolTipPlateView: NSView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: DesignTokens.Radius.md, yRadius: DesignTokens.Radius.md)
        DesignTokens.Palette.Surface.content.setFill(); path.fill()
        DesignTokens.Palette.separator.setStroke(); path.lineWidth = 1; path.stroke()
    }
}
