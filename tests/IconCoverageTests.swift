// OSN-045: one icon family. Every chrome icon resolves to an embedded Font Awesome Free vector (or, for a listed Free-less icon,
// to its SF Symbol), every FAIcon case has a user, every Free path parses and draws, and nothing Pro leaks into the Free data.
// Offscreen rendering and source reading only; no windows, no desktop input, no network.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D ICON_COVERAGE_TESTS \
//   Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift Sources/FontAwesomeFree.swift Sources/SVGPath.swift \
//   Sources/DesignTokens.swift tests/IconCoverageTests.swift -o build/icon-coverage-tests
#if ICON_COVERAGE_TESTS
import AppKit

@main
@MainActor
private enum IconCoverageTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    /// Icons whose only user is a control another owner still has to switch over (T5 hunks in ModernEditorChrome and App.swift,
    /// and the T7 error cue). Each leaves this list in the same change that makes a control use it; the test fails the other way too.
    private static let pendingUsers: Set<FAIcon> = [.upload, .dragHand, .warning]
    /// Icons Free cannot draw. Empty today: the four Pro-only icons use a Free stand-in. A new Pro-only icon must be listed here.
    private static let freeLess: Set<FAIcon> = []
    /// Names that exist only in Font Awesome Pro. None of them may appear as embedded Free path data.
    /// Font Awesome lets a few strokes (the eye-slash diagonal, for one) run up to 32 units past the viewBox; more than that is corrupt data.
    private static let overshoot: CGFloat = 40
    private static let proOnlyNames = ["slash-forward", "camera-viewfinder", "arrow-up-right", "text", "arrow-up-from-bracket"]

    static func main() {
        _ = NSApplication.shared
        precondition(!FontAwesomeFont.isAvailable(.regular) && !FontAwesomeFont.isAvailable(.solid), "This suite runs without Pro subsets registered")
        resolverBranches()
        everyIconHasAUser()
        freeGlyphsParseAndDraw()
        freeProSeparation()
        noticeFile()
        print("IconCoverageTests: \(checks) checks passed (offscreen; no desktop input)")
    }

    // MARK: sources

    private static func roots() -> [URL] {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var roots = [here.deletingLastPathComponent().appendingPathComponent("Sources", isDirectory: true), here]
        var parent = here
        for _ in 0..<5 { parent = parent.deletingLastPathComponent(); roots.append(parent) }
        return roots
    }

    /// Product sources only: the repository's Sources folder, or the flat test snapshot minus the test files.
    private static func productSources() -> [String: String] {
        let fm = FileManager.default
        guard let folder = roots().first(where: { fm.fileExists(atPath: $0.appendingPathComponent("FontAwesomeFree.swift").path) }),
              let names = try? fm.contentsOfDirectory(atPath: folder.path) else { expect(false, "Sources were not found next to the tests"); return [:] }
        var result: [String: String] = [:]
        for name in names where name.hasSuffix(".swift") && !name.hasSuffix("Tests.swift") && !name.hasSuffix("Cases.swift")
            && name != "TestDefaults.swift" && name != "ViewTreeAudit.swift" {
            result[name] = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        }
        return result
    }

    private static func rootFile(_ name: String) -> String? {
        for root in roots() { if let text = try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) { return text } }
        return nil
    }

    // MARK: (a) resolver branches

    private static func resolverBranches() {
        let original = ChromeIcons.freeGlyph
        defer { ChromeIcons.freeGlyph = original }
        let missing = Set(FAIcon.allCases.filter { FontAwesomeFree.glyph(for: $0, family: .regular) == nil || FontAwesomeFree.glyph(for: $0, family: .solid) == nil })
        expect(missing == freeLess, "Exactly the listed icons lack a Free vector (missing: \(missing.map(\.rawValue).sorted()))")
        for icon in FAIcon.allCases {
            for family in FAFamily.allCases {
                let resolved = ChromeIcons.resolve(icon, family: family, pointSize: 22)
                if freeLess.contains(icon) {
                    expect(resolved.source == .sfSymbol(icon.sfSymbolFallback), "\(icon)/\(family) is Free-less, so it uses its SF Symbol")
                } else {
                    expect(resolved.source == .fontAwesomeFree(icon.freeSource.name), "\(icon)/\(family) resolves to the Free vector \(icon.freeSource.name), got \(resolved.source)")
                }
                expect(resolved.image?.isTemplate == true, "\(icon)/\(family) is a template image")
            }
            // The other branch: when Free misses, every icon falls through to an SF Symbol that exists on this host.
            ChromeIcons.freeGlyph = { _, _ in nil }
            let fallback = ChromeIcons.resolve(icon, family: .regular, pointSize: 22)
            ChromeIcons.freeGlyph = original
            expect(fallback.source == .sfSymbol(icon.sfSymbolFallback) && fallback.image != nil, "\(icon) falls back to SF Symbol \(icon.sfSymbolFallback)")
        }
        expect(FAIcon.broom.sfSymbolFallback != "trash" && FAIcon.trash.sfSymbolFallback == "trash", "Wipe never falls back to the delete symbol")
        // Regular asks for the outline where Free has one; solid always gets the filled shape.
        expect(FontAwesomeFree.glyph(for: .circle, family: .regular)?.style == .regular && FontAwesomeFree.glyph(for: .circle, family: .solid)?.style == .solid,
               "Circle: regular outline, solid disc")
        expect(FontAwesomeFree.glyph(for: .toolbox, family: .regular)?.style == .solid, "An icon with no Free regular style uses solid for both families")
    }

    // MARK: (b) every case has a user

    /// FAIcon cases that a non-icon-layer source file names as an implicit member or `FAIcon.x`, on or just under a line that talks about icons.
    private static func referencedIcons() -> Set<FAIcon> {
        let layer: Set<String> = ["FontAwesomeIcons.swift", "FontAwesomeFree.swift", "ChromeIcons.swift"]
        let keyword = try! NSRegularExpression(pattern: "FAIcon|[Ii]con|make\\(")
        var found = Set<FAIcon>()
        for (name, text) in productSources() where !layer.contains(name) {
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let window = lines[max(0, index - 2)...index].joined(separator: " ")
                guard keyword.firstMatch(in: window, range: NSRange(window.startIndex..., in: window)) != nil else { continue }
                for icon in FAIcon.allCases {
                    let pattern = "(?<![A-Za-z0-9_)\\]\"])\\.\(icon)\\b(?![:(])|FAIcon\\.\(icon)\\b"
                    if line.range(of: pattern, options: .regularExpression) != nil { found.insert(icon) }
                }
            }
        }
        return found
    }

    private static func everyIconHasAUser() {
        let used = referencedIcons()
        expect(used.count >= 20, "The reference scan finds the chrome's icons (\(used.count) found); a scan that finds nothing proves nothing")
        let dead = FAIcon.allCases.filter { !used.contains($0) && !pendingUsers.contains($0) }
        expect(dead.isEmpty, "Dead FAIcon entries with no control or view using them: \(dead.map(\.rawValue)). Use them or delete them")
        let finished = pendingUsers.filter { used.contains($0) }
        expect(finished.isEmpty, "\(finished.map(\.rawValue)) now have a user: delete them from pendingUsers in IconCoverageTests")
        expect(pendingUsers.isSubset(of: Set(FAIcon.allCases)), "pendingUsers only lists real icons")
    }

    // MARK: (c) Free paths parse, sit inside their viewBox, and draw at 1x and 2x

    /// The image drawn into a bitmap of `scale` pixels per point, rows running top to bottom.
    private static func render(_ image: NSImage, scale: Int) -> NSBitmapImageRep {
        let pixels = Int(image.size.width) * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func ink(_ image: NSImage, scale: Int) -> (coverage: Int, box: (minX: Int, maxX: Int, minY: Int, maxY: Int)?, pixels: Int) {
        let rep = render(image, scale: scale), pixels = rep.pixelsWide
        var coverage = 0
        var box: (minX: Int, maxX: Int, minY: Int, maxY: Int)?
        let data = rep.bitmapData!
        for y in 0..<pixels { for x in 0..<pixels {
            let alpha = Int(data[y * rep.bytesPerRow + x * 4 + 3])
            coverage += alpha
            if alpha > 40 {
                if let b = box { box = (min(b.minX, x), max(b.maxX, x), min(b.minY, y), max(b.maxY, y)) } else { box = (x, x, y, y) }
            }
        } }
        return (coverage, box, pixels)
    }

    private static func freeGlyphsParseAndDraw() {
        expect(FontAwesomeFree.entries.count >= 30, "The Free table embeds its icons (\(FontAwesomeFree.entries.count))")
        expect(Set(FontAwesomeFree.entries.map { "\($0.style.rawValue)/\($0.name)" }).count == FontAwesomeFree.entries.count, "No Free entry is embedded twice")
        for entry in FontAwesomeFree.entries {
            let label = "\(entry.style.rawValue)/\(entry.name)"
            guard let glyph = FontAwesomeFree.glyph(named: entry.name, style: entry.style) else { expect(false, "\(label) did not parse"); continue }
            let bounds = glyph.bounds
            expect(!bounds.isNull && !bounds.isEmpty && !glyph.path.isEmpty, "\(label) parses into a non-empty path")
            let box = CGRect(x: 0, y: 0, width: glyph.viewBox.width, height: glyph.viewBox.height)
            expect(entry.viewBoxWidth > 0 && glyph.viewBox.height == 512, "\(label) viewBox is 0 0 \(entry.viewBoxWidth) 512")
            expect(box.insetBy(dx: -overshoot, dy: -overshoot).contains(bounds), "\(label) lies inside its viewBox: \(bounds) in \(box)")
        }
        for icon in FAIcon.allCases where !freeLess.contains(icon) {
            for family in FAFamily.allCases {
                guard let glyph = FontAwesomeFree.glyph(for: icon, family: family) else { expect(false, "\(icon)/\(family) has no Free glyph"); continue }
                let box = CGRect(x: 0, y: 0, width: glyph.viewBox.width, height: glyph.viewBox.height)
                expect(box.insetBy(dx: -overshoot, dy: -overshoot).contains(glyph.bounds), "\(icon)/\(family) (\(glyph.name), rotation \(icon.freeSource.rotation)) stays inside its viewBox: \(glyph.bounds)")
                guard let image = FontAwesomeFree.image(glyph, pointSize: 22) else { expect(false, "\(icon)/\(family) renders no image"); continue }
                expect(image.isTemplate && image.size.width == ceil(22 * 1.25) && image.size.height == image.size.width, "\(icon)/\(family) is a square template image sized to the point size")
                let one = ink(image, scale: 1), two = ink(image, scale: 2)
                expect(one.coverage > 0 && two.coverage > 0 && one.box != nil && two.box != nil, "\(icon)/\(family) draws ink at 1x and 2x")
                if let a = one.box, let b = two.box {
                    expect(a.minX > 0 && a.minY > 0 && a.maxX < one.pixels - 1 && a.maxY < one.pixels - 1, "\(icon)/\(family) is not clipped at 1x")
                    expect(b.minX > 0 && b.minY > 0 && b.maxX < two.pixels - 1 && b.maxY < two.pixels - 1, "\(icon)/\(family) is not clipped at 2x")
                    let width1 = a.maxX - a.minX + 1, width2 = b.maxX - b.minX + 1
                    expect(abs(width2 - 2 * width1) <= 3, "\(icon)/\(family) is redrawn at 2x, not upscaled: \(width1) px wide at 1x, \(width2) px at 2x")
                }
            }
        }
        // The two rotated icons really point where their names say: up and to the right.
        for icon in [FAIcon.arrowUpRight, .slashForward] {
            guard let glyph = FontAwesomeFree.glyph(for: icon), glyph.bounds.height > 0 else { expect(false, "\(icon) is missing"); continue }
            expect(abs(glyph.bounds.width - glyph.bounds.height) < glyph.bounds.width * 0.15, "\(icon) is a 45 degree glyph, about as tall as wide")
        }
        if let arrow = FontAwesomeFree.glyph(for: .arrowUpRight), let image = FontAwesomeFree.image(arrow, pointSize: 40) {
            let rep = render(image, scale: 1), pixels = rep.pixelsWide, half = pixels / 2
            var upperRight = 0, lowerLeft = 0
            for y in 0..<pixels { for x in 0..<pixels {
                let alpha = Int(rep.bitmapData![y * rep.bytesPerRow + x * 4 + 3])
                if x >= half && y < half { upperRight += alpha }
                if x < half && y >= half { lowerLeft += alpha }
            } }
            // The head is the heavy end of an arrow: more ink in the upper right than in the lower left.
            expect(upperRight > lowerLeft, "The arrow tool's head is in the upper right, so it points up and right (\(upperRight) vs \(lowerLeft))")
        }
        expect(FontAwesomeFree.image(FontAwesomeFree.glyph(for: .circle)!, pointSize: 0) == nil, "Non-positive sizes render nothing")
    }

    // MARK: Free / Pro separation

    private static func freeProSeparation() {
        for entry in FontAwesomeFree.entries {
            expect(!proOnlyNames.contains(entry.name), "\(entry.name) is Pro-only and must not be embedded as Free data")
            expect(entry.pathData.allSatisfy { "MmLlHhVvCcSsQqTtAaZz0123456789.,- eE+".contains($0) }, "\(entry.name) holds nothing but SVG path data")
        }
        let sources = productSources()
        guard let free = sources["FontAwesomeFree.swift"] else { return expect(false, "FontAwesomeFree.swift was not found") }
        expect(free.contains("Font Awesome Free 7.3.1") && free.contains("CC BY 4.0") && free.contains("fontawesome.com/license/free"),
               "The Free data file carries the Font Awesome Free attribution comment")
        for forbidden in ["FontAwesome7Pro", "-subset", ".ttf", ".otf", ".woff", "fontawesome-pro", "npm.fontawesome.com", "_authToken", "FONTAWESOME_TOKEN"] {
            expect(!free.contains(forbidden), "FontAwesomeFree.swift must not mention \(forbidden)")
        }
        expect(FontAwesomeFree.version == "7.3.1" && free.contains("Font Awesome Free \(FontAwesomeFree.version)"), "The pinned Free version matches its attribution")
        let token = try! NSRegularExpression(pattern: "_authToken=[0-9A-Fa-f-]{36}|FONTAWESOME[A-Z_]*TOKEN\\s*[=:]\\s*[\"']?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
        for (name, text) in sources {
            expect(token.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil, "\(name) holds no Font Awesome registry token")
        }
        // Only the Pro table names the Pro fonts, and only the dev fetch path ever loads them.
        for (name, text) in sources where name != "FontAwesomeIcons.swift" {
            expect(!text.contains("FontAwesome7Pro"), "\(name) must not name the Pro font; only FontAwesomeIcons.swift may")
        }
    }

    // MARK: the attribution

    private static func noticeFile() {
        guard let notice = rootFile("THIRD_PARTY_NOTICES.md") else { return expect(false, "THIRD_PARTY_NOTICES.md was not found; the attribution must ship") }
        for needle in ["Font Awesome Free \(FontAwesomeFree.version)", "Fonticons, Inc.", "CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/",
                       "https://fontawesome.com/license/free", "Changes made", "does not endorse"] {
            expect(notice.contains(needle), "THIRD_PARTY_NOTICES.md names \"\(needle)\"")
        }
        expect(!notice.contains("FontAwesome7Pro") && !notice.lowercased().contains("pro license"), "The notice claims nothing from Pro")
        if let build = rootFile("tools/build.sh") {
            expect(build.contains("THIRD_PARTY_NOTICES.md") && build.contains("THIRD_PARTY_NOTICES.txt"), "build.sh bundles the notice where the About window reads it")
        } else { expect(false, "tools/build.sh was not found") }
    }
}
#endif
