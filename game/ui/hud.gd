extends CanvasLayer
## HUD (autoload): the one place on-screen text goes through.
## - prompt(text): interaction hint, bottom center ("" hides)
## - say(speaker, text): spoken/examined line, fades after a few seconds
## - notify(text): small transient notice, top center

const CREAM := UITheme.CREAM
const TEAL := UITheme.TEAL
const SHADOW := UITheme.SHADOW

var _root: Control
var _prompt: Label
var _speaker: Label
var _line: Label
var _notice: Label
var _satchel: Label
var _say_token := 0
var _notify_token := 0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply(_root)
	add_child(_root)
	# Full-rect labels + text alignment: layout that cannot land off-screen.
	_prompt = _make_label(17, CREAM, VERTICAL_ALIGNMENT_BOTTOM, -70.0)
	_speaker = _make_label(16, TEAL, VERTICAL_ALIGNMENT_BOTTOM, -170.0)
	_line = _make_label(19, CREAM, VERTICAL_ALIGNMENT_BOTTOM, -140.0)
	_notice = _make_label(15, CREAM, VERTICAL_ALIGNMENT_TOP, 14.0)
	_satchel = _make_label(16, CREAM, VERTICAL_ALIGNMENT_TOP, 48.0)
	WorldState.changed.connect(_on_state_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		_satchel.visible = not _satchel.visible
		if _satchel.visible:
			_refresh_satchel()


func _on_state_changed(key: String, _value: Variant) -> void:
	if key == "player.inventory" and _satchel.visible:
		_refresh_satchel()


func _refresh_satchel() -> void:
	var inv: Dictionary = Items.inventory()
	if inv.is_empty():
		_satchel.text = "— satchel —\n(empty)"
		return
	var lines: Array[String] = ["— satchel —"]
	for id in inv:
		lines.append("%s × %d" % [Items.display_name(id), inv[id]])
	_satchel.text = "\n".join(lines)


func prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = not text.is_empty()


func say(speaker: String, text: String, seconds := 4.5) -> void:
	_say_token += 1
	var token := _say_token
	_speaker.text = speaker
	_speaker.visible = not speaker.is_empty()
	_line.text = text
	_line.visible = true
	await get_tree().create_timer(seconds).timeout
	if token == _say_token:
		_speaker.visible = false
		_line.visible = false


func notify(text: String, seconds := 2.5) -> void:
	_notify_token += 1
	var token := _notify_token
	_notice.text = text
	_notice.visible = true
	await get_tree().create_timer(seconds).timeout
	if token == _notify_token:
		_notice.visible = false


func _make_label(size: int, color: Color, valign: int, edge_offset: float) -> Label:
	var label := Label.new()
	label.visible = false
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = valign as VerticalAlignment
	if valign == VERTICAL_ALIGNMENT_BOTTOM:
		label.offset_bottom = edge_offset
	else:
		label.offset_top = edge_offset
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", SHADOW)
	label.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(label)
	return label
