import AppKit

/// Every size, space, radius and colour the chrome is allowed to use. AppKit only, so every test suite can compile it.
enum DesignTokens {
    // MARK: Typography
    enum Typography {
        static let readableMinimum: CGFloat = 18, readableDefault: CGFloat = 20

        /// `caption` and `numeric` are the only styles allowed at 18; everything readable defaults to 20.
        enum Style: CaseIterable { case caption, body, bodyStrong, headline, title, hud, numeric, countdown }

        static func font(_ style: Style) -> NSFont {
            let font: NSFont
            switch style {
            case .caption: font = .systemFont(ofSize: 18, weight: .regular)
            case .body: font = .systemFont(ofSize: 20, weight: .regular)
            case .bodyStrong: font = .systemFont(ofSize: 20, weight: .semibold)
            case .headline: font = .systemFont(ofSize: 22, weight: .semibold)
            case .title: font = .systemFont(ofSize: 26, weight: .semibold)
            case .hud: font = .systemFont(ofSize: 20, weight: .medium)
            case .numeric: font = .monospacedDigitSystemFont(ofSize: 18, weight: .regular)
            case .countdown:
                let heavy = NSFont.systemFont(ofSize: 160, weight: .heavy)
                font = heavy.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 160) } ?? heavy
            }
            assert(font.pointSize >= readableMinimum, "\(style) is below the readable minimum")
            return font
        }

        /// The single replacement for the three local floors: nil becomes the default, anything under the minimum is raised to it.
        static func floored(_ font: NSFont?) -> NSFont {
            guard let font else { return .systemFont(ofSize: readableDefault) }
            guard font.pointSize < readableMinimum else { return font }
            return NSFont(descriptor: font.fontDescriptor, size: readableMinimum) ?? .systemFont(ofSize: readableMinimum)
        }

        static func attributes(_ style: Style, color: NSColor = .labelColor) -> [NSAttributedString.Key: Any] {
            [.font: font(style), .foregroundColor: color]
        }

        /// Sets the control font, its cell font and, for popups, the font AppKit uses for the menu items.
        static func apply(_ style: Style, to control: NSControl) {
            let font = font(style)
            control.font = font
            control.cell?.font = font
            if let popup = control as? NSPopUpButton {
                popup.menu?.font = font
            }
        }

        static let iconRegular: CGFloat = 22, iconPrimary: CGFloat = 26, iconInline: CGFloat = 20
    }

    // MARK: Spacing, radius, size, layout
    /// The 4-point grid; only these values belong in layout.
    enum Space {
        static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32
        static let all: [CGFloat] = [s1, s2, s3, s4, s5, s6]
    }

    enum Radius {
        static let sm: CGFloat = 4, md: CGFloat = 8, lg: CGFloat = 12, xl: CGFloat = 16
        static let all: [CGFloat] = [sm, md, lg, xl]
        /// Inner corners follow the outer corner minus the inset between them, never sharper than `sm`. A capsule is height / 2.
        static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat { max(sm, outer - inset) }
    }

    enum Size {
        static let control: CGFloat = 36, field: CGFloat = 40, row: CGFloat = 44, hitMin: CGFloat = 36
        static let tool = CGSize(width: 44, height: 40)
        static let primary = CGSize(width: 56, height: 44)
        /// 48 x 36, the current `GlassChrome.Metrics.iconButton`, not the spec's 48 x 40, so adopting this token moves no pixel.
        static let icon = CGSize(width: 48, height: 36)
    }

    enum Layout {
        /// 12, not `Space.s4`: the rail-removal width budget (T15) is computed with 12 and breaks at 16.
        static let margin: CGFloat = 12
        static let gap: CGFloat = Space.s2
        static let header: CGFloat = 44, footer: CGFloat = 44
        static let groupGap: CGFloat = 12
    }

    // MARK: Palette
    /// Every role is a dynamic colour with an arm for aqua, darkAqua and both high-contrast appearances.
    /// Never cache one as a `cgColor`; resolve it with `resolve(_:for:)` or draw it inside `performAsCurrentDrawingAppearance`.
    enum Palette {
        enum Arm: CaseIterable {
            case aqua, darkAqua, highContrastAqua, highContrastDarkAqua
            /// The appearance an arm is evaluated under. A headless process cannot build a working high-contrast `NSAppearance`
            /// (`NSAppearance(named:)` returns plain aqua/darkAqua and `appearanceNamed:bundle:` builds an inert one), so the
            /// high-contrast arms evaluate under their plain twin; system colours inside them are system-owned and unverified there.
            var baseAppearance: NSAppearance {
                NSAppearance(named: self == .darkAqua || self == .highContrastDarkAqua ? .darkAqua : .aqua) ?? .currentDrawing()
            }
        }

        /// High-contrast names first: `bestMatch` on a high-contrast appearance returns plain aqua/darkAqua if those come first.
        private static let appearances: [NSAppearance.Name] = [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua]

        static func arm(forName name: NSAppearance.Name) -> Arm {
            switch name {
            case .accessibilityHighContrastDarkAqua: return .highContrastDarkAqua
            case .accessibilityHighContrastAqua: return .highContrastAqua
            case .darkAqua: return .darkAqua
            default: return .aqua
            }
        }

        static func arm(for appearance: NSAppearance) -> Arm { arm(forName: appearance.bestMatch(from: appearances) ?? .aqua) }

        private static let armsLock = NSLock()
        nonisolated(unsafe) private static var registeredArms: [ObjectIdentifier: [Arm: () -> NSColor]] = [:]

        /// Arms are built lazily under the appearance being resolved: `withAlphaComponent` on a system colour snaps to the
        /// appearance current at the moment it is called, so building it at launch would freeze every arm to one appearance.
        private static func role(_ name: String, aqua: @autoclosure @escaping () -> NSColor, darkAqua: @autoclosure @escaping () -> NSColor,
                                 highContrastAqua: @autoclosure @escaping () -> NSColor, highContrastDarkAqua: @autoclosure @escaping () -> NSColor) -> NSColor {
            let arms: [Arm: () -> NSColor] = [.aqua: aqua, .darkAqua: darkAqua, .highContrastAqua: highContrastAqua, .highContrastDarkAqua: highContrastDarkAqua]
            let color = NSColor(name: "opensnap." + name) { appearance in
                var color = NSColor.clear
                appearance.performAsCurrentDrawingAppearance { color = arms[arm(for: appearance)]!() }
                return color
            }
            armsLock.lock()
            registeredArms[ObjectIdentifier(color)] = arms
            armsLock.unlock()
            return color
        }

        /// A system colour already adapts to each appearance, so all four arms build it.
        private static func system(_ name: String, _ color: @autoclosure @escaping () -> NSColor) -> NSColor {
            role(name, aqua: color(), darkAqua: color(), highContrastAqua: color(), highContrastDarkAqua: color())
        }

        /// A role whose value differs only when Increase Contrast is on.
        private static func contrast(_ name: String, normal: @autoclosure @escaping () -> NSColor, high: @autoclosure @escaping () -> NSColor) -> NSColor {
            role(name, aqua: normal(), darkAqua: normal(), highContrastAqua: high(), highContrastDarkAqua: high())
        }

        enum Surface {
            static let window = system("surface.window", .windowBackgroundColor)
            static let content = system("surface.content", .controlBackgroundColor)
            /// Solid on purpose: the canvas well is not a material.
            static let canvasWell = system("surface.canvasWell", .underPageBackgroundColor)
            /// The plate of an app alert and of the permission sheet. A system window colour takes a tint from the wallpaper (an orange one made the
            /// dark plate rgb 41,30,30, a warm brown), so the sheets paint their own neutral grey, which keeps the text at 4.5:1 and the plate
            /// the same colour on every desktop.
            static let sheet = role("surface.sheet",
                                    aqua: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                                    darkAqua: NSColor(srgbRed: 38 / 255, green: 38 / 255, blue: 40 / 255, alpha: 1),
                                    highContrastAqua: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                                    highContrastDarkAqua: NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1))
            static let all = [window, content, canvasWell]
        }

        enum Text {
            static let primary = system("text.primary", .labelColor)
            /// Deviates from `secondaryLabelColor`, which is 3.95:1 on the light window; light arms are black at 0.60 / 0.70 (5.7:1+) so the 4.5:1 floor holds in all four appearances.
            static let secondary = role("text.secondary",
                                        aqua: NSColor.black.withAlphaComponent(0.60), darkAqua: .secondaryLabelColor,
                                        highContrastAqua: NSColor.black.withAlphaComponent(0.70), highContrastDarkAqua: NSColor.white.withAlphaComponent(0.75))
            /// Disabled text is exempt from the contrast floor (WCAG 1.4.3 inactive components); the test only keeps it visible.
            static let disabled = system("text.disabled", .disabledControlTextColor)
        }

        static let accent = system("accent", .controlAccentColor)

        enum State {
            static let hover = contrast("state.hover", normal: NSColor.labelColor.withAlphaComponent(0.08), high: NSColor.labelColor.withAlphaComponent(0.16))
            static let pressed = contrast("state.pressed", normal: NSColor.labelColor.withAlphaComponent(0.16), high: NSColor.labelColor.withAlphaComponent(0.28))
            /// High contrast adds a 1 pt accent border at the call site; the fill alone only strengthens. In dark the accent needs more weight to
            /// read as the accent: at 0.20 a yellow accent over the dark window came out olive (rgb 98,89,64), so the dark arm is 0.34 (0.40 under
            /// Increase Contrast) and the fill stays a saturated accent tint, still light enough to keep text at 4.5:1.
            static let selectedFill = role("state.selected.fill",
                                           aqua: NSColor.controlAccentColor.withAlphaComponent(0.20), darkAqua: NSColor.controlAccentColor.withAlphaComponent(0.34),
                                           highContrastAqua: NSColor.controlAccentColor.withAlphaComponent(0.32), highContrastDarkAqua: NSColor.controlAccentColor.withAlphaComponent(0.40))
            static let primaryFill = system("state.primary.fill", NSColor.controlAccentColor.withAlphaComponent(1))
        }

        /// The keyboard focus ring: dark amber on the light bar, bright amber on the dark one, so it clears 3:1 against the window, the plate
        /// and the selected fill in every arm (the system ring was 1.36:1 in light and a muddy olive in dark). The shape, not only the tone,
        /// separates it from "selected": `StateStyles.focusRingWidth` / `focusRingOutset`.
        static let focusRing = role("focus.ring",
                                    aqua: NSColor(srgbRed: 140 / 255, green: 80 / 255, blue: 0, alpha: 1),
                                    darkAqua: NSColor(srgbRed: 255 / 255, green: 214 / 255, blue: 102 / 255, alpha: 1),
                                    highContrastAqua: NSColor(srgbRed: 105 / 255, green: 58 / 255, blue: 0, alpha: 1),
                                    highContrastDarkAqua: NSColor(srgbRed: 255 / 255, green: 230 / 255, blue: 150 / 255, alpha: 1))

        /// The base tint under every menu and popover plate and under the hint plate. Glass alone lets a saturated canvas through, so the
        /// text over an orange shape fell to 2.2:1; this keeps every label above 4.5:1 over the worst case, and Increase Contrast makes it opaque.
        static let menuBase = role("menu.base",
                                   aqua: NSColor(srgbRed: 250 / 255, green: 250 / 255, blue: 250 / 255, alpha: 0.88),
                                   darkAqua: NSColor(srgbRed: 30 / 255, green: 30 / 255, blue: 32 / 255, alpha: 0.90),
                                   highContrastAqua: NSColor(srgbRed: 250 / 255, green: 250 / 255, blue: 250 / 255, alpha: 1),
                                   highContrastDarkAqua: NSColor(srgbRed: 30 / 255, green: 30 / 255, blue: 32 / 255, alpha: 1))
        static let separator = system("separator", .separatorColor)
        /// Always paired with an "Error"-prefixed string or an icon (Differentiate Without Color).
        /// Deviates from `systemRed`, which is 3.3:1 on the light canvas well and 4.3:1 on the dark one; it is used as text, so each arm clears 4.5:1.
        static let feedbackError = role("feedback.error",
                                        aqua: NSColor(srgbRed: 200 / 255, green: 20 / 255, blue: 15 / 255, alpha: 1),
                                        darkAqua: NSColor(srgbRed: 255 / 255, green: 105 / 255, blue: 97 / 255, alpha: 1),
                                        highContrastAqua: NSColor(srgbRed: 176 / 255, green: 0, blue: 0, alpha: 1),
                                        highContrastDarkAqua: NSColor(srgbRed: 255 / 255, green: 120 / 255, blue: 110 / 255, alpha: 1))

        enum SwatchOutline {
            static let rest = system("swatch.outline.rest", .separatorColor)
            static let hover = system("swatch.outline.hover", NSColor.labelColor.withAlphaComponent(0.5))
        }

        /// Fixed on purpose: these sit on screenshots and arbitrary screen pixels, not on app surfaces, so they do not follow the appearance.
        enum Overlay {
            private static let scrimBase = NSColor(deviceRed: 24 / 255, green: 24 / 255, blue: 24 / 255, alpha: 0.65)
            private static func fixed(_ name: String, _ color: @autoclosure @escaping () -> NSColor, high: (() -> NSColor)? = nil) -> NSColor {
                contrast("overlay." + name, normal: color(), high: (high ?? color)())
            }
            static let scrim = fixed("scrim", scrimBase)
            static let plateFill = fixed("plateFill", NSColor.white.withAlphaComponent(0.75), high: { NSColor.white.withAlphaComponent(0.92) })
            static let plateText = fixed("plateText", .black)
            static let hudFill = fixed("hudFill", NSColor.black.withAlphaComponent(0.85))
            static let hudText = fixed("hudText", .white)
            static let hudStroke = fixed("hudStroke", NSColor.white.withAlphaComponent(0.95))
            /// A 3 pt stroke under a 1 pt inner stroke keeps the crosshair visible on light and dark pixels.
            static let crosshairOuter = fixed("crosshairOuter", NSColor.white.withAlphaComponent(0.2))
            static let crosshairInner = fixed("crosshairInner", NSColor.black.withAlphaComponent(0.4))
        }

        /// One arm of a role, as sRGB. A colour that is not one of these roles resolves under the arm's base appearance.
        static func resolve(_ color: NSColor, arm: Arm) -> NSColor {
            armsLock.lock()
            let build = registeredArms[ObjectIdentifier(color)]?[arm]
            armsLock.unlock()
            var resolved = color
            arm.baseAppearance.performAsCurrentDrawingAppearance {
                resolved = (build?() ?? color).usingColorSpace(.sRGB) ?? color
            }
            return resolved
        }

        /// The colour as the given appearance draws it: sRGB, alpha kept.
        static func resolve(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
            var resolved = color
            appearance.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB) ?? color
            }
            return resolved
        }

        /// Black or white text for a fill drawn at `alpha` over `plate`. The contrast is measured against the blended colour that is on
        /// screen, not the opaque fill. White wins when it reaches 4.5:1, then black; if neither does, the stronger of the two.
        /// Both colours resolve under the current drawing appearance.
        static func onAccent(fill: NSColor, alpha: CGFloat, over plate: NSColor) -> NSColor {
            let blended = blend(fill, alpha: alpha, over: plate)
            let white = contrastRatio(.white, blended), black = contrastRatio(.black, blended)
            if white >= 4.5 { return .white }
            if black >= 4.5 { return .black }
            return white >= black ? .white : .black
        }

        // MARK: Contrast helpers (WCAG 2.x)
        struct RGB { var red: CGFloat, green: CGFloat, blue: CGFloat }

        static func rgb(_ color: NSColor) -> (rgb: RGB, alpha: CGFloat) {
            let srgb = color.usingColorSpace(.sRGB) ?? color
            return (RGB(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent), srgb.alphaComponent)
        }

        /// `fill` drawn at `alpha` (times its own alpha) over `plate`, which is treated as opaque.
        static func blend(_ fill: NSColor, alpha: CGFloat, over plate: NSColor) -> RGB {
            let top = rgb(fill), bottom = rgb(plate).rgb
            let a = min(1, max(0, alpha)) * top.alpha
            return RGB(red: top.rgb.red * a + bottom.red * (1 - a),
                       green: top.rgb.green * a + bottom.green * (1 - a),
                       blue: top.rgb.blue * a + bottom.blue * (1 - a))
        }

        static func luminance(_ color: RGB) -> CGFloat {
            func linear(_ value: CGFloat) -> CGFloat { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        }

        static func contrastRatio(_ a: RGB, _ b: RGB) -> CGFloat {
            let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
            return (hi + 0.05) / (lo + 0.05)
        }

        /// Text drawn over an opaque background; translucent text is blended over it first.
        static func contrastRatio(_ text: NSColor, _ background: RGB) -> CGFloat {
            let backdrop = NSColor(srgbRed: background.red, green: background.green, blue: background.blue, alpha: 1)
            return contrastRatio(blend(text, alpha: 1, over: backdrop), background)
        }
    }
}

extension DesignTokens {
    /// The one product name. Menus, About, the status item and window titles read it; tools/check-brand.py holds Info.plist to it.
    enum Brand {
        static let name = "OpenSnap"
    }
}

/// The one way a pixel size is written anywhere in the app: whole pixels (half up, never below 1), no thousands separators ("2560 × 1800"),
/// so the title, the status line, History Details, the Export panel and the Photos list all read the same. It lives with the tokens
/// because every surface compiles them.
enum PixelSizeText {
    static func text(width: Int, height: Int) -> String { String(width) + " × " + String(height) }
    static func text(_ size: CGSize) -> String {
        guard size.width.isFinite, size.height.isFinite, abs(size.width) < 1e9, abs(size.height) < 1e9 else { return "Unknown size" }
        func whole(_ value: CGFloat) -> Int { max(1, Int((value + 0.5).rounded(.down))) }
        return text(width: whole(size.width), height: whole(size.height))
    }
}
