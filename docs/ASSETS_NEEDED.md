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

The future asset load is a combinatorics problem, not a volume
problem: 8 biomes × ~8 flora species × 4 lifecycle stages × seasonal
states is 1,000+ paintings — no solo illustrator survives that.
The mitigations, in force from now on:

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

## The master ledger (2026-07-05 — the whole game, for batch planning)

*Everything the finished game wants from human hands, grouped by tool so
work can be batched away from the engine. Horizons: **[now]** the slot
exists and renders a placeholder today · **[village]** needed when M4
lands · **[under]** the underworld layer · **[later]** gated on a
decision or a distant milestone. Rough totals at the bottom — the point
of the ledger is that the whole game is a finite, survivable list.*

### Paintings — transparent PNG → `assets/paintings/`

**Flora, by biome** (the scale-discipline rules above: 2–3 signature
species per biome + one shared filler set; paint the `grow` stage
always, a `bloom` and `dry` variant for signatures only — sprout/seed
come from scale + shader tint). Current placeholder biome names, rename
at the kitchen table:

| Biome | Signature species (paint) | Notes |
|---|---|---|
| oasis_green [now] | arch tree ✅(hers) · high palm ✅(hers) · bloom tuft | The home valley — mostly done; bloom tuft is the forageable, worth a real painting early |
| scrub [now] | low shrub ✅(hers) · a dry-grass clump · a thorny silhouette | The connective-tissue biome, most walked-through |
| dune_desert [now] | dune cactus (SVG placeholder) · a ribbed succulent | First biome with zero real art — 2 paintings make it a place |
| wetland [now] | reeds · a broad-leaf clump | Bay shores, river mouths |
| strand [now] | beach grass · driftwood tuft | The coasts — huge shoreline mileage per painting |
| volcanic_rock [now] | a lichen pad · one hardy pioneer plant | Sparse by design |
| bare_peak [now] | (none — stone + snow) | Free |
| deep_sea [now] | (none) | Free |
| shared filler [now] | 3–4 generic tufts/pebbles (replaces the placeholder SVGs, same slots) | Appears everywhere, carries the density |
| underworld [under] | 2–3 glow-adjacent species | Gated on the glow's fiction (axioms) |

**Everything else painted:**

| Asset | Spec | Horizon |
|---|---|---|
| Ground-cover kit (top table) | 4–6 elements | now ★★★ |
| Rock family billboards (top table) | 3–4 | now ★★★ |
| Sky gradient strips dawn/day/dusk/night | ~256×1024 each | now ★★ |
| Seasonal sky variants (winter light differs) | 4 more strips | later |
| Distant mountain cutouts | 2–3, ~2000px | now ★ |
| Rain-curtain texture (the posterized hanging rain reads as painted) | 1 tileable sheet | now ★ |
| Cloud/fog wisps for the FogVolume + horizon | 2–3 soft sheets | later |
| UI 9-slices: panel, button, slider, focus ring (UITheme placeholders wear these slots) | per ART_BIBLE palette | now ★★ |
| Journal paper + map parchment background | 2 large sheets | now ★ |
| Item icons | NONE — rendered from the Blender turntable rig, never painted | — |
| Particle sprites: dust mote, rain streak, snowflake, seed fluff, splash puff (moth ✅ exists) | tiny, 64–128px | now, trivial |
| Character turnarounds (design docs for his rigging): villagers ×4–6, caravan drivers | any size | village |
| Creature concept paintings (each wildlife species starts as her painting — the fox and hound already did) | any | rolling |

### Blender models — glTF → `assets/models/` (F4 conventions: low-poly,
flat palette, `-col` collision meshes, +Z facing, ×1 scale)

