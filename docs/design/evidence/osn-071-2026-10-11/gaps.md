# OSN-071 gaps: coverage-matrix surfaces and modes NOT captured

Round 4 @ `8188b73` (rounds 1 `4254505`, 2 `cbd0186` / `a399d8a7` and 3 `723e65b` / `5d5221c` are in git history; the surface and mode gaps below are unchanged from round 2, the same set was re-run). Everything here is a surface or mode with no capture in `REVIEW.md`, each with the concrete reason. A row of `docs/design/e2e/coverage-matrix.md` that is not listed here has at least one harness capture (its `rendered` surface ids or the S50 to S60 glass surfaces) in both light and dark. Gap categories follow the matrix (`permission`, `hardware`, `OS-owned`, `harness`, `unsafe`) plus `behaviour` for rows that are not visual states.

## Surface gaps from the harness (manifest `gaps`, every pack)

| Surface / row | Modes missed | Reason | Category |
|---|---|---|---|
| S26 Wipe confirmation | light, dark | No Wipe confirmation exists: `Canvas.wipe` acts immediately, so there is nothing to render. Recorded as a finding, not a defect of the capture | n/a (does not exist) |
| S29 native tooltips / help tags | light, dark | AppKit tooltips are drawn by the window server on a real pointer hover and cannot be forced; the app-owned tooltip plate (S38) and help bevel (S29) are captured instead | harness |
| S29 Share with macOS picker (E2E-SHEET-052) | light, dark | `NSSharingServicePicker` runs out of process and lists the owner's real services and accounts | OS-owned |
| S23 menu bar menus (E2E-MENU-*) | menu windows, all modes | Menu windows are absent from own-window composites; menus are covered as text (`menus.json` in the raw run) and by the two open-menu captures (Toolbox, canvas text context menu) | harness |

## Coverage-matrix rows with no capture

| Rows | Reason | Category |
|---|---|---|
| E2E-CAP-003 Fullscreen snapshot, E2E-BAR-005 Snap right-click (partial) | Needs live Screen Recording permission and a real display grab; the picker (S13) is captured with the "no recording grant" lens only and a synthetic lens | permission |
| E2E-CAP-010 multi-display, E2E-CAP-011 1x display | Needs a second display or a 1x panel; the harness renders at the host scale (2x) on one display | hardware |
| E2E-HOT-035 to 040 hotkeys firing while backgrounded | Needs the global hotkey to fire from another app, i.e. physical HID input; the Capture tab and key panel are captured (S17, S60) | hardware |
| E2E-SHEET-048 Open panel, 049 Save panel, 050 Page Setup, E2E-SHEET-022 Choose image folder, E2E-MENU-077 Spelling panel | OS-owned panels (NSOpenPanel and friends); the app-owned accessory is captured (S10: alone and inside the save panel in every mode). In `S10-export-panel` the system panel's body (name field, folder list, buttons) is hosted out of process and comes back empty, so the capture shows the panel's title and the real accessory window over a blank body | OS-owned |
| E2E-SHEET-051 Print panel | Needs a real printer destination | hardware |
| E2E-A11Y-006 VoiceOver speech | Needs spoken VoiceOver; the spoken scripts a screen reader would be told (generated from the AX tree, not real speech) are in `docs/design/evidence/osn-062-2026-10-11/spoken/` | hardware |
| E2E-MENU-066 to 076, 078, 079 (Hide Others, Show All, Bring All to Front, Pencil Smoothing, Arrow Head, Spelling items) | Menu bar items with no visual state of their own: menu windows are not captured (see S23); their effect on drawing is covered by the populated editor captures | harness |
| E2E-ICON-102 OpenSnap.icon (Dock/Finder rendering) | The harness captures only the app's own windows; the app icon is built and previewed with `ictool` (see the icon-composer notes), not by this run | harness |
| E2E-SET-024 persisted settings across relaunch, E2E-CAP-009 Snap from Link, E2E-DEST-031 to 037 upload journeys (success, failure, retry, cancel, Delete from Web, Test connection) as flows | Behaviours across time or network; the harness stubs the uploader and runs offline (sandbox denies network). The publish progress, success and error states and the busy and empty upload panels are captured (S21, S52, S58) | behaviour / unsafe |
| E2E-HIST-042, E2E-ALERT-006, E2E-SET-023, E2E-HOT-044, E2E-KEY-036 to 038, E2E-A11Y-001 to 005 and 007 | Keyboard behaviours (Return, Space, arrows, Escape, Command-D, Command-W, focus order); no pixels change. Resulting states (focus rings S28, glass hover/focus/dismissed variants S50 to S60) are captured | behaviour |

