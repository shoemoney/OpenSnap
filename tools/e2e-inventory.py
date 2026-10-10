#!/usr/bin/env python3
"""Builds docs/design/e2e/inventory.json (and the coverage-matrix skeleton) for the complete end-to-end audit.

Two sources are merged:
  (a) the running app's own structure: pass --harness DIR, an output folder of `sh tools/eye-dump-audit.sh DIR ...` (its meta/*.json
      name every rendered surface, its ax/*.json list every control the app exposed). Controls the harness saw that no inventory
      entry accounts for are added as E2E-HARN entries, so the source tables below can never silently miss something that renders.
  (b) the sources: FAIcon cases, MenuSymbols, the menu-bar and Toolbox menus (parsed from Sources/App.swift), and curated tables
      for everything the harness does not enumerate (Settings, History, destinations, sheets, alerts, shortcuts, states).
Audit IDs are stable: a regenerate reuses the ID of every entry already in inventory.json (keyed by area, surface, name and type)
and only appends new numbers. `proof` names an existing test; each proof is verified to exist in tests/ at generation time.

  python3 -I tools/e2e-inventory.py [--harness DIR] [--check]
--check regenerates in memory and fails when inventory.json or the matrix would change (used by the guard in tools/test.py).
"""
from pathlib import Path
import argparse
import collections
import json
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources"
OUT_DIR = ROOT / "docs/design/e2e"
INVENTORY = OUT_DIR / "inventory.json"
MATRIX = OUT_DIR / "coverage-matrix.md"

# Why an entry cannot be fully exercised by real-click E2E in an isolated session.
GAPS = {
    "screen-recording": "needs Screen Recording permission (the throwaway bundle id has none; only the refusal path is reachable)",
    "photos-library": "needs the Photos library (privacy-gated; not available to a throwaway identity)",
    "os-panel": "OS-owned panel content (open/save/print/colour/font/share panels): the command and the app-owned parts can be driven, the panel itself is not ours to judge",
    "display-hardware": "needs multi-display or 1x hardware",
    "voiceover": "needs real VoiceOver speech (AX data is not proof of speech)",
    "global-hotkey-background": "global hotkeys firing while the app is in the background need system-level key events",
    "printer": "needs a real printer",
    "replaced": "retired: replaced by Settings › Upload in audit batch 5 (one destinations surface); kept only so the audit IDs and their evidence stay stable",
    "removed": "retired: removed in d9ed8b7 (one capture-shortcut surface, Settings › Capture); kept only so the audit IDs and their evidence stay stable",
    "system-setting": "a system appearance or display option cannot be changed in an E2E session (no global accessibility/appearance changes); only harness-injected rendered evidence exists",
}
RETIRED_GAPS = ("replaced", "removed")   # a row whose surface no longer exists: evidence class `retired`, whatever its historic evidence was
EXERCISE = ("e2e", "e2e-partial", "gap")   # e2e-partial: the app-owned part is real-click, the named gap is the rest
TYPES = ("menu item", "toolbar button", "control", "icon", "preference", "popover", "sheet", "window", "alert", "shortcut", "state", "gesture")
AREAS = {
    "MENU": "Menu bar", "TOOLBOX": "Toolbox pop-up", "STAT": "Status item", "BAR": "Editor chrome (top and bottom bars)",
    "TOOL": "Tools and drawing options", "CANVAS": "Canvas interactions", "CAP": "Capture", "SET": "Settings window",
    "HOT": "Capture shortcuts (global hotkeys)", "HIST": "History window", "DEST": "Destinations and upload",
    "SHEET": "Sheets, panels and secondary windows", "ALERT": "Alerts", "ICON": "Icons", "KEY": "Keyboard shortcuts and modifiers",
    "STATE": "Window, display and appearance states", "A11Y": "Accessibility", "HARN": "Seen by the harness, not accounted for by a source table",
}

entries = []


def add(area, surface, name, kind, path, expected, prereq="Fresh launch, empty document", icon=None, ex="e2e", gap=None, owner="app",
        note=None, proof=None, shortcut=None, rendered=None, src="source"):
    assert area in AREAS and kind in TYPES and ex in EXERCISE and owner in ("app", "os"), (area, name, kind, ex, owner)
    assert (ex == "e2e") == (gap is None), f"{name}: gap reason iff not fully e2e"
    assert gap is None or gap in GAPS, gap
    entries.append(dict(area=area, surface=surface, name=name, type=kind, icon=icon, entryPath=path, prerequisite=prereq, expected=expected, owner=owner,
                        exercise=ex, gap=gap, note=note, shortcut=shortcut, proof=proof or [], rendered=rendered or [], sources=[src]))


# ------------------------------------------------------------------------------------------------------------------ source parsing
def read(name):
    return (SRC / name).read_text()


def parse_faicons():
    text = read("FontAwesomeIcons.swift")
    block = re.search(r"enum FAIcon: String, CaseIterable, Sendable \{\n(.*?)\n\n    var codepoint", text, re.S).group(1)
    cases = []
    for item in re.split(r",\s*", block.replace("case ", "").replace("\n", " ").strip()):
        item = item.strip()
        if not item:
            continue
        m = re.fullmatch(r'(\w+)(?: = "([^"]+)")?', item)
        cases.append((m.group(1), m.group(2) or m.group(1)))
    codepoints = dict(re.findall(r"case \.(\w+): return (0x[0-9A-Fa-f]+)", text))
    sf = dict(re.findall(r'case \.(\w+): return "([^"]+)"', text[text.index("var sfSymbolFallback"):]))
    return [(case, fa, codepoints[case], sf[case]) for case, fa in cases]


def icon_users(case):
    """Source files (other than the icon tables) that name the case, e.g. `.eyeSlash`."""
    users = []
    for path in sorted(SRC.glob("*.swift")):
        if path.name in ("FontAwesomeIcons.swift", "FontAwesomeFree.swift", "ChromeIcons.swift"):
            continue
        if re.search(rf"[\s\[(,:]\.{case}\b", path.read_text()):
            users.append(path.name)
    return users


def parse_menu_symbols():
    text = read("MenuSymbols.swift")
    body = text[text.index("Dictionary(uniqueKeysWithValues: ["):text.index("].map")]
    return re.findall(r'\("([A-Za-z0-9]+)", "([^"]+)"\)', body)


def parse_menus():
    """(menu title, item title, selector or None, key) in menu-bar order, from the menu(...) calls in buildMenus."""
    text = read("App.swift")
    body = text[text.index("    func buildMenus() {"):text.index("    @objc func changeSmoothing")]
    found = []
    for call in re.finditer(r'(?:let|var) (\w+) = menu\(("[^"]+"|name), items: \[(.*?)\]\)', body, re.S):
        title = "OpenSnap" if call.group(2) == "name" else call.group(2).strip('"')
        for item in re.finditer(r'\("([^"]*)"( \+ name)?, (nil|#selector\((\w+)[^)]*\)\)?), "([^"]*)"\)', call.group(3)):
            name = item.group(1) + ("OpenSnap" if item.group(2) else "")
            if name == "-" or item.group(4) == "NSApplication":   # system selectors are listed in SYSTEM_MENU
                continue
            # The Edit item is retitled live by the wipe stage (Remove Annotations first, Clear Image once only the picture is left).
            if item.group(4) == "wipe":
                name = "Remove Annotations / Clear Image"
            found.append((title, name, item.group(4), item.group(5)))
    return found


def parse_toolbox_groups():
    text = read("App.swift")
    block = text[text.index("static let toolboxGroups: [[Selector]] = ["):text.index("func bezelToolbox()")]
    return [re.findall(r"#selector\((\w+)", line) for line in block.splitlines()[1:] if "#selector" in line]


def shortcut_text(key, extra=""):
    if not key:
        return None
    mods = extra + ("⇧" if key != key.lower() else "") + "⌘"
    return mods + (key.upper() if key.isalpha() else key)


def verify_proofs():
    corpus = "\n".join(p.read_text() for p in (ROOT / "tests").glob("*.swift"))
    for entry in entries:
        for proof in entry["proof"]:
            if proof["file"] not in {p.name for p in (ROOT / "tests").glob("*.swift")} or proof["test"] not in (ROOT / "tests" / proof["file"]).read_text():
                raise SystemExit(f"proof not found: {proof} (entry {entry['name']})")
    return corpus


def proof(file, test):
    assert test.strip(), "a proof must name a real test message"
    return [{"file": file, "test": test}]


