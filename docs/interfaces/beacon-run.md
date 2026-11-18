# Beacon Run

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
action and brush buttons (4 run/info + 1 erase + up to 15 discovered drawable = 20 max) can be scrolled fully into view at these sizes,
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
on the player's top visible row and a bell icon above it are drawn in the warden's
current warning/danger/recovery color, so the opaque player cannot hide the
encounter phase; the rest of the player retains its protection color. The bell's
upper row includes two phase-colored pixels that remain visible even if the
lower icon and entire phase bar are covered by hazards, provided that row is
within the viewport. A win or failure freezes ticks and ignores paint until
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

The character starts with three health. Fire cells and burning oil damage when
they overlap the 5 × 9 body. Burning pitch damages on overlap or when it shares
a horizontal or vertical cell edge with the body; corner-only contact is safe.
This additional pitch boundary makes the blocking material dangerous without
requiring penetration. Nonburning hot pitch or oil and ordinary water are safe.
After commands, all material movement and reactions, and character movement,
only the final cell positions and burning flags are sampled, including in frozen
chunks; intermediate crossings, cells quenched, removed or burned out that
tick do not damage. Out-of-world cells are ignored. Newly ignited material
can hurt immediately. Overlapping fire and burning oil or pitch, and every
edge-adjacent burning pitch cell, receive black or white marks at their exact
cells. Every boundary mark chooses black or white to maximize its minimum
contrast against visible, unmarked orthogonal neighbors; fully surrounded
interior marks use a world-anchored checkerboard. A one-cell-wide region can
therefore be a solid contrasting band. A single pixel cannot achieve high
contrast against both black and white neighbors simultaneously; the choice is
the best of the two colors, not a 4.5:1 guarantee for every boundary.
This replaces the pitch's orange only at contact.
Cold or merely hot fuel has no mark. The HUD identifies the last hit while the shield is active;
Help explains the contact rules. Display callbacks can still skip hazard states.

Fire, hot vent or threatening warden contact deals one damage immediately
when the global protection timer is zero, setting it to 30 ticks. Simultaneous
contacts produce only one hit, identified in priority order fire, vent, warden.
The timer decrements
on each subsequent playing tick, including outside the vent or while cooled;
contact can damage again on the tick it reaches zero. A pink character and the
HUD show the remaining protection; health does not regenerate. Zero health
ends the run as `exhausted`. Restart restores all health and timers and clears
the last-hit source.
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
