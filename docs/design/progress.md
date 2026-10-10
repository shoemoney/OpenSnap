# OpenSnap implementation progress

**Baseline:** `bad6617`, when implementation began (the rename and migration were already merged in `f7ff86b` and `d2dc3c9`).
**Main now:** `284f028`, after the thirteen implementation merges below, five more implementation merges (`3ee9503`, `4fca729`, `660cfe3`, `7c8bdb1`, `b538fcd`) and the E2E audit merges (see the E2E audit section).
**Status of 36 todos:** 29 done, 2 verified, 1 not-a-bug, 3 in-progress, 1 pending.

Per-todo state is in `backlog.json` (`status`, `mainState`, `implementation`). The roadmap has the milestone table (section 2b). Findings statuses in the roadmap (section 4) are still as at `dc1eb26`.

## Merges to main, in order

| # | Merge | Branch | Branch commits |
|---|---|---|---|
| 1 | `3431efc` | impl/osn-001-harness | `0f0db46`, `161e191`, `b919775`, `9e9ec8c`, `db973a6` |
| 2 | `8df7780` | impl/m4-tokens | `eee03d3`, `13c032c`, `0ed44b4`, `fac0cc7` |
| 3 | `f484d3e` | impl/m5-dest-history | `3be3870`, `26e2160`, `708b6bd`, `a2f3843`, `dd17d50` |
| 4 | `c53155c` | impl/t15-rail | `de7f511`, `891c197`, `ab4373d`, `b30ee32`, `356dde5`, `4f164ef`, `f9bc0fc`, `1e9d4de`, `e65662c`, `616c9b0`, `4981836`, `2189f4a`, `fef46c7`, `e2db58c` |
| 5 | `77bad0c` | impl/m3-identity-menus | `51e37a9`, `45dc148`, `dbf7461` |
| 6 | `f3ba77f` | impl/m5-capture | `75a9ee6`, `08f03e5`, `1eead53`, `8a9af59`, `1e6a089`, `8a0e8d9`, `b9a0f24` |
| 7 | `198274f` | docs/impl-progress | `cb1fc5b` |
| 8 | `0996da5` | impl/m7-gates | `90f70bc`, `2cbf59c`, `bb0659a`, `56393f8`, `8cdebcb`, `7852769`, `8c75d9e` |
| 9 | `efe2f68` | impl/m4-type | `462b8c7`, `aeaee06`, `cc3c5d9`, `81131ae`, `7526fc5`, `b6658d2` |
| 10 | `accfedd` | impl/m6-displayoptions | `de21b6e`, `d0f8013`, `2dc613e`, `eaab72f`, `f975dfa` |
| 11 | `439d734` | impl/m4-icons | `637792d`, `3ca617d`, `8f66c62`, `515cab1` |
| 12 | `8015360` | impl/m4-glass | `7b0c636`, `acfc154`, `850a2e9`, `622ca82`, `da2738d`, `ff3eeb4`, `212059c`, `33b8b3e` |
| 13 | `658a16f` | impl/m4-window | `d59b0a1`, `2cc0415`, `a3d0afe`, `aeaf890`, `52d0398`, `7bf20f8`, `1a65cd0` |
| 14 | `3ee9503` | impl/m4-states | `90aa46d`, `3253979`, `8c70583`, `cc97054`, `feca8e8` (OSN-044, and OSN-061 part 2) |
| 15 | `4fca729` | impl/m6-a11y | `ab367c1`, `c775070` (OSN-062 walker, sheet Return and Escape) |
| 16 | `660cfe3` | impl/e2e-infra | `cd1ce87`, `afd60c5` (E2E launcher, guard, inventory) |
| 17 | `7c8bdb1` | impl/m5-upload-a11y | `fc61ac7`, `fbe4d67` (OSN-054, OSN-060, OSN-062 hooks; export formats) |
| 18 | `b538fcd` | fix/tooltip-crash-e2e | `cd1ce87`, `afd60c5`, `5937858`, `a89163d`, `15d5ec2` (P0 tooltip hover crash, E2E infra) |

Merges 1 to 6 list the branch commits the orchestrator named. Merges 7 to 13 list the non-merge commits in git history for each branch. Merges 14 to 18 list the commits reachable from the second parent and not from the first. In all cases, merges of main into a branch are not listed.

## Issue to implementation to test to render

Each row is a todo that is done, verified, or not-a-bug. Commits in brackets are the branch commits that carry the work, attributed by commit subject. "Tested" gives only the counts the sources record. "Rendered" is the evidence folder under `docs/design/evidence/impl-2026-10-09/`; `n/a` means no rendered evidence is recorded for that todo.

