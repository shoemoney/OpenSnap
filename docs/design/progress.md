# OpenSnap implementation progress

**Baseline:** `bad6617`, when implementation began (the rename and migration were already merged in `f7ff86b` and `d2dc3c9`).
**Main now:** `33743c5`. The eighteen implementation merges below are followed by the E2E audit merges since `284f028`, listed in the E2E audit section.
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

## Audit fix batch 1 (branch `fix/audit-batch-1`, merged in `529af8b`)

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

**Evidence classes are never merged.** `E2E` is a real click or key in an isolated session copy, with the result seen in a screenshot or an AX read. `rendered` is a harness capture (`tools/eye-dump-audit.sh`): the app drew the state in-process, which shows how it looks, not that a user can reach it. `unit/source` is a named existing test. `unverified` is a row the audit could not exercise; it carries exactly one gap reason. `retired` is a row whose surface the app removed or replaced; it is counted in no other class.

### Merges since 284f028

Merges to main, in merge order. Merges of main into the batch and probe branches (`e41f0c2`, `663fa39`, `082ff95`, `cc764dc`, `41eade2`, `26c8be3`, `a8cfc00`) are not listed.

| Merge | Branch | What it did |
|---|---|---|
| `c9d485c` | audit/e2e-j5 | J5 gap closure: 47 `unverified` rows to E2E, 99 rows each with one gap reason, F-J5-001 to 007 (source `e953411`) |
| `04dda5b` | fix/audit-batch-4 | Batch 4: whole-pixel sizes, non-colour selection cues, Increase Contrast glyphs, fitted destination forms, one capture-shortcut surface removed, Cancel-first destructive sheets, History notices, Resize and Toolbox icons. Branch commits `d9ed8b7`, `6d833a8`, `1d8c3d3`, `e3f99b8`, `12b75e6`; evidence `495ff6b` |
| `877a5c6` | audit/panel-probe | Launcher panel-service watchdog (SIGKILL above 2 GB) and the F-J5-005 investigation |
| `b09ecc6` | fix/review-r1-tools-docs | Review round 1 tools and docs: leaked capture withdrawn, OCR sweep tool, harness input fence, Free-only fonts by default, ledger corrections, neutral role names |
| `fa4715f` | fix/panel-service-runaway | F-J5-005 root cause: the launchers canonicalize their session dir. App code unchanged; the OS bug remains on macOS 27.2 |
| `0bd6f94` | fix/audit-batch-5 | Batch 5: upload honours Original size, Resize opens at the title's size, Toolbox icons drawn, one destinations surface, labelled History actions, footer stops repeating the title. Branch commits `d05cb49`, `f7f68be`; evidence `fe15ddc` |
| `14d4d9f` | audit/e2e-j6 | J6 real-click retest of batches 4 and 5: F-J6-001 to 010, live S3 original-size check, every unverified row carries one gap reason |
| `0b03903` | fix/review-r2-tools-ledger | Review round 2 tools and ledger: session-scoped panel watchdogs (R2-013), retired ledger class (R2-008), text-readout downgrades (R2-007), stale-row flags (R2-009), S42 caption correction (R2-011) |
| `5989fa0` | fix/audit-batch-6 | Batch 6: Resize rewrites the picture under Original size, one size formatter, shortcuts pause only while Settings is key, Toolbox menu button, History at 880, compact format toggle, Hide and Trash Cancel-first. Carries review round 2 R2-001 to 005 and R2-014 to 018 |
| `5b30929` | fix/audit-batch-7 | Batch 7: footer upload error is the whole line, `Upload failed · code` or `Upload failed`, never a cut sentence |
| `5310a2c` | audit/e2e-j7 | J7 real-input validation of batches 6 and 7 and the review round 2 fixes: F-J7-001 to 006, live S3 resized upload 1200 × 844 |
| `87abbfd` | fix/audit-batch-8 | Batch 8: Resize always rewrites the picture, visible shortcut-pause note, stable published size, HTTP status in upload errors, checkbox kept beside an error at 980 |
| `7f0a767` | audit/final-render | Final render pass: display options on current surfaces with positive controls, 48 stale rendered rows refreshed, F-R-001 to 005 |
| `33743c5` | audit/e2e-j8 | J8 real-input validation of batch 8: visible shortcut-pause lifecycle, Resize one rule, stable published size, 980 error keeps the checkbox; F-J8-001 and 002 |

### Journeys

| Journey | Scope | Source revision | Merge | Result |
|---|---|---|---|---|
| J1 editor core | Real clicks and keys: drawing, text, colour, size, shadow, Resize, crop, full screen, Toolbox, Photos, keyboard walk | `15d5ec2` | `10040ba` | 26 findings (F-J1-001 to 026); 87 image files in `e2e-2026-10-10/j1/` (86 captures per the merge message) |
| J2 History, Settings, Destinations, upload | Real clicks: History actions and sheets, Settings tabs, Destinations forms, About, and one live S3 synthetic upload | `10040ba` | `2cc07da` | 24 findings (F-J2-001 to 024); 78 captures in `e2e-2026-10-10/j2/` |
| J3 rendered matrix | **Rendered only, not E2E.** Light and dark, five sizes, Reduce Transparency, Increase Contrast, Differentiate Without Color, Reduce Motion and combinations, with positive controls | `3194247` | `baea204` | 11 findings (F-J3-001 to 011); 111 captures packed in `e2e-2026-10-10/j3/` from 3,338 PNGs over 18 runs |
| J4 real-click retest | Real-click retest of the 47 fixes from batches 1 to 3c, plus the live S3 delete through the app | `94b7aa5` | `284f028` | 37 pass, 8 partial, 2 unverified of 47 (the table after the ledger correction; the original summary said 38 and 7); 7 new P3 findings (F-J4-001 to 007); 76 captures in `e2e-2026-10-10/j4/`, AWS log in `e2e/j4-aws-log.md` |
| J5 gap closure | Real input for every `unverified` row that could be reached; one gap reason for each row that could not; the F-J5-005 panel-service investigation | `e953411` | `c9d485c` | 7 findings (F-J5-001 to 007); 47 rows to E2E; 48 jpg plus one AX and state readout file in `e2e-2026-10-10/j5/` |
| J6 real-click retest | Real clicks on batches 4 and 5, four isolated sessions, computer-use driver only | `0bd6f94` | `14d4d9f` | 10 findings (F-J6-001 to 010); 64 captures in `e2e-2026-10-10/j6/`; AWS log `e2e/j6-aws-log.md`; 0 panel-service kills, stores unchanged |
| J7 real-input validation | Batches 6 and 7 and the review round 2 fixes, two isolated sessions | `5b30929` | `5310a2c` | 6 findings (F-J7-001 to 006); 34 captures in `e2e-2026-10-10/j7/`; live S3 resized upload 1200 × 844; `e2e/j7-aws-log.md` |
| J8 real-input validation | Batch 8, one isolated session | `87abbfd` | `33743c5` | 2 findings (F-J8-001 and 002); 19 captures in `e2e-2026-10-10/j8/`; live S3 upload and delete; `e2e/j8-aws-log.md` |
| Final render pass | Harness renders (not real input) of display options on current surfaces, with positive controls | `5b30929` | `7f0a767` | 5 findings (F-R-001 to 005); 122 captures in `impl-2026-10-09/final-render/` |

