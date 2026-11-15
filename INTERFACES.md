# Simulation and host interface contracts

The milestone 1 choices below are a **provisional, single-owner prototype**.
They have not been reviewed by separate core and renderer contributors. That
review remains open; the project owner authorized a single-owner implementation
of the separate resident-world direction below. Do not treat either interface as
independently reviewed, particularly full-snapshot cost and GPU buffer ownership.

## Coordinates and storage

World coordinates are signed integer cells; x increases right and y increases
up. Valid coordinates are inclusive -1,000,000 through 1,000,000 on each axis.
Outside is an impassable boundary. Commands and snapshot lookups outside these
bounds throw `positionOutOfBounds`. The limit ensures neighbor and chunk
arithmetic is safe on supported Swift platforms; it is not a streaming policy.

Chunks are provisionally 64 by 64, row-major from local (0, 0), using floor
division and nonnegative local coordinates. Each chunk stores 4,096 `Material`
values; the deterministic simulation tracks each chunk's occupied-cell count
and removes it when the count reaches zero. Boundary chunks include empty padding outside
the world. The change from 16 to 64 increases the memory and scanning cost of
individual chunks; it has not been performance-tested on target devices. Chunk
size, layout, allocation and snapshot costs need measurement before being permanent.
Both worlds additionally store a row-major `ThermalCellState` value for every
cell in each allocated chunk. Its `UInt16` heat, burn elapsed age and fire
elapsed age, plus a burning flag, initially equal zero/false.
The eager sidecar increases allocated-chunk and snapshot memory; its cost has
not been measured.
Empty cells always have zero thermal state. Internal checked world accessors
`thermalState(at:)` and `setThermalState(_:at:)` reject out-of-bounds positions;
the setter returns false for empty cells and otherwise true. Resident thermal
changes wake the cell's chunk and allocated neighboring chunks as material
changes do. A no-op thermal write does not wake them.

Explicit material replacement resets thermal state even when replacing a
material with itself. Moving material carries its thermal state, including
both participants in liquid displacement; removing material clears it.
Deleting a chunk deletes its sidecar.
There is no chunk or command-queue budget, streaming, or recoverable
out-of-memory API; Swift allocation failure is not caught. Callers must bound
their workloads, especially on iOS.

## Materials, commands, and tick rules

The enum raw identifiers are empty 0, solid 1, sand 2, water 3, fire 4,
pitch 5, and lamp oil 6. Former burning-stage identifiers 7...69 are rejected;
identifier 6 has been reused for oil, not migrated from the former stage format;
there is no automatic conversion or replay compatibility with the previous rules.
The typed API accepts only these cases; external decoding must reject unknown
identifiers. There is no material definition or persistence format yet.

`Simulation(seed:)` owns an initially empty world at completed tick zero.
`enqueue` accepts a material replacement for an explicit future tick, validates
it immediately, and throws for an out-of-bounds position or a tick already
completed. Commands for a tick are applied in enqueue order; the last write to
a position wins. Commands can be enqueued out of tick order. `advance()`
checks for tick overflow before mutation, consumes the next tick's commands,
then executes rules, and only then publishes the new tick. The host supplies
ticks; the core reads no clock or platform input.

`advance(activeChunks:)` optionally restricts physics to an inclusive rectangular
chunk region; the default is unrestricted. Commands still apply everywhere.
Frozen chunks retain their cells and consume no random draws. Movement and fire
reactions cannot cross into frozen chunks. When a chunk becomes active again it
updates normally without replaying missed ticks. Reproducibility requires the
same active region on each tick as well as the same seed and commands.

After commands, capture the occupied positions and process them in increasing
world y, then increasing x. A cell displaced into a position is marked so it
cannot be processed again that tick. Updates are immediate: the first actor to
claim an empty cell wins, and later actors see prior movement and reactions.
Empty and solid do not act. Sand attempts down, then the two down-diagonals;
water and oil do the same and then attempt the two horizontal neighbors. In
this discrete density approximation sand may displace water or oil, and water
may displace oil only when moving down or diagonally down. Oil displaces neither
water nor sand; no liquid displaces its own kind. The ordered movement candidates
are tried as usual, so an earlier empty candidate beats a later displacement.
Diagonal movement requires the adjacent horizontal cell to be empty and active.
Only a target that has not already moved can be displaced. The displaced liquid
is relocated to the first empty side of the destination in the actor's preferred
direction, then the opposite side, or to the first empty cell found searching
upward in the destination column, passing occupied cells. The actor's vacated
cell is available. The search stops at the world or active-region boundary; if
no slot exists that candidate is rejected and later candidates are tried.
Both relocated liquid and actor are marked moved. Their thermal states are
captured before any writes, including when the displaced cell takes the actor's
vacated position; no aliasing or duplication is intended.
Otherwise the first empty in-bounds destination wins. The left/right
preference for both diagonal and horizontal choices comes from one SplitMix64
draw per processed sand, water, or oil cell, even when blocked or falling straight
down. Seed initializes the state; all arithmetic wraps modulo 2^64.

