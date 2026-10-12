// G10 and OSN-060: the accessibility walker (tests/AccessibilityAudit.swift) must (a) catch a seeded violation of every kind it claims
// to judge, (b) find zero violations on every real surface whose sources compile in isolation, and (c) the sheets outside the editor
// must answer Return and Escape through performKeyEquivalent, with the focus ring and key-view rules of their custom views intact.
// Windows are built, never ordered on screen. VoiceOver speech itself is a manual pass; this proves structure, not what is spoken.
// xcrun swiftc -swift-version 5 -target arm64-apple-macosx26.0 -D ACCESSIBILITY_AUDIT_TESTS \
//   Sources/DesignTokens.swift Sources/AboutWindow.swift Sources/HistoryBrowser.swift Sources/ResizePresets.swift Sources/ResizePanel.swift \
//   Sources/Publishing.swift Sources/PublishingS3.swift Sources/PublishingDestinations.swift Sources/PublishingDestinationsView.swift \
//   Sources/SVGPath.swift Sources/StrokeFitting.swift Sources/GeneralPreferencesState.swift Sources/TextStyleForm.swift Sources/ExportAccessory.swift \
//   Sources/SettingsWindow.swift Sources/GlobalHotkeys.swift Sources/AppToolTip.swift Sources/DisplayOptions.swift Sources/OriginalCaptureFlash.swift \
//   Sources/PhotoBrowser.swift Sources/AppAlert.swift Sources/FontAwesomeIcons.swift Sources/ChromeIcons.swift Sources/FontAwesomeFree.swift \
//   tests/TestDefaults.swift tests/AccessibilityTreeWalk.swift tests/SpokenScript.swift tests/UserStringWalk.swift tests/AccessibilityAudit.swift tests/AccessibilityAuditTests.swift -o /tmp/opensnap-accessibility-audit-tests
#if ACCESSIBILITY_AUDIT_TESTS
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A shortcut backend that registers nothing, so the Settings window and the shortcut sheet can be built without touching the system.
@MainActor
private final class InertHotkeyBackend: GlobalHotkeyBackend {
    var registeredIDs: Set<UInt32> { [] }
    func installHandler(onEvent: @escaping @MainActor @Sendable (UInt32) -> Void) throws {}
    func systemReservedBindings() throws -> Set<GlobalHotkeyBinding> { [] }
    func register(_ binding: GlobalHotkeyBinding, id: UInt32) throws {}
    func unregister(id: UInt32) throws {}
    func shutdown() throws {}
}

/// A control that does everything right except report a role.
@MainActor
private final class RolelessControl: NSControl {
    override var acceptsFirstResponder: Bool { true }
}

/// A control that is fully described and focusable but has chosen not to be an accessibility element: VoiceOver cannot land on it.
@MainActor
private final class MuteControl: NSControl {
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { false }
}

/// A focusable picture (as the drawing canvas is) that names itself; `summary` is what it says it holds, if anything.
@MainActor
private final class FocusablePicture: NSView {
    var summary: String?
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityValue() -> Any? { summary }
}

/// A slider-shaped control that names itself and takes focus but never says where it stands.
@MainActor
private final class ValuelessSlider: NSControl {
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityValue() -> Any? { nil }
}

