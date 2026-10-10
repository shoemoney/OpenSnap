# OSN-043 unified window chrome and OSN-041 app-owned alert sheets: visual acceptance captures

Source `7bf20f8`; icon mode **sf** (FA unavailable); 50 captures, every PNG scaled to at most 1200 px wide.
Pre-change twins are referenced from `docs/design/evidence/impl-2026-10-09/m4-glass` at `da2738d`; they are not copied.

| Capture | Appearance | Window pt | What it shows | Layout JSON | BEFORE (pre-change) |
|---|---|---|---|---|---|
| `S01-editor-empty-dark@7bf20f8.png` | dark | 1120×812 | fresh blank canvas, default window | `layout/S01-editor-empty-dark@7bf20f8.json` | `docs/design/evidence/impl-2026-10-09/m4-glass/S01-editor-empty-dark@da2738d.png` |
| `S01-editor-empty-light@7bf20f8.png` | light | 1120×812 | fresh blank canvas, default window | `layout/S01-editor-empty-light@7bf20f8.json` | `docs/design/evidence/impl-2026-10-09/m4-glass/S01-editor-empty-light@da2738d.png` |
| `S11-size-contentmin-dark@7bf20f8.png` | dark | 980×640 | contentMinSize 980x608 | `layout/S11-size-contentmin-dark@7bf20f8.json` | — |
| `S11-size-contentmin-light@7bf20f8.png` | light | 980×640 | contentMinSize 980x608 | `layout/S11-size-contentmin-light@7bf20f8.json` | — |
| `S11-size-default-dark@7bf20f8.png` | dark | 1120×812 | default 1024x740 | `layout/S11-size-default-dark@7bf20f8.json` | — |
| `S11-size-default-light@7bf20f8.png` | light | 1120×812 | default 1024x740 | `layout/S11-size-default-light@7bf20f8.json` | — |
| `S11-size-maximized-dark@7bf20f8.png` | dark | 2056×1197 | maximized to visibleFrame 2056x1197 | `layout/S11-size-maximized-dark@7bf20f8.json` | — |
| `S11-size-maximized-light@7bf20f8.png` | light | 2056×1197 | maximized to visibleFrame 2056x1197 | `layout/S11-size-maximized-light@7bf20f8.json` | — |
| `S11-size-tall-dark@7bf20f8.png` | dark | 1000×1157 | tall 1000x1157 | `layout/S11-size-tall-dark@7bf20f8.json` | — |
| `S11-size-tall-light@7bf20f8.png` | light | 1000×1157 | tall 1000x1157 | `layout/S11-size-tall-light@7bf20f8.json` | — |
| `S11-size-wide-dark@7bf20f8.png` | dark | 1900×640 | wide 1900x640 | `layout/S11-size-wide-dark@7bf20f8.json` | — |
| `S11-size-wide-light@7bf20f8.png` | light | 1900×640 | wide 1900x640 | `layout/S11-size-wide-light@7bf20f8.json` | — |
| `S11-width-1024-dark@7bf20f8.png` | dark | 1024×812 | window width 1024 pt, default height | `layout/S11-width-1024-dark@7bf20f8.json` | — |
| `S11-width-1024-light@7bf20f8.png` | light | 1024×812 | window width 1024 pt, default height | `layout/S11-width-1024-light@7bf20f8.json` | — |
| `S11-width-1280-dark@7bf20f8.png` | dark | 1280×812 | window width 1280 pt, default height | `layout/S11-width-1280-dark@7bf20f8.json` | — |
| `S11-width-1280-light@7bf20f8.png` | light | 1280×812 | window width 1280 pt, default height | `layout/S11-width-1280-light@7bf20f8.json` | — |
| `S11-width-1440-dark@7bf20f8.png` | dark | 1440×812 | window width 1440 pt, default height | `layout/S11-width-1440-dark@7bf20f8.json` | — |
| `S11-width-1440-light@7bf20f8.png` | light | 1440×812 | window width 1440 pt, default height | `layout/S11-width-1440-light@7bf20f8.json` | — |
| `S11-width-980-dark@7bf20f8.png` | dark | 980×812 | window width 980 pt, default height | `layout/S11-width-980-dark@7bf20f8.json` | — |
| `S11-width-980-light@7bf20f8.png` | light | 980×812 | window width 980 pt, default height | `layout/S11-width-980-light@7bf20f8.json` | — |
| `S11F-size-fullscreen-dark@7bf20f8.png` | dark | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11F-size-fullscreen-dark@7bf20f8.json` | `docs/design/evidence/2026-10-09/S11-size-fullscreen-dark@dc1eb26.png` |
| `S11F-size-fullscreen-light@7bf20f8.png` | light | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11F-size-fullscreen-light@7bf20f8.json` | `docs/design/evidence/2026-10-09/S11-size-fullscreen-light@dc1eb26.png` |
| `S11FP-size-fullscreen-populated-dark@7bf20f8.png` | dark | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11FP-size-fullscreen-populated-dark@7bf20f8.json` | — |
| `S11FP-size-fullscreen-populated-light@7bf20f8.png` | light | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11FP-size-fullscreen-populated-light@7bf20f8.json` | — |
| `S12-frame-mode-dark@7bf20f8.png` | dark | 1489×1179 | Frame mode: clear canvas hole, Snap Frame + Cancel, window alpha 0.8 | `layout/S12-frame-mode-dark@7bf20f8.json` | — |
| `S12-frame-mode-light@7bf20f8.png` | light | 1489×1179 | Frame mode: clear canvas hole, Snap Frame + Cancel, window alpha 0.8 | `layout/S12-frame-mode-light@7bf20f8.json` | — |
| `S12-frame-resnap-dark@7bf20f8.png` | dark | 1489×1179 | Re-snap (keep pen) Frame mode over existing annotations | `layout/S12-frame-resnap-dark@7bf20f8.json` | — |
| `S12-frame-resnap-light@7bf20f8.png` | light | 1489×1179 | Re-snap (keep pen) Frame mode over existing annotations | `layout/S12-frame-resnap-light@7bf20f8.json` | — |
| `S12-frame-w1024-dark@7bf20f8.png` | dark | 1024×1179 | Frame mode at window width 1024 pt | `layout/S12-frame-w1024-dark@7bf20f8.json` | — |
| `S12-frame-w1024-light@7bf20f8.png` | light | 1024×1179 | Frame mode at window width 1024 pt | `layout/S12-frame-w1024-light@7bf20f8.json` | — |
| `S12-frame-w1280-dark@7bf20f8.png` | dark | 1280×1179 | Frame mode at window width 1280 pt | `layout/S12-frame-w1280-dark@7bf20f8.json` | — |
| `S12-frame-w1280-light@7bf20f8.png` | light | 1280×1179 | Frame mode at window width 1280 pt | `layout/S12-frame-w1280-light@7bf20f8.json` | — |
| `S12-frame-w980-dark@7bf20f8.png` | dark | 980×1179 | Frame mode at window width 980 pt | `layout/S12-frame-w980-dark@7bf20f8.json` | — |
| `S12-frame-w980-light@7bf20f8.png` | light | 980×1179 | Frame mode at window width 980 pt | `layout/S12-frame-w980-light@7bf20f8.json` | — |
| `S16-permission-sheet-dark@7bf20f8.png` | dark | 1489×1179 | app-owned sheet: title, instructions, Open System Settings (default) and Cancel | `—` | `docs/design/evidence/2026-10-09/S16-permission-alert-dark.png` |
| `S16-permission-sheet-light@7bf20f8.png` | light | 1489×1179 | app-owned sheet: title, instructions, Open System Settings (default) and Cancel | `—` | `docs/design/evidence/2026-10-09/S16-permission-alert-light.png` |
| `S16-permission-sheet-in-context-dark@7bf20f8.png` | dark | 1489×1179 | the sheet over the dimmed editor (sheet + parent composite, sheet in front) | `—` | — |
| `S16-permission-sheet-in-context-light@7bf20f8.png` | light | 1489×1179 | the sheet over the dimmed editor (sheet + parent composite, sheet in front) | `—` | — |
| `S39-discard-sheet-dark@7bf20f8.png` | dark | 1280×800 | Save your drawing? sheet over the titled window (Save / Cancel / Don’t Save) | `—` | `docs/design/evidence/2026-10-09/S26-close-unsaved-dark.png` |
| `S39-discard-sheet-light@7bf20f8.png` | light | 1280×800 | Save your drawing? sheet over the titled window (Save / Cancel / Don’t Save) | `—` | — |
| `S39-titlebar-crop-w1280-dark@7bf20f8.png` | dark | 1280×800 | the title bar and top bar only, at w1280 | `layout/S39-titlebar-crop-w1280-dark@7bf20f8.json` | `docs/design/evidence/impl-2026-10-09/m4-glass/S01-editor-empty-dark@da2738d.png` |
| `S39-titlebar-crop-w1280-light@7bf20f8.png` | light | 1280×800 | the title bar and top bar only, at w1280 | `layout/S39-titlebar-crop-w1280-light@7bf20f8.json` | `docs/design/evidence/impl-2026-10-09/m4-glass/S01-editor-empty-light@da2738d.png` |
| `S39-titlebar-crop-w980-dark@7bf20f8.png` | dark | 980×640 | the title bar and top bar only, at w980 | `layout/S39-titlebar-crop-w980-dark@7bf20f8.json` | `docs/design/evidence/impl-2026-10-09/m4-glass/S01-editor-empty-dark@da2738d.png` |
| `S39-titlebar-crop-w980-light@7bf20f8.png` | light | 980×640 | the title bar and top bar only, at w980 | `layout/S39-titlebar-crop-w980-light@7bf20f8.json` | `docs/design/evidence/impl-2026-10-09/m4-glass/S01-editor-empty-light@da2738d.png` |
| `S39-titled-window-w1280-dark@7bf20f8.png` | dark | 1280×800 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w1280 | `layout/S39-titled-window-w1280-dark@7bf20f8.json` | `docs/design/evidence/2026-10-09/S11-width-1280-dark@dc1eb26.png` |
| `S39-titled-window-w1280-light@7bf20f8.png` | light | 1280×800 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w1280 | `layout/S39-titled-window-w1280-light@7bf20f8.json` | `docs/design/evidence/2026-10-09/S11-width-1280-light@dc1eb26.png` |
| `S39-titled-window-w980-dark@7bf20f8.png` | dark | 980×640 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w980 | `layout/S39-titled-window-w980-dark@7bf20f8.json` | `docs/design/evidence/2026-10-09/S11-width-980-dark@dc1eb26.png` |
| `S39-titled-window-w980-light@7bf20f8.png` | light | 980×640 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w980 | `layout/S39-titled-window-w980-light@7bf20f8.json` | `docs/design/evidence/2026-10-09/S11-width-980-light@dc1eb26.png` |
| `S39-upload-error-sheet-dark@7bf20f8.png` | dark | 1280×800 | error sheet after a stubbed failed upload, over the titled window | `—` | `docs/design/evidence/2026-10-09/S21-publish-error-dark.png` |
| `S39-upload-error-sheet-light@7bf20f8.png` | light | 1280×800 | error sheet after a stubbed failed upload, over the titled window | `—` | — |

