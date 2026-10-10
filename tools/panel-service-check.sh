#!/bin/sh
# MANUAL live check for F-J5-005 (not part of tools/test.py). Opens one real system Open panel from the throwaway probe app
# (docs/design/e2e/panel-probe/probe.swift) under the same `env -i` isolation as tools/e2e-session.sh and reports the panel service's peak RSS.
#
#   sh tools/panel-service-check.sh             normalized CFFIXED_USER_HOME: expect a peak under 300 MB
#   sh tools/panel-service-check.sh --reproduce non-normalized ("//") CFFIXED_USER_HOME: on macOS 27.2 beta the service grows ~1.2 GB/s until killed
#
# The panel service inherits CFFIXED_USER_HOME from the app that opens the panel; a value with "//", "/./" or "/../" sends it into an endless
# CFURL parent walk (_CFURLIsProtectedDirectory). Nothing in OpenSnap is involved: the probe shows the same. SAFETY: a watchdog SIGKILLs any
# openAndSavePanelService above 2 GB (checked every 0.4 s), the run stops when free memory is under 30 %, and the probe never chooses a file.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODE=normalized
case "${1:-}" in --reproduce) MODE=reproduce ;; "") ;; *) echo "usage: $0 [--reproduce]" >&2; exit 2 ;; esac
free=$(memory_pressure | sed -n 's/.*free percentage: \([0-9]*\)%.*/\1/p')
[ "${free:-0}" -ge 30 ] || { echo "free memory ${free:-?}% is under 30%; not running" >&2; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/panel-service-check.XXXXXX")
T=$(CDPATH= cd -- "$T" && pwd -P)
ID="com.shoemoney.opensnap.e2e-panelcheck$$"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
WATCHDOG=""
cleanup() {
    [ -z "$WATCHDOG" ] || { kill "$WATCHDOG" 2>/dev/null; wait "$WATCHDOG" 2>/dev/null; } || true
    "$LSREGISTER" -u "$T/Probe.app" >/dev/null 2>&1 || true
    /usr/bin/defaults delete "$ID" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$ID.plist"
    rm -rf "$T"
}
trap cleanup EXIT

xcrun swiftc -O -swift-version 5 -sdk "$(xcrun --show-sdk-path)" "$ROOT/docs/design/e2e/panel-probe/probe.swift" -o "$T/Probe" 2>/dev/null
mkdir -p "$T/Probe.app/Contents/MacOS" "$T/home" "$T/tmp"
cp "$T/Probe" "$T/Probe.app/Contents/MacOS/OpenSnap"
cp "$ROOT/Info.plist" "$T/Probe.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" "$T/Probe.app/Contents/Info.plist"
codesign --force --sign - "$T/Probe.app" >/dev/null 2>&1

CFHOME="$T/home"
[ "$MODE" = normalized ] || CFHOME="$T//home"
KILLED="$T/killed"
( while :; do
    /bin/ps -axo pid=,rss=,comm= | awk '/com\.apple\.appkit\.xpc\.openAndSavePanelService$/ && $2 > 2097152 { print $1 }' | while read -r pid; do
        kill -9 "$pid" 2>/dev/null && echo "$pid" >> "$KILLED"
    done
    sleep 0.4
  done ) &
WATCHDOG=$!

( env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$T/home" CFFIXED_USER_HOME="$CFHOME" TMPDIR="$T/tmp" OPENSNAP_APP_SUPPORT="$T/support" \
    "$T/Probe.app/Contents/MacOS/OpenSnap" open-opensnap 4 >"$T/probe.out" 2>&1 ) &
PROBE=$!
peak=0; end=$(( $(date +%s) + 12 ))
while [ "$(date +%s)" -lt "$end" ] && kill -0 "$PROBE" 2>/dev/null; do
    rss=$(/bin/ps -axo rss=,comm= | awk '/com\.apple\.appkit\.xpc\.openAndSavePanelService$/ { if ($1 > m) m = $1 } END { print m + 0 }')
    [ "$rss" -le "$peak" ] || peak=$rss
    sleep 0.25
done
kill "$PROBE" 2>/dev/null || true
peak_mb=$((peak / 1024)); kills=0; [ ! -f "$KILLED" ] || kills=$(wc -l < "$KILLED" | tr -d ' ')
echo "mode             $MODE (CFFIXED_USER_HOME=$CFHOME)"
echo "peak panel RSS   ${peak_mb} MB   watchdog kills: $kills"
if [ "$MODE" = normalized ]; then
    [ "$peak_mb" -lt 300 ] && [ "$kills" -eq 0 ] && echo "RESULT ok: the panel service stayed small" || { echo "RESULT FAIL: the panel service grew"; exit 1; }
else
    [ "$kills" -gt 0 ] && echo "RESULT reproduced: the OS bug is still present (the watchdog ended the service)" || echo "RESULT not reproduced: this macOS build no longer loops on a non-normalized CFFIXED_USER_HOME"
fi
