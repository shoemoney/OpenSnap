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
| 1 Editor | Footer "Original size" (`dragOriginalControl`) | native checkbox beside the status | `GlassChoiceButton` toggle on a footer plate; `DragOriginalSize`, large-shot visibility, status-slot reflow and width budgets unchanged; no glass behind the status text |
| 1 History | Action groups | glass plates + `CommandButton` | unchanged; consistency pass only |
| 1 History | "Drag as" format pop-up | native `NSPopUpButton` menu | glass pop-up face, choices in a `MenuChoicePanel` |
| 1 History | Date filter pop-up (`datePopup`) | native `NSPopUpButton` menu | glass pop-up face, choices in a `MenuChoicePanel` |
| 1 History | Category (All / Shared / Exported / Saved, `categoryControl`) | native segmented control | `GlassChoiceGroup` on one plate |
| 1 History | Search field, thumbnail grid, details | content / form | **kept native** (readable content) |
| 1 History | Grid right-click menu | native contextual menu | **kept native** (contextual menu, not a picker) |
| 2 Toolbox | 18 commands in 5 groups (copied main-menu items) | native `NSMenu` rows | `MenuChoicePanel`: 5 group plates, rows with a Font Awesome Free glyph (`MenuChoiceIcons`), title, shortcut, toggle state; the native menu bar keeps its SF Symbols |
| 2 Zoom | 25–200 %, computed Fit/Frame row (tag 999), Actual Size (tag 998) | native pop-up menu | `MenuChoicePanel` from the pop-up's own menu: percentage options, a computed row that names its mode (`Fit, 83%`), and an Actual Size row (Free magnifying-glass glyph) |
| 2 Upload | Cancel Upload (busy), destinations (default checked), "No destination configured" (disabled), Destination Settings…, Share with macOS… | native menu on right-click / Control-click / AX ShowMenu | `MenuChoicePanel` via `OriginalActionButton.menuPresenter`; rebuilt on every open, and a rebuild closes the old panel |
| 3 Color | 10 preset swatches, Custom color… | solid content in `NSPopover` | `GlassPanelHost`: swatch plate + Custom color plate |
| 3 Size | track + readout, 5 presets | solid content in `NSPopover` | `GlassPanelHost`: track plate + preset plate |
| 4 Settings | tab strip (4) | app-owned solid strip | one glass plate, `StatePlate` fills |
| 4 Settings | Presence (3), Precision (3), Arrow head (2) radios | native radios | `GlassChoiceGroup` (radio role, circle / circle-check glyph) |
| 4 Settings | hover hints, keyboard tips, include app, capture flash | native checkboxes | `GlassChoiceButton` toggles (checkbox role, square / filled square-check glyph) |
| 4 Settings | Add…, Edit…, Remove, Make Default, empty-state Add… | native push buttons | titled `CommandButton`s on one action plate |
| 4 Settings › Capture | "Enable global capture shortcuts" | native checkbox | `GlassChoiceButton` toggle |
| 4 Settings › Capture | per-shortcut key pop-up | native pop-up | `GlassPopUpButton` (long list: scrolls inside the height cap) |
| 4 Settings › Capture | per-shortcut modifiers ⌃⌥⇧⌘ | native multi-select segmented control | four `GlassChoiceButton` toggles on one plate per row |
| 4 Settings › Capture | Clear All | native push button | titled `CommandButton` on an action plate |
| 4 Settings | destination list | content list | **kept solid** (readable content) |
| 4 Settings › Destination sheet | Protocol (`protocolPopup`), key source (`sourcePopup`) | native pop-ups | Glass pop-up faces (`GlassPopUpButton`) with choices in a `MenuChoicePanel`; the Source face reads "AWS profile" or "Keychain" at 560 pt, with the full text kept in the menu, panel, AX and tooltip |
| 4 Settings › Destination sheet | "Make uploads public-read" (`aclCheckbox`) | native checkbox | `GlassChoiceButton` toggle on the related plate; default, visibility and save/test payload unchanged |
| 4 Settings › Destination sheet | Test / Save / Cancel and other sheet buttons | native push buttons | titled `CommandButton`s on one action plate; default/cancel keys kept |
| 4 Settings › Destination sheet | host, user, password, path, URL fields, status text | form fields / status | **kept native** |
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
| M2 Toolbox / Zoom / Upload | A — `gp-menus` / `impl/gp-menus` | `Sources/ModernEditorChrome.swift`, `Sources/App+ModernChrome.swift`, `Sources/App.swift` Toolbox hunk (`bezelToolbox`), the `dragOriginalControl` declaration and Upload hunk (`configureWebpostButton` … `setDefaultDestination`), `Sources/App+Upload.swift`, their tests in `tests/GlassChromeTests.swift`, `tests/AppSafetyModernCases.swift`, `tests/AppSafetyWebpostCases.swift`, `tests/AppSafetyMenuCases.swift` |
| M3 Color / Size | B — `gp-color-size` / `impl/gp-color-size` | `Sources/BezelDrawingControls.swift`, `Sources/App.swift` Color hunk (`syncDrawingControls` … `releaseCustomColorPanel`, the `colorPopover` declaration), `Sources/App+Keyboard.swift`, Color/Size tests (`tests/AppSafetyTests.swift` Color/Size cases, `tests/GlassChromeTests.swift` Size cases only) |
| M4 Settings | C — `gp-settings` / `impl/gp-settings` | `Sources/SettingsWindow.swift`, the `GlobalHotkeyForm` part of `Sources/GlobalHotkeys.swift`, `tests/SettingsWindowTests.swift`, `tests/GlobalHotkeysTests.swift`, the `hotkey-tests` line of `tools/test.py`, Settings cases in `tests/ViewTreeAuditTests.swift`, `tests/AccessibilityAuditTests.swift`, `tests/AppSafetyWindowChromeCases.swift` |
| M5 Resize + History choices | D — `gp-resize` / `impl/gp-resize` | `Sources/ResizePanel.swift`, `Sources/HistoryBrowser.swift` (date filter, category and Drag as choices only), `tests/ResizePanelTests.swift`, `tests/ResizePanelLayoutTests.swift`, `tests/HistoryBrowserTests.swift`, Resize/History cases in the audit suites |
| M5b Destination sheet | F — `gp-destinations` / `impl/gp-destinations` | `Sources/PublishingDestinationsView.swift`, `tests/PublishingDestinationsTests.swift`, destination-sheet cases in the audit suites |
| M6 audit harness captures | E — `gp-harness` / `impl/gp-harness` | `Sources/EyeDumpAudit*.swift`, `tools/eye-dump-audit*.{sh,py}`, `tools/check-eye-dump.py`, `tools/test-eye-dump-audit-guard.py` |
| M6b end-to-end inventory | G — `gp-inventory` / `impl/gp-inventory` (took `tools/e2e-inventory.py` over from E at 00:45) | `tools/e2e-inventory.py`, the generated `docs/design/e2e/inventory.json` and `docs/design/e2e/coverage-matrix.md` (audited reasons and observed cells preserved byte for byte; no new E2E or rendered claims) |
| M7 integration, full suite, Opus review, fixes | orchestrator | merges into the integration branch |
| M8 docs reconciliation | Haiku docs worker | this file, `README.md` / `HANDOFF.md` / `docs/design/technical-spec.md` mentions of native menus and popovers |

