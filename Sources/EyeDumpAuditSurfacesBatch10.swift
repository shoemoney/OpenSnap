import AppKit
import Carbon

/// Audit fix batch 10 (independent review round 3): a Resize above the room the window has, with Original size unticked and ticked; a corner
/// drag on a snap; the Export accessory seeded from the footer box; the selected Upload row that is not the default (the bar under Differentiate
/// Without Color); the Capture note when the shortcuts cannot be put back; and History Details after Delete from Web. Synthetic content only.
extension AuditRun {
    func s46() {
        // The harness screen is far larger than any snap worth drawing, so the editor is given the room of a small display (the window's minimum
        // size): a 2560 x 1800 snap does not fit it, and neither does the 1600 wide it is resized to.
        let capacity = CGSize(width: 920, height: 540)
        app.maximumNormalCanvasOverride = capacity
        defer { app.maximumNormalCanvasOverride = nil }
        let snap = CGSize(width: 2560, height: 1800)
        let typedWidth = 1600

        func resizeTo(_ width: Int) -> Bool {
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
        func facts() -> [String: Any] {
            ["subtitle": app.window.subtitle, "pictureSize": NSStringFromSize(canvas.canvasSize), "outputSize": NSStringFromSize(canvas.outputSize),
             "zoom": Double(canvas.zoom), "checkboxHidden": app.dragOriginalControl.isHidden, "checkboxTicked": app.dragOriginalControl.state == .on,
             "capacity": NSStringFromSize(capacity)]
        }

        // 1. Resize above the room: the picture is the typed size, the window shows it by zoom, the title and every output say the same.
        for ticked in [false, true] {
            let word = ticked ? "ticked" : "unticked"
            loadSynthetic(size: snap, name: "Audit 10 resize")
            placeWindow(windowSize(for: "980xmin", surface: "S46") ?? CGSize(width: 980, height: window.minSize.height))
            app.dragOriginalControl.state = ticked ? .on : .off; app.changeDragOptions(nil); app.updateDragPreview(); pump(0.4)
            let before = app.window.subtitle
            if resizeTo(typedWidth) {
                shoot("S46", "resize-oversized-\(word)", surface: "Editor title and footer",
                      state: "Original size \(word) on a \(Int(snap.width)) × \(Int(snap.height)) snap, Resize to \(typedWidth) wide (above the \(Int(capacity.width)) × \(Int(capacity.height)) pt of room this display gives it): the title reads \(app.window.subtitle) (was \(before)), the picture is \(NSStringFromSize(canvas.canvasSize)) and the box has nothing to offer (R3-001)",
                      refs: ["AppViewport.swift|let rewritten = plan.scaleTo", "AppViewport.swift|func refitPictureZoom"], settle: 0.3, extra: facts())
                shoot("S46", "resize-oversized-\(word)-footer", surface: "Editor title and footer", state: "the footer of the same editor: size and format \(app.window.subtitle), no Original size box (R3-001)",
                      crop: footerCrop(), refs: ["AppViewport.swift|var isLargeShot"], settle: 0.2, extra: facts())
            } else { gap("S46", "oversized Resize \(word)", "the Resize sheet, its Width field or its Apply button was not found") }
            app.activeResizeSession?.cancel()
        }

        // 2. A corner drag on a snap is the same Resize, one Undo step.
        for ticked in [false, true] {
            let word = ticked ? "ticked" : "unticked"
            loadSynthetic(size: snap, name: "Audit 10 corner")
            placeWindow(windowSize(for: "980xmin", surface: "S46") ?? CGSize(width: 980, height: window.minSize.height))
            app.dragOriginalControl.state = ticked ? .on : .off; app.changeDragOptions(nil); app.updateDragPreview(); pump(0.4)
            let before = app.window.subtitle
            if app.beginWindowGesture(.corner(.bottomRight)) {
                app.previewBorderGesture(delta: CGPoint(x: -150, y: 0), flags: [])
                app.endWindowGesture(); app.updateDragPreview(); pump(0.5)
                shoot("S46", "corner-drag-\(word)", surface: "Editor title and footer",
                      state: "Original size \(word), the canvas border's bottom-right corner dragged 150 pt narrower: the title reads \(app.window.subtitle) (was \(before)), the picture is \(NSStringFromSize(canvas.canvasSize)) and the Undo step is \(canvas.editingUndoManager.undoActionName) (R3-002)",
                      refs: ["AppViewport.swift|func endWindowGesture"], settle: 0.3,
                      extra: facts().merging(["undoName": canvas.editingUndoManager.undoActionName], uniquingKeysWith: { $1 }))
            } else { gap("S46", "corner drag \(word)", "the corner gesture did not begin") }
        }

        // 3. File > Export: the accessory opens on the footer's choice.
        loadSynthetic(size: snap, name: "Audit 10 export")
        placeWindow(windowSize(for: "980xmin", surface: "S46") ?? CGSize(width: 980, height: window.minSize.height))
        for ticked in [true, false] {
            let word = ticked ? "ticked" : "unticked"
            app.dragOriginalControl.state = ticked ? .on : .off; app.changeDragOptions(nil); pump(0.3)
            let accessory = app.exportPanelAccessory()
            let view = accessory.view
            view.frame = NSRect(origin: .zero, size: view.fittingSize.width > 10 ? view.fittingSize : NSSize(width: 460, height: 120))
            let host = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            host.title = "Export accessory"; host.contentView = view
            host.orderFront(nil); pump(0.4)
            shoot("S46", "export-accessory-footer-\(word)", surface: "export save panel", state: "the footer's Original size box \(word): the Export accessory opens with Export at original size \(word) too (R3-003)", windows: [host],
                  refs: ["App.swift|func exportPanelAccessory"], settle: 0.2, extra: ["accessoryOriginalSize": accessory.originalSize, "footerTicked": ticked])
            host.orderOut(nil)
        }

        // 4. Settings > Upload with a selected row that is not the Default: under Differentiate Without Color it wears a bar, never the pill's check.
        syntheticDestinations()
        if let controller = openSettingsUpload() {
            let list = app.publishing.destinations()
            if let other = list.destinations.first(where: { $0.id != list.defaultID }) {
                controller.upload.select(id: other.id); pump(0.4)
                shoot("S46", "upload-selected-not-default", surface: "Settings: Upload",
                      state: "Upload tab, \(other.name) selected while the Default pill sits on another row; with Differentiate Without Color the selected row has a 2 pt edge and a leading bar, and the pill keeps its check (R3-007)",
                      windows: [controller.window], refs: ["SettingsWindow.swift|final class SettingsSelectionBar"], settle: 0.4,
                      extra: ["selected": other.name, "defaultID": list.defaultID ?? "", "markHidden": controller.upload.rows.map { $0.selectionMark.isHidden }])
            } else { gap("S46", "Upload selected row", "only one destination was available") }
            app.closePreferences(); pump(0.3)
        } else { gap("S46", "Upload selected row", "Sharing Settings… did not open Settings") }

        // 5. Settings > Capture when the shortcut cannot be put back: another claim on the key appears while the editor holds the shortcuts paused.
        app.shortcutSettings()
        if let controller = app.settingsController {
            controller.window.contentView?.layoutSubtreeIfNeeded()
            var custom = GlobalHotkeySettings()
            let keyCode = UInt32(GlobalHotkeyKeys.choices.first { $0.name == "K" }!.code)
            custom.screen = .init(keyCode: keyCode, modifiers: [.command, .option, .control])
            do { try app.hotkeys.apply(custom) } catch { gap("S46", "Capture note error", "the shortcut could not be saved: \(error.localizedDescription)") }
            controller.capture.reloadShortcuts()
            controller.activityChanged(key: true, appActive: true); pump(0.4)
            var blocker: EventHotKeyRef?
            let claimed = RegisterEventHotKey(keyCode, custom.screen.modifiers.carbonFlags, EventHotKeyID(signature: OSType(0x4F53_3130), id: 99),
                                              GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &blocker)
            controller.activityChanged(key: false, appActive: false); pump(0.5)
            let note = controller.capture.hotkeyForm.statusField.stringValue
            if claimed == noErr, note.hasPrefix("Error: ") {
                shoot("S46", "capture-note-reregister-error", surface: "Settings: Capture",
                      state: "Capture tab after the window stopped being the one in use while another claim holds the key: the note carries the manager's error instead of saying shortcuts are saved and live (R3-008)",
                      windows: [controller.window], refs: ["GlobalHotkeys.swift|private var errorFromPause"], settle: 0.3, extra: ["note": note])
            } else { gap("S46", "Capture note error", "could not stage the failure (claim status \(claimed), note \(note))") }
            if let blocker { UnregisterEventHotKey(blocker) }
            try? app.hotkeys.apply(.defaults)
            controller.capture.reloadShortcuts()
        } else { gap("S46", "Capture note error", "Capture Shortcuts… did not open Settings") }
        app.closePreferences(); pump(0.3)

        // 6. History Details after Delete from Web: the address stays, marked deleted, beside the published size.
        window.makeKeyAndOrderFront(nil)
        loadSynthetic(size: CGSize(width: 1438, height: 1011), name: "Audit 10 shared")
        app.showHistory(); pump(0.8)
        if let history = app.historyWindow, let store = try? app.archiveStore(), let snapshot = try? app.historySnapshot() {
            let link = URL(string: "https://cdn.example.com/pics/audit-10-shared.png")!
            if let id = try? store.archive(snapshot, name: "Audit 10 shared", action: .shared, destination: link.absoluteString, remoteURL: link,
                                           remoteBinding: ["destination": "audit-10"], publishedSize: CGSize(width: 1200, height: 844)) {
                try? store.clearRemote(id); app.refreshHistory(); pump(0.5)
                app.historyBrowser?.select(ids: [id]); pump(0.5)
                shoot("S46", "history-details-deleted", surface: "History", state: "a shared entry after Delete from Web: Details keeps the address and the 1200 × 844 (published) size and marks the address (deleted) (R3-009)",
                      windows: [history], refs: ["HistoryBrowser.swift|(deleted)"], settle: 0.3)
            } else { gap("S46", "History Details deleted", "the shared entry could not be archived") }
            history.orderOut(nil)
        } else { gap("S46", "History Details deleted", "History or its store was unavailable") }
        window.makeKeyAndOrderFront(nil)
    }
}
