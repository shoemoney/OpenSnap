# E2E audit findings: lane J1 (editor core)

Source revision `15d5ec2` (main `7c8bdb1` + tooltip crash fix + E2E infra). Driver: Sonnet J1, real clicks and keys through kimi-cu on an isolated session copy. Screenshots live in `docs/design/evidence/e2e-2026-10-10/j1/`.

Severity: P0 crash or data loss, P1 broken or confusing, P2 visual or space, P3 polish.

Harness notes that affect how to read the evidence (not app defects):

- The pink diagonal stroke visible in some captures after a drag is the harness's own drag-trail overlay, not app content.
- The session window is never key until it is raised; keys and popovers only behave once it is (see the matrix rows marked `unverified`).
- Menu-bar picks can only be committed while the app is active; the in-window Toolbox menu always works.

## Findings

### F-J1-001 · P2 · Eraser stroke carries the drop shadow
- **Surface:** Eraser tool
- **Steps:** draw a filled rectangle, select Eraser, drag across it with Shadow on.
- **Observed:** the erase stroke is a white stroke with a grey shadow, so the rectangle gets a visible grey-outlined white scar (`04-eraser-white-stroke-with-shadow-halo.jpg`). Undo removes it.
- **Expected:** erasing leaves no outline; the Shadow preference should not apply to the eraser.
- **Suggested fix:** skip the shadow when drawing an eraser element.

### F-J1-002 · P2 · Colour swatches do not match the colour they apply and show no selected state
- **Surface:** Color popover
- **Steps:** open Color, pick Blue, reopen the popover.
- **Observed:** the Blue swatch is rgb(26,142,255) but the applied colour is rgb(21,93,255) (Red swatch 255,39,0 vs applied 255,0,0). No swatch shows a check after Blue (`07-color-popover-after-blue-no-check.jpg`); only an exact match shows the gold ring and check (`08-color-popover-black-checked.jpg`). AX gives the swatches no selected value either.
- **Expected:** the swatch is the colour that gets applied, and the chosen preset shows its check.
- **Suggested fix:** draw the swatch with the preset's real colour (not through the popover material tint) and compare the selection with a tolerance, or mark the selected preset by identity.

### F-J1-003 · P1 · Custom color… silently overwrites the drawing colour
- **Surface:** Color popover › Custom color…, system Colors panel
- **Steps:** pick Black, open Color › Custom color…, close the Colors panel without choosing anything.
- **Observed:** the panel opens showing pure blue, not the current colour (`10-colors-panel-opens-showing-blue.jpg`); after closing it the toolbar colour is rgb(0,0,255) (`11-after-closing-colors-panel-colour-now-blue.jpg`). Reproduced twice.
- **Expected:** the panel starts at the current drawing colour and closing it changes nothing.
- **Suggested fix:** set `NSColorPanel.shared.color` to the current colour before showing it and only apply colour changes the user makes while the panel is open.

### F-J1-004 · P2 · Return in the Resize sheet only previews; no default button is shown
- **Surface:** Resize or Crop sheet (Resize and Limit modes)
- **Steps:** open Resize…, type Width 400, press Return.
- **Observed:** the document is previewed at 400 × 300 and the sheet stays open (`25-resize-sheet-after-return-still-open-doc-400x300.jpg`); Cancel reverts it. Neither Apply nor OK is drawn as the default button. The matrix expects Return = OK (apply and close). Same in Limit mode. By contrast the Rename sheet draws OK as the yellow default and Return commits (`72-file-rename-sheet-default-ok.jpg`).
- **Expected:** Return commits and closes (OK is the default button); Apply is the non-default way to preview.
- **Suggested fix:** give OK `keyEquivalent = "\r"` and make Apply a plain button.

### F-J1-005 · P1 · Changing Size resizes a selected text's frame but not its glyphs
- **Surface:** Size popover with a Text element selected
- **Steps:** type text, pick Size 12 from the popover.
- **Observed:** the selection frame balloons (about 460 × 80 pt) while the glyphs stay the same size (`13-size-popover-preset12-text-frame-balloons.jpg`). Duplicate (Edit › Duplicate) then renders the copy's glyphs larger than the original at the same frame (`35-edit-duplicate-copy-text-larger-than-original.jpg`), so the original is stale.
- **Expected:** the glyphs and the frame follow the size together.
- **Suggested fix:** re-render the text element after a size change.

