#!/bin/sh
# Bump the app's minor marketing version (0.x.0), reset patch to 0.
# Updates every MARKETING_VERSION in Noirpx.xcodeproj/project.pbxproj.
#
# usage: scripts/bump-version.sh [--dry-run] <worktree-path>
set -eu

dry_run=false
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=true
  shift
fi

wt="${1:?usage: $0 [--dry-run] <worktree-path>}"
pbxproj="$wt/Noirpx.xcodeproj/project.pbxproj"
[ -f "$pbxproj" ] || { echo "error: $pbxproj not found" >&2; exit 1; }

# Find current MARKETING_VERSION lines; they should all be identical.
# BSD grep and sed do not understand \s, so use POSIX character classes.
cur=$(grep -E 'MARKETING_VERSION[[:space:]]*=' "$pbxproj" | head -1 \
  | sed -E 's/.*MARKETING_VERSION[[:space:]]*=[[:space:]]*([0-9]+)\.([0-9]+)\.([0-9]+);.*/\1.\2.\3/')
[ -n "$cur" ] || { echo "error: no MARKETING_VERSION found" >&2; exit 1; }
case "$cur" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "error: cannot parse MARKETING_VERSION from '$cur'" >&2; exit 1 ;;
esac

# Parse major.minor.patch; bump minor, zero patch.
IFS='.' read -r major minor patch <<EOF
$cur
EOF
new_minor=$((minor + 1))
new_version="${major}.${new_minor}.0"

if $dry_run; then
  echo "current: $cur"
  echo "new:     $new_version"
  exit 0
fi

# Replace all occurrences. Escape the dots so they match literally.
pattern=$(printf '%s' "$cur" | sed 's/\./\\./g')
sed -i '' -E "s/MARKETING_VERSION[[:space:]]*=[[:space:]]*${pattern}/MARKETING_VERSION = ${new_version}/g" "$pbxproj"

if ! grep -q "MARKETING_VERSION = ${new_version};" "$pbxproj"; then
  echo "error: version bump did not apply to $pbxproj" >&2
  exit 1
fi

echo "Bumped $cur -> $new_version in $pbxproj"