@main
@MainActor
private enum AccessibilityAuditTests {
    typealias Audit = AccessibilityAudit
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        checks += 1
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Audit.recording = false  // seeded trees are not surfaces: no script, no findings dump
        seededViolations()
        trackedKinds()
        cleanTreeIsClean()
        menus()
        spokenScriptRendering()
        UserStrings.reset()  // the seeded violations above name the retired product on purpose
        Audit.recording = true
        realSurfaces()
        Audit.recording = false
        sheetKeyboard()
        customViewFocus()
        labelsAndStatus()
        userStringsAreClean()
        print("AccessibilityAuditTests: \(checks) checks passed (windows never ordered on screen)")
    }

    /// G3 (dynamic): nothing the real surfaces above can show names the retired product, and the walk can see a seeded violation of every kind.
    private static func userStringsAreClean() {
        expect(UserStrings.entries.count > 200, "the string walk visited the real surfaces (\(UserStrings.entries.count) distinct strings)")
        expect(UserStrings.hits.isEmpty, "no user-visible string names the retired product: \(UserStrings.hits.map { "\($0.surface) \($0.kind) '\($0.text)'" })")
        expect(UserStrings.writeDump(name: "accessibility-audit-tests") || ProcessInfo.processInfo.environment["OPENSNAP_USER_STRINGS_DIR"] == nil, "the string dump was written")
    }

    // MARK: Builders

    private static let plain = NSImage(size: NSSize(width: 8, height: 8))
    private static func described(_ text: String) -> NSImage { let image = NSImage(size: NSSize(width: 8, height: 8)); image.accessibilityDescription = text; return image }

    private static func host(_ views: NSView...) -> NSView {
        let stack = NSStackView(views: views); stack.orientation = .vertical
        stack.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        return stack
    }

    private static func button(_ title: String, label: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        if let label { button.setAccessibilityLabel(label) }
        return button
    }

    private static func iconButton(_ image: NSImage = plain, label: String? = nil) -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.image = image; button.imagePosition = .imageOnly
        if let label { button.setAccessibilityLabel(label) }
        return button
    }

    private static func found(_ view: NSView, allowing: [String: String] = [:]) -> Audit.Report { Audit.audit(view, surface: "seed", allowedDuplicates: allowing) }

    private static func kinds(_ report: Audit.Report) -> [Audit.Kind] { report.violations.map(\.kind) }

    // MARK: A. The walker can fail

    private static func seededViolations() {
        // Each case: a tree with exactly one offending element and the one kind the walker must file it under.
        let cases: [(String, NSView, Audit.Kind)] = [
            ("icon-only button with no description", host(iconButton()), .missingLabel),
            ("popup with no label", host(NSPopUpButton(frame: .zero, pullsDown: false).with { $0.addItems(withTitles: ["A", "B"]) }), .missingLabel),
            ("editable text field with no label", host(NSTextField(string: "name").with { $0.isEditable = true }), .missingLabel),
            ("slider with no label", host(NSSlider()), .missingLabel),
            ("checkbox with an empty title and no label", host(NSButton(checkboxWithTitle: "", target: nil, action: nil)), .missingLabel),
            ("control that reports no role", host(RolelessControl().with { $0.setAccessibilityLabel("Roleless") }), .missingRole),
            ("segment with neither text nor description", host(NSSegmentedControl(images: [described("Left"), plain], trackingMode: .selectOne, target: nil, action: nil).with { $0.setAccessibilityLabel("Align") }), .unlabelledSegment),
            ("a label that names the retired product", host(button("Upload", label: "Upload to " + Audit.retiredName)), .retiredName),
            ("a retired name in lower case in the help text", host(button("Upload").with { $0.setAccessibilityHelp("sends it to " + Audit.retiredName.lowercased()) }), .retiredName),
            ("a control that refuses focus", host(button("Save").with { $0.refusesFirstResponder = true }), .notKeyboardReachable),
            ("an image that conveys meaning and says nothing", host(NSImageView(image: plain)), .undescribedImage),
        ]
        for (name, view, kind) in cases {
            let report = found(view)
            expect(kinds(report) == [kind], "\(name): expected exactly [\(kind)], got \(kinds(report)): \(report.description)")
            expect(report.controls >= 1, "\(name): the walker judged the element it was shown")
        }

        // Two controls on screen with one label: both are named; the allow-list (with a reason) silences exactly that label.
        let pair = host(button("One", label: "Same"), button("Two", label: "same"))
        expect(kinds(found(pair)) == [.duplicateLabel, .duplicateLabel], "duplicate labels are compared without case")
        // The allow-list silences the window-wide check only; two of them under one AX parent are still found.
        expect(kinds(found(pair, allowing: ["Same": "the toolbar and its overflow menu are one command"])) == [.duplicateInGroup, .duplicateInGroup], "an allow-listed duplicate under one parent is a duplicateInGroup, not a duplicateLabel")
        func group(_ name: String, _ child: NSView) -> NSView {
            let group = NSStackView(views: [child]); group.setAccessibilityElement(true); group.setAccessibilityRole(.group); group.setAccessibilityLabel(name); return group
        }
        let apart = host(group("First", button("One", label: "Same")), group("Second", button("Two", label: "same")))
        expect(found(apart, allowing: ["Same": "the toolbar and its overflow menu are one command"]).violations.isEmpty, "an allow-listed duplicate under two parents passes")
        expect(kinds(found(pair, allowing: ["Other": "unrelated"])) == [.duplicateLabel, .duplicateLabel], "an allow-list entry for another label does not help")
        // A control and a static caption that read the same are not a duplicate: only controls compete.
        expect(found(host(button("Name"), NSTextField(labelWithString: "Name"))).violations.isEmpty, "a caption is not a control")

        // Fixes pass: a label, a described image, a decorative image, a composite owner, and a labelled field.
        expect(found(host(iconButton(label: "Share"))).violations.isEmpty, "an explicit label satisfies an icon-only button")
        expect(found(host(iconButton(described("Share")))).violations.isEmpty, "an image description satisfies an icon-only button")
        expect(found(host(NSImageView(image: described("Preview of Shot 1")))).violations.isEmpty, "an image with a description passes")
        expect(found(host(NSImageView(image: plain).with { $0.setAccessibilityIdentifier("decorative.logo") })).violations.isEmpty, "a decorative image passes")
        let pill = NSView(); pill.setAccessibilityLabel("Default destination"); pill.addSubview(NSImageView(image: plain))
        expect(found(host(pill)).violations.isEmpty, "an image inside a labelled pill belongs to the pill's label")
        let bareRow = NSView(); bareRow.addSubview(NSImageView(image: plain))
        expect(kinds(found(host(bareRow))) == [.undescribedImage], "an image inside an unlabelled container is still found")
        expect(found(host(RolelessControl().with { $0.setAccessibilityLabel("Fine"); $0.setAccessibilityRole(.button) })).violations.isEmpty, "a custom control that sets a role passes")
        let titled = NSTextField(labelWithString: "Width"); let field = NSTextField(string: "10"); field.isEditable = true
        field.setAccessibilityTitleUIElement(titled)
        expect(found(host(titled, field)).violations.isEmpty, "a text field titled by its caption passes")

        // A composite widget (a custom focusable parent) owns the keys for the controls inside it.
        final class KeyOwner: NSView { override var acceptsFirstResponder: Bool { true } }
        let owner = KeyOwner(); owner.setAccessibilityRole(.tabGroup); owner.setAccessibilityLabel("Sections")
        let inner = button("Inside").with { $0.refusesFirstResponder = true }
        owner.addSubview(inner)
        expect(found(host(owner)).violations.isEmpty, "a refusing button inside a focusable composite widget passes")
        let ownerless = KeyOwner(); ownerless.setAccessibilityLabel("Sections")
        expect(kinds(found(host(ownerless))) == [.missingRole], "a custom focusable view with a label but no role is filed under missingRole")

        // A scroll view's clip view is furniture: a subclass that takes the keys is not an unlabelled control (the main window's canvas sits in one).
        final class FocusableClip: NSClipView { override var acceptsFirstResponder: Bool { true } }
        let scroll = NSScrollView(); scroll.contentView = FocusableClip()
        expect(found(host(scroll)).violations.isEmpty, "a focusable clip view inside a scroll view is not judged as a control")

        // Disabled and hidden: a disabled control need not take focus; a hidden one must still be labelled but is out of uniqueness.
        expect(found(host(button("Save").with { $0.refusesFirstResponder = true; $0.isEnabled = false })).violations.isEmpty, "a disabled control may refuse focus")
        let hiddenPair = host(button("One", label: "Page"), button("Two", label: "Page").with { $0.isHidden = true })
        expect(found(hiddenPair).violations.isEmpty, "a hidden page does not collide with the visible one")
        let hiddenBare = found(host(iconButton().with { $0.isHidden = true }))
        expect(kinds(hiddenBare) == [.missingLabel] && hiddenBare.violations[0].hidden, "a hidden unlabelled control is still found, and marked hidden")

        // A table: its cells are walked, a missing label inside is found, and two rows with one label do not collide.
        final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
            let labelled: Bool
            init(labelled: Bool) { self.labelled = labelled }
            func numberOfRows(in tableView: NSTableView) -> Int { 2 }
            func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
                let cell = NSTableCellView()
                let control = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                if labelled { control.setAccessibilityLabel("Include") }
                cell.addSubview(control); return cell
            }
        }
        func table(labelled: Bool) -> (NSTableView, Rows) {
            let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 100)); table.setAccessibilityLabel("Rows")
            table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")))
            let rows = Rows(labelled: labelled); table.dataSource = rows; table.delegate = rows; table.reloadData()
            return (table, rows)
        }
        let (goodTable, goodRows) = table(labelled: true)
        withExtendedLifetime(goodRows) { expect(found(host(goodTable)).violations.isEmpty, "two table rows may share a label") }
        let (badTable, badRows) = table(labelled: false)
        withExtendedLifetime(badRows) { expect(kinds(found(host(badTable))) == [.missingLabel, .missingLabel], "an unlabelled control in every row is found in every row") }
        let (unlabelledTable, unlabelledRows) = table(labelled: true)
        unlabelledTable.setAccessibilityLabel(nil)
        withExtendedLifetime(unlabelledRows) { expect(kinds(found(host(unlabelledTable))) == [.missingLabel], "a table with no label is found") }

        // Tabs: a page that is not selected is still walked, and marked hidden.
        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        for (index, page) in [host(button("Fine")), host(iconButton())].enumerated() {
            let item = NSTabViewItem(identifier: index); item.label = "Tab \(index)"; item.view = page; tabs.addTabViewItem(item)
        }
        tabs.selectTabViewItem(at: 0)
        let tabReport = found(tabs)
        expect(kinds(tabReport) == [.missingLabel] && tabReport.violations[0].hidden && tabReport.violations[0].path.contains("tab[1]"), "the unselected tab is walked: \(tabReport.description)")

        // Window level: a titlebar accessory is walked too.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = host(button("Fine"))
        let accessory = NSTitlebarAccessoryViewController(); accessory.view = host(iconButton()); window.addTitlebarAccessoryViewController(accessory)
        let windowReport = Audit.audit(window, surface: "window")
        let unlabelled = windowReport.violations.filter { $0.kind == .missingLabel }
        expect(unlabelled.count == 1 && unlabelled[0].path.contains("titlebarAccessory"), "a titlebar accessory is walked: \(windowReport.description)")
    }

    // MARK: A2. The tracked kinds (OSN-062 WP1a): each can fail, each is exactly one kind

    /// A host that is in a window (never ordered on screen) and laid out, so frames, the key loop and element-ness are real.
    private static func hosted(_ view: NSView, size: NSSize = NSSize(width: 400, height: 300)) -> NSView {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        retained.append(window)
        view.frame = NSRect(origin: .zero, size: size)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return view
    }
    private static var retained: [NSWindow] = []

    /// A plain container with its children placed by hand, first child at the top, one row each: the order they were added is the order the eye reads.
    private static func column(_ views: [NSView]) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        for (index, view) in views.enumerated() {
            view.frame = NSRect(x: 20, y: 260 - CGFloat(index) * 40, width: 160, height: 28)
            container.addSubview(view)
        }
        return container
    }

    private static func trackedKinds() {
        // genericLabel: a role word, a symbol, a file, a kebab or camel-case identifier, the class name.
        for label in ["button", "Image", "camera.viewfinder", "shot.png", "cloud-arrow-up", "cloudArrowUp", "cloud_arrow_up"] {
            expect(kinds(found(host(iconButton(label: label)))) == [.genericLabel], "\(label): a label that names the kind of thing or a symbol is a genericLabel")
        }
        expect(kinds(found(host(iconButton(label: "NSButton")))) == [.genericLabel] || kinds(found(host(iconButton(label: "NSButtonCell")))) == [.genericLabel], "the class name as a label is a genericLabel")
        for label in ["Save", "Take a screenshot", "Re-Snap", "Version 1.2.3", "Settings\u{2026}", "Open in Photos."] {
            expect(found(host(iconButton(label: label))).violations.isEmpty, "\(label): a real name is not generic")
        }
        let genericImage = found(host(NSImageView(image: described("camera.viewfinder"))))
        expect(kinds(genericImage) == [.genericLabel], "an image described by a symbol name is a genericLabel: \(genericImage.description)")
        let genericMenuItem = NSMenu(title: "Root"); genericMenuItem.addItem(withTitle: "camera.viewfinder", action: nil, keyEquivalent: "")
        expect(kinds(Audit.audit(genericMenuItem, surface: "menu")) == [.genericLabel], "a menu item titled by a symbol name is a genericLabel")

        // missingValue: a slider-shaped control that never says where it stands; the real slider, checkbox and pop-up do.
        let valueless = found(host(ValuelessSlider().with { $0.setAccessibilityLabel("Volume") }))
        expect(kinds(valueless) == [.missingValue], "a slider with no value is a missingValue: \(valueless.description)")
        let popup = NSPopUpButton(frame: .zero, pullsDown: false); popup.addItems(withTitles: ["A", "B"]); popup.setAccessibilityLabel("Choice")
        expect(found(host(NSSlider().with { $0.setAccessibilityLabel("Size") }, NSButton(checkboxWithTitle: "Remember", target: nil, action: nil), popup)).violations.isEmpty, "a slider, a checkbox and a pop-up report their values")

        // readingOrderMismatch: the first child sits below the second.
        let inOrder = column([button("Top"), button("Middle"), button("Bottom")])
        expect(found(hosted(inOrder)).violations.isEmpty, "three buttons listed top to bottom read top to bottom")
        let swapped = column([button("Top"), button("Middle"), button("Bottom")])
        let (upper, lower) = (swapped.subviews[0], swapped.subviews[2])
        let upperOrigin = upper.frame.origin
        upper.setFrameOrigin(lower.frame.origin); lower.setFrameOrigin(upperOrigin)
        let mismatch = found(hosted(swapped))
        expect(kinds(mismatch) == [.readingOrderMismatch], "swapping the places of two children is a readingOrderMismatch: \(mismatch.description)")
        let freeForm = column([button("Top"), button("Middle"), button("Bottom")])
        freeForm.subviews[0].setFrameOrigin(freeForm.subviews[2].frame.origin); freeForm.subviews[2].setFrameOrigin(NSPoint(x: 20, y: 260))
        freeForm.setAccessibilityElement(true); freeForm.setAccessibilityRole(.group); freeForm.setAccessibilityLabel("Board"); freeForm.setAccessibilityIdentifier("order-free.board")
        expect(found(hosted(freeForm)).violations.isEmpty, "a parent whose identifier starts with order-free opts out")
        // Side by side reads left to right, and a taller neighbour does not break the row.
        let row = column([button("Left"), button("Right")])
        row.subviews[0].frame = NSRect(x: 20, y: 200, width: 100, height: 28); row.subviews[1].frame = NSRect(x: 140, y: 190, width: 100, height: 48)
        expect(found(hosted(row)).violations.isEmpty, "two buttons in one row read left to right")
        row.subviews[0].frame = NSRect(x: 140, y: 200, width: 100, height: 28); row.subviews[1].frame = NSRect(x: 20, y: 200, width: 100, height: 28)
        expect(kinds(found(hosted(row))) == [.readingOrderMismatch], "...and the reverse is a mismatch")

        // keyLoopDisagreesWithAXOrder: A, B, C in a column; the key loop goes A, C, B.
        let loopHost = column([button("A"), button("B"), button("C")])
        let loopWindow = NSWindow(contentRect: loopHost.frame, styleMask: [.titled], backing: .buffered, defer: true)
        loopWindow.isReleasedWhenClosed = false; loopWindow.contentView = loopHost; loopHost.layoutSubtreeIfNeeded()
        retained.append(loopWindow)
        let (a, b, c) = (loopHost.subviews[0], loopHost.subviews[1], loopHost.subviews[2])
        loopWindow.initialFirstResponder = a
        a.nextKeyView = c; c.nextKeyView = b; b.nextKeyView = a
        let loop = Audit.audit(loopWindow, surface: "seed")
        expect(loop.violations.map(\.kind) == [.keyLoopDisagreesWithAXOrder], "a key loop that goes A, C, B against the order A, B, C is found: \(loop.description)")
        a.nextKeyView = b; b.nextKeyView = c; c.nextKeyView = a
        expect(Audit.audit(loopWindow, surface: "seed").violations.isEmpty, "...and the loop A, B, C is clean")
        loopWindow.initialFirstResponder = b; a.nextKeyView = b; b.nextKeyView = c; c.nextKeyView = a
        expect(Audit.audit(loopWindow, surface: "seed").violations.isEmpty, "...wherever the loop starts")

        // ignoredButFocusable: focusable and enabled, but not an element and holding none.
        let mute = hosted(host(MuteControl().with { $0.setAccessibilityLabel("Mute"); $0.setAccessibilityRole(.button) }))
        let ignored = found(mute)
        expect(kinds(ignored) == [.ignoredButFocusable], "a focusable control that is not an accessibility element is found: \(ignored.description)")
        expect(found(hosted(host(MuteControl().with { $0.setAccessibilityLabel("Mute"); $0.setAccessibilityRole(.button); $0.isEnabled = false }))).violations.isEmpty, "a disabled one is not")
        expect(found(hosted(host(MuteControl().with { $0.setAccessibilityLabel("Mute"); $0.setAccessibilityRole(.button); $0.isHidden = true }))).violations.isEmpty, "a hidden one is not")
        let holder = MuteControl(); holder.setAccessibilityLabel("Holder"); holder.setAccessibilityRole(.group); holder.addSubview(button("Inside"))
        expect(found(hosted(host(holder))).violations.isEmpty, "a focusable container that holds an element is not (VoiceOver can land on what is inside)")

        // nameMismatch: a button named by its icon's description in the tree an external client reads, though the control carries another label.
        let iconic = described("Icon name")
        let renamed = NSButton(title: "", target: nil, action: nil); renamed.image = iconic; renamed.imagePosition = .imageOnly; renamed.setAccessibilityLabel("Real name")
        let mismatch2 = found(hosted(host(renamed)))
        expect(kinds(mismatch2) == [.nameMismatch], "a button whose own label the tree does not read is a nameMismatch: \(mismatch2.description)")
        let agreed = NSButton(title: "", target: nil, action: nil); agreed.image = iconic; agreed.imagePosition = .imageOnly; agreed.setAccessibilityLabel("Icon name")
        expect(found(hosted(host(agreed))).violations.isEmpty, "...and one whose label is the same words is not")

        // missingValue on a picture: a focusable image-role view names itself but must also say what it holds.
        let canvasLike = FocusablePicture(); canvasLike.setAccessibilityLabel("Drawing canvas")
        let pictureReport = found(hosted(host(canvasLike)))
        expect(kinds(pictureReport) == [.missingValue], "a focusable picture with a name and no value is a missingValue: \(pictureReport.description)")
        canvasLike.summary = "No annotations"
        expect(found(hosted(host(canvasLike))).violations.isEmpty, "...and with a value it is clean")

        // The baseline: a covered finding moves to `baselined`, a stale or different one does not.
        let covered = Audit.Finding(kind: .genericLabel, surface: "s", path: "p", label: "l", hidden: false)
        expect(covered.kind.isTracked && Audit.Kind.nameMismatch.isTracked && Audit.Kind.missingLabel.isTracked && !Audit.Kind.retiredName.isTracked && !Audit.Kind.undescribedImage.isTracked,
               "the WP1a kinds, nameMismatch, missingLabel, missingRole and duplicateLabel are baselinable; the retired name and an undescribed image never are")
    }

    // MARK: B. Nothing false

    private static func cleanTreeIsClean() {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false); popup.addItems(withTitles: ["A", "B"]); popup.setAccessibilityLabel("Choice")
        let segmented = NSSegmentedControl(labels: ["PNG", "JPG"], trackingMode: .selectOne, target: nil, action: nil); segmented.setAccessibilityLabel("Image format")
        let tree = host(NSTextField(labelWithString: "Title"), button("Save"), iconButton(label: "Share"), popup, segmented,
                        NSButton(checkboxWithTitle: "Remember", target: nil, action: nil), NSImageView(image: described("Logo")))
        let report = found(tree)
        expect(report.violations.isEmpty, "a clean tree has no violations: \(report.description)")
        expect(report.controls == 6 && report.labelled == 6, "the walker judged the six interactive elements (the static caption is content) and found a label on each (\(report.controls)/\(report.labelled))")
    }

    // MARK: B2. The spoken script, and the synthetic good window the new kinds must leave clean

    /// One of everything the rendering table names, placed by hand from the top, in a window that is never ordered.
    private static func syntheticWindow() -> (NSWindow, NSView) {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false); popup.addItems(withTitles: ["PNG", "JPG"]); popup.selectItem(at: 1); popup.setAccessibilityLabel("Format")
        let slider = NSSlider(value: 40, minValue: 0, maxValue: 100, target: nil, action: nil); slider.setAccessibilityLabel("Size")
        let remember = NSButton(checkboxWithTitle: "Remember", target: nil, action: nil); remember.state = .on
        let save = button("Save"); let share = iconButton(label: "Share").with { $0.setAccessibilityHelp("Sends the image to your default destination") }
        let name = NSTextField(string: "Shot 1"); name.isEditable = true; name.setAccessibilityLabel("Name")
        let empty = NSTextField(string: ""); empty.isEditable = true; empty.setAccessibilityLabel("Caption")
        let secret = NSSecureTextField(string: "hunter2"); secret.setAccessibilityLabel("Password")
        let logo = NSImageView(image: described("Logo"))
        let off = button("Delete").with { $0.isEnabled = false }
        let container = column([NSTextField(labelWithString: "Title"), save, share, popup, slider, remember, name, empty, secret, logo, off])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.title = "Export"
        window.contentView = container; container.layoutSubtreeIfNeeded()
        retained.append(window)
        return (window, container)
    }

    private static func spokenScriptRendering() {
        let (window, container) = syntheticWindow()
        let clean = Audit.audit(window, surface: "synthetic")
        expect(clean.violations.isEmpty && clean.baselined.isEmpty, "the synthetic good window is clean of every kind, new ones included: \(clean.description)")

        let tree = AXTree.walk(window)
        let lines = SpokenScript.lines(for: tree).filter { !$0.contains("\u{2026}") }
        let expected = [
            "[0] Title",
            "[0] Save, button",
            "[0] Share, button",
            "[0]   hint: Sends the image to your default destination",
            "[0] JPG, Format, pop up button",
            "[0] Size, 40, slider",
            "[0] Remember, checked, checkbox",
            "[0] Name, Shot 1, edit text",
            "[0] Caption, empty, edit text",
            "[0] Password, secure edit text",
            "[0] Logo, image",
            "[0] Delete, button, dimmed",
        ]
        expect(lines == expected, "the script reads as the rendering table says:\n" + lines.joined(separator: "\n") + "\n--- expected\n" + expected.joined(separator: "\n"))
        expect(!lines.joined().contains("hunter2"), "a secure field's value is never printed")
        let document = SpokenScript.render(tree, surface: "Export window", suite: "t")
        expect(document.hasPrefix("# Export window\n") && document.contains("[0] Export, window") && document.contains("- Nodes: \(tree.nodes.count)"), "the document carries its surface, window line and node count")
        expect(SpokenScript.slug("Settings: General (tab view)") == "settings-general-tab-view" && SpokenScript.slug("  ") == "surface", "slugs are lower-case hyphenated words")

        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Save", action: nil, keyEquivalent: "s")
        menu.addItem(.separator())
        let sub = NSMenuItem(title: "Export", action: nil, keyEquivalent: ""); sub.submenu = NSMenu(title: "Export")
        sub.submenu?.addItem(withTitle: "PNG", action: nil, keyEquivalent: "")
        menu.addItem(sub)
        expect(SpokenScript.lines(for: menu) == ["[0] Save, Command S", "[0] Export, submenu", "[1]   PNG"], "a menu reads title, shortcut, nesting: \(SpokenScript.lines(for: menu))")

        // Mutations of the good window, each caught as exactly its own kind (and reverted: the window is clean again afterwards).
        let kept = container.subviews[1].frame.origin, other = container.subviews[2].frame.origin
        container.subviews[1].setFrameOrigin(other); container.subviews[2].setFrameOrigin(kept)
        let swapped = Audit.audit(window, surface: "synthetic")
        expect(swapped.violations.map(\.kind) == [.readingOrderMismatch], "swapping two subviews of the good window is a readingOrderMismatch: \(swapped.description)")
        container.subviews[1].setFrameOrigin(kept); container.subviews[2].setFrameOrigin(other)
        let share = container.subviews[2]
        share.setAccessibilityLabel("camera.viewfinder")
        expect(Audit.audit(window, surface: "synthetic").violations.map(\.kind) == [.genericLabel], "a symbol name as a label is a genericLabel")
        share.setAccessibilityLabel("Share")
        let muteHost = MuteControl(); muteHost.setAccessibilityLabel("Mute"); muteHost.setAccessibilityRole(.button); muteHost.frame = NSRect(x: 200, y: 260, width: 60, height: 28)
        container.addSubview(muteHost)
        expect(Audit.audit(window, surface: "synthetic").violations.map(\.kind).contains(.ignoredButFocusable), "a control that stopped being an accessibility element is an ignoredButFocusable")
        muteHost.removeFromSuperview()
        expect(Audit.audit(window, surface: "synthetic").violations.isEmpty, "...and the good window is clean again once the mutations are reverted")
    }

    // MARK: C. Menus

    private static func menus() {
        func menu(_ titles: [String], _ configure: (NSMenu) -> Void = { _ in }) -> NSMenu {
            let menu = NSMenu(title: "Root"); titles.forEach { menu.addItem(withTitle: $0, action: nil, keyEquivalent: "") }; configure(menu); return menu
        }
        expect(Audit.audit(menu(["Copy", "Paste"]) { $0.insertItem(.separator(), at: 1) }, surface: "menu").violations.isEmpty, "a plain menu with a separator is clean")
        expect(kinds(Audit.audit(menu(["Copy", ""]), surface: "menu")) == [.missingLabel], "a menu item with no title is found")
        expect(kinds(Audit.audit(menu(["Copy", "copy"]), surface: "menu")) == [.duplicateLabel, .duplicateLabel], "two items with one title in one menu are found")
        expect(kinds(Audit.audit(menu(["Copy", "copy"]), surface: "menu", allowedDuplicates: ["Copy": "Edit and context menu share it"])) == [.duplicateInGroup, .duplicateInGroup],
               "an allow-listed menu duplicate is no longer a duplicateLabel but is still two items of one menu")
        expect(kinds(Audit.audit(menu(["Open in " + Audit.retiredName]), surface: "menu")) == [.retiredName], "a retired name in a menu title is found")
        let nested = menu(["Outer"]) { root in
            let sub = NSMenu(title: "Sub"); sub.addItem(withTitle: "", action: nil, keyEquivalent: "")
            root.items[0].submenu = sub
        }
        expect(kinds(Audit.audit(nested, surface: "menu")) == [.missingLabel], "a submenu item with no title is found")
        let iconItem = NSMenuItem(title: "", action: nil, keyEquivalent: ""); iconItem.image = plain
        let iconMenu = NSMenu(title: "Icons"); iconMenu.addItem(iconItem)
        expect(kinds(Audit.audit(iconMenu, surface: "menu")) == [.missingLabel], "an icon-only menu item is found")
        iconItem.setAccessibilityLabel("Share")
        expect(Audit.audit(iconMenu, surface: "menu").violations.isEmpty, "an accessibility label rescues an icon-only menu item")
    }

    // MARK: D. The real surfaces

    private struct Key { static let returnKey: (String, UInt16) = ("\r", 36), escape: (String, UInt16) = ("\u{1b}", 53) }

    private static func key(_ code: (String, UInt16), in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: code.0, charactersIgnoringModifiers: code.0, isARepeat: false, keyCode: code.1)!
    }

    private static func parentWindow() -> NSWindow {
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        parent.isReleasedWhenClosed = false
        return parent
    }

    /// A private property read back by name (test-only): the sheets keep their panel private.
    private static func private_<T>(_ object: Any, _ name: String, as: T.Type = T.self) -> T? {
        Mirror(reflecting: object).children.first { $0.label == name }.flatMap { $0.value as? T }
    }

    private static func realSurfaces() {
        var reports: [(String, Audit.Report)] = []
        func record(_ surface: String, _ report: Audit.Report) { reports.append((surface, report)) }

        // About, its licence window and the third-party notices window.
        let about = AboutWindow(icon: NSImage(size: NSSize(width: 64, height: 64)),
                                info: ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "45"], licenseText: { "MIT License\n\nPermission is hereby granted." },
                                noticesText: { "Notices" })
        record("About", Audit.audit(about, surface: "About"))
        record("License", Audit.audit(about.makeLicenseWindow(), surface: "License"))
        record("Notices", Audit.audit(about.makeNoticesWindow(), surface: "Notices"))

        // History: empty state, then populated and filtered.
        let suite = "OpenSnapAccessibilityAudit." + UUID().uuidString
        let defaults = TestDefaults(name: suite)
        defer { TestDefaults.dispose(defaults, name: suite) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let history = HistoryBrowser(defaults: defaults, calendar: calendar, now: { now })
        defer { history.close() }
        history.saveShortcut = { "\u{2318}S" }
        record("History (empty)", Audit.audit(history.window!, surface: "History (empty)"))
        var items: [HistoryBrowser.Item] = []
        for index in 0..<4 {
            let shared = index % 2 == 1
            let date = now.addingTimeInterval(TimeInterval(-index * 90_000))
            let link: URL? = shared ? URL(string: "https://example.invalid/shot") : nil
            items.append(HistoryBrowser.Item(id: UUID(), name: "Shot \(index)", date: date, size: CGSize(width: 640, height: 480),
                                             action: shared ? "Shared" : "Saved", text: "note", destination: nil,
                                             link: link, previewURL: nil, missing: index == 3))
        }
        history.update(items: items)
        history.window!.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 700), display: false)
        history.window!.contentView?.layoutSubtreeIfNeeded()
        record("History (populated)", Audit.audit(history.window!, surface: "History (populated)"))

        // Destination editor: the form for every protocol (the Protocol popup swaps rows).
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.invalid/shots"; dav.username = "user"
        var s3 = PublishingSettings(); s3.transport = .s3; s3.endpoint = "https://s3.example.invalid"; s3.s3 = S3Options()
        let first = PublishingDestination(name: "Work", settings: dav), second = PublishingDestination(name: "Backup", settings: s3)
        _ = second
        let destinations = PublishingDestinationsView(editing: first)
        destinations.frame = NSRect(x: 0, y: 0, width: PublishingDestinationsView.sheetWidth, height: 600)
        let destinationsWindow = NSWindow(contentRect: destinations.frame, styleMask: [.titled], backing: .buffered, defer: true)
        destinationsWindow.isReleasedWhenClosed = false; destinationsWindow.contentView = destinations
        destinations.layoutSubtreeIfNeeded()
        record("Destinations (edit form)", Audit.audit(destinations, surface: "Destinations (edit form)"))
        destinations.showStatus("Could not reach the server")
        record("Destinations (edit form, error)", Audit.audit(destinations, surface: "Destinations (edit form, error)"))
        destinations.showForm(for: nil)
        for (index, transport) in PublishingProtocol.allCases.enumerated() {
            destinations.protocolPopup.selectItem(at: index)
            _ = destinations.protocolPopup.target?.perform(destinations.protocolPopup.action, with: destinations.protocolPopup)
            destinations.layoutSubtreeIfNeeded()
            record("Destinations (form, \(transport.title))", Audit.audit(destinations, surface: "Destinations (form, \(transport.title))"))
        }
        destinations.showTestResult(ok: true, message: "Listed the bucket")
        record("Destinations (form, test result)", Audit.audit(destinations, surface: "Destinations (form, test result)"))

        // Resize or Crop in all three modes.
        let resizeSuite = "OpenSnapAccessibilityAudit.resize." + UUID().uuidString
        let resizeDefaults = TestDefaults(name: resizeSuite)
        defer { TestDefaults.dispose(resizeDefaults, name: resizeSuite) }
        let resizeParent = parentWindow()
        let resize = ResizePanel(session: ResizePanelSession(size: CGSize(width: 800, height: 600), onApply: { _, _, _ in }), presets: ResizePresetStore(defaults: resizeDefaults))
        resize.show(attachedTo: resizeParent)
        let resizePanel: NSPanel? = private_(resize, "panel")
        expect(resizePanel != nil, "the Resize or Crop panel was built")
        if let resizePanel, let modeControl: GlassChoiceGroup = private_(resize, "modeControl") {
            for (index, name) in ["Resize", "Crop", "Limit"].enumerated() {
                modeControl.choose(index)
                resizePanel.contentView?.layoutSubtreeIfNeeded()
                record("Resize or Crop (\(name))", Audit.audit(resizePanel, surface: "Resize or Crop (\(name))"))
                expect(modeControl.buttons[index].title == name && modeControl.buttons[index].accessibilityLabel() == name, "the \(name) segment is labelled")
            }
            expect(modeControl.accessibilityLabel() == "Size operation", "the mode control has a group label")
        } else { expect(false, "the mode control was found") }
        // WP1b: the size preset choices, the glass panel behind the preset pop-up.
        if let presetPopup: GlassPopUpButton = private_(resize, "presetPopup") {
            presetPopup.choicePanel.host.presenter = { _, _ in }
            presetPopup.performClick(nil)
            expect(presetPopup.choicePanel.host.isShown, "the Resize preset panel opened")
            record("Resize preset panel", Audit.audit(presetPopup.choicePanel.host.window, surface: "Resize preset panel"))
            presetPopup.choicePanel.host.close()
        } else { expect(false, "the preset pop-up was found") }
        if let sheet = resizeParent.attachedSheet ?? resizePanel { resizeParent.endSheet(sheet) }

        // Photos sheet.
        let photoParent = parentWindow()
        let photos = PhotoBrowserCoordinator()
        photos.show(relativeTo: photoParent, onOpen: { _ in })
        let photoPanel: NSPanel? = private_(photos, "panel")
        expect(photoPanel != nil, "the Photos panel was built")
        if let photoPanel {
            photoPanel.contentView?.layoutSubtreeIfNeeded()
            record("Photos (empty)", Audit.audit(photoPanel, surface: "Photos (empty)"))
            if let empty: NSView = private_(photos, "emptyState"), let folderButton: NSButton = private_(photos, "folderButton"), let libraryButton: NSButton = private_(photos, "libraryButton") {
                expect(!empty.isHidden && folderButton.isDescendant(of: empty) && libraryButton.isDescendant(of: empty),
                       "Photos: with nothing chosen the grid itself holds the explanation and both source buttons (F-J1-013)")
                expect(folderButton.title == "Choose Pictures Folder…" && libraryButton.title == "Choose from Photos Library…", "Photos: the buttons say what they do")
            } else { expect(false, "Photos: the empty state and its buttons were found") }
            // OSN-071 r3: every Photos button is a 36 pt glass capsule on an action plate (the alert's), not a flat system push button.
            let photoButtons: [(String, GlassChoiceButton)] = [("Choose Pictures Folder…", photos.folderButton), ("Choose from Photos Library…", photos.libraryButton),
                                                              ("Open Selected Photo", photos.openButton), ("Close", photos.closeButton)]
            for (title, button) in photoButtons {
                var plate: NSView? = button.superview
                while let candidate = plate, !(candidate is GlassSurfaceView) { plate = candidate.superview }
                expect(type(of: button) == GlassChoiceButton.self && plate != nil && plate === (title.hasPrefix("Choose") ? photos.sourcesPlate : photos.actionsPlate),
                       "Photos: '\(title)' is a GlassChoiceButton on its action plate")
                expect(button.title == title && button.frame.height == DesignTokens.Size.control, "Photos: '\(title)' is \(DesignTokens.Size.control) pt high (\(button.frame.height))")
            }
            expect(photos.openButton.isPrimary && photoPanel.defaultButtonCell === photos.openButton.cell && photos.closeButton.keyEquivalent == "\u{1b}", "Photos: Open is the tinted default (Return) button, Close answers Escape")
        }
        photos.shutdown()

        // The Settings window, every tab.
        let settingsSuite = "OpenSnapAccessibilityAudit.settings." + UUID().uuidString
        let settingsDefaults = TestDefaults(name: settingsSuite)
        defer { TestDefaults.dispose(settingsDefaults, name: settingsSuite) }
        let settings = SettingsWindowController(state: { GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2, includeApp: true, statusMenu: 0, showToolTips: true) },
                                                hotkeys: GlobalHotkeyManager(defaults: settingsDefaults, backend: InertHotkeyBackend()), defaults: settingsDefaults,
                                                destinations: { PublishingDestinationList(defaultID: first.id, destinations: [first, second]) })
        for (index, item) in settings.tabItems.enumerated() {
            settings.select(index)
            settings.window.contentView?.layoutSubtreeIfNeeded()
            record("Settings: \(item.label)", Audit.audit(settings.window, surface: "Settings: \(item.label)"))
            record("Settings: \(item.label) (tab view)", Audit.audit(item.viewController.view, surface: "Settings: \(item.label) (tab view)"))
        }

        // Text style, the Export accessory, the shortcut form in both modes and the alert sheets.
        record("Text style", Audit.audit(TextStyleForm(outlined: nil, shadowed: nil), surface: "Text style"))
        let accessory = ExportAccessory(format: "jpeg", originalSize: false, jpegQuality: 0.7)
        accessory.view.layoutSubtreeIfNeeded()
        record("Export accessory", Audit.audit(accessory.view, surface: "Export accessory"))
        // T9 (OSN-054): five formats, and the JPG quality is a statement ("JPG quality 75%"), not a locked slider.
        accessory.fixedJPEGQuality = 0.75
        func everyView(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(everyView) }
        let accessoryViews = everyView(accessory.view)
        expect(accessoryViews.compactMap { $0 as? NSPopUpButton }.first?.itemTitles == ["PNG", "JPG", "PDF", "TIFF", "SVG"], "Export accessory: the format popup lists PNG, JPG, PDF, TIFF, SVG")
        expect(accessoryViews.compactMap { $0 as? NSSlider }.isEmpty, "Export accessory: there is no quality slider")
        expect(accessoryViews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "JPG quality 75%" }, "Export accessory: the quality row reads JPG quality 75%")
        // OSN-071 r3: the JPG quality line belongs to JPG (hidden while PNG is chosen, no control to explain), and "Format:" takes the colon of its neighbours.
        func qualityLine(_ accessory: ExportAccessory) -> NSTextField? { everyView(accessory.view).compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("JPG quality") } }
        expect(qualityLine(accessory)?.isHidden == false, "Export accessory: the quality line shows while JPG is chosen")
        accessory.format = "png"
        expect(qualityLine(accessory)?.isHidden == true, "Export accessory: the quality line is hidden while PNG is chosen")
        accessory.format = "jpeg"
        expect(qualityLine(accessory)?.isHidden == false, "Export accessory: the quality line is back for JPG")
        let accessoryLabels = everyView(accessory.view).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
        expect(accessoryLabels.contains("Format:") && !accessoryLabels.contains("Format") && accessoryLabels.contains { $0.hasPrefix("Dimensions:") } && accessoryLabels.contains { $0.hasPrefix("Encoded size:") },
               "Export accessory: Format has the colon the other labels have: \(accessoryLabels)")
        let field = NSTextField(string: "6"); field.frame = NSRect(x: 0, y: 0, width: 400, height: 40); field.setAccessibilityLabel("Number of copies")
        let alerts: [(String, AppAlert)] = [
            ("one button", AppAlert(title: "Saved", message: "The drawing was saved.")),
            ("save, cancel, don't save", AppAlert(title: "Save your drawing?", message: "Changes are lost otherwise.",
                buttons: [.init(title: "Save"), .init(title: "Cancel", role: .cancel), .init(title: "Don\u{2019}t Save", role: .destructive)])),
            ("with a text field", AppAlert(title: "Rename", buttons: [.init(title: "OK"), .init(title: "Cancel", role: .cancel)], accessoryView: field)),
            ("error", AppAlert(error: NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error: the upload failed",
                                                                          NSLocalizedRecoverySuggestionErrorKey: "Check the destination."]))),
        ]
        for (name, alert) in alerts { record("Alert (\(name))", Audit.audit(alert.panel, surface: "Alert (\(name))")) }

        // WP1b: the questions the app asks in its own words (App.confirmDiscard, App.prompt, removeHistory, deleteFromWeb).
        let promptText = "Name for this drawing"
        let promptField = NSTextField(string: "Untitled"); promptField.frame = NSRect(x: 0, y: 0, width: AppAlert.width - 2 * DesignTokens.Space.s5, height: DesignTokens.Size.field)
        promptField.setAccessibilityLabel(promptText)
        let questions: [(String, AppAlert)] = [
            ("confirm discard", AppAlert(title: "Save your drawing?", message: "This document has changes that have not been saved.",
                buttons: [.init(title: "Save"), .init(title: "Cancel", role: .cancel), .init(title: "Don\u{2019}t Save", role: .destructive)])),
            ("prompt", AppAlert(title: "Rename", message: promptText, buttons: [.init(title: "OK"), .init(title: "Cancel", role: .cancel)], accessoryView: promptField)),
            ("remove history", AppAlert(title: "Move archived drawings to Trash?",
                message: "The selected History copies and previews will move to Trash. Exported originals and web posts are kept.",
                buttons: [.init(title: "Cancel", role: .cancel), .init(title: "Move to Trash", role: .destructive)])),
            ("delete remote", AppAlert(title: "Delete this web post?",
                message: "This removes the published image at https://example.invalid/pics/shot.png. Its editable History copy will be kept.",
                buttons: [.init(title: "Cancel", role: .cancel), .init(title: "Delete from Web", role: .destructive)])),
        ]
        for (name, alert) in questions { record("Alert (\(name))", Audit.audit(alert.panel, surface: "Alert (\(name))")) }

        // WP1b: the History date filter's glass panel and the thumbnail grid's context menu.
        let dateFilter = history.dateFilterPopUp
        dateFilter.choicePanel.host.presenter = { _, _ in }
        dateFilter.performClick(nil)
        expect(dateFilter.choicePanel.host.isShown, "the History filter panel opened")
        record("History filter panel", Audit.audit(dateFilter.choicePanel.host.window, surface: "History filter panel"))
        dateFilter.choicePanel.host.close()
        if let grid: NSCollectionView = private_(history, "collection"), let menu = grid.menu {
            // As a right-click leaves it: the shared entry (Shot 1, a day back) selected, its actions enabled.
            let handled: ([UUID]) -> Void = { _ in }
            history.onOpen = handled; history.onCopy = handled; history.onCopyLink = handled; history.onOpenLink = handled
            history.onRemove = handled; history.onDeleteFiles = handled; history.onDeleteRemote = handled
            grid.selectionIndexPaths = [IndexPath(item: 0, section: 1)]
            history.collectionView(grid, didSelectItemsAt: [IndexPath(item: 0, section: 1)])
            menu.update()
            record("History context menu", Audit.audit(menu, surface: "History context menu"))
        } else { expect(false, "the History grid has a context menu") }

        var controls = 0, labelled = 0
        var problems: [String] = []
        for (surface, report) in reports {
            expect(report.controls > 0 || surface.hasPrefix("License") || surface.hasPrefix("Notices"), "\(surface): the walker judged no element at all, so a zero-violation result would prove nothing")
            if !report.violations.isEmpty { problems.append("\(surface):\n\(report.description)") }
            controls += report.controls; labelled += report.labelled
            print("  \(surface): \(report.controls) elements, \(report.labelled) labelled, 0 violations")
        }
        print("  \(reports.count) surfaces, \(controls) elements judged, \(labelled) labelled")
        expect(problems.isEmpty, "accessibility violations on real surfaces:\n" + problems.joined(separator: "\n"))

        Audit.recording = false  // from here the surfaces are deliberately worsened: no script, no findings dump
        // The walker must fail when a real surface is made worse: strip one label from each of three, expect exactly that.
        let kept = destinations.nameField.accessibilityLabel()
        destinations.nameField.setAccessibilityLabel(nil)
        let strippedDestinations = Audit.audit(destinations, surface: "Destinations (seeded)").violations.filter { $0.kind == .missingLabel }
        expect(strippedDestinations.count == 1 && strippedDestinations[0].kind == .missingLabel, "Destinations: a stripped Name label is caught on the real form: \(strippedDestinations)")
        destinations.nameField.setAccessibilityLabel(kept)
        if let widthField: NSTextField = private_(resize, "widthField"), let modeControl: GlassChoiceGroup = private_(resize, "modeControl") {
            let label = widthField.accessibilityLabel()
            widthField.setAccessibilityLabel(nil)
            let strippedResize = Audit.audit(resizePanel!, surface: "Resize (seeded)").violations.filter { $0.kind == .missingLabel }
            expect(strippedResize.count == 1 && strippedResize[0].kind == .missingLabel, "Resize: a stripped Width label is caught on the real panel: \(strippedResize)")
            widthField.setAccessibilityLabel(label)
            // The glass mode group is a custom radio group: the walker does not hold it, so its name and role are asserted here.
            expect(modeControl.accessibilityLabel() == "Size operation" && modeControl.accessibilityRole() == .radioGroup && modeControl.buttons.allSatisfy { $0.accessibilityRole() == .radioButton },
                   "Resize: the mode group is a named radio group of radio buttons")
        }
        about.versionLabel.setAccessibilityLabel("Version 1.2.3 of " + Audit.retiredName)
        expect(kinds(Audit.audit(about, surface: "About (seeded)")).contains(.retiredName), "About: the retired name in a label is caught on the real window")
        UserStrings.removeSeeded(surface: "About (seeded)")  // the seeded name is on purpose; the string walk must judge only what ships

    }

    // MARK: E. Return and Escape in every sheet outside the editor (OSN-060, T7 test 4)

    /// Presses Return or Escape on a sheet that is attached to an unordered parent. AppKit parks the Return key equivalent of a window
    /// that is not on screen (the OK button reads back an empty key equivalent), but the window's default button is still the thing
    /// Return fires, so Return is the default cell clicked; Escape is a real key event through performKeyEquivalent.
    private static func press(_ code: (String, UInt16), on panel: NSWindow) -> Bool {
        if code.0 == "\r" {
            guard let cell = panel.defaultButtonCell, cell.isEnabled else { return false }
            cell.performClick(nil); return true
        }
        return panel.performKeyEquivalent(with: key(code, in: panel))
    }

    private static func button(titled title: String, in window: NSWindow) -> NSButton? {
        func search(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.title == title { return button }
            for sub in view.subviews { if let hit = search(sub) { return hit } }
            return nil
        }
        return window.contentView.flatMap(search)
    }

    private static func spin(until condition: () -> Bool, seconds: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    }

    private static func sheetKeyboard() {
        // Resize or Crop: Return is OK (applies), Escape is Cancel (applies nothing).
        for (name, code, applies) in [("Return", Key.returnKey, true), ("Escape", Key.escape, false)] {
            let suite = "OpenSnapAccessibilityAudit.keys." + UUID().uuidString
            let defaults = TestDefaults(name: suite); defer { TestDefaults.dispose(defaults, name: suite) }
            var applied: [CGSize] = []
            let parent = parentWindow()
            let resize = ResizePanel(session: ResizePanelSession(size: CGSize(width: 800, height: 600), onApply: { size, _, _ in applied.append(size) }),
                                     presets: ResizePresetStore(defaults: defaults))
            resize.show(attachedTo: parent)
            guard let panel: NSPanel = private_(resize, "panel") else { expect(false, "Resize panel exists"); continue }
            expect(panel.sheetParent === parent, "Resize: the panel is a sheet on its parent")
            expect(panel.defaultButtonCell != nil && panel.defaultButtonCell === button(titled: "OK", in: panel)?.cell, "Resize: the default button is the OK button")
            expect(button(titled: "Cancel", in: panel)?.keyEquivalent == "\u{1b}", "Resize: Cancel answers Escape")
            expect(press(code, on: panel), "Resize: \(name) is handled")
            expect(applied.count == (applies ? 1 : 0), "Resize: \(name) \(applies ? "applies once (OK)" : "applies nothing (Cancel)")")
            expect(panel.sheetParent == nil, "Resize: \(name) ends the sheet")
        }

        // Return and Escape typed into a size field answer for the sheet as well (audit F-J1-004): Return is OK whether or not the sheet's own key
        // equivalents are live, Apply is only the preview button, and the preset name field keeps Return for its own text.
        for (name, command, applies) in [("Return", #selector(NSResponder.insertNewline(_:)), true), ("Escape", #selector(NSResponder.cancelOperation(_:)), false)] {
            let suite = "OpenSnapAccessibilityAudit.fieldkeys." + UUID().uuidString
            let defaults = TestDefaults(name: suite); defer { TestDefaults.dispose(defaults, name: suite) }
            var applied: [CGSize] = []
            let parent = parentWindow()
            let resize = ResizePanel(session: ResizePanelSession(size: CGSize(width: 800, height: 600), onApply: { size, _, _ in applied.append(size) }),
                                     presets: ResizePresetStore(defaults: defaults))
            resize.show(attachedTo: parent)
            guard let panel: NSPanel = private_(resize, "panel"), let content = panel.contentView else { expect(false, "Resize panel exists"); continue }
            func field(_ label: String) -> NSTextField? {
                func search(_ view: NSView) -> NSTextField? {
                    if let field = view as? NSTextField, field.accessibilityLabel() == label { return field }
                    for sub in view.subviews { if let hit = search(sub) { return hit } }
                    return nil
                }
                return search(content)
            }
            resize.setPresetManagementShown(true) // preset naming is folded away until asked for
            guard let width = field("Width in pixels"), let preset = field("Preset name") else { expect(false, "Resize fields exist"); continue }
            expect(panel.defaultButtonCell !== button(titled: "Apply", in: panel)?.cell && panel.defaultButtonCell === button(titled: "OK", in: panel)?.cell,
                   "Resize: Apply is the plain preview button and OK is the default")
            width.stringValue = "400"
            resize.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: width))
            // The key goes where it goes for a person: into the field editor, which asks the field's own delegate. Calling the delegate method
            // directly would pass even if the field were never wired to it.
            expect(width.delegate === resize && preset.delegate === resize, "Resize: the size fields and the preset name field report their keys to the panel")
            if applies {
                expect(panel.makeFirstResponder(preset), "Resize: the preset name field takes the keyboard")
                (preset.currentEditor() as? NSTextView)?.doCommand(by: command)
                expect(applied.isEmpty && panel.sheetParent === parent, "Resize: \(name) in the preset name field is left to that field")
            }
            expect(panel.makeFirstResponder(width), "Resize: the width field takes the keyboard")
            (width.currentEditor() as? NSTextView)?.doCommand(by: command)
            expect(applied.count == (applies ? 1 : 0) && (!applies || applied[0].width == 400), "Resize: \(name) in the width field \(applies ? "applies the typed size once (OK)" : "applies nothing (Cancel)") (\(applied))")
            expect(panel.sheetParent == nil, "Resize: \(name) in the width field closes the sheet")
        }

        // Photos: Escape closes without opening; Return opens the selected photo and does nothing while nothing is selected.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("opensnap-a11y-photos-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("Shot.png")
        let destination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemBlue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        expect(CGImageDestinationFinalize(destination), "the photo fixture was written")
        for (name, code, opens) in [("Return", Key.returnKey, true), ("Escape", Key.escape, false)] {
            let parent = parentWindow()
            var opened: [URL] = []
            let photos = PhotoBrowserCoordinator()
            photos.show(relativeTo: parent, onOpen: { opened.append($0) })
            guard let panel: NSPanel = private_(photos, "panel"), let table: NSTableView = private_(photos, "table") else { expect(false, "Photos panel exists"); continue }
            expect(panel.defaultButtonCell != nil && panel.defaultButtonCell === button(titled: "Open Selected Photo", in: panel)?.cell, "Photos: the default button is Open Selected Photo")
            expect(button(titled: "Close", in: panel)?.keyEquivalent == "\u{1b}", "Photos: Close answers Escape")
            if opens {
                expect(!press(code, on: panel) && opened.isEmpty && panel.sheetParent === parent, "Photos: Return with nothing selected opens nothing and keeps the sheet")
                photos.loadFolder(folder)
                spin(until: { table.numberOfRows == 1 })
                expect(table.numberOfRows == 1, "Photos: the fixture folder loaded one photo")
                if let empty: NSView = private_(photos, "emptyState"), let folderButton: NSButton = private_(photos, "folderButton") {
                    expect(empty.isHidden && !folderButton.isDescendant(of: empty), "Photos: once photos load, the empty state gives way and the source buttons move to the row above the grid")
                }
                table.selectRowIndexes([0], byExtendingSelection: false)
            }
            expect(press(code, on: panel), "Photos: \(name) is handled")
            expect(opened.count == (opens ? 1 : 0), "Photos: \(name) \(opens ? "opens the selected photo" : "closes without opening")")
            expect(panel.sheetParent == nil, "Photos: \(name) ends the sheet")
            photos.shutdown()
        }

        // Destination editor: Return is Save and Escape is Cancel.
        for (name, code) in [("Return", Key.returnKey), ("Escape", Key.escape)] {
            let view = PublishingDestinationsView(editing: nil)
            view.frame = NSRect(x: 0, y: 0, width: PublishingDestinationsView.sheetWidth, height: 600)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false; window.contentView = view
            var cancelled = 0, saved: [PublishingDestination] = []
            view.onCancel = { cancelled += 1 }; view.onSave = { destination, _ in saved.append(destination) }
            view.nameField.stringValue = "Fresh"; view.endpointField.stringValue = "https://dav.example.invalid/more"
            expect(window.defaultButtonCell === view.saveButton.cell, "Destinations: Save is the default button")
            expect(window.performKeyEquivalent(with: key(code, in: window)), "Destinations: \(name) is handled")
            if name == "Return" { expect(saved.count == 1 && saved[0].name == "Fresh" && cancelled == 0, "Destinations: Return is Save") }
            else { expect(saved.isEmpty && cancelled == 1, "Destinations: Escape is Cancel") }
        }

        // Alerts: Return answers the first button, Escape answers Cancel (the full matrix is in app-alert-tests).
        for (name, code, expected) in [("Return", Key.returnKey, 0), ("Escape", Key.escape, 1)] {
            let alert = AppAlert(title: "Save your drawing?", buttons: [.init(title: "Save"), .init(title: "Cancel", role: .cancel)])
            expect(alert.panel.contentView?.performKeyEquivalent(with: key(code, in: alert.panel)) == true, "Alert: \(name) is handled")
            expect(alert.response?.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + expected, "Alert: \(name) answers button \(expected)")
        }
        let lone = AppAlert(title: "Done"); lone.panel.cancelOperation(nil)
        expect(lone.response == .alertFirstButtonReturn, "Alert: Escape (cancelOperation) answers a lone OK")

        // Settings: Escape closes through cancelOperation; the Export accessory and Text style are not sheets of their own.
        let settingsSuite = "OpenSnapAccessibilityAudit.settingskeys." + UUID().uuidString
        let settingsDefaults = TestDefaults(name: settingsSuite); defer { TestDefaults.dispose(settingsDefaults, name: settingsSuite) }
        let settings = SettingsWindowController(state: { GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2, includeApp: true, statusMenu: 0, showToolTips: true) },
                                                hotkeys: GlobalHotkeyManager(defaults: settingsDefaults, backend: InertHotkeyBackend()), defaults: settingsDefaults,
                                                destinations: { PublishingDestinationList(defaultID: nil, destinations: []) })
        var closes = 0
        settings.onClose = { closes += 1 }
        settings.window.cancelOperation(nil)
        expect(closes == 1, "Settings: Escape (cancelOperation) closes the window")
    }

    // MARK: F. Custom views expose a focus ring and a mask, and the tab strip is one key view

    private static func customViewFocus() {
        let settingsSuite = "OpenSnapAccessibilityAudit.focus." + UUID().uuidString
        let defaults = TestDefaults(name: settingsSuite); defer { TestDefaults.dispose(defaults, name: settingsSuite) }
        let settings = SettingsWindowController(state: { GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2, includeApp: true, statusMenu: 0, showToolTips: true) },
                                                hotkeys: GlobalHotkeyManager(defaults: defaults, backend: InertHotkeyBackend()), defaults: defaults,
                                                destinations: { PublishingDestinationList(defaultID: nil, destinations: []) })
        settings.select(0)
        settings.window.contentView?.layoutSubtreeIfNeeded()
        let strip = settings.strip
        expect(strip.acceptsFirstResponder && strip.canBecomeKeyView, "Settings: the tab strip is one key view")
        expect(strip.buttons.allSatisfy { $0.refusesFirstResponder }, "Settings: the tab buttons leave the keys to the strip")
        expect(strip.focusRingType == .none && !strip.showsKeyboardFocus, "Settings: no ring while focus is not keyboard-driven")
        let arrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: settings.window.windowNumber, context: nil,
                                     characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124)!
        strip.keyDown(with: arrow)
        expect(strip.showsKeyboardFocus && strip.focusRingType == .none && !strip.tokenRing.layer.isHidden, "Settings: an arrow key puts keyboard focus on the strip and draws the token ring")
        expect(strip.tokenRing.target().width > 0 && strip.tokenRing.target().height > 0, "Settings: the strip's focus ring has an area")
        expect(!(strip.tokenRing.layer.path?.boundingBox.isEmpty ?? true) && strip.tokenRing.layer.lineWidth == StateStyles.focusRingWidth, "Settings: the strip draws a token-ring outline around the tab")
    }
    // MARK: G. Labels, status roles and the "Error:" prefix (OSN-062 steps 1 and 4, in the files outside the editor)

    private static func labelsAndStatus() {
        // Destinations: buttons say what they do, the Default pill is a labelled static text, status rows are static text.
        var dav = PublishingSettings(); dav.endpoint = "https://dav.example.invalid/shots"
        let work = PublishingDestination(name: "Work", settings: dav)
        let view = PublishingDestinationsView(editing: work)
        view.frame = NSRect(x: 0, y: 0, width: PublishingDestinationsView.sheetWidth, height: 600)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = view
        view.layoutSubtreeIfNeeded()
        expect([view.cancelButton, view.saveButton, view.testButton].allSatisfy { !Audit.label(of: $0).isEmpty }, "Destinations: the footer buttons are labelled")
        expect(Audit.label(of: view.saveButton) == "Save" && Audit.label(of: view.cancelButton) == "Cancel" && Audit.label(of: view.testButton) == "Test", "Destinations: Save, Cancel and Test are named by their titles")
        let pill = DefaultPillView()
        expect(pill.accessibilityLabel() == "Default destination" && pill.accessibilityRole() == .staticText, "Destinations: the Default pill is a labelled static text")
        let row = SettingsDestinationRow(name: "Work", transport: "WebDAV", isDefault: true)
        expect(row.accessibilityLabel() == "Work, WebDAV, Default" && row.accessibilityRole() == .row, "Settings: a destination row reads name, protocol and Default together: \(String(describing: row.accessibilityLabel()))")
        view.showStatus("The server refused it")
        expect(view.formResult.text.stringValue == "Error: The server refused it", "Destinations: an error is prefixed Error:")
        expect(view.formResult.accessibilityRole() == .staticText && view.formResult.accessibilityLabel()?.hasPrefix("Error:") == true, "Destinations: the status row is a static text that reads the error")
        view.showStatus("Error: already prefixed")
        expect(view.formResult.text.stringValue == "Error: already prefixed", "Destinations: the prefix is not doubled")
        view.showTestResult(ok: false, message: "No route to host")
        expect(view.formResult.text.stringValue == "Error: No route to host", "Destinations: a failed Test result is prefixed Error:")
        expect(view.formResult.glyph.image?.accessibilityDescription == "Error", "Destinations: the failure glyph is described, so the state is not colour alone")

        // Resize: the three mode segments, the validation line.
        let suite = "OpenSnapAccessibilityAudit.labels." + UUID().uuidString
        let defaults = TestDefaults(name: suite); defer { TestDefaults.dispose(defaults, name: suite) }
        let parent = parentWindow()
        let resize = ResizePanel(session: ResizePanelSession(size: CGSize(width: 800, height: 600), onApply: { _, _, _ in }), presets: ResizePresetStore(defaults: defaults))
        resize.show(attachedTo: parent)
        if let panel: NSPanel = private_(resize, "panel"), let widthField: NSTextField = private_(resize, "widthField"), let errorLabel: NSTextField = private_(resize, "errorLabel"),
           let modeControl: GlassChoiceGroup = private_(resize, "modeControl") {
            expect(modeControl.buttons.map(\.title) == ["Resize", "Crop", "Limit"], "Resize: the mode segments are labelled Resize, Crop and Limit")
            expect(errorLabel.accessibilityRole() == .staticText, "Resize: the validation line is a static text")
            widthField.stringValue = "abc"
            widthField.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: widthField))
            _ = press(Key.returnKey, on: panel)   // OK with an invalid width must not close the sheet and must say why
            expect(panel.sheetParent === parent && errorLabel.stringValue.hasPrefix("Error: "), "Resize: an invalid width keeps the sheet and shows an Error: line: \(errorLabel.stringValue)")
            _ = press(Key.escape, on: panel)
        } else { expect(false, "the Resize panel and its fields were found") }

        // Photos: the status line is a static text and a failed folder read begins Error:.
        let photoParent = parentWindow()
        let photos = PhotoBrowserCoordinator()
        photos.show(relativeTo: photoParent, onOpen: { _ in })
        if let status: NSTextField = private_(photos, "status") {
            expect(status.accessibilityRole() == .staticText, "Photos: the status line is a static text")
            photos.loadFolder(URL(fileURLWithPath: "/nonexistent-opensnap-a11y-folder-" + UUID().uuidString))
            spin(until: { status.stringValue.hasPrefix("Error: ") })
            expect(status.stringValue.hasPrefix("Error: "), "Photos: an unreadable folder reports Error: \(status.stringValue)")
        } else { expect(false, "the Photos status line was found") }
        photos.shutdown()

        // The shortcut sheet: an impossible binding is rejected with an Error: line in a static text.
        let hotkeySuite = "OpenSnapAccessibilityAudit.labels.hotkeys." + UUID().uuidString
        let hotkeyDefaults = TestDefaults(name: hotkeySuite); defer { TestDefaults.dispose(hotkeyDefaults, name: hotkeySuite) }
        let manager = GlobalHotkeyManager(defaults: hotkeyDefaults, backend: InertHotkeyBackend())
        let form = GlobalHotkeyForm(manager: manager, labelWidth: 200, width: 700)
        expect(form.statusField.accessibilityRole() == .staticText, "Shortcuts: the status line is a static text")
        form.keyPopup(for: .screen).selectItem(at: 3)
        _ = form.keyPopup(for: .screen).target?.perform(form.keyPopup(for: .screen).action, with: form.keyPopup(for: .screen))
        expect(form.statusField.stringValue.hasPrefix("Error: "), "Shortcuts: a binding with no modifier is rejected with an Error: line: \(form.statusField.stringValue)")
        expect(form.modifierToggles(for: .screen).allSatisfy { $0.accessibilityRole() == .checkBox && !Audit.label(of: $0).isEmpty }, "Shortcuts: the four modifier toggles are labelled check boxes")

        // Settings: the tab strip is a tab group of four radio buttons, one of them current.
        let settingsSuite = "OpenSnapAccessibilityAudit.labels.settings." + UUID().uuidString
        let settingsDefaults = TestDefaults(name: settingsSuite); defer { TestDefaults.dispose(settingsDefaults, name: settingsSuite) }
        let settings = SettingsWindowController(state: { GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2, includeApp: true, statusMenu: 0, showToolTips: true) },
                                                hotkeys: GlobalHotkeyManager(defaults: settingsDefaults, backend: InertHotkeyBackend()), defaults: settingsDefaults,
                                                destinations: { PublishingDestinationList(defaultID: nil, destinations: []) })
        settings.select(1)
        let strip = settings.strip
        expect(strip.accessibilityRole() == .tabGroup && strip.accessibilityLabel() == "Settings sections", "Settings: the strip is a tab group labelled Settings sections")
        expect((strip.accessibilityTabs()?.count ?? 0) == 4, "Settings: four tabs are exposed")
        expect(strip.buttons.allSatisfy { $0.accessibilityRole() == .radioButton && !Audit.label(of: $0).isEmpty }, "Settings: every tab is a labelled radio button")
        expect(strip.buttons.map { ($0.accessibilityValue() as? Int) ?? -1 } == [0, 1, 0, 0], "Settings: exactly the current tab reports value 1")

        // The choices: each radio set is a named radio group of radio buttons with one value; each check box says on or off.
        settings.select(0)
        settings.window.contentView?.layoutSubtreeIfNeeded()
        let presence = settings.general.presenceGroup!
        expect(presence.accessibilityRole() == .radioGroup && presence.accessibilityLabel() == "Show in" && (presence.accessibilityChildren() ?? []).count == 3,
               "Settings: Show in is a radio group of three")
        expect(presence.buttons.allSatisfy { $0.accessibilityRole() == .radioButton && !Audit.label(of: $0).isEmpty }, "Settings: every Show in choice is a labelled radio button")
        expect(presence.buttons.map { ($0.accessibilityValue() as? Int) ?? -1 } == [0, 0, 1], "Settings: exactly the chosen radio (Both) reports value 1")
        let boxes = [settings.general.snapCheckbox!, settings.general.hoverHintsCheckbox!, settings.general.keyboardTipsCheckbox!]
        expect(boxes.allSatisfy { $0.accessibilityRole() == .checkBox && !Audit.label(of: $0).isEmpty }, "Settings: the three General options are labelled check boxes")
        expect(boxes.map { ($0.accessibilityValue() as? Int) ?? -1 } == [1, 1, 0], "Settings: each check box reports its own value (snap and hover hints on, keyboard tips off)")
        let walked = Audit.audit(settings.window, surface: "Settings: General (choices)")
        expect(walked.violations.isEmpty && walked.controls >= 11, "Settings: the walker judged the choices and found nothing wrong:\n\(walked.description)")
        // A radio that cannot take the keyboard, with no key-taking owner above it, is caught on the real window.
        let victim = presence.buttons[2]
        victim.refusesFirstResponder = true
        let unreachable = Audit.audit(settings.window, surface: "Settings (seeded unreachable radio)").violations
        expect(unreachable.contains { $0.kind == .notKeyboardReachable && $0.label == "Both" }, "Settings: a radio that refuses the keyboard is caught: \(unreachable)")
        victim.refusesFirstResponder = false
        // And a check box with its name taken away is caught as unlabelled.
        let box = settings.general.hoverHintsCheckbox!
        let name = box.accessibilityLabel()
        box.setAccessibilityLabel(nil); box.makeIconOnly(name: "", derivesToolTip: false)
        expect(Audit.audit(settings.window, surface: "Settings (seeded unlabelled box)").violations.contains { $0.kind == .missingLabel }, "Settings: a check box with no name is caught")
        box.makeIconOnly(name: name ?? "", derivesToolTip: false); box.setAccessibilityLabel(name)
        expect(Audit.audit(settings.window, surface: "Settings (restored)").violations.isEmpty, "Settings: restoring the name clears it")
    }
}

private extension NSObject {
    /// Builder helper so a seeded view can be configured inside an expression.
    func with(_ configure: (Self) -> Void) -> Self { configure(self); return self }
}
#endif
