#!/usr/bin/env python3
"""Can-fail checks for the interactive E2E launcher tools/e2e-session.sh (no GUI, no real app launched, fast).

Every script run here uses a SCRATCH HOME and TMPDIR, a fake `defaults` recorder (E2E_DEFAULTS) and a fake app bundle. Mutated copies
with a protection stripped are run only that way too: the memory note can-fail-proofs-destructive-cleanup is why (a mutated harness
once ran its EXIT cleanup against the real defaults domain). Proved, each with a mutant that must go red:
 (a) the throwaway id is validated before anything exists (start) and before anything destructive (stop reads an id from disk);
 (b) both real ids (current and retired) and odd ids are refused: no defaults call, no plist removed;
 (c) only the temp copy executes, under env -i with throwaway HOME / CFFIXED_USER_HOME / TMPDIR / OPENSNAP_APP_SUPPORT;
 (d) defaults are dropped only for a valid id, the temp dir is removed only when it is a marked session dir, a pid is signalled only
     when it is that session's app copy;
 (e) cleanup runs BEFORE the real-store compare (an evil `defaults` that damages a real store during cleanup must make stop fail);
 (f) a tampered real store makes stop exit non-zero; SIGKILL follows an ignored SIGTERM;
 (g) --aws never echoes credential content (sentinel in a fake credentials file never appears in any output or file);
 (h) the E2E inventory (tools/e2e-inventory.py): docs/design/e2e/inventory.json and the coverage matrix match the sources, every FAIcon case and
     menu symbol is listed, every pre-filled proof names a real test, and scratch copies with a drift or a bad proof make --check fail.
Run: python3 -I tools/test-e2e-session-guard.py
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import real_store_guard as guard

SCRIPT = root / "tools" / "e2e-session.sh"
failures = []
SAFE = {}
RUNS = []
SENTINEL = "SENTINEL-SECRET-do-not-print-7f3a9c"
REAL_ID = "com.shoemoney.opensnap"


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
    (home / ".aws").mkdir()
    (home / ".aws" / "credentials").write_text(f"[default]\naws_access_key_id = AKIA{SENTINEL}\naws_secret_access_key = {SENTINEL}\n")
    return home


def fake_app(base, name="Fake.app"):
    """A bundle whose executable records how it was launched, then idles. Resources/ignore-term makes it ignore SIGTERM."""
    app = Path(base) / name
    (app / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    (app / "Contents/Resources").mkdir(exist_ok=True)
    (app / "Contents/Info.plist").write_text('<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                                             '"http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>'
                                             '<key>CFBundleExecutable</key><string>Fake</string>'
                                             '<key>CFBundleIdentifier</key><string>com.example.fake</string></dict></plist>')
    exe = app / "Contents/MacOS/Fake"
    exe.write_text("""#!/bin/sh
