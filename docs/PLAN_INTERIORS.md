# Plan — interiors (the heightfield question)

*Planning doc, 2026-07-08. The gate named by Strata's
PLAN_CREATION_LIBRARY §4b / rung L11 (kit-bashing): Nicco wants to
build dungeons visually from kit pieces, Creation-Kit style; the
`arch/under/*` and `arch/ruins/*` card slots are the seeds; placement
v2 with stable ids just landed; gizmos/snapping is queued. The blocker
as stated: valley's world is a heightfield — no overhangs, no caves by
construction. The Creation Kit answers with separate interior cells
behind load doors. This doc settles OUR answer.*

*Method: read-deep against the landed code (terrain.gd, world_streamer,
cell_records, the save manager, player swim, the soak) plus the standing
decisions (DESIGN "World Architecture", IDEAS "The underworld",
DECISIONS 2026-07-04). Cheap probes only, all listed in §9; no code on
this branch beyond the doc. Laws respected throughout: one source of
truth per domain; everything is a record; the sim contract (one 1:1
clock, catch-up through `advance_hours`); the soak fingerprint moves
for nobody; zero engine-fork patches.*

---

## 0 · Executive summary

**The recommendation is the hybrid, and most of it is already decided
or already possible.** Three registers, three different answers:

1. **Surface overhangs and grottos — possible TODAY, no holes needed.**
   The heightfield constraint binds *terrain*, not placed meshes. Every
   placed kit piece is an ordinary body with its own `-col` collision
   (probed: cell collision is a per-cell trimesh from our own mesh
   builder, and placed GLBs collide independently of it). An arch you
   can walk under, a grotto mouth against a cliff, a leaning slab you
   can shelter beneath — placement v2 places them now. Kit-bashing a
   *ruin* on the surface is not gated on anything in this doc.

2. **Built interiors — the Creation Kit answer, minus the load screen:
   the Threshold.** A door placement leads to a small kit-bashed
   interior. But not a separate scene behind a loading moment: the
   interior instantiates as a **pocket in the same running world**,
   hovering at a fixed altitude above its own door, entered through a
   fade. Every autoload keeps ticking (they never noticed), streaming
   stays warm at the door's cell (stepping back out is instant), the
   1:1 clock holds — you come out and the world has moved on, which is
   the game's soul, kept. Interior placements are records shaped
   exactly like cell records, one file per interior, so the Toolkit
   hand and Strata's records browser both ride free. DESIGN.md already
   blessed this door: *"complex interiors may use door transitions if
   ever needed. Let the game teach us."* The game has now taught us.

3. **Seamless caves — the underworld layer, already decided, not this
   plan's to build.** IDEAS "The underworld" (2026-07-04, ★★) settled
   caves as **layered heightfields** — a second floor+ceiling terrain
   layer streamed like the surface, voxels explicitly rejected —
   implemented WITH the F3 region-tile work (`layer` is already baked
   into every region record). Punch-through holes in the surface
   heightfield are needed exactly once, as *cave mouths for that
   layer*; §2 prices why building one-off hole tech per cave now would
   be the expensive way to get the cheap thing.

**Fork question, answered explicitly: zero fork patches.** Everything
here is GDScript, records, and (deferred, for the underworld) our own
GDExtension kernel — which is our library, not an engine fork. No
engine work anywhere in this plan.

---

## 1 · What the heightfield actually forbids (the probe)

The blocker deserves precision, because half of it is imaginary:

- `Terrain.height(x, z)` is single-valued — the *terrain* cannot fold
  over itself. That forbids terrain-shaped overhangs and any space
  *below the ground function*. It forbids nothing about placed meshes.
