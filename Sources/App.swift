import AppKit
import UniformTypeIdentifiers

/// Frame preview clears only the canvas hole; application controls keep an
/// opaque backdrop so their adaptive label colors remain readable.
final class FrameChromeView: NSView {
    weak var canvasScrollView: NSScrollView?
    var showsCanvasHole = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let chrome = NSBezierPath(rect: bounds)
        if showsCanvasHole, let scroll = canvasScrollView {
            let hole = scroll.convert(scroll.bounds, to: self).intersection(bounds)
            NSGraphicsContext.current?.cgContext.clear(hole)
            chrome.appendRect(hole)
            chrome.windingRule = .evenOdd
        }
        DesignTokens.Palette.Surface.window.setFill(); chrome.fill()
    }
    override func layout() { super.layout(); if showsCanvasHole { needsDisplay = true } }
}

/// The drag well. Dragging it hands the drawing to another app; it is also a keyboard-reachable button: Space or Return (and VoiceOver's
/// press) run `onActivate`, which opens the Export panel, the alternative to dragging. Hover shows an open hand and a held press a closed one.
final class DragExportView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    struct Payload { let data: Data; let name: String; var format: String = "png"; let delivered: (URL) -> Void }
    static let accessibilityName = "Drag image to another app"
    var prepare: (() -> Payload?)?
    /// The keyboard and assistive alternative to dragging.
    var onActivate: (() -> Void)?
    /// Hover and press changes, so the cell the well sits in can draw its plate fill for the same state.
    var onInteractionChange: (() -> Void)?
    private(set) var isHovered = false, isPressed = false
    private var hoverArea: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { KeyboardNavigation.reaches(self) }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.accessibilityName)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        onInteractionChange?()
    }
    func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else { return }
        isPressed = pressed
        window?.invalidateCursorRects(for: self)
        onInteractionChange?()
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
    override func viewDidHide() { super.viewDidHide(); setHovered(false); setPressed(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false); setPressed(false) }
        super.viewWillMove(toWindow: newWindow)
    }
    /// What the pointer shows over the well: an open hand, closed while it is held.
    var wellCursor: NSCursor { isPressed ? .closedHand : .openHand }
    override func resetCursorRects() { addCursorRect(bounds, cursor: wellCursor) }
    override func mouseDown(with event: NSEvent) { setPressed(true) }
    override func mouseUp(with event: NSEvent) { setPressed(false) }

    /// Runs the keyboard alternative to dragging; false when nothing is wired.
    @discardableResult func activate() -> Bool {
        guard let onActivate else { return false }
        onActivate()
        return true
    }
    override func accessibilityPerformPress() -> Bool { activate() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36, 76: if !activate() { super.keyDown(with: event) }
        default: super.keyDown(with: event)
        }
    }
    private var focusBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override var focusRingMaskBounds: NSRect { focusBounds.isEmpty ? .zero : focusBounds }
    override func drawFocusRingMask() {
        guard !focusBounds.isEmpty else { return }
        NSColor.black.setFill()
        NSBezierPath(roundedRect: focusBounds, xRadius: StatePlate.radius, yRadius: StatePlate.radius).fill()
    }
    var overview: NSImage? { didSet { needsDisplay = true } }
    var onBegin: ((UUID) -> Void)?
    var onLeaveControl: ((UUID) -> Void)?
    var onEnd: ((UUID, Bool) -> Void)?
    var onDeliveryFailure: ((UUID) -> Void)?
    private struct Export {
        let id: UUID
        let provider: NSFilePromiseProvider
        let payload: Payload
        let controlRect: NSRect
    }
    private var payloads: [ObjectIdentifier: Export] = [:]
    private var sessions: [ObjectIdentifier: ObjectIdentifier] = [:]
    private var activeProvider: ObjectIdentifier?
    /// Modern lets the glass surface behind the view be the plate.
    var drawsBackground = true { didSet { needsDisplay = true } }
    /// Modern shows only an open-hand icon: no thumbnail and no text. The thumbnail still feeds the drag image.
    var showsHandIconOnly = false { didSet { needsDisplay = true } }
    static let handSymbolName = "hand.raised"
    override func draw(_ dirtyRect: NSRect) {
        if drawsBackground { NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill() }
        if showsHandIconOnly {
            guard let hand = ChromeIcons.resolve(.dragHand, family: .solid, pointSize: 22).image else { return }
            let tinted = NSImage(size: hand.size, flipped: false) { rect in
                hand.draw(in: rect); NSColor.labelColor.setFill(); rect.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: NSRect(x: bounds.midX - hand.size.width / 2, y: bounds.midY - hand.size.height / 2, width: hand.size.width, height: hand.size.height))
            return
        }
        if let overview { overview.draw(in: bounds.insetBy(dx: 4, dy: 4), from: .zero, operation: .sourceOver, fraction: 0.2) }
        let title = "Drag Me"
        let attrs = DesignTokens.Typography.attributes(.bodyStrong)
        let size = title.size(withAttributes: attrs)
        title.draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attrs)
    }
    override func mouseDragged(with event: NSEvent) {
        guard activeProvider == nil, let window, let payload = prepare?() else { return }
        let provider = NSFilePromiseProvider(fileType: (UTType(filenameExtension: payload.format) ?? .data).identifier, delegate: self)
        guard beginExport(provider: provider, payload: payload, controlRect: window.convertToScreen(convert(bounds, to: nil))) else { return }
        let item = NSDraggingItem(pasteboardWriter: provider)
        let preview = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { [overview] rect in
            overview?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.5)
            return true
        }
        item.setDraggingFrame(NSRect(x: bounds.midX - 64, y: bounds.midY - 64, width: 128, height: 128), contents: preview)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        sessions[ObjectIdentifier(session)] = ObjectIdentifier(provider)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard sessions[ObjectIdentifier(session)] == activeProvider else { return }
        moveExport(to: screenPoint)
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        setPressed(false)
        if let provider = sessions.removeValue(forKey: ObjectIdentifier(session)) { endExport(provider: provider, succeeded: !operation.isEmpty) }
    }
    @discardableResult
    func beginExport(provider: NSFilePromiseProvider, payload: Payload, controlRect: NSRect) -> Bool {
        guard activeProvider == nil else { return false }
        let key = ObjectIdentifier(provider), export = Export(id: UUID(), provider: provider, payload: payload, controlRect: controlRect)
        payloads[key] = export; activeProvider = key
        activeExport = export
        onBegin?(export.id)
        return true
    }
    private var activeExport: Export?
    func moveExport(to screenPoint: NSPoint) {
        guard let export = activeExport, !export.controlRect.contains(screenPoint) else { return }
        onLeaveControl?(export.id)
    }
    func endExport(provider: ObjectIdentifier, succeeded: Bool) {
        guard activeProvider == provider, let export = activeExport else { return }
        activeProvider = nil; activeExport = nil
        if !succeeded { payloads.removeValue(forKey: provider) }
        onEnd?(export.id, succeeded)
    }
    /// The file extension for a payload format: JPEG files are named .jpg, matching uploads.
    static func fileExtension(forFormat format: String) -> String { format == "jpeg" ? "jpg" : format }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        let payload = payloads[ObjectIdentifier(filePromiseProvider)]?.payload
        return (payload?.name ?? MainWindowFrame.untitled) + "." + Self.fileExtension(forFormat: payload?.format ?? "png")
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        let export = payloads.removeValue(forKey: ObjectIdentifier(filePromiseProvider))
        do {
            guard let export else { throw NSError(domain: "OpenSnap", code: 1, userInfo: [NSLocalizedDescriptionKey: "The dragged image is no longer available."]) }
            try export.payload.data.write(to: url, options: .atomic)
            export.payload.delivered(url); completionHandler(nil)
        } catch {
            if let export { onDeliveryFailure?(export.id) }
            completionHandler(error)
        }
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }
}

final class DragThumbnailView: NSView {
    var image: NSImage?
    var clickToExpand = false { didSet { needsDisplay = true } }
    var restore: (() -> Void)?
    private var hovering = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { restore?() }
    override func accessibilityPerformPress() -> Bool {
        guard let restore else { return false }
        restore(); return true
    }
    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        if clickToExpand {
            NSColor.white.withAlphaComponent(0.1).setFill(); bounds.fill()
            drawBadge(symbol: "arrow.up.left.and.arrow.down.right", emphasized: hovering)
        } else if hovering {
            drawBadge(symbol: "xmark", emphasized: true)
        }
    }
    private func drawBadge(symbol: String, emphasized: Bool) {
        let diameter = min(56, min(bounds.width, bounds.height) * 0.6)
        let disc = NSRect(x: (bounds.width-diameter)/2, y: (bounds.height-diameter)/2, width: diameter, height: diameter)
        NSColor.black.withAlphaComponent(emphasized ? 0.78 : 0.55).setFill()
        NSBezierPath(ovalIn: disc).fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: diameter*0.42, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = glyph.size
        glyph.draw(in: NSRect(x: disc.midX-size.width/2, y: disc.midY-size.height/2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1)
    }
}

