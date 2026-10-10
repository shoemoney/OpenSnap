import AppKit

enum ChromeIconSource: Equatable { case fontAwesome(FAFamily), fontAwesomeFree(String), sfSymbol(String), none }

/// One icon, one fallback chain: Font Awesome Pro glyph (dev builds that bundle the subsets), then the embedded Font Awesome
/// Free vector (every release build), then SF Symbol, then nothing.
@MainActor
enum ChromeIcons {
    struct Resolved { let image: NSImage?; let source: ChromeIconSource }

    /// Test seam: lets tests force the SF Symbol branch to miss.
    static var symbolName: (FAIcon) -> String = { $0.sfSymbolFallback }

    /// Test seam: lets tests force the Free branch to miss, as it does for an icon Free does not have.
    static var freeGlyph: (FAIcon, FAFamily) -> FontAwesomeFree.Glyph? = { FontAwesomeFree.glyph(for: $0, family: $1) }

    static func resolve(_ icon: FAIcon, family: FAFamily = .regular, pointSize: CGFloat = 22) -> Resolved {
        if let image = FontAwesomeIcons.image(icon, family: family, pointSize: pointSize) {
            return Resolved(image: image, source: .fontAwesome(family))
        }
        if let glyph = freeGlyph(icon, family), let image = FontAwesomeFree.image(glyph, pointSize: pointSize) {
            return Resolved(image: image, source: .fontAwesomeFree(glyph.name))
        }
        let name = symbolName(icon)
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let image = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) ?? symbol
            image.isTemplate = true
            return Resolved(image: image, source: .sfSymbol(name))
        }
        return Resolved(image: nil, source: .none)
    }
}
