#!/usr/bin/env python3
"""OSN-072: dry-run the one-time migration against a SYNTHETIC old store and verify what it did.

  python3 tools/migration-dry-run.py [--work-dir DIR] [--keep] [--binary PATH] [--no-guard]
  python3 tools/migration-dry-run.py --self-test

It builds, in a throwaway directory, an old "SkitchRedux" Application Support folder that mimics the real layout (58 History
documents with previews and an index, two Publishing destinations on fake hosts, loose files the migration must ignore) and a
synthetic old-defaults plist. It compiles the migration test binary exactly the way tools/test.py does (Migration.swift + its
dependencies + tests/MigrationTests.swift) and runs that binary's --migration-dry-run mode, which uses in-memory defaults and an
in-memory Keychain. Then it asserts:
  1. the new History holds 58 entries and 58 .opensnap files, all opening in the new store (binary-verified);
  2. both destinations are listed, with the default preserved;
  3. migration-report.txt was written and says "No failures.";
  4. a SHA-256 / size / mtime manifest of the synthetic source is identical before and after the run;
  5. a second run is a no-op: "Nothing to migrate", exit 0, and the new tree's manifest is identical before and after.
Never read or written: ~/Library/Application Support/{SkitchRedux,OpenSnap}, the real defaults domains, the Keychain. Every path
this script touches is resolved and refused if it lies under the real home's Library; the binary's HOME and CFFIXED_USER_HOME point
into the throwaway directory. Unless --no-guard, tools/real_store_guard.py snapshots the real stores before and compares after
(it hashes them read-only and prints no contents).
Exit: 0 all assertions hold, 1 an assertion failed, 2 refused or unusable. --self-test proves each assertion can fail.
"""
from pathlib import Path
import argparse, hashlib, json, os, plistlib, pwd, re, shutil, struct, subprocess, sys, tempfile, uuid, zlib

root = Path(__file__).resolve().parent.parent
FIXTURES = root / "tests" / "fixtures"
SUITE_SOURCES = ["SVGPath.swift", "LegacyReader.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift",
                 "ImageExport.swift", "Canvas.swift", "OpenSnapFile.swift", "HistoryStore.swift", "Migration.swift", "DesignTokens.swift"]
HISTORY_COUNT = 58
OLD_SERVICE = "SkitchRedux.CustomPublishing"  # named inside the synthetic destination files so the rewrite is exercised
DESTINATIONS = [
    {"id": "D1111111-1111-4111-8111-111111111111", "name": "Synthetic SFTP", "transport": "sftp", "endpoint": "sftp://files.example.invalid/imgs",
     "credentialID": "C1111111-1111-4111-8111-111111111111"},
    {"id": "D2222222-2222-4222-8222-222222222222", "name": "Synthetic S3", "transport": "s3", "endpoint": "",
     "credentialID": "C2222222-2222-4222-8222-222222222222"},
]


class Refused(Exception):
    pass


