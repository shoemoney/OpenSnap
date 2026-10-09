#!/bin/sh
# Visual audit evidence run. Launches an ISOLATED COPY of the built app (throwaway bundle id, throwaway home,
# throwaway support folder), once per appearance and surface group, and writes PNGs + metrics + AX dumps.
# Captures only the app's own windows; never the screen. Proves the real stores were untouched.
#
#   sh tools/eye-dump-audit.sh OUTDIR [--groups main,more,overlays,welcome,fullscreen] [--appearances light,dark]
#
# OUTDIR gets raw/ (per-capture files), safety.txt (hashes before/after), run.log.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:?usage: eye-dump-audit.sh OUTDIR [--groups ...] [--appearances ...]}
shift
GROUPS_WANTED="main,more,overlays,welcome,fullscreen"
APPEARANCES="light,dark"
APP_SRC=""; SOURCE_SHA=""; SUFFIX=""; CUSTOM=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --groups) GROUPS_WANTED=$2; shift 2 ;;
        --appearances) APPEARANCES=$2; shift 2 ;;
        --surfaces) CUSTOM=$2; shift 2 ;;      # one custom run with exactly these surface ids
        --app) APP_SRC=$2; shift 2 ;;          # a pre-built OpenSkitch.app to copy (default: build/OpenSkitch.app)
        --sha) SOURCE_SHA=$2; shift 2 ;;       # recorded as sourceSha in every capture
        --suffix) SUFFIX=$2; shift 2 ;;        # appended to every file stem, e.g. @4b2ae0f
        *) echo "unknown argument $1" >&2; exit 2 ;;
    esac
done
mkdir -p "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd)
RAW="$OUT/raw"; mkdir -p "$RAW"

if [ -z "$APP_SRC" ]; then
    APP_SRC="$ROOT/build/OpenSkitch.app"
    NEWEST=$(ls -t "$ROOT"/Sources/*.swift | head -1)
    if [ ! -x "$APP_SRC/Contents/MacOS/OpenSkitch" ] || [ "$NEWEST" -nt "$APP_SRC/Contents/MacOS/OpenSkitch" ]; then
        sh "$ROOT/tools/build.sh" >/dev/null
    fi
fi
[ -n "$SOURCE_SHA" ] || SOURCE_SHA=$(git -C "$ROOT" rev-parse --short HEAD)

REAL_ID="com.shoemoney.skitch-redux"
THROWAWAY_ID="$REAL_ID.eyedump-$$"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/eye-dump-audit.XXXXXX")
APP="$TMP/OpenSkitch.app"
REAL_SUPPORT="$HOME/Library/Application Support/SkitchRedux"

store_hash() {
    if [ -d "$REAL_SUPPORT" ]; then find "$REAL_SUPPORT" -type f -exec stat -f '%N %z %m' {} \; 2>/dev/null | sort | shasum | cut -d' ' -f1
    else echo "absent"; fi
}
defaults_hash() { defaults export "$REAL_ID" - 2>/dev/null | shasum | cut -d' ' -f1; }

cleanup() {
    defaults delete "$THROWAWAY_ID" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$THROWAWAY_ID.plist"
    rm -rf "$TMP"
}
trap cleanup EXIT

BEFORE_STORE=$(store_hash); BEFORE_DEFAULTS=$(defaults_hash)
{
    echo "before: SkitchRedux files hash   $BEFORE_STORE"
    echo "before: $REAL_ID defaults hash   $BEFORE_DEFAULTS"
} | tee "$OUT/safety.txt"

cp -R "$APP_SRC" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $THROWAWAY_ID" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1
mkdir -p "$TMP/home"

# Other agents' GUI test runs. Ignores shells whose command line merely mentions the names (including this script's own parent).
other_gui_busy() {
    for pid in $(pgrep -f 'test-app-safety|tools/test.py|test-native-startup|AppSafetyTests' 2>/dev/null); do
        cmd=$(ps -o command= -p "$pid" 2>/dev/null || true)
        case "$cmd" in
            *eye-dump-audit*|*"zsh -c"*|*"bash -c"*|*pgrep*) ;;
            "") ;;
            *) return 0 ;;
        esac
    done
    return 1
}
wait_for_other_gui() {
    waited=0
    while other_gui_busy; do
        if [ "$waited" -ge 900 ]; then echo "other GUI tests still running after 15 minutes; giving up" >&2; return 1; fi
        echo "waiting for another agent's GUI tests ($waited s)" >&2
        sleep 45; waited=$((waited + 45))
    done
}

run_one() {
    appearance=$1; surfaces=$2; welcome=$3; label=$4
    wait_for_other_gui || return 1
    support="$TMP/support-$label-$appearance"
    mkdir -p "$support"
    [ "$welcome" = yes ] || : > "$support/FirstLaunchDone"
    echo "== $label ($appearance): $surfaces"
    (
        env -u SKITCH_FIXTURE AUDIT_SOURCE_SHA="$SOURCE_SHA" AUDIT_STEM_SUFFIX="$SUFFIX" CFFIXED_USER_HOME="$TMP/home" SKITCH_APP_SUPPORT="$support" SKITCH_APPEARANCE=modern \
            "$APP/Contents/MacOS/OpenSkitch" --eye-dump-audit "$RAW" --audit-appearance "$appearance" --audit-surfaces "$surfaces" >>"$OUT/run.log" 2>&1
    ) &
    child=$!
    ( sleep 420; kill "$child" >/dev/null 2>&1 || true ) 2>/dev/null &
    watchdog=$!
    wait "$child" || echo "   child exited non-zero ($label/$appearance)" >&2
    kill "$watchdog" >/dev/null 2>&1 || true
    wait "$watchdog" 2>/dev/null || true
    rm -rf "$support"
}

for appearance in $(echo "$APPEARANCES" | tr ',' ' '); do
    if [ -n "$CUSTOM" ]; then run_one "$appearance" "$CUSTOM" no custom; continue; fi
    for group in $(echo "$GROUPS_WANTED" | tr ',' ' '); do
        case "$group" in
            main) run_one "$appearance" "ENV,S01,S11,S02,S03,S04,S05,S06,S07,S08,S09,S10" no main ;;
            more) run_one "$appearance" "S12,S16,S17,S18,S19,S20,S21,S22,S23,S24,S25,S26,S28,S29" no more ;;
            overlays) run_one "$appearance" "S13,S14,S15" no overlays ;;
            welcome) run_one "$appearance" "S27" yes welcome ;;
            fullscreen) run_one "$appearance" "S11F" no fullscreen ;;
            layout) run_one "$appearance" "LAYOUT" no layout ;;
            proto) run_one "$appearance" "PROTO" no proto ;;
            delta) run_one "$appearance" "ENV,S01,S02,S03,S05,S07,S09,S11,S12,S14,S17,S24,S25,S29" no delta ;;
        esac
    done
done

AFTER_STORE=$(store_hash); AFTER_DEFAULTS=$(defaults_hash)
{
    echo "after:  SkitchRedux files hash   $AFTER_STORE"
    echo "after:  $REAL_ID defaults hash   $AFTER_DEFAULTS"
    [ "$BEFORE_STORE" = "$AFTER_STORE" ] && echo "RESULT store unchanged" || echo "RESULT STORE CHANGED"
    [ "$BEFORE_DEFAULTS" = "$AFTER_DEFAULTS" ] && echo "RESULT defaults unchanged" || echo "RESULT DEFAULTS CHANGED"
} | tee -a "$OUT/safety.txt"
