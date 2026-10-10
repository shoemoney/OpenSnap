import AppKit

/// VoiceOver announcements for events that have no focus change to carry them (OSN-062, T7, R10).
///
/// `Announcer.announce(_:priority:)` posts `NSAccessibility.announcementRequested` through an injectable poster. It is rate-limited to
/// state changes: the same text within one second is dropped (a repeated click or a double notification would otherwise be read out
/// twice), while a different text always goes through at once. There is no queue and no timer: the only state is when each recent text
/// was last posted, and entries older than the window are forgotten on the next call.
///
/// The App owns the call sites. Each one is a single line at the point the state actually changes:
///   upload start / success / failure   the upload state change in AppDelegate (Message.uploadStarted / uploadSucceeded / uploadFailed)
///   capture success                    where a finished capture opens in the editor (Message.captureSucceeded)
///   Frame enter / leave                enterFrame / leaveFrame (Message.frameEntered / frameLeft)
///   Undo / Redo result                 after the undo manager acts (Message.undone / redone)
@MainActor
enum Announcer {
    typealias Priority = NSAccessibilityPriorityLevel
    /// Delivers one announcement to one accessibility element.
    typealias Poster = @MainActor (_ element: Any, _ text: String, _ priority: Priority) -> Void

    /// The same text inside this many seconds is a repeat, not a state change.
    static let repeatWindow: TimeInterval = 1

    /// What `NSAccessibility.post` receives for an announcement.
    static func userInfo(text: String, priority: Priority) -> [NSAccessibility.NotificationUserInfoKey: Any] {
        [.announcement: text, .priority: priority.rawValue]
    }

    /// The production poster. A test replaces it.
    static var poster: Poster = { element, text, priority in
        NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: userInfo(text: text, priority: priority))
    }
    /// The element the announcement is posted for: the key window, else the main window, else the application.
    static var target: @MainActor () -> Any = { defaultTarget() }
    static func defaultTarget() -> Any {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow { return window }
        return NSApp as Any
    }
    /// Seconds on a monotonic clock. A test replaces it to step time without sleeping.
    static var clock: @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    private static var recent: [String: TimeInterval] = [:]

    /// Posts `text` unless the same text was posted within `repeatWindow`. Returns whether it was posted.
    @discardableResult
    static func announce(_ text: String, priority: Priority = .medium) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let now = clock()
        recent = recent.filter { now - $0.value < repeatWindow && now >= $0.value }
        if recent[text] != nil { return false }
        recent[text] = now
        poster(target(), text, priority)
        return true
    }

    /// Forgets what was posted, so the next announcement of any text goes through.
    static func reset() { recent.removeAll() }

    /// The wording of the announcements the App makes, in one place so the sentences stay consistent. Errors begin "Error:" like every
    /// other error in the app, and are the only ones announced at high priority.
    enum Message {
        static func uploadStarted(_ name: String) -> String { name.isEmpty ? "Uploading" : "Uploading \(name)" }
        static let uploadSucceeded = "Upload complete. Link copied."
        static func uploadFailed(_ reason: String) -> String { reason.hasPrefix("Error:") ? reason : "Error: " + (reason.isEmpty ? "the upload failed" : reason) }
        static let captureSucceeded = "Screenshot captured"
        static let frameEntered = "Frame mode on. Drag to choose the area to capture."
        static let frameLeft = "Frame mode off"
        static func undone(_ action: String) -> String { action.isEmpty ? "Undone" : "Undid \(action)" }
        static func redone(_ action: String) -> String { action.isEmpty ? "Redone" : "Redid \(action)" }
    }

    /// The priority each kind of message is announced at.
    static func priority(for message: String) -> Priority { message.hasPrefix("Error:") ? .high : .medium }
}
