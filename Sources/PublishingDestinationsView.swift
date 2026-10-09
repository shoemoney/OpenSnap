import AppKit

// The Destination Settings sheet content: a list of saved destinations (Add / Edit / Remove /
// Make Default) and a form for one destination. It owns no storage; the coordinator supplies
// callbacks, so every action is testable without a window or a network.
final class PublishingDestinationsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private typealias Typography = DesignTokens.Typography
    private typealias Space = DesignTokens.Space

    var onMakeDefault: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    var onSave: ((PublishingDestination, String) -> Void)?
    var onTest: ((PublishingDestination, String) -> Void)?
    var onDone: (() -> Void)?
    var passwordFor: (PublishingDestination) -> String = { _ in "" }
    /// Asks before a destination is removed. Tests replace it; the default is a modal alert.
    var confirmRemoval: (_ title: String, _ detail: String) -> Bool = PublishingDestinationsView.askToRemove

    /// The sheet is 720 wide and at most 720 tall; on a short screen it shrinks and the form scrolls instead of clipping.
    static let sheetWidth: CGFloat = 720, sheetMaxHeight: CGFloat = 720, sheetScreenMargin: CGFloat = 120, sheetMinHeight: CGFloat = 360
    static var contentWidth: CGFloat { sheetWidth - 2 * Space.s5 }
    static func sheetSize(visibleFrame: NSRect) -> NSSize {
        let height = max(sheetMinHeight, min(sheetMaxHeight, visibleFrame.height - sheetScreenMargin))
        return NSSize(width: sheetWidth, height: min(height, visibleFrame.height))
    }

    private(set) var list: PublishingDestinationList
    private(set) var editing: PublishingDestination?

    let table = NSTableView()
    let scrollView = NSScrollView()
    private let listPage = NSStackView(), formPage = NSStackView()
    private let listStatus = DestinationStatusRow()
    /// The inline Test / Save result: a glyph and text together, never colour alone.
    let formResult = DestinationStatusRow()

    // Form controls (internal so tests can fill them in like a user would).
    let nameField = NSTextField(), endpointField = NSTextField(), usernameField = NSTextField()
    let passwordField = NSSecureTextField(), folderField = NSTextField(), publicField = NSTextField()
    let aliasField = NSTextField(), remoteRootField = NSTextField(), portField = NSTextField()
    let regionField = NSTextField(), bucketField = NSTextField(), profileField = NSTextField()
    let protocolPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let aclCheckbox = NSButton(checkboxWithTitle: "Make uploads public-read (leave off when the bucket disables ACLs)", target: nil, action: nil)
    private(set) var sectionHeaders: [NSTextField] = []

    private struct Row { let label: NSTextField; let stack: NSStackView; let visible: (PublishingProtocol, Bool) -> Bool }
    private var rows: [String: Row] = [:]

    private static func button(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        Typography.apply(.body, to: button); button.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.Size.control).isActive = true
        return button
    }
    static func symbol(_ name: String, pointSize: CGFloat = Typography.iconInline, description: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
    }

    // Footer buttons: pinned below the scroll view so Return and Escape always have a visible target.
    private(set) lazy var doneButton: NSButton = {
        let button = Self.button("Done", self, #selector(doneTapped)); button.keyEquivalent = "\r"; return button
    }()
    private(set) lazy var cancelButton: NSButton = {
        let button = Self.button("Cancel", self, #selector(cancelFormTapped)); button.keyEquivalent = "\u{1b}"; return button
    }()
    private(set) lazy var saveButton: NSButton = {
        let button = Self.button("Save", self, #selector(saveTapped)); button.keyEquivalent = "\r"; return button
    }()
    private(set) lazy var testButton: NSButton = Self.button("Test", self, #selector(testTapped))
    private let listFooter = NSStackView(), formFooter = NSStackView()

    init(list: PublishingDestinationList) {
        self.list = list
        super.init(frame: .zero)
        buildList(); buildForm(); buildFooters()

        let pages = NSStackView(views: [listPage, formPage]); pages.orientation = .vertical; pages.alignment = .leading
        let document = DestinationFlippedView()
        pages.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(pages)
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true; scrollView.hasHorizontalScroller = false; scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false; scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false; addSubview(scrollView)

        let separator = NSBox(); separator.boxType = .separator; separator.translatesAutoresizingMaskIntoConstraints = false; addSubview(separator)
        for footer in [listFooter, formFooter] { footer.translatesAutoresizingMaskIntoConstraints = false; addSubview(footer) }
        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor), document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            pages.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Space.s5),
            pages.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -Space.s5),
            pages.topAnchor.constraint(equalTo: document.topAnchor, constant: Space.s5),
            pages.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -Space.s5),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor), separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomAnchor.constraint(equalTo: listFooter.bottomAnchor, constant: Space.s4),
            bottomAnchor.constraint(equalTo: formFooter.bottomAnchor, constant: Space.s4),
        ])
        for footer in [listFooter, formFooter] {
            NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s5),
                                         footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s5),
                                         footer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Space.s3)])
        }
        showList()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateDefaultButton() }

    /// Return is Done on the list and Save on the form; Escape is Done on the list (the button owns Return, so this owns Escape) and Cancel on the form.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, !listPage.isHidden else { return false }
        doneTapped(); return true
    }
    private func updateDefaultButton() {
        window?.defaultButtonCell = (listPage.isHidden ? saveButton : doneButton).cell as? NSButtonCell
    }

    private func buildFooters() {
        for footer in [listFooter, formFooter] { footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = Space.s4; footer.distribution = .fill }
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        listFooter.setViews([spacer, doneButton], in: .trailing)
        let flexible = NSView(); flexible.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [testButton, flexible, cancelButton, saveButton]); buttons.spacing = Space.s4
        formResult.translatesAutoresizingMaskIntoConstraints = false
        let column = NSStackView(views: [formResult, buttons]); column.orientation = .vertical; column.alignment = .leading; column.spacing = Space.s2
        buttons.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        formResult.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        formFooter.addArrangedSubview(column)
        column.widthAnchor.constraint(equalTo: formFooter.widthAnchor).isActive = true
    }

    // MARK: List page

    private func buildList() {
        listPage.orientation = .vertical; listPage.alignment = .leading; listPage.spacing = Space.s4
        let title = label("Upload destinations. The one marked Default receives a Webpost click; right-click Webpost to switch.")
        title.preferredMaxLayoutWidth = Self.contentWidth
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("destination"))
        column.resizingMask = .autoresizingMask; column.width = Self.contentWidth
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = DesignTokens.Size.row
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self; table.delegate = self; table.allowsEmptySelection = true
        table.setAccessibilityLabel("Destinations")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: DesignTokens.Size.row * 6).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        let add = Self.button("Add…", self, #selector(addTapped))
        let edit = Self.button("Edit…", self, #selector(editTapped))
        let remove = Self.button("Remove", self, #selector(removeTapped))
        let makeDefault = Self.button("Make Default", self, #selector(makeDefaultTapped))
        let actions = NSStackView(views: [add, edit, remove, makeDefault]); actions.spacing = Space.s4
        listStatus.translatesAutoresizingMaskIntoConstraints = false
        listPage.setViews([title, scroll, actions, listStatus], in: .leading)
        listStatus.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        listButtons = (edit, remove, makeDefault)
    }
    private var listButtons: (edit: NSButton, remove: NSButton, makeDefault: NSButton)?

    func numberOfRows(in tableView: NSTableView) -> Int { list.destinations.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard list.destinations.indices.contains(row) else { return nil }
        let destination = list.destinations[row]
        return DestinationRowView(name: destination.name, transport: destination.settings.transport.shortTitle,
                                  isDefault: destination.id == list.defaultDestination?.id)
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateListButtons() }

    var selectedDestination: PublishingDestination? {
        let row = table.selectedRow
        return list.destinations.indices.contains(row) ? list.destinations[row] : nil
    }
    func select(id: String) {
        if let index = list.destinations.firstIndex(where: { $0.id == id }) { table.selectRowIndexes([index], byExtendingSelection: false) }
        updateListButtons()
    }
    private func updateListButtons() {
        let selected = selectedDestination
        listButtons?.edit.isEnabled = selected != nil
        listButtons?.remove.isEnabled = selected != nil
        listButtons?.makeDefault.isEnabled = selected != nil && selected?.id != list.defaultDestination?.id
    }

    /// Replaces the list (after a save, remove or default change) and returns to the list page.
    func reload(_ list: PublishingDestinationList, status text: String = "", selecting id: String? = nil) {
        self.list = list
        table.reloadData()
        if let id { select(id: id) }
        showList()
        listStatus.show(text.isEmpty ? .idle : .info, text)
    }
    /// A failure from storage or a worker. The row says "Error:" and carries a glyph, so it never relies on colour.
    func showStatus(_ text: String) {
        let message = text.hasPrefix("Error:") ? text : "Error: " + text
        listStatus.show(.failure, message); formResult.show(.failure, message)
    }
    /// The S3 Test result: "Connected" with the server's detail, or "Error: <message>".
    func showTestResult(ok: Bool, message: String) {
        if ok { formResult.show(.success, "Connected", detail: message) }
        else { formResult.show(.failure, message.hasPrefix("Error:") ? message : "Error: " + message) }
    }

    /// Set by the coordinator: the credential an older build's destination.json still points at.
    var legacyCredentialID: String?

    @objc func addTapped() { showForm(for: nil) }
    @objc func editTapped() { if let selected = selectedDestination { showForm(for: selected) } }
    @objc func removeTapped() {
        guard let selected = selectedDestination else { return }
        let prompt = Self.removalPrompt(for: selected, in: list, legacyCredentialID: legacyCredentialID)
        guard confirmRemoval(prompt.title, prompt.detail) else { return }
        onRemove?(selected.id)
    }

    /// Names the destination, says its saved secret goes with it, and says who becomes the default.
    static func removalPrompt(for destination: PublishingDestination, in list: PublishingDestinationList,
                              legacyCredentialID: String? = nil) -> (title: String, detail: String) {
        // The Keychain item an older build's destination.json still uses is kept for downgrades.
        let keepsSecret = legacyCredentialID != nil && legacyCredentialID == destination.settings.credentialID
        var detail = destination.settings.storesSecretInKeychain && !keepsSecret
            ? "Its saved password or secret key is removed from the Keychain too. This cannot be undone."
            : "Any saved settings for it are removed. This cannot be undone."
        if destination.id == list.defaultDestination?.id {
            if let next = list.destinations.first(where: { $0.id != destination.id }) {
                detail += " It is the default, so “\(next.name)” becomes the default."
            } else {
                detail += " It is the only destination, so Webpost will need a new one before it can upload."
            }
        }
        return ("Remove “\(destination.name)”?", detail)
    }

    private static func askToRemove(_ title: String, _ detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title; alert.informativeText = detail; alert.alertStyle = .warning
        let remove = alert.addButton(withTitle: "Remove"), cancel = alert.addButton(withTitle: "Cancel")
        Typography.apply(.body, to: remove); Typography.apply(.body, to: cancel)
        for case let field as NSTextField in alert.window.contentView?.subviews ?? [] {
            field.font = Typography.floored(field.font)
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
    @objc func makeDefaultTapped() { if let selected = selectedDestination { onMakeDefault?(selected.id) } }
    @objc func doneTapped() { onDone?() }

    private func showList() {
        formPage.isHidden = true; listPage.isHidden = false
        formFooter.isHidden = true; listFooter.isHidden = false
        editing = nil; updateListButtons(); updateDefaultButton(); scrollToTop()
    }
    private func scrollToTop() {
        scrollView.contentView.scroll(to: .zero); scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Form page

    private let formHelp = NSTextField(wrappingLabelWithString: "")

    private static let captionWidth: CGFloat = 200

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
    private func addRow(_ id: String, _ title: String, _ control: NSView, visible: @escaping (PublishingProtocol, Bool) -> Bool) {
        let caption = label(title, style: .bodyStrong)
        let stack = NSStackView(views: [caption, control]); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = Space.s4
        caption.widthAnchor.constraint(equalToConstant: Self.captionWidth).isActive = true
        caption.preferredMaxLayoutWidth = Self.captionWidth
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        control.setAccessibilityLabel(title)
        rows[id] = Row(label: caption, stack: stack, visible: visible)
        formPage.addArrangedSubview(stack)
    }

    private func buildForm() {
        formPage.orientation = .vertical; formPage.alignment = .leading; formPage.spacing = Space.s3
        for popup in [protocolPopup, sourcePopup] { Typography.apply(.body, to: popup); popup.menu?.autoenablesItems = false }
        protocolPopup.addItems(withTitles: PublishingProtocol.allCases.map(\.title))
        protocolPopup.target = self; protocolPopup.action = #selector(formChanged)
        sourcePopup.addItems(withTitles: ["AWS credentials profile", "Access key stored in Keychain"])
        sourcePopup.target = self; sourcePopup.action = #selector(formChanged)
        Typography.apply(.body, to: aclCheckbox)
        Typography.apply(.body, to: passwordField)
        let all: (PublishingProtocol, Bool) -> Bool = { _, _ in true }
        formPage.addArrangedSubview(sectionHeader("Connection"))
        addRow("name", "Name", styled(nameField, "Shown in the Webpost right-click menu"), visible: all)
        addRow("protocol", "Protocol", protocolPopup, visible: all)
        addRow("endpoint", "Endpoint URL", styled(endpointField, "https://example.com/uploads"), visible: all)
        addRow("region", "Region", styled(regionField, "us-east-1 (auto for Cloudflare R2)"), visible: { p, _ in p == .s3 })
        addRow("bucket", "Bucket", styled(bucketField, "cdn.example.com"), visible: { p, _ in p == .s3 })
        addRow("folder", "Remote folder", styled(folderField, "screenshots (relative to endpoint)"), visible: all)
        addRow("public", "Public base URL", styled(publicField, "https://example.com/screenshots (optional)"), visible: all)
        addRow("alias", "SSH host alias", styled(aliasField, "myserver (from ~/.ssh/config)"), visible: { p, _ in p == .sftp })
        addRow("root", "SFTP remote root", styled(remoteRootField, "/var/www/site/uploads"), visible: { p, _ in p == .sftp })
        addRow("port", "SFTP port", styled(portField, "Use SSH configuration (optional)"), visible: { p, _ in p == .sftp })
        addRow("acl", "", aclCheckbox, visible: { p, _ in p == .s3 })
        if let last = rows["acl"]?.stack { formPage.setCustomSpacing(Space.s5, after: last) }
        formPage.addArrangedSubview(sectionHeader("Credentials"))
        addRow("source", "Source", sourcePopup, visible: { p, _ in p == .s3 })
        addRow("profile", "AWS profile", styled(profileField, "default (from ~/.aws/credentials)"), visible: { p, keychain in p == .s3 && !keychain })
        addRow("username", "Username", styled(usernameField, "Optional for anonymous destinations"),
               visible: { p, keychain in p == .s3 ? keychain : true })
        addRow("password", "Password", { passwordField.placeholderString = "Password stored in macOS Keychain"; return passwordField }(),
               visible: { p, keychain in p == .s3 ? keychain : p != .sftp })
        Typography.apply(.caption, to: formHelp); formHelp.textColor = DesignTokens.Palette.Text.secondary
        formHelp.maximumNumberOfLines = 0; formHelp.preferredMaxLayoutWidth = Self.contentWidth
        formPage.addArrangedSubview(formHelp)
        formPage.setCustomSpacing(Space.s4, after: rows["password"]!.stack)
        formPage.isHidden = true
    }

    private var keychainSource: Bool { sourcePopup.indexOfSelectedItem == 1 }
    private var selectedProtocol: PublishingProtocol {
        PublishingProtocol.allCases.indices.contains(protocolPopup.indexOfSelectedItem)
            ? PublishingProtocol.allCases[protocolPopup.indexOfSelectedItem] : .webDAV
    }

    @objc func formChanged() { refreshForm() }
    private func refreshForm() {
        let transport = selectedProtocol, keychain = keychainSource
        for row in rows.values { row.stack.isHidden = !row.visible(transport, keychain) }
        func caption(_ id: String, _ text: String) { rows[id]?.label.stringValue = text; rows[id]?.stack.arrangedSubviews.last?.setAccessibilityLabel(text) }
        switch transport {
        case .s3:
            caption("endpoint", "Endpoint (blank = AWS)"); caption("folder", "Key prefix")
            caption("username", "Access key ID"); caption("password", "Secret access key")
            formHelp.stringValue = "Path-style S3 over system curl. Public base URL maps to the key prefix; the uploaded file is downloaded from it to verify the exact bytes. Test lists the bucket without uploading."
        case .sftp:
            caption("endpoint", "Endpoint URL"); caption("folder", "Remote folder"); caption("username", "Username"); caption("password", "Password")
            formHelp.stringValue = "SFTP uses keys from SSH configuration or your agent, with strict known-host checks. Leave username and port empty to use the alias settings. Folders must exist."
        default:
            caption("endpoint", "Endpoint URL"); caption("folder", "Remote folder"); caption("username", "Username"); caption("password", "Password")
            formHelp.stringValue = "FTPS: ftp:// is explicit TLS, ftps:// is implicit TLS. Folders must exist. Public base URL maps to the upload folder; only the filename is appended."
        }
        testButton.isHidden = transport != .s3
    }

    /// Disables protocols the system tools cannot run.
    func setUnavailable(_ unavailable: Set<PublishingProtocol>) {
        for (index, transport) in PublishingProtocol.allCases.enumerated() { protocolPopup.item(at: index)?.isEnabled = !unavailable.contains(transport) }
    }

    private func showForm(for destination: PublishingDestination?) {
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
        formResult.show(.idle, "")
        listPage.isHidden = true; formPage.isHidden = false
        listFooter.isHidden = true; formFooter.isHidden = false
        refreshForm(); updateDefaultButton(); scrollToTop()
    }

    /// Assembles the destination the form describes, preserving the edited entry's id.
    func makeDraft() throws -> (destination: PublishingDestination, password: String) {
        var settings = editing?.settings ?? PublishingSettings()
        let transport = selectedProtocol
        settings.transport = transport
        settings.endpoint = endpointField.stringValue; settings.remoteFolder = folderField.stringValue
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
        do { let draft = try makeDraft(); formResult.show(.working, "Saving…"); onSave?(draft.destination, draft.password) }
        catch { showStatus(error.localizedDescription) }
    }
    @objc func testTapped() {
        do { let draft = try makeDraft(); formResult.show(.working, "Testing…"); onTest?(draft.destination, draft.password) }
        catch { showStatus(error.localizedDescription) }
    }
    @objc func cancelFormTapped() { showList() }
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

/// Top-left origin, so a short form starts at the top of the scroll view instead of floating at the bottom.
final class DestinationFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// One line of feedback: a glyph and words together, so the meaning never rests on colour alone.
final class DestinationStatusRow: NSStackView {
    enum Kind { case idle, working, info, success, failure }
    private(set) var kind: Kind = .idle
    let glyph = NSImageView()
    let text = NSTextField(wrappingLabelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    private typealias Palette = DesignTokens.Palette

    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .horizontal; alignment = .top; spacing = DesignTokens.Space.s2
        glyph.imageScaling = .scaleProportionallyDown
        glyph.widthAnchor.constraint(equalToConstant: DesignTokens.Typography.iconRegular).isActive = true
        glyph.heightAnchor.constraint(equalToConstant: DesignTokens.Typography.iconRegular).isActive = true
        DesignTokens.Typography.apply(.body, to: text); DesignTokens.Typography.apply(.caption, to: detail)
        let textWidth = PublishingDestinationsView.contentWidth - DesignTokens.Typography.iconRegular - DesignTokens.Space.s2
        text.preferredMaxLayoutWidth = textWidth; detail.preferredMaxLayoutWidth = textWidth
        text.maximumNumberOfLines = 0; detail.maximumNumberOfLines = 0
        detail.textColor = Palette.Text.secondary
        let column = NSStackView(views: [text, detail]); column.orientation = .vertical; column.alignment = .leading; column.spacing = 2
        addArrangedSubview(glyph); addArrangedSubview(column)
        show(.idle, "")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ kind: Kind, _ message: String, detail extra: String = "") {
        self.kind = kind
        text.stringValue = message; detail.stringValue = extra; detail.isHidden = extra.isEmpty
        let symbol: String?
        switch kind {
        case .success: symbol = "checkmark.circle"
        case .failure: symbol = "xmark.octagon"
        case .idle, .working, .info: symbol = nil
        }
        glyph.image = symbol.flatMap { PublishingDestinationsView.symbol($0, pointSize: DesignTokens.Typography.iconInline, description: kind == .success ? "Connected" : "Error") }
        glyph.isHidden = glyph.image == nil
        let color = kind == .failure ? Palette.feedbackError : Palette.Text.primary
        text.textColor = color; glyph.contentTintColor = color
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
        glyph.image = PublishingDestinationsView.symbol("checkmark", pointSize: DesignTokens.Typography.readableMinimum)
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
            layer?.backgroundColor = (emphasized ? NSColor.clear : Palette.State.selectedFill).cgColor
            layer?.borderColor = (emphasized ? NSColor.alternateSelectedControlTextColor : Palette.accent).cgColor
        }
    }
    private func refreshColors() {
        let color = emphasized ? NSColor.alternateSelectedControlTextColor : Palette.Text.primary
        label.textColor = color; glyph.contentTintColor = color
    }
}

/// A destination row: name, transport, and a Default pill for the destination Webpost uses.
final class DestinationRowView: NSTableCellView {
    let nameField: NSTextField, transportField: NSTextField
    private(set) var pill: DefaultPillView?
    private typealias Palette = DesignTokens.Palette

    init(name: String, transport: String, isDefault: Bool) {
        nameField = NSTextField(labelWithString: name); transportField = NSTextField(labelWithString: transport)
        super.init(frame: .zero)
        nameField.font = DesignTokens.Typography.font(.body); nameField.lineBreakMode = .byTruncatingTail
        transportField.font = DesignTokens.Typography.font(.caption)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let flexible = NSView(); flexible.setContentHuggingPriority(.init(1), for: .horizontal)
        var views: [NSView] = [nameField, transportField, flexible]
        if isDefault { let pill = DefaultPillView(); self.pill = pill; views.append(pill) }
        let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = DesignTokens.Space.s3
        stack.distribution = .fill; stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Space.s2),
                                     stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Space.s2),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        textField = nameField
        setAccessibilityLabel([name, transport, isDefault ? "Default" : nil].compactMap { $0 }.joined(separator: ", "))
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { refreshColors() } }
    private func refreshColors() {
        let emphasized = backgroundStyle == .emphasized
        nameField.textColor = emphasized ? .alternateSelectedControlTextColor : Palette.Text.primary
        transportField.textColor = emphasized ? .alternateSelectedControlTextColor : Palette.Text.secondary
        pill?.emphasized = emphasized
    }
}
