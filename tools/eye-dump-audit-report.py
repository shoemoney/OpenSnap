#!/usr/bin/env python3
"""Assemble the visual-audit evidence directory from raw harness output.

  python3 -I tools/eye-dump-audit-report.py --out DOCDIR --raw RAWDIR [--raw RAWDIR2 ...] --observations observations.json

Copies PNGs + metrics/ax/meta, builds manifest.json (resolving "File.swift|needle" refs to Sources/File.swift:LINE,
adding sourceSha), gaps.md, captures.md and metrics/text-size-summary.md.
"""
import argparse, json, pathlib, re, shutil, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources"


def resolve_ref(ref: str) -> str:
    if "|" not in ref:
        return ref
    name, needle = ref.split("|", 1)
    path = SRC / name
    if path.exists():
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if needle in line:
                return f"Sources/{name}:{number}"
    return f"Sources/{name}:?"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--raw", action="append", required=True)
    ap.add_argument("--observations", required=True)
    ap.add_argument("--baseline-sha", default="b9319c4", help="captures at this sha sort first and carry no @sha suffix")
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    for sub in ("metrics", "ax", "layout"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    observations = json.loads(pathlib.Path(args.observations).read_text())
    manifest, gaps = [], []
    dropped = set(observations.get("_drop", []))

    def is_dropped(name: str) -> bool:
        base = re.sub(r"-(light|dark)(@.*)?(\.png|\.json)?$", "", name)
        return base in dropped

    for raw in map(pathlib.Path, args.raw):
        for png in sorted(raw.glob("*.png")):
            if is_dropped(png.name):
                continue
            shutil.copy2(png, out / png.name)
        for sub in ("metrics", "ax"):
            for f in (raw / sub).glob("*.json"):
                if not is_dropped(f.name):
                    shutil.copy2(f, out / sub / f.name)
        for f in raw.glob("menus*.json"):
            shutil.copy2(f, out / f.name)
        for f in raw.glob("environment*.json"):
            shutil.copy2(f, out / f.name)
        for f in (raw / "layout").glob("*.json"):
            shutil.copy2(f, out / "layout" / f.name)
        for f in (raw / "gapsraw").glob("*.json"):
            gaps.extend(json.loads(f.read_text()))
        for f in sorted((raw / "meta").glob("*.json")):
            meta = json.loads(f.read_text())
            stem = f.stem
            if is_dropped(stem):
                continue
            base = re.sub(r"-(light|dark)(@.*)?$", "", stem)
            suffix = ""
            if "@" in stem:
                suffix = "@" + stem.split("@", 1)[1]
            note = observations.get(stem) or observations.get(base + suffix) or observations.get(base) or {}
            manifest.append({
                "id": note.get("id", meta["id"]), "surface": note.get("surface", meta["surface"]), "state": note.get("state", meta["state"]), "appearance": meta["appearance"], "file": meta["file"],
                "pixelSize": meta["pixelSize"], "pointSize": meta["pointSize"], "scale": meta["scale"], "method": meta["method"],
                "sourceRefs": [resolve_ref(r) for r in meta["sourceRefs"]], "sourceSha": meta.get("sourceSha", "unknown"),
                "observed": note.get("observed", ""), "issues": note.get("issues", []),
                "windowSize": meta.get("windowSize"), "iconMode": meta.get("iconMode", "sf"),
                "windowAlpha": meta.get("windowAlpha"), "appActive": meta.get("appActive"), "prototype": bool(meta.get("prototype", False)),
            })
    manifest.sort(key=lambda m: (m["sourceSha"] != args.baseline_sha, m["id"], m["file"]))
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    (out / "gaps-raw.json").write_text(json.dumps(gaps, indent=2) + "\n")
    print(f"{len(manifest)} captures, {len(gaps)} raw gap records")


if __name__ == "__main__":
    sys.exit(main())