### F-J1-006 · P1 · Shadow toggle restyles the whole selection
- **Surface:** Drawing › Shadow, Toolbox › Shadow
- **Steps:** draw a red filled rectangle, a red ellipse and lines; set the pen to blue, size 9; Select All; toggle Shadow.
- **Observed:** every selected shape turns blue, size 9, the filled rectangle loses its fill (`38-drawing-shadow-toggle-restyled-all-selected-blue.jpg`, `40-toolbox-shadow-reproduces-restyle-of-selection.jpg`). One Undo restores everything (`39-one-undo-restores-restyle.jpg`). Reproduced from both menus.
- **Expected:** a preference toggle changes the shadow flag only.
- **Suggested fix:** apply only the shadow attribute to the selection, not the whole pen style.

### F-J1-007 · P1 · Keyboard focus is trapped on the canvas; the bottom bar is unreachable forward
- **Surface:** whole window, Tab order
- **Steps:** ⌥⌘T (Focus Toolbar), press Tab repeatedly.
- **Observed:** order is Hide, Toolbox, Photos, Snap, ten tools, Color, Size, Font, then the canvas. In the canvas Tab and ⇧Tab only toggle Brush (`55-keyboard-trap-tab-in-canvas-toggles-brush-crop-overlay-lingers.jpg`) and focus never leaves. Undo, Wipe, Zoom, Resize, Save, History, Format, Drag, Upload can only be reached by ⇧Tab backwards from Hide.
- **Expected:** every control reachable both ways with Tab, no trap.
- **Suggested fix:** let Tab leave the canvas (keep the pencil toggle on a different key or only when not keyboard-navigating), and order the bottom bar after the canvas.

### F-J1-008 · P2 · Full screen cannot be entered or left from a menu or key
- **Surface:** Window menu, green button
- **Steps:** green button → full screen; look for Exit Full Screen in the Window menu; try ⌃⌘F.
- **Observed:** the Window menu has no Enter/Exit Full Screen item and ⌃⌘F does nothing (`45-fullscreen-entered-green-button.jpg`). Exiting needs the title bar revealed with a real pointer; in this session it was done with System Events `AXFullScreen = false`.
- **Expected:** a View or Window item "Enter/Exit Full Screen" (⌃⌘F).
- **Suggested fix:** add the standard AppKit item.

### F-J1-009 · P2 · Toolbox menu is a 33-row copy of the menu bar
- **Surface:** Toolbox pop-up
- **Observed:** About, Settings, Quit, file, edit, capture and image commands in one menu taller than the window (`37-toolbox-menu-open-33-rows-no-leading-icons.jpg`); its help says "common drawing and capture commands". No leading icons are drawn although the inventory lists menu symbols.
- **Expected:** a short menu of the commands a drawing session needs; icons present.
- **Suggested fix:** cut it to drawing and capture commands, or confirm why the symbols are not drawn.

### F-J1-010 · P3 · Status line goes stale
- **Observed:** "Exit full screen to use Frame" is still shown after leaving full screen and after hide/restore (`47-fullscreen-exited-status-text-stale.jpg`, `54-hide-then-show-via-status-item-restored.jpg`). "Saved to History" stays until the next event (`33-save-to-history-status-confirms.jpg`). The status never names PNG or JPG.
- **Suggested fix:** clear transient messages on a timer or on the next state change; add the format to the size text.

### F-J1-011 · P2 · Crop tool gives no way to learn Return applies it, and its overlay lingers
- **Observed:** after a drag the status says only "Crop · Unsaved changes" (`52-crop-tool-region-dimmed-no-apply-hint.jpg`). After an Undo and a Tab-driven switch to Brush the dim crop overlay is still drawn (`55-keyboard-trap-tab-in-canvas-toggles-brush-crop-overlay-lingers.jpg`).
- **Suggested fix:** status "Crop: press Return to apply, Esc to cancel"; drop the overlay when the tool changes.

### F-J1-012 · P2 (plausible) · Drag well activation never shows an Export panel
- **Surface:** Drag image to another app
- **Steps:** focus the well (ring visible), press Space; repeat on a clean drawing with the window key.
- **Observed:** the app goes modal (AX tree empty until Esc), but no panel appears in a window capture or in a real-desktop screencapture 15 s later (`58-drag-well-focused-space-does-nothing.jpg`). The source comment says Space/Return open the Export panel. The same happens for the Save panel from the quit sheet. Likely the OS save-panel service is not shown to this harness, so this is unconfirmed.
- **Expected:** the Export panel is visible.
- **Suggested fix:** none until a human confirms with a real display.

### F-J1-013 · P3 · Photos sheet empty state is a large blank grid
- **Observed:** a 850 × 420 pt empty box with the explanation only in a small line under it (`32-photos-sheet-empty-state.jpg`).
- **Suggested fix:** put "Choose Pictures Folder… or Photos Library…" inside the empty grid.

