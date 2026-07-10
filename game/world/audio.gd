extends Node
## Audio (autoload): the house audio architecture, framework-owned.
## PLAN_AUDIO rung A1. The ONE-WIND law's audio twin (LAW A2): the
## framework owns a single bus topology in CODE (diffable, ships clean in
## the manifest — never a .tres bus layout); games tune LEVELS, never
## invent buses. Sound CONTENT is records (data/audio/**); the GRAPH is
## this file.
##
## The house graph (built at boot):
##   Master
##   ├── World       ← the underwater low-pass lives here (player.gd), so
##   │   ├── Ambience    submersion muffles the world, not the UI/music
##   │   └── SFX         (before A1 everything was bus 0 — one bus)
##   ├── Music       ← never muffled by submersion
##   └── UI          ← never muffled, never ducked
##
## Determinism (LAW A1 — audio is presentation-tier BY LAW): every audible
## variation pick rides a PRIVATE RandomNumberGenerator seeded from wall
## time. Nothing here touches the sim's seeded streams or writes sim
## state; the soak fingerprint must never move on an audio change. Audio
## only ever READS the sim (Weather, GameClock, Interiors — as ambience
## does), never the reverse.
##
## Content-empty (FW1): no SFX records → Audio.play() is a silent no-op,
## no errors. A game boots quiet and clean before a single wav exists.
##
## Records desk (Strata R5, LAW A3): SFX events are validated content —
## data/audio/sfx/*.json, kind "audio_sfx", judged by the game's own
## loader schema so `records validate/schema/reload audio_sfx` edit them
## for free. Files stay Nicco's; the machinery is here on day one.

## The house buses, parent-first. Master is engine bus 0 (always present,
## never removable); the rest are appended and routed by _build_buses.
const BUSES := {
	"World": "Master",
	"Ambience": "World",
	"SFX": "World",
	"Music": "Master",
	"UI": "Master",
}
## Ordered so a parent bus exists before a child names it as its send.
const BUS_ORDER: Array[String] = ["World", "Ambience", "SFX", "Music", "UI"]

## SFX event records (LAW A3). Kind is "audio_sfx" (the desk verb the A1
## acceptance names); the files live one level down at data/audio/sfx, so
## the schema is registered by name (Records.register_schema) rather than
## through load_dir's basename keying.
const SFX_KIND := "audio_sfx"
const SFX_DIR := "res://data/audio/sfx"
const SFX_SCHEMA := {
	"id": TYPE_STRING, "files": TYPE_ARRAY,
	"volume_db": TYPE_FLOAT, "bus": TYPE_STRING,
}

## Round-robin voice pools owned by the autoload — no per-shot node churn
## (LAW A2's positional posture, 3d). Sized for the sparse mix (Pillar
## four): a handful of concurrent one-shots is plenty.
const POOL_SIZE := 8

## The ducking table (PLAN_AUDIO 3b) — bus-to-bus duck rules as DATA, not
## scattered constants. A single framework-level file (one object with a
## "ducks" array), each rule:
##   { "id": "interior_hush", "when": "interiors.inside", "bus": "Ambience",
##     "gain": 0.08, "fade_s": 0.8 }
## `when` names a predicate from a small closed vocabulary the audio
## autoload evaluates (the quest-conditions posture). A rule whose
## predicate holds ducks its bus's content by `gain` (a linear multiplier
## the CONSUMER applies — ambience beds multiply it into their gain, so the
## bus level the settings slider owns is never silently moved; the `audio`
## verb's duck token names WHY a bus sounds quiet). Content-empty (no
## mix.json) = no ducks, the neutral fallback (FW4). Held as a single file
## rather than a records-desk dir (it is ONE table, not per-record content).
const MIX_PATH := "res://data/audio/mix.json"
## The duck-rule required fields, judged by the records desk's own validator
## (LAW A3). `gain`/`fade_s` are optional with house defaults.
const MIX_SCHEMA := {
	"id": TYPE_STRING, "when": TYPE_STRING, "bus": TYPE_STRING,
}

