# E2E audit findings: lane J1 (editor core)

Source revision `15d5ec2` (main `7c8bdb1` + tooltip crash fix + E2E infra). Driver: J1 lane, real clicks and keys through the computer-use driver on an isolated session copy. Screenshots live in `docs/design/evidence/e2e-2026-10-10/j1/`.

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
- **Observed:** `AXSelectedTextRange` cannot be set on the in-place text editor (the driver's `select_text` returns -25205 although the replace worked through events).
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


---

# E2E audit findings: lane J2 (History, Destinations, Settings, uploads, About, status item)

Source revision `10040ba` (main after J1 and audit fix batch 1). Driver: J2 lane, real clicks through the computer-use driver on two isolated session copies (pids 39783 and 90314). Screenshots live in `docs/design/evidence/e2e-2026-10-10/j2/` (names below are relative to it). History's glass/text-button polish request is deferred by the owner and is not a finding here.

How to read the evidence: windows are captured one at a time, so menus, pop-up lists and context menus never appear in a screenshot; those were driven through AX presses and read back, and are labelled as such in the matrix.

## Findings

### F-J2-001 · P1 · History's Hide, Trash and Delete confirmations appear on the editor window, not on History
- **Surface:** History › Hide from History, Move to Trash, Delete from Web, Delete key
- **Steps:** open History from the bar, select a tile, click the eye-slash icon.
- **Observed:** nothing changes in History (`04-history-hide-clicked-history-window-shows-nothing.jpg`); the “Hide drawings from History?” sheet is drawn on the editor window behind it (`05-history-hide-confirm-sheet-is-on-editor-window.jpg`, `07-…`, `24-…`). If the editor is hidden or minimised the click looks dead and the History window stays modal-blocked by a sheet it cannot show.
- **Expected:** the confirmation attaches to the window the user clicked in.
- **Suggested fix:** present the AppAlert on `historyBrowser.window` (fallback: bring the editor forward first).

### F-J2-002 · P1 · The app cannot delete its own S3 upload: Delete from Web refuses
- **Surface:** History › Delete from Web (icon enabled), S3 default destination `cdn.shoemoney.com`
- **Steps:** make the seeded S3 destination default, Upload once, open History, select the new Shared entry, click Delete from Web.
- **Observed:** no confirm sheet; the status line says “This item has no verified publication destination for de…” (`75-aws-history-delete-from-web-refused-no-verified-binding.jpg`). The new entry has a `remoteURL` and no `remoteBinding` in `index.json`. `App.deleteHistoryRemote` guards on a binding that `beginUpload` drops when `payload.binding != currentBinding`. The fallback `aws s3api delete-object` on that single key worked.
- **Expected:** an item the app just published to a configured S3 destination is deletable through the app, or the icon stays disabled with a reason.
- **Suggested fix:** find why the pre-publication and post-publication bindings differ for the S3 profile destination (public URL mapping or the settings fingerprint) and fix or compare the stable fields; show the reason in a tooltip when the icon is refused.

### F-J2-003 · P1 · Opening a History entry silently replaces a document that shows “Unsaved changes”
- **Surface:** History › Open icon (also Return)
- **Steps:** open one entry (status line reads Unsaved changes), then select another entry and press the Open icon.
- **Observed:** the second entry replaced the first immediately with no Save your drawing? sheet (`23-history-open-icon-replaces-unsaved-doc-no-prompt.jpg`).
- **Expected:** the same dirty-document guard as File › New and Quit, or autosave of the previous document.
- **Suggested fix:** route History Open through the same `confirmDiscard` path as New/Open.

### F-J2-004 · P2 · Copy and Copy Link in History give no visible confirmation
- **Steps:** select a Shared tile, press Copy Link, then Copy. The pasteboard changed (link text, PNG) but History shows no toast, no status change (`03-history-shared-tile-link-actions-enabled.jpg`).
- **Expected:** a one-line confirmation (“Link copied”) in the History status line.
- **Suggested fix:** reuse the editor’s “Link copied” style message in History’s footer.

### F-J2-005 · P2 · A freshly opened History entry already says “Unsaved changes”
- **Observed:** a never-edited entry opened with Return reads “Arrow · Unsaved changes” (`69-control-session2-open-entry-bright-no-prompt-but-unsaved-changes.jpg`, `22-…`), so Quit and New prompt for a document the user never touched.
- **Suggested fix:** clear the dirty flag after loading a document from the archive.

### F-J2-006 · P2 (plausible, not reproduced) · The opened document rendered about 45% dark for the rest of one session
- **Observed:** in the first session, after Hide and Trash confirmations, every opened entry showed a dim canvas even with no sheet up (`22-…`, `23-…`, `25-editor-canvas-still-dim-after-sheet-cancel.jpg`, `57-…`). The History tile for the same entry is bright. In the second session, with no earlier sheet, an opened entry was bright (`69-…`), and the dim came and went with a sheet (Cancel and Hide both undimmed). A stuck sheet-dim after double-triggered or overlapping confirmations is the likely cause.
- **Suggested fix:** make sheet presentation idempotent (one alert at a time) and remove the dim layer in the completion handler.

### F-J2-007 · P2 · Category names do not match tile labels
- **Observed:** the Saved tab shows entries labelled “Exported/Dragged” (`13-…`); entries labelled “Saved” live under Archived (`01-…`, `14-…`).
- **Suggested fix:** use one vocabulary (tab “Exported” for Exported/Dragged, tab “Saved” for saved ones) or relabel tiles.

### F-J2-008 · P3 · History empty and no-match states
- **Observed:** the no-match state removes the status line and gives no hint or button to clear the filters (`14-…`, `16-…`, `18-…`); the footer says “1 items · 0 selected” (`15-…`).
- **Suggested fix:** keep the footer, add “Clear filters”, pluralise.

### F-J2-009 · P2 · History wastes space
- **Observed:** with nothing selected the right 280 pt column holds only “Select a snap to see its details.” (`01-…`); at the 880 × 600 minimum two 210 pt tiles leave about a third of each row empty (`20-…`); each day section reserves about 60 pt of blank under the captions.
- **Suggested fix:** collapse the details column until a selection exists (or fill it with the day’s summary), and let the grid add a column when it fits.

### F-J2-010 · P2 · Details panel clips the Destination URL
- **Observed:** for an uploaded entry the Destination value wraps to “https:// cdn.shoemoney.com/pics/” and the file name is cut below the panel (`74-aws-history-entry-details-destination-url-clipped.jpg`).
- **Suggested fix:** let the details column scroll or truncate in the middle and expose the full link in the tooltip/Copy Link.

### F-J2-011 · P2 (plausible) · ⌘1–⌘4 in Settings may start captures instead of switching tabs
- **Steps:** with Settings key, send ⌘1.
- **Observed:** the harness maps a ⌘ chord to the matching menu item, so the Capture menu’s ⌘1 ran (crosshair overlay opened, Escape cancelled it) and the tab did not change. On a real keyboard `SettingsWindow.performKeyEquivalent` may win; not confirmable here.
- **Suggested fix:** if confirmed, give the tab shortcuts different keys or stop the menu equivalents while Settings is key.

### F-J2-012 · P2 · Settings window height jumps between tabs; the Upload tab clips its caption
- **Observed:** 301, 242, 609 and 457 pt tall for the four tabs; with five destinations the Upload list needs scrolling and “Uploads go to the default destination.” is below the fold (`53-…`, `41-…`).
- **Suggested fix:** one fixed content height for all tabs, scroll inside the form.

### F-J2-013 · P2 · The Destinations sheet is wider than the Settings window that hosts it
- **Observed:** opened from Settings › Manage Destinations… the 800 pt sheet overhangs a 640 pt window with a stub of the parent above it (`36-destinations-sheet-from-settings-manage.jpg`); from OpenSnap › Sharing Settings… it sits well inside the editor (`65-…`).
- **Suggested fix:** open it from the editor window in both cases, or size it to the parent.

### F-J2-014 · P2 · Only S3 destinations have a Test button
- **Observed:** WebDAV, FTP, FTPS and SFTP forms offer only Cancel and Save (`37-…`, `42-…`, `44-…`); the S3 form has Test (`47-…`). The inventory and the plan expect Test everywhere.
- **Suggested fix:** add a connectivity Test per protocol or say why it is absent.

### F-J2-015 · P2 · Destination form copy does not follow the protocol
- **Observed:** the Endpoint placeholder stays `https://example.com/uploads` for FTP, FTPS and SFTP (`42-…`, `44-…`); the WebDAV form carries the FTPS help paragraph (`37-…`); SFTP shows both Endpoint URL and SSH host alias/remote root, which overlap (`44-…`); a wrong scheme says “matching scheme” without naming it (`43-…`).
- **Suggested fix:** per-protocol placeholders and help, hide Endpoint for SFTP or explain the split, name the expected scheme in the error.

### F-J2-016 · P2 · S3 credential fields contradict their own validation
- **Observed:** Access key ID placeholder says “Optional for anonymous destinations” but Test/Save answer “Enter the access key ID and secret, or choose an AWS credentials profile.”; the Secret field placeholder is “Password stored in macOS Keychain” (`48-destination-s3-test-needs-keys-placeholder-says-optional.jpg`).
- **Suggested fix:** S3-specific placeholders; drop “optional” for S3.

### F-J2-017 · P2 · Filled destination fields lose their accessible name
- **Observed:** with text entered the AX tree shows `AXTextField = "J2 WebDAV fake"` and no name, while empty fields show `(Name)`, `(Endpoint URL)`; the label comes from the placeholder. A VoiceOver user hears the value without the field.
- **Suggested fix:** set `setAccessibilityLabel` on each field explicitly.

### F-J2-018 · P2 · The S3 form’s result bar and button bar cover content
- **Observed:** a three-line Test error covers the Secret access key field (`49-…`); the explanatory paragraph at the foot is cut by the button bar while the sheet scrolls (`48-…`).
- **Suggested fix:** reserve the result area above the buttons and let the form scroll above it.

### F-J2-019 · P3 · Remove confirmation has no visible default and the destructive button is focused
- **Observed:** Cancel and Remove both look the same grey; AX marks Remove focused (`50-…`, `51-…`). The inventory describes this alert as NSAlert, but it is the app’s own sheet.
- **Suggested fix:** make Cancel the default and style Remove as destructive.

### F-J2-020 · P3 · Capture shortcuts: stale error, duplicate surfaces, faint modifiers
- **Observed:** Disable All leaves the red duplicate-shortcut error on screen (`33-…`); Settings applies live while the app-menu sheet has Save/Cancel with the same controls (`30-…`, `64-…`); selected ⌘ ⌥ ⌃ ⇧ segments are a pale pill against dim ones (`32-…`); the key pop-up is a 69-item menu.
- **Suggested fix:** clear the error on Disable All/Reset, drop one of the two surfaces, give selected modifiers the accent, and offer a record-shortcut field.

### F-J2-021 · P2 · Upload failure messaging
- **Observed:** the inline error is tail-truncated at the default width (“Error: The publishing password could n…”, `57-…`; complete at full screen, `59-…`); the Details alert repeats “Error:” under an “Upload failed” title (`58-…`); Retry gives the same line and no visible “retrying” state.
- **Suggested fix:** middle/line-wrap the status, drop the redundant prefix in the alert, show a busy state during Retry.

### F-J2-022 · P2 · Upload progress is visible, outcome confirmation is not
- **Observed:** the spinner and “Uploading …” with ✕ show (`66-…`, `72-…`); a cancelled upload returns to the idle line with no “Upload cancelled” (`67-…`); after the S3 success the “Link copied” line was already gone four seconds later and the status was back to “Arrow · Unsaved changes” (the link was on the pasteboard). Only one real upload was allowed, so the line could not be re-captured.
- **Suggested fix:** keep the result line (with the Open and Copy icons) for at least ten seconds or until the next action.

### F-J2-023 · P2 · About, License and Notices
- **Observed:** the MIT License text is hard-wrapped in the file and re-wraps raggedly in the 620 pt window (`61-…`); the notices describe the toolbar, status and action icons as Font Awesome Free (`62-…`) while the Modern appearance uses Font Awesome Pro; the About window has no title text and its Escape and ⌘W did not respond in this harness (the Settings window behaved the same).
- **Suggested fix:** reflow paragraphs on load, check the notices against the shipped icon set, confirm the About window closes on Escape.

### F-J2-024 · P3 · Move to Trash escapes the isolated home
- **Observed:** after the History Trash test two synthetic `.opensnap` and `.png` files appeared in the owner’s real `~/.Trash` (`08-…`); `FileManager.trashItem` ignores the throwaway HOME. Removed by hand (those two files only).
- **Suggested fix:** none for the app; the launcher notes should say Trash is not isolated.

## Notes (subjective, not findings)

- History tiles show the plain gradient preview for seeded entries until the entry is opened; after opening, the preview shows the annotations.
- Settings tab strip text is large and readable; the Capture tab is the densest surface and a good candidate for a two-column layout.
- The status item menu reads Hide OpenSnap / Show OpenSnap correctly when the editor is hidden, but it cannot be committed by the harness while the app is in the background.
- The pop-up menus in History and Settings use the system 29 pt row height.

## Harness limits that cost coverage (not app defects)

- Right-click context menus (History tiles, Upload button) never open from a synthetic right-click.
- `activate_window` is not a callable tool in this build; menu-bar and status-item picks work only while the app happens to be active, and clicks are routed by screen position, so overlapping windows (History over the editor) take the click.
- Escape and ⌘W reach only the key window; Settings and About were not key when tried. AX press on the About close button did nothing; a real click on it closed the window.


---

# E2E audit findings: lane J3 (rendered matrix)

Source revision `3194247` (main after fix batches 3a and 3b). Driver: J3 lane, harness captures only (`tools/eye-dump-audit.sh`, throwaway bundle id, isolated HOME and defaults, display options injected inside the throwaway copy). **Nothing here is a real-click E2E result**: a capture proves how a state looks, not that a user can reach it, and the harness cannot prove VoiceOver speech or live screen capture. The 106-capture packed set is `docs/design/evidence/e2e-2026-10-10/j3/` (file names below are relative to it, with `@3194247` dropped); side-by-side composites are in `docs/design/evidence/e2e-2026-10-10/j3-diffs/`. Raw runs stayed in `/tmp/j3/` (not committed, 3,338 PNGs over 18 runs).

Severity: P0 crash or data loss, P1 broken or confusing, P2 visual or space, P3 polish. Surfaces whose fix is still in flight in batch 3c (Resize sheet, Toolbox menu, full-screen layout, History confirmations) are marked **pending 3c** instead of being filed again.

## What was run

All with `--icons sf` (see "Icons" below), all sequential, built from `3194247` with `sh tools/build.sh`.

| Run | Command (after `sh tools/eye-dump-audit.sh /tmp/j3/<name>`) | PNGs |
|---|---|---|
| base-a | `--groups main,more,overlays,states,fullscreen,layout --appearances light,dark --icons sf` | 517 |
| base-sizes | `--groups sizes --sizes 980xmin,1024x740,1280x800,1440x900,full --appearances light,dark --icons sf` | 20 |
| rt, ic, dwc, rm | `--display reduceTransparency` / `increaseContrast` / `differentiateWithoutColor` / `reduceMotion` `--groups main,states` (ic also `overlays`) `--sizes 980xmin,1440x900 --appearances light,dark` | 262 / 286 / 262 / 262 |
| combo-rt-ic, combo-all | `--display reduceTransparency,increaseContrast` and all four, `--groups main,states --sizes 980xmin` | 258 / 258 |
| icons-fa, icons-sf | `--groups main --sizes 1280x800 --appearances light --icons fa` / `sf` | 0 / 53 |
| rm-overlays(2) | `--display reduceMotion --groups overlays` (run twice) | 24 / 24 |
| base-more, rt-more, ic-more(2), dwc-more | `[--display …] --surfaces S17,S19,S20,S21,S25,S26,S39[,S31]` | 219 / 204 / 203, 219 / 216 |
| noise | `--groups main --appearances light --icons sf` (a second baseline, no option) | 51 |

`--sizes` is consumed only by the `sizes` group (populated S11M and empty S11E matrices), so the five sizes exist as a full matrix for the editor alone; every other surface is captured at the size its harness step uses (listed in the matrix footnotes).

Validity checks:
- **Determinism:** the noise run matches the baseline bit for bit in 49 of 51 captures; the two that differ are `S05-selection-multi-light` (2,670 px) and the system Colors panel `S06-color-panel-light` (5,022 px). Every other difference below is therefore a real signal. Date lines in History details (`4:01AM` vs `4:26AM`) also differ per run and are ignored.
- **Active-app flag:** each capture records `appActive`. 46 captures in the first `ic-more`/`rm-overlays` runs were taken with the app inactive (yellow default buttons render grey); they were re-run (`ic-more2`, `rm-overlays2`) and only active pairs are used, though S21/S25/S26/S39 stayed inactive in `ic-more2` and `base-more` and are not used for any claim.
- **Checker:** `python3 tools/check-eye-dump.py` on every raw run reports 0 failures (no clipping, overlap, size or rail violation), except the baseline's `raw-sf/layout/budget-3194247.json` which "has no PNG" by design (the packed set passes: 111 PNGs, 69 layouts, 0 failures).
- **Real stores:** the guard digest (`dbde037ac2085108`, 122 files + 2 defaults plists) was identical before and after every run. Three runs (`dwc`, `rm-overlays`, `ic-more2`) print `RESULT STORES CHANGED` solely because of throwaway plists left in `~/Library/Preferences` by other sessions: `com.shoemoney.opensnap.eyedump-43695`, `…eyedump-71647` (another worker's harness runs; mine were 10523, 71508, 62036) and `com.shoemoney.opensnap.e2e-62694` (the E2E session launcher). The e2e plist is still there and its pid is no longer running; it was not touched.

## Positive controls (does each display option change the render where it must?)

Pixel diff = pixels whose luma differs by more than 8 between the baseline capture and the same capture with the option, same size and appearance.

| Option | Captures compared (identical) | Where it must change | Measured | Verdict |
|---|---|---|---|---|
| Reduce Transparency | 262 (15: system panels, standalone popovers) | glass plates become solid | dark `S11-width-980`: 212,420 px (6.67%); `S03-topbar-dark` crop 24.2%; `S09-footer-dark` 24.5%. Light: only 2,157 px (0.07%), plate edge hairlines. Structure: in `S01` metrics 16 `hidden` flags flip true→false (8 solid fallback views appear), both appearances. | **Pass.** Strong in dark, near invisible in light because the glass already reads as white over white (`j3-diffs/rt-top-light-base-vs-rt.png`, baseline left, option right). |
| Increase Contrast | 286 (21: system panels, S13 pickers, S14 contrast variant) | stronger borders | every plate gains a hairline border and Snap a black outline: `S11-width-980` 12,298 px light / 24,162 dark; footer 2.8% / 4.7% (`j3-diffs/ic-980-light.png`, `ic-980-dark.png`). | **Pass** for the editor chrome. See F-J3-004 for what it does not touch. |
| Differentiate Without Color | 262 (60) | a non-colour selection cue | exactly 128 px per capture with a selected tool: a 16 × 2 pt underline under the selected tool (`j3-diffs/dwc-arrow.png`). `S09-format-toggle-png-light-dwc` is **0 px** different. | **Pass, minimal**; see F-J3-001. |
| Reduce Motion | 262 (240) | no animation | static stills cannot show motion. Pressed tool glyph is no longer scaled down (`S40-tool-pressed-*` 504 px; `j3-diffs/rm-pressed.png`); the S14 countdown state string changes (digit 3 reached at tick 1 instead of 2, digit 1 at tick 41 instead of 42). The S15 flash stills are driven with explicit alpha, so they cannot differ. | **Pass, indirect.** |
| Reduce Transparency + Increase Contrast | 258 (7) | both effects | additive: dark `S11-width-980` 203,180 px (6.38%), light 13,852 px (0.44%) | Pass |
| All four | 258 (7) | all four effects, no conflict | versus the two-option run only about 190 px more at 980 light (underline plus press scale); `j3-diffs/combo-all-980.png` shows opaque plates, outlines and the underline together, nothing clipped or overlapping | Pass |

No option shows an absent change where one is required, so no "dead option" finding is filed; the weaknesses are in what the options do (F-J3-001, F-J3-004).

## Icons

- `--icons fa` is **unavailable in this build** (`icon-mode-unavailable.json`: no `FontAwesome7Pro-*-subset.ttf` bundled), so nothing was captured and nothing is claimed for Font Awesome Pro.
- `--icons sf` removes the Pro subset fonts from the throwaway copy and so exercises the shipped chain Pro → embedded Free vector → SF Symbol; the harness does not record which branch each glyph took. The glyphs are Font Awesome Free shapes (eye-slash, toolbox, images, crosshairs, pointer, brush, bucket, eraser, box-archive, clock-rotate-left, hand, cloud-arrow-up), consistent with `FontAwesomeIconsTests` ("Without Pro the Free vector outranks the SF Symbol", `tests/FontAwesomeIconsTests.swift:171`). The `icons-sf` run is bit-identical to the baseline (0 px on `S11-width-1280-light`, `S03-topbar-light`, `S09-footer-light`, `S04-tool-brush-light`), as it must be.
- Semantics read correctly at 980: Hide = eye-slash, Toolbox = toolbox, Photos = stacked images, Snap = crosshairs, ten tool glyphs, colour well, stroke bar, Font "A", Undo = counter-clockwise arrow, Clear = broom, Save = box-archive (the floppy-disk of F-J1-021 is gone), History = clock-rotate-left, Drag = hand, Upload = cloud-arrow-up. Only the Resize glyph (stepped ruler, bottom bar next to the zoom pop-up) does not suggest resize (F-J3-011).

## Findings

### F-J3-001 · P2 · Differentiate Without Color adds one 2 pt underline; the PNG | JPG selection stays hue-only
- **Surface:** editor bottom bar › Image format; any selection pill
- **Observed:** selected PNG fill `#FEF5DC` against unselected JPG `#F0F0F0` is a 1.04:1 lightness contrast in light and `#61583E` against `#484949` is 1.3:1 in dark; both labels share the same weight (Demi 20). With Differentiate Without Color on, `S09-format-toggle-png-light-dwc` is **0 px** different from `S09-format-toggle-png-light`. The only change in the whole editor is a 16 × 2 pt underline beneath the selected tool (`S11-width-980-light-dwc` vs `S11-width-980-light`, `j3-diffs/dwc-arrow.png`), sitting directly under the glyph inside the pill.
- **Expected:** every selected state has a non-colour cue (shape, weight, check, outline) when the option is on, and the format toggle is the editor's one two-state control.
- **Suggested fix:** under the option draw a check or heavier outline on the selected PNG/JPG segment, and give the tool underline more room (4 pt, 2 pt gap).

### F-J3-002 · P2 · History's empty and no-match states leave a blank 260 pt column
- **Surface:** History › No history yet / No history items match these filters
- **Observed:** the empty list well ends at x = 724 in a 1000 pt window and at x = 604 in the 880 pt one; the right-hand details column (about 260 pt, 26% and 30% of the window) is empty white in both (`S20-history-empty-light`, `S20-history-no-match-light`), while the same window with items fills it with the "6 snaps in this view" summary (`S20-history-populated-dark`). The seven action icons above stay drawn, all disabled.
- **Expected:** with nothing to show, the message uses the whole width (or the column holds guidance such as the Save to History hint).
- **Suggested fix:** collapse the column when there are zero items, or move the empty-state message to the window centre.

### F-J3-003 · P2 · WebDAV, FTP, FTPS and SFTP forms keep the S3 form's height: about 190 pt of blank band
- **Surface:** Upload Destinations › Add/Edit, non-S3 protocols
- **Observed:** the sheet is 737 × 760 pt for every protocol. In the WebDAV form the last help line ends at y = 486 and the footer note starts at y = 679, a 193 pt (25%) empty band above Test / Cancel / Save (`S19-destinations-form-webdav-in-context-light`, `S19-destinations-form-sftp-in-context-light`; the S3 form fills the same height, `S19-destinations-form-s3-in-context-light`).
- **Expected:** the sheet fits its content, as the destination list does (737 × 409 pt).
- **Suggested fix:** size the sheet per protocol (or from the form's fitting size) instead of the tallest form.

### F-J3-004 · P3 · Increase Contrast adds outlines only; glyph, disabled and segment contrast are unchanged or lower
- **Surface:** editor chrome with Increase Contrast
- **Observed (sampled from the PNGs):** unselected tool glyphs are `#7F7F7F` on white, 4.0:1, in baseline and with the option; in dark `#A8A8A8` on `#3D3D3D` is 4.57:1 and 4.54:1 with it. Disabled Undo is 1.6:1 before and after. The unselected JPG segment is made lighter (`#484949` → `#555555`) so its label drops from 7.09:1 to 5.92:1 in dark (`S11-width-980-dark-ic` vs `S11-width-980-dark`, JPG label). Combined with Reduce Transparency the dark glyph rises to 5.92:1 only because the plate goes solid (`S11-width-980-dark-rt-ic`).
- **Expected:** the option darkens inactive glyphs (aim 7:1) and never lowers a label's contrast.
- **Suggested fix:** resolve inactive glyph and segment colours through the same Increase Contrast branch as the plate border.
- **Not a finding, a harness limit:** Settings, History, Destinations, About and the alert sheets are unchanged under the injected option (`S17` 44 of 44 captures identical, `S19` standalone forms 28 of 28 (the in-context ones differ only through the editor behind), `S20` populated, empty and no-match 10 of 10, `S25` dark 2 of 2 active captures). Those windows are drawn with stock AppKit controls (`NSButton` radios and push buttons, `SettingsWindow.swift:76`, `AppAlert.swift:72`) that follow the real system setting and cannot be flipped by an in-process injection.

### F-J3-005 · P3 · "100%" and "Original size" do not say what they measure
- **Surface:** bottom bar › zoom pop-up and the "Original size" checkbox
- **Observed:** a 2400 × 1600 shot is shown at 1516 × 1011 pt with the pop-up reading **100%** and the checkbox ticked (`S11M-size-1440x900-dark`, `S11M-size-980xmin-light`). True 1:1 is a separate Actual Size mode (canvas 4800 pt wide for a 4800 px shot, pop-up greyed, no checkbox: `S07-actual-size-light`). The checkbox controls the size of the dragged-out and exported image (`App+ModernChrome.swift:98`) but sits beside the zoom reading as a view option.
- **Expected:** the readout and the label say what they are (for example "Fit 100%" or the pixel scale; "Drag at original size").
- **Suggested fix:** rename the checkbox and add the pixel scale to the zoom tooltip.

### F-J3-006 · P3 (plausible, needs a real-click check) · Size readouts disagree with the canvas in three captures
- **Observed:** `S02-populated-light` is titled "800 × 600 · 10 KB" while its canvas is 1516 × 1011 pt (3:2, a 1200 × 800 synthetic); `S35-large-canvas-w1280-dark` and `S36-selection-w1280-dark` say "300 × 180 · 37 KB" over a shot that fills the 1280 pt window; and in `S08-resize-panel-in-context-light` the title says 2400 × 1600 while the Resize sheet's Width and Height read 1517 and 1011 pixels (**pending 3c**: Resize sheet).
- **Likely cause:** the harness replaces the document image without refreshing title and status, and the Resize session starts from `canvas.outputSize` (document points) rather than the pixel size. Neither is confirmed against a real file open.
- **Suggested check:** open a 2400 × 1600 PNG in an E2E session and compare title, status line and Resize sheet.

### F-J3-007 · P3 · At 980 the status line loses its content, at 1440 and wider the bar sits idle
- **Surface:** bottom bar status slot
- **Observed:** the layout budget sample at 980 with the checkbox shown leaves 48 pt of free bottom-bar width and the status 172 pt, so "Arrow · Unsaved changes · 800 × 600 · 10 KB" is cut to "Unsaved changes" (`S11M-size-980xmin-light`) and the upload link to "Link copied · cdn.exa…" (`S21-publish-success-footer-w980-light`, `j3-diffs/S21-footer-states-w980-light.png`; progress shows "Uploading Quarterly plan…"). The same bar has 542 pt of free width at 1440 and 891 to 1,158 pt at 2056 (`S11M-size-full-dark`, layout `slack.freeHorizontal`). Full-screen layout itself is **pending 3c**.
- **Expected:** the 980 bar spends its space on what the user needs after an upload (the link), and wide windows are not left with a hole in the middle.
- **Suggested fix:** at 980 shrink the "Original size" label to the checkbox plus tooltip (about 100 pt back); let the status keep the tool name and link first.

### F-J3-008 · P3 · The window title line is the only app-owned text under 18 pt
- **Observed:** a sweep of every `metrics/*.json` text field across 537 baseline captures finds no visible app-owned text below 18 pt except the title bar string ("Untitled – 800 × 600 · 10 KB", document name and size) at 13 pt system size. The Fonts panel (11 pt) is a system panel; the zoom pop-up's inner field reports 13 pt but its digits are drawn about 17 pt tall.
- **Expected:** app-owned strings that carry information are 18 pt or more.
- **Suggested fix:** none required if the title bar is treated as system chrome; if not, the size line belongs in the 20 pt status line, where it already is.

### F-J3-009 · P3 · Small and empty documents use 4–41% of a large window
- **Surface:** editor canvas well at 1440 × 900 and larger
- **Observed:** the blank 800 × 600 canvas is 803 × 600 pt in a 1440 × 812 window (41%, `S11-width-1440-dark`), 800 × 600 in 2056 × 1197 (`S11E-empty-size-full-light`, 19.5%) and a 300 × 180 shot is 4.2% of a 1440 × 900 window (`S34-small-canvas-w1440-dark`); tools and footer are unchanged in size. Full-screen specifics are F-J1-018, **pending 3c**.
- **Expected:** a small image can be shown larger without leaving 100%.
- **Suggested fix:** an optional "Fit up to 200%" for images under half the viewport.

### F-J3-010 · P3 · Unselected radios and checkboxes are 1.25:1
- **Observed:** the unselected "Dock" radio disc is `#E6E6E6` on `#FFFFFF`, 1.25:1 (1.34:1 in dark: `#343434` on `#1E1E1E`), with no outline (`S17-settings-general-light`, same rendering for "Export at original size" in `S10-export-accessory-alone-light` and "Make uploads public-read" in `S19-destinations-form-s3-in-context-light`). These are system-drawn controls.
- **Expected:** non-text contrast of at least 3:1 for a control's state indicator.
- **Suggested fix:** leave to AppKit's Increase Contrast handling, or draw an outline ring; flagged because the owner asked about the chrome as a whole.

### F-J3-011 · P3 · The Resize glyph does not read as resize
- **Observed:** the bottom-bar Resize… button is a stepped ruler (`S11-width-980-light`, right of the zoom pop-up); the Crop tool uses the standard crop glyph, and the Resize sheet is titled "Resize or Crop".
- **Suggested fix:** use arrows-to-corners or the crop glyph for the command, keep the ruler for dimensions.

## Rendered confirmations of earlier fixes (rendered only, not E2E)

| Earlier finding | What the 3194247 render shows |
|---|---|
| F-J1-021 floppy-disk means Save to History | Save is a box-archive glyph (`S11-width-980-light`) |
| F-J2-008 History no-match | "Clear filters" button and "0 of 6 items" footer (`S20-history-no-match-light`); the blank column is F-J3-002 |
| F-J2-009 History details column | selected and populated states fill it ("6 snaps in this view", `S20-history-populated-dark`) |
| F-J2-012 Settings height jumps | General, Drawing, Capture and Upload at 301, 242, 577 and 400 pt (558 with five or more destinations), each fitted, no clipped caption (`S17-settings-general-light`, `S17-settings-upload-many-light`) |
| F-J2-014 / 015 / 016 / 018 destination forms | per-protocol Test, per-protocol placeholders and help, S3 placeholders, a separate red result band above the buttons (`S19-destinations-form-webdav-in-context-light`, `S19-destinations-test-error-dark`) |
| F-J2-019 Remove confirmation | Cancel is the yellow default, Remove is red (`S26-remove-destination-light`) |
| F-J2-021 / 022 upload status | progress, success (Open and Copy icons), error (Retry and Info) states; link still truncated at 980 (F-J3-007) |
| F-J2-023 About reflow | About is a compact column; the license text reflows at 20 pt (`S25-license-window-dark`) |
| F-J1-004 Return in Resize | the sheet draws OK as the yellow default (`S08-resize-panel-in-context-light`); the Return behaviour needs a real key press |

## J3 rendered matrix

Legend: **ok** = captured and looked at; **ok·m** = captured and machine-checked (`check-eye-dump`, pixel diff against the baseline, metrics) but not individually viewed; **F-J3-nnn** = finding; **n/c** = not captured (reason below). Sizes: `L`/`D` = light/dark; "980" = 980 pt wide; "wide" = 1280, 1440 or full. Option columns refer to the injected option at 980 and 1440 (light and dark) unless a footnote says otherwise.

| Surface (harness id) | L 980 | D 980 | L wide | D wide | Reduce Transp. | Increase Contrast | Diff. w/o Color | Reduce Motion | RT+IC / all four |
|---|---|---|---|---|---|---|---|---|---|
| Editor empty (S01, S11, S11E) | ok | ok | ok·m | ok (F-J3-009) | ok | ok (F-J3-004) | F-J3-001 | ok | ok |
| Editor populated (S02, S11M) | ok | ok·m | ok·m | ok | ok·m | ok·m | ok·m | ok·m | ok·m |
| Top and bottom bars (S03, S09, S37) | ok | ok·m | ok·m | ok·m | ok | ok (F-J3-004) | F-J3-001 | ok·m | ok |
| Tool and control states (S04, S28, S40) | ok·m | ok·m | ok·m | ok·m | ok (S40-pressed) | ok·m | ok·m | ok (press scale) | ok·m |
| Selection, text editing (S05, S36) | ok | ok·m | ok·m | ok | ok·m | ok·m | ok·m | ok·m | ok·m |
| Colour, size, font popovers (S06, S30, S31) | ok | ok·m | ok·m | ok·m | ok·m | ok·m | ok·m | ok·m | ok·m |
| Zoom, large, small, Actual Size (S07, S33-S35) | ok | ok·m | ok·m | ok (F-J3-005, 009) | ok·m | ok·m | ok·m | ok·m | n/c |
| Crop and Resize sheet (S08) | ok (pending 3c) | ok·m | n/c | n/c | ok·m | ok·m | ok·m | n/c | n/c |
| Export accessory alone (S10) | ok | ok·m | n/c | n/c | ok·m | ok·m | ok·m | n/c | n/c |
| Frame mode (S12, S32) | ok | ok·m | ok·m | ok | ok·m | ok·m | ok·m | n/c | n/c |
| Picker, countdown, flash (S13-S15) | ok | ok | n/c | n/c | n/c | ok·m (S13 0 px) | n/c | ok·m (state only) | n/c |
| Permission sheet (S16) | ok | ok·m | n/c | n/c | n/c | n/c | n/c | n/c | n/c |
| Settings, 4 tabs (S17) | ok | ok·m | ok·m (1280 variants) | ok | ok·m (0 px) | harness limit | ok·m (0 px) | n/c | n/c |
| Capture Shortcuts sheet (S18) | ok·m | ok | n/c | n/c | n/c | n/c | n/c | n/c | n/c |
| Destinations list and forms (S19) | ok | ok·m | ok·m | ok·m | ok·m | harness limit | ok·m | n/c | n/c |
| History (S20) | ok | ok·m | ok·m (1120, 1280) | ok (F-J3-002) | ok·m | harness limit | ok·m | n/c | n/c |
| Upload states (S21) | ok (F-J3-007) | ok·m | ok·m (1280, 1440) | ok | n/c (inactive pairs) | n/c (inactive pairs) | n/c | n/c | n/c |
| Photos browser (S22) | n/c: reads the owner's Photos library, no synthetic seam | n/c | n/c | n/c | n/c | n/c | n/c | n/c | n/c |
| Toolbox menu open (S23) | n/c: harness step reports "toolbox popup not found" (pending 3c) | n/c | n/c | n/c | n/c | n/c | n/c | n/c | n/c |
| Status item (S24) | ok (limit: template glyph tinted by the menu bar, contrast not assessable) | ok·m | n/c | n/c | n/c | n/c | n/c | n/c | n/c |
| About, License (S25) | ok | ok | n/c | n/c | ok·m | ok·m (0 px) | n/c | n/c | n/c |
| Alerts and sheets (S26, S39) | ok | ok | ok·m | ok·m | ok·m | harness limit | ok·m | n/c | n/c |
| Tooltips, drag thumbnail, help bevel (S29, S38) | ok | ok·m | n/c | n/c | ok·m | ok·m | n/c | n/c | n/c |
| Full screen (S11F, S11FP) | n/a | n/a | ok·m | ok (pending 3c) | n/c | n/c | n/c | n/c | n/c |
| Layout budget (LAYOUT) | ok·m | ok·m | ok·m | ok·m | n/c | n/c | n/c | n/c | n/c |

Not captured and why: the native macOS tooltip and the Share picker (`S29`, window-server and out-of-process, recorded as harness gaps), the export save panel itself (`S10`: the modal call returns before a window can be captured, so only the accessory is rendered), the Wipe confirmation (none exists: Wipe acts immediately, recorded by the harness), Photos (above), Font Awesome Pro icons (not bundled), system-owned appearance and accessibility settings (injected only), VoiceOver speech and live screen capture (not provable from renders). Sizes 1024 × 740 and 1440 × 900 exist for the editor (S11M, S11E), History (1120 × 850, 1280 × 800), Settings (1280 variants), Upload (1280, 1440) and the S30-S36 states (1280, 1440); the other surfaces were captured only at their native harness size.

Method note: an automated per-field contrast sweep over the metrics was tried and dropped because the nested sheet frames do not map cleanly to PNG coordinates; every contrast figure above comes from sampling the PNG at a known location.

# E2E audit findings: lane J4 (real-click retest of audit batches 3a, 3b and 3c)

Source revision `94b7aa5` (main after merge of batch 3c). Driver: J4 lane, real clicks and keys through the computer-use driver on two isolated session copies: pid 62733 (`com.shoemoney.opensnap.e2e-62694`, `--seed all`) and pid 70107 (`com.shoemoney.opensnap.e2e-70088`, `--seed history --aws`). Both stopped with "stores unchanged". Screenshots are in `docs/design/evidence/e2e-2026-10-10/j4/` (names below are relative to it, shortened to their number). The live AWS check is logged in `j4-aws-log.md`.

## J4 retest

Result key: PASS = the original steps no longer reproduce the defect and the corrected behaviour was seen in a screenshot or AX read; PARTIAL = part of the fix seen, part not; unverified = not reachable here, reason given. Findings left out on purpose: F-J1-012 (gap), F-J1-023 (deferred), F-J2-024 (doc-only), F-J2-020 (partly deferred, only the stale error was retested).

| Finding | Result | Evidence | Note |
|---|---|---|---|
| F-J1-001 eraser shadow | PASS | `12` | The erased notch is clean white with no grey halo. Side effect: the rest of the cut rectangle lost its shadow (F-J4-007). |
| F-J1-002 swatches | PASS | `01`, `02` | Red and Blue show the check and look like the applied colour. |
| F-J1-003 Custom color… | **PASS (P1)** | `03`, `04` | Black, Custom color…: the Colors panel opens on black (was blue); closing it leaves the colour black. |
| F-J1-004 Resize Return | PASS | `13`, `14`, `15` | OK is the yellow default; Return on a bad width validates, Return on 400 applied and closed (400 × 300). |
| F-J1-005 text Size | **PASS (P1)** | `05`, `06`, `07` | Preset 12 grows glyphs and frame together; the duplicate renders at the same size as the original. |
| F-J1-006 Shadow restyle | **PASS (P1)** | `08`, `10`, `11` | Select All on a red ellipse and a blue outline rectangle (pen blue, size 9), Toolbox › Shadow off and on: only the shadow changed. |
| F-J1-007 Tab trap | **PASS (P1)** | `19` | Focus walked Hide, Toolbox, Photos, Snap, ten tools, Color, Size, Font, canvas, then left the canvas to Undo; no Brush toggle. |
| F-J1-008 full screen item | PASS | `18` | Window menu lists Enter Full Screen; ⌃⌘F (harness maps it to the menu item) entered and left full screen. |
| F-J1-009 Toolbox | PARTIAL | `09` | 18 rows (was 33), a drawing session's commands; still no leading icons. |
| F-J1-010 stale status | PASS | `00`, `21` | Status names the format and is current after full screen and after hide and restore. |
| F-J1-011 crop hint | PASS | `26`, `27` | "Crop: Return applies, Esc cancels"; switching tool drops the overlay. |
| F-J1-013 Photos empty | PASS | `28` | Explanation and both Choose buttons sit inside the grid. |
| F-J1-014 Resize layout | PASS | `13`, `16`, `17` | Mode and dimensions first, presets below, 3 × 3 crop anchor grid, no blank bands in any mode. |
| F-J1-015 paste position | PASS | `23` | Pasted copy is offset from the original. |
| F-J1-016 handles at 25% | PARTIAL | `24` | Handles are about 12 px at 25% as at 100% (fixed screen size); on an 85 px selection they are still large. |
| F-J1-017 command naming | PASS | AX | Edit has Arrange as a submenu and Remove Annotations / Remove Snap Picture; Image no longer holds the arrange commands (AX read of the live menus, not visible in a capture). |
| F-J1-018 full-screen layout | PASS | `18` | Canvas fits at 200%; chrome capped and grouped. |
| F-J1-019 popover dismissal | PARTIAL | `05` | `05` shows the Size popover open with its preset buttons, not closed after a pick; no J4 capture shows either popover dismissing, so the fix is not evidenced yet. |
| F-J1-020 Undo enabled | PASS | `00` | Undo and Remove annotations disabled on a blank canvas. |
| F-J1-021 floppy icon | PASS | `00` | Save is the box-archive glyph. |
| F-J1-022 ⌘M | PASS | `20`, `21` | ⌘M (harness maps it to the menu item) hid the window (tool: window exists but is not on-screen); the status item read Show OpenSnap and restored it. No capture of the hidden state is possible. |
| F-J1-024 Option-Return | PASS | `22` | Option-Return finished "first"; typing "second" made no box. |
| F-J1-025 Add Shadow | PASS | AX | Disabled without a snap. |
| F-J1-026 flip text | PASS | `25` | Shapes mirror, text stays readable. |
| F-J2-001 sheets on the editor | **PASS (P1)** | `31`, `40`, `41`, `42` | Hide, Trash and the Delete key open their sheets on the History window; Escape cancels. |
| F-J2-002 S3 delete | **PASS (P1)** | `69`, `70`, `71`, `j4-aws-log.md` | The app deleted its own S3 object (head-object 404). See the AWS log. |
| F-J2-003 dirty-document guard | **PASS (P1)** | `33`, `34` | Open with unsaved changes asks Save your drawing? on History; Cancel keeps everything. |
| F-J2-004 copy confirmation | PASS | `36`, `37` | "Link copied" and "Image copied" in the History footer. |
| F-J2-005 Unsaved on open | PASS | `35` | Opened entry reads "Saved". |
| F-J2-006 dim canvas | PASS | `35` | Bright after every sheet; not reproduced (no defect seen; the finding was plausible only, so this is an absence of the symptom, not a verified fix). |
| F-J2-007 vocabulary | PASS | `29` | Tabs All, Shared, Exported, Saved match the tiles. |
| F-J2-008 empty states | PASS | `38`, `39` | No-match shows Clear filters and the footer "0 of 5 items". |
| F-J2-009 space | PARTIAL | `29` | The right column now holds a summary; the 880 × 600 minimum reflow was not reachable (no window resize tool). |
| F-J2-010 details clip | PASS | `69` | Destination is middle-truncated. The Date is still tail-cut (F-J4-002). |
| F-J2-011 ⌘1 to ⌘4 | unverified | none | The harness maps ⌘ chords to menu items; ⌘2 would start a real full-screen capture of the owner's display, so none were pressed. |
| F-J2-012 Settings heights | PASS | `43`, `44`, `45`, `48` | Each tab fits its own form; the Upload caption is in view. |
| F-J2-013 sheet vs window | PASS | `49` | Destinations sheet sits inside the Settings window. |
| F-J2-014 Test button | PARTIAL | `50`, `51`, `52`, `54` | WebDAV, SFTP and S3 forms have Test with a "never uploads" line; only the S3 local-validation Test was pressed. FTP and FTPS were not opened. |
| F-J2-015 per-protocol copy | PARTIAL | `50`, `51` | WebDAV and SFTP copy is protocol specific and SFTP has no Endpoint field; FTP and FTPS not opened. |
| F-J2-016 S3 fields | PASS | `53` | S3 placeholders, no "optional". |
| F-J2-017 field names | unverified | none | A filled field still prints as `AXTextField = "value"` with no name in the tool (Name, Region, and the Resize fields); the tool cannot show whether an explicit label exists. Not confirmed fixed. |
| F-J2-018 result band | PASS | `54` | The error band sits above the buttons and the form scrolls above it. |
| F-J2-019 Remove default | PASS | `56` | Remove in the warning colour, Cancel focused. |
| F-J2-020 stale error | PARTIAL | `46`, `47` | Disable All clears the error. The 69-item key menu and the two shortcut surfaces remain (suggestions). |
| F-J2-021 failure text | PASS | `61`, `62` | Inline "Error: Upload failed", Details body has no second prefix and keeps the code (-25300). |
| F-J2-022 outcome line | PARTIAL | `63`, `67` | The success line shows "Link copied" with Open and Copy icons about five seconds after the upload; the 12 s hold, the cancel notice and the Retrying label could not be timed (only one real upload was allowed; Retry failed instantly). |
| F-J2-023 About | PASS | `57`, `58`, `59` | Visible title, reflowed licence, Escape closes About, licence and notices; notices match the shipped Free set. |

Positive controls re-exercised and still working: drawing an ellipse, rectangle and arrow, Select All, Duplicate, Copy and Paste, Undo, Resize (Resize and Limit applied), Crop overlay, zoom 25%, Flip, History search and Clear filters, Hide with confirm, Copy and Copy Link, Settings tabs, Destinations Add forms, About, an S3 upload with link copied.

**Known open item (fractional size): not reproduced in real use.** Every size seen in real use was an integer: the title and status line (400 × 300, 900 × 600, 1011 × 758), the Resize fields (Limit 1011 on 800 × 600 gives Width 1011, Height 758, not 758.25), and History Details for a real saved drawing (`73`, 1,011 × 758). The only fractional size ever seen was the harness-saved entry in J2, so it comes from that fixture, not from the app's own save path.

## New findings

### F-J4-001 · P3 · The Destinations list shows the cancelled form's stale Test error
- **Surface:** Settings › Upload › Manage Destinations… › Add… › S3 form
- **Steps:** choose S3-compatible, Access key source, press Test with the keys empty (error band appears), press Cancel.
- **Observed:** back on the list the same red "Error: Enter the access key ID and secret…" line is drawn under the buttons, half clipped by the Done bar, and the sheet grows a vertical scrollbar (`55-NEW-…jpg`). Pressing Done and reopening the sheet clears it (`60-…jpg`). The AX tree of the list sheet contains the error text.
- **Expected:** Cancel clears the form's result band; the list shows no error.
- **Suggested fix:** clear the result text when the form is dismissed (or give the list its own status label).

### F-J4-002 · P3 · History Details clips the Date for two-digit days
- **Surface:** History › Details
- **Observed:** "October 10, 2026 at 6:49…" (`30-…jpg`, `69-…jpg`) while "October 7, 2026 at 5:49 AM" fits (`36-…jpg`); the AM/PM is lost on every day from the 10th.
- **Suggested fix:** shorten the format (for example "Oct 10, 2026, 6:49 AM"), wrap the line, or middle-truncate.

### F-J4-003 · P3 (observation) · After Delete from Web the public link still answers 200
- **Surface:** History › Delete from Web, S3 behind CloudFront
- **Observed:** head-object returned 404 at 11:50:56Z but `curl -sI https://cdn.shoemoney.com/pics/…png` kept returning 200 with `x-cache: Hit from cloudfront` (age 69 s and still 200 20 s later). The app has no after-delete notice in the History footer (`71-…jpg`).
- **Expected:** the user is told the origin object is gone and that a CDN may keep serving it until its cache expires.
- **Suggested fix:** a one-line notice after a successful delete ("Removed from the server. A CDN may keep serving it for a while.").

### F-J4-004 · P3 · A Shared entry's Details report the later, resized size
- **Surface:** History › Details
- **Steps:** upload an 800 × 600 drawing to S3 (entry Untitled · Shared, Size 800 × 600, `69-…jpg`); resize the same document to 1011 × 758; Save to History.
- **Observed:** two entries exist (a new Untitled · Saved and the earlier Untitled · Shared); the Shared one now reads Size 1,011 × 758 (`72-NEW-…jpg`) although the published PNG is 800 × 600.
- **Expected:** the Shared entry keeps the size it was published at, or Details says it describes the editable copy.
- **Suggested fix:** show the publication's recorded size for the Shared action, or label the field.

### F-J4-005 · P3 · The Delete from Web confirmation focuses the destructive button
- **Surface:** History › Delete from Web sheet
- **Observed:** AX marks Delete from Web focused on the sheet (`70-…jpg`), while the Remove-destination sheet focuses Cancel (`56-…jpg`). Return on the first deletes a server file.
- **Suggested fix:** focus Cancel on every destructive sheet.

### F-J4-006 · P3 · A freshly opened History entry shows the previous document's size for a moment
- **Surface:** editor title and status line after History › Open
- **Observed:** right after Don't Save the title read "Quarterly mockup – 400 × 300 · PNG" and the status "Brush · Saved · 400 × 300" while the canvas already showed the 900 × 600 entry at 79% (`75-NEW-…jpg`); a second later both read 900 × 600 · PNG · 57 KB (`35-…jpg`).
- **Suggested fix:** compute the size text from the loaded document before the first draw.

### F-J4-007 · P3 (design check) · Erasing a corner of a shape removes the shadow from the rest of it
- **Surface:** Eraser tool
- **Observed:** after one erase stroke across the top edge of the blue rectangle the remaining pieces draw without the drop shadow while the neighbouring ellipse keeps its shadow (`12-…jpg`). This follows the batch-3a rule "erased fragments of a real cut are unshadowed" (test `72ecadb`), so it may be intended.
- **Suggested fix:** if intended, say so in the Eraser help; if not, keep the shadow on cut fragments and only skip it for the erase stroke itself.

## Harness notes for the next driver

- The session window is often not key (grey title): AX presses and `window_id` clicks work, plain clicks on sheet controls are swallowed, and the first drag after a tool switch is dropped (draw again). A real drag on the canvas makes the window key; Tab, ⌘ chords through menu mapping and Escape then work.
- `get_app_state … rect` is ignored for images; use AX filters (`ax_filter`) to keep output small.
- Menu-bar pick commits only while the app is active; the status item menu committed with Return.

## Unverified and why

F-J2-011 (⌘1 to ⌘4, see above), F-J2-017 (tool cannot show labels), F-J2-009 minimum-size reflow (no resize tool), FTP and FTPS destination forms (not opened), the Retrying label and Upload cancelled notice (needs a slow network), the 12 s success-line hold (only one upload allowed), and the clipboard: it held no text before the run, so non-text contents (if any) could not be saved; it was reset to empty text at the end.

## J5 gap closure

J5 lane, build e953411, three isolated sessions (pid 70334 seeded `all`, 86919 seeded `history` for the no-destination rows, 23880 seeded `empty` for the Fonts panel and zoom labels). Every row that was `unverified` was either exercised by real input and set to E2E with a viewed screenshot, or given exactly one gap reason in its notes and left `unverified`. The matrix `gap` column is regenerated from `tools/e2e-inventory.py` and was not touched; the J5 reason class is the first words of the `observed` cell (`J5 lane: gap: <reason>.`). Evidence is in `docs/design/evidence/e2e-2026-10-10/j5/` (48 jpg plus `44-ax-and-state-readouts-j5.txt`).

### Counts

| Evidence class | before J5 | after J5 |
|---|---|---|
| E2E | 258 | 305 |
| rendered | 94 | 94 |
| unit/source | 91 | 91 |
| unverified | 146 | 99 |
| total | 589 | 589 |

47 rows moved to E2E, 99 stay `unverified` with an explicit reason:

| Gap reason | rows | what it covers |
|---|---|---|
| `gap: unsafe` | 36 | capture items and shortcuts that grab the owner's display (Crosshair, Fullscreen, Window, Frame Snap, Timed, Snap…, ⌘1–⌘4, Shift/Option capture gestures), Hide Others / Show All, global-hotkey firing and the live Settings › Capture shortcut controls (system-wide registration), Move to Trash, Open Link, uploads and web deletes (network), Cancel Upload |
| `gap: harness` | 32 | synthetic right-click context menus (History, text annotation), held modifiers and keys (Space, Shift, Option), file drop and cross-app drag-out, menu picks while the app is inactive (Spelling), clicks swallowed when the window is not key (Group/Ungroup, missing-file selection, shortcut sheet segments), full-keyboard sweeps, announcements, VoiceOver, menu check marks, the navigator panel, the dead circle-exclamation icon |
| `gap: OS-owned` | 22 | Open, Save, Export and Print panels and the Export accessory (out-of-process panel service, invisible to the harness), Photos/Pictures folder choosers, share picker, Spelling panel, Colors panel modes |
| `gap: hardware` | 5 | multi-display, 1x display, printer |
| `gap: permission` | 4 | Screen Recording capture rows, Photos Library |

### What changed to E2E (47)

Capture menu Frame Snapshot, Cancel Frame, Snap from Link (a synthetic page on 127.0.0.1) and its sheet; Timed Snapshot sheet; Hide OpenSnap (⌘H) and the status item Show / Settings…; Arrow Head At End; Edit › Remove Annotations, Remove Snap Picture, Arrange › Bring to Front and Send to Back; zoom pop-up Actual Size, the Overview navigator (appears, follows the wheel), canvas border handles; Upload menu destination row, Destination Settings…, No destination configured and Upload with no destination; Fonts panel Text outline, Text shadow and Default Text Style; History Drag as JPG, TIFF, SVG, tile double-click, the selected-tile circle-check badge; Resize or Crop Limit by, anchors and validation message; Page Setup; ⌘, ⌘C ⌘X ⇧⌘P ⌘W ⌘H and ⌘D on the Save your drawing? sheet; Settings Esc and ⌘W; default window size; dirty then Save; AX names, roles and states of the icon-only controls; the Toolbox menu rows.

### Re-check after batch 4

These rows were tested against the current behaviour and need a second look once the batch 4 changes land: E2E-MENU-004 note and E2E-HOT-016 (app-menu Capture Shortcuts… still opens the sheet; the idle sheet shows no status line, only the pause note and the Original Frame footnote, `19-…jpg`), the Capture tab in Settings (`18-…jpg`), destination form heights (not opened this run), History empty states (not reached) and the Resize glyph (not compared).

### New findings

### F-J5-001 · P3 · Timed Snapshot throws away an invalid delay without a word
- **Surface:** Capture › Timed Snapshot…
- **Steps:** open the sheet (Delay in seconds, default 6), replace the value with `abc`, press OK.
- **Observed:** the sheet closes, nothing starts, no message or status line explains it (`04-…jpg`, `05-…jpg`). The code accepts 0 to 120 only and returns silently for anything else.
- **Expected:** keep the sheet open with an Error: line the way Resize or Crop does (`34-…jpg`: "Enter whole pixel dimensions from 1 to 16,384."), or at least a status notice.
- **Suggested fix:** validate in the sheet and show the range (0–120 s) before closing.

### F-J5-002 · P3 (observation, may be the harness) · ⌘D does not answer the Save your drawing? sheet that is attached to History
- **Surface:** History › double-click a tile while the editor is dirty
- **Steps:** double-click a tile; the sheet appears on the History window; press ⌘D (the Don't Save equivalent that works on the editor-attached sheet, `08-…jpg`).
- **Observed:** the sheet stays (`27-…jpg`); pressing the Don't Save button through AX worked and opened the snap (`28-…jpg`). The History window was not key when ⌘D was posted, which may be why.
- **Expected:** the same key equivalents on both hosts.
- **Suggested fix:** confirm with a real key press; route AppAlert key equivalents through the sheet's own window, not the key window.

### F-J5-003 · P3 · Save to History on a blank canvas does nothing and says nothing
- **Surface:** Edit/File › Save to History and the bottom-bar Save
- **Steps:** Snap from Link, then Remove Snap Picture and Remove Annotations so the canvas is blank white; press Save to History (menu and button, twice).
- **Observed:** no new History entry (History still shows 6 items), status stays "Select · Unsaved changes", no notice (`22-…jpg`, History count unchanged in `23-…jpg`). With a picture plus drawings the same action works and reads "Saved to History" (`29-…jpg`).
- **Expected:** either save the blank document or say there is nothing to save.
- **Suggested fix:** add a status notice for the refused case.

### F-J5-004 · P4 · Upload with no destination shows an empty list and no explanation
- **Surface:** bottom-bar Upload with nothing configured
- **Observed:** the Upload destinations sheet opens with a blank list box, Add… enabled and the help line "The one marked Default receives an Upload click" (`42-…jpg`); nothing says that no destination is configured (the menu does say No destination configured).
- **Suggested fix:** show an empty-state line such as "No destinations yet. Add one to upload."

### F-J5-005 · P1 (root cause found and fixed in the launchers, see "Root cause" at the end of the investigation) · The Open/Save panel service grows to ~66 GB when the isolated copy shows a system panel
- **Surface:** ⌘E Export…, ⌘O Open…, ⌘S / ⇧⌘S Save (system panels, out-of-process `com.apple.appkit.xpc.openAndSavePanelService`)
- **Steps:** in session 70334 press ⌘E, ⌘O, ⌘S, ⇧⌘S in turn, each dismissed with Esc or ⌘. after 3–6 s.
- **Observed:** the app's AX tree collapses to one element while a panel is open and the panel is not visible to the harness. The ops log sweep (a peer session's message, not measured by this lane) reports the panel service footprint reaching ~66 GB within about two minutes, twice (07:26:29 and 07:31:04 CDT), ~52 GB of swap and free disk falling from 87 to 34 GiB; ops killed pids 77714 and 98463. This lane's own sample at 07:29 was pid 77714 at 57 % CPU and 3.3 GB resident. After that report this lane opened no further system panels (the Open Folder, Photos and Export accessory rows are therefore `gap: OS-owned`). The panel also registered `com.apple.xctest.FakeForceTouchDevice` (ops note).
- **Expected:** a normal panel footprint (tens of MB).
- **Suggested fix:** reproduce with `NSSavePanel` and no accessory view, then with the Export accessory, on the same macOS build, to separate an OpenSnap hand-over (accessory, preview image, directory URL) from a beta-OS bug; keep the ops watchdog (8 GB kill) in place for any future run that opens a system panel.

### F-J5-006 · P4 (observation) · The circle-exclamation icon has no call site
- **Surface:** E2E-ICON-026
- **Observed:** `FAIcon.warning` (circle-exclamation) is defined in `FontAwesomeIcons.swift` and mapped in `FontAwesomeFree.swift`, but no source file uses it, so no UI state renders it and the row cannot be exercised. Errors use circle-xmark.
- **Suggested fix:** drop the case or wire it where a warning (not failure) is shown.

### F-J5-007 · P4 · Inventory names for three rows do not match the build
- **Surface:** coverage matrix E2E-MENU-088 (Clear Image), E2E-HARN-001 (More Commands), E2E-HARN-002 (Wipe Snap Only)
- **Observed:** the live Edit menu item is Remove Annotations, the bottom-bar button reads Remove annotations (AX also keeps "Clear image" on its disabled state), the Toolbox button is AXMenuButton "Toolbox menu" and its wipe row is Remove Snap Picture; no menu or button is named More Commands or Wipe Snap Only (`44-…txt`).
- **Suggested fix:** rename in `tools/e2e-inventory.py` at the next regenerate (docs lane).

### Harness notes for the next driver (J5 additions)

- Menu picks commit ~3 s after the AX press and only while the app is active; indexes in the AX tree drift between menu opens, so re-query the menu item right before each press. A stale index silently presses a neighbouring item (this duplicated a rectangle once).
- `AXShowMenu` on the Upload button opens the destinations menu without uploading (AXPress uploads); the AX press error code returned is misleading, the menu opens anyway.
- `type_text` can report "not delivered, window occluded" while the text arrives; check the screenshot.
- System panels (Open, Save, Export, Print) are out of process: the app's AX tree shrinks to one element and the harness cannot see or click them; ⌘. dismissed the print panel when Esc did not. Page Setup is in-process and visible. **Superseded by the F-J5-005 root cause:** that invisibility was the runaway service spinning before it could draw; with a normalized session home the Open, Save and Export panels are visible and clickable through the driver (a Cancel click needs a fresh AX snapshot, and a background Escape does not reach a panel while the window is occluded).
- The owner's other windows can occlude the isolated window, after which menu bar picks are refused ("background app") and clicks are swallowed; a real drag makes the window key for one or two calls.
- After a stop, the real-store compare may list `com.shoemoney.opensnap.eyedump-<pid>.plist` files: during this run pids 6797 and 6799 were live `tools/eye-dump-audit.sh` processes of the batch 4 lane (`/tmp/a4/ev/...`), so the plists are theirs and were not deleted. Sessions 86919 and 23880 stopped with "stores unchanged"; 70334's compare listed only those two plists.

### Clipboard

The pasteboard held no text before the run (`pbpaste` returned 0 bytes; any non-text contents could not be saved). ⌘C, ⌘V and ⌘X were used once each on a synthetic rectangle; the clipboard was reset to empty text at the end (`pbpaste` = 0 bytes).

## F-J5-005 investigation

**Question.** Why did the Open/Save panel service (`com.apple.appkit.xpc.openAndSavePanelService`) reach ~66 GB when ⌘E, ⌘O, ⌘S were pressed in the isolated copy? Candidates: (A) the `env -i` / fake-HOME launch from `tools/e2e-session.sh`, (B) OpenSnap's panel configuration, (C) a macOS 27 beta bug.

**Update, same day: reproduced on the real app, see "Controlled live trial" below.** The paragraph that follows is the probe-only conclusion.

**Conclusion: inconclusive, with (A) and (B) ruled out as sufficient causes.** 39 bounded trials on the same machine and OS build (Darwin 27.2) never moved the service off ~85–116 MB, in either environment, with OpenSnap's exact panel configurations, with an Accessibility client attached, and with four panels back to back. The 66 GB case therefore needs something the probe does not have: the real OpenSnap process, or the real-click harness's input and capture path. Confidence that the env and the panel config are not the cause: high. Confidence in any specific cause: low.

### Method

- A throwaway app (`panel-probe/probe.swift`, 64 lines, kept out of the app target) opens one system panel with `runModal`, cancels itself with `cancel(nil)` after 5 s and exits. A failsafe exits at `seconds + 6`.
- Modes: `open-basic` (`NSOpenPanel()`), `open-opensnap` (`allowedContentTypes = [.image, .pdf, UTType(exportedAs: com.shoemoney.opensnap.document)]`, single selection, App.swift `openFile`), `save-basic` (`NSSavePanel()`), `save-opensnap` (`Untitled.opensnap`, `[document type]`, App.swift `save`), `export-opensnap` (title, label, prompt, `allowsOtherFileTypes = false`, PNG content type, and a 600 pt wide accessory stack with the same controls as `ExportAccessory`: heading, format popup, quality line, checkbox, two wrapped labels with a 60 pt minimum), `sequence` (export, open, save, save-basic in one process, 4 s each).
- The probe bundle carries the same `CFBundleDocumentTypes` and `UTExportedTypeDeclarations` as `build/OpenSnap.app`, is copied into a fresh directory per trial, gets a throwaway bundle id (`com.shoemoney.panelprobe-<pid>-<n>`) and an ad-hoc signature, and is exec'd directly like the launcher does. It never touches OpenSnap's bundle ids, defaults domains, Application Support or the Keychain.
- Safety: a watchdog (`ps` every 0.5 s, `kill -9` above 2 GB, log to `watchdog.log`) ran for the whole experiment; the runner also checked `memory_pressure` (free < 30 %) before each trial and had its own 2 GB kill. Conditions ran strictly one at a time, at most 3 trials per mode.
- Conditions: **normal** (inherited shell environment, real HOME); **isolated** (exactly the launcher's `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=$T/home CFFIXED_USER_HOME=$T/home TMPDIR=$T/tmp OPENSNAP_APP_SUPPORT=$T/support`, fresh `$T` per trial, deleted after); **isolated+ax** (isolated, plus a read-only Accessibility walker over the probe and the panel service, depth ≤ 8, ≤ 400 nodes, every 0.4 s, which is what a computer-use harness does); **isolated+ax+esc** (as isolated+ax, with a real Esc key event posted only to the probe's pid every 4.5 s, and the `sequence` mode).
- Per trial the runner recorded peak service RSS and CPU (`ps`, every 0.25 s), whether a service process and panel windows existed (read-only `CGWindowListCopyWindowInfo`), whether the auto-cancel returned, and whether the service was gone a second after the probe exited.

### Results (39 trials)

| Condition | Mode | Trials | Peak service RSS (MB) | Peak CPU (%) | Service seen | Panel window seen | Auto-cancel returned | Watchdog fired |
|---|---|---|---|---|---|---|---|---|
| normal | open-basic | 3 | 88.8–91.2 | 175–182 | 3/3 | 3/3 | 3/3 | 0 |
| normal | open-opensnap | 3 | 90.3–91.2 | 171–182 | 3/3 | 3/3 | 3/3 | 0 |
| normal | save-basic | 3 | 85.3–85.5 | 137–160 | 3/3 | 3/3 | 3/3 | 0 |
| normal | save-opensnap | 3 | 84.2–85.5 | 148–168 | 3/3 | 3/3 | 3/3 | 0 |
| normal | export-opensnap | 3 | 84.7–86.3 | 145–161 | 3/3 | 3/3 | 3/3 | 0 |
| isolated | open-basic | 3 | 90.7–90.9 | 161–172 | 3/3 | 3/3 | 3/3 | 0 |
| isolated | open-opensnap | 3 | 89.5–91.2 | 170–182 | 3/3 | 3/3 | 3/3 | 0 |
| isolated | save-basic | 3 | 84.6–85.9 | 151–155 | 3/3 | 3/3 | 3/3 | 0 |
| isolated | save-opensnap | 3 | 84.6–86.6 | 148–156 | 3/3 | 3/3 | 3/3 | 0 |
| isolated | export-opensnap | 3 | 86.2–86.6 | 149–157 | 3/3 | 3/3 | 3/3 | 0 |
| isolated+ax | open-opensnap | 3 | 92.3–92.6 | 162–176 | 3/3 | 3/3 | 3/3 | 0 |
| isolated+ax | export-opensnap | 3 | 87.3–88.0 | 148–168 | 3/3 | 3/3 | 3/3 | 0 |
| isolated+ax+esc | sequence (4 panels) | 3 | 114.1–116.2 | 150–165 | 3/3 | 3/3 | 3/3 | 0 |

The peak CPU is the panel's first-second launch burst (a few samples), not a sustained load. In every trial the service process was gone within a second of the probe cancelling. The 448 watchdog samples never exceeded 119 MB. Watchdog firings: **0**. No condition was stopped early.

### What the trials do show

- The panels are visible to a window-list query in every condition: an "Open and Save Panel Service" window (layer 8, titled Open or Save) plus the probe's own panel window. So the panel being invisible to the harness in J5 is a property of the harness, not of the isolated environment.
- With a panel open the probe's AX tree grows from ~91 to ~112 (save, export) or ~391 (open) nodes and the service itself exposes 1 element. That matches the J5 observation that the app's tree "collapses to one element" while a panel is up.
- The service's `CoreUI ... myDocuments.cannedSearch` faults and the `com.apple.dt.xctest` "test daemon" registration also appear in the healthy probe runs, so they are not the cause. The `FakeForceTouchDevice` registration noted by ops was not reproduced by the probe.

### What the incident log adds (not reproduced)

`log show` for 07:25–07:33 CDT on 2026-10-10 shows service pid 77714 starting 07:26:29 and still alive at 07:30:22 when ops sent SIGTERM; it then logged "Remaining transactions after SIGTERM: 9 (5 os_transaction + 4 xpc_transaction_begin)" 60 times without exiting. Pid 98463 ran 07:31:04–07:31:15. A healthy service exits within a second of the panel closing, so in the J5 session the panel was **not torn down** after the Esc / ⌘. presses even though the lane believed it had dismissed it. The leading explanation is that the panel stayed open and wedged in the ViewBridge / event path while the driver kept sending events, but this is inference from the log, not a measured cause.

### Recommended next steps

1. No change to `tools/e2e-session.sh`'s environment is justified: the launcher's `env -i` set is not the trigger, so adding USER, LOGNAME, SHELL or XPC variables would be a guess. Nothing was implemented there.
2. Keep the ops watchdog (it worked: it is what ended both runaway services) and have every future lane that opens a system panel start one first. A cheap place for it is `tools/e2e-session.sh start` (a background loop killing any `openAndSavePanelService` above 2 GB, stopped by `stop`), with a test in `tools/test-e2e-session-guard.py`. It is a small, separate change.
3. To close the gap, run the one experiment this lane was not allowed to run: the real isolated OpenSnap copy, one ⌘O, with the 2 GB watchdog already up, dismissed by `cancel` from a debugger-free timer rather than by the driver. If the service stays small, drive the same panel with the real-click harness; the harness's input path (the `FakeForceTouchDevice` registration is an XCTest signature) is then the remaining suspect. If the service grows without a harness, the cause is in the real process (document state, history, canvas) and the probe should be extended with those.
4. Until then treat ⌘E, ⌘O, ⌘S, ⇧⌘S as `gap: harness` rows in the matrix, not as an OpenSnap defect: nothing in OpenSnap's panel configuration reproduced the growth.

The probe source is `docs/design/e2e/panel-probe/probe.swift`; build with `swiftc -O probe.swift`, wrap in an `.app` carrying OpenSnap's document-type keys, and run `PanelProbe <mode> [seconds]`.

### Controlled live trial (watchdog up, real OpenSnap, one ⌘O)

The experiment step 3 above asked for, run after the launcher watchdog was implemented. `sh tools/e2e-session.sh start --seed empty` (an isolated copy, so `env -i` and the throwaway HOME as before) with the watchdog (SIGKILL above 2 GB, checked every 0.5 s) running; one ⌘O sent to the app's pid through the real-click driver; panel-service RSS and CPU and the window list sampled (`ps` plus read-only `CGWindowListCopyWindowInfo`, `panel-probe/trials/sampler.py`). Memory free stayed at 80-82 % (hard stop was 30 %). The machine was idle (no other test run) for both trials.

| Trial | Sample step | Baseline | Service appears | RSS over time | CPU | Watchdog | Dismissal | Service gone |
|---|---|---|---|---|---|---|---|---|
| 1, ⌘O | 1 s | no service, 1 app window | t+8 s, 88 MB | 88 MB, then 1322 MB one second later, then killed at 2506 MB | 29 %, then 97 % | SIGKILL at 08:12:33 (rss 2,505,616 KB) | none possible: the service was already gone, the Open window disappeared with it | yes, killed |
| 2, ⌘O (same session) | 0.25 s | no service, 1 app window | t+4.0 s, 33 MB | 33, 291, 625, 923, 1218, 1544, 1820, 2123, 2425 MB at 0.25-0.3 s steps, then killed at 2516 MB | 56 % rising to 100 % | SIGKILL at 08:14:21 (rss 2,515,968 KB) | none possible, as above | yes, killed |

Growth is roughly linear at **1.1-1.2 GB per second** at 100 % CPU, starting the moment the panel appears. The 2 GB threshold is crossed about 2 s after ⌘O, so the watchdog's 0.5 s poll reacts in time and no human or driver dismissal step (Esc, clicking Cancel) can land first: the three dismissal steps in the plan (Esc, Cancel button, `stop`) were not meaningfully testable, because the watchdog had already ended the service each time. After the kill the app stayed responsive (a window "Untitled", the AX tree normal) and `stop` ended it with SIGTERM in 1 s. The session's real-store compare said "stores unchanged" and no preference plist or temp dir was left. ⌘S was not run: the plan only repeated with ⌘S when the first trial stayed under 500 MB, and ⌘O reached 2.5 GB.

### Conclusion

1. **The growth is real and reproduces 2 of 2 on the real isolated OpenSnap process with one ⌘O**, on macOS 27 (Darwin 27.2). The J5 observation (and the ~66 GB figure) is therefore not a one-off.
2. **It is not the launcher's environment and not OpenSnap's panel configuration alone.** The probe used the same `env -i` environment and the same allowed content types and never left 119 MB in 39 trials. What differs now: the real OpenSnap process (its `runModal` is called inside `withFrameWindowValuesSuspended`, with a document and an editor window behind it) and the real-click driver's key path, which performs the matching menu item through Accessibility instead of posting a key event. These two are not separated yet. A probe with a File > Open… menu item, driven by the same driver, would split them; that is the one remaining experiment and it needs the watchdog first.
3. **The launcher watchdog is now the mitigation, and it is sufficient for safety.** At 1.1-1.2 GB/s from a 2 GB threshold and a 0.5 s poll the service is killed at about 2.5 GB instead of reaching the ~66 GB seen in J5. It is built into `tools/e2e-session.sh start` (see the script header and `tools/test-e2e-session-guard.py`), logged to the session and printed by `stop`. A lane that opens a system panel without a session started by `start` is still unprotected.
4. **Matrix.** ⌘E, ⌘O, ⌘S and ⇧⌘S (E2E-KEY-007, -004, -005, -006) are `gap: harness`: an open/save panel cannot be viewed or dismissed through the real-click driver until the cause is found. They are not marked E2E because nothing was viewed. Until an app-side cause is known, do not describe this as an OpenSnap defect or as a macOS defect.

Evidence: `panel-probe/trials/` holds the two sample logs, the sampler and the watchdog's kill log.

## Ledger corrections after review round 1

An independent review found class inflation in `coverage-matrix.md`. Changes (the generator keeps the edited cells; `python3 -I tools/e2e-inventory.py --check` passes):

- **AX presence is not a render.** 23 rows classed `rendered` that cite only `j1/menus-ax-dump.txt` ("present … not pressed") are now `unverified` with "gap: AX presence only": MENU-007, 009, 010, 013, 014, 015, 016, 020, 021, 023, 029, 030, 032, 033, 039, 047, 048, 049, 062, 063, 068, 069, 076.
- **No screenshot of the claim.** BAR-034 and BAR-035 (AX value only; the cited image shows 50%), BAR-041 and A11Y-003 (cite only a text readout) moved from `E2E` to `unverified` with the reason in `observed`.
- **Entry path substituted.** MENU-001, 006, 019, 022 and 059 were pressed through the Toolbox pop-up, not the menu bar item; the rows now say so.
- **Stale rows.** DEST-036 now records the J4 pass (the app deleted its own S3 upload from History › Delete from Web; `j4/69`–`71`, `j4-aws-log.md`) beside the J2 refusal. DEST-010 is marked "re-check after batch 4" (pre-batch-4 SFTP form). SHEET-002 to SHEET-006 said "pending batch 3c": they now say they were drawn on the pre-3c sheet and need a re-check. MENU-004 is `unverified` (it observed the Capture Shortcuts sheet, removed in d9ed8b7; the entry now opens Settings › Capture). HOT-001 to HOT-018 (the removed sheet) are marked retired, and HOT-041 is the new row for the menu entry. HIST-003 to HIST-005 keep their IDs and evidence under the current tab names (Shared, Exported, Saved).
- **J4 retest table.** F-J1-019 is PARTIAL (the cited image shows the popover open). F-J2-006 reads "not reproduced (no defect seen)", which is an absence of the symptom, not a verified fix.
- **Class counts** (589 rows): `E2E` 304 → 299, `rendered` 94 → 71, `unit/source` 91 → 91, `unverified` 101 → 129.

### Root cause (found 2026-10-10, same day): a non-normalized `CFFIXED_USER_HOME`

**The service loops because the app was launched with `CFFIXED_USER_HOME=/var/folders/…/T//e2e-session.XXXXXX/home` (a double slash).** macOS 27.2 beta's `com.apple.appkit.xpc.openAndSavePanelService` takes `CFFIXED_USER_HOME`, `HOME` and `TMPDIR` from the app that opens the panel, and on a path containing `//`, `/./` or `/../` it never leaves the first `_CFURLIsProtectedDirectory` call: it keeps taking the parent of the URL (`CFURLCreateCopyDeletingLastPathComponent`), adding each result to a set, and never reaches the root. Memory grows ~1.2 GB/s at 100 % CPU; the panel UI never finishes loading, which is why J5 saw an empty AX tree and could not dismiss anything. The path got its `//` because `tools/e2e-session.sh` (and `tools/eye-dump-audit.sh`) build the session dir as `mktemp -d "${TMPDIR:-/tmp}/…"` and macOS `$TMPDIR` ends in `/`. Nothing in OpenSnap is involved: the probe app reproduces it with a plain `NSOpenPanel()`.

**Evidence.**
- `sample` of the growing service (1 s, 650 samples): one thread, every sample under `NSRemoteSavePanel initWithOptions:` → nib load → `FITagEditorView` → `FinderKit` → `TNode::Initialize` → `TFSVolumeInfo::AddVolume` → `_CFURLIsProtectedDirectory` (a `dispatch_once` block) → `CFURLCreateCopyDeletingLastPathComponent` + `CFBasicHashAddValue`.
- `ps eww` of the service: it carries `CFFIXED_USER_HOME`, `HOME` and `TMPDIR` of the client (healthy run: `/tmp/pf/man.X/home`; runaway run: `…/T//man.X/home`).
- Isolating one variable at a time on a bare OpenSnap with no delegate, each in a fresh `env -i` launch: `//` in `CFFIXED_USER_HOME` alone reproduces; `//` in `HOME` alone or in `TMPDIR` alone does not; a trailing slash does not; `/./` and `/x/../` do; a leading `//` does; the same `/var/folders` location with a single slash does not.
- The stock probe reproduces with `CFFIXED_USER_HOME=…//home` (2 GB, watchdog kill) and is fine with the same path normalized, so it is an OS bug triggered by the client's environment, not an OpenSnap defect.
- An in-process `setenv("CFFIXED_USER_HOME", normalized)` before opening the panel does **not** help (the service still sees the launch-time value), so the app cannot defend itself; the fix has to be where the app is launched.

**Why the earlier probe never reproduced.** Its trials put `$T` under `/tmp` (or a TMPDIR with the slash stripped), so the path never had a `//`. The real launcher used the raw `$TMPDIR/` prefix.

**Fix (efb8e1c).** `tools/e2e-session.sh` and `tools/eye-dump-audit.sh` canonicalize the session dir right after `mktemp` (`TMP=$(CDPATH= cd -- "$TMP" && pwd -P)`), so HOME, CFFIXED_USER_HOME, TMPDIR and the support folder passed to the app are normalized. No source change in the app. Tests: `tools/test-e2e-session-guard.py` now runs every launch with a trailing-slash TMPDIR (what macOS does) and `test_normalized_home` asserts the app saw a normalized CFFIXED_USER_HOME, HOME and support path; the same assertion is in `tools/test-eye-dump-audit-guard.py`. Both have a can-fail mutant (the script copy without the canonicalizing line) that must produce a `//` path and turn the check red; both mutants went red and the real scripts green. `tools/panel-service-check.sh` is a manual live check (not in `tools/test.py`): it opens one real panel from the probe under the launcher's isolation with the 2 GB watchdog, `sh tools/panel-service-check.sh` expects a peak under 300 MB and `--reproduce` deliberately passes a `//` home and shows the OS bug is still there on this build (peak 2.1 GB, watchdog kill).

**Hypotheses tested and rejected.** LaunchServices pollution (the orchestrator's lead): 764 throwaway-id references and 208 registered paths of deleted throwaway copies were unregistered with `lsregister -u` (only paths under `eye-dump-audit.*`, `e2e-session.*`, `opensnap-startup-*`, `e2e-probe.*`); the next trial still reached 2.67 GB, so it is not the cause (the stale registrations are untidy but harmless here). Link target (probe built `-target arm64-apple-macosx26.0`): 86 MB. App icon/`Assets.car` (probe inside a full copy of the app bundle): 89 MB. WebKit/ImageIO linked into the probe: 88 MB. Panel configuration (content types, accessory): a bare `NSOpenPanel()` in the app grows identically. Main window, activation policy, status item: no effect. App launch stages (menus, window, observers, status item, policy, hints, hotkeys, end): all fine when the home is normalized. Driver input: the in-app auto-panel (no driver) already reproduced.

**Trials** (every run behind the 2 GB watchdog; free memory stayed ≥ 80 %; "killed" = the watchdog ended it, so the peak is just past 2 GB):

| # | Condition | Panel service peak |
|---|---|---|
| 1 | Session + in-app auto-panel, `openFile()`, no driver | killed at 2.1 GB (~1.1 GB/s) |
| 2 | Same after unregistering 208 stale LaunchServices paths | killed at 2.67 GB |
| 3 | Same, `sample` taken at 0.5 s | killed at 2.35 GB; stack above |
| 4 | Probe `-target 26.0`; probe in full app bundle; probe + WebKit/ImageIO (isolated, `/tmp`) | 86 / 89 / 88 MB |
| 5 | Plain `NSOpenPanel()` inside the app (session) | killed at 2.4 GB |
| 6 | Same plus close all windows / accessory policy / no status item | 2.1 / 2.1 / 2.05 GB (killed) |
| 7 | Bare OpenSnap, no delegate (`/tmp`) | 88 MB |
| 8 | Launch stages menus, window, observers, status item, policy, hints, pre-status, pre-show, shown, hotkeys, end (`/tmp`) | 87-97 MB (11 runs) |
| 9 | Full launch + late timer trigger; same orphaned with nohup (`/tmp`) | 90 / 90 MB |
| 10 | Launcher-like: under `$TMPDIR` + numeric id | killed at 1.9 GB |
| 11 | Path only (`$TMPDIR`, other id) / id only (`/tmp`) / name only (`/tmp`) / `$TMPDIR` with a different name | 1.97 GB killed / 89 / 89 / 2.2 GB killed |
| 12 | Bare OpenSnap under `$TMPDIR`, stages bare … end | 1.9-2.4 GB killed (6 runs) |
| 13 | Probe under `$TMPDIR` with the slash stripped (full bundle, plain and configured panel) | 88 / 87 MB |
| 14 | Probe with `CFFIXED_USER_HOME=…//home` | killed at 2.0 GB |
| 15 | `//` in HOME only / CFFIXED only / TMPDIR only / all three | 88 MB / 1.87 GB killed / 90 MB / 1.99 GB killed |
| 16 | CFFIXED forms: trailing `/`, `/./`, `/x/../`, leading `//`, mid `//` | 90 MB / 2.4 GB / 1.87 GB / 1.88 GB / 1.85 GB (last four killed) |
| 17 | Runtime `setenv` of the normalized value before the panel (2 runs) | killed at 2.4 / 2.3 GB (service env unchanged) |
| 18 | `$TMPDIR` location with the slash stripped | 90 MB |
| 19 | Fixed launcher: in-app auto-panel Open / Save / Export, each cancelled with `cancel(nil)` after 3 s (`runModal` returned at 3.02 s) | 94 / 87 / 88 MB, kills 0 |
| 20 | Fixed launcher, real-click driver, one press each: ⌘O, ⌘E, ⌘S, ⇧⌘S, dismissed with a Cancel click | 89 / 77-86 / 89 / 90 MB, kills 0 |
| 21 | `tools/panel-service-check.sh` and `--reproduce` | 90 MB ok / 2.1 GB killed (OS bug still present) |

**Live verification of the fix.** Panel service 77-94 MB at its peak for Open, Save, Export in the app and for ⌘O, ⌘E, ⌘S, ⇧⌘S under the driver; CPU 0 % once drawn; watchdog kills 0 in every session. The service does **not** exit within a second of the panel closing: it idles at ~80-90 MB until the app exits (the earlier probe's "gone within a second" was measured after the probe process exited). Matrix rows E2E-KEY-004..007 now carry `E2E` evidence (`docs/design/evidence/e2e-2026-10-10/panelfix/`); the ⌘O screenshot lists the owner's Documents folder and is deliberately not stored.

**Still open / notes for the next person.** The OS bug itself is unfixed on 27.2 (26B5101f): any app launched with a non-normalized CFFIXED_USER_HOME hangs its first Open/Save panel. OpenSnap cannot trigger it for a user (a real launch has a normal home). Two other scripts build session paths the same way but never open a panel and were left alone: `tools/test-app-safety.sh` and `tools/check-clean-clone.sh`; any new harness that opens a system panel must canonicalize its home first.

## Independent review round 1 (pinned e41f0c2)

**Verdict:** needs fixes.

**Strengths noted:**

- No real Keychain, UserDefaults or Application Support access, and no outside network, in the new tests.
- All 39 Font Awesome Free paths match the official 7.3.1 data byte for byte.
- No app-owned text below 18 pt in source.

**Findings** (severity · ID · surface · finding · status):

- P1 · R1-001 · evidence · private text visible in a harness capture (m4-glass S01 dark rt-ic); harness window accepted real input · capture withdrawn from the tree and replaced (b09ecc6); OCR sweep tool added (tools/evidence-ocr-sweep.py, 1849 images, no other leak); harness input fence added; history cleanup owned by root before any push.
- P1 · R1-002 · Upload · upload sent the fitted size while title/status/tooltip promise the picture's own pixel size when "Original size" is ticked · batch 5.
- P2 · R1-003 · Resize sheet · opens in output points (e.g. 1517×1011) under a title showing pixel size (2400×1600) · batch 5.
- P2 · R1-004 · build / E2E sessions · default dev builds bundled Font Awesome Pro and E2E copies didn't strip it · fixed b09ecc6 (Pro opt-in only; sessions strip Pro and print the icon mode).
- P2 · R1-005 · Toolbox pull-down · icons unverified in a real menu; batch-4 capture overclaimed; near-identical symbols for Actual Size/Full Screen/Resize and Close/Cancel Snapshot · batch 5.
- P2 · R1-006 · bottom bar · Resize glyph reads as expand/full screen · batch 5 (decision: "Resize…" text button if it fits at 980).
- P2 · R1-007 · ledger · rows still described the removed Capture Shortcuts sheet and old History tab names · fixed b09ecc6 (rows retired, new entry-path row, generator updated).
- P2 · R1-008 · ledger · class inflation: 23 rendered rows were AX listings only; 4 E2E rows lacked a screenshot of the claim; 5 rows used a substituted entry path · fixed b09ecc6 (reclassified/annotated).
- P2 · R1-009 · process · batch 4 had no real-click retest · J6 pending after batch 5.
- P2 · R1-010 · Delete from Web · re-saving a destination changed its credential id and fingerprint, so older entries refused deletion with a still-enabled button · batch 5.
- P2 · R1-011 · Settings › Upload · duplicated the Destinations sheet · batch 5 (decision: single surface in Settings › Upload).
- P2 · R1-012 · History toolbar · seven unlabeled glyphs beside empty space; eye-slash meaning differs from the editor · batch 5.
- P2 · R1-013 · status line · repeated the title's size/format/bytes, starving it at 980 · batch 5.
- P2 · R1-014 · status line · 980 upload success showed "Link copied · cdn.exa…" · batch 5.
- P3 · R1-015 · empty states/copy · Destinations empty list had no text; punctuation/units inconsistencies · batch 5.
- P3 · R1-016 · Actual Size navigator · full-height column mostly empty · deferred.
- P3 · R1-017 · Settings › Capture · redundant Disable All / Reset Defaults; edits go live mid-entry; 69-item key pop-up (record field not built) · batch 5 (cleanup), record field deferred.
- P3 · R1-018 · Settings tab strip · Differentiate Without Color outline didn't update live · batch 5.
- P3 · R1-019 · tests · six weak/tautological assertions · batch 5.
- P3 · R1-020 · Window › Full Screen · acted on the editor while another window was key or after Hide · batch 5.
- P3 · R1-021 · eraser · drops the shadow from the whole remaining shape · batch 5 stretch.
- P3 · R1-022 · misc · WebDAV Test accepted 3xx/unauthenticated OPTIONS; clearRemote left publishedSize; notices hid upload status; Capture Shortcuts… enabled under a sheet; weak SF fallbacks · batch 5.
- P2 · R1-023 · docs/tooling · model and AI-tool names in committed docs/tooling · fixed b09ecc6 except root-owned files (the audit plan, the presentation page) and the vendored tool-skills folder (owner decision).
- — · R1-024 · F-J5-005 judgement · reviewer saw no app cause; root cause later found in the launchers (non-normalized CFFIXED_USER_HOME triggering a macOS 27.2 panel-service loop) and fixed in fa4715f.

**Ledger-honesty sample.** 25 E2E, 15 rendered and 15 unverified rows were sampled. All cited files existed. Overclaims were found and corrected in b09ecc6: BAR-034/035, SHEET-017 (weak), MENU-011 and SET-010 (partial), DEST-036 and DEST-010 (stale), 6 AX-only rendered rows, SHEET-003, and HOT-014. No row claims VoiceOver speech or live capture as proven.

## J6 retest (batches 4 and 5)

J6 lane, build 0bd6f94, four isolated sessions through `tools/e2e-session.sh`, driven only with the computer-use driver: pid 82616 (seed `all`), pid 69609 (seed `history` plus `--aws`, the two uploads), pid 1790 (seed `empty`), pid 43171 (seed `empty`, the Resize presets). Every session stopped with `RESULT stores unchanged` and 0 panel-service watchdog kills; no system Open, Save, Export or Print panel was opened. Evidence is `docs/design/evidence/e2e-2026-10-10/j6/` (64 jpg, numbers below are the file prefixes); the AWS steps are in `j6-aws-log.md`. A local synthetic page (`http://127.0.0.1:8765/`, a gradient, a red rounded rectangle and the words "J6 synthetic page, fixture, nothing personal") served Snap from Link, which gives a 2560 × 1800 snap and the Original size checkbox without touching the real display. Result key as in J4: PASS = the corrected behaviour was seen in a screenshot I looked at; PARTIAL = part of it; FAIL = the fix did not hold; unverified = not reachable, reason given.

### Result table

| Finding | Result | Evidence | Note |
|---|---|---|---|
| R1-002 Upload honours Original size | **PASS (P1)** | `31`, `33`, `34`, `38`, `39`, `40`, `j6-aws-log.md` | Original size ticked, title 2560 × 1800: the object is **2560 × 1800** (`sips` on the downloaded file), History Details 2,560 × 1,800. Unticked, title 674 × 474: the object is **674 × 474**, Details 674 × 474. |
| R1-003 Resize opens at the title's size | PASS (opens) / **FAIL (after apply)** | `04`, `54`, `55`, `05`, `06` | Opens at 2560 × 1800 ticked (also from the Image menu) and at 1438 × 1011 unticked, equal to the title each time. After applying 1200 × 844 the title and the export do not follow: F-J6-001. |
| R1-005 Toolbox shows icons | PARTIAL | `01` | The real open menu draws an icon on 16 of 18 rows; Filled Shapes and Shadow (check-mark toggles) have none: F-J6-009. The old near-identical Actual Size / Full Screen / Resize / Close / Cancel Snapshot rows are no longer in the Toolbox. |
| R1-006 Resize… text button | PASS | `03`, `06`, `53` | Text button at 980 and 1482 wide; disabled in Actual Size. |
| R1-010 Delete from Web after edits | PARTIAL | `35`, `36`, `37`, `40`–`43`, `j6-aws-log.md` | Rename then reselect: enabled; the app deleted upload 2 (head-object 404). A folder edit disables it with a reason, but after restoring the exact folder the entry stayed undeletable until the list reloaded, so upload 1 had to be removed with the CLI: F-J6-003. |
| R1-011 One destinations surface | PASS | `08`–`15`, `17`, `27`, `44`, `46`, `47`, `48` | Settings › Upload list with Add…, Edit…, Remove, Make Default (disabled on the Default row, moved the pill to FTPS); empty state No destinations yet with Add…; form-only editor sheet on Settings; Sharing Settings…, Capture Shortcuts… and an unconfigured Upload land on the right Settings tab. Publish… could not be pressed (app went inactive, unverified: harness). |
| R1-012 History labelled actions | PARTIAL | `18`, `19`, `20` | All seven actions labelled at the default 1000 and at 945. 880 was not reachable by real input: dragging the edge stopped at 945 (F-J6-006), so the icon-only collapse is still rendered-only. |
| R1-013 Footer does not repeat the title | PASS | `06`, `24` | Windowed: no size, format or bytes in the status line; full screen: `Arrow · Unsaved changes · 674 × 474 · PNG · 213 KB`. The 980 status is still tail-cut: F-J6-004. |
| R1-014 980 upload success | PASS | `33`, `39` | `Copied · …23.png`, `Copied · …7c.png` with Open and Copy buttons. |
| R1-015 Empty-state wording | PASS | `21`, `44`, `45` | No history yet / No history items match these filters / No destinations yet. |
| R1-017 Settings › Capture cleanup | PASS | `07`, `48` | Clear All only (no Disable All, no Reset Defaults); note "They work again when you leave this tab." The live hotkey pause itself is not observable without registering a global hotkey (unverified: unsafe). |
| R1-018 Tab outline follows Differentiate Without Color live | unverified | `docs/design/evidence/impl-2026-10-09/audit-fix-4/dwc/S17-settings-*` | Needs the system option; harness-injected, rendered only. |
| R1-020 Full Screen only for a visible, key editor | unverified | `24` | ⌃⌘F aimed at the editor entered and left full screen; the refusal with another window key was not shown (harness). |
| R1-021 Eraser keeps the shadow of what is left | unverified | none kept | The harness drag trail covers the stroke in every capture; inconclusive. |
| R1-022 Settings commands off under a sheet | PASS (AX) | AX read | With the Add… sheet up, Settings… and Sharing Settings… in the OpenSnap menu read disabled. |
| F-J5-001 Timed Snapshot invalid delay | PASS | `25` | `abc` plus OK keeps the sheet with `Error: Enter a number of seconds from 0 to 120.` |
| F-J5-002 Sheets take ⌘D | PASS (caveat) | `29`, `30` | ⌘D did nothing while History was not key and answered Don't Save once a real drag had made it key. |
| F-J5-003 Blank Save to History | PASS | `26` | Status `Nothing to sa…` (tail-cut at 980, F-J6-004); no entry added. |
| F-J5-004 Upload with no destination | PASS | `44` | Opens Settings › Upload with No destinations yet and Add…. |
| F-J5-006 Dead circle-exclamation icon | PASS (source) | none | `FAIcon.warning` is gone; the matrix has no ICON-107 any more. |
| F-J5-005 Open/Save panel service | not retested | none | Out of scope; no system panel was opened (the launcher fix is E2E-KEY-004..007). |
| F-J3-001 DWC adds a cue to PNG \| JPG | unverified | `docs/design/evidence/impl-2026-10-09/audit-fix-4/dwc/S09-format-toggle-*` | System option; rendered only. |
| F-J3-002 History empty and no-match columns | PASS | `21`, `45` | Message centred across the full width, no details column. |
| F-J3-003 Destination forms fit per protocol | **PASS** | `10`, `11`, `12`, `13`, `14` | WebDAV, FTP, FTPS, SFTP and S3-compatible all fit with no blank band; a new SFTP has no Endpoint field. |
| F-J3-004 Increase Contrast glyphs | unverified | `docs/design/evidence/impl-2026-10-09/audit-fix-4/ic/` | System option; rendered only. |
| F-J3-005 Zoom and Original size explain themselves | PARTIAL | AX | The zoom reads Output, 100% and the checkbox help says what it measures (text readout); no capture of the tooltips. |
| F-J3-006 Size readouts disagree | PARTIAL | `04`, `05`, `55` | Title, status, Resize fields and History Details agree and are whole pixels; the Resize result is the exception (F-J6-001). |
| F-J3-007 Status at 980 | PARTIAL | `06`, `26` | Wide: idle bar not rechecked. 980: the status is still cut, F-J6-004. |
| F-J3-011 Resize glyph | PASS | `03`, `06` | The glyph is gone; the button is the word Resize…. |
| F-J4-001 Stale Test error | PASS | `46`, `47` | Cancel returns to a clean list. |
| F-J4-002 Details Date clip | PASS | `19`, `29` | `Oct 10, 2026 at 10:12 AM` fits. |
| F-J4-003 After-delete notice | PASS | `43` | `Deleted from cdn.shoemoney.com. Cached copies of the link can persist for a while.` The public URL still answered 200 twenty seconds later, as the notice says it may. |
| F-J4-004 Shared entry keeps the published size | PARTIAL | `34`, `40` | Details show the size each upload went out at; the resize-after-publish scenario was not run. |
| F-J4-005 Delete from Web focus | PASS | `42` | Cancel is the focused button. |
| F-J4-006 Stale size after History › Open | PARTIAL | `30` | The title read 940 × 600 at once after ⌘D; a similar lag shows after toggling Original size (F-J6-005). |
| Whole-pixel sizes everywhere | PASS | `19`, `30`, `55`, `56` | Title, status, Resize fields, History Details (980 × 600, 900 × 600, 940 × 600, 1438 × 1011). |
| Cancel-first destructive sheets | PASS | `15`, `23`, `42` | Remove destination, Move to Trash (cancelled, not confirmed) and Delete from Web focus Cancel; the non-destructive Hide sheet focuses Hide (`22`, F-J6-008). |
| In-memory secrets message | PASS | `28` | `Upload failed: No password is stored for this destination in this session.` |
| Resize… text button, F-J5-001/003/004 | PASS | see above | |
| DWC and IC cues | unverified | `docs/design/evidence/impl-2026-10-09/audit-fix-4/dwc/`, `…/ic/` | The driver cannot change system appearance or accessibility options; the cues were rendered only. |
| Shortcuts paused while the Capture tab is open | unverified | `07` | Only the note is visible; firing a global hotkey is unsafe. |

### Re-check rows

`E2E-MENU-004` and `E2E-HOT-041` (Capture Shortcuts… now opens Settings › Capture), `E2E-BAR-024` (Resize… text button), `E2E-DEST-010` (SFTP form), `E2E-DEST-030` (Remove sheet), `E2E-MENU-003` and `E2E-DEST-033` (land on Settings › Upload), `E2E-SHEET-004`, `006`, `018` (preset controls and Apply operated for real; `002`, `003`, `005` still only drawn or pressed without a visible result) and `E2E-HOT-016` (retired) were re-checked. `E2E-HOT-032`, `033` and `E2E-DEST-001`, `006` describe controls batch 5 removed and carry a RETIRED note.

### New findings

### F-J6-001 · P2 · Applying a Resize never changes the title or the exported size
- **Surface:** Resize… › Resize with Original size ticked or unticked; title, status, Upload.
- **Steps:** Snap from Link (2560 × 1800, Original size ticked), Resize… (the sheet opens at 2560 × 1800), type Width 1200 (Height 844), OK.
- **Observed:** with Original size ticked the title stays `Screenshot – 2560 × 1800 · PNG · 4 MB` (`05`) and the uploaded object is 2560 × 1800: the Resize left no trace in the output. Unticked, the title reads `674 × 474 · PNG · 213 KB` (`06`), the size the picture is fitted into the 980 wide window, and the uploaded object is 674 × 474. Neither number is 1200 × 844 and nothing says so. The implementer's note ("with Original size ticked, Resize changes the output size while the title keeps showing the original") is a user-visible defect: a user who resizes to 1200 × 844 and uploads gets 2560 × 1800.
- **Expected:** after Resize the title, status and export agree with the size just chosen, or the sheet says Original size will keep the picture's own pixels.
- **Suggested fix:** apply Resize to the picture's own pixels (then the checkbox no longer overrides it), or untick and hide Original size once a Resize has been applied, and write a status line such as `Resized to 1200 × 844`.

### F-J6-002 · P3 · Edit › Copy Image ignores Original size
- **Surface:** Edit › Copy Image.
- **Observed:** with Original size ticked and the title `2560 × 1800`, the pasteboard held `public.tiff` of 1438 × 1011 pixels (types and size read, content not looked at; `50` shows the state). Drag, export and upload are the three paths the checkbox names; copy is a fourth path that sends the fitted size.
- **Expected:** the same pixels the title promises, or the checkbox help names copy.
- **Suggested fix:** route Copy Image through the same `dragAtOriginalSize` output as upload.

### F-J6-003 · P3 · History's Delete from Web state is not recomputed when a destination changes
- **Surface:** Settings › Upload › Edit… then History › Delete from Web.
- **Steps:** upload to the S3 destination, rename it (button still enabled after reselecting the entry), change Key prefix `pics` to `pics-j6x` and Save, reselect the entry; then restore `pics` exactly, Save, reselect.
- **Observed:** straight after the first Save the button stayed enabled until the entry was reselected (`34`); after the edit it was disabled with the reason "the default destination is no longer the server, bucket or folder it was published to" (`37`); after restoring the exact values and reselecting, the button stayed disabled with the same reason (the Edit sheet showed us-east-1, cdn.shoemoney.com, pics) and only came back enabled after the list reloaded because a second upload added an entry (`41`). The app could not delete upload 1 in the meantime, so `aws s3api delete-object` removed that exact key (`j6-aws-log.md`).
- **Expected:** the button follows the destination store (or the check runs again when Delete from Web is pressed).
- **Suggested fix:** recompute the binding when the destinations change, not only on a list reload.

### F-J6-004 · P3 · At 980 the plain status messages are still tail-cut
- **Surface:** bottom bar status beside the Original size checkbox.
- **Observed:** `Unsaved chan…` (`06`), `Nothing to sa…` (`26`) and `Error: Upload fail…` (`63`, retry and details buttons beside it) at the minimum window; the checkbox also shows on a blank canvas with no snap (`26`).
- **Expected:** the message that replaced the repeated facts reads whole at 980.
- **Suggested fix:** shorten to `Unsaved` and `Nothing to save`, or give the status the checkbox's width when it is not needed.

### F-J6-005 · P4 · The title lags a moment behind the Original size checkbox
- **Surface:** window title after unticking Original size.
- **Observed:** the first capture after the untick still read `2560 × 1800 · PNG · 4 MB`, the next one `674 × 474 · PNG · 217 KB` (two sessions).
- **Suggested fix:** compute the title text in the same pass as the checkbox state.

### F-J6-006 · P4 · The History window stops at 945 wide, not at its 880 minimum
- **Surface:** History window edge drag.
- **Observed:** three edge drags from 1000 left the window at 945 × 720 (AX bounds); dragging further inward changed nothing (`20`). Source says `minimumSize` 880.
- **Expected:** reach the minimum the labelled-action collapse is measured for, or change the minimum.
- **Suggested fix:** check what holds the window at 945 (the action row's fitting width) and either lower it or raise `minimumSize`.

### F-J6-007 · P4 · Resize's Apply is a preview that Cancel undoes
- **Surface:** Resize or Crop sheet.
- **Observed:** the title already follows typed dimensions (640 × 480, 500 × 375 behind the sheet, `58`, `59`); Apply keeps the sheet open; Cancel then returned the document to 800 × 600 (`61`). This matches the matrix expectation "Previews the change, keeps the sheet".
- **Suggested fix:** name the button Preview.

### F-J6-008 · P4 · The Hide and Trash sheets disagree on button order and default
- **Surface:** History › Hide, History › Move to Trash.
- **Observed:** Hide: Cancel left, Hide right, Hide focused (`22`); Move to Trash: the warning-coloured action left, Cancel right, Cancel focused (`23`). Hide is non-destructive, so the focus may be deliberate.
- **Suggested fix:** one order for every confirmation sheet.

### F-J6-009 · P4 · Toolbox: two rows without an icon, AX value Select All
- **Surface:** Toolbox pop-up.
- **Observed:** Filled Shapes and Shadow are the only rows with no leading icon (Shadow has a check mark, `01`); AX reports the closed pop-up's Value as `Select All`.
- **Suggested fix:** give the toggles an icon (or say in the Toolbox help that toggles use a check mark) and set the pop-up's accessibility value to its title.

### F-J6-010 · P4 (observation) · Size formats differ between the title and History Details
- **Surface:** window title and History Details.
- **Observed:** `2560 × 1800` in the title, `2,560 × 1,800` in Details (`34`).
- **Suggested fix:** pick one grouping style.

### Observations that are not findings

- After Settings and Sharing Settings… had been used in the first session the editor window was no longer in the window list until Show OpenSnap was committed from the status item; it did not recur in the three later sessions, and the cause (a stray click on the Settings window corner, or the app going inactive) is not established.
- Capture › Snap from Link and the Timed Snapshot… sheet were opened from the Capture menu bar item; every pick was made by item name after a fresh AX read and only those two entries were pressed. Nothing started a capture of the real display.

### Class counts (matrix at the J6 build, 597 rows)

| Evidence class | before J6 | after J6 |
|---|---|---|
| E2E | 297 | 322 |
| rendered | 69 | 64 |
| unit/source | 93 | 93 |
| unverified | 138 | 118 |
| total | 597 | 597 |

25 rows moved to E2E (20 from unverified: MENU-004, 023, 029, 030, 033, 095, SET-025 to 030, HOT-041, HIST-043, 044, DEST-038, ALERT-004, ICON-109, 110, HARN-003; 5 from rendered: BAR-030, BAR-031, SHEET-004, 006, 018). Before the pass 17 unverified rows (the batch 5 TBD rows and MENU-004) had no reason in their notes. 36 further rows carry an appended J6 re-check note and keep their class.

*Note, 2026-10-10 (review round 2, R2-008):* the table above is the history at the J6 build. Rows whose surface no longer exists now carry the class `retired` and count toward no other class; the current counts are in the "Independent review round 2" section at the end of this file.

### Gap reasons of the 118 `unverified` rows (exactly one per row, in the observed cell)

| Gap reason | rows | what it covers |
|---|---|---|
| `gap: unsafe` | 36 | captures of the real display, ⌘1–⌘4, global hotkeys and live shortcut fields, Hide Others, Move to Trash, Open Link, Cancel Upload, Timed Snapshot with a valid delay, Clear All |
| `gap: harness` | 30 | synthetic right-click menus, held modifiers, file drops and drags to other apps, menu picks while the app is inactive, Group and Ungroup, full-keyboard sweeps, announcements |
| `gap: AX presence only` | 18 | menu items only listed, not pressed (File, Edit, Image and Text entries; Pencil Smoothing parent) |
| `gap: OS-owned` | 18 | Open, Save, Export and Print panels and the Export accessory, share picker, Photos and Pictures choosers, Spelling and Colors panels |
| `gap: hardware` | 5 | multi-display, 1x display, printer |
| `gap: text readout only` | 4 | Edit › Copy Image (pasteboard read), the Clear image tooltip, No destination configured (BAR-041) and the icon-only AX names (A11Y-003) |
| `gap: permission` | 4 | Screen Recording captures, Photos Library |
| `gap: AX value only` | 2 | zoom entries 75% and 100% |
| `gap: retired` | 1 | HOT-016 (the removed Capture Shortcuts sheet's status line) |

### Harness notes for the next driver (J6 additions)

- Settings and History are often not key: plain clicks on them are swallowed (`suspected_noop`), AX press through `perform_secondary_action` always lands, and one real drag inside the window makes it key for the next click or key press.
- Indexes drift on every get_app_state; query `ax_filter` for the one control and press it in the next call. Use `mode: image` for pictures: the default also returns the tree twice and costs 3–4 thousand tokens per call.
- `drag` coordinates must lie inside the last screenshot of the same window; a window cannot be widened past its own image.
- The harness draws a red drag trail over captures taken just after a drag (visible in `20` and `58`); it hides small details such as a thin eraser cut.
- The synthetic page for Snap from Link: any static HTML on `127.0.0.1` through `python3 -I -m http.server --bind 127.0.0.1 --directory <dir>`; stop it afterwards.

### Clipboard

The pasteboard held 14 bytes of text before the run; it was saved to a temp file (not printed) and restored byte for byte after the Copy Image press and the two upload links had replaced it (`cmp` identical); the temp file was deleted.

## Independent review round 2 (pinned 14d4d9f)

**Round 1 status, as the reviewer stated it:** R1-005 (Toolbox icons) and R1-023 (model and tool names in committed files) are **reopened**; R1-017 (Settings › Capture cleanup) has a **regression**, tracked as R2-001; every other round 1 item stays as recorded in the round 1 section above.

**Findings** (severity · ID · surface · finding · status). All eighteen findings are described below, with the lane each was routed to.

- P2 · R2-001 · Settings › Capture / global shortcuts · the batch-5 pause (`isShown && selectedIndex == captureTab`, SettingsWindow.swift ~1046, GlobalHotkeys.swift ~492) keeps every global capture shortcut off while Settings is merely shown on the Capture tab, even after switching to another app · batch 6 (pause only while Settings is key and the app active; resume on resign key, deactivate, hide, close).
- P2 · R2-002 · document size · deeper cause of F-J6-001: `Canvas.renderSize` holds both the chosen Resize result and the auto-fit presentation size, so refits can overwrite a Resize; with Original size ticked export used `document.size` and ignored it; `dragAtOriginalSize` depended on the current screen (`isLargeShot`) · batch 6 (separate the chosen output size from the view fit; decide from the document).
- P3 · R2-003 · bottom bar · the Original size checkbox stays on a canvas with no snap picture (after Remove Snap Picture) and does nothing · batch 6 (require a snap picture).
- P3 · R2-004 · Toolbox · the selection-style pop-up places a row over its own button (the open menu covers Toolbox, Photos and part of the tools) and exposes a pop-up role with a value (the "Select All" of F-J6-009) · batch 6 (menu button that opens below itself, role menu button, label "Toolbox").
- P3 · R2-005 · History · labels are chosen only after a resize, so with all labels shown the action row holds the window near 945 pt and 880 is unreachable by a real drag (likely cause of F-J6-006) · batch 6.
- P3 · R2-006 · evidence text · `panelfix/00-cmd-o-panel-service.txt` line 1 named the computer-use tool · fixed in this lane (now "real-click driver"); `git grep` for model, vendor and tool names (case-insensitive, the assistant's own config folder excluded) leaves only `docs/design/e2e-audit-plan.md:7` and `docs/design/audit-overview.html` (root-owned) and one `.gitignore` entry for the assistant's worktree folder (owner decision).
- P3 · R2-007 · ledger · E2E-SET-023 and E2E-KEY-021 cited image 16 (Settings open) for a "closed" result that is only a window-list readout · fixed in this lane: both moved to `unverified` with `gap: text readout only`; E2E-MENU-061 (the hidden state is a readout, the image shows the restore) treated the same way.
- P3 · R2-008 · ledger · retired rows (HOT-001 to HOT-018, HOT-032, HOT-033, DEST-001 to DEST-006, DEST-030) still counted as rendered or E2E · fixed in this lane: a new evidence class `retired`, set by the generator for every row whose gap is `removed` or `replaced`; IDs and historic evidence stay in the row's observed and evidence columns.
- P3 · R2-009 · ledger · rendered rows drawn from build 3194247 describe the chrome before batches 4 and 5 (E2E-STATE-002 "82 pt free at 980" among them) · fixed in this lane as a note: each carries "Re-check after batch 6" in its observed cell and keeps its class; the final render pass after batch 6 refreshes them.
- · R2-010 · display options · covered by the final display-option render pass after batch 6.
- P3 · R2-011 · evidence · `audit-fix-5/S42-status-notice-light` showed the normal status while its layout JSON reads "Saved to History"; `captures.md` said S42-status-after-notice names the export format (stale since R1-013) and that the S10 dark export panel did not produce, while `ZZ-unexpected-modal-1-dark` is that panel, blank · fixed in this lane in `captures.md` (mistimed capture marked, statement corrected, blank panel described); the final render pass recaptures the notice.
- P3 · R2-012 · harness input fence · the swallowed-event count is never written to the run record, and mouseEntered/mouseExited/cursorUpdate are not fenced (a real cursor can still put hover states into captures) · batch 6.
- P3 · R2-013 · tooling · the panel-service watchdogs killed any `openAndSavePanelService` above 2 GB system-wide, `panel-service-check.sh` counted other apps' services in its peak, and its cleanup touched the real Preferences folder · fixed in this lane: both watchdogs and the peak consider only a service whose `ps eww` environment names the session's own temp dir (`CFFIXED_USER_HOME=`, `HOME=` or `TMPDIR=` followed by `<dir>/`; an unreadable environment is left alone), and the real-home cleanup is gone. Tests use fake `ps`, `ps eww` and `kill`: a big service of another environment is not killed, one with the session environment is, and mutated scratch copies go red.
- P3 · R2-014 · bottom bar at 980 · the status gets ~150 pt while PNG|JPG takes 134 pt and zoom + Resize… ~226 pt · batch 6 (compact format toggle below ~1100 pt, no "Error:" prefix, "Uploading… NN%").
- P3 · R2-015 · History · at 1280×800 three fixed tiles leave ~26% of the grid empty; "Drag as" stretches to ~300 pt at 880; Details shows "Destination: —" for never-shared entries · batch 6 if time, else next.
- P3 · R2-016 · Settings › Upload · a ~230 pt label column for the only control leaves the left quarter empty; the empty state still says "Right-click Upload to switch."; the selected row and the Default pill share one yellow · batch 6 if time, else next.
- P3 · R2-017 · destination form · an empty Endpoint gives a three-line URL rule without naming or marking the field · batch 6 if time, else next.
- P3 · R2-018 · WebDAV Test · a 2xx with a username set reports that the server accepted the login, although a server that never asks for auth also answers 2xx · batch 6 if time, else next.

**Ledger sample (reviewer, at 14d4d9f).** Class counts E2E 322 · rendered 64 · unit/source 93 · unverified 118 (597 rows). 22 of 25 sampled E2E rows held; KEY-021 and SET-023 overclaimed (R2-007). DEST-001 was retired but still counted as E2E (R2-008). MENU-092 (Send to Back) is ambiguous: the two rectangles share a colour, so the stacking order cannot be read from the picture. All 118 unverified rows carry exactly one gap reason. No E2E row claims Differentiate Without Color or Increase Contrast as proven.

### Class counts after the round 2 ledger fixes (597 rows)

| Evidence class | at 14d4d9f | now |
|---|---|---|
| E2E | 322 | 309 |
| rendered | 64 | 48 |
| unit/source | 93 | 93 |
| unverified | 118 | 120 |
| retired | – | 27 |
| total | 597 | 597 |

Movement: 27 retired rows left their classes (10 E2E: HOT-017, HOT-032, HOT-033, DEST-001 to DEST-006, DEST-030; 16 rendered: HOT-001 to HOT-015 and HOT-018; 1 unverified: HOT-016). SET-023, KEY-021 and MENU-061 moved from E2E to unverified (`gap: text readout only`), so unverified is 118 − 1 (HOT-016) + 3 = 120 and each of the three carries exactly one gap reason. The "Gap reasons of the 118 unverified rows" table above is the J6 history: its `gap: retired` row (HOT-016) is now counted as `retired`, and `gap: text readout only` is 7 rows (4 + 3).

### Rendered rows to re-check after batch 6 (R2-009)

48 rendered rows cite evidence drawn at build 3194247, before batches 4 and 5 changed the editor chrome, Settings, the destination form, Resize and the Toolbox (three Resize rows record 0bd6f94 as their source SHA while their image is the 3194247 one). They keep class `rendered` and carry the note; the final render pass after batch 6 refreshes the evidence, and any row it shows unchanged simply loses the note.

STAT-001, TOOL-012, TOOL-013, TOOL-015, TOOL-016, TOOL-017, TOOL-018, TOOL-019, TOOL-021, TOOL-029, CAP-001, CAP-004, CAP-005, CAP-006, CAP-007, SET-006, DEST-014, DEST-016, DEST-022, DEST-025, SHEET-002, SHEET-003, SHEET-005, SHEET-026, SHEET-036, SHEET-037, SHEET-044, ICON-025, ICON-027, ICON-031, ICON-100, ICON-101, ICON-102, ICON-106, STATE-002, STATE-003, STATE-009, STATE-010, STATE-011, STATE-014, STATE-015, STATE-016, STATE-017, STATE-018, STATE-019, STATE-020, STATE-021, STATE-022

## J7 real-input validation (5b30929)

J7 lane, build 5b30929 (main after batch 6 and batch 7), two isolated sessions through `tools/e2e-session.sh`, driven only with the computer-use driver: pid 60030 (seed `all`, no AWS) and pid 35679 (seed `history` plus `--aws`, the two uploads). Both stopped with 0 panel-service watchdog kills and an unchanged store digest (`dbde037ac2085108` before and after). Both `stop` runs still printed `RESULT STORES CHANGED` for one reason: a file named `com.shoemoney.opensnap.eyedump-<pid>.plist` in `~/Library/Preferences`, left by the parallel render lane's `eye-dump-audit` run (pids 25143 and 76389, running at that time), not by these sessions; the watched real files hash identically. No system Open, Save, Export or Print panel was opened. A local synthetic page (`http://127.0.0.1:8765/`, gradient, red rounded rectangle, the words "J7 synthetic page, fixture, nothing personal") served Snap from Link for the 2560 × 1800 snap, and a throwaway local WebDAV stand-in on 127.0.0.1:8766 (207 for PROPFIND, 403 for PUT) served the Test wording and the footer error; both were stopped and deleted. Evidence is `docs/design/evidence/e2e-2026-10-10/j7/` (34 jpg, numbers below are the file prefixes); the AWS steps are in `j7-aws-log.md`. Result key as in J4 and J6: PASS = the corrected behaviour was seen in a screenshot I looked at; PARTIAL = part of it; FAIL = the fix did not hold; unverified = not reachable, reason given.

### Result table

| Item | Result | Evidence | Note |
|---|---|---|---|
| 1 R2-001 shortcut pause lifecycle | PARTIAL / unverified (firing part: unsafe) | `02`, `04`, `05` | Settings › Capture note reads "Shortcuts are saved as you change them. They pause while this window is in front." (new wording). Making the editor the front window left it unchanged, close then reopen landed on Capture with the same note. There is no visible or AX readout of the pause state (F-J7-004), and pressing a real global shortcut would start a capture of the real display, so the pause and its end are unverified (`gap: unsafe`). In this driver neither window was key most of the time, so no key/resign transition could be asserted either. |
| 2a F-J6-001 / R2-002 Resize with Original size ticked | **PASS** | `10`, `11`, `12`, `13`, `22`, `j7-aws-log.md` | 2560 × 1800 snap, Resize 1200 × 844: title 1200 × 844 behind the sheet and after Apply, after OK; full-screen footer `Rectangle · Unsaved changes · 1200 × 844 · PNG · 377 KB`; Edit › Copy Image left a TIFF of 1200 × 844 on the pasteboard (readout, not a screenshot); Upload produced a **1200 × 844** object (J6: 2560 × 1800). |
| 2b Original size unticked | **PASS** | `14`, `23` | Title fitted 1438 × 1011 at once (no lag, J6 had one); the object is **1438 × 1011**. Unticked then Resize 1200 × 844: title 1200 × 844 (sheet open and after OK). |
| 2c Crop and Limit | PARTIAL | `15` | Limit, Longest side 800: title 800 × 563 and the window narrowed to 980. Crop mode was not run. |
| 2d Apply then Cancel keeps the size (F-J6-007) | PASS | `11`, `12` | Apply put 1200 × 844 in the title and enabled Undo; Cancel kept it. The button is still named Apply for what is a commit. |
| 2e Export accessory, drag | unverified | none | Export is an OS-owned panel (not opened, privacy); a drag out of the app is not possible with this driver. |
| 3 R2-003 no Original size without a snap picture | PASS (blank canvas) / PARTIAL (after Remove Snap Picture) | `00`, `18` | The blank 800 × 600 launch canvas has no checkbox (`00`). After Toolbox › Remove Snap Picture the checkbox is gone, but the 980 footer was showing an upload error, which also hides it (F-J7-006), so `18` does not isolate the fix. |
| 4 R2-004 Toolbox | **PASS** | `01` | The open menu starts below its button; the button, Photos and the tools stay uncovered. All rows have an icon, Filled Shapes and Shadow included (R1-005 closed). AX: AXMenuButton, label Toolbox, no Value (F-J6-009 closed). On macOS 27 the system adds an "Ask Siri" row to the top of the open menu; that row is not the app's. |
| 5 R2-005 / F-J6-006 History at 880 | **PASS** | `19`, `20`, `21` | Dragging the right edge from 1000 reached 880 × 720 (J6 stopped at 945). At 880 Open, Copy, Copy Link and Open Link are icon-only; Hide, Trash and Delete from Web keep their words. |
| 6 R2-014 / batch 7 980 footer | PASS (one exception) | `15`, `16`, `17` | At 980 the format toggle shows only the selected format (PNG) and the status `Unsaved changes` is whole. An upload failure reads `Upload failed (curl 22).` on one whole line with retry and details buttons, no `Error:` prefix; the Details dialog names `HTTP 403` (a WebDAV stand-in, never the real bucket). The form is `(curl 22)`, not `· HTTP 403` (F-J7-002). |
| 7 F-J6-003 Delete from Web recomputes | **PASS** | `24`, `26`, `27`, `28`, `29`, `30` | Key prefix `pics` to `pics-j7x`, Save: Delete from Web disabled at once with its reason, no reselect. Prefix restored to `pics`, Save: enabled at once. The app then deleted both uploads (head-object 404 for each); the CLI fallback was not needed. |
| 8a R2-015 Drag as width, Destination hidden | PASS | `19`, `20`, `21` | Drag as is a normal pop-up at 1000 and at 880. A never-shared Saved entry shows Name, Date, Size, Action and no Destination row. |
| 8b R2-016 Settings › Upload | PASS / PARTIAL | `06`, `09`, `25` | Full-width list under a Destinations heading, outlined Default pill on the yellow selected row, pill moves with Make Default, a single destination keeps its pill. The hint "hidden when empty" was not run (needs an empty list). |
| 8c R2-017 empty-field Test error | **PASS** | `07` | `Error: Endpoint URL is empty. Enter the server address, such as https://example.com/uploads.` with the field outlined. |
| 8d R2-018 WebDAV wording | PARTIAL | `08` | The note no longer says the login was accepted ("it did not reject the login … does not prove the login was checked") but the band cuts it at "answe…" and the closing "Nothing was uploaded." is lost (F-J7-001). |

### Re-check rows

`E2E-DEST-014`, `016` and `022` moved from rendered to E2E (the live S3 edit form was opened with real input, `31`; their R2-009 re-check note is cleared). 31 further rows carry an appended J7 note and keep their class: TOOLBOX-001, 053, 054, 055, BAR-002, 024, 025, 028, 030, 031, SHEET-007, 009, 017, 018, 019, HIST-023, 025, 034, 041, SET-004, 019, 029, 030, HOT-044 (stays unit/source, only the note was observable), DEST-007, 013, 026, 029, 031, 036 and MENU-021 (stays unverified; the J6 pasteboard finding F-J6-002 no longer reproduces: 1200 × 844 after a ticked Resize, `gap: text readout only` unchanged).

### New findings

### F-J7-001 · P3 · The WebDAV 2xx Test note is cut at three lines
- **Surface:** Settings › Upload › Add…/Edit… (WebDAV) › Test, result band.
- **Steps:** WebDAV endpoint `http://127.0.0.1:8766/` (a stand-in answering 207), a user name and password, Test.
- **Observed:** `Connected` with `Reached the server (HTTP 207); it did not reject the login and the folder was not refused. A server that never asks for a login answe…` (`08`). The tail of the caveat and the sentence `Nothing was uploaded.` never show.
- **Expected:** the whole note, or a shorter one that fits.
- **Suggested fix:** shorten to `Reached the server (HTTP 207). A server with no login answers the same way, so the login is not proven. Nothing was uploaded.` or let the result band grow to four lines.

### F-J7-002 · P4 · The footer error shows curl's exit code, not the status the server sent
- **Surface:** bottom bar at 980, upload error.
- **Observed:** a WebDAV PUT answered with 403 reads `Upload failed (curl 22).` in the footer (`16`); `HTTP 403` appears only in the Details dialog (`17`). Batch 7's own target form is `Upload failed · <code>` (the S3 case, `HTTP 403`).
- **Expected:** `Upload failed · HTTP 403` for every protocol that has an HTTP status.
- **Suggested fix:** map curl 22 to the HTTP code it carries (`--write-out %{http_code}`) before building the footer line.

### F-J7-003 · P3 · A shared entry's Details Size changes after Delete from Web
- **Surface:** History › Details, Size.
- **Steps:** upload with a ticked Resize to 1200 × 844, open History, select that entry, Delete from Web (confirm).
- **Observed:** before, Size `1200 × 844` and a Destination ending `…afc6c576.png` (`24`); right after the delete, with the same entry still selected (Destination still `…afc6c576.png`, AX text names the same object key), Size reads `1438 × 1011` (`29`), the size of the second upload's document. The History copy's size and the published size are two different numbers and the panel switches between them.
- **Expected:** one size per entry (the published size, or the editable copy's, with a label), not a change on delete.
- **Suggested fix:** keep showing the published size for a Shared entry after the web copy is gone, or relabel the field once it is the History copy's.

### F-J7-004 · P4 (observation) · Nothing shows whether global shortcuts are paused
- **Surface:** Settings › Capture.
- **Observed:** the note is static; the pause state set by `updateShortcutEditing` has no readout (no label, no AX value), so R2-001 can only be proven by firing a real shortcut, which is unsafe on a real display (`02`, `04`, `05`).
- **Suggested fix:** expose the state, for example the note changing to `Shortcuts are paused while this window is in front` and back, or an AX value on the Enable checkbox, so the lifecycle can be tested without a capture.

### F-J7-005 · P4 · Original size behaves differently after a ticked and an unticked Resize
- **Surface:** bottom bar Original size after Resize.
- **Observed:** ticked, Resize 1200 × 844 rewrites the picture and hides the checkbox (`12`). Unticked, Resize 1200 × 844 keeps the checkbox; ticking it makes the title jump to `2560 × 1800` (`32`) and unticking brings `1200 × 844` back (`33`); nothing says that the chosen size is held in the background, and Undo stays enabled.
- **Expected:** one rule, for example Resize always rewrites the picture, or the checkbox says what ticking will discard.
- **Suggested fix:** hide the checkbox after any applied Resize, or show `Resized to 1200 × 844` and keep it.

### F-J7-006 · P4 · An upload error hides the Original size checkbox at 980
- **Surface:** bottom bar at 980.
- **Observed:** with `Upload failed (curl 22).`, Retry and Details showing, the Original size checkbox is not in the bar (`16`, `18`); it is there with an idle status (`15`). The checkbox cannot be changed while the error is up.
- **Suggested fix:** let the error line and the checkbox share the row (the format toggle already gave up width), or clear the error when the checkbox is toggled.

### Observations that are not findings

- The editor and the Settings window showed grey traffic lights for most of the run (driver-side focus); plain clicks on Toolbox rows, the Resize sheet's mode segments and the Delete from Web sheet were swallowed, while AX presses and keyboard navigation (Up and Return on an open menu) always landed.
- Snap from Link on a document with changes asks Save your drawing; Don't Save was pressed on the throwaway fixture only.
- Dates in History Details read `1:03PM` with no visible space.

### Harness notes for the next driver (J7 additions)

- The Toolbox opens only through `perform_secondary_action AXShowMenu` (it answers "did not open a menu" but opens); then `press_key up up up up` and `Return` commits Remove Snap Picture. Clicking its rows does nothing.
- The Resize sheet is its own window id; `type_text "1200\t"` into it reaches the Width field, `Return` presses OK, and the Limit segment needs an AX press taken from the editor window's tree.
- `get_app_state` indexes shift by one between calls; query with `ax_filter`, press in the next call with the returned `snapshot_id`.
- Menu-bar picks work when the menu item is queried right after the menu bar item was pressed, from the window that owns the focus.

### Class counts (matrix at 5b30929, 597 rows)

| Evidence class | before J7 | after J7 |
|---|---|---|
| E2E | 309 | 312 |
| rendered | 48 | 45 |
| unit/source | 93 | 93 |
| unverified | 120 | 120 |
| retired | 27 | 27 |
| total | 597 | 597 |

3 rows moved to E2E (DEST-014, 016, 022, all from rendered). Every unverified row still carries exactly one gap reason.

### Clipboard

The pasteboard held 13 bytes of text before the run; it was saved to a temp file (not printed), replaced by Edit › Copy Image and the two upload links, restored byte for byte (`cmp` identical) after the last session, and the temp file was deleted.

## Final render pass (5b30929)

Source revision `5b30929` (main after audit batch 7), built with `sh tools/build.sh`; this section closes review round 2 (R2-009 stale rendered rows, R2-010 display options after batches 5 and 6, R2-011 the mistimed S42 capture). Harness captures only (`tools/eye-dump-audit.sh`, throwaway copies, `--icons sf`; Font Awesome Pro is not bundled, so every icon is an SF Symbol). Nothing here is a real-click result, and no `Sources/` or `tests/` file was edited. The packed set is `docs/design/evidence/impl-2026-10-09/final-render/` (122 PNGs, 18 layout JSONs, 143 files, 7.05 MB; `python3 tools/check-eye-dump.py` on it: 0 failures). Raw runs stayed in `/tmp/fr/` (not committed).

### Runs (all sequential, all `--icons sf --sha 5b30929 --no-wait-gui`, command shown after `sh tools/eye-dump-audit.sh /tmp/fr/<run>`)

| Run | Arguments (every `fc-base`, `fa-*` and `fb-*` run also passed `--sizes 980xmin,1440x900,full`, which only S11M consumes) | Role |
|---|---|---|
| fc-base | `--surfaces S03,S08,S09,S11,S17,S20,S40,S07,S12,S13,S14,S15,S16,S19,S24,S25,S29,S31,S34,S11M --appearances light,dark --sizes 980xmin,1440x900,full` | clean baseline and the row-refresh surfaces |
| fc-s10 | `--surfaces S10 --appearances light,dark` | export accessory (the real Save panel is opened by S10) |
| fa-dwc, fa-ic, fa-rt, fa-all | `--surfaces S03,S08,S09,S11,S17,S20,S40 --appearances light,dark --sizes 980xmin,1440x900,full --display differentiateWithoutColor` / `increaseContrast` / `reduceTransparency` / `reduceTransparency,increaseContrast,differentiateWithoutColor,reduceMotion` | display options on the non-menu surfaces |
| rm | `--surfaces S40 --appearances light,dark --display reduceMotion` | Reduce Motion |
| fb-base, fb-dwc, fb-ic, fb-rt, fb-all | `--surfaces S42,S44 --appearances light,dark [--display …]` (same four option values) | the surfaces that open the Toolbox menu (S42 Toolbox menu, status notice, Resize variants; S44 footer states at 980 and 1440) |
| s42-2 | `--surfaces S42 --appearances light` | the one run whose status-notice capture shows the notice |

Earlier runs of the same surfaces (`base`, `base2`, `dwc`, `dwc2`, `ic`, `rt`, `all`, `rows`, `s42-1..3`, `s42d-1..4`, `m-*`, `f-*`, `g-*`) were used to find problems and are not cited. Two of them taught the validity rules below: the first baseline's light run had **0 of 115** captures taken with the app active (yellow default buttons and the Original size tick render grey, so a pixel diff against it is meaningless), and the first Differentiate Without Color dark run had 98 of 117 inactive. Every cited run has `appActive` true for every capture.

Validity checks:
- **Determinism:** `fc-base` against an earlier all-active baseline (`base2`): 118 of 180 shared captures identical; the differences are History's date line (about 2,300 px in every populated History capture) and the S40 swatch states, so S20 numbers below are noise-level by construction.
- **Real stores:** the guard digest (`dbde037ac2085108`, 122 files and 2 defaults plists) was identical before and after every cited run (`RESULT stores unchanged`). The first baseline reported `STORES CHANGED` solely because of `com.shoemoney.opensnap.e2e-60011.plist`, a throwaway plist from the J7 lane's live E2E session (app pid 60030, watchdog pid 60071 running from `.todo-worktrees/j7`); it was left alone and is gone from the later runs.
- **Input fence:** `fc-base`, `fa-dwc`, `fa-ic`, `fa-rt`, `fa-all` and `rm` swallowed **0** real events (6 runs, each with a light and a dark appearance). The Toolbox-menu runs `fb-*` swallowed 61 to 70 per appearance, `fc-s10` 11, `s42-2` 17. A per-surface sweep (S07, S08, S09, S10, S11, S11M, S12 to S17, S19, S20, S24, S25, S29, S31, S34, S44) found the events only in S44, S42 and S10, every other surface 0; the pointer sat at one screen point (909, 910) in three samples. So the count is the menu tracking loop and the Save panel reading the parked pointer, not typing, but that is an inference (the fence records a count, not event kinds): see F-R-005. The captures in those runs were looked at and OCR-swept (below).
- **OCR sweep:** `uv run --with pyobjc-framework-Vision --with pyobjc-framework-Quartz python3 tools/evidence-ocr-sweep.py docs/design/evidence/impl-2026-10-09/final-render --report /tmp/fr/ocr-final.txt`: 122 images, 10 with flagged lines, 0 unreadable. Every flagged line is fixture text (the Lorem ipsum lines, "Ship it today!", the `AKIAEXAMPLEEXAMPLE0` fixture key, misreads of the S3 help paragraph); the S07, S11M and S19 captures behind them were viewed. Nothing private.

### Positive controls (does each display option change the render where it must?)

Pixel diff = pixels whose luma differs by more than 8 between the untagged baseline and the same capture with the option (same run family, same size and appearance, both active). S42 and S44 use `fb-*`, the rest `fa-*`.

| Capture | Appearance | DWC | IC | RT | all four |
|---|---|---|---|---|---|
| S11 width 980 | light | 1,804 (0.06%) | 12,295 (0.39%) | 2,157 (0.07%) | 15,782 (0.50%) |
| S11 width 980 | dark | 1,773 (0.06%) | 24,090 (0.76%) | 208,064 (6.54%) | 206,914 (6.50%) |
| S11 width 1440 | light / dark | 1,804 / 1,774 | 13,961 / 25,754 | 2,157 / 218,826 | 17,447 / 218,233 |
| S09 footer | light | 1,676 (0.47%) | 9,109 (2.55%) | 1,073 (0.30%) | 11,625 (3.26%) |
| S09 footer | dark | 1,645 (0.46%) | 16,088 (4.50%) | 94,044 (26.33%) | 94,763 (26.54%) |
| S44 footer error 980 | light / dark | 1,676 / 1,644 | 20,298 / 27,201 | 1,077 / 84,703 | 22,776 / 97,593 |
| S42 Toolbox menu open | light / dark | 1,804 / 1,774 | 14,303 / 26,189 | 2,075 / 214,281 | 17,738 / 214,061 |
| S03 top bar | light / dark | 128 / 128 | 5,583 / 10,409 | 1,080 / 124,181 | 6,551 / 123,456 |
| S08 Resize in context | light / dark | 1,774 / 1,726 | 12,907 / 11,887 | 600 / 208,355 | 15,060 / 207,353 |
| S17 Settings, Upload list | light / dark | 2,584 / 2,540 | **0 / 0** | **0 / 0** | 2,584 / 2,540 |
| S17 Settings, General | light / dark | 2,680 / 2,636 | **0 / 0** | **0 / 0** | 2,680 / 2,636 |
| S20 History 880 selected | light / dark | 2,289 / 2,065 | 2,294 / 2,353 | 2,137 / 2,193 | 2,087 / 2,334 |
| S20 History populated | light / dark | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| S40 pressed tool (strip) | light / dark | 2,208 / 2,208 | 13,601 / 17,526 | 3,110 / 128,521 | 14,448 / 123,231 |

| Option | Where it must change | Measured | Verdict |
|---|---|---|---|
| Differentiate Without Color | a non-colour selection cue on PNG \| JPG, the Settings tab strip, the Upload list selection and the Default pill | **PNG \| JPG:** the selected PNG segment gains a black outline and an underline (footer 1,676 px, light and dark; was 0 px at 3194247, F-J3-001). **Settings tab:** the selected tab gains a black outline (2,584 px, the only change in the Upload tab capture). **Selected tool:** the 128 px underline as before. **Upload list row:** unchanged, but the row already has a fill and a 1 pt border and the Default pill already carries a check and an outline, so a cue exists, only a weak one (F-R-003). | **Pass.** F-J3-001 is fixed at the format toggle. |
| Increase Contrast | stronger glyph and border contrast | every plate gains a hairline, Snap a black outline, the JPG segment an outline (footer 2.55% light, 4.50% dark; S44 error footer 8.63% / 11.57%; the open Toolbox menu 14,303 / 26,189 px). Glyph contrast is **not** raised (F-R-002); Settings, History and the destination form change by 0 px (stock AppKit controls follow the real system option, harness limit as in F-J3-004). | **Pass for the editor chrome**, no change in the stock-control windows. |
| Reduce Transparency | opaque plates | dark plates turn opaque (S11 980 dark 6.54%, footer 26.33%, S44 error footer 36.01%, S40 strip 38.12%); light changes 0.05 to 0.07% because the glass already reads as white over white. Settings and History 0 px (no glass). | **Pass** (strong in dark, near invisible in light). |
| All four | all effects together, no conflict | additive: S11 980 dark 206,914 px; nothing clipped or overlapping in any combined capture (`check-eye-dump` clean); the PNG outline, underline, solid plates and borders show together (`S09-footer-*-rt-ic-dwc-rm`). | **Pass** |
| Reduce Motion | no decorative motion | the pressed tool glyph no longer scales down: S40 strip 504 px, both appearances (`rm` run); motion itself is not provable from stills. | **Pass, indirect** |

No option shows an absent change where one is required, so no dead-option finding is filed; the weaknesses are F-R-002 and F-R-003.

### Refreshed rows (48, all class `rendered`, source SHA now `5b30929`, "Re-check after batch 6" flag dropped)

STAT-001, TOOL-012, TOOL-013, TOOL-015, TOOL-016, TOOL-017, TOOL-018, TOOL-019, TOOL-021, TOOL-029, CAP-001, CAP-004, CAP-005, CAP-006, CAP-007, SET-006, DEST-014, DEST-016, DEST-022, DEST-025, SHEET-002, SHEET-003, SHEET-005, SHEET-026, SHEET-036, SHEET-037, SHEET-044, ICON-025, ICON-027, ICON-031, ICON-100, ICON-101, ICON-102, ICON-106, STATE-002, STATE-003, STATE-009, STATE-010, STATE-011, STATE-014, STATE-015, STATE-016, STATE-017, STATE-018, STATE-019, STATE-020, STATE-021, STATE-022.

Three rows changed meaning, not just evidence: **STATE-002** (re-measured from the layout JSON: 270 pt free in the bottom bar for the empty "Arrow · Saved" editor, 48 pt for the populated worst case at 980 with Original size shown and the compact format toggle, minimum gap 12 pt, no overlaps; the old 82 pt is gone), **STATE-003** (at 2056 pt the bars are a centred 1440 pt column, 451 pt free, instead of pinned to the edges with 891 pt free) and **STATE-010** (a 4800 x 3000 shot fitted into 1618 x 1011 pt, the zoom face still 100%). **STATE-019** gained the PNG segment outline and the Settings tab outline. **SHEET-003 and SHEET-005** record that Manage is collapsed in the render, so the preset name field and Save Preset are visible only in the J6 real-click screenshots (57, 59); the harness has no expanded-Manage capture. Class counts after regeneration (`python3 -I tools/e2e-inventory.py` then `--check`: PASS): E2E 309, rendered 48, unit/source 93, unverified 120, retired 27, total 597 (unchanged, no row gained or lost a class).

### What was looked at

Light 980 and dark 1440 (or the nearest size the surface has) were viewed for: editor empty and populated, top and bottom bars and the footer in every option, Settings General and Upload (list, Default pill, tab strip) and the destination form (S3 form light, Test error dark), History (880 selected, 880 none, populated dark), Toolbox menu open (dark), S44 footer states at 980 and 1440 in both appearances, Resize in context, export accessory, Frame at 980, picker lens, countdown, flash, permission sheet, About, help bevel, colour popover, Actual Size, large fit, small canvas at 1440, the maximised and 980-minimum matrices, and the S42 status notice. The remaining packed captures (S17 Drawing, the other S19 forms, S42 Resize variants, S44 History sheets) were not viewed one by one; they passed `check-eye-dump` and the OCR sweep. Judged as good as it can look: the compact footer, the centred full-screen column, the labelled History actions (all seven labelled at the default width, the three destructive ones at 880, glyphs only below that, measured from the live buttons), the 5 x 2 colour popover and the footer error line (`Upload failed · HTTP 403`, Retry and Details beside it). Still open from earlier rounds and re-observed unchanged: F-J3-005 (zoom face 100% while the picture is drawn at about 34%), F-J3-009 (the 300 x 180 shot is 4.2% of a 1440 x 900 window), F-J3-010 (unselected radios and checkboxes 1.25:1, e.g. the Dock radio and Make uploads public-read).

### Findings

### F-R-001 · P3 · Harness · S42 status-notice captures the stale status
- **Surface:** `S42-status-notice` (bottom bar crop), `Sources/EyeDumpAuditSurfacesBatch3c.swift` (the step posts "Saved to History", then shoots with `settle: 0.2`).
- **Observed:** of 21 attempts at 5b30929 the PNG shows the notice in 2 (both light: `s42-2` and `fb-dwc`); the other 19 show the normal status "Arrow · Unsaved changes" and a grey Original size tick while the capture's own layout JSON reads `Saved to History`. All 11 dark attempts are stale, as are `S42-status-notice-*@cc764dc` (both appearances, `audit-fix-6/captures.md`) and the light copy at `f7f68be`. The window server frame is read before the footer repaints.
- **Expected:** the capture shows what the layout JSON says.
- **Suggested fix:** force the footer to display (or pump until the label's drawn string matches `status.stringValue`) before shooting; compare the cropped pixels with the string as a self-check. Until then `S42-status-notice-light@5b30929.png` (from `s42-2`) is the only correct copy; there is no correct dark one.

### F-R-002 · P3 · Increase Contrast does not raise glyph or disabled contrast (F-J3-004 still open)
- **Surface:** editor chrome, `S11-width-980-*-ic` against `S11-width-980-*`.
- **Observed (sampled from the PNGs):** the unselected Select-tool glyph is 4.00:1 on white in baseline and with the option; in dark 4.57:1 baseline, 4.50:1 with the option. Disabled Undo 1.47:1 → 1.57:1 (light), 1.63:1 → 1.78:1 (dark). The zoom text is unchanged. Only borders and the Snap outline strengthen.
- **Expected:** inactive glyphs reach at least 7:1 under the option and no label loses contrast; disabled controls stay legible.
- **Suggested fix:** resolve inactive glyph and disabled colours through the same Increase Contrast branch that draws the plate border.

### F-R-003 · P3 · Differentiate Without Color leaves the Upload list selection and radios at colour-only strength
- **Surface:** Settings › Upload destination list, `S17-settings-upload-many-light-dwc` against `S17-settings-upload-many-light`; Settings › General radios.
- **Observed:** the selected row is a pale yellow fill (`#FDF4DC`, 1.10:1 against white) with a 1 pt border (`#DDB546`, 1.95:1 against white in light; 11:1 in dark); under the option the only change in the capture is the black outline on the selected tab (2,584 px), so the row is identical. The unselected radio discs stay 1.25:1 (F-J3-010).
- **Expected:** with the option on, a selected row has a cue that does not rely on hue, at least 3:1 (a dark border or a leading mark), as the tab strip and the format toggle now do.
- **Suggested fix:** thicken and darken the row border (or add a check) when `DisplayOptions.current.differentiateWithoutColor`, the way `SettingsWindow.swift:667` already does for the tab.

### F-R-004 · P3 · Harness · the Toolbox menu capture fails intermittently
- **Surface:** S23, S42, S44 "Toolbox menu open".
- **Observed:** in the first set of runs 12 of 30 menu captures failed with "menu tracking returned before the capture timer fired (menu did not open)" (for example the light S23 and S42 baseline, the dark S42 under Reduce Transparency); the ten `fb-*` runs of S42 and S44 (20 captures) had 0 failures, and a re-run of each missing combination opened the menu first time. A capture that silently drops looks like a pass in a count of PNGs.
- **Expected:** the menu opens every time or the run fails.
- **Suggested fix:** arm the capture timer before `popUp`, retry once on the gap, and have `check-eye-dump` fail a run with an unexplained menu gap.

### F-R-005 · P3 · Harness · the input-fence count cannot tell a parked pointer from typing
- **Surface:** `Sources/EyeDumpAuditInputGuard.swift` (a local monitor counting every event).
- **Observed:** runs that open a menu or the Save panel swallow 11 to 70 events per appearance (S44 38 in a single-surface run; S42 15 to 19; S10 11), every other surface 0, with the pointer parked at (909, 910). The count is correct as a count, but "somebody used the machine" printed beside it is wrong for these runs, and a reader cannot tell. The fence records no event kinds.
- **Expected:** the safety record separates key and button events from move, enter and cursor-update events.
- **Suggested fix:** keep one counter per kind in `record()` and print "keyboard 0, buttons 0, pointer moves N".

**Not captured:** the light and dark S42 status notice in the form the row asked for exists only for light (F-R-001); the Resize sheet with Manage expanded (no harness step); real Font Awesome icons (Pro fonts not bundled in this build); the status item on a real menu bar (transparent capture only); native tooltips and the Share picker (recorded harness gaps).

## J8 real-input validation (87abbfd)

J8 lane, build 87abbfd (main after batch 8), one isolated session through `tools/e2e-session.sh`: pid 94116 (seed `history` plus `--aws`, one upload), driven only with the computer-use driver. `stop` ended with 0 panel-service watchdog kills and `RESULT stores unchanged` (digest `dbde037ac2085108` before and after; no concurrent `eyedump` plist was present this time, `pgrep -f eye-dump-audit` was empty). No system Open, Save, Export or Print panel was opened. A local synthetic page (`http://127.0.0.1:8765/`, gradient, red rounded rectangle, the words "J8 synthetic page, fixture, nothing personal") served Snap from Link for the 2560 × 1800 snap; a throwaway local WebDAV stand-in on 127.0.0.1:8766 (207 for PROPFIND, 403 for PUT) served the Test note and the failed upload. Both were stopped and deleted afterwards (ports answer nothing). Evidence is `docs/design/evidence/e2e-2026-10-10/j8/` (18 jpg, numbers below are the file prefixes; `03` is a second view of the editor key at the moment of `02`); the AWS steps are in `j8-aws-log.md`. Result key as before: PASS = the corrected behaviour was seen in a screenshot I looked at; PARTIAL = part of it; unverified = not reachable, reason given.

### Result table

| Item | Result | Evidence | Note |
|---|---|---|---|
| 1a R2-001 / F-J7-004: note while Settings is key | **PASS** | `01` | Settings › Capture with Settings key and the app active reads `Shortcuts are paused while this window is in front.`; its AX value says the same. |
| 1b editor window of the same app becomes key | **PASS** | `02`, `03` | The editor's traffic lights are lit, Settings' are grey, and the Capture note is back to `Shortcuts are saved as you change them. They pause while this window is in front.` (AX value too). |
| 1c Settings key again | **PASS** | `04` | Paused text again. |
| 1d switch tab | PARTIAL | `05`, `06` | While on Drawing there is no readout (the note lives only on the Capture tab, `05`), so the pause release on leaving the tab cannot be read. Re-entering Capture while the editor was key (AX press of the tab) showed the normal note (`06`). |
| 1e close Settings, reopen | **PASS** (with a note) | `07` | Closed with ⌘W, reopened with ⌘,: Settings is key at once, so it reads the paused text straight away (`07`); there is no moment where it is shown but not key. |
| 1f app deactivated | unverified | none | `gap: unsafe`. The isolated app has only the editor and Settings windows; deactivating the app means bringing another app forward, which could be one of the owner's. The real global shortcuts were never pressed, so the unregistration itself stays unit/source (HOT-044, class unchanged). |
| 2a F-J7-005: Resize with Original size unticked | **PASS** | `09`, `11` | 2560 × 1800 snap, Original size unticked (title 1438 × 1011), Resize Width 1200: the title behind the sheet is 1200 × 844 at once and the checkbox is already gone; after OK the title stays 1200 × 844 with no checkbox. (J7: the checkbox stayed and ticking jumped to 2560 × 1800.) |
| 2b ticked variant | **PASS** | `10`, `12` | Undo, tick Original size (title 2560 × 1800), Resize 1200: title 1200 × 844, checkbox hidden. |
| 2c Limit once | **PASS** | `13` | Limit, Longest side 800: title 800 × 563, the window narrowed to 980, no checkbox, one PNG toggle. |
| 2d nothing jumps when toggling | PASS (nothing to toggle) | `11`, `12`, `13` | After any applied Resize or Limit the picture equals the shown size, so the checkbox is hidden; there is no toggle that can jump. |
| 3 F-J7-003: Details Size, shared entry | **PASS** | `14`, `15`, `17` | Live S3 upload of the 800 × 563 picture (object 800 × 563 by `sips`): Details reads `800 × 563 (published)`; after Delete from Web, same entry still selected, it still reads `800 × 563 (published)` and the Destination keeps the URL. (J7: `1200 × 844` then `1438 × 1011`.) |
| 3b Delete from Web (live object) | **PASS** | `16`, `17` | Sheet names the exact URL; the pixel click on the sheet's button was swallowed, the AX press landed; the app deleted the object (head-object 404). The public URL still answered 200 from CloudFront (`age: 91`) – the app's notice says cached copies can persist; no invalidation was requested. |
| 4 F-J7-006 / F-J7-002: 980 footer after a 403 | **PASS** (F-J7-006) / PARTIAL (F-J7-002) | `18`, `19` | At 980 with `Original size` ticked the footer is `[x] Original size  Failed` with Retry and Details beside it – the checkbox stays. The visible line gives up its words to `Failed`; the full `Upload failed · HTTP 403` is the status text's AX value and AX help text, and Details shows `Upload failed · HTTP 403` and `curl: (22) The requested URL returned error: 403` (`19`). |
| 5 F-J7-001: WebDAV Test note | **PASS** | `08` | Test against the 207 stand-in with a user name and password: `Connected`, `Reached the server (HTTP 207); it did not reject the login. A server with no login answers the same way, so this does not prove it. Nothing was uploaded.` – three whole lines, the closing sentence included. |

### Re-check rows

14 matrix rows carry an appended J8 note and keep their class: BAR-024, 025, 030, HOT-034, HIST-023, 034, 040, DEST-026, 034, 036, SHEET-007, 009 and 019 (E2E), and HOT-044 (stays unit/source: the pause now has a readout that follows key window, tab entry and reopen, but the firing/unregistration is unsafe to prove and the app was never deactivated).

### New findings

### F-J8-001 · P4 (observation) · The 980 footer error line shows only "Failed"; the status code is in the AX help text and Details
- **Surface:** bottom bar at 980, upload error with the Original size checkbox kept beside it.
- **Observed:** `Failed` with Retry and Details (`18`). The whole `Upload failed · HTTP 403` exists as the status text's AX value and AX help text and in Details (`19`), but a sighted user must open Details to see the code (hover was not tried).
- **Expected:** acceptable as a trade-off after batch 8 (the checkbox won); a short code such as `HTTP 403` fits in the free space left of Retry if the owner wants it visible.
- **Suggested fix:** show `HTTP 403` (or `Failed · 403`) when the status carries a code and the row has room.

### F-J8-002 · P4 (observation) · The pause note cannot be read off the Capture tab
- **Surface:** Settings, any tab but Capture.
- **Observed:** the readout lives in the Capture form; on Drawing, General or Upload nothing says whether shortcuts are paused (`05`), so the release on a tab change cannot be asserted without firing a shortcut.
- **Suggested fix:** none needed for users; for testing, an AX value on the tab group would do. Not worth shipping on its own.

### Observations that are not findings

- Settings window ⌘, from the editor needed one repeat after ⌘W the first time (the first press returned ok but no window appeared); the second press opened it. Likely the menu command racing the closing window in the driver.
- The destination form's text fields give no AX readback; `type_text` with a pixel target types into whichever field is first responder (the Endpoint text landed in Name first), and a Tab inside the text skips a field. Clicking the field, then typing, put text where expected for Endpoint, Public base URL, Username and Password; the Name field kept the stale text. Harness note below.
- The WebDAV destination's name defaulted to the endpoint URL in the list when Name held the endpoint text; no finding.

### Harness notes for the next driver (J8 additions)

- Settings, History and the sheets are separate window ids; `activate_window` on the editor id makes the editor key and the Settings window resigns, which is what the pause note follows. `get_app_state` with `additional_window_ids` captures both in one call.
- Sheet buttons (Delete from Web) take an AX press from the owning window's tree (`ax_filter Delete`); pixel clicks are swallowed. Segmented Limit tab likewise needs the AX press from the editor window's tree; the Limit field then takes a click, then `type_text` without a trailing tab, then Return.
- Dragging the editor window's right edge in `get_app_state` pixel coordinates with the current `screenshot_id` resizes it (1482 → 1030 → 980); the footer goes compact below ~1000.
- Keep AX filters tight (`ax_filter`): a bare `AXButton` or `AX` filter returns the whole tree and costs tens of thousands of tokens.

### Class counts (matrix at 87abbfd, 597 rows)

| Evidence class | before J8 | after J8 |
|---|---|---|
| E2E | 312 | 312 |
| rendered | 45 | 45 |
| unit/source | 93 | 93 |
| unverified | 120 | 120 |
| retired | 27 | 27 |
| total | 597 | 597 |

No row changed class: the J8 results confirm batch 8 on rows that were already E2E, and the one row that could have moved (HOT-044) stays unit/source for a stated reason. Every unverified row still carries exactly one gap reason (the check passes).

### Clipboard

The pasteboard held 13 bytes of text before the run; it was saved to a temp file (not printed), replaced by the upload's link (read back once to learn the exact key of the object this lane created), restored byte for byte (`cmp` identical) after the session was stopped, and the temp file was deleted.
