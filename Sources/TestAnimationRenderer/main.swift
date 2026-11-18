/// TestAnimationRenderer - CLI tool for rendering simulation test scenarios as animations
///
/// Usage: TestAnimationRenderer --scenario <id> --output-dir <path> [options]

import Foundation
import SimulationCore
import GamePresentation

struct Arguments {
    let scenario: String?
    let seed: UInt64
    let ticks: Int
    let outputDir: String
    let fps: Int
    let format: VideoEncoder.OutputFormat
    let width: Int
    let height: Int
    let longEdgeCells: Int
    let listScenarios: Bool
    let customScenarioPath: String?
}

func parseArguments() -> Arguments? {
    let args = CommandLine.arguments.dropFirst()
    var scenario: String?
    var seed: UInt64 = 42
    var ticks: Int = 300
    var outputDir: String?
    var fps: Int = 30
    var format: VideoEncoder.OutputFormat = .png
    var width: Int = 640
    var height: Int = 360
    var longEdgeCells: Int = 200
    var listScenarios = false
    var customScenarioPath: String?

    var i = args.startIndex
    while i < args.endIndex {
        let arg = args[i]
        switch arg {
        case "--scenario":
            i += 1
            guard i < args.endIndex else { return nil }
            scenario = args[i]
        case "--seed":
            i += 1
            guard i < args.endIndex, let s = UInt64(args[i]) else { return nil }
            seed = s
        case "--ticks":
            i += 1
            guard i < args.endIndex, let t = Int(args[i]) else { return nil }
            ticks = t
        case "--output-dir", "-o":
            i += 1
            guard i < args.endIndex else { return nil }
            outputDir = args[i]
        case "--fps":
            i += 1
            guard i < args.endIndex, let f = Int(args[i]) else { return nil }
            fps = f
        case "--format":
            i += 1
            guard i < args.endIndex else { return nil }
            format = VideoEncoder.OutputFormat(rawValue: args[i]) ?? .png
        case "--width":
            i += 1
            guard i < args.endIndex, let w = Int(args[i]) else { return nil }
            width = w
        case "--height":
            i += 1
            guard i < args.endIndex, let h = Int(args[i]) else { return nil }
            height = h
        case "--long-edge-cells":
            i += 1
            guard i < args.endIndex, let l = Int(args[i]) else { return nil }
            longEdgeCells = l
        case "--list-scenarios":
            listScenarios = true
        case "--custom-scenario":
            i += 1
            guard i < args.endIndex else { return nil }
            customScenarioPath = args[i]
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            break
        }
        i += 1
    }

    guard listScenarios || scenario != nil || customScenarioPath != nil else {
        printError("Missing required argument: --scenario or --custom-scenario or --list-scenarios")
        printUsage()
        return nil
    }

    if !listScenarios && outputDir == nil {
        printError("Missing required argument: --output-dir")
        printUsage()
        return nil
    }

    return Arguments(
        scenario: scenario,
        seed: seed,
        ticks: ticks,
        outputDir: outputDir ?? "",
        fps: fps,
        format: format,
        width: width,
        height: height,
        longEdgeCells: longEdgeCells,
        listScenarios: listScenarios,
        customScenarioPath: customScenarioPath
    )
}

func printUsage() {
    let stderr = FileHandle.standardError
    let msg = """
Usage: TestAnimationRenderer [options]

Required:
  --scenario <id>           Built-in scenario ID (use --list-scenarios to see all)
  --custom-scenario <path>  Path to custom scenario JSON file
  --output-dir <path>       Output directory for frames (required unless --list-scenarios)
  --list-scenarios          List all built-in scenarios and exit

Options:
  --seed <uint64>           Simulation seed (default: 42)
  --ticks <int>             Number of ticks to simulate (default: 300)
  --fps <int>               Output video FPS (default: 30)
  --format <png|gif|mp4>    Output format (default: png)
  --width <int>             Video width in pixels (default: 640)
  --height <int>            Video height in pixels (default: 360)
  --long-edge-cells <int>   Long edge cells for viewport (default: 200)
  --help, -h                Show this help

Examples:
  TestAnimationRenderer --list-scenarios
  TestAnimationRenderer --scenario sand-water-displacement --output-dir frames --ticks 60
  TestAnimationRenderer --scenario beacon-run-full --output-dir frames --format mp4 --ticks 600
  TestAnimationRenderer --custom-scenario my-scenario.json --output-dir frames --format gif
"""
    stderr.write(msg.data(using: .utf8)!)
}