var _sfx: Dictionary = {}  # event id -> record
var _cooldown: Dictionary = {}  # event id -> next-allowed msec (anti-machine-gun)
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next3d := 0
## Per-record randomizer cache: one AudioStreamRandomizer per event holds
## its variation pool + pitch/volume jitter (the footstep-pool pattern).
var _randomizers: Dictionary = {}
## Presentation-only RNG (LAW A1) — seeded from wall time, never the sim's
## seeded streams. Reserved for any variation pick the engine randomizer
## doesn't own; its mere existence states the determinism posture.
var _rng := RandomNumberGenerator.new()
## The loaded duck rules (from mix.json) — an Array of rule Dictionaries.
## Empty until _load_mix; empty stays empty when no mix.json ships.
var _ducks: Array = []
## The audition voice (PLAN_AUDIO 4b-ii, A3): ONE dedicated held player for
## looped ambience auditions over the link — kept apart from Ambience's live
## beds so `play_sound stop` silences the audition and never the running
## world. SFX auditions ride the fire-and-forget one-shot pool; only a
## LOOPING ambience layer needs a held voice with a stop.
var _audition: AudioStreamPlayer
## The ambience audition index (id -> record), handed over by the Ambience
## evaluator on load/reload. Audio is the autoload the link reaches; the beds
## live on a scene node the link can't name, so the node feeds its ONE
## validated record set here for `play_sound <ambience-id>`. Empty until the
## bed machine registers (content-empty / autoload-only test = no ambience
## audition, a clean no-op).
var _ambience_index: Dictionary = {}


func _ready() -> void:
	_rng.randomize()  # wall-time seed — presentation, never fingerprinted
	_build_buses()
	_build_pools()
	# The records desk (LAW A3): register the schema by name so the desk
	# judges data/audio/sfx records as kind "audio_sfx", the DIR so the
	# reload verb counts the true nested path (A1 wart: the naive
	# data/audio_sfx counted zero), and a reloader so `records reload
	# audio_sfx` re-reads them live after a landed edit — the same door a
	# restart would take, minus the restart.
	Records.register_schema(SFX_KIND, SFX_SCHEMA)
	Records.register_dir(SFX_KIND, SFX_DIR)
	Records.register_reloader(SFX_KIND, reload)
	_load_sfx()
	_load_mix()


## Build the house bus graph in code. Master (bus 0) stays; the rest are
## appended and their sends wired parent-first. Idempotent by name: a
## second call (a scaffolded game re-entering, a test) rebuilds the same
## topology without stacking duplicate buses.
func _build_buses() -> void:
	AudioServer.set_bus_count(1 + BUS_ORDER.size())
	AudioServer.set_bus_name(0, "Master")
	for i in BUS_ORDER.size():
		AudioServer.set_bus_name(i + 1, BUS_ORDER[i])
	# Sends after every bus exists, so a child can name its parent.
	for bus in BUS_ORDER:
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus), BUSES[bus])


func _build_pools() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		add_child(p3)
		_pool3d.append(p3)
	# The single held audition voice (A3): its bus is set per-audition to the
	# record's own house bus so a bed auditions on Ambience, not the SFX pool.
	_audition = AudioStreamPlayer.new()
	add_child(_audition)


## Read data/audio/sfx/*.json through the game's own validator. Every
## record is judged by SFX_SCHEMA (required fields + types), then two
## house rules the schema can't express: `bus` must name a house bus and
## every file must exist. A record failing either is dropped with a clear
## message — the same load-time honesty the desk surfaces verbatim.
## Content-empty (no dir / no files) loads nothing and errors nothing.
func _load_sfx() -> void:
	_sfx.clear()
	_randomizers.clear()
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		return  # content-empty: silent, clean
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path := SFX_DIR + "/" + f
		var rec = Records.load_json(path)
		if not (rec is Dictionary) or not Records.validate(rec, SFX_SCHEMA, path):
			continue
		var bus := String(rec["bus"])
		if AudioServer.get_bus_index(bus) < 0:
			push_error("[audio] %s: bus '%s' is not a house bus" % [path, bus])
			continue
		var files: Array = rec["files"]
		var missing := false
		for fp in files:
			if not ResourceLoader.exists(String(fp)):
				push_error("[audio] %s: missing file '%s'" % [path, fp])
				missing = true
		if missing or files.is_empty():
			continue
		_sfx[String(rec["id"])] = rec


## The desk's live reload (registered on Records for kind audio_sfx):
## re-read the SFX records so a landed edit takes effect in the running
## game. Rebuilding the dict drops the stale randomizer cache with it.
func reload() -> void:
	_load_sfx()