HERE=$(dirname "$0")
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$HERE/../Info.plist")
{
    echo "exe=$0"
    echo "bundle=$BUNDLE"
    echo "support=${OPENSNAP_APP_SUPPORT-unset}"
    echo "fixture=${OPENSNAP_FIXTURE-unset}"
    echo "home=${HOME-unset}"
    echo "cfhome=${CFFIXED_USER_HOME-unset}"
    echo "tmpdir=${TMPDIR-unset}"
    echo "aws=${AWS_SHARED_CREDENTIALS_FILE-unset}"
    echo "leak=${E2E_LEAK_SENTINEL-unset}"
    echo "args=$*"
} > "${TMPDIR:-/tmp}/launch.txt"
[ -f "$HERE/../Resources/ignore-term" ] && trap '' TERM
while :; do sleep 1; done
""")
    exe.chmod(exe.stat().st_mode | stat.S_IXUSR)
    return app


def make_recorders(base):
    """`defaults` stand-ins that only append argv to a log; the evil one also damages a scratch real store when asked to delete."""
    log = Path(base) / "fake-defaults.log"
    good = Path(base) / "fake-defaults.sh"
    good.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{log}'\n")
    evil = Path(base) / "evil-defaults.sh"
    victim = guard.REAL_STORE_FILES[1]
    evil.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{log}'\nprintf 'damaged-by-cleanup' >> '{victim}'\n")
    for path in (good, evil):
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return good, evil, log


def env_problem(env):
    if env.get("HOME") != SAFE["home"]:
        return "HOME is not the scratch home"
    if env.get("TMPDIR") != SAFE["tmp"]:
        return "TMPDIR is not the scratch tmp"
    if env.get("E2E_DEFAULTS") not in (SAFE["defaults"], SAFE["evil"]):
        return "E2E_DEFAULTS is not a fake recorder"
    return None


def run(script, args, extra_env=None, defaults=None, timeout=120):
    """The only way this file executes a copy of e2e-session.sh: scratch HOME and TMPDIR, fake defaults, recorded."""
    env = dict(os.environ, **(extra_env or {}))
    env.update(HOME=SAFE["home"], TMPDIR=SAFE["tmp"], E2E_DEFAULTS=defaults or SAFE["defaults"], E2E_STOP_TIMEOUT=env.get("E2E_STOP_TIMEOUT", "2"),
               E2E_LAUNCH_WAIT="0.4")
    env.pop("E2E_STATE_DIR", None)
    problem = env_problem(env)
    assert problem is None, problem
    RUNS.append(dict(env))
    Path(SAFE["log"]).write_text("")
    result = subprocess.run(["sh", str(script), *args], capture_output=True, text=True, env=env, timeout=timeout)
    result.defaults_log = Path(SAFE["log"]).read_text().splitlines()
    result.all_output = result.stdout + result.stderr
    return result


def state_dir():
    return Path(SAFE["tmp"]) / "opensnap-e2e-sessions"


def sessions():
    return sorted(state_dir().glob("*.session"))


def read_session(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)


def session_dirs():
    return sorted(Path(SAFE["tmp"]).glob("e2e-session.*"))


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError):
        return False


def reap():
    """Test hygiene only: kill any fake app still running and wipe scratch tmp (never touches anything outside the scratch dir)."""
    for path in sessions():
        pid = read_session(path).get("pid", "")
        if pid.isdigit() and alive(pid):
            os.kill(int(pid), signal.SIGKILL)
    shutil.rmtree(SAFE["tmp"], ignore_errors=True)
    Path(SAFE["tmp"]).mkdir(parents=True)
    for plist in guard.PREFERENCES.glob("com.shoemoney.opensnap.e2e-*.plist"):
        plist.unlink()
    for plist in guard.REAL_STORE_FILES:
        plist.write_bytes(b"<plist>values</plist>")


def launch_info(session_dir):
    path = Path(session_dir) / "tmp" / "launch.txt"
    return dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line) if path.exists() else {}


def start(app, *extra, script=SCRIPT, extra_env=None, defaults=None):
    return run(script, ["start", "--app", str(app), *extra], extra_env, defaults)


def stop(*args, script=SCRIPT, extra_env=None, defaults=None):
    return run(script, ["stop", *args], extra_env, defaults)


def script_copy(base, name, text):
    folder = Path(base) / name / "tools"
    folder.mkdir(parents=True)
    shutil.copy(root / "tools" / "real_store_guard.py", folder / "real_store_guard.py")
    copy = folder / "e2e-session.sh"
    copy.write_text(text)
    return copy


def strip_protection(text, *names):
    out = text
    for name in names:
        if name == "rm":
            changed = re.sub(r'^\s*if \[ "\$stem\.plist".*# protection:rm$', '    rm -f "$plist"', out, flags=re.M)
        elif name == "order":
            line = re.search(r"^.*# protection:order$\n", out, re.M).group(0)
            changed = out.replace(line, "", 1)
            anchor = '    compare_stores "$snapshot" || status=1\n'
            assert anchor in changed
            changed = changed.replace(anchor, anchor + line, 1)
        else:
            changed = re.sub(rf"^.*# protection:{name}$\n", "", out, flags=re.M)
        assert changed != out, f"protection:{name} not found"
        out = changed
    return out


def force_id(text, expression):
    changed = re.sub(r'^(\s*)THROWAWAY_ID="\$REAL_ID\.e2e-\$\$"$', rf'\1THROWAWAY_ID="{expression}"', text, count=1, flags=re.M)
    assert changed != text, "mutation did not apply"
    return changed


E2E_DELETE = re.compile(r"delete com\.shoemoney\.opensnap\.e2e-\d+")


def only_e2e_deletes(lines):
    return bool(lines) and all(E2E_DELETE.fullmatch(line) for line in lines)


OLD_ID = [path.stem for path in guard.REAL_STORE_FILES if path.stem != REAL_ID][0]
BAD_IDS = (REAL_ID, OLD_ID, "com.shoemoney.opensnap.e2eX", "com.shoemoney.opensnap.e2e-", "com.shoemoney.opensnap.e2e-12x")
FORCED = {REAL_ID: "$REAL_ID", OLD_ID: OLD_ID, "com.shoemoney.opensnap.e2eX": "$REAL_ID.e2eX"}


def forge_session(base, session_id, pid="", dir_path=None, marker=None, name=None):
    """A session file as if `start` had written it, but naming whatever the test wants: what does `stop` do with it?"""
    marked = Path(dir_path) if dir_path else Path(SAFE["tmp"]) / "e2e-session.FORGED"
    marked.mkdir(parents=True, exist_ok=True)
    if marker is not False:
        (marked / ".e2e-session").write_text(marker if marker is not None else session_id)
    state_dir().mkdir(parents=True, exist_ok=True)
    (state_dir() / (name or "forged.session")).write_text(f"id={session_id}\npid={pid}\ndir={marked}\nseed=empty\naws=no\n")
    snap = state_dir() / f"{session_id}.guard.json"
    if "/" not in session_id:
        subprocess.run([sys.executable, "-I", str(root / "tools/real_store_guard.py"), "--home", SAFE["home"], "snapshot", str(snap)], check=True, capture_output=True)
    return marked


def drop_harness(text, bad_id, base):
    """Source just valid_id and drop_defaults out of a script copy, point them at a bad id, call the drop: what did it do?"""
    functions = "\n".join(re.search(rf"^{fn}\(\) \{{\n.*?^\}}$", text, re.M | re.S).group(0) for fn in ("valid_id", "drop_defaults"))
    victim = guard.PREFERENCES / f"{bad_id}.plist"
    held = victim.read_bytes() if victim.exists() else None
    victim.write_bytes(b"<plist>real</plist>")
    harness = Path(base) / "drop-harness.sh"
    harness.write_text(f'REAL_ID={REAL_ID}\nDEFAULTS="$E2E_DEFAULTS"\n{functions}\ndrop_defaults "{bad_id}"\n')
    env = dict(os.environ, HOME=SAFE["home"], TMPDIR=SAFE["tmp"], E2E_DEFAULTS=SAFE["defaults"])
    assert env_problem(env) is None
    Path(SAFE["log"]).write_text("")
    subprocess.run(["sh", str(harness)], capture_output=True, text=True, env=env, timeout=30)
    survived = victim.exists()
    log = Path(SAFE["log"]).read_text().splitlines()
    if held is None:
        victim.unlink(missing_ok=True)
    else:
        victim.write_bytes(held)
    return log, survived


def protection_results(base, text, tag, app):
    """(start refuses, stop refuses, drop refuses, plist survives) for a script copy; every False means a protection did not hold."""
    start_refused = True
    for index, expression in enumerate(FORCED.values()):
        reap()
        copy = script_copy(base, f"{tag}-forced{index}", force_id(text, expression))
        result = start(app, script=copy)
        launched = bool(session_dirs()) or bool(sessions())
        start_refused = start_refused and result.returncode != 0 and not launched and not [l for l in result.defaults_log if not E2E_DELETE.fullmatch(l)]
    reap()
    stop_refused = True
    copy = script_copy(base, f"{tag}-stop", text)
    for bad in BAD_IDS:
        reap()
        victim = guard.PREFERENCES / f"{bad}.plist"
        victim.write_bytes(b"<plist>real</plist>")
        forge_session(base, bad)
        result = stop(script=copy)
        stop_refused = stop_refused and not result.defaults_log and victim.exists()
        if bad not in {p.stem for p in guard.REAL_STORE_FILES}:
            victim.unlink(missing_ok=True)
    reap()
    drop_refused, plist_survives = True, True
    for bad in BAD_IDS:
        log, survived = drop_harness(text, bad, base)
        drop_refused = drop_refused and not log
        plist_survives = plist_survives and survived
    reap()
    return start_refused, stop_refused, drop_refused, plist_survives


def test_static():
    text = SCRIPT.read_text()
    code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    check(not re.search(r"\bdefaults (delete|write|read)", code), "static: never calls a bare `defaults`; only the injectable $DEFAULTS")
    check("osascript" not in code and "tell application" not in code, "static: no AppleScript anywhere")
    check("sandbox-exec" not in code, "static: no sandbox fence (it would block the normal UI)")
    check("build/OpenSnap.app/Contents/MacOS" not in text, "static: never names the built binary path")
    check(not re.search(r"^\s*(export\s+)?OPENSNAP_FIXTURE=", code, re.M), "static: never sets OPENSNAP_FIXTURE")
    launches = [line for line in code.splitlines() if '/Contents/MacOS/$EXE"' in line and "PlistBuddy" not in line]
    check(len(launches) == 1 and '"$APP/Contents/MacOS/$EXE"' in launches[0] and re.search(r'^\s*APP="\$TMP/', code, re.M) is not None,
          "static: the only launch line runs the temp copy ($TMP/...)")
    check(re.search(r"nohup env -i PATH=\S+ HOME=\"\$TMP/home\" CFFIXED_USER_HOME=\"\$TMP/home\" TMPDIR=\"\$TMP/tmp\"", code) is not None
          and 'OPENSNAP_APP_SUPPORT="$TMP/support"' in code, "static: launched under env -i with throwaway HOME, CFFIXED_USER_HOME, TMPDIR and OPENSNAP_APP_SUPPORT")
    for kind in ("top", "drop", "rm", "dir", "pid", "order"):
        check(f"# protection:{kind}" in text, f"static: protection:{kind} is tagged (so its mutant can be built)")
    check(text.index("# protection:top") < text.index("trap cleanup EXIT"), "static: the id is validated before the failure trap is installed")
    stop_body = text[text.index("cmd_stop() {"):]
    check(stop_body.index("session_cleanup") < stop_body.index("compare_stores"), "static: stop cleans up before it compares the real stores")


def test_start_stop(base, app):
    reap()
    secret_env = {"E2E_LEAK_SENTINEL": "leaked"}
    result = start(app, "--seed", "all", extra_env=secret_env)
    check(result.returncode == 0, f"start: --seed all exits 0 (got {result.returncode}: {result.stderr.strip()[-200:]})")
    files = sessions()
    check(len(files) == 1, "start: one session file is written")
    session = read_session(files[0])
    session_id, pid, folder = session["id"], session["pid"], session["dir"]
    check(re.fullmatch(r"com\.shoemoney\.opensnap\.e2e-\d+", session_id) is not None and session_id not in {REAL_ID, OLD_ID},
          f"start: the throwaway id {session_id} differs from both real ids")
    check(f"pid              {pid}" in result.stdout and f"pid={pid}" in files[0].read_text(), "start: prints the pid and records it in the session file")
    check(alive(pid), "start: the app copy is running")
    info = launch_info(folder)
    check(info.get("exe", "").startswith(folder + "/") and info.get("exe") != str(app / "Contents/MacOS/Fake") and "/e2e-session." in info.get("exe", ""),
          "start: the executed binary is the temp copy, not the source bundle")
    check(info.get("bundle") == session_id, "start: the copy was re-identified to the throwaway bundle id")
    check(info.get("fixture") == "unset" and info.get("aws") == "unset" and info.get("leak") == "unset",
          "start: env -i keeps OPENSNAP_FIXTURE, AWS_SHARED_CREDENTIALS_FILE and the caller's own variables out of the child")
    check(all(info.get(key, "").startswith(folder + "/") or info.get(key) == folder + "/support" for key in ("support", "home", "cfhome", "tmpdir")),
          "start: support, HOME, CFFIXED_USER_HOME and TMPDIR are throwaway folders under the session dir")
    support = Path(folder) / "support"
    index = json.loads((support / "History" / "index.json").read_text())
    entries = index["entries"]
    check(len(entries) == 6 and all((support / "History" / e["nativeFile"]).is_file() and (support / "History" / e["previewFile"]).is_file() for e in entries),
          "seed: six History entries each with an .opensnap document and a preview")
    check(all(hashlib.sha256((support / "History" / e["nativeFile"]).read_bytes()).hexdigest() == e["digest"] and e["nativeFile"].endswith(".opensnap") for e in entries),
          "seed: every entry's digest matches its .opensnap bytes")
    doc = json.loads((support / "History" / entries[0]["nativeFile"]).read_text())
    check(doc["format"] == "com.shoemoney.opensnap.document" and doc["version"] == 1 and len(doc["elements"]) == 4, "seed: the .opensnap documents carry the document format")
    destinations = json.loads((support / "Publishing" / "destinations.json").read_text())
    hosts = re.findall(r"https?://[^/\"]+|sftp://[^/\"]+|ftps://[^/\"]+", json.dumps(destinations) + json.dumps(entries))
    check(len(destinations["destinations"]) == 4 and hosts and all(h.split("://")[1].endswith(".example.test") for h in hosts),
          f"seed: four destinations, every host synthetic (*.example.test): {sorted(set(hosts))}")
    check("password" not in json.dumps(destinations).lower() and "cdn.shoemoney.com" not in json.dumps(destinations), "seed: no secret and no real destination without --aws")
    status = run(SCRIPT, ["status"])
    check(status.returncode == 0 and session_id in status.stdout and "(running)" in status.stdout and "RESULT stores unchanged" in status.stdout,
          "status: lists the running session and says the real stores are unchanged")

    # cfprefsd writes the throwaway domain to the REAL preferences folder; stop must remove exactly that plist.
    plist = guard.PREFERENCES / f"{session_id}.plist"
    plist.write_bytes(b"<plist>throwaway</plist>")
    result = stop()
    check(result.returncode == 0 and "RESULT stores unchanged, session removed" in result.stdout, f"stop: a clean session stops with exit 0 and unchanged stores (got {result.returncode}: {result.all_output[-200:]})")
    check(not alive(pid) and not Path(folder).exists() and not sessions(), "stop: the app is gone, the temp dir is removed and the session file is deleted")
    check(only_e2e_deletes(result.defaults_log) and result.defaults_log == [f"delete {session_id}"], f"stop: defaults dropped only for the valid id (log {result.defaults_log})")
    check(not plist.exists(), "stop: the throwaway defaults plist in the preferences folder is removed")
    check(all(p.read_bytes() == b"<plist>values</plist>" for p in guard.REAL_STORE_FILES), "stop: the real defaults plists were never touched")
    out = result.stdout
    check(out.index("cleanup          app stopped") < out.index("real stores      after:"), "stop: cleanup is reported before the final store compare")

    # --seed variants and bad arguments
    reap()
    result = start(app, "--seed", "history")
    folder = read_session(sessions()[0])["dir"]
    check(result.returncode == 0 and (Path(folder) / "support/History/index.json").exists() and not (Path(folder) / "support/Publishing").exists(), "seed: --seed history writes History only")
    stop()
    reap()
    result = start(app, "--seed", "bogus")
    check(result.returncode == 2 and not session_dirs() and not sessions() and not result.defaults_log, "start: a bad --seed is refused (exit 2) before any temp dir or launch")
    result = start(Path(base) / "NoSuch.app")
    check(result.returncode != 0 and not session_dirs() and not sessions(), "start: a missing app bundle is refused before any temp dir or launch")
    result = run(SCRIPT, ["stop"])
    check(result.returncode == 2 and "no matching" in result.stderr, "stop: with no session it refuses (exit 2)")


def test_tamper_and_order(base, app):
    reap()
    start(app)
    guard.REAL_STORE_FILES[1].write_bytes(b"<plist>changed behind our back</plist>")
    result = stop()
    check(result.returncode != 0 and "RESULT STORES CHANGED" in result.stdout and "RESULT FAILED" in result.stdout,
          "tamper: a changed real defaults plist makes stop exit non-zero and say so")
    reap()
    start(app)
    (guard.OLD_FOLDER / "History" / "new.dat").write_bytes(b"x")
    result = stop()
    check(result.returncode != 0 and "appeared" in result.stdout, "tamper: a new file in a real store folder makes stop exit non-zero")
    (guard.OLD_FOLDER / "History" / "new.dat").unlink()
    reap()

    # Cleanup-before-compare: an evil `defaults` damages a real store while cleanup runs; only a compare AFTER cleanup can see it.
    start(app, defaults=SAFE["evil"])
    result = stop(defaults=SAFE["evil"])
    check(result.returncode != 0 and "RESULT STORES CHANGED" in result.stdout, "order: damage done DURING cleanup is caught, because the compare runs after cleanup")
    reap()
    mutant = script_copy(base, "mut-order", strip_protection(SCRIPT.read_text(), "order"))
    start(app, script=mutant, defaults=SAFE["evil"])
    result = stop(script=mutant, defaults=SAFE["evil"])
    check(result.returncode == 0 and "STORES CHANGED" not in result.stdout,
          "order (can fail): with the compare moved before cleanup the same damage goes unnoticed, so the check above is the ordering's doing")
    reap()


def test_kill_fallback(base):
    reap()
    stubborn = fake_app(base, "Stubborn.app")
    (stubborn / "Contents/Resources/ignore-term").write_text("")
    start(stubborn)
    pid = read_session(sessions()[0])["pid"]
    result = stop(extra_env={"E2E_STOP_TIMEOUT": "1"})
    check(result.returncode == 0 and "SIGKILL" in result.stdout and not alive(pid), "stop: an app that ignores SIGTERM is SIGKILLed after the timeout")
    reap()
    mutant = script_copy(base, "mut-kill", re.sub(r'^\s*kill -KILL.*\n', "", SCRIPT.read_text(), flags=re.M))
    start(stubborn, script=mutant)
    pid = read_session(sessions()[0])["pid"]
    stop(script=mutant, extra_env={"E2E_STOP_TIMEOUT": "1"})
    survived = alive(pid)
    if survived:
        os.kill(int(pid), signal.SIGKILL)
    check(survived, "stop (can fail): without the SIGKILL line the stubborn app survives, so the kill check above is the fallback's doing")
    reap()


def test_protections(base, app):
    text = SCRIPT.read_text()
    start_refused, stop_refused, drop_refused, plist_survives = protection_results(base, text, "real", app)
    check(start_refused, "real ids: start forced onto the current id, the retired id or ...e2eX is refused before any temp dir, session or launch")
    check(stop_refused, "real ids: stop on a session file naming a real/odd id records no defaults call and leaves that id's plist in place")
    check(drop_refused and plist_survives, "real ids: drop_defaults called directly with a real/odd id records no defaults call and leaves the plist in place")
    mutants = {"top check removed": ("top",), "drop check removed": ("drop",), "top + drop removed": ("top", "drop"), "top + drop + rm removed": ("top", "drop", "rm")}
    expected = {"top check removed": (False, True, True, True), "drop check removed": (True, True, False, True),
                "top + drop removed": (False, False, False, True), "top + drop + rm removed": (False, False, False, False)}
    for index, (label, names) in enumerate(mutants.items()):
        got = protection_results(base, strip_protection(text, *names), f"mut{index}", app)
        check(got == expected[label], f"real ids (can fail): with the {label}, exactly the dependent checks go red (start/stop/drop/plist = {got})")

    # The temp dir is removed only when it is a marked session dir.
    def dir_survives(script):
        reap()
        precious = Path(SAFE["tmp"]) / "precious"
        precious.mkdir()
        (precious / "file.txt").write_text("keep")
        mismatched = Path(SAFE["tmp"]) / "e2e-session.AAAAAA"
        mismatched.mkdir()
        (mismatched / "file.txt").write_text("keep")
        ok_id = f"{REAL_ID}.e2e-41001"
        results = []
        for target, marker, ident in ((precious, False, ok_id), (mismatched, f"{REAL_ID}.e2e-99", ok_id)):
            forge_session(base, ident, dir_path=target, marker=marker)
            stop(script=script)
            results.append(target.exists() and (target / "file.txt").exists())
            for leftover in state_dir().glob("*"):
                leftover.unlink()
        return all(results)
    check(dir_survives(SCRIPT), "dir: a session file pointing at an unmarked folder, or one marked for a different id, never gets that folder removed")
    check(not dir_survives(script_copy(base, "mut-dir", strip_protection(text, "dir"))), "dir (can fail): with the dir check removed the same forged session deletes the folder")

    # A pid is signalled only when it is this session's own app copy.
    def decoy_survives(script):
        reap()
        decoy = subprocess.Popen(["sleep", "300"])
        try:
            forge_session(base, f"{REAL_ID}.e2e-41002", pid=str(decoy.pid))
            stop(script=script)
            time.sleep(0.3)
            return decoy.poll() is None
        finally:
            decoy.kill(); decoy.wait()
    check(decoy_survives(SCRIPT), "pid: a pid that is not the session's app copy is never signalled")
    check(not decoy_survives(script_copy(base, "mut-pid", strip_protection(text, "pid"))), "pid (can fail): with the pid check removed the decoy process is killed")
    reap()


def test_aws(base, app):
    reap()
    creds = Path(SAFE["home"]) / ".aws" / "credentials"
    result = start(app, "--aws", "--seed", "all")
    folder = read_session(sessions()[0])["dir"]
    info = launch_info(folder)
    check(result.returncode == 0 and info.get("aws") == str(creds), f"aws: --aws hands the app the credentials file path in place and nothing else (got {info.get('aws')})")
    destinations = json.loads((Path(folder) / "support/Publishing/destinations.json").read_text())
    first = destinations["destinations"][0]
    s3 = first["settings"]["s3"]
    check(destinations["defaultID"] == first["id"] and s3 == {"region": "us-east-1", "bucket": "cdn.shoemoney.com", "credentialsProfile": "default", "publicReadACL": False}
          and first["settings"]["remoteFolder"] == "pics" and first["settings"]["publicBaseURL"] == "https://cdn.shoemoney.com/pics" and first["settings"]["transport"] == "s3",
          "aws: the seeded default destination is the cdn.shoemoney.com S3 profile destination, no stored secret")
    result_stop = stop()
    corpus = result.all_output + result_stop.all_output
    for path in list(Path(SAFE["tmp"]).rglob("*")) + [Path(folder) / "launch.txt"]:
        if path.is_file():
            corpus += path.read_text(errors="replace")
    # the session dir is gone after stop, so scan it from the start-time snapshot taken below too
    check(SENTINEL not in corpus and result.returncode == 0 and result_stop.returncode == 0, "aws: the credential sentinel appears in no start/stop output and no leftover file")
    reap()
    start(app, "--aws", "--seed", "all")
    folder = read_session(sessions()[0])["dir"]
    leaks = [str(path) for path in list(Path(folder).rglob("*")) + list(state_dir().glob("*")) if path.is_file() and SENTINEL in path.read_text(errors="replace")]
    check(not leaks, f"aws: the sentinel is in no file of the live session dir or session registry (leaks: {leaks})")
    stop()
    reap()
    # Positive control: a copy that cats the file leaks the sentinel into the output, so the scan above can fail.
    leaky = SCRIPT.read_text().replace('    mkdir -p "$SESSIONS"\n', '    cat "$AWS_FILE"\n    mkdir -p "$SESSIONS"\n', 1)
    check(leaky != SCRIPT.read_text(), "aws (can fail): the leak mutation applied")
    copy = script_copy(base, "mut-aws", leaky)
    result = start(app, "--aws", script=copy)
    check(SENTINEL in result.all_output, "aws (can fail): a copy that prints the credentials file puts the sentinel in the output, so the redaction check can detect a leak")
    stop(script=copy)
    reap()
    creds.rename(creds.with_name("credentials.off"))
    try:
        result = start(app, "--aws")
        check(result.returncode == 2 and not session_dirs() and not sessions(), "aws: --aws without a credentials file is refused before any temp dir or launch")
    finally:
        creds.with_name("credentials.off").rename(creds)


def inventory_tree(base, name):
    """A scratch copy of everything the inventory generator reads, so mutants never touch the real files."""
    tree = Path(base) / name
    (tree / "tools").mkdir(parents=True)
    shutil.copy(root / "tools/e2e-inventory.py", tree / "tools/e2e-inventory.py")
    shutil.copytree(root / "Sources", tree / "Sources", ignore=shutil.ignore_patterns("*.ttf"))
    (tree / "tests").mkdir()
    for path in (root / "tests").glob("*.swift"):
        shutil.copy(path, tree / "tests" / path.name)
    shutil.copytree(root / "docs/design/e2e", tree / "docs/design/e2e")
    return tree


def inventory_check(tree):
    return subprocess.run([sys.executable, "-I", str(tree / "tools/e2e-inventory.py"), "--check"], capture_output=True, text=True, cwd=tree)


def test_inventory(base):
    folder = root / "docs/design/e2e"
    result = subprocess.run([sys.executable, "-I", str(root / "tools/e2e-inventory.py"), "--check"], capture_output=True, text=True, cwd=root)
    check(result.returncode == 0, f"inventory: inventory.json and the coverage matrix match the sources ({(result.stdout + result.stderr).strip()[-160:]})")
    data = json.loads((folder / "inventory.json").read_text())
    entries = data["entries"]
    ids = [e["id"] for e in entries]
    check(len(ids) == len(set(ids)) and all(re.fullmatch(r"E2E-[A-Z0-9]+-\d{3}", i) for i in ids), "inventory: every audit ID is unique and shaped E2E-<AREA>-<nnn>")
    required = ("id", "area", "surface", "name", "type", "icon", "entryPath", "prerequisite", "expected", "owner", "exercise", "gap")
    check(all(all(k in e for k in required) and e["name"] and e["entryPath"] and e["expected"] for e in entries), "inventory: every entry has the required fields filled")
    check(all((e["exercise"] == "e2e") == (e["gap"] is None) and (e["gap"] is None or e["gap"] in data["gaps"]) for e in entries),
          "inventory: an entry has a named gap reason exactly when it is not fully real-click exercisable")
    icons_src = (root / "Sources/FontAwesomeIcons.swift").read_text()
    cases = re.findall(r"case \.(\w+): return 0x[0-9A-Fa-f]+", icons_src)
    fa_entries = [e for e in entries if e["area"] == "ICON" and e["surface"] == "FAIcon"]
    check(len(cases) >= 35 and len(fa_entries) == len(cases), f"inventory: every FAIcon case is an icon entry ({len(fa_entries)} of {len(cases)})")
    symbols = set(re.findall(r'\("[A-Za-z0-9]+", "([^"]+)"\)', (root / "Sources/MenuSymbols.swift").read_text()))
    listed = {e["name"] for e in entries if e["surface"] == "Menu leading symbol"}
    check(symbols and symbols <= listed, f"inventory: every menu leading SF symbol is an icon entry ({len(symbols & listed)} of {len(symbols)})")
    matrix = (folder / "coverage-matrix.md").read_text()
    rows = re.findall(r"^\| (E2E-[A-Z0-9]+-\d{3}) \|", matrix, re.M)
    check(rows == ids, "inventory: the coverage matrix has exactly one row per audit ID, in order")
    tests = {p.name: p.read_text() for p in (root / "tests").glob("*.swift")}
    proven = [e for e in entries if e["proof"]]
    check(proven and all(p["test"] in tests.get(p["file"], "") for e in proven for p in e["proof"]), f"inventory: every pre-filled unit/source proof names a test that exists ({len(proven)} entries)")
    check(all(("unit/source" in line) == ("| test " in line) for line in matrix.splitlines() if line.startswith("| E2E-")), "inventory: only rows that name a test are marked unit/source")

    # Can-fail: scratch copies with one thing broken must make --check red, and an untouched copy must pass.
    tree = inventory_check(inventory_tree(base, "inv-clean"))
    check(tree.returncode == 0, "inventory (can fail): an untouched scratch copy passes")
    mutants = {}
    t = inventory_tree(base, "inv-drop-entry")
    doc = json.loads((t / "docs/design/e2e/inventory.json").read_text()); doc["entries"].pop(10)
    (t / "docs/design/e2e/inventory.json").write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n")
    mutants["an entry deleted from inventory.json"] = t
    t = inventory_tree(base, "inv-new-icon")
    src = t / "Sources/FontAwesomeIcons.swift"
    text = src.read_text()
    text = text.replace("circleCheck = \"circle-check\", gear", "circleCheck = \"circle-check\", gear, newcomer", 1)
    text = text.replace("        case .gear: return 0xF013\n", "        case .gear: return 0xF013\n        case .newcomer: return 0xF999\n", 1)
    text = text.replace('        case .gear: return "gearshape.fill"\n', '        case .gear: return "gearshape.fill"\n        case .newcomer: return "star"\n', 1)
    check(text != src.read_text(), "inventory (can fail): the new-icon mutation applied")
    src.write_text(text)
    mutants["a new FAIcon case the inventory does not list"] = t
    t = inventory_tree(base, "inv-new-menu")
    app = t / "Sources/App.swift"
    text = app.read_text().replace('("Wipe Snap Only", #selector(wipeSnap), "")', '("Wipe Snap Only", #selector(wipeSnap), ""), ("Brand New Command", #selector(brandNew), "")', 1)
    check(text != app.read_text(), "inventory (can fail): the new-menu mutation applied")
    app.write_text(text)
    mutants["a new menu item nobody classified"] = t
    t = inventory_tree(base, "inv-matrix-row")
    lines = (t / "docs/design/e2e/coverage-matrix.md").read_text().splitlines()
    index = next(i for i, line in enumerate(lines) if line.startswith("| E2E-MENU-003"))
    (t / "docs/design/e2e/coverage-matrix.md").write_text("\n".join(lines[:index] + lines[index + 1:]) + "\n")
    mutants["a matrix row deleted"] = t
    t = inventory_tree(base, "inv-proof")
    test_file = t / "tests/SettingsWindowTests.swift"
    text = test_file.read_text().replace("Command-W is handled by the window", "Command-W is handled")
    check(text != test_file.read_text(), "inventory (can fail): the proof mutation applied")
    test_file.write_text(text)
    mutants["a pre-filled proof whose test no longer exists"] = t
    for label, tree in mutants.items():
        check(inventory_check(tree).returncode != 0, f"inventory (can fail): {label} makes --check fail")


def test_runs_were_safe():
    check(len(RUNS) > 0 and all(env_problem(env) is None for env in RUNS),
          f"every one of the {len(RUNS)} script runs used the scratch HOME and TMPDIR and a fake defaults recorder")
    check(env_problem({"HOME": os.environ.get("HOME", ""), "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": SAFE["defaults"]}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"]}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": "/usr/bin/defaults"}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": os.environ.get("TMPDIR", "/tmp"), "E2E_DEFAULTS": SAFE["defaults"]}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": SAFE["defaults"]}) is None,
          "the env checker rejects a real HOME, a real TMPDIR, a missing recorder and the real /usr/bin/defaults")


with tempfile.TemporaryDirectory(prefix="e2e-guard-test.") as scratch:
    scratch = str(Path(scratch).resolve())
    scratch_home = make_home(scratch)
    good, evil, log = make_recorders(scratch)
    (Path(scratch) / "tmp").mkdir()
    SAFE.update(home=str(scratch_home), tmp=str(Path(scratch) / "tmp"), defaults=str(good), evil=str(evil), log=str(log))
    app = fake_app(scratch)
    try:
        test_static()
        test_start_stop(scratch, app)
        test_tamper_and_order(scratch, app)
        test_kill_fallback(scratch)
        test_protections(scratch, app)
        test_aws(scratch, app)
        test_inventory(scratch)
        test_runs_were_safe()
    finally:
        reap()
if failures:
    raise SystemExit(f"FAIL test-e2e-session-guard: {len(failures)} check(s) failed")
print("PASS test-e2e-session-guard")
