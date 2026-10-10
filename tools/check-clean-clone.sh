#!/bin/sh
# G1 (OSN-020): the committed tree builds and passes its tests with no archive folder and no Font Awesome token.
#
# Clones this checkout's committed HEAD into a fresh temp directory and, inside the clone only:
#   1. asserts there is no original-archive folder, no build/ and no Font Awesome fonts,
#   2. sh tools/build.sh,
#   3. python3 tools/check-no-original.py build/OpenSnap.app,
#   4. python3 tools/test.py.
# It never touches this checkout's build/ and never launches the app. tools/test-native-startup.py is NOT run: it starts the
# built binary under the real bundle id (com.shoemoney.opensnap), and OPENSNAP_APP_SUPPORT / CFFIXED_USER_HOME do not
# isolate UserDefaults, so it would read and write the owner's live preferences. The screenshot harness
# (tools/eye-dump-audit.sh) is the safe way to run the built app: it launches a re-identified temp copy.
# Uncommitted edits are not in the clone; commit first (the script warns when the tree is dirty).
# Slow (a full build plus every suite), so it is not part of tools/test.py.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SHA=$(git -C "$ROOT" rev-parse HEAD)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/opensnap-clean-clone.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
CLONE="$TMP/clone"

if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
    echo "warning: uncommitted changes are not in the clone; this proves $SHA only" >&2
fi
echo "== clone $SHA into $CLONE"
git clone --quiet --no-checkout --no-hardlinks "$ROOT" "$CLONE"
git -C "$CLONE" checkout --quiet "$SHA"

ARCHIVE="original"
[ ! -e "$CLONE/$ARCHIVE" ] || { echo "FAIL: the clone contains an $ARCHIVE folder" >&2; exit 1; }
[ ! -e "$CLONE/build" ] || { echo "FAIL: the clone contains a build folder" >&2; exit 1; }
if find "$CLONE" -name '*.ttf' -o -name '.npmrc' | grep -q .; then
    echo "FAIL: the clone contains fonts or registry credentials" >&2; exit 1
fi
echo "PASS clone is clean: no $ARCHIVE folder, no build output, no fonts, no registry credentials"

# Nothing from this shell may stand in for a missing token or font directory.
run() { env -u OPENSNAP_FETCH_FONTAWESOME -u OPENSNAP_FA_FONT_DIR -u OPENSNAP_NO_PRO_FONTS -u OPENSNAP_APP_SUPPORT -u OPENSNAP_FIXTURE "$@"; }

echo "== build (in the clone)"
(cd "$CLONE" && run sh tools/build.sh >"$TMP/build.log" 2>&1) || { tail -40 "$TMP/build.log" >&2; echo "FAIL: build" >&2; exit 1; }
echo "PASS build"
echo "== check-no-original (bundle)"
(cd "$CLONE" && run python3 tools/check-no-original.py build/OpenSnap.app)
echo "== test.py (in the clone)"
(cd "$CLONE" && run python3 tools/test.py) || { echo "FAIL: tools/test.py in the clone" >&2; exit 1; }
echo "SKIPPED: tools/test-native-startup.py (launches the real bundle id against the real defaults; see the header)"
echo "PASS clean clone of $SHA: built, bundle has no original assets, all suites passed"
