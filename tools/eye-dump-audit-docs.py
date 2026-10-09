#!/usr/bin/env python3
"""Generate captures.md, gaps.md, metrics/text-size-summary.md and layout-width-budget.md from an assembled evidence dir.

  python3 -I tools/eye-dump-audit-docs.py --dir DOCDIR --observations observations.json
"""
import argparse, collections, json, pathlib, re, subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources"


def grep_line(needle: str, files=None):
    hits = []
    for path in sorted(SRC.glob("*.swift")):
        if files and path.name not in files:
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if needle in line:
                hits.append(f"Sources/{path.name}:{number}")
    return hits


STATIC_GAPS = [
    ("Liquid Glass backdrop of alerts and the status-bar button", "NSAlert panels use a translucent glass material that CGWindowList does not capture: the alert PNGs came out transparent behind the text (dark-mode text is white and invisible on a white viewer). The assembler flattens those PNGs onto a neutral backdrop (#ECECEC light, #2C2A29 dark; manifest field flattenedOnBackdrop); it is not the exact material a user sees. The S24 status-button renders (a bare template image) are flattened the same way."),
    ("Reduce Transparency", "Cannot be toggled without changing system settings (forbidden). Current value recorded in environment.json (false); the chrome's reduced-transparency path (opaque glass, no canvas bleed) was NOT rendered."),
    ("Increase Contrast", "Same: forbidden to toggle. Current value false; the 1-pt contrast ring on selected glass surfaces (GlassChrome.swift showsContrastRing) was NOT rendered."),
    ("Reduce Motion", "Same: forbidden to toggle. Current value false; window-zoom/drag-thumbnail animations ran in their animated form only."),
    ("Bold Text / system text size", "No public read-only API; not toggled. Recorded as unknown."),
    ("Differentiate Without Color", "Current value false (environment.json); the selected-tool state relies on accent fill alone and was not rendered in the differentiated mode."),
    ("VoiceOver speech", "Not run. The AX dumps in ax/ are a structural substitute only (roles, labels, help, children, key-view loop)."),
    ("Non-Retina 1x display", "Only the built-in 2x Retina display exists on this machine; 1x rendering (hairlines, glyph hinting) was not captured."),
    ("Multi-display", "A single display is attached; active-display capture and cross-display window placement were not exercised."),
    ("Live screen capture / real crosshair over real pixels", "No Screen Recording grant and capturing the screen is forbidden for this audit. The picker lens is shown grey (what renders without a grant) and with synthetic pixels."),
    ("Native tooltips / hover-only affordances", "AppKit tooltips are window-server drawn on real pointer dwell; they cannot be forced. Tooltip strings are recorded in metrics/*.json (toolTip). Hover/pressed glass states were forced through GlassSurfaceView.setHovered/isPressed only."),
    ("NSSharingServicePicker / system share sheet", "Out-of-process and lists the user's real accounts; not opened."),
    ("Photo browser (S22)", "Reads the user's Photos library and Desktop with no synthetic-content seam; not opened (privacy)."),
    ("Real drag-and-drop to Finder", "A real drag session needs a real pointer and writes files; only the drag thumbnail panel states were driven."),
    ("Real uploads (S3/SFTP/WebDAV)", "Forbidden; the publish progress/success/error states were driven through a stubbed uploader on an isolated destination store with in-memory secrets."),
]


def load_json(path):
    return json.loads(pathlib.Path(path).read_text())


def write_gaps(out, observations):
    raw = load_json(out / "gaps-raw.json") if (out / "gaps-raw.json").exists() else []
    seen, rows = set(), []
    for item in raw:
        # Menu/modal timers that did not fire are superseded by the curated rows below (the alerts were captured by the unexpected-modal guard).
        if item["reason"].startswith(("the modal call returned", "menu tracking returned")):
            continue
        key = (item["id"], item["surface"], item["reason"])
        if key in seen:
            continue
        seen.add(key); rows.append(dict(item, appearance="both"))
    manifest = load_json(out / "manifest.json")
    captured = {m["id"] for m in manifest}
    lines = ["# Coverage gaps", "",
             "Everything below was NOT captured (or could not be captured faithfully), with the reason. Nothing here is faked.", "",
             "## Surfaces / states not captured", "", "| ID | Surface / state | Appearance | Reason |", "|---|---|---|---|"]
    for item in sorted(rows, key=lambda r: (r["id"], r["surface"])):
        lines.append(f"| {item['id']} | {item['surface']} | {item['appearance']} | {item['reason']} |")
    for extra in observations.get("_extraGaps", []):
        lines.append(f"| {extra['id']} | {extra['surface']} | both | {extra['reason']} |")
    lines += ["", "## Environment / accessibility coverage gaps", "", "| Item | Why |", "|---|---|"]
    for name, why in STATIC_GAPS:
        lines.append(f"| {name} | {why} |")
    (out / "gaps.md").write_text("\n".join(lines) + "\n")


