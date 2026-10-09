#!/usr/bin/env python3
"""Turn layout/budget-<sha>.json (+ proto-*.json) into layout-width-budget.json and layout-width-budget.md.

  python3 -I tools/eye-dump-audit-layout-md.py --dir DOCDIR --sha 4b2ae0f
"""
import argparse, json, pathlib


def fmt(v, nd=1):
    if v is None:
        return "—"
    return f"{v:.{nd}f}".rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def w(box):
    return box["frame"][2] if box else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--sha", required=True)
    args = ap.parse_args()
    out = pathlib.Path(args.dir)
    data = json.loads((out / "layout" / f"budget-{args.sha}.json").read_text())
    protos = {}
    for f in sorted((out / "layout").glob(f"proto-*-{args.sha}.json")):
        protos[f.stem.split("-")[1]] = json.loads(f.read_text())

    summary = []
    for s in data["samples"]:
        h = s.get("header", {})
        slack = s.get("headerSlack", {})
        rail = s.get("railColumn", {})
        footer = s.get("footer", {})
        fs = footer.get("slack", {})
        sv = s.get("scrollView", {})
        summary.append({
            "scenario": s["scenario"], "windowWidth": s["windowWidth"], "frameMode": s["frameMode"],
            "headerGroupWidths": {k: (v["frame"][2] if v else None) for k, v in h.items()},
            "headerGroupFittingWidths": {k: (v["fitting"][0] if v else None) for k, v in h.items()},
            "headerRowWidth": slack.get("rowWidth"), "headerFreeHorizontal": slack.get("totalFreeHorizontal"),
            "headerGapLeadingToTools": slack.get("leadingToTools"), "headerGapToolsToTrailing": slack.get("toolsToTrailing"),
            "railColumnWidth": rail.get("railWidth"), "railColumnAreaPt2": rail.get("areaPt2"), "railBlankAreaPt2": rail.get("blankAreaPt2"),
            "railBlankPctOfWindow": rail.get("blankPctOfWindow"), "railBlankPctOfContent": rail.get("blankPctOfContent"),
            "footerRowWidth": fs.get("rowWidth"), "footerFreeHorizontal": fs.get("totalFree"), "footerStatusTruncated": fs.get("statusTruncated"),
            "footerStatusFrameWidth": fs.get("statusLabelFrameWidth"), "footerStatusNeedsAt18pt": fs.get("statusLabelNeedsAt18pt"),
            "scrollViewSize": sv.get("frame", [0, 0, 0, 0])[2:4] if sv else None,
            "scrollTrailingGapToWindowEdge": s.get("scrollTrailingGapToWindowEdge"),
        })
    full = {"sourceSha": args.sha, "measuredLive": True, "summary": summary, "statusTextWidthsAt18pt": data["statusTextWidthsAt18pt"],
            "samples": data["samples"], "prototype": protos, "units": "points; frames are window coordinates, top-left origin; fitting = NSView.fittingSize"}
    (out / "layout-width-budget.json").write_text(json.dumps(full, indent=2) + "\n")

    L = [f"# Layout width budget (measured live at `{args.sha}`)", "",
         "Real frames and `fittingSize` read from the running Modern editor (Light appearance; width does not depend on appearance) at four window widths, normal and Frame mode, with a small image (Original-size checkbox hidden) and a large image (checkbox visible). All numbers are points. Raw data: `layout-width-budget.json`.", ""]
    L += ["**Typical status string at 18 pt:** " + ", ".join(f"“{k}” = {v:g} pt" for k, v in list(data["statusTextWidthsAt18pt"].items())[:4]), ""]
    for scenario in ("small-image", "large-image"):
        L += [f"## Scenario: {scenario}", "",
              "| Window | Mode | Header row | Σ header groups | Header free | gap lead→tools / tools→trail | Rail col W | Rail BLANK pt² | Rail blank % window | Scroll view W×H | Scroll→window-edge | Footer free | Status W / needs |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for item, s in zip(summary, data["samples"]):
            if item["scenario"] != scenario:
                continue
            gw = item["headerGroupWidths"]
            tot = sum(v for v in gw.values() if v)
            sv = item["scrollViewSize"] or ["—", "—"]
            L.append(f"| {fmt(item['windowWidth'],0)} | {'Frame' if item['frameMode'] else 'normal'} | {fmt(item['headerRowWidth'])} | {fmt(tot)} | {fmt(item['headerFreeHorizontal'])} | "
                     f"{fmt(item['headerGapLeadingToTools'])} / {fmt(item['headerGapToolsToTrailing'])} | {fmt(item['railColumnWidth'])} | {fmt(item['railBlankAreaPt2'],0)} | {fmt(item['railBlankPctOfWindow'])}% | "
                     f"{fmt(sv[0])}×{fmt(sv[1])} | {fmt(item['scrollTrailingGapToWindowEdge'])} | {fmt(item['footerFreeHorizontal'])} | {fmt(item['footerStatusFrameWidth'])} / {fmt(item['footerStatusNeedsAt18pt'])}{' TRUNCATED' if item['footerStatusTruncated'] else ''} |")
        L.append("")
    L += ["## Per-element frames and fitting sizes (normal mode, small image)", ""]
    for s in data["samples"]:
        if s["scenario"] != "small-image" or s["frameMode"]:
            continue
        L += [f"### Window {fmt(s['windowWidth'],0)}", "", "| Group / control | frame W×H | fitting W×H | hidden |", "|---|---|---|---|"]
        def row(name, box):
            if not box:
                return
            L.append(f"| {name} | {fmt(box['frame'][2])}×{fmt(box['frame'][3])} | {fmt(box['fitting'][0])}×{fmt(box['fitting'][1])} | {box.get('hidden')} |")
        for gid, g in s.get("header", {}).items():
            row(f"**{gid}**", g)
            for c in (g or {}).get("controls", []):
                row(f"  · {c.get('label') or c.get('contentLabel') or c.get('class')}", c)
        for gid, g in s.get("rail", {}).items():
            row(f"**{gid}** (rail)", g)
            for c in (g or {}).get("controls", []):
                row(f"  · {c.get('label') or c.get('contentLabel') or c.get('class')}", c)
        f = s.get("footer", {})
        for key in ("zoomPopup", "originalSizeCheckbox", "dragSizeLabel", "status", "statusRow"):
            row(f"footer {key}", f.get(key))
        g = f.get("footerRowGroup")
        row("**GlassFooterRow**", g)
        for c in (g or {}).get("controls", []):
            row(f"  · {c.get('label') or c.get('contentLabel') or c.get('class')}", c)
        row("scroll view", s.get("scrollView"))
        row("canvas", s.get("canvasFrame"))
        L.append("")
    if protos:
        L += ["## PROTOTYPE MOCK fit (NOT product; harness-only re-parenting)", "",
              "| Appearance | Width | Mode | Top row needs | Top available | Top slack (− = overflow) | Bottom sum (excl. status) | Bottom available | Bottom slack | Status needs 18pt | Bottom overflow if status fully shown |", "|---|---|---|---|---|---|---|---|---|---|---|"]
        for appearance, p in protos.items():
            for s in p["samples"]:
                t, b = s.get("top", {}), s.get("bottom", {})
                L.append(f"| {appearance} | {fmt(s['windowWidth'],0)} | {'Frame' if s['frameMode'] else 'normal'} | {fmt(t.get('sumOfGroupFittingPlusSpacing'))} | {fmt(t.get('availableWidth'))} | {fmt(t.get('slackOrOverflow'))} | "
                         f"{fmt(b.get('sumOfGroupFittingPlusSpacing'))} | {fmt(b.get('availableWidth'))} | {fmt(b.get('slackOrOverflow'))} | {fmt(b.get('statusNeedsAt18pt'))} | {fmt(b.get('bottomOverflowIfStatusFullyShown'))} |")
        L.append("")
    (out / "layout-width-budget.md").write_text("\n".join(L) + "\n")


if __name__ == "__main__":
    main()
