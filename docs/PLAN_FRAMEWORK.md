# PLAN_FRAMEWORK — the valley IS the engine

*2026-07-08, from Nicco: "i want the valleys current setup to basically
be the game engine that every game strata makes uses. valley should
probably be baked into our strata setup by now no? for example i dont
see any water in my new game. its blue surface color though."
Cross-repo: `strata/docs/ONE_APP.md` stays the law spine (games are
self-contained repos Strata opens; profiles-not-platforms; the fork
law; no Strata code ships in the game) — this plan is the valley-side
half of the template story. `strata/docs/PLAN_CREATION_LIBRARY.md` is
its structural sibling: the copy + provenance + offered-updates
pattern, generalized here from assets to code. Same laws, same voice
as PLAN_PHYSICS/PLAN_FABRIC.*

## Executive summary

Nicco is right, and the codebase already agrees with him. DECISIONS
2026-07-04 (the Creation Kit entry) said it before tonight did: *"the
current valley is a test fixture; only the systems and the toolkit
carry forward."* The framework is those systems. The verdicts:

- **What is the framework?** Valley's `game/` tree minus a nub of
  content. Measured (every `.gd` read, ~15,850 lines across 67 files):
  **~85% of `game/` is generic machinery**; the valley-specific leaks
  are six seamed files' worth of constants plus a handful of magic
  paths — not a pervasive entanglement. The `[autoload]` column in
  `project.godot` — all 33 of them — IS the framework's table of
  contents. The sim contract (GameClock/WorldState/the soak law) is
  the framework's constitution and ships as law + code.
- **How does it ship? Copy + provenance + offered updates** — the
  stock-library pattern applied to code (option a). The scaffold
  copies the framework tree into each new game; every file is stamped
  with a recomputable rev; `strata-cli retemplate` (today a blind,
  provenance-free overwrite) is reborn as `framework update`: diff,
  offer, never force, demote honestly on local divergence. Games stay
  self-contained (the standing law); no shared addon, ever (option b
  is a database in a trench coat); option c (new game = valley minus
  content) is what option a becomes once a manifest says *which*
  files and a rev says *which day's* valley.
- **Where does it live? In valley.** A `framework.json` manifest
  first; a directory split only if drift ever proves it's needed.
  Valley is the framework's reference implementation and first
  consumer — the framework is what valley RUNS, not a fork of it.
  The receipts: 296 commits in the last eight days, and the hottest
  files are all engine-grade (toolkit, terrain, map, streamer, water
  bodies, the link, weather, climate, hydrology). Any framework
  valley doesn't run daily is stale by Tuesday.
- **Rung FW1 kills tonight's water gap specifically**: a new game
  gets valley's real Watershed — and its `hydrology.json` (already
  shipped, currently unread!) becomes rivers that foam and lakes with
  storm chop, not a blue mirror.

## Where the template stands (the water-gap autopsy, 2026-07-09)

Tonight's bug is not a bug; it is the inevitable drift of the current
approach. `strata/Sources/StrataCore/Project/GameScaffold.swift` is a
**1600-line Swift string-writer**: every game file is a hand-ported
miniature of a valley idea, frozen as a `static let` string constant.
What it writes: a preview terrain loader (`MAX_GRID = 192`, its own
header says *"a preview, not a kernel"*), camera rigs, a WASD player,
the link server — and for water, a **static translucent PlaneMesh
named "Sea"** (`roughness = 0.08` — a sky mirror) plus a hypsometric
ramp that tints low vertices blue. That is the "blue surface color."

Meanwhile the scaffolded game (`strata/mygame/`) **already ships
`data/terrain/world/hydrology.json`** — rivers, lakes, waterfalls,
baked by Strata's own pipeline — and contains no code that reads it.
Valley grew that consumer in P2 (rivers as no_sim records, lakes at
fill elevation, knickpoint waterfalls, fetch-scaled swell); the
consumer was never ported. **The data seam works; the code seam is
hand-copied and therefore always behind.** `strata-cli retemplate`
can't heal this: it re-runs the same string-writer as a plain
overwrite — no manifest, no shas, no diff, no idea whether you
hand-edited anything. Every system valley grows from here (the
Teller, the Threshold, fabric, substances…) widens the gap by
default. The string-writer must die of a better idea, not be fed.

