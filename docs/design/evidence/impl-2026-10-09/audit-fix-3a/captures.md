# Audit fix batch 3a visual acceptance captures

Source `cc05825`; icon mode **sf** (FA unavailable); 24 captures, every PNG scaled to at most 1200 px wide.
Pre-change twins are referenced from `docs/design/evidence/impl-2026-10-09/audit-fix-2` at `2275c5b`; they are not copied.

| Capture | Appearance | Window pt | What it shows | Layout JSON | BEFORE (pre-change) |
|---|---|---|---|---|---|
| `S08-crop-mode-dark@cc05825.png` | dark | 1561×1179 | crop tool with a 640x420 crop rectangle | `layout/S08-crop-mode-dark@cc05825.json` | — |
| `S08-crop-mode-light@cc05825.png` | light | 1561×1179 | crop tool with a 640x420 crop rectangle | `layout/S08-crop-mode-light@cc05825.json` | — |
| `S08-resize-panel-dark@cc05825.png` | dark | 1561×1179 | Resize sheet with built-in + two synthetic presets | `—` | — |
| `S08-resize-panel-light@cc05825.png` | light | 1561×1179 | Resize sheet with built-in + two synthetic presets | `—` | — |
| `S08-resize-panel-in-context-dark@cc05825.png` | dark | 1561×1179 | Resize sheet with built-in + two synthetic presets (parent window + sheet composite) | `—` | — |
| `S08-resize-panel-in-context-light@cc05825.png` | light | 1561×1179 | Resize sheet with built-in + two synthetic presets (parent window + sheet composite) | `—` | — |
| `S41-color-popover-blue-checked-w980-dark@cc05825.png` | dark | 980×640 | Blue picked, popover reopened: Blue is checked and drawn in the colour the toolbar swatch shows (F-J1-002) | `layout/S41-color-popover-blue-checked-w980-dark@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/07-color-popover-after-blue-no-check.jpg` |
| `S41-color-popover-blue-checked-w980-light@cc05825.png` | light | 980×640 | Blue picked, popover reopened: Blue is checked and drawn in the colour the toolbar swatch shows (F-J1-002) | `layout/S41-color-popover-blue-checked-w980-light@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/07-color-popover-after-blue-no-check.jpg` |
| `S41-color-popover-only-blue-checked-w980-dark@cc05825.png` | dark | 980×640 | the popover window alone, Blue checked | `—` | `docs/design/evidence/e2e-2026-10-10/j1/07-color-popover-after-blue-no-check.jpg` |
| `S41-color-popover-only-blue-checked-w980-light@cc05825.png` | light | 980×640 | the popover window alone, Blue checked | `—` | `docs/design/evidence/e2e-2026-10-10/j1/07-color-popover-after-blue-no-check.jpg` |
| `S41-colors-panel-at-current-colour-dark@cc05825.png` | dark | 980×640 | Custom color… with Black current and the shared panel last left on blue: it opens on Black and the drawing colour is untouched (F-J1-003) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/10-colors-panel-opens-showing-blue.jpg` |
| `S41-colors-panel-at-current-colour-light@cc05825.png` | light | 980×640 | Custom color… with Black current and the shared panel last left on blue: it opens on Black and the drawing colour is untouched (F-J1-003) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/10-colors-panel-opens-showing-blue.jpg` |
| `S41-crop-dropped-w980-dark@cc05825.png` | dark | 1489×1179 | after choosing the Brush tool the dim crop overlay and its hint are gone | `layout/S41-crop-dropped-w980-dark@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/55-keyboard-trap-tab-in-canvas-toggles-brush-crop-overlay-lingers.jpg` |
| `S41-crop-dropped-w980-light@cc05825.png` | light | 1489×1179 | after choosing the Brush tool the dim crop overlay and its hint are gone | `layout/S41-crop-dropped-w980-light@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/55-keyboard-trap-tab-in-canvas-toggles-brush-crop-overlay-lingers.jpg` |
| `S41-crop-hint-w980-dark@cc05825.png` | dark | 1489×1179 | a pending crop: the status line reads Crop: press Return to apply, Esc to cancel (F-J1-011) | `layout/S41-crop-hint-w980-dark@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/52-crop-tool-region-dimmed-no-apply-hint.jpg` |
| `S41-crop-hint-w980-light@cc05825.png` | light | 1489×1179 | a pending crop: the status line reads Crop: press Return to apply, Esc to cancel (F-J1-011) | `layout/S41-crop-hint-w980-light@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/52-crop-tool-region-dimmed-no-apply-hint.jpg` |
| `S41-footer-blank-w980-dark@cc05825.png` | dark | 980×640 | a blank drawing: Undo and Clear image are dimmed; Save to History is the archive box beside the History clock (F-J1-020, F-J1-021) | `layout/S41-footer-blank-w980-dark@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/00-brush-tool-selected.jpg` |
| `S41-footer-blank-w980-light@cc05825.png` | light | 980×640 | a blank drawing: Undo and Clear image are dimmed; Save to History is the archive box beside the History clock (F-J1-020, F-J1-021) | `layout/S41-footer-blank-w980-light@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/00-brush-tool-selected.jpg` |
| `S41-footer-drawn-w980-dark@cc05825.png` | dark | 980×640 | the same bar once the drawing has something to undo: Undo is live | `layout/S41-footer-drawn-w980-dark@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/84-bottom-bar-save-button-saved-to-history.jpg` |
| `S41-footer-drawn-w980-light@cc05825.png` | light | 980×640 | the same bar once the drawing has something to undo: Undo is live | `layout/S41-footer-drawn-w980-light@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/84-bottom-bar-save-button-saved-to-history.jpg` |
| `S41-text-size-committed-w980-dark@cc05825.png` | dark | 980×640 | text typed at the smallest size, recoloured and resized while open, then committed and selected (before the second size change) | `layout/S41-text-size-committed-w980-dark@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/12-size-popover-open-size7.jpg` |
| `S41-text-size-committed-w980-light@cc05825.png` | light | 980×640 | text typed at the smallest size, recoloured and resized while open, then committed and selected (before the second size change) | `layout/S41-text-size-committed-w980-light@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/12-size-popover-open-size7.jpg` |
| `S41-text-size-selected-w980-dark@cc05825.png` | dark | 980×640 | ...then resized as a selection (32 pt): the glyphs fill the frame (F-J1-005) | `layout/S41-text-size-selected-w980-dark@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/13-size-popover-preset12-text-frame-balloons.jpg` |
| `S41-text-size-selected-w980-light@cc05825.png` | light | 980×640 | ...then resized as a selection (32 pt): the glyphs fill the frame (F-J1-005) | `layout/S41-text-size-selected-w980-light@cc05825.json` | `docs/design/evidence/e2e-2026-10-10/j1/13-size-popover-preset12-text-frame-balloons.jpg` |