| Todo | Status | Implemented (commit) | Tested | Rendered (evidence) |
|---|---|---|---|---|
| OSN-001 | done | `3431efc`; `9e9ec8c` retired `eye-dump.sh` | `tools/test-eye-dump-audit-guard.py`, 43 can-fail checks | n/a (tooling) |
| OSN-002 | done | decisions, no merge | n/a (decision record) | n/a |
| OSN-010 | done | `c53155c` (`891c197`, `ab4373d`, `4f164ef`, `2189f4a`) | app-safety 145/145; GlassChromeTests 13266 checks | `m1-rail` |
| OSN-011 | done | `c53155c` (`de7f511`) | same suites as OSN-010 | `m1-rail` |
| OSN-012 | done | `c53155c` (`b30ee32`, `356dde5`) | rail-removal regression suite; same suites | n/a |
| OSN-013 | done | `c53155c` (`f9bc0fc` to `e2db58c`) | 80-capture matrix, visual (no unit count); independently reviewed | `m1-rail`, 80 at `fef46c7` |
| OSN-014 | done | `c53155c` (`ab4373d`, `2189f4a`, `fef46c7`) | Frame captures in the matrix | `m1-rail` |
| OSN-020 | done | `77bad0c` (`45dc148`, `dbf7461`) | `tools/check-clean-clone.sh` passed on `dbf7461` | n/a |
| OSN-021 | verified | before baseline: `fc77158`, `691b890`, `12c6dfa` | source gates clean | `m5-capture` (countdown) |
| OSN-022 | verified | before baseline: `42c52d8`, `6acc21c` | source gates clean | n/a |
| OSN-023 | done | `77bad0c` (`45dc148`) | StatusItemSupportTests artwork gate | n/a |
| OSN-024 | done | `77bad0c` (`45dc148`) | no silent skips; no `original/` references | n/a |
| OSN-030 | done | before baseline: `f7ff86b`, `d2dc3c9` | migration tests green on synthetic temp stores | n/a |
| OSN-031 | done | `77bad0c` (`51e37a9`) | menu parity tests; `tools/check-brand.py` | n/a |
| OSN-032 | done | `f484d3e`; Toolbox ellipsis in `77bad0c` | none recorded | n/a |
| OSN-040 | done | `8df7780` (`eee03d3`) | Typography, Palette and Metrics tests; `tools/check-tokens.py` (report mode) | n/a |
| OSN-041 | done | `efe2f68` (`462b8c7`, `aeaee06`, `cc3c5d9`, `81131ae`, `7526fc5`, `b6658d2`); `Alert.make` finished in `658a16f` (step 5) | app-safety 153/153 at `efe2f68`; literal sweep: font literals 68 to 6, colour literals 17 to 8; `tools/check-tooltips.py` | `m4-window` (step 5 only) |
| OSN-042 | done | `8015360` (`7b0c636`, `acfc154`, `850a2e9`, `622ca82`, `da2738d`, `ff3eeb4`, `212059c`, `33b8b3e`) | app-safety 154/154 (cases for plates, well and G5 in `acfc154`) | `m4-glass`, 98 at `da2738d` |
| OSN-043 | done | `658a16f` (`d59b0a1`, `2cc0415`, `a3d0afe`, `aeaf890`, `52d0398`, `7bf20f8`, `1a65cd0`) | app-safety 166/166; window-chrome and AppAlert suites (the alert check count differs between sources; see the gaps) | `m4-window`, 50 at `7bf20f8` |
| OSN-045 | done | `439d734` (`637792d`, `3ca617d`, `8f66c62`, `515cab1`) | IconCoverageTests: 980 checks | none recorded |
| OSN-050 | done | `f3ba77f` (`75a9ee6` to `b9a0f24`) | `08f03e5` tightened checks (no count) | `m5-capture`, 38 at `8a0e8d9` |
| OSN-052 | done | `f484d3e` (`3be3870`, `26e2160`, `708b6bd`, `dd17d50`) | harness variants in `708b6bd` (no count) | n/a |
| OSN-053 | done | `f484d3e` (`3be3870`, `26e2160`, `708b6bd`) | harness History variants in `708b6bd` (no count) | n/a |
| OSN-055 | done | `77bad0c` (`51e37a9`) | menu parity tests | n/a |
| OSN-056 | done | `f3ba77f` (`8a9af59`) | none recorded | `m5-capture` (hint plate clear of title bar and bars) |
| OSN-057 | not-a-bug | `8df7780` (`13c032c`) | regression test in `13c032c` | n/a |
| OSN-058 | done | `8df7780` (`0ed44b4`, `fac0cc7`) | none recorded | n/a |

Suite counts are the ones the sources record. No other counts are claimed.

Todos in progress, partly landed, or landed since `658a16f`:

