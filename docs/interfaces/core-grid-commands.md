# Core grid and commands

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
material state for character damage as described in [Beacon Run](beacon-run.md). Frozen chunks neither
cool nor age, and cannot exchange heat across the active boundary.
