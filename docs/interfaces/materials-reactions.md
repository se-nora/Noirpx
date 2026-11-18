# Materials and reactions

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

## Enemy material reactions

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

## Burning terrain spread

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

### Digest and rules version
- `SimulationSnapshot.digestVersion` bumped from 6 to 7.
- `SaveCodec.rulesVersion` bumped from 4 to 5.
- Replay/save compatibility changes: removing charring eliminates solid->pitch
  writes from fire and burning flammables, so old digests and old saves are not
  compatible.
