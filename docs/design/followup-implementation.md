# Follow-up implementation record — History glass pass and open behaviour fixes

> Status: version 3, 2026-10-10, **final for this pass**. All four packages are merged on the integration branch, the independent review's four items (FR-1 to FR-4) are fixed, and the final candidate is `718f601`. Integrated gates passed at `718f601`. Nothing is on `main`. After version 3, the mirror case (Resize sheet up, enter full screen, Cancel) was fixed: `3976ac0`, merged as `1ac6674` (section 4).

## 1. Scope and authorization

On 2026-10-10 the owner replied "great job lets implement changes" to the close-out in [final verification](e2e/final-verification.md). That reply authorized two things:

- the History text and glass-button request in `QUEUE.md`. It was raised on 2026-10-09 21:33 CDT and activated on 2026-10-10 19:23 CDT. Until then the final verification recorded it as deliberately not activated;
- the remaining actionable code issues from the audit. Those are listed in section 4.

| Item | Value |
|---|---|
| Baseline | `7fef2a8` (`docs: package final OpenSnap gallery and verification limits`) |
| Integration branch | `impl/followup-20261010` (integration worktree `.todo-worktrees/followup-integration`), final candidate head `718f601` (section 6) |
| Worker branches | `impl/fu-history` (Package 1), `impl/fu-harness` (harness package), `impl/fu-behavior` (Package 2) |
| This record | `docs/followup-implementation`, one file: `docs/design/followup-implementation.md` |

Nothing in this pass has been pushed, tagged, released or installed. The app is still `build/OpenSnap.app`, and the folder is still `OpenSkitch`. None of the commits below is on `main`.

## 2. Package 1 — History glass buttons and text

Status: **done**. Merged into the integration branch as `72f77a9`. Worker commits: `e423bfc` (feat), `c389327` (test), `2505c73` (test). Five files, +326/−50:

- `Sources/HistoryBrowser.swift`
- `tests/HistoryBrowserTests.swift`
- `tests/AppSafetyS3EndToEndCases.swift`
- `tools/test.py`
- `docs/design/e2e/inventory.json`

### What changed

| Area | Result |
|---|---|
| Actions | Each of the seven actions is a `HistoryActionButton` (a `CommandButton` subclass) with a Font Awesome glyph and a label drawn at 20 pt. Hide keeps the folder-minus glyph. |
| Glass | One `GlassChrome.container` ("HistoryActionBar") holds three `GlassChrome.plate`s: Open + Copy; Copy Link + Open Link; Hide + Trash + Delete from Web at the trailing edge, at least 24 pt from the link plate. These are the only glass elements in the window. There is no glass on glass, and none over the grid, tiles or details. |
| Layout | The bar is one 44 pt row, like the editor header. The grid and details panel are unchanged. |
| Labels | Same measured collapse rule as before. All labels show at 1000 pt wide. At the 880 minimum only the three destructive actions keep labels. Action labels stay at 20 pt. |
| States | Hover and pressed fills sit on the button. The focus ring follows the button shape. Disabled actions stay in place, dimmed to the shared 0.38 alpha. No action has a key equivalent, and there is no default button. Return in the grid still opens. |
| Keyboard | Tab follows reading order: filters, plates, grid. The window recalculates its key-view loop to do this. Reaching the buttons with Tab needs Full Keyboard Access or Focus Toolbar, as for every `CommandButton`. |
| Clear filters | A single accent-filled button with the xmark-circle glyph. The no-match state adds the hint "Try a different search, tab or date." |
| Text hierarchy | Details labels use secondary text and values use primary. Day headers and the summary use explicit semantic colours. |
| Tooltips | Still app-owned. `AppToolTip` adopts `button.toolTip`. |
| Filter row | The segmented control, search field and date pop-up stay native AppKit on purpose. The system controls already carry the macOS 26 look, and putting them on glass risked glass on glass. |

### Tests

Added in `tests/HistoryBrowserTests.swift`. Each one was shown able to fail by applying a deliberate regression to a scratch copy outside the repository:

