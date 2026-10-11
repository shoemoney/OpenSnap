#!/usr/bin/env python3
"""OSN-071 text walker over the captured layout data of raw harness runs (metrics/, meta/, layout/ JSON).
Usage: text-walker.py OUT.json RAW_RUN_DIR [RAW_RUN_DIR ...]
Violations: visible text below the 18 pt readable floor (DesignTokens.Typography), glass rows that are truncated or do not fit,
tooltip fonts below 18 pt. Reported but not violations: text-bearing controls between 18 and 20 pt (the 20 pt control floor is
waived for registered captions, which the capture data does not say), and status text truncation (counted per capture)."""
import json, sys
from pathlib import Path

FLOOR = 18.0
out_path, runs = Path(sys.argv[1]), [Path(p) for p in sys.argv[2:]]
violations, between, truncated, stats = [], [], [], {"captures": 0, "textNodes": 0, "smallestPt": None, "glassRows": 0}

# System-owned, exactly as tests/ViewTreeAudit.swift excludes them: the title bar and its widgets, the system colour and font panels, and
# AppKit's private NSButtonTextField inside a button (the owning button's own font is the one audited and drawn).
SYSTEM_ANCESTORS = {"NSTitlebarContainerView", "NSTitlebarView"}
SYSTEM_WINDOWS = {"NSColorPanel", "NSFontPanel"}
skipped = {"titleBarWidgetOrSystemPanel": 0, "systemPanel": 0, "privateButtonField": 0}

def walk(node, stem, path, system=False):
    if isinstance(node, dict):
        cls = node.get("class") or ""
        system = system or cls in SYSTEM_ANCESTORS or cls in SYSTEM_WINDOWS
        font, text = node.get("font"), node.get("string")
        if isinstance(font, dict) and isinstance(text, str) and text.strip() and (system or cls == "NSButtonTextField" or cls.startswith(("_NS", "NSTheme"))):
            skipped["systemPanel" if cls in SYSTEM_WINDOWS else "privateButtonField" if cls == "NSButtonTextField" else "titleBarWidgetOrSystemPanel"] += 1
        elif isinstance(font, dict) and isinstance(text, str) and text.strip():
            hidden = node.get("effectivelyHidden") or node.get("hidden") or node.get("alpha", 1) == 0
            if not hidden:
                size = float(font["pointSize"])
                stats["textNodes"] += 1
                stats["smallestPt"] = size if stats["smallestPt"] is None else min(stats["smallestPt"], size)
                rec = {"capture": stem, "class": node.get("class"), "pt": size, "text": text[:60], "path": path}
                if size < FLOOR: violations.append(rec)
                elif size < 20 and node.get("class", "").endswith(("Button", "PopUpButton", "TextField", "SegmentedControl")): between.append(rec)
        for k, v in node.items(): walk(v, stem, f"{path}/{k}", system)
    elif isinstance(node, list):
        for v in node: walk(v, stem, path, system)

for run in runs:
    base = run / "raw-sf"
    for f in sorted((base / "metrics").glob("*.json")):
        stats["captures"] += 1
        walk(json.loads(f.read_text()), f"{run.name}/{f.stem}", "")
    for f in sorted((base / "meta").glob("*.json")):
        m = json.loads(f.read_text()); stem = f"{run.name}/{f.stem}"
        for key in ("title", "message"):
            fnt = (m.get("fonts") or {}).get(key)
            if fnt and fnt["pointSize"] < FLOOR: violations.append({"capture": stem, "class": "alert " + key, "pt": fnt["pointSize"]})
        for fnt in (m.get("fonts") or {}).get("buttons", []):
            if fnt["pointSize"] < FLOOR: violations.append({"capture": stem, "class": "alert button", "pt": fnt["pointSize"]})
        if isinstance(m.get("tooltipFontPoints"), (int, float)) and m["tooltipFontPoints"] < FLOOR:
            violations.append({"capture": stem, "class": "tooltip", "pt": m["tooltipFontPoints"]})
        g = m.get("glassPanel")
        if g:
            if g.get("minFontSize") is not None and g["minFontSize"] < FLOOR: violations.append({"capture": stem, "class": "glass minFontSize", "pt": g["minFontSize"]})
            if g.get("truncatedRows"): violations.append({"capture": stem, "class": "glass truncatedRows", "rows": g["truncatedRows"]})
            for row in g.get("labelMetrics", []):
                stats["glassRows"] += 1
                if row.get("fits") is False or (row.get("font") or {}).get("pointSize", FLOOR) < FLOOR:
                    violations.append({"capture": stem, "class": "glass label", "title": row.get("title"), "fits": row.get("fits"), "pt": (row.get("font") or {}).get("pointSize")})
    for f in sorted((base / "layout").glob("*.json")):
        text = f.read_text()
        d = json.loads(text)
        for sample in [d] + (d.get("samples") or []):
            if isinstance(sample, dict) and sample.get("bottomBar", {}).get("statusTruncated"):
                truncated.append(f"{run.name}/{f.stem}"); break

result = {"floorPt": FLOOR, "stats": stats, "violationCount": len(violations), "violations": violations,
          "controlsBetween18And20": len(between), "controlsBetween18And20ByClassAndText": dict(__import__("collections").Counter(f"{b['class']} {b['pt']}pt {b['text'][:30]}" for b in between).most_common(40)), "skippedSystemOwnedNodes": skipped, "statusTruncatedCaptures": truncated}
out_path.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n")
print(f"captures walked {stats['captures']}, text nodes {stats['textNodes']}, glass rows {stats['glassRows']}, smallest {stats['smallestPt']} pt")
print(f"skipped system-owned/private nodes {skipped}")
print(f"violations {len(violations)}; controls 18-20 pt {len(between)}; status-truncated captures {len(truncated)}")
for v in violations[:25]: print("  ", v)
