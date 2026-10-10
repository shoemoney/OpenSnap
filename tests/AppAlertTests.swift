// The app-owned alert (OSN-041 step 5, D-TEXT): readable type, NSAlert's key conventions, a sheet on the document window, async answer.
// Windows are built but never ordered on screen; the host window below records the sheet calls instead of showing a sheet.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D APP_ALERT_TESTS \
//   Sources/DesignTokens.swift Sources/AppAlert.swift tests/AppAlertTests.swift -o build/app-alert-tests
#if APP_ALERT_TESTS
import AppKit

/// Stands in for the document window: it is "on screen", and it records what AppAlert asks of it.
@MainActor
final class RecordingHost: NSWindow {
    var begun: [NSWindow] = []
    var ended: [NSWindow] = []
    var openSheet: NSWindow?
    private var handlers: [ObjectIdentifier: (NSApplication.ModalResponse) -> Void] = [:]
    override var attachedSheet: NSWindow? { openSheet }
    override func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        begun.append(sheetWindow); openSheet = sheetWindow
        handlers[ObjectIdentifier(sheetWindow)] = handler
    }
    /// Like AppKit: ending a sheet, by anyone, runs the completion handler it was begun with.
    override func endSheet(_ sheetWindow: NSWindow) { endSheet(sheetWindow, returnCode: .stop) }
    override func endSheet(_ sheetWindow: NSWindow, returnCode: NSApplication.ModalResponse) {
        ended.append(sheetWindow); if openSheet === sheetWindow { openSheet = nil }
        handlers.removeValue(forKey: ObjectIdentifier(sheetWindow))?(returnCode)
    }
}

