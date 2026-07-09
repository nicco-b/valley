# Status — read this first when resuming

*As of 2026-07-03 (day three: the deep-sim build-out — 1:1 real time,
real seasons/sun/moon, climate/flora/rumors/wildlife, SIM_ROADMAP Phase
A+B starts, and the GPU granular sand simulation; ~91 commits, all
pushed to github.com/nicco-b/valley). This file is the live state;
update it when things change. The doc map: [DESIGN.md](DESIGN.md) = what the game is ·
[FOUNDATIONS.md](FOUNDATIONS.md) = build plan & backlog · [DEV_GUIDE.md](DEV_GUIDE.md)
= how to work on it · [DECISIONS.md](DECISIONS.md) = settled questions ·
[STORY.md](STORY.md) = the story layer (memory/quests/arcs) ·
[IDEAS.md](IDEAS.md) = the drawer · [ASSETS_NEEDED.md](ASSETS_NEEDED.md) =
the human-made shopping list · [lore/](lore/) = canon (axioms pending) ·
`/CLAUDE.md` = conventions + gotchas for AI sessions.*

## ⭐ Session handoff — resume here (2026-07-09, the late arc): THE FRAMEWORK ERA + THE WATER RINGS AND REMEMBERS

**This extends the 2026-07-08 roof below — read this first, then that
one; the handoffs under them are the rooms.** `strata/docs/ONE_APP.md`
stays the cross-repo spine (its late-arc progress log + rewritten next
steps are the full ledger); this is the valley-side view of what landed
after the day officially closed.

