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
        // 2. The Toolbox pull-down: the short drawing-session list with its symbols.
        if let toolbox = firstView(of: NSPopUpButton.self, label: "Toolbox menu") {
            captureTrackedMenu("S42", "toolbox-menu-open", surface: "menus", state: "Toolbox pull-down open: 18 drawing-session rows, no app or file plumbing (F-J1-009)",
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
    }
}
