// The screenshot harness's input fence classifies every real event it swallows: typing and button presses flag a run, pointer motion from a
// parked cursor (menu tracking, the Save panel) does not. No windows, no real events: the classifier is fed event types directly.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D EYE_DUMP_INPUT_GUARD_TESTS \
//   Sources/EyeDumpAuditInputGuard.swift tests/EyeDumpInputGuardTests.swift -o /tmp/opensnap-input-guard-tests
#if EYE_DUMP_INPUT_GUARD_TESTS
import AppKit

@main
@MainActor
private enum EyeDumpInputGuardTests {
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fputs("FAIL EyeDumpInputGuardTests: \(message)\n", stderr); exit(1) }
        checks += 1
    }

    static func main() {
        let keyboard: [NSEvent.EventType] = [.keyDown, .keyUp, .flagsChanged]
        let buttons: [NSEvent.EventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                            .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let pointer: [NSEvent.EventType] = [.mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate]
        let other: [NSEvent.EventType] = [.scrollWheel, .magnify, .rotate, .swipe, .smartMagnify, .pressure]
        for (kind, types) in [(HarnessInputGuard.Kind.keyboard, keyboard), (.buttons, buttons), (.pointer, pointer), (.scrollAndGestures, other)] {
            for type in types { expect(HarnessInputGuard.kind(of: type) == kind, "\(type.rawValue) is \(kind.rawValue)") }
        }
        // Every event the fence swallows lands in some kind: nothing is counted only in the total.
        var seen = 0
        for raw in 1..<40 {
            guard let type = NSEvent.EventType(rawValue: UInt(raw)), HarnessInputGuard.blockedEvents.contains(NSEvent.EventTypeMask(rawValue: 1 << UInt64(raw))) else { continue }
            seen += 1
            HarnessInputGuard.note(type)
        }
        let record = HarnessInputGuard.record()
        let byKind = record["byKind"] as? [String: Int] ?? [:]
        expect(seen == keyboard.count + buttons.count + pointer.count + other.count, "the mask holds exactly the \(seen) classified event types")
        expect(byKind.values.reduce(0, +) == seen && record["swallowedEvents"] as? Int == seen, "the per-kind counts add up to the total (\(byKind))")
        expect(byKind["keyboard"] == keyboard.count && byKind["buttons"] == buttons.count && byKind["pointer"] == pointer.count && byKind["scrollAndGestures"] == other.count,
               "each kind counted its own events: \(byKind)")
        expect(Set(record["flaggedKinds"] as? [String] ?? []) == ["keyboard", "buttons", "scrollAndGestures"], "keyboard, buttons and scrolling flag a run; pointer motion alone does not")
        HarnessInputGuard.reset()
        for type in pointer { HarnessInputGuard.note(type) }
        let parked = HarnessInputGuard.record()["byKind"] as? [String: Int] ?? [:]
        expect(parked["pointer"] == pointer.count && parked["keyboard"] == 0 && parked["buttons"] == 0 && HarnessInputGuard.swallowedCount == pointer.count,
               "a parked pointer shows as pointer events only")
        print("EyeDumpInputGuardTests: \(checks) checks passed")
    }
}
#endif
