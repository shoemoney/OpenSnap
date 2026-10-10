import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Independent History presentation. Original evidence: history help/screenshot,
/// open 0x00033ae7, search 0x00033ba3, details 0x00034238, sections 0x00034faa.
/// Recovered date/search predicates are retained. Exact original popup labels and
/// runtime visual parity remain unverified; labels describe the recovered intervals.
@MainActor
final class HistoryBrowser: NSWindowController, NSCollectionViewDataSource,
    NSCollectionViewDelegate, NSSearchFieldDelegate, NSMenuItemValidation, NSWindowDelegate {
    private typealias Typography = DesignTokens.Typography
    private typealias Space = DesignTokens.Space
    private typealias Palette = DesignTokens.Palette
    enum DetailsPlacement { case beside, below }
    struct Item: Equatable {
        var id: UUID
        var name: String
        var date: Date
        var size: CGSize
        var action: String
        var text: String
        var destination: String?
        var link: URL?
        var previewURL: URL?
        var missing: Bool
        /// False when the entry has a link but no recorded publication destination, so the app cannot take it down; the icon then says why.
        var canDeleteFromWeb = true
    }
    /// The tab names are the tile labels (`HistoryStore.Action.title`): one vocabulary, so a tab holds exactly the tiles it names.
    enum Category: Int, CaseIterable {
        case all, shared, exported, saved
        var title: String { ["All", "Shared", "Exported", "Saved"][rawValue] }
        func includes(_ item: Item) -> Bool { self == .all || item.action == title }
    }
    enum DateFilter: Int, CaseIterable {
        case all, lastHour, yesterday, last48
        var title: String { ["All dates", "Last hour", "Yesterday", "Last 48 hours"][rawValue] }
    }
    enum Action: Int, CaseIterable {
        case open, copy, copyLink, openLink, remove, deleteFiles, deleteRemote
        var title: String { ["Open", "Copy", "Copy Link", "Open Link", "Hide from History", "Move to Trash", "Delete from Web"][rawValue] }
        /// The toolbar-style action row is icon-only; the title is the tooltip, the accessibility label and the context-menu text.
        var icon: FAIcon { [FAIcon.openExternal, .copy, .link, .globe, .eyeSlash, .trash, .linkSlash][rawValue] }
    }
    struct Section { var day: Date; var title: String; var items: [Item] }
    /// Persisted keys. `jpeg` is the stored name for JPG, and `opensnap` is the editable document.
    nonisolated static let dragFormats = ["png", "jpeg", "pdf", "tiff", "svg", "opensnap"]
    nonisolated static func dragFormatTitle(_ format: String) -> String {
        switch format {
        case "jpeg": return "JPG"
        case "opensnap": return ".opensnap document"
        default: return format.uppercased()
        }
    }
    static let defaultSize = NSSize(width: 1000, height: 720), minimumSize = NSSize(width: 880, height: 600)
    /// Below this content width the details panel moves from beside the grid to under it.
    static let detailsCollapseWidth: CGFloat = 760
    /// The narrowest a tile gets; the preview is `previewAspect` as tall as the tile is wide, so a stretched tile shows a bigger preview
    /// instead of a preview floating in blank space.
    static let minimumTileWidth: CGFloat = 210, previewAspect: CGFloat = 0.65
    static let tileInset = DesignTokens.Space.s2, tileTextSpacing = DesignTokens.Space.s1
    /// Space between neighbouring tiles, and the grid's side inset.
    static let tileGap = DesignTokens.Space.s4, gridSideInset = DesignTokens.Space.s3
    /// Tiles share the row width exactly: as many as fit at the minimum width, each stretched to fill, so the gap between
    /// neighbours is always `tileGap` instead of the flow layout spreading fixed tiles to the far edges.
    static func tileWidth(forGridWidth width: CGFloat) -> CGFloat {
        let available = width - 2 * gridSideInset
        let columns = max(1, ((available + tileGap) / (minimumTileWidth + tileGap)).rounded(.down))
        return max(1, ((available - (columns - 1) * tileGap) / columns).rounded(.down))
    }
    static func previewHeight(forTileWidth width: CGFloat) -> CGFloat { ((width - 2 * tileInset) * previewAspect).rounded() }
    /// A tile is its preview, the name line and the action line, with nothing under them.
    static func tileHeight(forTileWidth width: CGFloat) -> CGFloat {
        func line(_ style: Typography.Style) -> CGFloat { ceil(NSLayoutManager().defaultLineHeight(for: Typography.font(style))) }
        return 2 * tileInset + previewHeight(forTileWidth: width) + 2 * tileTextSpacing + line(.body) + line(.caption)
    }
    static func tileSize(forGridWidth width: CGFloat) -> NSSize {
        let tile = tileWidth(forGridWidth: width)
        return NSSize(width: tile, height: tileHeight(forTileWidth: tile))
    }
    nonisolated static let dragFormatDefaultsKey = "OpenSnap.HistoryDragFormat"

    var onOpen: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onCopy: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onCopyLink: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onOpenLink: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onRemove: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onDeleteFiles: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onDeleteRemote: (([UUID]) -> Void)? { didSet { updateControls() } }
    var onExport: ((UUID, String) throws -> Data)?
    var onError: ((Error) -> Void)?

    private(set) var sections: [Section] = []
    private(set) var category: Category = .all
    private(set) var dateFilter: DateFilter = .all
    private(set) var query = ""
    var selectedIDs: [UUID] { selectedItems.map(\.id) }
    var dragFormat: String { Self.dragFormats.contains(defaults.string(forKey: Self.dragFormatDefaultsKey) ?? "") ? defaults.string(forKey: Self.dragFormatDefaultsKey)! : "png" }
    var visibleItems: [Item] { sections.flatMap(\.items) }
    private var items: [Item] = []
    private var lastRefreshDay: Date?
    #if HISTORY_BROWSER_TESTS
    private(set) var fullReloadCount = 0
    private(set) var partialReloadCount = 0
    #endif
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let thumbnails = NSCache<NSURL, NSImage>()
    private let collection = HistoryGrid()
    private let categoryControl = NSSegmentedControl()
    private let datePopup = NSPopUpButton()
    private let formatPopup = NSPopUpButton()
    private let search = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private let warning = NSTextField(wrappingLabelWithString: "")
    private let detailsImage = NSImageView()
    private var detailValues: [String: NSTextField] = [:]
    private var detailPairs: [NSStackView] = []
    private var detailLabelWidths: [NSLayoutConstraint] = []
    private var detailsFields: NSStackView?
    private let detailsHint = NSTextField(wrappingLabelWithString:"Select a snap to see its details.")
    /// What the details column shows with nothing selected: how many snaps the grid holds, by kind, so the column is never blank.
    private let detailsSummaryTitle = NSTextField(labelWithString:""), detailsSummary = NSTextField(wrappingLabelWithString:"")
    private var buttons: [Action: NSButton] = [:]
    private var contextItems: [Action: NSMenuItem] = [:]
    /// The grid's scroll view. Horizontal scrolling is off: the grid reflows instead.
    private(set) var gridScrollView: NSScrollView?
    /// The centred message over the grid when there is nothing to show.
    let emptyState = NSStackView()
    let emptyTitle = NSTextField(labelWithString: ""), emptyHint = NSTextField(wrappingLabelWithString: "")
    /// Shown with "No history items match these filters", so a dead end is one click from the full list.
    private(set) lazy var clearFiltersButton: NSButton = {
        let button = NSButton(title:"Clear filters",target:self,action:#selector(clearFilters))
        button.bezelStyle = .rounded; Typography.apply(.body,to:button)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant:DesignTokens.Size.control).isActive = true
        return button
    }()
    let filterRow = NSStackView(), actionRow = NSStackView()
    let detailsPanel = NSStackView()
    private(set) var detailsPlacement: DetailsPlacement = .beside
    private var besideConstraints: [NSLayoutConstraint] = [], belowConstraints: [NSLayoutConstraint] = []
    /// The Save to History key equivalent as the empty state should show it, or nil when the menu has none. Tests replace it.
    var saveShortcut: () -> String? = { HistoryBrowser.liveSaveToHistoryShortcut(menu: NSApp?.mainMenu) }
    private var selectionChanging = false
    private var selectedItems: [Item] {
        collection.selectionIndexPaths.sorted { a,b in a.section == b.section ? a.item < b.item : a.section < b.section }.compactMap(item)
    }

    convenience init() { self.init(defaults: .standard, calendar: .current, now: Date.init) }
    init(defaults: UserDefaults, calendar: Calendar, now: @escaping () -> Date) {
        self.defaults = defaults; self.calendar = calendar; self.now = now
        let window = NSWindow(contentRect: NSRect(origin:.zero,size:Self.defaultSize),
                              styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        window.setFrame(NSRect(origin:.zero,size:Self.defaultSize),display:false)
        window.title = "History"; window.minSize = Self.minimumSize
        window.isReleasedWhenClosed = false
        super.init(window:window)
        window.delegate = self
        thumbnails.countLimit = 256; thumbnails.totalCostLimit = 64*1024*1024
        buildUI(); rebuild(keeping: [])
    }
    required init?(coder: NSCoder) { return nil }

    func update(items: [Item]) {
        let selected = Set(selectedIDs)
        var seen = Set<UUID>()
        // Core supplies reverse insertion order. Dates can be edited or imported;
        // timestamp sorting here would change the recovered History ordering.
        let updated = items.filter { seen.insert($0.id).inserted }
        let movingDateWindow = dateFilter == .lastHour || dateFilter == .last48
        guard updated != self.items || lastRefreshDay != calendar.startOfDay(for:now()) || movingDateWindow else { return }
        let old = Dictionary(uniqueKeysWithValues:self.items.map { ($0.id,$0) })
        for value in updated where old[value.id] != value {
            if let url = value.previewURL { thumbnails.removeObject(forKey:url as NSURL) }
            if let url = old[value.id]?.previewURL { thumbnails.removeObject(forKey:url as NSURL) }
        }
        self.items = updated
        rebuild(keeping:selected,preserveScroll:true)
    }
    func setFilters(category: Category, date: DateFilter = .all, query: String = "") {
        clearConfirmation()
        let selected = Set(selectedIDs)
        self.category = category; dateFilter = date; self.query = query
        categoryControl.selectedSegment = category.rawValue
        datePopup.selectItem(at:date.rawValue); search.stringValue = query
        rebuild(keeping:selected)
    }
    func select(ids: [UUID]) {
        let wanted = Set(ids)
        var paths = Set<IndexPath>()
        for (section,group) in sections.enumerated() { for (index,value) in group.items.enumerated() where wanted.contains(value.id) {
            paths.insert(IndexPath(item:index,section:section))
        } }
        collection.selectionIndexPaths = paths
        updateControls()
    }
    func setDragFormat(_ format: String) {
        guard let index = Self.dragFormats.firstIndex(of:format) else { return }
        defaults.set(format,forKey:Self.dragFormatDefaultsKey); formatPopup.selectItem(at:index)
    }
    func canPerform(_ action: Action) -> Bool {
        let selected = selectedItems
        guard !selected.isEmpty, callback(action) != nil else { return false }
        switch action {
        case .open,.copy,.deleteFiles: return selected.allSatisfy { !$0.missing }
        case .copyLink,.openLink: return selected.allSatisfy { $0.link != nil }
        case .deleteRemote: return selected.allSatisfy { $0.link != nil && $0.canDeleteFromWeb }
        case .remove: return true
        }
    }
    func perform(_ action: Action) {
        guard canPerform(action) else { return }
        let ids = selectedIDs // Capture UUIDs before a callback changes the catalog.
        let before = pasteboardChangeCount()
        callback(action)?(ids)
        if let message = Self.confirmation(for:action), pasteboardChangeCount() != before { confirm(message) }
    }
    /// The tooltip of Delete from Web: its name, or the reason it is off for a published entry the app has no destination record for.
    nonisolated static func deleteRemoteHelp(for selected: [Item]) -> String {
        let unrecorded = !selected.isEmpty && selected.allSatisfy { $0.link != nil } && selected.contains { !$0.canDeleteFromWeb }
        return unrecorded ? "Delete from Web is unavailable: this was published before the app recorded where it went, so it can only be removed on the server."
                          : Action.deleteRemote.title
    }
    /// What the footer says once a clipboard action has written to the pasteboard.
    nonisolated static func confirmation(for action: Action) -> String? {
        switch action {
        case .copy: return "Image copied"
        case .copyLink: return "Link copied"
        default: return nil
        }
    }
    private func callback(_ action: Action) -> (([UUID]) -> Void)? {
        switch action {
        case .open: return onOpen
        case .copy: return onCopy
        case .copyLink: return onCopyLink
        case .openLink: return onOpenLink
        case .remove: return onRemove
        case .deleteFiles: return onDeleteFiles
        case .deleteRemote: return onDeleteRemote
        }
    }

    private func dateIncludes(_ date: Date,reference: Date) -> Bool {
        switch dateFilter {
        case .all: return true
        case .lastHour: return date > reference.addingTimeInterval(-3600) && date < .distantFuture
        case .last48: return date > reference.addingTimeInterval(-172800) && date < .distantFuture
        case .yesterday:
            let today = calendar.startOfDay(for:reference)
            guard let start = calendar.date(byAdding:.day,value:-1,to:today),
                  let nextDay = calendar.date(byAdding:.day,value:1,to:start) else { return false }
            // Modern calendar-day boundary with strict endpoints. Original used
            // NSCalendarDate +23h59m59s; its DST behavior remains runtime-unverified.
            return date > start && date < nextDay.addingTimeInterval(-1)
        }
    }
    private func rebuild(keeping selected: Set<UUID>,preserveScroll: Bool = false) {
        let previous = sections
        let scroll = collection.enclosingScrollView
        let origin = scroll?.contentView.bounds.origin
        let reference = now()
        let filtered = items.filter { value in
            category.includes(value) && dateIncludes(value.date,reference:reference) &&
                (query.isEmpty || [value.name,value.text,value.link?.absoluteString ?? ""]
                    .contains { $0.range(of:query,options:.caseInsensitive) != nil })
        }
        let today = calendar.startOfDay(for:reference), yesterday = calendar.date(byAdding:.day,value:-1,to:today)
        lastRefreshDay = today
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateStyle = .full
        sections = []
        for value in filtered {
            let day = calendar.startOfDay(for:value.date)
            if sections.last?.day != day {
                let title = day == today ? "Today" : (day == yesterday ? "Yesterday" : formatter.string(from:day))
                sections.append(Section(day:day,title:title,items:[]))
            }
            sections[sections.count-1].items.append(value)
        }
        selectionChanging = true
        let sameStructure = previous.count == sections.count && zip(previous,sections).allSatisfy {
            $0.day == $1.day && $0.items.map(\.id) == $1.items.map(\.id)
        }
        if preserveScroll && sameStructure {
            var changed = Set<IndexPath>(), headers = IndexSet()
            for section in sections.indices {
                if previous[section].title != sections[section].title { headers.insert(section) }
                for index in sections[section].items.indices where previous[section].items[index] != sections[section].items[index] {
                    changed.insert(IndexPath(item:index,section:section))
                }
            }
            if !headers.isEmpty { collection.reloadSections(headers) }
            if !changed.isEmpty {
                collection.reloadItems(at:changed)
                #if HISTORY_BROWSER_TESTS
                partialReloadCount += 1
                #endif
            }
        } else {
            collection.reloadData()
            #if HISTORY_BROWSER_TESTS
            fullReloadCount += 1
            #endif
        }
        select(ids:Array(selected)); selectionChanging = false
        if preserveScroll, let scroll, let origin {
            collection.layoutSubtreeIfNeeded()
            let maximumY = max(0,collection.bounds.height-scroll.contentView.bounds.height)
            scroll.contentView.scroll(to:NSPoint(x:origin.x,y:min(maximumY,max(0,origin.y))))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        updateControls()
    }
    private func item(_ path: IndexPath) -> Item? {
        guard sections.indices.contains(path.section), sections[path.section].items.indices.contains(path.item) else { return nil }
        return sections[path.section].items[path.item]
    }
    private func thumbnail(_ value: Item) -> NSImage? {
        guard !value.missing, let url = value.previewURL, url.isFileURL else { return nil }
        if let cached = thumbnails.object(forKey:url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,
                [kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,
                 kCGImageSourceThumbnailMaxPixelSize:320,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { return nil }
        let result = NSImage(cgImage:image,size:.zero)
        thumbnails.setObject(result,forKey:url as NSURL,cost:image.bytesPerRow*image.height)
        return result
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let root = NSStackView(); root.orientation = .vertical; root.spacing = Space.s3; root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:Space.s4),root.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-Space.s4),
                                     root.topAnchor.constraint(equalTo:content.topAnchor,constant:Space.s4),root.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-Space.s4)])

        // Filter row: category, search, date. It lives in the content area.
        categoryControl.segmentCount = Category.allCases.count; categoryControl.trackingMode = .selectOne
        categoryControl.segmentDistribution = .fit; Typography.apply(.body,to:categoryControl)
        for value in Category.allCases { categoryControl.setLabel(value.title,forSegment:value.rawValue) }
        categoryControl.selectedSegment = 0; categoryControl.target = self; categoryControl.action = #selector(filtersChanged)
        categoryControl.setAccessibilityLabel("History category")
        Typography.apply(.body,to:search); search.placeholderString = "Search history"; search.delegate = self
        search.sendsSearchStringImmediately = true; search.setAccessibilityLabel("Search history")
        search.widthAnchor.constraint(greaterThanOrEqualToConstant:160).isActive = true
        search.setContentHuggingPriority(.defaultLow,for:.horizontal)
        datePopup.addItems(withTitles:DateFilter.allCases.map(\.title)); Typography.apply(.body,to:datePopup)
        datePopup.target = self; datePopup.action = #selector(filtersChanged); datePopup.setAccessibilityLabel("History date filter")
        configure(filterRow,[categoryControl,search,datePopup]); root.addArrangedSubview(filterRow)

        // Action row: the seven actions as a toolbar, plus the drag format. Disabled ones stay in place so the row does not jump.
        let actions = Action.allCases.map { action -> NSButton in
            let button = NSButton(title:"",target:self,action:#selector(actionInvoked(_:)))
            button.tag = action.rawValue; button.bezelStyle = .rounded; Typography.apply(.body,to:button)
            if let symbol = ChromeIcons.resolve(action.icon,pointSize:Typography.iconInline).image {
                button.image = symbol; button.imagePosition = .imageOnly
            } else { button.title = action.title }
            button.toolTip = action.title; button.setAccessibilityLabel(action.title)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant:DesignTokens.Size.tool.width).isActive = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant:DesignTokens.Size.control).isActive = true
            buttons[action] = button; return button
        }
        let formatLabel = NSTextField(labelWithString:"Drag as"); Typography.apply(.body,to:formatLabel)
        formatPopup.addItems(withTitles:Self.dragFormats.map(Self.dragFormatTitle)); Typography.apply(.body,to:formatPopup)
        formatPopup.selectItem(at:Self.dragFormats.firstIndex(of:dragFormat) ?? 0)
        formatPopup.target = self; formatPopup.action = #selector(formatChanged); formatPopup.setAccessibilityLabel("History drag export format")
        let flexible = NSView(); flexible.setContentHuggingPriority(.init(1),for:.horizontal)
        configure(actionRow,actions+[flexible,formatLabel,formatPopup]); actionRow.spacing = Space.s2
        actionRow.setCustomSpacing(Space.s5,after:actions.last!)
        root.addArrangedSubview(actionRow)

        // Body: the grid, with the details panel beside it (or under it when narrow).
        let body = NSView(); body.translatesAutoresizingMaskIntoConstraints = false; root.addArrangedSubview(body)
        let layout = HistoryFlowLayout(); layout.itemSize = Self.tileSize(forGridWidth:640)
        layout.minimumInteritemSpacing = Self.tileGap; layout.minimumLineSpacing = Space.s3; layout.headerReferenceSize = NSSize(width:1,height:Self.dayHeaderHeight)
        layout.sectionInset = NSEdgeInsets(top:0,left:Self.gridSideInset,bottom:Space.s3,right:Self.gridSideInset)
        collection.frame = NSRect(x:0,y:0,width:640,height:400); collection.autoresizingMask = [.width]
        collection.collectionViewLayout = layout; collection.dataSource = self; collection.delegate = self
        collection.isSelectable = true; collection.allowsMultipleSelection = true; collection.allowsEmptySelection = true
        collection.backgroundColors = [Palette.Surface.content]; collection.setAccessibilityLabel("History thumbnail grid")
        collection.register(HistoryThumbnail.self,forItemWithIdentifier:HistoryThumbnail.identifier)
        collection.register(HistoryDayHeader.self,forSupplementaryViewOfKind:NSCollectionView.elementKindSectionHeader,withIdentifier:HistoryDayHeader.identifier)
        collection.setDraggingSourceOperationMask(.copy,forLocal:false); collection.setDraggingSourceOperationMask(.copy,forLocal:true)
        collection.browser = self
        // The keyboard starts on the grid, where Return opens the selection and Escape closes the window.
        window?.initialFirstResponder = collection
        let menu = NSMenu(title:"History actions"); menu.font = Typography.font(.body)
        for action in Action.allCases {
            let item = NSMenuItem(title:action.title,action:#selector(actionInvoked(_:)),keyEquivalent:"")
            item.tag = action.rawValue; item.target = self; menu.addItem(item); contextItems[action] = item
        }
        collection.menu = menu
        let scroll = NSScrollView(frame:NSRect(x:0,y:0,width:640,height:400)); scroll.documentView = collection
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder; scroll.translatesAutoresizingMaskIntoConstraints = false
        gridScrollView = scroll
        body.addSubview(scroll)
        body.setContentHuggingPriority(.defaultLow,for:.vertical); body.setContentCompressionResistancePriority(.init(100),for:.vertical)
        body.heightAnchor.constraint(greaterThanOrEqualToConstant:240).isActive = true

        buildDetails()
        body.addSubview(detailsPanel)
        besideConstraints = [scroll.leadingAnchor.constraint(equalTo:body.leadingAnchor),scroll.topAnchor.constraint(equalTo:body.topAnchor),
                             scroll.bottomAnchor.constraint(equalTo:body.bottomAnchor),scroll.trailingAnchor.constraint(equalTo:detailsPanel.leadingAnchor,constant:-Space.s3),
                             detailsPanel.trailingAnchor.constraint(equalTo:body.trailingAnchor),detailsPanel.topAnchor.constraint(equalTo:body.topAnchor),
                             detailsPanel.bottomAnchor.constraint(lessThanOrEqualTo:body.bottomAnchor),detailsPanel.widthAnchor.constraint(equalToConstant:Self.detailsWidth)]
        belowConstraints = [scroll.leadingAnchor.constraint(equalTo:body.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:body.trailingAnchor),
                            scroll.topAnchor.constraint(equalTo:body.topAnchor),scroll.bottomAnchor.constraint(equalTo:detailsPanel.topAnchor,constant:-Space.s3),
                            detailsPanel.leadingAnchor.constraint(equalTo:body.leadingAnchor),detailsPanel.trailingAnchor.constraint(equalTo:body.trailingAnchor),
                            detailsPanel.bottomAnchor.constraint(equalTo:body.bottomAnchor),detailsPanel.heightAnchor.constraint(equalToConstant:Self.detailsBelowHeight)]
        NSLayoutConstraint.activate(besideConstraints)

        buildEmptyState(over:scroll,in:body)

        Typography.apply(.body,to:warning); warning.textColor = Palette.feedbackError; warning.maximumNumberOfLines = 0
        root.addArrangedSubview(warning)
        Typography.apply(.caption,to:status); status.textColor = Palette.Text.secondary; root.addArrangedSubview(status)
        for child in root.arrangedSubviews { child.widthAnchor.constraint(equalTo:root.widthAnchor).isActive = true }
        content.layoutSubtreeIfNeeded()
        layoutDetails(forContentWidth:content.bounds.width)
    }
    static let detailsWidth: CGFloat = 248, detailsBelowHeight: CGFloat = 176, dayHeaderHeight: CGFloat = 44

    private func configure(_ stack: NSStackView,_ views: [NSView]) {
        stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = Space.s3
        views.forEach { stack.addArrangedSubview($0) }
    }
    private func buildDetails() {
        detailsPanel.translatesAutoresizingMaskIntoConstraints = false
        detailsPanel.orientation = .vertical; detailsPanel.alignment = .leading; detailsPanel.spacing = Space.s3
        detailsImage.imageScaling = .scaleProportionallyUpOrDown; detailsImage.setAccessibilityLabel("Selected history preview")
        let imageHeight = detailsImage.heightAnchor.constraint(equalToConstant:150); imageHeight.priority = .init(749); imageHeight.isActive = true
        detailsImage.heightAnchor.constraint(greaterThanOrEqualToConstant:48).isActive = true
        detailsImage.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let fields = NSStackView(); fields.orientation = .vertical; fields.alignment = .leading; fields.spacing = Space.s2
        for name in ["Name","Date","Size","Action","Destination"] {
            let label = NSTextField(labelWithString:name+":"); label.font = Typography.font(.bodyStrong)
            let value = NSTextField(wrappingLabelWithString:"—"); value.font = Typography.font(.body); value.isSelectable = true
            // A link or a long file name never wraps into a clipped second line: it keeps its two ends and the tooltip carries the rest.
            let isLink = name == "Destination"
            value.maximumNumberOfLines = isLink ? 1 : 2; value.lineBreakMode = isLink ? .byTruncatingMiddle : .byTruncatingTail
            value.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
            value.setAccessibilityLabel(name); detailValues[name] = value
            let pair = NSStackView(views:[label,value]); pair.orientation = .vertical; pair.alignment = .leading; pair.spacing = 0
            detailPairs.append(pair); fields.addArrangedSubview(pair)
            detailLabelWidths.append(label.widthAnchor.constraint(equalToConstant:118))
            pair.widthAnchor.constraint(equalTo:fields.widthAnchor).isActive = true
        }
        detailsFields = fields
        detailsHint.font = Typography.font(.body); detailsHint.textColor = Palette.Text.secondary; detailsHint.maximumNumberOfLines = 0
        detailsHint.preferredMaxLayoutWidth = Self.detailsWidth
        detailsSummaryTitle.font = Typography.font(.bodyStrong); detailsSummary.font = Typography.font(.body)
        detailsSummary.maximumNumberOfLines = 0; detailsSummary.preferredMaxLayoutWidth = Self.detailsWidth
        detailsSummaryTitle.setAccessibilityElement(true); detailsSummary.setAccessibilityElement(true)
        detailsPanel.addArrangedSubview(detailsSummaryTitle); detailsPanel.addArrangedSubview(detailsSummary)
        detailsPanel.setCustomSpacing(Space.s5,after:detailsSummary)
        detailsPanel.addArrangedSubview(detailsHint)
        detailsPanel.addArrangedSubview(detailsImage); detailsPanel.addArrangedSubview(fields)
        detailsImage.widthAnchor.constraint(equalTo:detailsPanel.widthAnchor).isActive = true
        fields.widthAnchor.constraint(equalTo:detailsPanel.widthAnchor).isActive = true
    }
    private func buildEmptyState(over scroll: NSView,in body: NSView) {
        emptyState.orientation = .vertical; emptyState.alignment = .centerX; emptyState.spacing = Space.s2
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyTitle.font = Typography.font(.headline); emptyTitle.textColor = Palette.Text.primary; emptyTitle.alignment = .center
        emptyHint.font = Typography.font(.body); emptyHint.textColor = Palette.Text.secondary; emptyHint.alignment = .center
        emptyHint.maximumNumberOfLines = 0; emptyHint.preferredMaxLayoutWidth = 360
        emptyState.addArrangedSubview(emptyTitle); emptyState.addArrangedSubview(emptyHint); emptyState.addArrangedSubview(clearFiltersButton)
        emptyState.setCustomSpacing(Space.s4,after:emptyHint)
        body.addSubview(emptyState)
        NSLayoutConstraint.activate([emptyState.centerXAnchor.constraint(equalTo:scroll.centerXAnchor),emptyState.centerYAnchor.constraint(equalTo:scroll.centerYAnchor),
                                     emptyState.widthAnchor.constraint(lessThanOrEqualTo:scroll.widthAnchor,constant:-2*Space.s5)])
        emptyState.setAccessibilityElement(true); emptyState.setAccessibilityRole(.staticText)
    }

    /// Moves the details panel beside the grid, or under it when the content is narrower than `detailsCollapseWidth`.
    func layoutDetails(forContentWidth width: CGFloat) {
        let placement: DetailsPlacement = width < Self.detailsCollapseWidth ? .below : .beside
        guard placement != detailsPlacement else { return }
        NSLayoutConstraint.deactivate(placement == .below ? besideConstraints : belowConstraints)
        NSLayoutConstraint.activate(placement == .below ? belowConstraints : besideConstraints)
        detailsPlacement = placement
        // Below the grid the panel is a wide strip: preview on the left, fields on the right.
        detailsPanel.orientation = placement == .below ? .horizontal : .vertical
        detailsPanel.alignment = placement == .below ? .top : .leading
        for pair in detailPairs { pair.orientation = placement == .below ? .horizontal : .vertical; pair.spacing = placement == .below ? Space.s2 : 0 }
        for width in detailLabelWidths { width.isActive = placement == .below }
        window?.contentView?.layoutSubtreeIfNeeded()
    }
    func windowDidResize(_ notification: Notification) {
        if let width = window?.contentView?.bounds.width { layoutDetails(forContentWidth:width) }
    }
    override func cancelOperation(_ sender: Any?) { window?.performClose(sender) }
    /// Opening the window puts the keyboard on the grid unless a field already has it.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if let window, !(window.firstResponder is NSText) { window.makeFirstResponder(collection) }
    }

    private func updateEmptyState() {
        let nothingSaved = items.isEmpty
        emptyState.isHidden = !visibleItems.isEmpty
        emptyTitle.stringValue = nothingSaved ? "No history yet." : "No history items match these filters."
        emptyHint.stringValue = nothingSaved ? Self.emptyHint(shortcut:saveShortcut()) : ""
        emptyHint.isHidden = !nothingSaved
        clearFiltersButton.isHidden = nothingSaved || !filtersAreActive
        emptyState.setAccessibilityLabel([emptyTitle.stringValue,emptyHint.stringValue].filter { !$0.isEmpty }.joined(separator:" "))
    }
    var filtersAreActive: Bool { category != .all || dateFilter != .all || !query.isEmpty }
    @objc func clearFilters() { setFilters(category:.all,date:.all,query:"") }
    /// A functional hint: the live shortcut when the menu has one, otherwise the command's name, never an invented key.
    nonisolated static func emptyHint(shortcut: String?) -> String {
        shortcut.map { "Press \($0) to save a snap" } ?? "Use Save to History to keep a snap"
    }
    /// Reads the live main menu for the Save to History item and describes its key equivalent, e.g. "⌘S"; nil when it has none.
    static func liveSaveToHistoryShortcut(menu: NSMenu?) -> String? {
        func find(in menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.action == NSSelectorFromString("saveHistory") { return item }
                if let submenu = item.submenu, let found = find(in:submenu) { return found }
            }
            return nil
        }
        guard let menu, let item = find(in:menu), item.keyEquivalent.count == 1 else { return nil }
        return shortcutDescription(keyEquivalent:item.keyEquivalent,modifiers:item.keyEquivalentModifierMask)
    }
    nonisolated static func shortcutDescription(keyEquivalent key: String,modifiers: NSEvent.ModifierFlags) -> String {
        var flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if key != key.lowercased() { flags.insert(.shift) } // an uppercase key equivalent implies Shift
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key.uppercased()
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views:views); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = Space.s3
        return stack
    }
    private func updateControls() {
        let selected = selectedItems
        for action in Action.allCases { buttons[action]?.isEnabled = canPerform(action) }
        if let delete = buttons[.deleteRemote] {
            // Before the window's tooltips are adopted the plain tooltip is the name; the reason replaces it, and the name comes back with it.
            let help = Self.deleteRemoteHelp(for:selected)
            if help != Action.deleteRemote.title || AppToolTip.text(for:delete) != nil { AppToolTip.setText(help,for:delete) }
        }
        status.stringValue = transientStatus ?? Self.statusText(shown:visibleItems.count,total:items.count,selected:selected.count)
        updateEmptyState()
        let missingCount = selected.filter(\.missing).count
        warning.stringValue = missingCount == 0 ? "" : "Error: \(missingCount) selected \(missingCount == 1 ? "file is" : "files are") missing. You can remove the history entry or use its web link."
        warning.isHidden = missingCount == 0
        detailsHint.isHidden = !selected.isEmpty || visibleItems.isEmpty; detailsImage.isHidden = selected.isEmpty; detailsFields?.isHidden = selected.isEmpty
        let summary = Self.summaryLines(for:visibleItems)
        detailsSummaryTitle.isHidden = !selected.isEmpty || summary.isEmpty; detailsSummary.isHidden = detailsSummaryTitle.isHidden
        detailsSummaryTitle.stringValue = summary.first ?? ""; detailsSummary.stringValue = summary.dropFirst().joined(separator:"\n")
        // Every value carries its full text as a tooltip, so a truncated link or name is one hover from readable.
        defer { for field in detailValues.values { AppToolTip.setText(field.stringValue == "—" ? nil : field.stringValue,for:field,mirrorsToAccessibility:false) } }
        guard let value = selected.first else {
            detailsImage.image = nil; detailValues.values.forEach { $0.stringValue = "—" }; return
        }
        detailsImage.image = selected.count == 1 ? thumbnail(value) : nil
        if selected.count > 1 {
            detailValues["Name"]?.stringValue = "\(selected.count) items selected"
            detailValues["Date"]?.stringValue = "Multiple dates"; detailValues["Size"]?.stringValue = "Multiple sizes"
            detailValues["Action"]?.stringValue = Set(selected.map(\.action)).sorted().joined(separator:", ")
            detailValues["Destination"]?.stringValue = "Multiple destinations"
        } else {
            let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateStyle = .long; formatter.timeStyle = .short
            detailValues["Name"]?.stringValue = value.name; detailValues["Date"]?.stringValue = formatter.string(from:value.date)
            let size = value.size
            detailValues["Size"]?.stringValue = size.width.isFinite && size.height.isFinite ? "\(size.width.formatted()) × \(size.height.formatted())" : "Unknown size"
            detailValues["Action"]?.stringValue = value.action
            detailValues["Destination"]?.stringValue = value.destination ?? value.link?.absoluteString ?? "—"
        }
    }
    /// The headline and one line per kind for the grid's current contents, in the tab order; empty when the grid is empty.
    nonisolated static func summaryLines(for items: [Item]) -> [String] {
        guard !items.isEmpty else { return [] }
        let kinds = Category.allCases.dropFirst().compactMap { category -> String? in
            let count = items.filter(category.includes).count
            return count == 0 ? nil : "\(category.title): \(count)"
        }
        return [items.count == 1 ? "1 snap in this view" : "\(items.count) snaps in this view"] + kinds
    }
    /// "1 item · 0 selected"; with a filter on, "2 of 6 items · 0 selected"; with everything filtered out, "0 of 6 items". The footer stays
    /// on screen in every state, so the counts are always where the eye expects them.
    nonisolated static func statusText(shown: Int,total: Int,selected: Int) -> String {
        func items(_ count: Int) -> String { count == 1 ? "1 item" : "\(count) items" }
        if total == 0 { return "No items" }
        if shown == 0 { return "0 of \(items(total))" }
        let count = shown == total ? items(shown) : "\(shown) of \(items(total))"
        return "\(count) · \(selected) selected"
    }
    /// A one-line confirmation in the footer ("Link copied"), until the next selection or filter change or `confirmationDuration` passes.
    static let confirmationDuration: TimeInterval = 5
    private var transientStatus: String?
    private var confirmationTimer: Timer?
    func confirm(_ message: String) {
        transientStatus = message
        confirmationTimer?.invalidate()
        let timer = Timer(timeInterval:Self.confirmationDuration,repeats:false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearConfirmation() }
        }
        confirmationTimer = timer; RunLoop.main.add(timer,forMode:.common)
        status.stringValue = message
    }
    func clearConfirmation() {
        confirmationTimer?.invalidate(); confirmationTimer = nil
        guard transientStatus != nil else { return }
        transientStatus = nil; updateControls()
    }
    var statusLine: String { status.stringValue }
    /// The pasteboard's change counter, so a Copy is confirmed only when the app really wrote something. A test replaces it.
    var pasteboardChangeCount: () -> Int = { NSPasteboard.general.changeCount }
    @objc private func filtersChanged() {
        setFilters(category:Category(rawValue:categoryControl.selectedSegment) ?? .all,
                   date:DateFilter(rawValue:datePopup.indexOfSelectedItem) ?? .all,query:search.stringValue)
    }
    @objc private func formatChanged() { setDragFormat(Self.dragFormats[max(0,formatPopup.indexOfSelectedItem)]) }
    @objc private func actionInvoked(_ sender: AnyObject) {
        let tag = (sender as? NSControl)?.tag ?? (sender as? NSMenuItem)?.tag ?? -1
        if let action = Action(rawValue:tag) { perform(action) }
    }
    func controlTextDidChange(_ obj: Notification) { filtersChanged() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Popup choices have default tag zero and no action selector. They
        // must remain selectable even when the grid has no selected drawing.
        guard menuItem.action == #selector(actionInvoked(_:)) else { return true }
        return Action(rawValue:menuItem.tag).map(canPerform) ?? false
    }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: NSCollectionView,numberOfItemsInSection section: Int) -> Int { sections[section].items.count }
    func collectionView(_ collectionView: NSCollectionView,itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier:HistoryThumbnail.identifier,for:indexPath) as! HistoryThumbnail
        if let value = item(indexPath) { cell.configure(value,image:thumbnail(value)) }
        return cell
    }
    func collectionView(_ collectionView: NSCollectionView,viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind:kind,withIdentifier:HistoryDayHeader.identifier,for:indexPath) as! HistoryDayHeader
        header.label.stringValue = sections[indexPath.section].title; return header
    }
    func collectionView(_ collectionView: NSCollectionView,didSelectItemsAt indexPaths: Set<IndexPath>) { if !selectionChanging { clearConfirmation(); updateControls() } }
    func collectionView(_ collectionView: NSCollectionView,didDeselectItemsAt indexPaths: Set<IndexPath>) { if !selectionChanging { clearConfirmation(); updateControls() } }

    /// Export now, never when Finder later asks the promise to write. The delegate
    /// owns immutable bytes/name/format even if the history catalog is then removed.
    func dragPromise(for id: UUID) -> NSFilePromiseProvider? {
        guard let value = visibleItems.first(where: { $0.id == id }), !value.missing, let export = onExport else { return nil }
        let format = dragFormat
        do {
            let bytes = try export(value.id,format)
            let snapshot = HistoryPromiseSnapshot(name:value.name,format:format,bytes:bytes) { [weak self] error in self?.onError?(error) }
            return HistoryFilePromise(snapshot:snapshot)
        } catch { onError?(error); return nil }
    }
    func collectionView(_ collectionView: NSCollectionView,pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        item(indexPath).flatMap { dragPromise(for:$0.id) }
    }
}

