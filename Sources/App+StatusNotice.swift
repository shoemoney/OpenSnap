import AppKit

/// Transient messages in the bottom bar's status slot (F-J1-010). A notice outranks the normal status, then gives the slot back: after
/// `statusNoticeDuration`, or at once when the state it described changes (an edit, another tool, full screen toggling).
extension AppDelegate {
    /// How a notice is spoken: as it reads (medium, or high when it begins "Error:"), as an error (the spoken line gains "Error:"), or
    /// urgently (high, wording unchanged).
    enum NoticeVoice { case plain, error, urgent }

    func postStatusNotice(_ text: String, duration: TimeInterval? = nil, voice: NoticeVoice = .plain) {
        switch voice {
        case .plain: Announcer.announce(text, priority: Announcer.priority(for: text))
        case .error: Announcer.announce(Announcer.Message.uploadFailed(text), priority: .high)
        case .urgent: Announcer.announce(text, priority: .high)
        }
        statusNoticeTimer?.invalidate()
        statusNotice = text
        let timer = Timer(timeInterval: duration ?? statusNoticeDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearStatusNotice() }
        }
        statusNoticeTimer = timer; RunLoop.main.add(timer, forMode: .common)
        showStatusNotice(text)
    }

    /// Frame mode keeps its own hint in the slot, so a notice there is written straight over it and the hint comes back when it expires.
    private func showStatusNotice(_ text: String?) {
        if frameMode { status.stringValue = text ?? frameStatusHint } else { refreshStatusText() }
    }

    var frameStatusHint: String { frameKeepsAnnotations ? "Frame: Snap keeps your drawing" : "Frame: position, then Snap" }

    func clearStatusNotice() {
        statusNoticeTimer?.invalidate(); statusNoticeTimer = nil
        guard statusNotice != nil else { return }
        statusNotice = nil
        showStatusNotice(nil)
    }
}
