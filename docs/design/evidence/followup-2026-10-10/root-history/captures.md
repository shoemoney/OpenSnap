# History glass controls — root review

Source `718f601`; icon mode **sf** (FA unavailable); 48 captures, every PNG scaled to at most 1200 px wide.
Pre-change twins are referenced from `docs/design/evidence/impl-2026-10-09/root-final-history` at `41700b3`; they are not copied.

| Capture | Appearance | Window pt | What it shows | Layout JSON | BEFORE (pre-change) |
|---|---|---|---|---|---|
| `S20-history-1120x850-selected-darkfollowup-root@718f601.png` | dark | 1120×812 | six synthetic entries, one selected, window 1120 x 850: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-1120x850-selected-lightfollowup-root@718f601.png` | light | 1120×812 | six synthetic entries, one selected, window 1120 x 850: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-1280x800-selected-darkfollowup-root@718f601.png` | dark | 1120×812 | six synthetic entries, one selected, window 1280 x 800: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-1280x800-selected-lightfollowup-root@718f601.png` | light | 1120×812 | six synthetic entries, one selected, window 1280 x 800: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-880x600-none-darkfollowup-root@718f601.png` | dark | 1120×812 | 880 x 600, nothing selected: the details column shows the summary instead of a blank hint; tiles sized to their preview | `—` | — |
| `S20-history-880x600-none-lightfollowup-root@718f601.png` | light | 1120×812 | 880 x 600, nothing selected: the details column shows the summary instead of a blank hint; tiles sized to their preview | `—` | — |
| `S20-history-880x600-selected-darkfollowup-root@718f601.png` | dark | 1120×812 | six synthetic entries, one selected, window 880 x 600: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-880x600-selected-lightfollowup-root@718f601.png` | light | 1120×812 | six synthetic entries, one selected, window 880 x 600: grid reflow, check badge, details beside the grid | `—` | — |
| `S20-history-action-focus-darkfollowup-root@718f601.png` | dark | 1120×812 | keyboard focus on the Open action: the focus ring around its rounded fill (made first responder directly; real Tab reaches it only with Full Keyboard Access or Window > Focus Toolbar) | `—` | — |
| `S20-history-action-focus-lightfollowup-root@718f601.png` | light | 1120×812 | keyboard focus on the Open action: the focus ring around its rounded fill (made first responder directly; real Tab reaches it only with Full Keyboard Access or Window > Focus Toolbar) | `—` | — |
| `S20-history-action-hover-darkfollowup-root@718f601.png` | dark | 1120×812 | one entry selected and the Copy action hovered: its own label 0.08 fill on the glass plate, the other actions at rest | `—` | — |
| `S20-history-action-hover-lightfollowup-root@718f601.png` | light | 1120×812 | one entry selected and the Copy action hovered: its own label 0.08 fill on the glass plate, the other actions at rest | `—` | — |
| `S20-history-action-pressed-darkfollowup-root@718f601.png` | dark | 1120×812 | one entry selected and the Copy action held down (press bracket driven directly, not a real click): the pressed fill and glyph scale on its plate | `—` | — |
| `S20-history-action-pressed-lightfollowup-root@718f601.png` | light | 1120×812 | one entry selected and the Copy action held down (press bracket driven directly, not a real click): the pressed fill and glyph scale on its plate | `—` | — |
| `S20-history-empty-darkfollowup-root@718f601.png` | dark | 1120×812 | History window with no entries | `—` | — |
| `S20-history-empty-lightfollowup-root@718f601.png` | light | 1120×812 | History window with no entries | `—` | — |
| `S20-history-link-copied-darkfollowup-root@718f601.png` | dark | 1120×812 | a Shared entry selected after Copy Link: the footer confirms, and the destination link is cut in its middle with the full text in its tooltip | `—` | — |
| `S20-history-link-copied-lightfollowup-root@718f601.png` | light | 1120×812 | a Shared entry selected after Copy Link: the footer confirms, and the destination link is cut in its middle with the full text in its tooltip | `—` | — |
| `S20-history-no-match-darkfollowup-root@718f601.png` | dark | 1120×812 | filters that match nothing at 880 x 600: centred message, no save hint | `—` | — |
| `S20-history-no-match-lightfollowup-root@718f601.png` | light | 1120×812 | filters that match nothing at 880 x 600: centred message, no save hint | `—` | — |
| `S20-history-no-match-footer-darkfollowup-root@718f601.png` | dark | 1120×812 | filters that match nothing: the footer stays (0 of 6 items) and Clear filters offers the way out | `—` | — |
| `S20-history-no-match-footer-lightfollowup-root@718f601.png` | light | 1120×812 | filters that match nothing: the footer stays (0 of 6 items) and Clear filters offers the way out | `—` | — |
| `S20-history-populated-darkfollowup-root@718f601.png` | dark | 1120×812 | six synthetic entries across dates and actions (Saved/Exported/Shared) | `—` | — |
| `S20-history-populated-lightfollowup-root@718f601.png` | light | 1120×812 | six synthetic entries across dates and actions (Saved/Exported/Shared) | `—` | — |
| `S20-history-selected-darkfollowup-root@718f601.png` | dark | 1120×812 | one entry selected (action buttons enabled) | `—` | — |
| `S20-history-selected-lightfollowup-root@718f601.png` | light | 1120×812 | one entry selected (action buttons enabled) | `—` | — |
| `S20-history-tile-hover-darkfollowup-root@718f601.png` | dark | 1120×812 | one entry selected (accent fill, border, check badge) and another tile hovered (label 0.08 fill) | `—` | — |
| `S20-history-tile-hover-lightfollowup-root@718f601.png` | light | 1120×812 | one entry selected (accent fill, border, check badge) and another tile hovered (label 0.08 fill) | `—` | — |
| `S43-history-delete-web-disabled-darkfollowup-root@718f601.png` | dark | 1488×1179 | Delete from Web dimmed for an upload with no recorded destination, its reason on the tooltip plate (F-J2-002) | `—` | — |
| `S43-history-delete-web-disabled-lightfollowup-root@718f601.png` | light | 1488×1179 | Delete from Web dimmed for an upload with no recorded destination, its reason on the tooltip plate (F-J2-002) | `—` | — |
| `S43-w980-photos-empty-darkfollowup-root@718f601.png` | dark | 980×640 | Photos sheet with nothing chosen over the 980 x minimum-height window: the grid, then the buttons with no blank band between | `—` | — |
| `S43-w980-photos-empty-lightfollowup-root@718f601.png` | light | 980×640 | Photos sheet with nothing chosen over the 980 x minimum-height window: the grid, then the buttons with no blank band between | `—` | — |
| `S43-w980-photos-empty-in-context-darkfollowup-root@718f601.png` | dark | 980×640 | Photos sheet with nothing chosen over the 980 x minimum-height window: the grid, then the buttons with no blank band between (parent window + sheet composite) | `—` | — |
| `S43-w980-photos-empty-in-context-lightfollowup-root@718f601.png` | light | 980×640 | Photos sheet with nothing chosen over the 980 x minimum-height window: the grid, then the buttons with no blank band between (parent window + sheet composite) | `—` | — |
| `S43-w980-resize-crop-darkfollowup-root@718f601.png` | dark | 1561×1179 | Resize or Crop sheet, crop mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row | `—` | — |
| `S43-w980-resize-crop-lightfollowup-root@718f601.png` | light | 1561×1179 | Resize or Crop sheet, crop mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row | `—` | — |
| `S43-w980-resize-crop-in-context-darkfollowup-root@718f601.png` | dark | 1561×1179 | Resize or Crop sheet, crop mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row (parent window + sheet composite) | `—` | — |
| `S43-w980-resize-crop-in-context-lightfollowup-root@718f601.png` | light | 1561×1179 | Resize or Crop sheet, crop mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row (parent window + sheet composite) | `—` | — |
| `S43-w980-resize-limit-darkfollowup-root@718f601.png` | dark | 980×640 | Resize or Crop sheet, limit mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row | `—` | — |
| `S43-w980-resize-limit-lightfollowup-root@718f601.png` | light | 980×640 | Resize or Crop sheet, limit mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row | `—` | — |
| `S43-w980-resize-limit-in-context-darkfollowup-root@718f601.png` | dark | 980×640 | Resize or Crop sheet, limit mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row (parent window + sheet composite) | `—` | — |
| `S43-w980-resize-limit-in-context-lightfollowup-root@718f601.png` | light | 980×640 | Resize or Crop sheet, limit mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row (parent window + sheet composite) | `—` | — |
| `S43-w980-resize-resize-darkfollowup-root@718f601.png` | dark | 980×640 | Resize or Crop sheet, resize mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row | `—` | — |
| `S43-w980-resize-resize-lightfollowup-root@718f601.png` | light | 980×640 | Resize or Crop sheet, resize mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row | `—` | — |
| `S43-w980-resize-resize-in-context-darkfollowup-root@718f601.png` | dark | 980×640 | Resize or Crop sheet, resize mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row (parent window + sheet composite) | `—` | — |
| `S43-w980-resize-resize-in-context-lightfollowup-root@718f601.png` | light | 980×640 | Resize or Crop sheet, resize mode, over the 980 x minimum-height window: whole sheet inside the parent, no clipped row (parent window + sheet composite) | `—` | — |
| `S43-zoom25-selection-handles-darkfollowup-root@718f601.png` | dark | 1488×1179 | rectangle selected at 25% zoom: handles stay a usable size and do not bury the selection (F-J1-016) | `layout/S43-zoom25-selection-handles-darkfollowup-root@718f601.json` | — |
| `S43-zoom25-selection-handles-lightfollowup-root@718f601.png` | light | 1488×1179 | rectangle selected at 25% zoom: handles stay a usable size and do not bury the selection (F-J1-016) | `layout/S43-zoom25-selection-handles-lightfollowup-root@718f601.json` | — |