## What these captures show (OSN-043 unified window chrome, OSN-041 step 5 app-owned alerts)

- **S39 titled-window / titlebar-crop (w980, w1280, light, dark):** the title bar reads `Quarterly mockup – 2000 × 1400 · 555 KB` with the document proxy icon: the system draws the title and the size subtitle on one line, at the system's size (OS-owned). Under it the top bar starts directly: no grey strip, no hairline. Measured on the crop at 1280: title-bar and window pixels are both 30/30/30 in dark and 255/255/255 in light (the first run, with an opaque title bar, measured 41/40/39 over 30/30/30 plus a 1 pt line, which is why the title bar is now transparent outside Frame mode).
- **S39 discard-sheet (light, dark):** `Save your drawing?` as an app-owned sheet over the dimmed window. Title 22 pt semibold, message 20 pt, buttons 20 pt (Don’t Save at the leading edge, Cancel, then the accent-filled default Save). The sheet sits mid-window in the capture, as the existing S16 permission sheet does; that is how the harness composites a sheet, not a layout choice.
- **S39 upload-error-sheet (light, dark):** the stubbed upload failure as one title line pair (it wraps to two lines, no ellipsis) and a single default OK. The upload-error inline UX is OSN-054; this only reroutes the alert.
- **S12 frame-\*:** Frame mode: title bar opaque and readable, hole unchanged, Cancel beside Snap Frame.
- **S11F / S11FP size-fullscreen:** now real full screen (`styleMask.fullScreen` set; before, `toggleFullScreen` was ignored). The window spans the 2056 x 1290 screen with no title bar and no traffic lights; the top bar sits at the screen's top edge.
- **S01, S11, S16:** same chrome as before with the title `Untitled`-style document title instead of the app name.

### Gaps and limits

- BEFORE twins: the NSAlert originals exist only in the baseline folder `docs/design/evidence/2026-10-09/` (`dc1eb26`) and only for the appearances captured then (`S26-close-unsaved` and `S21-publish-error`, dark only), so the light sheets show a dash. The titled window is compared with that baseline's `S11-width-*` window (the plain `OpenSnap` title bar) and the title-bar crops with `S01-editor-empty` of `m4-glass`. S11F, S12, S01 and S16 are paired with `m4-glass` where it has them.
- Real VoiceOver speech is not run; the sheet's role, label and focus are asserted in `AppAlertTests` and `AppSafetyWindowChromeCases`.
- The proxy-icon drag/menu (Command-click on the title) is not exercised.
- Standalone alert (no visible window, e.g. Quit from the status menu with the editor hidden) is a panel ordered on screen; it is covered by the routing assertions only, not captured.
- Alert text in Save and Open panels, the title-bar text and the traffic-light tooltips remain system-owned.

