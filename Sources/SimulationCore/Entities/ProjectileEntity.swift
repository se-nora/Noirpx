import Foundation

/// A simulated projectile entity that advances in the fixed tick loop.
public struct ProjectileEntity: Sendable {
    public let id: UInt64
    public let blueprintId: String
    public var position: FixedPoint
    public var velocity: FixedPoint
    public let gravityFactor: GravityFactor
    public let maxSpeed: ProjectileSpeed
    public var lifetimeTicks: UInt16
    public private(set) var age: UInt16 = 0
    public private(set) var hasImpacted: Bool = false
    /// Cells the projectile traversed during the most recent advance, including
    /// the origin cell and the terminal (impact or destination) cell.
    /// Session-only data for creature hit detection; not part of any snapshot.
    public private(set) var lastPath: [CellPosition] = []

    public init(id: UInt64,
                blueprintId: String,
                position: FixedPoint,
                velocity: FixedPoint,
                gravityFactor: GravityFactor,
                maxSpeed: ProjectileSpeed,
                lifetimeTicks: UInt16) {
        self.id = id
        self.blueprintId = blueprintId
        self.position = position
        self.velocity = velocity
        self.gravityFactor = gravityFactor
        self.maxSpeed = maxSpeed
        self.lifetimeTicks = lifetimeTicks
    }

    /// Advances the projectile by one simulation tick.
    /// Returns the impact cell if the projectile collided with a blocking material
    /// or the world edge, or nil if it is still moving or has expired.
    mutating func advance(canVisit: (CellPosition) -> Bool,
                          materialAt: (CellPosition) -> Material) -> CellPosition? {
        guard !hasImpacted, lifetimeTicks > 0 else { return nil }

        let fromCell = position.cell()
        lifetimeTicks -= 1
        age += 1

        // Compute new position: position += velocity (velocity components are
        // bounded by speed by construction: distance = max(|dx|, |dy|)).
        let newPosition = FixedPoint(
            x: position.x &+ velocity.x,
            y: position.y &+ velocity.y
        )

        // Apply gravity AFTER movement (y increases upward in world coords);
        // affects the next tick's velocity.
        if gravityFactor > 0 {
            velocity.y = velocity.y &- Int32(gravityFactor)
        }

        // Bresenham line from fromCell to newPosition.cell() for collision
        let toCell = newPosition.cell()

        // If position didn't change cell, just update position and continue
        if fromCell == toCell {
            position = newPosition
            lastPath = [fromCell]
            return nil
        }

        // Clear path for this tick
        lastPath.removeAll(keepingCapacity: true)
        lastPath.append(fromCell)

        // Check each cell along the Bresenham segment for collision
        let collisionCell = bresenhamCollision(from: fromCell, to: toCell,
                                               canVisit: canVisit, materialAt: materialAt,
                                               path: &lastPath)

        if let hitCell = collisionCell {
            // Impact! Clamp position to the impact cell center (Q8)
            position = FixedPoint.fromCells(x: hitCell.x, y: hitCell.y)
            hasImpacted = true
            return hitCell
        } else {
            // No collision, update position
            position = newPosition
            return nil
        }
    }

    /// Bresenham line algorithm with collision detection against blocking materials.
    /// Returns the first blocking cell encountered, or nil if none.
    private func bresenhamCollision(from: CellPosition, to: CellPosition,
                                     canVisit: (CellPosition) -> Bool,
                                     materialAt: (CellPosition) -> Material,
                                     path: inout [CellPosition]) -> CellPosition? {
        var x = from.x
        var y = from.y
        let dx = abs(to.x - from.x)
        let dy = abs(to.y - from.y)
        let sx = from.x < to.x ? 1 : -1
        let sy = from.y < to.y ? 1 : -1
        var err = dx - dy

        while true {
            let cell = CellPosition(x: x, y: y)
            path.append(cell)

            // Skip the starting cell (already occupied by projectile origin)
            if cell != from {
                // Check world bounds
                if !canVisit(cell) {
                    return cell // hit world edge
                }

                // Check material collision
                let material = materialAt(cell)
                if material.blocksCharacter {
                    return cell
                }
            }

            if x == to.x && y == to.y { break }

            let e2 = 2 * err
            if e2 > -dy {
                err -= dy
                x += sx
            }
            if e2 < dx {
                err += dx
                y += sy
            }
        }

        return nil
    }