| Todo | Status | Implemented (commit) | Tested | Rendered (evidence) |
|---|---|---|---|---|
| OSN-044 | done | `3ee9503` (`90aa46d`, `3253979`, `8c70583`, `cc97054`, `feca8e8`) | merge changes 7 files under `tests/`; counts not recorded in this pass | `m4-states`, 158 captures at `cc97054` |
| OSN-051 | done | `e124f77` (integrated at `a79a1d8`) | SettingsWindowTests 1405; G4 0 violations; app-safety 166/166 | `m5-settings`, 36 at `a48d0df` |
| OSN-054 | done | `7c8bdb1` (`fc61ac7`, `fbe4d67`) | merge changes 12 files; real-click S3 upload in J2 and J4 | `m5-upload`, 30 at `fc61ac7`; `audit-fix-1`, 74 at `8e7a37d` |
| OSN-060 | done | `7c8bdb1`; sheet Return and Escape in `4fca729` | `AccessibilityAuditTests` key-loop and Escape and Return cases (T7 tests 3 and 4) | J1 real-click Tab walk (F-J1-007 PASS) |
| OSN-062 | in-progress | `7c8bdb1` (labels, announcements); `4fca729` (G10 walker, 32 surfaces, 0 violations) | walker: 0 violations; manual VoiceOver pass not recorded | none for the manual pass |
| OSN-061 | done | part 1 `accfedd` (`de21b6e`, `d0f8013`, `2dc613e`, `eaab72f`, `f975dfa`); part 2 `3ee9503` | DisplayOptionsTests: 92 checks (part 1) | J3 rendered positive controls for all four options (`e2e-2026-10-10/j3`, rendered only) |
| OSN-070 | in-progress (partial) | `0996da5` (`90f70bc`, `2cbf59c`, `bb0659a`); wired into `tools/test.py` by `efe2f68` (`b6658d2`) | can-fail self-tests for G6 and G11 (`90f70bc`); seeded can-fail cases for G4 (`bb0659a`) | none |
| OSN-072 | in-progress (partial) | `0996da5` (`56393f8`, `8cdebcb`); release dry run in a temp clone | synthetic dry run: 58 documents, 2 destinations; a re-run is a no-op | none |

## Decisions in this period

- **Q3: option B (custom bars), on spike evidence.** An `NSToolbar` spike showed 14 of 17 top-bar items visible at 980 pt (14 of 18 in Frame mode), and needed 1060 pt (1120 in Frame mode) to show all. Implemented in `8015360` (OSN-042): 26 glass surfaces became 8 group plates in 2 containers.
- **Q4: full screen is enabled, and Frame refuses in full screen** with "Exit full screen to use Frame". Implemented in `658a16f` (OSN-043).
- **Q5: capture flash kept, peak 0.7.** Reduce Motion gives a single 0.05 s frame. "Show capture flash" off means no flash at any time. Resolved before this period; recorded in `f3ba77f` (OSN-050).
- **Minimum height: 640 pt window (608 pt content).** T15 governs; T8's 680 pt is not adopted. Width is measured from the live bars and floored at 980 pt. Implemented in `658a16f` (OSN-043).

## OSN-043 and OSN-041 step 5 (merged in `658a16f`)

Unified window chrome and app-owned alerts. Evidence: `evidence/impl-2026-10-09/m4-window/` (50 captures, source `7bf20f8`).

**Decisions**

- **Titlebar stays separate** (orchestrator). A full-size-content title bar would cost about 78 pt beside the traffic lights and break the 980 Frame fit (16 pt slack). Measured result: `titlebarSeparatorStyle = .none` plus the surface window colour was not enough (the opaque title bar is 41/40/39 over a 30/30/30 window in dark, with a 1 pt line), so the title bar is transparent outside Frame mode and opaque again inside it; no layout cost. Title and subtitle text are system-drawn (OS limit).
- **Frame and full screen exclude each other by refusal.** Entering Frame in full screen shows "Exit full screen to use Frame"; while Frame is up the window drops `.fullScreenPrimary`; a stray full-screen entry ends Frame. Refusing was chosen over "exit full screen first" because `toggleFullScreen` is an animated, cancellable transition, so entering Frame afterwards needs a deferred state machine with several failure modes, and Frame is a see-through window over the desktop, which a full-screen Space cannot show.
- **Minimum height stays 640** (608 content), not T8's 680; width is measured from the live bars, floored at 980.
- **Sheets, not modals,** for every document-scoped question. A question from New, Open or a capture is single at a time (a sheet does not stop the menu bar); Quit may always ask, stacks on the open sheet, and answers AppKit later through `reply(toApplicationShouldTerminate:)`. A hidden or minimised editor cannot carry a sheet, so the alert is a panel of its own and Quit never waits on an unseen question.
- The save panel names the document: a file the user just named in Save As becomes the document's name and title. Saving in place keeps the name.
- The Discard button is now "Don’t Save" (Command-D, destructive styling), as macOS words it.

**Alert sites converted** (all in `App.swift`, now `AppAlert` sheets): `error(_:)` (every open, save, export, upload, capture and history failure), `confirmDiscard` (was `allowDiscard`, used by New, Open, captures, Frame completion and Quit), `removeHistory` (Hide, Move to Trash), `deleteHistoryRemote` (Delete from Web), and `prompt` (Rename, Timed Snapshot, Snap from Link). `NSOpenPanel`, `NSSavePanel`, the export panel and `NSPageLayout` stay system modals. Left to the other worker, as recorded before the merge and not re-checked in this pass: `PublishingDestinationsView.swift` (remove-destination confirmation).

