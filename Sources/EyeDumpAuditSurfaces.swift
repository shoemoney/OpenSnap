import AppKit
import CoreGraphics

/// Surface flows for the audit harness. Every flow drives the app's own presentation code with synthetic content;
/// nothing here captures the screen, touches the network, the Keychain or the real stores.
extension AuditRun {
    var canvas: CanvasView { app.canvas }

    // MARK: helpers

    func step(_ id: String, _ surface: String, _ body: () -> Void) {
        guard wants(id) else { return }
        body()
        resetEditor()
        _ = surface
    }

    /// Back to a known editor state between surfaces.
    func resetEditor() {
        for sheet in [window.attachedSheet].compactMap({ $0 }) { window.endSheet(sheet, returnCode: .cancel); sheet.orderOut(nil) }
        app.activeResizeSession?.cancel()
        app.publishing.cancelSettings()
        canvas.commitPendingTextEditing()
        app.closeDrawingColors()
        app.closeFontPanel()
        app.closePreferences()
        app.leaveFrame()
        app.leaveActualSize()
        if app.dragThumbnailWindow != nil { app.removeDragThumbnail(); app.showEditorImmediately() }
        canvas.cropRect = nil
        canvas.selection = []
        app.setTool(.arrow)
        if let panel = NSColorPanel.shared as NSWindow?, panel.isVisible { panel.orderOut(nil) }
        for aux in NSApp.windows where aux !== window && aux.isVisible && aux.isKind(of: NSPanel.self) && String(describing: type(of: aux)).contains("About") { aux.orderOut(nil) }
        window.alphaValue = 1; window.level = .normal; window.hasShadow = true; window.isOpaque = true
        window.makeKeyAndOrderFront(nil)
        pump(0.15)
    }

    func find(_ identifier: String, in root: NSView? = nil) -> NSView? {
        func walk(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            for sub in view.subviews { if let hit = walk(sub) { return hit } }
            return nil
        }
        guard let start = root ?? window.contentView else { return nil }
        return walk(start)
    }

    func firstView<T: NSView>(of type: T.Type, label: String? = nil, in root: NSView? = nil) -> T? {
        func walk(_ view: NSView) -> T? {
            if let match = view as? T, label == nil || view.accessibilityLabel() == label { return match }
            for sub in view.subviews { if let hit = walk(sub) { return hit } }
            return nil
        }
        guard let start = root ?? window.contentView else { return nil }
        return walk(start)
    }

    /// Region of the window (points, top-left origin) covering a view, padded.
    func region(of view: NSView?, padding: CGFloat = 8) -> CGRect? {
        guard let view else { return nil }
        let inWindow = view.convert(view.bounds, to: nil)
        return CGRect(x: max(0, inWindow.minX - padding), y: max(0, window.frame.height - inWindow.maxY - padding),
                      width: inWindow.width + 2 * padding, height: inWindow.height + 2 * padding)
    }

