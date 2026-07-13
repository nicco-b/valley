class_name BodyData
extends RefCounted
## Body records (FW4): a family-generic envelope over a character's
## physical form — {body_family, mesh, skeleton, animations, look_hooks}.
## Before this record existed the mesh binding was TRAPPED inside the
## scene layer: player.tscn and villager_body.tscn each carried an
## ext_resource pointing straight at biped_fox.glb, invisible to the
## record system and dead the moment a scaffolded game forked. A body
## record lifts that binding into data — the scene now asks a record for
## its mesh (BodyLoader) instead of embedding one.
##
## `body_family` selects HOW the body renders, exactly as `look_family`
## selects a shader pipeline in LookData. `skinned_glb` is family #1 (a
## Godot PackedScene with an AnimationPlayer + Skeleton3D, instanced into
## the tree); the fox is INSTANCE #1 of that family, never the schema. A
## game ships its own body by shipping its own record — a different mesh,
## or one day a different family entirely. An unknown family, or an
## unknown FIELD, fails LOUDLY (push_error + {}), never a silent fallback.
##
## FUTURE SEAM (do NOT build here): a native Wash skinned-mesh renderer is
## a separate rung. When it lands it is a NEW body_family (e.g.
## "wash_skinned") that reads the same `mesh`/`skeleton`/`animations`
## fields this schema already declares, dispatched from load() the way
## LookData dispatches look_family — the record shape is ready for it; the
## renderer is not this rung's work. See docs/BODY_RECORDS.md.

## Every field a body record may carry. A field outside this set fails the
## load LOUDLY — a typo or a foreign field is a bug, not a silent no-op
## (the family-generic discipline: the schema is closed, the family is
## open). `note` is the human comment every record in this repo carries.
const KNOWN_FIELDS := [
	"format", "body_family", "note",
	"mesh", "skeleton", "animations", "look_hooks",
]

## The fields that MUST be present. skeleton/animations/look_hooks are
## OPTIONAL — a minimal body is just a family and a mesh — but when
## present they must be dictionaries (checked below).
const REQUIRED_FIELDS := ["format", "body_family", "mesh"]

## The families this loader knows how to render. skinned_glb is #1; a
## native-Wash family joins here alongside its renderer (the future seam).
const KNOWN_FAMILIES := ["skinned_glb"]


## Load and validate a body record at `path`. Returns the record dict on
## success, or {} (with a push_error) on: missing file, bad JSON, a
## missing/mistyped required field, an unknown field, an unknown family,
## or a mistyped optional sub-dict. Callers must treat {} as "something is
## wrong, look at the log", NEVER as "use defaults" — a body with no mesh
## is not a body.
static func load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[body_data] missing body record: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[body_data] %s did not parse as an object" % path)
		return {}
	var record: Dictionary = parsed
	# Unknown fields fail LOUDLY — a foreign or misspelled key is a bug.
	for field in record:
		if not KNOWN_FIELDS.has(field):
			push_error("[body_data] %s carries unknown field '%s' (known: %s)" %
					[path, field, ", ".join(KNOWN_FIELDS)])
			return {}
	for field in REQUIRED_FIELDS:
		if not record.has(field):
			push_error("[body_data] %s missing required field '%s'" % [path, field])
			return {}
	if typeof(record["mesh"]) != TYPE_STRING or String(record["mesh"]).is_empty():
		push_error("[body_data] %s field 'mesh' must be a non-empty string" % path)
		return {}
	var family := String(record.get("body_family", ""))
	if not KNOWN_FAMILIES.has(family):
		push_error("[body_data] %s declares body_family '%s', known: %s" %
				[path, family, ", ".join(KNOWN_FAMILIES)])
		return {}
	# Optional sub-dicts, when present, must be objects — a scalar where a
	# block is expected is the same class of bug as an unknown field.
	for field in ["skeleton", "animations", "look_hooks"]:
		if record.has(field) and typeof(record[field]) != TYPE_DICTIONARY:
			push_error("[body_data] %s field '%s' must be an object when present" %
					[path, field])
			return {}
	return record


## Instantiate the body's mesh as a Node3D named "Model", ready to parent
## under a scene's Body node — the one live consumption of a body record
## today (skinned_glb: the mesh is a PackedScene carrying its own
## AnimationPlayer + Skeleton3D). Returns null (with a push_error) on a
## record that failed load() or a mesh that will not load, so the caller
## degrades to "no model, look at the log" rather than crashing. The node
## is named "Model" so $Body/Model resolves exactly as the old embedded
## instance did — behaviour-identical, the binding just came from data.
static func instantiate_model(record: Dictionary) -> Node3D:
	if record.is_empty():
		return null
	var mesh_path := String(record.get("mesh", ""))
	var scene := ResourceLoader.load(mesh_path) as PackedScene
	if scene == null:
		push_error("[body_data] mesh did not load as a PackedScene: %s" % mesh_path)
		return null
	var model := scene.instantiate() as Node3D
	if model == null:
		push_error("[body_data] mesh instanced as a non-Node3D: %s" % mesh_path)
		return null
	model.name = "Model"
	return model
