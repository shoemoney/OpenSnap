// OSN-062 / T7 test 5: the announcement helper with an injected poster. Nothing is posted to the system; time is stepped by hand.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D ANNOUNCER_TESTS \
//   Sources/DesignTokens.swift Sources/Announcer.swift tests/AnnouncerTests.swift -o build/announcer-tests
#if ANNOUNCER_TESTS
import AppKit

@main
@MainActor
private enum AnnouncerTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    private struct Posted: Equatable { var text: String; var priority: NSAccessibilityPriorityLevel; var elementIsSentinel: Bool }
    private final class Sentinel {}
    private static var log: [Posted] = []
    private static var now: TimeInterval = 100
    private static let sentinel = Sentinel()

    /// A fresh Announcer: injected poster, stepped clock, a sentinel standing in for the window, no memory of earlier text.
    private static func fresh() {
        log = []; now = 100
        Announcer.reset()
        Announcer.clock = { now }
        Announcer.target = { sentinel }
        Announcer.poster = { element, text, priority in log.append(Posted(text: text, priority: priority, elementIsSentinel: (element as AnyObject) === sentinel)) }
    }

    static func main() {
        _ = NSApplication.shared
        delivery()
        rateLimit()
        priorities()
        productionPoster()
        messages()
        print("AnnouncerTests: \(checks) checks passed (nothing posted to the system)")
    }

    private static func delivery() {
        fresh()
        expect(Announcer.announce("Screenshot captured"), "the first announcement is posted")
        expect(log == [Posted(text: "Screenshot captured", priority: .medium, elementIsSentinel: true)], "the poster received the text, the default medium priority and the target element: \(log)")
        expect(!Announcer.announce(""), "an empty announcement is not posted")
        expect(!Announcer.announce("   \n"), "a blank announcement is not posted")
        expect(log.count == 1, "empty text posted nothing")
        fresh()
        expect(Announcer.announce("  Link copied  ") && log.map(\.text) == ["Link copied"], "text is trimmed before it is posted")
    }

    private static func rateLimit() {
        fresh()
        Announcer.announce("Undid Pen")
        now += 0.5
        expect(!Announcer.announce("Undid Pen"), "the same text 0.5 s later is dropped")
        now += 0.49
        expect(!Announcer.announce("Undid Pen"), "the same text 0.99 s after the first is dropped")
        expect(log.count == 1, "only the first was posted")
        now += 0.02
        expect(Announcer.announce("Undid Pen"), "the same text just over 1 s after the first goes through (state may have changed again)")
        expect(log.count == 2, "two posted in total")

        // A different text is a state change and goes through at once, even a hair later.
        fresh()
        Announcer.announce("Frame mode on")
        expect(Announcer.announce("Frame mode off"), "a different text goes through immediately")
        expect(log.map(\.text) == ["Frame mode on", "Frame mode off"], "both were posted in order")
        // Alternating chatter is still limited per text: A, B, A inside the window posts A and B once each.
        expect(!Announcer.announce("Frame mode on"), "A, B, A inside one second: the second A is dropped")
        now += 1.1
        expect(Announcer.announce("Frame mode on") && Announcer.announce("Frame mode off"), "after the window both may be posted again")
        expect(log.count == 4, "four posted in total")

        // No queue and no memory beyond the window: a dropped text is not delivered later.
        fresh()
        Announcer.announce("Upload complete. Link copied.")
        Announcer.announce("Upload complete. Link copied.")
        now += 5
        expect(log.count == 1, "a dropped announcement is never delivered later")
        // The memory is bounded: texts older than the window are forgotten.
        for index in 0..<50 { now += 2; Announcer.announce("Message \(index)") }
        expect(log.count == 51, "fifty distinct texts all went through")
        // A clock that steps backwards does not lock a text out.
        fresh()
        Announcer.announce("Redid Pen")
        now -= 10
        expect(Announcer.announce("Redid Pen"), "a clock that went backwards treats the text as new")
        Announcer.reset()
        expect(Announcer.announce("Redid Pen"), "reset forgets every text")
    }

    private static func priorities() {
        fresh()
        Announcer.announce("a", priority: .low)
        Announcer.announce("b", priority: .medium)
        Announcer.announce("c", priority: .high)
        expect(log.map(\.priority) == [.low, .medium, .high], "each priority reaches the poster unchanged: \(log.map(\.priority))")
        expect(Announcer.priority(for: "Error: the upload failed") == .high, "an error is announced at high priority")
        expect(Announcer.priority(for: "Upload complete. Link copied.") == .medium, "other messages are medium")
        // A repeat at another priority is still a repeat of the same state.
        fresh()
        Announcer.announce("Same", priority: .low)
        expect(!Announcer.announce("Same", priority: .high), "the same text at a higher priority inside the window is still dropped")
    }

    private static func productionPoster() {
        let info = Announcer.userInfo(text: "Hello", priority: .high)
        expect(info[.announcement] as? String == "Hello", "the system payload carries the text under the announcement key")
        expect(info[.priority] as? Int == NSAccessibilityPriorityLevel.high.rawValue, "the system payload carries the priority under the priority key")
        expect(info.count == 2, "nothing else is in the payload")
        // The default target is a window when there is one, else the application; it is never nil.
        _ = NSApp.setActivationPolicy(.prohibited)
        let target = Announcer.defaultTarget()
        expect(target is NSApplication || target is NSWindow, "the production target is the key or main window, else the application")
    }

    private static func messages() {
        typealias M = Announcer.Message
        expect(M.uploadStarted("Shot 1") == "Uploading Shot 1" && M.uploadStarted("") == "Uploading", "upload start names the file when it can")
        expect(M.uploadSucceeded == "Upload complete. Link copied.", "upload success says the link is copied")
        expect(M.uploadFailed("The server refused it") == "Error: The server refused it", "an upload failure begins Error:")
        expect(M.uploadFailed("Error: already prefixed") == "Error: already prefixed", "an Error: prefix is not doubled")
        expect(M.uploadFailed("") == "Error: the upload failed", "an upload failure with no reason still begins Error:")
        expect(M.captureSucceeded == "Screenshot captured", "capture success")
        expect(M.frameEntered.hasPrefix("Frame mode on") && M.frameLeft == "Frame mode off", "Frame enter and leave")
        expect(M.undone("Pen") == "Undid Pen" && M.undone("") == "Undone" && M.redone("Pen") == "Redid Pen" && M.redone("") == "Redone", "undo and redo results name the action when they can")
        for message in [M.uploadSucceeded, M.captureSucceeded, M.frameEntered, M.frameLeft, M.undone("Pen"), M.redone("Pen"), M.uploadStarted("x"), M.uploadFailed("x")] {
            expect(!message.lowercased().contains("ski" + "tch"), "no message names the retired product: \(message)")
        }
    }
}
#endif
