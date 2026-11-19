import Foundation
import SimulationCore
import GamePresentation

/// Core simulation and capture loop
public struct CaptureEngine {
    public let scenario: Scenario
    public let ticks: Int
    public let width: Int
    public let height: Int
    public let fps: Int
    public let outputDirectory: URL
    public let format: VideoEncoder.OutputFormat

    private var simulation: Simulation
    private var viewport: FixtureViewport
    private var character: FixtureCharacter?
    private var beaconRun: BeaconRun?
    private var caveRun: CaveRun?

    public init(scenario: Scenario, ticks: Int, width: Int, height: Int, fps: Int, outputDirectory: URL, format: VideoEncoder.OutputFormat) throws {
        self.scenario = scenario
        self.ticks = ticks
        self.width = width
        self.height = height
        self.fps = fps
        self.outputDirectory = outputDirectory
        self.format = format

        // Initialize simulation based on scenario
        let isBeaconPolicy: Bool
        switch scenario.autoPolicy {
        case .beaconRun, .moveRightJump: isBeaconPolicy = true
        default: isBeaconPolicy = false
        }
        if isBeaconPolicy {
            // BeaconRun scenario
            let run = try BeaconRun(seed: scenario.seed)
            self.beaconRun = run
            self.character = run.character
            self.simulation = run.simulation

            // Update viewport center to character
            let cameraCenter = CellPosition(
                x: run.character.position.x + FixtureCharacter.width / 2,
                y: run.character.position.y + FixtureCharacter.height / 2
            )
            guard let vp = FixtureViewport(drawableWidth: Double(width), drawableHeight: Double(height),
                                            center: cameraCenter, longEdgeCells: scenario.longEdgeCells) else {
                throw NSError(domain: "CaptureEngine", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to create viewport"])
            }
            self.viewport = vp

        } else if scenario.autoPolicy == .caveRun {
            // CaveRun scenario
            let generator = CaveWorldGenerator(seed: scenario.seed, width: 128, height: 64)
            let world = generator.generate()
            var simulation = Simulation(seed: scenario.seed)
            try generator.stamp(into: &simulation, tick: 1)
            try simulation.advance()

            self.caveRun = try CaveRun(seed: scenario.seed, width: 128, height: 64)
            self.character = self.caveRun?.character
            self.simulation = simulation

            let cameraCenter = world.spawn
            guard let vp = FixtureViewport(drawableWidth: Double(width), drawableHeight: Double(height),
                                            center: cameraCenter, longEdgeCells: scenario.longEdgeCells) else {
                throw NSError(domain: "CaptureEngine", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to create viewport"])
            }
            self.viewport = vp

        } else {
            // Generic Simulation scenario
            var sim = Simulation(seed: scenario.seed)
            // Apply initial commands
            for cmd in scenario.initialCommands {
                try sim.enqueue(cmd)
            }
            // Advance once to apply initial commands
            try sim.advance()
            self.simulation = sim
            self.character = nil
            self.beaconRun = nil
            self.caveRun = nil

            guard let vp = FixtureViewport(drawableWidth: Double(width), drawableHeight: Double(height),
                                            center: scenario.viewportCenter, longEdgeCells: scenario.longEdgeCells) else {
                throw NSError(domain: "CaptureEngine", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to create viewport"])
            }
            self.viewport = vp
        }
    }

    /// Run the capture loop and return number of frames captured
    @discardableResult
    public mutating func run(progress: ((Int, Int) -> Void)? = nil) throws -> Int {
        var frameCount = 0

        for tick in 0..<ticks {
            // Capture frame
            let pixels = captureFrame()
            let frameURL = FrameWriter.frameURL(directory: outputDirectory, index: tick)
            try FrameWriter.writePNG(pixels: pixels, width: viewport.columns, height: viewport.rows, to: frameURL)
            frameCount += 1

            // Report progress
            progress?(tick + 1, ticks)

            // Advance simulation (skip on last tick since we don't need next frame)
            if tick < ticks - 1 {
                try advanceTick(tick: tick)
            }
        }

        return frameCount
    }

    private mutating func captureFrame() -> [UInt8] {
        let (pixels, _) = FixturePixels.rasterize(
            snapshot: simulation.snapshot,
            viewport: viewport,
            character: character
        )
        return pixels
    }

    private mutating func advanceTick(tick: Int) throws {
        // Apply auto-policy commands
        let autoCommands = scenario.autoPolicy.commands(forTick: tick, state: currentState())
        for cmd in autoCommands.paintCommands {
            try simulation.enqueue(cmd)
        }

        let activeChunks = viewport.activeChunks

        if var run = beaconRun {
            try run.advance(horizontal: autoCommands.horizontal, jump: autoCommands.jump, pulse: autoCommands.pulse, activeChunks: activeChunks)
            self.beaconRun = run
            self.character = run.character
            self.simulation = run.simulation

            // Update viewport to follow character
            let cameraCenter = CellPosition(
                x: run.character.position.x + FixtureCharacter.width / 2,
                y: run.character.position.y + FixtureCharacter.height / 2
            )
            if let newVP = FixtureViewport(drawableWidth: Double(width), drawableHeight: Double(height),
                                           center: cameraCenter, longEdgeCells: scenario.longEdgeCells) {
                self.viewport = newVP
            }

        } else if var run = caveRun {
            try run.advance(horizontal: autoCommands.horizontal, jump: autoCommands.jump, activeChunks: activeChunks)
            self.caveRun = run
            self.character = run.character
            self.simulation = run.simulation

            // Update viewport to follow character
            let cameraCenter = CellPosition(
                x: run.character.position.x + FixtureCharacter.width / 2,
                y: run.character.position.y + FixtureCharacter.height / 2
            )
            if let newVP = FixtureViewport(drawableWidth: Double(width), drawableHeight: Double(height),
                                           center: cameraCenter, longEdgeCells: scenario.longEdgeCells) {
                self.viewport = newVP
            }

        } else {
            // Generic simulation
            try simulation.advance(activeChunks: activeChunks)
        }
    }

    private func currentState() -> AutoPolicy.ScenarioState {
        if let run = beaconRun {
            return AutoPolicy.ScenarioState(
                tick: Int(run.simulation.snapshot.tick),
                characterPosition: run.character.position,
                outcome: run.outcome,
                health: run.health
            )
        } else if let run = caveRun {
            // Cave Run has a single terminal state. The capture policy speaks BeaconRun
            // outcomes, so any non-playing Cave Run outcome maps to `.exhausted` by design.
            let beaconOutcome: BeaconRun.Outcome? = run.outcome == .playing ? nil : .exhausted
            return AutoPolicy.ScenarioState(
                tick: Int(run.simulation.snapshot.tick),
                characterPosition: run.character.position,
                outcome: beaconOutcome,
                health: run.health
            )
        } else {
            return AutoPolicy.ScenarioState(
                tick: Int(simulation.snapshot.tick),
                characterPosition: nil,
                outcome: nil,
                health: nil
            )
        }
    }
}

extension AutoPolicy {
    /// Generate commands for a specific tick
    func commands(forTick tick: Int, state: ScenarioState) -> AutoCommands {
        switch self {
        case .none:
            return AutoCommands()

        case .moveRight:
            return AutoCommands(horizontal: 1)

        case .moveRightJump(let interval):
            let jump = (tick % interval == 0)
            return AutoCommands(horizontal: 1, jump: jump)

        case .beaconRun:
            // Replicate BeaconRun auto-play logic from BeaconHazardTests.reachVent()
            let horizontal = 1
            var jump = false
            var pulse = false

            if let pos = state.characterPosition {
                // Jump at gap (around x=31)
                if !jump && pos.x >= 31 && pos.x <= 35 {
                    jump = true
                }
                // Jump at vent (around x=113-119)
                if pos.x >= 113 && pos.x <= 119 {
                    jump = true
                }
                // Pulse after x=50
                if pos.x >= 50 {
                    pulse = true
                }
            }

            return AutoCommands(horizontal: horizontal, jump: jump, pulse: pulse)

        case .caveRun:
            // Simple cave run: move right, jump occasionally
            let horizontal = 1
            let jump = (tick % 40 == 0) // Jump every 40 ticks
            return AutoCommands(horizontal: horizontal, jump: jump)

        case .custom(let closure):
            return closure(tick, state)
        }
    }
}