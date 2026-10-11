# Glass choices root verification — 2026-10-10

Status: implemented and accepted locally after root corrections. Tested source `21b8d68e10543b097cb6a902103e9c56eeb76be5`, tree `047c1a0ce65c3806633926740afea20c8eaffc4d`. Final local integration and cold rebuild are recorded below. Physical pointer hover, VoiceOver speech, live OS display settings and hardware/provider behavior remain qualified manual limits.

## Current acceptance

The requested glass choices are implemented: Toolbox/Zoom/Upload panels, Color/Size panels, Settings tabs/radios/toggles and shortcut choices, Resize groups/presets/actions, History category/date/export picks and grouped commands, destination Protocol/Source/ACL/actions, and editor Original size. The final reviewed screenshots show complete labels, clear chosen/focus states and horizontal containment inside a parent when the panel fits. Normal labels are 20pt with an 18pt app-drawn floor; OS title-bar typography remains OS-owned.

| Evidence | Result and practical limit |
| --- | --- |
| Full suite at `21b8d68` | Exit 0; 52 suites; app-safety 275/275; native idle termination passed; no source drift. Compilation is parallel, native suites run serially. Only unbundled FA Pro branches are skipped. |
| Glass S50–S60, light/dark | 206 PNGs; strict checker 0 failures, 0 advisories; 6 contrast samples skipped. No real keyboard/button/pointer input entered the capture run. |
| Core S06/S08/S09/S17/S19/S20/S23/S30/S31, light/dark | 180 PNGs; strict checker 0 failures, 0 advisories; 14 contrast samples skipped. Parked pointer events swallowed during native tracking are recorded in safety.txt and are not product interaction evidence. |
| Combined injected display options | 62 PNGs for S53/S56/S60, light/dark; Reduce Transparency, Increase Contrast, Differentiate Without Color and Reduce Motion; strict checker 0 failures/advisories. Root opened representative images in both appearances. These are injected app options, not live OS toggles. |
| Independent native external-client pass at `03d267b` | Every recorded AX action returned 0; no AXUnknown wrappers; coherent parents. All 18 Toolbox choices and all 69 Capture key rows are reachable. Color/Size/Zoom selection, Settings draft retention and modifier arrows, History filters/export format, sheet Return/Escape, Resize arrows and toolbar key handoff are verified by external AX and targeted routed keys. |
| Store guard | Watched 122 files and two defaults plists unchanged; digest `dbde037ac2085108`; throwaway preferences removed before comparison; native proof had zero watchdog kills. |

The final native review remains attributed to `03d267b933566114dad26e765f7fc306b553e2f4`. Sources, tests, Resources and Info.plist subtrees match the final gate source byte-for-byte. Only the app-safety harness event seam changed afterward. [Native source equivalence and outcomes](../evidence/glass-pickers-2026-10-10/native/03d267b/README.md), [final gate logs](../evidence/glass-pickers-2026-10-10/verification/21b8d68/gates.json), and [opened-image review](../evidence/glass-pickers-2026-10-10/opened-image-review.json) retain the exact identities.

Root inspected representative images for every S50–S60 area, minimum-width History and destination forms, full core forms and combined accessibility variants. Automated checks cover all 448 final PNGs; this is not a claim that root manually inspected every PNG or measured every text/background contrast pair. Raw renders are the canonical checker evidence. Packed gallery images are limited to 1280px wide; “Stored pixels” shows that stored image resolution, rather than claiming the original Retina pixels.

The [interactive before/after gallery](../glass-pickers-gallery.html) includes picker/phase/appearance filters, favorites, large previews, side-by-side comparison and downloads. Captures retain source and phase labels. The gallery's own text is at least 18 CSS px, normally 20px; final desktop/phone runtime results are recorded below.

Manual limits remain explicit: physical HID pointer/hover, VoiceOver speech, actual OS accessibility-setting changes, hardware screen capture and live provider operations. Full keyboard traversal under every OS keyboard-access configuration is not established. The successful toolbar command was activated via the known app-owned Window menu command; the failed driver attempt at Option-Command-T is not shortcut proof. Native system panels and OS menus retain their native presentation.

