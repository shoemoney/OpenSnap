# Queue

Things raised mid-task and deliberately not acted on. Captured, not executed.
Nothing here is in progress unless it says so.

## In progress

## Completed
- **Glass choices across OpenSnap** (Jeremy, 2026-10-10). Completed locally: grouped glass commands and choices across editor/History, Toolbox/Zoom/Upload, Color/Size, Settings/Resize and destination forms. Source `21b8d68` passed the serialized full suite (52 suites; app-safety 275/275), external AX/targeted-key review on identical product sources and 448 strict-checked final captures. Integrated on main at docs head `436b9eb` and cold rebuilt. [Root verification](docs/design/e2e/glass-pickers-root-verification.md) and [before/after gallery](docs/design/glass-pickers-gallery.html). Physical pointer/hover, VoiceOver speech and hardware/provider coverage remain qualified manual limits.
- **History text and glass buttons** (Jeremy, 2026-10-09 21:33 CDT, via scopecreep). "the history section needs some work on the text/buttons to be buttons glass effecd". Polish History text and present its actions as recognizable buttons with Liquid Glass styling consistent with the editor.
  Blast radius: OpenSnap History window, its text and action controls, and shared chrome/button styling. Coordinate with the ongoing visual roadmap owners when scheduled. Activated by Jeremy on 2026-10-10 19:23 CDT: “great job lets implement changes”. Completed locally: grouped glass action buttons, readable labels, named accessibility groups and button-state polish. Integrated at `b6b6b2e`, source tested at `1ac6674` (263/263 app-safety). Root History review and final viewport renders passed with real stores unchanged. See [follow-up root verification](docs/design/e2e/followup-root-verification.md) and [gallery](docs/design/audit-overview.html). Manual VoiceOver and real hover/Tab remain separately tracked acceptance gaps.

## Ready

## Blocked

## Notes worth keeping

## Measured and deliberately dropped