# --------------------------------------------------------------------------------------------------------------- menu semantics
# selector -> (prerequisite, expected, exercise, gap, owner). Every parsed menu selector must be classified here, so a new menu
# item fails generation until somebody decides how it is audited.
D = "Fresh launch, empty document"
SEM = {
    "about": (D, "About window opens: name, version, credit, MIT License and Third-party notices links", "e2e", None, "app"),
    "showPreferences": ("No sheet attached, not mid Frame capture", "Settings window opens on its last tab", "e2e", None, "app"),
    "sharingSettings": (D, "Settings opens on the Upload tab, where the destinations are listed and edited", "e2e", None, "app"),
    "shortcutSettings": (D, "Settings opens on the Capture tab (the Capture Shortcuts sheet was removed in d9ed8b7)", "e2e", None, "app"),
    "quit": ("Clean document; repeat with a dirty document", "App quits; a dirty document asks Save your drawing? first", "e2e", None, "app"),
    "toggleVisible": (D, "Editor hides; status item (if shown) reads Show OpenSnap", "e2e", None, "app"),
    "newFile": ("Dirty document for the confirm path", "Blank 800 x 600 canvas titled Untitled; dirty document asks Save your drawing? first", "e2e", None, "app"),
    "openFile": (D, "Open panel appears; choosing a synthetic .opensnap or picture loads it", "e2e-partial", "os-panel", "app"),
    "showPhotos": (D, "Photos sheet opens with the Pictures / image folder chooser", "e2e", None, "app"),
    "closeCurrentWindow": ("Settings, History or the editor frontmost", "Closes the front window; a dirty editor asks to save", "e2e", None, "app"),
    "saveFile": ("Untitled document, then a saved one", "Untitled: Save panel; saved: writes the .opensnap in place and clears the edited dot", "e2e-partial", "os-panel", "app"),
    "saveAs": ("Any document", "Save panel with .opensnap type; saving renames the document", "e2e-partial", "os-panel", "app"),
    "renameDocument": ("No sheet attached", "Rename sheet (Document name); OK changes the window title, Cancel leaves it", "e2e", None, "app"),
    "saveHistory": ("A drawing on the canvas", "Archived into History; status line confirms; the entry appears in the History window", "e2e", None, "app"),
    "showHistory": (D, "History window opens (1000 x 720, minimum 880 x 600)", "e2e", None, "app"),
    "exportFile": ("A drawing on the canvas", "Save panel with the Export options accessory (format, JPEG quality, original size, dimensions, bytes)", "e2e-partial", "os-panel", "app"),
    "publishImage": ("A drawing; a default destination (seeded) or none", "Uploads to the default destination and copies the link; with none, says so in the status line and opens Settings › Upload (empty list with Add… inside)", "e2e", None, "app"),
    "shareFromMenu": ("A drawing on the canvas", "The macOS sharing picker opens for the image", "e2e-partial", "os-panel", "app"),
    "printImage": ("A drawing on the canvas", "System print panel for the rendered image", "gap", "printer", "os"),
    "pageSetup": (D, "System Page Setup panel; OK keeps the settings", "e2e-partial", "os-panel", "app"),
    "undo": ("At least one edit", "Reverts the last edit; item disabled with no undoable edit", "e2e", None, "app"),
    "redo": ("After an undo", "Re-applies the undone edit; disabled with nothing to redo", "e2e", None, "app"),
    "cut": ("A selected element", "Removes it and puts it on the pasteboard", "e2e", None, "app"),
    "copyArtwork": ("A selected element, or nothing selected", "Copies the selection, or the whole artwork when nothing is selected", "e2e", None, "app"),
    "copyImage": ("A drawing on the canvas", "Copies the rendered image to the pasteboard", "e2e", None, "app"),
    "paste": ("Copied artwork or image on the pasteboard", "Pastes into the canvas and selects it", "e2e", None, "app"),
    "deleteSelection": ("A selected element", "Deletes the selection", "e2e", None, "app"),
    "selectAll": ("Elements on the canvas", "Selects every element", "e2e", None, "app"),
    "duplicate": ("A selected element", "Duplicates the selection offset from the original", "e2e", None, "app"),
    "wipe": ("A drawing with annotations", "First use clears the drawing; a second use erases the background (per the hint text)", "e2e", None, "app"),
    "wipeSnap": ("A drawing with a background picture", "Removes only the snap picture, keeps annotations", "e2e", None, "app"),
    "clear": ("A drawing with annotations", "Clears annotations, keeps the snap picture", "e2e", None, "app"),
    "toggleActualSize": ("A picture larger than the window", "Toggles Actual Size; checkmark and navigator appear; Resize disables", "e2e", None, "app"),
    "resize": ("Not in Actual Size or Frame mode", "Resize or Crop sheet opens", "e2e", None, "app"),
    "crop": ("A crop selection from the Crop tool", "Crops the canvas to the selection", "e2e", None, "app"),
    "trimSnap": ("A snap picture on the canvas", "Crops the snap at the current canvas edges", "e2e", None, "app"),
    "normalSize": ("A snap picture that was scaled", "Sets the snap back to normal (1x) size", "e2e", None, "app"),
    "rotateCW": ("A drawing", "Rotates the artwork 90 degrees clockwise", "e2e", None, "app"),
    "rotateCCW": ("A drawing", "Rotates the artwork 90 degrees counterclockwise", "e2e", None, "app"),
    "flipH": ("A drawing", "Flips the artwork horizontally", "e2e", None, "app"),
    "flipV": ("A drawing", "Flips the artwork vertically", "e2e", None, "app"),
    "transparent": ("A drawing", "Canvas background becomes transparent (checkerboard)", "e2e", None, "app"),
    "white": ("A drawing", "Canvas background becomes white", "e2e", None, "app"),
    "flatten": ("Several elements", "Merges annotations into the background picture", "e2e", None, "app"),
    "addShadow": ("A drawing", "Adds a drop shadow around the artwork", "e2e", None, "app"),
    "front": ("A selected element", "Brings it to the front of the stack", "e2e", None, "app"),
    "back": ("A selected element", "Sends it to the back of the stack", "e2e", None, "app"),
    "group": ("Two or more selected elements", "Groups them so they move together", "e2e", None, "app"),
    "ungroup": ("A selected group", "Splits the group", "e2e", None, "app"),
    "chooseFont": ("None, or a selected text element", "Toggles the Font panel with the app's Text outline / shadow / Default Text Style accessory; checkmark while open", "e2e-partial", "os-panel", "app"),
    "defaultTextStyle": ("A changed text style", "Resets text style to the default", "e2e", None, "app"),
    "toggleOutline": ("Text tool or selected text", "Toggles the text outline", "e2e", None, "app"),
    "toggleTextShadow": ("Text tool or selected text", "Toggles the text shadow", "e2e", None, "app"),
    "screenSnap": ("Screen Recording not granted (refusal path)", "Crosshair picker; without the permission the Screen Recording sheet appears instead", "e2e-partial", "screen-recording", "app"),
    "fullscreenSnap": ("Screen Recording not granted (refusal path)", "Full-screen capture; without the permission the Screen Recording sheet appears", "e2e-partial", "screen-recording", "app"),
    "windowSnap": ("Screen Recording not granted (refusal path)", "Window picker; without the permission the Screen Recording sheet appears", "e2e-partial", "screen-recording", "app"),
    "frameSnap": (D, "Frame mode begins: Snap becomes Snap Frame, Cancel appears, the canvas well opens a hole", "e2e-partial", "screen-recording", "app"),
    "resnap": ("A previous snap", "Re-captures keeping the pen settings; refusal path without permission", "e2e-partial", "screen-recording", "app"),
    "cancelFrame": ("In Frame mode", "Leaves Frame mode and restores the solid canvas well", "e2e", None, "app"),
    "timedSnap": (D, "Timed Snapshot sheet (Delay in seconds, default 6); valid delay starts the countdown", "e2e-partial", "screen-recording", "app"),
    "cancelSnapshot": ("A capture in progress", "Cancels the running capture; disabled when idle", "e2e", None, "app"),
    "webSnap": ("A reachable http(s) page (local server)", "Snap from Link sheet (Web address); a valid address loads and captures the page", "e2e", None, "app"),
    "toggleBezelFill": (D, "Toggles Filled Shapes; checkmark follows", "e2e", None, "app"),
    "toggleBezelShadow": (D, "Toggles Shadow for shapes; checkmark follows", "e2e", None, "app"),
    "vanish": (D, "Minimizes the editor to the Dock", "e2e", None, "app"),
    "toggleFullScreen": (D, "Enters or leaves full screen; the title reads Enter Full Screen or Exit Full Screen and follows the window; disabled in Frame mode", "e2e", None, "app"),
}
SYSTEM_MENU = {  # items wired to system selectors or added after the menu(...) calls
    ("OpenSnap", "Hide Others", "⌥⌘H", "Other apps hide", "os"),
    ("OpenSnap", "Show All", None, "Hidden apps reappear", "os"),
    ("Window", "Bring All to Front", None, "App windows move in front", "os"),
}
EXTRA_MENU = [  # inserted by buildMenus after the generic menu(...) calls
    ("OpenSnap", "Hide OpenSnap", "toggleVisible", "h"), ("File", "Close", "closeCurrentWindow", "w"), ("File", "Page Setup…", "pageSetup", "P"),
    ("File", "Rename…", "renameDocument", ""), ("Window", "Minimize", "vanish", "m"),
    ("Window", "Enter Full Screen", "toggleFullScreen", "f"),
]
SUBMENUS = [  # (menu, submenu, items, selector for validation/semantics, expected)
    ("Drawing", "Pencil Smoothing", ["Precise", "Medium", "Loose"], "Sets pencil smoothing; checkmark follows; mirrors Settings > Drawing > Drawing precision"),
    ("Drawing", "Arrow Head", ["At Start", "At End"], "Sets arrow head placement; checkmark follows; mirrors Settings > Drawing > Arrow head"),
    ("Text", "Spelling", ["Spelling…", "Check Spelling", "Check Spelling as You Type"], "System spelling commands routed to the text responder"),
]


def build_menus():
    parsed = parse_menus()
    symbols = dict(parse_menu_symbols())
    known = {sel for _, _, sel, _ in parsed if sel}
    missing = sorted(known - set(SEM))
    assert not missing, f"menu selectors with no audit classification in SEM: {missing}"
    rows = [(m, n, s, k) for m, n, s, k in parsed] + [(m, n, s, k) for m, n, s, k in EXTRA_MENU]
    seen = set()
    for menu, name, selector, key in rows:
        if (menu, name) in seen:
            continue
        seen.add((menu, name))
        prereq, expected, ex, gap, owner = SEM[selector]
        add("MENU", f"Menu bar › {menu}", name, "menu item", f"Menu bar › {menu} › {name}", expected, prereq=prereq, icon=symbols.get(selector),
            ex=ex, gap=gap, owner=owner, shortcut=shortcut_text(key, "⌥" if name == "Hide Others" else ("⌃" if name == "Enter Full Screen" else "")), rendered=["S12", "S16", "S17"],
            note=None if ex == "e2e" else f"Selector {selector}")
    for menu, name, key, expected, owner in sorted(SYSTEM_MENU):
        add("MENU", f"Menu bar › {menu}", name, "menu item", f"Menu bar › {menu} › {name}", expected, prereq="Other apps running" if name != "Bring All to Front" else D,
            ex="e2e", owner="os", shortcut=key, note="System selector routed through the responder chain")
    for menu, sub, items, expected in SUBMENUS:
        add("MENU", f"Menu bar › {menu}", sub, "menu item", f"Menu bar › {menu} › {sub}", f"Opens the {sub} submenu ({', '.join(items)})")
        for item in items:
            shortcut = {"Spelling…": "⌘:", "Check Spelling": "⌘;"}.get(item)
            add("MENU", f"Menu bar › {menu} › {sub}", item, "menu item", f"Menu bar › {menu} › {sub} › {item}", expected,
                prereq="A text field or annotation editor is first responder" if sub == "Spelling" else D, ex="e2e-partial" if item == "Spelling…" else "e2e",
                gap="os-panel" if item == "Spelling…" else None, owner="os" if sub == "Spelling" else "app", shortcut=shortcut,)
    for menu in ("OpenSnap", "File", "Edit", "Image", "Drawing", "Text", "Capture", "Window"):
        add("MENU", "Menu bar", menu, "menu item", f"Menu bar › {menu}", f"Every item in the {menu} menu renders at body size (20 pt)",
            rendered=["S12", "S16"], proof=proof("AppSafetyMenuCases.swift", "Every app-owned dropdown renders at body size: main, Toolbox, zoom, upload and status menus"))
    return parsed


