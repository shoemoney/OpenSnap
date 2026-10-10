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

private func carbonHotkeyFailure(_ operation: String, _ status: OSStatus) -> NSError {
    NSError(domain: NSOSStatusErrorDomain, code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "\(operation) failed (OSStatus \(status))."])
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
    // First launch and Reset Defaults claim no shortcuts. Only explicit saved
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
        guard status == noErr else { throw carbonHotkeyFailure("RegisterEventHotKey for \(binding.displayName)", status) }
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
    private var settingsPanel: GlobalHotkeySettingsPanel?
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
            try transition(to: settings.activeBindings)
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
                // keeps the manager stopped while settings are edited.
                try backend.installHandler { [weak self] id in self?.enqueue(id: id) }
                try transition(to: candidate.activeBindings)
                isRunning = true
            }
            store.write(data)
            settings = candidate; lastError = nil; loadError = nil
        } catch { lastError = error; throw error }
    }
    func disableAll() throws { var candidate = settings; candidate.enabled = false; try apply(candidate) }
    func resetDefaults() throws { try apply(.defaults) }

    func showSettings(attachedTo parent: NSWindow? = nil) {
        if settingsPanel == nil { settingsPanel = GlobalHotkeySettingsPanel(manager: self) }
        settingsPanel?.present(attachedTo: parent)
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
                  self.active[action] != nil, self.settingsPanel?.window?.isVisible != true,
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
}

/// The shortcut editor, shared by the capture sheet and the Settings window.
///
/// `.sheet` keeps the original transaction: edits stay in the draft until Save (Cancel discards them), and Reset Defaults
/// and Disable All only change the draft. `.live` is for the Settings window: every edit is applied through the manager at
/// once, and one the manager rejects stays on screen with an "Error:" line until the next edit that it accepts.
@MainActor
final class GlobalHotkeyForm: NSView {
    enum Mode { case sheet, live }
    private typealias Typography = DesignTokens.Typography
    private typealias Space = DesignTokens.Space

    /// Segment order of the modifier control: symbol, spoken name.
    static let modifierSegments: [(GlobalHotkeyModifiers, String, String)] = [
        (.command, "\u{2318}", "Command"), (.option, "\u{2325}", "Option"), (.control, "\u{2303}", "Control"), (.shift, "\u{21E7}", "Shift")]
    static let idleLiveStatus = "Shortcuts are saved as you change them."
    static let idleSheetStatus = "Shortcuts pause while this panel or another capture sheet is open. Save applies your changes; Cancel leaves them unchanged."
    static let keyPopupWidth: CGFloat = 120, modifierSegmentWidth: CGFloat = 44

    /// The label column is shared with the form it sits in, so its labels line up with the rows around it.
    static func labelTexts() -> [String] { ["Shortcuts:"] + GlobalHotkeyAction.allCases.map { $0.title + ":" } }
    static func labelFont() -> NSFont { Typography.font(.bodyStrong) }

    private final class Row {
        let key: NSPopUpButton
        let modifiers: NSSegmentedControl
        init(key: NSPopUpButton, modifiers: NSSegmentedControl) { self.key = key; self.modifiers = modifiers }
    }

    let mode: Mode
    private weak var manager: (any GlobalHotkeyEditing)?
    private var rows: [GlobalHotkeyAction: Row] = [:]
    let enabledCheckbox = NSButton(checkboxWithTitle: "Enable global capture shortcuts", target: nil, action: nil)
    let statusField = NSTextField(wrappingLabelWithString: "")
    private(set) var resetButton: NSButton!, disableButton: NSButton!
    private(set) var cancelButton: NSButton?, saveButton: NSButton?
    /// The sheet asks its panel to close; the live form never calls this.
    var onFinish: (() -> Void)?
    /// The status line changed height, so the window holding the form may need a new size.
    var onResize: (() -> Void)?

    func keyPopup(for action: GlobalHotkeyAction) -> NSPopUpButton { rows[action]!.key }
    func modifierControl(for action: GlobalHotkeyAction) -> NSSegmentedControl { rows[action]!.modifiers }

