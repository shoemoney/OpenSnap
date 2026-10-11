import AppKit
import Carbon

// Physical key positions and Carbon modifier masks come from the local macOS
// HIToolbox/Events.h. No event tap, keyboard monitor or Accessibility API is used.
enum GlobalHotkeyAction: String, Codable, CaseIterable, Sendable {
    case screen, window, fullscreen, frame, upload, show
    var title: String {
        switch self {
        case .screen: return "Screen region"
        case .window: return "Window"
        case .fullscreen: return "Full screen"
        case .frame: return "Frame"
        case .upload: return "Upload"
        case .show: return "Show OpenSnap"
        }
    }
    var carbonID: UInt32 { UInt32(Self.allCases.firstIndex(of: self)! + 1) }
}

struct GlobalHotkeyModifiers: OptionSet, Hashable, Codable, Sendable {
    let rawValue: UInt32
    init(rawValue: UInt32) { self.rawValue = rawValue }
    static let command = Self(rawValue: 1)
    static let option = Self(rawValue: 2)
    static let control = Self(rawValue: 4)
    static let shift = Self(rawValue: 8)
    static let allowed: Self = [.command, .option, .control, .shift]
    var carbonFlags: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
    init(carbonFlags: UInt32) {
        var value: Self = []
        if carbonFlags & UInt32(cmdKey) != 0 { value.insert(.command) }
        if carbonFlags & UInt32(optionKey) != 0 { value.insert(.option) }
        if carbonFlags & UInt32(controlKey) != 0 { value.insert(.control) }
        if carbonFlags & UInt32(shiftKey) != 0 { value.insert(.shift) }
        self = value
    }
    init(appKitFlags: NSEvent.ModifierFlags) {
        var value: Self = []
        if appKitFlags.contains(.command) { value.insert(.command) }
        if appKitFlags.contains(.option) { value.insert(.option) }
        if appKitFlags.contains(.control) { value.insert(.control) }
        if appKitFlags.contains(.shift) { value.insert(.shift) }
        self = value
    }
}

struct GlobalHotkeyBinding: Codable, Hashable, Sendable {
    var keyCode: UInt32?
    var modifiers: GlobalHotkeyModifiers
    init(keyCode: UInt32?, modifiers: GlobalHotkeyModifiers = []) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
    static let none = Self(keyCode: nil)
    var displayName: String {
        guard let code = keyCode else { return "None" }
        var names: [String] = []
        if modifiers.contains(.control) { names.append("Control") }
        if modifiers.contains(.option) { names.append("Option") }
        if modifiers.contains(.shift) { names.append("Shift") }
        if modifiers.contains(.command) { names.append("Command") }
        names.append(GlobalHotkeyKeys.name(for: code) ?? "Key \(code)")
        return names.joined(separator: " + ")
    }
}

enum GlobalHotkeyKeys {
    struct Key: Sendable { let code: UInt32; let name: String }
    // US labels describe hardware positions, not the active keyboard layout.
    static let choices: [Key] = {
        let letters: [(Int, String)] = [(0,"A"),(11,"B"),(8,"C"),(2,"D"),(14,"E"),(3,"F"),
            (5,"G"),(4,"H"),(34,"I"),(38,"J"),(40,"K"),(37,"L"),(46,"M"),(45,"N"),
            (31,"O"),(35,"P"),(12,"Q"),(15,"R"),(1,"S"),(17,"T"),(32,"U"),(9,"V"),
            (13,"W"),(7,"X"),(16,"Y"),(6,"Z")]
        let digits: [(Int, String)] = [(29,"0"),(18,"1"),(19,"2"),(20,"3"),(21,"4"),
            (23,"5"),(22,"6"),(26,"7"),(28,"8"),(25,"9")]
        let functions: [Int] = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
        let punctuation: [(Int, String)] = [(27,"Minus"),(24,"Equals"),(33,"Left bracket"),
            (30,"Right bracket"),(42,"Backslash"),(41,"Semicolon"),(39,"Quote"),
            (43,"Comma"),(47,"Period"),(44,"Slash"),(50,"Backtick"),(49,"Space")]
        return (letters + digits).map { Key(code: UInt32($0.0), name: $0.1) }
            + functions.enumerated().map { Key(code: UInt32($0.element), name: "F\($0.offset + 1)") }
            + punctuation.map { Key(code: UInt32($0.0), name: $0.1) }
    }()
    static func name(for code: UInt32) -> String? { choices.first { $0.code == code }?.name }
    static func code(forMenuKey key: String) -> UInt32? {
        if key.count == 1, let value = key.unicodeScalars.first?.value,
           value >= UInt32(NSF1FunctionKey), value <= UInt32(NSF20FunctionKey) {
            return choices.first { $0.name == "F\(value - UInt32(NSF1FunctionKey) + 1)" }?.code
        }
        let punctuation = ["-":"Minus", "=":"Equals", "[":"Left bracket", "]":"Right bracket",
                           "\\":"Backslash", ";":"Semicolon", "'":"Quote", ",":"Comma",
                           ".":"Period", "/":"Slash", "`":"Backtick", " ":"Space"]
        let name = punctuation[key] ?? key.uppercased()
        return choices.first { $0.name == name }?.code
    }
}

private func globalHotkeyFailure(_ message: String, underlying: [Error] = []) -> NSError {
    var info: [String: Any] = [NSLocalizedDescriptionKey: message]
    if let first = underlying.first { info[NSUnderlyingErrorKey] = first }
    if !underlying.isEmpty { info["RelatedErrors"] = underlying.map { $0 as NSError } }
    return NSError(domain: "OpenSnap.GlobalHotkeys", code: 1, userInfo: info)
}

