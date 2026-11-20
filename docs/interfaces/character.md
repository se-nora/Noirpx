# Character

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

### Character physics

- Reuses `FixtureCharacter` exactly: 5 × 9 body, quarter-cell vertical units,
  max step height 3, gravity and bounded fall speed, jump only while grounded,
  step-up when blocked horizontally.
- Character advances *after* each material tick using that tick's snapshot.
- Hazards (lava, acid, fire, magicLiquid) are detected by the test harness
  but do not affect cave character outcome in this increment (accepted gap).

### Levitation energy

- `FixtureCharacter.maxLevitationEnergy = 180` (integer ticks, 3 seconds at 60 Hz).
- `levitationEnergy: Int` (0…max), initialized to full energy.
- **Drain**: 1 energy/tick while `heldJump && !grounded && energy > 0 && post-gravity verticalVelocity <= levitationClimbCap`. Applies upward impulse
  of +2 quarter-cells after gravity (−1) → net +1 quarter-cell/tick climb, capped at 1
  quarter-cell/tick (`levitationClimbCap`). Ceiling collision clamps vertical velocity
  to ≤0; energy continues draining while held at ceiling.
- **Recharge**: 2 energy/tick while `grounded && energy < max`.
- Zero energy produces no upward force; normal gravity applies.
- `levitationEnergy` resets to full on new character creation (no cross-session persistence).
