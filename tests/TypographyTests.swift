// Pure AppKit font checks: no windows, no NSApplication, no desktop input.
// rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D TYPOGRAPHY_TESTS \
//   Sources/DesignTokens.swift tests/TypographyTests.swift -o /tmp/opensnap-typography-tests
#if TYPOGRAPHY_TESTS
import AppKit

@main
private enum TypographyTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
        checks += 1
    }

    static func main() throws {
        typealias T = DesignTokens.Typography
        try expect(T.readableMinimum == 18 && T.readableDefault == 20, "readable floor 18, default 20")
        try expect(T.Style.allCases.count == 8, "eight styles: a new one needs a size decision here")
        for style in T.Style.allCases {
            try expect(T.font(style).pointSize >= T.readableMinimum, "\(style) is \(T.font(style).pointSize) pt, under the 18 pt floor")
        }
        try expect(T.font(.body).pointSize == 20, "body is 20")
        let atFloor = T.Style.allCases.filter { T.font($0).pointSize == 18 }
        try expect(Set(atFloor.map { "\($0)" }) == ["caption", "numeric"], "only caption and numeric sit at 18, got \(atFloor)")
        try expect(T.font(.bodyStrong).pointSize == 20 && T.font(.hud).pointSize == 20, "bodyStrong and hud are 20")
        try expect(T.font(.headline).pointSize == 22 && T.font(.title).pointSize == 26 && T.font(.countdown).pointSize == 160, "headline 22, title 26, countdown 160")
        try expect(T.iconRegular == 22 && T.iconPrimary == 26 && T.iconInline == 20, "icon sizes")

        // weights and numerals
        func weight(_ style: T.Style) -> CGFloat {
            (T.font(style).fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? .nan
        }
        try expect(weight(.bodyStrong) > weight(.body), "bodyStrong is heavier than body")
        try expect(weight(.hud) > weight(.body) && weight(.hud) < weight(.bodyStrong), "hud is medium")
        try expect(weight(.countdown) > weight(.title), "countdown is the heaviest")
        func width(_ text: String, _ font: NSFont) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        try expect(abs(width("1111", T.font(.numeric)) - width("8888", T.font(.numeric))) < 0.01, "numeric digits are tabular")
        try expect(abs(width("1111", .systemFont(ofSize: 18)) - width("8888", .systemFont(ofSize: 18))) > 1, "plain system digits are not, so the check can tell the difference")

        // floored
        try expect(T.floored(.systemFont(ofSize: 9)).pointSize == 18, "floored(9) is 18")
        try expect(T.floored(nil).pointSize == 20, "floored(nil) is 20")
        try expect(T.floored(.systemFont(ofSize: 18)).pointSize == 18 && T.floored(.systemFont(ofSize: 31)).pointSize == 31, "floored leaves readable sizes alone")
        let raised = T.floored(.boldSystemFont(ofSize: 12))
        try expect(raised.pointSize == 18 && NSFontManager.shared.traits(of: raised).contains(.boldFontMask), "floored keeps the face when it raises the size")

        // attributes
        let attributes = T.attributes(.caption, color: .systemPink)
        try expect((attributes[.font] as? NSFont)?.pointSize == 18 && (attributes[.foregroundColor] as? NSColor) == .systemPink, "attributes carry the style font and colour")
        try expect((T.attributes(.body)[.foregroundColor] as? NSColor) == .labelColor, "attributes default to labelColor")

        // apply
        let field = NSTextField(labelWithString: "x")
        field.font = .systemFont(ofSize: 11)
        T.apply(.body, to: field)
        try expect(field.font?.pointSize == 20 && field.cell?.font?.pointSize == 20, "apply sets control and cell font")
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["One", "Two"])
        popup.font = .systemFont(ofSize: 11)
        popup.menu?.font = .systemFont(ofSize: 11)
        T.apply(.bodyStrong, to: popup)
        try expect(popup.font?.pointSize == 20 && popup.cell?.font?.pointSize == 20 && popup.menu?.font.pointSize == 20, "apply sets popup button, cell and menu fonts")
        print("TypographyTests: \(checks) checks passed")
    }
}
#endif
