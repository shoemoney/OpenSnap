# OSN-071 visual acceptance run (round 3): base

Source `723e65b`; icon mode **sf** (FA unavailable); 760 captures, every PNG scaled to at most 1200 px wide.
Pre-change twins are referenced from `docs/design/evidence/impl-2026-10-09/root-final-core` at `1ea366c`; they are not copied.

| Capture | Appearance | Window pt | What it shows | Layout JSON | BEFORE (pre-change) |
|---|---|---|---|---|---|
| `S01-editor-empty-dark@723e65b.png` | dark | 1120×812 | fresh blank canvas, default window | `layout/S01-editor-empty-dark@723e65b.json` | — |
| `S01-editor-empty-light@723e65b.png` | light | 1120×812 | fresh blank canvas, default window | `layout/S01-editor-empty-light@723e65b.json` | — |
| `S02-populated-dark@723e65b.png` | dark | 1561×1179 | synthetic 1200x800 background + arrow, line, rectangle (open+filled), ellipse, brush, highlighter, fill, text (outline+shadow, plain), SVG path, raster | `layout/S02-populated-dark@723e65b.json` | — |
| `S02-populated-light@723e65b.png` | light | 1561×1179 | synthetic 1200x800 background + arrow, line, rectangle (open+filled), ellipse, brush, highlighter, fill, text (outline+shadow, plain), SVG path, raster | `layout/S02-populated-light@723e65b.json` | — |
| `S03-bottombar-dark@723e65b.png` | dark | 1488×1179 | Undo, Wipe / Zoom, Resize / status / Save, History / PNG/JPG, Drag, Upload | `layout/S03-bottombar-dark@723e65b.json` | — |
| `S03-bottombar-light@723e65b.png` | light | 1488×1179 | Undo, Wipe / Zoom, Resize / status / Save, History / PNG/JPG, Drag, Upload | `layout/S03-bottombar-light@723e65b.json` | — |
| `S03-topbar-dark@723e65b.png` | dark | 1488×1179 | Hide, Toolbox, Photos / Snap / ten tools / Color, Size, Font; title shows document name | `layout/S03-topbar-dark@723e65b.json` | — |
| `S03-topbar-light@723e65b.png` | light | 1488×1179 | Hide, Toolbox, Photos / Snap / ten tools / Color, Size, Font; title shows document name | `layout/S03-topbar-light@723e65b.json` | — |
| `S04-controls-disabled-dark@723e65b.png` | dark | 1488×1179 | Resize + Undo disabled (isEnabled=false as Frame/Actual mode does) | `layout/S04-controls-disabled-dark@723e65b.json` | — |
| `S04-controls-disabled-light@723e65b.png` | light | 1488×1179 | Resize + Undo disabled (isEnabled=false as Frame/Actual mode does) | `layout/S04-controls-disabled-light@723e65b.json` | — |
| `S04-snap-hover-dark@723e65b.png` | dark | 1488×1179 | Snap (primary, accent) hovered | `layout/S04-snap-hover-dark@723e65b.json` | — |
| `S04-snap-hover-light@723e65b.png` | light | 1488×1179 | Snap (primary, accent) hovered | `layout/S04-snap-hover-light@723e65b.json` | — |
| `S04-tool-arrow-dark@723e65b.png` | dark | 1488×1179 | arrow tool selected | `layout/S04-tool-arrow-dark@723e65b.json` | — |
| `S04-tool-arrow-light@723e65b.png` | light | 1488×1179 | arrow tool selected | `layout/S04-tool-arrow-light@723e65b.json` | — |
| `S04-tool-brush-dark@723e65b.png` | dark | 1488×1179 | brush tool selected | `layout/S04-tool-brush-dark@723e65b.json` | — |
| `S04-tool-brush-light@723e65b.png` | light | 1488×1179 | brush tool selected | `layout/S04-tool-brush-light@723e65b.json` | — |
| `S04-tool-crop-dark@723e65b.png` | dark | 1488×1179 | crop tool selected | `layout/S04-tool-crop-dark@723e65b.json` | — |
| `S04-tool-crop-light@723e65b.png` | light | 1488×1179 | crop tool selected | `layout/S04-tool-crop-light@723e65b.json` | — |
| `S04-tool-ellipse-dark@723e65b.png` | dark | 1488×1179 | ellipse tool selected | `layout/S04-tool-ellipse-dark@723e65b.json` | — |
| `S04-tool-ellipse-light@723e65b.png` | light | 1488×1179 | ellipse tool selected | `layout/S04-tool-ellipse-light@723e65b.json` | — |
| `S04-tool-eraser-dark@723e65b.png` | dark | 1488×1179 | eraser tool selected | `layout/S04-tool-eraser-dark@723e65b.json` | — |
| `S04-tool-eraser-light@723e65b.png` | light | 1488×1179 | eraser tool selected | `layout/S04-tool-eraser-light@723e65b.json` | — |
| `S04-tool-fill-dark@723e65b.png` | dark | 1488×1179 | fill tool selected | `layout/S04-tool-fill-dark@723e65b.json` | — |
| `S04-tool-fill-light@723e65b.png` | light | 1488×1179 | fill tool selected | `layout/S04-tool-fill-light@723e65b.json` | — |
| `S04-tool-hover-dark@723e65b.png` | dark | 1488×1179 | Rectangle tool hovered (CommandButton.setHovered: a 0.08 fill on the group plate), Brush selected | `layout/S04-tool-hover-dark@723e65b.json` | — |
| `S04-tool-hover-light@723e65b.png` | light | 1488×1179 | Rectangle tool hovered (CommandButton.setHovered: a 0.08 fill on the group plate), Brush selected | `layout/S04-tool-hover-light@723e65b.json` | — |
| `S04-tool-line-dark@723e65b.png` | dark | 1488×1179 | line tool selected | `layout/S04-tool-line-dark@723e65b.json` | — |
| `S04-tool-line-light@723e65b.png` | light | 1488×1179 | line tool selected | `layout/S04-tool-line-light@723e65b.json` | — |
| `S04-tool-pressed-dark@723e65b.png` | dark | 1488×1179 | Rectangle tool pressed (CommandButton.highlight: a 0.16 fill on the group plate), Brush selected | `layout/S04-tool-pressed-dark@723e65b.json` | — |
| `S04-tool-pressed-light@723e65b.png` | light | 1488×1179 | Rectangle tool pressed (CommandButton.highlight: a 0.16 fill on the group plate), Brush selected | `layout/S04-tool-pressed-light@723e65b.json` | — |
| `S04-tool-rectangle-dark@723e65b.png` | dark | 1488×1179 | rectangle tool selected | `layout/S04-tool-rectangle-dark@723e65b.json` | — |
| `S04-tool-rectangle-light@723e65b.png` | light | 1488×1179 | rectangle tool selected | `layout/S04-tool-rectangle-light@723e65b.json` | — |
| `S04-tool-select-dark@723e65b.png` | dark | 1488×1179 | select tool selected | `layout/S04-tool-select-dark@723e65b.json` | — |
| `S04-tool-select-light@723e65b.png` | light | 1488×1179 | select tool selected | `layout/S04-tool-select-light@723e65b.json` | — |
| `S04-tool-text-dark@723e65b.png` | dark | 1488×1179 | text tool selected | `layout/S04-tool-text-dark@723e65b.json` | — |
| `S04-tool-text-light@723e65b.png` | light | 1488×1179 | text tool selected | `layout/S04-tool-text-light@723e65b.json` | — |
| `S05-selection-multi-dark@723e65b.png` | dark | 1488×1179 | ellipse + arrow selected together | `layout/S05-selection-multi-dark@723e65b.json` | — |
| `S05-selection-multi-light@723e65b.png` | light | 1488×1179 | ellipse + arrow selected together | `layout/S05-selection-multi-light@723e65b.json` | — |
| `S05-selection-rect-dark@723e65b.png` | dark | 1488×1179 | rectangle selected with resize handles | `layout/S05-selection-rect-dark@723e65b.json` | — |
| `S05-selection-rect-light@723e65b.png` | light | 1488×1179 | rectangle selected with resize handles | `layout/S05-selection-rect-light@723e65b.json` | — |
| `S05-text-editing-dark@723e65b.png` | dark | 1488×1179 | text tool field editor active with typed text and grip | `layout/S05-text-editing-dark@723e65b.json` | — |
| `S05-text-editing-light@723e65b.png` | light | 1488×1179 | text tool field editor active with typed text and grip | `layout/S05-text-editing-light@723e65b.json` | — |
| `S06-color-palette-dark@723e65b.png` | dark | 1488×1179 | preset palette popover open (original ten presets + Custom color…) | `layout/S06-color-palette-dark@723e65b.json` | — |
| `S06-color-palette-light@723e65b.png` | light | 1488×1179 | preset palette popover open (original ten presets + Custom color…) | `layout/S06-color-palette-light@723e65b.json` | — |
| `S06-color-palette-popover-dark@723e65b.png` | dark | 1488×1179 | preset palette popover window alone | `—` | — |
| `S06-color-palette-popover-light@723e65b.png` | light | 1488×1179 | preset palette popover window alone | `—` | — |
| `S06-color-panel-dark@723e65b.png` | dark | 1488×1179 | system NSColorPanel opened by Custom color… | `—` | — |
| `S06-color-panel-light@723e65b.png` | light | 1488×1179 | system NSColorPanel opened by Custom color… | `—` | — |
| `S06-fonts-panel-dark@723e65b.png` | dark | 1488×1179 | NSFontPanel with Outline / Shadow / Default accessory form | `—` | — |
| `S06-fonts-panel-light@723e65b.png` | light | 1488×1179 | NSFontPanel with Outline / Shadow / Default accessory form | `—` | — |
| `S06-size-max-dark@723e65b.png` | dark | 1488×1179 | size pill glyph at 12.0 (max) | `layout/S06-size-max-dark@723e65b.json` | — |
| `S06-size-max-light@723e65b.png` | light | 1488×1179 | size pill glyph at 12.0 (max) | `layout/S06-size-max-light@723e65b.json` | — |
| `S06-size-mid-dark@723e65b.png` | dark | 1488×1179 | size pill glyph at 6.75 (mid) | `layout/S06-size-mid-dark@723e65b.json` | — |
| `S06-size-mid-light@723e65b.png` | light | 1488×1179 | size pill glyph at 6.75 (mid) | `layout/S06-size-mid-light@723e65b.json` | — |
| `S06-size-min-dark@723e65b.png` | dark | 1488×1179 | size pill glyph at 1.5 (min) | `layout/S06-size-min-dark@723e65b.json` | — |
| `S06-size-min-light@723e65b.png` | light | 1488×1179 | size pill glyph at 1.5 (min) | `layout/S06-size-min-light@723e65b.json` | — |
| `S07-actual-size-dark@723e65b.png` | dark | 1662×1179 | Actual Size on: navigator overview panel beside the window | `layout/S07-actual-size-dark@723e65b.json` | — |
| `S07-actual-size-light@723e65b.png` | light | 1662×1179 | Actual Size on: navigator overview panel beside the window | `layout/S07-actual-size-light@723e65b.json` | — |
| `S07-large-fit-dark@723e65b.png` | dark | 1662×1179 | 2400x1500 image fitted into the window | `layout/S07-large-fit-dark@723e65b.json` | — |
| `S07-large-fit-light@723e65b.png` | light | 1662×1179 | 2400x1500 image fitted into the window | `layout/S07-large-fit-light@723e65b.json` | — |
| `S07-small-centred-dark@723e65b.png` | dark | 980×648 | 360x240 image centred in a large viewport (shot first, before any Actual Size state) (CenteringClipView) | `layout/S07-small-centred-dark@723e65b.json` | — |
| `S07-small-centred-light@723e65b.png` | light | 980×648 | 360x240 image centred in a large viewport (shot first, before any Actual Size state) (CenteringClipView) | `layout/S07-small-centred-light@723e65b.json` | — |
| `S07-zoom-200-dark@723e65b.png` | dark | 1662×1179 | zoom 200% | `layout/S07-zoom-200-dark@723e65b.json` | — |
| `S07-zoom-200-light@723e65b.png` | light | 1662×1179 | zoom 200% | `layout/S07-zoom-200-light@723e65b.json` | — |
| `S07-zoom-25-dark@723e65b.png` | dark | 1662×1179 | zoom 25% | `layout/S07-zoom-25-dark@723e65b.json` | — |
| `S07-zoom-25-light@723e65b.png` | light | 1662×1179 | zoom 25% | `layout/S07-zoom-25-light@723e65b.json` | — |
| `S07-zoom-50-dark@723e65b.png` | dark | 1662×1179 | zoom 50% | `layout/S07-zoom-50-dark@723e65b.json` | — |
| `S07-zoom-50-light@723e65b.png` | light | 1662×1179 | zoom 50% | `layout/S07-zoom-50-light@723e65b.json` | — |
| `S08-crop-mode-dark@723e65b.png` | dark | 1561×1179 | crop tool with a 640x420 crop rectangle | `layout/S08-crop-mode-dark@723e65b.json` | — |
| `S08-crop-mode-light@723e65b.png` | light | 1561×1179 | crop tool with a 640x420 crop rectangle | `layout/S08-crop-mode-light@723e65b.json` | — |
| `S08-resize-panel-dark@723e65b.png` | dark | 1561×1179 | Resize sheet with built-in + two synthetic presets | `—` | — |
| `S08-resize-panel-light@723e65b.png` | light | 1561×1179 | Resize sheet with built-in + two synthetic presets | `—` | — |
| `S08-resize-panel-in-context-dark@723e65b.png` | dark | 1561×1179 | Resize sheet with built-in + two synthetic presets (parent window + sheet composite) | `—` | — |
| `S08-resize-panel-in-context-light@723e65b.png` | light | 1561×1179 | Resize sheet with built-in + two synthetic presets (parent window + sheet composite) | `—` | — |
| `S09-footer-dark@723e65b.png` | dark | 1488×1179 | zoom, status, format, drag well, upload | `layout/S09-footer-dark@723e65b.json` | — |
| `S09-footer-light@723e65b.png` | light | 1488×1179 | zoom, status, format, drag well, upload | `layout/S09-footer-light@723e65b.json` | — |
| `S09-footer-long-status-dark@723e65b.png` | dark | 1488×1179 | very long status text | `layout/S09-footer-long-status-dark@723e65b.json` | — |
| `S09-footer-long-status-light@723e65b.png` | light | 1488×1179 | very long status text | `layout/S09-footer-long-status-light@723e65b.json` | — |
| `S09-format-toggle-jpg-dark@723e65b.png` | dark | 1488×1179 | PNG / JPG segmented toggle with JPG selected | `layout/S09-format-toggle-jpg-dark@723e65b.json` | — |
| `S09-format-toggle-jpg-light@723e65b.png` | light | 1488×1179 | PNG / JPG segmented toggle with JPG selected | `layout/S09-format-toggle-jpg-light@723e65b.json` | — |
| `S09-format-toggle-png-dark@723e65b.png` | dark | 1488×1179 | PNG / JPG segmented toggle with PNG selected | `layout/S09-format-toggle-png-dark@723e65b.json` | — |
| `S09-format-toggle-png-light@723e65b.png` | light | 1488×1179 | PNG / JPG segmented toggle with PNG selected | `layout/S09-format-toggle-png-light@723e65b.json` | — |
| `S09-upload-menu-open-dark@723e65b.png` | dark | 1488×1179 | Upload (Webpost) destination choices open, no destination configured (glass panel) | `—` | — |
| `S09-upload-menu-open-light@723e65b.png` | light | 1488×1179 | Upload (Webpost) destination choices open, no destination configured (glass panel) | `—` | — |
| `S09-upload-menu-open-dismissed-dark@723e65b.png` | dark | 1488×1179 | Upload panel dismissed with Escape | `layout/S09-upload-menu-open-dismissed-dark@723e65b.json` | — |
| `S09-upload-menu-open-dismissed-light@723e65b.png` | light | 1488×1179 | Upload panel dismissed with Escape | `layout/S09-upload-menu-open-dismissed-light@723e65b.json` | — |
| `S10-export-accessory-alone-dark@723e65b.png` | dark | 1488×1179 | ExportAccessory view rendered in its own window (JPEG selected) | `—` | — |
| `S10-export-accessory-alone-light@723e65b.png` | light | 1488×1179 | ExportAccessory view rendered in its own window (JPEG selected) | `—` | — |
| `S10-export-panel-dark@723e65b.png` | dark | 1488×1179 | NSSavePanel with ExportAccessory (aborted, nothing written); the panel's own file browser is a system remote view that never reaches a window image, so the capture is the panel frame plus the app's accessory content | `—` | — |
| `S10-export-panel-light@723e65b.png` | light | 1488×1179 | NSSavePanel with ExportAccessory (aborted, nothing written); the panel's own file browser is a system remote view that never reaches a window image, so the capture is the panel frame plus the app's accessory content | `—` | — |
| `S11-size-contentmin-dark@723e65b.png` | dark | 980×640 | contentMinSize 980x608 | `layout/S11-size-contentmin-dark@723e65b.json` | — |
| `S11-size-contentmin-light@723e65b.png` | light | 980×640 | contentMinSize 980x608 | `layout/S11-size-contentmin-light@723e65b.json` | — |
| `S11-size-default-dark@723e65b.png` | dark | 1120×812 | default 1024x740 | `layout/S11-size-default-dark@723e65b.json` | — |
| `S11-size-default-light@723e65b.png` | light | 1120×812 | default 1024x740 | `layout/S11-size-default-light@723e65b.json` | — |
| `S11-size-maximized-dark@723e65b.png` | dark | 2056×1197 | maximized to visibleFrame 2056x1197 | `layout/S11-size-maximized-dark@723e65b.json` | — |
| `S11-size-maximized-light@723e65b.png` | light | 2056×1197 | maximized to visibleFrame 2056x1197 | `layout/S11-size-maximized-light@723e65b.json` | — |
| `S11-size-tall-dark@723e65b.png` | dark | 1000×1157 | tall 1000x1157 | `layout/S11-size-tall-dark@723e65b.json` | — |
| `S11-size-tall-light@723e65b.png` | light | 1000×1157 | tall 1000x1157 | `layout/S11-size-tall-light@723e65b.json` | — |
| `S11-size-wide-dark@723e65b.png` | dark | 1900×640 | wide 1900x640 | `layout/S11-size-wide-dark@723e65b.json` | — |
| `S11-size-wide-light@723e65b.png` | light | 1900×640 | wide 1900x640 | `layout/S11-size-wide-light@723e65b.json` | — |
| `S11-width-1024-dark@723e65b.png` | dark | 1024×812 | window width 1024 pt, default height | `layout/S11-width-1024-dark@723e65b.json` | — |
| `S11-width-1024-light@723e65b.png` | light | 1024×812 | window width 1024 pt, default height | `layout/S11-width-1024-light@723e65b.json` | — |
| `S11-width-1280-dark@723e65b.png` | dark | 1280×812 | window width 1280 pt, default height | `layout/S11-width-1280-dark@723e65b.json` | — |
| `S11-width-1280-light@723e65b.png` | light | 1280×812 | window width 1280 pt, default height | `layout/S11-width-1280-light@723e65b.json` | — |
| `S11-width-1440-dark@723e65b.png` | dark | 1440×812 | window width 1440 pt, default height | `layout/S11-width-1440-dark@723e65b.json` | — |
| `S11-width-1440-light@723e65b.png` | light | 1440×812 | window width 1440 pt, default height | `layout/S11-width-1440-light@723e65b.json` | — |
| `S11-width-980-dark@723e65b.png` | dark | 980×812 | window width 980 pt, default height | `layout/S11-width-980-dark@723e65b.json` | — |
| `S11-width-980-light@723e65b.png` | light | 980×812 | window width 980 pt, default height | `layout/S11-width-980-light@723e65b.json` | — |
| `S11E-empty-size-1024x740-dark@723e65b.png` | dark | 1024×740 | requested 1024x740 (1024x740 pt), window is 1024x740 pt | `layout/S11E-empty-size-1024x740-dark@723e65b.json` | — |
| `S11E-empty-size-1024x740-light@723e65b.png` | light | 1024×740 | requested 1024x740 (1024x740 pt), window is 1024x740 pt | `layout/S11E-empty-size-1024x740-light@723e65b.json` | — |
| `S11E-empty-size-1280x800-dark@723e65b.png` | dark | 1280×800 | requested 1280x800 (1280x800 pt), window is 1280x800 pt | `layout/S11E-empty-size-1280x800-dark@723e65b.json` | — |
| `S11E-empty-size-1280x800-light@723e65b.png` | light | 1280×800 | requested 1280x800 (1280x800 pt), window is 1280x800 pt | `layout/S11E-empty-size-1280x800-light@723e65b.json` | — |
| `S11E-empty-size-1440x900-dark@723e65b.png` | dark | 1440×900 | requested 1440x900 (1440x900 pt), window is 1440x900 pt | `layout/S11E-empty-size-1440x900-dark@723e65b.json` | — |
| `S11E-empty-size-1440x900-light@723e65b.png` | light | 1440×900 | requested 1440x900 (1440x900 pt), window is 1440x900 pt | `layout/S11E-empty-size-1440x900-light@723e65b.json` | — |
| `S11E-empty-size-980xmin-dark@723e65b.png` | dark | 980×640 | requested 980xmin (980x640 pt), window is 980x640 pt | `layout/S11E-empty-size-980xmin-dark@723e65b.json` | — |
| `S11E-empty-size-980xmin-light@723e65b.png` | light | 980×640 | requested 980xmin (980x640 pt), window is 980x640 pt | `layout/S11E-empty-size-980xmin-light@723e65b.json` | — |
| `S11E-empty-size-full-dark@723e65b.png` | dark | 2056×1197 | requested full (2056x1197 pt), window is 2056x1197 pt | `layout/S11E-empty-size-full-dark@723e65b.json` | — |
| `S11E-empty-size-full-light@723e65b.png` | light | 2056×1197 | requested full (2056x1197 pt), window is 2056x1197 pt | `layout/S11E-empty-size-full-light@723e65b.json` | — |
| `S11F-size-fullscreen-dark@723e65b.png` | dark | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11F-size-fullscreen-dark@723e65b.json` | — |
| `S11F-size-fullscreen-light@723e65b.png` | light | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11F-size-fullscreen-light@723e65b.json` | — |
| `S11FP-size-fullscreen-populated-dark@723e65b.png` | dark | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11FP-size-fullscreen-populated-dark@723e65b.json` | — |
| `S11FP-size-fullscreen-populated-light@723e65b.png` | light | 2056×1290 | true full screen (styleMask.fullScreen) | `layout/S11FP-size-fullscreen-populated-light@723e65b.json` | — |
| `S11M-size-1024x740-dark@723e65b.png` | dark | 1024×740 | requested 1024x740 (1024x740 pt), window is 1024x740 pt | `layout/S11M-size-1024x740-dark@723e65b.json` | — |
| `S11M-size-1024x740-light@723e65b.png` | light | 1024×740 | requested 1024x740 (1024x740 pt), window is 1024x740 pt | `layout/S11M-size-1024x740-light@723e65b.json` | — |
| `S11M-size-1280x800-dark@723e65b.png` | dark | 1280×800 | requested 1280x800 (1280x800 pt), window is 1280x800 pt | `layout/S11M-size-1280x800-dark@723e65b.json` | — |
| `S11M-size-1280x800-light@723e65b.png` | light | 1280×800 | requested 1280x800 (1280x800 pt), window is 1280x800 pt | `layout/S11M-size-1280x800-light@723e65b.json` | — |
| `S11M-size-1440x900-dark@723e65b.png` | dark | 1440×900 | requested 1440x900 (1440x900 pt), window is 1440x900 pt | `layout/S11M-size-1440x900-dark@723e65b.json` | — |
| `S11M-size-1440x900-light@723e65b.png` | light | 1440×900 | requested 1440x900 (1440x900 pt), window is 1440x900 pt | `layout/S11M-size-1440x900-light@723e65b.json` | — |
| `S11M-size-980xmin-dark@723e65b.png` | dark | 980×640 | requested 980xmin (980x640 pt), window is 980x640 pt | `layout/S11M-size-980xmin-dark@723e65b.json` | — |
| `S11M-size-980xmin-light@723e65b.png` | light | 980×640 | requested 980xmin (980x640 pt), window is 980x640 pt | `layout/S11M-size-980xmin-light@723e65b.json` | — |
| `S11M-size-full-dark@723e65b.png` | dark | 2056×1197 | requested full (2056x1197 pt), window is 2056x1197 pt | `layout/S11M-size-full-dark@723e65b.json` | — |
| `S11M-size-full-light@723e65b.png` | light | 2056×1197 | requested full (2056x1197 pt), window is 2056x1197 pt | `layout/S11M-size-full-light@723e65b.json` | — |
| `S12-frame-mode-dark@723e65b.png` | dark | 1488×1179 | Frame mode: clear canvas hole, Snap Frame + Cancel, window alpha 0.8 | `layout/S12-frame-mode-dark@723e65b.json` | — |
| `S12-frame-mode-light@723e65b.png` | light | 1488×1179 | Frame mode: clear canvas hole, Snap Frame + Cancel, window alpha 0.8 | `layout/S12-frame-mode-light@723e65b.json` | — |
| `S12-frame-resnap-dark@723e65b.png` | dark | 1488×1179 | Re-snap (keep pen) Frame mode over existing annotations | `layout/S12-frame-resnap-dark@723e65b.json` | — |
| `S12-frame-resnap-light@723e65b.png` | light | 1488×1179 | Re-snap (keep pen) Frame mode over existing annotations | `layout/S12-frame-resnap-light@723e65b.json` | — |
| `S12-frame-w1024-dark@723e65b.png` | dark | 1024×1179 | Frame mode at window width 1024 pt | `layout/S12-frame-w1024-dark@723e65b.json` | — |
| `S12-frame-w1024-light@723e65b.png` | light | 1024×1179 | Frame mode at window width 1024 pt | `layout/S12-frame-w1024-light@723e65b.json` | — |
| `S12-frame-w1280-dark@723e65b.png` | dark | 1280×1179 | Frame mode at window width 1280 pt | `layout/S12-frame-w1280-dark@723e65b.json` | — |
| `S12-frame-w1280-light@723e65b.png` | light | 1280×1179 | Frame mode at window width 1280 pt | `layout/S12-frame-w1280-light@723e65b.json` | — |
| `S12-frame-w980-dark@723e65b.png` | dark | 980×1179 | Frame mode at window width 980 pt | `layout/S12-frame-w980-dark@723e65b.json` | — |
| `S12-frame-w980-light@723e65b.png` | light | 980×1179 | Frame mode at window width 980 pt | `layout/S12-frame-w980-light@723e65b.json` | — |
| `S13-picker-no-recording-grant-dark@723e65b.png` | dark | 1120×812 | crosshair overlay with magnifier (lens hatched placeholder reading Screen Recording off, as without a grant), no drag yet | `—` | — |
| `S13-picker-no-recording-grant-light@723e65b.png` | light | 1120×812 | crosshair overlay with magnifier (lens hatched placeholder reading Screen Recording off, as without a grant), no drag yet | `—` | — |
| `S13-picker-no-recording-grant-dragging-dark@723e65b.png` | dark | 1120×812 | mid-drag selection rectangle with dimmed surround and the size read-out (lens placeholder) | `—` | — |
| `S13-picker-no-recording-grant-dragging-light@723e65b.png` | light | 1120×812 | mid-drag selection rectangle with dimmed surround and the size read-out (lens placeholder) | `—` | — |
| `S13-picker-no-recording-grant-edge-bottom-right-dark@723e65b.png` | dark | 1120×812 | magnifier with the pointer at the bottom-right corner of the display (placeholder lens): lens and size label both stay on screen, the label 4 pt below the lens border | `—` | — |
| `S13-picker-no-recording-grant-edge-bottom-right-light@723e65b.png` | light | 1120×812 | magnifier with the pointer at the bottom-right corner of the display (placeholder lens): lens and size label both stay on screen, the label 4 pt below the lens border | `—` | — |
| `S13-picker-no-recording-grant-edge-top-left-dark@723e65b.png` | dark | 1120×812 | magnifier with the pointer at the top-left corner of the display (placeholder lens): lens and size label both stay on screen, the label 4 pt below the lens border | `—` | — |
| `S13-picker-no-recording-grant-edge-top-left-light@723e65b.png` | light | 1120×812 | magnifier with the pointer at the top-left corner of the display (placeholder lens): lens and size label both stay on screen, the label 4 pt below the lens border | `—` | — |
| `S13-picker-synthetic-lens-dark@723e65b.png` | dark | 1120×812 | crosshair overlay with magnifier (lens fed synthetic pixels), no drag yet | `—` | — |
| `S13-picker-synthetic-lens-light@723e65b.png` | light | 1120×812 | crosshair overlay with magnifier (lens fed synthetic pixels), no drag yet | `—` | — |
| `S13-picker-synthetic-lens-dragging-dark@723e65b.png` | dark | 1120×812 | mid-drag selection rectangle with dimmed surround and the size read-out (lens synthetic) | `—` | — |
| `S13-picker-synthetic-lens-dragging-light@723e65b.png` | light | 1120×812 | mid-drag selection rectangle with dimmed surround and the size read-out (lens synthetic) | `—` | — |
| `S14-countdown-1-dark@723e65b.png` | dark | 1120×812 | countdown digit 1 (tick 42) | `—` | — |
| `S14-countdown-1-light@723e65b.png` | light | 1120×812 | countdown digit 1 (tick 42) | `—` | — |
| `S14-countdown-2-dark@723e65b.png` | dark | 1120×812 | countdown digit 2 (tick 22) | `—` | — |
| `S14-countdown-2-light@723e65b.png` | light | 1120×812 | countdown digit 2 (tick 22) | `—` | — |
| `S14-countdown-3-dark@723e65b.png` | dark | 1120×812 | countdown digit 3 (tick 2) | `—` | — |
| `S14-countdown-3-light@723e65b.png` | light | 1120×812 | countdown digit 3 (tick 2) | `—` | — |
| `S14-countdown-3-contrast-reduce-motion-dark@723e65b.png` | dark | 1120×812 | digit 3 with Increase Contrast (plate 0.8) and Reduce Motion (alpha 1 on the first frame) | `—` | — |
| `S14-countdown-3-contrast-reduce-motion-light@723e65b.png` | light | 1120×812 | digit 3 with Increase Contrast (plate 0.8) and Reduce Motion (alpha 1 on the first frame) | `—` | — |
| `S15-flash-half-dark@723e65b.png` | dark | 1488×1179 | flash halfway up the ramp (0.35) in front of the editor | `—` | — |
| `S15-flash-half-light@723e65b.png` | light | 1488×1179 | flash halfway up the ramp (0.35) in front of the editor | `—` | — |
| `S15-flash-peak-dark@723e65b.png` | dark | 1488×1179 | flash panel at its peak alpha (0.7) in front of the editor, editor behind it | `—` | — |
| `S15-flash-peak-light@723e65b.png` | light | 1488×1179 | flash panel at its peak alpha (0.7) in front of the editor, editor behind it | `—` | — |
| `S16-permission-sheet-dark@723e65b.png` | dark | 1488×1179 | app-owned sheet: title, instructions, Open System Settings (default) and Cancel | `—` | — |
| `S16-permission-sheet-light@723e65b.png` | light | 1488×1179 | app-owned sheet: title, instructions, Open System Settings (default) and Cancel | `—` | — |
| `S16-permission-sheet-in-context-dark@723e65b.png` | dark | 1488×1179 | the sheet over the dimmed editor (sheet + parent composite, sheet in front) | `—` | — |
| `S16-permission-sheet-in-context-light@723e65b.png` | light | 1488×1179 | the sheet over the dimmed editor (sheet + parent composite, sheet in front) | `—` | — |
| `S17-settings-capture-dark@723e65b.png` | dark | 1488×1179 | Capture tab: flash on, shortcuts enabled, every action None | `—` | — |
| `S17-settings-capture-light@723e65b.png` | light | 1488×1179 | Capture tab: flash on, shortcuts enabled, every action None | `—` | — |
| `S17-settings-capture-1280x800-dark@723e65b.png` | dark | 1488×1179 | Capture tab: flash on, shortcuts enabled, every action None, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-1280x800-light@723e65b.png` | light | 1488×1179 | Capture tab: flash on, shortcuts enabled, every action None, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-error-dark@723e65b.png` | dark | 1488×1179 | Capture tab with a refused shortcut (a key with no Command or Control) | `—` | — |
| `S17-settings-capture-error-light@723e65b.png` | light | 1488×1179 | Capture tab with a refused shortcut (a key with no Command or Control) | `—` | — |
| `S17-settings-capture-error-1280x800-dark@723e65b.png` | dark | 1488×1179 | Capture tab with a refused shortcut (a key with no Command or Control), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-error-1280x800-light@723e65b.png` | light | 1488×1179 | Capture tab with a refused shortcut (a key with no Command or Control), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-modifiers-dark@723e65b.png` | dark | 1488×1179 | Capture tab with Option-Control-K chosen for Screen region: the chosen modifier toggles are in the accent | `—` | — |
| `S17-settings-capture-modifiers-light@723e65b.png` | light | 1488×1179 | Capture tab with Option-Control-K chosen for Screen region: the chosen modifier toggles are in the accent | `—` | — |
| `S17-settings-capture-modifiers-1280x800-dark@723e65b.png` | dark | 1488×1179 | Capture tab with Option-Control-K chosen for Screen region: the chosen modifier toggles are in the accent, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-modifiers-1280x800-light@723e65b.png` | light | 1488×1179 | Capture tab with Option-Control-K chosen for Screen region: the chosen modifier toggles are in the accent, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-drawing-dark@723e65b.png` | dark | 1488×1179 | Drawing tab, default values | `—` | — |
| `S17-settings-drawing-light@723e65b.png` | light | 1488×1179 | Drawing tab, default values | `—` | — |
| `S17-settings-drawing-1280x800-dark@723e65b.png` | dark | 1488×1179 | Drawing tab, default values, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-drawing-1280x800-light@723e65b.png` | light | 1488×1179 | Drawing tab, default values, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-drawing-alt-dark@723e65b.png` | dark | 1488×1179 | Drawing tab, alternate values (Loose, Start) | `—` | — |
| `S17-settings-drawing-alt-light@723e65b.png` | light | 1488×1179 | Drawing tab, alternate values (Loose, Start) | `—` | — |
| `S17-settings-drawing-alt-1280x800-dark@723e65b.png` | dark | 1488×1179 | Drawing tab, alternate values (Loose, Start), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-drawing-alt-1280x800-light@723e65b.png` | light | 1488×1179 | Drawing tab, alternate values (Loose, Start), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-general-dark@723e65b.png` | dark | 1488×1179 | General tab, default values | `—` | — |
| `S17-settings-general-light@723e65b.png` | light | 1488×1179 | General tab, default values | `—` | — |
| `S17-settings-general-1280x800-dark@723e65b.png` | dark | 1488×1179 | General tab, default values, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-general-1280x800-light@723e65b.png` | light | 1488×1179 | General tab, default values, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-general-alt-dark@723e65b.png` | dark | 1488×1179 | General tab, alternate values (Menu bar, snap window off, both hint options on) | `—` | — |
| `S17-settings-general-alt-light@723e65b.png` | light | 1488×1179 | General tab, alternate values (Menu bar, snap window off, both hint options on) | `—` | — |
| `S17-settings-general-alt-1280x800-dark@723e65b.png` | dark | 1488×1179 | General tab, alternate values (Menu bar, snap window off, both hint options on), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-general-alt-1280x800-light@723e65b.png` | light | 1488×1179 | General tab, alternate values (Menu bar, snap window off, both hint options on), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-dark@723e65b.png` | dark | 1488×1179 | Upload tab: three saved destinations, the first is the default | `—` | — |
| `S17-settings-upload-light@723e65b.png` | light | 1488×1179 | Upload tab: three saved destinations, the first is the default | `—` | — |
| `S17-settings-upload-1280x800-dark@723e65b.png` | dark | 1488×1179 | Upload tab: three saved destinations, the first is the default, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-1280x800-light@723e65b.png` | light | 1488×1179 | Upload tab: three saved destinations, the first is the default, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-empty-dark@723e65b.png` | dark | 1488×1179 | Upload tab, no destination saved | `—` | — |
| `S17-settings-upload-empty-light@723e65b.png` | light | 1488×1179 | Upload tab, no destination saved | `—` | — |
| `S17-settings-upload-empty-1280x800-dark@723e65b.png` | dark | 1488×1179 | Upload tab, no destination saved, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-empty-1280x800-light@723e65b.png` | light | 1488×1179 | Upload tab, no destination saved, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-many-dark@723e65b.png` | dark | 1488×1179 | Upload tab, eight saved destinations, all listed: the list is as tall as the screen allows and scrolls past that; Add…, Edit…, Remove, Make Default and the caption in view | `—` | — |
| `S17-settings-upload-many-light@723e65b.png` | light | 1488×1179 | Upload tab, eight saved destinations, all listed: the list is as tall as the screen allows and scrolls past that; Add…, Edit…, Remove, Make Default and the caption in view | `—` | — |
| `S17-settings-upload-many-1280x800-dark@723e65b.png` | dark | 1488×1179 | Upload tab, eight saved destinations, all listed: the list is as tall as the screen allows and scrolls past that; Add…, Edit…, Remove, Make Default and the caption in view, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-many-1280x800-light@723e65b.png` | light | 1488×1179 | Upload tab, eight saved destinations, all listed: the list is as tall as the screen allows and scrolls past that; Add…, Edit…, Remove, Make Default and the caption in view, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-many-440-dark@723e65b.png` | dark | 1488×1179 | Upload tab, eight destinations on a very short 440 pt visible height: the list scrolls inside, the caption stays in view | `—` | — |
| `S17-settings-upload-many-440-light@723e65b.png` | light | 1488×1179 | Upload tab, eight destinations on a very short 440 pt visible height: the list scrolls inside, the caption stays in view | `—` | — |
| `S17-settings-upload-many-640-dark@723e65b.png` | dark | 1488×1179 | Upload tab, eight destinations on a 640 pt tall screen (616 pt visible): same window, list capped | `—` | — |
| `S17-settings-upload-many-640-light@723e65b.png` | light | 1488×1179 | Upload tab, eight destinations on a 640 pt tall screen (616 pt visible): same window, list capped | `—` | — |
| `S18-hotkeys-via-app-menu-dark@723e65b.png` | dark | 1488×1179 | Capture Shortcuts… from the app menu: Settings opens on the Capture tab (all actions None) | `—` | — |
| `S18-hotkeys-via-app-menu-light@723e65b.png` | light | 1488×1179 | Capture Shortcuts… from the app menu: Settings opens on the Capture tab (all actions None) | `—` | — |
| `S19-destinations-edit-form-dark@723e65b.png` | dark | 1488×1179 | edit form for the selected destination, a sheet on the Settings window | `—` | — |
| `S19-destinations-edit-form-light@723e65b.png` | light | 1488×1179 | edit form for the selected destination, a sheet on the Settings window | `—` | — |
| `S19-destinations-edit-form-in-context-dark@723e65b.png` | dark | 1488×1179 | edit form for the selected destination, a sheet on the Settings window (parent window + sheet composite) | `—` | — |
| `S19-destinations-edit-form-in-context-light@723e65b.png` | light | 1488×1179 | edit form for the selected destination, a sheet on the Settings window (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-focus-dark@723e65b.png` | dark | 1488×1179 | first visible text field focused in the destination edit form | `—` | — |
| `S19-destinations-form-focus-light@723e65b.png` | light | 1488×1179 | first visible text field focused in the destination edit form | `—` | — |
| `S19-destinations-form-focus-in-context-dark@723e65b.png` | dark | 1488×1179 | first visible text field focused in the destination edit form (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-focus-in-context-light@723e65b.png` | light | 1488×1179 | first visible text field focused in the destination edit form (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-ftp-dark@723e65b.png` | dark | 1488×1179 | new FTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-ftp-light@723e65b.png` | light | 1488×1179 | new FTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-ftp-in-context-dark@723e65b.png` | dark | 1488×1179 | new FTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-ftp-in-context-light@723e65b.png` | light | 1488×1179 | new FTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-ftps-dark@723e65b.png` | dark | 1488×1179 | new FTPS destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-ftps-light@723e65b.png` | light | 1488×1179 | new FTPS destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-ftps-in-context-dark@723e65b.png` | dark | 1488×1179 | new FTPS destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-ftps-in-context-light@723e65b.png` | light | 1488×1179 | new FTPS destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-s3-dark@723e65b.png` | dark | 1488×1179 | new S3-compatible destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-s3-light@723e65b.png` | light | 1488×1179 | new S3-compatible destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-s3-in-context-dark@723e65b.png` | dark | 1488×1179 | new S3-compatible destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-s3-in-context-light@723e65b.png` | light | 1488×1179 | new S3-compatible destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-sftp-dark@723e65b.png` | dark | 1488×1179 | new SFTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-sftp-light@723e65b.png` | light | 1488×1179 | new SFTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-sftp-in-context-dark@723e65b.png` | dark | 1488×1179 | new SFTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-sftp-in-context-light@723e65b.png` | light | 1488×1179 | new SFTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-webdav-dark@723e65b.png` | dark | 1488×1179 | new WebDAV destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-webdav-light@723e65b.png` | light | 1488×1179 | new WebDAV destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-webdav-in-context-dark@723e65b.png` | dark | 1488×1179 | new WebDAV destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-webdav-in-context-light@723e65b.png` | light | 1488×1179 | new WebDAV destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-from-settings-640-dark@723e65b.png` | dark | 1488×1179 | the editor as hosted by the 640 pt Settings window: 640 wide, so it never overhangs its parent | `—` | — |
| `S19-destinations-from-settings-640-light@723e65b.png` | light | 1488×1179 | the editor as hosted by the 640 pt Settings window: 640 wide, so it never overhangs its parent | `—` | — |
| `S19-destinations-from-settings-640-in-context-dark@723e65b.png` | dark | 1488×1179 | the editor as hosted by the 640 pt Settings window: 640 wide, so it never overhangs its parent (parent window + sheet composite) | `—` | — |
| `S19-destinations-from-settings-640-in-context-light@723e65b.png` | light | 1488×1179 | the editor as hosted by the 640 pt Settings window: 640 wide, so it never overhangs its parent (parent window + sheet composite) | `—` | — |
| `S19-destinations-short-screen-dark@723e65b.png` | dark | 1488×1179 | edit form on a short display (visible frame 1280 x 500): the form scrolls and Test, Cancel and Save stay pinned | `—` | — |
| `S19-destinations-short-screen-light@723e65b.png` | light | 1488×1179 | edit form on a short display (visible frame 1280 x 500): the form scrolls and Test, Cancel and Save stay pinned | `—` | — |
| `S19-destinations-short-screen-in-context-dark@723e65b.png` | dark | 1488×1179 | edit form on a short display (visible frame 1280 x 500): the form scrolls and Test, Cancel and Save stay pinned (parent window + sheet composite) | `—` | — |
| `S19-destinations-short-screen-in-context-light@723e65b.png` | light | 1488×1179 | edit form on a short display (visible frame 1280 x 500): the form scrolls and Test, Cancel and Save stay pinned (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-connected-dark@723e65b.png` | dark | 1488×1179 | S3 form after a synthetic successful Test: check glyph, Connected, detail line | `—` | — |
| `S19-destinations-test-connected-light@723e65b.png` | light | 1488×1179 | S3 form after a synthetic successful Test: check glyph, Connected, detail line | `—` | — |
| `S19-destinations-test-connected-in-context-dark@723e65b.png` | dark | 1488×1179 | S3 form after a synthetic successful Test: check glyph, Connected, detail line (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-connected-in-context-light@723e65b.png` | light | 1488×1179 | S3 form after a synthetic successful Test: check glyph, Connected, detail line (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-error-dark@723e65b.png` | dark | 1488×1179 | S3 form after a synthetic failed Test: octagon glyph and an Error: line | `—` | — |
| `S19-destinations-test-error-light@723e65b.png` | light | 1488×1179 | S3 form after a synthetic failed Test: octagon glyph and an Error: line | `—` | — |
| `S19-destinations-test-error-in-context-dark@723e65b.png` | dark | 1488×1179 | S3 form after a synthetic failed Test: octagon glyph and an Error: line (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-error-in-context-light@723e65b.png` | light | 1488×1179 | S3 form after a synthetic failed Test: octagon glyph and an Error: line (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-error-webdav-dark@723e65b.png` | dark | 1488×1179 | WebDAV form after a synthetic failed Test (HTTP 401): the band grows to its lines and the form above it shrinks to make room | `—` | — |
| `S19-destinations-test-error-webdav-light@723e65b.png` | light | 1488×1179 | WebDAV form after a synthetic failed Test (HTTP 401): the band grows to its lines and the form above it shrinks to make room | `—` | — |
| `S19-destinations-test-error-webdav-in-context-dark@723e65b.png` | dark | 1488×1179 | WebDAV form after a synthetic failed Test (HTTP 401): the band grows to its lines and the form above it shrinks to make room (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-error-webdav-in-context-light@723e65b.png` | light | 1488×1179 | WebDAV form after a synthetic failed Test (HTTP 401): the band grows to its lines and the form above it shrinks to make room (parent window + sheet composite) | `—` | — |
| `S19-settings-upload-empty-dark@723e65b.png` | dark | 1488×1179 | Settings, Upload tab, no destination saved: No destinations yet and Add… inside the list | `—` | — |
| `S19-settings-upload-empty-light@723e65b.png` | light | 1488×1179 | Settings, Upload tab, no destination saved: No destinations yet and Add… inside the list | `—` | — |
| `S19-settings-upload-list-dark@723e65b.png` | dark | 1488×1179 | Settings, Upload tab: three synthetic destinations (Example S3 default, SFTP, WebDAV) with Add…, Edit…, Remove and Make Default | `—` | — |
| `S19-settings-upload-list-light@723e65b.png` | light | 1488×1179 | Settings, Upload tab: three synthetic destinations (Example S3 default, SFTP, WebDAV) with Add…, Edit…, Remove and Make Default | `—` | — |
| `S20-history-1120x850-selected-dark@723e65b.png` | dark | 1488×1179 | six synthetic entries, one selected, window 1120 x 850: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-1120x850-selected-light@723e65b.png` | light | 1488×1179 | six synthetic entries, one selected, window 1120 x 850: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-1280x800-selected-dark@723e65b.png` | dark | 1488×1179 | six synthetic entries, one selected, window 1280 x 800: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-1280x800-selected-light@723e65b.png` | light | 1488×1179 | six synthetic entries, one selected, window 1280 x 800: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-880x600-none-dark@723e65b.png` | dark | 1488×1179 | 880 x 600, nothing selected: the details column shows the summary instead of a blank hint; tiles sized to their preview | `—` | — |
| `S20-history-880x600-none-light@723e65b.png` | light | 1488×1179 | 880 x 600, nothing selected: the details column shows the summary instead of a blank hint; tiles sized to their preview | `—` | — |
| `S20-history-880x600-selected-dark@723e65b.png` | dark | 1488×1179 | six synthetic entries, one selected, window 880 x 600: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-880x600-selected-light@723e65b.png` | light | 1488×1179 | six synthetic entries, one selected, window 880 x 600: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-action-focus-dark@723e65b.png` | dark | 1488×1179 | keyboard focus on the Open action: the focus ring around its rounded fill (made first responder directly; real Tab reaches it only with Full Keyboard Access or Window > Focus Toolbar) | `—` | — |
| `S20-history-action-focus-light@723e65b.png` | light | 1488×1179 | keyboard focus on the Open action: the focus ring around its rounded fill (made first responder directly; real Tab reaches it only with Full Keyboard Access or Window > Focus Toolbar) | `—` | — |
| `S20-history-action-hover-dark@723e65b.png` | dark | 1488×1179 | one entry selected and the Copy action hovered: its own label 0.08 fill on the glass plate, the other actions at rest | `—` | — |
| `S20-history-action-hover-light@723e65b.png` | light | 1488×1179 | one entry selected and the Copy action hovered: its own label 0.08 fill on the glass plate, the other actions at rest | `—` | — |
| `S20-history-action-pressed-dark@723e65b.png` | dark | 1488×1179 | one entry selected and the Copy action held down (press bracket driven directly, not a real click): the pressed fill and glyph scale on its plate | `—` | — |
| `S20-history-action-pressed-light@723e65b.png` | light | 1488×1179 | one entry selected and the Copy action held down (press bracket driven directly, not a real click): the pressed fill and glyph scale on its plate | `—` | — |
| `S20-history-empty-dark@723e65b.png` | dark | 1488×1179 | History window with no entries | `—` | — |
| `S20-history-empty-light@723e65b.png` | light | 1488×1179 | History window with no entries | `—` | — |
| `S20-history-link-copied-dark@723e65b.png` | dark | 1488×1179 | a Shared entry selected after Copy Link: the footer confirms, and the destination link is cut in its middle with the full text in its tooltip | `—` | — |
| `S20-history-link-copied-light@723e65b.png` | light | 1488×1179 | a Shared entry selected after Copy Link: the footer confirms, and the destination link is cut in its middle with the full text in its tooltip | `—` | — |
| `S20-history-no-match-dark@723e65b.png` | dark | 1488×1179 | filters that match nothing at 880 x 600: centred message, no save hint | `—` | — |
| `S20-history-no-match-light@723e65b.png` | light | 1488×1179 | filters that match nothing at 880 x 600: centred message, no save hint | `—` | — |
| `S20-history-no-match-footer-dark@723e65b.png` | dark | 1488×1179 | filters that match nothing: the footer stays (0 of 6 items) and Clear filters offers the way out | `—` | — |
| `S20-history-no-match-footer-light@723e65b.png` | light | 1488×1179 | filters that match nothing: the footer stays (0 of 6 items) and Clear filters offers the way out | `—` | — |
| `S20-history-populated-dark@723e65b.png` | dark | 1488×1179 | six synthetic entries across dates and actions (Saved/Exported/Shared) | `—` | — |
| `S20-history-populated-light@723e65b.png` | light | 1488×1179 | six synthetic entries across dates and actions (Saved/Exported/Shared) | `—` | — |
| `S20-history-selected-dark@723e65b.png` | dark | 1488×1179 | one entry selected (action buttons enabled) | `—` | — |
| `S20-history-selected-light@723e65b.png` | light | 1488×1179 | one entry selected (action buttons enabled) | `—` | — |
| `S20-history-tile-hover-dark@723e65b.png` | dark | 1488×1179 | one entry selected (accent fill, border, check badge) and another tile hovered (label 0.08 fill) | `—` | — |
| `S20-history-tile-hover-light@723e65b.png` | light | 1488×1179 | one entry selected (accent fill, border, check badge) and another tile hovered (label 0.08 fill) | `—` | — |
| `S21-publish-cancelled-w1280-dark@723e65b.png` | dark | 1280×800 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w1280 | `layout/S21-publish-cancelled-w1280-dark@723e65b.json` | — |
| `S21-publish-cancelled-w1280-light@723e65b.png` | light | 1280×800 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w1280 | `layout/S21-publish-cancelled-w1280-light@723e65b.json` | — |
| `S21-publish-cancelled-w1440-dark@723e65b.png` | dark | 1440×900 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w1440 | `layout/S21-publish-cancelled-w1440-dark@723e65b.json` | — |
| `S21-publish-cancelled-w1440-light@723e65b.png` | light | 1440×900 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w1440 | `layout/S21-publish-cancelled-w1440-light@723e65b.json` | — |
| `S21-publish-cancelled-w980-dark@723e65b.png` | dark | 980×640 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w980 | `layout/S21-publish-cancelled-w980-dark@723e65b.json` | — |
| `S21-publish-cancelled-w980-light@723e65b.png` | light | 980×640 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w980 | `layout/S21-publish-cancelled-w980-light@723e65b.json` | — |
| `S21-publish-error-details-w1280-dark@723e65b.png` | dark | 1280×800 | the Details… sheet with the whole error (no second Error: under the title), at w1280 | `—` | — |
| `S21-publish-error-details-w1280-light@723e65b.png` | light | 1280×800 | the Details… sheet with the whole error (no second Error: under the title), at w1280 | `—` | — |
| `S21-publish-error-details-w1440-dark@723e65b.png` | dark | 1440×900 | the Details… sheet with the whole error (no second Error: under the title), at w1440 | `—` | — |
| `S21-publish-error-details-w1440-light@723e65b.png` | light | 1440×900 | the Details… sheet with the whole error (no second Error: under the title), at w1440 | `—` | — |
| `S21-publish-error-details-w980-dark@723e65b.png` | dark | 980×640 | the Details… sheet with the whole error (no second Error: under the title), at w980 | `—` | — |
| `S21-publish-error-details-w980-light@723e65b.png` | light | 980×640 | the Details… sheet with the whole error (no second Error: under the title), at w980 | `—` | — |
| `S21-publish-error-footer-w1280-dark@723e65b.png` | dark | 1280×800 | footer crop with the inline error, Retry and Details, at w1280 | `layout/S21-publish-error-footer-w1280-dark@723e65b.json` | — |
| `S21-publish-error-footer-w1280-light@723e65b.png` | light | 1280×800 | footer crop with the inline error, Retry and Details, at w1280 | `layout/S21-publish-error-footer-w1280-light@723e65b.json` | — |
| `S21-publish-error-footer-w1440-dark@723e65b.png` | dark | 1440×900 | footer crop with the inline error, Retry and Details, at w1440 | `layout/S21-publish-error-footer-w1440-dark@723e65b.json` | — |
| `S21-publish-error-footer-w1440-light@723e65b.png` | light | 1440×900 | footer crop with the inline error, Retry and Details, at w1440 | `layout/S21-publish-error-footer-w1440-light@723e65b.json` | — |
| `S21-publish-error-footer-w980-dark@723e65b.png` | dark | 980×640 | footer crop with the inline error, Retry and Details, at w980 | `layout/S21-publish-error-footer-w980-dark@723e65b.json` | — |
| `S21-publish-error-footer-w980-light@723e65b.png` | light | 980×640 | footer crop with the inline error, Retry and Details, at w980 | `layout/S21-publish-error-footer-w980-light@723e65b.json` | — |
| `S21-publish-error-w1280-dark@723e65b.png` | dark | 1280×800 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w1280 | `layout/S21-publish-error-w1280-dark@723e65b.json` | — |
| `S21-publish-error-w1280-light@723e65b.png` | light | 1280×800 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w1280 | `layout/S21-publish-error-w1280-light@723e65b.json` | — |
| `S21-publish-error-w1440-dark@723e65b.png` | dark | 1440×900 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w1440 | `layout/S21-publish-error-w1440-dark@723e65b.json` | — |
| `S21-publish-error-w1440-light@723e65b.png` | light | 1440×900 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w1440 | `layout/S21-publish-error-w1440-light@723e65b.json` | — |
| `S21-publish-error-w980-dark@723e65b.png` | dark | 980×640 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w980 | `layout/S21-publish-error-w980-dark@723e65b.json` | — |
| `S21-publish-error-w980-light@723e65b.png` | light | 980×640 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w980 | `layout/S21-publish-error-w980-light@723e65b.json` | — |
| `S21-publish-progress-footer-w1280-dark@723e65b.png` | dark | 1280×800 | footer crop during the upload, at w1280 | `layout/S21-publish-progress-footer-w1280-dark@723e65b.json` | — |
| `S21-publish-progress-footer-w1280-light@723e65b.png` | light | 1280×800 | footer crop during the upload, at w1280 | `layout/S21-publish-progress-footer-w1280-light@723e65b.json` | — |
| `S21-publish-progress-footer-w1440-dark@723e65b.png` | dark | 1440×900 | footer crop during the upload, at w1440 | `layout/S21-publish-progress-footer-w1440-dark@723e65b.json` | — |
| `S21-publish-progress-footer-w1440-light@723e65b.png` | light | 1440×900 | footer crop during the upload, at w1440 | `layout/S21-publish-progress-footer-w1440-light@723e65b.json` | — |
| `S21-publish-progress-footer-w980-dark@723e65b.png` | dark | 980×640 | footer crop during the upload, at w980 | `layout/S21-publish-progress-footer-w980-dark@723e65b.json` | — |
| `S21-publish-progress-footer-w980-light@723e65b.png` | light | 980×640 | footer crop during the upload, at w980 | `layout/S21-publish-progress-footer-w980-light@723e65b.json` | — |
| `S21-publish-progress-w1280-dark@723e65b.png` | dark | 1280×800 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w1280 | `layout/S21-publish-progress-w1280-dark@723e65b.json` | — |
| `S21-publish-progress-w1280-light@723e65b.png` | light | 1280×800 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w1280 | `layout/S21-publish-progress-w1280-light@723e65b.json` | — |
| `S21-publish-progress-w1440-dark@723e65b.png` | dark | 1440×900 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w1440 | `layout/S21-publish-progress-w1440-dark@723e65b.json` | — |
| `S21-publish-progress-w1440-light@723e65b.png` | light | 1440×900 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w1440 | `layout/S21-publish-progress-w1440-light@723e65b.json` | — |
| `S21-publish-progress-w980-dark@723e65b.png` | dark | 980×640 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w980 | `layout/S21-publish-progress-w980-dark@723e65b.json` | — |
| `S21-publish-progress-w980-light@723e65b.png` | light | 980×640 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w980 | `layout/S21-publish-progress-w980-light@723e65b.json` | — |
| `S21-publish-retrying-w1280-dark@723e65b.png` | dark | 1280×800 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w1280 | `layout/S21-publish-retrying-w1280-dark@723e65b.json` | — |
| `S21-publish-retrying-w1280-light@723e65b.png` | light | 1280×800 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w1280 | `layout/S21-publish-retrying-w1280-light@723e65b.json` | — |
| `S21-publish-retrying-w1440-dark@723e65b.png` | dark | 1440×900 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w1440 | `layout/S21-publish-retrying-w1440-dark@723e65b.json` | — |
| `S21-publish-retrying-w1440-light@723e65b.png` | light | 1440×900 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w1440 | `layout/S21-publish-retrying-w1440-light@723e65b.json` | — |
| `S21-publish-retrying-w980-dark@723e65b.png` | dark | 980×640 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w980 | `layout/S21-publish-retrying-w980-dark@723e65b.json` | — |
| `S21-publish-retrying-w980-light@723e65b.png` | light | 980×640 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w980 | `layout/S21-publish-retrying-w980-light@723e65b.json` | — |
| `S21-publish-success-footer-w1280-dark@723e65b.png` | dark | 1280×800 | footer crop with Link copied · the link, Open and Copy, at w1280 | `layout/S21-publish-success-footer-w1280-dark@723e65b.json` | — |
| `S21-publish-success-footer-w1280-light@723e65b.png` | light | 1280×800 | footer crop with Link copied · the link, Open and Copy, at w1280 | `layout/S21-publish-success-footer-w1280-light@723e65b.json` | — |
| `S21-publish-success-footer-w1440-dark@723e65b.png` | dark | 1440×900 | footer crop with Link copied · the link, Open and Copy, at w1440 | `layout/S21-publish-success-footer-w1440-dark@723e65b.json` | — |
| `S21-publish-success-footer-w1440-light@723e65b.png` | light | 1440×900 | footer crop with Link copied · the link, Open and Copy, at w1440 | `layout/S21-publish-success-footer-w1440-light@723e65b.json` | — |
| `S21-publish-success-footer-w980-dark@723e65b.png` | dark | 980×640 | footer crop with Link copied · the link, Open and Copy, at w980 | `layout/S21-publish-success-footer-w980-dark@723e65b.json` | — |
| `S21-publish-success-footer-w980-light@723e65b.png` | light | 980×640 | footer crop with Link copied · the link, Open and Copy, at w980 | `layout/S21-publish-success-footer-w980-light@723e65b.json` | — |
| `S21-publish-success-w1280-dark@723e65b.png` | dark | 1280×800 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w1280 | `layout/S21-publish-success-w1280-dark@723e65b.json` | — |
| `S21-publish-success-w1280-light@723e65b.png` | light | 1280×800 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w1280 | `layout/S21-publish-success-w1280-light@723e65b.json` | — |
| `S21-publish-success-w1440-dark@723e65b.png` | dark | 1440×900 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w1440 | `layout/S21-publish-success-w1440-dark@723e65b.json` | — |
| `S21-publish-success-w1440-light@723e65b.png` | light | 1440×900 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w1440 | `layout/S21-publish-success-w1440-light@723e65b.json` | — |
| `S21-publish-success-w980-dark@723e65b.png` | dark | 980×640 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w980 | `layout/S21-publish-success-w980-dark@723e65b.json` | — |
| `S21-publish-success-w980-light@723e65b.png` | light | 980×640 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w980 | `layout/S21-publish-success-w980-light@723e65b.json` | — |
| `S21-upload-menu-busy-dark@723e65b.png` | dark | 980×640 | destination choices while an upload runs (Cancel Upload offered) (glass panel) | `—` | — |
| `S21-upload-menu-busy-light@723e65b.png` | light | 980×640 | destination choices while an upload runs (Cancel Upload offered) (glass panel) | `—` | — |
| `S21-upload-menu-busy-dismissed-dark@723e65b.png` | dark | 980×640 | Upload panel dismissed with Escape | `layout/S21-upload-menu-busy-dismissed-dark@723e65b.json` | — |
| `S21-upload-menu-busy-dismissed-light@723e65b.png` | light | 980×640 | Upload panel dismissed with Escape | `layout/S21-upload-menu-busy-dismissed-light@723e65b.json` | — |
| `S22-photos-populated-dark@723e65b.png` | dark | 1488×1179 | Photos sheet over five synthetic fixture images in a throwaway folder (the real Photos library and Pictures folder are never read) | `—` | — |
| `S22-photos-populated-light@723e65b.png` | light | 1488×1179 | Photos sheet over five synthetic fixture images in a throwaway folder (the real Photos library and Pictures folder are never read) | `—` | — |
| `S22-photos-populated-in-context-dark@723e65b.png` | dark | 1488×1179 | Photos sheet over five synthetic fixture images in a throwaway folder (the real Photos library and Pictures folder are never read) (parent window + sheet composite) | `—` | — |
| `S22-photos-populated-in-context-light@723e65b.png` | light | 1488×1179 | Photos sheet over five synthetic fixture images in a throwaway folder (the real Photos library and Pictures folder are never read) (parent window + sheet composite) | `—` | — |
| `S23-canvas-text-context-open-dark@723e65b.png` | dark | 1488×1179 | canvas context menu on a text annotation | `layout/S23-canvas-text-context-open-dark@723e65b.json` | — |
| `S23-canvas-text-context-open-light@723e65b.png` | light | 1488×1179 | canvas context menu on a text annotation | `layout/S23-canvas-text-context-open-light@723e65b.json` | — |
| `S23-toolbox-menu-open-dark@723e65b.png` | dark | 1488×1179 | Toolbox choices open (a glass panel; rows open below its button, each with its icon) | `—` | — |
| `S23-toolbox-menu-open-light@723e65b.png` | light | 1488×1179 | Toolbox choices open (a glass panel; rows open below its button, each with its icon) | `—` | — |
| `S24-statusitem-highlighted-dark@723e65b.png` | dark | 1488×1179 | menu-bar icon, highlighted (menu open) (the real template icon on a stand-in menu-bar strip painted for this state and appearance; the real bar is not captured) | `—` | — |
| `S24-statusitem-highlighted-light@723e65b.png` | light | 1488×1179 | menu-bar icon, highlighted (menu open) (the real template icon on a stand-in menu-bar strip painted for this state and appearance; the real bar is not captured) | `—` | — |
| `S24-statusitem-normal-dark@723e65b.png` | dark | 1488×1179 | menu-bar icon, normal (the real template icon on a stand-in menu-bar strip painted for this state and appearance; the real bar is not captured) | `—` | — |
| `S24-statusitem-normal-light@723e65b.png` | light | 1488×1179 | menu-bar icon, normal (the real template icon on a stand-in menu-bar strip painted for this state and appearance; the real bar is not captured) | `—` | — |
| `S25-about-panel-dark@723e65b.png` | dark | 1488×1179 | app-owned About window: icon, name, version and build, credit line, license link | `—` | — |
| `S25-about-panel-light@723e65b.png` | light | 1488×1179 | app-owned About window: icon, name, version and build, credit line, license link | `—` | — |
| `S25-license-window-dark@723e65b.png` | dark | 1488×1179 | the MIT License window with the paragraphs reflowed to the window width | `—` | — |
| `S25-license-window-light@723e65b.png` | light | 1488×1179 | the MIT License window with the paragraphs reflowed to the window width | `—` | — |
| `S26-close-unsaved-dark@723e65b.png` | dark | 1488×1179 | Save your drawing? sheet (Save / Cancel / Don’t Save) | `—` | — |
| `S26-close-unsaved-light@723e65b.png` | light | 1488×1179 | Save your drawing? sheet (Save / Cancel / Don’t Save) | `—` | — |
| `S26-error-generic-dark@723e65b.png` | dark | 1488×1179 | generic error sheet | `—` | — |
| `S26-error-generic-light@723e65b.png` | light | 1488×1179 | generic error sheet | `—` | — |
| `S26-history-hide-dark@723e65b.png` | dark | 1488×1179 | Hide drawings from History? sheet | `—` | — |
| `S26-history-hide-light@723e65b.png` | light | 1488×1179 | Hide drawings from History? sheet | `—` | — |
| `S26-history-trash-dark@723e65b.png` | dark | 1488×1179 | Move archived drawings to Trash? sheet | `—` | — |
| `S26-history-trash-light@723e65b.png` | light | 1488×1179 | Move archived drawings to Trash? sheet | `—` | — |
| `S26-remove-destination-dark@723e65b.png` | dark | 1488×1179 | Remove “Example S3”? sheet on the Settings window (default destination): Cancel is the default, Remove is destructive | `—` | — |
| `S26-remove-destination-light@723e65b.png` | light | 1488×1179 | Remove “Example S3”? sheet on the Settings window (default destination): Cancel is the default, Remove is destructive | `—` | — |
| `S26-rename-dark@723e65b.png` | dark | 1488×1179 | Rename… sheet with text field | `—` | — |
| `S26-rename-light@723e65b.png` | light | 1488×1179 | Rename… sheet with text field | `—` | — |
| `S28-focus-footer-upload-dark@723e65b.png` | dark | 1488×1179 | Upload button is first responder | `layout/S28-focus-footer-upload-dark@723e65b.json` | — |
| `S28-focus-footer-upload-light@723e65b.png` | light | 1488×1179 | Upload button is first responder | `layout/S28-focus-footer-upload-light@723e65b.json` | — |
| `S28-focus-footer-zoom-dark@723e65b.png` | dark | 1488×1179 | Zoom popup is first responder | `layout/S28-focus-footer-zoom-dark@723e65b.json` | — |
| `S28-focus-footer-zoom-light@723e65b.png` | light | 1488×1179 | Zoom popup is first responder | `layout/S28-focus-footer-zoom-light@723e65b.json` | — |
| `S28-focus-topbar-hide-dark@723e65b.png` | dark | 1488×1179 | Hide button is first responder | `layout/S28-focus-topbar-hide-dark@723e65b.json` | — |
| `S28-focus-topbar-hide-light@723e65b.png` | light | 1488×1179 | Hide button is first responder | `layout/S28-focus-topbar-hide-light@723e65b.json` | — |
| `S28-focus-topbar-snap-dark@723e65b.png` | dark | 1488×1179 | Snap (primary) is first responder | `layout/S28-focus-topbar-snap-dark@723e65b.json` | — |
| `S28-focus-topbar-snap-light@723e65b.png` | light | 1488×1179 | Snap (primary) is first responder | `layout/S28-focus-topbar-snap-light@723e65b.json` | — |
| `S28-focus-topbar-tool-dark@723e65b.png` | dark | 1488×1179 | Brush tool button is first responder (focus ring) | `layout/S28-focus-topbar-tool-dark@723e65b.json` | — |
| `S28-focus-topbar-tool-light@723e65b.png` | light | 1488×1179 | Brush tool button is first responder (focus ring) | `layout/S28-focus-topbar-tool-light@723e65b.json` | — |
| `S29-drag-thumbnail-dark@723e65b.png` | dark | 1488×1179 | Drag Me thumbnail panel after the editor shrinks (not hovering) | `—` | — |
| `S29-drag-thumbnail-light@723e65b.png` | light | 1488×1179 | Drag Me thumbnail panel after the editor shrinks (not hovering) | `—` | — |
| `S29-drag-thumbnail-expand-dark@723e65b.png` | dark | 1488×1179 | clickToExpand overlay | `—` | — |
| `S29-drag-thumbnail-expand-light@723e65b.png` | light | 1488×1179 | clickToExpand overlay | `—` | — |
| `S29-help-bevel-dark@723e65b.png` | dark | 1488×1179 | OriginalHelpBevel HUD with a hover hint for a top-bar control (Rectangle tool) (feature is off by default); editor at the top of the screen, so the plate sits inside the window, clear of the title bar and both bars | `—` | — |
| `S29-help-bevel-light@723e65b.png` | light | 1488×1179 | OriginalHelpBevel HUD with a hover hint for a top-bar control (Rectangle tool) (feature is off by default); editor at the top of the screen, so the plate sits inside the window, clear of the title bar and both bars | `layout/S29-help-bevel-light@723e65b.json` | — |
| `S29-help-bevel-bottom-dark@723e65b.png` | dark | 1488×1179 | OriginalHelpBevel HUD with a hover hint for a bottom-bar control (Wipe) (feature is off by default); editor at the top of the screen, so the plate sits inside the window, clear of the title bar and both bars | `—` | — |
| `S29-help-bevel-bottom-light@723e65b.png` | light | 1488×1179 | OriginalHelpBevel HUD with a hover hint for a bottom-bar control (Wipe) (feature is off by default); editor at the top of the screen, so the plate sits inside the window, clear of the title bar and both bars | `layout/S29-help-bevel-bottom-light@723e65b.json` | — |
| `S29-help-bevel-hanging-dark@723e65b.png` | dark | 1488×1179 | the same hint with 140 pt free above the editor: the plate hangs from its top edge, behind it | `—` | — |
| `S29-help-bevel-hanging-light@723e65b.png` | light | 1488×1179 | the same hint with 140 pt free above the editor: the plate hangs from its top edge, behind it | `layout/S29-help-bevel-hanging-light@723e65b.json` | — |
| `S30-size-popover-w1280-dark@723e65b.png` | dark | 1280×800 | Size popover open below the pill at window width 1280x800, value 6.75, Brush tool | `layout/S30-size-popover-w1280-dark@723e65b.json` | — |
| `S30-size-popover-w1280-light@723e65b.png` | light | 1280×800 | Size popover open below the pill at window width 1280x800, value 6.75, Brush tool | `layout/S30-size-popover-w1280-light@723e65b.json` | — |
| `S30-size-popover-w980-dark@723e65b.png` | dark | 980×640 | Size popover open below the pill at window width 980xmin, value 6.75, Brush tool | `layout/S30-size-popover-w980-dark@723e65b.json` | — |
| `S30-size-popover-w980-light@723e65b.png` | light | 980×640 | Size popover open below the pill at window width 980xmin, value 6.75, Brush tool | `layout/S30-size-popover-w980-light@723e65b.json` | — |
| `S31-color-popover-custom-w1440-dark@723e65b.png` | dark | 1440×900 | Drawing colours popover open below the top-bar swatch at window width 1440, a custom colour current | `layout/S31-color-popover-custom-w1440-dark@723e65b.json` | — |
| `S31-color-popover-custom-w1440-light@723e65b.png` | light | 1440×900 | Drawing colours popover open below the top-bar swatch at window width 1440, a custom colour current | `layout/S31-color-popover-custom-w1440-light@723e65b.json` | — |
| `S31-color-popover-custom-w980-dark@723e65b.png` | dark | 980×640 | Drawing colours popover open below the top-bar swatch at window width 980, a custom colour current | `layout/S31-color-popover-custom-w980-dark@723e65b.json` | — |
| `S31-color-popover-custom-w980-light@723e65b.png` | light | 980×640 | Drawing colours popover open below the top-bar swatch at window width 980, a custom colour current | `layout/S31-color-popover-custom-w980-light@723e65b.json` | — |
| `S31-color-popover-only-custom-w1440-dark@723e65b.png` | dark | 1440×900 | the popover window alone, custom colour current | `—` | — |
| `S31-color-popover-only-custom-w1440-light@723e65b.png` | light | 1440×900 | the popover window alone, custom colour current | `—` | — |
| `S31-color-popover-only-custom-w980-dark@723e65b.png` | dark | 980×640 | the popover window alone, custom colour current | `—` | — |
| `S31-color-popover-only-custom-w980-light@723e65b.png` | light | 980×640 | the popover window alone, custom colour current | `—` | — |
| `S31-color-popover-only-w1440-dark@723e65b.png` | dark | 1440×900 | the popover window alone | `—` | — |
| `S31-color-popover-only-w1440-light@723e65b.png` | light | 1440×900 | the popover window alone | `—` | — |
| `S31-color-popover-only-w980-dark@723e65b.png` | dark | 980×640 | the popover window alone | `—` | — |
| `S31-color-popover-only-w980-light@723e65b.png` | light | 980×640 | the popover window alone | `—` | — |
| `S31-color-popover-w1440-dark@723e65b.png` | dark | 1440×900 | Drawing colours popover open below the top-bar swatch at window width 1440, a preset colour current | `layout/S31-color-popover-w1440-dark@723e65b.json` | — |
| `S31-color-popover-w1440-light@723e65b.png` | light | 1440×900 | Drawing colours popover open below the top-bar swatch at window width 1440, a preset colour current | `layout/S31-color-popover-w1440-light@723e65b.json` | — |
| `S31-color-popover-w980-dark@723e65b.png` | dark | 980×640 | Drawing colours popover open below the top-bar swatch at window width 980, a preset colour current | `layout/S31-color-popover-w980-dark@723e65b.json` | — |
| `S31-color-popover-w980-light@723e65b.png` | light | 980×640 | Drawing colours popover open below the top-bar swatch at window width 980, a preset colour current | `layout/S31-color-popover-w980-light@723e65b.json` | — |
| `S32-frame-large-w1280-dark@723e65b.png` | dark | 1280×800 | Frame mode at 1280x800: large shot at 100% so the canvas fills the viewport; Snap Frame + Cancel; no Original size checkbox | `layout/S32-frame-large-w1280-dark@723e65b.json` | — |
| `S32-frame-large-w1280-light@723e65b.png` | light | 1280×800 | Frame mode at 1280x800: large shot at 100% so the canvas fills the viewport; Snap Frame + Cancel; no Original size checkbox | `layout/S32-frame-large-w1280-light@723e65b.json` | — |
| `S32-frame-large-w980-dark@723e65b.png` | dark | 980×640 | Frame mode at 980xmin: large shot at 100% so the canvas fills the viewport; Snap Frame + Cancel; no Original size checkbox | `layout/S32-frame-large-w980-dark@723e65b.json` | — |
| `S32-frame-large-w980-light@723e65b.png` | light | 980×640 | Frame mode at 980xmin: large shot at 100% so the canvas fills the viewport; Snap Frame + Cancel; no Original size checkbox | `layout/S32-frame-large-w980-light@723e65b.json` | — |
| `S33-large-shot-w980-dark@723e65b.png` | dark | 980×640 | 2400x1500 shot at window width 980, Original size checkbox visible | `layout/S33-large-shot-w980-dark@723e65b.json` | — |
| `S33-large-shot-w980-light@723e65b.png` | light | 980×640 | 2400x1500 shot at window width 980, Original size checkbox visible | `layout/S33-large-shot-w980-light@723e65b.json` | — |
| `S33-large-shot-w980-bottombar-dark@723e65b.png` | dark | 980×640 | bottom bar only: Original size checkbox, status, groups | `layout/S33-large-shot-w980-bottombar-dark@723e65b.json` | — |
| `S33-large-shot-w980-bottombar-light@723e65b.png` | light | 980×640 | bottom bar only: Original size checkbox, status, groups | `layout/S33-large-shot-w980-bottombar-light@723e65b.json` | — |
| `S34-small-canvas-w1280-dark@723e65b.png` | dark | 1280×800 | 150x90 canvas at window 1280x800: equal margins left/right and top/bottom | `layout/S34-small-canvas-w1280-dark@723e65b.json` | — |
| `S34-small-canvas-w1280-light@723e65b.png` | light | 1280×800 | 150x90 canvas at window 1280x800: equal margins left/right and top/bottom | `layout/S34-small-canvas-w1280-light@723e65b.json` | — |
| `S34-small-canvas-w1440-dark@723e65b.png` | dark | 1440×900 | 150x90 canvas at window 1440x900: equal margins left/right and top/bottom | `layout/S34-small-canvas-w1440-dark@723e65b.json` | — |
| `S34-small-canvas-w1440-light@723e65b.png` | light | 1440×900 | 150x90 canvas at window 1440x900: equal margins left/right and top/bottom | `layout/S34-small-canvas-w1440-light@723e65b.json` | — |
| `S34-small-canvas-w980-dark@723e65b.png` | dark | 980×640 | 150x90 canvas at window 980xmin: equal margins left/right and top/bottom | `layout/S34-small-canvas-w980-dark@723e65b.json` | — |
| `S34-small-canvas-w980-light@723e65b.png` | light | 980×640 | 150x90 canvas at window 980xmin: equal margins left/right and top/bottom | `layout/S34-small-canvas-w980-light@723e65b.json` | — |
| `S35-large-canvas-w1280-dark@723e65b.png` | dark | 1280×800 | large shot at 100% in a 1280x800 window: canvas runs to the 12-pt margin and scrolls | `layout/S35-large-canvas-w1280-dark@723e65b.json` | — |
| `S35-large-canvas-w1280-light@723e65b.png` | light | 1280×800 | large shot at 100% in a 1280x800 window: canvas runs to the 12-pt margin and scrolls | `layout/S35-large-canvas-w1280-light@723e65b.json` | — |
| `S35-large-canvas-w980-dark@723e65b.png` | dark | 980×640 | large shot at 100% in a 980xmin window: canvas runs to the 12-pt margin and scrolls | `layout/S35-large-canvas-w980-dark@723e65b.json` | — |
| `S35-large-canvas-w980-light@723e65b.png` | light | 980×640 | large shot at 100% in a 980xmin window: canvas runs to the 12-pt margin and scrolls | `layout/S35-large-canvas-w980-light@723e65b.json` | — |
| `S36-selection-w1280-dark@723e65b.png` | dark | 1280×800 | rectangle selected with handles at window 1280x800; Color/Size/Font act on it | `layout/S36-selection-w1280-dark@723e65b.json` | — |
| `S36-selection-w1280-light@723e65b.png` | light | 1280×800 | rectangle selected with handles at window 1280x800; Color/Size/Font act on it | `layout/S36-selection-w1280-light@723e65b.json` | — |
| `S36-selection-w980-dark@723e65b.png` | dark | 980×640 | rectangle selected with handles at window 980xmin; Color/Size/Font act on it | `layout/S36-selection-w980-dark@723e65b.json` | — |
| `S36-selection-w980-light@723e65b.png` | light | 980×640 | rectangle selected with handles at window 980xmin; Color/Size/Font act on it | `layout/S36-selection-w980-light@723e65b.json` | — |
| `S36-text-editing-w1280-dark@723e65b.png` | dark | 1280×800 | text tool field editor active with typed text at window 1280x800 | `layout/S36-text-editing-w1280-dark@723e65b.json` | — |
| `S36-text-editing-w1280-light@723e65b.png` | light | 1280×800 | text tool field editor active with typed text at window 1280x800 | `layout/S36-text-editing-w1280-light@723e65b.json` | — |
| `S36-text-editing-w980-dark@723e65b.png` | dark | 980×640 | text tool field editor active with typed text at window 980xmin | `layout/S36-text-editing-w980-dark@723e65b.json` | — |
| `S36-text-editing-w980-light@723e65b.png` | light | 980×640 | text tool field editor active with typed text at window 980xmin | `layout/S36-text-editing-w980-light@723e65b.json` | — |
| `S37-format-jpg-w980-dark@723e65b.png` | dark | 980×640 | JPG selected at window width 980 with the large-shot bottom bar; footer group width 202.0 pt | `layout/S37-format-jpg-w980-dark@723e65b.json` | — |
| `S37-format-jpg-w980-light@723e65b.png` | light | 980×640 | JPG selected at window width 980 with the large-shot bottom bar; footer group width 202.0 pt | `layout/S37-format-jpg-w980-light@723e65b.json` | — |
| `S37-format-png-w980-dark@723e65b.png` | dark | 980×640 | PNG selected at window width 980 with the large-shot bottom bar; footer group width 202.0 pt | `layout/S37-format-png-w980-dark@723e65b.json` | — |
| `S37-format-png-w980-light@723e65b.png` | light | 980×640 | PNG selected at window width 980 with the large-shot bottom bar; footer group width 202.0 pt | `layout/S37-format-png-w980-light@723e65b.json` | — |
| `S38-tooltip-size-w980-dark@723e65b.png` | dark | 980×640 | the live Size tooltip below the Size pill (Size 7) | `layout/S38-tooltip-size-w980-dark@723e65b.json` | — |
| `S38-tooltip-size-w980-light@723e65b.png` | light | 980×640 | the live Size tooltip below the Size pill (Size 7) | `layout/S38-tooltip-size-w980-light@723e65b.json` | — |
| `S38-tooltip-snap-w980-dark@723e65b.png` | dark | 980×640 | the Snap tooltip below the Snap button; the long sentence wraps at 420 pt | `layout/S38-tooltip-snap-w980-dark@723e65b.json` | — |
| `S38-tooltip-snap-w980-light@723e65b.png` | light | 980×640 | the Snap tooltip below the Snap button; the long sentence wraps at 420 pt | `layout/S38-tooltip-snap-w980-light@723e65b.json` | — |
| `S38-tooltip-wipe-annotations-w980-dark@723e65b.png` | dark | 980×640 | Wipe over artwork: the plate says Remove annotations | `layout/S38-tooltip-wipe-annotations-w980-dark@723e65b.json` | — |
| `S38-tooltip-wipe-annotations-w980-light@723e65b.png` | light | 980×640 | Wipe over artwork: the plate says Remove annotations | `layout/S38-tooltip-wipe-annotations-w980-light@723e65b.json` | — |
| `S38-tooltip-wipe-blank-w980-dark@723e65b.png` | dark | 980×640 | Wipe on a blank canvas: dimmed, the plate says Nothing to clear | `layout/S38-tooltip-wipe-blank-w980-dark@723e65b.json` | — |
| `S38-tooltip-wipe-blank-w980-light@723e65b.png` | light | 980×640 | Wipe on a blank canvas: dimmed, the plate says Nothing to clear | `layout/S38-tooltip-wipe-blank-w980-light@723e65b.json` | — |
| `S38-tooltip-wipe-image-w980-dark@723e65b.png` | dark | 980×640 | Wipe over a snap alone: the plate says Clear image | `layout/S38-tooltip-wipe-image-w980-dark@723e65b.json` | — |
| `S38-tooltip-wipe-image-w980-light@723e65b.png` | light | 980×640 | Wipe over a snap alone: the plate says Clear image | `layout/S38-tooltip-wipe-image-w980-light@723e65b.json` | — |
| `S38-tooltip-zoom-w980-dark@723e65b.png` | dark | 980×640 | a bottom-bar control: the plate opens above the zoom face because there is no room below | `layout/S38-tooltip-zoom-w980-dark@723e65b.json` | — |
| `S38-tooltip-zoom-w980-light@723e65b.png` | light | 980×640 | a bottom-bar control: the plate opens above the zoom face because there is no room below | `layout/S38-tooltip-zoom-w980-light@723e65b.json` | — |
| `S39-discard-sheet-dark@723e65b.png` | dark | 1280×800 | Save your drawing? sheet over the titled window (Save / Cancel / Don’t Save) | `—` | — |
| `S39-discard-sheet-light@723e65b.png` | light | 1280×800 | Save your drawing? sheet over the titled window (Save / Cancel / Don’t Save) | `—` | — |
| `S39-titlebar-crop-w1280-dark@723e65b.png` | dark | 1280×800 | the title bar and top bar only, at w1280 | `layout/S39-titlebar-crop-w1280-dark@723e65b.json` | — |
| `S39-titlebar-crop-w1280-light@723e65b.png` | light | 1280×800 | the title bar and top bar only, at w1280 | `layout/S39-titlebar-crop-w1280-light@723e65b.json` | — |
| `S39-titlebar-crop-w980-dark@723e65b.png` | dark | 980×640 | the title bar and top bar only, at w980 | `layout/S39-titlebar-crop-w980-dark@723e65b.json` | — |
| `S39-titlebar-crop-w980-light@723e65b.png` | light | 980×640 | the title bar and top bar only, at w980 | `layout/S39-titlebar-crop-w980-light@723e65b.json` | — |
| `S39-titled-window-w1280-dark@723e65b.png` | dark | 1280×800 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w1280 | `layout/S39-titled-window-w1280-dark@723e65b.json` | — |
| `S39-titled-window-w1280-light@723e65b.png` | light | 1280×800 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w1280 | `layout/S39-titled-window-w1280-light@723e65b.json` | — |
| `S39-titled-window-w980-dark@723e65b.png` | dark | 980×640 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w980 | `layout/S39-titled-window-w980-dark@723e65b.json` | — |
| `S39-titled-window-w980-light@723e65b.png` | light | 980×640 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w980 | `layout/S39-titled-window-w980-light@723e65b.json` | — |
| `S39-upload-error-sheet-dark@723e65b.png` | dark | 1280×800 | Details… sheet after a stubbed failed upload (the error itself is inline), over the titled window | `—` | — |
| `S39-upload-error-sheet-light@723e65b.png` | light | 1280×800 | Details… sheet after a stubbed failed upload (the error itself is inline), over the titled window | `—` | — |
| `S40-border-crop-tool-dark@723e65b.png` | dark | 1084×768 | Crop tool chosen: the handles stay on without hover | `layout/S40-border-crop-tool-dark@723e65b.json` | — |
| `S40-border-crop-tool-light@723e65b.png` | light | 1084×768 | Crop tool chosen: the handles stay on without hover | `layout/S40-border-crop-tool-light@723e65b.json` | — |
| `S40-border-hover-dark@723e65b.png` | dark | 1084×768 | Pointer over the border: the accent outline and the four corner handles | `layout/S40-border-hover-dark@723e65b.json` | — |
| `S40-border-hover-light@723e65b.png` | light | 1084×768 | Pointer over the border: the accent outline and the four corner handles | `layout/S40-border-hover-light@723e65b.json` | — |
| `S40-border-rest-dark@723e65b.png` | dark | 1084×768 | Canvas border at rest: a separator hairline, no handles | `layout/S40-border-rest-dark@723e65b.json` | — |
| `S40-border-rest-light@723e65b.png` | light | 1084×768 | Canvas border at rest: a separator hairline, no handles | `layout/S40-border-rest-light@723e65b.json` | — |
| `S40-drag-focus-dark@723e65b.png` | dark | 980×640 | Drag well keyboard-focused (Space or Return opens the Export panel) | `layout/S40-drag-focus-dark@723e65b.json` | — |
| `S40-drag-focus-light@723e65b.png` | light | 980×640 | Drag well keyboard-focused (Space or Return opens the Export panel) | `layout/S40-drag-focus-light@723e65b.json` | — |
| `S40-drag-hover-dark@723e65b.png` | dark | 980×640 | Drag well hovered: the cell takes the label 0.08 fill; the pointer is an open hand | `layout/S40-drag-hover-dark@723e65b.json` | — |
| `S40-drag-hover-light@723e65b.png` | light | 980×640 | Drag well hovered: the cell takes the label 0.08 fill; the pointer is an open hand | `layout/S40-drag-hover-light@723e65b.json` | — |
| `S40-drag-pressed-dark@723e65b.png` | dark | 980×640 | Drag well held: the cell takes the 0.16 fill; the pointer is a closed hand | `layout/S40-drag-pressed-dark@723e65b.json` | — |
| `S40-drag-pressed-light@723e65b.png` | light | 980×640 | Drag well held: the cell takes the 0.16 fill; the pointer is a closed hand | `layout/S40-drag-pressed-light@723e65b.json` | — |
| `S40-drag-rest-dark@723e65b.png` | dark | 980×640 | Drag well at rest: the open-hand glyph, no plate | `layout/S40-drag-rest-dark@723e65b.json` | — |
| `S40-drag-rest-light@723e65b.png` | light | 980×640 | Drag well at rest: the open-hand glyph, no plate | `layout/S40-drag-rest-light@723e65b.json` | — |
| `S40-size-pill-disabled-dark@723e65b.png` | dark | 980×640 | Size pill disabled: stroke dimmed to 0.38, no fill, not draggable | `layout/S40-size-pill-disabled-dark@723e65b.json` | — |
| `S40-size-pill-disabled-light@723e65b.png` | light | 980×640 | Size pill disabled: stroke dimmed to 0.38, no fill, not draggable | `layout/S40-size-pill-disabled-light@723e65b.json` | — |
| `S40-size-pill-focus-dark@723e65b.png` | dark | 980×640 | Size pill keyboard-focused | `layout/S40-size-pill-focus-dark@723e65b.json` | — |
| `S40-size-pill-focus-light@723e65b.png` | light | 980×640 | Size pill keyboard-focused | `layout/S40-size-pill-focus-light@723e65b.json` | — |
| `S40-size-pill-hover-dark@723e65b.png` | dark | 980×640 | Size pill hovered: the cell takes the label 0.08 fill | `layout/S40-size-pill-hover-dark@723e65b.json` | — |
| `S40-size-pill-hover-light@723e65b.png` | light | 980×640 | Size pill hovered: the cell takes the label 0.08 fill | `layout/S40-size-pill-hover-light@723e65b.json` | — |
| `S40-size-pill-pressed-dark@723e65b.png` | dark | 980×640 | Size pill pressed: the cell takes the 0.16 fill and the stroke is drawn 0.96 shorter | `layout/S40-size-pill-pressed-dark@723e65b.json` | — |
| `S40-size-pill-pressed-light@723e65b.png` | light | 980×640 | Size pill pressed: the cell takes the 0.16 fill and the stroke is drawn 0.96 shorter | `layout/S40-size-pill-pressed-light@723e65b.json` | — |
| `S40-size-pill-rest-dark@723e65b.png` | dark | 980×640 | Size pill at rest: the stroke is the current thickness (6.75) | `layout/S40-size-pill-rest-dark@723e65b.json` | — |
| `S40-size-pill-rest-light@723e65b.png` | light | 980×640 | Size pill at rest: the stroke is the current thickness (6.75) | `layout/S40-size-pill-rest-light@723e65b.json` | — |
| `S40-size-preset-hover-dark@723e65b.png` | dark | 980×640 | Size popover, the smallest preset hovered (command hover fill) beside the selected one | `layout/S40-size-preset-hover-dark@723e65b.json` | — |
| `S40-size-preset-hover-light@723e65b.png` | light | 980×640 | Size popover, the smallest preset hovered (command hover fill) beside the selected one | `layout/S40-size-preset-hover-light@723e65b.json` | — |
| `S40-size-track-hover-dark@723e65b.png` | dark | 980×640 | Size popover, pointer over the track: the knob grows to 1.15 | `layout/S40-size-track-hover-dark@723e65b.json` | — |
| `S40-size-track-hover-light@723e65b.png` | light | 980×640 | Size popover, pointer over the track: the knob grows to 1.15 | `layout/S40-size-track-hover-light@723e65b.json` | — |
| `S40-size-track-pressed-dark@723e65b.png` | dark | 980×640 | Size popover, knob held: the knob at 1.25 and an accent 0.3 wash over the track | `layout/S40-size-track-pressed-dark@723e65b.json` | — |
| `S40-size-track-pressed-light@723e65b.png` | light | 980×640 | Size popover, knob held: the knob at 1.25 and an accent 0.3 wash over the track | `layout/S40-size-track-pressed-light@723e65b.json` | — |
| `S40-snap-disabled-dark@723e65b.png` | dark | 980×640 | Snap disabled: the accent dimmed to 0.38 | `layout/S40-snap-disabled-dark@723e65b.json` | — |
| `S40-snap-disabled-light@723e65b.png` | light | 980×640 | Snap disabled: the accent dimmed to 0.38 | `layout/S40-snap-disabled-light@723e65b.json` | — |
| `S40-snap-focus-dark@723e65b.png` | dark | 980×640 | Snap keyboard-focused | `layout/S40-snap-focus-dark@723e65b.json` | — |
| `S40-snap-focus-light@723e65b.png` | light | 980×640 | Snap keyboard-focused | `layout/S40-snap-focus-light@723e65b.json` | — |
| `S40-snap-hover-dark@723e65b.png` | dark | 980×640 | Snap hovered: the accent brightened 8 % | `layout/S40-snap-hover-dark@723e65b.json` | — |
| `S40-snap-hover-light@723e65b.png` | light | 980×640 | Snap hovered: the accent brightened 8 % | `layout/S40-snap-hover-light@723e65b.json` | — |
| `S40-snap-pressed-dark@723e65b.png` | dark | 980×640 | Snap pressed: the accent darkened 12 % and the glyph at 0.96 | `layout/S40-snap-pressed-dark@723e65b.json` | — |
| `S40-snap-pressed-light@723e65b.png` | light | 980×640 | Snap pressed: the accent darkened 12 % and the glyph at 0.96 | `layout/S40-snap-pressed-light@723e65b.json` | — |
| `S40-snap-rest-dark@723e65b.png` | dark | 980×640 | Snap at rest: opaque accent fill, glyph colour computed against it | `layout/S40-snap-rest-dark@723e65b.json` | — |
| `S40-snap-rest-light@723e65b.png` | light | 980×640 | Snap at rest: opaque accent fill, glyph colour computed against it | `layout/S40-snap-rest-light@723e65b.json` | — |
| `S40-swatch-states-dark@723e65b.png` | dark | 980×640 | Colour popover: Red selected (3 pt accent outline and check glyph), Blue hovered (label 0.5 outline), Translucent gray pressed (0.16 fill) | `—` | — |
| `S40-swatch-states-light@723e65b.png` | light | 980×640 | Colour popover: Red selected (3 pt accent outline and check glyph), Blue hovered (label 0.5 outline), Translucent gray pressed (0.16 fill) | `—` | — |
| `S40-toggle-disabled-dark@723e65b.png` | dark | 980×640 | PNG / JPG disabled: both segments' content at 0.38 | `layout/S40-toggle-disabled-dark@723e65b.json` | — |
| `S40-toggle-disabled-light@723e65b.png` | light | 980×640 | PNG / JPG disabled: both segments' content at 0.38 | `layout/S40-toggle-disabled-light@723e65b.json` | — |
| `S40-toggle-focus-dark@723e65b.png` | dark | 980×640 | PNG / JPG keyboard-focused (Left, Right and Space change the format) | `layout/S40-toggle-focus-dark@723e65b.json` | — |
| `S40-toggle-focus-light@723e65b.png` | light | 980×640 | PNG / JPG keyboard-focused (Left, Right and Space change the format) | `layout/S40-toggle-focus-light@723e65b.json` | — |
| `S40-toggle-hover-dark@723e65b.png` | dark | 980×640 | PNG selected, JPG hovered: label 0.08 plate | `layout/S40-toggle-hover-dark@723e65b.json` | — |
| `S40-toggle-hover-light@723e65b.png` | light | 980×640 | PNG selected, JPG hovered: label 0.08 plate | `layout/S40-toggle-hover-light@723e65b.json` | — |
| `S40-toggle-jpg-dark@723e65b.png` | dark | 980×640 | PNG / JPG with JPG selected | `layout/S40-toggle-jpg-dark@723e65b.json` | — |
| `S40-toggle-jpg-light@723e65b.png` | light | 980×640 | PNG / JPG with JPG selected | `layout/S40-toggle-jpg-light@723e65b.json` | — |
| `S40-toggle-png-dark@723e65b.png` | dark | 980×640 | PNG / JPG with PNG selected: accent 0.20 plate, 1 pt border, bodyStrong text; JPG on its faint plate | `layout/S40-toggle-png-dark@723e65b.json` | — |
| `S40-toggle-png-light@723e65b.png` | light | 980×640 | PNG / JPG with PNG selected: accent 0.20 plate, 1 pt border, bodyStrong text; JPG on its faint plate | `layout/S40-toggle-png-light@723e65b.json` | — |
| `S40-toggle-pressed-dark@723e65b.png` | dark | 980×640 | PNG selected, JPG pressed: label 0.16 plate | `layout/S40-toggle-pressed-dark@723e65b.json` | — |
| `S40-toggle-pressed-light@723e65b.png` | light | 980×640 | PNG selected, JPG pressed: label 0.16 plate | `layout/S40-toggle-pressed-light@723e65b.json` | — |
| `S40-tool-disabled-dark@723e65b.png` | dark | 980×640 | Rectangle tool disabled: no fill, content dimmed to 0.38 | `layout/S40-tool-disabled-dark@723e65b.json` | — |
| `S40-tool-disabled-light@723e65b.png` | light | 980×640 | Rectangle tool disabled: no fill, content dimmed to 0.38 | `layout/S40-tool-disabled-light@723e65b.json` | — |
| `S40-tool-focus-dark@723e65b.png` | dark | 980×640 | Rectangle tool keyboard-focused: AppKit's focus ring drawn through the button's own rounded mask | `layout/S40-tool-focus-dark@723e65b.json` | — |
| `S40-tool-focus-light@723e65b.png` | light | 980×640 | Rectangle tool keyboard-focused: AppKit's focus ring drawn through the button's own rounded mask | `layout/S40-tool-focus-light@723e65b.json` | — |
| `S40-tool-hover-dark@723e65b.png` | dark | 980×640 | Rectangle tool hovered: a label 0.08 fill (0.16 under Increase Contrast); Brush still selected | `layout/S40-tool-hover-dark@723e65b.json` | — |
| `S40-tool-hover-light@723e65b.png` | light | 980×640 | Rectangle tool hovered: a label 0.08 fill (0.16 under Increase Contrast); Brush still selected | `layout/S40-tool-hover-light@723e65b.json` | — |
| `S40-tool-pressed-dark@723e65b.png` | dark | 980×640 | Rectangle tool pressed: a label 0.16 fill (0.28 under Increase Contrast) and the glyph drawn at 0.96 | `layout/S40-tool-pressed-dark@723e65b.json` | — |
| `S40-tool-pressed-light@723e65b.png` | light | 980×640 | Rectangle tool pressed: a label 0.16 fill (0.28 under Increase Contrast) and the glyph drawn at 0.96 | `layout/S40-tool-pressed-light@723e65b.json` | — |
| `S40-tool-selected-focus-dark@723e65b.png` | dark | 980×640 | Brush (selected) keyboard-focused: the ring around the selection fill | `layout/S40-tool-selected-focus-dark@723e65b.json` | — |
| `S40-tool-selected-focus-light@723e65b.png` | light | 980×640 | Brush (selected) keyboard-focused: the ring around the selection fill | `layout/S40-tool-selected-focus-light@723e65b.json` | — |
| `S40-tool-selected-hover-dark@723e65b.png` | dark | 980×640 | Brush (selected) hovered: hover does not wash out the selection | `layout/S40-tool-selected-hover-dark@723e65b.json` | — |
| `S40-tool-selected-hover-light@723e65b.png` | light | 980×640 | Brush (selected) hovered: hover does not wash out the selection | `layout/S40-tool-selected-hover-light@723e65b.json` | — |
| `S40-tool-selected-pressed-dark@723e65b.png` | dark | 980×640 | Brush (selected) pressed: the selected fill deepens by 0.12 | `layout/S40-tool-selected-pressed-dark@723e65b.json` | — |
| `S40-tool-selected-pressed-light@723e65b.png` | light | 980×640 | Brush (selected) pressed: the selected fill deepens by 0.12 | `layout/S40-tool-selected-pressed-light@723e65b.json` | — |
| `S40-tool-selected-rest-dark@723e65b.png` | dark | 980×640 | Brush selected (accent 0.20 fill, 1 pt accent border, computed glyph colour; a 2 x 16 pt capsule under Differentiate Without Color); the other nine tools at rest | `layout/S40-tool-selected-rest-dark@723e65b.json` | — |
| `S40-tool-selected-rest-light@723e65b.png` | light | 980×640 | Brush selected (accent 0.20 fill, 1 pt accent border, computed glyph colour; a 2 x 16 pt capsule under Differentiate Without Color); the other nine tools at rest | `layout/S40-tool-selected-rest-light@723e65b.json` | — |
| `S40-undo-focus-dark@723e65b.png` | dark | 980×640 | Undo keyboard-focused | `layout/S40-undo-focus-dark@723e65b.json` | — |
| `S40-undo-focus-light@723e65b.png` | light | 980×640 | Undo keyboard-focused | `layout/S40-undo-focus-light@723e65b.json` | — |
| `S40-undo-hover-dark@723e65b.png` | dark | 980×640 | Undo hovered: label 0.08 fill | `layout/S40-undo-hover-dark@723e65b.json` | — |
| `S40-undo-hover-light@723e65b.png` | light | 980×640 | Undo hovered: label 0.08 fill | `layout/S40-undo-hover-light@723e65b.json` | — |
| `S40-undo-wipe-disabled-dark@723e65b.png` | dark | 980×640 | Undo and Wipe disabled: no fill, content at 0.38 | `layout/S40-undo-wipe-disabled-dark@723e65b.json` | — |
| `S40-undo-wipe-disabled-light@723e65b.png` | light | 980×640 | Undo and Wipe disabled: no fill, content at 0.38 | `layout/S40-undo-wipe-disabled-light@723e65b.json` | — |
| `S40-wipe-pressed-dark@723e65b.png` | dark | 980×640 | Wipe pressed: label 0.16 fill, glyph at 0.96 | `layout/S40-wipe-pressed-dark@723e65b.json` | — |
| `S40-wipe-pressed-light@723e65b.png` | light | 980×640 | Wipe pressed: label 0.16 fill, glyph at 0.96 | `layout/S40-wipe-pressed-light@723e65b.json` | — |
| `S50-toolbox-chosen-dark@723e65b.png` | dark | 1488×1179 | Toolbox panel with a filled rectangle selected: the toggle and tool rows that are on | `—` | — |
| `S50-toolbox-chosen-light@723e65b.png` | light | 1488×1179 | Toolbox panel with a filled rectangle selected: the toggle and tool rows that are on | `—` | — |
| `S50-toolbox-disabled-dark@723e65b.png` | dark | 1488×1179 | Toolbox panel while a frame capture is in progress (validation refuses the style rows); disabled row 15 (Filled Shapes) hovered and offered focus; the arrow keys walked past it | `—` | — |
| `S50-toolbox-disabled-light@723e65b.png` | light | 1488×1179 | Toolbox panel while a frame capture is in progress (validation refuses the style rows); disabled row 15 (Filled Shapes) hovered and offered focus; the arrow keys walked past it | `—` | — |
| `S50-toolbox-dismissed-dark@723e65b.png` | dark | 1488×1179 | Toolbox panel dismissed with Escape: gone, focus back on the Toolbox button | `layout/S50-toolbox-dismissed-dark@723e65b.json` | — |
| `S50-toolbox-dismissed-light@723e65b.png` | light | 1488×1179 | Toolbox panel dismissed with Escape: gone, focus back on the Toolbox button | `layout/S50-toolbox-dismissed-light@723e65b.json` | — |
| `S50-toolbox-focus-dark@723e65b.png` | dark | 1488×1179 | Toolbox panel open on a drawing with nothing selected; keyboard focus on row 0 (Save to History) | `—` | — |
| `S50-toolbox-focus-light@723e65b.png` | light | 1488×1179 | Toolbox panel open on a drawing with nothing selected; keyboard focus on row 0 (Save to History) | `—` | — |
| `S50-toolbox-hover-dark@723e65b.png` | dark | 1488×1179 | Toolbox panel open on a drawing with nothing selected; row 1 (Export…) hovered | `—` | — |
| `S50-toolbox-hover-light@723e65b.png` | light | 1488×1179 | Toolbox panel open on a drawing with nothing selected; row 1 (Export…) hovered | `—` | — |
| `S50-toolbox-rest-dark@723e65b.png` | dark | 1488×1179 | Toolbox panel open on a drawing with nothing selected | `—` | — |
| `S50-toolbox-rest-light@723e65b.png` | light | 1488×1179 | Toolbox panel open on a drawing with nothing selected | `—` | — |
| `S50-toolbox-rest-only-dark@723e65b.png` | dark | 1488×1179 | Toolbox panel open on a drawing with nothing selected (the panel window alone) | `—` | — |
| `S50-toolbox-rest-only-light@723e65b.png` | light | 1488×1179 | Toolbox panel open on a drawing with nothing selected (the panel window alone) | `—` | — |
| `S51-zoom-actual-size-dark@723e65b.png` | dark | 1662×1179 | Zoom panel while Actual Size is on: the Actual Size toggle row is chosen and the face shows Actual | `—` | — |
| `S51-zoom-actual-size-light@723e65b.png` | light | 1662×1179 | Zoom panel while Actual Size is on: the Actual Size toggle row is chosen and the face shows Actual | `—` | — |
| `S51-zoom-chosen-dark@723e65b.png` | dark | 1488×1179 | Zoom panel: the computed Fit row is the chosen row | `—` | — |
| `S51-zoom-chosen-light@723e65b.png` | light | 1488×1179 | Zoom panel: the computed Fit row is the chosen row | `—` | — |
| `S51-zoom-dismissed-dark@723e65b.png` | dark | 1488×1179 | Zoom panel dismissed with Escape: gone, focus back on the zoom button | `layout/S51-zoom-dismissed-dark@723e65b.json` | — |
| `S51-zoom-dismissed-light@723e65b.png` | light | 1488×1179 | Zoom panel dismissed with Escape: gone, focus back on the zoom button | `layout/S51-zoom-dismissed-light@723e65b.json` | — |
| `S51-zoom-focus-dark@723e65b.png` | dark | 1488×1179 | Zoom panel open with a computed Fit row chosen; keyboard focus on row 0 (Fit, 100%) | `—` | — |
| `S51-zoom-focus-light@723e65b.png` | light | 1488×1179 | Zoom panel open with a computed Fit row chosen; keyboard focus on row 0 (Fit, 100%) | `—` | — |
| `S51-zoom-hover-dark@723e65b.png` | dark | 1488×1179 | Zoom panel open with a computed Fit row chosen; row 1 (25%) hovered | `—` | — |
| `S51-zoom-hover-light@723e65b.png` | light | 1488×1179 | Zoom panel open with a computed Fit row chosen; row 1 (25%) hovered | `—` | — |
| `S51-zoom-rest-dark@723e65b.png` | dark | 1488×1179 | Zoom panel open with a computed Fit row chosen | `—` | — |
| `S51-zoom-rest-light@723e65b.png` | light | 1488×1179 | Zoom panel open with a computed Fit row chosen | `—` | — |
| `S51-zoom-rest-only-dark@723e65b.png` | dark | 1488×1179 | Zoom panel open with a computed Fit row chosen (the panel window alone) | `—` | — |
| `S51-zoom-rest-only-light@723e65b.png` | light | 1488×1179 | Zoom panel open with a computed Fit row chosen (the panel window alone) | `—` | — |
| `S52-upload-busy-dark@723e65b.png` | dark | 1488×1179 | Upload panel while an upload runs: Cancel Upload leads the rows | `—` | — |
| `S52-upload-busy-light@723e65b.png` | light | 1488×1179 | Upload panel while an upload runs: Cancel Upload leads the rows | `—` | — |
| `S52-upload-chosen-dark@723e65b.png` | dark | 1488×1179 | Upload panel after the default was switched to the second destination: the check follows it | `—` | — |
| `S52-upload-chosen-light@723e65b.png` | light | 1488×1179 | Upload panel after the default was switched to the second destination: the check follows it | `—` | — |
| `S52-upload-dismissed-dark@723e65b.png` | dark | 1488×1179 | Upload panel dismissed with Escape: gone, focus back on the Upload button | `layout/S52-upload-dismissed-dark@723e65b.json` | — |
| `S52-upload-dismissed-light@723e65b.png` | light | 1488×1179 | Upload panel dismissed with Escape: gone, focus back on the Upload button | `layout/S52-upload-dismissed-light@723e65b.json` | — |
| `S52-upload-empty-dark@723e65b.png` | dark | 1488×1179 | Upload panel with no destination saved: the disabled No destination configured row, Destination Settings… and Share with macOS… | `—` | — |
| `S52-upload-empty-light@723e65b.png` | light | 1488×1179 | Upload panel with no destination saved: the disabled No destination configured row, Destination Settings… and Share with macOS… | `—` | — |
| `S52-upload-focus-dark@723e65b.png` | dark | 1488×1179 | Upload panel with three fake destinations, the default checked; keyboard focus on row 0 (Example S3) | `—` | — |
| `S52-upload-focus-light@723e65b.png` | light | 1488×1179 | Upload panel with three fake destinations, the default checked; keyboard focus on row 0 (Example S3) | `—` | — |
| `S52-upload-hover-dark@723e65b.png` | dark | 1488×1179 | Upload panel with three fake destinations, the default checked; row 1 (Example SFTP) hovered | `—` | — |
| `S52-upload-hover-light@723e65b.png` | light | 1488×1179 | Upload panel with three fake destinations, the default checked; row 1 (Example SFTP) hovered | `—` | — |
| `S52-upload-rest-dark@723e65b.png` | dark | 1488×1179 | Upload panel with three fake destinations, the default checked | `—` | — |
| `S52-upload-rest-light@723e65b.png` | light | 1488×1179 | Upload panel with three fake destinations, the default checked | `—` | — |
| `S52-upload-rest-only-dark@723e65b.png` | dark | 1488×1179 | Upload panel with three fake destinations, the default checked (the panel window alone) | `—` | — |
| `S52-upload-rest-only-light@723e65b.png` | light | 1488×1179 | Upload panel with three fake destinations, the default checked (the panel window alone) | `—` | — |
| `S53-color-custom-dark@723e65b.png` | dark | 1488×1179 | Colour panel with a custom colour chosen: the Custom color… row carries the chip and the check | `—` | — |
| `S53-color-custom-light@723e65b.png` | light | 1488×1179 | Colour panel with a custom colour chosen: the Custom color… row carries the chip and the check | `—` | — |
| `S53-color-dismissed-dark@723e65b.png` | dark | 1488×1179 | Colour panel dismissed with Escape: gone, focus back on the colour swatch | `layout/S53-color-dismissed-dark@723e65b.json` | — |
| `S53-color-dismissed-light@723e65b.png` | light | 1488×1179 | Colour panel dismissed with Escape: gone, focus back on the colour swatch | `layout/S53-color-dismissed-light@723e65b.json` | — |
| `S53-color-focus-dark@723e65b.png` | dark | 1488×1179 | Colour panel open with the first preset chosen; keyboard focus on row 0 (Red) | `—` | — |
| `S53-color-focus-light@723e65b.png` | light | 1488×1179 | Colour panel open with the first preset chosen; keyboard focus on row 0 (Red) | `—` | — |
| `S53-color-hover-dark@723e65b.png` | dark | 1488×1179 | Colour panel open with the first preset chosen; row 1 (Yellow) hovered | `—` | — |
| `S53-color-hover-light@723e65b.png` | light | 1488×1179 | Colour panel open with the first preset chosen; row 1 (Yellow) hovered | `—` | — |
| `S53-color-rest-dark@723e65b.png` | dark | 1488×1179 | Colour panel open with the first preset chosen | `—` | — |
| `S53-color-rest-light@723e65b.png` | light | 1488×1179 | Colour panel open with the first preset chosen | `—` | — |
| `S53-color-rest-only-dark@723e65b.png` | dark | 1488×1179 | Colour panel open with the first preset chosen (the panel window alone) | `—` | — |
| `S53-color-rest-only-light@723e65b.png` | light | 1488×1179 | Colour panel open with the first preset chosen (the panel window alone) | `—` | — |
| `S54-size-dismissed-dark@723e65b.png` | dark | 1488×1179 | Size panel dismissed with Escape: gone, focus back on the size pill | `layout/S54-size-dismissed-dark@723e65b.json` | — |
| `S54-size-dismissed-light@723e65b.png` | light | 1488×1179 | Size panel dismissed with Escape: gone, focus back on the size pill | `layout/S54-size-dismissed-light@723e65b.json` | — |
| `S54-size-focus-dark@723e65b.png` | dark | 1488×1179 | Size panel open with a preset size chosen; keyboard focus on row 0 (Size 2) | `—` | — |
| `S54-size-focus-light@723e65b.png` | light | 1488×1179 | Size panel open with a preset size chosen; keyboard focus on row 0 (Size 2) | `—` | — |
| `S54-size-hover-dark@723e65b.png` | dark | 1488×1179 | Size panel open with a preset size chosen; row 1 (Size 4) hovered | `—` | — |
| `S54-size-hover-light@723e65b.png` | light | 1488×1179 | Size panel open with a preset size chosen; row 1 (Size 4) hovered | `—` | — |
| `S54-size-pressed-dark@723e65b.png` | dark | 1488×1179 | Size panel with the track held down | `—` | — |
| `S54-size-pressed-light@723e65b.png` | light | 1488×1179 | Size panel with the track held down | `—` | — |
| `S54-size-rest-dark@723e65b.png` | dark | 1488×1179 | Size panel open with a preset size chosen | `—` | — |
| `S54-size-rest-light@723e65b.png` | light | 1488×1179 | Size panel open with a preset size chosen | `—` | — |
| `S54-size-rest-only-dark@723e65b.png` | dark | 1488×1179 | Size panel open with a preset size chosen (the panel window alone) | `—` | — |
| `S54-size-rest-only-light@723e65b.png` | light | 1488×1179 | Size panel open with a preset size chosen (the panel window alone) | `—` | — |
| `S55-history-category-focus-dark@723e65b.png` | dark | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate; keyboard focus on row 0 (All) | `—` | — |
| `S55-history-category-focus-light@723e65b.png` | light | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate; keyboard focus on row 0 (All) | `—` | — |
| `S55-history-category-hover-dark@723e65b.png` | dark | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate; row 1 (Shared) hovered | `—` | — |
| `S55-history-category-hover-light@723e65b.png` | light | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate; row 1 (Shared) hovered | `—` | — |
| `S55-history-category-rest-dark@723e65b.png` | dark | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate | `—` | — |
| `S55-history-category-rest-light@723e65b.png` | light | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate | `—` | — |
| `S55-history-date-chosen-dark@723e65b.png` | dark | 1488×1179 | History: the Date filter panel with its chosen row | `—` | — |
| `S55-history-date-chosen-light@723e65b.png` | light | 1488×1179 | History: the Date filter panel with its chosen row | `—` | — |
| `S55-history-date-dismissed-dark@723e65b.png` | dark | 1488×1179 | Date filter choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S55-history-date-dismissed-light@723e65b.png` | light | 1488×1179 | Date filter choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S55-history-date-focus-dark@723e65b.png` | dark | 1488×1179 | History: the Date filter choices open; keyboard focus on row 0 (All dates) | `—` | — |
| `S55-history-date-focus-light@723e65b.png` | light | 1488×1179 | History: the Date filter choices open; keyboard focus on row 0 (All dates) | `—` | — |
| `S55-history-date-hover-dark@723e65b.png` | dark | 1488×1179 | History: the Date filter choices open; row 1 (Last hour) hovered | `—` | — |
| `S55-history-date-hover-light@723e65b.png` | light | 1488×1179 | History: the Date filter choices open; row 1 (Last hour) hovered | `—` | — |
| `S55-history-date-rest-dark@723e65b.png` | dark | 1488×1179 | History: the Date filter choices open | `—` | — |
| `S55-history-date-rest-light@723e65b.png` | light | 1488×1179 | History: the Date filter choices open | `—` | — |
| `S55-history-date-rest-only-dark@723e65b.png` | dark | 1488×1179 | History: the Date filter choices open (the panel window alone) | `—` | — |
| `S55-history-date-rest-only-light@723e65b.png` | light | 1488×1179 | History: the Date filter choices open (the panel window alone) | `—` | — |
| `S55-history-dragas-chosen-dark@723e65b.png` | dark | 1488×1179 | History: the Drag as panel with its chosen row | `—` | — |
| `S55-history-dragas-chosen-light@723e65b.png` | light | 1488×1179 | History: the Drag as panel with its chosen row | `—` | — |
| `S55-history-dragas-dismissed-dark@723e65b.png` | dark | 1488×1179 | Drag as choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S55-history-dragas-dismissed-light@723e65b.png` | light | 1488×1179 | Drag as choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S55-history-dragas-focus-dark@723e65b.png` | dark | 1488×1179 | History: the Drag as choices open; keyboard focus on row 0 (PNG) | `—` | — |
| `S55-history-dragas-focus-light@723e65b.png` | light | 1488×1179 | History: the Drag as choices open; keyboard focus on row 0 (PNG) | `—` | — |
| `S55-history-dragas-hover-dark@723e65b.png` | dark | 1488×1179 | History: the Drag as choices open; row 1 (JPG) hovered | `—` | — |
| `S55-history-dragas-hover-light@723e65b.png` | light | 1488×1179 | History: the Drag as choices open; row 1 (JPG) hovered | `—` | — |
| `S55-history-dragas-rest-dark@723e65b.png` | dark | 1488×1179 | History: the Drag as choices open | `—` | — |
| `S55-history-dragas-rest-light@723e65b.png` | light | 1488×1179 | History: the Drag as choices open | `—` | — |
| `S55-history-dragas-rest-only-dark@723e65b.png` | dark | 1488×1179 | History: the Drag as choices open (the panel window alone) | `—` | — |
| `S55-history-dragas-rest-only-light@723e65b.png` | light | 1488×1179 | History: the Drag as choices open (the panel window alone) | `—` | — |
| `S56-settings-actions-disabled-dark@723e65b.png` | dark | 1488×1179 | Settings, Upload: the destination action plate; disabled row 3 (Make Default) hovered and offered focus | `—` | — |
| `S56-settings-actions-disabled-light@723e65b.png` | light | 1488×1179 | Settings, Upload: the destination action plate; disabled row 3 (Make Default) hovered and offered focus | `—` | — |
| `S56-settings-actions-focus-dark@723e65b.png` | dark | 1488×1179 | Settings, Upload: the destination action plate; keyboard focus on row 0 (Add…) | `—` | — |
| `S56-settings-actions-focus-light@723e65b.png` | light | 1488×1179 | Settings, Upload: the destination action plate; keyboard focus on row 0 (Add…) | `—` | — |
| `S56-settings-actions-hover-dark@723e65b.png` | dark | 1488×1179 | Settings, Upload: the destination action plate; row 0 (Add…) hovered | `—` | — |
| `S56-settings-actions-hover-light@723e65b.png` | light | 1488×1179 | Settings, Upload: the destination action plate; row 0 (Add…) hovered | `—` | — |
| `S56-settings-actions-rest-dark@723e65b.png` | dark | 1488×1179 | Settings, Upload: the destination action plate | `—` | — |
| `S56-settings-actions-rest-light@723e65b.png` | light | 1488×1179 | Settings, Upload: the destination action plate | `—` | — |
| `S56-settings-radios-focus-dark@723e65b.png` | dark | 1488×1179 | Settings: Presence, Precision and Arrow head radios; keyboard focus on row 2 (Both) | `—` | — |
| `S56-settings-radios-focus-light@723e65b.png` | light | 1488×1179 | Settings: Presence, Precision and Arrow head radios; keyboard focus on row 2 (Both) | `—` | — |
| `S56-settings-radios-hover-dark@723e65b.png` | dark | 1488×1179 | Settings: Presence, Precision and Arrow head radios; row 0 (Dock) hovered | `—` | — |
| `S56-settings-radios-hover-light@723e65b.png` | light | 1488×1179 | Settings: Presence, Precision and Arrow head radios; row 0 (Dock) hovered | `—` | — |
| `S56-settings-radios-rest-dark@723e65b.png` | dark | 1488×1179 | Settings: Presence, Precision and Arrow head radios | `—` | — |
| `S56-settings-radios-rest-light@723e65b.png` | light | 1488×1179 | Settings: Presence, Precision and Arrow head radios | `—` | — |
| `S56-settings-tabs-focus-dark@723e65b.png` | dark | 1488×1179 | Settings tab strip on one glass plate; keyboard focus on row 0 (General) | `—` | — |
| `S56-settings-tabs-focus-light@723e65b.png` | light | 1488×1179 | Settings tab strip on one glass plate; keyboard focus on row 0 (General) | `—` | — |
| `S56-settings-tabs-hover-dark@723e65b.png` | dark | 1488×1179 | Settings tab strip on one glass plate; row 1 (Drawing) hovered | `—` | — |
| `S56-settings-tabs-hover-light@723e65b.png` | light | 1488×1179 | Settings tab strip on one glass plate; row 1 (Drawing) hovered | `—` | — |
| `S56-settings-tabs-rest-dark@723e65b.png` | dark | 1488×1179 | Settings tab strip on one glass plate | `—` | — |
| `S56-settings-tabs-rest-light@723e65b.png` | light | 1488×1179 | Settings tab strip on one glass plate | `—` | — |
| `S56-settings-toggles-focus-dark@723e65b.png` | dark | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles; keyboard focus on row 0 (Show hover hints for tools) | `—` | — |
| `S56-settings-toggles-focus-light@723e65b.png` | light | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles; keyboard focus on row 0 (Show hover hints for tools) | `—` | — |
| `S56-settings-toggles-hover-dark@723e65b.png` | dark | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles; row 0 (Show hover hints for tools) hovered | `—` | — |
| `S56-settings-toggles-hover-light@723e65b.png` | light | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles; row 0 (Show hover hints for tools) hovered | `—` | — |
| `S56-settings-toggles-rest-dark@723e65b.png` | dark | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles | `—` | — |
| `S56-settings-toggles-rest-light@723e65b.png` | light | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles | `—` | — |
| `S57-resize-anchor-focus-dark@723e65b.png` | dark | 1489×1179 | Crop mode: the anchor plate has keyboard focus (ring on the chosen cell) | `—` | — |
| `S57-resize-anchor-focus-light@723e65b.png` | light | 1489×1179 | Crop mode: the anchor plate has keyboard focus (ring on the chosen cell) | `—` | — |
| `S57-resize-anchor-hover-dark@723e65b.png` | dark | 1489×1179 | Crop mode: the Top Right cell hovered | `—` | — |
| `S57-resize-anchor-hover-light@723e65b.png` | light | 1489×1179 | Crop mode: the Top Right cell hovered | `—` | — |
| `S57-resize-anchor-rest-dark@723e65b.png` | dark | 1489×1179 | Crop mode: the 3 x 3 anchor plate, Center chosen | `—` | — |
| `S57-resize-anchor-rest-light@723e65b.png` | light | 1489×1179 | Crop mode: the 3 x 3 anchor plate, Center chosen | `—` | — |
| `S57-resize-groups-focus-dark@723e65b.png` | dark | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates; keyboard focus on row 0 (Resize) | `—` | — |
| `S57-resize-groups-focus-light@723e65b.png` | light | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates; keyboard focus on row 0 (Resize) | `—` | — |
| `S57-resize-groups-hover-dark@723e65b.png` | dark | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates; row 1 (Crop) hovered | `—` | — |
| `S57-resize-groups-hover-light@723e65b.png` | light | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates; row 1 (Crop) hovered | `—` | — |
| `S57-resize-groups-rest-dark@723e65b.png` | dark | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates | `—` | — |
| `S57-resize-groups-rest-light@723e65b.png` | light | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates | `—` | — |
| `S57-resize-preset-chosen-dark@723e65b.png` | dark | 1489×1179 | Resize sheet: the preset panel with its chosen row | `—` | — |
| `S57-resize-preset-chosen-light@723e65b.png` | light | 1489×1179 | Resize sheet: the preset panel with its chosen row | `—` | — |
| `S57-resize-preset-dismissed-dark@723e65b.png` | dark | 1489×1179 | Preset choices dismissed with Escape: gone, focus back on the preset face | `—` | — |
| `S57-resize-preset-dismissed-light@723e65b.png` | light | 1489×1179 | Preset choices dismissed with Escape: gone, focus back on the preset face | `—` | — |
| `S57-resize-preset-focus-dark@723e65b.png` | dark | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets); keyboard focus on row 0 (Custom size) | `—` | — |
| `S57-resize-preset-focus-light@723e65b.png` | light | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets); keyboard focus on row 0 (Custom size) | `—` | — |
| `S57-resize-preset-hover-dark@723e65b.png` | dark | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets); row 1 (Ad: Rectangle (Large)) hovered | `—` | — |
| `S57-resize-preset-hover-light@723e65b.png` | light | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets); row 1 (Ad: Rectangle (Large)) hovered | `—` | — |
| `S57-resize-preset-rest-dark@723e65b.png` | dark | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets) | `—` | — |
| `S57-resize-preset-rest-light@723e65b.png` | light | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets) | `—` | — |
| `S57-resize-preset-rest-only-dark@723e65b.png` | dark | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets) (the panel window alone) | `—` | — |
| `S57-resize-preset-rest-only-light@723e65b.png` | light | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets) (the panel window alone) | `—` | — |
| `S58-destination-acl-off-dark@723e65b.png` | dark | 1488×1179 | S3-compatible destination: Make uploads public-read off | `—` | — |
| `S58-destination-acl-off-light@723e65b.png` | light | 1488×1179 | S3-compatible destination: Make uploads public-read off | `—` | — |
| `S58-destination-acl-on-dark@723e65b.png` | dark | 1488×1179 | S3-compatible destination: Make uploads public-read on | `—` | — |
| `S58-destination-acl-on-light@723e65b.png` | light | 1488×1179 | S3-compatible destination: Make uploads public-read on | `—` | — |
| `S58-destination-protocol-dismissed-dark@723e65b.png` | dark | 1488×1179 | choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S58-destination-protocol-dismissed-light@723e65b.png` | light | 1488×1179 | choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S58-destination-protocol-focus-dark@723e65b.png` | dark | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected; keyboard focus on row 0 (WebDAV) | `—` | — |
| `S58-destination-protocol-focus-light@723e65b.png` | light | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected; keyboard focus on row 0 (WebDAV) | `—` | — |
| `S58-destination-protocol-hover-dark@723e65b.png` | dark | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected; row 1 (FTP) hovered | `—` | — |
| `S58-destination-protocol-hover-light@723e65b.png` | light | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected; row 1 (FTP) hovered | `—` | — |
| `S58-destination-protocol-rest-dark@723e65b.png` | dark | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected | `—` | — |
| `S58-destination-protocol-rest-light@723e65b.png` | light | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected | `—` | — |
| `S58-destination-protocol-rest-only-dark@723e65b.png` | dark | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected (the panel window alone) | `—` | — |
| `S58-destination-protocol-rest-only-light@723e65b.png` | light | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected (the panel window alone) | `—` | — |
| `S58-destination-source-dismissed-dark@723e65b.png` | dark | 1488×1179 | choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S58-destination-source-dismissed-light@723e65b.png` | light | 1488×1179 | choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S58-destination-source-focus-dark@723e65b.png` | dark | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected; keyboard focus on row 0 (AWS credentials profile) | `—` | — |
| `S58-destination-source-focus-light@723e65b.png` | light | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected; keyboard focus on row 0 (AWS credentials profile) | `—` | — |
| `S58-destination-source-hover-dark@723e65b.png` | dark | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected; row 1 (Access key stored in Keychain) hovered | `—` | — |
| `S58-destination-source-hover-light@723e65b.png` | light | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected; row 1 (Access key stored in Keychain) hovered | `—` | — |
| `S58-destination-source-rest-dark@723e65b.png` | dark | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected | `—` | — |
| `S58-destination-source-rest-light@723e65b.png` | light | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected | `—` | — |
| `S58-destination-source-rest-only-dark@723e65b.png` | dark | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected (the panel window alone) | `—` | — |
| `S58-destination-source-rest-only-light@723e65b.png` | light | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected (the panel window alone) | `—` | — |
| `S58-destination-width-560-dark@723e65b.png` | dark | 1488×1179 | S3-compatible with the Keychain key source, sheet 560 pt wide | `—` | — |
| `S58-destination-width-560-light@723e65b.png` | light | 1488×1179 | S3-compatible with the Keychain key source, sheet 560 pt wide | `—` | — |
| `S58-destination-width-640-dark@723e65b.png` | dark | 1488×1179 | S3-compatible with the Keychain key source, sheet 640 pt wide | `—` | — |
| `S58-destination-width-640-light@723e65b.png` | light | 1488×1179 | S3-compatible with the Keychain key source, sheet 640 pt wide | `—` | — |
| `S59-footer-original-hidden-dark@723e65b.png` | dark | 980×640 | large shot at 980 during an upload: the status slot reflows and the Original size toggle steps aside | `layout/S59-footer-original-hidden-dark@723e65b.json` | — |
| `S59-footer-original-hidden-light@723e65b.png` | light | 980×640 | large shot at 980 during an upload: the status slot reflows and the Original size toggle steps aside | `layout/S59-footer-original-hidden-light@723e65b.json` | — |
| `S59-footer-original-off-dark@723e65b.png` | dark | 1280×800 | large shot at 1280: the Original size toggle off | `layout/S59-footer-original-off-dark@723e65b.json` | — |
| `S59-footer-original-off-light@723e65b.png` | light | 1280×800 | large shot at 1280: the Original size toggle off | `layout/S59-footer-original-off-light@723e65b.json` | — |
| `S59-footer-original-on-dark@723e65b.png` | dark | 1280×800 | large shot at 1280: the Original size toggle on | `layout/S59-footer-original-on-dark@723e65b.json` | — |
| `S59-footer-original-on-light@723e65b.png` | light | 1280×800 | large shot at 1280: the Original size toggle on | `layout/S59-footer-original-on-light@723e65b.json` | — |
| `S60-capture-clear-all-dark@723e65b.png` | dark | 980×640 | Capture tab: the Clear All action plate | `—` | — |
| `S60-capture-clear-all-light@723e65b.png` | light | 980×640 | Capture tab: the Clear All action plate | `—` | — |
| `S60-capture-enable-off-dark@723e65b.png` | dark | 980×640 | Capture tab: Enable global capture shortcuts off | `—` | — |
| `S60-capture-enable-off-light@723e65b.png` | light | 980×640 | Capture tab: Enable global capture shortcuts off | `—` | — |
| `S60-capture-enable-on-dark@723e65b.png` | dark | 980×640 | Capture tab: Enable global capture shortcuts on | `—` | — |
| `S60-capture-enable-on-light@723e65b.png` | light | 980×640 | Capture tab: Enable global capture shortcuts on | `—` | — |
| `S60-capture-key-chosen-dark@723e65b.png` | dark | 980×640 | Capture tab: the key panel with K chosen | `—` | — |
| `S60-capture-key-chosen-light@723e65b.png` | light | 980×640 | Capture tab: the key panel with K chosen | `—` | — |
| `S60-capture-key-dismissed-dark@723e65b.png` | dark | 980×640 | Key choices dismissed with Escape: gone, focus back on the key face | `—` | — |
| `S60-capture-key-dismissed-light@723e65b.png` | light | 980×640 | Key choices dismissed with Escape: gone, focus back on the key face | `—` | — |
| `S60-capture-key-focus-dark@723e65b.png` | dark | 980×640 | Capture tab: the key choices open for Screen region, K chosen; keyboard focus on row 0 (None) | `—` | — |
| `S60-capture-key-focus-light@723e65b.png` | light | 980×640 | Capture tab: the key choices open for Screen region, K chosen; keyboard focus on row 0 (None) | `—` | — |
| `S60-capture-key-hover-dark@723e65b.png` | dark | 980×640 | Capture tab: the key choices open for Screen region, K chosen; row 1 (A) hovered | `—` | — |
| `S60-capture-key-hover-light@723e65b.png` | light | 980×640 | Capture tab: the key choices open for Screen region, K chosen; row 1 (A) hovered | `—` | — |
| `S60-capture-key-rest-dark@723e65b.png` | dark | 980×640 | Capture tab: the key choices open for Screen region, K chosen | `—` | — |
| `S60-capture-key-rest-light@723e65b.png` | light | 980×640 | Capture tab: the key choices open for Screen region, K chosen | `—` | — |
| `S60-capture-key-rest-only-dark@723e65b.png` | dark | 980×640 | Capture tab: the key choices open for Screen region, K chosen (the panel window alone) | `—` | — |
| `S60-capture-key-rest-only-light@723e65b.png` | light | 980×640 | Capture tab: the key choices open for Screen region, K chosen (the panel window alone) | `—` | — |
| `S60-capture-key-scroll-dark@723e65b.png` | dark | 980×640 | Capture tab: the long key list scrolled to its last row inside the height cap | `—` | — |
| `S60-capture-key-scroll-light@723e65b.png` | light | 980×640 | Capture tab: the long key list scrolled to its last row inside the height cap | `—` | — |
| `S60-capture-modifiers-chosen-dark@723e65b.png` | dark | 980×640 | Capture tab: K with Option and Control chosen on the Screen region row | `—` | — |
| `S60-capture-modifiers-chosen-light@723e65b.png` | light | 980×640 | Capture tab: K with Option and Control chosen on the Screen region row | `—` | — |
| `S60-capture-modifiers-disabled-dark@723e65b.png` | dark | 980×640 | Capture tab: no key set for Screen region, so its four modifier toggles are disabled | `—` | — |
| `S60-capture-modifiers-disabled-light@723e65b.png` | light | 980×640 | Capture tab: no key set for Screen region, so its four modifier toggles are disabled | `—` | — |