Immutable shared per-material behavior classes calculate movement and thermal
actions; cell state is never stored in them. Pitch remains ID 5 and blocking,
even while orange/burning. Oil is nonblocking and uses the same liquid movement
and shared flammable reaction rules through immutable composition.
Heat is an abstract UInt16 quantity. A heat transfer adds 40 with saturation
at 65535; at 100 or above pitch ignites, with burn age zero. An unburning,
heated pitch cell cools by 1 on each of its processed turns, to a minimum of
zero. Oil ignites at 80, also cools by 1 when unburning, and burns away after
48 processed burning turns. Fire and burning flammable cells increment their
respective UInt16 ages saturating at 65535. Starting with age zero, they can
transfer heat starting at age 2.
Fire expires to empty after its 32nd processed turn; burning pitch burns away
to empty after its 64th processed turn. Their last turns can still transfer heat.
Ignition does not advance burn age that tick. Fire is thus able to
ignite pitch from a single paint, and burning cells can independently spread.

Each source checks down, left, right, up for water first. Fire consumes the
first water and extinguishes; hot or burning pitch or oil consumes the first water and
resets its thermal state to zero, retaining its material. Cold flammable material ignores water.
Oil resolves its quench, burning/cooling and heat callbacks before its own
movement. If hot oil acts while cardinal water is present, quenching consumes
that water and the oil does not move that turn. A water or sand actor that
displaces oil first carries its current state without invoking an oil callback;
the moved oil cannot act again that tick. It may quench on a later tick.
Resident batches can visit water before lower oil, unlike the usual y-ordered
deterministic pass; within a batch proposals use a snapshot but conflicts and
callbacks resolve against the current world in order. A moved destination is
woken for later resident processing. Thus batch/budget choices can affect
whether quenching precedes displacement.
Water can have moved earlier in the tick. Without quenching, a source transfers
to at most one eligible nonburning flammable cell among all eight neighbors per tick. Eligible
targets are ordered down, left, right, up, down-left, down-right, up-left,
up-right, then rotated by source age modulo
eligible count; the warmest target is selected, using the first rotated target
for equal heat. Completing warmer targets avoids endlessly diluting heat, while
excluding burning targets permits branches to be served. This is bounded
fairness for stable neighborhoods with sufficient source lifetime, not a
promise under moving water, competing sources, deferral, or changing terrain.
Before applying heat to the selected flammable cell, that cell checks its own currently
edge-adjacent accessible water in down/left/right/up order. If present, it consumes
the first water and resets to zero instead of receiving heat, even if it was
cold before this attempt. This still spends the source's one target for the
tick; the source does not try another target and does not extinguish. That
water may already have moved. A source's own adjacent water still takes
priority and extinguishes or quenches the source before it selects a target.
The target-side check observes only the active region in deterministic mode;
water in a frozen chunk cannot be consumed.
The first source in traversal/commit order claims a target per global tick.
A heated or quenched target cannot subsequently act or be heated that tick;
a target that already had its own turn may be heated after cooling on that
turn, but cannot act again. A quenched target cannot reignite that tick.
Oil resolves its thermal action at its starting position before attempting its
liquid move; quenching consumes the turn, and burnout removes the cell without
moving. Otherwise its updated thermal state follows it to its destination.
Heating or quenching an oil target claims it for the tick and prevents its
movement or own reaction in that tick; if it already moved it cannot be heated.
Newly ignited cells never spread on their ignition tick. Diagonal heat passes
between solid corners; diagonal water never quenches either source or target.
Thermal choices are not random. This expanded neighborhood intentionally changes
old seeded replays when diagonal candidates are present. Beacon Run separately samples the completed
material state for character damage as described below. Frozen chunks neither
cool nor age, and cannot exchange heat across the active boundary.

## Resident-world mode

`ResidentSimulation` is a separate, opt-in mode; `Simulation` retains the
deterministic behavior above. Its finite world is 64,000 by 128,000 cells:
x is -32,000...31,999 and y is -64,000...63,999. All populated chunks remain
resident, while empty chunks are implicit and require no cell arrays. This
does not guarantee that a densely populated world fits in memory: even one
byte per cell would require 8.192 GB before overhead and snapshots.

The square chunk width is selected at world creation. It defaults to 64 and
must be a power of two at least 16 whose square fits in `Int`. There is no
artificial upper limit; impractically large widths or dense worlds can exhaust
memory, and Swift allocation failure is not recoverable by this API. Changing
width requires creating another world. Coordinates, tick-indexed replacement
commands, immutable full snapshots, and rejected input are exposed separately
from the original mode. Boundary chunks have empty out-of-world padding.

The host supplies an in-bounds focus and a `shouldStartBatch` callback on each
`advance`. The future host is intended to use the center of a 480 by 270-cell
viewport as focus. Neither a viewport nor a clock is implemented in the core.
Commands apply at the beginning of the global tick even if no batch runs.
Active chunks are sorted once per tick by `lastProcessedTick + Manhattan
distance in chunks from focus`, with y/x tie-breaking; never-processed chunks
start at zero. This generally favors the focus while aging distant work.
Eventual service requires a finite active set and the host to permit ongoing
batch progress; a host that always declines work cannot guarantee it. Scheduling
history is retained even after a chunk empties, to prevent repeatedly recreated
nearby chunks from starving distant work.

