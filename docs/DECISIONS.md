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
- **If you can see it, you can go there.** No fake vista geometry, ever.
  Distant terrain renders from the same height function the streamer
  builds walkable cells from (far-LOD mesh); a visible mountain is a real
  destination. Scales with the quilt: authored tiles feed both near and far.
- **Sitting changes nothing.** No depth-of-field, no filters, no cinematic
  dressing on the sit — the point of sitting is seeing the world exactly as
  it is. (Camera pull-out and HUD fade stay; they remove, not add.)
- **Repo: private GitHub (nicco-b/valley), plain git for binaries until ~1GB.**
- **Time is 1:1 with the real world — always** *(2026-07-02, the ambient
  machine; see [SESSION_2026-07-02_ambient_feel_and_combat.md](SESSION_2026-07-02_ambient_feel_and_combat.md))*.
  A game day lasts a real day: playing, unfocused, or closed. The save
  carries a wall-clock timestamp; time away (and laptop sleep) is replayed
  through the shared `GameClock.advance_hours()` catch-up in hour chunks,
  always at 1:1 — the valley is a place that keeps its own time, not a tape
  you pause. Stillness (`time_scale`) stays the diegetic fast-forward.
  Rate-1:1, *not* local-clock-synced: the world keeps its own calendar and
  the red-sun fiction; matching the player's actual wall clock + real sun
  position remains an optional future mode (IDEAS "celestial clockwork").
- **Simulation depth is wanted beyond the directly visible** *(2026-07-02)*.
  Amends the "player-visible or cut" clause of the simulation pillar: the
  golden category is **"unseen now, seen later"** — deep offscreen/away
  simulation whose *consequences* the player meets on return is the point
  of the ambient machine. Cut only computation with zero eventual
  consequence. Observability discipline (inspector for everything) is
  unchanged and matters more, not less.
- **Real seasons, the real calendar** *(2026-07-02)*. The valley shares the
  player's calendar: season (`GameClock.season`, mirrored to WorldState
  `time.season` for quests/dialogue/seeds) and daylight length derive from
  the real system date. Sun arc, sky palette, dusk audio, and night
  creatures all read `GameClock.solar_hours()` — hour-of-day warped so
  sunrise/sunset land on canonical 6:00/18:00 — so everything sun-shaped
  inherits seasonal daylight from one seam. Weather storm odds are
  season-biased. Northern-hemisphere arc (hemisphere setting later);
  seasonal *palette/flora* changes await her seasonal paintings.
- **Unfocused = watchable, throttled** *(2026-07-02)*. The unfocused window
  stays alive and glanceable (fps-capped, nothing dissolves, tiers stay
  distance-based); only a minimized window throttles near-idle. Good-citizen
  behavior for leave-it-running, without sabotaging the glance.

## Open (deliberately undecided)

- World-axioms, the glow's name, the Wanderer's identity, journey premise
- Field-recordist player character (signature-mechanic candidate — leaning yes)
- No-compass/no-markers Morrowind navigation (decide before quest content)
- Fast travel: diegetic-or-none (decide with world size)
- NPC navigation approach: navmesh-per-cell vs steering (before NPC #2)
- Factions, economy model
