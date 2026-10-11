import AppKit

/// Everything one upload needs, kept whole so Retry sends exactly what the first attempt did.
struct UploadPayload {
    let data: Data
    let fileName: String
    let name: String
    let snapshot: HistoryStore.Snapshot
    let generation: UUID
    let binding: [String: String]?
    /// The pixel size of `data`, recorded in History as the published size.
    let pixelSize: CGSize
}

/// The Upload button's destination choices: one glass panel over the upload menu, kept between opens (it rebuilds its rows from the menu
/// each time, so a destination added or made default elsewhere is there on the next open).
@MainActor
final class UploadChoices {
    private(set) var panel: MenuChoicePanel?
    /// Test seam: runs on a new panel before it is shown, so a test can give its host a presenter and keep the window off screen.
    var panelSetup: ((MenuChoicePanel) -> Void)?
    var isOpen: Bool { panel?.host.isShown == true }

    func panel(for menu: NSMenu) -> MenuChoicePanel {
        if let panel, panel.menu === menu { return panel }
        // Destinations are options (the default is the chosen one); Cancel Upload, Destination Settings… and Share with macOS… are commands.
        let made = MenuChoicePanel(menu: menu, identifier: "Upload", accessibilityLabel: "Upload destinations",
                                   kind: { $0.action == #selector(AppDelegate.chooseUploadDestination(_:)) ? .option : .command })
        panel = made
        panelSetup?(made)
        return made
    }
}

extension AppDelegate {
    /// Opens the destination choices above the Upload button (the footer has no room below). A nil event is a keyboard or accessibility
    /// request, which puts the focus on the default destination; a mouse open takes the keyboard but focuses no row. A second request while
    /// the panel is open only closes it.
    func presentUploadChoices(_ menu: NSMenu, event: NSEvent?, from button: NSButton) {
        guard !terminationStarted, button.window != nil else { return }
        if uploadChoices.isOpen { uploadChoices.panel?.host.close(); return }
        uploadChoices.panel(for: menu).present(relativeTo: button, preferredEdge: ChoiceEdge.above, keyboard: event == nil)
    }

    /// Runs on every change of `uploadState`: the chrome shows the matching spinner and commands, the status line takes the new text,
    /// the checkbox yields its place during a transfer, the "Link copied" countdown starts, and VoiceOver is told.
    func uploadStateChanged(from previous: UploadState) {
        uploadSuccessTimer?.invalidate(); uploadSuccessTimer = nil
        if uploadState != .idle { UploadNotice.clear() }
        if !uploadState.isUploading { UploadState.retryingName = nil }
        (modernChrome as? ModernEditorChrome)?.uploadControls.apply(uploadState)
        refreshStatusText(); updateViewportChrome()
        switch uploadState {
        case .idle: break
        case .uploading(let name):
            Announcer.announce(UploadState.retryingName == name && !name.isEmpty ? "Retrying \(name)" : Announcer.Message.uploadStarted(name))
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
        // The status says "Retrying <name>…" with the spinner and Cancel, so a failure that comes straight back is visibly a new attempt.
        UploadState.retryingName = payload.name
        beginUpload(payload)
    }

    @objc func showUploadErrorDetails() {
        guard let detail = uploadState.failureBody, !terminationStarted else { return }
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
        UploadNotice.onChange = { [weak self] in self?.refreshStatusText() }
        for (button, action) in [(controls.cancelButton, #selector(cancelUpload)), (controls.openButton, #selector(openUploadedLink)),
                                 (controls.copyButton, #selector(copyUploadedLink)), (controls.retryButton, #selector(retryUpload)),
                                 (controls.detailsButton, #selector(showUploadErrorDetails))] {
            button.target = self; button.action = action
        }
    }
}
