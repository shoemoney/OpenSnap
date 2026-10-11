import AppKit

// Font Awesome Free 7.3.1 by @fontawesome - https://fontawesome.com
// License - https://fontawesome.com/license/free (Icons: CC BY 4.0, Fonts: SIL OFL 1.1, Code: MIT License)
// Copyright 2026 Fonticons, Inc.
//
// The path strings in `FontAwesomeFree.entries` are the `d` attributes of the official @fortawesome/fontawesome-free
// 7.3.1 SVGs (svgs/<style>/<name>.svg), copied verbatim and checked against the package's metadata. They are compiled in
// as vector data: no font file and no Font Awesome Pro asset is involved. The only change made to an icon is a
// rotation applied at draw time (see `FAIcon.freeSource`). The notice shipped in the app is THIRD_PARTY_NOTICES.md.

/// Embedded Font Awesome Free vectors: the release icon family, between the optional Pro glyphs and the SF Symbol fallback.
@MainActor
enum FontAwesomeFree {
    static let version = "7.3.1"
    static let licenseURL = "https://fontawesome.com/license/free"

    enum Style: String { case regular, solid }

    struct Entry {
        let style: Style, name: String, viewBoxWidth: CGFloat, pathData: String
        init(_ style: Style, _ name: String, _ viewBoxWidth: CGFloat, _ pathData: String) {
            self.style = style; self.name = name; self.viewBoxWidth = viewBoxWidth; self.pathData = pathData
        }
    }

    /// One resolved icon: the SVG path in viewBox coordinates (y down), already rotated when the source asks for it.
    struct Glyph {
        let name: String, style: Style, viewBox: CGSize, path: CGPath
        var bounds: CGRect { path.boundingBoxOfPath }
    }

    /// Every Free viewBox is `0 0 <width> 512`; 512 units equal one em, so a glyph's size tracks the Pro font at the same point size.
    static let viewBoxHeight: CGFloat = 512

    static func glyph(for icon: FAIcon, family: FAFamily = .regular) -> Glyph? {
        let source = icon.freeSource
        let wanted: Style = family == .regular && source.hasRegular ? .regular : .solid
        return glyph(named: source.name, style: wanted, rotation: source.rotation)
    }

    static func glyph(named name: String, style: Style, rotation: CGFloat = 0) -> Glyph? {
        let key = "\(style.rawValue)/\(name)/\(rotation)"
        if let cached = cache[key] { return cached }
        guard let entry = entries.first(where: { $0.name == name && $0.style == style }),
              var path = try? makePath(entry.pathData) else { return nil }
        let viewBox = CGSize(width: entry.viewBoxWidth, height: viewBoxHeight)
        if rotation != 0 {
            var transform = CGAffineTransform(translationX: viewBox.width / 2, y: viewBox.height / 2)
                .rotated(by: rotation * .pi / 180)
                .translatedBy(x: -viewBox.width / 2, y: -viewBox.height / 2)
            if let rotated = path.copy(using: &transform) { path = rotated }
        }
        let glyph = Glyph(name: name, style: style, viewBox: viewBox, path: path)
        cache[key] = glyph
        return glyph
    }

    private static var cache: [String: Glyph] = [:]

