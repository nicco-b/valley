extends Node
## Region probe (dev-only, the Loom): boots the valley, kills
## FocusThrottle, teleports the focus to ONE vantage chosen by the
## REGION_SHOT env var (rim | barren | mesa | aerial), lets streaming
## and the far-terrain recenter settle, saves /tmp/region_<shot>.png,
## quits. One shot per run: multi-teleport runs starve on streaming
## churn. Run under Movie Maker so frames advance while unfocused:
##   REGION_SHOT=rim godot --path . --write-movie /tmp/x.avi \
##     --fixed-fps 15 res://tests/region_probe.tscn
# Vantages: focus (player park, off camera axis), cam, aim.
const SHOTS := {
	"rim": {  # the landmark law: mesa from the valley's plateau rim
		# Focus parked deeper than the camera: the far-terrain LOD only
		# recenters when the focus moves >600m from its boot anchor, and
		# the rim itself is too close — anchored at spawn, the far mesh
		# ends at z≈-3450 and clips the mesa (-3600).
		"focus": Vector3(440, 0, -1000),
		"cam": Vector3(440, 14.0, -660), "aim": Vector3(1400, 340, -3600)},
	"barren": {  # scale shot across the empty quarter
		"focus": Vector3(850, 0, -2340),
		"cam": Vector3(920, 20.0, -2420), "aim": Vector3(1400, 300, -3600)},
	"mesa": {  # close portrait: does the tiered flank read?
		"focus": Vector3(1330, 0, -2440),
		"cam": Vector3(1400, 30.0, -2500), "aim": Vector3(1400, 260, -3600)},
	"aerial": {  # overview of the island layout, high and steep
		"focus": Vector3(1000, 3000, -2600),
		"cam": Vector3(1000, 2800, -2600), "aim": Vector3(1400, 0, -3600),
		"absolute": true},
}

var _w: Node
var _t := 0
var _shot := "rim"


func _ready() -> void:
	var req := OS.get_environment("REGION_SHOT")
	if SHOTS.has(req):
		_shot = req
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _process(_d: float) -> void:
	_t += 1
	if _t % 60 == 0:
		print("[region_probe] frame ", _t)
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		# Movie Maker renders flat-out and never services the OS event
		# loop promptly — macOS beach-balls the window. Minimize it:
		# movie mode keeps rendering frames regardless, and the human
		# keeps their desktop.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var s: Dictionary = SHOTS[_shot]
	if _t == 20:
		GameClock.hours = 14.0
		GameClock.time_scale = 0.0
		Weather.state = "calm"
		print(Terrain.regions_summary())
		# Clear air for silhouette calibration: even calm fog (0.0008)
		# is ~91% extinction at 3km — a real landmark-law question, but
		# these shots need to see the shapes.
		var we: WorldEnvironment = _w.find_children("*", "WorldEnvironment", true, false)[0]
		we.environment.fog_enabled = false
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			var f: Vector3 = s.focus
			if not s.get("absolute", false):
				f.y = Terrain.height(f.x, f.z) + 2.0
			pl.global_position = f
	if _t == 780:
		var cam := Camera3D.new()
		add_child(cam)
		cam.far = 12000.0
		cam.make_current()
		var c: Vector3 = s.cam
		if not s.get("absolute", false):
			c.y += Terrain.height(c.x, c.z)
		cam.global_position = c
		cam.look_at(s.aim)
	if _t == 800:
		var path := "/tmp/region_%s.png" % _shot
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT WRITTEN " + path)
		get_tree().quit()