Shared-file rule: two workers touching the same file stay in their named hunks. Nobody reverts or reformats another worker's lines.

## Acceptance checklist

Each item carries the kind of proof behind it. The kinds are never merged:

- `[x] unit/source`: a named test in a suite (`tools/test.py`).
- `[x] guarded render`: an eye-dump capture that passed the checker (`tools/check-eye-dump.py`).
- `[x] routing (offscreen)`: synthesized window events through `sendEvent` on non-active or offscreen windows. No real HID input.
- `[x] root native AX/routing`: external window-root accessibility actions and targeted keys in the running isolated app prove parent/child focus and sheet Return/Escape. Physical pointer hover/click and VoiceOver speech remain manual.

- [x] unit/source: Toolbox, Zoom, Upload, History format and Resize preset open app-owned glass panels (`MenuChoicePanel` / `GlassPanelHost`). On those paths no `NSMenu.popUp` or `popUpContextMenu` runs. `OriginalActionButton` keeps its native presenter only as the class default; Upload installs a glass presenter. The remaining `popUp` calls in `Sources/EyeDumpAudit*` are harness triggers.
- [x] unit/source: one `NSGlassEffectContainerView` per panel and one plate per menu group, with no glass view inside another (`GlassChoicesTests`).
- [x] unit/source: selected state is accent fill, border, bodyStrong and glyph; disabled rows dim and skip focus.
- [x] unit/source: the Differentiate Without Color indicator on chosen choices and the current Settings tab (`StateStylesTests`, `SettingsWindowTests` `liveDifferentiateOutline` / `liveDifferentiateRow`). [x] guarded render: combined injected accessibility variants. [ ] manual: the live system setting.
- [x] routing (offscreen): synthesized NSEvents through the window drive Return, Space, Down, arrows and Escape on offscreen sheets and panels; red proofs are recorded for Return and for real-flag arrows.
- [x] root native AX/routing: Return validates default Save in the destination sheet; the first child-window Escape closes its panel and the second cancels the sheet. Keyboard-opened Capture key choices restore opener focus. Evidence retains its actual reviewed SHA.
- [x] routing (offscreen): a synthesized mouseDown/up through `sendEvent` chooses on an ordered, invisible, non-key panel.
- [x] unit/source: hover over Color does not close another open panel.
- [ ] manual: physical pointer hover fill, click, click outside, and a second click on the opener not reopening.
- [x] unit/source: Toolbox validation (`AppSafetyMenuCases`); placement, long-list scrolling and the small-screen height cap (`GlassChoicesTests` scrolling and placement tests).
- [x] unit/source: Zoom percentage choice, computed Fit row (`Fit, 83%`), Actual Size toggle and its refusal path (`AppSafetyModernCases`, `GlassChoicesTests`).
- [x] unit/source: Upload destinations rebuilt on each open, default checked, busy and empty states, choosing persists the default (`webpostChoicesPanel`); a rebuild closes the old panel (`webpostPanelRebuildClosesOld`).
- [x] unit/source: Color hover-opened palette never asks for the keyboard (`AppSafetyTests`, hover cases).
- [x] unit/source: Size undo grouping per gesture and dismissal mid-drag (`AppSafetyModernCases` "The Size pill opens its panel below and every gesture, preset, key and assistive step is exactly one undo step, even when the panel is dismissed mid-drag"; `GlassChromeTests` "A click outside the panel ends the open group", "A preset pick closes the panel"); Color custom row chosen (`AppSafetyModernCases`). [x] routing (offscreen): the first press on a non-key panel starts the track drag and its undo group, chooses a Size preset and applies a hover-opened swatch (`AppSafetyTests`, real mouseDown/up through `sendEvent` on an ordered, invisible, offscreen panel).
- [x] unit/source: History date filter, category and Drag as are glass pop-ups; search and grid stay native (`HistoryBrowserTests`).
- [x] unit/source: destination sheet protocol and key-source picks, the public-read toggle payload and its buttons (`PublishingDestinationsTests`); fields and status stay native.
- [x] unit/source: every destination face reads whole at 560, 640 and 900 pt (laid-out width tests, `cf1f954`); SFTP, WebDAV and FTP/FTPS fit unscrolled at 1280 × 800 (S3 scrolls, as before).
- [x] unit/source: Settings radios and toggles, one Tab stop per radio group and per modifier row (`SettingsWindowTests`); window heights General 301 → 371, Drawing 242 → 282, Capture 601 → 633, Upload 440 → 448 with three destinations, 277 → 285 empty, all fitting the 1280 × 800 check.
- [x] routing (offscreen): real-flag arrows reach the modifier toggles and the Settings tab strip; Escape and Command-W work with Caps Lock on.
- [x] unit/source: Resize mode, limit, anchor, preset behaviour and validation errors (`ResizePanelTests`, `ResizePanelLayoutTests`).
- [x] routing (offscreen): Return reaches the Resize OK default button through `sendEvent`; Return on a focused group does not swallow it.
- [x] root native AX/routing: live Resize Escape cancels and Return invokes OK even with an unchosen mode focused; repeated arrows retain selected-mode focus.
- [x] unit/source: text is 20 pt normal with an 18 pt floor; truncation is measured for button titles, shortcuts and glass pop-up faces. Glyphs are Font Awesome or existing semantic glyphs, with no emoji (`IconCoverageTests`, and the glass-row icon test `menuIconTests` in `GlassChoicesTests`).
- [x] guarded render: the glass surfaces S50–S60, light and dark, with the checker's required rest, hover, keyboard-focus, chosen, disabled (where one exists) and dismissed captures per panel. Each dismissed capture records the panel gone and focus back on the opener. The checker also enforces no nested glass, text ≥ 18 pt, no truncation of measured labels and faces, and panels inside a parent they fit (`88a95e3`, `ccccfe0`, `db2d574`). Hover is driven by `setHovered`, focus by `makeFirstResponder`, Escape by a synthesized key event: app-driven states, not real pointer or keyboard input. Current results are in the root verification report; the old orchestrator gate table is superseded.
- [x] unit/source: `python3 tools/test.py` green with no source drift and the real-store guard on `21b8d68e10543b097cb6a902103e9c56eeb76be5` (current root acceptance below); red proofs are listed in the Record.
- [x] unit/source and routing (offscreen): one adversarial Opus review round at `996f7fa`; 6 confirmed and 2 plausible findings, all fixed. Each finding's proof class is in the Record.