@main
@MainActor
private enum AppAlertTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    static let discardButtons: [AppAlert.Button] = [.init(title: "Save"), .init(title: "Cancel", role: .cancel), .init(title: "Don\u{2019}t Save", role: .destructive)]

    static func main() {
        _ = NSApplication.shared
        typeAndGeometry()
        keys()
        sheetPresentation()
        answering()
        endedWithoutAButton()
        accessibility()
        contrast()
        errorAlert()
        presenterSeam()
        inlineValidation()
        print("AppAlertTests: \(checks) checks passed (windows never ordered on screen)")
    }

    /// F-J5-001: a prompt whose entry is wrong stays open and says why, instead of closing without a word.
    private static func inlineValidation() {
        let field = NSTextField(string: "abc"); field.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        let alert = AppAlert(title: "Timed Snapshot", message: "Delay in seconds", buttons: [.init(title: "OK"), .init(title: "Cancel", role: .cancel)], accessoryView: field)
        alert.validator = { $0 == 0 ? (Double(field.stringValue) == nil ? "Enter a number of seconds from 0 to 120." : nil) : nil }
        let before = alert.panel.contentView!.frame.height, button = alert.buttonViews[0].frame
        let titleTop = alert.titleLabel.frame.maxY - alert.panel.contentView!.frame.height
        alert.buttonViews[0].performClick(nil)
        expect(alert.response == nil && alert.errorLabel?.stringValue == "Error: Enter a number of seconds from 0 to 120.", "OK with a wrong entry keeps the sheet open and says why")
        guard let line = alert.errorLabel, let content = alert.panel.contentView else { return expect(false, "the error line exists") }
        expect(line.superview === content && line.textColor == DesignTokens.Palette.feedbackError && (line.font?.pointSize ?? 0) >= 20, "the line is in the sheet, in the warning colour, at the app's size")
        expect(content.frame.height > before && alert.buttonViews[0].frame == button, "the sheet grew to hold it and the buttons stayed where they were")
        expect(abs((alert.titleLabel.frame.maxY - content.frame.height) - titleTop) < 0.5, "the title kept its distance from the top")
        expect(line.frame.maxY <= field.frame.minY && line.frame.minY >= alert.buttonViews[0].frame.maxY, "the line sits between the field and the buttons: \(line.frame) \(field.frame) \(alert.buttonViews[0].frame)")
        expect(line.accessibilityLabel() == "Error: Enter a number of seconds from 0 to 120.", "VoiceOver reads it")
        alert.buttonViews[0].performClick(nil)
        let grown = content.frame.height
        expect(alert.response == nil && grown == content.frame.height, "pressing OK again does not grow the sheet again")
        field.stringValue = "7"
        alert.buttonViews[0].performClick(nil)
        expect(alert.response == .alertFirstButtonReturn, "a right entry answers OK")
        let escape = AppAlert(title: "t", buttons: [.init(title: "OK"), .init(title: "Cancel", role: .cancel)], accessoryView: field)
        escape.validator = { _ in "never" }
        escape.cancel()
        expect(escape.response == .alertSecondButtonReturn && escape.errorLabel == nil, "Cancel and Escape are never validated")
    }

    private static func host() -> RecordingHost {
        RecordingHost(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
    }

    private static func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }

    private static func key(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = [], in panel: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters.lowercased(), isARepeat: false, keyCode: keyCode)!
    }

    // MARK: type and geometry

    private static func typeAndGeometry() {
        let field = NSTextField(string: "6"); field.font = DesignTokens.Typography.font(.body); field.frame = NSRect(x: 0, y: 0, width: 512, height: 40)
        let alert = AppAlert(title: "Save your drawing?", message: "This document has changes that have not been saved.", buttons: discardButtons, accessoryView: field)
        expect((alert.titleLabel.font?.pointSize ?? 0) >= DesignTokens.Typography.readableMinimum && alert.titleLabel.font == DesignTokens.Typography.font(.headline), "The title is headline type (\(alert.titleLabel.font?.pointSize ?? 0) pt)")
        expect(alert.messageLabel.font == DesignTokens.Typography.font(.body) && alert.messageLabel.font?.pointSize == 20, "The message is 20 pt body text")
        for button in alert.buttonViews {
            expect(button.font?.pointSize == 20, "Button \(button.title) is 20 pt (\(button.font?.pointSize ?? 0))")
            expect(button.frame.height >= DesignTokens.Size.control, "Button \(button.title) is at least 36 pt tall (\(button.frame.height))")
            expect(button.frame.width >= AppAlert.minimumButtonWidth, "Button \(button.title) is wide enough to hit (\(button.frame.width))")
            let wanted = button.cell?.cellSize.width ?? .greatestFiniteMagnitude
            expect(button.frame.width >= wanted, "Button \(button.title) shows its whole title (\(button.frame.width) of \(wanted))")
        }
        for view in allViews(alert.panel.contentView!) {
            if let field = view as? NSTextField { expect((field.font?.pointSize ?? 0) >= 18, "Every text in the alert is at least 18 pt (\(field.stringValue): \(field.font?.pointSize ?? 0))") }
        }
        // Nothing overlaps or leaves the panel; buttons run along the bottom, the third apart at the leading edge.
        let content = alert.panel.contentView!.bounds
        let frames = allViews(alert.panel.contentView!).dropFirst().map(\.frame)
        for frame in frames { expect(content.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(frame) lies inside the panel \(content)") }
        let b = alert.buttonViews.map(\.frame)
        expect(b[0].maxX < content.maxX && b[1].maxX <= b[0].minX && b[2].minX < b[1].minX, "Save is rightmost, Cancel to its left, Don't Save at the leading edge")
        expect(Set(b.map(\.minY)).count == 1, "The buttons share one baseline")
        expect(alert.messageLabel.frame.minY >= b[0].maxY && field.frame.minY >= b[0].maxY && alert.titleLabel.frame.minY >= field.frame.maxY, "Title, message and field stack above the buttons")
        expect(alert.panel.contentView!.frame.width >= AppAlert.width, "The panel is at least the standard width")
        // A long message stays on screen: it is capped, not allowed to grow the sheet past a screen.
        let long = AppAlert(title: "Could not upload the picture", message: String(repeating: "The server answered that the request could not be completed. ", count: 40), buttons: [.init(title: "OK")])
        expect(long.panel.contentView!.frame.height < 600, "A very long message does not make a sheet taller than 600 pt (\(long.panel.contentView!.frame.height))")
        expect(long.messageLabel.maximumNumberOfLines == 12 && long.messageLabel.accessibilityLabel() == long.message, "...and VoiceOver still gets all of it")
        // Long text wraps onto as many lines as it needs (up to the cap), and the frame is tall enough for all of them.
        let oneLine = AppAlert(title: "Done", message: "Short.", buttons: [.init(title: "OK")])
        let wrapped = AppAlert(title: "Upload to Example S3 failed: the connection was refused (stub, no network was used) and nothing was sent.",
                               message: "The server answered that the request could not be completed. Try again, or choose another destination in Settings.", buttons: [.init(title: "OK")])
        let line = DesignTokens.Typography.font(.headline).boundingRectForFont.height
        expect(wrapped.titleLabel.frame.height >= 2 * line * 0.8 && wrapped.titleLabel.frame.height > oneLine.titleLabel.frame.height * 1.8, "A long title wraps to a second line instead of being cut (\(wrapped.titleLabel.frame.height) vs \(oneLine.titleLabel.frame.height))")
        expect(wrapped.messageLabel.frame.height > oneLine.messageLabel.frame.height * 1.8, "A message that needs two lines gets two (\(wrapped.messageLabel.frame.height) vs \(oneLine.messageLabel.frame.height))")
        expect(long.messageLabel.frame.height > oneLine.messageLabel.frame.height * 6, "A very long message shows many lines before it is cut (\(long.messageLabel.frame.height))")
        // An empty message leaves no gap.
        let bare = AppAlert(title: "Done", message: "", buttons: [.init(title: "OK")])
        expect(bare.messageLabel.superview == nil, "No message, no empty label")
    }

    // MARK: keys

    private static func keys() {
        func answered(_ send: (AppAlert) -> Void) -> Int? {
            let alert = AppAlert(title: "Save your drawing?", buttons: discardButtons)
            send(alert)
            return alert.response.map { $0.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue }
        }
        func perform(_ event: @escaping (NSWindow) -> NSEvent) -> (AppAlert) -> Void {
            { alert in _ = alert.panel.contentView?.performKeyEquivalent(with: event(alert.panel)) }
        }
        expect(answered(perform { key("\r", keyCode: 36, in: $0) }) == 0, "Return answers the first button, Save")
        expect(answered(perform { key("\u{1b}", keyCode: 53, in: $0) }) == 1, "Escape answers Cancel")
        expect(answered(perform { key("d", keyCode: 2, flags: .command, in: $0) }) == 2, "Command-D answers Don't Save")
        expect(answered(perform { key("d", keyCode: 2, in: $0) }) == nil, "D alone answers nothing")
        expect(answered(perform { key("x", keyCode: 7, flags: .command, in: $0) }) == nil, "Another key answers nothing")
        expect(answered { $0.panel.cancelOperation(nil) } == 1, "cancelOperation, which Escape becomes in a text field, answers Cancel")
        // Clicks.
        for index in 0..<3 { expect(answered { $0.buttonViews[index].performClick(nil) } == index, "Clicking button \(index) answers \(index)") }
        // The key equivalents, as set.
        let alert = AppAlert(title: "t", buttons: discardButtons)
        expect(alert.buttonViews.map(\.keyEquivalent) == ["\r", "\u{1b}", "d"] && alert.buttonViews[2].keyEquivalentModifierMask == .command, "Return, Escape and Command-D, in button order")
        expect(alert.panel.defaultButtonCell === alert.buttonViews[0].cell, "The first button is the panel's default button")
        // ASCII apostrophe too; a button called Cancel is Cancel without a role.
        let ascii = AppAlert(title: "t", buttons: [.init(title: "Save"), .init(title: "Don't Save"), .init(title: "Cancel")])
        expect(ascii.buttonViews[1].keyEquivalent == "d" && ascii.buttonViews[2].keyEquivalent == "\u{1b}", "A straight apostrophe is still Don't Save; the title Cancel is Cancel")
        // One OK: Return and Escape both answer it. Two buttons and no Cancel: Escape answers nothing, as in NSAlert.
        expect(answered { _ in } == nil, "Nothing is answered until a key or click")
        let ok = AppAlert(title: "t", buttons: [.init(title: "OK")]); ok.panel.cancelOperation(nil)
        expect(ok.response == .alertFirstButtonReturn, "Escape answers a lone OK")
        let noCancel = AppAlert(title: "t", buttons: [.init(title: "Delete", role: .destructive), .init(title: "Keep")]); noCancel.panel.cancelOperation(nil)
        expect(noCancel.response == nil, "With no Cancel button Escape does not choose for the user")
        expect(noCancel.buttonViews[0].hasDestructiveAction && !noCancel.buttonViews[1].hasDestructiveAction, "Destructive styling is only on the destructive button")
        // Return in a field with a default button: the first responder is the field, the default button still answers Return.
        let field = NSTextField(string: "x"); field.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        let withField = AppAlert(title: "Rename", buttons: [.init(title: "OK"), .init(title: "Cancel", role: .cancel)], accessoryView: field)
        expect(withField.panel.initialFirstResponder === field, "A prompt starts in its text field")
    }

    // MARK: sheet

    private static func sheetPresentation() {
        let saved = AppAlert.hostIsPresentable
        AppAlert.hostIsPresentable = { _ in true }
        defer { AppAlert.hostIsPresentable = saved }
        let window = host()
        var answers: [NSApplication.ModalResponse] = []
        let alert = AppAlert(title: "Save your drawing?", buttons: discardButtons)
        alert.present(on: window) { answers.append($0) }
        expect(window.begun == [alert.panel] && window.attachedSheet === alert.panel, "The alert is a sheet on the document window")
        expect(AppAlert.presentedAlerts == [alert] && answers.isEmpty, "It does not block: present returned and nothing is answered yet")
        // A second alert while the first is up hangs from the first sheet.
        let second = AppAlert(title: "Upload failed", buttons: [.init(title: "OK")])
        expect(AppAlert.sheetParent(of: window) === alert.panel, "A new alert hangs from the topmost sheet")
        second.present(on: window) { answers.append($0) }
        expect(AppAlert.presentedAlerts == [alert, second], "Both are on screen, oldest first")
        second.buttonViews[0].performClick(nil)
        alert.buttonViews[2].performClick(nil)
        expect(answers == [.alertFirstButtonReturn, .alertThirdButtonReturn], "Each answer arrives once, in the order given")
        expect(AppAlert.presentedAlerts.isEmpty && window.ended.contains(alert.panel), "Answered alerts leave the screen and release the host window")
        // F-J5-002: a sheet hung from a window that is not key still takes the keys, so Return and Command-D answer it wherever it hangs.
        let savedActive = AppAlert.appIsActive
        defer { AppAlert.appIsActive = savedActive }
        AppAlert.appIsActive = { true }
        let history = host(), discard = AppAlert(title: "Save your drawing?", buttons: discardButtons)
        var discardAnswers: [NSApplication.ModalResponse] = []
        discard.present(on: history) { discardAnswers.append($0) }
        expect(history.attachedSheet === discard.panel && discard.panel.keyRequests == 1, "A sheet on a window that is not key asks to become key (\(discard.panel.keyRequests))")
        expect(discard.panel.contentView?.performKeyEquivalent(with: key("d", keyCode: 2, flags: .command, in: discard.panel)) == true && discardAnswers == [.alertThirdButtonReturn],
               "Command-D answers Don't Save on a sheet hung from History or Settings, as on the editor")
        AppAlert.appIsActive = { false }
        let quiet = AppAlert(title: "t", buttons: [.init(title: "OK")]); quiet.present(on: history) { _ in }
        expect(quiet.panel.keyRequests == 0, "An app that is not active is not made to grab the keys")
        quiet.dismiss(withButton: 0)
        // A window that cannot carry a sheet (hidden, in the Dock) gets no sheet.
        AppAlert.hostIsPresentable = { _ in false }
        expect(AppAlert.sheetParent(of: window) == nil && AppAlert.sheetParent(of: nil) == nil, "No presentable window, no sheet parent")
    }

    private static func answering() {
        let saved = AppAlert.hostIsPresentable
        AppAlert.hostIsPresentable = { _ in true }
        defer { AppAlert.hostIsPresentable = saved }
        let window = host()
        var count = 0, last: NSApplication.ModalResponse?
        let alert = AppAlert(title: "Delete this web post?", buttons: [.init(title: "Delete from Web", role: .destructive), .init(title: "Cancel", role: .cancel)])
        alert.present(on: window) { count += 1; last = $0 }
        alert.dismiss(withButton: 1)
        alert.dismiss(withButton: 0)
        alert.buttonViews[0].performClick(nil)
        alert.panel.cancelOperation(nil)
        expect(count == 1 && last == .alertSecondButtonReturn && alert.response == .alertSecondButtonReturn, "However many times it is pressed, it answers once, with the first answer")
        expect(window.ended == [alert.panel], "The sheet ends once")
        // Presenting twice shows once.
        let twice = AppAlert(title: "t")
        var seen = 0
        twice.present(on: window) { _ in seen += 1 }
        twice.present(on: window) { _ in seen += 100 }
        twice.dismiss(withButton: 0)
        expect(seen == 1 && window.begun.filter { $0 === twice.panel }.count == 1, "Presenting the same alert twice shows it once")
        expect(AppAlert(title: "t").response == nil, "An alert nobody has answered has no response")
        // Out-of-range dismissals are ignored.
        let odd = AppAlert(title: "t", buttons: [.init(title: "OK")]); odd.dismiss(withButton: 5)
        expect(odd.response == nil, "A button that does not exist answers nothing")
    }

    // MARK: ended without a button

    /// Every way a sheet can end answers its completion once, as Cancel, and leaves nothing on screen (the quit barrier depends on it).
    private static func endedWithoutAButton() {
        let saved = AppAlert.hostIsPresentable
        AppAlert.hostIsPresentable = { _ in true }
        defer { AppAlert.hostIsPresentable = saved }
        let cancelIndex = NSApplication.ModalResponse.alertSecondButtonReturn
        // endSheet from outside (nobody pressed a button).
        let window = host()
        var answers: [NSApplication.ModalResponse] = []
        let alert = AppAlert(title: "Save your drawing?", buttons: discardButtons)
        alert.present(on: window) { answers.append($0) }
        window.endSheet(alert.panel)
        expect(answers == [cancelIndex] && alert.response == cancelIndex, "endSheet with no button answers Cancel once (\(answers))")
        expect(AppAlert.presentedAlerts.isEmpty && window.attachedSheet == nil, "...and the alert is no longer presented")
        alert.dismiss(withButton: 0); alert.panel.cancelOperation(nil)
        expect(answers == [cancelIndex], "A late press after the sheet ended does not answer a second time")
        // The window the sheet hangs from closes.
        let closing = host()
        var closedAnswers: [NSApplication.ModalResponse] = []
        let underClose = AppAlert(title: "Rename", buttons: [.init(title: "OK"), .init(title: "Cancel", role: .cancel)])
        underClose.present(on: closing) { closedAnswers.append($0) }
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: closing)
        expect(closedAnswers == [.alertSecondButtonReturn] && AppAlert.presentedAlerts.isEmpty, "Closing the host window answers Cancel once and clears the alert (\(closedAnswers))")
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: closing)
        expect(closedAnswers == [.alertSecondButtonReturn], "A second close notification does not answer again")
        // The alert's own panel closes.
        let own = host()
        var ownAnswers: [NSApplication.ModalResponse] = []
        let closedPanel = AppAlert(title: "Upload failed", buttons: [.init(title: "OK")])
        closedPanel.present(on: own) { ownAnswers.append($0) }
        closedPanel.panel.close()
        expect(ownAnswers == [.alertFirstButtonReturn] && AppAlert.presentedAlerts.isEmpty, "Closing the alert's panel answers the only button once (\(ownAnswers))")
        // No Cancel button: the sheet ending never picks the destructive choice.
        let guarded = host()
        var guardedAnswers: [NSApplication.ModalResponse] = []
        let noCancel = AppAlert(title: "Delete?", buttons: [.init(title: "Delete", role: .destructive), .init(title: "Keep")])
        noCancel.present(on: guarded) { guardedAnswers.append($0) }
        guarded.endSheet(noCancel.panel)
        expect(guardedAnswers == [.cancel] && guardedAnswers != [.alertFirstButtonReturn], "Without a Cancel button, an ended sheet answers plain cancel, never the first (destructive) button")
        // A button still answers with its own response and the end of the sheet that follows does not answer again.
        let pressed = host()
        var pressedAnswers: [NSApplication.ModalResponse] = []
        let normal = AppAlert(title: "Save your drawing?", buttons: discardButtons)
        normal.present(on: pressed) { pressedAnswers.append($0) }
        normal.buttonViews[2].performClick(nil)
        expect(pressedAnswers == [.alertThirdButtonReturn] && pressed.ended == [normal.panel], "A button answers with its own response; the sheet ending after it adds nothing")
    }

    // MARK: accessibility

    private static func accessibility() {
        let saved = AppAlert.hostIsPresentable
        AppAlert.hostIsPresentable = { _ in true }
        defer { AppAlert.hostIsPresentable = saved }
        let window = host()
        let alert = AppAlert(title: "Move archived drawings to Trash?", message: "The selected copies will move to Trash.",
                             buttons: [.init(title: "Move to Trash", role: .destructive), .init(title: "Cancel", role: .cancel)])
        alert.present(on: window) { _ in }
        expect(alert.panel.accessibilityRole() == .sheet, "A presented alert is a sheet to VoiceOver (\(String(describing: alert.panel.accessibilityRole())))")
        expect(alert.panel.accessibilityLabel() == alert.title && alert.panel.accessibilityHelp() == alert.message, "It is labelled with its question and described by its message")
        expect(alert.panel.initialFirstResponder === alert.buttonViews[0] && alert.panel.defaultButtonCell === alert.buttonViews[0].cell, "The default button has the focus")
        expect(alert.buttonViews.map { $0.accessibilityLabel() } == ["Move to Trash", "Cancel"], "Every button is labelled with its title")
        expect(alert.titleLabel.accessibilityLabel() == alert.title && alert.messageLabel.accessibilityLabel() == alert.message, "Title and message are read as written")
        alert.dismiss(withButton: 1)
    }

    // MARK: contrast

    /// The sheet's title and message read on the sheet's window colour in light, dark and both Increase Contrast arms.
    private static func contrast() {
        let field = NSTextField(string: "Name"); field.font = DesignTokens.Typography.font(.body); field.frame = NSRect(x: 0, y: 0, width: 512, height: 40)
        for alert in [AppAlert(title: "Save your drawing?", message: "This document has changes that have not been saved.", buttons: discardButtons),
                      AppAlert(title: "Rename", message: "Document name", buttons: [.init(title: "OK"), .init(title: "Cancel", role: .cancel)], accessoryView: field)] {
            let content = alert.panel.contentView!
            for (name, appearance) in ContrastProbe.appearances {
                let reading = ContrastProbe.measure(content, appearance: appearance, plateAt: NSPoint(x: 3, y: 3),
                                                    textFrames: [alert.titleLabel.frame, alert.messageLabel.frame], plate: alert.panel.backgroundColor)
                expect(reading.plateOpaque, "The sheet sits on an opaque window colour (\(alert.title), \(name))")
                expect(reading.textRatios[0] >= 4.5 && reading.textRatios[1] >= 4.5,
                       "The title and message read at 4.5:1 on the sheet (\(alert.title), \(name): \(reading.textRatios))")
            }
        }
    }

    // MARK: error and seam

    private static func errorAlert() {
        let described = NSError(domain: "T", code: 1, userInfo: [NSLocalizedDescriptionKey: "The file could not be saved.", NSLocalizedRecoverySuggestionErrorKey: "Choose another location."])
        let alert = AppAlert(error: described)
        expect(alert.title == "The file could not be saved." && alert.message == "Choose another location." && alert.buttons == [.init(title: "OK")], "An error alert shows its description and recovery suggestion with one OK")
        let plain = AppAlert(error: NSError(domain: "T", code: 2, userInfo: [NSLocalizedDescriptionKey: "Upload failed"]))
        expect(plain.title == "Upload failed" && plain.message.isEmpty, "Without a suggestion the message is empty")
    }

    private static func presenterSeam() {
        var asked: [(String, NSWindow?)] = []
        AppAlert.presenter = { alert, window, reply in asked.append((alert.title, window)); reply(.alertSecondButtonReturn) }
        defer { AppAlert.presenter = nil }
        let window = host()
        var got: NSApplication.ModalResponse?
        AppAlert(title: "Asked").present(on: window) { got = $0 }
        expect(asked.count == 1 && asked[0].0 == "Asked" && asked[0].1 === window && got == .alertSecondButtonReturn && window.begun.isEmpty, "The seam receives the alert and window and no real sheet is shown")
    }
}
#endif
