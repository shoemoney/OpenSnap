import AppKit

/// Full screen gives the drawing the whole Space: the canvas is zoomed to fill it (F-J1-018) and put back when the window returns.
extension AppDelegate {
    /// How far full screen may magnify a small drawing: enough to use the room, never so far that a screenshot turns to mush.
    static let fullScreenMaximumScale: CGFloat = 2

    func fitDrawingForFullScreen() {
        guard !isActualSize, activeResizeSession == nil, windowGesture == nil else { return }
        let before = fullScreenZoom?.before ?? canvas.zoom
        if fullScreenZoom?.generation != documentGeneration { fullScreenEntryOutput = canvas.outputSize }
        fitCanvasToWindow(maximumScale: Self.fullScreenMaximumScale)
        fullScreenZoom = (documentGeneration, before, canvas.zoom)
        updateViewportChrome()
    }

    /// Full screen is a run of window resizes (the Space's size is reached over several), and AppKit's did-enter and did-exit notices come
    /// after them or not at all in a headless run, so the resizes drive the zoom: while the window is in full screen the drawing is fitted
    /// to whatever room it has (as long as the zoom is still the one full screen chose), and the first resize back out puts the zoom back.
    func refitForFullScreenResize() {
        if isFullScreen {
            if fullScreenZoom == nil { fitDrawingForFullScreen() }
            else if let saved = fullScreenZoom, saved.generation == documentGeneration, abs(canvas.zoom - saved.applied) < 0.0005 { fitDrawingForFullScreen() }
        } else if fullScreenZoom != nil { restoreZoomAfterFullScreen() }
    }

    /// A size change made in full screen is fitted to the Space (not to the window's room, which would leave the zoom the way out restores
    /// pointing at nothing), while the zoom is still the one full screen chose. Returns whether the zoom moved.
    func refitFullScreenZoom() -> Bool {
        guard !isActualSize, let saved = fullScreenZoom, saved.generation == documentGeneration, abs(canvas.zoom - saved.applied) < 0.0005 else { return false }
        fitCanvasToWindow(maximumScale: Self.fullScreenMaximumScale)
        fullScreenZoom = (saved.generation, saved.before, canvas.zoom)
        updateViewportChrome()
        return abs(canvas.zoom - saved.applied) >= 0.0005
    }

    func restoreZoomAfterFullScreen() {
        // A size change made in full screen was not fitted to the window then; it is now, once the zoom the window had is back (R4-004),
        // and the window follows the picture even when the zoom came back unchanged (FS-B).
        let entryOutput = fullScreenEntryOutput, returnFrame = fullScreenWindowedFrame
        defer {
            fullScreenZoom = nil; fullScreenEntryOutput = nil; fullScreenWindowedFrame = nil
            if let returnFrame, returnFrame.generation == documentGeneration { setWindowFrame(returnFrame.frame) }
            let zoomMoved = refitPictureZoom()
            if zoomMoved || entryOutput.map({ $0 != canvas.outputSize }) == true { sizeNormalWindowToCanvas(centered: false) }
        }
        guard let saved = fullScreenZoom, saved.generation == documentGeneration, !isActualSize,
              abs(canvas.zoom - saved.applied) < 0.0005 else { return }
        setCanvasDisplayZoom(saved.before, label: "Zoom")
        updateViewportChrome()
    }
}
