import AppKit

final class ActualNavigatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension AppDelegate {
    /// The size the picture is shown at once it is `picture` pixels: itself if the window can hold it, else the fit.
    func shownOutput(forPicture picture: CGSize) -> CGSize {
        guard let capacity = maximumNormalCanvas, let fitted = WindowSizingPolicy.fittedOutput(source: picture, available: capacity) else { return picture }
        return SketchDocument.wholePixels(fitted)
    }

    /// The zoom at which `size` just fits in the window (it may be above 1), nil when there is no screen to fit to.
    func zoomFitting(_ size: CGSize) -> CGFloat? {
        guard let capacity = maximumNormalCanvas, size.width > 0, size.height > 0 else { return nil }
        return min(capacity.width / size.width, capacity.height / size.height)
    }

    /// After a size change on a snap whose picture is the output (a Resize, a Limit, a corner drag, an Undo): a picture bigger than the window
    /// is fitted by display zoom, not by a smaller output, so the title and every output stay the picture's own pixels (R3-001). A zoom the
    /// user chose stays unless it no longer fits; the zoom this method chose follows the size back up to 100%.
    @discardableResult
    func refitPictureZoom() -> Bool {
        // Full screen has the Space's room, not the window's: the zoom it chose is put back on the way out (R4-004), and refit then.
        // Frame mode refits when it ends.
        if isFullScreen { return refitFullScreenZoom() }
        guard !isActualSize, !frameMode, canvas.document.backgroundPNG != nil, let fit = zoomFitting(canvas.outputSize) else { return false }
        var zoom = canvas.zoom
        if let automatic = pictureFitZoom, abs(zoom - automatic) < 0.0005 { zoom = min(1, fit) }
        else if zoom > fit { zoom = fit }
        let automatic: CGFloat? = zoom < 1 && abs(zoom - fit) < 0.0005 ? zoom : nil
        let changed = abs(zoom - canvas.zoom) >= 0.0005
        if changed { setCanvasDisplayZoom(zoom, label: automatic == nil ? "Output" : "Fit") }
        pictureFitZoom = automatic
        return changed
    }