@MainActor
private final class HistoryGrid: NSCollectionView {
    weak var browser: HistoryBrowser?
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with:event)
        if event.clickCount == 2, indexPathForItem(at:convert(event.locationInWindow,from:nil)) != nil { browser?.perform(.open) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let path = indexPathForItem(at:convert(event.locationInWindow,from:nil)) else { return nil }
        if !selectionIndexPaths.contains(path) {
            selectionIndexPaths = [path]
            browser?.collectionView(self,didSelectItemsAt:[path])
        }
        return super.menu(for:event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { browser?.perform(.open); return }
        if event.keyCode == 53 { browser?.cancelOperation(nil); return }
        if event.keyCode == 51 || event.keyCode == 117 { browser?.perform(.remove); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            browser?.perform(event.modifierFlags.contains(.shift) ? .copyLink : .copy); return
        }
        super.keyDown(with:event) // Native arrow/Shift/Command selection behavior.
    }
}

@MainActor
private final class HistoryThumbnail: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryThumbnail")
    private let name = NSTextField(labelWithString:"")
    private let action = NSTextField(labelWithString:"")
    private let placeholder = NSTextField(wrappingLabelWithString:"Preview unavailable")
    private let preview = NSImageView()
    override func loadView() {
        let tile = HistoryTileView(); view = tile
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = HistoryBrowser.tileTextSpacing; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        let inset = HistoryBrowser.tileInset
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:inset),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-inset),
                                     stack.topAnchor.constraint(equalTo:view.topAnchor,constant:inset),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-inset)])
        let host = NSView(); host.translatesAutoresizingMaskIntoConstraints = false
        host.heightAnchor.constraint(equalTo:host.widthAnchor,multiplier:HistoryBrowser.previewAspect).isActive = true
        for child in [preview,placeholder] {
            child.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(child)
            NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo:host.leadingAnchor),child.trailingAnchor.constraint(equalTo:host.trailingAnchor),
                                         child.topAnchor.constraint(equalTo:host.topAnchor),child.bottomAnchor.constraint(equalTo:host.bottomAnchor)])
        }
        preview.imageScaling = .scaleProportionallyUpOrDown
        placeholder.font = DesignTokens.Typography.font(.caption); placeholder.alignment = .center; placeholder.textColor = DesignTokens.Palette.Text.secondary
        name.font = DesignTokens.Typography.font(.body); name.maximumNumberOfLines = 1; name.lineBreakMode = .byTruncatingTail
        action.font = DesignTokens.Typography.font(.caption); action.lineBreakMode = .byTruncatingTail; action.textColor = DesignTokens.Palette.Text.secondary
        stack.addArrangedSubview(host); stack.addArrangedSubview(name); stack.addArrangedSubview(action)
        for line in [host,name,action] { line.widthAnchor.constraint(lessThanOrEqualTo:stack.widthAnchor).isActive = true }
        host.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        tile.addCheckBadge(over:host)
    }
    func configure(_ value: HistoryBrowser.Item,image: NSImage?) {
        _ = view
        name.stringValue = value.name; action.stringValue = value.missing ? "Missing file · \(value.action)" : value.action
        preview.image = image; placeholder.isHidden = image != nil; preview.isHidden = image == nil
        preview.setAccessibilityLabel(value.name); view.setAccessibilityLabel(value.name+", "+action.stringValue)
        refreshSelection()
    }
    override var isSelected: Bool { didSet { refreshSelection() } }
    private func refreshSelection() {
        guard isViewLoaded, let tile = view as? HistoryTileView else { return }
        tile.isTileSelected = isSelected
    }
}

