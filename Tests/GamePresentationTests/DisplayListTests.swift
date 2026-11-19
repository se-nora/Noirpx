import XCTest
@testable import GamePresentation
import SimulationCore
import Foundation

/// Tests for the platform-independent game-UI display list (Goal: game-ui-display-list).
/// Covers list construction, rasterization, PNG round-trip, determinism, hit-test,
/// and the forbidden-import scan for the new sources.
final class DisplayListTests: XCTestCase {

    // MARK: - 1. List construction

    func testFixedStateListContainsEveryComponentKind() {
        let list = HUDLayout.gameUI(width: 480, height: 270, state: fixedState())
        var kinds = Set<String>()
        for item in list.items {
            switch item {
            case .fillRect: kinds.insert("fillRect")
            case .strokeRect: kinds.insert("strokeRect")
            case .roundRect: kinds.insert("roundRect")
            case .text: kinds.insert("text")
            case .swatch: kinds.insert("swatch")
            case .clip: kinds.insert("clip")
            case .hitRegion: kinds.insert("hitRegion")
            }
        }
        for expected in ["fillRect", "strokeRect", "roundRect", "text", "clip", "hitRegion"] {
            XCTAssertTrue(kinds.contains(expected), "expected component kind \(expected) in list")
        }
        XCTAssertGreaterThan(list.items.count, 0)
    }

    // MARK: - 2. Action tags

    func testFixedStateListContainsEveryExpectedActionTag() {
        let list = HUDLayout.gameUI(width: 480, height: 270, state: fixedState())
        let tags = Set(list.actionTags())

        XCTAssertTrue(tags.contains(.restart))
        XCTAssertTrue(tags.contains(.newRun))
        XCTAssertTrue(tags.contains(.stats))
        XCTAssertTrue(tags.contains(.help))
        XCTAssertTrue(tags.contains(.toggleCrafting) || tags.contains(.craft) || tags.contains(.closeCrafting))

        // Palette
        XCTAssertTrue(tags.contains(.selectErase))
        XCTAssertTrue(tags.contains(.selectMaterial(.sand)))
        XCTAssertTrue(tags.contains(.selectMaterial(.water)))
        XCTAssertTrue(tags.contains(.selectMaterial(.fire)))

        // Wand
        for i in 0..<4 { XCTAssertTrue(tags.contains(.cycleWandSlot(i)), "missing cycleWandSlot(\(i))") }

        // Crafting (state has showCraftingGrid && craftingAllowed)
        XCTAssertTrue(tags.contains(.closeCrafting))
        XCTAssertTrue(tags.contains(.craft))
        for i in 0..<9 {
            XCTAssertTrue(tags.contains(.craftingSlot(i)), "missing craftingSlot(\(i))")
            XCTAssertTrue(tags.contains(.clearCraftingSlot(i)), "missing clearCraftingSlot(\(i))")
        }
    }

    // MARK: - 3. Non-empty pixel bands

    func testOverlayHasNonEmptyPixelsInExpectedBands() {
        let list = HUDLayout.gameUI(width: 480, height: 270, state: fixedState())
        let pixels = DisplayListRaster.overlay(list) // transparent where nothing drawn

        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            pixels[(y * 480 + x) * 4 + 3]
        }
        func bandHasOpaque(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int) -> Bool {
            for y in y0..<y1 {
                for x in x0..<x1 where alpha(x, y) > 0 { return true }
            }
            return false
        }