- **S1 · everything that moves rings the water** (commit `8e6897c`,
  PLAN_SUBSTANCES's first rung): wildlife rings fords with the same
  stride that stamps sand (one water query per stride, 0.24µs), wading
  past belly depth throws the big splash, the swimming player tows a
  V-wake by stride parity (no RNG anywhere in the rung), rain rides
  per-m² rates so a calm sky rings nothing. Window doubled
  (128m @1024², texels stay 12.5cm, 0.070ms/step measured);
  `ring_posterize` paints the field read into bands. **S2 · foam
  memory** (commit `7ebf153` — Nicco's own session): the field is
  rg16f now — R height, G foam history; deposits past a 0.004m floor,
  TIME-based decay by law (6s is 6s at any frame rate), advection
  along swell + focus drift (breaker foam rides ashore, rivers tow
  their foam), the breaker band importance-sampled through SeaSwell's
  surf mirror. The flagged eyesores fixed: foam fades to painted
  stillness with camera distance; river mouths feather into their
  lakes. Both rungs presentation-tier; **soak fingerprint 2814434129
  unmoved, deterministic twice.** Next rung: **S3 floaters** (analytic
  buoyancy, 7.6µs each, never sim-coupled).
- **The map-zoom engine deadlock — found, fixed on BOTH sides, both
  upstream-worthy.** Forensics (commit `ebc2354`'s message is the
  writeup): `create_trimesh_shape()` on a streamer worker re-fetched
  arrays via a RenderingServer cross-thread `push_and_ret`; a zoom
  burst parks enough builders to fill the WorkerThreadPool
  low-priority lane (threads×0.3 = 5 on this machine); main, freeing
  a streamed-out material, waits on its pipeline-compile task queued
  LOW behind the saturated lane — waiter needs the lane, lane needs
  main's flush. Valley fix: build the ConcavePolygonShape3D straight
  from the arrays in hand (zero RS involvement; regression probe
  `tests/stream_deadlock_probe.tscn` hangs pre-fix, passes post-fix;
  plus `6c2e5ad` — `_exit_tree` waits out in-flight worker ids).
  Engine fix: a **24-line WorkerThreadPool patch** (fork
  `d6462352f3`: a hard wait on a task starving in the low-priority
  admission queue promotes it). **Strata's shipped pane engine is the
  `fork/pane-4.7` build now** (F1 + presentsWithTransaction + WTP);
  the `.pre-wtp` and `.pre-f1` xcframework rollbacks sit gitignored
  beside it — deleted after the M5 soak week.
- **FW1 · the framework era** ([PLAN_FRAMEWORK.md](PLAN_FRAMEWORK.md)
  is the plan AND carries the ★ rulings — 2026-07-09, Nicco: all
  defaults; mygame the guinea pig): **valley IS the engine.**
  `framework.json` v0 names the world spine — **90 files across 18
  systems** (Chronicle/Almanac/Loom/Elements/the whole Watershed + the
  parse-time closure); `scripts/framework_dist.sh` audits (census +
  rev) or exports a dist tree. Strata's scaffold now COPIES these real
  files (the 1600-line string-writer died, strata `b00ba04`), stamps
  `framework.lock.json`, and **`strata-cli framework update <dir>`
  exists** (retemplate is an alias): added/updated/current/modified
  per the lock — modified files reported and kept, never clobbered.
  Two content-empty seams fixed so the machine boots with empty rooms
  (`3a41f44`, `c80026d` — kit placeholder scenes, scatter tables,
  watershed record, swarm paintings all optional; valley behavior
  identical, fingerprint unmoved). `~/Desktop/mygame` is the first
  child — retemplated as the acceptance test, its already-shipped
  hydrology.json now real rivers/lakes with the walker standing on
  60m relief (the strata E2E boots it headless).
- **The rev FLOATS — that's the design, not a bug:** the framework
  rev is computed (sha256 over sorted path+sha lines, 12 hex), never
  stored, so **the live checkout's value moves with every hand edit
  or commit to a manifest file** — it was `c1cb32b19219` at FW1's
  commit, `aad981f8ef1e` when mygame was stamped, and derives
  differently again today. The invariant is stability across runs on
  the same tree (`framework_dist.sh` always derives the same rev from
  the same files, both sides of the seam) — never a pinned number.
  Compare lock-vs-live by running the audit, not by quoting a rev
  from a log entry. (Same law as the soak fingerprint: floats with
  live edits, deterministic per state.)
- **Housekeeping:** `~/code/valley-p2` is REMOVED — the parked P2
  eye-check fixture is obsolete now that the water is live in games
  (mygame's water tour, in ONE_APP's queue, absorbs those checks).
  The spawn-on-land test wart below is still open
  (`agent/spawn-on-land`, unmerged). This roof supersedes the
  2026-07-08 roof's "in flight: substances" and valley-p2 lines.

## ⭐ Session handoff (2026-07-08, end of day): THE GAME GREW A STORY LAYER, INTERIORS, AND FABRIC

**This note is the day's roof — the handoffs below it are the rooms.**
The Q1+Q2 handoff (next section) has the Teller's full detail; what
follows is everything else that landed around and after it, so the
stack reads as one day. `strata/docs/ONE_APP.md` stays the cross-repo
spine (its second-half progress log + next steps were rewritten to the
true end-of-session state).

The game now has:

- **Quests — the Teller** (Q1+Q2, the handoff below;
  [DESIGN_QUESTS.md](DESIGN_QUESTS.md) is the design ledger). Its §15
  is RULED (commit `8ec2280`, Nicco away-mode): ★1–★6/★9 BLESSED as
  working defaults, ★4 amended to both scene-initiation modes chosen
  per-scene; **★7 (direction vocabulary), ★8 (deadline tone), ★10
  (the Main thread) stay OPEN** at their gates Q7/Q8/Q10. Next rung:
  **Q3 the hooks door**. **The soak fingerprint moved BY DESIGN with
  Q2: 4027936959 → 2814434129** (journal.*/choice.* ride the digest
  whole) — same-day sections below correctly report the old number;
  the fingerprint still floats with live re-imports until a world is
  blessed.
- **Interiors — the Threshold** (I1, commit `09642a1`;
  [PLAN_INTERIORS.md](PLAN_INTERIORS.md) is the plan): a door is a
  placement row that learned one key (`"door": {"interior": id}`);
  the pocket instantiates +1500m over its own door in the SAME running
  world behind a fade — no scene change, every autoload keeps ticking,
  the 1:1 clock holds (step out into a later sky). First proto-dungeon
  `data/interiors/smugglers_cellar.json` (47 rows of ruins/* +
  under/*); save v2 with honest fallback; the sun kept out by cull
  layer; presentation gates read the ONE flag — the weather SIM is
  never told. Next rung: **I2 the hand inside** (InteriorRecords, the
  Toolkit targets the active book — unblocks Strata's L11
  kit-bashing). Soak unmoved.
- **Fabric — the one-wind law** (F1 banners, handoff below; + F2
  spring bones, commit `e3d5e44`; [PLAN_FABRIC.md](PLAN_FABRIC.md) is
  the plan): tails and ears hear the ONE wind — FabricSpring
  (SkeletonModifier3D over the engine's SpringBoneSimulator3D)
  auto-adopts the chains a rig carries (hound tail, fox ears) and
  feeds `external_force` from Weather; gouache-tuned, damped and
  chunky, influence fades by 60m. Presentation tier, soak digest
  untouched. Next rungs: F3 cloaks (blocked on bodies), **F4 the
  village flutters** (card flag alone — gated on the village kit).
- **Placement editing v2** (handoff below) **and, riding its stable
  ids, P4 overrides EMISSION** (commits `6abe9e1` emitter + `cb480d1`
  probe): the game maintains `data/overrides/overrides.json` (format
  1 — every placed record by id + the hand-terrain layers as
  deflate_f32le blobs with their frames), emitted on the stroke-quiet
  flush / F5 / exit; `overrides status` link verb. Strata consumes it
  at bless + Send; the round-trip probe (`tests/overrides_probe.gd`)
  proved a +12m pen knoll and two records ride a full seed re-roll,
  hand delta identical on both sides of the seam to the centimeter.
  Hand work is DATA the re-roll respects now.
- **The chrome contract v2** (commit `a86207a`): the Toolkit fully
  drivable from Strata — `toolkit on|off` (F1 over the wire) and
  `toolkit undo`; `hud off` is TOTAL (every label dark, scene-tested)
  with HUD.notify rerouted to the `notices` drain verb; `panel` and
  `inspect` answer machine-readably; `toolkit status` carries the
  profile's real terrain names (`biomes=`) + `cats=` + `river=`. When
  Strata's chrome drives, the game view shows nothing but the world.

**In flight as this is written: the substances plan** — a
water/snow/sand/particles investigation on branch `plan/substances`
(worktree `~/code/valley-substances`); read its verdict before
touching anything wet, frozen, or granular. **Nicco's eye-check
queue** (banners/tails in a storm — regenerate the untracked GLBs
first, the F1 note below has the command; the Threshold; the map; the
P2 water checks — the parked `~/code/valley-p2` worktree holds the P2
fixture state, remove it after) lives in ONE_APP's next steps, with
the open-★ table calls beside it.

Known wart for fresh checkouts: the spawn-on-land unit test only
SKIPS when a live tile is cached — a fresh worktree has no tile, so
`test.sh` fails one test ("spawn is on land") against the committed
procedural world. Pre-existing, documented in the map handoff below;
the fix is in flight on `agent/spawn-on-land`.

## ⭐ Session handoff (2026-07-08, worktree agent): THE TELLER'S FIRST LATCH (Q1+Q2)

**DESIGN_QUESTS Q1 (the monotone core) + Q2 (the robustness spine)
landed.** The `Story` autoload (`game/story/story.gd`, the Campfire —
★9's proposed table name is "the Teller"): loads `data/quests/*.json`
(format 2, **stages-not-steps — ★1 blessed at the table 2026-07-08**
("defaults for now, may change later"); the shape swap stays contained
to records + the loader in case that changes), builds the condition index
by mechanical key extraction, and latches `journal.<quest>.<stage>` =
`{day, season, prose}` — append-only, sealed once, the memoir rides IN
the save. No quest state machine, no current-stage variable; frontier
is derived; failure/expiry are terminal stages; nothing un-happens.
Repeatable errands cycle under `journal.<id>.<cycle_day>.*` with
cooldown re-arm. Conditions v2 (`game/state/conditions.gd`): closed
table (§5, all of it — flag/eq/gte/lte/item/item_tag/season/
time_between/since/knows/weather; told/opinion_band reserved-fail-
closed; custom fails closed until Q3's hooks door), composition
all/any/not (bare dicts still AND), `keys_of()` extraction, and the
schema `lint()`. Mirrors added: `time.hour` (GameClock, solar int,
hourly — B9). **"The Dry Spell" v2** (`data/quests/dry_spell.json`) is
the proving errand: a scene test seeds real FloraLife vitality through
the save door, real hourly ticks mint `valley.parched`, the root
latches off the mirror, forced storms rain it green through
`advance_hours`, the terminal latches in catch-up, both entries read
in the minimal J screen (`game/story/journal_ui.gd`, J toggles,
Threads + Remembered, prose-first, zero markers). Notification
loudness is ★3-as-ruled: root and terminal latches notify, middle
stages fill the diary silently. Q2: the **quest
harness** (`tests/quest_harness.gd` + `tests/quests/*.test.json`,
tests-as-data: set/advance_hours/expect_reached/expect_not_reached/
expect_objective/expect_cycles/expect_gap/expect_minted/
expect_scene_requested, inline synthetic records allowed) and the
**linter** (`game/story/quest_lint.gd`: rooted/acyclic/reachable,
no-wedge, required-stage skip-proof, terminal prose, story-terminals-
mint, closed-language rows, repeatable-only-errands, sibling-terminal
disjointness, $role refs, scene/dialogue/hooks targets, spine-gating
vs `data/story/recurrent.json`) — both a test.sh phase; nine
deliberately-broken lint probes prove the linter bites. **Soak
stance**: `journal.*`/`choice.*` ride the fingerprint whole plus an
always-present section header (so silently dropping the namespace
would move the digest) — fingerprint moved 4027936959 → 2814434129,
twice-identical; the playerless soak also gained the invariant that
only errand-tier quests may latch and no `choice.*` may seal. Link
verb added: `state set <key> <value>` (B12's forcing door). Deferred
to their rungs: hooks/QuestRun (Q3), roles (Q4), dialogue (Q5), scenes
assembler (Q6 — stage scene ids are logged as requests so the harness
asserts them), expire (Q8), desk verbs beyond `state set` (Q9),
threads/world-flips (Q10 — thread lint already speaks). `mint` records
into an in-memory log (harness-visible) until S1/B3's fact channels.
`weather.storminess` mirror deliberately NOT added (focus-dependent
presentation value today; needs a sim-owned menace mirror when a quest
first wants it).

**PLAN_FABRIC F1 landed** (shader tier — the cheapest visible win).
`fabric_wind.gdshader`: vertex-displaced world cloth reading the one
wind truth (`wind_strength`/`wind_dir` globals; fabric never invents
wind) — pin weights painted in vertex COLOR alpha (a=1 rigid, freedom =
1−a doubles as distance-along-cloth), an arc lean whose w² curve keeps
calm barely breathing and lets a gale slam the top end, two sine
octaves max, flap fading with camera distance INTO the leaned pose (a
far banner still points with the weather), and the `flap_posterize`
knob (held poses per wave cycle; **shipped at 4** from the probe A/B —
the quantized phase also chunks the fold into a painted kink; 0 =
smooth sine). Fragment = the character_paint gouache treatment over
vertex-color paint. Cards grew optional `"wind": "fabric"` +
`"wind_hang"` (meters at freedom 1); the Kit applies the override at
placement (`_dress_placeable`, both scatter and records paths, one
shared material per slot). Slots wearing it: `props/textile`,
`props/camp/tent` (regenerating also RIGHTED the old cone — it was
apex-down underground), `props/nautical/net`, and the new
`props/textile/banner` (3 variants, pole + crossarm + hung pennant —
the first placeholder that visibly hangs). `gen_meshes.py` is now
repo-relative, grew `paint_pinned` + `--only <slot>` partial refresh —
**regenerate the untracked GLBs** (`python3
tools/placeholders/gen_meshes.py --only props/textile --only
props/textile/banner --only props/camp/tent --only
props/nautical/net`) or old flat binaries stay wind-still (alpha 255 =
pinned; graceful, not broken). Toolkit world panel grew the FABRIC
line (flagged slots · dressed count · wind echo); scene test
`_test_fabric`; probe `tests/fabric_probe.gd` (FAB_WX=calm|windy|storm,
FAB_POST=n, opengl3 + Movie Maker like sea_probe) — shots at
/tmp/fabric_*.png. Presentation tier: no state, no WorldState keys,
soak untouched and bit-stable (4027936959 twice, same digest as before
F1). Next rungs: F2 tail/ears spring bones; F4 applies this shader to
the village kit by card flag alone when it lands.

## ⭐ Session handoff (2026-07-08, worktree agent): PLACEMENT EDITING V2

**The hand edits what it placed** (Creation Kit audit #1). In PLACE
mode RMB picks the nearest record within 4m of the ground hit (cyan
ring marker + a HUD SEL line: kit · id · yaw° · ×scale); RMB on empty
ground / Esc deselects. G moves the selection to the cursor — the
ground-relative law holds (ground_dy rides, so it seats on the NEW
ground + the same offset, and the record migrates cell files across a
boundary). R rotates 15° (Shift reverses), , . scale ×1.08 steps
(clamped 0.25–4), X deletes THE selected record (no selection: the old
LIFO remove_last under the cursor survives as fallback). Every record
now carries a stable `id` (minted at add; legacy rows are named on
their next save or the moment they're picked) — selection, the
one-deep PLACE memento `{op, cell, id, before}` (place/edit/delete all
Z-revert targeted, by id, bit-exact), and P4's overrides emitter all
hang on it. Placement-time yaw/scale randomization stays as the
default dressing — but it's data now, editable after. Edits
(CellRecords.update) defer their disk write to the stroke-quiet flush
/ F5 / exit (place/delete stay write-through per click); new InputMap
actions (place_move/rotate/grow/shrink/delete) surface in `toolkit
keys` automatically; link_state carries sel_* for a future Strata
inspector (no new link verbs). Scene test `_test_placement_edit`;
probe `tests/placement_probe.gd` (needs `--rendering-method
gl_compatibility` on this box — stock Metal Forward+ crashes at boot).
Soak untouched and bit-stable (4027936959 twice).

## ⭐ Session handoff (2026-07-08, worktree agent): THE MAP IS THE ORBIT

**M is a real 3D view now** (Nicco: "a real 3d view of the map, sort of
like the orbit; weather must not obstruct it"). The flat pitched-ortho
chart + its terrain-shader elevation palette (`map_view` global) are
RETIRED. The orbit machinery is one shared class (`game/world/
orbit_rig.gd`) ridden by BOTH the Toolkit's viewer posture and the map
— open frames the whole tile, LMB-drag orbits, wheel/pinch zooms, WASD
pans, Esc/M closes, player frozen (a camera swap, no second viewport).
Weather exemption is RENDERING-ONLY: the map camera wears the chart air
(world env minus fog/volumetrics + a solar-and-weather-scaled ambient
floor, so midnight and storm noon stay readable; the dimmed sun stays
as the honest hint), Atmosphere hides its FX + cuts stuck lightning,
weather_fx dust gated. Water stays visible (the far sea disc stretches
5x under the map so beyond-tile reads as ocean, not far-LOD slabs).
Player marker grew a heading wedge; compass N is a needle (the view
rotates). Scene test `_test_map`; probe `tests/map_probe.gd`
(MAP_WX/MAP_HOUR/MAP_DIST/MAP_SHOT; map_fog_probe folded in). NOTE:
the spawn-on-land unit test now SKIPS when a live tile is cached —
world_v1 floods (0,0) to -123m, so a fresh New Game would spawn in
deep sea; spawn wants to ride the import (bless-time item). Soak
bit-stable throughout.

## ⭐ Session handoff — resume here (2026-07-08): STRATA IS THE ONE APP

**The full state + progress log + next steps live in
`strata/docs/ONE_APP.md`** (progress log section) — the short version:
- **The game runs INSIDE Strata** (the Game pane) on **our engine
  fork** github.com/nicco-b/godot (`swiftgodotkit-4.7` = official
  4.7-stable + embed patches; fork law v2: patch-carrying, one-day
  rebase budget, Tier 2 lets the game ship on fork builds when the
  first real engine want lands — the GDScript worker-thread VM fix and
  precision=double are the queued candidates).
- **Valley is a Strata document**: `valley.strataproj` (committed
  here) — Strata opens it, restores the session, scans the asset cards
  into its Assets tab (real/synth ledger). New Game in Strata
  scaffolds a fresh game folder — "many games" is structurally real.
- Valley-side landings this arc: P0 direct tile import (pens →
  override layer, guide path deleted), StrataLink autoload (the live
  link; STRATA_LINK_PORT env), W1 ocean swell (SeaSwell + Gerstner —
  storms send rollers ahead of their rain), paper boot splash (engine
  logo retired), **P2 valley half (2026-07-08)**: the export's
  `hydrology.json` lands as real water at import — rivers as no_sim
  records (`data/water/rivers/hyd_*.json`, real catchment_m2; the
  region tier breathes each against its OWN baseflow, idle ~0.35),
  the LAKE_MAX(24) largest lakes at their fill elevation (basin depth
  0 — the depression is already in the tile; levels ride a new region
  LAKE tier, off the soak digest), knickpoint waterfalls foaming the
  ribbons full, and W2 bathymetry (CUSTOM0, per-surface level) +
  fetch-scaled swell on lakes with real fetch so storm chop shoals
  and dies at their shores. hyd_* records are gitignored cache,
  cleared each import; pre-P2 exports load exactly as before. The
  committed `valley.strata` gained the hydrology stage (old docs
  never migrate it in — flag for the Strata side). New probes:
  `RIVER_SHOT=fall|hydlake` in river_probe.
- **Next (Nicco's want): P8 the live viewport** — the Strata preview
  BECOMES the game view (auto-send bakes into the pane, time-of-day +
  weather controls in Strata; new `time` StrataLink verb must route
  through GameClock.advance_hours — the sim contract's one door). Then
  the **regeneration-hazard defenses** (ONE_APP has the full writeup:
  geology-then-dress law, bless-time diff report, ground-relative
  placement re-seating here in valley, P4 overrides round trip).
- Soak stays bit-stable-across-runs; the fingerprint floats with
  Nicco's live re-imports until he blesses a world (then pin).

## ⭐ Session handoff — (2026-07-07, night): ONE_APP P0 landed

**The seam fix is in — Strata exports walk in-game with ZERO re-erosion.**
(`strata/docs/ONE_APP.md` P0, now marked done there.)
- **Direct import:** `tools/strata/import_world.gd` copies the export's
  `height.exr` BYTE-IDENTICAL into `data/terrain/tiles/baked_world.exr`
  (manifest sha verified at import AND re-verifiable against the live
  cache forever; the region record carries source/sha/seed/sea_level
  provenance). No guide roundtrip, no droplet re-erosion, no ±12m
  detail noise. Probed bit-exact: in-game `height()` == the export's
  meters at every sample. Sea level + biome map ride the same manifest
  (one sea-level source). `import_and_bake.sh` is now a single import
  call (name kept for muscle memory); `bake_and_walk.sh` unchanged in
  use.
- **Pens re-scoped onto an override layer:** the blessed tile is
  READ-ONLY — the TERRAIN pen (flyover) and the map's P pen now paint
  `data/terrain/tile_override.exr` (additive METERS, 16m/px, the
  sculpt-EXR pattern at macro scale), composited over the tile at boot
  and on stroke-quiet commit (scoped recomposite — no kernel change,
  the kernel keeps sampling composited tile data; pens no longer need
  the kernel at all). F5/exit saves the override + sidecar meta only.
  Z restores the pre-stroke override bit-identically (scene-tested,
  skips honestly on checkouts without the tile cache).
- **The guide path is DELETED:** `WorldBake`, `tests/bake_world.gd`,
  `tests/propose_rivers.gd` (it re-eroded a stale guide for its flow
  map — river proposal returns in ONE_APP P2 as Strata's
  `hydrology.json`). `data/world/elevation_guide.exr` + `guide.json`
  are dormant on disk (Nicco's in-flight copies left untouched) —
  nothing reads them; delete when convenient. The Blender terrain trip
  (`assets/blender/terrain/`) rode the guide and is dead with it
  (DEV_GUIDE updated).
- **Not run for him:** the LIVE import of `~/Desktop/world_v2` (he was
  actively re-exporting at 20:16 — and his `data/world/biome_map.png`
  differs from a fresh remap of that export, so it may carry hand
  strokes a re-import would overwrite). **To land his world seam-free:
  `tools/strata/import_and_bake.sh ~/Desktop/world_v2`** — one command,
  sub-second, hot-reloads if the game is running.
- Soak green + bit-stable (fingerprint 3649289887 — still floats with
  his live bake until the world is blessed; the invariant that holds is
  two-run stability). All tests green.
- **Then, same session: ONE_APP P1 (Nicco's pick) landed in the strata
  repo** — one ⌘Z stream for params + strokes (slider sprees coalesce),
  A/B compare (⇧⌘B hold / ⌘B toggle), **Bless** (⇧⌘E or `strata-cli
  bless`: full-res bake → `worlds/world_vN/` beside the doc +
  `registry.json` blessed pointer + frozen.landform locks), and
  `scripts/make_app.sh` → `dist/Strata.app` (.strata double-click).
  Blessing his real world now gives the soak its pinnable baseline.
- **Then P3, the live link (both repos):** `StrataLink` autoload —
  localhost line protocol, debug builds (ping/status/reload_world/
  teleport/screenshot/weather; `STRATA_LINK_PORT` env for a second
  instance); Strata gained Play / ⌥-click Walk Here / **Send** (bake →
  P0 direct import → live reload). Cross-process verified; the GUI
  loop needs Nicco's eyes (⌥-click mirror gotcha noted in ONE_APP P3).
- **Then PLAN_PHYSICS W1, ocean swell (worktree agent, landed
  49714dc):** SeaSwell + 4 Gerstner components — storms send rollers
  hours ahead of their rain (see PLAN_PHYSICS W1 done-note). Soak
  bit-stable; the fingerprint now floats with Nicco's live re-imports
  by design.
- **Then the P3.5 embed spike (strata `spike/EmbedSpike/`): mechanism
  proven, gate FAILED on 4.6-vs-4.7** — Valley boots inside a SwiftUI
  pane (Forward+, 120fps, StrataLink answers from inside the pane!)
  but the 4.7 kernel refuses on 4.6, the 4.7 script-class cache won't
  load (parse cascade), CoreAudio hangs at embedded start. Live view
  v1 (child process) stands until a 4.7-matched libgodot exists —
  findings + rerun instructions in `strata/docs/ONE_APP.md` P3.5.

## ⭐ Session handoff — resume here (2026-07-07, later): the two plans

**Nicco's direction (this session): Strata becomes THE ONE APP** — the
game builder (worlds + assets + projects + bake/bless + launching the
game as its live view; places/moments stay in-engine via the Toolkit,
which reorients to "Strata's hand inside the live sim"). The full
decision + phased plan: **`~/code/strata/docs/ONE_APP.md`** (P0 = the
seam fix — Strata height.exr → the baked tile DIRECTLY, killing the
double-erosion that currently re-droplets every Strata export through
the old guide path; do P0 before anything else). Second track, this
repo: **[PLAN_PHYSICS.md](PLAN_PHYSICS.md)** — sand/water realism
(ocean swell → breakers → swash/wet strand → tier-3 sediment coupling
that erases beach footprints; sand response/wind/mud). The
next-session prompt to paste is at the bottom of ONE_APP.md.

## ⭐ Session handoff — resume here (2026-07-07): the de-valley wipe

**Strata is the world; the old hand-authored valley content is GONE.**
The "wipe-clean cascade" the last session reverted (it broke 14 tests +
Climate's pond thermometer) is now done properly as a scoped refactor —
full clean slate, tests rewritten to the new world (Nicco's call this
session). All on main, `./scripts/test.sh` green, soak green + deterministic.
**The soak fingerprint FLOATS right now**: the old 1333567381 died with
the NPCs leaving the digest + REFERENCE moving to world-center, and the
new value tracks the live Strata bake (Climate's wet grid reads the
terrain, and the terrain changes every time Nicco re-imports). The
invariant that holds is bit-stability across soak.sh's two runs; pin a
baseline number again when the world is blessed + committed.

- **Deleted content (data):** `data/{npcs,dialogue,quests,caravans,
  roads}` · `data/water/{pond.json, rivers/brook.json, rivers/pen_*.json}`
  (kept `sea.json` = Strata-synced sea level, and `watersheds/home.json` =
  Hydrology's operating frame) · all 9 authored `data/cells/*.json` · the
  37 old hand-authored archipelago region records (kept `baked_world.json`
  = the Strata tile).
- **Deleted/gutted code:** `game/npc/`, `game/dialogue/`, `game/quests/`,
  `game/world/caravans.gd` + `caravan_body.*`, `game/world/waypoint_graph.gd`;
  autoloads `Dialogue`, `Journal`, `Caravans`, `WaypointGraph` removed from
  project.godot; `valley.tscn` lost NPCManager + the Shrine landmark +
  PondStone pickup (both at dead old-valley coords). `Conditions` (the
  shared condition LANGUAGE) survives — WorldState uses it; a future
  quest/dialogue engine will speak it again.
- **Rewires:** `Climate.REFERENCE` (70,-310 pond clearing) → **world center
  (0,0)** the climate thermometer; Nav dropped its road far-tier (straight-
  line fallback only); Hydrology already tolerates empty water (all its
  water access is `for`-over-array). map_screen MARKS emptied, NPC labels
  dropped. Toolkit world panel lost its CARAVANS line (sim inspector kept —
  wildlife still has `sim_debug`).
- **Tests rewritten to the new world:** `scene_tests.gd` — `_test_dialogue`/
  `_test_quests` → one `_test_conditions` (the surviving language);
  `_test_water`/`_test_hydrology`/`_test_water_field` reworked to the sea +
  guard contract (home_guard is 0 in the protected interior, 1 in the open
  sea, so the guarded home reads dry and the outer world is sea);
  `_test_roads`/`_test_caravans`/`_test_rumors` deleted; `_test_long_memory`
  → `_test_wear` (kept the desire-path half). `soak.gd` drops the NPC
  instantiation/invariants/fingerprint; `ui_probe.gd` drops the journal shot.
  **The climate-v2 probes are now WORLD-AGNOSTIC** (they were pinned to the
  retired Range/valley coords and started failing as Nicco's live bakes
  reshaped that ground): the rain-shadow test finds the world's tallest
  peak on a coarse grid, blows the wind in off the nearest cardinal sea,
  and seats the lee at an exact ORO_UP probe distance (1300m) — skipping
  honestly when no wall tops its lee by 400m; the maritime test finds one
  fully-inland and one open-sea grid point and compares those. Both found
  their marks on the live bake (no skips fired).
- **Review-round cleanup:** orphaned `shrine.tscn` + the two old-valley
  authored cell scenes (`game/world/cells/cell_0_0/-1.tscn` — placeholder
  boxes at dead coords) deleted; dead `journal` input action removed from
  project.godot; DEV_GUIDE keymap (J/journal, talk) + "Add an NPC" recipe
  and data/README.md npcs section rewritten (also retired two stray
  "god-mode" name usages there).
- **NOT committed here:** `data/world/{biome_map.png,elevation_guide.exr,
  guide.json}` are Nicco's in-flight Strata bake — left for him to tune +
  bless. **Next:** rebuild the world's life on the Strata terrain — new
  inhabitants/quests placed against the baked biomes, water proposed from
  the Strata flow, not the retired hand-authored geography.

## ⭐ Session handoff — resume here (2026-07-06, later)

**The placeholder drop landed + Toolkit Phase 1 (cards → palette).** Ran
PLAN_TOOLKIT_AND_PLACEHOLDERS.md Phases 0 + 1; all on main, tests +
soak green (fingerprint 1333567381 unchanged).
- **Phase 0 — drop on disk, NO LFS (Nicco's call this session).** 258
  synth billboards (86 slots) + 345 static GLBs (112 slots), each with a
  `.card.json`, copied to `assets/paintings|models/` at their real paths;
  generators → `tools/placeholders/`; contact sheets there too. Binaries
  are gitignored (**on disk, untracked** — pending the real LFS decision);
  the tiny **cards ARE tracked** as the source of truth. Import clean (605
  steps), billboards inherit mipmaps-off/lossless automatically. On a fresh
  clone the cards exist but binaries don't — regenerate with
  `tools/placeholders/gen_*.py` or copy the drop; loaders tolerate missing.
- **Phase 1 — cards are the palette.** New **Cards** autoload (the
  Chronicle, `game/data/cards.gd`) scans `assets/**/*.card.json` → 198
  slots / 100 placeable meshes / 11 categories; `resolve`/`variant_for`
  hand back the RESOLVED file (deterministic by position). Toolkit world
  panel (O) grew a **CARDS** line = the real/synth ledger. Toolkit **PLACE**
  now reads its palette from Cards ([ ] step slots, 1-9 jump categories);
  placement writes the resolved `.glb` FILE into the cell record, never the
  slot, so retiring a placeholder never moves it. `Kit.scene_for()` loads
  either a res:// file or a legacy ENTRIES id (old placements keep working).
  **Ground cover per biome**: 38 `data/flora/gc_<biome>_<slot>.json` species
  from the drop's ground sets — the 8 biomes each grow their own cover
  through the existing scatter; the 3 SVG placeholders (dry_tuft/pebbles/
  bloom_tuft) retired to painted PNGs.
- **Then, from Nicco playing it (color + "generate across the map"):** synth
  GLBs bake color into VERTEX colors with no PBR material → rendered grey;
  `_dress_placeable` flips vertex_color_use_as_albedo on + hides the visible
  `-col` hull (kept its StaticBody). **Auto model-scatter** (`data/scatter/
  props.json`): rocks/cacti/shrubs/trees/cliffs auto-dress the world by biome
  (category groups draw every non-gated Cards slot — new cards join free).
  Then the asset-consumption sweep: **blooms → 7 wildflower species**
  (`data/flora/bloom_*.json`); **swarms → 5 ambient emitters** in
  atmosphere.gd (butterflies/pollen/gnats/embers/gulls, biome+time gated);
  **decals → per-cell projected ground detail** (`data/scatter/decals.json`);
  **water plants → lilies + reeds at the water** (`data/scatter/
  water_plants.json`, keyed off water_surface_base). All presentation-only,
  soak 1333567381 throughout.
- **Consumption map (which of the drop is live):** ✅ meshes rocks/cacti/
  shrubs/trees/cliffs (scatter + place); ✅ ground cover (38) + blooms (7) +
  water (6) as flora/aquatic; ✅ swarms (5) + decals (5) ambient. **Placement-
  only by nature** (their home is the PLACE palette, Phase 3 makes it fluent):
  props (16), arch (27), landmarks (6), chars (9), wildlife (15) — buildings/
  hero/clip-less stand-ins, NOT auto-scattered on purpose. **Deferred:**
  foliage 2×2 clump sheets (need per-instance UV cutting + a windowed check);
  sky (a shader today) + horizon (distant backdrop); forage-item pickups
  (blooms/fruit/roots → tie to the Foraging skill, not yet wired). **Git LFS
  still unresolved.** Scatter density lives in `data/scatter/*.json` `attempts`
  (restart to re-read — not hot-reloaded yet).
- **Next: PLAN Phase 2** (cross-pen undo/history — generalize sculpt's
  Z-undo across sculpt/terrain/biome/river/placement), then Phase 3
  (placement tools: multi-select, duplicate, scatter brush — how the 345
  meshes reach full-treatment density) + Phase 4 QoL.

## ⭐ Session handoff — resume here (2026-07-06)

**Shipped this session** (all on main, tests green): river-proposal
rebuild + drape + rapids; per-region hydrology (gen rivers breathe);
flow maps + golden-hour water palette; the fill-channels water
experiment (debug K, off); NPC AgentSim port (Phase A COMPLETE) +
caravan embodiment; streamer fixes (finish budget, velocity lookahead
union — no vanishing terrain); the **map generator** (LandformGen:
sketch/painted-guide → erosion → world, FILE-driven — in-game map
drawing was removed on purpose); Toolkit world-pens moved into the
flyover; scoped live terrain bake.

**The big planning artifacts:** [RPG_WEIGHT.md](RPG_WEIGHT.md) — the
plan for real RPG weight (consequence contract, standing on the rumor
rails, one-timeline saves, 11 sim-forward unlocks). Nicco wants a
whimsical/magical feel, friends AND enemies, decisions that hold
(memory: valley-wants-rpg-weight, valley-tone-whimsy-voice).
**[STORY.md](STORY.md) (2026-07-06, from Nicco's ideas)** — the story
layer: authored quests on sim delivery ("never ask the ground to
mean"), Memory v2 (erosion/rehearsal/sediment/legend replaces
MAX_RUMORS and R1's standing scalar — bands survive as a derived
reading), three quest tiers (Errands/Stories/Arcs), scenes-as-requests
(canon: the scene WAITS for the player; hold counts missed attempts),
NPCs age normally, fossils, rainbows, S1–S5 build order. Its ★s join
the kitchen-table queue; known bug it flags: quest steps conditioned
on `npc.X.knows.*` can un-complete when the rumor FIFO forgets — seal
steps (latch) with or without the rest.

**Kitchen-table ★ decisions blocking real writing** (see RPG_WEIGHT +
DESIGN Open Questions): the world axioms · the VOICE question ("lots
of voiced dialog" reverses text-only canon — proposed invented
spoken language) · progression cost model · death fiction · adopt the
Consequence Contract into DESIGN.md.

**Execution plan ready:**
[PLAN_TOOLKIT_AND_PLACEHOLDERS.md](PLAN_TOOLKIT_AND_PLACEHOLDERS.md)
(2026-07-06) — land the synth placeholder drop (258 billboards + 345
meshes w/ asset cards, in Nicco's Downloads; forces the Git LFS
decision), then Toolkit build-out: cards→palette, pens+undo,
placement tools, QoL. Spin up a session on it directly.

**Next-move options** (Nicco's call):
  1. **RPG spine** — R1 standing on the rumor rails (~2 days, pure
     code, no ★ gate; the multiplier for every future quest). The
     unbuilt half of "best RPG ever."
  2. **Generator polish** — polyline ranges in LandformGen (mountain
     chains, not radial mounds) + the model-scatter records so
     generated worlds auto-dress with rocks (answers "do I hand-place
     rocks": no).
  3. Cheap debt: Toolkit `summary()` sweep (18 autoloads missing it) +
     a shared `Focus` helper (audit findings); Git LFS chore.

**In Nicco's checkout, uncommitted (HIS authored play — triage, don't
let a session clobber):** hand-drawn rivers `data/water/rivers/pen_*.
json` (×14), placed `data/cells/cell_*.json`, and edited
`elevation_guide.exr` / `biome_map.png` / `sketch.json` / `edit_layer.
exr`. Commit the keepers; the guide/biome/edit_layer are also the
runtime-write footgun the audit flagged (LFS/decide-per-file pending).

**To generate a world from a file:** edit `data/world/sketch.json` (or
paint the guide EXR), then `godot --headless --path . -s
res://tests/gen_world.gd`. Runbook + keymap in DEV_GUIDE.md.

## What exists and works (all tested; run `./scripts/test.sh`)

**World** — streamed 128m cell grid (threaded generation); one height
function feeding near terrain, far-terrain LOD to the horizon, and the map
("if you can see it, you can go there" — the distant mountains are real);
authored valley landform (spawn → pond ~310m → shrine ~620m); Toolkit
sculpt layer (EXR); painterly terrain shader (height/slope bands, wind
ripples, sun glints); scattered flora from her 3 paintings + dense
ground-cover stratum (placeholder SVGs); **water bodies as records**
(`data/water/*.json` lakes = basin + surface height; `rivers/*.json`
rivers = node polyline with per-node width + surface; Terrain carves
basin/channel and answers `water_surface()`, ribbon/disc surface meshes
built from records, painterly flow shader scrolls downstream — a new lake
or brook is one JSON file; swimming, navmesh carving, moisture floors,
flora/cover submersion all read the same records; first authored brook
feeds the pond); **whole-watershed hydrology** (DECISIONS 2026-07-04:
tier 1 of 3 — the Hydrology autoload flow-routes the entire valley once
at boot (priority-flood pit filling + D8 on a 256² grid, on a worker
thread) giving every river/lake its real catchment, then runs an hourly
water balance forever: storm runoff scaled by ground saturation,
snowmelt, spring baseflow, river reservoirs, lake evaporation/outflow;
water surfaces ride the live levels via `Terrain.water_surface()` while
cell generation reads the authored base — the pond visibly swells in
storms and drops through droughts, the brook's flow speed tracks real
discharge, fords open and close unscripted; state is per-basin scalars
on the sim contract: hour_tick, WorldState `water.*`, catch-up, soaked
deterministic); **tier 2 — live water dynamics** (WaterField autoload +
WaterGpu: one 1024² GPU depth field at 2m texels over the WHOLE 2048m
watershed, same budget as the sand field; pipe-model flux kernels flow
rain down the real terrain, pool it in hollows, drain it into the ground
(seepage-bounded so flat ground never floods) and into the authored
water bodies as sinks; a WaterSheet patch follows the player and lifts
its vertices onto the live field, discarding where dry; a one-thread
readback probe feeds `current_at()` — the river/field current now pushes
the player downstream, real effort upstream; presentation-only —
disabled headless, never saved, never fingerprinted; tier 3, the
near-window sediment coupling, is the remaining seed); **tier 2.5 —
the wave field** (WaterWaves autoload + WaveGpu: a 512² damped
wave-equation window at 12.5cm texels following the player; wading
strides ring the surface, storm rain pocks it, wind keeps a chop; the
water shader displaces VERTICES by the field — lake discs and river
ribbons are now vertex-dense so the surface actually moves; scrolls
with the focus, presentation-only, off headless); **water that
reads as water** (the shader composites the refracted bed
through the surface — screen-space refraction bent by ripple + wave
normals, light drunk toward the deep pink with depth — plus painted
posterized foam at shorelines, wave crests, fast water, and stirred
wading; still the pool's pink language, Elden Ring's recipe in gouache;
the compute-kernel compile check now runs headless in scene tests so CI
catches GLSL errors); pond
with wading/swimming and
ripple wake; day/night palette cycle; custom sky (swelling red sun, stars);
weather (calm/windy/storm) driving sway, audio, fog, dust, and NPC shelter;
interaction field (80m coarse: desire-path wear, distant trails) +
**granular sand simulation** (GPU compute when available — 1024x1024
field at 2.3cm texels over 24m, apply/relax/scroll kernels, renderer
samples the field directly via Texture2DRD, zero CPU texel work; CPU
threaded reference otherwise — a heightfield sim in a 20m
window: signed sand volume in meters, CONSERVED — footsteps displace
material into ejecta ridges, landings blast craters with thrown rims,
moving feet plow bow waves; cells past the angle of repose avalanche
downhill each tick, so pits slump shut and ridges slide; wet raises
repose, wind erodes; rendered as real geometry by a 9.4cm sand patch;
sand-slide traversal on steep slopes — the Journey move; conservation
unit-tested; visual probe verifies eight framings); ambient
particles (sand motes, dusk moths from her painting, night glow-motes).

**Simulation** — GameClock (**1:1 real time** — a game day is a real day;
wall-clock driven, hour_tick bus, time_scale for Stillness); **real
seasons, real local sun** (season + daylight + sunrise/sunset from the
system date and geolocated latitude/longitude — solar declination +
equation of time, hemisphere-correct; new worlds anchor the clock to
real local time; sun/palette/dusk-audio/creatures follow via
`solar_hours()`; storms season-biased; `time.season` in WorldState for
conditions; dev time travel: T → next sunrise/noon/sunset/midnight,
Shift/Alt+T → +day/+week, always lived via `advance_hours`;
Shift+Alt+T → back to now, re-anchoring the dial to real time); the ambient machine: saves carry a wall-clock timestamp and time away/asleep is
replayed via shared `GameClock.advance_hours()` catch-up (weather rolls,
NPCs live the skipped hours — needs/position/activity persist hourly);
FocusThrottle (unfocused window fps-capped but watchable, minimized
near-idle); needs/utility NPC AI from records; two-tier (bodies dissolve
>170m, coarse sim continues); sim inspector (the Toolkit → right-click NPC).

**Deep sim (built 2026-07-02, the six-domain pass — every sim obeys the
CLAUDE.md sim contract):** Climate substrate (`temperature(x,z)` +
`moisture(x,z)`; rain soaks / warmth dries; wet ground darkens via
`ground_wetness`); FloraLife (valley-wide vitality chasing climate over
days; billboards dry toward straw via `flora_vitality`; writes
`valley.bloom`/`valley.parched` — first sim-authored story-seed, "The
Dry Spell", with journal seed-latching so transient states can open
quests); real moon phase (stars wash out, glow-motes/fireflies thin
under a full moon; `sky.moon_phase`); rumors (NPCs notice valley-scale
events, hold 12 facts oldest-forgotten, mirror them as
`npc.<id>.knows.*` flags for dialogue, and swap news when they share a
place for an hour); wildlife tier-3 (star-hound herd as pure data —
drink at dawn, shade at noon, prowl — embodied only near the focus;
`data/wildlife/*.json`); long memory (NPC pantry stocks from
`produces` activities → `npc.<id>.stock.*`, ready for trading;
permanent desire-path wear layer persisted in the save, fading over
game-months; placed records stamp their day for future weathering).

**RPG** — WorldState (all flags/values, saved); records loader with
validation; interaction layer (E); items + satchel (I); fireflies (catch at
night / F deploys orbiting light swarm / R recalls); dialogue engine
(records in data/dialogue/, conditions/effects, familiarity-aware); quests
(declarative over WorldState, journal on J); use-based skills (Wayfaring/
Stillness—bends time while sitting/Swimming/Foraging); two inhabitants —
the Wanderer (pink scarf) and the Keeper (teal, tends shrine) — who know
each other; first errand quest "Between Two Solitudes".

**Characters** — Blender creature pipeline live (assets/blender/creatures/
README.md is the contract): scripted low-poly build → rig → clip set →
glb export. Two creatures built: the biped fox (**now the player body**,
from her painting) and the star hound (fully animated, currently unplaced).
NPCs (Wanderer, Keeper) still ride the CC0 robot placeholder.

**Shell/tools** — title screen, pause/settings (**UI pass 2026-07-04:**
`canvas_items` stretch so text/DPI scale with any window; one shared
`UITheme` (game/ui/ui_theme.gd) — gouache paper/ink/water-pink palette,
painterly StyleBoxFlat panels/buttons/sliders as labeled placeholders for
her painted 9-slices, fat pink focus rings; title/pause/journal wear it;
menus gamepad-navigable — focus grabbed on open, D-pad walks, Start/Esc
via ui_cancel; verified by tests/ui_probe.gd screenshots), autosave (**hardened
2026-07-04:** atomic write via tmp+rename, rotating `.bak1`/`.bak2`
refreshed ≤ every 10 min, load falls back live → bak1 → bak2 with a
warning — a torn save costs minutes, never the world); the Toolkit (F1:
fly/sculpt/place/inspect); live map (M, gestures); hot-reload of paintings;
place mode writing cell records; gamepad support (physics interpolation
was tried 2026-07-04 and REVERTED: a streamed world teleports/adds nodes
every frame — cells, scatter, sand patch, water sheet — and each arrival
renders as a white streak without a per-node reset_physics_interpolation
pass; adopt deliberately later with interpolation OFF on procedural
nodes, or accept the 60/120Hz micro-judder); CI on
GitHub (Linux + **macOS-14/Apple Silicon** — the shipping platform;
note test.sh is headless, so Metal compute kernels still only run under
a local windowed session); test
harness (unit + scene + dual smoke). The home valley has hand-composed
places (pond oasis + surrounds) authored via place mode — cells in data/cells/.
**Pending, needs both machines:** Git LFS adoption — `.gitattributes`
patterns are written (in the 2026-07-04 handoff patch) but NOT committed
because git-lfs isn't installed here yet; install on both machines, then
commit the attributes and (optionally, history rewrite — coordinate!)
`git lfs migrate`.

**Archipelago v3 — the Big Island (2026-07-05, Nicco's map-scale
call: "2-3x bigger, Hawaii, detailed coastlines, satellite chain, SF-
bay interior").** Usable land 15→49 km² (Big Island 42 km², one
landmass): an 850m Throat-of-the-World-class volcano (v3 called it
"Mauna"; v4's plain-names pass retired explicit Hawaii naming — real
names wait on the naming-language canon item)
(new `volcano` region kind — concave flanks + radial ridge/ravine
drainage; winter snowline crosses it, so the seasonal snowcap falls
out of the lapse-rate sim), the home valley untouched at its foot;
connecting lobes with **fractal coast noise** (new coast_amp/
coast_freq on all landforms — coves and headlands, not circles);
**the Bay** (new subtractive `bay` kind + `over_bays` flag) — an
SF-style enclosed interior sea east of the valley with Alcatraz-
Rock/Angel-Isle/Yerba islets, an eastern peninsula arm, and a gate
strait; the tiered city on the bay's SW shore; a trailing 7-island
chain ESE (pali volcano-mini, 7-tier terrace hill, barren isle,
stairstep ridge, smoke isle, skerries, the painted atoll). All
kernel-mirrored (parity <7e-5m), soak fingerprint UNCHANGED
(2183523517 — the watershed never saw a moved sample). Map zoom to
13km. Superseded entry below kept for the record.

**Archipelago feel-prototype v2 (2026-07-04, the Loom; v1 desert bowl
redone same day on Nicco's call: literal water, bounded world, smaller
city)** — the ~12km world shape as a disposable draft to fly and walk:
a **world sea** (`data/water/sea.json`, surface −2m; not a lake — no
basin, no hydrology reservoir) fills everything below it outside the
home guard; the ground beyond the valley sinks to a seabed (−35m) and
the procedural ranges fade out with it, so the horizon is water — the
sea IS the world's bound. Authored islands are **region records**
(`data/regions/*.json`, mesa/ridge/dome; every record carries the
`layer` field the F3 schema will need). The home valley is island #1:
`Terrain.home_guard()` (rect from the watershed record + 150–550m
noise-wobbled coast ramp) keeps every sample the Hydrology grid sees
bit-identical — soak fingerprint unchanged through the whole rework.
Islands: the metropolis mesa (210m, 5 tiers, rounded-riser terraces),
gate-dome islets, the stairstep ridge, the 7-tier terrace hill, a big
low barren isle; low **causeway ridges** link them until boats are a
thing. Sea renders as a wave-window patch following the focus + a
coarse horizon disc (water_bodies.gd). Hot path is packed
(region sampling ~+15% over valley baseline). NOT the final map.
Toolkit: `Terrain.regions_summary()`; `tests/region_map.gd` (headless
hillshade + landmark check); `tests/region_bench.gd` (throughput +
steepest-grade); `tests/region_probe.tscn` (Movie Maker screenshots,
minimized). Far-terrain rebuilds moved to a dedicated thread (was
starving behind cell builds on the shared pool). Open feel questions:
fog vs landmark (calm fog eats 91% contrast at 3km), causeway vs boat
traversal, coast silhouette still square-ish.

**RESOLVED (2026-07-05) — the descent crash: fixed by the native
terrain kernel.** The GDExtension port (below) removed all GDScript
from worker threads; `tests/fall_probe.tscn` went from 5/5 crashes to
5/5 clean with ZERO "Bad address index" errors — the long-filed
threaded-sampler script errors were the same disease and died with
it. The final abort site (once everything else was native, the crash
handler could finally print it) was sand_patch's re-anchor build; the
underlying engine bug (GDScript VM corruption under concurrent
worker-thread execution) remains worth an upstream report, but the
game no longer exercises it.

**The native kernel (native/, the Loom, 2026-07-05):** TerrainKernel,
a GDExtension port of `height()` / `water_surface_base()` + block and
whole-mesh builders (`build_cell`, `build_far`) — cell meshes, far
LOD, sand patch/base, water-field base, and the hydrology grid all
sample in C++ now; GDScript keeps the single-sample main-thread API
and is the fallback where the library isn't built. macOS-only .dylib
loaded at runtime by Terrain._ready via a custom-suffix
`native/bin/loomkernel.gdext` (deliberately not `.gdextension`, so
Linux CI never sees it and falls back clean). Rebuild: clone
godot-cpp into native/, dump the engine API (commands in
native/CMakeLists.txt header), `cmake -B native/build -S native &&
cmake --build native/build -j`. Determinism contract:
bit-parity with the engine's own GDScript math is impossible (the
official binary's fma codegen), so the kernel is bit-stable with
ITSELF, every worker consumer reads the kernel, divergence vs
GDScript is gated <1e-4m by `tests/kernel_parity.gd`, and the soak
fingerprint changed ONCE at adoption (still bit-identical across
runs). If the double-precision engine build ever lands, recompile
with `precision=double` (CLAUDE.md GDExtension policy).

**Superseded — descent crash (2026-07-04 night; kept for the record).** Falling/moving
fast (~25m/s+) into unstreamed terrain SIGSEGVs on a WorkerThread
(EXC_BAD_ACCESS near-null; sometimes SIGABRT). Deterministic repro:
`tests/fall_probe.tscn` (headless, ~40s; env knobs FALL_KEEP strips
the scene, FALL_NO_PHYSICS disables the player). **Pre-existing, not
archipelago content**: the same probe crashes commit 1eea47e, and a
matching crash report exists from 01:16 the same day. Ruled OUT by
bisection (each tested with the repro): navmesh baking, trimesh shape
creation, cell unload/queue_free, the far-terrain dedicated thread,
region/guard/sea terrain code, in-flight build caps, serializing all
worker height() sampling behind a mutex, player physics, call-stack
tracking setting. Standalone hammers (pool-only, main+pool, mesh
builds — `tests/thread_crash_probe.gd`) do NOT reproduce; it needs
the real streamer + autoload composition. The long-filed "Bad address
index" threaded-sampler script errors accompany it but serializing
sampling doesn't stop the crash, so they may be a co-symptom, not the
cause. Candidate real fixes, in order: (1) **GDExtension port of the
bulk height samplers** (already the named hot-loop candidate — moves
all worker-thread work out of the GDScript VM), (2) try a newer Godot
4.7.x patch when available, (3) upstream bug report with fall_probe.
Meanwhile: descend big landforms at walking pace, or give streaming a
head start; the valley itself has never triggered it in normal play.

**The air, phase A (2026-07-05, the Elements)** — dew fog as a
stateless function of the sim: `Weather.fog_amount()` condenses from
Climate's real wetness/temperature on calm nights, peaks pre-sunrise,
burns off with the real sun (fog SEASONS fall out for free; storms
carry their own murk). Presentation: thin distance haze (landmark law
survives fog weather) + HEIGHT fog that floods sea/strand/valley
floor while mesa tops float clear + a wind-drifted FogVolume noise
bank you wade through (pools BELOW you on a summit). Toolkit:
`Weather.summary()`, `fog_override` knob; probe `FOG=1
REGION_SHOT=rim|summit`. **Phase B (same day): weather as FRONTS** —
systems are bands with positions spawning windward of the 13km world
circle, traveling at 2.2–4m/s along the wind they were born with,
expiring leeward; local weather = youngest band over the point (800m
soft leading edge), calm between bands. `.state/.wind/.storminess`
are now AT-THE-FOCUS values (all consumers unchanged); spatial sims
read `state_at()`: Climate wets the valley and Hydrology rains into
the watershed only when a band is over THEM. Sim contract type (b):
hour_tick + "weather" Rng stream + `weather.fronts` in WorldState +
catch-up; soak fingerprint moved once (3242764635), bit-stable.
Toolkit: `force_kind()` (Y key + all probes/tests use it — writing
`.state` no longer reaches spatial consumers), `summary()` lists all
fronts. **Phase C (same day): seven kinds, continuous properties,
storm bodies.** A kind is a bundle of numbers (wind/rain/cloud/dust/
menace), not a switch: calm, overcast, drizzle, windy, gale (dry
sand-blasting — summer's violence), squall (narrow, 5.5m/s, vicious),
storm; wet kinds favor winter. Consumers read the numbers:
`rain_at()` wets Climate/Hydrology continuously (drizzle = slow soak),
dust hazes and thickens motes, cloud dims without menace; legacy
names kept so saves/probes migrate free. Presentation: posterized
rain CURTAINS hang under rainy fronts within 9km (the approaching
storm has a body); double-pulse LIGHTNING near heavy rain
(presentation-only randomness; thunder audio = placeholder for his
recordings). Soak moved once (3180831281), bit-stable. Kitchen-table
items: volumetric-fog gouache look; rain-curtain texture is a painted
slot. **Climate v2 phase 1 (2026-07-05): the rain shadow and the
wetness field.** Where the wet air CAME FROM matters now: the rain
term probes terrain upwind along each front's own travel direction —
a barrier that tops a point starts stealing its rain (deep lee of the
950m Range: ~18% of base), ground rising just downwind reads as the
windward slope and rains harder (orographic lift with a direction,
not just altitude). And Climate's one global wetness became a FIELD:
an 8×8 grid of 2048m cells over the world frame, each cell wetting
under the rain actually falling on IT and drying by its own
temperature — so the lee of the Range dries into desert while the
windward flank stays lush, and `FloraLife.vitality_at` /
`moisture(x,z)` inherit the split for free (windward green, leeward
straw — the Hawaii fact, derived). `Climate.wetness` is now a
property: read = the home-valley cell (Hydrology runoff, fog, the
soak line keep their meaning), assign = flood-fill (the old global
semantic — every test and dev knob works unchanged); old saves
migrate by flooding the field with their scalar. Fog dew now reads
wetness at the focus. Sim contract intact (hour_tick, catch-up,
`climate.wet_grid` mirror, no randomness); soak moved once
(1071113081, the grid digest + shadowed valley rain), bit-stable,
30 days ~1s. **Phase 2 (same day): the thermal field.**
`temperature(x,z)` knows where it is beyond altitude: the sea damps
the diurnal swing within ~1.8km (coasts never bake or freeze like
the interior — and the home valley itself reads mildly maritime,
because it IS 1.4km from the east shore), and slopes facing the
sun's CURRENT bearing run warmer (this sky's sun rises +Z, passes
overhead, sets −Z — no permanent warm side exists, so aspect is
time-of-day: east flanks thaw first, west flanks hold evening heat;
pure `aspect_term`, unit-tested). Rain-shadow clearance raised
(120m/500m): a valley does NOT sit in the shadow of its own rim —
only a big sustained wall wrings the air dry (found honestly: the
tightened constants broke the brook-swell test through the west
rim). Per-cell static terrain facts (swing/gradient/height) cached
once, cleared on Terrain.edited — the hourly field tick costs no
terrain probes on dry hours, soak back to ~0.75s. Fingerprint moved
once (1333567381), bit-stable. Fun fact the soak taught: in summer
the maritime damping doesn't change 30-day drying at all — the
swing is symmetric and drying is linear in temperature, so warmer
nights buy back exactly what milder afternoons lose; the asymmetry
arrives with winter's freezing clamp. **Phase 3 (same day):
humidity.** AIR moisture, distinct from ground wetness, STATELESS
(type (a) — nothing saved, nothing to catch up):
`Climate.humidity(x,z)` = base + open water upwind (four probes ride
the LIVE wind — the sea breath) + ground wetness under the column +
a wet front overhead (raining air is saturated air), thinning with
altitude to 0.45× on the peaks. Three consumers wired same-commit:
fog's dew term now condenses from humidity (coasts fog harder than
the interior, summits float clear — sea fog for free);
**dew at dawn** (IDEAS ★): in the pre-dawn window, still saturated
air skips drying and lays a 0.03 film on the wetness field — the
ground darkens before sunrise and dries off by mid-morning; and
**star extinction** (`air_humidity` global, sky shader): humid
nights wash the stars, so the clearest sky of the year is a cold
dry winter night — the field recordist's almanac before the
mechanic exists. Fingerprint UNCHANGED (1333567381) and that is
honest: dew is a dawn film that burns off within two hours, so the
9am end-state never sees it (the scene test proves it fires).
Still open in Climate v2: soil from the erosion bake,
biome-from-climate (SIM_ROADMAP).

**The map pipeline, stage A (2026-07-05, the Toolkit): paint →
bake → world.** `data/world/elevation_guide.exr` (1024px, 16m/px,
EXR meters — paint it in any image editor) + `guide.json` (bake
settings) → `tests/bake_world.gd` runs the kernel's `bake_terrain`:
bilinear upsample + fractal relief + thermal talus + **hydraulic
droplet erosion** (400k droplets on 2048² in ~0.4s — coherent
dendritic drainage, alluvial fans, sediment; the believability
engine) → written as an F3 painted-tile record covering the world.
Baked EXR + record are LOCAL CACHE (gitignored; regenerate with one
command — missing bake just means procedural records show through).
The guide is the source of truth; `tests/derive_guide.gd` seeded it
from the v4 archipelago, so the current world IS the first painting.
The running game hot-reloads the tile when a bake lands: repaint →
rebake (sub-second) → the world reshapes under you. Stage B queued:
painted BIOME map + `biome_at(x,z)` substrate (shader palettes,
per-biome flora species/density, Climate/Weather biome response,
sand physicality) — the palette is a kitchen-table item. Stage C:
river proposal from the erosion flow map (Hydrology-compatible
records), beach rules. Same-day Toolkit pass: Toolkit WORLD PANEL
(O — every system's summary live), sculpt flatten (Ctrl) + stroke
undo (Z), map right-click teleport, summary() coverage completed
(Climate/Hydrology/Sand/WaterField/Flora/Wear/Nav).

**Map pipeline stage B — the biome substrate (2026-07-05).** A
painted biome map (`data/world/biome_map.png`, committed painted
source; palette in `biomes.json`) is matched to an R8 index image and
fed to rendering + flora. `tests/derive_biomes.gd` seeds a believable
starting map from terrain rules (height/slope/water-proximity: grey
bare peaks → volcanic rock → green mid-slopes → sandy strand → sea).
`Terrain.biome_at/biome_density`; a global index texture + Nx1 palette
texture drive the shader (ground tinted toward the biome albedo — a
tint, not a replace); flora scatter scales by biome density (deserts
bare, oases teeming). 8 PLACEHOLDER biomes (rename at the kitchen
table). Pure presentation + flora — soak untouched (2183523517).
Hot-reloads. Stage C (rivers proposed from the erosion flow map)
queued.

**Map pipeline stage C — rivers from the erosion flow (2026-07-05).**
The bake's droplets already found the drainage; `bake_terrain` now
returns `{height, flow}` (flow = droplet passage per cell), and
`tests/propose_rivers.gd` traces the major channels down the carved
valleys to the sea (headwaters first, tributaries merge) into river
records (`data/water/rivers/gen_*.json`, gitignored cache). They carve
+ render like any river but are **no_sim** (Hydrology skips them via
`Terrain.sim_rivers()` — its domain is the home watershed until
per-region watersheds land, and registering them would move the soak
on a presentation knob). Verified soak 2183523517, parity holds. The
map draws all rivers. Re-run with a different FLOW_PCTILE for more/
fewer. **The paint→bake→world pipeline is complete**: elevation guide
+ biome map in → eroded terrain + biomes + drainage out.
**Proposal quality rebuilt (2026-07-05, same day, from playtest
screenshots — the first pass wrote 40 near-duplicate rectangular
gullies whose ribbons floated over dips):** now ≤10 major rivers — a
wide claim mask coalesces parallel gullies, tributaries junction into
trunks, and only channels reaching the sea or a trunk survive;
flow-guided descent (max-flow lower neighbor, not steepest) keeps
traces in the valley floors; Chaikin ×3 + uniform 45m resample kills
the grid corners; node surfaces are bilinear from the BAKED
heightfield (never Terrain.height) with a monotone downstream clamp,
so ribbons lie in the carved channels. Verified visually by the new
`tests/river_probe.tscn` (RIVER_SHOT=close|flank|wide, Movie Maker +
minimized, region_probe's recipe); soak 4124434361 bit-stable
(unchanged — the current fingerprint since the flora-depletion entry;
gen rivers stay no_sim). **The drape (same day, "it's not actually
flowing over the terrain"):** river ribbons no longer trust the
node-lerped surface — every 1.8m cross-section takes min(record
waterline, carved centerline ground + depth), then a backward
max-scan from the mouth (monotone downstream; dips become flat pools
behind their lips, never bridges). Row-to-row grade goes into
COLOR.r; the water shader's new `rapids_boost` (rivers only) foams
the steep runs — cascades read as falls. The tracer resamples
adaptively (45m gentle → 16m steep) so the CARVE follows the step
scale too. Presentation-only: Terrain/kernel untouched, soak
unchanged. Real live flow out there (per-region WaterField windows)
stays future work.
**Live flow everywhere (2026-07-05, the Elements/Watershed): the
tier-2 field is now a SCROLLING WINDOW.** The 1024² 2m-texel dynamics
field no longer sits on the home watershed — it follows the focus
(player or Toolkit cam) anywhere in the archipelago, the sand-field
recipe: re-anchor past 384m drift, depth scrolled by texel offset
(new water_copy kernel), terrain base rebaked off-thread through the
native kernel; entering texels start dry and rain refills them. Storm
runoff now streams down any island's real slopes, pools in its
hollows, and drains into ALL water bodies (generated rivers and the
sea were already in water_base_block's sink answer). Generated
rivers' currents push at a fixed healthy-flow fraction (no Hydrology
discharge to read — per-region routing is still the future item).
Presentation-only: off headless, soak untouched. Verified live at the
volcano: river_probe RIVER_WX=storm (+RIVER_WALK=1 exercises the
mid-run re-anchor/scroll path).
**Flow maps + the water's hours (2026-07-05, Nicco's realism call +
"pink only at golden hours").** Rivers carry a PER-VERTEX flow map
(UV2 = downstream direction × local pace baked from the drape —
rapids race, pools laze, bends curve) scaled by `flow_scale`, the
live hourly discharge; the shader advects ripples/foam along it with
two half-offset cross-faded phases (the flow-map trick — one shared
clock would shear the pattern into streaks). And the pink is now the
LOW SUN'S GIFT: day_night publishes `water_gold`/`water_night` (bell
around solar sunrise/sunset; night from sun elevation) and both water
shaders blend teal day / slate night / the signature pink at golden
hour — day water also absorbs harder so shallow runs still read as
water. river_probe grows RIVER_HOUR=gold + a pond vantage.
**Fill-channels experiment (2026-07-05, debug key K, default OFF).**
The tier-2 field can now SPRING the rivers instead of sinking them: a
new source texture (water_depth.glsl binding 5) injects
discharge-scaled water along each rasterized channel while those
texels drop out of the sink mask (sea + lakes stay sinks), so the
pipe model fills the carved beds with real flowing water. Toggle K
rebakes the base + hides the ribbons for a clean A/B. (The first
recorded finding — "nearly identical" — was INVALID: that probe ran
in a stale checkout and never enabled fill; superseded same day.)
Made livable: channels PRE-FILL to their waterline at bake (rivers
start full, never dry), the flux kernel gains CHANNEL FRICTION
(x0.10 outflow in channel texels — without bed roughness a cascade
sheds its water in one substep; probe depth 0.013m -> 0.304m), and
the sheet grows 96m -> 288m in fill mode. REAL FINDING: the sim
water reads soft and organic in the bed — good — but coverage is
the sheet around the focus; distant stretches are dry, so ribbons
still ship and K stays a diagnostic. BONUS FIX for default mode:
the water sheet was frustum-culled on ALL elevated terrain (node at
y=0, flat AABB, verts lifted to absolute height — fine only in the
home valley); now seated at ground with a relief-sized cull margin,
so rain rivulets/puddles exist on the volcano and mesas for the
first time. Presentation-only: off headless, soak untouched
(1333567381).
**Region hydrology (2026-07-05): the generated rivers BREATHE.**
Hydrology grows a region tier: every no_sim river is a linear
reservoir on the same hourly balance, rained on through
`Weather.rain_at` at its own midpoint (fronts + the v2 rain shadow
make flanks differ for real) and fed by the catchment the erosion
bake measured (`catchment_m2` in the record — peak droplet passage ×
area-per-droplet; the tracer writes it now). Discharge feeds
flow_norm → ribbon flow speed, surface level, and current_at push,
exactly like the brook. State in `region_storage` — SEPARATE from
river_storage because the soak fingerprint digests that dict and gen
records are a regenerable cache; verified: fingerprint identical
with and without gen_*.json present. Saved via WorldState water.*,
hour_tick catch-up, load_state — full sim contract. Soak note: the
expected fingerprint is 1333567381 since the Climate v2 rain-shadow
commits (their message records the move; STATUS's flora-era
4124434361 was stale). **Dev time travel fixed + granular:** the T
lag was water_bodies rebuilding every draped ribbon on each hourly
levels_changed (~80ms, found by the new `tests/clock_probe.tscn`
per-consumer timer); levels now TRANSLATE the built mesh (1h chunk:
80ms → 1ms). New Ctrl+T = +1 hour, Ctrl+Shift+T = +15 min.
**Ribbon seam pass (same day, the Skyrim lessons — bed and surface
authored to agree, disagreements hidden):** tangents smoothed ±2 rows
(bend notches), edges tucked 0.4m past the waterline into the carved
bank (edge cracks), and POOL LIPS (flat water arriving at a >1.1m
cliff) emit a vertical fall face instead of one stretched quad —
lip detection requires the flat above, because splitting every steep
row shingled the cascades (tried, reverted same hour).

## Placeholder ledger (each has a named replacement path)

Biped fox player (hers, replaced the star hound as the player body
2026-07-02) and the star hound (now placed as the placeholder *wildlife*
body — a herd with daily lives west of the pond → rename/re-skin when
canon names the valley's creatures). The fox now
renders through character_paint.gdshader (gouache wash/grain/edge-dark
in-engine, restoring what the flat glb export loses); apply the same
CharacterPaint pass to the star hound and NPC models when they land ·
synth wind + footsteps
(→ his recordings; night bed is a CC0 field recording, see
assets/audio/SOURCES.md) · **the synth placeholder drop** (2026-07-06:
258 billboards + 345 static GLBs, every slot `placeholder-synth` in its
`.card.json` — flip status when real art lands in the same file slot; the
Cards catalog + Toolkit CARDS panel count real vs synth) · SVG cactus
(dune_cactus still on placeholder_cactus.svg; tuft/pebble/bloom SVGs
retired to painted PNGs this session) · noise terrain beyond the valley
(→ painted region tiles,
FOUNDATIONS F3) · all dialogue text (→ post-axioms rewrite) · seasons
change daylight/weather only (→ her seasonal palettes + flora states when
painted) · location via one-shot IP lookup (→ settings-screen location
picker).

## Next up (in rough priority)

−1. **The Toolkit UI build-out** (DECISIONS 2026-07-05, the named order):
   ✅ (1) `--toolkit` boot posture — `scripts/toolkit.sh` / `godot --path
   . -- --toolkit` skips the title and lands the fly camera over the live
   world (dev-only, gated on is_debug_build; Toolkit watches node_added
   for the player, opens itself). ✅ (2) paint the world in-game on the
   live map (kills the Blender terrain trip): P = elevation guide (brush
   + B bake through WorldBake, HotReload reshapes live) · G = biome pen
   (LMB paints the selected biome into the live index map, ground tint
   updates instantly, 1-9 pick, B commits — persists the PNG +
   rescatters flora) · R = river pen (draw a course, Enter carves the
   basin live via Terrain.add_river — densify + baked surface + downhill
   clamp, ribbon + region hydrology attach, persists pen_N.json). All
   three write authored data and hot-reshape without a restart; soak
   untouched (1333567381). **Pens moved into the FLYOVER (2026-07-06,
   Nicco: "I couldn't see the terrain changing in map mode"):** Tab now
   cycles SCULPT → PLACE → TERRAIN → BIOME → RIVER in the fly cam —
   TERRAIN paints the guide on the ground you're looking at and
   AUTO-BAKES on stroke-quiet (worker bake, HotReload reshapes under
   you), BIOME retints live and re-floras on release (1-9 pick), RIVER
   drops points on the terrain (cyan preview strip) and carves on
   Enter. Shared cores so the map pens can't drift: WorldBake.paint_disc
   + RiverPen (commit/densify). Map pens kept for whole-world strokes.
   Remaining, in order: (3)
   MAP GENERATOR (2026-07-06): a whole eroded world from a high-level
   sketch, not hand-sculpting. game/world/landform_gen.gd composes a
   land outline + typed elevation stamps (range/peak/plateau/basin/
   hills/volcano) into an elevation field — rolling FBM base relief on
   every land cell + noised coastline so erosion carves everywhere —
   and the SAME WorldBake erosion weathers it (drainage, talus, fans);
   ~490ms for a continent. Authored as FILES, NOT drawn in-game
   (2026-07-06 Nicco: rely on committed map files, not in-game map
   drawing): edit data/world/sketch.json (outline + stamps) OR paint
   the elevation guide EXR in any image editor, then run
   tests/gen_world.gd (WorldBake.load_sketch → generate → guide +
   tile), offline. The in-map sketch editor was removed; the live
   pens (elevation/biome/river/sculpt) remain for LOCAL edits that
   need the world. ✅ (2026-07-06) **the palette IS the records** — the
   Cards catalog (asset `.card.json`) drives Toolkit PLACE; Kit.ENTRIES
   only survives for legacy already-placed records. Remaining: (4) real
   placement tools (multi-select, duplicate, align, scatter brush) · (5)
   live rule-card editing · (6) undo/history across tools. Toolkit-mode
   checklist extras still open: sim-freeze toggle, eager saves.

0. **[SIM_ROADMAP.md](SIM_ROADMAP.md) Phase A — in progress** (started
   2026-07-02 on "go"): ✅ A1 determinism (Rng streams) + soak harness
   (30 days headless ×2, fingerprint-matched) · ✅ A2 AgentSim core
   (wildlife ported, fingerprint bit-identical; NPC is the second
   adopter, with the village) · ✅ perception v1 (wildlife wariness:
   light-scaled sight, hearing, alert/flee/resume) · ✅ navmesh-per-cell
   (baked per streamed cell on the worker thread from terrain triangles,
   water carved out; NPCs and wildlife walk waypoints via PathCursor,
   straight-line fallback where no navmesh exists; Toolkit N toggles
   the overlay) · ✅ far waypoint graph (roads as records in data/roads/;
   graph derived — consecutive nodes edge, coincident nodes junction;
   A* route(); Nav.path()'s far tier now follows the road instead of
   one blind line; first authored road runs spawn → pond → shrine, a
   disposable fixture for the 12km map) · ✅ NPC AgentSim port
   (2026-07-05: the NPC mind — needs/utility/advance — moved into the
   shared AgentSim core wildlife already runs; the node keeps physics,
   animation, dialogue, rumors, and the pantry flush; `needs` is a
   shared reference to sim.needs so the soak and inspector read
   unchanged; AgentSim grew a per-agent drain_scale [NPCs 6.0,
   wildlife 5.0]. Soak fingerprint BIT-IDENTICAL through the port —
   1333567381 before and after, the A2 wildlife standard held).
   **Phase A COMPLETE — caravan embodiment and the village unblocked.**
   · ✅ caravan embodiment (same day: near the focus a body walks the
   route — seated on stateless locate() every frame at fractional
   hours so it GLIDES, faces its travel, wears the road in, stamps
   sand prints, and nods in passing [E — Greet, `caravan.<id>.met`];
   dissolves past 170m; the robot placeholder body, her caravan-walker
   painting's slot; `tests/caravan_probe.tscn` frames it mid-leg;
   soak untouched — presentation seated on a pure function).
   **Phase B started:** ✅ snow (cover state +
   emergent snowline from the lapse rate, meltwater soaks the ground) ·
   ✅ wind direction (wanders hourly, swings in storms; sand ripples and
   dust follow it) · ✅ herd cohesion (roam draws around the group's
   drifting centroid) · ✅ per-cell flora + species records (2026-07-05,
   the Elements: `data/flora/*.json` — a new plant is one JSON file
   carrying per-stage art slots [all placeholder paths today, her stage
   paintings drop into the same slots], biome composition weights, a
   moisture need, and optional forage `yields`; scatter and ground
   cover are now species-driven — biome picks WHO grows, dune cells
   finally scatter the cactus, stage art chosen at cell build from
   season + vitality; `FloraLife.vitality_at(x,z)` is STATELESS spatial
   vitality — global vitality shifted by local Climate, so pond banks
   stay green through a drought and density breathes with the land, no
   per-cell tick, no save growth; HONEST HARVEST: ForageSpot gather
   spots [E — Gather, feeds the Foraging skill, first source: bloom
   tufts → dried blooms] wound a SPARSE per-cell depletion state on
   the sim contract [hour_tick regrow scaled by local vitality,
   WorldState `flora.cells`, catch-up, load_state] — cells thin while
   wounded, heal over ~2 days, and healed cells are FORGOTTEN so the
   save only remembers open wounds — no cell-reset respawns, ever;
   soak fingerprint moved once [4124434361, the depletion digest
   joining it], bit-stable) ·
   population dynamics gated on the life-timescale axiom.

1. **Asset track (humans)** — see ASSETS_NEEDED.md. Top: her ground-cover
   kit, his Blender rock family, real wind recording.
2. **Canon track (kitchen table)** — the axioms conversation
   (docs/lore/axioms.md is scaffolded); gates all real writing. Pending
   decisions: field-recordist player mechanic (IDEAS ★), no-compass
   Morrowind navigation (must precede quest writing).
3. **Code: G4 remainder** — inventory/item-use UI (eat, examine, gift),
   trading (needs the errand pattern + prices).
4. **Code: G6** — NPC-to-NPC ambient meetings (they cross paths at the pond
   daily and ignore each other — though they now trade rumors there);
   proper navmesh before more NPCs; extract the shared sim core
   (NPC/wildlife utility logic → one RefCounted, three presentations)
   when the village lands.
5. **Code: G5** — region tile pipeline (painted heightmaps) when the world
   wants to grow; biome mask when region #2 exists.
6. **Code: G1 leftovers** — save slots, macOS export build.

## How to resume

`./scripts/run.sh` plays · `./scripts/test.sh` before every commit ·
`godot --path . -e` opens the editor · full keymap + recipes in
DEV_GUIDE.md. For AI sessions: CLAUDE.md carries every hard-won gotcha
(tscn rules, import traps, autoload-vs-`-s` compile order, etc).
