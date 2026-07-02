extends Node
## Dev hot-reload (autoload). Polls painting source files once a second;
## when one changes on disk (a re-export from her painting app), the live
## texture is swapped everywhere it's used — flora materials and sprites —
## without restarting the game.

const WATCH_DIR := "res://assets/paintings"

var _mtimes: Dictionary = {}
var _accum := 0.0


func _ready() -> void:
	set_process(OS.is_debug_build())


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0:
		return
	_accum = 0.0
	var dir := DirAccess.open(WATCH_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not (f.ends_with(".png") or f.ends_with(".svg")):
			continue
		var path := WATCH_DIR + "/" + f
		var mtime := FileAccess.get_modified_time(ProjectSettings.globalize_path(path))
		if _mtimes.has(path) and _mtimes[path] != mtime:
			_reload(path)
		_mtimes[path] = mtime


func _reload(path: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)

	var ws := get_tree().get_first_node_in_group("world_streamer")
	if ws:
		for i in ws.FLORA.size():
			if ws.FLORA[i][0] == path:
				ws._flora_meshes[i].material.set_shader_parameter("albedo_tex", tex)
	for sp in get_tree().root.find_children("*", "Sprite3D", true, false):
		if sp.texture and sp.texture.resource_path.begins_with(path):
			sp.texture = tex
	print("[hotreload] ", path)
