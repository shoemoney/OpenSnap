#!/usr/bin/env python3
"""G12 / OSN-070: layout fit at the 980 pt minimum width, from the harness's layout.json evidence.

For every main-editor layout (it has a topBar and a bottomBar) whose window is the minimum width wide
(minimumWindowWidth in Sources/ModernEditorChrome.swift, 980), every visible control, group, row and text the bars report must
  - FIT: its fitting size (what the view needs) is no larger than its frame (what it was given), width and height, and
  - lie inside the window.
A control that needs more than it has is clipped. The gate also requires coverage: at least one layout at the minimum width in each of
normal mode and Frame mode, in light and in dark, so deleting the evidence cannot make it pass.

Usage: check-layout-fit.py [EVIDENCE_DIR ...]   (default: docs/design/evidence, searched recursively for layout/*.json)
       check-layout-fit.py --self-test          (seeds a clipped control, a missing mode and a missing appearance; each must fail)
"""
from pathlib import Path
import argparse, copy, json, re, subprocess, sys, tempfile

root = Path(__file__).resolve().parent.parent
TOLERANCE = 0.5
# Elastic by design: the status line truncates with an ellipsis and its row and the bar row give way to it, so their fitting size is the
# natural width of the text, not a minimum. Everything the user presses, and every plate around it, must fit.
ELASTIC = {"status", "statusRow", "row"}


def minimum_width():
    source = root / "Sources" / "ModernEditorChrome.swift"
    if source.is_file():
        found = re.search(r"minimumWindowWidth\s*(?::\s*CGFloat\s*)?=\s*([0-9.]+)", source.read_text(errors="replace"))
        if found:
            return float(found.group(1))
    return 980.0


def nodes(value, path):
    """(path, node) for every dict that carries both a frame and a fitting size."""
    if isinstance(value, dict):
        if isinstance(value.get("frame"), list) and isinstance(value.get("fitting"), list):
            yield path, value
        for key, child in value.items():
            yield from nodes(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            label = child.get("label") if isinstance(child, dict) else None
            yield from nodes(child, f"{path}[{label or index}]")


def problems_in(layout):
    """[problem] for one layout dict: clipped controls and controls outside the window."""
    size = layout.get("windowSize") or [0, 0]
    found = []
    for bar in ("topBar", "bottomBar"):
        for path, node in nodes(layout.get(bar), bar):
            if node.get("hidden") or path.rsplit(".", 1)[-1] in ELASTIC:
                continue
            x, y, width, height = node["frame"]
            need_w, need_h = node["fitting"][:2]
            if need_w > 0 and need_w > width + TOLERANCE:
                found.append(f"{path}: needs {need_w:g} pt wide, has {width:g}")
            if need_h > 0 and need_h > height + TOLERANCE:
                found.append(f"{path}: needs {need_h:g} pt tall, has {height:g}")
            if x < -TOLERANCE or x + width > size[0] + TOLERANCE:
                found.append(f"{path}: frame x {x:g}..{x + width:g} leaves the {size[0]:g} pt window")
    return found


def check(folders, minimum):
    problems, covered, files = [], set(), 0
    for folder in folders:
        for path in sorted(Path(folder).rglob("layout/*.json")):
            try:
                layout = json.loads(path.read_text())
            except ValueError:
                continue
            size = layout.get("windowSize")
            if not (isinstance(layout.get("topBar"), dict) and isinstance(layout.get("bottomBar"), dict) and isinstance(size, list) and size[0] == minimum):
                continue
            files += 1
            mode = "frame" if layout.get("frameMode") else "normal"
            covered.add((mode, layout.get("appearance")))
            problems += [f"{path.relative_to(folder) if path.is_relative_to(folder) else path}: {p}" for p in problems_in(layout)]
    for mode in ("normal", "frame"):
        for appearance in ("light", "dark"):
            if (mode, appearance) not in covered:
                problems.append(f"coverage: no layout at {minimum:g} pt in {mode} mode, {appearance} appearance")
    return problems, files


def self_test():
    def control(label, fit, frame, **extra):
        return {"class": "CommandButton", "label": label, "fitting": fit, "frame": frame, "hidden": False, **extra}

    def layout(mode, appearance, fit_w=48):
        group = {"fitting": [106, 44], "frame": [12, 8, 106, 44], "hidden": False,
                 "controls": [control("Undo", [fit_w, 36], [16, 12, 48, 36]), control("Clear", [48, 36], [66, 12, 48, 36])]}
        return {"windowSize": [980, 640], "appearance": appearance, "frameMode": mode == "frame",
                "topBar": {"groups": {"A": group}, "row": {"fitting": [834, 0], "frame": [12, 8, 956, 44], "hidden": False}},
                "bottomBar": {"groups": {}, "status": {"fitting": [219, 21], "frame": [325, 600, 219, 21], "hidden": False}}}

    cases = {
        "clean evidence": ([("normal", "light"), ("normal", "dark"), ("frame", "light"), ("frame", "dark")], {}, 0),
        "a clipped control": ([("normal", "light"), ("normal", "dark"), ("frame", "light"), ("frame", "dark")], {("frame", "dark"): 70}, 1),
        "no Frame-mode layout": ([("normal", "light"), ("normal", "dark")], {}, 1),
        "no dark layout": ([("normal", "light"), ("frame", "light")], {}, 1),
        "no layout at all": ([], {}, 1),
    }
    ok = True
    with tempfile.TemporaryDirectory(prefix="check-layout-fit.") as tmp:
        for name, (present, widen, expected) in cases.items():
            folder = Path(tmp) / name.replace(" ", "-") / "layout"
            folder.mkdir(parents=True)
            for index, (mode, appearance) in enumerate(present):
                (folder / f"{index}.json").write_text(json.dumps(layout(mode, appearance, widen.get((mode, appearance), 48))))
            got = subprocess.run([sys.executable, str(Path(__file__).resolve()), str(folder.parent)], capture_output=True, text=True).returncode
            print(f"  self-test {name}: exit {got} (expected {expected})")
            ok &= got == expected
    if not ok:
        raise SystemExit("FAIL check-layout-fit self-test")
    print("PASS check-layout-fit self-test")


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("folders", nargs="*", type=Path)
parser.add_argument("--self-test", action="store_true")
options = parser.parse_args()
if options.self_test:
    self_test()
    raise SystemExit(0)
width = minimum_width()
issues, count = check(options.folders or [root / "docs/design/evidence"], width)
for line in issues[:60]:
    print(line, file=sys.stderr)
if issues:
    print(f"FAIL check-layout-fit: {len(issues)} problem(s) over {count} layout(s) at {width:g} pt", file=sys.stderr)
    raise SystemExit(1)
print(f"PASS check-layout-fit ({count} layouts at {width:g} pt: normal and Frame mode, light and dark; 0 clipped controls)")
