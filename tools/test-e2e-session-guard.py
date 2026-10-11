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
 (i) the panel-service watchdog: only the exact openAndSavePanelService executable is ever a kill target, only above the RSS threshold
     (override honoured) and only when its `ps eww` environment names THIS session's temp dir (a big service of another app or session,
     a prefix-lookalike dir, a service with no readable environment are all left alone); kills are timestamped in the log, start/stop
     write and remove the pid file and stop keeps its cleanup order; tools/panel-service-check.sh scopes its peak and kills the same way.
     `ps`, `ps eww` and `kill` are replaced by fakes (E2E_WATCHDOG_PS / E2E_WATCHDOG_ENV / E2E_WATCHDOG_KILL) so no test reads or signals a real process.
 (h) the E2E inventory (tools/e2e-inventory.py): docs/design/e2e/inventory.json and the coverage matrix match the sources, every FAIcon case and
     menu symbol is listed, every pre-filled proof names a real test, and scratch copies with a drift or a bad proof make --check fail.
     Rows converted to glass keep their native evidence as `history` in inventory.json: it must equal the matrix at its pinned commit byte for
     byte, the row's current class is `unverified` with gap reason `UI changed`, and a restored class, an edited history or a stray reason fails.
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
    if env.get("TMPDIR") not in (SAFE["tmp"], SAFE["tmp"] + "/"):
        return "TMPDIR is not the scratch tmp"
    if env.get("E2E_DEFAULTS") not in (SAFE["defaults"], SAFE["evil"]):
        return "E2E_DEFAULTS is not a fake recorder"
    if env.get("E2E_WATCHDOG_PS") != SAFE["fake_ps"] or env.get("E2E_WATCHDOG_KILL") != SAFE["fake_kill"] or env.get("E2E_WATCHDOG_ENV") != SAFE["fake_env"]:
        return "the watchdog ps/env/kill are not the fakes"
    return None


def run(script, args, extra_env=None, defaults=None, timeout=120):
    """The only way this file executes a copy of e2e-session.sh: scratch HOME and TMPDIR, fake defaults, recorded."""
    env = dict(os.environ, **(extra_env or {}))
    env.update(HOME=SAFE["home"], TMPDIR=SAFE["tmp"] + "/", E2E_DEFAULTS=defaults or SAFE["defaults"], E2E_STOP_TIMEOUT=env.get("E2E_STOP_TIMEOUT", "2"),
               E2E_LAUNCH_WAIT="0.4", E2E_WATCHDOG_PS=SAFE["fake_ps"], E2E_WATCHDOG_ENV=SAFE["fake_env"], E2E_WATCHDOG_KILL=SAFE["fake_kill"], E2E_WATCHDOG_INTERVAL="0.1")
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
    for path in state_dir().glob("*.watchdog.pid"):
        pid = path.read_text().strip()
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
    env = dict(os.environ, HOME=SAFE["home"], TMPDIR=SAFE["tmp"], E2E_DEFAULTS=SAFE["defaults"], E2E_WATCHDOG_PS=SAFE["fake_ps"], E2E_WATCHDOG_ENV=SAFE["fake_env"], E2E_WATCHDOG_KILL=SAFE["fake_kill"])
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
    for kind in ("top", "drop", "rm", "dir", "pid", "order", "watchdog"):
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


def normalized(path):
    return bool(path) and path == os.path.normpath(path) and "//" not in path


def test_normalized_home(base, app):
    """F-J5-005: macOS 27's Open/Save panel service inherits CFFIXED_USER_HOME and spins to tens of GB when it is not normalized. Real macOS
    TMPDIR ends in "/", so a raw mktemp path has "//"; run() therefore passes a trailing-slash TMPDIR and the launcher must canonicalize."""
    def launched(script):
        reap()
        result = start(app, script=script)
        files = sessions()
        info = launch_info(read_session(files[0])["dir"]) if files else {}
        stop(script=script)
        return result, info
    result, info = launched(SCRIPT)
    check(result.returncode == 0 and normalized(info.get("cfhome", "")) and normalized(info.get("home", "")) and normalized(info.get("support", "")),
          f"F-J5-005: with a trailing-slash TMPDIR the app is launched with normalized HOME, CFFIXED_USER_HOME and support paths (cfhome={info.get('cfhome')})")
    text = SCRIPT.read_text()
    canon = '    TMP=$(CDPATH= cd -- "$TMP" && pwd -P)\n'
    check(canon in text, "F-J5-005: the canonicalizing line is where the test expects it (so the mutant below really removes it)")
    _, mutant_info = launched(script_copy(base, "mut-normalize", text.replace(canon, "")))
    check(not normalized(mutant_info.get("cfhome", "")) and "//" in mutant_info.get("cfhome", ""),
          f"F-J5-005 (can fail): without the canonicalizing line CFFIXED_USER_HOME contains '//' ({mutant_info.get('cfhome')}), so the check above goes red")
    reap()


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


def test_free_icons(base):
    """R1-004/R1-001: a session copy never carries a Font Awesome Pro font, and start says so and warns that typing lands in the app."""
    reap()
    pro = fake_app(base, "Pro.app")
    for name in ("FontAwesome7Pro-Regular-subset.ttf", "FontAwesome7Pro-Solid-subset.ttf"):
        (pro / "Contents/Resources" / name).write_bytes(b"not a real font")
    result = start(pro)
    folder = read_session(sessions()[0])["dir"]
    copied = [p.name for p in (Path(folder)).glob("*.app/Contents/Resources/*")]
    check(result.returncode == 0 and not any("Pro" in name for name in copied), f"icons: no FontAwesome*Pro* file reaches the session copy (found {copied})")
    check((pro / "Contents/Resources/FontAwesome7Pro-Regular-subset.ttf").exists(), "icons: the source bundle is left untouched")
    check("icons: Font Awesome Free" in result.stdout and "keep personal text out of it" in result.stdout, "start: prints the Free-icons line and the typing warning")
    stop()
    reap()
    mutant = script_copy(base, "mut-pro", re.sub(r'^\s*rm -f "\$APP/Contents/Resources"/FontAwesome.*\n', "", SCRIPT.read_text(), flags=re.M))
    check(mutant.read_text() != SCRIPT.read_text(), "icons (can fail): the strip line was found to remove")
    start(pro, script=mutant)
    folder = read_session(sessions()[0])["dir"]
    leaked = [p.name for p in Path(folder).glob("*.app/Contents/Resources/*Pro*")]
    stop(script=mutant)
    check(leaked, "icons (can fail): without the strip line the Pro fonts do reach the copy, so the check above is the strip's doing")
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
    text = app.read_text().replace('("Remove Snap Picture", #selector(wipeSnap), "")', '("Remove Snap Picture", #selector(wipeSnap), ""), ("Brand New Command", #selector(brandNew), "")', 1)
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

    test_gap_reason_ledger(base, folder)


