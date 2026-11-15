/// Pure internal template for the cave spawn pad and shaft.
/// Contains constants, layout geometry, and the shaft termination rule.
/// No stamping code; the generator calls into this file.
internal enum CaveSpawnTemplate {
    // MARK: - Constants

    /// Character body width (5 cells).
    static let bodyWidth = FixtureCharacter.width
    /// Character body height (9 cells).
    static let bodyHeight = FixtureCharacter.height
    /// Headroom above the body inside the room (3 cells).
    static let headroom = 3
    /// Wall thickness around the shaft (2 cells).
    static let wallThickness = 2
    /// Shaft interior width (7 cells).
    static let shaftWidth = 7
    /// Left column of the shaft band (8).
    static let shaftLeft = 8
    /// Left column of the body (17 = shaftLeft + shaftWidth + wallThickness).
    static let bodyLeft = shaftLeft + shaftWidth + wallThickness
    /// Rows from top border down to the pad floor (23).
    static let topInset = 23
    /// Clearance radius around room and shaft interiors (6 cells Chebyshev).
    static let clearanceRadius = 6
    /// Minimum carved shaft depth including the opening row (32).
    static let minShaftDepth = 32
    /// Maximum carved shaft depth (48).
    static let maxShaftDepth = 48
    /// Minimum rows between cap row and bottom border (2).
    static let minBottomMargin = 2

    // MARK: - Layout

    /// Precomputed layout for a given world size.
    /// Returns nil when the template does not fit (width < 30 or height < 56).
    struct Layout: Sendable {
        let width: Int
        let height: Int
        let originX: Int
        let originY: Int
        /// Pad floor row (grid row index).
        let padFloorRow: Int
        /// Body occupies rows padFloorRow+1 ... padFloorRow+bodyHeight.
        let bodyTopRow: Int
        /// Headroom occupies rows bodyTopRow+bodyHeight ... bodyTopRow+bodyHeight+headroom-1.
        let headroomTopRow: Int
        /// Ceiling rows (2 rows solid above headroom).
        let ceilingBottomRow: Int
        /// Shaft band columns (inclusive).
        let shaftLeftCol: Int
        let shaftRightCol: Int
        /// Flank wall columns (inclusive pairs).
        let leftFlankLeft: Int
        let leftFlankRight: Int
        let rightFlankLeft: Int
        let rightFlankRight: Int
        /// Right wall columns (inclusive).
        let rightWallLeft: Int
        let rightWallRight: Int
        /// Body columns (inclusive).
        let bodyLeftCol: Int
        let bodyRightCol: Int
        /// Room interior columns (inclusive).
        let roomLeftCol: Int
        let roomRightCol: Int
        /// Room interior rows (inclusive).
        let roomBottomRow: Int
        let roomTopRow: Int
        /// Shaft carve bottom row (determined by termination scan).
        let carveBottomRow: Int
        /// Flank wall bottom row (one above carveBottomRow for open, capRow-1 for cap).
        let wallBottomRow: Int
        /// Termination row for cap case (clamped to >= 2).
        let capRow: Int
        /// Minimum bottom row for open-end scan (padFloorRow - minShaftDepth - 1).
        let minBottomRow: Int
        /// Spawn cell in grid coordinates.
        let spawnCell: (Int, Int)
        /// Maximal footprint (union of dilated room and shaft rects, clipped to 1...w-2 by 1...h-2).
        let maximalFootprint: Set<Int>
        /// Descent in cells from body bottom to shaft end.
        let descent: Int
        /// Whether the termination is an open cave (.openCave) or a cap (.cap).
        let terminationKind: Termination.Kind

        /// Grid row to world Y conversion.
        func worldY(_ gy: Int) -> Int { originY + gy }
        /// Grid column to world X conversion.
        func worldX(_ gx: Int) -> Int { originX + gx }
    }

