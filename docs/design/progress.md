> Current result: [Final local verification](e2e/final-verification.md) at the rewritten candidate `41700b3`, with the exact tested tree of `1ea366c`. The historical tables below retain their original source labels. Final integration gates passed; complete E2E coverage remains partial.

# OpenSnap implementation progress

**Baseline:** `bad6617`, when implementation began (the rename and migration were already merged in `f7ff86b` and `d2dc3c9`).
**Main now:** `3b453b3`. The eighteen implementation merges below are followed by the E2E audit merges since `284f028`, listed in the E2E audit section.
**Status of 36 todos:** 31 done, 2 verified, 1 not-a-bug, 2 in-progress, 0 pending, at `66ff7312` (release 0.4.0, 2026-10-12; see Release 0.4.0 status). At `3b453b3` it was 29 done, 2 verified, 1 not-a-bug, 3 in-progress, 1 pending.

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
| OSN-062 | in-progress (automated layer done; manual listening pass open) | `7c8bdb1` (labels, announcements); `4fca729` (G10 walker, 32 surfaces, 0 violations); `aeb37912`, `be4d72cb` (round 3 and burn-down) | G10 walker 0 violations; announcement inventory 42 rows (38 announced, 1 VoiceOver-native, 3 silent, 0 pending) | 75 spoken scripts in `docs/design/evidence/osn-062-2026-10-11/spoken/`; manual pass none |
| OSN-061 | done | part 1 `accfedd` (`de21b6e`, `d0f8013`, `2dc613e`, `eaab72f`, `f975dfa`); part 2 `3ee9503` | DisplayOptionsTests: 92 checks (part 1) | J3 rendered positive controls for all four options (`e2e-2026-10-10/j3`, rendered only) |
| OSN-070 | done (release 0.4.0 state; `9011e305` and later on `impl/osn-062`, not on main) | G2 to G12 wired in `tools/test.py`; G1 by hand; G3 and G12 not on main | can-fail self-test for every gate except G1 and G2 (recorded exception); gate table below | `docs/design/evidence/osn-071-2026-10-11/` (G7 runs over the committed sets) |
| OSN-072 | done | evidence `c906d7bb` (on main); migration and dry run on copies | migration 58/58, 2 destinations, re-run no-op; clean clone 275/275 app safety; release dry run at 0.3.0 | `docs/design/evidence/osn-072-2026-10-11/` |
| OSN-071 | in-progress (round 4 captured; sign-off pending final confirmation) | evidence only, `66ff7312` (round 4 at `8188b73`) | `check-eye-dump --strict` 0 failures on 5 packs; text walker 0 violations | 2,260 captures, `docs/design/evidence/osn-071-2026-10-11/` |

## Release 0.4.0 status (2026-10-12)

State at `66ff7312` on `impl/osn-062`. `main` is at `c906d7bb`. The gate and VoiceOver work is on `impl/osn-062` and is not merged. SHAs for this update resolve in the local clone; the older SHAs carried in the todo rows and notes are historical (see the last note).

| Todo | At `41700b3` | Now | Evidence |
|---|---|---|---|
| OSN-070 | in-progress | **done** | gates from `9011e305` and later; gate table below |
| OSN-072 | in-progress | **done** | `docs/design/evidence/osn-072-2026-10-11/`; evidence commit `c906d7bb` (on main) |
| OSN-062 | in-progress | in-progress | automated layer done (`docs/design/evidence/osn-062-2026-10-11/spoken/`); manual listening pass open |
| OSN-071 | in-progress | in-progress | round 4 at `8188b73` (commit `66ff7312`, `docs/design/evidence/osn-071-2026-10-11/`); sign-off pending final confirmation |

Totals: 31 done, 2 verified, 1 not-a-bug, 2 in-progress, 0 pending (was 29, 2, 1, 4, 0). Milestone counts: roadmap section 2b.

Notes:

- **G1** is run by hand (`tools/check-clean-clone.sh`). It is not in `tools/test.py`.
- **G3 and G12** (`check-user-strings.py`, `check-layout-fit.py`) are not on main. Main has neither file.
- **OSN-071 advisories:** `REVIEW.md` reports 0 contrast advisories on every pack. The non-contrast advisories (18 pt controls, truncated status text) are listed in the todo.
- **OSN-062 provenance:** `spoken/INDEX.md` records build `dda6b216` on every row. `aeb37912` changed the script text after that commit.
- **OSN-072 dry run used 0.3.0.** `Info.plist` is still `0.3.0`, build `3`. The bump to 0.4.0 and a `tools/release.sh 0.4.0` dry run are still to do. Release work, not changed here.
- **Historical SHAs:** 108 of the 123 SHAs cited in `backlog.json` do not resolve in this clone (for example `658a16f`, `284f028`, `7c8bdb1`, `3ee9503`, `0996da5`). Older notes are kept as written. The R1-001 history cleanup (Open items and gaps) may explain the gap.

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

