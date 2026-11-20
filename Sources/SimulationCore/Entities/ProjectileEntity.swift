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
}