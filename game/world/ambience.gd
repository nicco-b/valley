extends Node
class_name Ambience
## The ambience machine (PLAN_AUDIO A2). Ambient beds are RECORDS now
## (data/audio/ambience/*.json, kind "audio_ambience"), not two hardcoded
## players: one record per LAYER, keyed by biome × weather × time-of-day,
## its crossfade rules and gain curves all fields (2c). This node is the
## EVALUATOR — every frame it reads the same inputs the old hardcoded beds
## read (GameClock solar hours, Weather.wind/storminess, plus the player's
## biome and Audio's duck table) and drives each bed's live volume from its
## record. New biome beds, a rain bed, a shoreline layer are ROWS, not code.
##
## Byte-faithful migration (the A2 acceptance): valley ships wind_bed and
## night_bed records whose fields reproduce the old curves EXACTLY — same
## gains at the same hours, asserted numerically in scene_tests. The unified
## gain formula (bed_linear) collapses to each old bed's arithmetic term for
## term: the wind bed's storm_duck is 0 (storm factor 1.0) and the night
## bed's wind_base/scale are 1.0/0.0 (gusting 1.0), so multiplying the extra
## neutral factors changes nothing in IEEE754 (x*1.0 == x).
##
## Neutral fallback (FW4): a game that ships NO ambience records boots
## silent and clean — no beds, no players, no errors. Audio is presentation
## only (LAW A1): this file READS the sim and never writes it, never touches
## a seeded stream, never moves the soak fingerprint.
##
## Records desk (LAW A3): the beds register kind "audio_ambience" with the
## desk (schema + dir + reloader), so `records validate/schema/reload
## audio_ambience` edit them for free — the same door WildlifeManager and
## the SFX records take.

## The beds are content: data/audio/ambience/*.json, one file per layer.
## Kind "audio_ambience" to the desk; the dir is registered by name (like
## audio_sfx) because it nests below data/<kind>.
const AMBIENCE_KIND := "audio_ambience"
const AMBIENCE_DIR := "res://data/audio/ambience"
## Required fields (the desk's field check); everything else is optional
## with a house default read in the pure helpers below.
const AMBIENCE_SCHEMA := {
	"id": TYPE_STRING, "file": TYPE_STRING, "bus": TYPE_STRING,
}

## Live beds: each { "rec": Dictionary, "player": AudioStreamPlayer,
## "presence": float } — presence is the biome crossfade envelope (1.0 in
## biome, 0.0 out, eased over crossfade_s).
var _beds: Array[Dictionary] = []


func _ready() -> void:
	# The desk owns these beds like any records kind (LAW A3): schema by
	# name (they nest under data/audio/ambience), the dir so `records reload
	# audio_ambience` counts the true path, and a reloader so a landed edit
	# — a retuned curve, a new bed, an interior-duck tweak — applies live.
	Records.register_schema(AMBIENCE_KIND, AMBIENCE_SCHEMA)
	Records.register_dir(AMBIENCE_KIND, AMBIENCE_DIR)
	Records.register_reloader(AMBIENCE_KIND, reload)
	_load_beds()


## Read data/audio/ambience/*.json through the game's own validator: the
## required-field schema, then two house rules the schema can't express —
## `bus` must name a house bus and `file` must exist (the SFX loader's
## honesty, verbatim). A valid bed gets a dedicated looping player on its
## bus; the whole set is torn down and rebuilt on reload. Content-empty (no
## dir / no files) builds nothing and errors nothing — silence, the FW4
## neutral fallback.
func _load_beds() -> void:
	for bed in _beds:
		if is_instance_valid(bed.player):
			bed.player.queue_free()
	_beds.clear()
	var dir := DirAccess.open(AMBIENCE_DIR)
	if dir == null:
		return  # content-empty: silent, clean
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path := AMBIENCE_DIR + "/" + f
		var rec = Records.load_json(path)
		if not (rec is Dictionary) or not Records.validate(rec, AMBIENCE_SCHEMA, path):
			continue
		var bus := String(rec["bus"])
		if AudioServer.get_bus_index(bus) < 0:
			push_error("[ambience] %s: bus '%s' is not a house bus" % [path, bus])
			continue
		var file := String(rec["file"])
		if not ResourceLoader.exists(file):
			push_error("[ambience] %s: missing file '%s'" % [path, file])
			continue
		var player := AudioStreamPlayer.new()
		player.bus = bus
		player.stream = load(file)
		player.volume_db = -80.0  # silent until _process sets the first curve value
		add_child(player)
		player.play()
		# A universal ("*") bed is present from boot; a biome-specific bed
		# starts absent and fades in when the player enters its biome (no
		# pop-in at world load).
		_beds.append({
			"rec": rec, "player": player,
			"presence": 1.0 if _biome_matches(rec, "") else 0.0,
		})


