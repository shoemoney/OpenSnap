import AppKit
import CoreGraphics

/// Glass-choice captures (S50-S59). Every app-owned glass choice panel and group is drawn as a real window and measured: the
/// `glassPanel` record in each capture's meta JSON is what tools/check-eye-dump.py holds the run to (one glass container per panel,
/// nested glass 0, text >= 18 pt, a hovered / focused / chosen / disabled row where the capture promises one, and for a dismissal that the
/// panel is gone and focus is back on its opener). The slugs below are the checker's GLASS_SURFACES; tools/test-eye-dump-audit-guard.py
/// fails if the two lists drift.
///
/// Input rules: hover is `setHovered(_:)`, focus is `makeFirstResponder`, dismissal is a synthesized Escape key event handed to the panel's
/// own `sendEvent` (never `NSApp.sendEvent`, which the input fence swallows and counts as real input) with `cancelOperation` on the first
/// responder as the recorded fallback. No CGEvent, no AppleScript, no screen capture.
extension AuditRun {
    static let glassPanelPrefix = "GlassChoicePanel."

    /// The captures each glass surface must produce, in light and dark: the checker's GLASS_SURFACES, which tools/test-eye-dump-audit-guard.py
    /// compares with this table. Whatever a surface fails to take is recorded as a gap, so a silent skip cannot pass.
    static let glassRequired: [String: [String]] = [
        "S50": ["toolbox-rest", "toolbox-hover", "toolbox-focus", "toolbox-disabled", "toolbox-chosen", "toolbox-dismissed"],
        "S51": ["zoom-rest", "zoom-hover", "zoom-focus", "zoom-chosen", "zoom-actual-size", "zoom-dismissed"],
        "S52": ["upload-rest", "upload-hover", "upload-focus", "upload-chosen", "upload-busy", "upload-empty", "upload-dismissed"],
        "S53": ["color-rest", "color-hover", "color-focus", "color-custom", "color-dismissed"],
        "S54": ["size-rest", "size-hover", "size-focus", "size-pressed", "size-dismissed"],
        "S55": ["history-category-rest", "history-category-hover", "history-category-focus", "history-date-rest", "history-date-hover", "history-date-focus", "history-date-chosen", "history-date-dismissed", "history-dragas-rest", "history-dragas-hover", "history-dragas-focus", "history-dragas-chosen", "history-dragas-dismissed"],
        "S56": ["settings-tabs-rest", "settings-tabs-hover", "settings-tabs-focus", "settings-radios-rest", "settings-radios-hover", "settings-radios-focus", "settings-toggles-rest", "settings-toggles-hover", "settings-toggles-focus", "settings-actions-rest", "settings-actions-hover", "settings-actions-focus", "settings-actions-disabled"],
        "S57": ["resize-groups-rest", "resize-groups-hover", "resize-groups-focus", "resize-anchor-rest", "resize-anchor-hover", "resize-anchor-focus", "resize-preset-rest", "resize-preset-hover", "resize-preset-focus", "resize-preset-chosen", "resize-preset-dismissed"],
        "S58": ["destination-protocol-rest", "destination-protocol-hover", "destination-protocol-focus", "destination-protocol-dismissed", "destination-source-rest", "destination-source-hover", "destination-source-focus", "destination-source-dismissed", "destination-acl-off", "destination-acl-on", "destination-width-640", "destination-width-560"],
        "S59": ["footer-original-on", "footer-original-off", "footer-original-hidden"],
        "S60": ["capture-enable-on", "capture-enable-off", "capture-modifiers-chosen", "capture-modifiers-disabled", "capture-clear-all", "capture-key-rest", "capture-key-focus", "capture-key-chosen", "capture-key-scroll", "capture-key-dismissed"],
    ]

    func verifyGlassCaptures(_ id: String) {
        for slug in AuditRun.glassRequired[id] ?? [] where !FileManager.default.fileExists(atPath: dir.appendingPathComponent("meta/\(stemFor(id, slug)).json").path) {
            gap(id, "glass / \(slug)", "the required glass capture \(slug) was not taken")
        }
    }


    // MARK: finding things

