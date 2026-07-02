extends Node
## Settings (autoload): user preferences, persisted to user://settings.json
## (separate from save games — preferences belong to the player, not the
## playthrough). Applied on load and on change.

const PATH := "user://settings.json"

var master_volume := 0.8
var mouse_sensitivity := 1.0
var fullscreen := false


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			master_volume = float(data.get("master_volume", master_volume))
			mouse_sensitivity = float(data.get("mouse_sensitivity", mouse_sensitivity))
			fullscreen = bool(data.get("fullscreen", fullscreen))
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED
		)


func save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"master_volume": master_volume,
		"mouse_sensitivity": mouse_sensitivity,
		"fullscreen": fullscreen,
	}, "\t"))