| Asset | Spec | Horizon |
|---|---|---|
| **Rock family** (top table) | 4–5 boulders | now ★★★ |
| **Cliff/plateau kit** — the rock family grown up: slab, rim, overhang, sheer face, slide wall | 5–8 pieces, ~1–2k tris each | now ★★ — this is terrain, not decoration (IDEAS); breaks the heightfield ceiling |
| Mesa / large formations | ×1–2 | now ★★ |
| Shrine rebuild (modular) | 4–6 pieces | now ★ |
| **First character** from her turnaround | rigged; clips: Idle/Walk/Run/SitDown/SitIdle/StandUp + Talk gesture | now ★★ — retires the robot for BOTH current NPCs (reskin) |
| Villager body variants | 4–6 reskins/proportion tweaks of the character rig | village |
| Wildlife species (shared clip taxonomy: Idle/Walk/Run/Drink/Rest/Alert/Flee + 1 special) — grazer herd, predator, small skitterer, bird (or painted billboard flock), fish (simple), caravan beast | ~8–15 total over the project; star hound ✅ | rolling; predator when wildlife rung 4, caravan beast when caravans embody |
| Village architecture kit — wall, roof, door, window, awning, market stall, well, fence, lantern post | 10–15 pieces | village ★★★ (the kit IS the village) |
| Bridge + ford stones | 3–4 pieces | now ★ (rivers partition the world already) |
| Props: campfire, cookpot, baskets, crates, bedroll, tools | ~10 small pieces | village |
| Food/forage items (each auto-renders its satchel icon) | ~8–12 tiny models | rolling, starts with dried bloom |
| The recorder (player's field-recording device) | 1 hero prop | later — gated on the field-recordist decision |
| Boat / raft | 1 | later — gated on the traversal decision (causeway vs boat) |
| Waterfall mesh pieces (stepped river drops) | 2–3 | later — rivers' open item |
| Underworld kit: stalactite, column, cave mouth, sinkhole rim | 6+ pieces | under |

### Audio — WAV → `assets/audio/` (seamless loops for beds, one-shots
for events; `reimport.sh` swaps them live)

| Asset | Spec | Horizon |
|---|---|---|
| **Wind bed** + storm wind layer (top table) | 60s+ loops | now ★★★ |
| **Night bed** (top table) | 60s+ loop | now ★★★ |
| Footsteps: sand / stone / water / plants ×4–6 each | one-shots | now ★★ |
| Footsteps: mud, snow ×4 each | one-shots | later (both ground states exist) |
| Pond lap / brook run / sea shore / bay lap | 30s+ loops, positional | now ★★ |
| Rain: light (drizzle) + heavy (storm) beds | 60s loops | now ★★ (seven weather kinds ship on synth) |
| Thunder set ×4–6 (near cracks + distant rolls — the lightning system schedules them by distance) | one-shots | now ★★ (placeholder noted in STATUS) |
| Dawn chorus | 60s, crossfades in at real sunrise | now ★ |
| Insect chorus loop (steppable rate — Dolbear's-law thermometer wants ~3 density variants) | loops | later ★ (an IDEAS signature) |
| Waterfall loop (loudness will track real flow) | 60s | later, with waterfall meshes |
| Sand: slide hiss, booming-dune drone | loop + drone | later (sim ships, sound is the missing half) |
| Splashes: wade, dive, surface ×3–4 | one-shots | now ★ |
| Gather/forage, satchel open, journal page, UI tick set | one-shots | now ★ |
| Creature voices: hound calls ×3, grazer, bird calls ×4 | one-shots | rolling with each species |
| Shrine wind-chimes | loop, positional | now ★ |
| Village murmur bed + market clatter | loops | village |
| Underworld: drip set, cavern room-tone, distant water | loops | under |
| Reverb impulse responses (record real canyons/rooms — IDEAS) | IRs | later |
| Humming/whistle lines for NPCs + ONE findable daily performance | musical, diegetic-only canon | later — post-axioms |

### Rough totals (the whole game, at current design)

~55–70 paintings (≈25 flora + ~15 environment/sky/UI + ~15 concepts/
misc) · ~60–80 models (≈30 kit pieces + ~15 creatures/characters +
~25 props) · ~70–90 audio files (≈25 beds/loops + ~50 one-shot sets
counted as files). **A finite list** — a painting every few days and
a model every week lands the whole ledger within a year, and the
priority tables mean the top 10% of it carries 80% of the look.

*Maintenance: when the derived asset-manifest tool lands (scale
discipline, above), the [now] rows of this ledger become a generated
report and this section shrinks to the horizons and totals.*

## Already handled by code (no assets needed)

Terrain color/variation, ambient occlusion, soft shadows, palette grading,
day/night, fog, weather, water surface, sway — tuned in-engine. When the
ground kit + rock meshes + real audio land, the remaining look-gap is
content density, not technology. Also never needed: item icons (Blender
turntable renders them), star fields, water foam, snow cover, wetness
darkening, biome ground tints (all shader work reading the sim).
