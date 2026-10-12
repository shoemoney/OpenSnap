// The component state model (T6) as a pure function: every state x primary x Increase Contrast x Differentiate Without Color, with the exact
// alphas and flags, plus the invariants the spec names. No views, windows, NSApplication or input.
// rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D STATE_STYLES_TESTS \
//   Sources/DesignTokens.swift Sources/StateStyles.swift tests/StateStylesTests.swift -o /tmp/opensnap-state-styles-tests
#if STATE_STYLES_TESTS
import AppKit

@main
private enum StateStylesTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0
    typealias P = DesignTokens.Palette

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

    private static let aqua = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
    private static let appearances: [(String, NSAppearance)] = [("aqua", aqua), ("darkAqua", dark)]
    private static let flags = [false, true]

    private static func accent(_ appearance: NSAppearance, highContrast: Bool) -> NSColor {
        P.resolve(P.accent, arm: StateStyles.arm(for: appearance, highContrast: highContrast))
    }

    private static func same(_ a: NSColor?, _ b: NSColor?, tolerance: CGFloat = 0.004) -> Bool {
        guard let a, let b, let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return a == nil && b == nil }
        return abs(x.redComponent - y.redComponent) < tolerance && abs(x.greenComponent - y.greenComponent) < tolerance
            && abs(x.blueComponent - y.blueComponent) < tolerance && abs(x.alphaComponent - y.alphaComponent) < tolerance
    }

    private static func alpha(_ color: NSColor?) -> CGFloat { color?.usingColorSpace(.sRGB)?.alphaComponent ?? -1 }
    private static func lum(_ color: NSColor) -> CGFloat { P.luminance(P.rgb(color).rgb) }

    static func main() throws {
        try tableTests()
        try invariantTests()
        try primaryTests()
        try contrastTests()
        try toggleTests()
        try trackTests()
        try swatchTests()
        try restPlateTests()
        try focusRingTests()
        print("PASS state-styles-tests (\(checks) checks)")
    }

    // MARK: the T6 table, exactly

    private static func tableTests() throws {
        for (name, appearance) in appearances {
            for hc in flags {
                for dwc in flags {
                    for focused in flags {
                        func style(_ state: ControlState, selected: Bool = false) -> StateStyle {
                            StateStyles.command(state, primary: false, focused: focused, highContrast: hc, differentiate: dwc, selected: selected, appearance: appearance)
                        }
                        let label = "\(name) hc=\(hc) dwc=\(dwc) focus=\(focused)"
                        let hoverAlpha: CGFloat = hc ? 0.16 : 0.08, pressedAlpha: CGFloat = hc ? 0.28 : 0.16, selectedAlpha: CGFloat = hc ? (name == "darkAqua" ? 0.35 : 0.32) : (name == "darkAqua" ? 0.34 : 0.20)
                        let acc = accent(appearance, highContrast: hc)

                        let rest = style(.rest)
                        try expect(rest.fill == nil && rest.border == nil && rest.borderWidth == 0 && rest.contentAlpha == 1 && !rest.indicator && rest.glyphScale == 1 && !rest.strongText, "rest is bare: \(label)")
                        try expect(rest.focusRing == focused, "rest shows the focus ring only when focused: \(label)")

                        let hover = style(.hover)
                        try expect(abs(alpha(hover.fill) - hoverAlpha) < 0.004 && hover.border == nil && hover.contentAlpha == 1 && !hover.indicator && hover.glyphScale == 1, "hover is label@\(hoverAlpha): \(label)")

                        let pressed = style(.pressed)
                        try expect(abs(alpha(pressed.fill) - pressedAlpha) < 0.004 && pressed.border == nil && pressed.glyphScale == 0.96 && !pressed.indicator, "pressed is label@\(pressedAlpha), glyph 0.96: \(label)")

                        let selected = style(.selected)
                        try expect(abs(alpha(selected.fill) - selectedAlpha) < 0.004 && same(selected.fill?.withAlphaComponent(1), acc.withAlphaComponent(1)), "selected is accent@\(selectedAlpha): \(label)")
                        try expect(same(selected.border, acc) && selected.borderWidth == 1 && selected.strongText && selected.contentAlpha == 1 && selected.glyphScale == 1, "selected has a 1 pt accent border and strong text: \(label)")
                        try expect(selected.indicator == dwc, "the selected indicator follows Differentiate Without Color: \(label)")

                        let selectedHover = style(.hover, selected: true)
                        try expect(selectedHover == selected, "hover does not wash out a selected control: \(label)")
                        let selectedPressed = style(.pressed, selected: true)
                        try expect(abs(alpha(selectedPressed.fill) - (selectedAlpha + 0.12)) < 0.004 && selectedPressed.glyphScale == 0.96 && selectedPressed.indicator == dwc, "pressing a selected control deepens it by 0.12: \(label)")

                        let disabled = style(.disabled)
                        try expect(disabled.fill == nil && disabled.border == nil && disabled.contentAlpha == StateStyles.disabledAlpha(highContrast: hc) && !disabled.indicator && !disabled.focusRing && disabled.glyphScale == 1, "disabled is bare at 0.38: \(label)")
                        let disabledSelected = style(.disabled, selected: true)
                        try expect(disabledSelected.fill == nil && !disabledSelected.indicator, "a disabled selected control keeps nothing interactive: \(label)")

                        for state in ControlState.allCases where state != .disabled {
                            try expect(style(state).contentAlpha == 1, "only disabled dims: \(state) \(label)")
                        }
                    }
                }
            }
        }
    }

    // MARK: invariants over the whole input space

    private static func invariantTests() throws {
        for (name, appearance) in appearances {
            for primary in flags {
                for dwc in flags {
                    for state in ControlState.allCases {
                        func style(_ hc: Bool, _ s: ControlState = state) -> StateStyle {
                            StateStyles.command(s, primary: primary, focused: false, highContrast: hc, differentiate: dwc, appearance: appearance)
                        }
                        let label = "\(name) primary=\(primary) dwc=\(dwc) \(state)"
                        let normal = style(false), high = style(true)

                        // disabled never gets a hover or pressed fill
                        if state == .disabled {
                            let hover = style(false, .hover), pressed = style(false, .pressed), rest = style(false, .rest)
                            try expect(normal.glyphScale == 1, "disabled never scales: \(label)")
                            if primary {
                                try expect(same(normal.fill, rest.fill) && !same(normal.fill, hover.fill) && !same(normal.fill, pressed.fill), "a disabled Snap keeps its rest fill, not hover or pressed: \(label)")
                            } else {
                                try expect(normal.fill == nil && high.fill == nil, "a disabled command has no fill at all: \(label)")
                            }
                        }

                        // selected with differentiate always has an indicator; without it never does
                        if state == .selected && !primary {
                            try expect(normal.indicator == dwc && high.indicator == dwc, "selected indicator == differentiate: \(label)")
                        }

                        // high contrast is strictly stronger than normal wherever there is something to strengthen
                        switch (primary, state) {
                        case (false, .hover), (false, .pressed), (false, .selected):
                            try expect(alpha(high.fill) > alpha(normal.fill), "HC fill is stronger: \(label) \(alpha(high.fill)) vs \(alpha(normal.fill))")
                        case (true, _):
                            try expect(high.borderWidth > normal.borderWidth, "HC outlines Snap: \(label)")
                        default: break
                        }
                    }
                    // pressed differs from hover, in every combination
                    for hc in flags {
                        let hover = StateStyles.command(.hover, primary: primary, focused: false, highContrast: hc, differentiate: dwc, appearance: appearance)
                        let pressed = StateStyles.command(.pressed, primary: primary, focused: false, highContrast: hc, differentiate: dwc, appearance: appearance)
                        try expect(!same(hover.fill, pressed.fill) && hover != pressed, "pressed differs from hover: \(name) primary=\(primary) hc=\(hc)")
                    }
                }
            }
        }
        // the selected fill is stronger than hover, so hovering a plain control never looks selected
        for hc in flags {
            let hover = StateStyles.command(.hover, primary: false, focused: false, highContrast: hc, differentiate: false, appearance: aqua)
            let selected = StateStyles.command(.selected, primary: false, focused: false, highContrast: hc, differentiate: false, appearance: aqua)
            try expect(alpha(selected.fill) > alpha(hover.fill) && selected.border != nil && hover.border == nil, "selected reads stronger than hover: hc=\(hc)")
        }
        // the flag, not the appearance, picks the high-contrast arm (the harness injects it under plain aqua)
        try expect(StateStyles.arm(for: aqua, highContrast: true) == .highContrastAqua && StateStyles.arm(for: dark, highContrast: true) == .highContrastDarkAqua
                   && StateStyles.arm(for: aqua, highContrast: false) == .aqua && StateStyles.arm(for: dark, highContrast: false) == .darkAqua, "highContrast selects the HC arm of either appearance")
    }

    // MARK: keyboard focus ring

    /// The ring is at least 3:1 against the surface it sits on (WCAG 1.4.11) in every arm, and is a different SHAPE from "selected":
    /// stroked wider than the selected 1 pt border and standing off the control, never the accent fill's tone alone.
    private static func focusRingTests() throws {
        for (name, appearance) in appearances {
            for hc in flags {
                let arm = StateStyles.arm(for: appearance, highContrast: hc)
                let ring = StateStyles.focusRingColor(highContrast: hc, appearance: appearance)
                let window = P.resolve(P.Surface.window, arm: arm), content = P.resolve(P.Surface.content, arm: arm)
                for (surface, color) in [("window", window), ("content", content)] {
                    let ratio = P.contrastRatio(ring, P.rgb(color).rgb)
                    try expect(ratio >= 3, "focus ring on the \(surface) in \(name) hc=\(hc) is \(String(format: "%.2f", ratio)):1, needs 3:1")
                }
                let selected = StateStyles.command(.selected, primary: false, focused: true, highContrast: hc, differentiate: false, appearance: appearance)
                try expect(selected.focusRing && selected.borderWidth == 1, "a focused selected control shows both its 1 pt border and the ring (\(name) hc=\(hc))")
                try expect(StateStyles.focusRingWidth > selected.borderWidth && StateStyles.focusRingOutset > 0,
                           "the ring is stroked wider than the selected border and stands off the control (\(StateStyles.focusRingWidth) pt at +\(StateStyles.focusRingOutset))")
                try expect(!same(ring, accent(appearance, highContrast: hc)), "the ring is not the selected accent colour (\(name) hc=\(hc))")
            }
        }
    }

    // MARK: Snap

    private static func primaryTests() throws {
        for (name, appearance) in appearances {
            for hc in flags {
                func style(_ state: ControlState) -> StateStyle {
                    StateStyles.command(state, primary: true, focused: false, highContrast: hc, differentiate: false, appearance: appearance)
                }
                let label = "\(name) hc=\(hc)", acc = accent(appearance, highContrast: hc)
                let rest = style(.rest), hover = style(.hover), pressed = style(.pressed), disabled = style(.disabled)
                try expect(same(rest.fill, acc) && alpha(rest.fill) == 1 && !rest.indicator, "Snap rests on the opaque accent: \(label)")
                try expect(same(hover.fill, acc.blended(withFraction: 0.08, of: .white)), "hover brightens by 8 %: \(label)")
                try expect(same(pressed.fill, acc.blended(withFraction: 0.12, of: .black)), "press darkens by 12 %: \(label)")
                try expect(lum(hover.fill!) > lum(rest.fill!) && lum(pressed.fill!) < lum(rest.fill!), "hover is lighter and press darker than rest: \(label)")
                try expect(same(disabled.fill, rest.fill) && disabled.contentAlpha == StateStyles.disabledAlpha(highContrast: hc) && rest.contentAlpha == 1, "disabled Snap is the same accent dimmed to 0.38: \(label)")
                try expect(pressed.glyphScale == 0.96 && hover.glyphScale == 1, "pressed Snap scales its glyph: \(label)")
                try expect(rest.borderWidth == (hc ? 1 : 0), "Increase Contrast outlines Snap: \(label)")
                let selected = StateStyles.command(.selected, primary: true, focused: false, highContrast: hc, differentiate: true, appearance: appearance)
                try expect(same(selected.fill, rest.fill) && !selected.indicator, "Snap has no selected state of its own: \(label)")
            }
        }
    }

    // MARK: onAccent is computed against the blended fill

    private static func contrastTests() throws {
        for (name, appearance) in appearances {
            for hc in flags {
                let arm = StateStyles.arm(for: appearance, highContrast: hc)
                let window = P.resolve(P.Surface.window, arm: arm)
                for (stateName, state, selectedFlag) in [("rest", ControlState.rest, false), ("selected", .selected, false), ("selected pressed", .pressed, true), ("selected hover", .hover, true)] {
                    let style = StateStyles.command(state, primary: false, focused: false, highContrast: hc, differentiate: false, selected: selectedFlag, appearance: appearance)
                    guard let fill = style.fill else { continue }
                    let blended = P.blend(fill, alpha: 1, over: window)
                    let content = P.resolve(style.content, arm: arm)
                    let ratio = P.contrastRatio(content, blended)
                    try expect(ratio >= 4.5, "a \(stateName) glyph on the blended fill is \(ratio):1 in \(name) hc=\(hc)")
                }
                for state in [ControlState.rest, .hover, .pressed, .disabled] {
                    let style = StateStyles.command(state, primary: true, focused: false, highContrast: hc, differentiate: false, appearance: appearance)
                    let ratio = P.contrastRatio(style.content, P.rgb(style.fill!).rgb)
                    try expect(ratio >= 4.5, "the Snap glyph on its \(state) fill is \(ratio):1 in \(name) hc=\(hc)")
                }
            }
        }
        // The style itself, with an accent that separates the blend from the opaque fill: a navy accent at 0.20 over the window is a pale tint
        // (black text) in light, while the opaque navy needs white. Under dark the dark window keeps the tint dark (white text).
        let navyAccent = NSColor(srgbRed: 0, green: 0.1, blue: 0.5, alpha: 1)
        let lightSelected = StateStyles.command(.selected, primary: false, focused: false, highContrast: false, differentiate: false, accent: navyAccent, appearance: aqua)
        let darkSelected = StateStyles.command(.selected, primary: false, focused: false, highContrast: false, differentiate: false, accent: navyAccent, appearance: dark)
        try expect(lightSelected.content == .black && darkSelected.content == .white, "a selected glyph is chosen against the blended fill, not the opaque accent (light \(lightSelected.content), dark \(darkSelected.content))")
        let lightPrimary = StateStyles.command(.rest, primary: true, focused: false, highContrast: false, differentiate: false, accent: navyAccent, appearance: aqua)
        try expect(lightPrimary.content == .white && same(lightPrimary.fill, navyAccent), "Snap on the opaque navy gets white: the opaque fill is what it sits on")
        // computed, not assumed: a fill that white cannot reach gets black, and the other way round, whatever the accent
        let plate = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), darkPlate = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        let yellow = NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1), navy = NSColor(srgbRed: 0, green: 0.1, blue: 0.5, alpha: 1)
        try expect(P.onAccent(fill: yellow, alpha: 1, over: plate) == .black && P.onAccent(fill: navy, alpha: 1, over: plate) == .white, "onAccent picks the readable one for an opaque fill")
        // a 0.20 navy over white is a pale tint: black text; the same navy at 0.20 over near-black is still dark: white text
        try expect(P.onAccent(fill: navy, alpha: 0.2, over: plate) == .black && P.onAccent(fill: navy, alpha: 0.2, over: darkPlate) == .white, "onAccent measures the blend over the plate, not the opaque accent")
        try expect(P.onAccent(fill: navy, alpha: 0.2, over: plate) != P.onAccent(fill: navy, alpha: 1, over: plate), "the same accent gets different text at different fill alphas")
    }

    // MARK: PNG | JPG segment

    private static func toggleTests() throws {
        for (name, appearance) in appearances {
            for hc in flags {
                func style(_ state: ControlState, dwc: Bool = false, focused: Bool = false) -> StateStyle {
                    StateStyles.toggleSegment(state, focused: focused, highContrast: hc, differentiate: dwc, appearance: appearance)
                }
                let label = "\(name) hc=\(hc)"
                try expect(abs(alpha(style(.rest).fill) - 0.06) < 0.004 && !style(.rest).strongText, "an unselected segment rests on label@0.06 at every contrast, so a heavier plate never sits under its label: \(label)")
                // The label's contrast on the plate it sits on is never lower with Increase Contrast than without.
                func labelRatio(_ high: Bool) -> CGFloat {
                    let rest = StateStyles.toggleSegment(.rest, focused: false, highContrast: high, differentiate: false, appearance: appearance)
                    let window = P.resolve(P.Surface.window, arm: StateStyles.arm(for: appearance, highContrast: high))
                    let shown = rest.fill.map { P.blend($0, alpha: 1, over: window) } ?? P.rgb(window).rgb
                    return P.contrastRatio(rest.content, shown)
                }
                try expect(labelRatio(true) >= labelRatio(false) - 0.001 && labelRatio(true) >= 7, "Increase Contrast never lowers the unselected label's contrast (\(labelRatio(false)) -> \(labelRatio(true))): \(label)")
                try expect((style(.rest).border != nil && style(.rest).borderWidth == 1) == hc, "Increase Contrast adds a 1 pt outline to the unselected segment and nothing else changes: \(label)")
                try expect(abs(alpha(style(.hover).fill) - (hc ? 0.16 : 0.08)) < 0.004 && abs(alpha(style(.pressed).fill) - (hc ? 0.28 : 0.16)) < 0.004, "hover .08 and pressed .16 (HC .16, .28): \(label)")
                let selected = style(.selected)
                try expect(abs(alpha(selected.fill) - (hc ? (name == "darkAqua" ? 0.35 : 0.32) : (name == "darkAqua" ? 0.34 : 0.20))) < 0.004 && selected.strongText && selected.border != nil, "the selected segment is the accent tint (0.20 light, 0.34 dark; 0.32 / 0.35 under Increase Contrast) with bodyStrong text: \(label)")
                let marked = style(.selected, dwc: true), unmarked = style(.selected)
                try expect(marked.indicator && marked.strongText && marked.borderWidth == 2 && marked.border != nil, "Differentiate adds the capsule and a 2 pt outline on top of the weight: \(label)")
                try expect(!unmarked.indicator && unmarked.borderWidth == 1, "without Differentiate the selected segment keeps its 1 pt accent border and no capsule: \(label)")
                try expect(!same(marked.border, unmarked.border), "the Differentiate outline is the label colour, not the accent: \(label)")
                try expect(style(.disabled).contentAlpha == StateStyles.disabledAlpha(highContrast: hc) && alpha(style(.disabled).fill) == alpha(style(.rest).fill), "a disabled segment keeps its plate and dims its content: \(label)")
                try expect(!style(.rest).focusRing && style(.rest, focused: true).focusRing && !style(.disabled, focused: true).focusRing, "focus ring follows focus and never shows when disabled: \(label)")
            }
        }
    }

    // MARK: Size track

    private static func trackTests() throws {
        for (name, appearance) in appearances {
            for hc in flags {
                func style(_ state: ControlState) -> TrackStyle { StateStyles.track(state, highContrast: hc, appearance: appearance) }
                let label = "\(name) hc=\(hc)", acc = accent(appearance, highContrast: hc)
                try expect(style(.rest).knobScale == 1 && style(.hover).knobScale == 1.15 && style(.pressed).knobScale == 1.25, "knob scales 1, 1.15, 1.25: \(label)")
                try expect(style(.rest).highlight == nil && style(.hover).highlight == nil, "only a held knob highlights the track: \(label)")
                try expect(abs(alpha(style(.pressed).highlight) - (hc ? 0.45 : 0.30)) < 0.004 && same(style(.pressed).highlight?.withAlphaComponent(1), acc), "the held track is accent@0.3 (HC 0.45): \(label)")
                try expect(style(.disabled).alpha == StateStyles.disabledAlpha(highContrast: hc) && style(.rest).alpha == 1 && style(.disabled).knobScale == 1 && style(.disabled).highlight == nil, "a disabled track is dimmed to 0.38 and inert: \(label)")
                try expect(same(style(.rest).knob, acc), "the knob is the accent: \(label)")
                try expect((style(.rest).knobBorder != nil) == hc, "Increase Contrast rings the knob: \(label)")
                if hc {
                    let normal = StateStyles.track(.rest, highContrast: false, appearance: appearance)
                    try expect(alpha(style(.rest).track) > alpha(normal.track), "HC draws a stronger track: \(label)")
                }
            }
        }
    }

    // MARK: rest plate (audit fix 1: a command on the bar, off any group plate, reads as a button before hover)

    private static func restPlateTests() throws {
        for (name, appearance) in appearances {
            for hc in flags {
                let label = "\(name) hc=\(hc)"
                func plated(_ state: ControlState, focused: Bool = false) -> StateStyle {
                    StateStyles.command(state, primary: false, focused: focused, highContrast: hc, differentiate: false, restPlate: true, appearance: appearance)
                }
                func plain(_ state: ControlState) -> StateStyle {
                    StateStyles.command(state, primary: false, focused: false, highContrast: hc, differentiate: false, appearance: appearance)
                }
                let rest = StateStyles.restPlateAlpha(highContrast: hc)
                try expect(abs(rest - (hc ? 0.12 : 0.06)) < 0.0001, "the rest plate is the toggle segment's faint fill: \(label)")
                try expect(plain(.rest).fill == nil, "without the flag a command still rests with no fill: \(label)")
                try expect(abs(alpha(plated(.rest).fill) - rest) < 0.004, "a rest-plated command rests on label@\(rest): \(label)")
                // Hover and press deepen by the plate, so the feedback is never smaller than on a plain command.
                try expect(abs(alpha(plated(.hover).fill) - (alpha(plain(.hover).fill) + rest)) < 0.004, "hover adds to the rest plate: \(label)")
                try expect(abs(alpha(plated(.pressed).fill) - (alpha(plain(.pressed).fill) + rest)) < 0.004, "press adds to the rest plate: \(label)")
                try expect(alpha(plated(.hover).fill) > alpha(plated(.rest).fill) && alpha(plated(.pressed).fill) > alpha(plated(.hover).fill), "rest < hover < pressed: \(label)")
                try expect(abs(alpha(plated(.disabled).fill) - rest) < 0.004 && plated(.disabled).contentAlpha == StateStyles.disabledAlpha(highContrast: hc), "a disabled one keeps the plate and dims: \(label)")
                // Everything else is the plain command: content colour, no border, focus ring, no indicator.
                try expect(plated(.rest).content == plain(.rest).content && plated(.rest).border == nil && !plated(.rest).indicator && plated(.rest, focused: true).focusRing, "only the fill differs: \(label)")
                // Selection and Snap are untouched by the flag.
                let selected = StateStyles.command(.selected, primary: false, focused: false, highContrast: hc, differentiate: false, restPlate: true, appearance: appearance)
                try expect(selected == StateStyles.command(.selected, primary: false, focused: false, highContrast: hc, differentiate: false, appearance: appearance), "a selected command ignores the flag: \(label)")
                let snap = StateStyles.command(.rest, primary: true, focused: false, highContrast: hc, differentiate: false, restPlate: true, appearance: appearance)
                try expect(snap == StateStyles.command(.rest, primary: true, focused: false, highContrast: hc, differentiate: false, appearance: appearance), "Snap ignores the flag: \(label)")
            }
        }
    }

    // MARK: colour swatch

    private static func swatchTests() throws {
        for (name, appearance) in appearances {
            for hc in flags {
                func style(_ state: ControlState) -> SwatchStyle { StateStyles.swatch(state, highContrast: hc, appearance: appearance) }
                let label = "\(name) hc=\(hc)", arm = StateStyles.arm(for: appearance, highContrast: hc)
                let rest = style(.rest), hover = style(.hover), pressed = style(.pressed), selected = style(.selected), disabled = style(.disabled)
                try expect(rest.outlineWidth == 1 && rest.fill == nil && !rest.check && rest.alpha == 1, "rest is a 1 pt outline: \(label)")
                try expect(!hc ? same(rest.outline, P.resolve(P.SwatchOutline.rest, arm: arm)) : alpha(rest.outline) > alpha(P.resolve(P.SwatchOutline.rest, arm: arm)), "the rest outline is the separator (stronger in HC): \(label)")
                try expect(hover.outlineWidth == 1 && !hover.check && (hc || abs(alpha(hover.outline) - 0.5) < 0.004), "hover is label@0.5: \(label)")
                try expect(alpha(hover.outline) > alpha(rest.outline), "hover outlines stronger than rest: \(label)")
                try expect(abs(alpha(pressed.fill) - (hc ? 0.28 : 0.16)) < 0.004 && !pressed.check, "pressed fills label@0.16: \(label)")
                try expect(selected.outlineWidth == 3 && selected.check && same(selected.outline, accent(appearance, highContrast: hc)), "selected is a 3 pt accent outline plus the check: \(label)")
                try expect(disabled.alpha == StateStyles.disabledAlpha(highContrast: hc) && !disabled.check && disabled.fill == nil, "disabled swatch is dimmed to 0.38: \(label)")
                try expect([rest, hover, pressed, disabled].allSatisfy { !$0.check } && selected.check, "only the selected swatch carries the check")
            }
        }
        let light = NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1), darkSwatch = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        try expect(StateStyles.checkColor(on: light) == .black && StateStyles.checkColor(on: darkSwatch) == .white, "the check contrasts with the swatch it sits on")
        let translucent = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.1)
        try expect(StateStyles.checkColor(on: translucent) == .black, "a nearly clear swatch reads as white behind it, so the check is black")
    }
}
#endif