- **Collision is not a heightfield.** Probed: cells build an
  `ArrayMesh` and call `create_trimesh_shape()`
  (world_streamer.gd `_build_terrain_mesh`); `HeightMapShape3D` is not
  in play anywhere. So "does Godot support heightfield collision
  holes?" is the wrong question for us — holes would be our own mesh
  builder's business (skip the masked triangles). For the record:
  upstream Godot 4.7 exposes no hole support on `HeightMapShape3D`
  (the proposal has been open for years; Jolt's native heightfield has
  a no-collision sentinel Godot doesn't surface) — irrelevant to us
  either way.
- The mesh builder is **two implementations under a bit-parity test**:
  the native kernel's `build_cell` (C++, macOS) and the GDScript
  fallback (`tests/kernel_parity.gd` pins them together). Any hole
  mask must land in both, twice-tested. This is the real recurring tax
  on option 2 below.
- Everything downstream samples `height()` and assumes ground exists:
  five scatter passes (flora, model, decal, water-plant, cover), the
  forage spots, navmesh face emission, the far-LOD quadtree, `seat_y`.
  A hole is a lie to all of them until each learns the mask.

---

## 2 · The options, priced

| | option | what it buys | the honest bill |
|---|---|---|---|
| **A** | **Interior pockets behind doors** (the Threshold, §3) | Full CK-style kit-bashing in enclosed spaces; zero terrain interaction; every interior is pure content after the first rung | One autoload + one record kind + presentation gates: **M once**, then interiors are data. Costs seamlessness at the door — a fade, not a load (the pocket needs no scene change, no streaming, no import) |
| **B** | **Punch-through caves**: hole in the heightfield + cave-kit cap | A seamless walk-in cave in the open world | Hole mask in BOTH mesh builders + parity test (M); navmesh mask (S — the wet-face skip pattern in `_build_terrain_mesh` already does per-face exclusion, reusable); five scatter passes + forage + decals learn the mask (S–M, fiddly); far LOD draws ground over the mouth at distance (acceptable — fade covers it); **water is the trap**: `water_surface()` is a radius/guard test, not a mesh — a hole below a lake surface or below sea level reports water above the cave, so swimming, the strand shader, and the sea sheets all flood it; per-hole occlusion volumes are new machinery (M). Streaming the cave's contents, lighting the void, hiding the ~2.7m jagged mesh edge under a collar piece (the `arch/under/sinkhole_rim` card already anticipates exactly this). **Sum: M–L for the FIRST cave**, before the cave itself is any fun — and none of it reusable for built interiors |
| **C** | **The underworld layer** (IDEAS 2026-07-04) | The vast cavern with its own micro-biome, hydrology seepage, skylights on the real sun — the signature seamless underground | Already scheduled WITH F3 region tiles (`layer` is in the schema today). Its cave mouths need option B's hole tech **once, at the mouths only** — built then, amortized over the whole layer instead of per-cave |

**Ruling: A now, C later as already planned, B never as a standalone.**
Option B's entire bill buys one cave; option A's bill buys every
interior forever; option C makes B's one honest use-case (mouths)
someone else's amortized line item. And the soak guard makes B
permanently nervous: holes must never touch `height()` or the
fingerprint moves — a constraint A simply cannot violate, because the
pocket never samples terrain at all.

---

## 3 · Decision: the Threshold (doors, pockets, and interior records)

*New system name (DECISIONS: christen freely): **the Threshold** —
doors, interior pockets, and the records that furnish them.*

**The door is a placement row that learned one key.** Probed:
`CellRecords.validate` checks only `kit/x/y/z/yaw`, and
add/insert/update/save carry unknown keys verbatim — so a door is an
ordinary placed object whose record gains:

```json
{ "id": "p18c…", "kit": "arch/village/door_arch_01.glb",
  "x": …, "y": …, "z": …, "yaw": …, "ground_dy": …,
  "door": { "interior": "smugglers_cellar" } }
```

The streamer, on instancing a record with a `door` key, attaches an
`Interactable` (the F1.3 layer, shipped) with prompt "Enter". No new
record file for doors, no schema migration, no legacy breakage.

**The interior is a record file**: `data/interiors/<id>.json` —

```json
{ "id": "smugglers_cellar", "name": "…",
  "light": "dark_warm", "ambience": "drips",
  "placements": [ { "id": "p…", "kit": "arch/ruins/broken_wall_02.glb",
                    "x": …, "y": …, "z": …, "yaw": …, "scale": … }, … ] }
```

Placements are **the CellRecords row shape verbatim** (stable ids and
all), with two deliberate differences: coordinates are local to the
pocket origin, and `y` is absolute — no `ground_dy`, no `seat_y`,
because there is no terrain to seat on; the interior's own floor
pieces are the ground. Same shape means the Toolkit's select/move/
rotate/undo machinery and Strata's records browser both apply with
minimal ceremony (§5, §6).

**The pocket, not a scene change.** Entering instantiates the interior
at the door's own XZ, at a fixed altitude (**POCKET_ALT ≈ +1500m** —
above any tile's `height_max`, above the ranges' 320m, above every
water surface), and fades the player there. Why this shape wins:

- **The sim never pauses and never forks.** Every system is an
  autoload; nothing is scene-local. GameClock, Weather, Climate,
  Hydrology, FloraLife, the wildlife — all keep ticking because nobody
  told them anything. The 1:1 law ("morning exists only in the
  morning") holds inside: sit in a cellar an hour, come out to a
  different sky. This is the sim-soul answer the CK's frozen exterior
  cells never had.
- **Streaming stays warm.** The streamer keys on the focus XZ; at the
  door's XZ the door's cells stay loaded, so stepping out is a fade,
  not a rebuild. No cell churn on enter or exit.
- **No false water.** Probed: swimming requires
  `global_position.y < water_surface + 0.2` (player.gd) — at +1500m
  the pocket is above every surface, so submersion, the underwater
  bus, and the strand logic need no gate at all.
- **One interior at a time.** Instantiate on enter, free on exit
  (single player; the pocket is never persistent scenery). Two
  interiors can therefore never collide at altitude, whatever their
  doors' spacing.
- **Presentation gates, not sim gates.** An `Interiors.inside` flag;
  readers: weather FX (rain/snow particles off), ambience (wind bed
  ducked, the interior's own bed in), sky/fog swap to the interior's
  `light` preset, HUD compass if/when one exists. Weather itself is
  never told — you *hear* the storm gated, and it is still rightly
  raining when you step out.
- **Light**: the interior brings its own small rig (the `light`
  header); the sun stays outside by enclosure + cull layer if the
  probe in I1 shows leakage. Detail owned by I1, not this doc.
- **Save**: the save carries `player {x, z}` today and re-seats on
  `Terrain.height` at load. Version bump: an optional
  `player.interior` + local position; restore routes through the
  Threshold (spawn inside, or honest fallback to the door if the
  interior record is gone).
- **Exit** is a door placement *inside* the interior record with
  `"door": {"exit": true}` — same mechanism pointing home.

**What the Threshold is NOT:** not the underworld (caverns are terrain,
these are rooms); not a second world grid (interiors don't stream,
they instantiate whole — they are small by definition; a "vast"
interior is the underworld's job); not hand-built `.tscn` scenes
(records stay the truth — the filesystem law).

---

## 4 · Decision: the hand inside

**The same hand.** The Toolkit's place/select/move/rotate/scale/undo
loop targets the interior's records when `Interiors.inside`: the
Chronicle grows a second book — `InteriorRecords`, same verbs as
CellRecords (`add/record/find_at/update/remove/insert/flush`), keyed
by interior id instead of cell, writing `data/interiors/<id>.json`
atomically (the temp+rename pattern, inherited). The Toolkit asks "the
active book" instead of CellRecords directly — a one-seam change,
priced into I2.

- **Palette unchanged**: the same cards, the same `Kit.scene_for`;
  `arch/under/*` and `arch/ruins/*` drop their `gated` flag as they
  become reachable content.
- **Placement differences inside**: no `ground_dy` (place seats on the
  raycast hit — the `-col` hulls of already-placed pieces ARE the
  floor); snap-to-ground means snap-to-hit. `seat_y` never consulted.
- **Camera**: the fly camera works unchanged in a room (it's free
  flight); the third-person rig in tight rooms is a known genre
  problem — I1 ships with the existing rig and a note; a spring-arm
  clamp is a polish line, not a gate.
- **Sockets and snapping (L11 proper)** ride audit R4's gizmos and the
  card-metadata work in Strata's plan — this doc only guarantees them
  a terrain-free room where pieces can click. Nothing here blocks or
  presupposes the socket schema.

---

## 5 · What Strata sees

- **Records browser: interiors arrive free.** `data/interiors/*.json`
  is a new record kind through the records-as-data door — the browser
  that already reads 330 records / 13 kinds lists it with zero Strata
  changes (I4 is the *verification*, not a build). The `validate` verb
  (Strata plan L6) covers it the day InteriorRecords is its loader.
- **Interiors never enter the bake.** No terrain interaction means no
  bless, no diff report, no soak presence — Strata's geology pipeline
  does not know interiors exist, correctly.
- **A kit-bash VIEW of an interior in Strata** (orbit an interior's
  records in the pane, edit placements from the desk) is a later rung
  of L11's Strata half, riding the live-pane machinery — out of scope
  here; the record shape chosen in §3 is what makes it possible later.

## 6 · Sim, weather, and soak stances (the guard rails)

- **The soak digest must not move — and cannot.** Interiors are
  placement data plus a runtime pocket: nothing writes `height()`, the
  hydrology grid, the climate fields, or WorldState canon. Door and
  interior records are never fingerprinted (the cell-records precedent:
  presentation/content, not sim state). Standing order restated from
  the Toolkit plan: if any rung of this plan moves the soak
  fingerprint, something is wrong; stop and investigate.
- **Weather/time inside**: ticking, ungated, unfaked (§3). The only
  gates are presentational and all read one flag.
- **The underworld inherits cleanly**: when the layer lands (with F3),
  its caverns are *terrain* with the full sim stack; built interiors
  remain rooms behind doors — the two coexist, and a cellar can one
  day open into a cavern by putting a door where the mouth is.

## 7 · The fence — what NOT to build

- **No load screens, no scene swaps.** The pocket is the transition
  tech; the fade is the whole ceremony.
- **No per-interior `.tscn`.** Records are the truth; the host builds
  from JSON. (Authored one-off *pieces* stay cards, as ever.)
- **No voxels, no SDF terrain** — re-affirming IDEAS' rejection;
  nothing in this plan re-opens it.
- **No one-off hole punching.** Option B is declined standalone; hole
  tech arrives once, as underworld mouths, with F3.
- **No interior-forked sim.** One clock, one weather, one WorldState.
  An interior that needs "its own time" is a design smell, not a
  feature request.
- **No streaming interiors.** An interior too big to instantiate whole
  is the underworld's job description.

## 8 · The milestone ladder (agent-sized; S ≤ 2 days, M ≈ a week)

| # | rung | size | done means |
|---|---|---|---|
| **I1** | **The Threshold v1**: `Interiors` autoload + pocket host (build from `data/interiors/<id>.json`), `door` key on placements → Interactable "Enter", exit door, fades, presentation gates (weather FX / ambience / sky), save version bump with honest fallback, light-leak probe | M | Place a door against a ruin, press E, stand in a kit-bashed cellar; wait; step out into a later, changed sky. Soak fingerprint identical before/after |
| **I2** | **The hand inside**: `InteriorRecords` (the Chronicle's second book, CellRecords' verbs, atomic writes), Toolkit targets the active book, undo mementos work inside, palette ungates `under/*`/`ruins/*` | S–M | Kit-bash a room in-game from ruins + under pieces without leaving the pocket; Z walks it back; the JSON on disk is the room |
| **I3** | **Interior air**: header fields (`light`, `ambience`) drive a real light rig + an ambience bed through the gates; the six-file audio reality means one bed is enough to prove it | S | Two interiors *feel* different for data-only reasons |
| **I4** | **Strata sees it** (verification rung, Strata side): interiors listed in the records browser + notes sidecar; confirm zero Strata code was needed; file the kit-bash-view idea against L11's Strata half | S | The browser shows `smugglers_cellar` beside the cell records; a note sticks to a placement inside it |

Sequencing: I1 → I2 strictly; I3/I4 ride behind in any order. **L11
unblocks at I2**: sockets/snapping (R4 gizmos + card metadata) then
have both of their venues — surface ruins (available since placement
v2) and interiors (available at I2) — and the "heightfield spike"
gate named in Strata's plan §4b is answered by this doc.

The underworld layer is deliberately NOT a rung here: it belongs to
F3's schedule (IDEAS "The underworld" is its charter), and this plan's
only obligation to it is negative — build nothing that fights it. Met.

## 9 · Probe log (what was actually checked, 2026-07-08)

- `world_streamer.gd _build_terrain_mesh`: collision =
  `create_trimesh_shape()` on the cell ArrayMesh; `HeightMapShape3D`
  unused anywhere. Navmesh already does per-face exclusion (wet flags).
- Native kernel `build_cell` + GDScript fallback under
  `tests/kernel_parity.gd` — the dual-implementation tax on any hole.
- `cell_records.gd`: `validate` requires only kit/x/y/z/yaw; unknown
  keys ride through add/insert/update/_save verbatim → the `door` key
  needs no migration. Stable ids landed (placement v2).
- `player.gd` swim: `y < water_surface + 0.2` gate → a +1500m pocket
  needs no submersion special-case.
- `save_manager.gd`: v1 carries `player {x,z}` only, re-seats on
  `Terrain.height` — interiors need the version bump named in I1.
- `terrain.gd`: `water_surface()` is radius/guard math, not geometry —
  the flood trap that prices option B's water line.
- `assets/models/arch/under/*` (5 slots, incl. `sinkhole_rim`) and
  `arch/ruins/*` (4 slots) exist as gated placeholder-synth cards with
  `-col` hulls — the kit seeds are real.
- DESIGN.md "World Architecture": door transitions for complex
  interiors pre-blessed. IDEAS "The underworld": layered heightfields
  decided ★★, voxels rejected, `layer` already in region records.
