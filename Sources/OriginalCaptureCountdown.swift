import AppKit
import CoreGraphics

@MainActor
protocol CaptureCountdownPresenting: AnyObject, Sendable {
    func start(rect: NSRect, parent: NSWindow?, delay: Double,
               cue: @escaping () -> Void, completion: @escaping () -> Void)
    func cancel()
}

/// Native presentation for snapTimer: (0x23d28). Capture and sound remain parent-owned.
@MainActor
final class OriginalCaptureCountdown: CaptureCountdownPresenting {
    typealias Flag = @MainActor () -> Bool
    /// Speaks one numeral to VoiceOver.
    typealias Announce = @MainActor (String) -> Void
    typealias PanelFactory = @MainActor (NSRect) -> NSPanel
    typealias Images = @MainActor (Int) -> NSImage?
    typealias ScreenFrames = @MainActor () -> [NSRect]
    typealias Cancellation = @MainActor () -> Void
    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Cancellation

    private final class Session {
        var timing: OriginalCaptureTiming
        let cue: () -> Void
        let completion: () -> Void
        weak var parent: NSWindow?
        var panel: NSPanel?
        var imageView: NSImageView?
        /// The numeral on screen, so a display-option change can redraw it.
        var number = 3
        var cancelTimer: Cancellation?
        let reduceMotion: Bool
        var announced: Int?
        var advancing = false
        var registering = false
        var completionPending = false
        init(timing: OriginalCaptureTiming, reduceMotion: Bool, cue: @escaping () -> Void, completion: @escaping () -> Void) {
            self.timing = timing; self.reduceMotion = reduceMotion; self.cue = cue; self.completion = completion
        }
    }

    private let panelFactory: PanelFactory
    private let images: Images
    private let scheduler: Scheduler
    private let screenFrames: ScreenFrames
    private let reduceMotion: Flag
    private let announce: Announce
    private var session: Session?
    private var displayObservation: DisplayOptions.Observation?
    private var cleaningUp = false
    private var lifetime: OriginalCaptureCountdown?
    var isRunning: Bool { session != nil }

