// G12 / OSN-070 layout fit, on the LIVE window: at the 980 pt minimum width, in normal and Frame mode, in light and dark, with the Original size
// toggle shown and hidden, no bar group, no control inside one, and no zoom or Original size control needs more room than it was given
// (fitting size <= frame). The status line is elastic (it truncates) and is judged by its own cases. The same fitting-versus-frame rule runs
// over the committed layout.json evidence in tools/check-layout-fit.py.
// Run through tools/test-app-safety.sh; no window is ever put on screen.
#if APP_SAFETY_TESTS
import AppKit

extension AppSafetyTests {
    static var layoutFitCases: [(String, () throws -> Void)] {
        [
            ("Layout fit at 980: every bar group and control fits its frame in normal and Frame mode, light and dark, Original size toggle shown and hidden", layoutFitAtMinimumWidth),
            ("Frame outline sits on all four edges of the transparent capture area at the default size, 980, 1024 and 1280", frameOutlineMatchesCaptureArea),
            ("Layout fit can fail: a group squeezed below what its controls need is reported", layoutFitCanFail)
        ]
    }

    private static let fitGroupIDs = ["GlassHeaderLeading", "GlassCaptureGroup", "GlassToolBar", "GlassAnnotationGroup",
                                      "GlassUndoWipeGroup", "GlassViewGroup", "GlassSaveGroup", "GlassFooterRow"]

    private static func visibleInWindow(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let node = current { if node.isHidden || node.alphaValue <= 0.01 { return false }; current = node.superview }
        return true
    }

    private static func firstStack(in view: NSView) -> NSStackView? {
        if let stack = view as? NSStackView { return stack }
        if let container = view as? NSGlassEffectContainerView, let content = container.contentView { return firstStack(in: content) }
        for sub in view.subviews { if let hit = firstStack(in: sub) { return hit } }
        return nil
    }

