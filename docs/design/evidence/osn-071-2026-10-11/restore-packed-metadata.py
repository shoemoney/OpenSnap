#!/usr/bin/env python3
"""Merge the raw run's per-capture manifest fields (glassPanel records, display options, requested surfaces) back into a packed
manifest, which tools/eye-dump-evidence-pack.py trims. Usage: restore-packed-metadata.py RAW_RUN_DIR PACKED_DIR"""
import json, sys
from pathlib import Path

raw, out = Path(sys.argv[1]), Path(sys.argv[2])
origin = json.loads((raw / "manifest.json").read_text())
path = out / "manifest.json"
packed = json.loads(path.read_text())
index = {(c["id"], c["slug"], c["appearance"], c["iconMode"]): c for c in origin["captures"]}
for c in packed["captures"]:
    for k, v in index[(c["id"], c["slug"], c["appearance"], c["iconMode"])].items():
        c.setdefault(k, v)
for k in ("injectedDisplayOptions", "requested"):
    if k in origin:
        packed[k] = origin[k]
packed.pop("displayOptions", None)
path.write_text(json.dumps(packed, indent=1, ensure_ascii=False) + "\n")
