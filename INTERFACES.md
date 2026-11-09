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
both participants in sand/water displacement; removing material clears it.
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
water and oil do the same and then attempt the two horizontal neighbors. Oil
cannot displace water, sand, or other oil; sand cannot displace oil.
Diagonal
movement requires the adjacent horizontal cell to be empty and active. Sand can
enter water that has not already moved this tick: it relocates that water to
the first empty side cell of the destination in the sand's preferred direction,
then the opposite side, or searches upward for the first empty cell, passing
through occupied cells if needed. The sand's vacated cell is available. The
search stays within the world and active region; if it finds no cell, that
destination is rejected. Both relocated water and sand are marked moved.
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
Water can have moved earlier in the tick. Without quenching, a source transfers
to at most one eligible adjacent nonburning flammable cell per tick. Eligible
targets are sorted in down/left/right/up order, rotated by source age modulo
eligible count; the warmest target is selected, using the first rotated target
for equal heat. Completing warmer targets avoids endlessly diluting heat, while
excluding burning targets permits branches to be served. This is bounded
fairness for stable neighborhoods with sufficient source lifetime, not a
promise under moving water, competing sources, deferral, or changing terrain.
Before applying heat to the selected flammable cell, that cell checks its own currently
adjacent accessible water in down/left/right/up order. If present, it consumes
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
Newly ignited cells never spread on their ignition tick. No diagonals, random
thermal choices, or character damage are involved. Frozen chunks neither
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
using a seed/tick/position-derived direction; fire, pitch and oil propose adjacent
water and flammable materials. Destinations empty, water for sand, or water or flammable for flames
at the start of the batch are proposed, subject to the same diagonal corner
rule. Proposals commit in world y/x order; each source must still hold its
original material, and destinations and diagonal side cells must still be
available. Water displacement is resolved against the current committed world
and cannot relocate water already moved that tick. A move tries its remaining proposed destinations if an earlier
choice was claimed. A moved cell cannot move again in the same global tick,
including across batches. Later batches see earlier commits. Consequently,
batch size, focus, and deadline decisions can change outcomes. The mode does
not record schedules or promise reproducible replay across runs or devices.

Flames and oil propose all adjacent water and flammable materials visible at batch
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
The later target-side water-priority correction and oil addition also change replay outcomes
without changing the v3 byte layout.
Prior digest versions are not compatible. It includes the
completed world and RNG state, **not queued future commands**; equal digests
alone do not establish equal future inputs. It is not a cryptographic hash,
save format, or cross-device determinism certification.
Resident snapshots have no digest; their equality includes thermal data but
their deadline-dependent scheduling still precludes a replay guarantee.
There is no save migration.

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
on the player's top visible row and a bell icon above it are drawn last in the warden's
current warning/danger/recovery color, so the opaque player cannot hide the
encounter phase; the rest of the player retains its protection color. A win or failure freezes ticks and ignores paint until
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

The character starts with three health. Hot vent or threatening warden contact deals one damage immediately
when the global protection timer is zero, setting it to 30 ticks. It decrements
on each subsequent playing tick, including outside the vent or while cooled;
contact can damage again on the tick it reaches zero. A pink character and the
HUD show the remaining protection; health does not regenerate. Zero health
ends the run as `exhausted`. Restart restores all health and timers. None of
ordinary water, fire or oil damages the character, including while frozen.
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
