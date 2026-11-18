import Foundation
import SimulationCore

/// A scenario defines initial conditions and auto-advance policy for animation capture.
public struct Scenario {
    public let id: String
    public let name: String
    public let description: String
    public let seed: UInt64
    public let initialCommands: [SimulationCommand]
    public let autoPolicy: AutoPolicy
    public let viewportCenter: CellPosition
    public let longEdgeCells: Int

    public init(
        id: String,
        name: String,
        description: String,
        seed: UInt64 = 42,
        initialCommands: [SimulationCommand] = [],
        autoPolicy: AutoPolicy = .moveRight,
        viewportCenter: CellPosition = CellPosition(x: 0, y: 0),
        longEdgeCells: Int = 200
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.seed = seed
        self.initialCommands = initialCommands
        self.autoPolicy = autoPolicy
        self.viewportCenter = viewportCenter
        self.longEdgeCells = longEdgeCells
    }
}

/// Auto-advance policies for simulation ticks.
public enum AutoPolicy: Equatable {
    /// No automatic commands; simulation runs with only initial commands
    case none
    /// Move right each tick (for horizontal courses)
    case moveRight
    /// Move right, jump periodically (for BeaconRun-like courses)
    case moveRightJump(interval: Int = 60)
    /// Full BeaconRun auto-play (move right, jump at gaps, pulse periodically)
    case beaconRun
    /// CaveRun auto-play (move right, jump occasionally)
    case caveRun
    /// Custom policy defined by a closure (not encodable)
    case custom((_ tick: Int, _ state: ScenarioState) -> AutoCommands)

    /// Commands to apply for a single tick
    public struct AutoCommands {
        public let horizontal: Int
        public let jump: Bool
        public let pulse: Bool
        public let paintCommands: [SimulationCommand]

        public init(horizontal: Int = 0, jump: Bool = false, pulse: Bool = false, paintCommands: [SimulationCommand] = []) {
            self.horizontal = horizontal
            self.jump = jump
            self.pulse = pulse
            self.paintCommands = paintCommands
        }
    }

    /// State available to custom policies
    public struct ScenarioState {
        public let tick: Int
        public let characterPosition: CellPosition?
        public let outcome: BeaconRun.Outcome?
        public let health: Int?
    }

    public static func == (lhs: AutoPolicy, rhs: AutoPolicy) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.moveRight, .moveRight): return true
        case (.moveRightJump(let a), .moveRightJump(let b)): return a == b
        case (.beaconRun, .beaconRun): return true
        case (.caveRun, .caveRun): return true
        case (.custom, .custom): return false // Cannot compare closures
        default: return false
        }
    }
}

/// Built-in scenarios mapped from existing test cases
public enum BuiltInScenario {
    nonisolated(unsafe) public static let all: [Scenario] = [
        // MaterialBehaviorTests
        Scenario(
            id: "sand-water-displacement",
            name: "Sand-Water Displacement",
            description: "Sand falling into water demonstrates liquid displacement",
            seed: 1,
            initialCommands: [
                SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 10), material: .sand),
                SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 0), material: .water),
            ],
            autoPolicy: .none,
            viewportCenter: CellPosition(x: 0, y: 5),
            longEdgeCells: 50
        ),
        Scenario(
            id: "fire-water-reaction",
            name: "Fire-Water Reaction",
            description: "Fire meeting water creates steam",
            seed: 2,
            initialCommands: [
                SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 0), material: .fire),
                SimulationCommand(tick: 1, position: CellPosition(x: 1, y: 0), material: .water),
            ],
            autoPolicy: .none,
            viewportCenter: CellPosition(x: 0, y: 0),
            longEdgeCells: 50
        ),
        Scenario(
            id: "sand-movement",
            name: "Sand Movement",
            description: "Sand falling and piling",
            seed: 3,
            initialCommands: [
                SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 20), material: .sand),
                SimulationCommand(tick: 1, position: CellPosition(x: 1, y: 20), material: .sand),
                SimulationCommand(tick: 1, position: CellPosition(x: -1, y: 20), material: .sand),
            ],
            autoPolicy: .none,
            viewportCenter: CellPosition(x: 0, y: 10),
            longEdgeCells: 50
        ),

        // MaterialExpansionTests
        Scenario(
            id: "lava-water-reaction",
            name: "Lava-Water Reaction",
            description: "Lava solidifies to rock, water becomes steam",
            seed: 2,
            initialCommands: [
                SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 0), material: .lava),
                SimulationCommand(tick: 1, position: CellPosition(x: 1, y: 0), material: .water),
            ],
            autoPolicy: .none,
            viewportCenter: CellPosition(x: 0, y: 0),
            longEdgeCells: 50
        ),
        Scenario(
            id: "gunpowder-explosion",
            name: "Gunpowder Explosion",
            description: "Gunpowder ignited by fire explodes",
            seed: 7,
            initialCommands: [
                SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 0), material: .gunpowder),
                SimulationCommand(tick: 1, position: CellPosition(x: 1, y: 0), material: .fire),
            ],
            autoPolicy: .none,
            viewportCenter: CellPosition(x: 0, y: 0),
            longEdgeCells: 50
        ),
        Scenario(
            id: "acid-movement",
            name: "Acid Movement",
            description: "Acid moves like water",
            seed: 4,
            initialCommands: [
                SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 10), material: .acid),
                SimulationCommand(tick: 1, position: CellPosition(x: 0, y: -2), material: .solid),
            ],
            autoPolicy: .none,
            viewportCenter: CellPosition(x: 0, y: 4),
            longEdgeCells: 50
        ),
        Scenario(
            id: "ice-melting",
            name: "Ice Melting Near Fire",
            description: "Ice melts to water when heated by fire",
            seed: 6,
            initialCommands: [
                SimulationCommand(tick: 1, position: CellPosition(x: 1, y: 0), material: .solid),
                SimulationCommand(tick: 1, position: CellPosition(x: 0, y: 0), material: .ice),
            ],
            autoPolicy: .none,
            viewportCenter: CellPosition(x: 0, y: 0),
            longEdgeCells: 50
        ),

        // BeaconHazardTests / BeaconRun
        Scenario(
            id: "vent-contact",
            name: "Vent Contact",
            description: "Character near heat vent - demonstrates half-open body boundaries",
            seed: 42,
            initialCommands: [],
            autoPolicy: .beaconRun,
            viewportCenter: CellPosition(x: 119, y: 0),
            longEdgeCells: 200
        ),
        Scenario(
            id: "water-cools-vent",
            name: "Water Cools Vent",
            description: "Water cools heat vent, vent recovers after water removed",
            seed: 42,
            initialCommands: [],
            autoPolicy: .custom { tick, state in
                // Replicate testWaterCoolsAfterPhysicsAndVentRecovers logic
                if tick == 300 { // reachVent takes ~300 ticks
                    return AutoPolicy.AutoCommands(horizontal: 0, jump: false, pulse: false, paintCommands: [
                        SimulationCommand(tick: UInt64(tick + 1), position: CellPosition(x: 126, y: 1), material: .water)
                    ])
                }
                if tick > 300 && tick < 305 {
                    return AutoPolicy.AutoCommands(horizontal: 0, jump: false)
                }
                return AutoPolicy.AutoCommands(horizontal: 1, jump: false)
            },
            viewportCenter: CellPosition(x: 119, y: 0),
            longEdgeCells: 200
        ),
        Scenario(
            id: "beacon-run-full",
            name: "Full Beacon Run",
            description: "Complete BeaconRun with auto movement, jumps, and pulses",
            seed: 42,
            initialCommands: [],
            autoPolicy: .beaconRun,
            viewportCenter: CellPosition(x: 65, y: 0),
            longEdgeCells: 200
        ),

        // CaveRun
        Scenario(
            id: "cave-world",
            name: "Cave World",
            description: "Generated cave world simulation",
            seed: 42,
            initialCommands: [],
            autoPolicy: .caveRun,
            viewportCenter: CellPosition(x: 0, y: 0), // Will be updated after world generation
            longEdgeCells: 200
        ),
        Scenario(
            id: "cave-run-128x64",
            name: "Cave Run 128x64",
            description: "Smaller cave run",
            seed: 1,
            initialCommands: [],
            autoPolicy: .caveRun,
            viewportCenter: CellPosition(x: 0, y: 0),
            longEdgeCells: 200
        ),
    ]

    public static func byId(_ id: String) -> Scenario? {
        return all.first { $0.id == id }
    }

    public static func list() -> [(id: String, name: String, description: String)] {
        return all.map { ($0.id, $0.name, $0.description) }
    }
}

