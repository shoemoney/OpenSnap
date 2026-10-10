#!/bin/sh
# Safe interactive session for real-click end-to-end testing. Launches ONE isolated COPY of the built app (throwaway bundle id,
# throwaway home, support folder and TMPDIR) and leaves it running so a driver (the kimi-cu computer-use tools) can click it.
# build/OpenSnap.app is never run in place and the real bundle id is never used, so the owner's defaults domain, support folder
# and Keychain are never reachable. The real stores are hashed at start and compared again at stop, after all cleanup.
#
#   sh tools/e2e-session.sh start [--app PATH] [--seed empty|history|destinations|all] [--aws]
#   sh tools/e2e-session.sh status
#   sh tools/e2e-session.sh stop [SESSION_ID|APP_PID]
#
# --seed writes SYNTHETIC fixtures into the throwaway support folder before launch: History entries (.opensnap documents
# with previews) and/or destinations on fake hosts. --aws additionally points the app's own S3 profile reader at the owner's
# credentials file IN PLACE (AWS_SHARED_CREDENTIALS_FILE) and seeds an S3 destination on profile "default"; the file is never
# read, copied, printed or logged by this script. Secrets stay in memory because OPENSNAP_APP_SUPPORT keeps them there.
# There is deliberately NO sandbox fence: it would block the normal UI. The isolation env and the real-store guard protect.
#
# NOT ISOLATED: History > Move to Trash uses FileManager.trashItem, which ignores the throwaway HOME and moves the files into the
# owner's REAL ~/.Trash (the J2 run left two synthetic .opensnap/.png files there). The real-store guard does not watch ~/.Trash, so
# nothing here notices. Do not drive Move to Trash in a session; if it was driven, remove only the files it trashed (the session's
# own entries) from ~/.Trash by hand. Everything else the app writes stays under the session's temp dir.
#
# stop: SIGTERM, SIGKILL after E2E_STOP_TIMEOUT seconds (default 10), drop the throwaway defaults domain (E2E_DEFAULTS, default
# /usr/bin/defaults), remove the temp dir, THEN compare the real stores. Exit non-zero when any watched real store changed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REAL_ID="com.shoemoney.opensnap"
DEFAULTS=${E2E_DEFAULTS:-/usr/bin/defaults}
STOP_TIMEOUT=${E2E_STOP_TIMEOUT:-10}
SESSIONS=${E2E_STATE_DIR:-${TMPDIR:-/tmp}/opensnap-e2e-sessions}
GUARD="python3 -I $ROOT/tools/real_store_guard.py"

# Only <real id>.e2e-<digits> passes, so neither real defaults domain (the current id or the retired one) can ever match.
valid_id() {
    case "$1" in
        "$REAL_ID") return 1 ;;
        com.shoemoney.opensnap.e2e-*[!0-9]*|com.shoemoney.opensnap.e2e-) return 1 ;;
        com.shoemoney.opensnap.e2e-[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}