/// A Carbon hotkey call that failed. The words say what to do when the status is one a person can act on (a key another app holds, a key
/// macOS cannot register); the call and the raw status stay in `NSDebugDescriptionErrorKey`, which the Capture note carries as its help.
func carbonHotkeyFailure(_ operation: String, _ status: OSStatus, shortcut: String? = nil) -> NSError {
    let technical = "\(operation) failed (OSStatus \(status))."
    var words = technical
    if let shortcut {
        switch status {
        case OSStatus(eventHotKeyExistsErr): words = "\(shortcut) is already used by another app. Choose a different shortcut."
        case OSStatus(eventHotKeyInvalidErr): words = "macOS cannot register \(shortcut). Choose a different shortcut."
        default: break
        }
    }
    return NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                   userInfo: [NSLocalizedDescriptionKey: words, NSDebugDescriptionErrorKey: technical])
}

extension Error {
    /// The raw call and status behind a hotkey error whose message was put in words, else nil.
    var hotkeyTechnicalDetail: String? {
        let error = self as NSError
        if let detail = error.userInfo[NSDebugDescriptionErrorKey] as? String { return detail }
        return (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.hotkeyTechnicalDetail
    }
}

struct GlobalHotkeySettings: Codable, Equatable, Sendable {
    var version = 1
    var enabled = true
    var screen: GlobalHotkeyBinding = .none
    var window: GlobalHotkeyBinding = .none
    var fullscreen: GlobalHotkeyBinding = .none
    var frame: GlobalHotkeyBinding = .none
    var upload: GlobalHotkeyBinding = .none
    var show: GlobalHotkeyBinding = .none

    init() {}
    // Preferences saved before Upload/Show existed lack those keys. A legacy
    // camera binding is not a coding key, so it is ignored on decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        screen = try c.decode(GlobalHotkeyBinding.self, forKey: .screen)
        window = try c.decode(GlobalHotkeyBinding.self, forKey: .window)
        fullscreen = try c.decode(GlobalHotkeyBinding.self, forKey: .fullscreen)
        frame = try c.decode(GlobalHotkeyBinding.self, forKey: .frame)
        upload = try c.decodeIfPresent(GlobalHotkeyBinding.self, forKey: .upload) ?? .none
        show = try c.decodeIfPresent(GlobalHotkeyBinding.self, forKey: .show) ?? .none
    }

    subscript(_ action: GlobalHotkeyAction) -> GlobalHotkeyBinding {
        get {
            switch action {
            case .screen: return screen
            case .window: return window
            case .fullscreen: return fullscreen
            case .frame: return frame
            case .upload: return upload
            case .show: return show
            }
        }
        set {
            switch action {
            case .screen: screen = newValue
            case .window: window = newValue
            case .fullscreen: fullscreen = newValue
            case .frame: frame = newValue
            case .upload: upload = newValue
            case .show: show = newValue
            }
        }
    }

    // Verified against setupHotKeyPrefs in analysis/decompiled.c:3316-3345
    // and disassembly.txt:4939-5075: code 0x17/0x16/0x1a, flags 0x300.
    // Help text conflicts with the executable about Command versus Control.
    // These are historical suggestions ONLY, never automatically activated.
    // Even the old Frame chord can belong to macOS or another installed app.
    static let originalBindings: [GlobalHotkeyAction: GlobalHotkeyBinding] = [
        .screen: .init(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift]),
        .fullscreen: .init(keyCode: UInt32(kVK_ANSI_6), modifiers: [.command, .shift]),
        .frame: .init(keyCode: UInt32(kVK_ANSI_7), modifiers: [.command, .shift]),
        // kCrosshairsAndWebPostHotkey: code 0x17, flags 0x1300 (Command+Shift+Control).
        // kShowApplicationHotkey has no default.
        .upload: .init(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift, .control])
    ]
    // First launch and Clear All claim no shortcuts. Only explicit saved
    // choices are activated; an invalid saved choice remains an actual error.
    static var defaults: Self { Self() }
    static var disabled: Self { var settings = Self(); settings.enabled = false; return settings }

    static let internalBindings: Set<GlobalHotkeyBinding> = {
        let plain = ["N","O","S","E","P","Q","H","W","M","Z","X","C","V","A","D",",","1","2","3","4"]
        var bindings = Set(plain.compactMap { key -> GlobalHotkeyBinding? in
            guard let code = GlobalHotkeyKeys.code(forMenuKey: key) else { return nil }
            return .init(keyCode: code, modifiers: .command)
        })
        for key in ["S", "Z"] {
            bindings.insert(.init(keyCode: GlobalHotkeyKeys.code(forMenuKey: key), modifiers: [.command, .shift]))
        }
        return bindings
    }()
    static let screenshotBindings: Set<GlobalHotkeyBinding> = {
        var result: Set<GlobalHotkeyBinding> = []
        for key in ["3", "4", "5", "6"] {
            let code = GlobalHotkeyKeys.code(forMenuKey: key)
            result.insert(.init(keyCode: code, modifiers: [.command, .shift]))
            // Control variants copy to the clipboard (3, 4) or capture the Touch Bar (6);
            // Command+Shift+Control+5 is the original Upload chord and no macOS screenshot shortcut.
            if key != "5" { result.insert(.init(keyCode: code, modifiers: [.command, .shift, .control])) }
        }
        return result
    }()

    func validate(additionalReserved: Set<GlobalHotkeyBinding> = []) throws {
        guard version == 1 else { throw globalHotkeyFailure("Unsupported global-shortcut settings version: \(version). Reset or reconfigure the shortcuts.") }
        var seen: [GlobalHotkeyBinding: GlobalHotkeyAction] = [:]
        for action in GlobalHotkeyAction.allCases {
            let binding = self[action]
            guard binding.modifiers.rawValue & ~GlobalHotkeyModifiers.allowed.rawValue == 0 else {
                throw globalHotkeyFailure("\(action.title) has unsupported modifiers.")
            }
            guard let code = binding.keyCode else {
                guard binding.modifiers.isEmpty else { throw globalHotkeyFailure("None cannot have modifiers for \(action.title).") }
                continue
            }
            guard GlobalHotkeyKeys.name(for: code) != nil else { throw globalHotkeyFailure("Unsupported physical key code \(code) for \(action.title).") }
            guard !binding.modifiers.intersection([.command, .control]).isEmpty else {
                throw globalHotkeyFailure("Choose Command or Control for \(action.title); plain typing keys cannot be global shortcuts.")
            }
            if let other = seen[binding] { throw globalHotkeyFailure("\(action.title) and \(other.title) use the same shortcut: \(binding.displayName).") }
            seen[binding] = action
            if Self.screenshotBindings.contains(binding) { throw globalHotkeyFailure("\(binding.displayName) is reserved for macOS screenshots. Choose another shortcut.") }
            if Self.internalBindings.contains(binding) || additionalReserved.contains(binding) {
                throw globalHotkeyFailure("\(binding.displayName) clashes with an app or system shortcut. Choose another shortcut.")
            }
        }
    }
    var activeBindings: [GlobalHotkeyAction: GlobalHotkeyBinding] {
        guard enabled else { return [:] }
        return Dictionary(uniqueKeysWithValues: GlobalHotkeyAction.allCases.compactMap { action in
            self[action].keyCode == nil ? nil : (action, self[action])
        })
    }
}

