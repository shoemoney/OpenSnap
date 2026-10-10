# docs/design: index

Design docs for the OpenSnap visual and cosmetic audit (2026-10-09, final). Start with `roadmap.md` for the plan, then `todo-checklist.md` for the work items. `backlog.json` is the same work in machine-readable form. Implementation progress at main `3b453b3` (baseline `bad6617`) is in `progress.md`.

Open [audit-overview.html](audit-overview.html) for the self-contained interactive roadmap and evidence gallery: milestone filtering, task details, shortlisting, side-by-side comparisons, and downloads. It embeds ECharts and a selected set of ten evidence images, including placement mocks explicitly labelled as unimplemented. The full evidence set remains below. Viewer text was checked at 728 and 360 CSS px widths with an 18 px minimum; filtering, previews, shortlisting and comparison were exercised in the browser.

## Files

| File | Owner | Purpose |
|---|---|---|
| `README.md` | docs child C (round 2) | This index: files, evidence key, screenshot location, rerun commands, safety proof, coverage gaps, counts. |
| `roadmap.md` | docs child C (round 2) | Summary, drift, owner decisions, findings, milestones, lane and file ownership, estimates, gates, risks, outward-facing steps, source inconsistencies. |
| `todo-checklist.md` | docs child C (round 2) | One section per todo (36 todos, OSN-001 to OSN-072 as numbered in `visual-audit.md` section 9), in milestone order: main state, substeps, files, prerequisites, estimates, acceptance, visual checks with BEFORE stems, and tests. |
| `backlog.json` | docs child C (round 2), implementation update | The same backlog as JSON: `meta`, `decisions` (10), `milestones` (8), `todos` (36), `findings` (29). Each todo has a `status`, a `mainState` and an `implementation` block at `658a16f`. Each decision has a `resolution`. |
| `progress.md` | implementation docs writer | Implementation progress at `3b453b3`: baseline and merge map (18 merges), E2E audit (journeys, fix batches, finding resolution index, coverage, evidence index, gaps), todo to commit to test to evidence table, AWS live validation, OS-owned limitations, open items and gaps. |
| `visual-audit.md` | orchestrator | Source, read-only here. FINAL audit: summary, drift (section 0), coverage (section 5), findings VF-01 to VF-29 (section 6, with status at `dc1eb26` in 6.0), reconciliation (section 7), owner layout (section 8), backlog (section 9). |
| `technical-spec.md` | source and spec child B | Source, read-only here. Decisions Q1 to Q5 (section 0), implementation specs T1 to T15, file ownership map (section O). |
| `source-inventory.md` | source and spec child B | Source, read-only here. File and line inventory at `4b2ae0f`. |
| `user-feedback.md` | root (owner) | Source, read-only here. The owner's 10:24 CDT layout request and its acceptance checks. |
| `evidence/source-font-sizes.json` | source and spec child B | Source, read-only here. Font sizes by file and line. |
| `evidence/2026-10-09/` | evidence child A | Captures, metrics, AX dumps, menus, `manifest.json`, `captures.md`, `gaps.md`, `layout-width-budget.*`, `safety.txt`. See below. |

## Evidence classes

| Tag | Meaning |
|---|---|
| **R** observed | Seen in an app-owned rendered capture. The capture stem is cited. |
| **M** measured | Read from view-tree metrics, an AX dump, the layout budget, or a probe. The JSON or probe is cited. |
| **S** source-inferred | Read from code at `4b2ae0f` unless stated. Not seen rendered. |
| **U** unverified | Plausible, but neither rendered nor confirmed in source. Check before work starts. |

Findings show the header's evidence class and confidence in the form `R+S/H`: classes, then confidence (H, M or L). The category used for counts (R/M, S, U) is in `roadmap.md` section 13, item 1.

## Severities

| Severity | Meaning |
|---|---|
| **P0** | Blocks the OpenSnap direction. Breaks a hard owner rule (identity, original assets, data safety, the readable-text floor on a primary surface). Or is a foundation other work depends on. |
| **P1** | A visible quality or accessibility defect on a main surface, or an owner-required change. |
| **P2** | Polish. |