def build_toolbox(parsed):
    titles = {sel: name for _, name, sel, _ in parsed if sel}
    titles.update({"toggleVisible": "Hide OpenSnap"})
    symbols = dict(parse_menu_symbols())
    add("TOOLBOX", "Toolbar › Toolbox", "Toolbox", "toolbar button", "Top bar › Toolbox (icon and chevron)", "Menu opens (a selection-style pop-up, because a pull-down draws no row icons): five groups of drawing-session commands (keep, edit, capture, adjust the picture, pen settings); no app or file plumbing",
        icon="toolbox", rendered=["S04", "S12"])
    for index, group in enumerate(parse_toolbox_groups(), start=1):
        for selector in group:
            name = titles.get(selector, selector)
            add("TOOLBOX", f"Toolbar › Toolbox › group {index}", name, "menu item", f"Top bar › Toolbox › {name}",
                f"Runs the same command as the menu-bar item {name} (the Toolbox row is a copy: title, key and symbol match)", icon=symbols.get(selector),
                prereq=SEM.get(selector, (D,))[0], ex=SEM[selector][2] if selector in SEM else "e2e", gap=SEM[selector][3] if selector in SEM else None,
                owner=SEM[selector][4] if selector in SEM else "app", rendered=["S12"],
                proof=proof("AppSafetyMenuCases.swift", "Toolbox rows are copies of main-menu rows: subset by action, same titles"))


# ------------------------------------------------------------------------------------------------------------------- icons
FA_WHERE = {  # entry path for each icon, kept beside the source-derived "used in" list
    "eyeSlash": "Top bar › Hide", "folderMinus": "History › Hide (list-only removal)", "chevronDown": "Top bar › Toolbox (face)", "toolbox": "Top bar › Toolbox", "images": "Top bar › Photos", "boxArchive": "Bottom bar › Save",
    "clockRotateLeft": "Bottom bar › History", "arrowPointer": "Top bar › Select tool", "paintbrush": "Top bar › Brush tool; Settings › Drawing tab",
    "slashForward": "Top bar › Line tool", "circle": "Top bar › Ellipse tool", "square": "Top bar › Rectangle tool", "fillDrip": "Top bar › Fill tool",
    "eraser": "Top bar › Eraser tool", "text": "Top bar › Text tool", "arrowUpRight": "Top bar › Arrow tool", "cropSimple": "Top bar › Crop tool",
    "crosshairs": "Top bar › Snap; Settings › Capture tab", "frameViewfinder": "Top bar › Snap Frame (Frame mode)", "xmark": "Top bar › Cancel (Frame mode)",
    "font": "Top bar › Font", "arrowRotateLeft": "Bottom bar › Undo", "broom": "Bottom bar › Wipe",
    "upload": "Bottom bar › Upload; Settings › Upload tab", "dragHand": "Bottom bar › Drag Me", "check": "Default pill; success results",
    "xmarkCircle": "Failure results", "openExternal": "History › Open", "copy": "History › Copy", "link": "History › Copy Link",
    "globe": "History › Open Link", "trash": "History › Move to Trash", "linkSlash": "History › Delete from Web", "circleCheck": "Connected result; selected tile badge",
    "gear": "Settings › General tab",
}


def build_icons():
    for case, fa, codepoint, sf in parse_faicons():
        users = icon_users(case)
        add("ICON", "FAIcon", f"{fa}", "icon", FA_WHERE.get(case, "see source"),
            f"Renders as a Font Awesome glyph ({codepoint}) in release builds, or SF Symbol {sf} when no glyph resolves; centred, template-tinted, matches its meaning",
            prereq="Control visible", icon=fa, note=f"case .{case}; Free codepoint {codepoint}; SF fallback {sf}; used in {', '.join(users) or 'icon tables only'}",
            rendered=["S03", "S04"])
    seen = set()
    for selector, symbol in parse_menu_symbols():
        if (selector, symbol) in seen:
            continue
        seen.add((selector, symbol))
        add("ICON", "Menu leading symbol", symbol, "icon", f"Menu bar / Toolbox row for {selector}",
            f"Leading SF Symbol {symbol} sits left of the {selector} item title, template-tinted, 20 pt row", prereq="Menu open", icon=symbol,
            note=f"selector {selector}", rendered=["S12", "S16"], proof=proof("MenuSymbolsTests.swift", "maps to") + proof("AppSafetyMenuCases.swift", "Every menu and Toolbox row has an SF symbol or a named exemption"))
    add("ICON", "Status item", "camera.viewfinder", "icon", "System menu bar › OpenSnap status item", "Template symbol, tinted by the menu bar, tooltip and VoiceOver label OpenSnap",
        icon="camera.viewfinder", prereq="Show in: Menu bar or Both", rendered=["S17"])
    add("ICON", "Bottom bar", "icloud.and.arrow.up", "icon", "Bottom bar › Upload", "Upload glyph (SF fallback uploadSymbolName) when Font Awesome does not resolve",
        icon="icloud.and.arrow.up", rendered=["S03"])
    add("ICON", "App icon", "OpenSnap.icon", "icon", "Dock / Finder / About window", "Liquid Glass app icon (Assets.car) with flattened icns fallback; per-rendition previews via ictool",
        prereq="Built bundle", icon="OpenSnap.icon", note="see memory note icon-composer-ictool for the headless per-rendition previews")


# --------------------------------------------------------------------------------------------------------------------- chrome
def build_chrome():
    top = [
        ("Hide", "Hide the editor (⌘M behaviour via vanish)", "eyeSlash", "Editor minimizes; tooltip Hide (⌘M)"),
        ("Toolbox", "Common commands menu", "toolbox", "Menu opens, rows with icons (see Toolbox entries)"),
        ("Photos", "Open the Photos sheet", "images", "Photos sheet opens"),
        ("Snap", "Primary capture control", "crosshairs", "Starts a crosshair snap (right-click or Control-click for Fullscreen); refusal sheet without Screen Recording"),
    ]
    for name, what, icon, expected in top:
        add("BAR", "Top bar", name, "toolbar button" if name != "Toolbox" else "control", f"Top bar › {name}", expected, icon=icon, rendered=["S03", "S04"],
            ex="e2e-partial" if name == "Snap" else "e2e", gap="screen-recording" if name == "Snap" else None)
    add("BAR", "Top bar", "Snap (right-click / Control-click)", "gesture", "Top bar › Snap, right-click or Control-click", "Fullscreen capture; refusal sheet without Screen Recording",
        icon="crosshairs", ex="e2e-partial", gap="screen-recording")
    add("BAR", "Top bar", "Cancel (Frame mode)", "toolbar button", "Frame mode › top bar › Cancel", "Leaves Frame mode; the Cancel button disappears", icon="xmark",
        prereq="Frame mode entered via Capture › Frame Snapshot", rendered=["S32", "S33"])
    add("BAR", "Top bar", "Snap Frame", "toolbar button", "Frame mode › top bar › Snap Frame", "Captures inside the Frame (Shift: six-second timer); refusal sheet without Screen Recording",
        icon="camera-viewfinder", prereq="Frame mode", ex="e2e-partial", gap="screen-recording", rendered=["S32", "S33"])
    add("BAR", "Top bar", "Color", "toolbar button", "Top bar › Color swatch", "Drawing colors popover opens (see TOOL)", rendered=["S06"])
    add("BAR", "Top bar", "Size", "control", "Top bar › Size slider", "Slider changes stroke size 1-… ; tooltip and accessibilityValue carry Size N; undo groups one drag", rendered=["S06"])
    add("BAR", "Top bar", "Font", "toolbar button", "Top bar › Font", "Toggles the Font panel", icon="font", ex="e2e-partial", gap="os-panel", rendered=["S06"])
    for tool, label in [("select", "Select"), ("brush", "Brush"), ("line", "Line"), ("ellipse", "Ellipse"), ("rectangle", "Rectangle"), ("fill", "Fill"),
                        ("eraser", "Eraser"), ("text", "Text"), ("arrow", "Arrow"), ("crop", "Crop")]:
        add("BAR", "Top bar › tools", f"{label} tool", "toolbar button", f"Top bar › {label}", f"{label} becomes the selected tool: accent border, tooltip says (selected), status line names it",
            icon={"select": "arrow-pointer", "brush": "paintbrush", "line": "slash-forward", "ellipse": "circle", "rectangle": "square", "fill": "fill-drip",
                  "eraser": "eraser", "text": "text", "arrow": "arrow-up-right", "crop": "crop-simple"}[tool], rendered=["S04"])
    bottom = [
        ("Undo", "toolbar button", "arrow-rotate-left", "Reverts the last edit; disabled with nothing to undo", "S09"),
        ("Wipe", "toolbar button", "broom", "First click clears the drawing; a second erases the background; disabled when empty", "S09"),
        ("Canvas zoom", "control", None, "Pop-up: 25, 50, 75, 100, 150, 200 %, Actual Size; face shows the percentage; Fit adds a computed entry", "S07"),
        ("Resize…", "toolbar button", None, "Text button (20 pt, no glyph); Resize or Crop sheet opens at the size the title shows; disabled in Actual Size and Frame mode", "S08"),
        ("Status line", "control", None, "Names the tool, saved state and size; truncates in the middle only at the minimum width", "S09"),
        ("Save", "toolbar button", "box-archive", "Saves to History (tooltip Save to History); status confirms", "S09"),
        ("History", "toolbar button", "clock-rotate-left", "Opens the History window", "S09"),
        ("Image format (PNG | JPG)", "control", None, "Two-segment capsule; choice persists and drives drag, export and upload format", "S09"),
        ("Drag image to another app", "control", "hand", "The Drag Me well (accessibility label Drag image to another app): drag the drawing to Finder or another app; the file is frozen at drag start", "S09"),
        ("Original size", "control", None, "Checkbox: drag out at original size; stored as DragOriginalSize", "S09"),
        ("Upload", "toolbar button", "cloud-arrow-up", "Left-click uploads to the default destination and copies the link; right-click or Control-click opens the destination menu", "S09"),
    ]
    for name, kind, icon, expected, surface in bottom:
        add("BAR", "Bottom bar", name, kind, f"Bottom bar › {name}", expected, icon=icon, rendered=[surface, "S03"],
            prereq="A drawing on the canvas" if name in ("Undo", "Wipe", "Save") else D)
    for name, expected in [("Zoom entry 25%", "Canvas shows at 25%"), ("Zoom entry 50%", "50%"), ("Zoom entry 75%", "75%"), ("Zoom entry 100%", "100%"),
                           ("Zoom entry 150%", "150%"), ("Zoom entry 200%", "200%"), ("Zoom entry Actual Size", "Toggles Actual Size (same as Image › Actual Size)")]:
        add("BAR", "Bottom bar › zoom pop-up", name, "menu item", f"Bottom bar › Canvas zoom › {name.replace('Zoom entry ', '')}", expected + "; face updates", rendered=["S07"])
    for name, expected in [("Cancel Upload", "Cancels a running upload; shown only while publishing"), ("Destination row", "Chooses the default destination; checkmark moves"),
                           ("No destination configured", "Disabled row shown when no destination exists"), ("Destination Settings…", "Opens Settings on the Upload tab"),
                           ("Share with macOS…", "Opens the macOS sharing picker (OS-owned)")]:
        add("BAR", "Bottom bar › Upload menu", name, "menu item", f"Bottom bar › Upload (right-click) › {name}", expected,
            prereq="Destinations seeded" if name == "Destination row" else D, ex="e2e-partial" if name.startswith("Share") else "e2e", gap="os-panel" if name.startswith("Share") else None,
            owner="os" if name.startswith("Share") else "app", rendered=["S21", "S09"])
    add("BAR", "Bottom bar", "Blank (the Wipe button's accessible name on an empty canvas)", "state", "Bottom bar › Wipe with an empty document",
        "The control beside Undo is named Blank and disabled on an empty canvas; becomes Wipe once there is something to clear (audit the name: a user hears 'Blank')",
        icon="broom", rendered=["S01", "S11"])
    add("BAR", "Top bar", "Size slider value labels (Size 2, Size 4, Size 7, Size 9, Size 12)", "state", "Top bar › Size slider",
        "The slider's help and tooltip read Size N for the current value; the visible face stays icon-only", rendered=["S06", "S30"])
    add("BAR", "Bottom bar", "Canvas zoom spoken labels (Output, 100% / Actual, 100% / Fit, 83%)", "state", "Bottom bar › Canvas zoom",
        "The face shows the percentage alone; the mode word (Output, Actual, Fit) rides on the tooltip and the spoken value", rendered=["S02", "S07", "S38"])
    add("BAR", "Canvas well", "Canvas scroll area", "control", "Centre of the window", "Centred solid well; scrollers autohide; reachable when the canvas is larger than the window", rendered=["S07", "S11"])
    add("BAR", "Canvas well", "Canvas border handles", "gesture", "Canvas edge handles (drag)", "Dragging a handle previews then resizes the window/canvas gesture; Shift keeps proportions", rendered=["S11"],
)
    add("BAR", "Canvas well", "Navigator (Actual Size)", "control", "Actual Size mode › navigator thumbnail", "Click or drag moves the viewport; updates the scroller position", prereq="Actual Size on a large picture", rendered=["S07"])
    add("BAR", "Window", "Document title / edited dot", "state", "Window titlebar", "Untitled – W × H · size; edited dot after a change; renamed by Rename…", rendered=["S01", "S02"])
    add("BAR", "Window", "Traffic lights (close, minimize, zoom)", "control", "Window titlebar", "Close prompts when dirty; minimize docks; zoom toggles the maximised size", owner="os", rendered=["S11"])