// Only this versioned, bounded settings blob is persisted. None is encoded as a
// missing keyCode plus empty modifiers. No account, credential or captured key
// text is stored. A corrupt/future blob must not fall back to enabled defaults.
struct GlobalHotkeyStore {
    static let defaultsKey = "OpenSnap.GlobalHotkeys.v1"
    let defaults: UserDefaults
    func load() throws -> GlobalHotkeySettings {
        guard let object = defaults.object(forKey: Self.defaultsKey) else { return .defaults }
        guard let data = object as? Data, data.count <= 16_384 else {
            throw globalHotkeyFailure("Saved global-shortcut settings are invalid. Reset or configure them before enabling shortcuts.")
        }
        let settings = try JSONDecoder().decode(GlobalHotkeySettings.self, from: data)
        try settings.validate()
        return settings
    }
    func encoded(_ settings: GlobalHotkeySettings) throws -> Data {
        try settings.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(settings)
    }
    func save(_ settings: GlobalHotkeySettings) throws { write(try encoded(settings)) }
    func write(_ data: Data) { defaults.set(data, forKey: Self.defaultsKey) }
}

// Injectable registration boundary makes persistence, conflict, rollback and
// lifecycle tests pure: tests never register an actual desktop shortcut.
@MainActor
protocol GlobalHotkeyBackend: AnyObject {
    var registeredIDs: Set<UInt32> { get }
    func installHandler(onEvent: @escaping @MainActor @Sendable (UInt32) -> Void) throws
    func systemReservedBindings() throws -> Set<GlobalHotkeyBinding>
    func register(_ binding: GlobalHotkeyBinding, id: UInt32) throws
    func unregister(id: UInt32) throws
    func shutdown() throws
}

private final class CarbonHotkeyRelay: Sendable {
    let signature: UInt32
    let callback: @MainActor @Sendable (UInt32) -> Void
    init(signature: UInt32, callback: @escaping @MainActor @Sendable (UInt32) -> Void) {
        self.signature = signature; self.callback = callback
    }
}

private let openSnapGlobalHotkeyHandler: EventHandlerUPP = { _, event, userData in
    guard Thread.isMainThread, let event, let userData,
          GetEventClass(event) == UInt32(kEventClassKeyboard),
          GetEventKind(event) == UInt32(kEventHotKeyPressed) else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard status == noErr else { return status }
    let relay = Unmanaged<CarbonHotkeyRelay>.fromOpaque(userData).takeUnretainedValue()
    guard identifier.signature == relay.signature else { return OSStatus(eventNotHandledErr) }
    return MainActor.assumeIsolated { relay.callback(identifier.id); return noErr }
}

// Pointer resources are accessed on main only. Deallocation copies the cleanup
// batch to main and retains the handler context until RemoveEventHandler returns.
private final class CarbonHotkeyCleanup: @unchecked Sendable {
    let refs: [EventHotKeyRef]
    let handler: EventHandlerRef?
    let relay: CarbonHotkeyRelay?
    init(refs: [EventHotKeyRef], handler: EventHandlerRef?, relay: CarbonHotkeyRelay?) {
        self.refs = refs; self.handler = handler; self.relay = relay
    }
    @MainActor func run() {
        for ref in refs {
            let status = UnregisterEventHotKey(ref)
            if status != noErr { NSLog("Global hotkey cleanup: UnregisterEventHotKey OSStatus %d", status) }
        }
        if let handler {
            let status = RemoveEventHandler(handler)
            if status != noErr {
                NSLog("Global hotkey cleanup: RemoveEventHandler OSStatus %d", status)
                // If Carbon refuses removal, keep the weak-callback context alive
                // rather than leaving a dangling native userData pointer.
                if let relay { _ = Unmanaged.passRetained(relay) }
            }
        }
    }
}

private final class CarbonHotkeyResources: @unchecked Sendable {
    var refs: [UInt32: EventHotKeyRef] = [:]
    var handler: EventHandlerRef?
    var relay: CarbonHotkeyRelay?
    deinit {
        let batch = CarbonHotkeyCleanup(refs: Array(refs.values), handler: handler, relay: relay)
        if Thread.isMainThread { MainActor.assumeIsolated { batch.run() } }
        else { DispatchQueue.main.async { batch.run() } }
    }
}

