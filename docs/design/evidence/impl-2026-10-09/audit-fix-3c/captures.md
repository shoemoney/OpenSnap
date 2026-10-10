# Audit fix batch 3c visual acceptance captures

Source `0edc3ce`; icon mode **sf** (FA unavailable); 24 captures, every PNG scaled to at most 1200 px wide.
Pre-change twins are referenced from `docs/design/evidence/impl-2026-10-09/audit-fix-3c/before-harness` at `54e930a`; they are not copied.

| Capture | Appearance | Window pt | What it shows | Layout JSON | BEFORE (pre-change) |
|---|---|---|---|---|---|
| `S11F-size-fullscreen-dark@0edc3ce.png` | dark | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11F-size-fullscreen-dark@0edc3ce.json` | — |
| `S11F-size-fullscreen-light@0edc3ce.png` | light | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11F-size-fullscreen-light@0edc3ce.json` | — |
| `S42-history-hide-on-history-dark@0edc3ce.png` | dark | 1561×1179 | Hide drawings from History? raised on the History window the click came from (F-J2-001) | `—` | — |
| `S42-history-hide-on-history-light@0edc3ce.png` | light | 1561×1179 | Hide drawings from History? raised on the History window the click came from (F-J2-001) | `—` | — |
| `S42-photos-empty-dark@0edc3ce.png` | dark | 1561×1179 | Photos sheet with nothing chosen: the grid holds the explanation and both source buttons (F-J1-013) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/32-photos-sheet-empty-state.jpg` |
| `S42-photos-empty-light@0edc3ce.png` | light | 1561×1179 | Photos sheet with nothing chosen: the grid holds the explanation and both source buttons (F-J1-013) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/32-photos-sheet-empty-state.jpg` |
| `S42-photos-empty-in-context-dark@0edc3ce.png` | dark | 1561×1179 | Photos sheet with nothing chosen: the grid holds the explanation and both source buttons (F-J1-013) (parent window + sheet composite) | `—` | — |
| `S42-photos-empty-in-context-light@0edc3ce.png` | light | 1561×1179 | Photos sheet with nothing chosen: the grid holds the explanation and both source buttons (F-J1-013) (parent window + sheet composite) | `—` | — |
| `S42-resize-crop-dark@0edc3ce.png` | dark | 1561×1179 | Resize or Crop sheet, crop mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/27-resize-sheet-crop-mode-anchor-popup.jpg` |
| `S42-resize-crop-light@0edc3ce.png` | light | 1561×1179 | Resize or Crop sheet, crop mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/27-resize-sheet-crop-mode-anchor-popup.jpg` |
| `S42-resize-crop-in-context-dark@0edc3ce.png` | dark | 1561×1179 | Resize or Crop sheet, crop mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) (parent window + sheet composite) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/27-resize-sheet-crop-mode-anchor-popup.jpg` |
| `S42-resize-crop-in-context-light@0edc3ce.png` | light | 1561×1179 | Resize or Crop sheet, crop mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) (parent window + sheet composite) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/27-resize-sheet-crop-mode-anchor-popup.jpg` |
| `S42-resize-limit-dark@0edc3ce.png` | dark | 1561×1179 | Resize or Crop sheet, limit mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/29-resize-sheet-limit-mode.jpg` |
| `S42-resize-limit-light@0edc3ce.png` | light | 1561×1179 | Resize or Crop sheet, limit mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/29-resize-sheet-limit-mode.jpg` |
| `S42-resize-limit-in-context-dark@0edc3ce.png` | dark | 1561×1179 | Resize or Crop sheet, limit mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) (parent window + sheet composite) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/29-resize-sheet-limit-mode.jpg` |
| `S42-resize-limit-in-context-light@0edc3ce.png` | light | 1561×1179 | Resize or Crop sheet, limit mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) (parent window + sheet composite) | `—` | `docs/design/evidence/e2e-2026-10-10/j1/29-resize-sheet-limit-mode.jpg` |
| `S42-resize-resize-dark@0edc3ce.png` | dark | 1561×1179 | Resize or Crop sheet, resize mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) | `—` | — |
| `S42-resize-resize-light@0edc3ce.png` | light | 1561×1179 | Resize or Crop sheet, resize mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) | `—` | — |
| `S42-resize-resize-in-context-dark@0edc3ce.png` | dark | 1561×1179 | Resize or Crop sheet, resize mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) (parent window + sheet composite) | `—` | — |
| `S42-resize-resize-in-context-light@0edc3ce.png` | light | 1561×1179 | Resize or Crop sheet, resize mode: mode control and dimensions first, presets folded into one row, buttons trailing (F-J1-014) (parent window + sheet composite) | `—` | — |
| `S42-status-after-notice-dark@0edc3ce.png` | dark | 1561×1179 | the normal status back, now naming the export format (F-J1-010) | `layout/S42-status-after-notice-dark@0edc3ce.json` | `docs/design/evidence/e2e-2026-10-10/j1/47-fullscreen-exited-status-text-stale.jpg` |
| `S42-status-after-notice-light@0edc3ce.png` | light | 1561×1179 | the normal status back, now naming the export format (F-J1-010) | `layout/S42-status-after-notice-light@0edc3ce.json` | `docs/design/evidence/e2e-2026-10-10/j1/47-fullscreen-exited-status-text-stale.jpg` |
| `S42-status-notice-dark@0edc3ce.png` | dark | 1561×1179 | a transient message in the status slot (F-J1-010) | `layout/S42-status-notice-dark@0edc3ce.json` | `docs/design/evidence/e2e-2026-10-10/j1/33-save-to-history-status-confirms.jpg` |
| `S42-status-notice-light@0edc3ce.png` | light | 1561×1179 | a transient message in the status slot (F-J1-010) | `layout/S42-status-notice-light@0edc3ce.json` | `docs/design/evidence/e2e-2026-10-10/j1/33-save-to-history-status-confirms.jpg` |

## Notes

- Before twins in `before-harness/` are the same surfaces captured by the same harness at `54e930a` (main + audit batch 3a); the rest point at the E2E journey screenshot that showed the defect.
- The Toolbox pull-down is a menu window the harness cannot image (it appears only as the editor window behind it); its content is proven by `AppSafetyTests`: 18 rows, an icon on every row, no About/Settings/Quit/file plumbing.
- `S11F-size-fullscreen-*`: real full screen with the small 800 x 600 drawing; the zoom fits it (192%), the bars stay one centred group.
- `S42-status-notice-*` and `S42-status-after-notice-*` crop the bottom bar: the message while it lasts, then the normal status naming PNG.

