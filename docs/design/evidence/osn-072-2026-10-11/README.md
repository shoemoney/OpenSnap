# OSN-072 / WP7 evidence, 2026-10-11

Run against main `4254505`. Migration ran on a COPY of the owner's SkitchRedux store; the live folder was only read.
Only counts, hashes and filenames are recorded here (no drawing content, no preference values).

| # | Check | Result |
|---|-------|--------|
| 1 | Source SHA-256 manifest (121 files) before vs after copy, migration, re-run and release dry run | identical (`source-manifest-before.txt` / `-after.txt`) |
| 2 | History 58 of 58 converted to editable `.opensnap`, 58 previews copied, 2 destinations (default "AWS cdn"), 24 of 25 preference keys copied (`disableSounds` dropped as obsolete), "No failures." | `report-run1.txt`, exit 0 |
| 2b | Independent check (`verify_docs.py`): all 58 canvas JSON documents equal the old `rawCanvasData` (only the format id differs), 139 elements, text and preview bytes equal | 0 mismatches (`docs-verify.txt`) |
| 3 | Re-run is a no-op: "Nothing to migrate", output manifest (123 files) and mtimes identical | `report-run2.txt`, `report-run3.txt`, `out-manifest-*.txt`, `mt-*.txt` |
| 4 | Real OpenSnap folder absent before and after; `com.shoemoney.skitch-redux.plist` hash unchanged; `com.shoemoney.opensnap.plist` does not exist | `opensnap-*.txt`, `prefs-*.txt` |
| 5 | Clean clone (no `original/`): `tools/build.sh`, `check-no-original.py`, `tools/test.py` | all exit 0 (`logs/exit-codes.txt`); 275/275 app safety tests; skips are only the budgeted "FA not bundled" |
| 6 | `tools/release.sh 0.3.0` in the clone, run with a PATH shim logging git/gh/curl/ssh/etc. and under `sandbox-exec` denying all network | exit 0; only 3 read-only git calls (`diff --quiet`, `ls-files`, `rev-parse`), no other tool call, no tag, no push, no network. The script has no outward step, so no `--dry-run` guard was needed. `logs/trace.log` |

Not run: `tools/test-native-startup.py` and GUI-session steps (they need a desktop session; the app bundle was never launched).
The migration dry run uses in-memory defaults and an in-memory Keychain with placeholder secrets, so the real Keychain and defaults domains were never written.
Note: document A6B3BE93 is a panned image; its full pan source is preserved in the `.opensnap` file (the old viewport-only `document` copy differs by design).
