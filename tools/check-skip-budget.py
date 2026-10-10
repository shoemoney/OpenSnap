#!/usr/bin/env python3
"""G11: fail when a test log reports a SKIP / SKIPPED whose reason is not one of the two allowed ones.

Usage: check-skip-budget.py LOG      (the captured output of `python3 tools/test.py`; `-` reads standard input)
       check-skip-budget.py --self-test

Every SKIP / SKIPPED marker in the log must carry a parenthesised reason, and the reason must be
  macOS < N        the host is older than a feature's floor (the suites print e.g. "SKIPPED (macOS < 27): ...")
  FA not bundled   the licensed Font Awesome Pro subsets are absent. Allowed only when OPENSNAP_ALLOW_SKIP contains `fa`
                   (a licence-free CI) or when build/fonts holds no *-subset.ttf; if the fonts ARE there the glyph branch
                   must have run, so a skip is a failure.
Anything else, or a marker with no reason, is a violation. An empty log exits 2 (a missing log must never read as a pass).
Exit status: 0 within budget, 1 violations, 2 unusable input. --fonts-dir DIR overrides build/fonts (tests only).
"""
from pathlib import Path
import argparse, os, re, subprocess, sys, tempfile

root = Path(__file__).resolve().parent.parent
MARKER = re.compile(r"\bSKIP(?:PED)?\b(?:\s*\(([^)]*)\))?")
MACOS = re.compile(r"macOS\s*<\s*\d+(?:\.\d+)?")
FA = re.compile(r"FA not bundled")


def fa_allowed(fonts_dir, environment):
    allow = {part.strip() for part in environment.get("OPENSNAP_ALLOW_SKIP", "").split(",")}
    if "fa" in allow:
        return True, "OPENSNAP_ALLOW_SKIP=fa"
    if not any(fonts_dir.glob("*-subset.ttf")):
        return True, f"no *-subset.ttf in {fonts_dir}"
    return False, f"Font Awesome subsets exist in {fonts_dir}, so the glyph branch must run"


def check(text, fonts_dir, environment):
    """(allowed [(line, reason)], violations [(line, why, text)], fa_note)"""
    fa_ok, fa_note = fa_allowed(fonts_dir, environment)
    allowed, violations = [], []
    for number, line in enumerate(text.splitlines(), 1):
        for match in MARKER.finditer(line):
            reason = (match.group(1) or "").strip()
            if not reason:
                violations.append((number, "skip with no reason", line.strip()))
            elif MACOS.fullmatch(reason):
                allowed.append((number, reason))
            elif FA.fullmatch(reason):
                if fa_ok:
                    allowed.append((number, reason))
                else:
                    violations.append((number, f"'{reason}' not allowed: {fa_note}", line.strip()))
            else:
                violations.append((number, f"reason '{reason}' is not 'macOS < N' or 'FA not bundled'", line.strip()))
    return allowed, violations, fa_note


def run(text, fonts_dir, environment):
    allowed, violations, fa_note = check(text, fonts_dir, environment)
    reasons = {}
    for _, reason in allowed:
        reasons[reason] = reasons.get(reason, 0) + 1
    for number, why, line in violations:
        print(f"  line {number}: {why}\n    {line[:200]}")
    print("check-skip-budget: " + (", ".join(f"{count} x '{reason}'" for reason, count in sorted(reasons.items())) or "no allowed skips")
          + f" allowed; {len(violations)} violation(s)  (FA skips: {fa_note})")
    return 1 if violations else 0


def self_test():
    """The gate must exit 1 on a bad skip, 0 on the allowed ones, 2 on an empty log, and honour the FA switches."""
    script = str(Path(__file__).resolve())
    with tempfile.TemporaryDirectory() as folder:
        empty, stocked = Path(folder, "empty"), Path(folder, "stocked")
        empty.mkdir()
        stocked.mkdir()
        (stocked / "FontAwesome7Pro-Regular-subset.ttf").write_bytes(b"x")
        base = {key: value for key, value in os.environ.items() if key != "OPENSNAP_ALLOW_SKIP"}
        fa = "FontAwesomeIconsTests: 222 checks passed; SKIPPED (FA not bundled): glyph branch\n"
        macos = "GlassChromeTests: 40 passed; SKIPPED (macOS < 27): liquid glass\n"
        both = "GlassChromeTests: 40 passed; SKIPPED (FA not bundled): a; SKIPPED (macOS < 27): b\n"
        cases = [
            ("macOS floor skip", macos, empty, {}, 0),
            ("FA skip, no fonts present", fa, empty, {}, 0),
            ("two allowed skips on one line", both, empty, {}, 0),
            ("FA skip, fonts present", fa, stocked, {}, 1),
            ("FA skip, fonts present, OPENSNAP_ALLOW_SKIP=fa", fa, stocked, {"OPENSNAP_ALLOW_SKIP": "fa"}, 0),
            ("macOS skip is unaffected by fonts", macos, stocked, {}, 0),
            ("unlisted reason", "CanvasTests: SKIPPED (needs original/ archive)\n", empty, {}, 1),
            ("missing original", "PhotoBrowserTests: SKIPPED (original/ absent)\n", empty, {}, 1),
            ("no reason", "SomeTests: SKIP\n", empty, {}, 1),
            ("TAP style skip", "ok 3 - thing # SKIP\n", empty, {}, 1),
            ("bad reason beside a good one", "X: SKIPPED (macOS < 27): a; SKIPPED (flaky): b\n", empty, {}, 1),
            ("no skips at all", "All suites passed on arm64\n", empty, {}, 0),
            ("word merely contains skip", "SKIPPING is not a marker; skipped lowercase neither\n", empty, {}, 0),
            ("empty log", "", empty, {}, 2),
        ]
        failed = False
        for label, text, fonts, extra, expected in cases:
            log = Path(folder, "log.txt")
            log.write_text(text)
            got = subprocess.run([sys.executable, script, str(log), "--fonts-dir", str(fonts)], capture_output=True, env=base | extra).returncode
            print(f"  self-test {label}: exit {got} (expected {expected})")
            failed |= got != expected
    if failed:
        raise SystemExit("FAIL check-skip-budget self-test")
    print("PASS check-skip-budget self-test")


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("log", nargs="?", help="test log path, or - for standard input")
parser.add_argument("--self-test", action="store_true", help="prove the gate can fail")
parser.add_argument("--fonts-dir", type=Path, default=root / "build" / "fonts")
options = parser.parse_args()
if options.self_test:
    self_test()
    raise SystemExit(0)
if not options.log:
    parser.error("a log path (or -) is required")
log_text = sys.stdin.read() if options.log == "-" else Path(options.log).read_text(errors="replace")
if not log_text.strip():
    print("check-skip-budget: empty log, nothing to judge", file=sys.stderr)
    raise SystemExit(2)
raise SystemExit(run(log_text, options.fonts_dir, os.environ))
