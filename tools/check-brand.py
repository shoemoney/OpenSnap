#!/usr/bin/env python3
"""Hold the product name and menu wording to one source of truth (OSN-031, T12 / G6).

  1. DesignTokens.Brand.name is the product name; Info.plist's CFBundleName, CFBundleDisplayName and CFBundleExecutable
     and the document type names must equal it (or start with it, for "OpenSnap Drawing").
  2. No string literal under Sources/ ends in three ASCII dots: a title that continues in a dialog uses the single
     ellipsis character. Comments and doc comments are not scanned.
Usage: check-brand.py [--self-test]
"""
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
THREE_DOTS = re.compile(r'"[^"\n]*\.\.\."')
# Not a title: this sentence names the path components "." and ".." and then ends with a full stop.
ALLOWED = ("cannot be . or ...",)


def brand_name(tokens_text):
    match = re.search(r'enum Brand\s*\{\s*static let name = "([^"]+)"', tokens_text)
    return match.group(1) if match else None


def plist_problems(name, info):
    problems = []
    for key in ("CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"):
        if info.get(key) != name:
            problems.append(f"Info.plist {key} is {info.get(key)!r}, the brand is {name!r}")
    names = [t.get("CFBundleTypeName", "") for t in info.get("CFBundleDocumentTypes", [])]
    if not any(n.startswith(name) for n in names):
        problems.append(f"no document type name starts with {name!r}: {names}")
    for declared in info.get("UTExportedTypeDeclarations", []):
        if not declared.get("UTTypeDescription", "").startswith(name):
            problems.append(f"exported type description {declared.get('UTTypeDescription')!r} does not start with {name!r}")
    return problems


def dot_problems(label, text):
    problems = []
    for number, line in enumerate(text.splitlines(), 1):
        # Strip a trailing comment, but not a "//" inside a string (a URL).
        stripped = re.sub(r'"(?:[^"\\\n]|\\.)*"', lambda m: "S" * len(m.group(0)), line)
        cut = stripped.find("//")
        code = line if cut < 0 else line[:cut]
        if THREE_DOTS.search(code) and not any(allowed in code for allowed in ALLOWED):
            problems.append(f"{label}:{number}: {line.strip()}")
    return problems


def check(tokens_path, plist_path, sources):
    name = brand_name(tokens_path.read_text())
    if not name:
        return ["DesignTokens.Brand.name was not found"]
    problems = plist_problems(name, plistlib.loads(plist_path.read_bytes()))
    files = sorted(sources.glob("*.swift"))
    if len(files) < 20:
        problems.append(f"only {len(files)} Swift files under {sources}; the source tree was not found")
    for path in files:
        problems += dot_problems(path.name, path.read_text())
    return problems


def self_test():
    script = str(Path(__file__).resolve())
    good_tokens = 'extension DesignTokens {\n    enum Brand {\n        static let name = "Acme"\n    }\n}\n'
    good_plist = {"CFBundleName": "Acme", "CFBundleDisplayName": "Acme", "CFBundleExecutable": "Acme",
                  "CFBundleDocumentTypes": [{"CFBundleTypeName": "Acme Drawing"}],
                  "UTExportedTypeDeclarations": [{"UTTypeDescription": "Acme Drawing"}]}
    cases = [("clean", good_tokens, good_plist, 'let a = "Open…"\n// "Old..." in a comment\nlet url = "https://x.test/a"\n', 0),
             ("ASCII dots in a title", good_tokens, good_plist, 'let a = NSMenuItem(title: "Open...", action: nil, keyEquivalent: "")\n', 1),
             ("Info.plist drifts from the brand", good_tokens, {**good_plist, "CFBundleDisplayName": "Other"}, 'let a = 1\n', 1),
             ("document type loses the brand", good_tokens, {**good_plist, "CFBundleDocumentTypes": [{"CFBundleTypeName": "Drawing"}]}, 'let a = 1\n', 1),
             ("no Brand constant", "enum DesignTokens {}\n", good_plist, 'let a = 1\n', 1)]
    failed = False
    for label, tokens, plist, code, expected in cases:
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            (base / "Tokens.swift").write_text(tokens)
            (base / "Info.plist").write_bytes(plistlib.dumps(plist))
            (base / "src").mkdir()
            (base / "src" / "Code.swift").write_text(code)
            for index in range(25):
                (base / "src" / f"Filler{index}.swift").write_text("let x = 1\n")
            got = subprocess.run([sys.executable, script, "--paths", str(base / "Tokens.swift"), str(base / "Info.plist"), str(base / "src")],
                                 capture_output=True).returncode
        print(f"  self-test {label}: exit {got} (expected {expected})")
        failed |= got != expected
    if failed:
        raise SystemExit("FAIL check-brand self-test")
    print("PASS check-brand self-test")


if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
    self_test()
    raise SystemExit(0)
if len(sys.argv) > 1 and sys.argv[1] == "--paths":
    tokens, plist, sources = map(Path, sys.argv[2:5])
else:
    tokens, plist, sources = root / "Sources/DesignTokens.swift", root / "Info.plist", root / "Sources"
problems = check(tokens, plist, sources)
for line in problems:
    print(line, file=sys.stderr)
if problems:
    raise SystemExit("FAIL check-brand: %d problem(s)" % len(problems))
print("PASS check-brand (Info.plist names match DesignTokens.Brand.name; no ASCII three-dot string literal under Sources)")
