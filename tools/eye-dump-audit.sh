#!/bin/sh
# The only screenshot path. Visual audit evidence run: launches an ISOLATED COPY of the built app (throwaway bundle id,
# throwaway home, support folder and evidence folder) once per appearance, icon mode and surface group, and writes PNGs +
# view-tree metrics + AX dumps + a manifest. It captures only the app's own windows (CGWindowList by window number, else
# cacheDisplay); it never captures the screen. build/OpenSnap.app is never run in place, so the owner's defaults domain,
# support folder and Keychain are never reachable; the real stores are hashed before and after and any change fails the run.
#
#   sh tools/eye-dump-audit.sh OUTDIR [--groups main,more,overlays,sizes,fullscreen,states] [--appearances light,dark]
#                                     [--icons sf|fa|both] [--sizes 980xmin,1024x740,1280x800,1440x900,full]
#
# Other groups: pairs (the S01/S02/S03/S12 captures that have a pre-rail twin), states (rail-removal state captures S30-S37: popovers, Frame at 980/1280, large shot, centring, selection, PNG|JPG),
# layout (width budget), delta (a short regression subset). sizes runs the populated (S11M) and empty (S11E) matrix. --surfaces IDS runs exactly those surface ids.
# --app APP uses a pre-built bundle instead of build/OpenSnap.app; --sha / --suffix tag the captures; --guard-home DIR points
# the store guard at another home (tests only; recorded in safety.txt); --no-wait-gui skips waiting for other agents' GUI tests.
#
# OUTDIR gets raw-<icons>/ (per-capture files), manifest.json, safety.txt (hashes before/after) and run.log.
# Exit status is non-zero when any watched real store changed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:?usage: eye-dump-audit.sh OUTDIR [--groups ...] [--appearances ...] [--icons sf|fa|both] [--sizes ...]}
shift
GROUPS_WANTED="main,more,overlays,sizes,fullscreen"
APPEARANCES="light,dark"
ICONS="sf"
SIZES=""
APP_SRC=""; SOURCE_SHA=""; SUFFIX=""; CUSTOM=""; GUARD_HOME=""; WAIT_GUI=yes; GROUPS_GIVEN=no
while [ "$#" -gt 0 ]; do
    case "$1" in
        --groups) GROUPS_WANTED=$2; GROUPS_GIVEN=yes; shift 2 ;;
        --appearances) APPEARANCES=$2; shift 2 ;;
        --icons) ICONS=$2; shift 2 ;;
        --sizes) SIZES=$2; shift 2 ;;
        --surfaces) CUSTOM=$2; shift 2 ;;
        --app) APP_SRC=$2; shift 2 ;;
        --sha) SOURCE_SHA=$2; shift 2 ;;
        --suffix) SUFFIX=$2; shift 2 ;;
        --guard-home) GUARD_HOME=$2; shift 2 ;;
        --no-wait-gui) WAIT_GUI=no; shift ;;
        *) echo "unknown argument $1" >&2; exit 2 ;;
    esac
done
case "$ICONS" in sf) ICON_MODES="sf" ;; fa) ICON_MODES="fa" ;; both) ICON_MODES="sf fa" ;; *) echo "--icons must be sf, fa or both" >&2; exit 2 ;; esac
if [ -n "$SIZES" ] && [ "$GROUPS_GIVEN" = yes ]; then
    case ",$GROUPS_WANTED," in *,sizes,*) ;; *) GROUPS_WANTED="$GROUPS_WANTED,sizes" ;; esac
fi
# Identity of the throwaway defaults domain, validated BEFORE any trap or cleanup exists: a cleanup that runs on a bad id
# is exactly how a real defaults domain gets deleted. `defaults` is injectable so tests never reach the real preferences.
REAL_ID="com.shoemoney.opensnap"
THROWAWAY_ID="$REAL_ID.eyedump-$$"
DEFAULTS=${EYE_DUMP_AUDIT_DEFAULTS:-/usr/bin/defaults}

# Only <real id>.eyedump-<digits> passes, so neither real defaults domain (the current id or the retired one) can ever match.
valid_throwaway_id() {
    case "$1" in
        "$REAL_ID") return 1 ;;
        com.shoemoney.opensnap.eyedump-*[!0-9]*|com.shoemoney.opensnap.eyedump-) return 1 ;;
        com.shoemoney.opensnap.eyedump-[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}
drop_throwaway_defaults() {
    valid_throwaway_id "$THROWAWAY_ID" || { echo "refusing to drop defaults for unexpected id: $THROWAWAY_ID" >&2; return 1; } # protection:drop
    "$DEFAULTS" delete "$THROWAWAY_ID" >/dev/null 2>&1 || true
    plist="$HOME/Library/Preferences/$THROWAWAY_ID.plist"
    base=$(basename "$plist"); stem=${base%.plist}
    if [ "$stem.plist" = "$base" ] && valid_throwaway_id "$stem"; then rm -f "$plist"; fi # protection:rm
}
valid_throwaway_id "$THROWAWAY_ID" || { echo "refusing: throwaway id '$THROWAWAY_ID' is not com.shoemoney.opensnap.eyedump-<pid>" >&2; exit 2; } # protection:top
mkdir -p "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd)

