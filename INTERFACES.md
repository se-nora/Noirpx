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

The enum raw identifiers are empty 0, solid 1, sand 2, water 3, fire 4,
pitch 5, and 64 consecutive burning-pitch stages 6...69.
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
always expires to empty on its turn. If it found no water, it instead ignites
the first adjacent pitch in that same down, left, right, up order. Pitch is a
stationary blocking solid; ignition changes it to burning stage 6, marked
updated so it cannot advance in the same tick. Burning pitch checks adjacent
water in the same order: it consumes the first and returns to pitch. Otherwise
it advances 6→7→...→69→fire, one stage per processed tick. Ignition on tick T
publishes stage 6 without advancing it; absent quenching and deferral, stages
6...69 are published on T...T+63, and it becomes fire on T+64. Water is checked
first on every burning turn, including T+64, giving 64 subsequent processed
ticks in which to quench. Fire then acts no earlier than T+65. All stages
render the same orange color; at 60 ticks/second this is about 1.07 seconds of
simulation time, not a guarantee of display frames, wall-clock time or human
reaction. Water must actually remain adjacent until the burning turn: painting
one cell directly above the fixture is one way to do that.
Fire can spread to another pitch only when its own subsequent turn runs.
Each actor affects at most one neighbor; there is no random ignition, diagonal
reaction, heat radius, timer, or damage. Water may be consumed even if it
already moved that tick, as with existing fire. Fire and burning pitch check
the current world in traversal order: first claim wins, a consumed water is
unavailable to later actors, and a newly ignited or quenched cell cannot change
again on that tick. Pitch and burning pitch block movement, liquid, player and warden;
the pulse stops at them without removing them. A water cell
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
using a seed/tick/position-derived direction; fire proposes adjacent water
and pitch, and burning pitch proposes adjacent water. Destinations empty, water for sand, or water or pitch for fire
at the start of the batch are proposed, subject to the same diagonal corner
rule. Proposals commit in world y/x order; each source must still hold its
original material, and destinations and diagonal side cells must still be
available. Water displacement is resolved against the current committed world
and cannot relocate water already moved that tick. A move tries its remaining proposed destinations if an earlier
choice was claimed. A moved cell cannot move again in the same global tick,
including across batches. Later batches see earlier commits. Consequently,
batch size, focus, and deadline decisions can change outcomes. The mode does
not record schedules or promise reproducible replay across runs or devices.

Fire proposes all adjacent water and pitch visible at batch start; burning
pitch proposes adjacent water. Commit first checks still-present proposed
water in down/left/right/up order, then (for fire only) still-present proposed
pitch in that order. New neighbors created since proposal are not considered.
An ignition marks its target updated for the global tick even across batches.
Burn stages and quenching use the deterministic transitions above, but only
when the owning chunk is processed; a deferred chunk does not advance. A
processed fire may interact across a chunk boundary even if the neighbor chunk
is deferred; changed cells wake allocated neighboring chunks, which wait for
the next tick if absent from the original candidate list. A changed burning
cell keeps its chunk active; inert pitch can sleep until a nearby edit wakes it.
If a later batch clears the wake for a newly ignited, already-updated burning
cell, processing that skipped proposal restores its chunk's wake for the next
global tick. It does not update twice. Deferred processing can extend the
duration in global ticks, but cannot shorten the 64 processed opportunities.

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
The digest algorithm and version remain unchanged for this addition, preserving
digests of pitch-free worlds given identical inputs. Pitch and its stages hash
as their new identifier bytes; old software cannot decode those identifiers.
The longer burn changes outcomes and future digests for existing pitch-containing
states, including stages 6...9, but not material-only worlds without pitch.
The Beacon Run fixture itself now contains pitch, so its snapshots and digests
intentionally differ from earlier releases. There is no save migration.

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
Stats, Help and all six brushes in a compact window. The same keyboard shortcuts
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
fire or pitch (also via keys 1–6); each cell replacement is enqueued in event order for
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
including intermediate vertical cells, against rock, sand, pitch, burning pitch, and world bounds.
Empty space, water, and fire do not block the character; the character does not affect
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
applies paint before physics, so fire can expire immediately while leaving a
visible burning-pitch snapshot; display callbacks may still skip states under
load. At a 1000×600 host size after settling, the shared HUD geometry keeps
these cells and the cells directly above and below them outside the HUD;
320×300 and portrait 600×1000 layouts are also covered by geometry tests.
On macOS, a hosted SwiftUI test checks the actual scroll viewport and that all
ten action and brush buttons can be scrolled fully into view at these sizes,
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
ends the run as `exhausted`. Restart restores all health and timers. Neither
ordinary water nor ordinary fire damages the character: active fire expires in
the material tick, before gameplay checks, and frozen fire is also harmless.
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
clearance or support, or would leave the patrol lower-left bounds. Water and
fire are passable. This update runs every gameplay tick regardless of frozen
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
the first rock, pitch, burning pitch, or sand. Rock and pitch are unchanged; the first sand is removed;
empty, water and fire are transparent and unchanged. Each pulse inspects at
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
player; empty, water and fire are transparent. This check neither excavates
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
