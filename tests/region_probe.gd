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
	"rim": {  # the landmark law: mesa across the sea from the valley rim
		# Focus parked deeper than the camera so the far-terrain LOD
		# recenters (>600m from its boot anchor) and covers the mesa.
		"focus": Vector3(440, 0, -1000),
		"cam": Vector3(440, 14.0, -660), "aim": Vector3(1200, 160, -3000)},
	"causeway": {  # the walk to the city: strand, sea both sides
		"focus": Vector3(700, 0, -2150),
		"cam": Vector3(700, 12.0, -2150), "aim": Vector3(1200, 140, -3000)},
	"mesa": {  # close portrait: does the tiered flank read?
		"focus": Vector3(1150, 0, -2650),
		"cam": Vector3(1150, 25.0, -2680), "aim": Vector3(1200, 120, -3000)},
	"aerial": {  # overview of the island layout, high and steep
		"focus": Vector3(400, 3000, -1500),
		"cam": Vector3(400, 2800, -1500), "aim": Vector3(1200, 0, -3000),
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