if [ -z "$APP_SRC" ]; then
    APP_SRC="$ROOT/build/OpenSnap.app"
    NEWEST=$(ls -t "$ROOT"/Sources/*.swift | head -1)
    if [ ! -x "$APP_SRC/Contents/MacOS/OpenSnap" ] || [ "$NEWEST" -nt "$APP_SRC/Contents/MacOS/OpenSnap" ]; then
        sh "$ROOT/tools/build.sh" >/dev/null
    fi
fi
if [ -z "$SOURCE_SHA" ]; then
    SOURCE_SHA=$(git -C "$ROOT" rev-parse --short HEAD)
    [ -z "$(git -C "$ROOT" status --porcelain -- Sources 2>/dev/null)" ] || SOURCE_SHA="$SOURCE_SHA-dirty"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/eye-dump-audit.XXXXXX")
# EXIT safety net only: removes $TMP and re-runs the validated drop (a no-op after the explicit drop below). The explicit drop
# runs BEFORE the final guard compare, so any damage cleanup could do to a real store is visible to the compare, never after it.
DROPPED=no
cleanup() {
    [ "$DROPPED" = yes ] || drop_throwaway_defaults || true
    rm -rf "$TMP"
}
trap cleanup EXIT
APP_NAME=$(basename "$APP_SRC")
APP="$TMP/$APP_NAME"
EXE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_SRC/Contents/Info.plist")
GUARD="python3 -I $ROOT/tools/real_store_guard.py"
[ -z "$GUARD_HOME" ] || GUARD="$GUARD --home $GUARD_HOME"
REAL_HOME=${GUARD_HOME:-$HOME}

$GUARD snapshot "$TMP/guard-before.json" > "$TMP/guard-before.txt"
{
    echo "sourceSha        $SOURCE_SHA"
    echo "real stores      before: $(cat "$TMP/guard-before.txt")"
    echo "guard home       $REAL_HOME"
    echo "bundle id        $THROWAWAY_ID (real id $REAL_ID is never launched)"
    echo "app copy         $APP (copied from $APP_SRC; the source bundle is never executed)"
    echo "isolation        env -i; HOME and CFFIXED_USER_HOME, TMPDIR, OPENSNAP_APP_SUPPORT, OPENSNAP_EVIDENCE_DIR all under $TMP; OPENSNAP_FIXTURE unset"
    echo "destinations     none exist in the throwaway support folder; with OPENSNAP_APP_SUPPORT set the app keeps secrets in memory (no Keychain item is read or written) and the S19/S21 flows stub the uploader"
} | tee "$OUT/safety.txt"

# Kernel-enforced fences for the child, when sandbox-exec exists: no network at all, and no access to the real stores,
# AWS/SSH config, Keychain files or the original-art folder. A violation shows up as an error in run.log, not as a silent read.
SANDBOX=""
PROFILE="$TMP/audit.sb"
if [ -x /usr/bin/sandbox-exec ] && [ "${EYE_DUMP_AUDIT_NO_SANDBOX:-0}" != 1 ]; then
    {
        echo "(version 1)"
        echo "(allow default)"
        echo "(deny network* (remote ip))"
        echo "(deny network-outbound (remote tcp) (remote udp))"
        {
            $GUARD folders
            echo "$REAL_HOME/.aws"; echo "$REAL_HOME/.ssh"; echo "$REAL_HOME/Library/Keychains"; echo "$ROOT/original"
        } | while IFS= read -r fenced; do
            # The kernel matches resolved paths (/var is /private/var), so fence the physical path as well as the given one.
            physical=$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$fenced")
            echo "(deny file-read* file-write* (subpath \"$fenced\") (subpath \"$physical\"))"
        done
    } > "$PROFILE"
    SANDBOX="/usr/bin/sandbox-exec -f $PROFILE"
    echo "sandbox          sandbox-exec: network denied; real stores, ~/.aws, ~/.ssh, Keychains and the original-art folder unreadable" | tee -a "$OUT/safety.txt"
else
    echo "sandbox          NOT USED (sandbox-exec unavailable or disabled); only the before/after hash guard protects the real stores" | tee -a "$OUT/safety.txt"
fi

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
    [ "$WAIT_GUI" = yes ] || return 0
    waited=0
    while other_gui_busy; do
        if [ "$waited" -ge 900 ]; then echo "giving up: another agent's GUI test run (test.py / app-safety / native-startup) is still going after 15 minutes; rerun this later, or pass --no-wait-gui to run alongside it" >&2; return 1; fi
        echo "waiting for another agent's GUI test run (test.py / app-safety / native-startup) to finish before launching the app ($waited s so far, gives up at 900 s)" >&2
        sleep 45; waited=$((waited + 45))
    done
}

# One throwaway copy of the app per icon mode. sf: the Font Awesome subset fonts are removed from the COPY so the chrome
# can only resolve SF Symbols. fa: needs the subsets in the source bundle; without them the mode is reported unavailable.
prepare_copy() {
    mode=$1
    rm -rf "$APP"
    cp -R "$APP_SRC" "$APP"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $THROWAWAY_ID" "$APP/Contents/Info.plist"
    if [ "$mode" = sf ]; then rm -f "$APP/Contents/Resources"/FontAwesome7Pro-*-subset.ttf; fi
    codesign --force --sign - "$APP" >/dev/null 2>&1
}
have_fa_fonts() { ls "$APP_SRC/Contents/Resources"/FontAwesome7Pro-*-subset.ttf >/dev/null 2>&1; }

run_one() {
    mode=$1; appearance=$2; surfaces=$3; label=$4
    raw="$OUT/raw-$mode"
    wait_for_other_gui || return 1
    support="$TMP/support-$label-$appearance-$mode"
    mkdir -p "$support" "$TMP/home" "$TMP/tmp"
    echo "== $label ($appearance, icons $mode): $surfaces"
    (
        # shellcheck disable=SC2086
        env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$TMP/home" CFFIXED_USER_HOME="$TMP/home" TMPDIR="$TMP/tmp" \
            OPENSNAP_APP_SUPPORT="$support" OPENSNAP_EVIDENCE_DIR="$TMP/evidence" \
            AUDIT_SOURCE_SHA="$SOURCE_SHA" AUDIT_STEM_SUFFIX="$SUFFIX" \
            $SANDBOX "$APP/Contents/MacOS/$EXE" --eye-dump-audit "$raw" --audit-appearance "$appearance" --audit-icons "$mode" \
            --audit-surfaces "$surfaces" --audit-sizes "$SIZES" >>"$OUT/run.log" 2>&1
    ) &
    child=$!
    ( sleep 420; kill "$child" >/dev/null 2>&1 || true ) 2>/dev/null &
    watchdog=$!
    wait "$child" || echo "   child exited non-zero ($label/$appearance/$mode)" >&2
    pkill -P "$watchdog" >/dev/null 2>&1 || true
    kill "$watchdog" >/dev/null 2>&1 || true
    wait "$watchdog" 2>/dev/null || true
    rm -rf "$support"
    drop_throwaway_defaults
}

for mode in $ICON_MODES; do
    mkdir -p "$OUT/raw-$mode"
    if [ "$mode" = fa ] && ! have_fa_fonts; then
        printf '{"requested":"fa","effective":"none","reason":"FA unavailable: no FontAwesome7Pro-*-subset.ttf in %s (build with OPENSNAP_FETCH_FONTAWESOME=1 and your own token)"}\n' "$APP_SRC" > "$OUT/raw-fa/icon-mode-unavailable.json"
        echo "icons fa: FA unavailable, SKIPPED (FA not bundled)" | tee -a "$OUT/safety.txt"
        continue
    fi
    prepare_copy "$mode"
    for appearance in $(echo "$APPEARANCES" | tr ',' ' '); do
        if [ -n "$CUSTOM" ]; then run_one "$mode" "$appearance" "$CUSTOM" custom; continue; fi
        for group in $(echo "$GROUPS_WANTED" | tr ',' ' '); do
            case "$group" in
                main) run_one "$mode" "$appearance" "ENV,S01,S11,S02,S03,S04,S05,S06,S07,S08,S09,S10" main ;;
                more) run_one "$mode" "$appearance" "S12,S16,S17,S18,S19,S20,S21,S22,S23,S24,S25,S26,S28,S29" more ;;
                overlays) run_one "$mode" "$appearance" "S13,S14,S15" overlays ;;
                sizes) run_one "$mode" "$appearance" "S11M,S11E" sizes ;;
                fullscreen) run_one "$mode" "$appearance" "S11F,S11FP" fullscreen ;;
                pairs) run_one "$mode" "$appearance" "ENV,S01,S02,S03,S12" pairs ;;
                states) run_one "$mode" "$appearance" "S30,S31,S32,S33,S34,S35,S36,S37" states ;;
                layout) run_one "$mode" "$appearance" "LAYOUT" layout ;;
                delta) run_one "$mode" "$appearance" "ENV,S01,S02,S03,S05,S07,S09,S11,S12,S14,S17,S24,S25,S29" delta ;;
                *) echo "unknown group $group" >&2 ;;
            esac
        done
    done
done

python3 -I "$ROOT/tools/eye-dump-audit-manifest.py" "$OUT" --sha "$SOURCE_SHA" --bundle-id "$THROWAWAY_ID" >/dev/null || echo "manifest could not be written" >&2

# All defaults cleanup is finished here, before the compare, so the compare observes whatever cleanup did.
drop_throwaway_defaults
DROPPED=yes
echo "cleanup          throwaway defaults ($THROWAWAY_ID) dropped BEFORE the final compare; the compare below would show any damage cleanup did" | tee -a "$OUT/safety.txt"
status=0
$GUARD compare "$TMP/guard-before.json" > "$TMP/guard-after.txt" || status=1
{
    echo "real stores      after:  $(sed -n '1p' "$TMP/guard-after.txt")"
    sed -n '2,$p' "$TMP/guard-after.txt"
} | tee -a "$OUT/safety.txt"
exit "$status"
