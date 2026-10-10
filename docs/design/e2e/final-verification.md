# Final local verification — 2026-10-10

The visual rebuild and audit fixes through batch 13 are integrated. The local candidate builds and passes the required integration checks. This is a verified local candidate with explicit audit gaps, not a claim that every inventory row was exercised end to end or that a release was published.

## Candidate and provenance

- Tested candidate before the privacy rewrite: `1ea366c2db089069c7e5443bdc2800929ca53895`.
- Same candidate after the local privacy rewrite: `41700b3cba3453e928a065fa013fb6b93d833e70`.
- Their complete Git tree hashes are identical. Product sources, resources, tests and tools are unchanged by the rewrite.
- Historical evidence filenames and source-revision labels retain their original capture provenance. The local old-to-new commit map is `.git/privacy-scrub-commit-map`; labels are not current release identifiers.
- Review round 6's R6-001 and R6-002 are fixed in batch 13, with regression tests that failed against the old code. This adds two fixed findings to the previous 160-ID index: 162 findings, 131 fixed, 17 partial, 2 deferred, 5 gaps, 1 documentation-only, 4 open and 2 accepted trade-offs. Some IDs describe the same underlying issue; these are finding IDs, not independent bug counts.

## Completed checks

| Check | Result | Evidence |
|---|---|---|
| Cold build | PASS | `/tmp/fg-build.log` |
| Full suite, first run | PASS, no source drift | `/tmp/fg-test1.log` |
| Full suite, second run | PASS, no source drift | `/tmp/fg-test2.log` |
| Fresh clean clone: build, original-asset gate, full suite | PASS | `/tmp/fg-cleanclone.log`; isolated native-startup check explicitly skipped because that clone gate has no GUI session |
| Default bundle excludes Pro fonts | PASS | `/tmp/fg-nofonts.log` |
| Current E2E inventory and matrix rules | PASS | `python3 tools/e2e-inventory.py --check` |
| Full screenshot OCR sweep | Executed successfully; 2,575 images, 442 flagged, none unreadable | `/tmp/fg-ocr-run.log`; private OCR report stays outside the repository. Exit zero alone is not a privacy verdict |
| Known withdrawn clipboard image | Removed from every local Git ref and the primary object database | `git cat-file -e` fails for its blob; `git rev-list --objects --all` does not contain it |
| Known withdrawn-image OCR lines | None of the four candidate private lines occur in the current OCR report | Private comparison emitted counts only |
| Repository integrity after rewrite | PASS; temporary private history backup removed | `git fsck --no-reflogs`, exit zero; commit map retained privately in `.git/` |
| Fresh evidence-pack integrity checks | PASS, 90 PNGs, no hard failures or contrast advisories; 20 core contrast samples skipped | `check-eye-dump.py` on both root-final evidence folders |
| Interactive audit viewer | PASS at 728px/light and 360px/dark; no readable text below 18px or page overflow | Real browser checks: favorite/filter, two-image comparison, coverage class/search/pagination, expanded evidence details, task search; all gallery images decoded |
| Fresh representative candidate renders | PASS, real stores unchanged | `evidence/impl-2026-10-09/root-final-core/` (62 captures), `root-final-history/` (28 captures) |

The two full suites and the clean-clone suite passed before the history rewrite. The byte-identical tree proof carries those results to the rewritten candidate. Subsequent work in this handoff is documentation and evidence packaging only.

## Render review

Root viewed fresh editor, Toolbox, Settings, History and Resize images in light/dark appearance. The right rail is absent, actions are grouped across the top/bottom, and readable control text stays large. The run's `sf` icon label is legacy metadata meaning Pro font subsets were removed. `ChromeIcons.resolve` uses bundled Font Awesome Free vectors first when no Pro font is available; it falls back to SF Symbols only if a Free vector is missing. Therefore a `sf` label does not establish that a screenshot uses SF Symbols. The final default build visibly uses Free icons. Pro rendering remains an optional untested development mode.

The new captures are rendered harness states, not additional real-click coverage. They do not upgrade a coverage-matrix row to E2E. The interactive gallery in `audit-overview.html` shows selected representative captures with their provenance and offers downloads, favorites and comparison.

## Coverage and remaining work

The ledger contains 597 IDs: 312 real-input checks, 45 rendered checks, 93 unit/source checks, 120 unverified rows and 27 retired rows. Every unverified row has an explicit reason; retired rows do not count as tested live options. The original phased backlog remains partly open for spoken VoiceOver, the full acceptance matrix, some regression-gate requirements, and migration of a copy of the owner's real store.

The audit has not proved spoken VoiceOver, actual global capture firing on the owner's display, real Screen Recording capture, 1x/multiple displays, a populated Photos library, printer output, held-modifier gestures, a drop onto another application, or the live full-screen transition sequence. See `progress.md` and `e2e/coverage-matrix.md` for all row-specific gaps.

Known code/design issues remain explicitly recorded: text-editing accessibility selection, small-canvas/navigator space choices, transient History-open size presentation, shadow semantics after erasing, and the three pre-existing full-screen edge cases listed after the round 6 response. Uploads have an indeterminate spinner, not byte-percentage progress. The separately queued History text/glass-button request remains in `QUEUE.md` and was deliberately not activated.

No installed app was launched against the owner's real stores; no folder/repository rename, push, tag, release or installation occurred in this final verification. The local app is `build/OpenSnap.app`; the folder remains OpenSkitch.