/// The document name. It stays off screen and is mirrored into the window title.
@MainActor
final class DocumentNameField: NSTextField {
    var onChange: ((String) -> Void)?
    override var stringValue: String { didSet { onChange?(stringValue) } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSFontChanging, @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate, @preconcurrency NSMenuDelegate {
    var window: NSWindow!
    let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    let capture = CaptureCoordinator()
    /// One store for Webpost and remote deletion, derived from the same OPENSNAP_APP_SUPPORT the rest of the app honours.
    /// It exists before buildWindow, which loads it while building the Webpost menu.
    static let publishingStore = PublishingDestinationStore.forEnvironment(ProcessInfo.processInfo.environment)
    let publishing: PublishingCoordinator = { let coordinator = PublishingCoordinator(); coordinator.store = AppDelegate.publishingStore; return coordinator }()
    var webpostButton: NSButton?
    /// Where the upload stands (OSN-054). It drives the status slot in the bottom bar: refreshStatusText() shows its text while it is not idle,
    /// the chrome shows the matching spinner and commands, and each change is announced to VoiceOver.
    var uploadState: UploadState = .idle { didSet { if uploadState != oldValue { statusNotice = nil; uploadStateChanged(from: oldValue) } } }
    /// What Retry sends again after a failure: the same bytes, file name and document the failed attempt had.
    var retryablePayload: UploadPayload?
    var uploadSuccessTimer: Timer?
    /// How long "Link copied" stays in the status slot before the normal status returns (long enough to read the link and reach for Open or Copy).
    var uploadSuccessDuration: TimeInterval = UploadState.successDuration
    /// The failure belongs to the document it was raised for; a different document drops it.
    var uploadFailureGeneration: UUID?
    /// Test seam: opens the uploaded link in the browser.
    var linkOpener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Test seams: replace the real NSSharingServicePicker and the Sharing Settings sheet.
    var sharePickerPresenter: ((NSImage, NSView?) -> Void)?
    var sharingSettingsPresenter: (() -> Void)?
    /// `var` so a test can give it a fake adapter; production never reassigns it.
    var historyRemoteDeletion = HistoryRemoteDeletionCoordinator(destinationBinding: nil, store: AppDelegate.publishingStore)
    /// Test seam: the window the keyboard is in.
    var keyWindowProvider: () -> NSWindow? = { NSApp.keyWindow }
    /// Test seams: the deletion binding captured for a file name before an upload, and for the published URL after it.
    lazy var plannedBindingCapture: (String) -> [String: String]? = { [unowned self] in try? self.historyRemoteDeletion.captureBinding(fileName: $0) }
    lazy var publishedBindingCapture: (URL) -> [String: String]? = { [unowned self] in try? self.historyRemoteDeletion.captureBinding(for: $0) }
    let hotkeys = GlobalHotkeyManager()
    var generalPreferences: OriginalGeneralPreferences { OriginalGeneralPreferences(defaults: .standard) }
    var settingsController: SettingsWindowController?
    var preferencesWindow: NSWindow? { settingsController?.window }
    var helpBevel: OriginalHelpBevel?
    /// Controls the hover-hint bevel describes (weak): their tooltip yields to the bevel while it is enabled.
    let hintTrackedViews = NSHashTable<NSView>.weakObjects()
    private var hintEventMonitor: Any?
    let photoBrowser = PhotoBrowserCoordinator()
    let nameField = DocumentNameField(string: "Untitled")
    let status = StatusTextField(labelWithString: "")
    let colorWell = NSColorWell()
    let widthControl = BezelSizeSlider(frame: .zero)
    let sizeLabel = NSTextField(labelWithString: "Size · 6.75")
    let paletteButton = BezelHoverButton(title: "Color…", target: nil, action: nil)
    var colorPopover: NSPopover?
    var colorControlHovered = false, colorPaletteHovered = false, colorOpenedByHover = false
    private var colorHoverDismissal: DispatchWorkItem?
    var presetColorButtons: [BezelColorButton] = []
    weak var customColorButton: BezelCustomColorButton?
    var sizeUndoGrouping = false
    /// The system Colors panel; a test hands in a panel that is never ordered on screen.
    var colorPanelProvider: () -> NSColorPanel = { NSColorPanel.shared }
    /// True from Custom color… until the Colors panel is closed. The panel is shared and AppKit pushes colours into it (a text box does, whenever it
    /// takes focus or changes selection), so a colour that arrives while it is not ours is an echo, never a choice.
    var customColorPanelOpen = false
    private var colorPanelCloseObserver: NSObjectProtocol?
    var customDrawingColor = NSColor(calibratedRed: 0, green: 1, blue: 1, alpha: 1) // token-exempt: drawing colour data, not chrome
    let zoomControl = ZoomPopUpButton(frame: .zero, pullsDown: false)
    let dragFormatToggle = SegmentedToggle(titles: FormatToggle.titles)
    let dragOriginalControl = NSButton(checkboxWithTitle: "Export at original size", target: nil, action: nil)
    let dragSizeLabel = NSTextField(labelWithString: "")
    var dragExportView: DragExportView?
    var dragPreviewTimer: Timer?
    var activeDragID: UUID?
    var dragThumbnailID: UUID?
    var dragThumbnailWindow: NSPanel?
    var windowZoom: WindowZoomAnimation?
    var windowZoomID: UUID?
    var visibilityZoomOrigin: CGRect?
    /// The status-item zoom is for a window that sits on the desktop; a full-screen window has its own Space and its own transition.
    var animatesWindowZoom: Bool { !DisplayOptions.current.reduceMotion && !isFullScreen }
    var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }
    var resizeButton: NSButton?
    let navigator = CanvasNavigator(frame: NSRect(x: 0, y: 0, width: 180, height: 170))
    var navigatorWindow: NSPanel?
    let canvasBorder = CanvasBorderView(frame: .zero)
    struct ActualViewState {
        let generation: UUID
        let outputSize: CGSize
        let zoom: CGFloat
        let windowFrame: CGRect
        let scrollOrigin: CGPoint
        var savedWhileActive = false
    }
    var actualView: ActualViewState?
    var isActualSize: Bool { actualView != nil }
    struct WindowGesture {
        let generation: UUID
        let outputSize: CGSize
        let sourceSize: CGSize
        let zoom: CGFloat
        let windowFrame: CGRect
        let handle: CanvasBorderHandle
    }
    var windowGesture: WindowGesture?
    var adjustingWindowFrame = false
    var navigatorTimer: Timer?
    var fontPanel: NSFontPanel?
    var textStyleForm: TextStyleForm?
    var fontPanelRefreshTimer: Timer?
    var fontPanelRecordedTypography = false
    var fontPanelOpeningLayoutApplied = false
    var fontPanelVisibleFrameOverride: (() -> NSRect?)?
    var applyingFontChange = false
    var activeResizeSession: ResizePanelSession?
    var toolButtons: [SketchTool: NSButton] = [:]
    var modernChrome: NSView?
    /// The file the document saves to. The title bar's proxy icon follows it.
    var currentURL: URL? { didSet { window?.representedURL = currentURL } }
    var documentGeneration = UUID()
    var drawingDefaults = DrawingDefaults()
    var dirty = false
    var restoring = false
    var discardedForTermination = false
    /// A "Save your drawing?" question from New, Open or a capture is on screen.
    var discardQuestionOpen = false
    /// History questions on screen, by kind. A second click on a command whose question is already open changes nothing, so a
    /// double-click can never stack two sheets on one window (F-J2-006).
    var openHistoryQuestions: Set<String> = []
    /// A message in the status slot that outranks the normal status until it expires or the state it described changes (F-J1-010).
    var statusNotice: String?
    var statusNoticeTimer: Timer?
    /// How long a notice stays: long enough to read, short enough that it never describes a state that has moved on.
    var statusNoticeDuration: TimeInterval = 8
    /// The zoom full screen replaced, put back when it ends (only while the document and the zoom are still the ones full screen set).
    var fullScreenZoom: (generation: UUID, before: CGFloat, applied: CGFloat)?
    var terminationStarted = false
    var decidingTermination = false
    var shutdownPending: Set<String> = []
    var shutdownError: Error?
    var timer: Timer?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    var aboutWindow: AboutWindow?
    var historyBrowser: HistoryBrowser?
    var historyWindow: NSWindow? { historyBrowser?.window }
    var historyStore: HistoryStore?
    struct ShareSnapshot { let snapshot: HistoryStore.Snapshot; let name: String; let generation: UUID }
    var sharePicker: NSSharingServicePicker?
    var pickerSnapshot: ShareSnapshot?
    var sharingSnapshots: [ObjectIdentifier: ShareSnapshot] = [:]
    var currentArchiveID: UUID?
    var historyFollowTimer: Timer?
    var snapButton: NSButton!
    var cancelFrameButton: NSButton!
    /// Located by its action on first use, so the window builder needs no extra reference.
    weak var wipeButton: NSButton?
    var frameMode = false
    var frameKeepsAnnotations = false
    var frameCaptureInProgress = false
    var frameTimedSnap = false
    var activeFrameScreenSize: NSSize?
    var frameWindowWasOpaque = true
    var frameWindowHadShadow = true
    var frameWindowAlpha: CGFloat = 1
    var frameWindowLevel = NSWindow.Level.normal
    var frameWindowBackground: NSColor?
    var frameScrollDrewBackground = true
    /// Overlay scrollers fade in over the Frame hole and a screen capture would take them with the picture, so Frame mode hides them.
    var frameScrollersShown = (horizontal: true, vertical: true)
    var frameTitlebarBackdrop: FrameChromeView?
    /// Where the main window remembers its frame. A test names its own, so no run touches the real "OpenSnap.Main" entry.
    var frameAutosaveName: String? = MainWindowFrame.autosaveName
    /// Where the "is a frame saved?" question is asked. AppKit itself writes the frame to the standard defaults.
    var frameDefaults: UserDefaults = .standard
    let support: URL = {
        if let isolated = ProcessInfo.processInfo.environment["OPENSNAP_APP_SUPPORT"] { return URL(fileURLWithPath: isolated, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenSnap", isDirectory: true)
    }()


    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus(); buildWindow()
        for (name, handler) in [(NSWindow.willEnterFullScreenNotification, windowWillEnterFullScreen), (NSWindow.didEnterFullScreenNotification, windowDidEnterFullScreen), (NSWindow.didExitFullScreenNotification, windowDidExitFullScreen)] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { note in MainActor.assumeIsolated { handler(note) } }
        }
        installMenuPresence()
        applyPresencePolicy()
        installHintMonitoring()
        NSColorPanel.shared.showsAlpha = true
        canvas.onChange = { [weak self] in self?.changed() }
        canvas.tabNavigatesFocus = { KeyboardNavigation.fullKeyboardAccess() }
        canvas.onPendingCropChange = { [weak self] in self?.updateStatus() }
        // Undo is dimmed while there is nothing to undo: the canvas history and a text box's typing history both count.
        for name in [NSNotification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange, .NSUndoManagerDidCloseUndoGroup] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateUndoButton() }
            }
        }
        canvas.onTextStyleRequested = { [weak self] in self?.chooseFont() }
        canvas.onTextStyleContextChange = { [weak self] in self?.syncFontPanelSelection(); self?.updateWipeButton() }
        canvas.onViewportEditCancelled = { [weak self] in
            self?.endWindowGesture(cancelled: true)
            self?.activeResizeSession?.cancel()
        }
        canvas.onHistoryRestored = { [weak self] previous in self?.finishHistoryResize(previousOutput: previous) }
        canvas.onOpenDocument = { [weak self] url in self?.openURL(url) }
        canvas.onToolChange = { [weak self] tool in
            guard let self else { return }
            self.updateToolButtons(tool)
            self.clearStatusNotice(); self.updateStatus()
        }
        canvas.onColorChange = { [weak self] color in self?.colorWell.color = color; self?.rememberDrawingDefaults(); self?.syncDrawingControls() }
        try? FileManager.default.createDirectory(at: support.appendingPathComponent("History"), withIntermediateDirectories: true)
        let recoveryData = try? Data(contentsOf: support.appendingPathComponent(Self.recoveryName))
        if let data = recoveryData {
            do { let restored = try OpenSnapFile.decode(data); restoring = true; try canvas.loadDocument(data: restored.canvasData); drawingDefaults = restored.drawingDefaults; restoreDrawingDefaults(); restoring = false; dirty = true; window.isDocumentEdited = true; nameField.stringValue = "Recovered drawing" }
            catch { restoring = false; status.stringValue = "Previous session could not be restored." }
        }
        let fixturePath = ProcessInfo.processInfo.environment["OPENSNAP_FIXTURE"]
        if let fixture = fixturePath { openURL(URL(fileURLWithPath: fixture)) }
        updateStatus(); updateWipeButton()
        if let notice = OpenSnapMigration.launchNotice { status.stringValue = notice }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor in self?.saveRecovery() } }
        restoreWindowFrame(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas); NSApp.activate(ignoringOtherApps: true)
        window.contentView?.layoutSubtreeIfNeeded(); updateViewportChrome()
        do {
            try hotkeys.install(globalScreen: { [weak self] in self?.captureCrosshair(manualOption: false) }, globalWindow: { [weak self] in self?.windowSnap() }, globalFullscreen: { [weak self] in self?.captureFullscreen(manualOption: false) }, globalFrame: { [weak self] in self?.enterFrame(keepingAnnotations: false, manualFlags: []) }, globalUpload: { [weak self] in self?.snapAndUpload() }, globalShow: { [weak self] in self?.makeVisible() })
        } catch { status.stringValue = "Global shortcuts unavailable: " + error.localizedDescription }
        writeLayoutEvidence()
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { self.runSmokeTest() }
        }
        if let auditDirectory = AppDelegate.eyeDumpAuditDirectory() {
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { self.runEyeDumpAudit(to: auditDirectory) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationStarted { return shutdownPending.isEmpty ? .terminateNow : .terminateLater }
        widthControl.dismissPopover(); widthControl.endTracking(); closeDrawingColors()
        if windowZoom != nil { makeVisible() }
        saveRecovery()
        // The unsaved-changes question is a sheet, so the answer may come after this method returns: then AppKit is told
        // `.terminateLater` and the answer goes back through reply(toApplicationShouldTerminate:), as the cleanup's does.
        var answered: NSApplication.TerminateReply?, returned = false
        confirmDiscard(discardingForTermination: true) { [weak self] allowed in
            guard let self else { return }
            let reply: NSApplication.TerminateReply = allowed ? self.beginShutdown() : .terminateCancel
            if !returned { answered = reply; return }
            switch reply {
            case .terminateNow: NSApp.reply(toApplicationShouldTerminate: true)
            case .terminateCancel: NSApp.reply(toApplicationShouldTerminate: false)
            default: break // acknowledgeShutdown answers when the cleanup finishes
            }
        }
        returned = true
        return answered ?? .terminateLater
    }
    /// What follows an approved Quit: stop the backends and wait for them.
    private func beginShutdown() -> NSApplication.TerminateReply {
        terminationStarted = true; decidingTermination = true
        shutdownPending = ["capture", "publishing", "photos", "history-deletion"]; shutdownError = nil
        historyRemoteDeletion.shutdown { [weak self] result in self?.acknowledgeShutdown("history-deletion", result: result) }
        photoBrowser.shutdown { [weak self] in self?.acknowledgeShutdown("photos", result: .success(())) }
        capture.shutdown { [weak self] (result: Result<Void, Error>) in self?.acknowledgeShutdown("capture", result: result) }
        publishing.shutdown { [weak self] (result: Result<Void, Error>) in self?.acknowledgeShutdown("publishing", result: result) }
        decidingTermination = false
        if shutdownPending.isEmpty { return finishShutdownDecision() ? .terminateNow : .terminateCancel }
        status.stringValue = "Finishing capture and publishing cleanup…"
        return .terminateLater
    }
    func acknowledgeShutdown(_ operation: String, result: Result<Void, Error>) {
        guard shutdownPending.remove(operation) != nil else { return }
        if case .failure(let error) = result, shutdownError == nil { shutdownError = error }
        guard shutdownPending.isEmpty, !decidingTermination else { return }
        let approved = finishShutdownDecision()
        NSApp.reply(toApplicationShouldTerminate: approved)
    }
    func finishShutdownDecision() -> Bool {
        guard let failure = shutdownError else { return true }
        terminationStarted = false
        if discardedForTermination { dirty = true; window.isDocumentEdited = true }
        discardedForTermination = false; saveRecovery(); updateStatus()
        // Reply to AppKit before presenting an error about incomplete cleanup.
        DispatchQueue.main.async { [weak self] in self?.error(failure) }
        return false
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        leaveFrame()
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        fitDrawingForFullScreen()
        DispatchQueue.main.async { [weak self] in self?.refitForFullScreenResize() }
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        restoreZoomAfterFullScreen(); clearStatusNotice()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === preferencesWindow { closePreferences(); return false }
        guard sender === window else { return true }
        vanish()
        return false
    }
    func installMenuPresence() {
        guard statusItem == nil else { return }
        guard UserDefaults.standard.integer(forKey: "statusMenu") != 2 else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button { StatusIcon.configure(button) }
        item.menu = makeStatusMenu()
    }
    /// What clicking the menu-bar icon opens: show or hide the editor, start a snap, open Settings, quit.
    func makeStatusMenu() -> NSMenu {
        let name = DesignTokens.Brand.name
        let menu = NSMenu(title: name)
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        add(statusShowHideTitle, #selector(statusShowHide))
        menu.addItem(.separator())
        add("Snap…", #selector(screenSnap))
        add("Settings…", #selector(showPreferences))
        menu.addItem(.separator())
        add("Quit " + name, #selector(quit))
        MenuSymbols.apply(to: menu)
        MenuTypography.apply(to: menu)
        statusMenu = menu
        return menu
    }
    /// Mirrors toggleVisible(): the editor is hidden by the item only while it is visible, in front and the app is active.
    var statusShowHideTitle: String {
        let editorInFront = window.isVisible && !window.isMiniaturized && NSApp.isActive
        return (editorInFront ? "Hide " : "Show ") + DesignTokens.Brand.name
    }
    @objc func statusShowHide() { toggleVisible() }
    func applyPresencePolicy() {
        let presence = generalPreferences.state.statusMenu
        // Modern AppKit changes Dock presence without rewriting the signed app
        // bundle or restarting with pending drawings, unlike the original app.
        NSApp.setActivationPolicy(presence == 1 ? .accessory : .regular)
        if presence == 2, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item); statusItem = nil
        } else if presence != 2 { installMenuPresence() }
    }
    func trackHint(_ view: NSView, owner: String, message: @escaping () -> String?) {
        let tracking = HintTrackingView(); tracking.translatesAutoresizingMaskIntoConstraints = false
        tracking.setAccessibilityElement(false)
        tracking.onHover = { [weak self] entered in
            guard let self, !self.terminationStarted else { return }
            if entered { self.helpBevel?.hover(owner: owner, message: message()) }
            else { self.helpBevel?.exit(owner: owner) }
        }
        hintTrackedViews.add(view)
        view.addSubview(tracking)
        NSLayoutConstraint.activate([tracking.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tracking.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tracking.topAnchor.constraint(equalTo: view.topAnchor), tracking.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }
    func hintModifiers(_ flags: NSEvent.ModifierFlags) {
        guard !terminationStarted, window.attachedSheet == nil,
              !(window.firstResponder is NSTextView) else { return }
        let message = canvas.isTemporaryHand ? "" : OriginalHintMessages.getHelpForModifiers(tool: canvas.toolForModifiers(flags), modifiers: flags)
        helpBevel?.modifiers(message: message)
    }
    func installHintMonitoring() {
        hintEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, NSApp.keyWindow === self.window { self.hintModifiers(event.modifierFlags) }
            }
            return event
        }
    }
    func applicationWillResignActive(_ notification: Notification) { helpBevel?.clear() }
    func applicationDidHide(_ notification: Notification) { helpBevel?.clear() }
    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { helpBevel?.clear(); KeyboardNavigation.toolbarFocusActive = false }
    }
    func windowWillMiniaturize(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { helpBevel?.clear() }
    }
    /// Minimize and the Hide button: a visible editor always goes away. (The toggle below raises an inactive editor instead, which is right
    /// for Hide OpenSnap and the status item, but a command that says Minimize must never do the opposite of its name.)
    @objc func vanish() {
        guard window.isVisible else { return }
        hideOrShowEditor(hidingWhenInactive: true)
    }
    @objc func toggleVisible() { hideOrShowEditor(hidingWhenInactive: false) }
    func hideOrShowEditor(hidingWhenInactive: Bool) {
        guard !terminationStarted, !frameCaptureInProgress, window.attachedSheet == nil else { return }
        widthControl.dismissPopover(); widthControl.endTracking(); closeDrawingColors(); helpBevel?.clear()
        if windowZoom != nil { makeVisible(); return }
        if dragThumbnailWindow != nil {
            let panel = dragThumbnailWindow!, source = panel.frame
            let image = snapshot(window: panel)
            removeDragThumbnail()
            if UserDefaults.standard.integer(forKey: "statusMenu") == 2 {
                visibilityZoomOrigin = nil; window.orderFront(nil); window.miniaturize(nil)
            } else {
                let target = zoomDestinationRect(); visibilityZoomOrigin = target.isEmpty ? nil : target
                if let image { _ = startWindowZoom(image: image, source: source, destination: target, direction: .shrink, frames: 25,
                                                  completion: { [weak self] in self?.writeLayoutEvidence() }) }
            }
            writeLayoutEvidence(); return
        }
        if !window.isVisible || window.isMiniaturized || (!NSApp.isActive && !hidingWhenInactive) {
            makeVisible()
        } else {
            saveRecovery()
            timer?.fireDate = .distantFuture
            fontPanel?.orderOut(nil); navigatorWindow?.orderOut(nil)
            if UserDefaults.standard.integer(forKey: "statusMenu") == 2 { visibilityZoomOrigin = nil; window.miniaturize(nil) }
            else {
                let target = zoomDestinationRect(); visibilityZoomOrigin = target.isEmpty ? nil : target
                if animatesWindowZoom, let image = snapshot(window: window) {
                    _ = startWindowZoom(image: image, source: window.frame, destination: target, direction: .shrink, frames: 15,
                                        completion: { [weak self] in self?.writeLayoutEvidence() })
                }
                window.orderOut(nil)
            }
            writeLayoutEvidence()
        }
    }
    @objc func makeVisible() {
        guard !terminationStarted else { return }
        if animatesWindowZoom && windowZoom == nil && dragThumbnailWindow == nil && !window.isVisible && !window.isMiniaturized,
           UserDefaults.standard.integer(forKey: "statusMenu") != 2, let previous = visibilityZoomOrigin,
           let image = snapshot(window: window) {
            let current = zoomDestinationRect(), source = current.isEmpty ? previous : current
            visibilityZoomOrigin = nil
            NSApp.activate(ignoringOtherApps: true); timer?.fireDate = Date(timeIntervalSinceNow: 15)
            if startWindowZoom(image: image, source: source, destination: window.frame, direction: .restore, frames: 15,
                               completion: { [weak self] in self?.showEditorImmediately() }) { writeLayoutEvidence(); return }
        }
        showEditorImmediately()
    }
    func showEditorImmediately() {
        guard !terminationStarted else { return }
        visibilityZoomOrigin = nil
        removeDragThumbnail()
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        timer?.fireDate = Date(timeIntervalSinceNow: 15)
        updateViewportChrome(); writeLayoutEvidence()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !window.isVisible && window.attachedSheet == nil { makeVisible() }
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        if discardedForTermination { removeRecovery() }
        else { saveRecovery(finalizingTermination: true) }
        timer?.invalidate(); historyFollowTimer?.invalidate(); dragPreviewTimer?.invalidate(); navigatorTimer?.invalidate(); closeFontPanel(); try? hotkeys.unregister()
        preferencesWindow?.orderOut(nil); aboutWindow?.close()
        helpBevel?.shutdown()
        if let hintEventMonitor { NSEvent.removeMonitor(hintEventMonitor); self.hintEventMonitor = nil }
        removeDragThumbnail(); activeDragID = nil; visibilityZoomOrigin = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem); self.statusItem = nil }
    }
    static func dragThumbnailRect(windowFrame: NSRect, controlRect: NSRect) -> NSRect {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return .zero }
        let scale = 128 / max(windowFrame.width, windowFrame.height)
        let width = max(90, windowFrame.width * scale), height = max(90, windowFrame.height * scale)
        return NSRect(x: controlRect.midX-width/2, y: controlRect.midY-height/2, width: width, height: height).integral
    }
    func zoomDestinationRect() -> CGRect { statusItem?.button?.window?.frame ?? .zero }
    func snapshot(window: NSWindow) -> NSImage? {
        guard let content = window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let image = NSImage(size: content.bounds.size); image.addRepresentation(bitmap)
        return image
    }
    func iconifyDrag(_ id: UUID) {
        guard activeDragID == id, dragThumbnailWindow == nil, !terminationStarted,
              window.isVisible, window.attachedSheet == nil, let drag = dragExportView,
              let image = snapshot(window: window) else { return }
        let rect = Self.dragThumbnailRect(windowFrame: window.frame, controlRect: window.convertToScreen(drag.convert(drag.bounds, to: nil)))
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hasShadow = true; panel.level = .statusBar; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        let view = DragThumbnailView(frame: NSRect(origin: .zero, size: rect.size)); view.image = image
        view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Restore OpenSnap editor")
        view.restore = { [weak self] in self?.restoreDragThumbnail(id) }
        panel.contentView = view; dragThumbnailWindow = panel; dragThumbnailID = id
        saveRecovery(); timer?.fireDate = .distantFuture
        fontPanel?.orderOut(nil); navigatorWindow?.orderOut(nil)
        if !startWindowZoom(image: image, source: window.frame, destination: rect, direction: .shrink, completion: { [weak self, weak panel] in
            guard self?.dragThumbnailID == id else { return }
            panel?.orderFrontRegardless(); self?.writeLayoutEvidence()
        }) { panel.orderFrontRegardless() }
        window.orderOut(nil); writeLayoutEvidence()
    }
    func endDrag(_ id: UUID, succeeded: Bool) {
        guard activeDragID == id, !terminationStarted else { return }
        activeDragID = nil
        if !succeeded { restoreDragThumbnail(id) }
        else if dragThumbnailID == id {
            (dragThumbnailWindow?.contentView as? DragThumbnailView)?.clickToExpand = true
            writeLayoutEvidence()
        }
    }
    func restoreDragThumbnail(_ id: UUID) {
        guard dragThumbnailID == id, dragThumbnailWindow != nil, !terminationStarted else { return }
        let image = (dragThumbnailWindow?.contentView as? DragThumbnailView)?.image
        let source = dragThumbnailWindow!.frame
        removeDragThumbnail()
        NSApp.activate(ignoringOtherApps: true)
        guard let image, startWindowZoom(image: image, source: source, destination: window.frame, direction: .restore,
                                        completion: { [weak self] in self?.makeVisible() }) else { makeVisible(); return }
        writeLayoutEvidence()
    }
    func removeDragThumbnail() {
        cancelWindowZoom()
        (dragThumbnailWindow?.contentView as? DragThumbnailView)?.restore = nil
        dragThumbnailWindow?.orderOut(nil); dragThumbnailWindow?.close()
        dragThumbnailWindow = nil; dragThumbnailID = nil
    }
    func replaceDragPresentation() {
        closeDrawingColors()
        activeDragID = nil
        if dragThumbnailWindow != nil || windowZoom != nil || visibilityZoomOrigin != nil { showEditorImmediately() }
    }
    @discardableResult
    func startWindowZoom(image: NSImage, source: CGRect, destination: CGRect, direction: WindowZoomDirection, frames: Int? = nil, completion: @escaping () -> Void) -> Bool {
        guard animatesWindowZoom, !terminationStarted else { return false }
        cancelWindowZoom()
        let token = UUID()
        guard let animation = WindowZoomAnimation(image: image, source: source, destination: destination, direction: direction, frames: frames, completion: { [weak self] in
            guard let self, self.windowZoomID == token, !self.terminationStarted else { return }
            self.windowZoom = nil; self.windowZoomID = nil; completion()
        }) else { return false }
        windowZoom = animation; windowZoomID = token; animation.start(); return true
    }
    func cancelWindowZoom() {
        let previous = windowZoom
        windowZoom = nil; windowZoomID = nil; previous?.cancel()
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first { openURL(URL(fileURLWithPath: first)) }
        sender.reply(toOpenOrPrint: .success)
    }

    func label(_ text: String) -> NSTextField { let f = NSTextField(labelWithString: text); f.font = DesignTokens.Typography.font(.body); return f }
    func button(_ title: String, _ action: Selector) -> NSButton { let b = OriginalActionButton(title: title, target: self, action: action); b.font = DesignTokens.Typography.font(.body); return b }
    /// A live copy of the main-menu item for `action`, so a popup never carries wording of its own.
    func copiedMainMenuItem(_ action: Selector) -> NSMenuItem? {
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.action == action { return item }
                if let submenu = item.submenu, let found = find(submenu) { return found }
            }
            return nil
        }
        guard let main = NSApp.mainMenu else { return nil }
        return find(main)?.copy() as? NSMenuItem
    }
    func copiedMainMenu(_ title: String) -> NSMenu? {
        NSApp.mainMenu?.items.first(where: { $0.submenu?.title == title })?.submenu?.copy() as? NSMenu
    }
    /// The Toolbox is a subset of the main menu by action: every row is a copy of the menu-bar item, so titles, keys and symbols match.
    /// It holds what a drawing session reaches for (keep, edit, capture, adjust the picture, pen settings); the app, file and settings
    /// plumbing lives in the menu bar only (F-J1-009).
    static let toolboxGroups: [[Selector]] = [
        [#selector(saveHistory), #selector(exportFile)],
        [#selector(copyArtwork), #selector(paste), #selector(duplicate), #selector(deleteSelection), #selector(selectAll)],
        [#selector(screenSnap), #selector(fullscreenSnap), #selector(frameSnap), #selector(resnap)],
        [#selector(rotateCW), #selector(flipH), #selector(trimSnap), #selector(wipeSnap)],
        [#selector(toggleBezelFill(_:)), #selector(toggleBezelShadow(_:)), #selector(chooseFont)]
    ]
    func bezelToolbox() -> NSPopUpButton {
        let control = ToolboxPopUpButton(frame: .zero, pullsDown: true)
        control.font = DesignTokens.Typography.font(.body)
        let choices = NSMenu(title: "Toolbox")
        choices.addItem(withTitle: "Toolbox", action: nil, keyEquivalent: "")
        for (index, group) in Self.toolboxGroups.enumerated() {
            if index > 0 { choices.addItem(.separator()) }
            for action in group {
                if let item = copiedMainMenuItem(action) { choices.addItem(item) }
            }
        }
        MenuTypography.apply(to: choices)
        control.menu = choices; control.setAccessibilityLabel("Toolbox menu")
        AppToolTip.setText("Drawing, edit and capture commands; everything else is in the menu bar", for: control)
        return control
    }
    func buildWindow() {
        let visible = NSScreen.main?.visibleFrame.size ?? MainWindowFrame.defaultContentSize
        window = NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowFrame.defaultContentSize(fittingScreen: visible)),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = MainWindowFrame.untitled; window.delegate = self; window.minSize = NSSize(width: 900, height: MainWindowFrame.minimumHeight)
        buildModernWindowContent()
        configureWindowChrome()
        configureKeyViewLoop()
    }
    func configureDragExport(_ drag: DragExportView) {
        drag.prepare = { [weak self] in
            guard let self, !self.terminationStarted, !self.frameCaptureInProgress, self.window.attachedSheet == nil else { return nil }
            self.canvas.commitPendingTextEditing()
            self.updateDragPreview()
            guard let data = try? self.exportData(format: self.dragFormat, originalSize: self.dragAtOriginalSize, jpegQuality: self.dragQuality), let snapshot = try? self.historySnapshot() else { return nil }
            let name = self.safeName(), generation = self.documentGeneration
            return DragExportView.Payload(data: data, name: name, format: self.dragFormat, delivered: { [weak self] url in
                guard let self, !self.terminationStarted else { return }
                self.archive(snapshot, name: name, action: .exported, destination: url.path, generation: generation)
            })
        }
        drag.onBegin = { [weak self] id in self?.activeDragID = id }
        drag.onLeaveControl = { [weak self] id in self?.iconifyDrag(id) }
        drag.onEnd = { [weak self] id, succeeded in self?.endDrag(id, succeeded: succeeded) }
        drag.onDeliveryFailure = { [weak self] id in
            guard let self, !self.terminationStarted else { return }
            if self.activeDragID == id { self.activeDragID = nil }
            self.restoreDragThumbnail(id)
        }
        drag.onActivate = { [weak self] in
            guard let self, !self.terminationStarted, !self.frameCaptureInProgress, self.window.attachedSheet == nil else { return }
            self.exportFile()
        }
        AppToolTip.setText("Drag the drawing into Finder or another application", for: drag)
        trackHint(drag, owner: "drag-me") { OriginalHintMessages.hover(actionTag: 40) }
    }
    func wireEditorChrome(scroll: NSScrollView) {
        canvasBorder.onBegin = { [weak self] handle, flags in self?.beginWindowGesture(handle, flags: flags) ?? false }
        canvasBorder.onDrag = { [weak self] delta, flags in self?.previewBorderGesture(delta: delta, flags: flags) }
        canvasBorder.onEnd = { [weak self] cancelled in self?.endWindowGesture(cancelled: cancelled) }
        navigator.onNavigate = { [weak self] origin in
            guard let self, self.isActualSize, let scroll = self.canvas.enclosingScrollView else { return }
            scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView)
            self.updateViewportChrome()
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(canvasViewportChanged), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        canvas.strokeColor = colorWell.color; canvas.strokeWidth = CGFloat(OriginalDrawingControls.initialSize)
        canvas.fontSize = OriginalDrawingControls.readableFontSize(OriginalDrawingControls.initialSize)
        syncDrawingControls()
        canvas.strokeSmoothing = generalPreferences.state.drawingPrecision
        canvas.arrowHeadPreference = UserDefaults.standard.integer(forKey: OriginalArrowGeometry.preferenceKey)
        helpBevel = OriginalHelpBevel(host: window)
        helpBevel?.enabled = generalPreferences.state.showKeyboardTips
        // The opt-in hover-hint bevel replaces the tooltip on the controls it covers: never both.
        AppToolTip.shared.suppressed = { [weak self] view in
            guard let self, self.helpBevel?.enabled == true else { return false }
            return self.hintTrackedViews.contains(view)
        }
        canvas.onHintModifiers = { [weak self] flags in self?.hintModifiers(flags) }
        canvas.onHintHover = { [weak self] entered in
            guard let self else { return }
            if entered { self.helpBevel?.hover(owner: "canvas", message: OriginalHintMessages.hover(tool: self.canvas.tool)) }
            else { self.helpBevel?.exit(owner: "canvas") }
        }
    }
    func menu(_ title: String, items: [(String, Selector?, String)]) -> NSMenu {
        let m = NSMenu(title: title)
        for (name, action, key) in items { if name == "-" { m.addItem(.separator()); continue }; let item = NSMenuItem(title: name, action: action, keyEquivalent: key); item.target = self; m.addItem(item) }; return m
    }
    func buildMenus() {
        let bar = NSMenu()
        let name = DesignTokens.Brand.name
        let appMenu = menu(name, items: [("About " + name, #selector(about), ""), ("Settings…", #selector(showPreferences), ","), ("Sharing Settings…", #selector(sharingSettings), ""), ("Capture Shortcuts…", #selector(shortcutSettings), ""), ("-", nil, ""), ("Quit " + name, #selector(quit), "q")])
        appMenu.insertItem(NSMenuItem(title: "Hide " + name, action: #selector(toggleVisible), keyEquivalent: "h"), at: appMenu.numberOfItems - 1)
        appMenu.item(at: appMenu.numberOfItems - 2)?.target = self
        let quitIndex = appMenu.numberOfItems - 1
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        let showAll = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        for (offset, item) in [hideOthers, showAll, NSMenuItem.separator()].enumerated() {
            item.target = nil; appMenu.insertItem(item, at: quitIndex + offset)
        }
        let file = menu("File", items: [("New", #selector(newFile), "n"), ("Open…", #selector(openFile), "o"), ("Photos…", #selector(showPhotos), ""), ("Save", #selector(saveFile), "s"), ("Save As…", #selector(saveAs), "S"), ("Save to History", #selector(saveHistory), ""), ("History", #selector(showHistory), ""), ("Export…", #selector(exportFile), "e"), ("Publish…", #selector(publishImage), ""), ("Share…", #selector(shareFromMenu), ""), ("Print…", #selector(printImage), "p")])
        let close = NSMenuItem(title: "Close", action: #selector(closeCurrentWindow), keyEquivalent: "w")
        close.target = self; file.insertItem(close, at: 3)
        let setup = NSMenuItem(title: "Page Setup…", action: #selector(pageSetup), keyEquivalent: "P")
        setup.target = self; file.insertItem(setup, at: file.numberOfItems - 1)
        let rename = NSMenuItem(title: "Rename…", action: #selector(renameDocument), keyEquivalent: "")
        rename.target = self; file.insertItem(rename, at: (file.items.firstIndex { $0.title == "Save As…" } ?? 3) + 1)
        let edit = menu("Edit", items: [("Undo", #selector(undo), "z"), ("Redo", #selector(redo), "Z"), ("-", nil, ""), ("Cut", #selector(cut), "x"), ("Copy", #selector(copyArtwork), "c"), ("Copy Image", #selector(copyImage), ""), ("Paste", #selector(paste), "v"), ("Delete", #selector(deleteSelection), ""), ("Select All", #selector(selectAll), "a"), ("Duplicate", #selector(duplicate), "d"), ("-", nil, ""), ("Clear Image", #selector(wipe), ""), ("Remove Snap Picture", #selector(wipeSnap), "")])
        let arrange = menu("Arrange", items: [("Bring to Front", #selector(front), ""), ("Send to Back", #selector(back), ""), ("-", nil, ""), ("Group", #selector(group), ""), ("Ungroup", #selector(ungroup), "")])
        let arrangeItem = NSMenuItem(title: "Arrange", action: nil, keyEquivalent: ""); arrangeItem.submenu = arrange
        edit.insertItem(arrangeItem, at: (edit.items.firstIndex { $0.action == #selector(duplicate) } ?? edit.numberOfItems - 1) + 1)
        let image = menu("Image", items: [("Actual Size", #selector(toggleActualSize), ""), ("Resize…", #selector(resize), ""), ("Crop Selection", #selector(crop), ""), ("Crop Snap at Current Edges", #selector(trimSnap), ""), ("Set Snap to Normal Size", #selector(normalSize), ""), ("Rotate Clockwise", #selector(rotateCW), ""), ("Rotate Counterclockwise", #selector(rotateCCW), ""), ("Flip Horizontal", #selector(flipH), ""), ("Flip Vertical", #selector(flipV), ""), ("Transparent Background", #selector(transparent), ""), ("White Background", #selector(white), ""), ("Flatten", #selector(flatten), ""), ("Add Shadow", #selector(addShadow), "")])
        let text = menu("Text", items: [("Text Style…", #selector(chooseFont), ""), ("Default Text Style", #selector(defaultTextStyle), ""), ("Toggle Text Outline", #selector(toggleOutline), ""), ("Toggle Text Shadow", #selector(toggleTextShadow), "")])
        let spelling = NSMenu(title: "Spelling")
        for (title, action, key) in [("Spelling…", "showGuessPanel:", ":"), ("Check Spelling", "checkSpelling:", ";"), ("Check Spelling as You Type", "toggleContinuousSpellChecking:", "")] {
            // Original MainMenu.nib connects these directly to the text responder.
            // Keep the target nil so sheet fields and annotation editors both work.
            spelling.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let spellingItem = NSMenuItem(title: "Spelling", action: nil, keyEquivalent: ""); spellingItem.submenu = spelling; text.addItem(spellingItem)
        let snap = menu("Capture", items: [("Crosshair Snapshot", #selector(screenSnap), "1"), ("Fullscreen Snapshot", #selector(fullscreenSnap), "2"), ("Window Snapshot", #selector(windowSnap), "3"), ("Frame Snapshot", #selector(frameSnap), "4"), ("Re-snap (Keep Pen)", #selector(resnap), ""), ("Cancel Frame", #selector(cancelFrame), ""), ("Timed Snapshot…", #selector(timedSnap), ""), ("Cancel Snapshot", #selector(cancelSnapshot), ""), ("Snap from Link…", #selector(webSnap), "")])
        let drawing = menu("Drawing", items: [("Filled Shapes", #selector(toggleBezelFill(_:)), ""), ("Shadow", #selector(toggleBezelShadow(_:)), ""), ("-", nil, "")])
        let smoothing = menu("Pencil Smoothing", items: [])
        for mode in [StrokeSmoothing.precise, .medium, .loose] {
            let item = NSMenuItem(title: mode.rawValue.capitalized, action: #selector(changeSmoothing(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue; item.target = self; smoothing.addItem(item)
        }
        let smoothingItem = NSMenuItem(title: "Pencil Smoothing", action: nil, keyEquivalent: "")
        smoothingItem.submenu = smoothing; drawing.addItem(smoothingItem)
        let arrowHead = menu("Arrow Head", items: [])
        for (title, tag) in [("At Start", 1), ("At End", 2)] {
            let item = NSMenuItem(title: title, action: #selector(changeArrowHead(_:)), keyEquivalent: "")
            item.tag = tag; item.target = self; arrowHead.addItem(item)
        }
        let arrowHeadItem = NSMenuItem(title: "Arrow Head", action: nil, keyEquivalent: "")
        arrowHeadItem.submenu = arrowHead; drawing.addItem(arrowHeadItem)
        let windows = menu("Window", items: [("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "")])
        for item in windows.items { item.target = nil }
        let minimize = NSMenuItem(title: "Minimize", action: #selector(vanish), keyEquivalent: "m")
        minimize.target = self; windows.insertItem(minimize, at: 0)
        // The bars are not an NSToolbar, so the system's Move-focus-to-toolbar shortcut has nothing to find: this command is the way in.
        let focusItem = NSMenuItem(title: "Focus Toolbar", action: #selector(focusToolbar), keyEquivalent: "t")
        focusItem.keyEquivalentModifierMask = [.command, .option]; focusItem.target = self; windows.insertItem(focusItem, at: 1)
        // The standard full-screen command, so the green button is not the only way in or out.
        let fullScreen = NSMenuItem(title: "Enter Full Screen", action: #selector(toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]; fullScreen.target = self; windows.insertItem(fullScreen, at: 2)
        for m in [appMenu, file, edit, image, drawing, text, snap, windows] { let i = NSMenuItem(); i.submenu = m; bar.addItem(i) }
        MenuSymbols.apply(to: bar)
        MenuTypography.applyToDropdowns(of: bar)
        NSApp.mainMenu = bar; NSApp.windowsMenu = windows
    }
    @objc func changeSmoothing(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = StrokeSmoothing(rawValue: raw) else { return }
        canvas.strokeSmoothing = mode; generalPreferences.setPrecision(mode)
        settingsController?.synchronize(generalPreferences.state)
    }
    @objc func changeArrowHead(_ sender: NSMenuItem) {
        guard sender.tag == 1 || sender.tag == 2 else { return }
        canvas.arrowHeadPreference = sender.tag
        UserDefaults.standard.set(sender.tag, forKey: OriginalArrowGeometry.preferenceKey)
        settingsController?.synchronize(generalPreferences.state)
    }
    @objc func toggleFullScreen(_ sender: Any?) {
        guard !terminationStarted else { return }
        window.toggleFullScreen(sender)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleFullScreen(_:)) {
            menuItem.title = isFullScreen ? "Exit Full Screen" : "Enter Full Screen"
            // Frame mode takes the window out of the full-screen collection behaviour, so there is no way in while it is up.
            return !terminationStarted && (isFullScreen || !frameMode)
        }
        if Self.settingsOwnsKeyEquivalent(of: menuItem, event: NSApp.currentEvent, keyWindow: keyWindowProvider(), settingsWindow: preferencesWindow) { return false }
        if menuItem.action == #selector(addShadow) { return !terminationStarted && canvas.document.backgroundPNG != nil }
        if menuItem.action == #selector(statusShowHide) { menuItem.title = statusShowHideTitle; return !terminationStarted }
        if menuItem.action == #selector(cancelSnapshot) { return !terminationStarted && capture.isCapturing }
        if menuItem.action == #selector(showPreferences) { return !terminationStarted && !frameCaptureInProgress && window?.attachedSheet == nil }
        if menuItem.action == #selector(changeArrowHead(_:)) {
            menuItem.state = ((canvas.arrowHeadPreference == 1) == (menuItem.tag == 1)) ? .on : .off
            return !terminationStarted && !frameCaptureInProgress
        }
        if menuItem.action == #selector(wipe) {
            let stage = canvas.wipeStage
            menuItem.title = stage.menuTitle
            return stage.isEnabled
        }
        if menuItem.action == #selector(toggleBezelFill(_:)) { menuItem.state = canvas.filled ? .on : .off; return !terminationStarted && !frameCaptureInProgress }
        if menuItem.action == #selector(toggleBezelShadow(_:)) { menuItem.state = canvas.shadowed ? .on : .off; return !terminationStarted && !frameCaptureInProgress }
        if menuItem.action == #selector(chooseFont) {
            menuItem.state = fontPanel?.isVisible == true ? .on : .off
            return !terminationStarted
        }
        if menuItem.action == #selector(toggleActualSize) { menuItem.state = isActualSize ? .on : .off; return canToggleActualSize }
        if menuItem.action == #selector(renameDocument) { return !terminationStarted && !frameCaptureInProgress && window?.attachedSheet == nil }
        if menuItem.action == #selector(resize) { return !isActualSize && !frameMode }
        if menuItem.action == #selector(changeSmoothing(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == canvas.strokeSmoothing.rawValue ? .on : .off
        }
        if menuItem.action == #selector(undo) { return activeUndoManager.canUndo }
        if menuItem.action == #selector(redo) { return activeUndoManager.canRedo }
        return true
    }
    func updateToolButtons(_ tool: SketchTool) {
        // The crop tool is the one that works the borders, so only it keeps their handles showing at rest.
        canvasBorder.showsHandles = tool == .crop
        for (choice, button) in toolButtons {
            let selected = choice == tool
            button.state = selected ? .on : .off
            button.bezelColor = selected ? .controlAccentColor : nil
            let tip = choice.rawValue.capitalized + (selected ? " tool (selected)" : " tool")
            AppToolTip.setText(choice == .arrow ? tip + "; Option reverses direction, Shift constrains the angle" : tip, for: button)
            button.needsDisplay = true
        }
    }
    func setTool(_ tool: SketchTool) { canvas.tool = tool; updateToolButtons(tool); window?.makeFirstResponder(canvas); updateStatus() }
    @objc func chooseTool(_ sender: NSButton) { if let s = sender.identifier?.rawValue, let t = SketchTool(rawValue: s) { setTool(t) } }
    @objc func changeColor(_ sender: Any) {
        // NSColorPanel can route its standard changeColor: before a custom
        // target is installed. It uses calibrated components, unlike pen state.
        if let panel = sender as? NSColorPanel { changeCustomColor(panel) }
        else if let well = sender as? NSColorWell { applyChosenColor(well.color, modifiers: NSApp.currentEvent?.modifierFlags ?? []) }
    }
    func applyChosenColor(_ color: NSColor, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) {
            canvas.setBackgroundColor(color); colorWell.color = canvas.strokeColor
        } else {
            canvas.strokeColor = color; canvas.applyColorToSelection(color)
        }
        rememberDrawingDefaults(); syncDrawingControls()
        writeLayoutEvidence()
    }
    @objc func changeWidth(_ sender: NSControl) {
        let size = OriginalDrawingControls.size(sender.doubleValue, continuous: true)
        canvas.strokeWidth = CGFloat(size); canvas.fontSize = OriginalDrawingControls.readableFontSize(size, displayFontScale: canvas.outputSize.height / canvas.canvasSize.height)
        _ = canvas.convertSelectedTextFonts({ NSFont(name: $0.fontName, size: self.canvas.fontSize) }, name: "Change Text Size")
        rememberDrawingDefaults(); syncDrawingControls(); updateStatus(); writeLayoutEvidence()
    }
    func endDrawingSizeGesture() {
        guard sizeUndoGrouping else { return }
        sizeUndoGrouping = false; canvas.editingUndoManager.endUndoGrouping(); writeLayoutEvidence()
    }
    func syncDrawingControls() {
        colorWell.color = canvas.strokeColor
        widthControl.doubleValue = Double(canvas.strokeWidth)
        sizeLabel.stringValue = "Size · " + String(format: "%.0f", widthControl.doubleValue.rounded())
        // Modern has no visible Size text; the slider carries the value in its tooltip (VoiceOver reads its accessibilityValue).
        AppToolTip.setText("Size " + String(format: "%.0f", widthControl.doubleValue.rounded()), for: widthControl)
        let indicatorColor = canvas.strokeColor
        let swatchSize = NSSize(width: 28, height: 22)
        paletteButton.image = NSImage(size: swatchSize, flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            indicatorColor.setFill(); rect.insetBy(dx: 1, dy: 1).fill()
            DesignTokens.Palette.SwatchOutline.rest.setStroke(); NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke(); return true
        }
        let chosen = SketchColor(canvas.strokeColor)
        for button in presetColorButtons {
            let preset = OriginalDrawingControls.presets.first { $0.tag == button.tag }
            button.state = preset.map { SketchColor($0.color) == chosen } == true ? .on : .off
        }
        // A colour that is none of the presets is marked on the Custom color… row instead.
        customColorButton?.currentColor = presetColorButtons.contains { $0.state == .on } ? nil : canvas.strokeColor
        paletteButton.setAccessibilityValue(String(format: "Red %.3g, green %.3g, blue %.3g, alpha %.3g", chosen.red, chosen.green, chosen.blue, chosen.alpha))
    }
    @objc func showDrawingColors(_ sender: NSButton) {
        guard !terminationStarted, !frameCaptureInProgress, window.attachedSheet == nil else { return }
        if let colorPopover, colorPopover.isShown {
            // Keep click/keyboard access stable when entering Color first
            // opened it by hover. An explicit activation pins the palette.
            if colorOpenedByHover {
                colorOpenedByHover = false; colorHoverDismissal?.cancel(); colorHoverDismissal = nil
            } else { closeDrawingColors() }
            writeLayoutEvidence(); return
        }
        presentDrawingColors(hover: false)
    }
    func drawingColorHover(_ inside: Bool, palette: Bool) {
        if palette { colorPaletteHovered = inside } else { colorControlHovered = inside }
        colorHoverDismissal?.cancel(); colorHoverDismissal = nil
        if inside {
            if !palette && colorPopover?.isShown != true { presentDrawingColors(hover: true) }
        } else if colorOpenedByHover && !colorControlHovered && !colorPaletteHovered {
            // The modern popover has an arrow gap absent from the old panel.
            // Briefly bridge that gap so crossing into the swatches cannot close it.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.colorOpenedByHover, !self.colorControlHovered, !self.colorPaletteHovered else { return }
                self.closeDrawingColors()
            }
            colorHoverDismissal = work
            DispatchQueue.main.asyncAfter(deadline: .now()+0.12, execute: work)
        }
    }
    func closeDrawingColors() {
        colorHoverDismissal?.cancel(); colorHoverDismissal = nil
        colorOpenedByHover = false; colorControlHovered = false; colorPaletteHovered = false
        (colorPopover?.contentViewController?.view as? BezelHoverPaletteView)?.onHover = nil
        colorPopover?.performClose(nil)
    }
    func presentDrawingColors(hover: Bool) {
        guard !terminationStarted, !frameCaptureInProgress, window.isVisible,
              window.attachedSheet == nil, colorPopover?.isShown != true else { return }
        colorOpenedByHover = hover
        // 12 pt margins around a grid of five 42 x 32 swatches (each draws 3 pt inside its frame); the Custom color… row spans exactly the
        // drawn grid, so the left and right edges of every row line up.
        let view = BezelHoverPaletteView(frame: NSRect(x: 0, y: 0, width: 246, height: 155))
        view.onHover = { [weak self] inside in self?.drawingColorHover(inside, palette: true) }
        let title = label("Drawing colors"); title.textColor = DesignTokens.Palette.Text.primary; title.frame = NSRect(x: 13, y: 118, width: 220, height: 25); view.addSubview(title)
        presetColorButtons.removeAll()
        for (index, preset) in OriginalDrawingControls.presets.enumerated() {
            let button = BezelColorButton(frame: NSRect(x: CGFloat(12+(index%5)*45), y: CGFloat(78-(index/5)*34), width: 42, height: 32))
            button.title = ""; button.isBordered = false; button.font = DesignTokens.Typography.font(.body)
            button.drawingColor = preset.color; button.tag = preset.tag
            button.target = self; button.action = #selector(choosePresetColor(_:))
            button.setAccessibilityLabel(preset.name); AppToolTip.setText(preset.name + "; Shift changes the background", for: button)
            trackHint(button, owner: "color-" + String(preset.tag)) { OriginalHintMessages.hover(actionTag: preset.tag) }
            presetColorButtons.append(button); view.addSubview(button)
        }
        let custom = BezelCustomColorButton(title: "Custom color…", target: self, action: #selector(chooseCustomColor(_:)))
        custom.font = DesignTokens.Typography.font(.body)
        custom.frame = NSRect(x: 15, y: 12, width: 216, height: 30); custom.tag = 110; view.addSubview(custom)
        customColorButton = custom
        // The popover is its own window: the preset swatches in reading order, then Custom color…, then round again.
        let swatchOrder: [NSView] = presetColorButtons + [custom]
        for (index, swatch) in swatchOrder.enumerated() { swatch.nextKeyView = swatchOrder[(index + 1) % swatchOrder.count] }
        AppToolTip.install(on: view)
        let controller = NSViewController(); controller.view = view
        let popover = NSPopover(); popover.behavior = .transient; popover.contentViewController = controller
        colorPopover = popover; syncDrawingControls()
        popover.show(relativeTo: paletteButton.bounds, of: paletteButton, preferredEdge: .minY)
        writeLayoutEvidence()
    }
    @objc func choosePresetColor(_ sender: NSButton) {
        guard !terminationStarted, !frameCaptureInProgress,
              let preset = OriginalDrawingControls.presets.first(where: { $0.tag == sender.tag }) else { return }
        applyChosenColor(preset.color, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
        closeDrawingColors()
    }
    @objc func chooseCustomColor(_ sender: NSButton) {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        closeDrawingColors()
        // The panel opens on the colour in use and applies nothing: only a change the user makes while it is open (the target and action
        // below) becomes the drawing colour, so opening or closing it can never repaint anything.
        let panel = colorPanelProvider(); panel.showsAlpha = true; panel.isContinuous = true
        customColorPanelOpen = false
        panel.setTarget(nil); panel.setAction(nil)
        panel.color = canvas.strokeColor
        panel.setTarget(self); panel.setAction(#selector(changeCustomColor(_:)))
        customColorPanelOpen = true
        if let colorPanelCloseObserver { NotificationCenter.default.removeObserver(colorPanelCloseObserver) }
        colorPanelCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseCustomColorPanel(panel) }
        }
        panel.orderFront(sender)
    }
    /// The panel is closed: it stops talking to the editor, and nothing it is later told (by a text box, say) reaches the drawing.
    func releaseCustomColorPanel(_ panel: NSColorPanel) {
        customColorPanelOpen = false
        panel.setTarget(nil); panel.setAction(nil)
        if let colorPanelCloseObserver { NotificationCenter.default.removeObserver(colorPanelCloseObserver); self.colorPanelCloseObserver = nil }
    }
    @objc func changeCustomColor(_ sender: NSColorPanel) {
        guard !terminationStarted, !frameCaptureInProgress, customColorPanelOpen, sender.isVisible else { return }
        guard let chosen = OriginalDrawingControls.drawingColor(from: sender.color) else { return }
        customDrawingColor = sender.color
        applyChosenColor(chosen, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
    }
    func rememberDrawingDefaults() {
        let color = SketchColor(canvas.strokeColor)
        let custom = OriginalDrawingControls.drawingColor(from: customDrawingColor) ?? OriginalDrawingControls.presets[0].color
        drawingDefaults.values["brushColor"] = OriginalDrawingControls.legacyRGB(canvas.strokeColor)
        drawingDefaults.values["brushColorAlpha"] = String(Double(color.alpha))
        drawingDefaults.values["brushSize"] = String(Double(canvas.strokeWidth))
        drawingDefaults.values["customColor"] = OriginalDrawingControls.legacyRGB(custom)
        drawingDefaults.values["customColorAlpha"] = String(Double(SketchColor(custom).alpha))
    }
    func restoreDrawingDefaults() {
        closeDrawingColors()
        if let color = OriginalDrawingControls.legacyColor(drawingDefaults.values["brushColor"], alpha: drawingDefaults.values["brushColorAlpha"]) {
            canvas.strokeColor = color
        }
        if let custom = OriginalDrawingControls.legacyColor(drawingDefaults.values["customColor"], alpha: drawingDefaults.values["customColorAlpha"]) {
            let rgba = SketchColor(custom)
            customDrawingColor = NSColor(calibratedRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha) // token-exempt: drawing colour data, not chrome
        }
        if let size = Double(drawingDefaults.values["brushSize"] ?? ""), size.isFinite {
            canvas.strokeWidth = CGFloat(OriginalDrawingControls.size(size, continuous: true))
            canvas.fontSize = OriginalDrawingControls.readableFontSize(Double(canvas.strokeWidth), displayFontScale: canvas.outputSize.height / canvas.canvasSize.height)
        }
        syncDrawingControls()
    }
    /// The two Drawing toggles set a pen default and change only that one flag on the selection; they never restyle it with the pen.
    @objc func toggleBezelFill(_ sender: NSMenuItem) { canvas.filled.toggle(); canvas.setFilledOnSelection(canvas.filled) }
    @objc func toggleBezelShadow(_ sender: NSMenuItem) { canvas.shadowed.toggle(); canvas.setShadowOnSelection(canvas.shadowed) }
    @objc func changeZoom(_ sender: NSPopUpButton) {
        AppToolTip.setText(sender.selectedItem?.toolTip, for: sender)
        guard !isActualSize, let scale = sender.selectedItem?.representedObject as? Double else { return }
        canvas.setZoom(CGFloat(scale)); updateStatus()
    }
    /// Zooms the whole drawing into the window. A window never magnifies it past 100%; full screen passes a larger ceiling.
    func fitCanvasToWindow(maximumScale: CGFloat = 1) {
        window.contentView?.layoutSubtreeIfNeeded()
        guard let scroll = canvas.enclosingScrollView else { return }
        let viewport = scroll.contentView.bounds.size, size = canvas.outputSize
        let scale = min(maximumScale, max(0.05, min((viewport.width-20)/size.width, (viewport.height-20)/size.height)))
        setCanvasDisplayZoom(scale, label: "Fit")
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
    }
    func setCanvasDisplayZoom(_ scale: CGFloat, label: String) {
        canvas.setZoom(scale)
        for item in zoomControl.itemArray where item.tag == 999 { zoomControl.menu?.removeItem(item) }
        // The face is the percentage alone; the mode word rides on the tooltip and in the spoken value ("Fit, 83%").
        let percent = "\(Int((canvas.zoom*100).rounded()))%"
        let item = NSMenuItem(title: percent, action: nil, keyEquivalent: "")
        item.toolTip = "\(label), \(percent)"
        AppToolTip.setText("\(label), \(percent)", for: zoomControl)
        item.tag = 999; item.representedObject = Double(canvas.zoom); zoomControl.menu?.insertItem(item, at: 0); zoomControl.select(item)
    }
    func changed() {
        if isActualSize { _ = canvas.setPresentationOutputSize(canvas.fullResolutionOutputSize); scheduleNavigatorImage() }
        if !restoring { dirty = true; clearStatusNotice() }
        window?.isDocumentEdited = dirty; updateStatus(); updateWipeButton()
        historyFollowTimer?.invalidate()
        if currentArchiveID != nil {
            let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in Task { @MainActor in self?.followHistory() } }
            historyFollowTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    /// Original updateWipeButton: the stage (blank, clear, wipe) is derived from the canvas; the button says what it does ("Remove annotations",
    /// "Clear image") and, dimmed on a blank canvas, why there is nothing to do.
    func updateWipeButton() {
        if wipeButton == nil { wipeButton = findWipeButton(in: window?.contentView) }
        guard let button = wipeButton else { return }
        let stage = canvas.wipeStage
        if button.title != stage.actionName { button.title = stage.actionName }
        if button.isEnabled != stage.isEnabled { button.isEnabled = stage.isEnabled }
        if AppToolTip.text(for: button) != stage.toolTip { AppToolTip.setText(stage.toolTip, for: button) }
        updateUndoButton()
    }
    /// The Undo button follows the same history as Edit > Undo, so a blank document shows it dimmed.
    func updateUndoButton() {
        guard let button = (modernChrome as? ModernEditorChrome)?.undoButton else { return }
        let available = activeUndoManager.canUndo
        if button.isEnabled != available { button.isEnabled = available }
    }
    private func findWipeButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.action == #selector(wipe) { return button }
        for sub in view.subviews { if let found = findWipeButton(in: sub) { return found } }
        return nil
    }
    func updateStatus() {
        expireStaleUploadFailure()
        refreshStatusText()
        updateUndoButton()
        updateViewportChrome(); scheduleDragPreview() }
    /// The one status line: tool, saved state and the export size and bytes the drag preview last measured.
    /// A narrow window shows the longest of these that fits whole (bytes go first, then the tool, never the state);
    /// the tooltip and the spoken value always carry the full text. Frame mode keeps its own hint.
    func refreshStatusText() {
        guard !frameMode else { return }
        let variants: [String]
        if let notice = statusNotice { variants = [notice] }
        else if !uploadState.statusVariants.isEmpty { variants = uploadState.statusVariants }
        else if let notice = UploadNotice.text { variants = [notice] }
        else if canvas.tool == .crop && canvas.hasPendingCrop {
            // The crop is applied by Return and dropped by Esc; say so, shortest last, never the state alone first.
            variants = ["Crop: press Return to apply, Esc to cancel", "Crop: Return applies, Esc cancels", "Return applies, Esc cancels", dirty ? "Unsaved changes" : "Saved"]
        } else {
            let tool = canvas.tool.rawValue.capitalized, state = dirty ? "Unsaved changes" : "Saved"
            let detail = dragSizeLabel.stringValue
            if detail.isEmpty { variants = ["\(tool) · \(state)", state] }
            else {
                let dimensions = detail.components(separatedBy: " · ")[0]
                variants = ["\(tool) · \(state) · \(detail)", "\(tool) · \(state) · \(dimensions)", "\(state) · \(dimensions)", state]
            }
        }
        status.setVariants(variants)
        AppToolTip.setText(uploadState.detailText ?? variants[0], for: status, mirrorsToAccessibility: false)
        status.setAccessibilityHelp(uploadState.detailText)
    }
    var dragFormat: String {
        FormatToggle.payload(forSegment: dragFormatToggle.selectedSegment).format
    }
    var dragQuality: Double {
        FormatToggle.payload(forSegment: dragFormatToggle.selectedSegment).quality
    }
    @objc func changeDragOptions(_ sender: Any?) {
        let current = UserDefaults.standard.integer(forKey: FormatToggle.defaultsKey)
        UserDefaults.standard.set(FormatToggle.storedChoice(forSegment: dragFormatToggle.selectedSegment, current: current), forKey: FormatToggle.defaultsKey)
        UserDefaults.standard.set(dragOriginalControl.state == .on, forKey: "DragOriginalSize")
        scheduleDragPreview()
    }
    func scheduleDragPreview() {
        guard dragExportView != nil else { return }
        dragPreviewTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDragPreview() }
        }
        dragPreviewTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func updateDragPreview() {
        dragPreviewTimer?.invalidate(); dragPreviewTimer = nil
        let original = dragAtOriginalSize
        let size = SketchDocument.wholePixels(original && canvas.document.backgroundPNG != nil ? canvas.canvasSize : canvas.outputSize)
        if let data = try? exportData(format: dragFormat, originalSize: original, jpegQuality: dragQuality) {
            dragSizeLabel.stringValue = "\(Int(size.width)) × \(Int(size.height)) · " + (dragFormat == "jpeg" ? "JPG" : "PNG") + " · " + ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            window?.subtitle = dragSizeLabel.stringValue
        } else { dragSizeLabel.stringValue = "Preview unavailable"; window?.subtitle = "" }
        refreshStatusText()
        if let raw = try? canvas.snapshotDocumentData(), let document = try? CanvasView.validatedDocumentData(raw) {
            let scale = min(1, 128 / max(document.size.width, document.size.height))
            dragExportView?.overview = ImageExport.image(document: document, size: CGSize(width: max(1, ceil(document.size.width * scale)), height: max(1, ceil(document.size.height * scale))))
        }
    }
    func safeName() -> String { let s = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); return (s.isEmpty ? MainWindowFrame.untitled : s).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
    func applyFrameWindowValues() {
        window.hasShadow = false
        window.alphaValue = CGFloat(Float32(bitPattern: 0x3f4ccccd))
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
    }
    /// The screen-saver Frame level would bury alerts and panels (they open at modal level),
    /// so modals shown during Frame run with the stored pre-Frame window values.
    func withFrameWindowValuesSuspended<T>(_ body: () -> T) -> T {
        guard frameMode else { return body() }
        window.hasShadow = frameWindowHadShadow; window.alphaValue = frameWindowAlpha; window.level = frameWindowLevel
        defer { if frameMode { applyFrameWindowValues() } }
        return body()
    }
    /// Raises an app-owned alert on the document window. It is a sheet, so it never blocks; `completion` gets the answer later.
    func present(_ alert: AppAlert, on host: NSWindow? = nil, completion: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        alert.present(on: host ?? alertHost, completion: completion)
    }
    /// The window a question belongs to: the one in front when it is one of ours (History, Settings), else the document window.
    var alertHost: NSWindow? {
        if let key = NSApp.keyWindow, key !== window, key.isVisible, !(key is NSColorPanel), !(key is NSFontPanel), !(key is NSSavePanel),
           key.isSheet || key.canBecomeMain { return key }
        return window
    }
    func error(_ error: Error) { present(AppAlert(error: error)) }
    /// Asks whether the unsaved changes may go, then calls `proceed` once: true to carry on, false to stop.
    /// The question is a sheet, so `proceed` runs after the answer; callers continue from it.
    /// Only one question from New, Open and captures is open at a time (a sheet does not stop the menu), but Quit may always ask.
    func confirmDiscard(discardingForTermination: Bool = false, on host: NSWindow? = nil, proceed: @escaping (Bool) -> Void) {
        if discardedForTermination { proceed(true); return }
        guard dirty || canvas.hasPendingTextChanges else { proceed(true); return }
        if !discardingForTermination && discardQuestionOpen { proceed(false); return }
        if !discardingForTermination { discardQuestionOpen = true }
        let alert = AppAlert(title: "Save your drawing?", message: "This document has changes that have not been saved.",
                             buttons: [.init(title: "Save"), .init(title: "Cancel", role: .cancel), .init(title: "Don\u{2019}t Save", role: .destructive)])
        present(alert, on: host) { [weak self] result in
            guard let self else { return }
            if !discardingForTermination { self.discardQuestionOpen = false }
            // A question left open while Quit went ahead is moot: it must not save or discard under a document that is closing.
            if self.terminationStarted && !discardingForTermination { proceed(false); return }
            switch result {
            case .alertFirstButtonReturn: proceed(self.save())
            case .alertThirdButtonReturn:
                if discardingForTermination { self.discardedForTermination = true; self.dirty = false }
                proceed(true)
            default: proceed(false)
            }
        }
    }
    @objc func newFile() {
        guard !terminationStarted else { return }
        confirmDiscard { [weak self] allowed in
            guard let self, allowed, !self.terminationStarted else { return }
            do {
                // The original loads the replacement and registers one transaction (loadFromFileTA, decompiled.c:314172-314243).
                let scratch = CanvasView(frame: .zero); scratch.newBlank(size: NSSize(width: 1000, height: 700))
                try self.restoreHistoryEditorState(HistoryEditorState(data: try scratch.snapshotDocumentData(), drawingDefaults: .init(), name: "Untitled",
                    url: nil, archiveID: nil, dirty: false), actionName: "New", resetDrawingDefaults: false)
                self.replaceDragPresentation()
            } catch { self.error(error) }
        }
    }
    @objc func openFile() { let p = NSOpenPanel(); p.allowedContentTypes = Self.openPanelContentTypes; p.allowsMultipleSelection = false; if withFrameWindowValuesSuspended({ p.runModal() }) == .OK, let u = p.url { openURL(u) } }
    static let documentType = UTType(exportedAs: OpenSnapFile.typeIdentifier, conformingTo: .data)
    /// The only documents the app opens: pictures it can edit and its own .opensnap drawings.
    static let openPanelContentTypes: [UTType] = [.image, .pdf, documentType]
    static let savePanelContentTypes: [UTType] = [documentType]
    static let recoveryName = "Recovery." + OpenSnapFile.fileExtension
    func openURL(_ url: URL) {
        guard !terminationStarted else { return }
        confirmDiscard { [weak self] allowed in
            guard let self, allowed, !self.terminationStarted else { return }
            self.openApproved(url)
        }
    }
    private func openApproved(_ url: URL) {
        do {
            let state: HistoryEditorState, native = url.pathExtension.lowercased() == OpenSnapFile.fileExtension
            if native {
                let file = try OpenSnapFile.read(url)
                // Bundled samples stay intact; ordinary drawings save in place.
                state = HistoryEditorState(data: try file.canvasData, drawingDefaults: file.drawingDefaults, name: url.deletingPathExtension().lastPathComponent,
                    url: url.path.contains(".app/Contents/Resources/") ? nil : url, archiveID: nil, dirty: false)
            } else {
                guard SketchDocument.isPictureFile(url) else {
                    throw NSError(domain: "OpenSnap", code: 3, userInfo: [NSLocalizedDescriptionKey: "OpenSnap opens pictures, PDFs and its own .opensnap drawings, but not this kind of file."])
                }
                guard let image = NSImage(contentsOf: url) else { throw NSError(domain: "OpenSnap", code: 3, userInfo: [NSLocalizedDescriptionKey: "The file could not be read as an image."]) }; var proposed = CGRect(origin: .zero, size: image.size)
                guard let pixels = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil), SketchDocument.validSize(NSSize(width: pixels.width, height: pixels.height)) else {
                    throw NSError(domain: "OpenSnap", code: 5, userInfo: [NSLocalizedDescriptionKey: "This image is too large or cannot be decoded safely."])
                }
                let scratch = CanvasView(frame: .zero)
                scratch.newBlank(size: NSSize(width: pixels.width, height: pixels.height)); scratch.setBackground(image)
                state = HistoryEditorState(data: try scratch.snapshotDocumentData(), drawingDefaults: .init(), name: url.deletingPathExtension().lastPathComponent,
                    url: nil, archiveID: nil, dirty: false)
            }
            try restoreHistoryEditorState(state, actionName: "Open", resetDrawingDefaults: native, rasterViewport: !native)
            replaceDragPresentation()
        } catch { self.error(error) }
    }
    func save(forceChoose: Bool = false) -> Bool {
        if let session = activeResizeSession {
            do { guard try session.apply() else { return false } }
            catch { self.error(error); return false }
        }
        endWindowGesture()
        var url = forceChoose ? nil : currentURL
        let choseInPanel = url == nil
        if url == nil { let p = NSSavePanel(); p.nameFieldStringValue = safeName()+"."+OpenSnapFile.fileExtension; p.allowedContentTypes = Self.savePanelContentTypes; if p.runModal() != .OK { return false }; url = p.url }
        do {
            guard let url else { return false }
            let snapshot = try canvas.snapshotDocumentData(); let document = try CanvasView.validatedDocumentData(snapshot)
            try OpenSnapFile(document: document, drawingDefaults: drawingDefaults, canvasData: snapshot).write(to: url)
            canvas.commitPendingTextEditing(); currentURL = url; dirty = false; window.isDocumentEdited = false
            // A file the user just named in the save panel is the document: its name, and the title that shows it, follow that name.
            if choseInPanel { nameField.stringValue = url.deletingPathExtension().lastPathComponent }
            updateStatus()
            postStatusNotice("Saved " + url.lastPathComponent)
            if isActualSize { actualView?.savedWhileActive = true }
            archive(try HistoryStore.Snapshot(canvasData: snapshot, drawingDefaults: drawingDefaults, preview: canvas.imageData(format: "png")), name: safeName(), action: .exported, destination: url.path, generation: documentGeneration)
            return true
        } catch { self.error(error); return false }
    }
    @objc func saveFile() { _ = save() }
    @objc func saveAs() { _ = save(forceChoose: true) }
    func saveRecovery(finalizingTermination: Bool = false) {
        // Queued timer work must not interpret the temporary Discard dirty flag
        // as permission to delete recovery before backend cleanup succeeds.
        guard !terminationStarted || finalizingTermination else { return }
        guard activeResizeSession?.lastPreview == nil else { return }
        followHistory()
        let url = support.appendingPathComponent(Self.recoveryName)
        guard dirty || canvas.hasPendingTextChanges else { removeRecovery(); return }
        guard let snapshot = try? canvas.snapshotDocumentData(), let document = try? CanvasView.validatedDocumentData(snapshot), let data = try? OpenSnapFile(document: document, drawingDefaults: drawingDefaults, canvasData: snapshot).encoded() else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch { return }
    }
    func removeRecovery() {
        try? FileManager.default.removeItem(at: support.appendingPathComponent(Self.recoveryName))
    }
    func archiveStore() throws -> HistoryStore {
        if let historyStore { return historyStore }
        let store = try HistoryStore(directory: support.appendingPathComponent("History"))
        historyStore = store
        return store
    }
    func historySnapshot() throws -> HistoryStore.Snapshot {
        let raw = try canvas.snapshotDocumentData()
        let document = try CanvasView.validatedDocumentData(raw)
        let preview = ImageExport.encode(document: document, size: document.outputSize, format: "png")
        return try HistoryStore.Snapshot(canvasData: raw, drawingDefaults: drawingDefaults, preview: preview)
    }
    @discardableResult
    func archive(_ snapshot: HistoryStore.Snapshot, name: String, action: HistoryStore.Action,
                 destination: String? = nil, remoteURL: URL? = nil, remoteBinding: [String: String]? = nil, generation: UUID) -> Bool {
        guard !snapshot.isEmpty else { return false }
        do {
            let store = try archiveStore()
            let id = try store.archive(snapshot, name: name, action: action, destination: destination, remoteURL: remoteURL, remoteBinding: remoteBinding)
            if documentGeneration == generation {
                followHistory(); currentArchiveID = id
                // An asynchronous export may have completed after more edits.
                // Keep its successful-output snapshot, then follow the live copy.
                followHistory()
            }
            refreshHistory()
            return true
        } catch { status.stringValue = "History could not be updated: " + error.localizedDescription; return false }
    }
    func followHistory() {
        guard activeResizeSession?.lastPreview == nil else { return }
        historyFollowTimer?.invalidate(); historyFollowTimer = nil
        guard let id = currentArchiveID else { return }
        do { try archiveStore().follow(id, snapshot: historySnapshot(), name: safeName()); refreshHistory() }
        catch { status.stringValue = "History update failed; the previous archive was preserved: " + error.localizedDescription }
    }
    @objc func saveHistory() {
        do {
            if archive(try historySnapshot(), name: safeName(), action: .archived, generation: documentGeneration) { postStatusNotice("Saved to History") }
        } catch { self.error(error) }
    }
    func refreshHistory() {
        guard let browser = historyBrowser, let store = historyStore else { return }
        browser.update(items: store.entries.map { entry in
            HistoryBrowser.Item(id: entry.id, name: entry.name, date: entry.date, size: entry.size,
                action: entry.action.title, text: entry.text, destination: entry.destination,
                link: entry.remoteURL, previewURL: store.previewURL(entry), missing: store.missing(entry.id),
                canDeleteFromWeb: entry.remoteBinding != nil)
        })
    }
    @objc func showHistory() {
        do {
            _ = try archiveStore(); followHistory()
            if historyBrowser == nil {
                let browser = HistoryBrowser()
                browser.onOpen = { [weak self] ids in if let id = ids.first { self?.openHistory(id) } }
                browser.onCopy = { [weak self] ids in self?.copyHistory(ids) }
                browser.onCopyLink = { [weak self] ids in self?.copyHistoryLink(ids) }
                browser.onOpenLink = { [weak self] ids in
                    guard let self, let id = ids.first, let url = self.historyStore?.entry(id)?.remoteURL,
                          ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
                    NSWorkspace.shared.open(url)
                }
                browser.onRemove = { [weak self] ids in self?.removeHistory(ids, deleteFiles: false) }
                browser.onDeleteFiles = { [weak self] ids in self?.removeHistory(ids, deleteFiles: true) }
                browser.onDeleteRemote = { [weak self] ids in self?.deleteHistoryRemote(ids) }
                browser.onExport = { [weak self] id, format in
                    guard let self else { throw HistoryStore.Failure.missing }
                    return try self.historyExport(id, format: format)
                }
                browser.onError = { [weak self] in self?.presentFromHistory(AppAlert(error: $0)) }
                historyBrowser = browser
            }
            refreshHistory(); historyBrowser?.showWindow(nil); historyBrowser?.window?.makeKeyAndOrderFront(nil)
            if let content = historyBrowser?.window?.contentView { AppToolTip.install(on: content) }
        } catch { self.error(error) }
    }
    struct HistoryEditorState {
        let data: Data; let drawingDefaults: DrawingDefaults; let name: String
        let url: URL?; let archiveID: UUID?; let dirty: Bool
    }
    func historyEditorState() throws -> HistoryEditorState {
        HistoryEditorState(data: try canvas.snapshotDocumentData(), drawingDefaults: drawingDefaults, name: nameField.stringValue,
                           url: currentURL, archiveID: currentArchiveID, dirty: dirty)
    }
    /// The whole document identity participates in the same Undo operation as
    /// the artwork, so reopening History cannot redirect a later Save.
    func restoreHistoryEditorState(_ state: HistoryEditorState, actionName: String = "Open History",
                                   resetDrawingDefaults: Bool = true, rasterViewport: Bool = false) throws {
        _ = try CanvasView.validatedDocumentData(state.data)
        canvas.commitPendingTextEditing()
        activeResizeSession?.cancel(); endWindowGesture(cancelled: true); leaveActualSize()
        let inverse = try historyEditorState()
        followHistory(); leaveFrame()
        restoring = true
        defer { restoring = false }
        try canvas.loadDocument(data: state.data, clearingUndo: false)
        drawingDefaults = state.drawingDefaults; if resetDrawingDefaults { restoreDrawingDefaults() }; nameField.stringValue = state.name; currentURL = state.url
        currentArchiveID = state.archiveID; dirty = state.dirty; documentGeneration = UUID()
        let manager = canvas.editingUndoManager
        let grouping = !manager.isUndoing && !manager.isRedoing
        if grouping { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { app in
            do { try app.restoreHistoryEditorState(inverse, actionName: actionName, resetDrawingDefaults: resetDrawingDefaults) } catch { app.error(error) }
        }
        manager.setActionName(actionName)
        if grouping { manager.endUndoGrouping() }
        if rasterViewport { adoptRasterViewport() } else { fitCanvasToWindow() }
        window.isDocumentEdited = dirty; updateStatus(); refreshHistory()
    }
    /// History's Open runs the same guard as File > New and Open: a document with unsaved changes asks first, on History, where the click was.
    func openHistory(_ id: UUID) {
        guard !terminationStarted else { return }
        confirmDiscard(on: historyHost) { [weak self] allowed in
            guard let self, allowed, !self.terminationStarted else { return }
            self.openHistoryApproved(id)
        }
    }
    private func openHistoryApproved(_ id: UUID) {
        do {
            let store = try archiveStore(), file = try store.read(id)
            guard let entry = store.entry(id) else { throw HistoryStore.Failure.missing }
            // The archive already holds this document (and keeps following it), so a freshly opened entry has nothing unsaved.
            try restoreHistoryEditorState(HistoryEditorState(data: file.canvasData, drawingDefaults: file.drawingDefaults,
                name: entry.name, url: nil, archiveID: id, dirty: false))
            historyBrowser?.window?.orderOut(nil)
            replaceDragPresentation(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas)
        } catch { self.presentFromHistory(AppAlert(error: error)); refreshHistory() }
    }
    func historyExport(_ id: UUID, format: String) throws -> Data {
        let file = try archiveStore().read(id)
        if format == OpenSnapFile.fileExtension { return try file.encoded() }
        if format == "svg" { return try SVGExport.encode(file.document) }
        let view = CanvasView(frame: .zero); try view.loadDocument(data: file.canvasData)
        guard let data = view.imageData(format: format, jpegQuality: historyJPEGQuality) else { throw HistoryStore.Failure.missing }
        return data
    }
    /// Every JPG is written at the toggle's fixed quality.
    var historyJPEGQuality: Double { FormatToggle.jpgQuality }
    func copyHistory(_ ids: [UUID]) {
        do {
            guard let id = ids.first else { return }
            let file = try archiveStore().read(id), native = try file.encoded()
            let view = CanvasView(frame: .zero); try view.loadDocument(data: file.canvasData)
            guard let png = view.imageData(format: "png") else { throw HistoryStore.Failure.missing }
            let board = NSPasteboard.general; board.clearContents()
            board.setData(png, forType: .png)
            board.setData(native, forType: NSPasteboard.PasteboardType("com.shoemoney.opensnap.native"))
            if let tiff = view.renderedImage().tiffRepresentation { board.setData(tiff, forType: .tiff) }
        } catch { self.error(error) }
    }
    func copyHistoryLink(_ ids: [UUID]) {
        guard let id = ids.first, let entry = historyStore?.entry(id), entry.action == .shared,
              let url = entry.remoteURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
    func removeHistory(_ ids: [UUID], deleteFiles: Bool) {
        guard !ids.isEmpty else { return }
        let question = deleteFiles ? "trash" : "hide"
        guard openHistoryQuestions.insert(question).inserted else { return }
        let alert = AppAlert(title: deleteFiles ? "Move archived drawings to Trash?" : "Hide drawings from History?",
            message: deleteFiles ? "The selected History copies and previews will move to Trash. Exported originals and web posts are kept." : "The selected drawings will leave the History list. Their archive files and web posts are kept.",
            buttons: [.init(title: deleteFiles ? "Move to Trash" : "Hide", role: deleteFiles ? .destructive : .normal), .init(title: "Cancel", role: .cancel)])
        presentFromHistory(alert) { [weak self] result in
            guard let self else { return }
            self.openHistoryQuestions.remove(question)
            guard result == .alertFirstButtonReturn else { return }
            do {
                if deleteFiles { try self.archiveStore().trash(Set(ids)) } else { try self.archiveStore().remove(Set(ids), deleteFiles: false) }
                if let id = self.currentArchiveID, ids.contains(id) { self.currentArchiveID = nil }
                self.refreshHistory()
            } catch { self.presentFromHistory(AppAlert(error: error)) }
        }
    }
    func deleteHistoryRemote(_ ids: [UUID]) {
        guard !terminationStarted, !ids.isEmpty else { return }
        guard ids.count == 1, let id = ids.first, let entry = historyStore?.entry(id), let url = entry.remoteURL, let binding = entry.remoteBinding else {
            // The toolbar button is off for these, and says why in its tooltip; an attempt anyway (menu, accessibility action) is answered with
            // the same reason as a sheet on History, never ignored.
            guard openHistoryQuestions.insert("web-refused").inserted else { return }
            let reason = ids.count == 1 ? Self.deleteFromWebRefusal(for: historyStore?.entry(ids[0])) : "Delete from Web removes one post at a time. Select a single entry."
            presentFromHistory(AppAlert(title: "Can\u{2019}t delete this from the web", message: reason)) { [weak self] _ in
                self?.openHistoryQuestions.remove("web-refused")
            }
            return
        }
        guard openHistoryQuestions.insert("web").inserted else { return }
        let alert = AppAlert(title: "Delete this web post?",
            message: "This removes the published image at " + url.absoluteString + ". Its editable History copy will be kept.",
            buttons: [.init(title: "Delete from Web", role: .destructive), .init(title: "Cancel", role: .cancel)])
        presentFromHistory(alert) { [weak self] result in
            guard let self else { return }
            self.openHistoryQuestions.remove("web")
            guard result == .alertFirstButtonReturn, !self.terminationStarted else { return }
            self.postStatusNotice("Deleting web post…")
            self.historyRemoteDeletion.deleteRemote(url: url, binding: binding, presenting: self.historyHost) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success:
                        do { try self.archiveStore().clearRemote(id); self.refreshHistory(); self.postStatusNotice("Web post deleted; History copy kept") }
                        catch { self.presentFromHistory(AppAlert(error: error)) }
                    case .failure(let error): if !self.terminationStarted { self.presentFromHistory(AppAlert(error: error)) }
                    }
                }
            }
        }
    }
    /// Why an entry cannot be deleted from the web: it never went to one, or it went before the app recorded where.
    static func deleteFromWebRefusal(for entry: HistoryStore.Entry?) -> String {
        if entry?.remoteURL == nil { return "This drawing was never uploaded, so there is nothing on the web to delete." }
        return "This upload was made before OpenSnap recorded which destination it went to, so it cannot be removed from here. Delete it with the destination\u{2019}s own tools."
    }
    @objc func showPhotos() {
        photoBrowser.show(relativeTo: window) { [weak self] url in self?.openURL(url) }
    }
    func exportData(format: String, originalSize: Bool, jpegQuality: Double) throws -> Data {
        if ["svg", OpenSnapFile.fileExtension].contains(format.lowercased()) {
            var snapshot = try canvas.snapshotDocumentData(), document = try CanvasView.validatedDocumentData(snapshot)
            if format.lowercased() == OpenSnapFile.fileExtension, originalSize, document.backgroundPNG != nil {
                var raw = try JSONSerialization.jsonObject(with: snapshot) as! [String: Any]
                raw.removeValue(forKey: "renderSize")
                snapshot = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
                document = try CanvasView.validatedDocumentData(snapshot)
            }
            if format.lowercased() == OpenSnapFile.fileExtension { return try OpenSnapFile(document: document, drawingDefaults: drawingDefaults, canvasData: snapshot).encoded() }
            return try SVGExport.encode(document, outputSize: originalSize && document.backgroundPNG != nil ? document.size : document.outputSize)
        }
        guard let encoded = canvas.imageData(format: format, originalSize: originalSize, jpegQuality: jpegQuality) else {
            throw NSError(domain: "OpenSnap", code: 4, userInfo: [NSLocalizedDescriptionKey: "That export format could not be encoded."])
        }
        return encoded
    }
    func exportPanelAccessory() -> ExportAccessory {
        let options = ExportAccessory(format: dragFormat,
            originalSize: UserDefaults.standard.bool(forKey: "ExportOriginalSize"),
            jpegQuality: UserDefaults.standard.object(forKey: "ExportQuality") as? Double ?? 0.7)
        options.fixedJPEGQuality = FormatToggle.jpgQuality
        return options
    }
    func exportPanelData(_ options: ExportAccessory) throws -> Data {
        try exportData(format: options.format, originalSize: options.originalSize, jpegQuality: options.effectiveJPEGQuality)
    }
    @objc func exportFile() {
        let panel = NSSavePanel()
        panel.title = "Export"; panel.nameFieldLabel = "Export As:"; panel.prompt = "Export"
        let options = exportPanelAccessory()
        panel.accessoryView = options.view; panel.allowsOtherFileTypes = false
        let refresh = { [weak self, weak panel, weak options] in
            guard let self, let panel, let options else { return }
            // Commit the filename editor before replacing its extension; otherwise
            // AppKit can restore the editor's old text when the format popup closes.
            if let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor {
                panel.makeFirstResponder(nil)
            }
            panel.allowedContentTypes = [UTType(filenameExtension: options.format) ?? .data]
            let stem = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = (stem.isEmpty ? self.safeName() : stem) + "." + options.format
            let size = SketchDocument.wholePixels(options.originalSize && self.canvas.document.backgroundPNG != nil ? self.canvas.canvasSize : self.canvas.outputSize)
            let data = try? self.exportPanelData(options)
            options.updateByteCount(data?.count, size: size)
        }
        options.onChange = refresh
        panel.nameFieldStringValue = safeName() + "." + options.format
        refresh()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try exportPanelData(options)
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(options.format, forKey: "ExportFormat")
            UserDefaults.standard.set(options.originalSize, forKey: "ExportOriginalSize")
            UserDefaults.standard.set(options.jpegQuality, forKey: "ExportQuality")
            postStatusNotice("Exported " + url.lastPathComponent)
            archive(try historySnapshot(), name: safeName(), action: .exported, destination: url.path, generation: documentGeneration)
        } catch { self.error(error) }
    }
    @objc func pageSetup() {
        let settings = NSPrintInfo.shared.copy() as! NSPrintInfo
        if NSPageLayout().runModal(with: settings) == NSApplication.ModalResponse.OK.rawValue { NSPrintInfo.shared = settings }
        writeLayoutEvidence()
    }
    @objc func printImage() { let view = NSImageView(frame: NSRect(origin: .zero,size: canvas.outputSize)); view.image = canvas.renderedImage(); view.imageScaling = .scaleProportionallyUpOrDown; let p = NSPrintInfo.shared.copy() as! NSPrintInfo; p.horizontalPagination = .fit; p.verticalPagination = .fit; NSPrintOperation(view: view, printInfo: p).run() }
    static let webpostHelp = "Upload image and copy link · Right-click for destinations"
    struct UploadDestination: Equatable { let id: String; let title: String }
    /// Left-click uploads to the default destination; right-click or Control-click shows the destination menu.
    func configureWebpostButton(_ button: NSButton) {
        webpostButton = button
        AppToolTip.setText(Self.webpostHelp, for: button)
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self; MenuTypography.apply(to: menu)
        button.menu = menu
        (button as? OriginalActionButton)?.showMenuOnLeftClick = false
        rebuildUploadMenu(menu)
    }
    @objc func share(_ sender: NSButton) { publishImage() }
    func menuNeedsUpdate(_ menu: NSMenu) { if menu === webpostButton?.menu { rebuildUploadMenu(menu) } }
    func rebuildUploadMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let list = publishing.destinations()
        let destinations = list.destinations.map { UploadDestination(id: $0.id, title: $0.name) }
        uploadDestinationMenuItems(destinations: destinations, defaultID: list.defaultDestination?.id).forEach(menu.addItem)
    }
    /// Destinations (default checkmarked), then Destination Settings… and Share with macOS…. More entries just add rows.
    func uploadDestinationMenuItems(destinations: [UploadDestination], defaultID: String?) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if publishing.isBusy {
            let cancel = NSMenuItem(title: "Cancel Upload", action: #selector(cancelUpload), keyEquivalent: ""); cancel.target = self
            items.append(contentsOf: [cancel, .separator()])
        }
        if destinations.isEmpty {
            let none = NSMenuItem(title: "No destination configured", action: nil, keyEquivalent: ""); none.isEnabled = false
            items.append(none)
        }
        for destination in destinations {
            let item = NSMenuItem(title: destination.title, action: #selector(chooseUploadDestination(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = destination.id
            item.state = destination.id == defaultID ? .on : .off
            items.append(item)
        }
        items.append(.separator())
        let settings = NSMenuItem(title: "Destination Settings…", action: #selector(openDestinationSettings), keyEquivalent: ""); settings.target = self
        let share = NSMenuItem(title: "Share with macOS…", action: #selector(shareFromMenu), keyEquivalent: ""); share.target = self
        items.append(contentsOf: [settings, share])
        return items
    }
    @objc func cancelUpload() {
        guard publishing.isBusy else { return }
        publishing.cancelPublishing { (_: Result<Void, Error>) in }
    }
    @objc func chooseUploadDestination(_ item: NSMenuItem) { if let id = item.representedObject as? String { setDefaultDestination(id) } }
    /// Persists the chosen destination as the default; the next Webpost click uploads to it.
    func setDefaultDestination(_ id: String) {
        do { try publishing.setDefaultDestination(id) } catch { self.error(error) }
        if let menu = webpostButton?.menu { rebuildUploadMenu(menu) }
    }
    @objc func openDestinationSettings() {
        if let sharingSettingsPresenter { sharingSettingsPresenter() } else { publishing.showSettings(relativeTo: window) }
    }
    @objc func shareFromMenu() { showSharePicker(relativeTo: webpostButton) }
    func showSharePicker(relativeTo anchor: NSView?) {
        guard let snapshot = try? historySnapshot() else { return }
        pickerSnapshot = ShareSnapshot(snapshot: snapshot, name: safeName(), generation: documentGeneration)
        let image = canvas.renderedImage()
        if let sharePickerPresenter { sharePickerPresenter(image, anchor); return }
        let picker = NSSharingServicePicker(items: [image]); picker.delegate = self; sharePicker = picker
        guard let anchor = anchor ?? window.contentView else { return }
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        if let snapshot = pickerSnapshot { sharingSnapshots[ObjectIdentifier(sharingService)] = snapshot }
        return self
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { pickerSnapshot = nil }; sharePicker = nil
    }
    func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
        guard let value = sharingSnapshots.removeValue(forKey: ObjectIdentifier(service)) else { return }
        pickerSnapshot = nil
        archive(value.snapshot, name: value.name, action: .shared, destination: service.title, generation: value.generation)
    }
    func sharingService(_ service: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        sharingSnapshots.removeValue(forKey: ObjectIdentifier(service)); pickerSnapshot = nil
        if !terminationStarted { self.error(error) }
    }
    @objc func showPreferences() {
        guard !terminationStarted, !frameCaptureInProgress, window?.attachedSheet == nil,
              preferencesWindow?.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        if settingsController == nil {
            let settings = SettingsWindowController(
                state: { [unowned self] in self.generalPreferences.state }, hotkeys: hotkeys, defaults: .standard,
                destinations: { [unowned self] in self.publishing.destinations() },
                manageDestinations: { [weak self] window in
                    guard let self, !self.terminationStarted else { return }
                    self.publishing.showSettings(relativeTo: window)
                },
                frameAutosaveName: SettingsWindowController.autosaveName)
            settings.onChange = { [weak self] in self?.applyGeneralPreferences($0) }
            settings.onClose = { [weak self] in self?.closePreferences() }
            settingsController = settings
        }
        settingsController?.show()
    }
    func applyGeneralPreferences(_ state: GeneralPreferencesState) {
        guard !terminationStarted else { return }
        let previous = generalPreferences.state
        generalPreferences.apply(state)
        let saved = generalPreferences.state
        canvas.strokeSmoothing = saved.drawingPrecision
        canvas.arrowHeadPreference = UserDefaults.standard.integer(forKey: OriginalArrowGeometry.preferenceKey)
        settingsController?.synchronize(saved)
        if saved.statusMenu != previous.statusMenu { applyPresencePolicy() }
        helpBevel?.enabled = saved.showKeyboardTips
    }
    func closePreferences() {
        guard let panel = preferencesWindow, panel.attachedSheet == nil else { return }
        panel.orderOut(nil)
        if !terminationStarted, window.isVisible { window.makeKeyAndOrderFront(nil) }
    }
    @objc func closeCurrentWindow() {
        closeWindow(NSApp.keyWindow)
    }
    func closeWindow(_ keyWindow: NSWindow?) {
        if let keyWindow, keyWindow === preferencesWindow { closePreferences() }
        else if let keyWindow, keyWindow !== window { keyWindow.performClose(nil) }
        else { toggleVisible() }
    }
    @objc func shortcutSettings() { hotkeys.showSettings(attachedTo: window) }
    @objc func sharingSettings() { publishing.showSettings(relativeTo: window) }
    /// Uploads use the footer toggle's format.
    var uploadEncoding: (format: String, quality: Double, fileExtension: String) {
        return (dragFormat, dragQuality, dragFormat == "jpeg" ? "jpg" : "png")
    }
    func uploadPayload() -> (Data, String)? {
        let encoding = uploadEncoding
        guard let data = canvas.imageData(format: encoding.format, jpegQuality: encoding.quality) else { return nil }
        return (data, encoding.fileExtension)
    }
    @objc func publishImage() {
        guard !terminationStarted else { return }
        if publishing.isBusy { postStatusNotice("An upload is already running…"); return }
        guard publishing.isConfigured else {
            openDestinationSettings(); return
        }
        guard let (data, fileExtension) = uploadPayload(), let snapshot = try? historySnapshot() else { return }
        let name = safeName()
        let fileName = name+"-"+UUID().uuidString.lowercased()+"."+fileExtension
        let binding = plannedBindingCapture(fileName)
        beginUpload(UploadPayload(data: data, fileName: fileName, name: name, snapshot: snapshot, generation: documentGeneration, binding: binding))
    }
    /// Starts one transfer of `payload`. A failed one is kept so Retry can send exactly the same thing again.
    func beginUpload(_ payload: UploadPayload) {
        retryablePayload = payload
        uploadFailureGeneration = payload.generation
        uploadState = .uploading(name: payload.name)
        publishing.publish(data: payload.data, fileName: payload.fileName) { [weak self] result in
            // Publishing guarantees delivery on main, including nested AppKit
            // termination loops. Archive success before its shutdown barrier can
            // acknowledge completion; an extra Task could run after app exit.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.receivePublishing(result)
                if case .success(let url) = result {
                    let retainedBinding = Self.retainedBinding(planned: payload.binding, published: self.publishedBindingCapture(url))
                    self.archive(payload.snapshot, name: payload.name, action: .shared, destination: url.absoluteString, remoteURL: url, remoteBinding: retainedBinding, generation: payload.generation)
                }
            }
        }
    }
    func receivePublishing(_ result: Result<URL, Error>) {
        // The spinner never outlives the transfer, even when the answer arrives during Quit and is otherwise ignored.
        if uploadState.isUploading { uploadState = .idle }
        guard !terminationStarted else { return }
        switch result {
        case .success(let url):
            retryablePayload = nil
            uploadState = .success(url: url, copied: publishing.lastTransferCopiedLink)
        case .failure(let error):
            if (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError {
                retryablePayload = nil; UploadNotice.post("Upload cancelled"); updateStatus()
            } else { uploadState = .failure(message: error.localizedDescription) }
        }
    }
    /// Snap & Upload hotkey: a crosshair capture whose installed result is published.
    /// A cancelled, failed or declined capture never reaches publishImage().
    func snapAndUpload() {
        startCapture("crosshair", afterInstalling: { [weak self] in self?.publishImage() })
    }
    func startCapture(_ mode: String, delay: Double = 0, manualOption: Bool = false, afterInstalling: (() -> Void)? = nil) {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        if capture.isCapturing {
            // Original snapSnap (decompiled.c:22327-22340) cancels the pending timed snap
            // before starting; the cancelled callback is silent (NSUserCancelledError).
            capture.cancelCapture { [weak self] result in
                guard let self, !self.terminationStarted else { return }
                if case .failure(let error) = result { self.updateStatus(); self.error(error); return }
                self.startCapture(mode, delay: delay, manualOption: manualOption, afterInstalling: afterInstalling)
            }
            return
        }
        helpBevel?.clear()
        leaveFrame()
        let generation = documentGeneration
        let includeApp = generalPreferences.includeApp(mode: mode, manualOption: manualOption)
        capture.capture(mode: mode, delay: delay, includeApp: includeApp) { [weak self] result in
            guard let self, self.documentGeneration == generation else { return }
            self.receiveCapture(result, expectedGeneration: generation, afterInstalling: afterInstalling)
        }
    }
    func receiveCapture(_ result: Result<NSImage,Error>, discardAlreadyApproved: Bool = false, expectedGeneration: UUID? = nil, afterInstalling: (() -> Void)? = nil) {
        guard !terminationStarted, expectedGeneration == nil || expectedGeneration == documentGeneration else { return }
        switch result { case .success(let image):
            var proposed = CGRect(origin: .zero, size: image.size)
            guard let pixels = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil), SketchDocument.validSize(NSSize(width: pixels.width, height: pixels.height)) else {
                self.error(NSError(domain: "OpenSnap", code: 5, userInfo: [NSLocalizedDescriptionKey: "This capture is too large or cannot be decoded safely."]))
                return
            }
            // Captures may finish after editing resumes. Recheck pending changes
            // here so timed and web captures cannot silently replace them.
            let install = { [weak self] in
                guard let self, !self.terminationStarted, expectedGeneration == nil || expectedGeneration == self.documentGeneration else { return }
                self.installCapture(image, pixels: pixels, afterInstalling: afterInstalling)
            }
            if discardAlreadyApproved { install() } else { confirmDiscard { allowed in if allowed { install() } } }
        case .failure(let error): if (error as NSError).code != NSUserCancelledError { self.error(error) } }
    }
    private func installCapture(_ image: NSImage, pixels: CGImage, afterInstalling: (() -> Void)?) {
        preferencesWindow?.orderOut(nil)
        followHistory(); currentArchiveID = nil; activeResizeSession?.cancel(); endWindowGesture(cancelled: true); leaveActualSize(); canvas.newBlank(size: NSSize(width: pixels.width, height: pixels.height)); canvas.setBackground(image); documentGeneration = UUID(); drawingDefaults = .init(); canvas.editingUndoManager.removeAllActions(); currentURL = nil; adoptRasterViewport(); nameField.stringValue = "Screenshot"; dirty = true; replaceDragPresentation(); window.makeKeyAndOrderFront(nil); updateStatus()
        Announcer.announce(Announcer.Message.captureSucceeded)
        afterInstalling?()
    }
    @objc func screenSnap() {
        captureCrosshair(manualOption: NSApp.currentEvent?.modifierFlags.contains(.option) == true)
    }
    @objc func snapButtonPressed() {
        if frameMode {
            frameTimedSnap = frameTimedSnap || NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            performFrameSnap(delay: frameTimedSnap ? OriginalCaptureTiming.originalDelay : 0)
        }
        else { screenSnap() }
    }
    @objc func cancelSnapshot() {
        capture.cancelCapture { [weak self] result in
            guard let self, !self.terminationStarted else { return }
            self.updateStatus()
            if case .failure(let error) = result { self.error(error) }
        }
    }
    func captureCrosshair(manualOption: Bool) {
        startCapture("crosshair", manualOption: manualOption)
    }
    @objc func fullscreenSnap() {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        captureFullscreen(manualOption: flags.contains(.option), delay: OriginalCaptureTiming.manualDelay(flags: flags))
    }
    func captureFullscreen(manualOption: Bool, delay: Double = 0) { startCapture("fullscreen", delay: delay, manualOption: manualOption) }
    @objc func windowSnap() { startCapture("window") }
    @objc func frameSnap() {
        enterFrame(keepingAnnotations: false)
    }
    @objc func resnap() {
        enterFrame(keepingAnnotations: true)
    }
    func enterFrame(keepingAnnotations: Bool, manualFlags: NSEvent.ModifierFlags? = nil) {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        // Frame is a see-through window floating over the desktop; a full-screen window owns a Space of its own, so the two exclude each other.
        guard !isFullScreen else { postStatusNotice(MainWindowFrame.exitFullScreenForFrame); return }
        activeResizeSession?.cancel(); endWindowGesture(cancelled: true); leaveActualSize()
        canvas.commitPendingTextEditing()
        if !frameMode {
            frameWindowWasOpaque = window.isOpaque
            frameWindowHadShadow = window.hasShadow
            frameWindowAlpha = window.alphaValue
            frameWindowLevel = window.level
            frameWindowBackground = window.backgroundColor
            frameScrollDrewBackground = canvas.enclosingScrollView?.drawsBackground ?? true
            frameScrollersShown = (canvas.enclosingScrollView?.hasHorizontalScroller ?? true, canvas.enclosingScrollView?.hasVerticalScroller ?? true)
        }
        frameTimedSnap = frameTimedSnap || (manualFlags ?? NSApp.currentEvent?.modifierFlags ?? []).contains(.shift)
        let enteringFrame = !frameMode
        frameMode = true; frameKeepsAnnotations = keepingAnnotations
        if enteringFrame { Announcer.announce(Announcer.Message.frameEntered) }
        window.isOpaque = false; window.backgroundColor = .clear
        window.collectionBehavior.remove(.fullScreenPrimary)
        // Recovered -[PlatformController(snap) setSnapMode:] (decompiled.c:20481): shadow off, screen-saver level, alpha 0x3f4ccccd (0.8f).
        applyFrameWindowValues()
        window.titlebarAppearsTransparent = false
        // A clear window also clears AppKit's titlebar on recent macOS. Keep
        // its adaptive white title readable without filling the canvas hole.
        if frameTitlebarBackdrop == nil,
           let titlebar = window.standardWindowButton(.closeButton)?.superview,
           titlebar.bounds.height > 0, titlebar.bounds.height <= 100 {
            let backdrop = FrameChromeView(frame: titlebar.bounds)
            backdrop.autoresizingMask = [.width, .height]
            titlebar.addSubview(backdrop, positioned: .below, relativeTo: nil)
            frameTitlebarBackdrop = backdrop
        }
        (window.contentView as? FrameChromeView)?.showsCanvasHole = true
        canvas.enclosingScrollView?.drawsBackground = false
        canvas.enclosingScrollView?.hasHorizontalScroller = false; canvas.enclosingScrollView?.hasVerticalScroller = false
        canvas.framePreview = true
        snapButton.cancelOperation(nil)
        snapButton.title = "Snap Frame"
        (snapButton as? OriginalActionButton)?.alternateAction = nil
        AppToolTip.setText("Capture the area inside the frame; hold Shift for a six-second timer", for: snapButton)
        cancelFrameButton.isHidden = false
        setModernFrameMode(true)
        updateViewportChrome()
        let fullStatus = keepingAnnotations ? "Frame preview · Snap Frame replaces the picture and keeps your drawing" : "Frame: position the window, then Snap"
        status.stringValue = frameStatusHint
        AppToolTip.setText(fullStatus, for: status, mirrorsToAccessibility: false)
        status.spokenValue = fullStatus; status.setAccessibilityHelp(fullStatus)
    }
    @objc func cancelFrame() {
        guard !frameCaptureInProgress else { return }
        leaveFrame()
    }
    func leaveFrame() {
        guard frameMode else { return }
        Announcer.announce(Announcer.Message.frameLeft)
        frameMode = false; frameKeepsAnnotations = false; frameTimedSnap = false
        frameTitlebarBackdrop?.removeFromSuperview(); frameTitlebarBackdrop = nil
        canvas.framePreview = false
        (window.contentView as? FrameChromeView)?.showsCanvasHole = false
        window.isOpaque = frameWindowWasOpaque
        window.hasShadow = frameWindowHadShadow
        window.alphaValue = frameWindowAlpha
        window.level = frameWindowLevel
        window.backgroundColor = frameWindowBackground
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.titlebarAppearsTransparent = true
        canvas.enclosingScrollView?.drawsBackground = frameScrollDrewBackground
        canvas.enclosingScrollView?.hasHorizontalScroller = frameScrollersShown.horizontal; canvas.enclosingScrollView?.hasVerticalScroller = frameScrollersShown.vertical
        snapButton.title = "Snap"
        (snapButton as? OriginalActionButton)?.alternateAction = #selector(fullscreenSnap)
        AppToolTip.setText("Drag an area or click a window; right-click or Control-click for Fullscreen", for: snapButton)
        cancelFrameButton.isHidden = true
        setModernFrameMode(false)
        updateStatus()
    }
    /// The visible area of the canvas view, in global bottom-left coordinates. For a canvas at least as large as the
    /// viewport that is the part of it on screen; for a smaller, centred canvas it is still the whole viewport (the margin
    /// around the canvas included), because that is the hole the user sees and positions. Always inside the Frame hole.
    var frameViewportScreenRect: NSRect { window.convertToScreen(canvas.convert(canvas.visibleRect, to: nil)) }
    func performFrameSnap(delay: Double = 0) {
        guard !terminationStarted, frameMode, !frameCaptureInProgress else { return }
        if frameKeepsAnnotations, !canvasIsFullyVisible {
            postStatusNotice("Re-Snap needs the whole drawing visible. Reduce zoom or enlarge the window, then try again.", duration: 12)
            return
        }
        let global = frameViewportScreenRect
        let top = NSScreen.screens.first?.frame.maxY ?? global.maxY
        capture.frameRect = NSRect(x: global.minX, y: top-global.maxY, width: global.width, height: global.height)
        activeFrameScreenSize = capture.frameRect?.integral.size
        let keepingAnnotations = frameKeepsAnnotations
        let generation = documentGeneration, size = canvas.canvasSize, visibleRect = canvas.visibleRect, zoom = canvas.zoom
        frameCaptureInProgress = true
        capture.capture(mode: "frame", delay: delay) { [weak self] result in
            guard let self else { return }
            self.frameCaptureInProgress = false
            guard self.documentGeneration == generation else { return }
            if keepingAnnotations, (self.canvas.canvasSize != size || self.canvas.visibleRect != visibleRect || self.canvas.zoom != zoom) {
                self.postStatusNotice("The drawing view changed during Re-Snap. Position the frame and try again.", duration: 12)
                return
            }
            self.receiveFrameCapture(result, keepingAnnotations: keepingAnnotations, expectedGeneration: generation)
        }
    }
    var canvasIsFullyVisible: Bool {
        let visible = canvas.visibleRect, full = canvas.bounds
        // Allow only subpixel layout rounding, never a clipped document strip.
        return visible.minX <= full.minX + 0.01 && visible.minY <= full.minY + 0.01 &&
            visible.maxX >= full.maxX - 0.01 && visible.maxY >= full.maxY - 0.01
    }
    func receiveFrameCapture(_ result: Result<NSImage, Error>, keepingAnnotations: Bool, expectedGeneration: UUID? = nil) {
        frameCaptureInProgress = false
        guard !terminationStarted, expectedGeneration == nil || expectedGeneration == documentGeneration else { return }
        switch result {
        case .success(let image):
            var proposed = CGRect(origin: .zero, size: image.size)
            guard let pixels = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil), SketchDocument.validSize(NSSize(width: pixels.width, height: pixels.height)) else {
                error(NSError(domain: "OpenSnap", code: 5, userInfo: [NSLocalizedDescriptionKey: "This capture is too large or cannot be decoded safely."]))
                return
            }
            if keepingAnnotations {
                guard canvas.replaceSnapPreservingAnnotations(image) else {
                    error(NSError(domain: "OpenSnap", code: 6, userInfo: [NSLocalizedDescriptionKey: "The frame snapshot could not be decoded safely."]))
                    return
                }
                leaveFrame(); updateStatus()
                Announcer.announce(Announcer.Message.captureSucceeded)
            } else {
                confirmDiscard { [weak self] allowed in
                    guard let self, allowed, !self.terminationStarted, expectedGeneration == nil || expectedGeneration == self.documentGeneration else { return }
                    self.leaveFrame(); self.receiveCapture(.success(image), discardAlreadyApproved: true, expectedGeneration: expectedGeneration)
                    if let frameSize = self.activeFrameScreenSize {
                        // Retina capture pixels must not enlarge the next frame.
                        let size = self.canvas.canvasSize
                        self.setCanvasDisplayZoom(min(frameSize.width/size.width, frameSize.height/size.height), label: "Frame")
                    }
                }
            }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { self.error(error) }
            // A cancelled picker keeps the frame ready for another attempt.
        }
    }
    @objc func timedSnap() {
        let option = NSApp.currentEvent?.modifierFlags.contains(.option) == true
        prompt("Timed Snapshot", text: "Delay in seconds", value: "6") { [weak self] answer in
            if let answer, let d = Double(answer), d >= 0, d <= 120 { self?.startCapture("crosshair", delay: d, manualOption: option) }
        }
    }
    @objc func webSnap() {
        guard !terminationStarted, !frameCaptureInProgress else { return }
        prompt("Snap from Link", text: "Web address", value: "https://") { [weak self] answer in
            guard let self, !self.terminationStarted, let answer, let url = URL(string: answer), ["https","http"].contains(url.scheme?.lowercased() ?? "") else { return }
            let generation = self.documentGeneration
            self.capture.captureURL(url) { [weak self] result in
                guard let self, self.documentGeneration == generation else { return }
                self.receiveCapture(result, expectedGeneration: generation)
            }
        }
    }
    /// Modern has no file-name field, so the document name lives in the window title and changes here.
    @objc func renameDocument() {
        guard !terminationStarted, !frameCaptureInProgress, window.attachedSheet == nil else { return }
        prompt("Rename", text: "Document name", value: nameField.stringValue) { [weak self] name in
            if let name { self?.applyDocumentName(name) }
        }
    }
    func applyDocumentName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { nameField.stringValue = trimmed }
    }
    /// A one-line question in an app-owned sheet. `completion` gets the text on OK and nil on Cancel.
    func prompt(_ title: String, text: String, value: String, completion: @escaping (String?) -> Void) {
        let field = NSTextField(string: value)
        field.font = DesignTokens.Typography.font(.body)
        field.frame = NSRect(x: 0, y: 0, width: AppAlert.width - 2 * DesignTokens.Space.s5, height: DesignTokens.Size.field)
        field.setAccessibilityLabel(text)
        let alert = AppAlert(title: title, message: text, buttons: [.init(title: "OK"), .init(title: "Cancel", role: .cancel)], accessoryView: field)
        present(alert) { result in completion(result == .alertFirstButtonReturn ? field.stringValue : nil) }
    }
    @objc func chooseFont() {
        guard !terminationStarted else { return }
        if let panel = fontPanel, panel.isVisible { panel.orderOut(nil); fontPanelRefreshTimer?.invalidate(); return }
        let panel = NSFontManager.shared.fontPanel(true) ?? NSFontPanel.shared
        fontPanel = panel; panel.delegate = self; panel.isReleasedWhenClosed = false
        let form = textStyleForm ?? TextStyleForm(outlined: canvas.outlined, shadowed: canvas.shadowed)
        textStyleForm = form; panel.accessoryView = form
        form.onOutlineChange = { [weak self] value in
            guard let self, !self.terminationStarted else { return }
            self.canvas.outlined = value; self.canvas.applyTextEffectsToSelection(outline: value); self.syncFontPanelSelection()
        }
        form.onShadowChange = { [weak self] value in
            guard let self, !self.terminationStarted else { return }
            self.canvas.shadowed = value; self.canvas.applyTextEffectsToSelection(shadow: value); self.syncFontPanelSelection()
        }
        form.onDefaultRequested = { [weak self] in self?.defaultTextStyle() }
        let manager = NSFontManager.shared; manager.target = self; manager.action = #selector(changeFont(_:))
        syncFontPanelSelection()
        panel.orderFront(nil)
        // AppKit restores the shared panel's saved small frame when first shown.
        // Size the loaded panel, bounded to the usable display (the accessory scrolls
        // when constrained), then keep it centered on this screen.
        let content = NSRect(x: 0, y: 0, width: 940, height: 720)
        if let main = window, let usable = fontPanelVisibleFrameOverride?() ?? main.screen?.visibleFrame {
            panel.setFrame(TextStyleForm.fontPanelFrame(size: panel.frameRect(forContentRect: content).size,
                                                        visible: usable.insetBy(dx: 12, dy: 12), anchor: main.frame), display: true)
        } else { panel.setContentSize(content.size) }
        fontPanelOpeningLayoutApplied = TextStyleForm.prepareFontPanelLayout(panel)
        TextStyleForm.prepareFontPanel(panel)
        if window != nil { writeLayoutEvidence() }
        fontPanelRefreshTimer?.invalidate()
        fontPanelRecordedTypography = false
        fontPanelRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshFontPanel() }
        }
    }
    func refreshFontPanel() {
        guard let panel = fontPanel, panel.isVisible else { fontPanelRefreshTimer?.invalidate(); return }
        // The modern shared panel creates its split views after Show. Retry the
        // opening layout until those native views are loaded, then never again for
        // this presentation: later refreshes must not fight a dragged divider.
        if !fontPanelOpeningLayoutApplied { fontPanelOpeningLayoutApplied = TextStyleForm.prepareFontPanelLayout(panel) }
        TextStyleForm.prepareFontPanel(panel)
        if window != nil, !fontPanelRecordedTypography {
            writeLayoutEvidence(); fontPanelRecordedTypography = true
        }
    }
    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask { NSFontPanel.ModeMask(rawValue: 7) }
    func syncFontPanelSelection() {
        guard fontPanel != nil, !applyingFontChange else { return }
        let selected = canvas.selectedTextElements
        let first = selected.first
        let source = NSFont(name: first?.fontName ?? canvas.fontName, size: first?.fontSize ?? canvas.fontSize) ?? .boldSystemFont(ofSize: 24) // token-exempt: annotation text fallback face (document content)
        // Original displayFontScale is output/logical height; editor zoom is a
        // view transform and must not change the point size in the Fonts panel.
        let scale = canvas.outputSize.height / canvas.canvasSize.height
        let displayed = NSFontManager.shared.convert(source, toSize: source.pointSize * scale)
        NSFontManager.shared.setSelectedFont(displayed, isMultiple: selected.count > 1)
        func uniform(_ values: [Bool], fallback: Bool) -> Bool? {
            guard let value = values.first else { return fallback }
            return values.allSatisfy { $0 == value } ? value : nil
        }
        textStyleForm?.setChoices(outlined: uniform(selected.map(\.outlined), fallback: canvas.outlined),
                                  shadowed: uniform(selected.map(\.shadowed), fallback: canvas.shadowed))
    }
    func changeFont(_ sender: NSFontManager?) {
        guard !terminationStarted, let panel = fontPanel, let form = textStyleForm else { return }
        let scale = canvas.outputSize.height / canvas.canvasSize.height
        let manager = NSFontManager.shared
        let convert: (NSFont) -> NSFont? = { source in
            let displayed = manager.convert(source, toSize: source.pointSize * scale)
            let changed = panel.convert(displayed)
            return manager.convert(changed, toSize: changed.pointSize / scale)
        }
        let first = canvas.selectedTextElements.first
        let source = NSFont(name: first?.fontName ?? canvas.fontName, size: first?.fontSize ?? canvas.fontSize) ?? .boldSystemFont(ofSize: 24) // token-exempt: annotation text fallback face (document content)
        guard let future = convert(source), future.pointSize.isFinite, future.pointSize > 0, future.pointSize <= 4096,
              future.pointSize >= 18 || future.pointSize == source.pointSize else { return }
        applyingFontChange = true
        let valid = canvas.convertSelectedTextFonts(convert, outline: form.outlineChoice, shadow: form.shadowChoice)
        if valid {
            canvas.fontName = future.fontName; canvas.fontSize = future.pointSize
            if let value = form.outlineChoice { canvas.outlined = value }
            if let value = form.shadowChoice { canvas.shadowed = value }
        }
        applyingFontChange = false; syncFontPanelSelection(); fontPanelRecordedTypography = false
    }
    func closeFontPanel() {
        fontPanelRefreshTimer?.invalidate(); fontPanelRefreshTimer = nil
        fontPanel?.orderOut(nil); fontPanel?.delegate = nil; fontPanel?.accessoryView = nil
        if NSFontManager.shared.target === self { NSFontManager.shared.target = nil }
        fontPanel = nil; textStyleForm = nil; fontPanelOpeningLayoutApplied = false
    }
    @objc func defaultTextStyle() { guard !terminationStarted else { return }; canvas.restoreDefaultTextStyle(); syncFontPanelSelection() }
    @objc func toggleTextShadow() {
        let selected = canvas.selectedTextElements.first
        canvas.shadowed = !(selected?.shadowed ?? canvas.shadowed)
        canvas.applyTextEffectsToSelection(shadow: canvas.shadowed)
    }
    @objc func toggleOutline() {
        let selected = canvas.selectedTextElements.first
        canvas.outlined = !(selected?.outlined ?? canvas.outlined)
        canvas.applyTextEffectsToSelection(outline: canvas.outlined)
    }
    @objc func resize() {
        guard let session = makeResizeSession() else { return }
        ResizePanel(session: session).show(attachedTo: window)
    }
    @objc func normalSize() { canvas.setSnapToNormalSize(); updateStatus() }
    @objc func trimSnap() { canvas.trimSnapAtCurrentEdges(); updateStatus() }
    var activeTextEditor: NSTextView? {
        (window?.attachedSheet ?? NSApp.keyWindow ?? window)?.firstResponder as? NSTextView
    }
    var activeUndoManager: UndoManager { activeTextEditor?.undoManager ?? canvas.editingUndoManager }
    @objc func undo() {
        if let editor = activeTextEditor { stepHistory(editor.undoManager, redo: false) { editor.undoManager?.undo() }; return }
        endWindowGesture(cancelled: true)
        stepHistory(canvas.editingUndoManager, redo: false) { canvas.undo() }
    }
    @objc func redo() {
        if let editor = activeTextEditor { stepHistory(editor.undoManager, redo: true) { editor.undoManager?.redo() }; return }
        endWindowGesture(cancelled: true)
        stepHistory(canvas.editingUndoManager, redo: true) { canvas.redo() }
    }
    /// Runs one Undo or Redo and tells VoiceOver what it did, by the action's name ("Undid Draw"); nothing is said when there was nothing to step.
    private func stepHistory(_ manager: UndoManager?, redo: Bool, _ step: () -> Void) {
        let possible = redo ? manager?.canRedo == true : manager?.canUndo == true
        let name = (redo ? manager?.redoActionName : manager?.undoActionName) ?? ""
        step()
        guard possible else { return }
        Announcer.announce(redo ? Announcer.Message.redone(name) : Announcer.Message.undone(name))
    }
    @objc func cut() { if let editor = activeTextEditor { editor.cut(nil) } else { canvas.copySelection(); canvas.deleteSelection() } }
    @objc func copyArtwork() { if let editor = activeTextEditor { editor.copy(nil) } else { canvas.copySelection() } }
    @objc func copyImage() { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([canvas.renderedImage()]) }
    @objc func paste() { if let editor = activeTextEditor { editor.paste(nil) } else { canvas.paste() } }
    @objc func selectAll() { if let editor = activeTextEditor { editor.selectAll(nil) } else { canvas.selectAll() } }
    @objc func deleteSelection() { if let editor = activeTextEditor { editor.delete(nil) } else { canvas.deleteSelection() } }
    @objc func duplicate() { canvas.duplicateSelection() }; @objc func clear() { canvas.clearAnnotations() }; @objc func crop() { canvas.cropSelection() }
    @objc func wipe() { leaveFrame(); canvas.wipe() }
    @objc func wipeSnap() { leaveFrame(); canvas.wipeSnap() }
    @objc func rotateCW() { canvas.rotate(clockwise: true) }; @objc func rotateCCW() { canvas.rotate(clockwise: false) }
    @objc func flipH() { canvas.flip(horizontal: true) }; @objc func flipV() { canvas.flip(horizontal: false) }
    @objc func transparent() { canvas.setBackgroundColor(.clear) }; @objc func white() { canvas.setBackgroundColor(.white) }; @objc func flatten() { canvas.flatten() }; @objc func addShadow() { canvas.addShadow(); updateStatus() }
    @objc func front() { canvas.bringSelectionToFront() }; @objc func back() { canvas.sendSelectionToBack() }; @objc func group() { canvas.groupSelection() }; @objc func ungroup() { canvas.ungroupSelection() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() {
        let panel = aboutWindow ?? AboutWindow(icon: NSApp.applicationIconImage, info: Bundle.main.infoDictionary)
        aboutWindow = panel
        if let content = panel.contentView { AppToolTip.install(on: content) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func runSmokeTest() {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OPENSNAP_EVIDENCE_DIR"] ?? NSTemporaryDirectory())
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let snapshot = try canvas.snapshotDocumentData()
            let expected = try CanvasView.validatedDocumentData(snapshot)
            let nativeURL = dir.appendingPathComponent("smoke." + OpenSnapFile.fileExtension)
            try OpenSnapFile(document: expected, drawingDefaults: drawingDefaults, canvasData: snapshot).write(to: nativeURL)
            let reopened = try OpenSnapFile.read(nativeURL)
            guard reopened.document == expected, reopened.drawingDefaults == drawingDefaults else { throw NSError(domain: "Smoke", code: 2) }
            try canvas.loadDocument(data: reopened.canvasData)
            guard let png = canvas.imageData(format: "png"), !png.isEmpty else { throw NSError(domain: "Smoke", code: 1) }
            try png.write(to: dir.appendingPathComponent("smoke.png"))
            try JSONSerialization.data(withJSONObject: appearanceEvidence(), options: [.sortedKeys]).write(to: dir.appendingPathComponent("smoke-appearance.json"))
            try Data("native startup, .opensnap editable save/load, PNG export succeeded\n".utf8).write(to: dir.appendingPathComponent("smoke-result.txt"))
            dirty = false; NSApp.terminate(nil)
        } catch {
            try? Data("FAILED: \(error)\n".utf8).write(to: dir.appendingPathComponent("smoke-result.txt"))
            dirty = false; NSApp.terminate(nil)
        }
    }
    func writeLayoutEvidence() {
        let folder = ProcessInfo.processInfo.environment["OPENSNAP_EVIDENCE_DIR"] ?? support.path
        window.contentView?.layoutSubtreeIfNeeded()
        let rect = window.convertToScreen(canvas.convert(canvas.visibleRect, to: nil))
        let top = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        var evidence: [String: Any] = ["windowFrame": NSStringFromRect(window.frame), "canvasScreenRect": NSStringFromRect(rect), "canvasInputTopLeft": [rect.minX,top-rect.maxY], "screenFrame": NSStringFromRect(NSScreen.screens.first?.frame ?? .zero), "nativeBackingScale":window.backingScaleFactor, "nameFontSize":nameField.font?.pointSize ?? 0,"statusFontSize":status.font?.pointSize ?? 0]
        evidence["shell"] = ["visible": window.isVisible, "miniaturized": window.isMiniaturized,
                             "statusMenu": UserDefaults.standard.integer(forKey: "statusMenu"), "menuIconInstalled": statusItem != nil]
        evidence["dragThumbnail"] = ["present": dragThumbnailWindow != nil,
                                     "frame": NSStringFromRect(dragThumbnailWindow?.frame ?? .zero),
                                     "clickToExpand": (dragThumbnailWindow?.contentView as? DragThumbnailView)?.clickToExpand ?? false,
                                     "dragging": activeDragID != nil]
        evidence["windowZoom"] = ["active": windowZoom != nil, "frame": windowZoom?.lastRenderedFrame ?? 0,
                                  "frames": windowZoom?.frameCount ?? 0,
                                  "restoring": windowZoom?.direction == .restore]
        evidence["visibilityZoomOrigin"] = NSStringFromRect(visibilityZoomOrigin ?? .zero)
        evidence["appearance"] = ["modernChrome": modernChrome != nil]
        evidence["toolButtons"] = SketchTool.allCases.compactMap { tool -> [String: Any]? in
            guard let button = toolButtons[tool] else { return nil }
            return ["tool": tool.rawValue, "fontSize": button.font?.pointSize ?? 0,
                    "frame": NSStringFromRect(button.frame), "selected": button.state == .on]
        }
        if let content = window.contentView {
            var controls: [[String: Any]] = []
            func inspect(_ view: NSView) {
                guard view !== canvas else { return }
                if let control = view as? NSControl, control is NSButton || control is NSTextField || control is BezelSizeSlider {
                    let rect = control.convert(control.bounds, to: content)
                    var clipped = rect.intersection(content.bounds)
                    var ancestor = control.superview
                    while let parent = ancestor {
                        if parent is NSClipView { clipped = clipped.intersection(parent.convert(parent.bounds, to: content)) }
                        ancestor = parent.superview
                    }
                    controls.append(["label": control.accessibilityLabel() ?? (control as? NSButton)?.title ?? (control as? NSTextField)?.stringValue ?? "",
                                     "fontSize": control.font?.pointSize ?? 0, "frame": NSStringFromRect(rect),
                                     "visibleFrame": NSStringFromRect(clipped), "hidden": control.isHiddenOrHasHiddenAncestor,
                                     "parentIsButton": control.superview is NSButton])
                }
                for child in view.subviews { inspect(child) }
            }
            inspect(content)
            evidence["bezelControls"] = controls
            let chosen = SketchColor(canvas.strokeColor), custom = SketchColor(OriginalDrawingControls.drawingColor(from: customDrawingColor) ?? .black)
            evidence["drawingControls"] = ["size": widthControl.doubleValue, "fontSize": canvas.fontSize,
                                           "colorRGBA": [chosen.red,chosen.green,chosen.blue,chosen.alpha],
                                           "customRGBA": [custom.red,custom.green,custom.blue,custom.alpha],
                                           "popoverShown": colorPopover?.isShown ?? false, "sizeUndoGrouping": sizeUndoGrouping,
                                           "hoverOpened": colorOpenedByHover, "controlHovered": colorControlHovered, "paletteHovered": colorPaletteHovered]
            evidence["bezelLayout"] = ["contentSize": NSStringFromSize(content.bounds.size), "minimumWindowSize": NSStringFromSize(window.minSize)]
            if let header = (modernChrome ?? content).subviews.first(where: { $0.identifier?.rawValue == "OpenSnapHeader" }),
               let brand = header.subviews.first(where: { $0.identifier?.rawValue == "OpenSnapBrand" }) {
                let frame = brand.convert(brand.bounds, to: content)
                evidence["bezelHeader"] = ["brandFrame": NSStringFromRect(frame), "windowCenterX": content.bounds.midX,
                                           "brandCenterOffset": frame.midX - content.bounds.midX,
                                           "commandFrames": header.subviews.filter { $0 !== brand }.map { NSStringFromRect($0.convert($0.bounds, to: content)) }]
            }
        }
        let printInfo = NSPrintInfo.shared
        evidence["printInfo"] = ["paperSize": NSStringFromSize(printInfo.paperSize),
                                "orientation": printInfo.orientation == .portrait ? "portrait" : "landscape",
                                "margins": [printInfo.leftMargin, printInfo.rightMargin, printInfo.topMargin, printInfo.bottomMargin]]
        if let panel = fontPanel {
            evidence["fontPanel"] = ["frame": NSStringFromRect(panel.frame), "visible": panel.isVisible, "windowNumber": panel.windowNumber,
                                     "key": panel.isKeyWindow, "modeMask": validModesForFontPanel(panel).rawValue,
                                     "typography": TextStyleForm.fontPanelTypographyEvidence(panel),
                                     "layout": TextStyleForm.fontPanelLayoutEvidence(panel)]
        }
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: .prettyPrinted) { try? data.write(to: URL(fileURLWithPath:folder).appendingPathComponent("layout.json"), options:.atomic) }
    }
}

@main
@MainActor
enum OpenSnapMain {
    static func main() {
        OpenSnapMigration.runAtLaunch()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
