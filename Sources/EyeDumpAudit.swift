import AppKit
import CoreGraphics
import Darwin

/// `--eye-dump-audit <outdir>`: audit-only evidence harness. For every surface it writes the app's own window as a PNG plus
/// a view-tree metrics file, an accessibility dump and the key-view loop, then quits. It captures only this process's own
/// windows (CGWindowList by window number); it never captures the screen. Extra flags:
///   --audit-appearance light|dark   --audit-surfaces S01,S02,...   (default: every surface)
///   --audit-icons sf|fa             --audit-sizes 980xmin,1024x740,...,full
/// Run it only through tools/eye-dump-audit.sh, which supplies the isolation this file refuses to run without.
extension AppDelegate {
    /// Every bundle id a harness copy may carry. The real ids (com.shoemoney.opensnap, and the retired product's) never match.
    static let auditBundlePrefix = HarnessGate.bundlePrefix

    /// The audit draws on the live canvas and quits clean, so it is ignored unless the process is fully isolated
    /// (`HarnessGate`: an isolated support folder, an isolated home, a throwaway bundle id and no document fixture).
    static func eyeDumpAuditDirectory(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment,
                                      bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> URL? {
        HarnessGate.auditDirectory(arguments: arguments, environment: environment, bundleIdentifier: bundleIdentifier)
    }

    func runEyeDumpAudit(to dir: URL) {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        let appearance = value("--audit-appearance") == "dark" ? "dark" : "light"
        let wanted = Set((value("--audit-surfaces") ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).uppercased() })
        let requestedIcons = value("--audit-icons") == "fa" ? "fa" : "sf"
        let sizes = (value("--audit-sizes") ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        let run = AuditRun(app: self, dir: dir, appearance: appearance, wanted: wanted, requestedIcons: requestedIcons, sizes: sizes)
        run.execute()
        dirty = false
        NSApp.terminate(nil)
    }
}

/// One audit process: one appearance, one icon mode, one set of surfaces, one fresh isolated support folder.
@MainActor
final class AuditRun {
    unowned let app: AppDelegate
    let dir: URL
    let appearance: String
    let wanted: Set<String>
    let requestedIcons: String
    let sizes: [String]
    var gaps: [[String: String]] = []
    var window: NSWindow { app.window }
    /// Swallows real keyboard and mouse input for the life of the run (`HarnessInputGuard`).
    var inputGuard: Any?

