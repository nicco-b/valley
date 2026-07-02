# Assets Needed — the human list

*Everything the game is waiting on from people rather than code, specified
so it can be made without asking questions. Ordered by visual/experiential
impact within each section. Specs referenced from [ART_BIBLE.md](ART_BIBLE.md).*

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

## Already handled by code (no assets needed)

Terrain color/variation, ambient occlusion, soft shadows, palette grading,
day/night, fog, weather, water surface, sway — tuned in-engine. When the
ground kit + rock meshes + real audio land, the remaining look-gap is
content density, not technology.
