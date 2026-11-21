#!/usr/bin/env bash
# Verification script for fix-cave-room-size-distribution-edits goal
# Checks six verbatim anchor strings against the REFERENCE CaveWorldGenerator.swift (26fcdfd working version)
# Exits non-zero on any mismatch.

set -euo pipefail

REF_FILE="/Users/nora/Noirpx-worktrees/cave-room-size-distribution/Sources/SimulationCore/World/CaveWorldGenerator.swift"

if [[ ! -f "$REF_FILE" ]]; then
    echo "ERROR: Reference file not found: $REF_FILE" >&2
    exit 1
fi

echo "Verifying cave anchors against reference: $REF_FILE"
echo

# Anchor 1: generateInspected signature
ANCHOR1='    func generateInspected(stampSpawnTemplate: Bool, capturePrePass: Bool, capturePostTemplate: Bool = false) -> (world: CaveWorld, prePass: [[Material]]?, postTemplate: [[Material]]?, chambers: [CaveChamber]) {'
if grep -q -F "$ANCHOR1" "$REF_FILE"; then
    echo "✓ Anchor 1 (generateInspected signature) matches reference"
else
    echo "✗ Anchor 1 (generateInspected signature) MISMATCH in reference" >&2
    echo "Expected:" >&2
    echo "$ANCHOR1" >&2
    echo "Found in reference:" >&2
    grep -n 'func generateInspected' "$REF_FILE" | head -1 | cut -d: -f2- >&2
    exit 1
fi

# Anchor 2: placeChambers call site
ANCHOR2='        placeChambers(
            grid: &grid,
            w: w, h: h,
            biomeConfig: biomeConfig,
            originX: originX, originY: originY,
            seed: seed,
            layout: layout,
            placedChambers: &placedChambers
        )'
# Use sed to extract the exact block from reference
ACTUAL2=$(sed -n '758,766p' "$REF_FILE")
if [[ "$ACTUAL2" == "$ANCHOR2" ]]; then
    echo "✓ Anchor 2 (placeChambers call site) matches reference"
else
    echo "✗ Anchor 2 (placeChambers call site) MISMATCH in reference" >&2
    echo "Expected:" >&2
    echo "$ANCHOR2" >&2
    echo "Found in reference (lines 758-766):" >&2
    echo "$ACTUAL2" >&2
    exit 1
fi

# Anchor 3: placeLava call + lavaCells binding
ANCHOR3='        let lavaCells = placeLava(grid: &grid, width: w, height: h, originX: originX, originY: originY,
                                  tunnelCells: tunnelCells, spawn: spawnCell, goal: goalCell, budget: &budget)'
ACTUAL3=$(sed -n '857,858p' "$REF_FILE")
if [[ "$ACTUAL3" == "$ANCHOR3" ]]; then
    echo "✓ Anchor 3 (placeLava call + lavaCells binding) matches reference"
else
    echo "✗ Anchor 3 (placeLava call + lavaCells binding) MISMATCH in reference" >&2
    echo "Expected:" >&2
    echo "$ANCHOR3" >&2
    echo "Found in reference (lines 857-858):" >&2
    echo "$ACTUAL3" >&2
    exit 1
fi

# Anchor 4: sealHazards call sites (TWO occurrences)
ANCHOR4A='        sealHazards(grid: &grid, width: w, height: h,
                    lavaCells: lavaCells, gunpowderCells: gunpowderCells)'
ANCHOR4B='            sealHazards(grid: &grid, width: w, height: h,
                        lavaCells: lavaCells, gunpowderCells: gunpowderCells)'

ACTUAL4A=$(sed -n '869,870p' "$REF_FILE")
ACTUAL4B=$(sed -n '878,879p' "$REF_FILE")

if [[ "$ACTUAL4A" == "$ANCHOR4A" && "$ACTUAL4B" == "$ANCHOR4B" ]]; then
    echo "✓ Anchor 4 (sealHazards call sites, both occurrences) match reference"
else
    echo "✗ Anchor 4 (sealHazards call sites) MISMATCH in reference" >&2
    echo "Expected first (lines 869-870):" >&2
    echo "$ANCHOR4A" >&2
    echo "Found first:" >&2
    echo "$ACTUAL4A" >&2
    echo "Expected second (lines 878-879):" >&2
    echo "$ANCHOR4B" >&2
    echo "Found second:" >&2
    echo "$ACTUAL4B" >&2
    exit 1
fi

# Anchor 5: generateWithChambers function
ANCHOR5='    internal func generateWithChambers(
        stampSpawnTemplate: Bool = true,
        capturePrePass: Bool = false,
        capturePostTemplate: Bool = false
    ) -> (world: CaveWorld, prePass: [[Material]]?, postTemplate: [[Material]]?, chambers: [CaveChamber]) {
        let (world, prePass, postTemplate, chambers) = generateInspected(stampSpawnTemplate: stampSpawnTemplate, capturePrePass: capturePrePass, capturePostTemplate: capturePostTemplate)
        return (world, prePass, postTemplate, chambers)
    }'
ACTUAL5=$(sed -n '2431,2438p' "$REF_FILE")
if [[ "$ACTUAL5" == "$ANCHOR5" ]]; then
    echo "✓ Anchor 5 (generateWithChambers function) matches reference"
else
    echo "✗ Anchor 5 (generateWithChambers function) MISMATCH in reference" >&2
    echo "Expected (lines 2431-2438):" >&2
    echo "$ANCHOR5" >&2
    echo "Found:" >&2
    echo "$ACTUAL5" >&2
    exit 1
fi

# Anchor 6: Inline chamber revalidation block
ANCHOR6_COMMENT='            // Post-pass chamber revalidation: check safety radius against FINAL spawn/goal.'
ACTUAL6_COMMENT=$(sed -n '892p' "$REF_FILE")
if [[ "$ACTUAL6_COMMENT" == "$ANCHOR6_COMMENT" ]]; then
    echo "✓ Anchor 6 (inline chamber revalidation block) comment matches reference"
else
    echo "✗ Anchor 6 (inline chamber revalidation block) comment MISMATCH in reference" >&2
    echo "Expected (line 892):" >&2
    echo "$ANCHOR6_COMMENT" >&2
    echo "Found:" >&2
    echo "$ACTUAL6_COMMENT" >&2
    exit 1
fi

# Verify the if block structure at line 897
ANCHOR6_IF='            if !placedChambers.isEmpty {'
ACTUAL6_IF=$(sed -n '897p' "$REF_FILE")
if [[ "$ACTUAL6_IF" == "$ANCHOR6_IF" ]]; then
    echo "✓ Anchor 6 (inline chamber revalidation block) if structure matches reference"
else
    echo "✗ Anchor 6 (inline chamber revalidation block) if structure MISMATCH in reference" >&2
    echo "Expected (line 897):" >&2
    echo "$ANCHOR6_IF" >&2
    echo "Found:" >&2
    echo "$ACTUAL6_IF" >&2
    exit 1
fi

echo
echo "All six anchors verified successfully against reference (26fcdfd)!"
exit 0