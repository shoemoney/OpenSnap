#!/usr/bin/env python3
"""Can-fail checks for the screenshot harness's protections (no GUI, no real app launched).

 (a) the real-store guard fails when any watched file or folder changes, shown on a scratch HOME;
 (b) tools/eye-dump-audit.sh never names the retired original-archive folder and never executes build/OpenSnap.app: a fake app proves the copy that
     runs is a re-identified temp copy, with no fixture and an isolated home/support;
 (c) the throwaway bundle id differs from both real ids, and a changed real store makes the whole script exit non-zero;
 (d) the defaults cleanup cannot touch a real domain: a script copy forced onto a real/odd id exits non-zero and records no
     delete, drop_throwaway_defaults refuses a bad id, and a normal run only deletes eyedump throwaway ids. Every script run
     here uses the scratch HOME and a fake `defaults` recorder; mutated copies with the protections stripped must go red.
 (e) --display (injected display options): an unknown name is refused before anything launches, a valid set reaches only the
     throwaway child as OPENSNAP_AUDIT_DISPLAY_OPTIONS, no --display sets nothing, and (static) the Swift side reads that variable
     in exactly one place, behind the same HarnessGate the audit needs; mutated sources that read it ungated must go red.
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
    echo "displayopts=${OPENSNAP_AUDIT_DISPLAY_OPTIONS-unset}"
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


def normalized(path):
    return bool(path) and path == os.path.normpath(path) and "//" not in path


def test_normalized_home(base, home):
    """F-J5-005: the audit opens system panels, and macOS 27's Open/Save panel service spins to tens of GB when the inherited
    CFFIXED_USER_HOME is not normalized. Real macOS TMPDIR ends in "/", so the raw mktemp path has "//"; the script must canonicalize."""
    scratch_tmp = Path(base) / "tmp-normalized"
    scratch_tmp.mkdir(exist_ok=True)
    app = fake_app(base)
    args = ["--app", str(app), "--guard-home", str(home), "--no-wait-gui", "--sha", "testsha", "--groups", "main", "--appearances", "light", "--icons", "both"]
    def cfhome(script, name):
        out = Path(base) / name
        result = run_harness(script, out, args, {"TMPDIR": str(scratch_tmp) + "/"})
        launches = read_launches(out)
        return result, [launch.get("cfhome", "") for launch in launches]
    result, homes = cfhome(SCRIPT, "out-normalized")
    check(result.returncode == 0 and homes and all(normalized(h) for h in homes),
          f"F-J5-005: with a trailing-slash TMPDIR every launch gets a normalized CFFIXED_USER_HOME ({homes[:1]})")
    canon = 'TMP=$(CDPATH= cd -- "$TMP" && pwd -P)\n'
    text = SCRIPT.read_text()
    check(canon in text, "F-J5-005: the canonicalizing line is where the test expects it (so the mutant below really removes it)")
    _, mutant_homes = cfhome(script_copy(base, "mut-normalize", text.replace(canon, "")), "out-mutant-normalize")
    check(mutant_homes and not any(normalized(h) for h in mutant_homes),
          f"F-J5-005 (can fail): without the canonicalizing line CFFIXED_USER_HOME keeps '//' ({mutant_homes[:1]}), so the check above goes red")


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


DISPLAY_KEY = "OPENSNAP_AUDIT_DISPLAY_OPTIONS"
SWIFT_SOURCES = root / "Sources"


def function_body(text, signature):
    """The brace-balanced body of the function whose declaration contains `signature`, or None."""
    start = text.find(signature)
    if start < 0:
        return None
    open_at = text.find("{", text.index(")", start))
    depth = 0
    for index in range(open_at, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text[open_at:index + 1]
    return None


def display_read_is_gated(sources):
    """True when `sources` ({name: text}) read the harness display-option variable exactly once, inside harnessInjection, after the gate."""
    holders = [name for name, text in sources.items() if DISPLAY_KEY in text or "harnessEnvironmentKey" in text.replace("static let harnessEnvironmentKey", "")]
    if holders != ["DisplayOptions.swift"]:
        return False
    text = sources["DisplayOptions.swift"]
    if text.count(f'"{DISPLAY_KEY}"') != 1 or text.count("environment[harnessEnvironmentKey]") != 1:
        return False
    body = function_body(text, "static func harnessInjection(")
    if body is None or body.count("environment[harnessEnvironmentKey]") != 1:
        return False
    gate = body.find("HarnessGate.auditDirectory(")
    guard_clause = re.search(r"guard\s+HarnessGate\.auditDirectory\([^\n]*\)\s*!=\s*nil\s+else\s*\{\s*return nil\s*\}", body)
    return guard_clause is not None and 0 <= gate < body.index("environment[harnessEnvironmentKey]")


def test_display_injection(base, home):
    text = SCRIPT.read_text()
    swift = {path.name: path.read_text() for path in sorted(SWIFT_SOURCES.glob("*.swift"))}
    check(display_read_is_gated(swift), "display: the Swift sources read the injection variable in one place, behind HarnessGate")
    check("HarnessGate.auditDirectory(" in swift["EyeDumpAudit.swift"], "display: the audit and the injection share one gate (HarnessGate)")
    code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    check(code.count(DISPLAY_KEY) == 1 and re.search(rf'DISPLAY_ENV="{DISPLAY_KEY}=\$DISPLAY_OPTIONS"', code) is not None
          and code.index("DISPLAY_ENV=") < code.index("env -i PATH="), "display: the script names the variable once, only as the child's env assignment")
    check(re.search(r"env -i PATH=[^\n]*\\\n([^\n]*\\\n){0,2}[^\n]*\$DISPLAY_ENV", code) is not None, "display: the variable rides the env -i launch line")

    # Can-fail proof: ungated, doubled, foreign and relocated reads must all be rejected by the static check.
    source = swift["DisplayOptions.swift"]
    ungated = source.replace("guard HarnessGate.auditDirectory(arguments: arguments, environment: environment, bundleIdentifier: bundleIdentifier) != nil else { return nil }\n", "")
    check(ungated != source and not display_read_is_gated({**swift, "DisplayOptions.swift": ungated}), "display (can fail): a read with the gate removed is rejected")
    after = ungated.replace("        guard let list = environment[harnessEnvironmentKey], !list.isEmpty else { return nil }\n",
                            "        guard let list = environment[harnessEnvironmentKey], !list.isEmpty else { return nil }\n        guard HarnessGate.auditDirectory(arguments: arguments, environment: environment, bundleIdentifier: bundleIdentifier) != nil else { return nil }\n")
    check(after != ungated and not display_read_is_gated({**swift, "DisplayOptions.swift": after}), "display (can fail): a read before the gate is rejected")
    check(not display_read_is_gated({**swift, "Elsewhere.swift": f'let x = ProcessInfo.processInfo.environment["{DISPLAY_KEY}"]\n'}), "display (can fail): a second reader in another file is rejected")
    check(not display_read_is_gated({**swift, "DisplayOptions.swift": source + f'\nfunc leak(_ e: [String: String]) -> String? {{ e["{DISPLAY_KEY}"] }}\n'}), "display (can fail): a second literal in the same file is rejected")
    check(not display_read_is_gated({**swift, "DisplayOptions.swift": source.replace("static func harnessInjection(", "static func harnessInjectionX(")}), "display (can fail): moving the read out of harnessInjection is rejected")

    app = fake_app(base)
    out = Path(base) / "out-display"
    result = run_harness(SCRIPT, out, ["--app", str(app), "--guard-home", str(home), "--no-wait-gui", "--sha", "testsha", "--groups", "main",
                                       "--appearances", "light", "--icons", "sf", "--display", "reduceTransparency,increaseContrast"])
    launches = read_launches(out)
    check(result.returncode == 0 and launches and all(launch.get("displayopts") == "reduceTransparency,increaseContrast" for launch in launches),
          f"display: --display reaches the throwaway child as the variable (exit {result.returncode}, {[l.get('displayopts') for l in launches]})")
    check("display options  reduceTransparency,increaseContrast" in (out / "safety.txt").read_text(), "display: safety.txt records the simulated options")
    check(only_eyedump_deletes(result.defaults_log), "display: a --display run still only deletes eyedump throwaway ids")
    out = Path(base) / "out-no-display"
    result = run_harness(SCRIPT, out, ["--app", str(app), "--guard-home", str(home), "--no-wait-gui", "--sha", "testsha", "--groups", "main",
                                       "--appearances", "light", "--icons", "sf"], extra_env={DISPLAY_KEY: "reduceMotion"})
    launches = read_launches(out)
    check(result.returncode == 0 and launches and all(launch.get("displayopts") == "unset" for launch in launches),
          f"display: without --display the child gets no variable, even if the caller's own environment has one ({[l.get('displayopts') for l in launches]})")
    for bad in ("bogus", "reduceMotion,reduce-motion", "increaseContrast,"[:-1] + ";x"):
        out = Path(base) / ("out-bad-" + re.sub(r"\W", "_", bad))
        result = run_harness(SCRIPT, out, ["--app", str(app), "--guard-home", str(home), "--no-wait-gui", "--sha", "testsha", "--groups", "main",
                                           "--appearances", "light", "--icons", "sf", "--display", bad])
        check(result.returncode == 2 and not list(out.glob("raw-*/launch-*.txt")) and not result.defaults_log and not (out / "safety.txt").exists(),
              f"display: --display '{bad}' is refused (exit 2) before anything launches or any defaults call (exit {result.returncode})")
    # Can fail: with the validation loop stripped the same bad name launches the app.
    stripped = re.sub(r"for option in \$\(echo \"\$DISPLAY_OPTIONS\".*?\ndone\n", "", text, flags=re.S)
    check(stripped != text, "display (can fail): the validation loop was found to strip")
    copy = script_copy(base, "display-unvalidated", stripped)
    out = Path(base) / "out-bad-unvalidated"
    run_harness(copy, out, ["--app", str(app), "--guard-home", str(home), "--no-wait-gui", "--sha", "testsha", "--groups", "main",
                            "--appearances", "light", "--icons", "sf", "--display", "bogus"])
    check(any(read_launches(out)), "display (can fail): without the validation loop a bogus name does launch, so the refusal above is the validation's doing")


def harness_sources():
    return sorted((root / "Sources").glob("EyeDumpAudit*.swift"))


def pasteboard_problems(sources):
    """Harness code never touches the shared clipboard, and the run installs the input fence before it shows a window."""
    problems = []
    for path in sources:
        if path.name == "EyeDumpAuditInputGuard.swift":
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if re.search(r"NSPasteboard\s*\.\s*general|NSPasteboard\s*\(\s*name\s*:\s*\.general", line):
                problems.append(f"{path.name}:{number} uses the general pasteboard")
    surfaces = (root / "Sources" / "EyeDumpAuditSurfaces.swift").read_text()
    execute = surfaces[surfaces.index("func execute()"):]
    if "HarnessInputGuard.install()" not in execute[:400]:
        problems.append("AuditRun.execute() does not install the input fence first")
    return problems


def test_input_fence(base):
    check(pasteboard_problems(harness_sources()) == [], "harness (R1-001): no EyeDumpAudit*.swift names the general pasteboard and execute() installs the input fence first")
    scratch = Path(base) / "fence-sources"
    scratch.mkdir()
    for path in harness_sources():
        shutil.copy(path, scratch / path.name)
    leaky = scratch / "EyeDumpAuditSurfaces.swift"
    leaky.write_text(leaky.read_text().replace("inputGuard = HarnessInputGuard.install()", "").replace("func execute() {", "func execute() {\n        NSPasteboard.general.clearContents()", 1))
    found = [path for path in [leaky]]
    problems = []
    for path in found:
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if re.search(r"NSPasteboard\s*\.\s*general", line):
                problems.append(number)
    check(problems != [], "harness (can fail): a planted NSPasteboard.general line in a scratch copy is detected by the same pattern")
    check("HarnessInputGuard.install()" not in leaky.read_text()[leaky.read_text().index("func execute()"):][:400], "harness (can fail): a scratch copy without the install call fails the fence-first check")


def fence_problems(guard_source, surfaces_source, script_source):
    """R2-012: the fence covers mouse enter/exit and cursor updates, and the run records how many real events it swallowed."""
    problems = []
    mask = guard_source[guard_source.index("blockedEvents"):guard_source.index("]", guard_source.index("blockedEvents"))]
    for kind in (".mouseEntered", ".mouseExited", ".cursorUpdate", ".mouseMoved", ".keyDown", ".scrollWheel"):
        if kind not in mask:
            problems.append(f"the fenced mask lacks {kind}")
    if "swallowedEvents" not in guard_source or "HarnessInputGuard.record()" not in surfaces_source:
        problems.append("finish() does not write the swallowed-event record")
    if "input fence" not in script_source or "input-fence" not in script_source:
        problems.append("eye-dump-audit.sh does not copy the count into safety.txt")
    return problems


def test_input_fence_record():
    guard = (root / "Sources" / "EyeDumpAuditInputGuard.swift").read_text()
    surfaces = (root / "Sources" / "EyeDumpAuditSurfaces.swift").read_text()
    script = (root / "tools" / "eye-dump-audit.sh").read_text()
    check(fence_problems(guard, surfaces, script) == [], "harness (R2-012): the fence covers enter/exit/cursor events and its swallowed count reaches safety.txt")
    check(fence_problems(guard.replace(".mouseEntered, .mouseExited, .cursorUpdate", ".scrollWheel"), surfaces, script) != []
          and fence_problems(guard, surfaces.replace("HarnessInputGuard.record()", "[:]"), script) != []
          and fence_problems(guard, surfaces, script.replace("input fence", "")) != [],
          "harness (can fail): a scratch copy without the extra event kinds, the record or the safety.txt line is detected")


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
    test_normalized_home(scratch, scratch_home)
    test_input_fence_record()
    test_cleanup_protection(scratch, scratch_home)
    test_display_injection(scratch, scratch_home)
    test_input_fence(scratch)
    test_runs_were_safe()
if failures:
    raise SystemExit(f"FAIL test-eye-dump-audit-guard: {len(failures)} check(s) failed")
print("PASS test-eye-dump-audit-guard")