## Screenshots and evidence

- **Location:** `docs/design/evidence/2026-10-09/`. 297 captures and metrics (manifest entries). Each capture is named `<surface>-<slug>-<light|dark>`. Captures suffixed `@dc1eb26` were taken at the current main SHA; captures without a suffix were taken at `b9319c4`.
- **Counts (from `manifest.json`):** 297 entries in total: **205** at `b9319c4`, **84** at `dc1eb26`, and **8** PROTO mocks (`sourceSha` `dc1eb26`, rail-less harness mocks, not product).
- **Index:** `manifest.json` lists every capture with its `sourceSha`. `captures.md` is the human index. `gaps.md` lists what was not captured and why. Also: `layout-width-budget.json` and `.md` (live widths at `dc1eb26`), `metrics/` (view-tree metrics), `ax/` (AX dumps), `menus.json` (menu text), `observations.json`, `environment.json` and `environment@dc1eb26.json`, and `safety.txt`.
- **Environment (M):** macOS 27.2 (build 26B5101f), built-in 2x Retina display, system appearance Dark, accent colour yellow. Every accent in the captures is yellow for that reason.

## Implementation evidence

Captures from the implementation run. They are separate from the audit set above. Each folder's `captures.md` and `manifest.json` list every capture with its `sourceSha`.

| Folder | sourceSha | Captures | Todos | What it shows |
|---|---|---|---|---|
| `evidence/impl-2026-10-09/m1-rail/` | `fef46c7` | 80 PNG (7.9 MB), plus `layout/` metrics | OSN-010 to OSN-014 | Rail-removal matrix: light and dark, 980 to full screen, empty and populated, Frame, popovers, PNG and JPG. FA mode unavailable. |
| `evidence/impl-2026-10-09/m5-capture/` | `8a0e8d9` | 38 PNG | OSN-050, OSN-056 (and the OSN-021 countdown) | Screen Recording sheet and its no-grant placeholder, countdown, picker, hint plate clear of the title bar and bars. |
| `evidence/impl-2026-10-09/m4-glass/` | `da2738d` | 98 captures | OSN-042 | Glass consolidation: 8 group plates in 2 containers, solid canvas well, Snap as the only saturated control, Reduce Transparency and Increase Contrast. Legacy-scroller corner noted as open. |
| `evidence/impl-2026-10-09/m4-window/` | `7bf20f8` | 50 captures | OSN-043, OSN-041 (step 5) | Unified window chrome: document title, proxy icon, subtitle, seamless title bar, app-owned alert sheets. |
| `evidence/impl-2026-10-09/m5-settings/` | `a48d0df` | 36 captures | OSN-051 | Settings rebuild. **Pending merge:** lives on `impl/m5-settings` (integrated at `a79a1d8`), not on main yet. |

## E2E audit

Owner-authorized end-to-end audit (2026-10-09 to 2026-10-10): every option, icon and state, checked with real clicks where the session allowed it and with rendered harness captures otherwise. The classes are never merged; the rendered folders are harness renders, not real-click proof.

