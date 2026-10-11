# Follow-up root verification — 2026-10-10

Status: follow-up integrated into local main; root visual review complete for this pass. This report covers the newly authorized History glass-button polish and remaining actionable audit behaviour checks. It supersedes the queued History status in the earlier final-verification snapshot, without claiming complete manual or hardware acceptance.

## Candidate

The first render candidate is integration commit `718f601293133933f5746581c711f8064999a368`, tree `685c4ea08ee9a65385201584b34d56900c230ba1`, based on local handoff `7fef2a8`. The cold build and full `tools/test.py` pass are recorded in `/tmp/fu-int-build2.log` and `/tmp/fu-int-test2.log`. All suites passed without source drift, including 262/262 app-safety checks and the real-store guard. History/chrome are unchanged between this render candidate and the final source.

## Changes reviewed

History actions share three native glass plates in one container, with coherent button states, 20pt labels and accessible named groups. At the 880pt minimum, destructive labels remain visible and benign actions retain semantic icons and accessible names. At wider sizes, all action labels fit. The filter controls and history cards remain readable native/content surfaces.

The earlier stale History-open size presentation and missing AX selection were not reproduced on the baseline: new regression checks preserve the working behaviour. The real AX-client check in `/tmp/fu-fj1023-e2e.md` set and read a selection and used a real Delete key to edit it in an isolated synthetic session. VoiceOver speech remains unverified; one driver's untargeted text insertion behaviour remains unresolved.

Full-screen changes have regression coverage, including output/frame restoration, document-generation guards and the did-exit ordering correction. Tests that simulate handler ordering do not establish the live transition animation.

## Evidence and remaining limits

Root captured and reviewed minimum-width and wider History layouts, focus/pressed states, empty/no-match states, and light/dark accessibility display variants at `718f601`. Two guarded runs produced 48 normal S20/S43 captures and 28 S20 accessibility captures, with no gaps, no actual input events and unchanged watched real stores (digest `dbde037ac2085108`). Both evidence packs pass `check-eye-dump.py` with zero hard failures and zero contrast advisories; History has no sampled-layout contrast proof in that checker. Packs: `evidence/followup-2026-10-10/root-history/` and `root-history-accessible/`.

Actual History action labels are attributed 20pt strings; raw metrics also expose AppKit internal backing fields at 13pt. The OS-owned History titlebar uses its native 13pt font, so this review does not claim the application font floor applies successfully to every OS-owned titlebar/control. The body and controls are visually readable; the shared typography test covers application labels.

The before/after gallery passes preview checks at 728px/light and 360px/dark: no readable HTML text below 18px and no page overflow. Real browser checks confirm favorite/filter, default two-image comparison, removal/re-addition, native-pixel preview, coverage-class filtering and all images decoded. These browser checks validate the report UI, not the native application interaction ledger.

Final candidate `b6b6b2e4ac1537207e5916e0dfefe82f5105ff0c` (tree `cc9e59add66e1daf50dbce23e3b835dc97be79ec`) was fast-forwarded into local main. Its Sources, tests and tools are byte-identical to tested `1ac66740bb976a9c00e2540839fbbdea63eec6b7` (tree `5061c9809c3f7cd99f66f8146fa5a7809bb5ea05`); only three docs changed after that tested commit. Final full suite: all suites on arm64, no source drift, 263/263 app-safety, native idle termination passed, real-store guard unchanged (122 files, 2 defaults files, throwaway plists 0/0). Logs: `/tmp/fu-int-build3.log`, `/tmp/fu-int-test3.log`.

Root rebuilt `build/OpenSnap.app` successfully from main (`/tmp/followup-root-build.log`). A guarded final-source run at `b6b6b2e` captured S02 (populated editor), S08 (Resize/Crop sheet), S11F and S11FP (empty/populated full screen), light and dark: 12 captures, no gaps. Root opened and reviewed the populated editor, both Resize appearances and both populated full-screen appearances; no material visual regression was found. The watched real stores remained unchanged (digest `dbde037ac2085108`), with zero real input events. Evidence: `evidence/followup-2026-10-10/root-viewport/`; `check-eye-dump.py` passed (12 PNGs, 8 layout JSONs, zero hard failures or contrast advisories). These frames establish layout appearance, not the Resize/full-screen Cancel transition itself. Since the History renders, the only application change is the mirror Resize Cancel correction: entering full screen with Resize up then cancelling now fits the restored drawing and retains the windowed zoom/frame for exit. Its regression test was shown to fail when the fix was reverted. This is behaviour proof from simulated event order, not live animation proof.

The final gallery preview also passes at 728px/light and 360px/dark, with 18px readable minimum and no horizontal overflow. Finding counts reconcile to 162 indexed IDs, including 132 fixed; FR-1 to FR-4 and FS-A/B/C are separately documented follow-up cases. No additional real-input coverage is implied by harness captures. Historical coverage rows retain their original source/evidence labels.

Small-canvas/navigator layout and eraser-shadow semantics remain recorded design choices. Live full-screen transitions, VoiceOver speech, real hover/Tab, display permissions and hardware-dependent paths remain explicit gaps. No installed application, real-store migration, network operation, push, tag or release is part of this local pass.
