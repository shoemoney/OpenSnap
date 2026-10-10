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

    /// How long "Link copied" and its Open and Copy commands stay once an upload succeeds: long enough to read the link and reach for a
    /// command (F-J2-022). The app's timer starts from this, and the next upload replaces it sooner.
    static let successDuration: TimeInterval = 12
    /// The file name of an upload that is being sent again, so the status says "Retrying" rather than showing the failed line's twin.
    nonisolated(unsafe) static var retryingName: String?

    /// The sentence the status line shows, longest first; empty when idle, where the normal adaptive status applies. The status line shows the
    /// first one that fits whole, so a narrow slot gives up the tail of the link before it gives up "Link copied".
    var statusVariants: [String] {
        switch self {
        case .idle: return []
        case .uploading(let name):
            let verb = Self.retryingName == name && !name.isEmpty ? "Retrying" : "Uploading"
            return [name.isEmpty ? "\(verb)…" : "\(verb) \(name)…"]
        case .success(let url, let copied):
            guard copied else { return [["http", "https"].contains(url.scheme ?? "") ? "Published image" : "Uploaded image to destination"] }
            return Self.copiedVariants(for: url)
        case .failure(let message): return Self.errorVariants(for: message)
        }
    }

    /// "Error: <first line>", then the same with the middle of the line cut a few characters at a time (the beginning says what failed and
    /// the end is often the code that matters), and last a sentence that always fits. The tail of a long error is never simply dropped.
    static func errorVariants(for message: String) -> [String] {
        let line = firstLine(of: message), prefix = "Error: "
        var variants = [prefix + line]
        var keep = line.count - 4
        while keep >= minimumErrorCharacters {
            variants.append(prefix + middleTruncated(line, to: keep))
            keep -= 4
        }
        if line.count > minimumErrorCharacters { variants.append(prefix + "Upload failed") }
        return variants
    }
    static let minimumErrorCharacters = 24

    /// The longest sentence the status line can show; nil when idle.
    var statusText: String? { statusVariants.first }

    /// "Link copied · cdn.example.com/pics/name.png", then the same with the middle of the address cut out a few characters at a time
    /// (the host and the file name are the parts worth keeping). When none of those fits, the whole sentence comes last: the status line then
    /// cuts it at its tail ("Link copied · cdn.exa…"), so the slot is never left empty and "Link copied" always leads, without a second ellipsis.
    static func copiedVariants(for url: URL) -> [String] {
        let base = "Link copied"
        let address = displayAddress(of: url)
        guard !address.isEmpty else { return [base] }
        var variants = [base + " · " + address]
        var keep = address.count - 3
        while keep >= minimumAddressCharacters {
            variants.append(base + " · " + middleTruncated(address, to: keep))
            keep -= 3
        }
        variants.append(variants[0])
        return variants
    }
    static let minimumAddressCharacters = 14

    /// The link without its scheme, which says nothing the host does not.
    static func displayAddress(of url: URL) -> String {
        let text = url.absoluteString
        for scheme in ["https://", "http://"] where text.lowercased().hasPrefix(scheme) { return String(text.dropFirst(scheme.count)) }
        return text
    }

    /// `text` cut to `count` characters with an ellipsis in the middle, keeping a little more of the end (the file name) than the start.
    static func middleTruncated(_ text: String, to count: Int) -> String {
        guard text.count > count, count > 1 else { return text }
        let tail = count / 2, head = count - 1 - tail
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
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

    /// The whole error text for the tooltip and VoiceOver help, always led by "Error:" so the sentence never relies on colour.
    var failureDetail: String? {
        guard case .failure(let message) = self else { return nil }
        return message.hasPrefix("Error:") ? message : "Error: " + message
    }

    /// The whole error for the Details sheet. Its title already says "Upload failed", so the text does not begin with "Error:" again.
    var failureBody: String? {
        guard case .failure(let message) = self else { return nil }
        let text = message.hasPrefix("Error:") ? String(message.dropFirst("Error:".count)) : message
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The status line is one line: a multi-line error shows its first line, Details shows the rest.
    static func firstLine(of message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = trimmed.components(separatedBy: .newlines).first ?? trimmed
        return line.hasPrefix("Error:") ? String(line.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces) : line
    }
}

/// A one-line outcome the status slot keeps after an upload that has no state of its own: today, "Upload cancelled". It stays for
/// `duration` seconds or until the next upload starts, instead of being overwritten by the next status refresh a moment later (F-J2-022).
@MainActor
enum UploadNotice {
    nonisolated static let duration: TimeInterval = 10
    private(set) static var text: String?
    private static var timer: Timer?
    /// Called when the notice appears or goes, so the owner refreshes the status line.
    static var onChange: (() -> Void)?

    static func post(_ message: String, duration: TimeInterval = UploadNotice.duration) {
        timer?.invalidate()
        text = message
        let expiry = Timer(timeInterval: duration, repeats: false) { _ in MainActor.assumeIsolated { clear() } }
        timer = expiry; RunLoop.main.add(expiry, forMode: .common)
        onChange?()
    }
    static func clear() {
        timer?.invalidate(); timer = nil
        guard text != nil else { return }
        text = nil
        onChange?()
    }
}

/// The controls an upload adds to the status slot: a 20 pt indeterminate spinner and the inline commands for each state. They are
/// built once and only hidden or shown (a hidden arranged view leaves its stack), so a state change never rebuilds the bar.
///   uploading   spinner, status text, Cancel
///   success     status text, Open, Copy (the last two only when the link was copied)
///   failure     status text, Retry, Details
/// Every command is an icon button with a rest plate (a faint fill, as the unselected segment of the PNG | JPG toggle has), so each one
/// reads as a button before the pointer arrives; it deepens on hover and press like the rest of the chrome. They sit on the bar itself,
/// not on a glass plate of their own: the bars hold exactly eight plates.
@MainActor
final class UploadStatusControls {
    static let spinnerSide: CGFloat = 20

    let spinner = NSProgressIndicator()
    let cancelButton = CommandButton(title: "", target: nil, action: nil)
    let openButton = CommandButton(title: "", target: nil, action: nil)
    let copyButton = CommandButton(title: "", target: nil, action: nil)
    let retryButton = CommandButton(title: "", target: nil, action: nil)
    let detailsButton = CommandButton(title: "", target: nil, action: nil)
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
        icon(retryButton, .arrowRotateRight, name: "Retry upload")
        icon(detailsButton, .circleInfo, name: "Show error details")
        apply(.idle)
    }

    /// Everything the stack arranges for the upload, in reading order (the spinner first, the commands after the status text).
    var leadingViews: [NSView] { [spinner] }
    var trailingViews: [NSView] { commandButtons }
    var commandButtons: [CommandButton] { [cancelButton, openButton, copyButton, retryButton, detailsButton] }

    private func icon(_ button: CommandButton, _ icon: FAIcon, name: String) {
        GlassChrome.useExtraLarge(button)
        button.iconPointSize = GlassChrome.Metrics.iconPointSize
        button.icon = icon
        button.makeIconOnly(name: name)
        button.showsRestPlate = true
        button.setAccessibilityLabel(name)
        GlassChrome.fix(button, GlassChrome.Metrics.iconButton)
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
