import AppKit

/// Audit fix batch 11 (independent review round 4): Actual Size after a Resize that made the snap bigger than the window; the picture's own width
/// typed while Original size is unticked; a corner drag with Original size ticked (the title mid-drag and after release); and the Export accessory
/// when nothing differs, with its real dimensions and bytes. Synthetic content only.
extension AuditRun {
    /// What File > Export does as the panel opens and after each change: the accessory is handed the size and bytes of what it would write.
    func refreshExportAccessory(_ accessory: ExportAccessory) {
        let data = try? app.exportPanelData(accessory)
        accessory.updateByteCount(data?.count, size: app.exportPixelSize(originalSize: accessory.originalSize))
    }

    /// Resize… with the width field set to `width` and Apply pressed, then the sheet closed; false when a control was not found.
    func auditResize(toWidth width: Int) -> Bool {
        app.resize(); pump(0.9)
        func titled(_ title: String, in root: NSView?) -> NSButton? {
            guard let root else { return nil }
            if let button = root as? NSButton, button.title == title { return button }
            for sub in root.subviews { if let hit = titled(title, in: sub) { return hit } }
            return nil
        }
        guard let sheet = window.attachedSheet, let field = firstView(of: NSTextField.self, label: "Width in pixels", in: sheet.contentView),
              let apply = titled("Apply", in: sheet.contentView) else { return false }
        field.stringValue = String(width)
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        apply.performClick(nil); pump(0.6)
        if let cancel = titled("Cancel", in: sheet.contentView) { cancel.performClick(nil) } else { window.endSheet(sheet, returnCode: .cancel) }
        pump(0.6)
        return true
    }