| Test | Regression that made it fail |
|---|---|
| Actions are `CommandButton`s on three named plates in one container | Hide moved out of the removal plate |
| No glass inside glass or over content | An extra nested `NSGlassEffectView` |
| Disabled actions stay in place and legible | Disabled buttons hidden |
| Tab reaches all seven in order, with no default button | `keyEquivalent` "\r" on Hide; a button removed as a key view |
| Clear filters is a primary accent button | Primary fill removed |
| App-drawn History text at least 18 pt (labels 20 pt), with light and dark contrast (4 tests). The native title bar is excluded: it is OS-owned at the system default size, about 13 pt | 14 pt label font |

Two notes on the test set:

- One state-fill test (rest, hover, focus and disabled, per action) has **no can-fail proof**. It is unit-tested only.
- The new tests reference the new API. They cannot run against the old code; they fail to compile there. That is expected and is not a regression proof.

Three existing History assertions were updated because the controls moved: buttons are found through their plates, font checks read the drawn attributed size, and the no-match hint is now shown.

### Worker checks

| Check | Result |
|---|---|
| `history-browser-tests` | 48/48 pass |
| `view-tree-audit-tests`, `accessibility-audit-tests` | pass (91 and 178 checks) |
| `check-tokens` | no hits in `HistoryBrowser.swift` |
| `check-tooltips`, `check-glyphs`, `e2e-inventory.py --check` | pass |
| Build | pass |
| `tools/test-app-safety.sh` | 252/252 pass, after the S3 end-to-end case was updated |
| Guarded harness `eye-dump-audit.sh --surfaces S20 --appearances light,dark` | exit 0; `RESULT stores unchanged` |

The captures are harness-rendered states at 880×600, 1120×850 and 1280×800 (selected); 880 with none selected; empty; no match; tile hover; light and dark. They are kept outside the repository. The final render review is done separately, by the root.

**Evidence level.** These are unit and headless tests plus harness-rendered captures. They are not real end-to-end input coverage, and they do not upgrade any row in the coverage matrix. Hover and keyboard focus on an action button, and the Increase Contrast and Reduce Transparency variants, are unit-tested only. They have no capture.

### Open follow-ups from Package 1

| # | Item | Status after this pass |
|---|---|---|
| 1 | The S43 harness capture `history-delete-web-disabled` in `Sources/EyeDumpAuditSurfacesBatch3c.swift` looked up Delete from Web the old way, and would have recorded a gap. | **Fixed** by `770b6c0` (section 3). |
| 2 | `tools/eye-dump-audit-docs.py` refers to older HistoryBrowser strings. This staleness predates this pass. | Open. Not touched. |
| 3 | Disabled plates look pale in light mode, because of the shared 0.38 alpha. | Open. Not touched. |

## 3. Harness package — `impl/fu-harness`

Status: **done**. Branch commit `b8d1860`, merged into the integration branch as `770b6c0`.

| Area | Result |
|---|---|
| S43 lookup | The Delete from Web lookup walks the glass plates again. `history-delete-web-disabled` captures, and there is no gap. Closes Package 1 open item 1. |
| S20 captures | New rendered captures `history-action-hover`, `history-action-pressed` and `history-action-focus`, in light and dark. They are driven through the buttons' own APIs. |
| Inventory | `inventory.json` gets one note line: the `.copy` icon is used in `EyeDumpAuditSurfaces.swift`. |

Checks: `e2e-inventory.py --check` passes. The guarded harness `--surfaces S20,S43` exits 0 with `gaps: []` and `RESULT stores unchanged`.

**Evidence level.** Rendered states only. The hover, pressed and focus captures do not show a real hover, a real press or a real Tab press. They are not real-input E2E.

## 4. Package 2 — Remaining behaviour defects

Status: **done** on the worker branch, merged into the integration branch as `210e80e`. Worker commit `719735d`, 6 files, +224/−8:

- `Sources/App.swift`
- `Sources/App+FullScreen.swift`
- `Sources/AppViewport.swift`
- `tests/AppSafetyFollowupCases.swift` (new)
- `tests/AppSafetyTests.swift` (registration)
- `tools/test-app-safety.sh` (registration)

Each "red before" note was measured on the baseline `7fef2a8` through the real paths.

| ID | Defect | Result | Fix and test |
|---|---|---|---|
| FS-A | Leaving full screen with the Resize sheet up, then Cancel, put full screen's zoom and frame back on the normal window. Repro: zoom 1.6585714285714286 against an expected 1.0, and a 2056×1329 frame. Cause: Cancel restored the zoom and frame captured at the first preview, in `AppViewport.swift` onFinish. | **fixed** | The baseline records whether the sheet opened in full screen. A Cancel after full screen ended restores the picture, puts back the pre-full-screen zoom, and sizes the normal window for the restored picture. `fuCancelResizeAfterFullScreenExit` (red before: zoom 1.6586 against 1.0). |
| FS-B | After a size change made in full screen, the window was resized on exit only if the zoom changed. | **fixed** | `fullScreenEntryOutput` remembers the picture size at entry. On the way out the window is also resized if that size differs. `fuWindowFollowsSizeChangeMadeInFullScreen` (red before: viewport 956 for a 1000-wide picture). |
| FS-C | Actual Size navigator nudge across full screen could leave the window narrower than its canvas (up to about 175 pt). Trigger: Actual Size begun windowed, full screen entered, Actual Size left inside full screen. `leaveActualSize`'s full-screen branch never restored the pre-nudge frame, so AppKit restored the nudged frame on exit. | **fixed** | `fullScreenWindowedFrame` holds the frame Actual Size began with, and the exit puts it back. `fuWindowAfterNudgeAndFullScreen` (red before: viewport 1857 for a 1936 canvas). |
| F-J4-006 | A freshly opened History entry showed the previous document's size for a moment (title, label and footer, after History › Open). | **fixed** by earlier code. No source change in this package. | `refreshStatusText` calls `syncDragSizeText()` first, so title, label and footer are rewritten synchronously on open. `b4SizeTextOnOpen` already covered the plain path. Regression guard `fuHistoryOpenShowsNewSize` covers Don't Save and clean paths × PNG/JPG, and the full-screen footer. It passes on the baseline, so it is a guard, not a red test. Can-fail proof: removing the `syncDragSizeText()` call in a scratch copy made it and `b4SizeTextOnOpen` fail ("400 × 300 · PNG" where "940 × 600 · PNG" was expected). The J4 retest had this row PARTIAL; no real-input re-run of this path was made on `210e80e`. F-J6-005 (title lag after the Original size checkbox) is a separate finding and is not changed here. |
| F-J1-023 | The text editor exposed no settable AX selection. | **not reproduced** headless. Real-input check in section 5. | Through the `NSAccessibility` protocol, the editor is a standard `AXTextArea` labelled "Annotation text", with a readable value and a readable and settable `AXSelectedTextRange`. Guard test `fuTextEditorAccessibility` passes on the baseline. Can-fail proof: `setAccessibilityElement(false)` in a scratch copy fails it. |
| F-J3-009 / R1-016 | Small-canvas and Actual Size navigator column space. | **left unchanged** | The only small candidate, "fit up to 200%", changes zoom semantics broadly. The navigator panel is already sized to its content, so the empty column comes with tall documents. |
| R1-021 / F-J4-007 | Eraser drops the shadow from the rest of a cut shape. | **left unchanged** | Recorded design trade-off. No stored format or semantics change. |

Worker checks: app-safety 257/257; build, `check-tokens` and `check-tooltips` pass; real-store guard "stores unchanged" (digest `dbde037ac2085108`).

### Mirror case: Resize sheet up, enter full screen, Cancel (fixed after version 3)