    func makeResizeSession() -> ResizePanelSession? {
        guard !terminationStarted, !isActualSize, !frameMode, windowGesture == nil,
              window.attachedSheet == nil, activeResizeSession == nil else { return nil }
        let generation = documentGeneration
        var baseline: (output: CGSize, source: CGSize, frame: CGRect, zoom: CGFloat, fit: CGFloat?, dirty: Bool, fullScreen: (generation: UUID, before: CGFloat, applied: CGFloat)?, inFullScreen: Bool)?
        // The fields open at the size the title shows; the geometry maps what is typed back into output pixels. Apply moves the base:
        // the title shows the new size and the next edit is measured from it.
        var displayed = titlePixelSize
        // What the title shows is the picture itself (box ticked, or a snap shown at its own size): then a typed size is a size of the
        // picture. Otherwise it is the shown size, and the picture's own pixels are left for the box to bring back.
        let titleIsPicture: (AppDelegate) -> Bool = { $0.canvas.document.backgroundPNG != nil && ($0.dragAtOriginalSize || !$0.isLargeShot) }
        var atPictureSize = titleIsPicture(self)
        let session = ResizePanelSession(size: displayed, onPreview: { [weak self] request in
            guard let self, !self.terminationStarted, self.documentGeneration == generation else {
                throw NSError(domain: "OpenSnap", code: 5, userInfo: [NSLocalizedDescriptionKey: "This image has changed. Close Resize and try again."])
            }
            let current = (output: self.canvas.outputSize, source: self.canvas.canvasSize)
            let basis = baseline.map { (output: $0.output, source: $0.source) } ?? current
            // One rule (F-J7-005): a Resize or Limit on a snap rewrites the picture itself, with the box ticked or not, so the picture ends at the
            // size that was asked for and ticking Original size afterwards never brings back an older, larger one. A request for the size already
            // shown changes nothing, and a Crop keeps the picture's resolution as it always did.
            let rewritesPicture = atPictureSize || (self.canvas.document.backgroundPNG != nil && !request.isCrop && SketchDocument.wholePixels(request.size) != displayed)
            let preview = try ResizePanelGeometry.preview(source: basis.source, output: basis.output, displayed: displayed, atPictureSize: rewritesPicture, request: request)
            if baseline == nil {
                // A request that leaves the picture as it is (Apply or OK straight after an Apply) starts no edit.
                let unchanged: Bool
                if let plan = preview.picture {
                    // Nothing differs when the picture is already that size and shown at it, or the request is the title's own size (Original
                    // size ticked). A request for the picture's own pixels on a snap shown smaller is not that (R4-002): it restores them.
                    let asTitled = SketchDocument.wholePixels(request.size) == displayed
                    unchanged = plan.scaleTo == nil && plan.crop == nil && (plan.size == current.output || (asTitled && plan.size == current.source))
                }
                else { unchanged = preview.rect == nil && preview.output == current.output }
                if unchanged { return }
                self.canvas.commitPendingTextEditing()
                // Preserve the first-Apply baseline in recovery/history before
                // the transient preview begins. Timer saves leave it intact.
                self.saveRecovery()
                let first = (output: self.canvas.outputSize, source: self.canvas.canvasSize,
                             frame: self.window.frame, zoom: self.canvas.zoom, fit: self.pictureFitZoom, dirty: self.dirty, fullScreen: self.fullScreenZoom, inFullScreen: self.isFullScreen)
                guard self.canvas.beginViewportEdit(name: "Resize") else {
                    throw NSError(domain: "OpenSnap", code: 5, userInfo: [NSLocalizedDescriptionKey: "Finish the current edit before resizing."])
                }
                baseline = first
            }
            let accepted: Bool
            if let plan = preview.picture {
                // R3-001: once the picture is rewritten it IS the output (no shown size apart from it): a picture bigger than the window is fitted
                // by display zoom, so the title and every output carry the typed size and the Original size box has nothing to offer.
                accepted = self.canvas.previewViewportPicture(scaleTo: plan.scaleTo, crop: plan.crop, output: plan.size)
            } else if let rect = preview.rect { accepted = self.canvas.previewViewportCrop(to: rect, outputSize: preview.output) }
            else { accepted = self.canvas.previewViewportResize(to: preview.output) }
            guard accepted else {
                throw NSError(domain: "OpenSnap", code: 5, userInfo: [NSLocalizedDescriptionKey: "This size exceeds the supported source dimensions. Choose smaller dimensions or restore the image to normal size first."])
            }
            self.refitPictureZoom()
            self.sizeNormalWindowToCanvas(centered: false)
            self.updateStatus()
        }, onFinish: { [weak self] cancelled in
            guard let self else { return }
            self.activeResizeSession = nil
            guard self.documentGeneration == generation else { return }
            guard let baseline else { return }
            self.canvas.endViewportEdit(cancelled: cancelled)
            if cancelled, baseline.inFullScreen, !self.isFullScreen {
                // Full screen ended while the sheet was up: the picture goes back, but the zoom and frame in the baseline are full screen's. The
                // window gets the zoom it had before full screen (or a fit) and a size that holds the restored picture (FS-A).
                // A record that is another document's (a new snap was taken in full screen) is not this one's zoom (R6-002).
                let before = baseline.fullScreen.flatMap { $0.generation == generation ? $0.before : nil } ?? baseline.zoom
                if abs(self.canvas.zoom - before) >= 0.0005 { self.setCanvasDisplayZoom(before, label: baseline.fit == nil ? "Output" : "Fit") }
                self.pictureFitZoom = baseline.fit
                self.fullScreenZoom = nil; self.clearFullScreenWindowRecords()
                self.refitPictureZoom()
                self.sizeNormalWindowToCanvas(centered: false)
                self.dirty = baseline.dirty
                self.window.isDocumentEdited = baseline.dirty
            } else if cancelled, !baseline.inFullScreen, self.isFullScreen {
                // Full screen was entered while the sheet was up, so it never fitted the drawing (the session blocked it) and holds no record of
                // the zoom to put back: the windowed zoom goes back as that record and the restored drawing is fitted to the Space as a normal
                // entry would. The baseline's frame is the window's, not the Space's; it is kept for the way out (mirror of FS-A).
                if abs(self.canvas.zoom - baseline.zoom) >= 0.0005 { self.setCanvasDisplayZoom(baseline.zoom, label: baseline.fit == nil ? "Output" : "Fit") }
                self.pictureFitZoom = baseline.fit
                self.fullScreenZoom = nil; self.clearFullScreenWindowRecords()
                self.fitDrawingForFullScreen()
                self.fullScreenWindowedFrame = (generation, baseline.frame)
                self.dirty = baseline.dirty
                self.window.isDocumentEdited = baseline.dirty
            } else if cancelled {
                if abs(self.canvas.zoom - baseline.zoom) >= 0.0005 {
                    self.setCanvasDisplayZoom(baseline.zoom, label: baseline.fit == nil ? "Output" : "Fit")
                }
                self.pictureFitZoom = baseline.fit
                // Each preview in full screen refitted and moved full screen's record of the zoom it chose; it goes back with the zoom (R5-001).
                if self.isFullScreen, baseline.fullScreen != nil { self.fullScreenZoom = baseline.fullScreen }
                self.setWindowFrame(baseline.frame)
                self.dirty = baseline.dirty
                self.window.isDocumentEdited = baseline.dirty
            }
            self.updateStatus()
        }, onCommit: { [weak self] in
            guard let self, self.documentGeneration == generation else { return displayed }
            if baseline != nil { self.canvas.endViewportEdit(cancelled: false); baseline = nil }
            self.updateDragPreview()
            displayed = self.titlePixelSize
            atPictureSize = titleIsPicture(self)
            return displayed
        })
        activeResizeSession = session
        return session
    }

