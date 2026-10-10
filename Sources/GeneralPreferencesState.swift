import AppKit

/// The choices the General and Drawing tabs of the Settings window edit. The parent owns persistence and application side effects.
@MainActor
struct GeneralPreferencesState: Equatable {
    var drawingPrecision: StrokeSmoothing
    var arrowHead: Int
    var includeApp: Bool
    var statusMenu: Int
    var showToolTips: Bool
    var showKeyboardTips: Bool

    init(drawingPrecision: StrokeSmoothing, arrowHead: Int, includeApp: Bool,
         statusMenu: Int, showToolTips: Bool = false,
         showKeyboardTips: Bool = false) {
        self.drawingPrecision = drawingPrecision
        self.arrowHead = arrowHead
        self.includeApp = includeApp
        self.statusMenu = statusMenu
        self.showToolTips = showToolTips
        self.showKeyboardTips = showKeyboardTips
    }
}