Status: **fixed**. Worker commit `3976ac0` (branch `impl/fu-mirror-cancel`), merged into the integration branch as `1ac6674`. Two files, +47: `Sources/AppViewport.swift` +11, `tests/AppSafetyFollowupCases.swift` +36. This is the mirror of FS-A. Version 3 recorded it as an adjacent gap that the reviewer judged unchanged and harmless; that judgement is withdrawn.

Cause, confirmed in source: while a Resize session is active, `fitDrawingForFullScreen()` returns early, so full screen never fitted the drawing and `fullScreenZoom` stayed nil. Cancel then took the plain windowed branch, which put back the windowed zoom with no full-screen record. (`setWindowFrame` already refuses to move a full-screen window, so the windowed frame was never applied.)

Fix: a new Cancel branch, placed before the plain Cancel, for "sheet opened windowed, now in full screen". It puts back the pre-sheet zoom and fit record, clears the stale full-screen records, fits the restored drawing to the Space the way a normal entry would (so `fullScreenZoom.before` is the pre-sheet zoom), keeps the pre-sheet window frame for the way out (as FS-C does), and restores the dirty and edited state. The other branches are unchanged.

Test `fuCancelResizeAfterFullScreenEntry`: preview 1600 wide in a window, enter full screen with the sheet up, Cancel, then leave full screen. It asserts the picture and title size are restored, the full-screen frame is kept, the zoom is the Space's fit with `before` equal to the pre-sheet zoom, and on exit the pre-sheet zoom and windowed frame are back and the window holds the canvas.

Red proof: with the fix reverted in a scratch copy, it fails with "The restored drawing is fitted to the Space, not left at the windowed 1.0 (1.0)". Green with the fix. Headless app-safety suite 263/263; build passed. Limit: simulated full-screen handler order only, not a live transition.

## 5. Real-input check of F-J1-023 (E2E class)

Evidence class: **real input**, the same class as the audit's E2E rows. It is not a unit test and not a harness render. It ran with the computer-use driver, in an isolated copy of the app made by `tools/e2e-session.sh`.

| Setting | Value |
|---|---|
| Build | `impl/followup-20261010` at `210e80e` (tree `15ff0f3e472ebfd5e567d46cefecdd34a304526e`) |
| Session | `com.shoemoney.opensnap.e2e-83132` (pid 83150), `--seed empty`, synthetic text only |
| Driver input | Background, targeted input (as recorded in the log) |
| Log | `/tmp/fu-fj1023-e2e.md` |

| Step | Result |
|---|---|
| Text tool, click on the canvas, type "Hello OpenSnap check" | The AX tree shows `AXTextArea` = "Hello OpenSnap check", focused, as a child of the canvas `AXScrollArea`. |
| `select_text` "OpenSnap" | Accepted, selected text "OpenSnap". No −25205 error. The `AXSelectedTextRange` set was honoured. |
| Untargeted `type_text` "Synthetic" (after the selection) | The value became "Hello OpenSyntheticSnap check". The text went in at offset 10, not over the selection. See the oddity below. |
| `select_text` "Synthetic" | Accepted. The crop screenshot shows "Synthetic" highlighted. |
| Real Delete key | The value became "Hello OpenSnap check". Exactly the selected "Synthetic" was removed, so the AX-set selection was honoured by a key edit. |
| `stop` | `RESULT stores unchanged` (digest `dbde037ac2085108` before and after). Session removed. |

**Oddity, unresolved.** An untargeted `type_text` "Synthetic" issued after a selection inserted the text at the driver's pointer position (offset 10, giving "Hello OpenSyntheticSnap check"). It did not replace the selection. It is not yet known whether this is the driver's input route or the app's handling of insertion. It is recorded here and not explained.

**Not covered.** VoiceOver speech remains unproved. The check does not show that an assistive client announces the editor.

**Structural notes, left unchanged on purpose.** The canvas has a role and a label but is not an accessibility element, so the editor hangs off the scroll area. The "Move annotation text" grip is not exposed.

## 6. Final candidate and integrated gates

### Final candidate