def build_tools():
    for name, expected, prereq in [
            ("Select: click and drag a marquee", "Selects elements; handles appear (move, resize, rotate)", "Elements on canvas"),
            ("Brush: drag", "Freehand stroke with the current colour and size, smoothed per Settings", D),
            ("Line: drag", "Straight line from press to release", D),
            ("Ellipse: drag", "Ellipse in the dragged rectangle; Filled Shapes fills it", D),
            ("Rectangle: drag", "Rectangle in the dragged rectangle; Filled Shapes fills it", D),
            ("Fill: click", "Fills the clicked shape or the background with the colour", "A shape or background"),
            ("Eraser: drag", "Erases elements under the pointer", "Elements on canvas"),
            ("Text: click and type", "Places an annotation editor; Esc or Option-Return finishes; minimum 18 pt text", D),
            ("Arrow: drag", "Arrow from press to release; Option reverses direction, Shift constrains the angle", D),
            ("Crop: drag a region, Return", "Draws a crop selection; Return crops, Esc cancels", D)]:
        add("TOOL", "Tools", name, "gesture", f"Pick the tool, then {name.split(':')[1].strip()} on the canvas", expected, prereq=prereq, rendered=["S05", "S08"])
    colors = ["Red", "Yellow", "Blue", "Pink", "Translucent gray", "Orange", "Green", "White", "Black", "Highlighter"]
    add("TOOL", "Drawing colors popover", "Drawing colors popover", "popover", "Top bar › Color", "Popover with a 5 x 2 grid of preset swatches, Custom color…; transient", rendered=["S06"])
    for color in colors:
        add("TOOL", "Drawing colors popover", f"Preset: {color}", "control", f"Top bar › Color › {color}", f"Sets the drawing colour to {color} (Shift sets the canvas background); swatch updates",
            rendered=["S06"])
    add("TOOL", "Drawing colors popover", "Custom color…", "control", "Top bar › Color › Custom color…", "Closes the popover and opens the system colour panel (alpha enabled); changes apply live", ex="e2e-partial", gap="os-panel", rendered=["S06"])
    add("TOOL", "Drawing options", "Size slider range", "control", "Top bar › Size", "Minimum, middle and maximum sizes are legible; readable text size floor of 18 pt for text", rendered=["S06"])
    add("TOOL", "Drawing options", "Filled Shapes", "preference", "Menu bar › Drawing › Filled Shapes", "Ellipse and Rectangle draw filled; checkmark shows", rendered=["S12"])
    add("TOOL", "Drawing options", "Shadow", "preference", "Menu bar › Drawing › Shadow", "Shapes draw with a shadow; checkmark shows", rendered=["S12"])
    add("TOOL", "Drawing options", "Text outline", "preference", "Font panel accessory › Text outline", "Toggles the outline on selected/new text", ex="e2e-partial", gap="os-panel", rendered=["S06"])
    add("TOOL", "Drawing options", "Text shadow", "preference", "Font panel accessory › Text shadow", "Toggles the shadow on selected/new text", ex="e2e-partial", gap="os-panel", rendered=["S06"])
    add("TOOL", "Drawing options", "Default Text Style (accessory button)", "control", "Font panel accessory › Default Text Style", "Resets the text style", ex="e2e-partial", gap="os-panel", rendered=["S06"])
    add("TOOL", "Drawing options", "Hover hints (tool help bevel)", "state", "Hover a tool or control with Show hover hints / keyboard tips on", "Original hint message shows for the control; native tooltip is suppressed on covered controls",
        rendered=["S04"])


def build_canvas():
    rows = [
        ("Click-drag draws with the selected tool", "gesture", "Element appears; Undo removes it; status updates"),
        ("Double-click or click text to edit", "gesture", "Annotation editor opens in place"),
        ("Right-click inside a text annotation", "gesture", "Context menu with system text items and Text Style…"),
        ("Move selection with Arrow keys", "gesture", "Selection nudges 1 pt (10 pt with Shift) as one undoable Nudge; status updates"),
        ("Delete / Forward Delete", "shortcut", "Deletes the selection"),
        ("Esc", "shortcut", "Finishes text editing, otherwise cancels the operation or crop"),
        ("Return (Crop tool)", "shortcut", "Crops to the selection"),
        ("Option-Return or keypad Enter in a text editor", "shortcut", "Finishes text editing"),
        ("Space (held)", "gesture", "Space-held modifier: the cursor changes while it is down and the drag pans instead of drawing (Canvas.spaceHeld)"),
        ("Tab", "gesture", "Control-Tab switches to the Brush tool and back to the previous tool (pencil toggle); plain Tab moves the keyboard to the next control, and does the pencil toggle only while the bars are not tab stops (Full Keyboard Access off)"),
        ("Pinch / scroll in Actual Size", "gesture", "Scrolls the viewport; the navigator follows"),
        ("Drop a picture or .opensnap onto the window", "gesture", "Accepts file URLs, PNG, TIFF and the native pasteboard type; only pictures, PDFs and .opensnap load, other file types are refused"),
        ("Drag the drawing out via Drag Me", "gesture", "Exports a file in the chosen format; History records Exported/Dragged"),
        ("Drag a History tile to Finder", "gesture", "Promised file in the History drag format"),
    ]
    for name, kind, expected in rows:
        add("CANVAS", "Canvas", name, kind, f"Canvas › {name}", expected, prereq="A drawing on the canvas" if "Drop" not in name else D, rendered=["S05"])


def build_capture():
    add("CAP", "Capture", "Crosshair snapshot (picker overlay)", "state", "Capture › Crosshair Snapshot / Snap", "Crosshair with magnifier and size readout over the display under the mouse; drag selects; Esc cancels",
        prereq="Screen Recording granted", ex="gap", gap="screen-recording", rendered=["S13", "S14"])
    add("CAP", "Capture", "Window snapshot (picker overlay)", "state", "Capture › Window Snapshot", "Hovered window highlights; click captures it", prereq="Screen Recording granted", ex="gap", gap="screen-recording", rendered=["S14"])
    add("CAP", "Capture", "Fullscreen snapshot", "state", "Capture › Fullscreen Snapshot", "Captures the display under the mouse, capture flash plays when enabled", prereq="Screen Recording granted", ex="gap", gap="screen-recording")
    add("CAP", "Capture", "Frame snapshot", "state", "Capture › Frame Snapshot", "Frame hole in the window; Snap Frame captures inside it; Shift resizes proportionally", prereq="Screen Recording granted", ex="e2e-partial", gap="screen-recording", rendered=["S32", "S33"])
    add("CAP", "Capture", "Screen Recording permission sheet", "sheet", "Any capture without permission", "Sheet titled Screen Recording with Settings… and Cancel; Return opens System Settings, Esc cancels",
        rendered=["S15"])
    add("CAP", "Capture", "Timed snapshot countdown overlay", "state", "Capture › Timed Snapshot… › valid delay", "Countdown overlay counts down, then captures", prereq="Screen Recording granted", ex="gap", gap="screen-recording", rendered=["S15"])
    add("CAP", "Capture", "Capture flash", "state", "After a successful capture with Settings › Capture › Show capture flash on", "Brief flash over the captured display", prereq="Screen Recording granted", ex="gap", gap="screen-recording",
)
    add("CAP", "Capture", "Re-snap (keep pen)", "state", "Capture › Re-snap", "Captures again keeping tool and colour", prereq="A previous snap and permission", ex="gap", gap="screen-recording")
    add("CAP", "Capture", "Snap from Link", "state", "Capture › Snap from Link… › address", "Renders the page in an app-owned web view and receives it as the snap", prereq="Reachable http(s) page (local server)")
    add("CAP", "Capture", "Multi-display: snaps cover the display under the mouse", "state", "Capture on a second display", "Capture and overlays use the display under the pointer", ex="gap", gap="display-hardware")
    add("CAP", "Capture", "1x display rendering", "state", "Window on a non-Retina display", "All glyphs and 1 pt borders render crisply at 1x", ex="gap", gap="display-hardware")


