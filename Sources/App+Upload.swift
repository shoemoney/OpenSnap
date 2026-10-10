import AppKit

/// Everything one upload needs, kept whole so Retry sends exactly what the first attempt did.
struct UploadPayload {
    let data: Data
    let fileName: String
    let name: String
    let snapshot: HistoryStore.Snapshot
    let generation: UUID
    let binding: [String: String]?
}

extension AppDelegate {
    /// Runs on every change of `uploadState`: the chrome shows the matching spinner and commands, the status line takes the new text,
    /// the checkbox yields its place during a transfer, the "Link copied" countdown starts, and VoiceOver is told.
    func uploadStateChanged(from previous: UploadState) {
        uploadSuccessTimer?.invalidate(); uploadSuccessTimer = nil
        (modernChrome as? ModernEditorChrome)?.uploadControls.apply(uploadState)
        refreshStatusText(); updateViewportChrome()
        switch uploadState {
        case .idle: break
        case .uploading(let name): Announcer.announce(Announcer.Message.uploadStarted(name))
        case .success(_, let copied):
            Announcer.announce(copied ? Announcer.Message.uploadSucceeded : "Upload complete")
            let timer = Timer(timeInterval: uploadSuccessDuration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.expireUploadSuccess() }
            }
            uploadSuccessTimer = timer; RunLoop.main.add(timer, forMode: .common)
        case .failure(let message):
            let text = Announcer.Message.uploadFailed(UploadState.firstLine(of: message))
            Announcer.announce(text, priority: Announcer.priority(for: text))
        }
    }

    /// "Link copied" gives the slot back to the normal status.
    func expireUploadSuccess() {
        uploadSuccessTimer?.invalidate(); uploadSuccessTimer = nil
        if case .success = uploadState { uploadState = .idle }
    }

    /// A failure and its Retry belong to the document that was uploaded; once that document is replaced they are stale.
    func expireStaleUploadFailure() {
        guard uploadState.isFailure, uploadFailureGeneration != documentGeneration else { return }
        retryablePayload = nil
        uploadState = .idle
    }

    @objc func retryUpload() {
        guard !terminationStarted, !publishing.isBusy, uploadState.isFailure, let payload = retryablePayload else { return }
        guard publishing.isConfigured else { openDestinationSettings(); return }
        beginUpload(payload)
    }

    @objc func showUploadErrorDetails() {
        guard let detail = uploadState.failureDetail, !terminationStarted else { return }
        present(AppAlert(title: "Upload failed", message: detail))
    }

    @objc func openUploadedLink() {
        guard let link = uploadState.link else { return }
        linkOpener(link)
    }

    @objc func copyUploadedLink() {
        guard let link = uploadState.link else { return }
        publishing.clipboardWriter(link)
    }

    /// Points the status slot's inline commands at this delegate. The chrome builds them; the app owns what they do.
    func wireUploadControls(_ controls: UploadStatusControls) {
        for (button, action) in [(controls.cancelButton, #selector(cancelUpload)), (controls.openButton, #selector(openUploadedLink)),
                                 (controls.copyButton, #selector(copyUploadedLink)), (controls.retryButton, #selector(retryUpload)),
                                 (controls.detailsButton, #selector(showUploadErrorDetails))] {
            button.target = self; button.action = action
        }
    }
}
