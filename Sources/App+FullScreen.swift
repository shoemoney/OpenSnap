import AppKit

/// Full screen gives the drawing the whole Space: the canvas is zoomed to fill it (F-J1-018) and put back when the window returns.
extension AppDelegate {
    /// How far full screen may magnify a small drawing: enough to use the room, never so far that a screenshot turns to mush.
    static let fullScreenMaximumScale: CGFloat = 2

    func fitDrawingForFullScreen() {
        guard !isActualSize, activeResizeSession == nil, windowGesture == nil else { return }
        let before = canvas.zoom
        fitCanvasToWindow(maximumScale: Self.fullScreenMaximumScale)
        fullScreenZoom = (documentGeneration, before, canvas.zoom)
        updateViewportChrome()
    }

    func restoreZoomAfterFullScreen() {
        defer { fullScreenZoom = nil }
        guard let saved = fullScreenZoom, saved.generation == documentGeneration, !isActualSize,
              abs(canvas.zoom - saved.applied) < 0.0005 else { return }
        setCanvasDisplayZoom(saved.before, label: "Zoom")
        updateViewportChrome()
    }
}
