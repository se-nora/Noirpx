# Simulation and host interface contracts

The milestone 1 choices below are a **provisional, single-owner prototype**.
They have not been reviewed by separate core and renderer contributors. That
review and agreement are required before dependent implementation branches
diverge; particularly review full-snapshot cost and GPU buffer ownership.

## Coordinates and storage

World coordinates are signed integer cells; x increases right and y increases
up. Valid coordinates are inclusive -1,000,000 through 1,000,000 on each axis.
Outside is an impassable boundary. Commands and snapshot lookups outside these
bounds throw `positionOutOfBounds`. The limit ensures neighbor and chunk
arithmetic is safe on supported Swift platforms; it is not a streaming policy.

Chunks are provisionally 16 by 16, row-major from local (0, 0), using floor
division and nonnegative local coordinates. This small, simple unit permits
testing both positive and negative boundaries without large allocations; it is
not performance-tuned. Each chunk stores 256 `Material` values; empty chunks are
removed. Boundary chunks include empty padding outside the world. Chunk size,
layout, allocation and snapshot costs need measurement before being permanent.
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

After commands, capture the occupied positions and process them in increasing
world y, then increasing x. A cell displaced into a position is marked so it
cannot be processed again that tick. Updates are immediate: the first actor to
claim an empty cell wins, and later actors see prior movement and reactions.
Empty and solid do not act. Sand attempts down, then the two down-diagonals;
water does the same and then attempts the two horizontal neighbors. The first
empty in-bounds destination wins; no material is displaced. The left/right
preference for both diagonal and horizontal choices comes from one SplitMix64
draw per processed sand or water cell, even when blocked or falling straight
down. Seed initializes the state; all arithmetic wraps modulo 2^64. Fire checks
down, left, right, then up, removes the first adjacent water if present, and
always expires to empty on its turn. Fire has no other effects. A water cell
may move before or be consumed by fire according to the same traversal order.
These deliberately simple rules are prototype behavior, not a balance promise.

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
64-bit words: digest version 1, seed, completed tick, RNG state, chunk count,
then for each sorted chunk signed two's-complement x and y as 64-bit words,
followed by 256 material identifier bytes in row-major order. It includes the
completed world and RNG state, **not queued future commands**; equal digests
alone do not establish equal future inputs. It is not a cryptographic hash,
save format, or cross-device determinism certification.

## Host and future work

The Apple app constructs only an initial snapshot and displays a Metal clear
color. It does not advance the core or render the fixture. The host owns the
Metal device, view, renderer, and display callbacks; rendering must never mutate
the world or advance ticks. Missing Metal devices/queues are reported, GPU
command errors are logged, and a missing drawable skips a frame.

The future host must translate device input into ordered commands, schedule
fixed ticks independently of rendering, define lifecycle handling and preserve
snapshot and GPU-buffer lifetimes. The proposed 60 Hz accumulator, four-tick
catch-up cap, and suspension baseline reset remain unimplemented.