@MainActor
private final class CarbonGlobalHotkeyBackend: GlobalHotkeyBackend {
    private let resources = CarbonHotkeyResources()
    var registeredIDs: Set<UInt32> { Set(resources.refs.keys) }
    func installHandler(onEvent: @escaping @MainActor @Sendable (UInt32) -> Void) throws {
        guard resources.handler == nil else { return }
        let relay = CarbonHotkeyRelay(signature: UInt32.random(in: 1...UInt32.max), callback: onEvent)
        var specification = EventTypeSpec(eventClass: UInt32(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var handler: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), openSnapGlobalHotkeyHandler, 1,
                                         &specification, Unmanaged.passUnretained(relay).toOpaque(), &handler)
        guard status == noErr else { throw carbonHotkeyFailure("InstallEventHandler", status) }
        guard let handler else { throw globalHotkeyFailure("InstallEventHandler returned success without a handler reference.") }
        resources.relay = relay; resources.handler = handler
    }
    func systemReservedBindings() throws -> Set<GlobalHotkeyBinding> {
        var array: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&array)
        guard status == noErr else { throw carbonHotkeyFailure("CopySymbolicHotKeys", status) }
        guard let array, let entries = array.takeRetainedValue() as? [[String: Any]] else {
            throw globalHotkeyFailure("macOS returned invalid system-shortcut information.")
        }
        var bindings: Set<GlobalHotkeyBinding> = []
        // CFSTR macro names and dictionary schema are documented in CarbonEvents.h.
        for entry in entries {
            guard (entry["kHISymbolicHotKeyEnabled"] as? NSNumber)?.boolValue == true,
                  let code = entry["kHISymbolicHotKeyCode"] as? NSNumber,
                  let modifiers = entry["kHISymbolicHotKeyModifiers"] as? NSNumber else { continue }
            bindings.insert(.init(keyCode: code.uint32Value, modifiers: .init(carbonFlags: modifiers.uint32Value)))
        }
        return bindings
    }
    func register(_ binding: GlobalHotkeyBinding, id: UInt32) throws {
        guard let relay = resources.relay, resources.handler != nil,
              let code = binding.keyCode, resources.refs[id] == nil else {
            throw globalHotkeyFailure("The global-shortcut registration lifecycle is invalid.")
        }
        var ref: EventHotKeyRef?
        // Exclusive registration surfaces another app's claim as an actual
        // eventHotKeyExistsErr, instead of silently triggering both applications.
        let status = RegisterEventHotKey(code, binding.modifiers.carbonFlags,
                                         EventHotKeyID(signature: relay.signature, id: id),
                                         GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &ref)
        guard status == noErr else { throw carbonHotkeyFailure("RegisterEventHotKey for \(binding.displayName)", status, shortcut: binding.displayName) }
        guard let ref else { throw globalHotkeyFailure("RegisterEventHotKey returned success without a registration reference.") }
        resources.refs[id] = ref
    }
    func unregister(id: UInt32) throws {
        guard let ref = resources.refs[id] else { return }
        let status = UnregisterEventHotKey(ref)
        guard status == noErr else { throw carbonHotkeyFailure("UnregisterEventHotKey", status) }
        resources.refs.removeValue(forKey: id)
    }
    func shutdown() throws {
        var failures: [Error] = []
        for id in registeredIDs.sorted() {
            do { try unregister(id: id) } catch { failures.append(error) }
        }
        if let handler = resources.handler {
            let status = RemoveEventHandler(handler)
            if status == noErr { resources.handler = nil; resources.relay = nil }
            else { failures.append(carbonHotkeyFailure("RemoveEventHandler", status)) }
        }
        if !failures.isEmpty { throw globalHotkeyFailure(failures.map { $0.localizedDescription }.joined(separator: "\n"), underlying: failures) }
    }
}

/// Parent API: retain a manager, install the five callbacks at launch, call
/// showSettings(attachedTo:) from Preferences, and unregister() on termination.
/// init has no desktop registration side effects. install/register are explicit.
@MainActor
final class GlobalHotkeyManager: NSObject, GlobalHotkeyEditing {
    typealias Callback = @MainActor () -> Void
    private let store: GlobalHotkeyStore
    private let backend: GlobalHotkeyBackend
    private let reservedBindings: Set<GlobalHotkeyBinding>
    private var callbacks: [GlobalHotkeyAction: Callback] = [:]
    private var active: [GlobalHotkeyAction: GlobalHotkeyBinding] = [:]
    private var generation: UInt64 = 0
    private var activationRequested = false
    private var loadError: Error?
    private(set) var settings: GlobalHotkeySettings
    private(set) var lastError: Error?
    private(set) var isRunning = false
    var registeredActions: Set<GlobalHotkeyAction> { Set(active.keys) }

    init(defaults: UserDefaults = .standard,
         reservedBindings: Set<GlobalHotkeyBinding> = [], backend: GlobalHotkeyBackend? = nil) {
        store = GlobalHotkeyStore(defaults: defaults)
        self.backend = backend ?? CarbonGlobalHotkeyBackend()
        self.reservedBindings = reservedBindings
        do { settings = try store.load() }
        catch { settings = .disabled; lastError = error; loadError = error }
        super.init()
    }

    func install(globalScreen: @escaping Callback, globalWindow: @escaping Callback,
                 globalFullscreen: @escaping Callback, globalFrame: @escaping Callback,
                 globalUpload: @escaping Callback, globalShow: @escaping Callback) throws {
        callbacks = [.screen: globalScreen, .window: globalWindow, .fullscreen: globalFullscreen,
                     .frame: globalFrame, .upload: globalUpload, .show: globalShow]
        generation &+= 1
        try register()
    }

    func register() throws {
        guard callbacks.count == GlobalHotkeyAction.allCases.count else { throw globalHotkeyFailure("Install the capture callbacks before registering global shortcuts.") }
        activationRequested = true
        do {
            if let loadError { throw loadError }
            let reserved = try currentReservedBindings(includingSystem: !settings.activeBindings.isEmpty)
            try settings.validate(additionalReserved: reserved)
            try backend.installHandler { [weak self] id in self?.enqueue(id: id) }
            try transition(to: editing ? [:] : settings.activeBindings)
            isRunning = true; lastError = nil
        } catch {
            lastError = error
            throw error
        }
    }

    /// Unregister without changing saved preferences. Failed native removals
    /// remain owned for retry/cleanup, while callback delivery is disabled.
    func unregister() throws {
        activationRequested = false
        isRunning = false; generation &+= 1
        do {
            try backend.shutdown()
            active = [:]
        } catch {
            active = active.filter { backend.registeredIDs.contains($0.key.carbonID) }
            lastError = error
            throw error
        }
    }

