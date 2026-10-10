#!/usr/bin/env python3
"""Pack one tools/eye-dump-audit.sh run into a small, committable evidence folder (writes only to --out).

  python3 -I tools/eye-dump-evidence-pack.py --raw RUNDIR --out DIR --sha SHA --before DIR2 --before-sha SHA2 [--notes FILE] [--title TEXT]

Keeps ONE copy of each capture (the sf icon-mode PNG, scaled to --max-width, optimised), a minified per-capture layout JSON,
manifest.json (sourceSha per capture), safety.txt, and a captures.md index with each capture's pre-change twin listed by path
(the twins are referenced, never copied). Metrics/AX trees stay out: they are large and live in the raw run folder.
"""
import argparse, json, pathlib, re, shutil, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parent.parent
WIDTHS = {"980xmin": "980", "1024x740": "1024", "1280x800": "1280", "1440x900": "1440"}


def before_stem(c):
    """Stem (without appearance/sha) of the pre-rail-removal capture that shows the same thing, or None."""
    i, slug = c["id"], c["slug"]
    special = {("S15", "flash-peak"): "S15-flash-full", ("S15", "flash-half"): "S15-flash-full",
               ("S16", "permission-sheet"): "S16-permission-alert",
               # OSN-043: the alerts were system NSAlerts in a modal window; they are app-owned sheets now.
               ("S39", "discard-sheet"): "S26-close-unsaved", ("S39", "upload-error-sheet"): "S21-publish-error",
               ("S26", "close-unsaved"): "S26-close-unsaved", ("S26", "rename"): "S26-rename", ("S26", "error-generic"): "S26-error-generic",
               ("S26", "history-hide"): "S26-history-hide", ("S26", "history-trash"): "S26-history-trash",
               ("S21", "publish-error"): "S21-publish-error",
               # OSN-054: the upload states live in the status slot at two widths; each is compared with the same state before.
               **{("S21", f"publish-{kind}{part}-{w}"): f"S21-publish-{kind}{part}" for kind in ("progress", "success", "error") for part in ("", "-footer") for w in ("w980", "w1280")},
               ("S21", "publish-error-details-w980"): "S21-publish-error", ("S21", "publish-error-details-w1280"): "S21-publish-error",
               # Audit fix 1: 1440 has no pre-change capture of its own; the 1280 one is the nearest (same states, 160 pt less slot).
               **{("S21", f"publish-{kind}{part}-w1440"): f"S21-publish-{kind}{part}-w1280" for kind in ("progress", "success", "error") for part in ("", "-footer")},
               ("S21", "publish-error-details-w1440"): "S21-publish-error-details-w1280",
               # The remove-destination question was a system NSAlert; the new one is an app-owned sheet on the destinations sheet.
               ("S26", "remove-destination"): "S26-remove-destination",
               # The Wipe tooltip plate is the same plate as the zoom control's: its pre-change twin is the zoom tooltip over the footer.
               ("S38", "tooltip-wipe-annotations-w980"): "S38-tooltip-zoom-w980", ("S38", "tooltip-wipe-image-w980"): "S38-tooltip-zoom-w980", ("S38", "tooltip-wipe-blank-w980"): "S38-tooltip-zoom-w980",
               # The titled window with subtitle is compared with the same window before: the plain "OpenSnap" title bar.
               ("S39", "titled-window-w980"): "S11-width-980", ("S39", "titled-window-w1280"): "S11-width-1280",
               ("S39", "titlebar-crop-w980"): "S01-editor-empty", ("S39", "titlebar-crop-w1280"): "S01-editor-empty"}
    if (i, slug) in special:
        return special[(i, slug)]
    if i == "S40":
        # OSN-044: each state capture is compared with the closest pre-change capture of the same control.
        s40 = {"tool-selected-rest": "S04-tool-brush", "tool-hover": "S04-tool-hover", "tool-pressed": "S04-tool-pressed", "tool-disabled": "S04-controls-disabled",
               "tool-focus": "S28-focus-topbar-tool", "tool-selected-focus": "S28-focus-topbar-tool", "tool-selected-hover": "S04-tool-hover", "tool-selected-pressed": "S04-tool-pressed",
               "snap-rest": "S03-topbar", "snap-hover": "S04-snap-hover", "snap-pressed": "S04-snap-hover", "snap-disabled": "S04-controls-disabled", "snap-focus": "S28-focus-topbar-snap",
               "size-pill-rest": "S03-topbar", "size-pill-hover": "S03-topbar", "size-pill-pressed": "S03-topbar", "size-pill-disabled": "S04-controls-disabled", "size-pill-focus": "S03-topbar",
               "size-track-hover": "S30-size-popover-w980", "size-track-pressed": "S30-size-popover-w980", "size-preset-hover": "S30-size-popover-w980",
               "swatch-states": "S31-color-popover-w980", "undo-hover": "S03-bottombar", "wipe-pressed": "S03-bottombar", "undo-wipe-disabled": "S04-controls-disabled",
               "undo-focus": "S28-focus-footer-zoom", "drag-rest": "S03-bottombar", "drag-hover": "S03-bottombar", "drag-pressed": "S03-bottombar", "drag-focus": "S28-focus-footer-upload",
               "toggle-png": "S09-format-toggle-png", "toggle-jpg": "S09-format-toggle-jpg", "toggle-hover": "S09-format-toggle-png", "toggle-pressed": "S09-format-toggle-png",
               "toggle-focus": "S09-format-toggle-png", "toggle-disabled": "S09-format-toggle-png", "border-rest": "S01-editor-empty", "border-hover": "S01-editor-empty", "border-crop-tool": "S01-editor-empty"}
        return s40.get(slug)
    if (i, slug) == ("S20", "history-tile-hover"):
        return "S20-history-selected"
    if i in ("S13", "S14", "S29"):
        return f"{i}-{slug}"  # capture-surface runs keep the same slug; a missing twin just prints a dash
    if i == "S11E":
        spec = slug.removeprefix("empty-size-")
        return f"S11-width-{WIDTHS[spec]}" if spec in WIDTHS else "S11-size-maximized" if spec == "full" else None
    if i == "S11F":
        return "S11-size-fullscreen"
    if i == "S12":
        return slug if slug in ("frame-mode", "frame-resnap", "frame-w980", "frame-w1024") and True else None
    table = {
        ("S01", "editor-empty"): "S01-editor-empty", ("S02", "populated"): "S02-populated", ("S03", "topbar"): "S03-topbar",
        ("S30", "size-popover-w980"): "S06-size-mid", ("S30", "size-popover-w1280"): "S06-size-mid",
        ("S31", "color-popover-w980"): "S06-color-palette", ("S31", "color-popover-custom-w980"): "S31-color-popover-w980",
        ("S31", "color-popover-w1440"): "S31-color-popover-w980", ("S31", "color-popover-custom-w1440"): "S31-color-popover-w980",
        ("S31", "color-popover-only-custom-w980"): "S31-color-popover-only-w980",
        ("S31", "color-popover-only-w1440"): "S31-color-popover-only-w980", ("S31", "color-popover-only-custom-w1440"): "S31-color-popover-only-w980",
        ("S32", "frame-large-w980"): "S12-frame-w980",
        ("S33", "large-shot-w980"): "S07-large-fit", ("S33", "large-shot-w980-bottombar"): "S09-footer",
        ("S34", "small-canvas-w980"): "S07-small-centred", ("S34", "small-canvas-w1280"): "S07-small-centred", ("S34", "small-canvas-w1440"): "S07-small-centred",
        ("S35", "large-canvas-w980"): "S07-large-fit", ("S35", "large-canvas-w1280"): "S07-large-fit",
        ("S36", "selection-w980"): "S05-selection-rect", ("S36", "selection-w1280"): "S05-selection-rect",
        ("S36", "text-editing-w980"): "S05-text-editing", ("S36", "text-editing-w1280"): "S05-text-editing",
        ("S37", "format-png-w980"): "S09-format-toggle-png", ("S37", "format-jpg-w980"): "S09-format-toggle-jpg",
    }
    if (i, slug) in table:
        return table[(i, slug)]
    if i == "S11M":
        spec = slug.removeprefix("size-")
        return None if spec not in WIDTHS and spec != "full" else None  # populated matrix has no pre-change twin
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--sha", required=True)
    ap.add_argument("--before", required=True, help="pre-change evidence dir, referenced by path only")
    ap.add_argument("--before-sha", required=True)
    ap.add_argument("--before-also", action="append", default=[], help="further pre-change dirs searched when --before has no twin (repeatable; names without @sha accepted)")
    ap.add_argument("--max-width", type=int, default=1200)
    ap.add_argument("--notes", help="markdown appended to captures.md")
    ap.add_argument("--title", default="Rail-removal visual acceptance captures")
    args = ap.parse_args()
    from PIL import Image

    raw, out, before = pathlib.Path(args.raw), pathlib.Path(args.out), pathlib.Path(args.before)
    run = json.loads((raw / "manifest.json").read_text())
    sf = [c for c in run["captures"] if c["iconMode"] == "sf"]
    shutil.rmtree(out, ignore_errors=True)
    (out / "layout").mkdir(parents=True)
    packed, rows = [], []
    for c in sorted(sf, key=lambda c: (c["id"], c["slug"], c["appearance"])):
        src = raw / c["file"]
        stem = pathlib.Path(c["file"]).stem
        dst = out / f"{stem}@{args.sha}.png"
        im = Image.open(src)
        stored = [im.width, im.height]
        if im.width > args.max_width:
            im = im.resize((args.max_width, max(1, round(im.height * args.max_width / im.width))), Image.LANCZOS)
            stored = [im.width, im.height]
        im.save(dst)
        if dst.stat().st_size > 150_000:
            subprocess.run(["/opt/homebrew/bin/pngquant", "--quality", "85-95", "--speed", "1", "--force", "--ext", ".png", str(dst)], check=False, capture_output=True)
        subprocess.run(["/opt/homebrew/bin/oxipng", "-o", "2", "--strip", "safe", "-q", str(dst)], check=False, capture_output=True)
        layout_src = raw / "raw-sf" / "layout" / f"{stem}.json"
        layout_rel = None
        if layout_src.is_file():
            layout_rel = f"layout/{stem}@{args.sha}.json"
            (out / layout_rel).write_text(json.dumps(json.loads(layout_src.read_text()), separators=(",", ":"), ensure_ascii=False))
        # The mapped twin first, then the same id and slug: later runs keep the slug, so an earlier folder may hold exactly that capture.
        before_rel = None
        stems = [x for x in (before_stem(c), f"{c['id']}-{c['slug']}") if x]
        for bs in stems:
            # Older evidence folders hold some twins without the @sha suffix.
            cand = next((p for p in (before / f"{bs}-{c['appearance']}@{args.before_sha}.png", before / f"{bs}-{c['appearance']}.png") if p.is_file()), None)
            for extra in args.before_also:
                if cand: break
                d = pathlib.Path(extra)
                cand = next((p for p in sorted(d.glob(f"{bs}-{c['appearance']}@*.png")) + [d / f"{bs}-{c['appearance']}.png"] if p.is_file()), None)
            if cand:
                before_rel = str(cand.relative_to(REPO)) if cand.is_absolute() and str(cand).startswith(str(REPO)) else str(cand)
                break
        entry = {k: c[k] for k in ("id", "slug", "surface", "state", "appearance", "iconMode", "windowSize", "pixelSize", "pointSize", "scale", "sourceSha", "method")}
        entry.update({"file": dst.name, "storedPixelSize": stored, "downscaled": stored != c["pixelSize"], "layout": layout_rel, "before": before_rel})
        packed.append(entry)
    unavailable = run.get("unavailable", [])
    manifest = {"sourceSha": args.sha, "bundleId": run.get("bundleId"), "iconMode": "sf",
                "faMode": "FA unavailable: no FontAwesome7Pro subset fonts are bundled in this build, so every capture uses SF Symbols (nothing was faked)",
                "captureCount": len(packed), "unavailable": unavailable, "gaps": run.get("gaps", []), "captures": packed}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    shutil.copy2(raw / "safety.txt", out / "safety.txt")

    L = [f"# {args.title}", "", f"Source `{args.sha}`; icon mode **sf** (FA unavailable); {len(packed)} captures, every PNG scaled to at most {args.max_width} px wide.",
         f"Pre-change twins are referenced from `{before}` at `{args.before_sha}`; they are not copied.", "",
         "| Capture | Appearance | Window pt | What it shows | Layout JSON | BEFORE (pre-change) |", "|---|---|---|---|---|---|"]
    for e in packed:
        win = "×".join(str(int(v)) for v in e["windowSize"]) if e.get("windowSize") else "—"
        L.append(f"| `{e['file']}` | {e['appearance']} | {win} | {e['state'].replace('|', '/')} | `{e['layout'] or '—'}` | {('`' + e['before'] + '`') if e['before'] else '—'} |")
    L.append("")
    if args.notes:
        L.append(pathlib.Path(args.notes).read_text())
    (out / "captures.md").write_text("\n".join(L) + "\n")
    total = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
    print(f"{len(packed)} captures, total {total/1e6:.2f} MB ({sum(f.stat().st_size for f in out.glob('*.png'))/1e6:.2f} MB PNG)")


if __name__ == "__main__":
    sys.exit(main())
