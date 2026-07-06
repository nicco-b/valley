extends Node
## Biome-pen probe (dev-only, the Toolkit): paints a biome patch the way
## the map pen does (Terrain.paint_biome_index) over the valley floor,
## commits (rescatter), and screenshots the retinted ground — plus a
## before/after biome_at readout. Movie Maker + minimized.
##   godot --path . --write-movie /tmp/x.avi --fixed-fps 15 \
##     res://tests/biome_pen_probe.tscn

const SPOT := Vector2(60, -300)  # valley floor near the pond
const PAINT_INDEX := 2  # placeholder dune_desert (sandy, flora-thin)

var _w: Node
var _t := 0


func _ready() -> void:
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _process(_d: float) -> void:
	_t += 1
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	if _t == 20:
		GameClock.hours = 12.0
		GameClock.time_scale = 0.0
		Weather.force_kind("calm")
		var we: WorldEnvironment = _w.find_children("*", "WorldEnvironment", true, false)[0]
		we.environment.fog_enabled = false
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			pl.global_position = Vector3(SPOT.x, Terrain.height(SPOT.x, SPOT.y) + 2.0, SPOT.y)
	if _t == 200:
		var before := Terrain.biome_at(SPOT.x, SPOT.y)
		var rect := Terrain.paint_biome_index(SPOT.x, SPOT.y, 90.0, PAINT_INDEX)
		Terrain.commit_biome_paint(rect)
		var after := Terrain.biome_at(SPOT.x, SPOT.y)
		print("[biome_probe] biome_at %d -> %d (painted %d over %.0fm)" % [
			before, after, PAINT_INDEX, 90.0])
	if _t == 700:
		var cam := Camera3D.new()
		add_child(cam)
		cam.far = 4000.0
		cam.make_current()
		cam.global_position = Vector3(SPOT.x - 40, Terrain.height(SPOT.x, SPOT.y) + 30.0, SPOT.y + 40)
		cam.look_at(Vector3(SPOT.x, Terrain.height(SPOT.x, SPOT.y), SPOT.y))
	if _t == 720:
		get_viewport().get_texture().get_image().save_png("/tmp/biome_pen.png")
		print("SHOT WRITTEN /tmp/biome_pen.png")
		get_tree().quit()