**Evidence classes are never merged.** `E2E` is a real click or key in an isolated session copy, with the result seen in a screenshot (viewed, not only listed) or an AX read. `rendered` is a harness capture (`tools/eye-dump-audit.sh`): the app drew the state in-process, which shows how it looks, not that a user can reach it. `unit/source` is a named existing test or source check. `unverified` is a row the audit could not exercise; it carries exactly one audited `gap reason`. `retired` is a row whose surface the app removed or replaced; it is counted in no other class. The `reachability note` column is the generator's static prediction of what may stand in the way; it is not evidence and is not counted.

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
| `02d4ca5` | fix/ledger-gap-column | Ledger: the gap column splits into a static `reachability note` (generator prediction) and the audited `gap reason`, with `--check` rules and can-fail proofs (`2649cce`). Every unverified row now carries exactly one audited reason |
| `76cbe52` | fix/tooltip-flake | Tooltip suite waits on events instead of a fixed 0.3 s spin, so a frozen process no longer trips the SIGTRAP; a freeze check that can fail (`05cd86e`). Test-only |
| `d1d24c0` | fix/audit-batch-9 | Batch 9: Increase Contrast reaches unselected tool glyphs and disabled controls; non-colour cue on the selected Upload row; S42 notice and S44 footer wait for the label's text; Toolbox menu capture retries once; input fence counts per kind. F-R-001 to 005 (`227a471`, `2567b89`, `6cc0b37`, `32b4a03`, `e14b985`); evidence `16a8e09` |
| `4f8b5d9` | fix/audit-batch-10 | Batch 10: oversized Resize and corner drags rewrite the picture, so title and outputs agree; Export accessory follows the footer; DWC row bar; hotkey pause errors reach the note; `(deleted)` Destination. R3-001 to 009 (`0fd7dfa`); harness surface S46 (`a601d7e`, `9faf5c0`); evidence `8802c2e` |
| `748f352` | fix/audit-batch-11 | Batch 11: Actual Size after an oversized Resize; native-width Resize; ticked corner drag in picture pixels; exact Limit; fit-zoom tracking; Export box only when it differs; plain-words hotkey error; Settings timing on an injectable clock. R4-001 to 007 (`61bea34`); harness surface S47 (`21113c9`); evidence `audit-fix-11`, docs `4c6927e` |
| `3b453b3` | fix/audit-batch-12 | Batch 12: full-screen Cancel restores the zoom record; Actual Size refits after Undo or a full-screen change; ticked corner drag clamps at the supported size; Limit lands on its number with no snap. R5-001 to 004 (`2045fcd`). Tests only, no evidence folder |

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
| 9 | `fix/audit-batch-9` | `d1d24c0` | `impl-2026-10-09/audit-fix-9/` (52, `16a8e09`). F-R-001 to 005; rendered and harness checks, not real-click |
| 10 | `fix/audit-batch-10` | `4f8b5d9` | `impl-2026-10-09/audit-fix-10/` (44, `8802c2e`, S46 at `9faf5c0`). Rendered, icon mode `sf`. R3-001 to 009 |
| 11 | `fix/audit-batch-11` | `748f352` | `impl-2026-10-09/audit-fix-11/` (36, `4c6927e`, S47 at `21113c9`). Rendered, icon mode `sf`. R4-001 to 007 |
| 12 | `fix/audit-batch-12` | `3b453b3` | no evidence folder; checked by tests in `tests/AppSafetyBatch11Cases.swift` (each with a can-fail proof, the fix reverted in a scratch copy). R5-001 to 004 |

Batches 9 to 12 are rendered or test-checked. No real-click pass is recorded for them.

### Review rounds

Independent reviews of the batch branches. Each round's findings are in `e2e/findings.md`; the round's fixes are in the batch named.

| Round | Pinned at | Scope | Findings | Outcome |
|---|---|---|---|---|
| 3 | `5af9ac0` | Focused: the round 2 regression fixes (pause lifecycle, size paths, Toolbox placement, session-only watchdogs, ledger categories, fresh evidence) | R3-001 to 009 (2 × P2, 2 × P3, 5 × P4) | Verdict: needs fixes. Every item fixed in batch 10 (`4f8b5d9`). A reviewer pass at `4f8b5d9` produced round 4 |
| 4 | `4f8b5d9` | Narrow: the batch 10 fixes and their follow-ups | R4-001 to 007 (3 × P3, 4 × P4; R4-005 and R4-006 are ledger and evidence) | Every item fixed in batch 11 (`748f352`). The orchestrator decided R4-003 (ticked corner drag in picture pixels) |
| 5 | `e084f15` | Confirmation of batch 11 | R5-001 to 004 (all P4) | Every item fixed in batch 12 (`3b453b3`) |
| 6 | `3b453b3` | Confirmation of batch 12 | R6-001 and R6-002 (P4) | Both fixed in batch 13; regression tests failed on old code and pass on the candidate |
| Final gates | `1ea366c` → `41700b3` (same tree) | Gates after batch 13 | **PASS** | Cold build, two full suites, clean clone and no-Pro-font gate passed; OCR executed with flags; see final-verification.md |

Round 3's objections, accepted with the decision recorded in the findings: R1-016, R1-021, the record-shortcut field, F-J1-012 (OS-owned panel), the upload-percentage item (no byte progress), F-J8-001, F-J8-002, and the final render's two historic menu gaps. Accepted with conditions: F-J1-023 is next in line; the deactivation pause stays unit-tested only, now with the real did-resign-active notification posted in the test (R3-008).

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

