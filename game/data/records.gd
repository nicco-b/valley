extends Node
## Records (autoload): the one validated path for loading data/*.json.
## Catches missing fields and wrong types at load time with a clear
## message, instead of mysterious nulls at runtime.

## Parse a JSON file; null (with an error) on failure.
func load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("[records] missing or empty: " + path)
		return null
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("[records] invalid JSON: " + path)
	return parsed


## Load every .json in a directory -> {basename: record}, dropping records
## that fail validation. `required` maps field name -> Variant.Type.
func load_dir(dir_path: String, required: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path := dir_path + "/" + f
		var rec = load_json(path)
		if rec is Dictionary and validate(rec, required, path):
			out[f.trim_suffix(".json")] = rec
	return out


## Check required fields and types. JSON numbers arrive as float; ints
## are accepted where floats are required.
func validate(record: Dictionary, required: Dictionary, context: String) -> bool:
	for field in required:
		if not record.has(field):
			push_error("[records] %s: missing field '%s'" % [context, field])
			return false
		var want: int = required[field]
		var got := typeof(record[field])
		if got != want and not (want == TYPE_FLOAT and got == TYPE_INT):
			push_error("[records] %s: field '%s' should be %s, got %s" % [
				context, field, type_string(want), type_string(got)
			])
			return false
	return true