    /// Actual Size has something to show when the output is smaller than the picture's pixels, or when a snap that is its own output is shown
    /// below 100% (a Resize or drag that made it bigger than the window, R4-001).
    var canToggleActualSize: Bool {
        !terminationStarted && !frameMode && windowGesture == nil &&
        (isActualSize || WindowSizingPolicy.actualEligible(source: canvas.fullResolutionOutputSize,
                                                          output: canvas.outputSize, normalMode: true)
         || (canvas.document.backgroundPNG != nil && canvas.zoom < 1))
    }

    var maximumNormalCanvas: CGSize? {
        if let maximumNormalCanvasOverride { return maximumNormalCanvasOverride }
        guard let window, let screen = window.screen ?? NSScreen.main,
              let scroll = canvas.enclosingScrollView else { return nil }
        let viewport = scroll.frame.size
        let chrome = CGSize(width: max(0, window.frame.width - viewport.width),
                            height: max(0, window.frame.height - viewport.height))
        let preferences = generalPreferences.state
        return WindowSizingPolicy.availableCanvas(screen: screen.visibleFrame.size, chrome: chrome,
            modtip: preferences.showKeyboardTips, overlay: preferences.showToolTips)
    }

    /// Whether the picture is bigger than the screen can show: a gesture rule (Shift on the corner restores a normal-size shot), not an export rule.
    var isLargerThanScreen: Bool {
        guard let maximumNormalCanvas else { return false }
        let source = canvas.fullResolutionOutputSize
        return source.width > maximumNormalCanvas.width || source.height > maximumNormalCanvas.height
    }
    /// Whether Original size means anything for this document: it has a snap whose own pixels differ from the size it is shown at. Decided
    /// from the document alone, never from the screen it happens to be on, so the same file exports the same pixels on any display (R2-002),
    /// and a canvas with no snap has no such choice (R2-003).
    var isLargeShot: Bool {
        guard canvas.document.backgroundPNG != nil else { return false }
        return SketchDocument.wholePixels(canvas.fullResolutionOutputSize) != SketchDocument.wholePixels(canvas.outputSize)
    }
    var dragAtOriginalSize: Bool { isActualSize || (isLargeShot && dragOriginalControl.state == .on) }