Every finding ID from J1 to J8 (93), every review round 1 ID R1-001 to R1-024 (24), every review round 2 ID R2-001 to R2-018 (18), every review round 3 ID R3-001 to R3-009 (9), round 4 R4-001 to R4-007 (7), round 5 R5-001 to R5-004 (4) and every final render ID F-R-001 to F-R-005 (5): **160 in all**. Status key: **fixed** (merge or batch named, and not contradicted by a later real-input result); **partial** (part of the item passed under real input, or the fix holds only in the rendered harness or in a test); **deferred**; **gap** (outside what the harness or the isolated session can prove); **doc-only**; **open** (no fix recorded in the sources; listed, not scheduled); **accepted trade-off** (recorded as acceptable by the journey that found it). R1 rows take their titles from the round 1 record in `docs/design/e2e/findings.md`. Rounds 3 to 5 and F-R-001 to 005 are fixed in the batch the responses name; round 6 and the final gates are not yet recorded and no row depends on them.

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
| F-J1-023 | partial | `impl/followup-20261010` at `210e80e` (not on main) | Not reproduced: real-input check selected and deleted text; guard `fuTextEditorAccessibility`. VoiceOver speech unproved |
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
| F-J3-004 | partial | batch 4 `6d833a8`; batch 9 `227a471` (F-R-002); rendered | Borders and the Snap outline strengthen under Increase Contrast; batch 9 raises unselected glyphs and disabled controls, measured in the render only. Stays partial until a real-display check |
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
| F-J4-006 | fixed | earlier code; guard `fuHistoryOpenShowsNewSize` on `impl/followup-20261010` at `210e80e` (not on main) | No source change; the size is synced on open. The J4 retest was PARTIAL; no real-input re-run on `210e80e` |
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
| R2-011 | P3 | S42 status-notice capture mistimed; captions wrong | fixed | review round 2 lane `0b03903`; batch 9 `6cc0b37` (F-R-001) | Captions corrected in `0b03903`. Batch 9 waits for the label's text before the shot; round 3 re-measured the notice claims and confirmed them |
| R2-012 | P3 | Harness input fence: no event counts, no hover fence | partial | batch 6 `29481af` (record); batch 9 `e14b985` (F-R-005) | The swallowed count is recorded, and batch 9 splits it by kind (keyboard, button, pointer). Hover fence not recorded in the sources |
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
| F-R-001 | P3 | S42 status-notice captures show the stale status | fixed | batch 9 `6cc0b37` | Notice in 2 of 21 attempts (light only) before the fix; the shot now waits for the label's text. Round 3 re-measured it |
| F-R-002 | P3 | Increase Contrast does not raise glyph or disabled contrast | fixed | batch 9 `227a471` | Glyph 4.00:1 before; 20.9:1 light and 10.7:1 dark after (round 3). Rendered only. F-J3-004 stays partial |
| F-R-003 | P3 | Differentiate Without Color leaves the Upload list selection colour-only | fixed | batch 9 `2567b89`; R3-007 | Selected row gets a 2 pt edge and a leading bar (edge 16:1 under Differentiate, per the batch 9 evidence message) |
| F-R-004 | P3 | Toolbox menu capture fails intermittently and passes silently | fixed | batch 9 `32b4a03` | The capture retries once; check-eye-dump fails an unexplained menu gap |
| F-R-005 | P3 | Input-fence count cannot tell a parked pointer from typing | fixed | batch 9 `e14b985` | Counts per kind; only typing and buttons flag a run |

#### Review round 3 (R3-001 to 009)

Focused review at `5af9ac0`. Fixed in batch 10 (`4f8b5d9`, code `0fd7dfa`).

| ID | Priority | Title | Status | Batch or merge | Note |
|---|---|---|---|---|---|
| R3-001 | P2 | Resize past the window's room: the picture stays, the title and outputs keep the fitted size | fixed | batch 10 `0fd7dfa` | A Resize or Limit above the room makes the picture the output, shown by display zoom; title, export, upload, copy, drag and History say the typed size (`b10OversizedResize`) |
| R3-002 | P2 | Corner drag on a snap changes only the shown size | fixed | batch 10 `0fd7dfa`; refined by R4-003 | A corner drag on a snap is a Resize of the picture: one Undo step (`b10CornerDragResizesPicture`) |
| R3-003 | P3 | File › Export seeds Original size from its own default, not the footer box | fixed | batch 10 `0fd7dfa` | Export seeds from the footer box and hands the answer back (`b10ExportAccessoryMatchesFooter`) |
| R3-004 | P3 | Ledger: E2E-STATE-018 and 019 describe the pre-batch-9 state; STATE-019 cites the wrong finding | fixed | batch 10 `0fd7dfa` | Rewritten for the batch 9 re-render; STATE-019 cites R3-007. Batch 11 corrected its SHA (R4-005) |
| R3-005 | P4 | "Selection-style pop-up" wording survives for the Toolbox | fixed | batch 10 `0fd7dfa` | Replaced in harness and inventory text |
| R3-006 | P4 | Gap-reason vocabulary accepts `retired` on an unverified row | fixed | batch 10 `0fd7dfa` | `--check` rule and can-fail proof in `tools/test.py` |
| R3-007 | P4 | Selected Upload row under Differentiate uses the Default pill's check glyph | fixed | batch 10 `0fd7dfa` | Selected row: 2 pt edge plus a leading bar; the check stays the Default pill's |
| R3-008 | P4 | Capture pause: failed re-registration not shown; no test posts the real deactivation notification; one path orders Settings out without marking it hidden | fixed | batch 10 `0fd7dfa` | The failure shows on the Capture note and its spoken value; the test posts the real did-resign-active notification |
| R3-009 | P4 | History Details: a dead link after Delete from Web shows nothing saying it was deleted | fixed | batch 10 `0fd7dfa` | Details marks the address `(deleted)` beside the published size |