**OS-owned limitations:** see the section below.

**Tests:** app-safety 166 (154 before; 12 new window-chrome cases, one existing Frame-prompt case changed on purpose: the Discard prompt is now a sheet on the Frame window, so it no longer runs with the pre-Frame level), `AppAlertTests` 77 checks, `GlassChromeTests` 13544 checks. Twelve can-fail mutations each fail the suite that should catch them and were reverted.

## OSN-054, OSN-060 and OSN-062 (merged in `7c8bdb1`; OSN-062 still needs the manual VoiceOver pass)

Upload states in the status slot, the main-window keyboard and VoiceOver hooks. Evidence: `evidence/impl-2026-10-09/m5-upload/` (see the evidence index there).

**Decisions**

- **`UploadState`** (`Sources/UploadStatus.swift`) is `.idle`, `.uploading(name)`, `.success(url, copied)`, `.failure(message)`. `AppDelegate.uploadState` drives `refreshStatusText()`, the chrome's `UploadStatusControls` (a 20 pt indeterminate spinner and the inline commands, built once and only hidden or shown) and the announcements. The bar does not widen: `measuredWindowWidth()` is unchanged in every state (FooterLayoutTests).
- **The Original size checkbox is hidden whenever an upload has the slot**, not only while it runs. Measured at 980 pt (FooterLayoutTests): the status slot is 309 pt, the checkbox takes 141 of it (129 + 12) and an idle status gets 172 pt. Open and Copy take 120 pt, which would leave 52 pt, under the 96 pt "Link copied" needs. With the checkbox hidden "Link copied" fits whole, uploading leaves the name 221 pt and the failure row leaves 119 pt for "Error: …" beside Retry and Details…. The checkbox returns with the idle state: after the 4 s of "Link copied", or once the error is dealt with. A failure stays until Retry, the next upload or a different document, so the checkbox is out of reach for that time (the Export panel has its own Original size option). This widens the brief ("for the duration") on purpose.
- **Failure is inline.** `Error: <first line>` with Retry and Details…; Details… opens an `AppAlert` titled "Upload failed" with the whole error. The upload-failure alert path is gone; "destination not configured" still opens Settings first. A failure belongs to the document it was raised for and is dropped when the document is replaced. Retry re-invokes the uploader with the same bytes and the same file name.
- **Retry and Details… are text, Cancel, Open and Copy are icons** (xmark, up-right-from-square, copy: all already in `FAIcon`). Adding "arrow-rotate-right" and "circle-info" would need Free SVG paths for the third-party notice; text also reads better for a recovery action.
- **Shutdown barrier.** `receivePublishing` clears the spinner before the `terminationStarted` guard, so a Quit that cancels a running upload leaves no spinner behind, and an inline error is not an alert, so `finishShutdownDecision` has nothing new to wait for. A refused Quit keeps the error and its commands. After a refused Quit the coordinator stays shut down (`publish` refuses permanently); that is the existing policy, so Retry after a refused Quit reports "Upload cancelled".
- **Export panel:** PNG, JPG, PDF, TIFF, SVG. Dropped from the panel: GIF, BMP and OpenSnap (a stored choice of those reads as PNG). The encoder still reads GIF and BMP (`ImageExport`), and Save As writes `.opensnap`; nothing else changed. The JPG quality row is the text "JPG quality 75 %" (the locked slider is gone).
- **`ImageFormat` enum: deferred.** Moving the persisted choice from the `DragFormatChoice` row index to an `OpenSnap.imageFormat` key needs a defaults migration of the owner's real store, which this run is not allowed to touch (see OSN-072); the byte-level tests and the stored-row shim stay as they are.
- **Drag and file names:** the fallback when the document has no name is "Untitled" (was "OpenSnap"). No "Skitch" default name remained.
- **Focus Toolbar** is in the **Window** menu (Option-Command-T): the bars are not an `NSToolbar`, so the system's Move-focus-to-toolbar shortcut finds nothing, and the Window menu is where a command about the window's own parts sits. It puts the keyboard on Hide and, until the window stops being key, lets the bars take Tab as if Full Keyboard Access were on.
- **Key-view loop.** `autorecalculatesKeyViewLoop = true`, `initialFirstResponder = canvas`. The geometric order is top bar, canvas, bottom bar. Buttons and pop-ups follow Full Keyboard Access like every AppKit button (`KeyboardNavigation`, a test seam). **Tab on the canvas stays the pencil swap**; **Control-Tab and Control-Shift-Tab leave the canvas** forward and back. The Size and Color popovers set `nextKeyView` by hand (they are windows of their own).
- **VoiceOver:** tools are "<Name> tool", Upload is "Upload image" (the tooltip begins the same way, then explains the right-click menu), the Toolbox is "Toolbox menu", the menu-bar item is "Show or hide OpenSnap", the editor status is a static text. The Size pill reads the whole number, steps one preset and has the custom action "Show size options". Announcements: upload start, success and error (high priority), capture success, Frame on and off, Undo and Redo by action name.
- **History:** the grid is the first responder, so Return opens the selection and Escape closes the window from the moment it opens; Escape from any other control reaches the window controller.
- **Audit tool change:** `tests/AccessibilityAudit.swift` no longer judges a focusable `NSClipView` or `NSScrollView` subclass as a control (the canvas inside is judged on its own); the main window uses a clip view subclass for centring.

