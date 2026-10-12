#!/usr/bin/env python3
"""OSN-062 WP1a: the spoken scripts and the tracked accessibility findings.

The native suites that run tests/AccessibilityAudit.swift (OPENSNAP_SPOKEN_SCRIPT_DIR) leave, for every surface they audit,
  <dir>/<surface-slug>.md        what a screen reader would be told, in reading order (tests/SpokenScript.swift)
  <dir>/_findings/<suite>.json   every finding of the six tracked kinds on each surface the suite audited, baselined or not
This gate, run after the suites:
  * every surface listed in tools/spoken-surfaces.txt has a non-empty script (a header and at least one node), every surface the suites
    audited is on that list, and the owner-facing <dir>/INDEX.md (written here) lists them all;
  * the tracked findings (genericLabel, missingValue, readingOrderMismatch, keyLoopDisagreesWithAXOrder, ignoredButFocusable,
    duplicateInGroup, and since WP1b nameMismatch, missingLabel, missingRole, duplicateLabel) match tools/accessibility-baseline.tsv exactly: a finding the baseline does not cover is NEW and fails; a baseline
    line no run produced is STALE and fails. Every baseline line carries a reason (today: "pending WP3", the burn-down);
  * <dir>/FINDINGS.md is written: the counts per surface and kind, then every finding.

Usage: check-spoken-scripts.py [--dir DIR] [--baseline FILE] [--surfaces FILE] [--require SUITE ...]
       check-spoken-scripts.py --write-baseline [--dir DIR]   (regenerate the baseline and the surface list from a full run; review the diff)
       check-spoken-scripts.py --self-test                    (seed each failure and prove the gate catches it)
"""
from pathlib import Path
import argparse, collections, json, re, sys, tempfile

ROOT = Path(__file__).resolve().parent.parent
TRACKED = ["genericLabel", "missingValue", "readingOrderMismatch", "keyLoopDisagreesWithAXOrder", "ignoredButFocusable", "duplicateInGroup",
           "nameMismatch", "missingLabel", "missingRole", "duplicateLabel"]
DEFAULT_REASON = "pending WP3"
BASELINE_HEADER = "# surface\tkind\telement\tlabel\treason\n"


def load_dumps(directory):
    """{surface: (slug, Counter of (kind, path, label))} merged over every suite's dump (the larger count wins), and the suites found."""
    surfaces, suites = {}, []
    for dump in sorted((directory / "_findings").glob("*.json")):
        data = json.loads(dump.read_text())
        suites.append(data["suite"])
        for entry in data["surfaces"]:
            counts = collections.Counter((f["kind"], f["path"], f["label"]) for f in entry["findings"])
            slug, merged = surfaces.get(entry["surface"], (entry["slug"], collections.Counter()))
            surfaces[entry["surface"]] = (slug, merged | counts)
    return surfaces, suites


def load_baseline(path):
    """(Counter of (surface, kind, path, label), [problems])."""
    counts, problems = collections.Counter(), []
    if not path.is_file():
        return counts, [f"the baseline {path} is missing"]
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 5:
            problems.append(f"{path.name}:{number}: expected 5 tab-separated fields (surface, kind, element, label, reason), got {len(fields)}")
            continue
        surface, kind, element, label, reason = fields
        if kind not in TRACKED:
            problems.append(f"{path.name}:{number}: {kind!r} is not a baselinable kind")
        if not reason.strip():
            problems.append(f"{path.name}:{number}: the entry for {surface} / {kind} has no reason")
        counts[(surface, kind, element, label)] += 1
    return counts, problems


def load_surfaces(path):
    if not path.is_file():
        return None
    return [line.strip() for line in path.read_text().splitlines() if line.strip() and not line.startswith("#")]


NOTHING_TO_READ = "(no accessibility elements: a screen reader finds nothing here)"