def real_library():
    """The account's real ~/Library, from the user database (HOME and CFFIXED_USER_HOME can lie)."""
    return Path(os.path.realpath(Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library"))


def assert_safe(path):
    """Refuse any path that resolves under the real home's Library (symlinks followed); returns the resolved path."""
    resolved = Path(os.path.realpath(path))
    library = real_library()
    if resolved == library or library in resolved.parents:
        raise Refused(f"refusing {path}: it resolves to {resolved}, inside the real {library}")
    return resolved


# ---------------------------------------------------------------- synthetic store

def png(width, height, shade):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    rows = b"".join(b"\x00" + bytes(v for x in range(width) for v in (shade, x * 7 % 256, y * 5 % 256, 255)) for y in range(height))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def variant(data, kind, n):
    """A distinct but still valid copy of a fixture document. The signed .skitch SVG is left byte-for-byte alone (editing it would
    make the migration note an outside edit); the JSON and plain forms carry the number in their visible text."""
    if kind == "redux-json":
        return data.replace(b"Second font", f"Second font {n}".encode())
    return data.replace(b"Hello OpenSnap", f"Hello OpenSnap {n}".encode()) if kind == "plain" else data


def build_old_store(old_support):
    history, publishing = old_support / "History", old_support / "Publishing"
    history.mkdir(parents=True)
    publishing.mkdir()
    fixtures = {"skitch": (FIXTURES / "legacy-sample.skitch").read_bytes(), "plain": (FIXTURES / "legacy-sample-plain.skitch").read_bytes(),
                "redux-json": (FIXTURES / "legacy-sample.skitchredux").read_bytes()}
    plan = ["skitch"] * 24 + ["redux-json"] * 18 + ["plain"] * 16
    assert len(plan) == HISTORY_COUNT
    entries = []
    for n, kind in enumerate(plan):
        entry_id = str(uuid.UUID(int=0xAAAA0000 + n)).upper()
        stem = f"redux-{entry_id}-{str(uuid.UUID(int=0xBBBB0000 + n)).upper()}" if kind != "plain" else f"{1791000000 + n}-plain"
        native = stem + (".skitchredux" if kind == "redux-json" else ".skitch")
        document = variant(fixtures[kind], kind, n)
        (history / native).write_bytes(document)
        preview = stem + ".png"
        (history / preview).write_bytes(png(40 + n % 5, 25 + n % 3, 10 + n))
        entries.append({"id": entry_id, "name": f"Synthetic shot {n:02d}", "date": 813053688.5 + n, "updated": 813053700.25 + n, "size": [320, 200],
                        "text": f"synthetic note {n}", "action": ["archived", "exported", "shared"][n % 3], "nativeFile": native,
                        "digest": hashlib.sha256(document).hexdigest(), "imported": False, "previewFile": preview})
    (history / "index.json").write_text(json.dumps({"version": 1, "entries": entries, "ignoredLooseFiles": ["hidden-by-user.skitch"]}, indent=1, sort_keys=True))
    (history / "stray.skitch").write_bytes(fixtures["skitch"])  # not in the index: must not be migrated
    (history / "hidden-by-user.skitch").write_bytes(fixtures["skitch"])
    listing = {"defaultID": DESTINATIONS[1]["id"], "version": 2, "destinations": [
        {"id": d["id"], "name": d["name"], "settings": {"credentialID": d["credentialID"], "endpoint": d["endpoint"], "transport": d["transport"],
                                                        "note": OLD_SERVICE}} for d in DESTINATIONS]}
    (publishing / "destinations.json").write_text(json.dumps(listing, indent=1, sort_keys=True))
    (publishing / "destination.json").write_text(json.dumps({"credentialID": DESTINATIONS[0]["credentialID"], "transport": "sftp", "endpoint": DESTINATIONS[0]["endpoint"]}))
    (publishing / "destination.json.pre-destinations.bak").write_text('{"old":true}')
    (old_support / "Recovery.skitch").write_bytes(fixtures["skitch"])
    (old_support / "layout.json").write_text("{}")


def build_old_defaults(path):
    values = {"arrowHead": 2, "PencilSmoothing": "medium", "disableSounds": False, "appearanceStyle": "classic", "skitchInSnap": True,
              "SkitchRedux.GlobalHotkeys.v1": b"\x01\x02\x03", "ExportFormat": "skitch", "SkitchRedux.HistoryDragFormat": "skitch", "fittingPrecision": 1,
              "SKPresetResizes": [{"SKPresetResizeNameKey": "Ad", "SkitchReduxResizePresetID": "preset-9"}, {"SKPresetResizeNameKey": "Banner"}]}
    path.write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))
    return values


def manifest(folder):
    """{relative path: [kind, size, mtime_ns, sha256]} for everything below folder."""
    result = {}
    for path in sorted(folder.rglob("*")):
        info = path.lstat()
        relative = str(path.relative_to(folder))
        result[relative] = ["dir", 0, info.st_mtime_ns, ""] if path.is_dir() else ["file", info.st_size, info.st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest()]
    return result


def digest(entries):
    return hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest()[:16]


def diff(before, after):
    return [f"{'changed' if name in before and name in after else 'appeared' if name in after else 'disappeared'} {name}"
            for name in sorted(before.keys() | after.keys()) if before.get(name) != after.get(name)]


# ---------------------------------------------------------------- binary

def compile_binary(output):
    command = ["xcrun", "swiftc", "-swift-version", "5", "-target", f"{os.uname().machine}-apple-macosx26.0", "-D", "MIGRATION_TESTS"]
    command += [str(root / "Sources" / name) for name in SUITE_SOURCES] + [str(root / "tests" / "MigrationTests.swift"), "-o", str(output)]
    subprocess.run(command, cwd=root, check=True, capture_output=True)


def run_binary(binary, home, old, new, plist):
    env = {k: v for k, v in os.environ.items() if k not in ("HOME", "CFFIXED_USER_HOME")} | {"HOME": str(home), "CFFIXED_USER_HOME": str(home)}
    return subprocess.run([str(binary), "--migration-dry-run", str(old), str(new), str(plist)], capture_output=True, text=True, env=env, cwd=home)


# ---------------------------------------------------------------- the run

def real_store_guard(action, state):
    return subprocess.run([sys.executable, str(root / "tools" / "real_store_guard.py"), action, str(state)], capture_output=True, text=True)


