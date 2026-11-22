/// CaptureComparison - Headless video frame capture for Noirpx simulation.
/// Outputs raw RGBA frames to stdout for ffmpeg consumption.
///
/// Usage: CaptureComparison --ref <git-ref> --seed <uint64> --ticks <int> --fps <int> --width <int> --height <int> [--worktree <path>] [--world-type beacon|cave] [--hud] [--out <path>] [--info]

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
    let hudEnabled: Bool
    let outPath: String?
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
    var width: Int = 800
    var height: Int = 450
    var worktreePath: String = FileManager.default.currentDirectoryPath
    var worldType: WorldType = .beacon
    var hudEnabled = false
    var showInfo = false
    var outPath: String?

    var i = args.startIndex
    while i < args.endIndex {
        let arg = args[i]
        switch arg {
        case "--ref": i += 1; ref = args[i]
        case "--seed": i += 1; seed = UInt64(args[i]) ?? 42
        case "--ticks": i += 1; ticks = Int(args[i]) ?? 300
        case "--fps": i += 1; fps = Int(args[i]) ?? 30
        case "--width": i += 1; width = Int(args[i]) ?? 800
        case "--height": i += 1; height = Int(args[i]) ?? 450
        case "--worktree": i += 1; worktreePath = args[i]
        case "--world-type": i += 1; worldType = WorldType(rawValue: args[i]) ?? .beacon
        case "--hud": hudEnabled = true
        case "--info": showInfo = true
        case "--out": i += 1; outPath = args[i]
        default: break
        }
        i += 1
    }
    guard let ref else { return nil }
    return ParsedArgs(args: Args(ref: ref, seed: seed, ticks: ticks, fps: fps, width: width, height: height, worktreePath: worktreePath, worldType: worldType, hudEnabled: hudEnabled, outPath: outPath), showInfo: showInfo)
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

/// Maps a `BeaconRun` outcome onto the display list outcome enum.
func displayOutcome(_ outcome: BeaconRun.Outcome) -> DisplayOutcome {
    switch outcome {
    case .playing: return .playing
    case .won: return .won
    case .fell: return .fell
    case .exhausted: return .exhausted
    }
}

/// Maps a `ChimeWarden` to `DisplayWarden`.
func displayWarden(_ warden: ChimeWarden) -> DisplayWarden {
    DisplayWarden(
        alive: warden.alive,
        shield: warden.shield,
        burning: warden.burning,
        lastHazardName: warden.lastHazard?.rawValue
    )
}

// MARK: - BeaconRun Capture

struct BeaconCapture {
    let width: Int
    let height: Int
    let seed: UInt64
    let version: String
    let hudEnabled: Bool
    let viewport: FixtureViewport
    var character: FixtureCharacter
    var challenge: BeaconRun?
    var simulation: Simulation