## Play an SFX event by record id — the ONE emit door (Pillar four, 4d:
## the record id IS the event name; game code is one line at each site).
## `pos` (a Vector3) plays positionally through a 3D voice when the record
## opts in; null (or a non-positional record) plays flat. Unknown id →
## silent no-op (content-empty law; the thunder socket rides this until a
## thunder_near record + wav exist). Fire-and-forget.
func play(event: String, pos = null) -> void:
	var rec: Dictionary = _sfx.get(event, {})
	if rec.is_empty():
		return
	if not _cooldown_ok(event, rec):
		return
	var stream := _randomizer_for(event, rec)
	var vol := float(rec["volume_db"])
	if bool(rec.get("positional", false)) and pos is Vector3:
		var p := _pool3d[_next3d]
		_next3d = (_next3d + 1) % _pool3d.size()
		p.stream = stream
		p.bus = String(rec["bus"])
		p.volume_db = vol
		p.max_distance = float(rec.get("radius", 400.0))
		p.global_position = pos
		p.play()
	else:
		var p := _pool[_next]
		_next = (_next + 1) % _pool.size()
		p.stream = stream
		p.bus = String(rec["bus"])
		p.volume_db = vol
		p.play()


## Audition a bare resource path on the SFX bus (play_sound's res-path
## arm, 4b-ii) — no record, no jitter, just "does this file sound right in
## the game." Fire-and-forget; missing path is a quiet no-op.
func play_file(path: String, pos = null) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if pos is Vector3:
		var p := _pool3d[_next3d]
		_next3d = (_next3d + 1) % _pool3d.size()
		p.stream = stream
		p.bus = "SFX"
		p.global_position = pos
		p.play()
	else:
		var p := _pool[_next]
		_next = (_next + 1) % _pool.size()
		p.stream = stream
		p.bus = "SFX"
		p.volume_db = 0.0
		p.play()


## Does an SFX event record exist for this id? The link's audition router
## (play_sound) asks so it can tell an SFX one-shot from an ambience LAYER
## (which loops and needs the held audition voice + a stop).
func has_sfx(event: String) -> bool:
	return _sfx.has(event)


## The Ambience evaluator hands over its bed records by id (load + reload) so
## the link can audition a bed even though the beds live on a scene node the
## link can't name. Audio only HOLDS the index — Ambience stays the one
## validated loader (no drift). Duplicated so a later reload can't mutate a
## caller's dict out from under us.
func register_ambience(index: Dictionary) -> void:
	_ambience_index = index.duplicate()


## Audition an ambience layer by id (the `play_sound <ambience-id>` arm):
## look it up in the registered index and audition it on the held voice.
## Unknown id (or no bed machine registered — content-empty / autoload-only)
## is a clean no-op.
func audition_by_id(id: String) -> void:
	var rec: Dictionary = _ambience_index.get(id, {})
	if not rec.is_empty():
		audition(rec)


## Audition an ambience LAYER by its record over the link (4b-ii, LAW A4 —
## "what does this feel like in the game"): loop the bed's file on its OWN
## house bus so the audition rides the real graph AND the live bus duck (an
## interior/storm-ducked bed auditions as quiet as it would sound in place).
## Held on the single audition voice — a second audition replaces the first;
## `audition_stop` (the `play_sound stop` arm) silences it. A missing file /
## unknown bus is a clean no-op (content-empty law). The bed's day_gain is the
## audition floor: a listen, not the full solar/wind/biome machine Ambience
## runs in place. The loaded stream is DUPLICATED before its loop flag is set
## so the shared cached resource (the live bed uses the same wav) is untouched.
func audition(rec: Dictionary) -> void:
	var file := String(rec.get("file", ""))
	if not ResourceLoader.exists(file):
		return
	var bus := String(rec.get("bus", "Ambience"))
	if AudioServer.get_bus_index(bus) < 0:
		bus = "Ambience"
	var stream: AudioStream = load(file).duplicate()
	# Loop the audition so a bed can be judged (beds loop in place); a
	# one-shot would end before the ear could settle. WAV carries loop_mode;
	# Ogg/other streams carry a `loop` bool — set whichever the stream has.
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif "loop" in stream:
		stream.set("loop", true)
	_audition.stream = stream
	_audition.bus = bus
	var lin := clampf(float(rec.get("day_gain", 1.0)) * bus_duck(bus), 0.0001, 1.0)
	_audition.volume_db = linear_to_db(lin)
	_audition.play()


## Stop the held ambience audition (the `play_sound stop` arm). Idempotent —
## stopping a silent voice is a clean no-op, so the Mix face's Stop button is
## always safe to press.
func audition_stop() -> void:
	if _audition and _audition.playing:
		_audition.stop()