    /// Termination result from scanning the unmodified grid.
    struct Termination: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case openCave, cap }
        let kind: Kind
        let carveBottomRow: Int
        let wallBottomRow: Int
        let descent: Int
    }

    /// Computes the layout for the given world size.
    /// Returns nil when width < 30 or height < 56.
    static func layout(width: Int, height: Int) -> Layout? {
        guard width >= 30, height >= 56 else { return nil }

        let originX = -width / 2
        let originY = -height / 2
        let pf = height - topInset // padFloorRow

        // Derived row indices
        let bodyTopRow = pf + 1
        let headroomTopRow = bodyTopRow + bodyHeight // pf + 10
        let ceilingBottomRow = headroomTopRow + headroom + 1 // pf + 14 (inclusive)

        // Column constants
        let shaftLeftCol = shaftLeft // 8
        let shaftRightCol = shaftLeft + shaftWidth - 1 // 14
        let leftFlankLeft = shaftLeftCol - wallThickness // 6
        let leftFlankRight = shaftLeftCol - 1 // 7
        let rightFlankLeft = shaftRightCol + 1 // 15
        let rightFlankRight = shaftRightCol + wallThickness // 16
        let rightWallLeft = bodyLeft + bodyWidth + wallThickness // 22
        let rightWallRight = rightWallLeft + wallThickness - 1 // 23
        let bodyLeftCol = bodyLeft // 17
        let bodyRightCol = bodyLeft + bodyWidth - 1 // 21
        let roomLeftCol = shaftLeftCol // 8
        let roomRightCol = rightWallRight // 23? No, room interior is 8...21 per spec.
        // Room interior cols 8...21 (shaft band + wall + body)
        let roomRightColInterior = bodyRightCol // 21
        let roomBottomRow = bodyTopRow // pf + 1
        let roomTopRow = ceilingBottomRow - 1 // pf + 12

        let minBottomRow = pf - minShaftDepth - 1
        let capRow = max(pf - maxShaftDepth - 1, minBottomMargin) // clamp to >= 2

        // Maximal footprint: dilate room rect and shaft rect by clearanceRadius, clip to interior
        var footprint = Set<Int>()
        let roomRectCols = roomLeftCol...roomRightColInterior
        let roomRectRows = roomBottomRow...roomTopRow
        let shaftRectCols = shaftLeftCol...shaftRightCol
        // Shaft rect rows will use capRow as the bottom (maximal)
        let shaftRectRows = capRow...pf

        func dilateAndAdd(cols: ClosedRange<Int>, rows: ClosedRange<Int>) {
            for gx in (cols.lowerBound - clearanceRadius)...(cols.upperBound + clearanceRadius) {
                for gy in (rows.lowerBound - clearanceRadius)...(rows.upperBound + clearanceRadius) {
                    guard gx >= 1, gx <= width - 2, gy >= 1, gy <= height - 2 else { continue }
                    footprint.insert(gy * width + gx)
                }
            }
        }
        dilateAndAdd(cols: roomRectCols, rows: roomRectRows)
        dilateAndAdd(cols: shaftRectCols, rows: shaftRectRows)

        let spawnCell = (bodyLeftCol, bodyTopRow) // (17, pf+1)

        // We don't know termination yet; pass placeholder, will be overwritten by caller after scan.
        return Layout(
            width: width,
            height: height,
            originX: originX,
            originY: originY,
            padFloorRow: pf,
            bodyTopRow: bodyTopRow,
            headroomTopRow: headroomTopRow,
            ceilingBottomRow: ceilingBottomRow,
            shaftLeftCol: shaftLeftCol,
            shaftRightCol: shaftRightCol,
            leftFlankLeft: leftFlankLeft,
            leftFlankRight: leftFlankRight,
            rightFlankLeft: rightFlankLeft,
            rightFlankRight: rightFlankRight,
            rightWallLeft: rightWallLeft,
            rightWallRight: rightWallRight,
            bodyLeftCol: bodyLeftCol,
            bodyRightCol: bodyRightCol,
            roomLeftCol: roomLeftCol,
            roomRightCol: roomRightColInterior,
            roomBottomRow: roomBottomRow,
            roomTopRow: roomTopRow,
            carveBottomRow: capRow, // placeholder
            wallBottomRow: capRow - 1, // placeholder
            capRow: capRow,
            minBottomRow: minBottomRow,
            spawnCell: spawnCell,
            maximalFootprint: footprint,
            descent: 0, // placeholder
            terminationKind: .cap // placeholder
        )
    }

    /// Scans the unmodified grid for a full-width two-row opening in the shaft band.
    /// - Parameters:
    ///   - layout: The precomputed layout (must have valid capRow, minBottomRow, shaft band columns).
    ///   - isEmpty: A closure that returns true if the cell at (col, row) in the unmodified grid is .empty.
    /// - Returns: Termination with kind, carveBottomRow, wallBottomRow, and descent.
    static func termination(layout: Layout, isEmpty: (_ col: Int, _ row: Int) -> Bool) -> Termination {
        // Scan from minBottomRow down to capRow (inclusive)
        for r in stride(from: layout.minBottomRow, through: layout.capRow, by: -1) {
            var allEmpty = true
            for c in layout.shaftLeftCol...layout.shaftRightCol {
                if !isEmpty(c, r) || !isEmpty(c, r - 1) {
                    allEmpty = false
                    break
                }
            }
            if allEmpty {
                // Open cave at row r (the upper row of the two-row opening)
                let carveBottomRow = r
                let wallBottomRow = r + 1
                let descent = layout.padFloorRow + 1 - r
                return Termination(kind: .openCave, carveBottomRow: carveBottomRow, wallBottomRow: wallBottomRow, descent: descent)
            }
        }
        // No opening found: cap case
        let carveBottomRow = layout.capRow
        let wallBottomRow = layout.capRow - 1
        let descent = layout.padFloorRow + 1 - layout.capRow
        return Termination(kind: .cap, carveBottomRow: carveBottomRow, wallBottomRow: wallBottomRow, descent: descent)
    }
}