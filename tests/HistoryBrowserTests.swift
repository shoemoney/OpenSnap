#if HISTORY_BROWSER_TESTS
import AppKit
import UniformTypeIdentifiers

// Standalone executable; no core files, activation, desktop input, or pasteboard writes.
// xcrun swiftc -swift-version 5 -warnings-as-errors -strict-concurrency=complete
// -D HISTORY_BROWSER_TESTS Sources/HistoryBrowser.swift tests/HistoryBrowserTests.swift -o /tmp/opensnap-history-browser-tests
// /tmp/opensnap-history-browser-tests
@main @MainActor
struct HistoryBrowserTests {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    static func expect(_ condition: @autoclosure () throws -> Bool,_ message: String) throws {
        if try !condition() { throw Failure(message) }
    }
    static var calendar: Calendar {
        var result = Calendar(identifier:.gregorian); result.timeZone = TimeZone(identifier:"America/Chicago")!; return result
    }
    static var now: Date { calendar.date(from:DateComponents(year:2026,month:3,day:9,hour:12))! }
    static func day(_ offset: Int,hour: Int = 12) -> Date {
        let start = calendar.date(byAdding:.day,value:offset,to:calendar.startOfDay(for:now))!
        return calendar.date(byAdding:.hour,value:hour,to:start)!
    }
    static func item(_ name: String,_ offset: Int = 0,action: String = "Saved",missing: Bool = false,link: Bool = false) -> HistoryBrowser.Item {
        HistoryBrowser.Item(id:UUID(),name:name,date:day(offset),size:CGSize(width:640,height:480),action:action,
                            text:"editable note",destination:nil,link:link ? URL(string:"https://example.invalid/item") : nil,previewURL:nil,missing:missing)
    }
    static func browser(_ body: (HistoryBrowser,UserDefaults) throws -> Void) throws {
        let suite = "OpenSnapHistoryTests."+UUID().uuidString
        let defaults = TestDefaults(name: suite)
        defer { TestDefaults.dispose(defaults, name: suite) }
        let view = HistoryBrowser(defaults:defaults,calendar:calendar,now:{ now })
        defer { view.close() }
        try body(view,defaults)
    }
    static func descendants(_ view: NSView) -> [NSView] { [view]+view.subviews.flatMap(descendants) }
    /// The glass plate a control sits on.
    static func glassPlate(of view: NSView) -> GlassSurfaceView? {
        var current: NSView? = view
        while let next = current?.superview { if let plate = next as? GlassSurfaceView { return plate }; current = next }
        return nil
    }
    /// The seven action buttons in `Action.allCases` order, wherever the glass plates put them.
    static func actionButtons(_ browser: HistoryBrowser) -> [HistoryActionButton] { descendants(browser.actionRow).compactMap { $0 as? HistoryActionButton } }
    /// The sizes a control really draws: the spans of an attributed label (a button's own title field keeps the system 13 pt in `font`
    /// and draws the attributed title), else its font. Empty labels draw nothing.
    static func drawnSizes(_ control: NSControl) -> [CGFloat] {
        var sizes: [CGFloat] = []
        if let button = control as? NSButton, button.imagePosition == .imageOnly { return [] } // draws no text (the search field's own accessory buttons too)
        let attributed = (control as? NSTextField)?.attributedStringValue ?? (control as? NSButton)?.attributedTitle
        if let attributed, attributed.length > 0 {
            attributed.enumerateAttribute(.font,in:NSRange(location:0,length:attributed.length)) { value,_,_ in sizes.append(((value as? NSFont) ?? control.font)?.pointSize ?? 13) }
        } else { sizes = [control.font?.pointSize ?? 20] }
        return sizes
    }
    /// A shared snap selected with every callback wired, so all seven actions are enabled.
    static func selectingEverythingEnabled(_ browser: HistoryBrowser) {
        let shared = item("Shared",action:"Shared",link:true)
        browser.onOpen = { _ in }; browser.onCopy = { _ in }; browser.onCopyLink = { _ in }; browser.onOpenLink = { _ in }
        browser.onRemove = { _ in }; browser.onDeleteFiles = { _ in }; browser.onDeleteRemote = { _ in }
        browser.update(items:[shared,item("Other",-1)]); browser.select(ids:[shared.id])
    }
    static func luminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB) ?? color
        func channel(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }
    /// WCAG contrast of `text` over `background`, both resolved under `appearance`.
    static func contrast(_ text: NSColor,over background: NSColor,_ appearance: NSAppearance) -> Double {
        let a = luminance(DesignTokens.Palette.resolve(text,for:appearance)), b = luminance(DesignTokens.Palette.resolve(background,for:appearance))
        return (max(a,b) + 0.05) / (min(a,b) + 0.05)
    }
    static func grid(_ browser: HistoryBrowser) throws -> NSCollectionView {
        guard let content = browser.window?.contentView,let grid = descendants(content).compactMap({ $0 as? NSCollectionView }).first else { throw Failure("Missing native grid") }
        return grid
    }
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryBrowserTests-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false); return url
    }
    static func laidOut(_ browser: HistoryBrowser,width: CGFloat,height: CGFloat) {
        browser.window!.setFrame(NSRect(x:0,y:0,width:width,height:height),display:false)
        browser.window!.contentView!.layoutSubtreeIfNeeded()
    }
    /// The frames the flow layout assigns, in the grid's own coordinates.
    static func tileFrames(_ browser: HistoryBrowser) throws -> [NSRect] {
        let grid = try grid(browser)
        grid.layoutSubtreeIfNeeded()
        return (grid.collectionViewLayout?.layoutAttributesForElements(in:grid.bounds) ?? []).filter { $0.representedElementCategory == .item }.map(\.frame)
    }
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let tests: [(String,() throws -> Void)] = [
            ("Date and format popup choices remain enabled without a selection", {
                try browser { browser,_ in
                    let choice = NSMenuItem(title:"Yesterday",action:nil,keyEquivalent:"")
                    try expect(browser.selectedIDs.isEmpty && browser.validateMenuItem(choice),"Popup default tag zero must not inherit Open's selection requirement")
                    let grid = try grid(browser)
                    guard let open = grid.menu?.items.first(where: { $0.title == "Open" }) else { throw Failure("Missing context Open") }
                    try expect(!browser.validateMenuItem(open),"Context Open still requires a selected drawing")
                    browser.update(items:[item("Proof")]); browser.select(ids:browser.visibleItems.map(\.id)); browser.onOpen = { _ in }
                    try expect(browser.validateMenuItem(open),"Context Open becomes enabled for valid selection")
                }
            }),
            ("Normal hidden NSWindow with accessible native multiselect grid", {
                try browser { browser,_ in
                    try expect(browser.window != nil && browser.window!.styleMask.contains(.closable) && browser.window!.styleMask.contains(.resizable),"Window contract changed")
                    try expect(!browser.window!.isVisible,"Tests must not show a live window")
                    let grid = try grid(browser)
                    try expect(grid.isSelectable && grid.allowsMultipleSelection && grid.allowsEmptySelection,"Native selection not enabled")
                    try expect(grid.collectionViewLayout is NSCollectionViewFlowLayout,"History is not a thumbnail grid")
                    try expect(grid.accessibilityLabel() == "History thumbnail grid","Grid accessibility name")
                }
            }),
            ("The History command groups reach an external client: each plate is a named group holding its commands, in order, with a coherent parent chain", {
                try browser { browser,_ in
                    selectingEverythingEnabled(browser)
                    laidOut(browser,width:1100,height:700)
                    let window = browser.window!
                    let tree = AXTree.walk(window)
                    let expected: [(String,[HistoryBrowser.Action])] = HistoryBrowser.actionGroups.map { ($0.label,$0.actions) }
                    try expect(expected.map(\.0) == ["Open and copy","Web link","Remove"],"The three command groups")
                    for (label,actions) in expected {
                        guard let group = tree.find(.group,label) else { throw Failure("The \(label) group is not reachable from the window:\n\(tree.outline)") }
                        let kids = tree.children(of: group)
                        try expect(kids.count == actions.count && kids.allSatisfy { $0.role == .button },"The \(label) plate shows its \(actions.count) buttons (it used to answer with none): \(kids.map { $0.label ?? "" })")
                        // Each command is named by its full title (AXDescription); the visible label may be the shorter one while the bar is narrow.
                        try expect(kids.map { $0.label ?? "" } == actions.map(\.title),"The \(label) commands are named in order: AXDescription \(kids.map { $0.axDescription ?? "nil" }), AXTitle \(kids.map { $0.title ?? "nil" })")
                        try expect(kids.allSatisfy(\.enabled),"With a drawing selected every command is enabled")
                    }
                    let problems = tree.parentProblems()
                    try expect(problems.isEmpty,"Every parent agrees with the tree and leads back to the window: \(problems.prefix(3))")
                    let shape = tree.shapeProblems()
                    try expect(shape.isEmpty,"No command group hands out an AXUnknown wrapper, and no node lacks a role (\(shape.count)): \(shape.prefix(3))")
                    // AXPress on a reached command runs it.
                    var opened = 0
                    browser.onOpen = { _ in opened += 1 }
                    guard let open = tree.find(.button,"Open") else { throw Failure("Open is reachable") }
                    let pressed = AXTree.press(open)
                    try expect(pressed && opened == 1,"AXPress on the reached Open command opens the drawing (press returned \(pressed), opened \(opened), element \(type(of: open.object)), enabled \(open.enabled))")
                }
            }),
            ("Supplied reverse insertion order and local day groups are preserved", {
                try browser { browser,_ in
                    let old = item("Old",-4), yesterday = item("Yesterday",-1), a = item("A"), b = item("B")
                    browser.update(items:[b,a,yesterday,old])
                    try expect(browser.sections.map(\.title).prefix(2) == ["Today","Yesterday"],"Original day headers")
                    try expect(browser.sections.count == 3 && browser.sections[2].day == calendar.startOfDay(for:old.date),"Older date group")
                    try expect(browser.visibleItems.map(\.id) == [b.id,a.id,yesterday.id,old.id],"UI timestamp/UUID sorting changes core insertion order")
                    browser.update(items:[a,old,b,yesterday])
                    try expect(browser.visibleItems.map(\.id) == [a.id,old.id,b.id,yesterday.id],"Display must preserve supplied order even with nonmonotone dates")
                    try expect(browser.sections.count == 4,"Consecutive calendar groups were globally reordered")
                }
            }),
            ("Original action filters use exact supplied core strings", {
                try browser { browser,_ in
                    let saved = item("Archive",action:"Saved"), dragged = item("Dragged",action:"Exported"), shared = item("Shared",action:"Shared",link:true), unknown = item("Other",action:"saved")
                    browser.update(items:[saved,dragged,shared,unknown])
                    for (category,expected) in [(HistoryBrowser.Category.saved,saved.id),(.exported,dragged.id),(.shared,shared.id)] {
                        browser.setFilters(category:category)
                        try expect(browser.visibleItems.map(\.id) == [expected],"Category mapping \(category)")
                    }
                    browser.setFilters(category:.all); try expect(browser.visibleItems.count == 4,"Unknown actions must remain visible in All")
                }
            }),
            ("Original search is one literal case insensitive OR over name link text", {
                try browser { browser,_ in
                    var a = item("Résumé plan",action:"Shared",link:true); a.text = "RÉSUMÉ draft  two spaces"; a.destination = "Team Folder"
                    let b = item("Other",action:"Saved")
                    browser.update(items:[a,b])
                    for query in ["résumé","DRAFT","example.invalid","draft  two","  "] {
                        browser.setFilters(category:.all,query:query)
                        try expect(browser.visibleItems.map(\.id) == [a.id],"Search field mismatch \(query)")
                    }
                    for query in ["resume","team","plan draft"," résumé ","Saved"] {
                        browser.setFilters(category:.shared,query:query)
                        try expect(browser.visibleItems.isEmpty,"Search tokenizes, trims, removes diacritics, or searches extra fields: \(query)")
                    }
                    browser.setFilters(category:.saved,query:"résumé"); try expect(browser.visibleItems.isEmpty,"Search ignores category")
                    browser.setFilters(category:.shared,date:.yesterday,query:"résumé"); try expect(browser.visibleItems.isEmpty,"Search ignores date")
                    browser.setFilters(category:.all,query:""); try expect(browser.visibleItems.count == 2,"Empty search must match all")
                }
            }),
            ("Recovered date predicates use strict hour 48hour and yesterday bounds", {
                try browser { browser,_ in
                    let todayStart = calendar.startOfDay(for:now), yesterdayStart = calendar.date(byAdding:.day,value:-1,to:todayStart)!
                    let yesterdayEnd = todayStart.addingTimeInterval(-1)
                    @MainActor func dated(_ name: String,_ date: Date) -> HistoryBrowser.Item { var value = item(name); value.date = date; return value }
                    let values = [dated("Future",now.addingTimeInterval(100)),dated("Now",now),
                                  dated("HourAfter",now.addingTimeInterval(-3599.5)),dated("HourExact",now.addingTimeInterval(-3600)),dated("HourBefore",now.addingTimeInterval(-3600.5)),
                                  dated("48After",now.addingTimeInterval(-172799.5)),dated("48Exact",now.addingTimeInterval(-172800)),dated("48Before",now.addingTimeInterval(-172800.5)),
                                  dated("Midnight",yesterdayStart),dated("AfterMidnight",yesterdayStart.addingTimeInterval(0.5)),
                                  dated("LastSecond",yesterdayEnd),dated("BeforeLastSecond",yesterdayEnd.addingTimeInterval(-0.5)),dated("NextDay",todayStart),
                                  dated("DistantFuture",.distantFuture),dated("BeyondFuture",Date.distantFuture.addingTimeInterval(1))]
                    browser.update(items:values)
                    for (filter,names) in [(HistoryBrowser.DateFilter.lastHour,["Future","Now","HourAfter"]),
                                          (.yesterday,["AfterMidnight","BeforeLastSecond"]),
                                          (.last48,values.filter { !["48Exact","48Before","DistantFuture","BeyondFuture"].contains($0.name) }.map(\.name))] {
                        browser.setFilters(category:.all,date:filter)
                        try expect(browser.visibleItems.map(\.name) == names,"Calendar range \(filter)")
                    }
                    browser.setFilters(category:.all); try expect(browser.visibleItems.count == values.count,"All dates excludes future")
                    try expect(todayStart.timeIntervalSince(yesterdayStart) == 23*3600,"Fixture must cross DST")
                }
            }),
            ("Selection survives identical metadata refresh without full reload", {
                try browser { browser,_ in
                    let a = item("A"), b = item("B",-1)
                    browser.update(items:[a,b]); browser.select(ids:[b.id,a.id])
                    let full = browser.fullReloadCount
                    for _ in 0..<20 { browser.update(items:[a,b]) }
                    try expect(browser.fullReloadCount == full && browser.selectedIDs == [a.id,b.id],"Follow timer resets collection/selection")
                    var changed = a; changed.name = "Renamed"
                    browser.update(items:[changed,b])
                    try expect(browser.fullReloadCount == full && browser.partialReloadCount == 1,"Metadata update should reload only changed items")
                    try expect(browser.selectedIDs == [a.id,b.id] && browser.visibleItems[0].name == "Renamed","Metadata refresh changed identity")
                    browser.setFilters(category:.all,date:.yesterday)
                    try expect(browser.selectedIDs == [b.id],"Hidden selection must not leak to callbacks")
                }
            }),
            ("Moving recovered date windows expire unchanged timer entries", {
                for filter in [HistoryBrowser.DateFilter.lastHour,.last48] {
                    let suite = "OpenSnapHistoryTests."+UUID().uuidString, defaults = TestDefaults(name: suite)
                    defer { TestDefaults.dispose(defaults, name: suite) }
                    var clock = now
                    let browser = HistoryBrowser(defaults:defaults,calendar:calendar,now:{ clock }); defer { browser.close() }
                    var value = item("Expiring"); value.date = now.addingTimeInterval(filter == .lastHour ? -3599 : -172799)
                    browser.update(items:[value]); browser.setFilters(category:.all,date:filter); browser.select(ids:[value.id])
                    try expect(browser.visibleItems.count == 1,"Initial recovered window")
                    clock = now.addingTimeInterval(2); browser.update(items:[value])
                    try expect(browser.visibleItems.isEmpty && browser.selectedIDs.isEmpty,"Unchanged catalog bypasses moving date filter")
                }
            }),
            ("Midnight refresh changes day headings despite unchanged catalog", {
                let suite = "OpenSnapHistoryTests."+UUID().uuidString, defaults = TestDefaults(name: suite)
                defer { TestDefaults.dispose(defaults, name: suite) }
                var clock = now
                let browser = HistoryBrowser(defaults:defaults,calendar:calendar,now:{ clock }); defer { browser.close() }
                let a = item("A"); browser.update(items:[a]); try expect(browser.sections[0].title == "Today","Initial heading")
                clock = day(1); browser.update(items:[a])
                try expect(browser.sections[0].title == "Yesterday","Unchanged timer catalog freezes relative dates")
            }),
            ("All callbacks receive selected UUIDs in visual order", {
                try browser { browser,_ in
                    let a = item("A",action:"Shared",link:true), b = item("B",-1,action:"Shared",link:true)
                    browser.update(items:[b,a]); browser.select(ids:[b.id,a.id])
                    var calls: [[UUID]] = []
                    let callback: ([UUID]) -> Void = { calls.append($0) }
                    browser.onOpen = callback; browser.onCopy = callback; browser.onCopyLink = callback; browser.onOpenLink = callback
                    browser.onRemove = callback; browser.onDeleteFiles = callback; browser.onDeleteRemote = callback
                    // Delete from Web removes one post at a time: off for two entries (its tooltip says why), yet an attempt still reaches the app, which explains in a sheet.
                    for action in HistoryBrowser.Action.allCases { try expect(browser.canPerform(action) != (action == .deleteRemote),"Action not enabled \(action)"); browser.perform(action) }
                    try expect(calls.count == 7 && calls.allSatisfy { $0 == [b.id,a.id] },"Callbacks must use UUIDs in supplied visual order, not file locations")
                    browser.select(ids:[]); browser.perform(.remove); try expect(calls.count == 7,"Empty selection callback")
                }
            }),
            ("Missing local files disable local actions but preserve links and Remove", {
                try browser { browser,_ in
                    let missing = item("Missing",action:"Shared",missing:true,link:true), valid = item("Local",-1)
                    browser.update(items:[missing,valid]); browser.select(ids:[missing.id])
                    var calls: [UUID] = []
                    let callback: ([UUID]) -> Void = { calls += $0 }
                    browser.onOpen = callback; browser.onCopy = callback; browser.onCopyLink = callback; browser.onOpenLink = callback
                    browser.onRemove = callback; browser.onDeleteFiles = callback; browser.onDeleteRemote = callback
                    for action in [HistoryBrowser.Action.open,.copy,.deleteFiles] {
                        try expect(!browser.canPerform(action),"Missing local action enabled"); browser.perform(action)
                    }
                    try expect(calls.isEmpty,"Missing file invoked local callback")
                    for action in [HistoryBrowser.Action.copyLink,.openLink,.remove,.deleteRemote] { try expect(browser.canPerform(action),"Missing item loses available action") }
                    let labels = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }
                    try expect(labels.contains { !$0.isHidden && $0.stringValue.contains("file is missing") },"Missing warning absent")
                    try expect(labels.contains { !$0.isHidden && $0.stringValue.hasPrefix("Error: ") && $0.stringValue.contains("file is missing") },"Warning rows carry the Error: prefix, not colour alone")
                    browser.select(ids:[missing.id,valid.id]); try expect(!browser.canPerform(.open) && !browser.canPerform(.copyLink),"Mixed selection silently operates on subset")
                }
            }),
            ("Detail fields show supplied metadata and aggregate multiselection", {
                try browser { browser,_ in
                    var a = item("Project",action:"Exported"); a.destination = "Finder folder"
                    let b = item("Second",-1)
                    browser.update(items:[a,b]); browser.select(ids:[a.id])
                    let fields = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }
                    for text in ["Project","640 × 480","Exported","Finder folder"] {
                        try expect(fields.contains { $0.stringValue == text },"Detail omitted \(text)")
                    }
                    browser.select(ids:[a.id,b.id]); try expect(fields.contains { $0.stringValue == "2 items selected" },"Multiselect details")
                }
            }),
            ("Bounded local PNG preview renders in thumbnail and details then refreshes", {
                try browser { browser,_ in
                    let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at:directory) }
                    let url = directory.appendingPathComponent("preview.png")
                    @MainActor func write(_ color: NSColor) throws {
                        let rgb = color.usingColorSpace(.sRGB)!
                        let pixel = [UInt8(rgb.redComponent*255),UInt8(rgb.greenComponent*255),UInt8(rgb.blueComponent*255),UInt8(255)]
                        let bytes = Data((0..<12).flatMap { _ in pixel })
                        let image = CGImage(width:4,height:3,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:16,space:CGColorSpace(name:CGColorSpace.sRGB)!,
                                            bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:CGDataProvider(data:bytes as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
                        let bitmap = NSBitmapImageRep(cgImage:image)
                        try bitmap.representation(using:.png,properties:[:])!.write(to:url,options:.atomic)
                    }
                    try write(NSColor(srgbRed:1,green:0,blue:0,alpha:1))
                    var a = item("Preview"); a.previewURL = url; browser.update(items:[a]); browser.select(ids:[a.id])
                    let grid = try grid(browser), cell = browser.collectionView(grid,itemForRepresentedObjectAt:IndexPath(item:0,section:0))
                    let cellImages = descendants(cell.view).compactMap { $0 as? NSImageView }
                    try expect(cellImages.contains { $0.image != nil && !$0.isHidden },"Grid shows no decoded thumbnail")
                    let detailImage = descendants(browser.window!.contentView!).compactMap { $0 as? NSImageView }.first { $0.accessibilityLabel() == "Selected history preview" }!
                    func pixel(_ image: NSImage) -> NSColor {
                        let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil)!
                        return NSBitmapImageRep(cgImage:cg).colorAt(x:0,y:0)!.usingColorSpace(.sRGB)!
                    }
                    try expect(pixel(detailImage.image!).redComponent > 0.95,"Decoded preview does not retain red pixels")
                    try write(NSColor(srgbRed:0,green:0,blue:1,alpha:1)); a.text = "new version"; browser.update(items:[a])
                    try expect(pixel(detailImage.image!).blueComponent > 0.95,"Metadata refresh retains stale preview pixels")
                    a.missing = true; browser.update(items:[a]); try expect(detailImage.image == nil,"Missing preview still displayed")
                }
            }),
            ("Keyboard Open Copy Copy Link Remove use UUID callbacks", {
                try browser { browser,_ in
                    let a = item("A",link:true); browser.update(items:[a]); browser.select(ids:[a.id])
                    var actions: [HistoryBrowser.Action] = []
                    browser.onOpen = { _ in actions.append(.open) }; browser.onCopy = { _ in actions.append(.copy) }
                    browser.onCopyLink = { _ in actions.append(.copyLink) }; browser.onRemove = { _ in actions.append(.remove) }
                    let grid = try grid(browser)
                    for (code,flags,text) in [(UInt16(36),NSEvent.ModifierFlags(),"\r"),(8,.command,"c"),(8,[.command,.shift],"c"),(51,[],"\u{7f}")] {
                        let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!
                        grid.keyDown(with:event)
                    }
                    try expect(actions == [.open,.copy,.copyLink,.remove],"Native keyboard callback mapping")
                }
            }),
            ("Return opens the selection, Escape closes the window, and the grid starts with the keyboard (OSN-060)", {
                try browser { browser,_ in
                    let a = item("A"), b = item("B"), gone = item("Gone",missing:true)
                    browser.update(items:[a,b,gone])
                    var opened: [[UUID]] = []
                    browser.onOpen = { opened.append($0) }
                    let grid = try grid(browser)
                    try expect(browser.window?.initialFirstResponder === grid,"The grid is where the keyboard starts")
                    func press(_ code: UInt16,_ text: String) {
                        grid.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!)
                    }
                    press(36,"\r")
                    try expect(opened.isEmpty,"Return with nothing selected opens nothing")
                    browser.select(ids:[b.id]); press(36,"\r")
                    try expect(opened == [[b.id]],"Return opens the selected item")
                    browser.select(ids:[a.id]); press(76,"\r")
                    try expect(opened == [[b.id],[a.id]],"Enter on the keypad opens it too")
                    browser.select(ids:[gone.id]); press(36,"\r")
                    try expect(opened.count == 2,"Return does not open an item whose file is missing")
                    var closed = 0
                    let token = NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:browser.window,queue:nil) { _ in closed += 1 }
                    defer { NotificationCenter.default.removeObserver(token) }
                    press(53,"\u{1b}")
                    try expect(closed == 1,"Escape on the grid closes the History window")
                }
                // Escape from any other control reaches the window controller through the responder chain.
                try browser { other,_ in
                    var closed = 0
                    let token = NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:other.window,queue:nil) { _ in closed += 1 }
                    defer { NotificationCenter.default.removeObserver(token) }
                    other.cancelOperation(nil)
                    try expect(closed == 1,"Escape reaching the window controller from another control closes the window as well")
                }
            }),
            ("All readable UI fonts satisfy minimum and grid captions use twenty", {
                try browser { browser,_ in
                    let a = item("A"); browser.update(items:[a])
                    let grid = try grid(browser)
                    let cell = browser.collectionView(grid,itemForRepresentedObjectAt:IndexPath(item:0,section:0))
                    let views = descendants(browser.window!.contentView!)+descendants(cell.view)
                    let controls = views.compactMap { $0 as? NSControl }
                    try expect(controls.allSatisfy { drawnSizes($0).allSatisfy { $0 >= 18 } },"Readable control below 18pt: \(controls.filter { !drawnSizes($0).allSatisfy { $0 >= 18 } }.map { String(describing: type(of: $0)) })")
                    let fields = descendants(cell.view).compactMap { $0 as? NSTextField }
                    try expect(fields.contains { $0.stringValue == "A" && $0.font!.pointSize >= 20 },"Thumbnail name below20")
                    browser.window!.contentView!.layoutSubtreeIfNeeded()
                    // OSN-053: the 1000 x 720 window keeps the details panel beside the grid, so the grid is narrower than in the old 1180 window.
                    try expect(grid.enclosingScrollView!.frame.width > 600 && grid.enclosingScrollView!.frame.height >= 240,"Grid collapsed instead of filling window")
                }
            }),
            ("History drag format has independent persistence and strict choices", {
                try browser { browser,defaults in
                    defaults.set("pdf",forKey:"OpenSnap.ExportFormat")
                    try expect(browser.dragFormat == "png","Default History format")
                    for format in HistoryBrowser.dragFormats { browser.setDragFormat(format); try expect(browser.dragFormat == format,"Format missing") }
                    browser.setDragFormat("exe"); try expect(browser.dragFormat == "opensnap","Unsupported format persisted")
                    try expect(defaults.string(forKey:"OpenSnap.ExportFormat") == "pdf","History changes editor export preference")
                    let reopened = HistoryBrowser(defaults:defaults,calendar:calendar,now:{ now }); defer { reopened.close() }
                    try expect(reopened.dragFormat == "opensnap","History format not restored")
                }
            }),
            ("File promise freezes export bytes name and format at drag start", {
                try browser { browser,_ in
                    let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at:directory) }
                    let a = item("Original.opensnap"); browser.update(items:[a]); browser.setDragFormat("jpeg")
                    var captures: [(UUID,String)] = []
                    let expected = Data("immutable snapshot with native/pan data".utf8)
                    browser.onExport = { id,format in captures.append((id,format)); return expected }
                    guard let promise = browser.dragPromise(for:a.id) as? HistoryFilePromise else { throw Failure("No file promise") }
                    try expect(captures.count == 1 && captures[0].0 == a.id && captures[0].1 == "jpeg","Drag does not capture now")
                    browser.setDragFormat("svg"); browser.onExport = { _,_ in throw Failure("Late export") }; browser.update(items:[])
                    try expect(promise.snapshot.filename == "Original.jpg" && promise.snapshot.typeIdentifier == UTType.jpeg.identifier,"Promised name/format changed")
                    let target = directory.appendingPathComponent(promise.snapshot.filename)
                    var completed = 0, failure: Error?
                    promise.snapshot.filePromiseProvider(promise,writePromiseTo:target) { error in completed += 1; failure = error }
                    try expect(completed == 1 && failure == nil && (try Data(contentsOf:target)) == expected,"Promise lost snapshot after catalog removal")
                    try expect(captures.count == 1,"Promise reexports at write time")
                }
            }),
            ("Promise sanitizes filenames and reports export failure without promise", {
                try browser { browser,_ in
                    let a = item("../../secret:bad\\name\0.png"); browser.update(items:[a]); browser.setDragFormat("opensnap")
                    browser.onExport = { _,_ in Data("SVG snapshot".utf8) }
                    let promise = browser.dragPromise(for:a.id) as! HistoryFilePromise
                    try expect(!promise.snapshot.filename.contains("/") && !promise.snapshot.filename.contains("\\") && !promise.snapshot.filename.contains(":"),"Filename permits path traversal")
                    try expect(promise.snapshot.filename.hasSuffix(".opensnap"),"Native promise extension")
                    var errors = 0; browser.onError = { _ in errors += 1 }
                    browser.onExport = { _,_ in throw Failure("Export refused") }
                    try expect(browser.dragPromise(for:a.id) == nil && errors == 1,"Export error silently ignored")
                    var missing = a; missing.missing = true; browser.update(items:[missing])
                    try expect(browser.dragPromise(for:a.id) == nil && errors == 1,"Missing file attempts export")
                }
            }),
            ("Duplicate UUID input stays unambiguous and removed items lose selection", {
                try browser { browser,_ in
                    let a = item("First"); var duplicate = a; duplicate.name = "Duplicate"
                    browser.update(items:[a,duplicate]); try expect(browser.visibleItems.count == 1 && browser.visibleItems[0].name == "First","Duplicate ID ambiguity")
                    browser.select(ids:[a.id]); browser.update(items:[])
                    try expect(browser.selectedIDs.isEmpty,"Removed item remains selected")
                }
            }),
            ("Window opens 1000 x 720 with an 880 x 600 minimum", {
                try browser { browser,_ in
                    try expect(browser.window!.frame.size == NSSize(width:1000,height:720),"Default History size is \(browser.window!.frame.size)")
                    try expect(browser.window!.minSize == NSSize(width:880,height:600),"Minimum History size is \(browser.window!.minSize)")
                }
            }),
            ("Tabs use plain names", {
                try browser { browser,_ in
                    let segmented = try descendants(browser.window!.contentView!).compactMap { $0 as? GlassChoiceGroup }.first { $0.accessibilityLabel() == "History category" }.unwrap("category control")
                    let labels = segmented.buttons.map(\.title)
                    try expect(labels == ["All","Shared","Exported","Saved"],"Tab names are \(labels)")
                    try expect(HistoryBrowser.Category.allCases.map(\.title) == labels,"Category titles match the control")
                    try expect(!labels.joined().contains("DragMe") && !labels.joined().contains("/"),"The cramped Saved/DragMe'd name is gone")
                    // One vocabulary: a tab holds exactly the tiles whose label is its name.
                    let all = ["Saved","Exported","Shared"].map { item("Tile "+$0,action:$0) }
                    browser.update(items:all)
                    for category in HistoryBrowser.Category.allCases.dropFirst() {
                        browser.setFilters(category:category)
                        try expect(browser.visibleItems.map(\.action) == [category.title],"Tab \(category.title) holds \(browser.visibleItems.map(\.action))")
                    }
                }
            }),
            ("Grid reflows at the 880 x 600 minimum with no horizontal scroller", {
                try browser { browser,_ in
                    browser.update(items:(0..<18).map { item("Tile \($0)",-($0/3)) })
                    laidOut(browser,width:1000,height:720)
                    let wide = try tileFrames(browser)
                    laidOut(browser,width:880,height:600)
                    let scroll = try grid(browser).enclosingScrollView.unwrap("grid scroll view")
                    let narrow = try tileFrames(browser)
                    try expect(!scroll.hasHorizontalScroller,"Horizontal scrolling must be off; the grid reflows instead")
                    let clip = scroll.contentView.bounds.width
                    try expect(try grid(browser).frame.width <= clip + 0.5,"The grid is wider than its clip view (\(try grid(browser).frame.width) > \(clip)): it would scroll sideways")
                    try expect(narrow.allSatisfy { $0.maxX <= clip + 0.5 },"A tile pokes past the right edge at 880 wide (clip \(clip), max \(narrow.map(\.maxX).max() ?? 0))")
                    func columns(_ frames: [NSRect]) -> Int { Set(frames.map { Int($0.minX.rounded()) }).count }
                    try expect(columns(narrow) >= 2,"Minimum width fits fewer than two tile columns: \(columns(narrow))")
                    try expect(columns(wide) > columns(narrow),"The grid does not reflow: \(columns(wide)) columns wide, \(columns(narrow)) at the minimum")
                    try expect(narrow.allSatisfy { $0.width >= 209.5 && abs($0.height - HistoryBrowser.tileHeight(forTileWidth:$0.width)) < 0.5 },"Tiles are at least 210 wide and as tall as their preview and two text lines: \(narrow.map(\.size))")
                    // Nothing sits under the captions: the tile is its preview plus two lines, and the preview grows with the tile.
                    try expect(narrow.allSatisfy { $0.height < 230 },"Tiles still reserve blank space under the captions: \(narrow.map(\.height))")
                    try expect(HistoryBrowser.previewHeight(forTileWidth:300) > HistoryBrowser.previewHeight(forTileWidth:210),"A stretched tile keeps a small preview")
                }
            }),
            ("Extra width becomes another column, never a tile wider than 280; the Drag as face stays within its cap; a never-shared snap has no Destination row (R2-015)", {
                for grid in stride(from:420.0,through:2600.0,by:20.0) {
                    let tile = HistoryBrowser.tileWidth(forGridWidth:grid)
                    let columns = max(1,((grid - 2 * HistoryBrowser.gridSideInset + HistoryBrowser.tileGap) / (tile + HistoryBrowser.tileGap)).rounded(.down))
                    // A tile is over the cap only where one more column would make every tile narrower than the minimum.
                    let next = (grid - 2 * HistoryBrowser.gridSideInset - columns * HistoryBrowser.tileGap) / (columns + 1)
                    try expect(tile <= HistoryBrowser.maximumTileWidth || next < HistoryBrowser.minimumTileWidth,"a \(grid) wide grid keeps its tiles at or under \(HistoryBrowser.maximumTileWidth) unless another column would be too narrow (tile \(tile), \(columns) columns, next \(next))")
                    if columns > 1 { try expect(tile >= HistoryBrowser.minimumTileWidth,"…and at least \(HistoryBrowser.minimumTileWidth) (tile \(tile))") }
                }
                try browser { browser,_ in
                    let content = try browser.window?.contentView.unwrap("content view") ?? NSView()
                    browser.update(items:[item("Local",0)]); browser.select(ids:[browser.visibleItems[0].id]); laidOut(browser,width:1000,height:720)
                    let pop = browser.dragFormatPopUp
                    let plate = try glassPlate(of:pop).unwrap("format plate")
                    try expect(plate.frame.width <= HistoryBrowser.formatPopupMaximumWidth + 0.5,"the format face is \(plate.frame.width) wide")
                    let longest = HistoryBrowser.dragFormats.map { ceil((HistoryBrowser.dragFormatTitle($0) as NSString).size(withAttributes:[.font:DesignTokens.Typography.font(.body)]).width) }.max() ?? 0
                    try expect(pop.frame.width >= longest + GlassChoiceButton.glyphSide,"the format face holds its longest name whole (\(pop.frame.width) for \(longest))")
                    let destination = try descendants(content).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Destination" }.unwrap("Destination value")
                    try expect(destination.superview?.isHidden == true,"a snap that was never shared has no Destination row")
                }
            }),
            ("Tiles in a row are evenly spaced, with no large gap, at 880, 1000 and 1280", {
                try browser { browser,_ in
                    // Nine snaps on one day so a wide window has full rows, plus three on an earlier day for a short row.
                    browser.update(items:(0..<9).map { item("Today \($0)",0) } + (0..<3).map { item("Earlier \($0)",-3) })
                    for (width,expectedColumns) in [(880.0,2),(1000.0,3),(1280.0,4)] as [(CGFloat,Int)] {
                        laidOut(browser,width:width,height:720)
                        let frames = try tileFrames(browser)
                        var rows: [Int: [NSRect]] = [:]
                        for frame in frames { rows[Int(frame.minY.rounded()),default:[]].append(frame) }
                        let widest = rows.values.map(\.count).max() ?? 0
                        try expect(widest == expectedColumns,"\(width) wide fits \(widest) columns, expected \(expectedColumns)")
                        var gaps: [CGFloat] = []
                        for row in rows.values {
                            let ordered = row.sorted { $0.minX < $1.minX }
                            gaps += zip(ordered,ordered.dropFirst()).map { $1.minX - $0.maxX }
                        }
                        try expect(!gaps.isEmpty,"\(width) wide has no row with two tiles to measure")
                        let spread = (gaps.max() ?? 0) - (gaps.min() ?? 0)
                        try expect(spread <= 1,"Gaps between tiles are uneven at \(width) wide: \(gaps.sorted())")
                        try expect((gaps.max() ?? 0) <= 24,"A gap between tiles is wider than 24 pt at \(width) wide: \(gaps.sorted())")
                        // Rows with fewer tiles start at the same columns as full rows rather than spreading out.
                        let fullRow = (rows.values.first { $0.count == widest } ?? []).map(\.minX).sorted()
                        for row in rows.values where row.count < widest {
                            for (index,frame) in row.sorted(by:{ $0.minX < $1.minX }).enumerated() {
                                try expect(abs(frame.minX - fullRow[index]) <= 1,"A short row spreads its tiles at \(width) wide: \(row.map(\.minX)) vs \(fullRow)")
                            }
                        }
                    }
                }
            }),
            ("Details panel sits beside the grid and collapses below it under 760 wide", {
                try browser { browser,_ in
                    browser.update(items:[item("A")]); laidOut(browser,width:1000,height:720)
                    let scroll = try grid(browser).enclosingScrollView.unwrap("grid scroll view"), content = browser.window!.contentView!
                    @MainActor func frame(_ view: NSView) -> NSRect { view.convert(view.bounds,to:content) }
                    try expect(browser.detailsPlacement == .beside && frame(browser.detailsPanel).minX >= frame(scroll).maxX - 0.5,"Wide windows put details beside the grid")
                    browser.layoutDetails(forContentWidth:759)
                    content.layoutSubtreeIfNeeded()
                    try expect(browser.detailsPlacement == .below,"Under 760 the placement is not .below")
                    try expect(frame(browser.detailsPanel).maxY <= frame(scroll).minY + 0.5 && frame(browser.detailsPanel).height > 0,"Under 760 the details panel is not under the grid")
                    browser.layoutDetails(forContentWidth:760)
                    try expect(browser.detailsPlacement == .beside,"760 is wide enough for the side panel")
                }
            }),
            ("Selected tile shows an accent border and a check badge, not colour alone", {
                try browser { browser,_ in
                    let a = item("Picked"); browser.update(items:[a]); laidOut(browser,width:1000,height:720)
                    let grid = try grid(browser)
                    let cell = browser.collectionView(grid,itemForRepresentedObjectAt:IndexPath(item:0,section:0))
                    guard let tile = cell.view as? HistoryTileView else { throw Failure("The tile is not a HistoryTileView") }
                    let badge = try tile.checkBadge.unwrap("check badge subview")
                    try expect(badge.superview === tile && badge.image != nil,"The badge is not an image subview of the tile")
                    try expect(badge.image?.isTemplate == true && ChromeIcons.resolve(.circleCheck,family:.solid,pointSize:DesignTokens.Typography.iconPrimary).source != .none,"The badge is the chrome's check-circle icon, tinted as a template")
                    try expect(badge.isHidden && !tile.isTileSelected,"An unselected tile must not show the badge")
                    tile.updateLayer(); try expect(tile.layer?.borderWidth == 0,"An unselected tile has a border")
                    cell.isSelected = true
                    try expect(!badge.isHidden,"A selected tile shows no check badge: the cue would be colour only")
                    tile.updateLayer(); try expect(tile.layer?.borderWidth == 2,"A selected tile has no accent border")
                    try expect(tile.accessibilityValue() as? String == "Selected","VoiceOver is not told the tile is selected")
                    cell.isSelected = false
                    try expect(badge.isHidden,"Deselecting leaves the badge showing")
                    // Through the real selection path, when AppKit has made the item.
                    browser.select(ids:[a.id])
                    if let live = grid.item(at:IndexPath(item:0,section:0)) as NSCollectionViewItem?, let liveTile = live.view as? HistoryTileView {
                        try expect(liveTile.isTileSelected && !(liveTile.checkBadge?.isHidden ?? true),"Selecting through the browser does not badge the live tile")
                    }
                }
            }),
            ("A tile fills on hover with state.hover; a selected tile keeps its stronger fill and its badge", {
                try browser { browser,_ in
                    let a = item("Hovered"); browser.update(items:[a]); laidOut(browser,width:1000,height:720)
                    let grid = try grid(browser)
                    let cell = browser.collectionView(grid,itemForRepresentedObjectAt:IndexPath(item:0,section:0))
                    guard let tile = cell.view as? HistoryTileView else { throw Failure("The tile is not a HistoryTileView") }
                    tile.appearance = NSAppearance(named:.aqua)
                    @MainActor func fillAlpha() -> CGFloat? { tile.updateLayer(); return tile.layer?.backgroundColor.flatMap { NSColor(cgColor:$0)?.alphaComponent } }
                    @MainActor func fillColor() -> NSColor? { tile.updateLayer(); return tile.layer?.backgroundColor.flatMap { NSColor(cgColor:$0)?.usingColorSpace(.sRGB) } }
                    try expect(!tile.isHovered && (fillAlpha() ?? 0) < 0.001,"A resting tile has no fill")
                    tile.updateTrackingAreas()
                    try expect(tile.trackingAreas.contains { $0.options.contains(.mouseEnteredAndExited) && $0.options.contains(.inVisibleRect) },"The tile tracks the pointer over its visible rect")
                    tile.mouseEntered(with:NSEvent.mouseEvent(with:.mouseMoved,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:0,pressure:0)!)
                    try expect(tile.isHovered && abs((fillAlpha() ?? 0) - 0.08) < 0.004,"Hover is the 0.08 label fill: \(fillAlpha() ?? -1)")
                    try expect(tile.layer?.borderWidth == 0 && tile.checkBadge?.isHidden == true,"Hover adds no border and no badge")
                    cell.isSelected = true
                    let accent = DesignTokens.Palette.resolve(DesignTokens.Palette.accent,for:tile.effectiveAppearance)
                    try expect(abs((fillAlpha() ?? 0) - 0.20) < 0.004 && abs((fillColor()?.blueComponent ?? 0) - accent.blueComponent) < 0.02,"A hovered selected tile keeps the 0.20 accent fill, not the hover wash")
                    try expect(tile.checkBadge?.isHidden == false && tile.layer?.borderWidth == 2,"The check badge and border stay")
                    cell.isSelected = false
                    tile.mouseExited(with:NSEvent.mouseEvent(with:.mouseMoved,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:0,pressure:0)!)
                    try expect(!tile.isHovered && (fillAlpha() ?? 0) < 0.001,"Leaving clears the fill")
                    tile.setHovered(true); tile.viewDidHide()
                    try expect(!tile.isHovered,"Hiding clears hover")
                }
            }),
            ("Empty state is centred and its hint follows the live Save to History shortcut", {
                try browser { browser,_ in
                    laidOut(browser,width:1000,height:720)
                    let scroll = try grid(browser).enclosingScrollView.unwrap("grid scroll view"), content = browser.window!.contentView!
                    try expect(!browser.emptyState.isHidden && browser.emptyTitle.stringValue == "No history yet","Empty History shows no empty state")
                    let box = browser.emptyState.convert(browser.emptyState.bounds,to:content), well = scroll.convert(scroll.bounds,to:content)
                    try expect(abs(box.midX - well.midX) < 1.5 && abs(box.midY - well.midY) < 1.5,"Empty state is off-centre: \(box) in \(well)")
                    // This test process has no main menu, so no shortcut is invented.
                    try expect(browser.emptyHint.stringValue == "Use Save to History to keep a snap","Hint without a shortcut: \(browser.emptyHint.stringValue)")
                    browser.saveShortcut = { "⌘S" }; browser.setFilters(category:.all)
                    try expect(browser.emptyHint.stringValue == "Press ⌘S to save a snap","Hint with a shortcut: \(browser.emptyHint.stringValue)")
                    browser.saveShortcut = { nil }; browser.setFilters(category:.all)
                    try expect(browser.emptyHint.stringValue == "Use Save to History to keep a snap","Hint after the shortcut is removed")
                    browser.update(items:[item("One")])
                    try expect(browser.emptyState.isHidden,"The empty state stays over a populated grid")
                    browser.setFilters(category:.all,query:"zzz")
                    try expect(!browser.emptyState.isHidden && browser.emptyTitle.stringValue.contains("match") && !browser.emptyHint.isHidden && !browser.emptyHint.stringValue.contains("save"),"Filtered-out History says no items match and how to get them back, with no save hint")
                    try expect(!browser.clearFiltersButton.isHidden && browser.clearFiltersButton.title == "Clear filters","A no-match state has no Clear filters button")
                    try expect(browser.statusLine == "0 of 1 item","The footer is gone from the no-match state: \(browser.statusLine)")
                    browser.clearFilters()
                    try expect(browser.emptyState.isHidden && browser.visibleItems.count == 1 && !browser.filtersAreActive,"Clear filters does not restore the list")
                    browser.update(items:[])
                    try expect(browser.clearFiltersButton.isHidden,"An empty History offers to clear filters it does not have")
                }
            }),
            ("Save to History shortcut is read from the main menu, never invented", {
                func menu(key: String,mask: NSEvent.ModifierFlags) -> NSMenu {
                    let main = NSMenu(), file = NSMenuItem(title:"File",action:nil,keyEquivalent:""), sub = NSMenu(title:"File")
                    let other = NSMenuItem(title:"Save Editable Document",action:NSSelectorFromString("saveFile"),keyEquivalent:"s")
                    let save = NSMenuItem(title:"Save to History",action:NSSelectorFromString("saveHistory"),keyEquivalent:key); save.keyEquivalentModifierMask = mask
                    sub.addItem(other); sub.addItem(save); file.submenu = sub; main.addItem(file); return main
                }
                try expect(HistoryBrowser.liveSaveToHistoryShortcut(menu:menu(key:"",mask:.command)) == nil,"A menu item with no key equivalent produced a shortcut")
                try expect(HistoryBrowser.liveSaveToHistoryShortcut(menu:menu(key:"h",mask:.command)) == "⌘H","Command-H")
                try expect(HistoryBrowser.liveSaveToHistoryShortcut(menu:menu(key:"S",mask:.command)) == "⇧⌘S","Uppercase key implies Shift")
                try expect(HistoryBrowser.liveSaveToHistoryShortcut(menu:menu(key:"h",mask:[.command,.option])) == "⌥⌘H","Option-Command-H")
                try expect(HistoryBrowser.liveSaveToHistoryShortcut(menu:nil) == nil,"No main menu means no shortcut")
                try expect(HistoryBrowser.liveSaveToHistoryShortcut(menu:NSMenu()) == nil,"A menu without the item means no shortcut")
            }),
            ("Drag formats are PNG JPG PDF TIFF SVG and the .opensnap document", {
                try browser { browser,_ in
                    let titles = HistoryBrowser.dragFormats.map(HistoryBrowser.dragFormatTitle)
                    try expect(titles == ["PNG","JPG","PDF","TIFF","SVG",".opensnap document"],"Drag format titles are \(titles)")
                    let popup = browser.dragFormatPopUp
                    try expect(popup.itemTitles == titles && popup.accessibilityLabel() == "History drag export format","The popup model holds \(popup.itemTitles)")
                    let choices = popup.choicePanel
                    choices.host.presenter = { _,_ in }; browser.window?.contentView?.layoutSubtreeIfNeeded()
                    popup.performClick(nil)
                    try expect(choices.rows.map(\.title) == titles && !choices.rows.contains { $0.title.lowercased().contains(["ski","tch"].joined()) },"The choice panel lists \(choices.rows.map(\.title))")
                    choices.host.close()
                    try expect(!popup.itemTitles.joined().lowercased().contains(["ski","tch"].joined()),"The format popup names the retired product")
                }
            }),
            ("The seven actions are a toolbar row and a context menu, each with a name for VoiceOver", {
                try browser { browser,_ in
                    let row = actionButtons(browser)
                    try expect(row.count == 7,"The action row has \(row.count) buttons")
                    try expect(Set(HistoryBrowser.Action.allCases.map(\.icon)).count == 7,"Each action has its own icon")
                    for (button,action) in zip(row,HistoryBrowser.Action.allCases) {
                        try expect(button.toolTip == action.title && button.accessibilityLabel() == action.title,"\(action) has no tooltip and accessibility name")
                        try expect(button.image != nil && (button.imagePosition == .imageOnly || button.imagePosition == .imageLeading),"\(action) has no glyph")
                        let source = ChromeIcons.resolve(action.icon,pointSize:DesignTokens.Typography.iconInline).source
                        if case .sfSymbol = source { throw Failure("\(action) draws an SF Symbol instead of the chrome icon family: \(source)") }
                        try expect(button.image?.isTemplate == true,"\(action) glyph is a template image, so it follows the label colour")
                        try expect(!button.isEnabled,"\(action) is enabled with nothing selected")
                    }
                    // The old layout stacked the same seven in two text-button rows under the details.
                    let textButtons = descendants(browser.window!.contentView!).compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) && !($0 is GlassChoiceButton) && $0 !== browser.clearFiltersButton && !$0.title.isEmpty }
                    try expect(textButtons.allSatisfy { $0.image != nil },"Only the action row carries labels, and each beside its icon: \(textButtons.map(\.title))")
                    let menu = try grid(browser).menu.unwrap("context menu")
                    try expect(menu.items.map(\.title) == HistoryBrowser.Action.allCases.map(\.title),"Context menu items: \(menu.items.map(\.title))")
                    let a = item("A",action:"Shared",link:true); browser.update(items:[a]); browser.select(ids:[a.id])
                    browser.onOpen = { _ in }; browser.onCopy = { _ in }
                    try expect(row[0].isEnabled && row[1].isEnabled && !row[2].isEnabled,"Row buttons keep their validation")
                }
            }),
            ("The action row shows icon and label while the window holds them, keeps the three that take something away labelled at the 880 minimum, and never clips (R1-012)", {
                try browser { browser,_ in
                    let content = try browser.window?.contentView.unwrap("content view") ?? NSView()
                    func show(width: CGFloat) throws -> [HistoryBrowser.Action: NSButton] {
                        let frame = browser.window!.frameRect(forContentRect: NSRect(x:0,y:0,width:width,height:720))
                        browser.window!.setFrame(NSRect(origin:browser.window!.frame.origin,size:frame.size),display:false)
                        content.layoutSubtreeIfNeeded(); browser.windowDidResize(Notification(name:NSWindow.didResizeNotification,object:browser.window)); content.layoutSubtreeIfNeeded()
                        let row = MainActor.assumeIsolated { actionButtons(browser) }
                        return Dictionary(uniqueKeysWithValues: zip(HistoryBrowser.Action.allCases,row))
                    }
                    let destructive: [HistoryBrowser.Action] = [.remove,.deleteFiles,.deleteRemote]
                    var labels: [CGFloat: HistoryBrowser.ActionLabels] = [:]
                    for width in [HistoryBrowser.minimumSize.width,1000,1400] as [CGFloat] {
                        let buttons = try show(width:width)
                        labels[width] = browser.actionLabels
                        let rowBox = browser.actionRow.convert(browser.actionRow.bounds,to:content), formatBox = try glassPlate(of:browser.dragFormatPopUp).unwrap("format plate")
                        for (action,button) in buttons {
                            let shown = !button.title.isEmpty
                            try expect(shown == (browser.actionLabels == .all || (browser.actionLabels == .destructiveOnly && destructive.contains(action))), "\(Int(width)): \(action) label follows the mode \(browser.actionLabels)")
                            if shown { try expect(button.title == action.shortTitle && button.imagePosition == .imageLeading && (button.font?.pointSize ?? 0) >= 20, "\(Int(width)): \(action) shows its short title beside its icon at 20 pt") }
                            else { try expect(button.imagePosition == .imageOnly && button.image != nil && button.toolTip == action.title, "\(Int(width)): \(action) is an icon with its full name as tooltip") }
                            let box = button.convert(button.bounds,to:content)
                            try expect(box.minX >= rowBox.minX - 0.5 && box.maxX <= rowBox.maxX + 0.5 && box.maxX <= content.bounds.maxX,
                                       "\(Int(width)): \(action) sits inside the row, unclipped (\(box) in \(rowBox))")
                            try expect(box.width >= DesignTokens.Size.tool.width - 0.5 && box.height >= DesignTokens.Size.control - 0.5, "\(Int(width)): \(action) is a full-size target (\(box.size))")
                        }
                        try expect(destructive.allSatisfy { !buttons[$0]!.title.isEmpty }, "\(Int(width)): Hide, Trash and Delete from Web keep their labels")
                        let formatInFooter = formatBox.convert(formatBox.bounds,to:content)
                        try expect(browser.footerRow.arrangedSubviews.contains(formatBox) && content.bounds.contains(formatInFooter) && formatInFooter.maxX <= content.bounds.maxX - DesignTokens.Space.s4 + 0.5,
                                   "\(Int(width)): the drag format sits at the end of the footer line, whole (\(formatInFooter))")
                    }
                    // F-J6-006/R2-005: with every label showing the row must not hold the window open; its fitting width stays under the 880 minimum.
                    _ = try show(width:1000)
                    try expect(browser.actionLabels == .all && content.fittingSize.width <= HistoryBrowser.minimumSize.width, "with every label showing, the window's own minimum is still 880 (fits at \(content.fittingSize.width))")
                    // A drag inward is decided from the width the window is about to have: 880 is accepted and collapses the labels first.
                    let proposed = browser.window!.frameRect(forContentRect:NSRect(x:0,y:0,width:880,height:720)).size
                    try expect(browser.windowWillResize(browser.window!,to:proposed) == proposed && browser.actionLabels == .destructiveOnly && browser.window!.minSize.width == 880,
                               "a resize to 880 is accepted, with the labels already collapsed (\(browser.actionLabels), min \(browser.window!.minSize))")
                    try expect(labels[HistoryBrowser.minimumSize.width] == .destructiveOnly, "at the 880 minimum only the three destructive ones carry labels (\(String(describing: labels[880])))")
                    try expect(labels[1000] == .all, "the default 1000 pt window labels every action (\(String(describing: labels[1000])))")
                    try expect(labels[1400] == .all, "a wide window labels every action (\(String(describing: labels[1400])))")
                    try expect(HistoryBrowser.Action.remove.icon == .folderMinus && HistoryBrowser.Action.remove.icon != .eyeSlash && HistoryBrowser.Action.remove.shortTitle == "Hide",
                               "Hide from History is a folder-minus, not the editor's eye-slash (which means hide the window there)")
                }
            }),
            ("The footer pluralises and stays on screen in every state", {
                try expect(HistoryBrowser.statusText(shown:1,total:1,selected:0) == "1 item · 0 selected","One item: \(HistoryBrowser.statusText(shown:1,total:1,selected:0))")
                try expect(HistoryBrowser.statusText(shown:6,total:6,selected:2) == "6 items · 2 selected","Several items")
                try expect(HistoryBrowser.statusText(shown:2,total:6,selected:0) == "2 of 6 items · 0 selected","A filtered view says how many exist")
                try expect(HistoryBrowser.statusText(shown:1,total:6,selected:1) == "1 of 6 items · 1 selected","A filtered view of one")
                try expect(HistoryBrowser.statusText(shown:0,total:1,selected:0) == "0 of 1 item","Everything filtered out, one item exists")
                try expect(HistoryBrowser.statusText(shown:0,total:0,selected:0) == "No items","An empty History")
                try browser { browser,_ in
                    try expect(browser.statusLine == "No items","Empty History footer is \(browser.statusLine)")
                    browser.update(items:[item("One")]); try expect(browser.statusLine == "1 item · 0 selected","Footer is \(browser.statusLine)")
                    browser.setFilters(category:.all,query:"nothing like this")
                    try expect(browser.statusLine == "0 of 1 item","A no-match History keeps its footer: \(browser.statusLine)")
                }
            }),
            ("Copy and Copy Link confirm in the footer only when the pasteboard changed", {
                try browser { browser,_ in
                    let a = item("Shared one",action:"Shared",link:true); browser.update(items:[a]); browser.select(ids:[a.id])
                    var count = 10
                    browser.pasteboardChangeCount = { count }
                    browser.onCopy = { _ in count += 1 }; browser.onCopyLink = { _ in count += 1 }
                    browser.perform(.copyLink)
                    try expect(browser.statusLine == "Link copied","Copy Link left the footer at \(browser.statusLine)")
                    browser.perform(.copy)
                    try expect(browser.statusLine == "Image copied","Copy left the footer at \(browser.statusLine)")
                    browser.select(ids:[]); browser.collectionView(try grid(browser),didDeselectItemsAt:[])
                    try expect(browser.statusLine == "1 item · 0 selected","A new selection did not clear the confirmation: \(browser.statusLine)")
                    browser.select(ids:[a.id]); browser.onCopy = { _ in } // a failed copy writes nothing
                    browser.perform(.copy)
                    try expect(browser.statusLine == "1 item · 1 selected","A copy that wrote nothing was confirmed: \(browser.statusLine)")
                    browser.onCopyLink = { _ in count += 1 }; browser.perform(.copyLink)
                    browser.update(items:[a]) // a catalog refresh keeps the message
                    try expect(browser.statusLine == "Link copied","A refresh dropped the confirmation: \(browser.statusLine)")
                    browser.clearConfirmation()
                    try expect(browser.statusLine == "1 item · 1 selected","Clearing did not restore the counts: \(browser.statusLine)")
                    try expect(HistoryBrowser.confirmationDuration >= 3,"The confirmation is too brief to read")
                }
            }),
            ("Delete from Web is off, with its reason in the tooltip, for a published entry with no recorded destination", {
                try browser { browser,_ in
                    var recorded = item("Recorded",action:"Shared",link:true), legacy = item("Legacy",action:"Shared",link:true)
                    recorded.canDeleteFromWeb = true; legacy.canDeleteFromWeb = false
                    browser.onDeleteRemote = { _ in }; browser.onCopyLink = { _ in }
                    browser.update(items:[recorded,legacy])
                    let button = try actionButtons(browser).first { $0.accessibilityLabel() == HistoryBrowser.Action.deleteRemote.title }.unwrap("Delete from Web button")
                    browser.select(ids:[recorded.id])
                    try expect(browser.canPerform(.deleteRemote) && button.isEnabled && (AppToolTip.text(for:button) ?? button.toolTip) == "Delete from Web","A recorded entry can be deleted from the web")
                    browser.select(ids:[legacy.id])
                    try expect(!browser.canPerform(.deleteRemote) && !button.isEnabled,"An entry with no destination record is not offered Delete from Web")
                    try expect(AppToolTip.text(for:button)?.contains("unavailable") == true && AppToolTip.text(for:button)?.contains("recorded where it went") == true,"The tooltip says why: \(AppToolTip.text(for:button) ?? "")")
                    try expect(browser.canPerform(.copyLink) && HistoryBrowser.deleteRemoteHelp(for:[]) == "Delete from Web","Its other link actions stay on, and nothing selected has no special text")
                    browser.select(ids:[recorded.id,legacy.id])
                    try expect(!browser.canPerform(.deleteRemote) && !button.isEnabled,"A multiple selection is not deletable")
                    try expect(AppToolTip.text(for:button)?.contains("one post at a time") == true,"A multiple selection says why: \(AppToolTip.text(for:button) ?? "")")
                    let local = item("Local",action:"Archived",link:false)
                    browser.update(items:[recorded,legacy,local]); browser.select(ids:[local.id])
                    try expect(!button.isEnabled && AppToolTip.text(for:button)?.contains("never uploaded") == true,"A drawing that never went to the web says so: \(AppToolTip.text(for:button) ?? "")")
                    var asked: [[UUID]] = []
                    browser.onDeleteRemote = { asked.append($0) }
                    browser.perform(.deleteRemote); browser.select(ids:[legacy.id]); browser.perform(.deleteRemote); browser.select(ids:[recorded.id]); browser.perform(.deleteRemote)
                    try expect(asked == [[local.id],[legacy.id],[recorded.id]],"Invoked anyway, the disabled action still reaches the app, which answers with a sheet: \(asked)")
                    browser.select(ids:[])
                    browser.perform(.deleteRemote)
                    try expect(asked.count == 3,"Nothing selected asks nothing")
                }
            }),
            ("The details column is a summary with nothing selected, and a link stays on one line with its full text in the tooltip", {
                try browser { browser,_ in
                    let lines = HistoryBrowser.summaryLines(for:[item("A",action:"Saved"),item("B",action:"Shared"),item("C",action:"Shared")])
                    try expect(lines == ["3 snaps in this view","Shared: 2","Saved: 1"],"Summary lines are \(lines)")
                    try expect(HistoryBrowser.summaryLines(for:[]).isEmpty && HistoryBrowser.summaryLines(for:[item("A")]).first == "1 snap in this view","Summary pluralisation")
                    var shared = item("Uploaded",action:"Shared",link:true)
                    let link = "https://cdn.example.invalid/pics/a-very-long-folder-name/another-long-segment/2026-10-10-capture-final-v2.png"
                    shared.destination = link
                    browser.update(items:[shared,item("Other",-1)]); laidOut(browser,width:1000,height:720)
                    let texts = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }
                    try expect(texts.contains { !$0.isHidden && $0.stringValue == "2 snaps in this view" },"No summary with nothing selected")
                    let summaryTree = AXTree.walk(browser.window!)
                    for summary in texts.filter({ !$0.isHidden && ($0.stringValue == "2 snaps in this view" || $0.stringValue == "Shared: 1\nSaved: 1") }) {
                        try expect(summaryTree.nodes.contains { $0.object === summary && $0.role == .staticText }, "History summary text is reached as static text, not AXUnknown")
                    }
                    try expect(texts.contains { !$0.isHidden && $0.stringValue == "Select a snap to see its details." },"The hint went missing")
                    browser.select(ids:[shared.id])
                    let value = try texts.first { $0.stringValue == link }.unwrap("destination value")
                    try expect(value.maximumNumberOfLines == 1 && value.lineBreakMode == .byTruncatingMiddle,"The destination wraps instead of cutting its middle")
                    try expect(AppToolTip.text(for:value) == link,"The full link is not in the tooltip")
                    try expect(!texts.contains { !$0.isHidden && $0.stringValue == "2 snaps in this view" },"The summary stays over a selection")
                }
            }),
            ("Every control in History is body size or larger and the filter row fits at the minimum", {
                try browser { browser,_ in
                    browser.update(items:[item("A")]); laidOut(browser,width:880,height:600)
                    let content = browser.window!.contentView!
                    for control in descendants(content).compactMap({ $0 as? NSControl }) {
                        try expect(drawnSizes(control).allSatisfy { $0 >= 18 },"\(type(of:control)) is below 18 pt")
                    }
                    let segmented = try descendants(content).compactMap { $0 as? GlassChoiceGroup }.first.unwrap("category control")
                    try expect(segmented.buttons.allSatisfy { ($0.titleLabel.font?.pointSize ?? 0) >= 20 },"Tabs are body size")
                    try expect(browser.filterRow.frame.maxX <= content.bounds.width + 0.5 && browser.filterRow.frame.minX >= 0,"The filter row overflows the window at 880 wide: \(browser.filterRow.frame)")
                    try expect(browser.actionRow.frame.maxX <= content.bounds.width + 0.5,"The action row overflows the window at 880 wide")
                }
            })
            ,
            ("With nothing to show the grid and its message use the whole width, and the details column returns with the first snap (F-J3-002)", {
                try browser { browser,_ in
                    laidOut(browser,width:1000,height:640)
                    let scroll = browser.gridScrollView!, body = scroll.superview!
                    try expect(browser.detailsCollapsed && browser.detailsPanel.isHidden,"The empty list hides the details panel")
                    try expect(abs(scroll.frame.maxX-body.bounds.maxX) < 0.5 && abs(scroll.frame.width-body.bounds.width) < 0.5,"The empty list is the full width: \(scroll.frame) in \(body.bounds)")
                    let message = browser.emptyState.frame
                    try expect(abs(message.midX-body.bounds.midX) < 1,"The message is centred in the window, not in a shortened well: \(message)")
                    browser.update(items:[item("A"),item("B",action:"Uploaded")]); laidOut(browser,width:1000,height:640)
                    try expect(!browser.detailsCollapsed && !browser.detailsPanel.isHidden && scroll.frame.maxX < body.bounds.maxX-200,"With snaps the details column is back beside the grid: \(scroll.frame)")
                    browser.setFilters(category:.all,query:"nothing matches this"); laidOut(browser,width:1000,height:640)
                    try expect(browser.detailsCollapsed && abs(scroll.frame.width-body.bounds.width) < 0.5,"No-match collapses it too (it keeps its Clear filters button)")
                    try expect(!browser.clearFiltersButton.isHidden && !browser.emptyState.isHidden,"The no-match message still offers Clear filters")
                    browser.clearFilters(); laidOut(browser,width:1000,height:640)
                    try expect(!browser.detailsCollapsed,"Clear filters brings the column back")
                    laidOut(browser,width:740,height:640); browser.setFilters(category:.all,query:"zzz")
                    try expect(browser.detailsPlacement == .below && browser.detailsCollapsed && abs(scroll.frame.height-body.bounds.height) < 0.5,"Below placement collapses to the full body as well")
                    browser.clearFilters(); laidOut(browser,width:740,height:640)
                    try expect(scroll.frame.height < body.bounds.height-100,"The strip returns under the grid when narrow")
                    // Batch 3b: selecting a snap still fills the column and clearing the selection returns the summary.
                    browser.select(ids:[browser.visibleItems[0].id])
                    try expect(!browser.detailsPanel.isHidden && browser.visibleItems.count == 2,"Selection keeps working with the column visible")
                }
            }),
            ("A snap's size reads in whole pixels without separators; a stored fraction never shows (F-J3-006)", {
                try expect(HistoryBrowser.sizeText(for:CGSize(width:1444.285714,height:1011)) == "1444 × 1011","Fractional width rounds: \(HistoryBrowser.sizeText(for:CGSize(width:1444.285714,height:1011)))")
                try expect(HistoryBrowser.sizeText(for:CGSize(width:1516.5,height:1010.49)) == "1517 × 1010","Ties round up, below-half rounds down")
                try expect(HistoryBrowser.sizeText(for:CGSize(width:2400,height:1600)) == "2400 × 1600","Whole sizes are unchanged")
                try expect(HistoryBrowser.sizeText(for:CGSize(width:0.2,height:CGFloat.nan)) == "Unknown size" && HistoryBrowser.sizeText(for:CGSize(width:CGFloat.infinity,height:3)) == "Unknown size","A non-finite side is unknown")
                try browser { browser,_ in
                    let fractional = HistoryBrowser.Item(id:UUID(),name:"Seeded",date:day(0),size:CGSize(width:1444.285714,height:1011),action:"Saved",text:"",destination:nil,link:nil,previewURL:nil,missing:false)
                    browser.update(items:[fractional]); browser.select(ids:[fractional.id]); laidOut(browser,width:1000,height:640)
                    let size = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Size" }
                    try expect(size?.stringValue == "1444 × 1011","The details Size field shows whole pixels: \(size?.stringValue ?? "none")")
                }
            })
            ,
            ("Details shows a two-digit-day date in full and a shared entry's published size, not the later resized one (F-J4-002, F-J4-004)", {
                try browser { browser,_ in
                    let late = calendar.date(from:DateComponents(year:2026,month:10,day:10,hour:18,minute:49))!
                    var shared = HistoryBrowser.Item(id:UUID(),name:"Untitled",date:late,size:CGSize(width:1011,height:758),action:"Shared",text:"",destination:"https://cdn.example.invalid/a.png",
                                                     link:URL(string:"https://cdn.example.invalid/a.png"),previewURL:nil,missing:false)
                    shared.publishedSize = CGSize(width:800,height:600)
                    browser.update(items:[shared]); browser.select(ids:[shared.id]); laidOut(browser,width:1000,height:640)
                    let fields = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }
                    let size = fields.first { $0.accessibilityLabel() == "Size" }, date = fields.first { $0.accessibilityLabel() == "Date" }
                    try expect(size?.stringValue == "800 × 600 (published)","A shared entry reports what was published, and says so: \(size?.stringValue ?? "none")")
                    // F-J7-003: the web copy goes (link gone, nothing else about the entry moves) and the same selection reads the same Size.
                    var taken = shared; taken.link = nil; taken.canDeleteFromWeb = false
                    browser.update(items:[taken]); browser.select(ids:[taken.id]); laidOut(browser,width:1000,height:640)
                    let afterDelete = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Size" }
                    try expect(afterDelete?.stringValue == "800 × 600 (published)","After Delete from Web the Size is unchanged: \(afterDelete?.stringValue ?? "none")")
                    // R3-009: …and Details says the post is gone instead of leaving a dead address that reads as live.
                    let destinationAfter = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Destination" }
                    try expect(destinationAfter?.stringValue == "https://cdn.example.invalid/a.png (deleted)","After Delete from Web the Destination says (deleted): \(destinationAfter?.stringValue ?? "none")")
                    browser.update(items:[shared]); browser.select(ids:[shared.id])
                    let destinationLive = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Destination" }
                    try expect(destinationLive?.stringValue == "https://cdn.example.invalid/a.png","A live post's Destination has no (deleted): \(destinationLive?.stringValue ?? "none")")
                    guard let date else { throw Failure("Missing Date field") }
                    try expect(date.stringValue.hasSuffix("PM"),"The time of day with its AM/PM is in the text: \(date.stringValue)")
                    date.superview?.layoutSubtreeIfNeeded()
                    let needed = date.attributedStringValue.boundingRect(with:NSSize(width:10_000,height:100),options:[.usesLineFragmentOrigin]).width
                    try expect(date.frame.width + 0.5 >= needed || date.frame.height > (date.font?.pointSize ?? 20) * 1.6,"The date fits its field or wraps onto a second line (\(date.frame.width) for \(needed))")
                    var plain = shared; plain.id = UUID(); plain.publishedSize = nil
                    browser.update(items:[plain]); browser.select(ids:[plain.id])
                    let again = descendants(browser.window!.contentView!).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Size" }
                    try expect(again?.stringValue == "1011 × 758","An entry that was never published reports its own size")
                }
            })
            ,
            ("The seven actions are shared glass-chrome buttons on three grouped glass plates in one container, the removal group apart and labelled", {
                try browser { browser,_ in
                    browser.update(items:[item("A")]); laidOut(browser,width:1000,height:720)
                    let content = browser.window!.contentView!, buttons = actionButtons(browser)
                    try expect(buttons.count == 7 && buttons.allSatisfy { $0 is CommandButton },"All seven actions are CommandButtons: \(buttons.map { String(describing: type(of:$0)) })")
                    try expect(!descendants(content).compactMap { $0 as? NSButton }.contains { $0.bezelStyle == .rounded && $0.isBordered && !($0 is NSPopUpButton) && type(of:$0) == NSButton.self && !$0.title.isEmpty },"A plain rounded text button is left in History")
                    let container = try (browser.actionContainer).unwrap("glass container")
                    try expect(container.identifier?.rawValue == "HistoryActionBar" && browser.actionPlates.count == 3 && browser.actionPlates.allSatisfy { descendants(container).contains($0) },"The three plates share one glass container")
                    for (plate,group) in zip(browser.actionPlates,HistoryBrowser.actionGroups) {
                        try expect(plate.identifier?.rawValue == group.identifier && plate.accessibilityLabel() == group.label,"Plate \(group.identifier) is named \(group.label)")
                        let inside = descendants(plate).compactMap { $0 as? HistoryActionButton }
                        try expect(inside.count == group.actions.count && zip(inside,group.actions).allSatisfy { $0.accessibilityLabel() == $1.title },"\(group.identifier) holds \(group.actions.map(\.title))")
                    }
                    let frames = browser.actionPlates.map { $0.convert($0.bounds,to:content) }
                    try expect(frames[0].maxX + GlassChrome.Metrics.groupGap - 0.5 <= frames[1].minX,"The open and link groups keep the group gap: \(frames)")
                    try expect(frames[2].minX - frames[1].maxX >= 2 * GlassChrome.Metrics.groupGap - 0.5 && abs(frames[2].maxX - (content.bounds.maxX - DesignTokens.Space.s4)) < 1,"The removal group is set apart at the trailing edge: \(frames)")
                    try expect(frames.allSatisfy { abs($0.height - GlassChrome.Metrics.headerHeight) < 0.5 },"Every plate is one bar row high: \(frames)")
                    let remove = Set(descendants(browser.actionPlates[2]).compactMap { ($0 as? HistoryActionButton)?.accessibilityLabel() })
                    try expect(remove == ["Hide from History","Move to Trash","Delete from Web"],"Only the three that take something away share the last plate: \(remove)")
                }
            }),
            ("Each action plate is an accessibility group with its name, so VoiceOver speaks \"Open and copy, group\", and its buttons stay reachable inside it (FR-4)", {
                try browser { browser,_ in
                    browser.update(items:[item("A")]); laidOut(browser,width:1000,height:720)
                    func reaches(_ element: Any?,_ target: AnyObject,depth: Int = 0) -> Bool {
                        // A button reaches a client through its cell, which stands in for it in the tree.
                        if let cell = element as? NSCell,cell.controlView === target { return true }
                        guard depth < 10,let element = element as? NSAccessibilityProtocol else { return false }
                        if (element as AnyObject) === target { return true }
                        return (element.accessibilityChildren() ?? []).contains { reaches($0,target,depth:depth+1) }
                    }
                    for (plate,group) in zip(browser.actionPlates,HistoryBrowser.actionGroups) {
                        try expect(plate.isAccessibilityElement(),"\(group.label) is an accessibility element, not skipped over")
                        try expect(plate.accessibilityRole() == .group && plate.accessibilityLabel() == group.label,"…with the group role and the name \(group.label)")
                        for button in descendants(plate).compactMap({ $0 as? HistoryActionButton }) {
                            try expect(reaches(plate,button),"…and a client walking its children still reaches \(button.accessibilityLabel() ?? "a button")")
                            try expect(reaches(browser.window!,button),"…and the window reaches it through the plate")
                        }
                    }
                }
            }),
            ("Glass is only the chrome: no glass inside glass, none over the grid, tiles or details", {
                try browser { browser,_ in
                    browser.update(items:[item("A"),item("B",-1)]); laidOut(browser,width:1000,height:720)
                    let content = browser.window!.contentView!
                    let glass = descendants(content).filter { $0 is NSGlassEffectView }
                    // Three action plates, plus one plate each for the category choice, the date filter and Drag as: every choice is a plate, nothing else is glass.
                    let filterPlates = [browser.categoryChoice.plate,glassPlate(of:browser.dateFilterPopUp),glassPlate(of:browser.dragFormatPopUp)].compactMap { $0 as NSView? }
                    try expect(glass.count == 6 && glass.allSatisfy { $0 is GlassSurfaceView } && filterPlates.count == 3 && filterPlates.allSatisfy { plate in glass.contains { $0 === plate } } && browser.actionPlates.allSatisfy { plate in glass.contains { $0 === plate } },
                               "History draws exactly its three action plates and its three choice plates as glass (found \(glass.count))")
                    for plate in glass {
                        let nested = descendants(plate).filter { $0 !== plate && ($0 is NSGlassEffectView || $0 is NSVisualEffectView) }
                        try expect(nested.isEmpty,"A glass plate holds another material: \(nested.map { String(describing: type(of:$0)) })")
                    }
                    for content in [try grid(browser) as NSView,browser.detailsPanel,browser.emptyState] {
                        var ancestor: NSView? = content
                        while let view = ancestor { try expect(!(view is NSGlassEffectView),"\(type(of:content)) sits on a glass material"); ancestor = view.superview }
                        try expect(!descendants(content).contains { $0 is NSGlassEffectView || $0 is NSVisualEffectView },"\(type(of:content)) draws a glass material")
                    }
                    let cell = browser.collectionView(try grid(browser),itemForRepresentedObjectAt:IndexPath(item:0,section:0))
                    try expect(!descendants(cell.view).contains { $0 is NSGlassEffectView || $0 is NSVisualEffectView },"A tile is glass")
                }
            }),
            ("With nothing selected the selection-dependent actions are disabled, still legible, and do not move when a snap is selected", {
                try browser { browser,_ in
                    let shared = item("Shared",action:"Shared",link:true)
                    browser.onOpen = { _ in }; browser.onCopy = { _ in }; browser.onCopyLink = { _ in }; browser.onOpenLink = { _ in }
                    browser.onRemove = { _ in }; browser.onDeleteFiles = { _ in }; browser.onDeleteRemote = { _ in }
                    browser.update(items:[shared]); laidOut(browser,width:1000,height:720)
                    let content = browser.window!.contentView!, buttons = actionButtons(browser)
                    let before = buttons.map { $0.convert($0.bounds,to:content) }
                    for (button,action) in zip(buttons,HistoryBrowser.Action.allCases) {
                        try expect(!button.isEnabled && !button.title.isEmpty,"\(action) is disabled but still in the row with its label")
                        let style = button.plate.stateStyle
                        try expect(style.contentAlpha >= StateStyles.disabledAlpha(highContrast:false) && abs(button.alphaValue - style.contentAlpha) < 0.001,"\(action) disabled stays legible (alpha \(button.alphaValue))")
                        try expect(!button.isHidden && button.frame.height >= DesignTokens.Size.control - 0.5,"\(action) keeps its full-size slot")
                    }
                    browser.select(ids:[shared.id]); laidOut(browser,width:1000,height:720)
                    try expect(buttons.allSatisfy(\.isEnabled),"Selecting a shared snap enables all seven")
                    let after = buttons.map { $0.convert($0.bounds,to:content) }
                    try expect(before == after,"The row jumped when a snap was selected: \(before) -> \(after)")
                    try expect(buttons.allSatisfy { $0.alphaValue == 1 },"Enabled actions are drawn at full strength")
                    browser.select(ids:[]); laidOut(browser,width:1000,height:720)
                    try expect(buttons.allSatisfy { !$0.isEnabled } && buttons.map({ $0.convert($0.bounds,to:content) }) == before,"Clearing the selection disables them again, in place")
                }
            }),
            ("Tab reaches every enabled action in reading order, skips the disabled ones, and no action is the default button", {
                let saved = KeyboardNavigation.fullKeyboardAccess
                KeyboardNavigation.fullKeyboardAccess = { true }
                defer { KeyboardNavigation.fullKeyboardAccess = saved }
                try browser { browser,_ in
                    laidOut(browser,width:1000,height:720)
                    @MainActor func loop() throws -> [NSView] {
                        browser.window!.recalculateKeyViewLoop() // what AppKit does itself when the window first orders in
                        let start = try grid(browser) as NSView
                        var seen: [NSView] = [], view = start.nextValidKeyView
                        while let current = view, current !== start, seen.count < 60 { seen.append(current); view = current.nextValidKeyView }
                        return seen
                    }
                    try expect(!loop().contains { $0 is HistoryActionButton },"Disabled actions are not tab stops")
                    selectingEverythingEnabled(browser); laidOut(browser,width:1000,height:720)
                    let reached = try loop().compactMap { $0 as? HistoryActionButton }
                    try expect(reached.map { $0.accessibilityLabel() ?? "" } == HistoryBrowser.Action.allCases.map(\.title),"Tab reaches the seven actions in order: \(reached.map { $0.accessibilityLabel() ?? "" })")
                    for button in actionButtons(browser) {
                        try expect(button.keyEquivalent.isEmpty && browser.window!.defaultButtonCell !== button.cell,"\(button.accessibilityLabel() ?? "") must not be the default button")
                    }
                    try expect(browser.window!.defaultButtonCell == nil,"History has no default button, so Return cannot trigger a removal")
                    var opened = 0, removed = 0
                    browser.onOpen = { _ in opened += 1 }; browser.onRemove = { _ in removed += 1 }
                    let gridView = try grid(browser)
                    gridView.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!)
                    try expect(opened == 1 && removed == 0,"Return in the grid still opens the selection and removes nothing (opened \(opened), removed \(removed))")
                }
            }),
            ("Every action shows rest, hover, pressed, focus and disabled on its own plate fill", {
                try browser { browser,_ in
                    selectingEverythingEnabled(browser); laidOut(browser,width:1000,height:720)
                    let open = try actionButtons(browser).first.unwrap("Open")
                    try expect(open.plate.style.fill == nil,"Open on its glass plate has no fill at rest")
                    open.setHovered(true)
                    try expect(open.plate.style.fill != nil && open.isHovered,"Hover draws a fill on the button, not another glass surface")
                    open.setHovered(false)
                    try expect(browser.window!.makeFirstResponder(open) && open.plate.stateStyle.focusRing && !open.plate.ringLayer.isHidden,"Keyboard focus draws the focus ring on the focused action")
                    _ = browser.window!.makeFirstResponder(nil)
                    try expect(!open.plate.stateStyle.focusRing,"The ring goes when focus moves on")
                    open.isEnabled = false
                    try expect(open.plate.style.fill == nil && open.plate.stateStyle.contentAlpha < 1,"A disabled action loses its fills and dims")
                }
            }),
            ("Clear filters is the single accent button of the no-match state and reads as a button", {
                try browser { browser,_ in
                    browser.update(items:[item("A")]); browser.setFilters(category:.all,query:"zzz"); laidOut(browser,width:1000,height:720)
                    let clear = browser.clearFiltersButton
                    try expect(!clear.isHidden && clear.isPrimary && clear.plate.style.fill != nil,"Clear filters takes the primary fill")
                    try expect(clear.frame.height >= DesignTokens.Size.control - 0.5 && clear.frame.width > 120 && drawnSizes(clear).allSatisfy { $0 >= 20 },"It is a full-size target with a 20 pt label (\(clear.frame))")
                    try expect(clear.accessibilityLabel() == "Clear filters" && clear.image != nil,"It has a glyph and a name")
                    var ancestor: NSView? = clear
                    while let view = ancestor { try expect(!(view is NSGlassEffectView),"Clear filters sits on glass"); ancestor = view.superview }
                }
            }),
            ("History text is body size or larger and keeps its contrast in light and dark, in every state", {
                try browser { browser,_ in
                    @MainActor func check(_ state: String) throws {
                        laidOut(browser,width:880,height:600)
                        let content = browser.window!.contentView!
                        for control in descendants(content).compactMap({ $0 as? NSControl }) {
                            try expect(drawnSizes(control).allSatisfy { $0 >= 18 },"\(state): \(type(of:control)) draws below 18 pt")
                        }
                    }
                    try check("empty")
                    browser.update(items:[item("A"),item("B",-1)]); try check("populated")
                    browser.select(ids:[browser.visibleItems[0].id]); try check("selected")
                    let cell = browser.collectionView(try grid(browser),itemForRepresentedObjectAt:IndexPath(item:0,section:0))
                    let header = browser.collectionView(try grid(browser),viewForSupplementaryElementOfKind:NSCollectionView.elementKindSectionHeader,at:IndexPath(item:0,section:0))
                    for field in (descendants(cell.view)+descendants(header)).compactMap({ $0 as? NSTextField }) {
                        try expect(drawnSizes(field).allSatisfy { $0 >= 18 },"tile or day header text '\(field.stringValue)' draws below 18 pt")
                    }
                    browser.setFilters(category:.all,query:"zzz"); try check("no match")
                    let content = browser.window!.contentView!
                    let texts = descendants(content).compactMap { $0 as? NSTextField }
                    let roles: [(String,NSTextField?,NSColor)] = [
                        ("empty hint",browser.emptyHint,DesignTokens.Palette.Text.secondary),
                        ("empty title",browser.emptyTitle,DesignTokens.Palette.Text.primary),
                        ("detail label",texts.first { $0.stringValue == "Name:" },DesignTokens.Palette.Text.secondary),
                        ("detail value",texts.first { $0.accessibilityLabel() == "Name" },DesignTokens.Palette.Text.primary),
                        ("day header",header.subviews.compactMap { $0 as? NSTextField }.first,DesignTokens.Palette.Text.primary),
                        ("status",texts.first { $0.stringValue == browser.statusLine },DesignTokens.Palette.Text.secondary)]
                    for (name,field,role) in roles {
                        let field = try field.unwrap(name)
                        try expect(field.textColor == role,"\(name) uses its semantic text role")
                        for appearance in [NSAppearance(named:.aqua)!,NSAppearance(named:.darkAqua)!] {
                            for surface in [DesignTokens.Palette.Surface.window,DesignTokens.Palette.Surface.content] {
                                let ratio = contrast(role,over:surface,appearance)
                                try expect(ratio >= 4.5,"\(name) contrast \(ratio) under \(appearance.name.rawValue)")
                            }
                        }
                    }
                }
            }),
            ("Category is a glass choice group: same titles, label and filter behaviour, radio roles, one tab stop, arrows move it", {
                try browser { browser,_ in
                    let group = browser.categoryChoice
                    try expect(group.accessibilityLabel() == "History category" && group.accessibilityRole() == .radioGroup && group.buttons.map(\.title) == HistoryBrowser.Category.allCases.map(\.title),
                               "Category group is named History category and lists \(group.buttons.map(\.title))")
                    try expect(glassPlate(of:group.buttons[0]) === group.plate && descendants(browser.window!.contentView!).filter { $0 is NSSegmentedControl }.isEmpty,"…on one plate, with no native segmented control left")
                    let all = ["Saved","Exported","Shared"].map { item("Tile "+$0,action:$0) }
                    browser.update(items:all)
                    for category in HistoryBrowser.Category.allCases.dropFirst() {
                        group.choose(category.rawValue)
                        try expect(browser.category == category && group.selectedIndex == category.rawValue && browser.visibleItems.map(\.action) == [category.title],"Choosing \(category.title) filters to \(browser.visibleItems.map(\.action))")
                        try expect(group.buttons.map { ($0.accessibilityValue() as? NSNumber)?.intValue ?? -1 } == (0..<4).map { $0 == category.rawValue ? 1 : 0 } && group.buttons.allSatisfy { $0.accessibilityRole() == .radioButton },"…and the radio values read 1 on the chosen button, 0 elsewhere")
                    }
                    group.choose(0)
                    try expect(browser.category == .all && browser.visibleItems.count == 3,"All shows everything again")
                    browser.setFilters(category:.exported)
                    try expect(group.selectedIndex == 2 && group.buttons[2].isChosen,"setFilters moves the group's choice without sending the action")
                    try expect(group.buttons.filter { $0.participatesInKeyLoop }.count == 1 && group.buttons[2].participatesInKeyLoop,"The group is one tab stop, on the chosen button")
                    let before = browser.category
                    group.choose(2)
                    try expect(browser.category == before,"Choosing the chosen button changes nothing")
                    try expect(group.buttons.allSatisfy { ($0.titleLabel.font?.pointSize ?? 0) >= 20 },"Category titles are 20 pt")
                    for width in [880.0,1000.0] as [CGFloat] {
                        laidOut(browser,width:width,height:720)
                        try expect(group.buttons.allSatisfy { ceil($0.titleLabel.intrinsicContentSize.width) <= $0.titleLabel.frame.width + 0.5 && $0.titleLabel.frame.maxX <= $0.bounds.maxX + 0.5 },"Category titles are not truncated at \(Int(width)) wide: \(group.buttons.map { "\($0.title) \(ceil($0.titleLabel.intrinsicContentSize.width))/\($0.titleLabel.frame.width)" })")
                        for popup in [browser.dateFilterPopUp,browser.dragFormatPopUp] {
                            let room = popup.bounds.width - 2 * GlassChoiceButton.padding - GlassChoiceButton.gap - GlassChoiceButton.glyphSide
                            let longest = popup.itemTitles.map { ceil(($0 as NSString).size(withAttributes:[.font:DesignTokens.Typography.font(.body)]).width) }.max() ?? 0
                            try expect(longest <= room + 0.5,"\(popup.accessibilityLabel() ?? "pop-up") shows its longest choice whole at \(Int(width)) wide (\(longest) in \(room))")
                        }
                    }
                }
            }),
            ("Date filter is a glass pop-up; choosing a row in its panel filters exactly as before", {
                try browser { browser,_ in
                    let popup = browser.dateFilterPopUp, choices = popup.choicePanel
                    choices.host.presenter = { _,_ in }
                    try expect(popup.accessibilityLabel() == "History date filter" && popup.accessibilityRole() == .popUpButton && popup.titleOfSelectedItem == "All dates" && popup.faceTitle == "All dates",
                               "The pop-up is named History date filter, a pop-up button showing All dates")
                    try expect(popup.itemTitles == HistoryBrowser.DateFilter.allCases.map(\.title) && glassPlate(of:popup) != nil && popup.superview is ChromeFillCell,"…on a glass plate in a fill cell, with the same four choices")
                    let all = [item("Now",0),item("Old",-5)]
                    browser.update(items:all)
                    popup.performClick(nil)
                    try expect(choices.host.isShown && choices.rows.map(\.title) == HistoryBrowser.DateFilter.allCases.map(\.title),"The panel lists \(choices.rows.map(\.title))")
                    try expect(choices.rows.allSatisfy { $0.accessibilityRole() == .radioButton && $0.isEnabled } && choices.rows.map { ($0.accessibilityValue() as? NSNumber)?.intValue ?? -1 } == [1,0,0,0],"Rows are enabled radio buttons, 1 on All dates and 0 elsewhere")
                    let last48 = try choices.rows.first { $0.title == "Last 48 hours" }.unwrap("row")
                    choices.activate(last48)
                    try expect(!choices.host.isShown && browser.dateFilter == .last48 && popup.faceTitle == "Last 48 hours" && popup.indexOfSelectedItem == 3,"Choosing Last 48 hours sets the filter (\(browser.dateFilter)) and the face")
                    try expect(browser.visibleItems.map(\.name) == ["Now"],"…and filters the grid: \(browser.visibleItems.map(\.name))")
                    browser.setFilters(category:.all,date:.all)
                    try expect(popup.faceTitle == "All dates" && browser.visibleItems.count == 2,"setFilters moves the face back")
                    try expect(popup.frame.width >= ceil(("Last 48 hours" as NSString).size(withAttributes:[.font:DesignTokens.Typography.font(.body)]).width) + GlassChoiceButton.glyphSide,"The face is as wide as its longest choice")
                }
            }),
            ("Drag as is a glass pop-up; choosing a row persists the format exactly as before", {
                try browser { browser,defaults in
                    let popup = browser.dragFormatPopUp, choices = popup.choicePanel
                    choices.host.presenter = { _,_ in }
                    try expect(popup.accessibilityLabel() == "History drag export format" && popup.faceTitle == "PNG" && browser.dragFormat == "png","The pop-up is named and shows PNG")
                    popup.performClick(nil)
                    try expect(choices.rows.map { ($0.accessibilityValue() as? NSNumber)?.intValue ?? -1 } == [1,0,0,0,0,0] && choices.rows.allSatisfy { $0.accessibilityRole() == .radioButton },"Six radio rows, PNG chosen")
                    choices.activate(try choices.rows.first { $0.title == "PDF" }.unwrap("PDF row"))
                    try expect(browser.dragFormat == "pdf" && defaults.string(forKey:HistoryBrowser.dragFormatDefaultsKey) == "pdf" && popup.faceTitle == "PDF","Choosing PDF persists pdf and updates the face")
                    browser.setDragFormat("opensnap")
                    try expect(popup.faceTitle == ".opensnap document" && popup.indexOfSelectedItem == 5,"setDragFormat moves the face to the document format")
                    browser.setDragFormat("nonsense")
                    try expect(browser.dragFormat == "opensnap","An unknown format changes nothing")
                }
            }),
            ("No route to a glass pop-up reaches the native dropdown: mouse, keys, performClick, AXPress, AXShowMenu, context menu, right and Control click", {
                try browser { browser,_ in
                    browser.update(items:[item("A")])
                    let window = try browser.window.unwrap("window")
                    for (name,popup) in [("Date filter",browser.dateFilterPopUp),("Drag as",browser.dragFormatPopUp)] {
                        let choices = popup.choicePanel
                        choices.host.presenter = { _,_ in }
                        var tracking = 0
                        let token = NotificationCenter.default.addObserver(forName:NSMenu.didBeginTrackingNotification,object:nil,queue:nil) { _ in tracking += 1 }
                        defer { NotificationCenter.default.removeObserver(token); choices.host.close() }
                        func event(_ type: NSEvent.EventType,_ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
                            try NSEvent.mouseEvent(with:type,location:popup.convert(NSPoint(x:5,y:5),to:nil),modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1).unwrap("event")
                        }
                        func key(_ code: UInt16,_ text: String) throws -> NSEvent {
                            try NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code).unwrap("key")
                        }
                        @MainActor func opens(_ route: String,_ act: @MainActor () throws -> Void) throws {
                            try act()
                            try expect(choices.host.isShown,"\(name): \(route) opens the glass panel")
                            choices.host.close()
                        }
                        try expect(popup.menu(for:try event(.rightMouseDown)) == nil,"\(name): there is no contextual menu to pop up")
                        try opens("mouse down") { popup.mouseDown(with:try event(.leftMouseDown)) }
                        try opens("right mouse down") { popup.rightMouseDown(with:try event(.rightMouseDown)) }
                        try opens("Control-click") { popup.mouseDown(with:try event(.leftMouseDown,.control)) }
                        try opens("other mouse down") { popup.otherMouseDown(with:try event(.otherMouseDown)) }
                        try opens("performClick") { popup.performClick(nil) }
                        for (code,text,label) in [(UInt16(49)," ","Space"),(125,"","Down"),(126,"","Up"),(36,"\r","Return"),(76,"\u{3}","Enter")] {
                            try opens(label) { popup.keyDown(with:try key(code,text)) }
                        }
                        try opens("AXPress") { try expect(popup.accessibilityPerformPress(),"") }
                        try opens("AXShowMenu") { try expect(popup.accessibilityPerformShowMenu(),"") }
                        try opens("the context-menu command") { popup.showContextMenuForSelection(nil) }
                        try expect(popup.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformShowMenu)) && popup.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformPress)),"\(name): AXPress and AXShowMenu are both offered, and both open the glass panel")
                        // Keyboard opens focus the chosen row; a type-ahead letter never starts AppKit's own pop-up handling.
                        popup.keyDown(with:try key(125,""))
                        try expect(choices.focusedRow?.isChosen == true,"\(name): a keyboard open focuses the chosen row")
                        choices.host.close()
                        popup.keyDown(with:try key(0,"a"))
                        try expect(!choices.host.isShown,"\(name): type-ahead does not open a native menu")
                        try expect(tracking == 0,"\(name): no native menu tracking began on any route (\(tracking))")
                    }
                    let grid = try descendants(browser.window!.contentView!).first { $0 is NSCollectionView }.unwrap("grid")
                    try expect(grid.menu != nil && grid.menu?.items.count == HistoryBrowser.Action.allCases.count,"The thumbnail grid keeps its native context menu")
                }
            })
        ]
        var failures = 0
        for (name,test) in tests {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error.localizedDescription)") }
        }
        print("HistoryBrowserTests: \(tests.count-failures)/\(tests.count) passed")
        if failures != 0 { exit(1) }
    }
}
extension Optional {
    func unwrap(_ what: String) throws -> Wrapped {
        guard let self else { throw HistoryBrowserTests.Failure("Missing \(what)") }
        return self
    }
}
#endif