#### Review round 4 (R4-001 to 007)

Narrow review at `4f8b5d9`. Fixed in batch 11 (`748f352`, branch commits `61bea34` and `21113c9`, `e4dcb06`, `2930ad2`, docs `4c6927e`).

| ID | Priority | Title | Status | Batch or merge | Note |
|---|---|---|---|---|---|
| R4-001 | P3 | Actual Size disabled after an oversized Resize, though the picture is bigger than its window | fixed | batch 11 `61bea34` | `canToggleActualSize` holds for a snap shown below 100%; the saved zoom returns on leaving Actual Size (`b11ActualSizeAfterOversizedResize`) |
| R4-002 | P3 | Unticked, typing the picture's own width does nothing or resamples a pixel short | fixed | batch 11 `61bea34` | Exact native size; a proportional request within a pixel snaps to the picture (`b11NativeWidthWhileUnticked`; `ResizePanelTests`) |
| R4-003 | P3 | Ticked corner drag collapsed the picture to the shown size | fixed | batch 11 `61bea34`; clamped by R5-003 | Drag scales the picture's own pixels by its proportion of the shown size, by the orchestrator's decision (`b11CornerDragTicked`) |
| R4-004 | P4 | Automatic zoom-to-fit not tracked on every path | fixed | batch 11 `61bea34` | Window fits, full screen and Frame undo all keep the record (`b11FitZoomIsTracked`) |
| R4-005 | P4 | Ledger: no round 3 responses; STATE-019 cites one SHA for three SHAs; reviewer cells stale | fixed | batch 11 `4c6927e` | This section and the STATE-019 SHA list; matrix regenerated, `--check` passes |
| R4-006 | P4 | Evidence text: audit-fix-10 captions give the wrong snap size; footer captions claim size; Export shots say "Not available" | fixed | batch 11 `4c6927e`; harness `21113c9`, `e4dcb06` | Captions corrected; the export step refreshes the accessory before the shot; the two accessory shots recaptured in audit-fix-11 |
| R4-007 | P4 | File › Export always offers "Export at original size" | fixed | batch 11 `61bea34` | Checkbox offered only when the picture differs (`b11ExportOffersOriginalOnlyWhenItDiffers`) |

Also in batch 11, with no R-number: a Limit one pixel short (pre-existing; a Limit of 1400 on 1981 × 953 came out 1399 wide, fixed by a model of 2,700 sizes, 712 failures before and 0 after), the capture-note error copy in words, and Settings timing tests on an injectable clock (`2930ad2`).

#### Review round 5 (R5-001 to 004)

Confirmation review at `e084f15`. Fixed in batch 12 (`3b453b3`, commit `2045fcd`).

| ID | Priority | Title | Status | Batch or merge | Note |
|---|---|---|---|---|---|
| R5-001 | P4 | Full screen: Cancel of a Resize preview left full screen's zoom record moved, so the exit skipped the zoom | fixed | batch 12 `2045fcd` | The Resize baseline holds the full-screen zoom record and Cancel puts it back (full-screen preview, Cancel, exit: 100%) |
| R5-002 | P4 | Undo or an edit in Actual Size restored a saved zoom without refitting | fixed | batch 12 `2045fcd` | Leaving Actual Size fits the picture that is back; full screen entered or left meanwhile fits the window it is in (`b11ActualSizeAfterOversizedResize`) |
| R5-003 | P4 | Ticked corner drag past 32 M pixels showed an impossible size and cancelled silently on release | fixed | batch 12 `2045fcd` | Stops the scale at the supported size, so the title shows what release applies (`b12OversizedTickedDrag`) |
| R5-004 | P4 | Limit one-pixel fix lived only in the snap path | fixed | batch 12 `2045fcd` | One shared rule serves the snap and generic proportional paths (`b12LimitWithoutSnap`) |

#### J8 findings (F-J8-001 to 002)

| ID | Priority | Title | Status | Batch or merge | Note |
|---|---|---|---|---|---|
| F-J8-001 | P4 | The 980 footer error line shows only "Failed" | accepted trade-off | batch 8 `87abbfd` | J8: acceptable, the checkbox won. The owner may want `HTTP 403` visible in the footer |
| F-J8-002 | P4 | The pause note cannot be read off the Capture tab | accepted trade-off | none | J8: not worth shipping on its own; an AX value on the tab group would serve testing |

#### Totals by status

| Status | F-J1 to F-J8 (93) | R1 (24) | R2 (18) | R3 (9) | R4 (7) | R5 (4) | F-R (5) | All (160) |
|---|---|---|---|---|---|---|---|---|
| fixed | 70 | 20 | 14 | 9 | 7 | 4 | 5 | 129 |
| partial | 11 | 2 | 4 | 0 | 0 | 0 | 0 | 17 |
| deferred | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 2 |
| gap | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 5 |
| doc-only | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| open | 3 | 1 | 0 | 0 | 0 | 0 | 0 | 4 |
| accepted trade-off | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |
| in progress | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **Total** | **93** | **24** | **18** | **9** | **7** | **4** | **5** | **160** |