# ---------------------------------------------------------------------------------------------------------------------- settings
def build_settings():
    add("SET", "Settings window", "Settings window", "window", "Menu bar › OpenSnap › Settings… (⌘,) or status item › Settings…", "Window with a solid (not glass) 20 pt tab strip (General, Drawing, Capture, Upload), centred forms, remembers the last tab",
        rendered=["S12"], proof=proof("SettingsWindowTests.swift", "the strip is solid, not glass"))
    for index, (tab, icon) in enumerate([("General", "gear"), ("Drawing", "paintbrush"), ("Capture", "crosshairs"), ("Upload", "cloud-arrow-up")], start=1):
        add("SET", "Settings › tab strip", f"{tab} tab", "control", f"Settings › {tab} (or ⌘{index})", f"Shows the {tab} form; selected tab has an accent border and accent icon, not colour alone",
            icon=icon, shortcut=f"⌘{index}", rendered=["S12"])
    rows = [
        ("General", "Show in: Dock", "preference", "Dock only: the app shows in the Dock, no status item", "Menu bar > none; Dock presence changes without restart"),
        ("General", "Show in: Menu bar", "preference", "Menu bar only: accessory policy, status item present", "Dock icon goes away"),
        ("General", "Show in: Both", "preference", "Dock and status item", ""),
        ("General", "Snapping: Show OpenSnap window in fullscreen and crosshair snaps", "preference", "Checkbox persists includeApp", ""),
        ("General", "Hints: Show hover hints for tools", "preference", "Checkbox persists showToolTips", ""),
        ("General", "Hints: Show keyboard tip overlay", "preference", "Checkbox persists showKeyboardTips; the help bevel appears on hover", ""),
        ("Drawing", "Drawing precision: Precise", "preference", "Pencil smoothing precise; mirrors Drawing › Pencil Smoothing", ""),
        ("Drawing", "Drawing precision: Medium", "preference", "Pencil smoothing medium", ""),
        ("Drawing", "Drawing precision: Loose", "preference", "Pencil smoothing loose", ""),
        ("Drawing", "Arrow head: End", "preference", "Arrow head at the end; mirrors Drawing › Arrow Head", ""),
        ("Drawing", "Arrow head: Start", "preference", "Arrow head at the start", ""),
        ("Drawing", "Caption: Holding Option reverses the setting.", "control", "Static caption, 20 pt, wraps within the control column", ""),
        ("Capture", "Flash: Show capture flash", "preference", "Checkbox persists showCaptureFlash", ""),
        ("Upload", "Destinations list", "control", "Every destination as a selectable row with name, transport and a Default pill; the list scrolls past what the screen leaves", ""),
        ("Upload", "Empty state: No destinations yet", "state", "Shown when no destination exists, with Add… inside the list", ""),
        ("Upload", "Add…", "control", "Opens the destination editor sheet on the Settings window", ""),
        ("Upload", "Edit…", "control", "Opens the selected destination in the editor sheet (double-click a row does the same)", ""),
        ("Upload", "Remove", "control", "Asks Remove “name”? (Cancel first, Remove destructive) as a sheet on Settings, then removes it and its stored secret", ""),
        ("Upload", "Make Default", "control", "Marks the selected destination as the one Upload uses; the Default pill moves", ""),
        ("Upload", "Caption: Uploads go to the default destination. Right-click Upload to switch.", "control", "Static caption", ""),
    ]
    for tab, name, kind, expected, extra in rows:
        add("SET", f"Settings › {tab}", name, kind, f"Settings › {tab} › {name.split(':')[0]}", expected + (f" ({extra})" if extra else ""),
            prereq="Destinations seeded" if "Destinations list" in name else (D if "Empty" not in name else "No destinations (--seed empty)"), rendered=["S12"],
            proof=proof("SettingsWindowTests.swift", "initial checkboxes mirror the stored state") if kind == "preference" and tab == "General" and "Snapping" in name else None)
    add("SET", "Settings window", "Settings window Esc / ⌘W", "shortcut", "Settings frontmost › Esc or ⌘W", "Closes Settings (a sheet attached blocks the tab shortcuts)", shortcut="Esc, ⌘W",
        proof=proof("SettingsWindowTests.swift", "Command-W is handled by the window"))
    add("SET", "Settings window", "Persisted settings across relaunch", "state", "Change a setting, stop and start a new session", "Each setting returns (in a throwaway domain); the real domain is never touched", prereq="Isolated session twice",
        note="A relaunch is a new throwaway id, so persistence is observed within one session by closing and reopening Settings")


def build_hotkeys():
    # The Capture Shortcuts sheet was removed in d9ed8b7; its rows stay (same IDs, same evidence) as retired. The live rows are the surface.
    for mode, where in (("sheet", "Menu bar › OpenSnap › Capture Shortcuts…"), ("live", "Settings › Capture › shortcut rows")):
        s = f"Capture shortcuts ({mode})"
        retired = {"ex": "gap", "gap": "removed"} if mode == "sheet" else {}
        what = (lambda text: f"RETIRED, removed in d9ed8b7 (the sheet no longer exists): {text}") if mode == "sheet" else (lambda text: text)
        add("HOT", s, "Enable global capture shortcuts", "preference", f"{where} › Enable", what("Checkbox enables or disables all bindings"),
            rendered=["S18"], **retired)
        for action in ("Screen region", "Window", "Full screen", "Frame", "Upload", "Show OpenSnap"):
            add("HOT", s, f"{action}: key", "control", f"{where} › {action} key", what("Pop-up: None plus the key choices; choosing a key enables its modifier segments"), rendered=["S18"], **retired)
            add("HOT", s, f"{action}: modifiers", "control", f"{where} › {action} modifiers", what("Four selectAny segments ⌘ ⌥ ⌃ ⇧; disabled until a key is chosen"), rendered=["S18"], **retired)
        replaced = {"ex": "gap", "gap": "replaced"}
        add("HOT", s, "Reset Defaults", "control", f"{where} › Reset Defaults", "RETIRED, renamed Clear All in audit batch 5 (it clears every key, it never restored defaults)", rendered=["S18"], **(retired or replaced))
        add("HOT", s, "Disable All", "control", f"{where} › Disable All", "RETIRED, removed in audit batch 5: unticking Enable global capture shortcuts does the same", rendered=["S18"], **(retired or replaced))
        if mode == "live":
            add("HOT", s, "Clear All", "control", f"{where} › Clear All", "Sets every key to None (first launch claims no shortcut) and applies at once", rendered=["S18"])
        add("HOT", s, "Status line", "state", f"{where} › status", what("Idle text, or Error: … beside a rejected draft (conflict with an internal or system binding)"), rendered=["S18"], **retired)
        if mode == "sheet":
            add("HOT", s, "Cancel", "control", f"{where} › Cancel", what("Closes the sheet leaving settings unchanged (Esc)"), shortcut="Esc", rendered=["S18"], **retired)
            add("HOT", s, "Save", "control", f"{where} › Save", what("Applies the draft and closes (Return)"), shortcut="Return", rendered=["S18"], **retired)
    add("HOT", "Capture shortcuts (live)", "Menu entry: Capture Shortcuts…", "menu item", "Menu bar › OpenSnap › Capture Shortcuts…", "Opens the Settings window on the Capture tab (no separate sheet since d9ed8b7)",
        shortcut=None, rendered=["S18"])
    add("HOT", "Capture shortcuts (live)", "Shortcuts pause while the Capture tab is in front", "state", "Settings › Capture", "Saved shortcuts are unregistered only while Settings is the key window on the Capture tab and the app is active; another window or app in front, another tab, hiding or closing Settings registers them again, so a half-entered chord never goes live",
        proof=proof("SettingsWindowTests.swift", "Settings key and the app active on Capture pauses every shortcut"))
    for action in ("Screen region", "Window", "Full screen", "Frame", "Upload", "Show OpenSnap"):
        add("HOT", "Global hotkey firing", f"{action} (fires while backgrounded)", "shortcut", "Another app frontmost › the bound chord", "OpenSnap performs the action without being frontmost",
            prereq="A binding saved", ex="gap", gap="global-hotkey-background")