    /// Template image on a square canvas of ceil(pointSize * 1.25), the same canvas the Pro font renders on. The glyph keeps
    /// its viewBox aspect at pointSize / 512 per unit and is centred on its own outline. A drawing handler (not a bitmap)
    /// keeps it crisp at 1x and 2x.
    static func image(_ glyph: Glyph, pointSize: CGFloat) -> NSImage? {
        guard pointSize > 0 else { return nil }
        let bounds = glyph.bounds
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        let side = ceil(pointSize * 1.25)
        let scale = min(pointSize / viewBoxHeight, side / bounds.width, side / bounds.height)
        let box = PathBox(path: glyph.path)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: side / 2, y: side / 2)
            context.scaleBy(x: scale, y: -scale)
            context.translateBy(x: -bounds.midX, y: -bounds.midY)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(box.path)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }

    private struct PathBox: @unchecked Sendable { let path: CGPath }

    /// SVGPathParser keeps arcs as arcs; Free uses them for rounded corners, so they become cubic segments here.
    static func makePath(_ data: String) throws -> CGPath {
        let path = CGMutablePath()
        var current = CGPoint.zero
        for command in try SVGPathParser.parse(data) {
            switch command {
            case .move(let p): path.move(to: p); current = p
            case .line(let p): path.addLine(to: p); current = p
            case .cubic(let c1, let c2, let p): path.addCurve(to: p, control1: c1, control2: c2); current = p
            case .quadratic(let c, let p): path.addQuadCurve(to: p, control: c); current = p
            case .arc(let rx, let ry, let rotation, let large, let sweep, let p):
                for curve in arcCurves(from: current, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep, to: p) {
                    path.addCurve(to: curve.end, control1: curve.c1, control2: curve.c2)
                }
                current = p
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    /// SVG implementation notes F.6.5: endpoint to centre parameterisation, then one cubic per quarter turn at most.
    private static func arcCurves(from p0: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool,
                                  to p1: CGPoint) -> [(c1: CGPoint, c2: CGPoint, end: CGPoint)] {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard p0 != p1 else { return [] }
        guard rx > 0, ry > 0 else { return [(p0, p1, p1)] }
        let phi = rotation * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : (max(0, numerator / denominator)).squareRoot()
        if large == sweep { factor = -factor }
        let cxp = factor * rx * y1 / ry, cyp = -factor * ry * x1 / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2, cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let start = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi } else if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2) - 1e-9)))
        let step = delta / CGFloat(segments), k = 4 / 3 * tan(step / 4)
        func point(_ t: CGFloat) -> CGPoint {
            let x = rx * cos(t), y = ry * sin(t)
            return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            let x = -rx * sin(t), y = ry * cos(t)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }
        var curves: [(c1: CGPoint, c2: CGPoint, end: CGPoint)] = []
        for index in 0..<segments {
            let a = start + step * CGFloat(index), b = a + step
            let pa = point(a), pb = index == segments - 1 ? p1 : point(b), da = derivative(a), db = derivative(b)
            curves.append((CGPoint(x: pa.x + k * da.x, y: pa.y + k * da.y), CGPoint(x: pb.x - k * db.x, y: pb.y - k * db.y), pb))
        }
        return curves
    }

    /// Embedded path data. Keep this the only place Free path strings live: IconCoverageTests audits it by name.
    static let entries: [Entry] = [
        Entry(.solid, "eye-slash", 576, "M41-24.9c-9.4-9.4-24.6-9.4-33.9 0S-2.3-.3 7 9.1l528 528c9.4 9.4 24.6 9.4 33.9 0s9.4-24.6 0-33.9l-96.4-96.4c2.7-2.4 5.4-4.8 8-7.2 46.8-43.5 78.1-95.4 93-131.1 3.3-7.9 3.3-16.7 0-24.6-14.9-35.7-46.2-87.7-93-131.1-47.1-43.7-111.8-80.6-192.6-80.6-56.8 0-105.6 18.2-146 44.2L41-24.9zM204.5 138.7c23.5-16.8 52.4-26.7 83.5-26.7 79.5 0 144 64.5 144 144 0 31.1-9.9 59.9-26.7 83.5l-34.7-34.7c12.7-21.4 17-47.7 10.1-73.7-13.7-51.2-66.4-81.6-117.6-67.9-8.6 2.3-16.7 5.7-24 10l-34.7-34.7zM325.3 395.1c-11.9 3.2-24.4 4.9-37.3 4.9-79.5 0-144-64.5-144-144 0-12.9 1.7-25.4 4.9-37.3L69.4 139.2c-32.6 36.8-55 75.8-66.9 104.5-3.3 7.9-3.3 16.7 0 24.6 14.9 35.7 46.2 87.7 93 131.1 47.1 43.7 111.8 80.6 192.6 80.6 37.3 0 71.2-7.9 101.5-20.6l-64.2-64.2z"),
        Entry(.solid, "toolbox", 512, "M176 56l0 40 160 0 0-40c0-4.4-3.6-8-8-8L184 48c-4.4 0-8 3.6-8 8zM128 96l0-40c0-30.9 25.1-56 56-56L328 0c30.9 0 56 25.1 56 56l0 40 28.1 0c12.7 0 24.9 5.1 33.9 14.1l51.9 51.9c9 9 14.1 21.2 14.1 33.9l0 76.1-136 0 0-16c0-13.3-10.7-24-24-24s-24 10.7-24 24l0 16-144 0 0-16c0-13.3-10.7-24-24-24s-24 10.7-24 24l0 16-136 0 0-76.1c0-12.7 5.1-24.9 14.1-33.9l51.9-51.9c9-9 21.2-14.1 33.9-14.1L128 96zM0 416l0-96 136 0 0 16c0 13.3 10.7 24 24 24s24-10.7 24-24l0-16 144 0 0 16c0 13.3 10.7 24 24 24s24-10.7 24-24l0-16 136 0 0 96c0 35.3-28.7 64-64 64L64 480c-35.3 0-64-28.7-64-64z"),
        Entry(.solid, "images", 576, "M96 96c0-35.3 28.7-64 64-64l320 0c35.3 0 64 28.7 64 64l0 256c0 35.3-28.7 64-64 64l-320 0c-35.3 0-64-28.7-64-64L96 96zM24 128c13.3 0 24 10.7 24 24l0 296c0 8.8 7.2 16 16 16l360 0c13.3 0 24 10.7 24 24s-10.7 24-24 24L64 512c-35.3 0-64-28.7-64-64L0 152c0-13.3 10.7-24 24-24zm168 32a32 32 0 1 0 0-64 32 32 0 1 0 0 64zm196.5 11.5c-4.4-7.1-12.1-11.5-20.5-11.5s-16.1 4.4-20.5 11.5l-56.3 92.1-24.5-30.6c-4.6-5.7-11.4-9-18.7-9s-14.2 3.3-18.7 9l-64 80c-5.8 7.2-6.9 17.1-2.9 25.4S174.8 352 184 352l272 0c8.7 0 16.7-4.7 20.9-12.3s4.1-16.8-.5-24.3l-88-144z"),
        Entry(.solid, "box-archive", 512, "M0 64C0 46.3 14.3 32 32 32l448 0c17.7 0 32 14.3 32 32l0 32c0 17.7-14.3 32-32 32L32 128C14.3 128 0 113.7 0 96L0 64zM32 176l448 0 0 240c0 35.3-28.7 64-64 64L96 480c-35.3 0-64-28.7-64-64l0-240zm152 64c-13.3 0-24 10.7-24 24s10.7 24 24 24l144 0c13.3 0 24-10.7 24-24s-10.7-24-24-24l-144 0z"),
        Entry(.solid, "clock-rotate-left", 576, "M288 64c106 0 192 86 192 192S394 448 288 448c-65.2 0-122.9-32.5-157.6-82.3-10.1-14.5-30.1-18-44.6-7.9s-18 30.1-7.9 44.6C124.1 468.6 201 512 288 512 429.4 512 544 397.4 544 256S429.4 0 288 0C202.3 0 126.5 42.1 80 106.7L80 80c0-17.7-14.3-32-32-32S16 62.3 16 80l0 112c0 17.7 14.3 32 32 32l24.6 0c.5 0 1 0 1.5 0l86 0c17.7 0 32-14.3 32-32s-14.3-32-32-32l-38.3 0C154.9 102.6 217 64 288 64zm24 88c0-13.3-10.7-24-24-24s-24 10.7-24 24l0 104c0 6.4 2.5 12.5 7 17l72 72c9.4 9.4 24.6 9.4 33.9 0s9.4-24.6 0-33.9l-65-65 0-94.1z"),
        Entry(.solid, "arrow-pointer", 448, "M77.3 2.5c8.1-4.1 17.9-3.2 25.1 2.3l320 239.9c8.3 6.2 11.6 17 8.4 26.8s-12.4 16.4-22.8 16.4l-152.3 0 88.9 177.7c7.9 15.8 1.5 35-14.3 42.9s-35 1.5-42.9-14.3l-88.9-177.7-91.3 121.8c-6.2 8.3-17 11.6-26.8 8.4S64 434.3 64 424L64 24c0-9.1 5.1-17.4 13.3-21.5z"),
        Entry(.solid, "paintbrush", 576, "M480.5 10.3L259.1 158c-29.1 19.4-47.6 50.9-50.6 85.3 62.3 12.8 111.4 61.9 124.3 124.3 34.5-3 65.9-21.5 85.3-50.6L565.7 95.5c6.7-10.1 10.3-21.9 10.3-34.1 0-33.9-27.5-61.4-61.4-61.4-12.1 0-24 3.6-34.1 10.3zM288 400c0-61.9-50.1-112-112-112S64 338.1 64 400c0 3.9 .2 7.8 .6 11.6 1.8 17.5-10.2 36.4-27.8 36.4L32 448c-17.7 0-32 14.3-32 32s14.3 32 32 32l144 0c61.9 0 112-50.1 112-112z"),
        Entry(.solid, "minus", 448, "M0 256c0-17.7 14.3-32 32-32l384 0c17.7 0 32 14.3 32 32s-14.3 32-32 32L32 288c-17.7 0-32-14.3-32-32z"),
        Entry(.regular, "circle", 512, "M464 256a208 208 0 1 0 -416 0 208 208 0 1 0 416 0zM0 256a256 256 0 1 1 512 0 256 256 0 1 1 -512 0z"),
        Entry(.solid, "circle", 512, "M0 256a256 256 0 1 1 512 0 256 256 0 1 1 -512 0z"),
        Entry(.regular, "square", 448, "M384 80c8.8 0 16 7.2 16 16l0 320c0 8.8-7.2 16-16 16L64 432c-8.8 0-16-7.2-16-16L48 96c0-8.8 7.2-16 16-16l320 0zM64 32C28.7 32 0 60.7 0 96L0 416c0 35.3 28.7 64 64 64l320 0c35.3 0 64-28.7 64-64l0-320c0-35.3-28.7-64-64-64L64 32z"),
        Entry(.solid, "square", 448, "M64 32l320 0c35.3 0 64 28.7 64 64l0 320c0 35.3-28.7 64-64 64L64 480c-35.3 0-64-28.7-64-64L0 96C0 60.7 28.7 32 64 32z"),
        Entry(.solid, "fill-drip", 576, "M309.7 71.6l-64.4 64.4 33.4 33.4c12.5 12.5 12.5 32.8 0 45.3s-32.8 12.5-45.3 0l-33.4-33.4-96.4 96.4c-2.9 2.9-5.1 6.5-6.3 10.3l321.5 0 53.7-53.7c4.9-4.9 7.6-11.5 7.6-18.3s-2.7-13.5-7.6-18.3L346.3 71.6C341.5 66.7 334.9 64 328 64s-13.5 2.7-18.3 7.6zM58.3 232.4l96.4-96.4-49.4-49.4c-12.5-12.5-12.5-32.8 0-45.3s32.8-12.5 45.3 0L200 90.7 264.4 26.3C281.3 9.5 304.1 0 328 0s46.7 9.5 63.6 26.3L517.7 152.4C534.5 169.3 544 192.1 544 216s-9.5 46.7-26.3 63.6L311.6 485.7C294.7 502.5 271.9 512 248 512s-46.7-9.5-63.6-26.3L58.3 359.6C41.5 342.7 32 319.9 32 296s9.5-46.7 26.3-63.6zM512 544c-35.3 0-64-28.7-64-64 0-25.2 32.6-79.6 51.2-108.7 6-9.4 19.5-9.4 25.5 0 18.7 29.1 51.2 83.5 51.2 108.7 0 35.3-28.7 64-64 64z"),
        Entry(.solid, "eraser", 576, "M178.5 416l123 0 65.3-65.3-173.5-173.5-126.7 126.7 112 112zM224 480l-45.5 0c-17 0-33.3-6.7-45.3-18.7L17 345C6.1 334.1 0 319.4 0 304s6.1-30.1 17-41L263 17C273.9 6.1 288.6 0 304 0s30.1 6.1 41 17L527 199c10.9 10.9 17 25.6 17 41s-6.1 30.1-17 41l-135 135 120 0c17.7 0 32 14.3 32 32s-14.3 32-32 32l-288 0z"),
        Entry(.solid, "t", 384, "M32 32C14.3 32 0 46.3 0 64S14.3 96 32 96l128 0 0 352c0 17.7 14.3 32 32 32s32-14.3 32-32l0-352 128 0c17.7 0 32-14.3 32-32s-14.3-32-32-32L32 32z"),
        Entry(.solid, "arrow-right", 512, "M502.6 278.6c12.5-12.5 12.5-32.8 0-45.3l-160-160c-12.5-12.5-32.8-12.5-45.3 0s-12.5 32.8 0 45.3L402.7 224 32 224c-17.7 0-32 14.3-32 32s14.3 32 32 32l370.7 0-105.4 105.4c-12.5 12.5-12.5 32.8 0 45.3s32.8 12.5 45.3 0l160-160z"),
        Entry(.solid, "crop-simple", 512, "M128 32c0-17.7-14.3-32-32-32S64 14.3 64 32l0 32-32 0C14.3 64 0 78.3 0 96s14.3 32 32 32l32 0 0 256c0 35.3 28.7 64 64 64l208 0 0-64-208 0 0-352zM384 480c0 17.7 14.3 32 32 32s32-14.3 32-32l0-32 32 0c17.7 0 32-14.3 32-32s-14.3-32-32-32l-32 0 0-256c0-35.3-28.7-64-64-64l-208 0 0 64 208 0 0 352z"),
        Entry(.solid, "crosshairs", 576, "M288-16c17.7 0 32 14.3 32 32l0 18.3c98.1 14 175.7 91.6 189.7 189.7l18.3 0c17.7 0 32 14.3 32 32s-14.3 32-32 32l-18.3 0c-14 98.1-91.6 175.7-189.7 189.7l0 18.3c0 17.7-14.3 32-32 32s-32-14.3-32-32l0-18.3C157.9 463.7 80.3 386.1 66.3 288L48 288c-17.7 0-32-14.3-32-32s14.3-32 32-32l18.3 0C80.3 125.9 157.9 48.3 256 34.3L256 16c0-17.7 14.3-32 32-32zM131.2 288c12.7 62.7 62.1 112.1 124.8 124.8l0-12.8c0-17.7 14.3-32 32-32s32 14.3 32 32l0 12.8c62.7-12.7 112.1-62.1 124.8-124.8L432 288c-17.7 0-32-14.3-32-32s14.3-32 32-32l12.8 0C432.1 161.3 382.7 111.9 320 99.2l0 12.8c0 17.7-14.3 32-32 32s-32-14.3-32-32l0-12.8C193.3 111.9 143.9 161.3 131.2 224l12.8 0c17.7 0 32 14.3 32 32s-14.3 32-32 32l-12.8 0zM288 208a48 48 0 1 1 0 96 48 48 0 1 1 0-96z"),
        Entry(.solid, "expand", 448, "M32 32C14.3 32 0 46.3 0 64l0 96c0 17.7 14.3 32 32 32s32-14.3 32-32l0-64 64 0c17.7 0 32-14.3 32-32s-14.3-32-32-32L32 32zM64 352c0-17.7-14.3-32-32-32S0 334.3 0 352l0 96c0 17.7 14.3 32 32 32l96 0c17.7 0 32-14.3 32-32s-14.3-32-32-32l-64 0 0-64zM320 32c-17.7 0-32 14.3-32 32s14.3 32 32 32l64 0 0 64c0 17.7 14.3 32 32 32s32-14.3 32-32l0-96c0-17.7-14.3-32-32-32l-96 0zM448 352c0-17.7-14.3-32-32-32s-32 14.3-32 32l0 64-64 0c-17.7 0-32 14.3-32 32s14.3 32 32 32l96 0c17.7 0 32-14.3 32-32l0-96z"),
        Entry(.solid, "xmark", 384, "M55.1 73.4c-12.5-12.5-32.8-12.5-45.3 0s-12.5 32.8 0 45.3L147.2 256 9.9 393.4c-12.5 12.5-12.5 32.8 0 45.3s32.8 12.5 45.3 0L192.5 301.3 329.9 438.6c12.5 12.5 32.8 12.5 45.3 0s12.5-32.8 0-45.3L237.8 256 375.1 118.6c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0L192.5 210.7 55.1 73.4z"),
        Entry(.solid, "font", 512, "M285.1 50.7C279.9 39.3 268.5 32 256 32s-23.9 7.3-29.1 18.7L59.5 416 48 416c-17.7 0-32 14.3-32 32s14.3 32 32 32l88 0c17.7 0 32-14.3 32-32s-14.3-32-32-32l-6.1 0 22-48 208.3 0 22 48-6.1 0c-17.7 0-32 14.3-32 32s14.3 32 32 32l88 0c17.7 0 32-14.3 32-32s-14.3-32-32-32l-11.5 0-167.4-365.3zM330.8 304L181.2 304 256 140.8 330.8 304z"),
        Entry(.solid, "arrow-rotate-left", 512, "M256 64c-56.8 0-107.9 24.7-143.1 64l47.1 0c17.7 0 32 14.3 32 32s-14.3 32-32 32L32 192c-17.7 0-32-14.3-32-32L0 32C0 14.3 14.3 0 32 0S64 14.3 64 32l0 54.7C110.9 33.6 179.5 0 256 0 397.4 0 512 114.6 512 256S397.4 512 256 512c-87 0-163.9-43.4-210.1-109.7-10.1-14.5-6.6-34.4 7.9-44.6s34.4-6.6 44.6 7.9c34.8 49.8 92.4 82.3 157.6 82.3 106 0 192-86 192-192S362 64 256 64z"),
        Entry(.solid, "broom", 576, "M566.6 54.6c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0l-192 192-34.7-34.7c-4.2-4.2-10-6.6-16-6.6-12.5 0-22.6 10.1-22.6 22.6l0 29.1 108.3 108.3 29.1 0c12.5 0 22.6-10.1 22.6-22.6 0-6-2.4-11.8-6.6-16l-34.7-34.7 192-192zM341.1 353.4L222.6 234.9c-42.7-3.7-85.2 11.7-115.8 42.3l-8 8c-22.3 22.3-34.8 52.5-34.8 84 0 6.8 7.1 11.2 13.2 8.2l51.1-25.5c5-2.5 9.5 4.1 5.4 7.9L7.3 473.4C2.7 477.6 0 483.6 0 489.9 0 502.1 9.9 512 22.1 512l173.3 0c38.8 0 75.9-15.4 103.4-42.8 30.6-30.6 45.9-73.1 42.3-115.8z"),
        Entry(.solid, "cloud-arrow-up", 576, "M144 480c-79.5 0-144-64.5-144-144 0-63.4 41-117.2 97.9-136.5-1.3-7.7-1.9-15.5-1.9-23.5 0-79.5 64.5-144 144-144 55.4 0 103.5 31.3 127.6 77.1 14.2-8.3 30.8-13.1 48.4-13.1 53 0 96 43 96 96 0 15.7-3.8 30.6-10.5 43.7 44 20.3 74.5 64.7 74.5 116.3 0 70.7-57.3 128-128 128l-304 0zM305 191c-9.4-9.4-24.6-9.4-33.9 0l-72 72c-9.4 9.4-9.4 24.6 0 33.9s24.6 9.4 33.9 0l31-31 0 102.1c0 13.3 10.7 24 24 24s24-10.7 24-24l0-102.1 31 31c9.4 9.4 24.6 9.4 33.9 0s9.4-24.6 0-33.9l-72-72z"),
        Entry(.solid, "hand", 512, "M288 32c0-17.7-14.3-32-32-32s-32 14.3-32 32l0 208c0 8.8-7.2 16-16 16s-16-7.2-16-16l0-176c0-17.7-14.3-32-32-32s-32 14.3-32 32l0 272c0 1.5 0 3.1 .1 4.6L67.6 283c-16-15.2-41.3-14.6-56.6 1.4S-3.6 325.7 12.4 341L124.8 448c43.1 41.1 100.4 64 160 64l19.2 0c97.2 0 176-78.8 176-176l0-208c0-17.7-14.3-32-32-32s-32 14.3-32 32l0 112c0 8.8-7.2 16-16 16s-16-7.2-16-16l0-176c0-17.7-14.3-32-32-32s-32 14.3-32 32l0 176c0 8.8-7.2 16-16 16s-16-7.2-16-16l0-208z"),
        Entry(.solid, "check", 448, "M434.8 70.1c14.3 10.4 17.5 30.4 7.1 44.7l-256 352c-5.5 7.6-14 12.3-23.4 13.1s-18.5-2.7-25.1-9.3l-128-128c-12.5-12.5-12.5-32.8 0-45.3s32.8-12.5 45.3 0l101.5 101.5 234-321.7c10.4-14.3 30.4-17.5 44.7-7.1z"),
        Entry(.solid, "circle-xmark", 512, "M256 512a256 256 0 1 0 0-512 256 256 0 1 0 0 512zM167 167c9.4-9.4 24.6-9.4 33.9 0l55 55 55-55c9.4-9.4 24.6-9.4 33.9 0s9.4 24.6 0 33.9l-55 55 55 55c9.4 9.4 9.4 24.6 0 33.9s-24.6 9.4-33.9 0l-55-55-55 55c-9.4 9.4-24.6 9.4-33.9 0s-9.4-24.6 0-33.9l55-55-55-55c-9.4-9.4-9.4-24.6 0-33.9z"),
        Entry(.solid, "up-right-from-square", 512, "M290.4 19.8C295.4 7.8 307.1 0 320 0L480 0c17.7 0 32 14.3 32 32l0 160c0 12.9-7.8 24.6-19.8 29.6s-25.7 2.2-34.9-6.9L400 157.3 246.6 310.6c-12.5 12.5-32.8 12.5-45.3 0s-12.5-32.8 0-45.3L354.7 112 297.4 54.6c-9.2-9.2-11.9-22.9-6.9-34.9zM0 176c0-44.2 35.8-80 80-80l80 0c17.7 0 32 14.3 32 32s-14.3 32-32 32l-80 0c-8.8 0-16 7.2-16 16l0 256c0 8.8 7.2 16 16 16l256 0c8.8 0 16-7.2 16-16l0-80c0-17.7 14.3-32 32-32s32 14.3 32 32l0 80c0 44.2-35.8 80-80 80L80 512c-44.2 0-80-35.8-80-80L0 176z"),
        Entry(.solid, "copy", 448, "M192 0c-35.3 0-64 28.7-64 64l0 256c0 35.3 28.7 64 64 64l192 0c35.3 0 64-28.7 64-64l0-200.6c0-17.4-7.1-34.1-19.7-46.2L370.6 17.8C358.7 6.4 342.8 0 326.3 0L192 0zM64 128c-35.3 0-64 28.7-64 64L0 448c0 35.3 28.7 64 64 64l192 0c35.3 0 64-28.7 64-64l0-16-64 0 0 16-192 0 0-256 16 0 0-64-16 0z"),
        Entry(.solid, "link", 576, "M419.5 96c-16.6 0-32.7 4.5-46.8 12.7-15.8-16-34.2-29.4-54.5-39.5 28.2-24 64.1-37.2 101.3-37.2 86.4 0 156.5 70 156.5 156.5 0 41.5-16.5 81.3-45.8 110.6l-71.1 71.1c-29.3 29.3-69.1 45.8-110.6 45.8-86.4 0-156.5-70-156.5-156.5 0-1.5 0-3 .1-4.5 .5-17.7 15.2-31.6 32.9-31.1s31.6 15.2 31.1 32.9c0 .9 0 1.8 0 2.6 0 51.1 41.4 92.5 92.5 92.5 24.5 0 48-9.7 65.4-27.1l71.1-71.1c17.3-17.3 27.1-40.9 27.1-65.4 0-51.1-41.4-92.5-92.5-92.5zM275.2 173.3c-1.9-.8-3.8-1.9-5.5-3.1-12.6-6.5-27-10.2-42.1-10.2-24.5 0-48 9.7-65.4 27.1L91.1 258.2c-17.3 17.3-27.1 40.9-27.1 65.4 0 51.1 41.4 92.5 92.5 92.5 16.5 0 32.6-4.4 46.7-12.6 15.8 16 34.2 29.4 54.6 39.5-28.2 23.9-64 37.2-101.3 37.2-86.4 0-156.5-70-156.5-156.5 0-41.5 16.5-81.3 45.8-110.6l71.1-71.1c29.3-29.3 69.1-45.8 110.6-45.8 86.6 0 156.5 70.6 156.5 156.9 0 1.3 0 2.6 0 3.9-.4 17.7-15.1 31.6-32.8 31.2s-31.6-15.1-31.2-32.8c0-.8 0-1.5 0-2.3 0-33.7-18-63.3-44.8-79.6z"),
        Entry(.solid, "globe", 512, "M351.9 280l-190.9 0c2.9 64.5 17.2 123.9 37.5 167.4 11.4 24.5 23.7 41.8 35.1 52.4 11.2 10.5 18.9 12.2 22.9 12.2s11.7-1.7 22.9-12.2c11.4-10.6 23.7-28 35.1-52.4 20.3-43.5 34.6-102.9 37.5-167.4zM160.9 232l190.9 0C349 167.5 334.7 108.1 314.4 64.6 303 40.2 290.7 22.8 279.3 12.2 268.1 1.7 260.4 0 256.4 0s-11.7 1.7-22.9 12.2c-11.4 10.6-23.7 28-35.1 52.4-20.3 43.5-34.6 102.9-37.5 167.4zm-48 0C116.4 146.4 138.5 66.9 170.8 14.7 78.7 47.3 10.9 131.2 1.5 232l111.4 0zM1.5 280c9.4 100.8 77.2 184.7 169.3 217.3-32.3-52.2-54.4-131.7-57.9-217.3L1.5 280zm398.4 0c-3.5 85.6-25.6 165.1-57.9 217.3 92.1-32.7 159.9-116.5 169.3-217.3l-111.4 0zm111.4-48C501.9 131.2 434.1 47.3 342 14.7 374.3 66.9 396.4 146.4 399.9 232l111.4 0z"),
        Entry(.solid, "trash", 448, "M136.7 5.9L128 32 32 32C14.3 32 0 46.3 0 64S14.3 96 32 96l384 0c17.7 0 32-14.3 32-32s-14.3-32-32-32l-96 0-8.7-26.1C306.9-7.2 294.7-16 280.9-16L167.1-16c-13.8 0-26 8.8-30.4 21.9zM416 144L32 144 53.1 467.1C54.7 492.4 75.7 512 101 512L347 512c25.3 0 46.3-19.6 47.9-44.9L416 144z"),
        Entry(.solid, "link-slash", 576, "M41-24.9c-9.4-9.4-24.6-9.4-33.9 0S-2.3-.3 7 9.1l528 528c9.4 9.4 24.6 9.4 33.9 0s9.4-24.6 0-33.9l-122-122c4.2-3.4 8.3-7.1 12.1-10.9l71.1-71.1c29.3-29.3 45.8-69.1 45.8-110.6 0-86.4-70-156.5-156.5-156.5-37.3 0-73.1 13.3-101.3 37.2 20.3 10.1 38.7 23.5 54.5 39.5 14.1-8.3 30.2-12.7 46.8-12.7 51.1 0 92.5 41.4 92.5 92.5 0 24.5-9.7 48-27.1 65.4l-71.1 71.1c-3.9 3.9-8.1 7.4-12.6 10.5l-47.5-47.5c16.5-.9 29.7-14.4 30.2-31.1 0-1.3 0-2.6 0-3.9 0-86.3-69.9-156.9-156.5-156.9-19.2 0-37.9 3.5-55.5 10.2L41-24.9zM225.9 160c.6 0 1.1 0 1.7 0 15.1 0 29.5 3.7 42.1 10.2 1.8 1.2 3.6 2.3 5.5 3.1 26.8 16.3 44.8 45.9 44.8 79.6 0 .4 0 .8 0 1.2L225.9 160zM346.2 416L192 261.8c1.2 84.6 69.6 152.9 154.1 154.1zM139.7 209.5l-45.3-45.3-48.6 48.6c-29.3 29.3-45.8 69.1-45.8 110.6 0 86.4 70 156.5 156.5 156.5 37.2 0 73.1-13.3 101.3-37.2-20.3-10.1-38.8-23.5-54.6-39.5-14 8.2-30.1 12.6-46.7 12.6-51.1 0-92.5-41.4-92.5-92.5 0-24.5 9.7-48 27.1-65.4l48.6-48.6z"),
        Entry(.solid, "circle-check", 512, "M256 512a256 256 0 1 1 0-512 256 256 0 1 1 0 512zM374 145.7c-10.7-7.8-25.7-5.4-33.5 5.3L221.1 315.2 169 263.1c-9.4-9.4-24.6-9.4-33.9 0s-9.4 24.6 0 33.9l72 72c5 5 11.8 7.5 18.8 7s13.4-4.1 17.5-9.8L379.3 179.2c7.8-10.7 5.4-25.7-5.3-33.5z"),
        Entry(.solid, "gear", 512, "M195.1 9.5C198.1-5.3 211.2-16 226.4-16l59.8 0c15.2 0 28.3 10.7 31.3 25.5L332 79.5c14.1 6 27.3 13.7 39.3 22.8l67.8-22.5c14.4-4.8 30.2 1.2 37.8 14.4l29.9 51.8c7.6 13.2 4.9 29.8-6.5 39.9L447 233.3c.9 7.4 1.3 15 1.3 22.7s-.5 15.3-1.3 22.7l53.4 47.5c11.4 10.1 14 26.8 6.5 39.9l-29.9 51.8c-7.6 13.1-23.4 19.2-37.8 14.4l-67.8-22.5c-12.1 9.1-25.3 16.7-39.3 22.8l-14.4 69.9c-3.1 14.9-16.2 25.5-31.3 25.5l-59.8 0c-15.2 0-28.3-10.7-31.3-25.5l-14.4-69.9c-14.1-6-27.2-13.7-39.3-22.8L73.5 432.3c-14.4 4.8-30.2-1.2-37.8-14.4L5.8 366.1c-7.6-13.2-4.9-29.8 6.5-39.9l53.4-47.5c-.9-7.4-1.3-15-1.3-22.7s.5-15.3 1.3-22.7L12.3 185.8c-11.4-10.1-14-26.8-6.5-39.9L35.7 94.1c7.6-13.2 23.4-19.2 37.8-14.4l67.8 22.5c12.1-9.1 25.3-16.7 39.3-22.8L195.1 9.5zM256.3 336a80 80 0 1 0 -.6-160 80 80 0 1 0 .6 160z"),
        Entry(.solid, "arrow-rotate-right", 512, "M436.7 74.7L448 85.4 448 32c0-17.7 14.3-32 32-32s32 14.3 32 32l0 128c0 17.7-14.3 32-32 32l-128 0c-17.7 0-32-14.3-32-32s14.3-32 32-32l47.9 0-7.6-7.2c-.2-.2-.4-.4-.6-.6-75-75-196.5-75-271.5 0s-75 196.5 0 271.5 196.5 75 271.5 0c8.2-8.2 15.5-16.9 21.9-26.1 10.1-14.5 30.1-18 44.6-7.9s18 30.1 7.9 44.6c-8.5 12.2-18.2 23.8-29.1 34.7-100 100-262.1 100-362 0S-25 175 75 75c99.9-99.9 261.7-100 361.7-.3z"),
        Entry(.solid, "circle-info", 512, "M256 512a256 256 0 1 0 0-512 256 256 0 1 0 0 512zM224 160a32 32 0 1 1 64 0 32 32 0 1 1 -64 0zm-8 64l48 0c13.3 0 24 10.7 24 24l0 88 8 0c13.3 0 24 10.7 24 24s-10.7 24-24 24l-80 0c-13.3 0-24-10.7-24-24s10.7-24 24-24l24 0 0-64-24 0c-13.3 0-24-10.7-24-24s10.7-24 24-24z"),
        Entry(.solid, "chevron-down", 448, "M201.4 406.6c12.5 12.5 32.8 12.5 45.3 0l192-192c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0L224 338.7 54.6 169.4c-12.5-12.5-32.8-12.5-45.3 0s-12.5 32.8 0 45.3l192 192z"),
        Entry(.solid, "folder-minus", 512, "M448 448L64 448c-35.3 0-64-28.7-64-64L0 96C0 60.7 28.7 32 64 32l138.7 0c13.8 0 27.3 4.5 38.4 12.8l38.4 28.8c5.5 4.2 12.3 6.4 19.2 6.4L448 80c35.3 0 64 28.7 64 64l0 240c0 35.3-28.7 64-64 64zM184 240c-13.3 0-24 10.7-24 24s10.7 24 24 24l144 0c13.3 0 24-10.7 24-24s-10.7-24-24-24l-144 0z"),
    ]
}

