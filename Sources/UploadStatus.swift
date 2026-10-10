import AppKit

/// Where an upload stands. It drives the bottom bar's status slot (OSN-054, T9): the slot never grows, the state only changes what sits in it.
enum UploadState: Equatable {
    case idle
    case uploading(name: String)
    case success(url: URL, copied: Bool)
    case failure(message: String)

    var isUploading: Bool { if case .uploading = self { return true } else { return false } }
    /// Whether the upload has the status slot: the Original size checkbox gives its place up, since at the 980 pt minimum the slot cannot hold
    /// the checkbox and a message and its commands too. It comes back when the state does (after the 4 s of Link copied, or once the error is dealt with).
    var occupiesStatusSlot: Bool { self != .idle }
    var isFailure: Bool { if case .failure = self { return true } else { return false } }

    /// The sentence the status line shows; nil when idle, where the normal adaptive status applies.
    var statusText: String? {
        switch self {
        case .idle: return nil
        case .uploading(let name): return name.isEmpty ? "Uploading…" : "Uploading \(name)…"
        case .success(let url, let copied):
            if copied { return "Link copied" }
            return ["http", "https"].contains(url.scheme ?? "") ? "Published image" : "Uploaded image to destination"
        case .failure(let message): return "Error: " + Self.firstLine(of: message)
        }
    }

    /// What the status line leaves out: the link itself, or the whole error. It travels on the tooltip and as VoiceOver help.
    var detailText: String? {
        switch self {
        case .success(let url, true): return "Link copied: " + url.absoluteString
        case .failure: return failureDetail
        default: return nil
        }
    }

    /// The link the Open and Copy commands act on: only a link the upload copied is a public one.
    var link: URL? { if case .success(let url, true) = self { return url } else { return nil } }

    /// The whole error text for the Details sheet, always led by "Error:" so the sentence never relies on colour.
    var failureDetail: String? {
        guard case .failure(let message) = self else { return nil }
        return message.hasPrefix("Error:") ? message : "Error: " + message
    }

    /// The status line is one line: a multi-line error shows its first line, Details shows the rest.
    static func firstLine(of message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = trimmed.components(separatedBy: .newlines).first ?? trimmed
        return line.hasPrefix("Error:") ? String(line.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces) : line
    }
}

/// The controls an upload adds to the status slot: a 20 pt indeterminate spinner and the inline commands for each state. They are
/// built once and only hidden or shown (a hidden arranged view leaves its stack), so a state change never rebuilds the bar.
///   uploading   spinner, status text, Cancel
///   success     status text, Open, Copy (the last two only when the link was copied)
///   failure     status text, Retry, Details…
@MainActor
final class UploadStatusControls {
    static let spinnerSide: CGFloat = 20

    let spinner = NSProgressIndicator()
    let cancelButton = CommandButton(title: "", target: nil, action: nil)
    let openButton = CommandButton(title: "", target: nil, action: nil)
    let copyButton = CommandButton(title: "", target: nil, action: nil)
    let retryButton = CommandButton(title: "Retry", target: nil, action: nil)
    let detailsButton = CommandButton(title: "Details…", target: nil, action: nil)
    private(set) var state: UploadState = .idle

    init() {
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        spinner.setAccessibilityLabel("Upload progress")
        GlassChrome.fix(spinner, NSSize(width: Self.spinnerSide, height: Self.spinnerSide))

        icon(cancelButton, .xmark, name: "Cancel upload")
        icon(openButton, .openExternal, name: "Open link in browser")
        icon(copyButton, .copy, name: "Copy link")
        text(retryButton)
        text(detailsButton)
        apply(.idle)
    }

    /// Everything the stack arranges for the upload, in reading order (the spinner first, the commands after the status text).
    var leadingViews: [NSView] { [spinner] }
    var trailingViews: [NSView] { [cancelButton, openButton, copyButton, retryButton, detailsButton] }
    var commandButtons: [CommandButton] { [cancelButton, openButton, copyButton, retryButton, detailsButton] }

    private func icon(_ button: CommandButton, _ icon: FAIcon, name: String) {
        GlassChrome.useExtraLarge(button)
        button.iconPointSize = GlassChrome.Metrics.iconPointSize
        button.icon = icon
        button.makeIconOnly(name: name)
        button.setAccessibilityLabel(name)
        GlassChrome.fix(button, GlassChrome.Metrics.iconButton)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func text(_ button: CommandButton) {
        GlassChrome.useExtraLarge(button)
        button.font = DesignTokens.Typography.font(.body)
        let width = ceil((button.title as NSString).size(withAttributes: [.font: button.font as Any]).width) + 2 * DesignTokens.Space.s3
        GlassChrome.fix(button, NSSize(width: width, height: GlassChrome.Metrics.commandHeight))
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    /// Shows what the state needs and nothing else. The spinner animates only while it is shown.
    func apply(_ state: UploadState) {
        self.state = state
        let uploading = state.isUploading
        spinner.isHidden = !uploading
        if uploading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        cancelButton.isHidden = !uploading
        let linked = state.link != nil
        openButton.isHidden = !linked
        copyButton.isHidden = !linked
        retryButton.isHidden = !state.isFailure
        detailsButton.isHidden = !state.isFailure
    }
}
