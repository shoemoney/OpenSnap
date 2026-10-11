# Root external accessibility review

Source: `03d267b933566114dad26e765f7fc306b553e2f4`, tree `e3e8d943ef748ae53411988c8a0d9371c467cf83`. The app build manifest was compared against every current source file and Info.plist before launch.

`summary.json` records the asserted outcomes. `actions.json` records raw external action results. The client walks only the isolated app's windows. `known-toolbar-command.swift` separately locates and activates the known command in the app-owned Window menu; it reads no other menu branch or recent-file content.

The isolated session used synthetic History entries and fake-host destinations. Global shortcuts were disabled before changing bindings. No uploads, trash operations, copied secrets or physical HID were used. `stop.txt` proves cleanup-before-compare, unchanged real stores and zero watchdog kills.

Dumps 47–50 record an unsuccessful driver attempt to route Option-Command-T; they are not proof of the shortcut. Dumps 51–53 record the actual command activation, toolbar focus restoration and continued Tab navigation. For a keyboard-opened picker, dump 32 verifies focus returning to its opener. A direct AXShowMenu without focusing the opener restores the prior responder instead (dump 18).

Arrows in the Resize group move from the selected choice: Resize → Crop → Resize → Crop in dump 42. The selected Crop row retains focus. Return from a focused but unchosen Crop row closes the Resize sheet through OK (dumps 45–46); Escape cancels it (dump 43).

These are external AX and targeted window/responder events in the running app. They do not establish physical pointer hover, hardware capture, VoiceOver speech or live provider behavior.

The final harness source `21b8d68e10543b097cb6a902103e9c56eeb76be5` has identical Sources, tests, Resources and Info.plist subtrees to this review source. Only `tools/test-app-safety.sh` changed to route the injected current event into the deferred swatch handler. This proof remains attributed to its actual review SHA.
