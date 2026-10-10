import AppKit

/// Audit fix batch 3c (E2E journeys J1 and J2, App side): the Resize sheet in each mode, the Toolbox, the Photos empty state, a History
/// question raised on History, and a status notice. Synthetic content only; nothing leaves the process.
extension AuditRun {
    func s42() {
        loadSynthetic(size: CGSize(width: 1200, height: 800), name: "Audit 3c")
        // 1. The Resize or Crop sheet, one capture per mode, then with the preset management opened.
        for (mode, label) in [(ResizePanelMode.resize, "resize"), (.crop, "crop"), (.limit, "limit")] {
            app.resize()
            if let panel = window.attachedSheet, let control = firstView(of: NSSegmentedControl.self, label: "Size operation", in: panel.contentView) {
                control.selectedSegment = mode.rawValue
                _ = control.target?.perform(control.action, with: control)
            }
            captureSheet("S42", "resize-\(label)", surface: "Resize panel", state: "Resize or Crop sheet, \(label) mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014)",
                         refs: ["ResizePanel.swift|private func buildContent", "ResizePanel.swift|final class ResizeAnchorGrid"], wait: 0.9, dismiss: { [self] in
                            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
                            app.activeResizeSession?.cancel()
                         })
        }
        // 2. The Toolbox menu: the short drawing-session list with its symbols.
        if let toolbox = firstView(of: NSPopUpButton.self, label: "Toolbox menu") {
            captureTrackedMenu("S42", "toolbox-menu-open", surface: "menus", state: "Toolbox menu open (selection-style pop-up, icons drawn): 18 drawing-session rows, no app or file plumbing (F-J1-009)",
                               refs: ["App.swift|func bezelToolbox()"], dismiss: { toolbox.menu?.cancelTracking() }, trigger: { toolbox.performClick(nil) })
        } else { gap("S42", "Toolbox menu open", "toolbox popup not found") }
        pump(0.4)
        // 3. The Photos sheet before any folder is chosen: the explanation and both ways to choose sit inside the grid.
        app.photoBrowser.show(relativeTo: window) { _ in }
        captureSheet("S42", "photos-empty", surface: "Photos sheet", state: "Photos sheet with nothing chosen: the grid holds the explanation and both source buttons (F-J1-013)",
                     refs: ["PhotoBrowser.swift|private func buildEmptyState"], wait: 0.9, dismiss: { [self] in
                        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
                     })
        // 4. A History question asked on History itself, and the editor left untouched behind it.
        app.showHistory()
        pump(0.8)
        if let history = app.historyWindow, let store = try? app.archiveStore() {
            if store.entries.isEmpty, let snapshot = try? app.historySnapshot() { _ = try? store.archive(snapshot, name: "Audit 3c drawing", action: .archived) }
            app.refreshHistory(); pump(0.6)
            if let id = store.entries.first?.id {
                app.historyBrowser?.select(ids: [id])
                app.removeHistory([id], deleteFiles: false)
                pump(0.9)
                if let alert = AppAlert.presentedAlerts.last {
                    shoot("S42", "history-hide-on-history", surface: "alerts / sheets", state: "Hide drawings from History? raised on the History window the click came from (F-J2-001)",
                          windows: [alert.panel, history], refs: ["App+HistoryFlow.swift|func presentFromHistory", "App.swift|func removeHistory("], settle: 0.1,
                          extra: ["presentedOnHistory": history.attachedSheet === alert.panel, "editorSheet": window.attachedSheet != nil])
                    alert.cancel(); pump(0.3)
                } else { gap("S42", "History question", "no app-owned alert was on screen") }
            }
            history.orderOut(nil)
        } else { gap("S42", "History question", "History or its store was unavailable") }
        window.makeKeyAndOrderFront(nil)
        // 5. A transient status message, then its expiry.
        app.updateStatus()
        app.postStatusNotice("Saved to History")
        shoot("S42", "status-notice", surface: "Bottom bar", state: "a transient message in the status slot (F-J1-010)", crop: footerCrop(), refs: ["App+StatusNotice.swift|func postStatusNotice"], settle: 0.2)
        app.clearStatusNotice(); pump(0.3)
        shoot("S42", "status-after-notice", surface: "Bottom bar", state: "the normal status back, now naming the export format (F-J1-010)", crop: footerCrop(), refs: ["App+StatusNotice.swift|func clearStatusNotice"], settle: 0.2)
        // Leave the small blank drawing behind, so the full-screen capture that may follow shows a small drawing in a large Space (F-J1-018).
        canvas.newBlank(size: CGSize(width: 800, height: 600)); canvas.editingUndoManager.removeAllActions()
        app.fitCanvasToWindow(); app.updateStatus()
    }

