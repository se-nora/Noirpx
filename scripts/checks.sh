#!/bin/sh
# Run verification checks for a Noirpx goal worktree.
#
# usage: scripts/checks.sh <worktree-path> [--quick|--full|--ios]
set -eu

wt="${1:?usage: $0 <worktree-path> [--quick|--full|--ios]}"
mode="${2:- --quick}"
[ -d "$wt" ] || { echo "error: worktree not found: $wt" >&2; exit 1; }

cd "$wt"

case "$mode" in
  --quick)
    echo "=== swift test (package) ==="
    swift test
    ;;
  --full)
    echo "=== swift test (package) ==="
    swift test
    echo
    echo "=== xcodebuild macOS Debug ==="
    xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug -destination 'platform=macOS' build
    ;;
  --ios)
    echo "=== swift test (package) ==="
    swift test
    echo
    echo "=== xcodebuild iOS Simulator Debug ==="
    xcodebuild -project Noirpx.xcodeproj -scheme Noirpx -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
    ;;
  *)
    echo "error: unknown mode $mode (use --quick, --full, or --ios)" >&2
    exit 2
    ;;
esac