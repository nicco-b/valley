extends Node
## Global terrain height function, autoloaded as Terrain. Deterministic
## (fixed seeds): every run and every cell samples the same world.
## Terrain meshes, collision, and content placement all read from here.
## Hand-authored terrain will later override/blend with this base.

# Flattened disks so authored content sits on level ground:
# [center x, center z, flat radius, feather distance]
const FLATTENS := [
	[0.0, 0.0, 60.0, 70.0],  # spawn area & starter rocks
	[150.0, -900.0, 35.0, 60.0],  # shrine
]

var _hills := FastNoiseLite.new()
var _dunes := FastNoiseLite.new()


func _ready() -> void:
	_hills.seed = 7
	_hills.frequency = 0.0025
	_hills.fractal_octaves = 4
	_dunes.seed = 40
	_dunes.frequency = 0.03


func height(x: float, z: float) -> float:
	var h := _hills.get_noise_2d(x, z) * 18.0 + _dunes.get_noise_2d(x, z) * 0.6
	for f in FLATTENS:
		var d := Vector2(x - f[0], z - f[1]).length()
		h *= smoothstep(f[2], f[2] + f[3], d)
	return h