The evidence ledger remains conservative: 626 rows = 234 E2E, 32 rendered, 27 retired, 122 unit/source and 211 unverified. No rows were promoted by this report. All 94 `UI changed` histories and the 12 intrinsic unsafe/OS-owned gap reasons remain intact.

Earlier sections below are the historical review chronology and superseded checkpoints.

## Authorized scope

Make app-owned choices across OpenSnap consistent glass buttons: editor/History commands; Toolbox, Zoom and Upload choices; Color/Size pickers; Settings/Resize choices. Preserve existing actions, menu validation, selection state, undo transactions, keyboard access, focus restoration and accessibility. Use readable 20pt labels (18pt minimum), semantic Font Awesome artwork and compact grouped surfaces with no glass nested inside glass. OS-owned menu bar and system panels remain native.

## Phases and acceptance

1. Capture the baseline, enumerate picker choices, and specify the shared selection system and ownership.
2. Implement shared controls first, then owned menu/picker/form consumers in isolated branches.
3. Prove selection/activation/dismissal behavior, validation and accessibility; run the full suite with real-store guard. Review light/dark and injected accessibility variants in the guarded harness.
4. Independently inspect the pinned final candidate, integrate locally, rebuild and finish the interactive comparison gallery.

## Historical acceptance checklist — before root corrections

- [x] Baseline captures: 176 light/dark frames at `57ec799`, no capture gaps; watched stores unchanged (digest `dbde037ac2085108`). The input fence swallowed 36 pointer-only events during native menu tracking, with zero keyboard/button inputs. This is not real-input product coverage.
- [ ] Toolbox/Zoom/Upload choices presented as glass buttons.
- [ ] Color/Size selections preserve gestures, discrete picks and undo.
- [ ] Settings/Resize choices preserve forms, validation and defaults.
- [ ] Selected/disabled/hover/focus states and keyboard dismissal/focus return.
- [ ] Final behavior/accessibility gates and source-drift check.
- [ ] Root light/dark and accessibility render review.
- [ ] Local integration/rebuild, gallery and queue completion.

No push, tag, installation, owner-store migration or system settings change is authorized in this pass. Guarded synthetic copies are the only native execution path. Manual or hardware-dependent coverage will remain explicitly separated from source, unit and render evidence.

Baseline evidence is in `evidence/glass-pickers-2026-10-10/root-before/`. Root inspected representative Toolbox, Size and Settings baseline images. Existing S09 skips its Upload menu capture after failing to find the retired format popup; S23 dumps Zoom/Upload menu models rather than rendering them. Direct glass panel/state captures are required in the new candidate, and those baseline limits remain explicit.

Baseline pack checker passed: 176 PNGs, 34 layout JSONs, zero hard failures or contrast advisories; 18 contrast samples were skipped. This is a qualified baseline check, not exhaustive contrast or interaction proof. The native GUI slot was released to the orchestrator after this run; root will reserve it again for independent final-candidate renders.

## Historical root specification review

Integration plan commit `1e44d49` enumerates group/button/panel primitives, eight milestones and owned consumers. Root requested closing two scope holes before implementation: History date/category choices, and Settings destination-editor protocol/source choices and action buttons. Native search/text/password fields and content lists remain readable form/content surfaces; their selectable choices are part of the glass-button request. Root prepared `docs/design/glass-pickers-gallery.html` with explicit baseline labels, favorites, native-scale previews, downloads and comparison; it is not a finished-implementation claim. Its phone preview has an 18px readable minimum and no horizontal overflow.

The scope additions are now in integration plan commit `5685519`, with a dedicated destination-editor owner and History date/category ownership assigned. Consumer branches `gp-menus`, `gp-color-size`, `gp-settings`, `gp-resize`, `gp-destinations` and `gp-harness` are created alongside `gp-primitives`. Product implementation and native gates remain pending.