Check: 129 + 17 + 2 + 5 + 1 + 4 + 2 + 0 = 160. Changes since the last count (140): batch 9 closed F-R-001 to 005 (5 fixed); R2-011 moved from partial to fixed (its dark notice capture and the stale-status fix are in batch 9, confirmed in round 3); rounds 3, 4 and 5 add 20 fixed. Still partial (17): F-J3-004 (rendered only), R2-001 (firing a shortcut and deactivation not run for real), and the rest as listed above.

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

How the class moved (rows, 597 throughout): at `14d4d9f` (J6) E2E 322, rendered 64, unit/source 93, unverified 118. After review round 2 (R2-007, R2-008) E2E 309, rendered 48, unverified 120, retired 27. After J7 (three rendered rows, DEST-014, 016 and 022, became E2E) E2E 312, rendered 45. J8, batches 9 to 12, the ledger split (`02d4ca5`) and rounds 3 to 5 changed no class count. Recounted at `3b453b3` with the class counts above and the gap reasons below.

Gap reasons of the 120 `unverified` rows, from the audited `gap reason` column, which matches the observed cell on every row (each row has exactly one):

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

Ledger columns (`02d4ca5`, which replaced the earlier mixed gap column):

- **`reachability note`** is the generator's static prediction (`e2e-partial: os-panel`, `gap: printer`). It is filled on 105 of 597 rows: 48 unverified, 11 E2E, 13 rendered, 6 unit/source and all 27 retired. A note is a prediction, not evidence, and it is not counted in any class.
- **`gap reason`** is the audited reason. It is filled on exactly the 120 unverified rows, using the eight values above, and empty on every other row. The `--check` rule fails when an unverified row lacks a reason, another class carries one, or the two columns disagree with the observed cell.
- The earlier mixed gap column (72 blank, 32 `e2e-partial:`, 16 second labels) and the prose counts from before the ledger work (590 rows; 597 rows at J6 with 322 / 64 / 93 / 118) are superseded by these counts.
- Three rows contain an escaped pipe in a cell. Column-splitting without escape handling miscounts them; the counts above split on unescaped pipes only.

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
| `impl-2026-10-09/audit-fix-9/` | 52 | Batch 9 visual acceptance at `16a8e09`, rendered, icon mode `sf`: Increase Contrast glyphs and disabled controls (21:1 for the Select glyph), the Upload row edge under Differentiate (16:1), the S42 notice and the Toolbox menu captures |
| `impl-2026-10-09/audit-fix-10/` | 44 | Batch 10 visual acceptance at `8802c2e` (S46 harness surface at `9faf5c0`), rendered, icon mode `sf`: oversized Resize and corner drags (picture pixels, title and outputs), the Export accessory and its footer, the Capture note error, Details after delete. Caption corrections for R4-006 are in `captures.md` |
| `impl-2026-10-09/audit-fix-11/` | 36 | Batch 11 visual acceptance (S47 harness surface at `21113c9`), rendered, icon mode `sf`: Actual Size after an oversized Resize, native-width Resize, the ticked corner drag, the Export accessory with real dimensions. `captures.md` and `manifest.json` list each capture with its source SHA |
| `impl-2026-10-09/audit-fix-12` | none | Batch 12 has no capture folder. Its evidence is the test set in `tests/AppSafetyBatch11Cases.swift`, each case with a can-fail proof |
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

### Known gaps and decisions

Outside what the harness or the isolated session could prove, or decided and not built. Listed, not waived. Gaps first, then decisions, then what the owner handles before any push.

**Gaps (not proven by this audit)**

1. **VoiceOver speech.** No manual VoiceOver pass is recorded. The AX dumps and the G10 walker are structural checks. OSN-062 stays in progress.
2. **Live Screen Recording capture of the real display.** Not run; it needs the owner's display.
3. **Global capture shortcuts actually firing.** Unsafe on the real display. The pause lifecycle is verified through the visible note (J8 1a to 1e) and unit tests, including the real did-resign-active notification (R3-008).
4. **App-deactivation pause path.** Unit-tested only. Not run for real, because deactivating the app brings another app forward, which could be the owner's.
5. **1x and multi-display.** The only display was 2x Retina.
6. **Photos library.** The Photos sheet was opened in its empty state only; the populated browser was not read.
7. **Printer.** Nothing was printed.
8. **OS-owned panel internals:** Open, Save, Export, Print, Share and Colors. The app-owned parts are driven and checked.
9. **Native tooltips.** Drawn by the OS.
10. **Synthetic right-click context menus.** The synthetic click does not reach them.
11. **Held-modifier gestures**, such as a drag made while Shift or Option is held.
12. **Drag out of the app.** The driver cannot drop onto another app.
13. **⌘1 to ⌘4 with the real keyboard in Settings** (F-J2-011). The harness maps the chords to menu items; ⌘2 would start a real full-screen capture of the owner's display.
14. **Window title text, and system radios and checkboxes.** OS-owned (F-J3-008, F-J3-010).
15. **Live full-screen exit animation.** The tests call the full-screen notification handlers directly; their interplay with the animation was not run.
16. **macOS 27.2 panel-service bug** (F-J5-005, OS build 26B5101f). Unfixed in the OS. The trigger was a `//` in the session path the launchers built; they now canonicalize it (`fa4715f`), and the session-scoped watchdog (R2-013, `0b03903`) bounds any growth. The app code is unchanged.
17. **Font Awesome Pro is not bundled by default** (R1-004). The `sf` harness label means Pro subsets were stripped; it does not bypass embedded Free vectors. The root candidate render review confirms default Free icons; Pro mode remains untested.
18. **Still not run from earlier passes:** FTP and FTPS destination forms (F-J2-014); the timed upload states, the 12 s success hold, the Retrying label and the cancel notice (F-J2-022, needs a slow network); field names in the destination forms (F-J2-017, the AX tool cannot show an explicit label); Edit › Copy Image for an unresized Original-size picture (F-J6-002).