Notes on counts that the sources disagree on:

- The J3 findings text calls its packed set "106-capture" in one place; the folder and the checker both count 111, and 111 is used here. The J1 merge message says 86 captures, while the folder holds 87 image files.
- The J4 summary (38 pass, 7 partial) predates the ledger correction that made F-J1-019 partial. The table gives 37 pass and 8 partial.
- F-J2-006 is PASS in the J4 table, but the ledger says it is an absence of the symptom, not a verified fix. The counts below keep it as a pass.

### Fix batches

| Batch | Branch | Merge | Evidence (captures) |
|---|---|---|---|
| 1 | `fix/audit-batch-1` | `529af8b` | `impl-2026-10-09/audit-fix-1/` (74, `8e7a37d`) |
| 2 | `fix/audit-batch-2` | `ad69580` | `impl-2026-10-09/audit-fix-2/` (38, `2275c5b`) |
| 3a | `fix/audit-batch-3a` | `ced431b` | `impl-2026-10-09/audit-fix-3a/` (24, `cc05825`) |
| 3b | `fix/audit-batch-3b` | `3194247` | `impl-2026-10-09/audit-fix-3b/` (184, `526ab3c` and `41b2507`); before twins in `audit-fix-3b-before/` (62, `2cc07da`) |
| 3c | `fix/audit-batch-3c` | `94b7aa5` | `impl-2026-10-09/audit-fix-3c/` (52, `0edc3ce` and `6469efb`) |
| 4 | `fix/audit-batch-4` | `04dda5b` | `impl-2026-10-09/audit-fix-4/` (147 captures at `1026e58`: dwc 16, ic 12, plain 119). Rendered only, icon mode `sf` (Font Awesome unavailable in that run). No real-click retest yet |
| 5 | `fix/audit-batch-5` | `0bd6f94` | `impl-2026-10-09/audit-fix-5/` (249, `f7f68be`) |
| 6 | `fix/audit-batch-6` | `5989fa0` | `impl-2026-10-09/audit-fix-6/` (78, `cc764dc`) |
| 7 | `fix/audit-batch-7` | `5b30929` | no folder of its own; checked in `e2e-2026-10-10/j7/` (34) and in the final render (`5b30929`) |
| 8 | `fix/audit-batch-8` | `87abbfd` | `impl-2026-10-09/audit-fix-8/` (24, `ee89d7b`); checked in `e2e-2026-10-10/j8/` (19) |
| 9 | not merged; branch not recorded in the sources | in progress | F-R-001 to 005, see the resolution index |

### Finding dispositions

Snapshot as at the J4 retest, kept for history; the resolution index below is current. Derived from the J4 retest table in `e2e/findings.md` (after the ledger correction), the J5 section, the F-J5-005 investigation, and the batch 4 commit subjects and evidence. Batch 4 has no verdict in `findings.md`, so its fixes are mapped from commit subjects and the evidence folder. They were checked rendered only, and the table keeps them apart from real-click passes.

| Journey | Findings | Real-click pass (J4) | Batch 4, rendered, not retested | Fixed, other | Partial | Gap | Deferred | Doc-only | Open |
|---|---|---|---|---|---|---|---|---|---|
| J1 | 26 | 21 | 1 (F-J1-009) | 0 | 2 (016, 019) | 1 (012) | 1 (023) | 0 | 0 |
| J2 | 24 | 16 | 0 | 0 | 5 (009, 014, 015, 020, 022) | 2 (011, 017) | 0 | 1 (024) | 0 |
| J3 | 11 | 0 | 7 (001 to 007) | 0 | 1 (011) | 2 (008, 010, OS-owned) | 0 | 0 | 1 (009) |
| J4 | 7 | 0 | 4 (001, 003, 004, 005) | 0 | 0 | 0 | 0 | 0 | 3 (002, 006, 007) |
| J5 | 7 | 0 | 0 | 1 (005, `fa4715f`) | 0 | 0 | 0 | 0 | 6 (001 to 004, 006, 007) |
| **Total** | **75** | **37** | **12** | **1** | **8** | **5** | **1** | **1** | **10** |

Totals check: 37 + 12 + 1 + 8 + 5 + 1 + 1 + 10 = 75.

Notes on the table:

- **F-J3-011 is partial, not fixed.** `1d8c3d3` changed the glyph to Font Awesome Free's resize arrows, but the batch 4 captures are in icon mode `sf`, so the new glyph is not in the evidence. It needs an FA-mode capture.
- **F-J1-009 (Toolbox icons)** is in the batch 4 count, but the same `sf` caveat applies to its icons.
- **Batch 4 mapping** is from commit subjects and the `audit-fix-4` folder. F-J3-002, 003, 006 and 007 and F-J4-001, 003, 004 and 005 are inferred this way; none has a real-click check.

### Finding resolution index

Every finding ID from J1 to J8 (93), every review round 1 ID R1-001 to R1-024 (24), every review round 2 ID R2-001 to R2-018 (18) and every final render ID F-R-001 to F-R-005 (5): 140 in all. Status key: **fixed** (merge or batch named, and not contradicted by a later real-input result); **partial** (part of the item passed under real input, or the fix holds only in the rendered harness); **deferred**; **gap** (outside what the harness or the isolated session can prove); **doc-only**; **open** (no fix recorded in the sources; listed, not scheduled); **in progress** (batch 9, F-R-001 to 005); **accepted trade-off** (recorded as acceptable by the journey that found it). R1 rows take their titles from the round 1 record in `docs/design/e2e/findings.md`.

#### Journey findings (F-J1 to F-J5)