Gallery runtime verification (headless T3 preview, 728px/light): favorite-only filtering, empty shortlist state, picker filtering, explicit empty After state before implementation, clearing comparison, two-image limit, removal/re-addition and native-scale previews all passed. Both desktop and phone previews measured 18px readable minimum with no horizontal overflow. This checks the gallery controls and is not native real-input evidence.

Root expanded the baseline gallery to Settings Upload/Capture, synthetic S3/SFTP destination sheets and canvas Crop mode. Filtering now selects a matching view and hides the preview plus disables image actions when no capture matches, so an empty After filter cannot display a Before image. Headless runtime checks for both behaviors passed at 728px/light and 360px/dark, with readable text at least 18px and no horizontal overflow. Root opened the S3 form and Crop baseline images directly. These additions remain baseline evidence only.

Root added an app-appearance filter to the gallery. Light filtering, combined picker/appearance filtering and empty-After isolation pass in headless previews at 728px/light and 360px/dark; the 18px readable minimum and zero horizontal overflow are retained. Only baseline images are present, and these checks verify the gallery controls, not native picker behavior.

The follow-on source inventory found two existing choices still outside the plan's explicit rows: the destination sheet's public-read checkbox, and the editor footer's Original size checkbox. Root sent both to the ongoing orchestrator under F and A respectively, with exact storage/action preservation and footer width/reflow requirements. Their conversion and evidence are pending; they are part of the named Settings/editor scope.

Shared API milestone `048d37a` now exists on `impl/gp-primitives`: choice button/group, child-panel host, menu adapter, vertical plates, glyphs and suite source lists. Root inspected its selection, action-dispatch, focus and dismissal source paths. Its initial test file is only scaffolding; follow-up fixes and behavior tests are still being written. This milestone is not an integrated build or verification result. Separate partial commits exist for Settings tabs (`a32eddc`) and capture scaffolding (`e481054`); neither establishes final consumer coverage.

## Historical review checks during implementation

| Check | Current evidence | Required resolution |
| --- | --- | --- |
| Shared toggle changes exactly once | Settings worker reproduced a double flip at `048d37a`; fixes and fresh-button activation tests are committed at `e2d6223` / `0fb7786` | Final serialized suite plus native click, keyboard and AX activation evidence; handler receives the new value, programmatic assignment sends no action |
| Popup secondary routes stay glass | Shared `GlassPopUpButton` is committed at `a3e7d69`; root inspected its opening routes and 14-route test inventory | Consumer adoption, final serialized suite and independent native input review; no native picker fallback |
| Destination Protocol/Source option semantics | Root's `fdae0a1` classification finding is addressed in first-pass `3d4f377` with explicit options | Final candidate verifies radio role and 0/1 values for chosen and unchosen choices |
| Destination face operation | First-pass `3d4f377` adds sheet/window keyboard event tests and first-Escape dismissal; shared popup adoption remains underway | Final integrated event paths plus independent native input prove opening, second activation dismisses, default Return and focus return |
| Shared choice-label sizing | Root opened C's provisional clipping reference, then inspected fix `b2d9650` (integration `ef8e729`): sizing uses NSTextField fittingSize in the strong face, including wrapped line heights; regression checks cover single/wrapped labels and selection-stable widths | Final captures show complete labels, selected font never reduces fit, wrapped rows include every line, and consumer regression checks pass |
| Destination Source at minimum width | F round-3 `8d5183d` uses AWS profile/Keychain face titles while retaining full option/AX/tooltip text; reports width checks at 560/640/900 across every protocol/source combination and a failing long-title red proof | Final serialized integrated gates and opened minimum-width captures prove complete readable faces, 20pt text and preserved source option/action identity |
| Capture checker covers custom popup faces | Root inspected E's in-progress glassRecord: labelMetrics filters only GlassChoiceButton title labels, skipping custom-drawn GlassPopUpButton faces; an empty metrics array passes the checker | Capture/checker measures popup faceTitle against its actual font/draw rectangle, including narrow Source and compact Zoom, with a failing clipping fixture |
| Zoom's actual footer allocation | E's provisional smoke7 checker flags 100% needing 51×25pt but drawn in 32×36pt; root compared the tight Zoom source in A and E's scratch tree and sent the frame/measurement mismatch to A through the orchestrator | Final footer allocates enough text space for every percentage at 20pt while retaining the 980pt minimum and status-width behavior |
| Capture modifier-row keyboard, alignment and label height | C's `cd426be` restores one Tab stop per row and centers the glyphs; E's `88a95e3` captures still fail 12 strict checks because shifted Option/Control labels need 25–27pt but receive 24pt | Preserve roving focus and optical centering, fit the actual attributed labels, and pass fresh Capture-tab render/input checks |
| Original size during upload errors at minimum width | A's final report at `658d95f` reports a 13pt shortfall at 980pt and weakens the F-J7-006 expectations; root returned this to the orchestrator | Preserve the existing error-state toggle visibility at 980pt, restore the behavior expectations, and verify the real footer without reducing text size |