    func headerCrop() -> CGRect? {
        guard let header = find("OpenSkitchHeader") else { return nil }
        let r = header.convert(header.bounds, to: nil)
        return CGRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height - r.minY + 6)
    }
    func footerCrop() -> CGRect? {
        guard let footer = find("OpenSkitchFooter") else { return nil }
        let r = footer.convert(footer.bounds, to: nil)
        let top = window.frame.height - r.maxY - 8
        return CGRect(x: 0, y: top, width: window.frame.width, height: window.frame.height - top)
    }

    func ownWindowNumbers(excluding known: Set<Int>) -> [NSWindow] {
        NSApp.windows.filter { !known.contains($0.windowNumber) && $0.isVisible && $0 !== window }
    }

    func mouse(_ type: NSEvent.EventType, docPoint: CGPoint, flags: NSEvent.ModifierFlags = [], clickCount: Int = 1) -> NSEvent? {
        let scale = canvas.displayScale
        let viewPoint = CGPoint(x: docPoint.x * scale.width, y: docPoint.y * scale.height)
        return NSEvent.mouseEvent(with: type, location: canvas.convert(viewPoint, to: nil), modifierFlags: flags,
                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                  context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1)
    }

    /// Runs `trigger` (which blocks in a modal alert/panel), captures the modal window once, aborts it.
    func captureModal(_ id: String, _ slug: String, surface: String, state: String, refs: [String], delay: TimeInterval = 0.9,
                      trigger: () -> Void) {
        var fired = false
        let timer = Timer(timeInterval: delay, repeats: false) { [self] _ in
            MainActor.assumeIsolated {
                fired = true
                if let modal = NSApp.modalWindow {
                    shoot(id, slug, surface: surface, state: state, windows: [modal], refs: refs, settle: 0)
                } else {
                    gap(id, surface + " / " + state, "no modal window was on screen when the capture fired")
                }
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trigger()
        timer.invalidate()
        if !fired { gap(id, surface + " / " + state, "the modal call returned before any window could be captured (it did not block; the panel is out-of-process or was refused in this environment)") }
    }

    /// Runs `trigger` (which blocks while a menu tracks), captures the app's windows including the menu, cancels tracking.
    func captureTrackedMenu(_ id: String, _ slug: String, surface: String, state: String, refs: [String],
                            delay: TimeInterval = 0.8, dismiss: @escaping () -> Void, trigger: () -> Void) {
        let known = Set(NSApp.windows.map(\.windowNumber))
        var fired = false
        var dismissTimer: Timer?
        let timer = Timer(timeInterval: delay, repeats: false) { [self] _ in
            MainActor.assumeIsolated {
                fired = true
                let extra = ownWindowNumbers(excluding: known)
                shoot(id, slug, surface: surface, state: state, windows: [window] + extra, refs: refs, settle: 0,
                      extra: ["menuWindows": extra.map { String(describing: type(of: $0)) }])
                dismiss()
                // Keep asking until tracking really ends; a single cancelTracking() has left a popUp blocking before.
                let again = Timer(timeInterval: 0.3, repeats: true) { _ in MainActor.assumeIsolated { dismiss(); NSApp.mainMenu?.cancelTracking() } }
                RunLoop.main.add(again, forMode: .common)
                dismissTimer = again
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trigger()
        dismissTimer?.invalidate()
        timer.invalidate()
        if !fired { gap(id, surface + " / " + state, "menu tracking returned before the capture timer fired (menu did not open)") }
    }

    /// Captures the sheet window itself (primary) and, separately, the parent with the sheet in context.
    func shootSheet(_ id: String, _ slug: String, surface: String, state: String, refs: [String], host: NSWindow, sheet: NSWindow) {
        sheet.displayIfNeeded()
        shoot(id, slug, surface: surface, state: state, windows: [sheet], refs: refs, settle: 0.4,
              extra: ["capturedWindow": "sheet itself", "sheetClass": String(describing: type(of: sheet)), "sheetOnScreen": sheet.isVisible])
        shoot(id, slug + "-in-context", surface: surface, state: state + " (parent window + sheet composite)", windows: [host, sheet], refs: refs, settle: 0.1,
              extra: ["capturedWindow": "parent + sheet composite"])
    }

    func captureSheet(_ id: String, _ slug: String, surface: String, state: String, refs: [String], parent: NSWindow? = nil,
                      wait: TimeInterval = 1.4, dismiss: (() -> Void)? = nil) {
        let host = parent ?? window
        pump(wait)
        if let sheet = host.attachedSheet ?? host.sheets.last {
            shootSheet(id, slug, surface: surface, state: state, refs: refs, host: host, sheet: sheet)
            if let dismiss { dismiss() } else { host.endSheet(sheet, returnCode: .cancel) }
            pump(0.4)
        } else {
            gap(id, surface + " / " + state, "the sheet did not attach to its parent window")
        }
    }

    // MARK: synthetic content

    static func syntheticImage(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.30, blue: 0.58, alpha: 1), NSColor(srgbRed: 0.58, green: 0.36, blue: 0.68, alpha: 1),
                                NSColor(srgbRed: 0.93, green: 0.55, blue: 0.40, alpha: 1)])?.draw(in: rect, angle: 35)
            let lorem = ["Lorem ipsum dolor sit amet, consectetur", "adipiscing elit, sed do eiusmod tempor", "incididunt ut labore et dolore magna",
                         "aliqua. Ut enim ad minim veniam, quis"]
            func fakeWindow(_ frame: CGRect, title: String, tone: CGFloat) {
                let body = NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow(); shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width: 0, height: -6)
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
                NSColor(white: tone, alpha: 1).setFill(); body.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSColor(white: tone - 0.08, alpha: 1).setFill()
                NSBezierPath(roundedRect: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 30), xRadius: 10, yRadius: 10).fill()
                for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                    color.setFill(); NSBezierPath(ovalIn: CGRect(x: frame.minX + 12 + CGFloat(index) * 20, y: frame.minY + 9, width: 12, height: 12)).fill()
                }
                (title as NSString).draw(at: CGPoint(x: frame.minX + 82, y: frame.minY + 6),
                                         withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor(white: 0.25, alpha: 1)])
                for (index, line) in lorem.enumerated() {
                    (line as NSString).draw(at: CGPoint(x: frame.minX + 20, y: frame.minY + 50 + CGFloat(index) * 26),
                                            withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor(white: 0.30, alpha: 1)])
                }
                NSColor(white: 0.82, alpha: 1).setFill()
                NSBezierPath(roundedRect: CGRect(x: frame.minX + 20, y: frame.minY + 168, width: min(220, frame.width - 40), height: 72), xRadius: 6, yRadius: 6).fill()
            }
            let w = rect.width, h = rect.height
            fakeWindow(CGRect(x: w * 0.06, y: h * 0.08, width: w * 0.50, height: h * 0.52), title: "Example Document", tone: 0.97)
            fakeWindow(CGRect(x: w * 0.44, y: h * 0.30, width: w * 0.48, height: h * 0.55), title: "Notes", tone: 0.93)
            return true
        }
    }

    func loadSynthetic(size: CGSize, name: String) {
        canvas.newBlank(size: size)
        canvas.setBackground(AuditRun.syntheticImage(size: size))
        app.documentGeneration = UUID(); app.legacyMetadata = .init()
        canvas.editingUndoManager.removeAllActions(); app.currentURL = nil
        app.adoptRasterViewport()
        app.nameField.stringValue = name
        app.dirty = true
        app.replaceDragPresentation()
        window.makeKeyAndOrderFront(nil)
        app.updateStatus()
        pump(0.3)
    }

    func addAllAnnotationKinds(scale: CGFloat) -> [String: SketchElement] {
        func element(_ kind: SketchElement.Kind, _ color: NSColor, width: CGFloat = 6, _ configure: (inout SketchElement) -> Void) -> SketchElement {
            var value = SketchElement(kind: kind); value.color = SketchColor(color); value.strokeWidth = width; configure(&value); return value
        }
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale) }
        var named: [String: SketchElement] = [:]
        named["arrow"] = element(.arrow, .systemRed) { $0.points = [p(110, 690), p(330, 590)] }
        named["line"] = element(.line, .systemBlue) { $0.points = [p(380, 700), p(620, 650)] }
        named["rectangle"] = element(.rectangle, .systemGreen) { $0.rect = r(90, 90, 300, 170) }
        named["rectangle-filled"] = element(.rectangle, .systemOrange) { $0.rect = r(430, 90, 190, 110); $0.filled = true }
        named["ellipse"] = element(.ellipse, .systemPink) { $0.rect = r(660, 80, 260, 150) }
        named["brush"] = element(.brush, .black) {
            $0.points = stride(from: CGFloat(700), through: 1060, by: 12).map { x in p(x, 420 + 36 * sin(x / 28)) }
        }
        named["highlighter"] = element(.brush, NSColor(deviceRed: 1, green: 1, blue: 0, alpha: 0.35), width: 26) { $0.points = [p(110, 322), p(560, 322)] }
        named["text"] = element(.text, .systemRed, width: 6) {
            $0.text = "Ship it today!"; $0.fontName = "Helvetica-Bold"; $0.fontSize = 44; $0.outlined = true; $0.shadowed = true
            $0.rect = r(110, 360, 520, 70)
        }
        named["text-plain"] = element(.text, .black, width: 6) {
            $0.text = "No outline, no shadow"; $0.fontName = "Helvetica"; $0.fontSize = 28; $0.outlined = false; $0.shadowed = false
            $0.rect = r(110, 450, 460, 50)
        }
        named["path"] = element(.path, .systemPurple, width: 5) {
            let c = p(1040, 640), outer: CGFloat = 70 * scale, inner: CGFloat = 30 * scale
            var commands: [SVGPathCommand] = []
            for index in 0..<10 {
                let angle = CGFloat(index) * .pi / 5 - .pi / 2, radius = index % 2 == 0 ? outer : inner
                let point = CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
                commands.append(index == 0 ? .move(to: point) : .line(to: point))
            }
            commands.append(.close); $0.pathCommands = commands
        }
        let tile = NSImage(size: NSSize(width: 120, height: 80), flipped: false) { rect in
            NSColor.systemTeal.setFill(); rect.fill(); NSColor.white.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 30, dy: 14)).fill(); return true
        }
        if let data = SketchRenderer.png(image: tile) {
            named["raster"] = element(.raster, .black, width: 1) { $0.rect = r(700, 520, 120, 80); $0.imagePNG = data }
        }
        let order = ["rectangle", "rectangle-filled", "ellipse", "highlighter", "brush", "path", "raster", "line", "arrow", "text-plain", "text"]
        canvas.document.elements.append(contentsOf: order.compactMap { named[$0] })
        // Fill tool: a closed outline, then the real flood fill into it.
        var closed = element(.rectangle, .systemIndigo) { $0.rect = r(860, 520, 150, 90) }
        closed.id = UUID()
        canvas.document.elements.append(closed)
        named["fill-target"] = closed
        canvas.strokeColor = .systemCyan
        canvas.floodFill(at: p(930, 565))
        canvas.strokeColor = .systemRed
        canvas.needsDisplay = true
        return named
    }

    // MARK: orchestration

    func execute() {
        let before = NSApp.effectiveAppearance.name.rawValue
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pump(1.0)
        guard app.modernChrome != nil else {
            gap("ALL", "Whole audit", "Modern chrome is absent in this process; nothing audited")
            finish(); return
        }
        if wants("ENV") { writeEnvironment(preOverrideAppearance: before) }
        // Any modal nobody asked for (an unexpected error alert) is recorded, then aborted so the run never wedges.
        var unexpected = 0
        let modalGuard = Timer(timeInterval: 2.5, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                guard let modal = NSApp.modalWindow else { return }
                unexpected += 1
                var texts: [String] = []
                func collect(_ view: NSView) { if let field = view as? NSTextField, !field.stringValue.isEmpty { texts.append(field.stringValue) }; view.subviews.forEach(collect) }
                if let content = modal.contentView { collect(content) }
                shoot("ZZ", "unexpected-modal-\(unexpected)", surface: "unexpected modal alert", state: "a modal appeared that no surface expected", windows: [modal],
                      refs: ["App.swift|func error(_ error: Error)"], settle: 0, extra: ["texts": texts])
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(modalGuard, forMode: .common)

        if wanted.contains("LAYOUT") { layoutBudget() }
        if wanted.contains("PROTO") { if #available(macOS 26, *) { proto() } }
        if wanted.contains("S27") { s27() }
        let fresh = !wanted.contains("S27")
        if fresh {
            step("S01", "editor empty") { s01() }
            step("S11", "window sizes") { s11() }
            step("S02", "editor populated") { s02() }
            step("S03", "top bar chrome") { s03() }
            step("S04", "tool states") { s04() }
            step("S05", "selection + text editing") { s05() }
            step("S06", "color / size / font") { s06() }
            step("S07", "canvas viewport") { s07() }
            step("S08", "crop + resize") { s08() }
            step("S09", "footer") { s09() }
            step("S10", "export save panel") { s10() }
            step("S12", "frame mode") { s12() }
            step("S16", "permission alert") { s16() }
            step("S17", "preferences general") { s17() }
            step("S18", "preferences hotkeys") { s18() }
            step("S19", "destinations") { s19() }
            step("S20", "history") { s20() }
            step("S21", "publish states") { s21() }
            step("S22", "photo browser") { s22() }
            step("S23", "menus") { s23() }
            step("S24", "status item") { s24() }
            step("S25", "about") { s25() }
            step("S26", "alerts") { s26() }
            step("S28", "keyboard focus") { s28() }
            step("S29", "extra surfaces") { s29() }
            step("S13", "capture picker") { s13() }
            step("S14", "countdown") { s14() }
            step("S15", "capture flash") { s15() }
        }
        if wanted.contains("S11F") { s11Fullscreen() }
        finish()
    }

    func finish() {
        let name = "gaps-\(appearance)-\(wanted.sorted().joined(separator: "_"))-\(getpid()).json"
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("gapsraw"), withIntermediateDirectories: true)
        write(gaps, to: "gapsraw/\(name)")
    }

    // MARK: surfaces

    func s27() {
        // The app opened its own bundled welcome document at launch (no FirstLaunchDone marker in the isolated support folder).
        shoot("S27", "first-launch-welcome", surface: "first launch / welcome document", state: "empty support dir: bundled welcome document",
              refs: ["App.swift|firstLaunchDocumentURL", "App.swift|openURL(welcome)"], settle: 1.0)
    }

    func s01() {
        shoot("S01", "editor-empty", surface: "editor, empty", state: "fresh blank canvas, default window",
              refs: ["App.swift|func buildWindow()", "App+ModernChrome.swift|func buildModernWindowContent()", "ModernEditorChrome.swift|private func build(actions"])
    }

    func s11() {
        let defaultFrame = window.frame
        let screen = window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        func restore() { window.setFrame(defaultFrame, display: true); pump(0.3) }
        window.setContentSize(window.contentMinSize)
        shoot("S11", "size-contentmin", surface: "window sizes", state: "contentMinSize \(Int(window.contentMinSize.width))x\(Int(window.contentMinSize.height))",
              refs: ["App.swift|window.minSize = NSSize", "App+ModernChrome.swift|window.minSize.width = max", "ModernEditorChrome.swift|static let minimumWindowWidth"])
        restore()
        var wide = defaultFrame; wide.size.width = min(screen.width - 40, 1900); wide.size.height = 640
        window.setFrame(wide, display: true)
        shoot("S11", "size-wide", surface: "window sizes", state: "wide \(Int(wide.width))x\(Int(wide.height))", refs: ["ModernEditorChrome.swift|private func build(actions"])
        restore()
        var tall = defaultFrame; tall.size.height = min(screen.height - 40, 1200); tall.size.width = 1000
        window.setFrame(tall, display: true)
        shoot("S11", "size-tall", surface: "window sizes", state: "tall \(Int(tall.width))x\(Int(tall.height))", refs: ["ModernEditorChrome.swift|private func build(actions"])
        restore()
        window.setFrame(screen, display: true)
        shoot("S11", "size-maximized", surface: "window sizes", state: "maximized to visibleFrame \(Int(screen.width))x\(Int(screen.height))", refs: ["ModernEditorChrome.swift|private func build(actions"])
        restore()
        shoot("S11", "size-default", surface: "window sizes", state: "default 1024x740", refs: ["App.swift|func buildWindow()"])
        for width in [980, 1024, 1280, 1440] {
            var f = defaultFrame; f.size.width = CGFloat(width)
            window.setFrame(f, display: true); pump(0.4)
            shoot("S11", "width-\(width)", surface: "window sizes", state: "window width \(width) pt, default height", refs: ["ModernEditorChrome.swift|static let minimumWindowWidth"])
        }
        restore()
    }

    func s11Fullscreen() {
        window.makeKeyAndOrderFront(nil)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.toggleFullScreen(nil)
        pump(3.5)
        let state = window.styleMask.contains(.fullScreen) ? "true full screen (styleMask.fullScreen)" : "toggleFullScreen requested but styleMask.fullScreen not set"
        shoot("S11", "size-fullscreen", surface: "window sizes", state: state, refs: ["ModernEditorChrome.swift|private func build(actions"], settle: 0.5)
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil); pump(3.0) }
    }

    func s02() {
        loadSynthetic(size: CGSize(width: 1200, height: 800), name: "Quarterly mockup")
        _ = addAllAnnotationKinds(scale: 1)
        shoot("S02", "populated", surface: "editor, populated", state: "synthetic 1200x800 background + arrow, line, rectangle (open+filled), ellipse, brush, highlighter, fill, text (outline+shadow, plain), SVG path, raster",
              refs: ["Canvas.swift|func floodFill", "DocumentModel.swift|enum Kind: String", "BezelDrawingControls.swift|Preset(tag: 109"])
    }

    func s03() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Quarterly mockup")
        shoot("S03", "topbar", surface: "title / top-bar chrome", state: "logo-less glass header: Hide, Toolbox, Photos | ten tools + Resize | Save, History; title shows document name",
              crop: headerCrop(), refs: ["ModernEditorChrome.swift|// Header: [Hide][Toolbox][Photos]", "App+ModernChrome.swift|func showDocumentName"])
        shoot("S03", "rail", surface: "right rail", state: "Snap, Color, Font, Size slider, Undo, Wipe",
              crop: region(of: find("GlassDrawingGroup")).map { CGRect(x: window.frame.width - 130, y: $0.minY - 90, width: 130, height: 520) },
              refs: ["ModernEditorChrome.swift|// Right rail: Snap / Cancel"])
    }

    func s04() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Tool states")
        for tool in SketchTool.allCases {
            app.setTool(tool)
            shoot("S04", "tool-\(tool.rawValue)", surface: "tool states", state: "\(tool.rawValue) tool selected", crop: headerCrop(),
                  refs: ["App.swift|func updateToolButtons", "GlassChrome.swift|private func resolvedTint"], settle: 0.3)
        }
        app.setTool(.brush)
        guard #available(macOS 26, *), let chrome = app.modernChrome as? ModernEditorChrome else { return }
        if let surface = chrome.surface(for: chrome.toolButtons["rectangle"]!) {
            surface.setHovered(true)
            shoot("S04", "tool-hover", surface: "tool states", state: "Rectangle tool hovered (GlassSurfaceView.setHovered), Brush selected", crop: headerCrop(),
                  refs: ["GlassChrome.swift|func setHovered"], settle: 0.4)
            surface.setHovered(false)
            surface.isPressed = true
            shoot("S04", "tool-pressed", surface: "tool states", state: "Rectangle tool pressed (GlassSurfaceView.isPressed), Brush selected", crop: headerCrop(),
                  refs: ["GlassChrome.swift|var isPressed"], settle: 0.4)
            surface.isPressed = false
        }
        chrome.resizeButton.isEnabled = false
        chrome.undoButton.isEnabled = false
        shoot("S04", "controls-disabled", surface: "tool states", state: "Resize + Undo disabled (isEnabled=false as Frame/Actual mode does)", refs: ["AppViewport.swift|resizeButton?.isEnabled", "GlassChrome.swift|isDisabled"], settle: 0.4)
        chrome.resizeButton.isEnabled = true; chrome.undoButton.isEnabled = true
        if let surface = chrome.surface(for: chrome.snapButton) {
            surface.setHovered(true)
            shoot("S04", "snap-hover", surface: "tool states", state: "Snap (primary, accent) hovered", crop: CGRect(x: window.frame.width - 140, y: 40, width: 140, height: 180),
                  refs: ["GlassChrome.swift|enum Prominence"], settle: 0.4)
            surface.setHovered(false)
        }
    }

    func s05() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Selection")
        let named = addAllAnnotationKinds(scale: 1)
        app.setTool(.select)
        if let rect = named["rectangle"] { canvas.selection = [rect.id] }
        shoot("S05", "selection-rect", surface: "selection handles", state: "rectangle selected with resize handles", refs: ["Canvas.swift|private func drawSelectionChrome"])
        if let ellipse = named["ellipse"], let arrow = named["arrow"] { canvas.selection = [ellipse.id, arrow.id] }
        shoot("S05", "selection-multi", surface: "selection handles", state: "ellipse + arrow selected together", refs: ["Canvas.swift|private func drawSelectionChrome"])
        canvas.selection = []
        app.setTool(.text)
        if let down = mouse(.leftMouseDown, docPoint: CGPoint(x: 640, y: 690)), let up = mouse(.leftMouseUp, docPoint: CGPoint(x: 640, y: 690)) {
            canvas.mouseDown(with: down); canvas.mouseUp(with: up)
        }
        pump(0.4)
        if let editor = window.firstResponder as? NSTextView {
            editor.insertText("Edit in progress", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        shoot("S05", "text-editing", surface: "text editing", state: "text tool field editor active with typed text and grip",
              refs: ["Canvas.swift|private func beginTextEditing", "Canvas.swift|case .text:"], extra: ["fieldEditor": window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"])
        canvas.commitPendingTextEditing()
    }

    func s06() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Color and size")
        app.presentDrawingColors(hover: false)
        pump(0.6)
        let popoverWindow = app.colorPopover?.contentViewController?.view.window
        shoot("S06", "color-palette", surface: "color picker", state: "preset palette popover open (original ten presets + Custom color…)",
              windows: popoverWindow.map { [window, $0] } ?? [window], refs: ["App.swift|func presentDrawingColors"])
        if let popoverWindow {
            shoot("S06", "color-palette-popover", surface: "color picker", state: "preset palette popover window alone", windows: [popoverWindow], refs: ["App.swift|func presentDrawingColors"], settle: 0.2)
        }
        app.closeDrawingColors(); pump(0.3)
        if let well = firstView(of: NSButton.self, label: "Drawing colors") { _ = well }
        app.chooseCustomColor(app.paletteButton)
        pump(0.8)
        if NSColorPanel.shared.isVisible {
            shoot("S06", "color-panel", surface: "color picker", state: "system NSColorPanel opened by Custom color…", windows: [NSColorPanel.shared], refs: ["App.swift|func chooseCustomColor"])
            NSColorPanel.shared.orderOut(nil)
        } else { gap("S06", "Custom color panel", "NSColorPanel did not become visible") }
        for (name, value) in [("min", 1.5), ("mid", 6.75), ("max", 12.0)] {
            app.widthControl.doubleValue = value
            app.changeWidth(app.widthControl)
            shoot("S06", "size-\(name)", surface: "size slider", state: "size slider at \(value) (\(name))",
                  crop: CGRect(x: window.frame.width - 130, y: 60, width: 130, height: window.frame.height - 130), refs: ["BezelDrawingControls.swift|final class BezelSizeSlider"], settle: 0.3)
        }
        canvas.fontName = "Helvetica-Bold"
        app.chooseFont()
        pump(3.5)
        if let panel = app.fontPanel, panel.isVisible {
            shoot("S06", "fonts-panel", surface: "Fonts panel / text style form", state: "NSFontPanel with Outline / Shadow / Default accessory form",
                  windows: [panel], refs: ["App.swift|@objc func chooseFont()", "TextStyleForm.swift|final class TextStyleForm"], settle: 0.3)
        } else { gap("S06", "Fonts panel", "NSFontPanel did not become visible") }
        app.closeFontPanel()
    }

    func s07() {
        loadSynthetic(size: CGSize(width: 360, height: 240), name: "Small image")
        shoot("S07", "small-centred", surface: "canvas viewport", state: "360x240 image centred in a large viewport (shot first, before any Actual Size state) (CenteringClipView)", refs: ["ModernEditorChrome.swift|final class CenteringClipView"])
        loadSynthetic(size: CGSize(width: 2400, height: 1500), name: "Large capture")
        _ = addAllAnnotationKinds(scale: 2)
        shoot("S07", "large-fit", surface: "canvas viewport", state: "2400x1500 image fitted into the window", refs: ["AppViewport.swift|func adoptRasterViewport"])
        for title in ["200%", "50%", "25%"] {
            app.zoomControl.selectItem(withTitle: title)
            app.changeZoom(app.zoomControl)
            shoot("S07", "zoom-\(title.replacingOccurrences(of: "%", with: ""))", surface: "canvas viewport", state: "zoom \(title)", refs: ["App.swift|@objc func changeZoom"])
        }
        app.zoomControl.selectItem(withTitle: "100%"); app.changeZoom(app.zoomControl)
        if app.canToggleActualSize {
            app.toggleActualSize()
            pump(0.8)
            shoot("S07", "actual-size", surface: "canvas viewport", state: "Actual Size on: navigator overview panel beside the window",
                  windows: [window] + (app.navigatorWindow.map { [$0] } ?? []), refs: ["AppViewport.swift|@objc func toggleActualSize", "AppViewport.swift|func showActualNavigator"])
            app.leaveActualSize()
        } else { gap("S07", "Actual Size toggle", "canToggleActualSize was false for the synthetic image in this window") }
    }

    func s08() {
        loadSynthetic(size: CGSize(width: 1200, height: 800), name: "Crop")
        app.setTool(.crop)
        canvas.cropRect = CGRect(x: 220, y: 150, width: 640, height: 420)
        window.makeFirstResponder(canvas)
        shoot("S08", "crop-mode", surface: "crop mode", state: "crop tool with a 640x420 crop rectangle", refs: ["Canvas.swift|case .crop:"])
        canvas.cropRect = nil
        app.setTool(.arrow)
        let store = ResizePresetStore()
        try? store.add(ResizePreset(name: "Blog hero", width: 1600, height: 900, mode: .scale))
        try? store.add(ResizePreset(name: "Avatar", width: 256, height: 256, mode: .crop))
        app.resize()
        captureSheet("S08", "resize-panel", surface: "Resize panel", state: "Resize sheet with built-in + two synthetic presets",
                     refs: ["App.swift|@objc func resize()", "ResizePanel.swift|func show(attachedTo"], dismiss: { [self] in
                        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
                        app.activeResizeSession?.cancel()
                     })
    }

    func s09() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Footer states")
        app.updateDragPreview()
        shoot("S09", "footer", surface: "footer", state: "zoom, status, format, drag well, upload", crop: footerCrop(), refs: ["ModernEditorChrome.swift|// One footer row"])
        app.status.stringValue = "Frame: position the window, then Snap · this status line is deliberately very long to test truncation at the footer edge"
        shoot("S09", "footer-long-status", surface: "footer", state: "very long status text", crop: footerCrop(), refs: ["ModernEditorChrome.swift|statusRow"])
        app.updateStatus()
        if let toggle = firstView(of: NSSegmentedControl.self, label: "Image format") {
            for (index, name) in [(0, "PNG"), (1, "JPG")] {
                toggle.selectedSegment = index
                app.changeDragOptions(toggle)
                app.updateDragPreview()
                shoot("S09", "format-toggle-\(name.lowercased())", surface: "footer", state: "PNG | JPG segmented toggle with \(name) selected", crop: footerCrop(),
                      refs: ["App+ModernChrome.swift|dragFormatToggle.segmentStyle", "ImageExport.swift|enum FormatToggle"], settle: 0.5)
            }
            toggle.selectedSegment = 0; app.changeDragOptions(toggle)
        }
        guard let format = firstView(of: NSPopUpButton.self, label: "Drag Me format") else {
            if firstView(of: NSSegmentedControl.self, label: "Image format") == nil { gap("S09", "format control", "neither the format popup nor the PNG|JPG toggle was found") }
            return
        }
        captureTrackedMenu("S09", "format-popup-open", surface: "footer", state: "format popup open (PNG selected)", refs: ["ModernEditorChrome.swift|let formatHolder", "App+ModernChrome.swift|dragFormatControl.addItems"],
                           dismiss: { format.menu?.cancelTracking() }, trigger: { format.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: format.bounds.height), in: format) })
        pump(0.4)
        if let share = app.webpostButton, let menu = share.menu {
            captureTrackedMenu("S09", "upload-menu-open", surface: "footer", state: "Upload (Webpost) destination menu open, no destination configured",
                               refs: ["App.swift|func uploadDestinationMenuItems", "App.swift|func configureWebpostButton"],
                               dismiss: { menu.cancelTracking() }, trigger: { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: share.bounds.height + 4), in: share) })
        }
    }

    func s10() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Export me")
        captureModal("S10", "export-panel", surface: "export save panel", state: "NSSavePanel with ExportAccessory (aborted, nothing written)",
                     refs: ["App.swift|@objc func exportFile()", "ExportAccessory.swift|final class ExportAccessory"], delay: 1.6) { app.exportFile() }
        // The save panel is an out-of-process view; also render the accessory alone as a fallback record.
        let accessory = ExportAccessory(format: "jpeg", originalSize: false, jpegQuality: 0.7)
        let view = accessory.view
        view.frame = NSRect(origin: .zero, size: view.fittingSize.width > 10 ? view.fittingSize : NSSize(width: 460, height: 120))
        let host = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        host.title = "ExportAccessory (rendered alone)"; host.contentView = view
        host.orderFront(nil); pump(0.4)
        shoot("S10", "export-accessory-alone", surface: "export save panel", state: "ExportAccessory view rendered in its own window (JPEG selected)", windows: [host],
              refs: ["ExportAccessory.swift|final class ExportAccessory"])
        host.orderOut(nil)
    }

    func s12() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Frame")
        app.enterFrame(keepingAnnotations: false, manualFlags: [])
        pump(0.9)
        shoot("S12", "frame-mode", surface: "Frame mode", state: "Frame mode: clear canvas hole, Snap Frame + Cancel, window alpha 0.8", refs: ["App.swift|func enterFrame", "ModernEditorChrome.swift|private func applyFrameMode"])
        app.leaveFrame()
        pump(0.3)
        _ = addAllAnnotationKinds(scale: 1)
        app.enterFrame(keepingAnnotations: true, manualFlags: [])
        pump(0.9)
        shoot("S12", "frame-resnap", surface: "Frame mode", state: "Re-snap (keep pen) Frame mode over existing annotations", refs: ["App.swift|@objc func resnap()"])
        app.leaveFrame()
        for width in [980, 1024] {
            loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Frame")
            var f = window.frame; f.size.width = CGFloat(width); window.setFrame(f, display: true); pump(0.3)
            app.enterFrame(keepingAnnotations: false, manualFlags: [])
            pump(0.9)
            shoot("S12", "frame-w\(width)", surface: "Frame mode", state: "Frame mode at window width \(width) pt", refs: ["App.swift|func enterFrame", "ModernEditorChrome.swift|private func applyFrameMode"])
            app.leaveFrame(); pump(0.3)
            window.setFrame(CGRect(x: window.frame.minX, y: window.frame.minY, width: 1024, height: window.frame.height), display: true)
        }
    }

    func s16() {
        let message = "Screen Recording access is not granted. Enable this app in System Settings > Privacy & Security > Screen Recording, then reopen it if macOS requests that."
        let error = NSError(domain: "SkitchRedux.Capture", code: 6, userInfo: [NSLocalizedDescriptionKey: message])
        captureModal("S16", "permission-alert", surface: "Screen Recording permission alert", state: "the alert Capture.swift raises when Screen Recording is missing (built in-process; TCC never asked)",
                     refs: ["Capture.swift|Screen Recording access is not granted", "App.swift|func error(_ error: Error)"]) { app.error(error) }
    }

    func s17() {
        app.showPreferences()
        pump(0.8)
        if let prefs = app.preferencesWindow {
            shoot("S17", "preferences-general", surface: "Preferences: General", state: "General preferences window (single page)", windows: [prefs],
                  refs: ["App.swift|@objc func showPreferences()", "GeneralPreferencesForm.swift|final class GeneralPreferencesForm"])
            if let form = app.preferencesForm {
                form.synchronize(GeneralPreferencesState(drawingPrecision: .loose, arrowHead: 1, includeSkitch: true, statusMenu: 1, showToolTips: true, showKeyboardTips: true))
                shoot("S17", "preferences-alt-values", surface: "Preferences: General", state: "alternate values selected (Loose, Start, Menu bar, both tip overlays on)", windows: [prefs],
                      refs: ["GeneralPreferencesForm.swift|func synchronize"])
            }
        } else { gap("S17", "Preferences", "preferencesWindow was nil") }
        app.closePreferences()
    }

    func s18() {
        app.shortcutSettings()
        captureSheet("S18", "hotkeys-sheet", surface: "Preferences: Hotkeys", state: "Capture Shortcuts sheet (all actions None)",
                     refs: ["GlobalHotkeys.swift|func present(attachedTo", "App.swift|@objc func shortcutSettings()"], dismiss: { [self] in
                        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel); sheet.orderOut(nil) }
                     })
    }

    func syntheticDestinations() {
        var s3 = PublishingSettings()
        s3.transport = .s3; s3.publicBaseURL = "https://cdn.example.com/pics"; s3.username = "AKIAEXAMPLEEXAMPLE0"
        var options = S3Options(); options.bucket = "example-bucket"; options.region = "us-east-1"; options.credentialsProfile = ""
        s3.s3 = options
        var sftp = PublishingSettings()
        sftp.transport = .sftp; sftp.endpoint = "sftp://example.com/var/www"; sftp.sshAlias = ""; sftp.sftpRemoteRoot = "/var/www/img"; sftp.publicBaseURL = "https://example.com/img"
        var dav = PublishingSettings()
        dav.transport = .webDAV; dav.endpoint = "https://dav.example.com/files"; dav.username = "demo"; dav.publicBaseURL = "https://dav.example.com/files"
        let store = AppDelegate.publishingStore
        for (name, settings) in [("Example S3", s3), ("Example SFTP", sftp), ("Example WebDAV", dav)] {
            try? store.save(PublishingDestination(name: name, settings: settings), password: "example-secret-not-real")
        }
    }

    func s19() {
        app.openDestinationSettings()
        pump(1.2)
        captureSheet("S19", "destinations-empty", surface: "Destinations / Publishing", state: "Upload Destinations sheet, no destination saved",
                     refs: ["Publishing.swift|public func showSettings(relativeTo", "PublishingDestinationsView.swift|private func buildList()"], wait: 0.3, dismiss: { [self] in app.publishing.cancelSettings() })
        pump(0.5)
        syntheticDestinations()
        do {
            let (panel, view) = try app.publishing.buildSettings()
            window.beginSheet(panel)
            pump(1.0)
            shootSheet("S19", "destinations-list", surface: "Destinations / Publishing", state: "three synthetic destinations (Example S3 default, SFTP, WebDAV)", refs: ["PublishingDestinationsView.swift|private func buildList()"], host: window, sheet: panel)
            view.reload(try AppDelegate.publishingStore.load(), selecting: try AppDelegate.publishingStore.load().defaultID)
            view.editTapped()
            pump(0.5)
            shootSheet("S19", "destinations-edit-form", surface: "Destinations / Publishing", state: "edit form for the selected destination", refs: ["PublishingDestinationsView.swift|private func showForm(for"], host: window, sheet: panel)
            for control in [view.nameField, view.endpointField, view.bucketField, view.regionField] where control.superview != nil && !control.isHidden && control.window === panel {
                panel.makeFirstResponder(control); break
            }
            shootSheet("S19", "destinations-form-focus", surface: "Preferences text field focus", state: "first visible text field focused in the destination edit form", refs: ["PublishingDestinationsView.swift|private func buildForm()"], host: window, sheet: panel)
            app.publishing.cancelSettings()
            pump(0.5)
        } catch { gap("S19", "Destinations list/edit form", "buildSettings threw: \(error.localizedDescription)") }
    }

    func s20() {
        app.showHistory()
        pump(1.0)
        if let history = app.historyWindow {
            shoot("S20", "history-empty", surface: "History browser", state: "History window with no entries", windows: [history], refs: ["App.swift|@objc func showHistory()", "HistoryBrowser.swift|private func buildUI()"])
        } else { gap("S20", "History (empty)", "historyWindow nil") }
        let calendar = Calendar.current
        let names = ["Quarterly mockup", "Bug report screenshot", "Onboarding flow", "Pricing page", "Team photo wall", "Error dialog"]
        let actions: [HistoryStore.Action] = [.archived, .exported, .shared, .archived, .shared, .exported]
        for (index, name) in names.enumerated() {
            let size = CGSize(width: 900 + CGFloat(index) * 40, height: 600)
            canvas.newBlank(size: size); canvas.setBackground(AuditRun.syntheticImage(size: size))
            _ = addAllAnnotationKinds(scale: 0.75)
            canvas.document.elements.removeLast(max(0, canvas.document.elements.count - 4 - index))
            if let snapshot = try? app.historySnapshot(), let store = try? app.archiveStore() {
                let date = calendar.date(byAdding: .day, value: -index * 3, to: Date()) ?? Date()
                _ = try? store.archive(snapshot, name: name, action: actions[index], destination: actions[index] == .shared ? "Example S3" : nil,
                                       remoteURL: actions[index] == .shared ? URL(string: "https://cdn.example.com/pics/\(index).png") : nil, date: date)
            }
        }
        app.refreshHistory()
        pump(1.2)
        app.historyBrowser?.select(ids: [])
        if let history = app.historyWindow {
            shoot("S20", "history-populated", surface: "History browser", state: "six synthetic entries across dates and actions (Saved/Exported/Shared)", windows: [history], refs: ["HistoryBrowser.swift|func update(items", "HistoryBrowser.swift|private func buildUI()"])
            if let first = app.historyStore?.entries.first?.id {
                app.historyBrowser?.select(ids: [first])
                shoot("S20", "history-selected", surface: "History browser", state: "one entry selected (action buttons enabled)", windows: [history], refs: ["HistoryBrowser.swift|private func updateControls()"])
            }
            history.orderOut(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    final class UploadGate: @unchecked Sendable {
        let release = DispatchSemaphore(value: 0)
        var mode = "success"
    }

    func s21() {
        syntheticDestinations()
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Upload demo")
        let gate = UploadGate()
        app.publishing.clipboardWriter = { _ in }
        app.publishing.uploader = { _, _, plan, _ in
            if gate.mode == "wait" { _ = gate.release.wait(timeout: .now() + 8) }
            if gate.mode == "fail" { throw PublishingFailure("Upload to Example S3 failed: the connection was refused (stub, no network was used).") }
            return plan.publicURL ?? plan.remoteURL
        }
        gate.mode = "wait"
        app.publishImage()
        pump(1.0)
        shoot("S21", "publish-progress", surface: "publish progress", state: "Uploading… status in footer while the stub uploader waits", refs: ["App.swift|@objc func publishImage()", "App.swift|uploadStatus = \"Uploading"], extra: ["status": app.status.stringValue])
        shoot("S21", "publish-progress-footer", surface: "publish progress", state: "footer crop during upload", crop: footerCrop(), refs: ["App.swift|func updateStatus()"], settle: 0.1)
        if let share = app.webpostButton, let menu = share.menu {
            captureTrackedMenu("S21", "upload-menu-busy", surface: "publish progress", state: "destination menu while an upload runs (Cancel Upload offered)", refs: ["App.swift|Cancel Upload"],
                               dismiss: { menu.cancelTracking() }, trigger: { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: share.bounds.height + 4), in: share) })
        }
        gate.release.signal()
        pump(2.5)
        shoot("S21", "publish-success", surface: "publish success", state: "status after a stubbed successful upload", refs: ["App.swift|func receivePublishing"], extra: ["status": app.status.stringValue])
        shoot("S21", "publish-success-footer", surface: "publish success", state: "footer crop after success", crop: footerCrop(), refs: ["App.swift|func receivePublishing"], settle: 0.1)
        pump(0.5)
        gate.mode = "fail"
        let failureTimer = Timer(timeInterval: 2.0, repeats: false) { [self] _ in
            MainActor.assumeIsolated {
                if let modal = NSApp.modalWindow {
                    shoot("S21", "publish-error", surface: "publish error", state: "error alert after a stubbed failed upload", windows: [modal], refs: ["App.swift|func receivePublishing", "App.swift|func error(_ error: Error)"], settle: 0)
                } else { gap("S21", "publish error alert", "no modal alert appeared") }
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(failureTimer, forMode: .common)
        app.publishImage()
        pump(3.5)
        failureTimer.invalidate()
        shoot("S21", "publish-error-footer", surface: "publish error", state: "footer crop after the error alert was dismissed", crop: footerCrop(), refs: ["App.swift|func receivePublishing"], settle: 0.2)
    }

    func s22() {
        gap("S22", "Photo browser", "PhotoBrowserCoordinator reads the user's Photos library and Desktop (Photos TCC prompt, real private pictures); no synthetic content seam exists, so it was deliberately not opened")
    }

    func s23() {
        var menus: [String: Any] = [:]
        if let main = NSApp.mainMenu { menus["mainMenu"] = menuNode(main) }
        if let toolbox = firstView(of: NSPopUpButton.self, label: "Toolbox"), let menu = toolbox.menu { menus["toolboxPopupMenu"] = menuNode(menu) }
        if let menu = app.webpostButton?.menu { menus["uploadDestinationMenu"] = menuNode(menu) }
        if let format = firstView(of: NSPopUpButton.self, label: "Drag Me format"), let menu = format.menu { menus["dragFormatPopupMenu"] = menuNode(menu) }
        menus["zoomPopupMenu"] = app.zoomControl.menu.map { menuNode($0) } as Any
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Menus")
        let named = addAllAnnotationKinds(scale: 1)
        if let text = named["text"], let event = mouse(.rightMouseDown, docPoint: CGPoint(x: text.rect.minX + 20, y: text.rect.minY + 20)), let menu = canvas.menu(for: event) {
            menus["canvasTextContextMenu"] = menuNode(menu)
        }
        menus["canvasContextMenuNote"] = "Canvas.menu(for:) returns a menu only when right-clicking a text annotation; blank canvas and shapes return nil (Canvas.swift:1843)"
        menus["snapAlternate"] = "Snap has no menu: left-click = region/window snap, right-click or Control-click = Fullscreen alternate (OriginalActionButton.alternateAction); Frame mode clears the alternate"
        menus["statusItem"] = ["hasMenu": app.statusItem?.menu != nil, "action": "showHide (toggle editor visibility)", "buttonToolTip": app.statusItem?.button?.toolTip ?? "none",
                               "note": "The status item has no menu; Option-click quits"]
        write(menus, to: "menus" + (ProcessInfo.processInfo.environment["AUDIT_STEM_SUFFIX"] ?? "") + ".json")
        guard let toolbox = firstView(of: NSPopUpButton.self, label: "Toolbox") else { gap("S23", "Toolbox menu open", "toolbox popup not found"); return }
        captureTrackedMenu("S23", "toolbox-menu-open", surface: "menus", state: "Toolbox pull-down open", refs: ["App.swift|func bezelToolbox()"],
                           dismiss: { toolbox.menu?.cancelTracking() }, trigger: { toolbox.performClick(nil) })
        pump(0.4)
        if let text = named["text"], let event = mouse(.rightMouseDown, docPoint: CGPoint(x: text.rect.minX + 20, y: text.rect.minY + 20)), let menu = canvas.menu(for: event) {
            let location = canvas.convert(event.locationInWindow, from: nil)
            captureTrackedMenu("S23", "canvas-text-context-open", surface: "menus", state: "canvas context menu on a text annotation", refs: ["Canvas.swift|override func menu(for event: NSEvent)"],
                               dismiss: { menu.cancelTracking() }, trigger: { menu.popUp(positioning: nil, at: location, in: canvas) })
        }
    }

    /// Renders one view (no window capture) at 2x. Used for the status-bar button, whose host window cannot be imaged by number.
    func shootView(_ id: String, _ slug: String, surface: String, state: String, view: NSView, refs: [String], extra: [String: Any] = [:]) {
        let stem = "\(id)-\(slug)-\(appearance)" + (ProcessInfo.processInfo.environment["AUDIT_STEM_SUFFIX"] ?? "")
        guard view.bounds.width > 1, view.bounds.height > 1, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            gap(id, surface + " / " + state, "the view has no drawable bounds"); return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { gap(id, surface + " / " + state, "PNG encoding failed"); return }
        try? png.write(to: dir.appendingPathComponent(stem + ".png"))
        var meta: [String: Any] = ["id": id, "slug": slug, "surface": surface, "state": state, "appearance": appearance, "file": stem + ".png",
            "pixelSize": [rep.pixelsWide, rep.pixelsHigh], "pointSize": [Double(view.bounds.width), Double(view.bounds.height)],
            "scale": Double(rep.pixelsWide) / Double(view.bounds.width), "method": "NSView.cacheDisplay (view only, not a window capture)", "sourceRefs": refs,
            "sourceSha": ProcessInfo.processInfo.environment["AUDIT_SOURCE_SHA"] ?? "unknown", "appActive": NSApp.isActive]
        for (key, item) in extra { meta[key] = item }
        write(meta, to: "meta/\(stem).json")
    }

    func s24() {
        guard let item = app.statusItem, let button = item.button else {
            gap("S24", "Status-bar item", "no NSStatusItem exists in this process (statusMenu preference or app policy)"); return
        }
        button.highlight(false)
        shootView("S24", "statusitem-normal", surface: "status-bar item", state: "menu-bar icon, normal (the button view only; the real bar is not captured)", view: button, refs: ["App.swift|func installMenuPresence()"], extra: ["toolTip": button.toolTip ?? "", "buttonSize": [Double(button.bounds.width), Double(button.bounds.height)]])
        button.highlight(true)
        shootView("S24", "statusitem-highlighted", surface: "status-bar item", state: "menu-bar icon, highlighted", view: button, refs: ["App.swift|button.alternateImage"])
        button.highlight(false)
    }

    func s25() {
        let known = Set(NSApp.windows.map(\.windowNumber))
        app.about()
        pump(1.0)
        let panels = NSApp.windows.filter { !known.contains($0.windowNumber) && $0.isVisible }
        if let panel = panels.first {
            shoot("S25", "about-panel", surface: "About panel", state: "standard About panel with OpenSkitch credits", windows: [panel], refs: ["App.swift|@objc func about()"])
            panel.orderOut(nil)
        } else { gap("S25", "About panel", "the standard About panel window was not found") }
    }

    func s26() {
        captureModal("S26", "rename", surface: "alerts / sheets", state: "Rename… alert with text field", refs: ["App.swift|@objc func renameDocument()", "App.swift|func prompt("]) { app.renameDocument() }
        app.dirty = true
        captureModal("S26", "close-unsaved", surface: "alerts / sheets", state: "Save your drawing? (Save / Cancel / Discard)", refs: ["App.swift|func allowDiscard("]) { _ = app.allowDiscard() }
        app.dirty = false
        captureModal("S26", "error-generic", surface: "alerts / sheets", state: "generic NSAlert(error:) alert", refs: ["App.swift|func error(_ error: Error)"]) {
            app.error(NSError(domain: "SkitchRedux", code: 5, userInfo: [NSLocalizedDescriptionKey: "This capture is too large or cannot be decoded safely."]))
        }
        if let store = try? app.archiveStore() {
            if store.entries.isEmpty, let snapshot = try? app.historySnapshot() { _ = try? store.archive(snapshot, name: "Alert demo", action: .archived) }
            if let id = store.entries.first?.id {
                captureModal("S26", "history-hide", surface: "alerts / sheets", state: "Hide drawings from History?", refs: ["App.swift|func removeHistory("]) { app.removeHistory([id], deleteFiles: false) }
                captureModal("S26", "history-trash", surface: "alerts / sheets", state: "Move archived drawings to Trash?", refs: ["App.swift|func removeHistory("]) { app.removeHistory([id], deleteFiles: true) }
            }
        }
        syntheticDestinations()
        do {
            let (panel, view) = try app.publishing.buildSettings()
            window.beginSheet(panel); pump(0.8)
            let list = try AppDelegate.publishingStore.load()
            if let name = list.destinations.first?.name, let target = list.destinations.first {
                let prompt = PublishingDestinationsView.removalPrompt(for: target, in: list)
                captureModal("S26", "remove-destination", surface: "alerts / sheets", state: "Remove “\(name)”? confirmation (default destination)", refs: ["PublishingDestinationsView.swift|private static func askToRemove"]) {
                    _ = view.confirmRemoval(prompt.title, prompt.detail)
                }
            }
            app.publishing.cancelSettings(); pump(0.4)
        } catch { gap("S26", "Remove destination alert", "buildSettings threw: \(error.localizedDescription)") }
        gap("S26", "Wipe confirmation", "No Wipe confirmation exists: Wipe/Undo (Canvas.wipe) acts immediately, so there is nothing to capture; recorded as a finding")
    }

    func s28() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Focus")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard #available(macOS 26, *), let chrome = app.modernChrome as? ModernEditorChrome else { return }
        window.makeFirstResponder(chrome.toolButtons["brush"])
        shoot("S28", "focus-topbar-tool", surface: "keyboard focus", state: "Brush tool button is first responder (focus ring)", crop: headerCrop(), refs: ["GlassChrome.swift|override func drawFocusRingMask"])
        window.makeFirstResponder(chrome.hideButton)
        shoot("S28", "focus-topbar-hide", surface: "keyboard focus", state: "Hide button is first responder", crop: headerCrop(), refs: ["GlassChrome.swift|focusRingMaskBounds"], settle: 0.3)
        window.makeFirstResponder(chrome.snapButton)
        shoot("S28", "focus-rail-snap", surface: "keyboard focus", state: "Snap (primary) is first responder", crop: CGRect(x: window.frame.width - 140, y: 40, width: 140, height: 200), refs: ["GlassChrome.swift|focusShape"], settle: 0.3)
        window.makeFirstResponder(app.zoomControl)
        shoot("S28", "focus-footer-zoom", surface: "keyboard focus", state: "Zoom popup is first responder", crop: footerCrop(), refs: ["ModernEditorChrome.swift|controls.zoomControl.isBordered"], settle: 0.3)
        if let format = firstView(of: NSPopUpButton.self, label: "Drag Me format") {
            window.makeFirstResponder(format)
            shoot("S28", "focus-footer-format", surface: "keyboard focus", state: "Format popup is first responder", crop: footerCrop(), refs: ["ModernEditorChrome.swift|let formatHolder"], settle: 0.3)
        }
        window.makeFirstResponder(chrome.shareButton)
        shoot("S28", "focus-footer-upload", surface: "keyboard focus", state: "Upload button is first responder", crop: footerCrop(), refs: ["ModernEditorChrome.swift|shareButton = GlassChromeButton"], settle: 0.3)
        window.makeFirstResponder(canvas)
    }

    func s29() {
        // Help bevel (tool-tip overlay) -- off by default; force it on only inside this process.
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Extras")
        app.helpBevel?.enabled = true
        app.helpBevel?.hover(owner: "audit", message: "Rectangle tool: drag to draw a rectangle. Hold Shift for a square.")
        pump(1.2)
        let known = Set([window.windowNumber])
        let helpers = NSApp.windows.filter { !known.contains($0.windowNumber) && $0.isVisible && String(describing: type(of: $0)).contains("Help") }
        shoot("S29", "help-bevel", surface: "help bevel (tool-tip overlay)", state: "OriginalHelpBevel HUD with a hover hint (feature is off by default)", windows: [window] + helpers, refs: ["OriginalHelpBevel.swift|final class OriginalHelpBevelView"],
              extra: ["helpWindowFound": !helpers.isEmpty])
        app.helpBevel?.clear()
        app.helpBevel?.enabled = false
        // Drag-out thumbnail panel with its hover overlay.
        let id = UUID()
        app.activeDragID = id
        app.iconifyDrag(id)
        pump(2.0)
        if let thumbnail = app.dragThumbnailWindow {
            shoot("S29", "drag-thumbnail", surface: "drag-out thumbnail", state: "Drag Me thumbnail panel after the editor shrinks (Skitch_Cancel_DragMe hover art absent: not hovering)", windows: [thumbnail], refs: ["App.swift|final class DragThumbnailView", "App.swift|func iconifyDrag"])
            if let view = thumbnail.contentView as? DragThumbnailView {
                view.clickToExpand = true
                shoot("S29", "drag-thumbnail-expand", surface: "drag-out thumbnail", state: "clickToExpand overlay (original Skitch_ShowSkitch artwork)", windows: [thumbnail], refs: ["App.swift|let name = hovering ? \"Skitch_ShowSkitch_mouseover\""])
            }
        } else { gap("S29", "Drag thumbnail", "iconifyDrag produced no thumbnail window") }
        app.removeDragThumbnail(); app.activeDragID = nil
        app.showEditorImmediately()
        pump(0.5)
        gap("S29", "Native tooltips / help tags", "AppKit tooltips are drawn by the window server on real mouse hover and cannot be forced or captured without a real pointer")
        gap("S29", "Share with macOS picker", "NSSharingServicePicker runs out of process and lists the user's real services/accounts")
    }

    func s13() {
        UserDefaults.standard.set(true, forKey: OriginalCaptureMagnifierGeometry.defaultsKey)
        guard let screen = window.screen ?? NSScreen.main else { gap("S13", "capture picker", "no screen"); return }
        let centre = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        for (label, image) in [("no-recording-grant", false), ("synthetic-lens", true)] {
            let picker = OriginalCapturePicker(displayFrames: { [screen.frame] }, windowRecords: { [] },
                                               screenImage: { rect in
                                                   guard image else { return nil }
                                                   let cg = AuditRun.syntheticImage(size: CGSize(width: rect.width, height: rect.height)).cgImage(forProposedRect: nil, context: nil, hints: nil)
                                                   return cg.map { OriginalCaptureScreenImage(image: $0, scale: 1) }
                                               },
                                               mouseLocation: { centre })
            picker.begin(windowOnly: false) { _ in }
            pump(0.8)
            guard let panel = picker.panels.first, let selection = panel.contentView as? OriginalCaptureSelectionView else {
                gap("S13", "capture picker", "picker did not create an overlay panel"); picker.cancel(); continue
            }
            let local = NSPoint(x: selection.bounds.midX, y: selection.bounds.midY)
            if let move = NSEvent.mouseEvent(with: .mouseMoved, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                selection.mouseMoved(with: move)
            }
            shoot("S13", "picker-\(label)", surface: "capture picker / crosshair + magnifier", state: "crosshair overlay with magnifier (lens \(image ? "fed synthetic pixels" : "grey, as without a Screen Recording grant")), no drag yet",
                  windows: [panel], refs: ["OriginalCapturePicker.swift|func begin(windowOnly", "OriginalCapturePicker.swift|func mountMagnifierIfEnabled"], settle: 0.4)
            let start = NSPoint(x: local.x - 240, y: local.y - 140), end = NSPoint(x: local.x + 260, y: local.y + 160)
            for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end)] {
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    if type == .leftMouseDown { selection.mouseDown(with: event) } else { selection.mouseDragged(with: event) }
                }
            }
            shoot("S13", "picker-\(label)-dragging", surface: "capture picker / crosshair + magnifier", state: "mid-drag selection rectangle with dimmed surround (lens \(image ? "synthetic" : "grey"))",
                  windows: [panel], refs: ["OriginalCapturePicker.swift|override func draw(_ dirtyRect"], settle: 0.4)
            picker.cancel()
            pump(0.4)
        }
        UserDefaults.standard.removeObject(forKey: OriginalCaptureMagnifierGeometry.defaultsKey)
    }

    func s14() {
        guard let screen = window.screen ?? NSScreen.main else { gap("S14", "countdown", "no screen"); return }
        var tick: (@MainActor @Sendable () -> Void)?
        let countdown = OriginalCaptureCountdown(scheduler: { _, action in tick = action; return { tick = nil } }, screenFrames: { [screen.visibleFrame] })
        let rect = window.frame.insetBy(dx: window.frame.width / 3, dy: window.frame.height / 3)
        countdown.start(rect: rect, parent: nil, delay: OriginalCaptureTiming.originalDelay, cue: {}, completion: {})
        var seen = Set<String>()
        var ticks = 0
        while countdown.isRunning, ticks < 90 {
            tick?(); ticks += 1
            guard let panel = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("Countdown") && $0.isVisible }),
                  let label = panel.contentView?.accessibilityLabel(), panel.alphaValue > 0.9, !seen.contains(label) else { continue }
            seen.insert(label)
            let digit = label.replacingOccurrences(of: "Capture countdown: ", with: "")
            shoot("S14", "countdown-\(digit)", surface: "countdown overlay", state: "countdown digit \(digit) (tick \(ticks))",
                  windows: [panel], refs: ["OriginalCaptureCountdown.swift|func start(rect", "OriginalCaptureCountdown.swift|private func advance"], settle: 0.2)
        }
        countdown.cancel()
        if seen.isEmpty { gap("S14", "countdown overlay", "no countdown panel became visible at full alpha during 90 manual ticks") }
        for panel in NSApp.windows where String(describing: type(of: panel)).contains("Countdown") { panel.orderOut(nil) }
    }

    func s15() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Flash")
        let controller = OriginalCaptureFlashController(timerFactory: { _, _ in { } })
        controller.play(frame: window.frame, deflashDuration: 0.5)
        pump(0.3)
        guard let flash = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("Flash") }) else {
            gap("S15", "capture flash", "flash window not found"); controller.cancel(); return
        }
        flash.alphaValue = 1
        shoot("S15", "flash-full", surface: "capture flash", state: "flash panel at full alpha over the editor frame (pure white fill)", windows: [flash], refs: ["OriginalCaptureFlash.swift|final class OriginalCaptureFlashWindow", "OriginalCaptureFlash.swift|final class OriginalCaptureFlashView"], settle: 0.3)
        flash.alphaValue = 0.55
        shoot("S15", "flash-half", surface: "capture flash", state: "flash at 55% alpha composited over the editor", windows: [window, flash], refs: ["OriginalCaptureFlash.swift|static func alpha(elapsed"], settle: 0.3)
        controller.cancel()
    }
}