# ----------------------------------------------------------------------------------------------------------------------- history
def build_history():
    add("HIST", "History window", "History window", "window", "Menu bar › File › History, or bottom bar › History", "Opens 1000 x 720 (min 880 x 600); grid with day sections, details panel beside the grid",
        rendered=["S20"], proof=proof("HistoryBrowserTests.swift", "Window opens 1000 x 720 with an 880 x 600 minimum"))
    for cat in ("All", "Shared", "Exported", "Saved"):
        add("HIST", "History › category control", cat, "control", f"History › {cat}", f"Filters the grid ({'every entry' if cat == 'All' else f'entries labelled {cat}'}; tab names are the tile labels)",
            prereq="History seeded", rendered=["S20"], proof=proof("HistoryBrowserTests.swift", "Original action filters use exact supplied core strings"))
    for date in ("All dates", "Last hour", "Yesterday", "Last 48 hours"):
        add("HIST", "History › date pop-up", date, "control", f"History › date filter › {date}", f"Filters by {date.lower()} using the strict bounds", prereq="History seeded", rendered=["S20"],
            proof=proof("HistoryBrowserTests.swift", "Recovered date predicates use strict hour 48hour and yesterday bounds"))
    add("HIST", "History", "Search history", "control", "History › search field", "One literal case-insensitive OR over name, link and text; filters live", prereq="History seeded",
        rendered=["S20"], proof=proof("HistoryBrowserTests.swift", "Original search is one literal case insensitive OR over name link text"))
    actions = [("Open", "openExternal", "Opens the entry's editable document in the editor"), ("Copy", "copy", "Copies the picture to the pasteboard"), ("Copy Link", "link", "Copies the published URL (Posted entries only)"),
               ("Open Link", "globe", "Opens the published URL in the default browser"), ("Hide from History", "folderMinus", "Confirm sheet, then the entry leaves the list (files kept); labelled Hide"),
               ("Move to Trash", "trash", "Confirm sheet, then archive copies move to Trash"), ("Delete from Web", "linkSlash", "Confirm sheet, then the remote object is deleted (verified binding only)")]
    for name, icon, expected in actions:
        add("HIST", "History › action row", name, "toolbar button", f"History › {name} (icon button, labelled while the window is wide enough; Hide, Trash and Delete from Web always)", expected, icon=icon, prereq="An entry selected" + (" with a remote link" if "Link" in name or "Web" in name else ""),
            rendered=["S20"],
            ex="e2e-partial" if name in ("Open Link",) else "e2e", gap="os-panel" if name == "Open Link" else None, note="Opens the default browser (OS-owned)" if name == "Open Link" else None)
        add("HIST", "History › context menu", name, "menu item", f"History › right-click a tile › {name}", expected, prereq="An entry selected", rendered=["S20"],
            ex="e2e-partial" if name == "Open Link" else "e2e", gap="os-panel" if name == "Open Link" else None)
    for fmt in ("PNG", "JPG", "PDF", "TIFF", "SVG", ".opensnap document"):
        add("HIST", "History › Drag as pop-up", fmt, "control", f"History › Drag as › {fmt}", f"The pop-up (end of the footer line) offers {fmt}; tiles then drag out as {fmt} and the choice persists independently of the editor", prereq="History seeded", rendered=["S20"],
            proof=proof("HistoryBrowserTests.swift", "Drag formats are PNG JPG PDF TIFF SVG and the .opensnap document"))
    for name, expected in [("Tile: select / multi-select", "Click selects with an accent border and check badge; ⌘/⇧-click extends"), ("Tile: double-click", "Opens the entry"),
                           ("Tile: drag out", "Promised file with the frozen format and a sanitised name"), ("Details: Name, Date, Size, Action, Destination", "Shows metadata; multi-selection aggregates"),
                           ("Details preview", "Bounded local preview image of the selection"), ("Day section headings", "Today, Yesterday, then dated headings"),
                           ("Empty state: No history yet", "Hint reads the live Save to History shortcut"), ("Empty state: No history items match these filters", "Shown when filters hide everything"),
                           ("Missing-file warning", "Missing local files disable local actions but keep links and Hide"), ("Status line", "N items · M selected"),
                           ("Reflow at 880 x 600", "No horizontal scroller; tiles evenly spaced; details move under the grid below 760 wide")]:
        add("HIST", "History", name, "state" if "Empty" in name or "warning" in name or "Reflow" in name else "control", f"History › {name}", expected, prereq="History seeded" if "Empty state: No history yet" not in name else "No History (--seed empty)",
            rendered=["S20"], proof=proof("HistoryBrowserTests.swift", "Selected tile shows an accent border and a check badge, not colour alone") if "select" in name else None)
    add("HIST", "History", "Keyboard: Open, Copy, Copy Link, Remove on the selection", "shortcut", "History › selection + keys", "Each key command invokes the matching action with the selected UUIDs", prereq="An entry selected",
        proof=proof("HistoryBrowserTests.swift", "Keyboard Open Copy Copy Link Remove use UUID callbacks"))


# --------------------------------------------------------------------------------------------------------------------- destinations
def build_destinations():
    # The Destinations list sheet was replaced by Settings › Upload in audit batch 5; its rows stay (same IDs, same evidence) as retired.
    gone = {"ex": "gap", "gap": "replaced"}
    old = lambda text: f"RETIRED, replaced by Settings › Upload in audit batch 5 (the list sheet no longer exists): {text}"
    add("DEST", "Destinations sheet", "Destinations sheet", "sheet", "Menu bar › OpenSnap › Sharing Settings…, Settings › Upload › Manage Destinations…, Upload right-click › Destination Settings…",
        old("Sheet over the main window: list of destinations plus Add…, Edit…, Remove, Make Default, Done"), rendered=["S19"], **gone)
    for name, expected in [("Add…", "Opens the form with the first protocol selected"), ("Edit…", "Opens the form for the selected destination"), ("Remove", "Confirmation alert (Remove / Cancel); removes the destination and its stored secret"),
                           ("Make Default", "Marks the destination used by Upload (Default pill moves)"), ("Done", "Closes the sheet (Return)")]:
        add("DEST", "Destinations sheet › list", name, "control", f"Destinations › {name}", old(expected), prereq="Destinations seeded" if name != "Add…" else D, rendered=["S19"], **gone)
    add("DEST", "Destination editor", "Destination editor sheet", "sheet", "Settings › Upload › Add… / Edit… (double-click a row)",
        "Sheet on the Settings window holding one destination's form; sized to its protocol, scrolls on a short screen, Return saves and Esc cancels", rendered=["S19"])
    for protocol in ("WebDAV", "FTP", "FTPS", "SFTP", "S3-compatible"):
        add("DEST", "Destination form › Protocol", protocol, "control", f"Settings › Upload › Add… › Protocol › {protocol}", f"Form shows the {protocol} field set and help", rendered=["S19", "S21"])
    fields = [("Name", "all", "Required, up to 80 characters, unique"), ("Endpoint URL", "all", "Validated scheme per protocol (https for S3 unless a private host)"),
              ("Region", "S3", "e.g. us-east-1"), ("Bucket", "S3", "Valid bucket name; dotted buckets use path-style"), ("Remote folder / Key prefix", "all", "Letters, digits, . _ - only for S3"),
              ("Public base URL", "all", "Optional; builds the copied link"), ("SSH host alias", "SFTP", "From ~/.ssh/config"), ("SFTP remote root", "SFTP", "Absolute path"),
              ("SFTP port", "SFTP", "Number or empty"), ("Source (AWS credentials profile | Access key stored in Keychain)", "S3", "Chooses the credential source"),
              ("AWS profile", "S3 + profile", "Reads the shared credentials file in place"), ("Username / Access key ID", "non-SFTP", "Optional for anonymous"),
              ("Password / Secret access key", "non-SFTP", "Secure field; stored in the Keychain (in memory in an isolated session)"), ("Make uploads public-read", "S3", "Checkbox; off by default (ACLs-off buckets)")]
    for name, scope, expected in fields:
        add("DEST", "Destination form", name, "control", f"Settings › Upload › Add…/Edit… › {name}", f"{expected} (shown for: {scope})", rendered=["S19", "S21"])
    for name, expected in [("Test", "Tries the destination; result line shows Connected + detail or Error: …"), ("Save", "Validates and stores; secret goes to the secret store (Return)"), ("Cancel", "Closes the editor sheet (Esc)"),
                           ("Result line: working / success / failure", "Glyph plus words (Saving…, Testing…, Connected, Error: …), never colour alone")]:
        add("DEST", "Destination form", name, "control", f"Settings › Upload › Add…/Edit… › {name}", expected, rendered=["S19", "S21"])
    add("DEST", "Destinations sheet", "Remove confirmation (NSAlert)", "alert", "Destinations › Remove", old("Alert: Remove “name”? with Remove / Cancel; drawn by NSAlert, not AppAlert"),
        prereq="Destinations seeded", note="Superseded: the question is an AppAlert sheet on Settings (Settings › Upload › Remove)", rendered=["S26"], **gone)
    add("DEST", "Destination editor", "Remove confirmation (AppAlert)", "alert", "Settings › Upload › Remove", "AppAlert sheet on the Settings window: Remove “name”? with Cancel first and default, Remove destructive; names who becomes the default",
        prereq="Destinations seeded", rendered=["S26"], proof=proof("SettingsWindowTests.swift", "Remove opens one app-owned alert hanging from the Settings window"))
    for name, expected, ex, gap in [
            ("Upload to the AWS profile destination (success)", "Synthetic PNG object under pics/, link https://cdn.shoemoney.com/pics/… copied, status confirms, History gets a Shared entry", "e2e", None),
            ("Upload to a fake host (failure)", "Error shown with a glyph; status and History do not claim success", "e2e", None),
            ("Upload with no destination", "Says so in the status line and opens Settings › Upload: empty list, Add… inside it", "e2e", None),
            ("Upload retry after failure", "Second click retries to the same destination", "e2e", None),
            ("Upload cancel while busy", "Cancel Upload stops the transfer", "e2e", None),
            ("Delete from Web (History)", "Confirm alert, then the remote object is removed; History copy kept", "e2e", None),
            ("Test connection (S3)", "Connected with the server's detail, or Error:", "e2e", None)]:
        add("DEST", "Upload journeys", name, "state", f"Upload (bottom bar) / Settings › Upload › {name}", expected, prereq="--seed destinations (fake hosts) or --aws (real profile, synthetic object, orchestrator-run)", ex=ex, gap=gap)


