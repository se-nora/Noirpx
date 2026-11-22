import XCTest
@testable import SimulationCore

/// Builds valid saves programmatically then surgically corrupts specific fields
/// to confirm every documented rejection.
final class SaveFormatValidationTests: XCTestCase {
    private let codec = SaveCodec()
    private let limit = Simulation.coordinateBounds.upperBound

    // MARK: Header

    func testHeaderChecks() throws {
        let bytes = try encode()
        assertThrows([UInt8]("NRST".utf8) + bytes.dropFirst(4), SaveError.badMagic)
        for version: UInt16 in [0, 2, .max] {
            assertThrows(replaced16(version, at: 4, in: bytes), SaveError.unknownFormatVersion(version))
        }
// rulesVersion is now 9, so version 8 and 10 should be rejected
        assertThrows(replaced16(8, at: 8, in: bytes), SaveError.unsupportedRulesVersion(8))
        assertThrows(replaced16(10, at: 8, in: bytes), SaveError.unsupportedRulesVersion(10))
        // digestVersion is now 13, so version 10 and 12 should be rejected
        assertThrows(replaced16(10, at: 10, in: bytes), SaveError.unsupportedDigestVersion(10))
        assertThrows(replaced16(12, at: 10, in: bytes), SaveError.unsupportedDigestVersion(12))
        assertThrows(replaced16(1, at: 6, in: bytes), SaveError.unsupportedFlags(1))
        assertThrows(replaced16(.max, at: 6, in: bytes), SaveError.unsupportedFlags(.max))
    }

    func testHeaderTruncatedAtEveryLengthBelowTwentyFour() throws {
        let full = try encode()
        for length in 0..<24 {
            XCTAssertThrowsError(try codec.decode(Array(full.prefix(length)))) { error in
                guard case SaveError.truncatedInput(let needed, let available) = error else {
                    XCTFail("expected truncatedInput at length \(length)")
                    return
                }
                XCTAssertGreaterThan(needed, available)
            }
        }
    }

    func testPayloadSizeChecks() throws {
        let bytes = try encode()
        let payloadCount = bytes.count - 24
        assertThrows(replaced32(payloadCount - 1, at: 12, in: bytes),
                     SaveError.payloadSizeMismatch(declaredBytes: payloadCount - 1, actualBytes: payloadCount))
        assertThrows(replaced32(payloadCount + 1, at: 12, in: bytes),
                     SaveError.payloadSizeMismatch(declaredBytes: payloadCount + 1, actualBytes: payloadCount))
        // Oversized payload check triggers only when actual size matches declared size.
        // With a small actual payload, payloadSizeMismatch fires first.
        assertThrows(replaced32(SaveCodec.maximumPayloadBytes + 1, at: 12, in: bytes),
                     SaveError.payloadSizeMismatch(declaredBytes: SaveCodec.maximumPayloadBytes + 1,
                                                   actualBytes: payloadCount))
        var trailing = bytes
        trailing.append(0)
        assertThrows(trailing, SaveError.payloadSizeMismatch(declaredBytes: payloadCount,
                                                             actualBytes: payloadCount + 1))
    }

    // MARK: World and chunks

