# Save format

## Persistence and save format

### Scope: what a save contains

A v1 save covers exactly the state that determines the next `BeaconRun.advance`
result in the deterministic mode. It persists:

- `Simulation.seed`, `Simulation.tick` (the completed tick), and
  `Simulation.randomState`. The SplitMix64 state is required: without it, the
  next direction draws diverge even with an identical world.
- Every allocated chunk: its `ChunkPosition`, all 4,096 `Material` cells, and
  all 4,096 `ThermalCellState` values (`heat`, `isBurning`, `burnElapsed`,
  `fireElapsed`). Allocation is already sparse: a chunk exists only while its
  occupied-cell count is nonzero, and empty cells always have zero thermal state.
- Every queued future command (`SimulationCommand`: tick, position, material),
  including the per-tick enqueue order, because commands for one tick apply in
  that order and the last write wins.
- Character `FixtureCharacter` state: `position`, `grounded`, and the private
  `verticalVelocity` and `verticalRemainder`, which determine later jumps and
  falls.
- `BeaconRun` gameplay state: `seed` (equal to the simulation seed), the complete
  `BeaconCourse` (`gap`, `step`, `sand`, `sandHeight`, `beacons`, `ventX`,
  `goal`, `patrolX`, `patrolSpawn`), `collected`, `outcome`, `facing`,
  `pulseCooldown`, `health`, `damageCooldown`, `lastDamageSource`,
  `ventCooling`, `pulseFlash`, `pulseFlashRemaining`, and the `ChimeWarden`
  (`position`, `direction`, `phase`, `alive`).

The tick-1 fixture placement commands created by `BeaconRun(seed:)` are part of
the saved command queue. Load must not call `BeaconRun(seed:)` and replay
generation; that would duplicate commands and would tie load to generator code.

Not saved, because it is presentation or host policy rather than authoritative
state:

- Brush selection (`MaterialBrush`), camera and viewport geometry, drawable
  size, resize/orientation state, HUD and diagnostics contents (submitted FPS,
  rendered and allocated chunk counts), help/stats/scroll positions, textures
  and other GPU resources.
- `GameplayControls` / `GameplayInput` held keys, touch state, buffered jump and
  pulse presses, accessibility one-shots, window focus, and the scheduler's
  accumulator and time baseline. These live in the host and are consumed per
  tick; `BeaconRun` stores no buffered input.
- The host-supplied `activeChunks` region. It is derived from the camera each
  tick and passed into `advance`; it is an input to the next tick, not state.
  A resumed session reproduces the original only if the host supplies the same
  region on the same ticks (and the same per-tick inputs).
- App version, device, OS, file path, timestamps, and user-facing names. None is
  needed and any of them would make byte equality a poor test oracle.

`pulseFlash` and `pulseFlashRemaining` are stored even though they only affect
rendering: they are `BeaconRun` state, are cheap, and make a resumed run's visual
feedback exact. They cannot change material or gameplay results.

`ResidentSimulation` is out of scope for v1. It has no digest, no replay
guarantee, and no app integration; a future format for it would be separate.

### Ownership and module boundary

The codec is a stateless value type, `SaveCodec`, in
`Sources/SimulationCore/Persistence/SaveCodec.swift`, with `SaveError` in
`Sources/SimulationCore/Persistence/SaveError.swift`. The type imports nothing: no
Foundation, Metal, SwiftUI, UIKit, AppKit, `Data`, `Date`, or file APIs, and no
clock reads. It converts between a `BeaconRun` and `[UInt8]`; every byte is
written and read explicitly, without `withUnsafeBytes` or `MemoryLayout`
assumptions. `SimulationCore` keeps its existing rule of no UI, Metal, audio,
platform input, or wall-clock dependency.

Writing the bytes to disk belongs to a later host/store layer, named here as a
future `GamePersistence` target with `Sources/GamePersistence/SaveStore.swift`
and a `SaveStore` type. That layer owns atomic write (temporary file plus
rename), failure reporting, backup/recovery policy, and choosing the application
support location. Neither the target nor the file exists yet; adding them
requires a `Package.swift` change and host coordination and is not part of this
contract.