/// A flow layout whose tiles stretch to share the row exactly, so gaps stay equal at every window width.
@MainActor
private final class HistoryFlowLayout: NSCollectionViewFlowLayout {
    private func fit(toGridWidth width: CGFloat) {
        let size = HistoryBrowser.tileSize(forGridWidth:width)
        if itemSize != size { itemSize = size }
    }
    override func prepare() {
        if let width = collectionView?.bounds.width { fit(toGridWidth:width) }
        super.prepare()
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        fit(toGridWidth:newBounds.width)
        return super.shouldInvalidateLayout(forBoundsChange:newBounds)
    }
}

/// A tile that says it is selected two ways: an accent border and fill, and a check badge, so colour is never the only cue.
@MainActor
final class HistoryTileView: NSView {
    private(set) var checkBadge: NSImageView?
    var isTileSelected = false { didSet { checkBadge?.isHidden = !isTileSelected; setAccessibilityValue(isTileSelected ? "Selected" : nil); needsDisplay = true } }
    /// A hover fill (`state.hover`) on a tile that is not selected; a selected tile keeps its stronger fill and check badge.
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewDidHide() { super.viewDidHide(); setHovered(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false) }
        super.viewWillMove(toWindow: newWindow)
    }
    override init(frame: NSRect) {
        super.init(frame:frame); wantsLayer = true; layer?.cornerRadius = DesignTokens.Radius.md
    }
    required init?(coder: NSCoder) { return nil }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderWidth = isTileSelected ? 2 : 0
            layer?.borderColor = DesignTokens.Palette.accent.cgColor
            layer?.backgroundColor = (isTileSelected ? DesignTokens.Palette.State.selectedFill : (isHovered ? DesignTokens.Palette.State.hover : NSColor.clear)).cgColor
        }
    }
    func addCheckBadge(over host: NSView) {
        let badge = NSImageView(); badge.translatesAutoresizingMaskIntoConstraints = false
        let size = DesignTokens.Typography.iconPrimary
        badge.image = ChromeIcons.resolve(.circleCheck,family:.solid,pointSize:size).image
        badge.contentTintColor = DesignTokens.Palette.accent; badge.isHidden = true
        badge.setAccessibilityElement(false)
        addSubview(badge); checkBadge = badge
        NSLayoutConstraint.activate([badge.topAnchor.constraint(equalTo:host.topAnchor,constant:DesignTokens.Space.s1),
                                     badge.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-DesignTokens.Space.s1)])
    }
}
@MainActor
private final class HistoryDayHeader: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryDayHeader")
    let label = NSTextField(labelWithString:"")
    override init(frame: NSRect) {
        super.init(frame:frame); label.font = DesignTokens.Typography.font(.headline)
        label.translatesAutoresizingMaskIntoConstraints = false; addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:leadingAnchor,constant:DesignTokens.Space.s3),label.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-DesignTokens.Space.s3),label.centerYAnchor.constraint(equalTo:centerYAnchor)])
    }
    required init?(coder: NSCoder) { return nil }
}

