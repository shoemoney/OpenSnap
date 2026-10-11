"""The owner's real data stores, which no test or harness run may touch (imported by tools/test.py; also a CLI).

Watched: the previous app's whole Application Support folder, the new app's folder, and both defaults
plists. The new app's folder must not even be CREATED by a run. Contents are hashed, never printed.
Named with the retired product name on purpose; it is on the allowlist of check-skitch-strings.py.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import sys
import time

HOME = SUPPORT = OLD_FOLDER = OPENSNAP_FOLDER = PREFERENCES = None
REAL_STORE_FOLDERS = []
REAL_STORE_FILES = []


def use_home(home):
    """Point every watched path at `home`. The default is the real home; only tests and the CLI's --home flag move it."""
    global HOME, SUPPORT, OLD_FOLDER, OPENSNAP_FOLDER, PREFERENCES, REAL_STORE_FOLDERS, REAL_STORE_FILES
    HOME = Path(home)
    SUPPORT = HOME / "Library/Application Support"
    OLD_FOLDER = SUPPORT / "SkitchRedux"
    OPENSNAP_FOLDER = SUPPORT / "OpenSnap"
    PREFERENCES = HOME / "Library/Preferences"
    REAL_STORE_FOLDERS = [OLD_FOLDER, OPENSNAP_FOLDER]
    REAL_STORE_FILES = [PREFERENCES / "com.shoemoney.skitch-redux.plist", PREFERENCES / "com.shoemoney.opensnap.plist"]


use_home(os.path.expanduser("~"))
# Throwaway defaults suites the tests (current and earlier names) create; none may be left behind by a run.
THROWAWAY_PREFIXES = ["SkitchRedux.ResizePresetsTests.", "SkitchHistoryTests.", "OpenSkitch.preferences.tests.",
                      "SkitchRedux.GlobalHotkeys.Tests.", "OpenSkitch.appearance.tests.", "OpenSkitch.magnifier.",
                      "OpenSnap.ResizePresetsTests.", "OpenSnapHistoryTests.", "OpenSnap.preferences.tests.",
                      "OpenSnap.magnifier.", "OpenSnap.GlobalHotkeys.Tests.", "openskitch-hotkey-probe",
                      "com.test.opensnap.", "com.shoemoney.opensnap.eyedump-", "com.shoemoney.opensnap.startup-",
                      "com.shoemoney.opensnap.e2e-", "AppSafetyTests-"]


def throwaway_plists():
    """Names of every plist in ~/Library/Preferences that matches a throwaway test prefix."""
    return {path.name for path in PREFERENCES.glob("*.plist") if path.name.startswith(tuple(THROWAWAY_PREFIXES))}


PID_NAMED = re.compile(r"^(?:AppSafetyTests-|com\.shoemoney\.opensnap\.eyedump-)(\d+)(?:[-.]|$)")
GRACE_SECONDS = 3.0


def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def leftovers(new_names):
    """Of the plists that are new since the snapshot, those that are genuinely left behind.

    A plist named for a PID (AppSafetyTests-<pid>-..., eyedump-<pid>) whose process is still alive belongs to a
    run in flight (another worktree's, or ours); it is not a leftover, and this never deletes it. A dead PID's file
    is re-checked after a short grace, since a finishing run removes its own plist just after its process exits.
    Names without a PID are always leftovers.
    """
    suspects = set(new_names)
    deadline = time.monotonic() + GRACE_SECONDS
    while True:
        suspects = {n for n in suspects if (PREFERENCES / n).exists()}
        dead = set()
        for name in suspects:
            match = PID_NAMED.match(name)
            if not match or not _pid_alive(int(match.group(1))):
                dead.add(name)
        if not dead or time.monotonic() >= deadline:
            return dead
        time.sleep(0.5)


def describe():
    return [str(path) for path in REAL_STORE_FOLDERS + REAL_STORE_FILES]


def _entry(path):
    info = path.stat()
    return (info.st_size, info.st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest())


def snapshot():
    """(folders, {path: (size, mtime_ns, sha256)}) for every file in the real stores."""
    entries = {}
    for folder in REAL_STORE_FOLDERS:
        if folder.exists():
            for path in sorted(folder.rglob("*")):
                if path.is_file():
                    entries[str(path)] = _entry(path)
    for path in REAL_STORE_FILES:
        if path.is_file():
            entries[str(path)] = _entry(path)
    return REAL_STORE_FOLDERS, entries


def compare(before, opensnap_folder_existed, plists_before=None):
    """Problems found since `before` (an earlier snapshot()); empty when nothing was touched."""
    _, after = snapshot()
    problems = [f"{'changed' if name in before and name in after else 'appeared' if name in after else 'disappeared'} {name}"
                for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)]
    # No test may write preferences for any OpenSnap-named domain: CFFIXED_USER_HOME does not redirect the
    # preferences daemon, so a defaults suite used by a test lands in the real ~/Library/Preferences.
    if plists_before is not None:
        problems += [f"left behind {PREFERENCES / name}" for name in sorted(leftovers(throwaway_plists() - plists_before))]
    if not opensnap_folder_existed and OPENSNAP_FOLDER.exists():
        problems.append(f"created {OPENSNAP_FOLDER}")
    return problems


def _cli(argv):
    """guard.py [--home DIR] snapshot FILE | compare FILE | folders  (exit 1 when anything watched changed; contents never printed)."""
    home = None
    if argv[:1] == ["--home"]:
        home, argv = argv[1], argv[2:]
    if home:
        use_home(home)
    if argv == ["folders"]:
        print("\n".join(str(path) for path in REAL_STORE_FOLDERS))
        return 0
    if len(argv) != 2 or argv[0] not in ("snapshot", "compare"):
        print(_cli.__doc__, file=sys.stderr)
        return 2
    command, state_file = argv
    if command == "snapshot":
        _, entries = snapshot()
        Path(state_file).write_text(json.dumps({"opensnapFolderExisted": OPENSNAP_FOLDER.exists(), "plists": sorted(throwaway_plists()),
                                                "entries": {k: list(v) for k, v in entries.items()}}, indent=1))
        print(_summary(entries))
        return 0
    saved = json.loads(Path(state_file).read_text())
    before = {k: tuple(v) for k, v in saved["entries"].items()}
    problems = compare(before, saved["opensnapFolderExisted"], set(saved["plists"]))
    print(_summary(snapshot()[1]))
    for problem in problems:
        print("STORE CHANGED:", problem)
    print("RESULT stores unchanged" if not problems else "RESULT STORES CHANGED")
    return 1 if problems else 0


def _summary(entries):
    digest = hashlib.sha256(json.dumps(sorted((k, list(v)) for k, v in entries.items())).encode()).hexdigest()
    return (f"watched {len(entries)} files in {len(REAL_STORE_FOLDERS)} folders + {len(REAL_STORE_FILES)} defaults plists; digest {digest[:16]}; "
            f"OpenSnap folder {'exists' if OPENSNAP_FOLDER.exists() else 'absent'}")


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
