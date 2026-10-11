#!/usr/bin/env python3
"""G3: no user-visible string names the retired product (case-insensitive "skitch", which also covers "openskitch").

Static  string literals in Sources/*.swift (comments are not literals) and every string value in Info.plist, outside the allow-list
        (the one-time migration and the only reader of the retired formats, which deal with the old data on purpose).
Dynamic JSON dumps written by the native suites (tests/UserStringWalk.swift, OPENSNAP_USER_STRINGS_DIR): every window title, text, button,
        menu row, tooltip and accessibility label the live objects can show. A dump must exist for each --require NAME and hold at least
        --min strings including "OpenSnap", so an empty or missing dump cannot pass.

Usage: check-user-strings.py [--dynamic DIR --require NAME ... --min N] [--root DIR] [--self-test]
Exit 1 on any hit or any missing dump. --self-test seeds a violation of each kind and proves the gate fails on it (and passes on clean input).
"""
from pathlib import Path
import argparse, json, plistlib, re, subprocess, sys, tempfile

NEEDLE = re.compile(r"skitch", re.I)
ALLOWED_SOURCES = {"Migration.swift", "LegacyReader.swift"}
here = Path(__file__).resolve()


def literals(text):
    # [(line number, literal text)] for every Swift string literal; // and /* */ comments are skipped, triple-quoted blocks are kept.
    found, number, i, n = [], 1, 0, len(text)
    block = False
    while i < n:
        ch = text[i]
        if ch == "\\n":
            number += 1
            i += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            number += text.count("\\n", i, end)
            i = end
        elif text.startswith('\"\"\"', i):
            end = text.find('\"\"\"', i + 3)
            end = n if end < 0 else end
            found.append((number, text[i + 3:end]))
            number += text.count("\\n", i, end)
            i = end + 3
        elif ch == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\\n":
                j += 2 if text[j] == "\\\\" else 1
            found.append((number, text[i + 1:j]))
            i = j + 1
        else:
            i += 1
    return found


def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)


def static_problems(root):
    problems = []
    for path in sorted((root / "Sources").glob("*.swift")):
        if path.name in ALLOWED_SOURCES:
            continue
        for number, literal in literals(path.read_text(errors="replace")):
            if NEEDLE.search(literal):
                problems.append(f"static: Sources/{path.name}:{number}: string literal names the retired product: {literal.strip()[:100]!r}")
    plist = root / "Info.plist"
    if plist.is_file():
        for value in strings_in(plistlib.loads(plist.read_bytes())):
            if NEEDLE.search(value):
                problems.append(f"static: Info.plist value names the retired product: {value[:100]!r}")
    else:
        problems.append("static: Info.plist is missing")
    return problems


def dynamic_problems(folders, required, minimum):
    problems, seen = [], {}
    for folder in folders:
        for path in sorted(Path(folder).glob("*.json")):
            try:
                dump = json.loads(path.read_text())
                strings = dump["strings"]
            except (ValueError, KeyError, TypeError):
                problems.append(f"dynamic: {path.name} is not a string dump")
                continue
            seen[dump.get("name", path.stem)] = strings
            texts = {entry.get("text", "") for entry in strings}
            if len(strings) < minimum or "OpenSnap" not in texts:
                problems.append(f"dynamic: {path.name} holds {len(strings)} strings (need {minimum}+ including 'OpenSnap'): the walk did not really run")
            for entry in strings:
                if NEEDLE.search(entry.get("text", "")):
                    problems.append(f"dynamic: {dump.get('name', path.stem)} / {entry.get('surface')} / {entry.get('kind')}: {entry['text'][:100]!r}")
    for name in required:
        if name not in seen:
            problems.append(f"dynamic: no string dump named {name!r} was written")
    return problems