## Audit fix batch 1 (branch `fix/audit-batch-1`, not merged)

Owner-authorized end-to-end audit, first batch. Evidence: `evidence/impl-2026-10-09/audit-fix-1/` (74 captures, source `8e7a37d`). This supersedes two OSN-054 decisions above (Retry and Details… as text; the checkbox hidden for the whole upload).

- **Upload commands (finding 1).** Retry is `arrow-rotate-right` and Details is `circle-info` (Font Awesome Free 7.3.1 solid, path data verbatim from the pinned package SVG, added to `FontAwesomeFree.swift` like `gear`). Cancel, Open, Copy, Retry and Details are 48 x 36 icon buttons with a **rest plate** (`CommandButton.showsRestPlate`, `StateStyles.command(restPlate:)`: label at 0.06, 0.12 under Increase Contrast, the same faint fill an unselected PNG | JPG segment has; hover and press add to it). Icons rather than plated text because the 980 slot is 309 pt: Retry plus Details… as text took about 190 pt and left the error 119 pt; two icons take 120 pt and leave 193 pt. Every other command in the bars is an icon with a tooltip. They sit on the bar, not on a ninth glass plate, because G5 pins the bars to exactly eight plates (a ninth plate failed `glassDepthChecks`). No text is left in the row, so nothing falls under 20 pt. Labels and tooltips: "Retry upload", "Show error details".
- **Link copied (finding 2).** The status carries the link: "Link copied · cdn.example.com/pics/name.png" (scheme dropped), cut in the middle three characters at a time as the slot narrows (host start and file name end kept); when no step fits, the whole sentence is cut at its tail ("Link copied · cdn.exa…"), so the slot is never empty and there is no double ellipsis. The full URL stays on the tooltip and the VoiceOver help; the 4 s expiry is untouched.
- **Original size checkbox (finding 3).** `ModernEditorChrome.slotHasRoomForCheckbox(during:)`: the checkbox stays during an upload only when the measured status slot (window width less the four plates and their gaps) holds the checkbox plus 200 pt of message plus the spinner and commands. At 980 (slot 309) it steps aside in every state; at 1440 (slot 769) it stays; the answer follows a resize (`windowDidResize`). Thresholds: about 1104 pt of window for uploading, 1132 for an error or Link copied.
- **Wipe (finding 4).** `WipeStage.actionName` / `.toolTip` replace the legacy titles on the button: wipe stage "Remove annotations", clear stage "Clear image", blank stage a disabled "Clear image" whose tooltip and help are "Nothing to clear". Stage logic and the `wipe` selector are unchanged. The Edit menu's "Wipe" item is static (it never mirrored the stage; a test pins its title), so it was left alone and the Toolbox menu has no Wipe entry.
- **Remove destination (finding 5).** `PublishingDestinationsView.confirmRemoval` is now asynchronous (`(title, detail, answer)`); the default is an `AppAlert` sheet on the destinations sheet: "Remove “name”?", destructive Remove (Return) and Cancel (Escape). `PublishingCoordinator.cancelSettings` answers an open question as Cancel before it ends the sheet, so the shutdown barrier is unchanged.
- **Colour popover (finding 6, verified).** With a colour that matched no preset nothing in the popover was marked. `BezelCustomColorButton` now carries the current colour as a chip with a check and the accent outline, and VoiceOver hears "Selected".
- **Space pass (finding 7).** Only one demonstrable defect, in the colour popover: swatches drew 3 pt inside their frames while the Custom color… row spanned the full frame (3 pt proud on the left, 7 pt on the right, margins 15 left / 19 right), and the row sat 2 pt from the bottom edge against 7 pt at the top. Now the swatch pitch is 45 and the row spans the drawn grid exactly (15 to 231 pt, margins 15 / 15); top and bottom margins are 12 pt; the popover is 246 x 155 (was 246 x 140). The bottom bar itself at 980/1280/1440 showed no further waste: with the checkbox the status already takes the whole slot and the idle status drops bytes then tool by design.

