#!/usr/bin/env python3
"""Exercise the built native app, editable save/reopen, render and real AppKit Quit, on an ISOLATED COPY.

build/OpenSnap.app is never executed. The script copies the bundle into a temp folder, gives the copy a throwaway bundle id
(com.shoemoney.opensnap.startup-<pid>, validated by a strict regex before any cleanup exists), ad-hoc re-signs it and runs only
that copy with a throwaway HOME, CFFIXED_USER_HOME, TMPDIR and OPENSNAP_APP_SUPPORT. OPENSNAP_APP_SUPPORT and CFFIXED_USER_HOME
do not redirect UserDefaults, so the real stores are hashed before the run and compared after it (tools/real_store_guard.py);
any change fails the run. The throwaway defaults domain is dropped BEFORE the final compare, so damage done by cleanup is visible.
`defaults` is injectable (OPENSNAP_STARTUP_DEFAULTS) so a test can use a recorder. No desktop input, capture permissions or network
publishing are exercised. The built window must carry the glass chrome.

--app APP runs a pre-built bundle instead of build/OpenSnap.app (skips the build-manifest check; tests only).
--guard-home DIR points the real-store guard and the defaults-plist cleanup at another home (tests only).
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import real_store_guard as guard

REAL_ID = "com.shoemoney.opensnap"
THROWAWAY_PATTERN = re.compile(r"^com\.shoemoney\.opensnap\.startup-[0-9]+$")


def valid_throwaway_id(identifier):
    """Only <real id>.startup-<digits> passes, so neither real defaults domain (current or retired) can ever match."""
    return identifier != REAL_ID and THROWAWAY_PATTERN.fullmatch(identifier) is not None


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--arch", choices=["arm64", "x86_64", "both"], default="arm64")
parser.add_argument("--timeout", type=float, default=30)
parser.add_argument("--app", type=Path)
parser.add_argument("--guard-home")
args = parser.parse_args()

# Validated before anything that could need cleaning up exists: a cleanup that runs on a bad id is how a real domain gets deleted.
THROWAWAY_ID = f"{REAL_ID}.startup-{os.getpid()}"
if not valid_throwaway_id(THROWAWAY_ID):  # protection:top
    raise SystemExit(f"refusing: throwaway id '{THROWAWAY_ID}' is not {REAL_ID}.startup-<pid>")
DEFAULTS = os.environ.get("OPENSNAP_STARTUP_DEFAULTS", "/usr/bin/defaults")
if args.guard_home:
    guard.use_home(args.guard_home)
REAL_HOME = guard.HOME


def drop_throwaway_defaults():
    """Delete the throwaway defaults domain and its plist; refuses any id that is not the validated throwaway id."""
    if not valid_throwaway_id(THROWAWAY_ID):  # protection:drop
        print("refusing to drop defaults for unexpected id:", THROWAWAY_ID, file=sys.stderr)
        return
    subprocess.run([DEFAULTS, "delete", THROWAWAY_ID], capture_output=True)
    plist = guard.PREFERENCES / (THROWAWAY_ID + ".plist")
    if plist.name == THROWAWAY_ID + ".plist" and valid_throwaway_id(plist.stem):  # protection:rm
        plist.unlink(missing_ok=True)


def prepare_copy(source, destination):
    """A re-identified, ad-hoc signed copy of the bundle. The source bundle is only ever read."""
    shutil.copytree(source, destination, symlinks=True)
    info = destination / "Contents/Info.plist"
    values = plistlib.loads(info.read_bytes())
    values["CFBundleIdentifier"] = THROWAWAY_ID
    info.write_bytes(plistlib.dumps(values))
    subprocess.run(["codesign", "--force", "--sign", "-", str(destination)], capture_output=True)
    return destination / "Contents/MacOS" / values["CFBundleExecutable"]


source_app = args.app or root / "build/OpenSnap.app"
source_binary = source_app / "Contents/MacOS" / plistlib.loads((source_app / "Contents/Info.plist").read_bytes())["CFBundleExecutable"]
digest = hashlib.sha256(source_binary.read_bytes()).hexdigest()
if args.app is None:
    manifest = json.loads((root / "build/build-manifest.json").read_text())
    assert digest == manifest["binary_sha256"], "Binary differs from its build manifest."
    for name, expected in manifest["source_sha256"].items():
        source = root / ("Info.plist" if name == "Info.plist" else "Sources/" + name)
        assert hashlib.sha256(source.read_bytes()).hexdigest() == expected, "Rebuild after changing " + name

evidence = (Path(tempfile.mkdtemp(prefix="startup-smoke-")) if args.app else root / "build" / ("startup-smoke-" + digest[:10]))
results = {"binary_sha256": digest, "bundle_id": THROWAWAY_ID, "verified_at": datetime.datetime.now(datetime.timezone.utc).isoformat()}
architectures = ["arm64", "x86_64"] if args.arch == "both" else [args.arch]

_, stores_before = guard.snapshot()
opensnap_folder_existed = guard.OPENSNAP_FOLDER.exists()
plists_before = guard.throwaway_plists()
scratch = Path(tempfile.mkdtemp(prefix="opensnap-startup-"))
store_problems = []
try:
    copy = scratch / source_app.name
    executable = prepare_copy(source_app, copy)
    for arch in architectures:
        folder = evidence / arch
        folder.mkdir(parents=True, exist_ok=True)
        home = scratch / ("home-" + arch)
        support = scratch / ("support-" + arch)
        temp = scratch / ("tmp-" + arch)
        for path in (home, support, temp):
            path.mkdir()
        env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(home), "CFFIXED_USER_HOME": str(home), "TMPDIR": str(temp),
               "OPENSNAP_APP_SUPPORT": str(support), "OPENSNAP_EVIDENCE_DIR": str(folder)}
        # Do not allow evidence left by an earlier invocation to count as a pass.
        for name in ["smoke-result.txt", "smoke.png", "smoke.opensnap", "smoke-appearance.json"]:
            (folder / name).unlink(missing_ok=True)
        result = {"passed": False}
        with (folder / "stderr.log").open("w") as log:
            process = subprocess.Popen(["/usr/bin/arch", "-" + arch, str(executable), "--smoke-test"],
                                       cwd=scratch, env=env, stdout=log, stderr=log)
            try:
                result["exit_code"] = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                # This is only this test's isolated child, never a user app process.
                process.kill()
                process.wait()
                result["error"] = "Native app did not finish startup/save/render/Quit within the test deadline."
        try:
            text = (folder / "smoke-result.txt").read_text().strip()
            result["result"] = text
            assert result.get("exit_code") == 0, result.get("error", "Native app exited unsuccessfully.")
            assert text == "native startup, .opensnap editable save/load, PNG export succeeded"
            native = (folder / "smoke.opensnap").read_bytes()
            assert json.loads(native)["format"] == "com.shoemoney.opensnap.document"
            png = (folder / "smoke.png").read_bytes()
            assert png.startswith(b"\x89PNG\r\n\x1a\n")
            # A window built from anything but the glass chrome must not pass.
            built = json.loads((folder / "smoke-appearance.json").read_text())
            result["appearance"] = built
            assert built["modernChrome"] and built["toolButtonClass"] == "GlassChromeButton" and built["glassSurfaces"] > 0, \
                "The window is not the glass chrome: %s" % built
            result.update(passed=True, png_bytes=len(png), editable_bytes=len(native),
                          editable_sha256=hashlib.sha256(native).hexdigest())
        except Exception as error:
            result["error"] = str(error)
        results[arch] = result
        print(arch, "PASS" if result["passed"] else "FAIL",
              result.get("error", "native save/reopen/render and Quit, glass chrome (%d glass surfaces)" % result.get("appearance", {}).get("glassSurfaces", 0)), flush=True)
finally:
    # All defaults cleanup happens here, before the compare, so the compare observes whatever cleanup did.
    drop_throwaway_defaults()
    shutil.rmtree(scratch, ignore_errors=True)
    store_problems = guard.compare(stores_before, opensnap_folder_existed, plists_before)

print("real stores:", "unchanged (defaults domain %s dropped before the compare)" % THROWAWAY_ID if not store_problems else "CHANGED", flush=True)
for problem in store_problems:
    print("STORE CHANGED:", problem, flush=True)
results["real_stores_unchanged"] = not store_problems
evidence.mkdir(parents=True, exist_ok=True)
(evidence / "results.json").write_text(json.dumps(results, indent=2) + "\n")
print("Evidence:", evidence, flush=True)
runs_passed = all(results[arch]["passed"] for arch in architectures)
raise SystemExit(0 if runs_passed and not store_problems else 1)
