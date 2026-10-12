import AppKit

private typealias Typography = DesignTokens.Typography

/// The menu-bar icon: a template SF Symbol, so the system tints it for light, dark and highlighted menu bars.
/// There is no bundled picture to load; the symbol is drawn by the system.
@MainActor
enum StatusIcon {
    static let symbolName = "camera.viewfinder"
    static let name = DesignTokens.Brand.name
    /// The menu-bar item opens a menu whose first command shows or hides the editor, so that is what VoiceOver says.
    static let accessibilityLabel = "Show or hide " + name

    static func image() -> NSImage? {
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        symbol?.isTemplate = true
        return symbol
    }

    /// Icon, tooltip and spoken label. The button's target and action stay with the caller.
    static func configure(_ button: NSButton) {
        button.image = image()
        button.toolTip = name
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityHelp("")   // the tooltip is only the app name, which the spoken label already contains
    }
}

/// App-owned menus draw at body size (20 pt) instead of the system menu size.
/// The strip of menu-bar titles belongs to the system and cannot be resized, so only dropdowns are set here.
@MainActor
enum MenuTypography {
    static var font: NSFont { Typography.font(.body) }

    /// `menu` and every submenu below it.
    static func apply(to menu: NSMenu) {
        menu.font = font
        for item in menu.items { if let submenu = item.submenu { apply(to: submenu) } }
    }

    /// The menu-bar strip itself keeps the system font; each dropdown under it is set.
    static func applyToDropdowns(of menuBar: NSMenu) {
        for item in menuBar.items { if let submenu = item.submenu { apply(to: submenu) } }
    }

    /// Every menu reachable from `root`, `root` first. Pass a dropdown, not the menu-bar strip, to a font check.
    static func menus(under root: NSMenu) -> [NSMenu] {
        [root] + root.items.compactMap(\.submenu).flatMap(menus(under:))
    }

    /// Titles whose rendered size would fall under the readable minimum, with the menu that draws them.
    static func belowReadableMinimum(in root: NSMenu) -> [String] {
        var problems: [String] = []
        for menu in menus(under: root) {
            let menuPoints = menu.font.pointSize
            for item in menu.items where !item.isSeparatorItem {
                let attributed = item.attributedTitle?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                let points = attributed?.pointSize ?? menuPoints
                if points < Typography.readableMinimum { problems.append("\(menu.title)/\(item.title): \(points) pt") }
            }
        }
        return problems
    }
}