| Item | Value |
|---|---|
| Branch | `impl/followup-20261010` |
| HEAD | `718f601293133933f5746581c711f8064999a368` |
| Tree | `685c4ea08ee9a65385201584b34d56900c230ba1` |
| Merge order | `72f77a9` (History), `1974325` (record v1), `770b6c0` (harness), `210e80e` (behaviour), `0cbd2b4` (record v2 and ledger rows), `718f601` (review corrections, from `4a0043f`) |

Nothing has been pushed, tagged, released or installed. `main` is unchanged. Final candidate hashes and the final full-suite result after the mirror fix (section 4) are reported in the task hand-off.

### Gates at `718f601`

| Check | Result | Log |
|---|---|---|
| Cold `tools/build.sh` | PASS | `/tmp/fu-int-build2.log` (exit 0; five compiler warnings, no errors) |
| Full `python3 tools/test.py` | PASS. All suites on arm64 with no source drift. App safety 262/262. Native AppKit idle termination PASS. Real-store guard unchanged: 122 files in 2 real-store folders and 2 defaults files, throwaway preference plists 0 before and 0 after. | `/tmp/fu-int-test2.log` |

Root's final guarded renders at `718f601` (S20 and S43, and its core set): no material layout defect found. Stores unchanged. Input fence at zero.

### Earlier run at `210e80e`

Run after the Package 2 merge, before the review correction round. Kept for the record.

| Check | Result | Log |
|---|---|---|
| Cold `tools/build.sh` | PASS | `/tmp/fu-int-build.log` |
| Full `python3 tools/test.py`, run 1 | PASS. All suites passed on arm64 with no source drift. App safety 257/257. Native AppKit idle termination PASS. Real-store guard unchanged (122 files in 2 real-store folders and 2 defaults files). | `/tmp/fu-int-test1.log` |

## 7. Independent review of `7fef2a8..210e80e`

One focused review, then one correction round (`4a0043f`, merged as `718f601`). No further round is planned in this pass.

| ID | Sev | Finding | Status |
|---|---|---|---|
| FR-1 | P2, confirmed | Leaving full screen during Actual Size could leave the window oversized, bigger than the screen. | **Fixed** in `4a0043f`. The full-screen exit's window work runs only when Actual Size is off. With Actual Size up, the saved frame waits, and `leaveActualSize`'s windowed branch applies it and resizes the window once the zoom refits. Tests: `fuActualSizeStillUpOnTheWayOut`, `fuActualSizeReenteredInFullScreen`, and `b13StaleFullScreenZoom`, which now also bounds the window to the visible frame. Can-fail: with the fix reverted the window came out 6044×1968 on a 2056×1197 screen. |
| FR-2 | P2, plausible (live) | FS-B and FS-C window records were cleared on the first resize out of full screen, so a late AppKit frame restore would undo the fix. | **Fixed (simulated handler order only).** The records are kept through the first resize. The new `finishFullScreenExit()`, called from `windowDidExitFullScreen`, repeats the window work idempotently and then clears them, unless Actual Size is up. Records are cleared at a new full-screen entry and generation-guarded. Tests: `fuNarrowFrameAfterFirstResizeOut`, `fuStaleWindowRecordsDoNotLeak`. Can-fail: the reverted fix gave viewport 1857 for a 1936 canvas. The live full-screen transition has not been run. |
| FR-3 | P3, confirmed | The FS-A Cancel branch took the full-screen zoom record without a generation check and fell back to a fit, discarding a user zoom. | **Fixed** in `4a0043f`. Cancel takes the pre-full-screen zoom only from a record of the same document generation, otherwise `baseline.zoom`. The unconditional fit is gone. Test: `fuCancelResizeWithNewSnapInFullScreen`, in two variants. Can-fail: zoom 0.6 where 1.0 was expected. |
| FR-4 | P3, plausible | History plates were not accessibility elements, so VoiceOver would likely not announce the groups. | **Fixed** in `4a0043f`. The three plates are accessibility groups labelled "Open and copy", "Web link" and "Remove". Their buttons stay reachable. Test: the FR-4 case in `tests/HistoryBrowserTests.swift`. Can-fail: with the element flag removed the test fails (48/49). |

