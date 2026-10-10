import AppKit

/// Audit fix batch 6 (E2E J6 and review round 2, App side): the editor title and footer with Original size ticked and unticked, the Resize
/// sheet after Apply, the footer at 980 in each state, the compact format toggle, and the History Hide and Trash questions. Synthetic
/// content only; nothing leaves the process.
extension AuditRun {
    func s44() {
        loadSynthetic(size: CGSize(width: 2400, height: 1600), name: "Audit 6")
        placeWindow(windowSize(for: "980xmin", surface: "S44") ?? CGSize(width: 980, height: window.minSize.height))
        pump(0.3)
        // 1. Original size ticked, then unticked: the title and the footer follow the box in the same pass.
        for (label, ticked) in [("ticked", true), ("unticked", false)] {
            app.dragOriginalControl.state = ticked ? .on : .off
            app.changeDragOptions(nil); app.updateDragPreview(); pump(0.3)
            shoot("S44", "editor-original-\(label)", surface: "Editor title and footer", state: "Original size \(label): the title reads \(app.window.subtitle) (F-J6-005, F-J6-010)",
                  refs: ["App.swift|func changeDragOptions", "DesignTokens.swift|enum PixelSizeText"], settle: 0.2, extra: ["subtitle": app.window.subtitle, "status": app.status.stringValue])
        }
        // 2. Resize to 1200 wide with the box ticked: Apply, and the title and the sheet's own fields read the new picture.
        app.dragOriginalControl.state = .on; app.changeDragOptions(nil); app.updateDragPreview(); pump(0.3)
        app.resize()
        pump(0.9)
        func titled(_ title: String, in root: NSView?) -> NSButton? {
            guard let root else { return nil }
            if let button = root as? NSButton, button.title == title { return button }
            for sub in root.subviews { if let hit = titled(title, in: sub) { return hit } }
            return nil
        }
        if let sheet = window.attachedSheet, let width = firstView(of: NSTextField.self, label: "Width in pixels", in: sheet.contentView),
           let apply = titled("Apply", in: sheet.contentView) {
            width.stringValue = "1200"
            width.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: width))
            apply.performClick(nil); pump(0.6)
            shoot("S44", "resize-after-apply", surface: "Resize panel", state: "after Apply with 1200 typed: the sheet stays open on the new size and the title behind it reads \(app.window.subtitle) (F-J6-001, F-J6-007)",
                  windows: [sheet, window], refs: ["ResizePanel.swift|func commit()", "AppViewport.swift|func makeResizeSession"], settle: 0.3,
                  extra: ["subtitle": app.window.subtitle, "pictureSize": NSStringFromSize(canvas.canvasSize), "sheetStillOpen": window.attachedSheet != nil])
            if let cancel = titled("Cancel", in: sheet.contentView) { cancel.performClick(nil) } else { window.endSheet(sheet, returnCode: .cancel) }
            pump(0.6)
            shoot("S44", "resize-after-cancel", surface: "Editor title and footer", state: "after Cancel the applied change stays: the title still reads \(app.window.subtitle) (F-J6-007)",
                  refs: ["ResizePanel.swift|func cancel()"], settle: 0.2, extra: ["subtitle": app.window.subtitle, "pictureSize": NSStringFromSize(canvas.canvasSize)])
        } else { gap("S44", "Resize after Apply", "the Resize sheet, its Width field or its Apply button was not found") }
        app.activeResizeSession?.cancel()
        // 3. The footer at 980 in each state: the state whole, never a tail cut.
        loadSynthetic(size: CGSize(width: 2400, height: 1600), name: "Audit 6 footer")
        placeWindow(windowSize(for: "980xmin", surface: "S44") ?? CGSize(width: 980, height: window.minSize.height))
        app.dragOriginalControl.state = .on; app.setTool(.arrow)
        app.dirty = true; app.updateStatus(); pump(0.3)
        shoot("S44", "footer-w980-unsaved", surface: "Bottom bar", state: "980 wide, Original size showing, unsaved: the state reads whole (F-J6-004); the format is one compact button (R2-014)", crop: footerCrop(),
              refs: ["App.swift|static func shortState", "GlassChrome.swift|var isCompact"], settle: 0.2, extra: ["status": app.status.stringValue, "variants": app.status.variants])
        app.dirty = false; app.updateStatus(); pump(0.2)
        shoot("S44", "footer-w980-saved", surface: "Bottom bar", state: "980 wide, saved", crop: footerCrop(), refs: ["App.swift|func refreshStatusText"], settle: 0.2, extra: ["status": app.status.stringValue])
        app.postStatusNotice(AppDelegate.nothingToSaveNotice); pump(0.3)
        shoot("S44", "footer-w980-nothing-to-save", surface: "Bottom bar", state: "980 wide, Save to History on a blank canvas: the notice reads whole (F-J6-004)", crop: footerCrop(),
              refs: ["App.swift|static func noticeVariants"], settle: 0.2, extra: ["status": app.status.stringValue, "variants": app.status.variants])
        app.clearStatusNotice()
        app.uploadState = .failure(message: "The server returned HTTP 403 for this request and refused it."); pump(0.4)
        shoot("S44", "footer-w980-error", surface: "Bottom bar", state: "980 wide, a failed upload: the message without an Error: lead, or Upload failed · and its code, never a cut sentence; Retry and Details beside it (R2-014)", crop: footerCrop(),
              refs: ["UploadStatus.swift|static func errorVariants"], settle: 0.2, extra: ["status": app.status.stringValue, "variants": app.status.variants])
        app.uploadState = .idle
        app.uploadState = .uploading(name: "Audit-6-3f2a9c0e-5b1d-4c77-9a0e-7d6c1b2f8a44.png"); pump(0.4)
        shoot("S44", "footer-w980-uploading", surface: "Bottom bar", state: "980 wide, an upload running: the verb whole, not a cut file name (R2-014)", crop: footerCrop(),
              refs: ["UploadStatus.swift|case .uploading"], settle: 0.2, extra: ["status": app.status.stringValue, "variants": app.status.variants])
        app.uploadState = .idle; app.dirty = true; app.updateStatus()
        if let wide = windowSize(for: "1440x900", surface: "S44") {
            placeWindow(wide); pump(0.4)
            app.uploadState = .failure(message: "The server returned HTTP 403 for this request and refused it."); pump(0.4)
            shoot("S44", "footer-w1440-error", surface: "Bottom bar", state: "1440 wide, a failed upload: the whole first line fits", crop: footerCrop(),
                  refs: ["UploadStatus.swift|static func errorVariants"], settle: 0.2, extra: ["status": app.status.stringValue, "variants": app.status.variants])
            app.uploadState = .idle; app.updateStatus(); pump(0.2)
            shoot("S44", "footer-w1440-unsaved", surface: "Bottom bar", state: "1440 wide: both format segments, the whole status", crop: footerCrop(), refs: ["ModernEditorChrome.swift|static let compactFormatBelow"],
                  settle: 0.2, extra: ["status": app.status.stringValue])
        }
        placeWindow(windowSize(for: "980xmin", surface: "S44") ?? CGSize(width: 980, height: window.minSize.height))
        // 4. History's Hide and Move to Trash questions: the same order, Cancel first and the default.
        app.showHistory(); pump(0.8)
        if let history = app.historyWindow, let store = try? app.archiveStore() {
            if store.entries.isEmpty, let snapshot = try? app.historySnapshot() { _ = try? store.archive(snapshot, name: "Audit 6 drawing", action: .archived) }
            app.refreshHistory(); pump(0.6)
            if let id = store.entries.first?.id {
                app.historyBrowser?.select(ids: [id])
                for (slug, trash) in [("hide", false), ("trash", true)] {
                    app.removeHistory([id], deleteFiles: trash); pump(0.9)
                    if let alert = AppAlert.presentedAlerts.last {
                        shoot("S44", "history-\(slug)-sheet", surface: "alerts / sheets", state: "\(alert.title): Cancel first and the default, then \(alert.buttons.last?.title ?? "the action") (F-J6-008)",
                              windows: [alert.panel, history], refs: ["App.swift|func removeHistory("], settle: 0.1, extra: ["buttons": alert.buttons.map(\.title)])
                        alert.cancel(); pump(0.3)
                    } else { gap("S44", "History \(slug) question", "no app-owned alert was on screen") }
                }
            }
            history.orderOut(nil)
        } else { gap("S44", "History questions", "History or its store was unavailable") }
        window.makeKeyAndOrderFront(nil)
        // 5. The Toolbox menu opens below its button with an icon on every row.
        if let toolbox = firstView(of: ToolboxPopUpButton.self) {
            captureTrackedMenu("S44", "toolbox-menu-open", surface: "menus", state: "Toolbox menu open below its button: icons on every row, Filled Shapes and Shadow included, nothing on the bar covered (F-J6-009, R2-004)",
                               refs: ["ModernEditorChrome.swift|final class ToolboxPopUpButton"], dismiss: { toolbox.menu?.cancelTracking() }, trigger: { toolbox.performClick(nil) })
        } else { gap("S44", "Toolbox menu open", "the Toolbox button was not found") }
    }
}
