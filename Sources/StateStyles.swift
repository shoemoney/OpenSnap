import AppKit

/// The five states every interactive control draws. `focused` is orthogonal: a control can be focused in any of them.
enum ControlState: CaseIterable, Equatable, Sendable {
    case rest, hover, pressed, selected, disabled
}

/// What one control draws in one state. Pure data: a view applies it, a test reads it. Fills, borders and computed content colours are
/// resolved sRGB for the arm the style was asked for; the plain content roles stay dynamic so they follow the appearance on their own.
struct StateStyle: Equatable {
    var fill: NSColor?
    var content: NSColor
    var border: NSColor?
    var borderWidth: CGFloat
    /// 1 at rest; 0.38 when disabled. A view applies it to the whole control, so a disabled Snap reads as the accent at 0.38.
    var contentAlpha: CGFloat
    /// The 2 x 16 pt capsule under the glyph: the non-colour cue for a selected command (Differentiate Without Color).
    var indicator: Bool
    /// The glyph is drawn at this fraction of its size while pressed (a view skips it under Reduce Motion).
    var glyphScale: CGFloat
    /// A keyboard-focused, enabled control: the view lets AppKit draw its 2 pt `keyboardFocusIndicatorColor` ring.
    var focusRing: Bool
    /// Segment text is `bodyStrong` while selected, so selection is also a weight, never colour alone.
    var strongText: Bool
}

/// The Size track (popover): colours, knob scale and the pressed highlight.
struct TrackStyle: Equatable {
    var track: NSColor
    var dots: NSColor
    var knob: NSColor
    var knobScale: CGFloat
    var knobBorder: NSColor?
    /// Drawn over the whole track while the knob is held.
    var highlight: NSColor?
    var alpha: CGFloat
}

/// A colour swatch: its outline, an optional pressed fill, and the check glyph that marks the selected one.
struct SwatchStyle: Equatable {
    var outline: NSColor
    var outlineWidth: CGFloat
    var fill: NSColor?
    var check: Bool
    var alpha: CGFloat
}

/// The one component state model (T6): every state of every control resolves through here, from `DesignTokens.Palette` roles, so a
/// state is a function of its inputs and never of the view that draws it. `highContrast` and `differentiate` come from `DisplayOptions`.
enum StateStyles {
    typealias Palette = DesignTokens.Palette

    static let disabledAlpha: CGFloat = 0.38
    static let pressedGlyphScale: CGFloat = 0.96
    /// Snap brightens by this fraction of white on hover and darkens by this fraction of black while pressed.
    static let primaryHoverBrightness: CGFloat = 0.08, primaryPressedDarkening: CGFloat = 0.12
    /// Pressing a selected control deepens its fill by this much.
    static let selectedPressedBoost: CGFloat = 0.12
    static let hoverKnobScale: CGFloat = 1.15, pressedKnobScale: CGFloat = 1.25
    static let selectedSwatchOutlineWidth: CGFloat = 3
    /// The selected-command capsule: 2 x 16 pt, 3 pt tall under Increase Contrast, sitting this far above the control's bottom edge.
    static func indicatorSize(highContrast: Bool) -> NSSize { NSSize(width: 16, height: highContrast ? 3 : 2) }
    static let indicatorInset: CGFloat = 3

    /// The arm each role resolves under. Increase Contrast can be injected, so the appearance alone cannot be trusted to carry it.
    static func arm(for appearance: NSAppearance, highContrast: Bool) -> Palette.Arm {
        let arm = Palette.arm(for: appearance)
        guard highContrast else { return arm }
        return arm == .darkAqua ? .highContrastDarkAqua : (arm == .aqua ? .highContrastAqua : arm)
    }

    private static func resolve(_ role: NSColor, _ arm: Palette.Arm) -> NSColor { Palette.resolve(role, arm: arm) }