    /// Frames and rect use AppKit global bottom-left coordinates. Supply VISIBLE
    /// screen frames in NSScreen order. Test factories must suppress window ordering.
    /// `reduceMotion`, `increaseContrast` and `announce` default to `DisplayOptions.current` and the system; tests force them.
    /// Reduce Motion is read once per countdown so a setting flipped mid-count cannot change how that count looks; Increase
    /// Contrast redraws the numeral on screen the moment it changes.
    init(panelFactory: PanelFactory? = nil, images: Images? = nil,
         scheduler: Scheduler? = nil, screenFrames: ScreenFrames? = nil,
         reduceMotion: Flag? = nil, increaseContrast: Flag? = nil, announce: Announce? = nil) {
        self.reduceMotion = reduceMotion ?? { DisplayOptions.current.reduceMotion }
        self.announce = announce ?? Self.postAnnouncement
        let increaseContrast = increaseContrast ?? { DisplayOptions.current.increaseContrast }
        self.panelFactory = panelFactory ?? { rect in
            OriginalCountdownPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: true)
        }
        self.images = images ?? { number in
            Self.numeral(number, highContrast: increaseContrast())
        }
        self.scheduler = scheduler ?? Self.schedule
        self.screenFrames = screenFrames ?? { NSScreen.screens.map(\.visibleFrame) }
    }

    func start(rect: NSRect, parent: NSWindow?, delay: Double,
               cue: @escaping () -> Void, completion: @escaping () -> Void) {
        // Original startCountdownForRect: (0x23876) ignores a second active start.
        guard session == nil, !cleaningUp, Self.valid(rect, allowZero: true),
              let timing = OriginalCaptureTiming(delay: delay) else { return }
        let request = Session(timing: timing, reduceMotion: reduceMotion(), cue: cue, completion: completion)
        session = request
        lifetime = self
        if timing.total == 0 { finish(request, complete: true); return }

        let initialImage = images(3)
        guard session === request else { return }
        speak(3, in: request)
        guard session === request else { return }
        let frames = screenFrames().filter { Self.valid($0) }
        guard session === request else { return }
        // Missing resources/displays must not strand the parent's capture phase.
        // Timing still runs, without inventing replacement artwork or geometry.
        if let image = initialImage, Self.valid(NSRect(origin: .zero, size: image.size)), !frames.isEmpty {
            let frame = Self.placement(rect: rect, imageSize: image.size, screenFrames: frames)
            let panel = panelFactory(frame)
            guard session === request else { panel.orderOut(nil); panel.close(); return }
            request.panel = panel
            panel.isReleasedWhenClosed = false
            panel.setFrame(frame, display: false)
            panel.alphaValue = request.reduceMotion ? 1 : 0
            panel.backgroundColor = .clear
            panel.isOpaque = false
            // A window read without a title is just "window"; the numeral panel has no title bar, so this is for assistive clients only.
            panel.title = "Capture countdown"; panel.isExcludedFromWindowsMenu = true
            panel.isMovable = false
            panel.isMovableByWindowBackground = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 100)
            panel.hidesOnDeactivate = false
            panel.canHide = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.animationBehavior = .none
            let view = OriginalCountdownImageView(frame: NSRect(origin: .zero, size: frame.size))
            view.imageScaling = .scaleNone
            view.imageAlignment = .alignCenter
            view.image = image
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.image)
            view.setAccessibilityLabel("Capture countdown: 3")
            request.imageView = view
            displayObservation = DisplayOptions.observe { [weak self, weak request] _ in
                guard let self, let request, self.session === request, let view = request.imageView else { return }
                view.image = self.images(request.number)
            }
            panel.contentView = view
            request.parent = parent
            if let parent { parent.addChildWindow(panel, ordered: .above) }
            else { panel.orderFrontRegardless() }
            guard session === request else { return }
        }
        request.registering = true
        let cancellation = scheduler(OriginalCaptureTiming.timerInterval) { [weak self, weak request] in
            guard let self, let request else { return }
            self.advance(request)
        }
        // An injected scheduler may fire/cancel synchronously during registration.
        request.registering = false
        if session === request {
            request.cancelTimer = cancellation
            if request.completionPending { finish(request, complete: true) }
        } else { cancellation() }
    }

    /// The plate is 140 x 140: a rounded HUD square with the digit centred on its ink, not on the font's line box.
    static let numeralSize = NSSize(width: 140, height: 140)
    static var numeralFontSize: CGFloat { DesignTokens.Typography.font(.countdown).pointSize }
    /// Plate opacity over the screen; Increase Contrast darkens it.
    static func plateAlpha(highContrast: Bool) -> CGFloat { highContrast ? 0.8 : 0.55 }
    static let shadowOffset = NSSize(width: 0, height: -2)

    private static func numeralLine(_ number: Int) -> CTLine {
        let text = NSAttributedString(string: String(number), attributes: [
            .font: DesignTokens.Typography.font(.countdown)])
        return CTLineCreateWithAttributedString(text)
    }

    /// Where the digit's glyph outline sits inside the plate, and the baseline origin that puts it there.
    static func numeralLayout(_ number: Int) -> (ink: NSRect, origin: NSPoint)? {
        guard (1...3).contains(number) else { return nil }
        let bounds = CTLineGetBoundsWithOptions(numeralLine(number), .useGlyphPathBounds)
        let origin = NSPoint(x: numeralSize.width / 2 - bounds.midX, y: numeralSize.height / 2 - bounds.midY)
        return (bounds.offsetBy(dx: origin.x, dy: origin.y), origin)
    }

    static func numeral(_ number: Int, highContrast: Bool = false) -> NSImage? {
        guard let layout = numeralLayout(number) else { return nil }
        return NSImage(size: numeralSize, flipped: false) { bounds in
            let palette = DesignTokens.Palette.Overlay.self
            palette.hudFill.withAlphaComponent(plateAlpha(highContrast: highContrast)).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: DesignTokens.Radius.xl, yRadius: DesignTokens.Radius.xl).fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            let shadow = NSShadow()
            shadow.shadowColor = palette.hudFill
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = shadowOffset
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            let text = NSAttributedString(string: String(number), attributes: [
                .font: DesignTokens.Typography.font(.countdown), .foregroundColor: palette.hudText])
            context.textPosition = layout.origin
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    private func speak(_ number: Int, in request: Session) {
        guard request.announced != number else { return }
        request.announced = number
        announce(String(number))
    }

    /// VoiceOver hears "3", "2", "1" without the panel taking focus, through the shared Announcer seam.
    static func postAnnouncement(_ text: String) {
        Announcer.announce(text, priority: .high)
    }

    func cancel() {
        guard let request = session else { return }
        finish(request, complete: false)
    }

    private func advance(_ request: Session) {
        guard session === request, !request.advancing, !request.completionPending else { return }
        request.advancing = true
        defer { request.advancing = false }
        let frame = request.timing.tick()
        // Original cue precedes image/alpha changes. It may cancel or start anew.
        if frame.playCue { request.cue() }
        guard session === request else { return }
        if frame.playCue {
            let image = images(frame.imageNumber)
            guard session === request else { return }
            request.number = frame.imageNumber
            request.imageView?.image = image
            request.imageView?.setAccessibilityLabel("Capture countdown: \(frame.imageNumber)")
            speak(frame.imageNumber, in: request)
            guard session === request else { return }
        }
        // The blink is motion: Reduce Motion keeps the numeral steady at full alpha until the countdown ends.
        request.panel?.alphaValue = request.reduceMotion ? 1 : CGFloat(frame.alpha)
        guard session === request else { return }
        if frame.finished { finish(request, complete: true) }
    }

    private func finish(_ request: Session, complete: Bool) {
        guard session === request else { return }
        // A synchronous injected scheduler has not returned its cancellation yet.
        // Defer expiry completion until we can invalidate that token first.
        if complete && request.registering { request.completionPending = true; return }
        session = nil // Reject stale ticks before calling injected/native code.
        displayObservation?.invalidate()
        displayObservation = nil
        cleaningUp = true
        let cancellation = request.cancelTimer
        request.cancelTimer = nil
        cancellation?()
        if let panel = request.panel {
            request.parent?.removeChildWindow(panel)
            request.parent = nil
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        request.panel = nil
        request.imageView = nil
        lifetime = nil
        cleaningUp = false
        // 0x2020f cancelTimedSnap precedes 0x205f4 endSnap. No sound-stop here.
        if complete { request.completion() }
    }

    private static func schedule(interval: TimeInterval,
                                 tick: @escaping @MainActor @Sendable () -> Void) -> Cancellation {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        // ONE timer, in the three modes registered by original 0x23c97–0x23d1d.
        for mode: RunLoop.Mode in [.default, .eventTracking, .modalPanel] {
            RunLoop.main.add(timer, forMode: mode)
        }
        return { timer.invalidate() }
    }

    private static func valid(_ rect: NSRect, allowZero: Bool = false) -> Bool {
        let values = [rect.origin.x, rect.origin.y, rect.width, rect.height]
        return values.allSatisfy { $0.isFinite && Float32($0).isFinite }
            && (allowZero ? rect.width >= 0 && rect.height >= 0 : rect.width > 0 && rect.height > 0)
    }

    /// 0x23961/0x23973 roundf centering, then 0x906d5 keepRectInsideScreens:
    /// translate BL, BR, TL, TR against all visible frames; do not choose one screen.
    static func placement(rect: NSRect, imageSize: NSSize, screenFrames: [NSRect]) -> NSRect {
        let width = Float32(imageSize.width), height = Float32(imageSize.height)
        let centerX = Float32(rect.origin.x) + Float32(rect.width) * Float32(0.5)
        let centerY = Float32(rect.origin.y) + Float32(rect.height) * Float32(0.5)
        var x = (centerX - width * Float32(0.5)).rounded(.toNearestOrAwayFromZero)
        var y = (centerY - height * Float32(0.5)).rounded(.toNearestOrAwayFromZero)
        for corner in [(Float32(0), Float32(0)), (width, 0), (0, height), (width, height)] {
            let px = x + corner.0, py = y + corner.1
            let clamped = keepPoint(px, py, frames: screenFrames)
            x = (clamped.0 - px) + x
            y = (clamped.1 - py) + y
        }
        return NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    private static func keepPoint(_ x: Float32, _ y: Float32, frames: [NSRect]) -> (Float32, Float32) {
        // Original 0x901d0: squared Float32 distance, strict comparison, first tie.
        var best: Float32 = 1e10
        var result: (Float32, Float32) = (-1e10, -1e10)
        for frame in frames {
            let minX = Float32(frame.origin.x), minY = Float32(frame.origin.y)
            let maxX = minX + Float32(frame.width), maxY = minY + Float32(frame.height)
            if x >= minX && x < maxX && y >= minY && y < maxY { return (x, y) }
            let cx = min(max(x, minX), maxX), cy = min(max(y, minY), maxY)
            let dx = x - cx, dy = y - cy
            let distance = dx * dx + dy * dy
            if distance < best { best = distance; result = (cx, cy) }
        }
        return result
    }
}

/// Never key/main, never a mouse or keyboard responder. No event monitor is installed.
class OriginalCountdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OriginalCountdownImageView: NSImageView {
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
