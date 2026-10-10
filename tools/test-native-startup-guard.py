#!/usr/bin/env python3
"""Can-fail checks for tools/test-native-startup.py's protections (no GUI; only a fake app is ever launched).

 (a) static: the script never executes the in-place build/OpenSnap.app binary, validates the throwaway id before any cleanup
     exists, calls `defaults` only through the injectable OPENSNAP_STARTUP_DEFAULTS path, and drops the defaults domain before
     the final store compare;
 (b) dynamic, with a fake app, a scratch HOME and a fake `defaults` recorder: the executed binary is a re-identified temp copy
     with a com.shoemoney.opensnap.startup-<pid> id and a throwaway HOME/support; the only defaults call is a delete of that id;
 (c) a run that touches the scratch "real" stores, or leaves a throwaway defaults plist behind, exits non-zero;
 (d) mutated script copies (id forced onto the real id, protections stripped, compare removed, in-place launch) go red where the
     original stays green. Every script run here uses the scratch HOME and the fake recorder; mutated copies never see a real store.
Run: python3 -I tools/test-native-startup-guard.py
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

SCRIPT = root / "tools" / "test-native-startup.py"
failures = []
SAFE = {}
RUNS = []
DELETE_OK = re.compile(r"delete com\.shoemoney\.opensnap\.startup-\d+")


def check(condition, message):
    print(("PASS " if condition else "FAIL ") + message, flush=True)
    if not condition:
        failures.append(message)


def make_home(base):
    home = Path(base) / "home"
    guard.use_home(home)
    (guard.OLD_FOLDER / "History").mkdir(parents=True)
    (guard.OLD_FOLDER / "History" / "entry.dat").write_bytes(b"first entry")
    guard.PREFERENCES.mkdir(parents=True)
    for plist in guard.REAL_STORE_FILES:
        plist.write_bytes(b"<plist>values</plist>")
    return home


def fake_app(base):
    """A bundle whose executable records how it was launched, writes the smoke evidence, then tampers with whatever tamper.txt names."""
    app = Path(base) / "Fake.app"
    (app / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    (app / "Contents/Resources").mkdir(exist_ok=True)
    (app / "Contents/Info.plist").write_text('<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                                             '"http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>'
                                             '<key>CFBundleExecutable</key><string>Fake</string>'
                                             '<key>CFBundleIdentifier</key><string>com.example.fake</string></dict></plist>')
    exe = app / "Contents/MacOS/Fake"
    exe.write_text("""#!/bin/sh