    init(manager: any GlobalHotkeyEditing, mode: Mode, labelWidth: CGFloat, width: CGFloat) {
        self.manager = manager; self.mode = mode
        super.init(frame: .zero)
        let statusWidth = width - labelWidth - Space.s4
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = Self.labelFont(); field.alignment = .right; field.textColor = DesignTokens.Palette.Text.primary
            return field
        }
        enabledCheckbox.font = Typography.font(.body); enabledCheckbox.controlSize = .large
        enabledCheckbox.target = self; enabledCheckbox.action = #selector(enabledChanged(_:))
        var gridRows: [[NSView]] = [[label("Shortcuts:"), enabledCheckbox]]
        for action in GlobalHotkeyAction.allCases {
            let key = NSPopUpButton(frame: .zero, pullsDown: false)
            Typography.apply(.body, to: key)
            key.addItems(withTitles: ["None"] + GlobalHotkeyKeys.choices.map(\.name))
            key.widthAnchor.constraint(equalToConstant: Self.keyPopupWidth).isActive = true
            key.setAccessibilityLabel("\(action.title) key")
            key.target = self; key.action = #selector(keyChanged(_:))
            let modifiers = NSSegmentedControl(labels: Self.modifierSegments.map(\.1), trackingMode: .selectAny, target: self, action: #selector(modifiersChanged(_:)))
            modifiers.font = Typography.font(.body); modifiers.controlSize = .large
            for index in Self.modifierSegments.indices { modifiers.setWidth(Self.modifierSegmentWidth, forSegment: index) }
            modifiers.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.Size.control).isActive = true
            modifiers.setAccessibilityLabel("\(action.title) modifier keys")
            AppToolTip.setText("Modifier keys: " + Self.modifierSegments.map { "\($0.1) \($0.2)" }.joined(separator: ", "), for: modifiers)
            let line = NSStackView(views: [key, modifiers])
            line.orientation = .horizontal; line.alignment = .centerY; line.spacing = Space.s3
            rows[action] = Row(key: key, modifiers: modifiers)
            gridRows.append([label(action.title + ":"), line])
        }
        statusField.font = Typography.font(.body)
        statusField.preferredMaxLayoutWidth = statusWidth
        statusField.widthAnchor.constraint(equalToConstant: statusWidth).isActive = true
        gridRows.append([NSGridCell.emptyContentView, statusField])
        resetButton = Self.button("Reset Defaults", self, #selector(reset(_:)))
        disableButton = Self.button("Disable All", self, #selector(disable(_:)))
        var buttons: [NSButton] = [resetButton, disableButton]
        if mode == .sheet {
            let cancel = Self.button("Cancel", self, #selector(cancel(_:))); cancel.keyEquivalent = "\u{1b}"
            let save = Self.button("Save", self, #selector(save(_:))); save.keyEquivalent = "\r"
            cancelButton = cancel; saveButton = save; buttons += [cancel, save]
        }
        let buttonRow = NSStackView(views: buttons); buttonRow.orientation = .horizontal; buttonRow.spacing = Space.s3
        gridRows.append([NSGridCell.emptyContentView, buttonRow])

        let grid = NSGridView(views: gridRows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = Space.s4; grid.columnSpacing = Space.s4
        grid.column(at: 0).xPlacement = .trailing; grid.column(at: 0).width = labelWidth
        grid.column(at: 1).xPlacement = .leading
        for index in 0..<grid.numberOfRows { grid.row(at: index).yPlacement = .center }
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor), grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor), grid.bottomAnchor.constraint(equalTo: bottomAnchor)])
        reload()
    }
    required init?(coder: NSCoder) { fatalError("Use init(manager:mode:labelWidth:width:)") }