### Wire format

All multi-byte integers are little-endian regardless of host byte order, written
one byte at a time. Fixed widths: `u8`, `u16`, `u32`, `u64`, and signed `i32`
two's complement. `Int` never appears in the file; decode range-checks and
converts. The file is not compressed or encrypted and has no string fields, so
encoding is a pure function of state.

Header, 24 bytes:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | magic, ASCII `NRSV` = `0x4E 0x52 0x53 0x56` |
| 4 | 2 | format version, `1` |
| 6 | 2 | flags, `0` (reserved; nonzero is rejected) |
| 8 | 2 | rules version, `1` |
| 10 | 2 | digest version, `10` |
| 12 | 4 | payload byte count u32, excluding the header |
| 16 | 8 | material digest u64 of the saved world (digest version 3) |

The payload, in this order:

1. World: `seed` u64, `tick` u64, `randomState` u64, `chunkCount` u32.
2. Chunks in strictly increasing chunk `y` then `x` order. Each chunk is
   `x` i32, `y` i32, `cellCount` u32, then `cellCount` entries in strictly
   increasing row-major local index (`localY * 64 + localX`, local y increasing
   upward). Each entry is `localIndex` u32, `material` u8, `heat` u16,
   `burning` u8 (0 or 1), `burnElapsed` u16, `fireElapsed` u16. The thermal
   field order intentionally matches the digest record order.
3. Commands: `commandCount` u32, then entries in nondecreasing `tick` order and,
   within a tick, enqueue order. Each is `tick` u64, `x` i32, `y` i32,
   `material` u8.
4. Gameplay, in this fixed order:
   `runSeed` u64; course `gap.lower`, `gap.upper`, `step.lower`, `step.upper`,
   `sand.lower`, `sand.upper`, `sandHeight` (i32 each); exactly two beacon
   positions as `x` i32, `y` i32; `ventX.lower`, `ventX.upper`; `goal.x`,
   `goal.y`; `patrolX.lower`, `patrolX.upper`; `patrolSpawn.x`,
   `patrolSpawn.y`; character `x` i32, `y` i32, `grounded` u8 (0/1),
   `verticalVelocity` i32, `verticalRemainder` i32; warden `x` i32, `y` i32,
   `direction` i32, `phase` u16, `alive` u8 (0/1); `collected[0]` u8,
   `collected[1]` u8; `outcome` u8; `facing` i32; `pulseCooldown` u16;
   `health` u8; `damageCooldown` u16; `lastDamageSource` u8;
   `ventCooling` u16; `pulseFlashRemaining` u8; `pulseFlashCellCount` u16;
   then that many flash positions as `x` i32, `y` i32.

Enum codes are fixed by this format rather than by Swift case order: outcome
0 playing, 1 won, 2 fell, 3 exhausted; damage source 0 none, 1 fire, 2 vent,
3 warden. Material bytes are the existing raw identifiers 0...6; an entry may
not use 0 because allocated chunks contain only nonempty cells. Commands may
use 0 to erase.

Chunks are encoded sparsely because allocation is already sparse and Beacon Run
allocated chunks are mostly empty; a dense 4,096-cell material array plus a
dense thermal array would cost 32,768 bytes for a chunk holding one pitch cell.
Sparse entries cost 12 bytes per nonempty cell and keep the encoder simple. The
decoder still materializes full 4,096-entry arrays so the restored `Simulation`
is byte-for-byte equivalent in layout to one built by gameplay.

The material digest in the header is the existing `SimulationSnapshot.digest`
(FNV-1a, digest version 3) of the reconstructed world. It intentionally covers
only the completed world and RNG state; it does not cover queued commands or the
gameplay block. It detects accidental world corruption and mismatched
version/layout, not tampering with gameplay scalars.

### Validation, limits, and errors

