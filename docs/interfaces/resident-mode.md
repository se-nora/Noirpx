# Resident mode

## Resident-world mode

`ResidentSimulation` is a separate, opt-in mode; `Simulation` retains the
deterministic behavior in [core grid and commands](core-grid-commands.md). Its finite world is 64,000 by 128,000 cells:
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
the thermal rules in [core grid and commands](core-grid-commands.md). New direct neighbors of the source created since
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
