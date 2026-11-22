#!/bin/sh
# edit-convention-check.sh — Verify agent editing conventions are in place.
#
# Acceptance criteria:
#   1. docs/agent-editing-conventions.md exists and is non-empty.
#   2. AGENTS.md contains the heading `## File Editing Conventions`.
#   3. README.md contains a link to docs/agent-editing-conventions.md.
#
# Negative controls (must fail, exit non-zero):
#   - docs/agent-editing-conventions.md missing or empty
#   - AGENTS.md missing the heading
#   - README.md missing the link
#
# Runs from the repo root (checks.sh does `cd "$wt"` before invoking this
# script). All paths are relative to the repo root, never worktree-absolute.
#
# Exit 0 on success, non-zero on any violation.

set -eu

echo "=== edit-convention verification ==="

# 1. Conventions doc exists and is non-empty.
if [ ! -s "docs/agent-editing-conventions.md" ]; then
    echo "FAIL: docs/agent-editing-conventions.md missing or empty"
    exit 1
fi
echo "OK: docs/agent-editing-conventions.md present and non-empty"

# 2. AGENTS.md contains the conventions heading.
if ! grep -q '^## File Editing Conventions' AGENTS.md; then
    echo "FAIL: AGENTS.md missing heading '## File Editing Conventions'"
    exit 1
fi
echo "OK: AGENTS.md has '## File Editing Conventions' heading"

# 3. README.md links to the conventions doc.
if ! grep -q 'agent-editing-conventions' README.md; then
    echo "FAIL: README.md missing link to docs/agent-editing-conventions.md"
    exit 1
fi
echo "OK: README.md links to docs/agent-editing-conventions.md"

echo "=== edit-convention: PASS ==="
exit 0
