# Decisions Log

*Settled questions and why — so future-us doesn't relitigate them.
All decided 2026-07-01 (first design day) unless noted.*

- **Godot 4, not Unity/Unreal/custom.** Mac-native, open source (MIT) = the
  real "max control"; our differentiating systems live in game code either
  way; custom engine = years of commodity plumbing. Unreal's big-world tech
  serves realistic art we don't use.
- **Hybrid art: painted billboards + flat-shaded meshes; characters are 3D.**
  Her paintings enter the game directly (billboards for flora/props/distant);
  terrain/buildings are low-poly flat-shaded meshes; characters (player,
  NPCs, creatures) are 3D for combat + immersion (Sable-like). Hero flora
  graduates to Blender models over time; billboards stay for density/distance
  (Elden Ring does grass this way).
- **Unified palette law.** One color script per biome/time-of-day; characters
  shade with the world's ramps; nothing gets realistic lighting. Only the
  glow-phenomenon/shrines/celestial emit light — glow is reserved language.
- **Third-person camera.** Settled by lock-on combat + billboard readability
  + seeing your character inhabit the world.
- **Combat: full system, souls-inspired, sparse.** Deliberate/stamina/lock-on;
  Shadow-of-the-Colossus structure (~one monumental guardian per biome).
  Built last (M5) — the world comes first.
- **RPG depth via systemic reactivity, not branching.** Consequences mutate
  existing content (state flags, schedules, prices), never spawn parallel
  content. Text-only dialogue, no VO — reactivity over performance.
- **Progression: use-based skills + tools as exploration keys.** No XP levels.
- **World: finite but undecided size — a growing quilt.** Authored heightmap
  tiles (rect canvases, irregular contents) + a fully irregular painted biome
  mask; auto frontier rim at unauthored edges; start small, grow outward.
  Generative = subordinate detail only. ~12km diameter before float work.
- **Setting: novel genre, not fantasy/sci-fi.** Derived from her paintings via
  2–3 world-axioms (pending). "Magic" is a banned word; the glow is a named
  natural phenomenon (name pending). Tools from world materials.
- **Simulation is a pillar.** Needs-driven NPCs (utility AI), weather,
  eventually flora lifecycle/ecology — with the Radiant AI discipline:
  inspector for everything, coarse far-tier, guardrails on canon state,
  one system at a time, player-visible or cut.
- **"Real physics" = the two-layer illusion.** Coarse state globally +
  interaction-field response near the player (trails, ripples, bent grass).
  World-scale volumetric fluid/granular solvers: never.
- **Maps: functional map rendered live from the world** (Skyrim-style camera);
  her illustrated map traced from it later.
- **Tools live in the game, dev-gated** (god mode pattern); content is
  records; place mode writes JSON, not scenes.
- **Repo: private GitHub (nicco-b/valley), plain git for binaries until ~1GB.**

## Open (deliberately undecided)

- World-axioms, the glow's name, the Wanderer's identity, journey premise
- Field-recordist player character (signature-mechanic candidate — leaning yes)
- No-compass/no-markers Morrowind navigation (decide before quest content)
- Fast travel: diegetic-or-none (decide with world size)
- NPC navigation approach: navmesh-per-cell vs steering (before NPC #2)
- Factions, economy model