## GUI slot protocol (workers)

Compiling is free. Running any AppKit test binary, `tools/test.py`, `tools/test-app-safety.sh`, `tools/eye-dump-audit.sh` or
`tools/e2e-session.sh` needs the single slot, taken and released in ONE shell command with an owner check (protocol v2, from 23:50 CDT;
the first unowned `mkdir`/`rmdir` recipe let one worker remove another's lock):

```sh
until mkdir /tmp/opensnap-glass-gui.lock 2>/dev/null; do sleep 20; done; echo "<worker>-$$" > /tmp/opensnap-glass-gui.lock/owner
# ... run ...
[ "$(cat /tmp/opensnap-glass-gui.lock/owner 2>/dev/null)" = "<worker>-$$" ] && rm -rf /tmp/opensnap-glass-gui.lock
```

Never remove a lock you did not create. Worker runs made before v2 may have overlapped and are not acceptance evidence. Current gates use owner-checked
serial integration and candidate runs, including root's internally serialized native suites. Never `build/OpenSnap.app` in place; never the real stores.

## Record

### Superseded orchestrator source

- Tested source: `fa3ddf7` (tree `7db217a`), the merge of P `ad2cf6c` into `impl/glass-pickers-20261010`, base `57ec799`.
- This table records the earlier orchestrator integration runs. Current acceptance uses the root final runs below. Worker-level AppKit runs before GUI slot protocol v2 may have overlapped and are not evidence.

### Superseded orchestrator gates

<!-- FINAL GATES: filled by orchestrator -->

| Gate | Result |
| --- | --- |
| `python3 tools/test.py` on `fa3ddf7` (tree `7db217a`), serialized, no other native process | exit 0: 52 suites; app-safety 275/275; "All suites passed on arm64 with no source drift"; real-store guard unchanged (122 files, 2 defaults plists); clean worktree; only the FA Pro glyph branch skipped ("FA not bundled") |
| Eye-dump captures and checker on `fa3ddf7` | glass S50–S60, light and dark, icons sf (no Pro subsets; embedded FA Free before SF): 206 PNGs, checker 0 failures, 0 advisories, 6 contrast samples skipped, input fence keyboard 0 / buttons 0 / pointer 0. Baseline set S06, S08, S09, S17, S19, S20, S23, S30, S31, light and dark: 180 PNGs, checker 0 failures, 0 advisories, 14 skipped, input fence keyboard 0 / buttons 0 / pointer 69 (a parked cursor during native menu tracking or the Save panel; no product input). Real stores unchanged in both (digest `dbde037ac2085108`). Orchestrator visual review: no objection. Root reviews the images independently and owns the evidence pack. |

### Worker branches and commits

| Area | Branch | Worker commits |
| --- | --- | --- |
| P primitives | `impl/gp-primitives` | `048d37a` API; `ad2cf6c` Font Awesome glyphs on glass menu rows (`MenuChoiceIcons`, 10 new Free 7.3.1 vectors, E2E-ICON-116..125); `e2d6223`, `0fb7786` single flip for toggles; `a3e7d69` `GlassPopUpButton`; `1ab00bd` tests; `b2d9650` label sizing; `996cae2` face metrics and option-only initial focus; `6974b9a` accessibility walker judges glass groups; `c4f92eb` review fixes; `ab3bb20` parent-window containment |
| A menus | `impl/gp-menus` | `5c72d35`, `658d95f` Toolbox, Zoom and Upload panels, Original size toggle; `18e0027`, `9bf2b99` F-J7-006 restored at the 980 pt floor, Zoom computed row names its mode; `da8641a` Focus Toolbar survives a keyboard-opened panel, Upload rebuild closes the old panel |
| B color and size | `impl/gp-color-size` | `e558cd8` Color and Size glass panels; `8d9bfa2` facade removed; `48115fd` first press on a non-key panel, hover keeps other panels, default-glass contrast restored |
| C settings | `impl/gp-settings` | `c220ea9` Settings and Capture tab; `cd426be` one Tab stop per modifier row, optical centring; `4383889` modifier labels fit; `d27400b` real arrow flags, key panel keeps shortcut editing paused |
| D resize and history | `impl/gp-resize` | `a6995d4` Resize and History choices; `49bafa5` Resize keeps keyboard focus; Return red-proofed through `sendEvent` |
| F destination sheet | `impl/gp-destinations` | `e9aaaad` fit at 1280 × 800, `GlassPopUpButton` faces; `8d5183d` readable faces at 560 pt; `cf1f954` laid-out width tests |
| E harness | `impl/gp-harness` | `88a95e3` S50–S60 glass surfaces and checker rules; `ccccfe0` containment gate; `db2d574` independent fit decision, false fallbacks fail |
| G inventory | `impl/gp-inventory` | `d9225c2`, `f1345db`, `4f42665` UI-changed reset, history, promotion rule |
| Docs (earlier pass) | `impl/gp-docs` | `dcfc752` technical-spec Glass choices section, todo checklist, roadmap |

### Adversarial review round

One adversarial Opus review at `996f7fa`: 6 confirmed and 2 plausible findings, all fixed. Each proof class is stated so the kinds stay separate.

| # | Finding | Owner of the fix | Proof class |
| --- | --- | --- | --- |
| 1 | The first click on a non-key Size panel, or on a hover-opened Color panel, was ignored | B | `routing (offscreen)`: real mouseDown/up through `window.sendEvent` to an ordered, invisible, offscreen non-key panel; red proof recorded |
| 2 | Return on a focused `GlassChoiceGroup` was swallowed, so the Resize sheet's OK never ran | P (fix), D (test) | `routing (offscreen)`: red proof with only P's guard reverted: `FAIL Return reaching the group through sendEvent does not choose the focused segment (mode crop)` |
| 3 | Real arrow events carry `.numericPad` and `.function`; modifier toggles and the Settings tab strip rejected them | C | `routing (offscreen)` with real flags; red proofs recorded |
| 4 | A keyboard-opened panel turned off Window > Focus Toolbar | A | `unit/source`: calls `windowDidResignKey` directly; not a live key handoff |
| 5 | The Settings Capture key panel un-paused global shortcuts | C | `unit/source`: handler order with a presenter stub |
| 6 | An arrow in the Resize mode group dropped focus | D | `routing (offscreen)`: real-flag arrows through `sendEvent` on an offscreen sheet |
| 7 | Type-to-select was lost in glass pop-ups | P | `unit/source` |
| 8 | Hover over Color closed another open panel | B | `unit/source` (app-safety) |

Hardening from the same round: a stale item after a menu rebuild (P); host invalidate and deinit remove the monitor and observers (P); the Upload panel rebuild closes the old panel (A).

### Root-requested corrections

- Scope added during the work: History `datePopup` and `categoryControl`; destination sheet choices and the ACL toggle; footer Original size; Capture-tab enable, key, modifiers and Clear All.
- Secondary routes (right-click, Control-click, `AXShowMenu`, context key, `menu(for:)`) all reach the glass panel. Native menu tracking counted zero.
- Sheet keyboard rule: Return and keypad Enter stay with the default button. Space and Down open a focused face. The first Escape closes the panel before Cancel.
- F-J7-006 restored word for word at the 980 pt floor: toggle 174 → 158 pt (per-instance padding 6 and gap 4), Zoom chevron 27 → 25, slot 177 against 172 needed.
- The Zoom computed row shows its mode in the panel (`Fit, 83%`); the face stays percentage-only.
- Settings windows are taller with 44 pt glass rows: General 301 → 371, Drawing 242 → 282, Capture 601 → 633, Upload 440 → 448 (three destinations), 277 → 285 (empty). The 1280 × 800 fit checks pass.
- The destination sheet fits SFTP, WebDAV and FTP/FTPS unscrolled at 1280 × 800 (SFTP has 2 pt spare). S3 still scrolls.
- Glass menu rows (Toolbox, Zoom Actual Size) draw Font Awesome (`ad2cf6c`). The native menu bar keeps its SF Symbols. Before that fix, the rows copied the `MenuSymbols` SF images: a root-found defect, now fixed.

### Superseded candidates

- `2bdd28e` (tree `572a267`): `tools/test.py` passed (52 suites, app-safety 275/275) and captures passed the checker. Visual review then found panels hanging outside their window (Upload about 270 pt, Size about 55 pt, History Drag as). Superseded by the containment fix (P `ab3bb20`, E `ccccfe0` and `db2d574`). Its captures are superseded developer evidence.
- `9cce74d`: the pre-icon rows still showed copied SF images. Superseded by P `ad2cf6c` (see the icon correction above).

### Inventory totals

Rows in `docs/design/e2e/inventory.json`, by evidence class.

| Snapshot | Rows | E2E | rendered | retired | unit/source | unverified |
| --- | --- | --- | --- | --- | --- | --- |
| Baseline `57ec799` | 597 | 312 | 45 | 27 | 93 | 120 |
| Pre-reset | 616 | 312 | 45 | 27 | 112 | 120 |
| Current | 626 | 234 | 32 | 27 | 122 | 211 |

- Current `unverified` 211 = 120 earlier unverified + 91 converted rows (78 from E2E, 13 from rendered). The 3 rows that were already unverified (E2E-BAR-034, -035, -041) sit inside the 120.
- 94 rows carry `UI changed`, each with its byte-exact `history`.
- 12 intrinsic gaps stay as they were: E2E-BAR-039 (unsafe), E2E-BAR-043 (OS-owned), HOT-019, HOT-024 to HOT-031 and HOT-042 (unsafe).
- A converted row leaves `UI changed` only with new glass evidence: a new SHA, a real path and a reviewer.

### Icon mode

The suites and captures run with the harness's `--icons sf` mode, which strips Font Awesome Pro only. No Pro subsets are bundled. `ChromeIcons.resolve` then draws the embedded Font Awesome Free 7.3.1 vectors (`Sources/FontAwesomeFree.swift`) before any SF Symbol fallback. Chrome glyphs therefore render as Font Awesome Free. Only the Pro branch is skipped ("FA not bundled"). Cite `IconCoverageTests` and the glass-row icon test (`GlassChoicesTests`, `menuIconTests`). The captures do not use SF icons only.

### Known limits

- No physical HID input or VoiceOver speech is verified. Root independently verified live parent/child focus and sheet Return/Escape via external AX actions and targeted window/responder events. See the root report for method and limits.
- Liquid Glass cannot be rendered offscreen. Contrast unit checks measure label ink against the window and canvas colours, with the plate treated as clear. The screenshot harness covers the material.
- Truncation is measured for `GlassChoiceButton` titles and shortcuts, `GlassPopUpButton` faces (`faceTextMetrics` uses plain string sizing) and titled command buttons. Not measured: `SegmentedToggle` segments, the Size readout and header, swatch glyphs and the Custom chip, anchor cells, plain labels, captions, status, Resize fields, Size preset stroke glyphs, the Toolbox face, menu header labels, tooltips and VoiceOver text.
- The earlier orchestrator pass captured no `--display` options. Root additionally captured combined injected Reduce Transparency, Increase Contrast, Differentiate Without Color and Reduce Motion for S53/S56/S60 in light/dark. These are injected app settings, not live system toggles.
- The F-J7-006 margin is 5 pt at current font metrics.
- The destination sheet overhangs a 640 pt Settings window by 17 pt when S3 scrolls. This is pre-existing and identical at `57ec799`.
- Hover does not move keyboard focus inside a panel. Native menus do.
- Each modifier toggle row is one Tab stop. ⌘⌥⌃⇧ are reached with the arrows.
- `tools/test-app-safety.sh` still carries a no-op text replacement for the removed `colorPopover: NSPopover?`.
- Worker-level AppKit runs before lock v2 may have overlapped. Acceptance uses the root's owner-checked serial integration runs; the earlier orchestrator gates are superseded.
- Ownership: P's round 6 (icons) changed two narrow hunks owned by A: `tests/AppSafetyMenuCases.swift` (the Toolbox row asserts Font Awesome rendering; the title, shortcut, validation and action assertions are kept) and `tests/AppSafetyModernCases.swift` (the Zoom Actual Size row's Font Awesome proof). The root reviewed and accepted both.

