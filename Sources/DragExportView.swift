import AppKit
import UniformTypeIdentifiers

/// The drag well. Dragging it hands the drawing to another app; it is also a keyboard-reachable button: Space or Return (and VoiceOver's
/// press) run `onActivate`, which opens the Export panel, the alternative to dragging. Hover shows an open hand and a held press a closed one.
final class DragExportView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate, TokenFocusRinged {
    struct Payload { let data: Data; let name: String; var format: String = "png"; let delivered: (URL) -> Void }
    static let accessibilityName = "Drag image to another app"
    var prepare: (() -> Payload?)?
    /// The keyboard and assistive alternative to dragging.
    var onActivate: (() -> Void)?
    /// Hover and press changes, so the cell the well sits in can draw its plate fill for the same state.
    var onInteractionChange: (() -> Void)?
    private(set) var isHovered = false, isPressed = false
    private var hoverArea: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { KeyboardNavigation.reaches(self) }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _ = tokenRing
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.accessibilityName)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        onInteractionChange?()
    }
    func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else { return }
        isPressed = pressed
        window?.invalidateCursorRects(for: self)
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
    override func viewDidHide() { super.viewDidHide(); setHovered(false); setPressed(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false); setPressed(false) }
        super.viewWillMove(toWindow: newWindow)
    }
    /// What the pointer shows over the well: an open hand, closed while it is held.
    var wellCursor: NSCursor { isPressed ? .closedHand : .openHand }
    override func resetCursorRects() { addCursorRect(bounds, cursor: wellCursor) }
    override func mouseDown(with event: NSEvent) { setPressed(true) }
    override func mouseUp(with event: NSEvent) { setPressed(false) }

    /// Runs the keyboard alternative to dragging; false when nothing is wired.
    @discardableResult func activate() -> Bool {
        guard let onActivate else { return false }
        onActivate()
        return true
    }
    override func accessibilityPerformPress() -> Bool { activate() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36, 76: if !activate() { super.keyDown(with: event) }
        default: super.keyDown(with: event)
        }
    }
    /// The keyboard focus ring is the app's token ring, standing off the well, not AppKit's system ring.
    private(set) lazy var tokenRing = TokenFocusRing(view: self, target: { [unowned self] in bounds.insetBy(dx: 1, dy: 1) })
    override var focusRingType: NSFocusRingType { get { .none } set {} }
    override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); tokenRing.setFocused(accepted); return accepted }
    override func resignFirstResponder() -> Bool { let resigned = super.resignFirstResponder(); if resigned { tokenRing.setFocused(false) }; return resigned }
    override func layout() { super.layout(); tokenRing.refresh() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); tokenRing.refresh() }
    var overview: NSImage? { didSet { needsDisplay = true } }
    var onBegin: ((UUID) -> Void)?
    var onLeaveControl: ((UUID) -> Void)?
    var onEnd: ((UUID, Bool) -> Void)?
    var onDeliveryFailure: ((UUID) -> Void)?
    private struct Export {
        let id: UUID
        let provider: NSFilePromiseProvider
        let payload: Payload
        let controlRect: NSRect
    }
    private var payloads: [ObjectIdentifier: Export] = [:]
    private var sessions: [ObjectIdentifier: ObjectIdentifier] = [:]
    private var activeProvider: ObjectIdentifier?
    /// Modern lets the glass surface behind the view be the plate.
    var drawsBackground = true { didSet { needsDisplay = true } }
    /// Modern shows only an open-hand icon: no thumbnail and no text. The thumbnail still feeds the drag image.
    var showsHandIconOnly = false { didSet { needsDisplay = true } }
    static let handSymbolName = "hand.raised"
    override func draw(_ dirtyRect: NSRect) {
        if drawsBackground { NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill() }
        if showsHandIconOnly {
            guard let hand = ChromeIcons.resolve(.dragHand, family: .solid, pointSize: 22).image else { return }
            let tinted = NSImage(size: hand.size, flipped: false) { rect in
                hand.draw(in: rect); NSColor.labelColor.setFill(); rect.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: NSRect(x: bounds.midX - hand.size.width / 2, y: bounds.midY - hand.size.height / 2, width: hand.size.width, height: hand.size.height))
            return
        }
        if let overview { overview.draw(in: bounds.insetBy(dx: 4, dy: 4), from: .zero, operation: .sourceOver, fraction: 0.2) }
        let title = "Drag Me"
        let attrs = DesignTokens.Typography.attributes(.bodyStrong)
        let size = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attrs)
    }
    override func mouseDragged(with event: NSEvent) {
        guard activeProvider == nil, let window, let payload = prepare?() else { return }
        let provider = NSFilePromiseProvider(fileType: (UTType(filenameExtension: payload.format) ?? .data).identifier, delegate: self)
        guard beginExport(provider: provider, payload: payload, controlRect: window.convertToScreen(convert(bounds, to: nil))) else { return }
        let item = NSDraggingItem(pasteboardWriter: provider)
        let preview = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { [overview] rect in
            overview?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.5)
            return true
        }
        item.setDraggingFrame(NSRect(x: bounds.midX - 64, y: bounds.midY - 64, width: 128, height: 128), contents: preview)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        sessions[ObjectIdentifier(session)] = ObjectIdentifier(provider)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard sessions[ObjectIdentifier(session)] == activeProvider else { return }
        moveExport(to: screenPoint)
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        setPressed(false)
        if let provider = sessions.removeValue(forKey: ObjectIdentifier(session)) { endExport(provider: provider, succeeded: !operation.isEmpty) }
    }
    @discardableResult
    func beginExport(provider: NSFilePromiseProvider, payload: Payload, controlRect: NSRect) -> Bool {
        guard activeProvider == nil else { return false }
        let key = ObjectIdentifier(provider), export = Export(id: UUID(), provider: provider, payload: payload, controlRect: controlRect)
        payloads[key] = export; activeProvider = key
        activeExport = export
        onBegin?(export.id)
        return true
    }
    private var activeExport: Export?
    func moveExport(to screenPoint: NSPoint) {
        guard let export = activeExport, !export.controlRect.contains(screenPoint) else { return }
        onLeaveControl?(export.id)
    }
    func endExport(provider: ObjectIdentifier, succeeded: Bool) {
        guard activeProvider == provider, let export = activeExport else { return }
        activeProvider = nil; activeExport = nil
        if !succeeded { payloads.removeValue(forKey: provider) }
        onEnd?(export.id, succeeded)
    }
    /// The file extension for a payload format: JPEG files are named .jpg, matching uploads.
    static func fileExtension(forFormat format: String) -> String { format == "jpeg" ? "jpg" : format }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        let payload = payloads[ObjectIdentifier(filePromiseProvider)]?.payload
        return (payload?.name ?? "Untitled") + "." + Self.fileExtension(forFormat: payload?.format ?? "png")
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        let export = payloads.removeValue(forKey: ObjectIdentifier(filePromiseProvider))
        do {
            guard let export else { throw NSError(domain: "OpenSnap", code: 1, userInfo: [NSLocalizedDescriptionKey: "The dragged image is no longer available."]) }
            try export.payload.data.write(to: url, options: .atomic)
            export.payload.delivered(url); completionHandler(nil)
        } catch {
            if let export { onDeliveryFailure?(export.id) }
            completionHandler(error)
        }
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }
}
