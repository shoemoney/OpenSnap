import AppKit

/// Harness-only input fence. The audit harness never needs a real keyboard, mouse or trackpad event: it calls the responders directly
/// (`canvas.mouseDown(with:)`, `insertText`, `selection.mouseDragged(with:)`), and none of that passes through `NSApp.sendEvent`. A real
/// event that does arrive while a capture window is on screen is somebody typing or clicking into the evidence, so a local monitor
/// swallows every one of them for the life of the run. (A private message once landed in a committed capture this way.)
/// The harness also performs no pasteboard copy or paste; tools/test-eye-dump-audit-guard.py fails if one ever names `NSPasteboard.general`.
@MainActor
enum HarnessInputGuard {
    static let blockedEvents: NSEvent.EventTypeMask = [
        .keyDown, .keyUp, .flagsChanged,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved, .scrollWheel,
        .magnify, .rotate, .swipe, .smartMagnify, .pressure,
        .mouseEntered, .mouseExited, .cursorUpdate
    ]

    /// What kind of real input an event is. Typing and button presses mean somebody used the machine during the run; pointer motion alone
    /// does not: a cursor parked on the desktop makes menu tracking and the Save panel deliver moves, enters, exits and cursor updates.
    enum Kind: String, CaseIterable {
        case keyboard, buttons, pointer, scrollAndGestures
        /// Whether a run that swallowed any of this kind is flagged in safety.txt.
        var isFlagged: Bool { self != .pointer }
    }

    static func kind(of type: NSEvent.EventType) -> Kind {
        switch type {
        case .keyDown, .keyUp, .flagsChanged: return .keyboard
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged: return .buttons
        case .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate: return .pointer
        default: return .scrollAndGestures
        }
    }

    /// How many real events were swallowed, in total and per kind; `finish()` writes them to `safety/input-fence-*.json` and
    /// tools/eye-dump-audit.sh copies "keyboard N, buttons N, pointer N" into the run's safety.txt.
    private(set) static var counts: [Kind: Int] = [:]
    static var swallowedCount: Int { counts.values.reduce(0, +) }
    static func note(_ type: NSEvent.EventType) { counts[kind(of: type), default: 0] += 1 }
    static func reset() { counts = [:] }

    /// The record written beside the captures: how many real events the fence swallowed, by kind, and which kinds it covers.
    static func record() -> [String: Any] {
        ["swallowedEvents": swallowedCount,
         "byKind": Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0.rawValue, counts[$0, default: 0]) }),
         "flaggedKinds": Kind.allCases.filter(\.isFlagged).map(\.rawValue),
         "fencedEventKinds": ["keyboard", "mouse buttons and drags", "mouse moves", "mouse enter and exit", "cursor updates", "scroll", "gestures"]]
    }

    /// Installs the fence; keep the returned token for the life of the run.
    static func install() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: blockedEvents) { event in
            note(event.type)
            return nil
        }
    }

    static func remove(_ token: Any?) {
        if let token { NSEvent.removeMonitor(token) }
    }
}