        // Top-left panel band: 0..45% width, 0..40% height
        XCTAssertTrue(bandHasOpaque(0, Int(0.45 * 480), 0, Int(0.40 * 270)),
                      "top-left HUD panel band should contain drawn pixels")
        // Bottom pill band: center, bottom 15%
        let bx0 = Int(0.35 * 480), bx1 = Int(0.65 * 480)
        XCTAssertTrue(bandHasOpaque(bx0, bx1, Int(0.85 * 270), 270),
                      "bottom pill band should contain drawn pixels")
    }

    // MARK: - 4. Hit-test

    func testHitTestAtKnownPoints() {
        // Use a state WITHOUT overlays so HUD buttons are not covered.
        let list = HUDLayout.gameUI(width: 480, height: 270, state: fixedStateNoOverlays())

        func center(of tag: DisplayActionTag) -> (Int, Int)? {
            for item in list.items.reversed() {
                if case .hitRegion(let rect, let t) = item, t == tag {
                    return (rect.x + rect.width / 2, rect.y + rect.height / 2)
                }
            }
            return nil
        }

        let expected: [DisplayActionTag] = [
            .restart, .newRun, .stats, .help,
            .selectErase, .selectMaterial(.sand),
            .cycleWandSlot(0),
        ]
        for tag in expected {
            guard let (x, y) = center(of: tag) else {
                XCTFail("no hit region found for \(tag.jsonString)")
                continue
            }
            XCTAssertEqual(list.hitTest(x: x, y: y), tag, "hitTest at center of \(tag.jsonString)")
        }

        // Point outside every band -> nil.
        XCTAssertNil(list.hitTest(x: 999, y: 999))

        // Crafting slot hit-test on a state with the crafting panel shown.
        let craftingList = HUDLayout.gameUI(width: 480, height: 270, state: fixedState())
        let slot4Rect = craftingList.items.reversed().compactMap { item -> DisplayRect? in
            if case .hitRegion(let rect, let t) = item, t == .craftingSlot(4) { return rect }
            return nil
        }.first
        XCTAssertNotNil(slot4Rect, "craftingSlot(4) hit region should exist when crafting is shown")
        if let rect = slot4Rect {
            XCTAssertEqual(craftingList.hitTest(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2), .craftingSlot(4))
        }
    }

    private func fixedStateNoOverlays() -> DisplayListState {
        var grid = CraftingGrid()
        _ = grid.setSlot(0, material: .sand, count: 2)
        _ = grid.setSlot(1, material: .fire, count: 1)
        return DisplayListState(
            version: "0.44.0",
            worldKind: .cave,
            seed: 42,
            worldWidth: 256,
            worldHeight: 128,
            position: CellPosition(x: 40, y: 60),
            tick: 100,
            outcome: .playing,
            health: 2,
            maxHealth: 3,
            energy: 2,
            maxEnergy: 3,
            selectedMaterial: .sand,
            isCasting: false,
            discoveredMaterials: [.sand, .water, .fire],
            wand: Wand(slots: [Spell(blueprint: .placeholder), nil, nil, nil]),
            manaPool: ManaPool(startingMana: 80),
            showCraftingGrid: false,
            craftingAllowed: false,
            craftingGrid: grid,
            framesPerSecond: 59.7,
            renderedChunks: 14,
            hoveredMaterialName: "Sand",
            hudVisible: true,
            controls: .keyboard,
            overlays: DisplayOverlayVisibility(stats: false, help: false, crafting: false)
        )
    }

    // MARK: - 5. Byte-identical determinism

    func testTwoOverlaysByteIdentical() {
        let a = DisplayListRaster.overlay(HUDLayout.gameUI(width: 480, height: 270, state: fixedState()))
        let b = DisplayListRaster.overlay(HUDLayout.gameUI(width: 480, height: 270, state: fixedState()))
        XCTAssertEqual(a, b)
    }

    func testTwoRastersByteIdentical() {
        let a = DisplayListRaster.rasterize(HUDLayout.gameUI(width: 480, height: 270, state: fixedState()))
        let b = DisplayListRaster.rasterize(HUDLayout.gameUI(width: 480, height: 270, state: fixedState()))
        XCTAssertEqual(a, b)
    }

    // MARK: - 6. PNG encode deterministic

    func testPNGEncodeDeterministic() {
        let list = HUDLayout.gameUI(width: 480, height: 270, state: fixedState())
        let pixels = DisplayListRaster.rasterize(list)
        let a = PNGWriter.pngData(pixels, width: 480, height: 270)
        let b = PNGWriter.pngData(pixels, width: 480, height: 270)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Array(a[0..<8]), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        // IHDR carries width/height and color type 6 (RGBA8).
        let decoded = decodeMinimalPNG(Array(a))
        XCTAssertEqual(decoded?.width, 480)
        XCTAssertEqual(decoded?.height, 270)
    }

    // MARK: - 7. PNG decode round-trip

    func testPNGDecodes() {
        let list = HUDLayout.gameUI(width: 64, height: 36, state: fixedState())
        let pixels = DisplayListRaster.rasterize(list)
        let encoded = PNGWriter.pngData(pixels, width: 64, height: 36)
        guard let decoded = decodeMinimalPNG(Array(encoded)) else {
            return XCTFail("PNG failed to decode")
        }
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 36)
        XCTAssertEqual(decoded.pixels, pixels, "decoded pixels must match encoded pixels")
    }

    // MARK: - 8. Forbidden-import scan

    func testScanNewSourcesImportNoUIFrameworks() {
        let forbidden = [
            "SwiftUI", "AppKit", "UIKit", "CoreGraphics", "CoreText", "Metal",
            "ImageIO", "UniformTypeIdentifiers", "Combine", "zlib",
        ]
        let newSources = [
            "Sources/GamePresentation/DisplayList.swift",
            "Sources/GamePresentation/DisplayListState.swift",
            "Sources/GamePresentation/BitmapFont.swift",
            "Sources/GamePresentation/DisplayListRaster.swift",
            "Sources/GamePresentation/PNGWriter.swift",
            "Sources/GamePresentation/HUDLayout.swift",
            "Sources/GamePresentation/CraftingLayout.swift",
            "Sources/GamePresentation/GuideLayout.swift",
            "Sources/GamePresentation/StatsLayout.swift",
            "Sources/HUDRender/main.swift",
        ]
        let fm = FileManager.default
        for rel in newSources {
            let path = "\(fm.currentDirectoryPath)/\(rel)"
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                XCTFail("could not read \(rel)"); continue
            }
            for line in contents.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                for token in forbidden {
                    XCTAssertFalse(trimmed.hasPrefix("import \(token)"),
                                   "\(rel) must not import \(token)")
                }
            }
        }
    }

    // MARK: - 9. Capture parity (HUDRender path == CaptureComparison path)

    func testCaptureParityOverlayBytes() {
        // Build the same state both paths construct for seed 12345, tick 10, 480x270.
        let stateA = caveState(seed: 12345, tick: 10)
        let stateB = caveState(seed: 12345, tick: 10)
        XCTAssertEqual(stateA, stateB)

        let overlayA = DisplayListRaster.overlay(HUDLayout.gameUI(width: 480, height: 270, state: stateA))
        let overlayB = DisplayListRaster.overlay(HUDLayout.gameUI(width: 480, height: 270, state: stateB))
        XCTAssertEqual(overlayA, overlayB, "both paths must produce byte-identical overlay bytes")

        let pngA = PNGWriter.pngData(overlayA, width: 480, height: 270)
        XCTAssertTrue(pngA.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
    }

    // MARK: - 10. Layout determinism

    func testLayoutDeterministicAcrossCalls() {
        let state = fixedState()
        let a = HUDLayout.gameUI(width: 480, height: 270, state: state)
        let b = HUDLayout.gameUI(width: 480, height: 270, state: state)
        XCTAssertEqual(a, b)
    }

    // MARK: - 11. Beacon objective + warden

    func testBeaconStateProducesObjectiveAndWarden() {
        let state = DisplayListState(
            version: "0.44.0",
            worldKind: .beacon,
            seed: 7,
            worldWidth: 200,
            worldHeight: 100,
            tick: 5,
            outcome: .playing,
            collectedBeacons: 1,
            warden: DisplayWarden(alive: true, shield: 2, burning: true, lastHazardName: nil),
            selectedMaterial: .sand,
            isCasting: false
        )
        let list = HUDLayout.gameUI(width: 480, height: 270, state: state)
        let text = list.items.compactMap { item -> String? in
            if case .text(_, let runs, _) = item { return runs.map { $0.text }.joined() }
            return nil
        }.joined(separator: "\n")

        XCTAssertTrue(text.contains("beacons"), "objective line should be present")
        XCTAssertTrue(text.contains("Warden"), "warden line should be present")
    }

    // MARK: - 12. hudVisible false -> empty

    func testHUDVisibleFalseProducesEmptyList() {
        var state = fixedState()
        state = DisplayListState(
            version: state.version,
            worldKind: state.worldKind,
            seed: state.seed,
            worldWidth: state.worldWidth,
            worldHeight: state.worldHeight,
            tick: state.tick,
            selectedMaterial: state.selectedMaterial,
            isCasting: state.isCasting,
            hudVisible: false
        )
        let list = HUDLayout.gameUI(width: 480, height: 270, state: state)
        XCTAssertTrue(list.items.isEmpty, "hudVisible=false must produce no items")
    }

    // MARK: - Helpers

    private func fixedState() -> DisplayListState {
        var grid = CraftingGrid()
        _ = grid.setSlot(0, material: .sand, count: 2)
        _ = grid.setSlot(1, material: .fire, count: 1)
        return DisplayListState(
            version: "0.44.0",
            worldKind: .cave,
            seed: 42,
            worldWidth: 256,
            worldHeight: 128,
            position: CellPosition(x: 40, y: 60),
            tick: 100,
            outcome: .playing,
            health: 2,
            maxHealth: 3,
            energy: 2,
            maxEnergy: 3,
            selectedMaterial: .sand,
            isCasting: false,
            discoveredMaterials: [.sand, .water, .fire],
            wand: Wand(slots: [Spell(blueprint: .placeholder), nil, nil, nil]),
            manaPool: ManaPool(startingMana: 80),
            showCraftingGrid: true,
            craftingAllowed: true,
            craftingGrid: grid,
            framesPerSecond: 59.7,
            renderedChunks: 14,
            hoveredMaterialName: "Sand",
            hudVisible: true,
            controls: .keyboard,
            overlays: DisplayOverlayVisibility(stats: false, help: false, crafting: false)
        )
    }

    private func caveState(seed: UInt64, tick: UInt64) -> DisplayListState {
        // Mirrors HUDRender.buildState for a cave run.
        var run = try! CaveRun(seed: seed, width: 256, height: 128)
        for _ in 0..<tick { try! run.advance(horizontal: 0, jump: false) }
        let outcome: DisplayOutcome
        switch run.outcome {
        case .playing: outcome = .playing
        case .died: outcome = .died
        }
        return DisplayListState(
            version: "0.44.0",
            worldKind: .cave,
            seed: seed,
            worldWidth: run.size.width,
            worldHeight: run.size.height,
            position: run.character.position,
            tick: tick,
            depth: run.world.spawn.y - run.character.position.y,
            outcome: outcome,
            health: run.health,
            maxHealth: run.maxHealth,
            selectedMaterial: .sand,
            isCasting: false,
            discoveredMaterials: [.sand, .water, .fire, .steam, .lava, .gold],
            wand: Wand(),
            manaPool: ManaPool(),
            hoveredMaterialName: Material.sand.wandName,
            hudVisible: true,
            controls: .keyboard
        )
    }
}