    @objc func toggleActualSize() {
        guard canToggleActualSize, window?.attachedSheet == nil else { return }
        if isActualSize { leaveActualSize(); return }
        canvas.commitPendingTextEditing()
        guard let window else { return }
        let state = ActualViewState(generation: documentGeneration, outputSize: canvas.outputSize,
                                    zoom: canvas.zoom, pictureFit: pictureFitZoom, windowFrame: window.frame,
                                    scrollOrigin: canvas.enclosingScrollView?.contentView.bounds.origin ?? .zero,
                                    fullScreen: isFullScreen, fullScreenZoom: fullScreenZoom)
        guard canvas.beginActualPresentation() else { return }
        actualView = state
        setCanvasDisplayZoom(1, label: "Actual")
        canvas.enclosingScrollView?.contentView.scroll(to: .zero)
        showActualNavigator()
        refreshNavigatorImage(); updateStatus()
    }

    func leaveActualSize() {
        guard let state = actualView else { return }
        actualView = nil
        navigatorTimer?.invalidate(); navigatorTimer = nil
        if let panel = navigatorWindow { window?.removeChildWindow(panel); panel.orderOut(nil) }
        guard state.generation == documentGeneration else { updateStatus(); return }
        canvas.endActualPresentation()
        let sizeChanged = canvas.outputSize != state.outputSize
        if state.fullScreen != isFullScreen {
            // Full screen was entered or left while Actual Size was up: the zoom and frame it began with belong to the other window, so the
            // picture is fitted to this one instead (R5-002).
            if isFullScreen {
                setCanvasDisplayZoom(state.zoom, label: "Normal")
                pictureFitZoom = state.pictureFit
                fitDrawingForFullScreen()
                fullScreenWindowedFrame = (state.generation, state.windowFrame)
            } else {
                setCanvasDisplayZoom(state.fullScreenZoom.flatMap { $0.generation == state.generation ? $0.before : nil } ?? state.zoom, label: "Normal")
                pictureFitZoom = state.pictureFit
                fullScreenZoom = nil
                // Full screen ended while Actual Size was up: the window work it left waiting is done now, for the picture that is back (FR-1).
                applyFullScreenReturnFrame()
                if refitPictureZoom() || sizeChanged || fullScreenEntryOutputChanged { sizeNormalWindowToCanvas(centered: false) }
                clearFullScreenWindowRecords()
            }
        } else {
            setCanvasDisplayZoom(state.zoom, label: "Normal")
            pictureFitZoom = state.pictureFit
            setWindowFrame(state.windowFrame)
            // An Undo or an Image edit made while Actual Size was up changed the picture: fit the one that is back (R5-002).
            if sizeChanged { finishHistoryResize(previousOutput: state.outputSize) }
            if let scroll = canvas.enclosingScrollView {
                scroll.contentView.scroll(to: state.scrollOrigin); scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        if state.savedWhileActive && canvas.outputSize != canvas.fullResolutionOutputSize {
            dirty = true; window?.isDocumentEdited = true
        }
        updateStatus()
    }

    func showActualNavigator() {
        guard let window else { return }
        if navigatorWindow == nil {
            let panel = ActualNavigatorPanel(contentRect: navigator.frame, styleMask: [.borderless, .nonactivatingPanel],
                                             backing: .buffered, defer: false)
            panel.contentView = navigator; panel.hasShadow = false
            panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true
            panel.setAccessibilityLabel("Actual Size overview")
            navigatorWindow = panel
        }
        if let screen = window.screen ?? NSScreen.main {
            let left = screen.visibleFrame.minX + navigator.frame.width - 5
            if window.frame.minX < left {
                var frame = window.frame
                frame.origin.x = left
                frame.size.width = max(window.minSize.width, min(frame.width, screen.visibleFrame.maxX - left))
                setWindowFrame(frame)
            }
        }
        positionActualNavigator()
        if window.isVisible, let panel = navigatorWindow { window.addChildWindow(panel, ordered: .above) }
    }

    func positionActualNavigator() {
        guard isActualSize, let window, let panel = navigatorWindow else { return }
        // Original navigator is a non-key child along the parent's left edge.
        // Extra header room preserves the user's 20-point readable-text preference.
        let source = canvas.fullResolutionOutputSize
        let maxHeight = max(100, (canvas.enclosingScrollView?.frame.height ?? 400) + 30)
        let previewHeight = min(maxHeight - 64, 156 * source.height / source.width)
        let size = CGSize(width: 180, height: max(100, previewHeight + 64))
        panel.setFrame(CGRect(x: window.frame.minX - size.width + 5,
                              y: window.frame.minY + 30, width: size.width, height: size.height), display: true)
    }

    func refreshNavigatorImage() {
        navigatorTimer?.invalidate(); navigatorTimer = nil
        guard isActualSize, let raw = try? canvas.snapshotDocumentData(),
              let document = try? CanvasView.validatedDocumentData(raw) else { return }
        let scale = min(1, 160 / max(document.size.width, document.size.height))
        navigator.image = ImageExport.image(document: document,
            size: CGSize(width: max(1, ceil(document.size.width * scale)),
                         height: max(1, ceil(document.size.height * scale))))
        updateViewportChrome()
        helpBevel?.reposition()
    }

    func scheduleNavigatorImage() {
        guard isActualSize else { return }
        navigatorTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNavigatorImage() }
        }
        navigatorTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    @objc func canvasViewportChanged(_ notification: Notification) { updateViewportChrome() }
    func updateViewportChrome() {
        resizeButton?.isEnabled = !isActualSize && !frameMode
        zoomControl.isEnabled = !isActualSize
        // An upload (running, done or failed) keeps the checkbox only when the slot, at this window width, holds it beside the message and
        // commands; otherwise the checkbox steps aside, so the bar never widens.
        let crowded = uploadState.occupiesStatusSlot && (modernChrome as? ModernEditorChrome)?.slotHasRoomForCheckbox(during: uploadState) != true
        dragOriginalControl.isHidden = isActualSize || frameMode || !isLargeShot || crowded
        guard let content = window?.contentView, canvas.enclosingScrollView != nil else {
            canvasBorder.isHidden = true; return
        }
        let fullVisible = canvas.visibleRect.contains(canvas.bounds.insetBy(dx: 0.5, dy: 0.5))
        canvasBorder.isHidden = frameMode || isActualSize || !fullVisible
        canvasBorder.frame = canvas.convert(canvas.bounds, to: content).insetBy(dx: -8, dy: -8)
        if isActualSize {
            navigator.documentSize = canvas.bounds.size
            navigator.viewport = canvas.visibleRect
            positionActualNavigator()
        }
    }

    func setWindowFrame(_ frame: CGRect) {
        // A full-screen window fills its Space; fitting it to a document is for the windowed editor.
        guard let window, !isFullScreen else { return }
        adjustingWindowFrame = true
        window.setFrame(frame, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        adjustingWindowFrame = false
        helpBevel?.reposition()
    }

    /// Used only for newly imported raster images and ordinary captures. Native
    /// documents retain their saved output size; their Fit control is view-only.
    func adoptRasterViewport() {
        // The fit scale is a view concern: the stored output size is whole pixels, so the title, History and the Resize
        // sheet read integers and an export has exactly that many pixels.
        guard !isActualSize, let capacity = maximumNormalCanvas,
              let fitted = WindowSizingPolicy.fittedOutput(source: canvas.fullResolutionOutputSize, available: capacity),
              canvas.setPresentationOutputSize(SketchDocument.wholePixels(fitted)) else { fitCanvasToWindow(); return }
        pictureFitZoom = nil
        setCanvasDisplayZoom(1, label: "Output")
        sizeNormalWindowToCanvas()
        canvas.enclosingScrollView?.contentView.scroll(to: .zero)
        updateViewportChrome()
    }

    func sizeNormalWindowToCanvas(centered: Bool = true) {
        let output = canvas.outputSize
        if let window, let viewport = canvas.enclosingScrollView?.frame.size {
            var frame = window.frame
            frame.size.width = max(window.minSize.width, frame.width + output.width * canvas.zoom + 20 - viewport.width)
            frame.size.height = max(window.minSize.height, frame.height + output.height * canvas.zoom + 20 - viewport.height)
            if centered, let screen = window.screen ?? NSScreen.main {
                frame.origin.x = screen.visibleFrame.midX - frame.width / 2
                frame.origin.y = screen.visibleFrame.midY - frame.height / 2
            } else {
                frame.origin.y -= frame.height - window.frame.height
            }
            setWindowFrame(frame)
        }
    }

    func finishHistoryResize(previousOutput: CGSize) {
        // In Frame mode the window is the see-through frame and is left alone; leaving Frame refits (R4-004).
        guard !isActualSize, !frameMode else { return }
        let zoom = canvas.zoom
        refitPictureZoom()
        guard previousOutput != canvas.outputSize || abs(zoom - canvas.zoom) >= 0.0005 else { return }
        sizeNormalWindowToCanvas(centered: false)
        updateStatus()
    }

    func beginWindowGesture(_ handle: CanvasBorderHandle, flags: NSEvent.ModifierFlags = []) -> Bool {
        guard !terminationStarted, !frameMode, !isActualSize, windowGesture == nil,
              let window, window.attachedSheet == nil else { return false }
        if case .corner = handle, flags.contains(.shift), !isLargerThanScreen {
            canvas.setSnapToNormalSize(); setCanvasDisplayZoom(1, label: "Normal")
            sizeNormalWindowToCanvas()
        }
        let name: String
        switch handle { case .corner: name = "Resize Image"; case .edge: name = "Crop Canvas" }
        guard canvas.beginViewportEdit(name: name) else { return false }
        windowGesture = WindowGesture(generation: documentGeneration, outputSize: canvas.outputSize,
                                       sourceSize: canvas.canvasSize, photoSize: canvas.retainedPhotoSize, zoom: canvas.zoom,
                                       windowFrame: window.frame, handle: handle,
                                       scalesPicture: canvas.document.backgroundPNG != nil && dragAtOriginalSize)
        return true
    }

    /// What a corner drag leaves the picture at when the title counts its own pixels (Original size ticked): the dragged shown size is a
    /// proportion of the one the drag began at, and the picture scales by that proportion, as the ticked Resize sheet does (R4-003).
    func cornerDragPictureSize(_ gesture: WindowGesture) -> CGSize {
        var factor = canvas.outputSize.width / gesture.outputSize.width
        // The picture's own pixels have a ceiling a shown size does not: the drag stops growing the picture there, so the title never
        // reads a size release could not make (R5-003). A photo kept behind an edge crop scales with the picture, so it counts too (R6-001).
        let source = gesture.sourceSize
        var bounded = [source]
        if let photo = gesture.photoSize { bounded.append(photo) }
        let ceiling = bounded.map { min(SketchDocument.maximumDimension / $0.width, SketchDocument.maximumDimension / $0.height,
                                        (SketchDocument.maximumPixelCount / ($0.width * $0.height)).squareRoot()) }.min() ?? factor
        factor = min(factor, ceiling)
        func sizes(_ factor: CGFloat) -> (picture: CGSize, photo: CGSize?) {
            let picture = SketchDocument.wholePixels(CGSize(width: source.width * factor, height: source.height * factor))
            return (picture, gesture.photoSize.map { CGSize(width: $0.width * picture.width / source.width, height: $0.height * picture.height / source.height) })
        }
        var scaled = sizes(factor)
        while factor > 0, !SketchDocument.validSize(scaled.picture) || !(scaled.photo.map(SketchDocument.validSize) ?? true) {
            factor *= 0.9999
            scaled = sizes(factor)
        }
        return scaled.picture
    }

    func previewBorderGesture(delta: CGPoint, flags: NSEvent.ModifierFlags) {
        guard let gesture = windowGesture, gesture.generation == documentGeneration else { return }
        var output: CGSize
        switch gesture.handle {
        case .corner(let corner):
            let proportional = canvas.document.backgroundPNG != nil || !canvas.document.elements.isEmpty
            guard let size = WindowSizingPolicy.cornerOutput(initial: gesture.outputSize,
                delta: CGPoint(x: delta.x / gesture.zoom, y: delta.y / gesture.zoom),
                corner: corner, proportional: proportional), canvas.previewViewportResize(to: size) else { return }
            output = canvas.outputSize
        case .edge(let edge):
            guard let preview = WindowSizingPolicy.cropPreview(source: gesture.sourceSize, output: gesture.outputSize,
                delta: delta, edge: edge, symmetric: flags.contains(.option), zoom: gesture.zoom),
                canvas.previewViewportCrop(to: preview.rect, outputSize: preview.outputSize) else { return }
            output = canvas.outputSize
        }
        if let window {
            var frame = gesture.windowFrame
            frame.size.width = max(window.minSize.width, frame.width + (output.width - gesture.outputSize.width) * gesture.zoom)
            frame.size.height = max(window.minSize.height, frame.height + (output.height - gesture.outputSize.height) * gesture.zoom)
            let dx = frame.width - gesture.windowFrame.width, dy = frame.height - gesture.windowFrame.height
            switch gesture.handle {
            case .corner(.topLeft): frame.origin.x -= dx
            case .corner(.bottomLeft): frame.origin.x -= dx; frame.origin.y -= dy
            case .corner(.bottomRight): frame.origin.y -= dy
            case .corner(.topRight): break
            case .edge(let edge):
                if flags.contains(.option) { frame.origin.x -= dx / 2; frame.origin.y -= dy / 2 }
                else { if edge == .left { frame.origin.x -= dx }; if edge == .bottom { frame.origin.y -= dy } }
            }
            frame.origin.x = frame.origin.x.rounded(); frame.origin.y = frame.origin.y.rounded()
            setWindowFrame(frame)
        }
        updateStatus()
    }

    func endWindowGesture(cancelled: Bool = false) {
        guard let gesture = windowGesture else { return }
        windowGesture = nil
        var cancelled = cancelled
        // R3-002: a corner drag on a snap is a Resize of the picture, one Undo step like the Resize sheet: the dragged size becomes the
        // picture's own pixels, so the title and every output follow whichever way the Original size box is set. With the box ticked the
        // drag is a proportion of the picture's own pixels (R4-003), the same as typing a percentage in the ticked sheet.
        if !cancelled, gesture.generation == documentGeneration, case .corner = gesture.handle,
           canvas.document.backgroundPNG != nil, canvas.outputSize != gesture.outputSize {
            let zoom = canvas.zoom
            let dragged = gesture.scalesPicture ? cornerDragPictureSize(gesture) : SketchDocument.wholePixels(canvas.outputSize)
            if canvas.previewViewportPicture(scaleTo: dragged, crop: nil, output: dragged) {
                refitPictureZoom()
                if abs(zoom - canvas.zoom) >= 0.0005 { sizeNormalWindowToCanvas(centered: false) }
            } else { cancelled = true }
        }
        canvas.endViewportEdit(cancelled: cancelled || gesture.generation != documentGeneration)
        if cancelled && gesture.generation == documentGeneration { setWindowFrame(gesture.windowFrame) }
        window?.makeFirstResponder(canvas); updateStatus()
    }

    func windowDidResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window, !adjustingWindowFrame else { return }
        refitForFullScreenResize()
        updateViewportChrome()
        helpBevel?.reposition()
    }
    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        positionActualNavigator()
        helpBevel?.reposition()
    }
    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window?.contentView?.layoutSubtreeIfNeeded(); updateViewportChrome()
    }
}