## The desk's live reload (kind audio_ambience): re-read the beds AND the
## duck table Audio owns (3b) — the ambience machine's data is the beds
## plus the ducks that shape them, so one `records reload audio_ambience`
## applies a retuned curve, a new bed, or an interior-duck edit together.
func reload() -> void:
	_load_beds()
	Audio.reload_mix()


func _process(delta: float) -> void:
	if _beds.is_empty():
		return  # neutral fallback (no records) — nothing to drive
	var h: float = GameClock.solar_hours()  # dusk tracks the seasonal sunset
	var wind: float = Weather.wind          # the wind you hear the trees feel
	var storminess: float = Weather.storminess
	var biome := _player_biome()
	for bed in _beds:
		var rec: Dictionary = bed.rec
		var nightness := nightness_for(rec.get("solar_window"), h)
		# Biome envelope: 1.0 in-biome, 0.0 out, eased over crossfade_s so
		# crossing a biome line is an audible fade, not a cut (Pillar four:
		# "crossing a biome line is audible the way it is visible").
		var target := 1.0 if _biome_matches(rec, biome) else 0.0
		bed.presence = crossfade_step(
			bed.presence, target, float(rec.get("crossfade_s", 4.0)), delta)
		# The interior duck (and any future bus duck) rides Audio's data
		# table (3b), never a constant here — the slider's bus level stays
		# put; the duck lives in the bed's own gain, so `audio`'s duck token
		# can name WHY the bed is quiet.
		var duck := Audio.bus_duck(String(rec["bus"]))
		var lin: float = bed_linear(rec, nightness, wind, storminess, duck) * float(bed.presence)
		bed.player.volume_db = linear_to_db(clampf(lin, 0.0001, 1.0))


## --- pure evaluation (unit-testable, no engine/sim state) ---------------

## The night envelope for a bed's solar window: rises through the dusk `in`
## ramp, recedes through the dawn `out` ramp — the old hardcoded
## `smoothstep(19,21.5,h) + 1 - smoothstep(5,7,h)`, now the window's two
## ramps. No window (null / malformed) → pure day (0.0), the neutral floor.
static func nightness_for(window: Variant, h: float) -> float:
	if not (window is Dictionary):
		return 0.0
	var win_in: Variant = window.get("in")
	var win_out: Variant = window.get("out")
	if not (win_in is Array and win_out is Array
			and win_in.size() >= 2 and win_out.size() >= 2):
		return 0.0
	return clampf(
		smoothstep(float(win_in[0]), float(win_in[1]), h)
		+ 1.0 - smoothstep(float(win_out[0]), float(win_out[1]), h),
		0.0, 1.0)


## A bed's linear gain from its record + the live inputs — the one formula
## both old beds collapse into (see the file header). `duck` is Audio's
## live bus-duck multiplier; `presence` (the biome envelope) is applied by
## the caller. Order is pinned for byte-faithfulness: base × gusting × storm
## × duck, each old bed's own term surviving as an identity factor.
static func bed_linear(rec: Dictionary, nightness: float, wind: float,
		storminess: float, duck: float) -> float:
	var base := lerpf(
		float(rec.get("day_gain", 0.0)), float(rec.get("night_gain", 0.0)), nightness)
	var gusting := float(rec.get("wind_base", 1.0)) + float(rec.get("wind_scale", 0.0)) * wind
	var storm := 1.0 - storminess * float(rec.get("storm_duck", 0.0))
	return base * gusting * storm * duck


## Ease a crossfade envelope one frame toward its target over crossfade_s
## seconds (a linear ramp — the beds are seconds-scale, no easing curve
## needed). crossfade_s <= 0 snaps. Pure and deterministic.
static func crossfade_step(current: float, target: float,
		crossfade_s: float, delta: float) -> float:
	if crossfade_s <= 0.0:
		return target
	return move_toward(current, target, delta / crossfade_s)


## --- biome keying -------------------------------------------------------

## Does a bed sound in `biome`? A `biomes` field of ["*"] (or missing /
## empty) plays everywhere; otherwise the current biome must be listed. The
## empty biome ("" — no biome map, off-map) matches only the universal "*".
func _biome_matches(rec: Dictionary, biome: String) -> bool:
	var biomes: Variant = rec.get("biomes", ["*"])
	if not (biomes is Array) or (biomes as Array).is_empty():
		return true
	for b in biomes:
		var name := String(b)
		if name == "*" or name == biome:
			return true
	return false


## The biome under the player's feet (its record id), or "" when there is
## no player yet / no biome map. Sampled like atmosphere's swarms.
func _player_biome() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if not (player is Node3D):
		return ""
	var pos: Vector3 = (player as Node3D).global_position
	var idx: int = Terrain.biome_at(pos.x, pos.z)
	if idx >= 0 and idx < Terrain.biomes.size():
		return String(Terrain.biomes[idx].id)
	return ""