    /// Creates a snapshot for rendering/presentation.
    func snapshot() -> ProjectileSnapshot {
        ProjectileSnapshot(from: self)
    }

    /// Advances a digging projectile one tick along its Bresenham flight path.
    /// Removes soft materials (sand, ice, slime, gunpowder) as it passes, passes
    /// through empty and non-diggable materials, and stops at the first `.solid`
    /// cell or world edge without leaving a footprint.
    ///
    /// - Parameters:
    ///   - canVisit: Bounds check closure (`isInBounds` for digging; world edge = stop).
    ///   - materialAt: Material lookup closure.
    ///   - blueprint: The projectile's blueprint (must have `.digging` flag).
    ///   - moved: Output set receiving dug cells so the tick pass can union them.
    /// - Returns: `(impactCell, dugCells)` where `impactCell` is non-nil when the
    ///   projectile stopped (rock or edge) and should be removed; `dugCells` are
    ///   cells emptied by digging this tick.
    mutating func advanceDigging(
        canVisit: (CellPosition) -> Bool,
        materialAt: (CellPosition) -> Material,
        blueprint: ProjectileBlueprint,
        moved: inout Set<CellPosition>
    ) -> (impactCell: CellPosition?, dugCells: [CellPosition]) {
        guard !hasImpacted, lifetimeTicks > 0 else { return (nil, []) }

        let fromCell = position.cell()
        lifetimeTicks -= 1
        age += 1

        // Compute new position: position += velocity
        let newPosition = FixedPoint(
            x: position.x &+ velocity.x,
            y: position.y &+ velocity.y
        )

        // Apply gravity AFTER movement; affects the next tick's velocity.
        if blueprint.gravityFactor > 0 {
            velocity.y = velocity.y &- Int32(blueprint.gravityFactor)
        }

        let toCell = newPosition.cell()
        if fromCell == toCell {
            position = newPosition
            return (nil, [])
        }

        // Bresenham iteration from fromCell (exclusive) to toCell (inclusive)
        var x = fromCell.x
        var y = fromCell.y
        let dx = abs(toCell.x - fromCell.x)
        let dy = abs(toCell.y - fromCell.y)
        let sx = fromCell.x < toCell.x ? 1 : -1
        let sy = fromCell.y < toCell.y ? 1 : -1
        var err = dx - dy

        var dugCells: [CellPosition] = []
        let diggable: Set<Material> = [.sand, .ice, .slime, .gunpowder]

        while true {
            let cell = CellPosition(x: x, y: y)

            if cell != fromCell {
                if !canVisit(cell) {
                    // World edge: stop at edge cell, remove projectile, no footprint.
                    position = FixedPoint.fromCells(x: cell.x, y: cell.y)
                    hasImpacted = true
                    moved.formUnion(dugCells)
                    return (cell, dugCells)
                }

                let material = materialAt(cell)

                // Indestructible guard: sanctuary walls stop digging like solid rock.
                if material.isIndestructible {
                    position = FixedPoint.fromCells(x: cell.x, y: cell.y)
                    hasImpacted = true
                    moved.formUnion(dugCells)
                    return (cell, dugCells)
                }

                if diggable.contains(material) {
                    dugCells.append(cell)
                } else if material == .solid {
                    // Rock: stop at rock cell, rock unchanged, no footprint.
                    position = FixedPoint.fromCells(x: cell.x, y: cell.y)
                    hasImpacted = true
                    moved.formUnion(dugCells)
                    return (cell, dugCells)
                }
                // else: pass through empty, water, fire, lava, etc.
            }

            if x == toCell.x && y == toCell.y { break }

            let e2 = 2 * err
            if e2 > -dy { err -= dy; x += sx }
            if e2 < dx  { err += dx; y += sy }
        }

        position = newPosition
        moved.formUnion(dugCells)
        return (nil, dugCells)
    }
}