M5 makes this urgent rather than cosmetic: the engine now boots with
Strata and IS the shaping viewport for every opened game. The
template is no longer a preview off to the side — it's the live
surface. A scaffolded game that can't render valley's water is a
broken pane, visibly, on night one.

## Q1 · The line through the systems

The classification law is already valley's own: *code is the machine;
data is the game* (CLAUDE.md). `game/` + `game/shaders/` + `native/`
= framework. `data/` + `assets/` + `lore/` + STORY = valley. The
table, system by system (blessed names):

| System | Files (the spine) | Verdict | The seam inside |
|---|---|---|---|
| **The Chronicle** | `world_state.gd`, `records.gd`, `cards.gd`, `cell_records.gd`, `save_manager.gd`, `overrides.gd`, `conditions.gd` | framework | none — the state spine is pure machinery; the records it loads are the game |
| **The Almanac + Ambient Machine** | `game_clock.gd`, `focus_throttle.gd` | framework | none. The sim contract (1:1 time, `hour_tick`, `advance_hours` as the one door, `world_state_reader` group, the soak law) ships as the framework's constitution — every system in every game signs it |
| **The Watershed** | `hydrology.gd`, `water_bodies.gd`, `water_field.gd`, `water_waves.gd`, `wave_gpu.gd`, `sea_swell.gd`, `water_gpu.gd`, `water_sheet.gd`, `wave_reference.gd`, `water*.gdshader`, `compute/water_*.glsl` | framework — all four tiers + the wave field | the cleanest seam in the repo; hydrology.gd's own comment: *"the map is replaceable, the system isn't."* Content = `data/water/` records. Fallback center + mood-physics tuning constants are valley defaults (FW4) |
| **The Loom** | `world_streamer.gd`, `terrain.gd`, `far_terrain.gd`, `nav.gd`, the native kernel | framework | the streamer + kernel are startlingly clean (the kernel takes valley geography as *parameters*, not compilation). `terrain.gd` is THE seamed file: `VALLEY_PATH`, the noise seeds, the archipelago draft — valley's placeholder world baked into `height()` (FW4, the biggest single job). `valleykernel.gdext` wants a rename ★ |
| **The Elements** | `weather.gd`, `climate.gd`, `flora_life.gd`, `atmosphere.gd`, `day_night.gd`, `ambience.gd`, `weather_fx.gd`, sky/rain/sway shaders | framework | wind truth (`wind_strength`/`wind_dir` globals) is the one-truth pattern every game inherits. Seams: `KINDS`/`TRANSITIONS` are a *desert default*; climate `REFERENCE` + grid frame; day_night `KEYS` palette is painting-sampled art in code; `valley.bloom`/`valley.parched` key names (FW4) |
| **The Grain** | `sand_field.gd`, `sand_gpu.gd`, `sand_patch.gd`, `compute/sand_*.glsl` | framework | tuning-as-content only |
| **The Traces** | `interaction_field.gd` | framework | none |
| **The Understory** | `agent_sim.gd`, `path_cursor.gd`, `rng.gd`, `wildlife_manager.gd`, `wildlife_body.gd` | framework | textbook cut: AgentSim is the generic mind (*"every future agent is an AgentSim plus a record"*); the star hound is valley's — `hound_body.tscn`, the glb, `data/wildlife/star_hounds.json`, and the `preload` at wildlife_manager.gd:18 that hardcodes the body scene (FW4: body path joins the record) |
| **The Campfire** | `story.gd`, `conditions.gd`, `journal_ui.gd`, `quest_lint.gd`, the quest harness | framework | near-zero residue; the closed Conditions table reads only WorldState mirrors by design. Quests are records |
| **The Threshold** | `interiors.gd` | framework | content = `data/interiors/*.json` (the cellar is valley's) |
| **Fabric** | `fabric_spring.gd`, `fabric_wind.gdshader` | framework | the one-wind law rides along. Seam: `PRESETS` hardcodes hound/fox bone names (FW4: per-creature record) |
| **The Toolkit + the link** | `toolkit.gd`, `strata_link.gd`, `overrides.gd`, `hot_reload.gd`, `river_pen.gd`, `preview_terrain.gd` | framework, emphatically | the crown jewel — a game without the Toolkit is a game Strata can't author, and the chrome contract is Strata's language into EVERY game. Seam: the `baked_world.exr` magic path (a Strata convention, not valley content — name it once) |
| **The map** | `map_screen.gd`, `orbit_rig.gd` | framework | `MARKS := []` already retired valley's list; draws from records |
| **The Kit** | `kit.gd` | framework | `scene_for()` is the resolver everyone uses; the 5 legacy `ENTRIES` ("Silly tree", "Bulb palm") are content and already dying per the Toolkit build-out (cards, not ENTRIES) |
| **UI / items / skills / interact** | `hud.gd`, `settings.gd`, `pause_menu.gd`, `title.gd`, `ui_theme.gd`, `items.gd`, `skills.gd`, `interactable.gd`, `examinable.gd` | framework | `title.gd`'s `WORLD_SCENE := "res://game/world/valley.tscn"` is the one hardcoded world pointer. The gouache paper theme is art-machinery ★ (ships as the default look) |
| **Player** | `player.gd`, `character_paint.gd/.gdshader`, `player.tscn` | framework | the controller (walk/sprint/sit/swim — swim reads the Watershed) is machinery; the fox model + footstep audio paths are content via character records. The firefly companion is a valley *mechanic* riding framework code ★ |

**Valley-content, staying home:** `data/` wholesale (water layout,
regions, flora species, scatter tables, cells, quests, interiors,
items, skills, wildlife records), `assets/` wholesale (351 glbs, 113
cards, paintings, audio, blender sources), `lore/`, STORY.md, the
axioms, the hound, the fox, the tuning that makes this valley THIS
valley. A new game gets the machine and empty rooms.

**Point couplings to sever (the FW4 checklist, complete):**
`project.godot` name/main_scene + stale valley coords in
`[shader_globals]` defaults (overwritten at runtime; ship zeroed) ·
`title.gd` world-scene pointer · day_night `KEYS` → `data/sky/` ·
weather `KINDS`/climate `REFERENCE` → `data/climate/` · fabric
`PRESETS` → creature records · wildlife `BODY_SCENE` preload → record
field · kit `ENTRIES` → `[]` · `valley.bloom` key namespacing ·
terrain's procedural draft → `data/world/landform.json` (or: the
blessed tile becomes the only ground and the draft dies) ·
`valleykernel` rename ★. Six files of constants, one preload, one
scene pointer. That's the whole entanglement.