**Decisions (deferred or accepted; not built)**

- **Navigator column** in Actual Size (R1-016, with F-J3-009): left unchanged in the follow-up pass. The only small candidate, "fit up to 200%", changes zoom semantics broadly, and the navigator panel is already sized to its content.
- **Eraser shadow on cut fragments** (R1-021, open; F-J4-007, a design question): a recorded design trade-off, left unchanged in the follow-up pass. No stored format or semantics change.
- **Record-shortcut field:** the 69-item key pop-up remains (F-J2-020, partial). UX debt, deferred.
- **Text editor accessibility selection** (F-J1-023): not reproduced on `impl/followup-20261010` at `210e80e` (headless guard, and a real-input check that selected and deleted text). Not on main. VoiceOver speech unproved.
- **Drag-well Export panel** (F-J1-012): OS-owned panel, never retested. A gap.
- **Upload percentage:** no byte progress exists to show. Accepted in the round 3 record, which cites it as R2-014. In this index R2-014 is the 980 bottom bar (fixed), so the percentage item has no row here of its own.
- **"Failed" at 980** with the HTTP code in AX help and Details (F-J8-001): accepted trade-off. The owner may want `HTTP 403` in the footer.
- **Pause note only on the Capture tab** (F-J8-002): accepted trade-off; an AX value on the tab group would serve testing.
- **Small and empty documents use 4 to 41% of a large window** (F-J3-009): open, left unchanged in the follow-up pass (see the navigator line above).
- **Previous document's size shown briefly after History › Open** (F-J4-006): fixed by earlier code, guarded by `fuHistoryOpenShowsNewSize` on `210e80e`. Not on main.
- **The final render manifest's two historic menu gaps:** accepted in round 3.

**Owner, before any push (root-owned)**

- **History cleanup of the withdrawn capture** (R1-001): completed locally by root; exact exposed blob removed from all local refs and the primary object database.
- **Model and tool names** in `e2e-audit-plan.md` and `audit-overview.html` (round 3 record). Remove before any push.
- **Vendored tool-skills folder and its `.gitignore` entry.** Handle before any push.

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