The callback is consulted before each batch, not per cell. A started batch
finishes even if the host's deadline passes. Sorting and command application
occur before the first callback, so the callback is not a hard bound on the
whole tick. The report counts considered and processed chunks and batches.
The host must use a monotonic clock and choose and measure its own time budget;
none is set by the core. Deferred chunks do not replay missed ticks: they update
more slowly and interact with current neighbors.

Within a batch, chunk proposals are calculated in parallel from the same
immutable world state. Sand, water and oil propose their normal movement preferences
using a seed/tick/position-derived direction; fire, pitch and oil propose edge-adjacent
water and eight-neighbor flammable materials. Movement proposals obey the
diagonal side-cell rule; heat does not. Proposals commit in world y/x order; each source must still hold its
original material, and destinations and diagonal side cells must still be
available. Liquid displacement is resolved against the current committed world
and cannot relocate a liquid already moved that tick. A move tries its remaining proposed destinations if an earlier
choice was claimed. A moved cell cannot move again in the same global tick,
including across batches. Later batches see earlier commits. Consequently,
batch size, focus, and deadline decisions can change outcomes. The mode does
not record schedules or promise reproducible replay across runs or devices.

Flames and oil propose edge-adjacent water and all eight-neighbor flammable materials visible at batch
start. Commit checks still-present candidates and current thermal state using
the thermal rules above. New direct neighbors of the source created since
proposal are not considered. The selected target's water check instead reads
the committed world at that instant, including water moved or created since the
batch proposal; this avoids skipping a quench when the target is claimed.
The source can quench a target in a deferred chunk; consuming water wakes
affected allocated chunks under the ordinary cross-batch rules.
A heat attempt marks its target updated for the global tick even when quenched
and across batches.
Oil movement and reaction candidates are captured independently at batch start;
commits recheck them against the current world, with reactions before movement.
Skipped mobile cells restore their chunk's wake even when their heat is zero.
Ages and cooling advance only when the owning chunk is processed; a deferred chunk does not advance. A
processed fire may interact across a chunk boundary even if the neighbor chunk
is deferred; changed cells wake allocated neighboring chunks, which wait for
the next tick if absent from the original candidate list. A changed hot or burning
cell keeps its chunk active; inert pitch and blocked cold oil can sleep until a nearby edit wakes them.
If a later batch clears the wake for an already-heated cell, its skipped
proposal restores the wake. Deferred processing extends durations in global
ticks rather than catching up.

Chunks with no resulting changes sleep. A changed cell wakes its own chunk and
any allocated chunk containing a neighboring cell, including diagonals. Newly
woken chunks not in the tick's original candidate list wait until a later tick.
There is no streaming, resource budget, renderer, or host deadline yet.

## Snapshots and digest

`snapshot` is a complete immutable Swift value for the last completed tick,
including seed, RNG state, and all nonempty chunks in increasing chunk y then
x order. Arrays use Swift value semantics: retaining a snapshot preserves its
contents as the simulation advances. A renderer may do a full resync from any
snapshot; absence of a previously seen chunk means removal, even when revisions
were skipped. There are no deltas or dirty notifications. The renderer must
retain or copy any storage used by asynchronous GPU work until completion;
concrete GPU upload buffering and synchronization are not implemented.
Each `ChunkSnapshot.thermalStates` array uses the same indices and length as
`cells`. `SimulationSnapshot.thermalState(at:)` and
`ResidentSnapshot.thermalState(at:)` provide checked lookups, returning
`.zero` for an empty position; snapshot equality includes thermal data. Arrays
have value semantics and do not share mutable per-cell objects with the world.

The `digest` is FNV-1a 64-bit, wrapping modulo 2^64. It hashes little-endian
64-bit words: digest version 3, seed, completed tick, RNG state, chunk count,
then for each sorted chunk signed two's-complement x and y as 64-bit words,
followed by 4,096 material identifier bytes in row-major order, then 4,096
thermal records in the same order. Each record is seven bytes: heat as a
little-endian UInt16, burning as 0 or 1, burn elapsed as a little-endian UInt16,
and fire elapsed as a little-endian UInt16. Version 3 differs from version 2
even for zero-thermal worlds; version 2 distinguished the 64-wide layout from
version 1's 16-wide layout. The stage-3 physics change keeps the stage-2 v3
byte layout but changes the simulation rules and therefore is not replay
compatible; old digests are not comparable as evidence of equal future behavior.
The later target-side water-priority correction, oil addition and liquid-density
rules also change replay outcomes
without changing the v3 byte layout.
Prior digest versions are not compatible. It includes the
completed world and RNG state, **not queued future commands**; equal digests
alone do not establish equal future inputs. It is not a cryptographic hash,
save format, or cross-device determinism certification.
Resident snapshots have no digest; their equality includes thermal data but
their deadline-dependent scheduling still precludes a replay guarantee.
There is no save migration.

## Persistence and save format

