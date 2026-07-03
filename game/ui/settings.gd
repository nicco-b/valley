extends Node
## Settings (autoload): user preferences, persisted to user://settings.json
## (separate from save games — preferences belong to the player, not the
## playthrough). Applied on load and on change.

const PATH := "user://settings.json"

var master_volume := 0.8
var mouse_sensitivity := 1.0
var fullscreen := false

## Real location, feeding GameClock's solar math (sunrise/sunset, season
## hemisphere). Defaults: mid-latitude, longitude guessed from the UTC
## offset (15° per hour); refined once by IP geolocation and cached.
## Placeholder: a settings-screen location picker replaces the IP lookup.
var latitude := 45.0
var longitude := 0.0
var location_set := false


func _ready() -> void:
	longitude = Time.get_time_zone_from_system().bias / 60.0 * 15.0
	if FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			master_volume = float(data.get("master_volume", master_volume))
			mouse_sensitivity = float(data.get("mouse_sensitivity", mouse_sensitivity))
			fullscreen = bool(data.get("fullscreen", fullscreen))
			latitude = float(data.get("latitude", latitude))
			longitude = float(data.get("longitude", longitude))
			location_set = bool(data.get("location_set", location_set))
	apply()
	GameClock.refresh_daylight()  # we load after GameClock; hand it the location
	if not location_set and DisplayServer.get_name() != "headless":
		_geolocate()


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
		"latitude": latitude,
		"longitude": longitude,
		"location_set": location_set,
	}, "\t"))


## One-shot IP geolocation so the valley's sun matches the player's sky.
## Best-effort: any failure leaves the timezone-guessed defaults in place
## and we simply try again next launch.
func _geolocate() -> void:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	req.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			req.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				return
			var data = JSON.parse_string(body.get_string_from_utf8())
			if data is Dictionary and data.has("latitude") and data.has("longitude"):
				latitude = float(data.latitude)
				longitude = float(data.longitude)
				location_set = true
				save()
				GameClock.refresh_daylight()
				print("[settings] located: %.1f°, %.1f° — sun aligned" % [latitude, longitude])
	)
	if req.request("https://ipapi.co/json/") != OK:
		req.queue_free()
