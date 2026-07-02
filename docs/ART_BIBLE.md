# Art Bible

*The visual laws and asset specs. For the illustrator (what to paint, how to
export) and the code (what to enforce). The style reference is her existing
gouache work: segmented bulb-flora, starburst blooms, striped mountains,
pink pools, a close red sun.*

## The laws

1. **The world is matte paint.** Flat colors, painted texture, roughness 1.0.
   No realistic materials, no normal maps, no PBR anywhere.
2. **Glow is reserved.** Only the glow-phenomenon, shrines, and celestial
   bodies emit light/bloom. If everything glows, nothing is sacred.
3. **One palette per biome per time-of-day.** The day/night cycle moves the
   whole world through palette keyframes (see `day_night.gd` KEYS) — night
   is a different painting, not a darker one.
4. **Characters live in the same paint.** Flat shading in the world's ramps;
   a character under "normal 3D lighting" looks pasted on and is wrong.
5. **Imperfection reads as style.** Boxy low-poly, visible brush grain,
   wobbly shapes — all on-style. Precision is not a goal.

## Current working palette (sampled from reference + in-game)

| Use | Color |
|---|---|
| Deep flora teal | `#1c4a4d` family (`#173f42`–`#235659`) |
| Olive flora | `#4a5233` family |
| Bulb-palm violet | `#7a7fd0` family |
| Starburst gold/ochre | `#b98a2e`, `#a8801f` |
| Bloom pink / glow | `#e8547a`, hot center `#ef6f8e` |
| Sand ground | `#EDE3D1` |
| Rock ochre | `#DEA95E` |
| Rock gray-green | `#677165` |
| Dawn/dusk sky | pink `#F9CFD3` → cream `#FCEEE4` |
| Night sky | indigo `#141A2B`, horizon mauve `#332B40` |
| Water | `#ED8C99` striped with `#FCC2C4` |

(Working values, not law — the palette matures with her paintings. Update
this table when it does.)

## Asset specs

**Flora / scatter elements (billboards)** — transparent PNG, ~1200–2000px
tall, one element per file, painted families with 3–4 variants per type so
scatter doesn't repeat. Export to `assets/paintings/`. Sizes/rarity are set
in the `FLORA` table. Strata wanted: ground tufts/grass (missing), shrubs ✓,
mid trees ✓, tall landmark trees ✓, rocks (missing as paintings).

**Sky gradients** — dawn/day/dusk/night, currently code keyframes; painted
gradient strips can replace them later.

**Character turnarounds** — front/side/back on one sheet, in palette, any
size. These drive Blender modeling (see FOUNDATIONS F4 for rig/export
conventions: 1u=1m, +Z forward, clips: Idle/Walk/Run/SitDown/SitIdle/
StandUp/...).

**Creatures** — same as characters + a note on how it moves (gait, speed,
temperament). The moth is first in line.

**The illustrated map** — traced from the in-game map (M) whenever a region
stabilizes; place names come from the lore bible's naming language.

## Workflow

- Re-exporting a PNG while the game runs hot-reloads it in-world within a
  second — paint with the game open on a second screen.
- The god camera (F1) and map (M) are composition tools: use them to judge
  how paintings sit in the world at distance, at dusk, in fog.
- Screenshots are canon reference: a folder of in-game dusk shots is the
  brief for every next painting.
