// Standalone native tests; no windows or desktop automation.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D GENERAL_PREFERENCES_STATE_TESTS \
//   Sources/SVGPath.swift Sources/StrokeFitting.swift Sources/GeneralPreferencesState.swift \
//   tests/GeneralPreferencesStateTests.swift -o build/general-preferences-state-tests
#if GENERAL_PREFERENCES_STATE_TESTS
import AppKit

@main
@MainActor
private enum GeneralPreferencesStateTests {
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func main() {
        let initial = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2,
                                              includeApp: true, statusMenu: 0)
        expect(!initial.showToolTips && !initial.showKeyboardTips, "Existing initializer call sites default both tips off")
        let toolOnly = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2,
                       includeApp: true, statusMenu: 0, showToolTips: true)
        let keyboardOnly = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2,
                           includeApp: true, statusMenu: 0, showKeyboardTips: true)
        expect(toolOnly.showToolTips && !toolOnly.showKeyboardTips, "Keyboard tips default independently")
        expect(!keyboardOnly.showToolTips && keyboardOnly.showKeyboardTips, "Tool tips default independently")
        expect(initial != toolOnly && initial != keyboardOnly && toolOnly != keyboardOnly,
               "Equatable includes each tip preference")
        var changed = initial
        changed.drawingPrecision = .loose
        expect(changed != initial && changed.arrowHead == initial.arrowHead, "Precision is part of the state's identity")
        changed = initial; changed.arrowHead = 1
        expect(changed != initial, "Arrow head is part of the state's identity")
        changed = initial; changed.includeApp = false
        expect(changed != initial, "Snap window choice is part of the state's identity")
        changed = initial; changed.statusMenu = 1
        expect(changed != initial, "Presence is part of the state's identity")
        print("GeneralPreferencesStateTests: \(checks) checks passed")
    }
}
#endif
