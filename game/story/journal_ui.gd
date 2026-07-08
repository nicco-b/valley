extends CanvasLayer
## The Campfire — the minimal J screen (Q1 rung of DESIGN_QUESTS §8; the
## full memoir screen is B10). One screen, two truths:
##
##   Threads      active quests: the latched prose so far, in latch
##                order, each entry stamped with its day and season,
##                followed by the frontier's open objectives — text
##                only, geography embedded, no markers, no distances.
##   Remembered   resolved quests, all endings equal. Entries render
##                from the prose STORED IN THE LATCH, so the memoir
##                survives record updates verbatim (§10).
##
## Repeatable errands show their freshest cycle; older cycles fade into
## Remembered. Instanced and owned by the Story autoload — the journal
## is the Teller's page, not its own system.

var _text: RichTextLabel


func _ready() -> void:
	layer = 12
	visible = false
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal"):
		if get_tree().get_first_node_in_group("player") == null:
			return
		visible = not visible
		if visible:
			refresh()
	elif visible and event.is_action_pressed("ui_cancel"):
		visible = false


func refresh() -> void:
	var lines: Array[String] = []
	var any_active := false
	var remembered: Array[Dictionary] = []
	for qid: String in Story.quests:
		var q: Dictionary = Story.quests[qid]
		if not Story.started(qid):
			continue
		if Story.resolved(qid):
			remembered.append(q)
			continue
		any_active = true
		lines.append("[b]%s[/b]" % q.title)
		lines.append_array(_entries(q))
		for sid: String in Story.frontier(qid):
			for obj: Dictionary in _stage(q, sid).get("objectives", []):
				if not Story.objective_done(qid, sid, obj.id):
					lines.append("   ○ %s" % obj.text)
		lines.append("")
	if not any_active:
		lines.append("[i]Nothing pressing. The valley keeps its own time.[/i]")
		lines.append("")
	if not remembered.is_empty():
		lines.append("[color=#8a7a6a][b]Remembered[/b][/color]")
		for q: Dictionary in remembered:
			lines.append("[color=#8a7a6a][b]%s[/b][/color]" % q.title)
			for entry in _entries(q):
				lines.append("[color=#8a7a6a]%s[/color]" % entry)
		lines.append("")
	_text.text = "\n".join(lines)


## The memoir entries of a quest's freshest cycle, in latch order (day,
## then stage order), each from the prose sealed at latch time.
func _entries(q: Dictionary) -> Array[String]:
	var latched: Array[Dictionary] = []
	var order := 0
	for stage: Dictionary in q.stages:
		order += 1
		if not Story.reached(q.id, stage.id):
			continue
		var latch: Variant = WorldState.get_value(Story._latch_prefix(q) + String(stage.id))
		if latch is Dictionary:
			latched.append({"day": int((latch as Dictionary).get("day", 0)),
				"order": order, "latch": latch})
	latched.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.day < b.day if a.day != b.day else a.order < b.order)
	var out: Array[String] = []
	for row: Dictionary in latched:
		var latch: Dictionary = row.latch
		var prose := String(latch.get("prose", ""))
		if prose.is_empty():
			continue
		out.append("[color=#7a6a5a]Day %d, %s[/color]" % [
			int(latch.get("day", 0)), latch.get("season", "")])
		out.append(prose)
	return out


func _stage(q: Dictionary, stage_id: String) -> Dictionary:
	for stage: Dictionary in q.stages:
		if stage.id == stage_id:
			return stage
	return {}


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
	vbox.custom_minimum_size = Vector2(480, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Journal"
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 420)
	vbox.add_child(scroll)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_text)
