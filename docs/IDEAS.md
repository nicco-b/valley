# Ideas Backlog — maximum immersion

*Brainstormed 2026-07-01. Not commitments — a drawer to pull from. Each entry:
the idea, the reference, rough effort, and what it rides on. Signature-candidate
ideas marked ★.*

## Sound (our unfair advantage)

- ★ **The player is a field recordist.** An in-world recorder as a core verb:
  capture soundscapes (dawn at the pond, wind in an arch, a bloom's hum) into
  a journal — quest structure, lore delivery (recordings of vanished things),
  and a mechanical reason to sit still in beautiful places. Effort: medium.
  Rides on: interaction layer, audio design. Nobody has done this properly.
- **Audio-visual wind coupling:** one wind value drives sway shader amplitude
  AND wind-bed volume. Effort: tiny. Rides on: weather system.
- **Reverb zones from real impulse responses** (record real canyons!),
  occlusion, distance low-pass. Effort: small-medium (Godot audio buses).
- **Diegetic music only:** no soundtrack; humming NPCs, wind-chimes at
  shrines, rare earned music moments (Death Stranding). Effort: content-side.
- **Footstep material system:** per-surface sounds (sand/stone/water/plants),
  ties into material states (wet/dry). Effort: small.

## A world that remembers (simulation pillar extensions)

- ★ **Worn paths emerge:** long-memory interaction field — repeated walking
  (player + NPCs) slowly wears visible trails. Desire paths across the valley.
  Effort: medium. Rides on: interaction field.
- **Weather memory:** puddles that dry over hours, damp sand, snow lingering
  in shade. Effort: small once material states exist.
- **Celestial clockwork:** moons + red sun on slow cycles; rare conjunctions/
  eclipses NPCs stop to watch. Ties to axioms + calendar. Effort: small-medium.
- **Campfire remains, placed-object permanence** (already have records) —
  the player's own traces persist.

## People — presence over systems

- **Familiarity greetings:** stranger → regular → friend from an encounter
  counter in WorldState. Effort: tiny. Payoff: huge warmth.
- ★ **Fires are social gravity:** NPCs converge on fires at night; the sit
  verb works *beside them* (RDR2 camp feel). Sitting becomes social.
  Effort: small on top of needs-AI.
- **Contextual idles:** shading eyes at low sun, hugging self in cold,
  watching things that fly over. Effort: animation content, incremental.

## Interface — immersion by removal

- ★ **No compass, no quest markers** (the Morrowind option): navigation by
  landmarks, the map, and spoken directions in dialogue ("past the twin
  palms, left at the pink pool"). Geography knowledge = progression. Effort:
  negative code, high writing discipline. Decide before quest content exists.
- **Diegetic fast travel or none:** if it exists, it's a creature/caravan at
  fixed points (silt-strider answer), never menu teleport. Decide with world
  size.
- **HUD approaches zero:** everything fades when unused (sit already does
  this — generalize).
- **Photo mode early:** the screenshot tool doubles as her composition/
  reference tool and free marketing in her style.

## Body

- **Character shows the world:** dust after wind, wet after wading, fire
  glow. Material states applied to the character. Effort: small per state
  once the systems exist.
- **Gentle comfort loop, NOT survival:** cold nights make fires feel good
  (warmth shimmer, contented idle); no hunger bars, no death timers. RDR2
  camp-feel, not homework. Effort: small, mostly feel work.
- **Traversal character:** slope scrambling, sand-slides on dunes (Journey),
  tools opening terrain (already planned as exploration keys).

## Later / bigger

- **Seasonal drift:** not four hard seasons — slow bloom-cycles and light
  changes across many game-days (ties to flora lifecycle sim).
- **Wildlife with daily lives:** drink at dawn, shade at noon, herds that
  remember being hunted (needs-AI reuse on creatures).
- **One live music performance in the world somewhere, once a day, findable.**
