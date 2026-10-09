#!/usr/bin/env python3
"""G9: report (or, with --strict, fail on) literal fonts, colours and corner radii outside the design tokens.

Scans Sources/*.swift for
  font    ofSize: <digit>, Self.font(<digit>, NSFont(name: ..., size: <digit>
  color   NSColor(white:, .darkGray, NSColor(calibratedRed:, NSColor(deviceRed:
  radius  cornerRadius = <digit>
Default mode prints counts per file and per kind and exits 0 (the sweeps that remove the literals land later).
--strict exits 1 on any hit. --self-test proves --strict can fail. --sources DIR scans DIR instead of Sources/.
"""
from pathlib import Path
import argparse, re, subprocess, sys, tempfile

root = Path(__file__).resolve().parent.parent

PATTERNS = {
    "font": [r"ofSize:\s*[0-9]", r"Self\.font\([0-9]", r"NSFont\(name:[^)]*size:\s*[0-9]"],
    "color": [r"NSColor\(white:", r"\.darkGray\b", r"NSColor\(calibratedRed:", r"NSColor\(deviceRed:"],
    "radius": [r"cornerRadius\s*=\s*[0-9]"],
}
COMPILED = {kind: [re.compile(p) for p in patterns] for kind, patterns in PATTERNS.items()}

# Files where a literal is correct, with the reason. Keep this explicit: a new entry needs a reason.
EXEMPT = {
    "DesignTokens.swift": "the one place the literals are defined",
    "Canvas.swift": "annotation drawing: sizes and colours are document data, not chrome",
    "DocumentModel.swift": "document model: stored annotation colours and sizes",
    "SVGExport.swift": "writes document colours and sizes into SVG",
    "LegacyReader.swift": "reads the retired document format, whose values are data",
    "Migration.swift": "converts the retired document format, whose values are data",
    "StrokeFitting.swift": "stroke geometry maths, not chrome",
}


def scan(sources):
    """{file name: {kind: [(line number, text)]}} for every non-exempt file."""
    hits = {}
    for path in sorted(sources.glob("*.swift")):
        if path.name in EXEMPT:
            continue
        for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            for kind, patterns in COMPILED.items():
                if any(p.search(line) for p in patterns):
                    hits.setdefault(path.name, {}).setdefault(kind, []).append((number, line.strip()))
    return hits


def report(hits):
    totals = dict.fromkeys(PATTERNS, 0)
    for name, kinds in sorted(hits.items()):
        counts = {kind: len(lines) for kind, lines in kinds.items()}
        for kind, count in counts.items():
            totals[kind] += count
        print(f"  {name:36} " + "  ".join(f"{kind} {counts.get(kind, 0)}" for kind in PATTERNS))
    print("check-tokens totals: " + ", ".join(f"{kind} {count}" for kind, count in totals.items())
          + f"  ({sum(totals.values())} hits in {len(hits)} files; {len(EXEMPT)} files exempt)")
    return sum(totals.values())


def self_test():
    """--strict must exit 1 on a literal, exit 0 on clean code, and skip an exempt file."""
    script = str(Path(__file__).resolve())
    cases = [
        ("font literal", "Bad.swift", "let f = NSFont.systemFont(ofSize: 20)\n", 1),
        ("colour literal", "Bad.swift", "let c = NSColor(white: 0.5, alpha: 1)\n", 1),
        ("radius literal", "Bad.swift", "layer.cornerRadius = 8\n", 1),
        ("token use", "Good.swift", "let f = DesignTokens.Typography.font(.body)\n// ofSize: 12 in a comment\n", 0),
        ("exempt file", "Canvas.swift", "let f = NSFont.systemFont(ofSize: 20)\n", 0),
    ]
    failed = False
    for label, name, code, expected in cases:
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / name).write_text(code)
            got = subprocess.run([sys.executable, script, "--strict", "--sources", folder], capture_output=True).returncode
        print(f"  self-test {label}: exit {got} (expected {expected})")
        failed |= got != expected
    if failed:
        raise SystemExit("FAIL check-tokens self-test")
    print("PASS check-tokens self-test")


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--strict", action="store_true", help="exit 1 on any hit")
parser.add_argument("--self-test", action="store_true", help="prove --strict can fail")
parser.add_argument("--sources", type=Path, default=root / "Sources")
options = parser.parse_args()
if options.self_test:
    self_test()
    raise SystemExit(0)
total = report(scan(options.sources))
if options.strict and total:
    raise SystemExit(1)
