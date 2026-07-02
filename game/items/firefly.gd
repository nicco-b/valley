class_name WildFirefly
extends Interactable
## A catchable light, drifting near the ground at night. Warm-white
## leaning green, each its own shade. E to catch.

var color := Color(0.95, 1.0, 0.8)

var _drift := Vector3.ZERO
var _retarget := 0.0
var _phase := randf() * TAU


static func random_color() -> Color:
	var lean := randf()  # 0 = warm white, 1 = green
	var c := Color(1.0, 0.97, 0.80).lerp(Color(0.86, 1.0, 0.76), lean)
	return c.lightened(randf() * 0.08)


func _ready() -> void:
	super()
	prompt = "Catch"
	color = random_color()
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = randf_range(1.5, 3.0)
		_drift = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * 0.5
	global_position += _drift * delta
	global_position.y += sin(Time.get_ticks_msec() * 0.001 * 2.1 + _phase) * 0.12 * delta * 8.0


func interact(by: Node) -> void:
	super(by)
	Items.add("firefly")
	WorldState.increment("player.items_taken")
	WorldState.set_flag("player.caught_firefly")
	HUD.notify("+ Firefly")
	queue_free()
