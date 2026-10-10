# OpenSnap implementation progress

**Baseline:** `bad6617`, when implementation began (the rename and migration were already merged in `f7ff86b` and `d2dc3c9`).
**Main now:** `fa4715f`. The eighteen implementation merges below are followed by the E2E audit merges since `284f028`, listed in the E2E audit section.
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

**Evidence classes are never merged.** `E2E` is a real click or key in an isolated session copy, with the result seen in a screenshot or an AX read. `rendered` is a harness capture (`tools/eye-dump-audit.sh`): the app drew the state in-process, which shows how it looks, not that a user can reach it. `unit/source` is a named existing test. `unverified` means nothing has been recorded yet.

### Merges since 284f028

Merges to main, first-parent order. Merges of main into the batch and probe branches (`e41f0c2`, `663fa39`, `082ff95`) are not listed.

| Merge | Branch | What it did |
|---|---|---|
| `c9d485c` | audit/e2e-j5 | J5 gap closure: 47 `unverified` rows to E2E, 99 rows each with one gap reason, F-J5-001 to 007 (source `e953411`) |
| `04dda5b` | fix/audit-batch-4 | Batch 4: whole-pixel sizes, non-colour selection cues, Increase Contrast glyphs, fitted destination forms, one capture-shortcut surface removed, Cancel-first destructive sheets, History notices, Resize and Toolbox icons. Branch commits `d9ed8b7`, `6d833a8`, `1d8c3d3`, `e3f99b8`, `12b75e6`; evidence `495ff6b` |
| `877a5c6` | audit/panel-probe | Launcher panel-service watchdog (SIGKILL above 2 GB) and the F-J5-005 investigation |
| `b09ecc6` | fix/review-r1-tools-docs | Review round 1 tools and docs: leaked capture withdrawn, OCR sweep tool, harness input fence, Free-only fonts by default, ledger corrections, neutral role names |
| `fa4715f` | fix/panel-service-runaway | F-J5-005 root cause: the launchers canonicalize their session dir. App code unchanged; the OS bug remains on macOS 27.2 |

### Journeys

| Journey | Scope | Source revision | Merge | Result |
|---|---|---|---|---|
| J1 editor core | Real clicks and keys: drawing, text, colour, size, shadow, Resize, crop, full screen, Toolbox, Photos, keyboard walk | `15d5ec2` | `10040ba` | 26 findings (F-J1-001 to 026); 87 image files in `e2e-2026-10-10/j1/` (86 captures per the merge message) |
| J2 History, Settings, Destinations, upload | Real clicks: History actions and sheets, Settings tabs, Destinations forms, About, and one live S3 synthetic upload | `10040ba` | `2cc07da` | 24 findings (F-J2-001 to 024); 78 captures in `e2e-2026-10-10/j2/` |
| J3 rendered matrix | **Rendered only, not E2E.** Light and dark, five sizes, Reduce Transparency, Increase Contrast, Differentiate Without Color, Reduce Motion and combinations, with positive controls | `3194247` | `baea204` | 11 findings (F-J3-001 to 011); 111 captures packed in `e2e-2026-10-10/j3/` from 3,338 PNGs over 18 runs |
| J4 real-click retest | Real-click retest of the 47 fixes from batches 1 to 3c, plus the live S3 delete through the app | `94b7aa5` | `284f028` | 37 pass, 8 partial, 2 unverified of 47 (the table after the ledger correction; the original summary said 38 and 7); 7 new P3 findings (F-J4-001 to 007); 76 captures in `e2e-2026-10-10/j4/`, AWS log in `e2e/j4-aws-log.md` |
| J5 gap closure | Real input for every `unverified` row that could be reached; one gap reason for each row that could not; the F-J5-005 panel-service investigation | `e953411` | `c9d485c` | 7 findings (F-J5-001 to 007); 47 rows to E2E; 48 jpg plus one AX and state readout file in `e2e-2026-10-10/j5/` |
| J6 real-click retest | Real clicks on batch 4 and the batch 5 fixes, in an isolated session | pending | pending | pending (R1-009) |

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
| 5 | no branch recorded yet | not merged | In progress: app findings from independent review round 1 (see the resolution index) |