Correction-round checks: app-safety 262/262, history-browser-tests 49/49, accessibility-audit-tests 178 checks, build, `check-tokens`, `check-tooltips` and `e2e-inventory.py --check` pass. The History captures from the harness package predate this round. The correction does not change History rendering (FR-4 is accessibility only).

Checked and fine, per the reviewer:

- FS-A: the dirty and edited restore matches the existing Cancel. Apply clears the baseline.
- FS-A, FS-B and FS-C tests fail on `7fef2a8` for the right reason, through the real paths.
- History layout arithmetic (`actionBarWidth`) matches the real stack: all labels at 1000, destructive-only at 880.
- No title recursion. Observation closures are weak.
- Exactly three glass plates, none nested. No default button.
- Return, Escape, the context menu and the `AppToolTip` reasons are intact.
- The harness S20 resets state.

## 8. Verification plan and honest limits

### Plan

1. Integrated cold build on the integration tree, after the sources stop changing. Done at `718f601` (section 6).
2. One full `python3 tools/test.py` run on the same tree. Done at `718f601`; the `210e80e` run is kept as the earlier run.
3. One independent code review, with one correction round. Both are done (section 7).
4. A final guarded render review by the root. Done at `718f601`: no material layout defect (section 6).

Real-store hashes must be unchanged for every run. The guarded harness is the only route used for captures.

### Coverage matrix

- The History action rows in `coverage-matrix.md` keep their earlier E2E evidence, at their original source SHAs. Those SHAs predate the glass restyle, so that evidence describes the earlier look.
- The new History captures in section 3 are rendered-only. They add no E2E row.
- No coverage-matrix row was changed in this pass.

### Not proved by this pass

- **Live full-screen transition not exercised (FR-2).** The FR-2 fix is proved against simulated handler order only. The exit animation and AppKit's own frame restore have not run on screen.
- **VoiceOver speech unproved.** The accessibility checks use the `NSAccessibility` protocol and AX reads. No assistive client has been heard announcing the editor or the History plates.
- **Real hover, press and Tab on History not exercised.** The History action states (hover, pressed, focus, disabled) are rendered captures and unit tests only. No real pointer or key press was driven.
- **Mirror case fixed (`3976ac0`, merged `1ac6674`).** Full screen entered with the Resize sheet up, then Cancel, now fits the drawing and keeps the way out (section 4). Proved against simulated handler order only; the live transition has not been run.
- **F-J3-009 and R1-016 unchanged.** The only small candidate, "fit up to 200%", changes zoom semantics broadly. The navigator is already sized to its content.
- **R1-021 and F-J4-007 unchanged.** The eraser shadow on cut fragments is a recorded design trade-off. Changing it would change stored semantics.
- **Driver-pointer insertion oddity in the F-J1-023 real-input check.** An untargeted type after a selection landed at the driver's pointer position and did not replace the selection. Whether the cause is the driver's input route or the app's insertion handling is unresolved (section 5).
- Live Screen Recording capture; multiple displays and 1x displays; held-modifier gestures.
- F-J4-006 on the real display. No real-input re-run of the History open path was made on `718f601`.
- Real assistive-client selection beyond the single text-editor check in section 5.

Passing unit tests and harness captures do not close any of these.

## 9. Status

Version 3, **final for this pass**. Package 1 (`72f77a9`), the harness package (`770b6c0`) and Package 2 (`210e80e`) are merged to the integration branch. The independent review's four items (FR-1 to FR-4) are fixed in `4a0043f`, merged as `718f601`. The final candidate is `718f601`. Its cold build and full test run passed (section 6). The root's final guarded renders at `718f601` (S20, S43 and the core set) found no material layout defect, with stores unchanged and the input fence at zero. Nothing is pushed, tagged, released or installed, and `main` is unchanged.
