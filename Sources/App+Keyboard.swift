import AppKit

extension AppDelegate {
    /// The main window's Tab order: the top bar left to right, the canvas, then the bottom bar left to right.
    /// AppKit recalculates it from the controls' positions, which already runs in that order now the right rail is gone, so only the
    /// two popovers (Size, Color) set `nextKeyView` by hand. The canvas is where the keyboard starts.
    ///
    /// The canvas keeps Tab for itself: on the canvas Tab swaps between the current tool and the pencil (the hint bar says "tab = Pen").
    /// Control-Tab and Control-Shift-Tab are the way out of it, forward and back, as in a text view. Everything else is reached by
    /// Tab once Full Keyboard Access is on (System Settings > Keyboard > Keyboard navigation), which is also the setting AppKit
    /// applies to every button. The Focus Toolbar command (Window menu, Option-Command-T) does not need it: it puts the keyboard on
    /// the first top-bar control and lets the bars take Tab for as long as the window stays key.
    func configureKeyViewLoop() {
        window.autorecalculatesKeyViewLoop = true
        window.initialFirstResponder = canvas
    }

    /// Window > Focus Toolbar: the keyboard goes to the first control of the top bar (Hide), from where Tab walks the bar.
    @objc func focusToolbar() {
        guard !terminationStarted, window.isVisible, window.attachedSheet == nil,
              let chrome = modernChrome as? ModernEditorChrome else { return }
        window.makeKeyAndOrderFront(nil)
        // Asking for the toolbar is asking for the keyboard on the bars: they take Tab as they would with Full Keyboard Access on,
        // until the window stops being key.
        KeyboardNavigation.toolbarFocusActive = true
        window.makeFirstResponder(chrome.firstToolbarControl)
    }
}