# --------------------------------------------------------------------------------------------------------------------- sheets etc.
def build_sheets():
    add("SHEET", "Resize or Crop", "Resize or Crop sheet", "sheet", "Menu bar › Image › Resize…, bottom bar › Resize…", "Sheet with heading, preset pop-up, mode control, dimension fields, buttons; Return = OK, Esc = Cancel", rendered=["S08"])
    for name, expected in [("Size preset pop-up", "Custom size plus saved presets"), ("Preset name field", "Names a new or edited preset"), ("Add Preset", "Saves the current dimensions as a new preset"),
                           ("Save Preset", "Updates the selected preset"), ("Remove (preset)", "Removes the selected preset"), ("Mode: Resize", "Resizes the canvas by pixels"), ("Mode: Crop", "Crops with an anchor"),
                           ("Mode: Limit", "Limits the longest side, width or height"), ("Width (pixels)", "Validated integer field"), ("Height (pixels)", "Validated integer field"),
                           ("Lock proportions", "Keeps the aspect ratio while editing"), ("Limit by: Longest side / Width / Height", "Chooses what the limit applies to"), ("Size limit field", "Validated integer"),
                           ("Crop anchor (9 positions)", "Top/Middle/Bottom x Left/Center/Right"), ("Validation message", "Error text with the field name, never colour alone"),
                           ("Cancel", "Closes without change (Esc)"), ("Apply", "Keeps the change and the sheet; Cancel then undoes only later edits"), ("OK", "Applies and closes (Return)")]:
        add("SHEET", "Resize or Crop", name, "control", f"Resize or Crop › {name}", expected, prereq="Not in Actual Size or Frame mode", rendered=["S08"])
    add("SHEET", "Photos", "Photos sheet", "sheet", "Menu bar › File › Photos…, top bar › Photos", "Sheet titled Photos: Open a photo, Pictures / image folder chooser, grid, Close", rendered=["S12"])
    for name, expected, ex, gap, owner in [("Pictures folder", "Browses the Pictures folder (only the chosen folder)", "e2e", None, "app"),
                                           ("Choose image folder…", "Open panel titled Choose an image folder", "e2e-partial", "os-panel", "app"),
                                           ("Photos Library", "Photos library browser window", "gap", "photos-library", "os"),
                                           ("Thumbnail grid / open photo", "Double-click opens the photo into the editor", "e2e", None, "app"),
                                           ("Close", "Closes the sheet", "e2e", None, "app")]:
        add("SHEET", "Photos", name, "control", f"Photos › {name}", expected, prereq="A synthetic folder of pictures for the grid", ex=ex, gap=gap, owner=owner)
    add("SHEET", "Export options (save-panel accessory)", "Export options accessory", "sheet", "Menu bar › File › Export…", "Save panel with the accessory: Format, JPEG quality, Export at original size, dimensions, file size", ex="e2e-partial", gap="os-panel",
        rendered=["S10"])
    for fmt in ("PNG", "JPEG", "TIFF", "GIF", "BMP", "PDF", "SVG", "OpenSnap"):
        add("SHEET", "Export options (save-panel accessory)", f"Format: {fmt}", "control", f"Export… › Format › {fmt}", f"Exports as {fmt}; quality and original-size controls follow the format", ex="e2e-partial", gap="os-panel", rendered=["S10"])
    for name, expected in [("JPEG quality slider (10-100%)", "Quality changes the encoded size line"), ("Export at original size", "Checkbox; dimensions line follows"), ("Dimensions and file-size lines", "Show actual encoded size")]:
        add("SHEET", "Export options (save-panel accessory)", name, "control", f"Export… › {name}", expected, ex="e2e-partial", gap="os-panel", rendered=["S10"])
    add("SHEET", "Font panel", "Font panel (system) with accessory", "sheet", "Top bar › Font, Text › Text Style…", "NSFontPanel sized 940 x 720 with Text outline, Text shadow and Default Text Style", ex="e2e-partial", gap="os-panel", owner="os", rendered=["S06"])
    add("SHEET", "Colour panel", "Colour panel modes (Color Wheel, Color Sliders, Color Palettes, Image Palettes, pick color, color slider)", "control",
        "Top bar › Color › Custom color… › panel toolbar", "System colour panel modes and eyedropper; OS-owned controls", ex="e2e-partial", gap="os-panel", owner="os", rendered=["S06"])
    add("SHEET", "Colour panel", "Colour panel (system)", "sheet", "Top bar › Color › Custom color…", "NSColorPanel with alpha; live-applies colour", ex="e2e-partial", gap="os-panel", owner="os", rendered=["S06"])
    add("SHEET", "About window", "About window", "window", "Menu bar › OpenSnap › About OpenSnap", "Window About OpenSnap: icon, name, Version 0.3.0 (build 3), credit, MIT License and Third-party notices links", rendered=["S12"])
    add("SHEET", "About window", "MIT License link", "control", "About › MIT License", "Opens the licence text window (bundled LICENSE.txt, or the missing-text message)", rendered=["S12"])
    add("SHEET", "About window", "Third-party notices link", "control", "About › Third-party notices", "Opens the notices window (Font Awesome Free 7.3.1 CC BY 4.0)", rendered=["S12"])
    add("SHEET", "Screen Recording", "Screen Recording sheet", "sheet", "Any capture without permission", "Title, explanation, Settings… (default) and Cancel", rendered=["S15"])
    for name, text in [("Timed Snapshot", "Delay in seconds (default 6, 0 to 120)"), ("Snap from Link", "Web address (default https://)"), ("Rename", "Document name")]:
        add("SHEET", name, f"{name} prompt", "sheet", f"Menu bar › {name}…", f"App-owned one-line sheet: {text}; OK / Cancel (Return / Esc)", rendered=["S26"])
    add("SHEET", "OS panels", "Open panel", "sheet", "File › Open…", "System open panel limited to .opensnap, pictures and PDFs", ex="e2e-partial", gap="os-panel", owner="os")
    add("SHEET", "OS panels", "Save panel", "sheet", "File › Save / Save As…", "System save panel with .opensnap type", ex="e2e-partial", gap="os-panel", owner="os")
    add("SHEET", "OS panels", "Page Setup panel", "sheet", "File › Page Setup…", "System page layout", ex="e2e-partial", gap="os-panel", owner="os")
    add("SHEET", "OS panels", "Print panel", "sheet", "File › Print…", "System print dialog; actual printing needs a printer", ex="gap", gap="printer", owner="os")
    add("SHEET", "OS panels", "Share picker", "popover", "File › Share…, Upload menu › Share with macOS…", "System sharing picker for the image", ex="e2e-partial", gap="os-panel", owner="os")


def build_alerts():
    for title, buttons, entry, prereq in [
            ("Save your drawing?", "Save · Cancel · Don’t Save", "New, Open, Close or Quit with a dirty document", "Dirty document"),
            ("Hide drawings from History?", "Hide · Cancel", "History › Hide from History", "History entry selected"),
            ("Move archived drawings to Trash?", "Move to Trash · Cancel", "History › Move to Trash", "History entry selected"),
            ("Delete this web post?", "Delete from Web · Cancel", "History › Delete from Web", "Posted entry with a verified binding"),
            ("Error alert (AppAlert(error:))", "OK", "Any failed action (open a corrupt file, save failure, upload failure)", "A forced failure")]:
        add("ALERT", "App alerts (AppAlert)", title, "alert", entry, f"App-owned sheet, 560 pt wide, title headline, body 20 pt, buttons ≥ 36 pt tall ({buttons}); Return = first, Esc = Cancel",
            prereq=prereq, rendered=["S26"])
    add("ALERT", "App alerts (AppAlert)", "Don’t Save answers ⌘D", "shortcut", "Save your drawing? sheet", "Don’t Save discards on ⌘D", shortcut="⌘D", prereq="Dirty document")
    add("ALERT", "Status line messages", "Transient status messages (Saved, Deleting web post…, errors)", "state", "Bottom bar status line", "Result is visible without searching another window", rendered=["S09"])


def build_status():
    add("STAT", "Status item", "Status item (menu bar)", "control", "System menu bar › OpenSnap", "Opens the status menu; shown for Show in: Menu bar or Both", prereq="Show in: Menu bar / Both", icon="camera.viewfinder", rendered=["S17"], proof=proof("AppSafetyMenuCases.swift", "The status item opens a menu: Show or Hide, Snap, Settings, Quit"))
    for name, expected in [("Show OpenSnap / Hide OpenSnap", "Title follows whether the editor is in front and the app active; toggles visibility"), ("Snap…", "Starts a crosshair snap"),
                           ("Settings…", "Opens Settings"), ("Quit OpenSnap", "Quits (dirty document asks first)")]:
        add("STAT", "Status item menu", name, "menu item", f"System menu bar › OpenSnap › {name}", expected, icon={"Snap…": "scope", "Settings…": "gearshape", "Quit OpenSnap": "power", "Show OpenSnap / Hide OpenSnap": "eye"}.get(name),
            ex="e2e-partial" if name == "Snap…" else "e2e", gap="screen-recording" if name == "Snap…" else None, rendered=["S17"])


def build_keys(parsed):
    for menu, name, selector, key in parsed + [(m, n, s, k) for m, n, s, k in EXTRA_MENU]:
        if key:
            chord = shortcut_text(key, "⌃" if name == "Enter Full Screen" else "")
            add("KEY", f"Menu key equivalents › {menu}", f"{chord} {name}", "shortcut", f"Press {chord} with the editor key", f"Runs {name}",
                prereq=SEM[selector][0], shortcut=chord, ex="e2e", rendered=["S12"])
    for chord, expected, kind in [
            ("Shift on Snap Frame", "Six-second timer instead of an instant frame snap", "gesture"), ("Option-click a capture control", "Keeps OpenSnap visible during the snap", "gesture"),
            ("Shift-click a colour swatch", "Sets the canvas background colour instead of the pen", "gesture"), ("Option while drawing an arrow", "Reverses arrow direction", "gesture"),
            ("Shift while drawing an arrow", "Constrains the angle", "gesture"), ("Hold Shift on the Size slider", "Allows custom sizes (hint text)", "gesture"),
            ("⌘1 … ⌘4 in Settings", "Select the General, Drawing, Capture or Upload tab (blocked while a sheet is attached)", "shortcut"),
            ("Esc in a sheet or alert", "Cancels", "shortcut"), ("Return in a sheet or alert", "Presses the default button", "shortcut"),
            ("Tab / ⇧Tab through the chrome", "Visits every enabled control in a sensible order with a visible focus ring", "shortcut"),
            ("Space on a focused button", "Presses it", "shortcut")]:
        add("KEY", "Modifiers and navigation", chord, kind, chord, expected, prereq=D, rendered=["S04"])


def build_states():
    for name, expected, ex, gap in [
            ("Window default size 1120 x 812", "Opens at the default size; canvas centred", "e2e", None), ("Window minimum 980 pt wide", "Both bars fit without clipping at the minimum", "e2e", None),
            ("Window maximised / zoomed", "Canvas centres; no stretched chrome", "e2e", None), ("Window full screen (green button)", "Chrome stays usable in the system full-screen space", "e2e", None),
            ("Frame mode at 980 and 1280", "Hole punched through the well; Snap becomes Snap Frame; Cancel visible; no full-screen entry while framing", "e2e", None),
            ("Empty document", "800 x 600 white canvas, Undo/Wipe disabled", "e2e", None), ("Populated document", "Elements drawn; Undo enabled; edited dot", "e2e", None),
            ("Dirty then Save", "Edited dot clears after Save to History / Save", "e2e", None), ("Actual Size mode", "Navigator shown, Resize disabled", "e2e", None),
            ("Large picture fit", "Fit computed zoom entry appears in the pop-up", "e2e", None), ("Small picture centred", "Centred, not stretched", "e2e", None),
            ("Long status text", "Truncates at the tail without pushing controls", "e2e", None), ("PNG | JPG toggle states", "Selected segment distinguishable without colour alone", "e2e", None),
            ("Control states: rest, hover, pressed, focus, selected, disabled", "Each distinguishable; hover/pressed are real pointer states", "e2e", None),
            ("Light appearance", "Whole app legible in light", "gap", "system-setting"), ("Dark appearance", "Whole app legible in dark (the machine's current style)", "e2e", None),
            ("Reduce Transparency", "Glass plates become solid", "gap", "system-setting"), ("Increase Contrast", "Borders strengthen", "gap", "system-setting"),
            ("Differentiate Without Color", "State cues beyond colour", "gap", "system-setting"), ("Reduce Motion", "No decorative motion", "gap", "system-setting"),
            ("Combined display options", "Combinations render coherently", "gap", "system-setting"), ("Retina (2x) rendering", "Crisp glyphs at 2x", "e2e", None),
            ("Multiple displays / 1x", "Chrome and overlays on a second display", "gap", "display-hardware")]:
        add("STATE", "Window and display states", name, "state", name, expected, prereq=D, ex=ex, gap=gap, rendered=["S11", "S01"],
            note="Harness-injected evidence exists (--display, --appearances)" if gap == "system-setting" else None)