| ID | Status | Batch or merge | Note |
|---|---|---|---|
| F-J1-001 | fixed | batches 1 to 3c; J4 pass | Eraser no longer carries the shadow (cut fragments lose theirs, see F-J4-007) |
| F-J1-002 | fixed | batches 1 to 3c; J4 pass | Swatches match the applied colour; the chosen one shows its check |
| F-J1-003 | fixed | batches 1 to 3c; J4 pass (P1) | Custom color… opens on the current colour |
| F-J1-004 | fixed | batches 1 to 3c; J4 pass | Resize Return validates, and applies on OK |
| F-J1-005 | fixed | batches 1 to 3c; J4 pass (P1) | Text Size grows glyphs and frame together |
| F-J1-006 | fixed | batches 1 to 3c; J4 pass (P1) | Shadow toggle restyles only the shadow |
| F-J1-007 | fixed | batches 1 to 3c; J4 pass (P1) | Tab walk leaves the canvas (keyboard evidence for OSN-060) |
| F-J1-008 | fixed | batches 1 to 3c; J4 pass | Full screen enters and leaves from the Window menu |
| F-J1-009 | fixed | batch 4 `1d8c3d3`; J7 item 4 pass | Toolbox rows draw their icons; every row has one in the J7 real-click pass (R1-005 closed) |
| F-J1-010 | fixed | batches 1 to 3c; J4 pass | Status names the format and stays current |
| F-J1-011 | fixed | batches 1 to 3c; J4 pass | Crop hint names Return and Escape |
| F-J1-012 | gap | none | Drag well Export panel never retested; the panel is OS-owned (see gaps) |
| F-J1-013 | fixed | batches 1 to 3c; J4 pass | Photos empty state fits the grid (the populated browser is a gap) |
| F-J1-014 | fixed | batches 1 to 3c; J4 pass | Resize: mode and dimensions first, presets below |
| F-J1-015 | fixed | batches 1 to 3c; J4 pass | Pasted copy offset from the original |
| F-J1-016 | partial | batches 1 to 3c; J4 partial | Handles still large on an 85 px selection at 25% |
| F-J1-017 | fixed | batches 1 to 3c; J4 pass | Arrange is a submenu (AX read only) |
| F-J1-018 | fixed | batches 1 to 3c; J4 pass | Full-screen chrome capped and grouped |
| F-J1-019 | partial | batches 1 to 3c; J4 partial (ledger) | No capture yet shows a popover dismissing |
| F-J1-020 | fixed | batches 1 to 3c; J4 pass | Undo disabled on a blank canvas |
| F-J1-021 | fixed | batches 1 to 3c; J4 pass | Save is the box-archive glyph |
| F-J1-022 | fixed | batches 1 to 3c; J4 pass | ⌘M hides the window; no capture of the hidden state |
| F-J1-023 | deferred | none | Text editor exposes no AX selection |
| F-J1-024 | fixed | batches 1 to 3c; J4 pass | Option-Return finishes text entry |
| F-J1-025 | fixed | batches 1 to 3c; J4 pass | Add Shadow disabled without a snap |
| F-J1-026 | fixed | batches 1 to 3c; J4 pass | Flip mirrors shapes and keeps text readable |
| F-J2-001 | fixed | batches 1 to 3c; J4 pass (P1) | Sheets attach to the History window; Escape cancels |
| F-J2-002 | fixed | batches 1 to 3c; J4 pass (P1) | App deleted its own S3 object (head-object 404); CDN lag is F-J4-003 |
| F-J2-003 | fixed | batches 1 to 3c; J4 pass (P1) | Open with unsaved changes asks first; Cancel keeps everything |
| F-J2-004 | fixed | batches 1 to 3c; J4 pass | "Link copied" and "Image copied" confirmations |
| F-J2-005 | fixed | batches 1 to 3c; J4 pass | Opened entry reads Saved |
| F-J2-006 | fixed | batches 1 to 3c; J4 pass | Canvas stays bright. Not reproduced: an absence of the symptom, not a verified fix |
| F-J2-007 | fixed | batches 1 to 3c; J4 pass | Tab names match the tiles |
| F-J2-008 | fixed | batches 1 to 3c; J4 pass | Empty states: Clear filters and "0 of 5 items" |
| F-J2-009 | partial | batches 1 to 3c; J4 partial | Right column holds a summary; the 880 × 600 reflow needs a resize tool |
| F-J2-010 | fixed | batches 1 to 3c; J4 pass | Destination middle-truncated (Date still tail-cut, see F-J4-002) |
| F-J2-011 | gap | none | ⌘1 to ⌘4 map to menu items; ⌘2 would start a real capture of the owner's display |
| F-J2-012 | fixed | batches 1 to 3c; J4 pass | Each Settings tab fits its own form |
| F-J2-013 | fixed | batches 1 to 3c; J4 pass | Destinations sheet sits inside Settings |
| F-J2-014 | partial | batches 1 to 3c; J4 partial | FTP and FTPS forms not opened |
| F-J2-015 | partial | batches 1 to 3c; J4 partial | Per-protocol copy checked for WebDAV and SFTP only |
| F-J2-016 | fixed | batches 1 to 3c; J4 pass | S3 placeholders, no "optional" |
| F-J2-017 | gap | none | AX tool cannot show whether a field has a name |
| F-J2-018 | fixed | batches 1 to 3c; J4 pass | Error band sits above the buttons |
| F-J2-019 | fixed | batches 1 to 3c; J4 pass | Remove is red; Cancel is the default |
| F-J2-020 | partial | batches 1 to 3c; J4 partial; batch 4 `d9ed8b7` removed one of two shortcut surfaces | Disable All clears the error; the 69-item key menu remains |
| F-J2-021 | fixed | batches 1 to 3c; J4 pass | Inline "Error: Upload failed"; details keep the code |
| F-J2-022 | partial | batches 1 to 3c; J4 partial | Success line seen; the 12 s hold, cancel notice and Retrying label not timed |
| F-J2-023 | fixed | batches 1 to 3c; J4 pass | About reflows; Escape closes it |
| F-J2-024 | doc-only | none | Move to Trash escapes the isolated home (two files reached the owner's real Trash). Launcher notes say so; the app is unchanged |
| F-J3-001 | fixed | batch 4 `6d833a8`; rendered | Differentiate Without Color outlines the selected PNG/JPG |
| F-J3-002 | fixed | batch 4; rendered (inferred) | Blank column in History's empty and no-match states (evidence "History empty" in `495ff6b`) |
| F-J3-003 | fixed | batch 4 `d9ed8b7`; rendered (inferred) | Destination forms fit their protocol, not the S3 height |
| F-J3-004 | partial | batch 4 `6d833a8`; rendered | Borders and the Snap outline strengthen under Increase Contrast; glyph and disabled contrast do not (F-R-002, batch 9) |
| F-J3-005 | partial | batch 4 `1d8c3d3`; J6 partial | Zoom and Original size explain what they measure (text readout); the tooltips were not captured |
| F-J3-006 | fixed | batch 4 `d9ed8b7`; J7 item 2a pass | Whole-pixel sizes; the Resize result that broke them is fixed (F-J6-001) |
| F-J3-007 | fixed | batch 4 `1d8c3d3`; batch 7 `5b30929`; J7 item 6 pass | Status keeps the tool or size longest; the 980 status reads whole (F-J6-004) |
| F-J3-008 | gap | OS-owned | Window title text is system-drawn |
| F-J3-009 | open | none | Small and empty documents use 4 to 41% of a large window; no batch 4 subject covers it |
| F-J3-010 | gap | OS-owned | Unselected radios and checkboxes are system-drawn |
| F-J3-011 | fixed | batch 4 `1d8c3d3`; batch 5 (R1-006 text button); J6 pass | The Font Awesome arrows gave way to the Resize… text button; J6 found the glyph gone |
| F-J4-001 | fixed | batch 4 `12b75e6`; rendered (inferred) | Destination errors stay on the page they were raised on; the list shows none |
| F-J4-002 | fixed | J6 pass (`14d4d9f`) | History Date fits at two-digit days: `Oct 10, 2026 at 10:12 AM` |
| F-J4-003 | fixed | batch 4 `d9ed8b7`; rendered (inferred) | History footer notice after Delete from Web. The CDN cache is outside the app |
| F-J4-004 | fixed | batch 4 `e3f99b8`; rendered (inferred) | History keeps the published size for Shared entries |
| F-J4-005 | fixed | batch 4 `d9ed8b7`; rendered (inferred) | Destructive sheets are Cancel-first, including Delete from Web |
| F-J4-006 | open | none | Previous document's size shown briefly after History › Open |
| F-J4-007 | open | none | Erased fragments lose their shadow; a design question, may be intended |
| F-J5-001 | fixed | J6 pass | An invalid delay keeps the sheet with the error line |
| F-J5-002 | fixed | J6 pass (caveat) | ⌘D answers the History sheet once History is key; may be the harness |
| F-J5-003 | fixed | J6 pass; status whole after batch 7 | Save to History on a blank canvas says Nothing to save; no entry is added |
| F-J5-004 | fixed | J6 pass | Opens Settings › Upload with No destinations yet and Add… |
| F-J5-005 | fixed | `877a5c6` watchdog; `fa4715f` root cause | Launchers canonicalize the session dir. App code unchanged; the OS bug remains on 27.2 (see the panel investigation) |
| F-J5-006 | fixed | J6 pass (source) | Dead circle-exclamation icon removed (`FAIcon.warning` is gone) |
| F-J5-007 | fixed | batch 5 `f7f68be` | Inventory names regenerated from a fresh harness run, matching the build |

#### Journey findings (F-J6)

Real-click retest of batches 4 and 5 (`14d4d9f`). Batch column names the fix where the sources name it.

| ID | Priority | Title | Status | Batch or merge | Note |
|---|---|---|---|---|---|
| F-J6-001 | P2 | Applying a Resize never changes the title or exported size | fixed | batch 6 `5989fa0` (R2-002) | J7 2a and J8 2a pass: title and upload both 1200 × 844 |
| F-J6-002 | P3 | Edit › Copy Image ignores Original size | partial | none named | J7 read a 1200 × 844 TIFF after a Resize (readout only); the copy of an unresized Original-size picture was not re-run |
| F-J6-003 | P3 | History's Delete from Web state not recomputed when a destination changes | fixed | not named in a merge | J7 item 7 pass: disabled at once after the prefix change, enabled at once after restore |
| F-J6-004 | P3 | At 980 the plain status messages are tail-cut | fixed | batch 7 `5b30929` | J7 item 6 pass: `Unsaved changes` and `Upload failed (curl 22).` read whole |
| F-J6-005 | P4 | The title lags a moment behind the Original size checkbox | fixed | batch 6 | J7 2b pass: title fitted at once, no lag |
| F-J6-006 | P4 | The History window stops at 945 wide, not at its 880 minimum | fixed | batch 6 (R2-005) | J7 item 5 pass: 880 × 720 reached |
| F-J6-007 | P4 | Resize's Apply is a preview that Cancel undoes | fixed | batch 6 `29481af` (Apply commits) | J7 2d pass: Cancel keeps the size. The button is still labelled Apply; the suggested rename was not made |
| F-J6-008 | P4 | The Hide and Trash sheets disagree on button order and default | fixed | batch 6 `9fda9c7` (Cancel first) | Not re-checked in J7 or J8 |
| F-J6-009 | P4 | Toolbox: two rows without an icon, AX value Select All | fixed | batch 6 (R2-004) | J7 item 4 pass: every row has an icon; AXMenuButton with no value |
| F-J6-010 | P4 | Size formats differ between the title and History Details | fixed | batch 6 (one size formatter) | Per the merge message; not re-read in J7 or J8 |

#### Review round 1 (R1-001 to R1-024)

| ID | Title | Status | Batch or merge | Note |
|---|---|---|---|---|
| R1-001 | Private text visible in a harness capture | fixed | `b09ecc6` | Harness input fence; leaked capture withdrawn from the tree. History cleanup pending, owned by root before any push |
| R1-002 | Upload size versus "Original size" promise | fixed | batch 5 `0bd6f94` | J6 pass (P1): ticked, the object is 2560 × 1800; unticked, 674 × 474 |
| R1-003 | Resize sheet opens in output points | fixed | batch 5 (opens); batch 6 `5989fa0` (apply) | J6 found Apply never reached the title or the upload (F-J6-001); J7 item 2a pass |
| R1-004 | Font Awesome Pro bundled in default builds | fixed | `b09ecc6` | Free-only fonts by default; the default build never bundles Font Awesome Pro |
| R1-005 | Toolbox pull-down icons unverified; near-identical symbols | fixed | batch 4 `1d8c3d3`; batch 6 (R2-004) | Reopened by review round 2; J6 partial; J7 item 4 pass: every row has an icon |
| R1-006 | Resize glyph reads as expand | fixed | batch 5 | J6 pass: text button at 980 and 1482 wide, disabled in Actual Size |
| R1-007 | Ledger rows describe removed sheet and old tab names | fixed | `b09ecc6` | — |
| R1-008 | Ledger class inflation | fixed | `b09ecc6` | — |
| R1-009 | No real-click retest of batch 4 | fixed | J6 retest `14d4d9f` | Retest done in real clicks for batches 4 and 5; results in the F-J6 rows |
| R1-010 | Delete from Web after re-save | fixed | not named in a merge (F-J6-003) | J6 partial; J7 item 7 pass: Delete from Web follows the destination at once |
| R1-011 | Settings › Upload duplicates Destinations sheet | fixed | batch 5 | J6 pass: one destinations list, Make Default, form-only editor sheet |
| R1-012 | History toolbar unlabeled glyphs | fixed | batch 5 (labels); batch 6 (880) | J6 partial (880 unreachable); J7 item 5 pass at 880 × 720 |
| R1-013 | Status line repeats the title | fixed | batch 5 | J6 pass: windowed footer has no size; full screen shows it once |
| R1-014 | Status line truncates the upload link at 980 | fixed | batch 7 `5b30929` | J7 item 6 pass: the 980 status and upload error read whole |
| R1-015 | Empty states and copy consistency | fixed | batch 5 | J6 pass: empty-state wording |
| R1-016 | Actual Size navigator mostly empty | deferred | none | — |
| R1-017 | Settings › Capture redundant controls | fixed | batch 5; pause fix in batch 6 (R2-001) | J6 pass (cleanup); J8 items 1a to 1e pass on the visible pause note |
| R1-018 | Differentiate Without Color outline not live | partial | batch 5 | Rendered positive control shows the tab outline under the option; the live toggle is a system option, not real input |
| R1-019 | Weak test assertions | fixed | batch 5 `f7f68be` | History and upload tests prove published size and success status |
| R1-020 | Window › Full Screen acts on the wrong window | partial | batch 5 | J6: Full Screen acted on the aimed editor; the refusal with another window key was not shown |
| R1-021 | Eraser drops the shadow from the whole shape | open | none (stretch goal, not in the batch 5 merge) | J6 inconclusive: the harness drag trail covers the stroke |
| R1-022 | Miscellaneous WebDAV, notice and shortcut defects | fixed | not named in a merge | WebDAV note: J7 partial, J8 item 5 pass. The shortcut part is R2-001 |
| R1-023 | Model and tool names in committed docs and tooling | fixed | `b09ecc6` | — |
| R1-024 | F-J5-005 judgement | fixed | `fa4715f` | Panel-service root cause in the launchers; the OS bug remains |

#### Independent review round 2 (R2-001 to R2-018)

| ID | Priority | Title | Status | Batch or merge | Note |
|---|---|---|---|---|---|
| R2-001 | P2 | Shortcut pause holds while Settings is only shown on the Capture tab | partial | batch 6 `5989fa0` | J8 items 1a to 1e pass on the visible note. Firing a shortcut and the app-deactivation path stay unverified (unsafe) |
| R2-002 | P2 | Resize result overwritten by refits; Original size ignores it | fixed | batch 6 `5989fa0` | J7 2a and 2b, J8 2a and 2b pass |
| R2-003 | P3 | Original size checkbox stays with no snap picture | partial | batch 6 (proof test `7882bb0`) | J7: blank canvas pass; after Remove Snap Picture not isolated (the 980 error hid it, fixed in batch 8) |
| R2-004 | P3 | Toolbox menu covers its own button; pop-up role with a value | fixed | batch 6 | J7 item 4 pass |
| R2-005 | P3 | History action labels chosen only after resize; 880 unreachable | fixed | batch 6 | J7 item 5 pass |
| R2-006 | P3 | Evidence text names the computer-use tool | fixed | review round 2 lane `0b03903` | Wording corrected in the evidence file |
| R2-007 | P3 | Ledger rows overclaim E2E (SET-023, KEY-021, MENU-061) | fixed | review round 2 lane `0b03903` | Moved to unverified with `gap: text readout only` |
| R2-008 | P3 | Retired rows still counted as rendered or E2E | fixed | review round 2 lane `0b03903` | New `retired` class, 27 rows |
| R2-009 | P3 | Rendered rows drawn before batches 4 and 5 describe old chrome | fixed | final render pass `7f0a767` | 48 rows refreshed from `5b30929`, flag dropped |
| R2-010 | P3 | Display options not re-rendered after batch 6 | fixed | final render pass `7f0a767` | Positive controls on the current surfaces (rendered, not real input) |
| R2-011 | P3 | S42 status-notice capture mistimed; captions wrong | partial | review round 2 lane `0b03903` | Captions corrected. A correct dark notice capture is still missing (F-R-001, batch 9) |
| R2-012 | P3 | Harness input fence: no event counts, no hover fence | partial | batch 6 `29481af` (record) | The swallowed count is recorded; no split by event kind (F-R-005, batch 9) |
| R2-013 | P3 | Panel watchdogs killed other apps' services; cleanup touched the real Preferences | fixed | review round 2 lane `0b03903` | Watchdogs consider only the session environment; the real-home cleanup is gone |
| R2-014 | P3 | Bottom bar at 980: status squeezed by the format toggle and zoom | fixed | batches 6 and 7 | J7 item 6 pass (one exception, F-J7-002) |
| R2-015 | P3 | History tiles, Drag as width and "Destination: —" | fixed | batch 6 `90b8be6` | J7 item 8a pass |
| R2-016 | P3 | Settings › Upload: wide label column, empty-state hint, shared yellow | partial | batch 6 `90b8be6` | J7 item 8b pass; the empty-list hint was not run (needs an empty list) |
| R2-017 | P3 | Empty Endpoint gives an unnamed three-line URL rule | fixed | batch 6 `90b8be6` | J7 item 8c pass |
| R2-018 | P3 | WebDAV 2xx Test says the login was accepted | fixed | batch 6 `90b8be6` | J7 item 8d partial (cut); J8 item 5 pass |

#### J7 findings (F-J7-001 to 006)

| ID | Priority | Title | Status | Batch or merge | Note |
|---|---|---|---|---|---|
| F-J7-001 | P3 | The WebDAV 2xx Test note is cut at three lines | fixed | not named in a merge | J8 item 5 pass: three whole lines, closing sentence included |
| F-J7-002 | P4 | The footer error shows curl's exit code, not the HTTP status | partial | batch 8 `87abbfd` (HTTP status) | J8 item 4: footer reads `Failed`; `Upload failed · HTTP 403` is in Details and AX only (F-J8-001) |
| F-J7-003 | P3 | A shared entry's Details Size changes after Delete from Web | fixed | batch 8 `87abbfd` (stable published size) | J8 item 3 pass: `800 × 563 (published)` before and after delete |
| F-J7-004 | P4 | Nothing shows whether global shortcuts are paused | fixed | batch 8 `87abbfd` (visible note) | J8 1a pass; the note and its AX value follow key window |
| F-J7-005 | P4 | Original size behaves differently after ticked and unticked Resize | fixed | batch 8 `87abbfd` (Resize one rule) | J8 2a and 2b pass: the checkbox is hidden after any applied Resize |
| F-J7-006 | P4 | An upload error hides the Original size checkbox at 980 | fixed | batch 8 `87abbfd` | J8 item 4 pass: checkbox kept beside Retry and Details |

#### Final render pass (F-R-001 to 005)

| ID | Priority | Title | Status | Batch or merge | Note |
|---|---|---|---|---|---|
| F-R-001 | P3 | S42 status-notice captures show the stale status | in progress (batch 9) | batch 9 | Notice in 2 of 21 attempts (light only); the layout JSON says Saved to History |
| F-R-002 | P3 | Increase Contrast does not raise glyph or disabled contrast | in progress (batch 9) | batch 9 | Glyph 4.00:1 unchanged; disabled Undo 1.47:1 to 1.57:1 (F-J3-004 still open) |
| F-R-003 | P3 | Differentiate Without Color leaves the Upload list selection colour-only | in progress (batch 9) | batch 9 | Selected row 1.10:1 fill, no cue under the option; the tab does gain one |
| F-R-004 | P3 | Toolbox menu capture fails intermittently and passes silently | in progress (batch 9) | batch 9 | 12 of 30 first-set menu captures dropped; the count of PNGs looked like a pass |
| F-R-005 | P3 | Input-fence count cannot tell a parked pointer from typing | in progress (batch 9) | batch 9 | The fence records no event kinds; menu runs swallow 11 to 70 events |

#### J8 findings (F-J8-001 to 002)

| ID | Priority | Title | Status | Batch or merge | Note |
|---|---|---|---|---|---|
| F-J8-001 | P4 | The 980 footer error line shows only "Failed" | accepted trade-off | batch 8 `87abbfd` | J8: acceptable, the checkbox won. The owner may want `HTTP 403` visible in the footer |
| F-J8-002 | P4 | The pause note cannot be read off the Capture tab | accepted trade-off | none | J8: not worth shipping on its own; an AX value on the tab group would serve testing |

#### Totals by status

| Status | F-J1 to F-J8 (93) | R1 (24) | R2 (18) | F-R (5) | All (140) |
|---|---|---|---|---|---|
| fixed | 70 | 20 | 13 | 0 | 103 |
| partial | 11 | 2 | 5 | 0 | 18 |
| deferred | 1 | 1 | 0 | 0 | 2 |
| gap | 5 | 0 | 0 | 0 | 5 |
| doc-only | 1 | 0 | 0 | 0 | 1 |
| open | 3 | 1 | 0 | 0 | 4 |
| in progress (batch 9) | 0 | 0 | 0 | 5 | 5 |
| accepted trade-off | 2 | 0 | 0 | 0 | 2 |
| **Total** | **93** | **24** | **18** | **5** | **140** |

Check: 103 + 18 + 2 + 5 + 1 + 4 + 5 + 2 = 140.

### Coverage summary

Source of truth: `e2e/coverage-matrix.md` (one row per audit ID, **597 rows**) and `e2e/inventory.json` (the same 597 entries). Counts below were recounted from the matrix on 2026-10-10 after the final render pass, with the table cells split on unescaped pipes only.

Evidence classes are never merged:

- **`E2E`**: real input (a click or key) in an isolated session copy, with the result seen in a screenshot or an AX read. The image was viewed, not just listed.
- **`rendered`**: the harness renders the state in-process (`tools/eye-dump-audit.sh`). It shows how the state looks, not that a user can reach it. It is not a real-input result.
- **`unit/source`**: a named existing test or source check.
- **`unverified`**: the audit could not exercise the row. Each one carries **exactly one gap reason**, in the observed cell.
- **`retired`**: the app removed or replaced the surface. The row keeps its IDs and history and is counted in no other class.

| Evidence class | Rows in `coverage-matrix.md` |
|---|---|
| `E2E` (real input, viewed) | 312 |
| `rendered` (harness render, not real input) | 45 |
| `unit/source` (named test or check) | 93 |
| `unverified` (one gap reason each) | 120 |
| `retired` (surface removed or replaced) | 27 |
| **Total** | **597** |

How the class moved (rows, 597 throughout): at `14d4d9f` (J6) E2E 322, rendered 64, unit/source 93, unverified 118. After review round 2 (R2-007, R2-008) E2E 309, rendered 48, unverified 120, retired 27. After J7 (three rendered rows, DEST-014, 016 and 022, became E2E) E2E 312, rendered 45. J8 changed no class.

Gap reasons of the 120 `unverified` rows, counted from the observed cell (each row has exactly one):

| Gap reason | Rows | What it covers |
|---|---|---|
| `gap: unsafe` | 36 | captures of the real display, global hotkeys, Hide Others, Move to Trash, Open Link, Cancel Upload, Timed Snapshot with a valid delay, Clear All |
| `gap: harness` | 30 | synthetic right-click menus, held modifiers, file drops and drags to other apps, menu picks while inactive, full-keyboard sweeps, announcements |
| `gap: AX presence only` | 18 | menu items listed in the AX tree, not pressed |
| `gap: OS-owned` | 18 | Open, Save, Export and Print panels, the Export accessory, share picker, Photos and Pictures choosers, Spelling and Colors panels |
| `gap: text readout only` | 7 | Edit › Copy Image pasteboard read, tooltips not captured, the No destination readout, icon-only AX names, the Settings-open readouts moved here in round 2 |
| `gap: hardware` | 5 | multi-display, 1x display, printer |
| `gap: permission` | 4 | Screen Recording captures, Photos Library |
| `gap: AX value only` | 2 | zoom entries 75% and 100% |
| **Total** | **120** | |

Matrix housekeeping, which this lane does not edit (`e2e/` is the e2e lane's):

- The row's separate **gap column** does not match the observed cell in some rows: 72 are blank, 32 read `e2e-partial:` (the reason is in the observed cell), and 16 give a second label (for example MENU-016 reads `AX presence only` in the observed cell and `printer` in the gap column). The observed cell is what the counts above use.
- Three rows contain an escaped pipe in a cell. Column-splitting without escape handling miscounts them; the counts above split on unescaped pipes only.
- The earlier prose counts (590 rows, 303 / 71 / 91 / 125; 597 rows at J6 with 322 / 64 / 93 / 118) are superseded by the counts above.

### Evidence index

Paths are under `docs/design/evidence/` unless stated. Counts are image files (`find`). Where an earlier note gives a different capture count, the earlier note is in brackets. Each folder with a `captures.md` or `manifest.json` lists every capture and its source SHA.

| Folder | Images | What it holds |
|---|---|---|
| `e2e-2026-10-10/j1/` | 87 | J1 real-click captures (editor core), source `15d5ec2`. Also `menus-ax-dump.txt` |
| `e2e-2026-10-10/j2/` | 78 | J2 real-click captures (History, Settings, Destinations, About, one live S3 upload), source `10040ba` |
| `e2e-2026-10-10/j3/` | 111 | J3 **rendered** matrix, `captures.md`, `manifest.json`, `layout/`, `safety.txt`, source `3194247`. Not real-click |
| `e2e-2026-10-10/j3-diffs/` | 8 | Side-by-side composites that prove the J3 display-option positive controls. Rendered only |
| `e2e-2026-10-10/j4/` | 76 | J4 real-click retest captures (the 47 fixes plus the live S3 delete), source `94b7aa5`. The AWS log is `e2e/j4-aws-log.md` |
| `e2e-2026-10-10/j5/` | 48 | J5 real-click gap closure captures, build `e953411`, plus `44-ax-and-state-readouts-j5.txt` |
| `e2e-2026-10-10/j6/` | 64 | J6 real-click retest of batches 4 and 5, four isolated sessions, build `0bd6f94`. AWS steps in `e2e/j6-aws-log.md` |
| `e2e-2026-10-10/j7/` | 34 | J7 real-input validation of batches 6 and 7 and the review round 2 fixes, build `5b30929`. AWS steps in `e2e/j7-aws-log.md` |
| `e2e-2026-10-10/j8/` | 19 | J8 real-input validation of batch 8, build `87abbfd`. AWS steps in `e2e/j8-aws-log.md` |
| `e2e-2026-10-10/panelfix/` | 4 | Panel-service check after the F-J5-005 fix: ⌘E, ⌘S and ⇧⌘S panels, and the state after Cancel, with `00-cmd-o-panel-service.txt`. The ⌘O screenshot shows the owner's Documents folder and is deliberately not stored |
| `impl-2026-10-09/audit-fix-1/` | 74 | Batch 1 visual acceptance, `8e7a37d` |
| `impl-2026-10-09/audit-fix-2/` | 38 | Batch 2 visual acceptance, `2275c5b` |
| `impl-2026-10-09/audit-fix-3a/` | 25 | Batch 3a visual acceptance, `cc05825` [24 captures in the earlier note] |
| `impl-2026-10-09/audit-fix-3b/` | 184 | Batch 3b visual acceptance, `526ab3c` (Settings re-captured at `41b2507`) |
| `impl-2026-10-09/audit-fix-3b-before/` | 62 | Batch 3b before-state twins, `2cc07da`, dark |
| `impl-2026-10-09/audit-fix-3c/` | 52 | Batch 3c visual acceptance, `0edc3ce` and `6469efb` |
| `impl-2026-10-09/audit-fix-5/` | 249 | Batch 5 visual acceptance at `f7f68be`, rendered, icon mode `sf`: Toolbox icons, labelled History at 880 and wide, Settings › Upload, editor sheet on Settings. Has `captures.md`, `manifest.json`, `safety.txt`, `layout/` |
| `impl-2026-10-09/audit-fix-6/` | 78 | Batch 6 visual acceptance at `cc764dc`, rendered, icon mode `sf`: Original size and Resize, footer at 980 states (S44), compact format toggle, Toolbox below its button, Hide and Trash Cancel-first, History at 880 |
| `impl-2026-10-09/audit-fix-8/` | 24 | Batch 8 visual acceptance at `ee89d7b`, rendered, icon mode `sf`: the J7 findings (pause note, Resize one rule, published size, footer error with the checkbox kept) |
| `impl-2026-10-09/final-render/` | 122 | Final render pass at `5b30929`, rendered only: display options on the current surfaces with positive controls, 48 stale rows refreshed; `captures.md`, `manifest.json`, `safety.txt`, `layout/` |
| `impl-2026-10-09/audit-fix-4/` | 147 | Batch 4 visual acceptance at `1026e58`, rendered, icon mode `sf`: `dwc/` 16, `ic/` 12, `plain/` 119; each with `captures.md` and `layout/` |
| `impl-2026-10-09/m1-rail/` | 80 | Rail removal, 80 captures at `fef46c7` |
| `impl-2026-10-09/m4-glass/` | 98 | Glass plates, 98 captures at `da2738d` |
| `impl-2026-10-09/m4-states/` | 230 | OSN-044 and OSN-061 part 2 states, source `cc97054` [158 captures in the earlier note] |
| `impl-2026-10-09/m4-window/` | 50 | OSN-043 and OSN-041 step 5 window chrome, `7bf20f8` |
| `impl-2026-10-09/m5-capture/` | 38 | OSN-050 capture states, `8a0e8d9` |
| `impl-2026-10-09/m5-settings/` | 36 | OSN-051 Settings, `a48d0df` |
| `impl-2026-10-09/m5-upload/` | 30 | OSN-054 upload states in the status slot, `fc61ac7` |

Also outside `evidence/`: `e2e/panel-probe/` holds `probe.swift` (the throwaway panel probe) and `trials/` (`sampler.py`, two sample logs for the live ⌘O trials, `watchdog.log`).

The rendered folders (`j3`, `j3-diffs`, `audit-fix-*`, `final-render`, `m*`) are harness renders. Do not read them as real-click proof. The `panelfix` and `j1`, `j2`, `j4`, `j5`, `j6`, `j7` and `j8` folders are the real-click evidence. `panelfix/` was already listed above and is unchanged.

### E2E audit gaps (not proven by this audit)

These are outside what the harness or the isolated session could prove. They are listed, not waived.

1. **VoiceOver speech.** The AX dumps and the G10 walker are structural checks.
2. **Live Screen Recording capture of the real display.** Not run; it needs the owner's display.
3. **Global capture shortcuts actually firing.** Unsafe on the real display. The pause lifecycle is verified through the visible note (J8 1a to 1e), not through a fired shortcut.
4. **The app deactivation path of the pause.** Not run: deactivating the app brings another app forward, which could be the owner's.
5. **1x and multi-display.** The only display was 2x Retina.
6. **Photos library.** The Photos sheet was opened in its empty state only; the populated browser reads the real library.
7. **Printer.** Nothing was printed.
8. **OS-owned panels' internals:** Open, Save, Export, Print, Share and Colors. The panels are OS-owned; the app-owned parts are driven and checked.
9. **Native tooltips.**
10. **Synthetic right-click context menus.** Not reachable by the synthetic click.
11. **Held-modifier gestures**, such as a drag made while holding Shift or Option.
12. **Drag out of the app.** The driver cannot drag to another app.
13. **⌘1 to ⌘4 with the real keyboard in Settings** (F-J2-011). The harness maps the chords to menu items, and ⌘2 would start a real full-screen capture of the owner's display.
14. **Window title text and system radios and checkboxes.** OS-owned (F-J3-008, F-J3-010).
15. **Font Awesome Pro is not bundled by default** (R1-004). No capture exercises Pro icons; the evidence is icon mode `sf`.
16. **The macOS 27.2 panel-service bug** (F-J5-005) is an OS bug. It is mitigated by the launchers canonicalizing the session path (`fa4715f`); real users are not affected.
17. **The manual VoiceOver pass for OSN-062** is not recorded. OSN-062 stays in progress.
18. **History cleanup of a withdrawn capture.** The leaked capture (R1-001) is out of the tree but still in history, owned by root. The cleanup must happen before any push.

Also still open from earlier passes:

- FTP and FTPS destination forms were not opened (F-J2-014); WebDAV and SFTP copy was checked (F-J2-015).
- Timed UI states: the 12 s success-line hold, the Retrying label and the Upload cancelled notice (F-J2-022). Needs a slow network.
- Field names in the destination forms (F-J2-017): the AX tool cannot show whether an explicit label exists.
- Font Awesome Free glyphs: every batch 4 and later capture is icon mode `sf`, so the Toolbox icons have no FA-mode capture (F-J1-009).

### Panel-service investigation (F-J5-005)

- **Symptom (J5).** ⌘E, ⌘O and ⌘S opened panels that the harness could not see, and the app's AX tree collapsed to one element. A peer's ops log reported the panel service at about 66 GB, twice. The ops watchdog killed the two processes.
- **Probe, not reproduced.** 39 bounded trials of a throwaway probe app, in the launcher's environment and in normal conditions, with OpenSnap's panel configurations, stayed at 85 to 116 MB and never triggered the watchdog.
- **Real app, reproduced.** Two trials of one ⌘O in the real isolated copy, with a 2 GB watchdog: the service grew at about 1.1 to 1.2 GB per second and was killed at about 2.5 GB (`877a5c6`).
- **Root cause (`fa4715f`).** The app's `CFFIXED_USER_HOME` carried a `//`, because the launchers built the session dir from `$TMPDIR`, which ends in `/`. On macOS 27.2 the panel service walks the parent directories of that path forever. The app is not at fault: a plain `NSOpenPanel()` in the probe reproduces it, and the 21-row trial table in the investigation isolates it to the `//` in the path.
- **Fix.** `tools/e2e-session.sh` and `tools/eye-dump-audit.sh` canonicalize the session dir right after `mktemp` (`TMP=$(CDPATH= cd -- "$TMP" && pwd -P)`). No change to the app. `tools/test-e2e-session-guard.py` and `tools/test-eye-dump-audit-guard.py` run with a trailing-slash `TMPDIR` and assert the normalized home, with can-fail mutants.
- **Verified.** The panel service peaks at 77 to 94 MB for Open, Save and Export in the app, and for ⌘O, ⌘E, ⌘S and ⇧⌘S under the driver. CPU drops to 0% once drawn, and the watchdog kills in those sessions number 0. The service idles at 80 to 90 MB until the app quits. The earlier "gone within a second" was measured after the probe exited, so it does not apply to the app.
- **Still open.** The OS bug on macOS 27.2 (26B5101f) is unfixed. `tools/panel-service-check.sh` is a manual check: a normal run expects a peak under 300 MB, and `--reproduce` passes a `//` home and shows the bug (peak 2.1 GB, watchdog kill). It is not in `tools/test.py`. `tools/test-app-safety.sh` and `tools/check-clean-clone.sh` build session paths the same way but never open a panel; they were left alone.
- **Matrix.** E2E-KEY-004 to 007 (⌘O, ⌘S, ⇧⌘S, ⌘E) carry E2E evidence from `panelfix/`, not `gap: harness`.

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

- **Batch 9 (in progress):** F-R-001 to 005. F-R-002: Increase Contrast must raise inactive glyph and disabled contrast (F-J3-004 stays partial). F-R-003: Differentiate Without Color needs a cue on the Settings › Upload selection. F-R-001: the S42 status notice must be captured from the layout the capture reports. F-R-004: the Toolbox menu capture must open every time or fail the run. F-R-005: the input fence must record keyboard, button and pointer events separately. Harness timing, menu and fence-count fixes are in the same batch. Branch not recorded in the sources.
- **Independent review round 3 (pending):** focused on the review round 2 regression fixes (R2-001 to R2-005, R2-014 to R2-018). OSN-071 waits on it.
- **Final gates (pending):** after batch 9 and review round 3. OSN-071 and OSN-072 depend on them.
- **Open with no fix recorded:** F-J3-009, F-J4-006, F-J4-007 and R1-021 (stretch goal). Partial: F-J6-002 (the Copy Image path for an unresized Original-size picture was not re-run). Gaps listed in the resolution index: F-J1-012, F-J2-011, F-J2-017, F-J3-008, F-J3-010.
- **R1-001 history cleanup:** the withdrawn capture is out of the tree but still in history. The cleanup is owned by root and must happen before any push.
- **Matrix housekeeping (e2e lane, next regenerate):** the gap column disagrees with the observed cell in 16 rows and is blank in 72; 32 rows read `e2e-partial:` in it. Counts in this file use the observed cell.
- **Font Awesome glyphs:** every capture since batch 4 is icon mode `sf` (Font Awesome Pro is not bundled). The Toolbox icons (F-J1-009) still need one FA-mode capture.
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