**Implementation status: not implemented.** The types, byte layout, limits, and
errors below are a contract for the next implementation iteration. No
`SaveCodec`, `SaveError`, save value, or file-writing store exists in the
repository yet; `BeaconRun` still has no save, and README's "there is no save"
remains accurate until that iteration merges. The rules, constants, and field
names below are the current code's, not a proposal to change gameplay.

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
`Sources/SimulationCore/SaveCodec.swift`, with `SaveError` in
`Sources/SimulationCore/SaveError.swift`. The type imports nothing: no
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
| 10 | 2 | digest version, `3` |
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

### Module-internal support required

The state lives behind `private` storage today, so the coding stage needs these
internal (not public) additions, each in the owning type's file:

- `Sources/SimulationCore/Simulation.swift`: an internal restoring initializer
  taking seed, tick, random state, chunk contents with thermal arrays, and
  grouped pending commands; it validates cell/thermal counts, recomputes
  `occupiedCount`, and inserts chunks and commands without re-enqueueing. Also
  an internal `pendingCommands` accessor returning commands in `(tick,
  enqueue order)` order.
- `Sources/SimulationCore/SimulationSnapshot.swift`: add
  `public static let digestVersion: UInt64 = 3` and use it in `digest`. The
  existing internal memberwise snapshot initializer and `ChunkSnapshot` internal
  initializer are sufficient to build the digest input.
- `Sources/SimulationCore/BeaconCourse.swift`: an internal memberwise
  initializer for the stored course fields.
- `Sources/SimulationCore/FixtureCharacter.swift`: an internal restoring
  initializer exposing `position`, `grounded`, `verticalVelocity`, and
  `verticalRemainder`.
- `Sources/SimulationCore/ChimeWarden.swift`: an internal restoring initializer
  for `position`, `direction`, `phase`, and `alive`.
- `Sources/SimulationCore/BeaconRun.swift`: an internal restoring initializer
  that sets `seed`, `course`, `simulation`, `character`, and the gameplay fields
  without generating a course or queueing fixtures.

No public gameplay API changes are required. New files in the coding iteration:
`Sources/SimulationCore/SaveCodec.swift` and
`Sources/SimulationCore/SaveError.swift`. `Package.swift`, the app target, and
the future `GamePersistence` target are untouched by that iteration.

### Test plan for the coding stage

Add these test files under `Tests/SimulationCoreTests/`, using
`@testable import SimulationCore` for the internal restoration and private
fields:

- `SaveCodecTests.swift`
  - Tick-zero round trip: fresh `BeaconRun`, zero chunks, queued fixture
    commands; decoded fields, snapshot, and re-encoded bytes equal; both runs
    advance one tick identically.
  - Mid-run round trip after painting, water/fire/pitch interaction, damage,
    collected beacons, and a pulse flash: compare every public gameplay field,
    snapshot equality, digest equality, and re-encode byte equality.
  - Boundary cells and negative coordinates: paint at the coordinate limits and
    across chunk boundaries (`-1`/`-64`, `63`/`64`), then round-trip.
  - One sparse chunk and one dense chunk in the same save; snapshot equality.
  - Queued commands: multiple future ticks and multiple writes to the same cell
    in one tick; after decode, advancing shows the same last-write-wins result.
  - Encoding determinism: encoding the same run twice is byte-identical, and
    `encode(decode(bytes)) == bytes`.
- `SaveFormatValidationTests.swift`
  - Bad magic; unknown format version (0, 2, UInt16.max); unsupported rules and
    digest versions; nonzero flags; header truncated at every length below 24.
  - Declared payload size too small, too large, and actual trailing bytes.
  - Truncation inside world header, chunk table, cell entries, commands, and
    gameplay block.
  - Unknown material ids in cells and commands; empty material in a sparse cell
    entry; `burning` other than 0/1.
  - Out-of-range chunk position, out-of-range cell (including nonempty padding
    beyond 1,000,000), duplicate chunk, noncanonical chunk and command order.
  - Oversized payload, chunk, total entry, command, and flash counts; flash
    count nonzero with zero remaining ticks; each invalid gameplay field.
  - Command tick equal to or below the completed tick.
  - Digest mismatch after flipping a world cell byte; assert the exact
    `SaveError` case, not a message.
- `SaveResumeTests.swift`
  - Resume-then-advance equivalence: run a scripted 40 ticks, save, decode,
    then advance the decoded run and an unsaved control for 60 more ticks with
    identical inputs, comparing snapshot, digest, and gameplay fields each tick.
  - Same with a non-nil `activeChunks` region supplied to both runs, confirming
    the region is a host input rather than saved state.
  - Resume with commands still queued for future ticks; they apply on the same
    ticks as the control.
  - Terminal run (`won`, `fell`, `exhausted`) round-trips and stays frozen and
    paint-disabled after load.

These tests are core-only and need no GPU, UI, or filesystem. Byte-golden
fixtures are optional; if added, they must be small and regenerated by the test,
not hand-edited.

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

## Host and future work

The Apple app runs `BeaconRun` with a host-owned
monotonic 60 Hz accumulator, independently of display callbacks. It performs at
most four ticks per timer callback and discards excess elapsed time rather than
skipping ticks. Lifecycle changes reset the time baseline and accumulated time.
The Metal renderer reads complete immutable snapshots; each frame uses a fresh
RGBA texture held by its command buffer through GPU completion. The camera
tracks the character's center and covers 200 cells along the drawable's long edge, with the short edge
rounded to the nearest whole cell (at least one). Its viewport is uniformly
scaled to fit and may have small margins; nearest-neighbor sampling does not
guarantee equal-sized display pixels at fractional scales. Full re-rasterizing
handles skipped snapshots and removed chunks; it is not a measured upload
strategy for a larger world.

