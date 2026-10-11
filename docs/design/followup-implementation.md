# Follow-up implementation record — History glass pass and open behaviour fixes

> Status: initial version, 2026-10-10. Package 1 is done and merged on the integration branch. Package 2 is in progress. Its results, the integrated test results and the review outcome will be added in the next revision.

## 1. Scope and authorization

On 2026-10-10 the owner replied "great job lets implement changes" to the close-out in [final verification](e2e/final-verification.md). That reply authorized two things:

- the History text and glass-button request in `QUEUE.md`. It was raised on 2026-10-09 21:33 CDT and activated on 2026-10-10 19:23 CDT. Until then the final verification recorded it as deliberately not activated;
- the remaining actionable code issues from the audit. Those are listed in section 3.

| Item | Value |
|---|---|
| Baseline | `7fef2a8` (`docs: package final OpenSnap gallery and verification limits`) |
| Integration branch | `impl/followup-20261010` (integration worktree `.todo-worktrees/followup-integration`) |
| Worker branches | `impl/fu-history` (Package 1), `impl/fu-behavior` (Package 2) |
| This record | `docs/followup-implementation`, one new file: `docs/design/followup-implementation.md` |

Nothing in this pass has been pushed, tagged, released or installed. The app is still `build/OpenSnap.app`, and the folder is still `OpenSkitch`.

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
| Actions | Each of the seven actions is a `HistoryActionButton` (a `CommandButton` subclass) with a Font Awesome glyph and a 20 pt label. Hide keeps the folder-minus glyph. |
| Glass | One `GlassChrome.container` ("HistoryActionBar") holds three `GlassChrome.plate`s: Open + Copy; Copy Link + Open Link; Hide + Trash + Delete from Web at the trailing edge, at least 24 pt from the link plate. These are the only glass elements in the window. There is no glass on glass, and none over the grid, tiles or details. |
| Layout | The bar is one 44 pt row, like the editor header. The grid and details panel are unchanged. |
| Labels | Same measured collapse rule as before. All labels show at 1000 pt wide. At the 880 minimum only the three destructive actions keep labels. Text stays 20 pt. |
| States | Hover and pressed fills sit on the button. The focus ring follows the button shape. Disabled actions stay in place, dimmed to the shared 0.38 alpha. Disabled actions have no key equivalent and are not the default button. Return in the grid still opens. |
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
| All History text at least 18 pt, with light and dark contrast (4 tests) | 14 pt label font |

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

These stay open in this version:

1. The S43 harness capture `history-delete-web-disabled` in `Sources/EyeDumpAuditSurfacesBatch3c.swift` still looks up Delete from Web the old way. It would record a gap instead of a capture.
2. `tools/eye-dump-audit-docs.py` refers to older HistoryBrowser strings. This staleness predates this pass.
3. Disabled plates look pale in light mode, because of the shared 0.38 alpha.

## 3. Package 2 — Remaining behaviour defects

Status: **in progress**. The table below will be completed in the next revision.

Source for the first three rows: the section "Pre-existing, unchanged by batches 11–13" in [findings](e2e/findings.md) (around line 1371), recorded after review round 6. The wording here is a summary; the findings file is the authority.

| ID | Defect | Result |
|---|---|---|
| A | Leaving full screen while the Resize sheet is up, then Cancel, puts full screen's zoom and frame back on the normal window. | in progress |
| B | After a size change made in full screen, leaving full screen resizes the window only if the zoom changed. | in progress |
| C | The Actual Size navigator nudge, when full screen is entered during Actual Size, can leave the window up to about 175 pt narrower than its canvas. | in progress |
| F-J4-006 | A freshly opened History entry shows the previous document's size for a moment (title and status line after History › Open). | in progress |
| F-J1-023 | The text editor exposes no settable AX selection (`AXSelectedTextRange` cannot be set on the in-place editor). Planned fix: an `NSTextView` with standard accessibility. | in progress |
| F-J3-009 / R1-016 (optional, bounded) | Small-canvas and navigator column space. Only if a bounded change is possible. | in progress, optional |
| R1-021 / F-J4-007 (design trade-off) | Eraser drops the shadow from the rest of a cut shape. Left unchanged unless a purely visual local fix exists. The stored format and semantics do not change. | recorded trade-off; no change planned |

## 4. Verification plan and honest limits

### Plan

1. Integrated cold build on the integration tree, after the sources stop changing.
2. One full `python3 tools/test.py` run on the integration tree, after the same point.
3. One independent code review, with at most one correction round.
4. A final guarded render review by the root.

Real-store hashes must be unchanged for every run. The guarded harness is the only route used for captures.

### Not proved by this pass

- spoken VoiceOver;
- live Screen Recording capture;
- multiple displays and 1x displays;
- held-modifier gestures;
- real AX client selection. The unit tests use the `NSAccessibility` protocol only, not a real assistive client;
- the live full-screen transition sequence on screen.

Passing unit tests and harness captures do not close any of these.

## 5. Status

This version: Package 1 is done and merged to the integration branch as `72f77a9`. Package 2 is in progress. Package 2 results, integrated test results and the review outcome will be added in the next revision.
