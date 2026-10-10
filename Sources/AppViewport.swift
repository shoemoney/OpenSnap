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

    func makeResizeSession() -> ResizePanelSession? {
        guard !terminationStarted, !isActualSize, !frameMode, windowGesture == nil,
              window.attachedSheet == nil, activeResizeSession == nil else { return nil }
        let generation = documentGeneration
        var baseline: (output: CGSize, source: CGSize, frame: CGRect, zoom: CGFloat, dirty: Bool)?
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
            let preview = try ResizePanelGeometry.preview(source: basis.source, output: basis.output, displayed: displayed, atPictureSize: atPictureSize, request: request)
            if baseline == nil {
                // A request that leaves the picture as it is (Apply or OK straight after an Apply) starts no edit.
                let unchanged: Bool
                if let plan = preview.picture { unchanged = plan.scaleTo == nil && plan.crop == nil && self.shownOutput(forPicture: plan.size) == current.output }
                else { unchanged = preview.rect == nil && preview.output == current.output }
                if unchanged { return }
                self.canvas.commitPendingTextEditing()
                // Preserve the first-Apply baseline in recovery/history before
                // the transient preview begins. Timer saves leave it intact.
                self.saveRecovery()
                let first = (output: self.canvas.outputSize, source: self.canvas.canvasSize,
                             frame: self.window.frame, zoom: self.canvas.zoom, dirty: self.dirty)
                guard self.canvas.beginViewportEdit(name: "Resize") else {
                    throw NSError(domain: "OpenSnap", code: 5, userInfo: [NSLocalizedDescriptionKey: "Finish the current edit before resizing."])
                }
                baseline = first
            }
            let accepted: Bool
            if let plan = preview.picture {
                accepted = self.canvas.previewViewportPicture(scaleTo: plan.scaleTo, crop: plan.crop, output: self.shownOutput(forPicture: plan.size))
            } else if let rect = preview.rect { accepted = self.canvas.previewViewportCrop(to: rect, outputSize: preview.output) }
            else { accepted = self.canvas.previewViewportResize(to: preview.output) }
            guard accepted else {
                throw NSError(domain: "OpenSnap", code: 5, userInfo: [NSLocalizedDescriptionKey: "This size exceeds the supported source dimensions. Choose smaller dimensions or restore the image to normal size first."])
            }
            self.sizeNormalWindowToCanvas(centered: false)
            self.updateStatus()
        }, onFinish: { [weak self] cancelled in
            guard let self else { return }
            self.activeResizeSession = nil
            guard self.documentGeneration == generation else { return }
            guard let baseline else { return }
            self.canvas.endViewportEdit(cancelled: cancelled)
            if cancelled {
                self.canvas.setZoom(baseline.zoom)
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

    var canToggleActualSize: Bool {
        !terminationStarted && !frameMode && windowGesture == nil &&
        (isActualSize || WindowSizingPolicy.actualEligible(source: canvas.fullResolutionOutputSize,
                                                          output: canvas.outputSize, normalMode: true))
    }

    var maximumNormalCanvas: CGSize? {
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
                                    zoom: canvas.zoom, windowFrame: window.frame,
                                    scrollOrigin: canvas.enclosingScrollView?.contentView.bounds.origin ?? .zero)
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
        setCanvasDisplayZoom(state.zoom, label: "Normal")
        setWindowFrame(state.windowFrame)
        if let scroll = canvas.enclosingScrollView {
            scroll.contentView.scroll(to: state.scrollOrigin); scroll.reflectScrolledClipView(scroll.contentView)
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
        guard !isActualSize, !frameMode, previousOutput != canvas.outputSize else { return }
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
                                       sourceSize: canvas.canvasSize, zoom: canvas.zoom,
                                       windowFrame: window.frame, handle: handle)
        return true
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