LEDGER_SPLIT = re.compile(r"(?<!\\)\|")


def ledger_mutant(base, name, pick, edit):
    """A scratch tree whose matrix has one row (chosen by `pick(cells)`) rewritten by `edit(cells)`; returns (tree, row id)."""
    tree = inventory_tree(base, name)
    path = tree / "docs/design/e2e/coverage-matrix.md"
    lines = path.read_text().splitlines()
    for index, line in enumerate(lines):
        cells = [c.strip() for c in LEDGER_SPLIT.split(line.strip().strip("|"))] if line.startswith("| E2E-") else None
        if cells and len(cells) == 14 and pick(cells):
            ident = cells[0]
            edit(cells)
            lines[index] = "| " + " | ".join(cells) + " |"
            path.write_text("\n".join(lines) + "\n")
            return tree, ident
    raise AssertionError(f"ledger mutant {name}: no row matched")


def test_gap_reason_ledger(base, folder):
    vocabulary = ("permission", "hardware", "OS-owned", "harness", "unsafe", "AX presence only", "AX value only", "text readout only", "UI changed")
    text = (folder / "coverage-matrix.md").read_text()
    check(next(l for l in text.splitlines() if l.startswith("| ID |")).endswith("| reachability note | gap reason |"), "ledger: the matrix ends with the static reachability note and the audited gap reason as separate columns")
    rows = [[c.strip() for c in LEDGER_SPLIT.split(line.strip().strip("|"))] for line in text.splitlines() if line.startswith("| E2E-")]
    check(rows and all(len(r) == 14 for r in rows), f"ledger: every matrix row has 14 columns ({len(rows)} rows)")
    unverified = [r for r in rows if r[10] == "unverified"]
    check(unverified and all(r[13] in vocabulary for r in unverified), f"ledger: every unverified row carries exactly one audited gap reason ({len(unverified)} rows)")
    check(all(not r[13] for r in rows if r[10] != "unverified"), "ledger: E2E, rendered, unit/source and retired rows carry no gap reason")
    check(all(f"gap: {r[13]}" in r[7] for r in unverified), "ledger: each audited reason is the one the auditor wrote in the observed cell")

    # Regenerating a clean scratch tree reproduces the matrix byte for byte (the reason column is preserved, not recomputed away).
    tree = inventory_tree(base, "ledger-regen")
    before = (tree / "docs/design/e2e/coverage-matrix.md").read_bytes()
    result = subprocess.run([sys.executable, "-I", str(tree / "tools/e2e-inventory.py")], capture_output=True, text=True, cwd=tree)
    check(result.returncode == 0 and (tree / "docs/design/e2e/coverage-matrix.md").read_bytes() == before, "ledger (can fail): a regenerate keeps every audited reason byte for byte")
    # A 13-column matrix from before the column existed migrates: the reason is lifted from the observed cell.
    old = inventory_tree(base, "ledger-migrate")
    path = old / "docs/design/e2e/coverage-matrix.md"
    stripped = []
    for line in path.read_text().splitlines():
        if line.startswith("| E2E-"):
            line = line.rsplit(" | ", 1)[0] + " |"
        elif line.startswith("| ID |"):
            line = line.replace(" | reachability note | gap reason |", " | gap |")
        elif line.startswith("|---"):
            line = "|" + "|".join("---" for _ in range(13)) + "|"
        stripped.append(line)
    path.write_text("\n".join(stripped) + "\n")
    result = subprocess.run([sys.executable, "-I", str(old / "tools/e2e-inventory.py")], capture_output=True, text=True, cwd=old)
    check(result.returncode == 0 and path.read_bytes() == before, f"ledger (can fail): a pre-column 13-column matrix migrates with every reason lifted from observed ({(result.stdout + result.stderr).strip()[-120:]})")

    verdicts = {}
    unv = lambda r: r[10] == "unverified"
    verdicts["an unverified row with no gap reason"] = ledger_mutant(base, "ledger-blank", unv, lambda r: r.__setitem__(13, ""))
    verdicts["an unverified row whose reason is outside the vocabulary"] = ledger_mutant(base, "ledger-vocab", unv, lambda r: r.__setitem__(13, "printer"))
    verdicts["an unverified row whose reason is `retired` (a class, not a gap reason)"] = ledger_mutant(base, "ledger-retired-reason", unv, lambda r: r.__setitem__(13, "retired"))
    verdicts["an unverified row with two reasons"] = ledger_mutant(base, "ledger-two", unv, lambda r: r.__setitem__(13, r[13] + ", harness"))
    verdicts["an E2E row that carries a gap reason"] = ledger_mutant(base, "ledger-e2e", lambda r: r[10] == "E2E", lambda r: r.__setitem__(13, "unsafe"))
    verdicts["a rendered row that carries a gap reason"] = ledger_mutant(base, "ledger-rendered", lambda r: r[10] == "rendered", lambda r: r.__setitem__(13, "harness"))
    verdicts["a unit/source row that carries a gap reason"] = ledger_mutant(base, "ledger-unit", lambda r: r[10] == "unit/source", lambda r: r.__setitem__(13, "harness"))
    verdicts["a retired row that carries a gap reason"] = ledger_mutant(base, "ledger-retired", lambda r: r[10] == "retired", lambda r: r.__setitem__(13, "retired"))
    verdicts["a reason that contradicts the observed cell (valid word, wrong finding)"] = ledger_mutant(
        base, "ledger-contradict", unv, lambda r: r.__setitem__(13, "hardware" if r[13] != "hardware" else "unsafe"))
    verdicts["a reachability note that claims a printer while the audit says otherwise (static note edited, reason untouched)"] = ledger_mutant(
        base, "ledger-static", lambda r: unv(r) and r[13] == "AX presence only", lambda r: (r.__setitem__(12, "gap: printer"), r.__setitem__(13, "hardware")))
    for label, (tree, ident) in verdicts.items():
        result = inventory_check(tree)
        check(result.returncode != 0 and ident in (result.stdout + result.stderr), f"ledger (can fail): {label} makes --check fail and names {ident}")
    retired_tree, _ = verdicts["an unverified row whose reason is `retired` (a class, not a gap reason)"]
    retired_result = inventory_check(retired_tree)
    check("use class retired" in (retired_result.stdout + retired_result.stderr), "ledger (can fail): a `retired` gap reason is refused with a message that says to use class retired")
    # Moving only the static note (the reason still agrees with observed) must NOT fail: the two columns are allowed to differ.
    tree, _ = ledger_mutant(base, "ledger-static-ok", lambda r: unv(r) and r[13] == "AX presence only", lambda r: r.__setitem__(12, "gap: printer"))
    result = inventory_check(tree)
    check("coverage-matrix.md ledger is inconsistent" not in (result.stdout + result.stderr), "ledger (can fail): editing only the static note does not trip the ledger rules (it trips the freshness check instead)")
    check(result.returncode != 0, "ledger (can fail): a hand-edited static note still fails --check because the matrix is generated")
    test_converted_history(base, folder)