Decode is all-or-nothing: it either returns a fully reconstructed `BeaconRun`
or throws, and no partially built state escapes. `encode` is also throwing, but
only the size caps below can fail for state produced by the current API.

Limits are fixed constants on `SaveCodec`:

- `maximumPayloadBytes = 16 * 1024 * 1024` (16 MiB)
- `maximumChunkCount = 1_024`
- `maximumCellEntryCount = 1_048_576` (total across chunks)
- `maximumCommandCount = 65_536`
- `maximumPulseFlashCellCount = 90` (five lanes times the 18-cell pulse range)

These are sized for Beacon Run, whose generated course spans on the order of
200 by 40 cells, not measured for large worlds. A 1,024-chunk world of fully
populated chunks would allocate roughly 33 MiB of cell and thermal arrays; the
entry cap rejects more than 1,048,576 entries before that allocation is
attempted. The counts exist to bound allocation before it happens, since Swift
allocation failure is not recoverable. They must be revisited before saving
larger worlds.

Decode enforces: header magic, exact format/rules/digest versions, zero flags,
`payloadByteCount == bytes.count - 24`, payload within the byte cap, every read
inside the payload, canonical chunk order with no duplicate positions, chunk
coordinates in `-15_625...15_625` on each axis, nonzero `cellCount` not above
4,096, strictly increasing in-range local indices, nonempty known materials,
`burning` of 0 or 1, every reconstructed cell inside
`Simulation.coordinateBounds` (this rejects nonempty padding outside the world),
nondecreasing command ticks, command ticks greater than the completed tick,
in-range command positions and known command materials, the course ranges
ordered low-to-high with positions in bounds, and the gameplay range invariants
the current code guarantees (all u8 flags 0 or 1; `health` 0...3, `facing` -1 or
1, `phase` 0...59, warden direction -1 or 1, character vertical velocity
-12...12 and vertical remainder -3...3, `pulseCooldown` 0...18,
`damageCooldown` 0...30, `ventCooling` 0...120, `pulseFlashRemaining` 0...4,
`sandHeight` at least 0 and within the coordinate limit, flash cell count within
the limit, zero flash cells when the remaining count is zero, and
`runSeed == seed`). Character and warden positions, every flash cell, and every
course marker and spawn position must lie inside `Simulation.coordinateBounds`.
`lastDamageSource` must be none whenever `damageCooldown` is zero, matching the
in-memory invariant that an expired shield clears the recorded source; a
nonzero source with a zero cooldown is invalid. It recomputes `occupiedCount` per chunk and the
material digest; the digest must equal the header value. Thermal data is
preserved verbatim for any nonempty material, including materials that are not
currently flammable, because the simulation itself stores it.

```swift
public enum SaveCountField: Equatable, Sendable {
    case chunks, cellEntries, commands, pulseFlashCells
}

public enum SaveField: Equatable, Sendable {
    case runSeed, courseRange, coursePosition, characterPosition, characterMotion
    case wardenPosition, wardenDirection, wardenPhase, outcome, collected
    case health, facing, pulseCooldown, damageCooldown, damageSource
    case ventCooling, pulseFlash
}

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
    case invalidGameplayField(SaveField)
    case digestMismatch(stored: UInt64, recomputed: UInt64)
}
```

`chunkCountMismatch` covers a chunk table that cannot yield exactly the declared
number of distinct chunks, for example a payload that ends inside the table or
a declared count inconsistent with the remaining bytes; per-entry damage uses
the more specific cases. Error payloads are values, not localized strings;
hosts map them to their own user-facing text.

### Determinism and compatibility policy

Three independent numbers appear in the header:

- **Format version** (1): the byte layout above. Any field, order, or encoding
  change bumps it. A decoder supports exactly one version; unknown versions are
  rejected. Trailing bytes and unknown flags are rejected rather than skipped,
  so v1 is deliberately not forward-compatible.
- **Rules version** (1): the deterministic ruleset. It must be bumped whenever
  the same seed, commands, and active region could produce a different state
  than under the previous rules (movement order, reaction order, thermal
  constants, RNG, material identifier reuse, character/course/warden behavior).
  A save resumed under different rules is rejected instead of silently
  producing a different game.
