#!/bin/sh
# Bump the app's marketing version. Default: minor bump, patch reset to 0
# (0.x.0 -> 0.(x+1).0). With --patch: patch bump only (0.x.y -> 0.x.(y+1)),
# for changes with no visual or gameplay effect (docs, refactoring, internal
# cleanups). Updates every MARKETING_VERSION in Noirpx.xcodeproj/project.pbxproj.
#
# usage: scripts/bump-version.sh [--dry-run] [--patch] <worktree-path>
set -eu

dry_run=false
patch_mode=false
while [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "--patch" ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --patch)   patch_mode=true ;;
  esac
  shift
done

wt="${1:?usage: $0 [--dry-run] [--patch] <worktree-path>}"
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

# Parse major.minor.patch.
IFS='.' read -r major minor patch <<EOF
$cur
EOF
if $patch_mode; then
  new_patch=$((patch + 1))
  new_version="${major}.${minor}.${new_patch}"
else
  new_minor=$((minor + 1))
  new_version="${major}.${new_minor}.0"
fi

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