    func apply(_ candidate: GlobalHotkeySettings) throws {
        do {
            try candidate.validate(additionalReserved: try currentReservedBindings(includingSystem: !candidate.activeBindings.isEmpty))
            let data = try store.encoded(candidate)
            if isRunning || activationRequested {
                // A launch-time conflict must not require relaunch after the
                // user repairs it in Preferences. Explicit unregister still
                // keeps the manager stopped while settings are edited, and so
                // does editing: a change is saved at once but goes live only
                // when the editor lets go (`setEditing(false)`).
                try backend.installHandler { [weak self] id in self?.enqueue(id: id) }
                if !editing { try transition(to: candidate.activeBindings) }
                isRunning = true
            }
            store.write(data)
            settings = candidate; lastError = nil; loadError = nil
        } catch { lastError = error; throw error }
    }
    func clearAll() throws { try apply(.defaults) }

    /// True while the shortcut editor is on screen. The saved shortcuts stay saved but none is registered, so a half-entered binding never
    /// goes live system-wide, and pressing a chord to see what it does cannot start a capture from inside the editor.
    private(set) var editing = false
    func setEditing(_ value: Bool) {
        guard value != editing else { return }
        editing = value
        guard isRunning || activationRequested else { return }
        do {
            try transition(to: value ? [:] : settings.activeBindings)
            if !value { lastError = nil }
        } catch { lastError = error }
    }

    private func currentReservedBindings(includingSystem: Bool) throws -> Set<GlobalHotkeyBinding> {
        var result = reservedBindings
        if includingSystem { result.formUnion(try backend.systemReservedBindings()) }
        func read(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { read(submenu) }
                guard !item.keyEquivalent.isEmpty,
                      let code = GlobalHotkeyKeys.code(forMenuKey: item.keyEquivalent) else { continue }
                var modifiers = GlobalHotkeyModifiers(appKitFlags: item.keyEquivalentModifierMask)
                if item.keyEquivalent.count == 1, item.keyEquivalent != item.keyEquivalent.lowercased() { modifiers.insert(.shift) }
                result.insert(.init(keyCode: code, modifiers: modifiers))
            }
        }
        if let menu = NSApp?.mainMenu { read(menu) }
        return result
    }

    private func transition(to target: [GlobalHotkeyAction: GlobalHotkeyBinding]) throws {
        generation &+= 1
        let previous = active
        do { try reconcile(to: target) }
        catch {
            let original = error
            do { try reconcile(to: previous) }
            catch {
                throw globalHotkeyFailure("Shortcut update failed: \(original.localizedDescription)\nRestoring the previous shortcuts also failed: \(error.localizedDescription)", underlying: [original, error])
            }
            throw original
        }
    }
    private func reconcile(to target: [GlobalHotkeyAction: GlobalHotkeyBinding]) throws {
        for action in GlobalHotkeyAction.allCases where active[action] != target[action] {
            if active[action] != nil {
                try backend.unregister(id: action.carbonID)
                active.removeValue(forKey: action)
            }
        }
        for action in GlobalHotkeyAction.allCases where active[action] != target[action] {
            if let binding = target[action] {
                try backend.register(binding, id: action.carbonID)
                active[action] = binding
            }
        }
    }
    private func enqueue(id: UInt32) {
        guard let action = GlobalHotkeyAction.allCases.first(where: { $0.carbonID == id }),
              isRunning, active[action] != nil else { return }
        let expectedGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning, self.generation == expectedGeneration,
                  self.active[action] != nil,
                  NSApp?.modalWindow == nil, NSApp?.keyWindow?.attachedSheet == nil,
                  NSApp?.keyWindow?.sheetParent == nil else { return }
            self.callbacks[action]?()
        }
    }
}

/// What the shortcut editor needs from the manager: the saved settings, the last failure, and a way to apply a candidate.
/// The real manager conforms; the app's isolated tests conform a stand-in that never touches the desktop.
@MainActor
protocol GlobalHotkeyEditing: AnyObject {
    var settings: GlobalHotkeySettings { get }
    var lastError: Error? { get }
    func apply(_ candidate: GlobalHotkeySettings) throws
    /// The editor is on screen (true) or gone (false); see `GlobalHotkeyManager.setEditing`. A stand-in with nothing registered ignores it.
    func setEditing(_ value: Bool)
}
extension GlobalHotkeyEditing { func setEditing(_ value: Bool) {} }

/// A titled command on a glass action plate: the chrome's `CommandButton` (borderless, a 20 pt label, its own rest, hover, pressed, focus
/// and disabled fills drawn by `StatePlate`) sized to its label, so it reads as a button on a plate. Nothing here is a second glass
/// surface. The Settings window's Upload commands and the shortcut form's Clear All use it; it lives here because both files compile together.
@MainActor
final class SettingsActionButton: CommandButton {
    static let padding = DesignTokens.Space.s4

    /// The width a button takes for this label: the label and the padding either side.
    static func width(for title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: DesignTokens.Typography.font(.body)]).width) + 2 * padding
    }

    /// Called once the title initializer has finished: it sets the system's 13 pt font after `init(frame:)`, which the chrome floors to 18 pt.
    func configure() {
        GlassChrome.useExtraLarge(self)
        DesignTokens.Typography.apply(.body, to: self)
        accessibility = ChromeAccessibility.live
        setContentCompressionResistancePriority(.required, for: .horizontal)
        // The label is drawn from an attributed string: the button's own title field would keep the system's 13 pt and take no state colour.
        plate.onApply = { [weak self] _ in self?.styleTitle() }
        styleTitle()
    }

    private func styleTitle() {
        let text = visibleTitle
        guard !text.isEmpty else { return }
        attributedTitle = NSAttributedString(string: text, attributes: [.font: DesignTokens.Typography.font(.body), .foregroundColor: plate.stateStyle.content])
    }

    override var title: String {
        didSet { invalidateIntrinsicContentSize(); styleTitle() }
    }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.width(for: visibleTitle), height: GlassChrome.Metrics.commandHeight) }
}