    /// The bar groups under `root` and the controls arranged inside them, with a name each.
    private static func fitTargets(under root: NSView) -> [(String, NSView)] {
        var named: [(String, NSView)] = []
        func walk(_ view: NSView) {
            if let id = view.identifier?.rawValue, fitGroupIDs.contains(id) {
                named.append((id, view))
                if let stack = firstStack(in: view) {
                    for item in stack.arrangedSubviews { named.append(("\(id)>\(item.accessibilityLabel() ?? String(describing: type(of: item)))", item)) }
                }
                return
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return named
    }

    /// One message per visible view under `root` (the bar groups, their arranged controls, and `extras`) whose fitting size exceeds its frame.
    private static func clippedControls(under root: NSView, extras: [(String, NSView)] = []) -> [String] {
        var problems: [String] = []
        for (name, view) in fitTargets(under: root) + extras where visibleInWindow(view) {
            let fit = view.fittingSize, frame = view.frame
            if fit.width > 0, fit.width > frame.width + 0.5 { problems.append("\(name) needs \(fit.width) pt wide, has \(frame.width)") }
            if fit.height > 0, fit.height > frame.height + 0.5 { problems.append("\(name) needs \(fit.height) pt tall, has \(frame.height)") }
        }
        return problems
    }

    private static func layoutFitAtMinimumWidth() throws {
        let fixture = try Fixture(), app = fixture.app
        guard let chrome = app.modernChrome as? ModernEditorChrome else { throw Failure(description: "AppDelegate did not build ModernEditorChrome") }
        chrome.accessibility = .none
        guard let content = app.window.contentView else { throw Failure(description: "Missing content view") }
        let width = ModernEditorChrome.minimumWindowWidth
        try expect(width == 980, "The minimum width is 980 pt (\(width))")
        let height = app.window.minSize.height
        var checked = 0
        defer { app.window.appearance = nil }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            app.window.appearance = NSAppearance(named: appearance)
            for frameMode in [false, true] {
                for toggleShown in [false, true] {
                    app.setWindowFrame(CGRect(origin: app.window.frame.origin, size: CGSize(width: width, height: height)))
                    try viewportFixture(app)
                    if frameMode { app.enterFrame(keepingAnnotations: false, manualFlags: []) }
                    app.dragOriginalControl.isHidden = !toggleShown
                    content.layoutSubtreeIfNeeded()
                    let label = "\(appearance.rawValue) \(frameMode ? "Frame" : "normal") toggle \(toggleShown ? "shown" : "hidden")"
                    try expect(app.window.frame.width == width, "\(label): the window is \(width) pt wide (\(app.window.frame.width))")
                    try expect(app.frameMode == frameMode, "\(label): the mode is the one asked for")
                    let measured = fitTargets(under: content).filter { visibleInWindow($0.1) }.count
                    try expect(measured >= (frameMode ? 8 : 20), "\(label): the measurement really reached the bars' groups and controls (\(measured) views)")
                    let found = clippedControls(under: content, extras: [("zoom", app.zoomControl), ("originalSize", app.dragOriginalControl)])
                    try expect(found.isEmpty, "\(label): clipped controls at \(width) pt: \(found)")
                    checked += 1
                    if frameMode { app.cancelFrame() }
                }
            }
        }
        try expect(checked == 8, "All eight window states were measured (\(checked))")
    }

    /// The yellow outline is the capture area's boundary: its four edges must be drawn on the hole's four edges
    /// (inset by half the 2 pt stroke), at every window width, not on the canvas view's bounds.
    private static func frameOutlineMatchesCaptureArea() throws {
        let fixture = try Fixture(), app = fixture.app
        guard let content = app.window.contentView as? FrameChromeView, let scroll = content.canvasScrollView else { throw Failure(description: "Frame content view") }
        app.window.appearance = NSAppearance(named: .aqua)
        defer { app.window.appearance = nil }
        let startWidth = app.window.frame.width
        for width in [startWidth, 980, 1024, 1280] {
            try viewportFixture(app)
            app.canvas.newBlank(size: CGSize(width: 1000, height: 700))
            app.setCanvasDisplayZoom(1, label: "Test")
            app.setWindowFrame(CGRect(origin: app.window.frame.origin, size: CGSize(width: width, height: app.window.frame.height)))
            app.enterFrame(keepingAnnotations: false, manualFlags: [])
            content.layoutSubtreeIfNeeded(); app.canvas.displayIfNeeded()
            defer { app.cancelFrame() }
            guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw Failure(description: "The window content does not render") }
            content.cacheDisplay(in: content.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / content.bounds.width
            let hole = scroll.convert(scroll.bounds, to: content).intersection(content.bounds)
            func alpha(_ x: CGFloat, _ yFromTop: CGFloat) -> CGFloat {
                rep.colorAt(x: Int(x * scale), y: Int(yFromTop * scale))?.alphaComponent ?? 0
            }
            let top = content.bounds.height - hole.maxY, bottom = content.bounds.height - hole.minY
            // The outline is opaque; the hole around it is clear. Probe one point inside each edge, a third and two thirds along it.
            for fraction in [CGFloat(0.33), 0.66] {
                let x = hole.minX + hole.width * fraction, y = top + hole.height * fraction
                let probes: [(String, CGFloat, CGFloat)] = [("top", x, top + 1), ("bottom", x, bottom - 1),
                                                           ("left", hole.minX + 1, y), ("right", hole.maxX - 1, y)]
                for (edge, px, py) in probes {
                    try expect(alpha(px, py) > 0.5, "Frame at \(Int(width)) pt: the outline's \(edge) edge is not on the capture area's \(edge) edge (hole \(hole), probe \(px),\(py), alpha \(alpha(px, py)))")
                }
                let inner: [(String, CGFloat, CGFloat)] = [("top", x, top + 5), ("bottom", x, bottom - 5), ("left", hole.minX + 5, y), ("right", hole.maxX - 5, y)]
                for (edge, px, py) in inner {
                    try expect(alpha(px, py) < 0.05, "Frame at \(Int(width)) pt: a second line sits 5 pt inside the \(edge) edge (alpha \(alpha(px, py)))")
                }
                for (edge, px, py) in [("interior", x, y)] {
                    try expect(alpha(px, py) < 0.05, "Frame at \(Int(width)) pt: the capture area's \(edge) is not clear")
                }
            }
        }
    }

    private static func layoutFitCanFail() throws {
        let squeezed = NSStackView(views: (0..<3).map { NSButton(title: "A long control title \($0)", target: nil, action: nil) })
        squeezed.identifier = NSUserInterfaceItemIdentifier("GlassSaveGroup")
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        root.addSubview(squeezed)
        squeezed.frame = NSRect(x: 0, y: 0, width: 60, height: 44)
        let found = clippedControls(under: root)
        try expect(found.contains { $0.hasPrefix("GlassSaveGroup needs") }, "A group squeezed to 60 pt is reported as clipped: \(found)")
        squeezed.frame = NSRect(x: 0, y: 0, width: max(squeezed.fittingSize.width, 1), height: max(squeezed.fittingSize.height, 44))
        try expect(clippedControls(under: root).isEmpty, "The same group given its fitting size is not reported: \(clippedControls(under: root))")
    }
}
#endif