**Tests ride too** — the sleeper win. `test.sh`, `soak.sh`, the unit
runner, scene tests, the quest harness and lint: a scaffolded game is
born with valley's whole verification discipline, not just its
renderer. The soak law is portable because the contract is.

## Q2 · How it ships

**(a) Copy + provenance + offered updates — the library pattern,
generalized. WINNER.** The mechanism, stolen precisely from
PLAN_CREATION_LIBRARY (it already priced these options for assets;
the physics is identical for code):

- Valley grows **`framework.json`** — the manifest: the list of
  framework file paths (per the Q1 table). An entry's `rev` = sha256
  over its files' shas, sorted, concatenated, truncated to 12 hex —
  **computed, never a counter**; derivable from the filesystem on
  both sides; git history is the audit trail. No registry, no DB.
- **`scripts/framework_dist.sh`** exports the manifest's files to a
  dist tree. Strata bundles a dist snapshot at build time (dev
  override: read the live `~/code/valley` checkout directly ★).
- **The scaffold copies real files.** `GameScaffold.writeGameTemplate`
  stops being a string-writer and becomes: copy the dist tree + write
  the per-game fill-ins (project name, `project.godot` header — kept
  tiny, never a template language). The game repo gains
  **`framework.lock.json`**: `{framework: "valley", rev, files:
  {path: sha}}` — a provenance key the game itself never reads,
  exactly like the asset cards' `stock` key.