    func glassPanelWindow(_ identifier: String) -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == AuditRun.glassPanelPrefix + identifier }
    }

    var anyGlassPanelWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && ($0.identifier?.rawValue ?? "").hasPrefix(AuditRun.glassPanelPrefix) }
    }

    /// Reading order: top to bottom, then left to right (windows are not flipped, so a larger maxY is higher).
    func readingOrder(_ views: [NSView]) -> [NSView] {
        func key(_ view: NSView) -> (Int, CGFloat) {
            let frame = view.convert(view.bounds, to: nil)
            return (-Int((frame.midY / 8).rounded()), frame.minX)
        }
        return views.sorted { key($0) < key($1) }
    }

    func visibleTitle(_ button: NSButton) -> String {
        // A glass choice draws its words in a label subview; its own title stays empty for VoiceOver.
        if let choice = button as? GlassChoiceButton, !choice.titleLabel.stringValue.isEmpty { return choice.titleLabel.stringValue }
        if !button.title.isEmpty { return button.title }
        if button.attributedTitle.length > 0 { return button.attributedTitle.string }
        return button.accessibilityLabel() ?? ""
    }

    /// The choice rows under `root`, in reading order: glass choice buttons, any other command button that carries a visible title (an action
    /// plate), and any other button the panel's own plates hold (a colour swatch, a size preset) that names itself for VoiceOver.
    func glassRows(in root: NSView) -> [NSButton] {
        var found: [NSButton] = []
        func walk(_ view: NSView) {
            if view.isHidden || view.alphaValue <= 0.01 { return }
            if let button = view as? NSButton, !(view is NSPopUpButton) {
                if button is GlassChoiceButton || !visibleTitle(button).isEmpty { found.append(button) }
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return readingOrder(found) as! [NSButton]
    }

    /// Whether the row lies wholly inside its window's content (a row scrolled out of a panel's clip lies outside it).
    func isWhollyInView(_ row: NSButton) -> Bool {
        guard let content = row.window?.contentView else { return false }
        let inWindow = row.convert(row.bounds, to: nil)
        let visible = content.convert(content.bounds, to: nil)
        return visible.insetBy(dx: -0.5, dy: -0.5).contains(inWindow)
    }

    func isChosen(_ row: NSButton) -> Bool {
        if let choice = row as? GlassChoiceButton { return choice.isChosen }
        if let value = row.accessibilityValue() as? NSNumber, value.intValue == 1 { return true }
        return row.state == .on
    }

    func isHovered(_ row: NSButton) -> Bool {
        switch row {
        case let command as CommandButton: return command.isHovered
        case let swatch as BezelColorButton: return swatch.isHovered
        case let preset as SizePresetButton: return preset.isHovered
        default: return false
        }
    }

    /// Offers keyboard focus to `row` and reports what happened. `NSWindow.makeFirstResponder` cannot be the judge: on this macOS it hands the keyboard to
    /// a disabled button although `acceptsFirstResponder` is false (measured with a bare NSButton subclass), so the row's own `acceptsFirstResponder` is
    /// the eligibility answer and the forced focus is recorded as a fact. The previous responder is put back afterwards.
    func offerFocus(in host: NSWindow, to row: NSButton) -> (took: Bool, facts: [String: Any]) {
        let before = host.firstResponder
        let accepted = host.makeFirstResponder(row)
        let forced = accepted && host.firstResponder === row
        if forced { host.makeFirstResponder(before) }
        return (row.acceptsFirstResponder, ["makeFirstResponderReturned": accepted, "makeFirstResponderForcedFocus": forced, "rowIsEnabled": row.isEnabled,
                                            "rowAcceptsFirstResponder": row.acceptsFirstResponder, "firstResponderBefore": before.map { String(describing: type(of: $0)) } ?? "none"])
    }

    /// Walks the panel with synthesized Down-arrow key events handed to its own `sendEvent` and returns the row indexes the keyboard visited,
    /// so a disabled row that the panel's own navigation lands on shows up. Restores the first responder it found.
    func keyboardWalk(_ panel: NSWindow, rows: [NSButton]) -> [Int] {
        let start = panel.firstResponder
        var visited: [Int] = []
        for _ in 0...rows.count {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                               context: nil, characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), charactersIgnoringModifiers: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                                               isARepeat: false, keyCode: 125) else { break }
            panel.sendEvent(event)
            if let index = rows.firstIndex(where: { panel.firstResponder === $0 }) { visited.append(index) }
        }
        panel.makeFirstResponder(start)
        return visited
    }

    /// Hover as the app sees it: each kind of row has its own `setHovered(_:)` test seam; nothing here moves a real pointer.
    func setHovered(_ row: NSButton, _ hovered: Bool) {
        switch row {
        case let command as CommandButton: command.setHovered(hovered)
        case let swatch as BezelColorButton: swatch.setHovered(hovered)
        case let preset as SizePresetButton: preset.setHovered(hovered)
        default: break
        }
    }

    /// (containers, plates, nested) of the glass views under `root`. Nested counts a glass view or container that has a glass plate above it.
    func glassCounts(in root: NSView) -> (containers: Int, plates: Int, nested: Int) {
        var containers = 0, plates = 0, nested = 0
        func walk(_ view: NSView, insidePlate: Bool) {
            let isContainer = view is NSGlassEffectContainerView, isPlate = view is NSGlassEffectView
            if isContainer { containers += 1; if insidePlate { nested += 1 } }
            if isPlate { plates += 1; if insidePlate { nested += 1 } }
            for sub in view.subviews { walk(sub, insidePlate: insidePlate || isPlate) }
        }
        walk(root, insidePlate: false)
        return (containers, plates, nested)
    }

    /// The smallest point size of any text drawn under `root` (button titles, labels, text views) and which view draws it, nil when there is none.
    func smallestText(in root: NSView) -> (size: Double, source: String)? {
        var smallest: (size: CGFloat, source: String)?
        func note(_ font: NSFont?, _ view: NSView, _ text: String) {
            guard let font, smallest == nil || font.pointSize < smallest!.size else { return }
            smallest = (font.pointSize, "\(type(of: view)) '\(text.prefix(30))' id=\(view.identifier?.rawValue ?? "-")")
        }
        func walk(_ view: NSView) {
            if view.isHidden || view.alphaValue <= 0.01 { return }
            if let button = view as? NSButton {
                if button.attributedTitle.length > 0 {
                    button.attributedTitle.enumerateAttribute(.font, in: NSRange(location: 0, length: button.attributedTitle.length)) { value, _, _ in note(value as? NSFont, view, button.attributedTitle.string) }
                    if button.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) == nil { note(button.font, view, button.attributedTitle.string) }
                } else if !button.title.isEmpty { note(button.font, view, button.title) }
            } else if let field = view as? NSTextField, !field.stringValue.isEmpty {
                // AppKit's own title field inside a standard button reports its default 13 pt, not what the cell draws; the button's font is read above.
                if String(describing: type(of: field)) != "NSButtonTextField" { note(field.font, view, field.stringValue) }
            } else if let text = view as? NSTextView, !text.string.isEmpty {
                note(text.font, view, text.string)
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return smallest.map { (Double($0.size), $0.source) }
    }

    func minimumTextSize(in root: NSView) -> Double? { smallestText(in: root)?.size }

    // MARK: truncation measurements

    /// Custom-drawn or plain text the glass records do NOT measure for truncation (their font size is still read when an NSButton or NSTextField
    /// carries them). Stated in every record so the no-truncation claim stays bounded to what is measured: GlassChoiceButton title and shortcut
    /// labels, GlassPopUpButton faces, and the cell titles of other titled command buttons.
    static let unmeasuredText = [
        "SegmentedToggle segments (the footer PNG | JPG toggle)", "the Size panel readout and header", "colour swatch glyphs and the Custom colour chip image",
        "ResizeAnchorGrid cell dots and ring (no text)", "plain NSTextField labels, captions, status and the Resize dimension fields",
        "Size preset stroke glyphs (no text)", "the Toolbox face (icon and chevron, no title)", "menu-row header labels (GlassChoiceLabel)", "tooltips and VoiceOver text"
    ]

    func labelMetric(_ label: NSTextField, kind: String) -> [String: Any] {
        label.layoutSubtreeIfNeeded()
        let fitting = label.fittingSize, frame = label.frame.size
        let wraps = label.maximumNumberOfLines != 1
        let textWidth = label.attributedStringValue.size().width
        let fits = frame.width > 0 && fitting.width <= frame.width + 0.5 && fitting.height <= frame.height + 0.5 && (wraps || textWidth <= frame.width + 0.5)
        return ["title": label.stringValue, "kind": kind, "fittingSize": [Double(fitting.width), Double(fitting.height)], "frameSize": [Double(frame.width), Double(frame.height)],
                "textWidth": Double(textWidth), "fits": fits]
    }

    /// The face of every GlassPopUpButton at or under `root`, read from the pop-up's own `faceTextMetrics` / `faceTextFits`.
    func popUpFaceMetrics(in root: NSView) -> [[String: Any]] {
        var faces: [[String: Any]] = []
        func walk(_ view: NSView) {
            if view.isHidden || view.alphaValue <= 0.01 { return }
            if let popup = view as? GlassPopUpButton {
                // The pop-up's own measurement: the title it draws, the font, what that needs and the rectangle it is drawn in (after its face
                // padding and chevron column, which the zoom control tightens).
                let metrics = popup.faceTextMetrics
                faces.append(["title": metrics.title, "kind": "pop-up face", "font": fontInfo(metrics.font) as Any,
                              "fittingSize": [Double(metrics.needed.width), Double(metrics.needed.height)],
                              "frameSize": [Double(metrics.available.width), Double(metrics.available.height)],
                              "textWidth": Double(metrics.needed.width), "fits": popup.faceTextFits && metrics.available.width > 0, "identifier": popup.panelIdentifier,
                              "facePadding": Double(popup.facePadding), "chevronColumn": Double(popup.chevronColumn), "source": "GlassPopUpButton.faceTextMetrics"])
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return faces
    }

    // MARK: the record

    /// What the harness measured on a panel or group, for the checker. `rowsRoot` limits the rows to one group's plate; the glass counts
    /// always cover `host`'s whole content, so nested glass anywhere in the window is seen.
    func glassRecord(kind: String, identifier: String, variant: String, host: NSWindow, rowsRoot: NSView? = nil, extraFaceRoots: [NSView] = [], extra: [String: Any] = [:]) -> [String: Any] {
        let content = host.contentView ?? NSView()
        let rows = glassRows(in: rowsRoot ?? content)
        let counts = glassCounts(in: content)
        func index(where test: (NSButton) -> Bool) -> Int? { rows.firstIndex(where: test) }
        var record: [String: Any] = [
            "kind": kind, "identifier": identifier, "variant": variant, "windowIdentifier": host.identifier?.rawValue ?? "",
            "rowTitles": rows.map { visibleTitle($0) }, "rowClasses": rows.map { String(describing: type(of: $0)) },
            "chosenIndexes": rows.indices.filter { isChosen(rows[$0]) },
            "disabledRows": rows.indices.filter { !rows[$0].isEnabled },
            "glassContainerCount": counts.containers, "plateCount": counts.plates, "nestedGlassCount": counts.nested,
            "panelFrame": rectJSON(host.frame), "firstResponder": host.firstResponder.map { String(describing: type(of: $0)) } ?? "none",
            "isKey": host.isKeyWindow
        ]
        // No title may be cut: a label fits when what it needs (fittingSize, and the text's own width) is within the frame that draws it.
        var labels: [[String: Any]] = []
        for case let choice as GlassChoiceButton in rows where !choice.isHiddenOrHasHiddenAncestor {
            labels.append(labelMetric(choice.titleLabel, kind: "choice title"))
            if !choice.shortcutLabel.isHidden, !choice.shortcutLabel.stringValue.isEmpty { labels.append(labelMetric(choice.shortcutLabel, kind: "shortcut")) }
        }
        // A command button that is not a glass choice (an action plate, a tab) draws its title in the cell: measured against the cell's title rectangle.
        for row in rows where !(row is GlassChoiceButton) && !(row is GlassPopUpButton) && !row.isHiddenOrHasHiddenAncestor && !row.title.isEmpty && row.imagePosition != .imageOnly {
            guard let cell = row.cell else { continue }
            let font = row.font ?? DesignTokens.Typography.font(.body)
            let textWidth = ceil((row.title as NSString).size(withAttributes: [.font: font]).width)
            let available = cell.titleRect(forBounds: row.bounds).width
            labels.append(["title": row.title, "kind": "button title", "fittingSize": [Double(textWidth), Double(ceil(font.boundingRectForFont.height))],
                           "frameSize": [Double(available), Double(row.bounds.height)], "textWidth": Double(textWidth), "fits": textWidth <= available + 0.5])
        }
        // Pop-up faces (a GlassPopUpButton draws its title in the width left by its padding and chevron) are labels too: the faces under the scope
        // and the opener's own face, whose window the panel record does not cover.
        var faces: [[String: Any]] = []
        for scope in [rowsRoot ?? content] + extraFaceRoots { faces += popUpFaceMetrics(in: scope) }
        record["labelMetrics"] = labels + faces
        record["faceTitles"] = faces.compactMap { $0["title"] as? String }
        record["truncatedRows"] = (labels + faces).filter { ($0["fits"] as? Bool) != true }.compactMap { $0["title"] as? String }
        record["unmeasuredText"] = AuditRun.unmeasuredText
        if kind == "panel", variant != "dismissed" {
            // Placement: where the panel is and where the window it hangs from is (screen coordinates, bottom-left origin, [x, y, width, height]), plus the
            // parent's content area (the title bar is what lies above it) and the opener's frame, so a panel that hangs outside its parent can be judged.
            let parent = host.parent ?? extraFaceRoots.first?.window
            if let parent {
                record["parentFrame"] = rectJSON(parent.frame)
                record["parentContentFrame"] = rectJSON(parent.convertToScreen(parent.contentLayoutRect))
                record["parentClass"] = String(describing: type(of: parent))
                // The part of the parent that is on screen, and the screen's own visible area: a panel that can fit in the visible parent must, and one
                // that cannot falls back to the screen. Derived from the frames until the host reports its own containment.
                let screenVisible = (parent.screen ?? NSScreen.main)?.visibleFrame
                let visibleParent = screenVisible.map { parent.frame.intersection($0) } ?? parent.frame
                if let screenVisible { record["screenVisibleFrame"] = rectJSON(screenVisible) }
                record["parentVisibleFrame"] = rectJSON(visibleParent)
                record["containmentDerived"] = host.frame.width <= visibleParent.width + 1 ? "parent" : "screenFallback"
                record["containmentDerivedFrom"] = "the frames: panel width <= visible parent width"
            }
            // What the product says: the live host's own placement (nil when this window is not the host's panel).
            if let live = GlassPanelHost.current, live.window === host, let placement = live.placement {
                record["containmentReported"] = placement.containment == .parent ? "parent" : "screenFallback"
                record["placementEdge"] = String(describing: placement.edge)
            }
            if let opener = extraFaceRoots.first, let openerWindow = opener.window {
                record["openerFrame"] = rectJSON(openerWindow.convertToScreen(opener.convert(opener.bounds, to: nil)))
            }
            // Height cap: how many rows the panel has, how many are wholly in view, and whether the host scrolls them.
            record["totalRows"] = rows.count
            record["visibleRows"] = rows.filter { isWhollyInView($0) }.count
            record["hostScrolls"] = GlassPanelHost.current?.window === host ? (GlassPanelHost.current?.scrolls ?? false) : false
        }
        if let hovered = index(where: { isHovered($0) }) { record["hoveredRow"] = hovered }
        if let focused = index(where: { host.firstResponder === $0 }) { record["focusedRow"] = focused }
        if let smallest = smallestText(in: rowsRoot ?? content) { record["minFontSize"] = smallest.size; record["minFontSource"] = smallest.source }
        for (key, value) in extra { record[key] = value }
        return record
    }

    // MARK: driving a panel

    /// One panel under test: how to open it, what opens it, and where its captures go.
    struct GlassPanelScript {
        let id: String, surface: String, identifier: String, base: String
        let opener: NSView
        let refs: [String]
        let open: () -> Void
        /// The native menu the opener would show in a build without the panel. If the open call blocks in it, the watchdog cancels tracking.
        var nativeMenu: NSMenu?
        /// The window the opener lives in (its first responder is what dismissal must restore); the editor window unless a sheet or Settings hosts it.
        var host: NSWindow?
        /// What is imaged behind the panel, frontmost first: the editor window unless the opener lives in a sheet.
        var context: [NSWindow]?
    }

    struct OpenedGlassPanel {
        let panel: NSWindow
        let responderBefore: NSResponder?
        let openerHadFocus: Bool
        let script: GlassPanelScript
    }

    /// Puts the keyboard on the opener, opens the panel, and returns it, or nil (with a gap) when no glass panel appeared. A build that still
    /// opens a native menu would block here, so a watchdog cancels menu tracking after 1.5 s and the caller records the gap.
    func openGlassPanel(_ script: GlassPanelScript, recordGap: Bool = true) -> OpenedGlassPanel? {
        let owner = script.host ?? window
        owner.makeKeyAndOrderFront(nil)
        let accepted = owner.makeFirstResponder(script.opener)
        let before = owner.firstResponder
        let hadFocus = accepted && before === script.opener
        let watchdog = Timer(timeInterval: 1.5, repeats: false) { [self] _ in
            MainActor.assumeIsolated {
                if glassPanelWindow(script.identifier) == nil { script.nativeMenu?.cancelTracking(); NSApp.mainMenu?.cancelTracking() }
            }
        }
        RunLoop.main.add(watchdog, forMode: .common)
        script.open()
        watchdog.invalidate()
        pump(0.5)
        guard let panel = glassPanelWindow(script.identifier) else {
            if recordGap { gap(script.id, script.surface + " / " + script.base, "the glass panel \(script.identifier) did not appear (a native menu or nothing opened instead)") }
            return nil
        }
        return OpenedGlassPanel(panel: panel, responderBefore: before, openerHadFocus: hadFocus, script: script)
    }

    /// Captures the open panel over the editor, with its glassPanel record.
    @discardableResult
    func shootGlassPanel(_ id: String, _ slug: String, surface: String, state: String, panel: NSWindow, opener: NSView?, refs: [String],
                         variant: String = "rest", identifier: String = "", extra: [String: Any] = [:], alsoPanelOnly: Bool = false, context: [NSWindow]? = nil) -> String? {
        let record = glassRecord(kind: "panel", identifier: identifier.isEmpty ? (panel.identifier?.rawValue ?? "") : identifier, variant: variant, host: panel,
                                 extraFaceRoots: opener.map { [$0] } ?? [], extra: extra)
        let stem = shoot(id, slug, surface: surface, state: state, windows: [panel] + (context ?? [window]), refs: refs, settle: 0.3, extra: ["glassPanel": record])
        if alsoPanelOnly {
            shoot(id, slug + "-only", surface: surface, state: state + " (the panel window alone)", windows: [panel], refs: refs, settle: 0.1, extra: ["glassPanel": record])
        }
        return stem
    }

    /// Sends Escape to the panel the way a key press reaches a window: a synthesized key event through `NSWindow.sendEvent`. Returns how it closed.
    func sendEscape(to panel: NSWindow) -> String {
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: panel.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                        isARepeat: false, keyCode: 53) {
            panel.sendEvent(event)
            pump(0.4)
            if !panel.isVisible { return "synthesized Escape key event through NSWindow.sendEvent" }
        }
        _ = panel.firstResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: nil)
        pump(0.4)
        return panel.isVisible ? "Escape did not close the panel" : "cancelOperation on the first responder (the key event alone did not close it)"
    }

    /// Escape, then the proof: the panel window is gone, the host registry is clear, and the keyboard is back on the opener.
    @discardableResult
    func dismissGlassPanel(_ id: String, _ slug: String, surface: String, state: String, script: GlassPanelScript, opened: OpenedGlassPanel, capture: Bool = true) -> Bool {
        let route = sendEscape(to: opened.panel)
        pump(0.3)
        let gone = glassPanelWindow(script.identifier) == nil && !opened.panel.isVisible
        let owner = script.host ?? window
        let returned = owner.firstResponder === opened.responderBefore
        if capture {
            let record = glassRecord(kind: "panel", identifier: script.identifier, variant: "dismissed", host: owner, rowsRoot: NSView(), extraFaceRoots: [script.opener], extra: [
                "panelGone": gone, "focusReturned": returned, "openerHadFocus": opened.openerHadFocus, "dismissedBy": route,
                "hostRegistryClear": GlassPanelHost.current == nil, "openerClass": String(describing: type(of: script.opener)),
                "firstResponderIsOpener": owner.firstResponder === script.opener,
                "firstResponderIdentifier": (owner.firstResponder as? NSView).flatMap { $0.identifier?.rawValue ?? ($0 as? GlassPopUpButton)?.panelIdentifier } ?? String(describing: owner.firstResponder.map { type(of: $0) }),
                "glassContainerCount": 0, "plateCount": 0, "nestedGlassCount": 0])
            shoot(id, slug, surface: surface, state: state, windows: script.context ?? [window], refs: script.refs, settle: 0.2, extra: ["glassPanel": record])
        }
        return gone && returned
    }

    /// The standard hover, focus and (when a row is disabled) disabled captures of one open panel.
    func glassPanelStates(_ script: GlassPanelScript, _ opened: OpenedGlassPanel, restState: String) {
        let panel = opened.panel
        let rows = glassRows(in: panel.contentView ?? NSView())
        // A keyboard or VoiceOver open puts focus on a row; the rest capture is the mouse-style open, so the ring waits for the focus capture.
        panel.makeFirstResponder(nil)
        shootGlassPanel(script.id, script.base + "-rest", surface: script.surface, state: restState, panel: panel, opener: script.opener, refs: script.refs,
                        identifier: script.identifier, alsoPanelOnly: true, context: script.context)
        let enabled = rows.indices.filter { rows[$0].isEnabled }
        // Hover a row that is neither the first nor chosen, so the fill is visibly the hover's.
        if let target = enabled.first(where: { !isChosen(rows[$0]) && $0 > 0 }) ?? enabled.first {
            setHovered(rows[target], true)
            shootGlassPanel(script.id, script.base + "-hover", surface: script.surface, state: "\(restState); row \(target) (\(visibleTitle(rows[target]))) hovered", panel: panel,
                            opener: script.opener, refs: script.refs, variant: "hover", identifier: script.identifier, context: script.context)
            setHovered(rows[target], false)
        }
        if let first = enabled.first {
            panel.makeKeyAndOrderFront(nil)
            let took = panel.makeFirstResponder(rows[first])
            shootGlassPanel(script.id, script.base + "-focus", surface: script.surface, state: "\(restState); keyboard focus on row \(first) (\(visibleTitle(rows[first])))", panel: panel,
                            opener: script.opener, refs: script.refs, variant: "focus", identifier: script.identifier, extra: ["focusAccepted": took], context: script.context)
        }
        glassDisabledState(script, opened, restState: restState)
    }

    /// The disabled capture of an open panel: a disabled row hovered and offered the keyboard (its own `acceptsFirstResponder` is the judge, and an
    /// arrow-key walk through the panel must never land on it). Returns false when no row is disabled.
    @discardableResult
    func glassDisabledState(_ script: GlassPanelScript, _ opened: OpenedGlassPanel, restState: String, extra: [String: Any] = [:]) -> Bool {
        let panel = opened.panel
        let rows = glassRows(in: panel.contentView ?? NSView())
        guard let off = rows.indices.first(where: { !rows[$0].isEnabled }) else { return false }
        setHovered(rows[off], true)
        let offer = offerFocus(in: panel, to: rows[off])
        let walked = keyboardWalk(panel, rows: rows)
        let disabled = Set(rows.indices.filter { !rows[$0].isEnabled })
        shootGlassPanel(script.id, script.base + "-disabled", surface: script.surface, state: "\(restState); disabled row \(off) (\(visibleTitle(rows[off]))) hovered and offered focus; the arrow keys walked past it",
                        panel: panel, opener: script.opener, refs: script.refs, variant: "disabled", identifier: script.identifier,
                        extra: offer.facts.merging(["disabledTookFocus": offer.took || !disabled.isDisjoint(with: walked), "keyboardWalk": walked]) { $1 }.merging(extra) { $1 }, context: script.context)
        setHovered(rows[off], false)
        return true
    }

    // MARK: S50 Toolbox

    func s50() {
        defer { verifyGlassCaptures("S50") }
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Glass Toolbox")
        let named = addAllAnnotationKinds(scale: 1)
        guard let toolbox = firstView(of: ToolboxPopUpButton.self) else { gap("S50", "Toolbox panel", "the Toolbox button was not found"); return }
        let script = GlassPanelScript(id: "S50", surface: "Toolbox panel", identifier: "Toolbox", base: "toolbox", opener: toolbox,
                                      refs: ["ModernEditorChrome.swift|final class ToolboxPopUpButton", "App.swift|func bezelToolbox()"], open: { toolbox.openMenu() }, nativeMenu: toolbox.menu)
        // Rest, hover and focus: nothing selected.
        canvas.selection = []
        app.setTool(.arrow)
        guard let opened = openGlassPanel(script) else { return }
        glassPanelStates(script, opened, restState: "Toolbox panel open on a drawing with nothing selected")
        let tookDisabled = FileManager.default.fileExists(atPath: dir.appendingPathComponent("meta/\(stemFor("S50", "toolbox-disabled")).json").path)
        dismissGlassPanel("S50", "toolbox-dismissed", surface: script.surface, state: "Toolbox panel dismissed with Escape: gone, focus back on the Toolbox button", script: script, opened: opened)
        // Disabled: a row that needs a selection would do, but no Toolbox row depends on one in this build. The validation that does exist refuses the
        // Fill, Shadow and Text Style rows while a frame capture is in progress; the app flag is set (nothing is captured) and cleared again.
        if !tookDisabled {
            app.frameCaptureInProgress = true
            pump(0.2)
            if let refused = openGlassPanel(script) {
                glassDisabledState(script, refused, restState: "Toolbox panel while a frame capture is in progress (validation refuses the style rows)", extra: ["disabledReason": "frameCaptureInProgress"])
                dismissGlassPanel("S50", "toolbox-dismissed-refused", surface: script.surface, state: "", script: script, opened: refused, capture: false)
            }
            app.frameCaptureInProgress = false
            pump(0.2)
        }
        // Chosen: a filled shape selected and the Rectangle tool current, so the toggle rows read on.
        if let filled = named["rectangle-filled"] { canvas.selection = [filled.id] }
        app.setTool(.rectangle)
        pump(0.2)
        guard let again = openGlassPanel(script) else { return }
        shootGlassPanel("S50", "toolbox-chosen", surface: script.surface, state: "Toolbox panel with a filled rectangle selected: the toggle and tool rows that are on", panel: again.panel,
                        opener: toolbox, refs: script.refs, variant: "chosen", identifier: "Toolbox")
        dismissGlassPanel("S50", "toolbox-dismissed-2", surface: script.surface, state: "", script: script, opened: again, capture: false)
    }

    // MARK: S51 Zoom

    func s51() {
        defer { verifyGlassCaptures("S51") }
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Glass Zoom")
        guard let zoom = app.zoomControl as? GlassPopUpButton else { gap("S51", "Zoom panel", "the zoom control is not a GlassPopUpButton"); return }
        let script = GlassPanelScript(id: "S51", surface: "Zoom panel", identifier: zoom.panelIdentifier, base: "zoom", opener: zoom,
                                      refs: ["ModernEditorChrome.swift|final class ZoomPopUpButton", "App+ModernChrome.swift|zoomControl.addItems"], open: { zoom.openChoices(keyboard: false) }, nativeMenu: zoom.menu)
        // A computed Fit row is part of the choices: fit the drawing to the window first.
        app.fitCanvasToWindow()
        pump(0.3)
        guard let opened = openGlassPanel(script) else { return }
        glassPanelStates(script, opened, restState: "Zoom panel open with a computed Fit row chosen")
        shootGlassPanel("S51", "zoom-chosen", surface: script.surface, state: "Zoom panel: the computed Fit row is the chosen row", panel: opened.panel, opener: zoom, refs: script.refs, variant: "chosen", identifier: zoom.panelIdentifier)
        dismissGlassPanel("S51", "zoom-dismissed", surface: script.surface, state: "Zoom panel dismissed with Escape: gone, focus back on the zoom button", script: script, opened: opened)
        // Actual Size on needs a shot too large for the window (the command refuses otherwise): the toggle row is chosen and the face still shows a percentage.
        guard loadLargeShot(name: "Glass Zoom large") != nil else { gap("S51", "Zoom panel / actual size", "no synthetic size made isLargeShot true"); return }
        app.toggleActualSize()
        pump(0.6)
        guard app.isActualSize else { gap("S51", "Zoom panel / actual size", "Actual Size refused on a large shot (canToggleActualSize was false)"); return }
        // The app disables the zoom pop-up while Actual Size is on (AppViewport: zoomControl.isEnabled = !isActualSize), so `openChoices` refuses and a user
        // cannot open its choices then. To draw the toggle row's chosen state the panel is presented directly from the pop-up's own `choicePanel`
        // (above the footer, `.maxY`), and the record says the app had the control disabled. The control itself is never re-enabled.
        let enabledByApp = zoom.isEnabled
        let direct = GlassPanelScript(id: script.id, surface: script.surface, identifier: script.identifier, base: script.base, opener: zoom, refs: script.refs,
                                  open: { zoom.choicePanel.present(relativeTo: zoom, preferredEdge: .maxY, keyboard: false) }, nativeMenu: nil)
        if let again = openGlassPanel(direct) {
            let face = zoom.faceTitle
            let percent = face.range(of: #"^\d+%$"#, options: .regularExpression) != nil
            shootGlassPanel("S51", "zoom-actual-size", surface: script.surface, state: "Zoom panel while Actual Size is on: the Actual Size toggle row is chosen and the face shows \(face)", panel: again.panel,
                            opener: zoom, refs: script.refs, variant: "chosen", identifier: zoom.panelIdentifier,
                            extra: ["actualSizeOn": app.isActualSize, "faceTitleNow": face, "faceShowsPercentage": percent, "zoomEnabledByApp": enabledByApp, "openedDirectly": true])
            dismissGlassPanel("S51", "zoom-dismissed-2", surface: script.surface, state: "", script: direct, opened: again, capture: false)
        }
        app.leaveActualSize()
    }

    // MARK: S52 Upload

    func s52() {
        defer { verifyGlassCaptures("S52") }
        guard let share = app.webpostButton else { gap("S52", "Upload panel", "the Upload (Webpost) button was not found"); return }
        let refs = ["App.swift|func uploadDestinationMenuItems", "App.swift|func rebuildUploadMenu", "OriginalActionButton.swift|var menuPresenter"]
        let script = GlassPanelScript(id: "S52", surface: "Upload panel", identifier: "Upload", base: "upload", opener: share, refs: refs,
                                      open: { _ = share.accessibilityPerformShowMenu() }, nativeMenu: share.menu)
        // Empty state first (no destination saved): the disabled "No destination configured" row.
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Glass Upload")
        if let menu = share.menu { app.rebuildUploadMenu(menu) }
        if let opened = openGlassPanel(script) {
            let rows = glassRows(in: opened.panel.contentView ?? NSView())
            let off = rows.firstIndex { !$0.isEnabled }
            if let off { setHovered(rows[off], true) }
            let offer = off.map { offerFocus(in: opened.panel, to: rows[$0]) }
            let walked = keyboardWalk(opened.panel, rows: rows)
            let walkedOntoDisabled = walked.contains { !rows[$0].isEnabled }
            shootGlassPanel("S52", "upload-empty", surface: script.surface, state: "Upload panel with no destination saved: the disabled No destination configured row, Destination Settings… and Share with macOS…",
                            panel: opened.panel, opener: share, refs: refs, variant: "disabled", identifier: "Upload",
                            extra: (offer?.facts ?? [:]).merging(["disabledTookFocus": (offer?.took ?? false) || walkedOntoDisabled, "keyboardWalk": walked]) { $1 })
            dismissGlassPanel("S52", "upload-dismissed-empty", surface: script.surface, state: "", script: script, opened: opened, capture: false)
        }
        // Three fake destinations, Example S3 the default (checked): rest, hover, focus, then a different default for the chosen capture.
        syntheticDestinations()
        if let menu = share.menu { app.rebuildUploadMenu(menu) }
        guard let opened = openGlassPanel(script) else { return }
        glassPanelStates(script, opened, restState: "Upload panel with three fake destinations, the default checked")
        let ids = (try? AppDelegate.publishingStore.load().destinations.map(\.id)) ?? []
        dismissGlassPanel("S52", "upload-dismissed", surface: script.surface, state: "Upload panel dismissed with Escape: gone, focus back on the Upload button", script: script, opened: opened)
        if ids.count > 1 { app.setDefaultDestination(ids[1]) }
        pump(0.2)
        if let again = openGlassPanel(script) {
            shootGlassPanel("S52", "upload-chosen", surface: script.surface, state: "Upload panel after the default was switched to the second destination: the check follows it", panel: again.panel,
                            opener: share, refs: refs, variant: "chosen", identifier: "Upload")
            dismissGlassPanel("S52", "upload-dismissed-2", surface: script.surface, state: "", script: script, opened: again, capture: false)
        }
        if let first = ids.first { app.setDefaultDestination(first) }
        // Busy: an upload in flight offers Cancel Upload. The uploader is a stub that waits; nothing leaves the process.
        let gate = UploadGate()
        gate.mode = "wait"
        app.publishing.clipboardWriter = { _ in }
        app.linkOpener = { _ in }
        app.publishing.uploader = { _, _, plan, _ in
            _ = gate.release.wait(timeout: .now() + 8)
            return plan.publicURL ?? plan.remoteURL
        }
        app.uploadState = .idle
        app.publishImage()
        pump(0.8)
        if let busy = openGlassPanel(script) {
            shootGlassPanel("S52", "upload-busy", surface: script.surface, state: "Upload panel while an upload runs: Cancel Upload leads the rows", panel: busy.panel, opener: share, refs: refs,
                            variant: "busy", identifier: "Upload")
            dismissGlassPanel("S52", "upload-dismissed-busy", surface: script.surface, state: "", script: script, opened: busy, capture: false)
        }
        gate.release.signal()
        pump(1.5)
        app.expireUploadSuccess()
        pump(0.3)
    }

    // MARK: S59 footer Original size toggle

    /// The footer's glass "Original size" toggle on a large shot: on, off, and at 980 pt during an upload, where the status slot reflows and hides it.
    /// The record names the toggle row, its chosen state and its visibility, measured on the footer itself.
    func s59() {
        defer { verifyGlassCaptures("S59") }
        let refs = ["App+ModernChrome.swift|dragOriginalControl", "ModernEditorChrome.swift|statusRow", "AppViewport.swift|var isLargeShot"]
        func footerRecord(variant: String, extra: [String: Any]) -> [String: Any] {
            let footer = find("OpenSnapFooter") ?? window.contentView ?? NSView()
            let toggle = app.dragOriginalControl
            var facts: [String: Any] = ["originalSizeVisible": !toggle.isHiddenOrHasHiddenAncestor, "originalSizeChosen": toggle.state == .on,
                                        "largeShot": app.isLargeShot, "windowWidth": Double(window.frame.width.rounded()),
                                        "uploadActive": app.uploadState != .idle, "originalSizeClass": String(describing: type(of: toggle))]
            for (key, value) in extra { facts[key] = value }
            return glassRecord(kind: "group", identifier: "FooterOriginalSize", variant: variant, host: window, rowsRoot: footer, extra: facts)
        }
        guard loadLargeShot(name: "Quarterly planning review of the new upload flow") != nil else { gap("S59", "Original size", "no synthetic size made isLargeShot true"); return }
        placeWindow(CGSize(width: 1280, height: 800))
        for (slug, on, variant) in [("footer-original-on", true, "chosen"), ("footer-original-off", false, "rest")] {
            app.dragOriginalControl.state = on ? .on : .off
            app.changeDragOptions(nil)
            pump(0.4)
            shoot("S59", slug, surface: "footer Original size", state: "large shot at 1280: the Original size toggle \(on ? "on" : "off")", crop: footerCrop(), refs: refs, settle: 0.3,
                  extra: ["glassPanel": footerRecord(variant: variant, extra: [:])])
        }
        app.dragOriginalControl.state = .on
        app.changeDragOptions(nil)
        // 980 pt with an upload in flight: the slot has no room for the toggle beside the upload state, so it steps aside. The uploader is a stub.
        syntheticDestinations()
        let gate = UploadGate()
        gate.mode = "wait"
        app.publishing.clipboardWriter = { _ in }
        app.linkOpener = { _ in }
        app.publishing.uploader = { _, _, plan, _ in
            _ = gate.release.wait(timeout: .now() + 8)
            return plan.publicURL ?? plan.remoteURL
        }
        placeWindow(CGSize(width: 980, height: CGFloat(window.minSize.height)))
        window.makeKeyAndOrderFront(nil)
        app.uploadState = .idle
        app.publishImage()
        pump(0.9)
        shoot("S59", "footer-original-hidden", surface: "footer Original size", state: "large shot at 980 during an upload: the status slot reflows and the Original size toggle steps aside", crop: footerCrop(),
              refs: refs, settle: 0.2, extra: ["glassPanel": footerRecord(variant: "hidden", extra: [:])])
        gate.release.signal()
        pump(1.5)
        app.expireUploadSuccess()
        pump(0.3)
    }

    // MARK: groups inside a window (Settings, History, Resize, destination sheet)

    /// The nearest glass plate above `view`, or the view itself when it is one.
    func enclosingPlate(of view: NSView?) -> NSView? {
        var current = view
        while let candidate = current {
            if candidate is GlassSurfaceView || candidate is GlassChoiceGroup { return candidate }
            current = candidate.superview
        }
        return nil
    }

    /// A group of choices that lives in a window rather than in a floating panel: rest, hover (a row that is not chosen), keyboard focus (the
    /// chosen row, else the first enabled one) and, when asked and a row is disabled, a disabled capture that also offers the row focus.
    /// `root` is the plate the rows sit on; the nested-glass count still covers the whole host window.
    func glassGroupStates(_ id: String, base: String, surface: String, refs: [String], host: NSWindow, windows: [NSWindow]? = nil, root: NSView, restState: String,
                          disabledSlug: String? = nil, extra: [String: Any] = [:]) {
        let shots = windows ?? [host]
        func record(_ variant: String, _ more: [String: Any] = [:]) -> [String: Any] {
            glassRecord(kind: "group", identifier: base, variant: variant, host: host, rowsRoot: root, extra: extra.merging(more) { $1 })
        }
        let rows = glassRows(in: root)
        guard !rows.isEmpty else { gap(id, surface + " / " + base, "no choice rows were found on the \(base) plate"); return }
        host.makeKeyAndOrderFront(nil)
        shoot(id, base + "-rest", surface: surface, state: restState, windows: shots, refs: refs, settle: 0.3, extra: ["glassPanel": record("rest")])
        let enabled = rows.indices.filter { rows[$0].isEnabled }
        if let target = enabled.first(where: { !isChosen(rows[$0]) }) ?? enabled.first {
            setHovered(rows[target], true)
            shoot(id, base + "-hover", surface: surface, state: "\(restState); row \(target) (\(visibleTitle(rows[target]))) hovered", windows: shots, refs: refs, settle: 0.25,
                  extra: ["glassPanel": record("hover")])
            setHovered(rows[target], false)
        }
        if let focus = enabled.first(where: { isChosen(rows[$0]) }) ?? enabled.first {
            let took = host.makeFirstResponder(rows[focus])
            shoot(id, base + "-focus", surface: surface, state: "\(restState); keyboard focus on row \(focus) (\(visibleTitle(rows[focus])))", windows: shots, refs: refs, settle: 0.25,
                  extra: ["glassPanel": record("focus", ["focusAccepted": took])])
        }
        if let slug = disabledSlug, let off = rows.indices.first(where: { !rows[$0].isEnabled }) {
            setHovered(rows[off], true)
            let offer = offerFocus(in: host, to: rows[off])
            shoot(id, slug, surface: surface, state: "\(restState); disabled row \(off) (\(visibleTitle(rows[off]))) hovered and offered focus", windows: shots, refs: refs, settle: 0.25,
                  extra: ["glassPanel": record("disabled", offer.facts.merging(["disabledTookFocus": offer.took]) { $1 })])
            setHovered(rows[off], false)
        }
        host.makeFirstResponder(nil)
    }

    // MARK: S56 Settings

    func s56() {
        defer { verifyGlassCaptures("S56") }
        let refs = ["SettingsWindow.swift|final class SettingsTabBar", "SettingsWindow.swift|final class SettingsActionButton"]
        syntheticDestinations()
        app.openPreferences(tab: 0)
        pump(0.8)
        guard let controller = app.settingsController else { gap("S56", "Settings", "Settings did not open"); return }
        let host = controller.window
        func tabs() -> Int { 4 }
        /// Selects tabs until the one that holds `identifier` is showing; returns the view.
        func reveal(_ identifier: String) -> NSView? {
            for tab in 0..<tabs() {
                controller.select(tab)
                pump(0.5)
                host.contentView?.layoutSubtreeIfNeeded()
                if let view = find(identifier, in: host.contentView), !view.isHiddenOrHasHiddenAncestor { return view }
            }
            return nil
        }
        if let bar = reveal("SettingsTabBar") {
            glassGroupStates("S56", base: "settings-tabs", surface: "Settings glass groups", refs: refs, host: host, root: bar, restState: "Settings tab strip on one glass plate")
        } else { gap("S56", "Settings tabs", "the tab strip plate (SettingsTabBar) was not found") }
        for (base, identifier, label) in [("settings-radios", "presenceDock", "Presence, Precision and Arrow head radios"), ("settings-toggles", "showToolTips", "hover hints, keyboard tips, include app and capture flash toggles")] {
            if let anchor = reveal(identifier), let plate = enclosingPlate(of: anchor) {
                glassGroupStates("S56", base: base, surface: "Settings glass groups", refs: refs, host: host, root: plate, restState: "Settings: \(label)")
            } else { gap("S56", "Settings / \(base)", "no glass plate was found around \(identifier)") }
        }
        if let add = reveal("addDestination"), let plate = enclosingPlate(of: add) {
            glassGroupStates("S56", base: "settings-actions", surface: "Settings glass groups", refs: refs, host: host, root: plate, restState: "Settings, Upload: the destination action plate",
                             disabledSlug: "settings-actions-disabled")
        } else { gap("S56", "Settings / settings-actions", "no glass plate was found around addDestination") }
        app.closePreferences()
        pump(0.3)
    }

    // MARK: S53 Color

    func s53() {
        defer { verifyGlassCaptures("S53") }
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Glass Color")
        let opener = app.paletteButton
        let refs = ["App.swift|func presentDrawingColors", "BezelDrawingControls.swift|final class ColorPaletteContent", "BezelDrawingControls.swift|final class BezelColorButton"]
        let script = GlassPanelScript(id: "S53", surface: "Colour panel", identifier: "DrawingColors", base: "color", opener: opener, refs: refs,
                                      open: { [self] in app.presentDrawingColors(hover: false) }, nativeMenu: nil)
        app.applyChosenColor(OriginalDrawingControls.presets[0].color, modifiers: [])
        guard let opened = openGlassPanel(script) else { return }
        glassPanelStates(script, opened, restState: "Colour panel open with the first preset chosen")
        dismissGlassPanel("S53", "color-dismissed", surface: script.surface, state: "Colour panel dismissed with Escape: gone, focus back on the colour swatch", script: script, opened: opened)
        app.applyChosenColor(NSColor(deviceRed: 0.18, green: 0.62, blue: 0.55, alpha: 1), modifiers: []) // token-exempt: a custom drawing colour for the capture
        pump(0.2)
        if let again = openGlassPanel(script) {
            shootGlassPanel("S53", "color-custom", surface: script.surface, state: "Colour panel with a custom colour chosen: the Custom color… row carries the chip and the check", panel: again.panel,
                            opener: opener, refs: refs, variant: "chosen", identifier: "DrawingColors")
            dismissGlassPanel("S53", "color-dismissed-2", surface: script.surface, state: "", script: script, opened: again, capture: false)
        }
        app.applyChosenColor(OriginalDrawingControls.presets[0].color, modifiers: [])
    }

    // MARK: S54 Size

    func s54() {
        defer { verifyGlassCaptures("S54") }
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Glass Size")
        app.setTool(.brush)
        let pill = app.widthControl
        let refs = ["BezelDrawingControls.swift|func showPopover", "BezelDrawingControls.swift|final class SizePopoverContent", "BezelDrawingControls.swift|final class SizePresetButton"]
        let script = GlassPanelScript(id: "S54", surface: "Size panel", identifier: "Size", base: "size", opener: pill, refs: refs, open: { pill.showPopover() }, nativeMenu: nil)
        pill.doubleValue = OriginalDrawingControls.sizeSteps[2]
        app.changeWidth(pill)
        pump(0.2)
        guard let opened = openGlassPanel(script) else { return }
        glassPanelStates(script, opened, restState: "Size panel open with a preset size chosen")
        // The track held down: the knob grows and the track takes its wash; the record says the track really is pressed.
        if let track = pill.popoverContent?.trackView {
            track.setPressed(true)
            shootGlassPanel("S54", "size-pressed", surface: script.surface, state: "Size panel with the track held down", panel: opened.panel, opener: pill, refs: refs,
                            variant: "pressed", identifier: "Size", extra: ["trackPressed": track.isPressed])
            track.setPressed(false)
        } else { gap("S54", "Size panel / size-pressed", "the Size panel has no track view") }
        dismissGlassPanel("S54", "size-dismissed", surface: script.surface, state: "Size panel dismissed with Escape: gone, focus back on the size pill", script: script, opened: opened)
    }

    // MARK: S58 destination sheet

    /// The destination sheet on Settings, S3-compatible selected: the Protocol and Key source glass faces with the choice panels they open, and
    /// the "Make uploads public-read" toggle off and on. In-memory fake destination only: nothing is tested, saved or sent.
    func s58() {
        defer { verifyGlassCaptures("S58") }
        let refs = ["PublishingDestinationsView.swift|let protocolPopup", "PublishingDestinationsView.swift|let aclCheckbox", "GlassChoices.swift|final class MenuChoicePanel"]
        syntheticDestinations()
        guard let controller = openSettingsUpload() else { gap("S58", "Destination sheet", "Settings did not open"); return }
        let settings = controller.window
        let (sheet, view) = app.publishing.buildEditor(editing: nil, visibleFrame: nil, hostWidth: settings.frame.width)
        settings.beginSheet(sheet)
        pump(0.8)
        defer { app.closePreferences() }
        view.protocolPopup.selectItem(withTitle: PublishingProtocol.s3.title)
        view.formChanged()
        pump(0.5)
        func script(_ popup: GlassPopUpButton, base: String) -> GlassPanelScript {
            GlassPanelScript(id: "S58", surface: "Destination sheet", identifier: popup.panelIdentifier, base: base, opener: popup, refs: refs,
                             open: { popup.openChoices(keyboard: false) }, nativeMenu: popup.menu, host: sheet, context: [sheet, settings])
        }
        for (face, base) in [(view.protocolPopup, "destination-protocol"), (view.sourcePopup, "destination-source")] {
            let panelScript = script(face, base: base)
            guard let opened = openGlassPanel(panelScript) else { continue }
            glassPanelStates(panelScript, opened, restState: "\(base == "destination-protocol" ? "Protocol" : "Key source") choices open on the destination sheet, S3-compatible selected")
            dismissGlassPanel("S58", base + "-dismissed", surface: "Destination sheet", state: "choices dismissed with Escape: gone, focus back on the face", script: panelScript, opened: opened)
        }
        // The public-read toggle (visible for S3-compatible): off, then on. Its row is the only choice on its plate.
        guard let plate = enclosingPlate(of: view.aclCheckbox) else { gap("S58", "Destination sheet / public-read", "no glass plate around the public-read toggle"); closeHarnessSheet(sheet); return }
        for (slug, on) in [("destination-acl-off", false), ("destination-acl-on", true)] {
            view.aclCheckbox.isChosen = on
            pump(0.3)
            let record = glassRecord(kind: "group", identifier: "DestinationPublicRead", variant: on ? "chosen" : "rest", host: sheet, rowsRoot: plate,
                                     extra: ["protocol": "S3", "aclChosen": view.aclCheckbox.isChosen])
            shoot("S58", slug, surface: "Destination sheet", state: "S3-compatible destination: Make uploads public-read \(on ? "on" : "off")", windows: [sheet, settings], refs: refs, settle: 0.3,
                  extra: ["glassPanel": record])
        }
        closeHarnessSheet(sheet)
        // The sheet at the normal 640 width and at its supported minimum (sheetMinWidth, 560), S3-compatible with the Keychain key source: every
        // face and choice label in it is measured, so a narrow sheet that cuts a title fails the run.
        for (width, slug) in [(CGFloat(640), "destination-width-640"), (PublishingDestinationsView.sheetMinWidth, "destination-width-560")] {
            let (narrow, form) = app.publishing.buildEditor(editing: nil, visibleFrame: nil, hostWidth: width)
            settings.beginSheet(narrow)
            pump(0.8)
            form.protocolPopup.selectItem(withTitle: PublishingProtocol.s3.title)
            form.formChanged()
            form.sourcePopup.selectItem(withTitle: "Access key stored in Keychain")
            form.formChanged()
            pump(0.6)
            let record = glassRecord(kind: "group", identifier: "DestinationSheetWidth", variant: "rest", host: narrow, rowsRoot: narrow.contentView,
                                     extra: ["protocol": "S3", "sourceTitle": form.sourcePopup.titleOfSelectedItem ?? "", "requestedWidth": Double(width), "sheetWidth": Double((narrow.contentView?.frame.width ?? narrow.frame.width).rounded()), "sheetFrameWidth": Double(narrow.frame.width.rounded()), "formWidth": Double(form.frame.width.rounded()),
                                             "sheetMinWidth": Double(PublishingDestinationsView.sheetMinWidth)])
            shoot("S58", slug, surface: "Destination sheet", state: "S3-compatible with the Keychain key source, sheet \(Int(width)) pt wide", windows: [narrow, settings], refs: refs, settle: 0.3, extra: ["glassPanel": record])
            closeHarnessSheet(narrow)
        }
    }

    // MARK: S57 Resize sheet

    /// The Resize sheet: every glass choice in it (mode, lock, limit, preset face and the sheet buttons), the 3 x 3 anchor plate in Crop mode,
    /// and the preset choice panel. Presets are written to the harness's isolated support folder, as S08 does.
    func s57() {
        defer { verifyGlassCaptures("S57") }
        let refs = ["ResizePanel.swift|final class ResizePanel", "ResizePanel.swift|final class ResizeAnchorGrid", "GlassChoices.swift|final class GlassChoiceGroup"]
        loadSynthetic(size: CGSize(width: 1000, height: 700), name: "Glass Resize")
        let store = ResizePresetStore()
        try? store.add(ResizePreset(name: "Blog hero", width: 1600, height: 900, mode: .scale))
        try? store.add(ResizePreset(name: "Avatar", width: 256, height: 256, mode: .crop))
        app.resize()
        pump(1.0)
        guard let sheet = window.attachedSheet, let content = sheet.contentView else { gap("S57", "Resize sheet", "the Resize sheet did not attach"); return }
        defer {
            if let attached = window.attachedSheet { window.endSheet(attached, returnCode: .cancel) }
            app.activeResizeSession?.cancel()
            pump(0.4)
        }
        glassGroupStates("S57", base: "resize-groups", surface: "Resize sheet", refs: refs, host: sheet, windows: [sheet, window], root: content,
                         restState: "Resize sheet: the mode, lock proportions, preset and button choices on their plates")
        // Crop mode shows the anchor plate.
        if let mode = find("ResizeMode.group", in: content) as? GlassChoiceGroup { mode.choose(1) } else { gap("S57", "Resize sheet / crop", "the mode group (ResizeMode) was not found") }
        pump(0.6)
        if let grid = firstView(of: ResizeAnchorGrid.self, in: content), !grid.isHiddenOrHasHiddenAncestor {
            func anchorRecord(_ variant: String) -> [String: Any] {
                var record = glassRecord(kind: "group", identifier: "ResizeAnchor", variant: variant, host: sheet, rowsRoot: NSView())
                record["rowTitles"] = ResizePanelAnchor.allCases.map(\.title)
                record["chosenIndexes"] = [grid.anchor.rawValue]
                if let hovered = grid.hovered { record["hoveredRow"] = hovered.rawValue }
                if sheet.firstResponder === grid { record["focusedRow"] = grid.anchor.rawValue }
                record["disabledRows"] = [Int]()
                if let font = minimumTextSize(in: content) { record["minFontSize"] = font }
                return record
            }
            sheet.makeKeyAndOrderFront(nil)
            shoot("S57", "resize-anchor-rest", surface: "Resize sheet", state: "Crop mode: the 3 x 3 anchor plate, Center chosen", windows: [sheet, window], refs: refs, settle: 0.3, extra: ["glassPanel": anchorRecord("rest")])
            grid.setHovered(.topRight)
            shoot("S57", "resize-anchor-hover", surface: "Resize sheet", state: "Crop mode: the Top Right cell hovered", windows: [sheet, window], refs: refs, settle: 0.25, extra: ["glassPanel": anchorRecord("hover")])
            grid.setHovered(nil)
            sheet.makeFirstResponder(grid)
            shoot("S57", "resize-anchor-focus", surface: "Resize sheet", state: "Crop mode: the anchor plate has keyboard focus (ring on the chosen cell)", windows: [sheet, window], refs: refs, settle: 0.25, extra: ["glassPanel": anchorRecord("focus")])
            sheet.makeFirstResponder(nil)
        } else { gap("S57", "Resize sheet / anchor", "the anchor grid was not visible in Crop mode") }
        if let mode = find("ResizeMode.group", in: content) as? GlassChoiceGroup { mode.choose(0) }
        pump(0.4)
        // The preset choice panel.
        guard let face = firstView(of: GlassPopUpButton.self, in: content) else { gap("S57", "Resize sheet / preset", "the preset pop-up (a GlassPopUpButton) was not found"); return }
        let script = GlassPanelScript(id: "S57", surface: "Resize sheet", identifier: face.panelIdentifier, base: "resize-preset", opener: face, refs: refs,
                                      open: { face.openChoices(keyboard: false) }, nativeMenu: face.menu, host: sheet, context: [sheet, window])
        guard let opened = openGlassPanel(script) else { return }
        glassPanelStates(script, opened, restState: "Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets)")
        shootGlassPanel("S57", "resize-preset-chosen", surface: script.surface, state: "Resize sheet: the preset panel with its chosen row", panel: opened.panel, opener: face, refs: refs,
                        variant: "chosen", identifier: face.panelIdentifier, context: script.context)
        dismissGlassPanel("S57", "resize-preset-dismissed", surface: script.surface, state: "Preset choices dismissed with Escape: gone, focus back on the preset face", script: script, opened: opened)
    }

    // MARK: S55 History

    /// History's category group on its plate, and the date filter and Drag as pop-up faces with the choice panels they open. Six synthetic
    /// entries go into the harness's isolated archive, as S20 does.
    func s55() {
        defer { verifyGlassCaptures("S55") }
        let refs = ["HistoryBrowser.swift|final class HistoryPopUpChoice", "HistoryBrowser.swift|HistoryCategory", "GlassChoices.swift|final class MenuChoicePanel"]
        let calendar = Calendar.current
        let names = ["Quarterly mockup", "Bug report screenshot", "Onboarding flow", "Pricing page", "Team photo wall", "Error dialog"]
        let actions: [HistoryStore.Action] = [.archived, .exported, .shared, .archived, .shared, .exported]
        for (index, name) in names.enumerated() {
            let size = CGSize(width: 900 + CGFloat(index) * 40, height: 600)
            canvas.newBlank(size: size); canvas.setBackground(AuditRun.syntheticImage(size: size))
            if let snapshot = try? app.historySnapshot(), let store = try? app.archiveStore() {
                let date = calendar.date(byAdding: .day, value: -(index / 3) * 3, to: Date())?.addingTimeInterval(-Double(index) * 600) ?? Date()
                _ = try? store.archive(snapshot, name: name, action: actions[index], destination: actions[index] == .shared ? "Example S3" : nil,
                                       remoteURL: actions[index] == .shared ? URL(string: "https://cdn.example.com/pics/\(index).png") : nil, date: date)
            }
        }
        app.showHistory()
        pump(1.2)
        guard let history = app.historyWindow, let content = history.contentView else { gap("S55", "History", "the History window did not open"); return }
        defer { history.orderOut(nil); window.makeKeyAndOrderFront(nil) }
        history.makeKeyAndOrderFront(nil)
        if let category = find("HistoryCategory", in: content) {
            glassGroupStates("S55", base: "history-category", surface: "History glass choices", refs: refs, host: history, root: category,
                             restState: "History: the All / Shared / Exported / Saved category group on one plate")
        } else { gap("S55", "History / category", "the category group (HistoryCategory) was not found") }
        guard let browser = app.historyBrowser else { gap("S55", "History", "no history browser"); return }
        for (popup, base, label) in [(browser.dateFilterPopUp, "history-date", "Date filter"), (browser.dragFormatPopUp, "history-dragas", "Drag as")] {
            let panelID = popup.panelIdentifier
            let script = GlassPanelScript(id: "S55", surface: "History glass choices", identifier: panelID, base: base, opener: popup, refs: refs,
                                          open: { popup.openChoices(keyboard: false) }, nativeMenu: popup.menu, host: history, context: [history])
            guard let opened = openGlassPanel(script) else { continue }
            glassPanelStates(script, opened, restState: "History: the \(label) choices open")
            shootGlassPanel("S55", base + "-chosen", surface: script.surface, state: "History: the \(label) panel with its chosen row", panel: opened.panel, opener: popup, refs: refs,
                            variant: "chosen", identifier: panelID, context: script.context)
            dismissGlassPanel("S55", base + "-dismissed", surface: script.surface, state: "\(label) choices dismissed with Escape: gone, focus back on the face", script: script, opened: opened)
        }
    }

    // MARK: S60 Settings Capture tab

    /// One group capture of a plate in a window: the glassPanel record for the rows on `root`, nothing else moved.
    func shootGlassGroup(_ id: String, _ slug: String, surface: String, state: String, host: NSWindow, root: NSView, variant: String, refs: [String], identifier: String,
                         windows: [NSWindow]? = nil, extra: [String: Any] = [:]) {
        let record = glassRecord(kind: "group", identifier: identifier, variant: variant, host: host, rowsRoot: root, extra: extra)
        shoot(id, slug, surface: surface, state: state, windows: windows ?? [host], refs: refs, settle: 0.3, extra: ["glassPanel": record])
    }

    /// The Capture tab at its normal size and the key-choice panel opened from a shortcut row's key face. The Settings window is built here against
    /// an inert shortcut backend (as S17 does), so no key is ever claimed on the desktop whatever the captures choose.
    func s60() {
        defer { verifyGlassCaptures("S60") }
        let refs = ["GlobalHotkeys.swift|final class GlobalHotkeyForm", "SettingsWindow.swift|final class CaptureSettingsTab", "GlassChoices.swift|class GlassPopUpButton"]
        var stored = GeneralPreferencesState(drawingPrecision: .medium, arrowHead: 2, includeApp: true, statusMenu: 0)
        let controller = SettingsWindowController(state: { stored }, hotkeys: GlobalHotkeyManager(defaults: .standard, backend: AuditInertHotkeyBackend()), defaults: .standard,
                                                  destinations: { PublishingDestinationList() })
        controller.onChange = { stored = $0 }
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        controller.select(SettingsWindowController.captureTabIndex)
        controller.visibleFrame = { screen }
        controller.fit(animated: false)
        controller.window.setFrameTopLeftPoint(NSPoint(x: screen.minX + 40, y: screen.maxY - 24))
        controller.show()
        pump(0.8)
        defer { controller.window.orderOut(nil); window.makeKeyAndOrderFront(nil) }
        guard let form = controller.capture.hotkeyForm else { gap("S60", "Settings Capture", "the shortcut form was not built"); return }
        let host = controller.window
        host.contentView?.layoutSubtreeIfNeeded()
        let surface = "Settings Capture tab"
        // Enable toggle, on then off (the manager is inert; nothing registers).
        let enabledOn = form.enabledCheckbox.isChosen
        shootGlassGroup("S60", "capture-enable-on", surface: surface, state: "Capture tab: Enable global capture shortcuts on", host: host, root: form.enabledPlate, variant: "chosen", refs: refs,
                        identifier: "GlobalHotkeyEnabled", extra: ["enabledChosen": enabledOn])
        form.enabledCheckbox.performClick(nil)
        pump(0.3)
        shootGlassGroup("S60", "capture-enable-off", surface: surface, state: "Capture tab: Enable global capture shortcuts off", host: host, root: form.enabledPlate, variant: "rest", refs: refs,
                        identifier: "GlobalHotkeyEnabled", extra: ["enabledChosen": form.enabledCheckbox.isChosen])
        form.enabledCheckbox.performClick(nil)
        pump(0.3)
        // Modifiers with no key set: the toggles are disabled and refuse the keyboard (acceptsFirstResponder is the judge).
        let screenRow = form.rowPlate(for: .screen)
        let toggles = form.modifierToggles(for: .screen)
        let offered = toggles.first.map { offerFocus(in: host, to: $0) }
        let anyAccepts = toggles.contains { $0.acceptsFirstResponder }
        shootGlassGroup("S60", "capture-modifiers-disabled", surface: surface, state: "Capture tab: no key set for Screen region, so its four modifier toggles are disabled", host: host, root: screenRow,
                        variant: "disabled", refs: refs, identifier: "GlobalHotkeyRow.screen", extra: (offered?.facts ?? [:]).merging(["disabledTookFocus": anyAccepts]) { $1 })
        // A key chosen (K) and Option and Control on: the modifier toggles that are on are chosen.
        let key = form.keyPopup(for: .screen)
        key.selectItem(withTitle: "K"); _ = key.target?.perform(key.action, with: key)
        pump(0.3)
        toggles[1].performClick(nil); toggles[2].performClick(nil)
        pump(0.3)
        shootGlassGroup("S60", "capture-modifiers-chosen", surface: surface, state: "Capture tab: K with Option and Control chosen on the Screen region row", host: host, root: screenRow,
                        variant: "chosen", refs: refs, identifier: "GlobalHotkeyRow.screen", extra: ["keyTitle": key.titleOfSelectedItem ?? ""])
        shootGlassGroup("S60", "capture-clear-all", surface: surface, state: "Capture tab: the Clear All action plate", host: host, root: form.clearPlate, variant: "rest", refs: refs,
                        identifier: "GlobalHotkeyClear")
        // The key-choice panel from the row's key face.
        let script = GlassPanelScript(id: "S60", surface: surface, identifier: key.panelIdentifier, base: "capture-key", opener: key, refs: refs,
                                      open: { key.openChoices(keyboard: false) }, nativeMenu: key.menu, host: host, context: [host])
        guard let opened = openGlassPanel(script) else { return }
        glassPanelStates(script, opened, restState: "Capture tab: the key choices open for Screen region, K chosen")
        shootGlassPanel("S60", "capture-key-chosen", surface: surface, state: "Capture tab: the key panel with K chosen", panel: opened.panel, opener: key, refs: refs, variant: "chosen",
                        identifier: key.panelIdentifier, context: script.context)
        dismissGlassPanel("S60", "capture-key-dismissed", surface: surface, state: "Key choices dismissed with Escape: gone, focus back on the key face", script: script, opened: opened)
        // Long list inside the height cap: scrolled to its last row. A screen tall enough to show every key is capped to 640 pt so the cap is exercised.
        func openForScroll(capped: Bool) -> OpenedGlassPanel? {
            key.choicePanel.host.visibleFrameOverride = capped ? NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: 640) : nil
            return openGlassPanel(script)
        }
        guard var scrolling = openForScroll(capped: false) else { return }
        var capOverride = false
        if GlassPanelHost.current?.scrolls != true {
            dismissGlassPanel("S60", "capture-key-dismissed-uncapped", surface: surface, state: "", script: script, opened: scrolling, capture: false)
            capOverride = true
            guard let again = openForScroll(capped: true) else { return }
            scrolling = again
        }
        let rows = glassRows(in: scrolling.panel.contentView ?? NSView())
        if let last = rows.last { GlassPanelHost.current?.reveal(last) }
        pump(0.4)
        let visible = rows.filter { isWhollyInView($0) }.count
        shootGlassPanel("S60", "capture-key-scroll", surface: surface, state: "Capture tab: the long key list scrolled to its last row inside the height cap", panel: scrolling.panel, opener: key, refs: refs,
                        variant: "scroll", identifier: key.panelIdentifier, extra: ["scrolledToEnd": rows.last.map { isWhollyInView($0) } ?? false,
                                                                                  "capOverride": capOverride, "visibleRowsAtScroll": visible, "totalRowsAtScroll": rows.count,
                                                                                  "hostScrollsAtScroll": GlassPanelHost.current?.scrolls ?? false], context: script.context)
        dismissGlassPanel("S60", "capture-key-dismissed-2", surface: surface, state: "", script: script, opened: scrolling, capture: false)
        key.choicePanel.host.visibleFrameOverride = nil
        key.selectItem(at: 0); _ = key.target?.perform(key.action, with: key)
    }

    /// The Toolbox choices as the older surfaces (S23, S42, S44) show them: the glass panel the Toolbox button opens, imaged over the editor and
    /// dismissed with Escape through the panel; a build without the panel falls back to the native menu it replaced.
    func captureToolboxChoices(_ id: String, _ slug: String, surface: String, state: String, refs: [String]) {
        guard let toolbox = firstView(of: ToolboxPopUpButton.self) else { gap(id, surface + " / " + state, "the Toolbox button was not found"); return }
        let script = GlassPanelScript(id: id, surface: surface, identifier: "Toolbox", base: "toolbox", opener: toolbox, refs: refs, open: { toolbox.openMenu() }, nativeMenu: toolbox.menu)
        if let opened = openGlassPanel(script, recordGap: false) {
            shootGlassPanel(id, slug, surface: surface, state: state, panel: opened.panel, opener: toolbox, refs: refs, identifier: "Toolbox")
            dismissGlassPanel(id, slug + "-dismissed", surface: surface, state: "Toolbox panel dismissed with Escape", script: script, opened: opened, capture: false)
        } else if let menu = toolbox.menu {
            captureTrackedMenu(id, slug, surface: surface, state: state, refs: refs, dismiss: { menu.cancelTracking() }, trigger: { toolbox.performClick(nil) })
        } else {
            gap(id, surface + " / " + state, "the Toolbox opened neither a glass panel nor a menu")
        }
    }
}