def build_a11y():
    for name, expected, ex, gap in [
            ("Full keyboard operation of the editor chrome", "Every control reachable and operable by keyboard only", "e2e", None),
            ("Focus order and focus appearance", "Logical order, visible ring on every control", "e2e", None),
            ("Accessible names, roles and states for icon-only controls", "Every app-owned icon-only action is named; toggles report state", "e2e", None),
            ("AX tree of every sheet and window", "Roles and labels present; value for sliders and pop-ups", "e2e", None),
            ("Announcements (Announcer)", "Status changes are posted as announcements", "e2e", None),
            ("VoiceOver speech", "Spoken labels match the visual meaning", "gap", "voiceover")]:
        add("A11Y", "Accessibility", name, "state", name, expected, ex=ex, gap=gap)


# ----------------------------------------------------------------------------------------------------------------------- harness
HARNESS_SEEN = OUT_DIR / "harness-seen.json"


def merge_harness(folder):
    folder = Path(folder)
    raw = folder / "raw-sf"
    surfaces = {}
    controls = {}
    for meta in sorted(raw.glob("meta/*.json")):
        data = json.loads(meta.read_text())
        surfaces[data["id"]] = {"id": data["id"], "slug": data.get("slug"), "surface": data.get("surface"), "state": data.get("state")}
    for ax in sorted(raw.glob("ax/*.json")):
        data = json.loads(ax.read_text())
        def walk(node):
            role = node.get("role", "")
            if role in ("AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXSlider", "AXTextField", "AXSegmentedControl", "AXMenuItem", "AXTab"):
                label = node.get("label") or node.get("title") or (node.get("help") or "").split(" (")[0].split(";")[0]
                if label:
                    controls.setdefault((role, label), set()).add(data["id"])
            for child in node.get("children", []):
                walk(child)
        for window in data.get("windows", []):
            walk(window["tree"])
    HARNESS_SEEN.write_text(json.dumps({"source": "tools/eye-dump-audit.sh --groups main,more,overlays,states,pairs --appearances light --icons sf",
                                        "surfaces": surfaces, "controls": [[role, label, sorted(ids)] for (role, label), ids in sorted(controls.items())]}, indent=1, ensure_ascii=False) + "\n")
    return surfaces, controls


def load_harness_seen():
    data = json.loads(HARNESS_SEEN.read_text())
    return data["surfaces"], {(role, label): set(ids) for role, label, ids in data["controls"]}


def norm(text):
    return re.sub(r"[^a-z0-9]", "", text.lower().replace("…", "").replace("(⌘m)", ""))


def account_for_harness(surfaces, controls):
    known = collections.defaultdict(set)
    for entry in entries:
        for text in {entry["name"], entry["name"].replace(" tool", ""), entry["name"].split(":")[0], entry["entryPath"].split("›")[-1].strip()}:
            known[norm(text)].add(entry["id"] if "id" in entry else entry["name"])
    unmatched = []
    for (role, label), ids in sorted(controls.items()):
        if norm(label) in known or any(norm(label) in k or (k and k in norm(label) and len(k) > 5) for k in known):
            continue
        unmatched.append((role, label, sorted(ids)))
    for entry in entries:
        entry["rendered"] = sorted(set(entry["rendered"]))
    for role, label, ids in unmatched:
        add("HARN", f"Harness {', '.join(ids[:3])}", label, "control", f"Seen in {', '.join(ids[:4])} ({role})", "Exercise it and record what it does; add it to a source table", prereq="See the surface", rendered=ids, src=f"harness:{ids[0]}")
    return unmatched


# ------------------------------------------------------------------------------------------------------------------------ output
# Entries whose name changed with the product (History tabs renamed to the tile labels): the ID follows the old row, so its evidence stays.
RENAMED = {"E2E-HIST-003": "Shared", "E2E-HIST-004": "Exported", "E2E-HIST-005": "Saved"}


def assign_ids():
    previous = {}
    if INVENTORY.exists():
        for entry in json.loads(INVENTORY.read_text())["entries"]:
            previous[(entry["area"], entry["surface"], RENAMED.get(entry["id"], entry["name"]), entry["type"])] = entry["id"]
    counters = collections.Counter()
    used = set(previous.values())
    for key, ident in previous.items():
        counters[key[0]] = max(counters[key[0]], int(ident.rsplit("-", 1)[1]))
    seen = set()
    for entry in entries:
        key = (entry["area"], entry["surface"], entry["name"], entry["type"])
        if key in seen:   # distinct entries must have distinct keys, or an ID would be shared
            entry["name"] += f" ({entry['entryPath']})"
            key = (entry["area"], entry["surface"], entry["name"], entry["type"])
        seen.add(key)
        if key in previous:
            entry["id"] = previous[key]
        else:
            counters[entry["area"]] += 1
            entry["id"] = f"E2E-{entry['area']}-{counters[entry['area']]:03d}"
            assert entry["id"] not in used
            used.add(entry["id"])
    entries.sort(key=lambda e: (list(AREAS).index(e["area"]), int(e["id"].rsplit("-", 1)[1])))


def counts():
    by = lambda f: dict(sorted(collections.Counter(f(e) for e in entries).items()))
    return {"total": len(entries), "byArea": by(lambda e: e["area"]), "byType": by(lambda e: e["type"]), "byExercise": by(lambda e: e["exercise"]),
            "byGap": by(lambda e: e["gap"] or "none"), "byOwner": by(lambda e: e["owner"])}


def cell(text):
    return str(text or "").replace("|", "\\|").replace("\n", " ")


SPLIT = re.compile(r"(?<!\\)\|")


def existing_rows():
    """Filled-in evidence columns of the current matrix by ID, so a regenerate never clobbers audit results."""
    rows = {}
    if MATRIX.exists():
        for line in MATRIX.read_text().splitlines():
            if line.startswith("| E2E-"):
                cells = [c.strip() for c in SPLIT.split(line.strip().strip("|"))]
                if len(cells) == 13:
                    rows[cells[0]] = cells
    return rows


def matrix():
    head = ["ID", "surface", "option", "entry path", "prerequisite", "action", "expected", "observed", "source SHA", "evidence (path)", "evidence class", "reviewer", "gap"]
    lines = ["# Coverage matrix", "",
             "Generated by `tools/e2e-inventory.py` from `inventory.json`; one row per audit ID. Columns 1-7 and `gap` are regenerated; `observed`, `source SHA`, "
             "`evidence (path)`, `evidence class` and `reviewer` are filled in while auditing and are preserved across regenerates. "
             "Evidence classes are never merged: `E2E` (real interaction), `rendered` (harness), `unit/source` (an existing named test proves the behaviour), `unverified`, "
             "and `retired` (the surface was removed or replaced: the ID and its historic evidence stay in the row, but it counts toward no other class). "
             "`TBD` means not yet observed; a row's class stays `unverified` until its evidence exists, and `unit/source` rows name the test.", "",
             "| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    kept = existing_rows()
    for e in entries:
        proofs = "; ".join(f"{p['file']}: “{p['test']}”" for p in e["proof"])
        action = f"{e['type']}: {e['name']}" if e["type"] != "icon" else f"look at the icon {e['name']} in place"
        gap = f"{e['exercise']}: {e['gap']}" if e["gap"] else ""
        fresh = [e["id"], e["surface"], e["name"], e["entryPath"], e["prerequisite"], action, e["expected"], "TBD", "TBD", f"test {proofs}" if proofs else "TBD",
                 "unit/source" if proofs else "unverified", "TBD", gap]
        old = kept.get(e["id"])
        if old and old[7] != "TBD":   # observed: a human or a run has filled this row in, keep its evidence columns
            fresh[7:12] = old[7:12]
        if e["gap"] in RETIRED_GAPS:
            fresh[10] = "retired"
        lines.append("| " + " | ".join(cell(x) for x in fresh) + " |")
    return "\n".join(lines) + "\n"


def build(args):
    entries.clear()
    parsed = build_menus()
    build_toolbox(parsed)
    build_icons()
    build_chrome(); build_tools(); build_canvas(); build_capture()
    build_settings(); build_hotkeys(); build_history(); build_destinations(); build_sheets(); build_alerts(); build_status(); build_keys(parsed); build_states(); build_a11y()
    surfaces, unmatched = {}, []
    if args.harness or HARNESS_SEEN.exists():
        surfaces, controls = merge_harness(args.harness) if args.harness else load_harness_seen()
        assign_ids()
        unmatched = account_for_harness(surfaces, controls)
    assign_ids()
    verify_proofs()
    return surfaces, unmatched


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--harness", help="output folder of tools/eye-dump-audit.sh")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    surfaces, unmatched = build(args)
    document = {"generator": "tools/e2e-inventory.py", "gaps": GAPS, "areas": AREAS, "counts": counts(),
                "harnessSurfaces": sorted(surfaces.values(), key=lambda s: s["id"]) if surfaces else [], "entries": entries}
    text = json.dumps(document, indent=1, ensure_ascii=False) + "\n"
    if args.check:
        if not INVENTORY.exists() or INVENTORY.read_text() != text or MATRIX.read_text() != matrix():
            raise SystemExit("inventory.json or coverage-matrix.md is out of date: run python3 -I tools/e2e-inventory.py --harness DIR")
        print("PASS e2e inventory is current")
        return
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    INVENTORY.write_text(text)
    MATRIX.write_text(matrix())
    print(json.dumps(counts(), indent=1, ensure_ascii=False))
    if unmatched:
        print(f"{len(unmatched)} harness control(s) added as E2E-HARN entries")


if __name__ == "__main__":
    main()