| File or folder | What it is |
|---|---|
| `e2e-audit-plan.md` | The audit plan and its phases. |
| `e2e/README.md` | The method, the evidence classes, the inventory and the launcher. |
| `e2e/findings.md` | Findings for J1 to J8 (93 IDs), review round 1 (R1-001 to 024), review round 2 (R2-001 to 018), review rounds 3 to 5 (R3-001 to 009, R4-001 to 007, R5-001 to 004), the final render pass (F-R-001 to 005), the J4 retest table, the J5 gap closure and the F-J5-005 panel-service investigation. |
| `e2e/coverage-matrix.md` | One row per audit ID (597 rows): E2E 312, rendered 45, unit/source 93, unverified 120 (one gap reason each), retired 27. See `progress.md`. |
| `e2e/inventory.json` | The 597 audit entries, generated from the sources and the harness. |
| `e2e/j4-aws-log.md` | The live S3 log for the F-J2-002 retest (J4): one synthetic upload and its delete through the app. |
| `evidence/e2e-2026-10-10/j1/` | J1 real-click captures (editor core). |
| `evidence/e2e-2026-10-10/j2/` | J2 real-click captures (History, Settings, Destinations, upload). |
| `evidence/e2e-2026-10-10/j3/` | J3 rendered matrix, 111 captures (not real-click). |
| `evidence/e2e-2026-10-10/j3-diffs/` | Positive-control composites for the display options (rendered). |
| `evidence/e2e-2026-10-10/j4/` | J4 real-click retest captures. |
| `evidence/e2e-2026-10-10/j5/` | J5 real-click gap closure captures (48 jpg and one AX/state readout). |
| `evidence/e2e-2026-10-10/j6/` | J6 real-click retest of batches 4 and 5 (64 captures, four sessions). |
| `evidence/e2e-2026-10-10/j7/` | J7 real-input validation of batches 6 and 7 and the review round 2 fixes (34 captures). |
| `evidence/e2e-2026-10-10/j8/` | J8 real-input validation of batch 8 (19 captures). |
| `evidence/e2e-2026-10-10/panelfix/` | Panel-service check after the F-J5-005 fix (real-click, 4 images and the service log). |
| `evidence/impl-2026-10-09/audit-fix-1` to `audit-fix-4`, `audit-fix-3b-before` | Visual acceptance for fix batches 1, 2, 3a, 3b (and its before twins), 3c and 4 (`audit-fix-4`: 147 captures, rendered only). |
| `evidence/impl-2026-10-09/audit-fix-5`, `audit-fix-6`, `audit-fix-8` | Visual acceptance for fix batches 5 (249 captures), 6 (78) and the batch 8 J7 findings (24). Rendered only, icon mode `sf`. |
| `evidence/impl-2026-10-09/audit-fix-9`, `audit-fix-10`, `audit-fix-11` | Visual acceptance for fix batches 9 (52 captures), 10 (44) and 11 (36). Rendered only, icon mode `sf`. Batch 12 has no capture folder; its evidence is the test set in `tests/AppSafetyBatch11Cases.swift`. |
| `evidence/impl-2026-10-09/final-render/` | Final render pass at `5b30929`: display options on current surfaces with positive controls (122 captures). Rendered only. |

The full index with the source SHA for each folder is in `progress.md`, section E2E audit.

## Regenerating the evidence

The harness is `tools/eye-dump-audit.sh` (merged by OSN-001; it is the only screenshot path and `tools/eye-dump.sh` is gone).

```sh
sh tools/eye-dump-audit.sh OUT [--groups main,more,overlays,sizes,fullscreen] [--appearances light,dark] [--icons sf|fa|both] [--sizes 980xmin,1024x740,1280x800,1440x900,full] [--sha SHA] [--suffix @SHA]

# assemble one icon mode of a run into an evidence folder (writes only to --out; run with -I)
python3 -I tools/eye-dump-audit-assemble.py --out DIR --b93 RAW [RAW...] --delta RAW [RAW...] --layout RAW --observations FILE --sha SHA [--icons sf|fa] [--baseline-sha SHA]
```

- `OUT` receives `raw-<icons>/` (per-capture files), `manifest.json` (every capture with `sourceSha`, surface id, appearance, window size and icon mode), `safety.txt` (real-store hashes before and after; the run exits non-zero if they changed) and `run.log`. `SHA` defaults to the build source's short SHA (`-dirty` when `Sources/` has uncommitted edits).
- The app copy runs under a throwaway bundle id `com.shoemoney.opensnap.eyedump-<pid>`, so its defaults domain is not the owner's; its home, support and evidence folders are throwaway too.
- Groups: `main`, `more`, `overlays`, `sizes` (the window-size matrix), `fullscreen`, plus `layout` and `delta`. The `welcome` group and the rail-less `proto` mock are gone. Appearance names are `light` and `dark`. `fa` icon runs need the Font Awesome subset fonts built into `build/OpenSnap.app`; otherwise the manifest lists `fa` under `unavailable` ("FA unavailable") instead of capturing SF icons.

