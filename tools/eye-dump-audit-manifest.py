#!/usr/bin/env python3
"""Write OUTDIR/manifest.json from the raw-<icons>/meta/*.json files one tools/eye-dump-audit.sh run produced.

  python3 -I tools/eye-dump-audit-manifest.py OUTDIR --sha SHA --bundle-id ID

Every capture entry carries sourceSha, surface id, appearance, window size, icon mode and the display options the app resolved
(injected by --display, or the system's own state; "injected" says which). Icon modes that could not run
(Font Awesome not bundled) are listed under "unavailable" with the reason, never captured as something else.
"""
import argparse, json, pathlib, sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out")
    parser.add_argument("--sha", required=True)
    parser.add_argument("--bundle-id", default="")
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    captures, unavailable, gaps = [], [], []
    for raw in sorted(out.glob("raw-*")):
        icon_mode = raw.name.removeprefix("raw-")
        note = raw / "icon-mode-unavailable.json"
        if note.is_file():
            unavailable.append({"iconMode": icon_mode, **json.loads(note.read_text())})
        for meta_file in sorted((raw / "meta").glob("*.json")):
            meta = json.loads(meta_file.read_text())
            captures.append({
                "id": meta["id"], "slug": meta["slug"], "surface": meta["surface"], "state": meta["state"],
                "appearance": meta["appearance"], "iconMode": meta.get("iconMode", icon_mode),
                "displayOptions": meta.get("displayOptions"), "windowSize": meta.get("windowSize"), "pixelSize": meta["pixelSize"], "pointSize": meta["pointSize"], "scale": meta["scale"],
                "sourceSha": meta.get("sourceSha", args.sha), "method": meta["method"], "sourceRefs": meta["sourceRefs"],
                "file": f"{raw.name}/{meta['file']}",
            })
        for gap_file in sorted((raw / "gapsraw").glob("*.json")):
            gaps.extend(json.loads(gap_file.read_text()))
    injected = sorted({tuple(c["displayOptions"]["active"]) for c in captures if (c.get("displayOptions") or {}).get("injected")})
    manifest = {"sourceSha": args.sha, "bundleId": args.bundle_id, "injectedDisplayOptions": [list(group) for group in injected],
                "captureCount": len(captures), "captures": captures,
                "unavailable": unavailable, "gaps": gaps}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(captures)} captures, {len(unavailable)} unavailable icon modes, {len(gaps)} gap records")
    return 0


if __name__ == "__main__":
    sys.exit(main())
