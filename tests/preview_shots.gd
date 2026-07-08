extends Node
## M2 measurement + screenshot probe (rebased from the spike's
## viewer_shots): boots the valley, wears a Strata export through the
## REAL verb path (StrataLink._execute — the same door the TCP link
## uses), measures the cold wear, warm re-wears (the slider loop), every
## layer switch cold + cached, and the frames around each push (the
## hitch dial). Screenshots each layer, then leaves preview and shoots
## the restored streamed world. Run windowed so rendering is real:
##   PREVIEW_DIR=<export> SHOT_DIR=<out> godot --path . res://tests/preview_shots.tscn
## Prints [preview_shots] lines; quits by itself.

const LAYERS := ["shaded", "moisture", "temperature", "slope", "biome"]

var _w: Node
var _t := 0
var _dir := ""
var _out := ""
var _cam: Camera3D
var _rig := OrbitRig.new()
var _step := 0
var _last_us := 0
var _dts: PackedFloat32Array = []


func _ready() -> void:
	_dir = OS.get_environment("PREVIEW_DIR")
	_out = OS.get_environment("SHOT_DIR")
	if _dir.is_empty() or _out.is_empty():
		push_error("[preview_shots] PREVIEW_DIR and SHOT_DIR env required")
		get_tree().quit(1)
		return
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _process(_d: float) -> void:
	_t += 1
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_dts.append((now - _last_us) / 1000.0)
	_last_us = now
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
	if _t == 240:
		GameClock.advance_hours(fposmod(12.0 - GameClock.hours, 24.0))  # noon light
		# The shared orbit framing (OrbitRig, since the spike branched):
		# the whole tile in one steady look — the Metal view's posture.
		_cam = Camera3D.new()
		add_child(_cam)
		_rig.frame_tile()
		_rig.elevation = 0.85
		_rig.apply(_cam)
		_cam.make_current()
		# Data views read NUMBERS: the atmosphere's depth wash stays with
		# the shaded world, not the drape (the M3 atmosphere policy).
		var env := _w.find_child("WorldEnvironment", true, false) as WorldEnvironment
		if env != null and env.environment != null:
			env.environment.fog_enabled = false
			env.environment.volumetric_fog_enabled = false
	if _t == 300:
		# Cold wear (includes the one-time mesh build), then the slider
		# loop: three warm re-wears, each timed at the verb.
		print("[preview_shots] cold: ", _verb("preview_mesh " + _dir))
		_dts.clear()
	if _t >= 330 and _t < 420 and (_t - 330) % 30 == 0:
		print("[preview_shots] warm: ", _verb("preview_mesh " + _dir))
	if _t == 420:
		var s := _dts.duplicate()
		s.sort()
		print("[preview_shots] frames across 3 warm wears: p50=%.1f max=%.1f ms (%d frames)"
			% [s[s.size() / 2], s[s.size() - 1], s.size()])
	# Layer pass 1 (cold texture loads) with a screenshot per layer…
	if _t >= 450 and (_t - 450) % 30 == 0 and _step < LAYERS.size():
		print("[preview_shots] ", _verb("view_layer " + LAYERS[_step]))
		_step += 1
	if _t >= 470 and (_t - 470) % 30 == 0 and (_t - 470) / 30 < LAYERS.size():
		var layer: String = LAYERS[(_t - 470) / 30]
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out.path_join("eng_%s.png" % layer))
		print("[preview_shots] shot ", layer)
	# …pass 2 rides the cache (the perception-threshold number).
	if _t >= 470 + 30 * LAYERS.size() and _t < 470 + 30 * LAYERS.size() + LAYERS.size():
		print("[preview_shots] cached: ",
			_verb("view_layer " + LAYERS[_t - 470 - 30 * LAYERS.size()]))
	if _t == 480 + 30 * LAYERS.size():
		print("[preview_shots] ", _verb("preview_mesh off"))
	if _t == 540 + 30 * LAYERS.size():
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out.path_join("eng_restored.png"))
		print("[preview_shots] shot restored world")
		get_tree().quit()


## One verb through the link's own executor, timed end-to-end.
func _verb(line: String) -> String:
	var t0 := Time.get_ticks_usec()
	var reply: String = StrataLink._execute(line)
	return "%s verb-total %.1fms" % [reply, (Time.get_ticks_usec() - t0) / 1000.0]