    init(app: AppDelegate, dir: URL, appearance: String, wanted: Set<String>, requestedIcons: String = "sf", sizes: [String] = []) {
        self.app = app; self.dir = dir; self.appearance = appearance; self.wanted = wanted
        self.requestedIcons = requestedIcons; self.sizes = sizes
        for sub in ["", "metrics", "ax", "meta", "layout"] {
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
    }

    func wants(_ id: String) -> Bool { wanted.isEmpty || wanted.contains(id) }

    /// What the chrome really resolved, not what was asked for: "fa" only when both bundled Font Awesome families are registered
    /// (the harness script removes the font files from its throwaway copy to force "sf").
    var iconMode: String { FontAwesomeFont.isAvailable(.regular) && FontAwesomeFont.isAvailable(.solid) ? "fa" : "sf" }
    var sourceSha: String { ProcessInfo.processInfo.environment["AUDIT_SOURCE_SHA"] ?? "unknown" }
    /// Display options the harness script asked this copy to simulate (nil on a normal system-state run). Gated by `HarnessGate`.
    var injectedDisplayOptions: DisplayOptions? { DisplayOptions.injection() }
    /// The options this run really resolved, and whether they were injected, for every manifest entry and layout JSON.
    var displayOptionsJSON: [String: Any] {
        let effective = DisplayOptions.current
        return ["injected": injectedDisplayOptions != nil, "active": effective.activeNames,
                "reduceTransparency": effective.reduceTransparency, "increaseContrast": effective.increaseContrast,
                "differentiateWithoutColor": effective.differentiateWithoutColor, "reduceMotion": effective.reduceMotion]
    }
    /// Script suffix plus one tag per injected display option (-rt, -ic, -dwc, -rm), so each option set has its own file stems.
    var stemSuffix: String { (ProcessInfo.processInfo.environment["AUDIT_STEM_SUFFIX"] ?? "") + (injectedDisplayOptions?.stemSuffix ?? "") }
    func pump(_ seconds: TimeInterval = 0.45) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
    func gap(_ id: String, _ surface: String, _ reason: String) {
        gaps.append(["id": id, "surface": surface, "appearance": appearance, "iconMode": iconMode, "reason": reason])
    }

    // MARK: image capture

    func grab(_ windows: [NSWindow]) -> (CGImage, String)? {
        let numbers = windows.map(\.windowNumber).filter { $0 > 0 }.map { CGWindowID($0) }
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        // A popover or tooltip plate sits above its window in the window server's own order, but a joint capture draws the window over
        // it and loses the overlap. Image each window on its own and stack them in the order given.
        let overlays = ["Popover", "ToolTip"]
        if windows.count > 1, windows.contains(where: { window in overlays.contains { String(describing: type(of: window)).contains($0) } }), let stacked = stackedImage(windows) {
            return (stacked, "CGWindowListCreateImage per window, stacked in order (\(windows.count) own windows; popover or tooltip above its window)")
        }
        var image: CGImage?
        if numbers.count == 1 {
            image = Self.windowImage(numbers[0], options)
        } else if numbers.count > 1 {
            let pointers = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: numbers.count)
            for (index, number) in numbers.enumerated() { pointers[index] = UnsafeRawPointer(bitPattern: UInt(number)) }
            if let array = CFArrayCreate(kCFAllocatorDefault, pointers, numbers.count, nil) {
                image = Self.windowImage(array, options)
            }
            pointers.deallocate()
        }
        if let image, image.width > 1, image.height > 1, !Self.isBlank(image) {
            return (image, numbers.count == 1 ? "CGWindowListCreateImage(bestResolution)" : "CGWindowListCreateImageFromArray(bestResolution, \(numbers.count) own windows)")
        }
        guard let first = windows.first, let view = first.contentView?.superview ?? first.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let cg = rep.cgImage else { return nil }
        return (cg, "cacheDisplay (CGWindowList image was blank)")
    }

    /// This process's own on-screen menu windows (window layer 101 and up), imaged by window number like every other capture and laid over
    /// `image` at their screen position. AppKit keeps open menus out of `NSApp.windows`, so this is the only way an open menu reaches a PNG.
    func compositeMenus(onto image: CGImage, union: CGRect, scale: CGFloat) -> (image: CGImage, count: Int)? {
        guard let primary = NSScreen.screens.first, scale > 0 else { return nil }
        let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        var parts: [(frame: CGRect, image: CGImage)] = []
        for info in infos where (info[kCGWindowOwnerPID as String] as? Int32) == getpid() && ((info[kCGWindowLayer as String] as? Int) ?? 0) >= 100 {
            guard let number = info[kCGWindowNumber as String] as? CGWindowID, let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let picture = Self.windowImage(number, [.boundsIgnoreFraming, .bestResolution]), picture.width > 1, !Self.isBlank(picture) else { continue }
            let topLeft = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            // CGWindowList is top-left from the primary display; AppKit frames are bottom-left.
            parts.append((CGRect(x: topLeft.minX, y: primary.frame.height - topLeft.maxY, width: topLeft.width, height: topLeft.height), picture))
        }
        guard !parts.isEmpty else { return nil }
        let bigger = parts.map(\.frame).reduce(union) { $0.union($1) }
        guard let context = CGContext(data: nil, width: Int((bigger.width * scale).rounded()), height: Int((bigger.height * scale).rounded()), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: (union.minX - bigger.minX) * scale, y: (union.minY - bigger.minY) * scale, width: CGFloat(image.width), height: CGFloat(image.height)))
        for part in parts {
            context.draw(part.image, in: CGRect(x: (part.frame.minX - bigger.minX) * scale, y: (part.frame.minY - bigger.minY) * scale,
                                                width: part.frame.width * scale, height: part.frame.height * scale))
        }
        return context.makeImage().map { ($0, parts.count) }
    }