/// Load custom scenario from JSON file
public struct CustomScenarioLoader {
    public static func load(from url: URL) throws -> Scenario {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(ScenarioDTO.self, from: data).toScenario()
    }
}

/// DTO for JSON decoding
private struct ScenarioDTO: Codable {
    let id: String
    let name: String
    let description: String
    let seed: UInt64
    let initialCommands: [CommandDTO]
    let autoPolicy: String
    let viewportCenter: PositionDTO
    let longEdgeCells: Int

    struct CommandDTO: Codable {
        let tick: UInt64
        let position: PositionDTO
        let material: String
        let isSpellCommand: Bool?
    }

    struct PositionDTO: Codable {
        let x: Int
        let y: Int
    }

    func toScenario() throws -> Scenario {
        var commands: [SimulationCommand] = []
        commands.reserveCapacity(initialCommands.count)
        for cmd in initialCommands {
            let material = try Material.fromString(cmd.material)
            commands.append(SimulationCommand(
                tick: cmd.tick,
                position: CellPosition(x: cmd.position.x, y: cmd.position.y),
                material: material,
                isSpellCommand: cmd.isSpellCommand ?? false
            ))
        }

        let policy = try AutoPolicy.fromString(autoPolicy)
        let center = CellPosition(x: viewportCenter.x, y: viewportCenter.y)

        return Scenario(
            id: id,
            name: name,
            description: description,
            seed: seed,
            initialCommands: commands,
            autoPolicy: policy,
            viewportCenter: center,
            longEdgeCells: longEdgeCells
        )
    }
}

extension Material {
    static func fromString(_ string: String) throws -> Material {
        switch string.lowercased() {
        case "empty": return .empty
        case "solid": return .solid
        case "sand": return .sand
        case "water": return .water
        case "fire": return .fire
        case "pitch": return .pitch
        case "oil": return .oil
        case "steam": return .steam
        case "lava": return .lava
        case "acid": return .acid
        case "blood": return .blood
        case "slime": return .slime
        case "ice": return .ice
        case "gunpowder": return .gunpowder
        case "gold": return .gold
        case "magicliquid", "magic-liquid": return .magicLiquid
        default: throw NSError(domain: "Scenario", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown material: \(string)"])
        }
    }
}

extension AutoPolicy {
    static func fromString(_ string: String) throws -> AutoPolicy {
        switch string.lowercased() {
        case "none": return .none
        case "move-right": return .moveRight
        case "move-right-jump": return .moveRightJump(interval: 60)
        case "beacon-run": return .beaconRun
        case "cave-run": return .caveRun
        default: throw NSError(domain: "Scenario", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown auto policy: \(string)"])
        }
    }
}