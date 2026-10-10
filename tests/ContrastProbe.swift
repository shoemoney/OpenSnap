// A reusable contrast probe: renders a view under an explicit appearance and measures what is actually drawn.
// AppKit only, no @main, no #if: list this file among a suite's sources.
//
// The popover bug this exists for was invisible to token maths: the text colour and the plate colour were both fine on paper, but
// the view drew no plate of its own, so the text landed on whatever material the system put behind it. So the probe reads pixels.
import AppKit

@MainActor
enum ContrastProbe {
    /// The four arms every surface must hold: light, dark, and each with Increase Contrast, reached through the explicit-appearance seam.
    static let appearances: [(name: String, appearance: NSAppearance)] = [
        ("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!),
        ("light+increaseContrast", NSAppearance(named: .accessibilityHighContrastAqua)!),
        ("dark+increaseContrast", NSAppearance(named: .accessibilityHighContrastDarkAqua)!)]

    struct Reading {
        /// The pixel at the plate point, as drawn, and whether it is fully opaque (a plate that is not leaves the system behind it showing).
        var plate: DesignTokens.Palette.RGB
        var plateOpaque: Bool
        /// Per text frame: the highest WCAG ratio any drawn pixel in it reaches against the plate (the text's own strongest pixels).
        var textRatios: [CGFloat]
    }

    /// Renders `view` under `appearance`. `plateAt` is a point (view coordinates) that holds nothing but the plate; `textFrames` are
    /// the frames of the labels and controls whose text is judged. `plate` replaces the sampled pixel for a view that is drawn on a window
    /// background it does not own (the alert's content view, which sits on the sheet's window colour).
    static func measure(_ view: NSView, appearance: NSAppearance, plateAt: NSPoint, textFrames: [NSRect], plate override: NSColor? = nil) -> Reading {
        view.appearance = appearance
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return Reading(plate: .init(red: 0, green: 0, blue: 0), plateOpaque: false, textRatios: []) }
        view.cacheDisplay(in: bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / bounds.width
        func pixel(_ x: Int, _ y: Int) -> NSColor? { rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) }
        func imageY(_ y: CGFloat) -> Int { rep.pixelsHigh - 1 - Int(y * scale) }
        let sampled = pixel(Int(plateAt.x * scale), imageY(plateAt.y))
        var plateColor = sampled ?? .clear
        var opaque = (sampled?.alphaComponent ?? 0) > 0.999
        if let override {
            plateColor = DesignTokens.Palette.resolve(override, for: appearance); opaque = plateColor.alphaComponent > 0.999
        }
        let plate = DesignTokens.Palette.rgb(plateColor).rgb
        var ratios: [CGFloat] = []
        for frame in textFrames {
            var best: CGFloat = 1
            let x0 = max(0, Int(frame.minX * scale)), x1 = min(rep.pixelsWide - 1, Int(frame.maxX * scale))
            let y0 = max(0, imageY(frame.maxY)), y1 = min(rep.pixelsHigh - 1, imageY(frame.minY))
            if x0 <= x1, y0 <= y1 {
                for y in y0...y1 { for x in x0...x1 {
                    guard let color = pixel(x, y) else { continue }
                    // A pixel with partial coverage is judged as it lands on the plate.
                    best = max(best, DesignTokens.Palette.contrastRatio(DesignTokens.Palette.blend(color, alpha: 1, over: plateColor), plate))
                } }
            }
            ratios.append(best)
        }
        return Reading(plate: plate, plateOpaque: opaque, textRatios: ratios)
    }
}