Panels formerly listed without a render are now covered by the glass surfaces: Toolbox (S50), Zoom (S51), Upload destinations (S52), Colour (S53), Size (S54), History date and drag-as (S55), Resize presets and anchor (S57), Destination protocol and source (S58), Capture key and modifiers (S60).

## Mode gaps

| Mode | Not captured | Reason |
|---|---|---|
| Reduce Transparency, Increase Contrast | S23 menu windows, the layout and pairs groups; text editing (S36) and Actual Size (S07) at 1024 and 1440 | S11M/S11E now cover 980, 1024, 1280, 1440 and full screen, and S13 to S15, S21, S22, S29 are in the `-surfaces` packs. Menus are not capturable as windows (see S23), layout and pairs are width-budget and before/after groups that are mode-independent, and the S36/S07 captures stay at 980 and 1280. Not a harness limit |
| Differentiate Without Color, Reduce Motion | all surfaces | Harness supports them (`--display`) but acceptance asked only for Reduce Transparency and Increase Contrast. Combined Increase Contrast plus Reduce Motion is in `S14 countdown-3-contrast-reduce-motion` |
| Increase Contrast + Reduce Transparency together | all | Not run as a pair here; each alone is. The pair exists in the older `m4-glass` pack |
| Font Awesome Pro icon mode | all | No Pro subset fonts in this build (Pro is opt-in with the owner's token and is not bundled or committed). Default mode, bundled Free vectors, is what is captured |
| Large widths beyond the visible frame | 1440 and full screen (2056 pt on this host) only; no 2560-wide or multi-display capture | Host display is 2056 x 1197 pt; wider needs another display (hardware) |
| Real system light/dark switch and real Reduce Transparency / Increase Contrast | all | System appearance and accessibility settings cannot be changed without touching global settings; the harness injects them inside its throwaway copy (rendered, not real) |
| Screen Recording backed content | picker lens, countdown over real desktop, flash over real desktop | Needs live Screen Recording permission; overlays are rendered in their own windows only |
| Welcome / first launch (S27) | all | The welcome document was removed; no surface exists |
| Actual Size at widths other than the S07 capture, text editing at 1024 and 1440 | those widths | Captured at 980 and 1280 (S36, S05, S07); other widths follow the same layout (width budget is captured in the layout group) |

## Round 3 findings verified fixed in round 4 (`8188b73`)

Each row was confirmed by opening the round 4 capture, not only by the machine checks (which pass: `check-eye-dump.py --strict` 0 failures and 0 advisories on all five packs, walker 0 violations).

| Round 3 finding | Confirmed in | What the capture shows |
|---|---|---|
| Secondary text on a selected fill under 4.5:1 ("S3-compatible", "Exported") | `base/S17-settings-upload-many-640-dark`, `base/S20-history-1120x850-selected-dark` | Seen: the selected Settings destination row and the selected History tile read "S3-compatible" and "Exported" as bright as the primary line; the new hard `selected` check passes on all five packs |
| Dark sheet plate not neutral / not painted | `base/S26-close-unsaved-dark`, `base/S16-permission-sheet-in-context-dark`, `increase-contrast-surfaces/S16-permission-sheet-in-context-dark-ic` | Seen: an opaque neutral plate; sampled rgb 38,38,40 at four points of the S26 plate, no desktop gradient showing through, buttons and focus ring crisp. S16 is the same in base and Increase Contrast |
| Light Overview card tinted wrong | `base/S07-actual-size-light` | Seen: the Overview card is a light grey wash, sampled rgb 222 to 226 on its face and 241 at its lower edge, with the thumbnail and its orange frame legible |
| S54 Size panel drew two focus rings | `base/S54-size-focus-dark` | Seen: one gold ring on the focused preset; the chosen preset carries only its fill |
| S56 radio ring ran into the label | `base/S56-settings-radios-focus-dark` | Seen: the "Both" ring stands off the radio and label with even padding, one ring |
| S58 light choice panel square corners | `base/S58-destination-protocol-rest-light` (and `S58-destination-acl-off-light`) | Seen: the open Protocol panel and the popups have rounded corners, the chosen row a rounded fill |
| S19 destination form help text | `base/S19-destinations-form-s3-in-context-light` | Seen: the S3-compatible form's Connection and Credentials rows and the whole four-line help paragraph are drawn with nothing clipped, and the Test help line sits above the footer buttons |

Still open (observation, not a check failure): the S19 `*-in-context` captures draw the destination sheet 15 px wider than the Settings window it hangs from (sheet edges at the capture edges, parent title bar narrower); still present in `S19-destinations-form-s3-in-context-light`, harness composition only.

## Defects the round 2 checks found (fixed)

| Surface | Finding |
|---|---|
| S51 `zoom-actual-size`, all 6 modes | Fixed in `a399d8a7`: the zoom pop-up face "Actual" needed 56 x 24 pt and was drawn in 54 x 25 pt, so `check-eye-dump.py --strict` and the text walker reported it cut off. S51 (every capture, base, Reduce Transparency and Increase Contrast) and S11M at 980 and 1280 (base) were recaptured at `a399d8a7`; `check-eye-dump.py --strict` exits 0 on all five packs and the walker reports 0 violations |

## Defects the round 3 checks found (fixed)

| Surface | Finding |
|---|---|
| Bottom bar "Original size" checkbox, Increase Contrast, dark appearance (42 captures: 31 in `increase-contrast`, 11 in `increase-contrast-surfaces`) | Fixed in `5d5221c`: the checked box's white label sampled 4.30 to 4.50:1 on the accent fill (about rgb 140,117,55) because `4d17d945` set the dark selected fill to 0.40 under Increase Contrast. The fill is now 0.35 (still above the plain dark 0.34 and 2.4:1 against the window; pinned in `PaletteTests` and `StateStylesTests`). Both Increase Contrast packs were recaptured at `5d5221c`: the box samples 4.82 to 5.03:1 (white on rgb 132,112,58 to 129,109,55) over 44 checked-box captures, and `check-eye-dump.py --strict` exits 0 on all five packs (0 failures, 0 advisories) |

Observation for the reviewer, carried from round 3 (not a check failure): in the S19 `*-in-context` captures the destination sheet is drawn 15 px wider than the Settings window it hangs from (sheet edges at the capture edges, parent title bar narrower), which a real AppKit sheet would not do; the sheet content itself is correct.

The round 2 defect (S51 `zoom-actual-size`) stays fixed: S51 passes `--strict` in all modes.

## Defects the round 4 checks found

None in the product. One harness issue: the new `selected` check read the palette-quantised desktop gradient of the packed PNGs as a selected fill (58 false failures, S15/S16/S21/S26/S39/S57); fixed in `tools/check-eye-dump.py` with a self-test case, see `REVIEW.md`. Layout JSON for the three `S29-help-bevel-*-light` base captures disappeared because the help window is now found and drawn (round 3 had missed it in those three).