## Notes (hand-written; the table above is generated)

- **BEFORE** for every S41 capture is the matching J1 real-click screenshot under `docs/design/evidence/e2e-2026-10-10/j1/` (dark appearance only); S08 has none (the Resize sheet is unchanged apart from Return handling, which a capture cannot show).
- `before-harness/S41-text-size-selected-w980-light@prefix-0616d4b+3a-edits.png` is the same harness scenario run on the real window **before** the stale-style fix (all other batch-3a edits already in). It reproduces F-J1-005: the frame has followed the second size (32 pt) while the glyphs are still the earlier 64 pt, so they overflow it. The after capture beside it (`S41-text-size-selected-w980-light`) has the glyphs inside the frame. The harness metrics at the time showed a style still staged on the canvas after the text box was committed.
- Not captured: the Window menu with Enter Full Screen. The harness could not image the open menu (`S41-window-menu-open` came out as the window without the menu), so those two files are omitted; the menu item is covered by the test and the regenerated inventory only. Tab / Shift-Tab, Minimize, the eraser slot and the shadow toggle are behaviour, not pictures; their proofs are tests.
- Image descriptions are in the final report of the batch.

## Can-fail proofs (mutating one Swift line in a scratch copy; each named test fails, the worktree is untouched)

| Mutation | Failing test |
|---|---|
| remove `guard !isFinishingText` in `applyColorToSelection` | canvas: text size, colour echo at commit |
| remove `fragment.shadowed = false` in `VectorGeometry.subtract` | canvas: eraser leaves no shadow |
| remove `cropRect = nil` on tool change | canvas: tool change clears crop |
| `ResizePanel.control(...)` Return returns false | accessibility audit: Return in the width field |
| `chooseCustomColor` applies the stored colour on open | app safety F-J1-003 |
| drop the `customColorPanelOpen`/`isVisible` guard in `changeCustomColor` | app safety F-J1-003 (closed-panel echo) |
| Shadow toggle calls `applyStyleToSelection()` again | app safety F-J1-006 |
| Tab never navigates (`&& false`) | app safety F-J1-007 (walk) and the Focus Toolbar arm |
| Tab always navigates (no `tabNavigatesFocus()` check) | app safety F-J1-007 (Full Keyboard Access off arm) |
| swatches drawn in the calibrated twin colour | app safety F-J1-002 |
| Window › Enter Full Screen not inserted | app safety F-J1-008 |
| full-screen title not toggled | app safety F-J1-008 |
| pending-crop status variants disabled | app safety F-J1-011 |
| `vanish` goes back to the inactive-raises rule | app safety F-J1-022 |
| `updateUndoButton` body removed | app safety F-J1-020 |
| Save button given the clock icon | app safety F-J1-021 |
