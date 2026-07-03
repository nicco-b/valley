extends Node
## FocusThrottle (autoload): good-citizen behavior for the ambient machine.
## The game is meant to stay open on the Mac all day, so an unfocused
## window must sip power — but stay *watchable*: a glanceable living valley
## is the point, so nothing dissolves and rendering continues, just slower.
## Minimized (nobody can see it) throttles near-idle. Game time is
## wall-clock driven (GameClock), so throttling never slows the world.

const FPS_UNFOCUSED := 12  # visible but not the front app: watchable, cheap
const FPS_MINIMIZED := 4  # nobody's looking; near-idle
const FPS_FOCUSED := 0  # uncapped (vsync governs)

var _focused := true


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			_apply()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			_apply()


func _process(_delta: float) -> void:
	# Minimize/restore has no notification of its own; poll while unfocused
	# (a dozen cheap calls a second at the throttled rate).
	if not _focused:
		_apply()


func _apply() -> void:
	if _focused:
		Engine.max_fps = FPS_FOCUSED
		return
	var minimized := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	Engine.max_fps = FPS_MINIMIZED if minimized else FPS_UNFOCUSED