    private static func button(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded; Typography.apply(.body, to: button)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.Size.control).isActive = true
        return button
    }

    /// Shows what the manager has saved, drops any unsaved draft and clears the status line. Delivers nothing.
    func reload() {
        guard let manager else { return }
        fill(manager.settings)
        setStatus(manager.lastError.map { "Error: " + $0.localizedDescription } ?? (mode == .live ? Self.idleLiveStatus : Self.idleSheetStatus),
                  isError: manager.lastError != nil)
    }

    private func setStatus(_ text: String, isError: Bool) {
        let changed = statusField.stringValue != text
        statusField.stringValue = text
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
            for (segment, entry) in Self.modifierSegments.enumerated() { row.modifiers.setSelected(binding.modifiers.contains(entry.0), forSegment: segment) }
            row.modifiers.isEnabled = index > 0
        }
    }

    func draft() -> GlobalHotkeySettings {
        var settings = GlobalHotkeySettings(); settings.enabled = enabledCheckbox.state == .on
        for action in GlobalHotkeyAction.allCases {
            guard let row = rows[action], row.key.indexOfSelectedItem > 0 else { settings[action] = .none; continue }
            var modifiers: GlobalHotkeyModifiers = []
            for (segment, entry) in Self.modifierSegments.enumerated() where row.modifiers.isSelected(forSegment: segment) { modifiers.insert(entry.0) }
            settings[action] = .init(keyCode: GlobalHotkeyKeys.choices[row.key.indexOfSelectedItem - 1].code, modifiers: modifiers)
        }
        return settings
    }

    /// Live mode: apply the draft now. A rejected draft stays on screen beside its error.
    private func commit() {
        guard mode == .live, let manager else { return }
        do { try manager.apply(draft()); setStatus(Self.idleLiveStatus, isError: false) }
        catch { setStatus("Error: " + error.localizedDescription, isError: true) }
    }

    @objc private func enabledChanged(_ sender: NSButton) { commit() }
    @objc private func keyChanged(_ sender: NSPopUpButton) {
        guard let row = rows.values.first(where: { $0.key === sender }) else { return }
        row.modifiers.isEnabled = sender.indexOfSelectedItem > 0
        if !row.modifiers.isEnabled { for segment in Self.modifierSegments.indices { row.modifiers.setSelected(false, forSegment: segment) } }
        commit()
    }
    @objc private func modifiersChanged(_ sender: NSSegmentedControl) { commit() }
    @objc private func reset(_ sender: Any?) {
        fill(.defaults)
        if mode == .live { commit() } else { setStatus("Defaults restored in this panel. Select Save to apply them.", isError: false) }
    }
    @objc private func disable(_ sender: Any?) {
        enabledCheckbox.state = .off
        if mode == .live { commit() } else { setStatus("All global shortcuts will be disabled when you select Save. Your key choices are kept.", isError: false) }
    }
    @objc private func save(_ sender: Any?) {
        guard let manager else { return }
        do { try manager.apply(draft()); onFinish?() }
        catch { setStatus("Error: " + error.localizedDescription, isError: true) }
    }
    @objc private func cancel(_ sender: Any?) { onFinish?() }
}

@MainActor
private final class GlobalHotkeyDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class GlobalHotkeySettingsPanel: NSWindowController, NSWindowDelegate {
    static let width: CGFloat = 760, margin = DesignTokens.Space.s5
    private weak var manager: GlobalHotkeyManager?
    private var form: GlobalHotkeyForm?
    private var stack: NSStackView?

    init(manager: GlobalHotkeyManager) {
        self.manager = manager
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 600),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Global Capture Shortcuts"
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: Self.width, height: 440)
        super.init(window: panel)
        panel.delegate = self
        buildContent(panel, manager: manager)
    }
    required init?(coder: NSCoder) { nil }

    private func label(_ text: String, heading: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = DesignTokens.Typography.font(heading ? .title : .body)
        return label
    }
    private func buildContent(_ panel: NSPanel, manager: GlobalHotkeyManager) {
        let content = NSView(); panel.contentView = content
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        let document = GlobalHotkeyDocumentView(); scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = DesignTokens.Space.s4
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Self.margin),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -Self.margin),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: Self.margin),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -Self.margin)
        ])
        self.stack = stack
        let contentWidth = Self.width - 2 * Self.margin
        let heading = label("Global Capture Shortcuts", heading: true)
        let introduction = label("Choose Command or Control with a key. None disables an action. Key names refer to physical US keyboard positions.")
        let labelWidth = Self.labelWidth()
        let form = GlobalHotkeyForm(manager: manager, mode: .sheet, labelWidth: labelWidth, width: contentWidth)
        form.onFinish = { [weak self] in self?.dismiss() }
        self.form = form
        let defaults = label("All actions start at None. Original Frame used Command + Shift + 7, but that shortcut may already belong to macOS or another app. Configure and save only the shortcuts you want.")
        for view in [heading, introduction, form, defaults] { stack.addArrangedSubview(view) }
        for view in [introduction, defaults] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        AppToolTip.install(on: content)
    }
    /// The widest row label, so the sheet's label column fits every action name on one line.
    static func labelWidth() -> CGFloat {
        let font = GlobalHotkeyForm.labelFont()
        return ceil(GlobalHotkeyForm.labelTexts().map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
    }
    func present(attachedTo parent: NSWindow?) {
        guard let window else { return }
        if window.isVisible { window.makeKeyAndOrderFront(nil); return }
        form?.reload()
        fitToContent(visibleHeight: (parent?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800)
        if let parent, parent.attachedSheet == nil { parent.beginSheet(window) }
        else { window.center(); showWindow(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    /// The sheet is as tall as its form (so Save is always in view), or as tall as the screen allows and then scrolls.
    private func fitToContent(visibleHeight: CGFloat) {
        guard let window, let stack else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let wanted = stack.fittingSize.height + 2 * Self.margin
        window.setContentSize(NSSize(width: Self.width, height: min(wanted, max(440, visibleHeight - 120))))
    }
    private func dismiss() {
        guard let window else { return }
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.orderOut(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }
}