extension FAIcon {
    struct FreeSource { let name: String, rotation: CGFloat, hasRegular: Bool }

    /// The Free icon that stands for this chrome icon. Solid is the family: one weight across both bars. Only the two unfilled-shape
    /// tools (`circle`, `square`) take the regular outline when unselected, so selecting one fills it. Four Pro-only icons use the closest Free shape instead:
    /// `slash-forward` is a diagonal `minus`, `text` is `t`, `arrow-up-right` is `arrow-right` turned 45° up
    /// (rotation is SVG degrees: negative turns counter-clockwise as drawn) and `camera-viewfinder` is `expand` (four capture-frame corners).
    /// The right and left chevrons are the embedded `chevron-down` turned a quarter turn (counter-clockwise for right, clockwise for left).
    var freeSource: FreeSource {
        switch self {
        case .eyeSlash: return .init(name: "eye-slash", rotation: 0, hasRegular: false)
        case .toolbox: return .init(name: "toolbox", rotation: 0, hasRegular: false)
        case .images: return .init(name: "images", rotation: 0, hasRegular: false)
        case .boxArchive: return .init(name: "box-archive", rotation: 0, hasRegular: false)
        case .clockRotateLeft: return .init(name: "clock-rotate-left", rotation: 0, hasRegular: false)
        case .arrowPointer: return .init(name: "arrow-pointer", rotation: 0, hasRegular: false)
        case .paintbrush: return .init(name: "paintbrush", rotation: 0, hasRegular: false)
        case .slashForward: return .init(name: "minus", rotation: -45, hasRegular: false)
        case .circle: return .init(name: "circle", rotation: 0, hasRegular: true)
        case .square: return .init(name: "square", rotation: 0, hasRegular: true)
        case .fillDrip: return .init(name: "fill-drip", rotation: 0, hasRegular: false)
        case .eraser: return .init(name: "eraser", rotation: 0, hasRegular: false)
        case .text: return .init(name: "t", rotation: 0, hasRegular: false)
        case .arrowUpRight: return .init(name: "arrow-right", rotation: -45, hasRegular: false)
        case .cropSimple: return .init(name: "crop-simple", rotation: 0, hasRegular: false)
        case .crosshairs: return .init(name: "crosshairs", rotation: 0, hasRegular: false)
        case .frameViewfinder: return .init(name: "expand", rotation: 0, hasRegular: false)
        case .xmark: return .init(name: "xmark", rotation: 0, hasRegular: false)
        case .font: return .init(name: "font", rotation: 0, hasRegular: false)
        case .arrowRotateLeft: return .init(name: "arrow-rotate-left", rotation: 0, hasRegular: false)
        case .broom: return .init(name: "broom", rotation: 0, hasRegular: false)
        case .upload: return .init(name: "cloud-arrow-up", rotation: 0, hasRegular: false)
        case .dragHand: return .init(name: "hand", rotation: 0, hasRegular: false)
        case .check: return .init(name: "check", rotation: 0, hasRegular: false)
        case .xmarkCircle: return .init(name: "circle-xmark", rotation: 0, hasRegular: false)
        case .openExternal: return .init(name: "up-right-from-square", rotation: 0, hasRegular: false)
        case .copy: return .init(name: "copy", rotation: 0, hasRegular: false)
        case .link: return .init(name: "link", rotation: 0, hasRegular: false)
        case .globe: return .init(name: "globe", rotation: 0, hasRegular: false)
        case .trash: return .init(name: "trash", rotation: 0, hasRegular: false)
        case .linkSlash: return .init(name: "link-slash", rotation: 0, hasRegular: false)
        case .circleCheck: return .init(name: "circle-check", rotation: 0, hasRegular: false)
        case .gear: return .init(name: "gear", rotation: 0, hasRegular: false)
        case .arrowRotateRight: return .init(name: "arrow-rotate-right", rotation: 0, hasRegular: false)
        case .circleInfo: return .init(name: "circle-info", rotation: 0, hasRegular: false)
        case .chevronDown: return .init(name: "chevron-down", rotation: 0, hasRegular: false)
        case .folderMinus: return .init(name: "folder-minus", rotation: 0, hasRegular: false)
        case .chevronRight: return .init(name: "chevron-down", rotation: -90, hasRegular: false)
        case .chevronLeft: return .init(name: "chevron-down", rotation: 90, hasRegular: false)
        }
    }
}
