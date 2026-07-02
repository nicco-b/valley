# Status — read this first when resuming

*As of 2026-07-01, end of the first build day (~70 commits, all pushed to
github.com/nicco-b/valley). This file is the live state; update it when
things change. The doc map: [DESIGN.md](DESIGN.md) = what the game is ·
[FOUNDATIONS.md](FOUNDATIONS.md) = build plan & backlog · [DEV_GUIDE.md](DEV_GUIDE.md)
= how to work on it · [DECISIONS.md](DECISIONS.md) = settled questions ·
[IDEAS.md](IDEAS.md) = the drawer · [ASSETS_NEEDED.md](ASSETS_NEEDED.md) =
the human-made shopping list · [lore/](lore/) = canon (axioms pending) ·
`/CLAUDE.md` = conventions + gotchas for AI sessions.*

## What exists and works (all tested; run `./scripts/test.sh`)

**World** — streamed 128m cell grid (threaded generation); one height
function feeding near terrain, far-terrain LOD to the horizon, and the map
("if you can see it, you can go there" — the distant mountains are real);
authored valley landform (spawn → pond ~310m → shrine ~620m); god-mode
sculpt layer (EXR); painterly terrain shader (height/slope bands, wind
ripples, sun glints); scattered flora from her 3 paintings + dense
ground-cover stratum (placeholder SVGs); pond with wading/swimming and
ripple wake; day/night palette cycle; custom sky (swelling red sun, stars);
weather (calm/windy/storm) driving sway, audio, fog, dust, and NPC shelter;
interaction field (footprints with relief, fading trails); ambient
particles (sand motes, dusk moths from her painting, night glow-motes).

**Simulation** — GameClock (15-min days, hour_tick bus, time_scale);
needs/utility NPC AI from records; two-tier (bodies dissolve >170m, coarse
sim continues); sim inspector (god mode → right-click NPC).

**RPG** — WorldState (all flags/values, saved); records loader with
validation; interaction layer (E); items + satchel (I); fireflies (catch at
night / F deploys orbiting light swarm / R recalls); dialogue engine
(records in data/dialogue/, conditions/effects, familiarity-aware); quests
(declarative over WorldState, journal on J); use-based skills (Wayfaring/
Stillness—bends time while sitting/Swimming/Foraging); two inhabitants —
the Wanderer (pink scarf) and the Keeper (teal, tends shrine) — who know
each other; first errand quest "Between Two Solitudes".

**Shell/tools** — title screen, pause/settings, autosave; god mode (F1:
fly/sculpt/place/inspect); live map (M, gestures); hot-reload of paintings;
place mode writing cell records; gamepad support; CI on GitHub; test
harness (unit + scene + dual smoke).

## Placeholder ledger (each has a named replacement path)

Robot character (→ her turnaround + Blender) · synth wind + footsteps
(→ his recordings; night bed is a CC0 field recording, see
assets/audio/SOURCES.md) · SVG tufts/pebbles/cactus (→ her painted PNGs,
same slots) · noise terrain beyond the valley (→ painted region tiles,
FOUNDATIONS F3) · all dialogue text (→ post-axioms rewrite).

## Next up (in rough priority)

1. **Asset track (humans)** — see ASSETS_NEEDED.md. Top: her ground-cover
   kit, his Blender rock family, real wind recording.
2. **Canon track (kitchen table)** — the axioms conversation
   (docs/lore/axioms.md is scaffolded); gates all real writing. Pending
   decisions: field-recordist player mechanic (IDEAS ★), no-compass
   Morrowind navigation (must precede quest writing).
3. **Code: G4 remainder** — inventory/item-use UI (eat, examine, gift),
   trading (needs the errand pattern + prices).
4. **Code: G6** — NPC-to-NPC ambient meetings (they cross paths at the pond
   daily and ignore each other); proper navmesh before more NPCs.
5. **Code: G5** — region tile pipeline (painted heightmaps) when the world
   wants to grow; biome mask when region #2 exists.
6. **Code: G1 leftovers** — save slots, macOS export build.

## How to resume

`./scripts/run.sh` plays · `./scripts/test.sh` before every commit ·
`godot --path . -e` opens the editor · full keymap + recipes in
DEV_GUIDE.md. For AI sessions: CLAUDE.md carries every hard-won gotcha
(tscn rules, import traps, autoload-vs-`-s` compile order, etc).