    func stackedImage(_ windows: [NSWindow]) -> CGImage? {
        let options: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        var parts: [(frame: CGRect, image: CGImage)] = []
        for target in windows {
            guard target.windowNumber > 0, let image = Self.windowImage(CGWindowID(target.windowNumber), options), image.width > 1, image.height > 1 else { return nil }
            parts.append((target.frame, image))
        }
        let union = parts.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard let first = parts.first, first.frame.width > 0 else { return nil }
        let scale = CGFloat(first.image.width) / first.frame.width
        guard let context = CGContext(data: nil, width: Int((union.width * scale).rounded()), height: Int((union.height * scale).rounded()), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for part in parts {
            context.draw(part.image, in: CGRect(x: (part.frame.minX - union.minX) * scale, y: (part.frame.minY - union.minY) * scale,
                                                width: CGFloat(part.image.width), height: CGFloat(part.image.height)))
        }
        return context.makeImage()
    }

    // Since macOS 15 the SDK marks CGWindowListCreateImage unavailable, but the symbol is still in CoreGraphics and still images this
    // process's own windows without any capture grant. Looked up at run time so the harness keeps building against the macOS 26 SDK.
    private typealias WindowImageFn = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
    private typealias WindowArrayImageFn = @convention(c) (CGRect, CFArray, CGWindowImageOption) -> Unmanaged<CGImage>?
    static func windowImage(_ number: CGWindowID, _ options: CGWindowImageOption) -> CGImage? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: WindowImageFn.self)(.null, .optionIncludingWindow, number, options)?.takeRetainedValue()
    }
    static func windowImage(_ array: CFArray, _ options: CGWindowImageOption) -> CGImage? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImageFromArray") else { return nil }
        return unsafeBitCast(symbol, to: WindowArrayImageFn.self)(.null, array, options)?.takeRetainedValue()
    }

    static func isBlank(_ image: CGImage) -> Bool {
        let side = 24
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return false }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        for index in stride(from: 3, to: side * side * 4, by: 4) where bytes[index] > 4 { return false }
        return true
    }

    func opaqueFraction(_ image: CGImage) -> Double {
        let side = 48
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var opaque = 0
        for index in stride(from: 3, to: side * side * 4, by: 4) where bytes[index] > 250 { opaque += 1 }
        return Double(opaque) / Double(side * side)
    }

    /// `crop` is in points, top-left origin, relative to the first window's frame.
    @discardableResult
    func shoot(_ id: String, _ slug: String, surface: String, state: String, windows: [NSWindow]? = nil, crop: CGRect? = nil,
               refs: [String], settle: TimeInterval = 0.45, extra: [String: Any] = [:], includeMenus: Bool = false) -> String? {
        let targets = windows ?? [window]
        if targets.contains(where: { $0.windowNumber <= 0 }) { gap(id, surface + " / " + state, "the window has no window-server window number (not on screen), so it cannot be imaged"); return nil }
        pump(settle)
        for target in targets { target.contentView?.layoutSubtreeIfNeeded(); target.displayIfNeeded() }
        guard var (image, method) = grab(targets) else {
            gap(id, surface + " / " + state, "no image could be produced for the window (not on screen?)")
            return nil
        }
        let union = targets.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let scale = union.width > 0 ? CGFloat(image.width) / union.width : 1
        var menuCount = 0
        if includeMenus, let merged = compositeMenus(onto: image, union: union, scale: scale) {
            image = merged.image; menuCount = merged.count; method += " + \(merged.count) open menu window(s) of this process"
        }
        var pointSize = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        if let crop {
            let pixel = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
            if let cropped = image.cropping(to: pixel) {
                image = cropped; method += " + crop"
                pointSize = CGSize(width: CGFloat(cropped.width) / scale, height: CGFloat(cropped.height) / scale)
            }
        }
        let stem = stemFor(id, slug)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            gap(id, surface + " / " + state, "PNG encoding failed"); return nil
        }
        try? png.write(to: dir.appendingPathComponent(stem + ".png"))

        let windowsInfo = targets.map { windowMetrics($0) }
        write(["sourceSha": sourceSha, "id": id, "appearance": appearance, "iconMode": iconMode, "displayOptions": displayOptionsJSON, "windows": windowsInfo], to: "metrics/\(stem).json")
        write(["sourceSha": sourceSha, "id": id, "appearance": appearance, "iconMode": iconMode, "displayOptions": displayOptionsJSON, "windows": targets.map { accessibilityDump($0) }], to: "ax/\(stem).json")
        if targets.first === window, app.modernChrome != nil {
            var layout = chromeMetrics()
            for (key, item) in ["sourceSha": sourceSha, "id": id, "stem": stem, "appearance": appearance, "iconMode": iconMode, "displayOptions": displayOptionsJSON] as [String: Any] { layout[key] = item }
            write(layout, to: "layout/\(stem).json")
        }

        var meta: [String: Any] = [
            "id": id, "slug": slug, "surface": surface, "state": state, "appearance": appearance, "file": stem + ".png",
            "pixelSize": [image.width, image.height], "pointSize": [Double(pointSize.width.rounded()), Double(pointSize.height.rounded())],
            "scale": Double(scale), "method": method, "sourceRefs": refs,
            "windows": targets.map { ["title": $0.title, "class": String(describing: type(of: $0)), "frame": rectJSON($0.frame), "isKey": $0.isKeyWindow] },
            "sourceSha": sourceSha, "iconMode": iconMode, "displayOptions": displayOptionsJSON, "windowSize": [Double(window.frame.width.rounded()), Double(window.frame.height.rounded())],
            "windowAlpha": Double(targets.first?.alphaValue ?? 1), "appActive": NSApp.isActive, "opaqueFraction": opaqueFraction(image)
        ]
        if includeMenus { meta["menuWindowsComposited"] = menuCount }
        for (key, item) in extra { meta[key] = item }
        write(meta, to: "meta/\(stem).json")
        return stem
    }

    /// File stem shared by every artefact of one capture. Icon-mode runs write to separate folders, so the stem stays the same.
    func stemFor(_ id: String, _ slug: String) -> String { "\(id)-\(slug)-\(appearance)" + stemSuffix }

    func write(_ object: Any, to relative: String) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: dir.appendingPathComponent(relative))
    }

    func rectJSON(_ rect: CGRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height].map { Double($0).isFinite ? Double($0) : 0 } }

    // MARK: metrics

    func hex(_ color: NSColor?) -> String? {
        guard let color, let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X%02X", Int(rgb.redComponent * 255 + 0.5), Int(rgb.greenComponent * 255 + 0.5), Int(rgb.blueComponent * 255 + 0.5), Int(rgb.alphaComponent * 255 + 0.5))
    }

    func windowMetrics(_ target: NSWindow) -> [String: Any] {
        var counter = 0
        var tree: [String: Any] = [:]
        if let content = target.contentView?.superview ?? target.contentView {
            tree = viewNode(content, in: target, glass: 0, hiddenAbove: false, depth: 0, counter: &counter)
        }
        return ["title": target.title, "class": String(describing: type(of: target)), "frame": rectJSON(target.frame),
                "isKey": target.isKeyWindow, "appearance": target.effectiveAppearance.name.rawValue,
                "backingScaleFactor": Double(target.backingScaleFactor), "styleMask": Int(target.styleMask.rawValue),
                "firstResponder": target.firstResponder.map { String(describing: type(of: $0)) } ?? "none", "viewCount": counter, "views": tree]
    }

    func fontInfo(_ font: NSFont?) -> [String: Any]? {
        guard let font else { return nil }
        return ["name": font.fontName, "pointSize": Double(font.pointSize), "weight": Double(NSFontManager.shared.weight(of: font))]
    }

    func viewNode(_ view: NSView, in target: NSWindow, glass: Int, hiddenAbove: Bool, depth: Int, counter: inout Int) -> [String: Any] {
        counter += 1
        var glassDepth = glass
        var node: [String: Any] = ["class": String(describing: type(of: view))]
        if #available(macOS 26, *), let surface = view as? NSGlassEffectView {
            glassDepth += 1
            node["glass"] = ["cornerRadius": Double(surface.cornerRadius), "style": surface.style.rawValue, "tint": hex(surface.tintColor) as Any]
        }
        let inWindow = view.convert(view.bounds, to: nil)
        let top = target.frame.height - inWindow.maxY
        node["frame"] = rectJSON(CGRect(x: inWindow.minX, y: top, width: inWindow.width, height: inWindow.height))
        let hidden = hiddenAbove || view.isHidden || view.alphaValue <= 0.01
        node["hidden"] = view.isHidden
        node["effectivelyHidden"] = hidden
        node["alpha"] = Double(view.alphaValue)
        node["glassDepth"] = glassDepth
        if let identifier = view.identifier?.rawValue, !identifier.isEmpty { node["identifier"] = identifier }
        if let tip = view.toolTip, !tip.isEmpty { node["toolTip"] = tip }

        var font: NSFont?
        var text: String?
        if let control = view as? NSControl {
            font = control.font
            node["isEnabled"] = control.isEnabled
            if !(view is NSButton), !(view is NSPopUpButton) { text = control.stringValue }
        }
        if let button = view as? NSButton {
            node["state"] = button.state.rawValue
            node["buttonType"] = String(describing: button.bezelStyle.rawValue)
            let title = button.attributedTitle.length > 0 ? button.attributedTitle.string : button.title
            if !title.isEmpty { text = title }
            if let image = button.image { node["image"] = imageInfo(image) }
            if let alternate = button.alternateImage { node["alternateImage"] = imageInfo(alternate) }
            node["imagePosition"] = button.imagePosition.rawValue
            if let tint = button.contentTintColor { node["contentTint"] = hex(tint) as Any }
        }
        if let popup = view as? NSPopUpButton { text = popup.titleOfSelectedItem; node["menuItems"] = popup.itemTitles.count }
        if let field = view as? NSTextField {
            node["isEditable"] = field.isEditable
            if let placeholder = field.placeholderString { node["placeholder"] = placeholder }
            if field.stringValue.isEmpty, field.placeholderString != nil { text = nil }
            node["textColor"] = hex(field.textColor) as Any
        }
        if let editor = view as? NSTextView { font = editor.font; text = editor.string }
        if let segmented = view as? NSSegmentedControl {
            node["segments"] = (0..<segmented.segmentCount).map { segmented.label(forSegment: $0) ?? "" }
            if text == nil { text = (0..<segmented.segmentCount).compactMap { segmented.label(forSegment: $0) }.joined(separator: " | ") }
        }
        if let toggle = view as? SegmentedToggle {
            node["segments"] = toggle.titles
            node["selectedSegment"] = toggle.selectedSegment
            font = toggle.textFont(forSegment: toggle.selectedSegment)
            if text == nil { text = toggle.titles.joined(separator: " | ") }
        }
        if let imageView = view as? NSImageView, let image = imageView.image { node["image"] = imageInfo(image) }
        if let font = fontInfo(font) { node["font"] = font }
        if let text, !text.isEmpty { node["string"] = text }

        if view.isAccessibilityElement() { node["axElement"] = true }
        if let role = view.accessibilityRole() { node["axRole"] = role.rawValue }
        if let label = view.accessibilityLabel(), !label.isEmpty { node["axLabel"] = label }
        if let help = view.accessibilityHelp(), !help.isEmpty { node["axHelp"] = help }
        if let title = view.accessibilityTitle(), !title.isEmpty { node["axTitle"] = title }
        if let axValue = view.accessibilityValue() { node["axValue"] = String(describing: axValue) }

        if let layer = view.layer {
            var info: [String: Any] = ["cornerRadius": Double(layer.cornerRadius)]
            if let background = layer.backgroundColor, let color = NSColor(cgColor: background) { info["backgroundColor"] = hex(color) as Any }
            if layer.borderWidth > 0 { info["borderWidth"] = Double(layer.borderWidth) }
            node["layer"] = info
        }
        node["acceptsFirstResponder"] = view.acceptsFirstResponder
        node["canBecomeKeyView"] = view.canBecomeKeyView
        if view.focusRingType != .default { node["focusRingType"] = view.focusRingType.rawValue }
        if target.firstResponder === view { node["isFirstResponder"] = true }

        var children: [[String: Any]] = []
        for sub in view.subviews where depth < 40 && counter < 6000 {
            children.append(viewNode(sub, in: target, glass: glassDepth, hiddenAbove: hidden, depth: depth + 1, counter: &counter))
        }
        if !children.isEmpty { node["children"] = children }
        return node
    }

    func imageInfo(_ image: NSImage) -> [String: Any] {
        var info: [String: Any] = ["size": [Double(image.size.width), Double(image.size.height)], "isTemplate": image.isTemplate]
        if let name = image.name() { info["name"] = name }
        if let description = image.accessibilityDescription, !description.isEmpty { info["accessibilityDescription"] = description }
        return info
    }

    // MARK: accessibility

    func accessibilityDump(_ target: NSWindow) -> [String: Any] {
        var budget = 3000
        func node(_ element: Any, depth: Int) -> [String: Any] {
            budget -= 1
            var info: [String: Any] = ["class": String(describing: type(of: element as AnyObject))]
            if let item = element as? NSAccessibilityProtocol {
                if let role = item.accessibilityRole() { info["role"] = role.rawValue }
                if let subrole = item.accessibilitySubrole() { info["subrole"] = subrole.rawValue }
                if let label = item.accessibilityLabel(), !label.isEmpty { info["label"] = label }
                if let title = item.accessibilityTitle(), !title.isEmpty { info["title"] = title }
                if let help = item.accessibilityHelp(), !help.isEmpty { info["help"] = help }
                if let value = item.accessibilityValue() { info["value"] = String(describing: value) }
                if let identifier = item.accessibilityIdentifier(), !identifier.isEmpty { info["identifier"] = identifier }
                if item.isAccessibilityEnabled() == false { info["enabled"] = false }
                let frame = item.accessibilityFrame()
                if frame != .zero { info["frame"] = rectJSON(frame) }
                if depth < 40, budget > 0, let children = item.accessibilityChildren(), !children.isEmpty {
                    var out: [[String: Any]] = []
                    for child in children where budget > 0 { out.append(node(child, depth: depth + 1)) }
                    info["children"] = out
                }
            }
            return info
        }
        var order: [[String: Any]] = []
        var seen = Set<ObjectIdentifier>()
        var view: NSView? = target.initialFirstResponder ?? target.contentView
        if let start = view, !start.canBecomeKeyView { view = start.nextValidKeyView }
        while let current = view, order.count < 250, seen.insert(ObjectIdentifier(current)).inserted {
            let inWindow = current.convert(current.bounds, to: nil)
            order.append(["class": String(describing: type(of: current)), "label": current.accessibilityLabel() ?? (current as? NSControl)?.stringValue ?? "",
                          "frame": rectJSON(CGRect(x: inWindow.minX, y: target.frame.height - inWindow.maxY, width: inWindow.width, height: inWindow.height))])
            view = current.nextValidKeyView
        }
        return ["title": target.title, "tree": node(target, depth: 0), "keyViewLoop": order,
                "initialFirstResponder": target.initialFirstResponder.map { String(describing: type(of: $0)) } ?? "none"]
    }

    // MARK: environment and menus

    func writeEnvironment(preOverrideAppearance: String) {
        let workspace = NSWorkspace.shared
        func global(_ key: String) -> Any { UserDefaults.standard.object(forKey: key) ?? NSNull() }
        let screens = NSScreen.screens.map { screen -> [String: Any] in
            ["name": screen.localizedName, "frame": rectJSON(screen.frame), "visibleFrame": rectJSON(screen.visibleFrame),
             "backingScaleFactor": Double(screen.backingScaleFactor), "colorSpace": screen.colorSpace?.localizedName ?? "unknown"]
        }
        let environment: [String: Any] = [
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "macOSVersion": [ProcessInfo.processInfo.operatingSystemVersion.majorVersion, ProcessInfo.processInfo.operatingSystemVersion.minorVersion, ProcessInfo.processInfo.operatingSystemVersion.patchVersion],
            "screens": screens, "screenCount": NSScreen.screens.count,
            "mainWindowScreenScale": Double(window.screen?.backingScaleFactor ?? 0),
            "systemAppearanceBeforeOverride": preOverrideAppearance,
            "appearanceOverrideUsed": appearance == "dark" ? "NSAppearance.darkAqua (in-process NSApp.appearance only)" : "NSAppearance.aqua (in-process NSApp.appearance only)",
            "NSApp.effectiveAppearance": NSApp.effectiveAppearance.name.rawValue,
            "accessibilityDisplayShouldReduceTransparency": workspace.accessibilityDisplayShouldReduceTransparency,
            "accessibilityDisplayShouldIncreaseContrast": workspace.accessibilityDisplayShouldIncreaseContrast,
            "accessibilityDisplayShouldReduceMotion": workspace.accessibilityDisplayShouldReduceMotion,
            "accessibilityDisplayShouldDifferentiateWithoutColor": workspace.accessibilityDisplayShouldDifferentiateWithoutColor,
            "displayOptions": displayOptionsJSON,
            "isVoiceOverEnabled": workspace.isVoiceOverEnabled,
            "isSwitchControlEnabled": workspace.isSwitchControlEnabled,
            "fullKeyboardAccess_AppleKeyboardUIMode": global("AppleKeyboardUIMode"),
            "boldText": "not readable through a public API without changing nothing; recorded as a coverage gap",
            "appleInterfaceStyleGlobal": global("AppleInterfaceStyle"),
            "modernChromePresent": app.modernChrome != nil,
            "appIsActive": NSApp.isActive, "mainWindowIsKey": window.isKeyWindow,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "bare binary (no bundle)",
            "sourceSha": sourceSha, "iconMode": iconMode, "iconModeRequested": requestedIcons,
            "fontAwesomeRegular": FontAwesomeFont.isAvailable(.regular), "fontAwesomeSolid": FontAwesomeFont.isAvailable(.solid),
            "defaultWindowFrame": rectJSON(window.frame), "contentMinSize": [Double(window.contentMinSize.width), Double(window.contentMinSize.height)],
            "minSize": [Double(window.minSize.width), Double(window.minSize.height)]
        ]
        write(environment, to: "environment" + stemSuffix + ".json")
    }

    func menuNode(_ menu: NSMenu, depth: Int = 0) -> [String: Any] {
        menu.update()
        var node: [String: Any] = ["title": menu.title, "font": fontInfo(menu.font) as Any, "autoenablesItems": menu.autoenablesItems]
        node["items"] = menu.items.map { item -> [String: Any] in
            var info: [String: Any] = ["title": item.title, "separator": item.isSeparatorItem, "enabled": item.isEnabled, "hidden": item.isHidden,
                                       "hasImage": item.image != nil, "state": item.state.rawValue, "alternate": item.isAlternate, "tag": item.tag]
            if !item.keyEquivalent.isEmpty {
                var mask = ""
                if item.keyEquivalentModifierMask.contains(.control) { mask += "⌃" }
                if item.keyEquivalentModifierMask.contains(.option) { mask += "⌥" }
                if item.keyEquivalentModifierMask.contains(.shift) || item.keyEquivalent != item.keyEquivalent.lowercased() { mask += "⇧" }
                if item.keyEquivalentModifierMask.contains(.command) { mask += "⌘" }
                info["keyEquivalent"] = mask + item.keyEquivalent.uppercased()
            }
            if let image = item.image { info["image"] = imageInfo(image) }
            if let action = item.action { info["action"] = NSStringFromSelector(action) }
            if let tip = item.toolTip { info["toolTip"] = tip }
            if let attributed = item.attributedTitle { info["attributedTitleFont"] = fontInfo(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as Any }
            if item.indentationLevel > 0 { info["indentation"] = item.indentationLevel }
            if let sub = item.submenu, depth < 6 { info["submenu"] = menuNode(sub, depth: depth + 1) }
            return info
        }
        return node
    }
}
