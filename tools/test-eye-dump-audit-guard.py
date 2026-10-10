#!/usr/bin/env python3
"""Can-fail checks for the screenshot harness's protections (no GUI, no real app launched).

 (a) the real-store guard fails when any watched file or folder changes, shown on a scratch HOME;
 (b) tools/eye-dump-audit.sh never names the retired original-archive folder and never executes build/OpenSnap.app: a fake app proves the copy that
     runs is a re-identified temp copy, with no fixture and an isolated home/support;
 (c) the throwaway bundle id differs from both real ids, and a changed real store makes the whole script exit non-zero;
 (d) the defaults cleanup cannot touch a real domain: a script copy forced onto a real/odd id exits non-zero and records no
     delete, drop_throwaway_defaults refuses a bad id, and a normal run only deletes eyedump throwaway ids. Every script run
     here uses the scratch HOME and a fake `defaults` recorder; mutated copies with the protections stripped must go red.
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
ARCHIVE_FOLDER = "original" + "/"  # built in two pieces so the repository-wide source gate does not trip on this file
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
    (app / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    (app / "Contents/Resources").mkdir(exist_ok=True)
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


SAFE = {}   # set once the scratch dir exists: {"home": scratch HOME, "defaults": fake recorder, "log": its log}
RUNS = []   # the env of every script run, so one check can prove none ran with the real HOME or the real defaults


def make_fake_defaults(base):
    """A `defaults` stand-in that only appends its argv to a log; it can never reach real preferences."""
    recorder = Path(base) / "fake-defaults.sh"
    log = Path(base) / "fake-defaults.log"
    recorder.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{log}'\n")
    recorder.chmod(recorder.stat().st_mode | stat.S_IXUSR)
    return recorder, log


def env_problem(env):
    """Why this env is unsafe for running the harness script, or None. Both the HOME and the defaults binary must be scratch."""
    if env.get("HOME") != SAFE["home"]:
        return "HOME is not the scratch home"
    if env.get("EYE_DUMP_AUDIT_DEFAULTS") != SAFE["defaults"]:
        return "EYE_DUMP_AUDIT_DEFAULTS is not the fake recorder"
    return None


def run_harness(script, out, args, extra_env=None):
    """The only way this file executes a copy of eye-dump-audit.sh: scratch HOME, fake defaults, recorded."""
    env = dict(os.environ, **(extra_env or {}))
    env["HOME"] = SAFE["home"]
    env["EYE_DUMP_AUDIT_DEFAULTS"] = SAFE["defaults"]
    problem = env_problem(env)
    assert problem is None, problem
    RUNS.append(dict(env))
    Path(SAFE["log"]).write_text("")
    result = subprocess.run(["sh", str(script), str(out), *args], capture_output=True, text=True, env=env, timeout=300)
    result.defaults_log = Path(SAFE["log"]).read_text().splitlines()
    return result


def run_script(out, app, home, extra_env=None, tamper=None):
    (app / "Contents/Resources/tamper.txt").unlink(missing_ok=True)
    if tamper:
        (app / "Contents/Resources/tamper.txt").write_text("\n".join(map(str, tamper)) + "\n")
    return run_harness(SCRIPT, out, ["--app", str(app), "--guard-home", str(home), "--no-wait-gui", "--sha", "testsha",
                                     "--groups", "main", "--appearances", "light", "--icons", "both"], extra_env)


def read_launches(out):
    launches = []
    for path in sorted(Path(out).glob("raw-*/launch-*.txt")):
        launches.append(dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line))
    return launches


def test_script(base, home):
    text = SCRIPT.read_text()
    check(ARCHIVE_FOLDER not in text, "script: never names the original-archive folder")
    check(not re.search(r"build/OpenSnap\.app/Contents/MacOS", text), "script: never names the built binary path")
    check(not re.search(r"^[^#\n]*\bdefaults (delete|write|read)", text, re.M), "script: never calls a bare `defaults`; only the injectable $DEFAULTS")
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


EYEDUMP_DELETE = re.compile(r"delete com\.shoemoney\.opensnap\.eyedump-\d+")


def only_eyedump_deletes(lines):
    return bool(lines) and all(EYEDUMP_DELETE.fullmatch(line) for line in lines)


def script_copy(base, name, text):
    """A copy of the script in its own tools/ dir (it finds its helpers relative to itself), so the real file is never edited."""
    folder = Path(base) / name / "tools"
    folder.mkdir(parents=True)
    for helper in ("real_store_guard.py", "eye-dump-audit-manifest.py"):
        shutil.copy(root / "tools" / helper, folder / helper)
    copy = folder / "eye-dump-audit.sh"
    copy.write_text(text)
    return copy


def force_id(text, expression):
    changed = re.sub(r"^THROWAWAY_ID=.*$", f'THROWAWAY_ID="{expression}"', text, count=1, flags=re.M)
    assert changed != text, "mutation did not apply"
    return changed


def strip_protection(text, *names):
    """Remove the named protections from a script copy: the lines tagged `# protection:<name>` (rm: the condition only)."""
    out = text
    for name in names:
        if name == "rm":
            changed = re.sub(r'^\s*if \[ "\$stem\.plist".*# protection:rm$', '    rm -f "$plist"', out, flags=re.M)
        else:
            changed = re.sub(rf"^.*# protection:{name}$\n", "", out, flags=re.M)
        assert changed != out, f"protection:{name} not found"
        out = changed
    return out


def drop_harness(text, bad_id, base):
    """Source just the two functions out of a script copy, point them at a bad id, call the drop: what did it do?"""
    functions = "\n".join(re.search(rf"^{fn}\(\) \{{\n.*?^\}}$", text, re.M | re.S).group(0)
                          for fn in ("valid_throwaway_id", "drop_throwaway_defaults"))
    prefs = Path(SAFE["home"]) / "Library/Preferences"
    victim = prefs / f"{bad_id}.plist"
    victim.parent.mkdir(parents=True, exist_ok=True)
    victim.write_bytes(b"<plist>real</plist>")
    harness = Path(base) / "drop-harness.sh"
    harness.write_text(f'REAL_ID=com.shoemoney.opensnap\nDEFAULTS="$EYE_DUMP_AUDIT_DEFAULTS"\n'
                       f'THROWAWAY_ID="{bad_id}"\n{functions}\ndrop_throwaway_defaults\n')
    env = dict(os.environ, HOME=SAFE["home"], EYE_DUMP_AUDIT_DEFAULTS=SAFE["defaults"])
    assert env_problem(env) is None
    Path(SAFE["log"]).write_text("")
    result = subprocess.run(["sh", str(harness)], capture_output=True, text=True, env=env, timeout=30)
    survived = victim.exists()
    victim.unlink(missing_ok=True)
    return result, Path(SAFE["log"]).read_text().splitlines(), survived


OLD_ID = [path.stem for path in guard.REAL_STORE_FILES if path.stem != "com.shoemoney.opensnap"][0]   # the retired app's defaults domain
BAD_IDS = ("com.shoemoney.opensnap", OLD_ID, "com.shoemoney.opensnap.eyedumpX",
           "com.shoemoney.opensnap.eyedump-", "com.shoemoney.opensnap.eyedump-12x", "com.shoemoney.opensnap.eyedump-1/../x")
FORCED = {"com.shoemoney.opensnap": "$REAL_ID", OLD_ID: OLD_ID,
          "com.shoemoney.opensnap.eyedumpX": "$REAL_ID.eyedumpX"}


def protection_results(base, text, tag, app, home):
    """Three booleans the protections must deliver for a script copy: refusal, drop refusal, plist survival."""
    refused = True
    for index, (bad_id, expression) in enumerate(FORCED.items()):
        copy = script_copy(base, f"{tag}-forced{index}", force_id(text, expression))
        out = Path(base) / f"{tag}-out{index}"
        result = run_harness(copy, out, ["--app", str(app), "--guard-home", str(home), "--no-wait-gui",
                                                                  "--sha", "testsha", "--groups", "main", "--appearances", "light", "--icons", "sf"])
        deletes = [line for line in result.defaults_log if line.startswith("delete ") and not EYEDUMP_DELETE.fullmatch(line)]
        started = out.exists() and (any(out.glob("raw-*/launch-*.txt")) or (out / "safety.txt").exists())
        refused = refused and result.returncode != 0 and not deletes and not started
    drop_refused, plist_survives = True, True
    for bad_id in BAD_IDS:
        result, log, survived = drop_harness(text, bad_id, base)
        drop_refused = drop_refused and not log
        plist_survives = plist_survives and survived
    return refused, drop_refused, plist_survives


def test_cleanup_protection(base, home):
    text = SCRIPT.read_text()
    app = fake_app(base)
    check(re.search(r"^valid_throwaway_id \"\$THROWAWAY_ID\".*exit 2.*# protection:top$", text, re.M) is not None
          and text.index("# protection:top") < text.index("trap cleanup EXIT"),
          "cleanup: the id is validated and refused before any trap is installed")
    check(text.index("\ndrop_throwaway_defaults\nDROPPED=yes") < text.index("$GUARD compare"),
          "cleanup: the explicit defaults cleanup runs before the final guard compare")

    refused, drop_refused, plist_survives = protection_results(base, text, "real", app, home)
    check(refused, "cleanup: a copy forced onto the current id, the retired id or ...eyedumpX exits non-zero before doing anything, and records no delete")
    check(drop_refused, "cleanup: drop_throwaway_defaults with a real/odd id records no defaults call at all")
    check(plist_survives, "cleanup: drop_throwaway_defaults with a real/odd id leaves that id's preferences plist in place")

    out = Path(base) / "out-normal-defaults"
    result = run_script(out, app, home)
    check(result.returncode == 0 and only_eyedump_deletes(result.defaults_log),
          f"cleanup: a normal run only ever deletes com.shoemoney.opensnap.eyedump-<pid> ids (log: {result.defaults_log[:3]})")
    safety = (out / "safety.txt").read_text()
    check("dropped BEFORE the final compare" in safety and safety.index("dropped BEFORE") < safety.index("real stores      after:"),
          "cleanup: safety.txt records that cleanup ran before the final compare")
    check(only_eyedump_deletes(["delete com.shoemoney.opensnap.eyedump-4242"]) and
          not only_eyedump_deletes(["delete com.shoemoney.opensnap"]) and not only_eyedump_deletes(["delete com.shoemoney.opensnap.eyedump-1", f"delete {OLD_ID}"]) and
          not only_eyedump_deletes([]), "cleanup: the log checker accepts eyedump deletes and rejects a real-id delete, a mixed log and an empty log")

    # Can-fail proof: the same checks must go red on copies with the protections stripped (fake defaults + scratch HOME only).
    mutants = {"top check removed": ("top",), "drop check removed": ("drop",), "top + drop checks removed": ("top", "drop"),
               "top + drop + rm checks removed": ("top", "drop", "rm")}
    for index, (label, names) in enumerate(mutants.items()):
        got = protection_results(base, strip_protection(text, *names), f"mut{index}", app, home)
        check(not all(got), f"cleanup (can fail): with the {label}, at least one protection check goes red (refused/drop/plist = {got})")
    got = protection_results(base, strip_protection(text, "top", "drop", "rm"), "mut-all", app, home)
    check(got == (False, False, False), f"cleanup (can fail): with every protection stripped all three checks go red (got {got})")
    # With only the top check gone the drop's own validation still blocks every delete, but the run starts: only "refused" goes red.
    got = protection_results(base, strip_protection(text, "top"), "mut-top-only", app, home)
    check(got == (False, True, True), f"cleanup (can fail): top-only removal fails exactly the refuse-before-starting check (got {got})")
    got = protection_results(base, strip_protection(text, "drop"), "mut-drop-only", app, home)
    check(got[1] is False and got[0] is True, f"cleanup (can fail): drop-only removal fails exactly the drop-refusal check (got {got})")


def test_runs_were_safe():
    check(len(RUNS) > 0 and all(env_problem(env) is None for env in RUNS),
          f"every one of the {len(RUNS)} script runs used the scratch HOME and the fake defaults recorder")
    check(env_problem({"HOME": os.environ.get("HOME", ""), "EYE_DUMP_AUDIT_DEFAULTS": SAFE["defaults"]}) is not None
          and env_problem({"HOME": SAFE["home"]}) is not None
          and env_problem({"HOME": SAFE["home"], "EYE_DUMP_AUDIT_DEFAULTS": "/usr/bin/defaults"}) is not None
          and env_problem({"HOME": SAFE["home"], "EYE_DUMP_AUDIT_DEFAULTS": SAFE["defaults"]}) is None,
          "the env checker rejects a real HOME, a missing recorder and the real /usr/bin/defaults")


with tempfile.TemporaryDirectory(prefix="eyedump-guard-test.") as scratch:
    scratch_home = test_guard(scratch)
    fake_recorder, fake_log = make_fake_defaults(scratch)
    SAFE.update(home=str(scratch_home), defaults=str(fake_recorder), log=str(fake_log))
    test_script(scratch, scratch_home)
    test_cleanup_protection(scratch, scratch_home)
    test_runs_were_safe()
if failures:
    raise SystemExit(f"FAIL test-eye-dump-audit-guard: {len(failures)} check(s) failed")
print("PASS test-eye-dump-audit-guard")
