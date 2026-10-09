import AppKit

/// PROTOTYPE MOCK (audit harness only, NOT product): re-parents the live Modern chrome's own controls into a rail-less layout
/// inside the audit process so it can be rendered and measured. Nothing here ships; it only runs behind --eye-dump-audit.
///   TOP:    [Hide][Toolbox][Photos] · [Snap][Cancel (Frame only)] · 10 tools @44pt · [Color][Stroke width pill (mock)][Font]
///   BOTTOM: [Undo][Wipe] · [Zoom][Resize…] · status (flex) · [Save][History] · [PNG|JPG][Drag][Upload]
@available(macOS 26, *)
extension AuditRun {
    func installProto(_ chrome: ModernEditorChrome) -> [String: Any] {
        typealias Metrics = GlassChrome.Metrics
        func surface(_ control: NSView) -> GlassSurfaceView? { chrome.surface(for: control) }
        guard let footer = find("OpenSkitchFooter"), let rail = find("GlassCaptureGroup")?.superview else { return ["error": "chrome views not found"] }

        // Retire the old groups' presentation; their surfaces move into the new groups below.
        for id in ["GlassHeaderLeading", "GlassToolBar", "GlassHeaderTrailing", "GlassCaptureGroup", "GlassDrawingGroup", "GlassHistoryGroup", "GlassFooterRow", "OpenSkitchStatusRow"] {
            find(id)?.isHidden = true
        }
        rail.isHidden = true

        let toolOrder = ["select", "brush", "line", "ellipse", "rectangle", "fill", "eraser", "text", "arrow", "crop"]
        var toolSurfaces: [NSView] = []
        for id in toolOrder {
            if let button = chrome.toolButtons[id], let s = surface(button) {
                s.setSize(NSSize(width: 44, height: Metrics.toolButton.height)); toolSurfaces.append(s)
            }
        }
        let pillSlider = NSSlider(value: 6.75, minValue: 1.5, maxValue: 12, target: nil, action: nil)
        pillSlider.setAccessibilityLabel("MOCK stroke width (horizontal)")
        let pill = GlassChrome.surface(pillSlider, shape: .capsule, accessibility: chrome.accessibility, size: NSSize(width: 120, height: Metrics.iconButton.height))

        func group(_ views: [NSView?], _ id: String, spacing: CGFloat = Metrics.surfaceSpacing) -> NSGlassEffectContainerView {
            let g = GlassChrome.group(views.compactMap { $0 }, orientation: .horizontal, identifier: id, spacing: spacing)
            g.translatesAutoresizingMaskIntoConstraints = false
            return g
        }
        let g1 = group([surface(chrome.hideButton), surface(app.bezelToolboxForProto(chrome)), surface(chrome.photosButton)], "ProtoGroupHidePhotos")
        let g2 = group([surface(chrome.snapButton), surface(chrome.cancelFrameButton)], "ProtoGroupCapture")
        let g3 = group(toolSurfaces, "ProtoGroupTools", spacing: Metrics.toolSpacing)
        let g4 = group([surface(app.paletteButton), pill, surface(chrome.fontButton)], "ProtoGroupDrawing")

        let top = NSStackView(views: [g1, g2, g3, g4])
        top.orientation = .horizontal; top.alignment = .centerY; top.distribution = .equalSpacing; top.spacing = 12
        top.identifier = NSUserInterfaceItemIdentifier("ProtoTopRow")
        top.translatesAutoresizingMaskIntoConstraints = false
        chrome.header.addSubview(top)
        let topTrailing = top.trailingAnchor.constraint(equalTo: chrome.header.trailingAnchor); topTrailing.priority = .init(750)
        NSLayoutConstraint.activate([top.leadingAnchor.constraint(equalTo: chrome.header.leadingAnchor), topTrailing, top.centerYAnchor.constraint(equalTo: chrome.header.centerYAnchor)])

        let b1 = group([surface(chrome.undoButton), surface(chrome.wipeButton)], "ProtoGroupUndoWipe")
        app.zoomControl.removeFromSuperview()
        app.zoomControl.translatesAutoresizingMaskIntoConstraints = false
        let zoomWidth = app.zoomControl.constraints.first { $0.firstAttribute == .width }
        zoomWidth?.isActive = false
        let b2 = NSStackView(views: [app.zoomControl, surface(chrome.resizeButton)].compactMap { $0 })
        b2.orientation = .horizontal; b2.alignment = .centerY; b2.spacing = 8; b2.identifier = NSUserInterfaceItemIdentifier("ProtoGroupZoomResize")
        b2.translatesAutoresizingMaskIntoConstraints = false
        app.status.removeFromSuperview()
        app.status.translatesAutoresizingMaskIntoConstraints = false
        app.status.setContentHuggingPriority(.init(1), for: .horizontal)
        app.status.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let b4 = group([surface(chrome.saveButton), surface(chrome.historyButton)], "ProtoGroupSaveHistory")
        let b5 = group([surface(chrome.dragFormatControlForProto(app)), surface(app.dragExportView ?? NSView()), surface(chrome.shareButton)], "ProtoGroupOutput")
        let bottom = NSStackView(views: [b1, b2, app.status, b4, b5])
        bottom.orientation = .horizontal; bottom.alignment = .centerY; bottom.distribution = .fill; bottom.spacing = 12
        bottom.identifier = NSUserInterfaceItemIdentifier("ProtoBottomRow")
        bottom.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(bottom)
        let bottomTrailing = bottom.trailingAnchor.constraint(equalTo: footer.trailingAnchor); bottomTrailing.priority = .init(750)
        NSLayoutConstraint.activate([bottom.leadingAnchor.constraint(equalTo: footer.leadingAnchor), bottomTrailing, bottom.centerYAnchor.constraint(equalTo: footer.centerYAnchor)])
        app.dragOriginalControl.isHidden = true
        app.dragSizeLabel.isHidden = true

        // The canvas runs to the trailing margin: drop the constraint that tied it to the retired rail.
        for constraint in chrome.constraints where constraint.firstItem === chrome.scrollView && constraint.firstAttribute == .trailing { constraint.isActive = false }
        chrome.scrollView.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -12).isActive = true
        chrome.layoutSubtreeIfNeeded()
        return ["installed": true]
    }

    func measureProto(width: CGFloat, frameMode: Bool) -> [String: Any] {
        var f = window.frame; f.size.width = width; window.setFrame(f, display: true); pump(0.4)
        if frameMode { app.enterFrame(keepingAnnotations: false, manualFlags: []) } else { app.leaveFrame() }
        pump(0.6)
        window.contentView?.layoutSubtreeIfNeeded()
        var out: [String: Any] = ["windowWidth": Double(window.frame.width), "frameMode": frameMode]
        func rowInfo(_ id: String, containerID: String?, container: NSView?) -> [String: Any] {
            guard let row = find(id) as? NSStackView, let parent = container ?? containerID.flatMap({ find($0) }) else { return ["error": "missing \(id)"] }
            let available = Double(parent.bounds.width)
            let groups = row.arrangedSubviews.filter { !$0.isHidden }.map { v -> [String: Any] in
                var d = box(v); d["id"] = v.identifier?.rawValue ?? String(describing: type(of: v)); d["fittingWidth"] = Double(v.fittingSize.width); return d
            }
            let needed = row.arrangedSubviews.filter { !$0.isHidden }.reduce(0.0) { $0 + Double($1.fittingSize.width) } + Double(max(0, row.arrangedSubviews.filter { !$0.isHidden }.count - 1)) * Double(row.spacing)
            let rowFrame = row.convert(row.bounds, to: parent)
            return ["groups": groups, "rowFittingWidth": Double(row.fittingSize.width), "sumOfGroupFittingPlusSpacing": needed, "availableWidth": available,
                    "slackOrOverflow": available - needed, "rowFrameWidth": Double(rowFrame.width), "rowMaxXBeyondParent": Double(rowFrame.maxX) - available]
        }
        if #available(macOS 26, *), let chrome = app.modernChrome as? ModernEditorChrome {
            out["top"] = rowInfo("ProtoTopRow", containerID: nil, container: chrome.header)
            var bottom = rowInfo("ProtoBottomRow", containerID: "OpenSkitchFooter", container: nil)
            let statusNeed = textWidth("Brush · Unsaved changes", size: 18)
            if let sum = bottom["sumOfGroupFittingPlusSpacing"] as? Double, let avail = bottom["availableWidth"] as? Double {
                // the status label itself contributes ~0 to the sum (it is the flexible element)
                bottom["statusLabelWidthIfEverythingElseFixed"] = avail - (sum - Double(app.status.fittingSize.width)) - 12
                bottom["statusNeedsAt18pt"] = statusNeed
                bottom["bottomOverflowIfStatusFullyShown"] = statusNeed - (avail - (sum - Double(app.status.fittingSize.width)) - 12)
            }
            out["bottom"] = bottom
            out["scrollView"] = box(chrome.scrollView)
            out["scrollViewTrailingGapToWindowEdge"] = Double(window.frame.width - chrome.scrollView.convert(chrome.scrollView.bounds, to: nil).maxX)
        }
        return out
    }

    func proto() {
        guard #available(macOS 26, *), let chrome = app.modernChrome as? ModernEditorChrome else { gap("PROTO", "prototype", "no Modern chrome"); return }
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Prototype mock")
        _ = addAllAnnotationKinds(scale: 0.8)
        app.setTool(.brush)
        app.status.stringValue = "Brush · Unsaved changes"
        _ = installProto(chrome)
        var samples: [[String: Any]] = []
        for width in [980, 1280] {
            for frameMode in [false, true] {
                var measured = measureProto(width: CGFloat(width), frameMode: frameMode)
                let slug = "w\(width)-\(frameMode ? "frame" : "normal")"
                shoot("PROTO", slug, surface: "PROTOTYPE MOCK (not product): rail-less layout", state: "mock at window width \(width), \(frameMode ? "Frame mode" : "normal")",
                      refs: ["ModernEditorChrome.swift|private func build(actions", "EyeDumpAuditProto.swift|func installProto"], settle: 0.5, extra: ["prototype": true])
                measured["slug"] = slug
                samples.append(measured)
            }
        }
        write(["sourceSha": ProcessInfo.processInfo.environment["AUDIT_SOURCE_SHA"] ?? "unknown", "appearance": appearance, "samples": samples,
               "note": "PROTOTYPE MOCK, audit process only; stroke width pill is a mock horizontal NSSlider; Original size checkbox and size label hidden (see layout budget for their widths)"],
              to: "layout/proto-\(appearance)-\(ProcessInfo.processInfo.environment["AUDIT_SOURCE_SHA"] ?? "unknown").json")
        _ = chrome
    }
}

@available(macOS 26, *)
extension AppDelegate {
    func bezelToolboxForProto(_ chrome: ModernEditorChrome) -> NSView {
        func walk(_ view: NSView) -> NSView? {
            if let popup = view as? NSPopUpButton, popup.accessibilityLabel() == "Toolbox" { return popup }
            for sub in view.subviews { if let hit = walk(sub) { return hit } }
            return nil
        }
        return walk(chrome) ?? NSView()
    }
}

@available(macOS 26, *)
extension ModernEditorChrome {
    func dragFormatControlForProto(_ app: AppDelegate) -> NSView { app.dragFormatToggle }
}
