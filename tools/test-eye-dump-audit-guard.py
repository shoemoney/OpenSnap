#!/usr/bin/env python3
"""Can-fail checks for the screenshot harness's protections (no GUI, no real app launched).

 (a) the real-store guard fails when any watched file or folder changes, shown on a scratch HOME;
 (b) tools/eye-dump-audit.sh never names original/ and never executes build/OpenSnap.app: a fake app proves the copy that
     runs is a re-identified temp copy, with no fixture and an isolated home/support;
 (c) the throwaway bundle id differs from both real ids, and a changed real store makes the whole script exit non-zero.
Run: python3 -I tools/test-eye-dump-audit-guard.py
"""
from pathlib import Path
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import real_store_guard as guard

SCRIPT = root / "tools" / "eye-dump-audit.sh"
GUARD_CLI = [sys.executable, "-I", str(root / "tools" / "real_store_guard.py")]
failures = []


def check(condition, message):
    print(("PASS " if condition else "FAIL ") + message, flush=True)
    if not condition:
        failures.append(message)


def make_home(base):
    """A scratch HOME laid out like the owner's, so the guard sees the same watched paths."""
    home = Path(base) / "home"
    guard.use_home(home)
    for folder in (guard.OLD_FOLDER,):
        (folder / "History").mkdir(parents=True)
        (folder / "History" / "entry.dat").write_bytes(b"first entry")
    guard.PREFERENCES.mkdir(parents=True)
    for plist in guard.REAL_STORE_FILES:
        plist.write_bytes(b"<plist>values</plist>")
    return home


def guard_run(home, *args):
    return subprocess.run(GUARD_CLI[:3] + ["--home", str(home), *args], capture_output=True, text=True)


def snapshot_then(home, state, tamper):
    assert guard_run(home, "snapshot", str(state)).returncode == 0
    tamper()
    return guard_run(home, "compare", str(state))


def test_guard(base):
    home = make_home(base)
    state = Path(base) / "state.json"
    entry = guard.OLD_FOLDER / "History" / "entry.dat"
    plist = guard.REAL_STORE_FILES[1]

    result = snapshot_then(home, state, lambda: None)
    check(result.returncode == 0 and "RESULT stores unchanged" in result.stdout, "guard: untouched stores compare clean")

    result = snapshot_then(home, state, lambda: entry.write_bytes(b"first entrY"))
    check(result.returncode == 1 and "changed" in result.stdout, "guard: an edited store file fails the guard")

    def same_size_same_mtime():
        stamp = entry.stat()
        entry.write_bytes(b"other bytes")
        os.utime(entry, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
    result = snapshot_then(home, state, same_size_same_mtime)
    check(result.returncode == 1, "guard: a content change with the same size and mtime is still caught (hash)")

    result = snapshot_then(home, state, lambda: plist.write_bytes(b"<plist>changed</plist>"))
    check(result.returncode == 1 and "changed" in result.stdout, "guard: a changed defaults plist fails the guard")

    result = snapshot_then(home, state, lambda: (guard.OLD_FOLDER / "History" / "new.dat").write_bytes(b"x"))
    check(result.returncode == 1 and "appeared" in result.stdout, "guard: a new file in a real store fails the guard")

    result = snapshot_then(home, state, entry.unlink)
    check(result.returncode == 1 and "disappeared" in result.stdout, "guard: a deleted store file fails the guard")
    entry.write_bytes(b"first entry")

    def create_opensnap_folder():
        guard.OPENSNAP_FOLDER.mkdir(parents=True)
    result = snapshot_then(home, state, create_opensnap_folder)
    check(result.returncode == 1 and "created" in result.stdout, "guard: merely creating the OpenSnap support folder fails the guard")
    shutil.rmtree(guard.OPENSNAP_FOLDER)

    result = snapshot_then(home, state, lambda: (guard.PREFERENCES / "com.shoemoney.opensnap.eyedump-1.plist").write_bytes(b"leftover"))
    check(result.returncode == 1 and "left behind" in result.stdout, "guard: a throwaway harness defaults plist left behind fails the guard")
    (guard.PREFERENCES / "com.shoemoney.opensnap.eyedump-1.plist").unlink()
    return home


def fake_app(base):
    """A bundle whose executable records how the harness launched it, then writes whatever its Resources/tamper.txt asks."""
    app = Path(base) / "Fake.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Resources").mkdir()
    (app / "Contents/Info.plist").write_text('<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                                             '"http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>'
                                             '<key>CFBundleExecutable</key><string>Fake</string>'
                                             '<key>CFBundleIdentifier</key><string>com.example.fake</string></dict></plist>')
    exe = app / "Contents/MacOS/Fake"
    exe.write_text("""#!/bin/sh
# args: --eye-dump-audit RAW --audit-appearance A --audit-icons M --audit-surfaces S --audit-sizes Z
RAW=$2
mkdir -p "$RAW"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$(dirname "$0")/../Info.plist")
{
    echo "exe=$0"
    echo "bundle=$BUNDLE"
    echo "support=${OPENSNAP_APP_SUPPORT-unset}"
    echo "fixture=${OPENSNAP_FIXTURE-unset}"
    echo "home=${HOME-unset}"
    echo "cfhome=${CFFIXED_USER_HOME-unset}"
    echo "args=$*"
} > "$RAW/launch-$$.txt"
TAMPER="$(dirname "$0")/../Resources/tamper.txt"
if [ -f "$TAMPER" ]; then while IFS= read -r target; do printf 'tampered' >> "$target" 2>>"$RAW/tamper-errors-$$.txt" || true; done < "$TAMPER"; fi
""")
    exe.chmod(exe.stat().st_mode | stat.S_IXUSR)
    return app


