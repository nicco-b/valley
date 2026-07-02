extends CanvasLayer
## HUD (autoload): the one place on-screen text goes through.
## - prompt(text): interaction hint, bottom center ("" hides)
## - say(speaker, text): spoken/examined line, fades after a few seconds
## - notify(text): small transient notice, top center

const CREAM := Color(1.0, 0.96, 0.9)
const TEAL := Color(0.62, 0.82, 0.8)
const SHADOW := Color(0, 0, 0, 0.7)

var _prompt: Label
var _speaker: Label
var _line: Label
var _notice: Label
var _say_token := 0
var _notify_token := 0


func _ready() -> void:
	layer = 5
	_prompt = _make_label(15, CREAM)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position.y -= 70.0
	_speaker = _make_label(14, TEAL)
	_speaker.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speaker.position.y -= 165.0
	_line = _make_label(17, CREAM)
	_line.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_line.position.y -= 140.0
	_notice = _make_label(13, CREAM)
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.position.y += 14.0


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


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.visible = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", SHADOW)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label
