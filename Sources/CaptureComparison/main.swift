/// CaptureComparison - Headless video frame capture for Noirpx simulation.
/// Outputs raw RGBA frames to stdout for ffmpeg consumption.
///
/// Usage: CaptureComparison --ref <git-ref> --seed <uint64> --ticks <int> --fps <int> --width <int> --height <int> [--worktree <path>] [--world-type beacon|cave] [--info]

import Foundation
import SimulationCore
import GamePresentation

enum WorldType: String {
    case beacon
    case cave
}

struct Args {
    let ref: String
    let seed: UInt64
    let ticks: Int
    let fps: Int
    let width: Int
    let height: Int
    let worktreePath: String
    let worldType: WorldType
}

struct ParsedArgs {
    let args: Args
    let showInfo: Bool
}

func parseArgs() -> ParsedArgs? {
    let args = CommandLine.arguments.dropFirst()
    var ref: String?
    var seed: UInt64 = 42
    var ticks: Int = 300
    var fps: Int = 30
    var width: Int = 640
    var height: Int = 360
    var worktreePath: String = FileManager.default.currentDirectoryPath
    var worldType: WorldType = .beacon
    var showInfo = false

    var i = args.startIndex
    while i < args.endIndex {
        let arg = args[i]
        switch arg {
        case "--ref": i += 1; ref = args[i]
        case "--seed": i += 1; seed = UInt64(args[i]) ?? 42
        case "--ticks": i += 1; ticks = Int(args[i]) ?? 300
        case "--fps": i += 1; fps = Int(args[i]) ?? 30
        case "--width": i += 1; width = Int(args[i]) ?? 640
        case "--height": i += 1; height = Int(args[i]) ?? 360
        case "--worktree": i += 1; worktreePath = args[i]
        case "--world-type": i += 1; worldType = WorldType(rawValue: args[i]) ?? .beacon
        case "--info": showInfo = true
        default: break
        }
        i += 1
    }
    guard let ref else { return nil }
    return ParsedArgs(args: Args(ref: ref, seed: seed, ticks: ticks, fps: fps, width: width, height: height, worktreePath: worktreePath, worldType: worldType), showInfo: showInfo)
}

func runGit(_ args: [String], at path: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: path)
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "git \(args) failed"])
    }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

// MARK: - BeaconRun Capture

struct BeaconCapture {
    let width: Int
    let height: Int
    let viewport: FixtureViewport
    var character: FixtureCharacter
    var challenge: BeaconRun?
    var simulation: Simulation

    init(width: Int, height: Int, seed: UInt64) throws {
        self.width = width
        self.height = height
        let run = try BeaconRun(seed: seed)
        self.challenge = run
        self.character = run.character
        let cameraCenter = CellPosition(x: character.position.x + FixtureCharacter.width / 2, y: character.position.y + FixtureCharacter.height / 2)
        guard let vp = FixtureViewport(drawableWidth: Double(width), drawableHeight: Double(height),
                                        center: cameraCenter, longEdgeCells: 200) else {
            throw NSError(domain: "capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create viewport"])
        }
        self.viewport = vp
        self.simulation = run.simulation
    }

    mutating func captureFrame() -> [UInt8] {
        let (pixels, _) = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, character: character)
        return pixels
    }

    mutating func advanceTick(horizontal: Int, jump: Bool, pulse: Bool) throws {
        let activeChunks = viewport.activeChunks
        guard var run = challenge else { return }
        try run.advance(horizontal: horizontal, jump: jump, pulse: pulse, activeChunks: activeChunks)
        self.challenge = run
        self.character = run.character
        self.simulation = run.simulation
    }

    mutating func runAuto(ticks: Int) throws -> [[UInt8]] {
        var frames: [[UInt8]] = []
        frames.reserveCapacity(ticks)
        for tick in 0..<ticks {
            frames.append(captureFrame())
            let horizontal: Int = 1
            let jump = (tick % 60 == 0)
            let pulse = (tick % 120 == 0)
            try advanceTick(horizontal: horizontal, jump: jump, pulse: pulse)
        }
        return frames
    }
}

// MARK: - CaveWorld Capture

