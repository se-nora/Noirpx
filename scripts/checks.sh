#!/bin/sh
# Run verification checks for a Noirpx goal worktree.
#
# usage: scripts/checks.sh <worktree-path> [--quick|--full|--ios]
#
# Builds reuse this worktree's own .build directory (SwiftPM's default scratch
# path) and DerivedData/{mac,ios-simulator}, so a second run with no source
# change is incremental. .build/ and DerivedData/ are git-ignored and unique
# per worktree, so separate worktrees can run checks concurrently; never run
# two checks at once in one worktree (they would contend on the shared .build
# lock). Different worktrees are independent.
set -eu

wt="${1:?usage: $0 <worktree-path> [--quick|--full|--ios]}"
mode="${2:---quick}"
[ -d "$wt" ] || { echo "error: worktree not found: $wt" >&2; exit 1; }

cd "$wt"

SCRATCH=".build"

now() { date +%s; }
ts() { date '+%Y-%m-%dT%H:%M:%S'; }

run_step() {
    step_name="$1"; shift
    step_start="$(now)"
    step_ts="$(ts)"
    printf '=== %s ===\n' "$step_name"
    printf '    start   %s\n' "$step_ts"
    printf '    run     %s\n' "$*"
    step_rc=0
    "$@" || step_rc=$?
    printf '    elapsed %ss\n' "$(( $(now) - step_start ))"
    return "$step_rc"
}

overall_start="$(now)"

case "$mode" in
  --quick)
    run_step "swift test" swift test --parallel -c release --scratch-path "$SCRATCH"
    run_step "simcore-layout" sh scripts/simcore-layout.sh
    ;;
  --full)
    run_step "swift test" swift test --parallel -c release --scratch-path "$SCRATCH"
    run_step "xcodebuild macOS Debug" \
        xcodebuild -project Noirpx.xcodeproj -scheme Noirpx \
        -configuration Debug -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath DerivedData/mac CODE_SIGNING_ALLOWED=NO build
    run_step "simcore-layout" sh scripts/simcore-layout.sh
    ;;
  --ios)
    run_step "swift test" swift test --parallel --scratch-path "$SCRATCH"
    run_step "xcodebuild iOS Simulator Debug" \
        xcodebuild -project Noirpx.xcodeproj -scheme Noirpx \
        -configuration Debug -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath DerivedData/ios-simulator CODE_SIGNING_ALLOWED=NO build
    run_step "simcore-layout" sh scripts/simcore-layout.sh
    ;;
  *)
    echo "error: unknown mode $mode (use --quick, --full, or --ios)" >&2
    exit 2
    ;;
esac

printf '=== total %ss ===\n' "$(( $(now) - overall_start ))"