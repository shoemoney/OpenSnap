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

    // MARK: post-rail chrome metrics

    static let topBarGroupIDs = ["GlassHeaderLeading", "GlassCaptureGroup", "GlassToolBar", "GlassAnnotationGroup"]
    static let bottomBarGroupIDs = ["GlassUndoWipeGroup", "GlassViewGroup", "GlassSaveGroup", "GlassFooterRow"]
    /// The two groups the permanent right rail used to hold. Either one existing again means the rail came back.
    static let retiredRailGroupIDs = ["GlassDrawingGroup", "GlassHistoryGroup"]
    static let viewportMargin = 12.0

    /// A view's rectangle in window points, top-left origin.
    func windowRect(_ view: NSView) -> CGRect {
        let r = view.convert(view.bounds, to: nil)
        return CGRect(x: r.minX, y: window.frame.height - r.maxY, width: r.width, height: r.height)
    }

    func visibleRects(_ ids: [String]) -> [(id: String, rect: CGRect)] {
        ids.compactMap { id in find(id).flatMap { $0.isHidden ? nil : (id, windowRect($0)) } }
    }

    /// Gaps between consecutive visible groups of one bar, left to right, plus the free space the row has left.
    func barSlack(_ ids: [String], row: CGRect?) -> [String: Any] {
        let groups = visibleRects(ids).sorted { $0.rect.minX < $1.rect.minX }
        var out: [String: Any] = [:]
        var gaps: [String: Double] = [:]
        for (a, b) in zip(groups, groups.dropFirst()) { gaps["\(a.id)->\(b.id)"] = Double(b.rect.minX - a.rect.maxX) }
        out["gaps"] = gaps
        out["minGap"] = gaps.values.min() ?? 0
        let sum = groups.reduce(0) { $0 + $1.rect.width }
        out["sumOfGroupWidths"] = Double(sum)
        if let row {
            out["rowWidth"] = Double(row.width)
            out["freeHorizontal"] = Double(row.width - sum)
            if let first = groups.first, let last = groups.last {
                out["leftInset"] = Double(first.rect.minX - row.minX); out["rightInset"] = Double(row.maxX - last.rect.maxX)
            }
        }
        var overlaps: [String] = []
        for (index, a) in groups.enumerated() { for b in groups.dropFirst(index + 1) where a.rect.intersects(b.rect) && !a.rect.intersection(b.rect).isEmpty { overlaps.append("\(a.id)&\(b.id)") } }
        out["overlaps"] = overlaps
        return out
    }

    /// Status width in the bottom bar with the Original-size checkbox forced visible and forced hidden, then restored.
    func statusWidthVariants() -> [String: Any] {
        let checkbox = app.dragOriginalControl, wasHidden = checkbox.isHidden
        func measure(hidden: Bool) -> [String: Double] {
            checkbox.isHidden = hidden
            window.contentView?.layoutSubtreeIfNeeded()
            return ["statusLabel": Double(app.status.frame.width), "statusRow": find("OpenSnapStatusRow").map { Double(windowRect($0).width) } ?? 0,
                    "checkbox": hidden ? 0 : Double(checkbox.frame.width)]
        }
        let with = measure(hidden: false), without = measure(hidden: true)
        checkbox.isHidden = wasHidden
        window.contentView?.layoutSubtreeIfNeeded()
        return ["withCheckbox": with, "withoutCheckbox": without, "checkboxShownNow": !wasHidden,
                "statusNeedsAt18pt": textWidth(app.status.stringValue, size: 18), "statusString": app.status.stringValue]
    }

    /// Everything the rail-removal acceptance cares about, read from the live window as it is right now: per-group frames for
    /// both bars, slack, status width, the viewport and its trailing margin, canvas centring, Frame-mode hole and capture rect,
    /// and the `rail` assertion. Frames are window points with a top-left origin.
    func chromeMetrics() -> [String: Any] {
        window.contentView?.layoutSubtreeIfNeeded()
        let contentWidth = Double(window.contentView?.bounds.width ?? window.frame.width)
        var result: [String: Any] = ["windowSize": [Double(window.frame.width), Double(window.frame.height)], "contentWidth": contentWidth,
                                     "frameMode": app.frameMode, "status": app.status.stringValue,
                                     // The drag-size label is an off-screen model now; the status line shows its text.
                                     "dragSizeLabelModel": app.dragSizeLabel.stringValue]
        var top: [String: Any] = [:]
        var topGroups: [String: Any] = [:]
        for id in AuditRun.topBarGroupIDs { topGroups[id] = describeGroup(id) as Any }
        top["groups"] = topGroups
        if let header = find("OpenSnapHeader") {
            top["row"] = box(header)
            top["slack"] = barSlack(AuditRun.topBarGroupIDs, row: windowRect(header))
            if let tools = find("GlassToolBar"), !tools.isHidden {
                let t = windowRect(tools), h = windowRect(header)
                top["toolsCentreOffsetFromRow"] = Double(t.midX - h.midX)
            }
        }
        top["snapTitle"] = app.snapButton.title
        top["cancelHidden"] = app.cancelFrameButton.isHidden
        result["topBar"] = top

        var bottom: [String: Any] = [:]
        var bottomGroups: [String: Any] = [:]
        for id in AuditRun.bottomBarGroupIDs { bottomGroups[id] = describeGroup(id) as Any }
        bottom["groups"] = bottomGroups
        if let footer = find("OpenSnapFooter") {
            bottom["row"] = box(footer)
            var ids = AuditRun.bottomBarGroupIDs; ids.insert("OpenSnapStatusRow", at: 2)
            bottom["slack"] = barSlack(ids, row: windowRect(footer))
        }
        bottom["zoomPopup"] = box(app.zoomControl)
        bottom["zoomTitle"] = app.zoomControl.titleOfSelectedItem ?? ""
        bottom["originalSizeCheckbox"] = box(app.dragOriginalControl)
        bottom["status"] = box(app.status)
        if let statusRow = find("OpenSnapStatusRow") { bottom["statusRow"] = box(statusRow) }
        bottom["statusWidths"] = statusWidthVariants()
        bottom["statusTruncated"] = Double(app.status.frame.width) + 0.5 < textWidth(app.status.stringValue, size: 18)
        bottom["formatSegments"] = app.dragFormatToggle.selectedSegment
        result["bottomBar"] = bottom

        let retired = AuditRun.retiredRailGroupIDs.filter { find($0) != nil }
        guard #available(macOS 26, *), let chrome = app.modernChrome as? ModernEditorChrome else {
            result["rail"] = "unknown: no Modern chrome"
            return result
        }
        let scroll = windowRect(chrome.scrollView)
        let header = find("OpenSnapHeader").map(windowRect), footer = find("OpenSnapFooter").map(windowRect)
        var viewport: [String: Any] = ["rect": rectJSON(scroll), "trailingMargin": contentWidth - Double(scroll.maxX), "leadingMargin": Double(scroll.minX),
                                       "contentSize": [Double(chrome.scrollView.contentView.bounds.width), Double(chrome.scrollView.contentView.bounds.height)]]
        if let header { viewport["gapBelowTopBar"] = Double(scroll.minY - header.maxY) }
        if let footer { viewport["gapAboveBottomBar"] = Double(footer.minY - scroll.maxY) }
        let visible = windowRectFromBottomLeft(app.canvas.convert(app.canvas.visibleRect, to: nil))
        // Centring and filling are judged against the clip view: legacy scrollers take a 15-17 pt gutter out of the scroll view's own frame.
        let clip = windowRect(chrome.scrollView.contentView)
        let gapLeft = Double(visible.minX - clip.minX), gapRight = Double(clip.maxX - visible.maxX)
        let gapTop = Double(visible.minY - clip.minY), gapBottom = Double(clip.maxY - visible.maxY)
        viewport["clipRect"] = rectJSON(clip)
        viewport["scrollerGutter"] = [Double(scroll.width - clip.width), Double(scroll.height - clip.height)]
        viewport["scrollerStyle"] = chrome.scrollView.scrollerStyle == .legacy ? "legacy" : "overlay"
        viewport["canvasVisible"] = rectJSON(visible)
        viewport["canvas"] = ["frameInWindow": rectJSON(windowRect(app.canvas)), "canvasSize": [Double(app.canvas.canvasSize.width), Double(app.canvas.canvasSize.height)],
                              "zoom": Double(app.canvas.zoom), "gapLeft": gapLeft, "gapRight": gapRight, "gapTop": gapTop, "gapBottom": gapBottom,
                              "fillsWidth": gapLeft <= 0.5 && gapRight <= 0.5, "fillsHeight": gapTop <= 0.5 && gapBottom <= 0.5,
                              "centredHorizontally": abs(gapLeft - gapRight) <= 1, "centredVertically": abs(gapTop - gapBottom) <= 1] as [String: Any]
        result["viewport"] = viewport

        // Rail assertion: neither retired group exists, the viewport reaches the 12-pt margin, and nothing narrow is parked on the trailing edge.
        let known: Set<String> = ["OpenSnapHeader", "OpenSnapFooter"]
        let strays = chrome.subviews.filter { sub in
            guard !sub.isHidden, sub !== chrome.scrollView, !known.contains(sub.identifier?.rawValue ?? "") else { return false }
            let r = windowRect(sub)
            return r.width < Double(contentWidth) * 0.2 && r.height > 100 && r.maxX >= CGFloat(contentWidth) - 0.5
        }.map { String(describing: type(of: $0)) }
        let marginOK = abs((viewport["trailingMargin"] as? Double ?? -1) - AuditRun.viewportMargin) <= 0.5
        let absent = retired.isEmpty && marginOK && strays.isEmpty
        result["rail"] = absent ? "absent" : "PRESENT"
        result["railChecks"] = ["retiredGroupsFound": retired, "trailingMarginIs12": marginOK, "trailingStrayViews": strays]

        if app.frameMode {
            let capture = windowRectFromBottomLeft(app.window.convertFromScreen(app.frameViewportScreenRect))
            let hole = scroll.intersection(CGRect(x: 0, y: 0, width: CGFloat(contentWidth), height: window.frame.height))
            var overlapping: [String] = []
            for (id, rect) in visibleRects(AuditRun.topBarGroupIDs + AuditRun.bottomBarGroupIDs + ["OpenSnapStatusRow"]) where rect.intersects(hole) && !rect.intersection(hole).isEmpty { overlapping.append(id) }
            result["frameHole"] = ["hole": rectJSON(hole), "holeMaxXToMargin": contentWidth - AuditRun.viewportMargin - Double(hole.maxX),
                                   "captureRect": rectJSON(capture), "captureEqualsHole": [abs(capture.minX - hole.minX), abs(capture.minY - hole.minY), abs(capture.maxX - hole.maxX), abs(capture.maxY - hole.maxY)].allSatisfy { $0 <= 1 },
                                   "captureInsideHole": hole.insetBy(dx: -1, dy: -1).contains(capture), "controlsOverlappingHole": overlapping,
                                   "photosHidden": find("GlassHeaderLeading").map { $0.isHidden } ?? true]
        }
        return result
    }

    /// `rect` is in window coordinates with a bottom-left origin (what `convert(_, to: nil)` and `convertFromScreen` return).
    func windowRectFromBottomLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: window.frame.height - rect.maxY, width: rect.width, height: rect.height)
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
        var result = chromeMetrics()
        result["windowWidth"] = Double(window.frame.width); result["windowHeight"] = Double(window.frame.height)
        result["requestedWidth"] = Double(width); result["scenario"] = scenario
        return result
    }

    func layoutBudget() {
        let sha = sourceSha
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
        // Top-bar slack in normal and Frame mode, bottom-bar status width with and without the checkbox, per scenario and width.
        func number(_ sample: [String: Any], _ path: [String]) -> Double? {
            var node: Any? = sample
            for key in path { node = (node as? [String: Any])?[key] }
            return node as? Double
        }
        let summary: [[String: Any]] = samples.map { sample in
            ["scenario": sample["scenario"] as Any, "windowWidth": sample["windowWidth"] as Any, "frameMode": sample["frameMode"] as Any, "rail": sample["rail"] as Any,
             "topBarFreeHorizontal": number(sample, ["topBar", "slack", "freeHorizontal"]) as Any, "topBarMinGap": number(sample, ["topBar", "slack", "minGap"]) as Any,
             "bottomBarFreeHorizontal": number(sample, ["bottomBar", "slack", "freeHorizontal"]) as Any,
             "statusRowWithCheckbox": number(sample, ["bottomBar", "statusWidths", "withCheckbox", "statusRow"]) as Any,
             "statusRowWithoutCheckbox": number(sample, ["bottomBar", "statusWidths", "withoutCheckbox", "statusRow"]) as Any,
             "statusLabelWithCheckbox": number(sample, ["bottomBar", "statusWidths", "withCheckbox", "statusLabel"]) as Any,
             "statusLabelWithoutCheckbox": number(sample, ["bottomBar", "statusWidths", "withoutCheckbox", "statusLabel"]) as Any,
             "viewportTrailingMargin": number(sample, ["viewport", "trailingMargin"]) as Any]
        }
        var typical: [String: Any] = [:]
        for text in ["Brush · Unsaved changes", "Brush · Saved", "Select · Unsaved changes", "Frame: position, then Snap", "Frame: Snap keeps your drawing",
                     "Link copied: https://cdn.example.com/pics/Quarterly-mockup-0000.png", "Brush · Unsaved changes · 2400 × 1500 · 610 KB"] {
            typical[text] = textWidth(text, size: 18)
        }
        write(["sourceSha": sha, "iconMode": iconMode, "appearance": appearance, "widths": widths.map { Double($0) }, "samples": samples, "summary": summary, "statusTextWidthsAt18pt": typical,
               "note": "frames are window points, top-left origin; fitting = NSView.fittingSize; hidden = isHidden or alpha 0"], to: "layout/budget-\(sha)\(iconMode == "sf" ? "" : "-" + iconMode).json")
    }
}
