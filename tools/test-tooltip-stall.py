#!/usr/bin/env python3
"""Freeze the app-tooltip suite while its hover wait is in flight; the suite must still pass.

A cold full `tools/test.py` run starts dozens of compiles at once, so a suite binary can be descheduled for longer than a fixed
`spin(0.3)` while its 0.05 s hover timer is due; the run loop then times out with the timer unfired and the suite traps. The suite
waits on the event instead (`wait(...)`). This stalls the process with SIGSTOP right after the hover wait begins, in a scratch
build, and `--self-test` proves the check can fail by rebuilding the suite with the old fixed-length wait.
"""
from pathlib import Path
import platform, random, signal, subprocess, sys, tempfile, time

root = Path(__file__).resolve().parent.parent
MARKER = "AppToolTipTests: hover wait begins"
SOURCES = [root / "Sources/AppToolTip.swift", root / "Sources/DesignTokens.swift", root / "tests/ContrastProbe.swift"]
TEST = root / "tests/AppToolTipTests.swift"
OLD_WAIT = "while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }"

def build(directory, test_source):
    test = directory / "AppToolTipTests.swift"
    test.write_text(test_source)
    binary = directory / "app-tooltip-tests"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-target", platform.machine() + "-apple-macosx26.0", "-D", "APP_TOOLTIP_TESTS",
                    *map(str, SOURCES), str(test), "-o", str(binary)], cwd=root, check=True, capture_output=True)
    return binary

def stalled_run(binary):
    """True when the suite passed although it was frozen for 0.6 s inside its hover wait."""
    process = subprocess.Popen([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=root)
    seen = ""
    while MARKER not in seen:
        line = process.stderr.readline()
        if not line:
            break
        seen += line
    time.sleep(random.uniform(0, 0.03))  # inside the 0.05 s delay, so the timer is due only after the freeze
    process.send_signal(signal.SIGSTOP)
    time.sleep(0.6)
    process.send_signal(signal.SIGCONT)
    process.communicate()
    return process.returncode == 0

def main():
    self_test = "--self-test" in sys.argv
    source = TEST.read_text()
    if OLD_WAIT not in source:
        raise SystemExit("FAIL tooltip-stall: the suite's wait helper changed; update OLD_WAIT in this tool")
    with tempfile.TemporaryDirectory(prefix="tooltip-stall.") as scratch:
        if self_test:
            binary = build(Path(scratch), source.replace(OLD_WAIT, "RunLoop.main.run(until: Date().addingTimeInterval(0.3))"))
            if all(stalled_run(binary) for _ in range(25)):
                raise SystemExit("FAIL tooltip-stall self-test: the fixed-length wait survived 25 freezes, so this check cannot fail")
            print("PASS tooltip-stall self-test (the fixed-length wait trapped under a freeze)")
            return
        binary = build(Path(scratch), source)
        runs = 8
        failed = sum(not stalled_run(binary) for _ in range(runs))
        if failed:
            raise SystemExit(f"FAIL tooltip-stall: {failed} of {runs} frozen runs failed")
        print(f"PASS tooltip-stall ({runs} runs frozen for 0.6 s inside the hover wait)")

main()