def script_problems(directory, expected, audited, explained=frozenset()):
    """Every expected surface has a script with a header and nodes; every audited one is expected.
    A script with no node is accepted only when it says so (NOTHING_TO_READ) and the surface carries a tracked finding that explains it
    (the capture picker overlay today): an empty tree with no finding is the walker seeing nothing, which proves nothing."""
    problems = []
    for slug in expected:
        script = directory / f"{slug}.md"
        if not script.is_file():
            problems.append(f"no spoken script for {slug} ({slug}.md)")
            continue
        text = script.read_text()
        nodes = re.search(r"^- Nodes: (\d+)$", text, re.M)
        if not text.startswith("# ") or not nodes or not re.search(r"^\[\d+\] ", text, re.M):
            problems.append(f"the spoken script {slug}.md is empty: the walker saw no element, so it proves nothing")
        elif int(nodes.group(1)) == 0 and not (NOTHING_TO_READ in text and slug in explained):
            problems.append(f"the spoken script {slug}.md is empty: the walker saw no element, so it proves nothing")
    for surface, slug in sorted(audited.items()):
        if slug not in expected:
            problems.append(f"surface {surface!r} ({slug}) was audited but is not in the expected surface list")
    return problems


def header_of(script):
    text = script.read_text()
    field = lambda name: (re.search(rf"^- {name}: (.*)$", text, re.M) or [None, "?"])[1]
    return field("Surface"), field("Suite"), field("Build"), field("Nodes")


def write_index(directory, expected):
    rows = ["# Spoken scripts", "",
            "What a screen reader would be told on each surface, in reading order (default verbosity, an approximation until the live pass).",
            "Read a script, and if a word is wrong or missing say which line.", "",
            "| Surface | Script | Suite | Nodes | Build |", "|---|---|---|---|---|"]
    for slug in sorted(expected):
        script = directory / f"{slug}.md"
        if script.is_file():
            surface, suite, build, nodes = header_of(script)
            rows.append(f"| {surface} | [{slug}.md]({slug}.md) | {suite} | {nodes} | {build} |")
    rows += ["", f"{len(expected)} surfaces. Known findings: [FINDINGS.md](FINDINGS.md).", ""]
    (directory / "INDEX.md").write_text("\n".join(rows))


def index_problems(directory, expected):
    index = directory / "INDEX.md"
    if not index.is_file():
        return ["INDEX.md was not written"]
    text = index.read_text()
    return [f"INDEX.md does not list {slug}.md" for slug in expected if f"({slug}.md)" not in text]


def compare(found, baseline):
    """(new, stale): Counters of (surface, kind, path, label)."""
    return found - baseline, baseline - found


def write_findings(directory, surfaces, baseline, new, stale):
    by_kind = collections.Counter()
    per_surface = {}
    for surface, (slug, counts) in sorted(surfaces.items()):
        per_surface[surface] = collections.Counter()
        for (kind, path, label), n in counts.items():
            per_surface[surface][kind] += n
            by_kind[kind] += n
    total = sum(by_kind.values())
    out = ["# Spoken-script findings", "",
           (f"{total} findings of the tracked kinds across {len(surfaces)} audited surfaces; every one is a baseline entry ({DEFAULT_REASON}) in `tools/accessibility-baseline.tsv`."
            if total else f"No findings of the tracked kinds across {len(surfaces)} audited surfaces; `tools/accessibility-baseline.tsv` is empty."),
           f"New (not in the baseline): {sum(new.values())}. Stale (in the baseline, not produced): {sum(stale.values())}.", "",
           "## By kind", "", "| Kind | Findings |", "|---|---|"]
    out += [f"| {kind} | {by_kind.get(kind, 0)} |" for kind in TRACKED]
    out += ["", "## By surface", "", "| Surface | " + " | ".join(TRACKED) + " | Total |", "|---|" + "---|" * (len(TRACKED) + 1)]
    for surface, counts in per_surface.items():
        out.append(f"| {surface} | " + " | ".join(str(counts.get(kind, 0)) for kind in TRACKED) + f" | {sum(counts.values())} |")
    out += ["", "## Every finding", ""]
    for surface, (slug, counts) in sorted(surfaces.items()):
        if not counts:
            continue
        out += [f"### {surface}", ""]
        for (kind, path, label), n in sorted(counts.items()):
            out.append(f"- `{kind}`{f' x{n}' if n > 1 else ''}: {path}" + (f" (label \"{label}\")" if label else ""))
        out.append("")
    (directory / "FINDINGS.md").write_text("\n".join(out))
    return by_kind, total


