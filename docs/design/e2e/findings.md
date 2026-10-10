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


---

# E2E audit findings: lane J2 (History, Destinations, Settings, uploads, About, status item)

Source revision `10040ba` (main after J1 and audit fix batch 1). Driver: Sonnet J2, real clicks through kimi-cu on two isolated session copies (pids 39783 and 90314). Screenshots live in `docs/design/evidence/e2e-2026-10-10/j2/` (names below are relative to it). History's glass/text-button polish request is deferred by the owner and is not a finding here.

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

Source revision `3194247` (main after fix batches 3a and 3b). Driver: Sonnet J3, harness captures only (`tools/eye-dump-audit.sh`, throwaway bundle id, isolated HOME and defaults, display options injected inside the throwaway copy). **Nothing here is a real-click E2E result**: a capture proves how a state looks, not that a user can reach it, and the harness cannot prove VoiceOver speech or live screen capture. The 106-capture packed set is `docs/design/evidence/e2e-2026-10-10/j3/` (file names below are relative to it, with `@3194247` dropped); side-by-side composites are in `docs/design/evidence/e2e-2026-10-10/j3-diffs/`. Raw runs stayed in `/tmp/j3/` (not committed, 3,338 PNGs over 18 runs).

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
