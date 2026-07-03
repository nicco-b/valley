class_name CharacterPaint
extends RefCounted
## Applies the painterly character shader to a glTF creature, one
## ShaderMaterial per surface carrying that surface's flat albedo as
## base_color. This restores the gouache depth that glTF export flattens
## out (see assets/blender/creatures/README.md). Call after the model is
## in the tree. Reusable for NPCs when they get real models.

const SHADER := preload("res://game/shaders/character_paint.gdshader")


static func apply(model_root: Node) -> void:
	for mi in _mesh_instances(model_root):
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(s)
			var base := Color(0.8, 0.8, 0.8)
			if src is BaseMaterial3D:
				base = src.albedo_color
			var mat := ShaderMaterial.new()
			mat.shader = SHADER
			mat.set_shader_parameter("base_color", base)
			mi.set_surface_override_material(s, mat)


static func _mesh_instances(node: Node, out: Array = []) -> Array:
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for c in node.get_children():
		_mesh_instances(c, out)
	return out