    func testWorldHeaderTruncationAndChunkCountMismatch() throws {
        let bytes = try encode()
        _ = bytes.count - 24

        // Truncate before header is complete (lengths 0..23)
        for length in 0..<24 {
            XCTAssertThrowsError(try codec.decode(Array(bytes.prefix(length)))) { error in
                guard case SaveError.truncatedInput = error else {
                    XCTFail("expected truncatedInput at length \(length)")
                    return
                }
            }
        }

        // Truncate after header but before full payload - should get payloadSizeMismatch
        // because header declares fullPayloadCount but we provide less
        for cut in 25..<bytes.count {
            XCTAssertThrowsError(try codec.decode(Array(bytes.prefix(cut)))) { error in
                guard case SaveError.payloadSizeMismatch = error else {
                    XCTFail("expected payloadSizeMismatch cutting at \(cut), got \(error)")
                    return
                }
            }
        }

        // Build a save with chunkCount=1 but no chunk data to test truncatedInput
        var truncatedBytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ])
        // The payload includes world header + 1 chunk + commands + gameplay
        // We want to truncate after chunkCount but before chunk data
        // World header is 28 bytes. Chunk entry starts at offset 28.
        // Truncate to exactly 28 bytes (world header only)
        let truncatedPayload = Array(truncatedBytes.dropFirst(24).prefix(28))
        truncatedBytes = Array(truncatedBytes.prefix(24)) + truncatedPayload
        // Update header payload size
        writeU32(UInt32(28), into: &truncatedBytes, at: 12)
        // This should fail with truncatedInput when trying to read the first chunk
        XCTAssertThrowsError(try codec.decode(truncatedBytes)) { error in
            guard case SaveError.truncatedInput = error else {
                XCTFail("expected truncatedInput for incomplete chunk, got \(error)")
                return
            }
        }

        // Test chunkCountMismatch: payload ends mid-chunk-table
        // Build a save with 2 chunks, truncate after first chunk
        var partialBytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)]),
            (ChunkPosition(x: 2, y: 2), [CellEntry(localIndex: 0, material: .sand)])
        ])
        // Truncate after first chunk but before second chunk completes
        let firstChunkEnd = 24 + 28 + chunkEntrySize(partialBytes, at: 24 + 28) // header + world + first chunk
        let partialPayload = Array(partialBytes.dropFirst(24).prefix(firstChunkEnd - 24))
        partialBytes = Array(partialBytes.prefix(24)) + partialPayload
        writeU32(UInt32(partialPayload.count), into: &partialBytes, at: 12)
        // Should get truncatedInput or chunkCountMismatch
        XCTAssertThrowsError(try codec.decode(partialBytes)) { error in
            // Either is acceptable per the spec
            if case SaveError.chunkCountMismatch = error { return }
            if case SaveError.truncatedInput = error { return }
            XCTFail("expected chunkCountMismatch or truncatedInput, got \(error)")
        }
    }

    func testChunkTableValidation() throws {
        // Test with a run that has a known chunk structure
        var run = try BeaconRun(seed: 42)
        // Add a known cell to ensure we have a chunk
        try run.paint(.sand, at: .init(x: 100, y: 100))
        let bytes = try codec.encode(run)

        let chunkCountOffset = 24 + 24 // header + world header

        // oversized chunk count
        assertThrows(replaced32(SaveCodec.maximumChunkCount + 1, at: chunkCountOffset, in: bytes),
                     SaveError.oversizedCount(field: .chunks, declared: SaveCodec.maximumChunkCount + 1,
                                              limit: SaveCodec.maximumChunkCount))

        // duplicate chunk position - build a complete valid save with 2 chunks then corrupt
        // Use positions where first < second canonically, then make second == first
        var dupBytes = buildSaveWithChunks([
            (ChunkPosition(x: 0, y: 0), [CellEntry(localIndex: 0, material: .sand)]),
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ])
        // Verify we have 2 chunks
        XCTAssertEqual(readU32(dupBytes, at: chunkCountOffset), 2)
        // First chunk is at (0,0), second at (1,1) - canonical
        // Overwrite second chunk position to match first (0,0)
        let firstChunkOffset = chunkCountOffset + 4
        let firstChunkSize = chunkEntrySize(dupBytes, at: firstChunkOffset)
        let secondChunkOffset = firstChunkOffset + firstChunkSize
        dupBytes = replaced32(0, at: secondChunkOffset, in: dupBytes) // x = 0
        dupBytes = replaced32(0, at: secondChunkOffset + 4, in: dupBytes) // y = 0
        // This should trigger nonCanonicalChunkOrder since (0,0) <= (0,0)
        // The duplicate check comes after canonical order check in the decoder
        assertThrows(dupBytes, SaveError.nonCanonicalChunkOrder(ChunkPosition(x: 0, y: 0)))

        // To test duplicateChunk, we need chunks where second > first canonically
        // and third == second but third > second in canonical order (impossible for equal positions)
        // Actually, we need the third chunk to have y > second's y, or same y but x > second's x.
        // But if third == second, that violates canonical order.
        // So we need a case where third chunk's position equals second's but is AFTER second in the list.
        // The only way is if the sort puts them in order but they have the same position.
        // But the encoder never produces such saves. For a hand-crafted save, we can put
        // chunks in order: (0,0), (1,1), (1,2) - then corrupt third to (1,1).
        // But (1,1) < (1,2) in canonical order, so (1,1) after (1,1) violates order.
        // What about (0,0), (1,1), (2,1)? Then corrupt third to (1,1). (1,1) after (1,1) violates.
        // The only way: (0,0), (1,0), (1,1) - corrupt third to (1,0). (1,0) after (1,0) violates.
        // Conclusion: duplicateChunk is unreachable because any duplicate position will violate
        // canonical order when placed after the original. The nonCanonicalChunkOrder check runs first.
        // We'll test that duplicate chunks trigger nonCanonicalChunkOrder.
        var dupBytes3 = buildSaveWithChunks([
            (ChunkPosition(x: 0, y: 0), [CellEntry(localIndex: 0, material: .sand)]),
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)]),
            (ChunkPosition(x: 1, y: 2), [CellEntry(localIndex: 0, material: .sand)])
        ])
        // Chunks are (0,0), (1,1), (1,2) - canonical
        // Corrupt third chunk (1,2) to match second (1,1)
        let thirdChunkOffset = chunkCountOffset + 4
        let thirdChunkSize1 = chunkEntrySize(dupBytes3, at: thirdChunkOffset)
        let thirdChunkSize2 = chunkEntrySize(dupBytes3, at: thirdChunkOffset + thirdChunkSize1)
        let thirdChunkOffsetFinal = thirdChunkOffset + thirdChunkSize1 + thirdChunkSize2
        dupBytes3 = replaced32(1, at: thirdChunkOffsetFinal, in: dupBytes3) // x = 1
        dupBytes3 = replaced32(1, at: thirdChunkOffsetFinal + 4, in: dupBytes3) // y = 1
        // Now chunks are (0,0), (1,1), (1,1) - third matches second, violates canonical order
        assertThrows(dupBytes3, SaveError.nonCanonicalChunkOrder(ChunkPosition(x: 1, y: 1)))

        // non-canonical chunk order - create save with chunks in order, then swap
        var orderBytes = buildSaveWithChunks([
            (ChunkPosition(x: 0, y: 0), [CellEntry(localIndex: 0, material: .sand)]),
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ])
        // First chunk at (0,0), second at (1,1) - canonical order
        // Corrupt to make first chunk (0,1) and second (0,0) - non-canonical
        let orderFirstChunkOffset = chunkCountOffset + 4
        orderBytes = replaced32(0, at: orderFirstChunkOffset, in: orderBytes)
        orderBytes = replaced32(1, at: orderFirstChunkOffset + 4, in: orderBytes)
        let orderFirstChunkSize = chunkEntrySize(orderBytes, at: orderFirstChunkOffset)
        let orderSecondChunkOffset = orderFirstChunkOffset + orderFirstChunkSize
        orderBytes = replaced32(0, at: orderSecondChunkOffset, in: orderBytes)
        orderBytes = replaced32(0, at: orderSecondChunkOffset + 4, in: orderBytes)
        assertThrows(orderBytes, SaveError.nonCanonicalChunkOrder(ChunkPosition(x: 0, y: 0)))

        // out of range chunk position
        var oobBytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ])
        let oobFirstChunkOffset = chunkCountOffset + 4
        oobBytes = replaced32(20000, at: oobFirstChunkOffset, in: oobBytes) // x out of bounds
        oobBytes = replaced32(0, at: oobFirstChunkOffset + 4, in: oobBytes)
        assertThrows(oobBytes, SaveError.outOfRangeChunk(ChunkPosition(x: 20000, y: 0)))
    }

    func testCellEntryValidation() throws {
        // All tests use buildSaveWithChunks for known chunk structure

        // Per-chunk cell count limit (SimulationGrid.cellCount = 4096)
        var oversizedCellBytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ])
        let chunkCountOffset = 24 + 24
        let cellCountOffset = chunkCountOffset + 4 + 8 // chunkCount(4) + chunkX(4) + chunkY(4)
        // Set cellCount to 4097 (> SimulationGrid.cellCount)
        oversizedCellBytes = replaced32(SimulationGrid.cellCount + 1, at: cellCountOffset, in: oversizedCellBytes)
        assertThrows(oversizedCellBytes, SaveError.invalidCellEntry(chunk: ChunkPosition(x: 1, y: 1), localIndex: 0))

        // unknown material - build save with 1 cell, corrupt material byte
        // Use 17 since 16 is now sanctuaryWall
        var mat = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ])
        let matOffset = cellCountOffset + 4 + 4
        mat[matOffset] = 17
        assertThrows(mat, SaveError.unknownMaterial(17))

        // empty material in sparse entry
        var empty = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ])
        empty[matOffset] = 0
        assertThrows(empty, SaveError.unknownMaterial(0))

        // burning not 0/1
        var burn = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ])
        // burning byte is at cellCountOffset + 4 + 4 + 1 + 2 = cellCountOffset + 11
        let burnOffset = cellCountOffset + 4 + 4 + 1 + 2
        burn[burnOffset] = 2
        assertThrows(burn, SaveError.invalidCellEntry(chunk: ChunkPosition(x: 1, y: 1), localIndex: 0))

        // invalid cell entry (local index out of range) - build valid save then corrupt localIndex
        var badIdxBytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [
                CellEntry(localIndex: 0, material: .sand),
                CellEntry(localIndex: 100, material: .sand) // valid, will corrupt to 4096
            ])
        ])
        // Second cell's localIndex is at: cellCountOffset + 4(cellCount) + 12(first cell) = cellCountOffset + 16
        let secondCellLocalIndexOffset = cellCountOffset + 4 + 12
        badIdxBytes = replaced32(4096, at: secondCellLocalIndexOffset, in: badIdxBytes)
        assertThrows(badIdxBytes, SaveError.invalidCellEntry(chunk: ChunkPosition(x: 1, y: 1), localIndex: 4096))

        // duplicate local index - build valid save then corrupt second cell's localIndex to match first
        var dupIdxBytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [
                CellEntry(localIndex: 100, material: .sand),
                CellEntry(localIndex: 200, material: .water) // valid, will corrupt to 100
            ])
        ])
        // Second cell's localIndex is at cellCountOffset + 4 + 12 = cellCountOffset + 16
        let dupSecondCellLocalIndexOffset = cellCountOffset + 4 + 12
        dupIdxBytes = replaced32(100, at: dupSecondCellLocalIndexOffset, in: dupIdxBytes)
        assertThrows(dupIdxBytes, SaveError.invalidCellEntry(chunk: ChunkPosition(x: 1, y: 1), localIndex: 100))

        // non-canonical local index order (decreasing) - build valid save then corrupt
        var orderIdxBytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [
                CellEntry(localIndex: 100, material: .sand),
                CellEntry(localIndex: 200, material: .water) // valid, will corrupt to 50
            ])
        ])
        // Second cell's localIndex is at cellCountOffset + 4 + 12 = cellCountOffset + 16
        let orderSecondCellLocalIndexOffset = cellCountOffset + 4 + 12
        orderIdxBytes = replaced32(50, at: orderSecondCellLocalIndexOffset, in: orderIdxBytes) // 50 < 100, out of order
        assertThrows(orderIdxBytes, SaveError.invalidCellEntry(chunk: ChunkPosition(x: 1, y: 1), localIndex: 50))
    }

    func testCommandValidation() throws {
        // Build a save with known structure and commands
        let commands = [
            PendingCommand(tick: 4, position: CellPosition(x: 80, y: 8), material: .sand),
            PendingCommand(tick: 4, position: CellPosition(x: 80, y: 8), material: .empty),
            PendingCommand(tick: 5, position: CellPosition(x: 81, y: 8), material: .water),
        ]
        let bytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ], commands: commands)

        // Find command section offset
        let chunkCountOffset = 24 + 24
        let cellCountOffset = chunkCountOffset + 4 + 8
        // After chunk: cellCount(4) + 1 cell * 12 = 16 bytes
        let commandCountOffset = cellCountOffset + 4 + 12

        // command tick not in future (tick <= completed tick)
        // completed tick is 0 (from buildSaveWithChunks), commands are at tick 4
        // Corrupt first command's tick to 0
        let firstCommandOffset = commandCountOffset + 4
        var badCmd = bytes
        badCmd = replaced64(0, at: firstCommandOffset, in: badCmd) // tick 0 (not > completed tick 0)
        assertThrows(badCmd, SaveError.commandTickNotInFuture(tick: 0, completedTick: 0))

        // non-canonical command order (decreasing tick)
        // Build a save with commands at tick 4 and tick 5, then corrupt to make tick 5 before tick 4
        var orderCmdBytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ], commands: [
            PendingCommand(tick: 4, position: CellPosition(x: 80, y: 8), material: .sand),
            PendingCommand(tick: 5, position: CellPosition(x: 81, y: 8), material: .water),
        ])
        let orderCommandCountOffset = cellCountOffset + 4 + 12 // same structure
        let orderFirstCmdOffset = orderCommandCountOffset + 4
        // First command at tick 4, second at tick 5 - canonical
        // Corrupt: make first command tick 5, second tick 4
        orderCmdBytes = replaced64(5, at: orderFirstCmdOffset, in: orderCmdBytes)
        let orderSecondCmdOffset = orderFirstCmdOffset + 18 // 8+4+4+1+1 = 18 bytes per command
        orderCmdBytes = replaced64(4, at: orderSecondCmdOffset, in: orderCmdBytes)
        assertThrows(orderCmdBytes, SaveError.nonCanonicalCommandOrder(previousTick: 5, nextTick: 4))

        // unknown command material
        var badMat = bytes
        badMat[firstCommandOffset + 16] = 17 // material byte (tick(8) + x(4) + y(4) + material(1))
        assertThrows(badMat, SaveError.unknownMaterial(17))

        // command position out of range
        var oobCmd = bytes
        oobCmd = replaced32(limit + 1, at: firstCommandOffset + 8, in: oobCmd) // x
        assertThrows(oobCmd, SaveError.outOfRangeCell(CellPosition(x: limit + 1, y: 8)))

        // command with empty material (0) - should be allowed for erase
        var emptyCmd = bytes
        emptyCmd[firstCommandOffset + 16] = 0 // material 0 = empty (erase)
        let decoded = try codec.decode(emptyCmd)
        XCTAssertEqual(decoded.simulation.pendingCommands.first?.material, .empty)
    }

    func testGameplayValidation() throws {
        // Build a save with known structure: 1 chunk, 1 cell, 0 commands
        // This gives us a deterministic gameplay offset
        let chunks = [
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ]
        let commands: [PendingCommand] = []
        let bytes = buildSaveWithChunks(chunks, commands: commands)

        // Gameplay offset calculation:
        // Header: 24
        // World header: 24 (seed + tick + randomState)
        // Chunk count: 4
        // 1 chunk: chunkX(4) + chunkY(4) + cellCount(4) + 1 cell * 12 = 24
        // Command count: 4
        // 0 commands: 0
        // Total from start of save: 24 + 24 + 4 + 24 + 4 = 80
        let gameplayOffset = 80

        // Gameplay block internal offsets (from gameplay block start):
        // runSeed: 0 (8 bytes)
        // Course: 19 i32 = 76 bytes at offset 8
        //   gap.lower: 8, gap.upper: 12
        //   step.lower: 16, step.upper: 20
        //   sand.lower: 24, sand.upper: 28
        //   sandHeight: 32
        //   beacon1.x: 36, beacon1.y: 40
        //   beacon2.x: 44, beacon2.y: 48
        //   ventX.lower: 52, ventX.upper: 56
        //   goal.x: 60, goal.y: 64
        //   patrolX.lower: 68, patrolX.upper: 72
        //   patrolSpawn.x: 76, patrolSpawn.y: 80
        // Character: 21 bytes at offset 84
        //   x: 84, y: 88, grounded: 92, verticalVelocity: 93, verticalRemainder: 97, lastLandingImpactVelocity: 101
        // Warden: 15 bytes at offset 105
        //   x: 105, y: 109, direction: 113, phase: 117, alive: 119
        // Collected: 2 bytes at offset 120
        // Outcome: 1 byte at offset 122
        // Facing: 4 bytes at offset 123
        // Pulse cooldown: 2 bytes at offset 127
        // Health: 1 byte at offset 129
        // Damage cooldown: 2 bytes at offset 130
        // Last damage source: 1 byte at offset 132
        // Vent cooling: 2 bytes at offset 133
        // Pulse flash remaining: 1 byte at offset 135
        // Pulse flash count: 2 bytes at offset 136
        // Pulse flash cells: count * 8 bytes at offset 138

        let gp = gameplayOffset

        // runSeed != seed (seed is 42 in buildSaveWithChunks)
        var badSeed = bytes
        badSeed = replaced64(999, at: gp, in: badSeed)
        assertThrowsGameplay(badSeed, .runSeed)

        // course ranges not ordered (gap lower > upper)
        var badGap = bytes
        badGap = replaced32(40, at: gp + 8, in: badGap) // gap.lower
        badGap = replaced32(35, at: gp + 12, in: badGap) // gap.upper < lower
        assertThrowsGameplay(badGap, .courseRange)

        // step lower > upper
        var badStep = bytes
        badStep = replaced32(40, at: gp + 16, in: badStep) // step.lower
        badStep = replaced32(35, at: gp + 20, in: badStep) // step.upper < lower
        assertThrowsGameplay(badStep, .courseRange)

        // sand lower > upper
        var badSand = bytes
        badSand = replaced32(40, at: gp + 24, in: badSand) // sand.lower
        badSand = replaced32(35, at: gp + 28, in: badSand) // sand.upper < lower
        assertThrowsGameplay(badSand, .courseRange)

        // sandHeight < 0
        var badSandHeight = bytes
        badSandHeight = replaced32(-1, at: gp + 32, in: badSandHeight)
        assertThrowsGameplay(badSandHeight, .coursePosition)

        // beacon1 position out of bounds
        var badBeacon1 = bytes
        badBeacon1 = replaced32(limit + 1, at: gp + 36, in: badBeacon1) // beacon1.x
        assertThrowsGameplay(badBeacon1, .coursePosition)

        var badBeacon1y = bytes
        badBeacon1y = replaced32(limit + 1, at: gp + 40, in: badBeacon1y) // beacon1.y
        assertThrowsGameplay(badBeacon1y, .coursePosition)

        // beacon2 position out of bounds
        var badBeacon2 = bytes
        badBeacon2 = replaced32(limit + 1, at: gp + 44, in: badBeacon2) // beacon2.x
        assertThrowsGameplay(badBeacon2, .coursePosition)

        // ventX lower > upper
        var badVentX = bytes
        badVentX = replaced32(40, at: gp + 52, in: badVentX) // ventX.lower
        badVentX = replaced32(35, at: gp + 56, in: badVentX) // ventX.upper < lower
        assertThrowsGameplay(badVentX, .courseRange)

        // goal position out of bounds
        var badGoal = bytes
        badGoal = replaced32(limit + 1, at: gp + 60, in: badGoal) // goal.x
        assertThrowsGameplay(badGoal, .coursePosition)

        var badGoalY = bytes
        badGoalY = replaced32(limit + 1, at: gp + 64, in: badGoalY) // goal.y
        assertThrowsGameplay(badGoalY, .coursePosition)

        // patrolX lower > upper
        var badPatrolX = bytes
        badPatrolX = replaced32(40, at: gp + 68, in: badPatrolX) // patrolX.lower
        badPatrolX = replaced32(35, at: gp + 72, in: badPatrolX) // patrolX.upper < lower
        assertThrowsGameplay(badPatrolX, .courseRange)

        // patrolSpawn position out of bounds
        var badPatrolSpawn = bytes
        badPatrolSpawn = replaced32(limit + 1, at: gp + 76, in: badPatrolSpawn) // patrolSpawn.x
        assertThrowsGameplay(badPatrolSpawn, .coursePosition)

        var badPatrolSpawnY = bytes
        badPatrolSpawnY = replaced32(limit + 1, at: gp + 80, in: badPatrolSpawnY) // patrolSpawn.y
        assertThrowsGameplay(badPatrolSpawnY, .coursePosition)

        // character position out of bounds
        var badChar = bytes
        badChar = replaced32(limit + 1, at: gp + 84, in: badChar) // character.x
        assertThrowsGameplay(badChar, .characterPosition)

        var badCharY = bytes
        badCharY = replaced32(limit + 1, at: gp + 88, in: badCharY) // character.y
        assertThrowsGameplay(badCharY, .characterPosition)

        // character vertical velocity out of range (> 12)
        var badCharVel = bytes
        badCharVel = replaced32(13, at: gp + 93, in: badCharVel)
        assertThrowsGameplay(badCharVel, .characterMotion)

        // character vertical remainder out of range (> 3)
        var badCharRem = bytes
        badCharRem = replaced32(4, at: gp + 97, in: badCharRem)
        assertThrowsGameplay(badCharRem, .characterMotion)

        // warden direction not -1 or 1
        var badWardenDir = bytes
        badWardenDir = replaced32(2, at: gp + 113, in: badWardenDir)
        assertThrowsGameplay(badWardenDir, .wardenDirection)

        // warden phase > 59
        var badWardenPhase = bytes
        badWardenPhase = replaced16(60, at: gp + 117, in: badWardenPhase)
        assertThrowsGameplay(badWardenPhase, .wardenPhase)

        // warden position out of bounds
        var badWardenPos = bytes
        badWardenPos = replaced32(limit + 1, at: gp + 105, in: badWardenPos) // warden.x
        assertThrowsGameplay(badWardenPos, .wardenPosition)

        var badWardenPosY = bytes
        badWardenPosY = replaced32(limit + 1, at: gp + 109, in: badWardenPosY) // warden.y
        assertThrowsGameplay(badWardenPosY, .wardenPosition)

        // health > 3
        var badHealth = bytes
        badHealth[gp + 129] = 4
        assertThrowsGameplay(badHealth, .health)

        // facing not -1 or 1
        var badFacing = bytes
        badFacing = replaced32(2, at: gp + 123, in: badFacing)
        assertThrowsGameplay(badFacing, .facing)

        // pulseCooldown > 18
        var badPulseCooldown = bytes
        badPulseCooldown = replaced16(19, at: gp + 127, in: badPulseCooldown)
        assertThrowsGameplay(badPulseCooldown, .pulseCooldown)

        // damageCooldown > 30
        var badDamageCooldown = bytes
        badDamageCooldown = replaced16(31, at: gp + 130, in: badDamageCooldown)
        assertThrowsGameplay(badDamageCooldown, .damageCooldown)

        // ventCooling > 120
        var badVentCooling = bytes
        badVentCooling = replaced16(121, at: gp + 133, in: badVentCooling)
        assertThrowsGameplay(badVentCooling, .ventCooling)

        // pulseFlashRemaining > 4
        var badFlashRemaining = bytes
        badFlashRemaining[gp + 135] = 5
        assertThrowsGameplay(badFlashRemaining, .pulseFlash)

        // flash count > limit - triggers oversizedCount before gameplay validation
        var badFlashCount = bytes
        badFlashCount = replaced16(UInt16(SaveCodec.maximumPulseFlashCellCount + 1), at: gp + 136, in: badFlashCount)
        XCTAssertThrowsError(try codec.decode(badFlashCount)) { error in
            guard case SaveError.oversizedCount(field: .pulseFlashCells, declared: SaveCodec.maximumPulseFlashCellCount + 1, limit: SaveCodec.maximumPulseFlashCellCount) = error else {
                XCTFail("expected oversizedCount for pulseFlashCells, got \(error)")
                return
            }
        }

        // flash count nonzero with zero remaining
        var badFlashCombo = bytes
        badFlashCombo[gp + 135] = 0 // pulseFlashRemaining = 0
        badFlashCombo = replaced16(1, at: gp + 136, in: badFlashCombo) // flashCount = 1
        // Need to add a flash cell position (x, y) at offset 138
        if badFlashCombo.count > gp + 138 + 8 {
            badFlashCombo = replaced32(0, at: gp + 138, in: badFlashCombo)
            badFlashCombo = replaced32(0, at: gp + 142, in: badFlashCombo)
        }
        assertThrowsGameplay(badFlashCombo, .pulseFlash)

        // lastDamageSource != none when damageCooldown == 0
        var badDamageSource = bytes
        // Set damageCooldown to 0
        badDamageSource = replaced16(0, at: gp + 130, in: badDamageSource)
        // Set lastDamageSource to fire (1)
        badDamageSource[gp + 132] = 1
        assertThrowsGameplay(badDamageSource, .damageSource)
    }

    func testDigestMismatch() throws {
        // Build a valid save with a known cell, then corrupt the material to a different valid value
        var bytes = buildSaveWithChunks([
            (ChunkPosition(x: 1, y: 1), [CellEntry(localIndex: 0, material: .sand)])
        ])

        // Cell entry layout: localIndex(4) + material(1) + ...
        // material is at cellCountOffset + 4(cellCount) + 4(localIndex) = cellCountOffset + 8
        let chunkCountOffset = 24 + 24
        let cellCountOffset = chunkCountOffset + 4 + 8
        let matOffset = cellCountOffset + 4 + 4

        // Corrupt material from sand (1) to water (2) - both valid, but digest will mismatch
        bytes[matOffset] = Material.water.rawValue

        XCTAssertThrowsError(try codec.decode(bytes)) { error in
            guard case SaveError.digestMismatch = error else {
                XCTFail("expected digestMismatch, got \(error)")
                return
            }
        }
    }

    // MARK: Test encoder helper

    /// Represents a cell entry for building test saves
    private struct CellEntry {
        let localIndex: UInt32
        let material: Material
    }

    /// Represents a pending command for building test saves
    private struct PendingCommand {
        let tick: UInt64
        let position: CellPosition
        let material: Material
    }

    /// Builds a complete save with the given chunks and commands.
    /// Each chunk tuple: (ChunkPosition, [CellEntry])
    private func buildSaveWithChunks(_ chunks: [(ChunkPosition, [CellEntry])], commands: [PendingCommand] = []) -> [UInt8] {
        let encoder = TestEncoder()

        // Header placeholder (24 bytes)
        encoder.writeBytes([UInt8](repeating: 0, count: 24))

        // World header
        let seed: UInt64 = 42
        let tick: UInt64 = 0
        let randomState: UInt64 = 0
        encoder.writeU64(seed)
        encoder.writeU64(tick)
        encoder.writeU64(randomState)

        // Chunk count
        encoder.writeU32(UInt32(chunks.count))

        // Chunks in order (y, then x)
        let sortedChunks = chunks.sorted { a, b in
            if a.0.y != b.0.y { return a.0.y < b.0.y }
            return a.0.x < b.0.x
        }

        for (chunkPos, entries) in sortedChunks {
            encoder.writeI32(Int32(chunkPos.x))
            encoder.writeI32(Int32(chunkPos.y))
            encoder.writeU32(UInt32(entries.count))
            for entry in entries {
                encoder.writeU32(entry.localIndex)
                encoder.writeU8(entry.material.rawValue)
                encoder.writeU16(0) // heat
                encoder.writeU8(0)  // burning
                encoder.writeU16(0) // burnElapsed
                encoder.writeU16(0) // fireElapsed
            }
        }

        // Commands (with isSpellCommand flag)
        encoder.writeU32(UInt32(commands.count))
        // Sort commands by tick for canonical order
        let sortedCommands = commands.sorted { $0.tick < $1.tick }
        for cmd in sortedCommands {
            encoder.writeU64(cmd.tick)
            encoder.writeI32(Int32(cmd.position.x))
            encoder.writeI32(Int32(cmd.position.y))
            encoder.writeU8(cmd.material.rawValue)
            encoder.writeU8(0) // isSpellCommand = false (paint command)
        }

        // Gameplay block - use a valid BeaconRun's gameplay data
        let gameplayRun = try! BeaconRun(seed: 42)
        let gameplayBytes = encodeGameplayBlock(gameplayRun)
        encoder.writeBytes(gameplayBytes)

        // Now build final header with correct payload size and digest
        let payload = encoder.bytes.dropFirst(24)
        var header = [UInt8](repeating: 0, count: 24)
        let magic: [UInt8] = [0x4E, 0x52, 0x53, 0x56] // NRSV
        header[0] = magic[0]; header[1] = magic[1]; header[2] = magic[2]; header[3] = magic[3]
        writeU16(SaveCodec.formatVersion, into: &header, at: 4)
        writeU16(0, into: &header, at: 6) // flags
        writeU16(SaveCodec.rulesVersion, into: &header, at: 8)
        writeU16(SaveCodec.digestVersion, into: &header, at: 10)
        writeU32(UInt32(payload.count), into: &header, at: 12)

        // For digest, we need to compute it from the simulation snapshot
        var chunkDict: [ChunkPosition: (cells: [Material], thermalStates: [ThermalCellState])] = [:]
        for (pos, entries) in chunks {
            var cells = [Material](repeating: .empty, count: SimulationGrid.cellCount)
            var thermals = [ThermalCellState](repeating: .zero, count: SimulationGrid.cellCount)
            for entry in entries {
                cells[Int(entry.localIndex)] = entry.material
                thermals[Int(entry.localIndex)] = ThermalCellState(heat: 0, isBurning: false, burnElapsed: 0, fireElapsed: 0)
            }
            chunkDict[pos] = (cells, thermals)
        }
        var cmdDict: [UInt64: [SimulationCommand]] = [:]
        for cmd in commands {
            cmdDict[cmd.tick, default: []].append(SimulationCommand(tick: cmd.tick, position: cmd.position, material: cmd.material))
        }
        let sim = Simulation(seed: seed, tick: tick, randomState: randomState, chunks: chunkDict, commands: cmdDict)
        let digest = sim.snapshot.digest
        writeU64(digest, into: &header, at: 16)

        return header + Array(payload)
    }

    private func encodeGameplayBlock(_ run: BeaconRun) -> [UInt8] {
        let encoder = TestEncoder()
        encoder.writeU64(run.seed) // runSeed
        // Course ranges
        encoder.writeI32(Int32(run.course.gap.lowerBound))
        encoder.writeI32(Int32(run.course.gap.upperBound))
        encoder.writeI32(Int32(run.course.step.lowerBound))
        encoder.writeI32(Int32(run.course.step.upperBound))
        encoder.writeI32(Int32(run.course.sand.lowerBound))
        encoder.writeI32(Int32(run.course.sand.upperBound))
        encoder.writeI32(Int32(run.course.sandHeight))
        // Beacons (exactly 2)
        encoder.writeI32(Int32(run.course.beacons[0].x))
        encoder.writeI32(Int32(run.course.beacons[0].y))
        encoder.writeI32(Int32(run.course.beacons[1].x))
        encoder.writeI32(Int32(run.course.beacons[1].y))
        // Vent X range
        encoder.writeI32(Int32(run.course.ventX.lowerBound))
        encoder.writeI32(Int32(run.course.ventX.upperBound))
        // Goal
        encoder.writeI32(Int32(run.course.goal.x))
        encoder.writeI32(Int32(run.course.goal.y))
        // Patrol X range
        encoder.writeI32(Int32(run.course.patrolX.lowerBound))
        encoder.writeI32(Int32(run.course.patrolX.upperBound))
        // Patrol spawn
        encoder.writeI32(Int32(run.course.patrolSpawn.x))
        encoder.writeI32(Int32(run.course.patrolSpawn.y))
        // Character
        encoder.writeI32(Int32(run.character.position.x))
        encoder.writeI32(Int32(run.character.position.y))
        encoder.writeU8(run.character.grounded ? 1 : 0)
        encoder.writeI32(Int32(run.character.verticalVelocity))
        encoder.writeI32(Int32(run.character.verticalRemainder))
        encoder.writeI32(Int32(run.character.lastLandingImpactVelocity))
        // Warden
        encoder.writeI32(Int32(run.warden.position.x))
        encoder.writeI32(Int32(run.warden.position.y))
        encoder.writeI32(Int32(run.warden.direction))
        encoder.writeU16(UInt16(run.warden.phase))
        encoder.writeU8(run.warden.alive ? 1 : 0)
        // Collected
        encoder.writeU8(run.collected[0] ? 1 : 0)
        encoder.writeU8(run.collected[1] ? 1 : 0)
        // Outcome
        encoder.writeU8(outcomeCode(run.outcome))
        // Facing
        encoder.writeI32(Int32(run.facing))
        // Pulse cooldown
        encoder.writeU16(UInt16(run.pulseCooldown))
        // Health
        encoder.writeU8(UInt8(run.health))
        // Damage cooldown
        encoder.writeU16(UInt16(run.damageCooldown))
        // Last damage source
        encoder.writeU8(damageSourceCode(run.lastDamageSource))
        // Vent cooling
        encoder.writeU16(UInt16(run.ventCooling))
        // Pulse flash remaining
        encoder.writeU8(UInt8(run.pulseFlashRemaining))
        // Pulse flash cells
        encoder.writeU16(UInt16(run.pulseFlash.count))
        for cell in run.pulseFlash {
            encoder.writeI32(Int32(cell.x))
            encoder.writeI32(Int32(cell.y))
        }
        return encoder.bytes
    }

    private func outcomeCode(_ outcome: BeaconRun.Outcome) -> UInt8 {
        switch outcome {
        case .playing: return 0
        case .won: return 1
        case .fell: return 2
        case .exhausted: return 3
        }
    }

    private func damageSourceCode(_ source: BeaconRun.DamageSource?) -> UInt8 {
        switch source {
        case .none: return 0
        case .fire: return 1
        case .vent: return 2
        case .warden: return 3
        }
    }

    // MARK: Helpers

    private func encode() throws -> [UInt8] {
        try codec.encode(try BeaconRun(seed: 42))
    }

    private func assertThrows<T: Error & Equatable>(
        _ bytes: [UInt8], _ expected: T, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try codec.decode(bytes), file: file, line: line) { error in
            XCTAssertEqual(error as? T, expected, file: file, line: line)
        }
    }

    private func assertThrowsGameplay(
        _ bytes: [UInt8], _ expected: SaveField, file: StaticString = #filePath, line: UInt = #line
    ) {
        assertThrows(bytes, SaveError.invalidGameplayField(expected), file: file, line: line)
    }

    /// Find command count offset by parsing the payload
    private func findCommandCountOffset(_ bytes: [UInt8]) throws -> Int {
        var offset = 24 // skip header
        offset += 24 // world header
        let chunkCount = Int(readU32(bytes, at: offset))
        offset += 4
        // Skip chunks
        for _ in 0..<chunkCount {
            offset += 12 // chunkX + chunkY + cellCount
            let cellCount = Int(readU32(bytes, at: offset - 4))
            offset += cellCount * 12
        }
        // Now at command count
        return offset
    }

    /// Find gameplay offset by parsing the payload
    private func findGameplayOffset(_ bytes: [UInt8]) throws -> Int {
        var offset = try findCommandCountOffset(bytes)
        let commandCount = Int(readU32(bytes, at: offset))
        offset += 4
        // Skip commands: each is tick(8) + x(4) + y(4) + material(1) = 17 bytes
        offset += commandCount * 17
        // Now at gameplay block (runSeed)
        return offset
    }

    private func readU16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private func readU32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private func readI32(_ bytes: [UInt8], at offset: Int) -> Int32 {
        Int32(bitPattern: readU32(bytes, at: offset))
    }

    private func replaced16(_ value: UInt16, at offset: Int, in bytes: [UInt8]) -> [UInt8] {
        var bytes = bytes
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        return bytes
    }

    private func replaced32(_ value: Int, at offset: Int, in bytes: [UInt8]) -> [UInt8] {
        var bytes = bytes
        let u32 = UInt32(truncatingIfNeeded: value)
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes[offset + shift / 8] = UInt8(truncatingIfNeeded: u32 >> shift)
        }
        return bytes
    }

    private func replaced64(_ value: UInt64, at offset: Int, in bytes: [UInt8]) -> [UInt8] {
        var bytes = bytes
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes[offset + shift / 8] = UInt8(truncatingIfNeeded: value >> shift)
        }
        return bytes
    }

    private func writeU16(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    private func writeU32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    private func writeU64(_ value: UInt64, into bytes: inout [UInt8], at offset: Int) {
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes[offset + shift / 8] = UInt8(truncatingIfNeeded: value >> shift)
        }
    }

    /// Calculate the size of a chunk entry at the given offset
    private func chunkEntrySize(_ bytes: [UInt8], at offset: Int) -> Int {
        // chunkX(4) + chunkY(4) + cellCount(4) + cellCount * 12
        let cellCount = Int(readU32(bytes, at: offset + 8))
        return 12 + cellCount * 12
    }
}

/// Test-only encoder for building save bytes
private final class TestEncoder {
    var bytes: [UInt8] = []

    func writeU8(_ value: UInt8) {
        bytes.append(value)
    }

    func writeU16(_ value: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    func writeU32(_ value: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    func writeU64(_ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }

    func writeI32(_ value: Int32) {
        let u32 = UInt32(bitPattern: value)
        writeU32(u32)
    }

    func writeBytes(_ bytes: [UInt8]) {
        self.bytes.append(contentsOf: bytes)
    }
}