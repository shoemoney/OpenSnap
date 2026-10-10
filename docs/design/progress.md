# OpenSnap implementation progress

**Baseline:** `bad6617`, when implementation began (the rename and migration were already merged in `f7ff86b` and `d2dc3c9`).
**Main now:** `f3ba77f`, after six merges.
**Status of 36 todos:** 20 done, 2 verified, 1 not-a-bug, 1 in-progress (OSN-041), 12 pending.

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
| OSN-050 | done | `f3ba77f` (`75a9ee6` to `b9a0f24`) | `08f03e5` tightened checks (no count) | `m5-capture`, 38 at `8a0e8d9` |
| OSN-052 | done | `f484d3e` (`3be3870`, `26e2160`, `708b6bd`, `dd17d50`) | harness variants in `708b6bd` (no count) | n/a |
| OSN-053 | done | `f484d3e` (`3be3870`, `26e2160`, `708b6bd`) | harness History variants in `708b6bd` (no count) | n/a |
| OSN-055 | done | `77bad0c` (`51e37a9`) | menu parity tests | n/a |
| OSN-056 | done | `f3ba77f` (`8a9af59`) | none recorded | `m5-capture` (hint plate clear of title bar and bars) |
| OSN-057 | not-a-bug | `8df7780` (`13c032c`) | regression test in `13c032c` | n/a |
| OSN-058 | done | `8df7780` (`0ed44b4`, `fac0cc7`) | none recorded | n/a |

Suite counts are the ones the sources record. No other counts are claimed.

## OSN-043 and OSN-041 step 5 (branch `impl/m4-window`, not merged)

Unified window chrome and app-owned alerts. Evidence: `evidence/impl-2026-10-09/m4-window/` (50 captures, source `7bf20f8`).

**Decisions**

- **Titlebar stays separate** (orchestrator). A full-size-content title bar would cost about 78 pt beside the traffic lights and break the 980 Frame fit (16 pt slack). Measured result: `titlebarSeparatorStyle = .none` plus the surface window colour was not enough (the opaque title bar is 41/40/39 over a 30/30/30 window in dark, with a 1 pt line), so the title bar is transparent outside Frame mode and opaque again inside it; no layout cost. Title and subtitle text are system-drawn (OS limit).
- **Frame and full screen exclude each other by refusal.** Entering Frame in full screen shows "Exit full screen to use Frame"; while Frame is up the window drops `.fullScreenPrimary`; a stray full-screen entry ends Frame. Refusing was chosen over "exit full screen first" because `toggleFullScreen` is an animated, cancellable transition, so entering Frame afterwards needs a deferred state machine with several failure modes, and Frame is a see-through window over the desktop, which a full-screen Space cannot show.
- **Minimum height stays 640** (608 content), not T8's 680; width is measured from the live bars, floored at 980.
- **Sheets, not modals,** for every document-scoped question. A question from New, Open or a capture is single at a time (a sheet does not stop the menu bar); Quit may always ask, stacks on the open sheet, and answers AppKit later through `reply(toApplicationShouldTerminate:)`. A hidden or minimised editor cannot carry a sheet, so the alert is a panel of its own and Quit never waits on an unseen question.
- The save panel names the document: a file the user just named in Save As becomes the document's name and title. Saving in place keeps the name.
- The Discard button is now "Don’t Save" (Command-D, destructive styling), as macOS words it.

**Alert sites converted** (all in `App.swift`, now `AppAlert` sheets): `error(_:)` (every open, save, export, upload, capture and history failure), `confirmDiscard` (was `allowDiscard`, used by New, Open, captures, Frame completion and Quit), `removeHistory` (Hide, Move to Trash), `deleteHistoryRemote` (Delete from Web), and `prompt` (Rename, Timed Snapshot, Snap from Link). `NSOpenPanel`, `NSSavePanel`, the export panel and `NSPageLayout` stay system modals. Left to the other worker: `PublishingDestinationsView.swift` (remove-destination confirmation).

**OS-owned limitations:** Save, Open, Export and Page Setup panels (their accessories are already 20 pt); the title-bar title and subtitle; traffic-light tooltips.

**Tests:** app-safety 166 (154 before; 12 new window-chrome cases, one existing Frame-prompt case changed on purpose: the Discard prompt is now a sheet on the Frame window, so it no longer runs with the pre-Frame level), `AppAlertTests` 77 checks, `GlassChromeTests` 13544 checks. Twelve can-fail mutations each fail the suite that should catch them and were reverted.

## Open items and gaps

- **Unsafe tool still on main:** `tools/test-native-startup.py` launches the real bundle id in place. The fix is in progress on `impl/m4-type`. Do not run it until that is merged.
- **Round-1 incident (OSN-001):** a can-fail proof deleted the owner's real `com.shoemoney.opensnap` defaults plist. Cause: a cleanup trap was installed before an id refusal. Fixed in `db973a6`. The SkitchRedux store and `com.shoemoney.skitch-redux.plist` hashed unchanged. The migration marker is a file in the absent OpenSnap folder, so the parked migration is unaffected.
- **OSN-042 (branch `impl/m4-glass`):** the phantom capsule under Snap and the full-screen salmon tint are gone (no per-button glass, no backdrop or bleed). The legacy-scroller corner is no longer white but is 250/255 against the well's 246/255 (AppKit draws it); open. Evidence: `evidence/impl-2026-10-09/m4-glass/`.
- **Size popover** can overhang the window edge. It stays on screen and is accepted as standard NSPopover behaviour.
- **Canvas centring** was a pre-existing bug, also present at `bad6617`. It is fixed for document changes in the rail-removal branch (`c53155c`).
- **Q3 resolved: option B (custom bars).** Spike: an `NSToolbar` with the top-bar items shows 14 of 17 at 980 pt (14 of 18 in Frame mode) and needs 1060 pt (1120 in Frame mode) to show all. The glass budget is 8 plates in 2 containers (was 26 in 7).
- **Settings** window is still titled "Preferences" (OSN-051).
- **Not run:** live screen capture; real popover translucency; VoiceOver speech (OSN-062 manual pass); Reduce Transparency alone and Increase Contrast alone captures (both together are in `m4-glass`); FA Pro icon mode.
- **OS-owned text (D-TEXT):** menu-bar strip titles, window title-bar text, system tooltips inside system panels, NSAlert text size, Save, Open and Print panels, Fonts and Colors panels.
- **OSN-023:** manual 1x and 2x menu-bar check not done.
- **OSN-041 in progress:** chrome, App, Resize, Photos, TextStyle, Hotkeys, Export and the 20 pt tooltips remain. The worker on `impl/m4-type` is not merged.
- **OSN-070:** the gates beyond the four on main (`check-no-original.py`, `check-clean-clone.sh`, `check-brand.py`, `check-tokens.py`) are not recorded as landed.
- **OSN-072:** migration on a copy of the owner's real store is not authorized in this run. Synthetic temp stores only.
- **Not done:** no push and no release. The first real launch and migration on the owner's machine is parked by the owner.