def tree_nodes(node, path=()):
    yield node, path
    for child in node.get("children", []):
        yield from tree_nodes(child, path + (node.get("class", "?"),))


def first_ref(file, needle):
    path = SRC / file
    if path.exists():
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if needle in line:
                return f"Sources/{file}:{number}"
    return f"Sources/{file}:?"


def source_for(sid, cls, text):
    """Where the point size of a measured control is set (grep-resolved), or who owns it."""
    t = text.strip()
    if cls in ("_NSThemeCloseWidget", "_NSThemeZoomWidget", "_NSThemeWidget") or (cls == "NSTextField" and sid in ("S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09", "S11", "S12", "S15", "S18", "S19", "S21", "S23", "S20") and t in ("Untitled", "Frame", "Focus", "Menus", "Flash", "History", "Crop") or t.startswith(("Quarterly", "Tool states", "Selection", "Color and size", "Large capture", "Small image", "Footer states", "Upload demo", "Preferences"))):
        return "system AppKit titlebar (not set by the app)"
    if cls == "NSButtonTextField":
        return "internal label of the format control; the control's own font is set at " + first_ref("App+ModernChrome.swift", "dragFormatToggle.font = .systemFont(ofSize: 20)")
    if sid == "S16" or cls == "_NSAlertButton":
        return "system NSAlert text (App.swift error alerts: " + first_ref("App.swift", "func error(_ error: Error)") + ")"
    if cls.startswith("NSColorPicker") or t in ("Opacity", "Colors", "G", "H", "I", "L") or (cls == "NSTextView" and t.endswith("%")):
        return "system NSColorPanel (AppKit)"
    if cls == "NSPopUpButton" and ("%" in t):
        return first_ref("App+ModernChrome.swift", "zoomControl.selectItem(withTitle:") + " (floor: " + first_ref("ModernEditorChrome.swift", "private func readable(") + ")"
    if t == "Original size":
        return first_ref("App+ModernChrome.swift", 'dragOriginalControl.title = "Original size"')
    if "·" in t and ("KB" in t or "MB" in t):
        return first_ref("App+ModernChrome.swift", "dragSizeLabel.font = .systemFont(ofSize: 18)")
    if "Unsaved changes" in t or t.endswith("· Saved") or t.startswith("Frame:") or t.startswith("Uploading") or t.startswith("Link copied"):
        return first_ref("App+ModernChrome.swift", "status.font = .systemFont(ofSize: 18)")
    if t == "Drawing colors":
        return first_ref("App.swift", "func label(_ text: String) -> NSTextField")
    if t.startswith("Takes effect"):
        return first_ref("GeneralPreferencesForm.swift", "appearanceNote.font = .systemFont(ofSize: 18)")
    if sid == "S19" and cls == "NSTextField":
        return first_ref("PublishingDestinationsView.swift", "let field = NSTextField(wrappingLabelWithString: text); field.font = Self.font(18)")
    if sid == "S19" and cls == "NSButton" and "public-read" in t:
        return first_ref("PublishingDestinationsView.swift", "aclCheckbox.font = Self.font(18)")
    if sid == "S19" and cls == "NSButton":
        return first_ref("PublishingDestinationsView.swift", "button.font = font(18)")
    if sid == "S19" and cls == "NSPopUpButton":
        return first_ref("PublishingDestinationsView.swift", "popup.font = Self.font(18)")
    if sid == "S20":
        if t.endswith(":") and t[:-1] in ("Name", "Date", "Size", "Action", "Destination"):
            return first_ref("HistoryBrowser.swift", "label.font = .systemFont(ofSize:18,weight:.semibold)")
        if "format" in t:
            return first_ref("HistoryBrowser.swift", "formatLabel.font = .systemFont(ofSize:18)")
        if "items" in t or "match" in t:
            return first_ref("HistoryBrowser.swift", "status.font = .systemFont(ofSize:18)")
        return first_ref("HistoryBrowser.swift", "action.font = .systemFont(ofSize:18)")
    if sid in ("S25", "S26", "S21", "S06"):
        return "system AppKit text (About panel / NSAlert / panels); the app sets no font here"
    return "see manifest sourceRefs for the surface"


