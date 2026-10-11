# Glass choices across OpenSnap — implementation plan and record

Integration branch `impl/glass-pickers-20261010` (worktree `.todo-worktrees/glass-pickers-integration`), base `57ec799`.
Requested by Jeremy, 2026-10-10 23:03 CDT. Root owns `QUEUE.md`, `docs/design/audit-overview.html`,
`docs/design/glass-pickers-gallery.html`, `docs/design/e2e/glass-pickers-root-verification.md` and
`docs/design/evidence/glass-pickers-2026-10-10/`; nothing on this branch touches them.

## Goal

Every app-owned choice in the four named areas is a recognizable Liquid Glass button: one glass plate per related group, per-button
state fills drawn by `StatePlate` / `StateStyles` (never glass inside glass), a selected state that is a fill, a border, a weight and
a glyph (never colour alone), 20 pt text (18 pt floor), semantic Font Awesome glyphs, and keyboard, VoiceOver and focus behaviour at
least as good as the native control it replaces.

## Choice inventory and disposition

| Area | Choice | Today | After |
| --- | --- | --- | --- |
| 1 Editor | Top/bottom bar commands, tools, Snap | glass plates + `CommandButton` | unchanged; consistency pass only |
| 1 History | Action groups | glass plates + `CommandButton` | unchanged; consistency pass only |
| 1 History | "Drag as" format pop-up | native `NSPopUpButton` menu | glass pop-up face, choices in a `MenuChoicePanel` |
| 1 History | Grid right-click menu | native contextual menu | **kept native** (contextual menu, not a picker) |
| 2 Toolbox | 18 commands in 5 groups (copied main-menu items) | native `NSMenu` rows | `MenuChoicePanel`: 5 group plates, rows with icon, title, shortcut, toggle state |
| 2 Zoom | 25–200 %, computed Fit/Frame row (tag 999), Actual Size (tag 998) | native pop-up menu | `MenuChoicePanel` from the pop-up's own menu, options + Actual Size toggle |
| 2 Upload | Cancel Upload (busy), destinations (default checked), "No destination configured" (disabled), Destination Settings…, Share with macOS… | native menu on right-click / Control-click / AX ShowMenu | `MenuChoicePanel` via `OriginalActionButton.menuPresenter`; rebuilt on every open |
| 3 Color | 10 preset swatches, Custom color… | solid content in `NSPopover` | `GlassPanelHost`: swatch plate + Custom color plate |
| 3 Size | track + readout, 5 presets | solid content in `NSPopover` | `GlassPanelHost`: track plate + preset plate |
| 4 Settings | tab strip (4) | app-owned solid strip | one glass plate, `StatePlate` fills |
| 4 Settings | Presence (3), Precision (3), Arrow head (2) radios | native radios | `GlassChoiceGroup` (radio role, circle / circle-check glyph) |
| 4 Settings | hover hints, keyboard tips, include app, capture flash | native checkboxes | `GlassChoiceButton` toggles (checkbox role, square / filled square-check glyph) |
| 4 Settings | Add…, Edit…, Remove, Make Default, empty-state Add… | native push buttons | titled `CommandButton`s on one action plate |
| 4 Settings | destination list, shortcut recorders | content list / form fields | **kept solid / native** (readable content) |
| 4 Resize | Resize / Crop / Limit | `NSSegmentedControl` | `GlassChoiceGroup` |
| 4 Resize | Lock proportions | native checkbox | `GlassChoiceButton` toggle |
| 4 Resize | Limit by | native pop-up | `GlassChoiceGroup` |
| 4 Resize | anchor 3 × 3 grid | app-owned view | on one glass plate, cells use `StateStyles.command` fills |
| 4 Resize | Preset | native pop-up | glass pop-up face, choices in a `MenuChoicePanel` |
| 4 Resize | Manage disclosure | native disclosure | `GlassChoiceButton` toggle with chevron |
| 4 Resize | Add Preset, Save Preset, Remove; Cancel, Apply, OK | native push buttons | titled `CommandButton`s, one plate per group; OK primary, Return default, Escape cancel |
| 4 Resize | width, height, limit, preset name | text fields | **kept native** (form fields) |
| OS-owned | menu bar, Font panel, Color panel, Save/Open/Export/Print panels, share picker, context menus | native | **kept native** |