Root sent these checks to the ongoing implementation orchestrator. These historical implementation checkpoints led to the fixes recorded below; final source and native acceptance remain pending.

## Adversarial review checkpoint

Root read the full Opus review at `996f7fa` (detached `.todo-worktrees/gp-review`). It reports six confirmed defects and two plausible regressions; three confirmed findings were exercised by an active throwaway AppKit probe under the serialized GUI lock. This review predates the final candidate, and every finding remains an acceptance checkpoint until its fix and proof are inspected.

| Finding | Assigned owner | Required verification |
| --- | --- | --- |
| First click lost on non-key Size and hover-opened Color | B | First-mouse behavior for track, presets and swatches |
| Choice groups consume Return/keypad Enter in Resize | P, with D's sheet tests | Real window event dispatch reaches default OK |
| Capture modifier and Settings tab arrows reject real event flags | C | Arrow events include numeric-pad/function flags; all choices remain reachable |
| Child panels turn off Focus Toolbar | A2 | Dismissal restores both opener focus and continued toolbar Tab navigation |
| Capture key panel un-pauses shortcuts and loses rejected drafts | C | Own-child key transitions retain editing suspension, draft and error state |
| Resize mode arrows drop focus | D | Repeated arrow navigation keeps focus within the mode group |
| Type-to-select removed from choice panels | P | Enabled-row prefix navigation for long key lists |
| Color hover replaces an already-open menu panel | B | Hover preserves the active explicit panel |

The owners also cover menu-rebuild/orphan cleanup hardening and the default-appearance Color contrast check. Final evidence must distinguish on-screen probe results, source proofs, guarded renders and root's isolated app interactions.

Review fixes are merged at integration `2bdd28e`: P `c4f92eb`, C `c643d25`/`d27400b`, A2 `da8641a`, B `48115fd` and D `49bafa5`. Root inspected the source changes and relevant tests. D's Return test now independently fails when only P's group guard is reverted; its OK/default loops are offscreen window/responder routing, not active-app evidence. C and A2's parent/child key tests simulate handlers or notifications and carry the same qualification. B dispatches mouse events to an inactive offscreen test panel; its default-glass contrast check measures semantic label colours against window/canvas colours, with rendered glass still pending. Final integrated gates and root native interactions remain open.

`2bdd28e` is superseded developer evidence. Its full suite passed (275/275 app-safety, no source drift, stores unchanged), and its 206 glass plus 180 baseline PNGs passed the existing checker. The orchestrator's visual review nevertheless found Upload overhanging the editor's right edge by about 270pt and Size by about 55pt; History’s Drag as has the same issue. Placement constrained the panel to the screen rather than its parent. P’s `ab3bb20`, merged at `85ac52f`, keeps above/below panels inside the screen-visible horizontal portion of the parent whenever they fit; genuinely wider panels fall back to the screen. Its placement grid, host movement checks and two red proofs pass. E owns geometry metadata/checker assertions, including an independent fit calculation to reject false fallback reports, followed by fresh integrated gates and captures. Root has made no acceptance, main integration or After-gallery claim for this build. Root opened seven of its completed images as provisional visual references: Toolbox light, Zoom dark, Capture modifiers light, Color light, Size dark, destination Source light and General radio choices dark. They show complete labels and corrected states, but do not establish final geometry or input acceptance.