    /// `labelColor` at an alpha, built under the arm's appearance because a system colour snaps to the appearance current when it is tinted.
    private static func label(alpha: CGFloat, _ arm: Palette.Arm) -> NSColor {
        var color = NSColor.clear
        arm.baseAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.withAlphaComponent(alpha).usingColorSpace(.sRGB) ?? .labelColor
        }
        return color
    }

    private static func accent(alpha: CGFloat, _ arm: Palette.Arm) -> NSColor {
        resolve(Palette.accent, arm).withAlphaComponent(alpha)
    }

    // MARK: command (icon buttons and Snap)

    /// A command button: a tool, Undo, Wipe, Hide, Snap...
    /// - Parameters:
    ///   - selected: the control is also selected while it is hovered or pressed; `.selected` itself already means it.
    ///   - accent: replaces the system accent colour; tests use it to prove the glyph colour follows the blended fill, whatever the accent.
    static func command(_ state: ControlState, primary: Bool, focused: Bool, highContrast: Bool, differentiate: Bool,
                        selected: Bool = false, accent accentOverride: NSColor? = nil, appearance: NSAppearance = .currentDrawing()) -> StateStyle {
        let arm = arm(for: appearance, highContrast: highContrast)
        let disabled = state == .disabled
        let ring = focused && !disabled
        let alpha = disabled ? disabledAlpha : 1
        let window = resolve(Palette.Surface.window, arm)

        if primary {
            var fill = accentOverride ?? resolve(Palette.State.primaryFill, arm)
            if state == .pressed { fill = fill.blended(withFraction: primaryPressedDarkening, of: .black) ?? fill }
            else if state == .hover { fill = fill.blended(withFraction: primaryHoverBrightness, of: .white) ?? fill }
            // The glyph is chosen against the fill that is on screen, not the opaque accent, so a hover or press never costs contrast.
            let content = Palette.onAccent(fill: fill, alpha: 1, over: window)
            // Increase Contrast outlines Snap so its edge no longer depends on the fill alone.
            return StateStyle(fill: fill, content: content, border: highContrast ? label(alpha: 1, arm) : nil, borderWidth: highContrast ? 1 : 0,
                              contentAlpha: alpha, indicator: false, glyphScale: state == .pressed ? pressedGlyphScale : 1,
                              focusRing: ring, strongText: false)
        }

        if (state == .selected || selected) && !disabled {
            let base = resolve(Palette.State.selectedFill, arm).alphaComponent
            let shown = state == .pressed ? base + selectedPressedBoost : base
            let accent = accentOverride ?? resolve(Palette.accent, arm)
            return StateStyle(fill: accent.withAlphaComponent(shown),
                              content: Palette.onAccent(fill: accent, alpha: shown, over: window),
                              border: accent, borderWidth: 1, contentAlpha: 1, indicator: differentiate,
                              glyphScale: state == .pressed ? pressedGlyphScale : 1, focusRing: ring, strongText: true)
        }

        var fill: NSColor?
        switch state {
        case .hover: fill = resolve(Palette.State.hover, arm)
        case .pressed: fill = resolve(Palette.State.pressed, arm)
        case .rest, .selected, .disabled: fill = nil
        }
        return StateStyle(fill: fill, content: Palette.Text.primary, border: nil, borderWidth: 0, contentAlpha: alpha, indicator: false,
                          glyphScale: state == .pressed ? pressedGlyphScale : 1, focusRing: ring, strongText: false)
    }

    // MARK: toggle segment (PNG | JPG)

    /// One segment of the format toggle. Unselected segments sit on a faint plate so both halves read as a control; the selected one
    /// takes the command selected fill and its text turns `bodyStrong`.
    static func toggleSegment(_ state: ControlState, focused: Bool, highContrast: Bool, differentiate: Bool,
                              appearance: NSAppearance = .currentDrawing()) -> StateStyle {
        let arm = arm(for: appearance, highContrast: highContrast)
        if state == .selected {
            return command(.selected, primary: false, focused: focused, highContrast: highContrast, differentiate: false, appearance: appearance)
        }
        let ring = focused && state != .disabled
        let fill: NSColor
        switch state {
        case .hover: fill = resolve(Palette.State.hover, arm)
        case .pressed: fill = resolve(Palette.State.pressed, arm)
        case .rest, .selected, .disabled: fill = label(alpha: highContrast ? 0.12 : 0.06, arm)
        }
        return StateStyle(fill: fill, content: Palette.Text.primary, border: nil, borderWidth: 0,
                          contentAlpha: state == .disabled ? disabledAlpha : 1, indicator: false,
                          glyphScale: 1, focusRing: ring, strongText: false)
    }

    // MARK: Size track

    static func track(_ state: ControlState, highContrast: Bool, appearance: NSAppearance = .currentDrawing()) -> TrackStyle {
        let arm = arm(for: appearance, highContrast: highContrast)
        var track = NSColor.clear, dots = NSColor.clear
        arm.baseAppearance.performAsCurrentDrawingAppearance {
            track = (highContrast ? NSColor.labelColor.withAlphaComponent(0.30) : NSColor.quaternaryLabelColor).usingColorSpace(.sRGB) ?? .quaternaryLabelColor
            dots = (highContrast ? NSColor.labelColor : NSColor.secondaryLabelColor).usingColorSpace(.sRGB) ?? .secondaryLabelColor
        }
        let scale: CGFloat = state == .hover ? hoverKnobScale : (state == .pressed ? pressedKnobScale : 1)
        return TrackStyle(track: track, dots: dots, knob: resolve(Palette.accent, arm), knobScale: scale,
                          // A hairline ring keeps the knob's edge visible when the accent is close to the track colour.
                          knobBorder: highContrast ? label(alpha: 1, arm) : nil,
                          highlight: state == .pressed ? accent(alpha: highContrast ? 0.45 : 0.30, arm) : nil,
                          alpha: state == .disabled ? disabledAlpha : 1)
    }

    // MARK: colour swatch

    static func swatch(_ state: ControlState, highContrast: Bool, appearance: NSAppearance = .currentDrawing()) -> SwatchStyle {
        let arm = arm(for: appearance, highContrast: highContrast)
        let rest = highContrast ? label(alpha: 0.6, arm) : resolve(Palette.SwatchOutline.rest, arm)
        let hover = highContrast ? label(alpha: 0.8, arm) : resolve(Palette.SwatchOutline.hover, arm)
        switch state {
        case .rest: return SwatchStyle(outline: rest, outlineWidth: 1, fill: nil, check: false, alpha: 1)
        case .hover: return SwatchStyle(outline: hover, outlineWidth: 1, fill: nil, check: false, alpha: 1)
        case .pressed: return SwatchStyle(outline: hover, outlineWidth: 1, fill: resolve(Palette.State.pressed, arm), check: false, alpha: 1)
        case .selected: return SwatchStyle(outline: resolve(Palette.accent, arm), outlineWidth: selectedSwatchOutlineWidth, fill: nil, check: true, alpha: 1)
        case .disabled: return SwatchStyle(outline: rest, outlineWidth: 1, fill: nil, check: false, alpha: disabledAlpha)
        }
    }

    /// Black or white for the check glyph on a swatch of `color`, computed against that colour over a white backdrop.
    static func checkColor(on color: NSColor) -> NSColor {
        let alpha = (color.usingColorSpace(.sRGB) ?? color).alphaComponent
        return Palette.onAccent(fill: color, alpha: alpha, over: .white)
    }
}