### Finding dispositions

Derived from the J4 retest table in `e2e/findings.md` (after the ledger correction), the J5 section, the F-J5-005 investigation, and the batch 4 commit subjects and evidence. Batch 4 has no verdict in `findings.md`, so its fixes are mapped from commit subjects and the evidence folder. They were checked rendered only, and the table keeps them apart from real-click passes.

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

Every finding ID from J1 to J5 (75) and every review round 1 ID R1-001 to R1-024 (24). Status key: **fixed** (merge or batch named); **partial**; **deferred**; **gap** (outside what the harness or the isolated session can prove); **doc-only**; **open** (no fix recorded in the sources; listed, not scheduled); **in progress** (batch 5); **J6 pending**; **accepted trade-off** (none recorded). The R1 titles are not written down in the repo, so R1 rows carry their status and batch from the lane brief, with no title.

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
| F-J1-009 | fixed | batch 4 `1d8c3d3`; not retested | Toolbox rows draw their icons (J4 had 18 rows and no icons). Batch 4 captures are icon mode `sf` |
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
| F-J3-004 | fixed | batch 4 `6d833a8`; rendered | Increase Contrast darkens glyphs and keeps toggle labels at contrast |
| F-J3-005 | fixed | batch 4 `1d8c3d3`; rendered | Zoom and Original size explain what they measure |
| F-J3-006 | fixed | batch 4 `d9ed8b7`; rendered (inferred) | Whole-pixel sizes. The finding is plausible only and still needs a real-click check |
| F-J3-007 | fixed | batch 4 `1d8c3d3`; rendered (inferred) | Status keeps the tool or size longest, and link steps file-name-first |
| F-J3-008 | gap | OS-owned | Window title text is system-drawn |
| F-J3-009 | open | none | Small and empty documents use 4 to 41% of a large window; no batch 4 subject covers it |
| F-J3-010 | gap | OS-owned | Unselected radios and checkboxes are system-drawn |
| F-J3-011 | partial | batch 4 `1d8c3d3`; not seen | Resize uses Font Awesome Free arrows, but batch 4 captures are icon mode `sf`. Needs an FA-mode capture |
| F-J4-001 | fixed | batch 4 `12b75e6`; rendered (inferred) | Destination errors stay on the page they were raised on; the list shows none |
| F-J4-002 | open | none | History Date clipped for two-digit days (AM/PM lost) |
| F-J4-003 | fixed | batch 4 `d9ed8b7`; rendered (inferred) | History footer notice after Delete from Web. The CDN cache is outside the app |
| F-J4-004 | fixed | batch 4 `e3f99b8`; rendered (inferred) | History keeps the published size for Shared entries |
| F-J4-005 | fixed | batch 4 `d9ed8b7`; rendered (inferred) | Destructive sheets are Cancel-first, including Delete from Web |
| F-J4-006 | open | none | Previous document's size shown briefly after History › Open |
| F-J4-007 | open | none | Erased fragments lose their shadow; a design question, may be intended |
| F-J5-001 | open | none | Timed Snapshot silently drops an invalid delay |
| F-J5-002 | open | none | ⌘D does not answer the sheet attached to History; may be the harness |
| F-J5-003 | open | none | Save to History on a blank canvas does nothing and says nothing |
| F-J5-004 | open | none | Upload with no destination shows an empty list and no explanation |
| F-J5-005 | fixed | `877a5c6` watchdog; `fa4715f` root cause | Launchers canonicalize the session dir. App code unchanged; the OS bug remains on 27.2 (see the panel investigation) |
| F-J5-006 | open | none | The circle-exclamation icon has no call site |
| F-J5-007 | open | docs lane, next matrix regenerate | Three inventory names do not match the build; the generator is outside this lane |

#### Review round 1 (R1-001 to R1-024)