The host computes the visible chunk rectangle from the viewport, including
partially visible chunks, and extends it by twice its chunk width and height
on each respective side for physics. The region updates on drawable size changes
and after every character tick, independently of display callbacks;
the simulation waits for a valid viewport before ticking. Rendering skips chunks
outside the visible rectangle. Frozen chunks remain in complete snapshots.

The top-left overlay is a vertically scrollable viewport, constrained to 45%
of the host view width when the view is at least 116 points wide (its fixed
padding is 52 points). Its height fits the view; on iOS it reserves 96 points
at the bottom for movement, jump and pulse. Its presentation-only guide shows
the current beacon/gate objective or terminal restart prompt, followed by
platform-specific movement, jump, pulse and painting reminders. Scroll to reach Restart, New Run,
Stats, Help and all seven brushes in a compact window. The same keyboard shortcuts
work while controls are offscreen. Help contains controls and fixture
instructions, and Stats opens the diagnostic panel reporting submitted FPS, completed tick, rendered
and allocated chunk counts, and the character's lower-left position. Rendered
counts are from the last submitted camera frame; allocated counts are from the
latest completed snapshot, so they can refer to different ticks. The simulation
continues while the panel is open; controls and the scheduler baseline reset on
opening and closing it. Restart recreates the current seed; New Run adds
`0x9e3779b97f4a7c15` modulo 2^64 to it (initial seed 42). Both create a
fresh run at tick zero, clear controls and pending edits, reset the scheduler
and refresh the renderer. The sequence is local, with no seed entry or save.
The material brush maps mouse or single-touch strokes through the same
following drawable viewport as the renderer, ignores letterboxing and cells
outside the world, and fills gaps between sampled cells. The overlay selects empty, solid, sand, water,
fire, pitch or lamp oil (also via keys 1–7); each cell replacement is enqueued in event order for
the next tick. A stroke leaving the viewport is disconnected until it re-enters.
The host surfaces enqueue and tick-overflow failures; inputs are not recorded
for replay. Missing Metal devices, renderer initialization failures, simulation
errors and GPU command errors are displayed; a missing drawable skips a frame.
`FixtureCharacter` starts at (-2, 6), has a 5 × 9-cell body, and advances once
after each completed material tick using that tick's snapshot. One horizontal
cell is attempted per tick; vertical velocity uses quarter-cell integer units,
with gravity and a bounded fall speed. When grounded horizontal movement is
blocked, the character can step up at most three cells, provided the upward and
horizontal paths are clear and the destination has support. Movement checks each newly entered edge,
including intermediate vertical cells, against rock, sand, pitch, and world bounds.
Empty space, water, fire and oil do not block the character; the character does not affect
material rules. Jump presses are buffered until the next tick and only take
effect while grounded. Simultaneous opposite directions cancel. Controls reset
on lifecycle changes and window focus loss. Painting a blocking material inside the
character is ignored, but an earlier queued edit or moving sand can overlap it;
edge-only collision permits it to leave such an overlap.
On macOS, each window attachment owns its keyboard monitor and focus observer.
Detaching, replacing the view, or destroying it cancels each registration at most
once; a detached view cannot leave an old keyboard monitor installed.

`BeaconRun` owns the seed, immutable `BeaconCourse`, simulation, character,
health, vent, two collected flags and outcome. Generation uses fixed UInt64
wrapping arithmetic and a SplitMix64 finalizer, independently choosing each
bounded feature; it never consults time, retries or platform APIs. Specifically,
choice i is `(mix(seed &+ i) ^ mix(42 &+ i)) % count`, with mix defined in
`BeaconCourse`. Seeds may map to the same layout; seed 42 preserves the original
fixture positions. The deprecated public `BeaconRun.beaconPositions`,
`BeaconRun.goalPosition`, and `BeaconRun.ventX` constants retain their original
fixed-course values for source compatibility. They match seed 42 but must not be
used to locate fixtures for arbitrary seeds; use the corresponding fields of
`run.course`. Gameplay and rendering use that generated course, not the legacy
constants. At tick 1 it installs a rock floor x=-40...160 at y=-2
except a gap starting at 36...40 of width 10...12, a 3-cell-high, 5-cell-wide
step starting at 14...16, and 6-cell-wide sand starting at 65...69, from y=-1
through y=14...16.

