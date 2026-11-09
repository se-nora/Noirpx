# Initial interface contracts

These are foundation proposals, not a claim that the world or renderer features
exist. One owner prepared both sides; core and renderer contributors must
review and agree on them before dependent implementation branches diverge.

## Implemented boundary

`SimulationCore` is a standalone Swift package product. `Simulation(seed:)`
creates one simulation owner at tick zero; `advance()` completes exactly one
tick or throws `SimulationError.tickOverflow` without changing state.
`snapshot` returns a value containing the seed and completed tick. Previously
obtained snapshots do not change as the owner advances. The seed is stored but
not yet used for randomness; advancing currently changes only the tick.

The Apple app constructs an initial snapshot and passes it to the Metal view
delegate. The delegate can replace its local snapshot but cannot mutate the
simulation. Drawing currently uses only a clear color and never advances a
tick. An unavailable Metal device or command queue is shown in the UI; command
creation and GPU failures are logged. A temporarily unavailable drawable skips
that frame. No scheduling or platform input is implemented.

## Contracts for subsequent milestones

- **Coordinates and chunks:** use signed integer world-cell coordinates and
  floor division when converting to chunk and nonnegative local coordinates,
  including negative edges. Chunk size, bounds, representation, allocation
  failures, and integer overflow policy must be decided and tested before the
  storage API is implemented. No chunk size is fixed here.
- **Materials:** stable material identifiers and rule data belong to the core;
  presentation maps identifiers to visuals without changing physical behavior.
  Unknown identifiers and invalid definitions must produce explicit errors,
  not silently become empty cells. Rules and versioning remain to be defined.
- **Commands and ticks:** the host translates input into ordered commands for
  explicit ticks. The simulation owns validation and mutation, and must report
  rejected commands explicitly. A tick consumes no real-time clock; RNG state
  derives from the seed and is owned by the core. The 60 Hz host accumulator,
  four-tick catch-up cap, and suspension baseline reset in the plan are not yet
  implemented.
- **Snapshots:** publish immutable, revisioned state only after completed ticks.
  The current tick is the revision for the placeholder snapshot. Future world
  snapshots must permit a full initial sync, describe removals, and recover
  correctly if revisions are skipped; a delta requires a matching base or a
  full resync. Snapshot storage and any upload buffers must remain valid until
  GPU work completes. Buffer ownership and the concrete API are unresolved.
- **Renderer lifecycle:** the Apple host owns the Metal device, view, renderer,
  and display callbacks. Rendering accepts a completed snapshot and handles
  resize and resource loss without mutating the world or advancing ticks.
  Report unrecoverable resource errors; absence of a drawable is a transient
  skipped frame. Threading, synchronization, and recovery need tests when added.
- **Input mapping:** platform hosts translate keyboard/mouse or touch into the
  same ordered, tick-indexed gameplay commands. Device events and coordinates
  stay outside the core. Bindings, touch gestures, cancellation on interruption,
  and invalid-input handling are not yet defined.