Root found a remaining iconography requirement before accepting `9cce74d`: the Toolbox’s new app-owned glass rows take `NSMenuItem.image` verbatim and therefore inherit MenuSymbols SF Symbols. Root assigned the semantic Font Awesome correction to the ongoing orchestrator, preserving native menu-bar models, actions, labels and shortcuts. Existing FA assets must be reused where available, with official embedded Free vectors for missing actions and a source/asset proof of the default branch. The `9cce74d` suite/capture run is developer evidence before that correction. The harness’s legacy `sf` mode strips Pro subsets; it does not force ChromeIcons to skip embedded FontAwesomeFree vectors. Final docs must describe the actual resolution chain accurately.

Root opened the completed `9cce74d` full-window light captures `S52-upload-rest`, `S54-size-rest` and `S55-history-dragas-rest`. All three panels now stay horizontally inside their visible parent, with complete menu/preset labels. This is provisional geometry review at the pre-icon source, not final-candidate acceptance. Its serialized full suite passes 275/275 app-safety with no source drift and stores unchanged; the new glass capture’s 206 images finished with zero real input events and unchanged store digest. The baseline capture and integrated Font Awesome correction remain in flight.

## Interim evidence integrity — 23:52 CDT

The orchestrator corrected its earlier claim that no worker captures had run: worker E ran isolated eye-dump smoke captures in `/tmp/gpE-smoke1..3`. These captures and some worker AppKit test runs may have overlapped after the old shared lock was removed while another worker held it. They are developer smoke results only and are excluded from acceptance evidence. The fleet now uses an owner-checked lock; acceptance requires fresh serialized integration gates and candidate captures, followed by root's independent review after the GUI slot is released.

Integration plan commit `ed39466` replaces the old unowned lock recipe with the owner-checked v2 protocol and records this evidence exclusion. Root inspected the updated protocol. Product gates and final captures remain pending.

Root also opened `/tmp/gpC/eye/raw-sf/S17-settings-general-light.png` as a provisional defect reference. It establishes visible clipping in that worker build, not final visual acceptance or serialized capture coverage. The ongoing orchestrator has already assigned the shared label-measurement and wrapping correction; no duplicate implementation was started by root.

Root opened `/tmp/gpE-final/raw-sf/S60-capture-modifiers-chosen-light.png` as a provisional reference after E's report at `88a95e3`. The modifier states and grouping read clearly, but the strict attributed-label height failures remain open. This image is not final acceptance evidence.

Destination first-pass commit `3d4f377` addresses the explicit option/radio semantics and first-Escape panel dismissal checks, but remains provisional. Its taller SFTP sheet scrolls on the original 1280×800 test screen; the worker is restoring that screen-size gate and compact fit, then adopting the shared popup base for AXShowMenu and downward disclosure. Root has not yet verified these changes through final renders or real input.

F round-2 commit `e9aaaad`, merged into integration as `86ef8e2`, restores the original 1280×800 fit assertion: SFTP fitting height is reported as 678pt against a 680pt cap. Protocol and Source use the shared popup base with option roles and all opening routes. These worker results are provisional until the final serialized integrated gates. F also reports Source truncation at the supported 560pt minimum sheet width; root sent that remaining width check to the ongoing owner.

## Independent candidate review inventory

