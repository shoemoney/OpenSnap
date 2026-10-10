import AppKit

enum CanvasBorderHandle: Equatable {
    case corner(CanvasCorner)
    case edge(CanvasEdge)
}

/// The center passes mouse events through to the editable canvas. At rest it is a quiet separator hairline around the image; the accent
/// outline and the four corner handles appear when the pointer is over a border or while the crop tool is active.
final class CanvasBorderView: NSView {
    static let border: CGFloat = 8
    /// The crop tool keeps the handles showing; the app sets this from the active tool.
    var showsHandles = false { didSet { needsDisplay = true } }
    private(set) var isHovered = false
    /// Whether the outline and handles are drawn right now.
    var revealsHandles: Bool { showsHandles || isHovered }
    private var hoverArea: NSTrackingArea?
    /// Hover state entry point for the tracking area; tests drive it directly.
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }
    var onBegin: ((CanvasBorderHandle, NSEvent.ModifierFlags) -> Bool)?
    var onDrag: ((CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onEnd: ((Bool) -> Void)?
    private var startScreenPoint: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Image borders. Drag an edge to crop or expand; hold Option for symmetry. Drag a corner to resize.")
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    func handle(at point: CGPoint) -> CanvasBorderHandle? {
        guard bounds.contains(point) else { return nil }
        let b = Self.border * 2
        let left = point.x < b, right = point.x > bounds.width-b
        let top = point.y < b, bottom = point.y > bounds.height-b
        if left && top { return .corner(.topLeft) }
        if right && top { return .corner(.topRight) }
        if left && bottom { return .corner(.bottomLeft) }
        if right && bottom { return .corner(.bottomRight) }
        if point.x < Self.border { return .edge(.left) }
        if point.x > bounds.width-Self.border { return .edge(.right) }
        if point.y < Self.border { return .edge(.top) }
        if point.y > bounds.height-Self.border { return .edge(.bottom) }
        return nil
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        return handle(at: local) == nil ? nil : self
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(handle(at: convert(event.locationInWindow, from: nil)) != nil) }
    override func mouseMoved(with event: NSEvent) { setHovered(handle(at: convert(event.locationInWindow, from: nil)) != nil) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewDidHide() { super.viewDidHide(); setHovered(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false) }
        super.viewWillMove(toWindow: newWindow)
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: Self.border/2, dy: Self.border/2)
        guard revealsHandles else {
            DesignTokens.Palette.separator.setStroke()
            let hairline = NSBezierPath(rect: rect); hairline.lineWidth = 1; hairline.stroke()
            return
        }
        NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
        let outline = NSBezierPath(rect: rect); outline.lineWidth = 1; outline.stroke()
        NSColor.controlAccentColor.setFill()
        for point in [CGPoint(x: rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),
                      CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)] {
            NSBezierPath(roundedRect: CGRect(x:point.x-4,y:point.y-4,width:8,height:8),xRadius:2,yRadius:2).fill()
        }
    }
    override func resetCursorRects() {
        let b = Self.border
        addCursorRect(CGRect(x:0,y:b,width:b,height:max(0,bounds.height-2*b)),cursor:.resizeLeftRight)
        addCursorRect(CGRect(x:bounds.width-b,y:b,width:b,height:max(0,bounds.height-2*b)),cursor:.resizeLeftRight)
        addCursorRect(CGRect(x:b,y:0,width:max(0,bounds.width-2*b),height:b),cursor:.resizeUpDown)
        addCursorRect(CGRect(x:b,y:bounds.height-b,width:max(0,bounds.width-2*b),height:b),cursor:.resizeUpDown)
    }
    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen:event.locationInWindow) ?? event.locationInWindow
    }
    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0,
              let handle = handle(at:convert(event.locationInWindow,from:nil)) else { return }
        let start = screenPoint(event)
        guard onBegin?(handle, event.modifierFlags) == true else { return }
        startScreenPoint = start
        window?.makeFirstResponder(self)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = startScreenPoint else { return }
        let point = screenPoint(event)
        onDrag?(CGPoint(x:point.x-start.x,y:start.y-point.y),event.modifierFlags)
    }
    override func mouseUp(with event: NSEvent) {
        guard startScreenPoint != nil else { return }
        startScreenPoint = nil; onEnd?(false)
    }
    override func cancelOperation(_ sender: Any?) {
        guard startScreenPoint != nil else { return }
        startScreenPoint = nil; onEnd?(true)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) } else { super.keyDown(with:event) }
    }
}