The first beacon is at x=22...25, the second at x=92...97, both at y=0.
The seven-cell-wide vent starts at x=123...128; the gate begins immediately
after it. The Chime Warden spawns at (107...109, -1), chosen with index 8
of the same seed function, and patrols lower-left x=104...112. Its five-cell
width stays clear of the second marker and vent. These separated ranges leave stable floor before and after the gap,
keep the low step climbable, keep sand away from the gap and markers, and
provide an unobstructed route past the vent. A grounded jump from five cells
before the gap crosses every allowed width; moving right while pulsing after
the gap can clear the sand without painting, and crossing the vent normally
costs at most one of three health. These are constraints on unedited generated
courses, not guarantees after painting or a general reachability proof.
The finite generator does not reject or repair layouts.
Five pitch cells at x=6...10, y=13 form a small floating experimental fixture
above the start, clear of the standing route. It does not ignite by itself:
paint fire beside it and water beside the orange cell to quench it. The host
applies paint before physics, and ignition requires multiple heat transfers;
display callbacks may still skip states under
load. At a 1000×600 host size after settling, the shared HUD geometry keeps
these cells and the cells directly above and below them outside the HUD;
320×300 and portrait 600×1000 layouts are also covered by geometry tests.
On macOS, a hosted SwiftUI test checks the actual scroll viewport and that all
eleven action and brush buttons can be scrolled fully into view at these sizes,
including the iOS bottom-reserve geometry. The HUD is not a
physical-device touch or readability validation.
Materials update before the character. After movement, a lower-left character
y of -20 or below loses, taking precedence over damage and marker checks. Otherwise,
the vent and health rules below run before marker checks; lethal damage also
takes precedence over a simultaneous goal. If alive,
overlap of the 5 × 9 body with each generated 5 × 12 marker collects it.
Overlap with the generated gate wins only once both flags are
set; visiting early does not automatically win later. Markers are not cells and
cannot be painted away. The renderer draws the vent, uncollected amber outlines,
gray locked or green unlocked gate, warden, pulse flash and player over the
materials, in that order. While the living warden overlaps the player, a bar
on the player's top visible row and a bell icon above it are drawn in the warden's
current warning/danger/recovery color, so the opaque player cannot hide the
encounter phase; the rest of the player retains its protection color. The bell's
upper row includes two phase-colored pixels that remain visible even if the
lower icon and entire phase bar are covered by hazards, provided that row is
within the viewport. A win or failure freezes ticks and ignores paint until
restart. Other than body protection, brushes remain unrestricted, so players
can bridge or erase obstacles.

The heat vent is a non-material course fixture occupying the generated vent x
range and y=0...6, just before the gate. Its striped red area is hot; blue means cooled.
Its contact rectangle uses inclusive cells against the character's half-open
body rectangle; touching only an edge is not contact. It can be jumped over.
After material physics and character movement on each playing tick, the vent
samples post-physics water in the generated vent x range, y=-1...3. The sensor includes the
space immediately above the floor, so water painted on the visible base at
y=0 can fall to y=-1 and still cool it. Any water there resets
cooling to 120 ticks without consuming the water; otherwise the cooling timer
decrements toward zero. It is safe on the wet tick and while the remaining timer
is positive; it becomes hot on the tick the timer reaches zero. Water can move
out of the sensor, be erased or react with fire according to normal rules. The
fixture and sensor are evaluated every gameplay tick, including if their chunk
is frozen; frozen material itself still obeys the active-region rules.

The character starts with three health. Fire cells and burning oil damage when
they overlap the 5 × 9 body. Burning pitch damages on overlap or when it shares
a horizontal or vertical cell edge with the body; corner-only contact is safe.
This additional pitch boundary makes the blocking material dangerous without
requiring penetration. Nonburning hot pitch or oil and ordinary water are safe.
After commands, all material movement and reactions, and character movement,
only the final cell positions and burning flags are sampled, including in frozen
chunks; intermediate crossings, cells quenched, removed or burned out that
tick do not damage. Out-of-world cells are ignored. Newly ignited material
can hurt immediately. Overlapping fire and burning oil or pitch, and every
edge-adjacent burning pitch cell, receive black or white marks at their exact
cells. Every boundary mark chooses black or white to maximize its minimum
contrast against visible, unmarked orthogonal neighbors; fully surrounded
interior marks use a world-anchored checkerboard. A one-cell-wide region can
therefore be a solid contrasting band. A single pixel cannot achieve high
contrast against both black and white neighbors simultaneously; the choice is
the best of the two colors, not a 4.5:1 guarantee for every boundary.
This replaces the pitch's orange only at contact.
Cold or merely hot fuel has no mark. The HUD identifies the last hit while the shield is active;
Help explains the contact rules. Display callbacks can still skip hazard states.

Fire, hot vent or threatening warden contact deals one damage immediately
when the global protection timer is zero, setting it to 30 ticks. Simultaneous
contacts produce only one hit, identified in priority order fire, vent, warden.
The timer decrements
on each subsequent playing tick, including outside the vent or while cooled;
contact can damage again on the tick it reaches zero. A pink character and the
HUD show the remaining protection; health does not regenerate. Zero health
ends the run as `exhausted`. Restart restores all health and timers and clears
the last-hit source.
The vent does not itself alter material rules or the material snapshot digest.

