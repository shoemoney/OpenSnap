# OpenSnap implementation progress

**Baseline:** `bad6617`, when implementation began (the rename and migration were already merged in `f7ff86b` and `d2dc3c9`).
**Main now:** `658a16f`, after thirteen merges (six up to `f3ba77f`, then seven more).
**Status of 36 todos:** 24 done, 2 verified, 1 not-a-bug, 5 in-progress, 4 pending.

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

Merges 1 to 6 list the branch commits the orchestrator named. Merges 7 to 13 list the non-merge commits in git history for each branch. In both cases, merges of main into a branch are not listed.

## Issue to implementation to test to render

Each row is a todo that is done, verified, or not-a-bug. Commits in brackets are the branch commits that carry the work, attributed by commit subject. "Tested" gives only the counts the sources record. "Rendered" is the evidence folder under `docs/design/evidence/impl-2026-10-09/`; `n/a` means no rendered evidence is recorded for that todo.

| Todo | Status | Implemented (commit) | Tested | Rendered (evidence) |
|---|---|---|---|---|
| OSN-001 | done | `3431efc`; `9e9ec8c` retired `eye-dump.sh` | `tools/test-eye-dump-audit-guard.py`, 43 can-fail checks | n/a (tooling) |
| OSN-002 | done | decisions, no merge | n/a (decision record) | n/a |
| OSN-010 | done | `c53155c` (`891c197`, `ab4373d`, `4f164ef`, `2189f4a`) | app-safety 145/145; GlassChromeTests 13266 checks | `m1-rail` |
| OSN-011 | done | `c53155c` (`de7f511`) | same suites as OSN-010 | `m1-rail` |
| OSN-012 | done | `c53155c` (`b30ee32`, `356dde5`) | rail-removal regression suite; same suites | n/a |
| OSN-013 | done | `c53155c` (`f9bc0fc` to `e2db58c`) | 80-capture matrix, visual (no unit count); reviewed by Opus | `m1-rail`, 80 at `fef46c7` |
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

Todos that are in progress or partly landed:

| Todo | Status | Implemented (commit) | Tested | Rendered (evidence) |
|---|---|---|---|---|
| OSN-044 | in-progress | `impl/m4-states`, not merged; no branch SHA recorded in this pass | none recorded | none |
| OSN-051 | done | `e124f77` (integrated at `a79a1d8`) | SettingsWindowTests 1405; G4 0 violations; app-safety 166/166 | `m5-settings`, 36 at `a48d0df` |
| OSN-054 | pending | AWS validation only (see the AWS section); the upload UX is not built | one synthetic object through the app's S3 path, 2026-10-09 | none (validation recorded below) |
| OSN-061 | in-progress (part 1) | `accfedd` (`de21b6e`, `d0f8013`, `2dc613e`, `eaab72f`, `f975dfa`) | DisplayOptionsTests: 92 checks | none recorded |
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

## OSN-054, OSN-060 and OSN-062 (branch `impl/m5-upload-a11y`, not merged)

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

## AWS live validation (2026-10-09)

Owner-authorized, via root. Run at about 21:30 CDT on 2026-10-09.

- **Scope:** OpenSnap's own S3 code path, using the default AWS profile read in place. The credentials were never copied or printed.
- **Read-only check:** credentials and bucket verified.
- **Upload:** one synthetic object, `pics/opensnap-validation-20261009213258-19279.png` (74 bytes, `image/png`). The public CDN URL returned HTTP 200 with identical bytes.
- **Delete:** the object was removed through the app's delete path. S3 now returns 404 and CloudFront returns 403 for it.
- **Not touched:** no other object was read or changed. No IAM, infrastructure or CloudFront change was made.

Recorded as validation evidence under OSN-054 and OSN-072. It partly satisfies OSN-072's "AWS cdn upload dry run". OSN-054 stays pending, because the upload UX (progress, success, errors, announcements) is not built.

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
- **OSN-044:** `impl/m4-states` is not merged. No branch SHA is recorded in this pass.
- **OSN-061:** part 1 only is on main; the todo stays in-progress.
- **OSN-070:** not recorded as landed: G3 (`check-user-strings.py`), the dynamic Skitch-string check, and a layout-fit-at-980 gate beyond the measured-width test in `658a16f`. G5 and G9 are not further recorded in this pass.
- **OSN-072:** migration on a copy of the owner's real store is not authorized in this run. Synthetic temp stores only. The release work is a dry run only: no tag, push, upload or release.
- **OSN-054:** the AWS run is validation evidence only. The upload UX is not built.
- **Not run:** live screen capture; real popover translucency; VoiceOver speech (OSN-062 manual pass); Reduce Transparency alone and Increase Contrast alone captures (both together are in `m4-glass`); FA Pro icon mode; the OSN-071 visual gallery and Opus sign-off.
- **OSN-023:** manual 1x and 2x menu-bar check not done.
- **Alert check count reconciled:** the full integration run at `a79a1d8` prints `AppAlertTests: 77 checks passed`; the `2cc0415` commit message figure (74) predates later additions.
- **Not done:** no push and no release. The first real launch and migration on the owner's machine is parked by the owner.
