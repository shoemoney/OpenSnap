# Audit fix 8: the J7 findings

Source `ee89d7b`; icon mode **sf** (FA unavailable); 24 captures, every PNG scaled to at most 1200 px wide.
Pre-change twins are referenced from `docs/design/evidence/impl-2026-10-09/audit-fix-6` at `cc764dc`; they are not copied.

| Capture | Appearance | Window pt | What it shows | Layout JSON | BEFORE (pre-change) |
|---|---|---|---|---|---|
| `S45-capture-note-not-paused-dark@ee89d7b.png` | dark | 980×640 | Capture tab while Settings is not the window in use: the normal note (F-J7-004) | `—` | — |
| `S45-capture-note-not-paused-light@ee89d7b.png` | light | 980×640 | Capture tab while Settings is not the window in use: the normal note (F-J7-004) | `—` | — |
| `S45-capture-note-paused-dark@ee89d7b.png` | dark | 980×640 | Capture tab with Settings key and the app active: the note says the shortcuts are paused (F-J7-004) | `—` | — |
| `S45-capture-note-paused-light@ee89d7b.png` | light | 980×640 | Capture tab with Settings key and the app active: the note says the shortcuts are paused (F-J7-004) | `—` | — |
| `S45-footer-w980-error-checkbox-dark@ee89d7b.png` | dark | 980×640 | 980 wide, a WebDAV upload refused with HTTP 403: Original size still showing, the message at its narrowest (Failed), Retry and Details beside it (F-J7-002, F-J7-006) | `layout/S45-footer-w980-error-checkbox-dark@ee89d7b.json` | — |
| `S45-footer-w980-error-checkbox-light@ee89d7b.png` | light | 980×640 | 980 wide, a WebDAV upload refused with HTTP 403: Original size still showing, the message at its narrowest (Failed), Retry and Details beside it (F-J7-002, F-J7-006) | `layout/S45-footer-w980-error-checkbox-light@ee89d7b.json` | — |
| `S45-history-details-shared-after-dark@ee89d7b.png` | dark | 1482×1179 | the same entry after Delete from Web: the link is gone, Details still reads 1200 × 844 (published), not the History copy's 1438 × 1011 (F-J7-003) | `—` | — |
| `S45-history-details-shared-after-light@ee89d7b.png` | light | 1482×1179 | the same entry after Delete from Web: the link is gone, Details still reads 1200 × 844 (published), not the History copy's 1438 × 1011 (F-J7-003) | `—` | — |
| `S45-history-details-shared-before-dark@ee89d7b.png` | dark | 1482×1179 | a shared entry whose History copy is 1438 × 1011 and whose web copy is 1200 × 844: Details reads 1200 × 844 (published) (F-J7-003) | `—` | — |
| `S45-history-details-shared-before-light@ee89d7b.png` | light | 1482×1179 | a shared entry whose History copy is 1438 × 1011 and whose web copy is 1200 × 844: Details reads 1200 × 844 (published) (F-J7-003) | `—` | — |
| `S45-resize-then-ticked-dark@ee89d7b.png` | dark | 1244×968 | the box ticked afterwards: nothing changes, the title still reads 1200 × 800 · PNG · 216 KB (F-J7-005) | `layout/S45-resize-then-ticked-dark@ee89d7b.json` | — |
| `S45-resize-then-ticked-light@ee89d7b.png` | light | 1244×968 | the box ticked afterwards: nothing changes, the title still reads 1200 × 800 · PNG · 216 KB (F-J7-005) | `layout/S45-resize-then-ticked-light@ee89d7b.json` | — |
| `S45-resize-unticked-after-dark@ee89d7b.png` | dark | 1244×968 | after Resize to 1200 wide with the box unticked: the picture is {1200, 800}, the title reads 1200 × 800 · PNG · 216 KB and the box has nothing to offer (F-J7-005) | `layout/S45-resize-unticked-after-dark@ee89d7b.json` | — |
| `S45-resize-unticked-after-light@ee89d7b.png` | light | 1244×968 | after Resize to 1200 wide with the box unticked: the picture is {1200, 800}, the title reads 1200 × 800 · PNG · 216 KB and the box has nothing to offer (F-J7-005) | `layout/S45-resize-unticked-after-light@ee89d7b.json` | — |
| `S45-resize-unticked-before-dark@ee89d7b.png` | dark | 980×640 | Original size unticked on a 2400 × 1600 snap: the title reads the shown size 1517 × 1011 · PNG · 305 KB | `layout/S45-resize-unticked-before-dark@ee89d7b.json` | — |
| `S45-resize-unticked-before-light@ee89d7b.png` | light | 980×640 | Original size unticked on a 2400 × 1600 snap: the title reads the shown size 1517 × 1011 · PNG · 305 KB | `layout/S45-resize-unticked-before-light@ee89d7b.json` | — |
| `S45-webdav-test-2xx-640-dark@ee89d7b.png` | dark | 1120×812 | WebDAV form at 640 pt after a Test that reached a server (HTTP 207): the whole note, ending Nothing was uploaded. (F-J7-001) | `—` | — |
| `S45-webdav-test-2xx-640-light@ee89d7b.png` | light | 1120×812 | WebDAV form at 640 pt after a Test that reached a server (HTTP 207): the whole note, ending Nothing was uploaded. (F-J7-001) | `—` | — |
| `S45-webdav-test-2xx-640-in-context-dark@ee89d7b.png` | dark | 1120×812 | WebDAV form at 640 pt after a Test that reached a server (HTTP 207): the whole note, ending Nothing was uploaded. (F-J7-001) (parent window + sheet composite) | `—` | — |
| `S45-webdav-test-2xx-640-in-context-light@ee89d7b.png` | light | 1120×812 | WebDAV form at 640 pt after a Test that reached a server (HTTP 207): the whole note, ending Nothing was uploaded. (F-J7-001) (parent window + sheet composite) | `—` | — |
| `S45-webdav-test-2xx-900-dark@ee89d7b.png` | dark | 1120×812 | WebDAV form at 900 pt after a Test that reached a server (HTTP 207): the whole note, ending Nothing was uploaded. (F-J7-001) | `—` | — |
| `S45-webdav-test-2xx-900-light@ee89d7b.png` | light | 1120×812 | WebDAV form at 900 pt after a Test that reached a server (HTTP 207): the whole note, ending Nothing was uploaded. (F-J7-001) | `—` | — |
| `S45-webdav-test-2xx-900-in-context-dark@ee89d7b.png` | dark | 1120×812 | WebDAV form at 900 pt after a Test that reached a server (HTTP 207): the whole note, ending Nothing was uploaded. (F-J7-001) (parent window + sheet composite) | `—` | — |
| `S45-webdav-test-2xx-900-in-context-light@ee89d7b.png` | light | 1120×812 | WebDAV form at 900 pt after a Test that reached a server (HTTP 207): the whole note, ending Nothing was uploaded. (F-J7-001) (parent window + sheet composite) | `—` | — |


## What each capture shows (audit fix batch 8, the J7 findings)

- `S45-webdav-test-2xx-640` / `-900`: the WebDAV Test note after a 207, whole in three lines, ending "Nothing was uploaded." (F-J7-001).
- `S45-footer-w980-error-checkbox`: 980 wide, a refused upload: Original size still showing, the message at its narrowest ("Failed"), Retry and Details beside it (F-J7-002, F-J7-006).
- `S45-capture-note-not-paused` / `-paused`: Settings › Capture note in both states (F-J7-004).
- `S45-history-details-shared-before` / `-after`: Details of a shared entry whose History copy is 1438 × 1011: Size reads 1200 × 844 (published) before and after Delete from Web (F-J7-003).
- `S45-resize-unticked-before` / `-after`, `S45-resize-then-ticked`: Resize to 1200 wide with the box unticked rewrites the picture (title 1200 × 800, no box left); ticking afterwards changes nothing (F-J7-005).

