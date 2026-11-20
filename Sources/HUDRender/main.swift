import Foundation
import GamePresentation
import SimulationCore

/// Headless HUD renderer. Builds a DisplayList from state and writes a PNG.
/// Usage: HUDRender --ref <sha> --out <png> [--seed N] [--tick N] [--width W] [--height H] [--material M] [--json <path>]
struct HUDRender {
    static let version = "0.44.0"

    static func main() {
        let args = CommandLine.arguments.dropFirst()
        var ref: String?
        var outPath: String?
        var seed: UInt64 = 42
        var tick: UInt64 = 0
        var width = 480
        var height = 270
        var material: Material = .sand
        var jsonPath: String?

        var i = args.startIndex
        while i < args.endIndex {
            let arg = args[i]
            switch arg {
            case "--ref":
                i = args.index(after: i)
                guard i < args.endIndex else { usageError("Missing value for --ref") }
                ref = args[i]
            case "--out":
                i = args.index(after: i)
                guard i < args.endIndex else { usageError("Missing value for --out") }
                outPath = args[i]
            case "--seed":
                i = args.index(after: i)
                guard i < args.endIndex, let v = UInt64(args[i]) else { usageError("Invalid --seed") }
                seed = v
            case "--tick":
                i = args.index(after: i)
                guard i < args.endIndex, let v = UInt64(args[i]) else { usageError("Invalid --tick") }
                tick = v
            case "--width":
                i = args.index(after: i)
                guard i < args.endIndex, let v = Int(args[i]) else { usageError("Invalid --width") }
                width = v
            case "--height":
                i = args.index(after: i)
                guard i < args.endIndex, let v = Int(args[i]) else { usageError("Invalid --height") }
                height = v
            case "--material":
                i = args.index(after: i)
                guard i < args.endIndex, let raw = Int(args[i]), let m = Material(rawValue: UInt8(raw)) else { usageError("Invalid --material") }
                material = m
            case "--json":
                i = args.index(after: i)
                guard i < args.endIndex else { usageError("Missing value for --json") }
                jsonPath = args[i]
            case "-h", "--help":
                printUsage()
                return
            default:
                usageError("Unknown argument: \(arg)")
            }
            i = args.index(after: i)
        }

        guard let ref = ref else { usageError("--ref is required") }
        guard let outPath = outPath else { usageError("--out is required") }

        // Build state from simulation
        let state: DisplayListState
        do {
            state = try buildState(
                seed: seed,
                tick: tick,
                material: material
            )
        } catch {
            fatalError("Failed to build state: \(error)")
        }

        // Build display list
        let list = HUDLayout.gameUI(width: width, height: height, state: state)

        // Rasterize with opaque black background
        let pixels = DisplayListRaster.rasterize(list, background: .rgba(0, 0, 0, 255))

        // Write PNG
        do {
            try PNGWriter.write(pixels, width: width, height: height, to: outPath)
        } catch {
            fatalError("Failed to write PNG: \(error)")
        }

        // Write JSON provenance if requested
        if let jsonPath = jsonPath {
            let itemsJson = list.items.map { item -> [String: Any] in
                var dict: [String: Any] = ["kind": itemKind(item)]
                if let frame = item.frame {
                    dict["rect"] = ["x": frame.x, "y": frame.y, "width": frame.width, "height": frame.height]
                }
                if case .fillRect(_, let color) = item, let frame = item.frame {
                    dict["color"] = ["r": color.r, "g": color.g, "b": color.b, "a": color.a]
                } else if case .strokeRect(_, let color, _) = item, let frame = item.frame {
                    dict["color"] = ["r": color.r, "g": color.g, "b": color.b, "a": color.a]
                } else if case .roundRect(_, let color, _) = item, let frame = item.frame {
                    dict["color"] = ["r": color.r, "g": color.g, "b": color.b, "a": color.a]
                } else if case .text(let rect, let runs, _) = item {
                    dict["rect"] = ["x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height]
                    dict["text"] = runs.map { $0.text }.joined()
                    dict["bold"] = runs.first?.bold ?? false
                } else if case .swatch(_, let mat) = item, let frame = item.frame {
                    let color = DisplayColor.material(mat)
                    dict["color"] = ["r": color.r, "g": color.g, "b": color.b, "a": color.a]
                }
                if let tag = item.actionTag {
                    dict["actionTag"] = tag.jsonString
                }
                return dict
            }

            let json: [String: Any] = [
                "provenance": [
                    "ref": ref,
                    "seed": seed,
                    "tick": tick,
                    "width": width,
                    "height": height,
                    "material": material.rawValue,
                    "worldKind": "cave"
                ],
                "items": itemsJson
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted])
                try data.write(to: URL(fileURLWithPath: jsonPath))
            } catch {
                fatalError("Failed to write JSON: \(error)")
            }
        }
    }

    private static func itemKind(_ item: DisplayItem) -> String {
        switch item {
        case .fillRect: return "fillRect"
        case .strokeRect: return "strokeRect"
        case .roundRect: return "roundRect"
        case .text: return "text"
        case .swatch: return "swatch"
        case .clip: return "clip"
        case .hitRegion: return "hitRegion"
        }
    }

    private static func buildState(
        seed: UInt64,
        tick: UInt64,
        material: Material
    ) throws -> DisplayListState {
        // Create CaveRun which sets up world + simulation + character
        var run = try CaveRun(seed: seed, width: 256, height: 128)

        // Advance simulation for the requested number of ticks (no player input)
        for _ in 0..<tick {
            try run.advance(horizontal: 0, jump: false)
        }

        // Map CaveRun.Outcome to DisplayOutcome
        let displayOutcome: DisplayOutcome?
        switch run.outcome {
        case .playing: displayOutcome = .playing
        case .died: displayOutcome = .died
        }

        // Build DisplayListState from CaveRun
        let position = run.character.position

        return DisplayListState(
            version: version,
            worldKind: .cave,
            seed: seed,
            worldWidth: run.size.width,
            worldHeight: run.size.height,
            position: position,
            tick: tick,
            depth: run.world.spawn.y - position.y,
            outcome: displayOutcome,
            health: run.health,
            maxHealth: run.maxHealth,
            energy: nil, // CaveRun doesn't track energy yet
            maxEnergy: nil,
            collectedBeacons: 0,
            warden: nil,
            selectedMaterial: material,
            isCasting: false,
            discoveredMaterials: [.sand, .water, .fire, .steam, .lava, .gold],
            wand: Wand(),
            manaPool: ManaPool(),
            showCraftingGrid: false,
            craftingAllowed: false,
            craftingGrid: CraftingGrid(),
            framesPerSecond: nil,
            renderedChunks: nil,
            errorMessage: nil,
            hoveredMaterialName: material.wandName,
            hudVisible: true,
            controls: .keyboard,
            overlays: DisplayOverlayVisibility(stats: false, help: false, crafting: false)
        )
    }

    private static func usageError(_ msg: String) -> Never {
        fputs("Error: \(msg)\n\n", stderr)
        printUsage()
        exit(1)
    }

    private static func printUsage() {
        print("""
        HUDRender v\(version) — Headless game-UI PNG renderer

        Usage: HUDRender --ref <sha> --out <png> [options]

        Required:
          --ref <sha>       Git commit SHA or tag (provenance, recorded in --json)
          --out <path>      Output PNG path

        Optional:
          --seed <N>        World seed (default: 42)
          --tick <N>        Simulation tick (default: 0)
          --width <W>       Canvas width (default: 480)
          --height <H>      Canvas height (default: 270)
          --material <M>    Selected material rawValue (default: 2 = sand)
          --json <path>     Write action-tag provenance JSON
          -h, --help        Show this help
        """)
    }
}

HUDRender.main()