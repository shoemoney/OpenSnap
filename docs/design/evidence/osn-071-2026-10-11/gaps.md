# OSN-071 gaps: coverage-matrix surfaces and modes NOT captured

Source `4254505`. Everything here is a surface or mode with no capture in `REVIEW.md`, each with the concrete reason. A row of `docs/design/e2e/coverage-matrix.md` that is not listed here has at least one harness capture (its `rendered` surface ids or the S50 to S60 glass surfaces) in both light and dark. Gap categories follow the matrix (`permission`, `hardware`, `OS-owned`, `harness`, `unsafe`) plus `behaviour` for rows that are not visual states.

## Surface gaps from the harness (manifest `gaps`, every pack)

| Surface / row | Modes missed | Reason | Category |
|---|---|---|---|
| S22 Photo browser (E2E-SHEET-021 to 025 partly) | light, dark, all widths | `PhotoBrowserCoordinator` reads the real Photos library and Desktop (Photos TCC prompt, private pictures); there is no synthetic content seam, so it is deliberately never opened. E2E-SHEET-023 (Photos Library) is `photos-library` | permission / unsafe |
| S26 Wipe confirmation | light, dark | No Wipe confirmation exists: `Canvas.wipe` acts immediately, so there is nothing to render. Recorded as a finding, not a defect of the capture | n/a (does not exist) |
| S29 native tooltips / help tags | light, dark | AppKit tooltips are drawn by the window server on a real pointer hover and cannot be forced; the app-owned tooltip plate (S38) and help bevel (S29) are captured instead | harness |
| S29 Share with macOS picker (E2E-SHEET-052) | light, dark | `NSSharingServicePicker` runs out of process and lists the owner's real services and accounts | OS-owned |
| S10 Export save panel, Increase Contrast light | Increase Contrast light (`increase-contrast` pack) | The modal save panel returned before a window could be captured (out of process). Captured in every other mode: the export accessory alone in all, and the panel itself in default and Reduce Transparency | OS-owned / harness |
| S23 menu bar menus (E2E-MENU-*) | menu windows, all modes | Menu windows are absent from own-window composites; menus are covered as text (`menus.json` in the raw run) and by the two open-menu captures (Toolbox, canvas text context menu) | harness |

## Coverage-matrix rows with no capture

| Rows | Reason | Category |
|---|---|---|
| E2E-CAP-003 Fullscreen snapshot, E2E-BAR-005 Snap right-click (partial) | Needs live Screen Recording permission and a real display grab; the picker (S13) is captured with the "no recording grant" lens only and a synthetic lens | permission |
| E2E-CAP-010 multi-display, E2E-CAP-011 1x display | Needs a second display or a 1x panel; the harness renders at the host scale (2x) on one display | hardware |
| E2E-HOT-035 to 040 hotkeys firing while backgrounded | Needs the global hotkey to fire from another app, i.e. physical HID input; the Capture tab and key panel are captured (S17, S60) | hardware |
| E2E-SHEET-048 Open panel, 049 Save panel, 050 Page Setup, E2E-SHEET-022 Choose image folder, E2E-MENU-077 Spelling panel | OS-owned panels (NSOpenPanel and friends); the app-owned accessory is captured (S10) | OS-owned |
| E2E-SHEET-051 Print panel | Needs a real printer destination | hardware |
| E2E-A11Y-006 VoiceOver speech | Needs spoken VoiceOver; AX trees are in the raw runs but are not committed | hardware |
| E2E-MENU-066 to 076, 078, 079 (Hide Others, Show All, Bring All to Front, Pencil Smoothing, Arrow Head, Spelling items) | Menu bar items with no visual state of their own: menu windows are not captured (see S23); their effect on drawing is covered by the populated editor captures | harness |
| E2E-ICON-102 OpenSnap.icon (Dock/Finder rendering) | The harness captures only the app's own windows; the app icon is built and previewed with `ictool` (see the icon-composer notes), not by this run | harness |
| E2E-SET-024 persisted settings across relaunch, E2E-CAP-009 Snap from Link, E2E-DEST-031 to 037 upload journeys (success, failure, retry, cancel, Delete from Web, Test connection) as flows | Behaviours across time or network; the harness stubs the uploader and runs offline (sandbox denies network). The publish progress, success and error states and the busy and empty upload panels are captured (S21, S52, S58) | behaviour / unsafe |
| E2E-HIST-042, E2E-ALERT-006, E2E-SET-023, E2E-HOT-044, E2E-KEY-036 to 038, E2E-A11Y-001 to 005 and 007 | Keyboard behaviours (Return, Space, arrows, Escape, Command-D, Command-W, focus order); no pixels change. Resulting states (focus rings S28, glass hover/focus/dismissed variants S50 to S60) are captured | behaviour |

Panels formerly listed without a render are now covered by the glass surfaces: Toolbox (S50), Zoom (S51), Upload destinations (S52), Colour (S53), Size (S54), History date and drag-as (S55), Resize presets and anchor (S57), Destination protocol and source (S58), Capture key and modifiers (S60).

## Mode gaps

| Mode | Not captured | Reason |
|---|---|---|
| Reduce Transparency, Increase Contrast | main-editor windows other than 980 and 1280 (1024, 1440, full screen); S13 to S15 overlays, S21 publish states, S22, S23, S29, layout and pairs groups | Run to a bounded set (see REVIEW.md) to keep the repo small; the harness supports them and a rerun with `--display` adds them. Not a harness limit |
| Differentiate Without Color, Reduce Motion | all surfaces | Harness supports them (`--display`) but acceptance asked only for Reduce Transparency and Increase Contrast. Combined Increase Contrast plus Reduce Motion is in `S14 countdown-3-contrast-reduce-motion` |
| Increase Contrast + Reduce Transparency together | all | Not run as a pair here; each alone is. The pair exists in the older `m4-glass` pack |
| Font Awesome Pro icon mode | all | No Pro subset fonts in this build (Pro is opt-in with the owner's token and is not bundled or committed). Default mode, bundled Free vectors, is what is captured |
| Large widths beyond the visible frame | 1440 and full screen (2056 pt on this host) only; no 2560-wide or multi-display capture | Host display is 2056 x 1197 pt; wider needs another display (hardware) |
| Real system light/dark switch and real Reduce Transparency / Increase Contrast | all | System appearance and accessibility settings cannot be changed without touching global settings; the harness injects them inside its throwaway copy (rendered, not real) |
| Screen Recording backed content | picker lens, countdown over real desktop, flash over real desktop | Needs live Screen Recording permission; overlays are rendered in their own windows only |
| Welcome / first launch (S27) | all | The welcome document was removed; no surface exists |
| Actual Size at widths other than the S07 capture, text editing at 1024 and 1440 | those widths | Captured at 980 and 1280 (S36, S05, S07); other widths follow the same layout (width budget is captured in the layout group) |