- **Batches 9 to 12 and review rounds 3 to 5: done.** Fixes and their evidence are in the fix batches table and the resolution index. Batch 12 has no capture folder; its evidence is the test set.
- **Round 6: completed.** R6-001 and R6-002 were fixed in batch 13; see the response table in findings.md and final-verification.md.
- **Final integration gates: passed** on the byte-identical candidate `1ea366c` → `41700b3`. OSN-062 and the complete visual acceptance matrix stay in progress for explicit remaining gaps.
- **Open with no fix recorded:** F-J3-009, F-J4-007 and R1-021 (stretch goal). Partial: the 17 partial IDs, listed in the totals table with their notes. Gaps listed in the resolution index: F-J1-012, F-J2-011, F-J2-017, F-J3-008, F-J3-010.
- **Follow-up pass on `impl/followup-20261010` (not on main, see the section before the final handoff):** the three full-screen edge cases (FS-A, FS-B, FS-C) are fixed at `210e80e`. The mirror case (Resize sheet up, enter full screen, Cancel) is fixed at `1ac6674`. Review corrections FR-1 to FR-4 are done at `718f601` on the integration branch, not on main. The text-editor selection and History-open items are in the resolution index above.
- **R1-001 history cleanup: complete in the local repository.** The exact exposed blob is absent from all refs and the primary object database; fresh remote refs never contained it. The tested tree is unchanged.
- **Font Awesome glyphs:** default Free vectors are shown in root candidate captures. The old `sf` label reflects absence of Pro fonts, not actual per-icon resolution. Optional Pro mode is still untested.
- **Round-1 incident (OSN-001):** a can-fail proof deleted the owner's real `com.shoemoney.opensnap` defaults plist. Cause: a cleanup trap was installed before an id refusal. Fixed in `db973a6`. The SkitchRedux store and `com.shoemoney.skitch-redux.plist` hashed unchanged. The migration marker is a file in the absent OpenSnap folder, so the parked migration is unaffected.
- **Unsafe tool, resolved:** `tools/test-native-startup.py` now runs only a throwaway-id temp copy, behind a store guard (`efe2f68`). The warning from the earlier pass no longer applies.
- **OSN-042 (merged in `8015360`):** the phantom capsule under Snap and the full-screen salmon tint are gone (no per-button glass, no backdrop or bleed). Open: the legacy-scroller corner is slightly lighter than the well (AppKit draws it; there is no public API). Controls are 36 pt tall inside 44 pt bars; to be reviewed at sign-off (OSN-071). Evidence: `evidence/impl-2026-10-09/m4-glass/`.
- **Size popover** can overhang the window edge. It stays on screen and is accepted as standard NSPopover behaviour.
- **Canvas centring** was a pre-existing bug, also present at `bad6617`. It is fixed for document changes in the rail-removal branch (`c53155c`).
- **Settings (OSN-051):** merged in `e124f77`; the full integration suite passed (app-safety 166/166). The window title follows the selected tab (no "Preferences").
- **OSN-044:** merged in `3ee9503`, with OSN-061 part 2.
- **OSN-061:** parts 1 and 2 are on main (`accfedd`, `3ee9503`); done.
- **OSN-062:** labels, announcements and the audit walker are on main; the recorded manual VoiceOver pass is not done, so the todo is in-progress. Updated 2026-10-12: the automated layer is complete; see Release 0.4.0 status.
- **OSN-070 (branch `impl/osn-070-gates`, not merged):** the gates the earlier pass left open are in. Gate table (strict means the run fails on a hit):

  | Gate | Check | Wired in `tools/test.py` | Mode | Can-fail self-test |
  |---|---|---|---|---|
  | G1 clean clone | `tools/check-clean-clone.sh` | no (it runs `test.py` itself); run by hand, passed on `dbf7461` | strict | none (exception: it is the whole build in a fresh clone) |
  | G2 no original assets | `tools/check-no-original.py` (`--sources`, built bundle) | yes | strict | none (exception: static name and hash lists; not seeded) |
  | G3 user-visible name | `tools/check-user-strings.py` (static literals and Info.plist; dynamic dumps) with `tests/UserStringWalk.swift` | yes, static before the suites, dynamic after app-safety | strict | yes: 13 python seeds, plus `user-string-walk-tests` (15 kinds of seeded text) |
  | G4 font floor | `view-tree-audit-tests`, main window via app-safety | yes | strict | yes (seeded violation per control class) |
  | G5 glass depth and budget | `glass-chrome-tests` and the real-window case in app-safety | yes | strict | yes (a seeded plate inside a plate is counted; the eye-dump record is seeded in G7) |
  | G6 decorative glyphs | `tools/check-glyphs.py --strict` | yes | strict | yes |
  | G7 eye-dump evidence | `tools/check-eye-dump.py` over each committed evidence set | yes | strict | yes |
  | G8 migration | `migration-tests`, `tools/migration-dry-run.py`, real-store guard | yes | strict | yes (crash injection) |
  | G9 token literals | `tools/check-tokens.py --strict` | yes (was report mode) | strict | yes |
  | G10 accessibility | `accessibility-audit-tests` | yes | strict | yes |
  | G11 skip budget | `tools/check-skip-budget.py` | yes | strict | yes |
  | G12 layout fit at 980 | `tools/check-layout-fit.py` over every committed `layout.json`; live window in `AppSafetyLayoutFitCases` | yes | strict | yes (python seeds; live squeeze case) |

  Exceptions, with reasons. G1 and G2 have no seeded self-test. G9 scans font, colour and radius literals only: the spec's roughly 100 constraint constants are not scanned, and the harness fixture literals in `EyeDumpAuditSurfaces.swift` carry a `token-exempt:` reason. The layout-fit gate treats the status line and the bar row as elastic (they truncate), so their fitting size is not a minimum. G7's contrast check runs on committed evidence, not on a fresh capture. The Swift string walk covers the windows, menus, alerts and tooltips that the app-safety and accessibility-audit suites build; text drawn by custom `draw(_:)` and system-owned panels are outside it, as for G4.
- **OSN-072:** migration on a copy of the owner's real store is not authorized in this run. Synthetic temp stores only. The release work is a dry run only: no tag, push, upload or release. Superseded 2026-10-12: the copy migration ran (see Release 0.4.0 status).
- **OSN-054:** the upload UX is merged (`7c8bdb1`). The AWS run on 2026-10-09 is validation evidence; the E2E audit added a live upload (J2) and a live delete through the app (J4).
- **Not run:** live screen capture; real popover translucency; VoiceOver speech (OSN-062 manual pass); Reduce Transparency alone and Increase Contrast alone captures (both together are in `m4-glass`); FA Pro icon mode; the OSN-071 visual gallery and independent visual sign-off.
- **OSN-023:** manual 1x and 2x menu-bar check not done.
- **Alert check count reconciled:** the full integration run at `a79a1d8` prints `AppAlertTests: 77 checks passed`; the `2cc0415` commit message figure (74) predates later additions.
- **Not done:** no push and no release. The first real launch and migration on the owner's machine is parked by the owner.

## Follow-up implementation pass (2026-10-10, integration branch impl/followup-20261010, not merged to main)

Full record: [followup-implementation.md](followup-implementation.md) (version 3, final for this pass). Baseline `7fef2a8`, integration head `718f601` (later `1ac6674`, with the mirror fix). Nothing pushed, tagged, released or installed.