/// Immutable file-promise state; no document/core/browser access on worker threads.
final class HistoryPromiseSnapshot: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    let filename: String
    let typeIdentifier: String
    let bytes: Data
    private let failure: @MainActor @Sendable (Error) -> Void
    private let queue: OperationQueue
    init(name: String,format: String,bytes: Data,failure: @escaping @MainActor @Sendable (Error) -> Void) {
        self.bytes = bytes; self.failure = failure
        let ext = format == "jpeg" ? "jpg" : format
        let invalid = CharacterSet(charactersIn:"/\\:\0").union(.controlCharacters)
        let clean = name.components(separatedBy:invalid).joined(separator:"_").trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:".")))
        let base = clean.isEmpty ? "OpenSnap" : String(clean.prefix(160))
        let knownExtension = HistoryBrowser.dragFormats.contains((base as NSString).pathExtension.lowercased()) || (base as NSString).pathExtension.lowercased() == "jpg"
        filename = (knownExtension ? (base as NSString).deletingPathExtension : base)+"."+ext
        typeIdentifier = UTType(filenameExtension:ext)?.identifier ?? UTType.data.identifier
        queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.name = "OpenSnap.HistoryPromise"
        super.init()
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,fileNameForType fileType: String) -> String { filename }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,writePromiseTo url: URL,completionHandler: @escaping (Error?) -> Void) {
        do { try bytes.write(to:url,options:.atomic); completionHandler(nil) }
        catch {
            completionHandler(error)
            let failure = failure
            Task { @MainActor in failure(error) }
        }
    }
}
final class HistoryFilePromise: NSFilePromiseProvider {
    private(set) var snapshot: HistoryPromiseSnapshot!
    // AppKit's fileType initializer dynamically calls init(); retain the delegate
    // after that initializer completes rather than relying on a Swift-only init.
    override init() { super.init() }
    convenience init(snapshot: HistoryPromiseSnapshot) {
        self.init(fileType:snapshot.typeIdentifier,delegate:snapshot); self.snapshot = snapshot
    }
    required init?(coder: NSCoder) { return nil }
}
