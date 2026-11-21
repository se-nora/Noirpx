/// Count fields whose declared values can exceed the codec's allocation caps.
public enum SaveCountField: Equatable, Sendable {
    case chunks, cellEntries, commands, pulseFlashCells
}

/// Gameplay block fields whose decoded values can violate the run's invariants.
public enum SaveField: Equatable, Sendable {
    case runSeed, courseRange, coursePosition, characterPosition, characterMotion
    case wardenPosition, wardenDirection, wardenPhase, outcome, collected
    case health, facing, pulseCooldown, damageCooldown, damageSource
    case ventCooling, pulseFlash
}

/// Save decode and encode failures. Payloads are values, not localized strings;
/// hosts map them to their own user-facing text.
public enum SaveError: Error, Equatable, Sendable {
    case truncatedInput(neededBytes: Int, availableBytes: Int)
    case badMagic
    case unknownFormatVersion(UInt16)
    case unsupportedRulesVersion(UInt16)
    case unsupportedDigestVersion(UInt16)
    case unsupportedFlags(UInt16)
    case payloadSizeMismatch(declaredBytes: Int, actualBytes: Int)
    case oversizedPayload(declaredBytes: Int, limitBytes: Int)
    case oversizedCount(field: SaveCountField, declared: Int, limit: Int)
    case chunkCountMismatch(declared: Int, decoded: Int)
    case duplicateChunk(ChunkPosition)
    case nonCanonicalChunkOrder(ChunkPosition)
    case nonCanonicalCommandOrder(previousTick: UInt64, nextTick: UInt64)
    case outOfRangeChunk(ChunkPosition)
    case outOfRangeCell(CellPosition)
    case unknownMaterial(UInt8)
    case invalidCellEntry(chunk: ChunkPosition, localIndex: UInt32)
    case commandTickNotInFuture(tick: UInt64, completedTick: UInt64)
    case invalidCommandFlag(UInt8)
    case invalidGameplayField(SaveField)
    case digestMismatch(stored: UInt64, recomputed: UInt64)
    /// Save attempted while sanctuary is active. Sanctuary state is not persisted.
    case sanctuaryActive
}
