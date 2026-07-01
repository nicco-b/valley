extends Node
## Crossfades ambient beds against the GameClock: wind by day, the night
## layer rising through dusk (19:00-21:30) and receding at dawn (5:00-7:00).

@onready var _wind: AudioStreamPlayer = $Wind
@onready var _night: AudioStreamPlayer = $Night


func _process(_delta: float) -> void:
	var h: float = GameClock.hours
	var nightness := clampf(
		smoothstep(19.0, 21.5, h) + 1.0 - smoothstep(5.0, 7.0, h), 0.0, 1.0
	)
	_wind.volume_db = linear_to_db(lerpf(0.5, 0.18, nightness))
	_night.volume_db = linear_to_db(maxf(nightness * 0.45, 0.0001))