Tests changed on purpose: the Wipe tests that pinned "Blank", "Clear" and "Wipe" (AppSafetyTests, AppSafetyModernCases, GlassChromeTests); the "Link copied" equality in AppSafetyWebpostCases; the Retry/Details… text test in AppSafetyUploadCases; the FontAwesomeIcons count (35 to 37); the footer checks that hid the checkbox unconditionally; the "no fill at rest" check, which now exempts the rest-plated upload commands; `confirmRemoval` seam in AppSafetyWebpostCases (now asynchronous). `tools/test.py` adds `AppAlert.swift` to the suites that compile `PublishingDestinationsView.swift`.

## AWS live validation (2026-10-09)

Owner-authorized, via root. Run at about 21:30 CDT on 2026-10-09.

- **Scope:** OpenSnap's own S3 code path, using the default AWS profile read in place. The credentials were never copied or printed.
- **Read-only check:** credentials and bucket verified.
- **Upload:** one synthetic object, `pics/opensnap-validation-20261009213258-19279.png` (74 bytes, `image/png`). The public CDN URL returned HTTP 200 with identical bytes.
- **Delete:** the object was removed through the app's delete path. S3 now returns 404 and CloudFront returns 403 for it.
- **Not touched:** no other object was read or changed. No IAM, infrastructure or CloudFront change was made.

Recorded as validation evidence under OSN-054 and OSN-072. It partly satisfies OSN-072's "AWS cdn upload dry run". OSN-054 stays pending, because the upload UX (progress, success, errors, announcements) is not built.

## E2E audit (owner-authorized, 2026-10-09 to 2026-10-10)

Owner authorization: Jeremy, 2026-10-09 23:27 CDT: audit every option and every icon, and ask whether each looks as good as it can and uses space well. The plan is [`e2e-audit-plan.md`](e2e-audit-plan.md). The method, inventory and launcher are in [`e2e/README.md`](e2e/README.md).

**Evidence classes are never merged.** `E2E` is a real click or key in an isolated session copy, with the result seen in a screenshot or an AX read. `rendered` is a harness capture (`tools/eye-dump-audit.sh`): the app drew the state in-process, which shows how it looks, not that a user can reach it. `unit/source` is a named existing test. `unverified` means nothing has been recorded yet.

### Journeys

| Journey | Scope | Source revision | Merge | Result |
|---|---|---|---|---|
| J1 editor core | Real clicks and keys: drawing, text, colour, size, shadow, Resize, crop, full screen, Toolbox, Photos, keyboard walk | `15d5ec2` | `10040ba` | 26 findings (F-J1-001 to 026); 87 image files in `e2e-2026-10-10/j1/` (86 captures per the merge message) |
| J2 History, Settings, Destinations, upload | Real clicks: History actions and sheets, Settings tabs, Destinations forms, About, and one live S3 synthetic upload | `10040ba` | `2cc07da` | 24 findings (F-J2-001 to 024); 78 captures in `e2e-2026-10-10/j2/` |
| J3 rendered matrix | **Rendered only, not E2E.** Light and dark, five sizes, Reduce Transparency, Increase Contrast, Differentiate Without Color, Reduce Motion and combinations, with positive controls | `3194247` | `baea204` | 11 findings (F-J3-001 to 011); 111 captures packed in `e2e-2026-10-10/j3/` from 3,338 PNGs over 18 runs |
| J4 real-click retest | Real-click retest of the 47 fixes from batches 1 to 3c, plus the live S3 delete through the app | `94b7aa5` | `284f028` | 38 pass, 7 partial, 2 unverified of 47; 7 new P3 findings (F-J4-001 to 007); 76 captures in `e2e-2026-10-10/j4/`, AWS log in `e2e/j4-aws-log.md` |

Two notes on counts that the sources disagree on. The J3 findings text calls its packed set "106-capture" in one place; the folder and the checker both count 111, and 111 is used here. The J1 merge message says 86 captures, while the folder holds 87 image files.

### Fix batches

| Batch | Branch | Merge | Evidence (captures) |
|---|---|---|---|
| 1 | `fix/audit-batch-1` | `529af8b` | `impl-2026-10-09/audit-fix-1/` (74, `8e7a37d`) |
| 2 | `fix/audit-batch-2` | `ad69580` | `impl-2026-10-09/audit-fix-2/` (38, `2275c5b`) |
| 3a | `fix/audit-batch-3a` | `ced431b` | `impl-2026-10-09/audit-fix-3a/` (24, `cc05825`) |
| 3b | `fix/audit-batch-3b` | `3194247` | `impl-2026-10-09/audit-fix-3b/` (184, `526ab3c` and `41b2507`); before twins in `audit-fix-3b-before/` (62, `2cc07da`) |
| 3c | `fix/audit-batch-3c` | `94b7aa5` | `impl-2026-10-09/audit-fix-3c/` (52, `0edc3ce` and `6469efb`) |
| 4 | `fix/audit-batch-4` | **in progress, not merged** | Scope: the J3 findings, the J4 P3s (F-J4-001 to 007), and one capture-shortcut surface (F-J2-020) |

