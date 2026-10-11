# Navigator and Actual Size thumbnail: Retina polish

Status: implemented and verified locally at source `c21c3f2`. The bounded polish pass is complete. Manual verification limits remain listed below.

Date written: 2026-10-11. Base: `main` at `daa2977`. Source of implementation: `c21c3f2ebe0703cad3c3039e9b71a68b137d5712`.

## Problem

Opus reviewed `main` at `daa2977` and found that the Actual Size overview thumbnail (the navigator) is capped at 160 px. The slot it draws into is 156 pt wide on a Retina display, which is 312 backing pixels at 2x. So the thumbnail was rendered at roughly half the pixels the slot can show, and it looked soft. Tall canvases were worse: the 160 px cap limited the long edge, so tall images came out smaller and blurrier than wide ones.

## Goal

Render the navigator at the pixel size the slot actually shows, on the screen it is shown on, and keep it bounded.

## Rules

1. Target pixels = shared drawable geometry (the slot size in points) x `backingScaleFactor`.
2. Clamp the longest edge to a 1024 px maximum. This is the bound, not the target.
3. Never upscale. If the source has fewer pixels than the target, use the source size.
4. Re-render on resize and on backing-scale change (moving the window between displays with different scale).
5. Wide, tall, small, and capped canvases all follow the same rule. No special case per shape.

## Milestones

| # | Milestone | Owner | Status |
|---|---|---|---|
| M0 | Source audit of `daa2977` (Opus review) | Opus | done |
| M1 | Before capture at `daa2977`, scenario S07, no input, real-store digest `dbde037ac2085108` | root | done |
| M2 | Native smoke at `daa2977` (see Baseline) | root | done |
| M3 | Shared geometry helper: slot points x scale, clamp to 1024, no upscale. Implemented in [`CanvasNavigator.swift`](../../Sources/CanvasNavigator.swift) and [`AppViewport.swift`](../../Sources/AppViewport.swift) | Sonnet | done |
| M4 | Wire navigator and Actual Size thumbnail to the helper; refresh on resize and backing change | Sonnet | done (same commit `c21c3f2`) |
| M5 | Unit tests: wide, tall, 2x small, cap. Tests in [`CanvasNavigatorTests.swift`](../../tests/CanvasNavigatorTests.swift) and [`AppSafetyTests.swift`](../../tests/AppSafetyTests.swift) | Sonnet | done |
| M6 | Red proof: new tests fail on the old 160 px renderer | root | done, qualified. Reverting only the pixel render path, with new APIs kept, failed at runtime with expected 312x234, actual 160x120. A full revert of the old `AppViewport` did not compile, because the new test APIs were missing, so it does not count as red proof. |
| M7 | Affected regression run: navigator and Actual Size suites | root | done. Navigator checks 230 passed. Full headless app-safety 275/275 passed. Native idle termination passed. |
| M8 | Guarded before/after captures, light and dark, into [`evidence/navigator-retina-2026-10-11/`](evidence/navigator-retina-2026-10-11/) | root | done, qualified. Wide Actual Size overview only: 12 PNGs before and 12 after, strict checker 0 failures, 0 advisories, 2 contrast skips per pack. Tall resolution is covered by bitmap tests, not a separate portrait render. Small canvases are covered by source-only tests. No small Actual Size navigator capture applies. |
| M9 | Local merge to `main` and artifact copy | root | done, qualified. The tested candidate app was copied to [`build/OpenSnap.app`](../../build/OpenSnap.app). Code signing verified. No root cold recompile was run. |

## Evidence

- Results: [`results.json`](evidence/navigator-retina-2026-10-11/results.json)
- Native smoke: [`interaction-smoke.json`](evidence/navigator-retina-2026-10-11/interaction-smoke.json)
- Build and copy record: [`local-integration.json`](evidence/navigator-retina-2026-10-11/local-integration.json)
- Captures: [`before/`](evidence/navigator-retina-2026-10-11/before/) and [`after/`](evidence/navigator-retina-2026-10-11/after/) (S07 light and dark)
- Red proof and build logs: [`verification/`](evidence/navigator-retina-2026-10-11/verification/), including [`red-behavior.log`](evidence/navigator-retina-2026-10-11/verification/red-behavior.log), [`app-safety-green.log`](evidence/navigator-retina-2026-10-11/verification/app-safety-green.log), and [`build.log`](evidence/navigator-retina-2026-10-11/verification/build.log)
- Gallery (offline, 4 images, favorites, appearance, comparison, downloads and detail): [`navigator-retina-gallery.html`](navigator-retina-gallery.html). Runtime checks passed at 728px/light and 360px/dark: filters, favorites, comparison, image loading and detail mode; readable text at least 18px, no horizontal page overflow. [Runtime record](evidence/navigator-retina-2026-10-11/gallery-runtime.json).

