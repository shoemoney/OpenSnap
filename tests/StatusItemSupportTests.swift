// Status-bar icon, app-owned menu text size, and the source gate that keeps bundled artwork lookups out of Sources/.
// No windows, no status item, no desktop input.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D STATUS_ITEM_TESTS \
//   Sources/DesignTokens.swift Sources/StatusItemSupport.swift tests/StatusItemSupportTests.swift -o build/status-item-tests
#if STATUS_ITEM_TESTS
import AppKit

@main
@MainActor
private enum StatusItemSupportTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    static func main() {
        _ = NSApplication.shared
        icon()
        menuFonts()
        artworkGate()
        print("StatusItemSupportTests: \(checks) checks passed (no status item, no windows)")
    }

    private static func icon() {
        guard let image = StatusIcon.image() else { return expect(false, "The status icon resolved on this host") }
        expect(image.isTemplate, "The status icon is a template image, so the system tints it for light, dark and highlighted bars")
        expect(image.size.width > 0 && image.size.height > 0 && !image.representations.isEmpty, "The status icon has drawable content")
        expect(image.accessibilityDescription == DesignTokens.Brand.name, "The image carries the product name for accessibility")

        let button = NSButton(title: "", target: nil, action: nil)
        StatusIcon.configure(button)
        expect(button.image?.isTemplate == true && (button.image?.size.width ?? 0) > 0, "configure() installs the template icon on the button")
        expect(button.toolTip == "OpenSnap", "The tooltip is the product name")
        expect(button.accessibilityLabel() == "Show or hide OpenSnap" && StatusIcon.accessibilityLabel == "Show or hide " + StatusIcon.name, "The spoken label says what the item does (OSN-062), and it still names the product")
        expect(!(button.accessibilityLabel() ?? "").lowercased().contains(["ski", "tch"].joined()), "No retired name on the status item")
    }

    private static func item(_ title: String, _ submenu: NSMenu? = nil) -> NSMenuItem {
        let made = NSMenuItem(title: title, action: submenu == nil ? NSSelectorFromString("noop") : nil, keyEquivalent: "")
        made.submenu = submenu
        return made
    }

    private static func menuFonts() {
        let leaf = NSMenu(title: "Leaf"); leaf.addItem(item("Deep"))
        let inner = NSMenu(title: "Inner"); inner.addItem(item("Mid")); inner.addItem(.separator()); inner.addItem(item("Sub", leaf))
        let root = NSMenu(title: "Root"); root.addItem(item("One")); root.addItem(item("More", inner))
        expect(MenuTypography.menus(under: root).map(\.title) == ["Root", "Inner", "Leaf"], "The walker visits the menu and every submenu, outermost first")
        expect(MenuTypography.belowReadableMinimum(in: root).count == 5, "Untouched system menus (13 pt) are all reported: \(MenuTypography.belowReadableMinimum(in: root))")

        MenuTypography.apply(to: root)
        expect(MenuTypography.menus(under: root).allSatisfy { $0.font.pointSize == 20 }, "apply(to:) sets body size (20 pt) on every level")
        expect(MenuTypography.belowReadableMinimum(in: root).isEmpty, "Nothing is reported after apply")

        // An attributed title overrides the menu font for that row, so the walker must look at it too.
        let small = item("Tiny"); small.attributedTitle = NSAttributedString(string: "Tiny", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        leaf.addItem(small)
        expect(MenuTypography.belowReadableMinimum(in: root) == ["Leaf/Tiny: 12.0 pt"], "A row drawn smaller than the menu font is caught")
        leaf.removeItem(small)

        let bar = NSMenu(title: "Bar"), barTop = item("Top", NSMenu(title: "Dropdown"))
        barTop.submenu?.addItem(item("Row")); bar.addItem(barTop)
        let barFont = bar.font.pointSize
        MenuTypography.applyToDropdowns(of: bar)
        expect(barTop.submenu?.font.pointSize == 20 && bar.font.pointSize == barFont,
               "The dropdowns are set; the menu-bar strip itself (system-owned) is left alone")
    }

    // MARK: Source gate (OSN-023): no bundled artwork lookups in Sources/

    /// Lines that load bundled artwork: NSImage(named:), Bundle image lookups, or a resource URL with a picture extension.
    static func artworkLookups(in text: String) -> [String] {
        let patterns = [#"NSImage\s*\(\s*named\s*:"#, #"\.image\s*\(\s*forResource"#,
                        #"forResource\s*:[^)]*withExtension\s*:\s*"(png|pdf|tiff?|jpe?g|icns|gif)""#,
                        #"forResource\s*:\s*"[^"]*\.(png|pdf|tiff?|jpe?g|icns|gif)""#]
        let regexes = patterns.map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        var found: [String] = []
        for line in text.components(separatedBy: "\n") {
            let code = line.components(separatedBy: "//").first ?? line
            let range = NSRange(code.startIndex..., in: code)
            if regexes.contains(where: { $0.firstMatch(in: code, range: range) != nil }) { found.append(line.trimmingCharacters(in: .whitespaces)) }
        }
        return found
    }

    private static func artworkGate() {
        expect(artworkLookups(in: #"let a = NSImage(named: "Icon")"#).count == 1, "Gate flags NSImage(named:)")
        expect(artworkLookups(in: #"let u = Bundle.main.url(forResource: "Tool", withExtension: "png")"#).count == 1, "Gate flags a .png resource URL")
        expect(artworkLookups(in: #"bundle.url(forResource: "Doc", withExtension: "PDF")"#).count == 1, "Gate flags a .pdf resource URL")
        expect(artworkLookups(in: #"Bundle.main.image(forResource: "Tool")"#).count == 1, "Gate flags Bundle.image(forResource:)")
        expect(artworkLookups(in: #"Bundle.main.url(forResource: "LICENSE", withExtension: "txt")"#).isEmpty, "The bundled license text is not artwork")
        expect(artworkLookups(in: #"bundle.url(forResource: family.resourceName, withExtension: "ttf")"#).isEmpty, "A font resource is not artwork")
        expect(artworkLookups(in: #"let a = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)"#).isEmpty, "System symbols are allowed")
        expect(artworkLookups(in: #"// NSImage(named: "Old") was removed"#).isEmpty, "A comment is not a lookup")

        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let candidates = [here, here.deletingLastPathComponent().appendingPathComponent("Sources", isDirectory: true)]
        guard let directory = candidates.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("App.swift").path) }),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "swift" && !$0.lastPathComponent.hasSuffix("Tests.swift") && !$0.lastPathComponent.hasPrefix("AppSafety") && $0.lastPathComponent != "TestDefaults.swift" }),
              files.count > 20 else { return expect(false, "Sources/ was not found next to the tests; the artwork gate must not skip") }
        var offenders: [String] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { offenders.append(file.lastPathComponent + ": unreadable"); continue }
            offenders += artworkLookups(in: text).map { file.lastPathComponent + ": " + $0 }
        }
        expect(offenders.isEmpty, "Sources/ loads bundled artwork: \(offenders)")
    }
}
#endif