### Finding dispositions

Derived from the J4 retest table in `e2e/findings.md`. "Pass" means the original steps no longer reproduce the defect and the corrected behaviour was seen.

| Journey | Findings | Pass (fixed) | Partial | Unverified | Gap, deferred or doc-only | Open for batch 4 |
|---|---|---|---|---|---|---|
| J1 | 26 (4 P1, 10 P2, 12 P3) | 22 | 2 (F-J1-009, 016) | 0 | 2: F-J1-012 gap (never retested), F-J1-023 deferred | 0 |
| J2 | 24 (3 P1, 17 P2, 4 P3) | 16 | 5 (F-J2-009, 014, 015, 020, 022) | 2 (F-J2-011, 017) | 1: F-J2-024 doc-only, not retested | 0 |
| J3 | 11 (3 P2, 8 P3) | not retested | n/a | n/a | F-J3-008 and 010 are OS-owned (see gaps) | 11 |
| J4 | 7 new (P3) | n/a | n/a | n/a | n/a | 7 |
| **Total** | **68** | **38** | **7** | **2** | **3** (1 gap, 1 deferred, 1 doc-only) | **18** |

The 68 findings split as 38 pass, 7 partial, 2 unverified, 1 gap (F-J1-012), 1 deferred (F-J1-023), 1 doc-only (F-J2-024) and 18 open for batch 4 (11 from J3, 7 from J4). Totals check: 38 + 7 + 2 + 1 + 1 + 1 + 18 = 68.

