# OSN-051 Settings window: captures at 4da64be

Run: `sh tools/eye-dump-audit.sh <out> --surfaces S17,S18 --appearances light,dark --icons sf --no-wait-gui --sha 4da64be`.
36 captures, 0 gaps, real stores unchanged. The window is built straight from `SettingsWindow.swift`
(App.swift is not wired yet), at the screen's own size and again "as sized for a 1280 x 800 screen" (706 pt visible).

| File stem | What it shows |
|---|---|
| `S17-settings-general-{light,dark}` | General tab, defaults: Show in (Dock / Menu bar / Both), Snapping checkbox wrapped to two lines, Hints group. 640 x 296. |
| `S17-settings-general-alt-*` | Same with Menu bar, snap off, both hint options on. |
| `S17-settings-drawing-*`, `-alt-*` | Drawing tab: precision and arrow head radios, 18 pt caption "Holding Option reverses the setting." 640 x 237. |
| `S17-settings-capture-*` | Capture tab: flash checkbox, then the embedded shortcut rows in the same label column, status line, Reset Defaults and Disable All. 640 x 604. |
| `S17-settings-capture-error-*` | A key chosen with no Command or Control: the red "Error:" line wraps to three lines and the window grows to 652 to hold it. |
| `S17-settings-upload-*` | Upload tab: three saved destinations (name over transport, Default pill), Manage Destinations button. 640 x 395. |
| `S17-settings-upload-empty-*` | Upload tab with nothing saved. 640 x 281. |
| `*-1280x800-*` | The same states sized for a 1280 x 800 screen; every tab fits (largest 652 of 706). |
| `S18-hotkeys-sheet-*` | The Capture Shortcuts sheet, now the same form (760 wide, as tall as its form so Save is in view). |
| `S18-hotkeys-sheet-in-context-*` | That sheet over the editor. |

Not visible in a capture: toolbar tab labels are drawn by AppKit at the system's size (about 13 pt), not 20 pt.
