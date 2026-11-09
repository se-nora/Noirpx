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
There is no chunk or command-queue budget, streaming, or recoverable
out-of-memory API; Swift allocation failure is not caught. Callers must bound
their workloads, especially on iOS.

## Materials, commands, and tick rules

The enum raw identifiers are empty 0, solid 1, sand 2, water 3, and fire 4.
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
water does the same and then attempts the two horizontal neighbors. Diagonal
movement requires the adjacent horizontal cell to be empty and active. Sand can
enter water that has not already moved this tick: it relocates that water to
the first empty side cell of the destination in the sand's preferred direction,
then the opposite side, or searches upward for the first empty cell, passing
through occupied cells if needed. The sand's vacated cell is available. The
search stays within the world and active region; if it finds no cell, that
destination is rejected. Both relocated water and sand are marked moved.
Otherwise the first empty in-bounds destination wins. The left/right
preference for both diagonal and horizontal choices comes from one SplitMix64
draw per processed sand or water cell, even when blocked or falling straight
down. Seed initializes the state; all arithmetic wraps modulo 2^64. Fire checks
down, left, right, then up, removes the first adjacent water if present, and
always expires to empty on its turn. Fire has no other effects. A water cell
may move before or be consumed by fire according to the same traversal order.
These deliberately simple rules are prototype behavior, not a balance promise.

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
immutable world state. Sand and water propose their normal movement preferences
using a seed/tick/position-derived direction; fire proposes adjacent water in
the normal priority order. Destinations empty, water for sand, or water for fire
at the start of the batch are proposed, subject to the same diagonal corner
rule. Proposals commit in world y/x order; each source must still hold its
original material, and destinations and diagonal side cells must still be
available. Water displacement is resolved against the current committed world
and cannot relocate water already moved that tick. A move tries its remaining proposed destinations if an earlier
choice was claimed. A moved cell cannot move again in the same global tick,
including across batches. Later batches see earlier commits. Consequently,
batch size, focus, and deadline decisions can change outcomes. The mode does
not record schedules or promise reproducible replay across runs or devices.

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

The `digest` is FNV-1a 64-bit, wrapping modulo 2^64. It hashes little-endian
64-bit words: digest version 2, seed, completed tick, RNG state, chunk count,
then for each sorted chunk signed two's-complement x and y as 64-bit words,
followed by 4,096 material identifier bytes in row-major order. Version 2
distinguishes the 64-wide layout from version 1's 16-wide layout, so prior
digests are not compatible. It includes the
completed world and RNG state, **not queued future commands**; equal digests
alone do not establish equal future inputs. It is not a cryptographic hash,
save format, or cross-device determinism certification.

## Host and future work

The Apple app runs the deterministic headless fixture with a host-owned
monotonic 60 Hz accumulator, independently of display callbacks. It performs at
most four ticks per timer callback and discards excess elapsed time rather than
skipping ticks. Lifecycle changes reset the time baseline and accumulated time.
The Metal renderer reads complete immutable snapshots; each frame uses a fresh
RGBA texture held by its command buffer through GPU completion. The camera
tracks the character's center and covers 509 cells along the drawable's long edge, approximately halving
the area of the previous 720-cell view, with the short edge
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

The overlay shows the bundle version, submitted frames per second, completed
tick, rendered and allocated chunk counts, and the character's lower-left position.
Rendered counts reflect chunks with at least one nonempty cell in the last
submitted camera frame; allocated counts reflect all allocated nonempty chunks
in the latest completed snapshot, including those outside the camera. The two
counts can refer to different ticks. Restart creates the same fixture
again. The material brush maps mouse or single-touch strokes through the same
following drawable viewport as the renderer, ignores letterboxing and cells
outside the world, and fills gaps between sampled cells. The overlay selects empty, solid, sand, water or
fire (also via keys 1–5); each cell replacement is enqueued in event order for
the next tick. A stroke leaving the viewport is disconnected until it re-enters.
The host surfaces enqueue and tick-overflow failures; inputs are not recorded
for replay. Missing Metal devices, renderer initialization failures, simulation
errors and GPU command errors are displayed; a missing drawable skips a frame.
The app also extends the fixture floor to x = -120...120. The separate
`FixtureCharacter` starts at (-2, 6), has a 5 × 9-cell body, and advances once
after each completed material tick using that tick's snapshot. One horizontal
cell is attempted per tick; vertical velocity uses quarter-cell integer units,
with gravity and a bounded fall speed. When grounded horizontal movement is
blocked, the character can step up at most three cells, provided the upward and
horizontal paths are clear and the destination has support. Movement checks each newly entered edge,
including intermediate vertical cells, against rock, sand, and world bounds.
Empty space, water, and fire do not block the character; the character does not affect
material rules. Jump presses are buffered until the next tick and only take
effect while grounded. Simultaneous opposite directions cancel. Controls reset
on lifecycle changes and window focus loss. Painting rock or sand inside the
character is ignored, but an earlier queued edit or moving sand can overlap it;
edge-only collision permits it to leave such an overlap.

Character state and input are separate from `SimulationSnapshot` and its digest,
so the digest does not represent a complete gameplay state. The renderer draws
the character over the material frame without affecting rendered-chunk counts.
There is no respawn except restart. Resident-mode
integration, richer gameplay, physical-device lifecycle and performance
validation remain open.