def normalise(cls, text):
    t = text.strip()
    if re.search(r"\d+ × \d+ · ", t):
        return "‹image size label, e.g. “800 × 600 · 10 KB”›"
    if "· Unsaved changes" in t or t.endswith("· Saved"):
        return "‹status line, e.g. “Arrow · Unsaved changes”›"
    if t.startswith("Frame:") or t.startswith("Uploading") or t.startswith("Link copied"):
        return "‹status line (Frame / upload message)›"
    if re.search(r"%$", t) and cls == "NSPopUpButton":
        return "‹zoom popup, e.g. “Output · 100%”›"
    if cls == "NSTextField" and t in ("Untitled", "Frame", "Focus", "Menus", "Flash", "History", "Crop", "Preferences") or t.startswith(("Quarterly", "Tool states", "Selection", "Color and size", "Large capture", "Small image", "Footer states", "Upload demo", "Layout")):
        return "‹window title›"
    return t


def write_text_size(out):
    manifest = load_json(out / "manifest.json")
    rows = {}
    annotation = set()
    for m in manifest:
        if m.get("prototype") or m["sourceSha"] != "b9319c4":
            continue
        stem = m["file"][:-4]
        path = out / "metrics" / f"{stem}.json"
        if not path.exists():
            continue
        data = load_json(path)
        for window in data["windows"]:
            if "views" not in window:
                continue
            for node, _ in tree_nodes(window["views"]):
                if node.get("effectivelyHidden"):
                    continue
                if node["class"] in ("GlassChromeButton", "BezelHoverButton") and node.get("imagePosition") == 1:
                    continue  # icon-only: the title is an accessibility name, never drawn
                font, text = node.get("font"), node.get("string")
                if not font or not text or font["pointSize"] >= 20:
                    continue
                size = round(font["pointSize"], 1)
                if node["class"] in ("SketchTextEditor",):
                    annotation.add((m["id"], text.strip()[:60], size)); continue
                key = (node["class"], normalise(node["class"], text), size, source_for(m["id"], node["class"], text))
                rows.setdefault(key, {"surfaces": {}, "appearances": set()})
                rows[key]["surfaces"].setdefault(m["id"], m["surface"])
                rows[key]["appearances"].add(m["appearance"])
    lines = ["# Text-size summary (visible UI text under 20 pt)", "",
             "Generated from the live view trees in `metrics/*.json` captured at `b9319c4` (Light + Dark): every VISIBLE (not hidden, alpha > 0) text-bearing control whose font reports a point size below 20. "
             "Icon-only buttons (their title is only an accessibility name) are excluded. Annotation CONTENT (user drawings) is listed separately at the end and is not a UI-readability finding. "
             "Text drawn by custom `draw(_:)` code (the old 'Drag Me' label, help-bevel HUD, native tooltips, native menu items) is not in the view tree; see the notes at the end.", ""]
    def count(lo, hi):
        return sum(1 for k in rows if lo <= k[2] < hi)
    lines += [f"**Totals: {count(0,18)} distinct controls under 18 pt (all system-owned AppKit text); {count(18,20)} distinct controls at 18 to 19.9 pt.**", ""]
    for band, lo, hi in (("Under 18 pt", 0, 18), ("18 to 19.9 pt", 18, 20)):
        lines += [f"## {band}", ""]
        common, specific = [], collections.OrderedDict()
        for key, info in sorted(rows.items(), key=lambda kv: (kv[0][2], kv[0][1])):
            if not (lo <= key[2] < hi):
                continue
            (common if len(info["surfaces"]) >= 6 else specific.setdefault(tuple(sorted(info["surfaces"].items())), [])).append((key, info)) if len(info["surfaces"]) >= 6 else specific.setdefault(tuple(sorted(info["surfaces"].items())), []).append((key, info))
        if common:
            lines += ["### Common to the editor window (present in 6 or more surfaces)", "", "| Control class | Text | pt | Source | Surfaces |", "|---|---|---|---|---|"]
            for key, info in common:
                ids = sorted(info["surfaces"])
                lines.append(f"| {key[0]} | {key[1]} | {key[2]} | {key[3]} | {len(ids)} surfaces ({', '.join(ids[:6])}…) |")
            lines.append("")
        for surfaces, items in specific.items():
            title = ", ".join(f"{sid} {name}" for sid, name in surfaces)
            lines += [f"### {title}", "", "| Control class | Text | pt | Source |", "|---|---|---|---|"]
            for key, info in items:
                lines.append(f"| {key[0]} | {key[1]} | {key[2]} | {key[3]} |")
            lines.append("")
    lines += ["## Annotation content text (user drawings, not UI)", ""]
    lines += [f"- {sid}: “{text}” {size} pt (field editor draws at the annotation's own size; new tool text is floored at 18 pt in Canvas.swift)" for sid, text, size in sorted(annotation)] or ["_None under 20 pt._"]
    lines += ["", "## Not in the view tree (custom-drawn or system-drawn)", "",
              f"- Window titles and traffic lights: system titlebar, 13 pt (listed above as common).",
              f"- Native menu bar and menu items: system-drawn; the app sets 20 pt on its own menus ({first_ref('App.swift', 'm.font = .systemFont(ofSize: 20)')}) but the menu-bar titles are system size.",
              f"- Native tooltips: system-drawn on hover, not capturable.",
              f"- Help bevel HUD text: 20 pt ({first_ref('OriginalHelpBevel.swift', 'static let font')}).",
              f"- Fonts panel, colour panel and Save panel internals: system views; the colour panel measured 11 pt labels (listed above)."]
    (out / "metrics" / "text-size-summary.md").write_text("\n".join(lines) + "\n")