## Tests

Each test must be able to fail. A test that only checks that a function returns something is not enough.

- **Wide canvas, 2x:** expected pixel size is slot x 2, within the 1024 cap. Fails on the old 160 px renderer (red proof, see M6).
- **Tall canvas, 2x:** long edge follows the same rule. Covered in bitmap app tests.
- **Small canvas:** source smaller than the target. Output equals the source size, never upscaled.
- **Cap:** a very large slot at high scale clamps to 1024 px on the long edge.
- **Scale change:** the same view at 1x and 2x produces different pixel sizes.
- **Resize and backing change:** a resize or a backing-scale change triggers a re-render.

## Regressions run (M7)

The navigator geometry and internal drag routing still clamp the viewport and synchronize its outline. Actual Size entry/exit, command gating, stale callbacks and document/Undo preservation passed the existing app-safety checks. The new bitmap checks cover wide and tall fixtures and a stale-resolution refresh. These are internal AppKit tests, not a new physical pointer or display-migration proof.

## Baseline

Recorded at `daa2977`:

- **Before capture (M1):** scenario S07 completed with no input. Real-store digest `dbde037ac2085108` unchanged.
- **Native smoke (M2):** see [`interaction-smoke.json`](evidence/navigator-retina-2026-10-11/interaction-smoke.json).
  - Toolbox opened by coordinate. Color Blue chosen through an AX click, which returned RGB.
  - Size Show options opened a non-key panel. AX main was unchanged, and the screenshot confirms it.
  - First coordinate click on the fourth preset changed 7 to 9 with the panel closed.
  - An outside click dismissed the panel.
  - A face click, then the same face click again, closed it without reopening.
  - **Not valid as proof:** a second Toolbox opener attempt. Its union image coordinates targeted the Save to History blank notice.

## Not claimed

This work does not claim any of the following. They are not verified and are out of scope for this pass:

- Physical HID input or real hover behaviour. Manual.
- Live display migration between screens with different scale. Manual.
- VoiceOver speech. Manual.
- Live OS display settings outside the test harness. Manual.
- Undo restoring pen size.
- A separate portrait (tall) capture.
- A small-canvas Actual Size navigator capture.
- Captures for every tall and small canvas. Only the wide canvas was captured.
- A root cold recompile of the merged `main`.

## Documented tradeoffs, unchanged

These stay as they are. They are still OPEN and are listed here so they are not mistaken for closed findings:

- **Small canvas and navigator strip:** small documents retain current fit semantics; the unused part of the large-document navigator column remains unchanged. Small documents do not acquire an Actual Size navigator. OPEN.
- **Eraser shadow:** the eraser shadow tradeoff stays as documented. OPEN.

## Ledger

The evidence ledger stays at 626 rows: 234 E2E, 32 rendered, 27 retired, 122 unit/source, 211 unverified. This work promotes no rows and changes no class counts. Source: the current acceptance section of [`glass-pickers-root-verification.md`](e2e/glass-pickers-root-verification.md).

## Existing references

- Root report: [`glass-pickers-root-verification.md`](e2e/glass-pickers-root-verification.md) (latest root verification; ledger source).
- Actual Size overview evidence: [`e2e-2026-10-10/j5/`](evidence/e2e-2026-10-10/j5/), including [`09-zoom-popup-actual-size-entry-overview-navigator-and-scrollbars.jpg`](evidence/e2e-2026-10-10/j5/09-zoom-popup-actual-size-entry-overview-navigator-and-scrollbars.jpg) and [`10-actual-size-scroll-wheel-pans-viewport-navigator-rectangle-follows.jpg`](evidence/e2e-2026-10-10/j5/10-actual-size-scroll-wheel-pans-viewport-navigator-rectangle-follows.jpg).
- Actual Size via menu, navigator zoom disabled: [`53-image-actual-size-via-menu-overview-navigator-zoom-disabled.jpg`](evidence/e2e-2026-10-10/j6/53-image-actual-size-via-menu-overview-navigator-zoom-disabled.jpg).

The app bundle in `build/OpenSnap.app` is the verified candidate build. Nothing was pushed or installed.
