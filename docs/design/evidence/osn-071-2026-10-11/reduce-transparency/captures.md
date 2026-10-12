# OSN-071 visual acceptance run (round 4): reduce-transparency

Source `8188b73`; icon mode **sf** (FA unavailable); 486 captures, every PNG scaled to at most 1200 px wide.
Pre-change twins are referenced from `docs/design/evidence/impl-2026-10-09/root-final-core` at `1ea366c`; they are not copied.

| Capture | Appearance | Window pt | What it shows | Layout JSON | BEFORE (pre-change) |
|---|---|---|---|---|---|
| `S01-editor-empty-dark-rt@8188b73.png` | dark | 1120×812 | fresh blank canvas, default window | `layout/S01-editor-empty-dark-rt@8188b73.json` | — |
| `S01-editor-empty-light-rt@8188b73.png` | light | 1120×812 | fresh blank canvas, default window | `layout/S01-editor-empty-light-rt@8188b73.json` | — |
| `S02-populated-dark-rt@8188b73.png` | dark | 1561×1179 | synthetic 1200x800 background + arrow, line, rectangle (open+filled), ellipse, brush, highlighter, fill, text (outline+shadow, plain), SVG path, raster | `layout/S02-populated-dark-rt@8188b73.json` | — |
| `S02-populated-light-rt@8188b73.png` | light | 1561×1179 | synthetic 1200x800 background + arrow, line, rectangle (open+filled), ellipse, brush, highlighter, fill, text (outline+shadow, plain), SVG path, raster | `layout/S02-populated-light-rt@8188b73.json` | — |
| `S03-bottombar-dark-rt@8188b73.png` | dark | 1488×1179 | Undo, Wipe / Zoom, Resize / status / Save, History / PNG/JPG, Drag, Upload | `layout/S03-bottombar-dark-rt@8188b73.json` | — |
| `S03-bottombar-light-rt@8188b73.png` | light | 1488×1179 | Undo, Wipe / Zoom, Resize / status / Save, History / PNG/JPG, Drag, Upload | `layout/S03-bottombar-light-rt@8188b73.json` | — |
| `S03-topbar-dark-rt@8188b73.png` | dark | 1488×1179 | Hide, Toolbox, Photos / Snap / ten tools / Color, Size, Font; title shows document name | `layout/S03-topbar-dark-rt@8188b73.json` | — |
| `S03-topbar-light-rt@8188b73.png` | light | 1488×1179 | Hide, Toolbox, Photos / Snap / ten tools / Color, Size, Font; title shows document name | `layout/S03-topbar-light-rt@8188b73.json` | — |
| `S04-controls-disabled-dark-rt@8188b73.png` | dark | 1488×1179 | Resize + Undo disabled (isEnabled=false as Frame/Actual mode does) | `layout/S04-controls-disabled-dark-rt@8188b73.json` | — |
| `S04-controls-disabled-light-rt@8188b73.png` | light | 1488×1179 | Resize + Undo disabled (isEnabled=false as Frame/Actual mode does) | `layout/S04-controls-disabled-light-rt@8188b73.json` | — |
| `S04-snap-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Snap (primary, accent) hovered | `layout/S04-snap-hover-dark-rt@8188b73.json` | — |
| `S04-snap-hover-light-rt@8188b73.png` | light | 1488×1179 | Snap (primary, accent) hovered | `layout/S04-snap-hover-light-rt@8188b73.json` | — |
| `S04-tool-arrow-dark-rt@8188b73.png` | dark | 1488×1179 | arrow tool selected | `layout/S04-tool-arrow-dark-rt@8188b73.json` | — |
| `S04-tool-arrow-light-rt@8188b73.png` | light | 1488×1179 | arrow tool selected | `layout/S04-tool-arrow-light-rt@8188b73.json` | — |
| `S04-tool-brush-dark-rt@8188b73.png` | dark | 1488×1179 | brush tool selected | `layout/S04-tool-brush-dark-rt@8188b73.json` | — |
| `S04-tool-brush-light-rt@8188b73.png` | light | 1488×1179 | brush tool selected | `layout/S04-tool-brush-light-rt@8188b73.json` | — |
| `S04-tool-crop-dark-rt@8188b73.png` | dark | 1488×1179 | crop tool selected | `layout/S04-tool-crop-dark-rt@8188b73.json` | — |
| `S04-tool-crop-light-rt@8188b73.png` | light | 1488×1179 | crop tool selected | `layout/S04-tool-crop-light-rt@8188b73.json` | — |
| `S04-tool-ellipse-dark-rt@8188b73.png` | dark | 1488×1179 | ellipse tool selected | `layout/S04-tool-ellipse-dark-rt@8188b73.json` | — |
| `S04-tool-ellipse-light-rt@8188b73.png` | light | 1488×1179 | ellipse tool selected | `layout/S04-tool-ellipse-light-rt@8188b73.json` | — |
| `S04-tool-eraser-dark-rt@8188b73.png` | dark | 1488×1179 | eraser tool selected | `layout/S04-tool-eraser-dark-rt@8188b73.json` | — |
| `S04-tool-eraser-light-rt@8188b73.png` | light | 1488×1179 | eraser tool selected | `layout/S04-tool-eraser-light-rt@8188b73.json` | — |
| `S04-tool-fill-dark-rt@8188b73.png` | dark | 1488×1179 | fill tool selected | `layout/S04-tool-fill-dark-rt@8188b73.json` | — |
| `S04-tool-fill-light-rt@8188b73.png` | light | 1488×1179 | fill tool selected | `layout/S04-tool-fill-light-rt@8188b73.json` | — |
| `S04-tool-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Rectangle tool hovered (CommandButton.setHovered: a 0.08 fill on the group plate), Brush selected | `layout/S04-tool-hover-dark-rt@8188b73.json` | — |
| `S04-tool-hover-light-rt@8188b73.png` | light | 1488×1179 | Rectangle tool hovered (CommandButton.setHovered: a 0.08 fill on the group plate), Brush selected | `layout/S04-tool-hover-light-rt@8188b73.json` | — |
| `S04-tool-line-dark-rt@8188b73.png` | dark | 1488×1179 | line tool selected | `layout/S04-tool-line-dark-rt@8188b73.json` | — |
| `S04-tool-line-light-rt@8188b73.png` | light | 1488×1179 | line tool selected | `layout/S04-tool-line-light-rt@8188b73.json` | — |
| `S04-tool-pressed-dark-rt@8188b73.png` | dark | 1488×1179 | Rectangle tool pressed (CommandButton.highlight: a 0.16 fill on the group plate), Brush selected | `layout/S04-tool-pressed-dark-rt@8188b73.json` | — |
| `S04-tool-pressed-light-rt@8188b73.png` | light | 1488×1179 | Rectangle tool pressed (CommandButton.highlight: a 0.16 fill on the group plate), Brush selected | `layout/S04-tool-pressed-light-rt@8188b73.json` | — |
| `S04-tool-rectangle-dark-rt@8188b73.png` | dark | 1488×1179 | rectangle tool selected | `layout/S04-tool-rectangle-dark-rt@8188b73.json` | — |
| `S04-tool-rectangle-light-rt@8188b73.png` | light | 1488×1179 | rectangle tool selected | `layout/S04-tool-rectangle-light-rt@8188b73.json` | — |
| `S04-tool-select-dark-rt@8188b73.png` | dark | 1488×1179 | select tool selected | `layout/S04-tool-select-dark-rt@8188b73.json` | — |
| `S04-tool-select-light-rt@8188b73.png` | light | 1488×1179 | select tool selected | `layout/S04-tool-select-light-rt@8188b73.json` | — |
| `S04-tool-text-dark-rt@8188b73.png` | dark | 1488×1179 | text tool selected | `layout/S04-tool-text-dark-rt@8188b73.json` | — |
| `S04-tool-text-light-rt@8188b73.png` | light | 1488×1179 | text tool selected | `layout/S04-tool-text-light-rt@8188b73.json` | — |
| `S05-selection-multi-dark-rt@8188b73.png` | dark | 1488×1179 | ellipse + arrow selected together | `layout/S05-selection-multi-dark-rt@8188b73.json` | — |
| `S05-selection-multi-light-rt@8188b73.png` | light | 1488×1179 | ellipse + arrow selected together | `layout/S05-selection-multi-light-rt@8188b73.json` | — |
| `S05-selection-rect-dark-rt@8188b73.png` | dark | 1488×1179 | rectangle selected with resize handles | `layout/S05-selection-rect-dark-rt@8188b73.json` | — |
| `S05-selection-rect-light-rt@8188b73.png` | light | 1488×1179 | rectangle selected with resize handles | `layout/S05-selection-rect-light-rt@8188b73.json` | — |
| `S05-text-editing-dark-rt@8188b73.png` | dark | 1488×1179 | text tool field editor active with typed text and grip | `layout/S05-text-editing-dark-rt@8188b73.json` | — |
| `S05-text-editing-light-rt@8188b73.png` | light | 1488×1179 | text tool field editor active with typed text and grip | `layout/S05-text-editing-light-rt@8188b73.json` | — |
| `S06-color-palette-dark-rt@8188b73.png` | dark | 1488×1179 | preset palette popover open (original ten presets + Custom color…) | `layout/S06-color-palette-dark-rt@8188b73.json` | — |
| `S06-color-palette-light-rt@8188b73.png` | light | 1488×1179 | preset palette popover open (original ten presets + Custom color…) | `layout/S06-color-palette-light-rt@8188b73.json` | — |
| `S06-color-palette-popover-dark-rt@8188b73.png` | dark | 1488×1179 | preset palette popover window alone | `—` | — |
| `S06-color-palette-popover-light-rt@8188b73.png` | light | 1488×1179 | preset palette popover window alone | `—` | — |
| `S06-color-panel-dark-rt@8188b73.png` | dark | 1488×1179 | system NSColorPanel opened by Custom color… | `—` | — |
| `S06-color-panel-light-rt@8188b73.png` | light | 1488×1179 | system NSColorPanel opened by Custom color… | `—` | — |
| `S06-fonts-panel-dark-rt@8188b73.png` | dark | 1488×1179 | NSFontPanel with Outline / Shadow / Default accessory form | `—` | — |
| `S06-fonts-panel-light-rt@8188b73.png` | light | 1488×1179 | NSFontPanel with Outline / Shadow / Default accessory form | `—` | — |
| `S06-size-max-dark-rt@8188b73.png` | dark | 1488×1179 | size pill glyph at 12.0 (max) | `layout/S06-size-max-dark-rt@8188b73.json` | — |
| `S06-size-max-light-rt@8188b73.png` | light | 1488×1179 | size pill glyph at 12.0 (max) | `layout/S06-size-max-light-rt@8188b73.json` | — |
| `S06-size-mid-dark-rt@8188b73.png` | dark | 1488×1179 | size pill glyph at 6.75 (mid) | `layout/S06-size-mid-dark-rt@8188b73.json` | — |
| `S06-size-mid-light-rt@8188b73.png` | light | 1488×1179 | size pill glyph at 6.75 (mid) | `layout/S06-size-mid-light-rt@8188b73.json` | — |
| `S06-size-min-dark-rt@8188b73.png` | dark | 1488×1179 | size pill glyph at 1.5 (min) | `layout/S06-size-min-dark-rt@8188b73.json` | — |
| `S06-size-min-light-rt@8188b73.png` | light | 1488×1179 | size pill glyph at 1.5 (min) | `layout/S06-size-min-light-rt@8188b73.json` | — |
| `S07-actual-size-dark-rt@8188b73.png` | dark | 1662×1179 | Actual Size on: navigator overview panel beside the window | `layout/S07-actual-size-dark-rt@8188b73.json` | — |
| `S07-actual-size-light-rt@8188b73.png` | light | 1662×1179 | Actual Size on: navigator overview panel beside the window | `layout/S07-actual-size-light-rt@8188b73.json` | — |
| `S07-large-fit-dark-rt@8188b73.png` | dark | 1662×1179 | 2400x1500 image fitted into the window | `layout/S07-large-fit-dark-rt@8188b73.json` | — |
| `S07-large-fit-light-rt@8188b73.png` | light | 1662×1179 | 2400x1500 image fitted into the window | `layout/S07-large-fit-light-rt@8188b73.json` | — |
| `S07-small-centred-dark-rt@8188b73.png` | dark | 980×648 | 360x240 image centred in a large viewport (shot first, before any Actual Size state) (CenteringClipView) | `layout/S07-small-centred-dark-rt@8188b73.json` | — |
| `S07-small-centred-light-rt@8188b73.png` | light | 980×648 | 360x240 image centred in a large viewport (shot first, before any Actual Size state) (CenteringClipView) | `layout/S07-small-centred-light-rt@8188b73.json` | — |
| `S07-zoom-200-dark-rt@8188b73.png` | dark | 1662×1179 | zoom 200% | `layout/S07-zoom-200-dark-rt@8188b73.json` | — |
| `S07-zoom-200-light-rt@8188b73.png` | light | 1662×1179 | zoom 200% | `layout/S07-zoom-200-light-rt@8188b73.json` | — |
| `S07-zoom-25-dark-rt@8188b73.png` | dark | 1662×1179 | zoom 25% | `layout/S07-zoom-25-dark-rt@8188b73.json` | — |
| `S07-zoom-25-light-rt@8188b73.png` | light | 1662×1179 | zoom 25% | `layout/S07-zoom-25-light-rt@8188b73.json` | — |
| `S07-zoom-50-dark-rt@8188b73.png` | dark | 1662×1179 | zoom 50% | `layout/S07-zoom-50-dark-rt@8188b73.json` | — |
| `S07-zoom-50-light-rt@8188b73.png` | light | 1662×1179 | zoom 50% | `layout/S07-zoom-50-light-rt@8188b73.json` | — |
| `S08-crop-mode-dark-rt@8188b73.png` | dark | 1561×1179 | crop tool with a 640x420 crop rectangle | `layout/S08-crop-mode-dark-rt@8188b73.json` | — |
| `S08-crop-mode-light-rt@8188b73.png` | light | 1561×1179 | crop tool with a 640x420 crop rectangle | `layout/S08-crop-mode-light-rt@8188b73.json` | — |
| `S08-resize-panel-dark-rt@8188b73.png` | dark | 1561×1179 | Resize sheet with built-in + two synthetic presets | `—` | — |
| `S08-resize-panel-light-rt@8188b73.png` | light | 1561×1179 | Resize sheet with built-in + two synthetic presets | `—` | — |
| `S08-resize-panel-in-context-dark-rt@8188b73.png` | dark | 1561×1179 | Resize sheet with built-in + two synthetic presets (parent window + sheet composite) | `—` | — |
| `S08-resize-panel-in-context-light-rt@8188b73.png` | light | 1561×1179 | Resize sheet with built-in + two synthetic presets (parent window + sheet composite) | `—` | — |
| `S09-footer-dark-rt@8188b73.png` | dark | 1488×1179 | zoom, status, format, drag well, upload | `layout/S09-footer-dark-rt@8188b73.json` | — |
| `S09-footer-light-rt@8188b73.png` | light | 1488×1179 | zoom, status, format, drag well, upload | `layout/S09-footer-light-rt@8188b73.json` | — |
| `S09-footer-long-status-dark-rt@8188b73.png` | dark | 1488×1179 | very long status text | `layout/S09-footer-long-status-dark-rt@8188b73.json` | — |
| `S09-footer-long-status-light-rt@8188b73.png` | light | 1488×1179 | very long status text | `layout/S09-footer-long-status-light-rt@8188b73.json` | — |
| `S09-format-toggle-jpg-dark-rt@8188b73.png` | dark | 1488×1179 | PNG / JPG segmented toggle with JPG selected | `layout/S09-format-toggle-jpg-dark-rt@8188b73.json` | — |
| `S09-format-toggle-jpg-light-rt@8188b73.png` | light | 1488×1179 | PNG / JPG segmented toggle with JPG selected | `layout/S09-format-toggle-jpg-light-rt@8188b73.json` | — |
| `S09-format-toggle-png-dark-rt@8188b73.png` | dark | 1488×1179 | PNG / JPG segmented toggle with PNG selected | `layout/S09-format-toggle-png-dark-rt@8188b73.json` | — |
| `S09-format-toggle-png-light-rt@8188b73.png` | light | 1488×1179 | PNG / JPG segmented toggle with PNG selected | `layout/S09-format-toggle-png-light-rt@8188b73.json` | — |
| `S09-upload-menu-open-dark-rt@8188b73.png` | dark | 1488×1179 | Upload (Webpost) destination choices open, no destination configured (glass panel) | `—` | — |
| `S09-upload-menu-open-light-rt@8188b73.png` | light | 1488×1179 | Upload (Webpost) destination choices open, no destination configured (glass panel) | `—` | — |
| `S09-upload-menu-open-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | Upload panel dismissed with Escape | `layout/S09-upload-menu-open-dismissed-dark-rt@8188b73.json` | — |
| `S09-upload-menu-open-dismissed-light-rt@8188b73.png` | light | 1488×1179 | Upload panel dismissed with Escape | `layout/S09-upload-menu-open-dismissed-light-rt@8188b73.json` | — |
| `S10-export-accessory-alone-dark-rt@8188b73.png` | dark | 1488×1179 | ExportAccessory view rendered in its own window (JPEG selected) | `—` | — |
| `S10-export-accessory-alone-light-rt@8188b73.png` | light | 1488×1179 | ExportAccessory view rendered in its own window (JPEG selected) | `—` | — |
| `S10-export-panel-dark-rt@8188b73.png` | dark | 1488×1179 | NSSavePanel with ExportAccessory (aborted, nothing written); the panel's own file browser is a system remote view that never reaches a window image, so the capture is the panel frame plus the app's accessory content | `—` | — |
| `S10-export-panel-light-rt@8188b73.png` | light | 1488×1179 | NSSavePanel with ExportAccessory (aborted, nothing written); the panel's own file browser is a system remote view that never reaches a window image, so the capture is the panel frame plus the app's accessory content | `—` | — |
| `S11-size-contentmin-dark-rt@8188b73.png` | dark | 980×640 | contentMinSize 980x608 | `layout/S11-size-contentmin-dark-rt@8188b73.json` | — |
| `S11-size-contentmin-light-rt@8188b73.png` | light | 980×640 | contentMinSize 980x608 | `layout/S11-size-contentmin-light-rt@8188b73.json` | — |
| `S11-size-default-dark-rt@8188b73.png` | dark | 1120×812 | default 1024x740 | `layout/S11-size-default-dark-rt@8188b73.json` | — |
| `S11-size-default-light-rt@8188b73.png` | light | 1120×812 | default 1024x740 | `layout/S11-size-default-light-rt@8188b73.json` | — |
| `S11-size-maximized-dark-rt@8188b73.png` | dark | 2056×1197 | maximized to visibleFrame 2056x1197 | `layout/S11-size-maximized-dark-rt@8188b73.json` | — |
| `S11-size-maximized-light-rt@8188b73.png` | light | 2056×1197 | maximized to visibleFrame 2056x1197 | `layout/S11-size-maximized-light-rt@8188b73.json` | — |
| `S11-size-tall-dark-rt@8188b73.png` | dark | 1000×1157 | tall 1000x1157 | `layout/S11-size-tall-dark-rt@8188b73.json` | — |
| `S11-size-tall-light-rt@8188b73.png` | light | 1000×1157 | tall 1000x1157 | `layout/S11-size-tall-light-rt@8188b73.json` | — |
| `S11-size-wide-dark-rt@8188b73.png` | dark | 1900×640 | wide 1900x640 | `layout/S11-size-wide-dark-rt@8188b73.json` | — |
| `S11-size-wide-light-rt@8188b73.png` | light | 1900×640 | wide 1900x640 | `layout/S11-size-wide-light-rt@8188b73.json` | — |
| `S11-width-1024-dark-rt@8188b73.png` | dark | 1024×812 | window width 1024 pt, default height | `layout/S11-width-1024-dark-rt@8188b73.json` | — |
| `S11-width-1024-light-rt@8188b73.png` | light | 1024×812 | window width 1024 pt, default height | `layout/S11-width-1024-light-rt@8188b73.json` | — |
| `S11-width-1280-dark-rt@8188b73.png` | dark | 1280×812 | window width 1280 pt, default height | `layout/S11-width-1280-dark-rt@8188b73.json` | — |
| `S11-width-1280-light-rt@8188b73.png` | light | 1280×812 | window width 1280 pt, default height | `layout/S11-width-1280-light-rt@8188b73.json` | — |
| `S11-width-1440-dark-rt@8188b73.png` | dark | 1440×812 | window width 1440 pt, default height | `layout/S11-width-1440-dark-rt@8188b73.json` | — |
| `S11-width-1440-light-rt@8188b73.png` | light | 1440×812 | window width 1440 pt, default height | `layout/S11-width-1440-light-rt@8188b73.json` | — |
| `S11-width-980-dark-rt@8188b73.png` | dark | 980×812 | window width 980 pt, default height | `layout/S11-width-980-dark-rt@8188b73.json` | — |
| `S11-width-980-light-rt@8188b73.png` | light | 980×812 | window width 980 pt, default height | `layout/S11-width-980-light-rt@8188b73.json` | — |
| `S11E-empty-size-1024x740-dark-rt@8188b73.png` | dark | 1024×740 | requested 1024x740 (1024x740 pt), window is 1024x740 pt | `layout/S11E-empty-size-1024x740-dark-rt@8188b73.json` | — |
| `S11E-empty-size-1024x740-light-rt@8188b73.png` | light | 1024×740 | requested 1024x740 (1024x740 pt), window is 1024x740 pt | `layout/S11E-empty-size-1024x740-light-rt@8188b73.json` | — |
| `S11E-empty-size-1280x800-dark-rt@8188b73.png` | dark | 1280×800 | requested 1280x800 (1280x800 pt), window is 1280x800 pt | `layout/S11E-empty-size-1280x800-dark-rt@8188b73.json` | — |
| `S11E-empty-size-1280x800-light-rt@8188b73.png` | light | 1280×800 | requested 1280x800 (1280x800 pt), window is 1280x800 pt | `layout/S11E-empty-size-1280x800-light-rt@8188b73.json` | — |
| `S11E-empty-size-1440x900-dark-rt@8188b73.png` | dark | 1440×900 | requested 1440x900 (1440x900 pt), window is 1440x900 pt | `layout/S11E-empty-size-1440x900-dark-rt@8188b73.json` | — |
| `S11E-empty-size-1440x900-light-rt@8188b73.png` | light | 1440×900 | requested 1440x900 (1440x900 pt), window is 1440x900 pt | `layout/S11E-empty-size-1440x900-light-rt@8188b73.json` | — |
| `S11E-empty-size-980xmin-dark-rt@8188b73.png` | dark | 980×640 | requested 980xmin (980x640 pt), window is 980x640 pt | `layout/S11E-empty-size-980xmin-dark-rt@8188b73.json` | — |
| `S11E-empty-size-980xmin-light-rt@8188b73.png` | light | 980×640 | requested 980xmin (980x640 pt), window is 980x640 pt | `layout/S11E-empty-size-980xmin-light-rt@8188b73.json` | — |
| `S11E-empty-size-full-dark-rt@8188b73.png` | dark | 2056×1197 | requested full (2056x1197 pt), window is 2056x1197 pt | `layout/S11E-empty-size-full-dark-rt@8188b73.json` | — |
| `S11E-empty-size-full-light-rt@8188b73.png` | light | 2056×1197 | requested full (2056x1197 pt), window is 2056x1197 pt | `layout/S11E-empty-size-full-light-rt@8188b73.json` | — |
| `S11M-size-1024x740-dark-rt@8188b73.png` | dark | 1024×740 | requested 1024x740 (1024x740 pt), window is 1024x740 pt | `layout/S11M-size-1024x740-dark-rt@8188b73.json` | — |
| `S11M-size-1024x740-light-rt@8188b73.png` | light | 1024×740 | requested 1024x740 (1024x740 pt), window is 1024x740 pt | `layout/S11M-size-1024x740-light-rt@8188b73.json` | — |
| `S11M-size-1280x800-dark-rt@8188b73.png` | dark | 1280×800 | requested 1280x800 (1280x800 pt), window is 1280x800 pt | `layout/S11M-size-1280x800-dark-rt@8188b73.json` | — |
| `S11M-size-1280x800-light-rt@8188b73.png` | light | 1280×800 | requested 1280x800 (1280x800 pt), window is 1280x800 pt | `layout/S11M-size-1280x800-light-rt@8188b73.json` | — |
| `S11M-size-1440x900-dark-rt@8188b73.png` | dark | 1440×900 | requested 1440x900 (1440x900 pt), window is 1440x900 pt | `layout/S11M-size-1440x900-dark-rt@8188b73.json` | — |
| `S11M-size-1440x900-light-rt@8188b73.png` | light | 1440×900 | requested 1440x900 (1440x900 pt), window is 1440x900 pt | `layout/S11M-size-1440x900-light-rt@8188b73.json` | — |
| `S11M-size-980xmin-dark-rt@8188b73.png` | dark | 980×640 | requested 980xmin (980x640 pt), window is 980x640 pt | `layout/S11M-size-980xmin-dark-rt@8188b73.json` | — |
| `S11M-size-980xmin-light-rt@8188b73.png` | light | 980×640 | requested 980xmin (980x640 pt), window is 980x640 pt | `layout/S11M-size-980xmin-light-rt@8188b73.json` | — |
| `S11M-size-full-dark-rt@8188b73.png` | dark | 2056×1197 | requested full (2056x1197 pt), window is 2056x1197 pt | `layout/S11M-size-full-dark-rt@8188b73.json` | — |
| `S11M-size-full-light-rt@8188b73.png` | light | 2056×1197 | requested full (2056x1197 pt), window is 2056x1197 pt | `layout/S11M-size-full-light-rt@8188b73.json` | — |
| `S30-size-popover-w1280-dark-rt@8188b73.png` | dark | 1280×800 | Size popover open below the pill at window width 1280x800, value 6.75, Brush tool | `layout/S30-size-popover-w1280-dark-rt@8188b73.json` | — |
| `S30-size-popover-w1280-light-rt@8188b73.png` | light | 1280×800 | Size popover open below the pill at window width 1280x800, value 6.75, Brush tool | `layout/S30-size-popover-w1280-light-rt@8188b73.json` | — |
| `S30-size-popover-w980-dark-rt@8188b73.png` | dark | 980×640 | Size popover open below the pill at window width 980xmin, value 6.75, Brush tool | `layout/S30-size-popover-w980-dark-rt@8188b73.json` | — |
| `S30-size-popover-w980-light-rt@8188b73.png` | light | 980×640 | Size popover open below the pill at window width 980xmin, value 6.75, Brush tool | `layout/S30-size-popover-w980-light-rt@8188b73.json` | — |
| `S31-color-popover-custom-w1440-dark-rt@8188b73.png` | dark | 1440×900 | Drawing colours popover open below the top-bar swatch at window width 1440, a custom colour current | `layout/S31-color-popover-custom-w1440-dark-rt@8188b73.json` | — |
| `S31-color-popover-custom-w1440-light-rt@8188b73.png` | light | 1440×900 | Drawing colours popover open below the top-bar swatch at window width 1440, a custom colour current | `layout/S31-color-popover-custom-w1440-light-rt@8188b73.json` | — |
| `S31-color-popover-custom-w980-dark-rt@8188b73.png` | dark | 980×640 | Drawing colours popover open below the top-bar swatch at window width 980, a custom colour current | `layout/S31-color-popover-custom-w980-dark-rt@8188b73.json` | — |
| `S31-color-popover-custom-w980-light-rt@8188b73.png` | light | 980×640 | Drawing colours popover open below the top-bar swatch at window width 980, a custom colour current | `layout/S31-color-popover-custom-w980-light-rt@8188b73.json` | — |
| `S31-color-popover-only-custom-w1440-dark-rt@8188b73.png` | dark | 1440×900 | the popover window alone, custom colour current | `—` | — |
| `S31-color-popover-only-custom-w1440-light-rt@8188b73.png` | light | 1440×900 | the popover window alone, custom colour current | `—` | — |
| `S31-color-popover-only-custom-w980-dark-rt@8188b73.png` | dark | 980×640 | the popover window alone, custom colour current | `—` | — |
| `S31-color-popover-only-custom-w980-light-rt@8188b73.png` | light | 980×640 | the popover window alone, custom colour current | `—` | — |
| `S31-color-popover-only-w1440-dark-rt@8188b73.png` | dark | 1440×900 | the popover window alone | `—` | — |
| `S31-color-popover-only-w1440-light-rt@8188b73.png` | light | 1440×900 | the popover window alone | `—` | — |
| `S31-color-popover-only-w980-dark-rt@8188b73.png` | dark | 980×640 | the popover window alone | `—` | — |
| `S31-color-popover-only-w980-light-rt@8188b73.png` | light | 980×640 | the popover window alone | `—` | — |
| `S31-color-popover-w1440-dark-rt@8188b73.png` | dark | 1440×900 | Drawing colours popover open below the top-bar swatch at window width 1440, a preset colour current | `layout/S31-color-popover-w1440-dark-rt@8188b73.json` | — |
| `S31-color-popover-w1440-light-rt@8188b73.png` | light | 1440×900 | Drawing colours popover open below the top-bar swatch at window width 1440, a preset colour current | `layout/S31-color-popover-w1440-light-rt@8188b73.json` | — |
| `S31-color-popover-w980-dark-rt@8188b73.png` | dark | 980×640 | Drawing colours popover open below the top-bar swatch at window width 980, a preset colour current | `layout/S31-color-popover-w980-dark-rt@8188b73.json` | — |
| `S31-color-popover-w980-light-rt@8188b73.png` | light | 980×640 | Drawing colours popover open below the top-bar swatch at window width 980, a preset colour current | `layout/S31-color-popover-w980-light-rt@8188b73.json` | — |
| `S32-frame-large-w1280-dark-rt@8188b73.png` | dark | 1280×800 | Frame mode at 1280x800: large shot at 100% so the canvas fills the viewport; Snap Frame + Cancel; no Original size checkbox | `layout/S32-frame-large-w1280-dark-rt@8188b73.json` | — |
| `S32-frame-large-w1280-light-rt@8188b73.png` | light | 1280×800 | Frame mode at 1280x800: large shot at 100% so the canvas fills the viewport; Snap Frame + Cancel; no Original size checkbox | `layout/S32-frame-large-w1280-light-rt@8188b73.json` | — |
| `S32-frame-large-w980-dark-rt@8188b73.png` | dark | 980×640 | Frame mode at 980xmin: large shot at 100% so the canvas fills the viewport; Snap Frame + Cancel; no Original size checkbox | `layout/S32-frame-large-w980-dark-rt@8188b73.json` | — |
| `S32-frame-large-w980-light-rt@8188b73.png` | light | 980×640 | Frame mode at 980xmin: large shot at 100% so the canvas fills the viewport; Snap Frame + Cancel; no Original size checkbox | `layout/S32-frame-large-w980-light-rt@8188b73.json` | — |
| `S33-large-shot-w980-dark-rt@8188b73.png` | dark | 980×640 | 2400x1500 shot at window width 980, Original size checkbox visible | `layout/S33-large-shot-w980-dark-rt@8188b73.json` | — |
| `S33-large-shot-w980-light-rt@8188b73.png` | light | 980×640 | 2400x1500 shot at window width 980, Original size checkbox visible | `layout/S33-large-shot-w980-light-rt@8188b73.json` | — |
| `S33-large-shot-w980-bottombar-dark-rt@8188b73.png` | dark | 980×640 | bottom bar only: Original size checkbox, status, groups | `layout/S33-large-shot-w980-bottombar-dark-rt@8188b73.json` | — |
| `S33-large-shot-w980-bottombar-light-rt@8188b73.png` | light | 980×640 | bottom bar only: Original size checkbox, status, groups | `layout/S33-large-shot-w980-bottombar-light-rt@8188b73.json` | — |
| `S34-small-canvas-w1280-dark-rt@8188b73.png` | dark | 1280×800 | 150x90 canvas at window 1280x800: equal margins left/right and top/bottom | `layout/S34-small-canvas-w1280-dark-rt@8188b73.json` | — |
| `S34-small-canvas-w1280-light-rt@8188b73.png` | light | 1280×800 | 150x90 canvas at window 1280x800: equal margins left/right and top/bottom | `layout/S34-small-canvas-w1280-light-rt@8188b73.json` | — |
| `S34-small-canvas-w1440-dark-rt@8188b73.png` | dark | 1440×900 | 150x90 canvas at window 1440x900: equal margins left/right and top/bottom | `layout/S34-small-canvas-w1440-dark-rt@8188b73.json` | — |
| `S34-small-canvas-w1440-light-rt@8188b73.png` | light | 1440×900 | 150x90 canvas at window 1440x900: equal margins left/right and top/bottom | `layout/S34-small-canvas-w1440-light-rt@8188b73.json` | — |
| `S34-small-canvas-w980-dark-rt@8188b73.png` | dark | 980×640 | 150x90 canvas at window 980xmin: equal margins left/right and top/bottom | `layout/S34-small-canvas-w980-dark-rt@8188b73.json` | — |
| `S34-small-canvas-w980-light-rt@8188b73.png` | light | 980×640 | 150x90 canvas at window 980xmin: equal margins left/right and top/bottom | `layout/S34-small-canvas-w980-light-rt@8188b73.json` | — |
| `S35-large-canvas-w1280-dark-rt@8188b73.png` | dark | 1280×800 | large shot at 100% in a 1280x800 window: canvas runs to the 12-pt margin and scrolls | `layout/S35-large-canvas-w1280-dark-rt@8188b73.json` | — |
| `S35-large-canvas-w1280-light-rt@8188b73.png` | light | 1280×800 | large shot at 100% in a 1280x800 window: canvas runs to the 12-pt margin and scrolls | `layout/S35-large-canvas-w1280-light-rt@8188b73.json` | — |
| `S35-large-canvas-w980-dark-rt@8188b73.png` | dark | 980×640 | large shot at 100% in a 980xmin window: canvas runs to the 12-pt margin and scrolls | `layout/S35-large-canvas-w980-dark-rt@8188b73.json` | — |
| `S35-large-canvas-w980-light-rt@8188b73.png` | light | 980×640 | large shot at 100% in a 980xmin window: canvas runs to the 12-pt margin and scrolls | `layout/S35-large-canvas-w980-light-rt@8188b73.json` | — |
| `S36-selection-w1280-dark-rt@8188b73.png` | dark | 1280×800 | rectangle selected with handles at window 1280x800; Color/Size/Font act on it | `layout/S36-selection-w1280-dark-rt@8188b73.json` | — |
| `S36-selection-w1280-light-rt@8188b73.png` | light | 1280×800 | rectangle selected with handles at window 1280x800; Color/Size/Font act on it | `layout/S36-selection-w1280-light-rt@8188b73.json` | — |
| `S36-selection-w980-dark-rt@8188b73.png` | dark | 980×640 | rectangle selected with handles at window 980xmin; Color/Size/Font act on it | `layout/S36-selection-w980-dark-rt@8188b73.json` | — |
| `S36-selection-w980-light-rt@8188b73.png` | light | 980×640 | rectangle selected with handles at window 980xmin; Color/Size/Font act on it | `layout/S36-selection-w980-light-rt@8188b73.json` | — |
| `S36-text-editing-w1280-dark-rt@8188b73.png` | dark | 1280×800 | text tool field editor active with typed text at window 1280x800 | `layout/S36-text-editing-w1280-dark-rt@8188b73.json` | — |
| `S36-text-editing-w1280-light-rt@8188b73.png` | light | 1280×800 | text tool field editor active with typed text at window 1280x800 | `layout/S36-text-editing-w1280-light-rt@8188b73.json` | — |
| `S36-text-editing-w980-dark-rt@8188b73.png` | dark | 980×640 | text tool field editor active with typed text at window 980xmin | `layout/S36-text-editing-w980-dark-rt@8188b73.json` | — |
| `S36-text-editing-w980-light-rt@8188b73.png` | light | 980×640 | text tool field editor active with typed text at window 980xmin | `layout/S36-text-editing-w980-light-rt@8188b73.json` | — |
| `S37-format-jpg-w980-dark-rt@8188b73.png` | dark | 980×640 | JPG selected at window width 980 with the large-shot bottom bar; footer group width 202.0 pt | `layout/S37-format-jpg-w980-dark-rt@8188b73.json` | — |
| `S37-format-jpg-w980-light-rt@8188b73.png` | light | 980×640 | JPG selected at window width 980 with the large-shot bottom bar; footer group width 202.0 pt | `layout/S37-format-jpg-w980-light-rt@8188b73.json` | — |
| `S37-format-png-w980-dark-rt@8188b73.png` | dark | 980×640 | PNG selected at window width 980 with the large-shot bottom bar; footer group width 202.0 pt | `layout/S37-format-png-w980-dark-rt@8188b73.json` | — |
| `S37-format-png-w980-light-rt@8188b73.png` | light | 980×640 | PNG selected at window width 980 with the large-shot bottom bar; footer group width 202.0 pt | `layout/S37-format-png-w980-light-rt@8188b73.json` | — |
| `S38-tooltip-size-w980-dark-rt@8188b73.png` | dark | 980×640 | the live Size tooltip below the Size pill (Size 7) | `layout/S38-tooltip-size-w980-dark-rt@8188b73.json` | — |
| `S38-tooltip-size-w980-light-rt@8188b73.png` | light | 980×640 | the live Size tooltip below the Size pill (Size 7) | `layout/S38-tooltip-size-w980-light-rt@8188b73.json` | — |
| `S38-tooltip-snap-w980-dark-rt@8188b73.png` | dark | 980×640 | the Snap tooltip below the Snap button; the long sentence wraps at 420 pt | `layout/S38-tooltip-snap-w980-dark-rt@8188b73.json` | — |
| `S38-tooltip-snap-w980-light-rt@8188b73.png` | light | 980×640 | the Snap tooltip below the Snap button; the long sentence wraps at 420 pt | `layout/S38-tooltip-snap-w980-light-rt@8188b73.json` | — |
| `S38-tooltip-wipe-annotations-w980-dark-rt@8188b73.png` | dark | 980×640 | Wipe over artwork: the plate says Remove annotations | `layout/S38-tooltip-wipe-annotations-w980-dark-rt@8188b73.json` | — |
| `S38-tooltip-wipe-annotations-w980-light-rt@8188b73.png` | light | 980×640 | Wipe over artwork: the plate says Remove annotations | `layout/S38-tooltip-wipe-annotations-w980-light-rt@8188b73.json` | — |
| `S38-tooltip-wipe-blank-w980-dark-rt@8188b73.png` | dark | 980×640 | Wipe on a blank canvas: dimmed, the plate says Nothing to clear | `layout/S38-tooltip-wipe-blank-w980-dark-rt@8188b73.json` | — |
| `S38-tooltip-wipe-blank-w980-light-rt@8188b73.png` | light | 980×640 | Wipe on a blank canvas: dimmed, the plate says Nothing to clear | `layout/S38-tooltip-wipe-blank-w980-light-rt@8188b73.json` | — |
| `S38-tooltip-wipe-image-w980-dark-rt@8188b73.png` | dark | 980×640 | Wipe over a snap alone: the plate says Clear image | `layout/S38-tooltip-wipe-image-w980-dark-rt@8188b73.json` | — |
| `S38-tooltip-wipe-image-w980-light-rt@8188b73.png` | light | 980×640 | Wipe over a snap alone: the plate says Clear image | `layout/S38-tooltip-wipe-image-w980-light-rt@8188b73.json` | — |
| `S38-tooltip-zoom-w980-dark-rt@8188b73.png` | dark | 980×640 | a bottom-bar control: the plate opens above the zoom face because there is no room below | `layout/S38-tooltip-zoom-w980-dark-rt@8188b73.json` | — |
| `S38-tooltip-zoom-w980-light-rt@8188b73.png` | light | 980×640 | a bottom-bar control: the plate opens above the zoom face because there is no room below | `layout/S38-tooltip-zoom-w980-light-rt@8188b73.json` | — |
| `S39-discard-sheet-dark-rt@8188b73.png` | dark | 1280×800 | Save your drawing? sheet over the titled window (Save / Cancel / Don’t Save) | `—` | — |
| `S39-discard-sheet-light-rt@8188b73.png` | light | 1280×800 | Save your drawing? sheet over the titled window (Save / Cancel / Don’t Save) | `—` | — |
| `S39-titlebar-crop-w1280-dark-rt@8188b73.png` | dark | 1280×800 | the title bar and top bar only, at w1280 | `layout/S39-titlebar-crop-w1280-dark-rt@8188b73.json` | — |
| `S39-titlebar-crop-w1280-light-rt@8188b73.png` | light | 1280×800 | the title bar and top bar only, at w1280 | `layout/S39-titlebar-crop-w1280-light-rt@8188b73.json` | — |
| `S39-titlebar-crop-w980-dark-rt@8188b73.png` | dark | 980×640 | the title bar and top bar only, at w980 | `layout/S39-titlebar-crop-w980-dark-rt@8188b73.json` | — |
| `S39-titlebar-crop-w980-light-rt@8188b73.png` | light | 980×640 | the title bar and top bar only, at w980 | `layout/S39-titlebar-crop-w980-light-rt@8188b73.json` | — |
| `S39-titled-window-w1280-dark-rt@8188b73.png` | dark | 1280×800 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w1280 | `layout/S39-titled-window-w1280-dark-rt@8188b73.json` | — |
| `S39-titled-window-w1280-light-rt@8188b73.png` | light | 1280×800 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w1280 | `layout/S39-titled-window-w1280-light-rt@8188b73.json` | — |
| `S39-titled-window-w980-dark-rt@8188b73.png` | dark | 980×640 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w980 | `layout/S39-titled-window-w980-dark-rt@8188b73.json` | — |
| `S39-titled-window-w980-light-rt@8188b73.png` | light | 980×640 | title = document name, subtitle = size, proxy icon, no title-bar separator, at w980 | `layout/S39-titled-window-w980-light-rt@8188b73.json` | — |
| `S39-upload-error-sheet-dark-rt@8188b73.png` | dark | 1280×800 | Details… sheet after a stubbed failed upload (the error itself is inline), over the titled window | `—` | — |
| `S39-upload-error-sheet-light-rt@8188b73.png` | light | 1280×800 | Details… sheet after a stubbed failed upload (the error itself is inline), over the titled window | `—` | — |
| `S40-border-crop-tool-dark-rt@8188b73.png` | dark | 1084×768 | Crop tool chosen: the handles stay on without hover | `layout/S40-border-crop-tool-dark-rt@8188b73.json` | — |
| `S40-border-crop-tool-light-rt@8188b73.png` | light | 1084×768 | Crop tool chosen: the handles stay on without hover | `layout/S40-border-crop-tool-light-rt@8188b73.json` | — |
| `S40-border-hover-dark-rt@8188b73.png` | dark | 1084×768 | Pointer over the border: the accent outline and the four corner handles | `layout/S40-border-hover-dark-rt@8188b73.json` | — |
| `S40-border-hover-light-rt@8188b73.png` | light | 1084×768 | Pointer over the border: the accent outline and the four corner handles | `layout/S40-border-hover-light-rt@8188b73.json` | — |
| `S40-border-rest-dark-rt@8188b73.png` | dark | 1084×768 | Canvas border at rest: a separator hairline, no handles | `layout/S40-border-rest-dark-rt@8188b73.json` | — |
| `S40-border-rest-light-rt@8188b73.png` | light | 1084×768 | Canvas border at rest: a separator hairline, no handles | `layout/S40-border-rest-light-rt@8188b73.json` | — |
| `S40-drag-focus-dark-rt@8188b73.png` | dark | 980×640 | Drag well keyboard-focused (Space or Return opens the Export panel) | `layout/S40-drag-focus-dark-rt@8188b73.json` | — |
| `S40-drag-focus-light-rt@8188b73.png` | light | 980×640 | Drag well keyboard-focused (Space or Return opens the Export panel) | `layout/S40-drag-focus-light-rt@8188b73.json` | — |
| `S40-drag-hover-dark-rt@8188b73.png` | dark | 980×640 | Drag well hovered: the cell takes the label 0.08 fill; the pointer is an open hand | `layout/S40-drag-hover-dark-rt@8188b73.json` | — |
| `S40-drag-hover-light-rt@8188b73.png` | light | 980×640 | Drag well hovered: the cell takes the label 0.08 fill; the pointer is an open hand | `layout/S40-drag-hover-light-rt@8188b73.json` | — |
| `S40-drag-pressed-dark-rt@8188b73.png` | dark | 980×640 | Drag well held: the cell takes the 0.16 fill; the pointer is a closed hand | `layout/S40-drag-pressed-dark-rt@8188b73.json` | — |
| `S40-drag-pressed-light-rt@8188b73.png` | light | 980×640 | Drag well held: the cell takes the 0.16 fill; the pointer is a closed hand | `layout/S40-drag-pressed-light-rt@8188b73.json` | — |
| `S40-drag-rest-dark-rt@8188b73.png` | dark | 980×640 | Drag well at rest: the open-hand glyph, no plate | `layout/S40-drag-rest-dark-rt@8188b73.json` | — |
| `S40-drag-rest-light-rt@8188b73.png` | light | 980×640 | Drag well at rest: the open-hand glyph, no plate | `layout/S40-drag-rest-light-rt@8188b73.json` | — |
| `S40-size-pill-disabled-dark-rt@8188b73.png` | dark | 980×640 | Size pill disabled: stroke dimmed to 0.38, no fill, not draggable | `layout/S40-size-pill-disabled-dark-rt@8188b73.json` | — |
| `S40-size-pill-disabled-light-rt@8188b73.png` | light | 980×640 | Size pill disabled: stroke dimmed to 0.38, no fill, not draggable | `layout/S40-size-pill-disabled-light-rt@8188b73.json` | — |
| `S40-size-pill-focus-dark-rt@8188b73.png` | dark | 980×640 | Size pill keyboard-focused | `layout/S40-size-pill-focus-dark-rt@8188b73.json` | — |
| `S40-size-pill-focus-light-rt@8188b73.png` | light | 980×640 | Size pill keyboard-focused | `layout/S40-size-pill-focus-light-rt@8188b73.json` | — |
| `S40-size-pill-hover-dark-rt@8188b73.png` | dark | 980×640 | Size pill hovered: the cell takes the label 0.08 fill | `layout/S40-size-pill-hover-dark-rt@8188b73.json` | — |
| `S40-size-pill-hover-light-rt@8188b73.png` | light | 980×640 | Size pill hovered: the cell takes the label 0.08 fill | `layout/S40-size-pill-hover-light-rt@8188b73.json` | — |
| `S40-size-pill-pressed-dark-rt@8188b73.png` | dark | 980×640 | Size pill pressed: the cell takes the 0.16 fill and the stroke is drawn 0.96 shorter | `layout/S40-size-pill-pressed-dark-rt@8188b73.json` | — |
| `S40-size-pill-pressed-light-rt@8188b73.png` | light | 980×640 | Size pill pressed: the cell takes the 0.16 fill and the stroke is drawn 0.96 shorter | `layout/S40-size-pill-pressed-light-rt@8188b73.json` | — |
| `S40-size-pill-rest-dark-rt@8188b73.png` | dark | 980×640 | Size pill at rest: the stroke is the current thickness (6.75) | `layout/S40-size-pill-rest-dark-rt@8188b73.json` | — |
| `S40-size-pill-rest-light-rt@8188b73.png` | light | 980×640 | Size pill at rest: the stroke is the current thickness (6.75) | `layout/S40-size-pill-rest-light-rt@8188b73.json` | — |
| `S40-size-preset-hover-dark-rt@8188b73.png` | dark | 980×640 | Size popover, the smallest preset hovered (command hover fill) beside the selected one | `layout/S40-size-preset-hover-dark-rt@8188b73.json` | — |
| `S40-size-preset-hover-light-rt@8188b73.png` | light | 980×640 | Size popover, the smallest preset hovered (command hover fill) beside the selected one | `layout/S40-size-preset-hover-light-rt@8188b73.json` | — |
| `S40-size-track-hover-dark-rt@8188b73.png` | dark | 980×640 | Size popover, pointer over the track: the knob grows to 1.15 | `layout/S40-size-track-hover-dark-rt@8188b73.json` | — |
| `S40-size-track-hover-light-rt@8188b73.png` | light | 980×640 | Size popover, pointer over the track: the knob grows to 1.15 | `layout/S40-size-track-hover-light-rt@8188b73.json` | — |
| `S40-size-track-pressed-dark-rt@8188b73.png` | dark | 980×640 | Size popover, knob held: the knob at 1.25 and an accent 0.3 wash over the track | `layout/S40-size-track-pressed-dark-rt@8188b73.json` | — |
| `S40-size-track-pressed-light-rt@8188b73.png` | light | 980×640 | Size popover, knob held: the knob at 1.25 and an accent 0.3 wash over the track | `layout/S40-size-track-pressed-light-rt@8188b73.json` | — |
| `S40-snap-disabled-dark-rt@8188b73.png` | dark | 980×640 | Snap disabled: the accent dimmed to 0.38 | `layout/S40-snap-disabled-dark-rt@8188b73.json` | — |
| `S40-snap-disabled-light-rt@8188b73.png` | light | 980×640 | Snap disabled: the accent dimmed to 0.38 | `layout/S40-snap-disabled-light-rt@8188b73.json` | — |
| `S40-snap-focus-dark-rt@8188b73.png` | dark | 980×640 | Snap keyboard-focused | `layout/S40-snap-focus-dark-rt@8188b73.json` | — |
| `S40-snap-focus-light-rt@8188b73.png` | light | 980×640 | Snap keyboard-focused | `layout/S40-snap-focus-light-rt@8188b73.json` | — |
| `S40-snap-hover-dark-rt@8188b73.png` | dark | 980×640 | Snap hovered: the accent brightened 8 % | `layout/S40-snap-hover-dark-rt@8188b73.json` | — |
| `S40-snap-hover-light-rt@8188b73.png` | light | 980×640 | Snap hovered: the accent brightened 8 % | `layout/S40-snap-hover-light-rt@8188b73.json` | — |
| `S40-snap-pressed-dark-rt@8188b73.png` | dark | 980×640 | Snap pressed: the accent darkened 12 % and the glyph at 0.96 | `layout/S40-snap-pressed-dark-rt@8188b73.json` | — |
| `S40-snap-pressed-light-rt@8188b73.png` | light | 980×640 | Snap pressed: the accent darkened 12 % and the glyph at 0.96 | `layout/S40-snap-pressed-light-rt@8188b73.json` | — |
| `S40-snap-rest-dark-rt@8188b73.png` | dark | 980×640 | Snap at rest: opaque accent fill, glyph colour computed against it | `layout/S40-snap-rest-dark-rt@8188b73.json` | — |
| `S40-snap-rest-light-rt@8188b73.png` | light | 980×640 | Snap at rest: opaque accent fill, glyph colour computed against it | `layout/S40-snap-rest-light-rt@8188b73.json` | — |
| `S40-swatch-states-dark-rt@8188b73.png` | dark | 980×640 | Colour popover: Red selected (3 pt accent outline and check glyph), Blue hovered (label 0.5 outline), Translucent gray pressed (0.16 fill) | `—` | — |
| `S40-swatch-states-light-rt@8188b73.png` | light | 980×640 | Colour popover: Red selected (3 pt accent outline and check glyph), Blue hovered (label 0.5 outline), Translucent gray pressed (0.16 fill) | `—` | — |
| `S40-toggle-disabled-dark-rt@8188b73.png` | dark | 980×640 | PNG / JPG disabled: both segments' content at 0.38 | `layout/S40-toggle-disabled-dark-rt@8188b73.json` | — |
| `S40-toggle-disabled-light-rt@8188b73.png` | light | 980×640 | PNG / JPG disabled: both segments' content at 0.38 | `layout/S40-toggle-disabled-light-rt@8188b73.json` | — |
| `S40-toggle-focus-dark-rt@8188b73.png` | dark | 980×640 | PNG / JPG keyboard-focused (Left, Right and Space change the format) | `layout/S40-toggle-focus-dark-rt@8188b73.json` | — |
| `S40-toggle-focus-light-rt@8188b73.png` | light | 980×640 | PNG / JPG keyboard-focused (Left, Right and Space change the format) | `layout/S40-toggle-focus-light-rt@8188b73.json` | — |
| `S40-toggle-hover-dark-rt@8188b73.png` | dark | 980×640 | PNG selected, JPG hovered: label 0.08 plate | `layout/S40-toggle-hover-dark-rt@8188b73.json` | — |
| `S40-toggle-hover-light-rt@8188b73.png` | light | 980×640 | PNG selected, JPG hovered: label 0.08 plate | `layout/S40-toggle-hover-light-rt@8188b73.json` | — |
| `S40-toggle-jpg-dark-rt@8188b73.png` | dark | 980×640 | PNG / JPG with JPG selected | `layout/S40-toggle-jpg-dark-rt@8188b73.json` | — |
| `S40-toggle-jpg-light-rt@8188b73.png` | light | 980×640 | PNG / JPG with JPG selected | `layout/S40-toggle-jpg-light-rt@8188b73.json` | — |
| `S40-toggle-png-dark-rt@8188b73.png` | dark | 980×640 | PNG / JPG with PNG selected: accent 0.20 plate, 1 pt border, bodyStrong text; JPG on its faint plate | `layout/S40-toggle-png-dark-rt@8188b73.json` | — |
| `S40-toggle-png-light-rt@8188b73.png` | light | 980×640 | PNG / JPG with PNG selected: accent 0.20 plate, 1 pt border, bodyStrong text; JPG on its faint plate | `layout/S40-toggle-png-light-rt@8188b73.json` | — |
| `S40-toggle-pressed-dark-rt@8188b73.png` | dark | 980×640 | PNG selected, JPG pressed: label 0.16 plate | `layout/S40-toggle-pressed-dark-rt@8188b73.json` | — |
| `S40-toggle-pressed-light-rt@8188b73.png` | light | 980×640 | PNG selected, JPG pressed: label 0.16 plate | `layout/S40-toggle-pressed-light-rt@8188b73.json` | — |
| `S40-tool-disabled-dark-rt@8188b73.png` | dark | 980×640 | Rectangle tool disabled: no fill, content dimmed to 0.38 | `layout/S40-tool-disabled-dark-rt@8188b73.json` | — |
| `S40-tool-disabled-light-rt@8188b73.png` | light | 980×640 | Rectangle tool disabled: no fill, content dimmed to 0.38 | `layout/S40-tool-disabled-light-rt@8188b73.json` | — |
| `S40-tool-focus-dark-rt@8188b73.png` | dark | 980×640 | Rectangle tool keyboard-focused: AppKit's focus ring drawn through the button's own rounded mask | `layout/S40-tool-focus-dark-rt@8188b73.json` | — |
| `S40-tool-focus-light-rt@8188b73.png` | light | 980×640 | Rectangle tool keyboard-focused: AppKit's focus ring drawn through the button's own rounded mask | `layout/S40-tool-focus-light-rt@8188b73.json` | — |
| `S40-tool-hover-dark-rt@8188b73.png` | dark | 980×640 | Rectangle tool hovered: a label 0.08 fill (0.16 under Increase Contrast); Brush still selected | `layout/S40-tool-hover-dark-rt@8188b73.json` | — |
| `S40-tool-hover-light-rt@8188b73.png` | light | 980×640 | Rectangle tool hovered: a label 0.08 fill (0.16 under Increase Contrast); Brush still selected | `layout/S40-tool-hover-light-rt@8188b73.json` | — |
| `S40-tool-pressed-dark-rt@8188b73.png` | dark | 980×640 | Rectangle tool pressed: a label 0.16 fill (0.28 under Increase Contrast) and the glyph drawn at 0.96 | `layout/S40-tool-pressed-dark-rt@8188b73.json` | — |
| `S40-tool-pressed-light-rt@8188b73.png` | light | 980×640 | Rectangle tool pressed: a label 0.16 fill (0.28 under Increase Contrast) and the glyph drawn at 0.96 | `layout/S40-tool-pressed-light-rt@8188b73.json` | — |
| `S40-tool-selected-focus-dark-rt@8188b73.png` | dark | 980×640 | Brush (selected) keyboard-focused: the ring around the selection fill | `layout/S40-tool-selected-focus-dark-rt@8188b73.json` | — |
| `S40-tool-selected-focus-light-rt@8188b73.png` | light | 980×640 | Brush (selected) keyboard-focused: the ring around the selection fill | `layout/S40-tool-selected-focus-light-rt@8188b73.json` | — |
| `S40-tool-selected-hover-dark-rt@8188b73.png` | dark | 980×640 | Brush (selected) hovered: hover does not wash out the selection | `layout/S40-tool-selected-hover-dark-rt@8188b73.json` | — |
| `S40-tool-selected-hover-light-rt@8188b73.png` | light | 980×640 | Brush (selected) hovered: hover does not wash out the selection | `layout/S40-tool-selected-hover-light-rt@8188b73.json` | — |
| `S40-tool-selected-pressed-dark-rt@8188b73.png` | dark | 980×640 | Brush (selected) pressed: the selected fill deepens by 0.12 | `layout/S40-tool-selected-pressed-dark-rt@8188b73.json` | — |
| `S40-tool-selected-pressed-light-rt@8188b73.png` | light | 980×640 | Brush (selected) pressed: the selected fill deepens by 0.12 | `layout/S40-tool-selected-pressed-light-rt@8188b73.json` | — |
| `S40-tool-selected-rest-dark-rt@8188b73.png` | dark | 980×640 | Brush selected (accent 0.20 fill, 1 pt accent border, computed glyph colour; a 2 x 16 pt capsule under Differentiate Without Color); the other nine tools at rest | `layout/S40-tool-selected-rest-dark-rt@8188b73.json` | — |
| `S40-tool-selected-rest-light-rt@8188b73.png` | light | 980×640 | Brush selected (accent 0.20 fill, 1 pt accent border, computed glyph colour; a 2 x 16 pt capsule under Differentiate Without Color); the other nine tools at rest | `layout/S40-tool-selected-rest-light-rt@8188b73.json` | — |
| `S40-undo-focus-dark-rt@8188b73.png` | dark | 980×640 | Undo keyboard-focused | `layout/S40-undo-focus-dark-rt@8188b73.json` | — |
| `S40-undo-focus-light-rt@8188b73.png` | light | 980×640 | Undo keyboard-focused | `layout/S40-undo-focus-light-rt@8188b73.json` | — |
| `S40-undo-hover-dark-rt@8188b73.png` | dark | 980×640 | Undo hovered: label 0.08 fill | `layout/S40-undo-hover-dark-rt@8188b73.json` | — |
| `S40-undo-hover-light-rt@8188b73.png` | light | 980×640 | Undo hovered: label 0.08 fill | `layout/S40-undo-hover-light-rt@8188b73.json` | — |
| `S40-undo-wipe-disabled-dark-rt@8188b73.png` | dark | 980×640 | Undo and Wipe disabled: no fill, content at 0.38 | `layout/S40-undo-wipe-disabled-dark-rt@8188b73.json` | — |
| `S40-undo-wipe-disabled-light-rt@8188b73.png` | light | 980×640 | Undo and Wipe disabled: no fill, content at 0.38 | `layout/S40-undo-wipe-disabled-light-rt@8188b73.json` | — |
| `S40-wipe-pressed-dark-rt@8188b73.png` | dark | 980×640 | Wipe pressed: label 0.16 fill, glyph at 0.96 | `layout/S40-wipe-pressed-dark-rt@8188b73.json` | — |
| `S40-wipe-pressed-light-rt@8188b73.png` | light | 980×640 | Wipe pressed: label 0.16 fill, glyph at 0.96 | `layout/S40-wipe-pressed-light-rt@8188b73.json` | — |
| `S50-toolbox-chosen-dark-rt@8188b73.png` | dark | 1488×1179 | Toolbox panel with a filled rectangle selected: the toggle and tool rows that are on | `—` | — |
| `S50-toolbox-chosen-light-rt@8188b73.png` | light | 1488×1179 | Toolbox panel with a filled rectangle selected: the toggle and tool rows that are on | `—` | — |
| `S50-toolbox-disabled-dark-rt@8188b73.png` | dark | 1488×1179 | Toolbox panel while a frame capture is in progress (validation refuses the style rows); disabled row 15 (Filled Shapes) hovered and offered focus; the arrow keys walked past it | `—` | — |
| `S50-toolbox-disabled-light-rt@8188b73.png` | light | 1488×1179 | Toolbox panel while a frame capture is in progress (validation refuses the style rows); disabled row 15 (Filled Shapes) hovered and offered focus; the arrow keys walked past it | `—` | — |
| `S50-toolbox-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | Toolbox panel dismissed with Escape: gone, focus back on the Toolbox button | `layout/S50-toolbox-dismissed-dark-rt@8188b73.json` | — |
| `S50-toolbox-dismissed-light-rt@8188b73.png` | light | 1488×1179 | Toolbox panel dismissed with Escape: gone, focus back on the Toolbox button | `layout/S50-toolbox-dismissed-light-rt@8188b73.json` | — |
| `S50-toolbox-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Toolbox panel open on a drawing with nothing selected; keyboard focus on row 0 (Save to History) | `—` | — |
| `S50-toolbox-focus-light-rt@8188b73.png` | light | 1488×1179 | Toolbox panel open on a drawing with nothing selected; keyboard focus on row 0 (Save to History) | `—` | — |
| `S50-toolbox-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Toolbox panel open on a drawing with nothing selected; row 1 (Export…) hovered | `—` | — |
| `S50-toolbox-hover-light-rt@8188b73.png` | light | 1488×1179 | Toolbox panel open on a drawing with nothing selected; row 1 (Export…) hovered | `—` | — |
| `S50-toolbox-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Toolbox panel open on a drawing with nothing selected | `—` | — |
| `S50-toolbox-rest-light-rt@8188b73.png` | light | 1488×1179 | Toolbox panel open on a drawing with nothing selected | `—` | — |
| `S50-toolbox-rest-only-dark-rt@8188b73.png` | dark | 1488×1179 | Toolbox panel open on a drawing with nothing selected (the panel window alone) | `—` | — |
| `S50-toolbox-rest-only-light-rt@8188b73.png` | light | 1488×1179 | Toolbox panel open on a drawing with nothing selected (the panel window alone) | `—` | — |
| `S51-zoom-actual-size-dark-rt@8188b73.png` | dark | 1662×1179 | Zoom panel while Actual Size is on: the Actual Size toggle row is chosen and the face shows Actual | `—` | — |
| `S51-zoom-actual-size-light-rt@8188b73.png` | light | 1662×1179 | Zoom panel while Actual Size is on: the Actual Size toggle row is chosen and the face shows Actual | `—` | — |
| `S51-zoom-chosen-dark-rt@8188b73.png` | dark | 1488×1179 | Zoom panel: the computed Fit row is the chosen row | `—` | — |
| `S51-zoom-chosen-light-rt@8188b73.png` | light | 1488×1179 | Zoom panel: the computed Fit row is the chosen row | `—` | — |
| `S51-zoom-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | Zoom panel dismissed with Escape: gone, focus back on the zoom button | `layout/S51-zoom-dismissed-dark-rt@8188b73.json` | — |
| `S51-zoom-dismissed-light-rt@8188b73.png` | light | 1488×1179 | Zoom panel dismissed with Escape: gone, focus back on the zoom button | `layout/S51-zoom-dismissed-light-rt@8188b73.json` | — |
| `S51-zoom-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Zoom panel open with a computed Fit row chosen; keyboard focus on row 0 (Fit, 100%) | `—` | — |
| `S51-zoom-focus-light-rt@8188b73.png` | light | 1488×1179 | Zoom panel open with a computed Fit row chosen; keyboard focus on row 0 (Fit, 100%) | `—` | — |
| `S51-zoom-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Zoom panel open with a computed Fit row chosen; row 1 (25%) hovered | `—` | — |
| `S51-zoom-hover-light-rt@8188b73.png` | light | 1488×1179 | Zoom panel open with a computed Fit row chosen; row 1 (25%) hovered | `—` | — |
| `S51-zoom-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Zoom panel open with a computed Fit row chosen | `—` | — |
| `S51-zoom-rest-light-rt@8188b73.png` | light | 1488×1179 | Zoom panel open with a computed Fit row chosen | `—` | — |
| `S51-zoom-rest-only-dark-rt@8188b73.png` | dark | 1488×1179 | Zoom panel open with a computed Fit row chosen (the panel window alone) | `—` | — |
| `S51-zoom-rest-only-light-rt@8188b73.png` | light | 1488×1179 | Zoom panel open with a computed Fit row chosen (the panel window alone) | `—` | — |
| `S52-upload-busy-dark-rt@8188b73.png` | dark | 1488×1179 | Upload panel while an upload runs: Cancel Upload leads the rows | `—` | — |
| `S52-upload-busy-light-rt@8188b73.png` | light | 1488×1179 | Upload panel while an upload runs: Cancel Upload leads the rows | `—` | — |
| `S52-upload-chosen-dark-rt@8188b73.png` | dark | 1488×1179 | Upload panel after the default was switched to the second destination: the check follows it | `—` | — |
| `S52-upload-chosen-light-rt@8188b73.png` | light | 1488×1179 | Upload panel after the default was switched to the second destination: the check follows it | `—` | — |
| `S52-upload-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | Upload panel dismissed with Escape: gone, focus back on the Upload button | `layout/S52-upload-dismissed-dark-rt@8188b73.json` | — |
| `S52-upload-dismissed-light-rt@8188b73.png` | light | 1488×1179 | Upload panel dismissed with Escape: gone, focus back on the Upload button | `layout/S52-upload-dismissed-light-rt@8188b73.json` | — |
| `S52-upload-empty-dark-rt@8188b73.png` | dark | 1488×1179 | Upload panel with no destination saved: the disabled No destination configured row, Destination Settings… and Share with macOS… | `—` | — |
| `S52-upload-empty-light-rt@8188b73.png` | light | 1488×1179 | Upload panel with no destination saved: the disabled No destination configured row, Destination Settings… and Share with macOS… | `—` | — |
| `S52-upload-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Upload panel with three fake destinations, the default checked; keyboard focus on row 0 (Example S3) | `—` | — |
| `S52-upload-focus-light-rt@8188b73.png` | light | 1488×1179 | Upload panel with three fake destinations, the default checked; keyboard focus on row 0 (Example S3) | `—` | — |
| `S52-upload-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Upload panel with three fake destinations, the default checked; row 1 (Example SFTP) hovered | `—` | — |
| `S52-upload-hover-light-rt@8188b73.png` | light | 1488×1179 | Upload panel with three fake destinations, the default checked; row 1 (Example SFTP) hovered | `—` | — |
| `S52-upload-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Upload panel with three fake destinations, the default checked | `—` | — |
| `S52-upload-rest-light-rt@8188b73.png` | light | 1488×1179 | Upload panel with three fake destinations, the default checked | `—` | — |
| `S52-upload-rest-only-dark-rt@8188b73.png` | dark | 1488×1179 | Upload panel with three fake destinations, the default checked (the panel window alone) | `—` | — |
| `S52-upload-rest-only-light-rt@8188b73.png` | light | 1488×1179 | Upload panel with three fake destinations, the default checked (the panel window alone) | `—` | — |
| `S53-color-custom-dark-rt@8188b73.png` | dark | 1488×1179 | Colour panel with a custom colour chosen: the Custom color… row carries the chip and the check | `—` | — |
| `S53-color-custom-light-rt@8188b73.png` | light | 1488×1179 | Colour panel with a custom colour chosen: the Custom color… row carries the chip and the check | `—` | — |
| `S53-color-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | Colour panel dismissed with Escape: gone, focus back on the colour swatch | `layout/S53-color-dismissed-dark-rt@8188b73.json` | — |
| `S53-color-dismissed-light-rt@8188b73.png` | light | 1488×1179 | Colour panel dismissed with Escape: gone, focus back on the colour swatch | `layout/S53-color-dismissed-light-rt@8188b73.json` | — |
| `S53-color-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Colour panel open with the first preset chosen; keyboard focus on row 0 (Red) | `—` | — |
| `S53-color-focus-light-rt@8188b73.png` | light | 1488×1179 | Colour panel open with the first preset chosen; keyboard focus on row 0 (Red) | `—` | — |
| `S53-color-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Colour panel open with the first preset chosen; row 1 (Yellow) hovered | `—` | — |
| `S53-color-hover-light-rt@8188b73.png` | light | 1488×1179 | Colour panel open with the first preset chosen; row 1 (Yellow) hovered | `—` | — |
| `S53-color-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Colour panel open with the first preset chosen | `—` | — |
| `S53-color-rest-light-rt@8188b73.png` | light | 1488×1179 | Colour panel open with the first preset chosen | `—` | — |
| `S53-color-rest-only-dark-rt@8188b73.png` | dark | 1488×1179 | Colour panel open with the first preset chosen (the panel window alone) | `—` | — |
| `S53-color-rest-only-light-rt@8188b73.png` | light | 1488×1179 | Colour panel open with the first preset chosen (the panel window alone) | `—` | — |
| `S54-size-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | Size panel dismissed with Escape: gone, focus back on the size pill | `layout/S54-size-dismissed-dark-rt@8188b73.json` | — |
| `S54-size-dismissed-light-rt@8188b73.png` | light | 1488×1179 | Size panel dismissed with Escape: gone, focus back on the size pill | `layout/S54-size-dismissed-light-rt@8188b73.json` | — |
| `S54-size-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Size panel open with a preset size chosen; keyboard focus on row 0 (Size 2) | `—` | — |
| `S54-size-focus-light-rt@8188b73.png` | light | 1488×1179 | Size panel open with a preset size chosen; keyboard focus on row 0 (Size 2) | `—` | — |
| `S54-size-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Size panel open with a preset size chosen; row 1 (Size 4) hovered | `—` | — |
| `S54-size-hover-light-rt@8188b73.png` | light | 1488×1179 | Size panel open with a preset size chosen; row 1 (Size 4) hovered | `—` | — |
| `S54-size-pressed-dark-rt@8188b73.png` | dark | 1488×1179 | Size panel with the track held down | `—` | — |
| `S54-size-pressed-light-rt@8188b73.png` | light | 1488×1179 | Size panel with the track held down | `—` | — |
| `S54-size-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Size panel open with a preset size chosen | `—` | — |
| `S54-size-rest-light-rt@8188b73.png` | light | 1488×1179 | Size panel open with a preset size chosen | `—` | — |
| `S54-size-rest-only-dark-rt@8188b73.png` | dark | 1488×1179 | Size panel open with a preset size chosen (the panel window alone) | `—` | — |
| `S54-size-rest-only-light-rt@8188b73.png` | light | 1488×1179 | Size panel open with a preset size chosen (the panel window alone) | `—` | — |
| `S55-history-category-focus-dark-rt@8188b73.png` | dark | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate; keyboard focus on row 0 (All) | `—` | — |
| `S55-history-category-focus-light-rt@8188b73.png` | light | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate; keyboard focus on row 0 (All) | `—` | — |
| `S55-history-category-hover-dark-rt@8188b73.png` | dark | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate; row 1 (Shared) hovered | `—` | — |
| `S55-history-category-hover-light-rt@8188b73.png` | light | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate; row 1 (Shared) hovered | `—` | — |
| `S55-history-category-rest-dark-rt@8188b73.png` | dark | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate | `—` | — |
| `S55-history-category-rest-light-rt@8188b73.png` | light | 1488×1179 | History: the All / Shared / Exported / Saved category group on one plate | `—` | — |
| `S55-history-date-chosen-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Date filter panel with its chosen row | `—` | — |
| `S55-history-date-chosen-light-rt@8188b73.png` | light | 1488×1179 | History: the Date filter panel with its chosen row | `—` | — |
| `S55-history-date-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | Date filter choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S55-history-date-dismissed-light-rt@8188b73.png` | light | 1488×1179 | Date filter choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S55-history-date-focus-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Date filter choices open; keyboard focus on row 0 (All dates) | `—` | — |
| `S55-history-date-focus-light-rt@8188b73.png` | light | 1488×1179 | History: the Date filter choices open; keyboard focus on row 0 (All dates) | `—` | — |
| `S55-history-date-hover-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Date filter choices open; row 1 (Last hour) hovered | `—` | — |
| `S55-history-date-hover-light-rt@8188b73.png` | light | 1488×1179 | History: the Date filter choices open; row 1 (Last hour) hovered | `—` | — |
| `S55-history-date-rest-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Date filter choices open | `—` | — |
| `S55-history-date-rest-light-rt@8188b73.png` | light | 1488×1179 | History: the Date filter choices open | `—` | — |
| `S55-history-date-rest-only-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Date filter choices open (the panel window alone) | `—` | — |
| `S55-history-date-rest-only-light-rt@8188b73.png` | light | 1488×1179 | History: the Date filter choices open (the panel window alone) | `—` | — |
| `S55-history-dragas-chosen-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Drag as panel with its chosen row | `—` | — |
| `S55-history-dragas-chosen-light-rt@8188b73.png` | light | 1488×1179 | History: the Drag as panel with its chosen row | `—` | — |
| `S55-history-dragas-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | Drag as choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S55-history-dragas-dismissed-light-rt@8188b73.png` | light | 1488×1179 | Drag as choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S55-history-dragas-focus-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Drag as choices open; keyboard focus on row 0 (PNG) | `—` | — |
| `S55-history-dragas-focus-light-rt@8188b73.png` | light | 1488×1179 | History: the Drag as choices open; keyboard focus on row 0 (PNG) | `—` | — |
| `S55-history-dragas-hover-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Drag as choices open; row 1 (JPG) hovered | `—` | — |
| `S55-history-dragas-hover-light-rt@8188b73.png` | light | 1488×1179 | History: the Drag as choices open; row 1 (JPG) hovered | `—` | — |
| `S55-history-dragas-rest-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Drag as choices open | `—` | — |
| `S55-history-dragas-rest-light-rt@8188b73.png` | light | 1488×1179 | History: the Drag as choices open | `—` | — |
| `S55-history-dragas-rest-only-dark-rt@8188b73.png` | dark | 1488×1179 | History: the Drag as choices open (the panel window alone) | `—` | — |
| `S55-history-dragas-rest-only-light-rt@8188b73.png` | light | 1488×1179 | History: the Drag as choices open (the panel window alone) | `—` | — |
| `S56-settings-actions-disabled-dark-rt@8188b73.png` | dark | 1488×1179 | Settings, Upload: the destination action plate; disabled row 3 (Make Default) hovered and offered focus | `—` | — |
| `S56-settings-actions-disabled-light-rt@8188b73.png` | light | 1488×1179 | Settings, Upload: the destination action plate; disabled row 3 (Make Default) hovered and offered focus | `—` | — |
| `S56-settings-actions-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Settings, Upload: the destination action plate; keyboard focus on row 0 (Add…) | `—` | — |
| `S56-settings-actions-focus-light-rt@8188b73.png` | light | 1488×1179 | Settings, Upload: the destination action plate; keyboard focus on row 0 (Add…) | `—` | — |
| `S56-settings-actions-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Settings, Upload: the destination action plate; row 0 (Add…) hovered | `—` | — |
| `S56-settings-actions-hover-light-rt@8188b73.png` | light | 1488×1179 | Settings, Upload: the destination action plate; row 0 (Add…) hovered | `—` | — |
| `S56-settings-actions-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Settings, Upload: the destination action plate | `—` | — |
| `S56-settings-actions-rest-light-rt@8188b73.png` | light | 1488×1179 | Settings, Upload: the destination action plate | `—` | — |
| `S56-settings-radios-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Settings: Presence, Precision and Arrow head radios; keyboard focus on row 2 (Both) | `—` | — |
| `S56-settings-radios-focus-light-rt@8188b73.png` | light | 1488×1179 | Settings: Presence, Precision and Arrow head radios; keyboard focus on row 2 (Both) | `—` | — |
| `S56-settings-radios-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Settings: Presence, Precision and Arrow head radios; row 0 (Dock) hovered | `—` | — |
| `S56-settings-radios-hover-light-rt@8188b73.png` | light | 1488×1179 | Settings: Presence, Precision and Arrow head radios; row 0 (Dock) hovered | `—` | — |
| `S56-settings-radios-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Settings: Presence, Precision and Arrow head radios | `—` | — |
| `S56-settings-radios-rest-light-rt@8188b73.png` | light | 1488×1179 | Settings: Presence, Precision and Arrow head radios | `—` | — |
| `S56-settings-tabs-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Settings tab strip on one glass plate; keyboard focus on row 0 (General) | `—` | — |
| `S56-settings-tabs-focus-light-rt@8188b73.png` | light | 1488×1179 | Settings tab strip on one glass plate; keyboard focus on row 0 (General) | `—` | — |
| `S56-settings-tabs-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Settings tab strip on one glass plate; row 1 (Drawing) hovered | `—` | — |
| `S56-settings-tabs-hover-light-rt@8188b73.png` | light | 1488×1179 | Settings tab strip on one glass plate; row 1 (Drawing) hovered | `—` | — |
| `S56-settings-tabs-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Settings tab strip on one glass plate | `—` | — |
| `S56-settings-tabs-rest-light-rt@8188b73.png` | light | 1488×1179 | Settings tab strip on one glass plate | `—` | — |
| `S56-settings-toggles-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles; keyboard focus on row 0 (Show hover hints for tools) | `—` | — |
| `S56-settings-toggles-focus-light-rt@8188b73.png` | light | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles; keyboard focus on row 0 (Show hover hints for tools) | `—` | — |
| `S56-settings-toggles-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles; row 0 (Show hover hints for tools) hovered | `—` | — |
| `S56-settings-toggles-hover-light-rt@8188b73.png` | light | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles; row 0 (Show hover hints for tools) hovered | `—` | — |
| `S56-settings-toggles-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles | `—` | — |
| `S56-settings-toggles-rest-light-rt@8188b73.png` | light | 1488×1179 | Settings: hover hints, keyboard tips, include app and capture flash toggles | `—` | — |
| `S57-resize-anchor-focus-dark-rt@8188b73.png` | dark | 1489×1179 | Crop mode: the anchor plate has keyboard focus (ring on the chosen cell) | `—` | — |
| `S57-resize-anchor-focus-light-rt@8188b73.png` | light | 1489×1179 | Crop mode: the anchor plate has keyboard focus (ring on the chosen cell) | `—` | — |
| `S57-resize-anchor-hover-dark-rt@8188b73.png` | dark | 1489×1179 | Crop mode: the Top Right cell hovered | `—` | — |
| `S57-resize-anchor-hover-light-rt@8188b73.png` | light | 1489×1179 | Crop mode: the Top Right cell hovered | `—` | — |
| `S57-resize-anchor-rest-dark-rt@8188b73.png` | dark | 1489×1179 | Crop mode: the 3 x 3 anchor plate, Center chosen | `—` | — |
| `S57-resize-anchor-rest-light-rt@8188b73.png` | light | 1489×1179 | Crop mode: the 3 x 3 anchor plate, Center chosen | `—` | — |
| `S57-resize-groups-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates; keyboard focus on row 0 (Resize) | `—` | — |
| `S57-resize-groups-focus-light-rt@8188b73.png` | light | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates; keyboard focus on row 0 (Resize) | `—` | — |
| `S57-resize-groups-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates; row 1 (Crop) hovered | `—` | — |
| `S57-resize-groups-hover-light-rt@8188b73.png` | light | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates; row 1 (Crop) hovered | `—` | — |
| `S57-resize-groups-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates | `—` | — |
| `S57-resize-groups-rest-light-rt@8188b73.png` | light | 1488×1179 | Resize sheet: the mode, lock proportions, preset and button choices on their plates | `—` | — |
| `S57-resize-preset-chosen-dark-rt@8188b73.png` | dark | 1489×1179 | Resize sheet: the preset panel with its chosen row | `—` | — |
| `S57-resize-preset-chosen-light-rt@8188b73.png` | light | 1489×1179 | Resize sheet: the preset panel with its chosen row | `—` | — |
| `S57-resize-preset-dismissed-dark-rt@8188b73.png` | dark | 1489×1179 | Preset choices dismissed with Escape: gone, focus back on the preset face | `—` | — |
| `S57-resize-preset-dismissed-light-rt@8188b73.png` | light | 1489×1179 | Preset choices dismissed with Escape: gone, focus back on the preset face | `—` | — |
| `S57-resize-preset-focus-dark-rt@8188b73.png` | dark | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets); keyboard focus on row 0 (Custom size) | `—` | — |
| `S57-resize-preset-focus-light-rt@8188b73.png` | light | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets); keyboard focus on row 0 (Custom size) | `—` | — |
| `S57-resize-preset-hover-dark-rt@8188b73.png` | dark | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets); row 1 (Ad: Rectangle (Large)) hovered | `—` | — |
| `S57-resize-preset-hover-light-rt@8188b73.png` | light | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets); row 1 (Ad: Rectangle (Large)) hovered | `—` | — |
| `S57-resize-preset-rest-dark-rt@8188b73.png` | dark | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets) | `—` | — |
| `S57-resize-preset-rest-light-rt@8188b73.png` | light | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets) | `—` | — |
| `S57-resize-preset-rest-only-dark-rt@8188b73.png` | dark | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets) (the panel window alone) | `—` | — |
| `S57-resize-preset-rest-only-light-rt@8188b73.png` | light | 1489×1179 | Resize sheet: the preset choices open (Custom size chosen, built-in and two saved presets) (the panel window alone) | `—` | — |
| `S58-destination-acl-off-dark-rt@8188b73.png` | dark | 1488×1179 | S3-compatible destination: Make uploads public-read off | `—` | — |
| `S58-destination-acl-off-light-rt@8188b73.png` | light | 1488×1179 | S3-compatible destination: Make uploads public-read off | `—` | — |
| `S58-destination-acl-on-dark-rt@8188b73.png` | dark | 1488×1179 | S3-compatible destination: Make uploads public-read on | `—` | — |
| `S58-destination-acl-on-light-rt@8188b73.png` | light | 1488×1179 | S3-compatible destination: Make uploads public-read on | `—` | — |
| `S58-destination-protocol-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S58-destination-protocol-dismissed-light-rt@8188b73.png` | light | 1488×1179 | choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S58-destination-protocol-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected; keyboard focus on row 0 (WebDAV) | `—` | — |
| `S58-destination-protocol-focus-light-rt@8188b73.png` | light | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected; keyboard focus on row 0 (WebDAV) | `—` | — |
| `S58-destination-protocol-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected; row 1 (FTP) hovered | `—` | — |
| `S58-destination-protocol-hover-light-rt@8188b73.png` | light | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected; row 1 (FTP) hovered | `—` | — |
| `S58-destination-protocol-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected | `—` | — |
| `S58-destination-protocol-rest-light-rt@8188b73.png` | light | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected | `—` | — |
| `S58-destination-protocol-rest-only-dark-rt@8188b73.png` | dark | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected (the panel window alone) | `—` | — |
| `S58-destination-protocol-rest-only-light-rt@8188b73.png` | light | 1488×1179 | Protocol choices open on the destination sheet, S3-compatible selected (the panel window alone) | `—` | — |
| `S58-destination-source-dismissed-dark-rt@8188b73.png` | dark | 1488×1179 | choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S58-destination-source-dismissed-light-rt@8188b73.png` | light | 1488×1179 | choices dismissed with Escape: gone, focus back on the face | `—` | — |
| `S58-destination-source-focus-dark-rt@8188b73.png` | dark | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected; keyboard focus on row 0 (AWS credentials profile) | `—` | — |
| `S58-destination-source-focus-light-rt@8188b73.png` | light | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected; keyboard focus on row 0 (AWS credentials profile) | `—` | — |
| `S58-destination-source-hover-dark-rt@8188b73.png` | dark | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected; row 1 (Access key stored in Keychain) hovered | `—` | — |
| `S58-destination-source-hover-light-rt@8188b73.png` | light | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected; row 1 (Access key stored in Keychain) hovered | `—` | — |
| `S58-destination-source-rest-dark-rt@8188b73.png` | dark | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected | `—` | — |
| `S58-destination-source-rest-light-rt@8188b73.png` | light | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected | `—` | — |
| `S58-destination-source-rest-only-dark-rt@8188b73.png` | dark | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected (the panel window alone) | `—` | — |
| `S58-destination-source-rest-only-light-rt@8188b73.png` | light | 1488×1179 | Key source choices open on the destination sheet, S3-compatible selected (the panel window alone) | `—` | — |
| `S58-destination-width-560-dark-rt@8188b73.png` | dark | 1488×1179 | S3-compatible with the Keychain key source, sheet 560 pt wide | `—` | — |
| `S58-destination-width-560-light-rt@8188b73.png` | light | 1488×1179 | S3-compatible with the Keychain key source, sheet 560 pt wide | `—` | — |
| `S58-destination-width-640-dark-rt@8188b73.png` | dark | 1488×1179 | S3-compatible with the Keychain key source, sheet 640 pt wide | `—` | — |
| `S58-destination-width-640-light-rt@8188b73.png` | light | 1488×1179 | S3-compatible with the Keychain key source, sheet 640 pt wide | `—` | — |
| `S59-footer-original-hidden-dark-rt@8188b73.png` | dark | 980×640 | large shot at 980 during an upload: the status slot reflows and the Original size toggle steps aside | `layout/S59-footer-original-hidden-dark-rt@8188b73.json` | — |
| `S59-footer-original-hidden-light-rt@8188b73.png` | light | 980×640 | large shot at 980 during an upload: the status slot reflows and the Original size toggle steps aside | `layout/S59-footer-original-hidden-light-rt@8188b73.json` | — |
| `S59-footer-original-off-dark-rt@8188b73.png` | dark | 1280×800 | large shot at 1280: the Original size toggle off | `layout/S59-footer-original-off-dark-rt@8188b73.json` | — |
| `S59-footer-original-off-light-rt@8188b73.png` | light | 1280×800 | large shot at 1280: the Original size toggle off | `layout/S59-footer-original-off-light-rt@8188b73.json` | — |
| `S59-footer-original-on-dark-rt@8188b73.png` | dark | 1280×800 | large shot at 1280: the Original size toggle on | `layout/S59-footer-original-on-dark-rt@8188b73.json` | — |
| `S59-footer-original-on-light-rt@8188b73.png` | light | 1280×800 | large shot at 1280: the Original size toggle on | `layout/S59-footer-original-on-light-rt@8188b73.json` | — |
| `S60-capture-clear-all-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: the Clear All action plate | `—` | — |
| `S60-capture-clear-all-light-rt@8188b73.png` | light | 980×640 | Capture tab: the Clear All action plate | `—` | — |
| `S60-capture-enable-off-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: Enable global capture shortcuts off | `—` | — |
| `S60-capture-enable-off-light-rt@8188b73.png` | light | 980×640 | Capture tab: Enable global capture shortcuts off | `—` | — |
| `S60-capture-enable-on-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: Enable global capture shortcuts on | `—` | — |
| `S60-capture-enable-on-light-rt@8188b73.png` | light | 980×640 | Capture tab: Enable global capture shortcuts on | `—` | — |
| `S60-capture-key-chosen-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: the key panel with K chosen | `—` | — |
| `S60-capture-key-chosen-light-rt@8188b73.png` | light | 980×640 | Capture tab: the key panel with K chosen | `—` | — |
| `S60-capture-key-dismissed-dark-rt@8188b73.png` | dark | 980×640 | Key choices dismissed with Escape: gone, focus back on the key face | `—` | — |
| `S60-capture-key-dismissed-light-rt@8188b73.png` | light | 980×640 | Key choices dismissed with Escape: gone, focus back on the key face | `—` | — |
| `S60-capture-key-focus-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: the key choices open for Screen region, K chosen; keyboard focus on row 0 (None) | `—` | — |
| `S60-capture-key-focus-light-rt@8188b73.png` | light | 980×640 | Capture tab: the key choices open for Screen region, K chosen; keyboard focus on row 0 (None) | `—` | — |
| `S60-capture-key-hover-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: the key choices open for Screen region, K chosen; row 1 (A) hovered | `—` | — |
| `S60-capture-key-hover-light-rt@8188b73.png` | light | 980×640 | Capture tab: the key choices open for Screen region, K chosen; row 1 (A) hovered | `—` | — |
| `S60-capture-key-rest-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: the key choices open for Screen region, K chosen | `—` | — |
| `S60-capture-key-rest-light-rt@8188b73.png` | light | 980×640 | Capture tab: the key choices open for Screen region, K chosen | `—` | — |
| `S60-capture-key-rest-only-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: the key choices open for Screen region, K chosen (the panel window alone) | `—` | — |
| `S60-capture-key-rest-only-light-rt@8188b73.png` | light | 980×640 | Capture tab: the key choices open for Screen region, K chosen (the panel window alone) | `—` | — |
| `S60-capture-key-scroll-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: the long key list scrolled to its last row inside the height cap | `—` | — |
| `S60-capture-key-scroll-light-rt@8188b73.png` | light | 980×640 | Capture tab: the long key list scrolled to its last row inside the height cap | `—` | — |
| `S60-capture-modifiers-chosen-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: K with Option and Control chosen on the Screen region row | `—` | — |
| `S60-capture-modifiers-chosen-light-rt@8188b73.png` | light | 980×640 | Capture tab: K with Option and Control chosen on the Screen region row | `—` | — |
| `S60-capture-modifiers-disabled-dark-rt@8188b73.png` | dark | 980×640 | Capture tab: no key set for Screen region, so its four modifier toggles are disabled | `—` | — |
| `S60-capture-modifiers-disabled-light-rt@8188b73.png` | light | 980×640 | Capture tab: no key set for Screen region, so its four modifier toggles are disabled | `—` | — |