E="$OPENSNAP_EVIDENCE_DIR"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$(dirname "$0")/../Info.plist")
{
    echo "exe=$0"
    echo "bundle=$BUNDLE"
    echo "support=${OPENSNAP_APP_SUPPORT-unset}"
    echo "home=${HOME-unset}"
    echo "cfhome=${CFFIXED_USER_HOME-unset}"
    echo "args=$*"
} > "$E/launch-$$.txt"
printf 'native startup, .opensnap editable save/load, PNG export succeeded' > "$E/smoke-result.txt"
printf '{"format": "com.shoemoney.opensnap.document"}' > "$E/smoke.opensnap"
printf '\\211PNG\\r\\n\\032\\n0000' > "$E/smoke.png"
printf '{"modernChrome": true, "toolButtonClass": "GlassChromeButton", "glassSurfaces": 7}' > "$E/smoke-appearance.json"
TAMPER="$(dirname "$0")/../Resources/tamper.txt"
if [ -f "$TAMPER" ]; then while IFS= read -r target; do printf 'tampered' >> "$target" 2>/dev/null || true; done < "$TAMPER"; fi
""")
    exe.chmod(exe.stat().st_mode | stat.S_IXUSR)
    return app


def make_fake_defaults(base):
    recorder = Path(base) / "fake-defaults.sh"
    log = Path(base) / "fake-defaults.log"
    recorder.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{log}'\n")
    recorder.chmod(recorder.stat().st_mode | stat.S_IXUSR)
    return recorder, log


def env_problem(env):
    if env.get("HOME") != SAFE["home"]:
        return "HOME is not the scratch home"
    if env.get("OPENSNAP_STARTUP_DEFAULTS") != SAFE["defaults"]:
        return "OPENSNAP_STARTUP_DEFAULTS is not the fake recorder"
    return None


def run_smoke(script, app, home, tamper=None):
    """The only way this file executes a copy of the script: scratch HOME and TMPDIR, fake defaults, recorded."""
    (app / "Contents/Resources/tamper.txt").unlink(missing_ok=True)
    if tamper:
        (app / "Contents/Resources/tamper.txt").write_text("\n".join(map(str, tamper)) + "\n")
    env = dict(os.environ, HOME=SAFE["home"], OPENSNAP_STARTUP_DEFAULTS=SAFE["defaults"], TMPDIR=SAFE["tmp"])
    problem = env_problem(env)
    assert problem is None, problem
    RUNS.append(dict(env))
    Path(SAFE["log"]).write_text("")
    result = subprocess.run([sys.executable, "-I", str(script), "--app", str(app), "--guard-home", str(home), "--timeout", "20"],
                            capture_output=True, text=True, env=env, timeout=240)
    result.defaults_log = Path(SAFE["log"]).read_text().splitlines()
    result.launches = []
    for evidence in Path(SAFE["tmp"]).glob("startup-smoke-*"):
        for path in sorted(evidence.glob("*/launch-*.txt")):
            result.launches.append(dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line))
        shutil.rmtree(evidence, ignore_errors=True)
    return result


def script_copy(base, name, text):
    folder = Path(base) / name / "tools"
    folder.mkdir(parents=True)
    shutil.copy(root / "tools" / "real_store_guard.py", folder / "real_store_guard.py")
    copy = folder / "test-native-startup.py"
    copy.write_text(text)
    return copy


def mutate(text, pattern, replacement):
    changed, count = re.subn(pattern, replacement, text, count=1, flags=re.M)
    assert count == 1, f"mutation did not apply: {pattern}"
    return changed


def runs_only_copy(text):
    launches = re.findall(r"^.*Popen\(.*$", text, re.M)
    return len(launches) == 1 and "str(executable)" in launches[0] and "source_binary" not in launches[0]


def test_static(text):
    check("build/OpenSnap.app/Contents/MacOS" not in text, "static: never names the in-place binary path")
    check(runs_only_copy(text), "static: the only process launch runs `executable`, the re-identified temp copy")
    check(re.search(r"^\s*executable = prepare_copy\(source_app, copy\)$", text, re.M) is not None
          and "source_binary.read_bytes()" in text,
          "static: the source binary is only read (hashed), never executed")
    check("setdefault" not in text and 'THROWAWAY_ID = f"{REAL_ID}.startup-{os.getpid()}"' in text,
          "static: the throwaway id is <real id>.startup-<pid>")
    check(text.index("# protection:top") < text.index("\ntry:\n"),
          "static: the id is validated and refused before the try/finally cleanup exists")
    check(re.search(r"^if not valid_throwaway_id\(THROWAWAY_ID\):  # protection:top$", text, re.M) is not None
          and "# protection:drop" in text and "# protection:rm" in text,
          "static: validation guards the top, the defaults delete and the plist removal")
    check(not re.search(r"""["']/?(usr/bin/)?defaults["']\s*[,\]]""", text.replace('"/usr/bin/defaults")', "")),
          "static: `defaults` is never spelled out as a command; only the injectable DEFAULTS is run")
    check('DEFAULTS = os.environ.get("OPENSNAP_STARTUP_DEFAULTS", "/usr/bin/defaults")' in text
          and "subprocess.run([DEFAULTS, \"delete\", THROWAWAY_ID]" in text,
          "static: defaults is called through OPENSNAP_STARTUP_DEFAULTS")
    finally_block = text[text.index("\nfinally:\n"):]
    check(finally_block.index("drop_throwaway_defaults()") < finally_block.index("guard.compare("),
          "static: the defaults domain is dropped before the final store compare")
    check("env=env" in text and '"CFFIXED_USER_HOME": str(home)' in text and '"OPENSNAP_APP_SUPPORT": str(support)' in text
          and '"HOME": str(home)' in text and '"TMPDIR": str(temp)' in text and "**os.environ" not in text and "os.environ |" not in text,
          "static: the child gets a minimal env with throwaway HOME, CFFIXED_USER_HOME, TMPDIR and OPENSNAP_APP_SUPPORT")


