# OSN-071 visual acceptance run (round 4): increase-contrast-surfaces

Source `8188b73`; icon mode **sf** (FA unavailable); 264 captures, every PNG scaled to at most 1200 px wide.
Pre-change twins are referenced from `docs/design/evidence/impl-2026-10-09/root-final-core` at `1ea366c`; they are not copied.

| Capture | Appearance | Window pt | What it shows | Layout JSON | BEFORE (pre-change) |
|---|---|---|---|---|---|
| `S12-frame-mode-dark-ic@8188b73.png` | dark | 1488×1179 | Frame mode: clear canvas hole, Snap Frame + Cancel, window alpha 0.8 | `layout/S12-frame-mode-dark-ic@8188b73.json` | — |
| `S12-frame-mode-light-ic@8188b73.png` | light | 1488×1179 | Frame mode: clear canvas hole, Snap Frame + Cancel, window alpha 0.8 | `layout/S12-frame-mode-light-ic@8188b73.json` | — |
| `S12-frame-resnap-dark-ic@8188b73.png` | dark | 1488×1179 | Re-snap (keep pen) Frame mode over existing annotations | `layout/S12-frame-resnap-dark-ic@8188b73.json` | — |
| `S12-frame-resnap-light-ic@8188b73.png` | light | 1488×1179 | Re-snap (keep pen) Frame mode over existing annotations | `layout/S12-frame-resnap-light-ic@8188b73.json` | — |
| `S12-frame-w1024-dark-ic@8188b73.png` | dark | 1024×1179 | Frame mode at window width 1024 pt | `layout/S12-frame-w1024-dark-ic@8188b73.json` | — |
| `S12-frame-w1024-light-ic@8188b73.png` | light | 1024×1179 | Frame mode at window width 1024 pt | `layout/S12-frame-w1024-light-ic@8188b73.json` | — |
| `S12-frame-w1280-dark-ic@8188b73.png` | dark | 1280×1179 | Frame mode at window width 1280 pt | `layout/S12-frame-w1280-dark-ic@8188b73.json` | — |
| `S12-frame-w1280-light-ic@8188b73.png` | light | 1280×1179 | Frame mode at window width 1280 pt | `layout/S12-frame-w1280-light-ic@8188b73.json` | — |
| `S12-frame-w980-dark-ic@8188b73.png` | dark | 980×1179 | Frame mode at window width 980 pt | `layout/S12-frame-w980-dark-ic@8188b73.json` | — |
| `S12-frame-w980-light-ic@8188b73.png` | light | 980×1179 | Frame mode at window width 980 pt | `layout/S12-frame-w980-light-ic@8188b73.json` | — |
| `S13-picker-no-recording-grant-dark-ic@8188b73.png` | dark | 1488×1179 | crosshair overlay with magnifier (lens hatched placeholder reading Screen Recording off, as without a grant), no drag yet | `—` | — |
| `S13-picker-no-recording-grant-light-ic@8188b73.png` | light | 1488×1179 | crosshair overlay with magnifier (lens hatched placeholder reading Screen Recording off, as without a grant), no drag yet | `—` | — |
| `S13-picker-no-recording-grant-dragging-dark-ic@8188b73.png` | dark | 1488×1179 | mid-drag selection rectangle with dimmed surround and the size read-out (lens placeholder) | `—` | — |
| `S13-picker-no-recording-grant-dragging-light-ic@8188b73.png` | light | 1488×1179 | mid-drag selection rectangle with dimmed surround and the size read-out (lens placeholder) | `—` | — |
| `S13-picker-no-recording-grant-edge-bottom-right-dark-ic@8188b73.png` | dark | 1488×1179 | magnifier with the pointer at the bottom-right corner of the display (placeholder lens): lens and size label both stay on screen, the label 4 pt below the lens border | `—` | — |
| `S13-picker-no-recording-grant-edge-bottom-right-light-ic@8188b73.png` | light | 1488×1179 | magnifier with the pointer at the bottom-right corner of the display (placeholder lens): lens and size label both stay on screen, the label 4 pt below the lens border | `—` | — |
| `S13-picker-no-recording-grant-edge-top-left-dark-ic@8188b73.png` | dark | 1488×1179 | magnifier with the pointer at the top-left corner of the display (placeholder lens): lens and size label both stay on screen, the label 4 pt below the lens border | `—` | — |
| `S13-picker-no-recording-grant-edge-top-left-light-ic@8188b73.png` | light | 1488×1179 | magnifier with the pointer at the top-left corner of the display (placeholder lens): lens and size label both stay on screen, the label 4 pt below the lens border | `—` | — |
| `S13-picker-synthetic-lens-dark-ic@8188b73.png` | dark | 1488×1179 | crosshair overlay with magnifier (lens fed synthetic pixels), no drag yet | `—` | — |
| `S13-picker-synthetic-lens-light-ic@8188b73.png` | light | 1488×1179 | crosshair overlay with magnifier (lens fed synthetic pixels), no drag yet | `—` | — |
| `S13-picker-synthetic-lens-dragging-dark-ic@8188b73.png` | dark | 1488×1179 | mid-drag selection rectangle with dimmed surround and the size read-out (lens synthetic) | `—` | — |
| `S13-picker-synthetic-lens-dragging-light-ic@8188b73.png` | light | 1488×1179 | mid-drag selection rectangle with dimmed surround and the size read-out (lens synthetic) | `—` | — |
| `S14-countdown-1-dark-ic@8188b73.png` | dark | 1488×1179 | countdown digit 1 (tick 42) | `—` | — |
| `S14-countdown-1-light-ic@8188b73.png` | light | 1488×1179 | countdown digit 1 (tick 42) | `—` | — |
| `S14-countdown-2-dark-ic@8188b73.png` | dark | 1488×1179 | countdown digit 2 (tick 22) | `—` | — |
| `S14-countdown-2-light-ic@8188b73.png` | light | 1488×1179 | countdown digit 2 (tick 22) | `—` | — |
| `S14-countdown-3-dark-ic@8188b73.png` | dark | 1488×1179 | countdown digit 3 (tick 2) | `—` | — |
| `S14-countdown-3-light-ic@8188b73.png` | light | 1488×1179 | countdown digit 3 (tick 2) | `—` | — |
| `S14-countdown-3-contrast-reduce-motion-dark-ic@8188b73.png` | dark | 1488×1179 | digit 3 with Increase Contrast (plate 0.8) and Reduce Motion (alpha 1 on the first frame) | `—` | — |
| `S14-countdown-3-contrast-reduce-motion-light-ic@8188b73.png` | light | 1488×1179 | digit 3 with Increase Contrast (plate 0.8) and Reduce Motion (alpha 1 on the first frame) | `—` | — |
| `S15-flash-half-dark-ic@8188b73.png` | dark | 1488×1179 | flash halfway up the ramp (0.35) in front of the editor | `—` | — |
| `S15-flash-half-light-ic@8188b73.png` | light | 1488×1179 | flash halfway up the ramp (0.35) in front of the editor | `—` | — |
| `S15-flash-peak-dark-ic@8188b73.png` | dark | 1488×1179 | flash panel at its peak alpha (0.7) in front of the editor, editor behind it | `—` | — |
| `S15-flash-peak-light-ic@8188b73.png` | light | 1488×1179 | flash panel at its peak alpha (0.7) in front of the editor, editor behind it | `—` | — |
| `S16-permission-sheet-dark-ic@8188b73.png` | dark | 1488×1179 | app-owned sheet: title, instructions, Open System Settings (default) and Cancel | `—` | — |
| `S16-permission-sheet-light-ic@8188b73.png` | light | 1488×1179 | app-owned sheet: title, instructions, Open System Settings (default) and Cancel | `—` | — |
| `S16-permission-sheet-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | the sheet over the dimmed editor (sheet + parent composite, sheet in front) | `—` | — |
| `S16-permission-sheet-in-context-light-ic@8188b73.png` | light | 1488×1179 | the sheet over the dimmed editor (sheet + parent composite, sheet in front) | `—` | — |
| `S17-settings-capture-dark-ic@8188b73.png` | dark | 1488×1179 | Capture tab: flash on, shortcuts enabled, every action None | `—` | — |
| `S17-settings-capture-light-ic@8188b73.png` | light | 1488×1179 | Capture tab: flash on, shortcuts enabled, every action None | `—` | — |
| `S17-settings-capture-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | Capture tab: flash on, shortcuts enabled, every action None, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-1280x800-light-ic@8188b73.png` | light | 1488×1179 | Capture tab: flash on, shortcuts enabled, every action None, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-error-dark-ic@8188b73.png` | dark | 1488×1179 | Capture tab with a refused shortcut (a key with no Command or Control) | `—` | — |
| `S17-settings-capture-error-light-ic@8188b73.png` | light | 1488×1179 | Capture tab with a refused shortcut (a key with no Command or Control) | `—` | — |
| `S17-settings-capture-error-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | Capture tab with a refused shortcut (a key with no Command or Control), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-error-1280x800-light-ic@8188b73.png` | light | 1488×1179 | Capture tab with a refused shortcut (a key with no Command or Control), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-modifiers-dark-ic@8188b73.png` | dark | 1488×1179 | Capture tab with Option-Control-K chosen for Screen region: the chosen modifier toggles are in the accent | `—` | — |
| `S17-settings-capture-modifiers-light-ic@8188b73.png` | light | 1488×1179 | Capture tab with Option-Control-K chosen for Screen region: the chosen modifier toggles are in the accent | `—` | — |
| `S17-settings-capture-modifiers-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | Capture tab with Option-Control-K chosen for Screen region: the chosen modifier toggles are in the accent, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-capture-modifiers-1280x800-light-ic@8188b73.png` | light | 1488×1179 | Capture tab with Option-Control-K chosen for Screen region: the chosen modifier toggles are in the accent, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-drawing-dark-ic@8188b73.png` | dark | 1488×1179 | Drawing tab, default values | `—` | — |
| `S17-settings-drawing-light-ic@8188b73.png` | light | 1488×1179 | Drawing tab, default values | `—` | — |
| `S17-settings-drawing-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | Drawing tab, default values, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-drawing-1280x800-light-ic@8188b73.png` | light | 1488×1179 | Drawing tab, default values, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-drawing-alt-dark-ic@8188b73.png` | dark | 1488×1179 | Drawing tab, alternate values (Loose, Start) | `—` | — |
| `S17-settings-drawing-alt-light-ic@8188b73.png` | light | 1488×1179 | Drawing tab, alternate values (Loose, Start) | `—` | — |
| `S17-settings-drawing-alt-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | Drawing tab, alternate values (Loose, Start), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-drawing-alt-1280x800-light-ic@8188b73.png` | light | 1488×1179 | Drawing tab, alternate values (Loose, Start), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-general-dark-ic@8188b73.png` | dark | 1488×1179 | General tab, default values | `—` | — |
| `S17-settings-general-light-ic@8188b73.png` | light | 1488×1179 | General tab, default values | `—` | — |
| `S17-settings-general-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | General tab, default values, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-general-1280x800-light-ic@8188b73.png` | light | 1488×1179 | General tab, default values, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-general-alt-dark-ic@8188b73.png` | dark | 1488×1179 | General tab, alternate values (Menu bar, snap window off, both hint options on) | `—` | — |
| `S17-settings-general-alt-light-ic@8188b73.png` | light | 1488×1179 | General tab, alternate values (Menu bar, snap window off, both hint options on) | `—` | — |
| `S17-settings-general-alt-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | General tab, alternate values (Menu bar, snap window off, both hint options on), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-general-alt-1280x800-light-ic@8188b73.png` | light | 1488×1179 | General tab, alternate values (Menu bar, snap window off, both hint options on), sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-dark-ic@8188b73.png` | dark | 1488×1179 | Upload tab: three saved destinations, the first is the default | `—` | — |
| `S17-settings-upload-light-ic@8188b73.png` | light | 1488×1179 | Upload tab: three saved destinations, the first is the default | `—` | — |
| `S17-settings-upload-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | Upload tab: three saved destinations, the first is the default, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-1280x800-light-ic@8188b73.png` | light | 1488×1179 | Upload tab: three saved destinations, the first is the default, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-empty-dark-ic@8188b73.png` | dark | 1488×1179 | Upload tab, no destination saved | `—` | — |
| `S17-settings-upload-empty-light-ic@8188b73.png` | light | 1488×1179 | Upload tab, no destination saved | `—` | — |
| `S17-settings-upload-empty-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | Upload tab, no destination saved, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-empty-1280x800-light-ic@8188b73.png` | light | 1488×1179 | Upload tab, no destination saved, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-many-dark-ic@8188b73.png` | dark | 1488×1179 | Upload tab, eight saved destinations, all listed: the list is as tall as the screen allows and scrolls past that; Add…, Edit…, Remove, Make Default and the caption in view | `—` | — |
| `S17-settings-upload-many-light-ic@8188b73.png` | light | 1488×1179 | Upload tab, eight saved destinations, all listed: the list is as tall as the screen allows and scrolls past that; Add…, Edit…, Remove, Make Default and the caption in view | `—` | — |
| `S17-settings-upload-many-1280x800-dark-ic@8188b73.png` | dark | 1488×1179 | Upload tab, eight saved destinations, all listed: the list is as tall as the screen allows and scrolls past that; Add…, Edit…, Remove, Make Default and the caption in view, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-many-1280x800-light-ic@8188b73.png` | light | 1488×1179 | Upload tab, eight saved destinations, all listed: the list is as tall as the screen allows and scrolls past that; Add…, Edit…, Remove, Make Default and the caption in view, sized for a 1280 x 800 screen (706 pt visible) | `—` | — |
| `S17-settings-upload-many-440-dark-ic@8188b73.png` | dark | 1488×1179 | Upload tab, eight destinations on a very short 440 pt visible height: the list scrolls inside, the caption stays in view | `—` | — |
| `S17-settings-upload-many-440-light-ic@8188b73.png` | light | 1488×1179 | Upload tab, eight destinations on a very short 440 pt visible height: the list scrolls inside, the caption stays in view | `—` | — |
| `S17-settings-upload-many-640-dark-ic@8188b73.png` | dark | 1488×1179 | Upload tab, eight destinations on a 640 pt tall screen (616 pt visible): same window, list capped | `—` | — |
| `S17-settings-upload-many-640-light-ic@8188b73.png` | light | 1488×1179 | Upload tab, eight destinations on a 640 pt tall screen (616 pt visible): same window, list capped | `—` | — |
| `S18-hotkeys-via-app-menu-dark-ic@8188b73.png` | dark | 1488×1179 | Capture Shortcuts… from the app menu: Settings opens on the Capture tab (all actions None) | `—` | — |
| `S18-hotkeys-via-app-menu-light-ic@8188b73.png` | light | 1488×1179 | Capture Shortcuts… from the app menu: Settings opens on the Capture tab (all actions None) | `—` | — |
| `S19-destinations-edit-form-dark-ic@8188b73.png` | dark | 1488×1179 | edit form for the selected destination, a sheet on the Settings window | `—` | — |
| `S19-destinations-edit-form-light-ic@8188b73.png` | light | 1488×1179 | edit form for the selected destination, a sheet on the Settings window | `—` | — |
| `S19-destinations-edit-form-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | edit form for the selected destination, a sheet on the Settings window (parent window + sheet composite) | `—` | — |
| `S19-destinations-edit-form-in-context-light-ic@8188b73.png` | light | 1488×1179 | edit form for the selected destination, a sheet on the Settings window (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-focus-dark-ic@8188b73.png` | dark | 1488×1179 | first visible text field focused in the destination edit form | `—` | — |
| `S19-destinations-form-focus-light-ic@8188b73.png` | light | 1488×1179 | first visible text field focused in the destination edit form | `—` | — |
| `S19-destinations-form-focus-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | first visible text field focused in the destination edit form (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-focus-in-context-light-ic@8188b73.png` | light | 1488×1179 | first visible text field focused in the destination edit form (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-ftp-dark-ic@8188b73.png` | dark | 1488×1179 | new FTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-ftp-light-ic@8188b73.png` | light | 1488×1179 | new FTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-ftp-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | new FTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-ftp-in-context-light-ic@8188b73.png` | light | 1488×1179 | new FTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-ftps-dark-ic@8188b73.png` | dark | 1488×1179 | new FTPS destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-ftps-light-ic@8188b73.png` | light | 1488×1179 | new FTPS destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-ftps-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | new FTPS destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-ftps-in-context-light-ic@8188b73.png` | light | 1488×1179 | new FTPS destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-s3-dark-ic@8188b73.png` | dark | 1488×1179 | new S3-compatible destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-s3-light-ic@8188b73.png` | light | 1488×1179 | new S3-compatible destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-s3-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | new S3-compatible destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-s3-in-context-light-ic@8188b73.png` | light | 1488×1179 | new S3-compatible destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-sftp-dark-ic@8188b73.png` | dark | 1488×1179 | new SFTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-sftp-light-ic@8188b73.png` | light | 1488×1179 | new SFTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-sftp-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | new SFTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-sftp-in-context-light-ic@8188b73.png` | light | 1488×1179 | new SFTP destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-webdav-dark-ic@8188b73.png` | dark | 1488×1179 | new WebDAV destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-webdav-light-ic@8188b73.png` | light | 1488×1179 | new WebDAV destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band | `—` | — |
| `S19-destinations-form-webdav-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | new WebDAV destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-form-webdav-in-context-light-ic@8188b73.png` | light | 1488×1179 | new WebDAV destination: its own endpoint scheme, placeholders and help, and the Test note in the one-line result band (parent window + sheet composite) | `—` | — |
| `S19-destinations-from-settings-640-dark-ic@8188b73.png` | dark | 1488×1179 | the editor as hosted by the 640 pt Settings window: 640 wide, so it never overhangs its parent | `—` | — |
| `S19-destinations-from-settings-640-light-ic@8188b73.png` | light | 1488×1179 | the editor as hosted by the 640 pt Settings window: 640 wide, so it never overhangs its parent | `—` | — |
| `S19-destinations-from-settings-640-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | the editor as hosted by the 640 pt Settings window: 640 wide, so it never overhangs its parent (parent window + sheet composite) | `—` | — |
| `S19-destinations-from-settings-640-in-context-light-ic@8188b73.png` | light | 1488×1179 | the editor as hosted by the 640 pt Settings window: 640 wide, so it never overhangs its parent (parent window + sheet composite) | `—` | — |
| `S19-destinations-short-screen-dark-ic@8188b73.png` | dark | 1488×1179 | edit form on a short display (visible frame 1280 x 500): the form scrolls and Test, Cancel and Save stay pinned | `—` | — |
| `S19-destinations-short-screen-light-ic@8188b73.png` | light | 1488×1179 | edit form on a short display (visible frame 1280 x 500): the form scrolls and Test, Cancel and Save stay pinned | `—` | — |
| `S19-destinations-short-screen-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | edit form on a short display (visible frame 1280 x 500): the form scrolls and Test, Cancel and Save stay pinned (parent window + sheet composite) | `—` | — |
| `S19-destinations-short-screen-in-context-light-ic@8188b73.png` | light | 1488×1179 | edit form on a short display (visible frame 1280 x 500): the form scrolls and Test, Cancel and Save stay pinned (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-connected-dark-ic@8188b73.png` | dark | 1488×1179 | S3 form after a synthetic successful Test: check glyph, Connected, detail line | `—` | — |
| `S19-destinations-test-connected-light-ic@8188b73.png` | light | 1488×1179 | S3 form after a synthetic successful Test: check glyph, Connected, detail line | `—` | — |
| `S19-destinations-test-connected-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | S3 form after a synthetic successful Test: check glyph, Connected, detail line (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-connected-in-context-light-ic@8188b73.png` | light | 1488×1179 | S3 form after a synthetic successful Test: check glyph, Connected, detail line (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-error-dark-ic@8188b73.png` | dark | 1488×1179 | S3 form after a synthetic failed Test: octagon glyph and an Error: line | `—` | — |
| `S19-destinations-test-error-light-ic@8188b73.png` | light | 1488×1179 | S3 form after a synthetic failed Test: octagon glyph and an Error: line | `—` | — |
| `S19-destinations-test-error-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | S3 form after a synthetic failed Test: octagon glyph and an Error: line (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-error-in-context-light-ic@8188b73.png` | light | 1488×1179 | S3 form after a synthetic failed Test: octagon glyph and an Error: line (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-error-webdav-dark-ic@8188b73.png` | dark | 1488×1179 | WebDAV form after a synthetic failed Test (HTTP 401): the band grows to its lines and the form above it shrinks to make room | `—` | — |
| `S19-destinations-test-error-webdav-light-ic@8188b73.png` | light | 1488×1179 | WebDAV form after a synthetic failed Test (HTTP 401): the band grows to its lines and the form above it shrinks to make room | `—` | — |
| `S19-destinations-test-error-webdav-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | WebDAV form after a synthetic failed Test (HTTP 401): the band grows to its lines and the form above it shrinks to make room (parent window + sheet composite) | `—` | — |
| `S19-destinations-test-error-webdav-in-context-light-ic@8188b73.png` | light | 1488×1179 | WebDAV form after a synthetic failed Test (HTTP 401): the band grows to its lines and the form above it shrinks to make room (parent window + sheet composite) | `—` | — |
| `S19-settings-upload-empty-dark-ic@8188b73.png` | dark | 1488×1179 | Settings, Upload tab, no destination saved: No destinations yet and Add… inside the list | `—` | — |
| `S19-settings-upload-empty-light-ic@8188b73.png` | light | 1488×1179 | Settings, Upload tab, no destination saved: No destinations yet and Add… inside the list | `—` | — |
| `S19-settings-upload-list-dark-ic@8188b73.png` | dark | 1488×1179 | Settings, Upload tab: three synthetic destinations (Example S3 default, SFTP, WebDAV) with Add…, Edit…, Remove and Make Default | `—` | — |
| `S19-settings-upload-list-light-ic@8188b73.png` | light | 1488×1179 | Settings, Upload tab: three synthetic destinations (Example S3 default, SFTP, WebDAV) with Add…, Edit…, Remove and Make Default | `—` | — |
| `S20-history-1120x850-selected-dark-ic@8188b73.png` | dark | 1488×1179 | six synthetic entries, one selected, window 1120 x 850: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-1120x850-selected-light-ic@8188b73.png` | light | 1488×1179 | six synthetic entries, one selected, window 1120 x 850: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-1280x800-selected-dark-ic@8188b73.png` | dark | 1488×1179 | six synthetic entries, one selected, window 1280 x 800: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-1280x800-selected-light-ic@8188b73.png` | light | 1488×1179 | six synthetic entries, one selected, window 1280 x 800: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-880x600-none-dark-ic@8188b73.png` | dark | 1488×1179 | 880 x 600, nothing selected: the details column shows the summary instead of a blank hint; tiles sized to their preview | `—` | — |
| `S20-history-880x600-none-light-ic@8188b73.png` | light | 1488×1179 | 880 x 600, nothing selected: the details column shows the summary instead of a blank hint; tiles sized to their preview | `—` | — |
| `S20-history-880x600-selected-dark-ic@8188b73.png` | dark | 1488×1179 | six synthetic entries, one selected, window 880 x 600: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-880x600-selected-light-ic@8188b73.png` | light | 1488×1179 | six synthetic entries, one selected, window 880 x 600: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-action-focus-dark-ic@8188b73.png` | dark | 1488×1179 | keyboard focus on the Open action: the focus ring around its rounded fill (made first responder directly; real Tab reaches it only with Full Keyboard Access or Window > Focus Toolbar) | `—` | — |
| `S20-history-action-focus-light-ic@8188b73.png` | light | 1488×1179 | keyboard focus on the Open action: the focus ring around its rounded fill (made first responder directly; real Tab reaches it only with Full Keyboard Access or Window > Focus Toolbar) | `—` | — |
| `S20-history-action-hover-dark-ic@8188b73.png` | dark | 1488×1179 | one entry selected and the Copy action hovered: its own label 0.08 fill on the glass plate, the other actions at rest | `—` | — |
| `S20-history-action-hover-light-ic@8188b73.png` | light | 1488×1179 | one entry selected and the Copy action hovered: its own label 0.08 fill on the glass plate, the other actions at rest | `—` | — |
| `S20-history-action-pressed-dark-ic@8188b73.png` | dark | 1488×1179 | one entry selected and the Copy action held down (press bracket driven directly, not a real click): the pressed fill and glyph scale on its plate | `—` | — |
| `S20-history-action-pressed-light-ic@8188b73.png` | light | 1488×1179 | one entry selected and the Copy action held down (press bracket driven directly, not a real click): the pressed fill and glyph scale on its plate | `—` | — |
| `S20-history-empty-dark-ic@8188b73.png` | dark | 1488×1179 | History window with no entries | `—` | — |
| `S20-history-empty-light-ic@8188b73.png` | light | 1488×1179 | History window with no entries | `—` | — |
| `S20-history-link-copied-dark-ic@8188b73.png` | dark | 1488×1179 | a Shared entry selected after Copy Link: the footer confirms, and the destination link is cut in its middle with the full text in its tooltip | `—` | — |
| `S20-history-link-copied-light-ic@8188b73.png` | light | 1488×1179 | a Shared entry selected after Copy Link: the footer confirms, and the destination link is cut in its middle with the full text in its tooltip | `—` | — |
| `S20-history-no-match-dark-ic@8188b73.png` | dark | 1488×1179 | filters that match nothing at 880 x 600: centred message, no save hint | `—` | — |
| `S20-history-no-match-light-ic@8188b73.png` | light | 1488×1179 | filters that match nothing at 880 x 600: centred message, no save hint | `—` | — |
| `S20-history-no-match-footer-dark-ic@8188b73.png` | dark | 1488×1179 | filters that match nothing: the footer stays (0 of 6 items) and Clear filters offers the way out | `—` | — |
| `S20-history-no-match-footer-light-ic@8188b73.png` | light | 1488×1179 | filters that match nothing: the footer stays (0 of 6 items) and Clear filters offers the way out | `—` | — |
| `S20-history-populated-dark-ic@8188b73.png` | dark | 1488×1179 | six synthetic entries across dates and actions (Saved/Exported/Shared) | `—` | — |
| `S20-history-populated-light-ic@8188b73.png` | light | 1488×1179 | six synthetic entries across dates and actions (Saved/Exported/Shared) | `—` | — |
| `S20-history-selected-dark-ic@8188b73.png` | dark | 1488×1179 | one entry selected (action buttons enabled) | `—` | — |
| `S20-history-selected-light-ic@8188b73.png` | light | 1488×1179 | one entry selected (action buttons enabled) | `—` | — |
| `S20-history-tile-hover-dark-ic@8188b73.png` | dark | 1488×1179 | one entry selected (accent fill, border, check badge) and another tile hovered (label 0.08 fill) | `—` | — |
| `S20-history-tile-hover-light-ic@8188b73.png` | light | 1488×1179 | one entry selected (accent fill, border, check badge) and another tile hovered (label 0.08 fill) | `—` | — |
| `S21-publish-cancelled-w1280-dark-ic@8188b73.png` | dark | 1280×800 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w1280 | `layout/S21-publish-cancelled-w1280-dark-ic@8188b73.json` | — |
| `S21-publish-cancelled-w1280-light-ic@8188b73.png` | light | 1280×800 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w1280 | `layout/S21-publish-cancelled-w1280-light-ic@8188b73.json` | — |
| `S21-publish-cancelled-w1440-dark-ic@8188b73.png` | dark | 1440×900 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w1440 | `layout/S21-publish-cancelled-w1440-dark-ic@8188b73.json` | — |
| `S21-publish-cancelled-w1440-light-ic@8188b73.png` | light | 1440×900 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w1440 | `layout/S21-publish-cancelled-w1440-light-ic@8188b73.json` | — |
| `S21-publish-cancelled-w980-dark-ic@8188b73.png` | dark | 980×640 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w980 | `layout/S21-publish-cancelled-w980-dark-ic@8188b73.json` | — |
| `S21-publish-cancelled-w980-light-ic@8188b73.png` | light | 980×640 | Upload cancelled in the status line after Cancel, kept for ten seconds, at w980 | `layout/S21-publish-cancelled-w980-light-ic@8188b73.json` | — |
| `S21-publish-error-details-w1280-dark-ic@8188b73.png` | dark | 1280×800 | the Details… sheet with the whole error (no second Error: under the title), at w1280 | `—` | — |
| `S21-publish-error-details-w1280-light-ic@8188b73.png` | light | 1280×800 | the Details… sheet with the whole error (no second Error: under the title), at w1280 | `—` | — |
| `S21-publish-error-details-w1440-dark-ic@8188b73.png` | dark | 1440×900 | the Details… sheet with the whole error (no second Error: under the title), at w1440 | `—` | — |
| `S21-publish-error-details-w1440-light-ic@8188b73.png` | light | 1440×900 | the Details… sheet with the whole error (no second Error: under the title), at w1440 | `—` | — |
| `S21-publish-error-details-w980-dark-ic@8188b73.png` | dark | 980×640 | the Details… sheet with the whole error (no second Error: under the title), at w980 | `—` | — |
| `S21-publish-error-details-w980-light-ic@8188b73.png` | light | 980×640 | the Details… sheet with the whole error (no second Error: under the title), at w980 | `—` | — |
| `S21-publish-error-footer-w1280-dark-ic@8188b73.png` | dark | 1280×800 | footer crop with the inline error, Retry and Details, at w1280 | `layout/S21-publish-error-footer-w1280-dark-ic@8188b73.json` | — |
| `S21-publish-error-footer-w1280-light-ic@8188b73.png` | light | 1280×800 | footer crop with the inline error, Retry and Details, at w1280 | `layout/S21-publish-error-footer-w1280-light-ic@8188b73.json` | — |
| `S21-publish-error-footer-w1440-dark-ic@8188b73.png` | dark | 1440×900 | footer crop with the inline error, Retry and Details, at w1440 | `layout/S21-publish-error-footer-w1440-dark-ic@8188b73.json` | — |
| `S21-publish-error-footer-w1440-light-ic@8188b73.png` | light | 1440×900 | footer crop with the inline error, Retry and Details, at w1440 | `layout/S21-publish-error-footer-w1440-light-ic@8188b73.json` | — |
| `S21-publish-error-footer-w980-dark-ic@8188b73.png` | dark | 980×640 | footer crop with the inline error, Retry and Details, at w980 | `layout/S21-publish-error-footer-w980-dark-ic@8188b73.json` | — |
| `S21-publish-error-footer-w980-light-ic@8188b73.png` | light | 980×640 | footer crop with the inline error, Retry and Details, at w980 | `layout/S21-publish-error-footer-w980-light-ic@8188b73.json` | — |
| `S21-publish-error-w1280-dark-ic@8188b73.png` | dark | 1280×800 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w1280 | `layout/S21-publish-error-w1280-dark-ic@8188b73.json` | — |
| `S21-publish-error-w1280-light-ic@8188b73.png` | light | 1280×800 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w1280 | `layout/S21-publish-error-w1280-light-ic@8188b73.json` | — |
| `S21-publish-error-w1440-dark-ic@8188b73.png` | dark | 1440×900 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w1440 | `layout/S21-publish-error-w1440-dark-ic@8188b73.json` | — |
| `S21-publish-error-w1440-light-ic@8188b73.png` | light | 1440×900 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w1440 | `layout/S21-publish-error-w1440-light-ic@8188b73.json` | — |
| `S21-publish-error-w980-dark-ic@8188b73.png` | dark | 980×640 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w980 | `layout/S21-publish-error-w980-dark-ic@8188b73.json` | — |
| `S21-publish-error-w980-light-ic@8188b73.png` | light | 980×640 | inline Error: with the Retry and Details icon buttons on their plate after a stubbed failed upload, at w980 | `layout/S21-publish-error-w980-light-ic@8188b73.json` | — |
| `S21-publish-progress-footer-w1280-dark-ic@8188b73.png` | dark | 1280×800 | footer crop during the upload, at w1280 | `layout/S21-publish-progress-footer-w1280-dark-ic@8188b73.json` | — |
| `S21-publish-progress-footer-w1280-light-ic@8188b73.png` | light | 1280×800 | footer crop during the upload, at w1280 | `layout/S21-publish-progress-footer-w1280-light-ic@8188b73.json` | — |
| `S21-publish-progress-footer-w1440-dark-ic@8188b73.png` | dark | 1440×900 | footer crop during the upload, at w1440 | `layout/S21-publish-progress-footer-w1440-dark-ic@8188b73.json` | — |
| `S21-publish-progress-footer-w1440-light-ic@8188b73.png` | light | 1440×900 | footer crop during the upload, at w1440 | `layout/S21-publish-progress-footer-w1440-light-ic@8188b73.json` | — |
| `S21-publish-progress-footer-w980-dark-ic@8188b73.png` | dark | 980×640 | footer crop during the upload, at w980 | `layout/S21-publish-progress-footer-w980-dark-ic@8188b73.json` | — |
| `S21-publish-progress-footer-w980-light-ic@8188b73.png` | light | 980×640 | footer crop during the upload, at w980 | `layout/S21-publish-progress-footer-w980-light-ic@8188b73.json` | — |
| `S21-publish-progress-w1280-dark-ic@8188b73.png` | dark | 1280×800 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w1280 | `layout/S21-publish-progress-w1280-dark-ic@8188b73.json` | — |
| `S21-publish-progress-w1280-light-ic@8188b73.png` | light | 1280×800 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w1280 | `layout/S21-publish-progress-w1280-light-ic@8188b73.json` | — |
| `S21-publish-progress-w1440-dark-ic@8188b73.png` | dark | 1440×900 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w1440 | `layout/S21-publish-progress-w1440-dark-ic@8188b73.json` | — |
| `S21-publish-progress-w1440-light-ic@8188b73.png` | light | 1440×900 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w1440 | `layout/S21-publish-progress-w1440-light-ic@8188b73.json` | — |
| `S21-publish-progress-w980-dark-ic@8188b73.png` | dark | 980×640 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w980 | `layout/S21-publish-progress-w980-dark-ic@8188b73.json` | — |
| `S21-publish-progress-w980-light-ic@8188b73.png` | light | 980×640 | Uploading <name>…: 20 pt spinner, truncating status, Cancel on its plate; the Original size checkbox only where the slot holds it, at w980 | `layout/S21-publish-progress-w980-light-ic@8188b73.json` | — |
| `S21-publish-retrying-w1280-dark-ic@8188b73.png` | dark | 1280×800 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w1280 | `layout/S21-publish-retrying-w1280-dark-ic@8188b73.json` | — |
| `S21-publish-retrying-w1280-light-ic@8188b73.png` | light | 1280×800 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w1280 | `layout/S21-publish-retrying-w1280-light-ic@8188b73.json` | — |
| `S21-publish-retrying-w1440-dark-ic@8188b73.png` | dark | 1440×900 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w1440 | `layout/S21-publish-retrying-w1440-dark-ic@8188b73.json` | — |
| `S21-publish-retrying-w1440-light-ic@8188b73.png` | light | 1440×900 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w1440 | `layout/S21-publish-retrying-w1440-light-ic@8188b73.json` | — |
| `S21-publish-retrying-w980-dark-ic@8188b73.png` | dark | 980×640 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w980 | `layout/S21-publish-retrying-w980-dark-ic@8188b73.json` | — |
| `S21-publish-retrying-w980-light-ic@8188b73.png` | light | 980×640 | Retrying <name>… with the spinner and Cancel, after Retry from a failed upload, at w980 | `layout/S21-publish-retrying-w980-light-ic@8188b73.json` | — |
| `S21-publish-success-footer-w1280-dark-ic@8188b73.png` | dark | 1280×800 | footer crop with Link copied · the link, Open and Copy, at w1280 | `layout/S21-publish-success-footer-w1280-dark-ic@8188b73.json` | — |
| `S21-publish-success-footer-w1280-light-ic@8188b73.png` | light | 1280×800 | footer crop with Link copied · the link, Open and Copy, at w1280 | `layout/S21-publish-success-footer-w1280-light-ic@8188b73.json` | — |
| `S21-publish-success-footer-w1440-dark-ic@8188b73.png` | dark | 1440×900 | footer crop with Link copied · the link, Open and Copy, at w1440 | `layout/S21-publish-success-footer-w1440-dark-ic@8188b73.json` | — |
| `S21-publish-success-footer-w1440-light-ic@8188b73.png` | light | 1440×900 | footer crop with Link copied · the link, Open and Copy, at w1440 | `layout/S21-publish-success-footer-w1440-light-ic@8188b73.json` | — |
| `S21-publish-success-footer-w980-dark-ic@8188b73.png` | dark | 980×640 | footer crop with Link copied · the link, Open and Copy, at w980 | `layout/S21-publish-success-footer-w980-dark-ic@8188b73.json` | — |
| `S21-publish-success-footer-w980-light-ic@8188b73.png` | light | 980×640 | footer crop with Link copied · the link, Open and Copy, at w980 | `layout/S21-publish-success-footer-w980-light-ic@8188b73.json` | — |
| `S21-publish-success-w1280-dark-ic@8188b73.png` | dark | 1280×800 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w1280 | `layout/S21-publish-success-w1280-dark-ic@8188b73.json` | — |
| `S21-publish-success-w1280-light-ic@8188b73.png` | light | 1280×800 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w1280 | `layout/S21-publish-success-w1280-light-ic@8188b73.json` | — |
| `S21-publish-success-w1440-dark-ic@8188b73.png` | dark | 1440×900 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w1440 | `layout/S21-publish-success-w1440-dark-ic@8188b73.json` | — |
| `S21-publish-success-w1440-light-ic@8188b73.png` | light | 1440×900 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w1440 | `layout/S21-publish-success-w1440-light-ic@8188b73.json` | — |
| `S21-publish-success-w980-dark-ic@8188b73.png` | dark | 980×640 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w980 | `layout/S21-publish-success-w980-dark-ic@8188b73.json` | — |
| `S21-publish-success-w980-light-ic@8188b73.png` | light | 980×640 | Link copied · the link itself, then Open and Copy on their plate, after a stubbed upload, at w980 | `layout/S21-publish-success-w980-light-ic@8188b73.json` | — |
| `S21-upload-menu-busy-dark-ic@8188b73.png` | dark | 980×640 | destination choices while an upload runs (Cancel Upload offered) (glass panel) | `—` | — |
| `S21-upload-menu-busy-light-ic@8188b73.png` | light | 980×640 | destination choices while an upload runs (Cancel Upload offered) (glass panel) | `—` | — |
| `S21-upload-menu-busy-dismissed-dark-ic@8188b73.png` | dark | 980×640 | Upload panel dismissed with Escape | `layout/S21-upload-menu-busy-dismissed-dark-ic@8188b73.json` | — |
| `S21-upload-menu-busy-dismissed-light-ic@8188b73.png` | light | 980×640 | Upload panel dismissed with Escape | `layout/S21-upload-menu-busy-dismissed-light-ic@8188b73.json` | — |
| `S22-photos-populated-dark-ic@8188b73.png` | dark | 1488×1179 | Photos sheet over five synthetic fixture images in a throwaway folder (the real Photos library and Pictures folder are never read) | `—` | — |
| `S22-photos-populated-light-ic@8188b73.png` | light | 1488×1179 | Photos sheet over five synthetic fixture images in a throwaway folder (the real Photos library and Pictures folder are never read) | `—` | — |
| `S22-photos-populated-in-context-dark-ic@8188b73.png` | dark | 1488×1179 | Photos sheet over five synthetic fixture images in a throwaway folder (the real Photos library and Pictures folder are never read) (parent window + sheet composite) | `—` | — |
| `S22-photos-populated-in-context-light-ic@8188b73.png` | light | 1488×1179 | Photos sheet over five synthetic fixture images in a throwaway folder (the real Photos library and Pictures folder are never read) (parent window + sheet composite) | `—` | — |
| `S24-statusitem-highlighted-dark-ic@8188b73.png` | dark | 1488×1179 | menu-bar icon, highlighted (menu open) (the real template icon on a stand-in menu-bar strip painted for this state and appearance; the real bar is not captured) | `—` | — |
| `S24-statusitem-highlighted-light-ic@8188b73.png` | light | 1488×1179 | menu-bar icon, highlighted (menu open) (the real template icon on a stand-in menu-bar strip painted for this state and appearance; the real bar is not captured) | `—` | — |
| `S24-statusitem-normal-dark-ic@8188b73.png` | dark | 1488×1179 | menu-bar icon, normal (the real template icon on a stand-in menu-bar strip painted for this state and appearance; the real bar is not captured) | `—` | — |
| `S24-statusitem-normal-light-ic@8188b73.png` | light | 1488×1179 | menu-bar icon, normal (the real template icon on a stand-in menu-bar strip painted for this state and appearance; the real bar is not captured) | `—` | — |
| `S25-about-panel-dark-ic@8188b73.png` | dark | 1488×1179 | app-owned About window: icon, name, version and build, credit line, license link | `—` | — |
| `S25-about-panel-light-ic@8188b73.png` | light | 1488×1179 | app-owned About window: icon, name, version and build, credit line, license link | `—` | — |
| `S25-license-window-dark-ic@8188b73.png` | dark | 1488×1179 | the MIT License window with the paragraphs reflowed to the window width | `—` | — |
| `S25-license-window-light-ic@8188b73.png` | light | 1488×1179 | the MIT License window with the paragraphs reflowed to the window width | `—` | — |
| `S26-close-unsaved-dark-ic@8188b73.png` | dark | 1488×1179 | Save your drawing? sheet (Save / Cancel / Don’t Save) | `—` | — |
| `S26-close-unsaved-light-ic@8188b73.png` | light | 1488×1179 | Save your drawing? sheet (Save / Cancel / Don’t Save) | `—` | — |
| `S26-error-generic-dark-ic@8188b73.png` | dark | 1488×1179 | generic error sheet | `—` | — |
| `S26-error-generic-light-ic@8188b73.png` | light | 1488×1179 | generic error sheet | `—` | — |
| `S26-history-hide-dark-ic@8188b73.png` | dark | 1488×1179 | Hide drawings from History? sheet | `—` | — |
| `S26-history-hide-light-ic@8188b73.png` | light | 1488×1179 | Hide drawings from History? sheet | `—` | — |
| `S26-history-trash-dark-ic@8188b73.png` | dark | 1488×1179 | Move archived drawings to Trash? sheet | `—` | — |
| `S26-history-trash-light-ic@8188b73.png` | light | 1488×1179 | Move archived drawings to Trash? sheet | `—` | — |
| `S26-rename-dark-ic@8188b73.png` | dark | 1488×1179 | Rename… sheet with text field | `—` | — |
| `S26-rename-light-ic@8188b73.png` | light | 1488×1179 | Rename… sheet with text field | `—` | — |
| `S28-focus-footer-upload-dark-ic@8188b73.png` | dark | 1488×1179 | Upload button is first responder | `layout/S28-focus-footer-upload-dark-ic@8188b73.json` | — |
| `S28-focus-footer-upload-light-ic@8188b73.png` | light | 1488×1179 | Upload button is first responder | `layout/S28-focus-footer-upload-light-ic@8188b73.json` | — |
| `S28-focus-footer-zoom-dark-ic@8188b73.png` | dark | 1488×1179 | Zoom popup is first responder | `layout/S28-focus-footer-zoom-dark-ic@8188b73.json` | — |
| `S28-focus-footer-zoom-light-ic@8188b73.png` | light | 1488×1179 | Zoom popup is first responder | `layout/S28-focus-footer-zoom-light-ic@8188b73.json` | — |
| `S28-focus-topbar-hide-dark-ic@8188b73.png` | dark | 1488×1179 | Hide button is first responder | `layout/S28-focus-topbar-hide-dark-ic@8188b73.json` | — |
| `S28-focus-topbar-hide-light-ic@8188b73.png` | light | 1488×1179 | Hide button is first responder | `layout/S28-focus-topbar-hide-light-ic@8188b73.json` | — |
| `S28-focus-topbar-snap-dark-ic@8188b73.png` | dark | 1488×1179 | Snap (primary) is first responder | `layout/S28-focus-topbar-snap-dark-ic@8188b73.json` | — |
| `S28-focus-topbar-snap-light-ic@8188b73.png` | light | 1488×1179 | Snap (primary) is first responder | `layout/S28-focus-topbar-snap-light-ic@8188b73.json` | — |
| `S28-focus-topbar-tool-dark-ic@8188b73.png` | dark | 1488×1179 | Brush tool button is first responder (focus ring) | `layout/S28-focus-topbar-tool-dark-ic@8188b73.json` | — |
| `S28-focus-topbar-tool-light-ic@8188b73.png` | light | 1488×1179 | Brush tool button is first responder (focus ring) | `layout/S28-focus-topbar-tool-light-ic@8188b73.json` | — |
| `S29-drag-thumbnail-dark-ic@8188b73.png` | dark | 1488×1179 | Drag Me thumbnail panel after the editor shrinks (not hovering) | `—` | — |
| `S29-drag-thumbnail-light-ic@8188b73.png` | light | 1488×1179 | Drag Me thumbnail panel after the editor shrinks (not hovering) | `—` | — |
| `S29-drag-thumbnail-expand-dark-ic@8188b73.png` | dark | 1488×1179 | clickToExpand overlay | `—` | — |
| `S29-drag-thumbnail-expand-light-ic@8188b73.png` | light | 1488×1179 | clickToExpand overlay | `—` | — |
| `S29-help-bevel-dark-ic@8188b73.png` | dark | 1488×1179 | OriginalHelpBevel HUD with a hover hint for a top-bar control (Rectangle tool) (feature is off by default); editor at the top of the screen, so the plate sits inside the window, clear of the title bar and both bars | `—` | — |
| `S29-help-bevel-light-ic@8188b73.png` | light | 1488×1179 | OriginalHelpBevel HUD with a hover hint for a top-bar control (Rectangle tool) (feature is off by default); editor at the top of the screen, so the plate sits inside the window, clear of the title bar and both bars | `—` | — |
| `S29-help-bevel-bottom-dark-ic@8188b73.png` | dark | 1488×1179 | OriginalHelpBevel HUD with a hover hint for a bottom-bar control (Wipe) (feature is off by default); editor at the top of the screen, so the plate sits inside the window, clear of the title bar and both bars | `—` | — |
| `S29-help-bevel-bottom-light-ic@8188b73.png` | light | 1488×1179 | OriginalHelpBevel HUD with a hover hint for a bottom-bar control (Wipe) (feature is off by default); editor at the top of the screen, so the plate sits inside the window, clear of the title bar and both bars | `—` | — |
| `S29-help-bevel-hanging-dark-ic@8188b73.png` | dark | 1488×1179 | the same hint with 140 pt free above the editor: the plate hangs from its top edge, behind it | `—` | — |
| `S29-help-bevel-hanging-light-ic@8188b73.png` | light | 1488×1179 | the same hint with 140 pt free above the editor: the plate hangs from its top edge, behind it | `—` | — |

