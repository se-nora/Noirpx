#!/bin/sh
# scripts/test-timings.sh
# Runs swift test --parallel and prints a sorted timing table plus total wall time.
# Usage: ./scripts/test-timings.sh [--slow] [--scratch-path DIR]

set -eu

SLOW=0
SCRATCH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --slow) SLOW=1; shift ;;
        --scratch-path) SCRATCH="--scratch-path $2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

XUNIT="${TMPDIR:-/tmp}/noirpx-timings.$$.xml"
trap 'rm -f "$XUNIT"' EXIT

echo "=== Running swift test --parallel (slow=$SLOW) ==="
START=$(date +%s)
STATUS=0
if [ $SLOW -eq 1 ]; then
    NOIRPX_SLOW_TESTS=1 swift test --parallel $SCRATCH --xunit-output "$XUNIT" || STATUS=$?
else
    swift test --parallel $SCRATCH --xunit-output "$XUNIT" || STATUS=$?
fi
END=$(date +%s)
ELAPSED=$((END - START))

# Parse xUnit XML: extract name/classname/time attributes INDEPENDENTLY of order.
# The name pattern is anchored on the preceding space/`>` so it cannot match
# the "name=" substring inside `classname="..."` when classname is emitted first.
echo
echo "=== Per-test timing table (descending) ==="
TABLE=$(awk '
    /<testcase[ >]/ {
        line = $0; name = ""; cls = ""; t = ""
        if (match(line, /[ \t>]name="[^"]*"/))  name = substr(line, RSTART+7,  RLENGTH-8)
        if (match(line, /classname="[^"]*"/))   cls  = substr(line, RSTART+11, RLENGTH-12)
        if (match(line, /time="[^"]*"/))        t    = substr(line, RSTART+6,  RLENGTH-7)
        if (t != "" && name != "") print t, cls "/" name
    }' "$XUNIT" | sort -k1,1gr | awk '{printf "%8.3f  %s\n", $1, $2}')

if [ -z "${TABLE:-}" ]; then
    echo "ERROR: no <testcase> entries parsed from xunit output ($XUNIT)" >&2
    head -40 "$XUNIT" >&2 2>/dev/null || true
    exit ${STATUS:-1}
fi
echo "$TABLE"
echo
echo "Total wall time: ${ELAPSED}s"

exit ${STATUS:-0}
