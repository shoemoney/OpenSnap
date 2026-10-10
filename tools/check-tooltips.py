#!/usr/bin/env python3
"""Fail when chrome writes a system tooltip instead of routing it through AppToolTip (D-TEXT: app-owned text is 18 pt or more).

A system tooltip is drawn by AppKit at about 11 pt. Every write to a view's `toolTip` must go through
`AppToolTip.setText(_:for:)`, or the view must sit in a tree that `AppToolTip.install(on:)` walks (it adopts the write).
The allowlist below names each file that still writes `toolTip` directly, with the reason. --self-test proves the gate can fail.
"""
from pathlib import Path
import argparse, re, subprocess, sys, tempfile

root = Path(__file__).resolve().parent.parent
WRITE = re.compile(r"(?<![\w])toolTip\s*!?\s*\+?=(?!=)")
DECLARATION = re.compile(r"\b(let|var|static let|static var)\s+toolTip\b")

# file name -> (line pattern that may write directly, reason)
ALLOWED = {
    "AppToolTip.swift": (r".", "the implementation clears and reads system tooltips"),
    "StatusItemSupport.swift": (r"button\.toolTip", "the menu-bar status item lives in the system's status bar window; the OS draws it"),
    "AboutWindow.swift": (r"licenseButton\.toolTip", "adopted by AppToolTip.install(on:) when About is shown"),
    "HistoryBrowser.swift": (r"button\.toolTip", "adopted by AppToolTip.install(on:) when History is shown"),
    "PublishingDestinationsView.swift": (r"item\(at: index\)\?\.toolTip", "an NSMenuItem tooltip inside an open menu; the OS draws it"),
    "App.swift": (r"\bitem\.toolTip", "the zoom menu item's mode text (read by VoiceOver); the zoom control's own tooltip goes through AppToolTip"),
}


def scan(sources):
    problems = []
    for path in sorted(sources.glob("*.swift")):
        allowed = ALLOWED.get(path.name)
        for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            code = line.split("//")[0]
            if not WRITE.search(code) or DECLARATION.search(code):
                continue
            if allowed and re.search(allowed[0], code):
                continue
            problems.append(f"{path.name}:{number}: {line.strip()[:140]}")
    return problems


def self_test():
    script = str(Path(__file__).resolve())
    cases = [
        ("direct write", "Bad.swift", "button.toolTip = \"x\"\n", 1),
        ("bare write in a subclass", "Bad.swift", "        toolTip = name\n", 1),
        ("append", "Bad.swift", "button.toolTip! += \"y\"\n", 1),
        ("routed", "Good.swift", "AppToolTip.setText(\"x\", for: button)\n", 0),
        ("read", "Good.swift", "let tip = button.toolTip\nif button.toolTip == nil {}\n", 0),
        ("comparison", "Good.swift", "expect(a.toolTip == b)\n", 0),
        ("constant", "Good.swift", "static let toolTip = \"Format\"\n", 0),
        ("parameter label", "Good.swift", "make(\"Save\", toolTip: \"Save to History\")\n", 0),
        ("allowed file and line", "StatusItemSupport.swift", "button.toolTip = name\n", 0),
        ("allowed file, other line", "StatusItemSupport.swift", "other.toolTip = name\n", 1),
    ]
    failed = False
    for label, name, code, expected in cases:
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / name).write_text(code)
            got = subprocess.run([sys.executable, script, "--sources", folder], capture_output=True).returncode
        print(f"  self-test {label}: exit {got} (expected {expected})")
        failed |= got != expected
    if failed:
        raise SystemExit("FAIL check-tooltips self-test")
    print("PASS check-tooltips self-test")


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--self-test", action="store_true")
parser.add_argument("--sources", type=Path, default=root / "Sources")
options = parser.parse_args()
if options.self_test:
    self_test()
    raise SystemExit(0)
problems = scan(options.sources)
for problem in problems:
    print("system tooltip write:", problem)
print("PASS check-tooltips" if not problems else f"FAIL check-tooltips: {len(problems)} write(s) bypass AppToolTip.setText")
raise SystemExit(1 if problems else 0)