func printError(_ message: String) {
    let stderr = FileHandle.standardError
    stderr.write(("Error: \(message)\n").data(using: .utf8)!)
}

func printInfo(_ message: String) {
    let stdout = FileHandle.standardOutput
    stdout.write(("\(message)\n").data(using: .utf8)!)
}

func main() throws {
    guard let args = parseArguments() else {
        exit(1)
    }

    // Handle list scenarios
    if args.listScenarios {
        printInfo("Available built-in scenarios:")
        for (id, name, desc) in BuiltInScenario.list() {
            printInfo("  \(id): \(name) - \(desc)")
        }
        return
    }

    // Load scenario
    let scenario: Scenario
    if let customPath = args.customScenarioPath {
        scenario = try CustomScenarioLoader.load(from: URL(fileURLWithPath: customPath))
    } else if let scenarioId = args.scenario {
        guard let s = BuiltInScenario.byId(scenarioId) else {
            printError("Unknown scenario: \(scenarioId)")
            printInfo("Use --list-scenarios to see available scenarios")
            exit(1)
        }
        // Override seed if provided
        scenario = Scenario(
            id: s.id,
            name: s.name,
            description: s.description,
            seed: args.seed,
            initialCommands: s.initialCommands,
            autoPolicy: s.autoPolicy,
            viewportCenter: s.viewportCenter,
            longEdgeCells: s.longEdgeCells
        )
    } else {
        printError("No scenario specified")
        exit(1)
    }

    // Prepare output directory
    let outputDir = URL(fileURLWithPath: args.outputDir)
    try FrameWriter.ensureOutputDirectory(outputDir)

    // Print configuration
    printInfo("Scenario: \(scenario.name) (\(scenario.id))")
    printInfo("Seed: \(scenario.seed)")
    printInfo("Ticks: \(args.ticks)")
    printInfo("Output: \(outputDir.path)")
    printInfo("Format: \(args.format.rawValue)")
    printInfo("Resolution: \(args.width)x\(args.height)")
    printInfo("Viewport long edge: \(scenario.longEdgeCells) cells")
    if args.format != .png {
        if VideoEncoder.isFFmpegAvailable() {
            printInfo("ffmpeg: available")
        } else {
            printInfo("ffmpeg: NOT found - will output PNG only")
        }
    }

    // Run capture
    var engine = try CaptureEngine(
        scenario: scenario,
        ticks: args.ticks,
        width: args.width,
        height: args.height,
        fps: args.fps,
        outputDirectory: outputDir,
        format: args.format
    )

    let startTime = Date()
    var frameCount = 0
    try engine.run { current, total in
        frameCount = current
        if current % 30 == 0 || current == total {
            printInfo("Progress: \(current)/\(total) frames")
        }
    }
    let elapsed = Date().timeIntervalSince(startTime)

    printInfo("Captured \(frameCount) frames in \(String(format: "%.2f", elapsed))s")

    // Encode video if requested
    if args.format != .png {
        let outputURL = outputDir.appendingPathComponent("animation.\(args.format.rawValue)")
        printInfo("Encoding \(args.format.rawValue.uppercased())...")
        do {
            try VideoEncoder.encode(
                format: args.format,
                framesDirectory: outputDir,
                outputURL: outputURL,
                fps: args.fps,
                width: args.width,
                height: args.height
            )
            printInfo("Video saved to: \(outputURL.path)")
        } catch {
            printError("Video encoding failed: \(error)")
            printInfo("PNG frames are still available in \(outputDir.path)")
            exit(1)
        }
    }

    printInfo("Done!")
}

do {
    try main()
} catch {
    printError("\(error)")
    exit(1)
}