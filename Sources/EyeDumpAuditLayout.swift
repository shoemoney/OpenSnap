import AppKit

/// Live layout-width budget (audit harness only). Measures real frames and fitting sizes of the Modern editor chrome at several
/// window widths, in normal and Frame mode, and writes layout/budget-<sha>.json. No pixels are captured.
extension AuditRun {
    func box(_ view: NSView) -> [String: Any] {
        let r = view.convert(view.bounds, to: nil)
        let frame = CGRect(x: r.minX, y: window.frame.height - r.maxY, width: r.width, height: r.height)
        let fit = view.fittingSize
        return ["frame": rectJSON(frame), "fitting": [Double(fit.width), Double(fit.height)], "hidden": view.isHidden || view.alphaValue <= 0.01,
                "class": String(describing: type(of: view))]
    }

    func firstStack(in view: NSView) -> NSStackView? {
        if let stack = view as? NSStackView { return stack }
        if #available(macOS 26, *), let container = view as? NSGlassEffectContainerView, let content = container.contentView { return firstStack(in: content) }
        for sub in view.subviews { if let hit = firstStack(in: sub) { return hit } }
        return nil
    }

    func describeGroup(_ identifier: String) -> [String: Any]? {
        guard let group = find(identifier) else { return nil }
        var info = box(group)
        if let stack = firstStack(in: group) {
            info["controls"] = stack.arrangedSubviews.map { item -> [String: Any] in
                var entry = box(item)
                entry["label"] = item.accessibilityLabel() ?? ((item as? NSControl)?.accessibilityLabel() ?? "")
                if #available(macOS 26, *), let inner = (item as? NSGlassEffectView)?.contentView {
                    entry["content"] = String(describing: type(of: inner))
                    entry["contentLabel"] = inner.accessibilityLabel() ?? ""
                    entry["contentFitting"] = [Double(inner.fittingSize.width), Double(inner.fittingSize.height)]
                }
                return entry
            }
            info["spacing"] = Double(stack.spacing)
        }
        return info
    }

    func textWidth(_ text: String, size: CGFloat) -> Double {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size)
        return Double(ceil(field.fittingSize.width))
    }

    func measureLayout(width: CGFloat, frameMode: Bool, scenario: String) -> [String: Any] {
        var f = window.frame; f.size.width = width; f.size.height = 772
        window.setFrame(f, display: true)
        pump(0.5)
        if frameMode { app.enterFrame(keepingAnnotations: false, manualFlags: []) } else { app.leaveFrame() }
        pump(0.6)
        window.contentView?.layoutSubtreeIfNeeded()
        app.updateDragPreview()
        window.contentView?.layoutSubtreeIfNeeded()
        var result: [String: Any] = ["windowWidth": Double(window.frame.width), "windowHeight": Double(window.frame.height), "requestedWidth": Double(width),
                                     "frameMode": frameMode, "scenario": scenario, "status": app.status.stringValue, "dragSizeLabel": app.dragSizeLabel.stringValue]
        let content = window.contentView
        result["contentSize"] = [Double(content?.bounds.width ?? 0), Double(content?.bounds.height ?? 0)]
        var headerGroups: [String: Any] = [:]
        for id in ["GlassHeaderLeading", "GlassToolBar", "GlassHeaderTrailing"] { headerGroups[id] = describeGroup(id) as Any }
        result["header"] = headerGroups
        if let header = find("OpenSkitchHeader") {
            result["headerRow"] = box(header)
            var slack: [String: Any] = [:]
            func frameOf(_ id: String) -> CGRect? { find(id).map { $0.convert($0.bounds, to: nil) } }
            if let a = frameOf("GlassHeaderLeading"), let b = frameOf("GlassToolBar"), let c = frameOf("GlassHeaderTrailing"), let row = Optional(header.convert(header.bounds, to: nil)) {
                slack["leadingToTools"] = Double(b.minX - a.maxX)
                slack["toolsToTrailing"] = Double(c.minX - b.maxX)
                slack["rowWidth"] = Double(row.width)
                slack["sumOfGroupWidths"] = Double(a.width + b.width + c.width)
                slack["totalFreeHorizontal"] = Double(row.width - (a.width + b.width + c.width))
                slack["leftInset"] = Double(a.minX - row.minX); slack["rightInset"] = Double(row.maxX - c.maxX)
            }
            result["headerSlack"] = slack
        }
        var railGroups: [String: Any] = [:]
        var rects: [CGRect] = []
        for id in ["GlassCaptureGroup", "GlassDrawingGroup", "GlassHistoryGroup"] {
            railGroups[id] = describeGroup(id) as Any
            if let view = find(id), !view.isHidden { rects.append(view.convert(view.bounds, to: nil)) }
        }
        result["rail"] = railGroups
        if let rail = find("GlassCaptureGroup")?.superview {
            let r = rail.convert(rail.bounds, to: nil)
            let groupArea = rects.reduce(0) { $0 + $1.width * $1.height }
            let union = rects.reduce(CGRect.null) { $0.union($1) }
            let windowArea = window.frame.width * window.frame.height
            let contentArea = (content?.bounds.width ?? 1) * (content?.bounds.height ?? 1)
            result["railColumn"] = ["frame": rectJSON(CGRect(x: r.minX, y: window.frame.height - r.maxY, width: r.width, height: r.height)),
                                    "areaPt2": Double(r.width * r.height), "groupsAreaPt2": Double(groupArea),
                                    "blankAreaPt2": Double(r.width * r.height - groupArea),
                                    "blankPctOfWindow": Double((r.width * r.height - groupArea) / windowArea * 100),
                                    "blankPctOfContent": Double((r.width * r.height - groupArea) / contentArea * 100),
                                    "groupsBoundingBox": rectJSON(union.isNull ? .zero : union), "railWidth": Double(r.width)]
        }
        var footer: [String: Any] = [:]
        footer["zoomPopup"] = box(app.zoomControl)
        footer["originalSizeCheckbox"] = box(app.dragOriginalControl)
        footer["dragSizeLabel"] = box(app.dragSizeLabel)
        footer["status"] = box(app.status)
        footer["statusStringWidthAt18pt"] = textWidth(app.status.stringValue, size: 18)
        footer["dragSizeLabelStringWidthAt18pt"] = textWidth(app.dragSizeLabel.stringValue, size: 18)
        footer["footerRowGroup"] = describeGroup("GlassFooterRow") as Any
        if let statusRow = find("OpenSkitchStatusRow") { footer["statusRow"] = box(statusRow) }
        if let foot = find("OpenSkitchFooter"), let statusRow = find("OpenSkitchStatusRow"), let group = find("GlassFooterRow") {
            let row = foot.convert(foot.bounds, to: nil), s = statusRow.convert(statusRow.bounds, to: nil), g = group.convert(group.bounds, to: nil)
            footer["footerRow"] = box(foot)
            footer["slack"] = ["rowWidth": Double(row.width), "statusRowWidth": Double(s.width), "groupWidth": Double(g.width),
                               "gapBetweenStatusRowAndGroup": Double(g.minX - s.maxX), "totalFree": Double(row.width - s.width - g.width),
                               "statusLabelFrameWidth": Double(app.status.frame.width), "statusLabelNeedsAt18pt": footer["statusStringWidthAt18pt"] as Any,
                               "statusTruncated": Double(app.status.frame.width) + 0.5 < (footer["statusStringWidthAt18pt"] as? Double ?? 0)]
        }
        result["footer"] = footer
        if #available(macOS 26, *), let chrome = app.modernChrome as? ModernEditorChrome {
            result["scrollView"] = box(chrome.scrollView)
            result["scrollViewContentSize"] = [Double(chrome.scrollView.contentView.bounds.width), Double(chrome.scrollView.contentView.bounds.height)]
            result["canvasFrame"] = box(app.canvas)
            result["canvasBorder"] = box(app.canvasBorder)
            result["scrollTrailingGapToWindowEdge"] = Double(window.frame.width - chrome.scrollView.convert(chrome.scrollView.bounds, to: nil).maxX)
        }
        return result
    }

    func layoutBudget() {
        let sha = ProcessInfo.processInfo.environment["AUDIT_SOURCE_SHA"] ?? "unknown"
        let widths: [CGFloat] = [980, 1024, 1280, 1440]
        var samples: [[String: Any]] = []
        let defaultFrame = window.frame
        for scenario in ["small-image", "large-image"] {
            let size = scenario == "small-image" ? CGSize(width: 1000, height: 700) : CGSize(width: 2400, height: 1500)
            for width in widths {
                for frameMode in [false, true] {
                    loadSynthetic(size: size, name: "Layout")
                    app.leaveFrame()
                    app.status.stringValue = "Brush · Unsaved changes"
                    samples.append(measureLayout(width: width, frameMode: frameMode, scenario: scenario))
                    app.leaveFrame()
                    window.setFrame(defaultFrame, display: true)
                    pump(0.2)
                }
            }
        }
        var typical: [String: Any] = [:]
        for text in ["Brush · Unsaved changes", "Brush · Saved", "Select · Unsaved changes", "Frame: position the window, then Snap", "Frame: Snap keeps your drawing",
                     "Link copied: https://cdn.example.com/pics/Quarterly-mockup-0000.png", "800 × 600 · 10 KB", "2400 × 1500 · 610 KB"] {
            typical[text] = textWidth(text, size: 18)
        }
        write(["sourceSha": sha, "widths": widths.map { Double($0) }, "samples": samples, "statusTextWidthsAt18pt": typical,
               "note": "frames are window points, top-left origin; fitting = NSView.fittingSize; hidden = isHidden or alpha 0"], to: "layout/budget-\(sha).json")
    }
}