## One AudioStreamRandomizer per event: its variation pool + pitch/volume
## jitter (AudioStreamRandomizer's own non-sim RNG — presentation, LAW
## A1). Cached; rebuilt when the record set reloads.
func _randomizer_for(event: String, rec: Dictionary) -> AudioStreamRandomizer:
	if _randomizers.has(event):
		return _randomizers[event]
	var rz := AudioStreamRandomizer.new()
	rz.random_pitch = float(rec.get("pitch_var", 1.0))
	rz.random_volume_offset_db = float(rec.get("volume_var_db", 0.0))
	for fp in rec["files"]:
		rz.add_stream(-1, load(String(fp)))
	_randomizers[event] = rz
	return rz


## Anti-machine-gun guard (2a `cooldown_s`): an event may not retrigger
## within its cooldown. Zero/absent cooldown always passes.
func _cooldown_ok(event: String, rec: Dictionary) -> bool:
	var cd := float(rec.get("cooldown_s", 0.0))
	if cd <= 0.0:
		return true
	var now := Time.get_ticks_msec()
	if now < int(_cooldown.get(event, 0)):
		return false
	_cooldown[event] = now + int(cd * 1000.0)
	return true


## The Mix face's data (4a) — the house bus levels for the `audio` link
## verb, in tree order. Master World Ambience SFX Music UI, each
## "<bus>:<volume_db>". Reads AudioServer live, so it mirrors whatever the
## settings slider or a future duck last wrote.
func bus_levels() -> String:
	var toks := PackedStringArray()
	for i in AudioServer.bus_count:
		toks.append("%s:%.1f" % [
			AudioServer.get_bus_name(i), AudioServer.get_bus_volume_db(i)])
	return " ".join(toks)


## Read the duck table (data/audio/mix.json). Each rule is validated
## against MIX_SCHEMA + a bus-is-a-house-bus check (SFX's honesty), so a
## malformed rule is dropped with a clear message, never a silent misduck.
## Content-empty (no file / no ducks) loads nothing, errors nothing (FW4).
func _load_mix() -> void:
	_ducks.clear()
	if not FileAccess.file_exists(MIX_PATH):
		return  # neutral fallback: no ducks
	var doc = Records.load_json(MIX_PATH)
	if not (doc is Dictionary) or not (doc.get("ducks") is Array):
		push_error("[audio] %s: expected an object with a 'ducks' array" % MIX_PATH)
		return
	for rule in doc["ducks"]:
		if not (rule is Dictionary):
			continue
		var msg := Records.validate_message(rule, MIX_SCHEMA)
		if msg != "":
			push_error("[audio] %s: duck rule %s" % [MIX_PATH, msg])
			continue
		if AudioServer.get_bus_index(String(rule["bus"])) < 0:
			push_error("[audio] %s: duck bus '%s' is not a house bus"
				% [MIX_PATH, rule["bus"]])
			continue
		_ducks.append(rule)


## The live linear duck multiplier for a bus — the product of every active
## rule's gain (a rule is active when its `when` predicate holds now).
## 1.0 when nothing ducks the bus. The CONSUMER (ambience beds) multiplies
## this into its own gain, so the settings slider's bus level is never
## silently moved — the duck lives in the content's level, not the graph.
func bus_duck(bus: String) -> float:
	var g := 1.0
	for rule in _ducks:
		if String(rule["bus"]) == bus and _predicate(String(rule["when"])):
			g *= float(rule.get("gain", 1.0))
	return g


## The ids of every duck rule active right now, space-joined — the `audio`
## verb's trailing `duck:<ids>` token so the Mix face can show WHY a bus is
## quiet. "-" when nothing ducks (the A1 placeholder this rung fills).
func active_ducks() -> String:
	var ids := PackedStringArray()
	for rule in _ducks:
		if _predicate(String(rule["when"])):
			ids.append(String(rule.get("id", "?")))
	return "-" if ids.is_empty() else " ".join(ids)


## Re-read the duck table live — the door a landed mix.json edit takes so
## an interior-duck tweak (3b, "interior duck edits as data") applies in the
## running game without a restart. Fire from the desk/reload path.
func reload_mix() -> void:
	_load_mix()


## The closed predicate vocabulary the duck rules name (3b: "named game
## predicates the audio autoload knows"). Reads sim state, never writes it
## (LAW A1). An unknown predicate is inactive (false) — an honest floor, the
## same posture the records desk takes on an unknown kind. Grows a case at a
## time as new ducks are wanted (dialogue-over-music when dialogue exists).
func _predicate(pred: String) -> bool:
	match pred:
		"interiors.inside":
			return Interiors.inside
	return false