    init(width: Int, height: Int, seed: UInt64, version: String, hudEnabled: Bool) throws {
        self.width = width
        self.height = height
        self.seed = seed
        self.version = version
        self.hudEnabled = hudEnabled
        let run = try BeaconRun(seed: seed)
        self.challenge = run
        self.character = run.character
        let cameraCenter = CellPosition(x: character.position.x + FixtureCharacter.width / 2, y: character.position.y + FixtureCharacter.height / 2)
        // BeaconRun floor spans x: -40...160; vertical playable range y: -20...20 (fall limit -20).
        let worldBounds = FixtureViewport.CellRange(x: -40...160, y: -20...20)
        guard let vp = FixtureViewport(drawableWidth: Double(width), drawableHeight: Double(height),
                                        center: cameraCenter, longEdgeCells: 200, worldBounds: worldBounds) else {
            throw NSError(domain: "capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create viewport"])
        }
        self.viewport = vp
        self.simulation = run.simulation
    }

    mutating func captureFrame() -> [UInt8] {
        let (pixels, renderedChunks) = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, character: character)
        var lit = pixels
        let light = FixturePixels.lightMap(snapshot: simulation.snapshot, viewport: viewport, character: character)
        FixturePixels.applyLightMap(to: &lit, lightMap: light, width: viewport.columns, height: viewport.rows, ambient: 0.15)
        // Upscale the game view to output resolution FIRST, then composite HUD at output resolution
        // so HUD text/elements are sized for readable output pixels, not tiny cell pixels.
        var outPixels = upscaleNearest(lit, fromWidth: viewport.columns, fromHeight: viewport.rows, toWidth: width, toHeight: height)
        guard hudEnabled else { return outPixels }
        guard let run = challenge else { return outPixels }
        let collectedBeacons = run.collected.filter { $0 }.count
        let state = DisplayListState(
            version: version,
            worldKind: .beacon,
            seed: seed,
            worldWidth: 200,  // BeaconRun floor width
            worldHeight: 40,  // BeaconRun floor height
            position: character.position,
            tick: simulation.snapshot.tick,
            depth: nil,
            outcome: displayOutcome(run.outcome),
            health: nil,
            maxHealth: nil,
            energy: nil,
            maxEnergy: nil,
            collectedBeacons: collectedBeacons,
            warden: displayWarden(run.warden),
            selectedMaterial: .sand,
            isCasting: false,
            discoveredMaterials: [],
            wand: Wand(),
            manaPool: ManaPool(),
            showCraftingGrid: false,
            craftingAllowed: false,
            craftingGrid: CraftingGrid(),
            framesPerSecond: nil,
            renderedChunks: renderedChunks,
            errorMessage: nil,
            hoveredMaterialName: nil,
            hudVisible: true,
            controls: .keyboard,
            overlays: DisplayOverlayVisibility(stats: false, help: false, crafting: false)
        )
        let list = HUDLayout.gameUI(width: width, height: height, state: state)
        DisplayListRaster.composite(onto: &outPixels, list)
        return outPixels
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
    let seed: UInt64
    let version: String
    let hudEnabled: Bool
    let viewport: FixtureViewport
    var simulation: Simulation

    init(width: Int, height: Int, seed: UInt64, version: String, hudEnabled: Bool) throws {
        self.width = width
        self.height = height
        self.seed = seed
        self.version = version
        self.hudEnabled = hudEnabled

        // Create base simulation and stamp cave world (256×128 centered at origin, matching CaveRun)
        var simulation = Simulation(seed: seed)
        let generator = CaveWorldGenerator(seed: seed, width: 256, height: 128)
        try generator.stamp(into: &simulation, tick: 1)

        // Get spawn position for camera center and world extents for clamping
        let caveWorld = generator.generate()
        let cameraCenter = caveWorld.spawn
        // CaveRun 256×128 centered at origin: x ∈ [-128, 127], y ∈ [-64, 63]
        let worldBounds = FixtureViewport.CellRange(x: -128...127, y: -64...63)

        guard let vp = FixtureViewport(drawableWidth: Double(width), drawableHeight: Double(height),
                                        center: cameraCenter, longEdgeCells: 200, worldBounds: worldBounds) else {
            throw NSError(domain: "capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create viewport"])
        }
        self.viewport = vp
        self.simulation = simulation
    }

    mutating func captureFrame(frame: UInt64 = 0) -> [UInt8] {
        let (pixels, renderedChunks) = FixturePixels.rasterize(snapshot: simulation.snapshot, viewport: viewport, character: nil, frame: frame)
        var lit = pixels
        let light = FixturePixels.lightMap(snapshot: simulation.snapshot, viewport: viewport, character: nil)
        FixturePixels.applyLightMap(to: &lit, lightMap: light, width: viewport.columns, height: viewport.rows, ambient: 0.15)
        // Upscale the game view to output resolution FIRST, then composite HUD at output resolution
        // so HUD text/elements are sized for readable output pixels, not tiny cell pixels.
        var outPixels = upscaleNearest(lit, fromWidth: viewport.columns, fromHeight: viewport.rows, toWidth: width, toHeight: height)
        guard hudEnabled else { return outPixels }
        let state = DisplayListState(
            version: version,
            worldKind: .cave,
            seed: seed,
            worldWidth: 256,
            worldHeight: 128,
            position: nil,
            tick: simulation.snapshot.tick,
            depth: nil,
            outcome: .playing,
            health: nil,
            maxHealth: nil,
            energy: nil,
            maxEnergy: nil,
            collectedBeacons: 0,
            warden: nil,
            selectedMaterial: .sand,
            isCasting: false,
            discoveredMaterials: [],
            wand: Wand(),
            manaPool: ManaPool(),
            showCraftingGrid: false,
            craftingAllowed: false,
            craftingGrid: CraftingGrid(),
            framesPerSecond: nil,
            renderedChunks: renderedChunks,
            errorMessage: nil,
            hoveredMaterialName: nil,
            hudVisible: true,
            controls: .keyboard,
            overlays: DisplayOverlayVisibility(stats: false, help: false, crafting: false)
        )
        let list = HUDLayout.gameUI(width: width, height: height, state: state)
        DisplayListRaster.composite(onto: &outPixels, list)
        return outPixels
    }

    mutating func advanceTick() throws {
        let activeChunks = viewport.activeChunks
        try simulation.advance(activeChunks: activeChunks)
    }

    mutating func runAuto(ticks: Int) throws -> [[UInt8]] {
        var frames: [[UInt8]] = []
        frames.reserveCapacity(ticks)
        for tick in 0..<ticks {
            frames.append(captureFrame(frame: UInt64(tick)))
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

/// Emits captured frames. With `--out <path.png>`, writes the first frame as a
/// PNG for a visual HUD spot-check. With `--out <path.mp4>`, encodes all frames
/// to an MP4 via ffmpeg at `fps`. Otherwise streams raw RGBA frames to stdout.
func emitFrames(_ frames: [[UInt8]], width: Int, height: Int, fps: Int, outPath: String?) throws {
    guard let first = frames.first else {
        throw NSError(domain: "capture", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "No frames captured"])
    }
    if let outPath {
        if outPath.lowercased().hasSuffix(".mp4") {
            try encodeMP4(frames: frames, width: width, height: height, fps: fps, outputPath: outPath)
            return
        }
        try PNGWriter.write(first, width: width, height: height, to: outPath)
    } else {
        writeFramesToStdout(frames)
    }
}

/// Nearest-neighbor upscale of RGBA pixels from (fromW × fromH) to (toW × toH).
/// Crisp (no interpolation), matching MetalRenderer's nearest sampling so the
/// cell grid and HUD scale cleanly to production resolution.
private func upscaleNearest(_ pixels: [UInt8], fromWidth: Int, fromHeight: Int,
                            toWidth: Int, toHeight: Int) -> [UInt8] {
    precondition(pixels.count == fromWidth * fromHeight * 4)
    var out = [UInt8](repeating: 0, count: toWidth * toHeight * 4)
    let xScale = Double(fromWidth) / Double(toWidth)
    let yScale = Double(fromHeight) / Double(toHeight)
    for y in 0..<toHeight {
        let sy = Int(Double(y) * yScale)
        let srcRow = sy * fromWidth
        let dstRow = y * toWidth
        for x in 0..<toWidth {
            let sx = Int(Double(x) * xScale)
            let srcIdx = (srcRow + sx) * 4
            let dstIdx = (dstRow + x) * 4
            out[dstIdx] = pixels[srcIdx]
            out[dstIdx + 1] = pixels[srcIdx + 1]
            out[dstIdx + 2] = pixels[srcIdx + 2]
            out[dstIdx + 3] = pixels[srcIdx + 3]
        }
    }
    return out
}

/// Encodes RGBA frames to MP4 via ffmpeg: writes temp PNGs, encodes, cleans up.
private func encodeMP4(frames: [[UInt8]], width: Int, height: Int, fps: Int, outputPath: String) throws {
    guard let ffmpeg = findExecutable("ffmpeg") else {
        throw NSError(domain: "capture", code: 5,
                      userInfo: [NSLocalizedDescriptionKey: "ffmpeg not found in PATH. Install ffmpeg to enable MP4 output."])
    }
    let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CaptureComparison-\(ProcessInfo.processInfo.globallyUniqueString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: nil)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    for (idx, frame) in frames.enumerated() {
        let path = tmpDir.appendingPathComponent(String(format: "frame_%05d.png", idx + 1)).path
        try PNGWriter.write(frame, width: width, height: height, to: path)
    }
    let pattern = tmpDir.appendingPathComponent("frame_%05d.png").path
    let args = [
        "-y",
        "-framerate", String(fps),
        "-i", pattern,
        "-vf", "scale=\(width):\(height)",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-crf", "23",
        outputPath,
    ]
    try runProcess(ffmpeg, args)
}

/// Locate an executable on PATH (mirrors TestAnimationRenderer.VideoEncoder).
private func findExecutable(_ name: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [name]
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}

/// Run an executable, throwing on non-zero exit with captured stderr.
private func runProcess(_ executable: String, _ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        throw NSError(domain: "capture", code: 6,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to launch \(executable): \(error)"])
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? "unknown error"
        throw NSError(domain: "capture", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(executable) failed: \(output)"])
    }
}

func printUsage() {
    let stderr = FileHandle.standardError
    let msg = """
Usage: CaptureComparison --ref <git-ref> --seed <uint64> --ticks <int> --fps <int> --width <int> --height <int> [--worktree <path>] [--world-type beacon|cave] [--hud] [--out <path>] [--info]
  --ref           Git ref to checkout (branch, tag, commit)
  --seed          Simulation seed (default: 42)
  --ticks         Ticks to simulate (default: 300)
  --fps           Output video FPS (default: 30)
  --width         Video width (default: 800)
  --height        Video height (default: 450)
  --worktree      Path to git worktree (default: current directory)
  --world-type    World type: beacon or cave (default: beacon)
  --hud           Composite the headless HUD overlay onto captured frames (default: off)
  --out           Write output to <path>: .png = first frame, .mp4 = full video at --fps, else raw RGBA to stdout
  --info          Print viewport info and exit
"""
    stderr.write(msg.data(using: .utf8)!)
}

func printError(_ message: String) {
    let stderr = FileHandle.standardError
    stderr.write(("Error: \(message)\n").data(using: .utf8)!)
}

/// Reads MARKETING_VERSION from the worktree's Xcode project, matching the
/// version shown by the live app HUD. Falls back to "unknown".
func loadVersion(at worktreePath: String) -> String {
    let pbxprojPath = worktreePath.appending("/Noirpx.xcodeproj/project.pbxproj")
    guard let content = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else { return "unknown" }
    guard let match = content.firstMatch(of: /MARKETING_VERSION\s*=\s*([0-9]+\.[0-9]+\.[0-9]+)/) else {
        return "unknown"
    }
    return String(match.output.1)
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

    let version = loadVersion(at: args.worktreePath)

    // Create capture to get viewport dimensions
    let vp: FixtureViewport
    switch args.worldType {
    case .beacon:
        let capture = try BeaconCapture(width: args.width, height: args.height, seed: args.seed,
                                        version: version, hudEnabled: args.hudEnabled)
        vp = capture.viewport
        if showInfo {
            let outBytes = args.width * args.height * 4
            let info = "WIDTH=\(args.width)\nHEIGHT=\(args.height)\nBYTES_PER_FRAME=\(outBytes)\n"
            FileHandle.standardOutput.write(info.data(using: .utf8)!)
            return
        }
        var mutableCapture = capture
        let frames = try mutableCapture.runAuto(ticks: args.ticks)
        try emitFrames(frames, width: args.width, height: args.height, fps: args.fps, outPath: args.outPath)

    case .cave:
        let capture = try CaveCapture(width: args.width, height: args.height, seed: args.seed,
                                      version: version, hudEnabled: args.hudEnabled)
        vp = capture.viewport
        if showInfo {
            let outBytes = args.width * args.height * 4
            let info = "WIDTH=\(args.width)\nHEIGHT=\(args.height)\nBYTES_PER_FRAME=\(outBytes)\n"
            FileHandle.standardOutput.write(info.data(using: .utf8)!)
            return
        }
        var mutableCapture = capture
        let frames = try mutableCapture.runAuto(ticks: args.ticks)
        try emitFrames(frames, width: args.width, height: args.height, fps: args.fps, outPath: args.outPath)
    }
}

do {
    try main()
} catch {
    printError("\(error)")
    exit(1)
}