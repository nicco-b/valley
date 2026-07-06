extends CanvasLayer
## The Campfire (shell UI): the menu (autoload). Esc/Start opens it; the
## WORLD KEEPS RUNNING underneath (no tree pause — a 1:1 world doesn't
## stop for a menu; only the player's body freezes, like the map). Panel
## offers resume, settings, save & quit. Esc in the map closes the map;
## god mode keeps its own Esc behavior. Wears UITheme; Resume grabs
## focus on open so the gamepad can walk the menu.

var paused := false

var _root: Control
var _volume: HSlider
var _sensitivity: HSlider
var _fullscreen: CheckButton
var _resume: Button


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if get_tree().get_first_node_in_group("player") == null:
		return  # title screen
	if Dialogue.active:
		return  # Esc ends the conversation instead
	if Journal.visible:
		return  # Esc closes the journal instead
	if GodMode.active:
		return  # god mode owns Esc while flying
	if MapScreen.active:
		MapScreen._close()
		return
	toggle()


func toggle() -> void:
	paused = not paused
	visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	# The world lives on; only the player's body holds still under the
	# menu (same treatment the map gives it).
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.set_physics_process(not paused)
		player.set_process_unhandled_input(not paused)
	if paused:
		_resume.grab_focus.call_deferred()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.apply(_root)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = UITheme.DUSK_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(360, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Valley"
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_resume = _button("Resume", toggle)
	vbox.add_child(_resume)

	vbox.add_child(_label("Volume"))
	_volume = _slider(0.0, 1.0, Settings.master_volume, func(v: float) -> void:
		Settings.master_volume = v
		Settings.apply()
		Settings.save())
	vbox.add_child(_volume)

	vbox.add_child(_label("Mouse sensitivity"))
	_sensitivity = _slider(0.3, 2.0, Settings.mouse_sensitivity, func(v: float) -> void:
		Settings.mouse_sensitivity = v
		Settings.save())
	vbox.add_child(_sensitivity)

	_fullscreen = CheckButton.new()
	_fullscreen.text = "Fullscreen"
	_fullscreen.button_pressed = Settings.fullscreen
	_fullscreen.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply()
		Settings.save())
	vbox.add_child(_fullscreen)

	vbox.add_child(_button("Save & Quit", func() -> void:
		SaveGame.save_game()
		get_tree().quit()))


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "SubtleLabel"
	return l


func _slider(vmin: float, vmax: float, value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = 0.05
	s.value = value
	s.value_changed.connect(on_change)
	return s