The ledger reset at integration `bffe5e7` preserves the earlier native evidence for 91 converted rows as byte-exact history, including a digest and the pinned prior matrix. Those rows now count as unverified with reason `UI changed`; 15 already-unverified converted rows retain their existing audited limitations when still applicable. Root accepted the narrow vocabulary/README change. Generator-parser totals are 616 rows: 234 E2E, 32 rendered, 27 retired, 112 unit/source and 211 unverified. These totals precede final candidate verification and do not count new glass interactions as complete.

Root source review found that the generator permits fresh glass evidence but the new independent guard requires every historical row to remain unverified. The ongoing G owner is correcting that mismatch: preserve immutable native history and reject recycled native evidence, while allowing complete new observations at a new glass source SHA. No row is promoted by this correction alone.

G round 3 (`4f42665`, integration `3a5fda0`) addresses that mismatch and passes the guard's 186 checks. The history set now contains 94 rows: 78 previously E2E, 13 rendered and three already unverified. The three additional rows are Zoom 75%/100% and the empty Upload menu: their old readout-only limitation belonged to native menus that could not be imaged. The other 12 already-unverified rows retain their intrinsic unsafe/OS-owned reasons unchanged. Totals remain 234 E2E, 32 rendered, 27 retired, 112 unit/source and 211 unverified. The new guard permits complete fresh glass evidence and rejects reused native observations, SHAs, paths and missing fields; one positive fixture and nine mutants exercise that distinction. Root inspected the source and accepted the classification; no new glass coverage is claimed by this tooling correction.

The harness branch now declares direct glass capture surfaces S50–S60. This inventory is preparation only: no final candidate has been captured or accepted by root. Its hover states are injected, its focus uses `makeFirstResponder`, and its Escape events are synthesized; rendered states must not be described as physical mouse or keyboard coverage.

| Area | Required final evidence |
| --- | --- |
| Toolbox, Zoom and Upload | S50–S52 light/dark state captures; visible option/toggle semantics; validation and disabled skipping; native app opening, choosing and dismissal/focus checks |
| Color and Size | S53–S54 light/dark captures; native app preset selection and Size undo; suite proof of hover versus pinned opening, Shift/background selection and gesture termination |
| History choices and existing action plates | S55 plus existing History surfaces; category/date/Drag as changes reflected in the UI; readable action labels and retained grouping |
| Settings and destination editor | S56/S58 plus full form captures; tabs/radios/toggles/actions; Capture shortcut enable/key/modifier/Clear All choices (plan `857858c`); Protocol/Source choices, public-read state, Return/default Save and Escape; SFTP fits the original test screen and Source fits the supported minimum width |
| Resize | S57 plus existing Resize sheets; mode/limit/anchor/preset states; Return/default OK, Escape/Cancel and restored document state |
| Editor Original size and existing toolbar | S59 plus core editor captures; footer on/off/hidden states, width/reflow and retained grouped toolbar surfaces |

At this historical checkpoint all rows remained pending. Root will record the exact reviewed source commit and tree, serialized gate logs, actual opened images, isolated app input outcomes and any remaining manual/hardware gaps. The gallery will add After images only from that reviewed candidate.

## Root external-client blocker — 2026-10-11

The serialized full suite at `fa3ddf7537ce58c06e263d874b0abbda0320a76d` (tree `7db217abf8fd3c89f78ececaa7307ad8e71ca9fe`) passed all 52 suites, app-safety 275/275 and no source drift. Its 206 glass and 180 core light/dark PNGs each passed root's independent checker, with zero hard failures or advisories; 6 and 14 contrast samples were skipped respectively. Root opened representative images for every S50–S60 area and found no new visual objection. This source is nevertheless provisional and has not been integrated or labelled After.

Root's guarded native session exposed a real gap: an external AXUIElement client sees `AXWindow Toolbox -> AXGroup Toolbox children=0`, with no choice rows. Settings General similarly exposes empty Snapping and Hints groups; Resize's action group is empty. The external probe walks only this isolated application's windows. See `evidence/glass-pickers-2026-10-10/native/fa3ddf7-external-ax-blocker.txt` and its `external-ax-probe.swift`. P owns a shared PanelRootView/GlassSurfaceView semantic-children and parent-chain correction, with window-root traversal tests and a required external-client proof. Direct row-object assertions alone are insufficient.

