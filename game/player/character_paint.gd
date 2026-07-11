class_name CharacterPaint
extends RefCounted
## Applies the painterly character shader to a glTF creature, one
## ShaderMaterial per surface carrying that surface's flat albedo as
## base_color. This restores the gouache depth that glTF export flattens
## out (see assets/blender/creatures/README.md). Call after the model is
## in the tree. Reusable for NPCs when they get real models.

const SHADER := preload("res://game/shaders/character_paint.gdshader")


## Apply the painterly shader to a glTF creature. An optional `palette` (a
## CHARACTER record's `body.palette`) tints the result: a `"base"` entry —
## an [r, g, b] array — overrides every surface's albedo, so one placeholder
## mesh can wear many colours (the cast's faces before real art lands). An
## empty palette keeps each surface's own flat albedo (the default look).
static func apply(model_root: Node, palette: Dictionary = {}) -> void:
	var override: Variant = _base_color(palette)
	for mi in _mesh_instances(model_root):
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(s)
			var base := Color(0.8, 0.8, 0.8)
			if src is BaseMaterial3D:
				base = src.albedo_color
			if override != null:
				base = override
			var mat := ShaderMaterial.new()
			mat.shader = SHADER
			mat.set_shader_parameter("base_color", base)
			mi.set_surface_override_material(s, mat)


## The palette's `base` tint as a Color, or null when unset/malformed (a bad
## palette is caught by the character validator; here we simply fall back to
## the mesh's own albedo, never a crash).
static func _base_color(palette: Dictionary) -> Variant:
	var base: Variant = palette.get("base")
	if base is Array and (base as Array).size() >= 3:
		return Color(float(base[0]), float(base[1]), float(base[2]))
	return null


static func _mesh_instances(node: Node, out: Array = []) -> Array:
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for c in node.get_children():
		_mesh_instances(c, out)
	return out
