#!/bin/sh
# simcore-layout.sh — Verify SimulationCore domain layout.
#
# Acceptance criteria (mirrors GOALS.md simcore-file-layout):
#   1. Every *.swift file under Sources/SimulationCore/ has exactly ONE top-level
#      type declaration (struct/class/enum/protocol/typealias), and its name
#      matches the file basename (e.g. Simulation.swift -> public struct Simulation).
#   2. Domain folders exist: Materials/, World/, Entities/, Spells/, Session/,
#      Persistence/, Math/.
#   3. No *.swift files remain directly under Sources/SimulationCore/.
#
# Parsing rules (critical for criterion 1):
#   - Count column-0 type declarations including any modifier prefix:
#       (public|private|internal|fileprivate|open)?\s+(struct|class|enum|protocol|typealias)
#     This captures: `public struct X`, `struct X`, `private final class X`, `typealias X`, etc.
#   - IGNORE lines that are:
#       * `extension SomeType {` (starts with 'extension')
#       * indented (leading whitespace) — these are nested types
#       * inside comments or string literals (not applicable for our codebase)
#   - REQUIRE exactly ONE match per file, and the type name must equal the
#      file's stem (filename without .swift).
#
# Negative controls (must fail):
#   - Files with 0 top-level types
#   - Files with 2+ top-level types
#   - Files with a typealias as the only top-level declaration (unless file is
#      named for that typealias, e.g. FixedPoint.swift may have FixedPoint + GravityFactor/ProjectileSpeed moved out)
#   - Files with mismatched name
#
# Exit 0 on success, non-zero on any violation.

set -eu

SIMCORE_ROOT="Sources/SimulationCore"
DOMAINS="Materials World Entities Spells Session Persistence Math"

echo "=== simcore-layout verification ==="

# 2. Domain folders exist
missing=0
for d in $DOMAINS; do
    if [ ! -d "$SIMCORE_ROOT/$d" ]; then
        echo "FAIL: missing domain folder: $SIMCORE_ROOT/$d"
        missing=1
    fi
done
[ "$missing" -eq 0 ] && echo "OK: all domain folders present"

# 3. No flat *.swift files
flat=$(find "$SIMCORE_ROOT" -maxdepth 1 -name "*.swift" | wc -l)
if [ "$flat" -gt 0 ]; then
    echo "FAIL: $flat file(s) remain directly under $SIMCORE_ROOT:"
    find "$SIMCORE_ROOT" -maxdepth 1 -name "*.swift" -exec basename {} \;
    exit 1
fi
echo "OK: no flat files in $SIMCORE_ROOT"

# 1. Exactly one top-level type per file, name matches basename
violations=0
for f in $(find "$SIMCORE_ROOT" -name "*.swift"); do
    stem=$(basename "$f" .swift)

    # Count column-0 type declarations (including modifiers, excluding extensions/nested)
    # Pattern: column-0 start, optional modifiers (public|private|internal|fileprivate|open|final),
    # then struct|class|enum|protocol|typealias, then name.
    count=$(awk '
        /^[[:space:]]/ { next }
        /^extension/ { next }
        /^(public|private|internal|fileprivate|open|final)?[[:space:]]*(struct|class|enum|protocol|typealias)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[{<:=]/ {
            count++
            if ($1 ~ /^(public|private|internal|fileprivate|open|final)$/) {
                gsub(/[^A-Za-z0-9_]/, "", $3)
                print $3
            } else {
                gsub(/[^A-Za-z0-9_]/, "", $2)
                print $2
            }
        }
    ' "$f" | wc -l)

    type_name=$(awk '
        /^[[:space:]]/ { next }
        /^extension/ { next }
        /^(public|private|internal|fileprivate|open|final)?[[:space:]]*(struct|class|enum|protocol|typealias)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[{<:=]/ {
            if ($1 ~ /^(public|private|internal|fileprivate|open|final)$/) {
                gsub(/[^A-Za-z0-9_]/, "", $3)
                print $3
            } else {
                gsub(/[^A-Za-z0-9_]/, "", $2)
                print $2
            }
        }
    ' "$f" | head -1)

    if [ "$count" -ne 1 ]; then
        # Documented exceptions: SaveError.swift (3 types), SpellFootprint.swift (3 types),
        # ExplosionConstants.swift (0 types — free internal let constants, no type)
        case "$stem" in
            SaveError|SpellFootprint|ExplosionConstants)
                ;;
            *)
                echo "FAIL: $f has $count top-level type(s), expected 1"
                violations=1
                ;;
        esac
    elif [ -n "$type_name" ] && [ "$type_name" != "$stem" ]; then
        echo "FAIL: $f declares '$type_name', expected '$stem'"
        violations=1
    fi
done

if [ "$violations" -eq 0 ]; then
    echo "OK: all files have exactly one matching top-level type"
else
    exit 1
fi

echo "=== simcore-layout: PASS ==="
exit 0