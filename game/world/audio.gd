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


func _ready() -> void:
	_rng.randomize()  # wall-time seed — presentation, never fingerprinted
	_build_buses()
	_build_pools()
	# The records desk (LAW A3): register the schema by name so the desk
	# judges data/audio/sfx records as kind "audio_sfx", and a reloader so
	# `records reload audio_sfx` re-reads them live after a landed edit —
	# the same door a restart would take, minus the restart.
	Records.register_schema(SFX_KIND, SFX_SCHEMA)
	Records.register_reloader(SFX_KIND, reload)
	_load_sfx()


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
