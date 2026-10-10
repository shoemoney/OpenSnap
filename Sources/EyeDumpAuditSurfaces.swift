import AppKit
import CoreGraphics

/// Surface flows for the audit harness. Every flow drives the app's own presentation code with synthetic content;
/// nothing here captures the screen, touches the network, the Keychain or the real stores.
/// A shortcut backend that registers nothing, so a Settings window built by the harness cannot claim a key on the desktop.
@MainActor
final class AuditInertHotkeyBackend: GlobalHotkeyBackend {
    var registeredIDs: Set<UInt32> { [] }
    func installHandler(onEvent: @escaping @MainActor @Sendable (UInt32) -> Void) throws {}
    func systemReservedBindings() throws -> Set<GlobalHotkeyBinding> { [] }
    func register(_ binding: GlobalHotkeyBinding, id: UInt32) throws {}
    func unregister(id: UInt32) throws {}
    func shutdown() throws {}
}

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
        guard let header = find("OpenSnapHeader") else { return nil }
        let r = header.convert(header.bounds, to: nil)
        return CGRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height - r.minY + 6)
    }
    func footerCrop() -> CGRect? {
        guard let footer = find("OpenSnapFooter") else { return nil }
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

    /// Raises an app-owned alert (a sheet, so `trigger` returns at once), captures the window with the sheet on it, then answers Cancel.
    func captureAlertSheet(_ id: String, _ slug: String, surface: String, state: String, refs: [String], trigger: () -> Void) {
        trigger()
        pump(0.9)
        guard let alert = AppAlert.presentedAlerts.last else { gap(id, surface + " / " + state, "no app-owned alert was on screen after the trigger"); return }
        var fonts: [String: Any] = ["title": fontInfo(alert.titleLabel.font) as Any, "message": fontInfo(alert.messageLabel.font) as Any,
                                    "buttons": alert.buttonViews.map { fontInfo($0.font) as Any }]
        if let field = alert.accessoryView as? NSTextField { fonts["field"] = fontInfo(field.font) as Any }
        shoot(id, slug, surface: surface, state: state, windows: [alert.panel, window], refs: refs, settle: 0.1,
              extra: ["alertTitle": alert.title, "alertButtons": alert.buttons.map(\.title), "fonts": fonts, "presentedAs": window.attachedSheet === alert.panel ? "sheet on the document window" : "separate panel"])
        alert.cancel()
        pump(0.3)
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
        shoot(id, slug + "-in-context", surface: surface, state: state + " (parent window + sheet composite)", windows: [sheet, host], refs: refs, settle: 0.1,
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
        app.documentGeneration = UUID()
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
            gap("ALL", "Whole audit", "The editor chrome is absent in this process; nothing audited")
            finish(); return
        }
        if requestedIcons == "fa" && iconMode != "fa" {
            gap("ALL", "Whole audit", "FA unavailable: icon mode fa was requested but no Font Awesome subset fonts are bundled in this app copy, so nothing was captured")
            write(["requested": "fa", "effective": iconMode, "reason": "FA unavailable"], to: "icon-mode-unavailable.json")
            finish(); return
        }
        if requestedIcons == "sf" && iconMode != "sf" {
            gap("ALL", "Whole audit", "icon mode sf was requested but Font Awesome fonts are registered in this app copy, so nothing was captured (the script must remove them from its throwaway copy)")
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
        do {
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
            step("S26D", "remove destination sheet") { s26d() }
            step("S28", "keyboard focus") { s28() }
            step("S29", "extra surfaces") { s29() }
            step("S30", "size popover") { s30() }
            step("S31", "colour popover") { s31() }
            step("S32", "frame mode, large canvas") { s32() }
            step("S33", "large shot at 980") { s33() }
            step("S34", "small canvas centred") { s34() }
            step("S35", "large canvas fills viewport") { s35() }
            step("S36", "selection and text editing at 980/1280") { s36() }
            step("S37", "PNG and JPG at 980") { s37() }
            step("S38", "app tooltips") { s38() }
            step("S39", "titled window and alert sheets") { s39() }
            step("S40", "component states") { s40() }
            step("S13", "capture picker") { s13() }
            step("S14", "countdown") { s14() }
            step("S15", "capture flash") { s15() }
        }
        // The empty matrix goes first: it needs the blank canvas this process started with, and the populated one replaces it.
        if wanted.contains("S11E") { s11SizeMatrix(populated: false) }
        if wanted.contains("S11M") { s11SizeMatrix(populated: true) }
        if wanted.contains("S11F") { s11Fullscreen(populated: false) }
        if wanted.contains("S11FP") { s11Fullscreen(populated: true) }
        finish()
    }

    func finish() {
        let name = "gaps-\(appearance)-\(iconMode)-\(wanted.sorted().joined(separator: "_"))-\(getpid()).json"
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("gapsraw"), withIntermediateDirectories: true)
        write(gaps, to: "gapsraw/\(name)")
    }

    // MARK: surfaces

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

    /// The rail-removal acceptance matrix: the editor at each named window size, populated or empty.
    /// Sizes come from --audit-sizes: `WxH`, `Wxmin` (that width at the smallest height the window allows) or `full` (the screen's visible frame).
    static let defaultSizeSpecs = ["980xmin", "1024x740", "1280x800", "1440x900", "full"]

    /// Resolves a size spec to points; nil (and a gap record) when the spec is unusable.
    func windowSize(for spec: String, surface: String) -> CGSize? {
        if spec == "full" { return (window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)).size }
        let parts = spec.split(separator: "x").map(String.init)
        guard parts.count == 2, let width = Double(parts[0]), width > 0 else { gap(surface, "window size matrix", "unusable size spec \(spec)"); return nil }
        let height = parts[1] == "min" ? Double(window.minSize.height) : (Double(parts[1]) ?? 0)
        guard height > 0 else { gap(surface, "window size matrix", "unusable size spec \(spec)"); return nil }
        return CGSize(width: width, height: height)
    }

    /// Puts the window at the top-left of the visible screen at `size` and reports whether AppKit clamped it.
    @discardableResult
    func placeWindow(_ size: CGSize) -> (landed: CGSize, clamped: Bool) {
        let screen = window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.setFrame(CGRect(origin: CGPoint(x: screen.minX, y: screen.maxY - size.height), size: size), display: true)
        pump(0.5)
        let landed = window.frame.size
        return (landed, abs(landed.width - size.width) > 1 || abs(landed.height - size.height) > 1)
    }

    func s11SizeMatrix(populated: Bool) {
        let id = populated ? "S11M" : "S11E"
        let specs = sizes.isEmpty ? AuditRun.defaultSizeSpecs : sizes
        let defaultFrame = window.frame
        // Populated: a 1200x800 shot with every annotation kind. Empty: the fresh blank canvas this process started with.
        if populated {
            loadSynthetic(size: CGSize(width: 1200, height: 800), name: "Size matrix")
            _ = addAllAnnotationKinds(scale: 1)
        }
        for spec in specs {
            guard let size = windowSize(for: spec, surface: id) else { continue }
            let placed = placeWindow(size)
            let slug = (populated ? "size-" : "empty-size-") + spec
            shoot(id, slug, surface: populated ? "window size matrix, populated" : "window size matrix, empty",
                  state: "requested \(spec) (\(Int(size.width))x\(Int(size.height)) pt), window is \(Int(placed.landed.width))x\(Int(placed.landed.height)) pt",
                  refs: ["ModernEditorChrome.swift|private func build(actions"], extra: ["requestedSize": spec, "requestedPoints": [Double(size.width), Double(size.height)], "sizeClamped": placed.clamped])
        }
        window.setFrame(defaultFrame, display: true)
        pump(0.3)
    }

    func s11Fullscreen(populated: Bool) {
        let id = populated ? "S11FP" : "S11F"
        // Populated = the blank 800x600 canvas plus every annotation kind. Loading a synthetic shot instead resizes the window to fit it,
        // and the window then keeps that size inside the full-screen space (a 1609x1179 "full screen" window) rather than spanning the display.
        if populated { _ = addAllAnnotationKinds(scale: 0.66) }
        window.makeKeyAndOrderFront(nil)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.toggleFullScreen(nil)
        // The transition runs longer with a big populated canvas: wait until the window really spans its screen before imaging it.
        pump(3.5)
        var waited = 0.0
        while waited < 10, window.screen.map({ abs(window.frame.width - $0.frame.width) > 2 }) ?? false { pump(0.5); waited += 0.5 }
        pump(0.8)
        let state = window.styleMask.contains(.fullScreen) ? "true full screen (styleMask.fullScreen)" : "toggleFullScreen requested but styleMask.fullScreen not set"
        shoot(id, populated ? "size-fullscreen-populated" : "size-fullscreen", surface: populated ? "window sizes, populated" : "window sizes", state: state, refs: ["ModernEditorChrome.swift|private func build(actions"], settle: 0.5)
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
        shoot("S03", "topbar", surface: "top bar", state: "Hide, Toolbox, Photos | Snap | ten tools | Color, Size, Font; title shows document name",
              crop: headerCrop(), refs: ["ModernEditorChrome.swift|// Top bar: [Hide][Toolbox][Photos]", "App+ModernChrome.swift|func showDocumentName"])
        shoot("S03", "bottombar", surface: "bottom bar", state: "Undo, Wipe | Zoom, Resize | status | Save, History | PNG|JPG, Drag, Upload",
              crop: footerCrop(), refs: ["ModernEditorChrome.swift|// Bottom bar: [Undo][Wipe]"])
    }

    func s04() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Tool states")
        for tool in SketchTool.allCases {
            app.setTool(tool)
            shoot("S04", "tool-\(tool.rawValue)", surface: "tool states", state: "\(tool.rawValue) tool selected", crop: headerCrop(),
                  refs: ["App.swift|func updateToolButtons", "StateStyles.swift|static func command"], settle: 0.3)
        }
        app.setTool(.brush)
        guard #available(macOS 26, *), let chrome = app.modernChrome as? ModernEditorChrome else { return }
        if let tool = chrome.toolButtons["rectangle"] {
            tool.setHovered(true)
            shoot("S04", "tool-hover", surface: "tool states", state: "Rectangle tool hovered (CommandButton.setHovered: a 0.08 fill on the group plate), Brush selected", crop: headerCrop(),
                  refs: ["GlassChrome.swift|func setHovered"], settle: 0.4)
            tool.setHovered(false)
            tool.highlight(true)
            shoot("S04", "tool-pressed", surface: "tool states", state: "Rectangle tool pressed (CommandButton.highlight: a 0.16 fill on the group plate), Brush selected", crop: headerCrop(),
                  refs: ["GlassChrome.swift|override func highlight"], settle: 0.4)
            tool.highlight(false)
        }
        chrome.resizeButton.isEnabled = false
        chrome.undoButton.isEnabled = false
        shoot("S04", "controls-disabled", surface: "tool states", state: "Resize + Undo disabled (isEnabled=false as Frame/Actual mode does)", refs: ["AppViewport.swift|resizeButton?.isEnabled", "GlassChrome.swift|disabled: !isEnabled"], settle: 0.4)
        chrome.resizeButton.isEnabled = true; chrome.undoButton.isEnabled = true
        chrome.snapButton.setHovered(true)
        shoot("S04", "snap-hover", surface: "tool states", state: "Snap (primary, accent) hovered", crop: headerCrop(),
              refs: ["GlassChrome.swift|var isPrimary"], settle: 0.4)
        chrome.snapButton.setHovered(false)
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
            shoot("S06", "size-\(name)", surface: "size pill", state: "size pill glyph at \(value) (\(name))",
                  crop: headerCrop(), refs: ["BezelDrawingControls.swift|final class BezelSizeSlider"], settle: 0.3)
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
        if let toggle = firstView(of: SegmentedToggle.self, label: "Image format") {
            for (index, name) in [(0, "PNG"), (1, "JPG")] {
                toggle.selectedSegment = index
                app.changeDragOptions(toggle)
                app.updateDragPreview()
                shoot("S09", "format-toggle-\(name.lowercased())", surface: "footer", state: "PNG | JPG segmented toggle with \(name) selected", crop: footerCrop(),
                      refs: ["GlassChrome.swift|final class SegmentedToggle", "ImageExport.swift|enum FormatToggle"], settle: 0.5)
            }
            toggle.selectedSegment = 0; app.changeDragOptions(toggle)
        }
        guard let format = firstView(of: NSPopUpButton.self, label: "Drag Me format") else {
            if firstView(of: SegmentedToggle.self, label: "Image format") == nil { gap("S09", "format control", "neither the format popup nor the PNG|JPG toggle was found") }
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
        for width in [980, 1024, 1280] {
            loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Frame")
            var f = window.frame; f.size.width = CGFloat(width); window.setFrame(f, display: true); pump(0.3)
            app.enterFrame(keepingAnnotations: false, manualFlags: [])
            pump(0.9)
            shoot("S12", "frame-w\(width)", surface: "Frame mode", state: "Frame mode at window width \(width) pt", refs: ["App.swift|func enterFrame", "ModernEditorChrome.swift|private func applyFrameMode"])
            app.leaveFrame(); pump(0.3)
            window.setFrame(CGRect(x: window.frame.minX, y: window.frame.minY, width: 1024, height: window.frame.height), display: true)
        }
    }

    // MARK: rail-removal state captures (T15 section j)

    /// A popover's geometry against the window and the control it hangs from, in screen points (bottom-left origin).
    func popoverMetrics(_ popoverWindow: NSWindow?, anchor: NSView) -> [String: Any] {
        guard let popoverWindow else { return ["popoverWindow": "none"] }
        let anchorScreen = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let pop = popoverWindow.frame
        return ["popoverClass": String(describing: type(of: popoverWindow)), "popoverFrameScreen": rectJSON(pop), "anchorFrameScreen": rectJSON(anchorScreen),
                "windowFrameScreen": rectJSON(window.frame),
                // The arrow tip may overlap the anchor by a few points, so "below" allows 14 pt.
                "opensBelowAnchor": pop.maxY <= anchorScreen.minY + 14,
                "insideWindowHorizontally": pop.minX >= window.frame.minX - 0.5 && pop.maxX <= window.frame.maxX + 0.5,
                "insideScreen": window.screen.map { $0.frame.insetBy(dx: -0.5, dy: -0.5).contains(pop) } ?? false,
                "popoverIsOpaque": popoverWindow.isOpaque, "popoverAlpha": Double(popoverWindow.alphaValue)]
    }

    /// Loads a synthetic shot, then puts the window at `spec`. Order matters: loading a shot resizes the window to fit it.
    func loadThenPlace(_ spec: String, size: CGSize, name: String, surface: String) -> CGSize? {
        loadSynthetic(size: size, name: name)
        guard let target = windowSize(for: spec, surface: surface) else { return nil }
        placeWindow(target)
        return target
    }

    func widthSlug(_ spec: String) -> String { "w" + String(spec.prefix { $0.isNumber }) }

    /// Stroke-size popover open from the top-bar pill, at 980 and 1280.
    func s30() {
        for spec in ["980xmin", "1280x800"] {
            guard loadThenPlace(spec, size: CGSize(width: 1000, height: 700), name: "Size popover", surface: "S30") != nil else { continue }
            app.setTool(.brush)
            app.widthControl.doubleValue = 6.75
            app.changeWidth(app.widthControl)
            pump(0.2)
            app.widthControl.showPopover()
            pump(0.7)
            let popoverWindow = app.widthControl.popover?.contentViewController?.view.window
            popoverWindow?.orderFrontRegardless()
            if popoverWindow == nil { gap("S30", "Size popover", "the popover window did not appear at \(spec)") }
            shoot("S30", "size-popover-\(widthSlug(spec))", surface: "Size popover", state: "Size popover open below the pill at window width \(spec), value 6.75, Brush tool",
                  windows: popoverWindow.map { [window, $0] } ?? [window], refs: ["BezelDrawingControls.swift|func showPopover", "BezelDrawingControls.swift|final class SizePopoverContent"],
                  settle: 0.2, extra: popoverMetrics(popoverWindow, anchor: app.widthControl))
            app.widthControl.dismissPopover()
            pump(0.4)
        }
    }

    /// Colour popover open from the top-bar swatch, at 980 and 1440: with a preset colour current (its swatch checked) and with a custom
    /// one (the Custom color… row carries the chip and the check).
    func s31() {
        for spec in ["980xmin", "1440x900"] {
            guard loadThenPlace(spec, size: CGSize(width: 1000, height: 700), name: "Colour popover", surface: "S31") != nil else { return }
            let width = widthSlug(spec)
            for (variant, color) in [("", OriginalDrawingControls.presets[0].color), ("-custom", NSColor(deviceRed: 0.18, green: 0.62, blue: 0.55, alpha: 1))] { // token-exempt: a custom drawing colour for the capture
                app.applyChosenColor(color, modifiers: [])
                app.presentDrawingColors(hover: false)
                pump(0.7)
                let popoverWindow = app.colorPopover?.contentViewController?.view.window
                popoverWindow?.orderFrontRegardless()
                if popoverWindow == nil { gap("S31", "Colour popover", "the popover window did not appear") }
                var extra = popoverMetrics(popoverWindow, anchor: app.paletteButton)
                extra["customRowIsCurrent"] = app.customColorButton?.isCurrentChoice ?? false
                extra["checkedPresets"] = app.presetColorButtons.filter { $0.state == .on }.map { $0.accessibilityLabel() ?? "" }
                if let content = app.colorPopover?.contentViewController?.view {
                    extra["popoverContentSize"] = [Double(content.frame.width), Double(content.frame.height)]
                    extra["rowFrames"] = (app.presetColorButtons.map { $0 as NSView } + [app.customColorButton].compactMap { $0 }).map { rectJSON($0.frame) }
                }
                shoot("S31", "color-popover\(variant)-\(width)", surface: "Colour popover", state: "Drawing colours popover open below the top-bar swatch at window width \(width.dropFirst()), \(variant.isEmpty ? "a preset colour current" : "a custom colour current")",
                      windows: popoverWindow.map { [window, $0] } ?? [window], refs: ["App.swift|func presentDrawingColors", "BezelDrawingControls.swift|final class BezelCustomColorButton"], settle: 0.2, extra: extra)
                if let popoverWindow {
                    shoot("S31", "color-popover-only\(variant)-\(width)", surface: "Colour popover", state: "the popover window alone\(variant.isEmpty ? "" : ", custom colour current")", windows: [popoverWindow], refs: ["App.swift|func presentDrawingColors"], settle: 0.1)
                }
                app.closeDrawingColors()
                pump(0.3)
            }
            app.applyChosenColor(OriginalDrawingControls.presets[0].color, modifiers: [])
        }
    }

    /// A shot big enough that the Original-size checkbox shows (`isLargeShot`), growing the synthetic size until the app agrees.
    func loadLargeShot(name: String) -> CGSize? {
        for size in [CGSize(width: 2400, height: 1500), CGSize(width: 3600, height: 2250), CGSize(width: 5200, height: 3250)] {
            loadSynthetic(size: size, name: name)
            if app.isLargeShot { return size }
        }
        return nil
    }

    /// Frame mode at 980 and 1280 over a canvas that fills the viewport: the hole runs to the margin and the capture rect equals it.
    func s32() {
        for spec in ["980xmin", "1280x800"] {
            guard loadLargeShot(name: "Frame large") != nil else { gap("S32", "Frame large", "no synthetic size made isLargeShot true"); return }
            app.zoomControl.selectItem(withTitle: "100%")
            app.changeZoom(app.zoomControl)
            guard let target = windowSize(for: spec, surface: "S32") else { continue }
            placeWindow(target)
            app.enterFrame(keepingAnnotations: false, manualFlags: [])
            pump(0.9)
            shoot("S32", "frame-large-\(widthSlug(spec))", surface: "Frame mode, canvas fills the viewport", state: "Frame mode at \(spec): large shot at 100% so the canvas fills the viewport; Snap Frame + Cancel; no Original size checkbox",
                  refs: ["App.swift|func enterFrame", "App.swift|var frameViewportScreenRect"],
                  extra: ["isLargeShot": app.isLargeShot, "originalSizeCheckboxHiddenInFrame": app.dragOriginalControl.isHidden])
            app.leaveFrame()
            pump(0.3)
        }
    }

    /// Large shot at 980 with the Original-size checkbox visible in the bottom bar.
    func s33() {
        guard let size = loadLargeShot(name: "Large shot") else { gap("S33", "Large shot", "no synthetic size made isLargeShot true"); return }
        _ = addAllAnnotationKinds(scale: size.width / 1200)
        placeWindow(windowSize(for: "980xmin", surface: "S33") ?? CGSize(width: 980, height: window.minSize.height))
        app.updateDragPreview()
        let shown = !app.dragOriginalControl.isHidden
        if !shown { gap("S33", "Large shot", "the Original size checkbox is hidden although isLargeShot is true") }
        let extra: [String: Any] = ["syntheticSize": [Double(size.width), Double(size.height)], "isLargeShot": app.isLargeShot, "originalSizeCheckboxVisible": shown]
        shoot("S33", "large-shot-w980", surface: "Large shot at 980", state: "\(Int(size.width))x\(Int(size.height)) shot at window width 980, Original size checkbox \(shown ? "visible" : "HIDDEN")",
              refs: ["AppViewport.swift|var isLargeShot", "ModernEditorChrome.swift|statusRow"], extra: extra)
        shoot("S33", "large-shot-w980-bottombar", surface: "Large shot at 980", state: "bottom bar only: Original size checkbox, status, groups", crop: footerCrop(),
              refs: ["ModernEditorChrome.swift|statusRow"], settle: 0.1, extra: extra)
    }

    /// A small canvas (150 x 90) sits in the middle of the viewport at every width.
    func s34() {
        for spec in ["980xmin", "1280x800", "1440x900"] {
            guard loadThenPlace(spec, size: CGSize(width: 150, height: 90), name: "Small canvas", surface: "S34") != nil else { continue }
            shoot("S34", "small-canvas-\(widthSlug(spec))", surface: "Small canvas centred", state: "150x90 canvas at window \(spec): equal margins left/right and top/bottom",
                  refs: ["ModernEditorChrome.swift|final class CenteringClipView"])
        }
    }

    /// A large canvas at 100% fills the viewport edge to edge (to the 12-pt margin) and pans.
    func s35() {
        for spec in ["980xmin", "1280x800"] {
            guard loadLargeShot(name: "Large canvas") != nil else { gap("S35", "Large canvas", "no synthetic size made isLargeShot true"); return }
            app.zoomControl.selectItem(withTitle: "100%")
            app.changeZoom(app.zoomControl)
            guard let target = windowSize(for: spec, surface: "S35") else { continue }
            placeWindow(target)
            shoot("S35", "large-canvas-\(widthSlug(spec))", surface: "Large canvas fills the viewport", state: "large shot at 100% in a \(spec) window: canvas runs to the 12-pt margin and scrolls",
                  refs: ["ModernEditorChrome.swift|scrollView.trailingAnchor"])
        }
    }

    /// Selection, then text editing, at 980 and 1280.
    func s36() {
        for spec in ["980xmin", "1280x800"] {
            guard loadThenPlace(spec, size: CGSize(width: 1000, height: 700), name: "Selection", surface: "S36") != nil else { continue }
            let named = addAllAnnotationKinds(scale: 1)
            app.setTool(.select)
            if let rect = named["rectangle"] { canvas.selection = [rect.id] }
            shoot("S36", "selection-\(widthSlug(spec))", surface: "Selection", state: "rectangle selected with handles at window \(spec); Color/Size/Font act on it", refs: ["Canvas.swift|private func drawSelectionChrome"])
            canvas.selection = []
            app.setTool(.text)
            if let down = mouse(.leftMouseDown, docPoint: CGPoint(x: 640, y: 690)), let up = mouse(.leftMouseUp, docPoint: CGPoint(x: 640, y: 690)) {
                canvas.mouseDown(with: down); canvas.mouseUp(with: up)
            }
            pump(0.4)
            if let editor = window.firstResponder as? NSTextView {
                editor.insertText("Edit in progress", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            shoot("S36", "text-editing-\(widthSlug(spec))", surface: "Text editing", state: "text tool field editor active with typed text at window \(spec)",
                  refs: ["Canvas.swift|private func beginTextEditing"], extra: ["fieldEditor": window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"])
            canvas.commitPendingTextEditing()
        }
    }

    /// PNG and JPG both selected at 980 with a large shot (checkbox visible): the bottom bar must not change width.
    func s37() {
        guard loadLargeShot(name: "Format states") != nil else { gap("S37", "Format states", "no synthetic size made isLargeShot true"); return }
        placeWindow(windowSize(for: "980xmin", surface: "S37") ?? CGSize(width: 980, height: window.minSize.height))
        guard let toggle = firstView(of: SegmentedToggle.self, label: "Image format") else { gap("S37", "Format states", "the PNG|JPG toggle was not found"); return }
        for (index, name) in [(0, "PNG"), (1, "JPG")] {
            toggle.selectedSegment = index
            app.changeDragOptions(toggle)
            app.updateDragPreview()
            let width = find("GlassFooterRow").map { Double(windowRect($0).width) } ?? 0
            shoot("S37", "format-\(name.lowercased())-w980", surface: "PNG | JPG at 980", state: "\(name) selected at window width 980 with the large-shot bottom bar; footer group width \(width) pt",
                  crop: footerCrop(), refs: ["ImageExport.swift|enum FormatToggle"], settle: 0.5, extra: ["footerRowGroupWidth": width, "selectedFormat": name])
        }
        toggle.selectedSegment = 0
        app.changeDragOptions(toggle)
    }

    /// OSN-044: every state the component state model draws, one capture per state at window width 980. The harness drives the same entry points the
    /// tracking areas and the responder chain do (`setHovered`, `highlight`, `makeFirstResponder`); a real pointer cannot be moved here.
    func s40() {
        guard #available(macOS 26, *), let chrome = app.modernChrome as? ModernEditorChrome,
              loadThenPlace("980xmin", size: CGSize(width: 1000, height: 700), name: "Component states", surface: "S40") != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        app.setTool(.brush)
        app.widthControl.doubleValue = 6.75
        app.changeWidth(app.widthControl)
        app.updateDragPreview()
        pump(0.3)
        func header(_ slug: String, _ state: String, _ refs: [String]) { shoot("S40", slug, surface: "component states", state: state, crop: headerCrop(), refs: refs, settle: 0.4) }
        func footer(_ slug: String, _ state: String, _ refs: [String]) { shoot("S40", slug, surface: "component states", state: state, crop: footerCrop(), refs: refs, settle: 0.4) }
        func focus(_ view: NSView?) { window.makeFirstResponder(view); pump(0.15) }
        let command = ["StateStyles.swift|static func command"]

        // Tools: the selected Brush shows the selection fill, border (and the capsule under Differentiate Without Color); the rest are bare.
        header("tool-selected-rest", "Brush selected (accent 0.20 fill, 1 pt accent border, computed glyph colour; a 2 x 16 pt capsule under Differentiate Without Color); the other nine tools at rest", command)
        if let tool = chrome.toolButtons["rectangle"] {
            tool.setHovered(true)
            header("tool-hover", "Rectangle tool hovered: a label 0.08 fill (0.16 under Increase Contrast); Brush still selected", ["GlassChrome.swift|func setHovered"])
            tool.setHovered(false)
            tool.highlight(true)
            header("tool-pressed", "Rectangle tool pressed: a label 0.16 fill (0.28 under Increase Contrast) and the glyph drawn at 0.96", ["GlassChrome.swift|override func highlight"])
            tool.highlight(false)
            tool.isEnabled = false
            header("tool-disabled", "Rectangle tool disabled: no fill, content dimmed to 0.38", ["GlassChrome.swift|alphaValue = style.contentAlpha"])
            tool.isEnabled = true
            focus(tool)
            header("tool-focus", "Rectangle tool keyboard-focused: AppKit's focus ring drawn through the button's own rounded mask", ["GlassChrome.swift|override func drawFocusRingMask"])
        }
        if let brush = chrome.toolButtons["brush"] {
            focus(brush)
            header("tool-selected-focus", "Brush (selected) keyboard-focused: the ring around the selection fill", ["GlassChrome.swift|override func becomeFirstResponder"])
            brush.setHovered(true)
            header("tool-selected-hover", "Brush (selected) hovered: hover does not wash out the selection", command)
            brush.highlight(true)
            header("tool-selected-pressed", "Brush (selected) pressed: the selected fill deepens by 0.12", command)
            brush.highlight(false); brush.setHovered(false)
        }
        focus(canvas)

        // Snap: the one saturated command.
        let snap = chrome.snapButton
        header("snap-rest", "Snap at rest: opaque accent fill, glyph colour computed against it", ["GlassChrome.swift|var isPrimary"])
        snap.setHovered(true)
        header("snap-hover", "Snap hovered: the accent brightened 8 %", ["StateStyles.swift|primaryHoverBrightness"])
        snap.setHovered(false)
        snap.highlight(true)
        header("snap-pressed", "Snap pressed: the accent darkened 12 % and the glyph at 0.96", ["StateStyles.swift|primaryPressedDarkening"])
        snap.highlight(false)
        snap.isEnabled = false
        header("snap-disabled", "Snap disabled: the accent dimmed to 0.38", ["GlassChrome.swift|alphaValue = style.contentAlpha"])
        snap.isEnabled = true
        focus(snap)
        header("snap-focus", "Snap keyboard-focused", ["GlassChrome.swift|override func becomeFirstResponder"])
        focus(canvas)

        // The Size pill: the cell behind it fills for hover and press, the stroke dims when disabled.
        let pill = app.widthControl, pillCell = pill.superview as? ChromeFillCell
        header("size-pill-rest", "Size pill at rest: the stroke is the current thickness (6.75)", ["BezelDrawingControls.swift|var pillStyle: StateStyle"])
        pillCell?.setHovered(true); pill.setHovered(true)
        header("size-pill-hover", "Size pill hovered: the cell takes the label 0.08 fill", ["GlassChrome.swift|func setPressed"])
        pillCell?.setHovered(false); pill.setHovered(false)
        pill.setPressed(true)
        header("size-pill-pressed", "Size pill pressed: the cell takes the 0.16 fill and the stroke is drawn 0.96 shorter", ["BezelDrawingControls.swift|func setPressed"])
        pill.setPressed(false)
        pill.isEnabled = false
        header("size-pill-disabled", "Size pill disabled: stroke dimmed to 0.38, no fill, not draggable", ["BezelDrawingControls.swift|override var isEnabled"])
        pill.isEnabled = true
        focus(pill)
        header("size-pill-focus", "Size pill keyboard-focused", ["BezelDrawingControls.swift|override var acceptsFirstResponder"])
        focus(canvas)

        // Size popover: the track's knob grows on hover and press.
        pill.showPopover()
        pump(0.6)
        if let popoverWindow = pill.popover?.contentViewController?.view.window, let track = pill.popoverContent?.trackView {
            popoverWindow.orderFrontRegardless()
            track.setHovered(true)
            shoot("S40", "size-track-hover", surface: "component states", state: "Size popover, pointer over the track: the knob grows to 1.15", windows: popoverWindow === window ? [window] : [window, popoverWindow],
                  refs: ["BezelDrawingControls.swift|var knobRect"], settle: 0.3, extra: popoverMetrics(popoverWindow, anchor: pill))
            track.setPressed(true)
            shoot("S40", "size-track-pressed", surface: "component states", state: "Size popover, knob held: the knob at 1.25 and an accent 0.3 wash over the track", windows: [window, popoverWindow],
                  refs: ["StateStyles.swift|static func track"], settle: 0.3, extra: popoverMetrics(popoverWindow, anchor: pill))
            track.setPressed(false); track.setHovered(false)
            if let preset = pill.popoverContent?.presetButtons.first {
                preset.setHovered(true)
                shoot("S40", "size-preset-hover", surface: "component states", state: "Size popover, the smallest preset hovered (command hover fill) beside the selected one", windows: [window, popoverWindow],
                      refs: ["BezelDrawingControls.swift|var commandStyle: StateStyle"], settle: 0.3, extra: popoverMetrics(popoverWindow, anchor: pill))
                preset.setHovered(false)
            }
        } else { gap("S40", "Size track states", "the Size popover window did not appear") }
        pill.dismissPopover()
        pump(0.3)

        // Colour swatches: selected (3 pt accent outline + check), hover, pressed.
        app.presentDrawingColors(hover: false)
        pump(0.7)
        if let popoverWindow = app.colorPopover?.contentViewController?.view.window, app.presetColorButtons.count > 4 {
            popoverWindow.orderFrontRegardless()
            let swatches = app.presetColorButtons
            swatches[2].setHovered(true)
            swatches[4].highlight(true)
            shoot("S40", "swatch-states", surface: "component states", state: "Colour popover: Red selected (3 pt accent outline and check glyph), Blue hovered (label 0.5 outline), Translucent gray pressed (0.16 fill)",
                  windows: [popoverWindow], refs: ["BezelDrawingControls.swift|var swatchStyle: SwatchStyle", "BezelDrawingControls.swift|static func drawTinted"], settle: 0.3, extra: popoverMetrics(popoverWindow, anchor: app.paletteButton))
            swatches[2].setHovered(false); swatches[4].highlight(false)
        } else { gap("S40", "Swatch states", "the colour popover window did not appear") }
        app.closeDrawingColors()
        // Closing a popover hands key status away; the focus rings below only draw in the key window.
        window.makeKeyAndOrderFront(nil)
        pump(0.5)

        // Bottom bar: Undo and Wipe, the drag well, the PNG | JPG toggle.
        chrome.undoButton.setHovered(true)
        footer("undo-hover", "Undo hovered: label 0.08 fill", ["GlassChrome.swift|func setHovered"])
        chrome.undoButton.setHovered(false)
        chrome.wipeButton.highlight(true)
        footer("wipe-pressed", "Wipe pressed: label 0.16 fill, glyph at 0.96", ["GlassChrome.swift|override func highlight"])
        chrome.wipeButton.highlight(false)
        chrome.undoButton.isEnabled = false; chrome.wipeButton.isEnabled = false
        footer("undo-wipe-disabled", "Undo and Wipe disabled: no fill, content at 0.38", ["GlassChrome.swift|alphaValue = style.contentAlpha"])
        chrome.undoButton.isEnabled = true; chrome.wipeButton.isEnabled = true
        focus(chrome.undoButton)
        footer("undo-focus", "Undo keyboard-focused", ["GlassChrome.swift|override func becomeFirstResponder"])
        focus(canvas)

        if let drag = app.dragExportView {
            let cell = drag.superview as? ChromeFillCell
            footer("drag-rest", "Drag well at rest: the open-hand glyph, no plate", ["App.swift|final class DragExportView"])
            cell?.setHovered(true); drag.setHovered(true)
            footer("drag-hover", "Drag well hovered: the cell takes the label 0.08 fill; the pointer is an open hand", ["App.swift|override func resetCursorRects"])
            cell?.setHovered(false); drag.setHovered(false)
            drag.setPressed(true)
            footer("drag-pressed", "Drag well held: the cell takes the 0.16 fill; the pointer is a closed hand", ["App.swift|var wellCursor: NSCursor"])
            drag.setPressed(false)
            focus(drag)
            footer("drag-focus", "Drag well keyboard-focused (Space or Return opens the Export panel)", ["App.swift|override func drawFocusRingMask", "App.swift|override func accessibilityPerformPress"])
            focus(canvas)
        } else { gap("S40", "Drag well states", "the drag well was not found") }

        let toggle = app.dragFormatToggle
        toggle.selectedSegment = 0; app.changeDragOptions(toggle)
        footer("toggle-png", "PNG | JPG with PNG selected: accent 0.20 plate, 1 pt border, bodyStrong text; JPG on its faint plate", ["GlassChrome.swift|final class SegmentedToggle"])
        toggle.selectedSegment = 1; app.changeDragOptions(toggle)
        footer("toggle-jpg", "PNG | JPG with JPG selected", ["GlassChrome.swift|final class SegmentedToggle"])
        toggle.selectedSegment = 0; app.changeDragOptions(toggle)
        toggle.setHoveredSegment(1)
        footer("toggle-hover", "PNG selected, JPG hovered: label 0.08 plate", ["GlassChrome.swift|func setHoveredSegment"])
        toggle.setHoveredSegment(nil)
        toggle.setPressedSegment(1)
        footer("toggle-pressed", "PNG selected, JPG pressed: label 0.16 plate", ["GlassChrome.swift|func setPressedSegment"])
        toggle.setPressedSegment(nil)
        focus(toggle)
        footer("toggle-focus", "PNG | JPG keyboard-focused (Left, Right and Space change the format)", ["GlassChrome.swift|override func keyDown"])
        focus(canvas)
        toggle.isEnabled = false
        footer("toggle-disabled", "PNG | JPG disabled: both segments' content at 0.38", ["GlassChrome.swift|override var isEnabled: Bool { didSet { needsDisplay"])
        toggle.isEnabled = true
        app.updateStatus()
        window.makeKeyAndOrderFront(nil)

        // The canvas border on a small canvas, so the hairline and the handles are easy to see.
        loadSynthetic(size: CGSize(width: 520, height: 300), name: "Border states")
        app.setTool(.arrow)
        pump(1.0)
        shoot("S40", "border-rest", surface: "component states", state: "Canvas border at rest: a separator hairline, no handles", refs: ["CanvasBorderView.swift|guard revealsHandles"], settle: 0.4)
        app.canvasBorder.setHovered(true)
        shoot("S40", "border-hover", surface: "component states", state: "Pointer over the border: the accent outline and the four corner handles", refs: ["CanvasBorderView.swift|func setHovered"], settle: 0.4)
        app.canvasBorder.setHovered(false)
        app.setTool(.crop)
        shoot("S40", "border-crop-tool", surface: "component states", state: "Crop tool chosen: the handles stay on without hover", refs: ["App.swift|canvasBorder.showsHandles"], settle: 0.4)
        app.setTool(.arrow)
    }

    func s16() {
        // The sheet Capture presents when Screen Recording is missing, over the editor. Its Settings opener is a no-op here and TCC is never asked.
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Permission")
        let sheet = ScreenRecordingPermissionSheet(openURL: { _ in })
        sheet.present(on: window)
        pump(1.0)
        let refs = ["Capture.swift|final class ScreenRecordingPermissionSheet", "Capture.swift|struct ScreenRecordingGate"]
        shoot("S16", "permission-sheet", surface: "Screen Recording permission sheet", state: "app-owned sheet: title, instructions, Open System Settings (default) and Cancel",
              windows: [sheet.panel], refs: refs, settle: 0.4, extra: ["capturedWindow": "sheet itself", "sheetOnScreen": sheet.panel.isVisible])
        // The overlay goes FIRST: CGWindowListCreateImageFromArray treats the first window as frontmost.
        shoot("S16", "permission-sheet-in-context", surface: "Screen Recording permission sheet", state: "the sheet over the dimmed editor (sheet + parent composite, sheet in front)",
              windows: [sheet.panel, window], refs: refs, settle: 0.1, extra: ["capturedWindow": "sheet + parent composite"])
        sheet.cancel()
        pump(0.4)
    }

    /// The Settings window, built straight from SettingsWindow.swift against stand-ins, so the capture does not depend on how the app opens it.
    /// Every tab is imaged at the screen's own size and again as sized for a 1280 x 800 screen (menu bar and Dock taken off).
    func s17() {
        let fakeVisible = CGSize(width: 1280, height: 706)
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.com/files"; dav.username = "demo"; dav.publicBaseURL = "https://dav.example.com/files"
        var s3 = PublishingSettings(); s3.transport = .s3; s3.publicBaseURL = "https://cdn.example.com/pics"; s3.s3 = S3Options()
        var sftp = PublishingSettings(); sftp.transport = .sftp; sftp.endpoint = "sftp://example.com/var/www"
        let items = [PublishingDestination(name: "Example S3", settings: s3), PublishingDestination(name: "Example WebDAV", settings: dav),
                     PublishingDestination(name: "Example SFTP", settings: sftp)]
        let list = PublishingDestinationList(defaultID: items[0].id, destinations: items)
        var stored = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2, includeApp: true, statusMenu: 0)
        var destinations = list
        let controller = SettingsWindowController(state: { stored }, hotkeys: GlobalHotkeyManager(defaults: .standard, backend: AuditInertHotkeyBackend()), defaults: .standard,
                                                  destinations: { destinations }, manageDestinations: { _ in })
        controller.onChange = { stored = $0 }
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let refs = ["SettingsWindow.swift|final class SettingsWindowController", "SettingsWindow.swift|final class SettingsTabViewController"]
        func place(_ visible: NSRect) {
            controller.visibleFrame = { visible }
            controller.fit(animated: false)
            controller.window.setFrameTopLeftPoint(NSPoint(x: visible.minX + 40, y: visible.maxY - 24))
        }
        func capture(_ tab: Int, _ slug: String, _ state: String) {
            controller.select(tab)
            place(screen)
            controller.show()
            controller.window.setFrameTopLeftPoint(NSPoint(x: screen.minX + 40, y: screen.maxY - 24))
            let title = controller.tabItems[tab].label
            shoot("S17", "settings-" + slug, surface: "Settings: " + title, state: state, windows: [controller.window], refs: refs, settle: 0.5,
                  extra: ["windowTitle": controller.window.title, "tabFittingHeight": Double(controller.windowHeight(forTabAt: tab))])
            // The captured window is the size its tab asks for: a late animation from an earlier change would show up here.
            if abs(controller.window.frame.height - controller.windowHeight(forTabAt: tab)) > 0.5 {
                gap("S17", "Settings: " + title, "the window settled at \(controller.window.frame.height) pt, not the \(controller.windowHeight(forTabAt: tab)) pt its tab asks for")
            }
            let fake = NSRect(x: screen.minX, y: screen.maxY - fakeVisible.height, width: fakeVisible.width, height: fakeVisible.height)
            place(fake)
            let fits = controller.window.frame.height <= fakeVisible.height
            shoot("S17", "settings-" + slug + "-1280x800", surface: "Settings: " + title, state: state + ", sized for a 1280 x 800 screen (\(Int(fakeVisible.height)) pt visible)", windows: [controller.window], refs: refs, settle: 0.5,
                  extra: ["fakeScreen": "1280x800", "fakeVisibleHeight": Double(fakeVisible.height), "windowHeight": Double(controller.window.frame.height), "fitsVisibleHeight": fits])
            if !fits { gap("S17", "Settings: " + title, "the window is \(controller.window.frame.height) pt tall on a \(fakeVisible.height) pt visible height") }
        }
        capture(0, "general", "General tab, default values")
        capture(1, "drawing", "Drawing tab, default values")
        capture(2, "capture", "Capture tab: flash on, shortcuts enabled, every action None")
        capture(3, "upload", "Upload tab: three saved destinations, the first is the default")
        stored = GeneralPreferencesState(drawingPrecision: .loose, arrowHead: 1, includeApp: false, statusMenu: 1, showToolTips: true, showKeyboardTips: true)
        controller.refresh()
        capture(0, "general-alt", "General tab, alternate values (Menu bar, snap window off, both hint options on)")
        capture(1, "drawing-alt", "Drawing tab, alternate values (Loose, Start)")
        // A refused shortcut leaves its error line on the tab, which grows the window to hold it.
        controller.select(2)
        let form = controller.capture.hotkeyForm!
        let key = form.keyPopup(for: .screen)
        key.selectItem(withTitle: "K"); _ = key.target?.perform(key.action, with: key)
        capture(2, "capture-error", "Capture tab with a refused shortcut (a key with no Command or Control)")
        key.selectItem(at: 0); _ = key.target?.perform(key.action, with: key)
        destinations = PublishingDestinationList()
        controller.refresh()
        capture(3, "upload-empty", "Upload tab, no destination saved")
        controller.window.orderOut(nil)
    }

    func s18() {
        app.shortcutSettings()
        captureSheet("S18", "hotkeys-sheet", surface: "Preferences: Hotkeys", state: "Capture Shortcuts sheet (all actions None)",
                     refs: ["GlobalHotkeys.swift|final class GlobalHotkeyForm", "GlobalHotkeys.swift|func present(attachedTo", "App.swift|@objc func shortcutSettings()"], dismiss: { [self] in
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
            // Test-result states are fed straight to the view, so nothing contacts a destination.
            view.showTestResult(ok: true, message: "OK: credentials and bucket verified. Nothing was uploaded.")
            pump(0.4)
            shootSheet("S19", "destinations-test-connected", surface: "Destinations / Publishing", state: "S3 form after a synthetic successful Test: check glyph, Connected, detail line", refs: ["PublishingDestinationsView.swift|func showTestResult", "PublishingDestinationsView.swift|final class DestinationStatusRow"], host: window, sheet: panel)
            view.showTestResult(ok: false, message: "The request signature does not match the signature provided.")
            pump(0.4)
            shootSheet("S19", "destinations-test-error", surface: "Destinations / Publishing", state: "S3 form after a synthetic failed Test: octagon glyph and an Error: line", refs: ["PublishingDestinationsView.swift|func showTestResult", "PublishingDestinationsView.swift|final class DestinationStatusRow"], host: window, sheet: panel)
            closeHarnessSheet(panel)
            // Short display: the sheet is sized for a 1280 x 500 visible frame, so the form scrolls and the buttons stay pinned.
            let (shortPanel, shortView) = try app.publishing.buildSettings(visibleFrame: NSRect(x: 0, y: 0, width: 1280, height: 500))
            window.beginSheet(shortPanel)
            pump(0.8)
            shortView.select(id: try AppDelegate.publishingStore.load().defaultID ?? "")
            shortView.editTapped()
            pump(0.5)
            shootSheet("S19", "destinations-short-screen", surface: "Destinations / Publishing", state: "edit form on a short display (visible frame 1280 x 500): the form scrolls and Test, Cancel and Save stay pinned", refs: ["Publishing.swift|func buildSettings(visibleFrame", "PublishingDestinationsView.swift|static func sheetSize"], host: window, sheet: shortPanel)
            closeHarnessSheet(shortPanel)
            // Audit batch 3b: one form per protocol with its own placeholders, help and Test note; a Test result for a non-S3 protocol;
            // and the sheet as it hangs from the 640 pt Settings window (as wide as its parent, never overhanging it).
            let (formPanel, formView) = try app.publishing.buildSettings()
            window.beginSheet(formPanel); pump(0.8)
            formView.addTapped()
            for transport in PublishingProtocol.allCases {
                formView.protocolPopup.selectItem(withTitle: transport.title); formView.formChanged()
                pump(0.4)
                shootSheet("S19", "destinations-form-\(transport.rawValue.lowercased())", surface: "Destinations / Publishing", state: "new \(transport.title) destination: its own endpoint scheme, placeholders and help, and the Test note in the reserved result band", refs: ["PublishingDestinationsView.swift|static func formCopy", "PublishingDestinationsView.swift|private func refreshForm"], host: window, sheet: formPanel)
            }
            formView.protocolPopup.selectItem(withTitle: PublishingProtocol.webDAV.title); formView.formChanged()
            formView.showTestResult(ok: false, message: "The server rejected the user name or password (HTTP 401).")
            pump(0.4)
            shootSheet("S19", "destinations-test-error-webdav", surface: "Destinations / Publishing", state: "WebDAV form after a synthetic failed Test (HTTP 401): the same band, the form above it unchanged", refs: ["Publishing.swift|enum PublishingConnectionTest", "PublishingDestinationsView.swift|func showTestResult"], host: window, sheet: formPanel)
            closeHarnessSheet(formPanel)
            let (narrowPanel, narrowView) = try app.publishing.buildSettings(hostWidth: SettingsLayout.contentWidth)
            window.beginSheet(narrowPanel); pump(0.8)
            narrowView.select(id: try AppDelegate.publishingStore.load().defaultID ?? ""); narrowView.editTapped(); pump(0.5)
            shootSheet("S19", "destinations-from-settings-640", surface: "Destinations / Publishing", state: "the sheet as hosted by the 640 pt Settings window: 640 wide, so it never overhangs its parent", refs: ["Publishing.swift|func buildSettings(visibleFrame", "PublishingDestinationsView.swift|static func sheetWidth(forHostWidth"], host: window, sheet: narrowPanel)
            closeHarnessSheet(narrowPanel)
        } catch { gap("S19", "Destinations list/edit form", "buildSettings threw: \(error.localizedDescription)") }
    }

    /// These sheets are begun on the window directly, not through the coordinator, so ending the sheet first keeps the
    /// coordinator's quit barrier from waiting forever for a dismissal callback it never registered. Every surface that
    /// begins a Destinations sheet itself closes it here (S19, S26D), the way pressing Cancel would. The whole audit runs inside
    /// one main-queue block, so a completion handler queued by AppKit could never run before the quit that ends the run.
    func closeHarnessSheet(_ panel: NSPanel) {
        window.endSheet(panel); pump(0.4)
        app.publishing.cancelSettings(); pump(0.3)
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
                let date = calendar.date(byAdding: .day, value: -(index / 3) * 3, to: Date())?.addingTimeInterval(-Double(index) * 600) ?? Date()
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
                var tiles: [HistoryTileView] = []
                func collectTiles(_ view: NSView) { if let tile = view as? HistoryTileView { tiles.append(tile) }; view.subviews.forEach(collectTiles) }
                if let content = history.contentView { collectTiles(content) }
                if let other = tiles.first(where: { !$0.isTileSelected }) {
                    other.setHovered(true)
                    shoot("S20", "history-tile-hover", surface: "History browser", state: "one entry selected (accent fill, border, check badge) and another tile hovered (label 0.08 fill)", windows: [history],
                          refs: ["HistoryBrowser.swift|func setHovered"], settle: 0.4)
                    other.setHovered(false)
                } else { gap("S20", "History tile hover", "no unselected tile was found in the grid") }
                for (width, height) in [(880, 600), (1120, 850), (1280, 800)] as [(CGFloat, CGFloat)] {
                    history.setFrame(NSRect(x: history.frame.minX, y: max(40, history.frame.maxY - height), width: width, height: height), display: true)
                    pump(0.8)
                    shoot("S20", "history-\(Int(width))x\(Int(height))-selected", surface: "History browser", state: "six synthetic entries, one selected, window \(Int(width)) x \(Int(height)): grid reflow, check badge, details beside the grid", windows: [history], refs: ["HistoryBrowser.swift|final class HistoryTileView", "HistoryBrowser.swift|func layoutDetails"])
                }
                history.setFrame(NSRect(x: history.frame.minX, y: max(40, history.frame.maxY - 600), width: 880, height: 600), display: true)
                app.historyBrowser?.setFilters(category: .shared, date: .all, query: "no such snap")
                pump(0.6)
                shoot("S20", "history-no-match", surface: "History browser", state: "filters that match nothing at 880 x 600: centred message, no save hint", windows: [history], refs: ["HistoryBrowser.swift|private func updateEmptyState"])
                app.historyBrowser?.setFilters(category: .all)
                // Audit batch 3b: nothing selected at the minimum (summary column), a clipped link made whole, and the footer confirmation.
                app.historyBrowser?.select(ids: [])
                pump(0.6)
                shoot("S20", "history-880x600-none", surface: "History browser", state: "880 x 600, nothing selected: the details column shows the summary instead of a blank hint; tiles sized to their preview", windows: [history], refs: ["HistoryBrowser.swift|static func summaryLines", "HistoryBrowser.swift|static func tileHeight"])
                if let shared = app.historyStore?.entries.first(where: { $0.remoteURL != nil })?.id {
                    app.historyBrowser?.select(ids: [shared])
                    app.historyBrowser?.confirm("Link copied")
                    pump(0.6)
                    shoot("S20", "history-link-copied", surface: "History browser", state: "a Shared entry selected after Copy Link: the footer confirms, and the destination link is cut in its middle with the full text in its tooltip", windows: [history], refs: ["HistoryBrowser.swift|func confirm", "HistoryBrowser.swift|let isLink"])
                    app.historyBrowser?.clearConfirmation()
                }
                app.historyBrowser?.setFilters(category: .shared, date: .all, query: "no such snap")
                pump(0.6)
                shoot("S20", "history-no-match-footer", surface: "History browser", state: "filters that match nothing: the footer stays (0 of 6 items) and Clear filters offers the way out", windows: [history], refs: ["HistoryBrowser.swift|func clearFilters", "HistoryBrowser.swift|static func statusText"])
                app.historyBrowser?.setFilters(category: .all)
            }
            history.orderOut(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    final class UploadGate: @unchecked Sendable {
        let release = DispatchSemaphore(value: 0)
        var mode = "success"
    }

    /// OSN-054: the upload states in the status slot of the bottom bar, at 980, 1280 and 1440, over a large shot so the Original size
    /// checkbox takes part (it steps aside only where the slot cannot hold it). The uploader is a stub; nothing leaves the process.
    func s21() {
        syntheticDestinations()
        guard loadLargeShot(name: "Quarterly planning review of the new upload flow") != nil else { gap("S21", "publish states", "no synthetic size made isLargeShot true"); return }
        let gate = UploadGate()
        app.publishing.clipboardWriter = { _ in }
        app.linkOpener = { _ in }
        // The "Link copied" state is held for the capture and ended by hand; in the app it lasts four seconds.
        app.uploadSuccessDuration = 600
        app.publishing.uploader = { _, _, plan, _ in
            if gate.mode == "wait" { _ = gate.release.wait(timeout: .now() + 8) }
            if gate.mode == "fail" { throw PublishingFailure("Upload to Example S3 failed: the connection was refused (stub, no network was used).") }
            return plan.publicURL ?? plan.remoteURL
        }
        let refs = ["UploadStatus.swift|enum UploadState", "App+Upload.swift|func uploadStateChanged", "App.swift|func beginUpload", "ModernEditorChrome.swift|let uploadControls"]
        for spec in ["980xmin", "1280x800", "1440x900"] {
            guard let size = windowSize(for: spec, surface: "S21") else { continue }
            placeWindow(size)
            window.makeKeyAndOrderFront(nil); pump(0.4)
            let width = widthSlug(spec)
            app.uploadState = .idle
            gate.mode = "wait"
            app.publishImage()
            pump(0.8)
            shoot("S21", "publish-progress-\(width)", surface: "publish progress", state: "Uploading <name>\u{2026}: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at \(width)", refs: refs, extra: ["status": app.status.stringValue, "uploadState": String(describing: app.uploadState), "originalSizeCheckboxHidden": app.dragOriginalControl.isHidden])
            shoot("S21", "publish-progress-footer-\(width)", surface: "publish progress", state: "footer crop during the upload, at \(width)", crop: footerCrop(), refs: refs, settle: 0.1)
            if width == "w980", let share = app.webpostButton, let menu = share.menu {
                captureTrackedMenu("S21", "upload-menu-busy", surface: "publish progress", state: "destination menu while an upload runs (Cancel Upload offered)", refs: ["App.swift|Cancel Upload"],
                                   dismiss: { menu.cancelTracking() }, trigger: { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: share.bounds.height + 4), in: share) })
            }
            gate.release.signal()
            pump(1.5)
            shoot("S21", "publish-success-\(width)", surface: "publish success", state: "Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at \(width)", refs: refs, extra: ["status": app.status.stringValue, "uploadState": String(describing: app.uploadState), "originalSizeCheckboxHidden": app.dragOriginalControl.isHidden])
            shoot("S21", "publish-success-footer-\(width)", surface: "publish success", state: "footer crop with Link copied · the link, Open and Copy, at \(width)", crop: footerCrop(), refs: refs, settle: 0.1)
            app.expireUploadSuccess()
            pump(0.4)
            gate.mode = "fail"
            app.publishImage()
            pump(1.5)
            shoot("S21", "publish-error-\(width)", surface: "publish error", state: "inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at \(width)", refs: refs, extra: ["status": app.status.stringValue, "uploadState": String(describing: app.uploadState), "originalSizeCheckboxHidden": app.dragOriginalControl.isHidden])
            shoot("S21", "publish-error-footer-\(width)", surface: "publish error", state: "footer crop with the inline error, Retry and Details, at \(width)", crop: footerCrop(), refs: refs, settle: 0.1)
            captureAlertSheet("S21", "publish-error-details-\(width)", surface: "publish error", state: "the Details\u{2026} sheet with the whole error (no second Error: under the title), at \(width)", refs: ["App+Upload.swift|func showUploadErrorDetails"]) { app.showUploadErrorDetails() }
            // Retry while the stub holds the transfer: the status names the new attempt.
            gate.mode = "wait"
            app.retryUpload()
            pump(0.8)
            shoot("S21", "publish-retrying-\(width)", surface: "publish retry", state: "Retrying <name>\u{2026} with the spinner and Cancel, after Retry from a failed upload, at \(width)", refs: refs, extra: ["status": app.status.stringValue, "uploadState": String(describing: app.uploadState)])
            app.cancelUpload()
            gate.release.signal()
            pump(1.2)
            shoot("S21", "publish-cancelled-\(width)", surface: "publish cancelled", state: "Upload cancelled in the status line after Cancel, kept for ten seconds, at \(width)", refs: refs + ["UploadStatus.swift|enum UploadNotice"], extra: ["status": app.status.stringValue, "uploadState": String(describing: app.uploadState)])
            UploadNotice.clear()
            app.uploadState = .idle
            pump(0.3)
        }
    }

    /// OSN-043: the window titled with the document name and its size, the proxy icon, and the app-owned alert sheets.
    func s39() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Quarterly mockup")
        _ = addAllAnnotationKinds(scale: 1)
        // A saved document: the file is written into the throwaway support folder, so the title bar shows a proxy icon for it.
        app.currentURL = app.support.appendingPathComponent("Quarterly mockup.opensnap")
        _ = app.save()
        app.updateDragPreview()
        for spec in ["980xmin", "1280x800"] {
            guard let size = windowSize(for: spec, surface: "S39") else { continue }
            placeWindow(size)
            window.makeKeyAndOrderFront(nil); pump(0.4)
            let width = spec.hasPrefix("980") ? "w980" : "w1280"
            let facts: [String: Any] = ["windowTitle": window.title, "subtitle": window.subtitle, "representedURL": window.representedURL?.lastPathComponent ?? "none",
                                        "titlebarSeparatorStyle": String(describing: window.titlebarSeparatorStyle), "backgroundIsSurfaceWindow": window.backgroundColor == DesignTokens.Palette.Surface.window,
                                        "fullScreenPrimary": window.collectionBehavior.contains(.fullScreenPrimary), "minSize": NSStringFromSize(window.minSize)]
            shoot("S39", "titled-window-\(width)", surface: "titled window", state: "title = document name, subtitle = size, proxy icon, no title-bar separator, at \(width)",
                  refs: ["App+ModernChrome.swift|func configureWindowChrome()", "App.swift|window?.subtitle = dragSizeLabel.stringValue"], extra: facts)
            shoot("S39", "titlebar-crop-\(width)", surface: "titled window", state: "the title bar and top bar only, at \(width)", crop: headerCrop(),
                  refs: ["App+ModernChrome.swift|func configureWindowChrome()"], settle: 0.1, extra: facts)
        }
        app.dirty = true
        captureAlertSheet("S39", "discard-sheet", surface: "alerts / sheets", state: "Save your drawing? sheet over the titled window (Save / Cancel / Don\u{2019}t Save)",
                          refs: ["App.swift|func confirmDiscard(", "AppAlert.swift|final class AppAlert"]) { app.confirmDiscard { _ in } }
        app.dirty = false
        syntheticDestinations()
        app.publishing.clipboardWriter = { _ in }
        app.publishing.uploader = { _, _, _, _ in throw PublishingFailure("Upload to Example S3 failed: the connection was refused (stub, no network was used).") }
        captureAlertSheet("S39", "upload-error-sheet", surface: "alerts / sheets", state: "Details\u{2026} sheet after a stubbed failed upload (the error itself is inline), over the titled window",
                          refs: ["App.swift|func receivePublishing", "App+Upload.swift|func showUploadErrorDetails"]) { app.publishImage(); pump(2.5); app.showUploadErrorDetails() }
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
        // Menus are not part of any window composite, so the status menu is dumped as titles, actions and fonts.
        let statusMenu = app.statusItem?.menu ?? app.makeStatusMenu()
        menus["statusItemMenu"] = menuNode(statusMenu)
        menus["statusItem"] = ["hasMenu": app.statusItem?.menu != nil, "installedInThisProcess": app.statusItem != nil,
                               "buttonToolTip": app.statusItem?.button?.toolTip ?? StatusIcon.name, "buttonAccessibilityLabel": app.statusItem?.button?.accessibilityLabel() ?? StatusIcon.name,
                               "iconIsTemplate": StatusIcon.image()?.isTemplate as Any,
                               "note": "Clicking the icon opens statusItemMenu; the first row follows the editor's visibility. The menu-bar strip titles are system-owned."]
        write(menus, to: "menus" + stemSuffix + ".json")
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
        let stem = stemFor(id, slug)
        guard view.bounds.width > 1, view.bounds.height > 1, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            gap(id, surface + " / " + state, "the view has no drawable bounds"); return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { gap(id, surface + " / " + state, "PNG encoding failed"); return }
        try? png.write(to: dir.appendingPathComponent(stem + ".png"))
        var meta: [String: Any] = ["id": id, "slug": slug, "surface": surface, "state": state, "appearance": appearance, "file": stem + ".png",
            "pixelSize": [rep.pixelsWide, rep.pixelsHigh], "pointSize": [Double(view.bounds.width), Double(view.bounds.height)],
            "scale": Double(rep.pixelsWide) / Double(view.bounds.width), "method": "NSView.cacheDisplay (view only, not a window capture)", "sourceRefs": refs,
            "sourceSha": sourceSha, "iconMode": iconMode, "displayOptions": displayOptionsJSON, "windowSize": [Double(window.frame.width.rounded()), Double(window.frame.height.rounded())], "appActive": NSApp.isActive]
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
            shoot("S25", "about-panel", surface: "About window", state: "app-owned About window: icon, name, version and build, credit line, license link", windows: [panel],
                  refs: ["App.swift|@objc func about()", "AboutWindow.swift|final class AboutWindow"])
            if let about = panel as? AboutWindow {
                write(["title": about.title, "name": about.nameLabel.stringValue, "version": about.versionLabel.stringValue, "credit": about.creditLabel.stringValue,
                       "licenseLink": about.licenseButton.attributedTitle.string,
                       "fonts": ["name": fontInfo(about.nameLabel.font) as Any, "version": fontInfo(about.versionLabel.font) as Any, "credit": fontInfo(about.creditLabel.font) as Any,
                                 "licenseLink": fontInfo(about.licenseButton.font) as Any],
                       "note": "The title bar text is visible, so the window has a name to find it by.", "titleVisible": about.titleVisibility == .visible] as [String: Any], to: "about" + stemSuffix + ".json")
            }
            if let about = panel as? AboutWindow {
                let license = about.makeLicenseWindow()
                license.setFrameTopLeftPoint(NSPoint(x: panel.frame.maxX + 24, y: panel.frame.maxY))
                license.makeKeyAndOrderFront(nil); pump(0.6)
                shoot("S25", "license-window", surface: "About window", state: "the MIT License window with the paragraphs reflowed to the window width", windows: [license], refs: ["AboutWindow.swift|static func reflowed"])
                license.orderOut(nil)
            }
            panel.orderOut(nil)
        } else { gap("S25", "About window", "the About window was not found") }
    }

    func s26() {
        captureAlertSheet("S26", "rename", surface: "alerts / sheets", state: "Rename… sheet with text field", refs: ["App.swift|@objc func renameDocument()", "App.swift|func prompt(", "AppAlert.swift|final class AppAlert"]) { app.renameDocument() }
        app.dirty = true
        captureAlertSheet("S26", "close-unsaved", surface: "alerts / sheets", state: "Save your drawing? sheet (Save / Cancel / Don’t Save)", refs: ["App.swift|func confirmDiscard(", "AppAlert.swift|final class AppAlert"]) { app.confirmDiscard { _ in } }
        app.dirty = false
        captureAlertSheet("S26", "error-generic", surface: "alerts / sheets", state: "generic error sheet", refs: ["App.swift|func error(_ error: Error)", "AppAlert.swift|convenience init(error: Error)"]) {
            app.error(NSError(domain: "OpenSnap", code: 5, userInfo: [NSLocalizedDescriptionKey: "This capture is too large or cannot be decoded safely."]))
        }
        if let store = try? app.archiveStore() {
            if store.entries.isEmpty, let snapshot = try? app.historySnapshot() { _ = try? store.archive(snapshot, name: "Alert demo", action: .archived) }
            if let id = store.entries.first?.id {
                captureAlertSheet("S26", "history-hide", surface: "alerts / sheets", state: "Hide drawings from History? sheet", refs: ["App.swift|func removeHistory("]) { app.removeHistory([id], deleteFiles: false) }
                captureAlertSheet("S26", "history-trash", surface: "alerts / sheets", state: "Move archived drawings to Trash? sheet", refs: ["App.swift|func removeHistory("]) { app.removeHistory([id], deleteFiles: true) }
            }
        }
        gap("S26", "Wipe confirmation", "No Wipe confirmation exists: Wipe/Undo (Canvas.wipe) acts immediately, so there is nothing to capture; recorded as a finding")
    }

    /// The Remove destination question as an app-owned sheet on the Upload Destinations sheet (a surface of its own so it can run alone).
    func s26d() {
        syntheticDestinations()
        do {
            let (panel, view) = try app.publishing.buildSettings()
            window.beginSheet(panel); pump(0.8)
            let list = try AppDelegate.publishingStore.load()
            if let name = list.destinations.first?.name, let target = list.destinations.first {
                view.select(id: target.id)
                view.removeTapped(); pump(0.9)
                if let alert = AppAlert.presentedAlerts.last {
                    shoot("S26", "remove-destination", surface: "alerts / sheets", state: "Remove “\(name)”? sheet on the Upload Destinations sheet (default destination): Cancel is the default, Remove is destructive",
                          windows: [alert.panel, panel, window], refs: ["PublishingDestinationsView.swift|private func askToRemove", "AppAlert.swift|final class AppAlert"], settle: 0.1,
                          extra: ["alertTitle": alert.title, "alertButtons": alert.buttons.map(\.title), "titleFont": fontInfo(alert.titleLabel.font) as Any, "messageFont": fontInfo(alert.messageLabel.font) as Any,
                                  "buttonFonts": alert.buttonViews.map { fontInfo($0.font) as Any }, "presentedAs": panel.attachedSheet === alert.panel ? "sheet on the Upload Destinations sheet" : "separate panel"])
                    alert.cancel(); pump(0.3)
                } else { gap("S26", "Remove destination alert", "no app-owned alert was on screen after Remove was pressed") }
            }
            closeHarnessSheet(panel)
        } catch { gap("S26", "Remove destination alert", "buildSettings threw: \(error.localizedDescription)") }
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
        shoot("S28", "focus-topbar-snap", surface: "keyboard focus", state: "Snap (primary) is first responder", crop: headerCrop(), refs: ["GlassChrome.swift|focusShape"], settle: 0.3)
        window.makeFirstResponder(app.zoomControl)
        shoot("S28", "focus-footer-zoom", surface: "keyboard focus", state: "Zoom popup is first responder", crop: footerCrop(), refs: ["ModernEditorChrome.swift|controls.zoomControl.isBordered"], settle: 0.3)
        if let format = firstView(of: NSPopUpButton.self, label: "Drag Me format") {
            window.makeFirstResponder(format)
            shoot("S28", "focus-footer-format", surface: "keyboard focus", state: "Format popup is first responder", crop: footerCrop(), refs: ["ModernEditorChrome.swift|let formatHolder"], settle: 0.3)
        }
        window.makeFirstResponder(chrome.shareButton)
        shoot("S28", "focus-footer-upload", surface: "keyboard focus", state: "Upload button is first responder", crop: footerCrop(), refs: ["ModernEditorChrome.swift|shareButton = CommandButton"], settle: 0.3)
        window.makeFirstResponder(canvas)
    }

    func s29() {
        // Help bevel (tool-tip overlay) -- off by default; force it on only inside this process.
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Extras")
        // The bevel only renders over the key window; a second launch can still be activating when this step starts.
        window.makeKeyAndOrderFront(nil)
        pump(0.4)
        app.helpBevel?.enabled = true
        let bands = OriginalHelpBevel.discoverBands(in: window)
        let hint = "Rectangle tool: drag to draw a rectangle. Hold Shift for a square."
        // The editor is at the top of the screen, so the plate goes inside the window: under the top bar for a top-bar control,
        // above the bottom bar for a bottom-bar control, and never over the title bar or the traffic lights.
        for (slug, control, point) in [("help-bevel", "top-bar control (Rectangle tool)", NSPoint(x: bands.header.midX, y: bands.header.midY)),
                                       ("help-bevel-bottom", "bottom-bar control (Wipe)", NSPoint(x: bands.footer.minX + 60, y: bands.footer.midY))] {
            app.helpBevel?.pointer = { point }
            app.helpBevel?.hover(owner: "audit-" + slug, message: hint)
            pump(1.2)
            let known = Set([window.windowNumber])
            let helpers = NSApp.windows.filter { !known.contains($0.windowNumber) && $0.isVisible && String(describing: type(of: $0)).contains("Help") }
            shoot("S29", slug, surface: "help bevel (tool-tip overlay)", state: "OriginalHelpBevel HUD with a hover hint for a \(control) (feature is off by default); editor at the top of the screen, so the plate sits inside the window, clear of the title bar and both bars", windows: helpers + [window], refs: ["OriginalHelpBevel.swift|final class OriginalHelpBevelView", "OriginalHelpBevel.swift|private func insideFrame"],
                  extra: ["helpWindowFound": !helpers.isEmpty, "plateFrame": NSStringFromRect(helpers.first?.frame ?? .zero), "titleBar": NSStringFromRect(bands.titleBar),
                          "header": NSStringFromRect(bands.header), "footer": NSStringFromRect(bands.footer)])
            app.helpBevel?.clear()
        }
        let known = Set([window.windowNumber])
        // With room above the editor the plate hangs from its top edge instead of sitting inside it.
        if let screen = window.screen ?? NSScreen.main {
            var frame = window.frame
            frame.origin.y = min(frame.origin.y, screen.visibleFrame.maxY - frame.height - 140)
            window.setFrame(frame, display: true)
            window.makeKeyAndOrderFront(nil)
            pump(0.4)
            app.helpBevel?.hover(owner: "audit", message: hint)
            pump(1.2)
            let hanging = NSApp.windows.filter { !known.contains($0.windowNumber) && $0.isVisible && String(describing: type(of: $0)).contains("Help") }
            shoot("S29", "help-bevel-hanging", surface: "help bevel (tool-tip overlay)", state: "the same hint with 140 pt free above the editor: the plate hangs from its top edge, behind it",
                  windows: hanging + [window], refs: ["OriginalHelpBevel.swift|private func layout"], extra: ["helpWindowFound": !hanging.isEmpty])
            app.helpBevel?.clear()
        }
        app.helpBevel?.enabled = false
        // Drag-out thumbnail panel with its hover overlay.
        let id = UUID()
        app.activeDragID = id
        app.iconifyDrag(id)
        pump(2.0)
        if let thumbnail = app.dragThumbnailWindow {
            shoot("S29", "drag-thumbnail", surface: "drag-out thumbnail", state: "Drag Me thumbnail panel after the editor shrinks (not hovering)", windows: [thumbnail], refs: ["App.swift|final class DragThumbnailView", "App.swift|func iconifyDrag"])
            if let view = thumbnail.contentView as? DragThumbnailView {
                view.clickToExpand = true
                shoot("S29", "drag-thumbnail-expand", surface: "drag-out thumbnail", state: "clickToExpand overlay", windows: [thumbnail], refs: ["App.swift|final class DragThumbnailView"])
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
            shoot("S13", "picker-\(label)", surface: "capture picker / crosshair + magnifier", state: "crosshair overlay with magnifier (lens \(image ? "fed synthetic pixels" : "hatched placeholder reading Screen Recording off, as without a grant")), no drag yet",
                  windows: [panel], refs: ["OriginalCapturePicker.swift|func begin(windowOnly", "OriginalCapturePicker.swift|func mountMagnifierIfEnabled"], settle: 0.4)
            let start = NSPoint(x: local.x - 240, y: local.y - 140), end = NSPoint(x: local.x + 260, y: local.y + 160)
            for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end)] {
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    if type == .leftMouseDown { selection.mouseDown(with: event) } else { selection.mouseDragged(with: event) }
                }
            }
            shoot("S13", "picker-\(label)-dragging", surface: "capture picker / crosshair + magnifier", state: "mid-drag selection rectangle with dimmed surround and the size read-out (lens \(image ? "synthetic" : "placeholder"))",
                  windows: [panel], refs: ["OriginalCapturePicker.swift|override func draw(_ dirtyRect"], settle: 0.4)
            picker.cancel()
            pump(0.4)
        }
        // Magnifier, lens and size label together at the screen's corners: both stay on screen with the gap between them.
        let edgePicker = OriginalCapturePicker(displayFrames: { [screen.frame] }, windowRecords: { [] }, screenImage: { _ in nil }, mouseLocation: { centre })
        edgePicker.begin(windowOnly: false) { _ in }
        pump(0.8)
        if let panel = edgePicker.panels.first, let selection = panel.contentView as? OriginalCaptureSelectionView {
            for (corner, point) in [("top-left", NSPoint(x: selection.bounds.minX + 6, y: selection.bounds.minY + 6)),
                                    ("bottom-right", NSPoint(x: selection.bounds.maxX - 6, y: selection.bounds.maxY - 6))] {
                if let move = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                    selection.mouseMoved(with: move)
                }
                shoot("S13", "picker-no-recording-grant-edge-\(corner)", surface: "capture picker / crosshair + magnifier", state: "magnifier with the pointer at the \(corner) corner of the display (placeholder lens): lens and size label both stay on screen, the label 4 pt below the lens border",
                      windows: [panel], refs: ["OriginalCaptureMagnifier.swift|static func labelRect", "OriginalCaptureMagnifier.swift|static func placementFrame"], settle: 0.4)
            }
        } else { gap("S13", "capture picker (screen edge)", "picker did not create an overlay panel") }
        edgePicker.cancel()
        pump(0.4)
        UserDefaults.standard.removeObject(forKey: OriginalCaptureMagnifierGeometry.defaultsKey)
    }

    func s14() {
        guard let screen = window.screen ?? NSScreen.main else { gap("S14", "countdown", "no screen"); return }
        var tick: (@MainActor @Sendable () -> Void)?
        // A plain run pins both options off. With --display the default seams run, so the capture shows what DisplayOptions.current drives.
        var seam: OriginalCaptureCountdown.Flag?
        if injectedDisplayOptions == nil { seam = { false } }
        let countdown = OriginalCaptureCountdown(scheduler: { _, action in tick = action; return { tick = nil } }, screenFrames: { [screen.visibleFrame] },
                                                 reduceMotion: seam, increaseContrast: seam, announce: { _ in })
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
        // Increase Contrast: the plate is darker (0.8 instead of 0.55). Reduce Motion: the panel is at full alpha from the first frame.
        var contrastTick: (@MainActor @Sendable () -> Void)?
        let contrast = OriginalCaptureCountdown(scheduler: { _, action in contrastTick = action; return { contrastTick = nil } }, screenFrames: { [screen.visibleFrame] },
                                                reduceMotion: { true }, increaseContrast: { true }, announce: { _ in })
        contrast.start(rect: rect, parent: nil, delay: OriginalCaptureTiming.originalDelay, cue: {}, completion: {})
        if let panel = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("Countdown") && $0.isVisible }) {
            shoot("S14", "countdown-3-contrast-reduce-motion", surface: "countdown overlay", state: "digit 3 with Increase Contrast (plate 0.8) and Reduce Motion (alpha 1 on the first frame)",
                  windows: [panel], refs: ["OriginalCaptureCountdown.swift|static func plateAlpha"], settle: 0.2, extra: ["panelAlpha": Double(panel.alphaValue)])
        } else { gap("S14", "countdown overlay (contrast)", "no countdown panel became visible") }
        contrast.cancel()
        for panel in NSApp.windows where String(describing: type(of: panel)).contains("Countdown") { panel.orderOut(nil) }
    }

    func s15() {
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Flash")
        let controller = OriginalCaptureFlashController(timerFactory: { _, _ in { } }, reduceMotion: { false }, showFlash: { true })
        controller.play(frame: window.frame, deflashDuration: 0.5)
        pump(0.3)
        guard let flash = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("Flash") }) else {
            gap("S15", "capture flash", "flash window not found"); controller.cancel(); return
        }
        flash.alphaValue = CGFloat(OriginalCaptureFlashTiming.peakAlpha)
        shoot("S15", "flash-peak", surface: "capture flash", state: "flash panel at its peak alpha (0.7) in front of the editor, editor behind it", windows: [flash, window], refs: ["OriginalCaptureFlash.swift|final class OriginalCaptureFlashWindow", "OriginalCaptureFlash.swift|final class OriginalCaptureFlashView"], settle: 0.3)
        flash.alphaValue = CGFloat(OriginalCaptureFlashTiming.peakAlpha) / 2
        shoot("S15", "flash-half", surface: "capture flash", state: "flash halfway up the ramp (0.35) in front of the editor", windows: [flash, window], refs: ["OriginalCaptureFlash.swift|static func alpha(elapsed"], settle: 0.3)
        controller.cancel()
    }
}
