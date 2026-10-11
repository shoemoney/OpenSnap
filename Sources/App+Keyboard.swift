import AppKit

extension AppDelegate {
    /// The main window's Tab order: the top bar left to right, the canvas, then the bottom bar left to right.
    /// AppKit recalculates it from the controls' positions, which already runs in that order now the right rail is gone, so only the
    /// two floating glass panels (Size, Color), each a window of its own, set `nextKeyView` by hand. The canvas is where the keyboard starts.
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

    /// Command-1 to Command-4 are Capture's shortcuts and also Settings' tab shortcuts. While Settings is the key window a key press
    /// belongs to its tabs: the menu item must not claim it (a menu that maps the chord itself, as a driver does, would start a capture
    /// instead of switching the tab). Choosing the item with the pointer is unaffected: only a key event is refused.
    static func settingsOwnsKeyEquivalent(of item: NSMenuItem, event: NSEvent?, keyWindow: NSWindow?, settingsWindow: NSWindow?) -> Bool {
        guard let settingsWindow, keyWindow === settingsWindow, event?.type == .keyDown,
              item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command,
              let number = Int(item.keyEquivalent), (1...4).contains(number) else { return false }
        return true
    }
}
