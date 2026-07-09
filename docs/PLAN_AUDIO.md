# PLAN_AUDIO — the robust audio system, end to end

*Design of record, 2026-07-09 (Nicco: "we need to build a robust audio
system. strata should have full control end to end"). DESIGN ONLY — a
build wave executes against this doc. Same discipline as the house
plans: laws, ladder, fence, ★s for Nicco's taste, file:line citations
for every exists claim. This plan **absorbs strata’s PLAN_CREATION_LIBRARY §5
(L5 audio citizens, L7 SFX records)** — both become rungs A1/A3 here,
their specs carried forward verbatim where still right — and
**explicitly amends the §6 fence line** "no bus/mixer editor"
(strata/docs/PLAN_CREATION_LIBRARY.md:453-455); see the fence section for the
honest supersession.*

---

## 0 · Survey — what exists today (read from source, 2026-07-09)

**The whole of valley's audio, six files and four hardcoded systems:**

| system | where | what it does |
|---|---|---|
| Ambient beds | `game/world/ambience.gd:1-22` + two `AudioStreamPlayer` nodes in `valley.tscn:90,95` (`Ambience/Wind`, `Ambience/Night`) | Crossfades wind vs night against `GameClock.solar_hours()`; wind gain rides `Weather.wind`, night ducks with `Weather.storminess`; a pocket interior ducks both to 0.08 (`Interiors.inside`). Every curve constant is hardcoded. |
| Footsteps | `game/player/player.gd:40` (`FOOTSTEP_AUDIO_DIR`), `:118-131` (`_make_footsteps`), `:149-151` | Directory-scans `assets/audio/steps/*.wav` into an `AudioStreamRandomizer` (pitch 1.12, ±2 dB) — ONE surface (sand), hardcoded −13 dB, non-positional `AudioStreamPlayer`. |
| Underwater muffle | `game/player/player.gd:276-292` | An `AudioEffectLowPassFilter` appended to **bus 0 (Master)** and toggled by camera submersion — so it muffles *everything*, UI included, because there is only one bus. |
| Master volume | `game/ui/settings.gd:39` | `AudioServer.set_bus_volume_db(0, …)` — again bus 0; the settings slider and the underwater filter share the only bus that exists. |
| Thunder | `game/world/atmosphere.gd:47-48` | Lightning flashes exist; thunder audio is "a named placeholder → his recordings" — **no code hook at all**. |
| Weather FX | `game/world/weather_fx.gd` | Dust particles only — zero audio. Rain has a painted curtain (`atmosphere.gd:40-44`) and **no sound**. |

**Assets:** `assets/audio/` = `wind_loop.wav` (synth placeholder),
`night_loop.wav` (CC0 freesound interim), `steps/sand_1-4.wav` (synth) +
`SOURCES.md`, whose license rule ("only CC0 or our own recordings; log
every addition") is prose, not data. **Zero `.card.json` under
`assets/audio/`** (strata/docs/CREATION_KIT_REVIEW_V2.md:37 — verified again today,
`find` returns empty). No music. No UI foley. No creature sounds.

**Bus reality:** `project.godot` sets no `default_bus_layout` and
no `[audio]` section at all — the game runs on Godot's default single
Master bus. That is why the low-pass and the volume slider both write
bus 0.

**The patterns to build on (all landed, all proven):**

- **Records desk** — `game/data/records.gd:6-17`: loaders
  register required-field schemas + optional live reloaders;
  `records validate|reload|schema <kind>` link verbs
  (`game/dev/strata_link.gd:758-830`) let Strata judge a record
  by the game's own loader and rebind it live. WildlifeManager is the
  exemplar consumer (`game/wildlife/wildlife_manager.gd:28-33` SCHEMA,
  `:53` load_dir, `:44` register_reloader).
- **The mirror** — `strata App/InspectorView.swift:518` ("the live sim mirror
  … the ONE home for time-of-day and weather"), fed by the batched
  `pulse` verb (`strata_link.gd:563-569`): Strata reads live sim state
  and drives it back through verbs. The mixer face below is this
  pattern, note for note.
- **Thumbnail/audition plumbing** — `thumbnail` verb renders in the
  pane and replies async (`strata_link.gd:323-325`);
  `strata App/ThumbnailBridge.swift` + sha-keyed cache on the Strata side.
  `play_sound` is this verb's audio sibling.
- **DropSanity** — `strata Sources/StrataCore/Project/DropSanity.swift`: the
  import-time sanity line pattern the audio drop copies.
- **Engine layer (Godot 4.7) is already rich** — buses + per-bus effect
  chains (`AudioServer`), `AudioStreamRandomizer` (in use),
  `AudioStreamPlayer3D` positional with attenuation/max_distance,
  `Area3D` bus overrides + reverb buses, and the 4.3+ composition
  streams (`AudioStreamInteractive`, `AudioStreamPlaylist`,
  `AudioStreamSynchronized`) for music transitions. **The engine layer
  is not the gap. The CONTENT layer is the gap** — nothing above the
  engine is data.

---

## 1 · The laws

**LAW A1 — Audio is presentation-tier, BY LAW.** Nothing audible may
ever enter the soak fingerprint or the sim contract. Every variation
pick (which footstep wav, thunder delay, pitch jitter) uses local,
non-sim RNG — the same posture lightning already declares
("Presentation-only randomness (never fingerprinted)",
`atmosphere.gd:46-47`). Audio *reads* the sim (Weather.wind,
GameClock, Interiors.inside — as `ambience.gd` does today) and never
writes it. A build rung that moves the fingerprint is wrong by
definition.

**LAW A2 — The ONE-WIND law's audio twin: one bus layout, framework-
owned.** The framework (valley IS the framework, PLAN_FRAMEWORK.md)
owns a single house bus topology; games tune levels, never invent
buses. Sound *content* is records; the *graph* is framework code.

**LAW A3 — Sound is validated content.** Every ambience layer, SFX
event, footstep surface, and music context is a record under
`data/audio/`, loaded through `Records.load_dir` with a registered
schema — so the records desk (validate/reload/schema) edits all of it
for free, day one, no new Strata machinery. Audio *files* are library
citizens with cards; `license` is a **mandatory** card field for audio
(the SOURCES.md rule promoted from prose to schema).

**LAW A4 — Strata plays and maps; it never edits waveforms.** Two
audition paths exist because they answer different questions:
AVAudioPlayer in Strata answers "what is this file"; `play_sound` over
the link answers "what does this feel like in the game" (through the
buses, the ducks, the low-pass). Neither is a DAW.

---

## 2 · Pillar one — RECORDS: sound as validated content

All under `data/audio/` (kind = `audio` to the records desk,
subdivided by file: the desk's `data/<kind>` scan and `RecordCatalog`'s
`data/**/*.json` scan both already tolerate this — mirror how
`data/wildlife/*.json` works). Schemas registered by the loaders
(Pillar-two's `audio.gd` autoload), exactly the WildlifeManager
pattern.

**2a · SFX records — `data/audio/sfx/*.json`** (one file per event,
the wildlife-records pattern: one record per citizen):

```jsonc
{ "id": "thunder_near",
  "files": ["res://assets/audio/sfx/thunder_1.wav", "…_2.wav"],  // variations
  "one_of": true,               // randomizer pool (local RNG — LAW A1)
  "volume_db": -6.0,
  "pitch_var": 1.08,            // AudioStreamRandomizer random_pitch
  "volume_var_db": 2.0,
  "bus": "SFX",                 // must name a house bus (validated)
  "positional": true,           // AudioStreamPlayer3D vs plain player
  "radius": 400.0,              // max_distance when positional
  "cooldown_s": 0.15 }          // anti-machine-gun guard
```

Schema: `id:String, files:Array, volume_db:Float, bus:String` required;
the rest optional with house defaults. The loader validates `bus`
against the house layout and every file against existence — the desk
surfaces the loader's words verbatim, as `records validate` already
does (`strata_link.gd:761-767`).

**2b · Footstep records — `data/audio/footsteps.json`**: rows of
`{ "surface": "sand", "files": [...], "volume_db": -13, "pitch_var": 1.12 }`.
`player.gd`'s pool becomes the consumer; surface is resolved from the
ground the foot lands on (biome/material lookup — stone, wet, interior
floor become **new rows, not new code**, which is exactly
ASSETS_NEEDED's "code is ready to add when sounds exist," done as
data). The current sand constants (−13 dB, 1.12) become the first row.

**2c · Ambience records — `data/audio/ambience/*.json`** — one record
per **layer**, keyed by biome × weather × time-of-day, with crossfade
rules as fields:

```jsonc
{ "id": "wind_bed",
  "file": "res://assets/audio/wind_loop.wav",
  "bus": "Ambience",
  "biomes": ["*"],                       // or ["dunes","flats"]
  "day_gain": 0.5, "night_gain": 0.18,   // ambience.gd:21's lerp endpoints
  "wind_scale": 1.1,                     // gusting = base + scale*Weather.wind
  "storm_duck": 0.0,                     // night_loop sets 0.7 (ambience.gd:23)
  "interior_duck": 0.08,                 // the through-the-wall murmur
  "crossfade_s": 4.0,                    // layer enter/exit fade
  "solar_window": null }                 // or {"in":[19.0,21.5],"out":[5.0,7.0]}
```

The ambience machine (Pillar two) evaluates every layer every frame
against the same inputs `ambience.gd` reads today — GameClock solar
hours, `Weather.wind`/`storminess`, `Interiors.inside` — plus the
player's current biome. Today's two hardcoded beds become the first
two records, byte-identical in behavior (the migration acceptance
test: same gains at the same hours). New biome beds, a rain bed, a
water-lap shoreline layer are **rows**.

**2d · Music records — `data/audio/music/*.json`** (rung A4, shape
fixed now): `{ "id", "file", "contexts": ["dusk","shrine","menu"],
"priority", "crossfade_s", "cooldown_min", "bus": "Music" }`. Contexts
are named game states the music player subscribes to; transition rules
are fields (crossfade seconds, silence-between preference — this game
should mostly be silent, see Pillar four). No sequencer, no timeline —
if layered/interactive music is ever wanted, `AudioStreamInteractive`
is the engine-native answer and the *record* just names the stream
file; queueing rules stay record fields the player interprets
(strata/docs/PLAN_CREATION_LIBRARY.md:437-441, carried forward).

**2e · Audio asset cards** (absorbing L5 verbatim,
strata/docs/PLAN_CREATION_LIBRARY.md:394-406): card classes `audio_loop` /
`audio_oneshot`; card carries **mandatory `license`** + optional
`loop_seconds`, `gain_db` hint, `tags`. Valley cards its six files
(SOURCES.md's table becomes card fields; SOURCES.md stays as the
human-readable ledger) and `cards.gd` ROOTS gains
`"audio_loop"/"audio_oneshot": "res://assets/audio"`
(`game/data/cards.gd:21-24`). Stock→game copy (L4) then moves audio
unchanged — Nicco's field recordings land in the library once and flow
to every game.

---

## 3 · Pillar two — the house architecture (ONE-WIND's audio twin)

**3a · The bus layout, framework-owned.** A new framework autoload
`game/world/audio.gd` ("Audio") builds the house graph in code
at boot (code, not a `.tres` bus layout file — the framework manifest
ships code cleanly, and the graph stays diffable):

```
Master
├── World            ← the underwater low-pass moves HERE (from bus 0)
│   ├── Ambience     ← beds
│   └── SFX          ← footsteps, thunder, foley, creatures
├── Music            ← never muffled by submersion
└── UI               ← never muffled, never ducked
```

Fixes a live wart on day one: today submersion low-passes the *entire*
game including UI clicks and any future music, because everything is
bus 0 (`player.gd:276-292`, `settings.gd:39`). Migration: settings'
master slider keeps writing Master; `player.gd`'s low-pass targets
"World"; `ambience.gd`'s players and the footstep pool get
`bus = "Ambience"/"SFX"`. Settings can later grow per-bus sliders for
free (Music/SFX volume — the standard options-menu trio) — same one
door, `AudioServer.set_bus_volume_db(by name)`.

**3b · Ducking rules as data.** The interior duck (0.08), the storm
duck on night sounds (0.7), and future ducks (dialogue-over-music when
dialogue exists) are **record fields** (see 2c) evaluated by the
ambience machine — never scattered constants. One new framework-level
duck table `data/audio/mix.json` holds *bus-to-bus* rules:
`{ "when": "interiors.inside", "bus": "Ambience", "gain": 0.08,
"fade_s": 0.8 }` — conditions are named game predicates the audio
autoload knows (the quest-conditions posture: a small closed
vocabulary, validated). The hardcoded `duck` in `ambience.gd:19-20`
migrates into this.

**3c · Determinism posture, stated for the record.** Audio is
presentation-tier BY LAW (LAW A1). The audio autoload owns a private
`RandomNumberGenerator` seeded from wall time; nothing audio-side may
touch the sim's seeded streams; the soak fingerprint is the merge gate
and it must not move on any audio rung (bit-stability across two runs,
per the fleet rule — never pin a value).

**3d · Positional posture.** SFX records with `positional: true` play
through pooled `AudioStreamPlayer3D`s (a small round-robin pool owned
by the autoload — no per-shot node churn); `radius` maps to
`max_distance`. Interiors later add an `Area3D` reverb-bus override as
an I3 rung — the graph is ready for it because the framework owns it.

---

## 4 · Pillar three — STRATA's control, end to end

Four faces, all reusing landed plumbing:

**4a · The mixer as an inspector face (the mirror pattern).** A "Mix"
section in InspectorView beside the live sim mirror
(`strata App/InspectorView.swift:518` — small section-add, the
conflict-resolvable kind, NOT a rewrite). Backed by two new link verbs:

```
audio            -> "ok audio Master:0.0 World:0.0 Ambience:-2.5 SFX:0.0 Music:-6.0 UI:0.0"
                    (bus:volume_db list, + a trailing "duck:<active-rule-ids>" token
                     so the face can show WHY a bus is quiet right now)
audio set <bus> <db>  -> live AudioServer.set_bus_volume_db; "ok audio <bus> <db>"
```

`audio` joins the batched `pulse` reply like the other mirror sections
(`strata_link.gd:563-569`). Sliders drive `audio set`; between
gestures the face follows the game — exactly the time-of-day slider's
contract. **Tuning, then committing:** a "write to mix.json" button
lands the current levels as a `base_gain_db` field per bus in
`data/audio/mix.json` via the records desk (validate → write → reload)
— so a live tuning session becomes data, not a lost knob state.

**4b · Audition from the browser (the thumbnail verb's audio
sibling).** (i) In-Strata: spacebar-preview on any `audio_*` card via
AVAudioPlayer — no game process needed (absorbing L5; "a librarian who
can't hear the records is the R6 blindness twice over"). AssetBrowser
shows an AVFoundation waveform strip + duration badge as the
thumbnail (strata/docs/PLAN_CREATION_LIBRARY.md:201, carried). (ii) In-pane: the
**`play_sound <event|res-path>`** link verb — plays an SFX record by
id (full pipeline: variations, jitter, bus, ducks, low-pass) or a bare
res-path on the SFX bus. An Audition button in the record inspector
and on audio cards drives it. Sync reply ("ok play_sound <id>"), fire
and forget — no async dance needed.

**4c · Drop-in import (DropSanity's audio sibling).** The Assets tab
accepts `.wav/.ogg` drops → card + copy into `assets/audio/<category>/`
(the L1-L3 drop path, new classes). The drop sheet asks loop vs
oneshot and **requires the license field** (blocking, per the
SOURCES.md rule — the one mandatory ask). The sanity line reports:
sample rate, channels, duration, **peak dBFS + a normalization
warning** ("peaks at −0.1 dBFS — hot; house target −6 to −3") and, for
loops, a seam check (first/last 10 ms delta). Report only — Strata
never rewrites the file (LAW A4). AVFoundation gives all of this
in-process.

**4d · Events wiring as data.** Which game event emits which SFX
record is the SFX record itself (2a): the record `id` IS the event
name; game code calls `Audio.play("thunder_near", pos)` — one line at
each emit site, everything else data. The wiring *view* in Strata is
the existing Records tab (RecordCatalog already scans `data/**`); the
only addition is the Audition button (4b). No graph editor, no event
router UI — an emit site is a grep away, and the record is the truth.

---

## 5 · Pillar four ★ — the gouache question for the EARS

What does a painted world *sound* like? Proposed direction (★ all of
this is Nicco's taste to ratify — it shapes every recording):

- **Sparse is the style.** The art laws' audio twins: *"glow is
  reserved"* → **loudness is reserved** — the mix lives quiet and thin;
  a loud moment (thunder, a shrine) spends scarce budget and therefore
  *lands*. `ambience.gd:22`'s own comment is the seed: "night sound
  should be felt, not noticed." House headroom law: beds sit low,
  nothing competes.
- **Hand-made, close-mic'd, imperfect.** Matte paint's twin: no
  glossy cinematic reverb walls, no stock "forest ambience" beds. His
  own field recordings (already the SOURCES.md intent) with audible
  human grain — a wind that sounds *recorded*, not generated.
  Imperfection reads as style (art law 5).
- **Night is a different painting, not a darker one** (art law 3,
  verbatim): the day/night cycle swaps *palettes* of sound, not just
  gains — dusk retires the wind bed's brightness and introduces the
  night layer as its own piece. The ambience records' solar windows
  (2c) are palette keyframes for the ears, deliberately parallel to
  `day_night.gd` KEYS.
- **One palette per biome** (art law 3 again): each biome gets a small
  bed family — dunes hiss, flats ring hollow, water laps pink — so
  crossing a biome line is *audible* the way it is visible.
- **Music is rare and diegetic-leaning ★**: mostly silence and wind;
  music enters at named moments (dusk, shrines, story beats) like the
  reserved glow — never a looping open-world score. Instrument
  direction (★ pure taste): warm, small, slightly detuned — the sonic
  equivalent of wobbly shapes and brush grain.

---

## 6 · The ladder

| rung | contents | side | size | acceptance |
|---|---|---|---|---|
| **A1 · buses + SFX records + play_sound** | `audio.gd` autoload builds the house graph (3a); low-pass/volume migrate off bus 0; SFX record kind + loader + pooled players (2a); footsteps.json (2b) — `player.gd` pool becomes a consumer; thunder gets its first hook (`atmosphere.gd` emits `Audio.play("thunder_near")`); `play_sound` + `audio`/`audio set` verbs land in strata_link (+ VERBS list + scene test) | valley | M | Footsteps-on-stone is a record row + files, no code; thunder placeholder has a socket; UI is audible underwater; soak fingerprint unmoved; `records validate audio_sfx` judges a bad record |
| **A2 · ambience machine** | ambience records (2c) + mix.json ducks (3b); `ambience.gd` becomes the evaluator; today's two beds become records with **identical** behavior; biome keying live | valley | M | Same gains at same hours as before (a listening A/B + gain probe); a new rain-bed row plays with zero code; interior duck edits as data |
| **A3 · Strata mixer + audition** | audio cards + drop-in + sanity line (2e, 4c); AVAudioPlayer preview + waveform strips (4b-i); Mix inspector section over `audio`/`pulse` (4a); Audition buttons drive `play_sound` (4b-ii); commit-to-mix.json | strata | M | A dropped wav is a carded, licensed, auditioned asset in one gesture; a bus slider moves the live pane; a tuned mix lands as a record |
| **A4 · music** | music records (2d) + the context player; first track when one exists | valley | S+content | A dusk context plays its track with record-field crossfade; silence between is the default |

Sequencing: A1 → A2 strictly (A2 consumes A1's buses); A3 parallel to
A2 after A1 lands; A4 pulled only when Nicco wants music at all.
Every rung's merge gate: `./scripts/test.sh` green, soak fingerprint
bit-stable, no new framework-lint seams (footsteps.json etc. are
`data/`, which the lint already treats as content).

---

## 7 · The fence

Standing (PLAN_CREATION_LIBRARY §6, carried whole): **no DAW** — no
trimming, fades, loop-point surgery, waveform *editing* in Strata (the
waveform render is a picture); **no audio middleware** (FMOD/Wwise);
**no generative audio** until pulled; no runtime streaming/CDN; the
filesystem + cards stay the truth.

**Amended (this plan supersedes one clause):** §6 said "no bus/mixer
editor — the game owns its AudioServer graph; Strata's reach ends at
record fields" (strata/docs/PLAN_CREATION_LIBRARY.md:453-455). Nicco's "full
control end to end" overrules the *mixer* half: Strata gets the Mix
face (4a) — live bus **levels** and a commit-to-record path. The
*graph* half stands, sharpened: Strata never edits bus **topology** or
effect chains; the framework owns the graph in code (LAW A2). Levels
are tuning; topology is architecture.

New fence posts: no per-object audio inspector in Strata (records +
audition cover it); no audio in the fingerprint, ever (LAW A1 — a
fence post AND a law); no speech/dialogue audio machinery until
dialogue records exist (DESIGN_QUESTS.md's open ★); no loudness
auto-normalization — the sanity line *reports*, humans decide.

## 8 · Build-wave note (2026-07-09)

The `play_sound` quick win (named in strata/docs/CREATION_KIT_REVIEW_V2.md:64 and
the audit) was deliberately **not** landed with this plan:
`strata_link.gd`'s VERBS const + dispatcher (`:258-263`, `:351+`) are
the exact lines every verb-adding sibling touches, and spawn/pulse
siblings are live this wave. It is A1's cheapest line item; land it
there, with the scene test's both-ways VERBS assertion
(`strata_link.gd:255-257`).