| ID | Status | Batch or merge | Note |
|---|---|---|---|
| R1-001 | fixed | `b09ecc6` | Harness input fence; leaked capture withdrawn from the tree. History cleanup pending, owned by root before any push |
| R1-002 | in progress | batch 5 || — |
| R1-003 | in progress | batch 5 || — |
| R1-004 | fixed | `b09ecc6` | Free-only fonts by default; the default build never bundles Font Awesome Pro |
| R1-005 | in progress | batch 5 || — |
| R1-006 | in progress | batch 5 || — |
| R1-007 | fixed | `b09ecc6` || — |
| R1-008 | fixed | `b09ecc6` || — |
| R1-009 | J6 pending | J6 retest | Real-click retest of batch 4 and the batch 5 fixes |
| R1-010 | in progress | batch 5 || — |
| R1-011 | in progress | batch 5 || — |
| R1-012 | in progress | batch 5 || — |
| R1-013 | in progress | batch 5 || — |
| R1-014 | in progress | batch 5 || — |
| R1-015 | in progress | batch 5 || — |
| R1-016 | deferred | none || — |
| R1-017 | in progress | batch 5 || — |
| R1-018 | in progress | batch 5 || — |
| R1-019 | in progress | batch 5 || — |
| R1-020 | in progress | batch 5 || — |
| R1-021 | in progress | batch 5 stretch || — |
| R1-022 | in progress | batch 5 || — |
| R1-023 | fixed | `b09ecc6` || — |
| R1-024 | fixed | `fa4715f` | Panel-service root cause in the launchers; the OS bug remains |

#### Totals by status

| Status | F-J (75) | R1 (24) | All (99) |
|---|---|---|---|
| fixed | 50 (37 real-click pass, 12 batch 4 rendered only, 1 launcher) | 6 | 56 |
| partial | 8 | 0 | 8 |
| deferred | 1 | 1 | 2 |
| gap | 5 | 0 | 5 |
| doc-only | 1 | 0 | 1 |
| open (no fix recorded) | 10 | 0 | 10 |
| in progress (batch 5) | 0 | 16 (incl. R1-021 stretch) | 16 |
| J6 pending | 0 | 1 | 1 |
| accepted trade-off | 0 | 0 | 0 |
| **Total** | **75** | **24** | **99** |

Check: 56 + 8 + 2 + 5 + 1 + 10 + 16 + 1 + 0 = 99.

### Coverage summary

Source of truth: `e2e/coverage-matrix.md` (one row per audit ID) and `e2e/inventory.json` (the same 590 entries). The matrix is regenerated from the sources, so these are the counts it has now.

Evidence classes are never merged:

- **`E2E`**: a real click or key in an isolated session copy, with the result seen in a screenshot or an AX read.
- **`rendered`**: the harness renders the state in-process (`tools/eye-dump-audit.sh`). It shows how the state looks, not that a user can reach it. It is not a real-click result.
- **`unit/source`**: a named existing test or source check.
- **`unverified`**: nothing recorded yet, or a row the audit could not exercise. Each one should carry a gap reason. 122 of the 125 do; the other 3 do not (see below).

| Evidence class | Rows in `coverage-matrix.md` |
|---|---|
| `E2E` (real input, viewed) | 303 |
| `rendered` (harness render, not real input) | 71 |
| `unit/source` (named test or check) | 91 |
| `unverified` (gap reason in the row, or none) | 125 |
| **Total** | **590** |

Earlier notes said 589 rows. The file has 590, and the inventory has 590 entries (`e2e`: 494, `e2e-partial`: 53, `gap`: 43). Earlier prose figures (258 / 94 / 146 before J5; 305 / 99 after J5; 299 / 71 / 129 after the ledger corrections) do not match this file. The matrix is the source.

Gap reasons for the 125 `unverified` rows, counted per row from the row text:

| Gap reason | Rows |
|---|---|
| `gap: unsafe` (captures that grab the owner's display, network, system-wide hotkeys) | 36 |
| `gap: harness` (synthetic right-click, held keys, file drop, non-key window) | 32 |
| `gap: AX presence only` (present in the menu tree, not pressed) | 23 |
| `gap: OS-owned` (system panels, Photos and Pictures choosers, share picker) | 18 |
| `gap: hardware` (multi-display, 1x, printer) | 5 |
| `gap: permission` (Screen Recording, Photos library) | 4 |
| `gap: text readout only` | 2 |
| `gap: AX value only` | 2 |
| **No gap reason in the row** | **3** |
| **Total** | **125** |

The 3 rows without a reason: MENU-004 (observed at `10040ba` opening the removed Capture Shortcuts sheet; its note says re-check after `d9ed8b7`), and HOT-041 and ICON-107, whose observed cell still reads `TBD`. Another 32 unverified rows show `e2e-partial:` in the gap column; their reasons sit in the observed cell.

A note on how these were counted. A plain `grep -o "gap: [a-zA-Z-]*"` cuts multi-word reasons after the first word (for example "gap: AX presence only" becomes "gap: AX") and also counts gap text outside the `unverified` rows, so it is not a per-row count.

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
| `e2e-2026-10-10/panelfix/` | 4 | Panel-service check after the F-J5-005 fix: ⌘E, ⌘S and ⇧⌘S panels, and the state after Cancel, with `00-cmd-o-panel-service.txt`. The ⌘O screenshot shows the owner's Documents folder and is deliberately not stored |
| `impl-2026-10-09/audit-fix-1/` | 74 | Batch 1 visual acceptance, `8e7a37d` |
| `impl-2026-10-09/audit-fix-2/` | 38 | Batch 2 visual acceptance, `2275c5b` |
| `impl-2026-10-09/audit-fix-3a/` | 25 | Batch 3a visual acceptance, `cc05825` [24 captures in the earlier note] |
| `impl-2026-10-09/audit-fix-3b/` | 184 | Batch 3b visual acceptance, `526ab3c` (Settings re-captured at `41b2507`) |
| `impl-2026-10-09/audit-fix-3b-before/` | 62 | Batch 3b before-state twins, `2cc07da`, dark |
| `impl-2026-10-09/audit-fix-3c/` | 52 | Batch 3c visual acceptance, `0edc3ce` and `6469efb` |
| `impl-2026-10-09/audit-fix-4/` | 147 | Batch 4 visual acceptance at `1026e58`, rendered, icon mode `sf`: `dwc/` 16, `ic/` 12, `plain/` 119; each with `captures.md` and `layout/` |
| `impl-2026-10-09/m1-rail/` | 80 | Rail removal, 80 captures at `fef46c7` |
| `impl-2026-10-09/m4-glass/` | 98 | Glass plates, 98 captures at `da2738d` |
| `impl-2026-10-09/m4-states/` | 230 | OSN-044 and OSN-061 part 2 states, source `cc97054` [158 captures in the earlier note] |
| `impl-2026-10-09/m4-window/` | 50 | OSN-043 and OSN-041 step 5 window chrome, `7bf20f8` |
| `impl-2026-10-09/m5-capture/` | 38 | OSN-050 capture states, `8a0e8d9` |
| `impl-2026-10-09/m5-settings/` | 36 | OSN-051 Settings, `a48d0df` |
| `impl-2026-10-09/m5-upload/` | 30 | OSN-054 upload states in the status slot, `fc61ac7` |

Also outside `evidence/`: `e2e/panel-probe/` holds `probe.swift` (the throwaway panel probe) and `trials/` (`sampler.py`, two sample logs for the live ⌘O trials, `watchdog.log`).

The rendered folders (`j3`, `j3-diffs`, `audit-fix-*`, `m*`) are harness renders. Do not read them as real-click proof. The `panelfix` and `j1`, `j2`, `j4`, `j5` folders are the real-click evidence.

### E2E audit gaps (not proven by this audit)

These are outside what the harness or the isolated session could prove. They are listed, not waived.

- **VoiceOver speech.** The AX dumps and the G10 walker are structural checks. The manual pass for OSN-062 is not recorded.
- **Live Screen Recording capture**, including the Frame-mode scroller question (VF-27) and the countdown over a live desktop.
- **1x and multi-display.** The only display was 2x Retina. The 1x menu-bar check (OSN-023) is not done.
- **Photos library contents.** J1 opened the Photos sheet in its empty state only. The populated browser reads the real library and was not exercised.
- **OS-owned panels.** The internals of Save, Open, Export, Print, Share, Page Setup and the Colors panel are the OS's. Since the F-J5-005 fix, the Open, Save and Export panels are visible and clickable through the driver (`panelfix`), but their contents are not judged.
- **Printer.** Nothing was printed.
- **Held-modifier gestures**, such as a drag made while holding Shift or Option.
- **Context menus** (History tiles, Upload button, text annotation) are not reachable by a synthetic right-click.
- **⌘1 to ⌘4 in Settings** (F-J2-011): the harness maps chords to menu items, and ⌘2 would start a real full-screen capture of the owner's display. A real-keyboard check is still open.
- **Window title text and system radio and checkbox drawing** are OS-owned (F-J3-008, F-J3-010).
- **Drag well Export panel** (F-J1-012, plausible and unconfirmed).
- **Field names in the destination forms** (F-J2-017): the AX tool cannot show whether an explicit label exists.
- **FTP and FTPS destination forms** were not opened in J2 or J4.
- **Timed UI states:** the 12 s success-line hold, the Retrying label and the Upload cancelled notice (needs a slow network). Only one real upload was allowed.
- **Minimum-size reflow** of History at 880 × 600 (F-J2-009): no window resize tool.
- **Clipboard:** it held no text before the run, so non-text contents could not be saved; it was reset to empty text at the end.
- **Added since 284f028:**
  - **Font Awesome Pro is no longer bundled by default** (`b09ecc6`, R1-004). The Pro glyph path is dev-only, so no capture here exercises Pro icons.
  - **Font Awesome Free in the batch 4 captures.** Batch 4 captures are icon mode `sf`, so the Free glyph changes (F-J3-011, and the Toolbox icons under F-J1-009) are not seen in the evidence.
  - **macOS 27.2 panel-service bug** (F-J5-005). The OS bug is unfixed. A process launched with a non-normalized `CFFIXED_USER_HOME` hangs its first Open or Save panel. Real users are not affected (their home is normal). Any new harness that opens a system panel must normalize its home first.

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

- **Batch 5 (in progress, no merge yet):** app findings from independent review round 1. Scope from the lane brief: upload original size, Resize seeding, Toolbox menu icons, a single destinations surface in Settings › Upload, History toolbar labels, the status line not repeating the title, Delete-from-Web binding stability, and the P3s. Mapped IDs: R1-002, 003, 005, 006, 010 to 015, 017 to 020 and 022 (15), plus R1-021 as a stretch goal. Batch 4 already touched the Toolbox icons (`1d8c3d3`), so batch 5 starts by checking what remains.
- **J6 real-click retest (R1-009):** pending. It is the first real-click check of batch 4 and of the batch 5 fixes, and it covers the batch 4 items that are rendered only.
- **Independent review round 2:** pending. OSN-071 waits on it.
- **Final gates:** pending. OSN-071 and OSN-072 depend on them.
- **R1-001 history cleanup:** the withdrawn capture is out of the tree but still in history. The cleanup is owned by root and must happen before any push.
- **Matrix and inventory housekeeping (docs lane, next regenerate; this lane does not edit `e2e/`):** F-J5-007 names; three unverified rows with no gap reason (MENU-004 has a re-check note, HOT-041 and ICON-107 read `TBD`); 32 unverified rows whose gap column reads `e2e-partial:` instead of a reason (the reason is in the observed cell); earlier prose counts (258/94/146, 305/99, 299/71/129) predate the current file (303/71/125 over 590 rows).
- **F-J3-011 and the batch 4 Font Awesome glyphs:** need one FA-mode capture; batch 4 evidence is icon mode `sf`.
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