- **`strata-cli framework update`** (retemplate reborn): recompute
  shas game-side, three honest states per file — **clean** (offer the
  new rev), **modified** (demote: *"framework has a newer version;
  yours is modified"* — replacing becomes an explicit act), **custom**
  (untracked = the game's own, untouched). Never automatic, never on
  a timer, never wholesale-forced. Updates flow OUT of valley
  *deliberately*: Nicco tunes valley all day; a game moves only when
  asked.

**(b) A shared Godot addon/package games reference — DRAWER,
by law.** The library plan already ruled the reference shape out for
assets: *"a game repo must stay self-contained and shippable — it can
never reference Strata's library at runtime."* A framework addon is
the same database wearing the same trench coat, plus version-skew
hell across games mid-iteration. Five games = five copies; disk is
cheap, coupling isn't.

**(c) Valley literally becomes the template (new game = valley minus
content) — honest, and subsumed.** The drag, named: a raw clone
carries 351 glbs, the paintings, the canon, the hound, in-flight
branches, and a delete-by-hand step that is retemplate's blindness
running in reverse. But (c)'s *soul* is correct — new games should
get valley's REAL files — and option (a) IS (c) with a manifest
saying which files, a rev saying which day's valley, and a diff
saying what changed since. We take (c)'s honesty through (a)'s door.

Weighed against the constraints: games ship standalone ✓ (copies).
Valley iterates daily ✓ (framework changes are just valley commits;
games see them as offered diffs). The one-day-rebase-budget spirit ✓
— a game's divergence from the framework is *visible* (the
modified-file count in `framework update` is the games-side analogue
of the fork's rebase budget: if a game can't take an update in a
day, its hand-edits have grown too big and that's now measurable).

## Q3 · Where the framework lives

**In valley. Manifest first; directory split only on evidence.**

- **(i) In valley — WINNER.** Valley is the reference implementation
  and first consumer; the framework is the code valley boots every
  day. The drift-proof shape is *extraction that valley itself
  consumes* — and the cheapest true form of that is a manifest over
  the files where they already live. Every valley commit to a
  manifest file is automatically a framework commit; the soak and the
  test suite verify the framework continuously because they verify
  valley.
- **(ii) A third repo (strata-framework) — NO.** It's a fork of
  valley by another name. Nicco will not PR water tweaks to a
  framework repo while tuning valley at 296 commits a week; the
  extraction he doesn't run isn't an extraction, it's a stale copy
  with a README. Every hour of divergence is exactly the drift that
  produced tonight's blue plane.
- **(iii) Inside strata's repo — NO.** "No Strata code ships in the
  game" has a mirror: no game code lives in Strata. GameScaffold's
  string constants are precisely this violation in miniature, and
  they're the thing that drifted.

**The directory-split question (framework/ vs game/ in-repo), priced
honestly:** a physical split is the visible fence — but it's a
fleet-day of `res://` path churn (preloads, tscn ext_resources,
`project.godot`, uid files, muscle memory), it breaks every open
branch and worktree, and it buys little the manifest doesn't. The
manifest buys the same seam for one file; a **lint rung** (FW5:
manifest files may not preload `assets/` or name content ids) is the
cheap fence in between. Revisit the split only if manifest-drift
actually bites — with the lint failing as the evidence.

## Q4 · The seam with profiles (many games = profiles, the law)

The standing law (ONE_APP amendment 3): *"Multi-game means profiles,
not platforms."* Today a profile is the biome classifier table
(`<name>.strataprofile.json`: biome rows with height/temp/moisture/
slope ranges + colors), consumed at **bake time** — the game wears
the baked result and never loads Strata's Profile type (the
self-containment law, kept).

The framework extends the same posture game-side: **a game's identity
is data, never code edits.** Everything the FW4 rungs pull out of
code lands in the places a profile/records pipeline can reach —
biome tables and palettes (`data/world/biomes.json`, the day_night
keyframes), climate mood (`data/climate/profile.json`: the KINDS
bundles, transitions, season biases, reference point), water look
(shader params as records, not shader edits), flora/scatter tables,
creature records (body path + fabric chains + activities), character
records, kit cards, quests, interiors. A second game with a swamp
mood and green water is: its own `.strataprofile.json` + its own
`data/` — zero framework-file edits, so `framework update` stays
clean forever. Code edits mean new *machinery* — and machinery
belongs upstream in valley, where the next `framework update` offers
it to every game. Contribution flows by being valley.

## Q5 · The ladder (FW rungs, each fleet-sized)

**FW1 · The water arrives (kill tonight's gap — the proof).**
`framework.json` v0 scoped to what water honestly needs — which is
the world spine, because Hydrology reads Terrain's rivers/height,
Weather's storms, Climate's wetness, GameClock's hours: the
Chronicle + Almanac + Loom + Elements + **the whole Watershed**,
their shaders and compute kernels, the native kernel binary, and the
autoload column for that set. `framework_dist.sh` + the scaffold's
water/terrain/world string-constants replaced by real copies (the
miniature `terrain.gd` and the "Sea" plane are deleted with honors).
The one real engineering task inside the rung: **the machine must
boot content-empty** — fresh game, empty `data/` dirs, headless
smoke green (Records already validates what exists; find what
doesn't). Fill-ins stay tiny (name, main scene).
✓ Retemplate mygame: its already-shipped `hydrology.json` becomes
rivers that foam over knickpoints and lakes with fetch-scaled storm
chop; wading rings the water; the static Sea plane no longer exists.
`test.sh` green in the fresh game AND in valley.

**FW2 · The lock and the offer (retemplate dies).**
`framework.lock.json` stamped at scaffold; `strata-cli framework
update` with the three honest states (clean / modified / custom);
`retemplate` becomes an alias that prints the diff and offers —
the blind overwrite retires. Divergence count surfaces in Strata's
project view (the game's "rebase budget" gauge).
✓ Scaffold at rev A; land a valley water tweak; `framework update`
offers exactly that file. Hand-edit a framework file game-side; the
offer demotes to modified and refuses to clobber silently.

**FW3 · The whole machine rides (pane parity).** The manifest grows
to the full Q1 table: the Toolkit + link + overrides (Strata's hand
inside every game), the Campfire, the Threshold, fabric, the map,
save, skills, items, the test harnesses and `soak.sh`. A scaffolded
game speaks the entire chrome contract and verifies itself like
valley does.
✓ Fresh game: F1 opens the Toolkit; `toolkit status` answers over
the link; the game's own `test.sh` and a 30-day soak run green on a
world with no content.

**FW4 · The de-contenting (many small rungs, valley bit-identical
after each).** The Q1 point-coupling checklist, one agent-sized rung
apiece: sky palette → records · climate/weather mood → records ·
fabric presets + wildlife body → creature records · kit ENTRIES
retired · title scene pointer parameterized · shader_globals defaults
zeroed · `valley.*` key namespacing · terrain's procedural draft →
`data/world/landform.json` (the big one, last) · kernel rename ★.
✓ After every rung: valley's soak fingerprint unmoved (or moved
knowingly, logged), and the framework file diff is content-free.

**FW5 · The fence gets teeth.** The manifest lint joins `test.sh`:
framework files may not `preload` from `assets/`, may not name
content ids, may not write un-namespaced `valley.*` keys. Plus the
standing review: has manifest-drift bitten? Decide the directory
split with evidence, not aesthetics.

**FW6 · The second game pulls (posture, not a rung).** Build nothing
speculative beyond FW5. The next real game's actual wants — a
different climate, a different palette, no interiors — drive profile
v2 and whatever the framework genuinely lacks. The second game is
the framework's first honest test; let it pull.

## The fence (do-not-build)

- **No engine-in-engine.** The framework is game code — autoloads,
  modules, shaders, one gdext kernel. It never abstracts over Godot
  (no GameBase class trees, no scene-graph wrappers). Anything
  wanting engine patches goes to the fork law's ladder, which
  already prices it: *"anything achievable as a module, GDExtension,
  shader, or autoload stays OUT of the patch set."*
- **No versioning bureaucracy.** No semver, no changelogs, no
  compatibility matrix, no deprecation policy. Provenance = shas;
  rev = recomputed; git history is the audit trail. The library
  already proved this is enough.
- **No shared runtime anything.** No addon, no submodule, no symlink
  into `~/code/valley`. Copies, always. Five games, five copies.
- **No forced updates, never on a timer.** Offered, counted, taken
  deliberately. A game that never updates is a valid game.
- **No framework repo, no framework process.** Valley is the dev
  environment; the manifest is the extraction. If editing valley
  starts to feel like maintaining a framework, we've built the
  bureaucracy this fence exists to prevent.
- **No template DSL.** Per-game fill-ins are a project name and a
  handful of headers. The day the fill-ins want a template language
  is the day too much stayed in the scaffold.
- **No speculative generality.** No system gets refactored "for the
  framework" ahead of a second game's demonstrated want (FW6). The
  framework is valley's systems as they are, offered honestly.

## Open questions (kitchen table) ★

*2026-07-09, Nicco: all defaults; mygame is FW1's guinea pig.* (The
DESIGN_QUESTS §15 pattern — the leans below are the rulings. Where a
lean wasn't written, FW1 took the smallest honest posture: 1:1 clock
is the house physics; no name yet — "the framework" until something
sings; on this machine Strata reads the live `~/code/valley` checkout
(env `STRATA_FRAMEWORK_DIR` overrides; a pinned dist snapshot is the
ship posture, not the dev one); the machine visibly lives — the
firefly field rides FW1 as the hello-world agents until a creature
record lands; valley's gouache look is the default look; the firefly
ships as framework machinery; mygame is retemplated under the new
scaffold as FW1's acceptance test.)

- ★ **The 1:1 clock, for every game?** The sim contract ships as the
  framework's constitution regardless (catch-up, hour_tick, the soak
  law). But "time is 1:1, always" was a *valley* decision — is it
  the default posture of every Strata game, or a profile choice? The
  machinery doesn't care; the philosophy does. (Lean: it's the house
  physics — default yes, and a game that bends it changes one clock,
  not thirty systems.)
- ★ **The framework's name.** "Systems get names" (DECISIONS). The
  valleykernel rename rides FW4 either way; christen the whole thing
  at the table. Candidates welcome; "the framework" is honest if
  nothing sings.
- ★ **Snapshot vs live checkout.** Strata bundles a dist snapshot at
  build (stable, pinned) with a dev override reading `~/code/valley`
  live (Nicco's machine always has one). Which is the default on his
  machine — pinned or live?
- ★ **A hello-world creature?** Does a fresh game get one placeholder
  agent (an AgentSim + record proving the Understory breathes) or an
  empty bestiary? (Lean: one — the machine should visibly live.)
- ★ **The gouache look.** The paper theme, character_paint, the
  painterly water — the shaders are welded to the systems and ship
  with them, but the *look* is valley's art. Framework default look,
  with palette inputs moving to records (FW4), or should a new game
  choose a look at scaffold time? (Lean: valley's look is the
  default; divergence is honest hand-edits, visible in the lock.)
- ★ **The firefly.** Companion mechanic, valley-flavored, riding
  framework player code + input map. Framework verb or valley
  content? (Small, decides the pattern for mechanic-shaped code.)
- ★ **mygame's fate.** FW1's guinea pig — retemplate it under the new
  scaffold as the acceptance test, or scaffold fresh and let mygame
  rest?