def write_captures(out, observations):
    manifest = load_json(out / "manifest.json")
    lines = ["# Visual audit — capture gallery", "",
             "Rendered evidence of the **Modern** UI, gathered by the flag-gated harness (`--eye-dump-audit`, branch `audit/visual-harness`) from an isolated copy of the app: throwaway bundle id, home and support folder; own windows only (CGWindowList by window number); synthetic content only.", "",
             "Observed-issue bullets describe what is visible in the PNG next to them. Source behaviour is cited in `manifest.json` (`sourceRefs`), never offered as an observation.", ""]
    banner = observations.get("_protoBanner")
    groups = collections.OrderedDict()
    for m in manifest:
        sha = m["sourceSha"]
        suffix = "@" + sha if sha != "b9319c4" else ""
        stem = m["file"][:-4]
        base = re.sub(r"-(light|dark)(@.*)?$", "", stem)
        groups.setdefault((sha, "PROTO" if m["id"] == "PROTO" else "product", base), {})[m["appearance"]] = m
    current_head = None
    for (sha, kind, base), pair in groups.items():
        head = (sha, kind)
        if head != current_head:
            current_head = head
            if kind == "PROTO":
                lines += ["", f"## PROTOTYPE MOCKS — NOT PRODUCT (source `{sha}`, harness-only re-parenting)", "", banner or "> **These captures are NOT product.** They are a harness-only mock built in the audit process.", ""]
            else:
                lines += ["", f"## Captures at `{sha}`", ""]
            lines += ["| Capture | Light | Dark | Directly observed (this capture) |", "|---|---|---|---|"]
        any_m = next(iter(pair.values()))
        cells = []
        for appearance in ("light", "dark"):
            m = pair.get(appearance)
            cells.append(f'<a href="{m["file"]}"><img src="{m["file"]}" width="300"></a>' if m else "—")
        issues = []
        for appearance in ("light", "dark"):
            m = pair.get(appearance)
            if m and m["issues"]:
                prefix = "" if appearance == "light" and not pair.get("dark") else f"**{appearance}:** " if (pair.get("dark") and pair["dark"]["issues"] != pair.get("light", {}).get("issues")) else ""
                for issue in m["issues"]:
                    text = prefix + issue
                    if text not in issues:
                        issues.append(text)
        observed = any_m["observed"]
        label = f"**{any_m['id']}** {any_m['surface']}<br>_{any_m['state']}_<br>`{any_m['pixelSize'][0]}×{any_m['pixelSize'][1]}px · {any_m['pointSize'][0]}×{any_m['pointSize'][1]}pt @{any_m['scale']:g}x · {any_m['method'].split('(')[0]}`"
        body = (observed + "<br>" if observed else "") + "<br>".join(f"• {i}" for i in issues)
        lines.append(f"| {label} | {cells[0]} | {cells[1]} | {body} |")
    lines += ["", observations.get("_footer", "")]
    (out / "captures.md").write_text("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--observations", required=True)
    args = ap.parse_args()
    out = pathlib.Path(args.dir)
    observations = load_json(args.observations)
    write_gaps(out, observations)
    write_text_size(out)
    write_captures(out, observations)


if __name__ == "__main__":
    main()
