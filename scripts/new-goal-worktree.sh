#!/bin/sh
# Create a Noirpx goal worktree for the loop skill.
#
# Creates branch agent/<slug> at ~/Noirpx-worktrees/<slug>, checked out from
# the current main. Refuses if the branch or path already exists.
#
# usage: scripts/new-goal-worktree.sh [--repo <repo-or-worktree>] --slug <slug>
set -eu

usage() {
  echo "usage: $0 [--repo <repo-or-worktree>] --slug <slug>" >&2
  exit 2
}

repo=""
slug=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || usage; repo="$2"; shift 2 ;;
    --slug) [ $# -ge 2 ] || usage; slug="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$slug" ] || usage
[ -n "$repo" ] || repo="$(git rev-parse --show-toplevel)"

# Resolve the checkout whose branch is main; never create a second one.
integration="$(git -C "$repo" worktree list --porcelain | awk '
  /^worktree / { wt = $2 }
  /^branch refs\/heads\/main$/ { print wt; exit }
')"
[ -n "$integration" ] || {
  echo "error: no worktree checked out on main; create one first, e.g." >&2
  echo "  git worktree add ~/Noirpx-worktrees/integration-main main" >&2
  exit 1
}

branch="agent/$slug"
root="$HOME/Noirpx-worktrees/$slug"

if git -C "$integration" show-ref --verify --quiet "refs/heads/$branch"; then
  echo "error: branch $branch already exists" >&2
  exit 1
fi
if [ -e "$root" ]; then
  echo "error: path $root already exists" >&2
  exit 1
fi

git -C "$integration" worktree add -b "$branch" "$root" main >/dev/null
echo "worktree: $root"
echo "branch:   $branch"