def run_script(out, app, home, extra_env=None, tamper=None):
    (app / "Contents/Resources/tamper.txt").unlink(missing_ok=True)
    if tamper:
        (app / "Contents/Resources/tamper.txt").write_text("\n".join(map(str, tamper)) + "\n")
    env = dict(os.environ, **(extra_env or {}))
    return subprocess.run(["sh", str(SCRIPT), str(out), "--app", str(app), "--guard-home", str(home), "--no-wait-gui", "--sha", "testsha",
                           "--groups", "main", "--appearances", "light", "--icons", "both"],
                          capture_output=True, text=True, env=env, timeout=300)


def read_launches(out):
    launches = []
    for path in sorted(Path(out).glob("raw-*/launch-*.txt")):
        launches.append(dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line))
    return launches


def test_script(base, home):
    text = SCRIPT.read_text()
    check(not re.search(r"original/", text), "script: never names original/")
    check(not re.search(r"build/OpenSnap\.app/Contents/MacOS", text), "script: never names the built binary path")
    check(not re.search(r"^\s*(export\s+)?OPENSNAP_FIXTURE=", text, re.M), "script: never sets OPENSNAP_FIXTURE")
    check(re.search(r'^APP="\$TMP/', text, re.M) is not None and "$APP/Contents/MacOS/$EXE" in text, "script: the only launch line runs the temp copy")

    app = fake_app(base)
    real_ids = {path.stem for path in guard.REAL_STORE_FILES}
    out = Path(base) / "out-clean"
    result = run_script(out, app, home)
    check(result.returncode == 0, f"script: a clean run exits 0 (got {result.returncode}: {result.stderr.strip()[-200:]})")
    launches = read_launches(out)
    check(len(launches) >= 1, "script: the fake app was launched")
    source_exe = str(app / "Contents/MacOS/Fake")
    for launch in launches:
        check(launch.get("exe") != source_exe and "/eye-dump-audit." in launch.get("exe", ""), "script: the executed binary is a temp copy, not the source bundle")
        bundle = launch.get("bundle", "")
        check(re.fullmatch(r"com\.shoemoney\.opensnap\.eyedump-\d+", bundle) is not None and bundle not in real_ids,
              f"script: throwaway bundle id {bundle} differs from the real ids {sorted(real_ids)}")
        check(launch.get("fixture") == "unset", "script: no OPENSNAP_FIXTURE reaches the app")
        tmp_root = launch.get("exe", "").split("/eye-dump-audit.")[0] + "/eye-dump-audit."
        check(launch.get("support", "").startswith(tmp_root) and launch.get("home", "").startswith(tmp_root) and launch.get("cfhome", "").startswith(tmp_root),
              "script: support, HOME and CFFIXED_USER_HOME are throwaway folders")
    check(any("--audit-icons sf" in launch.get("args", "") for launch in launches), "script: icon mode sf ran")
    check(not any("--audit-icons fa" in launch.get("args", "") for launch in launches) or any("FontAwesome7Pro" in str(p) for p in app.rglob("*")),
          "script: icon mode fa does not run without Font Awesome fonts in the source bundle")
    safety = (out / "safety.txt").read_text()
    check("RESULT stores unchanged" in safety and "FA unavailable" in safety, "script: safety.txt records unchanged stores and FA unavailable")

    # (c) a real-store change during the run fails the whole script, even though the app itself exited 0.
    out = Path(base) / "out-tampered"
    result = run_script(out, app, home, tamper=[guard.REAL_STORE_FILES[1]])
    check(result.returncode != 0 and "RESULT STORES CHANGED" in (out / "safety.txt").read_text(),
          "script: a changed real defaults plist makes the run exit non-zero and say so")
    guard.REAL_STORE_FILES[1].write_bytes(b"<plist>values</plist>")

    # The sandbox fence keeps the app out of the real stores entirely.
    if Path("/usr/bin/sandbox-exec").exists():
        folder_file = guard.OLD_FOLDER / "History" / "entry.dat"
        before = folder_file.read_bytes()
        out = Path(base) / "out-fenced"
        result = run_script(out, app, home, tamper=[folder_file])
        check(folder_file.read_bytes() == before and result.returncode == 0, "script: the sandbox fence stops the app writing into a real store folder")
        out = Path(base) / "out-unfenced"
        run_script(out, app, home, extra_env={"EYE_DUMP_AUDIT_NO_SANDBOX": "1"}, tamper=[folder_file])
        check(folder_file.read_bytes() != before and "RESULT STORES CHANGED" in (out / "safety.txt").read_text(),
              "script: without the fence the same write lands, and the hash guard catches it")
        folder_file.write_bytes(before)


with tempfile.TemporaryDirectory(prefix="eyedump-guard-test.") as scratch:
    scratch_home = test_guard(scratch)
    test_script(scratch, scratch_home)
if failures:
    raise SystemExit(f"FAIL test-eye-dump-audit-guard: {len(failures)} check(s) failed")
print("PASS test-eye-dump-audit-guard")
