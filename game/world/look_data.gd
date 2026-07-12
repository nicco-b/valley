class_name LookData
extends RefCounted
## Look records (E3.3): a family-generic envelope over a Look's shader
## constants — {look_family, params}. `look_family` selects which arm
## reads `params`; games will not always be gouache, so this dispatcher
## stays family-agnostic on purpose. gouache is look #1, not the schema:
## a game ships its own record with a different look_family to declare a
## different look. An unknown family fails LOUDLY (push_error + an empty
## params dict) — it never silently falls back to gouache's numbers.
##
## Both terrain.gd (the real game terrain) and preview_terrain.gd (the
## shaping drape) call load_gouache() so the SAME record binds the SAME
## uniforms on both — the gouache-gap discipline extended to data, not
## just the shader code.

const GOUACHE_PATH := "res://data/looks/gouache.json"
const SKY_PATH := "res://data/looks/sky.json"


## Load a look record from `path` and return its params dict IF its
## look_family matches `family`. Returns {} and push_errors on: missing
## file, bad JSON, or a family mismatch — callers must not treat {} as
## "use the defaults", only as "something is wrong, look at the log".
static func load_params(path: String, family: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[look_data] missing look record: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[look_data] %s did not parse as an object" % path)
		return {}
	var record: Dictionary = parsed
	var got_family: String = String(record.get("look_family", ""))
	if got_family != family:
		push_error("[look_data] %s declares look_family '%s', expected '%s'" %
				[path, got_family, family])
		return {}
	if not record.has("params") or typeof(record["params"]) != TYPE_DICTIONARY:
		push_error("[look_data] %s has no 'params' object" % path)
		return {}
	return record["params"]


## The gouache family's params, from the shipped record — the one call
## site both terrain.gd and preview_terrain.gd use.
static func load_gouache() -> Dictionary:
	return load_params(GOUACHE_PATH, "gouache")


## The sky family's params, from the shipped record (E3.4). Returns the dome
## CONSTANTS (`params`) only — the palette the hour is resolved against is a
## SEPARATE record named by the record's `palette_ref` (load_sky_palette_ref).
## Same loud-on-mismatch contract as load_gouache: {} means "something is
## wrong, look at the log", never "use defaults". sky is look #2, not the
## schema — a game with a different sky ships a different look_family.
static func load_sky() -> Dictionary:
	return load_params(SKY_PATH, "sky")


## The palette res:// path the sky record references (its `palette_ref`), or
## the empty string if the record is missing/malformed/not-sky or carries no
## ref. The sky look resolves palette(hour) from THIS one source; a game whose
## palette record is absent falls back to day_night.gd's DEFAULT_KEYS, exactly
## as day_night.gd already does when res://data/sky/day_night.json is content-
## empty.
static func load_sky_palette_ref() -> String:
	if not FileAccess.file_exists(SKY_PATH):
		push_error("[look_data] missing sky record: %s" % SKY_PATH)
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SKY_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[look_data] %s did not parse as an object" % SKY_PATH)
		return ""
	var record: Dictionary = parsed
	if String(record.get("look_family", "")) != "sky":
		push_error("[look_data] %s is not a sky record" % SKY_PATH)
		return ""
	return String(record.get("palette_ref", ""))


## Bind a gouache params dict onto a ShaderMaterial's uniforms (the exact
## names gouache.gdshaderinc's gouache_wash() takes). Missing/malformed
## params (an empty dict from a failed load) leave the material on its
## shader's own defaults rather than crashing — the shader's defaults are
## the same numbers as the record, so a load failure degrades to "the old
## literals", not a broken look.
static func bind_gouache(mat: ShaderMaterial, params: Dictionary) -> void:
	if params.is_empty():
		return
	var palette: Dictionary = params.get("palette", {})
	for key in ["sand_floor", "sand_warm", "rock_high", "rock_steep"]:
		if palette.has(key):
			var c: Array = palette[key]
			mat.set_shader_parameter(key, Color(c[0], c[1], c[2]))
	var bands: Dictionary = params.get("bands", {})
	if bands.has("sand_to_warm"):
		var b: Array = bands["sand_to_warm"]
		mat.set_shader_parameter("band_sand_to_warm", Vector2(b[0], b[1]))
	if bands.has("warm_to_rock"):
		var b: Array = bands["warm_to_rock"]
		mat.set_shader_parameter("band_warm_to_rock", Vector2(b[0], b[1]))
	if bands.has("slope_to_steep"):
		var b: Array = bands["slope_to_steep"]
		mat.set_shader_parameter("band_slope_to_steep", Vector2(b[0], b[1]))
	var freqs: Dictionary = params.get("variation_freqs", {})
	if freqs.has("blotch"):
		mat.set_shader_parameter("freq_blotch", float(freqs["blotch"]))
	if freqs.has("grain"):
		mat.set_shader_parameter("freq_grain", float(freqs["grain"]))
	if params.has("blotch_amp"):
		mat.set_shader_parameter("blotch_amp", float(params["blotch_amp"]))
	if params.has("grain_mix"):
		var gm: Array = params["grain_mix"]
		mat.set_shader_parameter("grain_mix", Vector2(gm[0], gm[1]))