The docs-only candidate `3fa5a952993d35125984c1e0ce40b3bc811d8199` changes only `docs/design/glass-pickers-implementation.md` and `docs/design/e2e/README.md` relative to the tested source, +132/-23, with Sources/tests/tools unchanged. It remains provisional pending the AX correction.

During this provisional native pass, routed Settings tab arrows changed General to Drawing to Capture. A coordinate click disabled the Capture enable toggle once. AXShowMenu opened the child key panel (the driver reported failure because it expects a native AXMenu, so the resulting glass window was independently observed). Routed K then Return selected K and retained the rejected draft/error when the panel closed. With the global enable flag off, external AX focus on Command followed by routed Right/Space reached Option and Control. Clear All reset the synthetic bindings; Resize Return closed the sheet. These are targeted/AX input results, not physical HID or VoiceOver speech. Full Tab navigation under the existing system keyboard-access preference and the Resize group's repeated arrows were not independently established and remain qualified.

The first executor-launched session's process lifetime ended when its terminal command returned; cleanup dropped its throwaway plist and the store guard passed. A held executor lifetime then kept the real review session running. Root stopped session `com.shoemoney.opensnap.e2e-31344`, with no watchdog kills, and verified digest `dbde037ac2085108` unchanged after cleanup. The owner-checked GUI slot was released for the corrective validation. Superseded packed captures are retained privately at `/tmp/opensnap-glass-superseded-fa3ddf7-packed`; root's gallery remains baseline-only.

## Corrective component verification — `5fceea6`

The window-root walk found the actual cause: `GlassChoiceButton` was an ignored control while also returning an empty children list, which suppressed both the button and its stand-in cell. Marking it as an accessibility element exposes its existing role, label, value and activation method. Reverting that change makes the Toolbox walk find zero rows. The new explicit panel/plate child lists are defensive: AppKit's default traversal exposes the fixed buttons without them, so no separate failing proof is claimed for those forwarders. Pop-up buttons also publish their own accessibility element and actions; focused choices scroll into view.

Root inspected the source and P's complete report. Its serialized component runs pass, including the actual Color/Size, Settings, History, Resize and toolbar tree checks, plus app-safety 275/275 and native idle shutdown. Tree tests check coherent parents and activation from reached elements. The primitive shortcut fixture has 52 rows; it is not a claim about every key in the real Capture form. Standard button-cell names/actions use the legacy accessibility attributes where the new protocol is silent; the helper qualifies its control-label fallback. The orchestrator's independent window-only AXUIElement pass and the final integrated suite/captures remain required before acceptance.

## Root takeover and additional corrections — 2026-10-11

The Claude provider usage cap stopped the orchestrator and its remaining worker at 03:12 CDT. Root cancelled later delegated turns to prevent overlapping edits, adopted the narrow unfinished correction, and continued validation under the owner-checked GUI lock. This is root work after the Opus/Sonnet/Haiku implementation, rather than a claim that those models performed the remaining gates.

The raw panel/plate child forwarders introduced in the first accessibility correction returned ignored AppKit container views. External clients exposed those views as `AXUnknown` wrappers. Default AppKit traversal exposes the now-explicit choice controls correctly, so root removed the forwarders and tightened the test walker to inspect raw returned children before unignored-child expansion. It checks legacy role attributes for legitimate AppKit stand-ins and coherent parents. It does not reject the OS title-bar's legitimate unnamed zoom-menu group. Restoring the forwarders fails the Size window-root test.

Root's initial synchronous Color action fixes (`9398144` and `add541c`) passed their in-process checks but still returned external `AXAttributeUnsupported` (-25205), despite opening the panel. Those sources are superseded. The final correction accepts accessibility activation before dispatching it on the next main-loop turn, including the button-cell `performClick` path. Tests prove accepted-before-dispatch, single activation, reached-element activation and disabled rejection. Pointer mouse-down and hover retain their existing paths. The external result, final integrated gates and captures will be recorded below when complete.

