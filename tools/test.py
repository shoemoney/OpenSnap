#!/usr/bin/env python3
"""Run independent native regression suites against a consistent source snapshot."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse, hashlib, json, os, platform, re, subprocess, sys, tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=["arm64", "x86_64"], default=platform.machine())
options = parser.parse_args()
root = Path(__file__).resolve().parent.parent
build = root / "build"
build.mkdir(exist_ok=True)
SUITE_OUTPUT = []  # every suite binary's output, for the G11 skip budget at the end

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import real_store_guard as guard
REAL_STORE_FOLDERS, SUPPORT = guard.REAL_STORE_FOLDERS, guard.SUPPORT
OPENSNAP_FOLDER_EXISTED = guard.OPENSNAP_FOLDER.exists()

def real_store_snapshot():
    return guard.snapshot()

def check_real_store(before):
    problems = guard.compare(before, OPENSNAP_FOLDER_EXISTED, PLISTS_BEFORE)
    if problems:
        raise SystemExit("FAIL real-store-guard: the owner's real stores " + str(guard.describe()) + " were touched by this run:\n" + "\n".join(problems))
    print("PASS real-store-guard (", len(guard.snapshot()[1]), "files in", len(REAL_STORE_FOLDERS), "real-store folders and 2 defaults files unchanged; OpenSnap folder not created; throwaway preference plists", len(PLISTS_BEFORE), "before /", len(guard.throwaway_plists()), "after, none new )", flush=True)

real_store_folder, real_store_before = real_store_snapshot()
PLISTS_BEFORE = guard.throwaway_plists()

def secrets_guard():
    """Licensed fonts and registry credentials must never become committable."""
    forbidden = re.compile(r"\.(ttf|otf|woff2?)$|(^|/)(\.npmrc|package-lock\.json)$|(^|/)node_modules/|(^|/)fortawesome-fontawesome-pro-[^/]*\.tgz$", re.I)
    listing = subprocess.run(["/usr/bin/git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=root, capture_output=True, text=True)
    problems = [f"committable licensed/credential file: {name}" for name in listing.stdout.splitlines() if forbidden.search(name)]
    token = re.compile(rb"_authToken=[0-9A-Fa-f-]{36}|FONTAWESOME[A-Z_]*TOKEN\s*[=:]\s*[\"']?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
    for folder in ("Sources", "tools", "tests"):
        for path in sorted((root / folder).rglob("*")):
            if path.is_file() and token.search(path.read_bytes()):
                problems.append(f"registry auth token in {path.relative_to(root)}")
    notices = root / "THIRD_PARTY_NOTICES.md"
    if notices.exists() and token.search(notices.read_bytes()):
        problems.append("registry auth token in THIRD_PARTY_NOTICES.md")
    if problems:
        raise SystemExit("FAIL secrets-guard\n" + "\n".join(problems))
    return "secrets-guard"

print("PASS", secrets_guard(), flush=True)
# The retired product name stays confined to the migration; the reader of retired formats stays unreachable from the app.
subprocess.run([sys.executable, str(root / "tools" / "check-skitch-strings.py")], cwd=root, check=True)
# OSN-024: nothing under Sources, tests or tools may name the retired original-archive folder.
subprocess.run([sys.executable, str(root / "tools" / "check-no-original.py"), "--sources"], cwd=root, check=True)
# OSN-031: Info.plist names follow DesignTokens.Brand.name and no title uses three ASCII dots; the self-test proves it can fail.
subprocess.run([sys.executable, str(root / "tools" / "check-brand.py")], cwd=root, check=True)
subprocess.run([sys.executable, str(root / "tools" / "check-brand.py"), "--self-test"], cwd=root, check=True)
# The screenshot harness's protections (store guard, isolation of the launched copy, sandbox fence) must be able to fail.
subprocess.run([sys.executable, "-I", str(root / "tools" / "test-eye-dump-audit-guard.py")], cwd=root, check=True)
# The startup smoke runs a re-identified temp copy and compares the real stores; its protections must be able to fail too.
subprocess.run([sys.executable, "-I", str(root / "tools" / "test-native-startup-guard.py")], cwd=root, check=True)
# G9: literal fonts, colours and radii outside the tokens. Report mode until the token sweeps land; the self-test proves --strict can fail.
subprocess.run([sys.executable, str(root / "tools" / "check-tokens.py")], cwd=root, check=True)
subprocess.run([sys.executable, str(root / "tools" / "check-tokens.py"), "--self-test"], cwd=root, check=True)
# D-TEXT: chrome tooltips are app-owned (20 pt); a direct system `toolTip` write fails this gate, and the self-test proves it can.
subprocess.run([sys.executable, str(root / "tools" / "check-tooltips.py")], cwd=root, check=True)
subprocess.run([sys.executable, str(root / "tools" / "check-tooltips.py"), "--self-test"], cwd=root, check=True)
# G6: decorative glyphs and emoji in string literals. Sources are clean, so it runs strict; the self-test proves --strict can fail.
subprocess.run([sys.executable, str(root / "tools" / "check-glyphs.py"), "--strict"], cwd=root, check=True)
subprocess.run([sys.executable, str(root / "tools" / "check-glyphs.py"), "--self-test"], cwd=root, check=True)
# G7: the screenshot-harness output checker. The self-test proves each assertion can fail; then every committed evidence set is checked.
subprocess.run([sys.executable, str(root / "tools" / "check-eye-dump.py"), "--self-test"], cwd=root, check=True)
for evidence in sorted((root / "docs/design/evidence/impl-2026-10-09").glob("m*")):
    subprocess.run([sys.executable, str(root / "tools" / "check-eye-dump.py"), str(evidence)], cwd=root, check=True)
# G11: the skip-budget gate's own self-test; the log check runs at the end, over the captured suite output.
subprocess.run([sys.executable, str(root / "tools" / "check-skip-budget.py"), "--self-test"], cwd=root, check=True)
# OSN-072: the migration on a synthetic old store (58 documents, 2 destinations); never the owner's data.
subprocess.run([sys.executable, str(root / "tools" / "migration-dry-run.py")], cwd=root, check=True)
snapshot = Path(tempfile.mkdtemp(prefix="test-snapshot.", dir=build))

def current_inputs():
    return sorted((root / "Sources").glob("*.swift")) + sorted((root / "tests").glob("*.swift"))

inputs = current_inputs()
for attempt in range(3):
    contents = {path: path.read_bytes() for path in inputs}
    if all(path.read_bytes() == data for path, data in contents.items()):
        break
else:
    raise SystemExit("Sources changed while taking the snapshot; rerun after edits finish.")
for path, data in contents.items():
    (snapshot / path.name).write_bytes(data)
manifest = {str(path.relative_to(root)): hashlib.sha256(data).hexdigest() for path, data in contents.items()}
(snapshot / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

def suite(name, sources, test, define=None, arguments=(), environment=None):
    # Every suite compiles the design tokens, so a file that adopts them never breaks its own suite.
    sources = [*sources, "DesignTokens.swift"] if "DesignTokens.swift" not in sources else sources
    for needed in [*sources, test]:
        if not (snapshot / needed).exists():
            raise SystemExit(f"FAIL {name}: {needed} is missing from the source snapshot")
    binary = snapshot / name
    command = ["xcrun", "swiftc", "-swift-version", "5", "-target", options.arch + "-apple-macosx26.0"]
    if define:
        command += ["-D", define]
    command += [str(snapshot / source) for source in sources]
    command += [str(snapshot / test), "-o", str(binary)]
    subprocess.run(command, cwd=root, check=True)
    env = None
    if environment:
        env = dict(os.environ)
        for key, value in environment.items():
            env[key] = tempfile.mkdtemp(prefix="home-", dir=snapshot) if value == "@temp-home" else value
    run = subprocess.run([str(binary), *arguments], cwd=root, env=env, capture_output=True, text=True)
    SUITE_OUTPUT.append(run.stdout + run.stderr)
    print(run.stdout + run.stderr, end="", flush=True)
    run.check_returncode()
    return "PASS", name

# Subsets from tools/fetch-fontawesome.sh are exercised when they have been built.
fonts = root / "build/fonts"
font_environment = os.environ | {"OPENSNAP_FA_FONT_DIR": str(fonts)} if any(fonts.glob("*-subset.ttf")) else None

# The icon layer (Pro glyph, embedded Free vector, SF Symbol) that every view drawing a chrome glyph compiles with.
ICONS = ["FontAwesomeIcons.swift", "ChromeIcons.swift", "FontAwesomeFree.swift", "SVGPath.swift"]

suites = [
    ("original-action-button-tests", ["OriginalActionButton.swift"], "OriginalActionButtonTests.swift", "ORIGINAL_ACTION_BUTTON_TESTS", ()),
    ("original-capture-timing-tests", ["OriginalCaptureTiming.swift"], "OriginalCaptureTimingTests.swift", "ORIGINAL_CAPTURE_TIMING_TESTS", ()),
    ("original-capture-picker-tests", ["OriginalCaptureMagnifier.swift", "OriginalCapturePicker.swift", "TestDefaults.swift"], "OriginalCapturePickerTests.swift", "ORIGINAL_CAPTURE_PICKER_TESTS", ()),
    ("original-capture-countdown-tests", ["OriginalCaptureTiming.swift", "OriginalCaptureCountdown.swift"], "OriginalCaptureCountdownTests.swift", "ORIGINAL_CAPTURE_COUNTDOWN_TESTS", ()),
    ("original-hint-messages-tests", ["SVGPath.swift", "DocumentModel.swift", "OriginalHintMessages.swift"], "OriginalHintMessagesTests.swift", "ORIGINAL_HINT_MESSAGES_TESTS", ()),
    ("original-help-bevel-tests", ["OriginalHelpBevel.swift"], "OriginalHelpBevelTests.swift", "ORIGINAL_HELP_BEVEL_TESTS", ()),
    ("window-zoom-tests", ["WindowZoom.swift"], "WindowZoomTests.swift", "WINDOW_ZOOM_TESTS", ()),
    ("text-style-form-tests", ["TextStyleForm.swift"], "TextStyleFormTests.swift", "TEXT_STYLE_FORM_TESTS", ()),
    ("general-preferences-form-tests", ["SVGPath.swift", "StrokeFitting.swift", "GeneralPreferencesForm.swift"], "GeneralPreferencesFormTests.swift", "GENERAL_PREFERENCES_FORM_TESTS", ()),
    ("original-general-preferences-tests", ["SVGPath.swift", "StrokeFitting.swift", "DocumentModel.swift", "GeneralPreferencesForm.swift", "OriginalGeneralPreferences.swift", "TestDefaults.swift"], "OriginalGeneralPreferencesTests.swift", "ORIGINAL_GENERAL_PREFERENCES_TESTS", ()),
    ("resize-presets-tests", ["ResizePresets.swift", "TestDefaults.swift"], "ResizePresetsTests.swift", "RESIZE_PRESETS_TESTS", ()),
    ("window-sizing-tests", ["WindowSizing.swift"], "WindowSizingTests.swift", "WINDOW_SIZING_TESTS", ()),
    ("canvas-navigator-tests", ["CanvasNavigator.swift"], "CanvasNavigatorTests.swift", "CANVAS_NAVIGATOR_TESTS", ()),
    ("canvas-border-tests", ["WindowSizing.swift", "CanvasBorderView.swift"], "CanvasBorderTests.swift", "CANVAS_BORDER_TESTS", ()),
    ("resize-panel-tests", ["ResizePresets.swift", "ResizePanel.swift"], "ResizePanelTests.swift", "RESIZE_PANEL_TESTS", ()),
    ("export-accessory-tests", ["ExportAccessory.swift"], "ExportAccessoryTests.swift", "EXPORT_ACCESSORY_TESTS", ()),
    ("image-export-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "ImageExport.swift"], "ImageExportTests.swift", "IMAGE_EXPORT_TESTS", ()),
    ("vector-geometry-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift"], "VectorGeometryTests.swift", "VECTOR_GEOMETRY_TESTS", ()),
    ("stroke-fitting-tests", ["SVGPath.swift", "StrokeFitting.swift"], "StrokeFittingTests.swift", "STROKE_FITTING_TESTS", ()),
    ("canvas-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift"], "CanvasTests.swift", "CANVAS_TESTS", ()),
    ("history-store-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "OpenSnapFile.swift", "HistoryStore.swift"], "HistoryStoreTests.swift", "HISTORY_STORE_TESTS", ()),
    ("history-browser-tests", ["HistoryBrowser.swift", "TestDefaults.swift", *ICONS], "HistoryBrowserTests.swift", "HISTORY_BROWSER_TESTS", ()),
    ("history-remote-deletion-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift", "HistoryRemoteDeletion.swift", *ICONS], "HistoryRemoteDeletionTests.swift", None, ("--test",)),
    ("publishing-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift", *ICONS], "PublishingTests.swift", None, ("--test",)),
    ("publishing-shutdown-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift", *ICONS], "PublishingShutdownTests.swift", None, ("--test",)),
    ("publishing-destinations-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift", *ICONS], "PublishingDestinationsTests.swift", None, ("--test",)),
    ("hotkey-tests", ["GlobalHotkeys.swift", "TestDefaults.swift"], "GlobalHotkeysTests.swift", "GLOBAL_HOTKEY_TESTS", ()),
    ("svg-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "SVGExport.swift"], "SVGExportTests.swift", "SVG_EXPORT_TESTS", ()),
    ("opensnap-file-tests", ["SVGPath.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "OpenSnapFile.swift"], "OpenSnapFileTests.swift", "OPENSNAP_FILE_TESTS", ()),
    ("migration-tests", ["SVGPath.swift", "LegacyReader.swift", "DocumentModel.swift", "VectorGeometry.swift", "StrokeFitting.swift", "ImageExport.swift", "Canvas.swift", "OpenSnapFile.swift", "HistoryStore.swift", "Migration.swift"], "MigrationTests.swift", "MIGRATION_TESTS", (), {"CFFIXED_USER_HOME": "@temp-home"}),
    ("capture-tests", ["OriginalCaptureTiming.swift", "OriginalCaptureMagnifier.swift", "OriginalCapturePicker.swift", "OriginalCaptureCountdown.swift", "OriginalCaptureFlash.swift", "Capture.swift"], "CaptureTests.swift", "CAPTURE_TESTS", ()),
    ("photo-browser-tests", ["PhotoBrowser.swift"], "PhotoBrowserTests.swift", None, ()),
    ("typography-tests", [], "TypographyTests.swift", "TYPOGRAPHY_TESTS", ()),
    ("palette-tests", [], "PaletteTests.swift", "PALETTE_TESTS", ()),
    ("status-item-tests", ["StatusItemSupport.swift"], "StatusItemSupportTests.swift", "STATUS_ITEM_TESTS", ()),
    ("about-window-tests", ["AboutWindow.swift"], "AboutWindowTests.swift", "ABOUT_WINDOW_TESTS", ()),
    ("metrics-tests", [], "MetricsTests.swift", "METRICS_TESTS", ()),
    ("app-tooltip-tests", ["AppToolTip.swift"], "AppToolTipTests.swift", "APP_TOOLTIP_TESTS", ()),
    # G4: the font-floor walker over every surface whose sources compile in isolation. The full main window joins via app-safety.
    ("view-tree-audit-tests", ["Publishing.swift", "PublishingS3.swift", "PublishingDestinations.swift", "PublishingDestinationsView.swift",
                               "AboutWindow.swift", "HistoryBrowser.swift", "ResizePresets.swift", "ResizePanel.swift", *ICONS, "StrokeFitting.swift",
                               "GeneralPreferencesForm.swift", "TextStyleForm.swift", "ExportAccessory.swift", "TestDefaults.swift", "ViewTreeAudit.swift"],
     "ViewTreeAuditTests.swift", "VIEW_TREE_AUDIT_TESTS", ()),
]
# These need the Modern chrome sources; a missing file fails the suite. Only the Font Awesome glyph branch inside them
# is licence-gated, and it prints "SKIPPED (FA not bundled)" when the Pro subsets are absent.
modern_suites = [
    ("fontawesome-icons-tests", [*ICONS], "FontAwesomeIconsTests.swift", "FONTAWESOME_ICONS_TESTS", (), font_environment),
    ("menu-symbols-tests", [*ICONS, "MenuSymbols.swift"], "MenuSymbolsTests.swift", "MENU_SYMBOLS_TESTS", ()),
    ("icon-coverage-tests", [*ICONS], "IconCoverageTests.swift", "ICON_COVERAGE_TESTS", ()),
    ("glass-chrome-tests", ["OriginalActionButton.swift", *ICONS, "BezelDrawingControls.swift", "DocumentModel.swift", "GlassChrome.swift", "ModernEditorChrome.swift", "AppToolTip.swift"], "GlassChromeTests.swift", "GLASS_CHROME_TESTS", ()),
]
with ThreadPoolExecutor(max_workers=len(suites) + len(modern_suites)) as executor:
    futures = [executor.submit(suite, *args) for args in suites]
    futures += [executor.submit(suite, *args) for args in modern_suites]
    failures = []
    for future in futures:
        try:
            print(*future.result(), flush=True)
        except Exception as error:
            failures.append(str(error))
            print("FAIL", error, flush=True)
if failures:
    check_real_store(real_store_before)
    raise SystemExit(1)
print("== build + check-no-original", flush=True)
subprocess.run(["sh", str(root / "tools" / "build.sh")], cwd=root, check=True, stdout=subprocess.DEVNULL)
subprocess.run([sys.executable, str(root / "tools" / "check-no-original.py"), str(build / "OpenSnap.app")], cwd=root, check=True)
# G11: a SKIP in any suite output needs a reason of "macOS < N" or "FA not bundled".
skips = subprocess.run([sys.executable, str(root / "tools" / "check-skip-budget.py"), "-"], input="".join(SUITE_OUTPUT), text=True)
if skips.returncode:
    raise SystemExit("FAIL skip-budget: an unexplained SKIP in the suite output")
print("== app-safety", flush=True)
subprocess.run([str(root / "tools" / "test-app-safety.sh"), "--arch", options.arch], cwd=root, check=True)
check_real_store(real_store_before)
if current_inputs() != inputs or not all(path.read_bytes() == data for path, data in contents.items()):
    raise SystemExit("Sources changed during verification; rerun before treating this result as current.")
print("All suites passed on", options.arch, "with no source drift. Evidence:", snapshot, flush=True)
