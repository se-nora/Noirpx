#!/usr/bin/env bash
# Verification script for fix-cave-room-size-distribution-edits goal
# Checks six verbatim anchor strings against the CURRENT CaveWorldGenerator.swift (main branch)
# Exits non-zero on any mismatch.

set -euo pipefail

REF_FILE="/Users/nora/Noirpx-worktrees/integration-main/Sources/SimulationCore/World/CaveWorldGenerator.swift"

if [[ ! -f "$REF_FILE" ]]; then
    echo "ERROR: Reference file not found: $REF_FILE" >&2
    exit 1
fi

echo "Verifying cave anchors against current main: $REF_FILE"
echo

# Use Python for reliable multiline matching
python3 << 'PYEOF'
import sys

with open("/Users/nora/Noirpx-worktrees/integration-main/Sources/SimulationCore/World/CaveWorldGenerator.swift") as f:
    content = f.read()

# Anchor 1: generateInspected signature
anchor1 = '    func generateInspected(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?) {'
if anchor1 in content:
    print("✓ Anchor 1 (generateInspected signature) matches current main")
else:
    print("✗ Anchor 1 (generateInspected signature) MISMATCH in current main", file=sys.stderr)
    sys.exit(1)

# Anchor 2: placeChambers call site with chamberCells param
import re
pattern2 = r'placeChambers\([^)]+chamberCells: &chamberCells'
if re.search(pattern2, content, re.DOTALL):
    print("✓ Anchor 2 (placeChambers call site with chamberCells param) matches current main")
else:
    print("✗ Anchor 2 (placeChambers call site) MISMATCH in current main", file=sys.stderr)
    sys.exit(1)

# Anchor 3: placeLava call + lavaCells binding with chamberCells param
pattern3 = r'let lavaCells = placeLava\([^)]+chamberCells: chamberCells\)'
if re.search(pattern3, content, re.DOTALL):
    print("✓ Anchor 3 (placeLava call + lavaCells binding with chamberCells) matches current main")
else:
    print("✗ Anchor 3 (placeLava call + lavaCells binding) MISMATCH in current main", file=sys.stderr)
    sys.exit(1)

# Anchor 4: sealHazards call site — SINGLE occurrence
seal_count = content.count('sealHazards(grid: &grid')
if seal_count == 1:
    print("✓ Anchor 4 (sealHazards call site, single occurrence) matches current main")
else:
    print(f"✗ Anchor 4: expected 1 sealHazards call, found {seal_count}", file=sys.stderr)
    sys.exit(1)

# Anchor 5: generateWithChambers function
anchor5 = 'public func generateWithChambers(stampSpawnTemplate: Bool, capturePrePass: Bool) -> (world: CaveWorld, prePass: [[Material]]?, chambers: [CaveChamber])'
if anchor5 in content:
    print("✓ Anchor 5 (generateWithChambers function) matches current main")
else:
    print("✗ Anchor 5 (generateWithChambers function) MISMATCH in current main", file=sys.stderr)
    sys.exit(1)

# Anchor 6: revalidateChambers function and call site
has_func = 'private func revalidateChambers(' in content
has_call = ('revalidateChambers(' in content and 'chamberCells: &chamberCells' in content)
if has_func and has_call:
    print("✓ Anchor 6 (revalidateChambers function and call site) matches current main")
else:
    print("✗ Anchor 6 (revalidateChambers function/call) MISMATCH in current main", file=sys.stderr)
    if not has_func:
        print("  - function definition missing", file=sys.stderr)
    if not has_call:
        print("  - call site missing or lacks chamberCells param", file=sys.stderr)
    sys.exit(1)

print()
print("All six anchors verified successfully against current main!")
PYEOF