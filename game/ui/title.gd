extends Control
## Title screen — the boot scene. Continue (if a journey exists), New
## Journey (with an are-you-sure second press), Quit.

const INK := Color(0.30, 0.17, 0.16)
const WORLD_SCENE := "res://game/world/valley.tscn"

var _new_button: Button
var _confirm_armed := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.10, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var glow := ColorRect.new()  # dusk band on the horizon line
	glow.color = Color(0.93, 0.62, 0.66, 0.14)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_top = 380.0
	add_child(glow)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "V A L L E Y"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.96, 0.93, 0.865))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "a working title"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.93, 0.62, 0.66))
	vbox.add_child(sub)

	vbox.add_child(_spacer(18))

	var has_save := FileAccess.file_exists(SaveGame.PATH)
	if has_save:
		var cont := Button.new()
		cont.text = "Continue"
		cont.pressed.connect(func() -> void:
			get_tree().change_scene_to_file(WORLD_SCENE))
		vbox.add_child(cont)

	_new_button = Button.new()
	_new_button.text = "New Journey"
	_new_button.pressed.connect(_on_new_journey.bind(has_save))
	vbox.add_child(_new_button)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit)


func _on_new_journey(has_save: bool) -> void:
	if has_save and not _confirm_armed:
		_confirm_armed = true
		_new_button.text = "Erase the old journey?"
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))
	get_tree().change_scene_to_file(WORLD_SCENE)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