### F-J1-014 · P2 · Resize sheet leads with preset management and wastes space
- **Surface:** Resize or Crop sheet
- **Observed:** three rows (preset pop-up, name field, Add/Save/Remove) sit above the mode control, with blank bands between fields and above the buttons in every mode (`24-resize-sheet-resize-mode.jpg`, `27-resize-sheet-crop-mode-anchor-popup.jpg`, `29-resize-sheet-limit-mode.jpg`); the crop anchor is a pop-up instead of a 3 × 3 grid.
- **Suggested fix:** mode control and dimensions first, presets collapsed; 3 × 3 anchor picker.

### F-J1-015 · P3 · Paste lands at the canvas top-left over other content
- **Observed:** pasted rectangle appears at the origin overlapping the first line (`51-toolbox-paste-lands-top-left.jpg`).
- **Suggested fix:** paste at the original position offset slightly, or at the view centre.

### F-J1-016 · P3 · Selection handles do not scale at 25% zoom
- **Observed:** handles are bigger than the text they select (`21-zoom-25-selection-handles-dominate.jpg`).

### F-J1-017 · P3 · Command naming
- **Observed:** Edit has Wipe, Wipe Snap Only and Clear Annotations as three near-synonyms; the Image menu holds Bring to Front, Send to Back, Group and Ungroup (arrange commands).

### F-J1-018 · P2 · Full-screen layout puts controls 1,900 pt apart
- **Observed:** the 800 × 600 canvas stays at 100% in the middle of a 2056 × 1329 window while the left controls, tool group and right controls are pinned to the corners (`45-fullscreen-entered-green-button.jpg`).
- **Suggested fix:** zoom to fit or cap the chrome width.

### F-J1-019 · P3 · Popovers disagree on dismissal
- **Observed:** the Colour popover closes after a pick, the Size popover stays open after a preset (`12-size-popover-open-size7.jpg`, `13-size-popover-preset12-text-frame-balloons.jpg`).

### F-J1-020 · P3 · Undo is enabled on a blank document
- **Observed:** on a fresh launch the Undo button is drawn enabled and AX has no `disabled`, while Wipe is correctly disabled (`00-brush-tool-selected.jpg`).
- **Suggested fix:** disable Undo (and Edit › Undo) while the undo stack is empty.

### F-J1-021 · P3 · Floppy-disk icon means "Save to History"
- **Observed:** the Save button shows a floppy disk, which reads as "save a file", but its action is Save to History (`84-bottom-bar-save-button-saved-to-history.jpg`); the History button sits right next to it.
- **Suggested fix:** use a tray/archive glyph so the two neighbours read as archive and browse.

### F-J1-022 · P2 (plausible) · ⌘M does not hide the window
- **Surface:** Window › Minimize (⌘M), Hide button tooltip "Hide (⌘M)"
- **Observed:** the Hide button hides the window, but ⌘M left it on screen in four tries (the harness's menu pick three times, one real System Events keystroke with OpenSnap confirmed frontmost). Not reproduced by a human on a real keyboard.
- **Suggested fix:** check `validateMenuItem`/`vanish` for the Minimize item.

### F-J1-023 · P3 · Text editor exposes no AX selection
- **Observed:** `AXSelectedTextRange` cannot be set on the in-place text editor (kimi-cu `select_text` returns -25205 although the replace worked through events).
- **Suggested fix:** make the editor's text view an `NSTextView` with standard accessibility.

### F-J1-024 · P3 · Option-Return then typing starts a second text box on top of the first
- **Observed:** Option-Return finished the first text (as documented) and the next typed characters created a second text box that overlapped it (`60-text-option-return-finishes-and-new-box-starts.jpg`).
- **Suggested fix:** after Option-Return ignore plain typing until a new click, or offset the new box.

### F-J1-025 · P3 · Add Shadow does nothing visible without a snap
- **Observed:** Image › Add Shadow is enabled but pressing it on a plain drawing changes nothing visible (`83-image-add-shadow-no-visible-change-without-snap.jpg`).
- **Suggested fix:** disable it unless there is a snap.

### F-J1-026 · P3 · Flip mirrors the text glyphs
- **Observed:** Flip Horizontal mirrors annotation text so it reads backwards (`61-image-flip-horizontal.jpg`); Rotate keeps it readable.

## Notes (subjective, not findings)

- The Font panel is large (940 × 720) for the three app accessories at its foot.
- Menu row height is 29 pt, system size; the status line text is small relative to the 20 pt chrome.
- The first drag with the Select tool without a press-and-hold did not move the rectangle; with a 150 ms hold it did. This may be a harness timing artefact.
