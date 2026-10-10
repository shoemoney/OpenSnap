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
