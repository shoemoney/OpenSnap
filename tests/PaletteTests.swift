// Colour-role checks: resolves each arm of every role; no windows, NSApplication or desktop input.
// rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D PALETTE_TESTS \
//   Sources/DesignTokens.swift tests/PaletteTests.swift -o /tmp/opensnap-palette-tests
#if PALETTE_TESTS
import AppKit

@main
private enum PaletteTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0
    typealias P = DesignTokens.Palette

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

    /// WCAG large text starts at 24 pt in this app's rules; below it the full 4.5 applies.
    private static func requiredRatio(pointSize: CGFloat) -> CGFloat { pointSize >= 24 ? 3 : 4.5 }

    private static func rgb(_ color: NSColor, _ arm: P.Arm) -> P.RGB { P.rgb(P.resolve(color, arm: arm)).rgb }
    private static func alpha(_ color: NSColor, _ arm: P.Arm) -> CGFloat { P.resolve(color, arm: arm).alphaComponent }

    /// Text drawn over `surface` in one arm.
    private static func ratio(_ text: NSColor, on surface: NSColor, _ arm: P.Arm) -> CGFloat {
        P.contrastRatio(P.resolve(text, arm: arm), rgb(surface, arm))
    }

    static func main() throws {
        // the contrast maths itself
        try expect(abs(P.contrastRatio(NSColor.black, P.RGB(red: 1, green: 1, blue: 1)) - 21) < 1e-6, "black on white is 21:1")
        try expect(abs(P.contrastRatio(NSColor.white, P.RGB(red: 1, green: 1, blue: 1)) - 1) < 1e-6, "white on white is 1:1")
        try expect(requiredRatio(pointSize: 26) == 3 && requiredRatio(pointSize: 20) == 4.5, "large text needs 3, body needs 4.5")

        // the four arms are told apart
        try expect(P.arm(forName: .aqua) == .aqua && P.arm(forName: .darkAqua) == .darkAqua, "aqua and darkAqua select their own arm")
        try expect(P.arm(forName: .accessibilityHighContrastAqua) == .highContrastAqua, "high-contrast aqua selects its own arm")
        try expect(P.arm(forName: .accessibilityHighContrastDarkAqua) == .highContrastDarkAqua, "high-contrast darkAqua selects its own arm")
        try expect(P.arm(for: NSAppearance(named: .darkAqua)!) == .darkAqua && P.arm(for: NSAppearance(named: .aqua)!) == .aqua, "a live appearance selects its arm")

        // text roles against every surface they sit on, in all four arms (body sizes, so 4.5)
        let textRoles: [(String, NSColor)] = [("text.primary", P.Text.primary), ("text.secondary", P.Text.secondary), ("feedback.error", P.feedbackError)]
        let needed = requiredRatio(pointSize: DesignTokens.Typography.font(.caption).pointSize)
        for arm in P.Arm.allCases {
            for (roleName, role) in textRoles {
                for (index, surface) in P.Surface.all.enumerated() {
                    let got = ratio(role, on: surface, arm)
                    try expect(got >= needed, "\(roleName) on surface \(index) in \(arm) is \(got):1, needs \(needed)")
                }
            }
            // primary text on the state fills it sits on, over the window
            for (fillName, fill) in [("hover", P.State.hover), ("pressed", P.State.pressed), ("selectedFill", P.State.selectedFill)] {
                let blended = P.blend(P.resolve(fill, arm: arm), alpha: 1, over: P.resolve(P.Surface.window, arm: arm))
                let got = P.contrastRatio(P.resolve(P.Text.primary, arm: arm), blended)
                try expect(got >= 4.5, "text.primary on \(fillName) over the window in \(arm) is \(got):1")
            }
            // disabled text is exempt from the floor, but must stay visible and weaker than secondary
            let disabled = ratio(P.Text.disabled, on: P.Surface.window, arm)
            try expect(disabled >= 1.5 && disabled < ratio(P.Text.secondary, on: P.Surface.window, arm), "text.disabled in \(arm) is \(disabled):1")
            // overlays sit on arbitrary pixels: check the worst case, a black and a white backdrop
            for (backdropName, backdrop) in [("black", NSColor.black), ("white", NSColor.white)] {
                let plate = P.blend(P.resolve(P.Overlay.plateFill, arm: arm), alpha: 1, over: backdrop)
                let plateGot = P.contrastRatio(P.resolve(P.Overlay.plateText, arm: arm), plate)
                try expect(plateGot >= 4.5, "plateText on plateFill over \(backdropName) in \(arm) is \(plateGot):1")
                let hud = P.blend(P.resolve(P.Overlay.hudFill, arm: arm), alpha: 1, over: backdrop)
                let hudGot = P.contrastRatio(P.resolve(P.Overlay.hudText, arm: arm), hud)
                try expect(hudGot >= 4.5, "hudText on hudFill over \(backdropName) in \(arm) is \(hudGot):1")
            }
        }

        // every role resolves to a finite colour in every arm, and the dynamic path agrees with the arm it selects
        let everyRole: [(String, NSColor)] = [
            ("surface.window", P.Surface.window), ("surface.content", P.Surface.content), ("surface.canvasWell", P.Surface.canvasWell),
            ("text.primary", P.Text.primary), ("text.secondary", P.Text.secondary), ("text.disabled", P.Text.disabled), ("accent", P.accent),
            ("state.hover", P.State.hover), ("state.pressed", P.State.pressed), ("state.selectedFill", P.State.selectedFill), ("state.primaryFill", P.State.primaryFill),
            ("focus.ring", P.focusRing), ("separator", P.separator), ("feedback.error", P.feedbackError),
            ("swatch.rest", P.SwatchOutline.rest), ("swatch.hover", P.SwatchOutline.hover),
            ("overlay.scrim", P.Overlay.scrim), ("overlay.plateFill", P.Overlay.plateFill), ("overlay.plateText", P.Overlay.plateText),
            ("overlay.hudFill", P.Overlay.hudFill), ("overlay.hudText", P.Overlay.hudText), ("overlay.hudStroke", P.Overlay.hudStroke),
            ("overlay.crosshairOuter", P.Overlay.crosshairOuter), ("overlay.crosshairInner", P.Overlay.crosshairInner),
        ]
        let live: [(P.Arm, NSAppearance)] = [(.aqua, NSAppearance(named: .aqua)!), (.darkAqua, NSAppearance(named: .darkAqua)!)]
        for (name, role) in everyRole {
            for arm in P.Arm.allCases {
                let resolved = P.resolve(role, arm: arm)
                try expect(resolved.alphaComponent.isFinite && resolved.redComponent.isFinite, "\(name) did not resolve in \(arm)")
            }
            for (arm, appearance) in live {
                try expect(P.resolve(role, for: appearance) == P.resolve(role, arm: arm), "\(name): the live \(arm) appearance and the \(arm) arm disagree")
            }
        }

        // the arms really differ where the spec says they do
        try expect(rgb(P.Surface.window, .aqua).red != rgb(P.Surface.window, .darkAqua).red, "window differs between aqua and darkAqua")
        try expect(alpha(P.State.hover, .highContrastAqua) > alpha(P.State.hover, .aqua) && alpha(P.State.hover, .highContrastDarkAqua) > alpha(P.State.hover, .darkAqua), "hover strengthens under Increase Contrast")
        for arm in [P.Arm.aqua, .darkAqua] {
            try expect(abs(alpha(P.State.hover, arm) - 0.08) < 0.005 && abs(alpha(P.State.pressed, arm) - 0.16) < 0.005, "hover 0.08, pressed 0.16 in \(arm)")
            try expect(abs(alpha(P.State.selectedFill, arm) - 0.20) < 0.005, "selected fill 0.20 in \(arm)")
            try expect(abs(alpha(P.Overlay.plateFill, arm) - 0.75) < 0.005, "plate 0.75 in \(arm)")
        }
        for arm in [P.Arm.highContrastAqua, .highContrastDarkAqua] {
            try expect(abs(alpha(P.State.hover, arm) - 0.16) < 0.005 && abs(alpha(P.State.pressed, arm) - 0.28) < 0.005, "hover 0.16, pressed 0.28 in \(arm)")
            try expect(abs(alpha(P.State.selectedFill, arm) - 0.32) < 0.005, "selected fill 0.32 in \(arm)")
            try expect(abs(alpha(P.Overlay.plateFill, arm) - 0.92) < 0.005, "plate 0.92 in \(arm)")
        }
        try expect(P.resolve(P.Overlay.hudFill, arm: .aqua) == P.resolve(P.Overlay.hudFill, arm: .darkAqua), "overlays are fixed across light and dark")
        try expect(P.resolve(P.State.primaryFill, arm: .aqua).alphaComponent == 1, "primary fill is opaque accent")

        // onAccent is computed from the blended fill
        let plate = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let yellow = NSColor(srgbRed: 1, green: 0.9, blue: 0, alpha: 1), navy = NSColor(srgbRed: 0, green: 0.1, blue: 0.5, alpha: 1)
        try expect(P.onAccent(fill: yellow, alpha: 1, over: plate) == .black, "yellow accent flips to black text")
        try expect(P.onAccent(fill: navy, alpha: 1, over: plate) == .white, "dark blue accent keeps white text")
        try expect(P.onAccent(fill: navy, alpha: 0.2, over: plate) == .black, "navy at 0.2 over white is a pale tint: black text (an opaque-accent check would say white)")
        try expect(P.onAccent(fill: yellow, alpha: 0.1, over: NSColor.black) == .white, "yellow at 0.1 over black is nearly black: white text")
        print("PaletteTests: \(checks) checks passed")
    }
}
#endif
