import AppKit

extension AppDelegate {
    /// The main window's Tab order: the top bar left to right, the canvas, then the bottom bar left to right.
    /// AppKit recalculates it from the controls' positions, which already runs in that order now the right rail is gone, so only the
    /// two popovers (Size, Color) set `nextKeyView` by hand. The canvas is where the keyboard starts.
    ///
    /// Tab moves the keyboard through that loop from the canvas as it does from any control, and Shift-Tab goes back, so the canvas is never a
    /// trap. The old "Tab = Pen" swap between the current tool and the pencil is Control-Tab now (the hint bar says so): where Tab moves focus,
    /// Control-Tab is the key that does what Tab would otherwise have done, as in a text field. The one exception is a window whose bars are
    /// not tab stops (Full Keyboard Access off, System Settings > Keyboard > Keyboard navigation, and no Focus Toolbar): Tab has nowhere to go
    /// there, so it keeps the swap. The Focus Toolbar command (Window menu, Option-Command-T) does not need the setting: it puts the keyboard
    /// on the first top-bar control and lets the bars take Tab for as long as the window stays key.
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