/// A label cell that draws its text higher (positive) or lower (negative) than its frame centres it, and changes nothing about what the field
/// needs: its cell size, and so the field's fitting size, are the plain text's. The modifier symbols use it to sit optically centred on a button.
final class ShiftedLabelCell: NSTextFieldCell {
    /// Points the text is raised in the field (negative lowers it).
    var raise: CGFloat = 0

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var shifted = super.titleRect(forBounds: rect)
        // Drawing space is flipped in a text field (y grows downward) and not in a plain view.
        shifted.origin.y += (controlView?.isFlipped ?? true) ? -raise : raise
        return shifted
    }
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var shifted = super.drawingRect(forBounds: rect)
        shifted.origin.y += (controlView?.isFlipped ?? true) ? -raise : raise
        return shifted
    }
}

/// The shortcut editor, the one surface for capture shortcuts (Settings › Capture; the app menu's Capture Shortcuts… opens it there).
/// Every edit is applied through the manager at once, and one the manager rejects stays on screen with an "Error:" line until the
/// next edit that it accepts. Its choices are glass: the enable box is a checkbox toggle on a plate, each action's key is a glass pop-up
/// and its four modifiers are toggles on ONE plate per row, and Clear All is a titled command on an action plate. The buttons draw their
/// own state fills, so there is never glass inside glass.
@MainActor
final class GlobalHotkeyForm: NSView {
    private typealias Typography = DesignTokens.Typography
    private typealias Space = DesignTokens.Space

    /// Modifier order on a row: the symbol drawn, the spoken name.
    static let modifierSegments: [(GlobalHotkeyModifiers, String, String)] = [
        (.command, "\u{2318}", "Command"), (.option, "\u{2325}", "Option"), (.control, "\u{2303}", "Control"), (.shift, "\u{21E7}", "Shift")]
    static let idleLiveStatus = "Shortcuts are saved as you change them. They pause while this window is in front."
    /// What the note says while the shortcuts really are paused, so the state is readable without firing one (F-J7-004).
    static let pausedStatus = "Shortcuts are paused while this window is in front."
    static let keyPopupWidth: CGFloat = 120, modifierSegmentWidth: CGFloat = 44
    /// What the modifier toggles say when the pointer rests on them.
    static let modifierToolTip = "Modifier keys: " + modifierSegments.map { "\($0.1) \($0.2)" }.joined(separator: ", ")

    /// The label column is shared with the form it sits in, so its labels line up with the rows around it.
    static func labelTexts() -> [String] { ["Shortcuts:"] + GlobalHotkeyAction.allCases.map { $0.title + ":" } }
    static func labelFont() -> NSFont { Typography.font(.bodyStrong) }

    /// One action's row: the key pop-up (in a fill cell, which supplies its hover and press fills) and the four modifier toggles, all on one plate.
    private final class Row {
        let key: GlassPopUpButton
        let keyCell: ChromeFillCell
        let modifiers: [GlassChoiceButton]
        /// The four toggles in one accessibility group, named after the row.
        let group: NSStackView
        let plate: GlassSurfaceView
        /// The toggle that is the group's one tab stop: where the keyboard last was, else the first.
        var stop = 0
        init(key: GlassPopUpButton, keyCell: ChromeFillCell, modifiers: [GlassChoiceButton], group: NSStackView, plate: GlassSurfaceView) {
            self.key = key; self.keyCell = keyCell; self.modifiers = modifiers; self.group = group; self.plate = plate
        }
    }

    private weak var manager: (any GlobalHotkeyEditing)?
    private var rows: [GlobalHotkeyAction: Row] = [:]
    let enabledCheckbox = GlassChoiceButton(title: "Enable global capture shortcuts", kind: .toggle, indicator: .checkbox, layout: .row)
    let statusField = NSTextField(wrappingLabelWithString: "")
    private(set) var clearButton: SettingsActionButton!
    /// The plates: one for the enable box, one per action, one for Clear All.
    private(set) var enabledPlate: GlassSurfaceView!, clearPlate: GlassSurfaceView!
    var rowPlates: [GlassSurfaceView] { GlobalHotkeyAction.allCases.compactMap { rows[$0]?.plate } }
    private var displayObservation: DisplayOptions.Observation?
    /// The status line changed height, so the window holding the form may need a new size.
    var onResize: (() -> Void)?
    /// Whether the manager has the shortcuts paused because this form is the thing in use. The note follows it (an error keeps the line
    /// until the next accepted edit), and VoiceOver reads the same words.
    private(set) var shortcutsPaused = false
    private var showsError = false
    /// The error on the note is the one the manager reported when the pause lifted (the shortcuts could not be put back), not one from an edit.
    private var errorFromPause = false
    private var liveStatus: String { shortcutsPaused ? Self.pausedStatus : Self.idleLiveStatus }
    func setShortcutsPaused(_ paused: Bool) {
        guard paused != shortcutsPaused else { return }
        shortcutsPaused = paused
        // Putting the shortcuts back can fail (a key another app took meanwhile): the note must not go on saying they are live (R3-008).
        if !paused, let error = manager?.lastError {
            setStatus("Error: " + error.localizedDescription, isError: true, error: error)
            errorFromPause = true
        } else if !showsError || errorFromPause { setStatus(liveStatus, isError: false) }
    }

    func keyPopup(for action: GlobalHotkeyAction) -> GlassPopUpButton { rows[action]!.key }
    /// The four modifier toggles of an action's row, in `modifierSegments` order (Command, Option, Control, Shift).
    func modifierToggles(for action: GlobalHotkeyAction) -> [GlassChoiceButton] { rows[action]!.modifiers }
    func rowPlate(for action: GlobalHotkeyAction) -> GlassSurfaceView { rows[action]!.plate }
    /// The group that holds an action's four modifier toggles: one tab stop, named "<action> modifiers" for VoiceOver.
    func modifierGroup(for action: GlobalHotkeyAction) -> NSStackView { rows[action]!.group }
    /// The modifier toggle that is that group's tab stop now.
    func modifierStop(for action: GlobalHotkeyAction) -> GlassChoiceButton { rows[action]!.modifiers[rows[action]!.stop] }