def self_test():
    seed = "Ski" + "tch"  # never spelled whole in this file
    with tempfile.TemporaryDirectory(prefix="check-user-strings.") as tmp:
        tmp = Path(tmp)

        def run(case, expected, *args):
            got = subprocess.run([sys.executable, str(here), *args], capture_output=True, text=True).returncode
            print(f"  self-test {case}: exit {got} (expected {expected})")
            return got == expected

        def tree(name, source=None, plist=None, extra_file=None):
            root = tmp / name
            (root / "Sources").mkdir(parents=True)
            (root / "Sources" / "App.swift").write_text(source or 'let title = "OpenSnap"\\n')
            (root / "Info.plist").write_bytes(plistlib.dumps(plist or {"CFBundleName": "OpenSnap"}))
            if extra_file:
                (root / "Sources" / extra_file[0]).write_text(extra_file[1])
            return str(root)

        def dump(name, texts, count=300, nm="app-safety"):
            folder = tmp / name
            folder.mkdir()
            strings = [{"surface": "s", "path": "p", "kind": "text", "text": t} for t in texts]
            strings += [{"surface": "s", "path": "p", "kind": "text", "text": f"filler {i}"} for i in range(count - len(strings))]
            (folder / (nm + ".json")).write_text(json.dumps({"name": nm, "strings": strings}))
            return str(folder)

        results = [
            run("clean tree", 0, "--root", tree("clean")),
            run("literal in Sources", 1, "--root", tree("lit", source=f'let title = "Import from {seed}"\\n')),
            run("literal in a multi-line block", 1, "--root", tree("block", source=f'let t = \"\"\"\\nline\\n{seed.lower()}\\n\"\"\"\\n')),
            run("interpolated literal", 1, "--root", tree("interp", source=f'let t = "\\\\(x) {seed.upper()}"\\n')),
            run("comment is not a literal", 0, "--root", tree("comment", source=f'// {seed}\\n/* {seed} */\\nlet title = "OpenSnap" // {seed}\\n')),
            run("allow-listed migration file", 0, "--root", tree("allow", extra_file=("Migration.swift", f'let old = "{seed}"\\n'))),
            run("another file is not allow-listed", 1, "--root", tree("other", extra_file=("Other.swift", f'let old = "{seed}"\\n'))),
            run("Info.plist value", 1, "--root", tree("plist", plist={"CFBundleName": "OpenSnap", "Nested": [{"Text": f"About {seed}"}]})),
            run("dynamic clean dump", 0, "--root", tree("c2"), "--dynamic", dump("d-clean", ["OpenSnap", "Save"]), "--require", "app-safety", "--min", "100"),
            run("dynamic seeded dump", 1, "--root", tree("c3"), "--dynamic", dump("d-bad", ["OpenSnap", f"Welcome to {seed}"]), "--require", "app-safety", "--min", "100"),
            run("dynamic empty walk", 1, "--root", tree("c4"), "--dynamic", dump("d-small", ["OpenSnap"], count=3), "--require", "app-safety", "--min", "100"),
            run("dynamic walk without the brand", 1, "--root", tree("c5"), "--dynamic", dump("d-nobrand", ["Save"]), "--require", "app-safety", "--min", "100"),
            run("dynamic dump missing", 1, "--root", tree("c6"), "--dynamic", dump("d-other", ["OpenSnap"], nm="other"), "--require", "app-safety", "--min", "100"),
        ]
    if not all(results):
        raise SystemExit("FAIL check-user-strings self-test")
    print("PASS check-user-strings self-test")


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--root", type=Path, default=here.parent.parent)
parser.add_argument("--dynamic", action="append", default=[], help="folder of string dumps written by the native suites")
parser.add_argument("--require", action="append", default=[], help="a dump name that must exist (repeatable)")
parser.add_argument("--min", type=int, default=100, help="fewest strings a dump may hold")
parser.add_argument("--self-test", action="store_true")
options = parser.parse_args()
if options.self_test:
    self_test()
    raise SystemExit(0)
problems = static_problems(options.root) + dynamic_problems(options.dynamic, options.require, options.min)
for line in problems[:100]:
    print(line, file=sys.stderr)
if problems:
    print(f"FAIL check-user-strings: {len(problems)} problem(s)", file=sys.stderr)
    raise SystemExit(1)
print(f"PASS check-user-strings (static: Sources literals and Info.plist; dynamic: {len(options.dynamic)} dump folder(s), required {options.require or 'none'})")
