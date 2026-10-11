#!/usr/bin/env bash
# Run Golf Tycoon's GUT test suites headless.
#
#   ./test.sh                      the unit suite (tests/unit)
#   ./test.sh integration          the integration suite (tests/integration)
#   ./test.sh all                  both suites in one run
#   ./test.sh unit -gselect=hole   anything after the suite goes to GUT
#
# Resolves Godot (bundled zip, $GODOT, PATH, or download) and imports the project
# when its script classes changed since the last import. A run fails when a test
# fails, and also when the engine logged an error while the tests ran: a GDScript
# runtime error ends the test it happened in without failing it, and a leak only
# shows up as an error at exit, so the log is checked as well.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SUITE="unit"
case "${1:-}" in
    unit|integration|all)
        SUITE="$1"
        shift
        ;;
esac
case "$SUITE" in
    unit) DIRS="res://tests/unit/" ;;
    integration) DIRS="res://tests/integration/" ;;
    all) DIRS="res://tests/unit/,res://tests/integration/" ;;
esac

GODOT_BIN="$(bash "$ROOT/scripts/resolve-godot.sh")"
echo "Using Godot: $GODOT_BIN"
bash "$ROOT/scripts/ensure-imported.sh" "$GODOT_BIN"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

echo "Running the $SUITE suite..."
set +e
"$GODOT_BIN" --headless --path "$ROOT" \
    -s addons/gut/gut_cmdln.gd \
    -gconfig=res://gutconfig.json \
    -gdir="$DIRS" \
    -gexit \
    "$@" 2>&1 | tee "$LOG"
STATUS="${PIPESTATUS[0]}"
set -e

# Engine and script errors, as Godot prints them (colour codes stripped).
ERRORS="$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -E '^(SCRIPT ERROR|ERROR|USER ERROR):' || true)"
if [ -n "$ERRORS" ]; then
    echo
    echo "The engine reported errors during the run:"
    printf '%s\n' "$ERRORS" | sort | uniq -c | sort -rn
    echo
    echo "Each error is printed in full, with its backtrace, in the log above."
    [ "$STATUS" -ne 0 ] || STATUS=1
fi

exit "$STATUS"