## Shared primitive contract (`Sources/GlassChoices.swift`, plus additive changes in `GlassChrome.swift`)

- `GlassSurfaceView(views:shape:accessibility:spacing:axis:)` — `axis` defaults to `.horizontal` (today's bar plate, unchanged);
  `.vertical` stacks full-width rows and takes its height from its content. `GlassChrome.plate(_:identifier:accessibility:axis:)`.
- `GlassChoiceButton: CommandButton` — `kind` `.command | .option | .toggle | .submenu`; `indicator` `.none | .check | .checkbox | .radio | .chevron`;
  `isChosen`; visible 20 pt title (bodyStrong while chosen), optional leading image or `FAIcon`, optional trailing shortcut text,
  `layout` `.row` (full width) or `.segment` (centred). Accessibility role follows `kind`
  (button / radio button / checkbox / menu button) with value 0/1. Disabled rows use the `StateStyles` disabled alpha and never take focus.
- `GlassChoiceGroup` — an inline exclusive set of `.option` buttons on one plate: `selectedIndex` (assignment sends nothing),
  target/action on user change, radio-group accessibility, arrow keys move the choice, one tab stop.
- `GlassPanelHost` — the floating, transparent, borderless child panel that holds ONE `NSGlassEffectContainerView` with the group plates.
  `show(relativeTo:of:preferredEdge:makeKey:)`, `close()`, `isShown`, `willClose` / `didClose`; frame placement is a pure, testable
  function (preferred edge, flips when there is no room, clamps to the visible screen, caps height and scrolls); transient dismissal
  (Escape, click outside, app deactivation, parent window closing, miniaturising, entering full screen or presenting a sheet, anchor
  leaving its window); a click on the anchor while open only closes; focus returns to the responder that had it; only one host is shown
  at a time (`GlassPanelHost.current`); `presenter` seam for tests.
- `MenuChoicePanel` — builds a `GlassPanelHost` from an `NSMenu`, which stays the source of truth: runs `menuNeedsUpdate` /
  `menuWillOpen` and `update()` (validation, dynamic titles, state) on each open; separators split group plates; hidden items are skipped;
  disabled items show disabled; `submenu` rows drill in with a Back row; activation closes first, then performs the item through the
  menu (`performActionForItem`) or, for a pop-up's plain item, selects it in the pop-up and sends the pop-up's action; Up/Down/Tab move,
  Home/End, Return/Space/Enter choose, Right/Left enter/leave a submenu, Escape closes (or leaves a submenu); keyboard opens focus the
  chosen row, else the first enabled one.

## Milestones and ownership

| Milestone | Owner (worktree / branch) | Files owned |
| --- | --- | --- |
| M1 shared primitives | P — `.todo-worktrees/gp-primitives` / `impl/gp-primitives` | `Sources/GlassChoices.swift` (new), `Sources/GlassChrome.swift`, `Sources/FontAwesomeIcons.swift`, `Sources/FontAwesomeFree.swift`, `Sources/ChromeIcons.swift`, `tests/GlassChoicesTests.swift` (new), `tools/test.py` suite lists, `tools/fetch-fontawesome.sh` glyph list, icon tests |
| M2 Toolbox / Zoom / Upload | A — `gp-menus` / `impl/gp-menus` | `Sources/ModernEditorChrome.swift`, `Sources/App+ModernChrome.swift`, `Sources/App.swift` Toolbox hunk (`bezelToolbox`) and Upload hunk (`configureWebpostButton` … `setDefaultDestination`), `Sources/App+Upload.swift`, their tests in `tests/GlassChromeTests.swift`, `tests/AppSafetyModernCases.swift`, `tests/AppSafetyWebpostCases.swift`, `tests/AppSafetyMenuCases.swift` |
| M3 Color / Size | B — `gp-color-size` / `impl/gp-color-size` | `Sources/BezelDrawingControls.swift`, `Sources/App.swift` Color hunk (`syncDrawingControls` … `releaseCustomColorPanel`, the `colorPopover` declaration), `Sources/App+Keyboard.swift`, Color/Size tests (`tests/AppSafetyTests.swift` Color/Size cases, `tests/GlassChromeTests.swift` Size cases only) |
| M4 Settings | C — `gp-settings` / `impl/gp-settings` | `Sources/SettingsWindow.swift`, `tests/SettingsWindowTests.swift`, Settings cases in `tests/ViewTreeAuditTests.swift`, `tests/AccessibilityAuditTests.swift`, `tests/AppSafetyWindowChromeCases.swift` |
| M5 Resize + History format | D — `gp-resize` / `impl/gp-resize` | `Sources/ResizePanel.swift`, `Sources/HistoryBrowser.swift` (format pop-up only), `tests/ResizePanelTests.swift`, `tests/ResizePanelLayoutTests.swift`, `tests/HistoryBrowserTests.swift`, Resize/History cases in the audit suites |
| M6 audit harness captures | E — `gp-harness` / `impl/gp-harness` | `Sources/EyeDumpAudit*.swift`, `tools/eye-dump-audit*.{sh,py}`, `tools/check-eye-dump.py`, `tools/test-eye-dump-audit-guard.py`, `tools/e2e-inventory.py` |
| M7 integration, full suite, Opus review, fixes | orchestrator | merges into the integration branch |
| M8 docs reconciliation | Haiku docs worker | this file, `README.md` / `HANDOFF.md` / `docs/design/technical-spec.md` mentions of native menus and popovers |

Shared-file rule: two workers touching the same file stay in their named hunks. Nobody reverts or reformats another worker's lines.

## Acceptance checklist

- [ ] Toolbox, Zoom, Upload, History format and Resize preset open app-owned glass panels; no `NSMenu.popUp` / `popUpContextMenu` remains on those paths.
- [ ] One `NSGlassEffectContainerView` per panel, one plate per menu group; no `NSGlassEffectView` inside another.
- [ ] Selected/on state = accent fill + border + bodyStrong + glyph; Differentiate Without Color adds the indicator; disabled rows dim and skip focus.
- [ ] Keyboard: open with Return/Space/Down; Up/Down/Tab/Home/End; Return/Space choose; Escape closes; focus returns to the opener.
- [ ] Mouse: hover fills, click chooses, click outside or on the opener closes, a second click on the opener does not reopen.
- [ ] Toolbox validation (enabled/disabled, Fill/Shadow/Font state), long-list scrolling and small-screen height cap.
- [ ] Zoom: percentage choice, computed Fit row, Actual Size toggle state and its refusal path unchanged.
- [ ] Upload: destinations rebuilt on each open, default checked, busy Cancel Upload, empty state disabled, settings/share entries.
- [ ] Color: hover-open does not take key, click pins, preset and custom choice, Shift background path; Size: undo grouping per gesture, presets close, dismissal mid-drag ends the gesture.
- [ ] Settings: radios and toggles unambiguous, tabs keyboardable, window sizing unchanged; Resize: mode/limit/anchor/preset behaviour, validation errors, Return = OK, Escape = Cancel.
- [ ] Text ≥ 18 pt (20 pt normal); only Font Awesome / existing semantic glyphs; no emoji or decorative arrows.
- [ ] Harness: direct captures of every new panel (rest, hover, keyboard focus, chosen, disabled, dismissed + focus restored), light and dark.
- [ ] `python3 tools/test.py` green with no source drift and the real-store guard; red proofs recorded for the key behaviour tests.
- [ ] One adversarial Opus review round; real defects fixed.

## GUI slot protocol (workers)

Compiling is free. Running any AppKit test binary, `tools/test.py`, `tools/test-app-safety.sh`, `tools/eye-dump-audit.sh` or
`tools/e2e-session.sh` needs the single slot: `until mkdir /tmp/opensnap-glass-gui.lock 2>/dev/null; do sleep 20; done` before,
`rmdir /tmp/opensnap-glass-gui.lock` after (also on failure). Never `build/OpenSnap.app` in place; never the real stores.

## Record

(Filled in at integration: candidate branch/head/tree, logs, coverage and limits.)
