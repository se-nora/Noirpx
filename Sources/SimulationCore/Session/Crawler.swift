/// Crawler-specific AI, movement, and hazard handling for a ``Creature``.
///
/// The AI is a deterministic state machine (`idle → wander → chase → attack`)
/// driven by the completed tick and the player position. It never reads the
/// wall clock and never mutates the world directly; death blood is scheduled by
/// the owning ``CaveRun`` through the ordinary material command path.
extension Creature {
    public struct TickResult: Equatable, Sendable {
        /// Damage the creature took from hazardous materials this tick.
        public var materialDamage: Int = 0
        /// Whether the creature's body overlaps the character body this tick.
        public var contact: Bool = false
        /// Whether the creature died this tick (health, hazard, or unsupported).
        public var died: Bool = false
    }

    /// Ticks the crawler idles before switching to wander.
    static let idleTicksBeforeWander = 120
    /// Ticks the crawler wanders without seeing the player before idling again.
    static let wanderTicksBeforeIdle = 300
    /// Ticks the crawler chases a player beyond `loseInterestRadius` before giving up.
    static let chaseTicksBeforeGivingUp = 60

    /// Advances the creature one gameplay tick.
    ///
    /// - Parameters:
    ///   - bounds: Valid x coordinates for the creature's body.
    ///   - materialAt: Material lookup for the completed tick.
    ///   - characterPosition: The character's lower-left cell.
    ///   - characterBody: The cells occupied by the character.
    @discardableResult
    public mutating func advance(bounds: ClosedRange<Int>,
                                 materialAt: (CellPosition) -> Material,
                                 characterPosition: CellPosition,
                                 characterBody: Set<CellPosition>) -> TickResult {
        var result = TickResult()
        guard alive else { return result }

        if damageCooldown > 0 { damageCooldown -= 1 }

        // Ground-bound creatures buried by terrain or left without support die.
        guard canStand(at: position, bounds: bounds, materialAt: materialAt) else {
            remove()
            result.died = true
            return result
        }

        let cells = bodyCells

        // Scan the body for hazards and water before moving.
        var hazard: Hazard?
        var inWater = false
        for cell in cells {
            switch materialAt(cell) {
            case .fire: hazard = heavier(hazard, .fire)
            case .lava: hazard = heavier(hazard, .lava)
            case .acid: hazard = heavier(hazard, .acid)
            case .water: inWater = true
            default: break
            }
        }
        if inWater { burning = false }

        // Decide the next state from the player's position.
        updateState(cells: cells, characterPosition: characterPosition, characterBody: characterBody)

        // Move on the cadence for active states.
        phase += 1
        if state == .wander || state == .chase, phase % moveInterval == 0 {
            step(bounds: bounds, materialAt: materialAt, characterPosition: characterPosition)
        }

        // Apply material damage at the (possibly new) position.
        if let hazard {
            if damageCooldown == 0 {
                damageCooldown = materialDamageCooldown
                health = max(0, health - hazard.damage)
                lastDamageSource = .material
                burning = hazard.ignites
                result.materialDamage = hazard.damage
                if health == 0 {
                    remove()
                    result.died = true
                    return result
                }
            } else if hazard.ignites {
                burning = true
            }
        }

        // Contact is evaluated after movement so a stepped-into player is hit.
        let contact = bodyCells.contains { characterBody.contains($0) }
        result.contact = contact
        if contact, state == .chase {
            state = .attack
            stateTicks = 0
        } else if !contact, state == .attack {
            state = .chase
            stateTicks = 0
        }

        return result
    }

    // MARK: - Internals

    private mutating func updateState(cells: [CellPosition],
                                      characterPosition: CellPosition,
                                      characterBody: Set<CellPosition>) {
        let distance = chebyshev(center, characterCenter(characterPosition))
        let seesPlayer = distance <= detectionRadius
        let melee = cells.contains { characterBody.contains($0) }

        switch state {
        case .dead:
            return
        case .idle:
            if seesPlayer {
                state = .chase
                stateTicks = 0
            } else {
                stateTicks += 1
                if stateTicks >= Self.idleTicksBeforeWander {
                    direction = -direction
                    state = .wander
                    stateTicks = 0
                }
            }
        case .wander:
            if seesPlayer {
                state = .chase
                stateTicks = 0
            } else {
                stateTicks += 1
                if stateTicks >= Self.wanderTicksBeforeIdle {
                    state = .idle
                    stateTicks = 0
                }
            }
        case .chase:
            if melee {
                state = .attack
                stateTicks = 0
            } else if distance > loseInterestRadius {
                stateTicks += 1
                if stateTicks >= Self.chaseTicksBeforeGivingUp {
                    state = .wander
                    stateTicks = 0
                }
            } else {
                stateTicks = 0
            }
        case .attack:
            if !melee {
                state = .chase
                stateTicks = 0
            }
        }
    }

    private mutating func step(bounds: ClosedRange<Int>,
                               materialAt: (CellPosition) -> Material,
                               characterPosition: CellPosition) {
        var moveDirection = direction
        if state == .chase {
            let dx = characterCenter(characterPosition).x - center.x
            moveDirection = dx == 0 ? 0 : (dx > 0 ? 1 : -1)
            if moveDirection != 0 { direction = moveDirection }
        }
        guard moveDirection != 0 else { return }

        let candidate = CellPosition(x: position.x + moveDirection, y: position.y)
        if canStand(at: candidate, bounds: bounds, materialAt: materialAt) {
            position = candidate
        } else if state == .wander {
            // Reverse at a wall or ledge so the patrol does not stall.
            direction = -direction
        }
    }

    private func canStand(at p: CellPosition,
                          bounds: ClosedRange<Int>,
                          materialAt: (CellPosition) -> Material) -> Bool {
        for dx in 0..<width {
            let x = p.x + dx
            guard bounds.contains(x) else { return false }
            guard materialAt(CellPosition(x: x, y: p.y - 1)).blocksCharacter else { return false }
            for dy in 0..<height where materialAt(CellPosition(x: x, y: p.y + dy)).blocksCharacter {
                return false
            }
        }
        return true
    }

    private func chebyshev(_ a: CellPosition, _ b: CellPosition) -> Int {
        max(abs(a.x - b.x), abs(a.y - b.y))
    }

    private func characterCenter(_ position: CellPosition) -> CellPosition {
        CellPosition(x: position.x + FixtureCharacter.width / 2,
                     y: position.y + FixtureCharacter.height / 2)
    }

    private func heavier(_ current: Hazard?, _ candidate: Hazard) -> Hazard {
        guard let current else { return candidate }
        return candidate.damage > current.damage ? candidate : current
    }
}