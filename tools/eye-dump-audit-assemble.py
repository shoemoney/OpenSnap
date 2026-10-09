#!/usr/bin/env python3
"""Assemble an evidence folder (the --out path you give; nothing is written elsewhere) from the raw harness outputs and keep it under the size cap.

  python3 -I tools/eye-dump-audit-assemble.py --out DIR --b93 RAW [RAW...] --delta RAW [RAW...] --layout RAW --observations FILE --sha SHA
"""
import argparse, json, pathlib, shutil, subprocess, tempfile, re, sys
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent


def stage(dirs, dest, icons="sf"):
    for sub in ("metrics", "ax", "meta", "gapsraw", "layout"):
        (dest / sub).mkdir(parents=True, exist_ok=True)
    for d in map(pathlib.Path, dirs):
        # A run dir holds raw/ (older runs) or raw-<icons>/ (tools/eye-dump-audit.sh). One icon mode per assembly: file stems
        # repeat across modes, so assemble sf and fa separately.
        r = d / "raw" if (d / "raw").is_dir() else d / f"raw-{icons}" if (d / f"raw-{icons}").is_dir() else d
        if not r.is_dir():
            continue
        for pat, sub in (("*.png", ""), ("metrics/*.json", "metrics"), ("ax/*.json", "ax"), ("meta/*.json", "meta"), ("gapsraw/*.json", "gapsraw"),
                         ("layout/*.json", "layout"), ("menus*.json", ""), ("environment*.json", "")):
            for f in r.glob(pat):
                shutil.copy2(f, dest / sub / f.name if sub else dest / f.name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--b93", nargs="+", required=True)
    ap.add_argument("--delta", nargs="*", default=[])
    ap.add_argument("--layout", nargs="*", default=[])
    ap.add_argument("--observations", required=True)
    ap.add_argument("--sha", required=True)
    ap.add_argument("--max-width", type=int, default=1200)
    ap.add_argument("--baseline-sha", default="b9319c4")
    ap.add_argument("--icons", choices=["sf", "fa"], default="sf", help="which raw-<icons> folder of each run dir to assemble")
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    work = pathlib.Path(tempfile.mkdtemp(prefix="audit-assemble."))
    stage(args.b93 + args.delta + args.layout, work, args.icons)
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    py = sys.executable
    subprocess.run([py, "-I", str(ROOT / "tools/eye-dump-audit-report.py"), "--out", str(out), "--raw", str(work), "--observations", args.observations, "--baseline-sha", args.baseline_sha], check=True)
    subprocess.run([py, "-I", str(ROOT / "tools/eye-dump-audit-docs.py"), "--dir", str(out), "--observations", args.observations, "--baseline-sha", args.baseline_sha], check=True)
    if list((out / "layout").glob(f"budget-{args.sha}.json")):
        subprocess.run([py, "-I", str(ROOT / "tools/eye-dump-audit-layout-md.py"), "--dir", str(out), "--sha", args.sha], check=True)
    def prune(node):
        for key, default in (("acceptsFirstResponder", None), ("canBecomeKeyView", None), ("alpha", 1.0), ("hidden", False), ("effectivelyHidden", False), ("glassDepth", 0)):
            if key in node and (default is None or node[key] == default):
                del node[key]
        layer = node.get("layer")
        if layer and layer.get("cornerRadius", 0) == 0 and "backgroundColor" not in layer and "borderWidth" not in layer:
            del node["layer"]
        for child in node.get("children", []):
            prune(child)

    # metrics: minify, and drop the in-context duplicates' trees (the sheet-alone capture already carries the sheet's tree)
    for f in (out / "metrics").glob("*.json"):
        if "in-context" in f.name:
            f.unlink(); continue
        data = json.loads(f.read_text())
        for window in data.get("windows", []):
            if "views" in window:
                prune(window["views"])
        data["note"] = "default-valued keys (alpha 1, hidden false, glassDepth 0, acceptsFirstResponder, canBecomeKeyView, square layers) are omitted to stay under the size cap"
        f.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False))
    for f in (out / "ax").glob("*.json"):
        if "in-context" in f.name:
            f.unlink(); continue
        f.write_text(json.dumps(json.loads(f.read_text()), separators=(",", ":"), ensure_ascii=False))
    manifest = json.loads((out / "manifest.json").read_text())
    downscaled = 0
    for m in manifest:
        png = out / m["file"]
        im = Image.open(png)
        if im.mode == "RGBA" and m["id"] in ("S16", "S26", "S21") and "alert" in (m["state"] + m["surface"]).lower() or (im.mode == "RGBA" and m["id"] in ("S16", "S26", "S24")):
            alpha = im.getchannel("A")
            opaque = sum(1 for v in alpha.get_flattened_data() if v > 250) / (im.width * im.height) if hasattr(alpha, "get_flattened_data") else sum(1 for v in alpha.getdata() if v > 250) / (im.width * im.height)
            if opaque < 0.6:
                backdrop = (44, 42, 41, 255) if m["appearance"] == "dark" else (236, 236, 236, 255)
                base = Image.new("RGBA", im.size, backdrop); base.alpha_composite(im); im = base
                im.save(png); m["flattenedOnBackdrop"] = "#%02X%02X%02X" % backdrop[:3]
        m["storedPixelSize"] = [im.width, im.height]
        if im.width > args.max_width:
            r = args.max_width / im.width
            im = im.resize((args.max_width, max(1, round(im.height * r))), Image.LANCZOS)
            im.save(png); downscaled += 1
            m["storedPixelSize"] = [im.width, im.height]; m["downscaled"] = True
        if png.stat().st_size > 150_000:
            subprocess.run(["/opt/homebrew/bin/pngquant", "--quality", "85-95", "--speed", "1", "--force", "--ext", ".png", str(png)], check=False, capture_output=True)
        subprocess.run(["/opt/homebrew/bin/oxipng", "-o", "2", "--strip", "safe", "-q", str(png)], check=False, capture_output=True)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    shutil.copy2(args.observations, out / "observations.json")
    total = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
    print(f"{len(manifest)} captures, {downscaled} downscaled to <= {args.max_width}px wide, total {total/1e6:.1f} MB")
    shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