HISTORY_KEYS = ("observed", "sourceSHA", "evidencePath", "evidenceClass", "reviewer", "gapReason")
HISTORY_COLUMNS = (7, 8, 9, 10, 11, 13)   # observed, source SHA, evidence (path), evidence class, reviewer, gap reason


def matrix_cells(text):
    return {cells[0]: cells for cells in ([c.strip() for c in LEDGER_SPLIT.split(line.strip().strip("|"))] for line in text.splitlines() if line.startswith("| E2E-"))}


def base_matrix_cells(commit):
    """The matrix as it was at `commit` (the native evidence the converted rows were reset from), or None when this checkout cannot read it."""
    result = subprocess.run(["git", "-C", str(root), "show", f"{commit}:docs/design/e2e/coverage-matrix.md"], capture_output=True, text=True)
    return matrix_cells(result.stdout) if result.returncode == 0 and result.stdout else None


def history_digest(history):
    return "sha256:" + hashlib.sha256(json.dumps([history.get(k, "") for k in HISTORY_KEYS], ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


INTRINSIC_REASONS = ("unsafe", "OS-owned", "permission", "hardware")   # limits of the system, not of a native control: never rewritten to `UI changed`
NOT_EVIDENCE = ("", "TBD")


def promotion_problems(h, row, tree):
    """A converted row may carry NEW current evidence from an audit of the glass control, and only that: a complete E2E or rendered observation,
    a new glass source SHA, new evidence files that exist, a reviewer and no gap reason. Returns what falls short (empty: a valid promotion)."""
    observed, sha, path, klass, reviewer, reason = row[7], row[8], row[9], row[10], row[11], row[13]
    problems = []
    if observed in NOT_EVIDENCE or len(observed) < 40 or observed.startswith("Converted to glass in") or "not current glass coverage" in observed or observed == h.get("observed"):
        problems.append("its observation is missing, the transition prose or the native text, not a new glass observation")
    if not re.fullmatch(r"[0-9a-f]{7,40}", sha) or sha.startswith(h.get("sourceSHA", "-")) or h.get("sourceSHA", "-").startswith(sha):
        problems.append(f"its source SHA {sha!r} is not a new glass build different from the native {h.get('sourceSHA')!r}")
    paths = [part.strip() for part in path.split(";")]
    native = {part.strip() for part in h.get("evidencePath", "").split(";")}
    if path in NOT_EVIDENCE or not all(paths) or any(part in native for part in paths):
        problems.append("its evidence path is TBD or reuses a native evidence file")
    elif not all((tree / part).is_file() for part in paths):
        problems.append("its evidence path names a file that does not exist")
    if reviewer in NOT_EVIDENCE:
        problems.append("its reviewer is not recorded")
    if reason:
        problems.append(f"a {klass} row carries no gap reason (found {reason!r})")
    return problems


def history_problems(tree, base_rows):
    """Independent of the generator: what is wrong with the history of every row converted to glass in `tree`.
    `base_rows` is the matrix at the pinned commit; with None only the digest and the current state can be judged.
    A converted row is either still reset (unverified, gap reason UI changed, the transition note, TBD evidence) or promoted by an audit of the glass control."""
    entries = json.loads((tree / "docs/design/e2e/inventory.json").read_text())["entries"]
    rows = matrix_cells((tree / "docs/design/e2e/coverage-matrix.md").read_text())
    converted = {e["id"]: e["history"] for e in entries if e.get("history")}
    problems = []
    for ident, h in sorted(converted.items()):
        row = rows.get(ident)
        if history_digest(h) != h.get("digest"):
            problems.append(f"{ident}: the history digest does not match its fields")
        if base_rows is not None:
            prior = base_rows.get(ident)
            if prior is None or tuple(prior[i] for i in HISTORY_COLUMNS) != tuple(h.get(k) for k in HISTORY_KEYS):
                problems.append(f"{ident}: the history differs from the matrix at {h.get('from')}")
        if h.get("evidenceClass") not in ("E2E", "rendered", "unverified"):
            problems.append(f"{ident}: a history holds prior E2E, rendered or unverified evidence, not {h.get('evidenceClass')!r}")
        if h.get("evidenceClass") == "unverified" and (h.get("gapReason") in INTRINSIC_REASONS or not h.get("gapReason")):
            problems.append(f"{ident}: an audited {h.get('gapReason')!r} gap is a limit of the system and still applies to the glass control, so it is never rewritten to UI changed")
        if not row:
            problems.append(f"{ident}: the matrix has no row for a converted entry")
        elif tuple(row[i] for i in HISTORY_COLUMNS) == tuple(h.get(k) for k in HISTORY_KEYS):
            problems.append(f"{ident}: its current cells are still the native evidence (not converted)")
        elif row[10] in ("E2E", "rendered"):
            problems += [f"{ident}: promoted without new glass evidence: {why}" for why in promotion_problems(h, row, tree)]
        elif row[10] != "unverified" or row[13] != "UI changed":
            problems.append(f"{ident}: a converted row is unverified with gap reason UI changed, or promoted with new evidence (found {row[10]!r} / {row[13]!r})")
        elif (not row[7].startswith("Converted to glass in") or f"Prior native evidence {h.get('evidenceClass')} at {h.get('sourceSHA')} " not in row[7]
              or "not current glass coverage" not in row[7]):
            problems.append(f"{ident}: its observed cell is not the transition note for its history")
        elif (row[8], row[9], row[11]) != ("TBD", "TBD", "TBD"):
            problems.append(f"{ident}: its source SHA, evidence path and reviewer must not carry the native evidence as current")
    for ident, row in sorted(rows.items()):
        if row[13] == "UI changed" and ident not in converted:
            problems.append(f"{ident}: gap reason UI changed on a row with no history")
    return problems


def promote_row(r, history, **fields):
    """Rewrites a matrix row's cells as an audit of the glass control would (the defaults are a valid promotion); `fields` override by cell name."""
    cells = {"observed": "Real click on the glass control: the panel opened below its button, the row was chosen and the state changed; screenshot 01 shows it.",
             "sha": "3a5f7c1", "path": "docs/design/evidence/e2e-fixture/01-glass.jpg", "class": "E2E", "reviewer": "G2 lane", "reason": ""}
    cells.update(fields)
    for column, key in ((7, "observed"), (8, "sha"), (9, "path"), (10, "class"), (11, "reviewer"), (13, "reason")):
        r[column] = cells[key]


def test_converted_history(base, folder):
    entries = json.loads((folder / "inventory.json").read_text())["entries"]
    converted = {e["id"]: e["history"] for e in entries if e.get("history")}
    commits = {h.get("from") for h in converted.values()}
    rows = matrix_cells((folder / "coverage-matrix.md").read_text())
    kinds = {k: sum(1 for h in converted.values() if h["evidenceClass"] == k) for k in ("E2E", "rendered", "unverified")}
    check(len(converted) > 0 and len(commits) == 1, f"history: {len(converted)} rows converted to glass keep their native evidence ({kinds}), all from the matrix at {', '.join(sorted(map(str, commits)))}")
    base_rows = base_matrix_cells(next(iter(commits))) if len(commits) == 1 else None
    problems = history_problems(root, base_rows)
    reset = sum(1 for i in converted if rows[i][13] == "UI changed")
    check(not problems, "history: each converted row's history equals its prior cells byte for byte"
          + ("" if base_rows is not None else " (digest only: the pinned commit is not readable in this checkout)")
          + f", and the row is either still reset to unverified with gap reason UI changed ({reset} of {len(converted)}) or promoted with new glass evidence"
          + (f" ({problems[:3]})" if problems else ""))
    check({i for i, r in rows.items() if r[13] == "UI changed"} <= set(converted), "history: gap reason UI changed sits only on rows that have a history")
    if base_rows is not None:
        intrinsic = [i for i, r in base_rows.items() if r[13] in INTRINSIC_REASONS and rows[i][13] != r[13] and rows[i][10] == "unverified" and i in converted]
        check(not intrinsic, f"history: no unsafe, OS-owned, permission or hardware gap was rewritten to UI changed ({intrinsic[:3]})")

    def restore(r):   # the pre-conversion row, exactly: native evidence counted as current again
        for column, key in zip(HISTORY_COLUMNS, HISTORY_KEYS):
            r[column] = converted[r[0]][key]
    converted_row = lambda r: r[13] == "UI changed" and r[0] in converted
    from_unverified = lambda r: r[0] in converted and converted[r[0]]["evidenceClass"] == "unverified"
    verdicts = {
        "a converted row restored to its native E2E or rendered evidence (still counting it as current)": ledger_mutant(base, "history-restored", converted_row, restore),
        "a converted row flipped back to a counted class while it still says it was converted": ledger_mutant(
            base, "history-class-flip", converted_row, lambda r: (r.__setitem__(10, "E2E"), r.__setitem__(13, ""))),
        "an already-unverified row restored to its native cells and reason": ledger_mutant(base, "history-restored-unverified", lambda r: from_unverified(r) and r[13] == "UI changed", restore),
        "`UI changed` on an unverified row that has no transition history": ledger_mutant(
            base, "history-stray-reason", lambda r: r[10] == "unverified" and r[0] not in converted, lambda r: (r.__setitem__(7, "J1 lane: gap: UI changed."), r.__setitem__(13, "UI changed"))),
    }
    for label, (tree, ident) in verdicts.items():
        result = inventory_check(tree)
        check(result.returncode != 0 and ident in (result.stdout + result.stderr), f"history (can fail): {label} makes --check fail and names {ident}")
    stray_tree, stray_ident = verdicts["`UI changed` on an unverified row that has no transition history"]
    check("no history in inventory.json" in (inventory_check(stray_tree).stdout + inventory_check(stray_tree).stderr), "history (can fail): the stray `UI changed` is refused for lacking a history")
    restored_tree, restored_ident = verdicts["a converted row restored to its native E2E or rendered evidence (still counting it as current)"]
    check(any(restored_ident in p for p in history_problems(restored_tree, base_rows)), f"history (can fail): the guard's history check refuses the restored row too ({restored_ident})")

    # An edited history: the generator's digest sees it; one whose digest was recomputed to match is seen by the pinned-commit comparison.
    tree = inventory_tree(base, "history-edited")
    path = tree / "docs/design/e2e/inventory.json"
    document = json.loads(path.read_text())
    target = next(e for e in document["entries"] if e.get("history"))
    target["history"]["observed"] += " (edited)"
    path.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n")
    result = inventory_check(tree)
    check(result.returncode != 0 and target["id"] in (result.stdout + result.stderr), f"history (can fail): an edited history makes --check fail and names {target['id']}")
    check(any(target["id"] in p for p in history_problems(tree, base_rows)), "history (can fail): the guard's own digest check sees the edited history too")
    if base_rows is not None:
        target["history"]["digest"] = history_digest(target["history"])
        path.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n")
        check(any(target["id"] in p and "differs from the matrix" in p for p in history_problems(tree, base_rows)),
              "history (can fail): a history edited with its digest recomputed still differs from the matrix at the pinned commit")

    # An already-unverified row converts only when its limitation belonged to the native control; an unsafe, OS-owned, permission or hardware gap never does.
    if base_rows is not None:
        victim = next(i for i, r in base_rows.items() if r[13] == "unsafe" and r[10] == "unverified" and i not in converted and (rows[i][13] == "unsafe"))
        tree = inventory_tree(base, "history-intrinsic")
        doc_path = tree / "docs/design/e2e/inventory.json"
        document = json.loads(doc_path.read_text())
        forged = {"converted": "impl/glass-pickers-20261010", "from": next(iter(commits)), "evidenceClass": "unverified", "sourceSHA": base_rows[victim][8],
                  "evidencePath": base_rows[victim][9], "reviewer": base_rows[victim][11], "gapReason": base_rows[victim][13], "observed": base_rows[victim][7]}
        forged["digest"] = history_digest(forged)
        next(e for e in document["entries"] if e["id"] == victim)["history"] = forged
        doc_path.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n")
        matrix_path = tree / "docs/design/e2e/coverage-matrix.md"
        lines = matrix_path.read_text().splitlines()
        for index, line in enumerate(lines):
            if line.startswith(f"| {victim} |"):
                cells = [c.strip() for c in LEDGER_SPLIT.split(line.strip().strip("|"))]
                cells[7] = (f"Converted to glass in impl/glass-pickers-20261010; gap: UI changed. Prior native evidence unverified at {forged['sourceSHA']} kept as history in "
                            f"inventory.json; not current glass coverage. Prior gap reason: {forged['gapReason']}.")
                cells[8] = cells[9] = cells[11] = "TBD"
                cells[13] = "UI changed"
                lines[index] = "| " + " | ".join(cells) + " |"
        matrix_path.write_text("\n".join(lines) + "\n")
        result = inventory_check(tree)
        check(result.returncode != 0 and victim in (result.stdout + result.stderr), f"history (can fail): an unsafe gap rewritten to UI changed is refused by --check ({victim})")
        check(any(victim in p and "never rewritten" in p for p in history_problems(tree, base_rows)), f"history (can fail): and by the guard's own history check ({victim})")

    # A converted row can be promoted, but only by genuinely new glass evidence.
    def promotion(name, fields=lambda ident: {}):
        """A scratch tree whose first converted row is rewritten as an audit would; the evidence file it names is created unless the case says otherwise."""
        tree, ident = ledger_mutant(base, name, converted_row, lambda r: promote_row(r, converted[r[0]], **fields(r[0])))
        given = fields(ident)
        evidence = given.get("path", "docs/design/evidence/e2e-fixture/01-glass.jpg")
        if evidence not in NOT_EVIDENCE and given.get("exists", True):
            for part in evidence.split(";"):
                (tree / part.strip()).parent.mkdir(parents=True, exist_ok=True)
                (tree / part.strip()).write_bytes(b"fixture")
        return tree, ident
    tree, ident = promotion("history-promoted")
    regenerated = subprocess.run([sys.executable, "-I", str(tree / "tools/e2e-inventory.py")], capture_output=True, text=True, cwd=tree)
    result = inventory_check(tree)
    check(regenerated.returncode == 0 and result.returncode == 0, f"history (positive): a row promoted with a complete observation, a new glass SHA, a real new evidence file and a reviewer passes the generator ({ident})")
    check(not [p for p in history_problems(tree, base_rows) if ident in p], f"history (positive): and the guard's history check ({ident})")
    transition_prose = lambda ident: (f"Converted to glass in impl/glass-pickers-20261010; gap: UI changed. Prior native evidence {converted[ident]['evidenceClass']} at "
                                      f"{converted[ident]['sourceSHA']} kept as history in inventory.json; not current glass coverage.")
    bad = {
        "the old native SHA with a rewritten observation": lambda ident: dict(sha=converted[ident]["sourceSHA"]),
        "the transition prose left in as the observation": lambda ident: dict(observed=transition_prose(ident)),
        "a TBD source SHA": lambda ident: dict(sha="TBD"),
        "a TBD evidence path": lambda ident: dict(path="TBD"),
        "a TBD reviewer": lambda ident: dict(reviewer="TBD"),
        "an evidence file that does not exist": lambda ident: dict(exists=False),
        "the native evidence file reused as the new evidence": lambda ident: dict(path=converted[ident]["evidencePath"]),
        "the native observation copied as the new one": lambda ident: dict(observed=converted[ident]["observed"]),
        "a gap reason left on the promoted row": lambda ident: dict(reason="UI changed"),
    }
    for label, fields in bad.items():
        tree, ident = promotion("history-promotion-" + re.sub(r"\W+", "-", label)[:30], fields)
        check(any(ident in p and "promoted without new glass evidence" in p for p in history_problems(tree, base_rows)),
              f"history (can fail): a promotion with {label} is refused by the history check ({ident})")

    # A converted row relabelled with another valid reason is not a state this contract allows.
    tree, ident = ledger_mutant(base, "history-other-reason", converted_row, lambda r: (r.__setitem__(7, "J9 lane: gap: harness."), r.__setitem__(13, "harness")))
    check(any(ident in p for p in history_problems(tree, base_rows)), f"history (can fail): a converted row relabelled with another reason is refused by the history check ({ident})")


PANEL = "com.apple.appkit.xpc.openAndSavePanelService"
PANEL_PATH = f"/System/Library/Frameworks/AppKit.framework/Versions/C/XPCServices/{PANEL}.xpc/Contents/MacOS/{PANEL}"
THRESHOLD_KB = 2097152


def ps_listing(rows):
    return "".join(f"{pid:>6} {rss:>9} {comm}\n" for pid, rss, comm in rows)


def set_fake_ps(rows):
    Path(SAFE["fake_ps"]).write_text("#!/bin/sh\ncat <<'EOF'\n" + ps_listing(rows) + "EOF\n")
    Path(SAFE["fake_ps"]).chmod(0o755)


def set_fake_env(table):
    """`ps eww -p PID` stand-in: pid -> the text after the command (the process environment); a pid absent from the table prints nothing."""
    Path(SAFE["env_table"]).write_text("".join(f"{pid} {text}\n" for pid, text in table.items()))


def owned_env(session_dir):
    """What `ps eww` shows for a panel service the session's app started: the service inherits the client's CFFIXED_USER_HOME, HOME and TMPDIR."""
    return f"{PANEL_PATH} PATH=/usr/bin HOME={session_dir}/home CFFIXED_USER_HOME={session_dir}/home TMPDIR={session_dir}/tmp OPENSNAP_APP_SUPPORT={session_dir}/support"


def killed_pids():
    path = Path(SAFE["kill_log"])
    return sorted(int(line.split()[-1]) for line in path.read_text().splitlines() if line.startswith("-9 ")) if path.exists() else []


def watch(script, rows, session_id, extra_env=None, ticks="1", env=None):
    """Run the `watchdog` subcommand (bounded by ticks) over a fake process table; returns (killed pids, log lines).
    Every row is a service of the session unless `env` overrides a pid's environment text (None: unreadable)."""
    reap()
    marked = forge_session(SAFE["base"], session_id, name=f"{session_id}.session")
    set_fake_ps(rows)
    table = {pid: owned_env(marked) for pid, _, _ in rows}
    for pid, text in (env or {}).items():
        table.pop(pid, None)
        if text is not None:
            table[pid] = text
    set_fake_env(table)
    Path(SAFE["kill_log"]).write_text("")
    result = run(script, ["watchdog", session_id], dict({"E2E_WATCHDOG_TICKS": ticks}, **(extra_env or {})))
    log = state_dir() / f"{session_id}.watchdog.log"
    return result, killed_pids(), (log.read_text().splitlines() if log.exists() else [])


def test_watchdog(base, app):
    text = SCRIPT.read_text()
    ident = f"{REAL_ID}.e2e-42001"
    over, under = THRESHOLD_KB + 1, THRESHOLD_KB
    rows = [(900, over, PANEL_PATH),                                           # the target: exact name, above threshold
            (901, 4096, PANEL_PATH),                                           # exact name, tiny
            (902, under, PANEL_PATH),                                          # exact name, exactly AT the threshold: not above it
            (903, over * 8, "/Applications/Some App.app/Contents/MacOS/Some App"),                     # huge but a different process
            (904, over * 8, f"/tmp/{PANEL}-helper"),                          # prefix of the name
            (905, over * 8, f"/Users/me/not-{PANEL}"),                        # suffix match only
            (906, over * 8, f"/tmp/{PANEL}.sh"),                              # name plus an extension
            (907, over * 8, "/System/Library/CoreServices/launchservicesd"),
            (908, over * 8, "/usr/bin/vim"),
            (909, over * 8, f"/tmp/dir with {PANEL} in it/runner"),           # name only in a parent directory
            (910, over + 5, f"/tmp/Odd Path/{PANEL}")]                         # exact basename under a path with a space
    result, killed, log = watch(SCRIPT, rows, ident)
    check(result.returncode == 0, f"watchdog: the bounded loop exits 0 ({result.all_output.strip()[-160:]})")
    check(killed == [900, 910], f"watchdog: only the exact panel service above the threshold is SIGKILLed (killed {killed})")
    check(len(log) == 2 and all(re.match(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d{4} killed pid (900|910) rss \d+KB \(threshold 2097152KB\) " + PANEL + r"$", l) for l in log),
          f"watchdog: each kill is logged with a timestamp, pid, rss and the threshold ({log[:1]})")
    check(Path(SAFE["kill_log"]).read_text().splitlines() == ["-9 900", "-9 910"],
          "watchdog: every kill is a -9 on exactly the logged pids")

    result, killed, log = watch(SCRIPT, [(900, under, PANEL_PATH), (901, 10, PANEL_PATH)], ident)
    check(not killed and not log, "watchdog: a panel service at or below the threshold is left alone and nothing is logged")
    result, killed, log = watch(SCRIPT, rows, ident, {"E2E_PANEL_WATCHDOG_KB": "1000"})
    check(killed == [900, 901, 902, 910], f"watchdog: E2E_PANEL_WATCHDOG_KB lowers the threshold (killed {killed})")
    result, killed, log = watch(SCRIPT, rows, ident, {"E2E_PANEL_WATCHDOG_KB": "999999999999"})
    check(not killed, "watchdog: E2E_PANEL_WATCHDOG_KB raises the threshold")
    result, killed, log = watch(SCRIPT, rows, ident, {"E2E_PANEL_WATCHDOG_KB": "lots"})
    check(killed == [900, 910], "watchdog: a non-numeric override falls back to the 2 GB default")
    result, killed, log = watch(SCRIPT, [(1, over, PANEL_PATH), (0, over, PANEL_PATH), (911, over, PANEL_PATH)], ident)
    check(killed == [911], f"watchdog: pid 0 and 1 are never signalled (killed {killed})")

    # The loop ends when the session file is gone.
    reap()
    set_fake_ps([(900, over, PANEL_PATH)])
    Path(SAFE["kill_log"]).write_text("")
    result = run(SCRIPT, ["watchdog", ident], {"E2E_WATCHDOG_TICKS": "50"})
    check(result.returncode == 0 and not killed_pids() and not (state_dir() / f"{ident}.watchdog.log").exists(), "watchdog: with no session file the loop does not run, even unbounded")
    result = run(SCRIPT, ["watchdog", REAL_ID], {"E2E_WATCHDOG_TICKS": "1"})
    check(result.returncode == 2 and "refusing" in result.stderr, "watchdog: a real/odd session id is refused")

    # Can fail: matching on a substring of the command instead of the exact name kills the decoys too.
    mutant = script_copy(base, "mut-watch-match", text.replace('parts[n] == name', 'index($0, "openAndSavePanelService") > 0'))
    check(mutant.read_text() != text, "watchdog (can fail): the match mutation applied")
    result, killed, log = watch(mutant, rows, ident)
    check(killed != [900, 910] and {904, 905, 906, 909} <= set(killed), f"watchdog (can fail): a loose name match also kills the decoys (killed {killed})")
    mutant = script_copy(base, "mut-watch-threshold", text.replace("rss + 0 > max + 0", "rss + 0 >= 0"))
    result, killed, log = watch(mutant, rows, ident)
    check({901, 902} <= set(killed), f"watchdog (can fail): ignoring the threshold kills small panel services (killed {killed})")
    mutant = script_copy(base, "mut-watch-pid1", text.replace("pid + 0 > 1 && ", ""))
    result, killed, log = watch(mutant, [(1, over, PANEL_PATH)], ident)
    check(killed == [1], f"watchdog (can fail): without the pid guard pid 1 is a kill target (killed {killed})")
    reap()

    # Lifecycle through start/status/stop (a fake app, the fake ps lists nothing over the threshold).
    set_fake_ps([])
    result = start(app)
    session = read_session(sessions()[0])
    session_id = session["id"]
    pidfile = state_dir() / f"{session_id}.watchdog.pid"
    wpid = pidfile.read_text().strip() if pidfile.exists() else ""
    check(result.returncode == 0 and wpid.isdigit() and alive(wpid), f"watchdog lifecycle: start writes {pidfile.name} and the watchdog is running (pid {wpid})")
    check("panel watchdog" in result.stdout and "2097152KB" in result.stdout, "watchdog lifecycle: start reports the watchdog and its threshold")
    command = subprocess.run(["ps", "-o", "command=", "-p", wpid], capture_output=True, text=True).stdout
    check(command.strip().endswith(f"watchdog {session_id}"), f"watchdog lifecycle: the process is this script's watchdog for this session ({command.strip()[-60:]})")
    status = run(SCRIPT, ["status"])
    check(f"panel watchdog pid {wpid} running, threshold 2097152KB, kills 0" in status.stdout, "watchdog lifecycle: status reports the watchdog, threshold and kill count")
    # A kill shows up in the log, in status and in stop's output.
    set_fake_ps([(920, over, PANEL_PATH), (921, over, PANEL_PATH)])
    set_fake_env({920: owned_env(session["dir"]), 921: owned_env("/private/var/folders/zz/another-app/T/other-session")})
    deadline = time.time() + 5
    log_path = state_dir() / f"{session_id}.watchdog.log"
    while time.time() < deadline and not (log_path.exists() and log_path.read_text()):
        time.sleep(0.1)
    set_fake_ps([])
    check(log_path.exists() and " killed pid 920 " in log_path.read_text() and " pid 921 " not in log_path.read_text(),
          "watchdog lifecycle: the running watchdog killed this session's over-threshold panel service and logged it, and left the other app's alone")
    status = run(SCRIPT, ["status"])
    check(re.search(r"kills [1-9]", status.stdout) is not None, "watchdog lifecycle: status counts the kills")
    result = stop()
    time.sleep(0.4)
    check(result.returncode == 0 and "RESULT stores unchanged" in result.stdout and " killed pid 920 " in result.stdout, "watchdog lifecycle: stop prints the kills and still ends with unchanged stores")
    check(not alive(wpid) and not pidfile.exists() and not log_path.exists(), "watchdog lifecycle: stop ends the watchdog and removes the pid file and log")
    check(not alive(session["pid"]) and not Path(session["dir"]).exists() and result.stdout.index("watchdog         stopped") < result.stdout.index("real stores      after:"),
          "watchdog lifecycle: the app and dir are gone and the watchdog is stopped before the final store compare")

    # Order: the app SIGTERM, defaults drop and dir removal precede the compare exactly as before (evil defaults damage is still caught).
    reap()
    start(app, defaults=SAFE["evil"])
    result = stop(defaults=SAFE["evil"])
    check(result.returncode != 0 and "RESULT STORES CHANGED" in result.stdout, "watchdog lifecycle: damage done during cleanup is still caught after the watchdog was added")

    # stop never signals a pid-file entry that is not this session's watchdog.
    reap()
    start(app)
    session = read_session(sessions()[0])
    pidfile = state_dir() / f"{session['id']}.watchdog.pid"
    real_wpid = pidfile.read_text().strip()
    os.kill(int(real_wpid), signal.SIGKILL)
    decoy = subprocess.Popen(["sleep", "300"])
    try:
        pidfile.write_text(f"{decoy.pid}\n")
        stop()
        time.sleep(0.3)
        check(decoy.poll() is None, "watchdog lifecycle: a pid-file pid that is not this session's watchdog is never signalled")
    finally:
        decoy.kill(); decoy.wait()
    reap()
    mutant = script_copy(base, "mut-watch-stop", text.replace('*" watchdog $id") kill', '*) kill'))
    start(app, script=mutant)
    session = read_session(sessions()[0])
    pidfile = state_dir() / f"{session['id']}.watchdog.pid"
    os.kill(int(pidfile.read_text().strip()), signal.SIGKILL)
    decoy = subprocess.Popen(["sleep", "300"])
    try:
        pidfile.write_text(f"{decoy.pid}\n")
        stop(script=mutant)
        time.sleep(0.3)
        check(decoy.poll() is not None, "watchdog lifecycle (can fail): with the identity check removed stop signals the decoy")
    finally:
        decoy.kill(); decoy.wait()
    reap()


def test_watchdog_scope(base, app):
    """The watchdog kills only this session's panel service: judged from the service's `ps eww` environment (fake table, no real process read)."""
    text = SCRIPT.read_text()
    ident = f"{REAL_ID}.e2e-42002"
    over = THRESHOLD_KB + 1
    mine = str(Path(SAFE["tmp"]) / "e2e-session.FORGED")
    other_app = "/private/var/folders/zz/another-app/T/some-other-run"
    rows = [(940, over, PANEL_PATH),        # this session's service, big: killed
            (941, over, PANEL_PATH),        # another app's service, big: foreign environment
            (942, over, PANEL_PATH),        # a lookalike dir that merely starts with this session's path
            (943, over, PANEL_PATH),        # big, but its environment cannot be read
            (944, over, PANEL_PATH),        # this session's dir appears only inside another variable's value, not as HOME/TMPDIR/CFFIXED_USER_HOME
            (945, over, PANEL_PATH),        # a variable that merely ends in HOME
            (946, 4096, PANEL_PATH)]        # this session's service, small: kept
    env = {941: owned_env(other_app), 942: owned_env(mine + "X"), 943: None,
           944: f"{PANEL_PATH} PATH=/usr/bin NOTES={mine}/home HOME=/Users/someone", 945: f"{PANEL_PATH} MYHOME={mine}/home HOME=/Users/someone"}
    result, killed, log = watch(SCRIPT, rows, ident, env=env)
    check(result.returncode == 0 and killed == [940], f"watchdog scope: only the big service whose environment names this session is killed (killed {killed})")
    check(len(log) == 1 and " killed pid 940 " in log[0], f"watchdog scope: only that kill is logged ({log})")
    result, killed, log = watch(SCRIPT, rows[:1], ident, env={940: owned_env(other_app)})
    check(not killed and not log, "watchdog scope: a big service from another app's environment is NOT killed, however big")
    result, killed, log = watch(SCRIPT, rows[:1], ident, env={940: f"{PANEL_PATH} TMPDIR={mine}/tmp"})
    check(killed == [940], "watchdog scope: a TMPDIR under the session dir alone is enough to attribute the service")
    result, killed, log = watch(SCRIPT, rows[:1], ident, env={940: f"{PANEL_PATH} CFFIXED_USER_HOME={mine}//home"})
    check(killed == [940], "watchdog scope: the non-normalized (\"//\") CFFIXED_USER_HOME that grows without bound is still attributed to its session")
    result, killed, log = watch(SCRIPT, rows[:1], ident, extra_env={"E2E_PANEL_WATCHDOG_KB": "1000"}, env={940: owned_env(other_app)})
    check(not killed, "watchdog scope: lowering the threshold never widens the scope")
    # A session file with no dir field has nothing to attribute a service to.
    reap()
    forge_session(SAFE["base"], ident, name=f"{ident}.session")
    (state_dir() / f"{ident}.session").write_text(f"id={ident}\npid=\nseed=empty\naws=no\n")
    set_fake_ps(rows[:1]); set_fake_env({940: owned_env(mine)}); Path(SAFE["kill_log"]).write_text("")
    result = run(SCRIPT, ["watchdog", ident], {"E2E_WATCHDOG_TICKS": "1"})
    check(result.returncode == 0 and not killed_pids(), "watchdog scope: a session file without a dir kills nothing")

    # Can fail: with the environment test removed every big service is a target again; with the trailing slash dropped a lookalike dir matches.
    mutant = script_copy(base, "mut-scope-all", text.replace('    return 1\n}\n\n# "pid rss" for every process of THIS session', '    return 0\n}\n\n# "pid rss" for every process of THIS session', 1))
    check(mutant.read_text() != text, "watchdog scope (can fail): the scope mutation applied")
    result, killed, log = watch(mutant, rows, ident, env=env)
    check({940, 941, 942, 943, 944, 945} <= set(killed), f"watchdog scope (can fail): without the environment test every big service is killed (killed {killed})")
    mutant = script_copy(base, "mut-scope-slash", text.replace('=$dir/"*', '=$dir"*'))
    check(mutant.read_text() != text, "watchdog scope (can fail): the prefix mutation applied")
    result, killed, log = watch(mutant, rows, ident, env=env)
    check(942 in killed and 941 not in killed, f"watchdog scope (can fail): without the trailing slash a lookalike dir is killed (killed {killed})")
    mutant = script_copy(base, "mut-scope-loose", text.replace('*" HOME=$dir/"*', '*"HOME=$dir/"*'))
    result, killed, log = watch(mutant, rows, ident, env=env)
    check(945 in killed and 941 not in killed, f"watchdog scope (can fail): without the leading space a variable ending in HOME is attributed (killed {killed})")
    reap()


def test_panel_service_check(base):
    """tools/panel-service-check.sh opens a real panel, so it is never run here; its own `session_panel_services` function is lifted out and run
    over a fake `ps` (the same text with /bin/ps pointed at the fake) and the script text is checked for the real-home cleanup it must not have."""
    script = root / "tools/panel-service-check.sh"
    text = script.read_text()
    check("Library/Preferences" not in text and "defaults delete" not in text and "$HOME/" not in text,
          "panel-service-check: nothing outside the run's own temp dir is touched (no real Preferences cleanup, no $HOME path)")
    check(text.count("session_panel_services") >= 3, "panel-service-check: the peak and the watchdog both read the session-scoped list")
    function = re.search(r"^session_panel_services\(\) \{\n.*?^\}$", text, re.M | re.S).group(0)
    run_dir = "/private/var/folders/zz/me/T/panel-service-check.AbC123"
    fake = Path(base) / "fake-ps-check.sh"
    fake.write_text(f"""#!/bin/sh
if [ "$1" = "-axo" ]; then
cat <<'EOF'
{ps_listing([(700, 3000000, PANEL_PATH), (701, 3000000, PANEL_PATH), (702, 3000000, PANEL_PATH), (703, 3000000, PANEL_PATH), (704, 90000, PANEL_PATH),
             (705, 3000000, "/usr/bin/vim"), (1, 3000000, PANEL_PATH)])}EOF
else
for last; do :; done
awk -v p="$last" '$1 == p {{ sub(/^[^ ]+ /, ""); print }}' '{SAFE["env_table"]}'
fi
""")
    fake.chmod(0o755)
    set_fake_env({700: owned_env(run_dir), 701: owned_env("/private/var/folders/zz/another/T/panel-service-check.Zzz999"), 702: f"{PANEL_PATH} CFFIXED_USER_HOME={run_dir}//home",
                  704: owned_env(run_dir), 705: owned_env(run_dir), 1: owned_env(run_dir)})

    def listed(source):
        harness = Path(base) / "psc-harness.sh"
        harness.write_text(f"T={run_dir}\n{source}\nsession_panel_services\n")
        return subprocess.run(["sh", str(harness)], capture_output=True, text=True, timeout=30).stdout.split("\n")[:-1]
    bound = function.replace("/bin/ps", str(fake))
    check(bound != function, "panel-service-check: the fake ps was bound into the function copy")
    check(listed(bound) == ["700 3000000", "702 3000000", "704 90000"],
          f"panel-service-check: only this run's panel services are listed: the other run's, an unreadable one, pid 1 and non-panel processes are not ({listed(bound)})")
    mutant = bound.replace('*" CFFIXED_USER_HOME=$T/"*|*" HOME=$T/"*|*" TMPDIR=$T/"*) echo', "*) echo")
    check(mutant != bound and {"701 3000000", "703 3000000"} <= set(listed(mutant)),
          "panel-service-check (can fail): without the environment test another run's and an unreadable service are counted and would be killed")
    reap_env()


def reap_env():
    set_fake_env({})


def test_runs_were_safe():
    check(len(RUNS) > 0 and all(env_problem(env) is None for env in RUNS),
          f"every one of the {len(RUNS)} script runs used the scratch HOME and TMPDIR and a fake defaults recorder")
    check(env_problem({"HOME": os.environ.get("HOME", ""), "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": SAFE["defaults"]}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"]}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": "/usr/bin/defaults"}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": os.environ.get("TMPDIR", "/tmp"), "E2E_DEFAULTS": SAFE["defaults"]}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": SAFE["defaults"], "E2E_WATCHDOG_PS": SAFE["fake_ps"], "E2E_WATCHDOG_ENV": SAFE["fake_env"], "E2E_WATCHDOG_KILL": SAFE["fake_kill"]}) is None,
          "the env checker rejects a real HOME, a real TMPDIR, a missing recorder and the real /usr/bin/defaults")
    check(env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": SAFE["defaults"]}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": SAFE["defaults"], "E2E_WATCHDOG_PS": "/bin/ps", "E2E_WATCHDOG_ENV": SAFE["fake_env"], "E2E_WATCHDOG_KILL": SAFE["fake_kill"]}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": SAFE["defaults"], "E2E_WATCHDOG_PS": SAFE["fake_ps"], "E2E_WATCHDOG_ENV": "/bin/ps eww -o command= -p", "E2E_WATCHDOG_KILL": SAFE["fake_kill"]}) is not None
          and env_problem({"HOME": SAFE["home"], "TMPDIR": SAFE["tmp"], "E2E_DEFAULTS": SAFE["defaults"], "E2E_WATCHDOG_PS": SAFE["fake_ps"], "E2E_WATCHDOG_ENV": SAFE["fake_env"], "E2E_WATCHDOG_KILL": "kill"}) is not None,
          "the env checker rejects a run without the fake ps, ps eww and kill (so a test can never signal a real process)")


with tempfile.TemporaryDirectory(prefix="e2e-guard-test.") as scratch:
    scratch = str(Path(scratch).resolve())
    scratch_home = make_home(scratch)
    good, evil, log = make_recorders(scratch)
    (Path(scratch) / "tmp").mkdir()
    fake_ps, fake_kill, kill_log = Path(scratch) / "fake-ps.sh", Path(scratch) / "fake-kill.sh", Path(scratch) / "fake-kill.log"
    fake_ps.write_text("#!/bin/sh\n")
    fake_kill.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{kill_log}'\n")
    fake_env, env_table = Path(scratch) / "fake-env.sh", Path(scratch) / "fake-env.table"
    env_table.write_text("")
    fake_env.write_text(f"#!/bin/sh\nawk -v p=\"$1\" '$1 == p {{ sub(/^[^ ]+ /, \"\"); print }}' '{env_table}'\n")
    for path in (fake_ps, fake_kill, fake_env):
        path.chmod(0o755)
    SAFE.update(fake_env=str(fake_env), env_table=str(env_table), home=str(scratch_home), tmp=str(Path(scratch) / "tmp"), defaults=str(good), evil=str(evil), log=str(log),
                fake_ps=str(fake_ps), fake_kill=str(fake_kill), kill_log=str(kill_log), base=scratch)
    app = fake_app(scratch)
    try:
        test_static()
        test_start_stop(scratch, app)
        test_normalized_home(scratch, app)
        test_tamper_and_order(scratch, app)
        test_kill_fallback(scratch)
        test_free_icons(scratch)
        test_protections(scratch, app)
        test_aws(scratch, app)
        test_watchdog(scratch, app)
        test_watchdog_scope(scratch, app)
        test_panel_service_check(scratch)
        test_inventory(scratch)
        test_runs_were_safe()
    finally:
        reap()
if failures:
    raise SystemExit(f"FAIL test-e2e-session-guard: {len(failures)} check(s) failed")
print("PASS test-e2e-session-guard")