def dry_run(options):
    """(failures, lines) for one full dry run."""
    failures, lines = [], []

    def say(text):
        lines.append(text)
        print(text, flush=True)

    def check(ok, message):
        say(("  PASS " if ok else "  FAIL ") + message)
        if not ok:
            failures.append(message)

    work = assert_safe(options.work_dir) if options.work_dir else None
    if work is None:
        work = assert_safe(tempfile.mkdtemp(prefix="opensnap-migration-dry-run-"))
    else:
        work.mkdir(parents=True, exist_ok=True)
    home, old_support = work / "home", work / "home" / "Library" / "Application Support" / "SkitchRedux"
    new_support, plist = work / "home" / "Library" / "Application Support" / "OpenSnap", work / "old-defaults.plist"
    for path in (home, old_support, new_support, plist, work / "bin"):
        assert_safe(path)
    guard_state = work / "real-store-guard.json"
    try:
        if not options.no_guard:
            snapshot = real_store_guard("snapshot", guard_state)
            if snapshot.returncode != 0:
                raise Refused("could not snapshot the real stores: " + snapshot.stderr.strip())
            say("real-store guard snapshot: " + snapshot.stdout.strip())
        home.mkdir(parents=True, exist_ok=True)
        build_old_store(old_support)
        old_values = build_old_defaults(plist)
        binary = Path(options.binary) if options.binary else work / "bin" / "migration-dry-run"
        if not options.binary:
            binary.parent.mkdir(exist_ok=True)
            compile_binary(binary)
        before = manifest(old_support)
        say(f"synthetic old store: {sum(1 for v in before.values() if v[0] == 'file')} files, manifest {digest(before)}; "
            f"{HISTORY_COUNT} History documents, {len(DESTINATIONS)} destinations, {len(old_values)} default keys")

        first = run_binary(binary, home, old_support, new_support, plist)
        say("--- run 1 (migrate) ---\n" + first.stdout.rstrip())
        if first.stderr.strip():
            say("stderr: " + first.stderr.strip()[:400])
        if options.tamper_source:
            (old_support / "layout.json").write_text('{"tampered":true}')
        check(first.returncode == 0, f"run 1 exits 0 (got {first.returncode})")
        after = manifest(old_support)
        check(before == after, "source manifest unchanged after run 1" + ("" if before == after else ": " + "; ".join(diff(before, after)[:5])))

        index = json.loads((new_support / "History" / "index.json").read_text()) if (new_support / "History" / "index.json").is_file() else {"entries": []}
        opensnap_files = sorted((new_support / "History").glob("*.opensnap")) if (new_support / "History").is_dir() else []
        expected = options.expect_history
        check(len(index["entries"]) == expected, f"new History index lists {len(index['entries'])} entries (expected {expected})")
        check(len(opensnap_files) == expected, f"new History holds {len(opensnap_files)} .opensnap files (expected {expected})")
        verified = re.search(r"DRY-RUN VERIFIED: (\d+) History entries open in the new store .*all \.opensnap: (true|false)", first.stdout, re.I)
        check(bool(verified) and int(verified.group(1)) == expected and verified.group(2).lower() == "true",
              f"the binary opened {verified.group(1) if verified else '?'} entries from the new store, all .opensnap (expected {expected})")
        check(not (new_support / "History" / "stray.skitch").exists() and not any("stray" in e.get("nativeFile", "") for e in index["entries"]),
              "the unindexed stray file was not migrated")

        destinations = json.loads((new_support / "Publishing" / "destinations.json").read_text()) if (new_support / "Publishing" / "destinations.json").is_file() else {}
        names = sorted(d["name"] for d in destinations.get("destinations", []))
        wanted = sorted(d["name"] for d in DESTINATIONS)
        check(names == wanted and len(names) == options.expect_destinations, f"destinations listed: {names} (expected {options.expect_destinations}: {wanted})")
        check(destinations.get("defaultID") == DESTINATIONS[1]["id"], "the default destination is preserved")
        check(OLD_SERVICE not in (new_support / "Publishing" / "destinations.json").read_text() if (new_support / "Publishing" / "destinations.json").is_file() else False,
              "the old Keychain service name no longer appears in the migrated destination file")

        report_file = new_support / "migration-report.txt"
        report = report_file.read_text() if report_file.is_file() else ""
        check(report.startswith("OpenSnap migration report") and f"History entries found: {HISTORY_COUNT}" in report
              and f"converted to .opensnap: {HISTORY_COUNT}" in report and "No failures." in report,
              "migration-report.txt written: found/converted 58, 'No failures.'")
        check((new_support / ".migrated-from-skitchredux").is_file(), "the completion marker was written")
        keychain = re.search(r"Keychain items: (\d+) copied, (\d+) already present, (\d+) failed", report)
        check(bool(keychain) and keychain.groups() == (str(len(DESTINATIONS)), "0", "0"), "both placeholder Keychain items were copied (in-memory fake; the real Keychain is not touched)")
        obsolete = {"appearanceStyle", "disableSounds"}
        copied = re.search(r"Preferences copied: (\d+)", report)
        check(bool(copied) and int(copied.group(1)) == len(old_values) - len(obsolete), f"preferences copied {copied.group(1) if copied else '?'} of {len(old_values)}, the {len(obsolete)} obsolete keys left out")

        new_before = manifest(new_support)
        if options.drop_marker:
            (new_support / ".migrated-from-skitchredux").unlink()
            new_before = manifest(new_support)
        second = run_binary(binary, home, old_support, new_support, plist)
        say("--- run 2 (re-run) ---\n" + second.stdout.rstrip())
        new_after = manifest(new_support)
        check(second.returncode == 0 and "Nothing to migrate" in second.stdout, "the re-run says 'Nothing to migrate' and exits 0")
        check(new_before == new_after, "the re-run left the new tree byte-identical" + ("" if new_before == new_after else ": " + "; ".join(diff(new_before, new_after)[:5])))
        check(manifest(old_support) == before or options.tamper_source, "source manifest still unchanged after the re-run")
        say(f"manifests: source before {digest(before)} / after {digest(after)}; new tree after run 1 {digest(new_before)} / after re-run {digest(new_after)}")

        if not options.no_guard:
            compare = real_store_guard("compare", guard_state)
            say("real-store guard compare: " + compare.stdout.strip().replace("\n", " | "))
            check(compare.returncode == 0, "the real stores are unchanged")
    finally:
        if not options.keep and not options.work_dir:
            shutil.rmtree(work, ignore_errors=True)
        else:
            say(f"kept: {work}")
    return failures, lines


