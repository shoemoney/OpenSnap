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

    /// How many real events were swallowed; `finish()` writes it to `safety/input-fence-*.json` and tools/eye-dump-audit.sh copies it into
    /// the run's safety.txt, so a run during which somebody touched the machine says so.
    private(set) static var swallowedCount = 0
    /// The record written beside the captures: how many real events the fence swallowed and which kinds it covers.
    static func record() -> [String: Any] {
        ["swallowedEvents": swallowedCount, "fencedEventKinds": ["keyboard", "mouse buttons and drags", "mouse moves", "mouse enter and exit", "cursor updates", "scroll", "gestures"]]
    }

    /// Installs the fence; keep the returned token for the life of the run.
    static func install() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: blockedEvents) { _ in
            swallowedCount += 1
            return nil
        }
    }

    static func remove(_ token: Any?) {
        if let token { NSEvent.removeMonitor(token) }
    }
}