# A session temp dir is exactly <tmp>/e2e-session.<6 alphanumerics> and carries a marker naming its own id.
valid_dir() {
    dir=$1; id=$2
    case "$dir" in /*) ;; *) return 1 ;; esac
    case "$dir" in *..*|*"
"*) return 1 ;; esac
    base=$(basename "$dir")
    case "$base" in e2e-session.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]) ;; *) return 1 ;; esac
    [ -d "$dir" ] && [ -f "$dir/.e2e-session" ] && [ "$(cat "$dir/.e2e-session")" = "$id" ]
}
drop_defaults() {
    id=$1
    valid_id "$id" || { echo "refusing to drop defaults for unexpected id: $id" >&2; return 1; } # protection:drop
    "$DEFAULTS" delete "$id" >/dev/null 2>&1 || true
    plist="$HOME/Library/Preferences/$id.plist"
    base=$(basename "$plist"); stem=${base%.plist}
    if [ "$stem.plist" = "$base" ] && valid_id "$stem"; then rm -f "$plist"; fi # protection:rm
}
remove_dir() {
    dir=$1; id=$2
    valid_dir "$dir" "$id" || { echo "refusing to remove unexpected session dir: $dir" >&2; return 1; } # protection:dir
    rm -rf "$dir"
}
# Fields of a session file are read one key at a time, never sourced.
field() { sed -n "s/^$1=//p" "$2" | head -n 1; }

# The process may only be signalled when its command line is the session's own app copy.
terminate_app() {
    pid=$1; dir=$2
    case "$pid" in ''|*[!0-9]*) echo "no valid pid recorded; nothing to stop" >&2; return 0 ;; esac
    kill -0 "$pid" 2>/dev/null || { echo "app pid $pid already gone"; return 0; }
    cmd=$(ps -o command= -p "$pid" 2>/dev/null || true)
    case "$cmd" in *"$dir/"*) ;; *) echo "pid $pid is not this session's app copy; NOT signalling it" >&2; return 0 ;; esac # protection:pid
    kill -TERM "$pid" 2>/dev/null || true
    waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$STOP_TIMEOUT" ]; do sleep 1; waited=$((waited + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
        echo "app pid $pid ignored SIGTERM for ${STOP_TIMEOUT}s; sending SIGKILL"
        kill -KILL "$pid" 2>/dev/null || true
        sleep 1
    else
        echo "app pid $pid exited after SIGTERM (${waited}s)"
    fi
}

# Everything destructive, in one place, so callers can order it relative to the compare.
session_cleanup() {
    pid=$1; dir=$2; id=$3
    terminate_app "$pid" "$dir"
    drop_defaults "$id" || return 1
    remove_dir "$dir" "$id" || return 1
}

compare_stores() {
    snapshot=$1
    status=0
    $GUARD compare "$snapshot" > "$SESSIONS/.compare.txt" || status=1
    echo "real stores      after:  $(sed -n '1p' "$SESSIONS/.compare.txt")"
    sed -n '2,$p' "$SESSIONS/.compare.txt"
    rm -f "$SESSIONS/.compare.txt"
    return "$status"
}

# ----------------------------------------------------------------------------------------------------------------- seeding
seed_fixtures() {
    support=$1; what=$2; aws=$3
    python3 -I - "$support" "$what" "$aws" <<'PYSEED'
import base64, hashlib, json, os, struct, sys, uuid, zlib, time
support, what, aws = sys.argv[1], sys.argv[2], sys.argv[3] == "yes"
REFERENCE = 978307200  # Foundation Date is seconds since 2001-01-01


def png(width, height, pixel):
    rows = b"".join(b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(width)) for y in range(height))
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def gradient(seed, width, height):
    def pixel(x, y):
        return (min(255, 40 + seed * 25 + x * 90 // width), min(255, 90 + y * 120 // height), max(0, 210 - seed * 20 + (x + y) * 30 // (width + height)))
    return pixel


def colour(red, green, blue):
    return {"red": red, "green": green, "blue": blue, "alpha": 1}


def element(kind, **fields):
    value = {"id": str(uuid.uuid4()), "kind": kind, "color": colour(0.9, 0.15, 0.15), "strokeWidth": 6, "filled": False, "shadowed": False,
             "text": "", "fontSize": 24, "fontName": "Helvetica-Bold", "outlined": True,
             "transform": {"a": 1, "b": 0, "c": 0, "d": 1, "tx": 0, "ty": 0}, "points": [], "rect": [[0, 0], [0, 0]]}
    value.update(fields)
    return value


def document(width, height, seed, label):
    pixels = png(width // 4, height // 4, gradient(seed, width // 4, height // 4))   # small pixels scaled by the canvas
    elements = [element("rectangle", rect=[[width * 0.12, height * 0.18], [width * 0.34, height * 0.28]]),
                element("ellipse", rect=[[width * 0.55, height * 0.2], [width * 0.26, height * 0.26]], color=colour(0.1, 0.45, 0.95)),
                element("arrow", points=[[width * 0.2, height * 0.8], [width * 0.6, height * 0.55]], color=colour(0.95, 0.7, 0.1)),
                element("text", text=label, rect=[[width * 0.1, height * 0.62], [width * 0.6, 40]], fontSize=28)]
    return {"format": "com.shoemoney.opensnap.document", "version": 1, "size": [width, height], "backgroundColor": colour(1, 1, 1),
            "backgroundPNG": base64.b64encode(pixels).decode(), "elements": elements}


def seed_history():
    folder = os.path.join(support, "History")
    os.makedirs(folder, exist_ok=True)
    names = ["Quarterly mockup", "Bug report screenshot", "Onboarding flow", "Pricing page", "Team photo wall", "Error dialog"]
    actions = ["archived", "exported", "shared", "archived", "shared", "exported"]
    entries = []
    now = time.time()
    for index, name in enumerate(names):
        width, height = 900 + index * 40, 600
        native = json.dumps(document(width, height, index, name), sort_keys=True).encode()
        stem = f"snap-{uuid.uuid4()}-{uuid.uuid4()}".upper().replace("SNAP-", "snap-")
        with open(os.path.join(folder, stem + ".opensnap"), "wb") as handle:
            handle.write(native)
        preview = png(180, 120, gradient(index, 180, 120))
        with open(os.path.join(folder, stem + ".png"), "wb") as handle:
            handle.write(preview)
        stamp = now - (index // 3) * 3 * 86400 - index * 600 - REFERENCE
        entry = {"id": str(uuid.uuid4()).upper(), "name": name, "date": stamp, "updated": stamp, "size": [width, height],
                 "text": name, "action": actions[index], "nativeFile": stem + ".opensnap", "previewFile": stem + ".png",
                 "digest": hashlib.sha256(native).hexdigest(), "imported": False}
        if actions[index] == "shared":
            entry["destination"] = "Example S3"
            entry["remoteURL"] = f"https://cdn.example.test/pics/e2e-{index}.png"
        entries.append(entry)
    with open(os.path.join(folder, "index.json"), "w") as handle:
        json.dump({"version": 1, "entries": list(reversed(entries)), "ignoredLooseFiles": []}, handle, indent=1, sort_keys=True)
    print(f"seed history      {len(entries)} synthetic entries (.opensnap + preview) in the throwaway support folder")


def destination(name, **settings):
    base = {"endpoint": "", "transport": "webDAV", "username": "", "remoteFolder": "", "publicBaseURL": "", "credentialID": str(uuid.uuid4()).upper(),
            "sshAlias": "", "sftpRemoteRoot": ""}
    base.update(settings)
    return {"id": str(uuid.uuid4()).upper(), "name": name, "settings": base}


def seed_destinations():
    folder = os.path.join(support, "Publishing")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    items = []
    if aws:
        items.append(destination("S3 · cdn.shoemoney.com", transport="s3", remoteFolder="pics", publicBaseURL="https://cdn.shoemoney.com/pics",
                                 s3={"region": "us-east-1", "bucket": "cdn.shoemoney.com", "credentialsProfile": "default", "publicReadACL": False}))
    if what in ("destinations", "all"):
        items += [destination("WebDAV · demo", transport="webDAV", endpoint="https://dav.example.test/remote.php/dav/files/demo", username="demo",
                              remoteFolder="shots", publicBaseURL="https://files.example.test/shots"),
                  destination("SFTP · e2e-host", transport="sftp", endpoint="sftp://sftp.example.test", sshAlias="e2e-host", sftpRemoteRoot="/srv/shots",
                              publicBaseURL="https://sftp.example.test/shots"),
                  destination("FTPS · demo", transport="ftps", endpoint="ftps://ftp.example.test", username="demo", remoteFolder="shots"),
                  destination("S3 · example-bucket", transport="s3", endpoint="https://s3.example.test", username="AKIAEXAMPLEFAKE", remoteFolder="pics",
                              s3={"region": "us-east-1", "bucket": "example-bucket", "credentialsProfile": "", "publicReadACL": False})]
    if not items:
        return
    with open(os.path.join(folder, "destinations.json"), "w") as handle:
        json.dump({"version": 2, "defaultID": items[0]["id"], "destinations": items}, handle, indent=1, sort_keys=True)
    os.chmod(os.path.join(folder, "destinations.json"), 0o600)
    print(f"seed destinations {len(items)} ({'1 real-profile S3 default + ' if aws else ''}fake-host examples); no secret is stored")


if what in ("history", "all"):
    seed_history()
if what in ("destinations", "all") or aws:
    seed_destinations()
if what == "empty" and not aws:
    print("seed              none (empty support folder)")
PYSEED
}

# ---------------------------------------------------------------------------------------------------------------- start
cmd_start() {
    APP_SRC="$ROOT/build/OpenSnap.app"; SEED="empty"; AWS=no
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --app) APP_SRC=${2:?--app needs a path}; shift 2 ;;
            --seed) SEED=${2:?--seed needs a value}; shift 2 ;;
            --aws) AWS=yes; shift ;;
            *) echo "unknown argument $1" >&2; exit 2 ;;
        esac
    done
    case "$SEED" in empty|history|destinations|all) ;; *) echo "--seed must be empty, history, destinations or all" >&2; exit 2 ;; esac
    THROWAWAY_ID="$REAL_ID.e2e-$$"
    # Validated BEFORE any trap or cleanup exists: a cleanup that runs on a bad id is how a real defaults domain gets deleted.
    valid_id "$THROWAWAY_ID" || { echo "refusing: throwaway id '$THROWAWAY_ID' is not $REAL_ID.e2e-<pid>" >&2; exit 2; } # protection:top
    [ -x "$APP_SRC/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_SRC/Contents/Info.plist")" ] || { echo "no built app at $APP_SRC (run sh tools/build.sh)" >&2; exit 2; }
    AWS_FILE=""
    if [ "$AWS" = yes ]; then
        AWS_FILE="$HOME/.aws/credentials"
        [ -f "$AWS_FILE" ] || { echo "--aws: $AWS_FILE does not exist" >&2; exit 2; }   # existence only; the content is never read here
    fi
    mkdir -p "$SESSIONS"

    TMP=$(mktemp -d "${TMPDIR:-/tmp}/e2e-session.XXXXXX")
    printf '%s' "$THROWAWAY_ID" > "$TMP/.e2e-session"
    APP_PID=""
    LAUNCHED=no
    GUARD_FILE="$SESSIONS/$THROWAWAY_ID.guard.json"
    # Failure-only safety net: once the session is up (LAUNCHED=yes) the trap is disarmed, because the session outlives this process.
    cleanup() {
        [ "$LAUNCHED" = yes ] && return 0
        session_cleanup "$APP_PID" "$TMP" "$THROWAWAY_ID" || true
        echo "start failed; session torn down" >&2
        compare_stores "$GUARD_FILE" >&2 || true
        rm -f "$SESSIONS/$THROWAWAY_ID.session" "$GUARD_FILE"
    }
    trap cleanup EXIT

    $GUARD snapshot "$GUARD_FILE" > "$TMP/guard-before.txt"
    EXE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_SRC/Contents/Info.plist")
    APP="$TMP/$(basename "$APP_SRC")"
    cp -R "$APP_SRC" "$APP"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $THROWAWAY_ID" "$APP/Contents/Info.plist"
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
    mkdir -p "$TMP/home" "$TMP/tmp" "$TMP/support"
    seed_fixtures "$TMP/support" "$SEED" "$AWS"

    AWS_ENV=""
    [ "$AWS" != yes ] || AWS_ENV="AWS_SHARED_CREDENTIALS_FILE=$AWS_FILE"
    # shellcheck disable=SC2086
    nohup env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$TMP/home" CFFIXED_USER_HOME="$TMP/home" TMPDIR="$TMP/tmp" \
        OPENSNAP_APP_SUPPORT="$TMP/support" $AWS_ENV "$APP/Contents/MacOS/$EXE" >"$TMP/app.log" 2>&1 </dev/null &
    APP_PID=$!
    sleep "${E2E_LAUNCH_WAIT:-2}"
    kill -0 "$APP_PID" 2>/dev/null || { echo "the app copy exited during launch; see $TMP/app.log" >&2; sed -n '1,20p' "$TMP/app.log" >&2; exit 1; }

    {
        echo "id=$THROWAWAY_ID"
        echo "pid=$APP_PID"
        echo "dir=$TMP"
        echo "app=$APP"
        echo "seed=$SEED"
        echo "aws=$AWS"
        echo "started=$(date '+%Y-%m-%dT%H:%M:%S%z')"
    } > "$SESSIONS/$THROWAWAY_ID.session"
    LAUNCHED=yes
    echo "session          $THROWAWAY_ID"
    echo "pid              $APP_PID   (drive it with mcp__kimi-cu__get_app_state pid=$APP_PID)"
    echo "app copy         $APP (copied from $APP_SRC; the source bundle is never executed)"
    echo "isolation        env -i; HOME and CFFIXED_USER_HOME, TMPDIR and OPENSNAP_APP_SUPPORT all under $TMP; OPENSNAP_FIXTURE unset; no sandbox fence"
    echo "seed             $SEED"
    echo "not isolated     History > Move to Trash goes to the owner's real ~/.Trash (FileManager.trashItem ignores HOME); do not drive it, or remove only what it trashed afterwards"
    if [ "$AWS" = yes ]; then
        echo "aws              AWS_SHARED_CREDENTIALS_FILE points at the owner's credentials file in place; its content is never read or printed here"
    fi
    echo "real stores      before: $(cat "$TMP/guard-before.txt")"
    echo "stop with        sh tools/e2e-session.sh stop"
}

# ----------------------------------------------------------------------------------------------------------------- status
sessions_list() { ls "$SESSIONS"/*.session 2>/dev/null || true; }

cmd_status() {
    found=0
    for file in $(sessions_list); do
        found=$((found + 1))
        pid=$(field pid "$file"); alive=gone
        case "$pid" in ''|*[!0-9]*) ;; *) kill -0 "$pid" 2>/dev/null && alive=running ;; esac
        echo "session $(field id "$file")  pid $pid ($alive)  seed $(field seed "$file")  aws $(field aws "$file")  started $(field started "$file")"
        echo "  dir $(field dir "$file")"
    done
    [ "$found" -gt 0 ] || echo "no e2e sessions"
    status=0
    for file in $(sessions_list); do
        id=$(field id "$file")
        if valid_id "$id" && [ -f "$SESSIONS/$id.guard.json" ]; then
            compare_stores "$SESSIONS/$id.guard.json" || status=1
            break
        fi
    done
    return "$status"
}

# ------------------------------------------------------------------------------------------------------------------- stop
cmd_stop() {
    want=${1:-}
    target=""
    for file in $(sessions_list); do
        if [ -z "$want" ] || [ "$(field id "$file")" = "$want" ] || [ "$(field pid "$file")" = "$want" ]; then
            [ -z "$target" ] || { echo "several sessions match; pass a session id or pid:" >&2; cmd_status >&2 || true; exit 2; }
            target=$file
        fi
    done
    [ -n "$target" ] || { echo "no matching e2e session" >&2; exit 2; }
    id=$(field id "$target"); pid=$(field pid "$target"); dir=$(field dir "$target")
    # The id comes out of a file on disk: validate it before anything destructive is even considered.
    valid_id "$id" || { echo "refusing: session file names an unexpected id '$id'" >&2; exit 2; } # protection:top
    snapshot="$SESSIONS/$id.guard.json"
    [ -f "$snapshot" ] || { echo "no store snapshot for $id; cannot prove the stores are unchanged" >&2; exit 2; }
    echo "stopping         $id (pid $pid)"
    cleanup_failed=0
    session_cleanup "$pid" "$dir" "$id" || cleanup_failed=1  # protection:order
    rm -f "$target"
    echo "cleanup          app stopped, throwaway defaults ($id) dropped, temp dir removed BEFORE the final compare; the compare below would show any damage cleanup did"
    status=0
    compare_stores "$snapshot" || status=1
    leftover="$HOME/Library/Preferences/$id.plist"
    if [ -e "$leftover" ]; then echo "LEFT BEHIND: $leftover"; status=1; fi
    [ "$cleanup_failed" -eq 0 ] || status=1
    rm -f "$snapshot"
    [ "$status" -ne 0 ] && echo "RESULT FAILED" || echo "RESULT stores unchanged, session removed"
    return "$status"
}

case "${1:-}" in
    start) shift; cmd_start "$@" ;;
    status) cmd_status ;;
    stop) shift; cmd_stop "$@" ;;
    *) echo "usage: e2e-session.sh start [--app PATH] [--seed empty|history|destinations|all] [--aws] | status | stop [SESSION_ID|PID]" >&2; exit 2 ;;
esac
