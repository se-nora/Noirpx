# Simulation and host interface contracts

The milestone 1 choices below are a **provisional, single-owner prototype**.
They have not been reviewed by separate core and renderer contributors. That
review remains open; the project owner authorized a single-owner implementation
of the separate [resident-world direction](docs/interfaces/resident-mode.md). Do not treat either interface as
independently reviewed, particularly full-snapshot cost and GPU buffer ownership.

This file is an index. Each contract lives in one subsystem document under
`docs/interfaces/`:

- [Core grid and commands](docs/interfaces/core-grid-commands.md) - world
  coordinates, chunk storage, materials, command ordering, and tick rules.
- [Materials and reactions](docs/interfaces/materials-reactions.md) - material
  identifiers 8-15, enemy material reactions, and burning terrain spread.
- [Resident mode](docs/interfaces/resident-mode.md) - opt-in resident-world
  simulation mode and its scheduling rules.
- [Snapshots and digest](docs/interfaces/snapshots-digest.md) - immutable
  snapshots, thermal sidecars, and the FNV-1a digest.
- [Save format](docs/interfaces/save-format.md) - persistence format, wire
  layout, validation limits, and compatibility policy.
- [Cave world and Cave Run](docs/interfaces/cave-world-and-cave-run.md) - cave
  world generation and the deterministic Cave Run session.
- [Character](docs/interfaces/character.md) - `FixtureCharacter` physics shared
  by Beacon Run and Cave Run.
- [Beacon Run](docs/interfaces/beacon-run.md) - course generation, heat vent,
  damage, Chime Warden, and Silt Pulse.
- [Spells and crafting](docs/interfaces/spells-crafting.md) - spell/wand
  crafting system, recipes, and cast resolution.
- [Host and input](docs/interfaces/host-and-input.md) - host timing, renderer,
  camera, brush, and input mapping.
- [HUD](docs/interfaces/hud.md) - overlay layout, outcome UI, and material
  discovery.

Rules that span subsystems are stated in the document that owns them. The
original single-file chronological order is not preserved.