The Chime Warden is a single 5 × 6-cell, non-material rectangle; it does not
block the player or materials. After material physics and player movement it
checks that every body cell is free of blocking material and every cell directly
under its width has blocking material support. If not, it is removed permanently for
that run, including if moving sand buries it or its support is erased. It does
not fall, climb, teleport, respawn or search for a new floor. Otherwise its
60-tick phase advances modulo 60. Phases 0...23 are amber warning, 24...35
red contact danger, and 36...59 purple recovery; phase zero is the initial
state. Every sixth phase (including zero), it attempts one horizontal cell,
initially left. It reverses without moving when its next full rectangle lacks
clearance or support, or would leave the patrol lower-left bounds. Water,
fire and oil are passable. This update runs every gameplay tick regardless of frozen
chunks, against the post-physics material state. A threatening half-open body
overlap uses the same global 30-tick damage protection as the vent; simultaneous
contact cannot deal two hits. Damage is checked before pulse and goal, and
lethal damage wins over either. Direct painting of blocking materials into a living
warden is ignored, but commands queued before it moved or material physics
can still change the area; the next validation applies the removal rule.
This intentionally bounded terrain response is not general enemy navigation.

The Silt Pulse fires in the last nonzero horizontal movement direction (initially
right), even if movement is blocked. Holding F on macOS or the iOS bolt button
repeats; a tap between ticks is buffered. Accessibility activation fires once.
Controls, held state, and buffered presses clear on restart, lifecycle changes,
diagnostics transitions, and macOS focus loss. A press during cooldown is not
queued for later unless held. A pulse costs 18 ticks of cooldown, decremented at
the start of each subsequent completed gameplay tick; holding fires again when
it reaches zero. The overlay displays remaining ticks or READY.

After material commands and physics, character movement, timer decrements, and
fall/damage/goal checks, a playing run may fire. Thus a winning or failing tick cannot
fire; terminal runs freeze cooldown and flash until restart. Five horizontal
lanes at character lower-left y+2...y+6 start immediately outside the facing
edge, extending at most 18 cells each. Each lane stops at the world boundary,
the first rock, pitch, or sand. Rock and pitch are unchanged; the first sand is removed;
empty, water, fire and oil are transparent and unchanged. Each pulse inspects at
most 90 cells and removes at most five. It uses the post-physics snapshot, so
paint commands applied this tick affect occlusion; removed sand affects physics
on the next tick. Like painting, this explicit action can modify frozen chunks.
The completed material snapshot includes removals. A cyan flash of the traced
cells, including hits, lasts four gameplay ticks (the firing tick included);
the renderer only reads it. If any traced cell reaches the living warden, the
warden is removed after tracing; rock, pitch and the first sand per lane shield it,
and sand excavation still occurs normally in every lane. The pulse is not
stopped by the warden. For an overlapping warden, a separate near-field check
walks each of the same five lanes across the player body, from the facing edge
inward, stopping before the first blocking material or world boundary. A warden cell
reached in that check also counts as a hit, even when it is entirely inside the
player; empty, water, fire and oil are transparent. This check neither excavates
material nor extends the external range or flash. Both checks use pre-excavation
material, so a pulse cannot hit through sand it removes on that tick.
Restart recreates the warden, initial facing, cooldown and
empty flash.

Course layout, warden position/direction/phase/alive state, character, health,
vent, pulse and progression state and queued input are separate from
`SimulationSnapshot` and its digest, so the digest does not represent a
complete gameplay state. There is no respawn except restart. Resident-mode
integration, richer gameplay, physical-device lifecycle and performance
validation remain open.

## Material expansion (identifiers 8-15)

Digest version bumped from 4 to 5 and rules version from 2 to 3 for this change.
The eight new materials reuse the existing single `heat` field (plus `isBurning`,
`burnElapsed`, `fireElapsed`) as documented below; no new storage fields were
added.

- `lava` (8): hot viscous liquid. Moves like a liquid but only one destination
  per tick, with no diagonal movement unless straight down is blocked. Heat
  starts at 300 and cools by 1 per processed turn; at heat 0 it becomes solid.
  Ignites flammable neighbors (pitch/oil/blood) and creates fire in adjacent
  empty cells. Water adjacency converts lava to solid and that water to steam.
  Treated as a thermal hazard on body overlap in the host.
- `acid` (9): liquid like water. Each tick, with small deterministic probability
  (direction draw plus coordinate hash), dissolves one adjacent solid/sand cell:
  both the acid cell and the dissolved cell become empty. Does not dissolve pitch
  or other liquids.
- `blood` (10): liquid like water (same movement and displacement as water).
  Flammable with ignition threshold 60 and burnout 24. Otherwise standard
  flammable reactions.
- `slime` (11): viscous liquid that moves only every third processed turn
  (phase counter stored in the heat field: heat increments each turn, movement
  occurs when the value is divisible by 3). No diagonal movement; moves straight
  down then spreads sideways. Does not displace other materials.
- `ice` (12): solid powder falling like sand (displaces water/oil). Melts to
  water when an adjacent cell has heat > 50 or is fire/lava. Freezes adjacent
  water with small deterministic probability when its heat is 0 and no heat source
  is adjacent.
- `gunpowder` (13): fine powder falling like sand, with a slightly faster fall.
  Explodes on contact with fire/lava or a burning flammable: the cell and up to
  12 cells within radius 3 become fire or empty by deterministic ~0.5 probability.
- `gold` (14): dense inert powder falling like sand, displacing water and oil
  (not lava). No reactions.