# ---------------------------------------------------------------- self-test

def self_test():
    """Every assertion must be able to fail, and the real-Library refusal must hold before anything is created."""
    script = str(Path(__file__).resolve())
    failed = False

    def run(label, args, expected, must_not_exist=None):
        nonlocal failed
        result = subprocess.run([sys.executable, script, "--no-guard", *args], capture_output=True, text=True)
        gone = must_not_exist is None or not Path(must_not_exist).exists()
        ok = result.returncode == expected and gone
        print(f"  self-test {label}: exit {result.returncode} (expected {expected})" + ("" if gone else f"; {must_not_exist} WAS CREATED"))
        if not ok:
            print(result.stdout[-1500:], result.stderr[-500:])
        failed |= not ok

    library = real_library()
    with tempfile.TemporaryDirectory() as folder:
        binary = Path(folder) / "bin"
        compile_binary(binary)
        probe = library / "Caches" / f"opensnap-dry-run-self-test-{os.getpid()}"
        run("refuses a work dir inside the real Library", ["--work-dir", str(probe)], 2, must_not_exist=probe)
        link = Path(folder) / "link-to-library"
        link.symlink_to(library)
        run("refuses a work dir that reaches the real Library through a symlink", ["--work-dir", str(link / "Caches" / f"opensnap-dry-run-self-test-{os.getpid()}")], 2,
            must_not_exist=library / "Caches" / f"opensnap-dry-run-self-test-{os.getpid()}")
        run("a clean run passes", ["--binary", str(binary)], 0)
        run("a wrong History count fails", ["--binary", str(binary), "--expect-history", "59"], 1)
        run("a wrong destination count fails", ["--binary", str(binary), "--expect-destinations", "3"], 1)
        run("a source file changed during the run fails", ["--binary", str(binary), "--tamper-source"], 1)
        run("a re-run that is not a no-op fails", ["--binary", str(binary), "--drop-marker"], 1)
    if failed:
        raise SystemExit("FAIL migration-dry-run self-test")
    print("PASS migration-dry-run self-test")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--work-dir", help="use and keep this directory (must be outside the real ~/Library)")
    parser.add_argument("--keep", action="store_true", help="keep the throwaway directory")
    parser.add_argument("--binary", help="reuse an already-compiled migration test binary")
    parser.add_argument("--no-guard", action="store_true", help="skip the real-store guard (self-test sub-runs)")
    parser.add_argument("--expect-history", type=int, default=HISTORY_COUNT, help=argparse.SUPPRESS)
    parser.add_argument("--expect-destinations", type=int, default=len(DESTINATIONS), help=argparse.SUPPRESS)
    parser.add_argument("--tamper-source", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--drop-marker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--self-test", action="store_true", help="prove each assertion can fail")
    options = parser.parse_args()
    if options.self_test:
        self_test()
        return 0
    try:
        failures, _ = dry_run(options)
    except Refused as error:
        print(f"REFUSED: {error}", file=sys.stderr)
        return 2
    print("PASS migration dry run" if not failures else f"FAIL migration dry run: {len(failures)} assertion(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    raise SystemExit(main())