## Safety proof

Hashes from `evidence/2026-10-09/safety.txt`, unchanged from the audit's run. No store contents were read, printed or copied.

```
SkitchRedux files hash (find -type f stat name/size/mtime | shasum)  1a388426cc6e209295d62975a3eadd41897e4a75
com.shoemoney.skitch-redux defaults hash (defaults export | shasum)  56fed48e39b705ec21c42dc36bbc55c93b47e0b7
SkitchRedux files hash  1a388426cc6e209295d62975a3eadd41897e4a75
com.shoemoney.skitch-redux defaults hash  56fed48e39b705ec21c42dc36bbc55c93b47e0b7
```

The file records: `RESULT store unchanged, defaults unchanged.` before and after the final GUI run, with cleanup of throwaway defaults domains and temp directories. No network access, no real uploads, no Keychain reads or writes, no screen capture beyond the app's own windows, and no system settings changed.

## Coverage gaps

Full list in `evidence/2026-10-09/gaps.md` and section 5 of the audit. Summary:

- **Not toggled (forbidden):** Reduce Transparency, Increase Contrast, Reduce Motion, Bold Text, Differentiate Without Color. The code paths are source-only. The injected `DisplayOptions` capture mode (OSN-061) closes this.
- **Not run:** VoiceOver speech (the AX dumps are a structural substitute; OSN-062 records a manual pass).
- **Not captured:** the Photo browser (S22, it reads the real Photos library), the menu windows (S23, text only in `menus.json`), the Wipe confirmation (none exists), native tooltips, the system share picker, real drag-and-drop to Finder, real uploads (the publish states use a stubbed uploader), and the save panel (S10 shows the accessory alone).
- **Environment:** a single 2x display only (no 1x, no multi-display), no live desktop behind the picker and countdown (S13, S14), and no Screen Recording grant (so the Frame-mode scroller question, VF-27, stays U until OSN-014 runs a live capture).
- **Flattened:** alert and status-button PNGs are flattened onto a neutral backdrop (`flattenedOnBackdrop` in the manifest, 24 entries). The S09 popup-open capture at `b9319c4` was dropped.

## Counts

| Measure | Count |
|---|---|
| Findings | 29: P0 6, P1 16, P2 7 |
| Findings by evidence category | R/M 22, S 6, U 1 (rule in `roadmap.md` section 13, item 1) |
| Todos | 36: P0 12, P1 20, P2 4 |
| Todos by milestone | M0 2, M1 5, M2 5, M3 3, M4 6, M5 9, M6 3, M7 3 |
| Todos in Lane A (`Sources/App.swift`, serial) | 22 (19 in the serial order, plus 3 landed) |
| Todos new in round 2 | 3: OSN-014, OSN-057, OSN-058 |
| Owner decisions | 10: Q1 to Q5, D-TEXT, D-HINT, D-T15-1 to D-T15-3. Each has a recommended default. All ten are resolved; Q3 is option B (custom bars), Q4 is implemented in OSN-043. |
| Estimate | 18.0 d numeric across 18 todos, plus 17.5 d of unsplit spec figures, total 35.5 d (`roadmap.md` section 8) |
| Status at `3b453b3` | 29 done, 2 verified, 1 not-a-bug, 3 in-progress, 1 pending (`progress.md`; roadmap section 2b). Unchanged since `284f028`. |

## Validating the files

```sh
python3 -m json.tool docs/design/backlog.json > /dev/null
```

The cross-checks (todo IDs, priorities, milestones, dependencies, Lane A, main state, findings and severities against `visual-audit.md` sections 6 and 9, stems against `manifest.json`, and the counts in this file) were run when these files were generated. The generator and checks are kept outside the repo, in `/tmp/osk-docs`, so no tooling was added to `tools/`.

