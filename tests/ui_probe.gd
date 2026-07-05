extends Node
## UI probe (dev-only): boots windowed, kills FocusThrottle, screenshots
## the title screen, then the world with the pause menu, then the journal.
## Saves /tmp/ui_title.png, /tmp/ui_pause.png, /tmp/ui_journal.png, quits.
## Run: godot res://tests/ui_probe.tscn  (with a ~90s watchdog).

var _t := 0
var _title: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # pause menu pauses the tree
	_title = load("res://game/ui/title.tscn").instantiate()
	add_child(_title)


func _process(_d: float) -> void:
	_t += 1
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
	elif _t == 30:
		get_viewport().get_texture().get_image().save_png("/tmp/ui_title.png")
		_title.queue_free()
		add_child(load("res://game/world/valley.tscn").instantiate())
	elif _t == 90:
		GameClock.hours = 14.0
		GameClock.time_scale = 0.0
		Weather.force_kind("calm")
		PauseMenu.toggle()
	elif _t == 110:
		get_viewport().get_texture().get_image().save_png("/tmp/ui_pause.png")
		PauseMenu.toggle()
		Journal.visible = true
		Journal._refresh()
	elif _t == 130:
		get_viewport().get_texture().get_image().save_png("/tmp/ui_journal.png")
		print("SHOTS WRITTEN")
		get_tree().quit()
