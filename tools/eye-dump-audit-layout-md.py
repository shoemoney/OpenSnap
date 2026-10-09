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
    for s_ in data["samples"]:
        top, bottom, vp = s_.get("topBar", {}), s_.get("bottomBar", {}), s_.get("viewport", {})
        ts, bs = top.get("slack", {}), bottom.get("slack", {})
        sw = bottom.get("statusWidths", {})
        summary.append({
            "scenario": s_["scenario"], "windowWidth": s_["windowWidth"], "frameMode": s_["frameMode"], "rail": s_.get("rail"),
            "topGroupWidths": {k: (v["frame"][2] if v else None) for k, v in top.get("groups", {}).items()},
            "topRowWidth": ts.get("rowWidth"), "topFreeHorizontal": ts.get("freeHorizontal"), "topMinGap": ts.get("minGap"), "topGaps": ts.get("gaps"),
            "bottomGroupWidths": {k: (v["frame"][2] if v else None) for k, v in bottom.get("groups", {}).items()},
            "bottomRowWidth": bs.get("rowWidth"), "bottomFreeHorizontal": bs.get("freeHorizontal"), "bottomMinGap": bs.get("minGap"),
            "statusLabelWithCheckbox": sw.get("withCheckbox", {}).get("statusLabel"), "statusLabelWithoutCheckbox": sw.get("withoutCheckbox", {}).get("statusLabel"),
            "statusNeedsAt18pt": sw.get("statusNeedsAt18pt"), "statusTruncated": bottom.get("statusTruncated"),
            "viewportSize": vp.get("rect", [0, 0, 0, 0])[2:4] if vp else None, "viewportTrailingMargin": vp.get("trailingMargin"),
        })
    full = {"sourceSha": args.sha, "measuredLive": True, "summary": summary, "statusTextWidthsAt18pt": data["statusTextWidthsAt18pt"],
            "samples": data["samples"], "prototype": protos, "units": "points; frames are window coordinates, top-left origin; fitting = NSView.fittingSize"}
    (out / "layout-width-budget.json").write_text(json.dumps(full, indent=2) + "\n")

    L = [f"# Layout width budget (measured live at `{args.sha}`)", "",
         "Real frames and `fittingSize` read from the running Modern editor (Light appearance; width does not depend on appearance) at four window widths, normal and Frame mode, with a small image (Original-size checkbox hidden) and a large image (checkbox visible). All numbers are points. Raw data: `layout-width-budget.json`.", ""]
    L += ["**Typical status string at 18 pt:** " + ", ".join(f"“{k}” = {v:g} pt" for k, v in list(data["statusTextWidthsAt18pt"].items())[:4]), ""]
    for scenario in ("small-image", "large-image"):
        L += [f"## Scenario: {scenario}", "",
              "| Window | Mode | rail | Top row | Top free | Top min gap | Bottom row | Bottom free | Status label w/ checkbox | w/o checkbox | Status needs 18pt | Viewport W×H | Trailing margin |",
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for item in summary:
            if item["scenario"] != scenario:
                continue
            vs = item["viewportSize"] or ["—", "—"]
            L.append(f"| {fmt(item['windowWidth'],0)} | {'Frame' if item['frameMode'] else 'normal'} | {item['rail']} | {fmt(item['topRowWidth'])} | {fmt(item['topFreeHorizontal'])} | {fmt(item['topMinGap'])} | "
                     f"{fmt(item['bottomRowWidth'])} | {fmt(item['bottomFreeHorizontal'])} | {fmt(item['statusLabelWithCheckbox'])} | {fmt(item['statusLabelWithoutCheckbox'])} | "
                     f"{fmt(item['statusNeedsAt18pt'])}{' TRUNCATED' if item['statusTruncated'] else ''} | {fmt(vs[0])}×{fmt(vs[1])} | {fmt(item['viewportTrailingMargin'])} |")
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
        for bar in ("topBar", "bottomBar"):
            for gid, g in s.get(bar, {}).get("groups", {}).items():
                row(f"**{gid}**", g)
                for c in (g or {}).get("controls", []):
                    row(f"  · {c.get('label') or c.get('contentLabel') or c.get('class')}", c)
        f = s.get("bottomBar", {})
        for key in ("zoomPopup", "originalSizeCheckbox", "status", "statusRow"):
            row(f"bottom bar {key}", f.get(key))
        vp = s.get("viewport", {})
        L.append(f"| viewport rect | {fmt(vp.get('rect', [0,0,0,0])[2])}×{fmt(vp.get('rect', [0,0,0,0])[3])} | — | — |")
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