Two notes from J4 that matter for claims. The live S3 delete was confirmed (head-object returned 404 and the app's own delete path ran), but the public CDN link still answered 200 for a while (F-J4-003, cache). The fractional-size finding is not reproduced in real use: every size seen was an integer.

### Coverage matrix

Source of truth: `e2e/coverage-matrix.md` (one row per audit ID) and `e2e/inventory.json` (the same 589 entries).

| Evidence class | Rows in `coverage-matrix.md` |
|---|---|
| `E2E` (real interaction) | 258 |
| `rendered` (harness capture, not real-click) | 94 |
| `unit/source` (named test) | 91 |
| `unverified` (nothing recorded yet) | 146 |
| **Total** | **589** |

Exercise verdicts in `inventory.json`: `e2e` 511, `e2e-partial` 53, `gap` 25. The 146 `unverified` rows are real work left, and they are not counted as covered anywhere in this document.

### Evidence folders

All paths are under `docs/design/evidence/`. Each folder with a `captures.md` or `manifest.json` lists every capture and its source SHA.

| Folder | What it holds |
|---|---|
| `e2e-2026-10-10/j1/` | J1 real-click captures (editor core), from source `15d5ec2`. Also `menus-ax-dump.txt`. |
| `e2e-2026-10-10/j2/` | J2 real-click captures (History, Settings, Destinations, About, one live S3 upload), from source `10040ba`. |
| `e2e-2026-10-10/j3/` | J3 **rendered** matrix: 111 harness captures with `captures.md`, `manifest.json`, `layout/` and `safety.txt`, source `3194247`. Not real-click. |
| `e2e-2026-10-10/j3-diffs/` | Eight side-by-side composites that prove the J3 display-option positive controls. Rendered only. |
| `e2e-2026-10-10/j4/` | J4 real-click retest captures (the 47 fixes plus the live S3 delete), from source `94b7aa5`. |
| `impl-2026-10-09/audit-fix-1/` | Batch 1 visual acceptance (74 captures, `8e7a37d`). |
| `impl-2026-10-09/audit-fix-2/` | Batch 2 visual acceptance (38 captures, `2275c5b`). |
| `impl-2026-10-09/audit-fix-3a/` | Batch 3a visual acceptance (24 captures, `cc05825`). |
| `impl-2026-10-09/audit-fix-3b/` | Batch 3b visual acceptance (184 captures, `526ab3c`, Settings re-captured at `41b2507`). |
| `impl-2026-10-09/audit-fix-3b-before/` | Batch 3b before-state twins (62 captures, `2cc07da`, dark). |
| `impl-2026-10-09/audit-fix-3c/` | Batch 3c visual acceptance (52 captures, `0edc3ce` and `6469efb`). |
| `impl-2026-10-09/m4-states/` | OSN-044 and OSN-061 part 2 (158 captures, `cc97054`). |
| `impl-2026-10-09/m5-upload/` | OSN-054 upload states in the status slot (30 captures, `fc61ac7`). |

The rendered folders above are harness renders. Do not read them as real-click proof.

### E2E audit gaps (not proven by this audit)

These are outside what the harness or the isolated session could prove. They are listed, not waived.

- **VoiceOver speech.** The AX dumps and the G10 walker are structural checks. The manual pass for OSN-062 is not recorded.
- **Live Screen Recording capture**, including the Frame-mode scroller question (VF-27) and the countdown over a live desktop.
- **1x and multi-display.** The only display was 2x Retina. The 1x menu-bar check (OSN-023) is not done.
- **Photos library contents.** J1 opened the Photos sheet in its empty state only. The populated browser reads the real library and was not exercised.
- **OS-owned panels:** Save, Open, Print, Share, the Page Setup and Print panels, and the Colors panel internals.
- **Printer.** Nothing was printed.
- **Held-modifier gestures**, such as a drag made while holding Shift or Option.
- **Context menus** (History tiles, Upload button) are not reachable by a synthetic right-click.
- **⌘1 to ⌘4 in Settings** (F-J2-011): the harness maps chords to menu items, and ⌘2 would start a real full-screen capture of the owner's display. A real-keyboard check is still open.
- **Window title text and system radio and checkbox drawing** are OS-owned (F-J3-008, F-J3-010).
- **Drag well Export panel** (F-J1-012, plausible and unconfirmed).
- **Field names in the destination forms** (F-J2-017): the AX tool cannot show whether an explicit label exists.
- **FTP and FTPS destination forms** were not opened in J2 or J4.
- **Timed UI states:** the 12 s success-line hold, the Retrying label and the Upload cancelled notice (needs a slow network). Only one real upload was allowed.
- **Minimum-size reflow** of History at 880 × 600 (F-J2-009): no window resize tool.
- **Clipboard:** it held no text before the run, so non-text contents could not be saved; it was reset to empty text at the end.

## OS-owned limitations

These are outside app control. They are recorded here, not waived silently.

- Menu-bar strip titles.
- Window title-bar title and subtitle text.
- System tooltips inside the Save, Open, Fonts and Colors panels, and NSMenuItem tooltips.
- Save, Open, Export and Page Setup panels.
- Fonts and Colors panels.
- Traffic-light tooltips.

App-specific alerts are no longer NSAlert: they are app-owned sheets at 20 pt (OSN-043). App-owned 20 pt tooltips are in `efe2f68` (OSN-041).

## Open items and gaps

- **Round-1 incident (OSN-001):** a can-fail proof deleted the owner's real `com.shoemoney.opensnap` defaults plist. Cause: a cleanup trap was installed before an id refusal. Fixed in `db973a6`. The SkitchRedux store and `com.shoemoney.skitch-redux.plist` hashed unchanged. The migration marker is a file in the absent OpenSnap folder, so the parked migration is unaffected.
- **Unsafe tool, resolved:** `tools/test-native-startup.py` now runs only a throwaway-id temp copy, behind a store guard (`efe2f68`). The warning from the earlier pass no longer applies.
- **OSN-042 (merged in `8015360`):** the phantom capsule under Snap and the full-screen salmon tint are gone (no per-button glass, no backdrop or bleed). Open: the legacy-scroller corner is slightly lighter than the well (AppKit draws it; there is no public API). Controls are 36 pt tall inside 44 pt bars; to be reviewed at sign-off (OSN-071). Evidence: `evidence/impl-2026-10-09/m4-glass/`.
- **Size popover** can overhang the window edge. It stays on screen and is accepted as standard NSPopover behaviour.
- **Canvas centring** was a pre-existing bug, also present at `bad6617`. It is fixed for document changes in the rail-removal branch (`c53155c`).
- **Settings (OSN-051):** merged in `e124f77`; the full integration suite passed (app-safety 166/166). The window title follows the selected tab (no "Preferences").
- **OSN-044:** merged in `3ee9503`, with OSN-061 part 2.
- **OSN-061:** parts 1 and 2 are on main (`accfedd`, `3ee9503`); done.
- **OSN-062:** labels, announcements and the audit walker are on main; the recorded manual VoiceOver pass is not done, so the todo is in-progress.
- **OSN-070:** not recorded as landed: G3 (`check-user-strings.py`), the dynamic Skitch-string check, and a layout-fit-at-980 gate beyond the measured-width test in `658a16f`. G5 and G9 are not further recorded in this pass.
- **OSN-072:** migration on a copy of the owner's real store is not authorized in this run. Synthetic temp stores only. The release work is a dry run only: no tag, push, upload or release.
- **OSN-054:** the upload UX is merged (`7c8bdb1`). The AWS run on 2026-10-09 is validation evidence; the E2E audit added a live upload (J2) and a live delete through the app (J4).
- **Not run:** live screen capture; real popover translucency; VoiceOver speech (OSN-062 manual pass); Reduce Transparency alone and Increase Contrast alone captures (both together are in `m4-glass`); FA Pro icon mode; the OSN-071 visual gallery and independent visual sign-off.
- **OSN-023:** manual 1x and 2x menu-bar check not done.
- **Alert check count reconciled:** the full integration run at `a79a1d8` prints `AppAlertTests: 77 checks passed`; the `2cc0415` commit message figure (74) predates later additions.
- **Not done:** no push and no release. The first real launch and migration on the owner's machine is parked by the owner.