- `magicLiquid` (15): non-flowing liquid. Each turn transforms one adjacent
  non-empty, non-magic-liquid cell along the cycle solid->sand->water->oil->
  pitch->fire->steam->empty. Consumed (becomes empty) after 8 transformations,
  counted in the heat field.

---

## APPENDED: Seeded cave world generation (agent/cave-worldgen)

`CaveWorldGenerator` (in `Sources/SimulationCore/WorldGeneration.swift`) produces a
larger multi-material grid deterministically from a seed and a bounded world size.
It uses only the 8 existing materials (empty, solid, sand, water, oil, pitch,
fire, steam). Terrain is layered solid carved by 4-octave value noise, with
flood-fill connectivity repair carving L-shaped tunnels (deterministic). Sand
fills shallow depressions, sealed water pools are walled in solid, and small
3-8 cell pitch/oil pockets are scattered. Extents stay within
`Simulation.coordinateBounds`.

API: `CaveWorldGenerator(seed:width:height:)`, `.generate() -> CaveWorld`, and
`.stamp(into:tick:)` which enqueues one `SimulationCommand` per non-empty cell
in chunked 512-cell batches (no giant intermediate array). `CaveWorld` exposes
`cells`, `spawn`, `goal`, `extents`, and `materialCounts`. Same seed yields an
identical `CaveWorld`.

---

## APPENDED: Enemy material reactions (agent/enemy-material-reactions)

`ChimeWarden` reacts to surrounding materials across its 5x6 area and feet:
- Water: quenches burning state, halves patrol step rate.
- Oil / Ice: makes ground slippery, doubling step distance (up to 2 cells).
- Hazards (`fire`, `lava`, `acid`): deals shield damage with 30-tick damage cooldown.
  - Fire / burning flammables: 1 shield damage, ignites warden.
  - Lava: 2 shield damage, ignites warden.
  - Acid: 2 shield damage, does not ignite.
  - Burning warden remains on fire until quenched by water.
  - Taking damage spawns 3 blood cells at warden's feet.
  - Shield zero removes warden from run.

## APPENDED: Cave materials (agent/cave-materials)

`CaveWorldGenerator` now places all 16 materials. New placement rules:
- Safety margins: dangerous materials (lava, acid, gunpowder, magicLiquid, fire) stay ≥6 cells (Chebyshev) from spawn/goal; lava keeps ≥8 cells.
- Protected materials (water, sand, lava, acid, gunpowder, magicLiquid, pitch, oil, blood, ice, slime, gold) are never carved through by connectivity repair.
- Magic liquid: 1-3 single-cell doses buried deep in rock.
- Gold: veins inside solid rock plus surface nuggets on cave floors.
- Gunpowder: thin seams adjacent to pitch/oil pockets.
- Ice: patches in upper, shallow caves.
- Slime: small pockets at mid depth.
- Acid: rare sealed pockets in lower rock.
- Lava: rare deep pools walled by solid rock; contained by `sealHazards` after carving.
- Blood: small pools next to oil pockets.
- Connectivity repair runs after material placement; fallback direct route carves if spawn cannot reach goal; borders and spawn/goal are re-enforced after all carving.

## Burning terrain spread (appendix)

### Consumption timing
- A burning flammable cell consumes itself once its burn age reaches `burnoutAge`
  processed burning turns: pitch 64, oil 48, blood 24. Pitch is consumed like
  oil and blood: while it burns it stays pitch (ID 5, blocking); on its 64th
  burning turn it becomes empty with zero thermal state, leaving open space
  behind it.
- The final burning turn still transfers heat to its selected target before the
  cell is consumed, so a burnt-out cell can still ignite a neighbour.
- A cell that is quenched by water keeps its burn age and its material; it is
  not consumed on that turn.
- Fire expires to empty after 32 processed turns (unchanged).

### Charring rule
- A burning cell (fire, or any burning pitch, oil or blood) that has a `solid`
  neighbour converts that solid to `pitch` with a fixed 1/16 chance per turn and
  per burning neighbour. The roll is derived from the source position, the
  source's burn/fire age and the neighbour position; it consumes no random
  stream, so movement draws are unchanged and both simulation modes reach the
  same result for the same scene.
- Only burning sources char. A hot but not burning cell never chars, and neither
  does a cell that spends its turn on its water reaction: water keeps priority,
  so a source that quenches or consumes water that turn neither spreads heat nor
  chars.
- The charred cell is a normal pitch cell with zero thermal state. It is not
  burning yet, so it has to reach the pitch ignition threshold again before it
  burns; once burning it consumes itself on its own 64th burning turn.
- Adjacency is the same eight neighbours used by the heat rules, and charring
  respects the active region (`canVisit`), so a frozen chunk is never charred.
  Charring crosses chunk boundaries when both chunks are active.
- Charring applies to `solid` only. Sand, ice and the other materials are not
  affected.

### Digest and rules version
- `SimulationSnapshot.digestVersion` bumped from 5 to 6.
- `SaveCodec.rulesVersion` bumped from 3 to 4.
- Replay/save compatibility changes: charring adds solid->pitch writes, so old
  digests and old saves are not compatible.
