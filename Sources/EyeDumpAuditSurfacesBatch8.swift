import AppKit

/// Audit fix batch 8 (E2E J7 findings): the WebDAV 2xx Test note whole, the footer at 980 with an error and the Original size box, the Capture
/// note while shortcuts are paused and not, a shared entry's Details Size before and after Delete from Web, and Resize unticked then ticked.
/// Synthetic content only; nothing leaves the process.
extension AuditRun {
    func s45() {
        // 1. The WebDAV Test note, fed the real wording for a 2xx with a login, in the sheet at the Settings width and at the widest.
        syntheticDestinations()
        if let controller = openSettingsUpload() {
            let settings = controller.window
            let note = PublishingConnectionTest.webDAVOutcome(stdout: "207", exitCode: 0, stderr: "", username: "demo", password: "example-secret-not-real").message
            for (label, hostWidth) in [("640", settings.frame.width), ("900", CGFloat(900))] {
                let (panel, view) = app.publishing.buildEditor(editing: nil, visibleFrame: nil, hostWidth: hostWidth)
                settings.beginSheet(panel); pump(0.8)
                view.protocolPopup.selectItem(withTitle: PublishingProtocol.webDAV.title); view.formChanged()
                view.showTestResult(ok: true, message: note); pump(0.5)
                shootSheet("S45", "webdav-test-2xx-\(label)", surface: "Destinations / Publishing", state: "WebDAV form at \(label) pt after a Test that reached a server (HTTP 207): the whole note, ending Nothing was uploaded. (F-J7-001)",
                           refs: ["Publishing.swift|case 200..<300", "PublishingDestinationsView.swift|detail.maximumNumberOfLines = maxLines"], host: settings, sheet: panel)
                settings.endSheet(panel); pump(0.4); app.publishing.cancelSettings(); pump(0.3)
            }
            app.closePreferences(); pump(0.3)
        } else { gap("S45", "WebDAV Test note", "Sharing Settings… did not open Settings") }

        // 2. The footer at 980 with an error: the Original size box stays, the message gives up its words.
        loadSynthetic(size: CGSize(width: 2400, height: 1600), name: "Audit 8")
        placeWindow(windowSize(for: "980xmin", surface: "S45") ?? CGSize(width: 980, height: window.minSize.height))
        app.dragOriginalControl.state = .on; app.changeDragOptions(nil); app.setTool(.arrow); pump(0.3)
        app.uploadState = .failure(message: PublishingPlan.transferFailure(exitCode: 22, stdout: "403\n", stderr: "", detail: "curl: (22) The requested URL returned error: 403")); pump(0.5)
        shoot("S45", "footer-w980-error-checkbox", surface: "Bottom bar", state: "980 wide, a WebDAV upload refused with HTTP 403: Original size still showing, the message at its narrowest (\(app.status.stringValue)), Retry and Details beside it (F-J7-002, F-J7-006)",
              crop: footerCrop(), refs: ["ModernEditorChrome.swift|func minimumMessageWidth", "Publishing.swift|static func transferFailure"], settle: 0.2,
              extra: ["status": app.status.stringValue, "variants": app.status.variants, "checkboxHidden": app.dragOriginalControl.isHidden])
        app.uploadState = .idle

        // 3. Settings › Capture: the note while the shortcuts are paused and while they are not.
        app.shortcutSettings()
        if let controller = app.settingsController {
            controller.window.contentView?.layoutSubtreeIfNeeded()
            controller.activityChanged(key: false, appActive: false); pump(0.4)
            shoot("S45", "capture-note-not-paused", surface: "Settings: Capture", state: "Capture tab while Settings is not the window in use: the normal note (F-J7-004)", windows: [controller.window],
                  refs: ["GlobalHotkeys.swift|static let idleLiveStatus"], settle: 0.3, extra: ["note": controller.capture.hotkeyForm.statusField.stringValue])
            controller.activityChanged(key: true, appActive: true); pump(0.4)
            shoot("S45", "capture-note-paused", surface: "Settings: Capture", state: "Capture tab with Settings key and the app active: the note says the shortcuts are paused (F-J7-004)", windows: [controller.window],
                  refs: ["GlobalHotkeys.swift|static let pausedStatus"], settle: 0.3, extra: ["note": controller.capture.hotkeyForm.statusField.stringValue])
            controller.activityChanged(key: false, appActive: false)
        } else { gap("S45", "Capture note", "Capture Shortcuts… did not open Settings") }
        app.closePreferences(); pump(0.3)

        // 4. History Details for a shared entry whose editable copy has a different size, before and after Delete from Web.
        window.makeKeyAndOrderFront(nil)
        loadSynthetic(size: CGSize(width: 1438, height: 1011), name: "Audit 8 shared")
        app.showHistory(); pump(0.8)
        if let history = app.historyWindow, let store = try? app.archiveStore(), let snapshot = try? app.historySnapshot() {
            let link = URL(string: "https://cdn.example.com/pics/audit-8-shared.png")!
            if let id = try? store.archive(snapshot, name: "Audit 8 shared", action: .shared, destination: link.absoluteString, remoteURL: link,
                                           remoteBinding: ["destination": "audit-8"], publishedSize: CGSize(width: 1200, height: 844)) {
                app.refreshHistory(); pump(0.5)
                app.historyBrowser?.select(ids: [id]); pump(0.5)
                shoot("S45", "history-details-shared-before", surface: "History", state: "a shared entry whose History copy is 1438 × 1011 and whose web copy is 1200 × 844: Details reads 1200 × 844 (published) (F-J7-003)",
                      windows: [history], refs: ["HistoryBrowser.swift|(published)"], settle: 0.3)
                try? store.clearRemote(id); app.refreshHistory(); pump(0.5)
                app.historyBrowser?.select(ids: [id]); pump(0.5)
                shoot("S45", "history-details-shared-after", surface: "History", state: "the same entry after Delete from Web: the link is gone, Details still reads 1200 × 844 (published), not the History copy's 1438 × 1011 (F-J7-003)",
                      windows: [history], refs: ["HistoryStore.swift|func clearRemote"], settle: 0.3)
            } else { gap("S45", "History Details", "the shared entry could not be archived") }
            history.orderOut(nil)
        } else { gap("S45", "History Details", "History or its store was unavailable") }
        window.makeKeyAndOrderFront(nil)

        // 5. Resize with Original size unticked, then ticked: the picture is the chosen size either way and the box has nothing left to bring back.
        loadSynthetic(size: CGSize(width: 2400, height: 1600), name: "Audit 8 resize")
        placeWindow(windowSize(for: "980xmin", surface: "S45") ?? CGSize(width: 980, height: window.minSize.height))
        app.dragOriginalControl.state = .off; app.changeDragOptions(nil); app.updateDragPreview(); pump(0.3)
        shoot("S45", "resize-unticked-before", surface: "Editor title and footer", state: "Original size unticked on a 2400 × 1600 snap: the title reads the shown size \(app.window.subtitle)", crop: footerCrop(),
              refs: ["AppViewport.swift|var isLargeShot"], settle: 0.2, extra: ["subtitle": app.window.subtitle, "pictureSize": NSStringFromSize(canvas.canvasSize)])
        app.resize(); pump(0.9)
        func titled(_ title: String, in root: NSView?) -> NSButton? {
            guard let root else { return nil }
            if let button = root as? NSButton, button.title == title { return button }
            for sub in root.subviews { if let hit = titled(title, in: sub) { return hit } }
            return nil
        }
        if let sheet = window.attachedSheet, let width = firstView(of: NSTextField.self, label: "Width in pixels", in: sheet.contentView), let apply = titled("Apply", in: sheet.contentView) {
            width.stringValue = "1200"
            width.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: width))
            apply.performClick(nil); pump(0.6)
            if let cancel = titled("Cancel", in: sheet.contentView) { cancel.performClick(nil) } else { window.endSheet(sheet, returnCode: .cancel) }
            pump(0.6)
            shoot("S45", "resize-unticked-after", surface: "Editor title and footer", state: "after Resize to 1200 wide with the box unticked: the picture is \(NSStringFromSize(canvas.canvasSize)), the title reads \(app.window.subtitle) and the box has nothing to offer (F-J7-005)",
                  refs: ["AppViewport.swift|let rewritesPicture"], settle: 0.2, extra: ["subtitle": app.window.subtitle, "pictureSize": NSStringFromSize(canvas.canvasSize), "checkboxHidden": app.dragOriginalControl.isHidden])
            app.dragOriginalControl.state = .on; app.changeDragOptions(nil); app.updateDragPreview(); pump(0.4)
            shoot("S45", "resize-then-ticked", surface: "Editor title and footer", state: "the box ticked afterwards: nothing changes, the title still reads \(app.window.subtitle) (F-J7-005)",
                  refs: ["AppViewport.swift|var dragAtOriginalSize"], settle: 0.2, extra: ["subtitle": app.window.subtitle, "pictureSize": NSStringFromSize(canvas.canvasSize)])
        } else { gap("S45", "Resize unticked", "the Resize sheet, its Width field or its Apply button was not found") }
        app.activeResizeSession?.cancel()
    }
}
