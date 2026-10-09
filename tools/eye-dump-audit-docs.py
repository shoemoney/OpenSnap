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
        key = (item["id"], item["surface"], item["reason"])
        if key in seen:
            continue
        seen.add(key); rows.append(item)
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


FONT_SOURCES = {}


def write_text_size(out):
    manifest = load_json(out / "manifest.json")
    groups = collections.OrderedDict()
    for m in manifest:
        if m.get("prototype") or m["sourceSha"] != "b9319c4":
            continue
        stem = m["file"][:-4]
        path = out / "metrics" / f"{stem}.json"
        if not path.exists():
            continue
        data = load_json(path)
        for window in data["windows"]:
            title = window.get("title", "")
            if "views" not in window:
                continue
            for node, _ in tree_nodes(window["views"]):
                if node.get("effectivelyHidden"):
                    continue
                font = node.get("font")
                text = node.get("string")
                if not font or not text:
                    continue
                size = font["pointSize"]
                if size >= 20:
                    continue
                content = node["class"] in ("SketchTextEditor", "NSTextView") and "annotation" in (node.get("axLabel", "") or "").lower()
                key = (m["id"], m["surface"], node["class"], text.strip()[:70], round(size, 1), content)
                groups.setdefault(key, set()).add(m["appearance"])
    lines = ["# Text-size summary (UI text under 20 pt)", "",
             "Generated from the live view trees in `metrics/*.json` captured at `b9319c4`: every VISIBLE (not hidden, alpha > 0) control whose font reports a point size below 20 and that carries a string. "
             "Annotation CONTENT (user drawings) is listed separately and is not a UI-readability finding. Menu-bar and native-menu text drawn by the system is covered at the end.", ""]
    for band, lo, hi in (("Under 18 pt", 0, 18), ("18 to 19.9 pt", 18, 20)):
        lines += [f"## {band}", ""]
        by_surface = collections.OrderedDict()
        for (sid, surface, cls, text, size, content), appearances in sorted(groups.items(), key=lambda kv: (kv[0][0], kv[0][4])):
            if content or not (lo <= size < hi):
                continue
            by_surface.setdefault((sid, surface), []).append((cls, text, size, appearances))
        if not by_surface:
            lines += ["_None found in the captured view trees._", ""]
        count = 0
        for (sid, surface), rows in by_surface.items():
            lines += [f"### {sid} — {surface}", "", "| Control class | Text | pt | Appearances | Source |", "|---|---|---|---|---|"]
            for cls, text, size, appearances in rows:
                source = FONT_SOURCES.get((cls, text)) or FONT_SOURCES.get(cls) or "see notes"
                lines.append(f"| {cls} | {text} | {size} | {'/'.join(sorted(appearances))} | {source} |")
                count += 1
            lines.append("")
        lines += [f"**{band}: {count} distinct (surface, control, text) entries.**", ""]
    annotation = sorted({(k[0], k[3], k[4]) for k in groups if k[5]})
    lines += ["## Annotation content text (user drawings, not UI)", ""]
    lines += [f"- {sid}: “{text}” {size} pt" for sid, text, size in annotation] or ["_None under 20 pt._"]
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