    init(manager: any GlobalHotkeyEditing, labelWidth: CGFloat, width: CGFloat) {
        self.manager = manager
        super.init(frame: .zero)
        let statusWidth = width - labelWidth - Space.s4
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = Self.labelFont(); field.alignment = .right; field.textColor = DesignTokens.Palette.Text.primary
            return field
        }
        func plate(_ views: [NSView], identifier: String, name: String, axis: NSUserInterfaceLayoutOrientation = .horizontal) -> GlassSurfaceView {
            let plate = GlassChrome.plate(views, identifier: identifier, accessibility: ChromeAccessibility.live, axis: axis)
            plate.setAccessibilityElement(true); plate.setAccessibilityLabel(name); plate.setAccessibilityRole(.group)
            return plate
        }
        enabledCheckbox.identifier = NSUserInterfaceItemIdentifier("GlobalHotkeyEnabled")
        enabledCheckbox.target = self; enabledCheckbox.action = #selector(enabledChanged(_:))
        enabledPlate = plate([enabledCheckbox], identifier: "GlobalHotkeyEnabledPlate", name: "Shortcuts", axis: .vertical)
        var gridRows: [[NSView]] = [[label("Shortcuts:"), enabledPlate]]
        for action in GlobalHotkeyAction.allCases {
            let key = GlassPopUpButton(frame: .zero, pullsDown: false)
            key.addItems(withTitles: ["None"] + GlobalHotkeyKeys.choices.map(\.name))
            key.panelIdentifier = "GlobalHotkeyKey." + action.rawValue; key.panelLabel = "\(action.title) key"
            key.setAccessibilityLabel("\(action.title) key")
            key.target = self; key.action = #selector(keyChanged(_:))
            let keyCell = ChromeFillCell(key, size: NSSize(width: max(Self.keyPopupWidth, ceil(key.intrinsicContentSize.width)), height: GlassChrome.Metrics.commandHeight))
            let toggles = Self.modifierSegments.enumerated().map { index, entry -> GlassChoiceButton in
                let toggle = GlassChoiceButton(title: entry.1, kind: .toggle, indicator: GlassChoiceButton.Indicator.none, layout: .segment)
                toggle.minimumWidth = Self.modifierSegmentWidth
                toggle.identifier = NSUserInterfaceItemIdentifier("GlobalHotkey.\(action.rawValue).\(entry.2.lowercased())")
                // The symbol is what is drawn; the name VoiceOver speaks says whose modifier it is, so six rows of Command are told apart.
                toggle.setAccessibilityLabel("\(action.title) \(entry.2)")
                toggle.target = self; toggle.action = #selector(modifiersChanged(_:))
                AppToolTip.setText(Self.modifierToolTip, for: toggle)
                Self.centre(symbol: entry.1, in: toggle)
                // The four toggles are ONE tab stop, like the segmented control they replace: only the stop takes Tab, and the arrows move within the row.
                toggle.participatesInKeyLoop = index == 0
                toggle.keyHandler = { [weak self, weak toggle] event in
                    guard let self, let toggle else { return false }
                    return self.modifierKey(event, from: toggle, action: action)
                }
                return toggle
            }
            let group = NSStackView(views: toggles)
            group.orientation = .horizontal; group.alignment = .centerY; group.spacing = GlassChrome.Metrics.groupSpacing
            group.setAccessibilityElement(true); group.setAccessibilityRole(.group); group.setAccessibilityLabel("\(action.title) modifiers")
            group.setAccessibilityChildren(toggles)
            let rowPlate = plate([keyCell, group], identifier: "GlobalHotkeyRow." + action.rawValue, name: "\(action.title) shortcut")
            rows[action] = Row(key: key, keyCell: keyCell, modifiers: toggles, group: group, plate: rowPlate)
            gridRows.append([label(action.title + ":"), rowPlate])
        }
        statusField.font = Typography.font(.body)
        statusField.setAccessibilityRole(.staticText)
        statusField.preferredMaxLayoutWidth = statusWidth
        statusField.widthAnchor.constraint(equalToConstant: statusWidth).isActive = true
        gridRows.append([NSGridCell.emptyContentView, statusField])
        clearButton = SettingsActionButton(title: "Clear All", target: self, action: #selector(clearAll(_:)))
        clearButton.configure()
        clearButton.identifier = NSUserInterfaceItemIdentifier("GlobalHotkeyClearAll")
        clearPlate = plate([clearButton], identifier: "GlobalHotkeyClearPlate", name: "Clear shortcuts")
        gridRows.append([NSGridCell.emptyContentView, clearPlate])

        let grid = NSGridView(views: gridRows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        // The Settings tab has to fit a small screen, so its rows sit close: a plate carries its own 4 pt of padding either side.
        grid.rowSpacing = Space.s1; grid.columnSpacing = Space.s4
        grid.column(at: 0).xPlacement = .trailing; grid.column(at: 0).width = labelWidth
        grid.column(at: 1).xPlacement = .leading
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor), grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor), grid.bottomAnchor.constraint(equalTo: bottomAnchor)])
        applyDisplayOptions()
        displayObservation = DisplayOptions.observe { [weak self] _ in self?.applyDisplayOptions() }
        reload()
    }
    required init?(coder: NSCoder) { fatalError("Use init(manager:labelWidth:width:)") }

    /// The plates and the buttons on them follow the display options (Reduce Transparency, Increase Contrast, Reduce Motion, Differentiate
    /// Without Color) while the window is up.
    private func applyDisplayOptions() {
        let options = ChromeAccessibility.live
        for plate in [enabledPlate, clearPlate].compactMap({ $0 }) + rowPlates { plate.accessibility = options }
        enabledCheckbox.accessibility = options
        clearButton?.accessibility = options
        for row in rows.values { row.keyCell.accessibility = options; for toggle in row.modifiers { toggle.accessibility = options } }
    }

    /// Shows what the manager has saved, drops any unsaved draft and clears the status line. Delivers nothing.
    func reload() {
        guard let manager else { return }
        fill(manager.settings)
        setStatus(manager.lastError.map { "Error: " + $0.localizedDescription } ?? liveStatus,
                  isError: manager.lastError != nil, error: manager.lastError)
    }

    private func setStatus(_ text: String, isError: Bool, error: Error? = nil) {
        let changed = statusField.stringValue != text
        showsError = isError; errorFromPause = false
        statusField.stringValue = text
        // The words are for the person; the call and status that failed ride on the tooltip and the spoken help.
        AppToolTip.setText(error?.hotkeyTechnicalDetail, for: statusField)
        statusField.textColor = isError ? DesignTokens.Palette.feedbackError : DesignTokens.Palette.Text.primary
        if changed { invalidateIntrinsicContentSize(); needsLayout = true; onResize?() }
    }

    private func fill(_ settings: GlobalHotkeySettings) {
        enabledCheckbox.state = settings.enabled ? .on : .off
        for action in GlobalHotkeyAction.allCases {
            guard let row = rows[action] else { continue }
            let binding = settings[action]
            let index = binding.keyCode.flatMap { code in GlobalHotkeyKeys.choices.firstIndex { $0.code == code } }.map { $0 + 1 } ?? 0
            row.key.selectItem(at: index)
            for (toggle, entry) in zip(row.modifiers, Self.modifierSegments) {
                toggle.state = binding.modifiers.contains(entry.0) ? .on : .off
                toggle.isEnabled = index > 0
            }
        }
    }

    func draft() -> GlobalHotkeySettings {
        var settings = GlobalHotkeySettings(); settings.enabled = enabledCheckbox.state == .on
        for action in GlobalHotkeyAction.allCases {
            guard let row = rows[action], row.key.indexOfSelectedItem > 0 else { settings[action] = .none; continue }
            var modifiers: GlobalHotkeyModifiers = []
            for (toggle, entry) in zip(row.modifiers, Self.modifierSegments) where toggle.state == .on { modifiers.insert(entry.0) }
            settings[action] = .init(keyCode: GlobalHotkeyKeys.choices[row.key.indexOfSelectedItem - 1].code, modifiers: modifiers)
        }
        return settings
    }

    /// Applies the draft now. A rejected draft stays on screen beside its error.
    private func commit() {
        guard let manager else { return }
        do { try manager.apply(draft()); setStatus(liveStatus, isError: false) }
        catch { setStatus("Error: " + error.localizedDescription, isError: true, error: error) }
    }

    /// Unticking the box switches off what is saved. A draft the manager had rejected (two actions on one key, say) is dropped with its
    /// error instead of being validated again, so the red line does not outlive the command that made it moot.
    private func disableSaved() {
        guard let manager else { return }
        var saved = manager.settings; saved.enabled = false
        do { try manager.apply(saved); reload() }
        catch { setStatus("Error: " + error.localizedDescription, isError: true, error: error) }
    }

    @objc private func enabledChanged(_ sender: NSButton) { if sender.state == .off { disableSaved() } else { commit() } }
    @objc private func keyChanged(_ sender: NSPopUpButton) {
        guard let row = rows.values.first(where: { $0.key === sender }) else { return }
        let hasKey = sender.indexOfSelectedItem > 0
        for toggle in row.modifiers { toggle.isEnabled = hasKey; if !hasKey { toggle.state = .off } }
        commit()
    }
    @objc private func modifiersChanged(_ sender: NSButton) {
        if let row = rows.values.first(where: { $0.modifiers.contains { $0 === sender } }), let index = row.modifiers.firstIndex(where: { $0 === sender }) { setStop(index, in: row) }
        commit()
    }

    /// Makes one of a row's modifier toggles the group's tab stop; the others leave the key loop.
    private func setStop(_ index: Int, in row: Row) {
        row.stop = index
        for (position, toggle) in row.modifiers.enumerated() { toggle.participatesInKeyLoop = position == index }
    }

    /// Keys on a focused modifier toggle. Left and Right move the focus within the four (wrapping, skipping any that is disabled), and Space,
    /// Return and Enter flip the focused one exactly once. Anything else (Tab included) is left to the window. The toggle the keyboard is on
    /// becomes the group's stop, so Tab comes back to it.
    private func modifierKey(_ event: NSEvent, from toggle: GlassChoiceButton, action: GlobalHotkeyAction) -> Bool {
        guard let row = rows[action], let index = row.modifiers.firstIndex(where: { $0 === toggle }) else { return false }
        setStop(index, in: row)
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return false }
        switch event.keyCode {
        case 123, 124:
            let step = event.keyCode == 124 ? 1 : -1, count = row.modifiers.count
            var next = index
            for _ in 0..<count {
                next = (next + step + count) % count
                if row.modifiers[next].isEnabled { break }
            }
            guard next != index, row.modifiers[next].isEnabled else { return true }
            window?.makeFirstResponder(row.modifiers[next])
            setStop(next, in: row)
            return true
        case 49, 36, 76:
            toggle.performClick(nil)
            return true
        default: return false
        }
    }

    /// A modifier symbol drawn at its own glyph's ink centre. Some of the four sit high or low in their em box (the control caret is a small
    /// mark at the top of it), so each is drawn lower or higher until the middle of its ink is on the middle of the line the others sit on.
    /// The shift is in the cell's drawing and nowhere else: a baseline offset in the text would make the field need a taller line than the
    /// button gave its label, so the label's fitting size stays the plain symbol's and its frame holds it whole.
    private static func centre(symbol: String, in toggle: GlassChoiceButton) {
        let font = Typography.font(.body)
        let ink = CTLineGetImageBounds(CTLineCreateWithAttributedString(NSAttributedString(string: symbol, attributes: [.font: font])), nil)
        let target = (font.ascender + font.descender) / 2
        let shift = target - ink.midY
        guard abs(shift) > 0.5 else { return }
        let label = toggle.titleLabel
        let cell = ShiftedLabelCell(textCell: symbol)
        cell.font = label.font ?? font
        cell.textColor = label.textColor
        cell.isBordered = false; cell.drawsBackground = false; cell.isSelectable = false; cell.isEditable = false
        cell.alignment = label.alignment; cell.lineBreakMode = .byClipping; cell.usesSingleLineMode = true
        cell.raise = shift
        label.cell = cell
        label.font = cell.font
    }
    /// Clear All sets every key to None (first launch claims no shortcut, so this is also where a fresh install starts).
    @objc private func clearAll(_ sender: Any?) {
        fill(.defaults); commit()
    }
}