def test_dynamic(base, home, app):
    real_ids = {path.stem for path in guard.REAL_STORE_FILES}
    result = run_smoke(SCRIPT, app, home)
    check(result.returncode == 0, f"dynamic: a clean run exits 0 (got {result.returncode}: {(result.stdout + result.stderr).strip()[-300:]})")
    check(len(result.launches) == 1, "dynamic: the fake app was launched once")
    launch = result.launches[0] if result.launches else {}
    check(launch.get("exe") != str(app / "Contents/MacOS/Fake") and "/opensnap-startup-" in launch.get("exe", ""),
          "dynamic: the executed binary is the temp copy, not the source bundle")
    bundle = launch.get("bundle", "")
    check(re.fullmatch(r"com\.shoemoney\.opensnap\.startup-\d+", bundle) is not None and bundle not in real_ids,
          f"dynamic: throwaway bundle id {bundle} differs from the real ids {sorted(real_ids)}")
    scratch = launch.get("exe", "").split("/Fake.app/")[0] + "/"
    check(all(launch.get(key, "").startswith(scratch) for key in ("support", "home", "cfhome")),
          "dynamic: support, HOME and CFFIXED_USER_HOME are inside the throwaway folder")
    check(launch.get("home") != SAFE["home"] and launch.get("cfhome") != SAFE["home"], "dynamic: the child never sees the process HOME")
    check(bool(result.defaults_log) and all(DELETE_OK.fullmatch(line) and line.split()[1] == bundle for line in result.defaults_log),
          f"dynamic: the only defaults call deletes the throwaway id (log: {result.defaults_log})")

    guard.REAL_STORE_FILES[1].write_bytes(b"<plist>values</plist>")
    result = run_smoke(SCRIPT, app, home, tamper=[guard.REAL_STORE_FILES[1]])
    check(result.returncode != 0 and "STORE CHANGED" in result.stdout, "dynamic: a changed real defaults plist makes the run exit non-zero")
    guard.REAL_STORE_FILES[1].write_bytes(b"<plist>values</plist>")

    leftover = guard.PREFERENCES / "com.shoemoney.opensnap.startup-999999.plist"
    result = run_smoke(SCRIPT, app, home, tamper=[leftover])
    check(result.returncode != 0 and "left behind" in result.stdout, "dynamic: a throwaway startup plist left behind fails the run")
    leftover.unlink(missing_ok=True)

    result = run_smoke(SCRIPT, app, home, tamper=[guard.OLD_FOLDER / "History" / "entry.dat"])
    check(result.returncode != 0 and "STORE CHANGED" in result.stdout, "dynamic: a changed real store file makes the run exit non-zero")
    (guard.OLD_FOLDER / "History" / "entry.dat").write_bytes(b"first entry")


def test_mutations(base, home, app, text):
    # id forced onto the real id: the original refuses before doing anything; with the protections stripped the real delete is issued.
    forced = mutate(text, r"^THROWAWAY_ID = .*$", 'THROWAWAY_ID = REAL_ID')
    result = run_smoke(script_copy(base, "forced", forced), app, home)
    check(result.returncode != 0 and not result.defaults_log and not result.launches,
          "mutation: a copy forced onto the real id exits non-zero before launching or recording any defaults call")
    stripped = mutate(forced, r"^if not valid_throwaway_id\(THROWAWAY_ID\):  # protection:top$", "if False:")
    stripped = mutate(stripped, r"^    if not valid_throwaway_id\(THROWAWAY_ID\):  # protection:drop$", "    if False:")
    result = run_smoke(script_copy(base, "stripped", stripped), app, home)
    check("delete com.shoemoney.opensnap" in result.defaults_log,
          "mutation: with the validation stripped, the same forced id DOES reach `defaults delete` (so the validation is what stops it)")

    # the in-place launch: a copy that executes the source binary is caught by the temp-copy check.
    inplace = mutate(text, r'\["/usr/bin/arch", "-" \+ arch, str\(executable\)', '["/usr/bin/arch", "-" + arch, str(source_binary)')
    result = run_smoke(script_copy(base, "inplace", inplace), app, home)
    launch = result.launches[0] if result.launches else {}
    check(launch.get("exe") == str(app / "Contents/MacOS/Fake") and "/opensnap-startup-" not in launch.get("exe", ""),
          "mutation: a copy that runs the source binary is visible to the executed-binary check")
    check(not runs_only_copy(inplace), "mutation: the static launch check goes red on the in-place edit")

    # the compare removed: the tampered run is no longer caught.
    blind = mutate(text, r"^    store_problems = guard\.compare\(.*$", "    store_problems = []")
    guard.REAL_STORE_FILES[1].write_bytes(b"<plist>values</plist>")
    result = run_smoke(script_copy(base, "blind", blind), app, home, tamper=[guard.REAL_STORE_FILES[1]])
    check(result.returncode == 0, "mutation: with the compare removed the same tamper passes (so the compare is what catches it)")
    guard.REAL_STORE_FILES[1].write_bytes(b"<plist>values</plist>")

    # the drop call removed: nothing deletes the throwaway defaults domain.
    nodrop = mutate(text, r"^(    )drop_throwaway_defaults\(\)$", r"\1pass")
    result = run_smoke(script_copy(base, "nodrop", nodrop), app, home)
    check(not result.defaults_log, "mutation: a copy without the drop call issues no defaults delete (the dynamic delete check sees it)")


def main():
    text = SCRIPT.read_text()
    test_static(text)
    with tempfile.TemporaryDirectory() as raw:
        base = os.path.realpath(raw)
        home = make_home(base)
        recorder, log = make_fake_defaults(base)
        tmp = Path(base) / "tmp"
        tmp.mkdir()
        SAFE.update(home=str(home), defaults=str(recorder), log=str(log), tmp=str(tmp))
        app = fake_app(base)
        test_dynamic(base, home, app)
        test_mutations(base, home, app, text)
        check(all(env_problem(env) is None for env in RUNS), f"every script run used the scratch HOME and the fake defaults ({len(RUNS)} runs)")
    if failures:
        raise SystemExit("FAIL native-startup-guard: " + "; ".join(failures))
    print("PASS native-startup-guard")


main()
