import AppKit

extension AuditRun {
    /// App-owned tooltips shown by calling the controller directly (hover is synthetic): the plate over a top-bar tool, the Size
    /// pill and a bottom-bar control, at 980. The plate is a real panel, captured together with the main window.
    func s38() {
        guard loadThenPlace("980xmin", size: CGSize(width: 1000, height: 700), name: "Tooltips", surface: "S38") != nil else { return }
        app.setTool(.brush)
        app.widthControl.doubleValue = 6.75
        app.changeWidth(app.widthControl)
        pump(0.3)
        AppToolTip.setText("Fit, 83%", for: app.zoomControl)
        let tip = AppToolTip.shared
        tip.dismiss()
        tip.reduceMotion = { true }
        tip.dismissesOnWindowChanges = false
        defer { tip.dismissesOnWindowChanges = true }
        let targets: [(slug: String, view: NSView?, state: String)] = [
            ("snap", app.snapButton, "the Snap tooltip below the Snap button; the long sentence wraps at 420 pt"),
            ("size", app.widthControl, "the live Size tooltip below the Size pill (Size 7)"),
            ("zoom", app.zoomControl, "a bottom-bar control: the plate opens above the zoom face because there is no room below"),
        ]
        for (slug, view, state) in targets {
            guard let view, AppToolTip.text(for: view) != nil else { gap("S38", "Tooltip " + slug, "the control has no tooltip text"); continue }
            tip.show(for: view)
            guard let plate = tip.panel, tip.isShown else { gap("S38", "Tooltip " + slug, "the tooltip plate did not appear"); continue }
            let anchor = AppToolTip.anchorRect(of: view, in: window)
            shoot("S38", "tooltip-\(slug)-w980", surface: "App tooltip", state: state, windows: [window, plate],
                  refs: ["AppToolTip.swift|final class AppToolTip"], settle: 0.3,
                  extra: ["tooltipText": tip.shownText ?? "", "tooltipFontPoints": Double(tip.label?.font?.pointSize ?? 0), "tooltipFrame": NSStringFromRect(plate.frame),
                          "controlScreenFrame": NSStringFromRect(anchor), "overlapsControl": plate.frame.intersects(anchor)])
            tip.dismiss()
        }
        AppToolTip.setText(nil, for: app.zoomControl)
        wipeTooltips(tip)
    }

    /// The Wipe button names what it does, not the legacy stage: "Remove annotations" over artwork, "Clear image" over a snap alone,
    /// and a dimmed button that says why ("Nothing to clear") on a blank canvas. The plate opens above the footer button.
    private func wipeTooltips(_ tip: AppToolTip) {
        guard let wipe = app.wipeButton else { gap("S38", "Tooltip wipe", "the Wipe button was not found"); return }
        _ = addAllAnnotationKinds(scale: 1)
        app.updateWipeButton(); pump(0.3)
        func capture(_ slug: String, _ state: String) {
            guard AppToolTip.text(for: wipe) != nil else { gap("S38", "Tooltip " + slug, "the Wipe button has no tooltip text"); return }
            tip.show(for: wipe)
            guard let plate = tip.panel, tip.isShown else { gap("S38", "Tooltip " + slug, "the tooltip plate did not appear"); return }
            shoot("S38", "tooltip-\(slug)-w980", surface: "App tooltip", state: state, windows: [window, plate], refs: ["App.swift|func updateWipeButton", "Canvas.swift|enum WipeStage"], settle: 0.3,
                  extra: ["tooltipText": tip.shownText ?? "", "wipeAccessibilityLabel": wipe.accessibilityLabel() ?? "", "wipeAccessibilityHelp": wipe.accessibilityHelp() ?? "", "wipeEnabled": wipe.isEnabled,
                          "tooltipFontPoints": Double(tip.label?.font?.pointSize ?? 0), "tooltipFrame": NSStringFromRect(plate.frame)])
            tip.dismiss()
        }
        capture("wipe-annotations", "Wipe over artwork: the plate says Remove annotations")
        app.canvas.wipe(); app.updateWipeButton(); pump(0.3)
        capture("wipe-image", "Wipe over a snap alone: the plate says Clear image")
        app.canvas.wipe(); app.updateWipeButton(); pump(0.3)
        capture("wipe-blank", "Wipe on a blank canvas: dimmed, the plate says Nothing to clear")
    }
}