- **Digest version** (3): the existing FNV-1a layout for `SimulationSnapshot`
  and the header's `materialDigest`. The coding stage adds
  `SimulationSnapshot.digestVersion: UInt64 = 3`, uses it in place of the
  current literal in `digest`, and derives `SaveCodec.digestVersion` from it, so
  the header cannot drift from the hash. That refactor must not change any
  digest bytes.

There is no v0 save and no migration: nothing has shipped, and no earlier save
format exists. For future versions, migration is an explicit, tested transform
from the old decoded value to the current in-memory value; it is never a silent
reinterpretation of bytes. Because queued commands and gameplay state are
outside the digest, byte equality plus digest equality is not a checksum of the
whole file; it is a test oracle, not an integrity guarantee.

Same-device, same-build resume is guaranteed for the deterministic mode: for
the same save bytes, same per-tick inputs, and same `activeChunks` region, the
decoded run re-encodes to identical bytes, has an equal snapshot and digest at
the resume tick, and matches an unsaved control for every following tick. The
simulation uses integer-only arithmetic, but cross-device determinism remains
unverified in this project and must not be relied on for saves, transfer between
devices, or networking. A saved session is not a replay log; it records no input
history.

### Public API

```swift
/// Stateless value codec for the deterministic Beacon Run save format.
public struct SaveCodec: Sendable {
    public static let headerByteCount = 24
    public static let formatVersion: UInt16 = 1
    public static let rulesVersion: UInt16 = 1
    public static let digestVersion = UInt16(SimulationSnapshot.digestVersion)

    public static let maximumPayloadBytes = 16 * 1024 * 1024
    public static let maximumChunkCount = 1_024
    public static let maximumCellEntryCount = 1_048_576
    public static let maximumCommandCount = 65_536
    public static let maximumPulseFlashCellCount = 90

    public init()

    /// Encodes the run's authoritative state. Throws `SaveError` only for the
    /// size limits above.
    public func encode(_ run: BeaconRun) throws -> [UInt8]

    /// Validates and reconstructs a runnable `BeaconRun`, or throws without
    /// returning partial state.
    public func decode(_ bytes: [UInt8]) throws -> BeaconRun
}
```

Encode is obtained from the live `BeaconRun`; there is no separate public save
value to keep in sync with gameplay fields. `decode` builds the restored
`Simulation` first, checks the digest, then constructs the `BeaconRun`. It does
not call `BeaconRun(seed:)`, `BeaconCourse(seed:)`, `Simulation(seed:)`, or any
command-enqueueing API other than validated restoration.

### Known limits and open questions

- No file I/O, atomic write, backup, recovery, autosave cadence, or user-facing
  error text exists in this contract; those belong to the future
  `GamePersistence`/`SaveStore` layer and its host integration.
- The material digest covers only the completed world and RNG state. Corruption
  confined to commands or gameplay scalars that still passes range checks is
  not detected. Adding a whole-file checksum is a format change, not a v1
  patch.
- The stored course is authoritative and is not regenerated or cross-checked
  against `BeaconCourse(seed:)`. This keeps load independent of generator code,
  but a forged or damaged-but-valid course cannot be detected structurally.
  Whether to add a course checksum is open.
- Saving a bare `Simulation` (headless fixture) is not in the public v1 API.
  Tests can use the internal restoration path; a public simulation-only archive
  is an open question for the host/store iteration.
- The 16 MiB payload and the chunk/cell/command caps are threshold guesses for
  the current Beacon Run, not measurements. Larger worlds, or many saved runs,
  need size and memory measurements first.
- Resident mode has no save format and no replay guarantee; it needs a separate,
  explicitly non-deterministic persistence design.
- Mobile backgrounding, interruption, and low-storage behavior are unverified;
  so are cross-device resume and any future iCloud or transfer feature.
- `pulseFlash` is stored for visual continuity only. If a future renderer stops
  using it, dropping it is a format change.
