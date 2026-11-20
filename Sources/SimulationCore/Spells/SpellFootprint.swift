/// Deterministic deposition pattern for spell impact. Pure function of impact cell + blueprint.
public struct SpellFootprint: Equatable, Sendable {
    public let id: String                    // stable key, e.g. "firebolt_impact"
    public let cells: [SpellFootprintCell]   // relative offsets + materials from impact center
    public let maxCells: Int                 // ≤ SpellFootprint.maxFootprintCells (37)

    public init(id: String, cells: [SpellFootprintCell]) {
        precondition(cells.count <= SpellFootprint.maxFootprintCells,
                     "Footprint cells (\(cells.count)) exceed maximum (\(SpellFootprint.maxFootprintCells))")
        self.id = id
        self.cells = cells
        self.maxCells = cells.count
    }

    /// Single source of truth for max footprint cells across the system.
    public static let maxFootprintCells: Int = 37

    /// Returns absolute cells for a given impact position.
    /// Rejects any cell overlapping the character body (consistent with CaveRun.paint rejection).
    public func resolve(impact: CellPosition, characterBody: Set<CellPosition>?) -> [ResolvedFootprintCell] {
        var result: [ResolvedFootprintCell] = []
        result.reserveCapacity(cells.count)

        for cell in cells {
            let absolute = CellPosition(x: impact.x + cell.offset.x, y: impact.y + cell.offset.y)

            // Reject cells overlapping the character body
            if let body = characterBody, body.contains(absolute) {
                continue
            }

            result.append(ResolvedFootprintCell(cell: absolute, material: cell.material, isPrimary: cell.isPrimary))
        }
        return result
    }
}

/// Single source cell within a spell footprint (relative to impact center).
public struct SpellFootprintCell: Equatable, Sendable {
    public let offset: CellPosition     // relative to impact cell (0,0) = impact center
    public let material: Material
    public let isPrimary: Bool          // true = primaryMaterial, false = secondary/trail

    public init(offset: CellPosition, material: Material, isPrimary: Bool = true) {
        self.offset = offset
        self.material = material
        self.isPrimary = isPrimary
    }
}

/// A resolved footprint cell with absolute position.
public struct ResolvedFootprintCell: Equatable, Sendable {
    public let cell: CellPosition
    public let material: Material
    public let isPrimary: Bool

    public init(cell: CellPosition, material: Material, isPrimary: Bool) {
        self.cell = cell
        self.material = material
        self.isPrimary = isPrimary
    }
}