    /// Audit fix batch 3c round 2: the Resize and Photos sheets at the 980 x minimum window (nothing may hang over the parent or clip), the selection
    /// handles at 25% zoom, and History's Delete from Web turned off with its reason on the tooltip plate. Synthetic content only.
    func s43() {
        loadSynthetic(size: CGSize(width: 1200, height: 800), name: "Audit 3c round 2")
        placeWindow(windowSize(for: "980xmin", surface: "S43") ?? CGSize(width: 980, height: window.minSize.height))
        func sheetAtMinimum(_ slug: String, _ state: String, refs: [String], dismiss: () -> Void) {
            pump(0.9)
            guard let sheet = window.attachedSheet else { gap("S43", slug, "the sheet did not attach"); return }
            sheet.displayIfNeeded()
            let parent = window.frame, frame = sheet.frame
            let extra: [String: Any] = ["sheetFrame": NSStringFromRect(frame), "parentFrame": NSStringFromRect(parent),
                                        "sheetHangsBelowParent": frame.minY < parent.minY - 0.5, "sheetWiderThanParent": frame.width > parent.width + 0.5,
                                        "sheetContentFits": sheet.contentView.map { $0.fittingSize.height <= sheet.contentLayoutRect.height + 0.5 && $0.fittingSize.width <= sheet.contentLayoutRect.width + 0.5 } ?? false]
            shoot("S43", slug, surface: "Sheet at the minimum window", state: state, windows: [sheet], refs: refs, settle: 0.3, extra: extra)
            shoot("S43", slug + "-in-context", surface: "Sheet at the minimum window", state: state + " (parent window + sheet composite)", windows: [sheet, window], refs: refs, settle: 0.1, extra: extra)
            dismiss()
            pump(0.4)
        }
        for (mode, label) in [(ResizePanelMode.resize, "resize"), (.crop, "crop"), (.limit, "limit")] {
            app.resize()
            if let panel = window.attachedSheet, let control = firstView(of: NSSegmentedControl.self, label: "Size operation", in: panel.contentView) {
                control.selectedSegment = mode.rawValue
                _ = control.target?.perform(control.action, with: control)
            }
            sheetAtMinimum("w980-resize-\(label)", "Resize or Crop sheet, \(label) mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row",
                           refs: ["ResizePanel.swift|private func buildContent"]) { [self] in
                if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
                app.activeResizeSession?.cancel()
            }
        }
        app.photoBrowser.show(relativeTo: window) { _ in }
        sheetAtMinimum("w980-photos-empty", "Photos sheet with nothing chosen over the 980 x minimum-height window: the grid, then the buttons with no blank band between",
                       refs: ["PhotoBrowser.swift|private func buildContent"]) { [self] in
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
        }
        // Selection handles at 25% zoom keep one size on screen (F-J1-016).
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Zoom 25")
        let named = addAllAnnotationKinds(scale: 1)
        app.setTool(.select)
        if let rect = named["rectangle"] { canvas.selection = [rect.id] }
        app.setCanvasDisplayZoom(0.25, label: "Zoom"); pump(0.5)
        shoot("S43", "zoom25-selection-handles", surface: "Selection", state: "rectangle selected at 25% zoom: handles stay a usable size and do not bury the selection (F-J1-016)", refs: ["Canvas.swift|static func handleLayout"], settle: 0.3)
        canvas.selection = []
        app.fitCanvasToWindow()
        // History: Delete from Web off for an upload made before the app recorded where it went, with its reason on the tooltip plate.
        app.showHistory()
        pump(0.8)
        if let history = app.historyWindow, let store = try? app.archiveStore(), let browser = app.historyBrowser, let snapshot = try? app.historySnapshot() {
            let url = URL(string: "https://cdn.example.com/pics/Legacy-upload.png")!
            let legacy = try? store.archive(snapshot, name: "Legacy upload", action: .shared, destination: url.absoluteString, remoteURL: url)
            app.refreshHistory(); pump(0.6)
            if let legacy {
                browser.select(ids: [legacy]); pump(0.5)
                let button = browser.actionRow.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == HistoryBrowser.Action.deleteRemote.title }
                let tip = AppToolTip.shared
                tip.dismiss(); tip.reduceMotion = { true }; tip.dismissesOnWindowChanges = false
                if let button, AppToolTip.text(for: button) != nil {
                    tip.show(for: button)
                    if let plate = tip.panel, tip.isShown {
                        shoot("S43", "history-delete-web-disabled", surface: "History browser", state: "Delete from Web dimmed for an upload with no recorded destination, its reason on the tooltip plate (F-J2-002)",
                              windows: [history, plate], refs: ["HistoryBrowser.swift|nonisolated static func deleteRemoteHelp", "App.swift|canDeleteFromWeb"], settle: 0.3,
                              extra: ["buttonEnabled": button.isEnabled, "tooltipText": tip.shownText ?? ""])
                    } else { gap("S43", "Delete from Web tooltip", "the tooltip plate did not appear") }
                    tip.dismiss()
                } else { gap("S43", "Delete from Web tooltip", "the button or its tooltip text was not found") }
                tip.dismissesOnWindowChanges = true
            }
            history.orderOut(nil)
        } else { gap("S43", "History Delete from Web", "History or its store was unavailable") }
        window.makeKeyAndOrderFront(nil)
    }
}
