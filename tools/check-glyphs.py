#!/usr/bin/env python3
"""G6: report (or, with --strict, fail on) decorative glyphs and emoji inside Swift string literals.

Scans every string literal in Sources/*.swift (ordinary, multi-line and raw strings, the code inside \\( ... ) interpolations, and
\\u{...} escapes, which are decoded before they are judged) for
  emoji    Emoji_Presentation characters, anything in the pictograph planes U+1F000-1FAFF, regional indicators, the emoji
           variation selector U+FE0F and the keycap U+20E3
  arrow    U+2190-21FF arrows, U+27F0-27FF and U+2900-297F supplemental arrows
  symbol   U+2600-27BF miscellaneous symbols and dingbats
  block    U+2B00-2BFF miscellaneous symbols and arrows
  apple    U+F8FF, the Apple logo private-use glyph
  ordinal  U+00BA masculine ordinal indicator (a degree sign typed by mistake; U+00B0 is the real degree sign and is allowed)
Computed scalars are caught too when they use an integer literal: Unicode.Scalar(0x2713), UnicodeScalar(0xF8FF).

Allowed, with the reason:
  U+21E7 shift, U+21E5 tab, U+21A9 return (only as U+21A9 U+FE0E, the text-presentation form: bare U+21A9 renders as an emoji)
      the macOS key-cap glyphs menus and tooltips print for a shortcut. They sit inside the arrow range, so they are listed here.
  U+2318 command, U+2325 option, U+2303 control, U+238B escape
      the same shortcut glyphs; they are outside every forbidden range and need no entry, listed for the record.
  U+203A separator, U+2026 ellipsis, U+00D7 dimension sign, U+00B7 middle dot, U+00B0 degree
      ordinary typography, outside every forbidden range.
  The annotation arrow tool is drawn geometry (a bezier path), not a string glyph, so it never reaches this scan.
Comments are not string literals and are not scanned.

Default mode prints every hit and exits 0. --strict exits 1 on any hit. --self-test proves --strict can fail.
--sources DIR scans DIR instead of Sources/.
"""
from pathlib import Path
import argparse, re, subprocess, sys, tempfile, unicodedata

root = Path(__file__).resolve().parent.parent

# (first, last, rule). Emoji_Presentation from emoji-data.txt (Unicode 15.1), plus the whole pictograph planes.
EMOJI_PRESENTATION = [
    (0x231A, 0x231B), (0x23E9, 0x23EC), (0x23F0, 0x23F0), (0x23F3, 0x23F3), (0x25FD, 0x25FE), (0x2614, 0x2615),
    (0x2648, 0x2653), (0x267F, 0x267F), (0x2693, 0x2693), (0x26A1, 0x26A1), (0x26AA, 0x26AB), (0x26BD, 0x26BE),
    (0x26C4, 0x26C5), (0x26CE, 0x26CE), (0x26D4, 0x26D4), (0x26EA, 0x26EA), (0x26F2, 0x26F3), (0x26F5, 0x26F5),
    (0x26FA, 0x26FA), (0x26FD, 0x26FD), (0x2705, 0x2705), (0x270A, 0x270B), (0x2728, 0x2728), (0x274C, 0x274C),
    (0x274E, 0x274E), (0x2753, 0x2755), (0x2757, 0x2757), (0x2795, 0x2797), (0x27B0, 0x27B0), (0x27BF, 0x27BF),
    (0x2B1B, 0x2B1C), (0x2B50, 0x2B50), (0x2B55, 0x2B55),
]
RANGES = [
    ("emoji", [*EMOJI_PRESENTATION, (0x1F000, 0x1FAFF), (0x20E3, 0x20E3), (0xFE0F, 0xFE0F)]),
    ("arrow", [(0x2190, 0x21FF), (0x27F0, 0x27FF), (0x2900, 0x297F)]),
    ("symbol", [(0x2600, 0x27BF)]),
    ("block", [(0x2B00, 0x2BFF)]),
    ("apple", [(0xF8FF, 0xF8FF)]),
    ("ordinal", [(0x00BA, 0x00BA)]),
]
KEY_GLYPHS = {0x21E7: "shift", 0x21E5: "tab", 0x238B: "escape", 0x2318: "command", 0x2325: "option", 0x2303: "control"}
RETURN_ARROW, TEXT_SELECTOR = 0x21A9, 0xFE0E


