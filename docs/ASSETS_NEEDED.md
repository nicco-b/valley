# Assets Needed — the human list

*Everything the game is waiting on from people rather than code, specified
so it can be made without asking questions. Ordered by visual/experiential
impact within each section. Specs referenced from [ART_BIBLE.md](ART_BIBLE.md).*

*Two views: the **priority tables** (what to make next) and the
**master ledger** at the bottom (everything the finished game wants —
for planning batches of engine-independent work). Every entry lands by
dropping a file into a named slot; nothing here blocks code, because
every slot renders a labeled placeholder until filled.*

## Paintings (her) — export: transparent PNG → `assets/paintings/`

| Priority | Asset | Spec | What it fixes / unlocks |
|---|---|---|---|
| ★★★ | **Ground cover kit** — grass tufts, small stones, tiny succulents, 4–6 elements | ~400–800px tall each, transparent PNG | The single biggest "looks bad" fix after rocks: the ground is currently empty between trees. Wired as high-density low-height scatter (thousands of instances, Elden Ring grass layer) |
| ★★★ | **Rock family** — 3–4 painted rocks/boulders, varied silhouettes | ~800–1500px | Retires the gray boxes *as billboards* until Blender versions exist; enters scatter + kit |
| ★★ | **Silly-tree variants** — 2 more poses of the arch tree, 1–2 more shrub + palm variants | match existing (~1200×1500) | Kills repetition in the current scatter |
| ★★ | **Sky gradient strips** — dawn / day / dusk / night, vertical gradients | ~256×1024 PNG each | Replaces code-picked sky colors with painted skies (her skies, literally) |
| ★ | **Distant mountain cutouts** — 2–3 striped mountain silhouettes | ~2000px wide | The far-horizon layer beyond the valley rim |
| ★ | Biome #2 first elements — whatever the second land wants to be | any | Starts the palette-swap proof |

## Audio (you) — export: seamless-loop WAV → `assets/audio/`, swap via `reimport.sh`

| Priority | Asset | Spec | Replaces |
|---|---|---|---|
| ★★★ | **Real wind bed** | 60s+ seamless stereo loop, low dynamic | The synthesized placeholder everyone hears constantly |
| ★★★ | **Night bed** | 60s+ loop: real night air/insects | The fake synth crickets (currently the weakest thing in the game) |
| ★★ | **Footsteps: sand** ×4–6 variants | short one-shots | Silence underfoot (needs a small footstep system — code is ready to add when sounds exist) |
| ★★ | **Water lap / pond ambience** | 30s+ loop | Positional emitter at the pond |
| ★ | Storm wind layer | 60s loop, aggressive | Weather crossfades it in at high wind |
| ★ | Footsteps: stone ×4 | one-shots | Shrine platform, future ruins |

## Blender (you — the learning track) — export: glTF → `assets/models/`

| Priority | Asset | Spec (FOUNDATIONS F4 conventions) | What it fixes |
|---|---|---|---|
| ★★★ | **Rock family** — 4–5 low-poly rocks/boulders | few hundred tris each, flat palette colors, `-col` collision mesh | **The #1 visual offender.** Boxes → sculptural silhouettes changes every screenshot. Ideal first Blender project: no rig, no UV precision, imperfection is on-style |
| ★★ | **Mesa / large formation** ×1–2 | ~1–2k tris | The valley's landmarks stop being crates |
| ★★ | **First character** (from her turnaround) | low-poly, rigged, clips: Idle/Walk/Run/SitDown/SitIdle/StandUp | Retires the robot; starts the whole character pipeline |
| ★ | Shrine rebuild | modular pieces | First architecture-kit exercise |

## Canon / writing (both — the kitchen-table track)

| Priority | Item | Unlocks |
|---|---|---|
| ★★★ | **World-axioms** (docs/lore/axioms.md is waiting) | All writing: dialogue, item text, place names, the glow's rules |
| ★★★ | **The glow's name + fiction** | Shrine text, magic-language, VFX design intent |
| ★★ | **The Wanderer's identity** | First real dialogue when the system lands |
| ★★ | **Decision: field-recordist player?** (IDEAS.md ★) | Shapes core verbs + what audio assets become gameplay |
| ★★ | **Decision: no-compass Morrowind navigation?** | Must precede quest/dialogue writing style |
| ★ | Naming language + first place names | The map's labels, the lore bible's spine |