## Current root acceptance — 2026-10-11

Tested source `21b8d68e10543b097cb6a902103e9c56eeb76be5`, tree `047c1a0ce65c3806633926740afea20c8eaffc4d`. The full root suite, fresh captures and independent native proof are documented in [root verification](e2e/glass-pickers-root-verification.md). The earlier `fa3ddf7` / `3fa5a95` candidate failed external accessibility and is superseded.

Root took over the unfinished narrow correction after the Claude provider cap stopped the fleet. Explicit semantic choice elements remain; raw defensive panel/plate forwarders were removed because they exposed AXUnknown wrappers. The raw window-root walker now checks returned roles and parent chains before flattening. Color and Size preset activation finishes its external AX reply before dispatching; Color retains initiating Shift modifiers. History summaries expose static-text roles. Red proofs and final external results are packaged in the root evidence.

`tools/test.py` now serializes native suite execution internally while keeping compilation parallel. Earlier fleet runs were serial relative to other fleet commands, but internal suite execution overlapped. Root final validation uses both the internal lock and owner-checked fleet GUI lock. Two pre-final runs failed stale asynchronous assertions and the isolated-event seam; neither is reported as final acceptance. The final harness supplies one isolated event to both app and swatch handlers, preserving the stronger Shift-over-later-event regression.

The native proof was captured at `03d267b`; Sources, tests, Resources and Info.plist subtree hashes are identical at the final tested source. The only delta is the harness event seam in `tools/test-app-safety.sh`. Native evidence is retained at its actual SHA rather than relabelled. All external actions returned success, parent chains agreed, and no AXUnknown wrappers remained. No inventory rows were promoted: all 94 UI-changed histories remain immutable.