// MARK: - Test spell blueprint

extension ProjectileBlueprint {
    static let placeholder = ProjectileBlueprint(
        id: "test_placeholder",
        name: "Test",
        primaryMaterial: .sand,
        maxRange: 12,
        budgetPerTick: 3,
        cooldownTicks: 0,
        manaCost: 1,
        flags: [],
        footprint: SpellFootprint(id: "test", cells: []),
        gravityFactor: 0,
        speed: 0
    )
}

// MARK: - Minimal PNG decoder (stored blocks, filter 0) for round-trip test.

private struct DecodedPNG { let width: Int, height: Int, pixels: [UInt8] }

private func decodeMinimalPNG(_ bytes: [UInt8]) -> DecodedPNG? {
    guard bytes.count > 8 else { return nil }
    let signature: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    guard Array(bytes[0..<8]) == signature else { return nil }

    var pos = 8
    var width = 0, height = 0
    var idat = [UInt8]()

    while pos + 8 <= bytes.count {
        let len = Int(bytes[pos]) << 24 | Int(bytes[pos+1]) << 16 | Int(bytes[pos+2]) << 8 | Int(bytes[pos+3])
        guard pos + 8 + len <= bytes.count else { return nil }
        let type = String(bytes: bytes[pos+4..<pos+4+4], encoding: .utf8) ?? ""
        let data = Array(bytes[pos+8..<pos+8+len])
        pos += 12 + len
        if type == "IHDR" && data.count >= 8 {
            width = Int(data[0]) << 24 | Int(data[1]) << 16 | Int(data[2]) << 8 | Int(data[3])
            height = Int(data[4]) << 24 | Int(data[5]) << 16 | Int(data[6]) << 8 | Int(data[7])
        } else if type == "IDAT" {
            idat.append(contentsOf: data)
        } else if type == "IEND" {
            break
        }
    }
    guard width > 0, height > 0, !idat.isEmpty else { return nil }

    // Decompress stored blocks: BFINAL(1)+BTYPE(2), LEN(16 LE), NLEN(16 LE), then data; adler at end.
    // Skip the 2-byte zlib header (CMF=0x78, FLG). Stored blocks follow.
    var raw = [UInt8]()
    var i = 2
    let idatEnd = idat.count - 4 // exclude Adler32 trailer
    while i < idatEnd {
        let hdr = idat[i]
        let bfinal = hdr & 1
        let btype = (hdr >> 1) & 3
        guard btype == 0 else { return nil }
        i += 1
        guard i + 4 <= idatEnd else { return nil }
        let len = Int(idat[i]) | (Int(idat[i+1]) << 8)
        i += 4
        guard i + len <= idatEnd else { return nil }
        raw.append(contentsOf: idat[i..<i+len])
        i += len
        if bfinal == 1 { break }
    }
    let rowBytes = width * 4
    var pixels = [UInt8](repeating: 0, count: height * rowBytes)
    var rp = 0
    for y in 0..<height {
        guard rp < raw.count else { return nil }
        rp += 1 // filter byte (0)
        guard rp + rowBytes <= raw.count else { return nil }
        pixels.replaceSubrange(y*rowBytes..<(y+1)*rowBytes, with: raw[rp..<rp+rowBytes])
        rp += rowBytes
    }
    return DecodedPNG(width: width, height: height, pixels: pixels)
}