#!/usr/bin/env bash
# Import the project if Godot's script class cache is missing or out of date.
#
# Headless runs (the tests, the warnings sweep) resolve `class_name` globals from
# .godot/global_script_class_cache.cfg, which only the editor or an --import run
# writes. A class added, renamed or moved since the last import would fail to
# parse, so this compares the classes the scripts declare with the cache and
# imports only when they differ — an import takes several seconds.
#
# Usage: scripts/ensure-imported.sh <path-to-godot>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${1:?usage: ensure-imported.sh <path-to-godot>}"
CACHE="$ROOT/.godot/global_script_class_cache.cfg"
export LC_ALL=C

# "ClassName res://path/to/script.gd" for every class_name in the project.
declared_classes() {
    (cd "$ROOT" && grep -rEo --include='*.gd' --exclude-dir=.godot --exclude-dir=.git \
        '^class_name[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' .) \
        | sed -E 's#^\./([^:]*):class_name[[:space:]]+(.*)$#\2 res://\1#' \
        | sort
}

# The same pairs as the cache records them.
cached_classes() {
    awk -F'"' '/"class": &"/ { name = $4 } /"path": "/ { print name " " $4 }' "$CACHE" | sort
}

if [ -f "$CACHE" ] && [ -z "$(comm -23 <(declared_classes) <(cached_classes))" ]; then
    exit 0
fi

echo "Importing project (script classes changed since the last import)..." >&2
"$GODOT_BIN" --headless --path "$ROOT" --import --quit >/dev/null 2>&1 || true
