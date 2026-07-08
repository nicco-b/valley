extends Node
## Crossfades ambient beds against the GameClock: wind by day, the night
## layer rising through dusk (19:00-21:30) and receding at dawn (5:00-7:00).

@onready var _wind: AudioStreamPlayer = $Wind
@onready var _night: AudioStreamPlayer = $Night


func _process(_delta: float) -> void:
	var h: float = GameClock.solar_hours()  # dusk tracks the seasonal sunset
	var nightness := clampf(
		smoothstep(19.0, 21.5, h) + 1.0 - smoothstep(5.0, 7.0, h), 0.0, 1.0
	)
	# The wind you hear is the wind the trees feel (Weather.wind).
	var gusting := 0.35 + 1.1 * Weather.wind
	# Inside a pocket interior the beds duck to a murmur through the wall
	# (the Threshold's presentation gate; the interior's OWN bed is I3's
	# rung). You still hear the gale gated — and it is still blowing.
	var duck := 0.08 if Interiors.inside else 1.0
	_wind.volume_db = linear_to_db(clampf(lerpf(0.5, 0.18, nightness) * gusting * duck, 0.0001, 1.0))
	# Kept deliberately low — night sound should be felt, not noticed.
	_night.volume_db = linear_to_db(maxf(nightness * 0.16 * (1.0 - Weather.storminess * 0.7) * duck, 0.0001))