- **Scope.** The owner's go-ahead on 2026-10-10 covered the History text and glass-button request and the remaining actionable audit code issues.
- **Package 1, History glass buttons and text** (`72f77a9`). Seven `HistoryActionButton`s on three glass plates in one container. Unit tests, and rendered captures only. No real-input result.
- **Harness package** (`770b6c0`). The S43 Delete from Web lookup walks the glass plates again, closing the Package 1 open item. New rendered S20 captures for action hover, pressed and focus. Rendered only.
- **Package 2, behaviour defects** (`210e80e`). FS-A, FS-B and FS-C fixed, each with a test that fails on `7fef2a8`. F-J4-006 fixed by earlier code, guarded by `fuHistoryOpenShowsNewSize`. F-J1-023 not reproduced headless, guarded by `fuTextEditorAccessibility`. F-J3-009 / R1-016 and R1-021 / F-J4-007 left unchanged, with reasons.
- **Real-input check, F-J1-023** (E2E class, isolated session `com.shoemoney.opensnap.e2e-83132`, synthetic text). The AX text area was read and its selection was set and honoured by a real Delete key. The session stores were unchanged. Unresolved: an untargeted type inserted at the driver's pointer position, not over the selection. VoiceOver speech unproved.
- **Integrated checks at `210e80e`.** Cold `tools/build.sh` PASS. Full `tools/test.py` run 1 PASS: app safety 257/257, native AppKit idle termination PASS, real-store guard unchanged.
- **Independent review of `7fef2a8..210e80e`.** FR-1 (P2, confirmed): a window can be oversized when leaving full screen during Actual Size. FR-2 (P2, plausible): the FS-B and FS-C window restore may be lost if AppKit restores its frame later in the exit. FR-3 (P3, confirmed): the FS-A Cancel branch lacks a generation check. FR-4 (P3, plausible): History plates are not accessibility elements. Correction round done, see the next three bullets.
- **Review corrections, `4a0043f` (merged `718f601`).** FR-1 fixed: with Actual Size still up, the full-screen exit leaves the window alone, and the saved frame is applied when Actual Size ends, staying within the screen. FR-2 fixed, simulated handler order only: window records survive the first resize, and `finishFullScreenExit()` on did-exit repeats the work. FR-3 fixed: the Cancel branch takes the zoom only from a record of the same document. FR-4 fixed: the History plates are accessibility groups. Each has a test that fails without its fix (section 7 of the record).
- **Final gates at `718f601`.** Cold `tools/build.sh` PASS (`/tmp/fu-int-build2.log`). Full `tools/test.py` PASS (`/tmp/fu-int-test2.log`): all suites on arm64 with no source drift, app safety 262/262, native AppKit idle termination PASS, real-store guard unchanged. The root's final guarded renders at `718f601` (S20, S43 and the core set) found no material layout defect, with stores unchanged and the input fence at zero. The `210e80e` run (257/257) stays as the earlier run.
- **Finding index totals on this branch.** The index rows give 160 IDs: 130 fixed, 18 partial, 1 deferred, 3 open, 5 gap, 2 accepted trade-off and 1 doc-only. With R6-001 and R6-002 (fixed in batch 13, recorded in `e2e/findings.md` only, with no index rows), that is 162 IDs and 132 fixed. Compared with the earlier "162 IDs, 131 fixed" line, F-J4-006 moved from open to fixed and F-J1-023 from deferred to partial. The index does not count FS-A, FS-B or FS-C (unnumbered pre-existing gaps) or FR-1 to FR-4 (follow-up review IDs in `e2e/findings.md`). The "Totals by status" table above (129 fixed, 17 partial, 2 deferred, 4 open, 160 in all) and the "Final root handoff" line are kept as snapshots of the earlier candidate.
- **Mirror case, after the final candidate** (`3976ac0`, merged `1ac6674`). Full screen entered with the Resize sheet up, then Cancel, was left unfitted; now it fits, and the way out keeps the windowed frame. Test `fuCancelResizeAfterFullScreenEntry` fails with the fix reverted and passes with it; headless app-safety 263/263. Simulated handler order only. Final candidate hashes and the final full-suite result after this fix are reported in the task hand-off.
- **Coverage.** No coverage-matrix row changed in this pass, and the coverage-summary counts are unchanged. Nothing was added to "Merges to main, in order", because nothing has merged to main. The final candidate hashes and the final full-suite result are in section 6 of the record.

## Final root handoff

See [final-verification.md](e2e/final-verification.md) for completed gates, the local history rewrite, refreshed default Free-icon renders and remaining limits. The earlier 160-ID totals exclude R6-001/R6-002; the current finding index has 162 IDs, 131 fixed, with the other status totals unchanged. This is a local candidate with a partial E2E matrix.

Final root packaging checks: both fresh evidence packs pass `check-eye-dump.py` (90 PNGs; no hard failures or advisories; 20 core contrast samples skipped). The offline gallery interaction checks pass; previews at 728px/light and 360px/dark have no readable text below 18px and no page overflow. The temporary private-history backup and derived private OCR files created for the scrub were removed after integrity and blob-absence verification. The private commit map remains in `.git/`.

### Follow-up root integration and render review — 2026-10-10

The follow-up candidate `b6b6b2e` is now integrated into local main. Sources/tests/tools match tested `1ac6674` (full suite passed; app-safety 263/263; native idle termination and unchanged real-store guard passed). Root rebuilt the app and captured 76 History/action/accessibility frames, reviewing representative minimum-width, wide, state and accessibility layouts at `718f601`, whose History source is unchanged in final main, plus 12 final-source editor/Resize/full-screen layout frames at `b6b6b2e`. All three guarded runs had no capture gaps and unchanged real stores. The current result is [follow-up root verification](e2e/followup-root-verification.md); manual/hardware and first real launch/migration/release remain open. The older branch-only statements above are snapshots before this local integration.