def check(directory, baseline_path, surfaces_path, require=()):
    problems = []
    surfaces, suites = load_dumps(directory)
    for suite in require:
        if suite not in suites:
            problems.append(f"no findings dump from {suite}: the suite did not run its audits (found: {', '.join(suites) or 'none'})")
    expected = load_surfaces(surfaces_path)
    if expected is None:
        problems.append(f"the expected surface list {surfaces_path} is missing")
        expected = []
    explained = {slug for slug, counts in surfaces.values() if counts}
    problems += script_problems(directory, expected, {surface: slug for surface, (slug, _) in surfaces.items()}, explained)
    baseline, baseline_problems = load_baseline(baseline_path)
    problems += baseline_problems
    found = collections.Counter()
    for surface, (_, counts) in surfaces.items():
        for (kind, path, label), n in counts.items():
            found[(surface, kind, path, label)] += n
    new, stale = compare(found, baseline)
    for (surface, kind, path, label), n in sorted(new.items()):
        problems.append(f"NEW finding x{n}: {surface}: {path} {kind} \"{label}\" (fix it; the baseline is only for reviewed, pending work)")
    for (surface, kind, path, label), n in sorted(stale.items()):
        problems.append(f"STALE baseline entry x{n}: {surface}: {path} {kind} \"{label}\" (no run produced it; delete the line)")
    write_index(directory, expected)
    problems += index_problems(directory, expected)
    by_kind, total = write_findings(directory, surfaces, baseline, new, stale)
    return problems, by_kind, total, len(expected)


def write_baseline(directory, baseline_path, surfaces_path):
    surfaces, _ = load_dumps(directory)
    lines = []
    for surface, (_, counts) in surfaces.items():
        for (kind, path, label), n in counts.items():
            lines += [f"{surface}\t{kind}\t{path}\t{label}\t{DEFAULT_REASON}"] * n
    baseline_path.write_text(BASELINE_HEADER + "\n".join(sorted(lines)) + ("\n" if lines else ""))
    slugs = sorted({slug for slug, _ in surfaces.values()})
    surfaces_path.write_text("# Surfaces the suites audit and script (WP1a); a surface audited but not listed, or listed but not scripted, fails the gate.\n" + "\n".join(slugs) + "\n")
    print(f"wrote {len(lines)} baseline entries over {len(surfaces)} surfaces and {len(slugs)} surface slugs")


