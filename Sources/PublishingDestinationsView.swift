import AppKit

// The destination editor: the sheet that adds or edits one destination (Settings, Upload opens it). The list of destinations, the default
// and removal live in Settings, Upload; this view owns no storage. The coordinator supplies callbacks, so every action is testable without a
// window or a network.
final class PublishingDestinationsView: NSView {
    private typealias Typography = DesignTokens.Typography
    private typealias Space = DesignTokens.Space

    var onCancel: (() -> Void)?
    var onSave: ((PublishingDestination, String) -> Void)?
    var onTest: ((PublishingDestination, String) -> Void)?
    var passwordFor: (PublishingDestination) -> String

    /// The sheet is 720 wide and at most 760 tall; on a short screen it shrinks and the form scrolls instead of clipping. Under a narrower
    /// window (Settings is 640) it is as wide as that window, never narrower than `sheetMinWidth`, so it never overhangs its parent.
    static let sheetWidth: CGFloat = 720, sheetMinWidth: CGFloat = 560, sheetMaxHeight: CGFloat = 760, sheetScreenMargin: CGFloat = 120, sheetMinHeight: CGFloat = 360
    static var contentWidth: CGFloat { sheetWidth - 2 * Space.s5 }
    /// The width of the sheet that hangs from a window `hostWidth` wide.
    static func sheetWidth(forHostWidth hostWidth: CGFloat) -> CGFloat { min(sheetWidth, max(sheetMinWidth, hostWidth)) }
    /// Width of the form's content, and of every control row in it.
    let width: CGFloat
    var contentWidth: CGFloat { width - 2 * Space.s5 }
    /// The list page shows between `minListRows` and `maxListRows` rows, so a short list does not leave the sheet mostly blank.
    static let minListRows = 4, maxListRows = 8
    static func sheetSize(visibleFrame: NSRect) -> NSSize {
        let height = max(sheetMinHeight, min(sheetMaxHeight, visibleFrame.height - sheetScreenMargin))
        return NSSize(width: sheetWidth, height: min(height, visibleFrame.height))
    }

    /// The glass plates carry a 4 pt inset of their own, so the form and footer give them less margin than a native control needs: that is
    /// what keeps the SFTP form inside the 680 pt sheet of a 1280 x 800 screen with 44 pt rows.
    private static let pageTop = Space.s4, footerTop = Space.s2, footerBottom = Space.s3

    private(set) var editing: PublishingDestination?

    /// The tallest the sheet may be (set from the screen). The form always asks for what it needs and scrolls when that is more.
    var maxSheetHeight: CGFloat = PublishingDestinationsView.sheetMaxHeight
    /// Called when the height the sheet should hug changes (a protocol with more rows, a longer result), so the coordinator can resize the panel.
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    /// The content height the form wants: its rows of the selected protocol, the result band it shows now, and the margins, never taller than
    /// the screen allows. A form that does not fit scrolls.
    var preferredHeight: CGFloat { min(maxSheetHeight, formPageHeight) }
    /// The visible form's rows, the separator, the footer with its result band, and the margins around them.
    var formPageHeight: CGFloat {
        Self.pageTop + formPage.fittingSize.height + Space.s5 + 1 + Self.footerTop + formFooter.fittingSize.height + Self.footerBottom
    }
    private func notifyPreferredHeight() { onPreferredHeightChange?(preferredHeight) }

    let scrollView = NSScrollView()
    /// How much of the form's edge dissolves where more of the form lies beyond it, so a paragraph is never sliced by a hard line.
    static let scrollFadeHeight: CGFloat = 32
    private let scrollFade = CAGradientLayer()
    /// Whether the form runs on below the visible part / above it: the edge that does fades out instead of being cut.
    private(set) var fadesAtBottom = false, fadesAtTop = false
    private let formPage = NSStackView()
    /// The inline Test / Save result: a glyph and text together, never colour alone. It sits above the buttons and is as tall as its text.
    let formResult: DestinationStatusRow

    // Form controls (internal so tests can fill them in like a user would).
    let nameField = TokenTextField(), endpointField = TokenTextField(), usernameField = TokenTextField()
    let passwordField = TokenSecureTextField(), folderField = TokenTextField(), publicField = TokenTextField()
    let aliasField = TokenTextField(), remoteRootField = TokenTextField(), portField = TokenTextField()
    let regionField = TokenTextField(), bucketField = TokenTextField(), profileField = TokenTextField()
    /// The Protocol and Source choices: glass pop-ups. Each keeps `NSPopUpButton` as the model (items, selection, the action `formChanged`)
    /// and opens every way, mouse, keys and VoiceOver included, as one glass panel; they sit on plates in a hover-fill cell.
    let protocolPopup = DestinationChoicePopUp(frame: .zero, pullsDown: false)
    let sourcePopup = DestinationChoicePopUp(frame: .zero, pullsDown: false)
    /// The "Make uploads public-read" switch: a checkbox-style glass toggle; `state` is `.on` while chosen.
    let aclCheckbox = GlassChoiceButton(title: "Make uploads public-read", kind: .toggle, indicator: .checkbox, layout: .row)
    private var glassPlates: [GlassSurfaceView] = []
    private var fillCells: [ChromeFillCell] = []
    private var displayOptionsObservation: DisplayOptions.Observation?
    private(set) var sectionHeaders: [NSTextField] = []
    /// The caption of every visible form row, so tests can check each fits its column on one line.
    var visibleFormCaptions: [NSTextField] { rows.values.filter { !$0.stack.isHidden && !$0.label.stringValue.isEmpty }.map(\.label) }

