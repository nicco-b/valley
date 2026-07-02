extends CanvasLayer
## Pause menu (autoload). Esc pauses the world (tree pause); panel offers
## resume, settings, save & quit. Esc in the map closes the map; god mode
## keeps its own Esc behavior.

const INK := Color(0.30, 0.17, 0.16)
const CREAM := Color(0.96, 0.93, 0.865)

var paused := false

var _volume: HSlider
var _sensitivity: HSlider
var _fullscreen: CheckButton


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
	if GodMode.active:
		return  # god mode owns Esc while flying
	if MapScreen.active:
		MapScreen._close()
		return
	toggle()


func toggle() -> void:
	paused = not paused
	get_tree().paused = paused
	visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.06, 0.08, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.border_color = Color(0.45, 0.32, 0.24)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(340, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Valley"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", INK)
	vbox.add_child(title)

	vbox.add_child(_button("Resume", toggle))

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
	_fullscreen.add_theme_color_override("font_color", INK)
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
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", INK)
	return l


func _slider(vmin: float, vmax: float, value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = 0.05
	s.value = value
	s.value_changed.connect(on_change)
	return s
