#!/bin/sh
# Run verification checks for a Noirpx goal worktree.
#
# usage: scripts/checks.sh <worktree-path> [--quick|--full|--ios]
set -eu

wt="${1:?usage: $0 <worktree-path> [--quick|--full|--ios]}"
mode="${2:- --quick}"
[ -d "$wt" ] || { echo "error: worktree not found: $wt" >&2; exit 1; }

cd "$wt"

# Use a unique scratch path per worktree to avoid .build lock conflicts
# when multiple worktrees run tests simultaneously.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/noirpx-checks.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

case "$mode" in
  --quick)
    echo "=== swift test --parallel --scratch-path $SCRATCH ==="
    swift test --parallel --scratch-path "$SCRATCH"
    ;;
  --full)
    echo "=== swift test --parallel --scratch-path $SCRATCH ==="
    swift test --parallel --scratch-path "$SCRATCH"
    echo
    echo "=== xcodebuild macOS Debug ==="
    xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug -destination 'platform=macOS' build
    ;;
  --ios)
    echo "=== swift test --parallel --scratch-path $SCRATCH ==="
    swift test --parallel --scratch-path "$SCRATCH"
    echo
    echo "=== xcodebuild iOS Simulator Debug ==="
    xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
    ;;
  *)
    echo "error: unknown mode $mode (use --quick, --full, or --ios)" >&2
    exit 2
    ;;
esac