The first root probe chose an empty `AXTitle` before a nonempty `AXDescription`, hiding the Color control's real name. Correcting this private client lookup finds `Drawing colors`; this was a probe issue, not a product label defect. Both provisional root sessions were stopped and their throwaway preferences removed before the final guard comparison: the real-store digest stayed `dbde037ac2085108`, with zero panel-watchdog kills.

Root additionally reproduced -25205 when picking Color and Size presets at `9ef89b6` and `45e9522`: the chosen values changed correctly, but closing the panel during the accessibility action invalidated the external reply. `f35ac6a` first added explicit preset elements/selection values and static-text roles for History's summary. `7a44857` then deferred preset dispatch until after the AX reply; Color retains the initiating modifiers for Shift/background selection. Focused tests preserve discrete Size undo, selection and dismissal and distinguish accepted-before-dispatch from the applied result. Restoring synchronous preset dispatch fails that timing check. The History summary test fails when its static-text roles are removed.

Root also found that earlier `tools/test.py` runs were serialized only relative to other fleet commands; their internal native suites ran concurrently in a thread pool. `45e9522` keeps compilation parallel and adds a runtime lock around each native suite. The final root run uses that lock, with no interactive session or capture process overlapping it. Deferred activation tests now pump the main loop until the observed action completes, with a bounded deadline, rather than assuming completion after a fixed 20 ms.

The first root final-suite attempts passed all 52 native suites but stopped in app-safety: `efd74d0` had two stale synchronous Color assertions; `03d267b` corrected those but exposed a separate harness event mismatch. `App.swift` read the injected `AppSafetyEvents.current`, while the deferred swatch handler still read `NSApp.currentEvent`. The harness now gives both paths the same isolated event. The stronger assertion initiates the choice with Shift, replaces the current event before dispatch, and requires background Yellow with stroke Blue preserved. Product sources are unchanged by these test/harness corrections. These failed runs are superseded and are not final acceptance evidence.

## Final local integration and gallery QA

Main was fast-forwarded from `57ec7995291104f40870e49fffe0ffe8c4b3efbd` to docs head `436b9eb5070f59a579cdc629d6dee08ebfdd129d` (tree `ec2b9fed597c3d25e44758525e792d26948528e2`). Sources, tests, tools, Resources and Info.plist are identical to tested `21b8d68e10543b097cb6a902103e9c56eeb76be5`; the intervening commit is docs only. A cold `sh tools/build.sh` on main passed. Every built source and Info.plist hash matches the current file; the app is `build/OpenSnap.app`, arm64, macOS 26.0 minimum. It was not launched in place, installed, pushed or tagged. See [build identity](../evidence/glass-pickers-2026-10-10/verification/21b8d68/main-integration.json).

The older packer omitted `glassPanel` and display/source-reference metadata, so its first packed glass/accessibility checks failed despite the raw passes. Root restored the exact omitted raw capture records and re-ran the strict checker: glass 206/0 failures/0 advisories/6 contrast skips; core 180/0/0/14 skips; injected accessibility 62/0/0. The failed pre-restoration logs remain labelled in each pack. Icon metadata is corrected to no Pro / embedded FA Free before SF. No product changes were made for packing.

The final gallery has 24 Before and 46 After views. T3 headless runtime checks passed at 728px/light and 360px/dark for all filters, empty-state isolation, favorites, two-image comparison/removal and stored-pixel mode. Both measured a readable CSS minimum of 18px, zero undersized text and no horizontal overflow. [Gallery QA](../evidence/glass-pickers-2026-10-10/gallery-runtime.json) preserves the outcomes. The GUI lock was released with its owner checked after all guarded native processes exited. Physical pointer/hover and VoiceOver speech remain manual limits; no blanket E2E completion is claimed.