    private struct Row { let label: NSTextField; let stack: NSStackView; let visible: (PublishingProtocol, Bool) -> Bool }
    private var rows: [String: Row] = [:]

    /// A sheet command: a titled glass command button (20 pt, its own state fills) that sits on an action plate.
    private static func button(_ title: String, _ target: AnyObject, _ action: Selector) -> GlassChoiceButton {
        let button = GlassChoiceButton(title: title, kind: .command, layout: .segment)
        button.target = target; button.action = action
        button.minimumWidth = commandMinimumWidth
        return button
    }
    private static let commandMinimumWidth: CGFloat = 96
    /// Status and pill glyphs share the chrome's icon family (ChromeIcons), so Destinations never mixes in a stray SF Symbol.
    static func icon(_ icon: FAIcon, pointSize: CGFloat = Typography.iconInline, description: String? = nil) -> NSImage? {
        let image = ChromeIcons.resolve(icon, family: .solid, pointSize: pointSize).image
        image?.accessibilityDescription = description
        return image
    }

    // Footer buttons: pinned below the scroll view so Return and Escape always have a visible target.
    private(set) lazy var cancelButton: GlassChoiceButton = {
        let button = Self.button("Cancel", self, #selector(cancelFormTapped)); button.keyEquivalent = "\u{1b}"; return button
    }()
    /// The default button, and the only primary (tinted) command on the sheet.
    private(set) lazy var saveButton: GlassChoiceButton = {
        let button = Self.button("Save", self, #selector(saveTapped)); button.keyEquivalent = "\r"; button.isPrimary = true; return button
    }()
    private(set) lazy var testButton: GlassChoiceButton = Self.button("Test", self, #selector(testTapped))
    /// The two action plates of the footer: Test on its own, Cancel and Save together.
    private(set) var testPlate: GlassSurfaceView?, actionPlate: GlassSurfaceView?
    private let formFooter = NSStackView()

    init(editing destination: PublishingDestination?, width: CGFloat = PublishingDestinationsView.sheetWidth,
         passwordFor: @escaping (PublishingDestination) -> String = { _ in "" }) {
        self.width = width; self.passwordFor = passwordFor
        formResult = DestinationStatusRow(width: width - 2 * Space.s5, maxLines: 3)
        super.init(frame: .zero)
        buildForm(); buildFooters()

        let document = DestinationFlippedView()
        formPage.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(formPage)
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true; scrollView.hasHorizontalScroller = false; scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false; scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false; addSubview(scrollView)
        scrollView.wantsLayer = true; scrollView.layer?.mask = scrollFade
        scrollFade.startPoint = CGPoint(x: 0.5, y: 1); scrollFade.endPoint = CGPoint(x: 0.5, y: 0)   // layer space: y grows upward
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollMoved), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        let separator = NSBox(); separator.boxType = .separator; separator.translatesAutoresizingMaskIntoConstraints = false; addSubview(separator)
        formFooter.translatesAutoresizingMaskIntoConstraints = false; addSubview(formFooter)
        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor), document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            formPage.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Space.s5),
            formPage.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -Space.s5),
            formPage.topAnchor.constraint(equalTo: document.topAnchor, constant: Self.pageTop),
            formPage.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -Space.s5),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor), separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomAnchor.constraint(equalTo: formFooter.bottomAnchor, constant: Self.footerBottom),
            formFooter.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s5),
            formFooter.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s5),
            formFooter.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Self.footerTop),
        ])
        showForm(for: destination)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func scrollMoved() { updateScrollFade() }
    override func layout() { super.layout(); updateScrollFade() }

    /// Fades the top or bottom edge of the form when part of it is scrolled out of sight there.
    func updateScrollFade() {
        guard let document = scrollView.documentView else { return }
        let clip = scrollView.contentView.bounds
        fadesAtTop = clip.minY > 0.5
        fadesAtBottom = clip.maxY < document.frame.height - 0.5
        let height = max(1, scrollView.bounds.height), fade = min(0.5, Self.scrollFadeHeight / height)
        let opaque = NSColor.black.cgColor, clear = NSColor.black.withAlphaComponent(0).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        scrollFade.frame = scrollView.bounds
        scrollFade.colors = [fadesAtTop ? clear : opaque, opaque, opaque, fadesAtBottom ? clear : opaque]
        scrollFade.locations = [0, NSNumber(value: Double(fadesAtTop ? fade : 0)), NSNumber(value: Double(1 - (fadesAtBottom ? fade : 0))), 1]
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateDefaultButton() }

    /// Return saves and Escape cancels; both buttons are always on screen, so the keys always have a visible target.
    private func updateDefaultButton() { window?.defaultButtonCell = saveButton.cell as? NSButtonCell }

    private func buildFooters() {
        formFooter.orientation = .horizontal; formFooter.alignment = .centerY; formFooter.spacing = Space.s4; formFooter.distribution = .fill
        let options = ChromeAccessibility.live
        for button in [testButton, cancelButton, saveButton, aclCheckbox] { button.accessibility = options }
        let testPlate = glassPlate([testButton], identifier: "DestinationTestGroup", label: "Test connection")
        let actionPlate = glassPlate([cancelButton, saveButton], identifier: "DestinationActionGroup", label: "Cancel or save")
        self.testPlate = testPlate; self.actionPlate = actionPlate
        let flexible = NSView(); flexible.setContentHuggingPriority(.init(1), for: .horizontal)
        // Both plates share one glass container, the way the editor and History bars do; the buttons on them draw their own state fills.
        let row = NSStackView(views: [testPlate, flexible, actionPlate]); row.orientation = .horizontal; row.alignment = .centerY
        row.spacing = GlassChrome.Metrics.groupGap; row.translatesAutoresizingMaskIntoConstraints = false
        let bar = NSView(); bar.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: bar.leadingAnchor), row.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
                                     row.topAnchor.constraint(equalTo: bar.topAnchor), row.bottomAnchor.constraint(equalTo: bar.bottomAnchor)])
        let buttons = GlassChrome.container(around: bar, identifier: "DestinationFooterBar")
        buttons.heightAnchor.constraint(equalToConstant: GlassChrome.Metrics.headerHeight).isActive = true
        displayOptionsObservation = DisplayOptions.observe { [weak self] _ in self?.applyDisplayOptions() }
        // The result band is as tall as what it says: one line for the idle hint, up to three for a Test error. The footer grows by the
        // difference and the form above it shrinks and scrolls, so a result never covers a field and an idle form keeps its room.
        formResult.translatesAutoresizingMaskIntoConstraints = false
        let column = NSStackView(views: [formResult, buttons]); column.orientation = .vertical; column.alignment = .leading; column.spacing = Space.s2
        buttons.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        formResult.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        formFooter.addArrangedSubview(column)
        column.widthAnchor.constraint(equalTo: formFooter.widthAnchor).isActive = true
    }

    /// One glass plate for a related group of choices; it is announced as a group so VoiceOver does not walk straight through it.
    private func glassPlate(_ views: [NSView], identifier: String, label: String? = nil) -> GlassSurfaceView {
        let plate = GlassChrome.plate(views, identifier: identifier, accessibility: .live)
        if let label { plate.setAccessibilityElement(true); plate.setAccessibilityLabel(label); plate.setAccessibilityRole(.group) }
        glassPlates.append(plate)
        return plate
    }
    private func applyDisplayOptions() {
        let options = ChromeAccessibility.live
        for plate in glassPlates { plate.accessibility = options }
        for cell in fillCells { cell.accessibility = options }
        for button in [testButton, cancelButton, saveButton, aclCheckbox] { button.accessibility = options }
    }

    /// A failure from storage or a worker: the form's result band says "Error:" and carries a glyph, so it never relies on colour.
    func showStatus(_ text: String) {
        showResult(.failure, text.hasPrefix("Error:") ? text : "Error: " + text)
    }
    /// The S3 Test result: "Connected" with the server's detail, or "Error: <message>".
    func showTestResult(ok: Bool, message: String) {
        if ok { showResult(.success, "Connected", detail: message) }
        else { showResult(.failure, message.hasPrefix("Error:") ? message : "Error: " + message) }
    }
    private func scrollToTop() {
        scrollView.contentView.scroll(to: .zero); scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Form page

    private let formHelp = NSTextField(wrappingLabelWithString: "")

    private static let captionWidth: CGFloat = 180

    private func styled(_ field: NSTextField, _ placeholder: String) -> NSTextField {
        Typography.apply(.body, to: field); field.placeholderString = placeholder
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.Size.control).isActive = true
        return field
    }
    private func label(_ text: String, style: Typography.Style = .body) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text); field.font = Typography.font(style); field.textColor = DesignTokens.Palette.Text.primary
        return field
    }
    private func sectionHeader(_ title: String) -> NSTextField {
        let header = NSTextField(labelWithString: title); header.font = Typography.font(.headline); header.textColor = DesignTokens.Palette.Text.primary
        header.setAccessibilityRole(.staticText); header.setAccessibilityLabel(title)
        sectionHeaders.append(header)
        return header
    }
    /// A row caption ends in a colon, as the labels of the Settings forms and every classic Mac form do; the control keeps the bare name for VoiceOver.
    static func captionText(_ title: String) -> String { title.isEmpty ? "" : title + ":" }
    private func addRow(_ id: String, _ title: String, _ control: NSView, stretches: Bool = true, visible: @escaping (PublishingProtocol, Bool) -> Bool) {
        let caption = label(Self.captionText(title), style: .bodyStrong)
        let stack = NSStackView(views: [caption, control]); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = Space.s4
        caption.widthAnchor.constraint(equalToConstant: Self.captionWidth).isActive = true
        caption.preferredMaxLayoutWidth = Self.captionWidth
        control.setContentHuggingPriority(stretches ? .defaultLow : .required, for: .horizontal)
        stack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        control.setAccessibilityLabel(title)
        rows[id] = Row(label: caption, stack: stack, visible: visible)
        formPage.addArrangedSubview(stack)
    }

    /// Everything on the form that reads differently per protocol: captions, placeholders, the help under the form and what Test does.
    struct FormCopy: Equatable {
        var endpointCaption = "Endpoint URL", endpointPlaceholder = ""
        var folderCaption = "Remote folder", folderPlaceholder = ""
        var usernameCaption = "Username", usernamePlaceholder = ""
        var passwordCaption = "Password", passwordPlaceholder = "Saved in the macOS Keychain"
        var help = "", testNote = ""
    }
    static func formCopy(for transport: PublishingProtocol) -> FormCopy {
        var copy = FormCopy()
        switch transport {
        case .webDAV:
            copy.endpointPlaceholder = "https://example.com"; copy.folderPlaceholder = "screenshots"
            copy.usernamePlaceholder = "Blank for anonymous access"
            copy.help = "WebDAV, or any server that accepts an HTTP PUT. The endpoint starts with http:// or https://. Folders must exist. Public base URL maps to the remote folder; only the file name is appended."
            copy.testNote = "Test asks the server about the folder and, when a login is set, checks it. It never uploads."
        case .ftp:
            copy.endpointPlaceholder = "ftp://ftp.example.com"; copy.folderPlaceholder = "screenshots"
            copy.usernamePlaceholder = "Blank for anonymous access"
            copy.help = "Plain FTP: the endpoint starts with ftp:// and the password travels unencrypted, so use FTPS or SFTP where the server offers them. Folders must exist. Public base URL maps to the upload folder; only the file name is appended."
            copy.testNote = "Test logs in and lists the folder. It never uploads."
        case .ftps:
            copy.endpointPlaceholder = "ftps://ftp.example.com"; copy.folderPlaceholder = "screenshots"
            copy.usernamePlaceholder = "Blank for anonymous access"
            copy.help = "FTPS: ftp:// starts explicit TLS and ftps:// implicit TLS; TLS is required either way. Folders must exist. Public base URL maps to the upload folder; only the file name is appended."
            copy.testNote = "Test logs in over TLS and lists the folder. It never uploads."
        case .sftp:
            copy.endpointPlaceholder = "sftp://host.example.com"; copy.folderPlaceholder = "screenshots"
            copy.usernamePlaceholder = "Blank to use SSH config"
            copy.help = "SFTP uses keys from your SSH configuration or agent, with strict known-host checks, and needs no password. Give the SSH host (an alias from ~/.ssh/config or a host name) and an absolute remote root; leave username and port empty to use the alias settings. Folders must exist."
            copy.testNote = "Test connects over SSH and lists the folder. It never uploads."
        case .s3:
            copy.endpointCaption = "Endpoint"; copy.endpointPlaceholder = "Blank for AWS, or a URL"
            copy.folderCaption = "Key prefix"; copy.folderPlaceholder = "screenshots (optional)"
            copy.usernameCaption = "Access key ID"; copy.usernamePlaceholder = "AKIAIOSFODNN7EXAMPLE"
            copy.passwordCaption = "Secret access key"
            copy.help = "Path-style S3 over system curl, for AWS, Cloudflare R2, Backblaze B2, DigitalOcean Spaces, Wasabi and MinIO. Public base URL maps to the key prefix; the uploaded file is downloaded from it to verify the exact bytes. Leave public-read off when the bucket disables ACLs."
            copy.testNote = "Test lists the bucket with these credentials. It never uploads."
        }
        return copy
    }

    /// True while an SFTP destination that was saved with an sftp:// endpoint is open: its Endpoint row stays so the value can be seen and
    /// cleared. A new SFTP destination has none; the SSH host row says it all.
    private var showsLegacySFTPEndpoint = false

    private func buildForm() {
        formPage.orientation = .vertical; formPage.alignment = .leading; formPage.spacing = Space.s3
        for popup in [protocolPopup, sourcePopup] { popup.menu?.autoenablesItems = false }
        protocolPopup.addItems(withTitles: PublishingProtocol.allCases.map(\.title))
        for (index, transport) in PublishingProtocol.allCases.enumerated() { protocolPopup.item(at: index)?.toolTip = transport.detail }
        protocolPopup.target = self; protocolPopup.action = #selector(formChanged)
        sourcePopup.addItems(withTitles: [Self.sourceTitles.profile, Self.sourceTitles.keychain])
        sourcePopup.faceTitles = Self.sourceFaceTitles
        sourcePopup.target = self; sourcePopup.action = #selector(formChanged)
        aclCheckbox.target = self; aclCheckbox.action = #selector(formChanged)
        Typography.apply(.body, to: passwordField)
        let all: (PublishingProtocol, Bool) -> Bool = { _, _ in true }
        formPage.addArrangedSubview(sectionHeader("Connection"))
        addRow("name", "Name", styled(nameField, "Shown in the Upload menu"), visible: all)
        addRow("protocol", "Protocol", choicePlate(protocolPopup, caption: "Protocol", identifier: "DestinationProtocol"), visible: all)
        addRow("endpoint", "Endpoint URL", styled(endpointField, ""), visible: { [unowned self] p, _ in p != .sftp || self.showsLegacySFTPEndpoint })
        addRow("region", "Region", styled(regionField, "us-east-1, or auto for R2"), visible: { p, _ in p == .s3 })
        addRow("bucket", "Bucket", styled(bucketField, "my-bucket"), visible: { p, _ in p == .s3 })
        addRow("folder", "Remote folder", styled(folderField, ""), visible: all)
        addRow("public", "Public base URL", styled(publicField, "https://cdn.example.com"), visible: all)
        addRow("alias", "SSH host alias", styled(aliasField, "myserver or host.example.com"), visible: { p, _ in p == .sftp })
        addRow("root", "SFTP remote root", styled(remoteRootField, "/var/www/site/uploads"), visible: { p, _ in p == .sftp })
        addRow("port", "SFTP port", styled(portField, "Blank to use SSH config"), visible: { p, _ in p == .sftp })
        addRow("acl", "", glassPlate([aclCheckbox], identifier: "DestinationPublicReadGroup"), stretches: false, visible: { p, _ in p == .s3 })
        if let last = rows["acl"]?.stack { formPage.setCustomSpacing(Space.s5, after: last) }
        formPage.addArrangedSubview(sectionHeader("Credentials"))
        addRow("source", "Source", choicePlate(sourcePopup, caption: "Source", identifier: "DestinationSource"), visible: { p, _ in p == .s3 })
        addRow("profile", "AWS profile", styled(profileField, "default (~/.aws/credentials)"), visible: { p, keychain in p == .s3 && !keychain })
        addRow("username", "Username", styled(usernameField, ""),
               visible: { p, keychain in p == .s3 ? keychain : true })
        addRow("password", "Password", passwordField,
               visible: { p, keychain in p == .s3 ? keychain : p != .sftp })
        Typography.apply(.caption, to: formHelp); formHelp.textColor = DesignTokens.Palette.Text.secondary
        formHelp.maximumNumberOfLines = 0; formHelp.preferredMaxLayoutWidth = contentWidth
        formPage.addArrangedSubview(formHelp)
        formPage.setCustomSpacing(Space.s4, after: rows["password"]!.stack)
        // The Protocol plate is 44 pt against the 36 pt fields around it; 8 pt each side keeps the rows' centres on the form's 48 pt pitch.
        for id in ["name", "protocol"] { if let stack = rows[id]?.stack { formPage.setCustomSpacing(Space.s2, after: stack) } }
    }

    private var keychainSource: Bool { sourcePopup.indexOfSelectedItem == 1 }
    var selectedProtocol: PublishingProtocol {
        PublishingProtocol.allCases.indices.contains(protocolPopup.indexOfSelectedItem)
            ? PublishingProtocol.allCases[protocolPopup.indexOfSelectedItem] : .webDAV
    }

    @objc func formChanged() { refreshForm() }
    private func refreshForm() {
        let transport = selectedProtocol, keychain = keychainSource, copy = Self.formCopy(for: transport)
        for row in rows.values { row.stack.isHidden = !row.visible(transport, keychain) }
        func caption(_ id: String, _ text: String) {
            rows[id]?.label.stringValue = Self.captionText(text)
            rows[id]?.stack.arrangedSubviews.last?.setAccessibilityLabel(text)
        }
        caption("endpoint", copy.endpointCaption); caption("folder", copy.folderCaption)
        caption("username", copy.usernameCaption); caption("password", copy.passwordCaption)
        endpointField.placeholderString = copy.endpointPlaceholder; folderField.placeholderString = copy.folderPlaceholder
        usernameField.placeholderString = copy.usernamePlaceholder; passwordField.placeholderString = copy.passwordPlaceholder
        formHelp.stringValue = copy.help
        syncProtocolHelp()
        if formResult.kind == .idle || formResult.kind == .hint { formResult.show(.hint, copy.testNote) }
        notifyPreferredHeight()
    }
    /// Shows the form's result band and lets the sheet follow its height.
    private func showResult(_ kind: DestinationStatusRow.Kind, _ message: String, detail: String = "") {
        formResult.show(kind, message, detail: detail)
        notifyPreferredHeight()
    }

    // MARK: Glass pop-ups

    /// A pop-up on its own plate: the pop-up draws its face (title and chevron) and opens one glass panel; the cell behind it draws the hover
    /// fill. It is as wide as its widest title, and never wider than the room the row leaves.
    private func choicePlate(_ popup: GlassPopUpButton, caption: String, identifier: String) -> GlassSurfaceView {
        popup.panelIdentifier = identifier + ".panel"; popup.panelLabel = caption
        popup.identifier = NSUserInterfaceItemIdentifier(identifier + "Popup")
        popup.setAccessibilityLabel(caption)
        let room = contentWidth - Self.captionWidth - Space.s4
        let width = min(ceil(popup.intrinsicContentSize.width), room)
        let cell = ChromeFillCell(popup, size: NSSize(width: width, height: GlassChoiceButton.height))
        cell.focusTarget = popup; cell.accessibility = .live
        popup.minimumPanelWidth = max(240, width)
        fillCells.append(cell)
        return glassPlate([cell], identifier: identifier + "Group")
    }

    /// The two credential sources, in menu order, with the full title the menu, the accessibility value and the tooltip keep and the short one the face shows.
    static let sourceTitles = (profile: "AWS credentials profile", keychain: "Access key stored in Keychain")
    static let sourceFaceTitles = [sourceTitles.profile: "AWS profile", sourceTitles.keychain: "Keychain"]

    /// The protocol pop-up says what the chosen protocol is; the source pop-up's tooltip is the full title its face shortens.
    private func syncProtocolHelp() {
        AppToolTip.setText(selectedProtocol.detail, for: protocolPopup)
        AppToolTip.setText(sourcePopup.titleOfSelectedItem, for: sourcePopup)
    }

    /// Closes any choice panel that is up and says whether there was one. Escape with a panel open dismisses only the panel; the sheet stays.
    @discardableResult
    private func closeOpenChoicePanels() -> Bool {
        let open = [protocolPopup, sourcePopup].map(\.choicePanel).filter { $0.host.isShown }
        for panel in open { panel.host.close() }
        return !open.isEmpty
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { for popup in [protocolPopup, sourcePopup] { popup.choicePanel.host.close(restoreFocus: false) } }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Disables protocols the system tools cannot run.
    func setUnavailable(_ unavailable: Set<PublishingProtocol>) {
        for (index, transport) in PublishingProtocol.allCases.enumerated() { protocolPopup.item(at: index)?.isEnabled = !unavailable.contains(transport) }
    }

    func showForm(for destination: PublishingDestination?) {
        editing = destination
        let settings = destination?.settings ?? PublishingSettings()
        nameField.stringValue = destination?.name ?? ""
        protocolPopup.selectItem(at: PublishingProtocol.allCases.firstIndex(of: settings.transport) ?? 0)
        endpointField.stringValue = settings.endpoint; usernameField.stringValue = settings.username
        folderField.stringValue = settings.remoteFolder; publicField.stringValue = settings.publicBaseURL
        aliasField.stringValue = settings.sshAlias; remoteRootField.stringValue = settings.sftpRemoteRoot
        portField.stringValue = settings.sftpPort.map(String.init) ?? ""
        let options = settings.s3 ?? S3Options()
        regionField.stringValue = options.region; bucketField.stringValue = options.bucket
        profileField.stringValue = options.credentialsProfile
        sourcePopup.selectItem(at: destination != nil && options.credentialsProfile.isEmpty && settings.transport == .s3 ? 1 : 0)
        aclCheckbox.state = options.publicReadACL ? .on : .off
        passwordField.stringValue = destination.map { settings.storesSecretInKeychain ? passwordFor($0) : "" } ?? ""
        showsLegacySFTPEndpoint = settings.transport == .sftp && !settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        formResult.show(.idle, "")
        refreshForm(); updateDefaultButton(); scrollToTop(); notifyPreferredHeight()
    }

    /// Assembles the destination the form describes, preserving the edited entry's id.
    func makeDraft() throws -> (destination: PublishingDestination, password: String) {
        var settings = editing?.settings ?? PublishingSettings()
        let transport = selectedProtocol
        settings.transport = transport
        // An SFTP destination names its host in the SSH host row; the Endpoint row only exists to show a value saved by an older build.
        settings.endpoint = transport == .sftp && !showsLegacySFTPEndpoint ? "" : endpointField.stringValue
        settings.remoteFolder = folderField.stringValue
        settings.publicBaseURL = publicField.stringValue
        settings.username = usernameField.stringValue
        settings.sshAlias = aliasField.stringValue; settings.sftpRemoteRoot = remoteRootField.stringValue
        let portText = portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if portText.isEmpty { settings.sftpPort = nil }
        else {
            guard let port = Int(portText) else { throw PublishingFailure("SFTP port must be a number, or empty to use SSH configuration.") }
            settings.sftpPort = port
        }
        var password = transport == .sftp ? "" : passwordField.stringValue
        if transport == .s3 {
            var options = S3Options()
            options.region = regionField.stringValue; options.bucket = bucketField.stringValue
            options.publicReadACL = aclCheckbox.state == .on
            if keychainSource {
                guard !settings.username.isEmpty, !password.isEmpty else {
                    throw PublishingFailure("Enter the access key ID and secret, or choose an AWS credentials profile.")
                }
            } else {
                options.credentialsProfile = profileField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !options.credentialsProfile.isEmpty else { throw PublishingFailure("Enter an AWS profile name, such as default.") }
                settings.username = ""; password = ""
            }
            settings.s3 = options
        } else { settings.s3 = nil }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = PublishingDestination(id: editing?.id ?? UUID().uuidString,
                                                name: typed.isEmpty ? settings.suggestedName : typed, settings: settings)
        return (destination, password)
    }

    @objc func saveTapped() {
        do { let draft = try makeDraft(); showResult(.working, "Saving…"); onSave?(draft.destination, draft.password) }
        catch { showStatus(error.localizedDescription) }
    }
    @objc func testTapped() {
        if let (field, sentence) = emptyRequiredField() { flag(field, sentence); return }
        do { let draft = try makeDraft(); showResult(.working, "Testing…"); onTest?(draft.destination, draft.password) }
        catch { showStatus(error.localizedDescription) }
    }

    /// The first required address field that is still empty for this protocol, with the sentence that names it. Test says which field it
    /// needs instead of a general "enter a complete URL" (R2-017).
    func emptyRequiredField() -> (NSTextField, String)? {
        func empty(_ field: NSTextField) -> Bool { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch selectedProtocol {
        case .webDAV, .ftp, .ftps:
            if empty(endpointField) { return (endpointField, "Endpoint URL is empty. Enter the server address, such as \(endpointField.placeholderString ?? "https://example.com/files").") }
        case .sftp:
            if !showsLegacySFTPEndpoint, empty(aliasField) { return (aliasField, "SSH host is empty. Enter an alias from ~/.ssh/config, or a host name.") }
        case .s3:
            if empty(bucketField) { return (bucketField, "Bucket is empty. Enter the name of the S3 bucket.") }
        }
        return nil
    }
    /// The field that needs attention: named in the result line, outlined in the error colour (with the words, so not colour alone), and focused.
    /// The outline goes as soon as the field is edited.
    private func flag(_ field: NSTextField, _ sentence: String) {
        showStatus(sentence)
        field.wantsLayer = true
        field.layer?.borderWidth = 2; field.layer?.cornerRadius = DesignTokens.Radius.md
        field.effectiveAppearance.performAsCurrentDrawingAppearance { field.layer?.borderColor = DesignTokens.Palette.feedbackError.cgColor }
        field.setAccessibilityHelp(sentence)
        window?.makeFirstResponder(field)
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification, object: field, queue: .main) { [weak field] _ in
            MainActor.assumeIsolated { field?.layer?.borderWidth = 0; field?.setAccessibilityHelp(nil) }
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
    @objc func cancelFormTapped() {
        if closeOpenChoicePanels() { return }
        formResult.show(.idle, ""); onCancel?()
    }
}

extension PublishingProtocol {
    var shortTitle: String {
        switch self {
        case .webDAV: return "WebDAV"
        case .ftp: return "FTP"
        case .ftps: return "FTPS"
        case .sftp: return "SFTP"
        case .s3: return "S3"
        }
    }
}

private extension NSStackView {
    func setViews(_ views: [NSView], in gravity: NSStackView.Gravity) {
        views.forEach { addArrangedSubview($0) }
    }
}

/// A glass pop-up whose face may show a shorter title than the item it stands for: the menu rows, the accessibility value and the tooltip
/// keep the full text, and the face is only as wide as its (short) titles, so it never truncates in the narrowest sheet.
final class DestinationChoicePopUp: GlassPopUpButton {
    /// Full item title to the title the face shows; an item with no entry shows its own title.
    var faceTitles: [String: String] = [:] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var faceTitle: String { let full = titleOfSelectedItem ?? ""; return faceTitles[full] ?? full }

    override var intrinsicContentSize: NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: DesignTokens.Typography.font(.body)]
        let titles = (menu?.items.map { faceTitles[$0.title] ?? $0.title } ?? []) + [faceTitle]
        let widest = titles.map { ceil(($0 as NSString).size(withAttributes: attributes).width) }.max() ?? 0
        return NSSize(width: 2 * GlassChoiceButton.padding + widest + GlassChoiceButton.gap + GlassChoiceButton.glyphSide, height: GlassChoiceButton.height)
    }
}

/// Top-left origin, so a short form starts at the top of the scroll view instead of floating at the bottom.
final class DestinationFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// One line of feedback: a glyph and words together, so the meaning never rests on colour alone.
final class DestinationStatusRow: NSStackView {
    /// `hint` is a quiet line in the secondary colour (what Test will do); the others report something that happened.
    enum Kind { case idle, hint, working, info, success, failure }
    private(set) var kind: Kind = .idle
    let glyph = NSImageView()
    let text = NSTextField(wrappingLabelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    private typealias Palette = DesignTokens.Palette

    init(width: CGFloat = PublishingDestinationsView.contentWidth, maxLines: Int = 0) {
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .top; spacing = DesignTokens.Space.s2
        glyph.imageScaling = .scaleProportionallyDown
        glyph.widthAnchor.constraint(equalToConstant: DesignTokens.Typography.iconRegular).isActive = true
        glyph.heightAnchor.constraint(equalToConstant: DesignTokens.Typography.iconRegular).isActive = true
        DesignTokens.Typography.apply(.body, to: text); DesignTokens.Typography.apply(.caption, to: detail)
        let textWidth = width - DesignTokens.Typography.iconRegular - DesignTokens.Space.s2
        text.preferredMaxLayoutWidth = textWidth; detail.preferredMaxLayoutWidth = textWidth
        // A bounded row cuts its last line with an ellipsis; the whole message stays in the accessibility label and the field's text.
        text.maximumNumberOfLines = maxLines; detail.maximumNumberOfLines = maxLines
        text.lineBreakMode = .byWordWrapping; (text.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
        (detail.cell as? NSTextFieldCell)?.truncatesLastVisibleLine = true
        detail.textColor = Palette.Text.secondary
        let column = NSStackView(views: [text, detail]); column.orientation = .vertical; column.alignment = .leading; column.spacing = 2
        addArrangedSubview(glyph); addArrangedSubview(column)
        show(.idle, "")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ kind: Kind, _ message: String, detail extra: String = "") {
        self.kind = kind
        text.stringValue = message; detail.stringValue = extra; detail.isHidden = extra.isEmpty
        let icon: FAIcon?
        switch kind {
        case .success: icon = .circleCheck
        case .failure: icon = .xmarkCircle
        case .idle, .hint, .working, .info: icon = nil
        }
        glyph.image = icon.flatMap { PublishingDestinationsView.icon($0, pointSize: DesignTokens.Typography.iconInline, description: kind == .success ? "Connected" : "Error") }
        glyph.isHidden = glyph.image == nil
        let color = kind == .failure ? Palette.feedbackError : (kind == .hint ? Palette.Text.secondary : Palette.Text.primary)
        text.textColor = color; glyph.contentTintColor = color
        DesignTokens.Typography.apply(kind == .hint ? .caption : .body, to: text)
        isHidden = kind == .idle || message.isEmpty
        setAccessibilityElement(!isHidden); setAccessibilityRole(.staticText)
        setAccessibilityLabel(message + (extra.isEmpty ? "" : ". " + extra))
    }
}

/// The "Default" pill: a check glyph and the word, drawn with theme-aware layer colours.
final class DefaultPillView: NSView {
    let glyph = NSImageView(), label = NSTextField(labelWithString: "Default")
    private typealias Palette = DesignTokens.Palette
    var emphasized = false { didSet { refreshColors(); needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true; layer?.borderWidth = 1
        glyph.image = PublishingDestinationsView.icon(.check, pointSize: DesignTokens.Typography.readableMinimum)
        glyph.imageScaling = .scaleProportionallyDown
        label.font = DesignTokens.Typography.font(.bodyStrong)
        let stack = NSStackView(views: [glyph, label]); stack.orientation = .horizontal; stack.spacing = DesignTokens.Space.s1; stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Space.s3),
                                     stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Space.s3),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor),
                                     heightAnchor.constraint(equalToConstant: DesignTokens.Size.control - DesignTokens.Space.s1)])
        setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityLabel("Default destination")
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }
    override func layout() { super.layout(); layer?.cornerRadius = bounds.height / 2 }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // Outlined and neutral, not the accent fill a selected row wears, so "Default" and "selected" are two different things.
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = (emphasized ? NSColor.alternateSelectedControlTextColor : Palette.Text.secondary).cgColor
        }
    }
    private func refreshColors() {
        let color = emphasized ? NSColor.alternateSelectedControlTextColor : Palette.Text.primary
        label.textColor = color; glyph.contentTintColor = color
    }
}