def rule_for(code):
    for rule, spans in RANGES:
        if any(first <= code <= last for first, last in spans):
            return rule
    return None


def judge(scalars):
    """[(offset, code, rule)] for the scalars of one literal that break the glyph rule. scalars: [(offset, code)]."""
    found = []
    for position, (offset, code) in enumerate(scalars):
        rule = rule_for(code)
        if rule is None or code in KEY_GLYPHS:
            continue
        if code == RETURN_ARROW:
            following = scalars[position + 1][1] if position + 1 < len(scalars) else None
            if following == TEXT_SELECTOR:
                continue
        found.append((offset, code, rule))
    return found


class Lexer:
    """Just enough Swift to find string literals: comments, ordinary / multi-line / raw strings and nested interpolation."""

    def __init__(self, text):
        self.text, self.i = text, 0
        self.literals = []  # [[(offset, code)]], one list per string literal
        self.code_hits = []  # (offset, code) from Unicode.Scalar(0x...) integer literals

    def code(self, until_paren=False):
        text, depth = self.text, 0
        while self.i < len(text):
            c = text[self.i]
            if text.startswith("//", self.i):
                end = text.find("\n", self.i)
                self.i = len(text) if end < 0 else end
            elif text.startswith("/*", self.i):
                self.block_comment()
            elif c == '"' or (c == "#" and re.match(r'#+"', text[self.i:self.i + 16])):
                self.string()
            elif c == "(":
                depth += 1
                self.i += 1
            elif c == ")":
                if until_paren and depth == 0:
                    self.i += 1
                    return
                depth -= 1
                self.i += 1
            else:
                scalar = re.match(r"(?:Unicode\.Scalar|UnicodeScalar)\(\s*(0x[0-9A-Fa-f_]+|[0-9]+)", text[self.i:self.i + 48]) if c == "U" else None
                if scalar:
                    self.code_hits.append((self.i, int(scalar.group(1).replace("_", ""), 0)))
                self.i += 1

    def block_comment(self):
        depth = 0
        while self.i < len(self.text):
            if self.text.startswith("/*", self.i):
                depth += 1
                self.i += 2
            elif self.text.startswith("*/", self.i):
                depth -= 1
                self.i += 2
                if depth == 0:
                    return
            else:
                self.i += 1

    def string(self):
        text = self.text
        hashes = 0
        while text[self.i] == "#":
            hashes += 1
            self.i += 1
        multiline = text.startswith('"""', self.i)
        self.i += 3 if multiline else 1
        close = ('"""' if multiline else '"') + "#" * hashes
        escape = "\\" + "#" * hashes
        scalars = []
        while self.i < len(text):
            if text.startswith(close, self.i):
                self.i += len(close)
                break
            if text.startswith(escape, self.i):
                start = self.i
                self.i += len(escape)
                marker = text[self.i] if self.i < len(text) else ""
                if marker == "(":
                    self.i += 1
                    self.literals.append(scalars)
                    scalars = []
                    self.code(until_paren=True)
                elif marker == "u" and text.startswith("{", self.i + 1):
                    end = text.find("}", self.i)
                    scalars.append((start, int(text[self.i + 2:end], 16)))
                    self.i = end + 1
                else:
                    self.i += 1
                continue
            if text[self.i] == "\n" and not multiline:
                break  # unterminated; stop rather than swallow the file
            scalars.append((self.i, ord(text[self.i])))
            self.i += 1
        self.literals.append(scalars)