## Scale discipline (2026-07-05 — read before the biome build-out)

**Ambition update (same day, Nicco's call): the discipline rules are
MULTIPLIERS, not caps.** The ledger below is the full-treatment
target — Skyrim-adjacent art volume, no compromise on density — and
the rules are what make that affordable for two people: paint a
species once and the sim recolors it through four seasons; sculpt
one rock and the placement rules scatter it believably across
kilometers. Discipline buys ambition; it doesn't ration it.

The raw combinatorics still need managing: 8 biomes × ~8 flora
species × 4 lifecycle stages × seasonal states is 1,000+ paintings
if every cell is hand-made. The mitigations, in force from now on:

- **2–3 signature species per biome + one shared filler set.** A
  biome's identity is its signature silhouettes; filler repeats
  everywhere and nobody notices.
- **Stages and seasons via shader, not repaint.** `flora_vitality`
  straw-drying already proves it; the stage-B biome palette tint is
  the same lever. Paint a species once; the sim recolors it.
- **Kits, not pieces** (rocks/cliffs/architecture — already canon).
- **One shared creature clip taxonomy** (Idle/Walk/Run/Drink/Rest/
  Alert/Flee + one special per species) so every new species drops
  into AgentSim's activity→clip mapping with zero code. ~8–15
  species is a full-feeling valley.
- **Icons rendered from a Blender turntable rig** — never paint an
  item twice.

Code will meet the art halfway (Toolkit-shaped, build as needed):
species records name their art slots (drop a file, never touch
code — mostly true already); a derived asset manifest (walk the
records, report filled vs. placeholder — this document's tables
become a generated report); a hot-reloading lineup scene (every
species × stage × biome light, so a new painting is judged
in-context in seconds); Blender export validation in test.sh
(clip names, +Z facing, `-col` meshes — fail at import, not in-game).

## The asset contract (2026-07-05 — rules & permissions; read first)

**The world generates itself from the assets' own rules.** Every
scatterable asset is two things: the files (mesh / billboard /
texture / clips) and a **record card** — a JSON sidecar carrying its
placement rules and permissions. The engine's generator reads the
cards and populates the world; nothing is hand-placed except
landmarks and villages. The flora species records
(`data/flora/*.json`) already prove the pattern (biome weights,
moisture needs, stage art slots, forage yields); the same schema
extends to every class. A card looks like:

```json
{
	"id": "juniper_gnarled",
	"class": "tree",
	"trunk": "trees/juniper_gnarled.glb",
	"foliage": "trees/juniper_cards.png",
	"variants": 3,
	"biomes": {"scrub": 0.4, "oasis_green": 0.15},
	"permissions": {"slope_max": 28, "alt": [2, 260],
		"moisture_min": 0.15, "water_dist_min": 2.0, "spacing": 4.0},
	"cluster": {"radius": 16, "count": [3, 9]},
	"collider": "trunk", "wind": 0.6, "yields": null
}
```

**Why this matters for production: assets are engine-independent.**
You produce the model/painting/clips and fill in the card; the engine
inherits both whenever the corresponding slot-loader lands. Nothing
you make waits on code, and nothing needs re-export when the engine
grows. Engine work this implies (queued, the Loom/Elements — none of
it blocks production): the species schema grows `permissions` +
`cluster` + `variants`; a `mesh`/`trunk` slot beside the billboard
slot (hybrid flora rendering: modeled trunk + camera-facing painted
leaf cards near, auto-generated impostor billboard far — the engine
renders impostors from the asset, no extra art); rock/prop scatter
records on the same schema (`data/scatter/*.json`).

**Production conventions (start today):** glTF → `assets/models/<class>/`,
low-poly, flat palette colors or painted texture per ART_BIBLE, `-col`
collision meshes, +Z facing, ×1 scale, clips named per the shared
taxonomy below. Paintings/cards: transparent PNG → `assets/paintings/`.
Textures: tiling PNG, power-of-two, → `assets/textures/`. One asset =
one card, committed together.

## The master ledger (2026-07-05, rev 2 — the full treatment)

*Everything the finished game wants from human hands, at the no-
compromise density target (rev 1's "minimum painterly world" was
retired same-day on Nicco's call — "Skyrim surely has more than
that", and it does: its believability is a library dozens deep per
category, nested in scale from cliff to pebble). Grouped by tool so
work batches away from the engine. Horizons: **[now]** the slot
exists or the contract is defined today · **[village]** M4 ·
**[under]** the underworld layer · **[later]** gated on a decision ·
**[rolling]** grows with each species. Totals + honest pacing at the
bottom.*

### Flora — the full treatment (hybrid: modeled trunks + painted cards)

*Trees stop being single billboards: each species is a low-poly
trunk/branch mesh + painted leaf-card texture (near), an impostor
(far, auto-generated). Billboards remain the right tool for the small
stratum — grass, flowers, ground succulents.*

| Class | Count target | Per-asset pieces |
|---|---|---|
| Tree species [now] | 10–14 species × 2–3 growth/age variants ≈ **30–40 tree assets** | trunk mesh · leaf-card sheet · bare/dead variant · card |
| Shrubs & bushes [now] | **12–16** | small mesh or billboard (judgment call per species) · card |
| Ground-cover billboards [now] | **25–35** — grasses ×8–10, flowers ×6–8, ferns, succulents, reeds, kelp, driftwood tufts | painted PNG · card |
| Underworld flora [under] | **6–10** glow-adjacent species | gated on the glow's fiction |

Per-biome signature allocation (2–3 signatures each + shared filler)
still governs *which* species: oasis (arch tree ✅ · high palm ✅ ·
bloom tuft), scrub (low shrub ✅ · dry tuft ⚠SVG · thorny), dune_desert
(cactus · ribbed succulent — still the zero-real-art biome), wetland
(reeds · broad-leaf), strand (beach grass · driftwood), volcanic
(lichen · pioneer), peaks/sea free. *(Code today: 7 species records
wired — the above plus `pebbles`, which is the shared-filler slot,
not a signature; audit 2026-07-06.)*

### Rock & stone — the library (Skyrim's real lesson: nested scale)

| Class | Count target | Notes |
|---|---|---|
| Boulder library [now] | **15–20** across 4 biome families: valley granite, volcanic, coastal wave-worn, desert sandstone | the first 4–5 stay the first Blender batch (top table) — the library grows from it |
| Cliff/plateau kit [now] | **20–30** slabs: rim, face, overhang, slide wall, talus, cave mouth | terrain, not decoration; breaks the heightfield ceiling |
| Scree & pebble clusters [now] | **8–10** scatter clumps | the between-scale that sells the big pieces |
| Landmark formations [now→later] | **8–12** heroes: arches, sea stacks, spires, hoodoos, the gate strait pillars | one per region identity |
| Underworld stone [under] | **10–15**: stalactites, columns, crystal clusters, sinkhole rims | |

### Textures & materials (new class — painted, tiling, engine-agnostic)

| Set | Count target | Notes |
|---|---|---|
| Ground tiles per biome [now] | **12–16**: sand, ripple sand, soil, grass mat, volcanic ash, scree, snow, mud, wet strand… | the terrain shader tints toward biome albedo today; painted tiles are its upgrade slot |
| Material sheets [now] | **10–15**: bark ×3–4, rock faces ×3–4, thatch, plaster, timber, woven | feed trunks, kits, architecture |
| Detail decals [later] | **8–12**: cracks, lichen, moss, tide stains | |
| Leaf-card sheets | counted with trees | |

### Characters, creatures & the animation library

*The clip taxonomy is the multiplier: one humanoid rig's library
retargets to every villager; one creature taxonomy drops every
species into AgentSim with zero code.*

**Clip-name contract (audit 2026-07-06 — export validation will
enforce these exact strings):** code today plays `Idle`, `Walking`,
`Running`, `Sitting`, `Jump` — new rigs use THESE names (not
Walk/Run/Sit/SitDown); the creature taxonomy extends with `Drink`,
`Eat`, `Rest`, `Sleep`, `Alert`, `Flee` + one special when the
activity→clip mapping lands. (The robot's `WalkJump` is
placeholder-only; the fox player has fallback chains but nothing
else does.)

| Class | Count target | Notes |
|---|---|---|
| Player moveset [now] | **25–35 clips**: locomotion set, jump/land, swim/dive, sand-slide, sit set, gather, catch/deploy fireflies, wade, shiver/warm, recorder poses | the fox body ✅ |
| Humanoid shared library [now→village] | **35–45 clips** on ONE rig: locomotion 6–8 · work loops 8–12 (sweep, dig, carry, cook, fish, tend, hammer) · social 6–8 (wave, talk gestures ×3, nod, point) · contextual idles 6–8 (shade eyes, hug-self cold, watch sky, stretch) · sit/sleep 5–6 | retires the robot; every villager reskins it |
| Villager bodies [village] | **6–10** variants on the shared rig | |
| Wildlife species [rolling] | **15–25** bodies (star hound ✅): grazer herd, predator, birds, fish, shore skitterers, caravan beast, underworld 3–5 | × 8–12 clips each on the shared taxonomy (Idle/Walk/Run/Drink/Eat/Rest/Sleep/Alert/Flee + specials) |
| Insect/ambient swarms [now] | **5–8** billboard swarm sprites: moths ✅, fireflies ✅(code), butterflies, gnat columns, shore birds wheeling | billboard is the right treatment here |
| **Animation total** | **≈300–420 clips** | the taxonomy makes it a library, not a per-character cost |

### Props, clutter & architecture

| Class | Count target | Horizon |
|---|---|---|
| Village architecture kit | **20–30** pieces: walls, roofs, doors, windows, awnings, stalls, well, fences, lantern posts, docks | village ★★★ |
| Shrine/ancient kit | **10–15** pieces + ruins set | now→later |
| Bridges, fords, causeways trim | **8–10** | now |
| Village life clutter | **40–60**: furniture, containers, market goods, tools, signage | village |
| Camps & travel | **12–15**: campfire ✅(code), bedrolls, packs, caravan fittings | now→village (the runner EMBODIED 2026-07-05 — fittings + beast have a live slot) |
| Shoreline/nautical | **10–15**: boats/raft, nets, floats, dock clutter | later (traversal decision) |
| Food & forage items | **20–30** tiny models (icons auto-render) | rolling |
| Hero props | recorder, instruments, the glow's vessels | later (decisions) |
| Underworld structures | **8–12** | under |

### Audio — the full map

Everything in rev 1 stands (wind/night/rain beds, footsteps ×6
surfaces, thunder set, positional water, creature voices, village
murmur, underworld drips, IRs, diegetic music) **plus**: a distinct
ambience bed per biome ×8, interior/cave room tones ×3–4, seasonal
variants of the day bed ×4, weather transitions (petrichor beat, gust
front), UI/satchel/journal foley set. **Target: 120–160 files.**

### Totals & pacing (the honest math)

**≈280–380 meshes · ≈90–130 paintings/billboards · ≈60–90 textures ·
≈300–420 animation clips · ≈120–160 audio files.** At a sustainable
3–5 finished assets a week between two people, the full ledger is a
**2–3 year arc** — which is what a Skyrim-inspired density costs at
kitchen-table scale, and the priority tables still front-load the
10% that carries 80% of the look. The asset contract is what makes
the arc parallel: production never waits on the engine, and every
finished asset starts working the day its slot-loader lands.

## Already handled by code (no assets needed)

Terrain color/variation, ambient occlusion, soft shadows, palette grading,
day/night, fog, weather, water surface, sway — tuned in-engine. When the
ground kit + rock meshes + real audio land, the remaining look-gap is
content density, not technology. Also never needed: item icons (Blender
turntable renders them), star fields, water foam, snow cover, wetness
darkening, biome ground tints (all shader work reading the sim).