def self_test():
    def build(root, findings=None, nodes=1):
        (root / "_findings").mkdir(parents=True)
        findings = findings if findings is not None else [{"kind": "genericLabel", "path": "AXButton \"x\"", "label": "x"}]
        (root / "_findings" / "suite-a.json").write_text(json.dumps({"suite": "suite-a", "surfaces": [{"surface": "Alpha", "slug": "alpha", "findings": findings}]}))
        (root / "alpha.md").write_text(f"# Alpha\n\n- Surface: Alpha\n- Suite: suite-a\n- Build: t\n- Nodes: {nodes}\n\n```\n[0] x, button\n```\n")
        (root / "surfaces.txt").write_text("alpha\n")
        (root / "baseline.tsv").write_text(BASELINE_HEADER + f"Alpha\tgenericLabel\tAXButton \"x\"\tx\t{DEFAULT_REASON}\n")

    def run(mutate=None, findings=None, nodes=1, require=("suite-a",)):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build(root, findings, nodes)
            if mutate:
                mutate(root)
            return check(root, root / "baseline.tsv", root / "surfaces.txt", require)[0]

    expectations = [
        ("a clean run passes", lambda: run(), None),
        ("a missing script is caught", lambda: run(lambda r: (r / "alpha.md").unlink()), "no spoken script"),
        ("an empty script with no finding to explain it is caught", lambda: run(lambda r: (r / "baseline.tsv").write_text(BASELINE_HEADER), findings=[], nodes=0), "is empty"),
        ("an empty script that does not say so is caught", lambda: run(nodes=0), "is empty"),
        ("an empty script that says so and carries a finding passes", lambda: run(lambda r: (r / "alpha.md").write_text(
            f"# Alpha\n\n- Nodes: 0\n\n```\n[0] window\n[0] {NOTHING_TO_READ}\n```\n")), None),
        ("a script with no lines is caught", lambda: run(lambda r: (r / "alpha.md").write_text("# Alpha\n\n- Nodes: 3\n")), "is empty"),
        ("a surface nobody listed is caught", lambda: run(lambda r: (r / "surfaces.txt").write_text("# none\n")), "not in the expected surface list"),
        ("a NEW finding is caught", lambda: run(findings=[{"kind": "genericLabel", "path": "AXButton \"x\"", "label": "x"}, {"kind": "missingValue", "path": "AXSlider \"s\"", "label": "s"}]), "NEW finding"),
        ("a second copy of a baselined finding is NEW", lambda: run(findings=[{"kind": "genericLabel", "path": "AXButton \"x\"", "label": "x"}] * 2), "NEW finding x1"),
        ("a STALE baseline entry is caught", lambda: run(findings=[]), "STALE baseline entry"),
        ("a baseline line with no reason is caught", lambda: run(lambda r: (r / "baseline.tsv").write_text(BASELINE_HEADER + "Alpha\tgenericLabel\tAXButton \"x\"\tx\t \n")), "has no reason"),
        ("a baseline line of an untracked kind is caught", lambda: run(lambda r: (r / "baseline.tsv").write_text(BASELINE_HEADER + "Alpha\tretiredName\tp\tl\twhy\n")), "not a baselinable kind"),
        ("a suite that left no dump is caught", lambda: run(require=("suite-a", "suite-b")), "no findings dump from suite-b"),
    ]
    failed = 0
    for name, action, wanted in expectations:
        problems = action()
        ok = (not problems) if wanted is None else any(wanted in p for p in problems)
        print(("PASS" if ok else "FAIL"), "self-test:", name, "" if ok else f"-> {problems}")
        failed += not ok
    with tempfile.TemporaryDirectory() as tmp:  # a tampered INDEX.md
        root = Path(tmp)
        build(root)
        check(root, root / "baseline.tsv", root / "surfaces.txt", ("suite-a",))
        (root / "INDEX.md").write_text("# Spoken scripts\n")
        ok = bool(index_problems(root, ["alpha"]))
        print(("PASS" if ok else "FAIL"), "self-test: an INDEX.md that omits a surface is caught")
        failed += not ok
    if failed:
        raise SystemExit(f"FAIL check-spoken-scripts self-test: {failed} case(s) did not behave")
    print("PASS check-spoken-scripts self-test")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", type=Path, default=ROOT / "build" / "spoken")
    parser.add_argument("--baseline", type=Path, default=ROOT / "tools" / "accessibility-baseline.tsv")
    parser.add_argument("--surfaces", type=Path, default=ROOT / "tools" / "spoken-surfaces.txt")
    parser.add_argument("--require", action="append", default=[])
    parser.add_argument("--write-baseline", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    if options.self_test:
        return self_test()
    if options.write_baseline:
        return write_baseline(options.dir, options.baseline, options.surfaces)
    problems, by_kind, total, surfaces = check(options.dir, options.baseline, options.surfaces, options.require)
    summary = ", ".join(f"{kind} {by_kind.get(kind, 0)}" for kind in TRACKED)
    if problems:
        raise SystemExit("FAIL spoken-scripts:\n" + "\n".join(problems))
    print(f"PASS spoken-scripts ({surfaces} surfaces scripted, INDEX.md and FINDINGS.md written; {total} baselined findings: {summary})")


if __name__ == "__main__":
    main()
