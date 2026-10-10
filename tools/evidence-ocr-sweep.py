#!/usr/bin/env python3
"""OCR sweep over committed evidence images: flags text that no app string or fixture explains.

    uv run --with pyobjc-framework-Vision --with pyobjc-framework-Quartz python3 tools/evidence-ocr-sweep.py docs/design/evidence

Reads every .png/.jpg/.jpeg under the given folders with Vision (VNRecognizeTextRequest) and compares each recognised line with a
vocabulary built from the app's own string literals (Sources/*.swift), the test and harness fixtures (tests/*.swift, tools/e2e-session.sh,
tools/e2e-inventory.py) and a short list of system UI words. A line is flagged when it holds two or more words the vocabulary does not
explain, or one long unexplained word. Evidence is synthetic, so a flagged line is either a missing vocabulary entry or real text that got
typed or pasted into a capture window; a person looks at each flagged image.

The report goes to /tmp/ocr-sweep.txt (override with --report) and is NEVER written into the repo: it can contain private text.
`--self-test` proves the flagging can fail without reading any image (offline, no Vision needed).
"""
from collections import Counter, defaultdict
from multiprocessing import Pool
from pathlib import Path
import argparse, re, sys

ROOT = Path(__file__).resolve().parent.parent
IMAGE = re.compile(r"\.(png|jpe?g)$", re.I)
WORD = re.compile(r"[A-Za-z][A-Za-z'’]+")
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

# macOS and system-panel vocabulary that appears around the app: menus, Save/Open panels, Colors, Fonts, alerts, Finder, Dock.
SYSTEM_WORDS = """
file edit view window help format tools tool app apple about services hide others show all quit close minimize zoom fill centre center
move resize tile left right top bottom enter exit full screen bring front cut copy paste delete select undo redo duplicate
save open recent clear menu cancel done ok yes no next previous back forward replace find spelling grammar substitutions transformations
speech start stop emoji symbols dictation fonts colors color panel size style bold italic underline strikethrough outline shadow
untitled desktop documents downloads pictures library applications home icloud drive network devices favorites tags locations
name tags kind date modified created size where format export options cancel choose browse allow deny don replace stop continue
preferences settings general advanced privacy security accessibility display reduce transparency increase contrast motion differentiate
without color light dark appearance automatic system default custom none auto preview finder dock trash untitled copy of
search results sidebar list icons columns gallery group sort arrange view by hide show toolbar customize
vertical horizontal angle opacity weight width height points pixels percent
monday tuesday wednesday thursday friday saturday sunday january february march april may june july august september october november december
am pm today yesterday tomorrow
the and for with from this that your you are not can will has have was were its into onto over under than then when what who how why
""".split()


def vocabulary():
    words = set(SYSTEM_WORDS)
    sources = sorted((ROOT / "Sources").glob("*.swift")) + sorted((ROOT / "tests").glob("*.swift"))
    sources += [ROOT / "tools" / "e2e-session.sh", ROOT / "tools" / "e2e-inventory.py", ROOT / "tools" / "eye-dump-audit.sh"]
    for path in sources:
        if not path.exists():
            continue
        text = path.read_text(errors="ignore")
        for literal in LITERAL.findall(text):
            words.update(w.lower().strip("'’") for w in WORD.findall(literal))
    return {w for w in words if w}


def unexplained(line, vocab):
    """The words of one recognised line that the vocabulary does not explain (length 3 or more; shorter ones are noise)."""
    out = []
    for word in WORD.findall(line):
        clean = word.lower().strip("'’")
        if len(clean) < 3 or clean in vocab:
            continue
        if clean.endswith("s") and clean[:-1] in vocab:
            continue
        out.append(word)
    return out


def flagged(line, vocab):
    words = unexplained(line, vocab)
    return len(words) >= 2 or any(len(w) >= 6 for w in words)


def recognise(path):
    import Vision
    from Foundation import NSURL, NSAutoreleasePool
    pool = NSAutoreleasePool.alloc().init()
    try:
        request = Vision.VNRecognizeTextRequest.alloc().init()
        request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
        request.setUsesLanguageCorrection_(False)
        handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(NSURL.fileURLWithPath_(str(path)), None)
        ok, error = handler.performRequests_error_([request], None)
        if not ok:
            return str(path), None
        lines = []
        for observation in request.results() or []:
            candidate = observation.topCandidates_(1)
            if candidate:
                lines.append((str(candidate[0].string()), float(candidate[0].confidence())))
        return str(path), lines
    finally:
        del pool


def self_test():
    vocab = {"save", "history", "arrow", "hello", "opensnap"}
    checks = [
        ("an explained line is not flagged", flagged("Save to History", vocab) is False),
        ("a sentence of unknown words is flagged", flagged("good to hear from somebody about plans", vocab) is True),
        ("one long unexplained word is flagged", flagged("Confidential", vocab) is True),
        ("short noise is not flagged", flagged("ab 12 x", vocab) is False),
        ("a plural of a known word is explained", flagged("Arrows", vocab) is False),
    ]
    bad = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print("PASS" if ok else "FAIL", "ocr-sweep self-test:", name)
    if bad:
        raise SystemExit(1)
    print("PASS ocr-sweep self-test")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folders", nargs="*")
    parser.add_argument("--report", default="/tmp/ocr-sweep.txt")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    if options.self_test:
        return self_test()
    report = Path(options.report).resolve()
    if ROOT in report.parents:
        raise SystemExit("refusing: the report may contain private text and must not be written inside the repo")
    images = sorted(p for folder in options.folders for p in Path(folder).rglob("*") if p.is_file() and IMAGE.search(p.name))
    vocab = vocabulary()
    print(f"{len(images)} images, vocabulary of {len(vocab)} words", flush=True)
    results, unreadable = [], []
    with Pool(options.jobs) as pool:
        for index, (path, lines) in enumerate(pool.imap_unordered(recognise, images, chunksize=4), 1):
            if lines is None:
                unreadable.append(path)
            else:
                results.append((path, lines))
            if index % 200 == 0:
                print(f"  {index}/{len(images)}", flush=True)
    results.sort()
    seen = Counter()
    per_image = defaultdict(list)
    for path, lines in results:
        for text, confidence in lines:
            if flagged(text, vocab):
                per_image[path].append((text, confidence))
                seen[text] += 1
    with report.open("w") as out:
        out.write(f"# OCR sweep: {len(images)} images, {len(per_image)} with flagged lines, {len(unreadable)} unreadable\n")
        out.write("# path\tconfidence\ttext   (private: do not copy into the repo)\n")
        for path in sorted(per_image):
            for text, confidence in per_image[path]:
                out.write(f"{path}\t{confidence:.2f}\t{text}\n")
        out.write("\n# unreadable\n" + "\n".join(unreadable) + "\n")
        out.write("\n# flagged lines by frequency (a line repeated across many captures is almost always UI)\n")
        for text, count in seen.most_common():
            out.write(f"{count}\t{text}\n")
    print(f"{len(images)} images, {len(per_image)} with flagged lines, {len(unreadable)} unreadable; report: {report}")


if __name__ == "__main__":
    sys.exit(main())
