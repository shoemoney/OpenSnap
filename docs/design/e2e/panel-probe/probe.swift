// Panel probe: opens one system panel configured like OpenSnap's, cancels itself, reports. Usage: probe MODE [SECONDS]
import AppKit
import UniformTypeIdentifiers

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "open-basic"
let seconds = Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "") ?? 5
let doc = UTType(exportedAs: "com.shoemoney.opensnap.document", conformingTo: .data)

func accessory() -> NSView {  // same structure as ExportAccessory: 600 wide, heading, format popup row, labels, checkbox
    let label = { (t: String) -> NSTextField in NSTextField(wrappingLabelWithString: t) }
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    popup.addItems(withTitles: ["PNG", "JPG", "PDF", "TIFF", "SVG"])
    let row = NSStackView(views: [NSTextField(labelWithString: "Format"), popup]); row.spacing = 20
    let bytes = label("Encoded size: Not available")
    let stack = NSStackView(views: [label("Export options"), row, label("JPG quality 70 %"),
        NSButton(checkboxWithTitle: "Export at original size", target: nil, action: nil), label("Dimensions: Not available"), bytes])
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
    content.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
        stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        bytes.widthAnchor.constraint(equalTo: stack.widthAnchor), bytes.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)])
    content.setFrameSize(NSSize(width: 600, height: stack.fittingSize.height + 40))
    stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20).isActive = true
    return content
}

func makePanel(_ mode: String) -> NSSavePanel {
    switch mode {
    case "open-basic": return NSOpenPanel()
    case "open-opensnap":  // App.swift openFile
        let p = NSOpenPanel(); p.allowedContentTypes = [.image, .pdf, doc]; p.allowsMultipleSelection = false; return p
    case "save-basic": return NSSavePanel()
    case "save-opensnap":  // App.swift save
        let p = NSSavePanel(); p.nameFieldStringValue = "Untitled.opensnap"; p.allowedContentTypes = [doc]; return p
    case "export-opensnap":  // App.swift exportFile
        let p = NSSavePanel(); p.title = "Export"; p.nameFieldLabel = "Export As:"; p.prompt = "Export"
        p.accessoryView = accessory(); p.allowsOtherFileTypes = false
        p.allowedContentTypes = [UTType(filenameExtension: "png") ?? .data]; p.nameFieldStringValue = "Untitled.png"; return p
    default: fputs("unknown mode \(mode)\n", stderr); exit(2)
    }
}

final class Probe: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "panelprobe"; window.makeKeyAndOrderFront(nil); NSApp.activate()
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds * 4 + 6) { print("FAILSAFE auto-cancel did not return"); exit(3) }
        let modes = mode == "sequence" ? ["export-opensnap", "open-opensnap", "save-opensnap", "save-basic"] : [mode]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for m in modes {  // each runModal returns on its own cancel timer (or a harness Esc), then the next panel opens
                let p = makePanel(m); let start = Date()
                let cancel = Timer(timeInterval: seconds, repeats: false) { _ in p.cancel(nil) }
                let abort = Timer(timeInterval: seconds + 2, repeats: false) { _ in NSApp.abortModal() }
                RunLoop.main.add(cancel, forMode: .common); RunLoop.main.add(abort, forMode: .common)
                let response = p.runModal(); cancel.invalidate(); abort.invalidate()
                print("mode=\(m) response=\(response.rawValue) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(start)))s")
            }
            exit(0)
        }
    }
}
let app = NSApplication.shared; app.setActivationPolicy(.regular)
let delegate = Probe(); app.delegate = delegate; app.run()