    func s47() {
        // The editor is given the room of a small display, as in S46, so a snap and a Resize above the room need the zoom.
        let capacity = CGSize(width: 920, height: 540)
        app.maximumNormalCanvasOverride = capacity
        defer { app.maximumNormalCanvasOverride = nil }
        let snap = CGSize(width: 2560, height: 1800)
        func facts() -> [String: Any] {
            ["subtitle": app.window.subtitle, "pictureSize": NSStringFromSize(canvas.canvasSize), "outputSize": NSStringFromSize(canvas.outputSize),
             "zoom": Double(canvas.zoom), "canToggleActualSize": app.canToggleActualSize, "isActualSize": app.isActualSize,
             "checkboxHidden": app.dragOriginalControl.isHidden, "checkboxTicked": app.dragOriginalControl.state == .on, "capacity": NSStringFromSize(capacity)]
        }
        func percent() -> String { "\(Int((canvas.zoom * 100).rounded()))%" }
        func prepare(_ name: String, ticked: Bool) {
            loadSynthetic(size: snap, name: name)
            placeWindow(windowSize(for: "980xmin", surface: "S47") ?? CGSize(width: 980, height: window.minSize.height))
            app.dragOriginalControl.state = ticked ? .on : .off; app.changeDragOptions(nil); app.updateDragPreview(); pump(0.4)
        }

        // 1. A Resize above the room: the picture is the output and is shown by zoom, yet Actual Size is available (R4-001).
        prepare("Audit 11 actual", ticked: false)
        let ownPixels = PixelSizeText.text(canvas.canvasSize)
        if auditResize(toWidth: 1600) {
            let item = NSApp.mainMenu?.items.first { $0.title == "Image" }?.submenu?.items.first { $0.title == "Actual Size" }
            let enabled = item.map { app.validateMenuItem($0) } ?? false
            if let imageMenu = NSApp.mainMenu?.items.first(where: { $0.title == "Image" })?.submenu, let content = window.contentView {
                captureTrackedMenu("S47", "image-menu-actual-size-enabled", surface: "menus",
                                   state: "Image menu open after a \(ownPixels) snap was resized to 1600 wide and is shown at \(percent()): Actual Size is enabled (\(enabled)) although the output equals the picture (R4-001)",
                                   refs: ["AppViewport.swift|var canToggleActualSize"],
                                   dismiss: { imageMenu.cancelTracking() }, trigger: { imageMenu.popUp(positioning: nil, at: NSPoint(x: 220, y: content.bounds.height - 60), in: content) })
            } else { gap("S47", "Image menu", "no Image menu was found") }
            let shownZoom = percent()
            if app.canToggleActualSize {
                app.toggleActualSize(); pump(0.8)
                shoot("S47", "actual-size-on", surface: "canvas viewport", state: "Actual Size on after the Resize: one image pixel per screen pixel (was \(shownZoom)), the navigator beside the window (R4-001)",
                      windows: [window] + (app.navigatorWindow.map { [$0] } ?? []), refs: ["AppViewport.swift|@objc func toggleActualSize"], settle: 0.4, extra: facts())
                app.leaveActualSize(); pump(0.5)
                shoot("S47", "actual-size-left", surface: "Editor title and footer", state: "Actual Size left: the zoom is back at \(percent()) (was \(shownZoom)) and the picture is still shown whole (R4-001)",
                      refs: ["AppViewport.swift|func leaveActualSize"], settle: 0.3, extra: facts())
            } else { gap("S47", "Actual Size after Resize", "canToggleActualSize was false after the oversized Resize") }
            // 4. The Export accessory when nothing differs: the picture is the size it is shown at, so there is no Export at original size to offer.
            let accessory = app.exportPanelAccessory()
            refreshExportAccessory(accessory)
            let view = accessory.view
            view.frame = NSRect(origin: .zero, size: view.fittingSize.width > 10 ? view.fittingSize : NSSize(width: 460, height: 120))
            let host = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            host.title = "Export accessory"; host.contentView = view
            host.orderFront(nil); pump(0.4)
            shoot("S47", "export-accessory-nothing-differs", surface: "export save panel",
                  state: "the Export accessory after the Resize: \(accessory.preview.dimensionsLabel), \(accessory.preview.byteCountLabel), and no Export at original size box because the picture already is the size it is shown at (R4-007)",
                  windows: [host], refs: ["App.swift|options.offersOriginalSize = isLargeShot"], settle: 0.2,
                  extra: ["offersOriginalSize": accessory.offersOriginalSize, "dimensions": accessory.preview.dimensionsLabel, "bytes": accessory.preview.byteCountLabel])
            host.orderOut(nil)
        } else { gap("S47", "oversized Resize", "the Resize sheet, its Width field or its Apply button was not found") }
        app.activeResizeSession?.cancel()

        // 2. The picture's own width typed while Original size is unticked: the picture itself comes back, not a resample a pixel short (R4-002).
        prepare("Audit 11 native", ticked: false)
        let shownTitle = app.window.subtitle
        let own = Int(canvas.canvasSize.width)
        if auditResize(toWidth: own) {
            shoot("S47", "native-width-unticked", surface: "Editor title and footer",
                  state: "Original size unticked on a \(ownPixels) snap shown as \(shownTitle): typing \(own) wide restores the picture's own pixels, the title reads \(app.window.subtitle), shown at \(percent()) (R4-002)",
                  refs: ["ResizePanel.swift|R4-002"], settle: 0.3, extra: facts().merging(["undoName": canvas.editingUndoManager.undoActionName], uniquingKeysWith: { $1 }))
        } else { gap("S47", "native-width Resize", "the Resize sheet, its Width field or its Apply button was not found") }
        app.activeResizeSession?.cancel()

        // 3. A corner drag with Original size ticked scales the picture in its own pixels; the title says so while dragging (R4-003).
        prepare("Audit 11 corner", ticked: true)
        let before = app.window.subtitle
        if app.beginWindowGesture(.corner(.bottomRight)) {
            app.previewBorderGesture(delta: CGPoint(x: -150, y: 0), flags: [])
            app.updateDragPreview()
            shoot("S47", "corner-drag-ticked-mid", surface: "Editor title and footer",
                  state: "Original size ticked, the bottom-right corner dragged 150 pt narrower and not yet released: the title already reads \(app.window.subtitle) (was \(before)), what release will leave (R4-003)",
                  refs: ["App.swift|Mid-drag on the ticked box"], settle: 0.3, extra: facts())
            app.endWindowGesture(); app.updateDragPreview(); pump(0.5)
            shoot("S47", "corner-drag-ticked-released", surface: "Editor title and footer",
                  state: "after release the picture is \(NSStringFromSize(canvas.canvasSize)) in its own pixels (a proportion of \(ownPixels), not the collapsed shown size), the title reads \(app.window.subtitle), shown at \(percent()), Undo step \(canvas.editingUndoManager.undoActionName) (R4-003)",
                  refs: ["AppViewport.swift|func cornerDragPictureSize"], settle: 0.3,
                  extra: facts().merging(["undoName": canvas.editingUndoManager.undoActionName], uniquingKeysWith: { $1 }))
        } else { gap("S47", "ticked corner drag", "the corner gesture did not begin") }
    }
}
