# Snapshots and digest

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
