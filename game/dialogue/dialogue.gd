extends CanvasLayer
## Dialogue (autoload): a records-native conversation engine. Dialogue
## lives in data/dialogue/*.json as node graphs; conditions read
## WorldState, effects write it. UI is a bottom panel with numbered
## choices (click or 1-9). Esc leaves the conversation.
##
## Node: {speaker, text, effects: [{set|inc: key}], choices: [
##   {text, next, if: {flag|not_flag|gte}} ]}
## Start selection: first entry of "start" whose "if" passes.

signal ended

const INK := Color(0.30, 0.17, 0.16)
const CREAM := Color(1.0, 0.96, 0.9)
const TEAL := Color(0.62, 0.82, 0.8)

var active := false

var _defs: Dictionary = {}
var _current: Dictionary = {}
var _player: Node = null
var _panel: PanelContainer
var _speaker: Label
var _text: Label
var _choices: VBoxContainer


func _ready() -> void:
	layer = 15
	visible = false
	var records := Records.load_dir("res://data/dialogue", {
		"id": TYPE_STRING, "start": TYPE_ARRAY, "nodes": TYPE_DICTIONARY,
	})
	for key in records:
		_defs[records[key].id] = records[key]
	_build_ui()


func has_dialogue(id: String) -> bool:
	return _defs.has(id)


func start(id: String, _by: Node = null) -> void:
	if active or not _defs.has(id):
		return
	_current = _defs[id]
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.set_physics_process(false)
		_player.set_process_unhandled_input(false)
	active = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	HUD.prompt("")
	_show(_pick_start())


func _pick_start() -> String:
	for entry in _current.start:
		if _eval(entry.get("if", {})):
			return entry.node
	return _current.start.back().node


func _eval(c: Dictionary) -> bool:
	if c.is_empty():
		return true
	if c.has("flag"):
		return WorldState.has_flag(c.flag)
	if c.has("not_flag"):
		return not WorldState.has_flag(c.not_flag)
	if c.has("gte"):
		return int(WorldState.get_value(c.gte[0], 0)) >= int(c.gte[1])
	return true


func _apply(effects: Array) -> void:
	for e in effects:
		if e.has("set"):
			WorldState.set_flag(e.set)
		elif e.has("inc"):
			WorldState.increment(e.inc)


func _show(nid: String) -> void:
	if nid.is_empty() or not _current.nodes.has(nid):
		_end()
		return
	var node: Dictionary = _current.nodes[nid]
	_apply(node.get("effects", []))
	_speaker.text = node.get("speaker", "")
	_speaker.visible = not _speaker.text.is_empty()
	_text.text = node.text
	for child in _choices.get_children():
		child.queue_free()
	var i := 0
	for ch in node.get("choices", []):
		if not _eval(ch.get("if", {})):
			continue
		i += 1
		var next: String = ch.get("next", "")
		var btn := Button.new()
		btn.text = "%d.  %s" % [i, ch.text]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.flat = true
		btn.add_theme_color_override("font_color", CREAM)
		btn.add_theme_color_override("font_hover_color", TEAL)
		btn.pressed.connect(_show.bind(next))
		_choices.add_child(btn)
	if i == 0:
		var btn := Button.new()
		btn.text = "1.  [Leave]"
		btn.flat = true
		btn.add_theme_color_override("font_color", CREAM)
		btn.pressed.connect(_end)
		_choices.add_child(btn)
	# Controller/keyboard navigation starts on the first choice.
	if _choices.get_child_count() > 0:
		(_choices.get_child(0) as Button).grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("ui_cancel"):
		_end()
	elif event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.physical_keycode - KEY_1
		var buttons := _choices.get_children()
		if idx >= 0 and idx < buttons.size():
			buttons[idx].pressed.emit()


func _end() -> void:
	if not active:
		return
	active = false
	visible = false
	if _player:
		_player.set_physics_process(true)
		_player.set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ended.emit()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.11, 0.92)
	style.border_color = Color(0.45, 0.32, 0.24)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", style)
	margin.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 14)
	_speaker.add_theme_color_override("font_color", TEAL)
	vbox.add_child(_speaker)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 17)
	_text.add_theme_color_override("font_color", CREAM)
	vbox.add_child(_text)

	_choices = VBoxContainer.new()
	vbox.add_child(_choices)
