extends CanvasLayer
## Journal (autoload). Quests are declarative records (data/quests/):
## titled steps whose done-ness is a Conditions check over WorldState —
## no quest state machine, no extra save data. The journal notices newly
## completed steps (via WorldState.changed), notifies once (seen-flags),
## and renders active/completed quests on J.

var _quests: Array = []  # records, load order
var _text: RichTextLabel


func _ready() -> void:
	layer = 12
	visible = false
	var records := Records.load_dir("res://data/quests", {
		"id": TYPE_STRING, "title": TYPE_STRING, "steps": TYPE_ARRAY,
	})
	var keys := records.keys()
	keys.sort()
	for k in keys:
		_quests.append(records[k])
	WorldState.changed.connect(_on_state_changed)
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal"):
		if get_tree().get_first_node_in_group("player") == null:
			return
		visible = not visible
		if visible:
			_refresh()
	elif visible and event.is_action_pressed("ui_cancel"):
		visible = false


func step_done(step: Dictionary) -> bool:
	return Conditions.eval(step.done_if)


func quest_done(q: Dictionary) -> bool:
	for step in q.steps:
		if not step_done(step):
			return false
	return true


## Latched activation: once a quest's start_if has passed, it stays
## started — story-seeds are triggered by transient sim states (a drought,
## a bloom) and must not vanish from the journal when the state passes.
func quest_started(q: Dictionary) -> bool:
	var key := "journal.%s.started" % q.id
	if WorldState.has_flag(key):
		return true
	if Conditions.eval(q.get("start_if", {})):
		WorldState.set_flag(key)
		return true
	return false


func quest_active(q: Dictionary) -> bool:
	return quest_started(q) and not quest_done(q)


## Notify (once) when a step or quest completes.
func _on_state_changed(_key: String, _value: Variant) -> void:
	for q in _quests:
		if not quest_started(q):
			continue
		for step in q.steps:
			var seen := "journal.%s.%s.seen" % [q.id, step.id]
			if step_done(step) and not WorldState.has_flag(seen):
				WorldState.set_flag(seen)
				HUD.notify("journal — %s ✓" % step.text)
		var qseen := "journal.%s.done.seen" % q.id
		if quest_done(q) and not WorldState.has_flag(qseen):
			WorldState.set_flag(qseen)
			HUD.notify("journal — “%s” complete" % q.title)
	if visible:
		_refresh()


func _refresh() -> void:
	var lines: Array[String] = []
	var any_active := false
	for q in _quests:
		if quest_active(q):
			any_active = true
			lines.append("[b]%s[/b]" % q.title)
			for step in q.steps:
				lines.append("   %s %s" % ["✓" if step_done(step) else "○", step.text])
			lines.append("")
	if not any_active:
		lines.append("[i]Nothing pressing. The valley keeps its own time.[/i]")
		lines.append("")
	var done_titles: Array[String] = []
	for q in _quests:
		if quest_started(q) and quest_done(q):
			done_titles.append(q.title)
	if not done_titles.is_empty():
		lines.append("[color=#8a7a6a][b]Remembered[/b][/color]")
		for t in done_titles:
			lines.append("[color=#8a7a6a]   ✓ %s[/color]" % t)
		lines.append("")
	lines.append("[b]Ways[/b]")
	for def in Skills.defs():
		var lvl: int = Skills.level(def.id)
		var dots := ""
		var filled := int(round(Skills.progress(def) * 8.0))
		for i in 8:
			dots += "●" if i < filled else "○"
		lines.append("   %-10s %-4s %s" % [def.name, Skills.NUMERALS[lvl], dots])
	_text.text = "\n".join(lines)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply(root)
	add_child(root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(440, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Journal"
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(440, 120)
	vbox.add_child(_text)