def scan_text(text):
    """[(line, code, rule, literal text)] for one Swift source."""
    lexer = Lexer(text)
    lexer.code()
    hits = []
    for scalars in lexer.literals:
        shown = "".join(chr(code) for _, code in scalars if code >= 0x20)[:60]
        for offset, code, rule in judge(scalars):
            hits.append((text.count("\n", 0, offset) + 1, code, rule, shown))
    for offset, code in lexer.code_hits:
        rule = rule_for(code)
        if rule and code not in KEY_GLYPHS and code != RETURN_ARROW:
            hits.append((text.count("\n", 0, offset) + 1, code, rule, f"computed scalar 0x{code:X}"))
    return sorted(hits)


def scan(sources):
    """{file name: [(line, code, rule, literal)]}"""
    hits = {}
    for path in sorted(sources.glob("*.swift")):
        found = scan_text(path.read_text(errors="replace"))
        if found:
            hits[path.name] = found
    return hits


def report(hits):
    totals = {}
    for name, found in sorted(hits.items()):
        for line, code, rule, shown in found:
            totals[rule] = totals.get(rule, 0) + 1
            print(f"  {name}:{line}: {rule:7} U+{code:04X} {unicodedata.name(chr(code), 'UNNAMED')}  in \"{shown}\"")
    count = sum(totals.values())
    print("check-glyphs totals: " + (", ".join(f"{rule} {n}" for rule, n in sorted(totals.items())) or "none")
          + f"  ({count} hits in {len(hits)} files)")
    return count


def self_test():
    """--strict must exit 1 on every banned glyph form, exit 0 on clean code, comments and the allow-list."""
    script = str(Path(__file__).resolve())
    cases = [
        ("emoji literal", 'let s = "Saved \U0001F600"\n', 1),
        ("emoji escape", 'let s = "Saved \\u{1F600}"\n', 1),
        ("emoji presentation sign", 'let s = "Done \u2705"\n', 1),
        ("variation selector 16", 'let s = "\u2764\uFE0F"\n', 1),
        ("apple logo escape", 'let s = "\\u{F8FF}"\n', 1),
        ("ordinal indicator", 'let s = "45\u00BA"\n', 1),
        ("arrow", 'let s = "Next \u2192"\n', 1),
        ("arrow escape", 'let s = "\\u{2192}"\n', 1),
        ("dingbat check", 'let s = "\u2713 Done"\n', 1),
        ("block symbol", 'let s = "\u2B50"\n', 1),
        ("bare return arrow", 'let s = "\u21A9"\n', 1),
        ("interpolation string", 'let s = "n=\\(f("\U0001F600"))"\n', 1),
        ("raw string", 'let s = #"\\#u{2713}x \u2713"#\n', 1),
        ("multi-line string", 'let s = """\nline\n\u2605\n"""\n', 1),
        ("computed scalar", 'let s = String(UnicodeScalar(0x2713)!)\n', 1),
        ("key glyphs", 'let s = "\u21E7\u2318S \u21E5 \u2325 \u2303 \u238B"\n', 0),
        ("return arrow text form", 'let s = "\u21A9\uFE0E"\n', 0),
        ("typography", 'let s = "Photos \u203A Edit\u2026 1920 \u00D7 1080 45\u00B0 \u00B7"\n', 0),
        ("plain code", 'let s = "Saved"\nlet n = 5\n', 0),
        ("glyph in line comment", '// \u2713 done\nlet s = "x"\n', 0),
        ("glyph in block comment", '/* \u2192 /* nested \u2713 */ */\nlet s = "x"\n', 0),
        ("glyph in doc comment", '/// \u2192 arrow tool\nlet s = "x"\n', 0),
    ]
    failed = False
    for label, code, expected in cases:
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "Case.swift").write_text(code)
            got = subprocess.run([sys.executable, script, "--strict", "--sources", folder], capture_output=True).returncode
        print(f"  self-test {label}: exit {got} (expected {expected})")
        failed |= got != expected
    if failed:
        raise SystemExit("FAIL check-glyphs self-test")
    print("PASS check-glyphs self-test")


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