struct CaveCapture {
    let width: Int
    let height: Int
    let viewport: FixtureViewport
    var simulation: Simulation

    init(width: Int, height: Int, seed: UInt64) throws {
        self.width = width
        self.height = height

        // Create base simulation and stamp cave world
        var simulation = Simulation(seed: seed)
        let generator = CaveWorldGenerator(seed: seed, width: 128, height: 64)
        try generator.stamp(into: &simulation, tick: 1)

        // Get spawn position for camera center
        let caveWorld = generator.generate()
        let cameraCenter = caveWorld.spawn

        guard let vp = FixtureViewport(drawableWidth: Double(width), drawableHeight: Double(height),
                                        center: cameraCenter, longEdgeCells: 200) else {
            throw NSError(domain: "capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create viewport"])
        }
        self.viewport = vp
        self.simulation = simulation
    }

    mutating func captureFrame() -> [UInt8] {
        let (pixels, _) = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, character: nil)
        return pixels
    }

    mutating func advanceTick() throws {
        let activeChunks = viewport.activeChunks
        try simulation.advance(activeChunks: activeChunks)
    }

    mutating func runAuto(ticks: Int) throws -> [[UInt8]] {
        var frames: [[UInt8]] = []
        frames.reserveCapacity(ticks)
        for _ in 0..<ticks {
            frames.append(captureFrame())
            try advanceTick()
        }
        return frames
    }
}

// MARK: - Common

func writeFramesToStdout(_ frames: [[UInt8]]) {
    let stdout = FileHandle.standardOutput
    for frame in frames {
        frame.withUnsafeBytes { buffer in
            try? stdout.write(contentsOf: buffer)
        }
    }
}

func printUsage() {
    let stderr = FileHandle.standardError
    let msg = """
Usage: CaptureComparison --ref <git-ref> --seed <uint64> --ticks <int> --fps <int> --width <int> --height <int> [--worktree <path>] [--world-type beacon|cave] [--info]
  --ref           Git ref to checkout (branch, tag, commit)
  --seed          Simulation seed (default: 42)
  --ticks         Ticks to simulate (default: 300)
  --fps           Output video FPS (default: 30)
  --width         Video width (default: 640)
  --height        Video height (default: 360)
  --worktree      Path to git worktree (default: current directory)
  --world-type    World type: beacon or cave (default: beacon)
  --info          Print viewport info and exit
"""
    stderr.write(msg.data(using: .utf8)!)
}

func printError(_ message: String) {
    let stderr = FileHandle.standardError
    stderr.write(("Error: \(message)\n").data(using: .utf8)!)
}

func main() throws {
    guard let parsed = parseArgs() else {
        printUsage()
        exit(1)
    }
    let args = parsed.args
    let showInfo = parsed.showInfo

    // Check out the ref in the worktree
    _ = try runGit(["checkout", "-q", args.ref], at: args.worktreePath)

    // Create capture to get viewport dimensions
    let vp: FixtureViewport
    switch args.worldType {
    case .beacon:
        let capture = try BeaconCapture(width: args.width, height: args.height, seed: args.seed)
        vp = capture.viewport
        if showInfo {
            let info = "WIDTH=\(vp.columns)\nHEIGHT=\(vp.rows)\nBYTES_PER_FRAME=\(vp.columns * vp.rows * 4)\n"
            FileHandle.standardOutput.write(info.data(using: .utf8)!)
            return
        }
        var mutableCapture = capture
        let frames = try mutableCapture.runAuto(ticks: args.ticks)
        writeFramesToStdout(frames)

    case .cave:
        let capture = try CaveCapture(width: args.width, height: args.height, seed: args.seed)
        vp = capture.viewport
        if showInfo {
            let info = "WIDTH=\(vp.columns)\nHEIGHT=\(vp.rows)\nBYTES_PER_FRAME=\(vp.columns * vp.rows * 4)\n"
            FileHandle.standardOutput.write(info.data(using: .utf8)!)
            return
        }
        var mutableCapture = capture
        let frames = try mutableCapture.runAuto(ticks: args.ticks)
        writeFramesToStdout(frames)
    }
}

do {
    try main()
} catch {
    printError("\(error)")
    exit(1)
}